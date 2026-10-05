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
    if ($Current -ceq $State['GraphSessionFingerprint']) {
        return 'Own'
    }
    'Changed'
}
