function Test-OERDeclaredProperty {
    <#
    .SYNOPSIS
    Reports whether an apply-document node declares a property with a usable value.

    .DESCRIPTION
    The single owner of the module's "declared" predicate for apply documents. A property counts as
    declared only when the node exists, carries a property of that name (matched case-insensitively,
    because the apply-document schema is case-insensitive), and the value is not null. An explicit
    JSON null therefore means exactly what an omitted key means -- leave the live value untouched --
    while an empty string and an empty array stay declared, because "" is the documented value that
    clears a description or disables an authentication context and [] is how a document asserts an
    empty list. Without the non-null clause a declared null is coerced downstream ([string]$null is
    '', [bool]$null is $false, [int]$null is 0) and silently overwrites live tenant state, which the
    offline validator cannot catch because it treats the same null as absent. Note the predicate
    reads PSObject properties, so it sees the PSCustomObject graph ConvertFrom-Json produces and
    deliberately does not see raw hashtable keys.

    .PARAMETER Node
    The document node to inspect, typically one item or one nested block of an apply document. A null
    node is never declared, so a caller may pass an absent block without guarding it first.

    .PARAMETER Name
    The property name to look for on the node, matched case-insensitively against the node's own
    property names because the apply-document schema is case-insensitive.

    .EXAMPLE
    Test-OERDeclaredProperty -Node ([PSCustomObject]@{ description = $null }) -Name 'description'
    Returns $false, because an explicit null means the property was not declared.

    .EXAMPLE
    Test-OERDeclaredProperty -Node ([PSCustomObject]@{ description = '' }) -Name 'description'
    Returns $true, because an empty string is the documented value that clears a description.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object]$Node,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $null -ne $Node -and ($Node.PSObject.Properties.Name -icontains $Name) -and $null -ne $Node.$Name
}
