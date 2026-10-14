# One row per section the helper serves: the kind words and the ErrorId prefix it must use, the
# arguments that name the section (Splat -- an assignment policy needs the access package it sits in),
# the row a Failed outcome is reported on (a policy is a row of its package's entry, decision D2), and
# the lower-cased map key base of an entry named 'New-Name'. Defined at the top level so Pester's
# discovery phase sees it for the -ForEach Contexts below.
$script:Kinds = @(
    @{ Section = 'administrativeUnits'; Prefix = 'AdministrativeUnit'; Capital = 'Administrative unit'; One = 'administrative unit'; Many = 'administrative units'; Article = 'an'; Where = ''
        Splat = @{ Section = 'administrativeUnits' }; RowSection = 'administrativeUnits'; RowItem = 'New-Name'; DetailPrefix = ''; KeyBase = 'administrativeunits' }
    @{ Section = 'catalogs'; Prefix = 'Catalog'; Capital = 'Catalog'; One = 'catalog'; Many = 'catalogs'; Article = 'a'; Where = ''
        Splat = @{ Section = 'catalogs' }; RowSection = 'catalogs'; RowItem = 'New-Name'; DetailPrefix = ''; KeyBase = 'catalogs' }
    @{ Section = 'accessPackages'; Prefix = 'AccessPackage'; Capital = 'Access package'; One = 'access package'; Many = 'access packages'; Article = 'an'; Where = ''
        Splat = @{ Section = 'accessPackages' }; RowSection = 'accessPackages'; RowItem = 'New-Name'; DetailPrefix = ''; KeyBase = 'accesspackages' }
    @{ Section = 'assignmentPolicies'; Prefix = 'AssignmentPolicy'; Capital = 'Assignment policy'; One = 'assignment policy'; Many = 'assignment policies'; Article = 'an'; Where = " in access package 'AP-Main'"
        Splat = @{ Section = 'assignmentPolicies'; AccessPackage = 'AP-Main' }; RowSection = 'accessPackages'; RowItem = 'AP-Main'; DetailPrefix = "assignmentPolicy 'New-Name': "; KeyBase = 'assignmentpolicies|ap-main' }
    @{ Section = 'accessReviews'; Prefix = 'AccessReview'; Capital = 'Access review'; One = 'access review'; Many = 'access reviews'; Article = 'an'; Where = ''
        Splat = @{ Section = 'accessReviews' }; RowSection = 'accessReviews'; RowItem = 'New-Name'; DetailPrefix = ''; KeyBase = 'accessreviews' }
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
            $script:Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' `
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
        It 'builds one Failed result row on the row section and item of the kind' {
            $script:Hit.Result.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
            $script:Hit.Result.Action | Should -BeExactly 'Failed'
            $script:Hit.Result.Section | Should -BeExactly $RowSection
            $script:Hit.Result.Item | Should -BeExactly $RowItem
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
        It 'carries the same phrases in the Failed row detail, after the policy prefix where there is one' {
            $Detail = $script:Hit.Result.Detail
            $Detail.StartsWith($DetailPrefix, [System.StringComparison]::Ordinal) | Should -BeTrue
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
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-00000000000a' -PreviousId 'AAAAAAAA-0000-0000-0000-00000000000A'
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'is Current when the two ids are identical' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' `
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
            $script:Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null
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
        It 'builds one Failed result row on the row section and item of the kind' {
            $script:Hit.Result.Action | Should -BeExactly 'Failed'
            $script:Hit.Result.Section | Should -BeExactly $RowSection
            $script:Hit.Result.Item | Should -BeExactly $RowItem
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
        It 'carries the same phrases in the Failed row detail, after the policy prefix where there is one' {
            $Detail = $script:Hit.Result.Detail
            $Detail.StartsWith($DetailPrefix, [System.StringComparison]::Ordinal) | Should -BeTrue
            $Detail | Should -Match "'New-Name'"
            $Detail | Should -Match "'Old-Name'"
            $Detail | Should -Match "matches $Article $One"
            $Detail | Should -Match 'nothing was created'
            $Detail | Should -Match 'wait and re-run'
            $Detail | Should -Match 'remove previousDisplayName'
        }
        It 'treats empty ids as no match' {
            $Empty = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id '' -PreviousId ''
            }
            $Empty.Outcome | Should -BeExactly 'NotFound'
            $Empty.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly "${Prefix}RenameNotFound"
            $Empty.Result.Action | Should -BeExactly 'Failed'
        }
        It 'treats an omitted id pair as no match' {
            $Omitted = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name'
            }
            $Omitted.Outcome | Should -BeExactly 'NotFound'
        }
    }

    Context 'Rename: only the previous name resolves (<Section>)' -ForEach $script:Kinds {
        It 'acts on the previous id and names the previous name as RenameFrom' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId 'p'
            }
            $Hit.Outcome | Should -BeExactly 'Rename'
            $Hit.Id | Should -BeExactly 'p'
            $Hit.RenameFrom | Should -BeExactly 'Old-Name'
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'is also Rename when the displayName id is the empty string' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id '' -PreviousId 'p'
            }
            $Hit.Outcome | Should -BeExactly 'Rename'
            $Hit.Id | Should -BeExactly 'p'
        }
    }

    Context 'Current: only the new name resolves (<Section>)' -ForEach $script:Kinds {
        It 'acts on the displayName id when the previous name matches nothing' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId $null
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'x'
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'acts on the displayName id when the previous id is the empty string' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId ''
            }
            $Hit.Outcome | Should -BeExactly 'Current'
            $Hit.Id | Should -BeExactly 'x'
        }
    }

    # Known answers, typed here and not derived from the helper: the sentences are the contract of the
    # five kinds, and the three kinds that existed before decision D1 must read exactly as they did.
    Context 'Exact texts (<Section>)' -ForEach $script:Kinds {
        It 'words the Conflict message and row detail exactly' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002'
            }
            $Hit.ErrorRecord.Exception.Message | Should -BeExactly "$Capital 'New-Name' (aaaaaaaa-0000-0000-0000-000000000001) and its previousDisplayName 'Old-Name' (aaaaaaaa-0000-0000-0000-000000000002)$Where are different $Many. The document never merges two $Many, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName."
            $Hit.Result.Detail | Should -BeExactly "${DetailPrefix}both 'New-Name' and its previousDisplayName 'Old-Name' exist$Where as different $Many; the document never merges two $Many, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
        }
        It 'words the NotFound message and row detail exactly' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null
            }
            $Hit.ErrorRecord.Exception.Message | Should -BeExactly "Neither 'New-Name' nor its previousDisplayName 'Old-Name' matches $Article $One$Where, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new $One, remove previousDisplayName."
            $Hit.Result.Detail | Should -BeExactly "${DetailPrefix}neither 'New-Name' nor its previousDisplayName 'Old-Name' matches $Article $One$Where, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new $One, remove previousDisplayName"
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

    # Decision D2: a policy row is a row of its package's entry, the policy named in the detail.
    Context 'Messages and rows of an assignment policy name its access package' {
        It 'names the package the call passes in the Conflict message and detail, and reports on that package' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002' -AccessPackage 'AP-Other'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Match "in access package 'AP-Other' are different assignment policies"
            $Hit.ErrorRecord.Exception.Message | Should -Not -Match 'AP-Main'
            $Hit.ErrorRecord.TargetObject | Should -BeExactly 'POL-New'
            $Hit.Result.Section | Should -BeExactly 'accessPackages'
            $Hit.Result.Item | Should -BeExactly 'AP-Other'
            $Hit.Result.Detail | Should -BeLike "assignmentPolicy 'POL-New': both 'POL-New' and its previousDisplayName 'POL-Old' exist in access package 'AP-Other' as different assignment policies;*"
        }
        It 'names the package the call passes in the NotFound message and detail, and reports on that package' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId $null -AccessPackage 'AP-Other'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Match "matches an assignment policy in access package 'AP-Other', so nothing was created or renamed"
            $Hit.ErrorRecord.TargetObject | Should -BeExactly 'POL-New'
            $Hit.Result.Section | Should -BeExactly 'accessPackages'
            $Hit.Result.Item | Should -BeExactly 'AP-Other'
            $Hit.Result.Detail | Should -BeLike "assignmentPolicy 'POL-New': neither 'POL-New' nor its previousDisplayName 'POL-Old' matches an assignment policy in access package 'AP-Other', so nothing was created*"
        }
        It 'does not take the package id for the package name in the messages or the row' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId $null `
                    -AccessPackage 'AP-Main' -AccessPackageId 'bbbbbbbb-0000-0000-0000-00000000000b'
            }
            $Hit.Result.Item | Should -BeExactly 'AP-Main'
            $Hit.ErrorRecord.Exception.Message | Should -Not -Match 'bbbbbbbb'
            $Hit.Result.Detail | Should -Not -Match 'bbbbbbbb'
        }
        It 'ignores -Catalog for an assignment policy' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId $null -AccessPackage 'AP-Main' -Catalog 'C1'
            }
            $Hit.ErrorRecord.Exception.Message | Should -Not -Match 'in catalog'
            $Hit.Result.Detail | Should -Not -Match 'in catalog'
        }
        It 'ignores -AccessPackage and -AccessPackageId for every section but assignmentPolicies' -ForEach @(
            @{ Section = 'administrativeUnits' }
            @{ Section = 'catalogs' }
            @{ Section = 'accessPackages' }
            @{ Section = 'accessReviews' }
        ) {
            $Result = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Hit = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId 'bbbbbbbb-0000-0000-0000-00000000000b' -RenameMap $Map
                $Gone = Resolve-OERStructureRename -Section $Section -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null `
                    -AccessPackage 'AP-Main' -AccessPackageId 'bbbbbbbb-0000-0000-0000-00000000000b'
                [PSCustomObject]@{ Outcome = $Hit.Outcome; Keys = @($Map.Keys); Item = $Gone.Result.Item; Message = $Gone.ErrorRecord.Exception.Message }
            }
            $Result.Outcome | Should -BeExactly 'Rename'
            $Result.Keys | Should -HaveCount 1
            $Result.Keys[0] | Should -BeExactly ($Section.ToLowerInvariant() + '|new-name')
            $Result.Item | Should -BeExactly 'New-Name'
            $Result.Message | Should -Not -Match 'access package ''AP-Main'''
        }
    }

    Context 'Run-scoped rename map (<Section>)' -ForEach $script:Kinds {
        It 'registers a Rename as not refused, with the previous id, under the lower-cased key' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-NAME' -PreviousName 'Old-Name' -Id $null -PreviousId 'p' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Key = @($Map.Keys)[0]; Entry = @($Map.Values)[0] }
            }
            $Result.Count | Should -Be 1
            $Result.Key | Should -BeExactly "$KeyBase|new-name"
            $Result.Entry.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRenameTarget'
            $Result.Entry.Section | Should -BeExactly $Section
            $Result.Entry.Name | Should -BeExactly 'New-NAME'
            $Result.Entry.PreviousName | Should -BeExactly 'Old-Name'
            $Result.Entry.Id | Should -BeExactly 'p'
            $Result.Entry.Refused | Should -BeFalse
            $Result.Entry.ErrorId | Should -BeNullOrEmpty
            $Result.Entry.Reason | Should -BeNullOrEmpty
        }
        It 'registers a Conflict as refused with the <Prefix>RenameConflict id and no object id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat; KeyBase = $KeyBase } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' `
                    -Id 'aaaaaaaa-0000-0000-0000-000000000001' -PreviousId 'aaaaaaaa-0000-0000-0000-000000000002' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Entry = $Map["$KeyBase|new-name"] }
            }
            $Result.Count | Should -Be 1
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Id | Should -BeNullOrEmpty
            $Result.Entry.ErrorId | Should -BeExactly "${Prefix}RenameConflict"
            $Result.Entry.Reason | Should -BeExactly "${Prefix}RenameConflict"
            $Result.Entry.PreviousName | Should -BeExactly 'Old-Name'
        }
        It 'registers a NotFound as refused with the <Prefix>RenameNotFound id and no object id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat; KeyBase = $KeyBase } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Entry = $Map["$KeyBase|new-name"] }
            }
            $Result.Count | Should -Be 1
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Id | Should -BeNullOrEmpty
            $Result.Entry.ErrorId | Should -BeExactly "${Prefix}RenameNotFound"
            $Result.Entry.Reason | Should -BeExactly "${Prefix}RenameNotFound"
        }
        It 'registers nothing for a Current outcome' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId $null -RenameMap $Map
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id 'x' -PreviousId 'x' -RenameMap $Map
                $Map.Count
            }
            $Result | Should -Be 0
        }
        It 'removes, for a Current outcome, an earlier entry registered for its key, and only that one (<Earlier>)' -ForEach @(
            @{ Earlier = 'undecided' }
            @{ Earlier = 'refused' }
        ) {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat; KeyBase = $KeyBase; Earlier = $Earlier } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($Earlier -eq 'undecided') {
                    $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Undecided -Reason 'one of its names could not be looked up' -RenameMap $Map
                } else {
                    $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $null -PreviousId $null -RenameMap $Map
                }
                $null = Resolve-OERStructureRename @Splat -Name 'Other-Name' -PreviousName 'Old-Name' -Id $null -PreviousId 'p' -RenameMap $Map
                $Before = $Map.Count
                $null = Resolve-OERStructureRename @Splat -Name 'NEW-name' -PreviousName 'Old-Name' -Id 'x' -PreviousId $null -RenameMap $Map
                [PSCustomObject]@{ Before = $Before; After = $Map.Count; Gone = -not $Map.ContainsKey("$KeyBase|new-name"); Kept = $Map.ContainsKey("$KeyBase|other-name") }
            }
            $Result.Before | Should -Be 2
            $Result.After | Should -Be 1
            $Result.Gone | Should -BeTrue
            $Result.Kept | Should -BeTrue
        }
        It 'returns the same outcome without a map as with one' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Without = Resolve-OERStructureRename @Splat -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p'
                $With = Resolve-OERStructureRename @Splat -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p' -RenameMap $Map
                [PSCustomObject]@{ Without = $Without; With = $With }
            }
            $Result.Without.Outcome | Should -BeExactly 'Rename'
            $Result.Without.Id | Should -BeExactly 'p'
            $Result.With.Outcome | Should -BeExactly $Result.Without.Outcome
            $Result.With.Id | Should -BeExactly $Result.Without.Id
        }
        It 'keeps two entries of different sections apart in one map' {
            $Count = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat; Section = $Section } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Other = if ($Section -eq 'catalogs') { 'accessPackages' } else { 'catalogs' }
                $null = Resolve-OERStructureRename @Splat -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p1' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section $Other -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p2' -RenameMap $Map
                $Map.Count
            }
            $Count | Should -Be 2
        }
    }

    # Decision D1: a policy is registered per access package, under the package's display name and, when
    # the id is known, under its object id as well; the outcome (Rename, a refusal, the removal a
    # Current makes) is applied under both.
    Context 'Rename map keys of an assignment policy' {
        BeforeAll {
            $script:PackageId = 'bbbbbbbb-0000-0000-0000-00000000000b'
            $script:PackageIdKey = 'assignmentpolicies|bbbbbbbb-0000-0000-0000-00000000000b|pol-new'
        }
        It 'registers the key with the package name alone when no package id is given' {
            $Result = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' -AccessPackage 'AP-Main' -RenameMap $Map
                [PSCustomObject]@{ Keys = @($Map.Keys) }
            }
            $Result.Keys | Should -HaveCount 1
            $Result.Keys[0] | Should -BeExactly 'assignmentpolicies|ap-main|pol-new'
        }
        It 'registers a Rename under the key with the package id as well, as the same entry' {
            $Result = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                [PSCustomObject]@{
                    Keys  = @($Map.Keys | Sort-Object)
                    ByName = $Map['assignmentpolicies|ap-main|pol-new']
                    ById   = $Map['assignmentpolicies|bbbbbbbb-0000-0000-0000-00000000000b|pol-new']
                    Same   = [object]::ReferenceEquals($Map['assignmentpolicies|ap-main|pol-new'], $Map['assignmentpolicies|bbbbbbbb-0000-0000-0000-00000000000b|pol-new'])
                }
            }
            $Result.Keys | Should -HaveCount 2
            $Result.Keys[0] | Should -BeExactly 'assignmentpolicies|ap-main|pol-new'
            $Result.Keys[1] | Should -BeExactly $script:PackageIdKey
            $Result.Same | Should -BeTrue
            $Result.ById.Id | Should -BeExactly 'p'
            $Result.ById.Refused | Should -BeFalse
            $Result.ByName.Id | Should -BeExactly 'p'
            $Result.ByName.Section | Should -BeExactly 'assignmentPolicies'
        }
        It 'lower-cases the package id in its key' {
            $Result = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId 'BBBBBBBB-0000-0000-0000-00000000000B' -RenameMap $Map
                [PSCustomObject]@{ Keys = @($Map.Keys | Sort-Object) }
            }
            $Result.Keys | Should -HaveCount 2
            ($Result.Keys -ccontains $script:PackageIdKey) | Should -BeTrue
            ($Result.Keys -ccontains 'assignmentpolicies|ap-main|pol-new') | Should -BeTrue
        }
        It 'registers a refusal under both keys: <Decision>' -ForEach @(
            @{ Decision = 'Conflict'; Id = 'aaaaaaaa-0000-0000-0000-000000000001'; PreviousId = 'aaaaaaaa-0000-0000-0000-000000000002'; WantId = 'AssignmentPolicyRenameConflict' }
            @{ Decision = 'NotFound'; Id = $null; PreviousId = $null; WantId = 'AssignmentPolicyRenameNotFound' }
        ) {
            $Result = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId; Id = $Id; PreviousId = $PreviousId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $Id -PreviousId $PreviousId `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                [PSCustomObject]@{
                    Count  = $Map.Count
                    ByName = $Map['assignmentpolicies|ap-main|pol-new']
                    ById   = $Map['assignmentpolicies|bbbbbbbb-0000-0000-0000-00000000000b|pol-new']
                }
            }
            $Result.Count | Should -Be 2
            foreach ($Entry in @($Result.ByName, $Result.ById)) {
                $Entry.Refused | Should -BeTrue
                $Entry.Id | Should -BeNullOrEmpty
                $Entry.ErrorId | Should -BeExactly $WantId
                $Entry.Reason | Should -BeExactly $WantId
            }
        }
        It 'removes both keys for a Current outcome, and only the keys of that policy in that package' {
            $Result = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-Other' -PreviousName 'POL-Old' -Id $null -PreviousId 'p2' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p3' `
                    -AccessPackage 'AP-Elsewhere' -RenameMap $Map
                $Before = $Map.Count
                $Hit = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'pol-NEW' -PreviousName 'POL-Old' -Id 'x' -PreviousId $null `
                    -AccessPackage 'ap-main' -AccessPackageId $PackageId.ToUpperInvariant() -RenameMap $Map
                [PSCustomObject]@{ Before = $Before; Outcome = $Hit.Outcome; Keys = @($Map.Keys | Sort-Object) }
            }
            $Result.Before | Should -Be 5
            $Result.Outcome | Should -BeExactly 'Current'
            $Result.Keys | Should -HaveCount 3
            $Result.Keys | Should -Not -Contain 'assignmentpolicies|ap-main|pol-new'
            $Result.Keys | Should -Not -Contain $script:PackageIdKey
            $Result.Keys | Should -Contain 'assignmentpolicies|ap-main|pol-other'
            $Result.Keys | Should -Contain 'assignmentpolicies|bbbbbbbb-0000-0000-0000-00000000000b|pol-other'
            $Result.Keys | Should -Contain 'assignmentpolicies|ap-elsewhere|pol-new'
        }
        It 'keeps a policy of the same name in two packages apart' {
            $Result = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-One' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p2' -AccessPackage 'AP-Two' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; One = $Map['assignmentpolicies|ap-one|pol-new'].Id; Two = $Map['assignmentpolicies|ap-two|pol-new'].Id }
            }
            $Result.Count | Should -Be 2
            $Result.One | Should -BeExactly 'p1'
            $Result.Two | Should -BeExactly 'p2'
        }
        It 'keeps a policy and an access review of the same name apart' {
            $Count = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p1' -AccessPackage 'AP-Main' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'accessReviews' -Name 'Same-Name' -PreviousName 'Old' -Id $null -PreviousId 'p2' -RenameMap $Map
                $Map.Count
            }
            $Count | Should -Be 2
        }
        It 'registers one key when the package id spells the package name' {
            $Count = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId 'ap-MAIN' -RenameMap $Map
                $Map.Count
            }
            $Count | Should -Be 1
        }
        It 'treats an empty package id as none' {
            $Count = InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId '' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-Next' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId $null -RenameMap $Map
                $Map.Count
            }
            $Count | Should -Be 2
        }
        It 'registers an Undecided mark under the name key only, whatever the package id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Undecided -Reason 'r' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                [PSCustomObject]@{ Keys = @($Map.Keys); Entry = $Map['assignmentpolicies|ap-main|pol-new'] }
            }
            $Result.Keys | Should -HaveCount 1
            $Result.Keys[0] | Should -BeExactly 'assignmentpolicies|ap-main|pol-new'
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Reason | Should -BeExactly 'r'
        }
        It 'replaces an Undecided mark by the decision, which adds the key with the package id' {
            $Result = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Undecided -Reason 'r' `
                    -AccessPackage 'AP-Main' -RenameMap $Map
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId -RenameMap $Map
                [PSCustomObject]@{ Keys = @($Map.Keys | Sort-Object); ByName = $Map['assignmentpolicies|ap-main|pol-new'] }
            }
            $Result.Keys | Should -HaveCount 2
            $Result.ByName.Refused | Should -BeFalse
            $Result.ByName.Id | Should -BeExactly 'p'
            $Result.ByName.Reason | Should -BeNullOrEmpty
        }
        It 'registers nothing without a map, with or without a package id' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ PackageId = $script:PackageId } {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'POL-New' -PreviousName 'POL-Old' -Id $null -PreviousId 'p' `
                    -AccessPackage 'AP-Main' -AccessPackageId $PackageId
            }
            $Hit.Outcome | Should -BeExactly 'Rename'
            $Hit.Id | Should -BeExactly 'p'
        }
    }

    # R12: a rename the run cannot decide -- one of its names could not be looked up, or -Include leaves
    # the section out -- is registered as refused with a reason, so a reference to the new name is refused
    # instead of looked up by name. A decision for the same key replaces it.
    Context 'Undecided (<Section>)' -ForEach $script:Kinds {
        It 'registers a refused entry with the reason, no object id and no error id, under the lower-cased key' {
            $Result = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-NAME' -PreviousName 'Old-Name' -Undecided -Reason 'one of its names could not be looked up' -RenameMap $Map
                [PSCustomObject]@{ Count = $Map.Count; Key = @($Map.Keys)[0]; Entry = @($Map.Values)[0] }
            }
            $Result.Count | Should -Be 1
            $Result.Key | Should -BeExactly "$KeyBase|new-name"
            $Result.Entry.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRenameTarget'
            $Result.Entry.Section | Should -BeExactly $Section
            $Result.Entry.Name | Should -BeExactly 'New-NAME'
            $Result.Entry.PreviousName | Should -BeExactly 'Old-Name'
            $Result.Entry.Refused | Should -BeTrue
            $Result.Entry.Id | Should -BeNullOrEmpty
            $Result.Entry.ErrorId | Should -BeNullOrEmpty
            $Result.Entry.Reason | Should -BeExactly 'one of its names could not be looked up'
        }
        It 'returns the Undecided outcome with nothing to act on and nothing to report' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Undecided -Reason 'r' -RenameMap $Map
            }
            $Hit.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureRename'
            $Hit.Outcome | Should -BeExactly 'Undecided'
            $Hit.Id | Should -BeNullOrEmpty
            $Hit.RenameFrom | Should -BeNullOrEmpty
            $Hit.ErrorRecord | Should -BeNullOrEmpty
            $Hit.Result | Should -BeNullOrEmpty
        }
        It 'registers nothing and returns the same outcome without a map' {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Undecided -Reason 'r'
            }
            $Hit.Outcome | Should -BeExactly 'Undecided'
        }
        It 'is replaced by the decision made afterwards for the same key: <Decision>' -ForEach @(
            @{ Decision = 'Rename'; Id = ''; PreviousId = 'p'; Refused = $false; WantId = 'p'; WantReason = '' }
            @{ Decision = 'Conflict'; Id = 'a'; PreviousId = 'b'; Refused = $true; WantId = ''; WantReason = 'Conflict' }
            @{ Decision = 'NotFound'; Id = ''; PreviousId = ''; Refused = $true; WantId = ''; WantReason = 'NotFound' }
        ) {
            $Entry = InModuleScope $script:moduleName -Parameters @{ Splat = $Splat; Id = $Id; PreviousId = $PreviousId } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Undecided -Reason 'one of its names could not be looked up' -RenameMap $Map
                $null = Resolve-OERStructureRename @Splat -Name 'New-Name' -PreviousName 'Old-Name' -Id $Id -PreviousId $PreviousId -RenameMap $Map
                if ($Map.Count -ne 1) { throw "expected one entry, found $($Map.Count)" }
                @($Map.Values)[0]
            }
            $Entry.Refused | Should -Be $Refused
            if ($WantId) { $Entry.Id | Should -BeExactly $WantId } else { $Entry.Id | Should -BeNullOrEmpty }
            if ($WantReason) {
                $Entry.Reason | Should -BeExactly "${Prefix}Rename$WantReason"
                $Entry.ErrorId | Should -BeExactly "${Prefix}Rename$WantReason"
            } else {
                $Entry.Reason | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Parameter contract' {
        It 'refuses an empty reason for an undecided rename' {
            InModuleScope $script:moduleName {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                { Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Undecided -Reason '' -RenameMap $Map -ErrorAction Stop } | Should -Throw
                $Map.Count | Should -Be 0
            }
        }
        It 'refuses -Undecided together with the ids of a decision' {
            InModuleScope $script:moduleName {
                { Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Undecided -Reason 'r' -Id 'a' -ErrorAction Stop } | Should -Throw
            }
        }
        It 'refuses a section other than the five it serves' {
            InModuleScope $script:moduleName {
                { Resolve-OERStructureRename -Section 'groups' -Name 'N' -PreviousName 'O' -ErrorAction Stop } | Should -Throw
            }
        }
        It 'serves the assignmentPolicies and accessReviews sections' -ForEach @(
            @{ Section = 'assignmentPolicies' }
            @{ Section = 'accessReviews' }
        ) {
            $Hit = InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                Resolve-OERStructureRename -Section $Section -Name 'N' -PreviousName 'O' -Id 'a' -AccessPackage 'AP'
            }
            $Hit.Outcome | Should -BeExactly 'Current'
        }
        It 'takes -AccessPackage and -AccessPackageId as optional strings in both parameter sets' {
            $Sets = InModuleScope $script:moduleName {
                @((Get-Command Resolve-OERStructureRename).ParameterSets | ForEach-Object {
                        $Package = @($_.Parameters.Where({ $_.Name -in 'AccessPackage', 'AccessPackageId' }))
                        [PSCustomObject]@{
                            Name      = $_.Name
                            Names     = @($Package.Name)
                            Mandatory = @($Package | Where-Object { $_.IsMandatory } | ForEach-Object { $_.Name })
                            Types     = @($Package.ParameterType | ForEach-Object { $_.FullName })
                        }
                    })
            }
            @($Sets.Name | Sort-Object) | Should -Be @('Decide', 'Undecided')
            foreach ($Set in $Sets) {
                @($Set.Names | Sort-Object) | Should -Be @('AccessPackage', 'AccessPackageId')
                $Set.Mandatory | Should -HaveCount 0
                $Set.Types | Should -Be @('System.String', 'System.String')
            }
        }
        It 'accepts -AccessPackage and -AccessPackageId together with -Undecided' {
            $Hit = InModuleScope $script:moduleName {
                Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'N' -PreviousName 'O' -Undecided -Reason 'r' -AccessPackage 'AP' -AccessPackageId 'bbbbbbbb-0000-0000-0000-00000000000b'
            }
            $Hit.Outcome | Should -BeExactly 'Undecided'
        }
        It 'throws an ArgumentException for an assignment policy when -AccessPackage is <Case>, registering nothing' -ForEach @(
            @{ Case = 'omitted'; Bound = @{} }
            @{ Case = 'null'; Bound = @{ AccessPackage = $null } }
            @{ Case = 'empty'; Bound = @{ AccessPackage = '' } }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Bound = $Bound } {
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                { Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p' @Bound -AccessPackageId 'bbbbbbbb-0000-0000-0000-00000000000b' -RenameMap $Map } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*-AccessPackage is required*'
                { Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'N' -PreviousName 'O' -Undecided -Reason 'r' @Bound -RenameMap $Map } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*-AccessPackage is required*'
                $Map.Count | Should -Be 0
            }
        }
        It 'does not require -AccessPackage for any other section' -ForEach @(
            @{ Section = 'administrativeUnits' }
            @{ Section = 'catalogs' }
            @{ Section = 'accessPackages' }
            @{ Section = 'accessReviews' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Section = $Section } {
                { Resolve-OERStructureRename -Section $Section -Name 'N' -PreviousName 'O' -Id $null -PreviousId 'p' } | Should -Not -Throw
                { Resolve-OERStructureRename -Section $Section -Name 'N' -PreviousName 'O' -Undecided -Reason 'r' } | Should -Not -Throw
            }
        }
        It 'writes nothing to the error stream for any outcome' {
            $Count = InModuleScope $script:moduleName {
                $Before = $Error.Count
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Id $null -PreviousId $null
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'N' -PreviousName 'O' -Id 'a' -PreviousId 'b'
                $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -Name 'N' -PreviousName 'O' -Id $null -PreviousId $null -AccessPackage 'AP'
                $null = Resolve-OERStructureRename -Section 'accessReviews' -Name 'N' -PreviousName 'O' -Id 'a' -PreviousId 'b'
                $Error.Count - $Before
            }
            $Count | Should -Be 0
        }
    }
}
