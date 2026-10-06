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
                TokenTenantId           = '11111111-1111-1111-1111-111111111111'
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
        $R | Should -Not -Match '22222222'
    }

    # BL-77: the tenant term is the tenant the Microsoft Graph token was issued for when that is a
    # GUID, and the tenant as named otherwise. Since BL-12 every named tenant is checked against that
    # token, so one tenant named by GUID on one command and by domain on another is one identity.
    Context 'the tenant term (BL-77)' {
        BeforeAll {
            # One state per case, built in module scope: the four terms after the tenant are the same
            # in every one, so a case differs only in the tenant term it names.
            function script:Get-IdentityOfState {
                param([Parameter(Mandatory)][hashtable]$State)
                InModuleScope Omnicit.EntraRBAC -Parameters @{ State = $State } {
                    param($State)
                    $State.AuthMethod = 'ClientCertificate'
                    $State.ClientId = '33333333-3333-3333-3333-333333333333'
                    $State.Environment = 'USGov'
                    $script:_OERAuthState = $State
                    Get-OERSignInIdentity
                }
            }
        }

        It 'reads the tenant a domain named on the command line was issued a token for' {
            $R = Get-IdentityOfState -State @{
                TenantId      = 'contoso.onmicrosoft.com'
                TokenTenantId = '11111111-1111-1111-1111-111111111111'
            }
            $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
        }

        It 'gives one identity to one tenant named by its domain and by its tenant ID' {
            $ByDomain = Get-IdentityOfState -State @{
                TenantId      = 'contoso.onmicrosoft.com'
                TokenTenantId = '11111111-1111-1111-1111-111111111111'
            }
            $ByGuid = Get-IdentityOfState -State @{
                TenantId      = '11111111-1111-1111-1111-111111111111'
                TokenTenantId = '11111111-1111-1111-1111-111111111111'
            }
            $ByGuid | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
            $ByDomain | Should -BeExactly $ByGuid
        }

        It 'gives one identity to a tenant named by a GUID in the other case' {
            $Lower = Get-IdentityOfState -State @{
                TenantId      = 'aaaaaaaa-1111-1111-1111-111111111111'
                TokenTenantId = 'aaaaaaaa-1111-1111-1111-111111111111'
            }
            $Upper = Get-IdentityOfState -State @{
                TenantId      = 'AAAAAAAA-1111-1111-1111-111111111111'
                TokenTenantId = 'aaaaaaaa-1111-1111-1111-111111111111'
            }
            # PowerShell's -eq, as Get-OERSignInSupersession compares, ignores case.
            ($Upper -eq $Lower) | Should -BeTrue
        }

        It 'reads the tenant a command that named none was issued a token for' {
            $R = Get-IdentityOfState -State @{
                TenantId      = 'organizations'
                TokenTenantId = '11111111-1111-1111-1111-111111111111'
            }
            $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
        }

        It 'reads the tenant as named when the granted tenant is <Case>' -ForEach @(
            @{ Case = 'absent'; Granted = '<absent>' }
            @{ Case = '$null'; Granted = $null }
            @{ Case = 'an empty string'; Granted = '' }
            @{ Case = 'a name that is not a GUID'; Granted = 'contoso' }
            @{ Case = 'a GUID in braces'; Granted = '{11111111-1111-1111-1111-111111111111}' }
            @{ Case = 'a GUID without hyphens'; Granted = '11111111111111111111111111111111' }
        ) {
            $State = @{ TenantId = 'contoso.onmicrosoft.com' }
            if ($Granted -ne '<absent>') {
                $State.TokenTenantId = $Granted
            }
            $R = Get-IdentityOfState -State $State
            $R | Should -BeExactly "contoso.onmicrosoft.com`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
        }

        It 'never reads the tenant the Azure Resource Manager token was issued for' {
            $R = Get-IdentityOfState -State @{
                TenantId         = 'contoso.onmicrosoft.com'
                ArmTokenTenantId = '22222222-2222-2222-2222-222222222222'
            }
            $R | Should -BeExactly "contoso.onmicrosoft.com`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov"
        }

        It 'keeps the identity the same whether or not an Azure Resource Manager token was acquired' {
            $Graph = '11111111-1111-1111-1111-111111111111'
            $GraphOnly = Get-IdentityOfState -State @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = $Graph }
            $WithArm = Get-IdentityOfState -State @{
                TenantId         = 'contoso.onmicrosoft.com'
                TokenTenantId    = $Graph
                ArmTokenTenantId = '22222222-2222-2222-2222-222222222222'
            }
            $WithArm | Should -BeExactly $GraphOnly
        }

        It 'still tells two tenants the tokens were issued for apart' {
            $A = Get-IdentityOfState -State @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = '11111111-1111-1111-1111-111111111111' }
            $B = Get-IdentityOfState -State @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = '77777777-7777-7777-7777-777777777777' }
            ($A -eq $B) | Should -BeFalse
        }
    }
}
