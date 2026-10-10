function Get-OERRoleManagementPolicyForScope {
    <#
    .SYNOPSIS
    Lists every Azure role management policy assignment at a scope as friendly per-role policy info.

    .DESCRIPTION
    Performs a SINGLE paged roleManagementPolicyAssignments list-for-scope call (ARM api-version
    2020-10-01) through Invoke-OERArmRequest and yields one PSCustomObject per assignment carrying the
    governing PolicyId (full ARM id), RoleDefinitionId, RoleName (from the expanded
    policyAssignmentProperties), Scope, and the EffectiveRules array -- the same shape
    Get-OERRoleManagementPolicyId returns for a single role. The list already contains every role's
    policy at the scope, so a caller that needs all roles (Get-OERRoleManagementPolicy
    -AllRolesAtScope) reads them with one list call instead of one lookup per role.
    Get-OERRoleManagementPolicyId reuses this lister and matches a single roleDefinitionId client-side
    (the ARM list-for-scope endpoint has no $filter). Returns nothing when the scope has no policy
    assignments (an empty scope is not an error).

    Each result also carries PolicyMetadata: the row's policyAssignmentProperties.policy object as ARM
    returned it (the policy id, and lastModifiedDateTime and lastModifiedBy when ARM reports them), or
    $null when the row carries none. Export-OERInventory's role policy selection reads whether a policy
    has been changed from it through Test-OERRolePolicyModified, with no request of its own; the other
    callers ignore it.

    .PARAMETER Scope
    The ARM scope at which to list policy assignments (e.g. '/subscriptions/{id}').

    .EXAMPLE
    Get-OERRoleManagementPolicyForScope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001'
    Returns the governing policy info for every role at the subscription scope.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope
    )
    $Response = Invoke-OERArmRequest -Path "$Scope/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01" -All
    foreach ($Assignment in @($Response.value)) {
        [PSCustomObject]@{
            PolicyId         = [string]$Assignment.properties.policyId
            RoleDefinitionId = [string]$Assignment.properties.roleDefinitionId
            RoleName         = [string]$Assignment.properties.policyAssignmentProperties.roleDefinition.displayName
            Scope            = [string]$Assignment.properties.scope
            EffectiveRules   = @($Assignment.properties.effectiveRules)
            PolicyMetadata   = $Assignment.properties.policyAssignmentProperties.policy
        }
    }
}
