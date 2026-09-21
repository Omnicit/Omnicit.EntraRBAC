BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Disconnect-OER' {
    # Disconnect-AzAccount is still mocked in every It, even though Disconnect-OER no longer calls
    # it. Two reasons, and neither is obsolete:
    #
    #   1. The NEGATIVE assertion below needs it. Pester's Mock resolves the command it is given and
    #      throws when it cannot, so 'Should -Invoke ... -Times 0' cannot even be written without a
    #      mock in place. Removing the mock would not simplify this file; it would delete the proof.
    #   2. It is the safety net if the call ever comes back. Without the mock, a reintroduced call
    #      would execute the REAL cmdlet during a local run and clear the operator's Az context and
    #      on-disk token cache -- the same context used for manual live verification.
    #
    # Az.Accounts is resolved into output/RequiredModules for this and for the Connect-AzAccount
    # -Times 0 assertion in Initialize-OERAuth.Tests.ps1; it is deliberately NOT a manifest
    # dependency. See RequiredModules.psd1's own comment and
    # docs/development/rationale.md#dependencies before concluding the entry is unused.
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

    It 'leaves an Az PowerShell session the operator started alone' {
        <#
            Philip's decision, 2026-09-21. The module never establishes an Az context -- -IncludeARM
            only acquires an ARM token, which Invoke-OERArmRequest sends itself -- so any Az context
            on the machine belongs to the operator. Signing it out here cleared their own sign-in and
            their on-disk Az token cache as a side effect of ending an unrelated session.

            -Exactly is REDUNDANT here and kept only for explicitness. Pester already treats
            -Times 0 as exact: its help for Should -Invoke says "If the value passed to the Times
            parameter is zero, the Exactly switch is implied", and the implementation agrees --
            Pester.psm1 decides with ($Exactly -or ($Times -eq 0)). Verified by execution against
            both Pester 5.7.1 and 6.2.0: a bare -Times 0 FAILS when the command was called. The
            at-least trap CLAUDE.md warns about is real, but only for -Times N where N >= 1.
        #>
        InModuleScope $script:moduleName { $script:_OERAuthState = @{ TenantId = 'x' } }
        Disconnect-OER -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Disconnect-AzAccount -Times 0 -Exactly
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
