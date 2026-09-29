function Resolve-OERApplicationId {
    <#
    .SYNOPSIS
    Resolves an Entra ID enterprise application to its service principal object id, accepting either an
    explicit id or a display name.

    .DESCRIPTION
    Returns the service principal object id for an enterprise application. When -Id is supplied it is
    returned unchanged without any Graph call. When -DisplayName is supplied a filtered
    v1.0/servicePrincipals query is issued through Invoke-OERGraphRequest, even when the value is a
    GUID: unlike Resolve-OERGroupId this helper has no GUID short-circuit on -DisplayName, so a caller
    holding an object id passes it as -Id. Exactly one match returns that service principal's id and no
    match returns $null; more than one match throws an ErrorRecord with ErrorId 'AmbiguousName' listing
    the candidate ids, because Entra does not enforce unique service principal display names and
    picking one of them would silently act on an arbitrary service principal. Null entries in the
    response are ignored. The display name is escaped through ConvertTo-OERODataFilterValue, which
    doubles embedded single quotes and percent-encodes the value so reserved characters survive
    transport.

    Entitlement management catalog application resources are identified by the service principal object id
    (originSystem AadApplication) -- not the app registration's appId or application object id -- so this
    helper intentionally queries servicePrincipals. This private helper is the single service principal
    lookup used by the catalog-resource cmdlets and by the principal resolvers (Resolve-OERPrincipal and
    Resolve-OERStructurePrincipal).

    .PARAMETER Id
    The service principal object id (GUID) to return verbatim. Takes precedence over -DisplayName when both
    are supplied and no Graph call is made.

    .PARAMETER DisplayName
    The enterprise application (service principal) display name to resolve to an id via a filtered
    servicePrincipals query when -Id is not supplied. Escaped through ConvertTo-OERODataFilterValue
    (quote-doubling plus percent-encoding) before the OData filter is built.

    .EXAMPLE
    Resolve-OERApplicationId -DisplayName 'Contoso Expense Portal'
    Returns the service principal object id of the enterprise application with that display name, $null
    when it does not exist, or throws AmbiguousName when more than one service principal carries it.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERApplicationId requires either -Id or -DisplayName.'
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/servicePrincipals?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Service principal display name '$DisplayName' matches $($Candidates.Count) service principals ($Ids). " +
                'Entra does not enforce unique service principal display names, so this name cannot identify a ' +
                'single service principal. Re-run with the object id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
