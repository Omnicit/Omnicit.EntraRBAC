BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERPimRuleSet' {
    # The '@odata.type' assertions below are WIRE-FORMAT pins, not redundancy. Graph accepts a rule
    # whose discriminator does not match the fields it carries, so a typo yields a policy the tenant
    # takes but that does not do what was intended -- and no mocked test would ever notice, because
    # the string only has to survive a round trip to a Mock. Every distinct literal emitted by
    # New-OERPimRuleSet is therefore pinned once per OCCURRENCE, not once per literal:
    # ExpirationRule on Expiration_EndUser_Assignment, Expiration_Admin_Eligibility and
    # Expiration_Admin_Assignment; EnablementRule on Enablement_EndUser_Assignment and
    # Enablement_Admin_Assignment; AuthenticationContextRule on
    # AuthenticationContext_EndUser_Assignment (which had ZERO hits repo-wide before this change);
    # NotificationRule on Notification_Admin_Admin_Eligibility; ApprovalRule on
    # Approval_EndUser_Assignment.
    It 'emits only the activation expiration rule when only ActivationMaxHours is supplied' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -ActivationMaxHours 8
            @($Rules).Count | Should -Be 1
            $Rules[0].id | Should -Be 'Expiration_EndUser_Assignment'
            $Rules[0].maximumDuration | Should -Be 'PT8H'
            $Rules[0].'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
        }
    }

    It 'emits the activation enablement rule with the requested enabledRules' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -ActivationEnabledRules @('Justification', 'MultiFactorAuthentication')
            $R = $Rules | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }
            $R.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            $R.enabledRules | Should -Contain 'Justification'
            $R.enabledRules | Should -Contain 'MultiFactorAuthentication'
            $R.target.caller | Should -Be 'EndUser'
            $R.target.level | Should -Be 'Assignment'
        }
    }

    It 'emits the active enablement rule on the admin/assignment target' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -ActiveEnabledRules @('MultiFactorAuthentication')
            $R = $Rules | Where-Object { $_.id -eq 'Enablement_Admin_Assignment' }
            $R.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            $R.enabledRules | Should -Contain 'MultiFactorAuthentication'
            $R.target.caller | Should -Be 'Admin'
            $R.target.level | Should -Be 'Assignment'
        }
    }

    It 'enables the auth-context rule when a context id is supplied' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -AuthenticationContextId 'c1'
            $R = $Rules | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' }
            $R.isEnabled | Should -BeTrue
            $R.claimValue | Should -Be 'c1'
            $R.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
        }
    }

    It 'disables the auth-context rule when an empty context id is supplied' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -AuthenticationContextId ''
            $R = $Rules | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' }
            $R.isEnabled | Should -BeFalse
            $R.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
        }
    }

    It 'requires eligible expiration by default and allows permanent when requested' {
        InModuleScope $script:moduleName {
            $Default = New-OERPimRuleSet -EligibleDuration 'P365D'
            ($Default | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).isExpirationRequired | Should -BeTrue

            $Perm = New-OERPimRuleSet -EligibleDuration 'P365D' -AllowPermanentEligibility
            $E = $Perm | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }
            $E.isExpirationRequired | Should -BeFalse
            $E.maximumDuration | Should -Be 'P365D'
            $E.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
        }
    }

    It 'allows permanent active assignment when requested' {
        InModuleScope $script:moduleName {
            $Perm = New-OERPimRuleSet -ActiveDuration 'P180D' -AllowPermanentActive
            ($Perm | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' }).isExpirationRequired | Should -BeFalse
            ($Perm | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' }).'@odata.type' |
                Should -Be '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
        }
    }

    It 'emits the three notification rules with recipients, defaults kept, correct targets' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -EligibleAlertRecipient @('person18@example.com') -ActiveAlertRecipient @('person22@example.com') -ActivationAlertRecipient @('person24@example.com')
            $Elig = $Rules | Where-Object { $_.id -eq 'Notification_Admin_Admin_Eligibility' }
            $Elig.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'
            $Elig.notificationType | Should -Be 'Email'
            $Elig.recipientType | Should -Be 'Admin'
            $Elig.notificationLevel | Should -Be 'All'
            $Elig.isDefaultRecipientsEnabled | Should -BeTrue
            $Elig.notificationRecipients | Should -Contain 'person18@example.com'
            $Elig.target.level | Should -Be 'Eligibility'
            ($Rules | Where-Object { $_.id -eq 'Notification_Admin_Admin_Assignment' }).target.level | Should -Be 'Assignment'
            $Act = $Rules | Where-Object { $_.id -eq 'Notification_Admin_EndUser_Assignment' }
            $Act.target.caller | Should -Be 'EndUser'
            $Act.notificationRecipients | Should -Contain 'person24@example.com'
        }
    }

    It 'emits nothing when no parameters are supplied' {
        InModuleScope $script:moduleName {
            @(New-OERPimRuleSet).Count | Should -Be 0
        }
    }

    It 'emits the full set when every input is supplied' {
        InModuleScope $script:moduleName {
            $Rules = New-OERPimRuleSet -ActivationMaxHours 8 -ActivationEnabledRules @('Justification') `
                -AuthenticationContextId 'c1' -EligibleDuration 'P365D' -ActiveDuration 'P180D' `
                -ActiveEnabledRules @('MultiFactorAuthentication') -EligibleAlertRecipient @('person18@example.com') `
                -ActiveAlertRecipient @('person22@example.com') -ActivationAlertRecipient @('person24@example.com')
            @($Rules).Count | Should -Be 9
        }
    }

    Context 'approval rule (Approval_EndUser_Assignment)' {
        It 'emits the approval rule with its @odata.type and EndUser/Assignment target' {
            InModuleScope $script:moduleName {
                $Rules = New-OERPimRuleSet -RequireApproval $true -PrimaryApprover @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'grp-1' })
                @($Rules).Count | Should -Be 1
                $R = @($Rules)[0]
                $R.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
                $R.id | Should -Be 'Approval_EndUser_Assignment'
                $R.target.caller | Should -Be 'EndUser'
                $R.target.level | Should -Be 'Assignment'
                @($R.target.operations) | Should -Be @('All')
                $R.setting.isApprovalRequired | Should -BeTrue
                $R.setting.approvalMode | Should -Be 'SingleStage'
                @($R.setting.approvalStages).Count | Should -Be 1
                $Stage = @($R.setting.approvalStages)[0]
                $Stage.approvalStageTimeOutInDays | Should -Be 1
                $Stage.isApproverJustificationRequired | Should -BeTrue
                @($Stage.primaryApprovers).Count | Should -Be 1
                @($Stage.primaryApprovers)[0].groupId | Should -Be 'grp-1'
                @($Stage.primaryApprovers)[0].'@odata.type' | Should -Be '#microsoft.graph.groupMembers'
                # Neither the setting nor the stage carries a discriminator: the approvers carry their
                # own, and the other rules send their target without one either.
                $R.setting.Keys | Should -Not -Contain '@odata.type'
                $Stage.Keys | Should -Not -Contain '@odata.type'
            }
        }

        It 'does not emit the approval rule when no approval parameter is bound' {
            InModuleScope $script:moduleName {
                $Rules = New-OERPimRuleSet -ActivationMaxHours 8
                @($Rules | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }).Count | Should -Be 0
            }
        }

        It 'carries undeclared live stage fields and approvers when only RequireApproval is bound' {
            InModuleScope $script:moduleName {
                # Beta shape: a group approver read from beta has id and no groupId.
                $Live = @{
                    setting = @{
                        isApprovalRequired               = $false
                        isRequestorJustificationRequired = $false
                        approvalMode                     = 'SingleStage'
                        approvalStages                   = @(@{
                                approvalStageTimeOutInDays      = 3
                                isApproverJustificationRequired = $false
                                escalationTimeInMinutes         = 0
                                isEscalationEnabled             = $false
                                primaryApprovers                = @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1'; description = 'A' })
                                escalationApprovers             = @()
                            })
                    }
                }
                $R = @(New-OERPimRuleSet -RequireApproval $true -LiveApprovalRule $Live)[0]
                $R.setting.isApprovalRequired | Should -BeTrue
                $R.setting.isRequestorJustificationRequired | Should -BeFalse
                $R.setting.isApprovalRequiredForExtension | Should -BeFalse
                $Stage = @($R.setting.approvalStages)[0]
                $Stage.approvalStageTimeOutInDays | Should -Be 3
                $Stage.isApproverJustificationRequired | Should -BeFalse
                @($Stage.primaryApprovers).Count | Should -Be 1
                $Approver = @($Stage.primaryApprovers)[0]
                $Approver.groupId | Should -Be 'grp-1'
                $Approver.'@odata.type' | Should -Be '#microsoft.graph.groupMembers'
                $Approver.Keys | Should -Not -Contain 'id'
                @($Stage.escalationApprovers).Count | Should -Be 0
            }
        }

        It 'replaces the primary approvers but keeps the live stage fields when PrimaryApprover is bound' {
            InModuleScope $script:moduleName {
                $Live = @{
                    setting = @{
                        isApprovalRequired               = $true
                        isApprovalRequiredForExtension   = $true
                        isRequestorJustificationRequired = $false
                        approvalMode                     = 'SingleStage'
                        approvalStages                   = @(@{
                                approvalStageTimeOutInDays      = 2
                                isApproverJustificationRequired = $false
                                escalationTimeInMinutes         = 30
                                isEscalationEnabled             = $true
                                primaryApprovers                = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1' })
                                escalationApprovers             = @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-esc' })
                            })
                    }
                }
                $New = @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'grp-2' })
                $R = @(New-OERPimRuleSet -RequireApproval $true -PrimaryApprover $New -LiveApprovalRule $Live)[0]
                $R.setting.isApprovalRequiredForExtension | Should -BeTrue
                $R.setting.isRequestorJustificationRequired | Should -BeFalse
                $Stage = @($R.setting.approvalStages)[0]
                $Stage.approvalStageTimeOutInDays | Should -Be 2
                $Stage.isApproverJustificationRequired | Should -BeFalse
                $Stage.escalationTimeInMinutes | Should -Be 30
                $Stage.isEscalationEnabled | Should -BeTrue
                @($Stage.primaryApprovers).Count | Should -Be 1
                @($Stage.primaryApprovers)[0].groupId | Should -Be 'grp-2'
                @($Stage.primaryApprovers | Where-Object { $_.userId -eq 'user-1' -or $_.id -eq 'user-1' }).Count | Should -Be 0
                @($Stage.escalationApprovers).Count | Should -Be 1
                @($Stage.escalationApprovers)[0].groupId | Should -Be 'grp-esc'
            }
        }

        It 'forces isApprovalRequired true when approvers are supplied' {
            InModuleScope $script:moduleName {
                $R = @(New-OERPimRuleSet -RequireApproval $false -PrimaryApprover @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'user-2' }))[0]
                $R.setting.isApprovalRequired | Should -BeTrue
                @(@($R.setting.approvalStages)[0].primaryApprovers)[0].userId | Should -Be 'user-2'
            }
        }

        It 'passes an approver kind it does not know through unchanged' {
            InModuleScope $script:moduleName {
                $Manager = @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
                $Live = @{
                    setting = @{
                        isApprovalRequired = $true
                        approvalMode       = 'SingleStage'
                        approvalStages     = @(@{
                                approvalStageTimeOutInDays = 1
                                primaryApprovers           = @($Manager, @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1' })
                            })
                    }
                }
                $R = @(New-OERPimRuleSet -RequireApproval $true -LiveApprovalRule $Live)[0]
                $Primary = @(@($R.setting.approvalStages)[0].primaryApprovers)
                $Primary.Count | Should -Be 2
                $Kept = @($Primary | Where-Object { [object]::ReferenceEquals($_, $Manager) })
                $Kept.Count | Should -Be 1
                $Kept[0].Keys.Count | Should -Be 2
                $Kept[0].managerLevel | Should -Be 1
                @($Primary | Where-Object { $_.userId -eq 'user-1' }).Count | Should -Be 1
            }
        }

        It 'sends no stage when approval is off and the live rule has none' {
            InModuleScope $script:moduleName {
                $R = @(New-OERPimRuleSet -RequireApproval $false -LiveApprovalRule @{ setting = @{ approvalStages = @() } })[0]
                $R.id | Should -Be 'Approval_EndUser_Assignment'
                $R.setting.isApprovalRequired | Should -BeFalse
                $R.setting.approvalStages.Count | Should -Be 0
                # An empty collection, never $null: Graph needs the key present as [] on the wire.
                $R.setting.Keys | Should -Contain 'approvalStages'
                $R.setting.approvalStages -is [array] | Should -BeTrue
            }
        }

        It 'defaults a NoApproval live mode to SingleStage' {
            InModuleScope $script:moduleName {
                $R = @(New-OERPimRuleSet -RequireApproval $true -PrimaryApprover @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'user-3' }) `
                        -LiveApprovalRule @{ setting = @{ approvalMode = 'NoApproval'; approvalStages = @() } })[0]
                $R.setting.approvalMode | Should -Be 'SingleStage'
            }
        }

        It 'emits the approval rule between the admin enablement rule and the notification rules' {
            InModuleScope $script:moduleName {
                $Rules = New-OERPimRuleSet -ActiveEnabledRules @('Justification') -RequireApproval $false `
                    -EligibleAlertRecipient @('person18@example.com')
                @($Rules).id | Should -Be @('Enablement_Admin_Assignment', 'Approval_EndUser_Assignment', 'Notification_Admin_Admin_Eligibility')
            }
        }
    }
}
