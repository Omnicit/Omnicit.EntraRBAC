BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERDirectoryRolePolicy' {
    It 'reads the policy by id with $expand=rules' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'DirectoryRole_pol1'; rules = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) }
        }
        $Result = InModuleScope $script:moduleName { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' }
        $Result.rules.Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -eq "v1.0/policies/roleManagementPolicies/DirectoryRole_pol1`?`$expand=rules"
        }
    }

    It 'propagates a transport failure instead of swallowing it' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'Forbidden: insufficient privileges' }
        InModuleScope $script:moduleName {
            { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }

    It 'rejects an empty string for -PolicyId at parameter binding' {
        InModuleScope $script:moduleName {
            { Get-OERDirectoryRolePolicy -PolicyId '' } | Should -Throw -ExpectedMessage '*empty string*'
        }
    }
}
