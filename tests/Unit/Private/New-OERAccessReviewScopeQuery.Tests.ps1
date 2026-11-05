BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OERAccessReviewScopeQuery' {
    It 'builds the verified v1.0 access-package scope object (assignments + relationship filter)' {
        InModuleScope Omnicit.EntraRBAC {
            $s = New-OERAccessReviewScopeQuery -AccessPackageId 'ap1' -AssignmentPolicyId 'pol1'
            $s.'@odata.type' | Should -Be '#microsoft.graph.accessReviewQueryScope'
            $s.queryType     | Should -Be 'MicrosoftGraph'
            $s.query | Should -Be "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'ap1' and assignmentPolicy/id eq 'pol1'"
        }
    }
    It 'targets the v1.0 assignments collection, not the beta accessPackageAssignments name' {
        InModuleScope Omnicit.EntraRBAC {
            $s = New-OERAccessReviewScopeQuery -AccessPackageId 'ap1' -AssignmentPolicyId 'pol1'
            $s.query | Should -Match '/entitlementManagement/assignments\?'
            $s.query | Should -Not -Match 'accessPackageAssignments'
        }
    }
    It 'builds the group-members scope object for -GroupId' {
        InModuleScope Omnicit.EntraRBAC {
            $s = New-OERAccessReviewScopeQuery -GroupId '00000000-0000-0000-0000-000000000011'
            $s.Keys.Count    | Should -Be 3
            $s.'@odata.type' | Should -Be '#microsoft.graph.accessReviewQueryScope'
            $s.queryType     | Should -Be 'MicrosoftGraph'
            $s.query         | Should -Be '/groups/00000000-0000-0000-0000-000000000011/transitiveMembers'
        }
    }
    It 'refuses -GroupId combined with the access package parameters' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERAccessReviewScopeQuery -GroupId 'g' -AccessPackageId 'a' -AssignmentPolicyId 'p' } | Should -Throw
        }
    }
    It 'escapes single quotes in ids' {
        InModuleScope Omnicit.EntraRBAC {
            $s = New-OERAccessReviewScopeQuery -AccessPackageId "a'b" -AssignmentPolicyId 'p'
            $s.query | Should -BeLike "*accessPackage/id eq 'a''b'*"
        }
    }
}
