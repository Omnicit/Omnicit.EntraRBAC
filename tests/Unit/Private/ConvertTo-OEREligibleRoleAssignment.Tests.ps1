BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OEREligibleRoleAssignment' {
    It 'maps a roleEligibilitySchedule and exposes the alias id' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id   = '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'
                name = 'sch1'
                properties = [PSCustomObject]@{
                    scope='/subscriptions/s1'; roleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    principalId='p1'; principalType='User'; status='Provisioned'; memberType='Direct'
                    startDateTime='2026-06-13T00:00:00Z'; endDateTime='2027-06-13T00:00:00Z'
                    createdOn='2026-06-13T00:00:00Z'; updatedOn='2026-06-13T00:00:00Z'
                    roleEligibilityScheduleRequestId='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilityScheduleRequests/req1'
                    expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{ displayName='Anna Berg' }
                        roleDefinition=[PSCustomObject]@{ displayName='Contributor' }; scope=[PSCustomObject]@{ displayName='Prod' } }
                }
            }
            $O = ConvertTo-OEREligibleRoleAssignment -InputObject $Raw
            $O.RoleEligibilityScheduleId | Should -Be $O.Id
            $O.MemberType                | Should -Be 'Direct'
            $O.RoleName                  | Should -Be 'Contributor'
            $O.PrincipalDisplayName      | Should -Be 'Anna Berg'
            $O.Status                    | Should -Be 'Provisioned'
            $O.PSObject.TypeNames[0]     | Should -Be 'Omnicit.EntraRBAC.EligibleRoleAssignment'
        }
    }

    It 'projects the ABAC condition so it can be read back' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id = '/x/providers/Microsoft.Authorization/roleEligibilitySchedules/n'
                name = 'n'
                properties = [PSCustomObject]@{
                    scope = '/x'; principalId = 'p'; roleDefinitionId = '/r'
                    condition = "@Resource[a] StringEquals 'b'"; conditionVersion = '2.0'
                }
            }
            $Out = ConvertTo-OEREligibleRoleAssignment -InputObject $Raw
            $Out.Condition        | Should -Be "@Resource[a] StringEquals 'b'"
            $Out.ConditionVersion | Should -Be '2.0'
        }
    }

    It 'stores the role eligibility schedule id exactly once and aliases Id to it' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OEREligibleRoleAssignment -InputObject @{
                id = '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilitySchedules/sch1'
                name = 'sch1'
                properties = @{ scope = '/subscriptions/s1'; roleDefinitionId = '/rd1'; principalId = 'p1' }
            }
            $Out.RoleEligibilityScheduleId | Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilitySchedules/sch1'
            $Out.Id | Should -Be $Out.RoleEligibilityScheduleId
            $Out.PSObject.Properties['RoleEligibilityScheduleId'].MemberType | Should -Be 'NoteProperty'
            $Out.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
        }
    }
}
