BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERScopedRoleMember' {
    It 'tags the output and maps the scoped role membership fields' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id = 'srm-1'; roleId = 'role-1'; administrativeUnitId = 'au-1'
                roleMemberInfo = @{ id = 'user-1'; displayName = 'Jane Doe' }
            }
            $Out = ConvertTo-OERScopedRoleMember -InputObject $Raw -RoleName 'User Administrator'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole'
            $Out.ScopedRoleMembershipId | Should -Be 'srm-1'
            $Out.RoleName | Should -Be 'User Administrator'
            $Out.RoleId | Should -Be 'role-1'
            $Out.AdministrativeUnitId | Should -Be 'au-1'
            $Out.PrincipalId | Should -Be 'user-1'
            $Out.PrincipalDisplayName | Should -Be 'Jane Doe'
        }
    }

    It 'leaves RoleName null when not supplied' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERScopedRoleMember -InputObject @{ id = 'srm-1'; roleId = 'role-1' }
            $Out.RoleName | Should -BeNullOrEmpty
            $Out.RoleId | Should -Be 'role-1'
        }
    }

    It 'processes multiple memberships from the pipeline' {
        InModuleScope $script:moduleName {
            $Raw = @(
                @{ id = 'srm-1'; roleId = 'role-1'; administrativeUnitId = 'au-1'; roleMemberInfo = @{ id = 'u-1'; displayName = 'Jane' } }
                @{ id = 'srm-2'; roleId = 'role-2'; administrativeUnitId = 'au-1'; roleMemberInfo = @{ id = 'u-2'; displayName = 'John' } }
            )
            $Out = @($Raw | ConvertTo-OERScopedRoleMember)
            $Out.Count | Should -Be 2
            $Out[0].ScopedRoleMembershipId | Should -Be 'srm-1'
            $Out[1].PrincipalId | Should -Be 'u-2'
        }
    }

    It 'yields null principal fields when roleMemberInfo is absent' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERScopedRoleMember -InputObject @{ id = 'srm-3'; roleId = 'role-3'; administrativeUnitId = 'au-1' }
            $Out.ScopedRoleMembershipId | Should -Be 'srm-3'
            $Out.PrincipalId | Should -BeNullOrEmpty
            $Out.PrincipalDisplayName | Should -BeNullOrEmpty
        }
    }
}
