BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERPermanentPolicyState' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'Eligible kind' {
        It 'reports PermanentAllowed false when Expiration_Admin_Eligibility requires expiration' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERRoleManagementPolicyId {
                    [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; EffectiveRules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
                        [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $false }
                    ) }
                }
                $State = Get-OERPermanentPolicyState -Scope '/subscriptions/s1' -RoleDefinitionId '/rd1' -Kind 'Eligible'
                $State.PolicyId         | Should -Be '/pol1'
                $State.RuleId           | Should -Be 'Expiration_Admin_Eligibility'
                $State.PermanentAllowed | Should -BeFalse
            }
        }
        It 'reports PermanentAllowed true when the eligibility rule allows permanent' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERRoleManagementPolicyId {
                    [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; EffectiveRules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }
                    ) }
                }
                (Get-OERPermanentPolicyState -Scope '/s' -RoleDefinitionId '/rd1' -Kind 'Eligible').PermanentAllowed | Should -BeTrue
            }
        }
        It 'reports PermanentAllowed true (no open) when the rule is absent' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERRoleManagementPolicyId { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; EffectiveRules = @() } }
                (Get-OERPermanentPolicyState -Scope '/s' -RoleDefinitionId '/rd1' -Kind 'Eligible').PermanentAllowed | Should -BeTrue
            }
        }
    }

    Context 'Active kind' {
        It 'inspects Expiration_Admin_Assignment for -Kind Active' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERRoleManagementPolicyId {
                    [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; EffectiveRules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }
                        [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $true }
                    ) }
                }
                $State = Get-OERPermanentPolicyState -Scope '/s' -RoleDefinitionId '/rd1' -Kind 'Active'
                $State.RuleId           | Should -Be 'Expiration_Admin_Assignment'
                $State.PermanentAllowed | Should -BeFalse
            }
        }
    }

    It 'propagates a Get-OERRoleManagementPolicyId failure' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERRoleManagementPolicyId { throw 'no policy' }
            { Get-OERPermanentPolicyState -Scope '/s' -RoleDefinitionId '/rd1' -Kind 'Eligible' } | Should -Throw
        }
    }
}
