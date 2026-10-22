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

    It 'returns the tenant, method, client, cloud and account joined with a line feed, in that order' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId        = '11111111-1111-1111-1111-111111111111'
                AuthMethod      = 'ClientCertificate'
                ClientId        = '33333333-3333-3333-3333-333333333333'
                Environment     = 'USGov'
                SignInAccountId = '55555555-5555-5555-5555-555555555555'
            }
            Get-OERSignInIdentity
        }
        $R | Should -BeOfType ([string])
        $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n55555555-5555-5555-5555-555555555555"
    }

    It 'reads a missing <Term> as an empty string' -ForEach @(
        @{ Term = 'TenantId'; Expected = "`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal`n55555555-5555-5555-5555-555555555555" }
        @{ Term = 'AuthMethod'; Expected = "11111111-1111-1111-1111-111111111111`n`n33333333-3333-3333-3333-333333333333`nGlobal`n55555555-5555-5555-5555-555555555555" }
        @{ Term = 'ClientId'; Expected = "11111111-1111-1111-1111-111111111111`nInteractive`n`nGlobal`n55555555-5555-5555-5555-555555555555" }
        @{ Term = 'Environment'; Expected = "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`n`n55555555-5555-5555-5555-555555555555" }
        @{ Term = 'SignInAccountId'; Expected = "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal`n" }
    ) {
        $R = InModuleScope Omnicit.EntraRBAC -Parameters @{ Term = $Term } {
            param($Term)
            $State = @{
                TenantId        = '11111111-1111-1111-1111-111111111111'
                AuthMethod      = 'Interactive'
                ClientId        = '33333333-3333-3333-3333-333333333333'
                Environment     = 'Global'
                SignInAccountId = '55555555-5555-5555-5555-555555555555'
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

    It 'carries the five terms and nothing else of a state that holds a token, an account and a session fingerprint' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId                = '11111111-1111-1111-1111-111111111111'
                AuthMethod              = 'Interactive'
                ClientId                = '33333333-3333-3333-3333-333333333333'
                Environment             = 'Global'
                Account                 = 'admin@contoso.com'
                GraphTokenExpiry        = [DateTime]::UtcNow.AddHours(1)
                TokenTenantId           = '11111111-1111-1111-1111-111111111111'
                SignedInObjectId        = '66666666-6666-6666-6666-666666666666'
                SignInAccountId         = '55555555-5555-5555-5555-555555555555'
                GraphSessionFingerprint = 'fingerprint-NOT-A-REAL-TOKEN'
                ArmToken                = [System.Net.NetworkCredential]::new('', 'fake-arm-token-NOT-A-REAL-TOKEN').SecurePassword
                ArmTokenExpiry          = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl          = 'https://management.azure.com'
                ArmTokenTenantId        = '22222222-2222-2222-2222-222222222222'
                ClaimsSatisfied         = $false
            }
            Get-OERSignInIdentity
        }
        $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal`n55555555-5555-5555-5555-555555555555"
        $R | Should -Not -Match 'NOT-A-REAL-TOKEN'
        $R | Should -Not -Match 'admin@contoso\.com'
        $R | Should -Not -Match '22222222'
        # The account term is the state's own SignInAccountId, not the oid of the last token.
        $R | Should -Not -Match '66666666'
        $R | Should -Not -Match 'True'
    }

    # BL-119: the fifth term is the account the session was established as. Initialize-OERAuth decides
    # when it moves; the reader only prints the key.
    Context 'the account term (BL-119)' {
        It 'moves the identity when only the account differs' {
            $Result = InModuleScope Omnicit.EntraRBAC {
                $State = @{
                    TenantId        = '11111111-1111-1111-1111-111111111111'
                    AuthMethod      = 'Interactive'
                    ClientId        = ''
                    Environment     = 'Global'
                    SignInAccountId = '55555555-5555-5555-5555-555555555555'
                }
                $script:_OERAuthState = $State
                $First = Get-OERSignInIdentity
                $State.SignInAccountId = '77777777-7777-7777-7777-777777777777'
                @{ First = $First; Second = Get-OERSignInIdentity }
            }
            ($Result.First -eq $Result.Second) | Should -BeFalse
        }

        It 'reads a state with no account, or a $null one, as an empty last term' {
            $Result = InModuleScope Omnicit.EntraRBAC {
                $State = @{ TenantId = 't'; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global' }
                $script:_OERAuthState = $State
                $Absent = Get-OERSignInIdentity
                $State.SignInAccountId = $null
                @{ Absent = $Absent; Null = Get-OERSignInIdentity }
            }
            $Result.Absent | Should -BeExactly "t`nInteractive`n`nGlobal`n"
            $Result.Null | Should -BeExactly $Result.Absent
        }

        It 'is not moved by the oid of the last token (SignedInObjectId) or by the account name' {
            $Result = InModuleScope Omnicit.EntraRBAC {
                $State = @{
                    TenantId         = 't'
                    AuthMethod       = 'Interactive'
                    ClientId         = ''
                    Environment      = 'Global'
                    SignInAccountId  = '55555555-5555-5555-5555-555555555555'
                    SignedInObjectId = '66666666-6666-6666-6666-666666666666'
                    Account          = 'first@contoso.com'
                }
                $script:_OERAuthState = $State
                $First = Get-OERSignInIdentity
                $State.SignedInObjectId = $null
                $State.Account = 'second@contoso.com'
                @{ First = $First; Second = Get-OERSignInIdentity }
            }
            $Result.Second | Should -BeExactly $Result.First
        }
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
            $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n"
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
            $ByGuid | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n"
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
            $R | Should -BeExactly "11111111-1111-1111-1111-111111111111`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n"
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
            $R | Should -BeExactly "contoso.onmicrosoft.com`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n"
        }

        It 'never reads the tenant the Azure Resource Manager token was issued for' {
            $R = Get-IdentityOfState -State @{
                TenantId         = 'contoso.onmicrosoft.com'
                ArmTokenTenantId = '22222222-2222-2222-2222-222222222222'
            }
            $R | Should -BeExactly "contoso.onmicrosoft.com`nClientCertificate`n33333333-3333-3333-3333-333333333333`nUSGov`n"
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
