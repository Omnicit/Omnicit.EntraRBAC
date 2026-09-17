BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERGroupEligibilityRequest' {
    It 'maps the eligibility schedule request into the shared request shape' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupEligibilityRequest -InputObject @{ id = 'esr-1'; status = 'Provisioned' } `
                -GroupId 'g1' -PrincipalId 'p1' -AccessType 'member' -Action 'adminAssign'
            $Out.RequestId | Should -Be 'esr-1'
            $Out.GroupId | Should -Be 'g1'
            $Out.PrincipalId | Should -Be 'p1'
            $Out.AccessType | Should -Be 'member'
            $Out.Action | Should -Be 'adminAssign'
            $Out.Status | Should -Be 'Provisioned'
        }
    }

    It 'tags the output with the GroupEligibility type name' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupEligibilityRequest -InputObject @{ id = 'r' } `
                -GroupId 'g' -PrincipalId 'p' -AccessType 'owner' -Action 'adminRemove'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibility'
        }
    }

    It 'emits the properties in the canonical order' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERGroupEligibilityRequest -InputObject @{ id = 'r' } `
                -GroupId 'g' -PrincipalId 'p' -AccessType 'member' -Action 'adminAssign'
            @($Out.PSObject.Properties.Name) -join ',' |
                Should -Be 'RequestId,GroupId,PrincipalId,AccessType,Action,Status'
        }
    }
}
