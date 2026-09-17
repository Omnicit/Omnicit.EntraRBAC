function Resolve-OEREligibilityDuration {
    <#
    .SYNOPSIS
    Reconstructs the declared duration in whole days from a PIM-for-groups eligibility schedule window.

    .DESCRIPTION
    Pure, tenant-free inverse of the day-count that Add-OERGroupEligibility -Duration writes: given the
    startDateTime and endDateTime of a privilegedAccessGroupEligibilityScheduleInstance, it returns the
    length of the declared window in whole days so Get-OERInventory can round-trip a time-bound
    eligibility. A permanent eligibility has no meaningful end -- Graph reports it as a null/empty
    endDateTime or as a far-future sentinel in year 9999 -- and yields $null. The result is clamped into
    the apply-schema range of 1 to 3650 days, so an oversized live window is reported as the maximum
    time-bound value rather than silently degrading to permanent. When startDateTime is absent or
    unparsable the window is measured from the current UTC time instead. No Graph, ARM, or
    authentication occurs.

    .PARAMETER StartDateTime
    The schedule instance start, as a string, DateTime, or DateTimeOffset. When it is absent or cannot
    be parsed, the current UTC time is used as the window start instead.

    .PARAMETER EndDateTime
    The schedule instance end, as a string, DateTime, or DateTimeOffset. A null, empty, unparsable, or
    year-9999 value means the eligibility is permanent and the function returns $null.

    .EXAMPLE
    Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T09:00:00Z' -EndDateTime '2026-01-31T09:00:00Z'
    Returns 30, the declared duration in whole days of that time-bound eligibility window.

    .EXAMPLE
    Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T09:00:00Z' -EndDateTime $null
    Returns $null because a missing end date marks the eligibility as permanent.
    #>
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [object]$StartDateTime,
        [object]$EndDateTime
    )

    if ($null -eq $EndDateTime -or [string]::IsNullOrWhiteSpace([string]$EndDateTime)) { return $null }

    $End = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$EndDateTime, [ref]$End)) { return $null }
    if ($End.UtcDateTime.Year -ge 9999) { return $null }

    $Start = [datetimeoffset]::UtcNow
    if ($null -ne $StartDateTime -and -not [string]::IsNullOrWhiteSpace([string]$StartDateTime)) {
        $Parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse([string]$StartDateTime, [ref]$Parsed)) { $Start = $Parsed }
    }

    $Days = [int][math]::Round(($End - $Start).TotalDays, [System.MidpointRounding]::AwayFromZero)
    if ($Days -lt 1) { return 1 }
    if ($Days -gt 3650) { return 3650 }
    $Days
}
