function ConvertTo-OERGroupEligibility {
    <#
    .SYNOPSIS
    Converts a raw PIM-for-groups eligibilityScheduleInstance into a tagged Omnicit.EntraRBAC.GroupEligibilitySchedule.

    .DESCRIPTION
    Maps a beta privilegedAccessGroupEligibilityScheduleInstance (returned by
    Get-OERGroup -IncludePimEligibility) into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.GroupEligibilitySchedule so the read Format view applies. A schedule INSTANCE
    carries no action or status (those belong to schedule REQUESTS produced by
    Add/Remove-OERGroupEligibility, which are tagged Omnicit.EntraRBAC.GroupEligibility); the instance
    exposes accessId (member or owner), memberType (direct or group), and the start/end window. The
    mapped properties are GroupId, PrincipalId, AccessType (accessId), MemberType (memberType),
    StartDateTime, EndDateTime, ScheduleInstanceId (id), and EligibilityScheduleId. This private
    converter is the single owner of the read-eligibility output shape and is used by
    Get-OERGroupEligibility.

    .PARAMETER InputObject
    The raw Graph eligibilityScheduleInstance (hashtable or PSObject) to convert. Accepts pipeline input.

    .PARAMETER GroupId
    The id of the group the eligibility belongs to, stamped onto the output.

    .EXAMPLE
    ConvertTo-OERGroupEligibility -InputObject $instance -GroupId 'g1'
    Converts a single eligibility schedule instance into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$GroupId
    )
    process {
        $Out = [PSCustomObject]@{
            GroupId               = $GroupId
            PrincipalId           = $InputObject.principalId
            AccessType            = $InputObject.accessId
            MemberType            = $InputObject.memberType
            StartDateTime         = $InputObject.startDateTime
            EndDateTime           = $InputObject.endDateTime
            ScheduleInstanceId    = $InputObject.id
            EligibilityScheduleId = $InputObject.eligibilityScheduleId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupEligibilitySchedule')
        $Out
    }
}
