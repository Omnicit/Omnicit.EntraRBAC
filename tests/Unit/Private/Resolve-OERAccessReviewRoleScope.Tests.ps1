BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERAccessReviewRoleScope' {
    BeforeAll {
        $script:Id = '00000000-0000-0000-0000-000000000041'
        $script:Mem = '#microsoft.graph.principalResourceMembershipsScope'
        $script:Plain = '#microsoft.graph.accessReviewQueryScope'
        $script:Inactive = '#microsoft.graph.accessReviewInactiveUsersQueryScope'
        $script:Elig = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '{0}')"
        $script:Act = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '{0}')"
        $script:Sp = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.servicePrincipal') and roleDefinitionId eq '{0}')"
    }

    BeforeAll {
        # A scope list item in the shape ConvertTo-OERAccessReviewDefinition surfaces.
        function New-Inner {
            param([string]$Query, [string]$QueryRoot = $null, [string]$ScopeType = '#microsoft.graph.accessReviewQueryScope', [string]$QueryType = 'MicrosoftGraph')
            [PSCustomObject]@{ Query = $Query; QueryType = $QueryType; QueryRoot = $QueryRoot; ScopeType = $ScopeType }
        }
    }

    Context 'the All form' {
        It 'reads the measured read-back as All with the id' {
            $P = @(New-Inner '/v1.0/users')
            $R = @(New-Inner "/beta/roleManagement/directory/roleDefinitions/$script:Id")
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $script:Mem } {
                param($P, $R, $T)
                Resolve-OERAccessReviewRoleScope -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'All'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }

        It 'reads the written form (unprefixed) as All' {
            $P = @(New-Inner '/users')
            $R = @(New-Inner "/roleManagement/directory/roleDefinitions/$script:Id" -QueryType '')
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $script:Mem } {
                param($P, $R, $T)
                Resolve-OERAccessReviewRoleScope -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'All'
        }

        It 'lower-cases an upper-case id and reads the outer type without regard to case' {
            $P = @(New-Inner '/v1.0/users')
            $R = @(New-Inner '/roleManagement/directory/roleDefinitions/AAAAAAAA-0000-0000-0000-00000000000B')
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $script:Mem.ToUpperInvariant() } {
                param($P, $R, $T)
                Resolve-OERAccessReviewRoleScope -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'All'
            $Out.RoleDefinitionId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000b'
        }

        It 'does not read it as All without the memberships scope type (<Case>)' -ForEach @(
            @{ Case = 'plain type'; Type = '#microsoft.graph.accessReviewQueryScope' }
            @{ Case = 'null type'; Type = $null }
            @{ Case = 'other type'; Type = '#microsoft.graph.accessReviewInactiveUsersQueryScope' }
        ) {
            $P = @(New-Inner '/v1.0/users')
            $R = @(New-Inner "/beta/roleManagement/directory/roleDefinitions/$script:Id")
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $Type } {
                param($P, $R, $T)
                Resolve-OERAccessReviewRoleScope -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'OtherForm'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }
    }

    Context 'the eligible and active forms' {
        It 'reads <Name> as written and with a prefix as <Kind>' -ForEach @(
            @{ Name = 'eligible'; Kind = 'Eligible'; Var = 'Elig' }
            @{ Name = 'active'; Kind = 'Active'; Var = 'Act' }
        ) {
            $Text = (Get-Variable -Scope Script -Name $Var).Value -f $script:Id
            foreach ($Prefix in '', '/beta', '/v1.0') {
                $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = ($Prefix + $Text) } {
                    param($Q)
                    Resolve-OERAccessReviewRoleScope -Query $Q -ScopeType '#microsoft.graph.accessReviewQueryScope'
                }
                $Out.Kind | Should -Be $Kind
                $Out.RoleDefinitionId | Should -Be $script:Id
            }
        }

        It 'reads the active query under another scope type as OtherForm' {
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = ('/beta' + ($script:Act -f $script:Id)); T = $script:Inactive } {
                param($Q, $T)
                Resolve-OERAccessReviewRoleScope -Query $Q -ScopeType $T
            }
            $Out.Kind | Should -Be 'OtherForm'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }

        It 'reads the service principal query at the top level as OtherForm' {
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = ($script:Sp -f $script:Id) } {
                param($Q)
                Resolve-OERAccessReviewRoleScope -Query $Q
            }
            $Out.Kind | Should -Be 'OtherForm'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }
    }

    Context 'forms that are not All' {
        It 'reads a <Case> as OtherForm with the id' -ForEach @(
            @{ Case = 'guest principal scope'; Mode = 'guest' }
            @{ Case = 'second principal scope'; Mode = 'two' }
            @{ Case = 'principal queryRoot'; Mode = 'pqroot' }
            @{ Case = 'resource queryRoot'; Mode = 'rqroot' }
            @{ Case = 'resource query with a trailing slash'; Mode = 'slash' }
            @{ Case = 'inner scope of another type'; Mode = 'innertype' }
            @{ Case = 'principal query with a trailing slash'; Mode = 'pslash' }
            @{ Case = 'inner query type other than MicrosoftGraph'; Mode = 'qtype' }
            @{ Case = 'second resource scope'; Mode = 'tworesources' }
            @{ Case = 'top-level query beside the scopes'; Mode = 'toplevel' }
        ) {
            $ResQ = "/beta/roleManagement/directory/roleDefinitions/$script:Id"
            $P = @(New-Inner '/v1.0/users')
            $R = @(New-Inner $ResQ)
            $Q = $null
            switch ($Mode) {
                'guest' { $P = @(New-Inner "/v1.0/users?`$filter=(userType eq 'Guest')") }
                'two' { $P = @((New-Inner '/v1.0/users'), (New-Inner '/v1.0/users')) }
                'pqroot' { $P = @(New-Inner '/v1.0/users' -QueryRoot '/v1.0/groups') }
                'rqroot' { $R = @(New-Inner $ResQ -QueryRoot '/v1.0/groups') }
                'slash' { $R = @(New-Inner ($ResQ + '/')) }
                'innertype' { $P = @(New-Inner '/v1.0/users' -ScopeType '#microsoft.graph.accessReviewInactiveUsersQueryScope') }
                'pslash' { $P = @(New-Inner '/v1.0/users/') }
                'qtype' { $R = @(New-Inner $ResQ -QueryType 'Other') }
                'tworesources' { $R = @((New-Inner $ResQ), (New-Inner $ResQ)) }
                'toplevel' { $Q = '/v1.0/users' }
            }
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $script:Mem; Q = $Q } {
                param($P, $R, $T, $Q)
                Resolve-OERAccessReviewRoleScope -Query $Q -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'OtherForm'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }

        It 'reads the bare role definition query (example 12.1) as OtherForm' {
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = "/roleManagement/directory/roleDefinitions/$script:Id" } {
                param($Q)
                Resolve-OERAccessReviewRoleScope -Query $Q
            }
            $Out.Kind | Should -Be 'OtherForm'
            $Out.RoleDefinitionId | Should -Be $script:Id
        }
    }

    Context 'no role scope' {
        It 'reads <Case> as NotRole with no id' -ForEach @(
            @{ Case = 'a group members query'; Query = '/v1.0/groups/00000000-0000-0000-0000-000000000011/transitiveMembers/microsoft.graph.user' }
            @{ Case = 'an access package query'; Query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'a'" }
            @{ Case = 'a role query with an id that is no GUID'; Query = "/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=roleDefinitionId eq 'not-a-guid'" }
            @{ Case = 'an empty query'; Query = '' }
            @{ Case = 'a null query'; Query = $null }
        ) {
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = $Query } {
                param($Q)
                Resolve-OERAccessReviewRoleScope -Query $Q
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'reads a memberships scope whose role id is no GUID as NotRole' {
            $P = @(New-Inner '/v1.0/users')
            $R = @(New-Inner '/beta/roleManagement/directory/roleDefinitions/not-a-guid')
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $script:Mem } {
                param($P, $R, $T)
                Resolve-OERAccessReviewRoleScope -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'reads the measured <Name> text with an id that is no GUID as NotRole' -ForEach @(
            @{ Name = 'eligible'; Var = 'Elig' }
            @{ Name = 'active'; Var = 'Act' }
        ) {
            $Text = (Get-Variable -Scope Script -Name $Var).Value -f 'not-a-guid'
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = $Text } {
                param($Q)
                Resolve-OERAccessReviewRoleScope -Query $Q -ScopeType '#microsoft.graph.accessReviewQueryScope'
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'reads a top-level role query naming a non-GUID id as NotRole' {
            $Out = InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewRoleScope -Query "/roleManagement/directory/roleDefinitions/not-a-guid"
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'reads a top-level filter naming a non-GUID id as NotRole' {
            $Out = InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewRoleScope -Query "/roleManagement/directory/roleAssignmentSchedules?`$filter=roleDefinitionId eq 'not-a-guid'"
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'lower-cases an upper-case id in the measured <Name> text' -ForEach @(
            @{ Name = 'eligible'; Var = 'Elig'; Kind = 'Eligible' }
            @{ Name = 'active'; Var = 'Act'; Kind = 'Active' }
        ) {
            $Text = (Get-Variable -Scope Script -Name $Var).Value -f 'AAAAAAAA-0000-0000-0000-00000000000B'
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ Q = $Text } {
                param($Q)
                Resolve-OERAccessReviewRoleScope -Query $Q
            }
            $Out.Kind | Should -Be $Kind
            $Out.RoleDefinitionId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000b'
        }

        It 'never reads a query or scope with a final line feed as the exact form (<Case>)' -ForEach @(
            @{ Case = 'principal'; Mode = 'principal' }
            @{ Case = 'resource'; Mode = 'resource' }
            @{ Case = 'eligible'; Mode = 'eligible' }
            @{ Case = 'active'; Mode = 'active' }
        ) {
            $Q = $null; $T = $script:Mem
            $P = @(New-Inner '/v1.0/users'); $R = @(New-Inner "/beta/roleManagement/directory/roleDefinitions/$script:Id")
            switch ($Mode) {
                'principal' { $P = @(New-Inner "/users`n") }
                'resource' { $R = @(New-Inner "/roleManagement/directory/roleDefinitions/$script:Id`n") }
                'eligible' { $Q = ($script:Elig -f $script:Id) + "`n"; $T = $null; $P = @(); $R = @() }
                'active' { $Q = ($script:Act -f $script:Id) + "`n"; $T = $null; $P = @(); $R = @() }
            }
            $Out = InModuleScope Omnicit.EntraRBAC -Parameters @{ P = $P; R = $R; T = $T; Q = $Q } {
                param($P, $R, $T, $Q)
                Resolve-OERAccessReviewRoleScope -Query $Q -ScopeType $T -PrincipalScope $P -ResourceScope $R
            }
            $Out.Kind | Should -BeIn @('OtherForm', 'NotRole')
        }

        It 'accepts all-null input' {
            $Out = InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewRoleScope -Query $null -ScopeType $null -PrincipalScope $null -ResourceScope $null
            }
            $Out.Kind | Should -Be 'NotRole'
            $Out.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'accepts empty collections' {
            $Out = InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewRoleScope -Query '' -ScopeType '' -PrincipalScope @() -ResourceScope @()
            }
            $Out.Kind | Should -Be 'NotRole'
        }
    }

    It 'returns one object typed AccessReviewRoleScope' {
        $Out = InModuleScope Omnicit.EntraRBAC {
            , @(Resolve-OERAccessReviewRoleScope -Query '/x')
        }
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewRoleScope'
    }
}
