BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERStructureDefault' {
    It 'returns the Defaults value for a known key (hashtable Defaults)' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ ActivationMaxHours = 8; Catalog = 'CAT-IT' } } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'ActivationMaxHours' | Should -Be 8
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'Catalog' | Should -Be 'CAT-IT'
        }
    }
    It 'returns an array default intact (PrimaryApprovers)' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ PrimaryApprovers = @('a', 'b') } } }
            @(Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'PrimaryApprovers').Count | Should -Be 2
        }
    }
    It 'returns null for an unknown key' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ ActivationMaxHours = 8 } } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'AuthenticationContextId' | Should -BeNullOrEmpty
        }
    }
    It 'returns null when no alias is given' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureDefault -Name 'ActivationMaxHours' | Should -BeNullOrEmpty
        }
    }
    It 'returns null when Defaults section is absent' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ TenantId = 'x' } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'Catalog' | Should -BeNullOrEmpty
        }
    }
    It 'returns null and does not throw when the profile read fails' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { throw 'no profile' }
            Resolve-OERStructureDefault -TenantAlias 'absent' -Name 'Catalog' | Should -BeNullOrEmpty
        }
    }

    It 'scrubs the bearer-hygiene record when the profile read fails' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { throw 'no profile' }
            Mock Remove-OERErrorRecord { }
            Resolve-OERStructureDefault -TenantAlias 'absent' -Name 'Catalog' | Should -BeNullOrEmpty
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }
}
