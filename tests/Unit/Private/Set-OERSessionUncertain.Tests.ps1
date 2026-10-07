BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Set-OERSessionUncertain' {
    # The session-uncertain marker (A10, BL-89). The tests write the module variable directly to set up
    # a state; the module itself reads and writes it only through this helper, which
    # tests/QA/sourcehygiene.tests.ps1 holds.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { Remove-Variable -Scope Script -Name _OERSessionUncertain -ErrorAction Ignore }
    }

    It 'returns $false and sets the marker when it is set from a fresh module' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $Existed = $null -ne (Get-Variable -Scope Script -Name _OERSessionUncertain -ErrorAction Ignore)
            $Previous = Set-OERSessionUncertain -Value $true
            @{ Existed = $Existed; Previous = $Previous; Now = $script:_OERSessionUncertain }
        }

        # Not vacuous: the module held no marker at all before the call.
        $R.Existed | Should -BeFalse
        $R.Previous | Should -BeOfType ([bool])
        $R.Previous | Should -BeFalse
        $R.Now | Should -BeOfType ([bool])
        $R.Now | Should -BeTrue
    }

    It 'returns $true and clears the marker when it is cleared after being set' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERSessionUncertain = $true
            $Previous = Set-OERSessionUncertain -Value $false
            @{ Previous = $Previous; Now = $script:_OERSessionUncertain }
        }

        $R.Previous | Should -BeOfType ([bool])
        $R.Previous | Should -BeTrue
        $R.Now | Should -BeOfType ([bool])
        $R.Now | Should -BeFalse
    }

    It 'reads a $null marker as $false' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $script:_OERSessionUncertain = $null
            $Previous = Set-OERSessionUncertain -Value $true
            @{ Previous = $Previous; Now = $script:_OERSessionUncertain }
        }

        $R.Previous | Should -BeOfType ([bool])
        $R.Previous | Should -BeFalse
        $R.Now | Should -BeTrue
    }

    It 'returns $true and keeps the marker set when it is set twice' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $First = Set-OERSessionUncertain -Value $true
            $Second = Set-OERSessionUncertain -Value $true
            @{ First = $First; Second = $Second; Now = $script:_OERSessionUncertain }
        }

        $R.First | Should -BeFalse
        $R.Second | Should -BeTrue
        $R.Now | Should -BeTrue
    }

    It 'requires a boolean value' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command Set-OERSessionUncertain).Parameters['Value'] }
        $Parameter.ParameterType | Should -Be ([bool])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }

    It 'returns exactly one value' {
        $R = InModuleScope Omnicit.EntraRBAC { @(Set-OERSessionUncertain -Value $true) }
        $R.Count | Should -Be 1
    }
}
