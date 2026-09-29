BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERDirectoryRolePermanentAllowed' {
    It 'returns $false for -Kind Eligible when isExpirationRequired is $true on the Eligibility rule' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRolePolicyAssignment {
                @(
                    [PSCustomObject]@{
                        policyId         = 'DirectoryRole_pol1'
                        roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                        policy           = [PSCustomObject]@{
                            rules = @(
                                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
                                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $true }
                            )
                        }
                    }
                )
            }
            Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Eligible | Should -BeFalse
        }
    }

    It 'returns $true for -Kind Eligible when isExpirationRequired is $false on the Eligibility rule' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRolePolicyAssignment {
                @(
                    [PSCustomObject]@{
                        policyId         = 'DirectoryRole_pol1'
                        roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                        policy           = [PSCustomObject]@{
                            rules = @(
                                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }
                            )
                        }
                    }
                )
            }
            Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Eligible | Should -BeTrue
        }
    }

    It 'reads the Assignment rule (not the Eligibility rule) for -Kind Active, and the two kinds disagree when their rules do' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRolePolicyAssignment {
                @(
                    [PSCustomObject]@{
                        policyId         = 'DirectoryRole_pol1'
                        roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                        policy           = [PSCustomObject]@{
                            rules = @(
                                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
                                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $false }
                            )
                        }
                    }
                )
            }
            Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Eligible | Should -BeFalse
            Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Active | Should -BeTrue
        }
    }

    It 'returns $null when no policy assignment is found for the role' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRolePolicyAssignment { @() }
            Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Eligible | Should -BeNullOrEmpty
        }
    }

    It 'propagates a read failure' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRolePolicyAssignment { throw 'transport failure' }
            { Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001' -Kind Eligible } | Should -Throw 'transport failure'
        }
    }
}
