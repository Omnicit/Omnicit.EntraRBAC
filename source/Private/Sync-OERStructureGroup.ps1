function Sync-OERStructureGroup {
    <#
    .SYNOPSIS
    Reconciles one groups[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single group entry from the structure document. It is called by
    the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult records
    describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key: an existing group is matched and updated by it. Renaming through
    the document is not possible -- changing displayName creates a new group and leaves the old one
    in place, unreported (Set-OERGroup has no -NewDisplayName parameter at all).

    Processing order within a single group (the PIM chicken-and-egg ordering):
    1. Create the group when absent, or diff and update mutable properties (Description, MailNickname,
       and MembershipRule/MembershipRuleProcessingState when the live group is already dynamic) when it
       already exists. Two properties
       are Graph-immutable once the group is created -- isAssignableToRole ("can only be set while
       creating the group and is immutable" per Microsoft Learn) and the static/dynamic membership type
       itself (Set-OERGroup has no PATCH path for either and raises its own NotDynamicGroup error for a
       membershipRule sent to a non-dynamic group). A document that declares a value differing from live
       state for either one gets a Skipped record naming the divergence plus a Write-Warning, and the
       write is never attempted; this also suppresses the contradictory 'group properties match'
       Unchanged for the same group.
    2. Reconcile declared members (add missing; emit Extra or prune undeclared with -Prune) -- UNLESS
       the group is dynamic (already dynamic, or declared dynamic=true in the document). Microsoft Learn
       is explicit that a member of a dynamic membership group cannot be added or removed manually, so
       every declared member is reported as a Skipped record instead, nothing is added, and the
       Extra/prune pass does not run (a group with no declared members but a live membership still gets
       one summary Skipped record so the inaction is visible under -Prune too).
    2b. Reconcile declared owners (add missing; emit Extra or prune undeclared with -Prune), gated on
        the document's owners key being DECLARED (present and non-null) -- an omitted owners key never
        reconciles or prunes, unlike members. Owners are not rule-derived, so this step runs even on a
        dynamic group. Microsoft Learn states a group's last (user) owner cannot be removed; a -Prune
        run that would remove the last remaining owner reports a Skipped record instead of firing a
        call Microsoft Graph rejects.
    3. Reconcile time-bound eligibility entries (those with durationDays) -- the first one onboards the
       group to PIM so that a roleManagementPolicy is created. Each entry is matched on the
       (principal, accessType) pair and its declared window is diffed against the live schedule
       instance by Resolve-OERGroupEligibilityChange, so a changed durationDays or a member/owner
       switch is re-issued instead of being reported Unchanged. Add-OERGroupEligibility is called with
       -Action adminAssign when the eligibility is absent and -Action adminUpdate when it already
       exists and only its window or permanence differs, since Microsoft Graph rejects an adminAssign
       against a principal that is already eligible.
    4. Apply pimPolicy (e.g. ActivationMaxHours, AllowPermanentEligibility) -- must come after the
       first time-bound eligibility so the policy exists.
    5. Reconcile permanent eligibility entries (those without durationDays) -- must come after
       pimPolicy has been set to allow permanent eligibility. Matched and diffed the same way, so a
       time-bound eligibility that the document declares permanent is re-issued as permanent, again
       selecting adminAssign or adminUpdate from the diff reason as in step 3.

    When -Prune is set, current members not present in the declared set are removed (with
    Write-Warning) after a ShouldProcess gate. Without -Prune those extra members are reported as
    Extra (informational) and left alone. The same applies to eligibility entries, with one
    difference: an eligibility entry is only reconciled (reported as Extra, or removed under
    -Prune) when the document's eligibility key is DECLARED (present and non-null, including an
    empty array) -- an omitted eligibility key leaves live eligibility alone entirely, unlike an
    omitted members key, which still reconciles against an empty declared set.

    A failed read of the live group -- its properties, members, owners or PIM eligibility -- reports
    Failed with the underlying ErrorRecord and reconciles nothing further for that item, so a Created
    row is never derived from a read that did not succeed; an empty read that SUCCEEDED still
    reconciles normally.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the group itself does not exist and
    its creation is skipped under -WhatIf, no child read or write calls are made.

    .PARAMETER Item
    One element from the groups[] array in the structure document, as a PSCustomObject produced by
    ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current members not in the declared set are removed after a ShouldProcess gate. Without
    this switch, extra members are only reported as Extra and never deleted. Also removes eligibility
    entries not in the declared set, but only when the document declares the eligibility key at all
    (present and non-null) -- an omitted eligibility key is never pruned or reported, regardless of
    -Prune. The same present-and-non-null gate applies to owners: an omitted OR explicit null
    owners key is never reconciled or pruned. members is the one collection where absent and null
    differ: an omitted members key still reconciles (existing members it does not name are
    pruned/reported same as any other run), but an explicit "members": null does not reconcile at
    all. null -- not an omitted key -- is how a group is declared without touching its members,
    owners or eligibility; applying the scalar "omission means untouched" rule to members gets
    this backwards.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias, accepted only for call-site uniformity with the other
    Sync-OERStructure* handlers that Invoke-OERStructure drives uniformly. This handler does not
    currently consult a tenant default for any field.

    .EXAMPLE
    Sync-OERStructureGroup -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one group entry from the document, pruning undeclared members. -TenantAlias is accepted
    for call-site uniformity with the other Sync-OERStructure* handlers but is not otherwise used here.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'The Invoke-OERStructure engine passes -TenantAlias uniformly to every Sync handler; this handler no longer consults a tenant default for pimPolicy but keeps the parameter for call-site uniformity.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias
    )
    process {
        # -- Resolve the display name (template or literal) ---------------------------------
        $Name = $null
        $HasTemplate = Test-OERDeclaredProperty -Node $Item -Name 'template'
        if ($HasTemplate -and $Item.template) {
            $TokenHash = @{}
            if (Test-OERDeclaredProperty -Node $Item -Name 'tokens') {
                foreach ($Prop in $Item.tokens.PSObject.Properties) {
                    $TokenHash[$Prop.Name] = $Prop.Value
                }
            }
            $Name = Resolve-OERName -Template $Item.template -Tokens $TokenHash
        } else {
            $Name = $Item.displayName
        }

        # -- Check existence ----------------------------------------------------------------
        $Gid = Resolve-OERGroupId -DisplayName $Name

        # -- Create or update the group object ------------------------------------------
        if (-not $Gid) {
            # Group does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create group')) {
                # Under -WhatIf: emit Skipped for the group and all children, then return.
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would create group $Name"

                # Emit Skipped for declared members
                if (Test-OERDeclaredProperty -Node $Item -Name 'members') {
                    foreach ($M in @($Item.members)) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure member '$M' after group is created"
                    }
                }

                # Emit Skipped for declared owners
                if (Test-OERDeclaredProperty -Node $Item -Name 'owners') {
                    foreach ($O in @($Item.owners)) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure owner '$O' after group is created"
                    }
                }

                # Emit Skipped for declared eligibility entries
                if (Test-OERDeclaredProperty -Node $Item -Name 'eligibility') {
                    foreach ($E in @($Item.eligibility)) {
                        $Ref = if (Test-OERDeclaredProperty -Node $E -Name 'principal') { $E.principal } else { '?' }
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure eligibility for '$Ref' after group is created"
                    }
                }

                # Emit Skipped for pimPolicy
                if (Test-OERDeclaredProperty -Node $Item -Name 'pimPolicy') {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail 'would configure pimPolicy after group is created'
                }
                return
            }

            # Build creation params
            $NewParams = @{ DisplayName = $Name; Confirm = $false }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'roleAssignable') -and $Item.roleAssignable -eq $true) {
                $NewParams.RoleAssignable = $true
            }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'dynamic') -and $Item.dynamic -eq $true) {
                $NewParams.Dynamic = $true
                if (Test-OERDeclaredProperty -Node $Item -Name 'membershipRule') {
                    $NewParams.MembershipRule = $Item.membershipRule
                }
                if (Test-OERDeclaredProperty -Node $Item -Name 'membershipRuleProcessingState') {
                    $NewParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
                }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if (Test-OERDeclaredProperty -Node $Item -Name 'mailNickname') { $NewParams.MailNickname = $Item.mailNickname }
            if (Test-OERDeclaredProperty -Node $Item -Name 'administrativeUnit') { $NewParams.AdministrativeUnit = $Item.administrativeUnit }

            $Created = $null
            try {
                $Created = New-OERGroup @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "group creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail 'New-OERGroup returned no object'
                return
            }

            $Gid = $Created.Id
            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Created' -Detail "created group $Name ($Gid)"

            # After create: current state is empty
            $CurrentMembers    = @()
            $CurrentOwners     = @()
            $CurrentEligibles  = @()

        } else {
            # Group exists -- diff mutable properties.
            # A failed read of the live group is not an empty group. Get-OERGroup now OMITS a
            # collection whose read failed, and without -ErrorAction Stop that absence collapsed
            # silently to @() below -- so the engine reconciled against an empty current state and
            # reported Created for members that already exist (issue #60, and the caller half of
            # issue #76).
            # Ask ONLY for the collections this document entry can actually consume. -ErrorAction Stop
            # makes the read all-or-nothing on purpose (a partially read item must never be pruned),
            # so requesting a collection the entry never uses would let one unusable endpoint fail the
            # whole item: a tenant whose PIM-for-Groups beta endpoint answers 403 rather than the
            # ResourceTypeNotSupported that Get-OERGroup carves out by name would report Failed for
            # every group, including ones declaring only members that applied cleanly before.
            # -IncludeMembers stays unconditional: $CurrentMembers feeds the Extra/prune pass whenever
            # 'members' is not declared-null, which includes an omitted key.
            # 'eligibility' alone drives -IncludePimEligibility, and 'pimPolicy' deliberately does NOT:
            # Step 4 reads the live policy through Get-OERGroupPimPolicy and never consults
            # $CurrentEligibles. Its only three consumers are the time-bound loop, the permanent loop
            # and the Extra/prune pass, and all three are reached solely when 'eligibility' is declared.
            # Requesting the read for a pimPolicy-only entry let a 403 on the beta eligibility endpoint
            # fail an item that has no use for the answer -- and that applies cleanly today.
            $NeedOwners = Test-OERDeclaredProperty -Node $Item -Name 'owners'
            $NeedElig   = Test-OERDeclaredProperty -Node $Item -Name 'eligibility'
            $Cur = $null
            try {
                $Cur = Get-OERGroup -Id $Gid -IncludeMembers -IncludeOwners:$NeedOwners `
                    -IncludePimEligibility:$NeedElig -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current state of group '$Name': $($PSItem.Exception.Message); no property, member, owner or eligibility change was made" `
                    -ErrorRecord $PSItem
                return
            }
            $CurrentMembers   = if ($Cur.Members) { @($Cur.Members) } else { @() }
            $CurrentOwners    = if ($Cur.Owners) { @($Cur.Owners) } else { @() }
            $CurrentEligibles = if ($Cur.PimEligibility) { @($Cur.PimEligibility) } else { @() }
            $CurIsDynamic     = ([string]$Cur.GroupType -eq 'Dynamic')

            # Diff Description and MailNickname
            $UpdateParams = @{}
            # Set when a drift Skipped record fires below, so the no-updates branch never also emits a
            # contradictory 'group properties match' Unchanged for the same group.
            $DriftReported = $false

            if (Test-OERDeclaredProperty -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) {
                    $UpdateParams.Description = $Item.description
                }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'mailNickname') {
                if ($Cur.MailNickname -ne $Item.mailNickname) {
                    $UpdateParams.MailNickname = $Item.mailNickname
                }
            }

            # isAssignableToRole: Microsoft Learn states it "can only be set while creating the group
            # and is immutable" -- so declared drift here can never be applied. Report it and move on
            # rather than firing a doomed PATCH or silently pretending the properties match.
            if ((Test-OERDeclaredProperty -Node $Item -Name 'roleAssignable') -and ([bool]$Item.roleAssignable -ne [bool]$Cur.IsAssignableToRole)) {
                $DriftReported = $true
                Write-Warning "Sync-OERStructureGroup: group '$Name' declares roleAssignable=$([bool]$Item.roleAssignable) but the live group is roleAssignable=$([bool]$Cur.IsAssignableToRole); isAssignableToRole can only be set while creating a group and is immutable on Microsoft Graph -- recreating the group is the only route."
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "declared 'roleAssignable' ($([bool]$Item.roleAssignable)) differs from the live group ($([bool]$Cur.IsAssignableToRole)); isAssignableToRole is immutable on Microsoft Graph -- recreating the group is the only route"
            }

            # dynamic: a static group cannot be converted to dynamic (and Set-OERGroup raises its own
            # NotDynamicGroup error for exactly that attempt), and this module never PATCHes a dynamic
            # group back to static either. Report the drift instead of attempting a doomed conversion.
            $WantDynamic = if (Test-OERDeclaredProperty -Node $Item -Name 'dynamic') { [bool]$Item.dynamic } else { $null }
            if (($null -ne $WantDynamic) -and ($WantDynamic -ne $CurIsDynamic)) {
                $DriftReported = $true
                Write-Warning "Sync-OERStructureGroup: group '$Name' declares dynamic=$WantDynamic but the live group is dynamic=$CurIsDynamic; Set-OERGroup cannot convert a group's membership type (NotDynamicGroup) -- recreating the group is the only route."
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "declared 'dynamic' ($WantDynamic) differs from the live group ($CurIsDynamic); Set-OERGroup cannot convert a group's membership type (NotDynamicGroup) -- recreating the group is the only route"
            }

            # membershipRule: Set-OERGroup PATCHes it only when the live group is already dynamic, and
            # guards the non-dynamic case with its own NotDynamicGroup error. When the live group is not
            # dynamic, the 'dynamic' drift report above already covers it -- do not also add the rule.
            if ((Test-OERDeclaredProperty -Node $Item -Name 'membershipRule') -and $CurIsDynamic -and ([string]$Cur.MembershipRule -ne [string]$Item.membershipRule)) {
                $UpdateParams.MembershipRule = [string]$Item.membershipRule
            }
            # membershipRuleProcessingState: same rule as membershipRule -- Set-OERGroup cannot convert a
            # group's type, so this is diffed only when the LIVE group is already dynamic (the 'dynamic'
            # drift report above covers a non-dynamic live group; a declared value there is drift, not a
            # prediction of what this run will produce).
            if ((Test-OERDeclaredProperty -Node $Item -Name 'membershipRuleProcessingState') -and $CurIsDynamic -and ([string]$Cur.MembershipRuleProcessingState -ne [string]$Item.membershipRuleProcessingState)) {
                $UpdateParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
            }

            if ($UpdateParams.Count -gt 0) {
                if ($Caller.ShouldProcess($Name, 'Update group properties')) {
                    try {
                        Set-OERGroup -Id $Gid @UpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "updated group properties ($($UpdateParams.Keys -join ', '))"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would update group properties ($($UpdateParams.Keys -join ', '))"
                }
            } elseif (-not $DriftReported) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail 'group properties match'
            }

        }

        # -- Step 2: members ----------------------------------------------------------------
        # A dynamic group's membership is owned by its membershipRule: Microsoft Learn states plainly
        # that a member of a dynamic membership group cannot be added or removed manually. Reconciling
        # here would fire calls Graph rejects and, under -Prune, fire them against rule-derived members.
        # $Cur exists only on the update path (the else branch above); on that path the LIVE type is
        # the only truth that matters, because Set-OERGroup has no parameter and no code path that can
        # convert an existing group's static/dynamic type -- a declared dynamic=true against a live
        # static group is drift (already reported above as a Skipped record), never a prediction of
        # what this run will produce, so it must not also flip the member step into dynamic mode. On
        # the create path there is no live group yet, so whether the document declares dynamic=true is
        # what decides -- New-OERGroup -Dynamic really does produce a dynamic group there.
        $EffectiveIsDynamic = if ($Cur) {
            $CurIsDynamic
        } else {
            (Test-OERDeclaredProperty -Node $Item -Name 'dynamic') -and [bool]$Item.dynamic
        }

        $DeclaredMemberIds = [System.Collections.Generic.List[string]]::new()
        # An omitted 'members' key has always meant "no add-list, but the prune/Extra loop below
        # still runs against whatever it finds" -- that is intentional, existing, tested behavior
        # (an absent collection is not an instruction to leave live state alone; only an EXPLICIT
        # null is). So the add loop is gated on Test-OERDeclaredProperty (skips on both absent and
        # null), while the prune/Extra loop below is gated on the narrower $MembersDeclaredNull so
        # it keeps running when the key is merely absent and only backs off on an explicit null.
        $MembersDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'members'

        if ($EffectiveIsDynamic) {
            $DeclaredMembers = if (Test-OERDeclaredProperty -Node $Item -Name 'members') { @($Item.members) } else { @() }
            foreach ($MRef in $DeclaredMembers) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "member '$MRef' was not reconciled: group '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be added or removed manually. Change the rule (membershipRule) to change the membership"
            }
            if ($DeclaredMembers.Count -eq 0 -and $CurrentMembers.Count -gt 0) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "the $($CurrentMembers.Count) current member(s) were not reconciled: group '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be removed manually, so -Prune does not apply to them"
            }
        } else {
            # A declared member that cannot be resolved carries no id, so it cannot protect its live
            # counterpart from the Extra/prune loop below; while this list is non-empty that loop
            # withholds every candidate (ConvertTo-OERPruneWithheldResult owns the rule).
            $MemberUnresolved = [System.Collections.Generic.List[string]]::new()
            if (Test-OERDeclaredProperty -Node $Item -Name 'members') {
                foreach ($MRef in @($Item.members)) {
                    $Mid = Resolve-OERStructurePrincipal -Reference $MRef
                    if (-not $Mid) {
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Could not resolve principal '$MRef' to an object id."),
                            'PrincipalNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $MRef
                        )
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve member '$MRef'" -ErrorRecord $ErrRec
                        $MemberUnresolved.Add($MRef)
                        continue
                    }
                    $DeclaredMemberIds.Add($Mid)

                    $AlreadyMember = $CurrentMembers | Where-Object { $_.id -eq $Mid }
                    if ($AlreadyMember) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "member '$MRef' already present"
                    } else {
                        if ($Caller.ShouldProcess($Name, "Add member '$Mid'")) {
                            try {
                                Add-OERGroupMember -Id $Gid -PrincipalId $Mid -Confirm:$false -ErrorAction Stop
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add member '$MRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "added member '$MRef'"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would add member '$MRef'"
                        }
                    }
                }
            }

            # Extra/prune undeclared current members. Skipped ONLY when 'members' is explicitly null --
            # an omitted key still reconciles against an empty declared set (existing behavior), but an
            # explicit null is a distinct "leave membership alone" signal and must not report every live
            # member as Extra or, worse under -Prune, remove them all.
            if (-not $MembersDeclaredNull) {
                foreach ($CurMember in $CurrentMembers) {
                    $CurId = $CurMember.id
                    if ($DeclaredMemberIds -notcontains $CurId) {
                        $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $MemberUnresolved -Candidate "undeclared member '$CurId'"
                        if ($Withheld) { $Withheld; continue }
                        if ($Prune) {
                            $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                            Write-Warning "Sync-OERStructureGroup: $PruneVerb undeclared member '$CurId' from group '$Name'."
                            if ($Caller.ShouldProcess($Name, "Remove undeclared member '$CurId'")) {
                                try {
                                    Remove-OERGroupMember -Id $Gid -PrincipalId $CurId -Confirm:$false -ErrorAction Stop
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    $Caller.WriteError($PSItem)
                                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove member '$CurId': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                    continue
                                }
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed undeclared member '$CurId'"
                            } else {
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove undeclared member '$CurId'"
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "undeclared member '$CurId' (use -Prune to remove)"
                        }
                    }
                }
            }
        }

        # -- Step 2b: owners -----------------------------------------------------------------
        # Owners are NOT rule-derived (unlike members, which are skipped or rule-owned on a dynamic
        # group), so this pass runs on a dynamic group too -- it must not be gated on
        # $EffectiveIsDynamic. The whole pass (add AND Extra/prune) is gated on the 'owners' key being
        # DECLARED (present and non-null): unlike members, an omitted owners key must never reconcile or
        # prune, because a brand-new destructive pass firing on every omitted key would strip the owners
        # off every group in an already-written document on its next -Prune run.
        if (Test-OERDeclaredProperty -Node $Item -Name 'owners') {
            $DeclaredOwnerIds = [System.Collections.Generic.List[string]]::new()
            # Same rule as $MemberUnresolved: an unresolved declared owner withholds every owner
            # candidate in the Extra/prune loop below.
            $OwnerUnresolved = [System.Collections.Generic.List[string]]::new()
            foreach ($ORef in @($Item.owners)) {
                $Oid = Resolve-OERStructurePrincipal -Reference $ORef
                if (-not $Oid) {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve owner '$ORef' to an object id."),
                        'PrincipalNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $ORef
                    )
                    $Caller.WriteError($ErrRec)
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve owner '$ORef'" -ErrorRecord $ErrRec
                    $OwnerUnresolved.Add($ORef)
                    continue
                }
                $DeclaredOwnerIds.Add($Oid)

                $AlreadyOwner = $CurrentOwners | Where-Object { $_.id -eq $Oid }
                if ($AlreadyOwner) {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "owner '$ORef' already present"
                } else {
                    if ($Caller.ShouldProcess($Name, "Add owner '$Oid'")) {
                        try {
                            Add-OERGroupMember -Id $Gid -PrincipalId $Oid -AccessType owner -Confirm:$false -ErrorAction Stop
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add owner '$ORef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "added owner '$ORef'"
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would add owner '$ORef'"
                    }
                }
            }

            # Extra/prune undeclared current owners. Microsoft Learn: "Once owners are assigned to a
            # group, the last owner (a user object) of the group cannot be removed" -- note the exact
            # wording, "a user object": Learn scopes the restriction to a USER owner specifically, so a
            # group whose sole remaining owner is a service principal may in fact be removable. This
            # guard is nonetheless DELIBERATELY conservative and counts owners of every type, not just
            # user owners: whether the restriction also applies to a lone service-principal owner is an
            # OPEN question on this PR's live-verification checklist, and narrowing the guard now would
            # encode an unverified assumption into a destructive path. Do NOT make this guard type-aware
            # without first confirming the behaviour against a real tenant -- see the checklist. The
            # number of owners still standing is tracked as removals are applied, and the removal that
            # would leave none is refused with a Skipped record instead of firing a call that may fail.
            $RemainingOwnerCount = $CurrentOwners.Count
            foreach ($CurOwner in $CurrentOwners) {
                $CurId = $CurOwner.id
                if ($DeclaredOwnerIds -notcontains $CurId) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $OwnerUnresolved -Candidate "undeclared owner '$CurId'"
                    if ($Withheld) { $Withheld; continue }
                    if ($Prune) {
                        if ($RemainingOwnerCount -le 1) {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                                -Detail "did not remove owner '$CurId': it is the last remaining owner of group '$Name', and this pass refuses to remove it (this is our own guard, not a Graph rejection). Microsoft Graph's documented restriction names a USER owner specifically, so if this is a service principal it may in fact be removable; this guard is deliberately conservative pending live verification."
                            continue
                        }
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureGroup: $PruneVerb undeclared owner '$CurId' from group '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared owner '$CurId'")) {
                            try {
                                Remove-OERGroupMember -Id $Gid -PrincipalId $CurId -AccessType owner -Confirm:$false -ErrorAction Stop
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove owner '$CurId': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                            $RemainingOwnerCount--
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed undeclared owner '$CurId'"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove undeclared owner '$CurId'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "undeclared owner '$CurId' (use -Prune to remove)"
                    }
                }
            }
        }

        # -- Steps 3-5: eligibility + pimPolicy (PIM chicken-and-egg order) ----------------
        $HasEligibility = (Test-OERDeclaredProperty -Node $Item -Name 'eligibility')
        $HasPimPolicy   = (Test-OERDeclaredProperty -Node $Item -Name 'pimPolicy')

        $TimeBoundEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
        $PermanentEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
        # Declared (principalId, accessType) keys, populated as both eligibility loops below resolve
        # each entry's principal and access type. Consumed by the Extra/prune pass after Step 5.
        $DeclaredEligibilityKeys = [System.Collections.Generic.List[string]]::new()
        # Declared eligibility principals that could not be resolved, fed by BOTH loops below. While
        # it is non-empty the Extra/prune pass withholds every eligibility candidate, since an
        # unresolved entry carries no key to protect its live counterpart with.
        $EligibilityUnresolved = [System.Collections.Generic.List[string]]::new()
        if ($HasEligibility) {
            foreach ($EEntry in @($Item.eligibility)) {
                if (Test-OERDeclaredProperty -Node $EEntry -Name 'durationDays') {
                    $TimeBoundEntries.Add($EEntry)
                } else {
                    $PermanentEntries.Add($EEntry)
                }
            }
        }

        # Nested helper: find the live eligibility schedule instance for one (principal, accessType)
        # pair. Matching on the pair -- not on principal id alone -- is what lets an owner eligibility
        # coexist with a member one and what makes a member/owner switch visible to the diff.
        # A Graph instance that omits accessId is treated as a member eligibility.
        function Get-CurrentEligibility {
            param([object[]]$Instances, [string]$PrincipalId, [string]$AccessType)
            foreach ($Instance in @($Instances)) {
                if ([string]$Instance.principalId -ne $PrincipalId) { continue }
                $InstanceAccess = if ($Instance.accessId) { [string]$Instance.accessId } else { 'member' }
                if ($InstanceAccess -eq $AccessType) { return $Instance }
            }
            return $null
        }

        # Step 3: time-bound eligibility
        foreach ($EEntry in $TimeBoundEntries) {
            $EPrinRef = $EEntry.principal
            $EPrinId  = Resolve-OERStructurePrincipal -Reference $EPrinRef
            if (-not $EPrinId) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve eligibility principal '$EPrinRef' to an object id."),
                    'PrincipalNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $EPrinRef
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve eligibility principal '$EPrinRef'" -ErrorRecord $ErrRec
                $EligibilityUnresolved.Add($EPrinRef)
                continue
            }

            $EAccessType = if ((Test-OERDeclaredProperty -Node $EEntry -Name 'accessType') -and $EEntry.accessType) { [string]$EEntry.accessType } else { 'member' }
            $DeclaredEligibilityKeys.Add(('{0}|{1}' -f $EPrinId, $EAccessType).ToLowerInvariant())
            $CurrentElig = Get-CurrentEligibility -Instances $CurrentEligibles -PrincipalId $EPrinId -AccessType $EAccessType
            $EChange = Resolve-OERGroupEligibilityChange -Declared $EEntry -Current $CurrentElig

            if (-not $EChange.Changed) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "eligibility for '$EPrinRef' ($($EChange.AccessType)) already matches"
                continue
            }

            $EAction = if ($EChange.Reason -eq 'Absent') { 'adminAssign' } else { 'adminUpdate' }
            if ($Caller.ShouldProcess($Name, "Add time-bound $($EChange.AccessType) eligibility for '$EPrinId' ($($EChange.DurationDays) days)")) {
                try {
                    Add-OERGroupEligibility -Id $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -DurationDays $EChange.DurationDays -Action $EAction -Confirm:$false -ErrorAction Stop
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add eligibility for '$EPrinRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    continue
                }
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "set time-bound $($EChange.AccessType) eligibility for '$EPrinRef' ($($EChange.DurationDays) days): $($EChange.Detail)"
            } else {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set time-bound $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            }
        }

        # -- Step 4: pimPolicy (per access type: member and/or owner) -----------------------
        if ($HasPimPolicy) {
            $Pp = $Item.pimPolicy

            # Which access types the document declares with a usable policy block.
            $HasMember = Test-OERDeclaredProperty -Node $Pp -Name 'member'
            $HasOwner  = Test-OERDeclaredProperty -Node $Pp -Name 'owner'

            # Whether the NESTED form was used at all. A key present with an explicit null still
            # selects the nested form -- it just declares no policy for that access type, exactly as
            # omitting the key inside a nested block would. Without this second question a
            # "member": null falls through to the flat back-compat branch and the whole pimPolicy
            # object is misread as a member policy.
            $UsesNestedForm = $HasMember -or $HasOwner -or
                (Test-OERDeclaredNull -Node $Pp -Name 'member') -or
                (Test-OERDeclaredNull -Node $Pp -Name 'owner')

            $DesiredByAccess = [ordered]@{}
            if ($UsesNestedForm) {
                if ($HasMember) { $DesiredByAccess['member'] = $Pp.member }
                if ($HasOwner)  { $DesiredByAccess['owner']  = $Pp.owner }
            } else {
                # Flat back-compat form = the member policy.
                $DesiredByAccess['member'] = $Pp
            }

            foreach ($AccessType in $DesiredByAccess.Keys) {
                $Declared = $DesiredByAccess[$AccessType]

                # Read current policy for this access type (best-effort -- group may not be onboarded).
                $CurrentPolicy = $null
                try {
                    $CurrentPolicy = Get-OERGroupPimPolicy -Id $Gid -AccessType $AccessType -ErrorAction Stop
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                }

                $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $CurrentPolicy
                if (-not $Change.Changed) {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "pimPolicy ($AccessType) already matches"
                    continue
                }

                if ($Caller.ShouldProcess($Name, "Set PIM policy ($AccessType): $($Change.Changes -join '; ')")) {
                    try {
                        $SetSplat = $Change.SetParams
                        $PimResult = Set-OERGroupPimPolicy -Id $Gid -AccessType $AccessType @SetSplat -Confirm:$false -ErrorAction Stop
                        if ($null -ne $PimResult -and ($PimResult.PSObject.Properties.Name -contains 'Applied') -and (-not $PimResult.Applied)) {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "pimPolicy ($AccessType) only partially applied; failed rules: $(@($PimResult.FailedRules) -join ', ')"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "pimPolicy ($AccessType) set: $($Change.Changes -join '; ')"
                        }
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "pimPolicy ($AccessType) update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set pimPolicy ($AccessType): $($Change.Changes -join '; ')"
                }
            }
        }

        # Step 5: permanent eligibility
        foreach ($EEntry in $PermanentEntries) {
            $EPrinRef = $EEntry.principal
            $EPrinId  = Resolve-OERStructurePrincipal -Reference $EPrinRef
            if (-not $EPrinId) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve eligibility principal '$EPrinRef' to an object id."),
                    'PrincipalNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $EPrinRef
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve eligibility principal '$EPrinRef'" -ErrorRecord $ErrRec
                $EligibilityUnresolved.Add($EPrinRef)
                continue
            }

            $EAccessType = if ((Test-OERDeclaredProperty -Node $EEntry -Name 'accessType') -and $EEntry.accessType) { [string]$EEntry.accessType } else { 'member' }
            $DeclaredEligibilityKeys.Add(('{0}|{1}' -f $EPrinId, $EAccessType).ToLowerInvariant())
            $CurrentElig = Get-CurrentEligibility -Instances $CurrentEligibles -PrincipalId $EPrinId -AccessType $EAccessType
            $EChange = Resolve-OERGroupEligibilityChange -Declared $EEntry -Current $CurrentElig

            if (-not $EChange.Changed) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "permanent eligibility for '$EPrinRef' ($($EChange.AccessType)) already matches"
                continue
            }

            $EAction = if ($EChange.Reason -eq 'Absent') { 'adminAssign' } else { 'adminUpdate' }
            if ($Caller.ShouldProcess($Name, "Add permanent $($EChange.AccessType) eligibility for '$EPrinId'")) {
                try {
                    Add-OERGroupEligibility -Id $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -Action $EAction -Confirm:$false -ErrorAction Stop
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add permanent eligibility for '$EPrinRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    continue
                }
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "set permanent $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            } else {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set permanent $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            }
        }

        # Extra/prune undeclared current eligibilities. Only runs when the document declares the
        # collection -- an absent (or explicitly null) eligibility key means "do not reconcile
        # eligibility at all", exactly as it does for members. UNLIKE members/resources/resourceRoles,
        # an OMITTED eligibility key does NOT prune here: this pass is new and destructive (it can
        # revoke standing privileged access), so it only fires when the document affirmatively
        # declares the collection (Test-OERDeclaredProperty), including as an empty array.
        if ($HasEligibility) {
            foreach ($CurElig in $CurrentEligibles) {
                $CurPrincipal = [string]$CurElig.principalId
                $CurAccess = if ($CurElig.accessId) { [string]$CurElig.accessId } else { 'member' }
                $CurKey = ('{0}|{1}' -f $CurPrincipal, $CurAccess).ToLowerInvariant()
                if ($DeclaredEligibilityKeys -contains $CurKey) { continue }
                $Label = "undeclared $CurAccess eligibility for principal '$CurPrincipal'"
                $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $EligibilityUnresolved -Candidate $Label
                if ($Withheld) { $Withheld; continue }
                if ($Prune) {
                    # Remove-OERGroupEligibility (ConfirmImpact = High) also emits its own generic
                    # Write-Warning inside its ShouldProcess gate on every real removal. A previous revision
                    # dropped the handler-level warning below to avoid a double-warn against that (unlike
                    # Remove-OERGroupMember, which is silent) -- but that traded a duplicate for a safety
                    # hole: the child cmdlet is never reached under -WhatIf or when an interactive -Confirm
                    # prompt is declined, so nothing warned before the destructive gate. The handler warning
                    # is restored here, phrased from $WhatIfPreference so it fires before the gate on every
                    # path, and the child's own duplicate is silenced at the call site because the handler's
                    # message already names the principal, the access type and the group -- strictly more
                    # informative than the cmdlet's generic one -- and is the one that reaches the operator
                    # before the prompt.
                    $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                    Write-Warning "Sync-OERStructureGroup: $PruneVerb $Label from group '$Name'."
                    if ($Caller.ShouldProcess($Name, "Remove $Label")) {
                        try {
                            Remove-OERGroupEligibility -Group $Gid -PrincipalId $CurPrincipal -AccessType $CurAccess `
                                -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed $Label"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove $Label`: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove $Label"
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "$Label (use -Prune to remove)"
                }
            }
        }
    }
}
