BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERGroupPimPolicy' {
    BeforeAll {
        $script:Rules = @(
            @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
            @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
            @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
            @{ id = 'Expiration_Admin_Eligibility'; maximumDuration = 'P365D'; isExpirationRequired = $false }
            @{ id = 'Expiration_Admin_Assignment'; maximumDuration = 'P30D'; isExpirationRequired = $true }
            @{ id = 'Enablement_Admin_Assignment'; enabledRules = @('Justification') }
            @{ id = 'Notification_Admin_Admin_Eligibility'; notificationRecipients = @('a@contoso.com') }
            @{ id = 'Notification_Admin_Admin_Assignment'; notificationRecipients = @('b@contoso.com') }
            @{ id = 'Notification_Admin_EndUser_Assignment'; notificationRecipients = @('c@contoso.com') }
        )
    }

    It 'projects every field of the read shape' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:Rules } {
            param($Rules)
            $Out = ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
            $Out.ActivationMaxHours | Should -Be 8
            $Out.AuthenticationContextId | Should -Be 'c1'
            $Out.ActivationEnabledRules | Should -Contain 'MultiFactorAuthentication'
            $Out.AllowPermanentEligibility | Should -BeTrue
            $Out.EligibleDuration | Should -Be 'P365D'
            $Out.EligibleDurationDays | Should -Be 365
            $Out.AllowPermanentActive | Should -Be $false
            $Out.ActiveDurationDays | Should -Be 30
            $Out.ActiveEnabledRules | Should -Contain 'Justification'
            $Out.Notifications.EligibleAlert | Should -Contain 'a@contoso.com'
            $Out.Notifications.ActiveAlert | Should -Contain 'b@contoso.com'
            $Out.Notifications.ActivationAlert | Should -Contain 'c@contoso.com'
            @($Out.Rules).Count | Should -Be 9
        }
    }

    It 'keeps the exact property order the read shape has always had' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:Rules } {
            param($Rules)
            $Out = ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
            @($Out.PSObject.Properties.Name) -join ',' | Should -Be 'GroupId,PolicyId,AccessType,ActivationMaxHours,AuthenticationContextId,ActivationEnabledRules,AllowPermanentEligibility,EligibleDuration,EligibleDurationDays,AllowPermanentActive,ActiveDuration,ActiveDurationDays,ActiveEnabledRules,Notifications,Rules'
        }
    }

    It 'returns genuinely empty arrays when a canonical rule id is missing from the policy' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicy -Rules @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT2H' }) `
                -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
            @($Out.ActivationEnabledRules).Count | Should -Be 0
            @($Out.Notifications.EligibleAlert).Count | Should -Be 0
            $Out.AllowPermanentEligibility | Should -BeNullOrEmpty
        }
    }

    It 'emits Notifications as a PSCustomObject, not a hashtable' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Rules = $script:Rules } {
            param($Rules)
            $Out = ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
            $Out.Notifications | Should -BeOfType [PSCustomObject]
        }
    }

    It 'tags the output with the GroupPimPolicy type name' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicy -Rules @() -GroupId 'g1' -PolicyId 'p1' -AccessType 'owner'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicy'
        }
    }

    Context 'reads any ISO 8601 duration, not just the whole-day/whole-hour forms this module emits (roundtrip PR task 13)' {
        It 'parses a year-form eligible maximumDuration into whole days instead of null' {
            InModuleScope Omnicit.EntraRBAC {
                $Out = ConvertTo-OERGroupPimPolicy -Rules @(@{ id = 'Expiration_Admin_Eligibility'; maximumDuration = 'P1Y'; isExpirationRequired = $true }) `
                    -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
                $Out.EligibleDurationDays | Should -Be 365
            }
        }

        It 'parses a month-form active maximumDuration into whole days instead of null' {
            InModuleScope Omnicit.EntraRBAC {
                $Out = ConvertTo-OERGroupPimPolicy -Rules @(@{ id = 'Expiration_Admin_Assignment'; maximumDuration = 'P6M'; isExpirationRequired = $true }) `
                    -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
                $Out.ActiveDurationDays | Should -Be 180
            }
        }

        It 'parses a composite activation maximumDuration into whole hours instead of null' {
            InModuleScope Omnicit.EntraRBAC {
                $Out = ConvertTo-OERGroupPimPolicy -Rules @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'P1DT12H' }) `
                    -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
                $Out.ActivationMaxHours | Should -Be 36
            }
        }

        It 'still returns null for a genuinely fractional duration rather than truncating it' {
            InModuleScope Omnicit.EntraRBAC {
                $Out = ConvertTo-OERGroupPimPolicy -Rules @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H30M' }) `
                    -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
                $Out.ActivationMaxHours | Should -BeNullOrEmpty
            }
        }
    }
}
