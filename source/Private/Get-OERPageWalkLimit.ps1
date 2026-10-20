function Get-OERPageWalkLimit {
    <#
    .SYNOPSIS
    Returns the number of pages a Graph or Azure Resource Manager -All walk may request.

    .DESCRIPTION
    The single owner of the page limit of Invoke-OERGraphRequest -All and Invoke-OERArmRequest -All.
    Each wrapper reads it ONCE per -All call, before its paging loop, and refuses the walk (it fails,
    it does not truncate) before requesting the page after the limit.

    The limit is a backstop against a service that never ends its next links, not a page size: at the
    smallest page a transport serves (a handful of items) it is far beyond any real collection in
    a tenant, so a legitimate enumeration never meets it. A walk that did meet it would otherwise
    have run for ever, so it is refused as incomplete and never returned as though it were the whole
    collection.

    The function takes no parameters and makes no request. A test that needs a small limit mocks this
    function in module scope instead of building a hundred thousand pages.

    .EXAMPLE
    Get-OERPageWalkLimit
    Returns 100000.

    .EXAMPLE
    $PageLimit = Get-OERPageWalkLimit
    if ($PageNumber -gt $PageLimit) { ... refuse the walk ... }
    Reads the limit once before the paging loop, as both wrappers do.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()
    return [int]100000
}
