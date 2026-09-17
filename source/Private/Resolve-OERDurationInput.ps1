function Resolve-OERDurationInput {
    <#
    .SYNOPSIS
    Normalizes a user-supplied duration value into a canonical ISO 8601 duration string.

    .DESCRIPTION
    The module's public duration parameters accept two forms: the module-standard raw ISO 8601
    duration ('P365D', 'PT8H') and a bare whole-unit count ('365' meaning 365 days), which several
    cmdlets shipped with before the vocabulary was unified and must keep accepting. This private
    helper is the single owner of that normalization. A bare whole number is range-checked and
    handed to ConvertTo-OERDuration (the sole int-to-ISO encoder); an ISO 8601 duration is validated
    and returned upper-cased and otherwise verbatim, so a value read back from Microsoft Graph or
    Azure PIM can be fed straight back in without re-parsing. Anything else throws an operator
    readable error that the calling public cmdlet routes through Write-CmdletError. The helper is
    pure: no network call and no state change. Passing an already-normalized ISO value through it a
    second time is a no-op, so a call site may normalize defensively.

    .PARAMETER Value
    The duration as supplied by the caller: either a bare whole-unit count (for example '365') or an
    ISO 8601 duration (for example 'P365D' or 'PT8H'). An empty or whitespace-only value throws.

    .PARAMETER Unit
    The unit a bare whole number is interpreted in: Days (the default, producing 'P{n}D') or Hours
    (producing 'PT{n}H'). Ignored when the value is already an ISO 8601 duration.

    .PARAMETER Maximum
    The largest accepted whole-unit count, defaulting to 3650 (the range the module's duration
    parameters have always enforced). Only applied to the bare whole-number form; an explicit ISO
    duration is passed through so the API remains the authority on its own limits.

    .EXAMPLE
    Resolve-OERDurationInput -Value '365'
    Returns 'P365D'.

    .EXAMPLE
    Resolve-OERDurationInput -Value 'PT8H'
    Returns 'PT8H' unchanged, because the value is already an ISO 8601 duration.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [ValidateSet('Days', 'Hours')]
        [string]$Unit = 'Days',

        [int]$Maximum = 3650
    )

    $Trimmed = "$Value".Trim()
    if ([string]::IsNullOrEmpty($Trimmed)) {
        throw 'A duration value is required. Supply a whole number of days (e.g. 365) or an ISO 8601 duration (e.g. ''P365D'').'
    }

    if ($Trimmed -match '^\d+$') {
        $Count = [int]$Trimmed
        if ($Count -lt 1 -or $Count -gt $Maximum) {
            throw "Duration '$Trimmed' is out of range: a whole number of $($Unit.ToLowerInvariant()) must be between 1 and $Maximum."
        }
        if ($Unit -eq 'Hours') { return ConvertTo-OERDuration -Hours $Count }
        return ConvertTo-OERDuration -Days $Count
    }

    # The module's established ISO 8601 duration pattern (the same one New-OEREligibleRoleAssignment
    # validates -Duration with). The look-ahead rejects a bare 'P' with no components.
    $Upper = $Trimmed.ToUpperInvariant()
    if ($Upper -match '^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$') {
        return $Upper
    }

    throw "Duration '$Trimmed' is not a valid duration. Supply a whole number of $($Unit.ToLowerInvariant()) (e.g. 365) or an ISO 8601 duration (e.g. 'P365D' or 'PT8H')."
}
