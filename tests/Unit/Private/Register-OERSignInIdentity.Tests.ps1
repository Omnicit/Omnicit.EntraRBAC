BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Register-OERSignInIdentity' {
    # Initialize-OERAuth is the only caller in source/. These tests call Register-OERSignInIdentity from
    # a stand-in command with that command's own $MyInvocation, which is the object Lock-OERSignIn
    # returns for the command that called Initialize-OERAuth.
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

    It 'creates the memory table on first use and stores the identity for the invocation' {
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                @{
                    TableType = if ($null -ne $script:_OERSignInIdentity) { $script:_OERSignInIdentity.GetType().FullName } else { '' }
                    Held      = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                    Value     = $Value
                    Identity  = Get-OERSignInIdentity
                }
            }
            Invoke-SignedInCommand
        }
        $R.TableType | Should -BeExactly ([System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]).FullName
        $R.Held | Should -BeTrue
        $R.Value | Should -BeOfType ([string])
        $R.Value | Should -BeExactly $R.Identity
        $R.Value | Should -BeExactly "11111111-1111-1111-1111-111111111111`nInteractive`n33333333-3333-3333-3333-333333333333`nGlobal"
    }

    It 'replaces the value a second call for the same invocation stores' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                $First = $Value
                $script:_OERAuthState.TenantId = '22222222-2222-2222-2222-222222222222'
                Register-OERSignInIdentity -Invocation $MyInvocation
                $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                @{ First = $First; Second = $Value; Identity = Get-OERSignInIdentity }
            }
            Invoke-SignedInCommand
        }
        $R.First | Should -Match '^11111111-1111-1111-1111-111111111111\n'
        $R.Second | Should -BeExactly $R.Identity
        $R.Second | Should -Match '^22222222-2222-2222-2222-222222222222\n'
    }

    It 'removes the invocation''s entry when the module holds no state' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                $HeldBefore = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                $script:_OERAuthState = $null
                Register-OERSignInIdentity -Invocation $MyInvocation
                @{ HeldBefore = $HeldBefore; HeldAfter = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value) }
            }
            Invoke-SignedInCommand
        }
        $R.HeldBefore | Should -BeTrue
        $R.HeldAfter | Should -BeFalse
    }

    It 'does nothing when the module holds no state and there is no table, and creates none' {
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
            $script:_OERAuthState = $null
            $Output = @(Register-OERSignInIdentity -Invocation $MyInvocation -ErrorAction Stop)
            @{ Count = $Output.Count; TableExists = $null -ne (Get-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore) }
        }
        $R.Count | Should -Be 0
        $R.TableExists | Should -BeFalse
    }

    It 'stores for exactly the invocation it is given and no other' {
        # The nested command registers the OUTER command's invocation, as Initialize-OERAuth registers
        # the one Lock-OERSignIn returned rather than its own.
        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param([System.Management.Automation.InvocationInfo]$Given)
                Register-OERSignInIdentity -Invocation $Given
                $Value = $null
                $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                $NestedHeld = Invoke-NestedCommand -Given $MyInvocation
                $Entries = @(foreach ($Pair in $script:_OERSignInIdentity) { $Pair })
                @{
                    NestedHeld = $NestedHeld
                    Count      = $Entries.Count
                    KeyIsOuter = $Entries.Count -eq 1 -and [object]::ReferenceEquals($Entries[0].Key, $MyInvocation)
                }
            }
            Invoke-OuterCommand
        }
        $R.NestedHeld | Should -BeFalse
        $R.Count | Should -Be 1
        $R.KeyIsOuter | Should -BeTrue
    }

    It 'writes nothing to the pipeline when it stores' {
        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                @(Register-OERSignInIdentity -Invocation $MyInvocation).Count
            }
            Invoke-SignedInCommand
        }
        $R | Should -Be 0
    }

    It 'requires the invocation to remember' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command Register-OERSignInIdentity).Parameters['Invocation'] }
        $Parameter.ParameterType | Should -Be ([System.Management.Automation.InvocationInfo])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}
