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
    NotFound as refused with their ErrorId (which is also the entry's Reason), and Current by removing
    any entry already registered for the key. Get-OERStructureRenameTarget reads it, so a reference to
    the new name later in the same run (an access package's catalog, a group's administrativeUnit when
    the group is created) reaches the object the document renames, or is refused when its rename was.
    The registration is made when the decision is, so under -WhatIf too and before the rename is sent.

    -Undecided registers a rename the run cannot decide (decision R12): a refused entry with no id and
    no ErrorId, whose Reason is the text given, and returns Outcome Undecided (Id, RenameFrom,
    ErrorRecord and Result all $null). A reference to the new name is then refused instead of being
    looked up by name, which while another object carries that name would reach that object. The
    administrative unit and catalog handlers register it before they look up either name, so a lookup
    that throws leaves it and the decision after the lookups replaces it; Invoke-OERStructure
    registers it for every entry of a section -Include leaves out. Without -RenameMap it registers
    nothing.

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

    .PARAMETER Undecided
    Registers the rename as one this run cannot decide, instead of deciding it; requires -Reason.

    .PARAMETER Reason
    With -Undecided: why the rename cannot be decided, as a clause the readers print in their Failed row.

    .EXAMPLE
    $Rename = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId $OldId -RenameMap $Map
    Returns Outcome Rename with Id $OldId, and registers 'catalogs|cat-new' as $OldId in $Map.

    .EXAMPLE
    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Undecided -Reason 'one of its names could not be looked up' -RenameMap $Map
    Registers 'catalogs|cat-new' in $Map as refused with that reason, until a decision replaces it.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Decide')]
    param(
        [Parameter(Mandatory)][ValidateSet('administrativeUnits', 'catalogs', 'accessPackages')][string]$Section,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$PreviousName,
        [Parameter(ParameterSetName = 'Decide')][AllowNull()][AllowEmptyString()][string]$Id,
        [Parameter(ParameterSetName = 'Decide')][AllowNull()][AllowEmptyString()][string]$PreviousId,
        [Parameter(ParameterSetName = 'Decide')][AllowNull()][AllowEmptyString()][string]$Catalog,
        [Parameter(Mandatory, ParameterSetName = 'Undecided')][switch]$Undecided,
        [Parameter(Mandatory, ParameterSetName = 'Undecided')][string]$Reason,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    $Key = ('{0}|{1}' -f $Section, $Name).ToLowerInvariant()

    # R12: a rename this run cannot decide -- one of its names could not be looked up, or -Include
    # leaves its section out. Registered as refused, so a reference to the new name is refused rather
    # than looked up by name; a decision for the same key replaces it.
    if ($Undecided) {
        if ($null -ne $RenameMap) {
            $Marker = [PSCustomObject]@{
                Section      = $Section
                Name         = $Name
                PreviousName = $PreviousName
                Id           = $null
                Refused      = $true
                ErrorId      = $null
                Reason       = $Reason
            }
            $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRenameTarget')
            $RenameMap[$Key] = $Marker
        }
        $Pending = [PSCustomObject]@{
            Outcome     = 'Undecided'
            Id          = $null
            RenameFrom  = $null
            ErrorRecord = $null
            Result      = $null
        }
        $Pending.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRename')
        return $Pending
    }

    $Kind = switch ($Section) {
        'administrativeUnits' { @{ Capital = 'Administrative unit'; One = 'administrative unit'; Many = 'administrative units'; Article = 'an'; Prefix = 'AdministrativeUnit' } }
        'catalogs'            { @{ Capital = 'Catalog'; One = 'catalog'; Many = 'catalogs'; Article = 'a'; Prefix = 'Catalog' } }
        'accessPackages'      { @{ Capital = 'Access package'; One = 'access package'; Many = 'access packages'; Article = 'an'; Prefix = 'AccessPackage' } }
    }
    $Where = if ($Section -eq 'accessPackages' -and $Catalog) { " in catalog '$Catalog'" } else { '' }
    $HasId = -not [string]::IsNullOrEmpty($Id)
    $HasPrev = -not [string]::IsNullOrEmpty($PreviousId)

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

    if ($null -ne $RenameMap -and $Outcome -eq 'Current') {
        # The new name finds the object: a reference to it needs no map, and an earlier mark for this
        # key (an undecided one, registered before the lookups) no longer holds.
        $null = $RenameMap.Remove($Key)
    } elseif ($null -ne $RenameMap) {
        $RefusedId = $(if ($ErrRec) { "$($Kind.Prefix)Rename$Outcome" } else { $null })
        $Entry = [PSCustomObject]@{
            Section      = $Section
            Name         = $Name
            PreviousName = $PreviousName
            Id           = $(if ($Outcome -eq 'Rename') { [string]$PreviousId } else { $null })
            Refused      = ($Outcome -ne 'Rename')
            ErrorId      = $RefusedId
            Reason       = $RefusedId
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
