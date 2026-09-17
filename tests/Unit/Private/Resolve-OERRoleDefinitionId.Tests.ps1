BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERRoleDefinitionId' {
    It 'passes a full ARM role definition id through unchanged' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            $Full = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
            Resolve-OERRoleDefinitionId -Role $Full -Scope '/subscriptions/s1' | Should -Be $Full
            Should -Invoke Invoke-OERArmRequest -Times 0 -Exactly
        }
    }

    It 'expands a bare GUID to the full id at the target scope without any ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            Resolve-OERRoleDefinitionId -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
        }
    }

    It 'resolves a role display name via the roleName filter with URL encoding' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000056' }
                ) }
            }
            Resolve-OERRoleDefinitionId -Role 'User Access Administrator' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000056'
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq "/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20%27User%20Access%20Administrator%27"
            }
        }
    }

    It 'throws when no role matches the name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            { Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1' } |
                Should -Throw "*'No Such Role'*"
        }
    }

    It 'names Get-OERRoleDefinition in the not-found message' {
        # A bare "was not found" leaves the operator with no way to discover the right spelling, and
        # all ten -Role consumers pass this message through verbatim, so the hint belongs here.
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'Reeder' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -Match 'Get-OERRoleDefinition'
            $Caught.Exception.Message | Should -Match "-Scope '/subscriptions/s1'"
        }
    }

    It 'throws AmbiguousName when two role definitions share the name at the scope' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/r1' }
                        [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1/providers/Microsoft.Authorization/roleDefinitions/r2' }
                    ) }
            }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'Custom Operator' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
            $Caught.Exception.Message | Should -Match 'roleDefinitions/r1'
            $Caught.Exception.Message | Should -Match 'roleDefinitions/r2'
        }
    }

    It 'still reports not found when the value array holds only a null' {
        # @($null).Count is 1, so a naive @($Response.value)[0].id would return an empty string here
        # and every caller would then build a role assignment body with no roleDefinitionId.
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @($null) } }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -Match 'was not found at scope'
        }
    }

    It 'returns a single match unchanged and makes no ambiguity claim' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/only' }
                    ) }
            }
            Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/only'
        }
    }
}
