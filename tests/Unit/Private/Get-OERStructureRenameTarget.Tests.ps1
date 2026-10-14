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
        It 'refuses a section other than the four it serves' -ForEach @(
            @{ Section = 'groups' }
            @{ Section = 'accessReviews' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                { Get-OERStructureRenameTarget -Section $Section -Name 'N' -ErrorAction Stop } | Should -Throw
            }
        }
        It 'serves the assignmentPolicies section' {
            InModuleScope $script:moduleName {
                { Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'N' -AccessPackage 'AP' -ErrorAction Stop } | Should -Not -Throw
            }
        }
        It 'takes -AccessPackage as an optional string' {
            $Parameter = InModuleScope $script:moduleName { (Get-Command Get-OERStructureRenameTarget).Parameters['AccessPackage'] }
            $Parameter.ParameterType | Should -Be ([string])
            $Parameter.ParameterSets.Values.IsMandatory | Should -BeFalse
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
            $Entry.Reason | Should -BeNullOrEmpty
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
            $Entry.Reason | Should -BeExactly 'CatalogRenameConflict'
        }
        It 'returns the refused entry an undecided rename registered, with its Reason and no ErrorId (R12)' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'administrativeUnits' -Name 'AU-New' -PreviousName 'AU-Old' -Undecided `
                    -Reason 'one of its names could not be looked up' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'administrativeUnits' -Name 'au-new' -RenameMap $Map
            }
            $Entry.Refused | Should -BeTrue
            $Entry.Id | Should -BeNullOrEmpty
            $Entry.ErrorId | Should -BeNullOrEmpty
            $Entry.Reason | Should -BeExactly 'one of its names could not be looked up'
            $Entry.PreviousName | Should -BeExactly 'AU-Old'
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
            $Entry.Reason | Should -BeExactly 'AdministrativeUnitRenameNotFound'
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

    # Decision D1: a policy is registered per access package, so the reader needs the package term. The
    # round trips below hold the key format of the two files together.
    Context 'Assignment policies, found by their access package' {
        BeforeAll {
            $script:PackageId = 'bbbbbbbb-0000-0000-0000-00000000000b'
        }
        It 'returns the entry a Rename registered, for the package name' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Main' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRenameTarget'
            $Entry.Section | Should -BeExactly 'assignmentPolicies'
            $Entry.Name | Should -BeExactly 'POL-New'
            $Entry.PreviousName | Should -BeExactly 'POL-Old'
            $Entry.Id | Should -BeExactly 'p1'
            $Entry.Refused | Should -BeFalse
        }
        It 'returns the entry a Rename registered, for the package id' {
            $Entry = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage $PackageId -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.Id | Should -BeExactly 'p1'
            $Entry.Refused | Should -BeFalse
        }
        It 'finds the entry under a policy name and a package name, or a package id, in other letter case' {
            $Found = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                [PSCustomObject]@{
                    ByName = (Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-NEW' -AccessPackage 'ap-MAIN' -RenameMap $Map).Id
                    ById   = (Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-NEW' -AccessPackage $PackageId.ToUpperInvariant() -RenameMap $Map).Id
                }
            }
            $Found.ByName | Should -BeExactly 'p1'
            $Found.ById | Should -BeExactly 'p1'
        }
        It 'finds the entry in other letter case even in a map built with the default case-sensitive comparer' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new()
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p2' -AccessPackage 'AP-Main' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-new' -AccessPackage 'ap-main' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.Id | Should -BeExactly 'p2'
        }
        It 'finds the entry by an upper-case package id in a default case-sensitive map, so both files lower-case the id' {
            $Found = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new()
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p5' `
                    -AccessPackage 'AP-Main' -AccessPackageId 'BBBBBBBB-0000-0000-0000-00000000000B' -RenameMap $Map
                [PSCustomObject]@{
                    ByUpper = (Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'BBBBBBBB-0000-0000-0000-00000000000B' -RenameMap $Map).Id
                    ByLower = (Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-new' -AccessPackage 'bbbbbbbb-0000-0000-0000-00000000000b' -RenameMap $Map).Id
                }
            }
            $Found.ByUpper | Should -BeExactly 'p5'
            $Found.ByLower | Should -BeExactly 'p5'
        }
        It 'returns $null for the same policy name in another package, and for another policy name in the package' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Other' -RenameMap $Map | Should -BeNullOrEmpty
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-Other' -AccessPackage 'AP-Main' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for the package id of another package' {
            InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'cccccccc-0000-0000-0000-00000000000c' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for an empty or omitted -AccessPackage, even when the map holds the policy' -ForEach @(
            @{ Case = 'omitted'; Bound = @{} }
            @{ Case = 'null'; Bound = @{ AccessPackage = $null } }
            @{ Case = 'empty'; Bound = @{ AccessPackage = '' } }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Bound = $Bound } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                $Map['assignmentpolicies||pol-new'] = [PSCustomObject]@{ Id = 'must-not-be-read'; Refused = $false }
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' @Bound -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for an empty name, even with an access package' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name '' -AccessPackage 'AP-Main' -RenameMap $Map | Should -BeNullOrEmpty
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name $null -AccessPackage 'AP-Main' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns $null without a map' {
            InModuleScope $script:moduleName {
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Main' | Should -BeNullOrEmpty
            }
        }
        It 'returns $null for a policy whose entry was Current (nothing registered)' {
            InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id 'x' -PreviousId $null `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Main' -RenameMap $Map | Should -BeNullOrEmpty
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage $PackageId -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'returns the refused entry a Conflict or a NotFound registered, by package name and by package id' -ForEach @(
            @{ Decision = 'Conflict'; Id = 'aaaaaaaa-0000-0000-0000-000000000001'; PreviousId = 'aaaaaaaa-0000-0000-0000-000000000002'; WantId = 'AssignmentPolicyRenameConflict' }
            @{ Decision = 'NotFound'; Id = $null; PreviousId = $null; WantId = 'AssignmentPolicyRenameNotFound' }
        ) {
            $Found = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId; Id = $Id; PreviousId = $PreviousId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $Id -PreviousId $PreviousId `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                @(
                    Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Main' -RenameMap $Map
                    Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage $PackageId -RenameMap $Map
                )
            }
            $Found | Should -HaveCount 2
            foreach ($Entry in $Found) {
                $Entry.Refused | Should -BeTrue
                $Entry.Id | Should -BeNullOrEmpty
                $Entry.ErrorId | Should -BeExactly $WantId
                $Entry.Reason | Should -BeExactly $WantId
            }
        }
        # Task 6 fix round 1 (Fix B): an undecided mark is registered under the package id too when the id
        # is given, so it is found by the package's name and by its object id alike.
        It 'returns the refused entry an undecided rename registered, by package name and, when the id was given, by package id (R12)' {
            $Found = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Undecided `
                    -Reason 'one of its names could not be looked up' -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-Next' -PreviousName 'POL-Old' -Undecided `
                    -Reason 'one of its names could not be looked up' -AccessPackage 'AP-Main' -RenameMap $Map
                [PSCustomObject]@{
                    ByName       = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-new' -AccessPackage 'AP-Main' -RenameMap $Map
                    ById         = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-new' -AccessPackage $PackageId.ToUpperInvariant() -RenameMap $Map
                    NoIdByName   = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-Next' -AccessPackage 'AP-Main' -RenameMap $Map
                    NoIdById     = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-Next' -AccessPackage $PackageId -RenameMap $Map
                }
            }
            foreach ($Entry in @($Found.ByName, $Found.ById, $Found.NoIdByName)) {
                $Entry | Should -Not -BeNullOrEmpty
                $Entry.Refused | Should -BeTrue
                $Entry.Id | Should -BeNullOrEmpty
                $Entry.ErrorId | Should -BeNullOrEmpty
                $Entry.Reason | Should -BeExactly 'one of its names could not be looked up'
            }
            # A mark registered without the package id is found by the package's name only.
            $Found.NoIdById | Should -BeNullOrEmpty
        }
        It 'does not find a policy entry under the section|name key of another section, or the other way round' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p2' -RenameMap $Map
                (Get-OERStructureRenameTarget -Section 'accessPackages' -Name 'Same-Name' -RenameMap $Map).Id | Should -BeExactly 'p2'
                (Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'Same-Name' -AccessPackage 'AP-Main' -RenameMap $Map).Id | Should -BeExactly 'p1'
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'Same-Name' -AccessPackage 'accessPackages' -RenameMap $Map | Should -BeNullOrEmpty
            }
        }
        It 'ignores -AccessPackage for every other section' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                Get-OERStructureRenameTarget -Section 'catalogs' -Name 'CAT-New' -AccessPackage 'AP-Main' -RenameMap $Map
            }
            $Entry | Should -Not -BeNullOrEmpty
            $Entry.Id | Should -BeExactly 'p1'
        }
        It 'reads the lower-cased assignmentPolicies|package|name key, held against a hand-written key' {
            $Entry = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Map['assignmentpolicies|ap-main|pol-new'] = [PSCustomObject]@{ Id = 'p4'; Refused = $false }
                Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP-Main' -RenameMap $Map
            }
            $Entry.Id | Should -BeExactly 'p4'
        }
    }
}
