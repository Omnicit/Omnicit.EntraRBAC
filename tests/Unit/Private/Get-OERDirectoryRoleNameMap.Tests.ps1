BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERDirectoryRoleNameMap' {
    It 'maps both the role id and the role template id to the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'role-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            $Map = Get-OERDirectoryRoleNameMap
            $Map['role-1'] | Should -Be 'User Administrator'
            $Map['tmpl-1'] | Should -Be 'User Administrator'
        }
    }

    It 'returns an empty map when the Graph call fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down' }
        InModuleScope $script:moduleName {
            $Map = Get-OERDirectoryRoleNameMap
            $Map       | Should -BeOfType [hashtable]
            $Map.Count | Should -Be 0
        }
    }

    It 'passes -All to the directoryRoles read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'role-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            $null = Get-OERDirectoryRoleNameMap
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles' -and $All
        }
    }
}
