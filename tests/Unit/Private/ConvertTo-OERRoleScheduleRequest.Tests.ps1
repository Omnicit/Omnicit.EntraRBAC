BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERRoleScheduleRequest' {
    It 'maps the core request fields' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilityScheduleRequests/req1'
                name       = 'req1'
                properties = [PSCustomObject]@{
                    scope                             = '/subscriptions/s1'
                    roleDefinitionId                  = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    principalId                       = 'p1'
                    principalType                     = 'User'
                    requestType                       = 'AdminAssign'
                    status                            = 'Provisioned'
                    requestorId                       = 'p1'
                    createdOn                         = '2026-06-13T00:00:00Z'
                    justification                     = 'because'
                    approvalId                        = $null
                    linkedRoleEligibilityScheduleId   = 'elig1'
                    scheduleInfo                      = [PSCustomObject]@{
                        startDateTime = '2026-06-13T00:00:00Z'
                        expiration    = [PSCustomObject]@{
                            type        = 'AfterDuration'
                            duration    = 'PT8H'
                            endDateTime = $null
                        }
                    }
                    expandedProperties                = [PSCustomObject]@{
                        principal      = [PSCustomObject]@{ displayName = 'Anna Berg' }
                        roleDefinition = [PSCustomObject]@{ displayName = 'Contributor' }
                        scope          = [PSCustomObject]@{ displayName = 'Prod' }
                    }
                }
            }
            $O = ConvertTo-OERRoleScheduleRequest -InputObject $Raw
            $O.RequestType                      | Should -Be 'AdminAssign'
            $O.Status                           | Should -Be 'Provisioned'
            $O.RoleName                         | Should -Be 'Contributor'
            $O.PrincipalDisplayName             | Should -Be 'Anna Berg'
            $O.ExpirationType                   | Should -Be 'AfterDuration'
            $O.ExpirationDuration               | Should -Be 'PT8H'
            $O.LinkedRoleEligibilityScheduleId  | Should -Be 'elig1'
            $O.PSObject.TypeNames[0]            | Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
        }
    }

    It 'handles a request without linkedRoleEligibilityScheduleId' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/req2'
                name       = 'req2'
                properties = [PSCustomObject]@{
                    scope            = '/subscriptions/s1'
                    roleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd2'
                    principalId      = 'p2'
                    principalType    = 'Group'
                    requestType      = 'AdminRemove'
                    status           = 'Revoked'
                    requestorId      = 'p2'
                    createdOn        = '2026-06-13T00:00:00Z'
                    justification    = $null
                    approvalId       = $null
                    scheduleInfo     = [PSCustomObject]@{
                        startDateTime = '2026-06-13T00:00:00Z'
                        expiration    = [PSCustomObject]@{
                            type        = 'NoExpiration'
                            duration    = $null
                            endDateTime = $null
                        }
                    }
                    expandedProperties = [PSCustomObject]@{
                        principal      = [PSCustomObject]@{ displayName = 'Dev Team' }
                        roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }
                        scope          = [PSCustomObject]@{ displayName = 'Prod' }
                    }
                }
            }
            $O = ConvertTo-OERRoleScheduleRequest -InputObject $Raw
            $O.LinkedRoleEligibilityScheduleId | Should -BeNullOrEmpty
            $O.PSObject.TypeNames[0]           | Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
        }
    }

    It 'projects the ABAC condition and ticket info so they can be read back' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id = '/x/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/n'
                name = 'n'
                properties = [PSCustomObject]@{
                    scope = '/x'; principalId = 'p'; roleDefinitionId = '/r'
                    scheduleInfo = [PSCustomObject]@{ expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    condition = "@Resource[a] StringEquals 'b'"; conditionVersion = '2.0'
                    ticketInfo = [PSCustomObject]@{ ticketNumber = 'INC-42'; ticketSystem = 'ServiceNow' }
                }
            }
            $Out = ConvertTo-OERRoleScheduleRequest -InputObject $Raw
            $Out.Condition        | Should -Be "@Resource[a] StringEquals 'b'"
            $Out.ConditionVersion | Should -Be '2.0'
            $Out.TicketNumber     | Should -Be 'INC-42'
            $Out.TicketSystem     | Should -Be 'ServiceNow'
        }
    }

    It 'keeps a null ticketNumber/ticketSystem null when ticketInfo exists but is empty' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id = '/x/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/n'
                name = 'n'
                properties = [PSCustomObject]@{
                    scope = '/x'; principalId = 'p'; roleDefinitionId = '/r'
                    scheduleInfo = [PSCustomObject]@{ expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    ticketInfo = [PSCustomObject]@{ ticketNumber = $null; ticketSystem = $null }
                }
            }
            $Out = ConvertTo-OERRoleScheduleRequest -InputObject $Raw
            # Null-preserving, like the sibling Justification/Condition fields -- not '' .
            $Out.TicketNumber | Should -BeNullOrEmpty
            $Out.TicketSystem | Should -BeNullOrEmpty
            $null -eq $Out.TicketNumber | Should -BeTrue
            $null -eq $Out.TicketSystem | Should -BeTrue
        }
    }
}
