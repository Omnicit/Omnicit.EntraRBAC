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
    It 'builds exactly the measured written form for -DirectoryRoleId' {
        InModuleScope Omnicit.EntraRBAC {
            $Id = '00000000-0000-0000-0000-000000000041'
            $Expected = @{
                '@odata.type'   = '#microsoft.graph.principalResourceMembershipsScope'
                principalScopes = @(@{ '@odata.type' = '#microsoft.graph.accessReviewQueryScope'; query = '/users'; queryType = 'MicrosoftGraph' })
                resourceScopes  = @(@{ '@odata.type' = '#microsoft.graph.accessReviewQueryScope'; query = "/roleManagement/directory/roleDefinitions/$Id"; queryType = 'MicrosoftGraph' })
            }
            $s = New-OERAccessReviewScopeQuery -DirectoryRoleId $Id
            ($s | ConvertTo-Json -Depth 5 -Compress) | Should -Be ($Expected | ConvertTo-Json -Depth 5 -Compress)
            $s.ContainsKey('query') | Should -BeFalse
        }
    }
    It 'builds a directory role scope that the role owner reads as All, fed through the converter shape' {
        InModuleScope Omnicit.EntraRBAC {
            $Id = '00000000-0000-0000-0000-000000000041'
            $Def = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'd'; scope = (New-OERAccessReviewScopeQuery -DirectoryRoleId $Id) }
            $R = Resolve-OERAccessReviewRoleScope -Query $Def.Scope -ScopeType $Def.ScopeType -PrincipalScope $Def.PrincipalScopes -ResourceScope $Def.ResourceScopes
            $R.Kind | Should -Be 'All'
            $R.RoleDefinitionId | Should -Be $Id
        }
    }
    It 'refuses -DirectoryRoleId combined with -GroupId' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERAccessReviewScopeQuery -DirectoryRoleId 'r' -GroupId 'g' } | Should -Throw
        }
    }

    Context 'DirectoryRoleAssignmentType' {
        It 'builds exactly the measured <Type> text, no version prefix' -ForEach @(
            @{
                Type     = 'Eligible'
                Expected = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000041')"
            }
            @{
                Type     = 'Active'
                Expected = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000041')"
            }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ T = $Type; E = $Expected } {
                param($T, $E)
                $s = New-OERAccessReviewScopeQuery -DirectoryRoleId '00000000-0000-0000-0000-000000000041' -DirectoryRoleAssignmentType $T
                $s.Keys.Count    | Should -Be 3
                $s.'@odata.type' | Should -Be '#microsoft.graph.accessReviewQueryScope'
                $s.queryType     | Should -Be 'MicrosoftGraph'
                $s.query         | Should -BeExactly $E
                $s.ContainsKey('principalScopes') | Should -BeFalse
            }
        }
        It 'accepts any letter case of the value' {
            InModuleScope Omnicit.EntraRBAC {
                $Id = '00000000-0000-0000-0000-000000000041'
                (New-OERAccessReviewScopeQuery -DirectoryRoleId $Id -DirectoryRoleAssignmentType eligible).query | Should -BeLike '/roleManagement/directory/roleEligibilityScheduleInstances?*'
                (New-OERAccessReviewScopeQuery -DirectoryRoleId $Id -DirectoryRoleAssignmentType ACTIVE).query | Should -BeLike '/roleManagement/directory/roleAssignmentScheduleInstances?*'
            }
        }
        It 'returns the all-assignments scope unchanged when the type is unbound' {
            InModuleScope Omnicit.EntraRBAC {
                $Id = '00000000-0000-0000-0000-000000000041'
                $s = New-OERAccessReviewScopeQuery -DirectoryRoleId $Id
                $s.'@odata.type' | Should -Be '#microsoft.graph.principalResourceMembershipsScope'
                $s.ContainsKey('query') | Should -BeFalse
                $s.principalScopes[0].query | Should -Be '/users'
                $s.resourceScopes[0].query  | Should -Be "/roleManagement/directory/roleDefinitions/$Id"
            }
        }
        It 'refuses a value other than Eligible or Active, and the type beside -GroupId' {
            InModuleScope Omnicit.EntraRBAC {
                { New-OERAccessReviewScopeQuery -DirectoryRoleId 'r' -DirectoryRoleAssignmentType All } | Should -Throw
                { New-OERAccessReviewScopeQuery -GroupId 'g' -DirectoryRoleAssignmentType Eligible } | Should -Throw
            }
        }
        It 'agrees with the classifier: <Kind> through the converter, <Prefix> prefix' -ForEach @(
            @{ Kind = 'All'; Type = $null; Prefix = '' }
            @{ Kind = 'Eligible'; Type = 'Eligible'; Prefix = '' }
            @{ Kind = 'Eligible'; Type = 'Eligible'; Prefix = '/beta' }
            @{ Kind = 'Active'; Type = 'Active'; Prefix = '' }
            @{ Kind = 'Active'; Type = 'Active'; Prefix = '/beta' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ K = $Kind; T = $Type; P = $Prefix } {
                param($K, $T, $P)
                $Id = '00000000-0000-0000-0000-000000000041'
                $Args1 = @{ DirectoryRoleId = $Id }
                if ($T) { $Args1.DirectoryRoleAssignmentType = $T }
                $Scope = New-OERAccessReviewScopeQuery @Args1
                if ($P) { $Scope.query = $P + $Scope.query }
                $Def = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'd'; scope = $Scope }
                $R = Resolve-OERAccessReviewRoleScope -Query $Def.Scope -ScopeType $Def.ScopeType -PrincipalScope $Def.PrincipalScopes -ResourceScope $Def.ResourceScopes
                $R.Kind | Should -Be $K
                $R.RoleDefinitionId | Should -Be $Id.ToLowerInvariant()
            }
        }
    }
}
