BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERDirectoryRoleInput' {
    It 'returns the resolved id with no ErrorId when Resolve-OERDirectoryRoleDefinitionId finds a match' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { '11111111-1111-1111-1111-111111111111' }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERDirectoryRoleInput -Role 'Reports Reader'
            $Result.RoleDefinitionId | Should -Be '11111111-1111-1111-1111-111111111111'
            $Result.ErrorId | Should -BeNullOrEmpty
        }
    }

    It 'returns RoleDefinitionNotFound with the exact message when no role definition matches' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERDirectoryRoleInput -Role 'Ghost Role'
            $Result.ErrorId | Should -Be 'RoleDefinitionNotFound'
            $Result.Category | Should -Be 'ObjectNotFound'
            $Result.Message | Should -Be (
                "No Microsoft Entra directory role definition named 'Ghost Role' was found. Use Tab " +
                'completion on -Role, or pass the role definition id directly.')
            $Result.RoleDefinitionId | Should -BeNullOrEmpty
        }
    }

    It 'returns AmbiguousRoleName with both candidate ids when the resolver throws an AmbiguousName error' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222). " +
                    'Re-run with the role definition id instead of the display name.'),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERDirectoryRoleInput -Role 'Dup'
            $Result.ErrorId | Should -Be 'AmbiguousRoleName'
            $Result.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $Result.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        }
    }

    It 'returns RoleDefinitionReadFailed with a leading explanatory message when the lookup fails for any other reason' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { throw 'Forbidden' }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERDirectoryRoleInput -Role 'Reports Reader'
            $Result.ErrorId | Should -Be 'RoleDefinitionReadFailed'
            $Result.Category | Should -Be 'ReadError'
            $Result.Message | Should -BeLike (
                "Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: *")
        }
    }

    It 'never throws for a match, a miss, an ambiguity or a read failure' {
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERDirectoryRoleInput -Role 'Reports Reader' } | Should -Not -Throw
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERDirectoryRoleInput -Role 'Ghost Role' } | Should -Not -Throw
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Dup matches 2.'), 'AmbiguousName',
                [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERDirectoryRoleInput -Role 'Dup' } | Should -Not -Throw
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { throw 'Forbidden' }
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERDirectoryRoleInput -Role 'Reports Reader' } | Should -Not -Throw
        }
    }

    It 'scrubs the bearer-hygiene record when the underlying lookup throws' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERDirectoryRoleInput -Role 'Reports Reader'
            $Result.ErrorId | Should -Be 'RoleDefinitionReadFailed'
        }
        Should -Invoke Remove-OERErrorRecord -ModuleName Omnicit.EntraRBAC -Times 1 -Exactly
    }
}
