function Test-OERDeclaredNull {
    <#
    .SYNOPSIS
    Reports whether an apply-document node declares a property as an explicit null.

    .DESCRIPTION
    The single owner of the module's "explicitly null" predicate for apply documents. A property
    counts as an explicit null only when the node exists, carries a property of that name (matched
    case-insensitively, because the apply-document schema is case-insensitive), and its value is
    null. An omitted key is NOT an explicit null -- it returns false, the same as a node that never
    carried the property at all. Several Sync-OERStructure* handlers use this to tell "the document
    omitted this collection, so the existing prune/Extra pass still runs against whatever it finds"
    apart from "the document explicitly nulled this collection, so leave live state alone" -- an
    omitted members/resources/resourceRoles key still reconciles against the declared (empty) set,
    while an explicit null on the same key is a distinct "hands off" signal that skips that pass
    entirely. This is the mirror image of Test-OERDeclaredProperty, which treats an explicit null the
    same as absent; this predicate instead isolates that one case on its own.

    .PARAMETER Node
    The document node to inspect, typically one item or one nested block of an apply document. A
    null node never counts as declaring an explicit null, so a caller may pass an absent block
    without guarding it first.

    .PARAMETER Name
    The property name to look for on the node, matched case-insensitively against the node's own
    property names because the apply-document schema is case-insensitive.

    .EXAMPLE
    Test-OERDeclaredNull -Node ([PSCustomObject]@{ members = $null }) -Name 'members'
    Returns $true, because the document explicitly nulled the members collection.

    .EXAMPLE
    Test-OERDeclaredNull -Node ([PSCustomObject]@{ displayName = 'x' }) -Name 'members'
    Returns $false, because the members key is absent rather than explicitly null.
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

    ($null -ne $Node) -and ($Node.PSObject.Properties.Name -icontains $Name) -and ($null -eq $Node.$Name)
}
