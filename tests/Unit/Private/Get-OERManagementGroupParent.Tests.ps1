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
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
        }
    }

    It 'leaves out an entity without a parent id, and one whose parent id is empty' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            name       = 'mg-no-parent'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ parent = $null; parentDisplayNameChain = @('MG A') }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-empty-parent-id'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ parent = [PSCustomObject]@{ id = '' }; parentDisplayNameChain = @('MG A') }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentDisplayNameChain = @('MG A')
                            }
                        }
                    ) }
            }

            $Map = Get-OERManagementGroupParent

            @($Map.Keys) | Should -Be @('mg-b')
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
                                parentDisplayNameChain = @()
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-blank-last'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
                                parentDisplayNameChain = @('Tenant Root Group', '  ')
                            }
                        }
                        [PSCustomObject]@{
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{
                                parent                 = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a' }
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
