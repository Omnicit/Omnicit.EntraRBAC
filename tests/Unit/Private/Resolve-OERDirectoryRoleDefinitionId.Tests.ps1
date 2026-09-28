BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERDirectoryRoleDefinitionId' {
    It 'resolves a built-in role by display name to its role definition id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader'; isBuiltIn = $true }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader' |
                Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -like "v1.0/roleManagement/directory/roleDefinitions?*displayName eq 'Reports%20Reader'*"
        }
    }

    It 'resolves a custom role (isBuiltIn = $false) by display name to its role definition id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Custom Reader'; isBuiltIn = $false }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'Custom Reader' |
                Should -Be 'aaaaaaaa-0000-0000-0000-000000000002'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -like "v1.0/roleManagement/directory/roleDefinitions?*displayName eq 'Custom%20Reader'*"
        }
    }

    It 'returns a GUID Role verbatim without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role '11111111-1111-1111-1111-111111111111' |
                Should -Be '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns $null when no role definition matches the name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'No Such Role' | Should -Be $null
        }
    }

    It 'throws AmbiguousName listing the candidates when two role definitions share the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup-Name' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup-Name' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERDirectoryRoleDefinitionId -Role 'Dup-Name' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        InModuleScope $script:moduleName -Parameters @{ Caught = $Caught } {
            param($Caught)
            Test-OERAmbiguousNameError -Record $Caught | Should -BeTrue
        }
    }

    It 'propagates a transport failure instead of swallowing it' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'Forbidden: insufficient privileges' }
        InModuleScope $script:moduleName {
            { Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader' } |
                Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }

    It 'never activates a role: no POST call, and no call ever targets v1.0/directoryRoles' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader'; isBuiltIn = $true }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader' | Out-Null
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Custom Reader'; isBuiltIn = $false }) } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'Custom Reader' | Out-Null
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'No Such Role' | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like 'v1.0/directoryRoles*' }
    }

    It 'escapes a single quote in the Role filter (O''Brien form after ConvertTo-OERODataFilterValue)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role "O'Brien" | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            $Uri -match "O%27%27Brien"
        }
    }

    It 'rejects an empty string for -Role at parameter binding' {
        InModuleScope $script:moduleName {
            { Resolve-OERDirectoryRoleDefinitionId -Role '' } | Should -Throw -ExpectedMessage '*empty string*'
        }
    }
}
