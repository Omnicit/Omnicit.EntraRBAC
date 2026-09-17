function Resolve-OERAccessReviewDefinitionId {
    <#
    .SYNOPSIS
    Resolves an access review definition to its id, accepting either an id or a display name.

    .DESCRIPTION
    Returns the access review definition id. When -Id is supplied it is returned unchanged without any
    Graph call. When -DisplayName is supplied and the value is a GUID it is returned verbatim (treated
    as an id) with no Graph call. Otherwise a filtered query against the access reviews definitions
    collection is issued through Invoke-OERGraphRequest and the first matching definition's id is
    returned, or $null when none matches. The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the value
    so reserved characters survive transport. This private helper is the single
    access-review-definition-lookup entry point used by the access review cmdlets.

    .PARAMETER Id
    The access review definition id (GUID) to return verbatim. Takes precedence over -DisplayName; no
    Graph call is made.

    .PARAMETER DisplayName
    The access review definition display name to resolve to an id via a filtered query when -Id is not
    supplied. If the value is a GUID it is returned verbatim (treated as an id) with no Graph call.

    .EXAMPLE
    Resolve-OERAccessReviewDefinitionId -DisplayName 'Q3 Review'
    Returns the id of the access review definition with that display name, or $null when it does not
    exist.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERAccessReviewDefinitionId requires either -Id or -DisplayName.'
    }
    if (Test-OERGuid -Value $DisplayName) {
        return $DisplayName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    if ($Response.value -and @($Response.value).Count -gt 0) {
        return [string]@($Response.value)[0].id
    }
    return $null
}
