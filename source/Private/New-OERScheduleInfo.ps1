function New-OERScheduleInfo {
    <#
    .SYNOPSIS
    Builds the scheduleInfo block (startDateTime + expiration) for an Azure PIM schedule request.

    .DESCRIPTION
    The single owner of the ARM scheduleInfo/expiration shape used by the Azure PIM cmdlets. At most
    one of -Duration, -EndDateTime, or -Permanent may be supplied. -Duration produces an
    'AfterDuration' expiration, -EndDateTime an 'AfterDateTime' expiration, and -Permanent (or
    supplying none) a 'NoExpiration' expiration. The expiration 'type' values are the PascalCase ARM
    values (AfterDuration/AfterDateTime/NoExpiration), distinct from the camelCase Graph values used
    by PIM-for-groups. Throws on conflicting input -- callers catch and route the message.

    .PARAMETER Duration
    ISO 8601 duration (e.g. 'PT8H', 'P365D') for an AfterDuration expiration.

    .PARAMETER EndDateTime
    Absolute end time for an AfterDateTime expiration; serialized as ISO 8601 UTC.

    .PARAMETER Permanent
    Produce a NoExpiration (permanent) schedule.

    .PARAMETER StartDateTime
    Start time of the schedule; defaults to the current UTC time.

    .EXAMPLE
    New-OERScheduleInfo -Duration 'PT8H'
    Returns a scheduleInfo whose expiration is AfterDuration PT8H starting now.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory builder; returns a hashtable and performs no state change.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [ValidatePattern('^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$')]
        [string]$Duration,

        [datetime]$EndDateTime,

        [switch]$Permanent,

        [datetime]$StartDateTime = [datetime]::UtcNow
    )

    $Supplied = @()
    if ($Duration) { $Supplied += '-Duration' }
    if ($PSBoundParameters.ContainsKey('EndDateTime')) { $Supplied += '-EndDateTime' }
    if ($Permanent) { $Supplied += '-Permanent' }
    if ($Supplied.Count -gt 1) {
        throw "Supply at most one of -Duration, -EndDateTime or -Permanent (got: $($Supplied -join ', '))."
    }

    $Expiration = if ($Duration) {
        @{ type = 'AfterDuration'; duration = $Duration }
    } elseif ($PSBoundParameters.ContainsKey('EndDateTime')) {
        @{ type = 'AfterDateTime'; endDateTime = $EndDateTime.ToUniversalTime().ToString('o') }
    } else {
        @{ type = 'NoExpiration' }
    }

    @{
        startDateTime = $StartDateTime.ToUniversalTime().ToString('o')
        expiration    = $Expiration
    }
}
