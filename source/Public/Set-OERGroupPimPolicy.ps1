function Set-OERGroupPimPolicy {
    <#
    .SYNOPSIS
    Updates the PIM-for-groups activation template (rule set) for a group.

    .DESCRIPTION
    Builds the activation rule set with the private New-OERPimRuleSet helper and PATCHes each rule on the
    group's roleManagementPolicy (resolved via Get-OERPimGroupPolicyId). Only the rules whose governing
    parameters are bound are patched -- omitted parameters are left unchanged (surgical patch). Each rule
    is patched individually so a single rejected rule does not abort the rest. The result is built by the
    private ConvertTo-OERGroupPimPolicyResult and tagged Omnicit.EntraRBAC.GroupPimPolicyResult (with the
    shared Omnicit.EntraRBAC.GroupPimPolicy type name still present underneath, for existing consumers):
    it lists ONLY the settings that were actually SENT to Graph -- a setting whose parameter was not
    bound, and was not reconciled onto the wire by the mutual-exclusion rule below, is absent from the
    object, never null or false -- plus GroupId, PolicyId, AccessType, Applied (true only when every
    rule this run built was both sent and accepted by Graph), and FailedRules (the ids that were sent
    and rejected; a declined rule is not a failure and is not listed here either). A rule the mutual-
    exclusion reconcile sent on the caller's behalf IS reported, with the value actually sent, even
    though its own parameter was never bound -- see the reconcile paragraph below. This summary is not
    a read of the resulting policy state; use Get-OERGroupPimPolicy for that. A group that has no PIM-
    for-groups policy assignment for the requested access type -- never onboarded, or onboarded moments
    ago and not yet listed by Graph (replication delay) -- produces a non-terminating PimPolicyNotFound
    error; re-running usually succeeds once the group's first eligibility has onboarded it. A refused
    read of that policy assignment (insufficient permission, throttling, a dead transport, ...) is a
    DIFFERENT, non-terminating PimPolicyReadFailed error: whether the group has a policy is unknown,
    which is not the same as it having none, so nothing is changed either way. When Graph rejects one
    or more rules the cmdlet still returns the summary object and additionally writes a non-terminating
    PolicyRulesRejected error, so a partial apply is detectable with -ErrorAction Stop or by inspecting
    $?. At least one rule parameter (ActivationMaxHours, AuthenticationContextId, ActivationEnabledRules,
    ActiveEnabledRules, EligibleDuration, ActiveDuration, EligibleAlertRecipient,
    ActiveAlertRecipient, ActivationAlertRecipient, RequireApproval, ApproverUser, ApproverGroup,
    AllowPermanentEligibility, or AllowPermanentActive) must be supplied or a non-terminating
    NothingToUpdate error is emitted; -AccessType alone only selects which policy would have been
    patched. Supports -WhatIf and -Confirm.

    Approval on activation is the Approval_EndUser_Assignment rule, set with -RequireApproval,
    -ApproverUser and -ApproverGroup. Binding -ApproverUser replaces the user approvers only and
    -ApproverGroup the group approvers only: the side left unbound is carried over from the live rule,
    so a call that names a new user approver keeps the group approvers already there (this differs
    from Set-OERRoleManagementPolicy, which replaces the whole list). A live approver that is neither
    a user nor a group (a requestor's manager, for example) is never replaced by either parameter and
    is sent back unchanged. Supplying approvers on either
    side implies approval is required. -RequireApproval $true needs at least one approver, either
    supplied or already on the live rule; with none, a non-terminating ApproverRequired error is
    written and nothing is sent. Every approver value is resolved to an object id first (a user by
    UPN or id, a group by display name or id); a value that does not resolve is a non-terminating
    ApproverNotFound error and nothing is sent. Stage fields this cmdlet has no parameter for, such
    as the approval timeout and whether approvers must justify, carry over from the live stage; a
    policy with no stage yet gets a 1-day timeout with approver justification required. Any of the
    three parameters makes the cmdlet read the live approval rule first; when that read fails, a
    non-terminating ApprovalRuleReadFailed error is written and NO rule is patched, including the
    other rules bound on the same call, since the carried-over stage and approvers would otherwise be
    lost.

    Entra PIM treats an enabled authentication context and MultiFactorAuthentication on activation as
    mutually exclusive, so this cmdlet reconciles the two instead of sending a combination the
    platform would only reject later, at end-user activation. Requesting both explicitly (a non-empty
    -AuthenticationContextId together with MultiFactorAuthentication in -ActivationEnabledRules) is
    refused outright with a non-terminating MfaAuthContextConflict error and nothing is sent. Asking
    for one side while the OTHER side is left unbound reads the live rule and clears it: binding
    -AuthenticationContextId (non-empty) without -ActivationEnabledRules reads the live activation
    enablement rule and, if it carries MultiFactorAuthentication, patches that rule with the flag
    removed and every other flag preserved; binding -ActivationEnabledRules with
    MultiFactorAuthentication without -AuthenticationContextId reads the live authentication-context
    rule and, if it is enabled, patches it disabled (empty claim value). Before any of this, a
    non-empty -AuthenticationContextId is validated against the tenant's authentication contexts (see
    Get-OERAuthenticationContext): an id that does not exist is a non-terminating
    AuthenticationContextNotFound error, and an id that exists but is not published is a
    non-terminating AuthenticationContextNotAvailable error -- both return before any Graph write. A
    failed validation READ (for example, missing AuthenticationContext.Read.All) is not a refusal: it
    degrades to a Write-Warning and the call proceeds unvalidated, so an automation identity without
    that scope can still set a context it knows is valid.

    .PARAMETER Group
    The target group whose PIM-for-groups activation policy is updated, given as a display name or object
    id (GUID) and resolved via Resolve-OERGroupId. Accepts the GroupId, Id, and DisplayName aliases
    (GroupId takes precedence during pipeline binding so a piped Get-OERGroupMember object binds the
    group's GroupId instead of a principal's Id) and binds from the pipeline by property name so
    Get-OERGroup pipes straight in.

    .PARAMETER AccessType
    Whether to update the member (default) or owner activation policy for the group. Binds from the
    pipeline by property name, so a piped Omnicit.EntraRBAC.GroupPimPolicy or GroupPimPolicyResult
    object (both carry an AccessType property) -- for example the output of Get-OERGroupPimPolicy --
    patches the same access type it reported instead of silently falling back to member.

    .PARAMETER ActivationMaxHours
    The maximum end-user activation window in hours (1-24). Optional -- when omitted the end-user
    expiration rule is not patched and the existing value is preserved.

    .PARAMETER AuthenticationContextId
    Optional authentication-context claim value required on activation (e.g. c1). When supplied as an
    empty string, the AuthenticationContext_EndUser_Assignment rule is disabled so activation does not
    require an authentication context. When supplied it must match the pattern c followed by digits or be
    empty. When omitted, the rule is normally left unpatched -- EXCEPT when -ActivationEnabledRules is
    bound together with MultiFactorAuthentication: PIM cannot hold both an enabled authentication
    context and MFA on activation, so the live authentication-context rule is read and, if it is
    enabled, patched off even though this parameter itself was never supplied.

    .PARAMETER ActivationEnabledRules
    The enabledRules required on end-user activation (Justification, MultiFactorAuthentication,
    Ticketing). When bound, patches the Enablement_EndUser_Assignment rule; when omitted the rule is
    normally left unchanged on the policy -- EXCEPT when a non-empty -AuthenticationContextId is
    supplied: PIM cannot hold both an enabled authentication context and MFA on activation, so the
    live enablement rule is read and, if it carries MultiFactorAuthentication, re-sent with that flag
    removed and every other flag preserved, even though this parameter itself was never bound.

    .PARAMETER ActiveEnabledRules
    The enabledRules required on an admin active assignment (Justification, MultiFactorAuthentication,
    Ticketing). When bound, patches the Enablement_Admin_Assignment rule; when omitted that rule is left
    unchanged on the policy.

    .PARAMETER EligibleDuration
    Maximum lifetime in whole days for time-bound admin eligible assignments (e.g. 365). Defaults to 365.
    The eligible-expiration rule is patched only when either -EligibleDuration or -AllowPermanentEligibility
    is explicitly supplied. The day count is converted to an ISO 8601 duration for Microsoft Graph. When
    -AllowPermanentEligibility is supplied WITHOUT -EligibleDuration, the rule's live maximumDuration is
    read and sent back untouched instead of this default -- so enabling permanence alone never silently
    rewrites an existing time-bound maximum to 365 days; the default is used only when that live read
    fails or the policy has no existing value. Also bindable as -EligibleDurationDays, the name
    Get-OERGroupPimPolicy uses on its output.

    .PARAMETER ActiveDuration
    Maximum lifetime in whole days for time-bound admin active assignments (e.g. 180). Defaults to 180.
    The active-expiration rule is patched only when either -ActiveDuration or -AllowPermanentActive is
    explicitly supplied. The day count is converted to an ISO 8601 duration for Microsoft Graph. When
    -AllowPermanentActive is supplied WITHOUT -ActiveDuration, the rule's live maximumDuration is read
    and sent back untouched instead of this default -- so enabling permanence alone never silently
    rewrites an existing time-bound maximum to 180 days; the default is used only when that live read
    fails or the policy has no existing value. Also bindable as -ActiveDurationDays, the name
    Get-OERGroupPimPolicy uses on its output.

    .PARAMETER EligibleAlertRecipient
    Extra recipient email addresses added to the eligible-assignment admin alert notification
    (Notification_Admin_Admin_Eligibility). When bound, patches that notification rule; when omitted the
    rule is not patched and the existing recipients are preserved.

    .PARAMETER ActiveAlertRecipient
    Extra recipient email addresses added to the active-assignment admin alert notification
    (Notification_Admin_Admin_Assignment). When bound, patches that notification rule; when omitted the
    rule is not patched and the existing recipients are preserved.

    .PARAMETER ActivationAlertRecipient
    Extra recipient email addresses added to the role-activation admin alert notification
    (Notification_Admin_EndUser_Assignment). When bound, patches that notification rule; when omitted
    the rule is not patched and the existing recipients are preserved.

    .PARAMETER RequireApproval
    Whether end-user activation requires approval (the Approval_EndUser_Assignment rule). $true
    requires at least one approver, either supplied with -ApproverUser or -ApproverGroup or already on
    the live rule, or the call is refused with ApproverRequired. $false turns approval off and keeps
    the live stage and approvers for a later re-enable. When omitted and neither approver parameter
    is bound, the approval rule is not patched.

    .PARAMETER ApproverUser
    The user approvers, each a user principal name or user object id, resolved to object ids before
    anything is sent. Replaces the user approvers on the live rule; the group approvers are kept.
    Supplying it implies -RequireApproval $true. An empty list clears the user side. A value that does
    not resolve refuses the whole call with ApproverNotFound. The same user named twice (by UPN and
    by id, or in a different letter case) is sent once.

    .PARAMETER ApproverGroup
    The group approvers, each a group display name or group object id, resolved to object ids before
    anything is sent. Replaces the group approvers on the live rule; the user approvers are kept.
    Supplying it implies -RequireApproval $true. An empty list clears the group side. A value that
    does not resolve refuses the whole call with ApproverNotFound.

    .PARAMETER AllowPermanentEligibility
    Allow permanent eligible assignments (sets isExpirationRequired to false on the eligibility rule).
    When supplied (even without -EligibleDuration), the eligible-expiration rule is included in the
    patch, carrying forward the rule's live maximumDuration (see -EligibleDuration) rather than
    rewriting it to the -EligibleDuration default.

    .PARAMETER AllowPermanentActive
    Allow permanent active assignments (sets isExpirationRequired to false on the active-assignment rule).
    When supplied (even without -ActiveDuration), the active-expiration rule is included in the patch,
    carrying forward the rule's live maximumDuration (see -ActiveDuration) rather than rewriting it to
    the -ActiveDuration default.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERGroupPimPolicy -Group 'role_sec_identity_administrator' -ActivationMaxHours 8 -AuthenticationContextId 'c1'
    Sets an 8-hour activation window requiring authentication context c1 for the named group, patching
    only those two rules and leaving all others unchanged.

    .EXAMPLE
    Set-OERGroupPimPolicy -Group 'OER_TEST_1' -ActivationMaxHours 8 -AllowPermanentEligibility -EligibleDuration 365
    Allows permanent eligible assignments (so Add-OERGroupEligibility without -Duration succeeds), caps
    time-bound eligibility at 365 days, and does not require an authentication context on activation.

    .EXAMPLE
    Set-OERGroupPimPolicy -Group 'role_az_owner' -AccessType owner -ActivationMaxHours 1 -ActiveEnabledRules MultiFactorAuthentication,Justification -EligibleAlertRecipient 'admin@contoso.com'
    Sets the owner activation window to 1 hour, requires MFA + justification on active assignment, and
    adds an admin recipient to the eligible-assignment alert -- patching only those rules.

    .EXAMPLE
    Set-OERGroupPimPolicy -Group 'role_sec_identity_administrator' -RequireApproval $true -ApproverGroup 'pim-approvers'
    Requires approval on member activation with the members of the pim-approvers group as approvers,
    replacing any group approvers on the live rule while keeping its user approvers, its approval
    timeout and its justification settings.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [ValidateRange(1, 24)]
        [int]$ActivationMaxHours,

        [ValidatePattern('^c\d+$|^$')]
        [string]$AuthenticationContextId,

        [ValidateSet('Justification', 'MultiFactorAuthentication', 'Ticketing')]
        [string[]]$ActivationEnabledRules,

        [ValidateSet('Justification', 'MultiFactorAuthentication', 'Ticketing')]
        [string[]]$ActiveEnabledRules,

        [ValidateRange(1, 3650)]
        [Alias('EligibleDurationDays')]
        [int]$EligibleDuration = 365,

        [ValidateRange(1, 3650)]
        [Alias('ActiveDurationDays')]
        [int]$ActiveDuration = 180,

        [string[]]$EligibleAlertRecipient,

        [string[]]$ActiveAlertRecipient,

        [string[]]$ActivationAlertRecipient,

        [bool]$RequireApproval,

        [string[]]$ApproverUser,

        [string[]]$ApproverGroup,

        [switch]$AllowPermanentEligibility,

        [switch]$AllowPermanentActive,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # This guard matters most on THIS cmdlet: with no rule parameter bound, New-OERPimRuleSet
        # builds zero rules (its own `if ($Rules.Count -gt 0)` gate at the tail), so the patch loop
        # below never runs, $Processed stays $false, and the cmdlet used to return NO object at all
        # after two Graph reads (resolve group, resolve policy id) -- a silence a caller cannot tell
        # apart from a successful patch. Guarding first also costs the caller no Graph round trip.
        $RuleParamNames = @(
            'ActivationMaxHours', 'AuthenticationContextId', 'ActivationEnabledRules', 'ActiveEnabledRules',
            'EligibleDuration', 'ActiveDuration', 'EligibleAlertRecipient', 'ActiveAlertRecipient',
            'ActivationAlertRecipient', 'RequireApproval', 'ApproverUser', 'ApproverGroup',
            'AllowPermanentEligibility', 'AllowPermanentActive')
        $AnyRuleBound = $RuleParamNames | Where-Object { $PSBoundParameters.ContainsKey($_) }
        if (-not $AnyRuleBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    'No updatable property was supplied. Pass at least one of -ActivationMaxHours, ' +
                    '-AuthenticationContextId, -ActivationEnabledRules, -ActiveEnabledRules, -EligibleDuration, ' +
                    '-ActiveDuration, -EligibleAlertRecipient, -ActiveAlertRecipient, -ActivationAlertRecipient, ' +
                    '-RequireApproval, -ApproverUser, -ApproverGroup, -AllowPermanentEligibility, or ' +
                    '-AllowPermanentActive. -AccessType alone only selects which policy would be patched; it is ' +
                    'not itself an update.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }

        # Approvers are resolved to object ids before anything else, all or nothing: one value that
        # does not resolve refuses the whole call before the group is even looked up, so nothing is
        # sent. The same principal named twice (a UPN and its id, or an id in another letter case)
        # is kept once, in first-seen order. Same shape as Set-OERRoleManagementPolicy.
        $ApproverUserBound = $PSBoundParameters.ContainsKey('ApproverUser')
        $ApproverGroupBound = $PSBoundParameters.ContainsKey('ApproverGroup')
        $ResolvedUser = [System.Collections.Generic.List[string]]::new()
        $ResolvedGroup = [System.Collections.Generic.List[string]]::new()
        $SeenUser = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $SeenGroup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Value = $null
        try {
            foreach ($Value in @($ApproverUser)) {
                if (-not $Value) { continue }
                $PrincipalId = [string](Resolve-OERPrincipal -User $Value).PrincipalId
                if ($SeenUser.Add($PrincipalId)) { $ResolvedUser.Add($PrincipalId) }
            }
            foreach ($Value in @($ApproverGroup)) {
                if (-not $Value) { continue }
                $PrincipalId = [string](Resolve-OERPrincipal -Group $Value).PrincipalId
                if ($SeenGroup.Add($PrincipalId)) { $ResolvedGroup.Add($PrincipalId) }
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'ApproverNotFound' -Category ObjectNotFound -TargetObject $Value -Cmdlet $PSCmdlet
            return
        }

        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $Group
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                    -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Group '$Group' not found. Verify the display name matches exactly (leading or trailing spaces " +
                    "and punctuation count) or pass the group object id instead.")) `
                -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Set-OERGroupPimPolicy] Resolved group to '$GroupId'."

        # A FAILED LOOKUP IS NOT AN ABSENT POLICY -- same split as Get-OERGroupPimPolicy.ps1:96-115.
        # A refused read (403, 429, ...) means "I could not tell", never "there is none", so it gets
        # its own PimPolicyReadFailed id and nothing is changed; only a genuinely absent policy is
        # PimPolicyNotFound.
        $PolicyId = $null
        try {
            $PolicyId = Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType $AccessType
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Could not read the PIM-for-groups policy assignment for group '$GroupId' ('$AccessType' access): " +
                    "$($PSItem.Exception.Message). Whether this group has a policy is UNKNOWN, which is not the same " +
                    'as the group having none, so nothing was changed.')) `
                -ErrorId 'PimPolicyReadFailed' -Category ReadError -TargetObject $GroupId `
                -InnerException $PSItem.Exception -Cmdlet $PSCmdlet
            return
        }
        if (-not $PolicyId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Group '$GroupId' has no PIM-for-groups policy for '$AccessType' access yet. A group created " +
                    'moments ago can take a short while before Microsoft Graph lists its policies (replication ' +
                    'delay), and re-running usually succeeds. A group never used with PIM for Groups gets its ' +
                    'policies when it is first onboarded, for example by its first eligibility.')) `
                -ErrorId 'PimPolicyNotFound' -Category ObjectNotFound -TargetObject $GroupId -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Set-OERGroupPimPolicy] Resolved PIM policy id: '$PolicyId'."

        # -- Authentication context: validate, then reconcile against MFA -----------------------
        # Graph does NOT validate claimValue, so a context that does not exist (or exists but is not
        # published) is accepted here and only fails later, for end users at activation time. The
        # portal only ever offers published contexts; match it. A failed READ is not a refusal -- an
        # automation identity without AuthenticationContext.Read.All must still be able to set a
        # context it knows is valid.
        $AcBound  = $PSBoundParameters.ContainsKey('AuthenticationContextId')
        $AerBound = $PSBoundParameters.ContainsKey('ActivationEnabledRules')
        $WantsAc  = $AcBound -and -not [string]::IsNullOrEmpty($AuthenticationContextId)
        $WantsMfa = $AerBound -and (@($ActivationEnabledRules) -contains 'MultiFactorAuthentication')

        if ($WantsAc) {
            $KnownContext = $null
            $ContextReadFailed = $false
            try {
                $KnownContext = @(Get-OERAuthenticationContext -ErrorAction Stop)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ContextReadFailed = $true
                Write-Warning "Could not verify authentication context '$AuthenticationContextId' against the tenant: $($PSItem.Exception.Message) Proceeding without validation."
            }
            if (-not $ContextReadFailed) {
                $Match = @($KnownContext) | Where-Object { $_.AuthenticationContextId -eq $AuthenticationContextId } | Select-Object -First 1
                if (-not $Match) {
                    $Known = (@($KnownContext).AuthenticationContextId | Sort-Object) -join ', '
                    if (-not $Known) { $Known = '(none defined in this tenant)' }
                    Write-CmdletError `
                        -Message ([System.Exception]::new(
                            "Authentication context '$AuthenticationContextId' does not exist in this tenant. Graph accepts an unknown claim value but end users then fail at activation. Defined contexts: $Known. List them with Get-OERAuthenticationContext.")) `
                        -ErrorId 'AuthenticationContextNotFound' -Category ObjectNotFound `
                        -TargetObject $AuthenticationContextId -Cmdlet $PSCmdlet
                    return
                }
                if (-not $Match.IsAvailable) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new(
                            "Authentication context '$AuthenticationContextId' ($($Match.DisplayName)) exists but is not published, so end users cannot satisfy it at activation. Publish it in Conditional Access first, or pick one from Get-OERAuthenticationContext -Available.")) `
                        -ErrorId 'AuthenticationContextNotAvailable' -Category InvalidArgument `
                        -TargetObject $AuthenticationContextId -Cmdlet $PSCmdlet
                    return
                }
            }
        }

        # The exclusion decision itself is owned by Resolve-OERPimActivationConflict, shared with the
        # ARM path. Only the two cases that can produce a real change issue a live read, and only the
        # rule they need -- an unconditional read would add a Graph call to every invocation.
        $Resolution = $null
        if ($WantsAc -and $WantsMfa) {
            $Resolution = Resolve-OERPimActivationConflict -CallerRequestsAuthContext -CallerRequestsMfa `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId $AuthenticationContextId `
                -EffectiveActivationEnabledRules @($ActivationEnabledRules)
        } elseif ($WantsAc -and -not $AerBound) {
            $LiveEnabledRules = $null
            try {
                $LiveRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Enablement_EndUser_Assignment" -f $PolicyId))
                $LiveEnabledRules = @($LiveRule.enabledRules)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read the live activation enablement rules for policy '$PolicyId'; multi-factor authentication may remain enabled alongside authentication context '$AuthenticationContextId', which PIM treats as mutually exclusive: $($PSItem.Exception.Message)"
            }
            if ($null -ne $LiveEnabledRules) {
                $Resolution = Resolve-OERPimActivationConflict -CallerRequestsAuthContext `
                    -EffectiveAuthContextEnabled -EffectiveAuthContextId $AuthenticationContextId `
                    -EffectiveActivationEnabledRules $LiveEnabledRules
            }
        } elseif ($WantsMfa -and -not $AcBound) {
            try {
                $LiveRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/AuthenticationContext_EndUser_Assignment" -f $PolicyId))
                $ConflictParams = @{
                    CallerRequestsMfa               = $true
                    EffectiveAuthContextId          = [string]$LiveRule.claimValue
                    EffectiveActivationEnabledRules = @($ActivationEnabledRules)
                }
                if ([bool]$LiveRule.isEnabled) { $ConflictParams.EffectiveAuthContextEnabled = $true }
                $Resolution = Resolve-OERPimActivationConflict @ConflictParams
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read the live authentication context rule for policy '$PolicyId'; it may remain enabled alongside the multi-factor authentication requirement, which PIM treats as mutually exclusive: $($PSItem.Exception.Message)"
            }
        }

        if ($Resolution -and $Resolution.Action -eq 'Conflict') {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "$($Resolution.Reason) Pass -AuthenticationContextId '$AuthenticationContextId' without MultiFactorAuthentication in -ActivationEnabledRules, or drop the authentication context.")) `
                -ErrorId 'MfaAuthContextConflict' -Category InvalidArgument `
                -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }

        # The expiration rule is a unit: New-OERPimRuleSet emits maximumDuration alongside
        # isExpirationRequired, so binding only the permanence switch used to send the PARAMETER
        # DEFAULT (365 / 180) and silently rewrite whatever the tenant had configured. Carry the live
        # value forward instead -- the same read-modify-write shape Enable-OERGroupPermanentEligibility
        # uses (read the single rule, then reuse its maximumDuration untouched). The raw ISO string is
        # passed through as-is, not re-parsed, so a non-day form (P1Y, PT1H30M, ...) survives exactly.
        # Only issued when a permanence switch is bound WITHOUT its duration -- an unconditional read
        # would add a Graph call to every invocation. A failed read falls back to the parameter default
        # and warns rather than failing the whole call.
        $LiveEligibleDuration = $null
        if ($PSBoundParameters.ContainsKey('AllowPermanentEligibility') -and -not $PSBoundParameters.ContainsKey('EligibleDuration')) {
            try {
                $LiveRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Expiration_Admin_Eligibility" -f $PolicyId))
                if (-not [string]::IsNullOrWhiteSpace([string]$LiveRule.maximumDuration)) { $LiveEligibleDuration = [string]$LiveRule.maximumDuration }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read the live eligible-assignment maximum duration for policy '$PolicyId'; falling back to the -EligibleDuration default of $EligibleDuration day(s): $($PSItem.Exception.Message)"
            }
        }
        $LiveActiveDuration = $null
        if ($PSBoundParameters.ContainsKey('AllowPermanentActive') -and -not $PSBoundParameters.ContainsKey('ActiveDuration')) {
            try {
                $LiveRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Expiration_Admin_Assignment" -f $PolicyId))
                if (-not [string]::IsNullOrWhiteSpace([string]$LiveRule.maximumDuration)) { $LiveActiveDuration = [string]$LiveRule.maximumDuration }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read the live active-assignment maximum duration for policy '$PolicyId'; falling back to the -ActiveDuration default of $ActiveDuration day(s): $($PSItem.Exception.Message)"
            }
        }

        # Approval is patched as one rule, so what the caller did not supply -- the stage fields and
        # the approver side left unbound -- has to come from the live rule, or the PATCH would erase
        # it. Unlike the duration reads above, a failed read here is a REFUSAL of the whole call, not
        # a warning: there is no safe fallback for someone else's approvers. It is issued only when an
        # approval parameter is bound, and before any PATCH, so no other rule is half-applied either.
        $ApproversBound = $ApproverUserBound -or $ApproverGroupBound
        $ApprovalBound = $ApproversBound -or $PSBoundParameters.ContainsKey('RequireApproval')
        $LiveApprovalRule = $null
        $EffUser = @()
        $EffGroup = @()
        $LiveOther = @()
        $EffRequired = $false
        if ($ApprovalBound) {
            try {
                $LiveApprovalRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Approval_EndUser_Assignment" -f $PolicyId))
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Could not read the live approval rule for PIM policy '$PolicyId': $($PSItem.Exception.Message) Nothing was changed: the approval stage and the approvers not supplied on this call are carried over from the live rule, and without it they would be lost.")) `
                    -ErrorId 'ApprovalRuleReadFailed' -Category ReadError -TargetObject $PolicyId `
                    -InnerException $PSItem.Exception -Cmdlet $PSCmdlet
                return
            }

            # Only the first stage counts (PIM uses one), read through the single approver reader so
            # a beta { id } approver is understood. A bound side replaces that side; the unbound side
            # is the live ids of that kind. A live approver of any OTHER kind (requestorManager, for
            # example) belongs to neither side, so no parameter replaces it: it is kept as the raw
            # object it was read as, and sent back unchanged.
            $LiveStage = $null
            if ($null -ne $LiveApprovalRule -and $null -ne $LiveApprovalRule.setting) {
                $LiveStage = @($LiveApprovalRule.setting.approvalStages) | Where-Object { $null -ne $_ } | Select-Object -First 1
            }
            $LivePrimary = @()
            if ($null -ne $LiveStage) {
                $LivePrimary = @(@($LiveStage.primaryApprovers) | ForEach-Object { ConvertFrom-OERGraphApprover -Approver $_ })
                $LiveOther = @(@($LiveStage.primaryApprovers) | Where-Object {
                        $null -ne $_ -and (ConvertFrom-OERGraphApprover -Approver $_).UserType -eq ''
                    })
            }
            $EffUser = @(if ($ApproverUserBound) { $ResolvedUser } else { $LivePrimary | Where-Object { $_.UserType -eq 'User' -and $_.Id } | ForEach-Object { $_.Id } })
            $EffGroup = @(if ($ApproverGroupBound) { $ResolvedGroup } else { $LivePrimary | Where-Object { $_.UserType -eq 'Group' -and $_.Id } | ForEach-Object { $_.Id } })
            # Supplying approvers implies approval. The live isApprovalRequired never decides here:
            # this block only runs when -RequireApproval or an approver parameter is bound.
            $EffRequired = if ($ApproversBound) { $true } else { $RequireApproval }

            # With approvers bound, what will be sent is the two effective sides plus the carried
            # other-kind approvers; otherwise the live primary approvers go out as they are. Every
            # kind is counted either way.
            $EffApproverCount = if ($ApproversBound) { $EffUser.Count + $EffGroup.Count + $LiveOther.Count } else { $LivePrimary.Count }
            if ($EffRequired -and $EffApproverCount -eq 0) {
                $NoApproverMessage = if ($ApproversBound) {
                    "Approval cannot be required with no approver: after -ApproverUser/-ApproverGroup are applied, PIM policy '$PolicyId' would have none. Pass at least one approver."
                } else {
                    "Approval cannot be required with no approver: PIM policy '$PolicyId' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup."
                }
                Write-CmdletError -Message ([System.Exception]::new($NoApproverMessage)) `
                    -ErrorId 'ApproverRequired' -Category InvalidArgument -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
        }

        $RuleParams = @{}
        if ($PSBoundParameters.ContainsKey('ActivationMaxHours'))      { $RuleParams.ActivationMaxHours = $ActivationMaxHours }
        if ($PSBoundParameters.ContainsKey('AuthenticationContextId')) { $RuleParams.AuthenticationContextId = $AuthenticationContextId }
        if ($PSBoundParameters.ContainsKey('ActivationEnabledRules'))  { $RuleParams.ActivationEnabledRules = $ActivationEnabledRules }
        # $ActivationEnabledRulesReported / $AuthenticationContextIdReported carry the values that
        # were ACTUALLY sent. A reconciled rule is patched even though its parameter was never bound,
        # so echoing the parameter variable in the Patched summary below would report $null for a
        # rule that carried a real value.
        $ActivationEnabledRulesReported = $ActivationEnabledRules
        $AuthenticationContextIdReported = $AuthenticationContextId
        if ($Resolution -and $Resolution.Action -eq 'ClearMfa') {
            $RuleParams.ActivationEnabledRules = $Resolution.ActivationEnabledRules
            $ActivationEnabledRulesReported = $Resolution.ActivationEnabledRules
            Write-Warning "Policy '$PolicyId': $($Resolution.Reason)"
        }
        if ($Resolution -and $Resolution.Action -eq 'DisableAuthContext') {
            $RuleParams.AuthenticationContextId = $Resolution.AuthenticationContextId
            $AuthenticationContextIdReported = $Resolution.AuthenticationContextId
            Write-Warning "Policy '$PolicyId': $($Resolution.Reason)"
        }
        if ($PSBoundParameters.ContainsKey('ActiveEnabledRules'))      { $RuleParams.ActiveEnabledRules = $ActiveEnabledRules }
        if ($PSBoundParameters.ContainsKey('EligibleAlertRecipient'))  { $RuleParams.EligibleAlertRecipient = $EligibleAlertRecipient }
        if ($PSBoundParameters.ContainsKey('ActiveAlertRecipient'))    { $RuleParams.ActiveAlertRecipient = $ActiveAlertRecipient }
        if ($PSBoundParameters.ContainsKey('ActivationAlertRecipient')){ $RuleParams.ActivationAlertRecipient = $ActivationAlertRecipient }
        # Bound approvers are sent as the two effective sides together -- rebuilding the unbound side
        # from its live ids is how that side is carried -- followed by the live approvers of any other
        # kind, as read (New-OERPimRuleSet passes those through unchanged). Unbound, New-OERPimRuleSet
        # carries the live stage's approvers itself. Either way New-OERPimRuleSet owns the wire shape:
        # it sends every user and group approver in the Graph beta shape (id and isBackup), so the
        # v1.0 userId/groupId objects built here never reach the PATCH body as they are.
        if ($ApprovalBound) {
            $RuleParams.RequireApproval = $EffRequired
            $RuleParams.LiveApprovalRule = $LiveApprovalRule
            if ($ApproversBound) {
                $RuleParams.PrimaryApprover = @($EffUser | ForEach-Object { New-OERApproverObject -Spec @{ User = $_ } }) +
                    @($EffGroup | ForEach-Object { New-OERApproverObject -Spec @{ Group = $_ } }) +
                    @($LiveOther)
            }
        }

        # The eligible- and active-expiration rules are each a unit: bind either the duration or the
        # permanence switch and both fields are sent so the rule is never half-updated. When only the
        # permanence switch was bound, prefer the live value read above over the parameter default (see
        # the read block above) so a caller enabling permanence does not silently rewrite an existing
        # time-bound maximum. $EligibleDurationDaysReported/$ActiveDurationDaysReported carry the day
        # count that was ACTUALLY sent, for the Patched summary built below (audit: the summary used to
        # echo the unbound -EligibleDuration/-ActiveDuration parameter variable instead).
        $EligibleDurationDaysReported = $EligibleDuration
        if ($PSBoundParameters.ContainsKey('EligibleDuration') -or $PSBoundParameters.ContainsKey('AllowPermanentEligibility')) {
            if ($PSBoundParameters.ContainsKey('EligibleDuration')) {
                $RuleParams.EligibleDuration = ConvertTo-OERDuration -Days $EligibleDuration
                $EligibleDurationDaysReported = $EligibleDuration
            } elseif ($LiveEligibleDuration) {
                $RuleParams.EligibleDuration = $LiveEligibleDuration
                $EligibleDurationDaysReported = ConvertFrom-OERDuration -Duration $LiveEligibleDuration -Unit Days
            } else {
                $RuleParams.EligibleDuration = ConvertTo-OERDuration -Days $EligibleDuration
                $EligibleDurationDaysReported = $EligibleDuration
            }
            if ($AllowPermanentEligibility) { $RuleParams.AllowPermanentEligibility = $true }
        }
        $ActiveDurationDaysReported = $ActiveDuration
        if ($PSBoundParameters.ContainsKey('ActiveDuration') -or $PSBoundParameters.ContainsKey('AllowPermanentActive')) {
            if ($PSBoundParameters.ContainsKey('ActiveDuration')) {
                $RuleParams.ActiveDuration = ConvertTo-OERDuration -Days $ActiveDuration
                $ActiveDurationDaysReported = $ActiveDuration
            } elseif ($LiveActiveDuration) {
                $RuleParams.ActiveDuration = $LiveActiveDuration
                $ActiveDurationDaysReported = ConvertFrom-OERDuration -Duration $LiveActiveDuration -Unit Days
            } else {
                $RuleParams.ActiveDuration = ConvertTo-OERDuration -Days $ActiveDuration
                $ActiveDurationDaysReported = $ActiveDuration
            }
            if ($AllowPermanentActive) { $RuleParams.AllowPermanentActive = $true }
        }

        $Rules = New-OERPimRuleSet @RuleParams

        # Graph validates the MFA / authentication-context exclusion ASYMMETRICALLY, so the order in
        # which these two rules are PATCHed is load-bearing, not incidental. Each rule is a separate
        # PATCH, so whichever goes second is validated against the state the first one left:
        #   - ENABLING an authentication context while MFA is still on is ACCEPTED (that acceptance is
        #     the defect issue #54 exists to reconcile);
        #   - ENABLING MFA while an authentication context is still on is REJECTED, observed live as
        #     'MfaAndAcrsConflict: The Mfa and Acrs policy settings cannot be enabled simultaneously.'
        # A run that disabled the context AFTER sending MFA therefore lost the MFA rule to that
        # rejection and left the policy with NEITHER protection in force.
        # Order by what the authentication-context rule DOES, not by a fixed sequence: a rule that
        # DISABLES the context goes FIRST (the Acrs side is already off when MFA is switched on), a
        # rule that ENABLES it goes LAST (the MFA flag is already gone by then). Both orderings avoid
        # a transient combination Graph rejects. This applies to any caller reaching the patch loop
        # with both rules built -- the reconcile above is only one of the ways that happens.
        # New-OERPimRuleSet is a shared, transport-free builder that owns rule SHAPE, not wire order:
        # do not move this there, and do not "tidy" it back into a fixed order.
        if ($null -ne $Rules) {
            $Ordered = @($Rules)
            $AcAt = -1
            $EnAt = -1
            for ($Index = 0; $Index -lt $Ordered.Count; $Index++) {
                if ($Ordered[$Index].id -eq 'AuthenticationContext_EndUser_Assignment') { $AcAt = $Index }
                elseif ($Ordered[$Index].id -eq 'Enablement_EndUser_Assignment') { $EnAt = $Index }
            }
            if ($AcAt -ge 0 -and $EnAt -ge 0) {
                $AcMustLead = -not [bool]$Ordered[$AcAt].isEnabled
                $AcLeadsNow = $AcAt -lt $EnAt
                if ($AcMustLead -ne $AcLeadsNow) {
                    $Swap = $Ordered[$AcAt]
                    $Ordered[$AcAt] = $Ordered[$EnAt]
                    $Ordered[$EnAt] = $Swap
                    $Rules = $Ordered
                }
            }
        }

        # $Sent tracks the rule ids that actually passed ShouldProcess this run -- a rule declined at
        # an interactive -Confirm prompt is built (it is in $Rules) but never sent, and must not be
        # reported as patched (see $Patched below) or counted toward Applied.
        $Sent = [System.Collections.Generic.List[string]]::new()
        $Failed = [System.Collections.Generic.List[string]]::new()
        $Processed = $false
        foreach ($Rule in $Rules) {
            if ($PSCmdlet.ShouldProcess("PIM policy $PolicyId", "Patch rule $($Rule.id)")) {
                $Processed = $true
                $Sent.Add($Rule.id)
                try {
                    Invoke-OERGraphRequest -Method PATCH -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/{1}" -f $PolicyId, $Rule.id)) -Body $Rule | Out-Null
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Failed.Add($Rule.id)
                    Write-Warning "Rule '$($Rule.id)' was not applied: $($PSItem.Exception.Message)"
                }
            }
        }

        # A per-rule -Confirm decline can accept one half of a reconciled pair and refuse the other,
        # which leaves the policy in exactly the mutually exclusive combination this cmdlet just
        # worked to avoid. Silence here would read as success.
        if ($Resolution -and $Resolution.Action -in @('ClearMfa', 'DisableAuthContext')) {
            $ReconciledRuleId = if ($Resolution.Action -eq 'ClearMfa') { 'Enablement_EndUser_Assignment' } else { 'AuthenticationContext_EndUser_Assignment' }
            $PartnerRuleId = if ($Resolution.Action -eq 'ClearMfa') { 'AuthenticationContext_EndUser_Assignment' } else { 'Enablement_EndUser_Assignment' }
            if ($Sent.Contains($PartnerRuleId) -and -not $Sent.Contains($ReconciledRuleId)) {
                Write-Warning "Rule '$ReconciledRuleId' was declined while '$PartnerRuleId' was applied, so PIM policy '$PolicyId' still requires both multi-factor authentication and an authentication context on activation. Re-run and accept both, or fix it with Get-OERGroupPimPolicy and a follow-up Set-OERGroupPimPolicy."
            }
        }

        # No rule was actually patched (e.g. -WhatIf, or every rule declined under -Confirm), so there
        # is no applied state to report. Returning here keeps the summary object honest -- it never
        # claims Applied = true for a run that changed nothing, mirroring Set-OERRoleManagementPolicy.
        if (-not $Processed) { return }

        # Report only what was actually SENT this run (see $Sent above) -- not merely bound. A rule
        # declined at an interactive -Confirm prompt was built (it is in $Rules, so $RuleParams and
        # $PSBoundParameters both agree it was requested) but never reached Graph, so gating on
        # binding alone would report a setting that was not applied (e.g. an MFA-on-activation
        # requirement that was never sent reads as "MFA is now required"). A field the caller never
        # bound is still absent entirely -- a null or false here reads as an authoritative policy
        # value and is not one (the run patched a subset of rules; Get-OERGroupPimPolicy is the
        # authority on the resulting state).
        $Patched = [ordered]@{}
        if ($Sent.Contains('Expiration_EndUser_Assignment'))            { $Patched.ActivationMaxHours = $ActivationMaxHours }
        if ($Sent.Contains('AuthenticationContext_EndUser_Assignment')) { $Patched.AuthenticationContextId = $AuthenticationContextIdReported }
        if ($Sent.Contains('Enablement_EndUser_Assignment'))            { $Patched.ActivationEnabledRules = $ActivationEnabledRulesReported }
        if ($Sent.Contains('Enablement_Admin_Assignment'))              { $Patched.ActiveEnabledRules = $ActiveEnabledRules }
        if ($Sent.Contains('Expiration_Admin_Eligibility'))             { $Patched.EligibleDurationDays = $EligibleDurationDaysReported }
        if ($Sent.Contains('Expiration_Admin_Assignment'))              { $Patched.ActiveDurationDays = $ActiveDurationDaysReported }
        # The expiration rule is a unit (see the $RuleParams build above): binding either the
        # duration or the permanence switch sends BOTH fields to Graph on the SAME rule, so both are
        # gated on whether that one rule id was actually sent, not on $RuleParams alone.
        if ($Sent.Contains('Expiration_Admin_Eligibility'))             { $Patched.AllowPermanentEligibility = [bool]$AllowPermanentEligibility }
        if ($Sent.Contains('Expiration_Admin_Assignment'))              { $Patched.AllowPermanentActive = [bool]$AllowPermanentActive }
        if ($Sent.Contains('Notification_Admin_Admin_Eligibility'))     { $Patched.EligibleAlertRecipient = $EligibleAlertRecipient }
        if ($Sent.Contains('Notification_Admin_Admin_Assignment'))      { $Patched.ActiveAlertRecipient = $ActiveAlertRecipient }
        if ($Sent.Contains('Notification_Admin_EndUser_Assignment'))    { $Patched.ActivationAlertRecipient = $ActivationAlertRecipient }
        # The effective values, not the parameters: approval is reported as it was sent (true when
        # approvers were supplied), and both approver sides as the object ids sent, the carried side
        # included.
        if ($Sent.Contains('Approval_EndUser_Assignment')) {
            $Patched.RequireApproval = $EffRequired
            if ($ApproversBound) {
                $Patched.ApproverUser = @($EffUser)
                $Patched.ApproverGroup = @($EffGroup)
            }
        }

        $Out = ConvertTo-OERGroupPimPolicyResult -GroupId $GroupId -PolicyId $PolicyId -AccessType $AccessType `
            -Patched $Patched -FailedRules $Failed.ToArray()
        # Applied requires both that nothing rejected AND that every rule this run built was actually
        # sent -- a decline is neither a failure (it never reached Graph, so it is not in $Failed) nor
        # a success, and must not be masked by the converter's default Failed-only computation.
        $Out.Applied = ($Failed.Count -eq 0 -and $Sent.Count -eq @($Rules).Count)
        $Out

        # A rejected rule is a PARTIALLY APPLIED high-privilege PIM policy change. Emitting only a
        # Write-Warning leaves $? true, does not trip -ErrorAction Stop, and lets a try/catch see
        # success, so automation (including Invoke-OERStructure) cannot detect the half-apply. Write a
        # non-terminating error AFTER the summary object so a caller that traps the error has still
        # received the object describing what did apply.
        if ($Failed.Count -gt 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "PIM policy '$PolicyId' for group '$GroupId' was only partially applied. " +
                    "Graph rejected $($Failed.Count) of $($Sent.Count) rule(s): $($Failed -join ', '). " +
                    "Run Get-OERGroupPimPolicy -Group '$Group' -AccessType $AccessType to read the resulting state.")) `
                -ErrorId 'PolicyRulesRejected' `
                -Category WriteError `
                -TargetObject $PolicyId `
                -Cmdlet $PSCmdlet
        }
    }
}
