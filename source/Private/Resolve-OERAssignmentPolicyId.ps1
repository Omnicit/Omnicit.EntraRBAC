function Resolve-OERAssignmentPolicyId {
    <#
    .SYNOPSIS
    Resolves an assignment policy of one access package to its id, accepting either an id or a display
    name.

    .DESCRIPTION
    The single owner of the assignment policy display name lookup (Ruling R11, Sprint 11 step 2). The
    lookup moved here unchanged from Resolve-OERAccessReviewScopeTarget, which creation uses, so that
    Get-OERAccessReviewTargetMismatch, which the apply engine uses before it updates an access review,
    resolves a policy name exactly the way creation does.

    A GUID -AssignmentPolicy is returned verbatim, with no request. Otherwise the policies of the
    access package are listed once (assignmentPolicies filtered on accessPackage/id) and matched on
    display name. One match returns that policy's id; no match returns $null.

    Every match is kept, never just the first (decision D3). Assignment policy display names are NOT
    unique within an access package in Microsoft Graph, and an access review is scoped by the id this
    returns, so taking the first of several would silently pick an arbitrary policy. More than one
    match THROWS an ErrorRecord with ErrorId 'AmbiguousName' and category InvalidArgument, targeting
    the policy value, whose message names every candidate id and the access package. A GUID skips the
    listing altogether, so for a caller the policy id IS the way out of the ambiguity.

    A listing that fails (a 403, an exhausted 429, a 5xx) is not evidence that the package has no such
    policy, so this function does not catch it: the failure propagates to the caller unchanged, and
    the caller scrubs and publishes it as itself.

    .PARAMETER AccessPackageId
    The id of the access package whose assignment policies are listed.

    .PARAMETER AssignmentPolicy
    The assignment policy display name or id.

    .PARAMETER AccessPackageLabel
    How the ambiguity message names the access package, typically the value the caller was given (a
    display name). Defaults to -AccessPackageId.

    .EXAMPLE
    Resolve-OERAssignmentPolicyId -AccessPackageId $ApId -AssignmentPolicy 'Standard' -AccessPackageLabel 'AP-Sales'
    Returns the id of the policy named Standard in that access package, $null when none carries the
    name, and throws AmbiguousName when several do.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AccessPackageId,
        [Parameter(Mandatory)][string]$AssignmentPolicy,
        [string]$AccessPackageLabel
    )
    if (Test-OERGuid -Value $AssignmentPolicy) { return $AssignmentPolicy }
    if (-not $AccessPackageLabel) { $AccessPackageLabel = $AccessPackageId }

    $Resp = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '{0}'" -f $AccessPackageId)
    $PolicyMatches = @(@($Resp.value) | Where-Object { $_.displayName -eq $AssignmentPolicy })
    if ($PolicyMatches.Count -gt 1) {
        $AmbiguousIds = ($PolicyMatches | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Assignment policy display name '$AssignmentPolicy' matches $($PolicyMatches.Count) policies ($AmbiguousIds) in access package '$AccessPackageLabel'. " +
                'Access packages do not enforce unique policy display names, so this name ' +
                'cannot identify a single policy. Re-run with the assignment policy id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $AssignmentPolicy)
    }
    $PolId = [string]($PolicyMatches | Select-Object -First 1).id
    if (-not $PolId) { return $null }
    return $PolId
}
