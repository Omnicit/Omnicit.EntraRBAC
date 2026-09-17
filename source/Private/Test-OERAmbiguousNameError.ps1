function Test-OERAmbiguousNameError {
    <#
    .SYNOPSIS
    Tests whether a caught error record is a display-name ambiguity error raised by an OER resolver.

    .DESCRIPTION
    The private Resolve-OER*Id helpers throw an ErrorRecord whose ErrorId is 'AmbiguousName' when a
    display name matches more than one directory object, rather than silently returning the first
    match. This predicate is the single owner of that detection so every calling cmdlet routes the
    condition the same way instead of hand-matching the id string. Matching is a case-sensitive
    prefix test, so a record that has already crossed a WriteError boundary and carries the
    qualified '<ErrorId>,<CommandName>' form is still recognised. It is pure, makes no Graph call
    and never throws, so it is safe to call as the first test inside a catch block.

    .PARAMETER Record
    The ErrorRecord caught around a Resolve-OER*Id call. A null record returns false rather than
    throwing, so the caller does not need its own null guard before calling this helper.

    .EXAMPLE
    Test-OERAmbiguousNameError -Record $PSItem

    Returns $true inside a catch block when the resolver refused an ambiguous display name, letting
    the caller report the ambiguity instead of a misleading not-found error.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [System.Management.Automation.ErrorRecord]$Record
    )
    if (-not $Record) { return $false }
    return ([string]$Record.FullyQualifiedErrorId).StartsWith('AmbiguousName', [System.StringComparison]::Ordinal)
}
