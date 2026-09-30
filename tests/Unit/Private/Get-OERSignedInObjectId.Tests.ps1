BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERSignedInObjectId' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'returns $null when there is no session' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERSignedInObjectId | Should -BeNullOrEmpty
        }
    }

    It 'returns the recorded object id when it is GUID-shaped' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ SignedInObjectId = 'aaaaaaaa-0000-0000-0000-000000000001' }
            Get-OERSignedInObjectId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
        }
    }

    It 'returns $null when the recorded value is not GUID-shaped' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ SignedInObjectId = 'not-a-guid' }
            Get-OERSignedInObjectId | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the key is absent from an older state' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = 'contoso' }
            Get-OERSignedInObjectId | Should -BeNullOrEmpty
        }
    }
}
