BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

Describe 'Resolve-OERScope with an ambiguous display name' {
    # Subscription display names are not unique, and neither are management group display names.
    # Taking the first match turned a name into an arbitrary subscription or management group, and
    # every write cmdlet that resolves a friendly scope (and the apply engine, which writes through
    # them) then acted on it. An ambiguous name is refused instead, in the shape Resolve-OERCatalogId
    # uses: an ErrorRecord with ErrorId AmbiguousName that names every candidate. No id below is
    # version-4 shaped.

    It 'refuses two subscriptions with the same display name, names both ids, and makes no further ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Dup Sub' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Dup Sub' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; displayName = 'Other Sub' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
            Mock Invoke-OERArmRequest { throw "unexpected ARM call: $Path" }

            # -ResourceGroup and -ResourceName would trigger a resource listing once a subscription id
            # is chosen, so the exact call count below proves the refusal comes before that.
            $Err = try { Resolve-OERScope -Subscription 'Dup Sub' -ResourceGroup 'rg1' -ResourceName 'stg1' } catch { $PSItem }

            # Positive proof first: the subscription list WAS read, once, and nothing else was.
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            $Err | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Err.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName'
            $Err.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Err.TargetObject | Should -BeExactly 'Dup Sub'
            $Err.Exception.Message | Should -BeExactly (
                "Subscription display name 'Dup Sub' matches 2 subscriptions " +
                '(aaaa1111-0000-0000-0000-000000000001, aaaa1111-0000-0000-0000-000000000002). ' +
                'Subscription display names are not unique, so this name cannot identify a single subscription. ' +
                'Re-run with the subscription id.')
        }
    }

    It 'counts every match: three subscriptions are named in list order, and a name differing only in case still counts' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Prod' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; displayName = 'prod' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000004'; displayName = 'Production' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }

            $Err = try { Resolve-OERScope -Subscription 'Prod' } catch { $PSItem }

            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            $Err.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName'
            $Err.Exception.Message | Should -BeLike "Subscription display name 'Prod' matches 3 subscriptions (aaaa1111-0000-0000-0000-000000000001, aaaa1111-0000-0000-0000-000000000002, aaaa1111-0000-0000-0000-000000000003). *"
            $Err.Exception.Message | Should -Not -Match 'aaaa1111-0000-0000-0000-000000000004'
        }
    }

    It 'still resolves a subscription display name that exactly one subscription carries' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod EU' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Prod' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; displayName = 'Production' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }

            Resolve-OERScope -Subscription 'Prod' | Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000002'
            Resolve-OERScope -Subscription 'Prod' -ResourceGroup 'rg1' |
                Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000002/resourceGroups/rg1'
            Should -Invoke Invoke-OERArmRequest -Times 2 -Exactly
        }
    }

    It 'keeps the plain not-found error for a subscription name nobody carries' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Other Sub' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }

            $Err = try { Resolve-OERScope -Subscription 'Ghost' } catch { $PSItem }

            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            $Err.FullyQualifiedErrorId | Should -Not -BeExactly 'AmbiguousName'
            $Err.Exception.Message | Should -BeExactly "Subscription 'Ghost' was not found or you do not have access to it."
        }
    }

    It 'takes a subscription GUID as it is, without reading the listing' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'a GUID must not be looked up' }

            Resolve-OERScope -Subscription 'aaaa1111-0000-0000-0000-000000000009' |
                Should -Be '/subscriptions/aaaa1111-0000-0000-0000-000000000009'
            Should -Invoke Invoke-OERArmRequest -Times 0
        }
    }

    It 'refuses two management groups with the same display name (403 on the verbatim probe), names both ids, and makes no further ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"...or the scope is invalid."}}' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform-a'; name = 'mg-platform-a'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform-b'; name = 'mg-platform-b'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-other'; name = 'mg-other'; properties = [PSCustomObject]@{ displayName = 'Other' } }
                ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            Mock Invoke-OERArmRequest { throw "unexpected ARM call: $Path" }

            $Err = try { Resolve-OERScope -ManagementGroup 'Platform' } catch { $PSItem }

            # Positive proof first: the probe and the list were each read once, and nothing else was.
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            Should -Invoke Invoke-OERArmRequest -Times 2 -Exactly
            $Err | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Err.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName'
            $Err.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Err.TargetObject | Should -BeExactly 'Platform'
            $Err.Exception.Message | Should -BeExactly (
                "Management group display name 'Platform' matches 2 management groups (mg-platform-a, mg-platform-b). " +
                'Management group display names are not unique, so this name cannot identify a single management group. ' +
                'Re-run with the management group name (its id).')
        }
    }

    It 'counts every management group match when the verbatim probe is a 404: three are named in list order' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 404; Content = '' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-one'; name = 'mg-one'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-two'; name = 'mg-two'; properties = [PSCustomObject]@{ displayName = 'platform' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-three'; name = 'mg-three'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-four'; name = 'mg-four'; properties = [PSCustomObject]@{ displayName = 'Platform Team' } }
                ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }

            $Err = try { Resolve-OERScope -ManagementGroup 'Platform' } catch { $PSItem }

            Should -Invoke Invoke-OERArmRequest -Times 2 -Exactly
            $Err.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName'
            $Err.Exception.Message | Should -BeLike "Management group display name 'Platform' matches 3 management groups (mg-one, mg-two, mg-three). *"
            $Err.Exception.Message | Should -Not -Match 'mg-four'
        }
    }

    It 'still resolves a management group display name that exactly one management group carries' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw (Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 404; Content = '' }))
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-team'; name = 'mg-team'; properties = [PSCustomObject]@{ displayName = 'Platform Team' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform'; name = 'mg-platform'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }

            Resolve-OERScope -ManagementGroup 'Platform' |
                Should -Be '/providers/Microsoft.Management/managementGroups/mg-platform'
        }
    }

    It 'keeps the verbatim probe path: a management group name that exists wins and the list is never read' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/Platform' }
            } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
            Mock Invoke-OERArmRequest { throw 'the list must not be read when the verbatim probe succeeds' } `
                -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' }

            Resolve-OERScope -ManagementGroup 'Platform' |
                Should -Be '/providers/Microsoft.Management/managementGroups/Platform'
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
        }
    }
}
