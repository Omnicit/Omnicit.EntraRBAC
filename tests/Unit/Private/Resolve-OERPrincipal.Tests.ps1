BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERPrincipal' {
    It 'resolves a user UPN through Resolve-OERUserId and tags PrincipalType User' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERUserId { 'aaaa0000-0000-0000-0000-000000000001' }
            $Out = Resolve-OERPrincipal -User 'anna@contoso.com'
            $Out.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
            $Out.PrincipalType | Should -Be 'User'
        }
    }

    It 'resolves a group display name through Resolve-OERGroupId and tags PrincipalType Group' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERGroupId { 'bbbb0000-0000-0000-0000-000000000002' }
            $Out = Resolve-OERPrincipal -Group 'role_sec_admins'
            $Out.PrincipalId | Should -Be 'bbbb0000-0000-0000-0000-000000000002'
            $Out.PrincipalType | Should -Be 'Group'
        }
    }

    It 'treats a service principal GUID as the object id without a Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERApplicationId { throw 'should not be called' }
            $Out = Resolve-OERPrincipal -ServicePrincipal 'cccc0000-0000-0000-0000-000000000003'
            $Out.PrincipalId | Should -Be 'cccc0000-0000-0000-0000-000000000003'
            $Out.PrincipalType | Should -Be 'ServicePrincipal'
            Should -Invoke Resolve-OERApplicationId -Times 0 -Exactly
        }
    }

    It 'resolves a service principal display name through Resolve-OERApplicationId' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERApplicationId { 'dddd0000-0000-0000-0000-000000000004' }
            $Out = Resolve-OERPrincipal -ServicePrincipal 'Contoso Automation'
            $Out.PrincipalId | Should -Be 'dddd0000-0000-0000-0000-000000000004'
            $Out.PrincipalType | Should -Be 'ServicePrincipal'
        }
    }

    It 'throws on not-found and on ambiguous/missing input' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERUserId { $null }
            { Resolve-OERPrincipal -User 'ghost@contoso.com' } | Should -Throw "*'ghost@contoso.com'*"
            { Resolve-OERPrincipal } | Should -Throw '*requires one of*'
            { Resolve-OERPrincipal -User 'a' -Group 'b' } | Should -Throw '*only one of*'
        }
    }
}
