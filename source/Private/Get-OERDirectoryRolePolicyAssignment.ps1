function Get-OERDirectoryRolePolicyAssignment {
    <#
    .SYNOPSIS
    Lists the roleManagementPolicyAssignment(s) that govern PIM for Microsoft Entra directory roles.

    .DESCRIPTION
    Reads unifiedRoleManagementPolicyAssignment objects at tenant scope ('/', scopeType
    'DirectoryRole') from Microsoft Graph v1.0, with the governing policy and its rules expanded
    in the same call ($expand=policy($expand=rules)), so a caller never needs a second round trip
    to read the rules of the policy an assignment names. Without -RoleDefinitionId every directory
    role's assignment is returned; with it, only the one assignment for that role. The list is
    paged with -All. A GUID passed as -RoleDefinitionId is not free text, but it is still escaped
    through ConvertTo-OERODataFilterValue -- the single owner of OData filter-value escaping makes
    no exception for a value that happens to already be safe. A transport or permission failure is
    not caught here and propagates to the caller unchanged.

    .PARAMETER RoleDefinitionId
    The directory role definition id to filter the assignment list to. Omit to list every directory
    role's policy assignment in a single call.

    .EXAMPLE
    Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001'
    Returns the single policy assignment governing that directory role, with its policy and rules
    expanded.

    .EXAMPLE
    Get-OERDirectoryRolePolicyAssignment
    Returns every directory role's policy assignment at tenant scope.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [string]$RoleDefinitionId
    )
    $Filter = "scopeId eq '/' and scopeType eq 'DirectoryRole'"
    if ($RoleDefinitionId) {
        $Escaped = ConvertTo-OERODataFilterValue -Value $RoleDefinitionId
        $Filter += " and roleDefinitionId eq '$Escaped'"
    }
    $Uri = "v1.0/policies/roleManagementPolicyAssignments?`$filter=$Filter&`$expand=policy(`$expand=rules)"
    $Response = Invoke-OERGraphRequest -Uri $Uri -All
    $Assignments = @($Response.value)
    Write-Output -InputObject $Assignments -NoEnumerate
}
