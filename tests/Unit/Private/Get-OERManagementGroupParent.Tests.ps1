BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERManagementGroupParent' {
    It 'reads the parents with ONE paged POST on the Entities - List path, groups only' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

            $null = Get-OERManagementGroupParent

            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/getEntities?api-version=2020-05-01&$view=GroupsOnly' -and
                $Method -ceq 'POST' -and $All
            }
        }
    }

    It 'maps each group name to its parent id, the last segment of that id and the last display name of the chain' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        # The tenant root group: no parent, so no entry.
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/t'
                            name       = 't'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Tenant Root Group'; parent = $null }
                        }
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/mg-b'
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                tenantId               = 't'
                                displayName            = 'MG B'
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('t', 'mg-a')
                                parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                            }
                        }
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/mg-a'
                            name       = 'mg-a'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                tenantId               = 't'
                                displayName            = 'MG A'
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/t' }
                                parentNameChain        = @('t')
                                parentDisplayNameChain = @('Tenant Root Group')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            $Map | Should -BeOfType ([hashtable])
            $Map.Count | Should -Be 2
            $Map.ContainsKey('t') | Should -BeFalse
            $Map['mg-b'].id | Should -BeExactly '/providers/Microsoft.Management/managementGroups/mg-a'
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
            $Map['mg-b'].displayName | Should -BeExactly 'MG A'
            @($Map['mg-b'].PSObject.Properties.Name) | Should -Be @('id', 'name', 'displayName')
            $Map['mg-a'].id | Should -BeExactly '/providers/Microsoft.Management/managementGroups/t'
            $Map['mg-a'].name | Should -BeExactly 't'
            $Map['mg-a'].displayName | Should -BeExactly 'Tenant Root Group'
        }
    }

    It 'keys the map case-insensitively' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'MG-B'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            $Map.ContainsKey('mg-b') | Should -BeTrue
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
        }
    }

    It 'leaves out an entity of another type' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = '11111111-1111-1111-1111-111111111111'
                            type       = '/subscriptions'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    It 'leaves out an entity without a parent' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-no-parent'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ parent = $null; parentNameChain = @('mg-a'); parentDisplayNameChain = @('MG A') }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    It 'leaves out an entity whose parent id is empty' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-empty-parent-id'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ parent = [PSCustomObject]@{ id = '' }; parentNameChain = @('mg-a'); parentDisplayNameChain = @('MG A') }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    # Without the string test a parent id that is not a string passes the blank check and .Split
    # throws out of the helper, so EVERY non-root group would be reported unread instead of only the
    # one entity. A number and an object are proven in separate tests, so each goes red on its own.
    It 'leaves out an entity whose parent id is a number instead of a string, and keeps the good one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-number-parent-id'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ parent = [PSCustomObject]@{ id = 42 }; parentNameChain = @('42'); parentDisplayNameChain = @('MG A') }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
        }
    }

    It 'leaves out an entity whose parent id is an object instead of a string, and keeps the good one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-object-parent-id'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = [PSCustomObject]@{ value = '/providers/Microsoft.Management/managementGroups/mg-a' } }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
        }
    }

    It 'leaves out an entity whose display name chain is empty, and one whose last chain element is white space' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-empty-chain'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('t', 'mg-a')
                                parentDisplayNameChain = @()
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-blank-last'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('t', 'mg-a')
                                parentDisplayNameChain = @('Tenant Root Group', '  ')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    # The name chain must end in the group parent.id names (R17). The Entities - List sample on
    # Microsoft Learn shows chains that end in another group than parent.id names; taking such an
    # entity would put that other group's display name beside the right ParentId and ParentName.
    It 'leaves out an entity whose name chain ends in another group than its parent id names, and keeps the good one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-chain-disagrees'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/t' }
                                parentNameChain        = @('t', 'mg-p')
                                parentDisplayNameChain = @('Tenant Root Group', 'MG P')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('t', 'mg-a')
                                parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
            $Map['mg-b'].displayName | Should -BeExactly 'MG A'
        }
    }

    It 'leaves out an entity whose name chain is empty, and one that has no name chain, and keeps the good one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-empty-name-chain'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @()
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-no-name-chain'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    It 'takes an entity whose name chain differs from its parent id only in case, with the name from the parent id' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('T', 'MG-A')
                                parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
            $Map['mg-b'].id | Should -BeExactly '/providers/Microsoft.Management/managementGroups/mg-a'
            $Map['mg-b'].name | Should -BeExactly 'mg-a'
            $Map['mg-b'].displayName | Should -BeExactly 'MG A'
        }
    }

    # A parent id that ends in a slash has an empty last segment. Without the blank-segment test a
    # name chain ending in an empty name, or no name chain at all, would match that empty segment.
    It 'leaves out an entity whose parent id ends in a slash, with a name chain ending in an empty name or without one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-slash-empty-name'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/' }
                                parentNameChain        = @('t', '')
                                parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-slash-no-name-chain'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/' }
                                parentDisplayNameChain = @('Tenant Root Group', 'MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentNameChain        = @('mg-a')
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    It 'throws a failed call to its caller and catches nothing' {
        InModuleScope Omnicit.EntraRBAC {
            $ArmErr = Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
            Mock Invoke-OERArmRequest { [CmdletBinding()] param($Path, $Method, $Body, [switch]$All) throw $ArmErr }
            Mock Remove-OERErrorRecord { }

            { Get-OERManagementGroupParent } | Should -Throw -ExpectedMessage 'AuthorizationFailed: denied' -ErrorId 'AuthorizationFailed*'

            Should -Invoke Remove-OERErrorRecord -Times 0
        }
    }
}
