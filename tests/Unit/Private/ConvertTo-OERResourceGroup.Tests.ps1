BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERResourceGroup' {
    It 'maps the ARM wire shape and tags the object' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id         = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net'
                name       = 'rg-net'
                type       = 'Microsoft.Resources/resourceGroups'
                location   = 'westeurope'
                managedBy  = $null
                tags       = [PSCustomObject]@{ env = 'prod' }
                properties = [PSCustomObject]@{ provisioningState = 'Succeeded' }
            }
            $Result = ConvertTo-OERResourceGroup -InputObject $Wire
            $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ResourceGroup'
            $Result.Name              | Should -Be 'rg-net'
            $Result.ResourceGroup     | Should -Be 'rg-net'
            $Result.SubscriptionId    | Should -Be '11111111-1111-1111-1111-111111111111'
            $Result.Location          | Should -Be 'westeurope'
            $Result.ProvisioningState | Should -Be 'Succeeded'
            $Result.ResourceId        | Should -Be '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net'
            $Result.ManagedBy         | Should -BeNullOrEmpty
            $Result.Tags.env          | Should -Be 'prod'
        }
    }

    It 'does not expose an Id property (would mis-bind to Id-aliased pipeline params on the delegation cmdlets)' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id         = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net'
                name       = 'rg-net'
                location   = 'westeurope'
                properties = [PSCustomObject]@{ provisioningState = 'Succeeded' }
            }
            $Result = ConvertTo-OERResourceGroup -InputObject $Wire
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Id'
            $Result.PSObject.Properties.Name | Should -Contain 'ResourceId'
        }
    }

    It 'stores ResourceGroup as the sole spelling of Name, with Name registered as its AliasProperty (Task 8a)' {
        InModuleScope Omnicit.EntraRBAC {
            $Wire = [PSCustomObject]@{
                id         = '/subscriptions/1/resourceGroups/rg-alias'
                name       = 'rg-alias'
                location   = 'westeurope'
                properties = [PSCustomObject]@{ provisioningState = 'Succeeded' }
            }
            $Result = ConvertTo-OERResourceGroup -InputObject $Wire

            ($Result.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Name' -Because 'Name must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Result.PSObject.Properties['Name'].MemberType | Should -Be 'AliasProperty'
            $Result.PSObject.Properties['Name'].ReferencedMemberName | Should -Be 'ResourceGroup'
            $Result.Name | Should -Be 'rg-alias'
        }
    }

    It 'pipes real converter output into New-OERActiveRoleAssignment -ResourceGroup, proving the migrated shape still round-trips (Task 8a)' {
        # Companion of New-OERActiveRoleAssignment.Tests.ps1's own "binds a piped resource-group-shaped
        # object end to end" case, but sources the piped object from the REAL converter. -ResourceGroup
        # binds by direct property-NAME match here (the parameter's own canonical name, not an alias),
        # which is exactly why this migration keeps ResourceGroup as the stored value rather than Name.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-pipe' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPermanentPolicyState { [PSCustomObject]@{ PolicyId = '/pol1'; RoleName = 'Reader'; RuleId = 'Expiration_Admin_Assignment'; PermanentAllowed = $true } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/sub-guid/resourceGroups/rg-pipe'; roleDefinitionId = 'rd1'; principalId = 'p1'; principalType = 'User'
                    requestType = 'AdminAssign'; status = 'Provisioned'; requestorId = 'p1'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'NoExpiration' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
        }

        InModuleScope Omnicit.EntraRBAC {
            $Rg = ConvertTo-OERResourceGroup -InputObject ([PSCustomObject]@{
                    id         = '/subscriptions/sub-guid/resourceGroups/rg-pipe'
                    name       = 'rg-pipe'
                    location   = 'westeurope'
                    properties = [PSCustomObject]@{ provisioningState = 'Succeeded' }
                })
            $Rg | New-OERActiveRoleAssignment -Role 'Reader' -User 'anna@contoso.com' -Confirm:$false
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-pipe'
        }
    }
}
