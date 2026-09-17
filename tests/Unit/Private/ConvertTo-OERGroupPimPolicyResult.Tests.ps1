BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERGroupPimPolicyResult' {
    It 'reports only the fields that were actually patched' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicyResult -GroupId 'g1' -PolicyId 'p1' -AccessType 'member' `
                -Patched @{ ActivationMaxHours = 4 } -FailedRules @()
            $Out.ActivationMaxHours | Should -Be 4
            $Out.PSObject.Properties.Name | Should -Not -Contain 'AuthenticationContextId'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'AllowPermanentEligibility'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'EligibleAlertRecipient'
        }
    }

    It 'always reports identity, Applied and FailedRules' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicyResult -GroupId 'g1' -PolicyId 'p1' -AccessType 'owner' `
                -Patched @{} -FailedRules @()
            $Out.GroupId | Should -Be 'g1'
            $Out.PolicyId | Should -Be 'p1'
            $Out.AccessType | Should -Be 'owner'
            $Out.Applied | Should -BeTrue
            @($Out.FailedRules).Count | Should -Be 0
        }
    }

    It 'reports Applied false and names the failed rules when a PATCH was rejected' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicyResult -GroupId 'g1' -PolicyId 'p1' -AccessType 'member' `
                -Patched @{ ActivationMaxHours = 4 } -FailedRules @('Expiration_EndUser_Assignment')
            $Out.Applied | Should -BeFalse
            $Out.FailedRules | Should -Contain 'Expiration_EndUser_Assignment'
        }
    }

    It 'carries the specific result type first and the shared policy type underneath' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupPimPolicyResult -GroupId 'g' -PolicyId 'p' -AccessType 'member' `
                -Patched @{} -FailedRules @()
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicyResult'
            $Out.PSTypeNames | Should -Contain 'Omnicit.EntraRBAC.GroupPimPolicy'
        }
    }
}
