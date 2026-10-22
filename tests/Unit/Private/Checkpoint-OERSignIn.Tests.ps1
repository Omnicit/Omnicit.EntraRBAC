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

    Context 'comparing with a snapshot, for a sign-in that names a tenant (BL-90)' {
        # The state is for tenant 4444 as named. Another identity (a client id) signs in to the SAME tenant
        # label after the snapshot: a sign-in naming 4444 would take that session, so it is refused.
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{
                    TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'
                    ClientId = '33333333-3333-3333-3333-333333333333'; Environment = 'Global'
                }
            }
        }
        It 'reports a change when the identity changed and the session is for the tenant the sign-in names' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.ClientId = '55555555-5555-5555-5555-555555555555'
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeTrue
            }
        }
        It 'reports no change when the identity changed and the session is for another tenant than the sign-in names' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                # Not vacuous: without -TenantId the same change is reported.
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeTrue
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'reports a change when the snapshot held no state and the session is now for the tenant the sign-in names' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = $null
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global' }
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeTrue
            }
        }
        It 'reports no change when the snapshot held no state and the session is now for another tenant' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = $null
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState = @{ TenantId = '77777777-7777-7777-7777-777777777777'; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global' }
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'reports no change when the state was cleared after the snapshot (the sign-in signs in itself)' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState = $null
                Checkpoint-OERSignIn -ChangedSince $S | Should -BeTrue
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'reports no change when the identity is unchanged, though the session is for the tenant the sign-in names' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'reports no change for a renewal that moved only the expiry, though the session is for the tenant the sign-in names' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.GraphTokenExpiry = [datetime]::UtcNow.AddHours(1)
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'compares the tenant as named: a domain does not take a session built for the tenant ID' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.ClientId = '55555555-5555-5555-5555-555555555555'
                Checkpoint-OERSignIn -ChangedSince $S -TenantId 'contoso.example.com' | Should -BeFalse
            }
        }
        It 'compares the identity alone for an empty -TenantId' {
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '' | Should -BeTrue
            }
        }
        It 'asks Test-OERSessionUsable, with the tenant, only when the identity changed' {
            Mock -ModuleName Omnicit.EntraRBAC Test-OERSessionUsable { $true }
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERSessionUsable -Times 0
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.ClientId = '55555555-5555-5555-5555-555555555555'
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeTrue
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERSessionUsable -Times 1 -Exactly -ParameterFilter { $TenantId -eq '44444444-4444-4444-4444-444444444444' }
        }
        It 'takes its answer from Test-OERSessionUsable, not from a comparison of its own' {
            Mock -ModuleName Omnicit.EntraRBAC Test-OERSessionUsable { $false }
            InModuleScope Omnicit.EntraRBAC {
                $S = Checkpoint-OERSignIn
                $script:_OERAuthState.ClientId = '55555555-5555-5555-5555-555555555555'
                # The mocked owner says the session is not for the tenant, though the state's label matches.
                Checkpoint-OERSignIn -ChangedSince $S -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERSessionUsable -Times 1 -Exactly
        }
        It 'declares -TenantId in the Compare parameter set only' {
            $Command = Get-Command Checkpoint-OERSignIn -Module Omnicit.EntraRBAC -ErrorAction SilentlyContinue
            if (-not $Command) { $Command = InModuleScope Omnicit.EntraRBAC { Get-Command Checkpoint-OERSignIn } }
            $Sets = @($Command.ParameterSets | Where-Object { $_.Parameters.Name -contains 'TenantId' } | ForEach-Object { $_.Name })
            $Sets | Should -Be @('Compare')
        }
    }
}
