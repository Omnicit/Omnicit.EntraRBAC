function ConvertTo-OERAssignmentRequest {
    <#
    .SYNOPSIS
    Converts a raw Graph accessPackageAssignmentRequest into a tagged
    Omnicit.EntraRBAC.AssignmentRequest object.

    .DESCRIPTION
    Maps the accessPackageAssignmentRequest returned by POST
    identityGovernance/entitlementManagement/assignmentRequests into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.AssignmentRequest so Format views apply. The v1.0 endpoint returns the request
    state under either state/status or the older requestState/requestStatus spelling depending on the
    request kind, so both are read with state/status winning. The response does not echo the target,
    access package, or policy, so the caller stamps them onto the output through the matching
    parameters. The request id is exposed as RequestId and deliberately NOT as a bare Id: it is the id
    of the REQUEST, not of the resulting assignment, and a bare Id would invite a caller to hand-write
    Remove-OERAccessPackageAssignment -AssignmentId $Result.Id, which would remove the wrong thing.
    This private converter is the single owner of the assignment-request output shape and is used by
    New-OERAccessPackageAssignment.

    .PARAMETER InputObject
    The raw Graph accessPackageAssignmentRequest (hashtable or PSObject). Accepts pipeline input.

    .PARAMETER AccessPackageId
    The id of the access package the request targets, stamped onto the output for correlation.

    .PARAMETER AssignmentPolicyId
    The id of the assignment policy the request was created under, stamped onto the output.

    .PARAMETER TargetId
    The object id of the principal the request assigns, stamped onto the output for correlation.

    .EXAMPLE
    ConvertTo-OERAssignmentRequest -InputObject $Response -AccessPackageId $PackageId -TargetId $UserId
    Returns the tagged assignment request object for a freshly created adminAdd request.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$AccessPackageId,

        [string]$AssignmentPolicyId,

        [string]$TargetId
    )
    process {
        $State = if ($InputObject.state) { $InputObject.state } else { $InputObject.requestState }
        $Status = if ($InputObject.status) { $InputObject.status } else { $InputObject.requestStatus }
        $Out = [PSCustomObject]@{
            RequestId          = [string]$InputObject.id
            RequestType        = [string]$InputObject.requestType
            State              = [string]$State
            Status             = [string]$Status
            Justification      = $InputObject.justification
            TargetId           = $TargetId
            AccessPackageId    = $AccessPackageId
            AssignmentPolicyId = $AssignmentPolicyId
            CreatedDateTime    = $InputObject.createdDateTime
            CompletedDateTime  = $InputObject.completedDateTime
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AssignmentRequest')
        $Out
    }
}
