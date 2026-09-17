function ConvertTo-OERODataFilterValue {
    <#
    .SYNOPSIS
    Escapes a free-text value for safe use inside a single-quoted OData string literal in a URL.

    .DESCRIPTION
    The single owner of the OData filter-value escaping rule used by every display-name lookup in
    this module. Microsoft Graph specifies a two-step contract for a value carried inside a
    single-quoted OData string literal: first double any embedded single quote so the literal is not
    terminated early, then percent-encode the resulting value per RFC 3986 so reserved characters
    survive transport. Doing only the first step leaves a name containing an ampersand, a plus sign,
    a hash or a space to corrupt the query string -- the hash is a URL fragment delimiter, so
    everything after it is dropped before the request ever reaches Graph, which is how a guest (B2B)
    user principal name carrying the EXT marker fails to resolve. Returns an empty string for null
    or empty input. Makes no network call and never throws, so it is safe to call on any code path.

    Callers supply the surrounding single quotes themselves, for example
    "v1.0/groups?`$filter=displayName eq '$Escaped'". Do not use this helper for a filter that is
    placed in a JSON request body rather than a URL, nor for a filter whose structural characters
    (slashes, parentheses) must survive unencoded -- encode the whole filter in those cases instead.

    .PARAMETER Value
    The raw, unescaped value to place inside a single-quoted OData string literal, typically a
    display name or a user principal name supplied by the caller. Null and empty input are accepted
    and produce an empty string.

    .EXAMPLE
    ConvertTo-OERODataFilterValue -Value "Lee's Team & Co"
    Returns Lee%27%27s%20Team%20%26%20Co, ready to interpolate between single quotes in a filter.

    .EXAMPLE
    "v1.0/groups?`$filter=displayName eq '$(ConvertTo-OERODataFilterValue -Value $DisplayName)'"
    Builds a transport-safe filtered group query for an arbitrary display name.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Value
    )
    return [uri]::EscapeDataString(([string]$Value).Replace("'", "''"))
}
