BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSignInSupersession' {
    # Initialize-OERAuth is the only caller of Register-OERSignInIdentity in source/. These tests call it
    # from stand-in commands with their own $MyInvocation, which is the object Lock-OERSignIn returns
    # for the command that called Initialize-OERAuth, and then change $script:_OERAuthState the way a
    # later sign-in would.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId    = '11111111-1111-1111-1111-111111111111'
                AuthMethod  = 'Interactive'
                ClientId    = '33333333-3333-3333-3333-333333333333'
                Environment = 'Global'
            }
        }
    }

    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'returns nothing at once, without reading the call stack, when the memory table was never created' {
        Mock -ModuleName Omnicit.EntraRBAC Get-PSCallStack { }
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
            @(Get-OERSignInSupersession)
        }
        $R.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-PSCallStack -Times 0

        # Not vacuous: the function calls Microsoft.PowerShell.Utility\Get-PSCallStack, and the same
        # mock does see that module-qualified call once a table exists. Without this the zero above
        # would also pass if the mock could not intercept the call at all.
        $null = InModuleScope Omnicit.EntraRBAC {
            $script:_OERSignInIdentity = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
            @(Get-OERSignInSupersession)
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-PSCallStack -Times 1 -Exactly
    }

    It 'returns nothing when the remembering command''s identity equals the state' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                @{
                    Held         = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                    Supersession = @(Get-OERSignInSupersession)
                }
            }
            Invoke-SignedInCommand
        }
        # Not vacuous: the frame is remembered, so it was compared.
        $R.Held | Should -BeTrue
        $R.Supersession.Count | Should -Be 0
    }

    It 'returns nothing when the table holds only a command that has finished' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-FinishedCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $MyInvocation
            }
            # Kept referenced, so the weak table cannot drop the entry.
            $Kept = Invoke-FinishedCommand
            $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
            $Value = $null
            $Held = $script:_OERSignInIdentity.TryGetValue($Kept, [ref]$Value)
            @{
                Held         = $Held
                Differs      = $Value -ne (Get-OERSignInIdentity)
                Supersession = @(Get-OERSignInSupersession)
            }
        }
        # Not vacuous: the table holds the finished command with an identity that differs from the
        # state, so only its absence from the call stack keeps it out.
        $R.Held | Should -BeTrue
        $R.Differs | Should -BeTrue
        $R.Supersession.Count | Should -Be 0
    }

    It 'does not compare a command that remembers nothing' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-ProbeCommand {
                [CmdletBinding()]
                param([switch]$Remember)
                if ($Remember) {
                    Register-OERSignInIdentity -Invocation $MyInvocation
                }
                $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                @(Get-OERSignInSupersession)
            }
            # Not vacuous: the same command, with a memory, is named; that call also creates the table.
            $With = Invoke-ProbeCommand -Remember
            $script:_OERAuthState.TenantId = '11111111-1111-1111-1111-111111111111'
            $Without = Invoke-ProbeCommand
            @{ With = @($With); Without = @($Without); TableExists = $null -ne $script:_OERSignInIdentity }
        }
        $R.TableExists | Should -BeTrue
        $R.With.Count | Should -Be 1
        $R.With[0] | Should -BeExactly 'Invoke-ProbeCommand'
        $R.Without.Count | Should -Be 0
    }

    It 'names the command when its memory differs from the state only in <Term>' -ForEach @(
        @{ Term = 'TenantId'; Value = '22222222-2222-2222-2222-222222222222' }
        @{ Term = 'AuthMethod'; Value = 'DeviceCode' }
        @{ Term = 'ClientId'; Value = '44444444-4444-4444-4444-444444444444' }
        @{ Term = 'Environment'; Value = 'USGov' }
    ) {
        $R = InModuleScope Omnicit.EntraRBAC -Parameters @{ Term = $Term; Value = $Value } {
            param($Term, $Value)
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param([string]$Term, [string]$Value)
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState[$Term] = $Value
                Get-OERSignInSupersession
            }
            Invoke-SignedInCommand -Term $Term -Value $Value
        }
        $R | Should -BeOfType ([string])
        $R | Should -BeExactly 'Invoke-SignedInCommand'
    }

    It 'compares without regard to case' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                $script:_OERAuthState.TenantId = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState.TenantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                $Value = $null
                $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                @{
                    CaseDiffers  = $Value -cne (Get-OERSignInIdentity)
                    Supersession = @(Get-OERSignInSupersession)
                }
            }
            Invoke-SignedInCommand
        }
        # Not vacuous: the remembered string and the state's differ, in case only.
        $R.CaseDiffers | Should -BeTrue
        $R.Supersession.Count | Should -Be 0
    }

    It 'names an outer command whose memory differs while the command nested in it remembers the state' {
        # A nested command's own memory equals the state, so the walk must not stop at the nearest
        # remembering frame.
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param()
                $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                @{
                    NestedHeld   = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                    NestedEquals = $Value -eq (Get-OERSignInIdentity)
                    Supersession = Get-OERSignInSupersession
                }
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                Invoke-NestedCommand
            }
            Invoke-OuterCommand
        }
        $R.NestedHeld | Should -BeTrue
        $R.NestedEquals | Should -BeTrue
        $R.Supersession | Should -BeExactly 'Invoke-OuterCommand'
    }

    It 'names the innermost differing command when two differ' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-InnerCommand {
                [CmdletBinding()]
                param()
                $script:_OERAuthState.TenantId = '33333333-3333-3333-3333-333333333333'
                Get-OERSignInSupersession
            }
            function Invoke-MiddleCommand {
                [CmdletBinding()]
                param()
                $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                Register-OERSignInIdentity -Invocation $MyInvocation
                Invoke-InnerCommand
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                Invoke-MiddleCommand
            }
            Invoke-OuterCommand
        }
        $R | Should -BeExactly 'Invoke-MiddleCommand'
    }

    It 'treats no state at all as a difference for a remembering command' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState = $null
                Get-OERSignInSupersession
            }
            Invoke-SignedInCommand
        }
        $R | Should -BeExactly 'Invoke-SignedInCommand'
    }

    It 'names a remembering script block that carries no command name ''a script block''' {
        $R = InModuleScope Omnicit.EntraRBAC {
            & {
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                Get-OERSignInSupersession
            }
        }
        $R | Should -BeExactly 'a script block'
    }

    It 'still names the differing command while a function named Get-PSCallStack that returns nothing is defined' {
        # Get-OERSignInSupersession calls Microsoft.PowerShell.Utility\Get-PSCallStack. An unqualified
        # call would resolve to this global function, which outranks the cmdlet for module code, and
        # walk an empty stack.
        function global:Get-PSCallStack { }
        try {
            $R = InModuleScope Omnicit.EntraRBAC {
                function Invoke-SignedInCommand {
                    [CmdletBinding()]
                    param()
                    Register-OERSignInIdentity -Invocation $MyInvocation
                    $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                    Get-OERSignInSupersession
                }
                Invoke-SignedInCommand
            }
        } finally {
            # Unqualified on purpose: a scope-qualified function: path removes nothing (see
            # OERTransportTripwire.ps1), and from here the nearest definition is the global one.
            Remove-Item -Path 'function:Get-PSCallStack' -ErrorAction SilentlyContinue
        }
        Get-Command -Name Get-PSCallStack -CommandType Function -ErrorAction Ignore | Should -BeNullOrEmpty
        $R | Should -BeExactly 'Invoke-SignedInCommand'
    }
}
