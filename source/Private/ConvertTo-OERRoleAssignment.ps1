function ConvertTo-OERRoleAssignment {
    <#
    .SYNOPSIS
    Converts a raw ARM role assignment response into a tagged Omnicit.EntraRBAC.RoleAssignment object.

    .DESCRIPTION
    Maps the Microsoft.Authorization/roleAssignments wire shape into a flat PSCustomObject.
    RoleAssignmentId is the FULL ARM resource id (scope + /providers/Microsoft.Authorization/roleAssignments/
    + GUID), stored once. The generic Id is an AliasProperty of RoleAssignmentId, registered in
    suffix.ps1, rather than a second stored copy that could drift out of sync -- piping into
    Set-OERRoleAssignment or Remove-OERRoleAssignment still binds the -Id parameter via its
    RoleAssignmentId alias (pipeline-alias convention from Phase 3b), and every existing .Id read keeps
    resolving to the same value.

    DelegatedManagedIdentityResourceId is the Azure Lighthouse / cross-tenant delegation link. It is
    projected (null when absent) because Set-OERRoleAssignment carries it forward verbatim on an edit,
    and an operator has to be able to confirm it survived.

    .PARAMETER InputObject
    The raw role assignment object (hashtable or PSCustomObject) as returned by the ARM API.

    .EXAMPLE
    ConvertTo-OERRoleAssignment -InputObject $Response
    Returns the tagged role assignment object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $Properties = $InputObject.properties
        $Out = [PSCustomObject]@{
            RoleAssignmentId = [string]$InputObject.id
            Name             = [string]$InputObject.name
            Scope            = [string]$Properties.scope
            RoleDefinitionId = [string]$Properties.roleDefinitionId
            PrincipalId      = [string]$Properties.principalId
            PrincipalType    = [string]$Properties.principalType
            Description      = if ($null -ne $Properties.description) { [string]$Properties.description } else { $null }
            Condition        = if ($null -ne $Properties.condition) { [string]$Properties.condition } else { $null }
            ConditionVersion = if ($null -ne $Properties.conditionVersion) { [string]$Properties.conditionVersion } else { $null }
            CreatedOn        = $Properties.createdOn
            UpdatedOn        = $Properties.updatedOn
            DelegatedManagedIdentityResourceId = if ($null -ne $Properties.delegatedManagedIdentityResourceId) { [string]$Properties.delegatedManagedIdentityResourceId } else { $null }
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleAssignment')
        $Out
    }
}
