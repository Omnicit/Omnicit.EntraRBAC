BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERBuiltInDirectoryRoleName' {
    It 'returns the full built-in directory-role set from Microsoft Learn' {
        InModuleScope Omnicit.EntraRBAC {
            # Microsoft Learn, "Microsoft Entra built-in roles", All roles table, verified against the
            # live page on 2026-09-28: exactly 136 built-in role display names. This is the tenant-wide
            # superset behind Get-OERBuiltInDirectoryRoleName; Get-OERCommonDirectoryRoleName's
            # administrative-unit-scopable set is a subset of it (checked below).
            $Names = @(Get-OERBuiltInDirectoryRoleName)
            $Names.Count | Should -Be 136
            $Names | Should -Contain 'Reports Reader'
            $Names | Should -Contain 'Message Center Reader'
            $Names | Should -Contain 'Global Administrator'
            $Names | Should -Contain 'Privileged Role Administrator'
        }
    }

    It 'returns strings only' {
        InModuleScope Omnicit.EntraRBAC {
            foreach ($Name in (Get-OERBuiltInDirectoryRoleName)) { $Name | Should -BeOfType [string] }
        }
    }

    It 'contains no duplicates' {
        InModuleScope Omnicit.EntraRBAC {
            $Names = @(Get-OERBuiltInDirectoryRoleName)
            ($Names | Sort-Object -Unique).Count | Should -Be $Names.Count
        }
    }

    It 'contains ASCII characters only' {
        InModuleScope Omnicit.EntraRBAC {
            foreach ($Name in (Get-OERBuiltInDirectoryRoleName)) {
                $Name | Should -Not -Match '[^\x00-\x7F]'
            }
        }
    }

    It 'is a superset of the administrative-unit-scopable curated set' {
        InModuleScope Omnicit.EntraRBAC {
            $BuiltIn = @(Get-OERBuiltInDirectoryRoleName)
            foreach ($Name in (Get-OERCommonDirectoryRoleName)) { $BuiltIn | Should -Contain $Name }
        }
    }

    It 'makes no Graph call' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'completers must not call Graph' }
        InModuleScope Omnicit.EntraRBAC { $null = Get-OERBuiltInDirectoryRoleName }
        Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0
    }
}
