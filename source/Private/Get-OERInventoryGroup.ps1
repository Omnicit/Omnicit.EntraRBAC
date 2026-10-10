function Get-OERInventoryGroup {
    <#
    .SYNOPSIS
    Reads the groups an inventory's Groups section holds, with their members, owners, PIM
    eligibility and PIM policy, and projects each as an apply-document entry.

    .DESCRIPTION
    The single owner of the inventory's Groups section. Get-OERInventory calls it to fill that
    section and replays the unread names and the causes it returns through its own lists.
    Export-OERInventory calls it directly, with -RelevantOnly unless -AllGroupsDetailed is given.

    By default it makes ONE Get-OERGroup call carrying the members, owners and PIM eligibility
    switches and the filter it is given, then projects each group as an apply-document entry: an
    explicit null for a members read that failed, the PIM-for-Groups pimPolicy only for a group that
    Test-OERGroupPimInUse finds in use, and onPremisesSynced only for a group synchronized from
    on-premises. A failed read is never an empty fact: it is named in the Unread list and its cause
    is kept in the Causes list.

    With -RelevantOnly the Get-OERGroup call carries the filter alone, and each listed group is first
    asked, in at most two requests, whether it is RBAC-relevant: its PIM eligibility, and, for a
    group that is not role-assignable and has none, the Test-OERGroupPimInUse criterion. A group
    that is neither role-assignable nor eligible nor found in use (nor synchronized from on-premises,
    under -IncludeSyncedGroups) costs exactly those two requests and is not returned. Every other
    group has its members and owners read one collection at a time (Read-OERGroupCollection) and is
    projected exactly as a full read projects it, the criterion's answer reused rather than asked
    again. A group whose relevance could not be read -- its eligibility or the criterion failed --
    is read in full and projected the same way, and the failure is named exactly as a full read
    names it.

    With -ExcludeSharedName a group whose display name another listed group shares, compared without
    regard to letter case, is left out in either mode, and the name is reported once, with the
    spelling of the first such group, in the Unread list ('groups/<name>') and with the
    Get-OERSharedNameCause text in the Causes list. The names are counted over every listed group,
    so a group -RelevantOnly does not keep still makes its name shared.

    It returns ONE tagged Omnicit.EntraRBAC.InventoryGroupRead object and never writes an error
    record. It writes a warning for a group list that could not be read, and its verbose lines carry
    the 'Get-OERInventory: ' prefix, so an inventory's verbose output reads the same wherever the
    line came from.
    - Groups: the projections, in list order.
    - Unread: the collection names that could not be read, in the order they were found ('groups'
      for the list itself, 'groups/<name>/members' and so on for a collection), exactly as the
      InventoryPartial message names them.
    - Causes: the raw causes behind them, in the order they were found, each an object with a Cause
      (the message) and a Target (the failing object's id, or an empty string). A blank cause is
      never added. Format-OERUnreadCauseClause turns them into the clause of the partial message.

    The calling command must already have signed in (Initialize-OERAuth); this function makes no
    sign-in of its own.

    .PARAMETER Filter
    The OData filter sent to Get-OERGroup, exactly as given. Get-OERInventory passes its -GroupFilter,
    or 'securityEnabled eq true' when it has none.

    .PARAMETER IncludeId
    Stamp each projection, and each eligibility entry of it, with its id.

    .PARAMETER PrincipalNameCache
    The caller's id to display name cache for principals. Eligibility principals are resolved through
    it and what is learned is left in it, so the caller's other sections share the lookups. A new,
    empty cache is used when none is given.

    .PARAMETER RelevantOnly
    Decide first which groups are RBAC-relevant (role-assignable, with PIM eligibility, or found to
    use PIM for Groups), and read the members, owners and PIM policy of those groups only, and of
    every group whose relevance could not be read.

    .PARAMETER IncludeSyncedGroups
    With -RelevantOnly, also keep every group synchronized from on-premises
    (Test-OERGroupOnPremisesSynced). Without -RelevantOnly every group is read in full already, and
    this switch changes nothing.

    .PARAMETER ExcludeSharedName
    Leave out every group whose display name another listed group shares, compared without regard to
    letter case, and report each such name once in the Unread and Causes lists.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -PrincipalNameCache $Cache
    $Read.Groups.Count
    Reads the security-enabled groups with their members, owners, eligibility and PIM policy, and
    returns the projections together with the collections that could not be read and why.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -IncludeId -ExcludeSharedName -RelevantOnly
    Reads only the RBAC-relevant security-enabled groups in full, after at most two requests per
    listed group, stamps their ids, and leaves out every group whose name another shares.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [switch]$IncludeId,

        [hashtable]$PrincipalNameCache = @{},

        [switch]$RelevantOnly,

        [switch]$IncludeSyncedGroups,

        [switch]$ExcludeSharedName
    )

    # What the read below records into: the projections, the unread collection names and the causes.
    # $Causes keeps every cause RAW (the message and the id it was about): the caller replays them
    # through its own list, and the clause is built where the partial message is, from all sections.
    $Groups            = [System.Collections.Generic.List[object]]::new()
    $UnreadCollections = [System.Collections.Generic.List[string]]::new()
    $Causes            = [System.Collections.Generic.List[object]]::new()
    function Add-UnreadCause {
        param(
            [string]$Cause,
            [string]$Target
        )
        if ([string]::IsNullOrWhiteSpace($Cause)) { return }
        $Causes.Add([PSCustomObject]@{ Cause = $Cause; Target = $Target })
    }
    # A section whose LIST could not be read at all is named by its own key, once however many
    # records the failed read produced (the same rule as Get-OERInventory's function of this name).
    function Add-UnreadSection {
        param([string]$Key, [string]$Cause)
        Write-Verbose "Get-OERInventory: $Cause"
        Add-UnreadCause -Cause $Cause
        if (-not $UnreadCollections.Contains($Key)) { $UnreadCollections.Add($Key) }
    }

    # A full read lists the groups with all three collections attached. A relevant-only read lists
    # them alone: the collections are read group by group in the projection loop below, so a group
    # that turns out not to be RBAC-relevant never costs a members or owners request.
    $GroupParams = if ($RelevantOnly) {
        @{ Filter = $Filter }
    } else {
        @{ IncludeMembers = $true; IncludePimEligibility = $true; IncludeOwners = $true; Filter = $Filter }
    }
    $GroupItems = @()
    # -ErrorAction SilentlyContinue + -ErrorVariable, not -ErrorAction Stop: Get-OERGroup now
    # writes a non-terminating error per group whose members, owners or eligibility read
    # failed, and Stop would abort the whole enumeration on the first one -- losing every
    # remaining group instead of losing one collection. The errors are inspected below, so
    # nothing is suppressed; SilentlyContinue here means "captured", not "ignored".
    $GroupReadErrors = $null
    # The try/catch still guards a genuinely TERMINATING failure of the whole read (auth,
    # a dead transport, an -ErrorAction Stop upstream); the inner loop handles the
    # NON-terminating per-group records. Both are needed: neither subsumes the other.
    try {
        $GroupItems = @(Get-OERGroup @GroupParams -ErrorAction SilentlyContinue -ErrorVariable GroupReadErrors)
        foreach ($GErr in @($GroupReadErrors)) {
            if ($null -eq $GErr) { continue }
            # No Remove-OERErrorRecord here: these records were WRITTEN deliberately by
            # Get-OERGroup (which already scrubbed the raw transport record behind each one),
            # not swallowed by a catch. Scrubbing a reported diagnostic would hide it.
            if ($GErr.FullyQualifiedErrorId -like 'GroupNotFound*') { continue }
            # Per-collection failures are accounted for at the projection below, where the
            # affected group is known by name; only anything else warrants a section warning.
            if ($GErr.FullyQualifiedErrorId -like 'GroupMemberReadFailed*' -or
                $GErr.FullyQualifiedErrorId -like 'GroupOwnerReadFailed*' -or
                $GErr.FullyQualifiedErrorId -like 'GroupPimEligibilityReadFailed*') {
                # Keep the CAUSE. Get-OERGroup composed the transport reason into this
                # message and it lives nowhere else once the record is dropped here.
                $GroupCause = [string]$GErr.Exception.Message
                Write-Verbose "Get-OERInventory: $GroupCause"
                Add-UnreadCause -Cause $GroupCause -Target ([string]$GErr.TargetObject)
                continue
            }
            # Warn only for a record Get-OERGroup itself PUBLISHED. -ErrorVariable is filled
            # by the ENGINE and also collects records raised inside nested calls -- the Graph
            # SDK's own, several of them empty, one of them the raw bearer-carrying request
            # record -- even when an inner catch swallowed them. Warning on those produced
            # eight spurious lines per failed read on a live tenant (about 72 in one run) and
            # buried the real signal. A published record carries the calling cmdlet's name as
            # a comma-separated segment of the FullyQualifiedErrorId; a stray does not.
            # Filtering on the error id instead would need widening for every id ever added
            # and would still admit every stray, so the test is the publisher, not the id.
            # Membership, not a suffix match: Write-Error appends a further name when a
            # record is republished, so the cmdlet's name is not always the last segment.
            if (@(([string]$GErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERGroup') {
                Write-Warning "Could not read groups: $($GErr.Exception.Message)"
                # The warning stays; the section is ALSO counted unread, since the groups array
                # below is [] whether the tenant has none or the list could not be read.
                Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($GErr.Exception.Message)"
            } else {
                # Routed to verbose rather than dropped: a stray is still evidence when a read
                # misbehaves, it just is not a section-level finding the operator must act on.
                Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading groups " +
                    "($($GErr.FullyQualifiedErrorId)): $($GErr.Exception.Message)")
            }
        }
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        if ($PSItem.FullyQualifiedErrorId -notlike 'GroupNotFound*') {
            Write-Warning "Could not read groups: $($PSItem.Exception.Message)"
            Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($PSItem.Exception.Message)"
        }
    }

    # -ExcludeSharedName: how many listed groups carry each display name, compared without regard to
    # letter case -- the key the validator refuses a duplicate on (Test-OERStructureSchema), so a pair
    # it would refuse is never written. Counted over EVERY listed group, before the relevance
    # decision below, because the name is shared whether or not the namesake is RBAC-relevant: two
    # live groups answer that name, so the apply engine refuses it either way, and a read that kept
    # only the relevant one would write an entry that cannot be applied.
    $SharedNameCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($ExcludeSharedName) {
        foreach ($G in $GroupItems) {
            $NameKey = [string]$G.DisplayName
            $SharedNameCount[$NameKey] = 1 + $(if ($SharedNameCount.ContainsKey($NameKey)) { $SharedNameCount[$NameKey] } else { 0 })
        }
    }

    # Project one access-type policy object from a Get-OERGroupPimPolicy result, or $null when
    # the group carries no policy for that access type. The block is emitted whenever ANY
    # meaningful field is present -- gating it on activationMaxHours alone used to discard a
    # policy that was customized only for permanence, expiration, enablement or notifications.
    function Convert-PimAccessProjection {
        param([object]$Policy)
        if (-not $Policy) { return $null }
        $Block = [ordered]@{}
        if ($null -ne $Policy.ActivationMaxHours) { $Block.activationMaxHours = $Policy.ActivationMaxHours }
        if ($Policy.AuthenticationContextId) { $Block.authenticationContextId = $Policy.AuthenticationContextId }
        # ConvertTo-OERGroupPimPolicy wraps ActivationEnabledRules/ActiveEnabledRules with a
        # null-filter (its own comment at ConvertTo-OERGroupPimPolicy.ps1:67-73), so a rule
        # the tenant never configured and a rule that is genuinely empty BOTH read back as
        # @() here -- $null -ne cannot tell "unread" from "read and empty" on these two
        # properties, and neither can Count -gt 0 alone. Fall back to the raw rule set
        # carried on Rules: when the canonical rule id IS present the policy was actually
        # read and the list is genuinely empty, so emit an explicit [] (security-relevant:
        # no MFA, justification or ticket is required on activation). When the rule id is
        # absent too, the policy never carried it -- omit, same as before.
        $HasActivationRule = @($Policy.Rules |
            Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }).Count -gt 0
        if (@($Policy.ActivationEnabledRules).Count -gt 0 -or $HasActivationRule) {
            $Block.activationEnablement = @($Policy.ActivationEnabledRules)
        }
        if ($null -ne $Policy.AllowPermanentEligibility) { $Block.allowPermanentEligibility = [bool]$Policy.AllowPermanentEligibility }
        if ($Policy.EligibleDurationDays) { $Block.eligibleDurationDays = [int]$Policy.EligibleDurationDays }
        if ($null -ne $Policy.AllowPermanentActive) { $Block.allowPermanentActive = [bool]$Policy.AllowPermanentActive }
        if ($Policy.ActiveDurationDays) { $Block.activeDurationDays = [int]$Policy.ActiveDurationDays }
        $HasActiveRule = @($Policy.Rules |
            Where-Object { $_.id -eq 'Enablement_Admin_Assignment' }).Count -gt 0
        if (@($Policy.ActiveEnabledRules).Count -gt 0 -or $HasActiveRule) {
            $Block.activeEnablement = @($Policy.ActiveEnabledRules)
        }
        if ($null -ne $Policy.RequireApproval) { $Block.requireApproval = [bool]$Policy.RequireApproval }
        # Approvers project as object ids, the same as the roleManagementPolicies projection:
        # an id resolves verbatim through the apply engine's declared-approver resolution,
        # whereas a display name may not. Exported only while approval is required, since the
        # apply engine ignores declared approvers whenever requireApproval is false and
        # Test-OERStructureSchema would otherwise warn about that combination on every
        # exported document that carries an approval-gated policy.
        if ($Policy.RequireApproval -eq $true) {
            $PimApproverUser  = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
            $PimApproverGroup = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
            if ($PimApproverUser.Count -gt 0 -or $PimApproverGroup.Count -gt 0) {
                $PimApproverProj = [ordered]@{}
                if ($PimApproverUser.Count -gt 0)  { $PimApproverProj.users = $PimApproverUser }
                if ($PimApproverGroup.Count -gt 0) { $PimApproverProj.groups = $PimApproverGroup }
                $Block.approvers = [PSCustomObject]$PimApproverProj
            }
        }
        $Notif = [ordered]@{}
        if ($Policy.Notifications) {
            if (@($Policy.Notifications.EligibleAlert).Count -gt 0)   { $Notif.eligibleAlert = @($Policy.Notifications.EligibleAlert) }
            if (@($Policy.Notifications.ActiveAlert).Count -gt 0)     { $Notif.activeAlert = @($Policy.Notifications.ActiveAlert) }
            if (@($Policy.Notifications.ActivationAlert).Count -gt 0) { $Notif.activationAlert = @($Policy.Notifications.ActivationAlert) }
        }
        if ($Notif.Count -gt 0) { $Block.notifications = [PSCustomObject]$Notif }
        if ($Block.Count -eq 0) { return $null }
        [PSCustomObject]$Block
    }

    # Asks Test-OERGroupPimInUse (the single owner of the criterion) whether one group uses PIM for
    # Groups, and returns the answer or the failure instead of recording either: the projection
    # below records the failure, with the group known by name, and a decision that is already made
    # can be reused without a second request. The catch scrubs first, as every transport-reaching
    # catch does; a failed criterion is never guessed in either direction.
    function Get-PimUsageDecision {
        param([object]$Group, [int]$EligibilityCount)
        try {
            [PSCustomObject]@{ Usage = (Test-OERGroupPimInUse -GroupId $Group.Id -EligibilityCount $EligibilityCount); Failed = $false; Message = $null }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            [PSCustomObject]@{ Usage = $null; Failed = $true; Message = [string]$PSItem.Exception.Message }
        }
    }
    # The criterion's answers already obtained for a group id, as Get-PimUsageDecision returns them.
    # The relevance decision under -RelevantOnly fills it for a group it had to ask, and the
    # projection reuses an entry instead of asking again, so no group's criterion is read twice.
    $PimUsageDecided = @{}

    foreach ($G in $GroupItems) {
        if ($RelevantOnly) {
            $GroupId = [string]$G.Id
            # THE FIRST REQUEST: the eligibility, which is both a relevance criterion and a collection
            # the projection needs. Kept on the group as Get-OERGroup would attach it, or recorded
            # exactly as Get-OERGroup's own record would have been: the cause here, and the
            # projection below names the collection, since the property stays absent.
            $EligRead = Read-OERGroupCollection -GroupId $GroupId -Collection PimEligibility
            if ($EligRead.Read) {
                $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue $EligRead.Value -Force
            } else {
                Write-Verbose "Get-OERInventory: $($EligRead.Message)"
                Add-UnreadCause -Cause $EligRead.Message -Target $GroupId
            }
            # A role-assignable group is relevant on its own, and so is a synchronized group when the
            # caller asked for them; neither needs the criterion to be kept.
            $Kept = ($G.IsAssignableToRole -eq $true) -or ($IncludeSyncedGroups -and (Test-OERGroupOnPremisesSynced -Group $G))
            if (-not $Kept) {
                # The null-filter is load-bearing, as in the projection below: @($null).Count is 1.
                $RelevantEligCount = if ($EligRead.Read) { @($EligRead.Value | Where-Object { $null -ne $_ }).Count } else { 0 }
                if ($RelevantEligCount -eq 0) {
                    # THE SECOND REQUEST: the criterion, decided here once and reused by the
                    # projection. A group with eligibility needs no request for it (the eligibility
                    # decides "in use" on its own), so it is asked only for a group without any.
                    $PimUsageDecided[$GroupId] = Get-PimUsageDecision -Group $G -EligibilityCount 0
                    $InUse = ($null -ne $PimUsageDecided[$GroupId].Usage -and [bool]$PimUsageDecided[$GroupId].Usage.InUse)
                    # R2: a group whose relevance could not be read -- its eligibility read failed, so
                    # its count is 0 by default rather than by measurement, or the criterion failed --
                    # is never guessed to be irrelevant. It is read in full below, exactly as a full
                    # read would have read it, and the projection names what could not be read.
                    $Undecided = (-not $EligRead.Read) -or $PimUsageDecided[$GroupId].Failed
                    # Not relevant, and known not to be: the two requests above are all this group
                    # costs. No members, owners or policy request is made for it, and it is not
                    # returned (the export would not keep it in inventory.json either).
                    if (-not $InUse -and -not $Undecided) { continue }
                }
            }
            # Every other group -- kept, eligible, found in use, or undecided -- gets the two
            # collections a full read attaches, one at a time and recorded the same way as the
            # eligibility above.
            foreach ($RelevantCollection in @('Members', 'Owners')) {
                $RelevantRead = Read-OERGroupCollection -GroupId $GroupId -Collection $RelevantCollection
                if ($RelevantRead.Read) {
                    $G | Add-Member -NotePropertyName $RelevantCollection -NotePropertyValue $RelevantRead.Value -Force
                } else {
                    Write-Verbose "Get-OERInventory: $($RelevantRead.Message)"
                    Add-UnreadCause -Cause $RelevantRead.Message -Target $GroupId
                }
            }
        }

        $Proj = [ordered]@{
            displayName    = $G.DisplayName
            roleAssignable = [bool]$G.IsAssignableToRole
            dynamic        = ($G.GroupType -eq 'Dynamic')
            description    = $G.Description
        }
        # A15: information only. Written as true for a group synchronized from on-premises
        # (Test-OERGroupOnPremisesSynced owns the rule) and never otherwise, so a cloud
        # group's entry is exactly what earlier versions exported. Invoke-OERStructure never
        # sends this key and decides nothing on it: it reads the group live.
        if (Test-OERGroupOnPremisesSynced -Group $G) { $Proj.onPremisesSynced = $true }
        if ($G.GroupType -eq 'Dynamic') {
            $Proj.membershipRule = $G.MembershipRule
            if ($G.MembershipRuleProcessingState) {
                $Proj.membershipRuleProcessingState = [string]$G.MembershipRuleProcessingState
            }
        }
        # mailNickname is writable on create AND diffed on update by the apply engine, so it
        # must be readable here or a custom nickname is silently replaced by the Graph-generated
        # one on the next round-trip. Emitted only when set, so a document for a group without
        # one stays clean and the apply leaves it untouched.
        if ($G.MailNickname) { $Proj.mailNickname = [string]$G.MailNickname }
        if ($IncludeId) { $Proj.id = $G.Id }
        # An OMITTED members key still reconciles in the apply engine and still prunes under
        # -Prune (Get-OERStructureSchemaJson: "An omitted key still reconciles"), so omitting
        # it here would leave issue #76's chain wide open. An EXPLICIT null is the schema's
        # documented "leave membership untouched" signal, and that is what an unread
        # membership has to be.
        if ($G.PSObject.Properties.Name -contains 'Members') {
            # Project each member as a reference the apply engine can resolve back to its object id:
            # a user as its userPrincipalName (friendly and resolvable), and every other member type
            # (group, device, service principal, ...) as its object id, which Resolve-OERStructurePrincipal
            # returns verbatim. A member display name is NOT resolvable (it is not a UPN), so it is only a
            # last-resort fallback when neither a UPN nor an id is present.
            $Proj.members = @(foreach ($M in @($G.Members)) {
                if (-not $M) { continue }
                if ($M.userPrincipalName) { [string]$M.userPrincipalName }
                elseif ($M.id)            { [string]$M.id }
                else                      { [string]$M.displayName }
            })
        } else {
            $Proj.members = $null
            $UnreadCollections.Add("groups/$($G.DisplayName)/members")
        }
        if ($G.PSObject.Properties.Name -contains 'Owners') {
            # Owners are writable through Add-/Remove-OERGroupMember -AccessType owner and a group
            # owner can add members, so an unprojected owner is a privilege path that disappears from
            # the captured posture. Emitted only when the group has any, so a document for an
            # owner-less group stays clean and the apply leaves owners untouched.
            $OwnerRefs = @(foreach ($O in @($G.Owners)) {
                if (-not $O) { continue }
                if ($O.userPrincipalName) { [string]$O.userPrincipalName }
                elseif ($O.id)            { [string]$O.id }
                else                      { [string]$O.displayName }
            })
            if ($OwnerRefs.Count -gt 0) { $Proj.owners = $OwnerRefs }
        } else {
            # An omitted owners key is ALREADY never reconciled or pruned, so omission is the
            # correct hands-off form here -- no explicit null needed. The read failure is
            # still accounted for, so the document is not silently short an owner set.
            $UnreadCollections.Add("groups/$($G.DisplayName)/owners")
        }
        if ($G.PSObject.Properties.Name -contains 'PimEligibility') {
            $EligIds = @(@($G.PimEligibility) | ForEach-Object { [string]$_.principalId } | Where-Object { $_ })
            $MissingEligIds = @($EligIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
            if ($MissingEligIds.Count -gt 0) {
                $Resolved = Resolve-OERPrincipalName -Id $MissingEligIds
                foreach ($K in $Resolved.Keys) { $PrincipalNameCache[$K] = $Resolved[$K] }
            }
            # Project each eligibility so a re-apply reproduces it faithfully: accessType is always
            # emitted (member or owner) and durationDays is emitted only for a time-bound window --
            # its absence is how the apply document expresses a permanent eligibility.
            $Proj.eligibility = @(foreach ($E in @($G.PimEligibility)) {
                if (-not $E) { continue }
                $PrincipalId = [string]$E.principalId
                $Name = if ($PrincipalNameCache.ContainsKey($PrincipalId)) { $PrincipalNameCache[$PrincipalId] } else { $PrincipalId }
                $EligProj = [ordered]@{ principal = $Name }
                $EligProj.accessType = $(if ($E.accessId) { [string]$E.accessId } else { 'member' })
                $EligDays = Resolve-OEREligibilityDuration -StartDateTime $E.startDateTime -EndDateTime $E.endDateTime
                if ($null -ne $EligDays) { $EligProj.durationDays = [int]$EligDays }
                if ($IncludeId) { $EligProj.id = $PrincipalId }
                [PSCustomObject]$EligProj
            })
        } else {
            # Same as owners: an omitted OR explicitly null eligibility key is never reconciled
            # or pruned, so omission is already hands-off. No principal-name lookup is issued
            # for a collection that was never read.
            $UnreadCollections.Add("groups/$($G.DisplayName)/eligibility")
        }

        $MemberPim = $null
        $OwnerPim  = $null
        # ASK FIRST WHETHER THE GROUP USES PIM FOR GROUPS AT ALL. Microsoft Graph lists
        # PIM-for-Groups policies for every group, including one never used with PIM for
        # Groups (measured live 2026-09-28), so reading and exporting them used to put a
        # default pimPolicy on EVERY group -- and a proposal that changes one of those blocks
        # onboards the group on apply, which cannot be undone (Microsoft Graph documentation,
        # "Onboarding groups to PIM for Groups"). Test-OERGroupPimInUse owns the rule: the
        # eligibility this section already read, or one listing of the group's policies for a
        # modified one (docs/development/rationale.md#pim-in-use-criterion, ruling R2). A group
        # the criterion does not find in use gets no pimPolicy key and none of the four reads
        # below. A criterion that could not be read is never guessed in either direction:
        # pimPolicy is omitted AND the collection is reported unread, with its cause, exactly
        # like a failed policy read. The null-filter on the count is load-bearing:
        # @($null).Count is 1.
        $EligibilityRead = $G.PSObject.Properties.Name -contains 'PimEligibility'
        $EligCount = if ($EligibilityRead) {
            @($G.PimEligibility | Where-Object { $null -ne $_ }).Count
        } else { 0 }
        # The criterion is asked once per group, through Get-PimUsageDecision, and the failure is
        # recorded here, where the group is known by name. A decision made ahead of the projection
        # is reused from $PimUsageDecided instead of being asked for a second time.
        $Decision = if ($PimUsageDecided.ContainsKey([string]$G.Id)) { $PimUsageDecided[[string]$G.Id] } else { Get-PimUsageDecision -Group $G -EligibilityCount $EligCount }
        $Usage = $Decision.Usage
        if ($Decision.Failed) {
            $CriterionCause = "Could not determine whether group '$($G.Id)' uses PIM for Groups: $($Decision.Message)"
            Write-Verbose "Get-OERInventory: $CriterionCause"
            Add-UnreadCause -Cause $CriterionCause -Target ([string]$G.Id)
            $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
        }
        $PimInUse = ($null -ne $Usage -and [bool]$Usage.InUse)
        if ($null -ne $Usage -and -not $PimInUse) {
            if ($EligibilityRead) {
                Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported -- $($Usage.Reason)."
            } else {
                # HALF AN ANSWER. The eligibility read failed, so the count above was 0 by
                # default, not by measurement: "not in use" was decided on the policies alone
                # and is a guess. pimPolicy is omitted and reported unread too. The eligibility
                # read's own cause is already on the cause list (it is what omitted
                # PimEligibility), so this adds the COLLECTION only, never a second cause. A
                # modified policy, by contrast, decides "in use" on its own and never gets here.
                Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported and not decided -- $($Usage.Reason), and its PIM eligibility could not be read."
                $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
            }
        }

        # ASK NEXT WHETHER THERE IS A POLICY AT ALL, rather than reading one and swallowing
        # the answer. For a group whose policy Graph does not list (an empty assignments
        # collection, or 400 ResourceTypeNotSupported) Get-OERGroupPimPolicy correctly
        # reports a non-terminating PimPolicyNotFound -- which -ErrorAction Stop turns into
        # TWO records per call, four per group, in the CALLER's -ErrorVariable. That
        # collection is filled by the ENGINE from the error stream, so neither the catch
        # below nor any other catch in this module can reach those records: the only way not
        # to have them is not to provoke them. Measured offline on 100 groups, 96 of them
        # answering with no listed policy, driving the real wrapper and the real cmdlets with
        # only the transport stubbed: 384 records for an entirely clean read -- it does not
        # depend on whether the assignments call answers 200-empty or 400, since
        # Get-OERPimGroupPolicyId returns $null either way. A group the criterion above does
        # not find to use PIM for Groups (no PIM eligibility and no modified policy) never
        # gets this far: Graph lists a group's policies before it is onboarded (measured live
        # 2026-09-28), which is exactly why the criterion runs first, and a group it does not
        # find in use -- or could not decide -- makes none of the four calls below and
        # carries no pimPolicy. That finding is the criterion's, not a measured fact about
        # the tenant: a group used only through PIM ACTIVE assignments, with untouched
        # policies, is not found in use either (rationale.md#pim-in-use-criterion).
        #
        # NOT -ErrorAction Ignore on the reads below. That would silence a genuine 403 or 429
        # along with the not-listed case and leave the operator with a document quietly
        # missing PIM policy it had no permission to read. Get-OERPimGroupPolicyId declares
        # ResourceTypeNotSupported to the transport, so it comes back as a silent $null with
        # nothing raised anywhere, while every OTHER failure still throws.
        # A throw here is therefore NOT an answer: the read runs anyway and reports through
        # the path below. Only a confident $null skips it.
        #
        # AND THE PATH BELOW HAS TO TELL THE TWO APART, which is the whole point of the pair
        # of ids Get-OERGroupPimPolicy now emits. Suppressing PimPolicyNotFound is right --
        # a policy Graph does not list is not a finding -- but the same cmdlet used to
        # answer PimPolicyNotFound for a refusal as well, so this suppression swallowed the
        # refusal with it. Measured: a 403 on the policy-id lookup for 96 of 100 groups
        # produced 0 error records, 0 warnings, and pimPolicy absent from all 96 -- an
        # inventory that looked complete and was not, issue #76's defect class in a new
        # place. A failure now arrives as PimPolicyReadFailed and is accounted for exactly
        # like a failed members, owners or eligibility read: the CAUSE to verbose and the
        # deduplicated cause list, the COLLECTION to $UnreadCollections, and the caller names
        # it: Get-OERInventory in its InventoryPartial error, Export-OERInventory (which reads
        # its groups through this function) in the bundle's IncompleteReads and its own
        # InventoryPartial message. No per-group warning, for the reason stated at
        # the enumeration loop above: a per-collection failure is reported at the projection,
        # where the group is known by name, and 96 refused groups would otherwise print 192
        # near-identical lines and bury the one signal an operator can act on.
        #
        # pimPolicy stays OMITTED for that access type either way, never present and empty --
        # exactly as Get-OERGroup omits PimEligibility on a failed read.
        $ReadMemberPim = $false
        $ReadOwnerPim  = $false
        if ($PimInUse) {
            $ReadMemberPim = $true
            $ReadOwnerPim  = $true
            try { $ReadMemberPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType member) }
            catch { Remove-OERErrorRecord -Record $PSItem; $ReadMemberPim = $true }
            try { $ReadOwnerPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType owner) }
            catch { Remove-OERErrorRecord -Record $PSItem; $ReadOwnerPim = $true }
        }
        foreach ($PimAccessType in @('member', 'owner')) {
            if ($PimAccessType -eq 'member' -and -not $ReadMemberPim) { continue }
            if ($PimAccessType -eq 'owner' -and -not $ReadOwnerPim) { continue }
            try {
                $PimRead = Get-OERGroupPimPolicy -Id $G.Id -AccessType $PimAccessType -ErrorAction Stop
                if ($PimAccessType -eq 'member') { $MemberPim = $PimRead } else { $OwnerPim = $PimRead }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -like 'PimPolicyNotFound*') { continue }
                # Keep the CAUSE. Get-OERGroupPimPolicy composed the transport reason into
                # this message and it lives nowhere else once the record is dropped here.
                $PimCause = [string]$PSItem.Exception.Message
                Write-Verbose "Get-OERInventory: $PimCause"
                $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy/$PimAccessType")
                Add-UnreadCause -Cause $PimCause -Target ([string]$G.Id)
            }
        }
        $MemberProj = Convert-PimAccessProjection -Policy $MemberPim
        $OwnerProj  = Convert-PimAccessProjection -Policy $OwnerPim
        if ($MemberProj -or $OwnerProj) {
            $PimProj = [ordered]@{}
            if ($MemberProj) { $PimProj.member = $MemberProj }
            if ($OwnerProj)  { $PimProj.owner = $OwnerProj }
            $Proj.pimPolicy = [PSCustomObject]$PimProj
        }
        $Groups.Add([PSCustomObject]$Proj)
    }

    # -ExcludeSharedName: none of the groups that share a name is written, and the name is reported
    # instead -- the unread entry 'groups/<name>' with the spelling of the first listed group that
    # carries it, and the cause -- once however many groups share it. The same rule, wording and
    # order as Get-OERInventory's Select-UniqueNamedEntry: added after every other finding of this
    # section. A group left out of the document removes nothing: Invoke-OERStructure prunes child
    # collections only.
    if ($ExcludeSharedName) {
        $UniqueGroups = [System.Collections.Generic.List[object]]::new()
        foreach ($P in $Groups) {
            if ($SharedNameCount[[string]$P.displayName] -gt 1) { continue }
            $UniqueGroups.Add($P)
        }
        $Groups = $UniqueGroups
        $ReportedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($G in $GroupItems) {
            $SharedName = [string]$G.DisplayName
            if ($SharedNameCount[$SharedName] -le 1 -or -not $ReportedNames.Add($SharedName)) { continue }
            $SharedPath = "groups/$SharedName"
            $UnreadCollections.Add($SharedPath)
            $SharedCause = Get-OERSharedNameCause -Path $SharedPath
            Write-Verbose "Get-OERInventory: $SharedCause"
            Add-UnreadCause -Cause $SharedCause -Target $SharedPath
        }
    }

    $Result = [PSCustomObject]@{
        Groups = $Groups.ToArray()
        Unread = $UnreadCollections.ToArray()
        Causes = $Causes.ToArray()
    }
    $Result.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryGroupRead')
    $Result
}
