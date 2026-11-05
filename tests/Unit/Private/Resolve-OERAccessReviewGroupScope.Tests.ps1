BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERAccessReviewGroupScope' {
    BeforeAll {
        $script:G = '00000000-0000-0000-0000-000000000011'
    }

    It 'reads <Query> as Members' -ForEach @(
        @{ Query = '/groups/{0}/transitiveMembers' }
        @{ Query = '/v1.0/groups/{0}/transitiveMembers/microsoft.graph.user' }
        @{ Query = '/beta/groups/{0}/transitiveMembers' }
        @{ Query = '/GROUPS/{0}/TRANSITIVEMEMBERS' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Query = ($Query -f $script:G); G = $script:G } {
            param($Query, $G)
            $R = Resolve-OERAccessReviewGroupScope -Query $Query
            $R.Kind | Should -Be 'Members'
            $R.GroupId | Should -Be $G
        }
    }

    It 'reads <Query> as OtherForm' -ForEach @(
        @{ Query = "/v1.0/groups/{0}/transitiveMembers/microsoft.graph.user/?`$count=true&`$filter=(userType eq 'Guest')" }
        @{ Query = "/groups/{0}/transitiveMembers/?`$filter=(userType eq 'Guest')" }
        @{ Query = '/v1.0/groups/{0}/members' }
        @{ Query = '/groups/{0}/owners' }
        @{ Query = '/groups/{0}/transitiveMembers/' }
        @{ Query = '/groups/{0}' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Query = ($Query -f $script:G); G = $script:G } {
            param($Query, $G)
            $R = Resolve-OERAccessReviewGroupScope -Query $Query
            $R.Kind | Should -Be 'OtherForm'
            $R.GroupId | Should -Be $G
        }
    }

    It 'reads <Query> as NotGroup with no group id' -ForEach @(
        @{ Query = '/groups/not-a-guid/transitiveMembers' }
        @{ Query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'a'" }
        @{ Query = '/roleManagement/directory/roleDefinitions/R' }
        @{ Query = '/tenants/x/groups/{0}/transitiveMembers' }
        @{ Query = '' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Query = ($Query -f $script:G) } {
            param($Query)
            $R = Resolve-OERAccessReviewGroupScope -Query $Query
            $R.Kind | Should -Be 'NotGroup'
            $R.GroupId | Should -BeNullOrEmpty
        }
    }

    It 'reads the members query with the scope type <Case> as <Kind>' -ForEach @(
        @{ Case = 'the plain query scope'; Type = '#microsoft.graph.accessReviewQueryScope'; Kind = 'Members' }
        @{ Case = 'the plain query scope in other letter case'; Type = '#MICROSOFT.graph.accessreviewqueryscope'; Kind = 'Members' }
        @{ Case = 'empty'; Type = ''; Kind = 'Members' }
        @{ Case = 'the inactive users scope'; Type = '#microsoft.graph.accessReviewInactiveUsersQueryScope'; Kind = 'OtherForm' }
        @{ Case = 'an unknown scope'; Type = '#microsoft.graph.somethingNew'; Kind = 'OtherForm' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Type = $Type; Kind = $Kind; G = $script:G } {
            param($Type, $Kind, $G)
            $R = Resolve-OERAccessReviewGroupScope -Query "/v1.0/groups/$G/transitiveMembers/microsoft.graph.user" -ScopeType $Type
            $R.Kind | Should -Be $Kind
            $R.GroupId | Should -Be $G
        }
    }

    It 'reads the members query with a null scope type as Members' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ G = $script:G } {
            param($G)
            $R = Resolve-OERAccessReviewGroupScope -Query "/groups/$G/transitiveMembers" -ScopeType $null
            $R.Kind | Should -Be 'Members'
        }
    }

    It 'does not let a scope type make a query that is no group scope one' {
        InModuleScope Omnicit.EntraRBAC {
            (Resolve-OERAccessReviewGroupScope -Query '/roleManagement/directory/roleDefinitions/R' -ScopeType '#microsoft.graph.accessReviewInactiveUsersQueryScope').Kind | Should -Be 'NotGroup'
        }
    }

    It 'reads a null query as NotGroup' {
        InModuleScope Omnicit.EntraRBAC {
            (Resolve-OERAccessReviewGroupScope -Query $null).Kind | Should -Be 'NotGroup'
        }
    }

    It 'returns one tagged object carrying the query' {
        InModuleScope Omnicit.EntraRBAC {
            $R = @(Resolve-OERAccessReviewGroupScope -Query '/groups/x')
            $R.Count | Should -Be 1
            $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewGroupScope'
            $R[0].Query | Should -Be '/groups/x'
        }
    }
}
