function Get-OERCatalogResourceRole {
    <#
    .SYNOPSIS
    Reads the roles of a catalog resource from the dedicated resourceRoles endpoint.

    .DESCRIPTION
    Returns the role objects for a resource onboarded into an entitlement management catalog by
    querying the catalog's resourceRoles endpoint
    (catalogs/{id}/resourceRoles?$filter=(originSystem eq '...' and resource/id eq '...')&$expand=resource)
    through Invoke-OERGraphRequest. This is the authoritative v1.0 method: the resource's own
    $expand=roles navigation property returns an EMPTY collection for role-assignable
    (isAssignableToRole) and PIM-managed groups, so it cannot be trusted. The filter is built as a
    literal OData string with single quotes -- NOT [uri]::EscapeDataString, which would encode
    the resource/id slash and parentheses and break the query. This private helper is the single
    owner of the resource-role read and is shared by Resolve-OERCatalogResource and
    Get-OERCatalogResource.

    .PARAMETER CatalogId
    The catalog id whose resourceRoles endpoint is queried.

    .PARAMETER OriginSystem
    The resource's originSystem (e.g. AadGroup), used in the filter.

    .PARAMETER ResourceId
    The resource's directory object id (the resource/id matched in the filter).

    .EXAMPLE
    Get-OERCatalogResourceRole -CatalogId 'cat-1' -OriginSystem 'AadGroup' -ResourceId 'res-1'
    Returns the role objects (active and PIM-eligible variants) for that resource.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogId,

        [Parameter(Mandatory)]
        [string]$OriginSystem,

        [Parameter(Mandatory)]
        [string]$ResourceId
    )
    $Filter = "(originSystem eq '$OriginSystem' and resource/id eq '$ResourceId')"
    $Uri = "v1.0/identityGovernance/entitlementManagement/catalogs/$CatalogId/resourceRoles?`$filter=$Filter&`$expand=resource"
    $Response = Invoke-OERGraphRequest -Uri $Uri -All
    $Roles = @($Response.value)
    Write-Output -InputObject $Roles -NoEnumerate
}
