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

    A listed management group carries no details.parent; its caller reads the parent separately and
    passes it in with -Parent. This converter stays the single owner of the output shape either way.

    .PARAMETER InputObject
    The raw management group object (hashtable or PSCustomObject) as returned by the ARM API.

    .PARAMETER Parent
    The parent read separately for a listed group -- an object with id, name and displayName -- used
    instead of properties.details.parent, which a list item does not carry. $null means no parent:
    when -Parent is given, it is the parent, $null included, and properties.details.parent is not
    read. Without -Parent, properties.details.parent is read as before.

    .EXAMPLE
    ConvertTo-OERManagementGroup -InputObject $Response
    Returns the tagged management group object.

    .EXAMPLE
    ConvertTo-OERManagementGroup -InputObject $Item -Parent $ParentByName[$Item.name]
    Returns the tagged object for a listed group, with the parent read through Entities - List.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,

        [AllowNull()]
        [object]$Parent
    )
    process {
        $Properties = $InputObject.properties
        $ParentObject = $null
        if ($PSBoundParameters.ContainsKey('Parent')) {
            $ParentObject = $Parent
        } elseif ($Properties.details -and $Properties.details.parent) {
            $ParentObject = $Properties.details.parent
        }

        $Out = [PSCustomObject]@{
            ResourceId          = [string]$InputObject.id
            ManagementGroupName = [string]$InputObject.name
            DisplayName         = [string]$Properties.displayName
            TenantId            = [string]$Properties.tenantId
            ParentId            = if ($ParentObject) { [string]$ParentObject.id } else { $null }
            ParentName          = if ($ParentObject) { [string]$ParentObject.name } else { $null }
            ParentDisplayName   = if ($ParentObject) { [string]$ParentObject.displayName } else { $null }
            Children            = $Properties.children
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ManagementGroup')
        $Out
    }
}
