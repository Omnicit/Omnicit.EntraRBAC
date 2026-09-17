BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'New-OERRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    Context 'validation' {
        It 'requires exactly one principal' {
            { New-OERRoleAssignment -Role 'Reader' -Subscription 'aaaa1111-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'NoPrincipal,New-OERRoleAssignment'
            { New-OERRoleAssignment -Role 'Reader' -Subscription 'aaaa1111-0000-0000-0000-000000000000' -User 'u' -Group 'g' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'AmbiguousPrincipal,New-OERRoleAssignment'
        }

        It 'rejects -ConditionVersion without -Condition' {
            { New-OERRoleAssignment -Role 'Reader' -Subscription 'aaaa1111-0000-0000-0000-000000000000' -User '00000000-0000-0000-0000-000000000058' -ConditionVersion '2.0' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'ConditionVersionWithoutCondition,New-OERRoleAssignment'
        }

        It 'rejects a condition version other than 2.0 (audit A-condition-version-no-validateset)' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { @{ } }

            $Threw = $false
            try {
                New-OERRoleAssignment -Role 'Reader' -User 'anna@contoso.com' `
                    -Subscription '00000000-0000-0000-0000-000000000000' `
                    -Condition "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'x'" `
                    -ConditionVersion 'v2' -Confirm:$false
            } catch {
                $Threw = $true
                $_.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            }
            $Threw | Should -Be $true
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
        }

        It 'accepts -ConditionVersion 2.0 (positive regression)' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000000' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
            New-OERRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription '00000000-0000-0000-0000-000000000000' `
                -Condition "@Resource[x]" -ConditionVersion '2.0' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.conditionVersion -eq '2.0'
            }
        }
    }

    Context 'creation' {
        It 'PUTs the verified body shape with a client-generated GUID name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{
                    id = '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/new1'
                    name = 'new1'
                    properties = [PSCustomObject]@{ roleDefinitionId = 'rd'; principalId = '00000000-0000-0000-0000-000000000058'; principalType = 'User'; scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000000' }
                }
            }
            $Result = New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -User '00000000-0000-0000-0000-000000000058' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Confirm:$false
            $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -match '^/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft\.Authorization/roleAssignments/[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\?api-version=2022-04-01$' -and
                $Body.properties.roleDefinitionId -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' -and
                $Body.properties.principalId -eq '00000000-0000-0000-0000-000000000058' -and
                $Body.properties.principalType -eq 'User' -and
                -not $Body.properties.ContainsKey('condition')
            }
        }

        It 'includes description and condition with default conditionVersion 2.0' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
            $null = New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -Group 'bbbb0000-0000-0000-0000-000000000002' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Description 'desc' -Condition 'cond' `
                -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.principalType -eq 'Group' -and
                $Body.properties.description -eq 'desc' -and
                $Body.properties.condition -eq 'cond' -and
                $Body.properties.conditionVersion -eq '2.0'
            }
        }

        It 'honors -WhatIf (no ARM call)' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
            $null = New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -User '00000000-0000-0000-0000-000000000058' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
        }

        It 'surfaces a 409 RoleAssignmentExists as a non-terminating error' {
            $ConflictError = InModuleScope Omnicit.EntraRBAC {
                Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 409; Content = '{"error":{"code":"RoleAssignmentExists","message":"exists"}}' })
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw $ConflictError }.GetNewClosure()
            { New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -User '00000000-0000-0000-0000-000000000058' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'RoleAssignmentExists,New-OERRoleAssignment'
        }

        It 'binds -Role from a piped role definition object' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
            $RoleDef = [PSCustomObject]@{ RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleName = 'Reader' }
            $null = $RoleDef | New-OERRoleAssignment `
                -User '00000000-0000-0000-0000-000000000058' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.roleDefinitionId -eq '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
            }
        }

        It 'binds -Role via RoleDefinitionId from a REAL ConvertTo-OERRoleDefinition object (task-2d regression: RoleDefinitionId keeps working after Id becomes ResourceId)' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
            $RoleDef = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERRoleDefinition -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    name       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    properties = @{ roleName = 'Reader'; type = 'BuiltInRole' }
                }
            }
            $null = $RoleDef | New-OERRoleAssignment `
                -User '00000000-0000-0000-0000-000000000058' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.roleDefinitionId -eq '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
            }
        }

        It 'surfaces PrincipalNotFound and never reaches the PUT when the user cannot be resolved' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
            { New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -User 'ghost@contoso.com' `
                -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'PrincipalNotFound,New-OERRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
        }

        It 'builds the management group scope path when -ManagementGroup is used' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform' }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/mg-platform?api-version=2020-05-01' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-platform/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            } -ParameterFilter { $Method -eq 'PUT' }
            $null = New-OERRoleAssignment `
                -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' `
                -User '00000000-0000-0000-0000-000000000058' `
                -ManagementGroup 'mg-platform' `
                -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -like '/providers/Microsoft.Management/managementGroups/mg-platform/providers/Microsoft.Authorization/roleAssignments/*?api-version=2022-04-01' -and
                $Body.properties.roleDefinitionId -eq '/providers/Microsoft.Management/managementGroups/mg-platform/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
            }
        }
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command New-OERRoleAssignment).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }

    It 'binds -ResourceName and -ResourceType from the pipeline by property name' {
        foreach ($ParamName in 'ResourceName', 'ResourceType') {
            $Param = (Get-Command New-OERRoleAssignment).Parameters[$ParamName]
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }
    }

    It 'accepts a piped resource-group-shaped object (SubscriptionId + ResourceGroup)' {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'Group' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ id = 'ra'; properties = [PSCustomObject]@{ principalId = 'p1'; roleDefinitionId = 'rd'; scope = '/subscriptions/sub-guid/resourceGroups/rg-net' } } }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERRoleAssignment { [PSCustomObject]@{ ok = $true } }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $Rg | New-OERRoleAssignment -Role 'Reader' -Group 'role_sec_readers' -Confirm:$false
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
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'Group' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ id = 'ra'; properties = [PSCustomObject]@{ principalId = 'p1'; roleDefinitionId = 'rd'; scope = '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' } } }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERRoleAssignment { [PSCustomObject]@{ ok = $true } }

        $Resource = [PSCustomObject]@{
            SubscriptionId = 'sub-guid'
            ResourceGroup  = 'rg-net'
            ResourceName   = 'stg1'
            ResourceType   = 'Microsoft.Storage/storageAccounts'
        }
        $Resource | New-OERRoleAssignment -Role 'Reader' -Group 'role_sec_readers' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stg1' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }

    It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ id = 'ra'; properties = [PSCustomObject]@{ principalId = 'p1'; roleDefinitionId = 'rd'; scope = '/subscriptions/sub-guid/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1' } } }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERRoleAssignment { [PSCustomObject]@{ ok = $true } }
        New-OERRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM PUT fails' {
        # CLAUDE.md SECURITY rule 6. Drives the transport catch at
        # source/Public/New-OERRoleAssignment.ps1:198. All three resolvers are mocked to SUCCEED so the
        # throwing transport is the only thing that can enter a catch -- an unmocked resolver would make
        # this assert the wrong catch.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/aaaa1111-0000-0000-0000-000000000000' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '00000000-0000-0000-0000-000000000058'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = New-OERRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }

    Context 'PrincipalId pipeline binding (audit B-new-roleassignment-principal-not-pipeable)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000000' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/r1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
        }

        It 'accepts a principal id from the pipeline' {
            # Adapted from the brief's template test: a real ConvertTo-OEREligibleRoleAssignment
            # object (which carries a stored PrincipalId property, not an AliasProperty) pipes its
            # principal straight into -PrincipalId by property name.
            $Eligible = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OEREligibleRoleAssignment -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleEligibilitySchedules/e1'
                    properties = @{
                        principalId      = '33333333-3333-3333-3333-333333333333'
                        roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                        scope            = '/subscriptions/s'
                    }
                }
            }
            $Eligible | New-OERRoleAssignment -Subscription '00000000-0000-0000-0000-000000000000' `
                -Role 'Reader' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly `
                -ParameterFilter { $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333' }
        }

        It 'binds -PrincipalId as a pipeline-by-property-name parameter (attribute check)' {
            $Param = (Get-Command New-OERRoleAssignment).Parameters['PrincipalId']
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }

        It 'does not let a piped DisplayName hijack -Group when -User is supplied explicitly' {
            # ConvertTo-OERSubscription emits DisplayName. -Group deliberately carries no
            # [Alias('DisplayName')] (see the brief), so piping a Subscription object alongside an
            # explicit -User must never produce AmbiguousPrincipal. Use the REAL converter, not a
            # hand-built stand-in -- a stand-in can silently drift from what the converter actually
            # emits (exactly the practice this task otherwise criticises).
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            $Sub = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERSubscription -InputObject @{
                    id             = '/subscriptions/00000000-0000-0000-0000-000000000000'
                    subscriptionId = '00000000-0000-0000-0000-000000000000'
                    displayName    = 'Prod'
                    state          = 'Enabled'
                }
            }
            $Sub | New-OERRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
            # Positive half: a not-X-only assertion would also pass if the pipe silently failed for
            # an unrelated reason. Prove it actually reached the ARM call.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.principalId -eq 'p1'
            }
        }

        It 'errors with InvalidPrincipalId when -PrincipalId is not a GUID' {
            New-OERRoleAssignment -Role 'Reader' -PrincipalId 'not-a-guid' -Subscription '00000000-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId,New-OERRoleAssignment'
        }

        It 'sends -PrincipalType in the body when supplied alongside a raw -PrincipalId (controller ruling I-2)' {
            # ARM's documented mitigation for a principal that has not yet replicated. A raw
            # -PrincipalId performs no Graph lookup (Resolve-OERPrincipalOrId never resolves a type
            # for it), so without an explicit -PrincipalType the canonical "just created a managed
            # identity" case could not send the mitigation at all.
            New-OERRoleAssignment -Role 'Reader' -PrincipalId '33333333-3333-3333-3333-333333333333' `
                -PrincipalType 'ServicePrincipal' -Subscription '00000000-0000-0000-0000-000000000000' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333' -and
                $Body.properties.principalType -eq 'ServicePrincipal'
            }
        }

        It 'omits the principalType KEY entirely (not $null) when it is unknown' {
            # $Body.properties is a hashtable, not a PSCustomObject -- .PSObject.Properties.Name on a
            # Hashtable reflects the .NET Hashtable class's OWN members (IsReadOnly, Keys, Values,
            # Count, ...), never the dictionary's own keys, so that reflection-based absence check
            # would be silently vacuous here (always passes, proves nothing). Assert with ContainsKey
            # instead, which is what genuinely distinguishes "key absent" from "key present with a
            # null value" for a hashtable body. Capture the real Body from inside the mock itself
            # (the established pattern in this suite), not from inside a -ParameterFilter predicate.
            $script:CapturedBody = $null
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                $script:CapturedBody = $Body
                [PSCustomObject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
            }
            New-OERRoleAssignment -Role 'Reader' -PrincipalId '33333333-3333-3333-3333-333333333333' `
                -Subscription '00000000-0000-0000-0000-000000000000' -Confirm:$false | Out-Null
            $script:CapturedBody.properties.principalId | Should -Be '33333333-3333-3333-3333-333333333333'
            $script:CapturedBody.properties.ContainsKey('principalType') | Should -Be $false
        }

        It 'still rejects a genuinely invalid -PrincipalType (the empty-string ValidateSet entry does not defang it)' {
            { New-OERRoleAssignment -Role 'Reader' -PrincipalId '33333333-3333-3333-3333-333333333333' `
                    -PrincipalType 'Bogus' -Subscription '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,New-OERRoleAssignment'
        }

        It 'binds a piped PrincipalType (empty string from a real converter) without a ValidateSet binding failure (regression)' {
            # Empirically confirmed BEFORE this fix: piping ConvertTo-OEREligibleRoleAssignment output
            # with no principalId.principalType on the wire (so PrincipalType casts to '') threw
            # ParameterBindingValidationException at bind time and the item was silently skipped --
            # the "accepts a principal id from the pipeline" test above would fail with "Invoke-OERArmRequest
            # ... called 0 times" if this regressed again.
            $Eligible = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OEREligibleRoleAssignment -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleEligibilitySchedules/e1'
                    properties = @{
                        principalId      = '33333333-3333-3333-3333-333333333333'
                        roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                        scope            = '/subscriptions/s'
                    }
                }
            }
            $Eligible.PrincipalType | Should -Be ''
            $Eligible | New-OERRoleAssignment -Subscription '00000000-0000-0000-0000-000000000000' `
                -Role 'Reader' -Confirm:$false -ErrorAction Stop | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333'
            }
        }
    }

    Context 'principal/scope error precedence (task-2 controller note)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw 'bad scope' }
        }
        It 'reports PrincipalNotFound, not InvalidScope, when both the scope and the principal are bad' {
            # DESIGN DECISION: Resolve-OERPrincipalOrId now replaces both the old early principal
            # count-guard and the later Resolve-OERPrincipal call in a SINGLE call, positioned after
            # the cheap local -ConditionVersion check but still BEFORE Resolve-OERScope. So a call
            # with both a bad scope and an unresolvable principal now reports PrincipalNotFound, not
            # InvalidScope, and Resolve-OERScope is never even invoked. Pinned here per the task-2
            # brief. -ErrorVariable also accumulates the nested terminating throw from inside
            # Resolve-OERPrincipal as it unwinds (a PowerShell quirk, not a bug -- see CLAUDE.md), so
            # assert presence across all captured records rather than position $e[0].
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            New-OERRoleAssignment -Role 'Reader' -User 'ghost@contoso.com' -Subscription 'not-a-real-sub' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PrincipalNotFound,New-OERRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0 -Exactly
        }
    }
}

Describe 'New-OERRoleAssignment verbose output' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/aaaa1111-0000-0000-0000-000000000000' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
            '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '00000000-0000-0000-0000-000000000058'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/x/y'; name = 'ra-1'; properties = [PSCustomObject]@{
                    roleDefinitionId = '/rd/1'; principalId = '00000000-0000-0000-0000-000000000058'; scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000000'
                }
            }
        }
    }

    It 'reports the resolved scope, role and principal under -Verbose' {
        $Verbose = New-OERRoleAssignment -SubscriptionId 'aaaa1111-0000-0000-0000-000000000000' `
            -Role 'Reader' -User '00000000-0000-0000-0000-000000000058' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }

        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[New-OERRoleAssignment\] Target scope:'
        $Text | Should -Match "\[New-OERRoleAssignment\] Resolved role 'Reader' to "
        $Text | Should -Match '\[New-OERRoleAssignment\] Resolved principal to '
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = New-OERRoleAssignment -SubscriptionId 'aaaa1111-0000-0000-0000-000000000000' `
            -Role 'Reader' -User '00000000-0000-0000-0000-000000000058' -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved role
        # definition id legitimately contains the 'Microsoft.Authorization' resource-provider
        # namespace (e.g. '.../providers/Microsoft.Authorization/roleDefinitions/...'), which is
        # not a header or token leak. Assert against the actual header/token shape instead
        # ('Authorization:' with a colon, or the word 'bearer').
        $Text = (New-OERRoleAssignment -SubscriptionId 'aaaa1111-0000-0000-0000-000000000000' `
                -Role 'Reader' -User '00000000-0000-0000-0000-000000000058' -Confirm:$false -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'New-OERRoleAssignment piped principal ambiguity guard' {
    <#
        Whole-branch review finding I-1. Task 2 made -PrincipalId ValueFromPipelineByPropertyName and
        Resolve-OERPrincipalOrId gives -PrincipalId precedence over the friendly parameters, so

            Get-OERRoleAssignment -Subscription $S | New-OERRoleAssignment -Role Reader -User anna@... -Scope $T

        stopped creating the assignment for anna and started creating one per piped object, for that
        object's OWN principal. Settled precedent (PR #26, Remove-OERGroupEligibility and
        Remove-OERAdministrativeUnitScopedRole) is to refuse this collision as AmbiguousPrincipal
        rather than warn, because the outcome is privileged access granted to a principal the caller
        never named.

        DELIBERATE NARROWING vs those two cmdlets: the guard here also requires the PIPED ITEM to
        carry a PrincipalId of its own. This cmdlet's pipeline is polymorphic -- a role definition,
        subscription, resource group or resource pipes in to supply the ROLE or the SCOPE, and pairing
        one of those with a named principal is the cmdlet's own second .EXAMPLE. Five existing tests
        in this file depend on that (two role-definition pipes with -User, two resource-shaped pipes
        with -Group, and the piped-DisplayName test that asserts AmbiguousPrincipal is NOT raised);
        an ExpectingInput-only guard would have broken all five and removed a documented capability.
    #>
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000000' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/r1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'friendly-principal'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
        }
    }

    It 'errors AmbiguousPrincipal and issues no ARM call when -User is bound alongside a piped assignment object' {
        # Built by the REAL converter, not a hand-rolled stand-in: a stand-in can drift from what the
        # converter actually emits, and the whole hazard is that every assignment-shaped object the
        # module produces carries PrincipalId.
        $Assignment = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ra1'
                name       = 'ra1'
                properties = @{
                    principalId      = '33333333-3333-3333-3333-333333333333'
                    principalType    = 'ServicePrincipal'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Assignment | New-OERRoleAssignment -Role 'Reader' -User 'anna@contoso.com' `
            -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,New-OERRoleAssignment'
        $Err[0].Exception.Message | Should -BeLike '*33333333-3333-3333-3333-333333333333*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'still binds the piped PrincipalId when no friendly parameter is supplied (Task 2 capability regression)' {
        # The guard must not cost Task 2 its new capability. Same pipe, no -User.
        $Assignment = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ra1'
                name       = 'ra1'
                properties = @{
                    principalId      = '33333333-3333-3333-3333-333333333333'
                    principalType    = 'ServicePrincipal'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Assignment | New-OERRoleAssignment -Role 'Reader' `
            -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333'
        }
    }

    It 'only WARNS for a direct call supplying both -PrincipalId and -User: the guard is pipe-only' {
        # Resolve-OERPrincipalOrId's documented precedence rule is unchanged off the pipeline -- the
        # operator typed both values in one visible command, so a warning is proportionate there.
        $Err = $null
        $Warnings = New-OERRoleAssignment -Role 'Reader' `
            -PrincipalId '33333333-3333-3333-3333-333333333333' -User 'anna@contoso.com' `
            -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        ($Warnings.Message -join "`n") | Should -Match '-PrincipalId takes precedence'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333'
        }
    }

    It 'binds a piped LEGACY PrincipalType instead of dropping the item at bind time (review M-5)' {
        <#
            -PrincipalType is a CLOSED ValidateSet on a pipeline-bound, converter-fed parameter. A
            piped record carrying a historical ARM spelling used to fail parameter binding, which
            skips THAT ITEM SILENTLY while the rest of the pipeline continues -- an assignment lost
            with no error the operator can act on. The set now carries the legacy values too.
        #>
        foreach ($LegacyType in 'Unknown', 'DirectoryRoleTemplate', 'Application', 'MSI', 'DirectoryObjectOrGroup', 'Everyone') {
            $Assignment = InModuleScope Omnicit.EntraRBAC -Parameters @{ LegacyType = $LegacyType } {
                param($LegacyType)
                ConvertTo-OERRoleAssignment -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ra1'
                    name       = 'ra1'
                    properties = @{
                        principalId      = '44444444-4444-4444-4444-444444444444'
                        principalType    = $LegacyType
                        roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                        scope            = '/subscriptions/s'
                    }
                }
            }
            $Assignment.PrincipalType | Should -Be $LegacyType
            $Assignment | New-OERRoleAssignment -Role 'Reader' `
                -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction Stop | Out-Null
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 6 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalType -eq 'MSI'
        }
    }
}
