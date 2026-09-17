function Resolve-OERStructureDefault {
    <#
    .SYNOPSIS
    Resolves a single orchestration default from a Tenant Profile's Defaults section.

    .DESCRIPTION
    Looks up one named fallback value from the Tenant Profile identified by -TenantAlias via
    Get-OERConfiguration. Only a small explicit set of keys is supported -- PrimaryApprovers,
    EscalationApprovers, AuthenticationContextId, ActivationMaxHours, and Catalog -- so the apply engine
    can fill an omitted document field. Returns $null when no alias is supplied, the profile cannot be
    read, the Defaults section is absent, or the key is not present. An explicit value in the document
    always wins; this helper is only consulted for omitted fields.

    .PARAMETER TenantAlias
    The Tenant Profile alias whose Defaults are read. When omitted the function returns $null.

    .PARAMETER Name
    The default key to resolve (PrimaryApprovers, EscalationApprovers, AuthenticationContextId,
    ActivationMaxHours, or Catalog).

    .EXAMPLE
    Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'ActivationMaxHours'
    Returns the configured default activation window, or $null when not set.
    #>
    [OutputType([object])]
    [CmdletBinding()]
    param(
        [string]$TenantAlias,
        [Parameter(Mandatory)]
        [ValidateSet('PrimaryApprovers', 'EscalationApprovers', 'AuthenticationContextId', 'ActivationMaxHours', 'Catalog')]
        [string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($TenantAlias)) { return $null }
    $Config = try { Get-OERConfiguration -TenantAlias $TenantAlias -ErrorAction Stop } catch { Remove-OERErrorRecord -Record $PSItem; $null }
    if (-not $Config) { return $null }
    $Defaults = $Config.Defaults
    if (-not $Defaults) { return $null }
    if ($Defaults -is [hashtable]) {
        if ($Defaults.ContainsKey($Name)) { return $Defaults[$Name] }
        return $null
    }
    if ($Defaults.PSObject.Properties.Name -contains $Name) { return $Defaults.$Name }
    return $null
}
