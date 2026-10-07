function Set-OERGroupPimPolicy {
    <#
    .SYNOPSIS
    Updates the PIM-for-groups activation template (rule set) for a group.

    .DESCRIPTION
    Builds the activation rule set with the private New-OERPimRuleSet helper and PATCHes each rule on the
    group's roleManagementPolicy (resolved via Get-OERPimGroupPolicyId). Only the rules whose governing
    parameters are bound are patched -- omitted parameters are left unchanged (surgical patch). Every
    rule is confirmed first, one confirmation per rule, and only then are the confirmed rules sent, each
    PATCHed on its own so a single rejected rule does not abort the rest. The authentication-context
    rule and the activation enablement rule are the exception, since together they decide whether
    activation requires MFA or an authentication context: when both are sent and Microsoft Graph
    accepts the first but rejects the second, the first is PATCHed straight back to its live value, so
    activation keeps the protection it had before the call instead of being left with neither. That
    rule is then not reported as changed, and the PolicyRulesRejected error says it was put back. Its live
    value is the one the mutual-exclusion reconcile below read, or else it is read once before the
    first PATCH; should that read fail, a warning says so before anything is sent, and the rule cannot
    be put back. Should putting it back fail, the rule stays reported and the error says how to set
    the protection the group needs. Warnings about rejected rules are written only after every rule
    and the put-back were sent. The result is built by the
    private ConvertTo-OERGroupPimPolicyResult and tagged Omnicit.EntraRBAC.GroupPimPolicyResult (with the
    shared Omnicit.EntraRBAC.GroupPimPolicy type name still present underneath, for existing consumers):
    it lists ONLY the settings that were actually SENT to Graph -- a setting whose parameter was not
    bound, and was not reconciled onto the wire by the mutual-exclusion rule below, is absent from the
    object, never null or false -- plus GroupId, PolicyId, AccessType, Applied (true only when every
    rule this run built was both sent and accepted by Graph), and FailedRules (the ids that were sent
    and rejected; a declined rule is not a failure and is not listed here either). A rule the mutual-
    exclusion reconcile sent on the caller's behalf IS reported, with the value actually sent, even
    though its own parameter was never bound -- see the reconcile paragraph below. This summary is not
    a read of the resulting policy state; use Get-OERGroupPimPolicy for that. A group whose policy
    assignment for the requested access type Microsoft Graph does not list -- in practice a group
    created moments ago (replication delay) -- produces a non-terminating PimPolicyNotFound error;
    re-running usually succeeds. Graph lists the policies of a group that was never used with PIM for
    Groups too, and the first update of such a policy onboards the group to PIM for Groups, which
    cannot be undone (Microsoft Graph documentation, "Onboarding groups to PIM for Groups"). A refused
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
    is sent back unchanged. Supplying approvers on either side implies approval is required, so
    -RequireApproval $false beside -ApproverUser or -ApproverGroup, an empty list included, is a
    contradiction: it is refused with a non-terminating MutuallyExclusiveParameter error before
    anything is looked up or sent, whatever other parameters the call binds (pass -RequireApproval
    $false alone to turn approval off). -RequireApproval $true needs at least one approver, either
    supplied or already on the live rule; with none, a non-terminating ApproverRequired error is
    written and nothing is sent. Every approver value is resolved to an object id first (a user by
    UPN or id, a group by display name or id), before the group is looked up, and nothing is sent
    unless every value resolves: a value that matches nothing is a non-terminating ApproverNotFound
    error, a group display name that several groups share is a non-terminating AmbiguousApproverName
    error whose message names the candidate ids, and a lookup that fails (insufficient permission,
    throttling, a dead transport, ...) is reported as that error itself, never as ApproverNotFound.
    Stage fields this cmdlet has no parameter for, such as the approval timeout and whether
    approvers must justify, carry over from the live stage; a policy with no stage yet gets a 1-day
    timeout with approver justification required. Any of the
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
    the live stage and approvers for a later re-enable; it cannot be combined with -ApproverUser or
    -ApproverGroup, even an empty list, and that call is refused with MutuallyExclusiveParameter
    before anything is looked up or sent. When omitted and neither approver parameter is bound, the
    approval rule is not patched.

    .PARAMETER ApproverUser
    The user approvers, each a user principal name or user object id, resolved to object ids before
    anything is sent. Replaces the user approvers on the live rule; the group approvers are kept.
    Supplying it implies -RequireApproval $true, so beside -RequireApproval $false it is refused with
    MutuallyExclusiveParameter before anything is looked up or sent. An empty list clears the user
    side (and is refused beside -RequireApproval $false all the same). A value that matches no user
    refuses the whole call with ApproverNotFound; a lookup that fails refuses it too, reported as
    that error itself. The same user named twice (by UPN and by id, or in a different letter case)
    is sent once.

    .PARAMETER ApproverGroup
    The group approvers, each a group display name or group object id, resolved to object ids before
    anything is sent. Replaces the group approvers on the live rule; the user approvers are kept.
    Supplying it implies -RequireApproval $true, so beside -RequireApproval $false it is refused with
    MutuallyExclusiveParameter before anything is looked up or sent. An empty list clears the group
    side (and is refused beside -RequireApproval $false all the same). A value that matches no group
    refuses the whole call with ApproverNotFound, and a display name several groups share refuses it
    with AmbiguousApproverName, naming the candidate ids (pass the object id instead); a lookup that
    fails refuses it too, reported as that error itself.

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

        [ValidateNotNullOrEmpty()]
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

        # Approvers apply only when approval is required, so -RequireApproval $false beside an approver
        # parameter contradicts itself: refused here, before the approver lookup and every request, so
        # a refused call looks nothing up and sends nothing, the other rules bound on the same call
        # included. "Bound" means bound, so an empty list counts. Resolve-OERGraphApproverSet throws the
        # same id as a backstop should a caller ever let the combination through.
        if ($PSBoundParameters.ContainsKey('RequireApproval') -and -not $RequireApproval -and
            ($PSBoundParameters.ContainsKey('ApproverUser') -or $PSBoundParameters.ContainsKey('ApproverGroup'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    '-RequireApproval $false and -ApproverUser/-ApproverGroup contradict each other: approvers apply ' +
                    'only when approval is required. Pass -RequireApproval $false alone to turn approval off (the ' +
                    'approvers already on the rule are kept), or pass the approvers without -RequireApproval $false. ' +
                    'Nothing was looked up or sent.')) `
                -ErrorId 'MutuallyExclusiveParameter' `
                -Category InvalidArgument `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }

        # Approvers are resolved to object ids before anything else, all or nothing: one value that
        # does not resolve refuses the whole call before the group is even looked up, so nothing is
        # sent. Resolve-OERApproverInput owns the rules (a blank value is skipped, the same principal
        # named twice is kept once in first-seen order) and is shared with
        # Set-OERDirectoryRoleManagementPolicy; the refusal is reported here, under this cmdlet's id.
        # Three outcomes, three reports: an ambiguous name is AmbiguousApproverName (the resolver's
        # text names the candidate ids), only an approver that matches nothing (ApproverUnresolved) is
        # ApproverNotFound, and anything else -- a 403, an exhausted 429, a 5xx -- is not evidence that
        # the approver is missing, so it is published as itself.
        $ApproverUserBound = $PSBoundParameters.ContainsKey('ApproverUser')
        $ApproverGroupBound = $PSBoundParameters.ContainsKey('ApproverGroup')
        try {
            $ApproverInput = Resolve-OERApproverInput -User $ApproverUser -Group $ApproverGroup
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError -Message ([System.Exception]::new("Could not resolve approver '$($PSItem.TargetObject)': $($PSItem.Exception.Message)")) -ErrorId 'AmbiguousApproverName' -Category InvalidArgument -TargetObject $PSItem.TargetObject -Cmdlet $PSCmdlet
                return
            }
            if (([string]$PSItem.FullyQualifiedErrorId).StartsWith('ApproverUnresolved', [System.StringComparison]::Ordinal)) {
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'ApproverNotFound' -Category ObjectNotFound -TargetObject $PSItem.TargetObject -Cmdlet $PSCmdlet
                return
            }
            $PSCmdlet.WriteError($PSItem)
            return
        }
        $ResolvedUser = $ApproverInput.User
        $ResolvedGroup = $ApproverInput.Group

        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
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
            # Anything else the resolver raised -- a 403, an exhausted 429, a 5xx -- is not evidence that
            # no such group exists: surface it as itself, never as the not-found below.
            $PSCmdlet.WriteError($PSItem)
            return
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

        # A FAILED LOOKUP IS NOT AN ABSENT POLICY -- same split as Get-OERGroupPimPolicy.
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
                    "Microsoft Graph does not list a PIM-for-groups policy for '$AccessType' access on group " +
                    "'$GroupId' yet. A group created moments ago can take a short while before its policies are " +
                    'listed (replication delay), and re-running usually succeeds.')) `
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
        # Each live rule a reconcile reads is kept by id: should both halves of the pair be sent and
        # Microsoft Graph reject the second, Send-OERPimRulePatch puts the first back to this value,
        # so it is not read a second time.
        $LiveRuleById = @{}
        if ($WantsAc -and $WantsMfa) {
            $Resolution = Resolve-OERPimActivationConflict -CallerRequestsAuthContext -CallerRequestsMfa `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId $AuthenticationContextId `
                -EffectiveActivationEnabledRules @($ActivationEnabledRules)
        } elseif ($WantsAc -and -not $AerBound) {
            $LiveEnabledRules = $null
            try {
                $LiveRule = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Enablement_EndUser_Assignment" -f $PolicyId))
                $LiveEnabledRules = @($LiveRule.enabledRules)
                if ($null -ne $LiveRule) { $LiveRuleById['Enablement_EndUser_Assignment'] = $LiveRule }
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
                if ($null -ne $LiveRule) { $LiveRuleById['AuthenticationContext_EndUser_Assignment'] = $LiveRule }
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

            # The Graph approver semantics -- first stage only, a bound side replaces that side, the
            # unbound side and any approver of another kind (requestorManager, for example) are
            # carried from the live rule, supplying approvers implies approval, and the approver
            # count -- are owned by Resolve-OERGraphApproverSet, shared with
            # Set-OERDirectoryRoleManagementPolicy. The live isApprovalRequired never decides here:
            # this block only runs when -RequireApproval or an approver parameter is bound.
            $ApproverSet = Resolve-OERGraphApproverSet -LiveApprovalRule $LiveApprovalRule `
                -UserBound $ApproverUserBound -GroupBound $ApproverGroupBound `
                -ResolvedUser $ResolvedUser -ResolvedGroup $ResolvedGroup `
                -RequireApprovalBound ($PSBoundParameters.ContainsKey('RequireApproval')) -RequireApproval $RequireApproval
            $EffUser = @($ApproverSet.EffUser)
            $EffGroup = @($ApproverSet.EffGroup)
            $LiveOther = @($ApproverSet.LiveOther)
            $EffRequired = $ApproverSet.EffRequired
            if ($ApproverSet.NoApprover) {
                $NoApproverMessage = if ($ApproverSet.NoApproverReason -eq 'Bound') {
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

        # The MFA / authentication-context PATCH order is load-bearing; Get-OERPimRulePatchOrder owns it (see its help).
        if ($null -ne $Rules) { $Rules = @(Get-OERPimRulePatchOrder -Rule @($Rules)) }

        $RulesPath = Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules" -f $PolicyId)

        # Every rule is confirmed before any is sent. $Sent tracks the rule ids that actually passed
        # ShouldProcess this run -- a rule declined at an interactive -Confirm prompt is built (it is
        # in $Rules) but never sent, and must not be reported as patched (see $Patched below) or
        # counted toward Applied.
        $ToSend = [System.Collections.Generic.List[object]]::new()
        foreach ($Rule in $Rules) {
            if ($PSCmdlet.ShouldProcess("PIM policy $PolicyId", "Patch rule $($Rule.id)")) { $ToSend.Add($Rule) }
        }
        $Sent = [System.Collections.Generic.List[string]]::new()
        foreach ($Rule in $ToSend) { $Sent.Add([string]$Rule.id) }
        $Processed = $Sent.Count -gt 0

        # When both halves of the MFA / authentication-context pair are sent, Send-OERPimRulePatch
        # needs the live value of the first (in patch order) to put it back should Microsoft Graph
        # reject the second. A reconcile above may already have read it; otherwise it is read here,
        # once, before the first PATCH. A failed read only costs the put-back, so it is a warning,
        # written now -- before any PATCH, so a -WarningAction Stop caller stops with nothing sent.
        $SentPair = @($Sent | Where-Object { $_ -in @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment') })
        if ($SentPair.Count -eq 2 -and -not $LiveRuleById.ContainsKey($SentPair[0])) {
            try {
                $FirstLive = Invoke-OERGraphRequest -Uri ('{0}/{1}' -f $RulesPath, $SentPair[0])
                if ($null -ne $FirstLive) { $LiveRuleById[$SentPair[0]] = $FirstLive }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read the live rule '$($SentPair[0])' of PIM policy '$PolicyId' before the update, so it cannot be put back should Microsoft Graph reject '$($SentPair[1])': $($PSItem.Exception.Message)"
            }
        }

        # Send-OERPimRulePatch owns the per-rule PATCH and the pair put-back (see its help). It writes
        # nothing itself: its messages are written here, once every rule and the put-back were sent,
        # so a -WarningAction Stop caller is never stopped half-way through the rule set.
        $SendResult = $null
        $Failed = [System.Collections.Generic.List[string]]::new()
        if ($ToSend.Count -gt 0) {
            $SendResult = Send-OERPimRulePatch -Rule $ToSend.ToArray() -RulesPath $RulesPath -LiveRule @($LiveRuleById.Values) -PolicyLabel "PIM policy '$PolicyId'"
            foreach ($Message in $SendResult.Warning) { Write-Warning $Message }
            $Failed.AddRange([string[]]$SendResult.Failed)
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
        # authority on the resulting state). A rule Send-OERPimRulePatch put back to its live value
        # was sent, but did not change, so $Reported is $Sent without it.
        $Reported = [System.Collections.Generic.List[string]]::new($Sent)
        if ($SendResult.Restored) { [void]$Reported.Remove([string]$SendResult.Restored) }
        $Patched = [ordered]@{}
        if ($Reported.Contains('Expiration_EndUser_Assignment'))            { $Patched.ActivationMaxHours = $ActivationMaxHours }
        if ($Reported.Contains('AuthenticationContext_EndUser_Assignment')) { $Patched.AuthenticationContextId = $AuthenticationContextIdReported }
        if ($Reported.Contains('Enablement_EndUser_Assignment'))            { $Patched.ActivationEnabledRules = $ActivationEnabledRulesReported }
        if ($Reported.Contains('Enablement_Admin_Assignment'))              { $Patched.ActiveEnabledRules = $ActiveEnabledRules }
        if ($Reported.Contains('Expiration_Admin_Eligibility'))             { $Patched.EligibleDurationDays = $EligibleDurationDaysReported }
        if ($Reported.Contains('Expiration_Admin_Assignment'))              { $Patched.ActiveDurationDays = $ActiveDurationDaysReported }
        # The expiration rule is a unit (see the $RuleParams build above): binding either the
        # duration or the permanence switch sends BOTH fields to Graph on the SAME rule, so both are
        # gated on whether that one rule id was actually sent, not on $RuleParams alone.
        if ($Reported.Contains('Expiration_Admin_Eligibility'))             { $Patched.AllowPermanentEligibility = [bool]$AllowPermanentEligibility }
        if ($Reported.Contains('Expiration_Admin_Assignment'))              { $Patched.AllowPermanentActive = [bool]$AllowPermanentActive }
        if ($Reported.Contains('Notification_Admin_Admin_Eligibility'))     { $Patched.EligibleAlertRecipient = $EligibleAlertRecipient }
        if ($Reported.Contains('Notification_Admin_Admin_Assignment'))      { $Patched.ActiveAlertRecipient = $ActiveAlertRecipient }
        if ($Reported.Contains('Notification_Admin_EndUser_Assignment'))    { $Patched.ActivationAlertRecipient = $ActivationAlertRecipient }
        # The effective values, not the parameters: approval is reported as it was sent (true when
        # approvers were supplied), and both approver sides as the object ids sent, the carried side
        # included.
        if ($Reported.Contains('Approval_EndUser_Assignment')) {
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
            $Message = "PIM policy '$PolicyId' for group '$GroupId' was only partially applied. " +
                "Graph rejected $($Failed.Count) of $($Sent.Count) rule(s): $($Failed -join ', ')."
            if ($SendResult.Restored) {
                $Message += " Rule '$($SendResult.Restored)', which Microsoft Graph had accepted, was put back to its value before " +
                    "this call, since it and '$($SendResult.PairSecond)' together decide whether activation requires multi-factor " +
                    'authentication or an authentication context: activation keeps the protection it had before the call.'
            } elseif ($SendResult.RestoreError) {
                $Message += " Rule '$($SendResult.PairFirst)' had been accepted, and putting it back to its value before this call " +
                    "failed too ($($SendResult.RestoreError)), so it stays changed: activation may now require neither " +
                    'multi-factor authentication nor an authentication context. Run the same command again, or run ' +
                    'Set-OERGroupPimPolicy with -ActivationEnabledRules or -AuthenticationContextId set to the protection this group needs.'
            }
            $Message += " Run Get-OERGroupPimPolicy -Group '$Group' -AccessType $AccessType to read the resulting state."
            Write-CmdletError `
                -Message ([System.Exception]::new($Message)) `
                -ErrorId 'PolicyRulesRejected' `
                -Category WriteError `
                -TargetObject $PolicyId `
                -Cmdlet $PSCmdlet
        }
    }
}
