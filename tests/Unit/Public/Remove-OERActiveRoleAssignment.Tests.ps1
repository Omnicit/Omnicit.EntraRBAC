BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Remove-OERActiveRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    Context 'request construction' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='aaaa0000-0000-0000-0000-000000000001'; principalType='User'; requestType='AdminRemove'; status='Provisioned'; requestorId='aaaa0000-0000-0000-0000-000000000001'; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'PUTs an AdminRemove roleAssignmentScheduleRequests request with no scheduleInfo' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -like '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/*`?api-version=2020-10-01' -and
                $Body.properties.requestType -eq 'AdminRemove' -and
                $Body.properties.principalId -eq 'aaaa0000-0000-0000-0000-000000000001' -and
                -not $Body.properties.ContainsKey('scheduleInfo')
            }
        }
        It 'uses -PrincipalId directly without resolving a principal' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 0
        }
        It 'resolves a friendly principal when -User is supplied' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Body.properties.principalId -eq 'p1' }
        }
        It 'binds principalId, role, and scope from the pipeline' {
            [PSCustomObject]@{ PrincipalId='aaaa0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Remove-OERActiveRoleAssignment -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.principalId -eq 'aaaa0000-0000-0000-0000-000000000001' -and $Body.properties.requestType -eq 'AdminRemove'
            }
        }
        It 'honors -WhatIf (no ARM call)' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
            }
        }
        It 'warns before removing and still issues the PUT' {
            # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- Remove-OERActiveRoleAssignment.ps1:128
            # emits an operator warning before the destructive PUT (AdminRemove), but no It captured it.
            $Warnings = @()
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
            $Warnings.Count | Should -BeGreaterThan 0
            $Warnings -join ' ' | Should -Match 'active assignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'scrubs the bearer-hygiene record when the ARM PUT fails' {
            # CLAUDE.md SECURITY rule 6. Drives the transport catch at
            # source/Public/Remove-OERActiveRoleAssignment.ps1:144. -PrincipalId skips the friendly
            # principal lookup and the Context BeforeAll already mocks Resolve-OERScope and
            # Resolve-OERRoleDefinitionId, so the AdminRemove PUT is the only failing call.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $null = Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }
    }
    Context 'validation' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='aaaa0000-0000-0000-0000-000000000001'; principalType='User'; requestType='AdminRemove'; status='Provisioned'; requestorId='aaaa0000-0000-0000-0000-000000000001'; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'errors when no principal is supplied' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
        }
        It 'errors when two principals are supplied' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Group 'b' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousPrincipal'
        }
        It 'errors with InvalidPrincipalId when -PrincipalId is not a GUID' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'anna@contoso.com' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'accepts a GUID -PrincipalId and proceeds to the ARM call' {
            Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command Remove-OERActiveRoleAssignment).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }
    It 'binds -ResourceName and -ResourceType from the pipeline by property name' {
        foreach ($ParamName in 'ResourceName', 'ResourceType') {
            $Param = (Get-Command Remove-OERActiveRoleAssignment).Parameters[$ParamName]
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Pipe a real object
        # and assert the resolver received the bound values.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{ scope = '/subscriptions/sub-guid/resourceGroups/rg-net'; roleDefinitionId = 'rd1'; principalId = 'aaaa0000-0000-0000-0000-000000000001'; principalType = 'User'; requestType = 'AdminRemove'; status = 'Provisioned'; requestorId = 'aaaa0000-0000-0000-0000-000000000001'; expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
        }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $Rg | Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    It 'binds a piped resource-shaped object end to end, including -ResourceName and -ResourceType' {
        # Companion to the resource-group pipe test above: a real Omnicit.EntraRBAC.Resource object
        # (ConvertTo-OERResource.ps1) also carries ResourceName and ResourceType, and until now
        # nothing piped that shape -- only the ValueFromPipelineByPropertyName attribute was checked
        # by reflection, and the sibling "forwards -ResourceType/-ResourceName" It passes them as
        # explicit parameters, which never exercises pipeline binding either.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{ scope = '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1'; roleDefinitionId = 'rd1'; principalId = 'aaaa0000-0000-0000-0000-000000000001'; principalType = 'User'; requestType = 'AdminRemove'; status = 'Provisioned'; requestorId = 'aaaa0000-0000-0000-0000-000000000001'; expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'stg1' } } } }
        }

        $Resource = [PSCustomObject]@{
            SubscriptionId = 'sub-guid'
            ResourceGroup  = 'rg-net'
            ResourceName   = 'stg1'
            ResourceType   = 'Microsoft.Storage/storageAccounts'
        }
        $Resource | Remove-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stg1' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }

    Context 'principal guard (shared Resolve-OERPrincipalOrId)' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }

        It 'rejects a non-GUID -PrincipalId with InvalidPrincipalId and does not call ARM' {
            $Err = $null
            Remove-OERActiveRoleAssignment -PrincipalId 'anna@contoso.com' -Role 'Reader' `
                -Scope '/subscriptions/s1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            Should -Invoke Invoke-OERArmRequest -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'reports NoPrincipal when no principal is supplied' {
            $Err = $null
            Remove-OERActiveRoleAssignment -Role 'Reader' `
                -Scope '/subscriptions/s1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }

        It 'reports AmbiguousPrincipal when -User and -Group are both supplied' {
            $Err = $null
            Remove-OERActiveRoleAssignment -User 'anna@contoso.com' -Group 'Sales Team' -Role 'Reader' `
                -Scope '/subscriptions/s1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
        }
    }
}

Describe 'Remove-OERActiveRoleAssignment verbose output' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'; requestType = 'AdminRemove'; status = 'Provisioned'; requestorId = 'p1'; expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
        }
    }

    It 'reports the resolved scope, role and principal under -Verbose' {
        $Verbose = Remove-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[Remove-OERActiveRoleAssignment\] Target scope:'
        $Text | Should -Match "\[Remove-OERActiveRoleAssignment\] Resolved role 'Reader' to "
        $Text | Should -Match '\[Remove-OERActiveRoleAssignment\] Resolved principal to '
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Remove-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved role
        # definition id legitimately contains the 'Microsoft.Authorization' resource-provider
        # namespace, which is not a header or token leak. Assert against the actual header/token
        # shape instead ('Authorization:' with a colon, or the word 'bearer').
        $Text = (Remove-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Scope '/subscriptions/s1' -Confirm:$false -WarningAction SilentlyContinue -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'Remove-OERActiveRoleAssignment operator-facing principal label' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '99999999-9999-9999-9999-999999999999'; PrincipalType = 'Group' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ id = 'req1' } }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERRoleScheduleRequest { }
    }

    It 'names the group the operator typed, not the resolved GUID, in the warning' {
        $Warn = $null
        Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -Group 'RoleSec-Finance' -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        @($Warn | Where-Object { $_.Message -match 'RoleSec-Finance' }).Count | Should -Be 1
        @($Warn | Where-Object { $_.Message -match '99999999-9999' }).Count | Should -Be 0
    }

    It 'names the GUID, not the ignored friendly value, when BOTH are supplied' {
        # -PrincipalId and -User share a parameter set and Resolve-OERPrincipalOrId lets
        # -PrincipalId WIN, warning that the friendly value is ignored. A label that named the
        # ignored value would show the operator a destructive prompt for a principal that is not
        # the one about to be touched -- they approve one revocation and get another.
        $Warn = $null
        Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -PrincipalId '99999999-9999-9999-9999-999999999999' -User 'anna@contoso.com' `
            -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        $Destructive = @($Warn | Where-Object { $_.Message -notmatch 'takes precedence' })
        $Destructive.Count | Should -Be 1
        $Destructive[0].Message | Should -Match '99999999-9999-9999-9999-999999999999'
        $Destructive[0].Message | Should -Not -Match 'anna@contoso\.com'
    }

    It 'still warns that the friendly value is ignored when both are supplied' {
        $Warn = $null
        Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -PrincipalId '99999999-9999-9999-9999-999999999999' -User 'anna@contoso.com' `
            -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        @($Warn | Where-Object { $_.Message -match '-PrincipalId takes precedence' -and $_.Message -match '-User' }).Count |
            Should -Be 1
    }

    It 'falls back to the GUID when -PrincipalId was used' {
        $Warn = $null
        Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -PrincipalId '99999999-9999-9999-9999-999999999999' -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        @($Warn | Where-Object { $_.Message -match '99999999-9999-9999-9999-999999999999' }).Count | Should -Be 1
    }

    It 'still reports the resolved GUID under -Verbose so nothing is hidden' {
        $Verbose = Remove-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -Group 'RoleSec-Finance' -Confirm:$false -WarningAction SilentlyContinue -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        ($Verbose.Message -join "`n") | Should -Match "Resolved principal to '99999999-9999-9999-9999-999999999999'"
    }
}
