BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERGroupId' {
    It 'returns the Id verbatim when -Id is supplied without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -Id '11111111-1111-1111-1111-111111111111' |
                Should -Be '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'resolves a DisplayName to an id via a filtered groups query' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'gid-1'; displayName = 'role_sec_identity_administrator' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName 'role_sec_identity_administrator' | Should -Be 'gid-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -match "displayName eq 'role_sec_identity_administrator'"
        }
    }

    It 'returns $null when no group matches the DisplayName' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName 'does-not-exist' | Should -Be $null
        }
    }

    It 'throws when neither -Id nor -DisplayName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERGroupId } | Should -Throw -ExpectedMessage '*-Id or -DisplayName*'
        }
    }

    It 'escapes single quotes in the DisplayName filter' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName { Resolve-OERGroupId -DisplayName "o'brien" | Out-Null }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            $Uri -match "o%27%27brien"
        }
    }

    It 'returns a GUID DisplayName verbatim without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName '33333333-3333-3333-3333-333333333333' |
                Should -Be '33333333-3333-3333-3333-333333333333'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'throws AmbiguousName listing the candidates when two groups share the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup-Name' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup-Name' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERGroupId -DisplayName 'Dup-Name' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
    }

    It 'still returns the single match unchanged when exactly one group has the name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Solo-Name' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName 'Solo-Name' | Should -Be '33333333-3333-3333-3333-333333333333'
        }
    }

    It 'still returns $null on a genuine no-match with an empty value collection' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }

    It 'still returns $null when the response carries no value collection at all' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ } }
        InModuleScope $script:moduleName {
            Resolve-OERGroupId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }
}
