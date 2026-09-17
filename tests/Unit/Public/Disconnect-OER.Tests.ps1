BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Disconnect-OER' {
    # Disconnect-AzAccount MUST be mocked in every It. It resolves for real in the test environment
    # (Az.Accounts arrives transitively with the pinned Az.Resources under output/RequiredModules), so
    # without the mock source/Public/Disconnect-OER.ps1:22-23 executes the real cmdlet and clears the
    # operator's local Az context and on-disk token cache -- the same context used for manual live
    # verification. Mocking it also makes the Get-Command guard resolve inside the module, which keeps
    # the branch reachable and assertable.
    BeforeEach {
        Mock -ModuleName $script:moduleName Disconnect-MgGraph {}
        Mock -ModuleName $script:moduleName Disconnect-AzAccount {}
    }

    It 'clears the cached auth state' {
        InModuleScope $script:moduleName { $script:_OERAuthState = @{ TenantId = 'x' } }
        Disconnect-OER -Confirm:$false
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
    }

    It 'calls Disconnect-MgGraph' {
        InModuleScope $script:moduleName { $script:_OERAuthState = @{ TenantId = 'x' } }
        Disconnect-OER -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 1
    }

    It 'calls Disconnect-AzAccount when the Az cmdlet is available' {
        InModuleScope $script:moduleName { $script:_OERAuthState = @{ TenantId = 'x' } }
        Disconnect-OER -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Disconnect-AzAccount -Times 1
    }
}

# -------------------------------------------------------------------------------------------------
# Sovereign clouds (Sprint 1.5, issue #81).
#
# Verified rather than assumed: Disconnect-OER replaces the WHOLE $script:_OERAuthState hashtable
# with $null, so the cloud goes with it and no separate clearing statement is needed. These two
# tests exist to keep that true, and to pin the deliberate asymmetry with the authority-host cache.
# -------------------------------------------------------------------------------------------------
Describe 'Disconnect-OER and the sovereign cloud state' {
    BeforeEach {
        Mock -ModuleName $script:moduleName Disconnect-MgGraph {}
        Mock -ModuleName $script:moduleName Disconnect-AzAccount {}
    }

    It 'drops the session cloud along with the rest of the auth state' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId    = 'tenant-a'
                AuthMethod  = 'Interactive'
                ClientId    = ''
                Environment = 'USGov'
            }
        }

        Disconnect-OER -Confirm:$false

        InModuleScope $script:moduleName {
            $script:_OERAuthState | Should -BeNullOrEmpty
            # Asserted through the state object rather than a bare property read, since a property
            # read off $null is itself $null and would pass whether or not the state was cleared.
            $script:_OERAuthState.Environment | Should -BeNullOrEmpty
        }
    }

    # Deliberately NOT cleared. Disconnect-OER does not -- and cannot -- clear AzAuth's own static
    # credential field, which is internal and lives in a private AssemblyLoadContext. That credential
    # is still baked to the authority the last acquisition used, so forgetting which authority that
    # was would let the next sign-in skip the -Force that is the only way to drop it, and the new
    # cloud's AZURE_AUTHORITY_HOST would then have no effect at all.
    It 'does NOT clear the last-authority cache, since AzAuth keeps its credential across a disconnect' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'tenant-a'; Environment = 'USGov' }
            $script:_OERLastAuthorityHost = 'https://login.microsoftonline.us/'
        }

        Disconnect-OER -Confirm:$false

        InModuleScope $script:moduleName {
            $script:_OERLastAuthorityHost | Should -Be 'https://login.microsoftonline.us/'
        }
    }
}
