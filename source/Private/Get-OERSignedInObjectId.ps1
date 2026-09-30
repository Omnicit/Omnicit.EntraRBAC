function Get-OERSignedInObjectId {
    <#
    .SYNOPSIS
    Returns the signed-in identity's object id recorded in the current session, or $null.

    .DESCRIPTION
    Reads $script:_OERAuthState.SignedInObjectId, the value Initialize-OERAuth recorded from the
    Graph token's oid claim (see Get-OERTokenObjectId) when the current session was established.
    Returns $null when there is no session, the key is absent (a state built before this key
    existed), or the recorded value is not GUID-shaped -- callers then treat the signed-in identity
    as unknown rather than trusting a malformed value.

    .EXAMPLE
    Get-OERSignedInObjectId
    Returns the signed-in identity's object id, or $null when it cannot be determined.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()
    if ($script:_OERAuthState -and (Test-OERGuid -Value ([string]$script:_OERAuthState.SignedInObjectId))) {
        return [string]$script:_OERAuthState.SignedInObjectId
    }
    return $null
}
