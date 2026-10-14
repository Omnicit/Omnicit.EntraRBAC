function Get-OERGroupReference {
    <#
    .SYNOPSIS
    Returns how an inventory names a group it references as a principal: its display name or its
    object id.

    .DESCRIPTION
    The single owner of how the export names a GROUP it references as a principal (BL-131, R-2).
    Microsoft Entra ID does not keep group display names unique, and the apply engine refuses a
    group name that more than one live group answers to, so a group is written by its display name
    only when the index of every group in the tenant (Get-OERGroupNameIndex) was read and exactly
    one group, this one, carries that name. Otherwise it is written by its object id, which the
    apply engine resolves verbatim: an index that was not read, a blank name, a name the index does
    not hold, a name the index lists under another group or under more than one group.

    The name is looked up in the index without regard to letter case, the key the index is built
    on, and the id is compared without regard to letter case, since the index holds lower-cased
    ids. A name the index does not hold is never an error: the function makes no request, never
    writes an error record and never throws on a missing key.

    .PARAMETER Id
    The group's object id, returned whenever the name cannot be written.

    .PARAMETER Name
    The name the caller would write for the group (its display name, or its id when no name was
    read). May be empty or null, which writes the id.

    .PARAMETER Index
    The index of every group's name in the tenant, as Get-OERGroupNameIndex returns it (Read and
    IdsByName). May be null, which writes the id.

    .EXAMPLE
    Get-OERGroupReference -Id $Row.PrincipalId -Name 'Admins' -Index $GroupNameIndex
    Returns 'Admins' when this group is the only group in the tenant named Admins in any letter
    case, and the group's object id otherwise.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [AllowEmptyString()][AllowNull()][string]$Name,
        [Parameter(Mandatory)][AllowNull()][object]$Index
    )

    # A null index reads Read as null, so it writes the id with no check of its own. A name the index
    # does not hold reads as null (an index never throws on a missing key here), which @() makes one
    # empty id that never equals the mandatory -Id, so it writes the id too.
    if ($Index.Read -ne $true -or [string]::IsNullOrWhiteSpace($Name)) { return $Id }
    $IdsByName = $Index.IdsByName
    if ($null -eq $IdsByName) { return $Id }
    $Ids = @($IdsByName[$Name])
    if ($Ids.Count -eq 1 -and [string]$Ids[0] -ieq $Id) { return $Name }
    $Id
}
