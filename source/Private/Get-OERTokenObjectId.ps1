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
    no token, not three segments, a payload that is not base64url JSON, or no GUID-shaped oid. The
    token is never written to any stream.

    .PARAMETER Token
    The plaintext access token, as AzAuth returns it.

    .EXAMPLE
    Get-OERTokenObjectId -Token $GraphToken.Token
    Returns the object id of the identity the token was issued to, or $null.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $Segments = $Token.Split('.')
    if ($Segments.Count -ne 3) { return $null }
    $Payload = $Segments[1].Replace('-', '+').Replace('_', '/')
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
