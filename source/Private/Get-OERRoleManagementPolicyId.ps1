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
    catch and route the message. A failed list propagates as the transport's own error and is never
    turned into the no-match throw. With -ThrowUnresolved the no-match case, a list that SUCCEEDED
    and held no assignment for the role, is thrown as an ErrorRecord with the internal id
    RolePolicyUnresolved (same message, category ObjectNotFound, target the role definition id) so a
    caller can tell it from a failed read through Test-OERRoleLookupUnresolved; the id is never
    published. Without the switch the throw is a plain string, as before. Mirrors Get-OERPimGroupPolicyId. Used by Get-OERRoleManagementPolicy
    and Set-OERRoleManagementPolicy.

    .PARAMETER Scope
    The ARM scope at which to list policy assignments (e.g. '/subscriptions/{id}').

    .PARAMETER RoleDefinitionId
    The FULL ARM role definition id to match (from Resolve-OERRoleDefinitionId).

    .PARAMETER ThrowUnresolved
    Throws the no-match case as an ErrorRecord with the internal id RolePolicyUnresolved instead of a
    plain string. Used by the two role management policy cmdlets.

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
        [string]$RoleDefinitionId,

        [switch]$ThrowUnresolved
    )
    $Match = Get-OERRoleManagementPolicyForScope -Scope $Scope |
        Where-Object { $PSItem.RoleDefinitionId -eq $RoleDefinitionId } | Select-Object -First 1
    if (-not $Match) {
        $NotFoundMessage = "No role management policy assignment was found for role definition '$RoleDefinitionId' at scope '$Scope'."
        if ($ThrowUnresolved) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($NotFoundMessage),
                'RolePolicyUnresolved',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $RoleDefinitionId)
        }
        throw $NotFoundMessage
    }
    $Match
}
