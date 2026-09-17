function Set-OERRoleManagementPolicy {
    <#
    .SYNOPSIS
    Updates the Azure PIM role management policy for a role at a scope.

    .DESCRIPTION
    Tunes HOW PIM behaves for an Azure resource role: activation window, MFA / justification / ticket
    on activation, approval and approvers, authentication context, eligible and active permanence
    plus max durations, MFA / justification on admin active assignment, and notifications. Each
    supplied setting is overlaid on the policy's current rule (read-modify-write per rule); the
    COMPLETE rules set is then PATCHed (ARM validates the submitted rules as a set and rejects a
    partial array on a default policy, so the full set is sent with untouched rules preserved). Every
    toggle is a [bool] so the policy can be both tightened and relaxed; an omitted parameter leaves
    its rule untouched. Identify the policy by -Role plus a scope, or directly by -PolicyId (which
    also binds from the pipeline from Get-OERRoleManagementPolicy). All ARM calls go through
    Invoke-OERArmRequest (api-version 2020-10-01). Supports -WhatIf and -Confirm (ConfirmImpact
    Medium: a policy change is security-affecting but not destructive). Setting permanent eligibility
    (or raising the eligible max duration) is what lets New-OEREligibleRoleAssignment -Permanent
    succeed. The returned object also carries a ChangedRuleIds property listing the rule ids patched.

    Two ARM cross-rule constraints apply. (1) MFA on activation and an authentication context are
    mutually exclusive: enabling -AuthenticationContextId automatically clears the MFA requirement
    from activation, and -RequireMfaOnActivation $true disables the authentication context; asking
    for both in one call is an error. (2) When approval is configured with CUSTOM approvers, ARM
    rejects setting custom recipients on the approver activation notification
    (New-OERPolicyNotificationRule -Event Activation -Recipient Approver -AdditionalRecipient ...)
    with ActivationCustomApproversNotEmpty -- the approvers are notified directly, so leave that
    notification's recipients empty (or use -Recipient Admin / Requestor).

    .PARAMETER Role
    The role: display name, role definition GUID, or full ARM id. Tab-completion offers the five
    curated common Azure RBAC roles; any other built-in or custom role name is still accepted.

    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.

    .PARAMETER Subscription
    A subscription GUID or display name.

    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.

    .PARAMETER ManagementGroup
    A management group name or display name. Bound from the pipeline by property name
    (ManagementGroupName), so Get-OERManagementGroup output pipes directly in.

    .PARAMETER PolicyId
    The full ARM id of the policy to update directly (binds from the pipeline by property name).

    .PARAMETER ActivationMaxHours
    Maximum end-user activation window in hours (1-24); sets the Expiration_EndUser_Assignment rule.

    .PARAMETER RequireMfaOnActivation
    Require multi-factor authentication when an eligible user activates the role.

    .PARAMETER RequireJustificationOnActivation
    Require a justification when an eligible user activates the role.

    .PARAMETER RequireTicketOnActivation
    Require ticket information when an eligible user activates the role.

    .PARAMETER RequireApproval
    Require approval for activation (Approval_EndUser_Assignment rule).

    .PARAMETER ApproverUser
    Primary approver users (user principal name or object id); each resolved to a User approver.
    Resolution is all-or-nothing -- if any approver value cannot be resolved, no approvers are set.
    Supplying approvers implies RequireApproval = true, overriding any -RequireApproval $false.

    .PARAMETER ApproverGroup
    Primary approver groups (display name or object id); each resolved to a Group approver.

    .PARAMETER AuthenticationContextId
    Authentication context claim value required on activation (e.g. c1). An empty string disables the
    authentication-context requirement.

    .PARAMETER AllowPermanentEligibility
    Allow permanent eligible assignments (sets isExpirationRequired false on the eligibility rule).

    .PARAMETER EligibleDuration
    Maximum lifetime of an eligible assignment, as either a whole number of days (for example 365,
    the historical form, capped at 3650) or a raw ISO 8601 duration (for example 'P365D'). The ISO
    form is exactly what Get-OERRoleManagementPolicy emits, so a read policy can be fed straight
    back. Also bindable as -EligibleDurationDays.

    .PARAMETER AllowPermanentActiveAssignment
    Allow permanent active assignments (sets isExpirationRequired false on the active rule).

    .PARAMETER ActiveDuration
    Maximum lifetime of an active (assigned) role assignment, as either a whole number of days (for
    example 180, capped at 3650) or a raw ISO 8601 duration (for example 'P180D'). Also bindable as
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
    Set-OERRoleManagementPolicy -Role 'Contributor' -Subscription 'Prod' -AllowPermanentEligibility $true
    Allows permanent eligible assignments for Contributor on Prod (so -Permanent grants succeed).

    .EXAMPLE
    Set-OERRoleManagementPolicy -Role 'Owner' -Subscription 'Prod' -ActivationMaxHours 4 -RequireMfaOnActivation $true -RequireApproval $true -ApproverGroup 'sec-approvers'
    Tightens Owner activation: 4-hour window, MFA, and approval by the named group.

    .EXAMPLE
    $Policy = Get-OERRoleManagementPolicy -Role 'Owner' -Subscription 'Prod'
    Set-OERRoleManagementPolicy -PolicyId $Policy.PolicyId -EligibleDuration $Policy.EligibleDuration
    Feeds the ISO duration read from a policy straight back into the setter without re-parsing it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByRole')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByRole', Mandatory)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ParameterSetName = 'ByRole')]
        [string]$Scope,
        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,
        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,
        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName')]
        [string]$ManagementGroup,

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
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
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

        if ($PSBoundParameters.ContainsKey('AuthenticationContextId') -and $AuthenticationContextId -and $AuthenticationContextId -notmatch '^c\d+$') {
            Write-CmdletError -Message ([System.Exception]::new("AuthenticationContextId '$AuthenticationContextId' is invalid: use a value like 'c1', or an empty string to disable.")) -ErrorId 'InvalidAuthenticationContext' -Category InvalidArgument -TargetObject $AuthenticationContextId -Cmdlet $PSCmdlet
            return
        }

        if ($PSBoundParameters.ContainsKey('ApproverUser') -or $PSBoundParameters.ContainsKey('ApproverGroup')) {
            $Approvers = [System.Collections.Generic.List[object]]::new()
            try {
                foreach ($Value in @($ApproverUser)) {
                    if (-not $Value) { continue }
                    $Resolved = Resolve-OERPrincipal -User $Value
                    $Approvers.Add(@{ id = $Resolved.PrincipalId; userType = 'User'; isBackup = $false })
                }
                foreach ($Value in @($ApproverGroup)) {
                    if (-not $Value) { continue }
                    $Resolved = Resolve-OERPrincipal -Group $Value
                    $Approvers.Add(@{ id = $Resolved.PrincipalId; userType = 'Group'; isBackup = $false })
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'ApproverNotFound' -Category ObjectNotFound -TargetObject $Value -Cmdlet $PSCmdlet
                return
            }
            $Setting.PrimaryApprovers = $Approvers.ToArray()
        }

        if ($Setting.Count -eq 0) {
            $NothingToUpdateTarget = if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') { $PolicyId } else { $Role }
            Write-CmdletError -Message ([System.Exception]::new('No policy change was supplied. Specify at least one setting parameter.')) -ErrorId 'NothingToUpdate' -Category InvalidArgument -TargetObject $NothingToUpdateTarget -Cmdlet $PSCmdlet
            return
        }

        $RoleName = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') {
            $ResolvedPolicyId = $PolicyId
        } else {
            try {
                $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup) | Where-Object { $_ } | Select-Object -First 1
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
                return
            }
            Write-Verbose "[Set-OERRoleManagementPolicy] Target scope: '$TargetScope'."
            try {
                $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
                return
            }
            Write-Verbose "[Set-OERRoleManagementPolicy] Resolved role '$Role' to '$RoleDefinitionId'."
            try {
                $PolicyInfo = Get-OERRoleManagementPolicyId -Scope $TargetScope -RoleDefinitionId $RoleDefinitionId
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'PolicyNotFound' -Category ObjectNotFound -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet
                return
            }
            $ResolvedPolicyId = $PolicyInfo.PolicyId
            $RoleName = $PolicyInfo.RoleName
            Write-Verbose "[Set-OERRoleManagementPolicy] Resolved policy id: '$ResolvedPolicyId'."
        }

        try {
            $Policy = Invoke-OERArmRequest -Path "$ResolvedPolicyId`?api-version=2020-10-01"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        try {
            $Plan = Resolve-OERPolicyRulePatch -CurrentRule @($Policy.properties.rules) -Setting $Setting
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidPolicyChange' -Category InvalidArgument -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
            return
        }
        $ChangedIds = @($Plan.ChangedRuleId)
        if ($ChangedIds.Count -eq 0) {
            Write-CmdletError -Message ([System.Exception]::new('No applicable policy rule changed.')) -ErrorId 'NoChange' -Category InvalidArgument -TargetObject $ResolvedPolicyId -Cmdlet $PSCmdlet
            return
        }

        # ARM validates the submitted rules as a set and rejects a partial array on a default policy
        # (InvalidPolicy), so PATCH the COMPLETE rules set (changed rules overlaid, others passed
        # through). $Plan.Rules is a flat [object[]] -- assigning it as a property keeps the JSON
        # rules array flat (a bare-array return would re-nest to [[...]] and ARM would reject it).
        $Target = "role management policy '$ResolvedPolicyId'"
        if ($PSCmdlet.ShouldProcess($Target, "Update rules: $($ChangedIds -join ', ')")) {
            $Body = @{ properties = @{ rules = $Plan.Rules } }
            try {
                $Response = Invoke-OERArmRequest -Method PATCH -Path "$ResolvedPolicyId`?api-version=2020-10-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERRoleManagementPolicy -Rules @($Response.properties.rules) -PolicyId $ResolvedPolicyId -Scope ([string]$Response.properties.scope) -RoleName $RoleName -ChangedRuleId $ChangedIds
        }
    }
}
