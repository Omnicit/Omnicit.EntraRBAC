BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Checkpoint-OERSignIn' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    AfterAll { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'taking a snapshot' {
        It 'holds no identity when the module holds no state' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $S.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.SignInSnapshot'
                $S.Identity | Should -BeNullOrEmpty
            }
        }
        It 'holds exactly what Get-OERSignInIdentity returns, and no other property' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{
                    TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'
                    ClientId = '33333333-3333-3333-3333-333333333333'; Environment = 'Global'
                    ArmToken = ConvertTo-SecureString 'NOT-A-REAL-TOKEN' -AsPlainText -Force
                    Account = 'oer-probe'
                }
                $S = Checkpoint-OERSignIn
                $S.Identity | Should -BeExactly (Get-OERSignInIdentity)
                @($S.PSObject.Properties.Name) | Should -Be @('Identity')
            }
        }
    }

    Context 'comparing with a snapshot' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{
                    TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'
                    ClientId = ''; Environment = 'Global'
                }
            }
        }
        It 'reports no change for the same identity' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeFalse
            }
        }
        It 'reports no change when only letter case differs' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.AuthMethod = 'INTERACTIVE'
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeFalse
            }
        }
        It 'reports a change of <Term>' -ForEach @(
            @{ Term = 'TenantId'; Value = '77777777-7777-7777-7777-777777777777' }
            @{ Term = 'AuthMethod'; Value = 'ClientCertificate' }
            @{ Term = 'ClientId'; Value = '33333333-3333-3333-3333-333333333333' }
            @{ Term = 'Environment'; Value = 'USGov' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Term = $Term; Value = $Value } {
                param($Term, $Value)
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState[$Term] = $Value
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeTrue
            }
        }
        It 'reports a change when the state was cleared after the snapshot' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState = $null
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeTrue
            }
        }
        It 'reports a change when a snapshot of no state meets a state' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = $null
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState = @{ TenantId = 'organizations'; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global' }
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeTrue
            }
        }
        It 'reports no change when a snapshot of no state meets no state' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = $null
                $S = Checkpoint-OERSignIn
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeFalse
            }
        }
        It 'refuses an object that is not a snapshot' {
            InModuleScope Omnicit.EntraRBAC {
                { Checkpoint-OERSignIn -ChangedSince ([pscustomobject]@{ Identity = 'x' }) } | Should -Throw
            }
        }
        It 'reads the identity through Get-OERSignInIdentity' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERSignInIdentity { 'mocked-identity' }
            InModuleScope Omnicit.EntraRBAC {
                (Checkpoint-OERSignIn).Identity | Should -BeExactly 'mocked-identity'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERSignInIdentity -Times 1 -Exactly
        }
    }
}
