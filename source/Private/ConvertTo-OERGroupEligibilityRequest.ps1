function ConvertTo-OERGroupEligibilityRequest {
    <#
    .SYNOPSIS
    Converts a PIM-for-groups eligibilityScheduleRequest response into a tagged
    Omnicit.EntraRBAC.GroupEligibility object.

    .DESCRIPTION
    Maps the privilegedAccessGroupEligibilityScheduleRequest returned by POST
    identityGovernance/privilegedAccess/group/eligibilityScheduleRequests into a [PSCustomObject]
    tagged Omnicit.EntraRBAC.GroupEligibility so the Format view applies. The response carries only the
    request id and status, so the group, principal, access type and action are stamped on by the caller
    that just sent them. This private converter is the single owner of the eligibility REQUEST shape
    and is used by Add-OERGroupEligibility and Remove-OERGroupEligibility; the read-side schedule
    INSTANCE shape is a different type owned by ConvertTo-OERGroupEligibility.

    .PARAMETER InputObject
    The raw Graph eligibilityScheduleRequest response (hashtable or PSObject). Accepts pipeline input.

    .PARAMETER GroupId
    The object id of the group the eligibility request was submitted against, stamped onto the output.

    .PARAMETER PrincipalId
    The object id of the principal the eligibility was granted to or revoked from, stamped on output.

    .PARAMETER AccessType
    The PIM access type the request applies to, either member or owner, stamped onto the output.

    .PARAMETER Action
    The request action that was submitted, for example adminAssign or adminRemove, stamped on output.

    .EXAMPLE
    ConvertTo-OERGroupEligibilityRequest -InputObject $Response -GroupId $Gid -PrincipalId $Pid -AccessType member -Action adminAssign
    Returns the tagged eligibility request object for a freshly submitted grant.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$GroupId,

        [string]$PrincipalId,

        [string]$AccessType,

        [string]$Action
    )
    process {
        $Out = [PSCustomObject]@{
            RequestId   = $InputObject.id
            GroupId     = $GroupId
            PrincipalId = $PrincipalId
            AccessType  = $AccessType
            Action      = $Action
            Status      = $InputObject.status
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupEligibility')
        $Out
    }
}
