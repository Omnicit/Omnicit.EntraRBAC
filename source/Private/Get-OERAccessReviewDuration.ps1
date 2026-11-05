function Get-OERAccessReviewDuration {
    <#
    .SYNOPSIS
    Returns the length in days that Microsoft Graph uses for an access review instance.

    .DESCRIPTION
    The single owner of the length of an access review instance, read from a definition's settings.
    A one-time review (settings.recurrence present with a null or absent pattern) is governed by its
    recurrence range, not by instanceDurationInDays: the instance ends on range.endDate, and Graph
    stores instanceDurationInDays 0 for the older shape the module used to write (a noEnd range
    thirty days long). For such a review the length is the whole days from range.startDate to
    range.endDate, provided both read as dates and the end is not before the start. In every other
    case -- a repeating review, a one-time review whose range cannot be read, no recurrence at all --
    the length is instanceDurationInDays, or $null when that is absent or not a whole number.
    The settings are read dictionary-safely: a raw Graph dictionary and a PSCustomObject fixture both
    work. A date is a datetime, an invariant yyyy-MM-dd string, or any string an invariant parse
    reads. Pure: makes no Graph call.

    .PARAMETER Settings
    The settings object of an access review definition (a raw Graph dictionary or a PSCustomObject),
    or $null.

    .EXAMPLE
    Get-OERAccessReviewDuration -Settings $Current.settings
    Returns 14 for a one-time review whose range runs from 2026-11-12 to 2026-11-26.
    #>
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Settings
    )

    function Get-DurationValue {
        param([object]$Bag, [string]$Key)
        if ($null -eq $Bag) { return $null }
        # Keys, not Contains or ContainsKey: a generic Dictionary[string, object] has a Contains that
        # takes a KeyValuePair, and an [ordered] dictionary (OrderedDictionary) has no ContainsKey.
        if ($Bag -is [System.Collections.IDictionary]) {
            if (@($Bag.Keys) -contains $Key) { return $Bag[$Key] }
            return $null
        }
        $Property = $Bag.PSObject.Properties[$Key]
        if ($Property) { return $Property.Value }
        return $null
    }

    function ConvertTo-DurationDate {
        param([object]$Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [datetime]) { return $Value }
        if ($Value -is [string]) {
            $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
            $Parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact($Value, 'yyyy-MM-dd', $Invariant, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
                return $Parsed
            }
            if ([datetime]::TryParse($Value, $Invariant, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$Parsed)) {
                return $Parsed
            }
        }
        return $null
    }

    if ($null -eq $Settings) { return $null }

    $Recurrence = Get-DurationValue -Bag $Settings -Key 'recurrence'
    if ($null -ne $Recurrence -and $null -eq (Get-DurationValue -Bag $Recurrence -Key 'pattern')) {
        $Range = Get-DurationValue -Bag $Recurrence -Key 'range'
        $Start = ConvertTo-DurationDate -Value (Get-DurationValue -Bag $Range -Key 'startDate')
        $End   = ConvertTo-DurationDate -Value (Get-DurationValue -Bag $Range -Key 'endDate')
        if ($null -ne $Start -and $null -ne $End -and $End.Date -ge $Start.Date) {
            return [int]($End.Date - $Start.Date).Days
        }
    }

    $Duration = Get-DurationValue -Bag $Settings -Key 'instanceDurationInDays'
    if ($null -eq $Duration) { return $null }
    $Number = $Duration -as [int]
    if ($null -eq $Number) { return $null }
    return $Number
}
