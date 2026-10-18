function Test-OERNamingStandardName {
    <#
    .SYNOPSIS
    Checks one object name against a naming standard and returns one finding per broken rule.

    .DESCRIPTION
    The single owner of what "follows the naming standard" means. Pure: no I/O, no error record, no
    request, and it never throws for any string, whatever characters the name holds. Standard is the
    object Read-OERNamingStandard returns. The result is zero or more objects with Rule, Segment (the
    1-based position of the segment, or $null), SegmentName (or $null) and Detail (one sentence, written
    to stand after "does not follow the naming standard (rule ...):"). Zero objects means the name
    follows the standard or matches an exception.

    Rule is one of maxLength, separator, segmentCount, values, pattern and case. The checks run in this
    order, and the results come in the order they are found:
      1. A name that matches an exception is never checked: nothing is returned.
      2. maxLength: the name is longer than the standard's MaxLength (the check continues).
         Detail: it is 65 characters long; the standard allows at most 64.
      3. The name is split at the separator, as text (String.Split with the separator string, no
         options), into its parts.
      4. separator, when any part is empty (the name starts or ends with the separator, or holds it
         twice in a row), and the check stops.
         Detail: a segment is empty: the name starts or ends with the separator '-' or holds it twice
         in a row; the standard expects the segments kind, area, purpose, environment (optional),
         separated by '-'.
      5. With R required segments, T segments and n parts: separator when n is 1 and R is 2 or more
         (Detail: it does not contain the separator '-'; the standard expects at least 3 segments:
         kind, area, purpose, environment (optional), separated by '-'.), otherwise segmentCount when n
         is below R (Detail: it has 2 segments when split at '-', and the standard requires at least 3:
         kind, area, purpose, environment (optional), separated by '-'.) or above T (Detail: it has 5
         segments when split at '-', and the standard allows at most 4: kind, area, purpose,
         environment (optional), separated by '-'.). The check stops at any of these.
      6. The parts are assigned to the segments in order. Every required segment takes the next part.
         Exactly n minus R optional segments are present, so an optional segment is skipped when none
         of them is left to place, takes the next part when as many optional segments are left (from
         this one to the end) as are still to be placed, and otherwise takes it when the part fits the
         segment (it is one of its values or matches its pattern, or the segment names neither, and it
         has the segment's letter case, or the segment names none) and is skipped when it does not.
      7. For each segment that was assigned a part, in segment order: values when the segment has a
         list of values and the part is not one of them, otherwise pattern when it has a pattern and
         the part does not match; then, independently, case when it has a letter case and the part
         does not have it.
         Details: 'Legal' is not one of the allowed values 'Finance', 'Sales', 'IT'. -- with
         " (it differs from 'Finance' only in letter case)" before the full stop when a value differs
         from the part in letter case alone; 'Finance' does not match the pattern 'Fin' (the whole
         segment must match). -- and 'readers' is not PascalCase (an uppercase letter first, then only
         letters and digits). -- where the words in brackets are, for the other cases, "a lowercase
         letter first, then only letters and digits" (camelCase), "no lowercase letter" (UPPERCASE) and
         "no uppercase letter" (lowercase).

    The matching semantics, the reference list the schema, the about topic and the README repeat:
      - A pattern (a segment's pattern, an exceptions entry) matches the WHOLE text: it was compiled by
        Read-OERNamingStandard as \A(?:pattern)\z with RegexOptions.CultureInvariant, and it is
        case-sensitive unless it carries (?i). "Fin" does not match "Finance", and the exception
        "All Users" does not exempt "All Users Copy".
      - Values are compared ordinally: exact and case-sensitive, never as patterns, so "C++" and "A.B"
        mean what they say, and a hidden character is a difference.
      - PascalCase is an uppercase letter first and then only letters and digits
        (\A\p{Lu}[\p{L}\p{Nd}]*\z); camelCase a lowercase letter first and then only letters and digits
        (\A\p{Ll}[\p{L}\p{Nd}]*\z); UPPERCASE has no lowercase letter (\A\P{Ll}*\z); lowercase has no
        uppercase letter (\A\P{Lu}*\z). Letters are Unicode letters, so an A with a ring above counts.

    .PARAMETER Name
    The name to check. An empty string is allowed and is reported as an empty segment.

    .PARAMETER Standard
    The naming standard, as returned by Read-OERNamingStandard.

    .EXAMPLE
    Test-OERNamingStandardName -Name 'SG_Finance_Readers' -Standard (Read-OERNamingStandard -Path ./naming-standard.json)
    Returns one separator finding: the name does not contain the separator the standard expects.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][PSCustomObject]$Standard
    )

    function ConvertTo-NameFinding {
        param([string]$Rule, [object]$Segment, [string]$Detail)
        [PSCustomObject]@{
            Rule        = $Rule
            Segment     = if ($null -ne $Segment) { $Segment.Position } else { $null }
            SegmentName = if ($null -ne $Segment) { $Segment.Name } else { $null }
            Detail      = $Detail
        }
    }

    # The letter case rules, with the words a finding uses. The regular expressions are the reference
    # list in this function's help; the static IsMatch overload keeps them in the regex cache.
    $CaseRule = @{
        PascalCase = @{ Pattern = '\A\p{Lu}[\p{L}\p{Nd}]*\z'; Words = 'an uppercase letter first, then only letters and digits' }
        camelCase  = @{ Pattern = '\A\p{Ll}[\p{L}\p{Nd}]*\z'; Words = 'a lowercase letter first, then only letters and digits' }
        UPPERCASE  = @{ Pattern = '\A\P{Ll}*\z'; Words = 'no lowercase letter' }
        lowercase  = @{ Pattern = '\A\P{Lu}*\z'; Words = 'no uppercase letter' }
    }

    function Test-CaseRule {
        param([string]$Part, [string]$Case)
        [regex]::IsMatch($Part, $CaseRule[$Case].Pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }

    # Whether the part is one of the segment's values (ordinal, so neither case nor a hidden character
    # is ignored), or matches its pattern, or the segment names neither.
    function Test-ValueRule {
        param([string]$Part, [object]$Segment)
        if ($null -ne $Segment.Values) { return ([System.Array]::IndexOf([string[]]$Segment.Values, $Part) -ge 0) }
        if ($null -ne $Segment.Regex) { return $Segment.Regex.IsMatch($Part) }
        $true
    }

    function Test-SegmentFit {
        param([string]$Part, [object]$Segment)
        if (-not (Test-ValueRule -Part $Part -Segment $Segment)) { return $false }
        if ($null -ne $Segment.Case -and -not (Test-CaseRule -Part $Part -Case $Segment.Case)) { return $false }
        $true
    }

    $Segments = @($Standard.Segments)
    $SegmentList = (@($Segments | ForEach-Object { if ($_.Optional) { "$($_.Name) (optional)" } else { $_.Name } })) -join ', '
    $Separator = $Standard.Separator

    # 1. An exception exempts the name from every other rule.
    foreach ($Exception in @($Standard.Exceptions)) {
        if ($Exception.Regex.IsMatch($Name)) { return }
    }

    # 2. The length.
    if ($null -ne $Standard.MaxLength -and $Name.Length -gt $Standard.MaxLength) {
        ConvertTo-NameFinding -Rule 'maxLength' -Detail "it is $($Name.Length) characters long; the standard allows at most $($Standard.MaxLength)."
    }

    # 3. The split, at the separator as text.
    $Parts = $Name.Split([string[]]@($Separator), [System.StringSplitOptions]::None)

    # 4. An empty part.
    if (@($Parts | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
        ConvertTo-NameFinding -Rule 'separator' -Detail ("a segment is empty: the name starts or ends with the separator '$Separator' or holds it twice in a row; " +
            "the standard expects the segments $SegmentList, separated by '$Separator'.")
        return
    }

    # 5. The count.
    $Required = @($Segments | Where-Object { -not $_.Optional }).Count
    $Total = $Segments.Count
    $Count = $Parts.Count
    if ($Count -eq 1 -and $Required -ge 2) {
        ConvertTo-NameFinding -Rule 'separator' -Detail ("it does not contain the separator '$Separator'; the standard expects at least $Required segments: " +
            "$SegmentList, separated by '$Separator'.")
        return
    }
    if ($Count -lt $Required) {
        ConvertTo-NameFinding -Rule 'segmentCount' -Detail ("it has $Count segments when split at '$Separator', and the standard requires at least $($Required): " +
            "$SegmentList, separated by '$Separator'.")
        return
    }
    if ($Count -gt $Total) {
        ConvertTo-NameFinding -Rule 'segmentCount' -Detail ("it has $Count segments when split at '$Separator', and the standard allows at most $($Total): " +
            "$SegmentList, separated by '$Separator'.")
        return
    }

    # 6. The alignment: n minus R optional segments are present.
    $Present = $Count - $Required
    $Next = 0
    $Assigned = [System.Collections.Generic.List[object]]::new()
    for ($J = 0; $J -lt $Total; $J++) {
        $Segment = $Segments[$J]
        if (-not $Segment.Optional) {
            $Assigned.Add([PSCustomObject]@{ Part = $Parts[$Next]; Segment = $Segment })
            $Next++
            continue
        }
        $OptionalLeft = @($Segments[$J..($Total - 1)] | Where-Object { $_.Optional }).Count
        if ($Present -eq 0) { continue }
        if ($Present -eq $OptionalLeft -or (Test-SegmentFit -Part $Parts[$Next] -Segment $Segment)) {
            $Assigned.Add([PSCustomObject]@{ Part = $Parts[$Next]; Segment = $Segment })
            $Present--
            $Next++
        }
    }

    # 7. The segments, in order.
    foreach ($Entry in $Assigned) {
        $Part = $Entry.Part
        $Segment = $Entry.Segment
        if (-not (Test-ValueRule -Part $Part -Segment $Segment)) {
            if ($null -ne $Segment.Values) {
                $Allowed = (@($Segment.Values | ForEach-Object { "'$_'" })) -join ', '
                $Hint = ''
                foreach ($Value in $Segment.Values) {
                    if ([string]::Equals($Value, $Part, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $Hint = " (it differs from '$Value' only in letter case)"
                        break
                    }
                }
                ConvertTo-NameFinding -Rule 'values' -Segment $Segment -Detail "'$Part' is not one of the allowed values $Allowed$Hint."
            } else {
                ConvertTo-NameFinding -Rule 'pattern' -Segment $Segment -Detail "'$Part' does not match the pattern '$($Segment.Pattern)' (the whole segment must match)."
            }
        }
        if ($null -ne $Segment.Case -and -not (Test-CaseRule -Part $Part -Case $Segment.Case)) {
            ConvertTo-NameFinding -Rule 'case' -Segment $Segment -Detail "'$Part' is not $($Segment.Case) ($($CaseRule[$Segment.Case].Words))."
        }
    }
}
