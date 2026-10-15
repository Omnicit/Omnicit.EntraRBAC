function Get-OERStructureRenameTarget {
    <#
    .SYNOPSIS
    Returns what the run-scoped rename map holds for a reference to a renamed structure object.

    .DESCRIPTION
    Reads the map Resolve-OERStructureRename fills for one document run (BL-128, decision A5). A
    reference to an object by the NEW name another entry of the same document gives it -- an access
    package's catalog, a group's administrativeUnit when the group is created, an access review's
    access package or assignment policy -- is looked up here first. $null means the map says nothing:
    resolve the name as before. An entry with Refused false carries the id of the object the document
    renames in this run (found under its previous name, whether or not the rename has been sent yet,
    -WhatIf included), so the reference uses that id instead of a name lookup that cannot find the new
    name yet. An entry with Refused true means the object the document means cannot be identified, so
    the referring entry must not act. It is either a rename that failed with a conflict or found
    nothing (ErrorId and Reason are the error id), or an undecided mark (R12: no ErrorId, and a Reason
    saying that the entry's section is not selected by -Include, or that one of its names could not be
    looked up, or that the entry did not reach a decision). Readers print Reason in their Failed row.
    The key is '<section>|<name>' in lower case, built exactly as Resolve-OERStructureRename builds it.

    An accessPackages entry that renames nothing is registered under the same key (BL-147, R-8;
    docs/development/rationale.md#review-package-in-the-same-run), and its entry carries no previous
    name (PreviousName $null): Refused false with the id of the package the entry found in its catalog or
    created there, or Refused true with no ErrorId and a Reason saying why the entry has no id for it yet.
    A reader tells it from a rename by the empty PreviousName, and words its rows without a rename.

    An assignment policy is registered per access package, so for the assignmentPolicies section the key
    is '<section>|<access package>|<name>' in lower case, and -AccessPackage is the package term: the
    package's display name as its accessPackages entry declares it, or its object id (the owner registers
    the id form too when the package id was known). An empty -AccessPackage returns $null. Access
    reviews are not registered, so the accessReviews section is not served here.

    .PARAMETER Section
    The section of the referenced object: administrativeUnits, catalogs, accessPackages or
    assignmentPolicies.

    .PARAMETER Name
    The name the reference uses.

    .PARAMETER AccessPackage
    For assignmentPolicies: the access package the referenced policy belongs to, as the reference names
    it (its display name or its object id). Ignored for every other section.

    .PARAMETER RenameMap
    The run-scoped rename map. Without it, or with an empty name, the result is $null.

    .EXAMPLE
    $Target = Get-OERStructureRenameTarget -Section 'catalogs' -Name $Item.catalog -RenameMap $RenameMap
    Returns the registered entry for that catalog name, or $null.

    .EXAMPLE
    $Target = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name $Review.assignmentPolicy -AccessPackage $Review.accessPackage -RenameMap $RenameMap
    Returns the registered entry for that policy name in that access package, or $null.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('administrativeUnits', 'catalogs', 'accessPackages', 'assignmentPolicies')][string]$Section,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$AccessPackage,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    if ($null -eq $RenameMap -or [string]::IsNullOrEmpty($Name)) { return $null }
    if ($Section -eq 'assignmentPolicies') {
        if ([string]::IsNullOrEmpty($AccessPackage)) { return $null }
        $Key = ('{0}|{1}|{2}' -f $Section, $AccessPackage, $Name).ToLowerInvariant()
    } else {
        $Key = ('{0}|{1}' -f $Section, $Name).ToLowerInvariant()
    }
    $Entry = $null
    if ($RenameMap.TryGetValue($Key, [ref]$Entry)) { return $Entry }
    return $null
}
