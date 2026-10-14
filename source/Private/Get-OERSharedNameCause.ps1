function Get-OERSharedNameCause {
    <#
    .SYNOPSIS
    Returns the cause text for objects left out of an inventory because two or more share a name.

    .DESCRIPTION
    The single owner of the sentence that says why live objects whose names match without regard to
    letter case are not written to an inventory: they would be two document entries the validator
    refuses as a duplicate, and the apply engine refuses an ambiguous name anyway, so none of them
    could be applied. The sentence names how many live objects carry the name. Get-OERInventory
    reports it through its Select-UniqueNamedEntry, for the groups, administrative units, catalogs,
    access packages and access reviews it writes, and Get-OERInventoryGroup reports it for the groups
    under -ExcludeSharedName, which Export-OERInventory uses.

    .PARAMETER Path
    The unread entry the text names, as the partial signal spells it: the section and the name
    ('groups/Admins'), or for an access package the catalog and the name.

    .PARAMETER Count
    How many live objects carry the name, as the caller counted them. For a group that is the larger
    of the count among the groups the inventory listed and the count among every group in the tenant
    (Get-OERGroupNameIndex), so a security group that shares its name with a Microsoft 365 group or a
    distribution group is counted with it; for any other object, the count among the objects read.

    .EXAMPLE
    Get-OERSharedNameCause -Path 'groups/Admins' -Count 2
    Returns the sentence naming groups/Admins as a name two live objects share, which is not written.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$Count
    )

    "$Count live objects share the name $Path (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name."
}
