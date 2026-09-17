BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERManagementGroup' {
    It 'tags the type and maps core and alias properties' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-platform'
                name       = 'mg-platform'
                type       = 'Microsoft.Management/managementGroups'
                properties = [PSCustomObject]@{
                    tenantId    = '11111111-1111-1111-1111-111111111111'
                    displayName = 'Platform'
                    details     = [PSCustomObject]@{
                        parent = [PSCustomObject]@{
                            id          = '/providers/Microsoft.Management/managementGroups/root'
                            name        = 'root'
                            displayName = 'Tenant Root Group'
                        }
                    }
                }
            }
            $Out = ConvertTo-OERManagementGroup -InputObject $Raw
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ManagementGroup'
            $Out.ResourceId | Should -Be '/providers/Microsoft.Management/managementGroups/mg-platform'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
            $Out.Name | Should -Be 'mg-platform'
            $Out.ManagementGroupName | Should -Be 'mg-platform'
            $Out.DisplayName | Should -Be 'Platform'
            $Out.TenantId | Should -Be '11111111-1111-1111-1111-111111111111'
            $Out.ParentName | Should -Be 'root'
            $Out.ParentDisplayName | Should -Be 'Tenant Root Group'
        }
    }

    It 'handles list-shaped items without details and carries expanded children' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-x'
                name       = 'mg-x'
                properties = [PSCustomObject]@{
                    tenantId    = 't'
                    displayName = 'X'
                    children    = @([PSCustomObject]@{ id = '/subscriptions/abc'; type = '/subscriptions'; name = 'abc'; displayName = 'Sub' })
                }
            }
            $Out = ConvertTo-OERManagementGroup -InputObject $Raw
            $Out.ParentId | Should -BeNullOrEmpty
            @($Out.Children)[0].name | Should -Be 'abc'
        }
    }

    It 'exposes the ARM path only as ResourceId so a piped management group cannot set a schedule id' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg-root'
                name       = 'mg-root'
                type       = 'Microsoft.Management/managementGroups'
                properties = @{
                    tenantId    = '11111111-1111-1111-1111-111111111111'
                    displayName = 'Root'
                }
            }
            $Out.ResourceId | Should -Be '/providers/Microsoft.Management/managementGroups/mg-root'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'exposes the ARM path as ResourceId and never as a bare Id' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg-aaaa0000'
                name       = 'mg-aaaa0000'
                properties = @{
                    tenantId    = 'aaaa0000-0000-0000-0000-000000000001'
                    displayName = 'MG'
                }
            }
            $Out.ResourceId | Should -Be '/providers/Microsoft.Management/managementGroups/mg-aaaa0000'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'does not bind Get-OERRoleManagementPolicy -PolicyId when piped, so the scope parameter set wins' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        $Mg = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg-root'
                name       = 'mg-root'
                type       = 'Microsoft.Management/managementGroups'
                properties = @{
                    tenantId    = '11111111-1111-1111-1111-111111111111'
                    displayName = 'Root'
                }
            }
        }
        $Bound = @($Mg.PSObject.Properties.Name)
        $Bound | Should -Not -Contain 'Id'
        $Bound | Should -Not -Contain 'PolicyId'
        $Bound | Should -Not -Contain 'RoleEligibilityScheduleId'
    }

    It 'stores Name as an AliasProperty of ManagementGroupName, not a second copy (Task 8a)' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg-alias'
                name       = 'mg-alias'
                properties = @{ tenantId = 't'; displayName = 'Alias' }
            }

            ($Out.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Name' -Because 'Name must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Out.PSObject.Properties['Name'].MemberType | Should -Be 'AliasProperty'
            $Out.PSObject.Properties['Name'].ReferencedMemberName | Should -Be 'ManagementGroupName'
            $Out.Name | Should -Be 'mg-alias'
        }
    }

    It 'pipes real converter output into Get-OERSubscription -ManagementGroup, proving the migrated shape still round-trips (Task 8a)' {
        # Mirrors Get-OERSubscription.Tests.ps1's own "binds -ManagementGroup from a piped management
        # group object" case, but pipes REAL ConvertTo-OERManagementGroup output (constructed here)
        # instead of a hand-built fixture object -- so this proves the converter's own alias
        # registration round-trips through a real downstream cmdlet, not just that a fixture shaped
        # like its output would.
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/subscriptions/cccc2222-0000-0000-0000-000000000000'; subscriptionId = 'cccc2222-0000-0000-0000-000000000000'; displayName = 'Workload'; state = 'Enabled'; tenantId = 't' }
            ) }
        } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg9' }
        } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/mg9?api-version=2020-05-01' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg9'
                name       = 'mg9'
                properties = [PSCustomObject]@{
                    children = @(
                        [PSCustomObject]@{ id = '/subscriptions/cccc2222-0000-0000-0000-000000000000'; type = '/subscriptions'; name = 'cccc2222-0000-0000-0000-000000000000'; displayName = 'Workload' }
                    )
                }
            }
        } -ParameterFilter { $Path -like '/providers/Microsoft.Management/managementGroups/mg9?api-version=2020-05-01&*recurse*' }

        $Result = InModuleScope Omnicit.EntraRBAC {
            $Mg = ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg9'
                name       = 'mg9'
                properties = @{ tenantId = 't'; displayName = 'Nine' }
            }
            @($Mg | Get-OERSubscription)
        }
        $Result.Count | Should -Be 1
        $Result[0].SubscriptionId | Should -Be 'cccc2222-0000-0000-0000-000000000000'
    }
}
