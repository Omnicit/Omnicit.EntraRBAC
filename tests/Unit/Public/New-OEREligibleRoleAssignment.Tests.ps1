BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

        It 'rolls the policy back FIRST when the grant is refused, then writes PolicyOpenedButGrantFailed, then the grant''s own error' {
            # Ruling R7: the rollback comes before any error, so -ErrorAction Stop cannot skip it.
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $Order.Add('grant'); throw 'ARM rejected the request' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentEligibility) { $Order.Add('open') } else { $Order.Add('rollback') }
                [PSCustomObject]@{ PolicyId = 'pol-1' }
            }
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
            $Order -join ',' | Should -Be 'open,grant,rollback'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'pol-1' -and $AllowPermanentEligibility -eq $false
            }
            # -ErrorVariable also collects every record the mock layers raise as the refused PUT
            # unwinds; the cmdlet's OWN records are the ones that carry its name, in the order written.
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' })
            $Own.Count | Should -Be 2
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment'
            $Own[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $Own[0].TargetObject | Should -BeExactly 'pol-1'
            $Own[0].Exception.Message | Should -BeExactly ("The eligible role assignment failed after role management policy 'pol-1' had " +
                'been opened to allow permanent assignments. It was rolled back to disallow permanent assignments. The request ' +
                'failed with: ARM rejected the request')
            # The grant's own record, re-published unchanged.
            $Own[1].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OEREligibleRoleAssignment'
            $Own[1].Exception.Message | Should -BeExactly 'ARM rejected the request'
        }

        It 'still rolls back under -ErrorAction Stop, and the error that stops the caller is PolicyOpenedButGrantFailed' {
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $Order.Add('grant'); throw 'ARM rejected the request' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentEligibility) { $Order.Add('open') } else { $Order.Add('rollback') }
                [PSCustomObject]@{ PolicyId = 'pol-1' }
            }
            $Thrown = $null
            try {
                New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
            } catch {
                $Order.Add('error')
                $Thrown = $PSItem
            }
            $Order -join ',' | Should -Be 'open,grant,rollback,error'
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment'
            $Thrown.Exception.Message | Should -BeExactly ("The eligible role assignment failed after role management policy 'pol-1' had " +
                'been opened to allow permanent assignments. It was rolled back to disallow permanent assignments. The request ' +
                'failed with: ARM rejected the request')
        }

        It 'names the policy left open and scrubs the bearer record when the rollback ALSO fails' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'ARM rejected the request' }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -ParameterFilter {
                $AllowPermanentEligibility -eq $false
            } -MockWith { throw 'rollback forbidden' }
            New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' })
            $Own.Count | Should -Be 2
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment'
            $Own[0].Exception.Message | Should -BeExactly ("The eligible role assignment failed after role management policy 'pol-1' had " +
                "been opened to allow permanent assignments. The rollback ALSO failed, so the policy is still open. Run " +
                "'Set-OERRoleManagementPolicy -PolicyId ''pol-1'' -AllowPermanentEligibility `$false' to close it. The request " +
                'failed with: ARM rejected the request')
            $Own[1].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OEREligibleRoleAssignment'
            # The refused grant's record and the failed rollback's record.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 2 -Exactly
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
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $AllowPermanentEligibility -eq $true
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter {
                $AllowPermanentEligibility -eq $false
            }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment' }).Count |
                Should -Be 0
            # The thrown path without an opened policy writes the grant's own error, and only that.
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'ARM rejected the request,New-OEREligibleRoleAssignment'
        }
    }

    Context 'a request Azure Resource Manager accepts but answers with a status in the Failed family (BL-33)' {
        # ARM can accept the AdminAssign request and answer it with status Failed (or another value of
        # the Failed family, such as FailedAsResourceIsLocked), which grants nothing. The cmdlet still
        # emits the request object, then writes EligibilityRequestFailed. When this invocation opened
        # the role management policy for a permanent grant, the policy is rolled back first, as for a
        # refused grant (Ruling R4), and the one record carries the rollback text. $script:Order records
        # the policy writes and the PUT; the tests add the emitted object and the stop as they see them.
        BeforeEach {
            $script:AnsweredStatus = 'Failed'
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState {
                [PSCustomObject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false }
            }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentEligibility) { $script:Order.Add('open') } else { $script:Order.Add('rollback') }
                [PSCustomObject]@{ PolicyId = 'pol-1' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                $script:Order.Add('grant')
                [PSCustomObject]@{
                    id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/req-f1'
                    name       = 'req-f1'
                    properties = [PSCustomObject]@{
                        scope = '/subscriptions/s1'; roleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'
                        principalId = 'p1'; principalType = 'User'; requestType = 'AdminAssign'; status = $script:AnsweredStatus
                        scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    }
                }
            }
            $script:FailedMessage = "Azure Resource Manager accepted the eligible role assignment request 'req-f1' (AdminAssign) of role " +
                "'/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' for principal 'p1' at scope '/subscriptions/s1' " +
                'but answered status Failed, so nothing was granted.'
            $script:OpenedText = " Role management policy 'pol-1' had been opened to allow permanent assignments before the request was sent."
            $script:Grant = @{ Role = 'Reader'; Subscription = 'Prod'; User = 'anna@contoso.com'; Confirm = $false; WarningAction = 'SilentlyContinue' }
        }

        It 'emits the request object AND writes exactly one EligibilityRequestFailed when ARM answers status <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'FAILED' }
            @{ Status = 'FailedAsResourceIsLocked' }
        ) {
            $script:AnsweredStatus = $Status
            $Err = $null
            $Out = @(New-OEREligibleRoleAssignment @script:Grant -DurationDays 30 -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
            $Out[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Err[0].TargetObject | Should -BeExactly '/subscriptions/s1'
            $Err[0].Exception.Message | Should -BeExactly $script:FailedMessage.Replace('answered status Failed,', "answered status $Status,")
            # A time-bound grant reads and opens no policy, so nothing is rolled back.
            $script:Order -join ',' | Should -Be 'grant'
        }

        It 'still hands the object to -OutVariable under -ErrorAction Stop, and the throw carries EligibilityRequestFailed' {
            $Out = $null
            $Thrown = $null
            try {
                New-OEREligibleRoleAssignment @script:Grant -DurationDays 30 -ErrorAction Stop -OutVariable Out | Out-Null
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
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
            $Out = @(New-OEREligibleRoleAssignment @script:Grant -DurationDays 30 -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The request was sent and answered with this status, so the absence below is a decision.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
            $Out.Count | Should -Be 1
            $Out[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 0
        }

        It 'rolls back the policy this invocation opened BEFORE the object and the error, and writes one record with the rollback text' {
            $Err = $null
            New-OEREligibleRoleAssignment @script:Grant -Permanent -ErrorAction SilentlyContinue -ErrorVariable Err |
                ForEach-Object { $script:Order.Add("emit:$($_.Status)") }
            # Rolled back before anything is emitted, so neither -ErrorAction Stop nor a consumer that
            # stops the pipeline can skip it.
            $script:Order -join ',' | Should -Be 'open,grant,rollback,emit:Failed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'pol-1' -and $AllowPermanentEligibility -eq $false
            }
            # One record, EligibilityRequestFailed: the request was accepted, not refused, so this is
            # not PolicyOpenedButGrantFailed, but it carries the same rollback text.
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' })
            $Reported.Count | Should -Be 1
            $Reported[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
            $Reported[0].Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                ' It was rolled back to disallow permanent assignments.')
        }

        It 'names the policy left open, and how to close it, when the rollback after a Failed answer ALSO fails' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy {
                if ($AllowPermanentEligibility) { $script:Order.Add('open'); return [PSCustomObject]@{ PolicyId = 'pol-1' } }
                $script:Order.Add('rollback')
                throw 'rollback forbidden'
            }
            $Err = $null
            $Out = @(New-OEREligibleRoleAssignment @script:Grant -Permanent -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $script:Order -join ',' | Should -Be 'open,grant,rollback'
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' })
            $Reported.Count | Should -Be 1
            $Reported[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
            $Reported[0].Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                " The rollback ALSO failed, so the policy is still open. Run 'Set-OERRoleManagementPolicy -PolicyId ''pol-1'' " +
                "-AllowPermanentEligibility `$false' to close it.")
            # The failed rollback's record is scrubbed, as on the refused-grant path.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'neither rolls back nor names the policy when the nested open was DECLINED' {
            # A declined self-gating open emits nothing having written nothing, so this invocation
            # opened nothing: a Failed answer must not revert, or name, a write that never happened.
            Mock -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy { if ($AllowPermanentEligibility) { $script:Order.Add('asked') } }
            $Err = $null
            $Out = @(New-OEREligibleRoleAssignment @script:Grant -Permanent -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $script:Order -join ',' | Should -Be 'asked,grant'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $AllowPermanentEligibility -eq $true }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $AllowPermanentEligibility -eq $false }
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
            $Err[0].Exception.Message | Should -BeExactly $script:FailedMessage
        }

        It 'still rolls back under -ErrorAction Stop, before the object reaches -OutVariable and the throw stops the caller' {
            $Out = $null
            $Thrown = $null
            try {
                New-OEREligibleRoleAssignment @script:Grant -Permanent -ErrorAction Stop -OutVariable Out |
                    ForEach-Object { $script:Order.Add("emit:$($_.Status)") }
            } catch {
                $script:Order.Add('error')
                $Thrown = $PSItem
            }
            $script:Order -join ',' | Should -Be 'open,grant,rollback,emit:Failed,error'
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,New-OEREligibleRoleAssignment'
            $Thrown.Exception.Message | Should -BeExactly ($script:FailedMessage + $script:OpenedText +
                ' It was rolled back to disallow permanent assignments.')
            @($Out).Count | Should -Be 1
            $Out[0].Status | Should -BeExactly 'Failed'
        }

        It 'does not roll back an opened policy when the permanent grant is answered Provisioned' {
            $script:AnsweredStatus = 'Provisioned'
            $Err = $null
            $Out = @(New-OEREligibleRoleAssignment @script:Grant -Permanent -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The policy was opened and the grant sent, so the missing rollback below is a decision.
            $script:Order -join ',' | Should -Be 'open,grant'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $AllowPermanentEligibility -eq $false }
            $Out.Count | Should -Be 1
            $Out[0].Status | Should -BeExactly 'Provisioned'
            @($Err).Count | Should -Be 0
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

Describe 'New-OEREligibleRoleAssignment: a refused grant after the policy open, in a script with no try (Ruling R7)' {
    # Under -ErrorAction Stop the first error the cmdlet writes stops it, and where no try stands
    # anywhere up the call stack it ends the whole script. So the rollback must be sent BEFORE that
    # error, and the error must be PolicyOpenedButGrantFailed. The script runs in a runspace through
    # Invoke-OERWithConfirmAnswer, so it is transported as text and installs its own fakes in ITS copy
    # of the module scope; they append every policy write and PUT to a log file whose path is
    # substituted into the text, since a stopped script prints nothing. The control runs the same
    # script without Stop, so the logged rollback cannot be an artefact of a fake that never logs.
    BeforeAll {
        $script:NewNoTryScenario = {
            param([string]$Log, [string]$Stop)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
    Set-Item -Path function:script:Resolve-OERPrincipal -Value { [pscustomobject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
    Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
    Set-Item -Path function:script:Get-OERPermanentPolicyState -Value {
        [pscustomobject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false }
    }
    Set-Item -Path function:script:Set-OERRoleManagementPolicy -Value {
        # SupportsShouldProcess so the rollback's -Confirm:$false binds; the fake never asks.
        [CmdletBinding(SupportsShouldProcess)]
        param([string]$PolicyId, [bool]$AllowPermanentEligibility)
        [System.IO.File]::AppendAllText('#LOG#', "$(if ($AllowPermanentEligibility) { 'open' } else { 'rollback' })`n")
        [pscustomobject]@{ PolicyId = $PolicyId }
    }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body)
        [System.IO.File]::AppendAllText('#LOG#', "grant $Method`n")
        throw 'ARM rejected the request'
    }
}
$Result = New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm:$false -WarningAction SilentlyContinue #STOP#
"REACHED:$(@($Result).Count)"
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#STOP#', $Stop))
        }
        $script:PolicyOpenedButGrantFailedText = "The eligible role assignment failed after role management policy 'pol-1' had been opened " +
            'to allow permanent assignments. It was rolled back to disallow permanent assignments. The request failed with: ARM rejected the request'
        function Get-TestLoggedLine ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'under -ErrorAction Stop rolls the policy back before PolicyOpenedButGrantFailed ends the script' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Stop '-ErrorAction Stop'
        # Measured: a stop outside any try ends the whole script, so the runner throws to its caller.
        $Thrown = { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } | Should -Throw -PassThru
        $Thrown.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
        $Thrown.Exception.InnerException.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment'
        $Thrown.Exception.InnerException.ErrorRecord.Exception.Message | Should -BeExactly $script:PolicyOpenedButGrantFailedText
        # The rollback was sent before that error stopped the script, and nothing after it.
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT', 'rollback')
    }

    It 'the control: without Stop the same script reaches the end, PolicyOpenedButGrantFailed written before the grant''s own error' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewNoTryScenario -Log $Log -Stop ''
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT', 'rollback')
        @($Run.Errors) | Should -Be @($script:PolicyOpenedButGrantFailedText, 'ARM rejected the request')
    }
}

Describe 'New-OEREligibleRoleAssignment: the rollback is not asked again under an explicit -Confirm (Ruling R12)' {
    # Under an explicit -Confirm the propagated $ConfirmPreference makes every nested ShouldProcess
    # prompt, and a declined Set-OERRoleManagementPolicy emits nothing and throws nothing. A rollback
    # that asked could therefore be declined while the record still said "It was rolled back". So the
    # rollback passes -Confirm:$false: it puts back this invocation's own open, which the operator
    # already confirmed. The fake models the real cmdlet's contract -- it writes and emits only when
    # its own ShouldProcess says yes -- and the host answers Yes to the assignment, Yes to the open,
    # and No to any prompt after those. The open's prompt and its logged write prove the harness
    # reaches the nested prompts. The script is transported as text and installs its own fakes in ITS
    # copy of the module scope; the log is written with AppendAllText, which never prompts.
    # Defined here, in the discovery phase, since -ForEach is read then.
    $FailedAnswer = @'
[pscustomobject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/req-f1'; name = 'req-f1'
    properties = [pscustomobject]@{
        scope = '/subscriptions/s1'; roleDefinitionId = $Body.properties.roleDefinitionId; principalId = $Body.properties.principalId
        principalType = 'User'; requestType = 'AdminAssign'; status = 'Failed'
        scheduleInfo = [pscustomobject]@{ startDateTime = 't'; expiration = [pscustomobject]@{ type = 'NoExpiration' } } } }
'@
    $Paths = @(
        @{
            Path     = 'a refused grant'
            Grant    = "throw 'ARM rejected the request'"
            Expected = @(
                ("PolicyOpenedButGrantFailed,New-OEREligibleRoleAssignment|The eligible role assignment failed after role management policy 'pol-1' " +
                    'had been opened to allow permanent assignments. It was rolled back to disallow permanent assignments. The request failed ' +
                    'with: ARM rejected the request')
                'ARM rejected the request,New-OEREligibleRoleAssignment|ARM rejected the request'
            )
        }
        @{
            Path     = 'a Failed answer'
            Grant    = $FailedAnswer
            Expected = @(
                ("EligibilityRequestFailed,New-OEREligibleRoleAssignment|Azure Resource Manager accepted the eligible role assignment request 'req-f1' " +
                    "(AdminAssign) of role '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' for principal 'p1' at scope " +
                    "'/subscriptions/s1' but answered status Failed, so nothing was granted. Role management policy 'pol-1' had been opened to " +
                    'allow permanent assignments before the request was sent. It was rolled back to disallow permanent assignments.')
            )
        }
    )

    BeforeAll {
        $script:NewConfirmScenario = {
            param([string]$Log, [string]$Grant)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
    Set-Item -Path function:script:Resolve-OERPrincipal -Value { [pscustomobject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
    Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
    Set-Item -Path function:script:Get-OERPermanentPolicyState -Value {
        [pscustomobject]@{ PolicyId = 'pol-1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Eligibility'; PermanentAllowed = $false }
    }
    Set-Item -Path function:script:Set-OERRoleManagementPolicy -Value {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
        param([string]$PolicyId, [bool]$AllowPermanentEligibility)
        if ($PSCmdlet.ShouldProcess("role management policy '$PolicyId'", "Set AllowPermanentEligibility $AllowPermanentEligibility")) {
            [System.IO.File]::AppendAllText('#LOG#', "$(if ($AllowPermanentEligibility) { 'open' } else { 'rollback' })`n")
            [pscustomobject]@{ PolicyId = $PolicyId }
        }
    }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body)
        [System.IO.File]::AppendAllText('#LOG#', "grant $Method`n")
        #GRANT#
    }
}
New-OEREligibleRoleAssignment -Role 'Reader' -Subscription 'Prod' -User 'anna@contoso.com' -Permanent -Confirm -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Recorded | Out-Null
@($Recorded | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,New-OEREligibleRoleAssignment' } | ForEach-Object { '{0}|{1}' -f $_.FullyQualifiedErrorId, $_.Exception.Message })
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#GRANT#', $Grant))
        }
        function Get-TestLoggedLine ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'after <Path>, rolls the policy back without a prompt of its own, where a third prompt would be declined' -ForEach $Paths {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Run = Invoke-OERWithConfirmAnswer -AnswerSequence @('&Yes', '&Yes', '&No') -Script (& $script:NewConfirmScenario -Log $Log -Grant $Grant)
        # Two prompts, the assignment's and the open's; the rollback asks none.
        @($Run.Prompts).Count | Should -Be 2
        $Run.Prompts[0] | Should -BeLike "*eligible role 'Reader' for User 'anna@contoso.com' at scope '/subscriptions/s1'*"
        $Run.Prompts[1] | Should -BeLike "*Set AllowPermanentEligibility True*role management policy 'pol-1'*"
        # The rollback was really written, so the record's "It was rolled back" is true.
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant PUT', 'rollback')
        @($Run.Output) | Should -Be (@($Expected) + 'END')
    }
}
