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

Describe 'Test-OERJsonDateKindSupport (BL-154)' {
    # ConvertFrom-Json gained -DateKind in PowerShell 7.5. The function asks the running PowerShell,
    # so the known answer here comes from the version number, which is independent of the command's
    # own metadata the function reads.
    It 'answers for the running PowerShell: true from 7.5 on, false before' {
        $Expected = $PSVersionTable.PSVersion -ge [version]'7.5'
        $Answer = InModuleScope $script:moduleName { Test-OERJsonDateKindSupport }
        $Answer | Should -BeOfType [bool]
        $Answer | Should -Be $Expected
    }

    It 'answers true when ConvertFrom-Json has a DateKind parameter' {
        InModuleScope $script:moduleName {
            Mock Get-Command {
                [PSCustomObject]@{ Parameters = @{ InputObject = $null; DateKind = $null } }
            } -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
            Mock Get-Command { Microsoft.PowerShell.Core\Get-Command @PesterBoundParameters }
            Test-OERJsonDateKindSupport | Should -BeTrue
            Should -Invoke Get-Command -Exactly -Times 1 -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
        }
    }

    It 'answers false when ConvertFrom-Json has no DateKind parameter' {
        InModuleScope $script:moduleName {
            Mock Get-Command {
                [PSCustomObject]@{ Parameters = @{ InputObject = $null; Depth = $null } }
            } -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
            Mock Get-Command { Microsoft.PowerShell.Core\Get-Command @PesterBoundParameters }
            Test-OERJsonDateKindSupport | Should -BeFalse
            Should -Invoke Get-Command -Exactly -Times 1 -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
        }
    }

    It 'answers false, and writes nothing, when the command cannot be found' {
        InModuleScope $script:moduleName {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
            Mock Get-Command { Microsoft.PowerShell.Core\Get-Command @PesterBoundParameters }
            $Error.Clear()
            Test-OERJsonDateKindSupport | Should -BeFalse
            Should -Invoke Get-Command -Exactly -Times 1 -ParameterFilter { $Name -eq 'Microsoft.PowerShell.Utility\ConvertFrom-Json' }
            $Error.Count | Should -Be 0
        }
    }

    It 'asks about the module-qualified cmdlet, so a function of the same name in the session is never the one asked' {
        InModuleScope $script:moduleName {
            # A function named ConvertFrom-Json that has no DateKind parameter, defined where the module
            # resolves commands, must not turn the answer to false on a PowerShell whose cmdlet has one:
            # the lookup names the cmdlet's module. A plain Get-Command ConvertFrom-Json finds the
            # function first (functions outrank cmdlets), so the control below shows the shadow is in force.
            function script:ConvertFrom-Json { param($InputObject) }
            try {
                (Get-Command -Name ConvertFrom-Json).CommandType | Should -Be 'Function' -Because 'the shadow must be what an unqualified lookup finds'
                $Expected = $PSVersionTable.PSVersion -ge [version]'7.5'
                Test-OERJsonDateKindSupport | Should -Be $Expected
            } finally {
                Remove-Item -LiteralPath 'function:ConvertFrom-Json'
            }
            Get-Command -Name ConvertFrom-Json | ForEach-Object { $_.CommandType } | Should -Be 'Cmdlet'
        }
    }
}
