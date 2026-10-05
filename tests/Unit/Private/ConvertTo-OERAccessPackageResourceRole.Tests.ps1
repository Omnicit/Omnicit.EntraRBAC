BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERAccessPackageResourceRole' {
    It 'maps ScopeDisplayName from scope.displayName and leaves ResourceDisplayName null when not stamped' {
        InModuleScope $script:moduleName {
            # Shape of a real Graph payload (GET .../accessPackages/{id}?$expand=resourceRoleScopes($expand=role,scope)); identifiers below are placeholders:
            # scope.displayName is the SCOPE label, not the resource name -- for a root-scoped Entra
            # group binding Graph literally returns 'Root'. There is no nested resource object.
            $Raw = @{
                id    = 'rrs-1'
                scope = @{
                    isRootScope  = $true
                    originId     = '00000000-0000-0000-0000-000000000050'
                    displayName  = 'Root'
                    id           = 'scope001-guid'
                    description  = 'Root Scope'
                    originSystem = 'AadGroup'
                }
                role  = @{
                    originSystem = 'AadGroup'
                    displayName  = 'Member'
                    id           = 'role0001-guid'
                    description  = $null
                    originId     = 'Member_00000000-0000-0000-0000-000000000050'
                    type         = $null
                }
                createdDateTime = '2026-06-16T13:46:33.643Z'
            }
            $Out = ConvertTo-OERAccessPackageResourceRole -InputObject $Raw -AccessPackageId 'ap-1'

            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
            $Out.ResourceRoleScopeId | Should -Be 'rrs-1'
            $Out.RoleName            | Should -Be 'Member'
            $Out.ScopeDisplayName    | Should -Be 'Root'
            $Out.OriginId            | Should -Be '00000000-0000-0000-0000-000000000050'
            $Out.OriginSystem        | Should -Be 'AadGroup'
            $Out.AccessPackageId     | Should -Be 'ap-1'

            # ResourceDisplayName is not derivable from this payload at all -- prove the property
            # exists on the shape (round-trippable) but carries no value when the caller does not
            # stamp one on.
            $Out.PSObject.Properties.Name | Should -Contain 'ResourceDisplayName'
            $Out.ResourceDisplayName | Should -BeNullOrEmpty
        }
    }

    It 'preserves the property order ResourceRoleScopeId, RoleName, ResourceDisplayName, ScopeDisplayName, OriginId, OriginSystem, AccessPackageId' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id    = 'rrs-1'
                role  = @{ displayName = 'Member' }
                scope = @{ originId = 'g'; originSystem = 'AadGroup'; displayName = 'Root' }
            }
            $Out = ConvertTo-OERAccessPackageResourceRole -InputObject $Raw -AccessPackageId 'ap-1'
            $ExpectedOrder = @(
                'ResourceRoleScopeId', 'RoleName', 'ResourceDisplayName', 'ScopeDisplayName',
                'OriginId', 'OriginSystem', 'AccessPackageId'
            )
            ($Out.PSObject.Properties.Name -join ',') | Should -Be ($ExpectedOrder -join ',')
        }
    }

    It 'emits a null, never an empty string, for ResourceDisplayName when none is supplied or an empty one is' {
        # P8 / A10: the help of this converter and of Get-OERAccessPackageResourceRole promise $null,
        # and an empty string is what an export would otherwise write as a binding's resource name.
        InModuleScope $script:moduleName {
            $Raw = @{
                id    = 'rrs-3'
                role  = @{ displayName = 'Member' }
                scope = @{ originId = 'g3'; originSystem = 'AadGroup'; displayName = 'Root' }
            }
            $Without = ConvertTo-OERAccessPackageResourceRole -InputObject $Raw -AccessPackageId 'ap-1'
            $Empty = ConvertTo-OERAccessPackageResourceRole -InputObject $Raw -AccessPackageId 'ap-1' -ResourceDisplayName ''

            # Reached: both calls produced the tagged shape, with the property present.
            $Without.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
            $Empty.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
            $Without.PSObject.Properties.Name | Should -Contain 'ResourceDisplayName'
            $Empty.PSObject.Properties.Name | Should -Contain 'ResourceDisplayName'
            $null -eq $Without.ResourceDisplayName | Should -BeTrue -Because 'no name was supplied'
            $null -eq $Empty.ResourceDisplayName | Should -BeTrue -Because 'an empty name is no name'
        }
    }

    It 'stamps a caller-supplied ResourceDisplayName distinctly from the scope label' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id    = 'rrs-2'
                role  = @{ displayName = 'Owner' }
                scope = @{ originId = 'g2'; originSystem = 'AadGroup'; displayName = 'Root' }
            }
            $Out = ConvertTo-OERAccessPackageResourceRole -InputObject $Raw -AccessPackageId 'ap-1' `
                -ResourceDisplayName 'Sales Group'

            $Out.ResourceDisplayName | Should -Be 'Sales Group'
            $Out.ScopeDisplayName    | Should -Be 'Root'
            $Out.ResourceDisplayName | Should -Not -Be $Out.ScopeDisplayName
        }
    }
}
