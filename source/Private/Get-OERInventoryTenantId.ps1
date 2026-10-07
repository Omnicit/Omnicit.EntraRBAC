function Get-OERInventoryTenantId {
    <#
    .SYNOPSIS
    Returns the tenant an exported structure document names: the tenant the session's Microsoft Graph
    token was issued for.

    .DESCRIPTION
    The single owner of which tenant an exported inventory names in its top-level tenantId (BL-88,
    decision A14). It is the tenant the Microsoft Graph token of the module's session was issued for
    (TokenTenantId, which Initialize-OERAuth records from the token itself) and never the tenant as the
    caller named it (TenantId): a domain, 'organizations' or no tenant at all names no tenant ID, and
    since BL-77 every request a command sends goes out under the identity whose tenant term is that
    granted tenant. Returns the GUID when it is one (Test-OERGuid), and nothing otherwise -- no state,
    or a token for which AzAuth reported no tenant ID. A document exported then carries no tenantId and
    is applied as a document without one, with no tenant check. Reads the module's state only; makes
    no request and never signs in.

    Get-OERInventory and Export-OERInventory call it in their begin block, directly after their own
    Initialize-OERAuth, and pass the value to ConvertTo-OERInventory -TenantId.

    .EXAMPLE
    $DocumentTenantId = Get-OERInventoryTenantId

    Returns the tenant ID the session's Graph token was issued for, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($null -eq $script:_OERAuthState) { return }
    [string]$Granted = $script:_OERAuthState.TokenTenantId
    if (Test-OERGuid -Value $Granted) { $Granted }
}
