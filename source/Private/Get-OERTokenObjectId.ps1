function Get-OERTokenObjectId {
    <#
    .SYNOPSIS
    Reads the oid claim -- the signed-in identity's object id -- from a Microsoft Graph access token.

    .DESCRIPTION
    The single owner of reading the signed-in identity's object id. Decodes the payload segment of a
    JWT access token (base64url, no signature check -- the token was just issued to this module) and
    returns its oid claim, lower-cased, when that is a GUID. Delegated tokens carry the user's object
    id there and app-only tokens the service principal's, so the same read serves both; nothing reads
    /me, which an app-only sign-in does not have. Returns $null, and never throws, for anything else:
    no token, an empty or disposed secure string, not three segments, a payload that is not base64url
    JSON, or no GUID-shaped oid. The token is never written to any stream.

    The token is taken as a SecureString, never as a plain string. PowerShell module logging
    (LogPipelineExecutionDetails, or the "Turn on Module Logging" policy) records every bound
    parameter value of a command, so a [string] parameter would log the live Graph token on every
    sign-in on such a machine; a SecureString is logged as its type name only. The plaintext is
    materialized inside this function through a .NET call, which is not a parameter binding, and the
    local reference is dropped as soon as the payload segment has been cut out of it.

    .PARAMETER Token
    The access token as a SecureString -- Initialize-OERAuth passes the same SecureString it hands
    to Connect-MgGraph.

    .EXAMPLE
    Get-OERTokenObjectId -Token $SecureToken
    Returns the object id of the identity the token was issued to, or $null.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()][securestring]$Token
    )
    if ($null -eq $Token) { return $null }
    $Payload = $null
    try {
        # Inside the try: a disposed SecureString throws on Length and on the conversion alike.
        if ($Token.Length -eq 0) { return $null }
        $Plain = [System.Net.NetworkCredential]::new('', $Token).Password
        $Segments = $Plain.Split('.')
        $Plain = $null
        if ($Segments.Count -eq 3) { $Payload = $Segments[1] }
        $Segments = $null
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return $null
    }
    if ($null -eq $Payload) { return $null }
    $Payload = $Payload.Replace('-', '+').Replace('_', '/')
    switch ($Payload.Length % 4) {
        1 { return $null }
        2 { $Payload += '==' }
        3 { $Payload += '=' }
    }
    $Claims = $null
    try {
        $Json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Payload))
        $Claims = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return $null
    }
    $Oid = [string]$Claims.oid
    if (Test-OERGuid -Value $Oid) { return $Oid.ToLowerInvariant() }
    return $null
}
