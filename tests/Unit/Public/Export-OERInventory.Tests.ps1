BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"

    # BL-125 (A3): where a test reaches the REAL group reader, its PIM for Groups assignment read
    # answers as a successful read that lists nothing, so every member and owner a fixture lists reads
    # as standing and every existing expectation keeps its meaning. A test about the read overrides it.
    Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
        [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
    }

    # Sprint 11 step 6 (BL-133, A18): where a test reaches the REAL Get-OERInventory RoleAssignments
    # section, its principals are looked up with Resolve-OERPrincipalName -Detailed (one answer per id:
    # Id, Read, Found, Name, ObjectType, Cause); every other section keeps the default map. A fixture's
    # mock answers both forms through this: -Names maps an id to the name the directory returns for it,
    # and an id it does not hold is one the directory did not return.
    $script:AnswerPrincipalLookup = {
        param([string[]]$Id, [bool]$Detailed, [hashtable]$Names)
        if (-not $Detailed) {
            $Map = @{}
            foreach ($One in @($Id)) { if ($One -and $Names.ContainsKey($One)) { $Map[$One] = $Names[$One] } }
            return $Map
        }
        foreach ($One in @($Id | Where-Object { $_ } | Select-Object -Unique)) {
            $Found = $Names.ContainsKey($One)
            [PSCustomObject]@{ Id = $One; Read = $true; Found = $Found; Name = $(if ($Found) { [string]$Names[$One] } else { $null }); ObjectType = $null; Cause = $null }
        }
    }

    # F2 / A17. The bundle's README.md lists what the export could not read; the apply document and
    # every other JSON file must not. These helpers read the section back from a written bundle.
    $script:CouldNotReadHeading = '## What this export could not read'
    # The ten top-level keys ConvertTo-OERInventory emits, in order: the shape of inventory.json.
    $script:InventoryTopLevelKeys = @(
        'version', 'groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'accessReviews',
        'directoryRoleManagementPolicies', 'directoryRoleAssignments', 'roleAssignments', 'roleManagementPolicies'
    )
    # The README section, heading included, up to the next level 2 heading; $null when it is missing.
    function Get-ReadmeCouldNotReadSection {
        param([string]$BundlePath)
        $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
        $Start = $Readme.IndexOf($script:CouldNotReadHeading)
        if ($Start -lt 0) { return $null }
        $Next = $Readme.IndexOf("`n## ", $Start)
        if ($Next -lt 0) { return $Readme.Substring($Start) }
        $Readme.Substring($Start, $Next - $Start)
    }
    # The bullet lines of a section.
    function Get-SectionBullets {
        param([string]$Section)
        @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
    }
    # Proves the list stayed out of the apply document and every other JSON file: no file carries the
    # heading, the partial notice or any of the given texts (the README's bullet lines, since a bare
    # entry such as 'groups' is a word the JSON legitimately holds), and inventory.json keeps exactly
    # its ten keys.
    function Assert-ListStaysOutOfJson {
        param([string]$BundlePath, [string[]]$Forbidden)
        $JsonFiles = @(Get-ChildItem -Path $BundlePath -Filter '*.json')
        $JsonFiles.Count | Should -BeGreaterThan 10 -Because 'the per-area files and inventory.json were all written'
        foreach ($File in $JsonFiles) {
            $Raw = Get-Content $File.FullName -Raw
            foreach ($Text in (@($script:CouldNotReadHeading, 'This bundle is PARTIAL') + @($Forbidden))) {
                $Raw | Should -Not -Match ([regex]::Escape($Text)) -Because "$($File.Name) must not carry '$Text'"
            }
        }
        $Inventory = Get-Content (Join-Path $BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        ($Inventory.PSObject.Properties.Name -join ',') | Should -BeExactly ($script:InventoryTopLevelKeys -join ',')
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Export-OERInventory (core)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # The group read: one RBAC-relevant group and one plain group.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @(
                    [PSCustomObject]@{ displayName = 'role_sec_admin'; roleAssignable = $true;  dynamic = $false; members = @('person26@example.com'); eligibility = @() },
                    [PSCustomObject]@{ displayName = 'PlainTeam';      roleAssignable = $false; dynamic = $false; members = @('person27@example.com','person28@example.com'); eligibility = @() }
                )
                Unread = @(); Causes = @()
            }
        }
        # The other Entra ID sections, never read for -Include Groups: empty, so a test that adds one
        # never reaches the real cmdlet.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g1'; DisplayName = 'role_sec_admin'; GroupType = 'RoleEnabled'; IsAssignableToRole = $true }
            [PSCustomObject]@{ Id = 'g2'; DisplayName = 'PlainTeam';      GroupType = 'Unified';     IsAssignableToRole = $false }
        }
    }

    It 'writes a bundle folder with the canonical and per-area JSON files' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        Test-Path $Result.BundlePath | Should -BeTrue
        foreach ($F in @('inventory.json','groups.json','groupsRoster.json')) {
            Test-Path (Join-Path $Result.BundlePath $F) | Should -BeTrue
        }
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.Version | Should -Be '1.0'
    }

    It 'writes every per-area JSON file as a JSON array on disk -- one element still an array, empty still []' {
        # Pins BOTH halves of Write-OERBundleJson's switch from a pipe to -InputObject:
        #   (a) a ONE-element collection must still serialize as a JSON ARRAY ("[{...}]"), not as
        #       the bare object a pipe would have unrolled it to (PowerShell unrolls a piped
        #       single-element array into one object on the pipeline, same as an empty one) --
        #       groups.json here carries exactly the one RBAC-relevant group this Describe's fixture
        #       provides.
        #   (b) an EMPTY collection must still be WRITTEN, as the literal "[]" -- roleAssignments.json
        #       is written UNCONDITIONALLY (unlike azurePimEligibility.json) and is empty on this
        #       pure-Entra -Include, so it is the file that proves the empty-array half without an
        #       Azure section at all.
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $GroupsRaw = (Get-Content (Join-Path $Result.BundlePath 'groups.json') -Raw).TrimStart()
        $GroupsRaw | Should -Match '^\[' -Because (
            'a one-element array piped into ConvertTo-Json used to unroll to a bare object; ' +
            '-InputObject keeps the array wrapper')
        $RaPath = Join-Path $Result.BundlePath 'roleAssignments.json'
        Test-Path $RaPath | Should -BeTrue
        (Get-Content $RaPath -Raw).Trim() | Should -Be '[]'
    }

    It 'keeps only RBAC-relevant groups in inventory.json but all groups in the roster' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups).Count | Should -Be 1
        $Inv.Groups[0].displayName | Should -Be 'role_sec_admin'
        $Roster = Get-Content (Join-Path $Result.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
        @($Roster).Count | Should -Be 2
    }

    It 'passes -IncludeId to the group reader for the roster join key' {
        Export-OERInventory -OutputPath $TestDrive -Include Groups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
            $IncludeId -eq $true
        }
    }

    It 'joins the roster member count by object id, not display name' {
        # Two groups sharing the display name 'dup' with different ids and different member
        # counts. A display-name-only join would attribute the LAST write's count to both rows;
        # keying on id must attribute each row its own group's count.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $G1 = [PSCustomObject]@{
                displayName = 'dup'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @()
            }
            $G2 = [PSCustomObject]@{
                displayName = 'dup'; roleAssignable = $true; dynamic = $false
                members = @('person27@example.com', 'person28@example.com', 'person29@example.com'); eligibility = @()
            }
            if ($IncludeId) {
                $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'id-A' -Force
                $G2 | Add-Member -NotePropertyName id -NotePropertyValue 'id-B' -Force
            }
            [PSCustomObject]@{ Groups = @($G1, $G2); Unread = @(); Causes = @() }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{
                Id = 'id-A'; DisplayName = 'dup'
                GroupType = 'RoleEnabled'; IsAssignableToRole = $true
            }
            [PSCustomObject]@{
                Id = 'id-B'; DisplayName = 'dup'
                GroupType = 'RoleEnabled'; IsAssignableToRole = $true
            }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $RosterPath = Join-Path $Result.BundlePath 'groupsRoster.json'
        $Roster = Get-Content $RosterPath -Raw | ConvertFrom-Json
        @($Roster).Count | Should -Be 2
        $Roster[0].memberCount | Should -Be 1
        $Roster[1].memberCount | Should -Be 3
    }

    It 'reports a null member count for a group the detailed projection did not include' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $G1 = [PSCustomObject]@{
                displayName = 'role_sec_admin'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @()
            }
            if ($IncludeId) {
                $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'id-A' -Force
            }
            [PSCustomObject]@{ Groups = @($G1); Unread = @(); Causes = @() }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{
                Id = 'id-A'; DisplayName = 'role_sec_admin'
                GroupType = 'RoleEnabled'; IsAssignableToRole = $true
            }
            [PSCustomObject]@{
                Id = 'id-C'; DisplayName = 'Ghost'
                GroupType = 'Unified'; IsAssignableToRole = $false
            }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $RosterPath = Join-Path $Result.BundlePath 'groupsRoster.json'
        $Roster = Get-Content $RosterPath -Raw | ConvertFrom-Json
        $Ghost = $Roster | Where-Object { $_.displayName -eq 'Ghost' }
        $Ghost.memberCount | Should -BeNullOrEmpty
    }

    It 'does not leak an id into inventory.json even though -IncludeId keys the roster join' {
        # inventory.json staying id-free is a documented portability property of the export;
        # -IncludeId is threaded through the internal call purely to key the roster join, and the
        # id it stamps (on both the top-level group and each eligibility entry) must be stripped
        # again before the canonical inventory is written.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $Elig = [PSCustomObject]@{ principal = 'anna@contoso.com'; accessType = 'member' }
            if ($IncludeId) {
                $Elig | Add-Member -NotePropertyName id -NotePropertyValue 'p-1' -Force
            }
            $G1 = [PSCustomObject]@{
                displayName = 'role_sec_admin'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @($Elig)
            }
            if ($IncludeId) {
                $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'id-A' -Force
            }
            [PSCustomObject]@{ Groups = @($G1); Unread = @(); Causes = @() }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'id'
        $Inv.Groups[0].eligibility[0].PSObject.Properties.Name | Should -Not -Contain 'id'
    }

    It 'keeps every group in inventory.json with -AllGroupsDetailed' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups -AllGroupsDetailed
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups).Count | Should -Be 2
    }

    It 'emits an empty (not null) groups section when no group is RBAC-relevant' {
        # Regression: an empty else-branch assigned from an if-statement collapses to $null, which
        # would inject a single null group and fail apply-schema validation.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; members = @('person26@example.com'); eligibility = @() })
                Unread = @(); Causes = @()
            }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Raw = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Raw.Groups).Count | Should -Be 0
        $Result.Groups | Should -Be 0
    }

    It 'returns a tagged InventoryBundle object with counts' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryBundle'
        $Result.Groups | Should -Be 1
        $Result.RosterCount | Should -Be 2
    }

    It 'does NOT acquire an ARM token for a pure-Entra -Include' {
        Export-OERInventory -OutputPath $TestDrive -Include Groups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            -not $IncludeARM
        }
    }

    It 'has a registered format view for the InventoryBundle type' {
        $Formatted = Export-OERInventory -OutputPath $TestDrive -Include Groups | Format-Table | Out-String
        $Formatted | Should -Match 'BundlePath'
    }

    It 'declares SupportsShouldProcess' {
        (Get-Command Export-OERInventory).Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'writes no files under -WhatIf' {
        $Out = Join-Path $TestDrive 'bundle-whatif'
        New-Item -ItemType Directory -Path $Out -Force | Out-Null
        Export-OERInventory -OutputPath $Out -Include Groups -WhatIf | Out-Null
        @(Get-ChildItem -Path $Out -Recurse -File).Count | Should -Be 0
    }

    It 'does not remove an existing bundle folder under -WhatIf with -Force' {
        # Pin the timestamp so both calls below compute the identical $BundlePath. Without this,
        # each call mints its own fresh "oer-inventory-tenant-<live timestamp>" folder name, the
        # -WhatIf call never sees a pre-existing folder to (not) delete, Test-Path $BundlePath is
        # always $false inside the cmdlet, and the assertion below passes regardless of whether the
        # Remove-Item guard actually checks $ShouldWrite -- i.e. the test is vacuous.
        Mock -ModuleName $script:moduleName Get-Date { '20260101-000000' }
        $Out = Join-Path $TestDrive 'bundle-force-whatif'
        New-Item -ItemType Directory -Path $Out -Force | Out-Null

        # Materialize the real bundle folder first (no -WhatIf), so it already exists on disk.
        $First = Export-OERInventory -OutputPath $Out -Include Groups
        Test-Path $First.BundlePath | Should -BeTrue
        $Sentinel = Join-Path $First.BundlePath 'inventory.json'
        Test-Path $Sentinel | Should -BeTrue

        # Same -OutputPath and the same pinned timestamp -> Export-OERInventory computes the exact
        # same $BundlePath again, so this run genuinely exercises the
        # (Test-Path $BundlePath) -and $Force -and $ShouldWrite branch, not a path that never exists.
        Mock -ModuleName $script:moduleName Remove-Item { }
        Export-OERInventory -OutputPath $Out -Include Groups -Force -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-Item -Times 0
        Test-Path $First.BundlePath | Should -BeTrue
        Test-Path $Sentinel | Should -BeTrue
    }

    It 'still writes the bundle when -WhatIf is absent' {
        $Out = Join-Path $TestDrive 'bundle-real'
        New-Item -ItemType Directory -Path $Out -Force | Out-Null
        $Result = Export-OERInventory -OutputPath $Out -Include Groups
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryBundle'
        @(Get-ChildItem -Path $Out -Recurse -File).Count | Should -BeGreaterThan 0
    }

    It 'emits the InventoryBundle summary with the planned Files list under -WhatIf' {
        $Out = Join-Path $TestDrive 'bundle-whatif-plan'
        New-Item -ItemType Directory -Path $Out -Force | Out-Null
        $Result = Export-OERInventory -OutputPath $Out -Include Groups -WhatIf
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryBundle'
        $Result.Files | Should -Contain 'inventory.json'
        $Result.Files | Should -Contain 'README.md'
        $Result.BundlePath | Should -Match ([regex]::Escape('bundle-whatif-plan'))
    }
}

Describe 'Export-OERInventory (the roster is complete, the apply document is not)' {
    # THE LIVE DEFECT. An operator exported his tenant and the bundle did not show all his groups:
    # 106 in the portal, 100 in the bundle. Paging was not at fault -- the arithmetic matched to the
    # group (98 security + 1 mail-enabled security + 1 Microsoft 365 with securityEnabled true = the
    # exact 100 returned). The six missing were 5 Microsoft 365 groups with securityEnabled false
    # and 1 distribution group, and they were missing because groupsRoster.json -- the one file that
    # claims to be a full roster -- was read with 'securityEnabled eq true'. The filter was
    # invisible: nothing in the bundle, the help or the README said the roster was scoped.
    #
    # The fix splits the two scopes and states both. The ROSTER is unfiltered. inventory.json keeps
    # its security-enabled scope on purpose -- it feeds Invoke-OERStructure, and widening it widens
    # what -Prune deletes -- so these two tests are a pair: neither is safe to "fix" alone.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # The group read is security-enabled-scoped, so it returns the ONE security group only.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $G1 = [PSCustomObject]@{
                displayName = 'role_sec_admin'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @()
            }
            if ($IncludeId) { $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'g-sec' -Force }
            [PSCustomObject]@{ Groups = @($G1); Unread = @(); Causes = @() }
        }
        # The roster read sees the tenant: the security group AND a Microsoft 365 group with
        # securityEnabled false, which is exactly what the old filter dropped. The mock HONOURS the
        # distinction rather than returning everything regardless -- a mock that answers the same
        # way whatever it is asked makes every assertion below pass with the filter reinstated,
        # which is guard-shaped and inert.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            param($Group, $Filter, $All, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId)
            $SecurityGroup = [PSCustomObject]@{ Id = 'g-sec'; DisplayName = 'role_sec_admin'; GroupType = 'RoleEnabled'; IsAssignableToRole = $true }
            $M365Group = [PSCustomObject]@{ Id = 'g-m365'; DisplayName = 'MarketingTeam'; GroupType = 'Unified'; IsAssignableToRole = $false }
            if ($All) { $SecurityGroup; $M365Group } else { $SecurityGroup }
        }
    }

    It 'reads the roster with -All and sends no filter of any kind' {
        Export-OERInventory -OutputPath $TestDrive -Include Groups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter {
            $All -eq $true -and -not $Filter
        }
    }

    It 'keeps a group the securityEnabled filter would drop in groupsRoster.json' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Roster = @(Get-Content (Join-Path $Result.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
        @($Roster.displayName) | Should -Contain 'MarketingTeam' -Because (
            'the roster is the only file in the bundle that claims to list every group, and a ' +
            'Microsoft 365 group with securityEnabled false is one of the six shapes the old ' +
            'filter silently dropped'
        )
        $Roster.Count | Should -Be 2
        $Result.RosterCount | Should -Be 2
        # Its member count is UNKNOWN, not zero: the detailed projection never read that group, and
        # $null is the roster's existing "not known" value.
        $Ghost = $Roster | Where-Object { $_.displayName -eq 'MarketingTeam' }
        $null -eq $Ghost.memberCount | Should -BeTrue -Because (
            'a group outside the inventory scope has no member count to report, and 0 would state ' +
            'an emptiness nothing measured'
        )
    }

    It 'leaves inventory.json scoped to the apply-engine group set' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Not -Contain 'MarketingTeam' -Because (
            'inventory.json feeds Invoke-OERStructure, so widening it past the security-enabled ' +
            'scope widens what the apply engine reconciles and, under -Prune, deletes'
        )
        @($Inv.Groups).Count | Should -Be 1
        # And the widening is not smuggled in from this side either: the export sends the group
        # reader the 'securityEnabled eq true' filter and nothing wider.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly -ParameterFilter {
            $Filter -eq 'securityEnabled eq true'
        }
    }

    It 'marks every roster row with onPremisesSynced: true for a synchronized group and false for a cloud group (A15)' {
        # The roster is the file an operator reads to see EVERY group, so unlike the apply document
        # it states the flag on every row, true or false. The rule is Test-OERGroupOnPremisesSynced's:
        # only a boolean true is synchronized, and the null a cloud group carries is not.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            param($Group, $Filter, $All, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId)
            [PSCustomObject]@{ Id = 'g-sec'; DisplayName = 'role_sec_admin'; GroupType = 'RoleEnabled'; IsAssignableToRole = $true; OnPremisesSyncEnabled = $null }
            [PSCustomObject]@{ Id = 'g-sync'; DisplayName = 'SyncedTeam'; GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $true }
            [PSCustomObject]@{ Id = 'g-was'; DisplayName = 'FormerlySynced'; GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $false }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Result.RosterCount | Should -Be 3
        $Roster = @(Get-Content (Join-Path $Result.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
        $Roster.Count | Should -Be 3
        foreach ($Row in $Roster) {
            @($Row.PSObject.Properties.Name) | Should -Contain 'onPremisesSynced' -Because "the row of $($Row.displayName) states the flag"
            $Row.onPremisesSynced | Should -BeOfType ([bool])
        }
        ($Roster | Where-Object { $_.displayName -eq 'SyncedTeam' }).onPremisesSynced | Should -BeTrue
        ($Roster | Where-Object { $_.displayName -eq 'role_sec_admin' }).onPremisesSynced | Should -BeFalse
        ($Roster | Where-Object { $_.displayName -eq 'FormerlySynced' }).onPremisesSynced | Should -BeFalse
        # The key sits after dynamic and before memberCount, the order the roster is read in; the
        # identity and type keys (BL-130) come last, in the order the help lists them.
        [string[]]$Names = @($Roster[0].PSObject.Properties.Name)
        $Names | Should -Be @(
            'displayName', 'roleAssignable', 'dynamic', 'onPremisesSynced', 'memberCount',
            'id', 'securityEnabled', 'mailEnabled', 'groupTypes', 'visibility', 'createdDateTime'
        )
    }

    It 'tells two roster groups of one display name apart by id and gives each its own type (BL-130)' {
        # Two groups named alike: a security group (no groupTypes, mail disabled, no visibility) and a
        # Microsoft 365 group (Unified, mail enabled, Private). Before BL-130 their roster rows were
        # told apart by nothing at all. The mock hands over the converter's property names and
        # values, which is what the roster reads.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            param($Group, $Filter, $All, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId)
            [PSCustomObject]@{
                Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Marketing'; GroupType = 'Regular'
                IsAssignableToRole = $false; SecurityEnabled = $true; MailEnabled = $false; GroupTypes = @()
                Visibility = $null; CreatedDateTime = '2026-01-02T03:04:05Z'
            }
            [PSCustomObject]@{
                Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Marketing'; GroupType = 'Regular'
                IsAssignableToRole = $false; SecurityEnabled = $false; MailEnabled = $true; GroupTypes = @('Unified')
                Visibility = 'Private'; CreatedDateTime = '2026-02-03T04:05:06Z'
            }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $RosterPath = Join-Path $Result.BundlePath 'groupsRoster.json'
        $Raw = Get-Content $RosterPath -Raw
        $Roster = @($Raw | ConvertFrom-Json)
        $Roster.Count | Should -Be 2
        @($Roster.displayName) | Should -Be @('Marketing', 'Marketing')
        @($Roster.id) | Should -Be @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')

        $Sec = $Roster | Where-Object { $_.id -eq '11111111-1111-1111-1111-111111111111' }
        $Sec.securityEnabled | Should -BeOfType ([bool])
        $Sec.securityEnabled | Should -BeTrue
        $Sec.mailEnabled | Should -BeOfType ([bool])
        $Sec.mailEnabled | Should -BeFalse
        @($Sec.groupTypes).Count | Should -Be 0
        $null -eq $Sec.visibility | Should -BeTrue

        $M365 = $Roster | Where-Object { $_.id -eq '22222222-2222-2222-2222-222222222222' }
        $M365.securityEnabled | Should -BeFalse
        $M365.mailEnabled | Should -BeTrue
        @($M365.groupTypes) | Should -Be @('Unified')
        $M365.visibility | Should -BeExactly 'Private'

        # The file itself: groupTypes is a JSON array in both rows ([] and ["Unified"], never a bare
        # string or null), and createdDateTime is the converter's UTC ISO 8601 string. The raw text is
        # checked for the time because ConvertFrom-Json would turn it into a DateTime.
        ([regex]::Matches($Raw, '"groupTypes"\s*:\s*\[\s*\]')).Count | Should -Be 1
        ([regex]::Matches($Raw, '"groupTypes"\s*:\s*\[\s*"Unified"\s*\]')).Count | Should -Be 1
        $Raw | Should -Match '"createdDateTime"\s*:\s*"2026-01-02T03:04:05Z"'
        $Raw | Should -Match '"createdDateTime"\s*:\s*"2026-02-03T04:05:06Z"'
        $Raw | Should -Match '"visibility"\s*:\s*null'
        $Raw | Should -Match '"visibility"\s*:\s*"Private"'
    }

    It 'writes groupTypes as a JSON array when the converter hands over a bare string or nothing, and unknown flags as null (BL-130)' {
        # A defensive shape: the roster forces groupTypes to an array of strings whatever it is given,
        # so a value that is a bare string still writes ["Unified"], a missing one writes [], and a
        # flag that is not a boolean is null (not known), never a truthy string.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            param($Group, $Filter, $All, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId)
            [PSCustomObject]@{
                Id = 'g-1'; DisplayName = 'bare'; GroupType = 'Regular'; IsAssignableToRole = $false
                SecurityEnabled = 'true'; MailEnabled = $null; GroupTypes = 'Unified'
            }
            [PSCustomObject]@{ Id = 'g-2'; DisplayName = 'none'; GroupType = 'Regular'; IsAssignableToRole = $false }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Raw = Get-Content (Join-Path $Result.BundlePath 'groupsRoster.json') -Raw
        ([regex]::Matches($Raw, '"groupTypes"\s*:\s*\[\s*"Unified"\s*\]')).Count | Should -Be 1
        ([regex]::Matches($Raw, '"groupTypes"\s*:\s*\[\s*\]')).Count | Should -Be 1
        ([regex]::Matches($Raw, '"securityEnabled"\s*:\s*null')).Count | Should -Be 2
        ([regex]::Matches($Raw, '"mailEnabled"\s*:\s*null')).Count | Should -Be 2
    }
}

Describe 'Export-OERInventory (-IncludeSyncedGroups, A15)' {
    # A group synchronized from on-premises is never role-assignable and never managed in PIM for
    # Groups, so none of the three RBAC-relevance criteria keeps it in inventory.json. The switch
    # keeps it on request; the group reader (Get-OERInventoryGroup) writes onPremisesSynced as a
    # boolean true for such a group and never otherwise, and the filter takes nothing but that. The
    # reader is mocked here and returns all three groups whatever it is asked, so these tests prove
    # the selection the export makes on what comes back.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # The group order is rbac, synced, plain: the order a kept set must come back in.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @(
                    [PSCustomObject]@{ displayName = 'rbac';   roleAssignable = $true;  dynamic = $false; members = @('person26@example.com'); eligibility = @() },
                    [PSCustomObject]@{ displayName = 'synced'; roleAssignable = $false; dynamic = $false; onPremisesSynced = $true; members = @() },
                    [PSCustomObject]@{ displayName = 'plain';  roleAssignable = $false; dynamic = $false; members = @() }
                )
                Unread = @(); Causes = @()
            }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g1'; DisplayName = 'rbac';   GroupType = 'RoleEnabled'; IsAssignableToRole = $true }
            [PSCustomObject]@{ Id = 'g2'; DisplayName = 'synced'; GroupType = 'Regular';     IsAssignableToRole = $false; OnPremisesSyncEnabled = $true }
            [PSCustomObject]@{ Id = 'g3'; DisplayName = 'plain';  GroupType = 'Regular';     IsAssignableToRole = $false }
        }
    }

    It 'declares the switch' {
        $Param = (Get-Command Export-OERInventory).Parameters['IncludeSyncedGroups']
        $Param | Should -Not -BeNullOrEmpty
        $Param.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
    }

    It 'keeps a synchronized group out of inventory.json without the switch (today''s selection)' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Be @('rbac')
        $Result.Groups | Should -Be 1
        # The roster still lists all three, the synchronized one flagged: that file is the only place
        # such a group appears without the switch.
        $Result.RosterCount | Should -Be 3
    }

    It 'keeps the synchronized group, after the role-assignable one and with its flag, under -IncludeSyncedGroups' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups -IncludeSyncedGroups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Be @('rbac', 'synced')
        $Result.Groups | Should -Be 2
        $Synced = $Inv.Groups | Where-Object { $_.displayName -eq 'synced' }
        $Synced.onPremisesSynced | Should -BeTrue -Because 'the key is what tells the apply document a group is managed on-premises'
        $Synced.onPremisesSynced | Should -BeOfType ([bool])
        # The role-assignable group is a cloud group and carries no such key at all.
        @(($Inv.Groups | Where-Object { $_.displayName -eq 'rbac' }).PSObject.Properties.Name) | Should -Not -Contain 'onPremisesSynced'
        # The per-area file is cut from the same set.
        $PerArea = @(Get-Content (Join-Path $Result.BundlePath 'groups.json') -Raw | ConvertFrom-Json)
        @($PerArea.displayName) | Should -Be @('rbac', 'synced')
        # A cloud group that is neither role-assignable nor PIM-managed is still not kept.
        @($Inv.Groups.displayName) | Should -Not -Contain 'plain'
    }

    It 'keeps every group with -AllGroupsDetailed, as before' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups -AllGroupsDetailed
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Be @('rbac', 'synced', 'plain')
        $Result.Groups | Should -Be 3
    }

    It 'keeps each group exactly once when -AllGroupsDetailed and -IncludeSyncedGroups are combined' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups -AllGroupsDetailed -IncludeSyncedGroups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Be @('rbac', 'synced', 'plain') -Because 'the synchronized group must not be listed once for each way of being kept'
        $Result.Groups | Should -Be 3
    }

    It 'takes only a boolean true for a synchronized group, never the string True or a boolean false' {
        # A hand-built group read can carry any shape; the reader writes a boolean true or no key.
        # The string 'True' and the boolean false are not synchronized groups, so neither is kept.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @(
                    [PSCustomObject]@{ displayName = 'rbac';       roleAssignable = $true;  dynamic = $false; members = @(); eligibility = @() },
                    [PSCustomObject]@{ displayName = 'as-string';  roleAssignable = $false; dynamic = $false; onPremisesSynced = 'True'; members = @() },
                    [PSCustomObject]@{ displayName = 'as-false';   roleAssignable = $false; dynamic = $false; onPremisesSynced = $false;  members = @() },
                    [PSCustomObject]@{ displayName = 'as-bool';    roleAssignable = $false; dynamic = $false; onPremisesSynced = $true;   members = @() }
                )
                Unread = @(); Causes = @()
            }
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups -IncludeSyncedGroups
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups.displayName) | Should -Be @('rbac', 'as-bool')
        $Result.Groups | Should -Be 2
    }

    It 'asks the group reader to keep synchronized groups, with the same security-enabled filter' {
        # The switch reaches the read (a synchronized group is then read in full rather than
        # dropped after two requests), but not the filter, so it cannot widen the securityEnabled
        # scope of inventory.json. The selection above is still made here on what comes back.
        Export-OERInventory -OutputPath $TestDrive -Include Groups -IncludeSyncedGroups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly -ParameterFilter {
            $Filter -eq 'securityEnabled eq true' -and $IncludeId -eq $true -and $RelevantOnly -eq $true -and $IncludeSyncedGroups -eq $true
        }
    }
}

Describe 'Export-OERInventory (Azure walk)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # Groups are not under test here: the default -Include reads them, and finds none.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes = @('/subscriptions/s1', '/subscriptions/s2')
                Hierarchy = [PSCustomObject]@{
                    managementGroups = @()
                    subscriptions = @(
                        [PSCustomObject]@{ subscriptionId = 's1'; displayName = 'Prod'; id = '/subscriptions/s1'; state = 'Enabled' }
                        [PSCustomObject]@{ subscriptionId = 's2'; displayName = 'Test'; id = '/subscriptions/s2'; state = 'Enabled' }
                    )
                }
            }
        }
        # This Describe is about the roleAssignments/roleManagementPolicies walk; the eligibility
        # read (R4) is its own pass over the same scope list and gets its own Describe below. Mocked
        # to an empty, all-read result here so it never reaches the real Get-OEREligibleRoleAssignment
        # (which would otherwise attempt a real ARM call with no cached token) and never pollutes
        # these tests' SkippedScopes / InventoryPartial assertions with an unrelated failure.
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() }
        }
        # Entra call returns empties; per-scope Azure calls return one assignment each (s1's is shared/duplicated).
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            $ra = @(); $rmp = @()
            if ($Include -contains 'RoleAssignments') {
                if ($Scope -eq '/subscriptions/s1') {
                    $ra = @([PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Owner'; principal = 'person26@example.com' })
                } elseif ($Scope -eq '/subscriptions/s2') {
                    $ra = @(
                        [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Owner'; principal = 'person26@example.com' }, # inherited dup
                        [PSCustomObject]@{ scope = '/subscriptions/s2'; role = 'Reader'; principal = 'person27@example.com' }
                    )
                }
            }
            if ($Include -contains 'RoleManagementPolicies' -and $Scope) {
                $rmp = @([PSCustomObject]@{ scope = $Scope; role = 'Owner'; allowPermanentEligibility = $false; activationMaxHours = 8 })
            }
            $inv = [PSCustomObject]@{
                Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@()
                AccessReviews=@(); RoleAssignments=$ra; RoleManagementPolicies=$rmp
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
    }

    It 'DOES acquire an ARM token when an Azure section is requested' {
        Export-OERInventory -OutputPath $TestDrive -Include RoleAssignments | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $IncludeARM
        }
    }

    It 'acquires an ARM token for the default -Include (RoleAssignments is on by default)' {
        Export-OERInventory -OutputPath $TestDrive | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $IncludeARM
        }
    }

    It 'walks every scope and dedupes inherited role assignments' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include RoleAssignments
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        # The s1 assignment is read twice (once at s1, once inherited at s2) and both copies carry
        # identical scope/role/principal, so the composite key collapses them. The fixture carries no
        # 'id' because Export-OERInventory never reads one -- it calls Get-OERInventory without
        # -IncludeId, so only the composite-key branch is reachable in production.
        @($Inv.RoleAssignments).Count | Should -Be 2
        $Result.ScopeCount | Should -Be 2
    }

    It 'writes scopeHierarchy.json from the resolved tree' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include RoleAssignments
        Test-Path (Join-Path $Result.BundlePath 'scopeHierarchy.json') | Should -BeTrue
        $H = Get-Content (Join-Path $Result.BundlePath 'scopeHierarchy.json') -Raw | ConvertFrom-Json
        @($H.subscriptions).Count | Should -Be 2
    }

    It 'reads PIM policies with -AllRolesAtScope, once per scope, when RoleManagementPolicies is included with -AllRolePolicies' {
        Export-OERInventory -OutputPath $TestDrive -Include RoleManagementPolicies -AllRolePolicies | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly -ParameterFilter {
            ($Include -contains 'RoleManagementPolicies') -and $AllRolesAtScope -eq $true
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s1' }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s2' }
    }

    It 'reads PIM policies per scope through the selection, not through Get-OERInventory, without -AllRolePolicies (BL-107)' {
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment {}
        Mock -ModuleName $script:moduleName Get-OERInventoryRolePolicy {}
        Export-OERInventory -OutputPath $TestDrive -Include RoleManagementPolicies | Out-Null
        # Reached: each scope's policies were read once, by the selection's own reader, and each
        # scope's role assignments once, with -AtScope.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryRolePolicy -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s1' }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryRolePolicy -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s2' }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s1' -and $AtScope -eq $true }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s2' -and $AtScope -eq $true }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 0 -ParameterFilter {
            ($Include -contains 'RoleManagementPolicies') -or $AllRolesAtScope -eq $true
        }
    }

    It 'skips a failing scope and still captures the others' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            if ($Scope -eq '/subscriptions/s1') { throw 'boom (throttled)' }
            $ra = @()
            if ($Include -contains 'RoleAssignments' -and $Scope -eq '/subscriptions/s2') {
                $ra = @([PSCustomObject]@{ scope = '/subscriptions/s2'; role = 'Reader'; principal = 'person27@example.com' })
            }
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=$ra; RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include RoleAssignments -WarningVariable Warn `
            -ErrorAction SilentlyContinue
        Test-Path $Result.BundlePath | Should -BeTrue
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.RoleAssignments).Count | Should -Be 1
        $Inv.RoleAssignments[0].scope | Should -Be '/subscriptions/s2'
        ($Warn -join "`n") | Should -Match 'subscriptions/s1'
    }

    It 'still writes a bundle when scope enumeration fails' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree { throw 'cannot read management groups' }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include RoleAssignments -WarningVariable Warn `
            -ErrorAction SilentlyContinue
        Test-Path $Result.BundlePath | Should -BeTrue
        $Result.ScopeCount | Should -Be 0
        @($Result.RoleAssignments) | Should -Be 0
        Test-Path (Join-Path $Result.BundlePath 'scopeHierarchy.json') | Should -BeTrue
        ($Warn -join "`n") | Should -Match 'enumerate Azure scopes'
    }

    It 'lists the Azure walk that could not start in the README, once per file it leaves short, as code spans' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree { throw 'cannot read management groups' }
        $Sentinel = '<all Azure scopes: scope enumeration failed>'
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'readme-walk') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: the walk was attempted and failed, and the returned object says the same.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERInventoryScopeTree -Times 1 -Exactly
        $Result.SkippedScopes | Should -Contain $Sentinel
        $Result.SkippedEligibilityScopes | Should -Contain $Sentinel

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Result.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        $Expected = @(
            '- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `<all Azure scopes: scope enumeration failed>`'
            '- Azure scope, absent from `azurePimEligibility.json`: `<all Azure scopes: scope enumeration failed>`'
        )
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # Shown, not swallowed as an HTML tag: outside a code span the section holds no angle bracket.
        ($Section -replace '`[^`]*`', '') | Should -Not -Match '<'
        $Section | Should -Match 'This bundle is PARTIAL'
        Assert-ListStaysOutOfJson -BundlePath $Result.BundlePath -Forbidden $Expected
    }

    It 'lists a scope that could not be read under the role assignment files only, not under azurePimEligibility.json' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            if ($Scope -eq '/subscriptions/s1') { throw 'boom (throttled)' }
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=@(); RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'readme-scope') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: s1 was attempted, failed and was skipped; s2 was read.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/s1' }
        $Result.SkippedScopes | Should -Contain '/subscriptions/s1'
        @($Result.SkippedEligibilityScopes).Count | Should -Be 0
        $Result.ScopeCount | Should -Be 1

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Result.BundlePath
        $Expected = @('- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `/subscriptions/s1`')
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        Assert-ListStaysOutOfJson -BundlePath $Result.BundlePath -Forbidden $Expected
    }
}

Describe 'Export-OERInventory (role assignments at the root scope, BL-126)' {
    # BL-126 (R3, R4). Every read of the walk returns a role assignment at the root scope '/' as
    # inherited, and Get-OERInventory leaves it out and names it in a warning and an information
    # record. The export keeps its per-scope call, captures those warnings instead of showing them,
    # names the rows ONCE in its own warning after the walk, and lists them in the README. Every other
    # per-scope warning is shown as before. The warnings are counted on the warning STREAM (3>&1), what
    # the caller is shown: a caller's -WarningVariable also collects the captured ones, since PowerShell
    # appends a nested command's warnings to every enclosing -WarningVariable whatever that command's
    # -WarningAction (measured). The mocks below write their warnings and records through the module's
    # session state (Write-AsGetOERInventory), as the real Get-OERInventory does: a mock body runs in
    # this file's session state, where the -WarningAction the export passes to the call, and the
    # export's own Stop preference, are not seen (measured). No id below is version-4 shaped.
    BeforeAll {
        # Writes what a per-scope Get-OERInventory call writes, from inside the module, so the
        # preferences of the call it stands in for govern it exactly as they govern the real command.
        function script:Write-AsGetOERInventory {
            param([string]$Warning, [object]$Notice)
            & (Get-Module $script:moduleName) {
                param($Warning, $Notice)
                if ($Warning) { Microsoft.PowerShell.Utility\Write-Warning $Warning }
                if ($Notice) { Microsoft.PowerShell.Utility\Write-Information -MessageData $Notice -Tags 'Omnicit.EntraRBAC.RootScopeAssignment' }
            } $Warning $Notice
        }
        $script:RootHeading = '## Role assignments at the root scope (elevated access)'
        $script:RootS1 = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:RootS2 = '/subscriptions/aaaa1111-0000-0000-0000-000000000002'
        $script:RootId = '/providers/Microsoft.Authorization/roleAssignments/cccc4444-0000-0000-0000-000000000001'
        # What a real per-scope Get-OERInventory call writes for one root row.
        $script:RootRow = [PSCustomObject]@{ RoleAssignmentId = $script:RootId; Role = 'User Access Administrator'; Principal = 'person1@example.com'; PrincipalType = 'User' }
        $script:RootGetWarning = "Get-OERInventory: left out 1 role assignment(s) at the root scope '/', which grants access over every " +
            "management group and subscription in the tenant (elevated access): 'User Access Administrator' for 'person1@example.com' (User). " +
            'A document never carries a role assignment at the root scope, and Invoke-OERStructure never creates or removes one; review them as a finding.'
        $script:RootExportWarning = "Export-OERInventory: left out 1 role assignment(s) at the root scope '/', which grants access over every " +
            'management group and subscription in the tenant (elevated access), from inventory.json and roleAssignments.json: ' +
            "'User Access Administrator' for 'person1@example.com' (User). README.md names them under 'Role assignments at the root scope " +
            "(elevated access)'; review them as a finding. Invoke-OERStructure never creates or removes a role assignment at the root scope."
        # The README section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-ReadmeRootSection {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:RootHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        # One export, its result and the text of every warning that reached the caller's stream.
        function Invoke-RootExport {
            param([hashtable]$Splat)
            $All = @(Export-OERInventory @Splat -WarningAction Continue -ErrorAction SilentlyContinue 3>&1)
            [PSCustomObject]@{
                Result   = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
                Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:RootS1, $script:RootS2)
                Hierarchy = [PSCustomObject]@{
                    managementGroups = @()
                    subscriptions    = @(
                        [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod'; id = $script:RootS1; state = 'Enabled' }
                        [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Test'; id = $script:RootS2; state = 'Enabled' }
                    )
                }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
        # Each scope: one row of its own, and the root row with the warning and the record a real call
        # writes for it -- the same role assignment id at both scopes.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            $Ra = @()
            if ($Include -contains 'RoleAssignments' -and $Scope) {
                $Ra = @([PSCustomObject]@{ scope = $Scope; role = 'Reader'; principal = 'person2@example.com' })
                $Notice = [PSCustomObject]@{ Warning = $script:RootGetWarning; Assignments = @($script:RootRow) }
                $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RootScopeAssignmentNotice')
                Write-AsGetOERInventory -Warning $script:RootGetWarning -Notice $Notice
            }
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = $Ra; RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
    }

    It 'names the root row once, in its own warning and in the README, and writes it to no JSON file' {
        $Run = Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-once'); Include = 'RoleAssignments' }
        # Reach proof: both scopes were read, and each reported the root row.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
        $Bundle = $Run.Result.BundlePath
        $Inv = Get-Content (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @(
            "$($script:RootS1)|Reader|person2@example.com"
            "$($script:RootS2)|Reader|person2@example.com"
        )
        @($Inv.roleAssignments | Where-Object { $_.scope -eq '/' }).Count | Should -Be 0
        $RaFile = @(Get-Content (Join-Path $Bundle 'roleAssignments.json') -Raw | ConvertFrom-Json)
        @($RaFile | Where-Object { $_.scope -eq '/' }).Count | Should -Be 0
        foreach ($File in @(Get-ChildItem -Path $Bundle -Filter '*.json')) {
            Get-Content $File.FullName -Raw | Should -Not -Match ([regex]::Escape('person1@example.com')) -Because "$($File.Name) must not carry the root row"
        }
        # Shown once, by the export; Get-OERInventory's warning for it, written once per scope, is not shown.
        $Run.Warnings | Should -Be @($script:RootExportWarning)
        @($Run.Warnings | Where-Object { $_ -like 'Get-OERInventory: left out*' }).Count | Should -Be 0
        $Section = Get-ReadmeRootSection -BundlePath $Bundle
        $Section | Should -Match '(?m)^This export read 1 role assignment\(s\) at the root scope:\r?$'
        @($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @('- `User Access Administrator` for `person1@example.com` (User)')
    }

    It 'writes the warning under -WhatIf too, and no bundle' {
        $Run = Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-whatif'); Include = 'RoleAssignments'; WhatIf = $true }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
        $Run.Warnings | Should -Be @($script:RootExportWarning)
        Test-Path -LiteralPath $Run.Result.BundlePath | Should -BeFalse
    }

    It 'shows a different per-scope warning once per scope, as before, and the README says none was read' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            Write-AsGetOERInventory -Warning 'per-scope other'
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @([PSCustomObject]@{ scope = $Scope; role = 'Reader'; principal = 'person2@example.com' }); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        $Run = Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-other'); Include = 'RoleAssignments' }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
        $Run.Warnings | Should -Be @('per-scope other', 'per-scope other')
        $Section = Get-ReadmeRootSection -BundlePath $Run.Result.BundlePath
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. No role assignment this export read is at the root scope `/`.'))
    }

    It 'shows a warning a per-scope call wrote before it failed, then skips the scope as before' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            if ($Scope -eq $script:RootS1) {
                Write-AsGetOERInventory -Warning 'written before the failure'
                throw 'per-scope failure'
            }
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        $Run = Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-fail'); Include = 'RoleAssignments' }
        $Run.Warnings | Should -Be @('written before the failure', "Skipping scope '$($script:RootS1)': per-scope failure")
        @($Run.Result.SkippedScopes) | Should -Be @($script:RootS1)
    }

    It 'stops under -WarningAction Stop at a per-scope warning, through the scope''s skip, as before' {
        # Before BL-126 the per-scope call's own warning stopped inside the call under the export's Stop
        # preference and reached the scope's catch. Now the call's warnings are captured, and the
        # export's re-write of the warning stops instead, reaching the same catch.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
            Write-AsGetOERInventory -Warning 'per-scope other'
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        $Out = Join-Path $TestDrive 'root-stop'
        $Thrown = { Export-OERInventory -OutputPath $Out -Include RoleAssignments -WarningAction Stop } | Should -Throw -PassThru
        $Thrown.Exception.Message | Should -BeLike "*Skipping scope '$($script:RootS1)':*per-scope other*"
        # The first scope stopped the export: the second was never read, and nothing was written.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        Test-Path -LiteralPath $Out | Should -BeFalse
    }

    It 'passes -WarningAction SilentlyContinue to every per-scope call, beside the -ErrorAction Stop it always passed' {
        Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-params'); Include = 'RoleAssignments' } | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly -ParameterFilter {
            $WarningAction -eq 'SilentlyContinue' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'passes -InformationAction SilentlyContinue to every per-scope call, so the root notices are captured and never shown per scope' {
        Invoke-RootExport -Splat @{ OutputPath = (Join-Path $TestDrive 'root-info-params'); Include = 'RoleAssignments' } | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly -ParameterFilter {
            $InformationAction -eq 'SilentlyContinue'
        }
    }

    It 'reads every scope and names the root row once under a caller''s -InformationAction Stop' {
        # Without -InformationAction on the per-scope call, a caller's Stop information preference
        # reached Get-OERInventory's root notice, which stopped the call, and every scope below a root
        # assignment was skipped.
        $All = @(Export-OERInventory -OutputPath (Join-Path $TestDrive 'root-info-stop') -Include RoleAssignments -InformationAction Stop `
                -WarningAction Continue -ErrorAction SilentlyContinue 3>&1)
        $Result = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
        $Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
        @($Result.SkippedScopes) | Should -BeNullOrEmpty
        $Warnings | Should -Be @($script:RootExportWarning)
        $Section = Get-ReadmeRootSection -BundlePath $Result.BundlePath
        $Section | Should -Match '(?m)^This export read 1 role assignment\(s\) at the root scope:\r?$'
    }

}

Describe 'Export-OERInventory (role assignments at the root scope, through the real Get-OERInventory, BL-126)' {
    # Get-OERInventory runs for REAL here, so the rows reach the README through its own warning and
    # information record, not through a mock that writes them. Only its role assignment read, the
    # principal names, the scope walk, the eligibility read, the group reads, the profile read and the
    # sign-in are mocked. One subscription; its read holds the root assignment (inherited) and one of
    # its own. No id below is version-4 shaped.
    BeforeAll {
        $script:E2eSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:E2eExportWarning = "Export-OERInventory: left out 1 role assignment(s) at the root scope '/', which grants access over every " +
            'management group and subscription in the tenant (elevated access), from inventory.json and roleAssignments.json: ' +
            "'User Access Administrator' for 'person1@example.com' (User). README.md names them under 'Role assignments at the root scope " +
            "(elevated access)'; review them as a finding. Invoke-OERStructure never creates or removes a role assignment at the root scope."
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:E2eSub)
                Hierarchy = [PSCustomObject]@{
                    managementGroups = @()
                    subscriptions    = @([PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod'; id = $script:E2eSub; state = 'Enabled' })
                }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
            [PSCustomObject]@{
                Scope = '/'; RoleName = 'User Access Administrator'; RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/rd-uaa'
                PrincipalId = 'dddd4444-0000-0000-0000-000000000001'; PrincipalType = 'User'; PrincipalDisplayName = 'Root Admin'
                RoleAssignmentId = '/providers/Microsoft.Authorization/roleAssignments/cccc4444-0000-0000-0000-000000000001'
            }
            [PSCustomObject]@{
                Scope = $script:E2eSub; RoleName = 'Reader'; RoleDefinitionId = "$($script:E2eSub)/providers/Microsoft.Authorization/roleDefinitions/rd-reader"
                PrincipalId = 'dddd4444-0000-0000-0000-000000000002'; PrincipalType = 'User'; PrincipalDisplayName = 'User Two'
                RoleAssignmentId = "$($script:E2eSub)/providers/Microsoft.Authorization/roleAssignments/cccc4444-0000-0000-0000-000000000002"
            }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
            & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'dddd4444-0000-0000-0000-000000000001' = 'person1@example.com'; 'dddd4444-0000-0000-0000-000000000002' = 'person2@example.com' }
        }
    }

    It 'writes only the subscription row to inventory.json and roleAssignments.json, names the root row in the README, and warns once' {
        $All = @(Export-OERInventory -OutputPath (Join-Path $TestDrive 'root-e2e') -Include RoleAssignments -WarningAction Continue -ErrorAction SilentlyContinue 3>&1)
        $Result = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
        $Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
        # Reach proof: the real Get-OERInventory read the scope once.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -eq $script:E2eSub -and $ResolveNames }
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @("$($script:E2eSub)|Reader|person2@example.com")
        $RaFile = @(Get-Content (Join-Path $Result.BundlePath 'roleAssignments.json') -Raw | ConvertFrom-Json)
        @($RaFile | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @("$($script:E2eSub)|Reader|person2@example.com")
        $Readme = Get-Content (Join-Path $Result.BundlePath 'README.md') -Raw
        $Readme | Should -Match '(?m)^This export read 1 role assignment\(s\) at the root scope:\r?$'
        $Readme | Should -Match ([regex]::Escape('- `User Access Administrator` for `person1@example.com` (User)'))
        $Warnings | Should -Be @($script:E2eExportWarning)
    }
}

Describe 'Export-OERInventory (Azure role policy selection, BL-107)' {
    # Without -AllRolePolicies the export keeps a role's policy at a scope only when the role has an
    # active assignment or an eligibility exactly at that scope, or when the policy has been changed.
    # The real Get-OERInventoryRolePolicy, Test-OERRolePolicyModified and Select-OERInventoryRolePolicy
    # run here; the policy list, the role assignment list and the eligibility read are mocked. One
    # subscription, five roles:
    #   Assigned  -- an active assignment at the subscription                            -> kept
    #   Eligible  -- an eligibility at the subscription                                   -> kept
    #   Changed   -- nobody uses it, and its policy carries a change                      -> kept
    #   Untouched -- nobody uses it, and its policy is untouched                          -> omitted
    #   Elsewhere -- an assignment at the parent management group and an eligibility at a
    #                resource group below, none at the subscription                      -> omitted
    # No id below is version-4 shaped.
    BeforeAll {
        $script:BlSub = '/subscriptions/11111111-1111-1111-1111-111111111111'
        # A second subscription, for the tests that walk two scopes.
        $script:BlSub2 = '/subscriptions/22222222-2222-2222-2222-222222222222'
        $script:BlRg = "$script:BlSub/resourceGroups/rg-app"
        $script:BlMg = '/providers/Microsoft.Management/managementGroups/mg-parent'
        $script:BlTenantRoleDef = '/providers/Microsoft.Authorization/roleDefinitions'
        $script:BlRoles = [ordered]@{
            Assigned  = 'aaaaaaaa-0000-0000-0000-00000000000a'
            Eligible  = 'aaaaaaaa-0000-0000-0000-00000000000e'
            Changed   = 'aaaaaaaa-0000-0000-0000-00000000000c'
            Untouched = 'aaaaaaaa-0000-0000-0000-00000000000f'
            Elsewhere = 'aaaaaaaa-0000-0000-0000-00000000000d'
        }
        $script:BlUnjudged = "roleManagementPolicies/role selection at $script:BlSub"
        $script:BlAzureBullet = '- Azure role management policies kept without being judged: `' + $script:BlUnjudged + '`'

        # The policy list of a scope in the lister's shape: every role's policy untouched (the shape
        # measured live), except Changed's, which carries a date and a name.
        $script:BlPolicyInfos = {
            param([string]$Scope)
            foreach ($Name in $script:BlRoles.Keys) {
                $Guid = $script:BlRoles[$Name]
                $PolicyId = "$Scope/providers/Microsoft.Authorization/roleManagementPolicies/$Guid"
                $Metadata = if ($Name -eq 'Changed') {
                    [PSCustomObject]@{ id = $PolicyId; lastModifiedDateTime = '2026-08-01T10:00:00Z'; lastModifiedBy = [PSCustomObject]@{ displayName = 'Person One' } }
                } else {
                    [PSCustomObject]@{ id = $PolicyId; lastModifiedBy = [PSCustomObject]@{} }
                }
                [PSCustomObject]@{
                    PolicyId         = $PolicyId
                    RoleDefinitionId = "$Scope/providers/Microsoft.Authorization/roleDefinitions/$Guid"
                    RoleName         = $Name
                    Scope            = $Scope
                    EffectiveRules   = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' })
                    PolicyMetadata   = $Metadata
                }
            }
        }
        # The roles of a written roleManagementPolicies.json, in order, joined with commas.
        function Get-BlPolicyRole {
            param([string]$BundlePath)
            @(@(Get-Content (Join-Path $BundlePath 'roleManagementPolicies.json') -Raw | ConvertFrom-Json) | ForEach-Object { $_.role }) -join ','
        }
        # A role assignment read that fails the way the real cmdlet does: a non-terminating record,
        # which only the caller's -ErrorAction Stop turns into a terminating one.
        $script:BlFailingAssignmentRead = {
            [CmdletBinding()]
            param($Scope, [switch]$AtScope)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Forbidden (403): the client has no authorization to list role assignments'),
                    'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, $Scope))
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # Groups are not under test here: a run that includes them finds none.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:BlSub)
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        # The per-scope call as it was: the scope's role assignments, and with -AllRolesAtScope the
        # policy of every role there. The Entra ID call (no -Scope) reads nothing.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $AllRolesAtScope, $ErrorAction)
            $Ra = @()
            $Rmp = @()
            if ($Scope -and $Include -contains 'RoleAssignments') {
                $Ra = @([PSCustomObject]@{ scope = $Scope; role = 'Assigned'; principal = 'principal-1' })
            }
            if ($Scope -and $Include -contains 'RoleManagementPolicies' -and $AllRolesAtScope) {
                $Rmp = @(foreach ($Info in (& $script:BlPolicyInfos -Scope $Scope)) {
                        [PSCustomObject]@{ scope = $Scope; role = $Info.RoleName; allowPermanentEligibility = $null; activationMaxHours = 8 }
                    })
            }
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = $Ra; RoleManagementPolicies = $Rmp
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope {
            param($Scope)
            & $script:BlPolicyInfos -Scope $Scope
        }
        # -AtScope lists the assignments at or above the scope: Assigned at the subscription, and
        # Elsewhere at the parent management group. The role definition ids are tenant-scoped, the
        # policy list's are subscription-scoped: the role is matched on its guid.
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
            param($Scope, [switch]$AtScope, $ErrorAction)
            [PSCustomObject]@{ Scope = $Scope; RoleDefinitionId = "$script:BlTenantRoleDef/$($script:BlRoles.Assigned)"; PrincipalId = 'principal-1' }
            [PSCustomObject]@{ Scope = $script:BlMg; RoleDefinitionId = "$script:BlTenantRoleDef/$($script:BlRoles.Elsewhere)"; PrincipalId = 'principal-2' }
        }
        # The unfiltered subscription read lists the eligibilities at and below it: Eligible at the
        # subscription, and Elsewhere at a resource group below it.
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{
                Eligibilities = @()
                SkippedScopes = @()
                RoleScopes    = @(
                    [PSCustomObject]@{ Scope = $script:BlSub; RoleDefinitionId = "$script:BlSub/providers/Microsoft.Authorization/roleDefinitions/$($script:BlRoles.Eligible)" }
                    [PSCustomObject]@{ Scope = $script:BlRg; RoleDefinitionId = "$script:BlSub/providers/Microsoft.Authorization/roleDefinitions/$($script:BlRoles.Elsewhere)" }
                )
            }
        }
    }

    It 'keeps exactly the policies of the role assigned and the role eligible at the scope, and the changed one' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-default') -Include RoleManagementPolicies `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed'
        $Bundle.RoleManagementPolicies | Should -Be 3
        $Inventory = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        (@($Inventory.roleManagementPolicies | ForEach-Object { $_.role }) -join ',') | Should -BeExactly 'Assigned,Eligible,Changed'
        @($Inventory.roleManagementPolicies)[0].scope | Should -BeExactly $script:BlSub
        # No per-scope Get-OERInventory call was made, and nothing null was merged in its place.
        @($Inventory.roleAssignments).Count | Should -Be 0
        $Bundle.RoleAssignments | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 0

        # One paged policy list and one role assignment list for the scope, nothing more.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 1 -Exactly -ParameterFilter { $Scope -eq $script:BlSub }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $Scope -eq $script:BlSub -and $AtScope -eq $true -and $ErrorAction -eq 'Stop'
        }

        # A complete selection: nothing unread, no warning, no partial error.
        $Bundle.ScopeCount | Should -Be 1
        @($Bundle.SkippedScopes).Count | Should -Be 0
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($Warn).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 0
    }

    It 'with -AllRolePolicies writes every policy through Get-OERInventory -AllRolesAtScope, exactly as before, and selects nothing' {
        Mock -ModuleName $script:moduleName Get-OERInventoryRolePolicy { throw 'the selection reader must not run under -AllRolePolicies' }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-all') -Include RoleManagementPolicies -AllRolePolicies `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed,Untouched,Elsewhere'
        $Bundle.RoleManagementPolicies | Should -Be 5
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $Scope -eq $script:BlSub -and (@($Include) -join ',') -eq 'RoleManagementPolicies' -and $AllRolesAtScope -eq $true -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryRolePolicy -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 0
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($Warn).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 0
    }

    It 'reads the role assignments per scope through Get-OERInventory without -AllRolesAtScope when it selects' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-ra') -Include RoleAssignments, RoleManagementPolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $Scope -eq $script:BlSub -and (@($Include) -join ',') -eq 'RoleAssignments' -and -not $AllRolesAtScope -and $ErrorAction -eq 'Stop'
        }
        $Bundle.RoleAssignments | Should -Be 1
        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed'
    }

    It 'reads the role assignments and every policy per scope in one Get-OERInventory call with -AllRolePolicies, as before' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-ra-all') -Include RoleAssignments, RoleManagementPolicies -AllRolePolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $Scope -eq $script:BlSub -and (@($Include) -join ',') -eq 'RoleAssignments,RoleManagementPolicies' -and $AllRolesAtScope -eq $true
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0
        $Bundle.RoleAssignments | Should -Be 1
        $Bundle.RoleManagementPolicies | Should -Be 5
    }

    It 'with the default -Include calls nothing new and reads each scope with the Get-OERInventory call it always made' {
        Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-none') -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $Scope -eq $script:BlSub -and (@($Include) -join ',') -eq 'RoleAssignments' -and -not $AllRolesAtScope -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 0
    }

    It 'keeps every unchanged unused policy at a scope whose role assignments could not be read, warns once, reads the scope, and names it' {
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment $script:BlFailingAssignmentRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-ra-fail') -Include RoleManagementPolicies `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reached: the read was attempted with -ErrorAction Stop and failed.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
        # Every policy at the scope is kept: Eligible and Changed on their own merits, the other three
        # because whether their role is assigned there could not be read.
        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed,Untouched,Elsewhere'
        $Bundle.RoleManagementPolicies | Should -Be 5

        # The scope was read, not skipped.
        @($Bundle.SkippedScopes).Count | Should -Be 0
        $Bundle.ScopeCount | Should -Be 1
        @($Warn | Where-Object { $_.Message -like 'Skipping scope*' }).Count | Should -Be 0
        # One warning, naming the scope and the cause, and saying which policies it keeps unjudged:
        # those not kept by a use or a change, not every policy at the scope.
        @($Warn).Count | Should -Be 1
        $Warn[0].Message | Should -BeLike "*'$script:BlSub'*"
        $Warn[0].Message | Should -BeLike '*Forbidden (403): the client has no authorization to list role assignments*'
        $Warn[0].Message | Should -BeLike "Could not read the role assignments at scope '$script:BlSub', so a role management policy there not kept by a use or a change is kept without being judged: *"

        # Named, as the one IncompleteReads entry, and by one InventoryPartial that names it in a
        # clause of its own -- not as an Entra ID read.
        @($Bundle.IncompleteReads) | Should -Be @($script:BlUnjudged)
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -BeLike "*$script:BlUnjudged*"
        $Partial[0].Exception.Message | Should -BeLike '*at 1 Azure scope(s) every role management policy that could not be judged was kept, none of them left out*'
        $Partial[0].Exception.Message | Should -BeLike '*where a scope''s role assignment or eligibility read failed, that is every policy of a role neither used nor changed there*'
        $Partial[0].Exception.Message | Should -BeLike '*roleManagementPolicies.json may hold policies of roles that are neither used nor changed*'
        $Partial[0].Exception.Message | Should -Not -BeLike '*partial Entra ID read entry*'

        # And in the bundle README, under the Azure label.
        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly $script:BlAzureBullet
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden @($script:BlAzureBullet)
    }

    It 'marks unread only the scope whose role assignment read failed, and judges the next scope on its own read' {
        # Two scopes, the failing one first. The unread mark belongs to one scope: the second
        # scope's role assignments were read, so its policies are judged and its scope is not named.
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:BlSub, $script:BlSub2)
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment $script:BlFailingAssignmentRead -ParameterFilter { $Scope -eq $script:BlSub }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-two-scopes') -Include RoleManagementPolicies `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reached: both scopes were read, and the first one's role assignment read failed.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -eq $script:BlSub2 }
        $Bundle.ScopeCount | Should -Be 2
        @($Bundle.SkippedScopes).Count | Should -Be 0
        @($Warn).Count | Should -Be 1
        $Warn[0].Message | Should -BeLike "*'$script:BlSub'*"

        # The first scope keeps every policy, three of them unjudged; the second keeps only the
        # role assigned there and the changed one, and omits the untouched one and the one used
        # elsewhere.
        $Written = @(Get-Content (Join-Path $Bundle.BundlePath 'roleManagementPolicies.json') -Raw | ConvertFrom-Json)
        (@($Written | Where-Object { $_.scope -eq $script:BlSub } | ForEach-Object { $_.role }) -join ',') |
            Should -BeExactly 'Assigned,Eligible,Changed,Untouched,Elsewhere'
        (@($Written | Where-Object { $_.scope -eq $script:BlSub2 } | ForEach-Object { $_.role }) -join ',') |
            Should -BeExactly 'Assigned,Changed'
        $Bundle.RoleManagementPolicies | Should -Be 7

        # Only the first scope is named, in IncompleteReads and in the one InventoryPartial.
        @($Bundle.IncompleteReads) | Should -Be @($script:BlUnjudged)
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -BeLike "*$script:BlUnjudged*"
        $Partial[0].Exception.Message | Should -BeLike '*at 1 Azure scope(s) every role management policy that could not be judged was kept*'
        $Partial[0].Exception.Message | Should -Not -BeLike "*role selection at $script:BlSub2*"
    }

    It 'writes a kept policy once when the walk lists its scope twice, as the -AllRolePolicies path does' {
        # The scope tree does not deduplicate the scopes it lists. Should one scope come twice, its
        # policies are read twice and every candidate comes twice; the merge keeps one of each, with
        # the same scope|role rule as the -AllRolePolicies merge.
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:BlSub, $script:BlSub)
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-twice') -Include RoleManagementPolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reached: the policy list was read once per listed scope, so every candidate came twice.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 2 -Exactly
        $Bundle.ScopeCount | Should -Be 2
        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed'
        $Bundle.RoleManagementPolicies | Should -Be 3

        $All = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-twice-all') -Include RoleManagementPolicies -AllRolePolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Get-BlPolicyRole -BundlePath $All.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed,Untouched,Elsewhere'
    }

    It 'appends the unjudged scope after the Entra ID entries, and keeps the Entra ID clause over the Entra ID entries only' {
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment $script:BlFailingAssignmentRead
        Mock -ModuleName $script:moduleName Get-OERGroup { throw 'the group roster could not be read (503)' }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-order') -Include Groups, RoleManagementPolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        (@($Bundle.IncompleteReads) -join '|') | Should -BeExactly "groupsRoster|$script:BlUnjudged"
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -BeLike '*1 partial Entra ID read entry(ies) name collections*: groupsRoster. A members*'
        $Partial[0].Exception.Message | Should -BeLike "*$script:BlUnjudged*"
        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly (@('- Entra ID: `groupsRoster`', $script:BlAzureBullet) -join "`n")
    }

    It 'keeps every unchanged policy of a role not assigned at a scope whose eligibility could not be read, and names it' {
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @($script:BlSub); RoleScopes = @() }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-elig-fail') -Include RoleManagementPolicies `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Assigned on its assignment, Changed on its change, the other three unjudged.
        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly 'Assigned,Eligible,Changed,Untouched,Elsewhere'
        @($Bundle.SkippedEligibilityScopes) | Should -Be @($script:BlSub)
        @($Bundle.SkippedScopes).Count | Should -Be 0
        $Bundle.ScopeCount | Should -Be 1
        @($Bundle.IncompleteReads) | Should -Be @($script:BlUnjudged)
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -BeLike "*$script:BlUnjudged*"
        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        (Get-SectionBullets -Section $Section) | Should -Contain $script:BlAzureBullet
    }

    It 'skips a scope whose policy list could not be read exactly as before, and names no unjudged scope for it' {
        # The role assignment read and the eligibility read fail for the scope as well, so the scope
        # would be named if the skip did not stop it.
        Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope { throw 'Service unavailable (503)' }
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment $script:BlFailingAssignmentRead
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @($script:BlSub); RoleScopes = @() }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sel-list-fail') -Include RoleManagementPolicies `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reached: both reads were attempted.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicyForScope -Times 1 -Exactly
        @($Bundle.SkippedScopes) | Should -Be @($script:BlSub)
        $Bundle.ScopeCount | Should -Be 0
        @($Warn | Where-Object { $_.Message -eq "Skipping scope '$script:BlSub': Service unavailable (503)" }).Count | Should -Be 1
        Get-BlPolicyRole -BundlePath $Bundle.BundlePath | Should -BeExactly ''
        @($Bundle.IncompleteReads).Count | Should -Be 0
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Not -BeLike '*roleManagementPolicies/*'
        # No role selection clause either, not even one counting zero scopes.
        $Partial[0].Exception.Message | Should -Not -BeLike '*could not be judged*'
    }

    It 'adds -AllRolePolicies as a switch directly after -AllDirectoryRolePolicies, and every positional parameter keeps its position' {
        $Command = Get-Command Export-OERInventory
        $Names = @($Command.Parameters.Keys)
        $Names.IndexOf('AllRolePolicies') | Should -Be ($Names.IndexOf('AllDirectoryRolePolicies') + 1)
        $Command.Parameters['AllRolePolicies'].ParameterType | Should -Be ([switch])
        @($Command.ParameterSets).Count | Should -Be 1
        $Positions = @($Command.ParameterSets[0].Parameters | Where-Object { $_.Position -ge 0 } | Sort-Object Position |
                ForEach-Object { '{0}:{1}' -f $_.Position, $_.Name })
        ($Positions -join ',') | Should -BeExactly '0:OutputPath,1:Include,2:ManagementGroup,3:Scope,4:TenantId,5:GroupFilter'
        @($Command.ParameterSets[0].Parameters | Where-Object { $_.Name -eq 'AllRolePolicies' })[0].Position | Should -BeLessThan 0
    }
}

Describe 'Export-OERInventory (Azure PIM eligibility)' {
    # R4: one bounded Get-OERInventoryAzureEligibility read of the walked scope list, written into
    # azurePimEligibility.json only when an Azure section is requested, folding its own
    # SkippedEligibilityScopes into the existing InventoryPartial error.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # Groups are not under test here: a run that includes them finds none.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @('/subscriptions/s1', '/subscriptions/s2')
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{
                Eligibilities = @(
                    [PSCustomObject]@{
                        scope = '/subscriptions/s1'; role = 'Owner'; principal = 'person26@example.com'
                        principalType = 'User'; memberType = 'Direct'; status = 'Provisioned'
                        startDateTime = $null; endDateTime = $null
                    }
                )
                SkippedScopes = @()
            }
        }
    }

    It 'writes azurePimEligibility.json only when an Azure section is included' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-write') -Include RoleAssignments
        Test-Path (Join-Path $Result.BundlePath 'azurePimEligibility.json') | Should -BeTrue
        $Result.Files | Should -Contain 'azurePimEligibility.json'
        $Data = Get-Content (Join-Path $Result.BundlePath 'azurePimEligibility.json') -Raw | ConvertFrom-Json
        @($Data).Count | Should -Be 1
        $Data[0].scope | Should -Be '/subscriptions/s1'
    }

    It 'does not write azurePimEligibility.json, and never calls the helper, for a pure-Entra -Include' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-entra-only') -Include Groups
        Test-Path (Join-Path $Result.BundlePath 'azurePimEligibility.json') | Should -BeFalse
        $Result.Files | Should -Not -Contain 'azurePimEligibility.json'
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryAzureEligibility -Times 0
    }

    It 'reports the AzurePimEligibility count on the bundle summary' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-count') -Include RoleAssignments
        $Result.AzurePimEligibility | Should -Be 1
    }

    It 'reports zero AzurePimEligibility for a pure-Entra -Include' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-zero') -Include Groups
        $Result.AzurePimEligibility | Should -Be 0
        @($Result.SkippedEligibilityScopes).Count | Should -Be 0
    }

    It 'calls the eligibility helper once with the walked scopes, after the role-assignment walk' {
        Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-call') -Include RoleAssignments | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryAzureEligibility -Times 1 -Exactly -ParameterFilter {
            @($Scope).Count -eq 2 -and $Scope -contains '/subscriptions/s1' -and $Scope -contains '/subscriptions/s2'
        }
    }

    It 'raises InventoryPartial naming azurePimEligibility.json when an eligibility scope was skipped' {
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @('/subscriptions/s2') }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig1') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Bundle.SkippedEligibilityScopes | Should -Contain '/subscriptions/s2'
        $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1 -Because 'the eligibility gap folds into the SAME trailing error, not a second one'
        $Partial[0].Exception.Message | Should -Match 'azurePimEligibility\.json'
        $Partial[0].Exception.Message | Should -Match '/subscriptions/s2'
    }

    It 'lists a scope whose eligibility could not be read in the README under azurePimEligibility.json only' {
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @('/subscriptions/s2') }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'readme-elig') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: the eligibility read ran, s2 is the one it skipped, and the role assignment
        # walk read both scopes, so the role assignment files are not the short ones.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryAzureEligibility -Times 1 -Exactly
        $Bundle.SkippedEligibilityScopes | Should -Contain '/subscriptions/s2'
        @($Bundle.SkippedScopes).Count | Should -Be 0
        $Bundle.ScopeCount | Should -Be 2

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        $Expected = @('- Azure scope, absent from `azurePimEligibility.json`: `/subscriptions/s2`')
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden $Expected
    }

    It 'does not raise InventoryPartial when the eligibility read of every scope succeeded' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-ok') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Bundle.SkippedEligibilityScopes).Count | Should -Be 0
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 0
    }

    # Measured live 2026-09-30: app-only, the management-group listing answers AuthorizationFailed, and
    # the walk read that as "no management groups" -- an incomplete bundle reported as complete.
    It 'reports a level the tree could not LIST in SkippedScopes and SkippedEligibilityScopes, and raises InventoryPartial' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes        = @('/subscriptions/s1')
                Hierarchy     = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                SkippedScopes = @('<management groups: the listing failed>')
            }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig-mglist') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Bundle.SkippedScopes | Should -Contain '<management groups: the listing failed>'
        $Bundle.SkippedEligibilityScopes | Should -Contain '<management groups: the listing failed>'
        # The subscription that WAS listed is still walked and read.
        $Bundle.ScopeCount | Should -Be 1
        $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'management groups: the listing failed'
        # The subscription WAS read: the unlisted level is named as a level, never counted as a scope
        # that could not be read.
        $Partial[0].Exception.Message | Should -Match ([regex]::Escape('1 level(s) of the Azure scope tree could not be listed, so none of their scopes was walked'))
        $Partial[0].Exception.Message | Should -Not -Match 'of 1 Azure scopes could not be read'
    }
    It 'sets SkippedEligibilityScopes to the enumeration-failure sentinel and raises InventoryPartial when the scope walk fails' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree { throw 'cannot read management groups' }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'elig2') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Bundle.SkippedEligibilityScopes).Count | Should -Be 1
        $Bundle.SkippedEligibilityScopes | Should -Contain '<all Azure scopes: scope enumeration failed>'
        $Bundle.AzurePimEligibility | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryAzureEligibility -Times 0 -Because (
            'there is no scope tree to walk, so the helper must never be called at all')
        $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'azurePimEligibility\.json'
        # The eligibility clause gets its own WALK-failed wording here, distinct from the "N Azure
        # scope(s) could not be read for azurePimEligibility.json" wording a partial (some-scopes-
        # failed) eligibility read gets -- same two-arm split the roleAssignments/roleManagementPolicies
        # clause already makes, and for the same reason: no tree at all reads differently from N of M
        # scopes failing.
        $Partial[0].Exception.Message | Should -Match 'the Azure scope walk could not be started, so no scope was read for azurePimEligibility\.json'
        Test-Path (Join-Path $Bundle.BundlePath 'azurePimEligibility.json') | Should -BeTrue
        $EmptyElig = @(Get-Content (Join-Path $Bundle.BundlePath 'azurePimEligibility.json') -Raw | ConvertFrom-Json)
        @($EmptyElig).Count | Should -Be 0
    }
}

Describe 'Export-OERInventory (partial coverage is reported, not swallowed)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # A test about a group read replaces this; the rest read no group.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # Default to an empty, all-read eligibility result so the many RoleAssignments-including
        # tests below (none of which are about azurePimEligibility.json) never reach the real
        # Get-OEREligibleRoleAssignment and never pick up a spurious SkippedEligibilityScopes entry.
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() }
        }
    }

    It 'raises InventoryPartial and reports the skipped scopes when a scope cannot be read' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                Scopes    = @('/subscriptions/aaa', '/subscriptions/bbb')
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory -ParameterFilter { $Scope -eq '/subscriptions/bbb' } -MockWith {
            throw 'Forbidden'
        }
        Mock -ModuleName $script:moduleName Get-OERInventory -ParameterFilter { $Scope -ne '/subscriptions/bbb' } -MockWith {
            [PSCustomObject]@{ RoleAssignments = @(); RoleManagementPolicies = @() }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count |
            Should -Be 1
        $Bundle.SkippedScopes | Should -Contain '/subscriptions/bbb'
        $Bundle.ScopeCount | Should -Be 1
        $Bundle.ScopesEnumerated | Should -Be 2
    }

    It 'emits the summary object BEFORE the partial error' {
        # ORDER, not merely presence. The merged stream (2>&1) is the only place the real emission
        # order is observable: -ErrorVariable collects records out of band, so a presence-only
        # assertion passes with the error emitted first. -ErrorAction is pinned to Continue on the
        # call: SilentlyContinue would suppress the record before 2>&1 could capture it, and leaving
        # it unset makes the module read the GLOBAL $ErrorActionPreference, so under a global Stop
        # (GitHub's pwsh shell, an operator profile) the record terminates the statement instead of
        # reaching 2>&1. A test-local $ErrorActionPreference cannot pin it: module code never sees
        # the caller's local scope (docs/development/rationale.md#bearer-scrub-tests).
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                Scopes    = @('/subscriptions/aaa', '/subscriptions/bbb')
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory -ParameterFilter { $Scope -eq '/subscriptions/bbb' } -MockWith {
            throw 'Forbidden'
        }
        Mock -ModuleName $script:moduleName Get-OERInventory -ParameterFilter { $Scope -ne '/subscriptions/bbb' } -MockWith {
            [PSCustomObject]@{ RoleAssignments = @(); RoleManagementPolicies = @() }
        }

        $Stream = @(Export-OERInventory -OutputPath (Join-Path $TestDrive 'b2') -Include RoleAssignments `
                -WarningAction SilentlyContinue -ErrorAction Continue 2>&1)

        $BundleIndex = -1
        $ErrorIndex = -1
        for ($I = 0; $I -lt $Stream.Count; $I++) {
            $Item = $Stream[$I]
            if ($BundleIndex -lt 0 -and $Item -isnot [System.Management.Automation.ErrorRecord] -and
                $Item.PSObject.TypeNames[0] -eq 'Omnicit.EntraRBAC.InventoryBundle') {
                $BundleIndex = $I
            }
            if ($ErrorIndex -lt 0 -and $Item -is [System.Management.Automation.ErrorRecord] -and
                $Item.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory') {
                $ErrorIndex = $I
            }
        }

        $BundleIndex | Should -BeGreaterThan -1
        $ErrorIndex | Should -BeGreaterThan -1
        $BundleIndex | Should -BeLessThan $ErrorIndex
        Test-Path $Stream[$BundleIndex].BundlePath | Should -Be $true
    }

    It 'catches a NON-terminating Get-OERInventory failure (needs -ErrorAction Stop)' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                Scopes    = @('/subscriptions/aaa')
            }
        }
        # Pester does not propagate the caller's -ErrorAction into a mock body the way the real
        # cmdlet's own $ErrorActionPreference would, so the mock honours it explicitly. That makes
        # this a behavioural test: with -ErrorAction Stop on the call the Write-Error terminates and
        # reaches the catch; without it $ErrorAction is unbound, the failure stays non-terminating,
        # and the scope silently contributes nothing -- exactly the defect.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $Scope, $AllRolesAtScope, $ErrorAction)
            $Ea = if ($ErrorAction) { $ErrorAction } else { 'Continue' }
            Write-Error 'non-terminating failure' -ErrorAction $Ea
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'c') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Bundle.SkippedScopes | Should -Contain '/subscriptions/aaa'
        $Bundle.ScopeCount | Should -Be 0
        $Bundle.ScopesEnumerated | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -ParameterFilter {
            $ErrorAction -eq 'Stop'
        }
    }

    It 'reports the whole Azure walk as skipped when scope enumeration itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree { throw 'cannot read management groups' }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            [PSCustomObject]@{ RoleAssignments = @(); RoleManagementPolicies = @() }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1
        @($Bundle.SkippedScopes).Count | Should -Be 1
        $Bundle.ScopeCount | Should -Be 0
        $Bundle.ScopesEnumerated | Should -Be 0
        # CONTENT, not just counts. A failed scope WALK is the loudest of the two Azure failures and
        # is exactly when the operator needs to be told which files are short and what was skipped;
        # those clauses must not be reachable only from the enumerated-scopes arm.
        $Partial[0].Exception.Message | Should -Match 'the Azure scope walk could not be started'
        $Partial[0].Exception.Message |
            Should -Match 'roleAssignments\.json and roleManagementPolicies\.json' -Because 'the operator must learn WHICH files are incomplete, in either arm'
        $Partial[0].Exception.Message |
            Should -Match 'Skipped: ' -Because 'the skipped entry must be named in the zero-scope arm too'
    }

    It 'writes no InventoryPartial error when every scope was read' {
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                Scopes    = @('/subscriptions/aaa', '/subscriptions/bbb')
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            [PSCustomObject]@{ RoleAssignments = @(); RoleManagementPolicies = @() }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'f') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count |
            Should -Be 0
        @($Bundle.SkippedScopes).Count | Should -Be 0
        $Bundle.ScopeCount | Should -Be 2
        $Bundle.ScopesEnumerated | Should -Be 2
    }

    It 'warns when the apply-schema self-check throws' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=@(); RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { throw 'schema blew up' }
        Export-OERInventory -OutputPath (Join-Path $TestDrive 'd') -Include Groups `
            -WarningVariable Warn -WarningAction SilentlyContinue | Out-Null
        @($Warn | Where-Object { $_.Message -match 'self-check' }).Count | Should -Be 1
    }

    It 'does not leak a profile error out of the naming auto-seed' {
        # A corrupt profile on disk now makes Get-OERConfiguration report TenantProfileMalformed.
        # Without -ErrorAction Stop on the auto-seed call that NON-terminating record bypasses the
        # catch, leaks out of Export-OERInventory and sets $? false on an otherwise complete bundle.
        # InventoryPartial is meant to be the only coverage signal this cmdlet raises.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=@(); RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
        # The param() block is required: Pester does not surface the caller's -ErrorAction to a mock
        # body without one, so the mock could not honour it and the test would prove nothing.
        Mock -ModuleName $script:moduleName Get-OERConfiguration {
            param($TenantAlias, $BasePath, $ErrorAction)
            $Ea = if ($ErrorAction) { $ErrorAction } else { 'Continue' }
            Write-Error -Message "Tenant Profile 'broken' could not be parsed and was skipped." `
                -ErrorId 'TenantProfileMalformed' -Category InvalidData -ErrorAction $Ea
        }

        $Stream = @(Export-OERInventory -OutputPath (Join-Path $TestDrive 'h') -Include Groups `
                -WarningAction SilentlyContinue 2>&1)

        @($Stream | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord] -and
                $_.FullyQualifiedErrorId -match 'TenantProfileMalformed'
            }).Count | Should -Be 0
        $Bundles = @($Stream | Where-Object {
                $_ -isnot [System.Management.Automation.ErrorRecord] -and
                $_.PSObject.TypeNames[0] -eq 'Omnicit.EntraRBAC.InventoryBundle'
            })
        $Bundles.Count | Should -Be 1
        Test-Path $Bundles[0].BundlePath | Should -Be $true
        Should -Invoke -ModuleName $script:moduleName Get-OERConfiguration -Times 1 -ParameterFilter {
            $ErrorAction -eq 'Stop'
        }
    }

    It 'writes a verbose line when the naming auto-seed fails' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=@(); RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
        Mock -ModuleName $script:moduleName Get-OERConfiguration { throw 'profile directory unreadable' }
        $Verbose = @(Export-OERInventory -OutputPath (Join-Path $TestDrive 'g') -Include Groups -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
        @($Verbose | Where-Object { $_.Message -match 'auto-seed' }).Count | Should -Be 1
    }

    It 'reports an unread collection on the bundle summary and raises InventoryPartial' {
        # The group reader reports a collection it could not read in its Unread list, by the
        # section/displayName/key triple, and returns a projection whose members key is an explicit
        # null.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                Unread = @('groups/role_sec_team/members')
                Causes = @([PSCustomObject]@{ Cause = "Could not read members for group g-1: Too many requests (429). The Members property is omitted rather than reported as empty."; Target = 'g-1' })
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir1') -Include Groups `
            -WarningAction SilentlyContinue -ErrorVariable ExErr -ErrorAction SilentlyContinue
        # CONTENT, not merely count: an entry that is the empty string would satisfy a count
        # assertion while naming nothing, which is exactly the guard-shaped-but-inert trap.
        @($Bundle.IncompleteReads).Count | Should -Be 1
        @($Bundle.IncompleteReads)[0] | Should -Be 'groups/role_sec_team/members'
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'groups/role_sec_team/members'
        $Partial[0].Exception.Message | Should -Match 'explicit null'
    }

    It 'counts IncompleteReads as partial reports, not as unread collections' {
        # One Get-OERInventory run raises ONE InventoryPartial naming every triple it lost, so this
        # count is of REPORTS. The message used to read "1 Entra ID collection read(s) failed" and
        # then list seven collections -- two headline numbers on one export that contradicted each
        # other, and contradicted Get-OERInventory's own "7 collection(s)" on the same run.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            Write-Error -Message 'This inventory is PARTIAL: 3 collection(s) could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded `
                -TargetObject 'administrativeUnits/AU-One/scopedRoles, administrativeUnits/AU-Two/scopedRoles, administrativeUnits/AU-Three/scopedRoles' `
                -ErrorAction Continue
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @()
                AdministrativeUnits = @(
                    [PSCustomObject]@{ displayName = 'AU-One'; description = $null; restricted = $false; scopedRoles = $null }
                    [PSCustomObject]@{ displayName = 'AU-Two'; description = $null; restricted = $false; scopedRoles = $null }
                    [PSCustomObject]@{ displayName = 'AU-Three'; description = $null; restricted = $false; scopedRoles = $null }
                )
                Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir-count') -Include AdministrativeUnits `
            -WarningAction SilentlyContinue -ErrorVariable ExErr -ErrorAction SilentlyContinue

        # Non-vacuity: one report standing for three collections is the whole point of the fixture.
        @($Bundle.IncompleteReads).Count | Should -Be 1
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        @($Partial).Count | Should -Be 1
        foreach ($Unit in @('AU-One', 'AU-Two', 'AU-Three')) {
            $Partial[0].Exception.Message | Should -Match "administrativeUnits/$Unit/scopedRoles"
        }
        $Partial[0].Exception.Message |
            Should -Match '1 partial Entra ID read entry\(ies\)' -Because 'the count names what it actually counts'
        $Partial[0].Exception.Message |
            Should -Not -Match 'collection read\(s\) failed' -Because 'one report standing for three collections must not be reported as one collection'
    }

    It 'opens the export InventoryPartial message by saying objects were left out for a shared name when that is the only cause' {
        # F5. The group reader leaves out two live groups that share a name and names them in its
        # Unread list. Nothing is unread and nothing is written as null, so an opening that spoke
        # only of collections that could not be read would be untrue of this export.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @()
                Unread = @('groups/Dup')
                Causes = @([PSCustomObject]@{ Cause = 'Two or more live objects share the name groups/Dup (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'; Target = 'groups/Dup' })
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir-dup') -Include Groups `
            -WarningAction SilentlyContinue -ErrorVariable ExErr -ErrorAction SilentlyContinue

        # Reach proof: the group read ran, its one report is the only entry, and Export raised its own error.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly
        @($Bundle.IncompleteReads) | Should -Be @('groups/Dup')
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'groups/Dup'
        $Partial[0].Exception.Message |
            Should -BeLike '*1 partial Entra ID read entry(ies) name collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are NOT stated as facts in the bundle*'
    }

    It 'still writes the whole bundle under -ErrorAction Stop when the inner read was partial' {
        # The inner Get-OERInventory call must PIN -ErrorAction Continue. Unpinned it inherits
        # $ErrorActionPreference from Export's scope, so under -ErrorAction Stop -- the usage both
        # .DESCRIPTIONs tell operators to adopt -- the inner InventoryPartial terminates at the call
        # site, which sits outside any try/catch and before a single file is written. The operator
        # then gets an exception and NO BUNDLE, instead of "summary first, then a loud error".
        #
        # The mock falls back to $ErrorActionPreference (NOT to a hardcoded 'Continue') when
        # $ErrorAction is unbound, which is precisely how the real cmdlet inherits the preference.
        # A hardcoded fallback would make this test INERT: it would stay non-terminating with the
        # pin removed and pass either way.
        #
        # Get-OERInventory no longer reads the groups, so the partial read under test is an
        # administrative unit's, and the run includes AdministrativeUnits to reach that call. The
        # group read reports its own unread collection beside it, through the reader's Unread list.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $ErrorAction)
            $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
            Write-Error -Message 'This inventory is PARTIAL: administrativeUnits/AU-One scopedRoles could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded `
                -TargetObject 'administrativeUnits/AU-One/scopedRoles' -ErrorAction $Ea
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @()
                AdministrativeUnits = @([PSCustomObject]@{ displayName = 'AU-One'; description = $null; restricted = $false; scopedRoles = $null })
                Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                Unread = @('groups/role_sec_team/members')
                Causes = @()
            }
        }
        # A real group so groupsRoster.json is genuinely written: the assertion below is that the
        # WHOLE bundle survives, not merely inventory.json. The Describe-level mock returns nothing,
        # which skips the roster file and would make that half of the assertion unfalsifiable.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $true; GroupType = 'Assigned' }
        }

        $Root = Join-Path $TestDrive 'eastop'
        $Caught = $null
        # 2>$null keeps the inner record out of the test output: the pin makes it a visible
        # non-terminating error. It does not touch the exception -ErrorAction Stop raises, which the
        # catch below receives.
        try {
            Export-OERInventory -OutputPath $Root -Include Groups, AdministrativeUnits -WarningAction SilentlyContinue -ErrorAction Stop 2>$null | Out-Null
        } catch {
            $Caught = $PSItem
        }

        # The bundle must exist on disk regardless of how the error surfaced -- that is the whole
        # point. Asserted from the filesystem, not from $Bundle, since a terminating failure at the
        # inner call site leaves $Bundle null and no directory at all.
        $Written = @(Get-ChildItem -Path $Root -Recurse -Filter 'inventory.json' -ErrorAction SilentlyContinue)
        @($Written).Count |
            Should -Be 1 -Because 'an inner partial read must not cost the operator the entire bundle'
        @(Get-ChildItem -Path $Root -Recurse -Filter 'groupsRoster.json' -ErrorAction SilentlyContinue).Count | Should -Be 1
        # -ErrorAction Stop must still be honoured -- by Export's OWN trailing error, after $Out.
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Be 'InventoryPartial,Export-OERInventory'
        $Caught.Exception.Message | Should -Match 'groups/role_sec_team/members'
        $Caught.Exception.Message | Should -Match 'administrativeUnits/AU-One/scopedRoles'
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1 -ParameterFilter { $ErrorAction -eq 'Continue' }
    }

    It 'falls back to the error message when the partial error carries no TargetObject' {
        # A record whose TargetObject is empty must not become a blank IncompleteReads entry: the
        # summary would then count a gap it cannot name. Get-OERInventory no longer reads the groups,
        # so the record is an administrative unit's.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            Write-Error -Message 'This inventory is PARTIAL: administrativeUnits/AU-One scopedRoles could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded -ErrorAction Continue
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @()
                AdministrativeUnits = @([PSCustomObject]@{ displayName = 'AU-One'; description = $null; restricted = $false; scopedRoles = $null })
                Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        # 2>$null keeps the inner record out of the test output: the export pins that call to
        # -ErrorAction Continue, so the record is a visible non-terminating error whatever this call's
        # own -ErrorAction is.
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir2') -Include AdministrativeUnits `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null
        @($Bundle.IncompleteReads).Count | Should -Be 1
        @($Bundle.IncompleteReads)[0] | Should -Not -BeNullOrEmpty
        @($Bundle.IncompleteReads)[0] | Should -Match 'AU-One'
    }

    It 'reports an empty IncompleteReads and raises no InventoryPartial when every collection was read' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @() })
                Unread = @(); Causes = @()
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir3') -Include Groups `
            -WarningAction SilentlyContinue -ErrorVariable ExErr -ErrorAction SilentlyContinue
        $Bundle.PSObject.Properties.Name | Should -Contain 'IncompleteReads'
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 0
    }

    It 'reports an unknown member count rather than one for a group whose members were not read' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                Unread = @('groups/role_sec_team/members'); Causes = @()
            }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $true; GroupType = 'Assigned' }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir4') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Roster = Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
        @($Roster).Count | Should -Be 1
        @($Roster)[0].displayName | Should -Be 'role_sec_team'
        $null -eq @($Roster)[0].memberCount |
            Should -BeTrue -Because 'a null members key is an unread membership, and @($null).Count would report it as 1'
    }

    It 'still reports a real member count for a group whose members were read' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @('person26@example.com','person27@example.com') })
                Unread = @(); Causes = @()
            }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $true; GroupType = 'Assigned' }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir5') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Roster = Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
        @($Roster)[0].memberCount | Should -Be 2
    }

    It 'does not class a group as RBAC-relevant on an eligibility key that was never read' {
        # eligibility is ABSENT on a group whose eligibility read failed. @($null).Count is 1, so a
        # bare count in the $DetailedGroups filter would promote every such group into inventory.json
        # on evidence that does not exist. The group reader returns such a group, read in full,
        # because its relevance could not be decided (R2).
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; description = $null; members = @() })
                Unread = @('groups/PlainTeam/eligibility', 'groups/PlainTeam/pimPolicy'); Causes = @()
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir6') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.Version | Should -Be '1.0'
        @($Inv.Groups).Count |
            Should -Be 0 -Because 'an absent eligibility key is not evidence of any eligibility'
    }

    It 'still classes a group as RBAC-relevant on a genuinely declared eligibility' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; description = $null; members = @()
                        eligibility = @([PSCustomObject]@{ principal = 'person30@example.com'; accessType = 'member' }) })
                Unread = @(); Causes = @()
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir7') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups).Count | Should -Be 1
    }

    It 'writes the explicit null through to inventory.json rather than an empty array' {
        # End-to-end: the file Invoke-OERStructure -Prune actually reads must carry null, since an
        # empty array there is a DECLARED empty membership and prunes every live member.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                Unread = @('groups/role_sec_team/members'); Causes = @()
            }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir8') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
        $Raw | Should -Match '"members"\s*:\s*null'
        $Doc = $Raw | ConvertFrom-Json
        $Node = @($Doc.Groups)[0]
        $Node.PSObject.Properties.Name | Should -Contain 'members'
        InModuleScope $script:moduleName -Parameters @{ Node = $Node } {
            param($Node)
            Test-OERDeclaredNull -Node $Node -Name 'members' |
                Should -BeTrue -Because 'this is the gate -Prune consults on the written document'
        }
    }
}

Describe 'Export-OERInventory (prompt + readme + self-check)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # Groups are not under test here: the group read finds none.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{ Version='1.0'; Groups=@(); AdministrativeUnits=@(); Catalogs=@(); AccessPackages=@(); AccessReviews=@(); RoleAssignments=@(); RoleManagementPolicies=@() }
            $inv.PSObject.TypeNames.Insert(0,'Omnicit.EntraRBAC.Inventory'); $inv
        }
    }

    It 'writes the prompt, README and JSON Schema' {
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        Test-Path (Join-Path $Result.BundlePath 'rbac-architect-prompt.md') | Should -BeTrue
        Test-Path (Join-Path $Result.BundlePath 'README.md') | Should -BeTrue
        Test-Path (Join-Path $Result.BundlePath 'schema.json') | Should -BeTrue
        # the emitted schema is valid JSON
        { Get-Content (Join-Path $Result.BundlePath 'schema.json') -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'says in the README that nothing was left unread when the export read everything, and keeps that out of the JSON' {
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'readme-complete') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: both group reads ran (the inventory's group reader and the roster), and the
        # export itself reports a complete read.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
        @($Result.IncompleteReads).Count | Should -Be 0
        @($Result.SkippedScopes).Count | Should -Be 0
        @($Result.SkippedEligibilityScopes).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Result.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match 'Nothing\.'
        $Collapsed | Should -Match 'read everything it was asked to read'
        @(Get-SectionBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -MatchExactly 'This bundle is PARTIAL'
        Assert-ListStaysOutOfJson -BundlePath $Result.BundlePath -Forbidden @('Nothing. `Export-OERInventory`')
    }

    It 'seeds the naming convention from a matching tenant profile' {
        Mock -ModuleName $script:moduleName Get-OERConfiguration {
            [PSCustomObject]@{ TenantAlias='contoso'; TenantId='t-123'; Naming=@{ Group='role_sec_{area}_{tier}' }; Defaults=@{}; Path='x' }
        }
        InModuleScope $script:moduleName { $script:_OERAuthState = [PSCustomObject]@{ TenantId='t-123' } }
        $Result = Export-OERInventory -OutputPath $TestDrive -Include Groups
        $Prompt = Get-Content (Join-Path $Result.BundlePath 'rbac-architect-prompt.md') -Raw
        $Prompt | Should -Match ([regex]::Escape('role_sec_{area}_{tier}'))
    }

    It 'warns when the assembled inventory is not schema-valid' {
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema {
            [PSCustomObject]@{ Valid = $false; Errors = @([PSCustomObject]@{ Section='groups'; Message='bad' }) }
        }
        Export-OERInventory -OutputPath $TestDrive -Include Groups -WarningVariable Warn | Out-Null
        ($Warn -join "`n") | Should -Match 'schema'
    }
}

Describe 'Export-OERInventory (members and owners left out as PIM for Groups access, BL-125)' {
    # BL-125 (A3). The group reader leaves out a member or owner whose access PIM for Groups holds and
    # names the group in its PimLeftOut list; the export writes that list into the README, adds the
    # members left out to the roster's member count, and carries an unread assignment read into
    # IncompleteReads through the reader's Unread list, like every other unread collection.
    BeforeAll {
        $script:PimHeading = '## Members and owners left out as PIM for Groups access'
        function Get-ReadmePimSection {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:PimHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{ Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @(); AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @() }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory'); $inv
        }
        # The roster: the two groups the reader below returns, by the same ids.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-pim'; DisplayName = 'role_sec_pim'; GroupType = 'Assigned'; IsAssignableToRole = $true }
            [PSCustomObject]@{ Id = 'g-unread'; DisplayName = 'role_sec_unread'; GroupType = 'Assigned'; IsAssignableToRole = $true }
        }
        # g-pim: two members written and one left out as an activation. g-unread: members unread
        # (an explicit null), one owner left out.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $G1 = [PSCustomObject]@{ displayName = 'role_sec_pim'; roleAssignable = $true; dynamic = $false; description = $null; members = @('person1@contoso.com', 'person2@contoso.com'); eligibility = @() }
            $G2 = [PSCustomObject]@{ displayName = 'role_sec_unread'; roleAssignable = $true; dynamic = $false; description = $null; members = $null; eligibility = @() }
            if ($IncludeId) {
                $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'g-pim' -Force
                $G2 | Add-Member -NotePropertyName id -NotePropertyValue 'g-unread' -Force
            }
            [PSCustomObject]@{
                Groups     = @($G1, $G2)
                Unread     = @('groups/role_sec_unread/members')
                Causes     = @()
                PimLeftOut = @(
                    [PSCustomObject]@{ GroupId = 'g-pim'; Group = 'role_sec_pim'; Members = 1; Owners = 0; Basis = 'Assignments' }
                    [PSCustomObject]@{ GroupId = 'g-unread'; Group = 'role_sec_unread'; Members = 0; Owners = 1; Basis = 'Assignments' }
                )
            }
        }
    }

    It 'writes one README bullet per group the reader left members or owners out of' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-readme') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Section = Get-ReadmePimSection -BundlePath $Bundle.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly (@(
                '- `role_sec_pim`: 1 member(s) and 0 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
                '- `role_sec_unread`: 0 member(s) and 1 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
            ) -join "`n")
        $Section | Should -Not -Match 'None\.'
        # The list goes into the README alone: inventory.json keeps its shape and no JSON file names it.
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden @($script:PimHeading, 'left out -- an activation')
    }

    It 'adds the members left out to the roster member count, and keeps an unknown count unknown' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-roster') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Roster = @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
        $Roster.Count | Should -Be 2
        ($Roster | Where-Object { $_.displayName -eq 'role_sec_pim' }).memberCount | Should -Be 3
        $null -eq ($Roster | Where-Object { $_.displayName -eq 'role_sec_unread' }).memberCount |
            Should -BeTrue -Because 'members is null, unread, so the count stays the roster''s "not known" value'
        # inventory.json holds the two members written, not the one left out.
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @(($Inv.Groups | Where-Object { $_.displayName -eq 'role_sec_pim' }).members) | Should -Be @('person1@contoso.com', 'person2@contoso.com')
    }

    Context 'a group read in full that inventory.json does not keep' {
        # The reader reads a group in full when its relevance could not be read, and the export's keep
        # filter then drops it from inventory.json. Its PimLeftOut entry is about a group the document
        # does not hold, so the README does not list it; the roster's memberCount still counts the
        # member left out, since it is the live count of every group read in full.
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{ Id = 'g-pim'; DisplayName = 'role_sec_pim'; GroupType = 'Assigned'; IsAssignableToRole = $true }
                [PSCustomObject]@{ Id = 'g-drop'; DisplayName = 'sec_unjudged'; GroupType = 'Assigned'; IsAssignableToRole = $false }
            }
            $script:KeptLeftOut = @()
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
                param($IncludeId)
                # g-pim is kept (role-assignable); g-drop is neither role-assignable nor eligible and
                # carries no pimPolicy, so the keep filter drops it. g-drop had one member left out.
                $G1 = [PSCustomObject]@{ displayName = 'role_sec_pim'; roleAssignable = $true; dynamic = $false; description = $null; members = @('person1@contoso.com'); eligibility = @() }
                $G2 = [PSCustomObject]@{ displayName = 'sec_unjudged'; roleAssignable = $false; dynamic = $false; description = $null; members = @('person3@contoso.com'); eligibility = @() }
                if ($IncludeId) {
                    $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'g-pim' -Force
                    $G2 | Add-Member -NotePropertyName id -NotePropertyValue 'g-drop' -Force
                }
                [PSCustomObject]@{
                    Groups     = @($G1, $G2)
                    Unread     = @()
                    Causes     = @()
                    PimLeftOut = @($script:KeptLeftOut) + @([PSCustomObject]@{ GroupId = 'g-drop'; Group = 'sec_unjudged'; Members = 1; Owners = 0; Basis = 'Assignments' })
                }
            }
        }

        It 'writes no README bullet for it beside a kept group''s bullet, and still counts its left-out member in the roster' {
            $script:KeptLeftOut = @([PSCustomObject]@{ GroupId = 'g-pim'; Group = 'role_sec_pim'; Members = 1; Owners = 0; Basis = 'Assignments' })
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-dropped-mixed') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            # Reach proof: the keep filter dropped the group from inventory.json.
            $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_pim')
            ((Get-SectionBullets -Section (Get-ReadmePimSection -BundlePath $Bundle.BundlePath)) -join "`n") |
                Should -BeExactly '- `role_sec_pim`: 1 member(s) and 0 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
            (Get-ReadmePimSection -BundlePath $Bundle.BundlePath) | Should -Not -Match 'sec_unjudged'
            $Roster = @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
            ($Roster | Where-Object { $_.displayName -eq 'sec_unjudged' }).memberCount | Should -Be 2
            ($Roster | Where-Object { $_.displayName -eq 'role_sec_pim' }).memberCount | Should -Be 2
        }

        It 'says in the README that none was left out when it is the only group that left one out' {
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-dropped-only') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $Section = Get-ReadmePimSection -BundlePath $Bundle.BundlePath
            ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. This export left no member or owner out as PIM for Groups access.'))
            @(Get-SectionBullets -Section $Section).Count | Should -Be 0
            $Section | Should -Not -Match 'sec_unjudged'
            $Roster = @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
            ($Roster | Where-Object { $_.displayName -eq 'sec_unjudged' }).memberCount | Should -Be 2
            ($Roster | Where-Object { $_.displayName -eq 'role_sec_pim' }).memberCount | Should -Be 1
        }
    }

    It 'says in the README that none was left out when the reader left nobody out, also for a reader result without the list' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-none') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
        $Section = Get-ReadmePimSection -BundlePath $Bundle.BundlePath
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. This export left no member or owner out as PIM for Groups access.'))
        @(Get-SectionBullets -Section $Section).Count | Should -Be 0
        @($ExErr).Count | Should -Be 0
    }

    It 'writes the "none" text, and no error from the missing list, when the group read stops (the catch path)' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { throw [System.Exception]::new('stop') }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-stop') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
        # Reach proof: the read stopped and the groups section is reported unread.
        @($Bundle.IncompleteReads)[0] | Should -Be 'groups'
        $Section = Get-ReadmePimSection -BundlePath $Bundle.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. This export left no member or owner out as PIM for Groups access.'))
        # The only error the export publishes is its own InventoryPartial. -ErrorVariable also collects
        # the records raised inside nested calls (the reader's stop among them), so the export's own are
        # the ones whose id names it; and no record at all is about the list.
        @($ExErr | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Export-OERInventory' } |
                ForEach-Object { $_.FullyQualifiedErrorId }) | Should -Be @('InventoryPartial,Export-OERInventory')
        @($ExErr | Where-Object { "$($_.Exception.Message)" -match 'PimLeftOut' }).Count | Should -Be 0
    }

    It 'names an unread assignment read in IncompleteReads, the README and the InventoryPartial message' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            param($IncludeId)
            $G1 = [PSCustomObject]@{ displayName = 'role_sec_pim'; roleAssignable = $true; dynamic = $false; description = $null; members = @('person1@contoso.com'); eligibility = @() }
            if ($IncludeId) { $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'g-pim' -Force }
            [PSCustomObject]@{
                Groups     = @($G1)
                Unread     = @('groups/role_sec_pim/pimAssignments')
                Causes     = @([PSCustomObject]@{ Cause = 'Could not read the PIM for Groups assignments of group g-pim: refused (403).'; Target = 'g-pim' })
                PimLeftOut = @([PSCustomObject]@{ GroupId = 'g-pim'; Group = 'role_sec_pim'; Members = 1; Owners = 0; Basis = 'Eligibility' })
            }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-unread') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
        @($Bundle.IncompleteReads) | Should -Be @('groups/role_sec_pim/pimAssignments')
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match ([regex]::Escape('groups/role_sec_pim/pimAssignments'))
        $Partial[0].Exception.Message | Should -Match ([regex]::Escape('Could not read the PIM for Groups assignments of group'))
        $CouldNotRead = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        ((Get-SectionBullets -Section $CouldNotRead) -join "`n") | Should -BeExactly '- Entra ID: `groups/role_sec_pim/pimAssignments`'
        ((Get-SectionBullets -Section (Get-ReadmePimSection -BundlePath $Bundle.BundlePath)) -join "`n") |
            Should -BeExactly '- `role_sec_pim`: 1 member(s) and 0 owner(s) left out -- eligible for the same access; the group''s PIM for Groups assignments could not be read'
        $Roster = @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
        ($Roster | Where-Object { $_.displayName -eq 'role_sec_pim' }).memberCount | Should -Be 2
    }
}

Describe 'Export-OERInventory (members and owners left out as PIM for Groups access, through the real group reader, BL-125)' {
    # The real Get-OERInventoryGroup and Get-OERGroupPimHeldAccess; the reads above the transport are
    # mocked (the list, the per-group collections, the criterion, the policy lookup and the PIM for
    # Groups assignment read). The export's default relevant-only read keeps the role-assignable group.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-pim'; DisplayName = 'role_sec_pim'; GroupType = 'Assigned'; IsAssignableToRole = $true; SecurityEnabled = $true }
        }
        Mock -ModuleName $script:moduleName Read-OERGroupCollection {
            param($GroupId, $Collection)
            $Value = switch ($Collection) {
                'Members' { @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'u-act'; userPrincipalName = 'person2@contoso.com' }) }
                'Owners' { @(@{ id = 'o-act'; userPrincipalName = 'person6@contoso.com' }) }
                default { @() }
            }
            [PSCustomObject]@{ Collection = $Collection; Read = $true; Value = $Value; ErrorId = $null; Message = $null; Exception = $null }
        }
        Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
        Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
            [PSCustomObject]@{
                Read      = $true
                Value     = @(
                    @{ principalId = 'u-std'; accessId = 'member'; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = $null; endDateTime = $null }
                    @{ principalId = 'u-act'; accessId = 'member'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' }
                    @{ principalId = 'o-act'; accessId = 'owner'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' }
                )
                Message   = $null
                Exception = $null
            }
        }
    }

    It 'leaves the activated member and owner out of inventory.json, names the group in the README and counts the roster in full' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'pim-e2e') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
        # Reach proof: the assignment read ran once, for the group.
        Should -Invoke -ModuleName $script:moduleName Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-pim' }
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups).Count | Should -Be 1
        @($Inv.Groups[0].members) | Should -Be @('person1@contoso.com')
        $Inv.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'owners'
        $Inv.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'id'
        $Roster = @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
        $Roster[0].memberCount | Should -Be 2
        $Readme = Get-Content (Join-Path $Bundle.BundlePath 'README.md') -Raw
        $Readme | Should -Match ([regex]::Escape('- `role_sec_pim`: 1 member(s) and 1 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'))
        # Nothing was unread: the export is complete, and no principal of the group reaches the README.
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($ExErr).Count | Should -Be 0
        $Readme | Should -Not -Match ([regex]::Escape('person2@contoso.com'))
        $Readme | Should -Not -Match ([regex]::Escape('person6@contoso.com'))
    }
}

Describe 'Export-OERInventory (help documents the bundle nesting)' {
    BeforeAll {
        $script:ExportHelp = Get-Help Export-OERInventory -Full
    }

    It 'names BundlePath and the timestamped folder in the description' {
        # Doc-drift guard for a live report where -OutputPath ./live/export was read as the folder that
        # holds inventory.json. It is not: the export writes into a per-run timestamped subfolder, so
        # the only stable handle on the written files is the returned object's BundlePath.
        $Description = (@($script:ExportHelp.Description) | ForEach-Object { $_.Text }) -join "`n"
        $Description | Should -Not -BeNullOrEmpty
        $Description | Should -Match 'BundlePath'
        $Description | Should -Match 'oer-inventory-'
    }

    It 'carries an example that reaches inventory.json through BundlePath' {
        $Examples = (@($script:ExportHelp.Examples.Example) | ForEach-Object {
                ([string]$_.Code + ' ' + ((@($_.Remarks) | ForEach-Object { $_.Text }) -join ' '))
            }) -join "`n"
        $Examples | Should -Not -BeNullOrEmpty
        $Examples | Should -Match 'BundlePath'
        $Examples | Should -Match 'Test-OERStructure'
    }

    It 'says -OutputPath is the parent directory rather than the bundle folder' {
        $Param = @($script:ExportHelp.Parameters.Parameter) | Where-Object { $_.Name -eq 'OutputPath' }
        $Param | Should -Not -BeNullOrEmpty
        $ParamText = (@($Param.Description) | ForEach-Object { $_.Text }) -join ' '
        $ParamText | Should -Not -BeNullOrEmpty
        $ParamText | Should -Match 'PARENT'
    }

    It 'says inventory.json carries the tenantId Get-OERInventory writes, and that it is not the tenant as named (BL-88, A14)' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Description = ((@($script:ExportHelp.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Description | Should -Match ([regex]::Escape("inventory.json carries the top-level tenantId that Get-OERInventory writes -- the tenant ID the session's Microsoft Graph token was issued for -- so Invoke-OERStructure applies it only in that tenant and refuses it elsewhere with DocumentTenantMismatch; the Get-OERInventory help describes the rule."))

        $Param = @($script:ExportHelp.Parameters.Parameter) | Where-Object { $_.Name -eq 'TenantId' }
        $Param | Should -Not -BeNullOrEmpty
        $ParamText = ((@($Param.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $ParamText | Should -Match ([regex]::Escape("The tenantId written into inventory.json is the tenant ID the session's Microsoft Graph token was issued for, not this value."))
    }

    It 'says which Azure role management policies are exported, where the unjudged entry stands, and that -AllRolePolicies keeps every one (BL-107)' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Description = ((@($script:ExportHelp.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Description | Should -Match ([regex]::Escape('WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED.'))
        $Description | Should -Match ([regex]::Escape('keeps a role''s policy at a scope only when the role has an active role assignment or a PIM eligibility EXACTLY at that scope, or the policy has been changed.'))
        $Description | Should -Match ([regex]::Escape('A policy that cannot be judged is kept, never dropped, and its scope is named in IncompleteReads (below)'))
        # Sprint 11 step 6 (BL-133): the role assignment principals that could not be read stand between
        # the Entra ID entries and these.
        $Description | Should -Match ([regex]::Escape('After every Entra ID entry, IncompleteReads carries one entry per role assignment principal that could not be read'))
        $Description | Should -Match ([regex]::Escape('Last, after those entries, IncompleteReads carries one entry per Azure scope where at least one role management policy could not be judged'))
        $Description | Should -Match ([regex]::Escape('It does not mean every policy at the scope was kept: when only one row could not be judged, the other unused, unchanged policies there are still left out.'))
        $Description | Should -Not -Match 'nothing is missing for it'
        $Description | Should -Match ([regex]::Escape('plus one per such Azure scope, and not the number of unread collections'))
        $Description | Should -Match ([regex]::Escape('Invoke-OERStructure reads and writes only the policies a document declares'))

        $Param = @($script:ExportHelp.Parameters.Parameter) | Where-Object { $_.Name -eq 'AllRolePolicies' }
        $Param | Should -Not -BeNullOrEmpty
        $ParamText = ((@($Param.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $ParamText | Should -Match ([regex]::Escape('export the policy of every Azure role at every scope the walk reads, as earlier versions did'))
        $ParamText | Should -Match ([regex]::Escape('no role assignment list is read for the selection, and no scope is named in IncompleteReads as kept without being judged'))

        $Examples = (@($script:ExportHelp.Examples.Example) | ForEach-Object { [string]$_.Code }) -join "`n"
        $Examples | Should -Match ([regex]::Escape('-AllRolePolicies'))
    }
}

Describe 'Export-OERInventory (directory role sections)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        # Groups are not under test here: the default -Include reads them, and finds none.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # -All-scope Azure walk zeroed out (Scopes empty) so a default -Include (which still carries
        # RoleAssignments) does not need the Azure per-scope mocking this Describe does not set up.
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @()
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $AllDirectoryRolePolicies)
            $Policy = [PSCustomObject]@{ role = 'Reports Reader'; activationMaxHours = 8 }
            $Assignment = [PSCustomObject]@{ role = 'Reports Reader'; principal = 'person26@example.com'; assignmentType = 'Eligible' }
            # The export does not ask Get-OERInventory for ids any more, so a real one stamps none. The
            # mock stamps them whatever it is asked, so the strip below (kept as a guard: a section that
            # arrived with an id must never write it into inventory.json) is still proven by the
            # 'strips id from both directory sections' test.
            $Policy | Add-Member -NotePropertyName id -NotePropertyValue 'pol-1' -Force
            $Assignment | Add-Member -NotePropertyName id -NotePropertyValue 'sched-1' -Force
            $inv = [PSCustomObject]@{
                Version                          = '1.0'
                Groups                           = @()
                AdministrativeUnits              = @()
                Catalogs                         = @()
                AccessPackages                   = @()
                AccessReviews                    = @()
                DirectoryRoleManagementPolicies  = @($Policy)
                DirectoryRoleAssignments         = @($Assignment)
                RoleAssignments                  = @()
                RoleManagementPolicies           = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
    }

    It 'passes both directory sections to Get-OERInventory under the default -Include' {
        Export-OERInventory -OutputPath $TestDrive | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $Include -contains 'DirectoryRoleManagementPolicies' -and $Include -contains 'DirectoryRoleAssignments'
        }
    }

    It 'does NOT acquire an ARM token for -Include DirectoryRoleAssignments alone' {
        Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleAssignments | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly -ParameterFilter {
            -not $IncludeARM
        }
    }

    It 'forwards -AllDirectoryRolePolicies to the internal Get-OERInventory call' {
        Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies -AllDirectoryRolePolicies | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            $AllDirectoryRolePolicies -eq $true
        }
    }

    It 'does not forward -AllDirectoryRolePolicies when the switch is absent' {
        Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            -not $AllDirectoryRolePolicies
        }
    }

    It 'lists the two per-area files in the WhatIf plan' {
        $Out = Join-Path $TestDrive 'dir-whatif'
        New-Item -ItemType Directory -Path $Out -Force | Out-Null
        $Result = Export-OERInventory -OutputPath $Out -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -WhatIf
        $Result.Files | Should -Contain 'directoryRoleManagementPolicies.json'
        $Result.Files | Should -Contain 'directoryRoleAssignments.json'
    }

    It 'writes the two per-area files to disk' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
        Test-Path (Join-Path $Result.BundlePath 'directoryRoleManagementPolicies.json') | Should -BeTrue
        Test-Path (Join-Path $Result.BundlePath 'directoryRoleAssignments.json') | Should -BeTrue
        $Result.Files | Should -Contain 'directoryRoleManagementPolicies.json'
        $Result.Files | Should -Contain 'directoryRoleAssignments.json'
    }

    It 'strips id from both directory sections in the written inventory.json' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.DirectoryRoleManagementPolicies[0].PSObject.Properties.Name | Should -Not -Contain 'id'
        $Inv.DirectoryRoleAssignments[0].PSObject.Properties.Name | Should -Not -Contain 'id'
    }

    It 'reports the directory section counts on the bundle summary' {
        $Result = Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
        $Result.DirectoryRoleManagementPolicies | Should -Be 1
        $Result.DirectoryRoleAssignments | Should -Be 1
    }

    It 'renders the DirRoleAsgn column when the returned InventoryBundle is formatted' {
        $Formatted = Export-OERInventory -OutputPath $TestDrive -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments |
            Format-Table | Out-String -Width 200
        $Formatted | Should -Match 'DirRolePol'
        $Formatted | Should -Match 'DirRoleAsgn'
    }
}

Describe 'Export-OERInventory (an unread collection is never applied as empty)' {
    BeforeAll {
        # The two NON-terminating failure shapes. A Write-Error mock body is never promoted by the
        # product code's -ErrorAction Stop, so it would not reach the new catch; a mock with its own
        # CmdletBinding that calls $PSCmdlet.WriteError is (measured in Task 1).
        $script:FailBindingRead = {
            [CmdletBinding()] param($AccessPackage)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }
        $script:FailResourceRead = {
            [CmdletBinding()] param($Catalog)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }

        # The tenant the exported document is applied to: its catalog holds ONE resource and its
        # package ONE binding. The ids differ from the ones the export saw on purpose (a document
        # is portable, and it keeps every apply-side assertion apart from the export-side calls).
        # Set AFTER the export, so the mocks the export read through are not the ones the apply sees.
        function Set-ApplySideTenant {
            Mock -ModuleName $script:moduleName Get-OERAccessPackage -MockWith {
                [PSCustomObject]@{ Id = 'ap-apply-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; IsHidden = $false }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith {
                [PSCustomObject]@{ Id = 'res-1'; OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            # Sync-OERStructureAccessPackage reads the current bindings with a raw resourceRoleScopes
            # request, not through Get-OERAccessPackageResourceRole, so that is what holds the binding.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' } -MockWith {
                [PSCustomObject]@{
                    value = @([PSCustomObject]@{
                            id    = 'rrs-1'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'orig-x' }
                        })
                }
            }
        }

        # The tenant a RENAMED group lives in. The catalog holds two group resources that both RECORD
        # the name 'role_sec_x': the group 1111... that was renamed since (the one the package is
        # bound to) and a NEW group 2222... created under the old name. The directory therefore
        # answers the name 'role_sec_x' with the new group, and an object id with itself -- the two
        # documented behaviours of Resolve-OERGroupId that the module relies on.
        function Set-RenamedGroupApplySideTenant {
            Mock -ModuleName $script:moduleName Get-OERAccessPackage -MockWith {
                [PSCustomObject]@{ Id = 'ap-apply-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; IsHidden = $false }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith {
                [PSCustomObject]@{ Id = 'res-1'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
                [PSCustomObject]@{ Id = 'res-2'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId -MockWith {
                [CmdletBinding()] param([string]$Id, [string]$DisplayName)
                if ($DisplayName -eq '11111111-1111-1111-1111-111111111111') { return $DisplayName }
                if ($DisplayName -eq 'role_sec_x') { return '22222222-2222-2222-2222-222222222222' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' } -MockWith {
                [PSCustomObject]@{
                    value = @([PSCustomObject]@{
                            id    = 'rrs-1'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = '11111111-1111-1111-1111-111111111111' }
                        })
                }
            }
        }

        function Get-ApplyPlan {
            param([string]$Path, [switch]$ForReal)
            if ($ForReal) {
                @(Invoke-OERStructure -Path $Path -Prune -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            } else {
                @(Invoke-OERStructure -Path $Path -Prune -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        # The export reads through the REAL Get-OERInventory, so what is mocked is the readers it
        # calls, healthy by default; a test swaps in the one reader it makes fail.
        Mock -ModuleName $script:moduleName Get-OERCatalog {
            [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
        }
        Mock -ModuleName $script:moduleName Get-OERAccessPackage {
            [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; CatalogId = 'cat-1' }
        }
        Mock -ModuleName $script:moduleName Get-OERCatalogResource {
            [PSCustomObject]@{ Id = 'res-1'; OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_x' }; $M }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
            [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x' }
        }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { }
        # Apply side: the handlers resolve the catalog and the declared group by name.
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-apply-1' }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'orig-x' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
        Mock -ModuleName $script:moduleName Remove-OERAccessPackageResourceRole { }
        Mock -ModuleName $script:moduleName Remove-OERCatalogResource { }
    }

    It 'writes an unread binding set as an explicit null on disk and names it in the one partial (non-terminating)' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b1') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -WarningVariable ExpWarn -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
        @($ExpErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
        @($Bundle.IncompleteReads).Count | Should -Be 1
        @($Bundle.IncompleteReads)[0] | Should -Match 'accessPackages/AP-Sales/resourceRoles'
        @($ExpWarn | Where-Object { "$_" -match 'apply-schema' }).Count | Should -Be 0 -Because 'a document carrying the null still passes the apply schema'

        foreach ($File in 'inventory.json', 'accessPackages.json') {
            $Raw = Get-Content (Join-Path $Bundle.BundlePath $File) -Raw
            $Raw | Should -Match '"resourceRoles":\s*null' -Because "$File must say the bindings are unknown, not empty"
            $Raw | Should -Not -Match '"resourceRoles":\s*\['
            $Parsed = $Raw | ConvertFrom-Json
            $Ap = if ($File -eq 'inventory.json') { @($Parsed.accessPackages)[0] } else { @($Parsed)[0] }
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name | Should -Contain 'resourceRoles' -Because 'an omitted key still reconciles and prunes'
            $null -eq $Ap.PSObject.Properties['resourceRoles'].Value | Should -BeTrue
            $Ap.PSObject.Properties.Name | Should -Not -Contain 'id' -Because 'the document carries no id on an access package, whether or not its resourceRoles was read'
        }
        # Only the collection that was not read is null: the catalog read succeeded and stays a fact.
        $Catalog = @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).catalogs)[0]
        @($Catalog.resources).Count | Should -Be 1
        $Catalog.resources[0].name | Should -Be 'role_sec_x'
    }

    It 'lists an unread binding set in the README under "What this export could not read" and in no JSON file' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b11') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        # Reach proofs: the binding read ran and failed, and the export reports exactly one entry.
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
        @($ExpErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
        @($Bundle.IncompleteReads).Count | Should -Be 1
        $Entry = @($Bundle.IncompleteReads)[0]
        $Entry | Should -Match 'accessPackages/AP-Sales/resourceRoles'

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        $Section | Should -Match 'This bundle is PARTIAL'
        $Section | Should -Not -Match 'Nothing\.'
        # One bullet per IncompleteReads entry, each in a code span; nothing under the Azure labels.
        $Bullets = @(Get-SectionBullets -Section $Section)
        $Bullets.Count | Should -Be 1
        $Bullets[0] | Should -BeExactly ('- Entra ID: `' + $Entry + '`')
        # The README sits where the bundle explains itself, ahead of the file list.
        $Readme = Get-Content (Join-Path $Bundle.BundlePath 'README.md') -Raw
        $Readme.IndexOf($script:CouldNotReadHeading) | Should -BeLessThan $Readme.IndexOf('## Files')
        $Readme.IndexOf($script:CouldNotReadHeading) | Should -BeGreaterThan -1

        # Never in the apply document or any other JSON file, whose shape is unchanged.
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden @($Entry, $Bullets[0])
    }

    It 'writes an unread catalog resource set as an explicit null on disk and names it in the one partial (non-terminating)' {
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b2') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -WarningVariable ExpWarn -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        # Once for the catalog's own resources, once to name its access packages' bindings.
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 2 -Exactly -ParameterFilter { $Catalog -eq 'cat-1' }
        @($ExpErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
        @($Bundle.IncompleteReads).Count | Should -Be 1
        @($Bundle.IncompleteReads)[0] | Should -Match 'catalogs/CAT-IT-Core/resources'
        @($ExpWarn | Where-Object { "$_" -match 'apply-schema' }).Count | Should -Be 0

        foreach ($File in 'inventory.json', 'catalogs.json') {
            $Raw = Get-Content (Join-Path $Bundle.BundlePath $File) -Raw
            $Raw | Should -Match '"resources":\s*null' -Because "$File must say the resources are unknown, not empty"
            $Raw | Should -Not -Match '"resources":\s*\['
            $Parsed = $Raw | ConvertFrom-Json
            $Cat = if ($File -eq 'inventory.json') { @($Parsed.catalogs)[0] } else { @($Parsed)[0] }
            $Cat.displayName | Should -Be 'CAT-IT-Core'
            $Cat.PSObject.Properties.Name | Should -Contain 'resources' -Because 'an omitted key still reconciles and prunes'
            $null -eq $Cat.PSObject.Properties['resources'].Value | Should -BeTrue
            $Cat.PSObject.Properties.Name | Should -Not -Contain 'id'
        }
    }

    It 'tells the operator in the export InventoryPartial message that a resources or resourceRoles key it names is an explicit null' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b1msg') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
        @($Bundle.IncompleteReads)[0] | Should -Match 'accessPackages/AP-Sales/resourceRoles'
        $Partial = @($ExpErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'accessPackages/AP-Sales/resourceRoles'
        $Partial[0].Exception.Message | Should -Match 'members, scopedRoles, resources or resourceRoles key reported here is an explicit null'
    }

    It 'writes a read that succeeded with nothing in it as [] and raises no partial' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith { }
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith { }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b8') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 2 -Exactly
        @($ExpErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        @($Bundle.IncompleteReads).Count | Should -Be 0
        $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
        $Raw | Should -Match '"resourceRoles":\s*\[\s*\]'
        $Raw | Should -Match '"resources":\s*\[\s*\]'
        $Raw | Should -Not -Match '"(resourceRoles|resources)":\s*null'
    }

    It 'plans no binding removal from an export whose binding read failed, though the live package holds a binding' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b3') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Set-ApplySideTenant

        $Rows = Get-ApplyPlan -Path (Join-Path $Bundle.BundlePath 'inventory.json')

        # The handler reached the package and SAW the live binding, so the only thing standing
        # between that binding and a removal row is the explicit null.
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-apply-1' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        $ApRows = @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' })
        $ApRows.Count | Should -BeGreaterThan 0 -Because 'the package was reconciled, not skipped before the prune decision'
        @($ApRows | Where-Object { $_.Detail -match 'undeclared|remov' }).Count | Should -Be 0
        @($ApRows | Where-Object { $_.Action -in 'Removed', 'Extra' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERAccessPackageResourceRole -Times 0
    }

    It 'plans no resource removal from an export whose resource read failed, though the live catalog holds a resource' {
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        # No package in this document: the access package section is not what is under test here.
        Mock -ModuleName $script:moduleName Get-OERAccessPackage -MockWith { }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b4') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Set-ApplySideTenant

        $Rows = Get-ApplyPlan -Path (Join-Path $Bundle.BundlePath 'inventory.json')

        Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq 'cat-apply-1' }
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-apply-1' }
        $CatRows = @($Rows | Where-Object { $_.Section -eq 'catalogs' -and $_.Item -eq 'CAT-IT-Core' })
        $CatRows.Count | Should -BeGreaterThan 0 -Because 'the catalog was reconciled, not skipped before the prune decision'
        @($CatRows | Where-Object { $_.Detail -match 'undeclared|remov' }).Count | Should -Be 0
        @($CatRows | Where-Object { $_.Action -in 'Removed', 'Extra' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERCatalogResource -Times 0
    }

    It 'contrast: the same document with an empty resourceRoles array DOES plan the binding removal' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b5') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
        $Declared = $Raw -replace '"resourceRoles":\s*null', '"resourceRoles": []'
        $Declared | Should -Not -BeExactly $Raw -Because 'the exported document carried the null this test turns into a declared empty set'
        $DeclaredPath = Join-Path $TestDrive 'declared-empty-resourceRoles.json'
        Set-Content -Path $DeclaredPath -Value $Declared -Encoding utf8
        Set-ApplySideTenant

        $Rows = Get-ApplyPlan -Path $DeclaredPath

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        $Removal = @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' -and $_.Detail -match 'undeclared' })
        $Removal.Count | Should -Be 1
        $Removal[0].Action | Should -Be 'Skipped'
        $Removal[0].Detail | Should -BeLike "would remove undeclared resourceRole binding 'Member|orig-x'*"
    }

    It 'contrast: the same document with an empty resources array DOES plan the resource removal' {
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        Mock -ModuleName $script:moduleName Get-OERAccessPackage -MockWith { }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b5c') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
        $Declared = $Raw -replace '"resources":\s*null', '"resources": []'
        $Declared | Should -Not -BeExactly $Raw -Because 'the exported document carried the null this test turns into a declared empty set'
        $DeclaredPath = Join-Path $TestDrive 'declared-empty-resources.json'
        Set-Content -Path $DeclaredPath -Value $Declared -Encoding utf8
        Set-ApplySideTenant

        $Rows = Get-ApplyPlan -Path $DeclaredPath

        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-apply-1' }
        $Removal = @($Rows | Where-Object { $_.Section -eq 'catalogs' -and $_.Item -eq 'CAT-IT-Core' -and $_.Detail -match 'undeclared' })
        $Removal.Count | Should -Be 1
        $Removal[0].Action | Should -Be 'Skipped'
        $Removal[0].Detail | Should -BeLike "would remove undeclared resource 'role_sec_x'*"
    }

    It 'removes no binding when the null document is applied for real, and removes it when the set is declared empty' {
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith $script:FailBindingRead
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b6') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $DocumentPath = Join-Path $Bundle.BundlePath 'inventory.json'
        $Raw = Get-Content $DocumentPath -Raw
        $DeclaredPath = Join-Path $TestDrive 'declared-empty-resourceRoles-real.json'
        Set-Content -Path $DeclaredPath -Value ($Raw -replace '"resourceRoles":\s*null', '"resourceRoles": []') -Encoding utf8
        Set-ApplySideTenant

        # -WhatIf never reaches the Remove cmdlet, so only a real run makes the zero a proof.
        $NullRows = Get-ApplyPlan -Path $DocumentPath -ForReal
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        @($NullRows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' }).Count | Should -BeGreaterThan 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERAccessPackageResourceRole -Times 0

        $EmptyRows = Get-ApplyPlan -Path $DeclaredPath -ForReal
        Should -Invoke -ModuleName $script:moduleName Remove-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter {
            $AccessPackage -eq 'ap-apply-1' -and $ResourceRoleScopeId -eq 'rrs-1'
        }
        @($EmptyRows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Action -eq 'Removed' }).Count | Should -Be 1
    }

    It 'removes no resource when the null document is applied for real, and removes it when the set is declared empty' {
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        Mock -ModuleName $script:moduleName Get-OERAccessPackage -MockWith { }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b7') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $DocumentPath = Join-Path $Bundle.BundlePath 'inventory.json'
        $Raw = Get-Content $DocumentPath -Raw
        $DeclaredPath = Join-Path $TestDrive 'declared-empty-resources-real.json'
        Set-Content -Path $DeclaredPath -Value ($Raw -replace '"resources":\s*null', '"resources": []') -Encoding utf8
        Set-ApplySideTenant

        $NullRows = Get-ApplyPlan -Path $DocumentPath -ForReal
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-apply-1' }
        @($NullRows | Where-Object { $_.Section -eq 'catalogs' -and $_.Item -eq 'CAT-IT-Core' }).Count | Should -BeGreaterThan 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERCatalogResource -Times 0

        $EmptyRows = Get-ApplyPlan -Path $DeclaredPath -ForReal
        Should -Invoke -ModuleName $script:moduleName Remove-OERCatalogResource -Times 1 -Exactly -ParameterFilter {
            $Catalog -eq 'cat-apply-1' -and $ResourceId -eq 'res-1'
        }
        @($EmptyRows | Where-Object { $_.Section -eq 'catalogs' -and $_.Action -eq 'Removed' }).Count | Should -Be 1
    }

    It 'exports a group binding under its object id when the names are unread, so a renamed group is not swapped for the one now carrying its old name' {
        # The package is bound to the group 1111..., which the catalog RECORDED as 'role_sec_x' and
        # which was renamed since; a NEW group 2222... now carries that name. Written under the
        # recorded name the binding would resolve to the new group on apply, so the real binding
        # would be read as undeclared and removed under -Prune. The object id cannot name another.
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith {
            [PSCustomObject]@{ ResourceDisplayName = 'role_sec_x'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadGroup' }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b9') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExpErr

        # Reach proofs for the export: the name-map read ran and failed, the binding read ran.
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 2 -Exactly -ParameterFilter { $Catalog -eq 'cat-1' }
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
        @($Bundle.IncompleteReads | Where-Object { $_ -match 'accessPackages/CAT-IT-Core/catalogResourceNames' }).Count | Should -Be 1
        $DocumentPath = Join-Path $Bundle.BundlePath 'inventory.json'
        $Written = @((Get-Content $DocumentPath -Raw | ConvertFrom-Json).accessPackages)[0]
        @($Written.resourceRoles).Count | Should -Be 1
        $Written.resourceRoles[0].resource | Should -Be '11111111-1111-1111-1111-111111111111'
        Set-RenamedGroupApplySideTenant

        # WhatIf plan: the binding is matched, nothing is planned for removal.
        $Rows = Get-ApplyPlan -Path $DocumentPath
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
        $ApRows = @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' })
        @($ApRows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like "resourceRole 'Member' on '11111111-1111-1111-1111-111111111111' already bound*" }).Count |
            Should -Be 1 -Because 'the live binding was found and matched, which is what makes the absence of a removal row a proof'
        @($ApRows | Where-Object { $_.Detail -match 'undeclared|would remove|would add' }).Count | Should -Be 0

        # A real run: -WhatIf never reaches the Remove cmdlet, so only this makes the zero a proof.
        # The run's own rows are kept so the zero is tied to the prune loop having SEEN the live
        # binding and matched it: a run that stopped before the loop would also remove nothing.
        $RealRows = Get-ApplyPlan -Path $DocumentPath -ForReal
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 2 -Exactly -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
        $RealApRows = @($RealRows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' })
        @($RealApRows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like "resourceRole 'Member' on '11111111-1111-1111-1111-111111111111' already bound*" }).Count |
            Should -Be 1 -Because 'the real run found and matched the live binding, so the prune loop was reached with that binding declared'
        @($RealApRows | Where-Object { $_.Action -in 'Removed', 'Failed' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERAccessPackageResourceRole -Times 0
    }

    It 'contrast: the same document written under the recorded name DOES plan the removal of the real binding' {
        # Proves the fixture can see the defect: with the binding under the name the catalog
        # recorded, the apply resolves it to the NEW group and plans to remove the real binding.
        Mock -ModuleName $script:moduleName Get-OERCatalogResource -MockWith $script:FailResourceRead
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -MockWith {
            [PSCustomObject]@{ ResourceDisplayName = 'role_sec_x'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadGroup' }
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'b10') -Include Catalogs, AccessPackages `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
        $Recorded = $Raw -replace '"resource":\s*"[^"]*"', '"resource": "role_sec_x"'
        $Recorded | Should -Match '"resource":\s*"role_sec_x"' -Because 'the document under test names the binding by the name the catalog recorded'
        $RecordedPath = Join-Path $TestDrive 'recorded-name-resourceRoles.json'
        Set-Content -Path $RecordedPath -Value $Recorded -Encoding utf8
        Set-RenamedGroupApplySideTenant

        $Rows = Get-ApplyPlan -Path $RecordedPath

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-apply-1/resourceRoleScopes*' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'role_sec_x' }
        $Removal = @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'AP-Sales' -and $_.Detail -match 'undeclared' })
        $Removal.Count | Should -Be 1
        $Removal[0].Detail | Should -BeLike "would remove undeclared resourceRole binding 'Member|11111111-1111-1111-1111-111111111111'*"
    }
}

Describe 'Export-OERInventory (a section whose list could not be read is partial)' {
    # BL-05 / decision A9. The export reads through the REAL Get-OERInventory (the administrative units
    # and the access reviews) and the REAL group reader Get-OERInventoryGroup (the groups), so what is
    # mocked is the three readers they call, healthy (and empty) by default; a test swaps in the one
    # that fails. A list that could not be read is written as [] -- the same file a tenant with none
    # produces -- so the only thing that tells the two apart is the partial signal reaching the
    # bundle summary.
    #
    # The failure is a record the reader PUBLISHED, built with its FullyQualifiedErrorId and written
    # with Write-Error -ErrorRecord: the section counts a record only when the id names the reader, and
    # a mock body appends no name (see Get-OERInventory.Tests.ps1, 'still warns at section level for a
    # group read error that is not a per-collection failure').
    BeforeAll {
        $script:GroupListPublished = {
            Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied,Get-OERGroup',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
        }
        $script:AuListPublished = {
            Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied,Get-OERAdministrativeUnit',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
        }
        $script:ArListPublished = {
            Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied,Get-OERAccessReviewDefinition',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
        }
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {}
        Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {}
    }

    It 'names the groups section in IncompleteReads and raises InventoryPartial when the filtered group read fails' {
        # The roster read (-All) is the one that still succeeds, so the entry is the section's alone.
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { -not $All } -MockWith $script:GroupListPublished
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { $All } -MockWith {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $true }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-groups') -Include Groups -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: the filtered read ran and failed, the roster read ran and answered.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $All }
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        $Bundle.RosterCount | Should -Be 1
        $Entries = @((@($Bundle.IncompleteReads) -join ', ') -split ', ')
        $Entries | Should -Contain 'groups'
        $Entries | Should -Not -Contain 'groupsRoster' -Because 'the roster read answered, so only the section is unread'
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
    }

    It 'shows progress while the real group reader reads, and ends it with one Completed' {
        # The record of every call, in order. The reader is the real one, so this is what the export
        # shows an operator: the list status, one record per group, then the end of the activity.
        $script:ExportProgressLog = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName $script:moduleName Write-Progress {
            param($Activity, $Status, $PercentComplete, [switch]$Completed)
            $script:ExportProgressLog.Add($(if ($Completed) { "$Activity|completed" } else { "$Activity|$Status|$PercentComplete" }))
        }
        Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { -not $All } -MockWith {
            foreach ($N in 1..2) {
                [PSCustomObject]@{ Id = "g-$N"; DisplayName = "role_sec_$N"; GroupType = 'Assigned'; IsAssignableToRole = $true; SecurityEnabled = $true; Members = @(); Owners = @(); PimEligibility = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { $All } -MockWith {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_1'; GroupType = 'Assigned'; IsAssignableToRole = $true }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-progress') -Include Groups -AllGroupsDetailed -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proof: the reader read both groups.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $All }
        $Bundle.Groups | Should -Be 2
        @($script:ExportProgressLog) | Should -Be @(
            'Export-OERInventory|Reading the groups in full|'
            'Export-OERInventory|Group 1 of 2|50'
            'Export-OERInventory|Group 2 of 2|100'
            'Export-OERInventory|completed'
        )
    }

    It 'reports the groups section as unread, with one warning and the cause, and still writes the bundle, when the group reader stops on <Label>' -ForEach @(
        @{ Label = 'a throw'; Stop = { throw [System.Exception]::new('stop') }; Expected = 'stop' }
        # A statement-terminating error is not a throw: without a try around the reader's call it would
        # end the call and leave $GroupRead empty, which reads as zero groups. The message is the
        # runtime's own, so the test asks the runtime for it rather than spelling it.
        @{ Label = 'a statement-terminating error'; Stop = { $null.NoSuchMethod() }; Expected = $(try { $null.NoSuchMethod() } catch { [string]$PSItem.Exception.Message }) }
    ) {
        # The error is raised inside the REAL group reader, by a helper it calls for the group's
        # eligibility outside any catch of its own (Resolve-OEREligibilityDuration), so the read stops
        # part-way. The helper is one the export does not call itself: the roster flag is read through
        # Test-OERGroupOnPremisesSynced, so stopping that one would stop the roster read as well.
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { -not $All } -MockWith {
            [PSCustomObject]@{
                Id = 'g-1'; DisplayName = 'role_sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $true; SecurityEnabled = $true
                Members = @(); Owners = @()
                PimEligibility = @([PSCustomObject]@{ principalId = 'p-1'; accessId = 'member'; startDateTime = $null; endDateTime = $null })
            }
        }
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { $All } -MockWith {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $true }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'Person One' } }
        Mock -ModuleName $script:moduleName Resolve-OEREligibilityDuration -MockWith $Stop

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-reader-stops') -Include Groups -AllGroupsDetailed `
            -WarningAction SilentlyContinue -WarningVariable ExWarn -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: the reader was reached, the helper inside it ran once and stopped it, and the
        # roster read after it still ran.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $All }
        Should -Invoke -ModuleName $script:moduleName Resolve-OEREligibilityDuration -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        $Expected | Should -Not -BeNullOrEmpty

        # The groups section is reported unread, first and by its own name, not read as an empty tenant.
        @($Bundle.IncompleteReads)[0] | Should -Be 'groups'
        $Bundle.Groups | Should -Be 0

        # ONE warning, in the reader's own wording for a list that could not be read.
        @($ExWarn | Where-Object { "$_" -like 'Could not read groups:*' }).Count | Should -Be 1
        @($ExWarn | Where-Object { "$_" -eq "Could not read groups: $Expected" }).Count | Should -Be 1

        # The cause reaches the one InventoryPartial the export raises.
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        $Partial[0].Exception.Message | Should -Match 'Causes of the unread group reads'
        $Partial[0].Exception.Message | Should -Match ([regex]::Escape("Could not read groups: $Expected"))

        # The bundle is still written, with the section unread in the README.
        Test-Path -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') | Should -BeTrue
        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly '- Entra ID: `groups`'
    }

    It 'lists the groups section in the README, as written to disk, when the filtered group read fails' {
        # The same failure as the first row above, but written for real (no -WhatIf): the README is
        # only generated when the bundle is, and this is the one that proves the section reaches it.
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { -not $All } -MockWith $script:GroupListPublished
        Mock -ModuleName $script:moduleName Get-OERGroup -ParameterFilter { $All } -MockWith {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $true }
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-groups-readme') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: the filtered read ran and failed, the roster read ran and answered, and the
        # export raised its one InventoryPartial.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $All }
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        $Bundle.RosterCount | Should -Be 1
        @($Bundle.IncompleteReads) | Should -Be @('groups')
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        $Section | Should -Match 'This bundle is PARTIAL'
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly '- Entra ID: `groups`'
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden @('- Entra ID: `groups`')
    }

    It 'names the administrativeUnits section in IncompleteReads and raises InventoryPartial when the unit list fails' {
        Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit -MockWith $script:AuListPublished

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-aus') -Include AdministrativeUnits -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
        $Bundle.AdministrativeUnits | Should -Be 0
        $Entries = @((@($Bundle.IncompleteReads) -join ', ') -split ', ')
        $Entries | Should -Contain 'administrativeUnits'
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
    }

    It 'names the accessReviews section in IncompleteReads and raises InventoryPartial when the access review list fails' {
        Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition -MockWith $script:ArListPublished

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-ars') -Include AccessReviews -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
        $Bundle.AccessReviews | Should -Be 0
        $Entries = @((@($Bundle.IncompleteReads) -join ', ') -split ', ')
        $Entries | Should -Contain 'accessReviews'
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
    }

    It 'writes no IncompleteReads entry and raises no InventoryPartial when the three lists read back empty' {
        # The control for the three rows above: an empty list that WAS read is a fact about the tenant.
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sec-none') `
            -Include Groups, AdministrativeUnits, AccessReviews -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 2 -Exactly
        $Bundle.PSObject.Properties.Name | Should -Contain 'IncompleteReads'
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
    }
}

Describe 'Export-OERInventory (the group roster that could not be read is partial)' {
    # BL-05 / decision A9, the roster half. groupsRoster.json is read-only context, but a roster that
    # could not be read is written as [] exactly like a tenant with no groups, so it is named in
    # IncompleteReads as groupsRoster -- by this cmdlet, not by the group reader, which never sees it.
    # The group reader is mocked here: the group read is healthy and returns the one group, and the
    # roster read (Get-OERGroup -All) is the only thing under test.
    BeforeAll {
        # A non-terminating failure the roster read's -ErrorAction Stop promotes. A Write-Error mock
        # body is never promoted, so it would not reach the catch; a mock with its own CmdletBinding
        # that calls $PSCmdlet.WriteError is.
        $script:FailRosterRead = {
            [CmdletBinding()] param([switch]$All)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # The filtered group read succeeds: it comes back with its one security group.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @() })
                Unread = @(); Causes = @()
            }
        }
    }

    It 'names groupsRoster in IncompleteReads and raises InventoryPartial when the roster read fails' {
        Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:FailRosterRead

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-fail') -Include Groups -WhatIf `
            -WarningVariable ExWarn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: the roster read ran, its failure was reported as a warning, and the roster is empty.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        @($ExWarn | Where-Object { "$_" -like '*Could not read the group roster*' }).Count | Should -Be 1
        $Bundle.RosterCount | Should -Be 0
        @($Bundle.IncompleteReads) | Should -Be @('groupsRoster')
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
    }

    It 'lists groupsRoster in the README, as written to disk, when the roster read fails' {
        Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:FailRosterRead

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-readme') -Include Groups `
            -WarningVariable ExWarn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        # Reach proofs: the roster read ran and failed, and groupsRoster.json is the empty array a
        # tenant with no groups would also produce -- which is why the README has to say it.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        @($ExWarn | Where-Object { "$_" -like '*Could not read the group roster*' }).Count | Should -Be 1
        $Bundle.RosterCount | Should -Be 0
        @($Bundle.IncompleteReads) | Should -Be @('groupsRoster')
        @(Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json).Count | Should -Be 0

        $Section = Get-ReadmeCouldNotReadSection -BundlePath $Bundle.BundlePath
        $Section | Should -Not -BeNullOrEmpty
        $Section | Should -Match 'This bundle is PARTIAL'
        $Section | Should -Not -Match 'Nothing\.'
        ((Get-SectionBullets -Section $Section) -join "`n") | Should -BeExactly '- Entra ID: `groupsRoster`'
        Assert-ListStaysOutOfJson -BundlePath $Bundle.BundlePath -Forbidden @('- Entra ID: `groupsRoster`')
    }

    It 'says in the export InventoryPartial message what a section named alone and the groupsRoster entry mean' {
        Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:FailRosterRead

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-msg') -Include Groups -WhatIf `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        @($Bundle.IncompleteReads) | Should -Be @('groupsRoster')
        $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
        $Partial.Count | Should -Be 1
        # The lead-in must be true when the only entry is groupsRoster, or a collection written as null
        # for want of a name: neither is "a collection that could not be read" alone.
        $Partial[0].Exception.Message |
            Should -BeLike '*1 partial Entra ID read entry(ies) name collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are NOT stated as facts in the bundle*'
        $Partial[0].Exception.Message |
            Should -BeLike '*A section named alone is written as an empty array, which does not mean the tenant has none, and the entry groupsRoster means groupsRoster.json is empty since the group roster could not be read*'
        # An Entra ID partial carries no Azure role selection clause, not even one counting zero
        # scopes.
        $Partial[0].Exception.Message | Should -Not -BeLike '*could not be judged*'
    }

    It 'adds no groupsRoster entry and raises no InventoryPartial when the roster read answers GroupNotFound' {
        # GroupNotFound is an answer -- there are no groups -- not a failed read.
        Mock -ModuleName $script:moduleName Get-OERGroup -MockWith {
            [CmdletBinding()] param([switch]$All)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('No group matches.'), 'GroupNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null))
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-nf') -Include Groups -WhatIf `
            -WarningVariable ExWarn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr

        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter { $All }
        $Bundle.RosterCount | Should -Be 0
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        @($ExWarn | Where-Object { "$_" -like '*Could not read the group roster*' }).Count | Should -Be 0
    }
}

Describe 'Export-OERInventory tenantId (BL-88, A14)' {
    # inventory.json names the tenant the session's Graph token was issued for, so Invoke-OERStructure
    # can refuse a document exported from another tenant. The mocked sign-in sets the module's auth
    # state the way the real one does (the tenant as named, and the tenant the token was issued for).
    # Test-OERStructureSchema is NOT mocked: the export's own self-check must accept the key.
    BeforeAll {
        # The real converter, taken before any test mocks it, so a mock can call through to it.
        $script:RealConvert = InModuleScope $script:moduleName { Get-Command ConvertTo-OERInventory -CommandType Function }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{
                    TenantId      = 'contoso.onmicrosoft.com'
                    TokenTenantId = '44444444-4444-4444-4444-444444444444'
                }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @()
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() }
        }
        # What Get-OERInventory hands back here carries no tenantId: the export writes its OWN capture.
        Mock -ModuleName $script:moduleName Get-OERInventory { & $script:RealConvert }
        # The group read finds no group; the groups section is not what decides tenantId.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
    }

    AfterAll {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    It 'writes the tenant the Graph token was issued for as inventory.json tenantId, and the self-check accepts it' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-groups') -Include Groups `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: the group read ran, the bundle was written, and the real self-check ran over it.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly
        Test-Path (Join-Path $Result.BundlePath 'inventory.json') | Should -BeTrue
        Test-Path (Join-Path $Result.BundlePath 'schema.json') | Should -BeTrue

        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        @($Inv.PSObject.Properties.Name)[0..2] | Should -Be @('version', 'tenantId', 'groups')
        @($Inv.PSObject.Properties.Name).Count | Should -Be 11
        @($Warn | Where-Object { "$_" -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
        @($Warn | Where-Object { "$_" -like '*Could not run the apply-schema self-check*' }).Count | Should -Be 0
    }

    It 'names the granted tenant in the file while the bundle folder and summary keep the tenant as named' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-label') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        $Result.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
        (Split-Path $Result.BundlePath -Leaf) | Should -BeLike 'oer-inventory-contoso.onmicrosoft.com-*'
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
    }

    It 'still carries tenantId when no Entra ID section is read (the Azure-only export)' {
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-azure') -Include RoleAssignments `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: the Azure walk ran (it asked for an ARM token), and no Entra read was made.
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $IncludeARM }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 0
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        @($Inv.PSObject.Properties.Name)[0..2] | Should -Be @('version', 'tenantId', 'groups')
        @($Warn | Where-Object { "$_" -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
    }

    It 'passes the capture to both ConvertTo-OERInventory calls, the Azure-only branch and the canonical one' {
        Mock -ModuleName $script:moduleName ConvertTo-OERInventory { & $script:RealConvert @PesterBoundParameters }
        Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-both') -Include RoleAssignments `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

        # The branch with no Entra section builds its empty document, then the canonical document is built.
        Should -Invoke -ModuleName $script:moduleName ConvertTo-OERInventory -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName ConvertTo-OERInventory -Times 2 -Exactly -ParameterFilter {
            $TenantId -eq '44444444-4444-4444-4444-444444444444'
        }
    }

    It 'writes its own capture, not the tenantId of the inventory Get-OERInventory returned' {
        # AdministrativeUnits, not Groups: Get-OERInventory no longer reads the groups, so a run of
        # groups alone would never call it and the test would prove nothing.
        Mock -ModuleName $script:moduleName Get-OERInventory { & $script:RealConvert -TenantId '77777777-7777-7777-7777-777777777777' }
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-own') -Include AdministrativeUnits `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
    }

    It 'leaves tenantId out, with no warning, when the token reported no tenant ID' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{ TenantId = '11111111-1111-1111-1111-111111111111'; TokenTenantId = $null }
            }
        }
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-none') -Include Groups `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Test-Path (Join-Path $Result.BundlePath 'inventory.json') | Should -BeTrue
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
        @($Inv.PSObject.Properties.Name)[0..1] | Should -Be @('version', 'groups')
        @($Warn).Count | Should -Be 0
    }

    It 'leaves tenantId out when the session holds no state' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'tid-nostate') -Include Groups `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Test-Path (Join-Path $Result.BundlePath 'inventory.json') | Should -BeTrue
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
        @($Warn).Count | Should -Be 0
    }
}

Describe 'Export-OERInventory self-check of a scope at a resource whose name holds a space (Sprint 11 step 3, decision A13)' {
    # The export's own self-check runs the real offline validator over inventory.json. An Azure resource
    # name can hold spaces between other characters, and the validator accepts them since A13 was
    # narrowed, so a role assignment at such a resource passes the self-check; a '#' in a name, which a
    # few resource types allow, is still refused, and the self-check says so when a read hands one over.
    # The real Get-OERInventory leaves such a row out (A13, A15; the Describe 'role assignments at a scope
    # no document can declare' holds that), so the mock below stands in for a read that did not, as the
    # control that the self-check runs. Test-OERStructureSchema is NOT mocked. No id below is version-4
    # shaped.
    BeforeAll {
        $script:SpaceSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:SpaceSub)
                Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility {
            [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() }
        }
        # The one scope's read returns the role assignment rows as Get-OERInventory writes them.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            [PSCustomObject]@{
                RoleAssignments        = @($script:SpaceRows)
                RoleManagementPolicies = @()
            }
        }
    }

    It 'writes the scope with its spaces into inventory.json, and the self-check accepts it' {
        $SqlScope = "$($script:SpaceSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/sales data"
        $script:SpaceRows = @(
            [PSCustomObject]@{ scope = $SqlScope; role = 'Reader'; principal = 'person1@example.com' }
        )
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'space-ok') -Include RoleAssignments `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proofs: the scope was read, and the bundle holds the row.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.roleAssignments | ForEach-Object { $_.scope }) | Should -Be @($SqlScope)
        @($Warn | Where-Object { "$_" -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
        @($Warn | Where-Object { "$_" -like '*Could not run the apply-schema self-check*' }).Count | Should -Be 0
    }

    It 'warns from the self-check when a resource name holds a ''#'', the control that the self-check ran' {
        $HashScope = "$($script:SpaceSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1"
        $script:SpaceRows = @(
            [PSCustomObject]@{ scope = $HashScope; role = 'Reader'; principal = 'person1@example.com' }
        )
        $Result = Export-OERInventory -OutputPath (Join-Path $TestDrive 'space-hash') -Include RoleAssignments `
            -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        $Inv = Get-Content (Join-Path $Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.roleAssignments | ForEach-Object { $_.scope }) | Should -Be @($HashScope)
        $SelfCheck = @($Warn | Where-Object { "$_" -like '*did not pass apply-schema validation*' })
        $SelfCheck.Count | Should -Be 1
        "$($SelfCheck[0])" | Should -BeLike "*First issue: 'scope' at roleAssignments[[]0[]] must be written without a '?' or '#'*"
    }
}

Describe 'Export-OERInventory (the groups are read through the relevance-first group reader, A13)' {
    # Without -AllGroupsDetailed the export asks the group reader to decide first, in two requests
    # per group, which groups are RBAC-relevant, and to read members, owners and policies only for
    # those. Get-OERInventory reads the other Entra ID sections only.
    Context 'what the export asks the reader for' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{ Scopes = @(); Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() } }
            }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventory {
                $inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
                }
                $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $inv
            }
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        }

        It 'asks once for the relevant groups only, with ids, without shared names, under the security-enabled filter' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-default') -WarningAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $RelevantOnly -eq $true -and $IncludeId -eq $true -and $ExcludeSharedName -eq $true -and
                $Filter -eq 'securityEnabled eq true' -and -not $IncludeSyncedGroups
            }
            # Get-OERInventory still reads the other Entra ID sections, and never the groups.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1 -ParameterFilter {
                $Include -contains 'AdministrativeUnits' -and $Include -contains 'DirectoryRoleAssignments'
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 0 -ParameterFilter { $Include -contains 'Groups' }
        }

        It 'asks Get-OERInventory for the other sections without ids, the roster join taking its ids from the group reader' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-no-id') -WarningAction SilentlyContinue | Out-Null
            # Reach proof: the call that reads the other sections ran, once, and the reader got the ids.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1 -ParameterFilter {
                $Include -contains 'AdministrativeUnits' -and $Include -contains 'DirectoryRoleAssignments'
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter { $IncludeId -eq $true }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 0 -ParameterFilter { $IncludeId }
        }

        It 'asks for every group in full under -AllGroupsDetailed' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-all') -Include Groups -AllGroupsDetailed | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                -not $RelevantOnly -and -not $IncludeSyncedGroups -and $IncludeId -eq $true -and $ExcludeSharedName -eq $true -and
                $Filter -eq 'securityEnabled eq true'
            }
        }

        It 'asks the reader to keep synchronized groups under -IncludeSyncedGroups' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-synced') -Include Groups -IncludeSyncedGroups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $RelevantOnly -eq $true -and $IncludeSyncedGroups -eq $true
            }
        }

        It 'asks for every group in full, and nothing about synchronized groups, under -AllGroupsDetailed -IncludeSyncedGroups' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-all-synced') -Include Groups -AllGroupsDetailed -IncludeSyncedGroups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                -not $RelevantOnly -and -not $IncludeSyncedGroups
            }
        }

        It 'always asks the reader to keep security-enabled groups only' -ForEach @(
            @{ Label = 'by default'; Splat = @{} }
            @{ Label = 'under -AllGroupsDetailed'; Splat = @{ AllGroupsDetailed = $true } }
            @{ Label = 'under -IncludeSyncedGroups'; Splat = @{ IncludeSyncedGroups = $true } }
            @{ Label = 'with a -GroupFilter'; Splat = @{ GroupFilter = "startswith(displayName,'role_')" } }
        ) {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-security-only') -Include Groups @Splat | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter { $SecurityEnabledOnly -eq $true }
        }

        It 'asks the reader to show progress as Export-OERInventory in every mode' -ForEach @(
            @{ Label = 'by default'; Splat = @{} }
            @{ Label = 'under -AllGroupsDetailed'; Splat = @{ AllGroupsDetailed = $true } }
            @{ Label = 'under -IncludeSyncedGroups'; Splat = @{ IncludeSyncedGroups = $true } }
            @{ Label = 'with a -GroupFilter'; Splat = @{ GroupFilter = "startswith(displayName,'role_')" } }
        ) {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-progress') -Include Groups @Splat | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter { $ProgressActivity -ceq 'Export-OERInventory' }
        }

        It 'asks for exactly the security-enabled filter without -GroupFilter' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-none') -Include Groups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -ceq 'securityEnabled eq true'
            }
        }

        It 'ANDs a -GroupFilter to the security-enabled filter, inside parentheses' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-given') -Include Groups -GroupFilter "startswith(displayName,'role_')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -ceq "securityEnabled eq true and (startswith(displayName,'role_'))"
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
        }

        It 'composes the same filter under -AllGroupsDetailed' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-all') -Include Groups -AllGroupsDetailed -GroupFilter "startswith(displayName,'role_')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                -not $RelevantOnly -and $Filter -ceq "securityEnabled eq true and (startswith(displayName,'role_'))"
            }
        }

        It 'passes the operator''s expression through unescaped, a quote doubled by the operator included (Review Focus 3)' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-quote') -Include Groups -GroupFilter "startswith(displayName,'O''Brien')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -ceq "securityEnabled eq true and (startswith(displayName,'O''Brien'))"
            }
        }

        It 'keeps an expression that closes the parenthesis exactly as typed, for the reader''s check to catch' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-widen') -Include Groups -GroupFilter 'x eq 1) or (securityEnabled eq false' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -ceq 'securityEnabled eq true and (x eq 1) or (securityEnabled eq false)' -and $SecurityEnabledOnly -eq $true
            }
        }

        It 'refuses -GroupFilter <Label> at parameter binding, and reads and signs in to nothing' -ForEach @(
            @{ Label = 'empty'; Value = ''; Message = 'The argument is null or empty' }
            @{ Label = '$null'; Value = $null; Message = 'The argument is null or empty' }
            @{ Label = 'one space'; Value = ' '; Message = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.' }
            @{ Label = 'three spaces'; Value = '   '; Message = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.' }
            @{ Label = 'a tab'; Value = "`t"; Message = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.' }
            @{ Label = 'a carriage return and a line feed'; Value = "`r`n"; Message = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.' }
        ) {
            $Caught = $null
            try {
                Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-filter-blank') -Include Groups -GroupFilter $Value -ErrorAction Stop | Out-Null
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Export-OERInventory'
            $Caught.Exception | Should -BeOfType [System.Management.Automation.ParameterBindingException]
            $Caught.Exception.GetType().Name | Should -BeExactly 'ParameterBindingValidationException'
            $Caught.Exception.Message | Should -BeLike "*$Message*"
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
            Test-Path (Join-Path $TestDrive 'ask-filter-blank') | Should -BeFalse
        }

        It 'does not read groups at all when -Include does not name Groups' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'ask-none') -Include AdministrativeUnits | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1
        }
    }

    Context 'end to end, through the transport' {
        # Only the sign-in and the transport are mocked (plus the profile read and the schema
        # self-check, which are not under test): the real group reader, the real Get-OERGroup and
        # the real collection, criterion and policy readers answer from one dispatcher, so every
        # request is counted and the document is what the real chain builds.
        BeforeAll {
            $script:E2EIdRa = '11111111-1111-1111-1111-111111111111'
            $script:E2EIdEl = '22222222-2222-2222-2222-222222222222'
            $script:E2EIdMod = '33333333-3333-3333-3333-333333333333'
            $script:E2EIdPlain = '44444444-4444-4444-4444-444444444444'
            $script:E2EIdSync = '55555555-5555-5555-5555-555555555555'
            $script:E2EIdDyn = '66666666-6666-6666-6666-666666666666'
            $script:E2EEligPrincipal = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            # The groups a test adds to the mixed tenant: a pair of names that differ only in letter
            # case, and a Microsoft 365 group (securityEnabled false) named like G-RA.
            $script:E2EIdDupRa = '77777777-7777-7777-7777-777777777777'
            $script:E2EIdDupPlain = '88888888-8888-8888-8888-888888888888'
            $script:E2EIdM365 = '99999999-9999-9999-9999-999999999999'

            # The mixed fixture tenant, in list order (the same set as Get-OERInventoryGroup.Tests.ps1).
            # Every group is security-enabled, so the security-enabled filter keeps all of them (a
            # test adds a group marked NotSecurity where it needs one the filter leaves out).
            $script:E2ENewTenant = {
                @(
                    @{ Id = $script:E2EIdRa; Name = 'G-RA'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                        Member = 'person1@contoso.com'; Owner = 'person2@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdEl; Name = 'G-EL'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                        Member = 'person3@contoso.com'; Owner = 'person4@contoso.com'; Eligibility = @($script:E2EEligPrincipal); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdMod; Name = 'G-MOD'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                        Member = 'person5@contoso.com'; Owner = 'person6@contoso.com'; Eligibility = @(); Policy = 'Modified' }
                    @{ Id = $script:E2EIdPlain; Name = 'G-PLAIN'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                        Member = 'person7@contoso.com'; Owner = 'person8@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdSync; Name = 'G-SYNC'; RoleAssignable = $false; Synced = $true; Dynamic = $false
                        Member = 'person9@contoso.com'; Owner = 'person10@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdDyn; Name = 'G-DYN'; RoleAssignable = $false; Synced = $false; Dynamic = $true
                        Member = 'person11@contoso.com'; Owner = 'person12@contoso.com'; Eligibility = 'NotSupported'; Policy = 'NotSupported' }
                )
            }

            # Answers one request the way Microsoft Graph would for the fixture tenant, and records
            # it. $script:E2ERefuse holds '<kind>:<group id>' keys (members, owners, eligibility,
            # criterion) whose request is refused with the key's text. A request it has no answer for
            # throws, so an unexpected request fails the test.
            $script:E2EFakeGraph = {
                param([string]$Method, [string]$Uri, [hashtable]$Body, [string[]]$ExpectedErrorCode)
                $Verb = if ($Method) { $Method } else { 'GET' }
                $script:E2EGraphCalls.Add("$Verb $Uri")
                $GroupOf = { param([string]$Id) @($script:E2ETenant | Where-Object { $_.Id -eq $Id })[0] }
                $RefuseIfAsked = {
                    param([string]$Key)
                    if ($script:E2ERefuse.ContainsKey($Key)) {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($script:E2ERefuse[$Key]), 'TooManyRequests',
                            [System.Management.Automation.ErrorCategory]::LimitsExceeded, $Key)
                    }
                }
                $NotSupported = {
                    if ($ExpectedErrorCode -notcontains 'ResourceTypeNotSupported') {
                        throw "The fake tenant answers ResourceTypeNotSupported, which the request did not declare: $Verb $Uri"
                    }
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceTypeNotSupported'; StatusCode = 400; Message = 'ResourceTypeNotSupported'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                }

                if ($Verb -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds') {
                    return [PSCustomObject]@{ value = @(foreach ($PrincipalId in @($Body.ids)) { @{ id = $PrincipalId; userPrincipalName = 'person13@contoso.com' } }) }
                }
                if ($Uri.StartsWith('v1.0/groups?') -or $Uri -eq 'v1.0/groups') {
                    # The unfiltered roster read is refused under the key 'roster'.
                    if ($Uri -eq 'v1.0/groups') { & $RefuseIfAsked 'roster' }
                    # A group a test marks NotSecurity (a Microsoft 365 group) is left out of a listing
                    # that carries the security-enabled filter and kept by the unfiltered roster read.
                    $Listed = @($script:E2ETenant | Where-Object { -not ($Uri -like '*securityEnabled*' -and $_.NotSecurity) })
                    # A listing the operator's own expression chose (the filter was composed as
                    # 'securityEnabled eq true and (...)', so the encoded URI holds ' and (') answers the
                    # ids a test names in $script:E2EFilterAnswer, security-enabled or not: that is how a
                    # filter that closes the parenthesis widens the listing.
                    if ($null -ne $script:E2EFilterAnswer -and $Uri -like '*%20and%20%28*') {
                        $Listed = @($script:E2ETenant | Where-Object { $script:E2EFilterAnswer -contains $_.Id })
                    }
                    return [PSCustomObject]@{
                        value = @(foreach ($G in $Listed) {
                                $Row = @{
                                    id                            = $G.Id
                                    displayName                   = $G.Name
                                    description                   = "$($G.Name) team"
                                    mailNickname                  = $G.Name.Replace('-', '').ToLowerInvariant()
                                    securityEnabled               = -not $G.NotSecurity
                                    isAssignableToRole            = $G.RoleAssignable
                                    groupTypes                    = [string[]]@(if ($G.Dynamic) { 'DynamicMembership' })
                                    membershipRule                = $(if ($G.Dynamic) { 'user.department -eq "IT"' } else { $null })
                                    membershipRuleProcessingState = $(if ($G.Dynamic) { 'On' } else { $null })
                                    onPremisesSyncEnabled         = $(if ($G.Synced) { $true } else { $null })
                                }
                                # A group marks its own securityEnabled when a test needs a value the
                                # security-enabled filter would never answer with: a boolean, a text or null
                                # as given, or the property left out when the value is the text '<missing>'.
                                if ($G.ContainsKey('SecurityEnabled')) {
                                    if ($G.SecurityEnabled -is [string] -and $G.SecurityEnabled -ceq '<missing>') { $Row.Remove('securityEnabled') }
                                    else { $Row.securityEnabled = $G.SecurityEnabled }
                                }
                                $Row
                            })
                    }
                }
                if ($Uri -match '^v1\.0/groups/(?<Id>[^/]+)/(?<Rel>members|owners)(?<Typed>/microsoft\.graph\.servicePrincipal)?$') {
                    $Id = $Matches.Id
                    $Rel = $Matches.Rel
                    $Typed = [bool]$Matches.Typed
                    & $RefuseIfAsked "$($Rel):$Id"
                    if ($Typed) { return [PSCustomObject]@{ value = @() } }
                    $G = & $GroupOf $Id
                    # Member and Owner hold one name or a list of them (an empty list answers an
                    # empty collection), so a test can give a group any number of members.
                    $Upns = @(if ($Rel -eq 'members') { $G.Member } else { $G.Owner })
                    return [PSCustomObject]@{ value = @(foreach ($Upn in $Upns) { @{ id = "u-$Rel-$($G.Name)-$Upn"; displayName = $Upn; userPrincipalName = $Upn; '@odata.type' = '#microsoft.graph.user' } }) }
                }
                if ($Uri.StartsWith('beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?') -and $Uri -match "groupId eq '(?<Id>[^']*)'") {
                    $Id = $Matches.Id
                    & $RefuseIfAsked "eligibility:$Id"
                    $G = & $GroupOf $Id
                    if ($G.Eligibility -is [string]) { return (& $NotSupported) }
                    return [PSCustomObject]@{ value = @(foreach ($PrincipalId in @($G.Eligibility)) { @{ principalId = $PrincipalId; accessId = 'member'; startDateTime = $null; endDateTime = $null } }) }
                }
                if ($Uri.StartsWith('beta/policies/roleManagementPolicies?') -and $Uri -match "scopeId eq '(?<Id>[^']*)'") {
                    $Id = $Matches.Id
                    & $RefuseIfAsked "criterion:$Id"
                    $G = & $GroupOf $Id
                    if ($G.Policy -eq 'NotSupported') { return (& $NotSupported) }
                    $Modified = if ($G.Policy -eq 'Modified') { '2026-09-01T00:00:00Z' } else { $null }
                    return [PSCustomObject]@{
                        value = @(
                            @{ id = "Group_$($Id)_member"; lastModifiedDateTime = $Modified; lastModifiedBy = $null }
                            @{ id = "Group_$($Id)_owner"; lastModifiedDateTime = $null; lastModifiedBy = $null }
                        )
                    }
                }
                if ($Uri.StartsWith('beta/policies/roleManagementPolicyAssignments?') -and $Uri -match "scopeId eq '(?<Id>[^']*)'") {
                    $Id = $Matches.Id
                    $G = & $GroupOf $Id
                    if ($G.Policy -eq 'NotSupported') { return (& $NotSupported) }
                    return [PSCustomObject]@{
                        value = @(
                            @{ roleDefinitionId = 'member'; policyId = "Group_$($Id)_member" }
                            @{ roleDefinitionId = 'owner'; policyId = "Group_$($Id)_owner" }
                        )
                    }
                }
                if ($Uri -match '^beta/policies/roleManagementPolicies/Group_[^/]+/rules$') {
                    return [PSCustomObject]@{
                        value = @(
                            @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                            @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                        )
                    }
                }
                throw "The fake tenant has no answer for: $Verb $Uri"
            }

            # One group per line, each normalised the same way on both sides (a JSON round trip, then
            # compressed), sorted, so a difference in serialisation can neither hide a difference in
            # content nor fake one.
            function ConvertTo-GroupLine {
                param([object[]]$Group)
                @(foreach ($G in @($Group)) {
                        if ($null -eq $G) { continue }
                        ConvertTo-Json -InputObject (ConvertTo-Json -InputObject $G -Depth 12 | ConvertFrom-Json) -Depth 12 -Compress
                    }) | Sort-Object
            }

            # The rows of a written groupsRoster.json, and a name -> memberCount map of them (a null
            # count is kept as a null entry, so a test can tell a null from a missing row).
            function Read-E2ERoster {
                param([string]$BundlePath)
                @(Get-Content (Join-Path $BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
            }
            function ConvertTo-E2ECountMap {
                param([object[]]$Roster)
                $Map = @{}
                foreach ($Row in $Roster) { $Map[[string]$Row.displayName] = $Row.memberCount }
                $Map
            }

            # Today's selection, applied to the groups Get-OERInventory returns: the predicate the
            # export used on them before the reader decided relevance first.
            function Select-TodayRelevantGroup {
                param([object[]]$Group, [switch]$IncludeSyncedGroups)
                @($Group | Where-Object {
                        $null -ne $_ -and (
                            $_.roleAssignable -eq $true -or
                            @($_.eligibility | Where-Object { $null -ne $_ }).Count -gt 0 -or
                            ($_.PSObject.Properties.Name -contains 'pimPolicy') -or
                            ($IncludeSyncedGroups -and $_.onPremisesSynced -is [bool] -and $_.onPremisesSynced))
                    })
            }
        }

        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            $script:E2ETenant = & $script:E2ENewTenant
            $script:E2ERefuse = @{}
            $script:E2EFilterAnswer = $null
            $script:E2EGraphCalls = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                param([string]$Method, [string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
                & $script:E2EFakeGraph -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode
            }
        }

        It 'writes the same groups, with the same content, as the export did before it decided relevance first' {
            # The tenant also holds a pair of groups whose names differ only in letter case, one
            # relevant (role-assignable) and one not. The rule that leaves a shared name out lives in
            # two places -- the reader's -ExcludeSharedName and Get-OERInventory's own -- so the
            # oracle and the export are compared on the pair too: both must leave both groups out,
            # and both must report the name.
            $script:E2ETenant = @($script:E2ETenant) + @(
                @{ Id = $script:E2EIdDupRa; Name = 'G-DUP'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                    Member = 'person15@contoso.com'; Owner = 'person16@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                @{ Id = $script:E2EIdDupPlain; Name = 'g-dup'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                    Member = 'person17@contoso.com'; Owner = 'person18@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
            )
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-default') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
            $Written = @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).groups)
            @($Written | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')

            $OracleRead = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable OracleErr
            $Oracle = Select-TodayRelevantGroup -Group @($OracleRead.Groups)
            @($Oracle | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD') -Because 'Get-OERInventory leaves both groups of the shared name out'
            $Expected = @(ConvertTo-GroupLine -Group $Oracle)
            $Expected.Count | Should -Be 3
            @(ConvertTo-GroupLine -Group $Written) | Should -Be $Expected
            # Both name the shared name once, with the spelling of the first group, and nothing else.
            @($Bundle.IncompleteReads) | Should -Be @('groups/G-DUP')
            @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 1
            $OraclePartial = @($OracleErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $OraclePartial.Count | Should -Be 1
            $OraclePartial[0].Exception.Message | Should -Match 'groups/G-DUP'
        }

        It 'writes every group Get-OERInventory returns, with the same content, under -AllGroupsDetailed' {
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-all') -Include Groups -AllGroupsDetailed `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $Written = @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).groups)
            $Expected = @(ConvertTo-GroupLine -Group @((Get-OERInventory -Include Groups -ErrorAction SilentlyContinue).Groups))
            $Expected.Count | Should -Be 6
            @(ConvertTo-GroupLine -Group $Written) | Should -Be $Expected
        }

        It 'writes the same groups as before under -IncludeSyncedGroups, the synchronized one included' {
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-synced') -Include Groups -IncludeSyncedGroups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $Written = @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).groups)
            @($Written | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD', 'G-SYNC')
            $Oracle = Select-TodayRelevantGroup -Group @((Get-OERInventory -Include Groups -ErrorAction SilentlyContinue).Groups) -IncludeSyncedGroups
            @(ConvertTo-GroupLine -Group $Written) | Should -Be @(ConvertTo-GroupLine -Group $Oracle)
        }

        It 'costs a group it does not keep exactly two requests' {
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-cost') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*55555555-5555-5555-5555-555555555555*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*66666666-6666-6666-6666-666666666666*' }
            # The same group read in full under -AllGroupsDetailed costs six: the members and the
            # owners (two requests each), the eligibility and the criterion -- eight for it in all
            # across the two runs of this test.
            Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-cost-all') -Include Groups -AllGroupsDetailed `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 8 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
        }

        It 'puts an unread members collection of a kept group first in IncompleteReads, and its cause in the partial message' {
            $script:E2ERefuse["members:$script:E2EIdRa"] = 'Too many requests (429)'
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-members') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
            @($Bundle.IncompleteReads)[0] | Should -Be 'groups/G-RA/members'
            @($Bundle.IncompleteReads).Count | Should -Be 1
            $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
            $Partial.Count | Should -Be 1
            $Partial[0].Exception.Message | Should -BeLike '*Causes of the unread group reads: Could not read members for group 11111111-1111-1111-1111-111111111111: Too many requests (429). The Members property is omitted rather than reported as empty*'
            # The written document says the membership is unknown, not empty.
            $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
            $Raw | Should -Match '"members"\s*:\s*null'
        }

        It 'still writes the whole bundle under -ErrorAction Stop when a kept group''s members could not be read' {
            # The reader call carries no -ErrorAction pin of its own (it writes no error record), so
            # it runs under the caller's Stop. Every read inside it that can fail is caught where it
            # is made, so the only error the caller sees is the export's own trailing InventoryPartial.
            $script:E2ERefuse["members:$script:E2EIdRa"] = 'Too many requests (429)'
            $Root = Join-Path $TestDrive 'e2e-stop'
            $Caught = $null
            try {
                Export-OERInventory -OutputPath $Root -Include Groups -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
            } catch {
                $Caught = $PSItem
            }
            @(Get-ChildItem -Path $Root -Recurse -Filter 'inventory.json' -ErrorAction SilentlyContinue).Count | Should -Be 1
            @(Get-ChildItem -Path $Root -Recurse -Filter 'groupsRoster.json' -ErrorAction SilentlyContinue).Count | Should -Be 1
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'InventoryPartial,Export-OERInventory'
            $Caught.Exception.Message | Should -Match 'groups/G-RA/members'
        }

        It 'gives one cause for two kept groups whose members failed the same way' {
            $script:E2ERefuse["members:$script:E2EIdRa"] = 'Too many requests (429)'
            $script:E2ERefuse["members:$script:E2EIdEl"] = 'Too many requests (429)'
            $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'e2e-members-two') -Include Groups `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
            @($Bundle.IncompleteReads)[0] | Should -Be 'groups/G-RA/members, groups/G-EL/members'
            $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
            $Partial.Count | Should -Be 1
            $Partial[0].Exception.Message | Should -BeLike '*Causes of the unread group reads: Could not read members for group*'
            [regex]::Matches($Partial[0].Exception.Message, 'Could not read members for group').Count | Should -Be 1
        }

        Context 'the roster''s member count (R3)' {
            # groupsRoster.json lists every group in the tenant, but a count is written only for a
            # group the export read in full: counting the others would cost a request per group, and
            # the one-request count (members/$count) needs a header the module's transport never
            # sends, answers from an index that can lag, and is not measured for service principals.
            # So the others get null, the roster's existing "not known" value.
            BeforeEach {
                # Counts that tell the rows apart: G-RA two members, G-MOD none (a real zero),
                # G-PLAIN three (a group the export does not keep, so its count shows whether it was read).
                $Fixture = @{}
                foreach ($Group in $script:E2ETenant) { $Fixture[$Group.Name] = $Group }
                $Fixture['G-RA'].Member = @('person1@contoso.com', 'person19@contoso.com')
                $Fixture['G-MOD'].Member = @()
                $Fixture['G-PLAIN'].Member = @('person7@contoso.com', 'person20@contoso.com', 'person21@contoso.com')
            }

            It 'gives a group the export read in full its member count, a count of zero included' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-kept') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                # Non-vacuity: every group of the tenant has a row.
                $Roster.Count | Should -Be 6
                $Counts = ConvertTo-E2ECountMap -Roster $Roster
                $Counts['G-RA'] | Should -Be 2
                $Counts['G-EL'] | Should -Be 1
                $null -ne $Counts['G-MOD'] | Should -BeTrue -Because 'a membership read and found empty is a count of zero, not an unknown one'
                $Counts['G-MOD'] | Should -Be 0
                # The kept groups are the ones the document holds, so the count is the document's own.
                $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
                @($Inv.groups | Where-Object { $_.displayName -eq 'G-RA' })[0].members.Count | Should -Be 2
            }

            It 'writes memberCount null, the key present, for a group the export did not read in full' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-null') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                $Counts = ConvertTo-E2ECountMap -Roster $Roster
                foreach ($NotKept in @('G-PLAIN', 'G-SYNC', 'G-DYN')) {
                    $Counts.ContainsKey($NotKept) | Should -BeTrue -Because "$NotKept has a row in the roster"
                    $Row = @($Roster | Where-Object { $_.displayName -eq $NotKept })[0]
                    $Row.PSObject.Properties.Name | Should -Contain 'memberCount' -Because "the key is written as null for $NotKept, never left out"
                    $null -eq $Row.memberCount | Should -BeTrue -Because "$NotKept was not read in full"
                }
                [regex]::Matches((Get-Content (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw), '"memberCount"\s*:\s*null').Count | Should -Be 3
                # Reach proofs: the null is a count nobody took, not a read that failed. G-PLAIN cost
                # its two requests (eligibility and the criterion) and its members were never asked for.
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 0 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444/members*' }
                # A count that was not taken is not a gap in the export.
                @($Bundle.IncompleteReads).Count | Should -Be 0
                @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
            }

            It 'gives a group whose relevance could not be read its full count (R2), and reports the gap' {
                $script:E2ERefuse["eligibility:$script:E2EIdPlain"] = 'Too many requests (429)'
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-undecided') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr
                # Reach proof: the refusal was served, and the group was then read in full.
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/44444444-4444-4444-4444-444444444444/members' }
                $Counts = ConvertTo-E2ECountMap -Roster (Read-E2ERoster -BundlePath $Bundle.BundlePath)
                $Counts['G-PLAIN'] | Should -Be 3
                $Counts['G-RA'] | Should -Be 2
                $Counts['G-SYNC'] | Should -BeNullOrEmpty
                # It is still not a kept group: the document is what it was.
                $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
                @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
                @($Bundle.IncompleteReads).Count | Should -Be 1
                @($Bundle.IncompleteReads)[0] | Should -Match 'G-PLAIN'
            }

            It 'gives every security group its member count under -AllGroupsDetailed' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-all') -Include Groups -AllGroupsDetailed `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                $Roster.Count | Should -Be 6
                $Counts = ConvertTo-E2ECountMap -Roster $Roster
                $Counts['G-RA'] | Should -Be 2
                $Counts['G-EL'] | Should -Be 1
                $Counts['G-MOD'] | Should -Be 0
                $Counts['G-PLAIN'] | Should -Be 3
                $Counts['G-SYNC'] | Should -Be 1
                $Counts['G-DYN'] | Should -Be 1
                @($Roster | Where-Object { $null -eq $_.memberCount }).Count | Should -Be 0
            }

            It 'gives a group left out for a shared name a null count, in both modes' {
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdDupRa; Name = 'G-DUP'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                        Member = @('person22@contoso.com', 'person23@contoso.com'); Owner = 'person24@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdDupPlain; Name = 'g-dup'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                        Member = 'person25@contoso.com'; Owner = 'person26@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                foreach ($Mode in @(@{ Name = 'default'; Detailed = $false }, @{ Name = 'all'; Detailed = $true })) {
                    $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive "roster-dup-$($Mode.Name)") -Include Groups `
                        -AllGroupsDetailed:$Mode.Detailed -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                    # Non-vacuity: the pair is in the roster, and the group beside it still has its count.
                    $Roster.Count | Should -Be 8
                    $Counts = ConvertTo-E2ECountMap -Roster $Roster
                    $Counts['G-RA'] | Should -Be 2 -Because "the mode is $($Mode.Name)"
                    foreach ($Row in @($Roster | Where-Object { $_.displayName -like 'g-dup' })) {
                        $null -eq $Row.memberCount | Should -BeTrue -Because "$($Row.displayName) shares its name, in the $($Mode.Name) mode"
                    }
                    @($Roster | Where-Object { $_.displayName -like 'g-dup' }).Count | Should -Be 2
                }
            }

            It 'gives neither group a count when a Microsoft 365 group shares a security group''s name, since the security group is left out (BL-131)' {
                # The security-enabled listing never holds the Microsoft 365 group, so the export did not
                # read it, and a name is no key: it is never counted as the security group that shares its
                # name. Since BL-131 the names are counted over the roster, so the security group shares
                # its name too: it is left out of inventory.json, and a group left out for a shared name
                # has no count either.
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'G-RA'; RoleAssignable = $false; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'roster-m365') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                $Roster.Count | Should -Be 7
                $Twins = @($Roster | Where-Object { $_.displayName -eq 'G-RA' })
                $Twins.Count | Should -Be 2
                @($Twins | Where-Object { $null -eq $_.memberCount }).Count | Should -Be 2 -Because 'neither group is written to inventory.json'
                # Non-vacuity: the group beside them keeps its count, and the security group is named.
                (ConvertTo-E2ECountMap -Roster $Roster)['G-EL'] | Should -Be 1
                @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).groups | ForEach-Object { $_.displayName }) |
                    Should -Not -Contain 'G-RA'
                @($Bundle.IncompleteReads) | Should -Be @('groups/G-RA')
            }
        }

        Context 'names two or more objects share (BL-131)' {
            # The names are counted over the roster, every group in the tenant, which the export reads
            # before the group reader. Every object of a shared name is left out of inventory.json and
            # the per-area files, the export writes ONE warning before the bundle, and README.md lists
            # each name with its count and section.
            BeforeAll {
                $script:SharedHeading = '## Names two or more objects share'
                function Get-E2ESharedBullets {
                    param([string]$BundlePath)
                    $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
                    $Start = $Readme.IndexOf($script:SharedHeading)
                    $Start | Should -BeGreaterOrEqual 0 -Because 'README.md carries the section'
                    $Section = $Readme.Substring($Start, $Readme.IndexOf("`n## ", $Start) - $Start)
                    @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
                }
                function Get-E2ESharedWarning {
                    param([object[]]$Warning)
                    @($Warning | Where-Object { "$_" -like 'Export-OERInventory: left out of inventory.json and the per-area files every object whose name*' } | ForEach-Object { "$_" })
                }
                function Get-E2EGroupFileName {
                    param([string]$BundlePath, [string]$File)
                    $Data = Get-Content (Join-Path $BundlePath $File) -Raw | ConvertFrom-Json
                    if ($File -eq 'inventory.json') { $Data = $Data.groups }
                    @($Data | ForEach-Object { $_.displayName })
                }
                $script:SharedWarningText = "Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares, since the apply engine refuses an ambiguous name: {0} name(s), carried by {1} object(s) in all. README.md lists each name, how many objects carry it and its section under 'Names two or more objects share'."
            }

            It 'leaves out two security groups of one name, names it in README.md with its count, and warns once' {
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdDupRa; Name = 'G-DUP'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                        Member = 'person15@contoso.com'; Owner = 'person16@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                    @{ Id = $script:E2EIdDupPlain; Name = 'g-dup'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                        Member = 'person17@contoso.com'; Owner = 'person18@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'shared-two-security') -Include Groups `
                    -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
                foreach ($File in 'inventory.json', 'groups.json') {
                    Get-E2EGroupFileName -BundlePath $Bundle.BundlePath -File $File | Should -Be @('G-RA', 'G-EL', 'G-MOD') -Because "$File leaves both out"
                }
                ((Get-E2ESharedBullets -BundlePath $Bundle.BundlePath) -join "`n") | Should -BeExactly '- `G-DUP` -- 2 objects, section `groups`'
                $Shared = @(Get-E2ESharedWarning -Warning $Warn)
                $Shared.Count | Should -Be 1
                $Shared[0] | Should -BeExactly ($script:SharedWarningText -f 1, 2)
                @($Bundle.IncompleteReads) | Should -Be @('groups/G-DUP')
            }

            It 'leaves out a security group a Microsoft 365 group in the roster shares its name with, and names it with its count' {
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'g-ra'; RoleAssignable = $false; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'shared-m365') -Include Groups `
                    -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue -ErrorVariable ExErr
                foreach ($File in 'inventory.json', 'groups.json') {
                    Get-E2EGroupFileName -BundlePath $Bundle.BundlePath -File $File | Should -Be @('G-EL', 'G-MOD') -Because "$File leaves G-RA out"
                }
                ((Get-E2ESharedBullets -BundlePath $Bundle.BundlePath) -join "`n") | Should -BeExactly '- `G-RA` -- 2 objects, section `groups`'
                $Shared = @(Get-E2ESharedWarning -Warning $Warn)
                $Shared.Count | Should -Be 1
                $Shared[0] | Should -BeExactly ($script:SharedWarningText -f 1, 2)
                @($Bundle.IncompleteReads) | Should -Be @('groups/G-RA')
                $Partial = @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
                $Partial.Count | Should -Be 1
                $Partial[0].Exception.Message | Should -BeLike '*2 live objects share the name groups/G-RA (compared without regard to letter case)*'
                # Reach proof: the Microsoft 365 group is in the roster, and was never read itself.
                @(Read-E2ERoster -BundlePath $Bundle.BundlePath | Where-Object { $_.id -eq $script:E2EIdM365 }).Count | Should -Be 1
                @($script:E2EGraphCalls | Where-Object { $_ -like "*$($script:E2EIdM365)*" }).Count | Should -Be 0
            }

            It 'writes every group of a unique name as before, says so in README.md, and writes no such warning' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'shared-none') -Include Groups `
                    -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
                Get-E2EGroupFileName -BundlePath $Bundle.BundlePath -File 'inventory.json' | Should -Be @('G-RA', 'G-EL', 'G-MOD')
                @(Get-E2ESharedBullets -BundlePath $Bundle.BundlePath).Count | Should -Be 0
                (Get-Content (Join-Path $Bundle.BundlePath 'README.md') -Raw) | Should -Match ([regex]::Escape('None. No two objects this export read share a name.'))
                (Get-E2ESharedWarning -Warning $Warn).Count | Should -Be 0
                @($Bundle.IncompleteReads).Count | Should -Be 0
            }

            It 'writes the warning under -WhatIf too, and writes nothing to disk' {
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'G-RA'; RoleAssignable = $false; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $Root = Join-Path $TestDrive 'shared-whatif'
                $Bundle = Export-OERInventory -OutputPath $Root -Include Groups -WhatIf `
                    -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
                $Shared = @(Get-E2ESharedWarning -Warning $Warn)
                $Shared.Count | Should -Be 1
                $Shared[0] | Should -BeExactly ($script:SharedWarningText -f 1, 2)
                Test-Path $Root | Should -BeFalse
                @($Bundle.Files) | Should -Contain 'README.md'
            }

            It 'reads the roster before the group listing' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'shared-order') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $Calls = @($script:E2EGraphCalls)
                $Roster = [array]::IndexOf($Calls, 'GET v1.0/groups')
                $Listing = [array]::IndexOf($Calls, 'GET v1.0/groups?$filter=securityEnabled%20eq%20true')
                $Roster | Should -BeGreaterOrEqual 0
                $Listing | Should -BeGreaterThan $Roster
                # The index is built from the roster: no listing of every group's name is sent.
                @($Calls | Where-Object { $_ -like 'GET v1.0/groups?$select=*' }).Count | Should -Be 0
                $Bundle.RosterCount | Should -Be 6
            }
        }

        Context '-GroupFilter narrows the listing and never widens the document (A13)' {
            # The listing request, the way Get-OERGroup -Filter spells it: the whole expression
            # percent-encoded ONCE. Written out here, not computed, so a filter that was escaped twice
            # (%2527 for a quote) or not at all cannot agree with its own expectation.
            BeforeAll {
                $script:SecurityOnlyListing = 'GET v1.0/groups?$filter=securityEnabled%20eq%20true'
                $script:RoleFilterListing = 'GET v1.0/groups?$filter=securityEnabled%20eq%20true%20and%20%28startswith%28displayName%2C%27G-%27%29%29'
                $script:QuoteFilterListing = 'GET v1.0/groups?$filter=securityEnabled%20eq%20true%20and%20%28startswith%28displayName%2C%27O%27%27Brien%27%29%29'
                $script:WidenedFilterListing = 'GET v1.0/groups?$filter=securityEnabled%20eq%20true%20and%20%28x%20eq%201%29%20or%20%28securityEnabled%20eq%20false%29'
                $script:WidenedFilter = 'x eq 1) or (securityEnabled eq false'
                $script:LeftOutWarning = '-GroupFilter returned {0} group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
                function Get-E2EListingCall {
                    param([string]$Exactly)
                    @($script:E2EGraphCalls | Where-Object { $_ -ceq $Exactly }).Count
                }
                function Get-E2EWrittenGroupName {
                    param([string]$BundlePath)
                    @((Get-Content (Join-Path $BundlePath 'inventory.json') -Raw | ConvertFrom-Json).groups | ForEach-Object { $_.displayName })
                }
            }

            It 'lists the groups with exactly the security-enabled filter when no -GroupFilter is given' {
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-none') -Include Groups `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable Warn
                Get-E2EListingCall -Exactly $script:SecurityOnlyListing | Should -Be 1
                @($script:E2EGraphCalls | Where-Object { $_ -like 'GET v1.0/groups[?]*' }).Count | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('G-RA', 'G-EL', 'G-MOD')
                @($Warn | Where-Object { "$_" -like '-GroupFilter returned*' }).Count | Should -Be 0
            }

            It 'sends the operator''s expression ANDed to the security-enabled filter, in parentheses, encoded once, and lists the roster unfiltered' {
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdEl)
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-role') -Include Groups -GroupFilter "startswith(displayName,'G-')" `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr -WarningVariable Warn
                Get-E2EListingCall -Exactly $script:RoleFilterListing | Should -Be 1
                # The security-enabled listing alone was not sent as well: one filtered listing, then the roster.
                @($script:E2EGraphCalls | Where-Object { $_ -like 'GET v1.0/groups[?]*' }).Count | Should -Be 1
                Get-E2EListingCall -Exactly 'GET v1.0/groups' | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('G-RA', 'G-EL')
                # The roster is read without the filter and still lists every group of the tenant.
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                $Roster.Count | Should -Be 6
                $Bundle.RosterCount | Should -Be 6
                @($Roster | Where-Object { $_.displayName -eq 'G-MOD' }).Count | Should -Be 1 -Because 'the filter narrows inventory.json, not the roster'
                @($Warn | Where-Object { "$_" -like '-GroupFilter returned*' }).Count | Should -Be 0
                @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
            }

            It 'carries a quote the operator doubled through to the listing request, percent-encoded once (Review Focus 3)' {
                $script:E2EFilterAnswer = @($script:E2EIdRa)
                $null = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-quote') -Include Groups -GroupFilter "startswith(displayName,'O''Brien')" `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                Get-E2EListingCall -Exactly $script:QuoteFilterListing | Should -Be 1
                @($script:E2EGraphCalls | Where-Object { $_ -like '*%25*' }).Count | Should -Be 0 -Because 'a request that holds %25 was percent-encoded twice'
            }

            It 'reads the groups it keeps in full under -AllGroupsDetailed with a -GroupFilter' {
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdPlain)
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-all') -Include Groups -AllGroupsDetailed -GroupFilter "startswith(displayName,'G-')" `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                Get-E2EListingCall -Exactly $script:RoleFilterListing | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('G-RA', 'G-PLAIN')
            }

            It 'leaves a group the filter widened to out of the document, unread, with ONE warning, and keeps it in the roster' {
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'G-M365'; RoleAssignable = $true; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @($script:E2EEligPrincipal); Policy = 'Modified' }
                )
                # The widened filter answers the security group and the Microsoft 365 group, which is
                # role-assignable, eligible and modified: relevant on every count, were it kept.
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdM365)
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-widened') -Include Groups -GroupFilter $script:WidenedFilter `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr -WarningVariable Warn
                # Reach proof: the widened listing was sent, and answered the Microsoft 365 group.
                Get-E2EListingCall -Exactly $script:WidenedFilterListing | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('G-RA')
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*99999999-9999-9999-9999-999999999999*' }
                $Raw = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
                $Raw | Should -Not -Match 'G-M365'
                (Get-Content (Join-Path $Bundle.BundlePath 'groups.json') -Raw) | Should -Not -Match 'G-M365'
                $Left = @($Warn | Where-Object { "$_" -like '-GroupFilter returned*' })
                $Left.Count | Should -Be 1
                "$($Left[0])" | Should -BeExactly ($script:LeftOutWarning -f 1)
                # A group the document is not meant to hold is not a gap in it.
                @($Bundle.IncompleteReads).Count | Should -Be 0
                @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
                # The roster is read unfiltered, so it still names the group, with no count taken.
                $Roster = Read-E2ERoster -BundlePath $Bundle.BundlePath
                $Roster.Count | Should -Be 7
                $Row = @($Roster | Where-Object { $_.displayName -eq 'G-M365' })
                $Row.Count | Should -Be 1
                $null -eq $Row[0].memberCount | Should -BeTrue -Because 'the group was not read, so no count was taken'
            }

            It 'leaves a group out whose securityEnabled is missing, null or not a boolean, and counts each in the one warning' {
                $Fixture = @{}
                foreach ($Group in $script:E2ETenant) { $Fixture[$Group.Name] = $Group }
                $Fixture['G-EL'].SecurityEnabled = '<missing>'
                $Fixture['G-MOD'].SecurityEnabled = 'true'
                $Fixture['G-PLAIN'].SecurityEnabled = $null
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdEl, $script:E2EIdMod, $script:E2EIdPlain)
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-notbool') -Include Groups -GroupFilter $script:WidenedFilter `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable Warn
                Get-E2EListingCall -Exactly $script:WidenedFilterListing | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('G-RA')
                $Left = @($Warn | Where-Object { "$_" -like '-GroupFilter returned*' })
                $Left.Count | Should -Be 1
                "$($Left[0])" | Should -BeExactly ($script:LeftOutWarning -f 3)
                # Left out before the relevance decision: not even the two requests a plain group costs.
                foreach ($LeftOutId in @($script:E2EIdEl, $script:E2EIdMod, $script:E2EIdPlain)) {
                    @($script:E2EGraphCalls | Where-Object { $_ -like "*$LeftOutId*" }).Count | Should -Be 0
                }
            }

            It 'leaves out the security group of a shared name when its namesake is one the filter widened to, since the roster counts it (BL-131)' {
                # Ruling 1 counted the names over the security-enabled listing alone, so a namesake the
                # filter widened to (and the reader dropped) did not make the name shared. BL-131 counts
                # them over every group in the tenant, the roster, where the namesake is listed: the
                # apply engine refuses the name either way.
                $Fixture = @{}
                foreach ($Group in $script:E2ETenant) { $Fixture[$Group.Name] = $Group }
                $Fixture['G-RA'].Name = 'Admins'
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'admins'; RoleAssignable = $false; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdM365)
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-shared') -Include Groups -GroupFilter $script:WidenedFilter `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr -WarningVariable Warn
                Get-E2EListingCall -Exactly $script:WidenedFilterListing | Should -Be 1
                @(Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath).Count | Should -Be 0
                @($Bundle.IncompleteReads) | Should -Be @('groups/Admins')
                @($ExErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 1
                @($Warn | Where-Object { "$_" -like '-GroupFilter returned*' }).Count | Should -Be 1
                @($Warn | Where-Object { "$_" -like '*1 name(s), carried by 2 object(s) in all*' }).Count | Should -Be 1
            }

            It 'keeps the security group of a shared name when the roster could not be read, counting over the security-enabled listing (ruling 1)' {
                # Without the roster the reader gets no index and counts over its own listing, where the
                # namesake the filter widened to is out of scope, so the name is not shared.
                $Fixture = @{}
                foreach ($Group in $script:E2ETenant) { $Fixture[$Group.Name] = $Group }
                $Fixture['G-RA'].Name = 'Admins'
                $script:E2ETenant = @($script:E2ETenant) + @(
                    @{ Id = $script:E2EIdM365; Name = 'admins'; RoleAssignable = $false; Synced = $false; Dynamic = $false; NotSecurity = $true
                        Member = 'person27@contoso.com'; Owner = 'person28@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                )
                $script:E2EFilterAnswer = @($script:E2EIdRa, $script:E2EIdM365)
                $script:E2ERefuse['roster'] = 'Insufficient privileges to complete the operation.'
                $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'gf-shared-noroster') -Include Groups -GroupFilter $script:WidenedFilter `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable ExErr -WarningVariable Warn
                Get-E2EListingCall -Exactly 'GET v1.0/groups' | Should -Be 1
                Get-E2EWrittenGroupName -BundlePath $Bundle.BundlePath | Should -Be @('Admins')
                @($Bundle.IncompleteReads) | Should -Be @('groupsRoster') -Because 'the namesake is out of scope of the listing, so the name is not shared'
                @($Warn | Where-Object { "$_" -like '*Could not read the group roster*' }).Count | Should -Be 1
                @($Warn | Where-Object { "$_" -like '*carried by*object(s) in all*' }).Count | Should -Be 0
            }

        }
    }
}

Describe 'Export-OERInventory (-GroupFilter: the warning for a group left out stands before the confirmation gate)' {
    # The warning is written by the group reader, which runs before the export's ShouldProcess, so
    # -WhatIf and a -Confirm prompt both show it first. The 'What if:' line and the prompt go straight
    # to the host, so the order is read from the answering host (tests/Unit/TestHelpers/
    # OERConfirmHost.ps1), in a runspace whose copy of the module has its sign-in and transport
    # replaced (a Pester mock does not cross the boundary). The list answers ONE group that is not
    # security-enabled, the way a filter that closes its parenthesis can, so nothing else is read.
    BeforeAll {
        $script:GateScenario = {
            param([string]$OutputPath)
            $Text = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    $script:GateCalls = [System.Collections.Generic.List[string]]::new()
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Get-OERConfiguration -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $script:GateCalls.Add("$Method $Uri")
        if ($Uri.StartsWith('v1.0/groups')) {
            return [pscustomobject]@{ value = @(@{ id = '99999999-9999-9999-9999-999999999999'; displayName = 'G-M365'; securityEnabled = $false; isAssignableToRole = $false; groupTypes = [string[]]@() }) }
        }
        throw "The fake tenant has no answer for: $Method $Uri"
    }
}
$Host.UI.WriteLine('PHASE: WhatIf')
Export-OERInventory -OutputPath '#OUTPUT#' -Include Groups -GroupFilter 'x eq 1) or (securityEnabled eq false' -WhatIf | Out-Null
"WHATIF-CALLS:$(& $Module { @($script:GateCalls) -join ';' })"
& $Module { $script:GateCalls.Clear() }
$Host.UI.WriteLine('PHASE: Confirm')
Export-OERInventory -OutputPath '#OUTPUT#' -Include Groups -GroupFilter 'x eq 1) or (securityEnabled eq false' -Confirm | Out-Null
"CONFIRM-CALLS:$(& $Module { @($script:GateCalls) -join ';' })"
'END'
'@
            [scriptblock]::Create($Text.Replace('#OUTPUT#', $OutputPath))
        }
        # The events of one phase: from that phase's marker line to the next marker (or the end).
        function Get-GatePhaseEvent {
            param([string[]]$Events, [string]$Phase)
            $Start = [array]::IndexOf($Events, "Line: PHASE: $Phase")
            if ($Start -lt 0) { return }
            for ($Index = $Start + 1; $Index -lt $Events.Count; $Index++) {
                if ($Events[$Index] -like 'Line: PHASE: *') { break }
                $Events[$Index]
            }
        }
        $script:GateOutput = Join-Path $TestDrive 'gate-bundle'
        $script:GateRun = Invoke-OERWithConfirmAnswer -Answer '&No' -Script (& $script:GateScenario -OutputPath $script:GateOutput)
        $script:GateWarning = 'Warning: -GroupFilter returned 1 group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
    }

    It 'reaches the end of the scenario with no error, and the list was sent with the composed filter' {
        @($script:GateRun.Output) | Should -Contain 'END'
        @($script:GateRun.Errors) | Should -BeNullOrEmpty
        foreach ($Prefix in 'WHATIF-CALLS:', 'CONFIRM-CALLS:') {
            $Line = [string](@($script:GateRun.Output | Where-Object { [string]$_ -like "$Prefix*" })[0])
            # BL-131: the roster (every group in the tenant) is read first, since the group reader
            # counts the names groups share over it; the filtered listing follows.
            $Line | Should -BeExactly ($Prefix + 'GET v1.0/groups;GET v1.0/groups?$filter=securityEnabled%20eq%20true%20and%20%28x%20eq%201%29%20or%20%28securityEnabled%20eq%20false%29')
        }
    }

    It 'under -WhatIf writes the warning once, before the What if: line' {
        $Events = @(Get-GatePhaseEvent -Events $script:GateRun.Events -Phase 'WhatIf')
        $WhatIf = [array]::FindIndex([string[]]$Events, [Predicate[string]] { param($E) $E -like 'Line: What if: *' })
        $WhatIf | Should -BeGreaterOrEqual 0 -Because 'the cmdlet must reach its gate, so the missing warning below is not a cmdlet that stopped early'
        @($Events | Where-Object { $_ -ceq $script:GateWarning }).Count | Should -Be 1
        [array]::IndexOf([string[]]$Events, $script:GateWarning) | Should -BeLessThan $WhatIf
    }

    It 'under -Confirm answered No writes the warning once, before the prompt, and writes no bundle' {
        $Events = @(Get-GatePhaseEvent -Events $script:GateRun.Events -Phase 'Confirm')
        $Prompt = [array]::FindIndex([string[]]$Events, [Predicate[string]] { param($E) $E -like 'Prompt: *' })
        $Prompt | Should -BeGreaterOrEqual 0 -Because 'the cmdlet must reach its prompt, so the missing warning below is not a cmdlet that stopped early'
        @($Events | Where-Object { $_ -ceq $script:GateWarning }).Count | Should -Be 1
        [array]::IndexOf([string[]]$Events, $script:GateWarning) | Should -BeLessThan $Prompt
        Test-Path $script:GateOutput | Should -BeFalse
    }
}

Describe 'Export-OERInventory (names two or more objects share, BL-131)' {
    # BL-131 (R-2, R-3). The export reads its roster (every group in the tenant) before the group
    # reader and hands the reader the index of every group's name built from it, so a security group
    # that shares its name with a Microsoft 365 or distribution group is left out like two security
    # groups that share it. The names the reader left out, followed by the ones Get-OERInventory hands
    # over in its information records tagged Omnicit.EntraRBAC.SharedName, go into ONE warning before
    # the bundle and into README.md. The reader and Get-OERInventory are mocked here; the real reader
    # is driven through the transport in the Context 'names two or more objects share (BL-131)' above.
    # No id below is version-4 shaped.
    BeforeAll {
        # Writes an information record the way the real Get-OERInventory does, from inside the module,
        # so the preferences of the call it stands in for govern it exactly as they govern the real one.
        function script:Write-AsGetOERInventoryRecord {
            param([object]$Notice, [string]$Tag)
            & (Get-Module $script:moduleName) {
                param($Notice, $Tag)
                Microsoft.PowerShell.Utility\Write-Information -MessageData $Notice -Tags $Tag
            } $Notice $Tag
        }
        function script:New-SnNotice {
            param([object[]]$Names)
            $Notice = [PSCustomObject]@{ Names = @($Names) }
            $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.SharedNameNotice')
            $Notice
        }
        function script:New-SnName {
            param([string]$Section, [string]$Name, [int]$Count)
            [PSCustomObject]@{ Section = $Section; Name = $Name; Count = $Count }
        }
        $script:SnHeading = '## Names two or more objects share'
        function script:Get-SnBullets {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:SnHeading)
            $Section = $Readme.Substring($Start, $Readme.IndexOf("`n## ", $Start) - $Start)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        $script:SnWarningText = "Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares, since the apply engine refuses an ambiguous name: {0} name(s), carried by {1} object(s) in all. README.md lists each name, how many objects carry it and its section under 'Names two or more objects share'."
        $script:SnSec1 = 'ffff1111-0000-0000-0000-000000000001'
        $script:SnM365 = 'ffff1111-0000-0000-0000-0000000000a1'
        $script:FailRosterReadSn = {
            [CmdletBinding()] param([switch]$All)
            $script:SnOrder.Add('roster')
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        $script:SnOrder = [System.Collections.Generic.List[string]]::new()
        # The roster: a security group and a Microsoft 365 group that carries its name.
        $script:SnRoster = @(
            [PSCustomObject]@{ Id = $script:SnSec1; DisplayName = 'Admins'; SecurityEnabled = $true; MailEnabled = $false; GroupTypes = @(); GroupType = 'Assigned'; IsAssignableToRole = $true }
            [PSCustomObject]@{ Id = $script:SnM365; DisplayName = 'ADMINS'; SecurityEnabled = $false; MailEnabled = $true; GroupTypes = @('Unified'); GroupType = 'Assigned'; IsAssignableToRole = $false }
        )
        Mock -ModuleName $script:moduleName Get-OERGroup {
            $script:SnOrder.Add('roster')
            $script:SnRoster
        }
        $script:SnReaderShared = @()
        $script:SnReaderUnread = @()
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            $script:SnOrder.Add('reader')
            [PSCustomObject]@{ Groups = @(); Unread = @($script:SnReaderUnread); Causes = @(); PimLeftOut = @(); SharedNames = @($script:SnReaderShared) }
        }
        # The records the Entra ID Get-OERInventory call writes: a list of @{ Notice; Tag }.
        $script:SnInventoryRecords = @()
        $script:SnInventoryPartial = $null
        Mock -ModuleName $script:moduleName Get-OERInventory {
            [CmdletBinding()] param($Include)
            foreach ($Record in @($script:SnInventoryRecords)) { Write-AsGetOERInventoryRecord -Notice $Record.Notice -Tag $Record.Tag }
            if ($script:SnInventoryPartial) {
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('This inventory is PARTIAL'), 'InventoryPartial',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $script:SnInventoryPartial))
            }
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
    }

    It 'reads the roster before the group reader, and hands the reader the index built from it' {
        $null = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sn-order') -Include Groups -WarningAction SilentlyContinue
        @($script:SnOrder) | Should -Be @('roster', 'reader')
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Exactly -Times 1 -ParameterFilter { $All }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter {
            $null -ne $GroupNameIndex -and $GroupNameIndex.Read -eq $true -and
            $GroupNameIndex.IdsByName['admins'].Count -eq 2 -and @($GroupNameIndex.IdsByName.Keys).Count -eq 1
        }
    }

    It 'hands the reader no index when the roster could not be read, and still names groupsRoster after every Get-OERInventory entry' {
        Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:FailRosterReadSn
        $script:SnReaderUnread = @('groups/Admins/members')
        $script:SnInventoryPartial = 'administrativeUnits'
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sn-noroster') -Include Groups, AdministrativeUnits `
            -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
        @($script:SnOrder) | Should -Be @('roster', 'reader')
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1 -ParameterFilter { $null -eq $GroupNameIndex }
        # The entry keeps its place: the group reader's, then Get-OERInventory's, then the roster's.
        @($Bundle.IncompleteReads) | Should -Be @('groups/Admins/members', 'administrativeUnits', 'groupsRoster')
        # The roster warning is written before the reader runs, so it stands before the bundle's gate.
        @($Warn | Where-Object { "$_" -like 'Could not read the group roster*' }).Count | Should -Be 1
    }

    It 'joins the reader''s names and the ones Get-OERInventory handed over, in that order, in one warning and in README.md' {
        $script:SnReaderShared = @(New-SnName -Section 'groups' -Name 'Admins' -Count 2)
        $script:SnInventoryRecords = @(
            @{ Tag = 'Omnicit.EntraRBAC.SharedName'; Notice = (New-SnNotice -Names @(
                        (New-SnName -Section 'administrativeUnits' -Name 'Team' -Count 2)
                        (New-SnName -Section 'accessPackages' -Name 'Catalog One/Package' -Count 3)
                    )) }
        )
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sn-join') -Include Groups, AdministrativeUnits, AccessPackages `
            -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
        $Shared = @($Warn | Where-Object { "$_" -like 'Export-OERInventory: left out of inventory.json and the per-area files*' } | ForEach-Object { "$_" })
        $Shared.Count | Should -Be 1
        $Shared[0] | Should -BeExactly ($script:SnWarningText -f 3, 7)
        ((Get-SnBullets -BundlePath $Bundle.BundlePath) -join "`n") | Should -BeExactly (@(
                '- `Admins` -- 2 objects, section `groups`'
                '- `Team` -- 2 objects, section `administrativeUnits`'
                '- `Catalog One/Package` -- 3 objects, section `accessPackages`'
            ) -join "`n")
        # The Entra ID call captures its records rather than showing them.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1 -ParameterFilter {
            $InformationAction -eq 'SilentlyContinue' -and $InformationVariable -eq 'InventoryInformation'
        }
    }

    It 'reads only the records tagged Omnicit.EntraRBAC.SharedName' {
        $script:SnInventoryRecords = @(
            @{ Tag = 'Omnicit.EntraRBAC.Other'; Notice = (New-SnNotice -Names @(New-SnName -Section 'catalogs' -Name 'Elsewhere' -Count 2)) }
            @{ Tag = 'Omnicit.EntraRBAC.SharedName'; Notice = (New-SnNotice -Names @(New-SnName -Section 'catalogs' -Name 'Shared' -Count 2)) }
        )
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sn-tag') -Include Catalogs -WarningAction SilentlyContinue -WarningVariable Warn
        ((Get-SnBullets -BundlePath $Bundle.BundlePath) -join "`n") | Should -BeExactly '- `Shared` -- 2 objects, section `catalogs`'
        @($Warn | Where-Object { "$_" -ceq ($script:SnWarningText -f 1, 2) }).Count | Should -Be 1
    }

    It 'writes no such warning, and README.md says no two objects share a name, when nothing is shared' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'sn-none') -Include Groups, AdministrativeUnits `
            -WarningAction SilentlyContinue -WarningVariable Warn
        @($Warn | Where-Object { "$_" -like '*carried by*object(s) in all*' }).Count | Should -Be 0
        @(Get-SnBullets -BundlePath $Bundle.BundlePath).Count | Should -Be 0
        (Get-Content (Join-Path $Bundle.BundlePath 'README.md') -Raw) | Should -Match ([regex]::Escape('None. No two objects this export read share a name.'))
        # Reach proof: both reads ran.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Exactly -Times 1
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Exactly -Times 1
    }

    It 'stops at the warning under a Stop warning preference, before it writes the bundle' {
        $script:SnReaderShared = @(New-SnName -Section 'groups' -Name 'Admins' -Count 2)
        $Root = Join-Path $TestDrive 'sn-stop'
        $Caught = $null
        try {
            Export-OERInventory -OutputPath $Root -Include Groups -WarningAction Stop | Out-Null
        } catch {
            $Caught = $PSItem
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.Exception.Message | Should -BeLike '*1 name(s), carried by 2 object(s) in all*'
        Test-Path $Root | Should -BeFalse
    }

    It 'states the rule in the help' {
        $Help = (Get-Help Export-OERInventory -Full | Out-String) -replace '\s+', ' '
        $Help | Should -Match ([regex]::Escape('NAMES THAT TWO OR MORE OBJECTS SHARE.'))
        $Help | Should -Match ([regex]::Escape('Groups are counted over every group in the tenant, the roster''s unfiltered listing, so a security group that shares its name with a Microsoft 365 group or a distribution group is left out too; when the roster could not be read, they are counted among the security-enabled groups the export reads.'))
        $Help | Should -Match ([regex]::Escape('The export writes ONE warning that gives how many names were left out and how many objects carry them in all.'))
        $Help | Should -Match ([regex]::Escape('in a section "Names two or more objects share", directly after "Role assignments at the root scope (elevated access)"'))
    }
}

Describe 'Export-OERInventory (one group name index per export, Sprint 11 step 6)' {
    # R-2 of step 5. A group named as a principal of a role assignment is written by its display name only
    # when no other group in the tenant carries it, decided over the index of every group's name
    # (Get-OERGroupNameIndex). Get-OERInventory builds that index once per call, and the export calls it
    # once per Azure scope, so an export over N scopes listed every group in the tenant N times. The export
    # now holds ONE run context for the Entra ID call and the whole Azure walk
    # ($script:_OERInventoryRunContext), whose GroupNameIndex is the roster's index when the roster was
    # read, and is otherwise built by the first caller, with one listing, and shared by the rest. The context
    # is owned by the export's own invocation, set back to $null by a plain statement after the walk (no
    # finally: a statement-terminating error in the region must keep skipping only its own statement), and
    # Get-OERInventory uses it only while its Owner is a frame of the call stack, so one an export leaves
    # behind is ignored. Get-OERInventory runs for REAL here and the listing is answered through the
    # transport, so the real Get-OERGroupNameIndex reads it. The tenant holds 'Ops' twice (in two letter
    # cases) and 'Solo' once; two subscriptions, the first assigning 'Ops' and the second 'Solo' to a group
    # principal. No id below is version-4 shaped.
    BeforeAll {
        $script:RcSubA = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:RcSubB = '/subscriptions/aaaa1111-0000-0000-0000-000000000002'
        $script:RcOps = 'eeee5555-0000-0000-0000-000000000001'
        $script:RcOpsOther = 'eeee5555-0000-0000-0000-000000000002'
        $script:RcSolo = 'eeee5555-0000-0000-0000-000000000003'
        $script:RcListing = 'v1.0/groups?$select=id,displayName&$top=999'
        # The rows inventory.json holds, as scope|principal|principalType, in scope order.
        function script:Get-RcRoleAssignmentRow {
            param([object]$Bundle)
            $Inventory = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inventory.roleAssignments | Sort-Object -Property scope | ForEach-Object { "$($_.scope)|$($_.principal)|$($_.principalType)" })
        }
        # What the run context holds right now, read from the module's scope.
        function script:Get-RcRunContext {
            & (Get-Module $script:moduleName) { $script:_OERInventoryRunContext }
        }
        $script:RcEmptyInventory = {
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        # The roster: the three groups of the tenant, 'Ops' in two letter cases.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = $script:RcOps; DisplayName = 'Ops'; GroupType = 'Assigned'; IsAssignableToRole = $false }
            [PSCustomObject]@{ Id = $script:RcOpsOther; DisplayName = 'OPS'; GroupType = 'Assigned'; IsAssignableToRole = $false }
            [PSCustomObject]@{ Id = $script:RcSolo; DisplayName = 'Solo'; GroupType = 'Assigned'; IsAssignableToRole = $false }
        }
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
        Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
            [PSCustomObject]@{
                Scopes    = @($script:RcSubA, $script:RcSubB)
                Hierarchy = [PSCustomObject]@{
                    managementGroups = @()
                    subscriptions    = @(
                        [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'One'; id = $script:RcSubA; state = 'Enabled' }
                        [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Two'; id = $script:RcSubB; state = 'Enabled' }
                    )
                }
            }
        }
        # One group principal per scope: 'Ops' at the first, 'Solo' at the second.
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
            $GroupId = if ($Scope -eq $script:RcSubA) { $script:RcOps } else { $script:RcSolo }
            [PSCustomObject]@{
                Scope = $Scope; RoleName = 'Reader'; RoleDefinitionId = "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-reader"
                PrincipalId = $GroupId; PrincipalType = 'Group'; PrincipalDisplayName = 'fixture'
                RoleAssignmentId = "$Scope/providers/Microsoft.Authorization/roleAssignments/$GroupId"
            }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
            & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ $script:RcOps = 'Ops'; $script:RcSolo = 'Solo' }
        }
        # Any request the fixture does not answer fails visibly; the one listing of every group is answered.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = $script:RcOps; displayName = 'Ops' }
                    @{ id = $script:RcOpsOther; displayName = 'OPS' }
                    @{ id = $script:RcSolo; displayName = 'Solo' }
                ) }
        } -ParameterFilter { $Uri -ceq $script:RcListing }
    }

    AfterEach {
        InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
    }

    It 'lists every group in the tenant once for the whole export, not once per Azure scope' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-listing') -Include RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        # Reach proof: the real Get-OERInventory read both scopes, each naming a group principal.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Exactly -Times 1 -ParameterFilter { $Scope -eq $script:RcSubA -and $ResolveNames }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Exactly -Times 1 -ParameterFilter { $Scope -eq $script:RcSubB -and $ResolveNames }
        # 'Ops' is shared by two groups, so it is written by its object id; 'Solo' is unique, so by its name.
        Get-RcRoleAssignmentRow -Bundle $Bundle | Should -Be @("$($script:RcSubA)|$($script:RcOps)|Group", "$($script:RcSubB)|Solo|Group")
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -ceq $script:RcListing -and $All }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1
    }

    It 'builds the index from the roster and sends no listing at all when Groups is included' {
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-roster') -Include Groups, RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        # Reach proof: the roster was read once, and both scopes were read and named from its index.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Exactly -Times 1 -ParameterFilter { $All }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Exactly -Times 2 -ParameterFilter { $ResolveNames }
        Get-RcRoleAssignmentRow -Bundle $Bundle | Should -Be @("$($script:RcSubA)|$($script:RcOps)|Group", "$($script:RcSubB)|Solo|Group")
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 0
    }

    It 'holds one context for the Entra ID call and every scope, created before the first call, owned by the export, holding the roster index' {
        $script:RcSeen = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $Context = & (Get-Module Omnicit.EntraRBAC) { $script:_OERInventoryRunContext }
            # Whether the Owner is a frame of the call stack this call runs on, the way Get-OERInventory asks.
            $OnStack = $false
            if ($null -ne $Context -and $null -ne $Context.Owner) {
                foreach ($Frame in Microsoft.PowerShell.Utility\Get-PSCallStack) {
                    if ([object]::ReferenceEquals($Frame.InvocationInfo, $Context.Owner)) { $OnStack = $true }
                }
            }
            $script:RcSeen.Add([PSCustomObject]@{ Include = (@($Include) -join ','); Context = $Context; OwnerOnStack = $OnStack })
            & $script:RcEmptyInventory
        }
        $null = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-shared') -Include Groups, AdministrativeUnits, RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        # The Entra ID call first, then one call per scope.
        @($script:RcSeen | ForEach-Object { $_.Include }) | Should -Be @('AdministrativeUnits', 'RoleAssignments', 'RoleAssignments')
        $Contexts = @($script:RcSeen | ForEach-Object { $_.Context })
        @($Contexts | Where-Object { $null -eq $_ }).Count | Should -Be 0
        [object]::ReferenceEquals($Contexts[0], $Contexts[1]) | Should -BeTrue
        [object]::ReferenceEquals($Contexts[0], $Contexts[2]) | Should -BeTrue
        # The Owner is the export's own invocation, and a frame of the stack every call runs on.
        @($script:RcSeen | Where-Object { $_.OwnerOnStack }).Count | Should -Be 3
        $Contexts[0].Owner | Should -BeOfType ([System.Management.Automation.InvocationInfo])
        $Contexts[0].Owner.MyCommand.Name | Should -BeExactly 'Export-OERInventory'
        # The owner, the group name index and the three members of the principal reads (Sprint 11 step 6,
        # BL-133): the deleted items answers, and the unread principal entries and their causes, each empty
        # and of the type Get-OERInventory fills.
        @($Contexts[0].PSObject.Properties.Name) | Should -Be @('Owner', 'GroupNameIndex', 'PrincipalStatus', 'UnreadPrincipal', 'UnreadPrincipalCause')
        $Contexts[0].PrincipalStatus | Should -BeOfType ([System.Collections.Generic.Dictionary[string, object]])
        $Contexts[0].PrincipalStatus.Comparer.Equals('ABC', 'abc') | Should -BeTrue
        $Contexts[0].PrincipalStatus.Count | Should -Be 0
        , $Contexts[0].UnreadPrincipal | Should -BeOfType ([System.Collections.Generic.List[string]])
        $Contexts[0].UnreadPrincipal.Count | Should -Be 0
        , $Contexts[0].UnreadPrincipalCause | Should -BeOfType ([System.Collections.Generic.List[object]])
        $Contexts[0].UnreadPrincipalCause.Count | Should -Be 0
        $Contexts[0].GroupNameIndex.Read | Should -BeTrue
        $Contexts[0].GroupNameIndex.IdsByName['ops'].Count | Should -Be 2
        $Contexts[0].GroupNameIndex.IdsByName['solo'].Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Exactly -Times 1 -ParameterFilter { $All }
    }

    It 'holds no index in the context until something asks for it, when the roster was not read' {
        $script:RcSeen = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $script:RcSeen.Add([PSCustomObject]@{ Include = (@($Include) -join ','); Context = (& (Get-Module Omnicit.EntraRBAC) { $script:_OERInventoryRunContext }) })
            & $script:RcEmptyInventory
        }
        $null = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-noroster') -Include AdministrativeUnits, RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $script:RcSeen.Count | Should -Be 3
        $Contexts = @($script:RcSeen | ForEach-Object { $_.Context })
        @($Contexts | Where-Object { $null -eq $_ }).Count | Should -Be 0
        $Contexts[0].PSObject.Properties.Name | Should -Contain 'GroupNameIndex'
        $null -eq $Contexts[0].GroupNameIndex | Should -BeTrue
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 0
    }

    It 'builds the index without the roster by the first caller and shares it, also when the roster could not be read' {
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [CmdletBinding()] param([switch]$All)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-rosterfail') -Include Groups, RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        # Reach proof: the roster read ran and failed, and the scopes were read.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Exactly -Times 1 -ParameterFilter { $All }
        Get-RcRoleAssignmentRow -Bundle $Bundle | Should -Be @("$($script:RcSubA)|$($script:RcOps)|Group", "$($script:RcSubB)|Solo|Group")
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -ceq $script:RcListing -and $All }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1
    }

    It 'removes the context when the export ends' {
        $null = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-end') -Include RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        # Reach proof: the walk ran under the context.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Exactly -Times 2
        $null -eq (Get-RcRunContext) | Should -BeTrue
    }

    It 'ignores a context an export left behind when its walk stopped: the next standalone Get-OERInventory lists for itself' {
        # There is no finally: an export that stops inside the walk never reaches the statement that clears
        # its context. The context is then ignored by ownership, since its Owner is on no call stack.
        Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { throw 'the eligibility read stopped' }
        { Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-left-behind') -Include Groups, RoleAssignments -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*the eligibility read stopped*'
        # Reach proof: both scopes were read, the walk stopped at the eligibility read, and the context the
        # export left behind holds the roster's index (the tenant of the roster: 'Ops' carried by two groups).
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Exactly -Times 2
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryAzureEligibility -Exactly -Times 1
        $Left = Get-RcRunContext
        $null -ne $Left | Should -BeTrue
        $Left.GroupNameIndex.IdsByName['ops'].Count | Should -Be 2
        # The listing now says 'Ops' belongs to one group: the call writes the name only when it listed for itself.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = $script:RcOps; displayName = 'Ops' }
                    @{ id = $script:RcSolo; displayName = 'Solo' }
                ) }
        } -ParameterFilter { $Uri -ceq $script:RcListing }
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:RcSubA -WarningAction SilentlyContinue
        @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @('Ops|Group')
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -ceq $script:RcListing -and $All }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1
    }

    It 'ignores a context an export left behind when the next export starts: it overwrites it and lists once' {
        $Stale = & (Get-Module $script:moduleName) {
            function Get-FinishedInvocation { $MyInvocation }
            $script:_OERInventoryRunContext = [PSCustomObject]@{
                Owner          = (Get-FinishedInvocation)
                GroupNameIndex = [PSCustomObject]@{ Read = $true; IdsByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new(); Message = $null }
            }
            $script:_OERInventoryRunContext
        }
        # Reach proof: a context with a finished command's invocation as its Owner stands in the module.
        $Stale.Owner | Should -BeOfType ([System.Management.Automation.InvocationInfo])
        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'rc-overwrite') -Include RoleAssignments -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Get-RcRoleAssignmentRow -Bundle $Bundle | Should -Be @("$($script:RcSubA)|$($script:RcOps)|Group", "$($script:RcSubB)|Solo|Group")
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -ceq $script:RcListing -and $All }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1
        $null -eq (Get-RcRunContext) | Should -BeTrue
    }

    It 'keeps the control flow of the region: a statement-terminating error in the Entra ID call skips only that statement, and the walk still runs' {
        # No try/finally wraps the region: a body-wide one skips the REST of the region on such an error,
        # the whole Azure walk included, and writes a bundle with no Azure rows and no partial signal. A
        # statement-terminating error only stays statement-level where no try stands up the call stack,
        # and Pester stands in one, so the export runs in a runspace and a script with no try. The stubs
        # replace the module's functions in that runspace's own copy; the log shows which reads were made.
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Root = Join-Path $TestDrive 'rc-no-try'
        $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Get-OERConfiguration -Value { }
    Set-Item -Path function:script:Test-OERStructureSchema -Value { [PSCustomObject]@{ Valid = $true; Errors = @() } }
    Set-Item -Path function:script:Get-OERInventoryAzureEligibility -Value { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
    Set-Item -Path function:script:Resolve-OERInventoryScopeTree -Value {
        [PSCustomObject]@{
            Scopes    = @('/subscriptions/aaaa1111-0000-0000-0000-000000000001', '/subscriptions/aaaa1111-0000-0000-0000-000000000002')
            Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
        }
    }
    Set-Item -Path function:script:Get-OERInventory -Value {
        [CmdletBinding()]
        param($Include, $Scope, [switch]$AllRolesAtScope, [switch]$AllDirectoryRolePolicies)
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value ('Get-OERInventory ' + (@($Include) -join ','))
        if (@($Include) -contains 'AdministrativeUnits') {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('the Entra ID call was refused'), 'EntraCallRefused',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
        }
        [PSCustomObject]@{
            Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
            AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
        }
    }
}
$Bundle = Export-OERInventory -OutputPath '#ROOT#' -Include AdministrativeUnits, RoleAssignments -Confirm:$false
"BUNDLE:$(@($Bundle).Count)"
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#ROOT#', $Root.Replace("'", "''")))
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        # The script reached its end, and the export wrote its bundle.
        ($Run.Output -join '|') | Should -Be 'BUNDLE:1|END'
        # The Entra ID call was made and refused, and the walk read both scopes after it.
        @(Get-Content -LiteralPath $Log) | Should -Be @('Get-OERInventory AdministrativeUnits', 'Get-OERInventory RoleAssignments', 'Get-OERInventory RoleAssignments')
        @($Run.Errors | Where-Object { $_ -like '*the Entra ID call was refused*' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Export-OERInventory (role assignments whose principal the directory did not return, Sprint 11 step 6, BL-133)' {
    # BL-133 (A18). A role assignment whose principal Microsoft Entra ID does not return stays in
    # inventory.json and roleAssignments.json, written by the principal's object id with principalStatus.
    # Every per-scope Get-OERInventory call names such rows in a warning and an information record tagged
    # Omnicit.EntraRBAC.UnresolvedPrincipal; the export reads the records, suppresses those warnings,
    # deduplicates the rows (the role assignment id, else scope, role and principal, without regard to
    # letter case), warns ONCE before its ShouldProcess and lists them in the README. The warnings are
    # counted on the warning STREAM (3>&1), what the caller is shown. No id below is version-4 shaped.
    BeforeAll {
        # Writes what a per-scope Get-OERInventory call writes, from inside the module, so the preferences
        # of the call it stands in for govern it exactly as they govern the real command.
        function script:Write-AsUpxInventory {
            param([string]$Warning, [object]$Notice)
            & (Get-Module $script:moduleName) {
                param($Warning, $Notice)
                if ($Warning) { Microsoft.PowerShell.Utility\Write-Warning $Warning }
                if ($Notice) { Microsoft.PowerShell.Utility\Write-Information -MessageData $Notice -Tags 'Omnicit.EntraRBAC.UnresolvedPrincipal' }
            } $Warning $Notice
        }
        $script:UpxHeading = '## Role assignments whose principal the directory did not return'
        $script:UpxMg = '/providers/Microsoft.Management/managementGroups/plat'
        $script:UpxS1 = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:UpxGone = 'dddd9999-0000-0000-0000-000000000001'
        $script:UpxNowhere = 'dddd9999-0000-0000-0000-000000000002'
        $script:UpxFail = 'dddd9999-0000-0000-0000-000000000003'
        $script:UpxIdA = "$($script:UpxMg)/providers/Microsoft.Authorization/roleAssignments/cccc9999-0000-0000-0000-000000000001"
        function script:Get-UpxExportWarning {
            param([int]$Count)
            "Export-OERInventory: $Count role assignment(s) in inventory.json and roleAssignments.json name a principal the " +
            "directory did not return, each written by the principal's object id with principalStatus Deleted (found among the " +
            "directory's deleted items) or Unresolved (found neither in the directory nor among its deleted items, or its deleted " +
            "items could not be read). README.md names them under 'Role assignments whose principal the directory did not return'; " +
            "review them as a finding. Invoke-OERStructure never " +
            'creates such an assignment.'
        }
        # The README section, heading included, up to the next level 2 heading; $null when it is missing.
        function script:Get-UpxReadmeSection {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:UpxHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        # One export, its result, the text of every warning that reached the caller's stream, and its errors.
        function script:Invoke-UpxExport {
            param([hashtable]$Splat)
            $ExErr = $null
            $All = @(Export-OERInventory @Splat -WarningAction Continue -ErrorAction SilentlyContinue -ErrorVariable ExErr 3>&1)
            [PSCustomObject]@{
                Result   = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
                Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                Partial  = @($ExErr | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
            }
        }
    }

    It 'states the rule in the help' {
        $Description = ((@((Get-Help Export-OERInventory -Full).Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Description | Should -Match ([regex]::Escape('ROLE ASSIGNMENTS WHOSE PRINCIPAL THE DIRECTORY DID NOT RETURN.'))
        $Description | Should -Match ([regex]::Escape('Invoke-OERStructure never creates such an assignment, and removing its entry lets -Prune remove it.'))
        $Description | Should -Match ([regex]::Escape('in a section "Role assignments whose principal the directory did not return", directly after "Names two or more objects share"'))
        $Description | Should -Match ([regex]::Escape('The Azure scope is never skipped for either.'))
        # Fix round 1 (F4): one read per principal for the whole export holds only for a read that succeeded.
        $Description | Should -Match ([regex]::Escape('A principal is looked for among the deleted items once for the whole export when that read succeeds, however many Azure scopes read the assignment; a read that fails is not kept, and is sent again by the next scope that needs it.'))
        # Fix round 1 (F3): the README lists the principal entries under a label of their own.
        $Description | Should -Match ([regex]::Escape('a role assignment principal that could not be read and an Azure scope where role management policies could not be judged, each under a label of its own'))
    }

    Context 'the rows the per-scope calls hand over' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{
                    Scopes    = @($script:UpxMg, $script:UpxS1)
                    Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                }
            }
            # Each scope hands over the inherited management group row A (its id in another letter case at
            # the second scope) and a row B with no role assignment id (its role and principal in another
            # letter case at the second scope), with the warning a real call writes.
            Mock -ModuleName $script:moduleName Get-OERInventory {
                param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
                $Ra = @()
                if ($Include -contains 'RoleAssignments' -and $Scope) {
                    $First = $Scope -eq $script:UpxMg
                    $RowA = [PSCustomObject]@{
                        RoleAssignmentId = $(if ($First) { $script:UpxIdA } else { $script:UpxIdA.ToUpperInvariant() })
                        Scope = $script:UpxMg; Role = 'Reader'; Principal = $script:UpxGone; PrincipalType = 'User'; PrincipalStatus = 'Deleted'; StatusRead = $true
                    }
                    $RowB = [PSCustomObject]@{
                        RoleAssignmentId = ''; Scope = $script:UpxS1; Role = $(if ($First) { 'Owner' } else { 'OWNER' })
                        Principal = $(if ($First) { $script:UpxNowhere } else { $script:UpxNowhere.ToUpperInvariant() }); PrincipalType = ''; PrincipalStatus = 'Unresolved'; StatusRead = $false
                    }
                    $Notice = [PSCustomObject]@{ Warning = "per-scope unresolved principals at $Scope"; Assignments = @($RowA, $RowB) }
                    $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.UnresolvedPrincipalNotice')
                    Write-AsUpxInventory -Warning "per-scope unresolved principals at $Scope" -Notice $Notice
                    $Ra = @([PSCustomObject]@{ scope = $script:UpxMg; role = 'Reader'; principal = $script:UpxGone; principalType = 'User'; principalStatus = 'Deleted' })
                }
                $Inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = $Ra; RoleManagementPolicies = @()
                }
                $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $Inv
            }
        }

        AfterEach {
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'names each row once, in its own warning and in the README, and shows none of the per-scope warnings' {
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-once'); Include = 'RoleAssignments' }
            # Reach proof: both scopes were read, and each handed over both rows.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            $Run.Warnings | Should -Be @(Get-UpxExportWarning -Count 2)
            $Section = Get-UpxReadmeSection -BundlePath $Run.Result.BundlePath
            $Section | Should -Match '(?m)^This export read 2 such role assignment\(s\):\r?$'
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @(
                "- ``Reader`` at ``$($script:UpxMg)`` for ``$($script:UpxGone)`` (User): ``Deleted``, found among the directory's deleted items"
                # Row B's deleted items read failed (StatusRead false): the export hands the member to the
                # README, which gives no reason as a fact (fix round 1, F1).
                "- ``Owner`` at ``$($script:UpxS1)`` for ``$($script:UpxNowhere)``: ``Unresolved``, not returned by the directory, and the read of its deleted items failed, so the reason is not known; that read is named under `"What this export could not read`""
            )
            # The rows stay in the document, and nothing about them is a partial read.
            $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalStatus)" }) | Should -Be @("$($script:UpxGone)|Deleted")
            $Run.Partial.Count | Should -Be 0
            @($Run.Result.IncompleteReads).Count | Should -Be 0
        }

        It 'writes the warning under -WhatIf too, and no bundle' {
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-whatif'); Include = 'RoleAssignments'; WhatIf = $true }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            $Run.Warnings | Should -Be @(Get-UpxExportWarning -Count 2)
            Test-Path -LiteralPath $Run.Result.BundlePath | Should -BeFalse
        }

        It 'stops at its own warning under -WarningAction Stop, before the bundle is written' {
            $Out = Join-Path $TestDrive 'upx-stop'
            $Thrown = { Export-OERInventory -OutputPath $Out -Include RoleAssignments -WarningAction Stop } | Should -Throw -PassThru
            $Thrown.Exception.Message | Should -BeLike '*role assignment(s) in inventory.json and roleAssignments.json name a principal*'
            # Both scopes were read: the per-scope warnings are captured, not shown, so neither stopped a scope.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            Test-Path -LiteralPath $Out | Should -BeFalse
        }

        It 'says in the README that none was found, and writes no such warning, when no scope handed a row over' {
            Mock -ModuleName $script:moduleName Get-OERInventory {
                $Inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
                }
                $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $Inv
            }
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-none'); Include = 'RoleAssignments' }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            @($Run.Warnings | Where-Object { $_ -like '*principalStatus*' }).Count | Should -Be 0
            ((Get-UpxReadmeSection -BundlePath $Run.Result.BundlePath) -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. No role assignment this export read names a principal that the directory did not return'))
        }
    }

    Context 'end to end, through the real Get-OERInventory' {
        # The management group read holds two assignments, both inherited by the subscription read: one
        # whose principal the directory did not return and holds among its deleted items, and one whose
        # principal lookup fails. The group reader leaves one collection unread, an Entra ID entry.
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
                [PSCustomObject]@{
                    Groups = @(); Unread = @('groups/Team/members')
                    Causes = @([PSCustomObject]@{ Cause = 'Could not read members for group ''g-1'': Too many requests (429).'; Target = 'g-1' })
                }
            }
            # The self-check is not what is tested here; the Context "the export's own apply-schema
            # self-check" below runs the real validator over a bundle that carries a principalStatus row.
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{
                    Scopes    = @($script:UpxMg, $script:UpxS1)
                    Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                }
            }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = $script:UpxMg; RoleName = 'Reader'; RoleDefinitionId = "$($script:UpxMg)/providers/Microsoft.Authorization/roleDefinitions/rd-reader"
                    PrincipalId = $script:UpxGone; PrincipalType = 'User'; PrincipalDisplayName = $null; RoleAssignmentId = $script:UpxIdA
                }
                [PSCustomObject]@{
                    Scope = $script:UpxMg; RoleName = 'Owner'; RoleDefinitionId = "$($script:UpxMg)/providers/Microsoft.Authorization/roleDefinitions/rd-owner"
                    PrincipalId = $script:UpxFail; PrincipalType = 'User'; PrincipalDisplayName = 'Person Three'
                    RoleAssignmentId = "$($script:UpxMg)/providers/Microsoft.Authorization/roleAssignments/cccc9999-0000-0000-0000-000000000003"
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                foreach ($One in @($Id)) {
                    if ($One -eq $script:UpxGone) { [PSCustomObject]@{ Id = $One; Read = $true; Found = $false; Name = $null; ObjectType = $null; Cause = $null } }
                    else { [PSCustomObject]@{ Id = $One; Read = $false; Found = $false; Name = $null; ObjectType = $null; Cause = 'Too many requests (429)' } }
                }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = $script:UpxGone; '@odata.type' = '#microsoft.graph.user' }
            } -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpxGone)" }
        }

        AfterEach {
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'reads each principal among the deleted items once for the whole export, writes it with principalStatus, and names it once' {
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-e2e'); Include = 'Groups', 'RoleAssignments' }
            # Reach proof: both scopes were read, each returning both assignments.
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 2 -Exactly -ParameterFilter { $ResolveNames }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpxGone)" }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)|$($_.principalStatus)" }) | Should -Be @(
                "Reader|$($script:UpxGone)|User|Deleted"
                "Owner|$($script:UpxFail)|User|"
            )
            @($Run.Warnings | Where-Object { $_ -like 'Export-OERInventory: * name a principal*' }) | Should -Be @(Get-UpxExportWarning -Count 1)
            @($Run.Warnings | Where-Object { $_ -like 'Get-OERInventory:*' }).Count | Should -Be 0
            @((Get-UpxReadmeSection -BundlePath $Run.Result.BundlePath) -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @(
                "- ``Reader`` at ``$($script:UpxMg)`` for ``$($script:UpxGone)`` (User): ``Deleted``, found among the directory's deleted items"
            )
        }

        It 'names a failed lookup once in IncompleteReads after the Entra ID entries, keeps the scopes, and gives it a clause of its own in InventoryPartial' {
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-unread'); Include = 'Groups', 'RoleAssignments' }
            $Entry = "roleAssignments/Owner -> $($script:UpxFail) @ $($script:UpxMg)/principal"
            # No scope was skipped: the per-scope calls named the failed lookup to the run context instead of
            # raising their own InventoryPartial, which -ErrorAction Stop would have turned into a skip.
            @($Run.Result.SkippedScopes) | Should -BeNullOrEmpty
            $Run.Result.ScopeCount | Should -Be 2
            # Both calls named it; the export names it once, after the Entra ID entry.
            @($Run.Result.IncompleteReads) | Should -Be @('groups/Team/members', $Entry)
            $Run.Partial.Count | Should -Be 1
            $Message = $Run.Partial[0].Exception.Message
            $Message | Should -BeLike "*1 role assignment principal read(s) failed, so each principal is written by its object id -- with no principalStatus where its lookup through directoryObjects/getByIds failed, and as Unresolved where only the read of the directory's deleted items failed: $Entry. Causes of the unread principal lookups: Could not look up the principal of a role assignment through directoryObjects/getByIds: Too many requests (429).*"
            # The Entra ID clause still counts the Entra ID entries only.
            $Message | Should -BeLike '*1 partial Entra ID read entry(ies) name*'
            # The README names it under "What this export could not read", under a label of its own (fix
            # round 1, F3), apart from the Entra ID entry.
            $Readme = Get-Content (Join-Path $Run.Result.BundlePath 'README.md') -Raw
            $Readme | Should -Match ([regex]::Escape("- Role assignment principal that could not be read: ``$Entry``"))
            $Readme | Should -Match ([regex]::Escape('- Entra ID: `groups/Team/members`'))
        }

        It 'raises InventoryPartial for a failed principal lookup alone, when nothing else was left unread' {
            # RoleAssignments only: no group read, no Entra ID entry, no skipped scope. The principal entry is
            # the one thing that makes the bundle partial.
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-alone'); Include = 'RoleAssignments' }
            $Entry = "roleAssignments/Owner -> $($script:UpxFail) @ $($script:UpxMg)/principal"
            @($Run.Result.IncompleteReads) | Should -Be @($Entry)
            @($Run.Result.SkippedScopes) | Should -BeNullOrEmpty
            @($Run.Result.SkippedEligibilityScopes) | Should -BeNullOrEmpty
            $Run.Partial.Count | Should -Be 1
            $Run.Partial[0].Exception.Message | Should -BeLike 'This inventory bundle is PARTIAL: 1 role assignment principal read(s) failed, so each principal is written by its object id*'
            $Run.Partial[0].Exception.Message | Should -Not -BeLike '*partial Entra ID read entry*'
        }
    }

    Context 'the export''s own apply-schema self-check (A18)' {
        # Test-OERStructureSchema is NOT mocked away here: the mock calls the real validator through and
        # keeps what it returned, so the test reads the validator's findings and not just the warning the
        # export writes when the document is invalid (an unknown key is a Warning finding, which leaves the
        # document Valid and so writes no export warning). The bundle carries one row of each status.
        BeforeAll {
            $script:UpxRealValidate = InModuleScope $script:moduleName { Get-Command Test-OERStructureSchema -CommandType Function }
        }

        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
            # A list the mock adds to: an assignment inside a mock would not reach the test's scope.
            $script:UpxSelfChecks = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{
                    Scopes    = @($script:UpxS1)
                    Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                }
            }
            Mock -ModuleName $script:moduleName Test-OERStructureSchema {
                $Result = & $script:UpxRealValidate @PesterBoundParameters
                $script:UpxSelfChecks.Add($Result)
                $Result
            }
            Mock -ModuleName $script:moduleName Get-OERInventory {
                param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
                $Ra = @()
                if ($Include -contains 'RoleAssignments' -and $Scope) {
                    $RowA = [PSCustomObject]@{
                        RoleAssignmentId = $script:UpxIdA; Scope = $script:UpxS1; Role = 'Reader'
                        Principal = $script:UpxGone; PrincipalType = 'User'; PrincipalStatus = 'Deleted'; StatusRead = $true
                    }
                    $RowB = [PSCustomObject]@{
                        RoleAssignmentId = ''; Scope = $script:UpxS1; Role = 'Owner'
                        Principal = $script:UpxNowhere; PrincipalType = ''; PrincipalStatus = 'Unresolved'; StatusRead = $true
                    }
                    $Notice = [PSCustomObject]@{ Warning = "per-scope unresolved principals at $Scope"; Assignments = @($RowA, $RowB) }
                    $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.UnresolvedPrincipalNotice')
                    Write-AsUpxInventory -Warning "per-scope unresolved principals at $Scope" -Notice $Notice
                    $Ra = @(
                        [PSCustomObject]@{ scope = $script:UpxS1; role = 'Reader'; principal = $script:UpxGone; principalType = 'User'; principalStatus = 'Deleted' }
                        [PSCustomObject]@{ scope = $script:UpxS1; role = 'Owner'; principal = $script:UpxNowhere; principalStatus = 'Unresolved' }
                    )
                }
                $Inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = $Ra; RoleManagementPolicies = @()
                }
                $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $Inv
            }
        }

        AfterEach {
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'passes the real self-check with no finding at all for a bundle whose inventory.json carries principalStatus rows' {
            $Run = Invoke-UpxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'upx-selfcheck'); Include = 'RoleAssignments' }
            # Reach proofs: the scope was read, the bundle holds both rows, and the real validator ran over them.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Times 1 -Exactly
            $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalStatus)" }) | Should -Be @(
                "Reader|$($script:UpxGone)|Deleted"
                "Owner|$($script:UpxNowhere)|Unresolved"
            )
            $script:UpxSelfChecks.Count | Should -Be 1
            @($script:UpxSelfChecks[0].Errors | ForEach-Object { "$($_.Severity): $($_.Path): $($_.Message)" }) | Should -Be @()
            $script:UpxSelfChecks[0].Valid | Should -BeTrue
            @($Run.Warnings | Where-Object { $_ -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
            @($Run.Warnings | Where-Object { $_ -like '*Could not run the apply-schema self-check*' }).Count | Should -Be 0
        }
    }
}

Describe 'Export-OERInventory (role assignments at a scope no document can declare, A13, A15)' {
    # A role assignment whose scope breaks a scope spelling rule the validator applies -- a resource whose
    # name holds a '#' or a '%', for one -- is left out of inventory.json and roleAssignments.json: every
    # per-scope Get-OERInventory call names such rows in a warning and an information record tagged
    # Omnicit.EntraRBAC.UndeclarableScope. The export reads the records, suppresses those warnings,
    # deduplicates the rows (the role assignment id, else scope, role and principal, without regard to
    # letter case), warns ONCE before its ShouldProcess and lists them in the README. The warnings are
    # counted on the warning STREAM (3>&1), what the caller is shown. Scopes holding '#' or '%' are
    # fixtures only. No id below is version-4 shaped.
    BeforeAll {
        # Writes what a per-scope Get-OERInventory call writes, from inside the module, so the preferences
        # of the call it stands in for govern it exactly as they govern the real command.
        function script:Write-AsUdxInventory {
            param([string]$Warning, [object]$Notice)
            & (Get-Module $script:moduleName) {
                param($Warning, $Notice)
                if ($Warning) { Microsoft.PowerShell.Utility\Write-Warning $Warning }
                if ($Notice) { Microsoft.PowerShell.Utility\Write-Information -MessageData $Notice -Tags 'Omnicit.EntraRBAC.UndeclarableScope' }
            } $Warning $Notice
        }
        $script:UdxHeading = '## Role assignments at a scope no document can declare'
        $script:UdxMg = '/providers/Microsoft.Management/managementGroups/plat'
        $script:UdxS1 = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:UdxHash = "$($script:UdxS1)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1"
        $script:UdxPercent = "$($script:UdxS1)/resourceGroups/rg%2Fone"
        $script:UdxIdA = "$($script:UdxHash)/providers/Microsoft.Authorization/roleAssignments/cccc8888-0000-0000-0000-000000000001"
        function script:Get-UdxExportWarning {
            param([int]$Count)
            "Export-OERInventory: left out $Count role assignment(s) whose scope no document can declare from inventory.json " +
            "and roleAssignments.json: the validator refuses the scope's spelling, so a document that carried one would be " +
            "refused as a whole. README.md names them under 'Role assignments at a scope no document can declare'; review them " +
            'as a finding. Invoke-OERStructure never creates or removes a role assignment at such a scope.'
        }
        # The README section, heading included, up to the next level 2 heading; $null when it is missing.
        function script:Get-UdxReadmeSection {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:UdxHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        # One export, its result, the text of every warning that reached the caller's stream, and its errors.
        function script:Invoke-UdxExport {
            param([hashtable]$Splat)
            $ExErr = $null
            $All = @(Export-OERInventory @Splat -WarningAction Continue -ErrorAction SilentlyContinue -ErrorVariable ExErr 3>&1)
            [PSCustomObject]@{
                Result   = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
                Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                Partial  = @($ExErr | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
            }
        }
    }

    It 'states the rule in the help' {
        $Description = ((@((Get-Help Export-OERInventory -Full).Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Description | Should -Match ([regex]::Escape('ROLE ASSIGNMENTS AT A SCOPE NO DOCUMENT CAN DECLARE.'))
        $Description | Should -Match ([regex]::Escape('inventory.json and roleAssignments.json never carry one'))
        $Description | Should -Match ([regex]::Escape('in a section "Role assignments at a scope no document can declare", directly after "Role assignments whose principal the directory did not return"'))
        $Description | Should -Match ([regex]::Escape('the warning on role assignments at a scope no document can declare'))
    }

    Context 'the rows the per-scope calls hand over' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{
                    Scopes    = @($script:UdxMg, $script:UdxS1)
                    Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                }
            }
            # Each scope hands over row A (its id in another letter case at the second scope) and a row B
            # with no role assignment id (its role and principal in another letter case at the second
            # scope), with the warning a real call writes, and one row of its own the document keeps.
            Mock -ModuleName $script:moduleName Get-OERInventory {
                param($Include, $Scope, $Subscription, $ManagementGroup, $AllRolesAtScope)
                $Ra = @()
                if ($Include -contains 'RoleAssignments' -and $Scope) {
                    $First = $Scope -eq $script:UdxMg
                    $RowA = [PSCustomObject]@{
                        RoleAssignmentId = $(if ($First) { $script:UdxIdA } else { $script:UdxIdA.ToUpperInvariant() })
                        Scope = $script:UdxHash; Role = 'Reader'; Principal = 'person1@example.com'; PrincipalType = 'User'
                        Reason = 'the scope holds a question mark or a number sign'
                    }
                    $RowB = [PSCustomObject]@{
                        RoleAssignmentId = ''; Scope = $script:UdxPercent; Role = $(if ($First) { 'Owner' } else { 'OWNER' })
                        Principal = $(if ($First) { 'Automation' } else { 'AUTOMATION' }); PrincipalType = ''; Reason = 'the scope holds a percent sign'
                    }
                    $Notice = [PSCustomObject]@{ Warning = "per-scope undeclarable scopes at $Scope"; Assignments = @($RowA, $RowB) }
                    $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.UndeclarableScopeNotice')
                    Write-AsUdxInventory -Warning "per-scope undeclarable scopes at $Scope" -Notice $Notice
                    $Ra = @([PSCustomObject]@{ scope = $script:UdxS1; role = 'Reader'; principal = 'person2@example.com'; principalType = 'User' })
                }
                $Inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = $Ra; RoleManagementPolicies = @()
                }
                $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $Inv
            }
        }

        AfterEach {
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'names each row once, in its own warning and in the README, and shows none of the per-scope warnings' {
            $Run = Invoke-UdxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'udx-once'); Include = 'RoleAssignments' }
            # Reach proof: both scopes were read, and each handed over both rows.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            $Run.Warnings | Should -Be @(Get-UdxExportWarning -Count 2)
            $Section = Get-UdxReadmeSection -BundlePath $Run.Result.BundlePath
            $Section | Should -Match '(?m)^This export read 2 such role assignment\(s\):\r?$'
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @(
                "- ``Reader`` at ``$($script:UdxHash)`` for ``person1@example.com`` (User): the scope holds a question mark or a number sign"
                "- ``Owner`` at ``$($script:UdxPercent)`` for ``Automation``: the scope holds a percent sign"
            )
            # The rows are left out of the document, not unread.
            $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.roleAssignments | ForEach-Object { $_.scope }) | Should -Be @($script:UdxS1)
            $Run.Partial.Count | Should -Be 0
            @($Run.Result.IncompleteReads).Count | Should -Be 0
        }

        It 'writes the warning under -WhatIf too, and no bundle' {
            $Run = Invoke-UdxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'udx-whatif'); Include = 'RoleAssignments'; WhatIf = $true }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            $Run.Warnings | Should -Be @(Get-UdxExportWarning -Count 2)
            Test-Path -LiteralPath $Run.Result.BundlePath | Should -BeFalse
        }

        It 'stops at its own warning under -WarningAction Stop, before the bundle is written' {
            $Out = Join-Path $TestDrive 'udx-stop'
            $Thrown = { Export-OERInventory -OutputPath $Out -Include RoleAssignments -WarningAction Stop } | Should -Throw -PassThru
            $Thrown.Exception.Message | Should -BeLike '*role assignment(s) whose scope no document can declare from inventory.json*'
            # Both scopes were read: the per-scope warnings are captured, not shown, so neither stopped a scope.
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            Test-Path -LiteralPath $Out | Should -BeFalse
        }

        It 'says in the README that none was read, and writes no such warning, when no scope handed a row over' {
            Mock -ModuleName $script:moduleName Get-OERInventory {
                $Inv = [PSCustomObject]@{
                    Version = '1.0'; Groups = @(); AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                    AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
                }
                $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
                $Inv
            }
            $Run = Invoke-UdxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'udx-none'); Include = 'RoleAssignments' }
            Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 2 -Exactly
            @($Run.Warnings | Where-Object { $_ -like '*no document can declare*' }).Count | Should -Be 0
            ((Get-UdxReadmeSection -BundlePath $Run.Result.BundlePath) -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. No role assignment this export read is at a scope a document cannot declare.'))
        }
    }

    Context 'end to end, through the real Get-OERInventory and the real self-check' {
        # The management group read and the subscription read both return the three assignments: one at the
        # subscription, one at a resource whose name holds a '#' and one at a resource group whose name holds
        # a '%'. Test-OERStructureSchema is NOT mocked: the export's own self-check runs the real validator.
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {}
            Mock -ModuleName $script:moduleName Get-OERGroup {}
            Mock -ModuleName $script:moduleName Get-OERInventoryGroup { [PSCustomObject]@{ Groups = @(); Unread = @(); Causes = @() } }
            Mock -ModuleName $script:moduleName Get-OERInventoryAzureEligibility { [PSCustomObject]@{ Eligibilities = @(); SkippedScopes = @() } }
            Mock -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus { throw "unexpected deleted items read: $Id" }
            Mock -ModuleName $script:moduleName Resolve-OERInventoryScopeTree {
                [PSCustomObject]@{
                    Scopes    = @($script:UdxMg, $script:UdxS1)
                    Hierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
                }
            }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = $script:UdxS1; RoleName = 'Reader'; RoleDefinitionId = "$($script:UdxS1)/providers/Microsoft.Authorization/roleDefinitions/rd-reader"
                    PrincipalId = 'dddd8888-0000-0000-0000-000000000001'; PrincipalType = 'User'; PrincipalDisplayName = 'User One'
                    RoleAssignmentId = "$($script:UdxS1)/providers/Microsoft.Authorization/roleAssignments/cccc8888-0000-0000-0000-000000000011"
                }
                [PSCustomObject]@{
                    Scope = $script:UdxHash; RoleName = 'Reader'; RoleDefinitionId = "$($script:UdxS1)/providers/Microsoft.Authorization/roleDefinitions/rd-reader"
                    PrincipalId = 'dddd8888-0000-0000-0000-000000000002'; PrincipalType = 'User'; PrincipalDisplayName = 'User Two'
                    RoleAssignmentId = $script:UdxIdA
                }
                [PSCustomObject]@{
                    Scope = $script:UdxPercent; RoleName = 'Owner'; RoleDefinitionId = "$($script:UdxS1)/providers/Microsoft.Authorization/roleDefinitions/rd-owner"
                    PrincipalId = 'dddd8888-0000-0000-0000-000000000003'; PrincipalType = 'ServicePrincipal'; PrincipalDisplayName = 'Automation'
                    RoleAssignmentId = "$($script:UdxPercent)/providers/Microsoft.Authorization/roleAssignments/cccc8888-0000-0000-0000-000000000013"
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{
                    'dddd8888-0000-0000-0000-000000000001' = 'person1@example.com'
                    'dddd8888-0000-0000-0000-000000000002' = 'person2@example.com'
                    'dddd8888-0000-0000-0000-000000000003' = 'Automation'
                }
            }
        }

        AfterEach {
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'leaves the rows at a scope holding a ''#'' and a ''%'' out of inventory.json and roleAssignments.json, warns once, lists them in the README, and passes its own self-check' {
            $Run = Invoke-UdxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'udx-e2e'); Include = 'RoleAssignments' }
            # Reach proof: both scopes were read, each returning all three assignments.
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 2 -Exactly -ParameterFilter { $ResolveNames }
            $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @("$($script:UdxS1)|Reader|person1@example.com")
            $RaFile = @(Get-Content (Join-Path $Run.Result.BundlePath 'roleAssignments.json') -Raw | ConvertFrom-Json)
            @($RaFile | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @("$($script:UdxS1)|Reader|person1@example.com")
            foreach ($File in @(Get-ChildItem -Path $Run.Result.BundlePath -Filter '*.json')) {
                Get-Content $File.FullName -Raw | Should -Not -Match ([regex]::Escape('db#1')) -Because "$($File.Name) must not carry the row at a scope holding a '#'"
                Get-Content $File.FullName -Raw | Should -Not -Match ([regex]::Escape('rg%2Fone')) -Because "$($File.Name) must not carry the row at a scope holding a '%'"
            }
            # One warning of the export's own, and none of the per-scope warnings; no self-check warning.
            @($Run.Warnings | Where-Object { $_ -like '*no document can declare*' }) | Should -Be @(Get-UdxExportWarning -Count 2)
            @($Run.Warnings | Where-Object { $_ -like 'Get-OERInventory:*' }).Count | Should -Be 0
            @($Run.Warnings | Where-Object { $_ -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
            @($Run.Warnings | Where-Object { $_ -like '*Could not run the apply-schema self-check*' }).Count | Should -Be 0
            @((Get-UdxReadmeSection -BundlePath $Run.Result.BundlePath) -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @(
                "- ``Reader`` at ``$($script:UdxHash)`` for ``person2@example.com`` (User): the scope holds a question mark or a number sign"
                "- ``Owner`` at ``$($script:UdxPercent)`` for ``Automation`` (ServicePrincipal): the scope holds a percent sign"
            )
            # Left out, not unread: the bundle is not partial, and no principal was looked for among the deleted items.
            $Run.Partial.Count | Should -Be 0
            @($Run.Result.IncompleteReads).Count | Should -Be 0
            @($Run.Result.SkippedScopes) | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus -Times 0
        }
    }
}

Describe 'Export-OERInventory (groups using PIM for Groups in a restricted management unit, Sprint 11 step 6, BL-134)' {
    # A group with PIM eligibility or a pimPolicy block that is a member of a restricted management unit may
    # be out of reach for the identity that applies the document. inventory.json keeps it; the export warns
    # ONCE before its ShouldProcess with the count, and the README names each group and its units. The
    # administrative units list a group member by its object id, which the export still holds before the id
    # strip, so the link is found with no request of its own. The warnings are counted on the warning STREAM
    # (3>&1), what the caller is shown. No id below is version-4 shaped.
    BeforeAll {
        $script:RuxHeading = '## Groups using PIM for Groups in a restricted management unit'
        $script:RuxElig = 'eeee5555-0000-0000-0000-00000000000a'
        $script:RuxPolicy = 'eeee5555-0000-0000-0000-00000000000b'
        $script:RuxPlain = 'eeee5555-0000-0000-0000-00000000000c'
        $script:RuxOpen = 'eeee5555-0000-0000-0000-00000000000d'
        $script:RuxUnreadUnit = 'eeee5555-0000-0000-0000-00000000000e'
        $script:RuxNullPolicy = 'eeee5555-0000-0000-0000-00000000000f'
        $script:RuxNullElig = 'eeee5555-0000-0000-0000-000000000010'
        function script:Get-RuxExportWarning {
            param([int]$Count)
            "Export-OERInventory: $Count group(s) written to inventory.json use PIM for Groups (PIM eligibility or a pimPolicy block) " +
            'and are members of a restricted management administrative unit. Microsoft Learn states that Privileged Identity Management ' +
            'does not support a group in a restricted management administrative unit. Invoke-OERStructure still sends the PIM settings ' +
            'and eligibility a document declares for these groups; what Microsoft Graph answers to those writes has not been measured. ' +
            "README.md names each group and its units under 'Groups using PIM for Groups in a restricted management unit'; review them " +
            'as a finding. Nothing is left out of the export.'
        }
        # The README section, heading included, up to the next level 2 heading; $null when it is missing.
        function script:Get-RuxReadmeSection {
            param([string]$BundlePath)
            $Readme = Get-Content (Join-Path $BundlePath 'README.md') -Raw
            $Start = $Readme.IndexOf($script:RuxHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        # One export, its result, the text of every warning that reached the caller's stream, and its errors.
        function script:Invoke-RuxExport {
            param([hashtable]$Splat)
            $ExErr = $null
            $All = @(Export-OERInventory @Splat -WarningAction Continue -ErrorAction SilentlyContinue -ErrorVariable ExErr 3>&1)
            [PSCustomObject]@{
                Result   = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
                Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                Partial  = @($ExErr | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' })
            }
        }
        $script:RuxRealValidate = InModuleScope $script:moduleName { Get-Command Test-OERStructureSchema -CommandType Function }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
        $script:RuxSelfChecks = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # The group reader: every group is read with its object id (the export asks for -IncludeId). The
        # first two use PIM for Groups, by eligibility and by a pimPolicy block; the third uses neither.
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups      = @(
                    [PSCustomObject]@{ id = $script:RuxElig; displayName = 'role_sec_elig'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; principalType = 'User'; accessType = 'Member' }) }
                    [PSCustomObject]@{ id = $script:RuxPolicy; displayName = 'role_sec_policy'; roleAssignable = $false; dynamic = $false; members = @(); eligibility = @(); pimPolicy = [PSCustomObject]@{ member = [PSCustomObject]@{ activationMaxHours = 8 } } }
                    [PSCustomObject]@{ id = $script:RuxPlain; displayName = 'role_sec_plain'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @() }
                )
                Unread      = @(); Causes = @(); PimLeftOut = @(); SharedNames = @()
            }
        }
        # The administrative units, as Get-OERInventory projects them: a group member by its object id.
        # The elig group's id is written in another letter case. 'Open AU' is not restricted; 'Unread
        # Restricted AU' has its members unread (an explicit null); 'Dynamic Restricted AU' has no members
        # key at all, as a dynamic unit is projected.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include)
            $Units = @()
            if ($Include -contains 'AdministrativeUnits') {
                $Units = @(
                    [PSCustomObject]@{ displayName = 'Restricted AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = @($script:RuxElig.ToUpperInvariant(), $script:RuxPolicy, $script:RuxPlain, 'person9@example.com'); scopedRoles = @() }
                    [PSCustomObject]@{ displayName = 'Second Restricted AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = @($script:RuxPolicy); scopedRoles = @() }
                    [PSCustomObject]@{ displayName = 'Open AU'; description = $null; restricted = $false; dynamic = $false; hiddenMembership = $false; members = @($script:RuxOpen); scopedRoles = @() }
                    [PSCustomObject]@{ displayName = 'Unread Restricted AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = $null; scopedRoles = @() }
                    [PSCustomObject]@{ displayName = 'Dynamic Restricted AU'; description = $null; restricted = $true; dynamic = $true; hiddenMembership = $false; membershipRule = '(user.department -eq "x")'; scopedRoles = @() }
                )
            }
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = $Units; Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
    }

    AfterEach {
        InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
    }

    It 'states the rule in the help' {
        $Description = ((@((Get-Help Export-OERInventory -Full).Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Description | Should -Match ([regex]::Escape('GROUPS USING PIM FOR GROUPS IN A RESTRICTED MANAGEMENT UNIT.'))
        $Description | Should -Match ([regex]::Escape('Microsoft Learn states that Privileged Identity Management does not support a group in a restricted management administrative unit'))
        $Description | Should -Match ([regex]::Escape('in a section "Groups using PIM for Groups in a restricted management unit", directly after "Role assignments at a scope no document can declare"'))
        $Description | Should -Match ([regex]::Escape('what Microsoft Graph answers to those writes has not been measured'))
        $Description | Should -Match ([regex]::Escape('a unit left out of the document because another unit shares its name is not checked here'))
    }

    It 'warns once with the count, names each group and its units in the README, and keeps both groups and every unit in inventory.json' {
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-once'); Include = @('Groups', 'AdministrativeUnits') }
        # Reach proof: the units were read, and the bundle holds every group and every unit.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Include -contains 'AdministrativeUnits' }
        $Run.Warnings | Should -Be @(Get-RuxExportWarning -Count 2)
        $Section = Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath
        $Section | Should -Match '(?m)^This export found 2 such group\(s\):\r?$'
        @($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) | Should -Be @(
            '- `role_sec_elig` -- member of the restricted management unit(s) `Restricted AU`'
            '- `role_sec_policy` -- member of the restricted management unit(s) `Restricted AU`, `Second Restricted AU`'
        )
        $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_elig', 'role_sec_policy', 'role_sec_plain')
        @($Inv.administrativeUnits | ForEach-Object { $_.displayName }) | Should -Be @('Restricted AU', 'Second Restricted AU', 'Open AU', 'Unread Restricted AU', 'Dynamic Restricted AU')
        # Nothing is left out and nothing is unread: the groups stay, and the bundle is not partial.
        $Run.Partial.Count | Should -Be 0
        @($Run.Result.IncompleteReads).Count | Should -Be 0
        # The id the link was found by stays out of the groups and out of the README: the units list their
        # group members by object id, as they always did, and the groups carry none.
        @($Inv.groups | Where-Object { $_.PSObject.Properties.Name -contains 'id' }).Count | Should -Be 0
        Get-Content (Join-Path $Run.Result.BundlePath 'README.md') -Raw | Should -Not -Match 'eeee5555'
        @($Run.Warnings | Where-Object { $_ -match 'eeee5555' }).Count | Should -Be 0
    }

    It 'lists a group once for each restricted unit that holds it, whatever the letter case of the id the unit lists' {
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-case'); Include = @('Groups', 'AdministrativeUnits') }
        # The elig group's id is upper-case in the unit's members and lower-case on the group.
        $Bullets = @((Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath) -split '\r?\n' | Where-Object { $_ -like '- *' })
        $Bullets[0] | Should -BeExactly '- `role_sec_elig` -- member of the restricted management unit(s) `Restricted AU`'
        $Bullets.Count | Should -Be 2
    }

    It 'names no group that uses no PIM, none that sits in a unit that is not restricted, and none whose unit was not read' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups      = @(
                    [PSCustomObject]@{ id = $script:RuxPlain; displayName = 'role_sec_plain'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @() }
                    [PSCustomObject]@{ id = $script:RuxOpen; displayName = 'role_sec_open'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; principalType = 'User'; accessType = 'Member' }) }
                    [PSCustomObject]@{ id = $script:RuxUnreadUnit; displayName = 'role_sec_unread'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; principalType = 'User'; accessType = 'Member' }) }
                )
                Unread      = @(); Causes = @(); PimLeftOut = @(); SharedNames = @()
            }
        }
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-none'); Include = @('Groups', 'AdministrativeUnits') }
        # Reach proofs: the units were read, and each group is in the document.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Include -contains 'AdministrativeUnits' }
        $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_plain', 'role_sec_open', 'role_sec_unread')
        @($Run.Warnings | Where-Object { $_ -like '*restricted management*' }).Count | Should -Be 0
        $Section = Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. No group that `inventory.json` writes with PIM eligibility or a `pimPolicy` block is a member of a restricted management unit this export checked.'))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape('a unit left out of the document because another unit shares its name, were not checked, and each is named under "What this export could not read".'))
        @($Section -split '\r?\n' | Where-Object { $_ -like '- *' }).Count | Should -Be 0
    }

    It 'does not take an explicit null pimPolicy or an eligibility that holds only a null for PIM for Groups' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups      = @(
                    [PSCustomObject]@{ id = $script:RuxNullPolicy; displayName = 'role_sec_nullpolicy'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @(); pimPolicy = $null }
                    [PSCustomObject]@{ id = $script:RuxNullElig; displayName = 'role_sec_nullelig'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @($null) }
                )
                Unread      = @(); Causes = @(); PimLeftOut = @(); SharedNames = @()
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include)
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(
                    [PSCustomObject]@{ displayName = 'Restricted AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = @($script:RuxNullPolicy, $script:RuxNullElig); scopedRoles = @() }
                ); Catalogs = @(); AccessPackages = @(); AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-nulls'); Include = @('Groups', 'AdministrativeUnits') }
        # Reach proofs: both groups are in the document (the keep filter keeps them as role-assignable
        # groups), and the restricted unit lists both by id.
        $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_nullpolicy', 'role_sec_nullelig')
        @($Inv.administrativeUnits[0].members).Count | Should -Be 2
        @($Run.Warnings | Where-Object { $_ -like '*restricted management*' }).Count | Should -Be 0
        @((Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath) -split '\r?\n' | Where-Object { $_ -like '- *' }).Count | Should -Be 0
    }

    It 'never takes a group with no object id for a member a unit lists as nothing' {
        Mock -ModuleName $script:moduleName Get-OERInventoryGroup {
            [PSCustomObject]@{
                Groups      = @(
                    [PSCustomObject]@{ displayName = 'role_sec_noid'; roleAssignable = $true; dynamic = $false; members = @(); eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; principalType = 'User'; accessType = 'Member' }) }
                )
                Unread      = @(); Causes = @(); PimLeftOut = @(); SharedNames = @()
            }
        }
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include)
            $Inv = [PSCustomObject]@{
                Version = '1.0'; Groups = @(); AdministrativeUnits = @(
                    [PSCustomObject]@{ displayName = 'Blank AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = @($null, ''); scopedRoles = @() }
                    [PSCustomObject]@{ displayName = 'Unread Restricted AU'; description = $null; restricted = $true; dynamic = $false; hiddenMembership = $false; members = $null; scopedRoles = @() }
                ); Catalogs = @(); AccessPackages = @(); AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
        }
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-noid'); Include = @('Groups', 'AdministrativeUnits') }
        # Reach proofs: the group is in the document, and both restricted units were read.
        $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_noid')
        @($Inv.administrativeUnits).Count | Should -Be 2
        @($Run.Warnings | Where-Object { $_ -like '*restricted management*' }).Count | Should -Be 0
        @((Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath) -split '\r?\n' | Where-Object { $_ -like '- *' }).Count | Should -Be 0
    }
    It 'names no group when the export includes Groups but not AdministrativeUnits' {
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-groups-only'); Include = @('Groups') }
        # Reach proof: the groups were read and kept, and no unit was.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventoryGroup -Times 1 -Exactly
        $Inv = Get-Content (Join-Path $Run.Result.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.groups).Count | Should -Be 3
        @($Inv.administrativeUnits).Count | Should -Be 0
        @($Run.Warnings | Where-Object { $_ -like '*restricted management*' }).Count | Should -Be 0
        ((Get-RuxReadmeSection -BundlePath $Run.Result.BundlePath) -replace '\s+', ' ') | Should -Match ([regex]::Escape('None. No group that `inventory.json` writes'))
    }

    It 'writes the warning under -WhatIf too, and no bundle' {
        $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-whatif'); Include = @('Groups', 'AdministrativeUnits'); WhatIf = $true }
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Include -contains 'AdministrativeUnits' }
        $Run.Warnings | Should -Be @(Get-RuxExportWarning -Count 2)
        Test-Path -LiteralPath $Run.Result.BundlePath | Should -BeFalse
    }

    It 'stops at its own warning under -WarningAction Stop, before the bundle is written' {
        $Out = Join-Path $TestDrive 'rux-stop'
        $Thrown = { Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits -WarningAction Stop } | Should -Throw -PassThru
        $Thrown.Exception.Message | Should -BeLike '*group(s) written to inventory.json use PIM for Groups*restricted management administrative unit*'
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter { $Include -contains 'AdministrativeUnits' }
        Test-Path -LiteralPath $Out | Should -BeFalse
    }

    Context 'the export''s own apply-schema self-check' {
        # Test-OERStructureSchema is NOT mocked away here: the mock calls the real validator through and
        # keeps what it returned. Exported groups carry no object id and no administrativeUnit, and the
        # units list a group member by its object id, so the validator's restricted unit Warning, which
        # reads a group's declared id, its displayName or its administrativeUnit, cannot see the link in
        # an exported document: the export's own warning and README section are what name these groups.
        BeforeEach {
            Mock -ModuleName $script:moduleName Test-OERStructureSchema {
                $Result = & $script:RuxRealValidate @PesterBoundParameters
                $script:RuxSelfChecks.Add($Result)
                $Result
            }
        }

        It 'passes the real self-check with no finding about a restricted unit, although the export names two groups' {
            $Run = Invoke-RuxExport -Splat @{ OutputPath = (Join-Path $TestDrive 'rux-selfcheck'); Include = @('Groups', 'AdministrativeUnits') }
            # Reach proofs: the export named both groups, and the real validator ran over the document.
            $Run.Warnings | Should -Contain (Get-RuxExportWarning -Count 2)
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Times 1 -Exactly
            $script:RuxSelfChecks.Count | Should -Be 1
            $script:RuxSelfChecks[0].Valid | Should -BeTrue
            @($script:RuxSelfChecks[0].Errors | Where-Object { $_.Message -like '*restricted management*' }).Count | Should -Be 0
            @($Run.Warnings | Where-Object { $_ -like '*did not pass apply-schema validation*' }).Count | Should -Be 0
        }
    }
}
