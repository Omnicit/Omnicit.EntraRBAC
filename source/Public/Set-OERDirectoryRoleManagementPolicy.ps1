function Set-OERDirectoryRoleManagementPolicy {
    <#
    .SYNOPSIS
    Updates the PIM role management policy of a Microsoft Entra directory role.

    .DESCRIPTION
    Tunes HOW PIM behaves for a Microsoft Entra directory role: activation window, MFA /
    justification / ticket on activation, approval and approvers, authentication context, eligible
    and active permanence plus max durations, MFA / justification on admin active assignment, and
    notifications. The parameter surface is the one Set-OERRoleManagementPolicy has for an Azure
    role, without the Azure scope parameters: a directory role policy always lives at tenant scope
    ('/'). Every toggle is a [bool] so the policy can be both tightened and relaxed; an omitted
    parameter leaves its rule untouched. Identify the policy by -Role (a display name or role
    definition id, resolved through Resolve-OERDirectoryRoleDefinitionId) or directly by -PolicyId,
    which also binds from the pipeline, so Get-OERDirectoryRoleManagementPolicy output pipes
    straight in.

    Every call goes through Microsoft Graph v1.0 (policies/roleManagementPolicyAssignments and
    policies/roleManagementPolicies), never the beta endpoint PIM for Groups is pinned to, and no
    Azure Resource Manager token is acquired. The live rules are read first and each supplied
    setting is overlaid on its rule (read-modify-write, through the same builder the Azure cmdlet
    uses); a rule that ends up identical to the live one is not sent, and when no rule differs a
    non-terminating NoChange error is written and nothing is sent. Each changed rule is then
    PATCHed on its own, at policies/roleManagementPolicies/{policyId}/rules/{ruleId}, in the order
    Get-OERPimRulePatchOrder decides: a rule that disables the authentication context goes before
    the activation enablement rule, and a rule that enables it goes after, so Microsoft Graph never
    sees MFA and an authentication context enabled together between two requests. The call asks
    for ONE confirmation (ConfirmImpact Medium), naming the policy and every rule id it is about to
    send; -WhatIf sends nothing and returns nothing. A rule Microsoft Graph rejects does not stop
    the others: the cmdlet returns the policy object with the rejected rule at its live value and
    only the accepted rule ids in ChangedRuleIds, and then writes a non-terminating
    PolicyRulesRejected error naming the rejected rules, so a partial apply is detectable with
    -ErrorAction Stop or $?. The authentication-context rule and the activation enablement rule are
    the exception, since together they decide whether activation requires MFA or an authentication
    context: when both are sent and Microsoft Graph accepts the first but rejects the second, the
    first is PATCHed straight back to its live value, so activation keeps the protection it had
    before the call instead of being left with neither. That rule is then left out of
    ChangedRuleIds as well, and the error says it was put back. Should putting it back fail too,
    the rule stays in ChangedRuleIds and the error states what activation of the role now requires
    and how to set it. The returned object is the same Omnicit.EntraRBAC.RoleManagementPolicy
    that Get-OERDirectoryRoleManagementPolicy returns, with Scope '/', plus ChangedRuleIds.

    Approvers follow the Microsoft Graph semantics of Set-OERGroupPimPolicy, not the whole-list
    replacement of Set-OERRoleManagementPolicy. Binding -ApproverUser replaces the user approvers
    only and -ApproverGroup the group approvers only; the side left unbound is carried over from
    the live approval stage, and a live approver of any other kind (a requestor's manager, for
    example) is never replaced by either parameter and is sent back unchanged. An explicit empty
    list clears its side. Supplying approvers on either side implies approval is required, even
    beside -RequireApproval $false. Every approver value is resolved to an object id first (a user
    by user principal name or id, a group by display name or id), and nothing is read or sent unless
    every value resolves: a value that matches nothing is a non-terminating ApproverNotFound error, a
    group display name that several groups share is a non-terminating AmbiguousApproverName error
    whose message names the candidate ids, and a lookup that fails (insufficient permission,
    throttling, a dead transport, ...) is reported as that error itself, never as ApproverNotFound.
    Approval required with no approver left -- -RequireApproval $true on a stage without one, or
    approver parameters that clear every approver -- is a non-terminating ApproverRequired error and
    nothing is sent.
    -RequireApproval alone changes only whether approval is required: the live stage and its
    approvers stay on the rule for a later re-enable. Stage fields this cmdlet has no parameter for
    (the approval timeout, whether approvers must justify) carry over from the live stage; a policy
    with no stage yet gets a 1-day timeout with approver justification required.

    PIM treats an enabled authentication context and MFA on activation as mutually exclusive.
    Asking for both in one call (a non-empty -AuthenticationContextId with -RequireMfaOnActivation
    $true) is refused with a non-terminating InvalidPolicyChange error and nothing is sent. Asking
    for one side clears the other: a non-empty -AuthenticationContextId removes MFA from the live
    activation enablement rule, and -RequireMfaOnActivation $true disables a live authentication
    context; either reconcile is reported with a warning. A combination the caller did not touch is
    left alone: an unrelated change to a policy that already holds both is sent without clearing
    MFA. That is the Microsoft Graph convention, since each rule is PATCHed on its own; it differs
    from Set-OERRoleManagementPolicy, which clears MFA from such a policy on any change because
    Azure Resource Manager validates the complete rule set on every write. -AuthenticationContextId
    is checked for its c<number> shape only; unlike Set-OERGroupPimPolicy, the value is not looked
    up in the tenant, and Microsoft Graph accepts a claim value no authentication context defines,
    which end users then fail at activation. Check it with Get-OERAuthenticationContext first.

    Notification rules are changed with the same builder objects the Azure cmdlet uses: pass one or
    more New-OERPolicyNotificationRule results to -NotificationRule.

    For least privilege, RoleManagementPolicy.ReadWrite.Directory is enough for the rule update and
    RoleManagement.Read.Directory resolves -Role; the module's default sign-in scope list already
    requests the broader RoleManagement.ReadWrite.Directory, which covers both. -ApproverUser and
    -ApproverGroup also read users and groups to resolve them. A delegated caller additionally
    needs the Privileged Role Administrator role.

    .PARAMETER Role
    The directory role: display name (e.g. 'Reports Reader') or role definition GUID. A GUID is
    used as the id, lower-cased, with no lookup; a name is resolved through
    Resolve-OERDirectoryRoleDefinitionId, where a name is matched without regard to letter case and
    a match that is ambiguous in either exact or case-insensitive form refuses (AmbiguousRoleName).
    No match is RoleDefinitionNotFound; a refused lookup is RoleDefinitionReadFailed. The returned
    RoleName is the name as typed, or empty when a GUID was given.

    .PARAMETER PolicyId
    The Microsoft Graph roleManagementPolicy id to update directly, for example
    'DirectoryRole_00000000-0000-0000-0000-000000000064_00000000-0000-0000-0000-000000000065'.
    Binds from the pipeline by property name, so Get-OERDirectoryRoleManagementPolicy output pipes
    straight in. A value that starts with '/' looks like an Azure Resource Manager policy id and is
    refused (InvalidPolicyId) before any Graph call -- ahead of the -ApproverUser and -ApproverGroup
    lookups too -- naming Set-OERRoleManagementPolicy as the cmdlet for that id; a value containing
    an embedded '/', '?', '#' or whitespace is refused the same way. A policy Microsoft Graph
    answers with a scope other than a tenant-wide directory scope -- a PIM for Groups policy, for
    example -- is refused as InvalidPolicyId after being read, naming Set-OERGroupPimPolicy, and
    nothing is sent.

    .PARAMETER ActivationMaxHours
    Maximum end-user activation window in hours (1-24); sets the Expiration_EndUser_Assignment rule.

    .PARAMETER RequireMfaOnActivation
    Require multi-factor authentication when an eligible user activates the role. $true disables a
    live authentication context (see the DESCRIPTION).

    .PARAMETER RequireJustificationOnActivation
    Require a justification when an eligible user activates the role.

    .PARAMETER RequireTicketOnActivation
    Require ticket information when an eligible user activates the role.

    .PARAMETER RequireApproval
    Require approval for activation (Approval_EndUser_Assignment rule). $true needs at least one
    approver, supplied or already on the live stage, or the call is refused with ApproverRequired.
    $false turns approval off and keeps the live stage and its approvers.

    .PARAMETER ApproverUser
    The user approvers, each a user principal name or user object id, resolved to object ids before
    anything is read or sent. Replaces the user approvers on the live stage; the group approvers are
    kept. An empty list clears the user side. Supplying it implies approval is required. The same
    user named twice (by user principal name and by id, or in another letter case) is sent once. A
    value that matches no user refuses the whole call with ApproverNotFound; a lookup that fails
    refuses it too, reported as that error itself.

    .PARAMETER ApproverGroup
    The group approvers, each a group display name or group object id, resolved to object ids before
    anything is read or sent. Replaces the group approvers on the live stage; the user approvers are
    kept. An empty list clears the group side. Supplying it implies approval is required. A value
    that matches no group refuses the whole call with ApproverNotFound, and a display name several
    groups share refuses it with AmbiguousApproverName, naming the candidate ids (pass the object id
    instead); a lookup that fails refuses it too, reported as that error itself.

    .PARAMETER AuthenticationContextId
    Authentication context claim value required on activation (e.g. c1). An empty string disables
    the authentication-context requirement. A non-empty value removes MFA from the activation
    enablement rule (see the DESCRIPTION). Only the value's shape is checked, not whether the tenant
    defines it.

    .PARAMETER AllowPermanentEligibility
    Allow permanent eligible assignments (sets isExpirationRequired false on the eligibility rule).

    .PARAMETER EligibleDuration
    Maximum lifetime of an eligible assignment, as either a whole number of days (for example 365,
    capped at 3650) or a raw ISO 8601 duration (for example 'P365D'). The ISO form is exactly what
    Get-OERDirectoryRoleManagementPolicy emits, so a read policy can be fed straight back. Also
    bindable as -EligibleDurationDays.

    .PARAMETER AllowPermanentActiveAssignment
    Allow permanent active assignments (sets isExpirationRequired false on the active rule).

    .PARAMETER ActiveDuration
    Maximum lifetime of an active assignment, as either a whole number of days (for example 180,
    capped at 3650) or a raw ISO 8601 duration (for example 'P180D'). Also bindable as
    -ActiveDurationDays.

    .PARAMETER RequireMfaOnActiveAssignment
    Require MFA on an admin active assignment (Enablement_Admin_Assignment rule).

    .PARAMETER RequireJustificationOnActiveAssignment
    Require a justification on an admin active assignment.

    .PARAMETER NotificationRule
    One or more notification-change objects from New-OERPolicyNotificationRule.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -RequireJustificationOnActivation $true
    Limits Reports Reader activation to 4 hours and requires a justification, patching only the two
    rules whose value changes.

    .EXAMPLE
    Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $true -ApproverGroup 'PIM Approvers'
    Requires approval on activation with the members of the PIM Approvers group as approvers,
    replacing the group approvers on the live stage while keeping its user approvers.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' | Set-OERDirectoryRoleManagementPolicy -RequireMfaOnActivation $true
    Reads the policy and pipes its PolicyId in, so the role is resolved once; requiring MFA also
    disables a live authentication context, with a warning.

    .EXAMPLE
    Set-OERDirectoryRoleManagementPolicy -Role '00000000-0000-0000-0000-000000000063' -AllowPermanentEligibility $false -EligibleDuration 180
    Ends permanent eligibility for the role identified by its role definition id and caps eligible
    assignments at 180 days.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByRole')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByRole', Mandatory)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ParameterSetName = 'ByPolicyId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$PolicyId,

        [ValidateRange(1, 24)]
        [int]$ActivationMaxHours,
        [bool]$RequireMfaOnActivation,
        [bool]$RequireJustificationOnActivation,
        [bool]$RequireTicketOnActivation,
        [bool]$RequireApproval,
        [string[]]$ApproverUser,
        [string[]]$ApproverGroup,
        [string]$AuthenticationContextId,
        [bool]$AllowPermanentEligibility,
        [Alias('EligibleDurationDays')]
        [string]$EligibleDuration,
        [bool]$AllowPermanentActiveAssignment,
        [Alias('ActiveDurationDays')]
        [string]$ActiveDuration,
        [bool]$RequireMfaOnActiveAssignment,
        [bool]$RequireJustificationOnActiveAssignment,
        [pscustomobject[]]$NotificationRule,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $RequestTarget = if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') { $PolicyId } else { $Role }

        # 1. The settings, built exactly as Set-OERRoleManagementPolicy builds them: the patch
        #    builder is shared, so it must receive the same keys and value shapes.
        $Setting = @{}
        if ($PSBoundParameters.ContainsKey('ActivationMaxHours')) { $Setting.ActivationMaxHours = $ActivationMaxHours }
        if ($PSBoundParameters.ContainsKey('RequireMfaOnActivation')) { $Setting.RequireMfaOnActivation = $RequireMfaOnActivation }
        if ($PSBoundParameters.ContainsKey('RequireJustificationOnActivation')) { $Setting.RequireJustificationOnActivation = $RequireJustificationOnActivation }
        if ($PSBoundParameters.ContainsKey('RequireTicketOnActivation')) { $Setting.RequireTicketOnActivation = $RequireTicketOnActivation }
        if ($PSBoundParameters.ContainsKey('RequireApproval')) { $Setting.RequireApproval = $RequireApproval }
        if ($PSBoundParameters.ContainsKey('AuthenticationContextId')) { $Setting.AuthenticationContextId = $AuthenticationContextId }
        if ($PSBoundParameters.ContainsKey('AllowPermanentEligibility')) { $Setting.AllowPermanentEligibility = $AllowPermanentEligibility }
        if ($PSBoundParameters.ContainsKey('EligibleDuration')) {
            try { $Setting.EligibleDuration = Resolve-OERDurationInput -Value $EligibleDuration -Unit Days }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("-EligibleDuration: $($PSItem.Exception.Message)")) -ErrorId 'InvalidDuration' -Category InvalidArgument -TargetObject $EligibleDuration -Cmdlet $PSCmdlet
                return
            }
        }
        if ($PSBoundParameters.ContainsKey('AllowPermanentActiveAssignment')) { $Setting.AllowPermanentActiveAssignment = $AllowPermanentActiveAssignment }
        if ($PSBoundParameters.ContainsKey('ActiveDuration')) {
            try { $Setting.ActiveDuration = Resolve-OERDurationInput -Value $ActiveDuration -Unit Days }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("-ActiveDuration: $($PSItem.Exception.Message)")) -ErrorId 'InvalidDuration' -Category InvalidArgument -TargetObject $ActiveDuration -Cmdlet $PSCmdlet
                return
            }
        }
        if ($PSBoundParameters.ContainsKey('RequireMfaOnActiveAssignment')) { $Setting.RequireMfaOnActiveAssignment = $RequireMfaOnActiveAssignment }
        if ($PSBoundParameters.ContainsKey('RequireJustificationOnActiveAssignment')) { $Setting.RequireJustificationOnActiveAssignment = $RequireJustificationOnActiveAssignment }
        if ($PSBoundParameters.ContainsKey('NotificationRule')) { $Setting.NotificationRule = $NotificationRule }

        # 2. The claim value's shape only -- no tenant lookup (parity with Set-OERRoleManagementPolicy).
        if ($PSBoundParameters.ContainsKey('AuthenticationContextId') -and $AuthenticationContextId -and $AuthenticationContextId -notmatch '^c\d+$') {
            Write-CmdletError -Message ([System.Exception]::new("AuthenticationContextId '$AuthenticationContextId' is invalid: use a value like 'c1', or an empty string to disable.")) -ErrorId 'InvalidAuthenticationContext' -Category InvalidArgument -TargetObject $AuthenticationContextId -Cmdlet $PSCmdlet
            return
        }

        # An explicit request for BOTH sides of the MFA / authentication-context exclusion is refused
        # here, before anything is read. The decision is Resolve-OERPimActivationConflict's; the
        # patch builder would refuse the same call as a backstop, but its message is written for
        # Azure PIM and is pinned there by the Azure tests.
        if ($PSBoundParameters.ContainsKey('AuthenticationContextId') -and -not [string]::IsNullOrEmpty($AuthenticationContextId) -and
            $PSBoundParameters.ContainsKey('RequireMfaOnActivation') -and $RequireMfaOnActivation) {
            $Conflict = Resolve-OERPimActivationConflict -CallerRequestsAuthContext -CallerRequestsMfa `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId $AuthenticationContextId `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication')
            if ($Conflict.Action -eq 'Conflict') {
                Write-CmdletError -Message ([System.Exception]::new($Conflict.Reason)) -ErrorId 'InvalidPolicyChange' -Category InvalidArgument -TargetObject $RequestTarget -Cmdlet $PSCmdlet
                return
            }
        }

        # 3. Nothing to do. Bound approvers are a setting even though they only join $Setting once
        #    the live stage is known (the approver section below); binding is all this needs, so it
        #    runs before any lookup.
        $ApproverUserBound = $PSBoundParameters.ContainsKey('ApproverUser')
        $ApproverGroupBound = $PSBoundParameters.ContainsKey('ApproverGroup')
        $ApproversBound = $ApproverUserBound -or $ApproverGroupBound
        if ($Setting.Count -eq 0 -and -not $ApproversBound) {
            Write-CmdletError -Message ([System.Exception]::new('No policy change was supplied. Specify at least one setting parameter.')) -ErrorId 'NothingToUpdate' -Category InvalidArgument -TargetObject $RequestTarget -Cmdlet $PSCmdlet
            return
        }

        # 4. An Azure Resource Manager policy id (piped from Get-OERRoleManagementPolicy, which emits
        #    the same type name) or anything else that cannot be a Graph policy id segment is refused
        #    before any Graph call, the approver lookups that follow included.
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId' -and $PolicyId -match '[/?#\s]') {
            if ($PolicyId.StartsWith('/', [System.StringComparison]::Ordinal)) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "The policy id '$PolicyId' looks like an Azure Resource Manager role " +
                        'management policy id, not a Microsoft Graph directory-role policy id. ' +
                        'Use Set-OERRoleManagementPolicy to update an Azure role policy by ARM id, ' +
                        'or pass the Microsoft Graph policy id (for example ' +
                        "'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.")) `
                    -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet
            } else {
                Write-CmdletError -Message ([System.Exception]::new(
                        "The policy id '$PolicyId' is not a valid Microsoft Graph directory-role " +
                        'policy id. Pass the Microsoft Graph policy id (for example ' +
                        "'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.")) `
                    -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet
            }
            return
        }

        # 5. Approvers are resolved to object ids before the policy is read, all or nothing, by
        #    Resolve-OERApproverInput (shared with Set-OERGroupPimPolicy: a blank value is skipped, the
        #    same principal named twice is kept once in first-seen order). The refusal is reported
        #    here, under this cmdlet's id. Three outcomes, three reports: an ambiguous name is
        #    AmbiguousApproverName (the resolver's text names the candidate ids), only an approver
        #    that matches nothing (ApproverUnresolved) is ApproverNotFound, and anything else -- a
        #    403, an exhausted 429, a 5xx -- is not evidence that the approver is missing, so it is
        #    published as itself.
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

        # 6. The policy and its live rules. A failed lookup is never reported as an absent object.
        $ResolvedPolicyId = $null
        $RoleDefinitionId = $null
        $RoleNameOut = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') {
            try {
                $Policy = Get-OERDirectoryRolePolicy -PolicyId $PolicyId
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (([string]$PSItem.FullyQualifiedErrorId).StartsWith('NotDirectoryRolePolicy', [System.StringComparison]::Ordinal)) {
                    Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                        -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet `
                        -InnerException $PSItem.Exception
                    return
                }
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'PolicyReadFailed' -Category ReadError -TargetObject $PolicyId -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }
            $ResolvedPolicyId = $PolicyId
            $Rules = @(@($Policy.rules) | Where-Object { $null -ne $_ })
        } else {
            try {
                $RoleDefinitionId = Resolve-OERDirectoryRoleDefinitionId -Role $Role
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (Test-OERAmbiguousNameError -Record $PSItem) {
                    Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                        -ErrorId 'AmbiguousRoleName' -Category InvalidArgument -TargetObject $Role -Cmdlet $PSCmdlet `
                        -InnerException $PSItem.Exception
                    return
                }
                Write-CmdletError -Message ([System.Exception]::new(
                        "Looking up the Microsoft Entra directory role '$Role' failed, so whether it " +
                        "exists could not be determined: $($PSItem.Exception.Message)")) `
                    -ErrorId 'RoleDefinitionReadFailed' -Category ReadError -TargetObject $Role -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }
            if (-not $RoleDefinitionId) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "No Microsoft Entra directory role definition named '$Role' was found. Use Tab " +
                        'completion on -Role, or pass the role definition id directly.')) `
                    -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
                return
            }
            Write-Verbose "[Set-OERDirectoryRoleManagementPolicy] Resolved role '$Role' to '$RoleDefinitionId'."
            $RoleNameOut = $(if (Test-OERGuid -Value $Role) { $null } else { $Role })

            try {
                # Direct assignment, never @() around the call: Get-OERDirectoryRolePolicyAssignment
                # emits its array with Write-Output -NoEnumerate (see Get-OERDirectoryRoleManagementPolicy).
                $Assignments = Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId $RoleDefinitionId
                $Assignment = $Assignments | Select-Object -First 1
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'PolicyReadFailed' -Category ReadError -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }
            if (-not $Assignment) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "No role management policy assignment was found for Microsoft Entra directory " +
                        "role '$RoleDefinitionId'.")) `
                    -ErrorId 'PolicyNotFound' -Category ObjectNotFound -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet
                return
            }
            $ResolvedPolicyId = [string]$Assignment.policyId
            $Rules = @(@($Assignment.policy.rules) | Where-Object { $null -ne $_ })
        }
        Write-Verbose "[Set-OERDirectoryRoleManagementPolicy] Policy id: '$ResolvedPolicyId'."

        # 7. Approvers. Resolve-OERGraphApproverSet (shared with Set-OERGroupPimPolicy) owns the Graph
        #    semantics: first live stage only, a bound side replaces that side, the unbound side and
        #    any approver of another kind (requestorManager, for example) are carried from the live
        #    stage, supplying approvers implies approval, and the approver count. -RequireApproval
        #    alone does not pass PrimaryApprovers to the builder (that key forces approval on), so the
        #    live approvers ride along untouched in the cloned rule.
        if ($ApproversBound -or $PSBoundParameters.ContainsKey('RequireApproval')) {
            $LiveApprovalRule = @($Rules) | Where-Object { [string]$_.id -eq 'Approval_EndUser_Assignment' } | Select-Object -First 1
            $ApproverSet = Resolve-OERGraphApproverSet -LiveApprovalRule $LiveApprovalRule `
                -UserBound $ApproverUserBound -GroupBound $ApproverGroupBound `
                -ResolvedUser $ApproverInput.User -ResolvedGroup $ApproverInput.Group `
                -RequireApprovalBound ($PSBoundParameters.ContainsKey('RequireApproval')) -RequireApproval $RequireApproval
            if ($ApproverSet.NoApprover) {
                $NoApproverMessage = if ($ApproverSet.NoApproverReason -eq 'Bound') {
                    "Approval cannot be required with no approver: after -ApproverUser/-ApproverGroup are applied, directory role management policy '$ResolvedPolicyId' would have none. Pass at least one approver."
                } else {
                    "Approval cannot be required with no approver: directory role management policy '$ResolvedPolicyId' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup."
                }
                Write-CmdletError -Message ([System.Exception]::new($NoApproverMessage)) `
                    -ErrorId 'ApproverRequired' -Category InvalidArgument -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
                return
            }
            if ($ApproversBound) {
                # The v1.0 approver shape (singleUser userId / groupMembers groupId) that
                # New-OERApproverObject builds, followed by the carried other-kind approvers as read.
                $Setting.PrimaryApprovers = @($ApproverSet.EffUser | ForEach-Object { New-OERApproverObject -Spec @{ User = $_ } }) +
                    @($ApproverSet.EffGroup | ForEach-Object { New-OERApproverObject -Spec @{ Group = $_ } }) +
                    @($ApproverSet.LiveOther)
            }
        }

        # 8. The read-modify-write plan. Graph approver keys (a v1.0 approver has no id or userType),
        #    and an untouched MFA plus authentication-context combination is left alone: each rule is
        #    PATCHed on its own here, unlike the Azure transport's full-set PATCH.
        try {
            $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph -ResolveUnrequestedConflict $false
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidPolicyChange' -Category InvalidArgument -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
            return
        }
        if ($Plan.ConflictResolution -and $Plan.ConflictResolution.Action -in @('ClearMfa', 'DisableAuthContext')) {
            Write-Warning "Policy '$ResolvedPolicyId': $($Plan.ConflictResolution.Reason)"
        }

        # 9. Nothing differs from the live policy.
        $ChangedIds = @($Plan.ChangedRuleId)
        if ($ChangedIds.Count -eq 0) {
            Write-CmdletError -Message ([System.Exception]::new('No applicable policy rule changed.')) -ErrorId 'NoChange' -Category InvalidArgument -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
            return
        }

        # 10. The changed rules only, in the order Get-OERPimRulePatchOrder owns (see its help: the
        #     MFA / authentication-context order is load-bearing).
        $ToSend = @(Get-OERPimRulePatchOrder -Rule @(@($Plan.Rules) | Where-Object { $ChangedIds -contains [string]$_.id }))
        $SendIds = @($ToSend | ForEach-Object { [string]$_.id })

        # 11. One confirmation for the call, then one PATCH per rule. A rejected rule does not stop
        #     the others.
        if ($PSCmdlet.ShouldProcess("directory role management policy '$ResolvedPolicyId'", "Update rules: $($SendIds -join ', ')")) {
            $LiveById = @{}
            foreach ($LiveRule in $Rules) { if ($LiveRule.id) { $LiveById[[string]$LiveRule.id] = $LiveRule } }

            # The authentication-context rule and the activation enablement rule together decide
            # whether activation requires MFA or an authentication context, so when both are sent
            # they are applied together or not at all. Should Microsoft Graph accept the first (in
            # patch order) and reject the second, the first is PATCHed straight back to its live
            # version: left half-applied, the pair can leave activation with NEITHER control -- a
            # context disabled for an MFA flag that never arrived, or MFA cleared for a context that
            # never arrived. Every changed rule is a clone of a live one (the patch builder refuses a
            # rule the policy lacks), so the live version is always there to send back. A rejected
            # FIRST half needs nothing: the second was then validated against an unchanged policy.
            $PairIds = @($SendIds | Where-Object { $_ -in @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment') })
            $PairFirst = $null
            $PairSecond = $null
            if ($PairIds.Count -eq 2) {
                $PairFirst = $PairIds[0]
                $PairSecond = $PairIds[1]
            }
            $Restored = $null
            $RestoreError = $null

            $Accepted = [System.Collections.Generic.List[string]]::new()
            $Failed = [System.Collections.Generic.List[string]]::new()
            foreach ($Rule in $ToSend) {
                $RuleId = [string]$Rule.id
                # Invoke-OERGraphRequest takes a [hashtable] body and the builder's changed rules are
                # PSCustomObject clones, so each is converted with a JSON round-trip (the same idiom
                # Enable-OERGroupPermanentEligibility uses for a single-rule PATCH).
                $Body = $Rule | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
                try {
                    Invoke-OERGraphRequest -Method PATCH -Uri ('v1.0/policies/roleManagementPolicies/{0}/rules/{1}' -f $ResolvedPolicyId, $RuleId) -Body $Body | Out-Null
                    $Accepted.Add($RuleId)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Failed.Add($RuleId)
                    Write-Warning "Rule '$RuleId' of directory role management policy '$ResolvedPolicyId' was not applied: $($PSItem.Exception.Message)"
                }

                if ($RuleId -eq $PairSecond -and $Failed.Contains($RuleId) -and $Accepted.Contains($PairFirst)) {
                    $LiveBody = $LiveById[$PairFirst] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
                    try {
                        Invoke-OERGraphRequest -Method PATCH -Uri ('v1.0/policies/roleManagementPolicies/{0}/rules/{1}' -f $ResolvedPolicyId, $PairFirst) -Body $LiveBody | Out-Null
                        [void]$Accepted.Remove($PairFirst)
                        $Restored = $PairFirst
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $RestoreError = $PSItem.Exception.Message
                        Write-Warning "Rule '$PairFirst' of directory role management policy '$ResolvedPolicyId' could not be put back to its value before this call: $RestoreError"
                    }
                }
            }

            # What was accepted, overlaid on the live rules: a rejected rule, and a rule put back
            # above, keeps its live version.
            $Effective = @(foreach ($PlannedRule in @($Plan.Rules)) {
                    $PlannedId = [string]$PlannedRule.id
                    if (($Failed.Contains($PlannedId) -or $PlannedId -eq $Restored) -and $LiveById.ContainsKey($PlannedId)) { $LiveById[$PlannedId] } else { $PlannedRule }
                })
            $ConvertParams = @{
                Rules         = $Effective
                PolicyId      = $ResolvedPolicyId
                Scope         = '/'
                ApproverShape = 'Graph'
                ChangedRuleId = $Accepted.ToArray()
            }
            if ($PSCmdlet.ParameterSetName -eq 'ByRole') {
                $ConvertParams.RoleName = $RoleNameOut
                $ConvertParams.RoleDefinitionId = $RoleDefinitionId
            }
            $PolicyOut = ConvertTo-OERRoleManagementPolicy @ConvertParams
            $PolicyOut

            # A rejected rule is a partially applied PIM policy change on a directory role. A warning
            # alone leaves $? true and does not trip -ErrorAction Stop, so write a non-terminating
            # error AFTER the object, so a caller that traps the error has still received it.
            if ($Failed.Count -gt 0) {
                $Message = "Directory role management policy '$ResolvedPolicyId' was not fully applied. Microsoft Graph " +
                    "rejected $($Failed.Count) of $($ToSend.Count) rule(s): $($Failed -join ', ')."
                if ($Restored) {
                    $Message += " Rule '$Restored', which Microsoft Graph had accepted, was put back to its value before " +
                        "this call, since it and '$PairSecond' together decide whether activation requires multi-factor " +
                        'authentication or an authentication context: activation keeps the protection it had before the call.'
                } elseif ($RestoreError) {
                    # What activation requires now, read from the object just returned.
                    $Protection = if ($PolicyOut.RequireMfaOnActivation) {
                        'multi-factor authentication, but no authentication context'
                    } elseif ($PolicyOut.AuthenticationContextId) {
                        "authentication context '$($PolicyOut.AuthenticationContextId)', but not multi-factor authentication"
                    } else {
                        'neither multi-factor authentication nor an authentication context'
                    }
                    $Message += " Rule '$PairFirst' had been accepted, and putting it back to its value before this call " +
                        "failed too ($RestoreError), so it stays changed: activation of this role now requires $Protection. " +
                        'Run the same command again, or run Set-OERDirectoryRoleManagementPolicy with ' +
                        '-RequireMfaOnActivation or -AuthenticationContextId set to the protection this role needs.'
                }
                $Message += " Run Get-OERDirectoryRoleManagementPolicy -PolicyId '$ResolvedPolicyId' to read the resulting state."
                Write-CmdletError -Message ([System.Exception]::new($Message)) `
                    -ErrorId 'PolicyRulesRejected' -Category WriteError -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
            }
        }
    }
}
