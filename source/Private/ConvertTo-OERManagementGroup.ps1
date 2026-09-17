function ConvertTo-OERManagementGroup {
    <#
    .SYNOPSIS
    Converts a raw ARM management group response into a tagged Omnicit.EntraRBAC.ManagementGroup object.

    .DESCRIPTION
    Maps the Microsoft.Management/managementGroups wire shape (id/name/properties.displayName/
    properties.tenantId, and properties.details.parent plus properties.children when present on Get
    responses) into a flat PSCustomObject. The ARM resource path is exposed as ResourceId (never a
    bare Id) so it cannot mis-bind downstream -PolicyId or -RoleEligibilityScheduleId parameters
    that carry an Id alias. ManagementGroupName is the only STORED name; Name is registered as an
    AliasProperty of it in suffix.ps1 (Task 8a), so downstream cmdlets binding -ManagementGroup via
    either the Name or the ManagementGroupName alias receive the same value when the object is piped
    (pipeline-alias convention from Phase 3b), and the two spellings can no longer drift apart.

    .PARAMETER InputObject
    The raw management group object (hashtable or PSCustomObject) as returned by the ARM API.

    .EXAMPLE
    ConvertTo-OERManagementGroup -InputObject $Response
    Returns the tagged management group object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $Properties = $InputObject.properties
        $Parent = $null
        if ($Properties.details -and $Properties.details.parent) { $Parent = $Properties.details.parent }

        $Out = [PSCustomObject]@{
            ResourceId          = [string]$InputObject.id
            ManagementGroupName = [string]$InputObject.name
            DisplayName         = [string]$Properties.displayName
            TenantId            = [string]$Properties.tenantId
            ParentId            = if ($Parent) { [string]$Parent.id } else { $null }
            ParentName          = if ($Parent) { [string]$Parent.name } else { $null }
            ParentDisplayName   = if ($Parent) { [string]$Parent.displayName } else { $null }
            Children            = $Properties.children
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ManagementGroup')
        $Out
    }
}
