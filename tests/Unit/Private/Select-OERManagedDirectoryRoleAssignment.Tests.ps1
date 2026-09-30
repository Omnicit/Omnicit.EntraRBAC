BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Select-OERManagedDirectoryRoleAssignment' {
    Context 'Activated guard' {
        It 'keeps an Assigned active assignment at tenant scope and Direct' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                    AssignmentType   = 'Assigned'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
                }
                $Result = Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Active
                $Result.PrincipalId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            }
        }

        It 'drops an Activated active assignment' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                    AssignmentType   = 'Activated'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000002'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Active)
                $Result.Count | Should -Be 0
            }
        }
    }

    Context 'Direct guard' {
        It 'drops an active assignment held through a group' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Group'
                    AssignmentType   = 'Assigned'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000003'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Active)
                $Result.Count | Should -Be 0
            }
        }

        It 'drops an eligible assignment held through a group' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Group'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000004'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Eligible)
                $Result.Count | Should -Be 0
            }
        }

        It 'drops an active assignment whose MemberType is Inherited' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Inherited'
                    AssignmentType   = 'Assigned'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000005'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Active)
                $Result.Count | Should -Be 0
            }
        }

        It 'drops an eligible assignment whose MemberType is Inherited' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Inherited'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000006'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Eligible)
                $Result.Count | Should -Be 0
            }
        }
    }

    Context 'Scope guard' {
        It 'drops an administrative-unit-scoped assignment' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/administrativeUnits/11111111-1111-1111-1111-111111111111'
                    MemberType       = 'Direct'
                    AssignmentType   = 'Assigned'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000007'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Active)
                $Result.Count | Should -Be 0
            }
        }
    }

    Context 'Eligible objects carry no AssignmentType field' {
        It 'keeps an eligible object with no AssignmentType when Direct at tenant scope' {
            InModuleScope Omnicit.EntraRBAC {
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000008'
                }
                $Result = Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind Eligible
                $Result.PrincipalId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000008'
            }
        }
    }

    Context 'null and empty input' {
        It 'skips a null entry in the collection without error' {
            InModuleScope Omnicit.EntraRBAC {
                $Kept = [PSCustomObject]@{
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                    AssignmentType   = 'Assigned'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000009'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($null, $Kept) -Kind Active)
                $Result.Count | Should -Be 1
                $Result[0].PrincipalId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000009'
            }
        }

        It 'returns nothing for an empty array without error' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @() -Kind Active)
                $Result.Count | Should -Be 0
            }
        }

        It 'returns nothing when the whole -Assignment argument is null' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment $null -Kind Active)
                $Result.Count | Should -Be 0
            }
        }
    }

    Context '-Excluded returns the other side, with every reason' {
        # The same guard lines decide both sides; -Excluded names each guard that drops an assignment.
        It 'names <Expected> for a <Kind> assignment that is <Case>' -TestCases @(
            @{ Case = 'an activation'; Kind = 'Active'; Scope = '/'; MemberType = 'Direct'; AssignmentType = 'Activated'; Expected = 'Activation' }
            @{ Case = 'held through a group'; Kind = 'Active'; Scope = '/'; MemberType = 'Group'; AssignmentType = 'Assigned'; Expected = 'Group' }
            @{ Case = 'Inherited'; Kind = 'Eligible'; Scope = '/'; MemberType = 'Inherited'; AssignmentType = $null; Expected = 'Group' }
            @{ Case = 'scoped to an administrative unit'; Kind = 'Eligible'; Scope = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; MemberType = 'Direct'; AssignmentType = $null; Expected = 'Scope' }
            @{ Case = 'an activation through a group at a unit scope'; Kind = 'Active'; Scope = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; MemberType = 'Group'; AssignmentType = 'Activated'; Expected = 'Scope,Group,Activation' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Scope = $Scope; MemberType = $MemberType; AssignmentType = $AssignmentType; Expected = $Expected } {
                param($Kind, $Scope, $MemberType, $AssignmentType, $Expected)
                $Candidate = [PSCustomObject]@{
                    DirectoryScopeId = $Scope
                    MemberType       = $MemberType
                    AssignmentType   = $AssignmentType
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
                }
                $Result = @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind $Kind -Excluded)
                $Result.Count | Should -Be 1
                $Result[0].Assignment.PrincipalId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
                ($Result[0].Reason -join ',') | Should -BeExactly $Expected
                @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Candidate) -Kind $Kind).Count | Should -Be 0
            }
        }

        It 'returns nothing for a managed assignment, and skips a null entry' {
            InModuleScope Omnicit.EntraRBAC {
                $Kept = [PSCustomObject]@{ DirectoryScopeId = '/'; MemberType = 'Direct'; AssignmentType = 'Assigned'; PrincipalId = 'aaaaaaaa-0000-0000-0000-000000000001' }
                @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Kept, $null) -Kind Active -Excluded).Count | Should -Be 0
                @(Select-OERManagedDirectoryRoleAssignment -Assignment @($Kept, $null) -Kind Active).Count | Should -Be 1
            }
        }
    }
}
