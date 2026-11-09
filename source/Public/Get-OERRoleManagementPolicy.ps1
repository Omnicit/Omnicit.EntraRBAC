function Get-OERRoleManagementPolicy {
    <#
    .SYNOPSIS
    Reads the Azure PIM role management policy for a role at a scope.

    .DESCRIPTION
    Resolves the role management policy that governs HOW PIM behaves for an Azure resource role
    (activation length, MFA / justification / ticket on activation, approval, authentication context,
    eligible and active permanence plus max durations, and notifications) and returns a tagged
    Omnicit.EntraRBAC.RoleManagementPolicy object with friendly summary properties plus the raw
    EffectiveRules. Identify the policy either by -Role plus a scope (resolved via the
    roleManagementPolicyAssignments list-for-scope) or directly by -PolicyId (a full ARM policy id,
    which also binds from the pipeline so Get-OERRoleManagementPolicy output round-trips). All ARM
    calls go through Invoke-OERArmRequest (api-version 2020-10-01); authentication is ensured via
    Initialize-OERAuth -IncludeARM. Pass -CommonRoles to read the curated common-role set at a scope,
    or -AllRolesAtScope to read every role at a scope in a single policy-assignments list call.

    .PARAMETER Role
    The role: display name (e.g. 'Reader'), role definition GUID, or full ARM id. Tab-completion
    offers the five curated common Azure RBAC roles; any other built-in or custom role name is still
    accepted.

    .PARAMETER CommonRoles
    Read the role management policy for each role in the curated common-role set (Reader, Contributor,
    Owner, User Access Administrator, Role Based Access Control Administrator) at the given scope. A
    role or policy that does not exist at the scope is skipped with a warning. A role whose lookup
    FAILED (a permission refusal, a paging refusal, an ambiguous name) is written as a non-terminating
    error of its own, and the next role is still read. Mutually exclusive with -Role and
    -AllRolesAtScope.

    .PARAMETER AllRolesAtScope
    Read the role management policy for EVERY role at the given scope from a single paged
    roleManagementPolicyAssignments list-for-scope call (one ARM list that already carries every
    role's policy and effective rules, not one lookup per role). Mutually exclusive with -Role and
    -CommonRoles.

    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.

    .PARAMETER Subscription
    A subscription GUID or display name.
    A display name that several subscriptions share is refused, naming the candidates;
    use the subscription id.

    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.

    .PARAMETER ManagementGroup
    A management group name or display name. Bound from the pipeline by property name
    (ManagementGroupName), so Get-OERManagementGroup output pipes directly in.
    A display name that several management groups share is refused, naming the candidates;
    use the management group name.

    .PARAMETER PolicyId
    The full ARM id of the role management policy to read directly: a path that starts with
    '/', which is what this cmdlet's own output carries. Any other value -- a Microsoft Graph
    directory role policy id, for example -- is refused with a non-terminating InvalidPolicyId
    error before any Azure Resource Manager or Microsoft Graph request; use
    Get-OERDirectoryRoleManagementPolicy for a directory role policy.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERRoleManagementPolicy -Role 'Contributor' -Subscription 'Prod'
    Reads the PIM policy governing the Contributor role on the Prod subscription.

    .EXAMPLE
    Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' | Set-OERRoleManagementPolicy -AllowPermanentEligibility $true
    Reads a policy and pipes its PolicyId into Set-OERRoleManagementPolicy.

    .EXAMPLE
    Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod'
    Reads the PIM policy for each curated common role on the Prod subscription, skipping any with no
    policy and writing an error for any whose lookup failed.

    .EXAMPLE
    Get-OERRoleManagementPolicy -AllRolesAtScope -Subscription 'Prod'
    Reads the PIM policy for every role on the Prod subscription in a single policy-assignments list call.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByRole')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByRole', Mandatory)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ParameterSetName = 'ByCommonRoles', Mandatory)]
        [switch]$CommonRoles,

        [Parameter(ParameterSetName = 'ByAllRolesAtScope', Mandatory)]
        [switch]$AllRolesAtScope,

        [Parameter(ParameterSetName = 'ByRole')]
        [Parameter(ParameterSetName = 'ByCommonRoles')]
        [Parameter(ParameterSetName = 'ByAllRolesAtScope')]
        [string]$Scope,

        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByCommonRoles', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByAllRolesAtScope', ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByCommonRoles', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByAllRolesAtScope', ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,

        [Parameter(ParameterSetName = 'ByRole', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByCommonRoles', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByAllRolesAtScope', ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName')]
        [string]$ManagementGroup,

        [Parameter(ParameterSetName = 'ByPolicyId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$PolicyId,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') {
            # Only an Azure Resource Manager path can go to Azure Resource Manager: a Microsoft Graph directory role
            # policy id (piped from Get-OERDirectoryRoleManagementPolicy, which has the same output type) or a PIM for Groups
            # policy id is refused here, before any request. The test is the leading '/' alone: an Azure resource name can
            # legally hold a space, so no other character is refused.
            if (-not $PolicyId.StartsWith('/', [System.StringComparison]::Ordinal)) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "The policy id '$PolicyId' is not an Azure Resource Manager role management policy id (a path " +
                        "that starts with '/'). Use Get-OERDirectoryRoleManagementPolicy to read a Microsoft Entra " +
                        'directory role policy by its Microsoft Graph id.')) `
                    -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet
                return
            }
            try {
                $Policy = Invoke-OERArmRequest -Path "$PolicyId`?api-version=2020-10-01"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERRoleManagementPolicy -Rules @($Policy.properties.rules) -PolicyId $PolicyId -Scope ([string]$Policy.properties.scope)
            return
        }

        # Scope resolution is shared by ByRole, ByCommonRoles, and ByAllRolesAtScope.
        try {
            $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup) | Where-Object { $_ } | Select-Object -First 1
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
            return
        }

        if ($AllRolesAtScope) {
            # The roleManagementPolicyAssignments list at the scope already names every role with its
            # policy and effective rules, so a single paged list (not one lookup per role) yields them
            # all -- far faster and without the per-role request storm that triggers ARM throttling.
            try {
                $PolicyInfos = @(Get-OERRoleManagementPolicyForScope -Scope $TargetScope)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleEnumerationFailed' -Category ObjectNotFound -TargetObject $TargetScope -Cmdlet $PSCmdlet
                return
            }
            foreach ($PolicyInfo in $PolicyInfos) {
                ConvertTo-OERRoleManagementPolicy -Rules @($PolicyInfo.EffectiveRules) -PolicyId $PolicyInfo.PolicyId -Scope $TargetScope -RoleName $PolicyInfo.RoleName -RoleDefinitionId $PolicyInfo.RoleDefinitionId
            }
            return
        }

        if ($CommonRoles) {
            # Read the curated set: resolve each display name to a role definition id, then read its
            # policy. A role or policy that does not exist at the scope is skipped with a warning,
            # not an abort; a lookup that FAILED (403, paging refusal, ambiguous name) is written as
            # a non-terminating error of its own and the next role is read.
            foreach ($Name in (Get-OERCommonRoleName)) {
                try {
                    $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Name -Scope $TargetScope -ThrowUnresolved
                    $PolicyInfo = Get-OERRoleManagementPolicyId -Scope $TargetScope -RoleDefinitionId $RoleDefinitionId -ThrowUnresolved
                    ConvertTo-OERRoleManagementPolicy -Rules @($PolicyInfo.EffectiveRules) -PolicyId $PolicyInfo.PolicyId -Scope $TargetScope -RoleName $PolicyInfo.RoleName -RoleDefinitionId $RoleDefinitionId
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    if (Test-OERRoleLookupUnresolved -Record $PSItem) {
                        Write-Warning "Skipping role '$Name': $($PSItem.Exception.Message)"
                    } else {
                        $PSCmdlet.WriteError($PSItem)
                    }
                    continue
                }
            }
            return
        }

        # ByRole: a single explicit role -- granular non-terminating errors (preserved behavior).
        # Only a lookup that succeeded and matched nothing is RoleDefinitionNotFound / PolicyNotFound;
        # a failed read (403, paging refusal, ambiguous name) is published as itself.
        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope -ThrowUnresolved
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERRoleLookupUnresolved -Record $PSItem) {
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            } else {
                $PSCmdlet.WriteError($PSItem)
            }
            return
        }
        try {
            $PolicyInfo = Get-OERRoleManagementPolicyId -Scope $TargetScope -RoleDefinitionId $RoleDefinitionId -ThrowUnresolved
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERRoleLookupUnresolved -Record $PSItem) {
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'PolicyNotFound' -Category ObjectNotFound -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet
            } else {
                $PSCmdlet.WriteError($PSItem)
            }
            return
        }

        ConvertTo-OERRoleManagementPolicy -Rules @($PolicyInfo.EffectiveRules) -PolicyId $PolicyInfo.PolicyId -Scope $TargetScope -RoleName $PolicyInfo.RoleName -RoleDefinitionId $RoleDefinitionId
    }
}
