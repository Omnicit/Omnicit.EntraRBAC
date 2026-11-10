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

    With -DirectoryRoleId (parameter set DirectoryRole) it builds the scope of a review of the users
    assigned to one directory role (who Microsoft Graph asks to review was not measured): a principalResourceMembershipsScope with the
    principal scope '/users' and the resource scope '/roleManagement/directory/roleDefinitions/{id}'
    (measured 2026-11-07). Microsoft Learn's example 12.1, an accessReviewQueryScope whose query is the
    role definition alone, is refused by Graph on write (400), so it is never built. Graph reads the form
    back with '/v1.0/users' and a '/beta' resource query; Resolve-OERAccessReviewRoleScope reads that.

    .PARAMETER DirectoryRoleId
    The directory role definition whose assignments are reviewed (parameter set DirectoryRole).

    .PARAMETER DirectoryRoleAssignmentType
    Eligible or Active (parameter set DirectoryRole only; compared without regard to letter case).
    Unbound, the all-assignments scope above is returned, exactly as before. Eligible builds an
    accessReviewQueryScope whose query is
    '/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal&$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '{id}')';
    Active builds one over '/roleManagement/directory/roleAssignmentScheduleInstances' filtered on
    assignmentType 'Assigned' as well. Both texts are written without a version prefix, which is the
    exact text Resolve-OERAccessReviewRoleScope classifies. Microsoft Graph accepted both forms (POST 201)
    and read them back with a leading '/beta' (measured 2026-11-10). Who Microsoft Graph asks to review
    was not measured.

    .EXAMPLE
    New-OERAccessReviewScopeQuery -AccessPackageId $ap -AssignmentPolicyId $pol
    Returns the scope object for the access package's assignments under the policy.

    .EXAMPLE
    New-OERAccessReviewScopeQuery -DirectoryRoleId $role
    Returns the scope object for every user's assignments to the directory role.

    .EXAMPLE
    New-OERAccessReviewScopeQuery -DirectoryRoleId $role -DirectoryRoleAssignmentType Eligible
    Returns the accessReviewQueryScope over the role's eligible assignment schedule instances.

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
        [Parameter(Mandatory, ParameterSetName = 'Group')][string]$GroupId,
        [Parameter(Mandatory, ParameterSetName = 'DirectoryRole')][string]$DirectoryRoleId,
        [Parameter(ParameterSetName = 'DirectoryRole')][ValidateSet('Eligible', 'Active')][string]$DirectoryRoleAssignmentType
    )
    if ($PSCmdlet.ParameterSetName -eq 'DirectoryRole') {
        if ($DirectoryRoleAssignmentType -eq 'Eligible') {
            return @{
                '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
                query         = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '$DirectoryRoleId')"
                queryType     = 'MicrosoftGraph'
            }
        }
        if ($DirectoryRoleAssignmentType -eq 'Active') {
            return @{
                '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
                query         = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '$DirectoryRoleId')"
                queryType     = 'MicrosoftGraph'
            }
        }
        return @{
            '@odata.type'  = '#microsoft.graph.principalResourceMembershipsScope'
            principalScopes = @(
                @{
                    '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
                    query         = '/users'
                    queryType     = 'MicrosoftGraph'
                }
            )
            resourceScopes = @(
                @{
                    '@odata.type' = '#microsoft.graph.accessReviewQueryScope'
                    query         = "/roleManagement/directory/roleDefinitions/$DirectoryRoleId"
                    queryType     = 'MicrosoftGraph'
                }
            )
        }
    }
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
