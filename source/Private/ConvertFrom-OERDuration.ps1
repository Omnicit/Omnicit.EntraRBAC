function ConvertFrom-OERDuration {
    <#
    .SYNOPSIS
    Parses an ISO 8601 duration string into a whole number of days or hours, or $null.

    .DESCRIPTION
    The read-side mirror of ConvertTo-OERDuration and the single owner of that direction of the
    conversion: ConvertTo-OERDuration is the sole owner of encoding a whole day/hour count into an ISO
    8601 duration, and this helper is the sole owner of parsing one back. It parses ANY ISO 8601
    duration -- not just the whole-day/whole-hour forms this module itself emits -- via
    [System.Xml.XmlConvert]::ToTimeSpan(), so a value written by the Entra portal or another tool
    (for example P1Y, P6M, PT30M, or P1DT12H) is read correctly instead of silently becoming $null under
    an anchored single-unit regex (^P(\d+)D$ or ^PT(\d+)H$). Returns $null when -Duration is empty or
    whitespace, is not a syntactically valid ISO 8601 duration, or does not amount to a WHOLE number of
    the requested -Unit -- a fractional unit (for example PT30M read as hours) is reported as unknown
    rather than silently truncated, because every caller (ConvertTo-OERGroupPimPolicy,
    ConvertTo-OERRoleManagementPolicy, Set-OERGroupPimPolicy) treats $null as "not configured / cannot
    be compared", never as zero. Per the .NET implementation of the ISO 8601 duration grammar that
    XmlConvert.ToTimeSpan follows, a year is exactly 365 days and a month is exactly 30 days.

    .PARAMETER Duration
    The ISO 8601 duration string to parse, for example 'P365D', 'PT8H', 'P1Y', or 'P1DT12H'. $null or an
    empty or whitespace-only string returns $null rather than throwing.

    .PARAMETER Unit
    Which unit to report the parsed duration as, Days or Hours. The duration must amount to a whole
    number of this unit, or $null is returned instead of a truncated value.

    .EXAMPLE
    ConvertFrom-OERDuration -Duration 'P365D' -Unit Days
    Returns 365.

    .EXAMPLE
    ConvertFrom-OERDuration -Duration 'P1Y' -Unit Days
    Returns 365, because XmlConvert.ToTimeSpan treats a year as 365 days.

    .EXAMPLE
    ConvertFrom-OERDuration -Duration 'PT30M' -Unit Hours
    Returns $null, because 30 minutes is not a whole number of hours.
    #>
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Duration,

        [Parameter(Mandatory)]
        [ValidateSet('Days', 'Hours')]
        [string]$Unit
    )
    if ([string]::IsNullOrWhiteSpace($Duration)) { return $null }

    try {
        $Span = [System.Xml.XmlConvert]::ToTimeSpan($Duration)
    } catch {
        # A value written by another tool need not be an ISO 8601 duration at all. Report "unknown"
        # rather than throwing: every caller treats $null as "not configured / cannot be compared". This
        # wraps a pure in-memory parse (no Graph or ARM request), so there is no bearer-carrying record
        # to scrub with Remove-OERErrorRecord -- that call is mandatory only in a Graph/ARM catch block.
        return $null
    }

    $Total = if ($Unit -eq 'Hours') { $Span.TotalHours } else { $Span.TotalDays }
    if ($Total -le 0 -or [Math]::Floor($Total) -ne $Total) { return $null }
    [int]$Total
}
