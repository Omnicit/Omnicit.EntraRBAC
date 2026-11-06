function Get-OERGroupReference {
    <#
    .SYNOPSIS
    Returns how an inventory names a group it references as a principal: its display name or its
    object id. A name that Test-OERGuid accepts is never written as a name.

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

    Two rules apply first, in this order. A blank or null name writes the id. A name that
    Test-OERGuid accepts, in any letter case, writes the id too (Sprint 13 step 2, BL-171c): the
    apply engine reads a name of that shape as an object id, so a group whose display name merely
    looks like a GUID, or equals another group's object id, would otherwise be applied to the wrong
    object. Then either the index rule above decides (parameter set Index, the default), or, with
    -KeepSharedName, the name is written as it is and no index is read.

    -KeepSharedName is for the positions where R-6 of
    docs/development/rationale.md#roster-identity-and-shared-names keeps a shared name: a PIM for
    Groups eligibility principal, an access review reviewer or fallback reviewer, a catalog resource
    and an access package resource role. They write the name even when other groups carry it, but a
    name that Test-OERGuid accepts is written as the id there as well. The set also serves two
    positions that are not a group (R-7): the principal of a role assignment that is a service
    principal or a user, and an application resource of an access package catalog, so an object
    whose display name has the form of an object id is written by its id there too.

    .PARAMETER Id
    The group's object id, returned whenever the name cannot be written.

    .PARAMETER Name
    The name the caller would write for the group (its display name, or its id when no name was
    read). May be empty or null, which writes the id.

    .PARAMETER Index
    The index of every group's name in the tenant, as Get-OERGroupNameIndex returns it (Read and
    IdsByName). May be null, which writes the id. Mandatory in the Index parameter set.

    .PARAMETER KeepSharedName
    Selects the KeepSharedName parameter set: the name is written as it is, shared or not, unless it
    is blank or Test-OERGuid accepts it, when the id is written. No index is taken or read.

    .EXAMPLE
    Get-OERGroupReference -Id $Row.PrincipalId -Name 'Admins' -Index $GroupNameIndex
    Returns 'Admins' when this group is the only group in the tenant named Admins in any letter
    case, and the group's object id otherwise.

    .EXAMPLE
    Get-OERGroupReference -Id $Group.Id -Name $Group.DisplayName -KeepSharedName
    Returns the display name even when other groups carry it, and the group's object id when the
    name is blank or shaped like a GUID.
    #>
    [OutputType([string])]
    [CmdletBinding(DefaultParameterSetName = 'Index')]
    param(
        [Parameter(Mandatory)][string]$Id,
        [AllowEmptyString()][AllowNull()][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Index')][AllowNull()][object]$Index,
        [Parameter(Mandatory, ParameterSetName = 'KeepSharedName')][switch]$KeepSharedName
    )

    # A blank name, then a name the apply engine would read as an object id, write the id.
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Id }
    if (Test-OERGuid -Value $Name) { return $Id }
    if ($KeepSharedName) { return $Name }

    # A null index is refused by name, before any member of it is read, so the declared [AllowNull()]
    # contract holds whatever strict mode the module runs under. A name the index does not hold reads
    # as null (indexing a dictionary never throws on a missing key here), which @() makes one empty id
    # that never equals the mandatory -Id, so it writes the id too.
    if ($null -eq $Index -or $Index.Read -ne $true -or [string]::IsNullOrWhiteSpace($Name)) { return $Id }
    $IdsByName = $Index.IdsByName
    if ($null -eq $IdsByName) { return $Id }
    $Ids = @($IdsByName[$Name])
    if ($Ids.Count -eq 1 -and [string]$Ids[0] -ieq $Id) { return $Name }
    $Id
}
