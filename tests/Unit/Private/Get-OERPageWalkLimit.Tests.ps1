BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERPageWalkLimit' {
    It 'returns 100000' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERPageWalkLimit | Should -Be 100000
        }
    }

    It 'returns exactly one value, typed as an int' {
        InModuleScope Omnicit.EntraRBAC {
            $Result = @(Get-OERPageWalkLimit)
            $Result.Count | Should -Be 1
            $Result[0] | Should -BeOfType ([int])
        }
    }

    It 'takes no parameters' {
        InModuleScope Omnicit.EntraRBAC {
            $Command = Get-Command Get-OERPageWalkLimit
            $Own = @($Command.Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters })
            $Own.Count | Should -Be 0
        }
    }
}
