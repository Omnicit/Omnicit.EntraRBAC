function Resolve-OERApplicationId {
    <#
    .SYNOPSIS
    Resolves an Entra ID enterprise application to its service principal object id, accepting either an
    explicit id or a display name.

    .DESCRIPTION
    Returns the service principal object id for an enterprise application. When -Id is supplied it is
    returned unchanged without any Graph call. When -DisplayName is supplied a filtered
    v1.0/servicePrincipals query is issued through Invoke-OERGraphRequest and the first matching service
    principal's id is returned, or $null when none matches. The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the
    value so reserved characters survive transport.

    Entitlement management catalog application resources are identified by the service principal object id
    (originSystem AadApplication) -- not the app registration's appId or application object id -- so this
    helper intentionally queries servicePrincipals. This private helper is the single application-lookup
    entry point used by the catalog-resource cmdlets.

    .PARAMETER Id
    The service principal object id (GUID) to return verbatim. Takes precedence over -DisplayName when both
    are supplied and no Graph call is made.

    .PARAMETER DisplayName
    The enterprise application (service principal) display name to resolve to an id via a filtered
    servicePrincipals query when -Id is not supplied. Escaped through ConvertTo-OERODataFilterValue
    (quote-doubling plus percent-encoding) before the OData filter is built.

    .EXAMPLE
    Resolve-OERApplicationId -DisplayName 'Contoso Expense Portal'
    Returns the service principal object id of the enterprise application with that display name, or $null
    when it does not exist.
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
    if ($Response.value -and @($Response.value).Count -gt 0) {
        return [string]@($Response.value)[0].id
    }
    return $null
}
