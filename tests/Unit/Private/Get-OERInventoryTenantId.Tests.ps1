BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryTenantId (BL-88, A14)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    AfterAll {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'returns nothing when the session holds no state' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            $Result = Get-OERInventoryTenantId
            $null -eq $Result | Should -BeTrue -Because 'no state names no tenant'
            @(Get-OERInventoryTenantId).Count | Should -Be 0
        }
    }

    It 'returns the tenant the Graph token was issued for, never the tenant as named' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId      = 'contoso.onmicrosoft.com'
                TokenTenantId = '44444444-4444-4444-4444-444444444444'
            }
            $Result = Get-OERInventoryTenantId
            $Result | Should -BeExactly '44444444-4444-4444-4444-444444444444'
            $Result | Should -Not -Be 'contoso.onmicrosoft.com'
        }
    }

    It 'returns the granted tenant when the caller named another GUID' {
        InModuleScope Omnicit.EntraRBAC {
            # The tenant as named is never the answer, even when it is itself a GUID: the token is
            # what every request goes out under.
            $script:_OERAuthState = @{
                TenantId      = '11111111-1111-1111-1111-111111111111'
                TokenTenantId = '44444444-4444-4444-4444-444444444444'
            }
            Get-OERInventoryTenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        }
    }

    It 'returns the granted tenant when the session was signed in under organizations' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId      = 'organizations'
                TokenTenantId = '44444444-4444-4444-4444-444444444444'
            }
            Get-OERInventoryTenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        }
    }

    It 'returns nothing when TenantId is a GUID but the token reported no tenant' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId      = '11111111-1111-1111-1111-111111111111'
                TokenTenantId = $null
            }
            @(Get-OERInventoryTenantId).Count | Should -Be 0 -Because 'the tenant as named is not evidence of the tenant granted'
        }
    }

    It 'returns nothing when the state carries no TokenTenantId at all' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = [PSCustomObject]@{ TenantId = '11111111-1111-1111-1111-111111111111' }
            @(Get-OERInventoryTenantId).Count | Should -Be 0
        }
    }

    It 'returns nothing when the token tenant is <Value>' -ForEach @(
        @{ Value = 'not-a-guid' }
        @{ Value = 'contoso.onmicrosoft.com' }
        @{ Value = '{44444444-4444-4444-4444-444444444444}' }
        @{ Value = '44444444444444444444444444444444' }
        @{ Value = '' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Value = $Value } {
            param($Value)
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = $Value }
            @(Get-OERInventoryTenantId).Count | Should -Be 0
        }
    }

    It 'reads the state only: it never signs in and never sends a request' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = '44444444-4444-4444-4444-444444444444' }
            Mock Initialize-OERAuth { }
            Mock Invoke-OERGraphRequest { }
            Mock Invoke-OERArmRequest { }
            Get-OERInventoryTenantId | Out-Null
            Should -Invoke Initialize-OERAuth -Times 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
            Should -Invoke Invoke-OERArmRequest -Times 0
        }
    }
}
