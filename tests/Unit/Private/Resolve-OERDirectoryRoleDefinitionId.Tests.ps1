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

    It 'returns a GUID Role as the id without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role '11111111-1111-1111-1111-111111111111' |
                Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns an upper-case GUID Role lower-cased, without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            # -BeExactly: -Be compares strings without regard to letter case.
            Resolve-OERDirectoryRoleDefinitionId -Role 'AAAAAAAA-0000-0000-0000-00000000000A' |
                Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
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

    It 'matches a name typed in another letter case through the full list when the exact filter finds nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -like '*$filter=*') { return @{ value = @() } }
            @{ value = @(
                    @{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader' },
                    @{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Message Center Reader' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'reports reader' |
                Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -like "v1.0/roleManagement/directory/roleDefinitions?*displayName eq 'reports%20reader'*"
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -eq 'v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName' -and $All
        }
    }

    It 'throws AmbiguousName with every candidate id when two definitions differ only in letter case' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -like '*$filter=*') { return @{ value = @() } }
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Reports Reader' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'REPORTS READER' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERDirectoryRoleDefinitionId -Role 'reports reader' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
    }

    It 'returns an exact-case match without listing every role definition' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader' | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $All }
    }

    It 'returns $null after both requests when no definition matches in any letter case' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -like '*$filter=*') { return @{ value = @() } }
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Message Center Reader' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERDirectoryRoleDefinitionId -Role 'No Such Role' | Should -Be $null
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 2
    }

    It 'propagates a failure of the full list instead of reporting no match' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -like '*$filter=*') { return @{ value = @() } }
            throw 'Forbidden: insufficient privileges'
        }
        InModuleScope $script:moduleName {
            { Resolve-OERDirectoryRoleDefinitionId -Role 'reports reader' } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }
}
