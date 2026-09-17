BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'New-OERActiveRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'request construction' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='p1'; principalType='User'
                    requestType='AdminAssign'; status='Provisioned'; requestorId='p1'
                    scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='NoExpiration' } }
                    expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'PUTs a roleAssignmentScheduleRequests request with AdminAssign and no principalType in the body' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -like '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/*`?api-version=2020-10-01' -and
                $Body.properties.requestType -eq 'AdminAssign' -and
                $Body.properties.roleDefinitionId -eq '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' -and
                $Body.properties.principalId -eq 'p1' -and
                -not $Body.properties.ContainsKey('principalType') -and
                $Body.properties.scheduleInfo.expiration.type -eq 'NoExpiration'
            }
        }
        It 'returns a tagged RoleScheduleRequest' {
            (New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Confirm:$false).PSObject.TypeNames[0] |
                Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
        }
        It 'honors -WhatIf (no ARM call)' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'defaults to NoExpiration (permanent) when no schedule param is given' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.type -eq 'NoExpiration'
            }
        }
        It 'converts -DurationDays to an AfterDuration ISO day duration' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 365 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.type -eq 'AfterDuration' -and
                $Body.properties.scheduleInfo.expiration.duration -eq 'P365D'
            }
        }
        It 'passes a raw ISO -Duration through unchanged' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Duration 'P6M' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.duration -eq 'P6M'
            }
        }
        It 'populates justification, ticketInfo, and condition when supplied' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent `
                -Justification 'audit-123' -TicketNumber 'T1' -TicketSystem 'Jira' -Condition "@Resource[x]" -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.justification -eq 'audit-123' -and
                $Body.properties.ticketInfo.ticketNumber -eq 'T1' -and
                $Body.properties.ticketInfo.ticketSystem -eq 'Jira' -and
                $Body.properties.condition -eq '@Resource[x]' -and
                $Body.properties.conditionVersion -eq '2.0'
            }
        }
        It 'accepts an explicit -ConditionVersion 2.0 (positive regression for the ValidateSet)' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent `
                -Condition "@Resource[x]" -ConditionVersion '2.0' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.conditionVersion -eq '2.0'
            }
        }
        It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
            }
        }

        It 'scrubs the bearer-hygiene record when the ARM PUT fails' {
            # CLAUDE.md SECURITY rule 6. Drives the transport catch at
            # source/Public/New-OERActiveRoleAssignment.ps1:219 -- the failed Invoke-WebRequest inside
            # Invoke-OERArmRequest carries the Authorization: Bearer header on its request object, so
            # Remove-OERErrorRecord -Record $PSItem must actually RUN, not merely be written. The static
            # AST gate proves placement; only this proves invocation. -DurationDays keeps the expiration
            # off NoExpiration so the permanent-policy self-heal block is skipped and the PUT catch is
            # the only catch that can fire.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $null = New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }
    }
    Context 'validation' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }
        It 'errors when no principal supplied' {
            New-OERActiveRoleAssignment -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
        }
        It 'errors when two principals supplied' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Group 'b' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousPrincipal'
        }
        It 'errors when -ConditionVersion is supplied without -Condition' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ConditionVersion '2.0' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'ConditionVersionWithoutCondition'
        }
        It 'rejects a condition version other than 2.0 (audit A-condition-version-no-validateset)' {
            $Threw = $false
            try {
                New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' `
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
        It 'errors with InvalidSchedule when conflicting schedule params are supplied' {
            # New-OERScheduleInfo throws on conflict; the cmdlet catches and re-routes it as
            # InvalidSchedule. -ErrorVariable also accumulates the nested terminating throw as it
            # unwinds, so assert the routed id appears among the captured errors (it is the last one).
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Duration 'P365D' -Permanent -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidSchedule'
        }
        It 'errors with AmbiguousDuration when both -Duration and -DurationDays are supplied' {
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Duration 'P365D' -DurationDays 30 -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousDuration'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command New-OERActiveRoleAssignment).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }
    It 'binds -ResourceName and -ResourceType from the pipeline by property name' {
        foreach ($ParamName in 'ResourceName', 'ResourceType') {
            $Param = (Get-Command New-OERActiveRoleAssignment).Parameters[$ParamName]
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
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/sub-guid/resourceGroups/rg-net'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
        }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $Rg | New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    It 'binds a piped resource-shaped object end to end, including -ResourceName and -ResourceType' {
        # Companion to the resource-group pipe test above: a real Omnicit.EntraRBAC.Resource object
        # (ConvertTo-OERResource.ps1) also carries ResourceName and ResourceType, and until now
        # nothing piped that shape -- only the ValueFromPipelineByPropertyName attribute was checked
        # by reflection, and the "forwards -ResourceType/-ResourceName" It above passes them as
        # explicit parameters, which never exercises pipeline binding either.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'stg1' } } } }
        }

        $Resource = [PSCustomObject]@{
            SubscriptionId = 'sub-guid'
            ResourceGroup  = 'rg-net'
            ResourceName   = 'stg1'
            ResourceType   = 'Microsoft.Storage/storageAccounts'
        }
        $Resource | New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stg1' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }

    Context 'permanent self-heal' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
            }
        }
        It 'opens the policy (active) then grants when permanent is forbidden' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -ParameterFilter {
                $PolicyId -eq '/pol1' -and $AllowPermanentActiveAssignment -eq $true
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }
        It 'does NOT open the policy when permanent active is already allowed' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
        It 'does NOT pre-check for a time-bound grant' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -DurationDays 365 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
        It 'errors PolicyOpenFailed and does NOT grant when opening fails' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { throw 'Forbidden' }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PolicyOpenFailed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'degrades and still grants when the pre-check read fails' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { throw 'read failed' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
    }

    Context 'PrincipalId pipeline binding (audit B-new-roleassignment-principal-not-pipeable)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000000' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/r1' }
            # A well-formed response, not the brief's bare @{ } -- ConvertTo-OERRoleScheduleRequest
            # indexes .PSObject.Properties['linkedRoleEligibilityScheduleId'] on .properties, which
            # throws "Cannot index into a null array" when .properties is absent (a hashtable with no
            # 'properties' key resolves that dot-access to $null, then the [...] indexer on $null
            # throws). A pre-existing converter quirk, unrelated to task 2 -- work around it in the
            # mock rather than touching the converter.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                        scope = '/subscriptions/00000000-0000-0000-0000-000000000000'; roleDefinitionId = 'rd1'; principalId = '33333333-3333-3333-3333-333333333333'; principalType = 'User'
                        requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'P1D' } }
                        expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
            }
        }

        It 'accepts a principal id from the pipeline (Eligible -> Active promotion)' {
            # Adapted from the brief's template test: New-OERActiveRoleAssignment has -DurationDays,
            # not -DurationHours, so -DurationDays 1 replaces the brief's -DurationHours 4 (that keeps
            # the schedule off NoExpiration, which would otherwise trigger the permanent-policy
            # pre-check and require an extra mock).
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
            $Eligible | New-OERActiveRoleAssignment -Subscription '00000000-0000-0000-0000-000000000000' `
                -Role 'Reader' -DurationDays 1 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly `
                -ParameterFilter { $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333' }
        }

        It 'binds -PrincipalId as a pipeline-by-property-name parameter (attribute check)' {
            $Param = (Get-Command New-OERActiveRoleAssignment).Parameters['PrincipalId']
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
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
            $Sub = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERSubscription -InputObject @{
                    id             = '/subscriptions/00000000-0000-0000-0000-000000000000'
                    subscriptionId = '00000000-0000-0000-0000-000000000000'
                    displayName    = 'Prod'
                    state          = 'Enabled'
                }
            }
            $Sub | New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
            # Positive half: a not-X-only assertion would also pass if the pipe silently failed for
            # an unrelated reason. Prove it actually reached the ARM call.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.principalId -eq 'p1'
            }
        }

        It 'errors with InvalidPrincipalId when -PrincipalId is not a GUID' {
            New-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'not-a-guid' -Subscription '00000000-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId,New-OERActiveRoleAssignment'
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
            # the cheap local -ConditionVersion/-Duration checks but still BEFORE Resolve-OERScope. So
            # a call with both a bad scope and an unresolvable principal now reports PrincipalNotFound,
            # not InvalidScope, and Resolve-OERScope is never even invoked. Pinned here per the task-2
            # brief. -ErrorVariable also accumulates the nested terminating throw from inside
            # Resolve-OERPrincipal as it unwinds (a PowerShell quirk, not a bug -- see CLAUDE.md), so
            # assert presence across all captured records rather than position $e[0].
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            New-OERActiveRoleAssignment -Role 'Reader' -User 'ghost@contoso.com' -Subscription 'not-a-real-sub' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PrincipalNotFound,New-OERActiveRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0 -Exactly
        }
    }
}

Describe 'New-OERActiveRoleAssignment verbose output' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'P30D' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } }
                }
            }
        }
    }

    It 'reports the resolved scope, role and principal under -Verbose' {
        $Verbose = New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[New-OERActiveRoleAssignment\] Target scope:'
        $Text | Should -Match "\[New-OERActiveRoleAssignment\] Resolved role 'Reader' to "
        $Text | Should -Match '\[New-OERActiveRoleAssignment\] Resolved principal to '
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved role
        # definition id legitimately contains the 'Microsoft.Authorization' resource-provider
        # namespace, which is not a header or token leak. Assert against the actual header/token
        # shape instead ('Authorization:' with a colon, or the word 'bearer').
        $Text = (New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'New-OERActiveRoleAssignment piped principal ambiguity guard' {
    <#
        Whole-branch review finding I-1, same guard as New-OERRoleAssignment. Task 2 made
        -PrincipalId ValueFromPipelineByPropertyName and Resolve-OERPrincipalOrId gives it precedence
        over -User/-Group/-ServicePrincipal, so piping assignment-shaped objects (all of which carry
        their own PrincipalId) alongside a named principal silently granted the role to each piped
        item's own principal instead. Refused as AmbiguousPrincipal, per the PR #26 precedent in
        Remove-OERGroupEligibility and Remove-OERAdministrativeUnitScopedRole.

        The guard additionally requires the PIPED ITEM to carry a PrincipalId: this cmdlet's pipeline
        also carries role definitions and scope-defining objects, and pairing one of those with a
        named principal is legitimate and documented.
    #>
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'friendly-principal'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; PermanentAllowed = $true } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{ scope = '/subscriptions/s1' } }
        }
    }

    It 'errors AmbiguousPrincipal and issues no ARM call when -Group is bound alongside a piped active assignment' {
        # Built by the REAL converter so the piped shape cannot drift from what the module emits.
        $Active = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERActiveRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignmentSchedules/a1'
                name       = 'a1'
                properties = @{
                    principalId      = '55555555-5555-5555-5555-555555555555'
                    principalType    = 'User'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Active | New-OERActiveRoleAssignment -Role 'Reader' -Group 'role_sec_ops' `
            -Scope '/subscriptions/s1' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,New-OERActiveRoleAssignment'
        $Err[0].Exception.Message | Should -BeLike '*55555555-5555-5555-5555-555555555555*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'still binds the piped PrincipalId when no friendly parameter is supplied (Task 2 capability regression)' {
        $Active = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERActiveRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignmentSchedules/a1'
                name       = 'a1'
                properties = @{
                    principalId      = '55555555-5555-5555-5555-555555555555'
                    principalType    = 'User'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Active | New-OERActiveRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '55555555-5555-5555-5555-555555555555'
        }
    }

    It 'only WARNS for a direct call supplying both -PrincipalId and -Group: the guard is pipe-only' {
        $Err = $null
        $Warnings = New-OERActiveRoleAssignment -Role 'Reader' `
            -PrincipalId '55555555-5555-5555-5555-555555555555' -Group 'role_sec_ops' `
            -Scope '/subscriptions/s1' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        ($Warnings.Message -join "`n") | Should -Match '-PrincipalId takes precedence'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '55555555-5555-5555-5555-555555555555'
        }
    }
}
