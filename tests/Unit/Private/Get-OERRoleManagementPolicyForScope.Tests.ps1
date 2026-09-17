BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERRoleManagementPolicyForScope' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'lists assignments at scope once (no $filter, -All) and maps every role' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-read'; policyId = '/s/pol-read'; scope = '/s'; effectiveRules = @([PSCustomObject]@{ id = 'X' }); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' } } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-own'; policyId = '/s/pol-own'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Owner' } } } }
                ) }
            }
            $r = @(Get-OERRoleManagementPolicyForScope -Scope '/s')
            $r.Count | Should -Be 2
            $r[0].PolicyId | Should -Be '/s/pol-read'
            $r[0].RoleDefinitionId | Should -Be '/s/rd-read'
            $r[0].RoleName | Should -Be 'Reader'
            $r[0].Scope | Should -Be '/s'
            @($r[0].EffectiveRules).Count | Should -Be 1
            $r[1].RoleName | Should -Be 'Owner'
            Should -Invoke Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01' -and $Path -notlike '*$filter*' -and $All -eq $true
            }
        }
    }

    It 'returns nothing for a scope with no policy assignments' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            @(Get-OERRoleManagementPolicyForScope -Scope '/s').Count | Should -Be 0
        }
    }
}
