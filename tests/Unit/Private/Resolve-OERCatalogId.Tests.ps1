BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERCatalogId' {
    It 'returns the Id verbatim without a Graph call when -Id is given' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {}
            Resolve-OERCatalogId -Id 'cat-123' | Should -Be 'cat-123'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'resolves a display name to an id via a filtered query' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'cat-9'; displayName = 'CAT-IT-Core' }) } }
            Resolve-OERCatalogId -DisplayName 'CAT-IT-Core' | Should -Be 'cat-9'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*entitlementManagement/catalogs?*displayName eq 'CAT-IT-Core'*"
            }
        }
    }

    It 'returns $null when no catalog matches' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERCatalogId -DisplayName 'nope' | Should -Be $null
        }
    }

    It 'throws when neither -Id nor -DisplayName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERCatalogId } | Should -Throw
        }
    }

    It 'escapes single quotes in the display name' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERCatalogId -DisplayName "O'Brien" | Out-Null
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like "*O%27%27Brien*" }
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cat-1'; displayName = 'R&D + Core' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERCatalogId -DisplayName 'R&D + Core' | Should -Be 'cat-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'returns a GUID display name verbatim without a Graph call' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {}
            Resolve-OERCatalogId -DisplayName '11111111-1111-1111-1111-111111111111' | Should -Be '11111111-1111-1111-1111-111111111111'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'throws AmbiguousName listing the candidates when two catalogs share the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'aaaaaaaa-1111-1111-1111-111111111111'; displayName = 'Dup-Name' },
                    @{ id = 'bbbbbbbb-2222-2222-2222-222222222222'; displayName = 'Dup-Name' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERCatalogId -DisplayName 'Dup-Name' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match 'aaaaaaaa-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match 'bbbbbbbb-2222-2222-2222-222222222222'
    }

    It 'still returns the single match unchanged when exactly one catalog has the name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cccccccc-3333-3333-3333-333333333333'; displayName = 'Solo-Name' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERCatalogId -DisplayName 'Solo-Name' | Should -Be 'cccccccc-3333-3333-3333-333333333333'
        }
    }

    It 'still returns $null on a genuine no-match with an empty value collection' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERCatalogId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }

    It 'still returns $null when the response carries no value collection at all' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ } }
        InModuleScope $script:moduleName {
            Resolve-OERCatalogId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }
}
