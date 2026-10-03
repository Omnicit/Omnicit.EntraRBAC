function Resolve-OERAccessReviewScopeTarget {
    <#
    .SYNOPSIS
    Resolves an access package, its catalog, and an assignment policy to the ids needed for an access
    review scope.

    .DESCRIPTION
    Resolves -AccessPackage (display name or GUID) to an id via Resolve-OERAccessPackageId. The catalog
    id is taken from -Catalog when supplied (display name resolved via Resolve-OERCatalogId, GUID used
    verbatim), otherwise read from the access package. The assignment policy id is taken from
    -AssignmentPolicy: a GUID is used verbatim, otherwise the package's assignment policies are queried
    and matched by display name. Returns a hashtable with AccessPackageId, AssignmentPolicyId, CatalogId
    and FailedKind/FailedValue describing the first unresolved input ($null when all resolve).
    FailedErrorId and FailedMessage are optional companions to FailedKind/FailedValue: they are $null
    for a plain not-found on the AccessPackage, explicit-Catalog, and AssignmentPolicy paths, but are
    populated for a catalog that could not be DERIVED from the access package, since that failure is
    not truthfully described as "Catalog '<name>' not found" (the name is the access package's, not a
    catalog's), and for an AMBIGUOUS access package or catalog display name, where the resolver's own
    message naming the candidate ids is far more actionable than a not-found. They are populated too
    for an AMBIGUOUS assignment policy display name -- two or more policies of the package carry it,
    Microsoft Graph does not enforce unique policy names within a package -- with FailedErrorId
    'AmbiguousName' and a message naming every candidate id; the first of them is never taken, and
    the way out for the caller is to pass the policy id, which skips the listing. They are populated for
    EVERY throw out of Resolve-OERAccessPackageId as well, ambiguity or not: its own
    AccessPackageNotFound names the id and why it may be wrong, and a 403 or an exhausted 429 from
    its existence read is not a not-found at all. A third optional companion, FailedCategory, is
    populated on that same EVERY-throw basis, not only on the 403/throttle case: 'InvalidArgument'
    on the ambiguity path, and the caught record's own ErrorCategory on every other throw --
    'PermissionDenied' for a 403, and 'ObjectNotFound' for the resolver's own AccessPackageNotFound,
    which is a category the caller would have derived identically on its own. The ambiguous
    assignment policy display name carries 'InvalidArgument' as well. It is $null on every
    path that does NOT come out of that catch: an access package display name that simply matched
    nothing, both catalog paths (AmbiguousCatalogName and CatalogDerivationFailed included), and the
    assignment policy other than the ambiguity above. A caller that has a FailedCategory uses it; a
    caller that does not keeps its own ErrorId-based derivation.

    FailedRecord is the one carrier shared with Resolve-OERReviewerScope and Resolve-OERTargetList for
    a lookup that FAILED rather than found nothing. It holds the caught ErrorRecord when an explicit
    -Catalog name's Resolve-OERCatalogId throws anything other than an ambiguity, or when the
    assignment policy listing throws -- a 403, an exhausted 429, a 5xx -- and is $null on every other
    descriptor, success included, so a caller can test it without a property check. A refused read is
    not evidence that no such catalog or policy exists, so FailedKind/FailedValue still name the
    lookup, FailedErrorId, FailedMessage and FailedCategory stay $null, and the caller re-publishes
    FailedRecord as itself instead of "<Kind> '<Value>' not found." The access package branch keeps
    its own FailedErrorId/FailedMessage/FailedCategory triple, and CatalogDerivationFailed (the
    package read behind a derived catalog) is already a failure id, so neither sets FailedRecord.

    .PARAMETER AccessPackage
    The access package display name or id.

    .PARAMETER AssignmentPolicy
    The assignment policy display name or id whose assignments are reviewed.

    .PARAMETER Catalog
    Optional catalog display name or id; when omitted the catalog is read from the access package.

    .EXAMPLE
    Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
    Resolves the three ids needed to scope an access review to the package's assignments.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AccessPackage,
        [Parameter(Mandatory)][string]$AssignmentPolicy,
        [string]$Catalog
    )
    $Fail = {
        param($Kind, $Value, $ErrId, $Msg, $Cat, $Rec)
        @{
            AccessPackageId = $null; AssignmentPolicyId = $null; CatalogId = $null
            FailedKind = $Kind; FailedValue = $Value
            FailedErrorId = $ErrId; FailedMessage = $Msg
            # Optional fifth field. Populated on EVERY throw out of Resolve-OERAccessPackageId:
            # 'InvalidArgument' on the ambiguity path below, and the caught record's own
            # ErrorCategory on every other throw -- which includes the 'ObjectNotFound' of the
            # resolver's own AccessPackageNotFound, a category the caller would have derived the
            # same way unaided. It is the 403 and the exhausted throttle that need it, since the
            # ErrorId alone cannot reveal those; the rest ride the same channel rather than being
            # filtered out, so this field is NOT "only where the ErrorId is insufficient". It is
            # $null on every Fail that does not come out of that catch: the plain no-match, both
            # catalog paths, and the assignment policy -- except that an AMBIGUOUS assignment policy
            # display name (decision D3) supplies 'InvalidArgument' here too.
            FailedCategory = $Cat
            # Optional sixth field, the carrier shared with Resolve-OERReviewerScope and
            # Resolve-OERTargetList: the caught ErrorRecord of a lookup that THREW on the explicit
            # -Catalog path or the assignment policy listing, for the caller to re-publish as itself.
            # $null on every other Fail, so a caller tests it without a property check.
            FailedRecord = $Rec
        }
    }

    # An ambiguous display name carries its own ErrorId and message through the Fail channel, so the
    # caller reports the ambiguity instead of the misleading "AccessPackage '<name>' not found.".
    # EVERY other throw travels the same channel, for the same reason: the resolver's own
    # AccessPackageNotFound names the id and says it may be stale, mistyped or from another tenant,
    # and a 403 or an exhausted 429 from its existence read is not evidence that no such package
    # exists. Booking either of those as a plain not-found is the failed-read-as-an-empty-fact
    # defect of issue #76. A display name that matched nothing still returns $null rather than
    # throwing, and that alone keeps the bare not-found shape below.
    $ApId = $null
    try {
        $ApId = Resolve-OERAccessPackageId -DisplayName $AccessPackage
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        if (Test-OERAmbiguousNameError -Record $PSItem) {
            return (& $Fail 'AccessPackage' $AccessPackage 'AmbiguousAccessPackageName' $PSItem.Exception.Message 'InvalidArgument')
        }
        # The record's own ErrorId, taken from the FIRST comma-separated segment: a record that has
        # crossed a WriteError boundary carries the composed '<ErrorId>,<CommandName>' form, and the
        # caller writes this value straight into its own error record's id.
        $ResolverErrorId = (([string]$PSItem.FullyQualifiedErrorId) -split ',')[0].Trim()
        if (-not $ResolverErrorId) { $ResolverErrorId = 'AccessPackageResolveFailed' }
        return (& $Fail 'AccessPackage' $AccessPackage $ResolverErrorId $PSItem.Exception.Message `
                ([string]$PSItem.CategoryInfo.Category))
    }
    if (-not $ApId) { return (& $Fail 'AccessPackage' $AccessPackage) }

    if ($Catalog) {
        $CatId = $null
        if (Test-OERGuid -Value $Catalog) {
            $CatId = $Catalog
        } else {
            try {
                $CatId = Resolve-OERCatalogId -DisplayName $Catalog
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (Test-OERAmbiguousNameError -Record $PSItem) {
                    return (& $Fail 'Catalog' $Catalog 'AmbiguousCatalogName' $PSItem.Exception.Message)
                }
                # Anything else the resolver raised -- a 403, an exhausted 429, a 5xx -- is not evidence
                # that no such catalog exists: carry it out in FailedRecord, never as the not-found below.
                return (& $Fail 'Catalog' $Catalog $null $null $null $PSItem)
            }
        }
        if (-not $CatId) { return (& $Fail 'Catalog' $Catalog) }
    }
    else {
        # The v1.0 accessPackage resource has no catalogId scalar; the catalog is a navigation
        # property, so expand it and read catalog.id (a $select of catalogId returns a 400).
        $Pkg = try { Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?`$expand=catalog" -f $ApId) } catch { Remove-OERErrorRecord -Record $PSItem; $null }
        $CatId = if ($Pkg.catalogId) { [string]$Pkg.catalogId } elseif ($Pkg.catalog) { [string]$Pkg.catalog.id } else { '' }
        # The catalog was DERIVED from the access package, not supplied by the caller. Reporting
        # "Catalog '<access package name>' not found." sends the operator hunting for a catalog by that
        # name, which does not exist. Report what actually failed instead.
        if (-not $CatId) {
            return (& $Fail 'Catalog' $AccessPackage 'CatalogDerivationFailed' (
                "Could not derive the catalog from access package '$AccessPackage'. " +
                "The package was found but its catalog could not be read -- pass -Catalog explicitly, " +
                "or verify the caller has EntitlementManagement read permission on the catalog."))
        }
    }

    if (Test-OERGuid -Value $AssignmentPolicy) {
        $PolId = $AssignmentPolicy
    }
    else {
        # A listing that THROWS has not shown that the package has no such policy: carry the record out
        # in FailedRecord, never as the not-found below. Only a listing that returned and held no policy
        # of that name is a not-found.
        $Resp = $null
        try {
            $Resp = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '{0}'" -f $ApId)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            return (& $Fail 'AssignmentPolicy' $AssignmentPolicy $null $null $null $PSItem)
        }
        # Every match is kept, never just the first (decision D3). Assignment policy display names are
        # NOT unique within an access package in Microsoft Graph, and the review is scoped by the id
        # this resolves, so taking the first of several would silently scope it to an arbitrary policy.
        # More than one match is reported through the same FailedErrorId/FailedMessage/FailedCategory
        # triple the access package branch uses, naming every candidate id. A GUID -AssignmentPolicy
        # skips this listing altogether, so for a caller the id IS the way out of the ambiguity.
        $PolicyMatches = @(@($Resp.value) | Where-Object { $_.displayName -eq $AssignmentPolicy })
        if ($PolicyMatches.Count -gt 1) {
            $AmbiguousIds = ($PolicyMatches | ForEach-Object { [string]$_.id }) -join ', '
            return (& $Fail 'AssignmentPolicy' $AssignmentPolicy 'AmbiguousName' (
                    "Assignment policy display name '$AssignmentPolicy' matches $($PolicyMatches.Count) policies ($AmbiguousIds) in access package '$AccessPackage'. " +
                    'Access packages do not enforce unique policy display names, so this name ' +
                    'cannot identify a single policy. Re-run with the assignment policy id instead of the display name.') 'InvalidArgument')
        }
        $PolId = [string]($PolicyMatches | Select-Object -First 1).id
        if (-not $PolId) { return (& $Fail 'AssignmentPolicy' $AssignmentPolicy) }
    }

    return @{ AccessPackageId = $ApId; AssignmentPolicyId = $PolId; CatalogId = $CatId; FailedKind = $null; FailedValue = $null; FailedRecord = $null }
}
