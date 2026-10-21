BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Export-OERConfiguration' {
    It 'writes a psd1 that round-trips via Import-PowerShellDataFile' {
        $Path = Join-Path $TestDrive 'contoso.psd1'
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
            param($Path)
            Export-OERConfiguration -Configuration @{
                TenantId = '00000000-0000-0000-0000-000000000000'
                Naming   = @{ Group = 'role_sec_{area}_{tier}' }
                Defaults = @{ PrimaryApprovers = @('a', 'b') }
            } -Path $Path
        }
        $Loaded = Import-PowerShellDataFile -Path $Path
        $Loaded.TenantId | Should -Be '00000000-0000-0000-0000-000000000000'
        $Loaded.Naming.Group | Should -Be 'role_sec_{area}_{tier}'
        $Loaded.Defaults.PrimaryApprovers | Should -HaveCount 2
    }

    It 'writes a key containing a space as a quoted PSD1 key that round-trips' {
        # Keys are caller-supplied: New-/Set-OERConfiguration take a bare [hashtable] for -Naming
        # and -Defaults with no key validation, so an unquoted key with a space wrote a profile
        # Import-PowerShellDataFile could not parse.
        $Path = Join-Path $TestDrive 'spaced.psd1'
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
            param($Path)
            Export-OERConfiguration -Configuration @{
                TenantId = '00000000-0000-0000-0000-000000000001'
                Naming   = @{ 'Group Template' = 'role_{area}' }
            } -Path $Path
        }
        $Data = Import-PowerShellDataFile -Path $Path
        $Data.Naming['Group Template'] | Should -Be 'role_{area}'
    }

    It 'escapes a single quote in a key' {
        $Path = Join-Path $TestDrive 'quoted.psd1'
        InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
            param($Path)
            Export-OERConfiguration -Configuration @{
                TenantId = '00000000-0000-0000-0000-000000000001'
                Naming   = @{ "O'Brien" = 'x' }
            } -Path $Path
        }
        (Import-PowerShellDataFile -Path $Path).Naming["O'Brien"] | Should -Be 'x'
    }

    Context 'a character PowerShell reads as a single quote (BL-113)' {
        # The tokenizer reads U+0027, U+2018, U+2019, U+201A and U+201B as single quotes; the writer must
        # double every one of them. Built from code points so this test file stays ASCII.
        It 'round-trips <Label> in a key, a list item, a scalar and a nested value, byte for byte' -ForEach @(
            @{ Label = 'U+0027'; Code = 0x27 }
            @{ Label = 'U+2018'; Code = 0x2018 }
            @{ Label = 'U+2019'; Code = 0x2019 }
            @{ Label = 'U+201A'; Code = 0x201A }
            @{ Label = 'U+201B'; Code = 0x201B }
        ) {
            $Q = [string][char]$Code
            $Path = Join-Path $TestDrive "q$Code.psd1"
            InModuleScope $script:moduleName -Parameters @{ Path = $Path; Q = $Q } {
                param($Path, $Q)
                Export-OERConfiguration -Configuration @{
                    TenantId = "ten${Q}ant"
                    Naming   = @{ "Key${Q}One" = "Val${Q}ue" }
                    Defaults = @{ "Def${Q}Key" = "x${Q}y"; Items = @("a${Q}b", $Q, 'plain') }
                } -Path $Path
            }
            $Data = Import-PowerShellDataFile -Path $Path -ErrorAction Stop
            $Data.TenantId -ceq "ten${Q}ant" | Should -BeTrue
            $Data.Naming["Key${Q}One"] -ceq "Val${Q}ue" | Should -BeTrue
            $Data.Defaults["Def${Q}Key"] -ceq "x${Q}y" | Should -BeTrue
            $Items = @($Data.Defaults.Items)
            $Items | Should -HaveCount 3
            $Items[0] -ceq "a${Q}b" | Should -BeTrue
            $Items[1] -ceq $Q | Should -BeTrue
        }

        It 'never adds a key when <Label> ends a string early in a key, a list item or a scalar' -ForEach @(
            @{ Label = 'U+0027'; Code = 0x27 }
            @{ Label = 'U+2018'; Code = 0x2018 }
            @{ Label = 'U+2019'; Code = 0x2019 }
            @{ Label = 'U+201A'; Code = 0x201A }
            @{ Label = 'U+201B'; Code = 0x201B }
        ) {
            $Q = [string][char]$Code
            $Inject = "x${Q}; Environment = ${Q}China"
            $Path = Join-Path $TestDrive "inject$Code.psd1"
            InModuleScope $script:moduleName -Parameters @{ Path = $Path; Inject = $Inject } {
                param($Path, $Inject)
                Export-OERConfiguration -Configuration @{
                    TenantId = $Inject
                    Naming   = @{ $Inject = 'n' }
                    Defaults = @{ Scalar = $Inject; Items = @($Inject, 'b') }
                } -Path $Path
            }
            $Data = Import-PowerShellDataFile -Path $Path -ErrorAction Stop
            @($Data.Keys | Sort-Object) -join ',' | Should -Be 'Defaults,Naming,TenantId'
            $Data.ContainsKey('Environment') | Should -BeFalse
            @($Data.Defaults.Keys | Sort-Object) -join ',' | Should -Be 'Items,Scalar'
            $Data.Defaults.Scalar -ceq $Inject | Should -BeTrue
            @($Data.Defaults.Items)[0] -ceq $Inject | Should -BeTrue
            @($Data.Naming.Keys)[0] -ceq $Inject | Should -BeTrue
            $Data.TenantId -ceq $Inject | Should -BeTrue
        }
    }
}
