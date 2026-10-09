BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERManagementGroupList' {
    It 'lists with ONE paged GET on the Management Groups - List path' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

            $null = @(Get-OERManagementGroupList)

            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and
                $All -and $Method -in @($null, 'GET')
            }
        }
    }

    It 'emits each listed item raw and unchanged, with no type name added, and skips a null item' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/mg-a'
                            name       = 'mg-a'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG A' }
                        }
                        $null
                        [PSCustomObject]@{
                            id         = '/providers/Microsoft.Management/managementGroups/mg-b'
                            name       = 'mg-b'
                            type       = 'Microsoft.Management/managementGroups'
                            properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG B' }
                        }
                    ) }
            }

            $Out = @(Get-OERManagementGroupList)

            $Out.Count | Should -Be 2
            $Out[0].name | Should -BeExactly 'mg-a'
            $Out[1].name | Should -BeExactly 'mg-b'
            foreach ($Item in $Out) {
                $Item.PSObject.TypeNames[0] | Should -BeExactly 'System.Management.Automation.PSCustomObject'
                $Item.PSObject.TypeNames | Should -Not -Contain 'Omnicit.EntraRBAC.ManagementGroup'
                @($Item.PSObject.Properties.Name) | Should -Be @('id', 'name', 'type', 'properties')
            }
            $Out[0].properties.displayName | Should -BeExactly 'MG A'
            $Out[0].properties.tenantId | Should -BeExactly 't'
        }
    }

    It 'throws a failed listing to its caller and catches nothing' {
        InModuleScope Omnicit.EntraRBAC {
            $ArmErr = Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
            Mock Invoke-OERArmRequest { [CmdletBinding()] param($Path, $Method, $Body, [switch]$All) throw $ArmErr }
            Mock Remove-OERErrorRecord { }

            { Get-OERManagementGroupList } | Should -Throw -ExpectedMessage 'AuthorizationFailed: denied' -ErrorId 'AuthorizationFailed*'

            Should -Invoke Remove-OERErrorRecord -Times 0
        }
    }
}
