BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
}
