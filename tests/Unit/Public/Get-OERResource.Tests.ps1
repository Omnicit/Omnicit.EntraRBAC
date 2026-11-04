BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }

    Context 'a failed role assignment read (BL-162a)' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stg1'; name = 'stg1'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope' }
                    [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-app/providers/Microsoft.Web/sites/web1'; name = 'web1'; type = 'Microsoft.Web/sites'; location = 'westeurope' }
                ) }
            }
            # The first resource's read fails with the read's own id; the second one succeeds.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment {
                if ($Scope -like '*storageAccounts/stg1') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ARM read refused'),
                        'RoleAssignmentReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $null)
                }
                [PSCustomObject]@{ PrincipalId = 'p2' }
            }
        }

        It 'sets RoleAssignments to null, writes one record with the read''s id and no warning' {
            $Result = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue -ErrorVariable Err -WarningVariable Warn)
            $Result.Count | Should -Be 2
            $Result[0].Name | Should -Be 'stg1'
            ($null -eq $Result[0].RoleAssignments) | Should -BeTrue -Because 'unread is null, never an empty array'
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResource' })
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'RoleAssignmentReadFailed*'
            @($Warn).Count | Should -Be 0
        }

        It 'still processes the next resource after the first failed' {
            $Result = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue)
            $Result[1].Name | Should -Be 'web1'
            @($Result[1].RoleAssignments).Count | Should -Be 1
            $Result[1].RoleAssignments[0].PrincipalId | Should -Be 'p2'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment -Times 2 -Exactly
        }

        It 'writes the resource before the error record' {
            $Stream = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments -ErrorAction Continue 2>&1)
            $Stream.Count | Should -Be 3
            $Stream[0].Name | Should -Be 'stg1'
            $Stream[1] | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Stream[2].Name | Should -Be 'web1'
        }

        It 'scrubs the caught record once' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $null = Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments `
                -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'reaches a caller''s -ErrorVariable with no try around the call, and still returns the object' {
            # No try and no catch around the call: the record is a written one, not a raised one, so it
            # lands in the variable and the object comes back.
            $Result = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -Name 'stg1' `
                    -IncludeRoleAssignments -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 1
            $Result[0].Name | Should -Be 'stg1'
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResource' })
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'RoleAssignmentReadFailed*'
        }

        It 'treats a non-terminating error of the read as a failure too' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment {
                [CmdletBinding()]
                param($Scope, $AtScope, $ResolveNames)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ARM read refused'), 'RoleAssignmentReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError, $null))
            }
            # The mock body runs under the GLOBAL preference, which Pester sets to Stop; pin it to Continue
            # so the mock's record is non-terminating unless the cmdlet itself asks for -ErrorAction Stop.
            $Saved = $global:ErrorActionPreference
            $global:ErrorActionPreference = 'Continue'
            try {
                $Result = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments `
                        -ErrorAction SilentlyContinue -ErrorVariable Err)
            } finally {
                $global:ErrorActionPreference = $Saved
            }
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResource' })
            ($null -eq $Result[0].RoleAssignments) | Should -BeTrue
            @($Err).Count | Should -Be 2 -Because 'one record per resource'
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'RoleAssignmentReadFailed*'
        }

        It 'gives an empty array, not null, when the read succeeds with no rows' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment { }
            $Result = @(Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 2
            ($null -eq $Result[0].RoleAssignments) | Should -BeFalse
            @($Result[0].RoleAssignments).Count | Should -Be 0
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResource' })
            @($Err).Count | Should -Be 0
        }
    }
}
