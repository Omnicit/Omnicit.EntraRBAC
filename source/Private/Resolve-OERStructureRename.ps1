function Resolve-OERStructureRename {
    <#
    .SYNOPSIS
    Decides what a structure entry with previousDisplayName means, given what its two names resolved to.

    .DESCRIPTION
    The single owner of the rename decision for the administrativeUnits, catalogs and accessPackages
    sections of a structure document (BL-128, decision A5), and of its error ids and texts. groups[]
    keeps its own decision in Sync-OERStructureGroup. The caller resolves both names first -- the
    entry's displayName (the new name) to -Id and its previousDisplayName to -PreviousId, each $null or
    empty when nothing matches -- before it reads or writes anything for the entry:
    - Both resolve to DIFFERENT objects (ids compared without regard to letter case): Outcome Conflict,
      with a <Kind>RenameConflict ErrorRecord (category ResourceExists, target the new name) and one
      Failed row. The document never merges two objects.
    - Neither resolves: Outcome NotFound, with a <Kind>RenameNotFound ErrorRecord (category
      ObjectNotFound, target the new name) and one Failed row. A document that declares a rename names
      an object that exists, so nothing is ever created for it.
    - Only the previous name resolves: Outcome Rename. The caller acts on that object (Id) and renames it
      to the new name in the same update as every other changed property.
    - Only the new name resolves, or both resolve to the same object: Outcome Current. The caller acts on
      it as on any entry; the rename is already done, or the two names are one object.
    <Kind> is AdministrativeUnit, Catalog or AccessPackage. The caller writes ErrorRecord through its
    engine PSCmdlet and emits Result; this helper writes nothing.

    With -RenameMap, the outcome is registered in the run-scoped map Invoke-OERStructure keeps for one
    document, under the key '<section>|<new name>' in lower case: Rename as the object's id, Conflict and
    NotFound as refused with their ErrorId, Current not at all. Get-OERStructureRenameTarget reads it,
    so a reference to the new name later in the same run (an access package's catalog, a group's
    administrativeUnit when the group is created) reaches the object the document renames, or is refused
    when its rename was. The registration is made when the decision is, so under -WhatIf too and before
    the rename is sent.

    .PARAMETER Section
    The document section of the entry: administrativeUnits, catalogs or accessPackages.

    .PARAMETER Name
    The entry's displayName: the name the object is to carry.

    .PARAMETER PreviousName
    The entry's previousDisplayName as the document wrote it: the object's current display name or
    object id.

    .PARAMETER Id
    The id the new name resolved to, or $null/empty when it matched nothing.

    .PARAMETER PreviousId
    The id the previous name resolved to, or $null/empty when it matched nothing.

    .PARAMETER Catalog
    For accessPackages: the catalog the entry declares, named in the messages (a package is matched
    within its catalog).

    .PARAMETER RenameMap
    The run-scoped rename map Invoke-OERStructure creates once per document. Optional.

    .EXAMPLE
    $Rename = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId $OldId -RenameMap $Map
    Returns Outcome Rename with Id $OldId, and registers 'catalogs|cat-new' as $OldId in $Map.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('administrativeUnits', 'catalogs', 'accessPackages')][string]$Section,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$PreviousName,
        [AllowNull()][AllowEmptyString()][string]$Id,
        [AllowNull()][AllowEmptyString()][string]$PreviousId,
        [AllowNull()][AllowEmptyString()][string]$Catalog,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    $Kind = switch ($Section) {
        'administrativeUnits' { @{ Capital = 'Administrative unit'; One = 'administrative unit'; Many = 'administrative units'; Article = 'an'; Prefix = 'AdministrativeUnit' } }
        'catalogs'            { @{ Capital = 'Catalog'; One = 'catalog'; Many = 'catalogs'; Article = 'a'; Prefix = 'Catalog' } }
        'accessPackages'      { @{ Capital = 'Access package'; One = 'access package'; Many = 'access packages'; Article = 'an'; Prefix = 'AccessPackage' } }
    }
    $Where = if ($Section -eq 'accessPackages' -and $Catalog) { " in catalog '$Catalog'" } else { '' }
    $HasId = -not [string]::IsNullOrEmpty($Id)
    $HasPrev = -not [string]::IsNullOrEmpty($PreviousId)
    $Key = ('{0}|{1}' -f $Section, $Name).ToLowerInvariant()

    $Outcome = if ($HasId -and $HasPrev -and ($Id -ine $PreviousId)) { 'Conflict' }
    elseif (-not $HasId -and -not $HasPrev) { 'NotFound' }
    elseif (-not $HasId) { 'Rename' }
    else { 'Current' }

    $ErrRec = $null
    $Row = $null
    if ($Outcome -eq 'Conflict') {
        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("$($Kind.Capital) '$Name' ($Id) and its previousDisplayName '$PreviousName' ($PreviousId)$Where are different $($Kind.Many). The document never merges two $($Kind.Many), so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName."),
            "$($Kind.Prefix)RenameConflict",
            [System.Management.Automation.ErrorCategory]::ResourceExists,
            $Name)
        $Row = ConvertTo-OERStructureResult -Section $Section -Item $Name -Action 'Failed' `
            -Detail "both '$Name' and its previousDisplayName '$PreviousName' exist$Where as different $($Kind.Many); the document never merges two $($Kind.Many), so nothing was changed -- rename or delete one of them, or remove previousDisplayName" `
            -ErrorRecord $ErrRec
    } elseif ($Outcome -eq 'NotFound') {
        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Neither '$Name' nor its previousDisplayName '$PreviousName' matches $($Kind.Article) $($Kind.One)$Where, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new $($Kind.One), remove previousDisplayName."),
            "$($Kind.Prefix)RenameNotFound",
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Name)
        $Row = ConvertTo-OERStructureResult -Section $Section -Item $Name -Action 'Failed' `
            -Detail "neither '$Name' nor its previousDisplayName '$PreviousName' matches $($Kind.Article) $($Kind.One)$Where, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new $($Kind.One), remove previousDisplayName" `
            -ErrorRecord $ErrRec
    }

    if ($null -ne $RenameMap -and $Outcome -ne 'Current') {
        $Entry = [PSCustomObject]@{
            Section      = $Section
            Name         = $Name
            PreviousName = $PreviousName
            Id           = $(if ($Outcome -eq 'Rename') { [string]$PreviousId } else { $null })
            Refused      = ($Outcome -ne 'Rename')
            ErrorId      = $(if ($ErrRec) { "$($Kind.Prefix)Rename$Outcome" } else { $null })
        }
        $Entry.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRenameTarget')
        $RenameMap[$Key] = $Entry
    }

    $Out = [PSCustomObject]@{
        Outcome     = $Outcome
        Id          = $(switch ($Outcome) { 'Current' { [string]$Id } 'Rename' { [string]$PreviousId } default { $null } })
        RenameFrom  = $(if ($Outcome -eq 'Rename') { $PreviousName } else { $null })
        ErrorRecord = $ErrRec
        Result      = $Row
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRename')
    $Out
}
