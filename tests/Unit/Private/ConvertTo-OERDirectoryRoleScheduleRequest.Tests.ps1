BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERDirectoryRoleScheduleRequest' {
    It 'tags an Eligible response as Omnicit.EntraRBAC.DirectoryRoleScheduleRequest and flattens the fields' {
        InModuleScope $script:moduleName {
            $Response = [PSCustomObject]@{
                id                = 'req1'
                action            = 'adminAssign'
                status            = 'Provisioned'
                roleDefinitionId  = 'aaaaaaaa-0000-0000-0000-000000000001'
                principalId       = 'bbbbbbbb-0000-0000-0000-000000000002'
                directoryScopeId  = '/'
                justification     = 'Test justification'
                createdDateTime   = '2026-09-01T00:00:00Z'
                scheduleInfo      = [PSCustomObject]@{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = [PSCustomObject]@{ type = 'afterDuration'; duration = 'P30D' }
                }
            }
            $Out = ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Eligible

            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.DirectoryRoleScheduleRequest'
            $Out.ScheduleRequestId | Should -Be 'req1'
            $Out.Kind | Should -Be 'Eligible'
            $Out.Action | Should -Be 'adminAssign'
            $Out.Status | Should -Be 'Provisioned'
            $Out.RoleDefinitionId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            $Out.PrincipalId | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
            $Out.DirectoryScopeId | Should -Be '/'
            $Out.Justification | Should -Be 'Test justification'
            $Out.ExpirationType | Should -Be 'afterDuration'
            $Out.Duration | Should -Be 'P30D'
            $Out.StartDateTime | Should -Be '2026-09-01T00:00:00Z'
            $Out.CreatedDateTime | Should -Be '2026-09-01T00:00:00Z'
        }
    }

    It 'tags an Active response as Omnicit.EntraRBAC.DirectoryRoleScheduleRequest' {
        InModuleScope $script:moduleName {
            $Response = [PSCustomObject]@{
                id               = 'req2'
                action           = 'adminRemove'
                status           = 'Provisioned'
                roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                principalId      = 'bbbbbbbb-0000-0000-0000-000000000002'
                directoryScopeId = '/'
                scheduleInfo     = [PSCustomObject]@{ startDateTime = '2026-09-01T00:00:00Z'; expiration = $null }
            }
            $Out = ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Active
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.DirectoryRoleScheduleRequest'
            $Out.Kind | Should -Be 'Active'
            $Out.Action | Should -Be 'adminRemove'
            $Out.Justification | Should -BeNullOrEmpty
            $Out.Duration | Should -BeNullOrEmpty
        }
    }

    It 'flattens an afterDateTime expiration into ExpirationType and EndDateTime' {
        InModuleScope $script:moduleName {
            $Response = [PSCustomObject]@{
                id               = 'req3'
                action           = 'adminAssign'
                roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                principalId      = 'bbbbbbbb-0000-0000-0000-000000000002'
                directoryScopeId = '/'
                scheduleInfo     = [PSCustomObject]@{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = [PSCustomObject]@{ type = 'afterDateTime'; endDateTime = '2026-10-01T00:00:00Z' }
                }
            }
            $Out = ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Eligible
            $Out.ExpirationType | Should -Be 'afterDateTime'
            $Out.EndDateTime | Should -Be '2026-10-01T00:00:00Z'
            $Out.Duration | Should -BeNullOrEmpty
        }
    }
}
