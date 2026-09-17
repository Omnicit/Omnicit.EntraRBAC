function ConvertTo-OERRoleDefinition {
    <#
    .SYNOPSIS
    Converts a raw ARM role definition response into a tagged Omnicit.EntraRBAC.RoleDefinition object.

    .DESCRIPTION
    Maps the Microsoft.Authorization/roleDefinitions wire shape into a flat PSCustomObject.
    RoleDefinitionId is the only STORED copy of the ARM resource path; ResourceId is registered as an
    AliasProperty of it in suffix.ps1 (Task 8a) rather than a second stored copy, and the type
    deliberately does NOT also alias a bare Id -- that would mis-bind downstream -PolicyId or
    -RoleEligibilityScheduleId parameters that carry an Id alias. Both
    Get-OERRoleManagementPolicy/Set-OERRoleManagementPolicy (-PolicyId) and
    Enable-OEREligibleRoleAssignment (-RoleEligibilityScheduleId, consumed UNGUARDED) would otherwise
    treat a piped role definition's ARM path as if it were a policy id or an eligibility schedule id.
    Name is the role definition GUID. Piping a role definition into New-OERRoleAssignment (and
    friends) binds the -Role parameter via its RoleDefinitionId alias (pipeline-alias convention from
    Phase 3b) -- that alias is RoleDefinitionId, never Id, so this is not the same collision.

    .PARAMETER InputObject
    The raw role definition object (hashtable or PSCustomObject) as returned by the ARM API.

    .EXAMPLE
    ConvertTo-OERRoleDefinition -InputObject $Response
    Returns the tagged role definition object.
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
            RoleDefinitionId = [string]$InputObject.id
            Name             = [string]$InputObject.name
            RoleName         = [string]$Properties.roleName
            RoleType         = [string]$Properties.type
            Description      = [string]$Properties.description
            AssignableScopes = $Properties.assignableScopes
            Permissions      = $Properties.permissions
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleDefinition')
        $Out
    }
}
