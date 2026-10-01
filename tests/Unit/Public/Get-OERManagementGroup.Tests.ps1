BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERManagementGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'authenticates with -IncludeARM' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Get-OERManagementGroup
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -ParameterFilter { $IncludeARM }
    }

    It 'lists all management groups with paging' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
            ) }
        }
        $Result = Get-OERManagementGroup
        $Result.Name | Should -Be 'mg1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ManagementGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All
        }
    }

    It 'gets a single management group by name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
        }
        $Result = Get-OERManagementGroup -Name 'mg1'
        $Result.DisplayName | Should -Be 'MG One'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01'
        }
    }

    It 'adds $expand=children for -Expand and $recurse=true (with expand) for -Recurse' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
        }
        $null = Get-OERManagementGroup -Name 'mg1' -Expand
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&$expand=children'
        }
        $null = Get-OERManagementGroup -Name 'mg1' -Recurse
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/providers/Microsoft.Management/managementGroups/mg1?api-version=2020-05-01&$expand=children&$recurse=true'
        }
    }

    It 'writes a non-terminating error when the ARM call fails' {
        $ArmErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $ArmErr }
        { Get-OERManagementGroup -ErrorAction Stop } | Should -Throw -ErrorId 'AuthorizationFailed,Get-OERManagementGroup'
        { Get-OERManagementGroup -ErrorAction SilentlyContinue } | Should -Not -Throw
    }

    It 'returns a clean ManagementGroupNotFound for a name that does not exist (ARM 403 AuthorizationFailed)' {
        $AuthErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"...does not have authorization... or the scope is invalid."}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $AuthErr }.GetNewClosure()
        { Get-OERManagementGroup -Name 'Does not exist' -ErrorAction Stop } |
            Should -Throw -ErrorId 'ManagementGroupNotFound,Get-OERManagementGroup' `
                -ExpectedMessage "*'Does not exist' was not found, or you do not have access to it*"
    }

    It 'still surfaces a non-not-found ARM error (e.g. throttling) on the -Name path' {
        $ThrottleErr = InModuleScope Omnicit.EntraRBAC {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests","message":"slow down"}}' })
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $ThrottleErr }.GetNewClosure()
        { Get-OERManagementGroup -Name 'mg1' -ErrorAction Stop } |
            Should -Throw -ErrorId 'TooManyRequests,Get-OERManagementGroup'
    }

    Context 'scope-target naming (audit PR6)' {
        It 'accepts -ManagementGroup as an alias for -Name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform'; name = 'mg-platform'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Platform' } }
            }
            Get-OERManagementGroup -ManagementGroup 'mg-platform' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*managementGroups/mg-platform*'
            }
            # A real invocation alone would still pass via PowerShell's unambiguous prefix-name
            # matching against the pre-existing ManagementGroupName alias, even without a dedicated
            # -ManagementGroup alias. Assert the alias is actually declared so this stays locked in
            # even if a future parameter (e.g. -ManagementGroupId) makes the prefix match ambiguous.
            (Get-Command Get-OERManagementGroup).Parameters['Name'].Aliases | Should -Contain 'ManagementGroup'
        }

        It 'emits ResourceId and no bare Id, so an ARM path cannot mis-bind downstream id parameters' {
            # B-subscription-mg-id-collides: a bare Id holding the ARM path used to bind
            # -RoleEligibilityScheduleId and -PolicyId, both of which carry Alias('Id') plus
            # ValueFromPipelineByPropertyName.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG One' } }
            }
            $Mg = Get-OERManagementGroup -Name 'mg1'
            $Mg.PSObject.Properties.Name | Should -Contain 'ResourceId'
            $Mg.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the management group LIST catch (no -Name).
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERManagementGroup -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
