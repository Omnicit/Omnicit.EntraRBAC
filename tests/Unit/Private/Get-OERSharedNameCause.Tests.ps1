BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSharedNameCause' {
    It 'returns the exact cause text for a group path' {
        InModuleScope Omnicit.EntraRBAC {
            $Cause = Get-OERSharedNameCause -Path 'groups/Admins'
            $Cause | Should -BeOfType ([string])
            $Cause | Should -BeExactly 'Two or more live objects share the name groups/Admins (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
        }
    }

    It 'puts the path in the sentence exactly as given, whatever section it names' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERSharedNameCause -Path 'accessPackages/Catalog One/Package' |
                Should -BeExactly 'Two or more live objects share the name accessPackages/Catalog One/Package (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
        }
    }
}
