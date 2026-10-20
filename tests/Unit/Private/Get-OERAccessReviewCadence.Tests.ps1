BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERAccessReviewCadence -Cadence (cadence to Graph pattern)' {
    It '<Cadence> is pattern type <PatternType> interval <Interval>' -ForEach @(
        @{ Cadence = 'OneTime';      PatternType = $null;              Interval = $null }
        @{ Cadence = 'Weekly';       PatternType = 'weekly';           Interval = 1 }
        @{ Cadence = 'Monthly';      PatternType = 'absoluteMonthly';  Interval = 1 }
        @{ Cadence = 'Quarterly';    PatternType = 'absoluteMonthly';  Interval = 3 }
        @{ Cadence = 'SemiAnnually'; PatternType = 'absoluteMonthly';  Interval = 6 }
        @{ Cadence = 'Annually';     PatternType = 'absoluteMonthly';  Interval = 12 }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Cadence = $Cadence; PatternType = $PatternType; Interval = $Interval } {
            param($Cadence, $PatternType, $Interval)
            $Shape = Get-OERAccessReviewCadence -Cadence $Cadence
            $Shape.Cadence        | Should -BeExactly $Cadence
            $Shape.PatternType    | Should -BeExactly $PatternType
            $Shape.Interval       | Should -Be $Interval
            $Shape.Representable  | Should -BeTrue
            if ($null -ne $Interval) { $Shape.Interval | Should -BeOfType [int] }
        }
    }

    It 'reads a cadence in any letter case and answers with the canonical spelling' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERAccessReviewCadence -Cadence 'semiannually').Cadence | Should -BeExactly 'SemiAnnually'
            (Get-OERAccessReviewCadence -Cadence 'WEEKLY').PatternType   | Should -BeExactly 'weekly'
            (Get-OERAccessReviewCadence -Cadence 'quarterly').Interval   | Should -Be 3
        }
    }

    It 'refuses a name that is not a cadence' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERAccessReviewCadence -Cadence 'Biweekly' } | Should -Throw "*'Biweekly' is not an access review cadence*"
        }
    }
}

Describe 'Get-OERAccessReviewCadence -PatternType -Interval (live pattern to cadence)' {
    It 'names a representable <Type> interval <Interval> pattern <Cadence>' -ForEach @(
        @{ Type = 'weekly';          Interval = 1;  Cadence = 'Weekly' }
        @{ Type = 'absoluteMonthly'; Interval = 1;  Cadence = 'Monthly' }
        @{ Type = 'absoluteMonthly'; Interval = 3;  Cadence = 'Quarterly' }
        @{ Type = 'absoluteMonthly'; Interval = 6;  Cadence = 'SemiAnnually' }
        @{ Type = 'absoluteMonthly'; Interval = 12; Cadence = 'Annually' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Type = $Type; Interval = $Interval; Cadence = $Cadence } {
            param($Type, $Interval, $Cadence)
            $Shape = Get-OERAccessReviewCadence -PatternType $Type -Interval $Interval
            $Shape.Cadence       | Should -BeExactly $Cadence
            $Shape.Representable | Should -BeTrue
            $Shape.PatternType   | Should -BeExactly $Type
            $Shape.Interval      | Should -Be $Interval
        }
    }

    It 'collapses a <Type> interval <Interval> pattern onto <Cadence> and says it is not representable' -ForEach @(
        @{ Type = 'weekly';          Interval = 2;  Cadence = 'Weekly';  SentType = 'weekly';          SentInterval = 1 }
        @{ Type = 'weekly';          Interval = 0;  Cadence = 'Weekly';  SentType = 'weekly';          SentInterval = 1 }
        @{ Type = 'absoluteMonthly'; Interval = 2;  Cadence = 'Monthly'; SentType = 'absoluteMonthly'; SentInterval = 1 }
        @{ Type = 'absoluteMonthly'; Interval = 4;  Cadence = 'Monthly'; SentType = 'absoluteMonthly'; SentInterval = 1 }
        @{ Type = 'absoluteMonthly'; Interval = 0;  Cadence = 'Monthly'; SentType = 'absoluteMonthly'; SentInterval = 1 }
        @{ Type = 'absoluteMonthly'; Interval = 24; Cadence = 'Monthly'; SentType = 'absoluteMonthly'; SentInterval = 1 }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Type = $Type; Interval = $Interval; Cadence = $Cadence; SentType = $SentType; SentInterval = $SentInterval } {
            param($Type, $Interval, $Cadence, $SentType, $SentInterval)
            $Shape = Get-OERAccessReviewCadence -PatternType $Type -Interval $Interval
            $Shape.Cadence       | Should -BeExactly $Cadence
            $Shape.Representable | Should -BeFalse
            # PatternType and Interval are what a rebuild from the collapsed cadence would send.
            $Shape.PatternType   | Should -BeExactly $SentType
            $Shape.Interval      | Should -Be $SentInterval
        }
    }

    It 'reads a pattern type that is not weekly or absoluteMonthly as OneTime and not representable' -ForEach @(
        @{ Type = 'relativeMonthly' }
        @{ Type = 'absoluteYearly' }
        @{ Type = '' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Type = $Type } {
            param($Type)
            $Shape = Get-OERAccessReviewCadence -PatternType $Type -Interval 1
            $Shape.Cadence       | Should -BeExactly 'OneTime'
            $Shape.Representable | Should -BeFalse
            $Shape.PatternType   | Should -BeNullOrEmpty
            $Shape.Interval      | Should -BeNullOrEmpty
        }
    }

    It 'reads the pattern type in any letter case' {
        InModuleScope Omnicit.EntraRBAC {
            $Shape = Get-OERAccessReviewCadence -PatternType 'ABSOLUTEMONTHLY' -Interval 6
            $Shape.Cadence       | Should -BeExactly 'SemiAnnually'
            $Shape.Representable | Should -BeTrue
            (Get-OERAccessReviewCadence -PatternType 'Weekly' -Interval 1).Cadence | Should -BeExactly 'Weekly'
        }
    }

    It 'accepts the interval of a pattern as the integer a caller cast it to' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERAccessReviewCadence -PatternType 'absoluteMonthly' -Interval ([int]'12')).Cadence | Should -BeExactly 'Annually'
        }
    }
}

Describe 'Get-OERAccessReviewCadence holds the whole vocabulary' {
    It 'answers every cadence the canonical list names, and each answer reads back as the same cadence' {
        InModuleScope Omnicit.EntraRBAC {
            $Canonical = @(Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List)
            $Canonical.Count | Should -BeGreaterThan 0
            foreach ($Name in $Canonical) {
                $Shape = Get-OERAccessReviewCadence -Cadence $Name
                $Shape.Cadence | Should -BeExactly $Name
                if ($Name -eq 'OneTime') { continue }
                $Back = Get-OERAccessReviewCadence -PatternType $Shape.PatternType -Interval $Shape.Interval
                $Back.Cadence       | Should -BeExactly $Name -Because "$Name reads back as itself"
                $Back.Representable | Should -BeTrue
            }
        }
    }

    It 'calls exactly five combinations of pattern type and interval representable' {
        InModuleScope Omnicit.EntraRBAC {
            $Representable = [System.Collections.Generic.List[string]]::new()
            foreach ($Type in 'weekly', 'absoluteMonthly', 'relativeMonthly', 'absoluteYearly', '') {
                foreach ($Interval in 0..30) {
                    if ((Get-OERAccessReviewCadence -PatternType $Type -Interval $Interval).Representable) {
                        $Representable.Add("$Type/$Interval")
                    }
                }
            }
            ($Representable -join ',') | Should -BeExactly 'weekly/1,absoluteMonthly/1,absoluteMonthly/3,absoluteMonthly/6,absoluteMonthly/12'
        }
    }
}

Describe 'no other source file spells the cadence and interval vocabulary (BL-117, third point)' {
    # Get-OERAccessReviewCadence owns the table that maps a cadence to a Graph pattern type and interval
    # and back. Five sites used to spell it out by hand (the builder, the live-state diff twice, the
    # export twice); a sixth that disagreed would write one interval and read back another. This scan
    # reads every .ps1 under source/ with the PowerShell parser and fails on the four shapes those
    # sites wrote, anywhere but the owner's file:
    #   A  an array of exactly the integers 1, 3, 6 and 12, in any order (the representable set);
    #   B  a switch clause whose condition is the integer 1, 3, 6 or 12 and whose body names one of
    #      Monthly, Quarterly, SemiAnnually or Annually (interval to cadence);
    #   C  a switch clause whose condition names one of those four cadences and whose body holds the
    #      integer 1, 3, 6 or 12 (cadence to interval);
    #   D  a switch clause whose condition is the pattern type weekly or absoluteMonthly.
    # It does NOT see a mapping written as a hashtable, a chain of if statements, a comparison such as
    # -eq 6 against an interval, or a table split across variables, and it reads no comment or string.
    # Unset, OER_COHORT_SOURCE_ROOT leaves the scan on the repository's own source/; a mutation proof
    # sets it to a scratch copy of source/ so the scan reads the mutated tree.
    BeforeAll {
        $script:CadenceSourceRoot = if ($env:OER_COHORT_SOURCE_ROOT) {
            $env:OER_COHORT_SOURCE_ROOT
        } else {
            Join-Path -Path $PSScriptRoot -ChildPath '../../../source'
        }
        if ($env:OER_COHORT_SOURCE_ROOT) {
            Write-Warning "OER_COHORT_SOURCE_ROOT is set: scanning $env:OER_COHORT_SOURCE_ROOT instead of the repository source."
        }
        $script:CadenceOwnerFile = 'Get-OERAccessReviewCadence.ps1'

        function Find-CadenceSpelling {
            param([System.Management.Automation.Language.Ast]$Ast)
            $IntervalSet = @(1, 3, 6, 12)
            $CadenceNames = @('Monthly', 'Quarterly', 'SemiAnnually', 'Annually')
            $PatternTypes = @('weekly', 'absoluteMonthly')
            $IsInterval = {
                param($Node)
                $Node -is [System.Management.Automation.Language.ConstantExpressionAst] -and
                $Node.Value -is [int] -and $Node.Value -in $IntervalSet
            }
            $IsCadenceName = {
                param($Node)
                $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $Node.Value -in $CadenceNames
            }
            $Found = [System.Collections.Generic.List[string]]::new()

            foreach ($Node in $Ast.FindAll({ param($N) $N -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true)) {
                $Elements = @($Node.Elements)
                $AllInts = ($Elements.Count -gt 0) -and (@($Elements | Where-Object {
                            $_ -isnot [System.Management.Automation.Language.ConstantExpressionAst] -or $_.Value -isnot [int]
                        }).Count -eq 0)
                if ($AllInts -and ((@($Elements.Value | Sort-Object) -join ',') -eq '1,3,6,12')) {
                    $Found.Add("line $($Node.Extent.StartLineNumber): the representable intervals 1, 3, 6, 12 (A)")
                }
            }

            foreach ($Switch in $Ast.FindAll({ param($N) $N -is [System.Management.Automation.Language.SwitchStatementAst] }, $true)) {
                foreach ($Clause in $Switch.Clauses) {
                    $Condition = $Clause.Item1
                    $Body = $Clause.Item2
                    $Line = $Condition.Extent.StartLineNumber
                    if ((& $IsInterval $Condition) -and (@($Body.FindAll({ param($N) & $IsCadenceName $N }, $true)).Count -gt 0)) {
                        $Found.Add("line ${Line}: interval $($Condition.Value) mapped to a cadence name (B)")
                    }
                    elseif ((& $IsCadenceName $Condition) -and (@($Body.FindAll({ param($N) & $IsInterval $N }, $true)).Count -gt 0)) {
                        $Found.Add("line ${Line}: cadence $($Condition.Value) mapped to an interval (C)")
                    }
                    elseif ($Condition -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $Condition.Value -iin $PatternTypes) {
                        $Found.Add("line ${Line}: a switch clause on the pattern type '$($Condition.Value)' (D)")
                    }
                }
            }
            @($Found)
        }

        function Find-CadenceSpellingInText {
            param([string]$Text)
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$Errors)
            if ($Errors -and $Errors.Count -gt 0) { throw "the sample does not parse: $($Errors[0].Message)" }
            Find-CadenceSpelling -Ast $Ast
        }
    }

    It 'finds the representable interval set, written as the five old sites wrote it' {
        @(Find-CadenceSpellingInText -Text '$Ok = $Interval -in 1, 3, 6, 12').Count | Should -Be 1
        @(Find-CadenceSpellingInText -Text '$Ok = @(12, 6, 3, 1) -contains $Interval').Count | Should -Be 1
        (@(Find-CadenceSpellingInText -Text '$Ok = $Interval -in 1, 3, 6, 12') -join ';') | Should -BeLike '*(A)'
    }

    It 'finds an interval to cadence switch, nested or not' {
        $Nested = "`$C = switch (`$T) { 'absoluteMonthly' { switch (`$I) { 1 { 'Monthly' } 3 { 'Quarterly' } 6 { 'SemiAnnually' } 12 { 'Annually' } default { 'Monthly' } } } default { 'OneTime' } }"
        $Found = @(Find-CadenceSpellingInText -Text $Nested)
        @($Found | Where-Object { $_ -like '*(B)' }).Count | Should -Be 4
        @($Found | Where-Object { $_ -like '*(D)' }).Count | Should -Be 1
        @(Find-CadenceSpellingInText -Text "`$C = switch (`$I) { 12 { 'Annually' } }").Count | Should -Be 1
        @(Find-CadenceSpellingInText -Text "`$C = switch (`$I) { 6 { `$X = 'SemiAnnually' } }").Count | Should -Be 1
    }

    It 'finds a cadence to interval switch' {
        $Found = @(Find-CadenceSpellingInText -Text "`$I = switch (`$R) { 'Monthly' { 1 } 'Quarterly' { 3 } 'SemiAnnually' { 6 } 'Annually' { 12 } }")
        $Found.Count | Should -Be 4
        @($Found | Where-Object { $_ -like '*(C)' }).Count | Should -Be 4
        @(Find-CadenceSpellingInText -Text "`$I = switch (`$R) { 'SemiAnnually' { 6 } }").Count | Should -Be 1
    }

    It 'finds a switch on the pattern type' {
        @(Find-CadenceSpellingInText -Text "`$C = switch (`$T) { 'weekly' { 'Weekly' } }").Count | Should -Be 1
        @(Find-CadenceSpellingInText -Text "`$C = switch (`$T) { 'AbsoluteMonthly' { 'x' } }").Count | Should -Be 1
    }

    It 'finds nothing in code that only looks like the vocabulary' {
        $Clean = @(
            '$Ok = $Interval -in 1, 3, 6'
            '$Ok = $Interval -in 1, 3, 6, 12, 24'
            '$Ok = $Interval -in 1, 3, 6, 11'
            '$Ok = $Interval -in 1, 3, 6, $Twelve'
            "`$C = switch (`$I) { 2 { 'Monthly' } 5 { 'Quarterly' } }"
            "`$C = switch (`$I) { 1 { 'Other' } 12 { 'Eleven' } }"
            "`$I = switch (`$R) { 'OneTime' { 6 } 'Other' { 12 } }"
            "`$I = switch (`$R) { 'Monthly' { 2 } }"
            "`$C = switch (`$T) { 'relativeMonthly' { 1 } }"
            '# the intervals are 1, 3, 6, 12 and the clause 12 { "Annually" }'
            '$Text = "interval 1, 3, 6, 12 is absoluteMonthly"'
        )
        foreach ($Line in $Clean) {
            @(Find-CadenceSpellingInText -Text $Line).Count | Should -Be 0 -Because "this is not the vocabulary: $Line"
        }
    }

    It 'finds nothing in any source file except the owner''s' {
        $Files = @(Get-ChildItem -LiteralPath $script:CadenceSourceRoot -Recurse -Filter '*.ps1' -File |
                Where-Object { $_.Name -ne $script:CadenceOwnerFile })
        # A scan that reads nothing proves nothing.
        $Files.Count | Should -BeGreaterThan 100
        ($Files.Name -contains 'Resolve-OERAccessReviewChange.ps1') | Should -BeTrue
        ($Files.Name -contains 'Get-OERInventory.ps1') | Should -BeTrue
        ($Files.Name -contains 'New-OERAccessReviewRecurrence.ps1') | Should -BeTrue
        $Spellings = foreach ($File in $Files) {
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$Errors)
            if ($Errors -and $Errors.Count -gt 0) { "$($File.Name): does not parse: $($Errors[0].Message)"; continue }
            foreach ($Finding in (Find-CadenceSpelling -Ast $Ast)) { "$($File.Name): $Finding" }
        }
        @($Spellings) | Should -BeNullOrEmpty -Because 'Get-OERAccessReviewCadence is the only place that spells the table'
    }

    It 'has the owner in the tree it scans, and the three consumers call it' {
        $Owner = Join-Path -Path $script:CadenceSourceRoot -ChildPath "Private/$($script:CadenceOwnerFile)"
        Test-Path -LiteralPath $Owner -PathType Leaf | Should -BeTrue
        foreach ($Relative in 'Private/New-OERAccessReviewRecurrence.ps1', 'Private/Resolve-OERAccessReviewChange.ps1', 'Public/Get-OERInventory.ps1') {
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $script:CadenceSourceRoot -ChildPath $Relative), [ref]$null, [ref]$Errors)
            $Errors.Count | Should -Be 0
            $Calls = @($Ast.FindAll({
                        param($N)
                        $N -is [System.Management.Automation.Language.CommandAst] -and
                        $N.GetCommandName() -eq 'Get-OERAccessReviewCadence'
                    }, $true))
            $Calls.Count | Should -BeGreaterThan 0 -Because "$Relative reads the cadence table through its owner"
        }
    }
}
