BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERDirectoryRoleAssignment' {
    It 'maps an eligibility schedule with an afterDateTime expiration to the tagged Eligible shape' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id               = 'aaaaaaaa-0000-0000-0000-000000000001'
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000002'
                roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                directoryScopeId = '/'
                memberType       = 'Direct'
                status           = 'Provisioned'
                createdDateTime  = '2026-08-01T00:00:00Z'
                scheduleInfo     = @{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = @{
                        type        = 'afterDateTime'
                        endDateTime = '2026-10-01T00:00:00Z'
                        duration    = $null
                    }
                }
                principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                roleDefinition   = @{ displayName = 'Reports Reader' }
            }
            $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.EligibleDirectoryRoleAssignment'
            $Out.PrincipalType | Should -Be 'User'
            $Out.RoleName | Should -Be 'Reports Reader'
            $Out.DurationDays | Should -Be 30
            $Out.PSObject.Properties.Name -contains 'AssignmentType' | Should -BeFalse
        }
    }

    It 'derives EndDateTime and DurationDays from an afterDuration expiration' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id               = 'aaaaaaaa-0000-0000-0000-000000000003'
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000004'
                roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                directoryScopeId = '/'
                memberType       = 'Direct'
                status           = 'Provisioned'
                createdDateTime  = '2026-08-01T00:00:00Z'
                scheduleInfo     = @{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = @{
                        type        = 'afterDuration'
                        endDateTime = $null
                        duration    = 'P30D'
                    }
                }
                principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                roleDefinition   = @{ displayName = 'Reports Reader' }
            }
            $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible
            $ExpectedEnd = [datetimeoffset]::Parse('2026-09-01T00:00:00Z').AddDays(30)
            [datetimeoffset]::Parse($Out.EndDateTime) | Should -Be $ExpectedEnd
            $Out.DurationDays | Should -Be 30
        }
    }

    It 'reports a noExpiration schedule as permanent (null EndDateTime and DurationDays)' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id               = 'aaaaaaaa-0000-0000-0000-000000000005'
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000006'
                roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                directoryScopeId = '/'
                memberType       = 'Direct'
                status           = 'Provisioned'
                createdDateTime  = '2026-08-01T00:00:00Z'
                scheduleInfo     = @{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = @{ type = 'noExpiration' }
                }
                principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                roleDefinition   = @{ displayName = 'Reports Reader' }
            }
            $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible
            $Out.EndDateTime | Should -BeNullOrEmpty
            $Out.DurationDays | Should -BeNullOrEmpty
            $Out.ExpirationType | Should -Be 'noExpiration'
        }
    }

    It 'tags an Active assignment schedule and passes AssignmentType through' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id               = 'aaaaaaaa-0000-0000-0000-000000000007'
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000008'
                roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                directoryScopeId = '/'
                memberType       = 'Direct'
                status           = 'Provisioned'
                assignmentType   = 'Activated'
                createdDateTime  = '2026-08-01T00:00:00Z'
                scheduleInfo     = @{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = @{ type = 'noExpiration' }
                }
                principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                roleDefinition   = @{ displayName = 'Reports Reader' }
            }
            $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Active
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ActiveDirectoryRoleAssignment'
            $Out.AssignmentType | Should -Be 'Activated'
        }
    }

    It 'exposes ScheduleId and DirectoryScopeId and never RoleEligibilityScheduleId or Scope (R3)' {
        # R3: an ARM cmdlet binds -RoleEligibilityScheduleId (Enable-/Disable-OEREligibleRoleAssignment)
        # or -Scope (Remove-OERActiveRoleAssignment/Remove-OEREligibleRoleAssignment) from a piped
        # object's property NAME. If this shape ever carried either of those property names, piping a
        # directory role assignment into one of those ARM cmdlets would silently mis-bind.
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id               = 'aaaaaaaa-0000-0000-0000-00000000000f'
                principalId      = 'aaaaaaaa-0000-0000-0000-000000000010'
                roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                directoryScopeId = '/'
                memberType       = 'Direct'
                status           = 'Provisioned'
                createdDateTime  = '2026-08-01T00:00:00Z'
                scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                roleDefinition   = @{ displayName = 'Reports Reader' }
            }
            $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible
            $Out.ScheduleId | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000f'
            $Out.DirectoryScopeId | Should -Be '/'
            $Out.PSObject.Properties.Name -contains 'RoleEligibilityScheduleId' | Should -BeFalse
            $Out.PSObject.Properties.Name -contains 'Scope' | Should -BeFalse
        }
    }

    Context 'principal type mapping' {
        It 'maps a group principal to Group' {
            InModuleScope Omnicit.EntraRBAC {
                $Raw = @{
                    id               = 'aaaaaaaa-0000-0000-0000-000000000009'
                    principalId      = 'aaaaaaaa-0000-0000-0000-00000000000a'
                    roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                    directoryScopeId = '/'
                    memberType       = 'Direct'
                    status           = 'Provisioned'
                    createdDateTime  = '2026-08-01T00:00:00Z'
                    scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                    principal        = @{ '@odata.type' = '#microsoft.graph.group'; displayName = 'OER Test Group' }
                    roleDefinition   = @{ displayName = 'Reports Reader' }
                }
                (ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible).PrincipalType | Should -Be 'Group'
            }
        }

        It 'maps a service principal to ServicePrincipal' {
            InModuleScope Omnicit.EntraRBAC {
                $Raw = @{
                    id               = 'aaaaaaaa-0000-0000-0000-00000000000b'
                    principalId      = 'aaaaaaaa-0000-0000-0000-00000000000c'
                    roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                    directoryScopeId = '/'
                    memberType       = 'Direct'
                    status           = 'Provisioned'
                    createdDateTime  = '2026-08-01T00:00:00Z'
                    scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                    principal        = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; displayName = 'OER Test App' }
                    roleDefinition   = @{ displayName = 'Reports Reader' }
                }
                (ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible).PrincipalType | Should -Be 'ServicePrincipal'
            }
        }

        It 'returns a null PrincipalType and an empty PrincipalDisplayName when principal is absent' {
            InModuleScope Omnicit.EntraRBAC {
                $Raw = @{
                    id               = 'aaaaaaaa-0000-0000-0000-00000000000d'
                    principalId      = 'aaaaaaaa-0000-0000-0000-00000000000e'
                    roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                    directoryScopeId = '/'
                    memberType       = 'Direct'
                    status           = 'Provisioned'
                    createdDateTime  = '2026-08-01T00:00:00Z'
                    scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                    roleDefinition   = @{ displayName = 'Reports Reader' }
                }
                $Out = ConvertTo-OERDirectoryRoleAssignment -InputObject $Raw -Kind Eligible
                $Out.PrincipalType | Should -BeNullOrEmpty
                $Out.PrincipalDisplayName | Should -Be ''
            }
        }
    }
}
