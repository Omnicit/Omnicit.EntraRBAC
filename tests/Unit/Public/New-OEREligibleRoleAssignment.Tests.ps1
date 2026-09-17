BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

Describe 'New-OEREligibleRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'request construction' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='p1'; principalType='User'
                    requestType='AdminAssign'; status='Provisioned'; requestorId='p1'
                    scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='NoExpiration' } }
                    expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'PUTs a roleEligibilityScheduleRequests request with AdminAssign and no principalType in the body' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -like '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/*`?api-version=2020-10-01' -and
                $Body.properties.requestType -eq 'AdminAssign' -and
                $Body.properties.roleDefinitionId -eq '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' -and
                $Body.properties.principalId -eq 'p1' -and
                -not $Body.properties.ContainsKey('principalType') -and
                $Body.properties.scheduleInfo.expiration.type -eq 'NoExpiration'
            }
        }
        It 'returns a tagged RoleScheduleRequest' {
            (New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Confirm:$false).PSObject.TypeNames[0] |
                Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
        }
        It 'honors -WhatIf (no ARM call)' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'defaults to NoExpiration (permanent) when no schedule param is given' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.type -eq 'NoExpiration'
            }
        }
        It 'populates justification, ticketInfo, and condition when supplied' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent `
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
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Permanent `
                -Condition "@Resource[x]" -ConditionVersion '2.0' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Body.properties.conditionVersion -eq '2.0'
            }
        }
        It 'converts -DurationDays to an AfterDuration ISO day duration' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 365 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.type -eq 'AfterDuration' -and
                $Body.properties.scheduleInfo.expiration.duration -eq 'P365D'
            }
        }
        It 'passes a raw ISO -Duration through unchanged' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -Duration 'P6M' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.duration -eq 'P6M'
            }
        }
        It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
            }
        }
    }
    Context 'validation' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }
        It 'errors when no principal supplied' {
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
        }
        It 'errors when two principals supplied' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Group 'b' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousPrincipal'
        }
        It 'errors when -ConditionVersion is supplied without -Condition' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -ConditionVersion '2.0' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'ConditionVersionWithoutCondition'
        }
        It 'rejects a condition version other than 2.0 (audit A-condition-version-no-validateset)' {
            $Threw = $false
            try {
                New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' `
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
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Duration 'P365D' -Permanent -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidSchedule'
        }
        It 'errors with AmbiguousDuration when both -Duration and -DurationDays are supplied' {
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Duration 'P365D' -DurationDays 30 -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousDuration'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }

    Context 'pipeline binding: Subscription object binds SubscriptionId to scope' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000060' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/00000000-0000-0000-0000-000000000060'; roleDefinitionId = 'rd1'
                    principalId = 'p1'; principalType = 'User'; requestType = 'AdminAssign'; status = 'Provisioned'
                    requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } }
                } }
            }
        }
        It 'pipes a Subscription object and binds SubscriptionId to Resolve-OERScope' {
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/00000000-0000-0000-0000-000000000060'
                SubscriptionId = '00000000-0000-0000-0000-000000000060'
                DisplayName    = 'Prod'
                State          = 'Enabled'
            }
            $Sub.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
            $Sub | New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $Subscription -eq '00000000-0000-0000-0000-000000000060'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
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
        It 'opens the policy then grants when permanent is forbidden' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -ParameterFilter {
                $PolicyId -eq '/pol1' -and $AllowPermanentEligibility -eq $true
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }
        It 'does NOT open the policy when permanent is already allowed' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $true } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
        It 'does NOT pre-check for a time-bound grant' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { }
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -DurationDays 365 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
        It 'errors PolicyOpenFailed and does NOT grant when opening fails' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false } }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { throw 'Forbidden' }
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PolicyOpenFailed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'degrades and still grants when the pre-check read fails' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { throw 'read failed' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'a' -Subscription 'Prod' -Permanent -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1
        }
    }

    Context 'permanent self-heal is gated on the grant decision' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState {
                [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false }
            }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'pol-1' } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                        scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                        requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                        expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
            }
        }

        It 'makes NO policy change when the operator genuinely declines the confirmation prompt' {
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
                    Set-Item -Path function:script:Get-OERPermanentPolicyState -Value { [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false } }
                    Set-Item -Path function:script:Set-OERRoleManagementPolicy -Value { $script:OERTestCalls.Add('open'); [PSCustomObject]@{ PolicyId = 'pol-1' } }
                    Set-Item -Path function:script:Invoke-OERArmRequest -Value { $script:OERTestCalls.Add('grant') }
                    Set-Item -Path function:script:ConvertTo-OERRoleScheduleRequest -Value { }
                }
                New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm | Out-Null
                & $Module { "CALLS:$($script:OERTestCalls -join ',')" }
            }
            $Accepted = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
            $Declined = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            $Accepted.Output[-1] | Should -Be 'CALLS:open,grant'
            $Declined.Output[-1] | Should -Be 'CALLS:'
            ($Declined.Warnings -join ' ') | Should -BeLike '*affects ALL eligible assignments for this role at this scope*'
        }

        It 'reaches no policy write except through the grant decision' {
            # Backstop for the behavioural test above, and the only guard that survives if the
            # answering-runspace harness is ever removed: every call that WRITES the policy must sit
            # under an if whose condition reads $Proceed, and must come after the gate is evaluated.
            $FunctionAst = (Get-Command New-OEREligibleRoleAssignment).ScriptBlock.Ast
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
            $WriteCalls.Count | Should -BeGreaterThan 0
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
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { $Order.Add('open'); [PSCustomObject]@{ PolicyId = 'pol-1' } }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $Order.Add('grant'); [PSCustomObject]@{ id = 'req-1'; properties = [PSCustomObject]@{ status = 'Provisioned' } } }
            $Warnings = New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL eligible assignments for this role at this scope*'
            # The warning precedes the decision, so it must describe what the assignment REQUIRES,
            # never claim the policy has already been opened.
            ($Warnings.Message -join ' ') | Should -BeLike '*requires opening the role management policy*'
            $Order -join ',' | Should -Be 'open,grant'
        }

        It 'STILL shows the policy open in the -WhatIf plan (PR #19 behaviour must not regress)' {
            $Warnings = New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -WhatIf 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL eligible assignments for this role at this scope*'
        }

        It 'rolls the policy back and reports PolicyOpenedButGrantFailed when the grant fails' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'ARM rejected the request' }
            $Reverts = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -ParameterFilter {
                $AllowPermanentEligibility -eq $false
            } -MockWith { $Reverts.Add($PolicyId) }
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Reverts) | Should -Contain 'pol-1'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment' }).Count |
                Should -Be 1
        }

        It 'names the policy left open and scrubs the bearer record when the rollback ALSO fails' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'ARM rejected the request' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -ParameterFilter {
                $AllowPermanentEligibility -eq $false
            } -MockWith { throw 'rollback forbidden' }
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -BeLike '*rollback ALSO failed*'
            $Reported[0].Exception.Message | Should -BeLike '*pol-1*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 2
        }

        It 'neither reports PolicyOpenedButGrantFailed nor rolls back when the nested open was DECLINED' {
            # Under an explicit -Confirm the propagated $ConfirmPreference makes the self-gating
            # Set-OERRoleManagementPolicy prompt on its own, and answering No emits NOTHING having
            # written nothing. A later grant failure must neither name that policy nor try to revert
            # a write that never happened.
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'ARM rejected the request' }
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -ParameterFilter {
                $AllowPermanentEligibility -eq $true
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter {
                $AllowPermanentEligibility -eq $false
            }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment' }).Count |
                Should -Be 0
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

        It 'accepts a principal id from the pipeline (a prior grant''s object id feeds a new one)' {
            # Adapted from the brief's template test: -DurationDays 1 keeps the schedule off
            # NoExpiration so the permanent-policy pre-check is skipped and no extra mock is needed.
            $Prior = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OEREligibleRoleAssignment -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleEligibilitySchedules/e1'
                    properties = @{
                        principalId      = '33333333-3333-3333-3333-333333333333'
                        roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/r1'
                        scope            = '/subscriptions/s'
                    }
                }
            }
            $Prior | New-OEREligibleRoleAssignment -Subscription '00000000-0000-0000-0000-000000000000' `
                -Role 'Reader' -DurationDays 1 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly `
                -ParameterFilter { $Body.properties.principalId -eq '33333333-3333-3333-3333-333333333333' }
        }

        It 'binds -PrincipalId as a pipeline-by-property-name parameter (attribute check)' {
            $Param = (Get-Command New-OEREligibleRoleAssignment).Parameters['PrincipalId']
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
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $true } }
            $Sub = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERSubscription -InputObject @{
                    id             = '/subscriptions/00000000-0000-0000-0000-000000000000'
                    subscriptionId = '00000000-0000-0000-0000-000000000000'
                    displayName    = 'Prod'
                    state          = 'Enabled'
                }
            }
            $Sub | New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
            # Positive half: a not-X-only assertion would also pass if the pipe silently failed for
            # an unrelated reason. Prove it actually reached the ARM call.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.principalId -eq 'p1'
            }
        }

        It 'errors with InvalidPrincipalId when -PrincipalId is not a GUID' {
            New-OEREligibleRoleAssignment -Role 'Reader' -PrincipalId 'not-a-guid' -Subscription '00000000-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId,New-OEREligibleRoleAssignment'
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
            New-OEREligibleRoleAssignment -Role 'Reader' -User 'ghost@contoso.com' -Subscription 'not-a-real-sub' `
                -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PrincipalNotFound,New-OEREligibleRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0 -Exactly
        }
    }
}

Describe 'New-OEREligibleRoleAssignment verbose output' {
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
        $Verbose = New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[New-OEREligibleRoleAssignment\] Target scope:'
        $Text | Should -Match "\[New-OEREligibleRoleAssignment\] Resolved role 'Reader' to "
        $Text | Should -Match '\[New-OEREligibleRoleAssignment\] Resolved principal to '
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved role
        # definition id legitimately contains the 'Microsoft.Authorization' resource-provider
        # namespace, which is not a header or token leak. Assert against the actual header/token
        # shape instead ('Authorization:' with a colon, or the word 'bearer').
        $Text = (New-OEREligibleRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Subscription 'Prod' -DurationDays 30 -Confirm:$false -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'New-OEREligibleRoleAssignment piped principal ambiguity guard' {
    <#
        Whole-branch review finding I-1, same guard as New-OERRoleAssignment. Task 2 made
        -PrincipalId ValueFromPipelineByPropertyName and Resolve-OERPrincipalOrId gives it precedence
        over -User/-Group/-ServicePrincipal, so piping assignment-shaped objects (all of which carry
        their own PrincipalId) alongside a named principal silently made each piped item's own
        principal eligible instead. Refused as AmbiguousPrincipal, per the PR #26 precedent in
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

    It 'errors AmbiguousPrincipal and issues no ARM call when -ServicePrincipal is bound alongside a piped eligible assignment' {
        # Built by the REAL converter so the piped shape cannot drift from what the module emits.
        $Eligible = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OEREligibleRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleEligibilitySchedules/e1'
                name       = 'e1'
                properties = @{
                    principalId      = '66666666-6666-6666-6666-666666666666'
                    principalType    = 'User'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Eligible | New-OEREligibleRoleAssignment -Role 'Reader' -ServicePrincipal 'sp-automation' `
            -Scope '/subscriptions/s1' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,New-OEREligibleRoleAssignment'
        $Err[0].Exception.Message | Should -BeLike '*66666666-6666-6666-6666-666666666666*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'still binds the piped PrincipalId when no friendly parameter is supplied (Task 2 capability regression)' {
        $Eligible = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OEREligibleRoleAssignment -InputObject @{
                id         = '/subscriptions/s/providers/Microsoft.Authorization/roleEligibilitySchedules/e1'
                name       = 'e1'
                properties = @{
                    principalId      = '66666666-6666-6666-6666-666666666666'
                    principalType    = 'User'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd1'
                    scope            = '/subscriptions/s'
                }
            }
        }
        $Err = $null
        $Eligible | New-OEREligibleRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' `
            -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '66666666-6666-6666-6666-666666666666'
        }
    }

    It 'only WARNS for a direct call supplying both -PrincipalId and -ServicePrincipal: the guard is pipe-only' {
        $Err = $null
        $Warnings = New-OEREligibleRoleAssignment -Role 'Reader' `
            -PrincipalId '66666666-6666-6666-6666-666666666666' -ServicePrincipal 'sp-automation' `
            -Scope '/subscriptions/s1' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        (($Err | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Not -Match 'AmbiguousPrincipal'
        ($Warnings.Message -join "`n") | Should -Match '-PrincipalId takes precedence'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.principalId -eq '66666666-6666-6666-6666-666666666666'
        }
    }
}
