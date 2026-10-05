BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERRoleManagementPolicy' {
    BeforeAll {
        $script:Rules = @(
            [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'PT8H' }
            [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('MultiFactorAuthentication','Justification') }
            [PSCustomObject]@{ id = 'Enablement_Admin_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('Justification') }
            [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $false; maximumDuration = 'P365D' }
            [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P180D' }
            [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; ruleType = 'RoleManagementPolicyApprovalRule'; setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalStages = @([PSCustomObject]@{ primaryApprovers = @([PSCustomObject]@{ id = 'g1'; description = 'Approvers'; userType = 'Group' }) }) } }
            [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; ruleType = 'RoleManagementPolicyAuthenticationContextRule'; isEnabled = $true; claimValue = 'c1' }
            [PSCustomObject]@{ id = 'Notification_Approver_EndUser_Assignment'; ruleType = 'RoleManagementPolicyNotificationRule'; recipientType = 'Approver'; notificationLevel = 'All'; isDefaultRecipientsEnabled = $true; notificationRecipients = @('person18@example.com') }
        )
    }

    It 'surfaces friendly summary properties and tags the output' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:Rules } {
            param($Rules)
            $p = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId '/s/pol1' -Scope '/s' -RoleName 'Reader' -RoleDefinitionId '/s/rd1'
            $p.PSObject.TypeNames[0]               | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            $p.ActivationMaxHours                  | Should -Be 8
            $p.RequireMfaOnActivation              | Should -BeTrue
            $p.RequireJustificationOnActivation    | Should -BeTrue
            $p.RequireTicketOnActivation           | Should -BeFalse
            $p.RequireJustificationOnActiveAssignment | Should -BeTrue
            $p.AllowPermanentEligibility           | Should -BeTrue
            $p.EligibleDuration                    | Should -Be 'P365D'
            $p.AllowPermanentActiveAssignment      | Should -Be $false
            $p.RequireApproval                     | Should -BeTrue
            $p.Approvers[0].UserType               | Should -Be 'Group'
            $p.AuthenticationContextId             | Should -Be 'c1'
            @($p.Notifications).Count              | Should -Be 1
            $p.RoleName                            | Should -Be 'Reader'
        }
    }

    It 'reports a null AuthenticationContextId when the rule is disabled' {
        InModuleScope Omnicit.EntraRBAC {
            $rules = @([PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = '' })
            (ConvertTo-OERRoleManagementPolicy -Rules $rules -PolicyId '/s/pol1').AuthenticationContextId | Should -BeNullOrEmpty
        }
    }

    It 'adds ChangedRuleIds only when supplied' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERRoleManagementPolicy -Rules @() -PolicyId '/s/pol1' -ChangedRuleId @('Expiration_Admin_Eligibility')
            $p.ChangedRuleIds | Should -Be 'Expiration_Admin_Eligibility'
            $noChange = ConvertTo-OERRoleManagementPolicy -Rules @() -PolicyId '/s/pol1'
            $noChange.PSObject.Properties.Name | Should -Not -Contain 'ChangedRuleIds'
        }
    }

    It 'parses the eligible and active maximum durations into day counts' {
        InModuleScope Omnicit.EntraRBAC {
            $Rules = @(
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment';  isExpirationRequired = $true; maximumDuration = 'P180D' }
            )
            $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId '/p/1'
            $Policy.EligibleDurationDays | Should -Be 365
            $Policy.ActiveDurationDays   | Should -Be 180
        }
    }

    It 'leaves the day counts null when the duration is absent or genuinely fractional' {
        InModuleScope Omnicit.EntraRBAC {
            $Rules = @(
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }
                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment';  isExpirationRequired = $true; maximumDuration = 'PT12H' }
            )
            $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId '/p/1'
            $Policy.EligibleDurationDays | Should -BeNullOrEmpty
            $Policy.ActiveDurationDays   | Should -BeNullOrEmpty
        }
    }

    It 'parses a year/month-form maximum duration into whole days instead of null (roundtrip PR task 13)' {
        InModuleScope Omnicit.EntraRBAC {
            $Rules = @(
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P1Y' }
                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment';  isExpirationRequired = $true; maximumDuration = 'P6M' }
            )
            $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId '/p/1'
            $Policy.EligibleDurationDays | Should -Be 365
            $Policy.ActiveDurationDays   | Should -Be 180
        }
    }

    Context 'Graph approver shape (directory-role policies)' {
        # Directory-role policies are read from Microsoft Graph v1.0, whose approvers carry the object
        # id as userId / groupId (beta-style reads carry it as id) and the kind in @odata.type -- not
        # the ARM id / userType pair. The projection stays one owner for both transports.
        BeforeAll {
            $script:GraphRules = @(
                [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                    setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'
                        approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                primaryApprovers = @(
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000001'; description = 'Approver One' }
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'bbbbbbbb-0000-0000-0000-000000000001' }
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'bbbbbbbb-0000-0000-0000-000000000002'; description = 'Beta Group' }
                                ) }) } }
            )
        }

        It 'projects v1.0 and beta-style Graph approvers to Id, UserType and DisplayName' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:GraphRules } {
                param($Rules)
                $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId 'pol-1' -Scope '/' -ApproverShape Graph
                $Approver = @($Policy.Approvers)
                $Approver.Count | Should -Be 3

                $Approver[0].Id          | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
                $Approver[0].UserType    | Should -Be 'User'
                $Approver[0].DisplayName | Should -Be 'Approver One'

                $Approver[1].Id          | Should -Be 'bbbbbbbb-0000-0000-0000-000000000001'
                $Approver[1].UserType    | Should -Be 'Group'
                $Approver[1].DisplayName | Should -Be ''

                $Approver[2].Id          | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
                $Approver[2].UserType    | Should -Be 'Group'
                $Approver[2].DisplayName | Should -Be 'Beta Group'

                # The approver objects carry the same three property names as the ARM projection.
                @($Approver[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('DisplayName', 'Id', 'UserType')
                $Policy.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
                $Policy.Scope | Should -Be '/'
                $Policy.RequireApproval | Should -BeTrue
            }
        }

        It 'reads Graph-shaped approvers as id-less without -ApproverShape Graph (the ARM default)' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:GraphRules } {
                param($Rules)
                $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId 'pol-1' -Scope '/'
                $Approver = @($Policy.Approvers)
                $Approver.Count | Should -Be 3
                # The ARM mapping reads id and userType, which v1.0 approvers do not carry: the two
                # v1.0 approvers lose their object id entirely and no approver gets a UserType.
                $Approver[0].Id | Should -Be ''
                $Approver[1].Id | Should -Be ''
                @($Approver | Where-Object { $_.UserType }).Count | Should -Be 0
            }
        }

        It 'keeps the ARM projection when -ApproverShape Arm is named explicitly' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true
                            approvalStages = @([PSCustomObject]@{ primaryApprovers = @([PSCustomObject]@{ id = 'g1'; description = 'Approvers'; userType = 'Group' }) }) } }
                )
                $Policy = ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId '/s/pol1' -ApproverShape Arm
                $Policy.Approvers[0].Id          | Should -Be 'g1'
                $Policy.Approvers[0].UserType    | Should -Be 'Group'
                $Policy.Approvers[0].DisplayName | Should -Be 'Approvers'
            }
        }

        It 'refuses an approver shape other than Arm or Graph' {
            InModuleScope Omnicit.EntraRBAC {
                { ConvertTo-OERRoleManagementPolicy -Rules @() -PolicyId 'pol-1' -ApproverShape 'Beta' -ErrorAction Stop } |
                    Should -Throw -ErrorId 'ParameterArgumentValidationError,ConvertTo-OERRoleManagementPolicy'
            }
        }
    }
}
