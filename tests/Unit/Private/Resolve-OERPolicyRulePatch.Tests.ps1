BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERPolicyRulePatch' {
    BeforeAll {
        $script:Current = @(
            [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
            [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'PT5H'; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('Justification'); target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'Enablement_Admin_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('Justification'); target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; ruleType = 'RoleManagementPolicyApprovalRule'; setting = [PSCustomObject]@{ isApprovalRequired = $false; approvalMode = 'NoApproval'; approvalStages = @() }; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; ruleType = 'RoleManagementPolicyAuthenticationContextRule'; isEnabled = $false; claimValue = ''; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            [PSCustomObject]@{ id = 'Notification_Approver_EndUser_Assignment'; ruleType = 'RoleManagementPolicyNotificationRule'; recipientType = 'Approver'; notificationLevel = 'Critical'; isDefaultRecipientsEnabled = $true; notificationRecipients = $null; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
        )
        # $script:Current has 8 rules; the helper always returns the FULL set in Rules.
    }

    It 'returns the full rule set (flat) and reports only the changed id' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ AllowPermanentEligibility = $true }
            @($plan.Rules).Count | Should -Be 8                     # full set returned, not just the change
            $plan.Rules[0] | Should -BeOfType [System.Management.Automation.PSCustomObject]  # flat, not a nested array
            @($plan.ChangedRuleId).Count | Should -Be 1
            $plan.ChangedRuleId | Should -Contain 'Expiration_Admin_Eligibility'
            $elig = $plan.Rules | Where-Object id -eq 'Expiration_Admin_Eligibility'
            $elig.isExpirationRequired | Should -Be $false
            $elig.target.level | Should -Be 'Eligibility'          # target preserved on the clone
        }
    }

    It 'does not mutate the input rules' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $null = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ AllowPermanentEligibility = $true }
            ($Current | Where-Object id -eq 'Expiration_Admin_Eligibility').isExpirationRequired | Should -BeTrue
        }
    }

    It 'adds an enablement flag without dropping the existing ones' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ RequireMfaOnActivation = $true }
            $r = $plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment'
            $r.enabledRules | Should -Contain 'MultiFactorAuthentication'
            $r.enabledRules | Should -Contain 'Justification'
        }
    }

    It 'removes an enablement flag when set to false' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ RequireJustificationOnActivation = $false }
            ($plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment').enabledRules | Should -Not -Contain 'Justification'
        }
    }

    It 'composes two enablement toggles on the same rule and reports it changed once' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ RequireMfaOnActivation = $true; RequireTicketOnActivation = $true }
            @($plan.ChangedRuleId | Where-Object { $_ -eq 'Enablement_EndUser_Assignment' }).Count | Should -Be 1
            $r = $plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment'
            $r.enabledRules | Should -Contain 'MultiFactorAuthentication'
            $r.enabledRules | Should -Contain 'Ticketing'
        }
    }

    It 'sets activation hours, eligible duration, approval+approvers, auth context, and notifications' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $note = [PSCustomObject]@{ RuleId = 'Notification_Approver_EndUser_Assignment'; NotificationLevel = 'All'; NotificationRecipients = @('person42@example.com') }
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{
                ActivationMaxHours      = 8
                EligibleDuration        = 365
                PrimaryApprovers        = @([PSCustomObject]@{ id = 'g1'; userType = 'Group'; isBackup = $false })
                AuthenticationContextId = 'c1'
                NotificationRule        = @($note)
            }
            @($plan.Rules).Count | Should -Be 8
            ($plan.Rules | Where-Object id -eq 'Expiration_EndUser_Assignment').maximumDuration | Should -Be 'PT8H'
            ($plan.Rules | Where-Object id -eq 'Expiration_Admin_Eligibility').maximumDuration | Should -Be 'P365D'
            $appr = $plan.Rules | Where-Object id -eq 'Approval_EndUser_Assignment'
            $appr.setting.isApprovalRequired | Should -BeTrue
            $appr.setting.approvalStages[0].primaryApprovers[0].id | Should -Be 'g1'
            $ctx = $plan.Rules | Where-Object id -eq 'AuthenticationContext_EndUser_Assignment'
            $ctx.isEnabled | Should -BeTrue
            $ctx.claimValue | Should -Be 'c1'
            $n = $plan.Rules | Where-Object id -eq 'Notification_Approver_EndUser_Assignment'
            $n.notificationLevel | Should -Be 'All'
            $n.notificationRecipients | Should -Contain 'person42@example.com'
            $plan.ChangedRuleId | Should -Contain 'Approval_EndUser_Assignment'
            $plan.ChangedRuleId | Should -Contain 'Notification_Approver_EndUser_Assignment'
        }
    }

    It 'adds primaryApprovers even when the cloned stage has no such property (live default-policy shape)' {
        InModuleScope Omnicit.EntraRBAC {
            # A stage with no primaryApprovers/escalationApprovers members, as a default policy returns.
            $rules = @(
                [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; ruleType = 'RoleManagementPolicyApprovalRule'
                    setting = [PSCustomObject]@{ isApprovalRequired = $false; approvalMode = 'SingleStage'
                        approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1; isApproverJustificationRequired = $true; escalationTimeInMinutes = 0; isEscalationEnabled = $false }) }
                    target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            )
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $rules -Setting @{ PrimaryApprovers = @([PSCustomObject]@{ id = 'u1'; userType = 'User'; isBackup = $false }) }
            $appr = $plan.Rules | Where-Object id -eq 'Approval_EndUser_Assignment'
            $appr.setting.isApprovalRequired | Should -BeTrue
            $appr.setting.approvalStages[0].primaryApprovers[0].id | Should -Be 'u1'
        }
    }

    It 'adds claimValue when the cloned auth-context rule lacks it (live default-policy shape)' {
        InModuleScope Omnicit.EntraRBAC {
            # A default policy returns the auth-context rule with isEnabled but NO claimValue member.
            $rules = @(
                [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; ruleType = 'RoleManagementPolicyAuthenticationContextRule'; isEnabled = $false; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            )
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $rules -Setting @{ AuthenticationContextId = 'c1' }
            $ctx = $plan.Rules | Where-Object id -eq 'AuthenticationContext_EndUser_Assignment'
            $ctx.isEnabled | Should -BeTrue
            $ctx.claimValue | Should -Be 'c1'
        }
    }

    It 'adds notificationRecipients when the cloned notification rule lacks it (live default-policy shape)' {
        InModuleScope Omnicit.EntraRBAC {
            # A default policy returns Notification_* rules with NO notificationRecipients member.
            $rules = @(
                [PSCustomObject]@{ id = 'Notification_Approver_EndUser_Assignment'; ruleType = 'RoleManagementPolicyNotificationRule'; recipientType = 'Approver'; notificationLevel = 'All'; isDefaultRecipientsEnabled = $true; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            )
            $note = [PSCustomObject]@{ RuleId = 'Notification_Approver_EndUser_Assignment'; NotificationRecipients = @('person43@example.com') }
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $rules -Setting @{ NotificationRule = @($note) }
            ($plan.Rules | Where-Object id -eq 'Notification_Approver_EndUser_Assignment').notificationRecipients | Should -Contain 'person43@example.com'
        }
    }

    Context 'MFA / authentication-context mutual exclusion' {
        BeforeAll {
            # A policy where activation requires MFA (so enabling ACRS would conflict).
            $script:MfaPolicy = @(
                [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('MultiFactorAuthentication', 'Justification'); target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
                [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; ruleType = 'RoleManagementPolicyAuthenticationContextRule'; isEnabled = $false; claimValue = ''; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            )
        }
        It 'enabling auth context clears MFA from the activation enablement rule' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:MfaPolicy } {
                param($Current)
                $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ AuthenticationContextId = 'c1' }
                ($plan.Rules | Where-Object id -eq 'AuthenticationContext_EndUser_Assignment').isEnabled | Should -BeTrue
                ($plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment').enabledRules | Should -Not -Contain 'MultiFactorAuthentication'
                ($plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment').enabledRules | Should -Contain 'Justification'
                $plan.ChangedRuleId | Should -Contain 'Enablement_EndUser_Assignment'
            }
        }
        It 'requiring MFA disables an already-enabled auth context' {
            InModuleScope Omnicit.EntraRBAC {
                $rules = @(
                    [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; ruleType = 'RoleManagementPolicyEnablementRule'; enabledRules = @('Justification'); target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
                    [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; ruleType = 'RoleManagementPolicyAuthenticationContextRule'; isEnabled = $true; claimValue = 'c1'; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
                )
                $plan = Resolve-OERPolicyRulePatch -CurrentRule $rules -Setting @{ RequireMfaOnActivation = $true }
                ($plan.Rules | Where-Object id -eq 'Enablement_EndUser_Assignment').enabledRules | Should -Contain 'MultiFactorAuthentication'
                ($plan.Rules | Where-Object id -eq 'AuthenticationContext_EndUser_Assignment').isEnabled | Should -Be $false
            }
        }
        It 'throws when both MFA and auth context are requested in one call' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:MfaPolicy } {
                param($Current)
                { Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ AuthenticationContextId = 'c1'; RequireMfaOnActivation = $true } } | Should -Throw '*mutually exclusive*'
            }
        }
    }

    It 'disables authentication context on empty string' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ AuthenticationContextId = '' }
            ($plan.Rules | Where-Object id -eq 'AuthenticationContext_EndUser_Assignment').isEnabled | Should -Be $false
        }
    }

    It 'patches the admin active-assignment expiration and enablement rules' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{
                AllowPermanentActiveAssignment = $false
                ActiveDuration                 = 180
                RequireMfaOnActiveAssignment   = $true
            }
            $exp = $plan.Rules | Where-Object id -eq 'Expiration_Admin_Assignment'
            $exp.isExpirationRequired | Should -BeTrue
            $exp.maximumDuration | Should -Be 'P180D'
            $en = $plan.Rules | Where-Object id -eq 'Enablement_Admin_Assignment'
            $en.enabledRules | Should -Contain 'MultiFactorAuthentication'
            $en.enabledRules | Should -Contain 'Justification'
        }
    }

    It 'throws when a required rule is absent from the policy' {
        InModuleScope Omnicit.EntraRBAC {
            { Resolve-OERPolicyRulePatch -CurrentRule @() -Setting @{ AllowPermanentEligibility = $true } } | Should -Throw "*no 'Expiration_Admin_Eligibility' rule*"
        }
    }

    It 'sets isApprovalRequired to false when RequireApproval is false' {
        # $script:Current's Approval_EndUser_Assignment already has isApprovalRequired = $false, so
        # asserting RequireApproval = $false against it is a genuine no-op under the Task 12
        # value-aware comparison -- it must NOT land in ChangedRuleId (the original assertion here
        # predates that fix and was asserting the touched-but-unchanged bug). Start from
        # isApprovalRequired = $true instead so the setting is a real change, which is what this test
        # is actually meant to prove: that RequireApproval = $false is correctly overlaid as $false.
        InModuleScope Omnicit.EntraRBAC {
            $Rules = @(
                [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; ruleType = 'RoleManagementPolicyApprovalRule'
                    setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'; approvalStages = @() }
                    target  = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
            )
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ RequireApproval = $false }
            $plan.ChangedRuleId | Should -Contain 'Approval_EndUser_Assignment'
            ($plan.Rules | Where-Object id -eq 'Approval_EndUser_Assignment').setting.isApprovalRequired | Should -Be $false
        }
    }

    It 'overlays only the supplied notification field (IsDefaultRecipientsEnabled)' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $note = [PSCustomObject]@{ RuleId = 'Notification_Approver_EndUser_Assignment'; IsDefaultRecipientsEnabled = $false }
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{ NotificationRule = @($note) }
            $n = $plan.Rules | Where-Object id -eq 'Notification_Approver_EndUser_Assignment'
            $n.isDefaultRecipientsEnabled | Should -Be $false
            $n.notificationLevel | Should -Be 'Critical'   # untouched field preserved
        }
    }

    It 'reports no changed ids but still returns the full set when no setting is supplied' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Current = $script:Current } {
            param($Current)
            $plan = Resolve-OERPolicyRulePatch -CurrentRule $Current -Setting @{}
            @($plan.ChangedRuleId).Count | Should -Be 0
            @($plan.Rules).Count | Should -Be 8
        }
    }

    Context 'value-aware ChangedRuleId (roundtrip PR task 12)' {
        It 'reports no changed rule when the overlaid value already equals the current one' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AllowPermanentEligibility = $false }
                @($Plan.ChangedRuleId).Count | Should -Be 0
                @($Plan.Rules).Count | Should -Be 1
            }
        }

        It 'still reports a changed rule when the value genuinely differs' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AllowPermanentEligibility = $true }
                @($Plan.ChangedRuleId) | Should -Contain 'Expiration_Admin_Eligibility'
            }
        }

        It 'ignores enabledRules ordering when deciding whether a rule changed' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification', 'MultiFactorAuthentication') }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ RequireMfaOnActivation = $true }
                @($Plan.ChangedRuleId).Count | Should -Be 0
            }
        }

        It 'still returns the complete rule set even when nothing changed' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
                    [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
                    [PSCustomObject]@{ id = 'Notification_Admin_Admin_Eligibility'; notificationLevel = 'All' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AllowPermanentEligibility = $false }
                @($Plan.Rules).Count | Should -Be 3
                @($Plan.Rules | ForEach-Object { $_.id }) | Should -Contain 'Notification_Admin_Admin_Eligibility'
            }
        }
    }

    Context 'duration input forms (audit PR6)' {
        It 'accepts an int day count for EligibleDuration' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @([PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; maximumDuration = 'P30D' })
                $Result = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ EligibleDuration = 365 }
                ($Result.Rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration | Should -Be 'P365D'
            }
        }
        It 'accepts an ISO string for EligibleDuration' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @([PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; maximumDuration = 'P30D' })
                $Result = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ EligibleDuration = 'P365D' }
                ($Result.Rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration | Should -Be 'P365D'
            }
        }
        It 'encodes ActivationMaxHours through the shared duration encoder' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT2H' })
                $Result = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ ActivationMaxHours = 8 }
                ($Result.Rules | Where-Object { $_.id -eq 'Expiration_EndUser_Assignment' }).maximumDuration | Should -Be 'PT8H'
            }
        }
    }

    Context 'authentication context and MFA mutual exclusion' {
        It 'throws the documented message when both are requested' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [pscustomobject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                    [pscustomobject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = '' }
                )
                { Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{
                        AuthenticationContextId = 'c1'; RequireMfaOnActivation = $true
                    } } | Should -Throw -ExpectedMessage 'Cannot enable both multi-factor authentication and an authentication context on activation; Azure PIM treats them as mutually exclusive. Set only one.'
            }
        }

        It 'clears MFA when only the authentication context is requested' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [pscustomobject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                    [pscustomobject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = '' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AuthenticationContextId = 'c1' }
                $Enablement = @($Plan.Rules) | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }
                @($Enablement.enabledRules) | Should -Be @('Justification')
                $Plan.ChangedRuleId | Should -Contain 'Enablement_EndUser_Assignment'
            }
        }

        It 'disables the authentication context when only MFA is requested' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [pscustomobject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                    [pscustomobject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ RequireMfaOnActivation = $true }
                $Acrs = @($Plan.Rules) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' }
                $Acrs.isEnabled | Should -BeFalse
                $Acrs.claimValue | Should -Be ''
            }
        }

        It 'still resolves a pre-existing invalid combination on an unrelated change' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [pscustomobject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                    [pscustomobject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                    [pscustomobject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT4H' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ ActivationMaxHours = 8 }
                $Enablement = @($Plan.Rules) | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }
                @($Enablement.enabledRules) | Should -Be @('Justification')
            }
        }
    }

    Context 'Graph mode (directory-role policies)' {
        # Directory-role policies live in Microsoft Graph v1.0 and share the ARM rule ids and field
        # names, so the same builder serves both transports. Two things differ: the approver shape
        # (v1.0 singleUser{userId} / groupMembers{groupId}, beta-style id as a fallback) and the
        # MFA / authentication-context convention (Graph leaves an untouched combination alone).

        It 'keys approvers on the Graph object id in Graph mode, which the ARM key cannot see' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; ruleType = 'RoleManagementPolicyApprovalRule'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'
                            approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1; isApproverJustificationRequired = $true; escalationTimeInMinutes = 0; isEscalationEnabled = $false
                                    primaryApprovers = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000001' })
                                    escalationApprovers = @() }) } }
                )
                $Setting = @{ PrimaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000002' }) }

                $Graph = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph
                @($Graph.ChangedRuleId) | Should -Contain 'Approval_EndUser_Assignment'

                # The default ARM key reads id and userType, which a v1.0 approver does not carry, so
                # both sides describe as "||False" and a genuinely different approver reads as equal.
                # That blindness is why the parameter exists.
                $Arm = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting
                @($Arm.ChangedRuleId).Count | Should -Be 0
            }
        }

        It 'keeps the Graph key through an approvalStages array of more than one stage' {
            # A one-stage approvalStages array reaches the comparison as the bare stage object (the
            # field reader unrolls a one-element array), so only a multi-stage rule walks the ARRAY
            # branch of the recursion -- which must hand the approver shape on as well.
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'Serial'
                            approvalStages = @(
                                [PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                    primaryApprovers = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000001' }) }
                                [PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                    primaryApprovers = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000003' }) }
                            ) } }
                )
                $Setting = @{ PrimaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'aaaaaaaa-0000-0000-0000-000000000002' }) }
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph
                @($Plan.ChangedRuleId) | Should -Contain 'Approval_EndUser_Assignment'
            }
        }

        It 'treats equal Graph approver sets as unchanged (id case, description and a missing isBackup ignored)' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'
                            approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                    primaryApprovers = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'bbbbbbbb-0000-0000-0000-000000000001'; description = 'Approvers'; isBackup = $false }) }) } }
                )
                $Setting = @{ PrimaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'BBBBBBBB-0000-0000-0000-000000000001' }) }
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph
                @($Plan.ChangedRuleId).Count | Should -Be 0
                # Unchanged means the ORIGINAL rule is passed through, not the clone.
                [object]::ReferenceEquals(@($Plan.Rules)[0], $Rules[0]) | Should -BeTrue
            }
        }

        It 'reads the beta-style id of a live Graph approver as its object id' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'
                            approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                    primaryApprovers = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'bbbbbbbb-0000-0000-0000-000000000001' }) }) } }
                )
                $Setting = @{ PrimaryApprovers = @(@{ groupId = 'bbbbbbbb-0000-0000-0000-000000000001' }) }
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph
                @($Plan.ChangedRuleId).Count | Should -Be 0
            }
        }

        It 'still reports a different Graph approver built by New-OERApproverObject as a change' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'
                        setting = [PSCustomObject]@{ isApprovalRequired = $true; approvalMode = 'SingleStage'
                            approvalStages = @([PSCustomObject]@{ approvalStageTimeOutInDays = 1
                                    primaryApprovers = @(New-OERApproverObject -Spec @{ Group = 'bbbbbbbb-0000-0000-0000-000000000001' }) }) } }
                )
                $Setting = @{ PrimaryApprovers = @(
                        New-OERApproverObject -Spec @{ Group = 'bbbbbbbb-0000-0000-0000-000000000001' }
                        New-OERApproverObject -Spec @{ User = 'aaaaaaaa-0000-0000-0000-000000000001' }
                    ) }
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting $Setting -ApproverShape Graph
                @($Plan.ChangedRuleId) | Should -Be @('Approval_EndUser_Assignment')
                $Sent = @(@($Plan.Rules)[0].setting.approvalStages[0].primaryApprovers)
                $Sent.Count | Should -Be 2
            }
        }

        It 'leaves a pre-existing MFA and authentication-context combination alone when told not to resolve it' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                    [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                    [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ ActivationMaxHours = 4 } -ResolveUnrequestedConflict $false
                @($Plan.ChangedRuleId) | Should -Not -Contain 'Enablement_EndUser_Assignment'
                @($Plan.ChangedRuleId) | Should -Not -Contain 'AuthenticationContext_EndUser_Assignment'
                @($Plan.ChangedRuleId) | Should -Be @('Expiration_EndUser_Assignment')
                $Plan.ConflictResolution.Action | Should -Be 'None'
                @((@($Plan.Rules) | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }).enabledRules) | Should -Contain 'MultiFactorAuthentication'

                # The default ($true, the ARM full-set PATCH) clears MFA on the same input.
                $Default = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ ActivationMaxHours = 4 }
                @($Default.ChangedRuleId) | Should -Contain 'Enablement_EndUser_Assignment'
                $Default.ConflictResolution.Action | Should -Be 'ClearMfa'
            }
        }

        It 'returns the conflict decision it applied as ConflictResolution' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @(
                    [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                    [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = '' }
                )
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AuthenticationContextId = 'c2' } -ApproverShape Graph -ResolveUnrequestedConflict $false
                $Plan.ConflictResolution.Action | Should -Be 'ClearMfa'
                $Plan.ConflictResolution.Reason | Should -Not -BeNullOrEmpty
                @($Plan.ChangedRuleId) | Should -Contain 'Enablement_EndUser_Assignment'
                @($Plan.ChangedRuleId) | Should -Contain 'AuthenticationContext_EndUser_Assignment'
            }
        }

        It 'returns a None ConflictResolution when no exclusion rule is involved' {
            InModuleScope Omnicit.EntraRBAC {
                $Rules = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' })
                $Plan = Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ ActivationMaxHours = 4 }
                $Plan.ConflictResolution.Action | Should -Be 'None'
                @($Plan.PSObject.Properties.Name) | Should -Be @('Rules', 'ChangedRuleId', 'ConflictResolution')
            }
        }

        It 'refuses an approver shape other than Arm or Graph' {
            InModuleScope Omnicit.EntraRBAC {
                # The error id pins a ValidateSet refusal, not an unknown-parameter binding failure.
                { Resolve-OERPolicyRulePatch -CurrentRule @() -Setting @{} -ApproverShape 'Beta' -ErrorAction Stop } | Should -Throw -ErrorId 'ParameterArgumentValidationError,Resolve-OERPolicyRulePatch'
            }
        }
    }
}
