BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'ConvertTo-OERActiveRoleAssignment' {
    It 'maps a roleAssignmentSchedule and exposes the alias id and assignment type' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id   = '/subscriptions/s1/providers/Microsoft.Authorization/RoleAssignmentSchedules/sch1'
                name = 'sch1'
                properties = [PSCustomObject]@{
                    scope                          = '/subscriptions/s1'
                    roleDefinitionId               = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    principalId                    = 'p1'
                    principalType                  = 'User'
                    status                         = 'Provisioned'
                    memberType                     = 'Direct'
                    assignmentType                 = 'Activated'
                    linkedRoleEligibilityScheduleId = 'elig1'
                    startDateTime                  = '2026-06-13T00:00:00Z'
                    endDateTime                    = '2026-06-13T08:00:00Z'
                    createdOn                      = '2026-06-13T00:00:00Z'
                    updatedOn                      = '2026-06-13T00:00:00Z'
                    roleAssignmentScheduleRequestId = '/subscriptions/s1/providers/Microsoft.Authorization/RoleAssignmentScheduleRequests/req1'
                    expandedProperties             = [PSCustomObject]@{
                        principal      = [PSCustomObject]@{ displayName = 'Anna Berg' }
                        roleDefinition = [PSCustomObject]@{ displayName = 'Contributor' }
                        scope          = [PSCustomObject]@{ displayName = 'Prod' }
                    }
                }
            }
            $O = ConvertTo-OERActiveRoleAssignment -InputObject $Raw
            $O.RoleAssignmentScheduleId        | Should -Be $O.Id
            $O.AssignmentType                  | Should -Be 'Activated'
            $O.LinkedRoleEligibilityScheduleId | Should -Be 'elig1'
            $O.RoleName                        | Should -Be 'Contributor'
            $O.PrincipalDisplayName            | Should -Be 'Anna Berg'
            $O.PSObject.TypeNames[0]           | Should -Be 'Omnicit.EntraRBAC.ActiveRoleAssignment'
        }
    }

    It 'returns null LinkedRoleEligibilityScheduleId when property is absent' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id   = '/subscriptions/s1/providers/Microsoft.Authorization/RoleAssignmentSchedules/sch2'
                name = 'sch2'
                properties = [PSCustomObject]@{
                    scope                          = '/subscriptions/s1'
                    roleDefinitionId               = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    principalId                    = 'p2'
                    principalType                  = 'Group'
                    status                         = 'Provisioned'
                    memberType                     = 'Direct'
                    assignmentType                 = 'Assigned'
                    startDateTime                  = '2026-06-13T00:00:00Z'
                    endDateTime                    = $null
                    createdOn                      = '2026-06-13T00:00:00Z'
                    updatedOn                      = '2026-06-13T00:00:00Z'
                    roleAssignmentScheduleRequestId = '/subscriptions/s1/providers/Microsoft.Authorization/RoleAssignmentScheduleRequests/req2'
                    expandedProperties             = [PSCustomObject]@{
                        principal      = [PSCustomObject]@{ displayName = 'Ops Team' }
                        roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }
                        scope          = [PSCustomObject]@{ displayName = 'Prod' }
                    }
                }
            }
            $O = ConvertTo-OERActiveRoleAssignment -InputObject $Raw
            $O.LinkedRoleEligibilityScheduleId | Should -BeNullOrEmpty
        }
    }

    It 'projects the ABAC condition so it can be read back' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id = '/x/providers/Microsoft.Authorization/roleAssignmentSchedules/n'
                name = 'n'
                properties = [PSCustomObject]@{
                    scope = '/x'; principalId = 'p'; roleDefinitionId = '/r'
                    condition = "@Resource[a] StringEquals 'b'"; conditionVersion = '2.0'
                }
            }
            $Out = ConvertTo-OERActiveRoleAssignment -InputObject $Raw
            $Out.Condition        | Should -Be "@Resource[a] StringEquals 'b'"
            $Out.ConditionVersion | Should -Be '2.0'
        }
    }

    It 'stores the role assignment schedule id exactly once and aliases Id to it' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERActiveRoleAssignment -InputObject @{
                id = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentSchedules/sch1'
                name = 'sch1'
                properties = @{ scope = '/subscriptions/s1'; roleDefinitionId = '/rd1'; principalId = 'p1' }
            }
            $Out.RoleAssignmentScheduleId | Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentSchedules/sch1'
            $Out.Id | Should -Be $Out.RoleAssignmentScheduleId
            $Out.PSObject.Properties['RoleAssignmentScheduleId'].MemberType | Should -Be 'NoteProperty'
            $Out.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
        }
    }
}
