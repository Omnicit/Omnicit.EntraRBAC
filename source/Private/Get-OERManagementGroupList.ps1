function Get-OERManagementGroupList {
    <#
    .SYNOPSIS
    Lists the Azure management groups visible to the caller, as the raw ARM items.

    .DESCRIPTION
    Sends the Management Groups - List call: GET /providers/Microsoft.Management/managementGroups
    (api-version 2020-05-01) through Invoke-OERArmRequest, with -All so every page is followed. Each
    non-null item of the answer's value collection is emitted as it is -- unconverted and untagged,
    with its id, name, type and properties (displayName, tenantId). The list carries no parent of
    any group.

    It has two callers, which therefore walk the same list. Get-OERManagementGroup converts the
    items and adds the parent of each listed group, which it reads separately through
    Get-OERManagementGroupParent. Resolve-OERInventoryScopeTree converts the items itself and reads
    no parent, so the inventory walk gains no failure mode from the parent read. (Resolve-OERScope's
    display-name lookup still sends the same list call on its own.)

    Nothing is caught here: a refused or failed listing throws to the caller, whose catch scrubs the
    record with Remove-OERErrorRecord and reports it. A caller that can read no management group is
    refused (AuthorizationFailed), not given an empty list. Authentication is the caller's: this
    helper never calls Initialize-OERAuth.

    .EXAMPLE
    $Items = @(Get-OERManagementGroupList)
    Returns every management group the caller can read, as raw ARM items.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $Response = Invoke-OERArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -All
    foreach ($Item in @($Response.value)) {
        if ($null -ne $Item) { $Item }
    }
}
