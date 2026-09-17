function Resolve-OERUserId {
    <#
    .SYNOPSIS
    Resolves an Entra ID user to its object id, accepting either an explicit id or a user principal name.

    .DESCRIPTION
    Returns the object id for a user. When -Id is supplied it is returned unchanged without any
    Graph call. When -UserPrincipalName is supplied and the value is a GUID it is returned verbatim
    (treated as an id) with no Graph call. Otherwise a filtered v1.0/users query is issued through
    Invoke-OERGraphRequest and the first matching user's id is returned, or $null when no user
    matches. Single quotes in the user principal name are doubled and the value is percent-encoded so
    the OData filter is safe -- this matters for guest (B2B) users whose principal names contain the
    reserved '#' character in the '#EXT#' marker, which must be sent as %23. This private helper is the
    single user-lookup entry point used by the policy builder cmdlets.

    .PARAMETER Id
    The user object id (GUID) to return verbatim. Takes precedence over -UserPrincipalName when both
    are supplied and no Graph call is made.

    .PARAMETER UserPrincipalName
    The user principal name to resolve to an id via a filtered users query when -Id is not supplied.
    If the value is a GUID it is returned verbatim (treated as an id) with no Graph call. Single
    quotes are escaped by doubling them and the value is percent-encoded before the OData filter is
    built (so guest '#EXT#' principal names resolve).

    .EXAMPLE
    Resolve-OERUserId -UserPrincipalName 'anna.berg@contoso.com'
    Returns the object id of the user with that user principal name, or $null when it does not exist.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$UserPrincipalName
    )
    if ($Id) { return $Id }
    if (-not $UserPrincipalName) {
        throw 'Resolve-OERUserId requires either -Id or -UserPrincipalName.'
    }
    if (Test-OERGuid -Value $UserPrincipalName) {
        return $UserPrincipalName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $UserPrincipalName
    $Uri = "v1.0/users?`$filter=userPrincipalName eq '$Escaped'&`$select=id,userPrincipalName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    if ($Response.value -and @($Response.value).Count -gt 0) {
        return [string]@($Response.value)[0].id
    }
    return $null
}
