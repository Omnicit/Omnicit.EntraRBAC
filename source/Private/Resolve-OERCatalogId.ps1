function Resolve-OERCatalogId {
    <#
    .SYNOPSIS
    Resolves an entitlement management catalog to its id, accepting either an id or a display name.

    .DESCRIPTION
    Returns the catalog id. When -Id is supplied it is returned unchanged without any Graph call.
    When -DisplayName is supplied and the value is a GUID it is returned verbatim (treated as an id)
    with no Graph call. Otherwise a filtered query against the entitlement management catalogs
    collection is issued through Invoke-OERGraphRequest. Exactly one match returns that catalog's id
    and no match returns $null; more than one match throws an ErrorRecord with ErrorId
    'AmbiguousName' listing the candidate ids, because catalog display names are not unique and
    picking the first match would silently act on an arbitrary catalog.
    The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the value
    so reserved characters survive transport. This private helper is the single catalog-lookup entry
    point used by the catalog and access-package cmdlets.

    .PARAMETER Id
    The catalog id (GUID) to return verbatim. Takes precedence over -DisplayName; no Graph call is made.

    .PARAMETER DisplayName
    The catalog display name to resolve to an id via a filtered query when -Id is not supplied.
    If the value is a GUID it is returned verbatim (treated as an id) with no Graph call.

    .EXAMPLE
    Resolve-OERCatalogId -DisplayName 'CAT-IT-Core'
    Returns the id of the catalog with that display name, or $null when it does not exist.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERCatalogId requires either -Id or -DisplayName.'
    }
    if (Test-OERGuid -Value $DisplayName) {
        return $DisplayName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/identityGovernance/entitlementManagement/catalogs?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Catalog display name '$DisplayName' matches $($Candidates.Count) catalogs ($Ids). " +
                'Entitlement management does not enforce unique catalog display names, so this name ' +
                'cannot identify a single catalog. Re-run with the catalog id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
