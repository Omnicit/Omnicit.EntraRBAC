function New-OERPimRuleSet {
    <#
    .SYNOPSIS
    Builds the PIM-for-groups roleManagementPolicy rule objects, emitting only the rules whose
    governing values are supplied.

    .DESCRIPTION
    Produces an array of unifiedRoleManagementPolicy rule hashtables for a PIM-for-groups policy
    (member or owner): the end-user activation window and enablement, the authentication-context
    requirement, the eligible and active assignment expirations, the admin-assignment enablement, and
    the three admin notification rules. Each input parameter is optional; a rule object is emitted only
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
        [switch]$AllowPermanentEligibility,
        [switch]$AllowPermanentActive
    )
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
