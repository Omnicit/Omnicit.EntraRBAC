BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERCommonRoleName' {
    It 'returns exactly the five curated role display names in order' {
        InModuleScope Omnicit.EntraRBAC {
            $Names = @(Get-OERCommonRoleName)
            $Names.Count | Should -Be 5
            $Names | Should -Be @(
                'Reader'
                'Contributor'
                'Owner'
                'User Access Administrator'
                'Role Based Access Control Administrator'
            )
        }
    }

    It 'returns string values' {
        InModuleScope Omnicit.EntraRBAC {
            foreach ($Name in (Get-OERCommonRoleName)) { $Name | Should -BeOfType [string] }
        }
    }
}
