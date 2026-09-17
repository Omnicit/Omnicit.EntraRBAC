function ConvertTo-OERAssignment {
    <#
    .SYNOPSIS
    Converts a raw Graph accessPackageAssignment into a tagged Omnicit.EntraRBAC.Assignment object.

    .DESCRIPTION
    Maps the relevant properties of a Graph access package assignment into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.Assignment, following the module-wide convention of an id plus a display name --
    TargetId/TargetDisplayName and AccessPackageId/AccessPackageDisplayName -- for every nested
    identity. The historical bare AccessPackageName is kept as an alias so existing scripts keep
    working. TargetId is read from target.objectId (the directory object id of the subject) first,
    falling back to target.id (the subject record's own id, which the docs explicitly warn should not
    be relied on) only when objectId is absent. The expiry is read from the top-level expiredDateTime
    property first, falling back to schedule.expiration.endDateTime, and finally to the beta-shaped
    schedule.stopDateTime so a non-v1.0 response still converts. State is read from the assignmentState
    property when present, falling back to the state property for responses that use the alternate
    field name. Caller must request the target and accessPackage navigation properties with
    $expand=target,accessPackage or their nested fields come back empty. This private converter is the
    single owner of the assignment output shape and is used by Get-OERAccessPackageAssignment. The
    create path emits the assignment REQUEST instead and is owned by ConvertTo-OERAssignmentRequest.

    .PARAMETER InputObject
    The raw Graph accessPackageAssignment object (hashtable or PSObject) to convert.

    .EXAMPLE
    ConvertTo-OERAssignment -InputObject $assignment
    Converts a single assignment into a tagged object.

    .EXAMPLE
    $Assignments | ConvertTo-OERAssignment
    Converts each raw Graph access package assignment in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $State = if ($InputObject.assignmentState) { $InputObject.assignmentState } else { $InputObject.state }
        $Expiry = if ($InputObject.expiredDateTime) {
            $InputObject.expiredDateTime
        } elseif ($InputObject.schedule.expiration.endDateTime) {
            $InputObject.schedule.expiration.endDateTime
        } elseif ($InputObject.schedule.stopDateTime) {
            $InputObject.schedule.stopDateTime
        } else {
            $null
        }
        $TargetId = if ($InputObject.target.objectId) { $InputObject.target.objectId } else { $InputObject.target.id }
        $Out = [PSCustomObject]@{
            Id                       = $InputObject.id
            TargetId                 = $TargetId
            TargetDisplayName        = $InputObject.target.displayName
            AccessPackageId          = $InputObject.accessPackage.id
            AccessPackageDisplayName = $InputObject.accessPackage.displayName
            State                    = $State
            ExpirationDateTime       = $Expiry
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Assignment')
        $Out
    }
}
