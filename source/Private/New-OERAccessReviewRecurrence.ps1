function New-OERAccessReviewRecurrence {
    <#
    .SYNOPSIS
    Builds the patternedRecurrence object for an access review schedule definition.

    .DESCRIPTION
    Maps a friendly recurrence cadence and start/end window to the v1.0 patternedRecurrence shape.
    OneTime returns nothing (the caller omits the recurrence key, producing a single review instance).
    Weekly emits a weekly pattern; Monthly, Quarterly and Annually emit an absoluteMonthly pattern with
    interval 1, 3 and 12 respectively and a dayOfMonth taken from the start date. The range is noEnd by
    default, endDate when -EndDate is supplied, or numbered when -Occurrences is supplied. Dates are
    emitted as invariant yyyy-MM-dd strings. This is a pure builder and makes no Graph call.

    .PARAMETER Recurrence
    The cadence: OneTime, Weekly, Monthly, Quarterly, or Annually.

    .PARAMETER StartDate
    The date the first review instance starts. Also supplies dayOfMonth for monthly cadences.

    .PARAMETER EndDate
    Optional end date; produces an endDate range. Mutually exclusive with -Occurrences.

    .PARAMETER Occurrences
    Optional number of occurrences; produces a numbered range. Mutually exclusive with -EndDate.

    .EXAMPLE
    New-OERAccessReviewRecurrence -Recurrence Quarterly -StartDate (Get-Date)
    Builds a quarterly, never-ending recurrence starting today.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')]
        [string]$Recurrence,
        [Parameter(Mandatory)][datetime]$StartDate,
        [datetime]$EndDate,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Occurrences
    )
    if ($PSBoundParameters.ContainsKey('EndDate') -and $PSBoundParameters.ContainsKey('Occurrences')) {
        throw 'New-OERAccessReviewRecurrence: -EndDate and -Occurrences are mutually exclusive.'
    }
    if ($Recurrence -eq 'OneTime') { return }

    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $Pattern = if ($Recurrence -eq 'Weekly') {
        [ordered]@{ type = 'weekly'; interval = 1 }
    }
    else {
        $Interval = switch ($Recurrence) { 'Monthly' { 1 } 'Quarterly' { 3 } 'Annually' { 12 } }
        [ordered]@{ type = 'absoluteMonthly'; interval = $Interval; dayOfMonth = $StartDate.Day }
    }

    $Range = [ordered]@{ startDate = $StartDate.ToString('yyyy-MM-dd', $Invariant) }
    if ($PSBoundParameters.ContainsKey('EndDate')) {
        $Range.type = 'endDate'
        $Range.endDate = $EndDate.ToString('yyyy-MM-dd', $Invariant)
    }
    elseif ($PSBoundParameters.ContainsKey('Occurrences')) {
        $Range.type = 'numbered'
        $Range.numberOfOccurrences = $Occurrences
    }
    else {
        $Range.type = 'noEnd'
    }

    return @{ pattern = $Pattern; range = $Range }
}
