BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERActiveDirectoryRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { '11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'aaaaaaaa-0000-0000-0000-000000000001'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        id               = 'aaaaaaaa-0000-0000-0000-000000000002'
                        principalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
                        roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                        directoryScopeId = '/'
                        memberType       = 'Direct'
                        status           = 'Provisioned'
                        assignmentType   = 'Activated'
                        createdDateTime  = '2026-08-01T00:00:00Z'
                        scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                        principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User' }
                        roleDefinition   = @{ displayName = 'Reports Reader' }
                    },
                    [PSCustomObject]@{
                        id               = 'aaaaaaaa-0000-0000-0000-000000000003'
                        principalId      = 'aaaaaaaa-0000-0000-0000-000000000004'
                        roleDefinitionId = '11111111-1111-1111-1111-111111111111'
                        directoryScopeId = '/'
                        memberType       = 'Direct'
                        status           = 'Provisioned'
                        assignmentType   = 'Assigned'
                        createdDateTime  = '2026-08-01T00:00:00Z'
                        scheduleInfo     = @{ startDateTime = '2026-09-01T00:00:00Z'; expiration = @{ type = 'noExpiration' } }
                        principal        = @{ '@odata.type' = '#microsoft.graph.user'; displayName = 'OER Test User Two' }
                        roleDefinition   = @{ displayName = 'Reports Reader' }
                    }
                )
            }
        }
    }

    It 'GETs roleAssignmentSchedules at tenant scope with -All and no other filter by default' {
        Get-OERActiveDirectoryRoleAssignment | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "v1.0/roleManagement/directory/roleAssignmentSchedules?`$filter=directoryScopeId eq '/'&`$expand=principal,roleDefinition" -and $All
        }
    }

    It 'returns each value item tagged as Omnicit.EntraRBAC.ActiveDirectoryRoleAssignment' {
        $Out = @(Get-OERActiveDirectoryRoleAssignment)
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ActiveDirectoryRoleAssignment'
    }

    It 'returns both an Activated row and an Assigned row, with AssignmentType projected' {
        $Out = @(Get-OERActiveDirectoryRoleAssignment)
        $Out.Count | Should -Be 2
        @($Out.AssignmentType | Sort-Object) | Should -Be @('Activated', 'Assigned')
    }

    It 'gains a roleDefinitionId filter clause for -Role' {
        Get-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like "*directoryScopeId eq '/' and roleDefinitionId eq '11111111-1111-1111-1111-111111111111'*"
        }
    }

    It 'gains a principalId filter clause for -User' {
        Get-OERActiveDirectoryRoleAssignment -User 'person1@example.com' | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like "*directoryScopeId eq '/' and principalId eq 'aaaaaaaa-0000-0000-0000-000000000001'*"
        }
    }

    It 'lower-cases an upper-case -PrincipalId in the principalId filter clause, like the role id' {
        Get-OERActiveDirectoryRoleAssignment -PrincipalId 'AAAAAAAA-0000-0000-0000-00000000000B' | Out-Null
        # -clike, not -like: the point is the letter case of the id in the request.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -clike "*directoryScopeId eq '/' and principalId eq 'aaaaaaaa-0000-0000-0000-00000000000b'&*"
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 0
    }

    It 'reports RoleDefinitionNotFound and issues no schedule GET when -Role does not resolve' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        $Err = $null
        Get-OERActiveDirectoryRoleAssignment -Role 'Ghost Role' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERActiveDirectoryRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -like '*roleAssignmentSchedules*'
        }
    }

    It 'reports a non-terminating error and returns nothing when the schedule read fails' {
        # Called directly (not inside a { } | Should -Not -Throw scriptblock, which runs in a child
        # scope and would let $Out silently stay unset in THIS scope even if the assignment worked) so
        # -ErrorVariable is observable and the WriteError call itself is proven, not merely assumed.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Out = Get-OERActiveDirectoryRoleAssignment -ErrorAction SilentlyContinue -ErrorVariable Err
        $Out | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERActiveDirectoryRoleAssignment' }).Count | Should -Be 1
    }

    It 'calls Initialize-OERAuth without -IncludeARM' {
        Get-OERActiveDirectoryRoleAssignment | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Exactly 1 -ParameterFilter { -not $IncludeARM }
    }
}
