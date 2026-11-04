BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }

    Context 'a failed role assignment read (BL-162a)' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-a'; name = 'rg-a'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
                    [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-b'; name = 'rg-b'; location = 'northeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
                ) }
            }
            # The first group's read fails with the read's own id; the second one succeeds.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment {
                if ($Scope -like '*/rg-a') {
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
            $Result = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue -ErrorVariable Err -WarningVariable Warn)
            $Result.Count | Should -Be 2
            $Result[0].Name | Should -Be 'rg-a'
            ($null -eq $Result[0].RoleAssignments) | Should -BeTrue -Because 'unread is null, never an empty array'
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResourceGroup' })
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'RoleAssignmentReadFailed*'
            @($Warn).Count | Should -Be 0
        }

        It 'still processes the next resource group after the first failed' {
            $Result = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue)
            $Result[1].Name | Should -Be 'rg-b'
            @($Result[1].RoleAssignments).Count | Should -Be 1
            $Result[1].RoleAssignments[0].PrincipalId | Should -Be 'p2'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment -Times 2 -Exactly
        }

        It 'writes the resource group before the error record' {
            $Stream = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments -ErrorAction Continue 2>&1)
            $Stream.Count | Should -Be 3
            $Stream[0].Name | Should -Be 'rg-a'
            $Stream[1] | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Stream[2].Name | Should -Be 'rg-b'
        }

        It 'scrubs the caught record once' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $null = Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'reaches a caller''s -ErrorVariable with no try around the call, and still returns the object' {
            # No try and no catch around the call: the record is a written one, not a raised one.
            $Result = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 2
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResourceGroup' })
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
                $Result = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments `
                        -ErrorAction SilentlyContinue -ErrorVariable Err)
            } finally {
                $global:ErrorActionPreference = $Saved
            }
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResourceGroup' })
            ($null -eq $Result[0].RoleAssignments) | Should -BeTrue
            @($Err).Count | Should -Be 2 -Because 'one record per resource group'
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'RoleAssignmentReadFailed*'
        }

        It 'gives an empty array, not null, when the read succeeds with no rows' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignment { }
            $Result = @(Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments `
                    -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 2
            ($null -eq $Result[0].RoleAssignments) | Should -BeFalse
            @($Result[0].RoleAssignments).Count | Should -Be 0
            $Err = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERResourceGroup' })
            @($Err).Count | Should -Be 0
        }
    }
}
