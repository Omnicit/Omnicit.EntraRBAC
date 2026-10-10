function Get-OERSharedNameCause {
    <#
    .SYNOPSIS
    Returns the cause text for objects left out of an inventory because two or more share a name.

    .DESCRIPTION
    The single owner of the sentence that says why live objects whose names match without regard to
    letter case are not written to an inventory: they would be two document entries the validator
    refuses as a duplicate, and the apply engine refuses an ambiguous name anyway, so none of them
    could be applied. Get-OERInventory reports it through its Select-UniqueNamedEntry, for the
    groups, administrative units, catalogs, access packages and access reviews it writes, and
    Get-OERInventoryGroup reports it for the groups under -ExcludeSharedName, which
    Export-OERInventory uses.

    .PARAMETER Path
    The unread entry the text names, as the partial signal spells it: the section and the name
    ('groups/Admins'), or for an access package the catalog and the name.

    .EXAMPLE
    Get-OERSharedNameCause -Path 'groups/Admins'
    Returns the sentence naming groups/Admins as an ambiguous name that is not written.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    "Two or more live objects share the name $Path (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name."
}
