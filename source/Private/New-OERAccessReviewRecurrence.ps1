function New-OERAccessReviewRecurrence {
    <#
    .SYNOPSIS
    Builds the patternedRecurrence object for an access review schedule definition.

    .DESCRIPTION
    Maps a friendly recurrence cadence and start/end window to the v1.0 patternedRecurrence shape.
    OneTime returns the one-time form Microsoft Graph stores unchanged: a null pattern and a numbered
    range of zero occurrences that starts on -StartDate and ends -DurationInDays days later (Graph
    reads the length of a one-time review from that range, not from instanceDurationInDays);
    -DurationInDays is required for it, and -EndDate and -Occurrences are ignored.
    Weekly emits a weekly pattern; Monthly, Quarterly, SemiAnnually and Annually emit an
    absoluteMonthly pattern with interval 1, 3, 6 and 12 respectively and a dayOfMonth taken from the
    start date. The pattern type and interval of each cadence are read from Get-OERAccessReviewCadence,
    the single owner of that table. The range is noEnd by default, endDate when -EndDate is supplied,
    or numbered when -Occurrences is supplied. Dates are emitted as invariant yyyy-MM-dd strings. This
    is a pure builder and makes no Graph call.

    .PARAMETER Recurrence
    The cadence: OneTime, Weekly, Monthly, Quarterly, SemiAnnually, or Annually.

    .PARAMETER StartDate
    The date the first review instance starts. Also supplies dayOfMonth for monthly cadences.

    .PARAMETER EndDate
    Optional end date; produces an endDate range. Mutually exclusive with -Occurrences.

    .PARAMETER Occurrences
    Optional number of occurrences; produces a numbered range. Mutually exclusive with -EndDate.

    .PARAMETER DurationInDays
    The length in days of a one-time review; required for OneTime, ignored by the repeating cadences.

    .EXAMPLE
    New-OERAccessReviewRecurrence -Recurrence Quarterly -StartDate (Get-Date)
    Builds a quarterly, never-ending recurrence starting today.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'SemiAnnually', 'Annually')]
        [string]$Recurrence,
        [Parameter(Mandatory)][datetime]$StartDate,
        [datetime]$EndDate,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Occurrences,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DurationInDays
    )
    if ($PSBoundParameters.ContainsKey('EndDate') -and $PSBoundParameters.ContainsKey('Occurrences')) {
        throw 'New-OERAccessReviewRecurrence: -EndDate and -Occurrences are mutually exclusive.'
    }

    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Recurrence -eq 'OneTime') {
        if (-not $PSBoundParameters.ContainsKey('DurationInDays')) {
            throw 'New-OERAccessReviewRecurrence: -DurationInDays is required for OneTime.'
        }
        # The measured Learn form: Graph reads the length of a one-time review from the range, so the
        # range ends -DurationInDays days after the start. A null pattern with a numbered range of
        # zero occurrences is what Graph stores back unchanged.
        return @{
            pattern = $null
            range   = [ordered]@{
                type                = 'numbered'
                numberOfOccurrences = 0
                recurrenceTimeZone  = $null
                startDate           = $StartDate.ToString('yyyy-MM-dd', $Invariant)
                endDate             = $StartDate.AddDays($DurationInDays).ToString('yyyy-MM-dd', $Invariant)
            }
        }
    }

    # The cadence's pattern type and interval come from the single owner of the cadence table; the
    # day of the month belongs to the monthly pattern only.
    $Shape = Get-OERAccessReviewCadence -Cadence $Recurrence
    $Pattern = [ordered]@{ type = $Shape.PatternType; interval = $Shape.Interval }
    if ($Shape.PatternType -ieq 'absoluteMonthly') { $Pattern.dayOfMonth = $StartDate.Day }

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
