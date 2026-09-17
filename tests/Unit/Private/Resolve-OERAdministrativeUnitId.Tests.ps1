BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERAdministrativeUnitId' {
    It 'returns the Id verbatim when -Id is supplied without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -Id '11111111-1111-1111-1111-111111111111' |
                Should -Be '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'resolves a DisplayName to an id via a filtered AU query' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-1'; displayName = 'au_hr' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'au_hr' | Should -Be 'au-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -match 'directory/administrativeUnits' -and $Uri -match "displayName eq 'au_hr'"
        }
    }

    It 'returns $null when no AU matches the DisplayName' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'nope' | Should -Be $null
        }
    }

    It 'throws when neither -Id nor -DisplayName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERAdministrativeUnitId } | Should -Throw -ExpectedMessage '*-Id or -DisplayName*'
        }
    }

    It 'escapes single quotes in the DisplayName filter' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName { Resolve-OERAdministrativeUnitId -DisplayName "o'brien" | Out-Null }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            $Uri -match "o%27%27brien"
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-9'; displayName = 'R&D + Core' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'R&D + Core' | Should -Be 'au-9'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'throws AmbiguousName listing the candidates when two administrative units share the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'a1a1a1a1-1111-1111-1111-111111111111'; displayName = 'Dup-Name' },
                    @{ id = 'b2b2b2b2-2222-2222-2222-222222222222'; displayName = 'Dup-Name' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERAdministrativeUnitId -DisplayName 'Dup-Name' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match 'a1a1a1a1-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match 'b2b2b2b2-2222-2222-2222-222222222222'
    }

    It 'still returns the single match unchanged when exactly one administrative unit has the name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'c3c3c3c3-3333-3333-3333-333333333333'; displayName = 'Solo-Name' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'Solo-Name' | Should -Be 'c3c3c3c3-3333-3333-3333-333333333333'
        }
    }

    It 'still returns $null on a genuine no-match with an empty value collection' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }

    It 'still returns $null when the response carries no value collection at all' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ } }
        InModuleScope $script:moduleName {
            Resolve-OERAdministrativeUnitId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }
}
