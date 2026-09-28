BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERDirectoryRolePolicyAssignment' {
    It 'lists every directory role policy assignment when -RoleDefinitionId is omitted' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                value = @(
                    @{ policyId = 'DirectoryRole_pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = @{ rules = @() } }
                    @{ policyId = 'DirectoryRole_pol2'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000002'; policy = @{ rules = @() } }
                )
            }
        }
        InModuleScope $script:moduleName {
            $Result = Get-OERDirectoryRolePolicyAssignment
            $Result.Count | Should -Be 2
            $Result[0].policyId | Should -Be 'DirectoryRole_pol1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $All -and
            $Uri -eq "v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'&`$expand=policy(`$expand=rules)"
        }
    }

    It 'filters by role definition id, escaped through ConvertTo-OERODataFilterValue' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ policyId = 'DirectoryRole_pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = @{ rules = @() } }) }
        }
        InModuleScope $script:moduleName {
            $Result = Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId 'aaaaaaaa-0000-0000-0000-000000000001'
            $Result.Count | Should -Be 1
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $All -and
            $Uri -eq "v1.0/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq 'aaaaaaaa-0000-0000-0000-000000000001'&`$expand=policy(`$expand=rules)"
        }
    }

    It 'escapes a single quote embedded in the role definition id filter' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId "id'x" | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            $Uri -match 'id%27%27x'
        }
    }

    It 'returns no assignment when Graph lists none' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            $Result = Get-OERDirectoryRolePolicyAssignment
            $Result | Should -BeNullOrEmpty
        }
    }

    It 'propagates a transport failure instead of swallowing it' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'Forbidden: insufficient privileges' }
        InModuleScope $script:moduleName {
            { Get-OERDirectoryRolePolicyAssignment } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }
}
