BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAccessReviewDecision' {
    It 'tags the output and maps Decision and Principal from nested properties' {
        InModuleScope $script:moduleName {
            $raw = @{
                id              = 'dec-1'
                decision        = 'Approve'
                justification   = 'Still needs access'
                reviewedBy      = @{ displayName = 'Alice Smith' }
                reviewedDateTime = '2026-07-10T09:00:00Z'
                appliedBy       = @{ displayName = 'Bob Jones' }
                applyResult     = 'Applied'
                principal       = @{ displayName = 'Carol White' }
                resource        = @{ displayName = 'HR Access Package' }
                recommendation  = 'Approve'
            }
            $o = ConvertTo-OERAccessReviewDecision -InputObject $raw
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDecision'
            $o.Decision | Should -Be 'Approve'
            $o.Principal | Should -Be 'Carol White'
        }
    }

    It 'maps all nested displayName fields correctly' {
        InModuleScope $script:moduleName {
            $raw = @{
                id               = 'dec-2'
                decision         = 'Deny'
                justification    = 'No longer required'
                reviewedBy       = @{ displayName = 'Reviewer One' }
                reviewedDateTime = '2026-07-11T10:00:00Z'
                appliedBy        = @{ displayName = 'Admin User' }
                applyResult      = 'Applied'
                principal        = @{ displayName = 'Target User' }
                resource         = @{ displayName = 'Sales Package' }
                recommendation   = 'Deny'
            }
            $o = ConvertTo-OERAccessReviewDecision -InputObject $raw
            $o.ReviewedBy | Should -Be 'Reviewer One'
            $o.AppliedBy | Should -Be 'Admin User'
            $o.Resource | Should -Be 'Sales Package'
            $o.Recommendation | Should -Be 'Deny'
            $o.ApplyResult | Should -Be 'Applied'
            $o.Justification | Should -Be 'No longer required'
            $o.ReviewedDateTime | Should -Be '2026-07-11T10:00:00Z'
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $raw = @{
                id               = 'dec-3'
                decision         = 'NotReviewed'
                justification    = ''
                reviewedBy       = @{ displayName = '' }
                reviewedDateTime = $null
                appliedBy        = @{ displayName = '' }
                applyResult      = 'New'
                principal        = @{ displayName = 'Pending User' }
                resource         = @{ displayName = 'Finance Package' }
                recommendation   = 'Approve'
            }
            $o = $raw | ConvertTo-OERAccessReviewDecision
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDecision'
            $o.Id | Should -Be 'dec-3'
            $o.Decision | Should -Be 'NotReviewed'
        }
    }

    It 'surfaces the principal and resource as an id plus a DisplayName pair' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAccessReviewDecision -InputObject @{
                id            = 'd1'
                decision      = 'Approve'
                principal     = @{ id = 'p1'; displayName = 'Ada Lovelace' }
                resource      = @{ id = 'r1'; displayName = 'Sales' }
                reviewedBy    = @{ id = 'rev1'; displayName = 'Bo Reviewer' }
                appliedBy     = @{ id = 'app1'; displayName = 'Cy Applier' }
                applyResult   = 'AppliedSuccessfully'
            }
            $Out.PrincipalId | Should -Be 'p1'
            $Out.PrincipalDisplayName | Should -Be 'Ada Lovelace'
            $Out.ResourceId | Should -Be 'r1'
            $Out.ResourceDisplayName | Should -Be 'Sales'
            $Out.ReviewedByDisplayName | Should -Be 'Bo Reviewer'
            $Out.AppliedByDisplayName | Should -Be 'Cy Applier'
        }
    }

    It 'keeps the historical bare-noun properties working as aliases' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAccessReviewDecision -InputObject @{
                id = 'd1'; principal = @{ id = 'p1'; displayName = 'Ada' }; resource = @{ id = 'r1'; displayName = 'Sales' }
                reviewedBy = @{ displayName = 'Bo' }; appliedBy = @{ displayName = 'Cy' }
            }
            $Out.Principal | Should -Be 'Ada'
            $Out.Resource | Should -Be 'Sales'
            $Out.ReviewedBy | Should -Be 'Bo'
            $Out.AppliedBy | Should -Be 'Cy'
            $Out.PSObject.Properties['Principal'].MemberType | Should -Be 'AliasProperty'
        }
    }
}
