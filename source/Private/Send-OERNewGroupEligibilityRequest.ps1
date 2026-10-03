function Send-OERNewGroupEligibilityRequest {
    <#
    .SYNOPSIS
    Sends a time-bound PIM-for-groups eligibility request for a group created in the same run, reporting
    a 404 as not known yet.

    .DESCRIPTION
    POSTs the eligibility schedule request that Add-OERGroupEligibility sends for a time-bound grant --
    the body comes from New-OERGroupEligibilityBody, the single owner of that shape, and the duration
    from ConvertTo-OERDuration -- and returns Microsoft Graph's response. For the apply engine's wait on
    a group created in the same run ONLY: right after a group is created, PIM for Groups can answer the
    first eligibility request with 404 ResourceNotFound while the group's replicas do not agree yet,
    and for such a group that is replication, not a failed write. ResourceNotFound is therefore declared
    to the transport at the REQUEST, so a 404 comes back as $null and leaves no record in the caller's
    -ErrorVariable. That is the whole reason this helper exists beside the cmdlet: a 404 thrown and then
    caught would still hand the caller its records, since -ErrorVariable is filled as the record is
    raised, before any catch runs (measured in plain PowerShell: a caught throw two frames down left
    three records in the outer variable). Add-OERGroupEligibility cannot declare the code without a
    new public parameter, so a time-bound write on a new group goes through this helper instead; a
    group that already existed keeps the cmdlet, and a 404 there stays a failure.
    The same code with any status other than 404 is thrown, and so is every other failure -- a refusal
    (403), a throttle that outlasted the transport's own retries, or a server error -- for the caller
    to handle as a refusal. This helper never waits and never retries; the caller owns the budget.

    .PARAMETER GroupId
    The object id of the group the eligibility is requested for.

    .PARAMETER PrincipalId
    The object id of the principal that becomes eligible.

    .PARAMETER DurationDays
    The lifetime of the eligibility in whole days (1-3650), converted to an ISO 8601 duration by
    ConvertTo-OERDuration.

    .PARAMETER AccessType
    Whether the eligibility is for the member or the owner access of the group. Defaults to member.

    .PARAMETER Action
    The Microsoft Graph admin operation: adminAssign (the default) for an absent eligibility,
    adminUpdate for one that already exists.

    .EXAMPLE
    Send-OERNewGroupEligibilityRequest -GroupId $Gid -PrincipalId $PrincipalId -DurationDays 365
    Requests a 365-day member eligibility and returns the response, or $null while Microsoft Graph
    answers 404 ResourceNotFound for the group.
    #>
    [OutputType([object])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter(Mandatory)]
        [ValidateRange(1, 3650)]
        [int]$DurationDays,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [ValidateSet('adminAssign', 'adminUpdate')]
        [string]$Action = 'adminAssign'
    )
    $Body = New-OERGroupEligibilityBody -GroupId $GroupId -PrincipalId $PrincipalId -AccessType $AccessType `
        -Action $Action -Duration (ConvertTo-OERDuration -Days $DurationDays)
    $Uri = Get-OERPimGroupsGraphPath -Path 'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests'
    # Declared at the REQUEST, as in Get-OERListedGroupPimPolicy: a caught throw would still hand the
    # caller its records, since -ErrorVariable is filled before any catch runs.
    $Response = Invoke-OERGraphRequest -Method POST -Uri $Uri -Body $Body -ExpectedErrorCode 'ResourceNotFound'
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        # Only a 404 is "not known yet"; Graph's code without that status stays a failure.
        if (($Response.StatusCode -as [int]) -ne 404) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new([string]$Response.Message),
                'ResourceNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $GroupId)
        }
        Write-Verbose "[Send-OERNewGroupEligibilityRequest] Microsoft Graph answered 404 ResourceNotFound for an eligibility request on group '$GroupId'; reporting it as not known yet."
        return $null
    }
    $Response
}
