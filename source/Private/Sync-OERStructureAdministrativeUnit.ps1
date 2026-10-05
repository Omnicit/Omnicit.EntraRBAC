function Sync-OERStructureAdministrativeUnit {
    <#
    .SYNOPSIS
    Reconciles one administrativeUnits[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single administrative unit entry from the structure document.
    It is called by the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult
    records describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key: an existing unit is matched and updated by it. Renaming through
    the document is not possible: this handler uses displayName purely to match, and never calls
    Set-OERAdministrativeUnit -NewDisplayName -- a changed displayName creates a new unit under the
    new name and leaves the old one in place, unreported.

    Processing order within a single administrative unit:
    1. Create the unit when absent (including -Dynamic/-MembershipRule/-MembershipRuleProcessingState
       and -HiddenMembership when declared), or diff and update the mutable properties (description,
       membershipType, membershipRule, membershipRuleProcessingState, and visibility in both directions)
       when it already exists. A membershipType conversion to dynamic carries the declared membershipRule
       in the same Set-OERAdministrativeUnit call, so the unit is never momentarily dynamic with no rule;
       when no rule is declared and the live unit has none, the conversion is reported as Failed instead.
       One drift this handler cannot apply to an EXISTING unit is reported as a Skipped record with a
       warning rather than silently ignored (or folded into a misleading Unchanged): the genuinely
       Graph-immutable isMemberManagementRestricted flag, for which recreating the unit is the only route.
    2. Reconcile declared members (add missing; emit Extra or prune undeclared with -Prune, or report
       them Skipped while a declared member cannot be resolved -- see "Withheld prune" below) -- UNLESS the
       unit is dynamic after this run (already dynamic, or converted by step 1). Microsoft Graph disables
       manual member management on a dynamic administrative unit: the membership rule owns the membership,
       Add/Remove member calls are rejected, and switching a unit to dynamic can change its existing
       membership on its own. Every declared member is then reported as a Skipped record explaining that,
       nothing is added, and the Extra/prune pass is not run (a unit with no declared members but a live
       membership gets one summary Skipped record so the inaction is visible under -Prune too).
    3. Reconcile declared scopedRoles (add missing by RoleName+PrincipalId, or by role id+PrincipalId
       when the declared role is a GUID -- see the role id paragraph below; emit Extra or prune
       undeclared with -Prune, removing by ScopedRoleMembershipId, or report them Skipped while a
       declared scoped role's principal cannot be resolved -- see "Withheld prune" below). Scoped roles are unaffected by dynamic membership --
       only member management is disabled on a dynamic unit -- so this step always runs.

    An explicit JSON null on any document property counts as NOT DECLARED (the live value is left
    untouched), the same rule the offline validator and the other apply diffs apply: "dynamic": null must
    not convert a live dynamic unit to Assigned, and "hiddenMembership": null must not reveal a hidden
    unit's membership. That "null counts as not declared" rule governs every scalar property, and it
    also governs the ADD side of members and scopedRoles -- an explicit null adds nothing, same as an
    omitted key. The PRUNE side of those two collections is the one place null and absent are NOT the
    same: see -Prune.

    When -Prune is set, current members and scoped roles not present in the declared set are
    removed (with Write-Warning) after a ShouldProcess gate. Without -Prune those extras are
    reported as Extra (informational) and left alone.

    Withheld prune: members and scopedRoles each withhold their OWN prune when one of their declared
    entries cannot be resolved -- Resolve-OERStructurePrincipal gives no object id for a member, or
    for a scoped role's principal (the declared role itself is matched as written, not looked up).
    Such an entry carries no id, so the pass cannot tell which live entry it names, and its live
    counterpart would otherwise look undeclared. Every undeclared live entry in that collection is
    then reported Skipped, with a Detail that starts "prune withheld: declared entry '<reference>'
    could not be resolved" (several unresolved entries: "declared entries '<a>', '<b>' could not be
    resolved"), with or without -Prune; no warning is written, no ShouldProcess prompt is issued, and
    nothing in that collection is removed until the entry is fixed or removed from the document
    (ConvertTo-OERPruneWithheldResult owns the rule and the text). The unresolved entry keeps its own
    error and Failed record (the record is lost only when the handler later throws for the same item,
    see below). The rule is per collection: an unresolved scoped role principal withholds the scopedRoles
    prune only, and the member pass runs as usual. A lookup that THROWS, rather than giving no id, is
    not caught by this handler: it ends the item where it is thrown, and neither that collection's
    prune pass nor any later step runs. The engine then reports the item as one Failed ("handler
    error") record and discards every record the handler had already emitted for it, so a member
    prune that already completed stands with no Removed row, and an unresolved entry's Failed row is
    lost; warnings and errors already written remain.

    Unnamed live scoped role: the directory role list that names each live role is read in full, but
    the reader does not check that every membership's role id is listed. A role id the list does not
    name gets an empty RoleName, with its RoleId kept; that has not been seen live, and this guard keeps
    the handler from adding and removing a role it cannot name. A role declared by NAME can never match
    such a role, yet it may be that very role. When the document declares a role by name for a principal who
    has no live role of that name but does hold at least one such unnamed live role on the unit, the
    handler adds nothing and removes nothing for that principal's unnamed roles: it emits ONE Skipped
    record for the declared entry, with a Detail that starts "prune withheld: scopedRole '<role>' for
    '<principal>' matches no live scoped role by name" and names the role ids, with or without -Prune
    and under -WhatIf alike, and the principal's unnamed roles get no Extra or Removed record of their
    own (ConvertTo-OERPruneWithheldResult owns the text). Declaring the role by its role id reconciles
    it. A role declared by id is matched on its id (see below) and is not affected, a principal's NAMED
    live roles are pruned as usual, and so are other principals' unnamed roles.

    A scopedRoles[].role may be a directory-role display name or a role id (GUID); a GUID is passed
    to Add-OERAdministrativeUnitScopedRole -RoleId, so a role whose friendly name could not be resolved
    still round-trips. A GUID is matched against the live membership RoleId or -- since the directory
    role name map keys a role by both its object id and its role template id -- against a live RoleId
    the map gives the same name (decision A16): a role declared by its template id is then neither added
    again nor removed when the live membership carries its object id, or the other way round. A GUID or
    a live RoleId the map does not name matches on the id alone. The map is read for this only when the
    document declares a role by GUID and the unit has a live scoped role whose name was read; when that
    read fails, the item is Failed and no scoped role is added or removed.

    A failed read of the live unit -- its properties, members or scoped roles -- reports Failed with
    the underlying ErrorRecord and reconciles nothing further for that item, so a Created row is
    never derived from a read that did not succeed; an empty read that SUCCEEDED still reconciles
    normally. The scoped roles read includes the directory role list that names each live role (a
    declared role is matched by name): when the unit has scoped roles and that list cannot be read, the
    item is Failed too and no scoped role is added or removed, with or without -Prune. The second read
    of that list, to match a role declared by role id (see above), follows the same rule for scoped
    roles; it comes after the member step, which has run by then. The one exception is the member
    re-read after a membership-type conversion, which deliberately falls back to the pre-change member
    list with a warning rather than abandoning an item whose PATCH already succeeded.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the unit itself does not exist and
    its creation is skipped under -WhatIf, no child read or write calls are made.

    -EnsureOnly short-circuits all of the above to existence only: it creates the unit when absent
    (emitting a single Created record) and returns immediately without reconciling members, scoped
    roles, other properties, or running any prune pass; when the unit already exists it returns with
    no records at all. The Invoke-OERStructure engine uses this in a pre-pass, ahead of the main
    dispatch loop, to create an administrative unit that a declared group is about to be created into
    (New-OERGroup -AdministrativeUnit) -- the normal dispatch order runs groups before administrative
    units so an AU can reference a group as a member, which would otherwise leave the AU missing on a
    first apply and fail the whole group entry.

    .PARAMETER Item
    One element from the administrativeUnits[] array in the structure document, as a PSCustomObject
    produced by ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current members and scoped roles not in the declared set are removed after a
    ShouldProcess gate. Without this switch, extra items are only reported as Extra and never
    deleted. Both members and scopedRoles follow the same rule Sync-OERStructureGroup's members key
    follows: an omitted key still reconciles against an empty declared set (existing members or
    scoped roles it does not name are pruned/reported same as any other run), but an explicit
    "members": null or "scopedRoles": null does not reconcile that collection at all -- nothing is
    added and nothing is pruned. null -- not an omitted key -- is how an administrative unit is
    declared without touching its members or scoped roles; applying the scalar "omission means
    untouched" rule to these two collections gets this backwards. "[]" and a populated array both
    reconcile normally. In each of members and scopedRoles, while a declared entry cannot be
    resolved to an object id, nothing in that collection is removed or reported Extra: every
    undeclared live entry in it is reported Skipped with a Detail starting "prune withheld:", with or
    without this switch. A lookup that throws aborts the item instead, before that collection's prune.
    A principal's live scoped role whose name the directory role list did not give is never removed,
    and never duplicated by an add, while the document declares a role by name for that principal
    that no live role matches: the declared entry gets one Skipped record instead.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Currently unused by this handler but
    accepted for a uniform Sync-OERStructure* signature.

    .PARAMETER EnsureOnly
    Creates the unit when it is missing and returns immediately, without reconciling members, scoped
    roles, any other property, or running a prune pass; returns with no records at all when the unit
    already exists. Used by the Invoke-OERStructure engine's pre-pass to guarantee an administrative
    unit exists before a declared group is created into it, ahead of the normal groups-before-
    administrativeUnits dispatch order. Every other Sync-OERStructure* handler signature is unchanged
    by this switch.

    .EXAMPLE
    Sync-OERStructureAdministrativeUnit -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one administrative unit entry from the document, pruning undeclared members and
    scoped roles, resolving the caller from the engine PSCmdlet.

    .EXAMPLE
    Sync-OERStructureAdministrativeUnit -Item $DocItem -Caller $PSCmdlet -EnsureOnly
    Creates the administrative unit if it does not already exist and returns immediately; emits
    nothing at all if it is already present.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'TenantAlias is part of the uniform Sync-OERStructure* handler signature; accepted for future use and caller consistency even though this handler does not resolve tenant defaults.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias,
        [switch]$EnsureOnly
    )
    process {
        # A property that is present but NULL counts as UNDECLARED, exactly as the offline validator's
        # Test-HasProp and the Resolve-OERRoleManagementPolicyChange / Resolve-OERAccessReviewChange
        # diffs do. The layers have to agree on what "declared" means: Invoke-OERStructure validates with
        # Test-OERStructureSchema (not Test-Json), so an explicit null reaches this handler. Without the
        # guard, "dynamic": null would cast to $false and convert a live dynamic unit to Assigned, and
        # "hiddenMembership": null would cast to $false and revert a hidden unit to public.
        # An explicitly EMPTY array is still a declared value: "members": [] keeps meaning "no members
        # declared", which is what -Prune removes against.
        # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
        function Test-DeclHas {
            param([object]$Node, [string]$Name)
            Test-OERDeclaredProperty -Node $Node -Name $Name
        }

        # Decision A16: one directory role, two ids. Get-OERDirectoryRoleNameMap keys an activated role
        # by its directoryRole object id AND its role template id, each to the role's display name, so a
        # role declared by one of the two ids is the live membership that carries the other when the map
        # gives both the same name. A GUID or a live RoleId the map does not name matches on the id
        # alone, as before: a name looked up without a key is never a match.
        function Test-SameScopedRole {
            param([string]$DeclaredRole, [string]$LiveRoleId, [hashtable]$RoleNameMap)
            if ([string]::IsNullOrWhiteSpace($LiveRoleId)) { return $false }
            if ($DeclaredRole -eq $LiveRoleId) { return $true }
            if ($null -eq $RoleNameMap) { return $false }
            $DeclaredName = [string]$RoleNameMap[$DeclaredRole]
            if ([string]::IsNullOrWhiteSpace($DeclaredName)) { return $false }
            return ($DeclaredName -eq [string]$RoleNameMap[$LiveRoleId])
        }

        # -- Resolve the display name -------------------------------------------------------
        $Name = $Item.displayName

        # -- Check existence ----------------------------------------------------------------
        $Auid = Resolve-OERAdministrativeUnitId -DisplayName $Name

        # -EnsureOnly stops here when the unit already exists: it exists solely so the engine's
        # pre-pass can create an administrative unit a declared group is about to be created into,
        # before the groups section runs. A unit that already exists needs no action from that
        # pre-pass and emits nothing -- no members, no scoped roles, no property diff, no prune.
        if ($EnsureOnly -and $Auid) {
            return
        }

        # -- Create or update the AU object -------------------------------------------------
        if (-not $Auid) {
            # AU does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create administrative unit')) {
                # Under -WhatIf: emit Skipped for the AU and, outside -EnsureOnly, all children, then
                # return. -EnsureOnly reconciles no children even when the unit is created for real, so
                # its -WhatIf plan does not claim it would configure any either. The pre-pass -EnsureOnly
                # call and the main administrativeUnits pass both reach this branch for the same missing
                # unit under -WhatIf (the pre-pass creates the unit so the group section that names it
                # can succeed; the main pass then still reconciles the unit itself), so the two Skipped
                # records would otherwise be byte-identical and read as a duplicate rather than a
                # sequence. Differentiate -EnsureOnly's wording to say what it is.
                $CreateDetail = if ($EnsureOnly) {
                    "would create administrative unit '$Name' first, so the group that declares it can be created"
                } else {
                    "would create administrative unit $Name"
                }
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail $CreateDetail

                if ((-not $EnsureOnly) -and (Test-DeclHas -Node $Item -Name 'members')) {
                    foreach ($M in @($Item.members)) {
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would configure member '$M' after unit is created"
                    }
                }

                if ((-not $EnsureOnly) -and (Test-DeclHas -Node $Item -Name 'scopedRoles')) {
                    foreach ($Sr in @($Item.scopedRoles)) {
                        $Ref = if (Test-DeclHas -Node $Sr -Name 'principal') { $Sr.principal } else { '?' }
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would configure scopedRole for '$Ref' after unit is created"
                    }
                }
                return
            }

            # Build creation params. Booleans are coerced with [bool] -- the same coercion the update
            # path below uses -- so create and update can never disagree on how a declared value reads.
            $NewParams = @{ DisplayName = $Name; Confirm = $false }
            if ((Test-DeclHas -Node $Item -Name 'restricted') -and ([bool]$Item.restricted)) {
                $NewParams.Restricted = $true
            }
            if (Test-DeclHas -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if ((Test-DeclHas -Node $Item -Name 'dynamic') -and ([bool]$Item.dynamic)) {
                $NewParams.Dynamic = $true
                if (Test-DeclHas -Node $Item -Name 'membershipRule') { $NewParams.MembershipRule = $Item.membershipRule }
                if (Test-DeclHas -Node $Item -Name 'membershipRuleProcessingState') {
                    $NewParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
                }
            }
            if ((Test-DeclHas -Node $Item -Name 'hiddenMembership') -and ([bool]$Item.hiddenMembership)) {
                $NewParams.HiddenMembership = $true
            }

            $Created = $null
            try {
                $Created = New-OERAdministrativeUnit @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "administrative unit creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail 'New-OERAdministrativeUnit returned no object'
                return
            }

            $Auid = $Created.Id
            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Created' -Detail "created administrative unit $Name ($Auid)"

            if ($EnsureOnly) {
                # -EnsureOnly's contract stops at existence: the unit was just created, so no members,
                # scoped roles, or further property reconciliation run in this call.
                return
            }

            # After create: current state is empty
            $CurrentMembers    = @()
            $CurrentScopedRoles = @()
            # A unit created dynamic gets its members from the rule; the member step below must not try
            # to add the declared ones (Graph rejects manual member management on a dynamic unit).
            $EffectiveIsDynamic = $NewParams.ContainsKey('Dynamic')

        } else {
            # AU exists -- diff mutable properties and apply them via Set-OERAdministrativeUnit.
            # membershipType and visibility (in both directions) are applied on this path, per
            # Microsoft Graph v1.0 which documents both as updatable via a direct
            # PATCH /directory/administrativeUnits/{id}. isMemberManagementRestricted is genuinely
            # immutable on Microsoft Graph and can never be changed once the unit is created --
            # recreating the unit is the only route for that one, so it is reported as a visible
            # Skipped record (never as a misleading Unchanged) instead of being silently ignored.
            # A failed read of the live unit is not an empty unit. Get-OERAdministrativeUnit now
            # OMITS a collection whose read failed, and without -ErrorAction Stop that absence
            # collapsed silently to @() below -- so the engine reconciled against an empty current
            # state and reported Created for members that already exist (issue #60, and the caller
            # half of issue #76).
            # Ask ONLY for the collections this document entry can actually consume -- the read is
            # all-or-nothing on purpose, so one unusable endpoint must not fail an item that never
            # needed it. Narrower than the group twin: an ABSENT scopedRoles key still runs the
            # Extra/prune pass below, so only an EXPLICIT null lets the scoped-role read be skipped.
            # -IncludeMembers stays unconditional for the same reason.
            $NeedScopedRoles = -not (Test-OERDeclaredNull -Node $Item -Name 'scopedRoles')
            $Cur = $null
            try {
                $Cur = Get-OERAdministrativeUnit -Id $Auid -IncludeMembers -IncludeScopedRoles:$NeedScopedRoles -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current state of administrative unit '$Name': $($PSItem.Exception.Message); no property, member or scopedRole change was made" `
                    -ErrorRecord $PSItem
                return
            }
            $CurrentMembers    = if ($Cur.Members)     { @($Cur.Members)     } else { @() }
            $CurrentScopedRoles = if ($Cur.ScopedRoles) { @($Cur.ScopedRoles) } else { @() }

            $CurIsDynamic = ([string]$Cur.MembershipType -eq 'Dynamic')
            $CurIsHidden  = ([string]$Cur.Visibility -eq 'HiddenMembership')
            # The membership type in force once this run is done. It stays the live value unless the
            # update below actually applies a membershipType change, so a skipped (-WhatIf) or failed
            # PATCH never makes the member step below act on a type the unit does not have.
            $EffectiveIsDynamic = $CurIsDynamic

            $UpdateParams = @{}
            # Set when a drift Skipped record fires below, so the no-updates branch never also emits a
            # contradictory 'administrative unit properties match' Unchanged for the same unit.
            $DriftReported = $false

            # membershipType: Microsoft Graph v1.0 supports changing it on an existing unit via PATCH,
            # and Set-OERAdministrativeUnit now sends it. A unit converted to Dynamic MUST carry a
            # membership rule in the SAME call -- a dynamic unit with no rule is an invalid state.
            $WantDynamic         = if (Test-DeclHas -Node $Item -Name 'dynamic') { [bool]$Item.dynamic } else { $null }
            $ConvertingToDynamic = ($true -eq $WantDynamic) -and (-not $CurIsDynamic)
            if (($null -ne $WantDynamic) -and ($WantDynamic -ne $CurIsDynamic)) {
                $UpdateParams.MembershipType = $(if ($WantDynamic) { 'Dynamic' } else { 'Assigned' })
            }

            if (Test-DeclHas -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) { $UpdateParams.Description = $Item.description }
            }
            # The rule is diffed on a unit that is already dynamic, and FORCE-carried when this call is
            # the one converting it to dynamic (the live rule is empty in that case, so relying on the
            # diff alone would be fragile).
            if (Test-DeclHas -Node $Item -Name 'membershipRule') {
                if ($ConvertingToDynamic) {
                    $UpdateParams.MembershipRule = [string]$Item.membershipRule
                } elseif ($CurIsDynamic -and ([string]$Cur.MembershipRule -ne [string]$Item.membershipRule)) {
                    $UpdateParams.MembershipRule = [string]$Item.membershipRule
                }
            }
            if (Test-DeclHas -Node $Item -Name 'membershipRuleProcessingState') {
                if ($ConvertingToDynamic) {
                    $UpdateParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
                } elseif ($CurIsDynamic -and ([string]$Cur.MembershipRuleProcessingState -ne [string]$Item.membershipRuleProcessingState)) {
                    $UpdateParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
                }
            }
            # A conversion to Dynamic with no rule declared anywhere would produce an invalid unit.
            # Set-OERAdministrativeUnit re-checks this against the LIVE unit and fails with
            # MembershipRuleRequired; report it here as Failed rather than firing a doomed call.
            # Every rule key above was FORCE-carried by $ConvertingToDynamic, so it has to go with the
            # abandoned conversion: leaving membershipRuleProcessingState behind would PATCH a rule
            # setting onto a unit that stays Assigned (where it is meaningless) and report Updated
            # alongside this Failed.
            if ($ConvertingToDynamic -and -not $UpdateParams.ContainsKey('MembershipRule') -and -not $Cur.MembershipRule) {
                $DriftReported = $true
                $UpdateParams.Remove('MembershipType')
                $UpdateParams.Remove('MembershipRule')
                $UpdateParams.Remove('MembershipRuleProcessingState')
                Write-Warning "Sync-OERStructureAdministrativeUnit: unit '$Name' declares dynamic=true but neither the document nor the live unit supplies a membershipRule; a dynamic unit requires one. Declare membershipRule alongside dynamic."
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' `
                    -Detail "declared 'dynamic' true but no membershipRule is declared and the live unit has none; a dynamic administrative unit requires a membership rule"
            }

            # visibility: Graph v1.0 documents visibility as updatable, with null meaning public.
            # Set-OERAdministrativeUnit translates 'Public' to that null, so both directions apply here.
            if (Test-DeclHas -Node $Item -Name 'hiddenMembership') {
                $WantHidden = [bool]$Item.hiddenMembership
                if ($WantHidden -and -not $CurIsHidden) {
                    $UpdateParams.Visibility = 'HiddenMembership'
                } elseif (-not $WantHidden -and $CurIsHidden) {
                    $UpdateParams.Visibility = 'Public'
                }
            }

            # isMemberManagementRestricted drift -- genuinely immutable on Microsoft Graph; recreation
            # is the only route.
            if ((Test-DeclHas -Node $Item -Name 'restricted') -and ([bool]$Item.restricted -ne [bool]$Cur.IsMemberManagementRestricted)) {
                $DriftReported = $true
                Write-Warning "Sync-OERStructureAdministrativeUnit: unit '$Name' declares restricted=$([bool]$Item.restricted) but the live unit is restricted=$([bool]$Cur.IsMemberManagementRestricted); isMemberManagementRestricted is immutable on Microsoft Graph and can never be changed after creation -- recreating the administrative unit is the only way to change it."
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' `
                    -Detail "declared 'restricted' ($([bool]$Item.restricted)) differs from the live unit ($([bool]$Cur.IsMemberManagementRestricted)); isMemberManagementRestricted is immutable on Microsoft Graph -- recreating the administrative unit is the only way to change it"
            }

            if ($UpdateParams.Count -gt 0) {
                if ($Caller.ShouldProcess($Name, "Update administrative unit properties ($($UpdateParams.Keys -join ', '))")) {
                    try {
                        Set-OERAdministrativeUnit -Id $Auid @UpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        if ($UpdateParams.ContainsKey('MembershipType')) {
                            $EffectiveIsDynamic = ([string]$UpdateParams.MembershipType -eq 'Dynamic')
                            if (-not $EffectiveIsDynamic) {
                                # Converting a dynamic unit back to Assigned freezes whatever the rule
                                # last produced, so the member list read BEFORE the PATCH is stale.
                                # Re-read it so the reconciliation below diffs against reality; keep the
                                # pre-PATCH list if the re-read fails rather than aborting the item.
                                try {
                                    $Refreshed      = Get-OERAdministrativeUnit -Id $Auid -IncludeMembers -ErrorAction Stop
                                    $CurrentMembers = if ($Refreshed.Members) { @($Refreshed.Members) } else { @() }
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    Write-Warning "Sync-OERStructureAdministrativeUnit: could not re-read the members of unit '$Name' after the membership type change; reconciling against the pre-change member list."
                                }
                            }
                        }
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Updated' -Detail "updated administrative unit properties ($($UpdateParams.Keys -join ', '))"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "administrative unit update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would update administrative unit properties ($($UpdateParams.Keys -join ', '))"
                }
            } elseif (-not $DriftReported) {
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Unchanged' -Detail 'administrative unit properties match'
            }
        }

        # -- Step 2: members ----------------------------------------------------------------
        # Manual member management is DISABLED by Microsoft Graph on a dynamic administrative unit: the
        # rule for dynamic membership groups retains sole ownership of adding and removing members, so
        # Add-/Remove-OERAdministrativeUnitMember are rejected, and switching a unit to dynamic can change
        # its existing membership on its own (which would also make the member list read before the
        # conversion PATCH wrong). Reconciling members there would fire doomed calls and report stale
        # Unchanged rows, so a dynamic unit -- whether it was already dynamic or this run converted it --
        # gets a visible Skipped record per declared member instead, and no Extra/prune pass at all.
        $DeclaredMemberIds = [System.Collections.Generic.List[string]]::new()
        $DeclaredMembers   = if (Test-DeclHas -Node $Item -Name 'members') { @($Item.members) } else { @() }
        # An omitted 'members' key has always meant "no add-list, but the prune/Extra loop below
        # still runs against whatever it finds" -- that is intentional, existing, tested behavior
        # (an absent collection is not an instruction to leave live state alone; only an EXPLICIT
        # null is). So the add loop above is gated on Test-DeclHas (skips on both absent and null),
        # while the prune/Extra loop below is gated on the narrower $MembersDeclaredNull so it keeps
        # running when the key is merely absent and only backs off on an explicit null.
        $MembersDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'members'

        if ($EffectiveIsDynamic) {
            foreach ($MRef in $DeclaredMembers) {
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' `
                    -Detail "member '$MRef' was not reconciled: administrative unit '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be added or removed manually. Change the rule (membershipRule) to change the membership"
            }
            if ($DeclaredMembers.Count -eq 0 -and $CurrentMembers.Count -gt 0) {
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' `
                    -Detail "the $($CurrentMembers.Count) current member(s) were not reconciled: administrative unit '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be removed manually, so -Prune does not apply to them"
            }
        } else {
            # A declared member that cannot be resolved carries no id, so it cannot protect its live
            # counterpart from the Extra/prune loop below; while this list is non-empty that loop
            # withholds every candidate (ConvertTo-OERPruneWithheldResult owns the rule).
            $MemberUnresolved = [System.Collections.Generic.List[string]]::new()
            foreach ($MRef in $DeclaredMembers) {
                $Mid = Resolve-OERStructurePrincipal -Reference $MRef
                if (-not $Mid) {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve principal '$MRef' to an object id."),
                        'PrincipalNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $MRef
                    )
                    $Caller.WriteError($ErrRec)
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "could not resolve member '$MRef'" -ErrorRecord $ErrRec
                    $MemberUnresolved.Add($MRef)
                    continue
                }
                $DeclaredMemberIds.Add($Mid)

                $AlreadyMember = $CurrentMembers | Where-Object { $_.Id -eq $Mid }
                if ($AlreadyMember) {
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Unchanged' -Detail "member '$MRef' already present"
                } else {
                    if ($Caller.ShouldProcess($Name, "Add member '$Mid'")) {
                        try {
                            Add-OERAdministrativeUnitMember -Id $Auid -MemberId $Mid -Confirm:$false -ErrorAction Stop
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Updated' -Detail "added member '$MRef'"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "failed to add member '$MRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would add member '$MRef'"
                    }
                }
            }

            # Extra/prune undeclared current members. Skipped ONLY when 'members' is explicitly null --
            # an omitted key still reconciles against an empty declared set (existing behavior), but an
            # explicit null is a distinct "leave membership alone" signal and must not report every live
            # member as Extra or, worse under -Prune, remove them all.
            if (-not $MembersDeclaredNull) {
                foreach ($CurMember in $CurrentMembers) {
                    $CurId = $CurMember.Id
                    if ($DeclaredMemberIds -notcontains $CurId) {
                        $Withheld = ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item $Name -Unresolved $MemberUnresolved -Candidate "undeclared member '$CurId'"
                        if ($Withheld) { $Withheld; continue }
                        if ($Prune) {
                            $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                            Write-Warning "Sync-OERStructureAdministrativeUnit: $PruneVerb undeclared member '$CurId' from unit '$Name'."
                            if ($Caller.ShouldProcess($Name, "Remove undeclared member '$CurId'")) {
                                try {
                                    Remove-OERAdministrativeUnitMember -Id $Auid -MemberId $CurId -Confirm:$false -ErrorAction Stop
                                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Removed' -Detail "removed undeclared member '$CurId'"
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    $Caller.WriteError($PSItem)
                                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "failed to remove member '$CurId': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                    continue
                                }
                            } else {
                                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would remove undeclared member '$CurId'"
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Extra' -Detail "undeclared member '$CurId' (use -Prune to remove)"
                        }
                    }
                }
            }
        }

        # -- Step 3: scopedRoles ------------------------------------------------------------
        # Build a set of declared (Role, PrincipalId) pairs for present-check and prune. Role holds
        # WHATEVER THE DOCUMENT DECLARED -- a directory role display name or, when the role name could
        # not be resolved on read, a role id GUID -- so it is matched against both the live RoleName
        # and the live RoleId below (a GUID through the directory role name map too, decision A16).
        $DeclaredScopedRoles = [System.Collections.Generic.List[PSCustomObject]]::new()
        # Same rule as $MemberUnresolved above: a declared scopedRole whose principal cannot be
        # resolved withholds every scopedRole candidate in the Extra/prune loop below.
        $ScopedRoleUnresolved = [System.Collections.Generic.List[string]]::new()
        # Same rule as $MembersDeclaredNull above: an omitted 'scopedRoles' key still reconciles
        # against an empty declared set (existing, tested behavior), while an explicit null is a
        # distinct "leave scoped roles alone" signal. The add loop below is already gated on
        # Test-DeclHas (skips on both absent and null); the prune/Extra loop is gated on the
        # narrower $ScopedRolesDeclaredNull so it keeps running when the key is merely absent and
        # only backs off on an explicit null.
        $ScopedRolesDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'scopedRoles'

        # A live scoped role whose name the directory role list did not give (RoleName blank, RoleId
        # known) cannot be matched to a role the document declares by NAME. Under such a declaration for
        # the same principal it may be that very role, so neither side is touched (decision A8): no add,
        # and the unnamed role is kept out of the Extra/prune pass below. The declared side emits the one
        # Skipped row; ConvertTo-OERPruneWithheldResult owns its text.
        $UnnamedLiveRoles = @($CurrentScopedRoles | Where-Object {
                [string]::IsNullOrWhiteSpace([string]$_.RoleName) -and -not [string]::IsNullOrWhiteSpace([string]$_.RoleId)
            })
        $ClaimedUnnamedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Decision A16: a role declared by GUID is matched through the directory role name map too
        # (Test-SameScopedRole). The map is read once per unit, and only when it can change a match: the
        # document declares at least one scoped role by GUID, and the unit holds at least one live scoped
        # role whose name the reader gave (an unnamed one is not in the map, so it matches on its id
        # alone). A map that cannot be read is not an empty map: the item is Failed and no scoped role is
        # added or removed, the rule the read of the live unit above follows.
        $RoleNameMap = $null
        $DeclaresGuidRole = (Test-DeclHas -Node $Item -Name 'scopedRoles') -and
            (@(@($Item.scopedRoles) | Where-Object { $null -ne $_ -and (Test-OERGuid -Value ([string]$_.role)) }).Count -gt 0)
        $HasNamedLiveRole = @($CurrentScopedRoles | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.RoleName) }).Count -gt 0
        if ($DeclaresGuidRole -and $HasNamedLiveRole) {
            try {
                $RoleNameMap = Get-OERDirectoryRoleNameMap -ThrowOnFailure
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the directory roles that match a scopedRole declared by role id: $($PSItem.Exception.Message); no scopedRole was added or removed" `
                    -ErrorRecord $PSItem
                return
            }
        }

        if (Test-DeclHas -Node $Item -Name 'scopedRoles') {
            foreach ($SrEntry in @($Item.scopedRoles)) {
                $SrRole = $SrEntry.role
                $SrRef  = $SrEntry.principal
                $SrId   = Resolve-OERStructurePrincipal -Reference $SrRef
                if (-not $SrId) {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve scopedRole principal '$SrRef' to an object id."),
                        'PrincipalNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $SrRef
                    )
                    $Caller.WriteError($ErrRec)
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "could not resolve scopedRole principal '$SrRef'" -ErrorRecord $ErrRec
                    $ScopedRoleUnresolved.Add($SrRef)
                    continue
                }

                # A directory role is declared either by display name or -- when the directory role name
                # map has no name for it -- by its role id. Match on whichever the live membership
                # exposes so a GUID-declared role is never re-added or pruned: a GUID matches a live
                # RoleId equal to it, or one the name map gives the same name (Test-SameScopedRole,
                # decision A16), so a role declared by its template id matches the live membership that
                # carries its object id, and the other way round. A name map that cannot be read at all
                # never reaches this match: Get-OERAdministrativeUnit then leaves ScopedRoles unread and
                # the read above fails the item, so no role is pruned for want of a name. A map
                # that IS read but does not list a live role's id gives that role RoleName '' with its
                # RoleId kept; a role declared by name never matches it here, so the unnamed-role guard
                # below keeps such a role from being added a second time and then pruned.
                $SrIsGuid = Test-OERGuid -Value ([string]$SrRole)

                $DeclaredScopedRoles.Add([PSCustomObject]@{ Role = $SrRole; PrincipalId = $SrId; IsGuid = $SrIsGuid })

                $AlreadyScoped = $CurrentScopedRoles | Where-Object {
                    $_.PrincipalId -eq $SrId -and
                    (($_.RoleName -eq $SrRole) -or ($SrIsGuid -and (Test-SameScopedRole -DeclaredRole ([string]$SrRole) -LiveRoleId ([string]$_.RoleId) -RoleNameMap $RoleNameMap)))
                }
                if ($AlreadyScoped) {
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Unchanged' -Detail "scopedRole '$SrRole' for '$SrRef' already present"
                } else {
                    # A role declared by role id is matched on its id above (an unnamed live role is not
                    # in the name map, so it matches on its id alone), so only a NAME declaration can be
                    # one of the principal's unnamed live roles.
                    if (-not $SrIsGuid) {
                        $PrincipalUnnamed = @($UnnamedLiveRoles | Where-Object { $_.PrincipalId -eq $SrId })
                        if ($PrincipalUnnamed.Count -gt 0) {
                            foreach ($Unnamed in $PrincipalUnnamed) {
                                $null = $ClaimedUnnamedKeys.Add("$($Unnamed.PrincipalId)|$($Unnamed.RoleId)|$($Unnamed.ScopedRoleMembershipId)")
                            }
                            ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item $Name `
                                -Declared "scopedRole '$SrRole' for '$SrRef'" `
                                -UnnamedRoleId @($PrincipalUnnamed | ForEach-Object { [string]$_.RoleId })
                            continue
                        }
                    }
                    if ($Caller.ShouldProcess($Name, "Add scopedRole '$SrRole' for '$SrId'")) {
                        $ScopedRoleParams = @{ Id = $Auid; PrincipalId = $SrId; Confirm = $false }
                        if ($SrIsGuid) { $ScopedRoleParams.RoleId = $SrRole } else { $ScopedRoleParams.RoleName = $SrRole }
                        try {
                            Add-OERAdministrativeUnitScopedRole @ScopedRoleParams -ErrorAction Stop | Out-Null
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Updated' -Detail "added scopedRole '$SrRole' for '$SrRef'"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "failed to add scopedRole '$SrRole' for '$SrRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would add scopedRole '$SrRole' for '$SrRef'"
                    }
                }
            }
        }

        # Extra/prune undeclared current scoped roles. Skipped ONLY when 'scopedRoles' is explicitly
        # null -- an omitted key still reconciles against an empty declared set (existing behavior),
        # but an explicit null is a distinct "leave scoped roles alone" signal and must not report
        # every live scoped role as Extra or, worse under -Prune, remove them all.
        if (-not $ScopedRolesDeclaredNull) {
            foreach ($CurSr in $CurrentScopedRoles) {
                if ($ClaimedUnnamedKeys.Contains("$($CurSr.PrincipalId)|$($CurSr.RoleId)|$($CurSr.ScopedRoleMembershipId)")) { continue }
                # A role declared by GUID also covers the live membership the name map gives the same
                # name (decision A16), so it is not removed for carrying the role's other id.
                $IsDeclared = $DeclaredScopedRoles | Where-Object {
                    $_.PrincipalId -eq $CurSr.PrincipalId -and
                    (($_.Role -eq $CurSr.RoleName) -or ($CurSr.RoleId -and $_.Role -eq [string]$CurSr.RoleId) -or
                        ($_.IsGuid -and (Test-SameScopedRole -DeclaredRole ([string]$_.Role) -LiveRoleId ([string]$CurSr.RoleId) -RoleNameMap $RoleNameMap)))
                }
                if (-not $IsDeclared) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item $Name -Unresolved $ScopedRoleUnresolved -Candidate "undeclared scopedRole '$($CurSr.RoleName)' for '$($CurSr.PrincipalId)'"
                    if ($Withheld) { $Withheld; continue }
                    if ($Prune) {
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureAdministrativeUnit: $PruneVerb undeclared scopedRole '$($CurSr.RoleName)' (principal '$($CurSr.PrincipalId)') from unit '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared scopedRole '$($CurSr.RoleName)' for '$($CurSr.PrincipalId)'")) {
                            try {
                                Remove-OERAdministrativeUnitScopedRole -Id $Auid -ScopedRoleMembershipId $CurSr.ScopedRoleMembershipId -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop
                                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Removed' -Detail "removed undeclared scopedRole '$($CurSr.RoleName)' (principal '$($CurSr.PrincipalId)')"
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Failed' -Detail "failed to remove scopedRole '$($CurSr.RoleName)': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Skipped' -Detail "would remove undeclared scopedRole '$($CurSr.RoleName)' for '$($CurSr.PrincipalId)'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Name -Action 'Extra' -Detail "undeclared scopedRole '$($CurSr.RoleName)' for '$($CurSr.PrincipalId)' (use -Prune to remove)"
                    }
                }
            }
        }
    }
}
