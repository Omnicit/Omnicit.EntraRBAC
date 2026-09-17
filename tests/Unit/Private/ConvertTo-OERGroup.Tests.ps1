BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERGroup' {
    It 'maps a Graph group hashtable to a tagged object' {
        InModuleScope $script:moduleName {
            $Graph = @{
                id = 'gid-1'; displayName = 'role_sec_identity_administrator'
                description = 'Core identity admin'; mailNickname = 'role_sec_identity_administrator'
                securityEnabled = $true; isAssignableToRole = $true
                groupTypes = @(); membershipRule = $null
            }
            $Out = ConvertTo-OERGroup -InputObject $Graph
            $Out.Id | Should -Be 'gid-1'
            $Out.DisplayName | Should -Be 'role_sec_identity_administrator'
            $Out.IsAssignableToRole | Should -BeTrue
            $Out.GroupType | Should -Be 'RoleEnabled'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Group'
        }
    }

    It 'classifies a dynamic security group as Dynamic' {
        InModuleScope $script:moduleName {
            $Graph = @{ id = 'g2'; displayName = 'dyn'; securityEnabled = $true; isAssignableToRole = $false
                groupTypes = @('DynamicMembership'); membershipRule = '(user.department -eq "IT")' }
            (ConvertTo-OERGroup -InputObject $Graph).GroupType | Should -Be 'Dynamic'
        }
    }

    It 'classifies a plain security group as Regular' {
        InModuleScope $script:moduleName {
            $Graph = @{ id = 'g3'; displayName = 'reg'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            (ConvertTo-OERGroup -InputObject $Graph).GroupType | Should -Be 'Regular'
        }
    }

    It 'exposes MembershipRuleProcessingState on the converted group' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $G = ConvertTo-OERGroup -InputObject ([PSCustomObject]@{
                    id = 'g-1'; displayName = 'x'; groupTypes = @('DynamicMembership')
                    membershipRule = 'user.department -eq "A"'; membershipRuleProcessingState = 'Paused'
                })
            $G.MembershipRuleProcessingState | Should -BeExactly 'Paused'
        }
    }
}
