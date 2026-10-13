function Get-OERAccessReviewTargetMismatch {
    <#
    .SYNOPSIS
    Tells whether a live access review found by display name reviews the access package and assignment
    policy an accessReviews[] document entry declares, and builds the error record when it does not.

    .DESCRIPTION
    The single owner of BL-127 (Sprint 11 step 2, Rulings R8 and R9). Sync-OERStructureAccessReview
    finds the live access review definition for an entry by display name in the whole tenant, and
    display names are not unique: a live review of a group, a role or another access package can carry
    the name the document uses for a package review. Before the handler updates the review it found,
    it calls this function, and writes nothing when it returns a record. See
    docs/development/rationale.md#access-review-target.

    Returns nothing when the live review reviews the access package AND the assignment policy the entry
    declares. Otherwise returns ONE ErrorRecord, which it never writes (the caller writes it). It writes
    no error and no warning of its own.

    The checks run in this order, and the first that fails decides:
    1. An entry that declares no accessPackage or no assignmentPolicy (absent, an explicit null, or a
       value that is empty or white space -- the offline validator requires both keys) is refused:
       without both, the review cannot be shown to be the one the entry declares, so the check fails
       closed. No request.
    2. A live review with no AccessPackageId -- a review of a group, a role or anything else that is
       not an access package assignment review -- is refused. No request.
    3. The declared access package is resolved as creation resolves it: a GUID is used verbatim, a name
       goes through Resolve-OERAccessPackageId -DisplayName. It is compared with the live
       AccessPackageId (case-insensitively); another package is refused.
    4. The declared assignment policy is resolved the same way: a GUID verbatim, a name through
       Resolve-OERAssignmentPolicyId against the package id (the lookup creation uses, Ruling R11), and
       compared with the live AssignmentPolicyId (case-insensitively); another policy is refused.

    A refusal is the ErrorId AccessReviewScopeMismatch, category InvalidOperation, targeting the review's
    display name; its message names both targets, says that nothing was written and that access review
    display names are not unique. An empty live scope or live policy is named as 'none'. A name that
    matches nothing returns AccessPackageNotFound or AssignmentPolicyNotFound, category ObjectNotFound,
    targeting the declared value, with the message New-OERAccessReviewDefinition publishes for the same
    lookup ("AccessPackage '<value>' not found."). A lookup that throws -- an ambiguous name, a 403, an
    exhausted 429 -- is scrubbed with Remove-OERErrorRecord and returned as itself, never as a not-found
    and never as a mismatch.

    .PARAMETER Declared
    One accessReviews[] entry from the structure document. Only displayName, accessPackage and
    assignmentPolicy are read, the last two through Test-OERDeclaredProperty.

    .PARAMETER Current
    The live definition as returned by Get-OERAccessReviewDefinition, carrying Scope, AccessPackageId and
    AssignmentPolicyId.

    .EXAMPLE
    $Refusal = Get-OERAccessReviewTargetMismatch -Declared $Item -Current $Existing
    if ($Refusal) { $Caller.WriteError($Refusal); return }

    Refuses to update a live review that does not review the declared access package and assignment
    policy.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Declared,
        [Parameter(Mandatory)][PSCustomObject]$Current
    )
    [string]$Name = $Declared.displayName
    $NotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'
    $NewMismatch = {
        param([string]$Message)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message),
            'AccessReviewScopeMismatch',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Name)
    }
    $NewNotFound = {
        param([string]$Kind, [string]$Value)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("$Kind '$Value' not found."),
            "${Kind}NotFound",
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Value)
    }

    # 1. Fail closed on an entry that cannot be compared. Test-OERDeclaredProperty is the single owner of
    # the declared rule: an explicit null means exactly what an omitted key means. A declared value that
    # is empty or white space names no package or policy either, and would otherwise reach a lookup that
    # refuses it with a message about its own parameters.
    $DeclaresTarget = (Test-OERDeclaredProperty -Node $Declared -Name 'accessPackage') -and
        (Test-OERDeclaredProperty -Node $Declared -Name 'assignmentPolicy')
    [string]$DeclaredPackage = if ($DeclaresTarget) { $Declared.accessPackage } else { '' }
    [string]$DeclaredPolicy = if ($DeclaresTarget) { $Declared.assignmentPolicy } else { '' }
    if ([string]::IsNullOrWhiteSpace($DeclaredPackage) -or [string]::IsNullOrWhiteSpace($DeclaredPolicy)) {
        return (& $NewMismatch ("Access review entry '$Name' declares no access package or no assignment policy, so the review " +
                'in the tenant with that display name cannot be shown to be the one it declares. Nothing was written.'))
    }
    [string]$LivePackage = $Current.AccessPackageId
    [string]$LivePolicy = $Current.AssignmentPolicyId

    # 2. A review that does not review an access package is not the review this entry declares, whatever
    # the entry names. Refused before any lookup, so a group review costs no request.
    if (-not $LivePackage) {
        [string]$LiveScope = $Current.Scope
        if (-not $LiveScope) { $LiveScope = 'none' }
        return (& $NewMismatch ("Access review '$Name' in the tenant does not review an access package (its scope is '$LiveScope'), " +
                "so it is not the review this entry declares for access package '$DeclaredPackage' and assignment policy " +
                "'$DeclaredPolicy'. Nothing was written. $NotUnique"))
    }

    # 3. The access package, resolved as creation resolves it.
    if (Test-OERGuid -Value $DeclaredPackage) {
        $DeclaredPackageId = $DeclaredPackage
        $PackageLabel = "'$DeclaredPackage'"
    } else {
        $DeclaredPackageId = $null
        try {
            $DeclaredPackageId = Resolve-OERAccessPackageId -DisplayName $DeclaredPackage
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # An ambiguous name, a 403 or an exhausted 429 is not evidence about the review: return the
            # record as itself, never as a not-found or a mismatch.
            return $PSItem
        }
        if (-not $DeclaredPackageId) { return (& $NewNotFound 'AccessPackage' $DeclaredPackage) }
        $PackageLabel = "'$DeclaredPackage' ('$DeclaredPackageId')"
    }
    if ($DeclaredPackageId -ine $LivePackage) {
        return (& $NewMismatch ("Access review '$Name' in the tenant reviews access package '$LivePackage', not the access package " +
                "$PackageLabel this entry declares, so it is not the review this entry declares. Nothing was written. $NotUnique"))
    }

    # 4. The assignment policy, resolved against the package the entry declares (which is the live one).
    if (Test-OERGuid -Value $DeclaredPolicy) {
        $DeclaredPolicyId = $DeclaredPolicy
        $PolicyLabel = "'$DeclaredPolicy'"
    } else {
        $DeclaredPolicyId = $null
        try {
            $DeclaredPolicyId = Resolve-OERAssignmentPolicyId -AccessPackageId $DeclaredPackageId -AssignmentPolicy $DeclaredPolicy `
                -AccessPackageLabel $DeclaredPackage
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            return $PSItem
        }
        if (-not $DeclaredPolicyId) { return (& $NewNotFound 'AssignmentPolicy' $DeclaredPolicy) }
        $PolicyLabel = "'$DeclaredPolicy' ('$DeclaredPolicyId')"
    }
    if ($DeclaredPolicyId -ine $LivePolicy) {
        $LivePolicyLabel = if ($LivePolicy) { $LivePolicy } else { 'none' }
        return (& $NewMismatch ("Access review '$Name' in the tenant reviews assignment policy '$LivePolicyLabel' of access package " +
                "'$LivePackage', not the assignment policy $PolicyLabel this entry declares, so it is not the review this entry " +
                "declares. Nothing was written. $NotUnique"))
    }
}
