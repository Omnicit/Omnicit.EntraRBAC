function Test-OERScheduleRequestFailed {
    <#
    .SYNOPSIS
    Tells whether the status a PIM schedule request was answered with means that the request failed.

    .DESCRIPTION
    The single owner of the rule that decides when a PIM schedule request that Microsoft Graph or
    Azure Resource Manager ACCEPTED is still an error. Returns $true exactly when -Status starts with
    Failed, compared without regard to letter case: Failed, FailedAsResourceIsLocked and any later
    value of the Failed family. $null, an empty string and every other value return $false. Pure: it
    makes no Graph or ARM call and writes nothing.

    Called by the twelve cmdlets that send a schedule request and emit its answer -- Add- and
    Remove-OERGroupEligibility, New- and Remove-OEREligibleDirectoryRoleAssignment, New- and
    Remove-OERActiveDirectoryRoleAssignment, New- and Remove-OEREligibleRoleAssignment, New- and
    Remove-OERActiveRoleAssignment, and Enable- and Disable-OEREligibleRoleAssignment -- and by the
    two new-group replication waits in Sync-OERStructureGroup. Nothing else in the module compares a
    status with a Failed literal. The cohort check in this function's unit test file holds that the
    twelve cmdlet files call this function and that no other file under source/ compares a status
    with a Failed literal in the shapes it scans; it does not hold the two replication waits, whose
    behaviour tests in tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1 do.

    The documented statuses. Microsoft Graph, on the request resource that
    unifiedRoleEligibilityScheduleRequest, unifiedRoleAssignmentScheduleRequest and
    privilegedAccessGroupEligibilityScheduleRequest inherit
    (learn.microsoft.com/graph/api/resources/request?view=graph-rest-1.0): Canceled, Denied, Failed,
    Granted, PendingAdminDecision, PendingApproval, PendingProvisioning, PendingScheduleCreation,
    Provisioned, Revoked, ScheduleCreated. Azure Resource Manager, Microsoft.Authorization
    api-version 2020-10-01, the Status enum of role assignment and role eligibility schedule
    requests (learn.microsoft.com, the azure-mgmt-authorization v2020_10_01 Status enum, and the
    Az.Resources completer for IRoleAssignmentScheduleRequest.Status): Accepted, PendingEvaluation,
    Granted, Denied, PendingProvisioning, Provisioned, PendingRevocation, Revoked, Canceled, Failed,
    PendingApprovalProvisioning, PendingApproval, FailedAsResourceIsLocked, PendingAdminDecision,
    AdminApproved, AdminDenied, TimedOut, ProvisioningStarted, Invalid, PendingScheduleCreation,
    ScheduleCreated, PendingExternalProvisioning.

    Why only the Failed family is an error. A Failed answer means that the service took the request
    and did nothing with it, so the request object must not be read as a grant, a removal, an
    activation or a deactivation. Denied, AdminDenied, Canceled and TimedOut are outcomes of an
    approval, or of a requester's cancellation, that come after the request was answered, never the
    synchronous answer to the admin and self requests these cmdlets send. Invalid has no documented
    meaning. The Pending values and the in-progress ones (Accepted, ProvisioningStarted,
    AdminApproved, Granted, ScheduleCreated) are on their way. Revoked is a removal's success and is
    never an error. Should one of those ever be measured as the synchronous answer to a request that
    did nothing, this function is the one place to add it.

    .PARAMETER Status
    The status the request was answered with, as the cmdlet's output object carries it (its Status
    property). $null and an empty string are accepted, and neither is a failure.

    .EXAMPLE
    Test-OERScheduleRequestFailed -Status 'FailedAsResourceIsLocked'
    Returns $true: the status is in the Failed family.

    .EXAMPLE
    Test-OERScheduleRequestFailed -Status 'Revoked'
    Returns $false: a removal answered Revoked succeeded.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Status
    )
    # -like is case-insensitive, and the pattern anchors at the start: ' Failed' and 'NotFailed' are
    # not in the family.
    $Status -like 'Failed*'
}
