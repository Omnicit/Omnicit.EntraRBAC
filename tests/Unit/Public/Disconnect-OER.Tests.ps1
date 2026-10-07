BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    # A10 (BL-89): after a refused sign-in the module's session is uncertain, and a command that names no
    # tenant is refused. Disconnect-OER leaves no session at all, so nothing is uncertain any more.
    It 'clears the session-uncertain marker' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x' }
            $script:_OERSessionUncertain = $true
        }

        Disconnect-OER -Confirm:$false

        InModuleScope $script:moduleName { $script:_OERSessionUncertain } | Should -BeFalse
        InModuleScope $script:moduleName { $null -eq $script:_OERSessionUncertain } | Should -BeFalse -Because 'the marker is cleared to $false, not removed'
    }

    It 'leaves the session-uncertain marker under -WhatIf, as it leaves the state' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x' }
            $script:_OERSessionUncertain = $true
        }

        Disconnect-OER -WhatIf

        # Positive proof that -WhatIf skipped the whole block: the state is still there.
        InModuleScope $script:moduleName { $script:_OERAuthState.TenantId } | Should -BeExactly 'x'
        InModuleScope $script:moduleName { $script:_OERSessionUncertain } | Should -BeTrue
        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0
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

# -------------------------------------------------------------------------------------------------
# Graph SDK session (A18). The fingerprint of the session the module connected lives in the auth
# state, so replacing the whole state with $null forgets it with no statement of its own. These
# tests keep that true: after a disconnect the module tracks no session, compares nothing and never
# reads the SDK's session to find out.
# -------------------------------------------------------------------------------------------------
Describe 'Disconnect-OER and the Graph SDK session fingerprint (A18)' {
    BeforeEach {
        Mock -ModuleName $script:moduleName Disconnect-MgGraph {}
        Mock -ModuleName $script:moduleName Disconnect-AzAccount {}
        # A stable fake session, so a state check that reached the SDK would read this and not the
        # real, process-wide one.
        Mock -ModuleName $script:moduleName Get-MgContext {
            [pscustomobject]@{
                AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
                ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '22222222-2222-2222-2222-222222222222'
                Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
            }
        }
    }

    It 'forgets the recorded fingerprint with the state, so the module tracks no session' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = '{"TenantId":"x"}' }
            # The precondition: a tracked state, so the 'Untracked' below is the disconnect's doing.
            $script:_OERAuthState.ContainsKey('GraphSessionFingerprint') | Should -BeTrue
        }

        Disconnect-OER -Confirm:$false

        InModuleScope $script:moduleName {
            $script:_OERAuthState | Should -BeNullOrEmpty
            Get-OERGraphSessionState | Should -Be 'Untracked'
        }
        Should -Invoke -ModuleName $script:moduleName Get-MgContext -Times 0 -Exactly
    }
}
