BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERDirectoryRoleId' {
    It 'returns the RoleId verbatim without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleId 'role-guid' | Should -Be 'role-guid'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns the id of an already-activated role matched by display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'active-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleName 'User Administrator' | Should -Be 'active-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'activates the role from its template when not yet activated' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'tmpl-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoleTemplates' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'activated-1'; displayName = 'User Administrator' }
        } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleName 'User Administrator' | Should -Be 'activated-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryRoles' -and $Body.roleTemplateId -eq 'tmpl-1'
        }
    }

    It 'returns $null when the role name matches no template (genuine no-match, not a failure)' {
        # Mirrors Resolve-OERAdministrativeUnitId's null-on-no-match contract: a role name that
        # matches neither an activated role nor a template is a normal outcome, not an exception.
        # Callers (Add-/Remove-OERAdministrativeUnitScopedRole) rely on this to report RoleNotFound
        # instead of misclassifying an ordinary "bad role name" as a lookup failure.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleName 'No Such Role' | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'throws when the role-activation POST itself fails (a real failure still surfaces, is not swallowed)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'tmpl-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoleTemplates' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw 'Forbidden: insufficient privileges'
        } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            { Resolve-OERDirectoryRoleId -RoleName 'User Administrator' } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }

    It 'throws when neither -RoleId nor -RoleName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERDirectoryRoleId } | Should -Throw -ExpectedMessage '*-RoleId or -RoleName*'
        }
    }

    It 'matches an already-activated role that only exists on the second page of directoryRoles' {
        # The un-paged mock returns only page 1 (a decoy role), so today (without -All) a role
        # that only exists on page 2 is never seen and the function falls through to the template
        # lookup (or a no-match) instead of returning the already-activated id.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles' -and $All
        } -MockWith {
            @{ value = @(
                @{ id = 'decoy-1'; displayName = 'Decoy Role' },
                @{ id = 'active-2'; displayName = 'User Administrator' }) }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles' -and -not $All
        } -MockWith { @{ value = @(@{ id = 'decoy-1'; displayName = 'Decoy Role' }) } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleName 'User Administrator' | Should -Be 'active-2'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'matches a directoryRoleTemplate that only exists on the second page before activating it' {
        # No activated role matches (empty directoryRoles). The template's own list is un-paged
        # today, so a template that only exists on page 2 is never seen and the function returns
        # $null instead of activating it.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' } -MockWith {
            @{ value = @() }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoleTemplates' -and $All
        } -MockWith {
            @{ value = @(
                @{ id = 'decoy-tmpl'; displayName = 'Decoy Role' },
                @{ id = 'tmpl-2'; displayName = 'User Administrator' }) }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoleTemplates' -and -not $All
        } -MockWith { @{ value = @(@{ id = 'decoy-tmpl'; displayName = 'Decoy Role' }) } }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryRoles'
        } -MockWith { @{ id = 'activated-2'; displayName = 'User Administrator' } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleId -RoleName 'User Administrator' | Should -Be 'activated-2'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryRoles' -and $Body.roleTemplateId -eq 'tmpl-2'
        }
    }
}
