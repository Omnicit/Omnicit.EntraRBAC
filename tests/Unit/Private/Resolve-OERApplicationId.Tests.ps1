BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERApplicationId' {
    It 'returns the Id verbatim without a Graph call when -Id is given' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {}
            Resolve-OERApplicationId -Id 'sp-123' | Should -Be 'sp-123'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'resolves a display name to a service principal id via a filtered query' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-9'; displayName = 'Contoso Expense Portal' }) } }
            Resolve-OERApplicationId -DisplayName 'Contoso Expense Portal' | Should -Be 'sp-9'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                # Spaces are percent-encoded (%20) so the value survives transport.
                $Uri -like "*servicePrincipals?*displayName eq 'Contoso%20Expense%20Portal'*"
            }
        }
    }

    It 'returns $null when no service principal matches' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERApplicationId -DisplayName 'nope' | Should -BeNullOrEmpty
        }
    }

    It 'throws when neither -Id nor -DisplayName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERApplicationId } | Should -Throw
        }
    }

    It 'escapes single quotes in the display name' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERApplicationId -DisplayName "O'Brien App" | Out-Null
            # Doubled quote first (''), then percent-encoded ('' -> %27%27, space -> %20).
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like "*O%27%27Brien%20App*" }
        }
    }

    It 'throws AmbiguousName listing both candidate ids when two service principals share the display name' {
        # Entra does not enforce unique service principal display names. Returning the first row
        # would silently act on an arbitrary one, so the helper refuses the name instead.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup App' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup App' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { $null = Resolve-OERApplicationId -DisplayName 'Dup App' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty -Because 'two matches must never resolve to one of them'
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -Be 'Dup App'
        $Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        $Caught.Exception.Message | Should -Match "Service principal display name 'Dup App' matches 2 service principals"
        $IsAmbiguous = InModuleScope $script:moduleName -Parameters @{ Record = $Caught } {
            param($Record)
            Test-OERAmbiguousNameError -Record $Record
        }
        $IsAmbiguous | Should -BeTrue -Because 'the callers route the refusal through Test-OERAmbiguousNameError'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'returns the single match when exactly one service principal has the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Solo App' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERApplicationId -DisplayName 'Solo App' | Should -BeExactly '33333333-3333-3333-3333-333333333333'
        }
    }

    It 'ignores null entries in the response: one real match beside a null returns that match without throwing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @($null, @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'Solo App' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERApplicationId -DisplayName 'Solo App' | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        }
    }

    It 'returns $null when the response carries only null entries, or no value collection at all' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @($null) } }
        InModuleScope $script:moduleName {
            Resolve-OERApplicationId -DisplayName 'Nobody App' | Should -BeNullOrEmpty
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ } }
        InModuleScope $script:moduleName {
            Resolve-OERApplicationId -DisplayName 'Nobody App' | Should -BeNullOrEmpty
        }
    }

    It 'still queries a GUID given as -DisplayName (no GUID short-circuit on that parameter)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERApplicationId -DisplayName '55555555-5555-5555-5555-555555555555' | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like "*servicePrincipals?*displayName eq '55555555-5555-5555-5555-555555555555'*"
        }
    }
}
