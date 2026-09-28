BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERDirectoryRoleManagementPolicy' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'ByRole' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        }

        It 'resolves a role name to its policy and returns a tagged Graph-shaped object' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment {
                @(
                    [PSCustomObject]@{
                        policyId         = 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
                        roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                        policy           = [PSCustomObject]@{
                            rules = @(
                                [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                [PSCustomObject]@{
                                    id      = 'Approval_EndUser_Assignment'
                                    setting = [PSCustomObject]@{
                                        isApprovalRequired = $true
                                        approvalStages      = @(
                                            [PSCustomObject]@{
                                                primaryApprovers = @(
                                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'bbbbbbbb-0000-0000-0000-000000000002' }
                                                )
                                            }
                                        )
                                    }
                                }
                            )
                        }
                    }
                )
            }

            $p = Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader'

            $p.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            $p.Scope | Should -Be '/'
            $p.RoleName | Should -Be 'Reports Reader'
            $p.RoleDefinitionId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            $p.PolicyId | Should -Be 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
            $p.ActivationMaxHours | Should -Be 8
            $p.Approvers[0].Id | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
            $p.Approvers[0].UserType | Should -Be 'Group'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment -Times 1 -Exactly -ParameterFilter {
                $RoleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001'
            }
        }

        It 'leaves RoleName empty when -Role is a GUID' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment {
                @([PSCustomObject]@{ policyId = 'pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = [PSCustomObject]@{ rules = @() } })
            }
            $p = Get-OERDirectoryRoleManagementPolicy -Role 'aaaaaaaa-0000-0000-0000-000000000001'
            $p.RoleName | Should -BeNullOrEmpty
        }

        It 'reports RoleDefinitionNotFound exactly once and never reads a policy when the resolver finds no role' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment { }
            Get-OERDirectoryRoleManagementPolicy -Role 'No Such Role' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment -Times 0
        }

        It 'reports RoleDefinitionReadFailed (and never RoleDefinitionNotFound) when the resolver throws' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { throw 'Forbidden: insufficient privileges' }
            Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionReadFailed,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 0
        }

        It 'reports AmbiguousRoleName when the resolver refuses an ambiguous name' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            Get-OERDirectoryRoleManagementPolicy -Role 'Dup' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRoleName,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
        }

        It 'reports PolicyNotFound when there is no policy assignment for the role' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment { @() }
            Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyNotFound,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
        }

        It 'reports PolicyReadFailed when the assignment read throws' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment { throw 'Forbidden: insufficient privileges' }
            Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyReadFailed,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
        }

        It 'calls Initialize-OERAuth without -IncludeARM' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment {
                @([PSCustomObject]@{ policyId = 'pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = [PSCustomObject]@{ rules = @() } })
            }
            Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
        }
    }

    Context 'ByPolicyId' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        }

        It 'reads the policy directly and converts its rules, leaving RoleName and RoleDefinitionId empty' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy {
                [PSCustomObject]@{
                    id        = 'DirectoryRole_pol1'
                    scopeId   = '/'
                    scopeType = 'DirectoryRole'
                    rules     = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT4H' })
                }
            }
            $p = Get-OERDirectoryRoleManagementPolicy -PolicyId 'DirectoryRole_pol1'
            $p.ActivationMaxHours | Should -Be 4
            $p.PolicyId | Should -Be 'DirectoryRole_pol1'
            $p.Scope | Should -Be '/'
            $p.RoleName | Should -BeNullOrEmpty
            $p.RoleDefinitionId | Should -BeNullOrEmpty
        }

        It 'rejects an ARM-shaped policy id as InvalidPolicyId, naming Get-OERRoleManagementPolicy, without calling Graph' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy { }
            Get-OERDirectoryRoleManagementPolicy -PolicyId '/providers/Microsoft.Authorization/roleManagementPolicies/x' `
                -ErrorVariable e -ErrorAction SilentlyContinue
            $Reported = @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Get-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match 'Get-OERRoleManagementPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy -Times 0
        }

        It 'writes PolicyReadFailed when the policy read throws' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy { throw 'Forbidden: insufficient privileges' }
            Get-OERDirectoryRoleManagementPolicy -PolicyId 'DirectoryRole_pol1' -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyReadFailed,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
        }

        It 'binds -PolicyId from a piped object exposing a PolicyId property' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy {
                [PSCustomObject]@{ id = 'DirectoryRole_pol1'; scopeId = '/'; scopeType = 'DirectoryRole'; rules = @() }
            }
            $Piped = [PSCustomObject]@{ PolicyId = 'DirectoryRole_pol1' }
            $Piped | Get-OERDirectoryRoleManagementPolicy | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicy -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'DirectoryRole_pol1' }
        }

        It 'rejects a PIM for Groups policy id as InvalidPolicyId and returns no object (R24)' {
            # Reproduces the real read path end to end: Get-OERDirectoryRolePolicy is NOT mocked
            # here, so its own scopeId/scopeType check (added by R24) runs for real and this
            # cmdlet's catch must translate the resulting NotDirectoryRolePolicy into InvalidPolicyId.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{
                    id        = 'Group_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
                    scopeId   = '33333333-3333-3333-3333-333333333333'
                    scopeType = 'Group'
                    rules     = @()
                }
            }
            $Piped = [PSCustomObject]@{
                PolicyId = 'Group_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
            }
            $Out = $Piped | Get-OERDirectoryRoleManagementPolicy -ErrorVariable e -ErrorAction SilentlyContinue
            $Out | Should -BeNullOrEmpty
            $Reported = @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyId,Get-OERDirectoryRoleManagementPolicy' })
            $Reported.Count | Should -Be 1
            $Reported[0].Exception.Message | Should -Match 'Get-OERGroupPimPolicy'
        }
    }

    Context 'All' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        }

        It 'returns one tagged object per assignment with names read from the role definitions list' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment {
                @(
                    [PSCustomObject]@{ policyId = 'pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = [PSCustomObject]@{ rules = @() } }
                    [PSCustomObject]@{ policyId = 'pol2'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000002'; policy = [PSCustomObject]@{ rules = @() } }
                )
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{
                    value = @(
                        @{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Reports Reader' }
                        @{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Global Reader' }
                    )
                }
            }
            $Policies = @(Get-OERDirectoryRoleManagementPolicy -All)
            $Policies.Count | Should -Be 2
            ($Policies | Where-Object { $_.RoleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001' }).RoleName | Should -Be 'Reports Reader'
            ($Policies | Where-Object { $_.RoleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000002' }).RoleName | Should -Be 'Global Reader'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $All -and $Uri -like 'v1.0/roleManagement/directory/roleDefinitions*'
            }
        }

        It 'still returns the policies, with a warning and an empty RoleName, when the names read fails' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment {
                @([PSCustomObject]@{ policyId = 'pol1'; roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; policy = [PSCustomObject]@{ rules = @() } })
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'Forbidden: insufficient privileges' }
            $Policies = @(Get-OERDirectoryRoleManagementPolicy -All -WarningVariable Warned -WarningAction SilentlyContinue)
            $Policies.Count | Should -Be 1
            $Policies[0].RoleName | Should -BeNullOrEmpty
            $Warned | Should -Not -BeNullOrEmpty
        }

        It 'reports PolicyReadFailed and reads no names when the assignment list read throws' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERDirectoryRolePolicyAssignment { throw 'Forbidden: insufficient privileges' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Get-OERDirectoryRoleManagementPolicy -All -ErrorVariable e -ErrorAction SilentlyContinue
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyReadFailed,Get-OERDirectoryRoleManagementPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        }
    }

    Context 'Mutual exclusivity' {
        BeforeAll { Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { } }
        It 'rejects -Role together with -All' {
            { Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -All } | Should -Throw
        }
        It 'rejects -PolicyId together with -All' {
            { Get-OERDirectoryRoleManagementPolicy -PolicyId 'pol1' -All } | Should -Throw
        }
    }
}
