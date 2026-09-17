BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERAmbiguousNameError' {
    It 'returns true for an ambiguity record' {
        InModuleScope $script:moduleName {
            $Rec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('two matches'), 'AmbiguousName',
                [System.Management.Automation.ErrorCategory]::InvalidArgument, 'RoleSec-Finance')
            Test-OERAmbiguousNameError -Record $Rec | Should -BeTrue
        }
    }

    It 'returns true when the id has been qualified with a command name' {
        InModuleScope $script:moduleName {
            # A record that has already crossed a WriteError boundary carries '<Id>,<Command>'.
            function Invoke-AmbiguityWriter {
                [CmdletBinding()]
                param()
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('two matches'), 'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument, 'RoleSec-Finance'))
            }
            Invoke-AmbiguityWriter -ErrorAction SilentlyContinue -ErrorVariable Written
            $Written[0].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Invoke-AmbiguityWriter'
            Test-OERAmbiguousNameError -Record $Written[0] | Should -BeTrue
        }
    }

    It 'returns false for an unrelated record' {
        InModuleScope $script:moduleName {
            $Rec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('throttled'), 'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded, 'x')
            # Should -BeFalse passes on $null, so assert the exact value.
            Test-OERAmbiguousNameError -Record $Rec | Should -Be $false
        }
    }

    It 'returns false for a record whose id merely contains the word later on' {
        InModuleScope $script:moduleName {
            $Rec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('nope'), 'GroupAmbiguousNameCheck',
                [System.Management.Automation.ErrorCategory]::InvalidOperation, 'x')
            Test-OERAmbiguousNameError -Record $Rec | Should -Be $false
        }
    }

    It 'returns false (never throws) for a null record' {
        InModuleScope $script:moduleName {
            Test-OERAmbiguousNameError -Record $null | Should -Be $false
        }
    }
}
