BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERResourceGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid' }
    }

    It 'lists all resource groups in the subscription' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-a'; name = 'rg-a'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-b'; name = 'rg-b'; location = 'northeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
            ) }
        }
        $Result = Get-OERResourceGroup -Subscription 'Prod'
        $Result.Count | Should -Be 2
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ResourceGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/sub-guid/resourcegroups?api-version=2025-04-01'
        }
    }

    It 'gets a single resource group by name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-a'; name = 'rg-a'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        $Result = Get-OERResourceGroup -Subscription 'Prod' -Name 'rg-a'
        $Result.Name | Should -Be 'rg-a'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/sub-guid/resourcegroups/rg-a?api-version=2025-04-01'
        }
    }

    It 'attaches RoleAssignments with -IncludeRoleAssignments' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-a'; name = 'rg-a'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
            ) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment {
            [PSCustomObject]@{ PrincipalId = 'p1'; Scope = '/subscriptions/sub-guid/resourceGroups/rg-a' }
        }
        $Result = Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments
        @($Result.RoleAssignments).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment -Times 1 -ParameterFilter {
            $Scope -eq '/subscriptions/sub-guid/resourceGroups/rg-a' -and $AtScope -eq $true
        }
    }

    It 'rejects -ResolveNames without -IncludeRoleAssignments' {
        $null = Get-OERResourceGroup -Subscription 'Prod' -ResolveNames -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err[0].FullyQualifiedErrorId | Should -BeLike 'ResolveNamesWithoutRoleAssignments*'
    }

    # T3: InvalidScope branch -- scope resolution failure is routed without any ARM call
    It 'errors with InvalidScope when scope resolution fails' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw [System.Exception]::new('bad scope') }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        $null = Get-OERResourceGroup -Subscription 'Bad' -ErrorAction SilentlyContinue -ErrorVariable Err
        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidScope'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the resource group LIST catch (no -Name).
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERResourceGroup -Subscription 'Prod' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
