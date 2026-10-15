function Resolve-OERStructureRename {
    <#
    .SYNOPSIS
    Decides what a structure entry with previousDisplayName means, given what its two names resolved to,
    and registers an access package entry that renames nothing in the run's rename map.

    .DESCRIPTION
    The single owner of the rename decision for the administrativeUnits, catalogs, accessPackages,
    assignmentPolicies and accessReviews sections of a structure document (BL-128, decision A5), and of
    its error ids and texts. groups[] keeps its own decision in Sync-OERStructureGroup. The caller
    resolves both names first -- the entry's displayName (the new name) to -Id and its
    previousDisplayName to -PreviousId, each $null or empty when nothing matches -- before it reads or
    writes anything for the entry:
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
    <Kind> is AdministrativeUnit, Catalog, AccessPackage, AssignmentPolicy or AccessReview. The caller
    writes ErrorRecord through its engine PSCmdlet and emits Result; this helper writes nothing.

    An assignment policy is matched within its access package, so -AccessPackage is required for the
    assignmentPolicies section (a caller error, thrown as an ArgumentException) and names the package in
    the messages. The Failed row of a policy is a row of the package's entry, as every other policy row
    is: Section accessPackages, Item the package's display name, and a Detail that starts
    "assignmentPolicy '<new name>': ". An access review is matched tenant-wide and its row is an
    accessReviews row for the new name.

    With -RenameMap, the outcome is registered in the run-scoped map Invoke-OERStructure keeps for one
    document, under the key '<section>|<new name>' in lower case (for a policy
    'assignmentPolicies|<package>|<new name>', the package as its accessPackages entry declares it):
    Rename as the object's id, Conflict and NotFound as refused with their ErrorId (which is also the
    entry's Reason), and Current by removing any entry already registered for the key. For a policy,
    when -AccessPackageId is given the same outcome is applied under the key built with the package id
    as well (the same entry, or the same removal), so a reference that names the package by object id
    finds it. Get-OERStructureRenameTarget reads it, so a reference to the new name later in the same
    run (an access package's catalog, a group's administrativeUnit when the group is created, an access
    review's access package or assignment policy) reaches the object the document renames, or is
    refused when its rename was. The registration is made when the decision is, so under -WhatIf too and
    before the rename is sent. Nothing reads a registered access review yet, so its handler decides
    without -RenameMap.

    -Undecided registers a rename the run cannot decide (decision R12): a refused entry with no id and
    no ErrorId, whose Reason is the text given, and returns Outcome Undecided (Id, RenameFrom,
    ErrorRecord and Result all $null). A reference to the new name is then refused instead of being
    looked up by name, which while another object carries that name would reach that object. The
    handlers register it before they look up either name, so a lookup that throws leaves it and the
    decision after the lookups replaces it; Invoke-OERStructure registers it for every entry of a
    section -Include leaves out. It is registered under the keys a decision uses: for a policy whose
    -AccessPackageId is given, under the key built with the package id as well (the same entry), so a
    reference that names the package by object id is refused too. A decision made with the same
    package id replaces it under both keys, and a Current outcome removes both. Without -RenameMap it
    registers nothing.

    -Identified and -Unidentified register an accessPackages entry that renames nothing (BL-147, R-8;
    docs/development/rationale.md#review-package-in-the-same-run), under the same key
    'accessPackages|<name>' a rename uses, so a review that names the package by that name reaches the
    package the entry means, or is refused, and is never looked up by name in the whole tenant, where a
    package of that name in another catalog would be found. -Identified -Id registers the package the
    entry found in its catalog or created there: not refused, with that id. -Unidentified -Reason registers
    it refused, with no id and no ErrorId, until the entry has the package's id. Neither takes a previous
    name, and the entry they register carries none (PreviousName $null): that is how a reader tells such
    an entry from a rename's. They return Outcome Identified (with Id) or Unidentified, every other
    member $null. Only the accessPackages section is registered this way: any other section, or
    -Identified with an empty id, is a caller error, thrown as an ArgumentException before anything is
    registered. Without -RenameMap they register nothing.

    .PARAMETER Section
    The document section of the entry: administrativeUnits, catalogs, accessPackages, assignmentPolicies
    or accessReviews.

    .PARAMETER Name
    The entry's displayName: the name the object is to carry.

    .PARAMETER PreviousName
    The entry's previousDisplayName as the document wrote it: the object's current display name or
    object id. Not taken with -Identified or -Unidentified.

    .PARAMETER Id
    The id the new name resolved to, or $null/empty when it matched nothing. With -Identified, required
    and not empty: the id of the access package the entry found or created.

    .PARAMETER PreviousId
    The id the previous name resolved to, or $null/empty when it matched nothing.

    .PARAMETER Catalog
    For accessPackages: the catalog the entry declares, named in the messages (a package is matched
    within its catalog).

    .PARAMETER AccessPackage
    For assignmentPolicies, and required there: the display name of the access package the policy
    belongs to, as its accessPackages entry declares it. Named in the messages, used as the Item of the
    policy's row and as the package term of the rename map key. Ignored for every other section.

    .PARAMETER AccessPackageId
    For assignmentPolicies: the package's object id, when it is known at decision time. With
    -RenameMap the outcome -- or, with -Undecided, the undecided mark -- is also applied under the key
    built with the id. Ignored for every other section.

    .PARAMETER RenameMap
    The run-scoped rename map Invoke-OERStructure creates once per document. Optional.

    .PARAMETER Undecided
    Registers the rename as one this run cannot decide, instead of deciding it; requires -Reason.

    .PARAMETER Reason
    With -Undecided: why the rename cannot be decided, as a clause the readers print in their Failed row.
    With -Unidentified: why the entry has no id for its access package yet, the same way.

    .PARAMETER Identified
    Registers an accessPackages entry that renames nothing as the access package it found or created:
    the id given by -Id. accessPackages section only.

    .PARAMETER Unidentified
    Registers an accessPackages entry that renames nothing as refused, with -Reason, until it registers
    the package's id. accessPackages section only.

    .EXAMPLE
    $Rename = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId $OldId -RenameMap $Map
    Returns Outcome Rename with Id $OldId, and registers 'catalogs|cat-new' as $OldId in $Map.

    .EXAMPLE
    $Rename = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId $OldId -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
    Returns Outcome Rename with Id $OldId, and registers 'assignmentpolicies|ap-main|pol-new' and
    'assignmentpolicies|<package id>|pol-new' as $OldId in $Map.

    .EXAMPLE
    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Undecided -Reason 'one of its names could not be looked up' -RenameMap $Map
    Registers 'catalogs|cat-new' in $Map as refused with that reason, until a decision replaces it.

    .EXAMPLE
    $null = Resolve-OERStructureRename -Section 'accessPackages' -Name 'AP-Main' -Identified -Id $PackageId -RenameMap $Map
    Registers 'accesspackages|ap-main' in $Map as the package an entry without a rename found or created.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Decide')]
    param(
        [Parameter(Mandatory)][ValidateSet('administrativeUnits', 'catalogs', 'accessPackages', 'assignmentPolicies', 'accessReviews')][string]$Section,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Decide')]
        [Parameter(Mandatory, ParameterSetName = 'Undecided')]
        [string]$PreviousName,
        [Parameter(ParameterSetName = 'Decide')]
        [Parameter(Mandatory, ParameterSetName = 'Identified')]
        [AllowNull()][AllowEmptyString()][string]$Id,
        [Parameter(ParameterSetName = 'Decide')][AllowNull()][AllowEmptyString()][string]$PreviousId,
        [Parameter(ParameterSetName = 'Decide')][AllowNull()][AllowEmptyString()][string]$Catalog,
        [Parameter(Mandatory, ParameterSetName = 'Undecided')][switch]$Undecided,
        [Parameter(Mandatory, ParameterSetName = 'Undecided')]
        [Parameter(Mandatory, ParameterSetName = 'Unidentified')]
        [string]$Reason,
        [Parameter(Mandatory, ParameterSetName = 'Identified')][switch]$Identified,
        [Parameter(Mandatory, ParameterSetName = 'Unidentified')][switch]$Unidentified,
        [AllowNull()][AllowEmptyString()][string]$AccessPackage,
        [AllowNull()][AllowEmptyString()][string]$AccessPackageId,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    # BL-147 (R-8): an accessPackages entry that renames nothing registers its package under the key a
    # rename uses -- the package's id once the entry found or created it, refused with a reason until then
    # -- and no previous name, which is how a reader tells it from a rename. Only that section is
    # registered this way, and an identified package always has an id: anything else is a private caller
    # error, so it throws before anything is registered.
    if ($Identified -or $Unidentified) {
        if ($Section -ne 'accessPackages') {
            throw [System.ArgumentException]::new("An entry that renames nothing (-Identified, -Unidentified) is registered for the accessPackages section only, not for $Section.", 'Section')
        }
        if ($Identified -and [string]::IsNullOrEmpty($Id)) {
            throw [System.ArgumentException]::new('-Identified requires the id of the access package the entry found or created.', 'Id')
        }
        $Outcome = if ($Identified) { 'Identified' } else { 'Unidentified' }
        if ($null -ne $RenameMap) {
            $Entry = [PSCustomObject]@{
                Section      = $Section
                Name         = $Name
                PreviousName = $null
                Id           = $(if ($Identified) { [string]$Id } else { $null })
                Refused      = [bool]$Unidentified
                ErrorId      = $null
                Reason       = $(if ($Unidentified) { $Reason } else { $null })
            }
            $Entry.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRenameTarget')
            $RenameMap[('{0}|{1}' -f $Section, $Name).ToLowerInvariant()] = $Entry
        }
        $Registered = [PSCustomObject]@{
            Outcome     = $Outcome
            Id          = $(if ($Identified) { [string]$Id } else { $null })
            RenameFrom  = $null
            ErrorRecord = $null
            Result      = $null
        }
        $Registered.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureRename')
        return $Registered
    }

    # A policy is matched within its package: without the package there is no key and no message to
    # build. A private caller error, so it throws (the callers pass the package their entry sits in).
    $IsPolicy = $Section -eq 'assignmentPolicies'
    if ($IsPolicy -and [string]::IsNullOrEmpty($AccessPackage)) {
        throw [System.ArgumentException]::new('-AccessPackage is required for the assignmentPolicies section: an assignment policy is matched within its access package.', 'AccessPackage')
    }

    # The keys the outcome is registered under, owned here and in Get-OERStructureRenameTarget alone: the
    # name key, and for a policy whose package id is known the same key with the id as well.
    if ($IsPolicy) {
        $Key = ('{0}|{1}|{2}' -f $Section, $AccessPackage, $Name).ToLowerInvariant()
        $IdKey = $(if (-not [string]::IsNullOrEmpty($AccessPackageId)) { ('{0}|{1}|{2}' -f $Section, $AccessPackageId, $Name).ToLowerInvariant() } else { $null })
    } else {
        $Key = ('{0}|{1}' -f $Section, $Name).ToLowerInvariant()
        $IdKey = $null
    }
    $DecisionKeys = @($Key)
    if ($IdKey) { $DecisionKeys += $IdKey }

    # R12: a rename this run cannot decide -- one of its names could not be looked up, or -Include
    # leaves its section out. Registered as refused, so a reference to the new name is refused rather
    # than looked up by name; a decision for the same key replaces it. Under the keys a decision uses,
    # as the same entry: for a policy whose package id is known, the key with the id as well, so a
    # reference that names the package by object id is refused too instead of looking the policy up by
    # name within the package, where another policy may carry the new name.
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
            foreach ($DecisionKey in $DecisionKeys) { $RenameMap[$DecisionKey] = $Marker }
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
        'assignmentPolicies'  { @{ Capital = 'Assignment policy'; One = 'assignment policy'; Many = 'assignment policies'; Article = 'an'; Prefix = 'AssignmentPolicy' } }
        'accessReviews'       { @{ Capital = 'Access review'; One = 'access review'; Many = 'access reviews'; Article = 'an'; Prefix = 'AccessReview' } }
    }
    $Where = if ($Section -eq 'accessPackages' -and $Catalog) { " in catalog '$Catalog'" }
    elseif ($IsPolicy) { " in access package '$AccessPackage'" }
    else { '' }
    # D2: every row about a policy is a row of its package's entry, with the policy named in the
    # detail, as every other policy row of the access package handler is.
    if ($IsPolicy) {
        $RowSection = 'accessPackages'
        $RowItem = $AccessPackage
        $DetailPrefix = "assignmentPolicy '$Name': "
    } else {
        $RowSection = $Section
        $RowItem = $Name
        $DetailPrefix = ''
    }
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
        $Row = ConvertTo-OERStructureResult -Section $RowSection -Item $RowItem -Action 'Failed' `
            -Detail "${DetailPrefix}both '$Name' and its previousDisplayName '$PreviousName' exist$Where as different $($Kind.Many); the document never merges two $($Kind.Many), so nothing was changed -- rename or delete one of them, or remove previousDisplayName" `
            -ErrorRecord $ErrRec
    } elseif ($Outcome -eq 'NotFound') {
        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Neither '$Name' nor its previousDisplayName '$PreviousName' matches $($Kind.Article) $($Kind.One)$Where, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new $($Kind.One), remove previousDisplayName."),
            "$($Kind.Prefix)RenameNotFound",
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Name)
        $Row = ConvertTo-OERStructureResult -Section $RowSection -Item $RowItem -Action 'Failed' `
            -Detail "${DetailPrefix}neither '$Name' nor its previousDisplayName '$PreviousName' matches $($Kind.Article) $($Kind.One)$Where, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new $($Kind.One), remove previousDisplayName" `
            -ErrorRecord $ErrRec
    }

    if ($null -ne $RenameMap -and $Outcome -eq 'Current') {
        # The new name finds the object: a reference to it needs no map, and an earlier mark for this
        # key (an undecided one, registered before the lookups) no longer holds. Both keys of a policy.
        foreach ($DecisionKey in $DecisionKeys) { $null = $RenameMap.Remove($DecisionKey) }
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
        foreach ($DecisionKey in $DecisionKeys) { $RenameMap[$DecisionKey] = $Entry }
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
