BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERRoleDefinition' {
    It 'tags the type and maps properties including the RoleDefinitionId pipeline alias' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                name       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
                type       = 'Microsoft.Authorization/roleDefinitions'
                properties = [PSCustomObject]@{
                    roleName         = 'Reader'
                    type             = 'BuiltInRole'
                    description      = 'View all resources'
                    assignableScopes = @('/')
                    permissions      = @([PSCustomObject]@{ actions = @('*/read'); notActions = @() })
                }
            }
            $Out = ConvertTo-OERRoleDefinition -InputObject $Raw
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleDefinition'
            $Out.ResourceId | Should -Be $Raw.id
            $Out.RoleDefinitionId | Should -Be $Raw.id
            $Out.Name | Should -Be 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
            $Out.RoleName | Should -Be 'Reader'
            $Out.RoleType | Should -Be 'BuiltInRole'
            $Out.Description | Should -Be 'View all resources'
            @($Out.AssignableScopes)[0] | Should -Be '/'
            @($Out.Permissions)[0].actions | Should -Contain '*/read'
        }
    }

    It 'stores ResourceId as an AliasProperty of RoleDefinitionId, not a second copy, and never registers a bare Id (Task 8a addendum)' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                name       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
                properties = [PSCustomObject]@{ roleName = 'Reader'; type = 'BuiltInRole' }
            }
            $Out = ConvertTo-OERRoleDefinition -InputObject $Raw

            ($Out.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'ResourceId' -Because 'ResourceId must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Out.PSObject.Properties['ResourceId'].MemberType | Should -Be 'AliasProperty'
            $Out.PSObject.Properties['ResourceId'].ReferencedMemberName | Should -Be 'RoleDefinitionId'
            $Out.ResourceId | Should -Be $Raw.id

            # Task 2d's whole point: 'Id' must NEVER resolve on this type (it would collide with
            # -PolicyId/-RoleEligibilityScheduleId's own Id alias elsewhere) -- unlike the other nine
            # rows in the Task 8a sweep, this type deliberately stays without an Id member at all.
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }
}
