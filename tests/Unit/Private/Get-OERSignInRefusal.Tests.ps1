BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSignInRefusal' {
    # Lock-OERSignIn is reached through a stand-in for Initialize-OERAuth, its only caller in source/.

    It 'returns nothing at once, without reading the call stack, when the latch table was never created' {
        Mock -ModuleName Omnicit.EntraRBAC Get-PSCallStack { }
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore
            @(Get-OERSignInRefusal)
        }
        $R.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-PSCallStack -Times 0
    }

    It 'returns the name of the refused command when that command is the caller' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                Get-OERSignInRefusal
            }
            Invoke-RefusedCommand
        }
        $R | Should -BeOfType ([string])
        $R | Should -BeExactly 'Invoke-RefusedCommand'
    }

    It 'finds a held frame two levels up the call stack' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-Deeper { Get-OERSignInRefusal }
            function Invoke-Nested { Invoke-Deeper }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                Invoke-Nested
            }
            Invoke-RefusedCommand
        }
        $R | Should -BeExactly 'Invoke-RefusedCommand'
    }

    It 'names the innermost held command when more than one frame is held' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-InnerRefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                Get-OERSignInRefusal
            }
            function Invoke-OuterRefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                Invoke-InnerRefusedCommand
            }
            Invoke-OuterRefusedCommand
        }
        $R | Should -BeExactly 'Invoke-InnerRefusedCommand'
    }

    It 'names a held script block that carries no command name ''a script block''' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            & {
                Initialize-StandIn
                Get-OERSignInRefusal
            }
        }
        $R | Should -BeExactly 'a script block'
    }

    It 'returns nothing after Unlock-OERSignIn released the frame' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                $Caller = Initialize-StandIn
                $Before = Get-OERSignInRefusal
                Unlock-OERSignIn -Invocation $Caller
                @{ Before = $Before; After = @(Get-OERSignInRefusal) }
            }
            Invoke-RefusedCommand
        }
        # Not vacuous: the same frame was held before the release.
        $R.Before | Should -BeExactly 'Invoke-RefusedCommand'
        $R.After.Count | Should -Be 0
    }

    It 'returns nothing from a later command once the refused one has finished' {
        $First = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                Get-OERSignInRefusal
            }
            Invoke-RefusedCommand
        }
        $Later = InModuleScope Omnicit.EntraRBAC {
            @{ TableExists = $null -ne $script:_OERSignInLatch; Refusal = @(Get-OERSignInRefusal) }
        }
        $First | Should -BeExactly 'Invoke-RefusedCommand'
        # The table is there, so the later read walked the stack and found no held frame.
        $Later.TableExists | Should -BeTrue
        $Later.Refusal.Count | Should -Be 0
    }
}
