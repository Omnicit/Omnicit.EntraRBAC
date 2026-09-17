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
}
