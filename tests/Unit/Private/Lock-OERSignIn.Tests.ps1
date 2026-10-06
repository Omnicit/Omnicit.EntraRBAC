BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Lock-OERSignIn' {
    # Initialize-OERAuth is the only caller in source/. These tests call Lock-OERSignIn through a
    # stand-in function in its place, so the frame Lock-OERSignIn skips is the stand-in's, and the
    # frame it latches is the command that called the stand-in.

    It 'returns the invocation of the command that called the stand-in for Initialize-OERAuth' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-SignInCaller {
                [CmdletBinding()]
                param()
                $Returned = Initialize-StandIn
                @{
                    Same = [object]::ReferenceEquals($Returned, $MyInvocation)
                    Type = if ($null -ne $Returned) { $Returned.GetType().FullName } else { '' }
                    Name = if ($null -ne $Returned) { [string]$Returned.MyCommand.Name } else { '' }
                }
            }
            Invoke-SignInCaller
        }
        $R.Type | Should -BeExactly 'System.Management.Automation.InvocationInfo'
        # Neither the stand-in's own frame nor the frame above the caller.
        $R.Name | Should -BeExactly 'Invoke-SignInCaller'
        $R.Same | Should -BeTrue -Because 'the latch key must be the very invocation object a transport finds on the call stack'
    }

    It 'latches the caller''s invocation with the boolean $true and nothing else' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-SignInCaller {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                $Value = $null
                $Held = $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                @{ Held = $Held; Value = $Value }
            }
            Invoke-SignInCaller
        }
        $R.Held | Should -BeTrue
        $R.Value | Should -BeOfType ([bool])
        $R.Value | Should -BeTrue
    }

    It 'creates the latch table on first use when there is none' {
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-SignInCaller {
                [CmdletBinding()]
                param()
                Initialize-StandIn
            }
            Invoke-SignInCaller
            if ($null -ne $script:_OERSignInLatch) { $script:_OERSignInLatch.GetType().FullName } else { '' }
        }
        $R | Should -BeExactly ([System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]).FullName
    }

    It 'latches the caller while a function named Get-PSCallStack that returns nothing is defined' {
        # Lock-OERSignIn calls Microsoft.PowerShell.Utility\Get-PSCallStack. An unqualified call would
        # resolve to this global function, which outranks the cmdlet for module code, and find no
        # caller to latch.
        function global:Get-PSCallStack { }
        try {
            $R = InModuleScope Omnicit.EntraRBAC {
                function Initialize-StandIn { $null = Lock-OERSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $Value = $null
                    $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                }
                Invoke-SignInCaller
            }
        } finally {
            # Unqualified on purpose: a scope-qualified function: path removes nothing (see
            # OERTransportTripwire.ps1), and from here the nearest definition is the global one.
            Remove-Item -Path 'function:Get-PSCallStack' -ErrorAction SilentlyContinue
        }
        Get-Command -Name Get-PSCallStack -CommandType Function -ErrorAction Ignore | Should -BeNullOrEmpty
        $R | Should -BeTrue
    }

    It 'keeps the table and the latch of an outer command when a nested command latches its own' {
        # The nested and pipeline cases A19 rests on: a second sign-in must never replace the table,
        # or every command latched before it would be released.
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                $TableBefore = $script:_OERSignInLatch
                Invoke-NestedCommand
                $Value = $null
                @{
                    SameTable = [object]::ReferenceEquals($TableBefore, $script:_OERSignInLatch)
                    OuterHeld = $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                }
            }
            Invoke-OuterCommand
        }
        $R.SameTable | Should -BeTrue
        $R.OuterHeld | Should -BeTrue
    }
}
