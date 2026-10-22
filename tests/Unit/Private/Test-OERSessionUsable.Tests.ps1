BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERSessionUsable' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    AfterAll { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'the module holds no sign-in state' {
        It 'answers false for a named tenant' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'answers false for an empty tenant' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable -TenantId '' | Should -BeFalse
            }
        }
        It 'answers false when no tenant is given' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable | Should -BeFalse
            }
        }
    }

    Context 'the module holds a sign-in state' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{
                    TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'
                    ClientId = '33333333-3333-3333-3333-333333333333'; Environment = 'Global'
                }
            }
        }
        It 'answers true for the tenant the state was built for' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeTrue
            }
        }
        It 'answers true when only the letter case of the tenant differs' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState.TenantId = 'Contoso.Example.com'
                Test-OERSessionUsable -TenantId 'contoso.example.COM' | Should -BeTrue
            }
        }
        It 'answers false for another tenant' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable -TenantId '77777777-7777-7777-7777-777777777777' | Should -BeFalse
            }
        }
        It 'answers false for a domain when the state names the tenant by its ID (the tenant as NAMED is compared)' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState.TokenTenantId = '44444444-4444-4444-4444-444444444444'
                Test-OERSessionUsable -TenantId 'contoso.example.com' | Should -BeFalse
            }
        }
        It 'answers false for a state that carries no tenant when one is named' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState.Remove('TenantId')
                Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444' | Should -BeFalse
            }
        }
        It 'answers true for an empty tenant, whichever tenant the state is for' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable -TenantId '' | Should -BeTrue
            }
        }
        It 'answers true when no tenant is given' {
            InModuleScope Omnicit.EntraRBAC {
                Test-OERSessionUsable | Should -BeTrue
            }
        }
        It 'answers true for an empty tenant when the state carries no tenant' {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState.Remove('TenantId')
                Test-OERSessionUsable -TenantId '' | Should -BeTrue
            }
        }
        It 'answers with a [bool]' {
            InModuleScope Omnicit.EntraRBAC {
                (Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444') -is [bool] | Should -BeTrue
                (Test-OERSessionUsable -TenantId '77777777-7777-7777-7777-777777777777') -is [bool] | Should -BeTrue
            }
        }
        It 'reads the state and changes none' {
            InModuleScope Omnicit.EntraRBAC {
                $Before = Get-OERSignInIdentity
                $null = Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444'
                $null = Test-OERSessionUsable -TenantId '77777777-7777-7777-7777-777777777777'
                Get-OERSignInIdentity | Should -BeExactly $Before
            }
        }
    }
}
