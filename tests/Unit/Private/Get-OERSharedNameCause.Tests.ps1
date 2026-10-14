BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSharedNameCause' {
    It 'returns the exact cause text for a group path, naming the count' {
        InModuleScope Omnicit.EntraRBAC {
            $Cause = Get-OERSharedNameCause -Path 'groups/Admins' -Count 2
            $Cause | Should -BeOfType ([string])
            $Cause | Should -BeExactly '2 live objects share the name groups/Admins (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
        }
    }

    It 'puts the path and the count in the sentence exactly as given, whatever section it names' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERSharedNameCause -Path 'accessPackages/Catalog One/Package' -Count 3 |
                Should -BeExactly '3 live objects share the name accessPackages/Catalog One/Package (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
        }
    }

    It 'declares -Path and -Count mandatory, so no caller can leave the count out' {
        InModuleScope Omnicit.EntraRBAC {
            $Command = Get-Command Get-OERSharedNameCause
            foreach ($Name in @('Path', 'Count')) {
                $Mandatory = @($Command.Parameters[$Name].Attributes |
                        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory })
                $Mandatory.Count | Should -BeGreaterThan 0 -Because "-$Name is mandatory"
            }
            $Command.Parameters['Count'].ParameterType | Should -Be ([int])
        }
    }
}
