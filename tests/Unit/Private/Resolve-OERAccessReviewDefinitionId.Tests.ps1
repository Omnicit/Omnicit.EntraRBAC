BeforeAll { Import-Module Omnicit.EntraRBAC -Force }
Describe 'Resolve-OERAccessReviewDefinitionId' {
    It 'returns a GUID verbatim with no Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { }
            Resolve-OERAccessReviewDefinitionId -DisplayName '55555555-5555-5555-5555-555555555555' | Should -Be '55555555-5555-5555-5555-555555555555'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
    It 'resolves a display name via filtered query' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'def-id'; displayName = 'Q3 Review' }) } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'Q3 Review' | Should -Be 'def-id'
        }
    }
    It 'returns null when none matches' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'nope' | Should -BeNullOrEmpty
        }
    }
    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'def-2'; displayName = 'R&D + Core' }) } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'R&D + Core' | Should -Be 'def-2'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
            }
        }
    }
}
