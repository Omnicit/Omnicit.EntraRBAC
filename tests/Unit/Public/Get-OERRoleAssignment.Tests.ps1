BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'requires a scope' {
        { Get-OERRoleAssignment -ErrorAction Stop } |
            Should -Throw -ErrorId 'InvalidScope,Get-OERRoleAssignment'
    }

    It 'lists assignments at a subscription scope with paging' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{
                    id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                    name = '00000000-0000-0000-0000-000000000059'
                    properties = [PSCustomObject]@{ roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/r'; principalId = 'p'; principalType = 'User'; scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000000' }
                }
            ) }
        }
        $Result = Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01' -and $All
        }
    }

    It 'applies the atScope filter with -AtScope' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -AtScope
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -like "*roleAssignments?api-version=2022-04-01&`$filter=atScope()*"
        }
    }

    It 'resolves a user principal filter through Graph and applies principalId eq' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = '00000000-0000-0000-0000-000000000058'; userPrincipalName = 'anna@contoso.com' }) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -User 'anna@contoso.com'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -like "*&`$filter=principalId*00000000-0000-0000-0000-000000000058*"
        }
    }

    It 'rejects -AtScope combined with a principal filter' {
        { Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -AtScope -User 'x' -ErrorAction Stop } |
            Should -Throw -ErrorId 'AmbiguousFilter,Get-OERRoleAssignment'
    }

    It 'binds the scope from a piped subscription object' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $Sub = [PSCustomObject]@{ SubscriptionId = 'aaaa1111-0000-0000-0000-000000000000'; DisplayName = 'Prod' }
        $null = $Sub | Get-OERRoleAssignment
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -like '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments*'
        }
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Pipe a real object
        # and assert the resolver received the bound values.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $null = $Rg | Get-OERRoleAssignment
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    It 'binds a piped resource-shaped object end to end, including -ResourceName and -ResourceType' {
        # Companion to the resource-group pipe test above: a real Omnicit.EntraRBAC.Resource object
        # (ConvertTo-OERResource.ps1) also carries ResourceName and ResourceType, and until now
        # nothing piped that shape -- only the ValueFromPipelineByPropertyName attribute was checked
        # by reflection, and the "forwards -ResourceType/-ResourceName" It below passes them as
        # explicit parameters, which never exercises pipeline binding either.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Resource = [PSCustomObject]@{
            SubscriptionId = 'sub-guid'
            ResourceGroup  = 'rg-net'
            ResourceName   = 'stg1'
            ResourceType   = 'Microsoft.Storage/storageAccounts'
        }
        $null = $Resource | Get-OERRoleAssignment
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stg1' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }

    Context '-ResolveNames' {
        It 'enriches with PrincipalDisplayName and RoleName, tags the Resolved type, keeps ids, and caches shared lookups' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'; name = 'a1'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p1'; principalType = 'User'; scope = '/subscriptions/s' } }
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a2'; name = 'a2'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p1'; principalType = 'User'; scope = '/subscriptions/s' } }
                ) }
            } -ParameterFilter { $Path -like '*roleAssignments?api-version=2022-04-01*' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Reader' } }
            } -ParameterFilter { $Path -like '*roleDefinitions/rd1?api-version=2022-04-01*' }
            # displayName AND userPrincipalName are both present on purpose: -PreferDisplayName must
            # pick displayName, proving PrincipalDisplayName is not silently switched to a UPN.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'p1'; displayName = 'Anna Berg'; userPrincipalName = 'anna.berg@contoso.com' }) }
            } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' }

            $Result = @(Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResolveNames)
            $Result.Count | Should -Be 2
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignmentResolved'
            $Result[0].RoleName | Should -Be 'Reader'
            $Result[0].PrincipalDisplayName | Should -Be 'Anna Berg'
            $Result[0].PrincipalDisplayName | Should -Not -Be 'anna.berg@contoso.com'
            # ids retained
            $Result[0].PrincipalId | Should -Be 'p1'
            $Result[0].RoleDefinitionId | Should -Be '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'
            $Result[0].RoleAssignmentId | Should -Be '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'
            # caching: each unique role/principal resolved once across both assignments, via ONE
            # batched getByIds call, not one GET per principal.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*roleDefinitions/rd1*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and ($Body.ids -contains 'p1')
            }
        }

        It 'batches every distinct principal on a page through one getByIds call, not one per principal' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'; name = 'a1'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p1'; principalType = 'User'; scope = '/subscriptions/s' } }
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a2'; name = 'a2'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p2'; principalType = 'Group'; scope = '/subscriptions/s' } }
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a3'; name = 'a3'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p3'; principalType = 'ServicePrincipal'; scope = '/subscriptions/s' } }
                ) }
            } -ParameterFilter { $Path -like '*roleAssignments?api-version=2022-04-01*' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Reader' } }
            } -ParameterFilter { $Path -like '*roleDefinitions/rd1?api-version=2022-04-01*' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'p1'; displayName = 'Anna Berg' }
                    @{ id = 'p2'; displayName = 'Sales Team' }
                    @{ id = 'p3'; displayName = 'svc-app' }
                ) }
            } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' }

            $Result = @(Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResolveNames)
            $Result.Count | Should -Be 3
            ($Result | Where-Object PrincipalId -eq 'p1').PrincipalDisplayName | Should -Be 'Anna Berg'
            ($Result | Where-Object PrincipalId -eq 'p2').PrincipalDisplayName | Should -Be 'Sales Team'
            ($Result | Where-Object PrincipalId -eq 'p3').PrincipalDisplayName | Should -Be 'svc-app'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and
                ($Body.ids -contains 'p1') -and ($Body.ids -contains 'p2') -and ($Body.ids -contains 'p3')
            }
        }

        It 'resolves a Device principal to its display name (M-1: batching must not narrow directory object coverage)' {
            # The per-principal GET this batching replaced (v1.0/directoryObjects/<id>) resolved ANY
            # directory object; Get-OERInventory's own comments acknowledge Azure role assignments can
            # carry ForeignGroup and Device principals. A getByIds call restricted to
            # user/group/servicePrincipal would silently exclude a Device principal, showing a raw
            # GUID where the old GET showed a name. Two layers: a catch-all that fails loudly if the
            # request still carries a 'types' filter, and the real (untyped) response underneath it --
            # so a regression back to the type-restricted call fails this test instead of just quietly
            # returning the id.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'; name = 'a1'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'dev-1'; principalType = 'Device'; scope = '/subscriptions/s' } }
                ) }
            } -ParameterFilter { $Path -like '*roleAssignments?api-version=2022-04-01*' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Reader' } }
            } -ParameterFilter { $Path -like '*roleDefinitions/rd1?api-version=2022-04-01*' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'unexpected getByIds call shape in device-principal test' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'dev-1'; displayName = 'CORP-LAPTOP-01' }) }
            } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and -not $Body.ContainsKey('types') }

            $Result = @(Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResolveNames)
            $Result[0].PrincipalDisplayName | Should -Be 'CORP-LAPTOP-01'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and -not $Body.ContainsKey('types')
            }
        }

        It 'falls back to ids when a principal or role cannot be resolved' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'; name = 'a1'; properties = [PSCustomObject]@{ roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/rdX'; principalId = 'pX'; principalType = 'User'; scope = '/subscriptions/s' } }
                ) }
            } -ParameterFilter { $Path -like '*roleAssignments?api-version=2022-04-01*' }
            $RoleErr = InModuleScope Omnicit.EntraRBAC {
                Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"no"}}' })
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $RoleErr }.GetNewClosure() -ParameterFilter { $Path -like '*roleDefinitions/rdX*' }
            # getByIds returns nothing for 'pX' (deleted, or not readable): Resolve-OERPrincipalName's
            # own fallback rule maps it back to the id itself.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' }

            $Result = @(Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000' -ResolveNames)
            $Result[0].RoleName | Should -Be 'rdX'
            $Result[0].PrincipalDisplayName | Should -Be 'pX'
        }

        It 'does not resolve or tag when -ResolveNames is omitted' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1'; name = 'a1'; properties = [PSCustomObject]@{ roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/rd1'; principalId = 'p1'; principalType = 'User'; scope = '/subscriptions/s' } }
                ) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'should not be called' }
            $Result = @(Get-OERRoleAssignment -Subscription 'aaaa1111-0000-0000-0000-000000000000')
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
            $Result[0].PSObject.Properties.Name | Should -Not -Contain 'PrincipalDisplayName'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command Get-OERRoleAssignment).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }

    It 'binds -ResourceName and -ResourceType from the pipeline by property name' {
        foreach ($ParamName in 'ResourceName', 'ResourceType') {
            $Param = (Get-Command Get-OERRoleAssignment).Parameters[$ParamName]
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }
    }

    It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Get-OERRoleAssignment -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the roleAssignments list catch -- a raw -Scope makes Resolve-OERScope return without an ARM call.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERRoleAssignment -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000000' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
