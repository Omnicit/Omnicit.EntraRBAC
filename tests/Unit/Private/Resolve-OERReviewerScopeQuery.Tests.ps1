BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERReviewerScopeQuery' {
    Context 'the unprefixed forms this module writes' {
        It 'parses ./manager as the manager reviewer with no id' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query './manager'
                $Parsed.Kind | Should -Be 'Manager'
                $Parsed.Id | Should -BeNullOrEmpty
            }
        }

        It 'parses ./manager case-insensitively' {
            InModuleScope Omnicit.EntraRBAC {
                (Resolve-OERReviewerScopeQuery -Query './Manager').Kind | Should -Be 'Manager'
            }
        }

        It 'parses /users/{id}' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query '/users/00000000-0000-0000-0000-000000000049'
                $Parsed.Kind | Should -Be 'User'
                $Parsed.Id | Should -Be '00000000-0000-0000-0000-000000000049'
            }
        }

        It 'parses /groups/{id}' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query '/groups/grp-1'
                $Parsed.Kind | Should -Be 'Group'
                $Parsed.Id | Should -Be 'grp-1'
            }
        }

        It 'parses the /groups/{id}/transitiveMembers form Resolve-OERReviewerScope writes' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query '/groups/grp-1/transitiveMembers'
                $Parsed.Kind | Should -Be 'Group'
                $Parsed.Id | Should -Be 'grp-1'
            }
        }
    }

    Context 'the API-version-prefixed forms Microsoft Graph returns on read' {
        # The live string that exposed the defect. Graph normalizes a scope written as '/users/{id}'
        # into '/v1.0/users/{id}', so the anchored '^/users/' parse this helper replaced matched
        # nothing on any real tenant. Kept verbatim, not sanitized, so the regression is proven
        # against the shape actually observed.
        It 'parses the live /v1.0/users/{id} form Graph returned for a real reviewer' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query '/v1.0/users/00000000-0000-0000-0000-000000000049'
                $Parsed.Kind | Should -Be 'User'
                $Parsed.Id | Should -Be '00000000-0000-0000-0000-000000000049'
            }
        }

        It 'parses /beta/users/{id}' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query '/beta/users/00000000-0000-0000-0000-000000000049'
                $Parsed.Kind | Should -Be 'User'
                $Parsed.Id | Should -Be '00000000-0000-0000-0000-000000000049'
            }
        }

        It 'parses /v1.0/groups/{id} and /beta/groups/{id}/transitiveMembers' {
            InModuleScope Omnicit.EntraRBAC {
                $Prefixed = Resolve-OERReviewerScopeQuery -Query '/v1.0/groups/grp-1'
                $Prefixed.Kind | Should -Be 'Group'
                $Prefixed.Id | Should -Be 'grp-1'

                $Transitive = Resolve-OERReviewerScopeQuery -Query '/beta/groups/grp-1/transitiveMembers'
                $Transitive.Kind | Should -Be 'Group'
                $Transitive.Id | Should -Be 'grp-1'
            }
        }

        It 'yields the same Kind and Id with and without the version prefix' {
            InModuleScope Omnicit.EntraRBAC {
                $Bare     = Resolve-OERReviewerScopeQuery -Query '/users/00000000-0000-0000-0000-000000000049'
                $Prefixed = Resolve-OERReviewerScopeQuery -Query '/v1.0/users/00000000-0000-0000-0000-000000000049'
                $Prefixed.Kind | Should -Be $Bare.Kind
                $Prefixed.Id | Should -Be $Bare.Id
            }
        }
    }

    Context 'forms that must stay unparsed' {
        # The prefix tolerance must not degenerate into "skip anything before /users/". Each of these
        # would be accepted by an unanchored match and must not be.
        It 'reports <Query> as Unparsed with a null id' -ForEach @(
            @{ Query = './owners' }
            @{ Query = '/servicePrincipals/sp-1/owners' }
            @{ Query = "/users?`$filter=startswith(displayName,'a')" }
            @{ Query = '/tenants/t-1/users/usr-1' }
            @{ Query = 'v1.0/users/usr-1' }
            @{ Query = '/v1.0users/usr-1' }
            @{ Query = '/betausers/usr-1' }
            @{ Query = '/users/usr-1/manager' }
            @{ Query = 'nonsense' }
            @{ Query = '' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Query = $Query } {
                param($Query)
                $Parsed = Resolve-OERReviewerScopeQuery -Query $Query
                $Parsed.Kind | Should -Be 'Unparsed'
                $Parsed.Id | Should -BeNullOrEmpty
            }
        }

        It 'reports a null query as Unparsed rather than throwing' {
            InModuleScope Omnicit.EntraRBAC {
                $Parsed = Resolve-OERReviewerScopeQuery -Query $null
                $Parsed.Kind | Should -Be 'Unparsed'
            }
        }
    }

    Context 'output contract' {
        It 'always returns exactly one tagged object carrying the original query' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = @(Resolve-OERReviewerScopeQuery -Query '/v1.0/users/usr-1')
                $Result.Count | Should -Be 1
                $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ReviewerScopeQuery'
                $Result[0].Query | Should -Be '/v1.0/users/usr-1'
            }
        }

        It 'matches ./manager BEFORE any user or group branch' {
            # Ordering guard. './manager' cannot reach the user/group patterns today, but the ordering
            # is a stated contract of the helper, so assert the Kind rather than trusting the shape of
            # the current regexes.
            InModuleScope Omnicit.EntraRBAC {
                (Resolve-OERReviewerScopeQuery -Query './manager').Kind | Should -Not -Be 'User'
                (Resolve-OERReviewerScopeQuery -Query './manager').Kind | Should -Not -Be 'Group'
                (Resolve-OERReviewerScopeQuery -Query './manager').Kind | Should -Be 'Manager'
            }
        }
    }
}
