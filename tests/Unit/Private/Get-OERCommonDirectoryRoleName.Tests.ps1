BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERCommonDirectoryRoleName' {
    It 'returns the curated administrative-unit-scopable directory roles' {
        InModuleScope Omnicit.EntraRBAC {
            $Names = @(Get-OERCommonDirectoryRoleName)
            $Names.Count | Should -Be 14
            $Names | Should -Contain 'User Administrator'
            $Names | Should -Contain 'Groups Administrator'
            $Names | Should -Contain 'Helpdesk Administrator'
            $Names | Should -Contain 'Privileged Authentication Administrator'
            $Names | Should -Contain 'Teams Devices Administrator'
        }
    }

    It 'returns strings only' {
        InModuleScope Omnicit.EntraRBAC {
            foreach ($Name in (Get-OERCommonDirectoryRoleName)) { $Name | Should -BeOfType [string] }
        }
    }

    It 'contains no duplicates' {
        InModuleScope Omnicit.EntraRBAC {
            $Names = @(Get-OERCommonDirectoryRoleName)
            ($Names | Sort-Object -Unique).Count | Should -Be $Names.Count
        }
    }

    It 'does not leak Azure RBAC role names into the directory-role set' {
        InModuleScope Omnicit.EntraRBAC {
            $Names = @(Get-OERCommonDirectoryRoleName)
            $Names | Should -Not -Contain 'Contributor'
            $Names | Should -Not -Contain 'Owner'
            $Names | Should -Not -Contain 'Reader'
        }
    }

    It 'makes no Graph call' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'completers must not call Graph' }
        InModuleScope Omnicit.EntraRBAC { $null = Get-OERCommonDirectoryRoleName }
        Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0
    }
}
