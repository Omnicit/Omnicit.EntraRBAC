BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # The full example of the naming standard file, as the documentation shows it.
    $script:FullJson = @'
{
  "version": "1.0",
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

    # Builds a naming standard from JSON text through the real reader, the way Test-OERStructure will.
    function Get-StandardFromJson {
        param([string]$Json)
        $Path = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } { Read-OERNamingStandard -Path $Path }
    }

    # A minimal standard with the given segments (JSON array text) and separator.
    function Get-StandardFromSegments {
        param([string]$Segments, [string]$Separator = '-', [string]$Extra = '')
        Get-StandardFromJson -Json ('{ "version": "1.0", "separator": "' + $Separator + '", "sections": [ "groups" ], "segments": ' + $Segments + $Extra + ' }')
    }

    # Runs the name check and returns its results as an array (zero results is an empty array).
    function Test-Name {
        param([string]$Name, [object]$Standard)
        InModuleScope $script:moduleName -Parameters @{ Name = $Name; Standard = $Standard } {
            , @(Test-OERNamingStandardName -Name $Name -Standard $Standard)
        }
    }

    $script:Standard = Get-StandardFromJson -Json $script:FullJson
    $script:List = 'kind, area, purpose, environment (optional)'
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERNamingStandardName' {
    Context 'a name that follows the standard' {
        It 'gives no result for <Name>' -ForEach @(
            @{ Name = 'SG-Finance-Readers' }
            @{ Name = 'SG-Finance-Readers-Prod' }
            @{ Name = 'AU-IT-Owners2' }
            @{ Name = 'POL-Sales-Approvers-Test' }
        ) {
            $Result = Test-Name -Name $Name -Standard $script:Standard
            $Result.Count | Should -Be 0
        }

        It 'treats the missing optional segment as no finding' {
            (Test-Name -Name 'SG-Finance-Readers' -Standard $script:Standard).Count | Should -Be 0
        }
    }

    Context 'the separator' {
        It 'reports a name with no separator' {
            $Result = Test-Name -Name 'SG_Finance_Readers' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'separator'
            $Result[0].Segment | Should -BeNullOrEmpty
            $Result[0].SegmentName | Should -BeNullOrEmpty
            $Result[0].Detail | Should -Be "it does not contain the separator '-'; the standard expects at least 3 segments: $script:List, separated by '-'."
        }

        It 'reports an empty segment for <Name>' -ForEach @(
            @{ Name = 'SG--Readers' }
            @{ Name = '-SG-Finance-Readers' }
            @{ Name = 'SG-Finance-Readers-' }
            @{ Name = '-' }
            @{ Name = '' }
        ) {
            $Result = Test-Name -Name $Name -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'separator'
            $Result[0].Segment | Should -BeNullOrEmpty
            $Result[0].SegmentName | Should -BeNullOrEmpty
            $Result[0].Detail | Should -Be "a segment is empty: the name starts or ends with the separator '-' or holds it twice in a row; the standard expects the segments $script:List, separated by '-'."
        }

        It 'splits at the separator as text, never as a pattern' {
            $Dot = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" } ]' -Separator '.'
            (Test-Name -Name 'SG.Finance' -Standard $Dot).Count | Should -Be 0
            $Result = Test-Name -Name 'SGxFinance' -Standard $Dot
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'separator'

            $Pipe = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" } ]' -Separator '|'
            (Test-Name -Name 'SG|Finance' -Standard $Pipe).Count | Should -Be 0
            $Long = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" } ]' -Separator '__'
            (Test-Name -Name 'SG__Finance' -Standard $Long).Count | Should -Be 0
            (Test-Name -Name 'SG_Finance' -Standard $Long)[0].Rule | Should -Be 'separator'
        }

        It 'accepts a name without separator when only one segment is required' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area", "optional": true } ]'
            (Test-Name -Name 'SG' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Finance' -Standard $Std).Count | Should -Be 0
        }

        It 'accepts any single part when every segment is optional' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "a", "optional": true }, { "name": "b", "optional": true } ]'
            (Test-Name -Name 'x' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'x-y' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'x-y-z' -Standard $Std)[0].Rule | Should -Be 'segmentCount'
        }
    }

    Context 'the segment count' {
        It 'reports too few segments' {
            $Result = Test-Name -Name 'SG-Finance' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'segmentCount'
            $Result[0].Segment | Should -BeNullOrEmpty
            $Result[0].SegmentName | Should -BeNullOrEmpty
            $Result[0].Detail | Should -Be "it has 2 segments when split at '-', and the standard requires at least 3: $script:List, separated by '-'."
        }

        It 'reports too many segments' {
            $Result = Test-Name -Name 'SG-Finance-Readers-Prod-Extra' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'segmentCount'
            $Result[0].Detail | Should -Be "it has 5 segments when split at '-', and the standard allows at most 4: $script:List, separated by '-'."
        }

        It 'stops at the count and checks no segment' {
            # SG-Legal would break the values rule of segment 2, but the count is wrong first.
            $Result = Test-Name -Name 'SG-Legal' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'segmentCount'
        }
    }

    Context 'the allowed values' {
        It 'reports a value outside the closed list' {
            $Result = Test-Name -Name 'SG-Legal-Readers' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'values'
            $Result[0].Segment | Should -Be 2
            $Result[0].SegmentName | Should -Be 'area'
            $Result[0].Detail | Should -Be "'Legal' is not one of the allowed values 'Finance', 'Sales', 'IT'."
        }

        It 'adds a hint when the value differs only in letter case' {
            $Result = Test-Name -Name 'SG-finance-Readers' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'values'
            $Result[0].Segment | Should -Be 2
            $Result[0].Detail | Should -Be "'finance' is not one of the allowed values 'Finance', 'Sales', 'IT' (it differs from 'Finance' only in letter case)."
        }

        It 'reports a value in the optional segment' {
            $Result = Test-Name -Name 'SG-Finance-Readers-Dev' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Segment | Should -Be 4
            $Result[0].SegmentName | Should -Be 'environment'
            $Result[0].Detail | Should -Be "'Dev' is not one of the allowed values 'Prod', 'Test'."
        }

        It 'compares values ordinally, so a hidden character is a difference' {
            $Hidden = "SG-Finance$([char]0xAD)-Readers"
            $Result = Test-Name -Name $Hidden -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'values'
            $Result[0].Segment | Should -Be 2
        }

        It 'compares values literally, never as patterns (review focus 2)' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind", "values": [ "C++", "A.B" ] }, { "name": "purpose" } ]'
            (Test-Name -Name 'C++-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'A.B-Readers' -Standard $Std).Count | Should -Be 0
            $Cc = Test-Name -Name 'CCC-Readers' -Standard $Std
            $Cc.Count | Should -Be 1
            $Cc[0].Rule | Should -Be 'values'
            $Cc[0].Detail | Should -Be "'CCC' is not one of the allowed values 'C++', 'A.B'."
            $Ax = Test-Name -Name 'AxB-Readers' -Standard $Std
            $Ax.Count | Should -Be 1
            $Ax[0].Rule | Should -Be 'values'
        }
    }

    Context 'the letter case' {
        It 'reports a PascalCase segment that starts in lower case' {
            $Result = Test-Name -Name 'SG-Finance-readers' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'case'
            $Result[0].Segment | Should -Be 3
            $Result[0].SegmentName | Should -Be 'purpose'
            $Result[0].Detail | Should -Be "'readers' is not PascalCase (an uppercase letter first, then only letters and digits)."
        }

        It 'reports a PascalCase segment that holds a character other than a letter or digit' {
            $Result = Test-Name -Name 'SG-Finance-Read_ers' -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'case'
            $Result[0].Segment | Should -Be 3
        }

        It 'reports a values break and a case break of the same segment, values first' {
            $Result = Test-Name -Name 'sg-Finance-Readers' -Standard $script:Standard
            $Result.Count | Should -Be 2
            $Result[0].Rule | Should -Be 'values'
            $Result[0].Segment | Should -Be 1
            $Result[0].SegmentName | Should -Be 'kind'
            $Result[0].Detail | Should -Be "'sg' is not one of the allowed values 'SG', 'AU', 'CAT', 'AP', 'POL', 'AR' (it differs from 'SG' only in letter case)."
            $Result[1].Rule | Should -Be 'case'
            $Result[1].Segment | Should -Be 1
            $Result[1].Detail | Should -Be "'sg' is not UPPERCASE (no lowercase letter)."
        }

        It 'reports camelCase and lowercase breaks with their own texts' {
            $Camel = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" }, { "name": "purpose", "case": "camelCase" } ]'
            (Test-Name -Name 'SG-Finance-readersAll' -Standard $Camel).Count | Should -Be 0
            $R = Test-Name -Name 'SG-Finance-ReadersAll' -Standard $Camel
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'case'
            $R[0].Detail | Should -Be "'ReadersAll' is not camelCase (a lowercase letter first, then only letters and digits)."

            $Lower = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" }, { "name": "purpose", "case": "lowercase" } ]'
            (Test-Name -Name 'SG-Finance-readers' -Standard $Lower).Count | Should -Be 0
            (Test-Name -Name 'SG-Finance-readers1' -Standard $Lower).Count | Should -Be 0
            $L = Test-Name -Name 'SG-Finance-Readers' -Standard $Lower
            $L.Count | Should -Be 1
            $L[0].Rule | Should -Be 'case'
            $L[0].Detail | Should -Be "'Readers' is not lowercase (no uppercase letter)."
        }

        It 'treats non-ASCII letters as letters (review focus 4)' {
            $Pascal = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "purpose", "case": "PascalCase" } ]'
            $Upper = "$([char]0xC4)gare"
            $Lower = "$([char]0xE4)gare"
            (Test-Name -Name "SG-$Upper" -Standard $Pascal).Count | Should -Be 0
            $R = Test-Name -Name "SG-$Lower" -Standard $Pascal
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'case'
            $R[0].Detail | Should -Be "'$Lower' is not PascalCase (an uppercase letter first, then only letters and digits)."

            $Caps = Get-StandardFromSegments -Segments '[ { "name": "kind", "case": "UPPERCASE" } ]'
            (Test-Name -Name "$([char]0xC5)$([char]0xC4)$([char]0xD6)" -Standard $Caps).Count | Should -Be 0
            (Test-Name -Name "$([char]0xC5)$([char]0xE4)$([char]0xD6)" -Standard $Caps)[0].Rule | Should -Be 'case'
        }

        It 'treats non-ASCII letters as letters for camelCase and lowercase too' {
            $Camel = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "purpose", "case": "camelCase" } ]'
            (Test-Name -Name "SG-$([char]0xE4)Gare1" -Standard $Camel).Count | Should -Be 0
            (Test-Name -Name "SG-$([char]0xC4)gare" -Standard $Camel)[0].Rule | Should -Be 'case'

            $Lower = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "purpose", "case": "lowercase" } ]'
            (Test-Name -Name "SG-$([char]0xE4)gare" -Standard $Lower).Count | Should -Be 0
            (Test-Name -Name "SG-$([char]0xC4)gare" -Standard $Lower)[0].Rule | Should -Be 'case'
        }

        It 'lets UPPERCASE and lowercase accept digits and punctuation' {
            $Caps = Get-StandardFromSegments -Segments '[ { "name": "kind", "case": "UPPERCASE" }, { "name": "x", "case": "lowercase" } ]'
            (Test-Name -Name 'A1_B-c2.d' -Standard $Caps).Count | Should -Be 0
        }
    }

    Context 'the pattern' {
        It 'matches the whole segment (review focus 3)' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "area" }, { "name": "purpose", "pattern": "Fin" } ]'
            (Test-Name -Name 'SG-Finance-Fin' -Standard $Std).Count | Should -Be 0
            $R = Test-Name -Name 'SG-Finance-Finance' -Standard $Std
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'pattern'
            $R[0].Segment | Should -Be 3
            $R[0].SegmentName | Should -Be 'purpose'
            $R[0].Detail | Should -Be "'Finance' does not match the pattern 'Fin' (the whole segment must match)."
        }

        It 'is case-sensitive unless the pattern carries (?i)' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind", "pattern": "v[0-9]+" }, { "name": "area", "pattern": "(?i)ab" } ]'
            (Test-Name -Name 'v12-AB' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'V12-ab' -Standard $Std)[0].Rule | Should -Be 'pattern'
            (Test-Name -Name 'V12-ab' -Standard $Std).Count | Should -Be 1
        }
    }

    Context 'the maximum length' {
        BeforeAll {
            $script:Fits = 'SG-Finance-R' + ('a' * 52)    # 64 characters
        }

        It 'accepts a name of exactly the maximum length' {
            $script:Fits.Length | Should -Be 64
            (Test-Name -Name $script:Fits -Standard $script:Standard).Count | Should -Be 0
        }

        It 'reports a name one character over' {
            $Long = $script:Fits + 'a'
            $Long.Length | Should -Be 65
            $Result = Test-Name -Name $Long -Standard $script:Standard
            $Result.Count | Should -Be 1
            $Result[0].Rule | Should -Be 'maxLength'
            $Result[0].Segment | Should -BeNullOrEmpty
            $Result[0].SegmentName | Should -BeNullOrEmpty
            $Result[0].Detail | Should -Be 'it is 65 characters long; the standard allows at most 64.'
        }

        It 'reports the length first and the separator second' {
            $Name = 'SG_' + ('x' * 67)
            $Name.Length | Should -Be 70
            $Result = Test-Name -Name $Name -Standard $script:Standard
            $Result.Count | Should -Be 2
            $Result[0].Rule | Should -Be 'maxLength'
            $Result[1].Rule | Should -Be 'separator'
        }

        It 'sets no limit when the standard has none' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" } ]'
            (Test-Name -Name ('x' * 300) -Standard $Std).Count | Should -Be 0
        }
    }

    Context 'the exceptions' {
        It 'gives no result for a name an exception matches in full' {
            (Test-Name -Name 'All Users' -Standard $script:Standard).Count | Should -Be 0
        }

        It 'does not exempt a name that only starts with an exception (review focus 3)' {
            (Test-Name -Name 'All Users Copy' -Standard $script:Standard).Count | Should -BeGreaterThan 0
            (Test-Name -Name 'The All Users' -Standard $script:Standard).Count | Should -BeGreaterThan 0
        }

        It 'is case-sensitive unless the exception carries (?i)' {
            (Test-Name -Name 'all users' -Standard $script:Standard).Count | Should -BeGreaterThan 0
            (Test-Name -Name 'LEGACY-anything' -Standard $script:Standard).Count | Should -Be 0
            (Test-Name -Name 'legacy-Anything' -Standard $script:Standard).Count | Should -Be 0
        }

        It 'exempts a name before the length is checked' {
            $Name = 'legacy-' + ('x' * 100)
            (Test-Name -Name $Name -Standard $script:Standard).Count | Should -Be 0
        }
    }

    Context 'optional segments' {
        It 'forces an optional segment in the middle to be present when the count requires it' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "scope", "values": [ "Global", "Local" ], "optional": true }, { "name": "purpose" } ]'
            (Test-Name -Name 'SG-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Local-Readers' -Standard $Std).Count | Should -Be 0
            $R = Test-Name -Name 'SG-Other-Readers' -Standard $Std
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'values'
            $R[0].Segment | Should -Be 2
            $R[0].SegmentName | Should -Be 'scope'
        }

        It 'lets a part fit the first of two optional segments or fall through to the second' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "scope", "values": [ "Global", "Local" ], "optional": true }, { "name": "env", "values": [ "Prod", "Test" ], "optional": true }, { "name": "purpose" } ]'
            (Test-Name -Name 'SG-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Local-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Prod-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Local-Prod-Readers' -Standard $Std).Count | Should -Be 0
            $R = Test-Name -Name 'SG-Other-Readers' -Standard $Std
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'values'
            $R[0].Segment | Should -Be 3
            $R[0].SegmentName | Should -Be 'env'
        }

        It 'lets a pattern decide whether an optional segment is present' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "ver", "pattern": "v[0-9]+", "optional": true }, { "name": "env", "values": [ "Prod" ], "optional": true }, { "name": "purpose" } ]'
            (Test-Name -Name 'SG-v2-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Prod-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-v2-Prod-Readers' -Standard $Std).Count | Should -Be 0
        }

        It 'lets a letter case decide whether an optional segment is present' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "tag", "case": "lowercase", "optional": true }, { "name": "env", "values": [ "Prod" ], "optional": true }, { "name": "purpose" } ]'
            (Test-Name -Name 'SG-eu-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-Prod-Readers' -Standard $Std).Count | Should -Be 0
        }

        It 'leaves an unconstrained optional segment out when the name has no part left for it' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "tag", "optional": true }, { "name": "purpose", "case": "PascalCase" } ]'
            (Test-Name -Name 'SG-Readers' -Standard $Std).Count | Should -Be 0
            (Test-Name -Name 'SG-eu-Readers' -Standard $Std).Count | Should -Be 0
            $R = Test-Name -Name 'SG-readers' -Standard $Std
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'case'
            $R[0].Segment | Should -Be 3
            $R[0].SegmentName | Should -Be 'purpose'
        }

        It 'reports the break of an optional segment under its own position' {
            $Std = Get-StandardFromSegments -Segments '[ { "name": "kind" }, { "name": "tag", "case": "lowercase", "optional": true }, { "name": "purpose" } ]'
            $R = Test-Name -Name 'SG-EU-Readers' -Standard $Std
            $R.Count | Should -Be 1
            $R[0].Rule | Should -Be 'case'
            $R[0].Segment | Should -Be 2
            $R[0].SegmentName | Should -Be 'tag'
        }
    }

    Context 'a name that holds characters a pattern would read specially (review focus 2)' {
        It 'never throws for <Text>' -ForEach @(
            @{ Text = 'an opening parenthesis'; Name = 'SG(-Finance-Readers' }
            @{ Text = 'an opening bracket'; Name = 'SG[-Finance-Readers' }
            @{ Text = 'a backslash'; Name = 'SG\-Finance-Readers' }
            @{ Text = 'only metacharacters'; Name = '(.*)[+]?{1}\' }
            @{ Text = 'an unmatched group at the end'; Name = 'SG-Finance-Readers(' }
            @{ Text = 'a line break'; Name = "SG-Finance-Readers`n" }
        ) {
            { Test-Name -Name $Name -Standard $script:Standard } | Should -Not -Throw
            (Test-Name -Name $Name -Standard $script:Standard).Count | Should -BeGreaterThan 0
        }

        It 'refuses a trailing line feed on a segment' {
            $R = Test-Name -Name "SG-Finance-Readers`n" -Standard $script:Standard
            ($R | Where-Object { $_.Rule -eq 'case' }).Count | Should -Be 1
        }
    }

    Context 'the result shape' {
        It 'returns objects with exactly Rule, Segment, SegmentName and Detail' {
            $R = Test-Name -Name 'SG-Legal-Readers' -Standard $script:Standard
            $R[0].PSObject.Properties.Name | Should -Be @('Rule', 'Segment', 'SegmentName', 'Detail')
            $R[0].Segment | Should -BeOfType ([int])
        }
    }
}
