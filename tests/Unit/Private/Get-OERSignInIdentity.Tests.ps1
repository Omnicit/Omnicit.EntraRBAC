BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSignInIdentity' {
    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'returns the tenant, method, client and cloud joined with a line feed, in that order' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId    = '11111111-1111-1111-1111-111111111111'
                AuthMethod  = 'ClientCertificate'
                ClientId    = '33333333-3333-3333-3333-333333333333'
                Environment = 'USGov'
            }
            Get-OERSignInIdentity
        }
        $R | Should -BeOfType ([string])
        $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
    }

    It 'reads a missing <Term> as an empty string' -ForEach @(
        @{ Term = 'TenantId'; Expected = "`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal" }
        @{ Term = 'AuthMethod'; Expected = "11111111-1111-1111-1111-111111111111`n`n33333333-3333-3333-3333-333333333333`nGlobal" }
        @{ Term = 'ClientId'; Expected = "11111111-1111-1111-1111-111111111111`nInteractive`n`nGlobal" }
        @{ Term = 'Environment'; Expected = "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`n" }
    ) {
        $R = InModuleScope Omnicit.EntraRBAC -Parameters @{ Term = $Term } {
            param($Term)
            $State = @{
                TenantId    = '11111111-1111-1111-1111-111111111111'
                AuthMethod  = 'Interactive'
                ClientId    = '33333333-3333-3333-3333-333333333333'
                Environment = 'Global'
            }
            $State.Remove($Term)
            $script:_OERAuthState = $State
            Get-OERSignInIdentity
        }
        $R | Should -BeOfType ([string])
        $R | Should -BeExactly $Expected
    }

    It 'returns $null when the module holds no auth state' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            $Identity = Get-OERSignInIdentity
            @{ IsNull = $null -eq $Identity; Count = @(Get-OERSignInIdentity).Count }
        }
        $R.IsNull | Should -BeTrue
        $R.Count | Should -Be 0
    }

    It 'carries the four terms and nothing else of a state that holds a token, an account and a session fingerprint' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId                = '11111111-1111-1111-1111-111111111111'
                AuthMethod              = 'Interactive'
                ClientId                = '33333333-3333-3333-3333-333333333333'
                Environment             = 'Global'
                Account                 = 'admin@contoso.com'
                GraphTokenExpiry        = [DateTime]::UtcNow.AddHours(1)
                TokenTenantId           = '22222222-2222-2222-2222-222222222222'
                SignedInObjectId        = '55555555-5555-5555-5555-555555555555'
                GraphSessionFingerprint = 'fingerprint-NOT-A-REAL-TOKEN'
                ArmToken                = [System.Net.NetworkCredential]::new('', 'fake-arm-token-NOT-A-REAL-TOKEN').SecurePassword
                ArmTokenExpiry          = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl          = 'https://management.azure.com'
                ArmTokenTenantId        = '22222222-2222-2222-2222-222222222222'
                ClaimsSatisfied         = $false
            }
            Get-OERSignInIdentity
        }
        $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal"
        $R | Should -Not -Match 'NOT-A-REAL-TOKEN'
        $R | Should -Not -Match 'admin@contoso\.com'
    }
}
