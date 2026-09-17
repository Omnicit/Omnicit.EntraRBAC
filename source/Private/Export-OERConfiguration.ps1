function Export-OERConfiguration {
    <#
    .SYNOPSIS
    Serializes a Tenant Profile hashtable to a PSD1 file on disk.

    .DESCRIPTION
    Writes the supplied Tenant Profile configuration hashtable to the given path as a PowerShell
    data file (PSD1) that can be read back with Import-PowerShellDataFile. Nested hashtables such
    as Naming and Defaults are serialized recursively. The parent directory is created when it does
    not already exist. This private helper is the single owner of profile serialization and is
    called by New-OERConfiguration and Set-OERConfiguration.

    .PARAMETER Configuration
    The Tenant Profile hashtable to serialize. Expected keys include TenantId, Naming, and Defaults.

    .PARAMETER Path
    The full path of the PSD1 file to write. Its parent directory is created if missing.

    .EXAMPLE
    Export-OERConfiguration -Configuration @{ TenantId = '...' } -Path 'C:\cfg\contoso.psd1'
    Writes the configuration to contoso.psd1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration,
        [Parameter(Mandatory)]
        [string]$Path
    )

    function ConvertTo-OERPsd1Fragment {
        param([Parameter(Mandatory)]$Value, [int]$Indent = 0)
        $Pad = ' ' * (4 * ($Indent + 1))
        $ClosePad = ' ' * (4 * $Indent)
        if ($Value -is [System.Collections.IDictionary]) {
            $Lines = [System.Collections.Generic.List[string]]::new()
            $Lines.Add('@{')
            foreach ($Key in ($Value.Keys | Sort-Object)) {
                $Inner = ConvertTo-OERPsd1Fragment -Value $Value[$Key] -Indent ($Indent + 1)
                # Keys are caller-supplied -- New-/Set-OERConfiguration take a bare [hashtable] for
                # -Naming and -Defaults with no key validation -- so an unquoted key containing a
                # space or a quote wrote a profile Import-PowerShellDataFile cannot parse, leaving
                # the alias unreadable. Quote and escape the key exactly as the values already are.
                $SafeKey = "'" + ([string]$Key -replace "'", "''") + "'"
                $Lines.Add(('{0}{1} = {2}' -f $Pad, $SafeKey, $Inner))
            }
            $Lines.Add(("$ClosePad" + '}'))
            return ($Lines -join [System.Environment]::NewLine)
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $Items = @($Value | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" })
            return '@(' + ($Items -join ', ') + ')'
        }
        return "'" + ($Value -replace "'", "''") + "'"
    }

    $ParentDir = Split-Path -Path $Path -Parent
    if ($ParentDir -and -not (Test-Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
    }

    $Body = ConvertTo-OERPsd1Fragment -Value $Configuration -Indent 0
    Set-Content -Path $Path -Value $Body -Encoding UTF8
}
