function Resolve-OERCatalogResource {
    <#
    .SYNOPSIS
    Finds a resource already onboarded into a catalog by its origin id.

    .DESCRIPTION
    Lists the resources of an entitlement management catalog through Invoke-OERGraphRequest, following
    @odata.nextLink across every page, and returns the first whose originId matches -OriginId, or $null
    when none matches. With -IncludeRoles the
    matching resource's roles are read from the catalog's dedicated resourceRoles endpoint
    (catalogs/{id}/resourceRoles?$filter=(originSystem eq '...' and resource/id eq '...')) and attached
    as the resource's roles property, so callers can map role bindings.

    The roles are read from the resourceRoles endpoint rather than from the resource's own
    $expand=roles navigation property because $expand=roles returns an EMPTY collection for some group
    types -- notably role-assignable (isAssignableToRole) and PIM-managed groups -- even though their
    Member/Owner (and PIM Eligible Member/Owner) roles exist. The resourceRoles endpoint is the
    authoritative v1.0 method and returns the roles for every supported resource type.

    This private helper backs the idempotency check in Add-OERCatalogResource and role resolution in
    Add-OERAccessPackageResourceRole.

    .PARAMETER CatalogId
    The catalog id whose resources are searched.

    .PARAMETER OriginId
    The directory object id (group/app) or site identifier to match against each resource's originId.

    .PARAMETER IncludeRoles
    Read the matching resource's roles from the catalog resourceRoles endpoint and attach them as the
    resource's roles property.

    .EXAMPLE
    Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'grp-guid' -IncludeRoles
    Returns the catalog resource (with roles) for that group, or $null.
    #>
    [OutputType([object])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogId,

        [Parameter(Mandatory)]
        [string]$OriginId,

        [switch]$IncludeRoles
    )
    $Uri = "v1.0/identityGovernance/entitlementManagement/catalogs/$CatalogId/resources"
    $Response = Invoke-OERGraphRequest -Uri $Uri -All

    $Match = $null
    foreach ($Item in @($Response.value)) {
        if ($Item.originId -eq $OriginId) { $Match = $Item; break }
    }
    if (-not $Match) { return $null }

    if ($IncludeRoles) {
        # Read roles from the dedicated resourceRoles endpoint via the shared helper; $expand=roles
        # on the resource returns empty for role-assignable / PIM-managed groups.
        $Match['roles'] = Get-OERCatalogResourceRole -CatalogId $CatalogId -OriginSystem $Match.originSystem -ResourceId $Match.id
    }
    return $Match
}
