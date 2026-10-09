BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERTokenRenewalThreshold' {
    # The single owner of the module's token renewal window (A11, BL-105): Initialize-OERAuth reads it
    # for its cached return, and both transports read it before every request. A token that expires at
    # or before the returned instant is due for renewal.
    It 'returns a UTC instant five minutes from now' {
        $R = InModuleScope Omnicit.EntraRBAC {
            $Before = [DateTime]::UtcNow.AddMinutes(5)
            $Threshold = Get-OERTokenRenewalThreshold
            $After = [DateTime]::UtcNow.AddMinutes(5)
            @{ Before = $Before; Threshold = $Threshold; After = $After }
        }

        $R.Threshold | Should -BeOfType ([datetime])
        $R.Threshold.Kind | Should -Be ([System.DateTimeKind]::Utc)
        $R.Threshold | Should -BeGreaterOrEqual $R.Before
        $R.Threshold | Should -BeLessOrEqual $R.After
    }

    It 'returns one value and writes nothing else' {
        $R = InModuleScope Omnicit.EntraRBAC {
            @(Get-OERTokenRenewalThreshold)
        }

        $R.Count | Should -Be 1
    }
}
