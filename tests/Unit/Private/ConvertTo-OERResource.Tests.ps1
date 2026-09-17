BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERResource' {
    It 'maps the ARM wire shape and tags the object' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id        = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stgfoo'
                name      = 'stgfoo'
                type      = 'Microsoft.Storage/storageAccounts'
                location  = 'westeurope'
                kind      = 'StorageV2'
                managedBy = $null
                tags      = [PSCustomObject]@{ env = 'prod' }
            }
            $Result = ConvertTo-OERResource -InputObject $Wire
            $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Resource'
            $Result.Name           | Should -Be 'stgfoo'
            $Result.ResourceName   | Should -Be 'stgfoo'
            $Result.ResourceType   | Should -Be 'Microsoft.Storage/storageAccounts'
            $Result.ResourceGroup  | Should -Be 'rg-app'
            $Result.SubscriptionId | Should -Be '11111111-1111-1111-1111-111111111111'
            $Result.Location       | Should -Be 'westeurope'
            $Result.Kind           | Should -Be 'StorageV2'
            $Result.ResourceId     | Should -Be '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stgfoo'
            $Result.Tags.env       | Should -Be 'prod'
        }
    }

    It 'leaves Tags null-or-empty when the wire object has no tags' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id   = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stgfoo'
                name = 'stgfoo'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope'
            }
            $Result = ConvertTo-OERResource -InputObject $Wire
            $Result.Tags | Should -BeNullOrEmpty
        }
    }

    It 'exposes ResourceId but neither Id nor Scope (would mis-bind on pipe)' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id   = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stgfoo'
                name = 'stgfoo'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope'
            }
            $Result = ConvertTo-OERResource -InputObject $Wire
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Id'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Scope'
            $Result.PSObject.Properties.Name | Should -Contain 'ResourceId'
            $Result.ResourceName | Should -Be $Result.Name
        }
    }

    It 'stores Name as an AliasProperty of ResourceName, not a second copy (Task 8a)' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id = '/subscriptions/1/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stgalias'
                name = 'stgalias'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope'
            }
            $Result = ConvertTo-OERResource -InputObject $Wire

            ($Result.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Name' -Because 'Name must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Result.PSObject.Properties['Name'].MemberType | Should -Be 'AliasProperty'
            $Result.PSObject.Properties['Name'].ReferencedMemberName | Should -Be 'ResourceName'
            $Result.Name | Should -Be 'stgalias'
        }
    }

    It 'pipes real converter output into New-OERActiveRoleAssignment, proving the migrated shape still round-trips (Task 8a)' {
        # Companion of New-OERActiveRoleAssignment.Tests.ps1's own "binds a piped resource-shaped
        # object end to end" case, but sources the piped object from the REAL converter instead of a
        # hand-built fixture -- proving the converter's own alias registration (Name -> ResourceName)
        # round-trips through a real downstream cmdlet's -ResourceName binding, not just that a
        # fixture shaped like its output would.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stgpipe' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stgpipe'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'stgpipe' } } } }
        }

        InModuleScope Omnicit.EntraRBAC {
            $Resource = ConvertTo-OERResource -InputObject ([PSCustomObject]@{
                    id       = '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stgpipe'
                    name     = 'stgpipe'
                    type     = 'Microsoft.Storage/storageAccounts'
                    location = 'westeurope'
                })
            $Resource | New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stgpipe' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }
}
