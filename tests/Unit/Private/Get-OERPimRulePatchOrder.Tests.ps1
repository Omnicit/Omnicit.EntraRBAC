BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERPimRulePatchOrder' {
    # Graph validates the MFA / authentication-context exclusion asymmetrically and each rule is its
    # own PATCH, so the relative order of these two rules is the contract. Every other rule keeps the
    # position it was given.

    It 'moves a DISABLING authentication-context rule ahead of the enablement rule' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'Expiration_EndUser_Assignment' }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = $null }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @(
                'Expiration_EndUser_Assignment'
                'AuthenticationContext_EndUser_Assignment'
                'Enablement_EndUser_Assignment'
            )
        }
    }

    It 'moves an ENABLING authentication-context rule behind the enablement rule' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                @{ id = 'Expiration_Admin_Eligibility' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @(
                'Enablement_EndUser_Assignment'
                'AuthenticationContext_EndUser_Assignment'
                'Expiration_Admin_Eligibility'
            )
        }
    }

    It 'leaves an already-correct order untouched (disabling context already first)' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
        }
    }

    It 'leaves an already-correct order untouched (enabling context already last)' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @('Enablement_EndUser_Assignment', 'AuthenticationContext_EndUser_Assignment')
        }
    }

    It 'leaves the order untouched when only the authentication-context rule is present' {
        # IndexOf-style -1 for the missing partner must never reach a swap: PowerShell's negative
        # indexing would address the LAST element, which here is an unrelated rule.
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false }
                @{ id = 'Expiration_Admin_Eligibility' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Expiration_Admin_Eligibility')
        }
    }

    It 'leaves the order untouched when only the enablement rule is present' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'Expiration_EndUser_Assignment' }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @('Expiration_EndUser_Assignment', 'Enablement_EndUser_Assignment')
        }
    }

    It 'keeps every other rule at its position when it swaps the pair' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'Expiration_EndUser_Assignment' }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
                @{ id = 'Enablement_Admin_Assignment'; enabledRules = @('Justification') }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false }
                @{ id = 'Notification_Admin_Admin_Eligibility' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @(
                'Expiration_EndUser_Assignment'
                'AuthenticationContext_EndUser_Assignment'
                'Enablement_Admin_Assignment'
                'Enablement_EndUser_Assignment'
                'Notification_Admin_Admin_Eligibility'
            )
        }
    }

    It 'reads PSCustomObject rules the same way as hashtables' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
                [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $false; claimValue = '' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            @($Ordered | ForEach-Object { $_.id }) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
        }
    }

    It 'returns the same rule objects it was given, not clones' {
        InModuleScope Omnicit.EntraRBAC {
            $Enablement = [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
            $Context = @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
            $Ordered = @(Get-OERPimRulePatchOrder -Rule @($Context, $Enablement))
            $Ordered.Count | Should -Be 2
            [object]::ReferenceEquals($Ordered[0], $Enablement) | Should -BeTrue
            [object]::ReferenceEquals($Ordered[1], $Context) | Should -BeTrue
        }
    }

    It 'returns an empty array for an empty input' {
        InModuleScope Omnicit.EntraRBAC {
            # A mandatory [object[]] parameter refuses an empty collection unless it is explicitly
            # allowed, and a caller whose change set came out empty must not fail here.
            { Get-OERPimRulePatchOrder -Rule @() -ErrorAction Stop } | Should -Not -Throw
            $Ordered = @(Get-OERPimRulePatchOrder -Rule @())
            $Ordered.Count | Should -Be 0
        }
    }

    It 'emits each rule as its own pipeline object, so @() at the call site never nests the array' {
        InModuleScope Omnicit.EntraRBAC {
            $Rule = @(
                @{ id = 'Expiration_EndUser_Assignment' }
                @{ id = 'Enablement_EndUser_Assignment' }
            )
            $Ordered = @(Get-OERPimRulePatchOrder -Rule $Rule)
            $Ordered.Count | Should -Be 2
            $Ordered[0] | Should -BeOfType [hashtable]
        }
    }
}
