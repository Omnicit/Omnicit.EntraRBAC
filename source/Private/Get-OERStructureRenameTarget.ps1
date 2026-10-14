function Get-OERStructureRenameTarget {
    <#
    .SYNOPSIS
    Returns what the run-scoped rename map holds for a reference to a renamed structure object.

    .DESCRIPTION
    Reads the map Resolve-OERStructureRename fills for one document run (BL-128, decision A5). A
    reference to an object by the NEW name another entry of the same document gives it -- an access
    package's catalog, a group's administrativeUnit when the group is created -- is looked up here
    first. $null means the map says nothing: resolve the name as before. An entry with Refused false
    carries the id of the object the document renames in this run (found under its previous name,
    whether or not the rename has been sent yet, -WhatIf included), so the reference uses that id
    instead of a name lookup that cannot find the new name yet. An entry with Refused true means that
    entry's rename failed with a conflict or found nothing (ErrorId), so the object the document means
    cannot be identified and the referring entry must not act. The key is '<section>|<name>' in lower
    case, built exactly as Resolve-OERStructureRename builds it.

    .PARAMETER Section
    The section of the referenced object: administrativeUnits, catalogs or accessPackages.

    .PARAMETER Name
    The name the reference uses.

    .PARAMETER RenameMap
    The run-scoped rename map. Without it, or with an empty name, the result is $null.

    .EXAMPLE
    $Target = Get-OERStructureRenameTarget -Section 'catalogs' -Name $Item.catalog -RenameMap $RenameMap
    Returns the registered entry for that catalog name, or $null.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('administrativeUnits', 'catalogs', 'accessPackages')][string]$Section,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    if ($null -eq $RenameMap -or [string]::IsNullOrEmpty($Name)) { return $null }
    $Entry = $null
    if ($RenameMap.TryGetValue(('{0}|{1}' -f $Section, $Name).ToLowerInvariant(), [ref]$Entry)) { return $Entry }
    return $null
}
