function Resolve-OERProfilePath {
    <#
    .SYNOPSIS
    Resolves the on-disk path to a Tenant Profile PSD1 file for a given alias.

    .DESCRIPTION
    Computes the full path to the Tenant Profile configuration file for the supplied alias under
    the Omnicit.EntraRBAC profile directory. The base directory defaults to the current user's
    home folder plus '.config/Omnicit.EntraRBAC/Profiles' and can be overridden for testing or for
    alternate storage locations. The function does not create the file; it only returns the path.
    The alias is validated with Test-OERTenantAlias before the path is built, and the resolved
    path is proven to stay under -BasePath before it is returned.

    .PARAMETER TenantAlias
    The short tenant alias whose profile file path should be resolved. An alias that fails the
    safe-file-name check throws an ErrorRecord with ErrorId InvalidTenantAlias.

    .PARAMETER BasePath
    The base directory that contains per-alias profile files. Defaults to a platform-neutral path
    under the current user's home folder, resolved through .NET rather than a Windows-only variable.

    .EXAMPLE
    Resolve-OERProfilePath -TenantAlias contoso
    Returns the full path to the contoso.psd1 profile file under the default config directory.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles')
    )
    if (-not (Test-OERTenantAlias -Value $TenantAlias)) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Tenant alias '$TenantAlias' is not a valid profile name. Use only letters, digits, " +
                "dot, underscore and hyphen (no path separators and no '..')."),
            'InvalidTenantAlias',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $TenantAlias)
    }

    $Candidate = Join-Path $BasePath ('{0}.psd1' -f $TenantAlias)

    # Defence in depth: even with a validated alias, prove the joined path stays under $BasePath
    # before any caller reads, writes or deletes it. GetFullPath normalizes '..' and separators
    # without requiring the path to exist, so this works for a profile that has not been created yet.
    $FullBase = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $FullCandidate = [System.IO.Path]::GetFullPath($Candidate)
    if (-not $FullCandidate.StartsWith($FullBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "The resolved profile path for alias '$TenantAlias' falls outside the profile directory '$BasePath'."),
            'ProfilePathEscapesBase',
            [System.Management.Automation.ErrorCategory]::SecurityError,
            $TenantAlias)
    }

    $Candidate
}
