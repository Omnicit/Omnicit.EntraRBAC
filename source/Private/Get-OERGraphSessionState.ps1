function Get-OERGraphSessionState {
    <#
    .SYNOPSIS
    Compares the Microsoft Graph PowerShell SDK session in the process with the one this module connected.

    .DESCRIPTION
    Returns one of four values:

    Untracked -- the module holds no session it connected itself: no auth state, or a state that
    carries no recorded fingerprint. Nothing is compared and Get-MgContext is not called.

    Own -- the process holds the session the module connected.

    Absent -- the process holds no session at all, for example after Disconnect-MgGraph.

    Changed -- the process holds a session the module did not connect: another Connect-MgGraph has
    replaced it.

    Initialize-OERAuth calls this at every entry and Invoke-OERGraphRequest before every Graph call.
    The fingerprint itself is Get-OERGraphSessionFingerprint's; this function only compares.

    .EXAMPLE
    if ((Get-OERGraphSessionState) -eq 'Changed') { throw (New-OERGraphSessionChangedError) }

    Refuses a Graph call when another Connect-MgGraph has replaced the module's session.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $State = $script:_OERAuthState
    if (-not ($State -is [System.Collections.IDictionary]) -or -not $State.Contains('GraphSessionFingerprint')) {
        return 'Untracked'
    }
    $Current = Get-OERGraphSessionFingerprint
    if ($null -eq $Current) {
        return 'Absent'
    }
    # Ordinal, not -ceq: -ceq compares with the invariant culture, which ignores characters of zero
    # weight -- a soft hyphen in one value compared equal to none (measured 2026-10-05). A stored
    # $null casts to '', which never equals the non-empty fingerprint of a session that exists, so
    # it stays Changed.
    if ([string]::Equals($Current, [string]$State['GraphSessionFingerprint'], [System.StringComparison]::Ordinal)) {
        return 'Own'
    }
    'Changed'
}
