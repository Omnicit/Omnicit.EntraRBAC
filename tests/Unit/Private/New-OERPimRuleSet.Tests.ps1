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
    # NotificationRule on Notification_Admin_Admin_Eligibility.
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
}
