function New-OERConfiguration {
    <#
    .SYNOPSIS
    Creates a new Tenant Profile configuration file for a tenant alias.

    .DESCRIPTION
    Creates a new Tenant Profile PSD1 file that stores the tenant id and optional naming templates
    and default values (approvers, catalog, authentication context, activation window) for a named
    tenant alias. This command is create-only: it emits a non-terminating error if a profile for the
    alias already exists and directs the caller to Set-OERConfiguration. Serialization is delegated
    to the private Export-OERConfiguration helper. The returned object carries the full profile shape,
    including the Naming and Defaults sections that were just written, not just the tenant alias, id,
    and path. Supports -WhatIf and -Confirm.

    .PARAMETER TenantAlias
    The short alias that identifies the tenant profile, e.g. 'contoso'. Used as the file name. The
    alias becomes a file name on disk, so it is restricted to letters, digits, dot, underscore and
    hyphen; anything else is rejected with an InvalidTenantAlias error.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain stored in the profile.

    .PARAMETER Naming
    Optional hashtable of naming templates keyed by object kind, e.g. @{ Group = 'role_sec_{area}_{tier}' }.

    .PARAMETER Defaults
    Optional hashtable of default values such as PrimaryApprovers, Catalog, and ActivationMaxHours.

    .PARAMETER BasePath
    The base directory for profile files. Defaults to the user's Omnicit.EntraRBAC config folder.

    .PARAMETER Environment
    Optional sovereign cloud to store for this tenant: 'Global', 'USGov', 'USGovDoD' or 'China'. When
    omitted, no Environment key is written and the profile behaves exactly as it did before this
    parameter existed -- Connect-OER -TenantAlias then falls back to its own 'Global' default rather
    than reading one from here. Stored so Connect-OER -TenantAlias can select the right cloud for this
    tenant automatically instead of requiring -Environment on every call.

    .EXAMPLE
    New-OERConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'
    Creates a new minimal tenant profile for the contoso alias.

    .EXAMPLE
    New-OERConfiguration -TenantAlias contoso-gcc -TenantId '00000000-0000-0000-0000-000000000001' -Environment USGov
    Creates a tenant profile that always signs in against the US Government (GCC High) cloud.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,
        [Parameter(Mandatory)]
        [string]$TenantId,
        [hashtable]$Naming,
        [hashtable]$Defaults,
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles'),

        # Declared LAST on purpose, matching Connect-OER's own -Environment. Positional binding
        # follows DECLARATION order, so inserting this anywhere above would silently change what an
        # existing positional -Naming or -Defaults argument binds to. No default value: an
        # unsupplied -Environment must leave no Environment key in the written profile at all (see
        # the .PARAMETER block above), and a default here would write 'Global' into every profile
        # ever created without -Environment.
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
    )
    process {
        if (-not (Test-OERTenantAlias -Value $TenantAlias)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Tenant alias '$TenantAlias' is not a valid profile name. Use only letters, digits, " +
                    "dot, underscore and hyphen (no path separators and no '..').")) `
                -ErrorId 'InvalidTenantAlias' `
                -Category InvalidArgument `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }

        # Resolve-OERProfilePath throws ProfilePathEscapesBase only for a pathological -BasePath (the
        # alias itself was already validated above); a public cmdlet must never let that terminate the
        # pipeline, so it is converted to a non-terminating error here.
        try {
            $Path = Resolve-OERProfilePath -TenantAlias $TenantAlias -BasePath $BasePath
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message $PSItem.Exception `
                -ErrorId 'ProfilePathEscapesBase' `
                -Category SecurityError `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }
        if (Test-Path $Path) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A Tenant Profile for alias '$TenantAlias' already exists at '$Path'. Use Set-OERConfiguration to update it.")) `
                -ErrorId 'ProfileAlreadyExists' `
                -Category ResourceExists `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }

        $Configuration = @{ TenantId = $TenantId }
        if ($Naming)      { $Configuration.Naming = $Naming }
        if ($Defaults)    { $Configuration.Defaults = $Defaults }
        if ($Environment) { $Configuration.Environment = $Environment }

        if ($PSCmdlet.ShouldProcess($Path, "Create Tenant Profile for alias '$TenantAlias'")) {
            Export-OERConfiguration -Configuration $Configuration -Path $Path
            ConvertTo-OERTenantConfiguration `
                -TenantAlias $TenantAlias `
                -TenantId $TenantId `
                -Environment $Environment `
                -Naming $Naming `
                -Defaults $Defaults `
                -Path $Path
        }
    }
}
