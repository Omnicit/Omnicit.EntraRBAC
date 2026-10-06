BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Unlock-OERSignIn' {
    # Lock-OERSignIn is reached through a stand-in for Initialize-OERAuth, its only caller in source/.

    It 'releases the invocation it is given' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-SignInCaller {
                [CmdletBinding()]
                param()
                $Caller = Initialize-StandIn
                $Value = $null
                $HeldBefore = $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                Unlock-OERSignIn -Invocation $Caller
                @{ HeldBefore = $HeldBefore; HeldAfter = $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value) }
            }
            Invoke-SignInCaller
        }
        $R.HeldBefore | Should -BeTrue
        $R.HeldAfter | Should -BeFalse
    }

    It 'releases only that invocation, keeping an outer command latched' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param()
                $Caller = Initialize-StandIn
                Unlock-OERSignIn -Invocation $Caller
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                $null = Initialize-StandIn
                Invoke-NestedCommand
                $Value = $null
                $script:_OERSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
            }
            Invoke-OuterCommand
        }
        $R | Should -BeTrue
    }

    It 'does nothing when there is no latch table, and creates none' {
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore
            $Output = @(Unlock-OERSignIn -Invocation $MyInvocation -ErrorAction Stop)
            @{ Count = $Output.Count; TableExists = $null -ne (Get-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore) }
        }
        $R.Count | Should -Be 0
        $R.TableExists | Should -BeFalse
    }

    It 'writes nothing to the pipeline when it releases' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-SignInCaller {
                [CmdletBinding()]
                param()
                $Caller = Initialize-StandIn
                @(Unlock-OERSignIn -Invocation $Caller).Count
            }
            Invoke-SignInCaller
        }
        $R | Should -Be 0
    }

    It 'requires the invocation to release' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command Unlock-OERSignIn).Parameters['Invocation'] }
        $Parameter.ParameterType | Should -Be ([System.Management.Automation.InvocationInfo])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}
