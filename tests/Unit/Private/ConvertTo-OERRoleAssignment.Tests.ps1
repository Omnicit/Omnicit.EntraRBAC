BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERRoleAssignment' {
    It 'tags the type and maps properties including the RoleAssignmentId pipeline alias' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name       = '00000000-0000-0000-0000-000000000059'
                type       = 'Microsoft.Authorization/roleAssignments'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000057'
                    principalId      = '00000000-0000-0000-0000-000000000058'
                    principalType    = 'User'
                    scope            = '/subscriptions/s1'
                    description      = 'test'
                    createdOn        = '2026-06-11T00:00:00Z'
                }
            }
            $Out = ConvertTo-OERRoleAssignment -InputObject $Raw
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
            $Out.Id | Should -Be $Raw.id
            $Out.RoleAssignmentId | Should -Be $Raw.id
            $Out.Name | Should -Be '00000000-0000-0000-0000-000000000059'
            $Out.Scope | Should -Be '/subscriptions/s1'
            $Out.RoleDefinitionId | Should -Be '/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000057'
            $Out.PrincipalId | Should -Be '00000000-0000-0000-0000-000000000058'
            $Out.PrincipalType | Should -Be 'User'
            $Out.Description | Should -Be 'test'
            # Absent on the wire -> $null, never an empty string.
            $Out.DelegatedManagedIdentityResourceId | Should -BeNullOrEmpty
        }
    }

    # Set-OERRoleAssignment carries delegatedManagedIdentityResourceId forward verbatim on an edit
    # (dropping it would destroy an Azure Lighthouse delegation), so it has to be readable to verify.
    It 'projects delegatedManagedIdentityResourceId when the assignment carries one' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name       = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000057'
                    principalId      = '00000000-0000-0000-0000-000000000058'
                    delegatedManagedIdentityResourceId = '/subscriptions/lighthouse-sub/resourceGroups/rg/providers/Microsoft.ManagedServices/registrationAssignments/00000000-0000-0000-0000-000000000052'
                }
            }
            $Out = ConvertTo-OERRoleAssignment -InputObject $Raw
            $Out.DelegatedManagedIdentityResourceId |
                Should -Be '/subscriptions/lighthouse-sub/resourceGroups/rg/providers/Microsoft.ManagedServices/registrationAssignments/00000000-0000-0000-0000-000000000052'
        }
    }

    It 'stores the role assignment id exactly once and aliases Id to it' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERRoleAssignment -InputObject @{
                id = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/ra1'
                name = 'ra1'
                properties = @{ scope = '/subscriptions/s1'; roleDefinitionId = '/rd1'; principalId = 'p1' }
            }
            $Out.RoleAssignmentId | Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/ra1'
            $Out.Id | Should -Be $Out.RoleAssignmentId
            $Out.PSObject.Properties['RoleAssignmentId'].MemberType | Should -Be 'NoteProperty'
            $Out.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
        }
    }

    # Reflection alone would not catch a binding regression: this pipes a converted object straight
    # into Set-OERRoleAssignment and proves the -Id parameter (bound via its RoleAssignmentId alias)
    # still binds and drives exactly one ARM write, after the duplicated Id NoteProperty was replaced
    # with an AliasProperty. Set-OERRoleAssignment reads the live assignment first (GET, default
    # Method) and then PUTs the update to the same id -- the mock returns the same shape for both calls
    # since only the PUT call needs to be asserted.
    It 'still binds Set-OERRoleAssignment -Id through the pipeline after the alias change' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            @{
                id = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/ra1'
                name = 'ra1'
                properties = @{ scope = '/subscriptions/s1'; roleDefinitionId = '/rd1'; principalId = 'p1'; description = 'updated' }
            }
        }
        $Piped = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERRoleAssignment -InputObject @{
                id = '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignments/ra1'
                name = 'ra1'
                properties = @{ scope = '/subscriptions/s1'; roleDefinitionId = '/rd1'; principalId = 'p1' }
            }
        }
        $Result = $Piped | Set-OERRoleAssignment -Description 'updated' -Confirm:$false
        $Result | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
    }
}
