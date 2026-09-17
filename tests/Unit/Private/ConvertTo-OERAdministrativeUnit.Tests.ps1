BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAdministrativeUnit' {
    It 'tags the output object and maps core properties' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id = 'au-1'; displayName = 'au_hr'; description = 'HR unit'
                membershipType = 'Assigned'; isMemberManagementRestricted = $true; visibility = 'HiddenMembership'
            }
            $Out = ConvertTo-OERAdministrativeUnit -InputObject $Raw
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnit'
            $Out.Id | Should -Be 'au-1'
            $Out.DisplayName | Should -Be 'au_hr'
            $Out.MembershipType | Should -Be 'Assigned'
            $Out.IsMemberManagementRestricted | Should -BeTrue
            $Out.Visibility | Should -Be 'HiddenMembership'
        }
    }

    It 'defaults MembershipType to Assigned when the Graph object omits it' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnit -InputObject @{ id = 'au-2'; displayName = 'au_x' }
            $Out.MembershipType | Should -Be 'Assigned'
            $Out.IsMemberManagementRestricted | Should -BeFalse
        }
    }

    It 'maps dynamic membership fields' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnit -InputObject @{
                id = 'au-3'; displayName = 'au_dyn'; membershipType = 'Dynamic'
                membershipRule = '(user.country -eq "SE")'; membershipRuleProcessingState = 'On'
            }
            $Out.MembershipType | Should -Be 'Dynamic'
            $Out.MembershipRule | Should -Be '(user.country -eq "SE")'
            $Out.MembershipRuleProcessingState | Should -Be 'On'
        }
    }
}
