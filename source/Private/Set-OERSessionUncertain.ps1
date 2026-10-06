function Set-OERSessionUncertain {
    <#
    .SYNOPSIS
    Sets or clears the module's session-uncertain marker and returns what it was.

    .DESCRIPTION
    The single owner of the session-uncertain marker (A10, BL-89). A sign-in that does not succeed
    leaves the module's session unchanged -- the previous tenant's, or none -- and outside any try the
    script carries on: a command that names no tenant would then act on the previous tenant. While the
    marker is set, Initialize-OERAuth refuses such a command with SignInRefused before it requests a
    token or sends anything.

    Initialize-OERAuth sets it at every entry, directly after it latches its caller, and clears it again
    at its two success ends when the sign-in named its tenant or was Connect-OER's; for any other success
    it puts back the value it found. Connect-OER sets it first thing, so its own refusals before any
    sign-in (an unknown tenant alias, for example) leave it set too. Disconnect-OER clears it. Nothing
    else reads or writes it.

    .PARAMETER Value
    $true to mark the session uncertain, $false to clear the marker.

    .EXAMPLE
    $WasUncertain = Set-OERSessionUncertain -Value $true

    Marks the session uncertain and keeps whether it already was.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Flips the module''s in-memory safety marker inside the sign-in of its three callers; a -WhatIf here could only skip the marker that keeps a later command from acting on the previous tenant.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [bool]$Value
    )

    [bool]$Previous = [bool]$script:_OERSessionUncertain
    $script:_OERSessionUncertain = $Value
    $Previous
}
