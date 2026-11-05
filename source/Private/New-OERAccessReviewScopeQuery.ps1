function New-OERAccessReviewScopeQuery {
    <#
    .SYNOPSIS
    Builds the verified v1.0 access-package scope object for an access review definition.

    .DESCRIPTION
    Returns a hashtable representing a microsoft.graph.accessReviewQueryScope that targets the
    assignments of one access package under one assignment policy. This is a pure builder: it makes
    no Graph call. Single quotes in the ids are doubled so the OData filter is safe.

    The scope query targets the v1.0 entitlement management assignments collection
    (/identityGovernance/entitlementManagement/assignments) with a relationship filter
    (accessPackage/id and assignmentPolicy/id). The beta collection name accessPackageAssignments and
    its scalar accessPackageId/assignmentPolicyId/catalogId filter properties do NOT exist on v1.0 --
    a scope query that referenced them was rejected by the access review service with
    "Policy is invalid due to invalid criteria" (the service executes the scope query against v1.0
    Graph, where accessPackageAssignments 404s). The package id pins the exact package, so no catalog
    filter is needed.

    .PARAMETER AccessPackageId
    The access package id to scope the review to.

    .PARAMETER AssignmentPolicyId
    The assignment policy id whose assignments are reviewed.

    With -GroupId (parameter set Group) it builds the scope of a review of a group's members instead:
    '/groups/{id}/transitiveMembers' (Microsoft Learn, "Configure access review scope by using
    Microsoft Graph APIs"). Graph reads it back as '/v1.0/groups/{id}/transitiveMembers/microsoft.graph.user'
    (measured 2026-11-05, Sprint 12 step 6); Resolve-OERAccessReviewGroupScope reads that form.

    .PARAMETER GroupId
    The group whose transitive members are reviewed (parameter set Group).

    .EXAMPLE
    New-OERAccessReviewScopeQuery -AccessPackageId $ap -AssignmentPolicyId $pol
    Returns the scope object for the access package's assignments under the policy.

    .EXAMPLE
    New-OERAccessReviewScopeQuery -GroupId $group
    Returns the scope object for the transitive members of the group.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding(DefaultParameterSetName = 'AccessPackage')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'AccessPackage')][string]$AccessPackageId,
        [Parameter(Mandatory, ParameterSetName = 'AccessPackage')][string]$AssignmentPolicyId,
        [Parameter(Mandatory, ParameterSetName = 'Group')][string]$GroupId
    )
    if ($PSCmdlet.ParameterSetName -eq 'Group') {
        return @{
            '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
            query         = "/groups/$GroupId/transitiveMembers"
            queryType     = 'MicrosoftGraph'
        }
    }
    $Ap = $AccessPackageId.Replace("'", "''")
    $Pol = $AssignmentPolicyId.Replace("'", "''")
    $Filter = "accessPackage/id eq '$Ap' and assignmentPolicy/id eq '$Pol'"
    return @{
        '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
        query         = "/identityGovernance/entitlementManagement/assignments?`$filter=$Filter"
        queryType     = 'MicrosoftGraph'
    }
}
