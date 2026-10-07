function Resolve-OERTenantDomain {
    <#
    .SYNOPSIS
    Resolves a tenant named by domain to its tenant ID through the cloud's OpenID discovery document.

    .DESCRIPTION
    The single owner of the module's one network call outside the Microsoft Graph and Azure Resource
    Manager transports. Initialize-OERAuth calls it for a tenant named by anything other than a GUID
    or 'organizations', before any token is requested, and compares the tenant ID it returns with the
    tenant each token was issued for (TenantMismatch).

    It sends one unauthenticated GET to the Microsoft Entra ID authority of the given cloud --
    {AuthorityHost}{domain}/v2.0/.well-known/openid-configuration, the host read from
    Get-OERCloudEndpoint -- with no Authorization header and no credential of any kind, and reads the
    tenant ID from the document's issuer. Measured 2026-10-06 against the commercial cloud: a verified
    domain and the tenant's own GUID answer 200 with an issuer that carries the tenant ID; a made-up
    domain answers 400 (invalid_tenant, AADSTS90002); 'organizations' and 'common' answer 200 with the
    template issuer '{tenantid}', which names no tenant.

    A tenant ID found is cached for the rest of the process, per cloud and per domain (case-insensitive),
    so a domain costs one request per process and cloud. A failure is not cached: the next sign-in asks
    again. Re-importing the module empties the cache.

    It throws an InvalidOperationException when the request fails or the document names no tenant ID;
    the caller turns that into TenantResolutionFailed.

    .PARAMETER Domain
    The tenant as the caller named it: a verified domain such as contoso.onmicrosoft.com.

    .PARAMETER Environment
    The sovereign cloud whose authority is asked: Global, USGov, USGovDoD or China.

    .EXAMPLE
    $TenantGuid = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'

    Returns the tenant ID of the tenant whose domain is contoso.onmicrosoft.com.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,

        [Parameter(Mandatory)]
        [string]$Environment
    )

    if ($null -eq $script:_OERTenantDomainCache) {
        $script:_OERTenantDomainCache = @{}
    }
    # Double-quoted on purpose: the line feed separates the two terms.
    [string]$Key = "$Environment`n$($Domain.ToLowerInvariant())"
    if ($script:_OERTenantDomainCache.ContainsKey($Key)) {
        return [string]$script:_OERTenantDomainCache[$Key]
    }

    $Endpoint = Get-OERCloudEndpoint -Environment $Environment
    [string]$Uri = '{0}{1}/v2.0/.well-known/openid-configuration' -f $Endpoint.AuthorityHost, [uri]::EscapeDataString($Domain)

    $Document = $null
    $RequestError = $null
    try {
        $Document = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 30 -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $RequestError = $PSItem
    }
    if ($null -ne $RequestError) {
        [string]$Detail = $RequestError.Exception.Message
        # The authority answers a refused lookup with a JSON body: error and error_codes name why.
        if ($RequestError.ErrorDetails -and $RequestError.ErrorDetails.Message) {
            try {
                $Body = $RequestError.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                if ($Body.error) {
                    [string]$Codes = (@($Body.error_codes) | Where-Object { $_ } | ForEach-Object { 'AADSTS{0}' -f $_ }) -join ', '
                    $Detail = '{0} ({1}{2})' -f $Detail, $Body.error, $(if ($Codes) { ', ' + $Codes } else { '' })
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
            }
        }
        throw [System.InvalidOperationException]::new(
            ("The Microsoft Entra ID authority '{0}' did not resolve '{1}' to a tenant: {2}" -f $Endpoint.AuthorityHost, $Domain, $Detail),
            $RequestError.Exception)
    }

    [string]$Issuer = if ($Document) { [string]$Document.issuer } else { '' }
    [string]$TenantGuid = ''
    $IssuerUri = $null
    if ($Issuer -and [uri]::TryCreate($Issuer, [System.UriKind]::Absolute, [ref]$IssuerUri)) {
        $FirstSegment = @($IssuerUri.Segments | ForEach-Object { $_.Trim('/') } | Where-Object { $_ })[0]
        if (Test-OERGuid -Value $FirstSegment) {
            $TenantGuid = $FirstSegment
        }
    }
    if (-not $TenantGuid) {
        throw [System.InvalidOperationException]::new(
            ("The OpenID discovery document the Microsoft Entra ID authority '{0}' returned for '{1}' names no tenant ID in its issuer ('{2}')." -f $Endpoint.AuthorityHost, $Domain, $Issuer))
    }

    $script:_OERTenantDomainCache[$Key] = $TenantGuid
    $TenantGuid
}
