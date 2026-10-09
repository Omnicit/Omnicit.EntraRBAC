function Get-OERManagementGroupParent {
    <#
    .SYNOPSIS
    Reads the parent of every management group the caller can reach, in one Entities - List call.

    .DESCRIPTION
    The single owner of the Entities - List call: POST /providers/Microsoft.Management/getEntities
    (api-version 2020-05-01, with $view=GroupsOnly) through Invoke-OERArmRequest, with -All so every
    page is followed. The Management Groups - List answer carries no parent, so
    Get-OERManagementGroup reads the parents of the groups it lists here: one call per list, not one
    GET per group.

    Returns ONE hashtable, keyed on the management group name (case-insensitive), whose value is the
    group's parent as a PSCustomObject with id (the parent's ARM id, from parent.id), name (the last
    segment of that id) and displayName (the last element of parentDisplayNameChain).

    An entity is taken only when all of these hold: its type is Microsoft.Management/managementGroups;
    its parent.id is a non-empty string whose last segment is not empty or white space; its
    parentNameChain has at least one element, the last of which equals that last segment, compared
    case-insensitively; and its parentDisplayNameChain has at least one element, the last of which is
    not empty or white space. Any other entity is left out, so a group the answer misses or
    mis-states has no entry: its caller leaves that group's three parent properties empty and reports
    them as unread, so they are not left silently empty.

    The parentNameChain check keeps an answer whose chains end in another group than the one parent.id
    names from putting that other group's display name beside the right ParentId and ParentName: the
    Entities - List sample on Microsoft Learn is such an answer. Measured live, the last element of
    parentNameChain equalled the last segment of parent.id for the one group measured, which sits
    directly under the tenant root group (1 of 1). The check compares the name chain only, so a
    parentDisplayNameChain that disagrees with its own parentNameChain is not detected.

    The tenant root group has no parent and so no entry; the caller recognises the root itself.

    Entities - List needs no Azure role of its own: it answers only with the groups the caller can
    reach (measured: an identity with no Azure role gets an empty answer, not a refusal).

    Nothing is caught here: a failed call throws to the caller, whose catch scrubs the record with
    Remove-OERErrorRecord and reports it. Authentication is the caller's: this helper never calls
    Initialize-OERAuth.

    .EXAMPLE
    $ParentByName = Get-OERManagementGroupParent
    $ParentByName['mg-platform'].displayName
    Returns the display name of the parent of mg-platform, when the answer carried it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $ParentByName = @{}
    $Response = Invoke-OERArmRequest -Method POST -Path '/providers/Microsoft.Management/getEntities?api-version=2020-05-01&$view=GroupsOnly' -All
    foreach ($Entity in @($Response.value)) {
        if ($null -eq $Entity) { continue }
        if ([string]$Entity.type -ne 'Microsoft.Management/managementGroups') { continue }

        $ParentId = $Entity.properties.parent.id
        if ($ParentId -isnot [string] -or [string]::IsNullOrWhiteSpace($ParentId)) { continue }

        # parent.id must end in a name, and parentNameChain (root group first, immediate parent last)
        # must end in that same name, ignoring case. Otherwise the last display name of the chain may
        # belong to another group than parent.id names, so the entity is left out and its group is
        # reported unread instead of shown with that other group's display name.
        $ParentName = $ParentId.Split('/')[-1]
        if ([string]::IsNullOrWhiteSpace($ParentName)) { continue }
        $NameChain = @($Entity.properties.parentNameChain)
        if ($NameChain.Count -lt 1 -or [string]$NameChain[-1] -ne $ParentName) { continue }

        $DisplayChain = @($Entity.properties.parentDisplayNameChain)
        if ($DisplayChain.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$DisplayChain[-1])) { continue }

        $ParentByName[[string]$Entity.name] = [PSCustomObject]@{
            id          = $ParentId
            name        = $ParentName
            displayName = [string]$DisplayChain[-1]
        }
    }
    $ParentByName
}
