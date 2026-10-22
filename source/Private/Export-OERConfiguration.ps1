function Export-OERConfiguration {
    <#
    .SYNOPSIS
    Serializes a Tenant Profile hashtable to a PSD1 file on disk.

    .DESCRIPTION
    Writes the supplied Tenant Profile configuration hashtable to the given path as a PowerShell
    data file (PSD1) that can be read back with Import-PowerShellDataFile. Nested hashtables such
    as Naming and Defaults are serialized recursively. The parent directory is created when it does
    not already exist. This private helper is the single owner of profile serialization and is
    called by New-OERConfiguration and Set-OERConfiguration. Every key, list item and scalar is
    written as a single-quoted string whose content is escaped by
    CodeGeneration.EscapeSingleQuotedStringContent, which doubles each of the five characters
    PowerShell reads as a single quote (U+0027, U+2018, U+2019, U+201A and U+201B), so a value
    carrying any of them reads back unchanged and can never end its string early.

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
                # EscapeSingleQuotedStringContent doubles every character the PowerShell tokenizer
                # reads as a single quote (U+0027, U+2018, U+2019, U+201A, U+201B), not only the
                # straight one: a curly quote left single ended the string early and the rest of the
                # value became PSD1 text (an injected key, or a file that no longer parses).
                $SafeKey = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$Key) + "'"
                $Lines.Add(('{0}{1} = {2}' -f $Pad, $SafeKey, $Inner))
            }
            $Lines.Add(("$ClosePad" + '}'))
            return ($Lines -join [System.Environment]::NewLine)
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $Items = @($Value | ForEach-Object { "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$_) + "'" })
            return '@(' + ($Items -join ', ') + ')'
        }
        return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$Value) + "'"
    }

    $ParentDir = Split-Path -Path $Path -Parent
    if ($ParentDir -and -not (Test-Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
    }

    $Body = ConvertTo-OERPsd1Fragment -Value $Configuration -Indent 0
    Set-Content -Path $Path -Value $Body -Encoding UTF8
}
