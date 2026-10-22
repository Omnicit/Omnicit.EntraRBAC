BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # The helper is private, so it is called inside the module. The result is returned in one object, as its
    # Items, so no unrolling decides what an empty or one-entry list looks like. Every assertion below joins
    # the items into one text, which -BeExactly compares by case and which is the same text for one order and
    # no other (Pester's collection comparison is not relied on for an order).
    function Invoke-Sort {
        param([object[]]$InputObject, [string[]]$Property)
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Entries = $InputObject; Names = $Property } {
            param($Entries, $Names)
            $Items = if ($Names) { @(Get-OEROrderedInventoryEntry -InputObject $Entries -Property $Names) } else { @(Get-OEROrderedInventoryEntry -InputObject $Entries) }
            [PSCustomObject]@{ Items = $Items }
        }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OEROrderedInventoryEntry (Sprint 11 step 10, BL-121, R-16)' {
    Context 'a list of texts' {
        It 'orders without regard to letter case, and puts the uppercase spelling first where two texts differ only in it' {
            $Sorted = (Invoke-Sort -InputObject @('bob@contoso.com', 'alice@contoso.com', 'Bob@contoso.com', 'Alice@contoso.com', 'carol@contoso.com')).Items
            ($Sorted -join '|') | Should -BeExactly 'Alice@contoso.com|alice@contoso.com|Bob@contoso.com|bob@contoso.com|carol@contoso.com'
        }

        It 'orders by ordinal values, never by culture: the same order under a culture that sorts differently' {
            # A culture comparison puts punctuation before letters ('a_b' before 'ab'), where the ordinal one
            # compares the upper-case values ('AB' is 65 66 and 'A_B' is 65 95, so 'ab' stands before 'a_b'),
            # and tr-TR treats 'i' and 'I' as two letters. The order here is the ordinal one in all of them:
            # '-' (45), '.' (46), digits, letters, then '_' (95), and 'I' before 'i'.
            $Texts = @('a_b', 'a.b', 'a-b', 'a1', 'ab', 'I', 'i', 'H')
            $Previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                foreach ($Culture in 'en-US', 'tr-TR', 'sv-SE') {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                    $Sorted = (Invoke-Sort -InputObject $Texts).Items
                    ($Sorted -join '|') | Should -BeExactly 'a-b|a.b|a1|ab|a_b|H|I|i' -Because "the order must not depend on the culture ($Culture)"
                }
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $Previous
            }
        }

        It 'gives the same list for the same set of texts whatever order it went in' {
            $Texts = @('b@contoso.com', 'B@contoso.com', 'a@contoso.com', 'A@contoso.com', 'c@contoso.com', 'C@contoso.com', 'dev-2', 'dev-10')
            $Reversed = @($Texts[($Texts.Count - 1)..0])
            $First = (Invoke-Sort -InputObject $Texts).Items
            $Second = (Invoke-Sort -InputObject $Reversed).Items
            ($First | ConvertTo-Json -Compress) | Should -BeExactly ($Second | ConvertTo-Json -Compress)
            ($First -join '|') | Should -BeExactly 'A@contoso.com|a@contoso.com|B@contoso.com|b@contoso.com|C@contoso.com|c@contoso.com|dev-10|dev-2'
        }

        It 'returns nothing for an empty list or a null, one entry for one, and drops a null entry' {
            @((Invoke-Sort -InputObject @()).Items).Count | Should -Be 0
            @((Invoke-Sort -InputObject @('only')).Items).Count | Should -Be 1
            ((Invoke-Sort -InputObject @('only')).Items -join '|') | Should -BeExactly 'only'
            ((Invoke-Sort -InputObject @($null, 'b', $null, 'a')).Items -join '|') | Should -BeExactly 'a|b'
            $Null = InModuleScope Omnicit.EntraRBAC {
                @(Get-OEROrderedInventoryEntry -InputObject $null).Count | Should -Be 0
            }
        }

        It 'keeps an empty text, and orders it first' {
            ((Invoke-Sort -InputObject @('b', '', 'a')).Items -join '|') | Should -BeExactly '|a|b'
        }
    }

    Context 'a list of objects ordered by properties' {
        It 'orders by the first property, then the next one only where the first ties' {
            $Rows = @(
                [PSCustomObject]@{ principal = 'bob'; accessType = 'owner' }
                [PSCustomObject]@{ principal = 'Alice'; accessType = 'owner' }
                [PSCustomObject]@{ principal = 'alice'; accessType = 'member' }
                [PSCustomObject]@{ principal = 'bob'; accessType = 'member' }
                [PSCustomObject]@{ principal = 'Alice'; accessType = 'member' }
            )
            $Sorted = (Invoke-Sort -InputObject $Rows -Property principal, accessType).Items
            (@($Sorted | ForEach-Object { "$($_.principal)/$($_.accessType)" }) -join '|') | Should -BeExactly 'Alice/member|Alice/owner|alice/member|bob/member|bob/owner'
        }

        It 'orders a number ascending and an absent or null number before every number, and numbers as numbers (9 before 10)' {
            $Rows = @(
                [PSCustomObject]@{ principal = 'p'; durationDays = 30 }
                [PSCustomObject]@{ principal = 'p' }
                [PSCustomObject]@{ principal = 'p'; durationDays = 9 }
                [PSCustomObject]@{ principal = 'p'; durationDays = $null }
                [PSCustomObject]@{ principal = 'p'; durationDays = 365 }
                [PSCustomObject]@{ principal = 'p'; durationDays = 10 }
            )
            $Sorted = (Invoke-Sort -InputObject $Rows -Property principal, durationDays).Items
            (@($Sorted | ForEach-Object { if ($null -eq $_.durationDays) { 'none' } else { [string]$_.durationDays } }) -join '|') | Should -BeExactly 'none|none|9|10|30|365'
        }

        It 'orders the eligibility entries of the group projection: principal, access type, duration, then id' {
            $Rows = @(
                [PSCustomObject]@{ principal = 'bob'; accessType = 'member'; durationDays = 30; id = '2' }
                [PSCustomObject]@{ principal = 'bob'; accessType = 'member'; id = '9' }
                [PSCustomObject]@{ principal = 'Alice'; accessType = 'owner'; id = '1' }
                [PSCustomObject]@{ principal = 'alice'; accessType = 'member'; durationDays = 7; id = '3' }
                [PSCustomObject]@{ principal = 'bob'; accessType = 'member'; durationDays = 30; id = '1' }
                [PSCustomObject]@{ principal = 'bob'; accessType = 'Member'; durationDays = 5; id = '4' }
            )
            $Sorted = (Invoke-Sort -InputObject $Rows -Property principal, accessType, durationDays, id).Items
            (@($Sorted | ForEach-Object { "$($_.principal)/$($_.accessType)/$($_.durationDays)/$($_.id)" }) -join '|') |
                Should -BeExactly 'Alice/owner//1|alice/member/7/3|bob/Member/5/4|bob/member//9|bob/member/30/1|bob/member/30/2'
        }

        It 'reads a property that an entry lacks as absent, with no error, and orders it first as the empty text' {
            $Rows = @(
                [PSCustomObject]@{ principal = 'b' }
                [PSCustomObject]@{ other = 1 }
                [PSCustomObject]@{ principal = 'a' }
            )
            $Sorted = (Invoke-Sort -InputObject $Rows -Property principal).Items
            (@($Sorted | ForEach-Object { [string]$_.principal }) -join '|') | Should -BeExactly '|a|b'
        }

        It 'gives the same JSON for the same entries in two orders' {
            $Rows = @(
                [PSCustomObject]@{ principal = 'b'; accessType = 'member' }
                [PSCustomObject]@{ principal = 'B'; accessType = 'member'; durationDays = 3 }
                [PSCustomObject]@{ principal = 'a'; accessType = 'owner' }
                [PSCustomObject]@{ principal = 'a'; accessType = 'member' }
            )
            $Reversed = @($Rows[($Rows.Count - 1)..0])
            $First = (Invoke-Sort -InputObject $Rows -Property principal, accessType, durationDays).Items
            $Second = (Invoke-Sort -InputObject $Reversed -Property principal, accessType, durationDays).Items
            ($First | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly ($Second | ConvertTo-Json -Depth 5 -Compress)
            (@($First | ForEach-Object { "$($_.principal)/$($_.accessType)/$($_.durationDays)" }) -join '|') | Should -BeExactly 'a/member/|a/owner/|B/member/3|b/member/'
        }
    }

    Context 'it uses no syntax newer than the module floor (PowerShell 7.2)' {
        # Fix round 1 of Sprint 11 step 10, task 4, finding 1. A generic method called with explicit type
        # arguments ([System.Linq.Enumerable]::OrderBy[object, string](...)) is syntax PowerShell has only
        # since 7.3 (about_Calling_Generic_Methods). Under the 7.2 grammar it is an index expression followed
        # by a parenthesis, a parse error, so the whole merged module would fail to load. CI runs a current
        # PowerShell only and PSScriptAnalyzer's PSUseCompatibleSyntax reports nothing for it, so every .ps1
        # under source/ is read with the parser instead (Sprint 11 step 15, BL-157: it was the helper's own
        # file alone): no InvokeMemberExpressionAst in any of them may carry generic type arguments, and a
        # parser that refuses the file (the 7.2 case) is a finding too. The checker has a known-answer test
        # of its own, so it cannot pass for nothing, and the scan asserts it read every file it should.
        BeforeAll {
            $script:SourceRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../source')).Path

            function script:Get-GenericTypeArgumentUse {
                param([string]$Path, [string]$Text)
                $ParseErrors = $null
                $Ast = if ($Path) {
                    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$ParseErrors)
                } else {
                    [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$ParseErrors)
                }
                $Uses = [System.Collections.Generic.List[string]]::new()
                foreach ($ParseError in @($ParseErrors)) {
                    if ($null -ne $ParseError) { $Uses.Add("does not parse: $($ParseError.Message)") }
                }
                $Calls = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
                foreach ($Call in $Calls) {
                    $TypeArguments = $Call.GenericTypeArguments
                    if ($null -ne $TypeArguments -and @($TypeArguments).Count -gt 0) {
                        $Uses.Add("line $($Call.Extent.StartLineNumber): $($Call.Extent.Text)")
                    }
                }
                , $Uses.ToArray()
            }
        }

        It 'finds an explicit generic type argument on a method call, and finds none on a call that infers them (known answer)' {
            $Explicit = Get-GenericTypeArgumentUse -Text '[System.Linq.Enumerable]::OrderBy[object, string]($Pairs, $Key)'
            @($Explicit).Count | Should -BeGreaterThan 0 -Because 'a call with explicit type arguments is exactly what the checker is for'
            $Inferred = Get-GenericTypeArgumentUse -Text '[System.Linq.Enumerable]::OrderBy($Pairs, $Key); $List.Add($Item); [System.Math]::Max(1, 2)'
            @($Inferred).Count | Should -Be 0
        }

        It 'has no method call with explicit generic type arguments in any file under source, which PowerShell 7.2 cannot parse' {
            $Files = @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1')
            $Findings = [System.Collections.Generic.List[string]]::new()
            $Scanned = 0
            foreach ($File in $Files) {
                $Scanned++
                $FileUses = Get-GenericTypeArgumentUse -Path $File.FullName
                foreach ($Use in $FileUses) {
                    $Findings.Add("$($File.FullName.Substring($script:SourceRoot.Length + 1)) $Use")
                }
            }
            # Non-vacuity: the scan read every .ps1 the tree holds, and the tree is not a near-empty one.
            $Scanned | Should -Be @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1').Count
            $Scanned | Should -BeGreaterThan 250 -Because 'the module holds over three hundred source files, so a smaller count means a partial tree, which is what this floor catches'
            $Findings.Count | Should -Be 0 -Because "the module declares PowerShell 7.2 as its floor and an explicit generic type argument on a method call is syntax of 7.3 and later, so the merged module would not load there: $($Findings -join ' | ')"
        }
    }

    Context 'it is pure' {
        It 'sends no request and signs in nowhere' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
            $null = Invoke-Sort -InputObject @('b', 'a')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }
}
