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

Describe 'Get-OERStructureRenameTarget' {

    Context 'Nothing to read' {
        It 'returns $null without a map' {
            InModuleScope $script:moduleName {
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'CAT-New' | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for an empty name, even when the map holds entries' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name '' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for a null name (a document entry that omits the referring key)' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name $null -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for a name no entry registered' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'CAT-Other' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null from an empty map' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                Get-OERStructureRenameTarget -Section 'administrativeUnits' -Name 'AU-New' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'refuses a section other than the three it serves' {
            InModuleScope $script:moduleName {
                { Get-OERStructureRenameTarget -Section 'groups' -Name 'N' -ErrorAction Stop } | Should -Throw
            }
        }
    }

    Context 'Round trip with Resolve-OERStructureRename (holds the key format of the two files together)' {
        It 'returns the entry a Rename registered, for the exact name' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'CAT-New' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRenameTarget'
            $Entry.Section | Should -BeExactly 'catalogs'
            $Entry.Name | Should -BeExactly 'CAT-New'
            $Entry.PreviousName | Should -BeExactly 'CAT-Old'
            $Entry.Id | Should -BeExactly 'p1'
            $Entry.Refused | Should -BeFalse
            $Entry.ErrorId | Should -BeNullOrEmpty
        }
        It 'finds the entry under a name that differs in letter case' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'cat-NEW' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.Id | Should -BeExactly 'p1'
        }
        It 'does not find the entry under another section' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'accessPackages' -Name 'CAT-New' -RenameMap $Map | Should -BeNullOrEmpty
                Get-OERStructureRenameTarget -Section 'administrativeUnits' -Name 'CAT-New' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'finds the entry in other letter case even in a map built with the default case-sensitive comparer' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new()
                $null = Resolve-OERStructureRename -Section 'administrativeUnits' -Name 'AU-New' -PreviousName 'AU-Old' -Id $null -PreviousId 'p2' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'administrativeUnits' -Name 'au-new' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.Id | Should -BeExactly 'p2'
        }
        It 'returns the refused entry a Conflict registered, with its ErrorId' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'CAT-New' -RenameMap $Map
            }
            $Entry.Refused | Should -BeTrue
            $Entry.Id | Should -BeNullOrEmpty
            $Entry.ErrorId | Should -BeExactly 'CatalogRenameConflict'
        }
        It 'returns the refused entry a NotFound registered, with its ErrorId' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'administrativeUnits' -Name 'AU-New' -PreviousName 'AU-Old' -Id $null -PreviousId $null -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'administrativeUnits' -Name 'AU-New' -RenameMap $Map
            }
            $Entry.Refused | Should -BeTrue
            $Entry.Id | Should -BeNullOrEmpty
            $Entry.ErrorId | Should -BeExactly 'AdministrativeUnitRenameNotFound'
        }
        It 'returns $null for a name whose entry was Current (nothing registered)' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name 'AP-New' -PreviousName 'AP-Old' -Id 'x' -PreviousId $null -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'accessPackages' -Name 'AP-New' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Key format, held against a hand-written key' {
        It 'reads the lower-cased section|name key' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Map['accesspackages|ap-new'] = [PSCustomObject]@{ Id = 'p3'; Refused = $false }
                Get-OERStructureRenameTarget -Section 'accessPackages' -Name 'AP-New' -RenameMap $Map
            }
            $Entry.Id | Should -BeExactly 'p3'
        }
    }
}
