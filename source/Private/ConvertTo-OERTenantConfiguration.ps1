function ConvertTo-OERTenantConfiguration {
    <#
    .SYNOPSIS
    Builds the tagged Omnicit.EntraRBAC.TenantConfiguration object for a Tenant Profile.

    .DESCRIPTION
    This private converter is the single owner of the Tenant Profile output shape and is used by
    Get-OERConfiguration, New-OERConfiguration, and Set-OERConfiguration. It always emits the same
    six properties in the same order -- TenantAlias, TenantId, Environment, Naming, Defaults, Path --
    so a caller can read .Naming or .Defaults off any of the three cmdlets' output instead of getting
    $null from the create and update paths, which previously built a three-property variant of the
    same type name. Naming, Defaults, and Environment are emitted as $null when the profile does not
    define them.

    Environment sits directly after TenantId, not at the end next to Path: it is identity/connection
    data describing WHICH cloud the tenant with that TenantId lives in, the same category as
    TenantAlias and TenantId themselves, not a user-authored settings section like Naming or Defaults
    and not file-location metadata like Path. Connect-OER reads TenantId and Environment together off
    this same object to decide where to sign in, which is the pairing this order documents.

    .PARAMETER TenantAlias
    The alias the Tenant Profile is stored under, which is also the PSD1 file base name on disk.

    .PARAMETER TenantId
    The directory (tenant) id the profile points at, as a GUID string or a verified domain name.

    .PARAMETER Environment
    The optional sovereign cloud stored for this tenant: 'Global', 'USGov', 'USGovDoD' or 'China'.
    $null when the profile does not define one, which Connect-OER treats as no cloud override rather
    than as an implicit 'Global' -- the fallback to the public cloud happens there, not here.

    .PARAMETER Naming
    The optional Naming section of the profile, a hashtable of naming templates keyed by object kind.

    .PARAMETER Defaults
    The optional Defaults section of the profile, a hashtable of per-tenant default values.

    .PARAMETER Path
    The full path of the PSD1 file the profile is stored in, so the caller can locate it on disk.

    .EXAMPLE
    ConvertTo-OERTenantConfiguration -TenantAlias 'contoso' -TenantId $Id -Path $Path
    Returns the tagged tenant configuration object with Naming and Defaults set to null.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,

        [string]$TenantId,

        [string]$Environment,

        [hashtable]$Naming,

        [hashtable]$Defaults,

        [string]$Path
    )
    process {
        $Out = [PSCustomObject]@{
            TenantAlias = $TenantAlias
            TenantId    = $TenantId
            Environment = $Environment
            Naming      = $Naming
            Defaults    = $Defaults
            Path        = $Path
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.TenantConfiguration')
        $Out
    }
}
