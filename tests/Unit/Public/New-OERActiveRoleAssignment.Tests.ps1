BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    Context 'permanent self-heal is gated on the grant decision (BL-80)' {
        # The policy pre-check is a READ and its warning comes before the confirmation prompt; the
        # policy WRITE comes only once the assignment is confirmed (or planned under -WhatIf).
        # $script:Order records the policy writes and the PUT in the order they are sent.
        BeforeEach {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState {
                [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false }
            }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentActiveAssignment) { $script:Order.Add('open') } else { $script:Order.Add('rollback') }
                [PSCustomObject]@{ PolicyId = 'pol-1' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                $script:Order.Add('grant')
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                        scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                        requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                        expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
            }
            $script:Grant = @{ Role = 'Reader'; Subscription = 'Prod'; User = 'anna@contoso.com'; Permanent = $true }
            $script:OpenedText = "The active role assignment failed after role management policy 'pol-1' had been opened to allow permanent assignments."
            $script:RefusedText = ' The request failed with: ARM rejected the request'
        }
        BeforeAll {
            # -ErrorVariable also collects every record the mock layers raise as the refused PUT
            # unwinds; the cmdlet's OWN records are the ones that carry its name, in the order written.
            function Get-TestOwnRecord ($Records) {
                @($Records | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OERActiveRoleAssignment' })
            }
        }

        It 'makes NO policy change and sends nothing when the operator genuinely declines the confirmation prompt' {
            # The decline is the state this guard exists for, and it is the one state an in-process
            # Pester construct cannot produce: -Confirm:$false confirms, and -WhatIf sets
            # $WhatIfPreference. So run the cmdlet twice in an answering runspace (see
            # tests/Unit/TestHelpers/OERConfirmHost.ps1) -- once answering Yes, which proves the
            # harness really reaches the code, and once answering No.
            $Scenario = {
                Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                $Module = Get-Module Omnicit.EntraRBAC
                & $Module {
                    $script:OERTestCalls = [System.Collections.Generic.List[string]]::new()
                    Set-Item -Path function:script:Initialize-OERAuth -Value { }
                    Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
                    Set-Item -Path function:script:Resolve-OERPrincipal -Value { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
                    Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
                    Set-Item -Path function:script:Get-OERPermanentPolicyState -Value { [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false } }
                    Set-Item -Path function:script:Set-OERRoleManagementPolicy -Value { $script:OERTestCalls.Add('open'); [PSCustomObject]@{ PolicyId = 'pol-1' } }
                    Set-Item -Path function:script:Invoke-OERArmRequest -Value { $script:OERTestCalls.Add('grant') }
                    Set-Item -Path function:script:ConvertTo-OERRoleScheduleRequest -Value { }
                }
                New-OERActiveRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm | Out-Null
                & $Module { "CALLS:$($script:OERTestCalls -join ',')" }
            }
            $Accepted = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
            $Declined = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            $Accepted.Output[-1] | Should -Be 'CALLS:open,grant'
            $Declined.Output[-1] | Should -Be 'CALLS:'
            # The decline was given at the assignment's own prompt, and the operator was warned first.
            @($Declined.Prompts).Count | Should -Be 1
            $Declined.Prompts[0] | Should -BeLike "*active role 'Reader' for User 'anna@contoso.com' at scope '/subscriptions/s1'*"
            ($Declined.Warnings -join ' ') | Should -BeLike '*requires opening the role management policy*affects ALL active assignments for this role at this scope*'
        }

        It 'reaches no policy write except through the grant decision' {
            # Backstop for the behavioural test above, and the only guard that survives if the
            # answering-runspace harness is ever removed: every call that WRITES the policy must sit
            # under an if whose condition reads $Proceed, and must come after the gate is evaluated.
            $FunctionAst = (Get-Command New-OERActiveRoleAssignment).ScriptBlock.Ast
            $GateOffset = $FunctionAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'ShouldProcess'
                }, $true) | ForEach-Object { $_.Extent.StartOffset } | Sort-Object | Select-Object -First 1
            $WriteCalls = @($FunctionAst.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and
                        $Node.GetCommandName() -eq 'Set-OERRoleManagementPolicy'
                    }, $true))

            $GateOffset | Should -Not -BeNullOrEmpty
            # The open and the rollback.
            $WriteCalls.Count | Should -Be 2
            foreach ($Call in $WriteCalls) {
                $Call.Extent.StartOffset | Should -BeGreaterThan $GateOffset
                $Gated = $false
                $Node = $Call.Parent
                while ($null -ne $Node) {
                    if ($Node -is [System.Management.Automation.Language.IfStatementAst]) {
                        foreach ($Clause in $Node.Clauses) {
                            $Referenced = @($Clause.Item1.FindAll({
                                        param($Inner)
                                        $Inner -is [System.Management.Automation.Language.VariableExpressionAst] -and
                                        $Inner.VariablePath.UserPath -eq 'Proceed'
                                    }, $true))
                            if ($Referenced.Count -gt 0) { $Gated = $true }
                        }
                    }
                    $Node = $Node.Parent
                }
                $Gated | Should -BeTrue -Because 'every policy write must be enclosed by an if whose condition reads the gate decision'
            }
        }

        It 'warns about the blast radius BEFORE the operator is asked, and opens before granting' {
            $Warnings = New-OERActiveRoleAssignment @script:Grant -Confirm:$false 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL active assignments for this role at this scope*'
            # The warning precedes the decision, so it must describe what the assignment REQUIRES,
            # never claim the policy has already been opened.
            ($Warnings.Message -join ' ') | Should -BeLike '*requires opening the role management policy*'
            $script:Order -join ',' | Should -Be 'open,grant'
            # And it is written before the gate is evaluated, not merely outside the if it reads.
            $FunctionAst = (Get-Command New-OERActiveRoleAssignment).ScriptBlock.Ast
            $GateOffset = $FunctionAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'ShouldProcess'
                }, $true) | ForEach-Object { $_.Extent.StartOffset } | Sort-Object | Select-Object -First 1
            $WarningCall = @($FunctionAst.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and
                        $Node.GetCommandName() -eq 'Write-Warning' -and $Node.Extent.Text -like '*requires opening the role management policy*'
                    }, $true))
            $WarningCall.Count | Should -Be 1
            $WarningCall[0].Extent.StartOffset | Should -BeLessThan $GateOffset
        }

        It 'STILL plans the policy open under -WhatIf, exactly once, and sends no grant' {
            $Warnings = New-OERActiveRoleAssignment @script:Grant -WhatIf 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            # The real Set-OERRoleManagementPolicy is self-gating and prints its own plan line; the
            # mock stands in for it, so the plan is the call it receives.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'pol-1' -and $AllowPermanentActiveAssignment -eq $true
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
            $script:Order -join ',' | Should -Be 'open'
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL active assignments for this role at this scope*'
        }

        It 'rolls the policy back FIRST when the grant is refused, then writes PolicyOpenedButGrantFailed, then the grant''s own error' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:Order.Add('grant'); throw 'ARM rejected the request' }
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment @script:Grant -Confirm:$false -WarningAction SilentlyContinue `
                    -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            $script:Order -join ',' | Should -Be 'open,grant,rollback'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'pol-1' -and $AllowPermanentActiveAssignment -eq $false
            }
            # The cmdlet's own records, in the order written: PolicyOpenedButGrantFailed first, then the
            # grant's own record, re-published unchanged.
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 2
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OERActiveRoleAssignment'
            $Own[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $Own[0].TargetObject | Should -BeExactly 'pol-1'
            $Own[0].Exception.Message | Should -BeExactly ($script:OpenedText + ' It was rolled back to disallow permanent assignments.' + $script:RefusedText)
            $Own[1].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OERActiveRoleAssignment'
            $Own[1].Exception.Message | Should -BeExactly 'ARM rejected the request'
        }

        It 'still rolls back under -ErrorAction Stop, and the error that stops the caller is PolicyOpenedButGrantFailed' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:Order.Add('grant'); throw 'ARM rejected the request' }
            $Thrown = $null
            try {
                New-OERActiveRoleAssignment @script:Grant -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
            } catch {
                $script:Order.Add('error')
                $Thrown = $PSItem
            }
            $script:Order -join ',' | Should -Be 'open,grant,rollback,error'
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OERActiveRoleAssignment'
            $Thrown.Exception.Message | Should -BeExactly ($script:OpenedText + ' It was rolled back to disallow permanent assignments.' + $script:RefusedText)
        }

        It 'names the policy left open, and how to close it, and scrubs both records when the rollback ALSO fails' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:Order.Add('grant'); throw 'ARM rejected the request' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentActiveAssignment) { $script:Order.Add('open'); return [PSCustomObject]@{ PolicyId = 'pol-1' } }
                $script:Order.Add('rollback')
                throw 'rollback forbidden'
            }
            $Err = $null
            New-OERActiveRoleAssignment @script:Grant -Confirm:$false -WarningAction SilentlyContinue `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $script:Order -join ',' | Should -Be 'open,grant,rollback'
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 2
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OERActiveRoleAssignment'
            $Own[0].Exception.Message | Should -BeExactly ($script:OpenedText +
                " The rollback ALSO failed, so the policy is still open. Run 'Set-OERRoleManagementPolicy -PolicyId ''pol-1'' " +
                "-AllowPermanentActiveAssignment `$false' to close it." + $script:RefusedText)
            $Own[1].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OERActiveRoleAssignment'
            # The refused grant's record and the failed rollback's record.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 2 -Exactly
        }

        It 'neither rolls back nor reports PolicyOpenedButGrantFailed when the nested open was DECLINED, and still writes the grant''s own error' {
            # Under an explicit -Confirm the propagated $ConfirmPreference makes the self-gating
            # Set-OERRoleManagementPolicy prompt on its own, and answering No emits NOTHING having
            # written nothing. A later grant failure must neither name that policy nor try to revert
            # a write that never happened.
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { if ($AllowPermanentActiveAssignment) { $script:Order.Add('asked') } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:Order.Add('grant'); throw 'ARM rejected the request' }
            $Err = $null
            New-OERActiveRoleAssignment @script:Grant -Confirm:$false -WarningAction SilentlyContinue `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $script:Order -join ',' | Should -Be 'asked,grant'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $AllowPermanentActiveAssignment -eq $true }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $AllowPermanentActiveAssignment -eq $false }
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OERActiveRoleAssignment'
        }

        It 'writes only the grant''s own error, and rolls nothing back, when a refused grant follows no open (<Case>)' -ForEach @(
            @{ Case = 'time-bound'; Schedule = @{ DurationDays = 30 }; Expected = 'grant' }
            @{ Case = 'permanent already allowed'; Schedule = @{ Permanent = $true }; Expected = 'grant'; Allowed = $true }
        ) {
            if ($Allowed) {
                Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState {
                    [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true }
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:Order.Add('grant'); throw 'ARM rejected the request' }
            $Err = $null
            New-OERActiveRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' @Schedule -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            # The PUT was sent and refused, so the missing rollback below is a decision.
            $script:Order -join ',' | Should -Be $Expected
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OERActiveRoleAssignment'
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

    Context 'a request Azure Resource Manager accepts but answers with a status in the Failed family (BL-33)' {
        # ARM can accept the AdminAssign request and answer it with status Failed (or another value of
        # the Failed family, such as FailedAsResourceIsLocked), which grants nothing. The cmdlet still
        # emits the request object, then writes AssignmentRequestFailed. Time-bound, so no policy is
        # read or opened.
        BeforeEach {
            $script:AnsweredStatus = 'Failed'
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{
                    id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/req-f1'
                    name       = 'req-f1'
                    properties = [PSCustomObject]@{
                        scope = '/subscriptions/s1'; roleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                        principalId = 'aaaa0000-0000-0000-0000-000000000001'; principalType = 'User'; requestType = 'AdminAssign'
                        status = $script:AnsweredStatus
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'P30D' } }
                    }
                }
            }
        }

        It 'emits the request object AND writes exactly one AssignmentRequestFailed when ARM answers status <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'FAILED' }
            @{ Status = 'FailedAsResourceIsLocked' }
        ) {
            $script:AnsweredStatus = $Status
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' `
                    -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
            $Out[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Err[0].TargetObject | Should -BeExactly '/subscriptions/s1'
            $Err[0].Exception.Message | Should -BeExactly ("Azure Resource Manager accepted the active role assignment request 'req-f1' " +
                "(AdminAssign) of role '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' for principal " +
                "'aaaa0000-0000-0000-0000-000000000001' at scope '/subscriptions/s1' but answered status $Status, so nothing was granted.")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'still hands the object to -OutVariable under -ErrorAction Stop, and the throw carries AssignmentRequestFailed' {
            $Out = $null
            $Thrown = $null
            try {
                New-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' `
                    -DurationDays 30 -Confirm:$false -ErrorAction Stop -OutVariable Out | Out-Null
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            @($Out).Count | Should -Be 1
            $Out[0].Name | Should -BeExactly 'req-f1'
            $Out[0].Status | Should -BeExactly 'Failed'
        }

        It 'writes no error for status <Status>, and still emits the object' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'PendingApproval' }
        ) {
            $script:AnsweredStatus = $Status
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment -Role 'Reader' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' `
                    -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The request was sent and answered with this status, so the absence below is a decision.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
            $Out.Count | Should -Be 1
            $Out[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 0
        }
    }

    Context 'a Failed answer after this invocation opened the role management policy (BL-33, BL-80, Rulings R4 and R8)' {
        # A Failed answer granted nothing, so a policy this invocation opened for the permanent grant
        # is rolled back -- before the object is emitted, so neither -ErrorAction Stop nor a consumer
        # that stops the pipeline can skip it -- and the one AssignmentRequestFailed record carries the
        # rollback text. $script:Order records the policy writes and the PUT; the tests add the emitted
        # object and the stop as they see them.
        BeforeEach {
            $script:AnsweredStatus = 'Failed'
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState {
                [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false }
            }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentActiveAssignment) { $script:Order.Add('open') } else { $script:Order.Add('rollback') }
                [PSCustomObject]@{ PolicyId = 'pol-1' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                $script:Order.Add('grant')
                [PSCustomObject]@{
                    id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/req-f1'
                    name       = 'req-f1'
                    properties = [PSCustomObject]@{
                        scope = '/subscriptions/s1'; roleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                        principalId = 'p1'; principalType = 'User'; requestType = 'AdminAssign'; status = $script:AnsweredStatus
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    }
                }
            }
            $script:FailedMessage = "Azure Resource Manager accepted the active role assignment request 'req-f1' (AdminAssign) of role " +
                "'/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' for principal 'p1' at scope '/subscriptions/s1' " +
                'but answered status Failed, so nothing was granted.'
            $script:OpenedText = " Role management policy 'pol-1' had been opened to allow permanent assignments before the request was sent."
            $script:Grant = @{ Role = 'Reader'; Subscription = 'Prod'; User = 'anna@contoso.com'; Permanent = $true; Confirm = $false; WarningAction = 'SilentlyContinue' }
        }

        It 'rolls back the policy this invocation opened BEFORE the object and the error, and writes one record with the rollback text' {
            $Err = $null
            New-OERActiveRoleAssignment @script:Grant -ErrorAction SilentlyContinue -ErrorVariable Err |
                ForEach-Object { $script:Order.Add("emit:$($_.Status)") }
            $script:Order -join ',' | Should -Be 'open,grant,rollback,emit:Failed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'pol-1' -and $AllowPermanentActiveAssignment -eq $false
            }
            # One record, AssignmentRequestFailed: the request was accepted, not refused, so this is
            # not PolicyOpenedButGrantFailed, but it carries the same rollback text.
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Err[0].TargetObject | Should -BeExactly '/subscriptions/s1'
            $Err[0].Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                ' It was rolled back to disallow permanent assignments.')
        }

        It 'names the policy left open, and how to close it, when the rollback after a Failed answer ALSO fails' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentActiveAssignment) { $script:Order.Add('open'); return [PSCustomObject]@{ PolicyId = 'pol-1' } }
                $script:Order.Add('rollback')
                throw 'rollback forbidden'
            }
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment @script:Grant -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $script:Order -join ',' | Should -Be 'open,grant,rollback'
            $Reported = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OERActiveRoleAssignment' })
            $Reported.Count | Should -Be 1
            $Reported[0].FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            $Reported[0].Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                " The rollback ALSO failed, so the policy is still open. Run 'Set-OERRoleManagementPolicy -PolicyId ''pol-1'' " +
                "-AllowPermanentActiveAssignment `$false' to close it.")
            # The failed rollback's record is scrubbed, as on the refused-grant path.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'neither rolls back nor names the policy when the nested open was DECLINED' {
            # A declined self-gating open emits nothing having written nothing, so this invocation
            # opened nothing: a Failed answer must not revert, or name, a write that never happened.
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { if ($AllowPermanentActiveAssignment) { $script:Order.Add('asked') } }
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment @script:Grant -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $script:Order -join ',' | Should -Be 'asked,grant'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $AllowPermanentActiveAssignment -eq $true }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $AllowPermanentActiveAssignment -eq $false }
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            $Err[0].Exception.Message | Should -BeExactly $script:FailedMessage
        }

        It 'still rolls back under -ErrorAction Stop, before the object reaches -OutVariable and the throw stops the caller' {
            $Out = $null
            $Thrown = $null
            try {
                New-OERActiveRoleAssignment @script:Grant -ErrorAction Stop -OutVariable Out |
                    ForEach-Object { $script:Order.Add("emit:$($_.Status)") }
            } catch {
                $script:Order.Add('error')
                $Thrown = $PSItem
            }
            $script:Order -join ',' | Should -Be 'open,grant,rollback,emit:Failed,error'
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'AssignmentRequestFailed,New-OERActiveRoleAssignment'
            $Thrown.Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                ' It was rolled back to disallow permanent assignments.')
            @($Out).Count | Should -Be 1
            $Out[0].Status | Should -BeExactly 'Failed'
        }

        It 'does not roll back an opened policy when the permanent grant is answered Provisioned' {
            $script:AnsweredStatus = 'Provisioned'
            $Err = $null
            $Out = @(New-OERActiveRoleAssignment @script:Grant -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The policy was opened and the grant sent, so the missing rollback below is a decision.
            $script:Order -join ',' | Should -Be 'open,grant'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $AllowPermanentActiveAssignment -eq $false }
            $Out.Count | Should -Be 1
            $Out[0].Status | Should -BeExactly 'Provisioned'
            @($Err).Count | Should -Be 0
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

Describe 'New-OERActiveRoleAssignment: the policy open and its rollback in a script with no try (BL-80, Ruling R7)' {
    # Two shapes that must hold where no try stands anywhere up the call stack, as at a prompt. A
    # declined permanent grant reaches the end of the script having opened no policy and sent no PUT.
    # A refused grant after an open, under -ErrorAction Stop, rolls the policy back BEFORE the first
    # error stops the script, and that error is PolicyOpenedButGrantFailed. The script runs in a
    # runspace through Invoke-OERWithConfirmAnswer, so it is transported as text and installs its own
    # fakes in ITS copy of the module scope; they append every policy write and PUT to a log file
    # whose path is substituted into the text, since a stopped script prints nothing. Each shape has a
    # control in the same script with the same fakes. The log is written with AppendAllText, never
    # Add-Content: under -Confirm the fakes inherit $ConfirmPreference, so Add-Content would prompt on
    # its own and a declined run would decline the log line too (measured).
    BeforeAll {
        $script:NewNoTryScenario = {
            param([string]$Log, [string]$Grant, [string]$Call)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
    Set-Item -Path function:script:Resolve-OERPrincipal -Value { [pscustomobject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
    Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
    Set-Item -Path function:script:Get-OERPermanentPolicyState -Value {
        [pscustomobject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $false }
    }
    Set-Item -Path function:script:Set-OERRoleManagementPolicy -Value {
        [CmdletBinding()]
        param([string]$PolicyId, [bool]$AllowPermanentActiveAssignment)
        [System.IO.File]::AppendAllText('#LOG#', "$(if ($AllowPermanentActiveAssignment) { 'open' } else { 'rollback' })`n")
        [pscustomobject]@{ PolicyId = $PolicyId }
    }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body)
        [System.IO.File]::AppendAllText('#LOG#', "grant $Method`n")
        #GRANT#
    }
}
#CALL#
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#GRANT#', $Grant).Replace('#CALL#', $Call))
        }
        $script:Provisioned = @'
[pscustomobject]@{ id = 'req-1'; name = 'req-1'; properties = [pscustomobject]@{
        scope = '/subscriptions/s1'; roleDefinitionId = $Body.properties.roleDefinitionId; principalId = $Body.properties.principalId
        principalType = 'User'; requestType = 'AdminAssign'; status = 'Provisioned'
        scheduleInfo = [pscustomobject]@{ startDateTime = 't'; expiration = [pscustomobject]@{ type = 'NoExpiration' } } } }
'@
        $script:Refused = "throw 'ARM rejected the request'"
        $script:DeclinableCall = @'
$Result = New-OERActiveRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm -WarningAction SilentlyContinue
"REACHED:$(@($Result).Count)"
'@
        $script:RefusedCall = @'
$Result = New-OERActiveRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false -WarningAction SilentlyContinue #STOP#
"REACHED:$(@($Result).Count)"
'@
        $script:PolicyOpenedButGrantFailedText = "The active role assignment failed after role management policy 'pol-1' had been opened " +
            'to allow permanent assignments. It was rolled back to disallow permanent assignments. The request failed with: ARM rejected the request'
        function Get-TestLoggedLine ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'a declined permanent grant reaches the end of the script, opens no policy and sends no PUT' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Grant $script:Provisioned -Call $script:DeclinableCall
        $Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        @(Get-TestLoggedLine -Log $Log).Count | Should -Be 0
        # The one prompt was the assignment's own, and it was answered No.
        @($Run.Prompts).Count | Should -Be 1
        $Run.Prompts[0] | Should -BeLike "*active role 'Reader' for User 'anna@contoso.com' at scope '/subscriptions/s1'*"
        @($Run.Errors).Count | Should -Be 0
    }

    It 'the control: the same script, accepted, opens the policy, sends the PUT and reaches the end' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Grant $script:Provisioned -Call $script:DeclinableCall
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|END'
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT')
        # The same one prompt, so the declined run above was asked exactly what this run accepted.
        @($Run.Prompts).Count | Should -Be 1
        @($Run.Errors).Count | Should -Be 0
    }

    It 'a refused grant after an open, under -ErrorAction Stop, rolls the policy back before PolicyOpenedButGrantFailed ends the script' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Grant $script:Refused -Call $script:RefusedCall.Replace('#STOP#', '-ErrorAction Stop')
        # Measured: a stop outside any try ends the whole script, so the runner throws to its caller.
        $Thrown = { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } | Should -Throw -PassThru
        $Thrown.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
        $Thrown.Exception.InnerException.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OERActiveRoleAssignment'
        $Thrown.Exception.InnerException.ErrorRecord.Exception.Message | Should -BeExactly $script:PolicyOpenedButGrantFailedText
        # The rollback was sent before that error stopped the script, and nothing after it.
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT', 'rollback')
    }

    It 'the control: without Stop the same script reaches the end, PolicyOpenedButGrantFailed written before the grant''s own error' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Grant $script:Refused -Call $script:RefusedCall.Replace('#STOP#', '')
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT', 'rollback')
        @($Run.Errors) | Should -Be @($script:PolicyOpenedButGrantFailedText, 'ARM rejected the request')
    }
}
