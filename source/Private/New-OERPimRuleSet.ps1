function New-OERPimRuleSet {
    <#
    .SYNOPSIS
    Builds the PIM-for-groups roleManagementPolicy rule objects, emitting only the rules whose
    governing values are supplied.

    .DESCRIPTION
    Produces an array of unifiedRoleManagementPolicy rule hashtables for a PIM-for-groups policy
    (member or owner): the end-user activation window and enablement, the authentication-context
    requirement, the eligible and active assignment expirations, the admin-assignment enablement, the
    end-user approval requirement and its approvers (Approval_EndUser_Assignment), and the three admin
    notification rules. Each input parameter is optional; a rule object is emitted only
    when its governing value parameter is bound, so the caller (Set-OERGroupPimPolicy) can patch a
    surgical subset without rebuilding the whole policy. Each rule carries the correct target
    (caller/operations/level with empty inheritable/enforced settings) and @odata.type confirmed against
    the PIM rule-update schema. This private helper is the single owner of the rule shape.

    .PARAMETER ActivationMaxHours
    The maximum end-user activation window in hours, emitted as the PT{n}H maximum duration on the
    Expiration_EndUser_Assignment rule. When omitted, that rule is not emitted.

    .PARAMETER EligibleDuration
    ISO 8601 maximum duration for admin eligible assignments (for example P365D). When omitted, the
    Expiration_Admin_Eligibility rule is not emitted.

    .PARAMETER ActiveDuration
    ISO 8601 maximum duration for admin active assignments (for example P180D). When omitted, the
    Expiration_Admin_Assignment rule is not emitted.

    .PARAMETER AuthenticationContextId
    The authentication-context claim value required on activation (for example c1). A non-empty value
    enables the AuthenticationContext_EndUser_Assignment rule with that claim; an empty string disables
    it. When the parameter is not bound at all, the rule is not emitted.

    .PARAMETER ActivationEnabledRules
    The enabledRules required on activation (Justification, MultiFactorAuthentication, Ticketing),
    emitted on the Enablement_EndUser_Assignment rule. When omitted, that rule is not emitted.

    .PARAMETER ActiveEnabledRules
    The enabledRules required on an active admin assignment (Justification, MultiFactorAuthentication,
    Ticketing), emitted on the Enablement_Admin_Assignment rule. When omitted, that rule is not emitted.

    .PARAMETER EligibleAlertRecipient
    Extra recipient addresses added to the eligible-assignment admin alert
    (Notification_Admin_Admin_Eligibility), keeping the default recipients. When omitted, that rule is
    not emitted.

    .PARAMETER ActiveAlertRecipient
    Extra recipient addresses added to the active-assignment admin alert
    (Notification_Admin_Admin_Assignment), keeping the default recipients. When omitted, that rule is
    not emitted.

    .PARAMETER ActivationAlertRecipient
    Extra recipient addresses added to the role-activation admin alert
    (Notification_Admin_EndUser_Assignment), keeping the default recipients. When omitted, that rule is
    not emitted.

    .PARAMETER RequireApproval
    Whether end-user activation requires approval, emitted as isApprovalRequired on the
    Approval_EndUser_Assignment rule. The rule is emitted when this parameter or PrimaryApprover is
    bound; when neither is bound, it is not emitted. When PrimaryApprover is bound, isApprovalRequired
    is sent as true whatever this parameter says, since supplying approvers implies approval.

    .PARAMETER PrimaryApprover
    The complete list of primary approvers for the single approval stage, as Graph approver objects
    (for example from New-OERApproverObject). Each is normalized to the shape of the Graph BETA
    endpoint PIM for Groups is PATCHed on: a user becomes a singleUser and a group a groupMembers,
    each carrying only id and isBackup (false), whether it came in as v1.0's userId/groupId or as
    beta's id. The beta types declare no userId or groupId, and their description is read-only, so
    neither is ever sent. Any other approver kind is passed through unchanged. When bound, it
    replaces the live stage's primary approvers while the live stage's other fields carry over. When
    omitted, the live stage's primary approvers carry over, normalized the same way, and so do its
    escalation approvers either way.

    .PARAMETER LiveApprovalRule
    The Approval_EndUser_Assignment rule as currently read from the policy (hashtable or
    PSCustomObject), or null when there is none. Every setting and stage field that this helper does
    not set carries over from it: isApprovalRequiredForExtension (default false),
    isRequestorJustificationRequired (default true), approvalMode (default SingleStage, also used when
    the live mode is NoApproval), and from the FIRST live stage only the timeout in days (default 1),
    isApproverJustificationRequired (default true), the escalation time and switch (defaults 0 and
    false) and the escalation approvers. With no PrimaryApprover and no live stage, no stage is sent.

    .PARAMETER AllowPermanentEligibility
    When set, permanent eligible assignments are allowed (the Expiration_Admin_Eligibility rule sets
    isExpirationRequired to false). Only meaningful together with EligibleDuration.

    .PARAMETER AllowPermanentActive
    When set, permanent active assignments are allowed (the Expiration_Admin_Assignment rule sets
    isExpirationRequired to false). Only meaningful together with ActiveDuration.

    .EXAMPLE
    New-OERPimRuleSet -ActivationMaxHours 8 -ActivationEnabledRules @('Justification')
    Returns the activation expiration rule and the activation enablement rule only.

    .EXAMPLE
    New-OERPimRuleSet -EligibleAlertRecipient @('admin@contoso.com')
    Returns only the eligible-assignment notification rule with the admin recipient added.

    .EXAMPLE
    New-OERPimRuleSet -RequireApproval $true -LiveApprovalRule $LiveRule
    Returns only the approval rule with approval required, keeping the live stage's timeout,
    justification settings and approvers.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory rule-set builder; returns an array and performs no state change, so ShouldProcess does not apply.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'Returns an array of rule hashtables; [OutputType([object[]])] is correct but the analyzer infers System.Array and does not reconcile the two.')]
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [int]$ActivationMaxHours,
        [string]$EligibleDuration,
        [string]$ActiveDuration,
        [string]$AuthenticationContextId,
        [string[]]$ActivationEnabledRules,
        [string[]]$ActiveEnabledRules,
        [string[]]$EligibleAlertRecipient,
        [string[]]$ActiveAlertRecipient,
        [string[]]$ActivationAlertRecipient,
        [bool]$RequireApproval,
        [object[]]$PrimaryApprover,
        [object]$LiveApprovalRule,
        [switch]$AllowPermanentEligibility,
        [switch]$AllowPermanentActive
    )

    # PIM for Groups is PATCHed on the Graph BETA endpoint, and this is the BETA type model, not
    # v1.0's: beta singleUser and groupMembers declare only id, description and isBackup, so a user
    # or group approver is sent as { @odata.type, id, isBackup = $false }. v1.0's userId and groupId
    # are never sent, and neither is description, which is read-only. (The only documented
    # userId/groupId PATCH is v1.0, for Entra roles; New-OERApproverObject keeps that shape for the
    # v1.0 access-package path.) ConvertFrom-OERGraphApprover owns READING either shape, so an
    # approver built by New-OERApproverObject and one carried from a beta read both land here in the
    # same form. An approver kind that is neither a user nor a group is returned as it came, never
    # dropped.
    function ConvertTo-PatchApprover {
        param([object]$Approver)
        if ($null -eq $Approver) { return }
        $Read = ConvertFrom-OERGraphApprover -Approver $Approver
        if ($Read.UserType -eq 'User') { return @{ '@odata.type' = '#microsoft.graph.singleUser'; id = $Read.Id; isBackup = $false } }
        if ($Read.UserType -eq 'Group') { return @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = $Read.Id; isBackup = $false } }
        $Approver
    }

    $TgtEndUser   = @{ caller = 'EndUser'; operations = @('All'); level = 'Assignment';  inheritableSettings = @(); enforcedSettings = @() }
    $TgtAdminAsg  = @{ caller = 'Admin';   operations = @('All'); level = 'Assignment';  inheritableSettings = @(); enforcedSettings = @() }
    $TgtAdminElig = @{ caller = 'Admin';   operations = @('All'); level = 'Eligibility'; inheritableSettings = @(); enforcedSettings = @() }

    $Rules = [System.Collections.Generic.List[hashtable]]::new()

    if ($PSBoundParameters.ContainsKey('ActivationMaxHours')) {
        $Rules.Add(@{
            '@odata.type'   = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
            id              = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true
            maximumDuration = (ConvertTo-OERDuration -Hours $ActivationMaxHours); target = $TgtEndUser
        })
    }
    if ($PSBoundParameters.ContainsKey('ActivationEnabledRules')) {
        $Rules.Add(@{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id            = 'Enablement_EndUser_Assignment'; enabledRules = @($ActivationEnabledRules); target = $TgtEndUser
        })
    }
    if ($PSBoundParameters.ContainsKey('AuthenticationContextId')) {
        $Rules.Add(@{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
            id            = 'AuthenticationContext_EndUser_Assignment'
            isEnabled     = [bool]$AuthenticationContextId
            claimValue    = if ($AuthenticationContextId) { $AuthenticationContextId } else { $null }
            target        = $TgtEndUser
        })
    }
    if ($PSBoundParameters.ContainsKey('EligibleDuration')) {
        $Rules.Add(@{
            '@odata.type'   = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
            id              = 'Expiration_Admin_Eligibility'; isExpirationRequired = (-not $AllowPermanentEligibility)
            maximumDuration = $EligibleDuration; target = $TgtAdminElig
        })
    }
    if ($PSBoundParameters.ContainsKey('ActiveDuration')) {
        $Rules.Add(@{
            '@odata.type'   = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
            id              = 'Expiration_Admin_Assignment'; isExpirationRequired = (-not $AllowPermanentActive)
            maximumDuration = $ActiveDuration; target = $TgtAdminAsg
        })
    }
    if ($PSBoundParameters.ContainsKey('ActiveEnabledRules')) {
        $Rules.Add(@{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id            = 'Enablement_Admin_Assignment'; enabledRules = @($ActiveEnabledRules); target = $TgtAdminAsg
        })
    }

    # Approval is one rule, patched whole: every field this call does not set carries over from the
    # live rule, so a caller changing only the requirement never resets the stage timeout or the
    # approvers. PIM uses a single stage, so only the FIRST live stage is read (the ARM path does the
    # same). Neither setting nor stage carries an @odata.type -- the approvers carry their own.
    $PrimaryBound = $PSBoundParameters.ContainsKey('PrimaryApprover')
    if ($PrimaryBound -or $PSBoundParameters.ContainsKey('RequireApproval')) {
        $LiveSetting = if ($null -ne $LiveApprovalRule) { $LiveApprovalRule.setting } else { $null }
        $LiveStage = $null
        if ($null -ne $LiveSetting) {
            $LiveStage = @($LiveSetting.approvalStages) | Where-Object { $null -ne $_ } | Select-Object -First 1
        }
        $Mode = if ($null -ne $LiveSetting) { [string]$LiveSetting.approvalMode } else { '' }
        if ([string]::IsNullOrEmpty($Mode) -or $Mode -eq 'NoApproval') { $Mode = 'SingleStage' }

        $Stages = @()
        if ($PrimaryBound -or $null -ne $LiveStage) {
            $Primary = if ($PrimaryBound) { @($PrimaryApprover) } else { @($LiveStage.primaryApprovers) }
            $Stages = @(@{
                approvalStageTimeOutInDays      = if ($null -ne $LiveStage.approvalStageTimeOutInDays) { $LiveStage.approvalStageTimeOutInDays } else { 1 }
                isApproverJustificationRequired = if ($null -ne $LiveStage.isApproverJustificationRequired) { [bool]$LiveStage.isApproverJustificationRequired } else { $true }
                escalationTimeInMinutes         = if ($null -ne $LiveStage.escalationTimeInMinutes) { $LiveStage.escalationTimeInMinutes } else { 0 }
                isEscalationEnabled             = if ($null -ne $LiveStage.isEscalationEnabled) { [bool]$LiveStage.isEscalationEnabled } else { $false }
                primaryApprovers                = @($Primary | ForEach-Object { ConvertTo-PatchApprover -Approver $_ })
                escalationApprovers             = @(@($LiveStage.escalationApprovers) | ForEach-Object { ConvertTo-PatchApprover -Approver $_ })
            })
        }

        $Rules.Add(@{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
            id            = 'Approval_EndUser_Assignment'
            target        = $TgtEndUser
            setting       = @{
                isApprovalRequired               = if ($PrimaryBound) { $true } else { [bool]$RequireApproval }
                isApprovalRequiredForExtension   = if ($null -ne $LiveSetting.isApprovalRequiredForExtension) { [bool]$LiveSetting.isApprovalRequiredForExtension } else { $false }
                isRequestorJustificationRequired = if ($null -ne $LiveSetting.isRequestorJustificationRequired) { [bool]$LiveSetting.isRequestorJustificationRequired } else { $true }
                approvalMode                     = $Mode
                approvalStages                   = $Stages
            }
        })
    }

    $NotifMap = @(
        @{ Bound = 'EligibleAlertRecipient';   Id = 'Notification_Admin_Admin_Eligibility'; Target = $TgtAdminElig; Value = $EligibleAlertRecipient }
        @{ Bound = 'ActiveAlertRecipient';     Id = 'Notification_Admin_Admin_Assignment';  Target = $TgtAdminAsg;  Value = $ActiveAlertRecipient }
        @{ Bound = 'ActivationAlertRecipient'; Id = 'Notification_Admin_EndUser_Assignment'; Target = $TgtEndUser;  Value = $ActivationAlertRecipient }
    )
    foreach ($N in $NotifMap) {
        if ($PSBoundParameters.ContainsKey($N.Bound)) {
            $Rules.Add(@{
                '@odata.type'              = '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'
                id                         = $N.Id
                notificationType           = 'Email'
                recipientType              = 'Admin'
                notificationLevel          = 'All'
                isDefaultRecipientsEnabled = $true
                notificationRecipients     = @($N.Value)
                target                     = $N.Target
            })
        }
    }

    if ($Rules.Count -gt 0) { , $Rules.ToArray() }
}
