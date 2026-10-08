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
        # Disconnect-OER reads the Graph SDK session once, to decide whether it is the one the module
        # connected (A4, BL-67). Mocked, so no test reads the real, process-wide session: it answers no
        # session unless a test sets $script:SessionContext.
        $script:SessionContext = $null
        Mock -ModuleName $script:moduleName Get-MgContext { $script:SessionContext }
    }

    It 'clears the cached auth state' {
        InModuleScope $script:moduleName { $script:_OERAuthState = @{ TenantId = 'x' } }
        Disconnect-OER -Confirm:$false
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
    }

    It 'calls Disconnect-MgGraph for the session the module connected' {
        # An 'Own' state: the process holds the session whose fingerprint the state carries.
        $script:SessionContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '22222222-2222-2222-2222-222222222222'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        InModuleScope $script:moduleName -Parameters @{ C = $script:SessionContext } {
            param($C)
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = (Get-OERGraphSessionFingerprint -Context $C) }
        }
        Disconnect-OER -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 1 -Exactly
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
        # Disconnect-OER reads the Graph SDK session once (A4, BL-67); no session here, so these tests
        # neither read the real, process-wide session nor see the warning for a session left connected.
        Mock -ModuleName $script:moduleName Get-MgContext { $null }
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

        # The state's fingerprint is not the mocked session's, so this is a 'Changed' session and
        # Disconnect-OER writes its warning (A4, BL-67); silenced here, asserted in the Describe below.
        Disconnect-OER -Confirm:$false -WarningAction SilentlyContinue

        # Disconnect-OER reads the session once, to decide whether it is the module's own. That is its
        # own decision, made before the state is cleared.
        Should -Invoke -ModuleName $script:moduleName Get-MgContext -Times 1 -Exactly
        InModuleScope $script:moduleName {
            $script:_OERAuthState | Should -BeNullOrEmpty
            Get-OERGraphSessionState | Should -Be 'Untracked'
        }
        # The module tracks nothing now, so finding that out does not read the session: still the one read.
        Should -Invoke -ModuleName $script:moduleName Get-MgContext -Times 1 -Exactly
    }
}

# -------------------------------------------------------------------------------------------------
# Disconnect-OER ends only the Graph SDK session the module connected (A4, BL-67, Sprint 10 step 3).
#
# The state is read once, before the gate: Get-OERGraphSessionState says Own (the process holds the
# session the module connected -- disconnected), Changed (another Connect-MgGraph replaced it),
# Absent (no session) or Untracked (the module holds no record of a session of its own -- an earlier
# import of the module, say). Only Own is disconnected. A session that exists and is left -- Changed,
# or Untracked with a session in the process -- gets one warning, written BEFORE the gate so that
# -WhatIf and a -Confirm prompt show it. The state and the A10 marker are cleared in every case.
# -------------------------------------------------------------------------------------------------
Describe 'Disconnect-OER ends only the Graph SDK session the module connected (A4, BL-67)' {
    BeforeAll {
        # One string; the help, README and about topic say the same in their own words.
        $script:LeftWarning = 'Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process ' +
            'connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.'
    }

    BeforeEach {
        Mock -ModuleName $script:moduleName Disconnect-MgGraph {}
        Mock -ModuleName $script:moduleName Disconnect-AzAccount {}
        # The session the process holds: a stable fake, so nothing reads the real, process-wide one.
        $script:SessionContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '22222222-2222-2222-2222-222222222222'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:SessionContext }
        # The fingerprint of that session, which an 'Own' state carries.
        $script:SessionFingerprint = InModuleScope $script:moduleName -Parameters @{ C = $script:SessionContext } {
            param($C)
            Get-OERGraphSessionFingerprint -Context $C
        }
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $false
        }
    }

    AfterEach {
        # Leave no state or marker behind for the next test or the next file.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $false
        }
    }

    It 'Own: disconnects the session the module connected, writes no warning and clears the state' {
        InModuleScope $script:moduleName -Parameters @{ F = $script:SessionFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = $F }
            # The precondition: the state really reads Own, so the Disconnect-MgGraph below is its doing.
            Get-OERGraphSessionState | Should -BeExactly 'Own'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 1 -Exactly
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
        @($Warnings).Count | Should -Be 0
    }

    It 'Changed: leaves the session another Connect-MgGraph started, with exactly one warning, and still clears the state and the marker' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = '{"TenantId":"other"}' }
            $script:_OERSessionUncertain = $true
            Get-OERGraphSessionState | Should -BeExactly 'Changed'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName {
            $script:_OERAuthState | Should -BeNullOrEmpty
            $script:_OERSessionUncertain | Should -BeFalse
        }
        @($Warnings).Count | Should -Be 1
        $Warnings[0].Message | Should -BeExactly $script:LeftWarning
    }

    It 'Untracked, no state, a session in the process: leaves it, with exactly one warning' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            Get-OERGraphSessionState | Should -BeExactly 'Untracked'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
        @($Warnings).Count | Should -Be 1
        $Warnings[0].Message | Should -BeExactly $script:LeftWarning
    }

    It 'Untracked, a state with no fingerprint, a session in the process: leaves it, with exactly one warning' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x' }
            Get-OERGraphSessionState | Should -BeExactly 'Untracked'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
        @($Warnings).Count | Should -Be 1
        $Warnings[0].Message | Should -BeExactly $script:LeftWarning
    }

    It 'Untracked and no session in the process: nothing is left connected, so no warning and no Disconnect-MgGraph' {
        $script:SessionContext = $null
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            Get-OERGraphSessionState | Should -BeExactly 'Untracked'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
        @($Warnings).Count | Should -Be 0
    }

    It 'Absent: the session the module connected is already gone, so no warning and no Disconnect-MgGraph' {
        $script:SessionContext = $null
        InModuleScope $script:moduleName -Parameters @{ F = $script:SessionFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = $F }
            Get-OERGraphSessionState | Should -BeExactly 'Absent'
        }

        Disconnect-OER -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName { $script:_OERAuthState | Should -BeNullOrEmpty }
        @($Warnings).Count | Should -Be 0
    }

    It 'under -WhatIf on a Changed session, shows the warning and changes nothing' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = '{"TenantId":"other"}' }
            $script:_OERSessionUncertain = $true
        }

        Disconnect-OER -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue

        # The warning is written before the gate: a warning inside it is never written under -WhatIf.
        @($Warnings).Count | Should -Be 1
        $Warnings[0].Message | Should -BeExactly $script:LeftWarning
        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName {
            $script:_OERAuthState.TenantId | Should -BeExactly 'x'
            $script:_OERSessionUncertain | Should -BeTrue
        }
    }

    # The guard for the one call that ends a live session. On a Changed session Disconnect-MgGraph is not
    # called whatever the gate does, so only an Own state shows that -WhatIf does not reach it.
    It 'under -WhatIf on an Own session, does not disconnect it, keeps the state and the marker, and writes no warning' {
        InModuleScope $script:moduleName -Parameters @{ F = $script:SessionFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = 'x'; GraphSessionFingerprint = $F }
            $script:_OERSessionUncertain = $true
            # The precondition: the state really reads Own, so the call that must not happen is the one
            # the gate guards.
            Get-OERGraphSessionState | Should -BeExactly 'Own'
        }

        Disconnect-OER -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 0 -Exactly
        InModuleScope $script:moduleName -Parameters @{ F = $script:SessionFingerprint } {
            param($F)
            $script:_OERAuthState.TenantId | Should -BeExactly 'x'
            $script:_OERAuthState.GraphSessionFingerprint | Should -BeExactly $F
            $script:_OERSessionUncertain | Should -BeTrue
        }
        @($Warnings).Count | Should -Be 0
    }

    It 'writes its one warning before its first $PSCmdlet.ShouldProcess call, read from the loaded function' {
        # From the loaded command, so a mutated copy under the harness and the built module in the gate
        # are both what is read. The run-time half of the same fact is the -WhatIf test above.
        $Ast = (Get-Command -Module $script:moduleName -Name Disconnect-OER).ScriptBlock.Ast
        $Warnings = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Write-Warning'
                }, $true))
        $Gates = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $Node.Member.Value -eq 'ShouldProcess'
                }, $true))

        $Warnings.Count | Should -Be 1
        $Gates.Count | Should -BeGreaterThan 0
        $FirstGate = $Gates | Sort-Object -Property { $_.Extent.StartOffset } | Select-Object -First 1
        $Warnings[0].Extent.StartOffset | Should -BeLessThan $FirstGate.Extent.StartOffset
    }
}
