BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

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
}
