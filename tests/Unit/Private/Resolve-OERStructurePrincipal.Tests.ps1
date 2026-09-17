BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERStructurePrincipal' {
    It 'returns a GUID verbatim with no lookup' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERUserId {}; Mock Resolve-OERGroupId {}
            Resolve-OERStructurePrincipal -Reference '11111111-1111-1111-1111-111111111111' | Should -Be '11111111-1111-1111-1111-111111111111'
            Should -Invoke Resolve-OERUserId -Times 0; Should -Invoke Resolve-OERGroupId -Times 0
        }
    }
    It 'resolves a UPN via Resolve-OERUserId' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERUserId { 'u-1' } -ParameterFilter { $UserPrincipalName -eq 'person9@example.com' }
            Mock Resolve-OERGroupId {}
            Resolve-OERStructurePrincipal -Reference 'person9@example.com' | Should -Be 'u-1'
            Should -Invoke Resolve-OERGroupId -Times 0
        }
    }
    It 'resolves a plain name via Resolve-OERGroupId' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERGroupId { 'g-1' } -ParameterFilter { $DisplayName -eq 'Some Group' }
            Mock Resolve-OERUserId {}
            Resolve-OERStructurePrincipal -Reference 'Some Group' | Should -Be 'g-1'
        }
    }
    It 'falls back to user lookup when group lookup misses' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERGroupId { $null }
            Mock Resolve-OERUserId { 'u-2' }
            Resolve-OERStructurePrincipal -Reference 'ambiguous' | Should -Be 'u-2'
        }
    }
    It 'returns null when nothing resolves' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERGroupId { $null }; Mock Resolve-OERUserId { $null }
            Resolve-OERStructurePrincipal -Reference 'ghost' | Should -BeNullOrEmpty
        }
    }
    It 'returns null for an unresolved UPN without trying a group lookup' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERUserId { $null }; Mock Resolve-OERGroupId { 'should-not-be-called' }
            Resolve-OERStructurePrincipal -Reference 'person10@example.com' | Should -BeNullOrEmpty
            Should -Invoke Resolve-OERGroupId -Times 0
        }
    }

    It 'resolves a service principal display name via Resolve-OERApplicationId when -Type ServicePrincipal' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERApplicationId { 'sp-1' }
            Mock Resolve-OERGroupId { 'WRONG' }
            Resolve-OERStructurePrincipal -Reference 'Contoso SP' -Type 'ServicePrincipal' | Should -Be 'sp-1'
            Should -Invoke Resolve-OERApplicationId -Times 1
        }
    }

    It 'returns $null when a typed service principal is not found' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERApplicationId { $null }
            Resolve-OERStructurePrincipal -Reference 'No SP' -Type 'ServicePrincipal' | Should -BeNullOrEmpty
        }
    }

    It 'resolves via the user lookup when -Type User' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERUserId { 'u-1' }
            Resolve-OERStructurePrincipal -Reference 'Anna' -Type 'User' | Should -Be 'u-1'
        }
    }

    It 'returns a GUID verbatim regardless of -Type' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Resolve-OERStructurePrincipal -Reference '11111111-1111-1111-1111-111111111111' -Type 'ServicePrincipal' | Should -Be '11111111-1111-1111-1111-111111111111'
        }
    }
}
