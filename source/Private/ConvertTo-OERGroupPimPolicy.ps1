function ConvertTo-OERGroupPimPolicy {
    <#
    .SYNOPSIS
    Projects a PIM-for-groups roleManagementPolicy rule set into a tagged
    Omnicit.EntraRBAC.GroupPimPolicy object.

    .DESCRIPTION
    Maps the rules collection of a beta policies/roleManagementPolicies/{id}/rules read into the flat
    [PSCustomObject] shape tagged Omnicit.EntraRBAC.GroupPimPolicy so the Format view applies and
    Resolve-OERGroupPimPolicyChange can diff a live policy against a declared apply-document block.
    Activation, authentication context, eligible and active expiration, both enablement rule sets, the
    three admin notification recipient lists, and approval on activation are read from their canonical
    rule ids; the raw rules are carried through unchanged on the Rules property. RequireApproval is the
    Approval_EndUser_Assignment rule's isApprovalRequired, or $null when the policy has no approval
    rule at all -- distinct from a rule that exists with approval turned off. Approvers is the first
    approval stage's primaryApprovers, each read through the single owner ConvertFrom-OERGraphApprover
    (so a beta-read group approver, which carries id and no groupId, still matches a declared group id)
    -- an absent approval rule or stage gives a genuinely empty array, never a one-element array holding
    $null. This private converter is the single owner of the PIM-for-groups policy READ shape and is
    used by Get-OERGroupPimPolicy. The patch summary that Set-OERGroupPimPolicy returns is a different
    shape owned by ConvertTo-OERGroupPimPolicyResult.

    .PARAMETER Rules
    The rules collection read from the group's roleManagementPolicy, one object per policy rule.

    .PARAMETER GroupId
    The object id of the group the policy governs, stamped onto the output for correlation.

    .PARAMETER PolicyId
    The roleManagementPolicy id the rules were read from, stamped onto the output for later patches.

    .PARAMETER AccessType
    The PIM access type the policy governs, either member or owner, stamped onto the output.

    .EXAMPLE
    ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId $Gid -PolicyId $Pid -AccessType member
    Returns the tagged member-access policy projection for the group.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [object[]]$Rules,

        [string]$GroupId,

        [string]$PolicyId,

        [string]$AccessType
    )
    process {
        $EndUserExpiry = $Rules | Where-Object { $_.id -eq 'Expiration_EndUser_Assignment' } | Select-Object -First 1
        $ActEnable     = $Rules | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' } | Select-Object -First 1
        $CtxRule       = $Rules | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' } | Select-Object -First 1
        $EligExpiry    = $Rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' } | Select-Object -First 1
        $ActiveExpiry  = $Rules | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' } | Select-Object -First 1
        $ActiveEnable  = $Rules | Where-Object { $_.id -eq 'Enablement_Admin_Assignment' } | Select-Object -First 1
        $NotifElig     = $Rules | Where-Object { $_.id -eq 'Notification_Admin_Admin_Eligibility' } | Select-Object -First 1
        $NotifActive   = $Rules | Where-Object { $_.id -eq 'Notification_Admin_Admin_Assignment' } | Select-Object -First 1
        $NotifActon    = $Rules | Where-Object { $_.id -eq 'Notification_Admin_EndUser_Assignment' } | Select-Object -First 1
        $Approval      = $Rules | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' } | Select-Object -First 1

        # Parsed through the single read-side owner rather than an anchored single-unit regex: a policy
        # written by the portal or another tool can legitimately hold P1Y or PT1H30M, and reading those
        # back as $null made them look "not configured" and let a declared-permanence-only apply
        # overwrite them with a hard-coded default.
        $MaxHours = ConvertFrom-OERDuration -Duration ([string]$EndUserExpiry.maximumDuration) -Unit Hours
        $EligDays = ConvertFrom-OERDuration -Duration ([string]$EligExpiry.maximumDuration) -Unit Days
        $ActiveDays = ConvertFrom-OERDuration -Duration ([string]$ActiveExpiry.maximumDuration) -Unit Days

        $CtxId = if ($CtxRule -and [bool]$CtxRule.isEnabled) { $CtxRule.claimValue } else { $null }
        $AllowPermElig = if ($EligExpiry -and ($null -ne $EligExpiry.isExpirationRequired)) { (-not [bool]$EligExpiry.isExpirationRequired) } else { $null }
        $AllowPermActive = if ($ActiveExpiry -and ($null -ne $ActiveExpiry.isExpirationRequired)) { (-not [bool]$ActiveExpiry.isExpirationRequired) } else { $null }

        # Wrap each rule's array-valued property with a null-filter, not just @(): when a tenant's
        # policy does not carry one of the canonical rule ids, the corresponding $XxxRule variable is
        # $null, and @($NullVar.someProperty) alone still produces a ONE-element array containing
        # $null (a PowerShell array-wrap gotcha), not a genuinely empty array. That leaked a stray
        # null into enum-typed schema arrays (activationEnablement/activeEnablement) and notification
        # recipient lists downstream. Where-Object { $null -ne $PSItem } collapses both "rule missing"
        # and "rule present but property null/empty" to a real empty array.
        $Notifications = [PSCustomObject]@{
            EligibleAlert   = @($NotifElig.notificationRecipients | Where-Object { $null -ne $PSItem })
            ActiveAlert     = @($NotifActive.notificationRecipients | Where-Object { $null -ne $PSItem })
            ActivationAlert = @($NotifActon.notificationRecipients | Where-Object { $null -ne $PSItem })
        }

        # RequireApproval is $null when the policy carries no Approval_EndUser_Assignment rule at all --
        # distinct from a rule that exists with isApprovalRequired = $false. PIM uses one approval
        # stage; only its primaryApprovers are read here, through the single owner
        # ConvertFrom-OERGraphApprover so a beta-read group approver (id, no groupId) still projects to
        # the same Id a declared group would resolve to.
        $RequireApproval = if ($Approval) { [bool]$Approval.setting.isApprovalRequired } else { $null }
        $ApprovalStage = $null
        if ($Approval -and $Approval.setting) {
            $ApprovalStage = @($Approval.setting.approvalStages) | Where-Object { $null -ne $_ } | Select-Object -First 1
        }
        $Approvers = @($ApprovalStage.primaryApprovers | Where-Object { $null -ne $PSItem } | ForEach-Object { ConvertFrom-OERGraphApprover -Approver $PSItem })

        $Out = [PSCustomObject]@{
            GroupId                   = $GroupId
            PolicyId                  = $PolicyId
            AccessType                = $AccessType
            ActivationMaxHours        = $MaxHours
            AuthenticationContextId   = $CtxId
            ActivationEnabledRules    = @($ActEnable.enabledRules | Where-Object { $null -ne $PSItem })
            AllowPermanentEligibility = $AllowPermElig
            EligibleDuration          = $EligExpiry.maximumDuration
            EligibleDurationDays      = $EligDays
            AllowPermanentActive      = $AllowPermActive
            ActiveDuration            = $ActiveExpiry.maximumDuration
            ActiveDurationDays        = $ActiveDays
            ActiveEnabledRules        = @($ActiveEnable.enabledRules | Where-Object { $null -ne $PSItem })
            RequireApproval           = $RequireApproval
            Approvers                 = $Approvers
            Notifications             = $Notifications
            Rules                     = $Rules
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimPolicy')
        $Out
    }
}
