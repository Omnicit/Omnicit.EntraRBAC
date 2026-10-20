function Get-OERAccessReviewCadence {
    <#
    .SYNOPSIS
    Maps an access review cadence to its Microsoft Graph recurrence pattern, and a live pattern back to
    a cadence.

    .DESCRIPTION
    The single owner of the cadence table (BL-117, third point). An access review's recurrence is a
    closed vocabulary of six cadences, each one a fixed Graph pattern type and interval: OneTime is no
    recurrence object at all, Weekly is pattern type weekly with interval 1, and Monthly, Quarterly,
    SemiAnnually and Annually are pattern type absoluteMonthly with interval 1, 3, 6 and 12. The
    builder New-OERAccessReviewRecurrence, the live-state diff Resolve-OERAccessReviewChange and the
    export in Get-OERInventory all read that table here; none of them spells an interval switch of its
    own, and a test in Get-OERAccessReviewCadence.Tests.ps1 holds that no other file under source/ does.

    The function answers in one shape, whichever direction it is asked in: Cadence (the canonical
    spelling), PatternType and Interval (the pattern that cadence stands for, both $null for OneTime)
    and Representable.

    -Cadence answers the pattern a cadence is sent as. The name is matched without regard to letter
    case and answered in the canonical spelling, and Representable is $true. A name outside the six is a
    caller error and throws, since this is a private pure helper.

    -PatternType with -Interval answers the cadence a live pattern is read as. Representable is $true
    only when the live pattern is exactly one of the five patterns above (weekly interval 1, or
    absoluteMonthly interval 1, 3, 6 or 12). Any other interval collapses onto the first cadence of the
    same pattern type -- weekly onto Weekly, absoluteMonthly onto Monthly -- with Representable $false,
    and PatternType and Interval then hold what a rebuild from that collapsed cadence would send. A
    pattern type that is neither weekly nor absoluteMonthly (an empty one included) reads as OneTime
    with Representable $false. A caller that rewrites a recurrence must refuse when Representable is
    $false, since the rewrite would silently replace the live pattern with the coarser one.

    The pattern type is matched without regard to letter case. No Graph, ARM or authentication occurs.

    .PARAMETER Cadence
    A cadence name: OneTime, Weekly, Monthly, Quarterly, SemiAnnually or Annually.

    .PARAMETER PatternType
    The pattern type of a live recurrence pattern, as Graph reports it: weekly or absoluteMonthly. Any
    other value, an empty one included, is read as no cadence the module can write.

    .PARAMETER Interval
    The interval of the live pattern, already an integer.

    .EXAMPLE
    Get-OERAccessReviewCadence -Cadence Quarterly

    Returns Cadence Quarterly, PatternType absoluteMonthly, Interval 3 and Representable $true.

    .EXAMPLE
    Get-OERAccessReviewCadence -PatternType absoluteMonthly -Interval 2

    Returns Cadence Monthly with Representable $false: a bi-monthly review the module cannot write back.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'FromCadence')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FromCadence')]
        [string]$Cadence,

        [Parameter(Mandatory, ParameterSetName = 'FromPattern')]
        [AllowEmptyString()]
        [string]$PatternType,

        [Parameter(Mandatory, ParameterSetName = 'FromPattern')]
        [int]$Interval
    )

    # The table, in the canonical order of Resolve-OERStructureEnumCasing's accessReviewRecurrence.
    # OneTime is the one row with no pattern, so it is also what an unreadable pattern falls back to.
    $Table = @(
        [PSCustomObject]@{ Cadence = 'OneTime';      PatternType = $null;             Interval = $null }
        [PSCustomObject]@{ Cadence = 'Weekly';       PatternType = 'weekly';          Interval = 1 }
        [PSCustomObject]@{ Cadence = 'Monthly';      PatternType = 'absoluteMonthly'; Interval = 1 }
        [PSCustomObject]@{ Cadence = 'Quarterly';    PatternType = 'absoluteMonthly'; Interval = 3 }
        [PSCustomObject]@{ Cadence = 'SemiAnnually'; PatternType = 'absoluteMonthly'; Interval = 6 }
        [PSCustomObject]@{ Cadence = 'Annually';     PatternType = 'absoluteMonthly'; Interval = 12 }
    )

    $Match = $null
    $Exact = $false
    if ($PSCmdlet.ParameterSetName -eq 'FromCadence') {
        foreach ($Row in $Table) {
            if ($Row.Cadence -ieq $Cadence) { $Match = $Row; $Exact = $true; break }
        }
        if ($null -eq $Match) {
            throw "Get-OERAccessReviewCadence: '$Cadence' is not an access review cadence."
        }
    }
    else {
        foreach ($Row in $Table) {
            if ($null -eq $Row.PatternType -or $Row.PatternType -ine $PatternType) { continue }
            if ($Row.Interval -eq $Interval) { $Match = $Row; $Exact = $true; break }
            # The first row of a pattern type is where every interval the table lacks collapses to.
            if ($null -eq $Match) { $Match = $Row }
        }
        if ($null -eq $Match) { $Match = $Table[0] }
    }

    [PSCustomObject]@{
        Cadence       = $Match.Cadence
        PatternType   = $Match.PatternType
        Interval      = $Match.Interval
        Representable = $Exact
    }
}
