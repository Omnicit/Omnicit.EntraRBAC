BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERPimActivationConflict' {
    It 'returns Conflict when the caller asks for both an authentication context and MFA' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsAuthContext -CallerRequestsMfa `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication', 'Justification')
            $R.Action | Should -Be 'Conflict'
            $R.ActivationEnabledRules | Should -BeNullOrEmpty
            $R.Reason | Should -Match 'mutually exclusive'
        }
    }

    It 'clears MFA when the caller sets a context and the live rules carry MFA' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsAuthContext `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication', 'Justification', 'Ticketing')
            $R.Action | Should -Be 'ClearMfa'
            $R.ActivationEnabledRules | Should -Be @('Justification', 'Ticketing')
            $R.Reason | Should -Match 'c1'
        }
    }

    It 'preserves the order of the flags it keeps' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsAuthContext `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c2' `
                -EffectiveActivationEnabledRules @('Ticketing', 'MultiFactorAuthentication', 'Justification')
            $R.ActivationEnabledRules[0] | Should -Be 'Ticketing'
            $R.ActivationEnabledRules[1] | Should -Be 'Justification'
            $R.ActivationEnabledRules.Count | Should -Be 2
        }
    }

    It 'disables the authentication context when the caller asks for MFA instead' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsMfa `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication')
            $R.Action | Should -Be 'DisableAuthContext'
            $R.AuthenticationContextId | Should -Be ''
            $R.Reason | Should -Match 'c1'
        }
    }

    It 'does nothing when the authentication context rule is present but not enabled' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsMfa -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication')
            $R.Action | Should -Be 'None'
        }
    }

    It 'does nothing when the caller sets a context and the live rules carry no MFA' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -CallerRequestsAuthContext `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('Justification')
            $R.Action | Should -Be 'None'
        }
    }

    It 'leaves a pre-existing invalid combination alone when neither side was requested' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication')
            $R.Action | Should -Be 'None'
        }
    }

    It 'resolves a pre-existing invalid combination when -ResolveUnrequestedConflict is passed' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -ResolveUnrequestedConflict `
                -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' `
                -EffectiveActivationEnabledRules @('MultiFactorAuthentication', 'Justification')
            $R.Action | Should -Be 'ClearMfa'
            $R.ActivationEnabledRules | Should -Be @('Justification')
        }
    }

    It 'tags its output' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERPimActivationConflict -EffectiveActivationEnabledRules @()
            $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.PimActivationConflict'
            $R.Action | Should -Be 'None'
        }
    }
}
