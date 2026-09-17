function ConvertTo-OERDuration {
    <#
    .SYNOPSIS
    Converts a whole number of days or hours into an ISO 8601 duration string (e.g. 365 -> 'P365D',
    8 -> 'PT8H').

    .DESCRIPTION
    Public OER cmdlets express assignment lifetimes in days, and activation windows in hours, because
    that is more intuitive than ISO 8601 durations, while the Microsoft Graph and Azure PIM APIs require
    an ISO 8601 duration. This private helper is the single owner of that whole-unit conversion: with
    -Days it turns an integer day count into a 'P{n}D' duration, and with -Hours an integer hour count
    into a 'PT{n}H' duration, using System.Xml.XmlConvert over a TimeSpan -- the module's standard ISO
    8601 duration mechanism. Emitting whole-day durations ('P365D' rather than 'P1Y') also avoids the
    Graph PIM validation that rejects 'P1Y' against a 365-day policy maximum.

    .PARAMETER Days
    The number of days to convert. Must be a positive integer. Produces a 'P{n}D' duration.

    .PARAMETER Hours
    The number of hours to convert. Must be a positive integer. Produces a 'PT{n}H' duration.

    .EXAMPLE
    ConvertTo-OERDuration -Days 365
    Returns 'P365D'.

    .EXAMPLE
    ConvertTo-OERDuration -Hours 8
    Returns 'PT8H'.
    #>
    [OutputType([string])]
    [CmdletBinding(DefaultParameterSetName = 'Days')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Days')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Days,

        [Parameter(Mandatory, ParameterSetName = 'Hours')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Hours
    )
    if ($PSCmdlet.ParameterSetName -eq 'Hours') {
        [System.Xml.XmlConvert]::ToString([timespan]::FromHours($Hours))
    }
    else {
        [System.Xml.XmlConvert]::ToString([timespan]::FromDays($Days))
    }
}
