BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    Context 'OnPremisesSyncEnabled (A15)' {
        It 'carries <Case> as <Expected>' -ForEach @(
            @{ Case = 'a synced group (true)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $true }; Expected = $true }
            @{ Case = 'a no-longer-synced group (false)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $false }; Expected = $false }
            @{ Case = 'a cloud group (null)'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = $null }; Expected = $null }
            @{ Case = 'an answer without the key'; Raw = @{ id = 'g-1'; displayName = 'a' }; Expected = $null }
            @{ Case = 'a non-boolean value'; Raw = @{ id = 'g-1'; displayName = 'a'; onPremisesSyncEnabled = 'false' }; Expected = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw; Expected = $Expected } {
                param($Raw, $Expected)
                $G = ConvertTo-OERGroup -InputObject $Raw
                @($G.PSObject.Properties.Name) | Should -Contain 'OnPremisesSyncEnabled'
                if ($null -eq $Expected) { $G.OnPremisesSyncEnabled | Should -BeNullOrEmpty }
                else { $G.OnPremisesSyncEnabled | Should -BeOfType [bool]; $G.OnPremisesSyncEnabled | Should -Be $Expected }
            }
        }
    }
}
