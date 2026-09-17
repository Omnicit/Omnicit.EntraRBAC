BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERResource' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid' }
    }

    It 'lists resources in a resource group' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stg1'; name = 'stg1'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope' }
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Web/sites/web1'; name = 'web1'; type = 'Microsoft.Web/sites'; location = 'westeurope' }
            ) }
        }
        $Result = Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app'
        $Result.Count | Should -Be 2
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Resource'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/sub-guid/resourceGroups/rg-app/resources?api-version=2025-04-01'
        }
    }

    It 'lists all resources in the subscription when no resource group is given' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERResource -Subscription 'Prod'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/sub-guid/resources?api-version=2025-04-01'
        }
    }

    It 'filters by -Name and -ResourceType client-side' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stg1'; name = 'stg1'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope' }
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Web/sites/web1'; name = 'web1'; type = 'Microsoft.Web/sites'; location = 'westeurope' }
            ) }
        }
        $Result = Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -Name 'web1' -ResourceType 'Microsoft.Web/sites'
        @($Result).Count | Should -Be 1
        $Result.Name | Should -Be 'web1'
    }

    It 'attaches RoleAssignments at the resource scope with -IncludeRoleAssignments' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stg1'; name = 'stg1'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope' }
            ) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment { [PSCustomObject]@{ PrincipalId = 'p1' } }
        $Result = Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments
        @($Result.RoleAssignments).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment -Times 1 -ParameterFilter {
            $Scope -eq '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stg1' -and $AtScope -eq $true
        }
    }

    It 'rejects -ResolveNames without -IncludeRoleAssignments' {
        $null = Get-OERResource -Subscription 'Prod' -ResolveNames -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err[0].FullyQualifiedErrorId | Should -BeLike 'ResolveNamesWithoutRoleAssignments*'
    }

    It 'errors with InvalidScope when scope resolution fails and makes no ARM call' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw [System.Exception]::new('bad scope') }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        $null = Get-OERResource -Subscription 'Bad' -ErrorAction SilentlyContinue -ErrorVariable Err
        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidScope'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'binds -Subscription and -ResourceGroup from the pipeline by property name' {
        foreach ($ParamName in 'Subscription', 'ResourceGroup') {
            $Param = (Get-Command Get-OERResource).Parameters[$ParamName]
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Get-OERResource
        # does not forward -ResourceGroup through Resolve-OERScope (it builds the ARM path
        # directly from the bound value), so assert both the resolver call for -Subscription
        # AND the ARM path actually built from -ResourceGroup.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $null = $Rg | Get-OERResource
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/sub-guid/resourceGroups/rg-net/resources?api-version=2025-04-01'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the resources list catch.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERResource -Subscription 'Prod' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
