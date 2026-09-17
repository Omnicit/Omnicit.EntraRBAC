BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

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
    It 'escapes single quotes in ids' {
        InModuleScope Omnicit.EntraRBAC {
            $s = New-OERAccessReviewScopeQuery -AccessPackageId "a'b" -AssignmentPolicyId 'p'
            $s.query | Should -BeLike "*accessPackage/id eq 'a''b'*"
        }
    }
}
