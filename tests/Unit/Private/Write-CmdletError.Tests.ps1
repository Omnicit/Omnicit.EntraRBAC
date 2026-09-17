BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Write-CmdletError' {
    It 'emits a non-terminating error with the given ErrorId' {
        $Err = $null
        InModuleScope $script:moduleName {
            function Invoke-Target {
                [CmdletBinding()] param()
                Write-CmdletError -Message ([System.Exception]::new('boom')) -ErrorId 'TestId' -Cmdlet $PSCmdlet
            }
            Invoke-Target -ErrorVariable script:captured -ErrorAction SilentlyContinue
        }
        $captured = InModuleScope $script:moduleName { $script:captured }
        $captured.FullyQualifiedErrorId | Should -Match 'TestId'
    }

    It 'throws a terminating error when -Terminating is set' {
        InModuleScope $script:moduleName {
            function Invoke-Target2 {
                [CmdletBinding()] param()
                Write-CmdletError -Message ([System.Exception]::new('fatal')) -ErrorId 'FatalId' -Cmdlet $PSCmdlet -Terminating
            }
            { Invoke-Target2 } | Should -Throw
        }
    }

    It 'does not capture the callers caught ErrorRecord as TargetObject' {
        InModuleScope $script:moduleName {
            # A parameter default resolves $PSItem through the CALLER's dynamic scope, so a bare call
            # from inside a catch used to bind the caught record as the new error's TargetObject.
            function Test-BareCallFromCatch {
                [CmdletBinding()]
                param()
                try { throw [System.Exception]::new('inner boom') }
                catch {
                    Write-CmdletError -Message ([System.Exception]::new('outer')) `
                        -ErrorId 'Outer' -Cmdlet $PSCmdlet
                }
            }

            $Err = $null
            Test-BareCallFromCatch -ErrorVariable Err -ErrorAction SilentlyContinue

            $Target = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Outer,Test-BareCallFromCatch' })[0].TargetObject
            $Target | Should -BeNullOrEmpty
            $Target -is [System.Management.Automation.ErrorRecord] | Should -Be $false
        }
    }

    It 'still honours an explicitly supplied TargetObject' {
        InModuleScope $script:moduleName {
            function Test-ExplicitTarget {
                [CmdletBinding()]
                param()
                Write-CmdletError -Message ([System.Exception]::new('boom')) -ErrorId 'Boom' `
                    -TargetObject 'group-123' -Cmdlet $PSCmdlet
            }
            $Err = $null
            Test-ExplicitTarget -ErrorVariable Err -ErrorAction SilentlyContinue
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Boom,Test-ExplicitTarget' })[0].TargetObject |
                Should -Be 'group-123'
        }
    }
}
