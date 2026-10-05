BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSubscription' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'lists all subscriptions with paging' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000'; subscriptionId = 'aaaa1111-0000-0000-0000-000000000000'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
            ) }
        }
        $Result = Get-OERSubscription
        $Result.SubscriptionId | Should -Be 'aaaa1111-0000-0000-0000-000000000000'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Subscription'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions?api-version=2022-12-01' -and $All
        }
    }

    It 'gets a single subscription directly when -Name is a GUID' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000'; subscriptionId = 'aaaa1111-0000-0000-0000-000000000000'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
        }
        $Result = Get-OERSubscription -Name 'aaaa1111-0000-0000-0000-000000000000'
        $Result.DisplayName | Should -Be 'Prod'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000000?api-version=2022-12-01'
        }
    }

    It 'filters by display name client-side and errors when nothing matches' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/a'; subscriptionId = 'a'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
                [PSCustomObject]@{ id = '/subscriptions/b'; subscriptionId = 'b'; displayName = 'Dev'; state = 'Enabled'; tenantId = 't' }
            ) }
        }
        (Get-OERSubscription -Name 'prod').SubscriptionId | Should -Be 'a'
        { Get-OERSubscription -Name 'Ghost' -ErrorAction Stop } |
            Should -Throw -ErrorId 'SubscriptionNotFound,Get-OERSubscription'
    }

    It 'lists subscriptions under a management group by intersecting the descendant tree' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/a'; subscriptionId = 'a'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
                [PSCustomObject]@{ id = '/subscriptions/b'; subscriptionId = 'b'; displayName = 'Dev'; state = 'Enabled'; tenantId = 't' }
            ) }
        } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1' }
        } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg1'
                name       = 'mg1'
                properties = [PSCustomObject]@{
                    children = @(
                        [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/child'; type = 'Microsoft.Management/managementGroups'; name = 'child'; children = @(
                            [PSCustomObject]@{ id = '/subscriptions/a'; type = '/subscriptions'; name = 'a'; displayName = 'Prod' }
                        ) }
                    )
                }
            }
        } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&*recurse*' }
        $Result = @(Get-OERSubscription -ManagementGroup 'mg1')
        $Result.Count | Should -Be 1
        $Result[0].SubscriptionId | Should -Be 'a'
    }

    It 'binds -ManagementGroup from a piped management group object without hijacking -Name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/cccc2222-0000-0000-0000-000000000000'; subscriptionId = 'cccc2222-0000-0000-0000-000000000000'; displayName = 'Workload'; state = 'Enabled'; tenantId = 't' }
            ) }
        } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg9' }
        } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/mg9?api-version=2020-05-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg9'
                name       = 'mg9'
                properties = [PSCustomObject]@{
                    children = @(
                        [PSCustomObject]@{ id = '/subscriptions/cccc2222-0000-0000-0000-000000000000'; type = '/subscriptions'; name = 'cccc2222-0000-0000-0000-000000000000'; displayName = 'Workload' }
                    )
                }
            }
        } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/mg9?api-version=2020-05-01&*recurse*' }
        $Mg = [PSCustomObject]@{ ManagementGroupName = 'mg9'; Name = 'mg9'; DisplayName = 'Nine' }
        $Result = @($Mg | Get-OERSubscription)
        $Result.Count | Should -Be 1
        $Result[0].SubscriptionId | Should -Be 'cccc2222-0000-0000-0000-000000000000'
    }

    Context 'scope-target naming (audit PR6)' {
        It 'accepts -Subscription as an alias for -Name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/a'; subscriptionId = 'a'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
                ) }
            }
            Get-OERSubscription -Subscription 'Prod' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
            # A real invocation alone would still pass via PowerShell's unambiguous prefix-name
            # matching against the pre-existing SubscriptionId alias, even without a dedicated
            # -Subscription alias. Assert the alias is actually declared so this stays locked in
            # even if a future parameter (e.g. -SubscriptionType) makes the prefix match ambiguous.
            (Get-Command Get-OERSubscription).Parameters['Name'].Aliases | Should -Contain 'Subscription'
        }

        It 'keeps -Name out of the pipeline so a piped management group name is not read as a subscription' {
            (Get-Command Get-OERSubscription).Parameters['Name'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ValueFromPipelineByPropertyName -or $_.ValueFromPipeline } |
                Should -Not -Contain $true
        }

        It 'emits ResourceId and no bare Id, so an ARM path cannot mis-bind downstream id parameters' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/a'; subscriptionId = 'a'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
                ) }
            }
            $Sub = Get-OERSubscription -Subscription 'Prod'
            $Sub.PSObject.Properties.Name | Should -Contain 'ResourceId'
            $Sub.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the subscriptions LIST catch -- no -Name and no -ManagementGroup.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERSubscription -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}

Describe 'Get-OERSubscription with an ambiguous management group display name' {
    # Resolve-OERScope runs for REAL here: only the ARM transport is mocked, and the management group
    # list answers with two management groups that share the display name 'Platform'. Management group
    # display names are not unique, so the name is refused and the candidates reach the operator in the
    # ManagementGroupNotFound record this cmdlet maps a resolver failure to (the id is unchanged).
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod'; state = 'Enabled'; tenantId = 't' }
            ) }
        } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
        $NotFoundErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 404; Content = '' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -MockWith ({ throw $NotFoundErr }.GetNewClosure()) `
            -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/Platform?*' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform-a'; name = 'mg-platform-a'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform-b'; name = 'mg-platform-b'; properties = [PSCustomObject]@{ displayName = 'Platform' } }
            ) }
        } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw "unexpected ARM call: $Path" }
    }

    It 'reports ManagementGroupNotFound carrying both candidate names, and reads no management group tree' {
        $Err = $null
        $Out = @(Get-OERSubscription -ManagementGroup 'Platform' -ErrorAction SilentlyContinue -ErrorVariable Err)

        # Positive proof first: the management group list WAS read, so the refusal is the ambiguity.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*expand=children*' }
        $Out.Count | Should -Be 0

        $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ManagementGroupNotFound,Get-OERSubscription' })
        $Mine.Count | Should -Be 1
        $Mine[0].Exception.Message | Should -BeExactly (
            "Management group display name 'Platform' matches 2 management groups (mg-platform-a, mg-platform-b). " +
            'Management group display names are not unique, so this name cannot identify a single management group. ' +
            'Re-run with the management group name (its id).')
    }
}
