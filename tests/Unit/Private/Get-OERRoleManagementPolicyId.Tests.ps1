BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERRoleManagementPolicyId' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'lists assignments at scope (no $filter) and matches roleDefinitionId client-side' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-other'; policyId = '/s/pol-other'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Other' } } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd1'; policyId = '/s/pol1'; scope = '/s'; effectiveRules = @([PSCustomObject]@{ id = 'X' }); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' } } } }
                ) }
            }
            $r = Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1'
            $r.PolicyId | Should -Be '/s/pol1'
            $r.RoleDefinitionId | Should -Be '/s/rd1'
            $r.RoleName | Should -Be 'Reader'
            $r.Scope | Should -Be '/s'
            @($r.EffectiveRules).Count | Should -Be 1
            Should -Invoke Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01' -and $Path -notlike '*$filter*' -and $All -eq $true
            }
        }
    }

    It 'throws when no assignment matches the role' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' } | Should -Throw '*was found*'
        }
    }
}
