function Get-OERGraphSessionFingerprint {
    <#
    .SYNOPSIS
    Returns a fingerprint of a Microsoft Graph PowerShell SDK session, or $null when there is none.

    .DESCRIPTION
    The Microsoft Graph PowerShell SDK keeps one session per process, and Invoke-OERGraphRequest sends
    every Graph call under it with no token of its own. Initialize-OERAuth records this fingerprint
    straight after its own Connect-MgGraph, and Get-OERGraphSessionState compares it with the session
    the process holds before the module trusts its cache or sends a Graph call.

    It is built from eight properties of the context Get-MgContext returns: AuthType,
    TokenCredentialType, ClientId, TenantId, Account, AppName, Environment and Scopes (sorted). For a
    Connect-MgGraph -AccessToken session, the one this module makes, the SDK sets AuthType and
    TokenCredentialType to UserProvidedAccessToken and fills ClientId, TenantId, Account, AppName and
    Scopes from the token's appid, tid, upn, app_displayname and scp or roles claims. Any other
    Connect-MgGraph -- a certificate, a client secret, a managed identity, an interactive sign-in, or a
    token for another application, tenant or user -- therefore gives a different fingerprint. Two
    sessions with equal values give an equal fingerprint whatever object carries them, so two
    runspaces connected as the same identity to the same tenant do not refuse each other.

    It never reads the context's ClientSecret or Certificate, never keeps the context object, and never
    holds a token: the SDK keeps the token in its own token cache, not on the context. It does hold the
    session's tenant id and user principal name, so it is never written to any stream.

    .PARAMETER Context
    A context as Get-MgContext returns it; $null means there is no session. When omitted,
    Get-MgContext is called once.

    .EXAMPLE
    $Fingerprint = Get-OERGraphSessionFingerprint

    Fingerprints the Graph SDK session the process holds now, or returns $null when there is none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Context
    )
    if (-not $PSBoundParameters.ContainsKey('Context')) {
        $Context = Get-MgContext
    }
    if ($null -eq $Context) {
        return $null
    }
    # Sorted ordinally so the same grant in another order is the same session. [string[]] over an
    # empty pipeline is an empty array, so a context with no scopes still fingerprints.
    [string[]]$Scopes = @($Context.Scopes | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    [System.Array]::Sort($Scopes, [System.StringComparer]::Ordinal)
    # JSON, not a joined string: a value holding the separator can never make two sessions compare
    # equal. Every value is read by name -- never by enumerating the context, which would read its
    # ClientSecret and Certificate too.
    [ordered]@{
        AuthType            = [string]$Context.AuthType
        TokenCredentialType = [string]$Context.TokenCredentialType
        ClientId            = [string]$Context.ClientId
        TenantId            = [string]$Context.TenantId
        Account             = [string]$Context.Account
        AppName             = [string]$Context.AppName
        Environment         = [string]$Context.Environment
        Scopes              = $Scopes
    } | ConvertTo-Json -Compress
}
