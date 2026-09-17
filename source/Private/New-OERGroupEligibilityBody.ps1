function New-OERGroupEligibilityBody {
    <#
    .SYNOPSIS
    Builds the request body for a PIM-for-groups eligibility schedule request.

    .DESCRIPTION
    Constructs the hashtable body POSTed to the beta privilegedAccess group eligibilityScheduleRequests
    endpoint to assign, remove, or update a principal's PIM-for-groups eligibility. -AccessType selects
    member or owner eligibility, -Action selects the admin operation (adminAssign by default), and
    -Duration produces an afterDuration schedule while its absence produces a noExpiration schedule.
    This private helper is the single owner of the eligibility-request shape used by
    Add-OERGroupEligibility and Remove-OERGroupEligibility.

    .PARAMETER GroupId
    The object id of the group whose PIM-for-groups eligibility is being changed.

    .PARAMETER PrincipalId
    The object id of the principal granted or removed from eligibility.

    .PARAMETER AccessType
    Whether the eligibility is for the member or the owner access of the group. Defaults to member.

    .PARAMETER Action
    The admin operation: adminAssign, adminRemove, adminUpdate, adminExtend, or adminRenew. Defaults to adminAssign.

    .PARAMETER Duration
    Optional ISO 8601 duration (e.g. P1Y or PT8H) for an afterDuration expiration. When omitted the
    schedule is noExpiration.

    .PARAMETER Justification
    Justification text recorded on the request. Defaults to a standard scaffolding note.

    .EXAMPLE
    New-OERGroupEligibilityBody -GroupId $GroupId -PrincipalId $UserId -Duration 'P1Y'
    Returns an adminAssign member-eligibility body expiring after one year.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory request-body builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [string]$PrincipalId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [ValidateSet('adminAssign', 'adminRemove', 'adminUpdate', 'adminExtend', 'adminRenew')]
        [string]$Action = 'adminAssign',

        # Same ISO 8601 duration pattern Resolve-OERDurationInput validates against, so a raw
        # -Duration 'PT8H' (audit PR6) survives the round trip instead of being rejected here.
        [ValidatePattern('^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$')]
        [string]$Duration,

        [string]$Justification = 'Omnicit.EntraRBAC: PIM-for-groups eligible assignment'
    )

    $Expiration = if ($Duration) {
        @{ type = 'afterDuration'; duration = $Duration }
    } else {
        @{ type = 'noExpiration' }
    }

    @{
        accessId      = $AccessType
        principalId   = $PrincipalId
        groupId       = $GroupId
        action        = $Action
        justification = $Justification
        scheduleInfo  = @{
            startDateTime = [DateTime]::UtcNow.ToString('o')
            expiration    = $Expiration
        }
    }
}
