function Resolve-OERGroupPimPolicyChange {
    <#
    .SYNOPSIS
    Computes the PIM-for-groups policy parameter changes needed to make the current policy match a
    declared apply-document block.

    .DESCRIPTION
    Pure, tenant-free diff used by the Invoke-OERStructure group handler. Compares a declared
    pimPolicy access-type block (member or owner, or the flat back-compat form) against the current
    Get-OERGroupPimPolicy object and returns a tagged result with a Changed flag, a SetParams hashtable
    ready to splat into Set-OERGroupPimPolicy (only the fields that differ), and a human-readable
    Changes list. Enablement and notification-recipient lists are compared as order- and
    case-insensitive sets. The eligible-expiration and active-expiration rules are each treated as a
    unit (permanence plus duration) so a single PATCH never leaves them half-updated. A null Current
    (the group is not PIM-onboarded or the policy could not be read) is treated as everything-changed.
    Presence semantics apply: a field the document does not declare is never compared and never sent.
    A field present with an explicit JSON null counts as UNDECLARED too -- a key absent, an explicit
    null, and "leave the live value untouched" are the same three-way state -- matching the offline
    validator Test-OERStructureSchema, so a null can never be coerced into a $false toggle or a
    zero-day duration that silently overwrites the live policy. An empty string is still a declared
    value: authenticationContextId "" remains the documented "disable the authentication context"
    request, and an empty activationEnablement/activeEnablement array is still a declared clear. The
    one documented exception is the authentication-context / MultiFactorAuthentication mutual
    exclusion: because the platform cannot hold both at once, reconciling them can add an
    ActivationEnabledRules or an AuthenticationContextId the document never declared -- a plan that
    printed "unchanged" for a field the apply then overwrites would be lying. See
    docs/development/rationale.md#mfa-authcontext-exclusion.

    Declared approver values (approvers.users, approvers.groups) are ALREADY resolved to object ids by
    the time this diff sees them -- the caller (Sync-OERStructureGroup) resolves a declared UPN or
    group display name through Resolve-OERDeclaredApprover first, so this diff only ever compares ids
    with ids, never a name with an id. requireApproval and each approver side are independently
    presence-gated. A document that explicitly declares requireApproval = false takes precedence over
    a declared approvers block, and no approver parameter is sent: binding -ApproverUser or
    -ApproverGroup on Set-OERGroupPimPolicy FORCES approval on (supplying approvers implies approval),
    so sending them would override the explicit false -- the same reason the Azure Resource Manager
    sibling gives. The ignore is noted in Changes, but that note alone changes nothing: when it is the
    only entry, Changed is false and the handler reports "already matches" for that access type, so
    the note is not shown to a plan reader at all. Unlike the Azure Resource Manager sibling
    (Resolve-OERRoleManagementPolicyChange), which always sends both approver sides because ARM
    replaces the whole primaryApprovers array in one patch, this diff sends only the DECLARED side(s)
    when either side differs: Set-OERGroupPimPolicy replaces only the side it is bound for and carries
    the other side from the live rule, so an undeclared side must never be sent here either. No Graph,
    ARM, or authentication occurs.

    .PARAMETER Declared
    The declared pimPolicy block for one access type: either a member/owner sub-object or the flat
    member-only form. Recognized fields: activationMaxHours, authenticationContextId,
    activationEnablement, allowPermanentEligibility, eligibleDurationDays, allowPermanentActive,
    activeDurationDays, activeEnablement, a notifications object (eligibleAlert, activeAlert,
    activationAlert), requireApproval, and approvers (an object whose users and groups arrays are each
    independently optional -- declaring only one side leaves the other alone on the live rule, and the
    whole block is ignored when requireApproval is explicitly false). Approver values must already be
    object ids (see Resolve-OERDeclaredApprover).

    .PARAMETER Current
    The current policy as returned by Get-OERGroupPimPolicy for the same access type, or null when the
    group is not onboarded to PIM for Groups (in which case every declared field is considered changed).

    .EXAMPLE
    Resolve-OERGroupPimPolicyChange -Declared $Doc.pimPolicy.member -Current (Get-OERGroupPimPolicy -Id $Gid -AccessType member)
    Returns the SetParams needed to reconcile the member policy, or Changed = $false when it matches.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Declared,
        [PSCustomObject]$Current
    )

    $SetParams = @{}
    $Changes   = [System.Collections.Generic.List[string]]::new()

    # A property that is present but NULL counts as UNDECLARED -- a key absent, an explicit null, and
    # "leave the live value untouched" are the same three-way state, matching the offline validator's
    # Test-HasProp. Without the null guard, "authenticationContextId": null would cast to '' and
    # DISABLE a live authentication context, "allowPermanentEligibility": null would cast to $false and
    # REVOKE permanence, and "activationEnablement": null would cast to an empty set and CLEAR MFA. An
    # empty string or empty array is still a declared value -- "" stays the documented "disable"
    # request and [] stays the documented "clear this list" request.
    # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
    function Test-DeclHas {
        param([object]$Node, [string]$Name)
        Test-OERDeclaredProperty -Node $Node -Name $Name
    }

    function Test-SetEqual {
        param([object]$A, [object]$B)
        $LA = @($A | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        $LB = @($B | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        if ($LA.Count -ne $LB.Count) { return $false }
        for ($I = 0; $I -lt $LA.Count; $I++) { if ($LA[$I] -ne $LB[$I]) { return $false } }
        return $true
    }

    # -- scalar: activationMaxHours --------------------------------------------------------
    if (Test-DeclHas $Declared 'activationMaxHours') {
        $D = [int]$Declared.activationMaxHours
        if ($null -eq $Current -or [int]($Current.ActivationMaxHours) -ne $D) {
            $SetParams.ActivationMaxHours = $D; $Changes.Add("activationMaxHours=$D")
        }
    }

    # -- scalar: authenticationContextId (empty string means disable) ----------------------
    if (Test-DeclHas $Declared 'authenticationContextId') {
        $D = [string]$Declared.authenticationContextId
        $C = if ($null -ne $Current) { [string]$Current.AuthenticationContextId } else { '' }
        if ($null -eq $Current -or $D -ne $C) { $SetParams.AuthenticationContextId = $D; $Changes.Add("authenticationContextId=$D") }
    }

    # -- set: activationEnablement ---------------------------------------------------------
    if (Test-DeclHas $Declared 'activationEnablement') {
        $D = @($Declared.activationEnablement)
        $C = if ($null -ne $Current) { @($Current.ActivationEnabledRules) } else { @() }
        if ($null -eq $Current -or -not (Test-SetEqual $D $C)) {
            $SetParams.ActivationEnabledRules = $D; $Changes.Add("activationEnablement=[$($D -join ',')]")
        }
    }

    # -- set: activeEnablement -------------------------------------------------------------
    if (Test-DeclHas $Declared 'activeEnablement') {
        $D = @($Declared.activeEnablement)
        $C = if ($null -ne $Current) { @($Current.ActiveEnabledRules) } else { @() }
        if ($null -eq $Current -or -not (Test-SetEqual $D $C)) {
            $SetParams.ActiveEnabledRules = $D; $Changes.Add("activeEnablement=[$($D -join ',')]")
        }
    }

    # -- unit: eligible permanence + duration ----------------------------------------------
    $HasEligPerm = Test-DeclHas $Declared 'allowPermanentEligibility'
    $HasEligDur  = Test-DeclHas $Declared 'eligibleDurationDays'
    if ($HasEligPerm -or $HasEligDur) {
        $DPerm = if ($HasEligPerm) { [bool]$Declared.allowPermanentEligibility } elseif ($null -ne $Current) { [bool]$Current.AllowPermanentEligibility } else { $false }
        $DDur  = if ($HasEligDur)  { [int]$Declared.eligibleDurationDays } elseif ($null -ne $Current -and $Current.EligibleDurationDays) { [int]$Current.EligibleDurationDays } else { 365 }
        $CPerm = if ($null -ne $Current) { [bool]$Current.AllowPermanentEligibility } else { $null }
        $CDur  = if ($null -ne $Current -and $Current.EligibleDurationDays) { [int]$Current.EligibleDurationDays } else { $null }
        if ($null -eq $Current -or ($HasEligPerm -and $DPerm -ne $CPerm) -or ($HasEligDur -and $DDur -ne $CDur)) {
            $SetParams.EligibleDuration = $DDur
            $SetParams.AllowPermanentEligibility = $DPerm
            $Changes.Add("eligible(perm=$DPerm,days=$DDur)")
        }
    }

    # -- unit: active permanence + duration ------------------------------------------------
    $HasActPerm = Test-DeclHas $Declared 'allowPermanentActive'
    $HasActDur  = Test-DeclHas $Declared 'activeDurationDays'
    if ($HasActPerm -or $HasActDur) {
        $DPerm = if ($HasActPerm) { [bool]$Declared.allowPermanentActive } elseif ($null -ne $Current) { [bool]$Current.AllowPermanentActive } else { $false }
        $DDur  = if ($HasActDur)  { [int]$Declared.activeDurationDays } elseif ($null -ne $Current -and $Current.ActiveDurationDays) { [int]$Current.ActiveDurationDays } else { 180 }
        $CPerm = if ($null -ne $Current) { [bool]$Current.AllowPermanentActive } else { $null }
        $CDur  = if ($null -ne $Current -and $Current.ActiveDurationDays) { [int]$Current.ActiveDurationDays } else { $null }
        if ($null -eq $Current -or ($HasActPerm -and $DPerm -ne $CPerm) -or ($HasActDur -and $DDur -ne $CDur)) {
            $SetParams.ActiveDuration = $DDur
            $SetParams.AllowPermanentActive = $DPerm
            $Changes.Add("active(perm=$DPerm,days=$DDur)")
        }
    }

    # -- notifications (three alerts) ------------------------------------------------------
    if (Test-DeclHas $Declared 'notifications') {
        $DN = $Declared.notifications
        $CN = if ($null -ne $Current) { $Current.Notifications } else { $null }
        $AlertMap = @(
            @{ Decl = 'eligibleAlert';   Cur = 'EligibleAlert';   Param = 'EligibleAlertRecipient' }
            @{ Decl = 'activeAlert';     Cur = 'ActiveAlert';     Param = 'ActiveAlertRecipient' }
            @{ Decl = 'activationAlert'; Cur = 'ActivationAlert'; Param = 'ActivationAlertRecipient' }
        )
        foreach ($A in $AlertMap) {
            if (Test-DeclHas $DN $A.Decl) {
                $D = @($DN.($A.Decl))
                $C = if ($null -ne $CN -and (Test-DeclHas $CN $A.Cur)) { @($CN.($A.Cur)) } else { @() }
                if ($null -eq $Current -or -not (Test-SetEqual $D $C)) {
                    $SetParams[$A.Param] = $D; $Changes.Add("$($A.Decl)=[$($D -join ',')]")
                }
            }
        }
    }

    # -- scalar: requireApproval -------------------------------------------------------------
    if (Test-DeclHas $Declared 'requireApproval') {
        $D = [bool]$Declared.requireApproval
        if ($null -eq $Current -or $D -ne [bool]$Current.RequireApproval) {
            $SetParams.RequireApproval = $D; $Changes.Add("requireApproval=$D")
        }
    }

    # -- set: approvers (users/groups) --------------------------------------------------------
    # Declared values are already object ids (see the help above -- Resolve-OERDeclaredApprover runs
    # before this diff), so the comparison below only ever matches ids with ids. requireApproval=false
    # wins over a declared approvers block: binding -ApproverUser or -ApproverGroup on
    # Set-OERGroupPimPolicy FORCES approval on (supplying approvers implies approval, and
    # New-OERPimRuleSet sends isApprovalRequired true whenever approvers are bound), so sending them
    # would silently override the explicit false -- the same reason the ARM sibling,
    # Resolve-OERRoleManagementPolicyChange, gives. The ignore is added to Changes, but it sets no
    # parameter: when it is the only entry, Changed is false and the handler reports "already
    # matches", so a plan reader never sees the note. Otherwise,
    # only the side(s) the document actually declares are compared and, when either differs, sent:
    # Set-OERGroupPimPolicy replaces exactly the side it is bound for and carries the other from the
    # live rule, so sending an undeclared side here would be redundant at best and, on a null Current,
    # would invent a side the document never named.
    $HasDeclUser  = Test-DeclHas $Declared.approvers 'users'
    $HasDeclGroup = Test-DeclHas $Declared.approvers 'groups'
    $ApprovalExplicitlyOff = (Test-DeclHas $Declared 'requireApproval') -and (-not [bool]$Declared.requireApproval)
    if (($HasDeclUser -or $HasDeclGroup) -and $ApprovalExplicitlyOff) {
        $Changes.Add('approvers ignored: requireApproval=False takes precedence (approvers only apply when approval is required)')
    } elseif ($HasDeclUser -or $HasDeclGroup) {
        $CurAll   = if ($null -ne $Current) { @(@($Current.Approvers) | Where-Object { $_ }) } else { @() }
        $CurUser  = @($CurAll | Where-Object { [string]$_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id })
        $CurGroup = @($CurAll | Where-Object { [string]$_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id })

        $DeclUser  = @(@($Declared.approvers.users) | ForEach-Object { [string]$_ } | Where-Object { $_ })
        $DeclGroup = @(@($Declared.approvers.groups) | ForEach-Object { [string]$_ } | Where-Object { $_ })

        $UserChanged  = $HasDeclUser  -and ($null -eq $Current -or -not (Test-SetEqual $DeclUser  $CurUser))
        $GroupChanged = $HasDeclGroup -and ($null -eq $Current -or -not (Test-SetEqual $DeclGroup $CurGroup))
        if ($UserChanged -or $GroupChanged) {
            $Parts = [System.Collections.Generic.List[string]]::new()
            if ($HasDeclUser) {
                $SetParams.ApproverUser = $DeclUser
                $Parts.Add("users=[$($DeclUser -join ',')]")
            }
            if ($HasDeclGroup) {
                $SetParams.ApproverGroup = $DeclGroup
                $Parts.Add("groups=[$($DeclGroup -join ',')]")
            }
            $Changes.Add("approvers($($Parts -join ','))")
        }
    }

    # -- cross-rule: authentication context vs MFA on activation ---------------------------
    # PIM treats an enabled authentication context and MultiFactorAuthentication on activation as
    # mutually exclusive, and Set-OERGroupPimPolicy enforces that on the write path. The diff must
    # agree, or a document declaring both never converges: run 1 sends only the context and the
    # write path clears MFA, run 2 sees MFA differ and sends it back, run 3 repeats run 1.
    # The DisableAuthContext arm deliberately breaks presence semantics -- it sends a field the
    # document did not declare -- because the write path will disable the context regardless, and a
    # plan that printed "unchanged" for a change the apply then makes would be lying. The ClearMfa
    # arm breaks presence semantics the same way: a document declaring only authenticationContextId
    # (no activationEnablement) still gets a SetParams.ActivationEnabledRules entry whenever the
    # current policy carries MultiFactorAuthentication, because the write path will clear it
    # regardless and the plan must say so.
    # Why: docs/development/rationale.md#mfa-authcontext-exclusion
    $DeclaredAc = if (Test-DeclHas $Declared 'authenticationContextId') { [string]$Declared.authenticationContextId } else { $null }
    $DeclaredAerDeclared = Test-DeclHas $Declared 'activationEnablement'
    $EffectiveAer = if ($DeclaredAerDeclared) { @($Declared.activationEnablement) }
    elseif ($null -ne $Current) { @($Current.ActivationEnabledRules) } else { @() }
    $EffectiveAcId = if ($null -ne $DeclaredAc) { $DeclaredAc }
    elseif ($null -ne $Current) { [string]$Current.AuthenticationContextId } else { '' }

    $ConflictParams = @{
        EffectiveAuthContextId          = $EffectiveAcId
        EffectiveActivationEnabledRules = $EffectiveAer
    }
    if (-not [string]::IsNullOrEmpty($EffectiveAcId)) { $ConflictParams.EffectiveAuthContextEnabled = $true }
    if (-not [string]::IsNullOrEmpty($DeclaredAc)) { $ConflictParams.CallerRequestsAuthContext = $true }
    # A document declaring BOTH is resolved, never refused (decision D2): the authentication context
    # wins and the MFA flag is dropped with the reason recorded. Withholding CallerRequestsMfa when
    # the document also declares a context is what turns the helper's Conflict into ClearMfa here.
    # The write path still refuses when a HUMAN binds both parameters explicitly.
    if ($DeclaredAerDeclared -and (@($Declared.activationEnablement) -contains 'MultiFactorAuthentication') -and
        -not $ConflictParams.ContainsKey('CallerRequestsAuthContext')) {
        $ConflictParams.CallerRequestsMfa = $true
    }
    $Resolution = Resolve-OERPimActivationConflict @ConflictParams

    if ($Resolution.Action -eq 'ClearMfa') {
        # Re-decide the enablement entry from scratch: the per-field comparison above may already
        # have queued the DECLARED list (which still carries MFA), and on the second apply run the
        # reconciled list is exactly what the policy already has, so the entry must come back OUT or
        # the diff never converges.
        $Reconciled = @($Resolution.ActivationEnabledRules)
        $CurrentAer = if ($null -ne $Current) { @($Current.ActivationEnabledRules) } else { @() }
        $ExistingChange = @($Changes | Where-Object { $_ -like 'activationEnablement=*' })
        foreach ($Entry in $ExistingChange) { [void]$Changes.Remove($Entry) }
        if ($null -eq $Current -or -not (Test-SetEqual $Reconciled $CurrentAer)) {
            $SetParams.ActivationEnabledRules = $Reconciled
            $Changes.Add("activationEnablement=[$($Reconciled -join ',')] ($($Resolution.Reason))")
        } elseif ($SetParams.ContainsKey('ActivationEnabledRules')) {
            [void]$SetParams.Remove('ActivationEnabledRules')
        }
    } elseif ($Resolution.Action -eq 'DisableAuthContext') {
        $SetParams.AuthenticationContextId = ''
        $Changes.Add("authenticationContextId='' ($($Resolution.Reason))")
    }

    $Out = [PSCustomObject]@{
        Changed   = ($SetParams.Keys.Count -gt 0)
        SetParams = $SetParams
        Changes   = $Changes.ToArray()
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimPolicyChange')
    $Out
}
