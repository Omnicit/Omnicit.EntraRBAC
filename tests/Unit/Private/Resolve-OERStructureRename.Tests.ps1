# One row per section the helper serves: the kind words and the ErrorId prefix it must use. Defined at
# the top level so Pester's discovery phase sees it for the -ForEach Contexts below.
$script:Kinds = @(
    @{ Section = 'administrativeUnits'; Prefix = 'AdministrativeUnit'; One = 'administrative unit'; Many = 'administrative units'; Article = 'an' }
    @{ Section = 'catalogs'; Prefix = 'Catalog'; One = 'catalog'; Many = 'catalogs'; Article = 'a' }
    @{ Section = 'accessPackages'; Prefix = 'AccessPackage'; One = 'access package'; Many = 'access packages'; Article = 'an' }
)

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

Describe 'Resolve-OERStructureRename' {

    Context 'Conflict: both names resolve to different objects (<Section>)' -ForEach $script:Kinds {
        BeforeAll {
            $script:Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002'
            }
        }
        It 'reports the Conflict outcome and acts on nothing' {
            $script:Hit.Outcome | Should -BeExactly 'Conflict'
            $script:Hit.Id | Should -BeNullOrEmpty
            $script:Hit.RenameFrom | Should -BeNullOrEmpty
        }
        It 'is tagged Omnicit.EntraRBAC.StructureRename' {
            $script:Hit.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRename'
        }
        It 'builds a <Prefix>RenameConflict error record with category ResourceExists and the new name as target' {
            $script:Hit.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $script:Hit.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameConflict"
            $script:Hit.ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
            $script:Hit.ErrorRecord.TargetObject | Should -BeExactly 'New-Name'
        }
        It 'builds one Failed result row for the section and the new name' {
            $script:Hit.Result.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
            $script:Hit.Result.Action | Should -BeExactly 'Failed'
            $script:Hit.Result.Section | Should -BeExactly $Section
            $script:Hit.Result.Item | Should -BeExactly 'New-Name'
            $script:Hit.Result.Error.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameConflict"
        }
        It 'names both names and both ids, and says it never merges two <Many>' {
            $Message = $script:Hit.ErrorRecord.Exception.Message
            $Message | Should -Match "'New-Name'"
            $Message | Should -Match "'Old-Name'"
            $Message | Should -Match 'aaaaaaaa-0000-0000-0000-000000000001'
            $Message | Should -Match 'aaaaaaaa-0000-0000-0000-000000000002'
            $Message | Should -Match "never merges two $Many"
            $Message | Should -Match 'nothing was changed'
            $Message | Should -Match 'remove previousDisplayName'
        }
        It 'carries the same phrases in the Failed row detail' {
            $Detail = $script:Hit.Result.Detail
            $Detail | Should -Match "'New-Name'"
            $Detail | Should -Match "'Old-Name'"
            $Detail | Should -Match "never merges two $Many"
            $Detail | Should -Match 'nothing was changed'
        }
        It 'does not name a catalog outside accessPackages' {
            $script:Hit.ErrorRecord.Exception.Message | Should -Not -Match 'in catalog'
        }
    }

    Context 'Same object found under both names (<Section>)' -ForEach $script:Kinds {
        It 'is Current when the two ids differ only in letter case, acting on the displayName id' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-00000000000a' -PreviousId 'AAAAAAAA-0000-0000-0000-00000000000A'
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'is Current when the two ids are identical' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'x' -PreviousId 'x'
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'x'
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
    }

    Context 'NotFound: neither name resolves (<Section>)' -ForEach $script:Kinds {
        BeforeAll {
            $script:Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null
            }
        }
        It 'reports the NotFound outcome and acts on nothing' {
            $script:Hit.Outcome | Should -BeExactly 'NotFound'
            $script:Hit.Id | Should -BeNullOrEmpty
            $script:Hit.RenameFrom | Should -BeNullOrEmpty
        }
        It 'builds a <Prefix>RenameNotFound error record with category ObjectNotFound and the new name as target' {
            $script:Hit.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $script:Hit.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameNotFound"
            $script:Hit.ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $script:Hit.ErrorRecord.TargetObject | Should -BeExactly 'New-Name'
        }
        It 'builds one Failed result row for the section and the new name' {
            $script:Hit.Result.Action | Should -BeExactly 'Failed'
            $script:Hit.Result.Section | Should -BeExactly $Section
            $script:Hit.Result.Item | Should -BeExactly 'New-Name'
            $script:Hit.Result.Error.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameNotFound"
        }
        It 'names both names and says nothing was created or renamed, to wait and re-run, or to remove previousDisplayName' {
            $Message = $script:Hit.ErrorRecord.Exception.Message
            $Message | Should -Match "'New-Name'"
            $Message | Should -Match "'Old-Name'"
            $Message | Should -Match "matches $Article $One"
            $Message | Should -Match 'nothing was created or renamed'
            $Message | Should -Match 'wait and re-run'
            $Message | Should -Match 'remove previousDisplayName'
            $Message | Should -Not -Match 'in catalog'
        }
        It 'carries the same phrases in the Failed row detail' {
            $Detail = $script:Hit.Result.Detail
            $Detail | Should -Match "'New-Name'"
            $Detail | Should -Match "'Old-Name'"
            $Detail | Should -Match "matches $Article $One"
            $Detail | Should -Match 'nothing was created'
            $Detail | Should -Match 'wait and re-run'
            $Detail | Should -Match 'remove previousDisplayName'
        }
        It 'treats empty ids as no match' {
            $Empty = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id '' -PreviousId ''
            }
            $Empty.Outcome | Should -BeExactly 'NotFound'
            $Empty.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameNotFound"
            $Empty.Result.Action | Should -BeExactly 'Failed'
        }
        It 'treats an omitted id pair as no match' {
            $Omitted = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name'
            }
            $Omitted.Outcome | Should -BeExactly 'NotFound'
        }
    }

    Context 'Rename: only the previous name resolves (<Section>)' -ForEach $script:Kinds {
        It 'acts on the previous id and names the previous name as RenameFrom' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId 'p'
            }
            $Hit.Outcome | Should -BeExactly 'Rename'
            $Hit.Id | Should -BeExactly 'p'
            $Hit.RenameFrom | Should -BeExactly 'Old-Name'
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'is also Rename when the displayName id is the empty string' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id '' -PreviousId 'p'
            }
            $Hit.Outcome | Should -BeExactly 'Rename'
            $Hit.Id | Should -BeExactly 'p'
        }
    }

    Context 'Current: only the new name resolves (<Section>)' -ForEach $script:Kinds {
        It 'acts on the displayName id when the previous name matches nothing' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId $null
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'x'
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'acts on the displayName id when the previous id is the empty string' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId ''
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'x'
        }
    }

    Context 'Messages of an access package name its catalog' {
        It 'says "in catalog ''C1''" in the Conflict message and row detail' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'accessPackages' -Name 'AP-New' -PreviousName 'AP-Old' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002' -Catalog 'C1'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Match "in catalog 'C1'"
            $Hit.Result.Detail | Should -Match "in catalog 'C1'"
        }
        It 'says "in catalog ''C1''" in the NotFound message and row detail' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'accessPackages' -Name 'AP-New' -PreviousName 'AP-Old' -Id $null -PreviousId $null -Catalog 'C1'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Match "in catalog 'C1'"
            $Hit.Result.Detail | Should -Match "in catalog 'C1'"
        }
        It 'names no catalog when an access package entry passes none' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'accessPackages' -Name 'AP-New' -PreviousName 'AP-Old' -Id $null -PreviousId $null
            }
            $Hit.ErrorRecord.Exception.Message | Should -Not -Match 'in catalog'
        }
        It 'ignores -Catalog for a section that is not accessPackages' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId $null -Catalog 'C1'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Not -Match 'in catalog'
        }
    }

    Context 'Run-scoped rename map (<Section>)' -ForEach $script:Kinds {
        It 'registers a Rename as not refused, with the previous id, under the lower-cased section|name key' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section $Section -Name 'New-NAME' -PreviousName 'Old-Name' -Id $null -PreviousId 'p' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Key = @($Map.Keys)[0]; Entry = @($Map.Values)[0] }
            }
            $Result.Count | Should -Be 1
            $Result.Key | Should -BeExactly ($Section.ToLowerInvariant() + '|new-name')
            $Result.Entry.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRenameTarget'
            $Result.Entry.Section | Should -BeExactly $Section
            $Result.Entry.Name | Should -BeExactly 'New-NAME'
            $Result.Entry.PreviousName | Should -BeExactly 'Old-Name'
            $Result.Entry.Id | Should -BeExactly 'p'
            $Result.Entry.Refused | Should -BeFalse
            $Result.Entry.ErrorId | Should -BeNullOrEmpty
        }
        It 'registers a Conflict as refused with the <Prefix>RenameConflict id and no object id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Entry = $Map[('{0}|new-name' -f $Section)] }
            }
            $Result.Count | Should -Be 1
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Id | Should -BeNullOrEmpty
            $Result.Entry.ErrorId | Should -BeExactly "${Prefix}RenameConflict"
            $Result.Entry.PreviousName | Should -BeExactly 'Old-Name'
        }
        It 'registers a NotFound as refused with the <Prefix>RenameNotFound id and no object id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Entry = $Map[('{0}|new-name' -f $Section)] }
            }
            $Result.Count | Should -Be 1
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Id | Should -BeNullOrEmpty
            $Result.Entry.ErrorId | Should -BeExactly "${Prefix}RenameNotFound"
        }
        It 'registers nothing for a Current outcome' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId $null -RenameMap $Map
                $null = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId 'x' -RenameMap $Map
                $Map.Count
            }
            $Result | Should -Be 0
        }
        It 'returns the same outcome without a map as with one' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Without = Resolve-OERStructureRename -Section $Section -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p'
                $With = Resolve-OERStructureRename -Section $Section -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p' -RenameMap $Map
                [PSCustomObject]@{ Without = $Without; With = $With }
            }
            $Result.Without.Outcome | Should -BeExactly 'Rename'
            $Result.Without.Id | Should -BeExactly 'p'
            $Result.With.Outcome | Should -BeExactly $Result.Without.Outcome
            $Result.With.Id | Should -BeExactly $Result.Without.Id
        }
        It 'keeps two entries of different sections apart in one map' {
            $Count = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Other = if ($Section -eq 'catalogs') { 'accessPackages' } else { 'catalogs' }
                $null = Resolve-OERStructureRename -Section $Section -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section $Other -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p2' -RenameMap $Map
                $Map.Count
            }
            $Count | Should -Be 2
        }
    }

    Context 'Parameter contract' {
        It 'refuses a section other than the three it serves' {
            InModuleScope $script:moduleName {
                { Resolve-OERStructureRename -Section 'groups' -Name 'N' -PreviousName 'O' -ErrorAction Stop } | Should -Throw
            }
        }
        It 'writes nothing to the error stream for any outcome' {
            $Count = InModuleScope $script:moduleName {
                $Before = $Error.Count
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Id $null -PreviousId $null
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Id 'a' -PreviousId 'b'
                $Error.Count - $Before
            }
            $Count | Should -Be 0
        }
    }
}
