function New-OERDirectoryRoleScheduleRequestBody {
    <#
    .SYNOPSIS
    Builds the request body for a Microsoft Entra directory role eligibility or assignment schedule
    request.

    .DESCRIPTION
    Constructs the hashtable body POSTed to the Microsoft Graph v1.0
    roleManagement/directory/roleEligibilityScheduleRequests or roleAssignmentScheduleRequests
    endpoint to grant, remove, or update a principal's directory role eligibility or active
    assignment. -Action selects the admin operation (adminAssign by default); -Duration produces an
    afterDuration schedule, -EndDateTime an afterDateTime schedule, and neither of them a
    noExpiration schedule. An adminRemove request carries no scheduleInfo at all, since Microsoft
    Graph rejects a removal that supplies one. directoryScopeId is always '/' (tenant scope), the
    only scope these schedule requests support. This private helper is the single owner of the
    request-body shape used by New-/Remove-OEREligibleDirectoryRoleAssignment and
    New-/Remove-OERActiveDirectoryRoleAssignment.

    .PARAMETER Action
    The Microsoft Graph admin operation: adminAssign (create), adminUpdate (change an existing
    schedule), or adminRemove (revoke).

    .PARAMETER PrincipalId
    The object id of the principal the schedule request targets.

    .PARAMETER RoleDefinitionId
    The Microsoft Entra directory role definition id.

    .PARAMETER Duration
    Optional ISO 8601 duration (e.g. 'P30D') for an afterDuration expiration. Mutually exclusive with
    -EndDateTime.

    .PARAMETER EndDateTime
    Optional absolute end time for an afterDateTime expiration. Mutually exclusive with -Duration.

    .PARAMETER Justification
    Justification text recorded on the request.

    .PARAMETER TicketNumber
    Optional ticket number recorded on the request.

    .PARAMETER TicketSystem
    Optional ticket system name recorded on the request.

    .EXAMPLE
    New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId $PrincipalId -RoleDefinitionId $RoleDefinitionId -Duration 'P30D' -Justification 'Onboarding'
    Returns an adminAssign body with a 30-day afterDuration expiration.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory request-body builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('adminAssign', 'adminUpdate', 'adminRemove')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [Parameter(Mandatory)]
        [string]$RoleDefinitionId,

        [ValidatePattern('^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$')]
        [string]$Duration,

        [datetime]$EndDateTime,

        [Parameter(Mandatory)]
        [string]$Justification,

        [string]$TicketNumber,
        [string]$TicketSystem
    )
    if ($Duration -and $PSBoundParameters.ContainsKey('EndDateTime')) {
        throw 'Supply either -Duration or -EndDateTime, not both.'
    }
    $Body = @{
        action           = $Action
        principalId      = $PrincipalId
        roleDefinitionId = $RoleDefinitionId
        directoryScopeId = '/'
        justification    = $Justification
    }
    if ($Action -ne 'adminRemove') {
        $Expiration = if ($Duration) {
            @{ type = 'afterDuration'; duration = $Duration }
        } elseif ($PSBoundParameters.ContainsKey('EndDateTime')) {
            @{ type = 'afterDateTime'; endDateTime = $EndDateTime.ToUniversalTime().ToString('o') }
        } else {
            @{ type = 'noExpiration' }
        }
        $Body.scheduleInfo = @{
            startDateTime = [DateTime]::UtcNow.ToString('o')
            expiration    = $Expiration
        }
    }
    if ($TicketNumber -or $TicketSystem) {
        $Body.ticketInfo = @{ ticketNumber = $TicketNumber; ticketSystem = $TicketSystem }
    }
    $Body
}
