function Get-OERRoleManagementPolicyId {
    <#
    .SYNOPSIS
    Resolves the Azure role management policy governing a role at a scope.

    .DESCRIPTION
    Lists the roleManagementPolicyAssignments at the given ARM scope (api-version 2020-10-01, via the
    shared Get-OERRoleManagementPolicyForScope lister) and matches the FULL ARM role definition id
    client-side -- the ARM list-for-scope endpoint does not support a $filter, unlike the Graph
    equivalent. Returns a PSCustomObject with the governing PolicyId (full ARM id), the RoleName and
    Scope from the expanded policyAssignmentProperties, and the EffectiveRules array (so a caller needs
    no second GET to read the policy). Throws when no assignment matches the role -- the public cmdlets
    catch and route the message. Mirrors Get-OERPimGroupPolicyId. Used by Get-OERRoleManagementPolicy
    and Set-OERRoleManagementPolicy.

    .PARAMETER Scope
    The ARM scope at which to list policy assignments (e.g. '/subscriptions/{id}').

    .PARAMETER RoleDefinitionId
    The FULL ARM role definition id to match (from Resolve-OERRoleDefinitionId).

    .EXAMPLE
    Get-OERRoleManagementPolicyId -Scope '/subscriptions/00000000-0000-0000-0000-000000000001' -RoleDefinitionId '/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
    Returns the governing policy id and role name for the Reader role on the subscription.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$RoleDefinitionId
    )
    $Match = Get-OERRoleManagementPolicyForScope -Scope $Scope |
        Where-Object { $PSItem.RoleDefinitionId -eq $RoleDefinitionId } | Select-Object -First 1
    if (-not $Match) {
        throw "No role management policy assignment was found for role definition '$RoleDefinitionId' at scope '$Scope'."
    }
    $Match
}
