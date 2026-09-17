function Test-OERTenantAlias {
    <#
    .SYNOPSIS
    Tests whether a tenant alias is safe to use as a Tenant Profile file name.

    .DESCRIPTION
    Pure predicate used by the configuration cmdlets and by Resolve-OERProfilePath to reject a
    -TenantAlias that would escape the profiles directory. The alias becomes the base name of a
    profile .psd1 file on disk, so it is restricted to letters, digits, dot, underscore and
    hyphen, and must not be '.', '..', or contain '..' anywhere. Directory separators, drive qualifiers, UNC
    prefixes and wildcards are all rejected by the character set. A Windows reserved device name
    (CON, PRN, AUX, NUL, COM1-COM9, LPT1-LPT9) is also rejected, whether it is the whole alias or
    the segment before the first dot, because such a name addresses a device rather than a regular
    file on Windows. Returns $false for null or empty. Makes no network or file-system call and
    never throws.

    .PARAMETER Value
    The tenant alias string to test for safe-file-name format.

    .EXAMPLE
    Test-OERTenantAlias -Value 'contoso'
    Returns $true.

    .EXAMPLE
    Test-OERTenantAlias -Value '../../../evil'
    Returns $false, because the value would write a profile outside the profiles directory.

    .EXAMPLE
    Test-OERTenantAlias -Value 'CON'
    Returns $false, because CON is a Windows reserved device name and would not behave as a
    regular file on disk.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -eq '.') { return $false }
    if ($Value.Contains('..')) { return $false }
    if (-not ($Value -match '^[A-Za-z0-9._-]+$')) { return $false }

    $ReservedDeviceNames = @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    )
    $UpperValue = $Value.ToUpperInvariant()
    $UpperBaseName = $Value.Split('.')[0].ToUpperInvariant()
    if ($ReservedDeviceNames -contains $UpperValue -or $ReservedDeviceNames -contains $UpperBaseName) {
        return $false
    }

    return $true
}
