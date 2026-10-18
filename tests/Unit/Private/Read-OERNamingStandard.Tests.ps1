BeforeDiscovery {
    # Builds a naming standard file. A part passed as '' is left out of the file, so a test can omit a
    # required key; every other part is JSON text, written exactly as the test passes it.
    function New-StandardJson {
        param(
            [string]$Version = '"1.0"',
            [string]$Separator = '"-"',
            [string]$MaxLength = '',
            [string]$Sections = '[ "groups" ]',
            [string]$Segments = '[ { "name": "x" } ]',
            [string]$Extra = ''
        )
        $Parts = [System.Collections.Generic.List[string]]::new()
        if ($Version) { $Parts.Add('"version": ' + $Version) }
        if ($Separator) { $Parts.Add('"separator": ' + $Separator) }
        if ($MaxLength) { $Parts.Add('"maxLength": ' + $MaxLength) }
        if ($Sections) { $Parts.Add('"sections": ' + $Sections) }
        if ($Segments) { $Parts.Add('"segments": ' + $Segments) }
        if ($Extra) { $Parts.Add($Extra) }
        '{ ' + ($Parts -join ', ') + ' }'
    }

    # Every refusal the reader makes. SchemaRefuses is true when draft-07 refuses the same file; the
    # three reader-only rules (a pattern that does not compile, an exception that does not compile, a
    # value that contains the separator) are accepted by Test-Json, which is why the reader checks them.
    $RefusalCases = @(
        @{ Name = 'a missing version'; Json = (New-StandardJson -Version ''); Path = 'version'; SchemaRefuses = $true }
        @{ Name = 'version 2.0'; Json = (New-StandardJson -Version '"2.0"'); Path = 'version'; SchemaRefuses = $true }
        @{ Name = 'a version that is a number'; Json = (New-StandardJson -Version '1.0'); Path = 'version'; SchemaRefuses = $true }
        @{ Name = 'a missing separator'; Json = (New-StandardJson -Separator ''); Path = 'separator'; SchemaRefuses = $true }
        @{ Name = 'an empty separator'; Json = (New-StandardJson -Separator '""'); Path = 'separator'; SchemaRefuses = $true }
        @{ Name = 'a separator that is a number'; Json = (New-StandardJson -Separator '5'); Path = 'separator'; SchemaRefuses = $true }
        @{ Name = 'maxLength 0'; Json = (New-StandardJson -MaxLength '0'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'maxLength 257'; Json = (New-StandardJson -MaxLength '257'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'maxLength 12.5'; Json = (New-StandardJson -MaxLength '12.5'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'maxLength as a string'; Json = (New-StandardJson -MaxLength '"64"'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'maxLength true'; Json = (New-StandardJson -MaxLength 'true'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'maxLength null'; Json = (New-StandardJson -MaxLength 'null'); Path = 'maxLength'; SchemaRefuses = $true }
        @{ Name = 'a missing sections'; Json = (New-StandardJson -Sections ''); Path = 'sections'; SchemaRefuses = $true }
        @{ Name = 'an empty sections'; Json = (New-StandardJson -Sections '[ ]'); Path = 'sections'; SchemaRefuses = $true }
        @{ Name = 'sections that is a string'; Json = (New-StandardJson -Sections '"groups"'); Path = 'sections'; SchemaRefuses = $true }
        @{ Name = 'a repeated section'; Json = (New-StandardJson -Sections '[ "groups", "groups" ]'); Path = 'sections[1]'; SchemaRefuses = $true }
        @{ Name = 'a section in the wrong letter case'; Json = (New-StandardJson -Sections '[ "Groups" ]'); Path = 'sections[0]'; SchemaRefuses = $true }
        @{ Name = 'an unknown section'; Json = (New-StandardJson -Sections '[ "groups", "roleAssignments" ]'); Path = 'sections[1]'; SchemaRefuses = $true }
        @{ Name = 'a section that is a number'; Json = (New-StandardJson -Sections '[ 1 ]'); Path = 'sections[0]'; SchemaRefuses = $true }
        @{ Name = 'a missing segments'; Json = (New-StandardJson -Segments ''); Path = 'segments'; SchemaRefuses = $true }
        @{ Name = 'an empty segments'; Json = (New-StandardJson -Segments '[ ]'); Path = 'segments'; SchemaRefuses = $true }
        @{ Name = 'segments that is an object'; Json = (New-StandardJson -Segments '{ "name": "x" }'); Path = 'segments'; SchemaRefuses = $true }
        @{ Name = 'a segment that is a string'; Json = (New-StandardJson -Segments '[ "x" ]'); Path = 'segments[0]'; SchemaRefuses = $true }
        @{ Name = 'a segment that is null'; Json = (New-StandardJson -Segments '[ { "name": "a" }, null ]'); Path = 'segments[1]'; SchemaRefuses = $true }
        @{ Name = 'a segment without a name'; Json = (New-StandardJson -Segments '[ { "values": [ "A" ] } ]'); Path = 'segments[0].name'; SchemaRefuses = $true }
        @{ Name = 'an empty segment name'; Json = (New-StandardJson -Segments '[ { "name": "" } ]'); Path = 'segments[0].name'; SchemaRefuses = $true }
        @{ Name = 'a segment name that is a number'; Json = (New-StandardJson -Segments '[ { "name": 7 } ]'); Path = 'segments[0].name'; SchemaRefuses = $true }
        @{ Name = 'a segment with both values and pattern'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ "A" ], "pattern": "A" } ]'); Path = 'segments[0]'; SchemaRefuses = $true }
        @{ Name = 'empty values'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ ] } ]'); Path = 'segments[0].values'; SchemaRefuses = $true }
        @{ Name = 'values that is a string'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": "A" } ]'); Path = 'segments[0].values'; SchemaRefuses = $true }
        @{ Name = 'a repeated value'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ "A", "A" ] } ]'); Path = 'segments[0].values[1]'; SchemaRefuses = $true }
        @{ Name = 'an empty value'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ "" ] } ]'); Path = 'segments[0].values[0]'; SchemaRefuses = $true }
        @{ Name = 'a value that is a number'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ "A", 2 ] } ]'); Path = 'segments[0].values[1]'; SchemaRefuses = $true }
        @{ Name = 'a segment description that is a number'; Json = (New-StandardJson -Segments '[ { "name": "x", "description": 5 } ]'); Path = 'segments[0].description'; SchemaRefuses = $true }
        @{ Name = 'an empty pattern'; Json = (New-StandardJson -Segments '[ { "name": "x", "pattern": "" } ]'); Path = 'segments[0].pattern'; SchemaRefuses = $true }
        @{ Name = 'a pattern that is a number'; Json = (New-StandardJson -Segments '[ { "name": "x", "pattern": 3 } ]'); Path = 'segments[0].pattern'; SchemaRefuses = $true }
        @{ Name = 'case Pascal'; Json = (New-StandardJson -Segments '[ { "name": "a" }, { "name": "x", "case": "Pascal" } ]'); Path = 'segments[1].case'; SchemaRefuses = $true }
        @{ Name = 'case pascalcase'; Json = (New-StandardJson -Segments '[ { "name": "x", "case": "pascalcase" } ]'); Path = 'segments[0].case'; SchemaRefuses = $true }
        @{ Name = 'optional as a string'; Json = (New-StandardJson -Segments '[ { "name": "x", "optional": "yes" } ]'); Path = 'segments[0].optional'; SchemaRefuses = $true }
        @{ Name = 'includeSyncedGroups as a string'; Json = (New-StandardJson -Extra '"includeSyncedGroups": "true"'); Path = 'includeSyncedGroups'; SchemaRefuses = $true }
        @{ Name = 'an empty exception'; Json = (New-StandardJson -Extra '"exceptions": [ "" ]'); Path = 'exceptions[0]'; SchemaRefuses = $true }
        @{ Name = 'exceptions that is a string'; Json = (New-StandardJson -Extra '"exceptions": "All Users"'); Path = 'exceptions'; SchemaRefuses = $true }
        @{ Name = 'an exception that is a number'; Json = (New-StandardJson -Extra '"exceptions": [ "a", 4 ]'); Path = 'exceptions[1]'; SchemaRefuses = $true }
        @{ Name = 'a description that is a number'; Json = (New-StandardJson -Extra '"description": 42'); Path = 'description'; SchemaRefuses = $true }
        @{ Name = 'an unknown root key seperator'; Json = (New-StandardJson -Extra '"seperator": "-"'); Path = 'seperator'; SchemaRefuses = $true }
        @{ Name = 'a root key in the wrong letter case'; Json = (New-StandardJson -Version '' -Extra '"Version": "1.0"'); Path = 'Version'; SchemaRefuses = $true }
        @{ Name = 'an unknown segment key allowed'; Json = (New-StandardJson -Segments '[ { "name": "x", "allowed": [ "A" ] } ]'); Path = 'segments[0].allowed'; SchemaRefuses = $true }
        @{ Name = 'a version with a hidden character'; Json = (New-StandardJson -Version '"1.0\u00AD"'); Path = 'version'; SchemaRefuses = $true }
        @{ Name = 'a section with a hidden character'; Json = (New-StandardJson -Sections '[ "groups\u200B" ]'); Path = 'sections[0]'; SchemaRefuses = $true }
        @{ Name = 'a case with a hidden character'; Json = (New-StandardJson -Segments '[ { "name": "x", "case": "lowercase\u00AD" } ]'); Path = 'segments[0].case'; SchemaRefuses = $true }
        @{ Name = 'a root key with a hidden character'; Json = (New-StandardJson -Extra '"separator\u00AD": "-"'); Path = 'separator'; SchemaRefuses = $true }
        @{ Name = 'a pattern that does not compile'; Json = (New-StandardJson -Segments '[ { "name": "x", "pattern": "(" } ]'); Path = 'segments[0].pattern'; SchemaRefuses = $false }
        @{ Name = 'an exception that does not compile'; Json = (New-StandardJson -Extra '"exceptions": [ "[a-" ]'); Path = 'exceptions[0]'; SchemaRefuses = $false }
        @{ Name = 'a value that contains the separator'; Json = (New-StandardJson -Segments '[ { "name": "x", "values": [ "A-B" ] } ]'); Path = 'segments[0].values[0]'; SchemaRefuses = $false }
    )

}

BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # The smallest valid file, and the same with maxLength written as 64.0.
    $script:MinimalJson = '{ "version": "1.0", "separator": "-", "sections": [ "groups" ], "segments": [ { "name": "x" } ] }'
    $script:MaxLengthFloatJson = '{ "version": "1.0", "separator": "-", "maxLength": 64.0, "sections": [ "groups" ], "segments": [ { "name": "x" } ] }'

    # The full example of the naming standard file, as the documentation shows it.
    $script:FullJson = @'
{
  "$schema": "./naming-standard.schema.json",
  "version": "1.0",
  "description": "free text, optional",
  "separator": "-",
  "maxLength": 64,
  "sections": [ "groups", "administrativeUnits", "catalogs", "accessPackages", "assignmentPolicies", "accessReviews" ],
  "includeSyncedGroups": false,
  "segments": [
    { "name": "kind", "values": [ "SG", "AU", "CAT", "AP", "POL", "AR" ], "case": "UPPERCASE" },
    { "name": "area", "values": [ "Finance", "Sales", "IT" ] },
    { "name": "purpose", "case": "PascalCase" },
    { "name": "environment", "values": [ "Prod", "Test" ], "optional": true }
  ],
  "exceptions": [ "All Users", "(?i)legacy-.*" ]
}
'@

    # Writes a file under $TestDrive (UTF-8, no BOM) and returns its path.
    function Write-StandardFile {
        param([string]$Json, [string]$Name = 'naming-standard.json')
        $Path = Join-Path -Path $TestDrive -ChildPath $Name
        [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
        $Path
    }

    # Reads a file with the reader and returns the thrown message, or $null when it did not throw.
    function Get-ReadFailure {
        param([string]$Path)
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
            $Message = $null
            try { $null = Read-OERNamingStandard -Path $Path } catch { $Message = $PSItem.Exception.Message }
            $Message
        }
    }

    # Reads a file with the reader and returns the standard.
    function Read-Standard {
        param([string]$Path)
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
            Read-OERNamingStandard -Path $Path
        }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Read-OERNamingStandard' {
    Context 'a valid file' {
        It 'returns the normalized object for the full example' {
            $Std = Read-Standard -Path (Write-StandardFile -Json $script:FullJson)

            $Std.PSObject.Properties.Name | Sort-Object | Should -Be @(
                'Exceptions', 'IncludeSyncedGroups', 'MaxLength', 'Sections', 'Segments', 'Separator')
            $Std.Separator | Should -Be '-'
            $Std.MaxLength | Should -Be 64
            $Std.MaxLength | Should -BeOfType ([int])
            $Std.IncludeSyncedGroups | Should -BeFalse
            $Std.IncludeSyncedGroups | Should -BeOfType ([bool])
            , $Std.Sections | Should -BeOfType ([string[]])
            $Std.Sections | Should -Be @('groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'assignmentPolicies', 'accessReviews')

            , $Std.Segments | Should -BeOfType ([object[]])
            $Std.Segments.Count | Should -Be 4
            ($Std.Segments | ForEach-Object { $_.Position }) | Should -Be @(1, 2, 3, 4)
            ($Std.Segments | ForEach-Object { $_.Name }) | Should -Be @('kind', 'area', 'purpose', 'environment')
            ($Std.Segments | ForEach-Object { $_.Optional }) | Should -Be @($false, $false, $false, $true)
            $Std.Segments[0].PSObject.Properties.Name | Sort-Object | Should -Be @(
                'Case', 'Name', 'Optional', 'Pattern', 'Position', 'Regex', 'Values')
            , $Std.Segments[0].Values | Should -BeOfType ([string[]])
            $Std.Segments[0].Values | Should -Be @('SG', 'AU', 'CAT', 'AP', 'POL', 'AR')
            $Std.Segments[0].Case | Should -Be 'UPPERCASE'
            $Std.Segments[0].Pattern | Should -BeNullOrEmpty
            $Std.Segments[0].Regex | Should -BeNullOrEmpty
            $Std.Segments[1].Case | Should -BeNullOrEmpty
            $Std.Segments[2].Values | Should -BeNullOrEmpty
            $Std.Segments[2].Case | Should -Be 'PascalCase'

            , $Std.Exceptions | Should -BeOfType ([object[]])
            $Std.Exceptions.Count | Should -Be 2
            $Std.Exceptions[0].PSObject.Properties.Name | Sort-Object | Should -Be @('Pattern', 'Regex')
            $Std.Exceptions[0].Pattern | Should -Be 'All Users'
            $Std.Exceptions[1].Pattern | Should -Be '(?i)legacy-.*'
        }

        It 'returns the defaults for a minimal file' {
            $Std = Read-Standard -Path (Write-StandardFile -Json $script:MinimalJson)

            $Std.MaxLength | Should -BeNullOrEmpty
            $Std.IncludeSyncedGroups | Should -BeFalse
            $Std.Separator | Should -Be '-'
            $Std.Sections.Count | Should -Be 1
            $Std.Segments.Count | Should -Be 1
            , $Std.Segments | Should -BeOfType ([object[]])
            $Std.Segments[0].Name | Should -Be 'x'
            $Std.Segments[0].Position | Should -Be 1
            $Std.Segments[0].Optional | Should -BeFalse
            , $Std.Exceptions | Should -BeOfType ([object[]])
            $Std.Exceptions.Count | Should -Be 0
        }

        It 'reads a file saved with a UTF-8 byte order mark exactly like one without (review focus 1)' {
            $Bom = [byte[]](0xEF, 0xBB, 0xBF)
            $Body = [System.Text.UTF8Encoding]::new($false).GetBytes($script:FullJson)
            $Path = Join-Path -Path $TestDrive -ChildPath 'bom.json'
            [System.IO.File]::WriteAllBytes($Path, [byte[]]($Bom + $Body))
            ([System.IO.File]::ReadAllBytes($Path))[0] | Should -Be 0xEF -Because 'the fixture must start with the byte order mark'

            $WithBom = Read-Standard -Path $Path
            $Without = Read-Standard -Path (Write-StandardFile -Json $script:FullJson -Name 'plain.json')

            $WithBom.Separator | Should -Be $Without.Separator
            $WithBom.MaxLength | Should -Be $Without.MaxLength
            $WithBom.Segments.Count | Should -Be $Without.Segments.Count
            $WithBom.Exceptions.Count | Should -Be $Without.Exceptions.Count
            $WithBom.Sections | Should -Be $Without.Sections
        }

        It 'reads includeSyncedGroups true' {
            $Std = Read-Standard -Path (Write-StandardFile -Json $script:MinimalJson.Replace('"-",', '"-", "includeSyncedGroups": true,'))
            $Std.IncludeSyncedGroups | Should -BeTrue
            $Std.IncludeSyncedGroups | Should -BeOfType ([bool])
        }
        It 'accepts maxLength 64.0 as the integer 64' {
            $Std = Read-Standard -Path (Write-StandardFile -Json $script:MaxLengthFloatJson)
            $Std.MaxLength | Should -Be 64
            $Std.MaxLength | Should -BeOfType ([int])
        }

        It 'accepts maxLength at both ends of its range' {
            $One = $script:MinimalJson.Replace('"-",', '"-", "maxLength": 1,')
            $Top = $script:MinimalJson.Replace('"-",', '"-", "maxLength": 256,')
            (Read-Standard -Path (Write-StandardFile -Json $One -Name 'one.json')).MaxLength | Should -Be 1
            (Read-Standard -Path (Write-StandardFile -Json $Top -Name 'top.json')).MaxLength | Should -Be 256
        }

        It 'compiles a pattern and an exception as a whole-text match (review focus 3)' {
            $Json = $script:MinimalJson.Replace('{ "name": "x" }', '{ "name": "x", "pattern": "Fin" }').Replace('"-",', '"-", "exceptions": [ "All Users", "(?i)legacy-.*" ],')
            $Std = Read-Standard -Path (Write-StandardFile -Json $Json)

            $Std.Segments[0].Pattern | Should -Be 'Fin'
            $Std.Segments[0].Regex | Should -BeOfType ([regex])
            $Std.Segments[0].Regex.IsMatch('Fin') | Should -BeTrue
            $Std.Segments[0].Regex.IsMatch('Finance') | Should -BeFalse -Because 'a pattern must match the whole segment'
            $Std.Segments[0].Regex.IsMatch('xFin') | Should -BeFalse
            $Std.Segments[0].Regex.IsMatch("Fin`n") | Should -BeFalse -Because 'the end anchor must not allow a trailing line feed'
            $Std.Exceptions[0].Regex | Should -BeOfType ([regex])
            $Std.Exceptions[0].Regex.IsMatch('All Users') | Should -BeTrue
            $Std.Exceptions[0].Regex.IsMatch('All Users Copy') | Should -BeFalse
            $Std.Exceptions[0].Regex.IsMatch('all users') | Should -BeFalse -Because 'a pattern is case-sensitive unless it carries (?i)'
            $Std.Exceptions[1].Regex.IsMatch('LEGACY-anything') | Should -BeTrue
            $Std.Exceptions[1].Regex.IsMatch('xlegacy-anything') | Should -BeFalse
        }

        It 'keeps an alternation inside the anchors' {
            $Json = $script:MinimalJson.Replace('{ "name": "x" }', '{ "name": "x", "pattern": "A|B" }')
            $Std = Read-Standard -Path (Write-StandardFile -Json $Json)
            $Std.Segments[0].Regex.IsMatch('A') | Should -BeTrue
            $Std.Segments[0].Regex.IsMatch('B') | Should -BeTrue
            $Std.Segments[0].Regex.IsMatch('AB') | Should -BeFalse
            $Std.Segments[0].Regex.IsMatch('xB') | Should -BeFalse
        }
    }

    Context 'a file that breaks the standard' {
        It 'refuses <Name> naming <Path>' -ForEach $RefusalCases {
            $File = Write-StandardFile -Json $Json
            $Message = Get-ReadFailure -Path $File

            $Message | Should -Not -BeNullOrEmpty -Because 'the reader must refuse this file'
            $Message | Should -Match ('^' + [regex]::Escape("The naming standard at '$File' is not valid: "))
            $Message | Should -Match ([regex]::Escape($Path))
            $Body = $Message.Substring("The naming standard at '$File' is not valid: ".Length)
            $Body | Should -BeLike ($Path.Replace('[', '`[').Replace(']', '`]') + '*') -Because 'the first problem must start with its JSON path'
        }

        It 'words the problems exactly' {
            $Texts = [ordered]@{
                'version-2'    = @($script:FullJson.Replace('"version": "1.0"', '"version": "2.0"'), "version must be the string '1.0'; found '2.0'.")
                'maxlength'    = @($script:FullJson.Replace('"maxLength": 64', '"maxLength": 12.5'), 'maxLength must be an integer from 1 to 256; found 12.5.')
                'section-case' = @($script:FullJson.Replace('[ "groups", "administrativeUnits"', '[ "Groups", "administrativeUnits"'), "sections[0] must be one of groups, administrativeUnits, catalogs, accessPackages, assignmentPolicies, accessReviews; found 'Groups'.")
                'case'         = @($script:FullJson.Replace('"PascalCase"', '"Pascal"'), "segments[2].case must be one of PascalCase, camelCase, UPPERCASE, lowercase; found 'Pascal'.")
                'unknown-root' = @($script:FullJson.Replace('"separator": "-",', '"seperator": "-",'), 'seperator is not a known key; expected one of $schema, version, description, separator, maxLength, sections, includeSyncedGroups, segments, exceptions.')
                'separator-in' = @($script:FullJson.Replace('"SG", "AU"', '"SG", "A-U"'), "segments[0].values[1] is 'A-U', which contains the separator '-' and could never match a segment; remove the separator from it.")
                'segment-str'  = @($script:MinimalJson.Replace('{ "name": "x" }', '"x"'), "segments[0] must be an object; found 'x'.")
                'section-dup'  = @($script:FullJson.Replace('[ "groups", "administrativeUnits"', '[ "groups", "groups"'), "sections[1] repeats 'groups', which sections[0] already lists; list each section once.")
                'sections-str' = @($script:MinimalJson.Replace('[ "groups" ]', '"groups"'), "sections must be an array of section names; found 'groups'.")
                'segments-obj' = @($script:MinimalJson.Replace('[ { "name": "x" } ]', '{ "name": "x" }'), 'segments must be an array of segment objects; found an object.')
                'values-str'   = @($script:MinimalJson.Replace('{ "name": "x" }', '{ "name": "x", "values": "A" }'), "segments[0].values must be an array of strings; found 'A'.")
                'exceptions'   = @($script:MinimalJson.Replace('"-",', '"-", "exceptions": "All Users",'), "exceptions must be an array of regular expressions; found 'All Users'.")
                'name-missing' = @($script:MinimalJson.Replace('{ "name": "x" }', '{ "values": [ "A" ] }'), 'segments[0].name is required but missing.')
                'both'         = @($script:FullJson.Replace('"area", "values": [ "Finance", "Sales", "IT" ]', '"area", "pattern": "x", "values": [ "Finance" ]'), 'segments[1] must not declare both values and pattern; use one of them.')
            }
            foreach ($Key in $Texts.Keys) {
                $Message = Get-ReadFailure -Path (Write-StandardFile -Json $Texts[$Key][0] -Name "$Key.json")
                $Message | Should -Match ([regex]::Escape($Texts[$Key][1])) -Because "case $Key"
            }
        }

        It 'reports a pattern that does not compile once, as itself, and does not wrap it' {
            $Json = $script:MinimalJson.Replace('{ "name": "x" }', '{ "name": "x", "pattern": "a)(b" }')
            $Message = Get-ReadFailure -Path (Write-StandardFile -Json $Json)
            $Message | Should -Match 'segments\[0\]\.pattern must be a valid \.NET regular expression'
            $Message | Should -Match ([regex]::Escape("found 'a)(b'"))
            ([regex]::Matches($Message, 'segments\[0\]\.pattern')).Count | Should -Be 1
        }

        It 'reports a pattern that compiles alone but not inside the anchors without throwing' {
            # In (?x) mode a comment runs to the end of the line, so it swallows the closing group.
            $Json = $script:MinimalJson.Replace('{ "name": "x" }', '{ "name": "x", "pattern": "(?x)ab # note" }')
            $Message = Get-ReadFailure -Path (Write-StandardFile -Json $Json)
            $Message | Should -Match 'segments\[0\]\.pattern must be a valid \.NET regular expression'
        }

        It 'collects every problem and throws once naming all of them' {
            $Json = $script:FullJson.Replace('"separator": "-",', '"seperator": "-", "separator": "-",').Replace('"PascalCase"', '"Pascal"').Replace('"values": [ "Finance", "Sales", "IT" ]', '"values": [ ]')
            $Message = Get-ReadFailure -Path (Write-StandardFile -Json $Json)

            $Message | Should -Not -BeNullOrEmpty
            $Message | Should -Match 'seperator'
            $Message | Should -Match ([regex]::Escape('segments[2].case'))
            $Message | Should -Match ([regex]::Escape('segments[1].values'))
            ([regex]::Matches($Message, 'The naming standard at')).Count | Should -Be 1
        }
        It 'throws a message that starts with the path as given' {
            $File = Write-StandardFile -Json (New-Object psobject | ConvertTo-Json) -Name 'rootonly.json'
            $Message = Get-ReadFailure -Path $File
            $Message | Should -Match ('^' + [regex]::Escape("The naming standard at '$File' is not valid: "))
            $Message | Should -Match 'version is required but missing\.'
            $Message | Should -Match 'separator is required but missing\.'
            $Message | Should -Match 'sections is required but missing\.'
            $Message | Should -Match 'segments is required but missing\.'
        }
    }

    Context 'a path that is not a usable file' {
        It 'throws for a file that does not exist' {
            $Missing = Join-Path -Path $TestDrive -ChildPath 'missing.json'
            Get-ReadFailure -Path $Missing | Should -Be "The naming standard was not found at path '$Missing'."
        }

        It 'throws for a directory path' {
            Get-ReadFailure -Path $TestDrive | Should -Be "The naming standard was not found at path '$TestDrive'."
        }

        It 'throws for an empty file' {
            $File = Write-StandardFile -Json '' -Name 'empty.json'
            Get-ReadFailure -Path $File | Should -Be "The naming standard at '$File' is empty."
        }

        It 'throws for a file that holds only white space' {
            $File = Write-StandardFile -Json "  `r`n  " -Name 'blank.json'
            Get-ReadFailure -Path $File | Should -Be "The naming standard at '$File' is empty."
        }

        It 'throws for malformed JSON' {
            $File = Write-StandardFile -Json '{ bad' -Name 'bad.json'
            Get-ReadFailure -Path $File | Should -BeLike "The naming standard at '$File' is not valid JSON: *"
        }

        It 'removes the parser error record before it throws for malformed JSON' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
            $File = Write-StandardFile -Json '{ bad' -Name 'bad2.json'
            Get-ReadFailure -Path $File | Should -BeLike "The naming standard at '$File' is not valid JSON: *"
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        }
        It 'throws when the root is not one JSON object: <Text>' -ForEach @(
            @{ Text = 'an empty array'; Json = '[ ]' }
            @{ Text = 'an array holding one object'; Json = '[ { "version": "1.0" } ]' }
            @{ Text = 'null'; Json = 'null' }
            @{ Text = 'a number'; Json = '42' }
            @{ Text = 'a string'; Json = '"text"' }
        ) {
            $File = Write-StandardFile -Json $Json -Name 'root.json'
            Get-ReadFailure -Path $File | Should -Be "The naming standard at '$File' must be a single JSON object."
        }
    }

    Context 'agreement with the schema' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        It 'agrees with the reader on <Name>' -ForEach $RefusalCases {
            $Schema = InModuleScope $script:moduleName { Get-OERNamingStandardSchemaJson }
            $Accepted = Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue
            if ($SchemaRefuses) {
                $Accepted | Should -BeFalse -Because 'draft-07 refuses this file as the reader does'
            } else {
                $Accepted | Should -BeTrue -Because 'draft-07 cannot express this rule, so the reader checks it itself'
            }
        }

        It 'accepts the full example, the minimal file and maxLength 64.0' {
            $Schema = InModuleScope $script:moduleName { Get-OERNamingStandardSchemaJson }
            Test-Json -Json $script:FullJson -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
            Test-Json -Json $script:MinimalJson -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
            Test-Json -Json $script:MaxLengthFloatJson -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }
}
