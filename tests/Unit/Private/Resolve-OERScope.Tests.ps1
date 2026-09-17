BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERScope' {
    It 'passes a raw ARM scope through and rejects one without a leading slash' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OERScope -Scope '/subscriptions/abc/resourceGroups/rg1' |
                Should -Be '/subscriptions/abc/resourceGroups/rg1'
            { Resolve-OERScope -Scope 'subscriptions/abc' } | Should -Throw '*must start with*'
        }
    }

    It 'builds subscription and resource group scopes from a GUID without any ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            Resolve-OERScope -Subscription '00000000-0000-0000-0000-000000000060' |
                Should -Be '/subscriptions/00000000-0000-0000-0000-000000000060'
            Resolve-OERScope -Subscription '00000000-0000-0000-0000-000000000060' -ResourceGroup 'rg1' |
                Should -Be '/subscriptions/00000000-0000-0000-0000-000000000060/resourceGroups/rg1'
            Should -Invoke Invoke-OERArmRequest -Times 0 -Exactly
        }
    }

    It 'resolves a subscription display name via the list endpoint' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000000'; displayName = 'Prod' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
            Resolve-OERScope -Subscription 'Prod' | Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000000'
            { Resolve-OERScope -Subscription 'DoesNotExist' } | Should -Throw "*'DoesNotExist'*"
        }
    }

    It 'uses the management group name verbatim when the direct GET succeeds' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform' }
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/mg-platform?api-version=2020-05-01*' }
            Resolve-OERScope -ManagementGroup 'mg-platform' |
                Should -Be '/providers/Microsoft.Management/managementGroups/mg-platform'
        }
    }

    It 'falls back to displayName matching when the direct GET fails' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 404; Content = '' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{
                        id         = '/providers/Microsoft.Management/managementGroups/mg-platform'
                        name       = 'mg-platform'
                        properties = [PSCustomObject]@{ displayName = 'Platform' }
                    }
                ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            Resolve-OERScope -ManagementGroup 'Platform' |
                Should -Be '/providers/Microsoft.Management/managementGroups/mg-platform'
        }
    }

    It 'validates the parameter combinations' {
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERScope } | Should -Throw '*scope is required*'
            { Resolve-OERScope -Scope '/x' -Subscription 'y' } | Should -Throw '*only one of*'
            { Resolve-OERScope -ResourceGroup 'rg1' } | Should -Throw '*requires -Subscription*'
        }
    }

    It 'rethrows throttling/server errors from the management group verbatim GET instead of masking them' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests","message":"throttled"}}' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/mg-busy?*' }
            Mock Invoke-OERArmRequest { throw 'list should not be called' } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' }
            { Resolve-OERScope -ManagementGroup 'mg-busy' } | Should -Throw -ErrorId 'TooManyRequests'
        }
    }

    It 'falls back to displayName matching when the verbatim GET is AuthorizationFailed (403)' {
        InModuleScope Omnicit.EntraRBAC {
            # ARM returns 403 AuthorizationFailed (not 404) for an MG name that does not exist; a
            # display name supplied to -ManagementGroup must still resolve via the list fallback.
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"...or the scope is invalid."}}' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{
                        id         = '/providers/Microsoft.Management/managementGroups/mg-platform'
                        name       = 'mg-platform'
                        properties = [PSCustomObject]@{ displayName = 'Platform' }
                    }
                ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            Resolve-OERScope -ManagementGroup 'Platform' |
                Should -Be '/providers/Microsoft.Management/managementGroups/mg-platform'
        }
    }

    It 'throws a clean not-found error when neither the verbatim GET nor the displayName match resolves the management group' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"...or the scope is invalid."}}' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Nope?*' }
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            { Resolve-OERScope -ManagementGroup 'Nope' } | Should -Throw "*'Nope' was not found, or you do not have access to it*"
        }
    }

    It 'resolves a resource by name within a resource group' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1'; name = 'stg1'; type = 'Microsoft.Storage/storageAccounts' }
                ) }
            } -ParameterFilter { $Path -like '*/resourceGroups/rg1/resources?api-version=2025-04-01' -and $All }
            Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceGroup 'rg1' -ResourceName 'stg1' |
                Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1'
        }
    }

    It 'narrows to the matching type when -ResourceType is supplied' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/dup'; name = 'dup'; type = 'Microsoft.Storage/storageAccounts' }
                    [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Web/sites/dup'; name = 'dup'; type = 'Microsoft.Web/sites' }
                ) }
            } -ParameterFilter { $Path -like '*/resources?api-version=2025-04-01' -and $All }
            Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceGroup 'rg1' -ResourceName 'dup' -ResourceType 'Microsoft.Web/sites' |
                Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Web/sites/dup'
        }
    }

    It 'throws when a resource name is ambiguous and -ResourceType is not given' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/dup'; name = 'dup'; type = 'Microsoft.Storage/storageAccounts' }
                    [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/resourceGroups/rg1/providers/Microsoft.Web/sites/dup'; name = 'dup'; type = 'Microsoft.Web/sites' }
                ) }
            } -ParameterFilter { $Path -like '*/resources?api-version=2025-04-01' -and $All }
            { Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceGroup 'rg1' -ResourceName 'dup' } |
                Should -Throw '*ambiguous*'
        }
    }

    It 'throws a not-found error when no resource matches' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } } -ParameterFilter { $Path -like '*/resources?api-version=2025-04-01' -and $All }
            { Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceGroup 'rg1' -ResourceName 'ghost' } |
                Should -Throw "*'ghost'*was not found*"
        }
    }

    It 'validates the resource parameter combinations' {
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' } |
                Should -Throw '*-ResourceType requires -ResourceName*'
            { Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResourceName 'stg1' } |
                Should -Throw '*-ResourceName requires -Subscription and -ResourceGroup*'
        }
    }

    It 'scrubs the bearer-hygiene record when the verbatim management group probe fails' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'transport failure' }
            Mock Remove-OERErrorRecord { }
            { Resolve-OERScope -ManagementGroup 'mg-platform' } | Should -Throw '*transport failure*'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }
}
