BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"

    $script:PolicyId = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
    $script:RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:User1 = 'bbbbbbbb-0000-0000-0000-000000000001'
    $script:User2 = 'bbbbbbbb-0000-0000-0000-000000000002'
    $script:GroupA = 'cccccccc-0000-0000-0000-000000000001'
    $script:GroupB = 'cccccccc-0000-0000-0000-000000000002'

    # The nine Microsoft Graph v1.0 rules this cmdlet can touch, as hashtables -- the shape
    # Invoke-MgGraphRequest returns -- with v1.0 approver objects (userId / groupId, never id).
    # -EnablementFirst lists the activation enablement rule BEFORE the authentication-context rule,
    # so each of the two patch-order tests starts from the order the helper has to change.
    function New-TestRuleSet {
        param(
            [string]$ActivationDuration = 'PT8H',
            [string[]]$ActivationEnabledRules = @('Justification'),
            [bool]$AuthContextEnabled = $false,
            [string]$AuthContextClaim = '',
            [bool]$ApprovalRequired = $false,
            [object[]]$Approvers = @(),
            [switch]$NoApprovalStage,
            [switch]$EnablementFirst
        )
        function New-Target ([string]$Caller, [string]$Level) {
            @{ caller = $Caller; operations = @('All'); level = $Level; inheritableSettings = @(); enforcedSettings = @() }
        }
        $Stages = if ($NoApprovalStage) { @() } else {
            @(@{
                    approvalStageTimeOutInDays      = 1
                    isApproverJustificationRequired = $true
                    escalationTimeInMinutes         = 0
                    isEscalationEnabled             = $false
                    primaryApprovers                = @($Approvers)
                    escalationApprovers             = @()
                })
        }
        $Expiration = @{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
            id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = $ActivationDuration
            target = New-Target -Caller 'EndUser' -Level 'Assignment'
        }
        $AuthContext = @{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
            id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $AuthContextEnabled; claimValue = $AuthContextClaim
            target = New-Target -Caller 'EndUser' -Level 'Assignment'
        }
        $Enablement = @{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id = 'Enablement_EndUser_Assignment'; enabledRules = @($ActivationEnabledRules)
            target = New-Target -Caller 'EndUser' -Level 'Assignment'
        }
        $Approval = @{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
            id = 'Approval_EndUser_Assignment'
            target = New-Target -Caller 'EndUser' -Level 'Assignment'
            setting = @{
                isApprovalRequired               = $ApprovalRequired
                isApprovalRequiredForExtension   = $false
                isRequestorJustificationRequired = $true
                approvalMode                     = 'SingleStage'
                approvalStages                   = $Stages
            }
        }
        $Rest = @(
            @{
                '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
                id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D'
                target = New-Target -Caller 'Admin' -Level 'Eligibility'
            }
            @{
                '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
                id = 'Expiration_Admin_Assignment'; isExpirationRequired = $true; maximumDuration = 'P180D'
                target = New-Target -Caller 'Admin' -Level 'Assignment'
            }
            @{
                '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
                id = 'Enablement_Admin_Assignment'; enabledRules = @('Justification')
                target = New-Target -Caller 'Admin' -Level 'Assignment'
            }
            @{
                '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'
                id = 'Notification_Admin_Admin_Eligibility'; notificationType = 'Email'; recipientType = 'Admin'
                notificationLevel = 'All'; isDefaultRecipientsEnabled = $true; notificationRecipients = @()
                target = New-Target -Caller 'Admin' -Level 'Eligibility'
            }
            @{
                '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'
                id = 'Notification_Approver_EndUser_Assignment'; notificationType = 'Email'; recipientType = 'Approver'
                notificationLevel = 'All'; isDefaultRecipientsEnabled = $true; notificationRecipients = @()
                target = New-Target -Caller 'EndUser' -Level 'Assignment'
            }
        )
        $Head = if ($EnablementFirst) { @($Expiration, $Enablement, $AuthContext) } else { @($Expiration, $AuthContext, $Enablement) }
        @($Head) + @($Approval) + $Rest
    }

    function New-TestUserApprover ([string]$Id, [string]$Name = 'Person') {
        @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $Id; description = $Name }
    }
    function New-TestGroupApprover ([string]$Id, [string]$Name = 'Approvers') {
        @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $Id; description = $Name }
    }

    # A rule as JSON with its keys sorted at every level, so a PATCH body can be compared with the
    # live rule it must equal whatever order either hashtable enumerates its keys in.
    function ConvertTo-CanonicalJson ($Value) {
        function ConvertTo-SortedNode ($Node) {
            if ($Node -is [System.Collections.IDictionary]) {
                $Sorted = [ordered]@{}
                foreach ($Key in @($Node.Keys | Sort-Object)) { $Sorted[[string]$Key] = ConvertTo-SortedNode $Node[$Key] }
                return $Sorted
            }
            if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
                return , @(foreach ($Item in $Node) { ConvertTo-SortedNode $Item })
            }
            $Node
        }
        ConvertTo-SortedNode $Value | ConvertTo-Json -Depth 20 -Compress
    }

    # The PATCH bodies sent, in order, and the primary approvers of the approval rule sent.
    function Get-SentRule ([string]$Id) { @($script:Calls | Where-Object { $_.RuleId -eq $Id }) }
    function Get-SentPrimaryApprover {
        $Sent = @(Get-SentRule -Id 'Approval_EndUser_Assignment')
        if ($Sent.Count -ne 1) { throw "Expected exactly one PATCH of the approval rule, got $($Sent.Count)." }
        @(@($Sent[0].Body.setting.approvalStages)[0].primaryApprovers)
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Set-OERDirectoryRoleManagementPolicy' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        $script:LiveRules = New-TestRuleSet
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:RejectRuleId = @()
        # A rule id here is accepted on its first PATCH and rejected on every later one.
        $script:RejectRepeatRuleId = @()

        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        # Anything not matched by a filtered mock below is a call this cmdlet must not make.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw "Unexpected Graph call: $Method $Uri" }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -like 'v1.0/roleManagement/directory/roleDefinitions*'
        } {
            @{ value = @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader' }) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -like 'v1.0/policies/roleManagementPolicyAssignments*'
        } {
            @{
                value = @(@{
                        id               = 'assignment-1'
                        policyId         = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
                        roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                        scopeId          = '/'
                        scopeType        = 'DirectoryRole'
                        policy           = @{ id = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'; rules = @($script:LiveRules) }
                    })
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like 'v1.0/policies/roleManagementPolicies/*'
        } {
            @{
                id        = ($Uri -replace '^v1\.0/policies/roleManagementPolicies/', '' -replace '\?.*$', '')
                scopeId   = '/'
                scopeType = 'DirectoryRole'
                rules     = @($script:LiveRules)
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {
            $RuleId = ($Uri -split '/')[-1]
            $script:Calls.Add([pscustomobject]@{ Uri = $Uri; RuleId = $RuleId; Body = $Body })
            if ($script:RejectRuleId -contains $RuleId) { throw "Graph rejected rule '$RuleId'." }
            if ($script:RejectRepeatRuleId -contains $RuleId -and @($script:Calls | Where-Object { $_.RuleId -eq $RuleId }).Count -gt 1) {
                throw "Graph rejected the repeated PATCH of rule '$RuleId'."
            }
            @{}
        }
        # An id resolves to itself (letter case preserved, as the real resolver returns a GUID
        # input untouched); a name resolves through the map; anything else is not found, thrown as
        # the record the real Resolve-OERPrincipal throws for a value that matches nothing.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
            $Map = @{
                'person1@example.com' = 'bbbbbbbb-0000-0000-0000-000000000001'
                'person2@example.com' = 'bbbbbbbb-0000-0000-0000-000000000002'
                'grpA'                = 'cccccccc-0000-0000-0000-000000000001'
                'grpB'                = 'cccccccc-0000-0000-0000-000000000002'
            }
            $Kind = if ($User) { 'User' } else { 'Group' }
            $Name = if ($User) { $User } else { $Group }
            $Id = if ($Name -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Name } else { $Map[$Name] }
            if (-not $Id) {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("$Kind '$Name' was not found."), 'PrincipalUnresolved',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Name)
            }
            [pscustomobject]@{ PrincipalId = $Id; PrincipalType = $Kind }
        }
    }

    Context 'guards that refuse the call before any write' {
        It 'reports NothingToUpdate and makes no Graph call when no setting is supplied (<Shape>)' -TestCases @(
            @{ Shape = 'ByPolicyId'; Splat = @{ PolicyId = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222' } }
            @{ Shape = 'ByRole'; Splat = @{ Role = 'Reports Reader' } }
        ) {
            Set-OERDirectoryRoleManagementPolicy @Splat -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'reports InvalidAuthenticationContext for a claim value that is not c followed by digits, before any Graph call' {
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -AuthenticationContextId 'x1' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidAuthenticationContext,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'refuses an explicit request for both an authentication context and MFA as InvalidPolicyChange without naming Azure, and sends nothing' {
            # Live: MFA off, context off -- so only the caller's own request makes the combination.
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -AuthenticationContextId 'c1' -RequireMfaOnActivation $true `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyChange,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match 'mutually exclusive'
            # The patch builder's own backstop message names Azure PIM; a directory-role caller must
            # never see that text.
            $Reported[0].Exception.Message | Should -Not -Match 'Azure'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'reports InvalidDuration for an -EligibleDuration that is neither a day count nor an ISO duration' {
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -EligibleDuration 'forever' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidDuration,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'reports ApproverNotFound when one approver does not resolve, and reads and sends nothing' {
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser 'person1@example.com', 'nobody@example.com' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ApproverNotFound,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'refuses an Azure Resource Manager policy id as InvalidPolicyId naming Set-OERRoleManagementPolicy, with no Graph call' {
            Set-OERDirectoryRoleManagementPolicy -PolicyId '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' `
                -ActivationMaxHours 2 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match 'Set-OERRoleManagementPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'refuses an Azure Resource Manager policy id as InvalidPolicyId before resolving any bound approver' {
            Set-OERDirectoryRoleManagementPolicy -PolicyId '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' `
                -ApproverUser 'person1@example.com' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'refuses a policy id with an embedded query or fragment character as InvalidPolicyId, with no Graph call' {
            Set-OERDirectoryRoleManagementPolicy -PolicyId 'DirectoryRole_x?$expand=rules' -ActivationMaxHours 2 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Not -Match 'Azure Resource Manager'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'refuses a PIM for Groups policy id as InvalidPolicyId after reading it, and sends nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Method -ne 'PATCH' -and $Uri -like 'v1.0/policies/roleManagementPolicies/*'
            } {
                @{ id = 'Group_x'; scopeId = '33333333-3333-3333-3333-333333333333'; scopeType = 'Group'; rules = @($script:LiveRules) }
            }
            Set-OERDirectoryRoleManagementPolicy -PolicyId 'Group_33333333-3333-3333-3333-333333333333_22222222-2222-2222-2222-222222222222' `
                -ActivationMaxHours 2 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match 'Set-OERGroupPimPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'calls Initialize-OERAuth without -IncludeARM' {
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
        }
    }

    Context 'role and policy resolution' {
        It 'reports RoleDefinitionNotFound and reads no policy when the resolver finds no role' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
            Set-OERDirectoryRoleManagementPolicy -Role 'No Such Role' -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'reports RoleDefinitionReadFailed, never RoleDefinitionNotFound, when the resolver throws' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { throw 'Forbidden: insufficient privileges' }
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionReadFailed,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }

        It 'reports AmbiguousRoleName with the candidate ids when the resolver refuses an ambiguous name' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            Set-OERDirectoryRoleManagementPolicy -Role 'Dup' -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRoleName,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        }

        It 'reports PolicyNotFound when no policy assignment exists for the role' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -like 'v1.0/policies/roleManagementPolicyAssignments*'
            } { @{ value = @() } }
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyNotFound,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'reports PolicyReadFailed, not PolicyNotFound, when the assignment read is refused' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -like 'v1.0/policies/roleManagementPolicyAssignments*'
            } { throw 'Forbidden: insufficient privileges' }
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyReadFailed,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyNotFound,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'reports PolicyReadFailed when the read of a policy by id is refused' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Method -ne 'PATCH' -and $Uri -like 'v1.0/policies/roleManagementPolicies/*'
            } { throw 'Forbidden: insufficient privileges' }
            Set-OERDirectoryRoleManagementPolicy -PolicyId $script:PolicyId -ActivationMaxHours 4 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyReadFailed,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'binds -PolicyId from a piped object and reads that policy by id' {
            $Result = [PSCustomObject]@{ PolicyId = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222' } |
                Set-OERDirectoryRoleManagementPolicy -ActivationMaxHours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/policies/roleManagementPolicies/DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222?$expand=rules'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Uri -like 'v1.0/policies/roleManagementPolicyAssignments*'
            }
            @($script:Calls).Count | Should -Be 1
            $script:Calls[0].Uri | Should -Be 'v1.0/policies/roleManagementPolicies/DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222/rules/Expiration_EndUser_Assignment'
            $Result.RoleName | Should -BeNullOrEmpty
            $Result.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'leaves RoleName empty but reports the RoleDefinitionId when -Role is a GUID' {
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'aaaaaaaa-0000-0000-0000-000000000001' -ActivationMaxHours 4 -Confirm:$false
            $Result.RoleName | Should -BeNullOrEmpty
            $Result.RoleDefinitionId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Uri -like 'v1.0/roleManagement/directory/roleDefinitions*'
            }
        }
    }

    Context 'rule updates' {
        It 'PATCHes only Expiration_EndUser_Assignment, at its v1.0 rule path, when -ActivationMaxHours changes' {
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Uri -eq 'v1.0/policies/roleManagementPolicies/DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222/rules/Expiration_EndUser_Assignment'
            }
            $Body = $script:Calls[0].Body
            $Body.maximumDuration | Should -Be 'PT4H'
            # Read-modify-write: the live rule is sent back with only the field changed.
            $Body.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
            $Body.isExpirationRequired | Should -BeTrue
            $Body.target.caller | Should -Be 'EndUser'

            $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            @($Result.ChangedRuleIds) | Should -Be @('Expiration_EndUser_Assignment')
            $Result.Scope | Should -Be '/'
            $Result.PolicyId | Should -Be 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
            $Result.RoleName | Should -Be 'Reports Reader'
            $Result.RoleDefinitionId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            $Result.ActivationMaxHours | Should -Be 4
        }

        It 'reports NoChange and sends nothing when the supplied value already matches the live policy' {
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 8 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoChange,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'PATCHes the eligibility expiration rule when permanence and a duration are supplied' {
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -AllowPermanentEligibility $true -EligibleDuration 'P180D' -Confirm:$false
            @($script:Calls).Count | Should -Be 1
            $script:Calls[0].RuleId | Should -Be 'Expiration_Admin_Eligibility'
            $script:Calls[0].Body.isExpirationRequired | Should -BeFalse
            $script:Calls[0].Body.maximumDuration | Should -Be 'P180D'
            $Result.AllowPermanentEligibility | Should -BeTrue
            $Result.EligibleDurationDays | Should -Be 180
        }

        It 'PATCHes a notification rule built by New-OERPolicyNotificationRule' {
            $Note = New-OERPolicyNotificationRule -Event Activation -Recipient Approver -Level Critical -AdditionalRecipient 'person1@example.com'
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -NotificationRule $Note -Confirm:$false
            @($script:Calls).Count | Should -Be 1
            $script:Calls[0].RuleId | Should -Be 'Notification_Approver_EndUser_Assignment'
            $script:Calls[0].Body.notificationLevel | Should -Be 'Critical'
            @($script:Calls[0].Body.notificationRecipients) | Should -Be @('person1@example.com')
            @($Result.ChangedRuleIds) | Should -Be @('Notification_Approver_EndUser_Assignment')
        }

        It 'returns the policy with only the accepted rule in ChangedRuleIds, then writes PolicyRulesRejected naming the rejected rule' {
            $script:RejectRuleId = @('Expiration_Admin_Eligibility')
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -AllowPermanentEligibility $true `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
            # A rejected rule does not stop the other: both were sent.
            @($script:Calls).Count | Should -Be 2
            @($Result.ChangedRuleIds) | Should -Be @('Expiration_EndUser_Assignment')
            $Result.ActivationMaxHours | Should -Be 4
            # The rejected rule keeps its live value on the returned object.
            $Result.AllowPermanentEligibility | Should -BeFalse
            $Rejected = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERDirectoryRoleManagementPolicy' })
            $Rejected.Count | Should -Be 1
            $Rejected[0].Exception.Message | Should -Match 'Expiration_Admin_Eligibility'
            $Rejected[0].Exception.Message | Should -Not -Match 'Expiration_EndUser_Assignment'
            ($Warn -join ' ') | Should -Match 'Expiration_Admin_Eligibility'
        }

        It 'writes no error when every rule is accepted' {
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -AllowPermanentEligibility $true `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 0
        }

        It 'sends nothing and returns no object under -WhatIf' {
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 4 -WhatIf
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'approvers (Microsoft Graph semantics)' {
        It 'PATCHes the approval rule when an approver set of the same size changes, in the v1.0 shape' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(New-TestGroupApprover -Id $script:GroupA)
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup 'grpB' -Confirm:$false
            @($script:Calls).Count | Should -Be 1
            $script:Calls[0].RuleId | Should -Be 'Approval_EndUser_Assignment'
            $Primary = @(Get-SentPrimaryApprover)
            $Primary.Count | Should -Be 1
            $Primary[0].'@odata.type' | Should -Be '#microsoft.graph.groupMembers'
            $Primary[0].groupId | Should -Be 'cccccccc-0000-0000-0000-000000000002'
            # v1.0 shape: exactly the discriminator and groupId -- no beta id, no read-only description.
            @($Primary[0].Keys | Sort-Object) | Should -Be @('@odata.type', 'groupId')
            $script:Calls[0].Body.setting.isApprovalRequired | Should -BeTrue
            @($Result.Approvers.Id) | Should -Be @('cccccccc-0000-0000-0000-000000000002')
        }

        It 'reports NoChange when the bound approvers equal the live ones, whatever their letter case' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(New-TestGroupApprover -Id $script:GroupA)
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup 'CCCCCCCC-0000-0000-0000-000000000001' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoChange,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            @($script:Calls).Count | Should -Be 0
        }

        It 'replaces only the user side and carries the live group side when only -ApproverUser is bound' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(
                New-TestUserApprover -Id $script:User1
                New-TestGroupApprover -Id $script:GroupA
            )
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser 'person2@example.com' -Confirm:$false
            $Primary = @(Get-SentPrimaryApprover)
            $Primary.Count | Should -Be 2
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' }).userId | Should -Be @('bbbbbbbb-0000-0000-0000-000000000002')
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' }).groupId | Should -Be @('cccccccc-0000-0000-0000-000000000001')
        }

        It 'clears the group side and keeps the live user when -ApproverGroup is bound to an empty list' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(
                New-TestUserApprover -Id $script:User1
                New-TestGroupApprover -Id $script:GroupA
            )
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup @() -Confirm:$false
            $Primary = @(Get-SentPrimaryApprover)
            $Primary.Count | Should -Be 1
            $Primary[0].'@odata.type' | Should -Be '#microsoft.graph.singleUser'
            $Primary[0].userId | Should -Be 'bbbbbbbb-0000-0000-0000-000000000001'
        }

        It 'carries a live approver of another kind untouched when an approver side is bound' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(
                @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
                New-TestUserApprover -Id $script:User1
                New-TestGroupApprover -Id $script:GroupA
            )
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser 'person2@example.com' -Confirm:$false
            $Primary = @(Get-SentPrimaryApprover)
            $Primary.Count | Should -Be 3
            $Manager = @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.requestorManager' })
            $Manager.Count | Should -Be 1
            @($Manager[0].Keys | Sort-Object) | Should -Be @('@odata.type', 'managerLevel')
            $Manager[0].managerLevel | Should -Be 1
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' }).userId | Should -Be @('bbbbbbbb-0000-0000-0000-000000000002')
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' }).groupId | Should -Be @('cccccccc-0000-0000-0000-000000000001')
        }

        It 'sends an approver named twice, by UPN and by id in another letter case, once' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(New-TestGroupApprover -Id $script:GroupA)
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' `
                -ApproverUser 'person2@example.com', 'BBBBBBBB-0000-0000-0000-000000000002' -Confirm:$false
            $Primary = @(Get-SentPrimaryApprover)
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' }).userId | Should -Be @('bbbbbbbb-0000-0000-0000-000000000002')
        }

        It 'refuses -RequireApproval $true with ApproverRequired when the live stage has no approver, and sends nothing' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $false -Approvers @()
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $true -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ApproverRequired,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -BeLike '*has none on its live approval rule*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'refuses with ApproverRequired when -ApproverGroup @() leaves no approver at all, and sends nothing' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(New-TestGroupApprover -Id $script:GroupA)
            Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup @() -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ApproverRequired,Set-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -BeLike '*would have none*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'turns approval off with -RequireApproval $false alone and keeps the live approver object on the stage' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $true -Approvers @(New-TestGroupApprover -Id $script:GroupA -Name 'PIM Approvers')
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $false -Confirm:$false
            @($script:Calls).Count | Should -Be 1
            $script:Calls[0].RuleId | Should -Be 'Approval_EndUser_Assignment'
            $script:Calls[0].Body.setting.isApprovalRequired | Should -BeFalse
            $Primary = @(Get-SentPrimaryApprover)
            $Primary.Count | Should -Be 1
            $Primary[0].'@odata.type' | Should -Be '#microsoft.graph.groupMembers'
            $Primary[0].groupId | Should -Be 'cccccccc-0000-0000-0000-000000000001'
            $Primary[0].description | Should -Be 'PIM Approvers'
            $Result.RequireApproval | Should -BeFalse
        }

        It 'requires approval when approvers are supplied, even beside -RequireApproval $false' {
            $script:LiveRules = New-TestRuleSet -ApprovalRequired $false -Approvers @()
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $false -ApproverGroup 'grpB' -Confirm:$false
            $script:Calls[0].Body.setting.isApprovalRequired | Should -BeTrue
            @(Get-SentPrimaryApprover).Count | Should -Be 1
        }
    }

    Context 'MFA and authentication context' {
        It 'clears live MFA when a context is set, and PATCHes the enablement rule BEFORE the context rule' {
            # Default fixture order lists the context rule first, so the helper has to move it.
            $script:LiveRules = New-TestRuleSet -ActivationEnabledRules @('MultiFactorAuthentication', 'Justification')
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -AuthenticationContextId 'c1' -Confirm:$false `
                -WarningAction SilentlyContinue -WarningVariable Warn
            @($script:Calls.RuleId) | Should -Be @('Enablement_EndUser_Assignment', 'AuthenticationContext_EndUser_Assignment')
            @($script:Calls[0].Body.enabledRules) | Should -Be @('Justification')
            $script:Calls[1].Body.isEnabled | Should -BeTrue
            $script:Calls[1].Body.claimValue | Should -Be 'c1'
            ($Warn -join ' ') | Should -Match 'mfa cleared'
            @($Result.ChangedRuleIds | Sort-Object) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            $Result.RequireMfaOnActivation | Should -BeFalse
            $Result.AuthenticationContextId | Should -Be 'c1'
        }

        It 'disables a live context when MFA is requested, and PATCHes the context rule BEFORE the enablement rule' {
            # This fixture lists the enablement rule first, so the helper has to move the context rule.
            $script:LiveRules = New-TestRuleSet -AuthContextEnabled $true -AuthContextClaim 'c1' -EnablementFirst
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireMfaOnActivation $true -Confirm:$false `
                -WarningAction SilentlyContinue -WarningVariable Warn
            @($script:Calls.RuleId) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            $script:Calls[0].Body.isEnabled | Should -BeFalse
            $script:Calls[0].Body.claimValue | Should -Be ''
            @($script:Calls[1].Body.enabledRules | Sort-Object) | Should -Be @('Justification', 'MultiFactorAuthentication')
            ($Warn -join ' ') | Should -Match "authentication context 'c1' disabled"
        }

        It 'leaves an untouched MFA plus context combination alone on an unrelated change' {
            $script:LiveRules = New-TestRuleSet -AuthContextEnabled $true -AuthContextClaim 'c1' -ActivationEnabledRules @('MultiFactorAuthentication')
            $null = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ActivationMaxHours 2 -Confirm:$false `
                -WarningAction SilentlyContinue -WarningVariable Warn
            @($script:Calls.RuleId) | Should -Be @('Expiration_EndUser_Assignment')
            $Warn | Should -BeNullOrEmpty
        }
    }

    Context 'MFA and authentication context rules sent together, and one of them rejected' {
        It '<Direction>: puts the accepted <First> back to its live version when <Second> is rejected' -TestCases @(
            @{
                Direction = 'context to MFA'
                LiveSplat = @{ AuthContextEnabled = $true; AuthContextClaim = 'c1' }
                Splat     = @{ RequireMfaOnActivation = $true }
                First     = 'AuthenticationContext_EndUser_Assignment'
                Second    = 'Enablement_EndUser_Assignment'
                Mfa       = $false
                Context   = 'c1'
            }
            @{
                Direction = 'MFA to context'
                LiveSplat = @{ ActivationEnabledRules = @('MultiFactorAuthentication', 'Justification') }
                Splat     = @{ AuthenticationContextId = 'c1' }
                First     = 'Enablement_EndUser_Assignment'
                Second    = 'AuthenticationContext_EndUser_Assignment'
                Mfa       = $true
                Context   = $null
            }
        ) {
            $script:LiveRules = New-TestRuleSet @LiveSplat
            $LiveFirst = @($script:LiveRules | Where-Object { $_.id -eq $First })[0]
            $script:RejectRuleId = @($Second)
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' @Splat -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
            # The pair in patch order, then exactly one compensating PATCH, of the first rule.
            @($script:Calls.RuleId) | Should -Be @($First, $Second, $First)
            (ConvertTo-CanonicalJson $script:Calls[0].Body) | Should -Not -Be (ConvertTo-CanonicalJson $LiveFirst)
            (ConvertTo-CanonicalJson $script:Calls[2].Body) | Should -Be (ConvertTo-CanonicalJson $LiveFirst) -Because 'the compensating PATCH sends the rule exactly as it was read'
            $script:Calls[2].Uri | Should -Be "v1.0/policies/roleManagementPolicies/$($script:PolicyId)/rules/$First"
            # Neither rule of the pair is reported as changed, and the object shows both as read.
            @($Result.ChangedRuleIds).Count | Should -Be 0
            $Result.RequireMfaOnActivation | Should -Be $Mfa
            $Result.AuthenticationContextId | Should -Be $Context
            $Rejected = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERDirectoryRoleManagementPolicy' })
            $Rejected.Count | Should -Be 1
            $Rejected[0].Exception.Message | Should -BeLike "*rejected 1 of 2 rule(s): $Second.*"
            $Rejected[0].Exception.Message | Should -BeLike "*Rule '$First', which Microsoft Graph had accepted, was put back to its value before this call*"
            $Rejected[0].Exception.Message | Should -BeLike '*activation keeps the protection it had before the call.*'
        }

        It '<Direction>: keeps <First> in ChangedRuleIds and says what activation now requires when putting it back fails too' -TestCases @(
            @{
                Direction = 'context to MFA'
                LiveSplat = @{ AuthContextEnabled = $true; AuthContextClaim = 'c1' }
                Splat     = @{ RequireMfaOnActivation = $true }
                First     = 'AuthenticationContext_EndUser_Assignment'
                Second    = 'Enablement_EndUser_Assignment'
                Mfa       = $false
                Context   = $null
                Requires  = 'neither multi-factor authentication nor an authentication context'
            }
            @{
                Direction = 'context c1 to c2'
                LiveSplat = @{ AuthContextEnabled = $true; AuthContextClaim = 'c1' }
                Splat     = @{ AuthenticationContextId = 'c2'; RequireJustificationOnActivation = $false }
                First     = 'Enablement_EndUser_Assignment'
                Second    = 'AuthenticationContext_EndUser_Assignment'
                Mfa       = $false
                Context   = 'c1'
                Requires  = "authentication context 'c1', but not multi-factor authentication"
            }
        ) {
            $script:LiveRules = New-TestRuleSet @LiveSplat
            $script:RejectRuleId = @($Second)
            $script:RejectRepeatRuleId = @($First)
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' @Splat -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
            @($script:Calls.RuleId) | Should -Be @($First, $Second, $First)
            @($Result.ChangedRuleIds) | Should -Be @($First)
            $Result.RequireMfaOnActivation | Should -Be $Mfa
            $Result.AuthenticationContextId | Should -Be $Context
            $Rejected = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERDirectoryRoleManagementPolicy' })
            $Rejected.Count | Should -Be 1
            $Rejected[0].Exception.Message | Should -BeLike "*rejected 1 of 2 rule(s): $Second.*"
            $Rejected[0].Exception.Message | Should -BeLike "*putting it back to its value before this call failed too*"
            $Rejected[0].Exception.Message | Should -BeLike "*activation of this role now requires $Requires.*"
            $Rejected[0].Exception.Message | Should -BeLike '*Run the same command again, or run Set-OERDirectoryRoleManagementPolicy with -RequireMfaOnActivation or -AuthenticationContextId set to the protection this role needs.*'
            $Rejected[0].Exception.Message | Should -Not -BeLike '*keeps the protection*'
            ($Warn -join ' ') | Should -BeLike "*Rule '$First'*could not be put back*"
        }

        It 'sends no compensating PATCH when the FIRST rule of the pair is rejected' {
            $script:LiveRules = New-TestRuleSet -AuthContextEnabled $true -AuthContextClaim 'c1'
            $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
            $Result = Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireMfaOnActivation $true -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
            @($script:Calls.RuleId) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            @($Result.ChangedRuleIds) | Should -Be @('Enablement_EndUser_Assignment')
            $Rejected = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERDirectoryRoleManagementPolicy' })
            $Rejected.Count | Should -Be 1
            $Rejected[0].Exception.Message | Should -Not -BeLike '*put back*'
        }
    }

    Context 'one confirmation per call' {
        BeforeAll {
            # Pester mocks do not cross into the answering runspace, so the fakes are installed in
            # that runspace's own copy of the module (see tests/Unit/TestHelpers/OERConfirmHost.ps1).
            $script:ConfirmScenario = {
                Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                $Module = Get-Module Omnicit.EntraRBAC
                & $Module {
                    $script:TestPatchCount = 0
                    Set-Item -Path function:script:Initialize-OERAuth -Value { }
                    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                        param([string]$Method = 'GET', [string]$Uri, $Body)
                        if ($Method -eq 'PATCH') { $script:TestPatchCount++; return @{} }
                        @{
                            id = 'p1'; scopeId = '/'; scopeType = 'DirectoryRole'
                            rules = @(
                                @{ id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT8H' }
                                @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                            )
                        }
                    }
                }
                $null = Set-OERDirectoryRoleManagementPolicy -PolicyId 'DirectoryRole_p1' -ActivationMaxHours 4 `
                    -AllowPermanentEligibility $true -Confirm
                & $Module { $script:TestPatchCount }
            }
        }

        It 'asks once, naming both changed rules, and sends nothing when declined' {
            $Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $script:ConfirmScenario
            $Run.Prompts.Count | Should -Be 1
            $Run.Prompts[0] | Should -Match "directory role management policy 'DirectoryRole_p1'"
            $Run.Prompts[0] | Should -Match 'Expiration_EndUser_Assignment'
            $Run.Prompts[0] | Should -Match 'Expiration_Admin_Eligibility'
            $Run.Output[-1] | Should -Be 0
        }

        It 'asks once and sends every changed rule when accepted' {
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $script:ConfirmScenario
            $Run.Prompts.Count | Should -Be 1
            $Run.Output[-1] | Should -Be 2
        }
    }
}

Describe 'Set-OERDirectoryRoleManagementPolicy: an approver lookup, missing, ambiguous and failed are three outcomes (Sprint 8 step 3, BL-14)' {
    # The real Resolve-OERApproverInput and Resolve-OERPrincipal run here (this Describe mocks neither);
    # only the lookups under them answer. Approvers are resolved before the policy and the role are
    # read, so no Graph call is made on any of the three paths. Each test filters -ErrorVariable to the
    # records this cmdlet wrote itself, since a record thrown inside a nested command is collected
    # there as well.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw "Unexpected Graph call: $Method $Uri" }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'missing-approvers' } { $null }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'dup-approvers' } {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, " +
                    '22222222-2222-2222-2222-222222222222). Re-run with the object id instead of the display name.'),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup-approvers')
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERUserId -ParameterFilter { $UserPrincipalName -eq 'person9@example.com' } {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
        }
    }

    It 'reports an approver that matches nothing as ApproverNotFound, with the message, category and target it always had' {
        Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup 'missing-approvers' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' })
        $Own.Count | Should -Be 1
        $Own[0].FullyQualifiedErrorId | Should -Be 'ApproverNotFound,Set-OERDirectoryRoleManagementPolicy'
        $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Own[0].TargetObject | Should -Be 'missing-approvers'
        $Own[0].Exception.Message | Should -Be "Group 'missing-approvers' was not found."
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports an ambiguous approver name as AmbiguousApproverName naming the candidates, never as ApproverNotFound' {
        Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverGroup 'dup-approvers' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' })
        $Own.Count | Should -Be 1
        $Own[0].FullyQualifiedErrorId | Should -Be 'AmbiguousApproverName,Set-OERDirectoryRoleManagementPolicy'
        $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Own[0].TargetObject | Should -Be 'dup-approvers'
        $Own[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Own[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports a failed approver lookup as itself, once, never as ApproverNotFound' {
        Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser 'person9@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' })
        $Own.Count | Should -Be 1
        $Own[0].FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy'
        $Own[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Own[0].Exception.Message | Should -Match 'Insufficient privileges'
        @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'scrubs a failed approver lookup before it publishes it as itself' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERApproverInput {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser 'person9@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        # Reached: the catch published the record as itself.
        @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
        # A prefix match: $PSCmdlet.WriteError appends ',<cmdlet>' to this same record, in place,
        # before the filter is evaluated.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record -and [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' -and
            $Record.Exception.Message -like '*Insufficient privileges*'
        }
    }
}
