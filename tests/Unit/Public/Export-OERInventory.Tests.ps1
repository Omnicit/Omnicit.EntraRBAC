BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Export-OERInventory (core)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        # An inventory with one RBAC-relevant group and one plain group.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @(
                    [PSCustomObject]@{ displayName = 'role_sec_admin'; roleAssignable = $true;  dynamic = $false; members = @('person26@example.com'); eligibility = @() },
                    [PSCustomObject]@{ displayName = 'PlainTeam';      roleAssignable = $false; dynamic = $false; members = @('person27@example.com','person28@example.com'); eligibility = @() }
                )
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
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

    It 'passes -IncludeId to the internal Get-OERInventory call for the roster join key' {
        Export-OERInventory -OutputPath $TestDrive -Include Groups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -ParameterFilter {
            $IncludeId -eq $true
        }
    }

    It 'joins the roster member count by object id, not display name' {
        # Two groups sharing the display name 'dup' with different ids and different member
        # counts. A display-name-only join would attribute the LAST write's count to both rows;
        # keying on id must attribute each row its own group's count.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $IncludeId)
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
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @($G1, $G2)
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $IncludeId)
            $G1 = [PSCustomObject]@{
                displayName = 'role_sec_admin'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @()
            }
            if ($IncludeId) {
                $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'id-A' -Force
            }
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @($G1)
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $IncludeId)
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
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @($G1)
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; members = @('person26@example.com'); eligibility = @() })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory'); $inv
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
        # The inventory read is security-enabled-scoped, so it returns the ONE security group only.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $IncludeId)
            $G1 = [PSCustomObject]@{
                displayName = 'role_sec_admin'; roleAssignable = $true; dynamic = $false
                members = @('person26@example.com'); eligibility = @()
            }
            if ($IncludeId) { $G1 | Add-Member -NotePropertyName id -NotePropertyValue 'g-sec' -Force }
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @($G1)
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        # And the widening is not smuggled in from this side either: Export never passes a
        # -GroupFilter, so Get-OERInventory keeps its own 'securityEnabled eq true' default.
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -Times 1 -Exactly -ParameterFilter {
            -not $GroupFilter
        }
    }
}

Describe 'Export-OERInventory (Azure walk)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
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

    It 'reads PIM policies with -AllRolesAtScope when RoleManagementPolicies is included' {
        Export-OERInventory -OutputPath $TestDrive -Include RoleManagementPolicies | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERInventory -ParameterFilter {
            ($Include -contains 'RoleManagementPolicies') -and $AllRolesAtScope -eq $true
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
        # Get-OERInventory now reports a collection it could not read as a non-terminating
        # InventoryPartial carrying the section/displayName/key triple on TargetObject, and returns
        # a document whose members key is an explicit null.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            Write-Error -Message 'This inventory is PARTIAL: groups/role_sec_team members could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded `
                -TargetObject 'groups/role_sec_team/members' -ErrorAction Continue
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        Mock -ModuleName $script:moduleName Get-OERInventory {
            param($Include, $IncludeId, $ErrorAction)
            $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
            Write-Error -Message 'This inventory is PARTIAL: groups/role_sec_team members could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded `
                -TargetObject 'groups/role_sec_team/members' -ErrorAction $Ea
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }
        # A real group so groupsRoster.json is genuinely written: the assertion below is that the
        # WHOLE bundle survives, not merely inventory.json. The Describe-level mock returns nothing,
        # which skips the roster file and would make that half of the assertion unfalsifiable.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $true; GroupType = 'Assigned' }
        }

        $Root = Join-Path $TestDrive 'eastop'
        $Caught = $null
        try {
            Export-OERInventory -OutputPath $Root -Include Groups -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
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
    }

    It 'falls back to the error message when the partial error carries no TargetObject' {
        # A record whose TargetObject is empty must not become a blank IncompleteReads entry: the
        # summary would then count a gap it cannot name.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            Write-Error -Message 'This inventory is PARTIAL: groups/role_sec_team members could not be read.' `
                -ErrorId 'InventoryPartial' -Category LimitsExceeded -ErrorAction Continue
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir2') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        @($Bundle.IncompleteReads).Count | Should -Be 1
        @($Bundle.IncompleteReads)[0] | Should -Not -BeNullOrEmpty
        @($Bundle.IncompleteReads)[0] | Should -Match 'role_sec_team'
    }

    It 'reports an empty IncompleteReads and raises no InventoryPartial when every collection was read' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @() })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir3') -Include Groups `
            -WarningAction SilentlyContinue -ErrorVariable ExErr -ErrorAction SilentlyContinue
        $Bundle.PSObject.Properties.Name | Should -Contain 'IncompleteReads'
        @($Bundle.IncompleteReads).Count | Should -Be 0
        @($ExErr | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Export-OERInventory' }).Count | Should -Be 0
    }

    It 'reports an unknown member count rather than one for a group whose members were not read' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @('person26@example.com','person27@example.com') })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
        # on evidence that does not exist.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; description = $null; members = @() })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir6') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        $Inv.Version | Should -Be '1.0'
        @($Inv.Groups).Count |
            Should -Be 0 -Because 'an absent eligibility key is not evidence of any eligibility'
    }

    It 'still classes a group as RBAC-relevant on a genuinely declared eligibility' {
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'PlainTeam'; roleAssignable = $false; dynamic = $false; description = $null; members = @()
                        eligibility = @([PSCustomObject]@{ principal = 'person30@example.com'; accessType = 'member' }) })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
        }

        $Bundle = Export-OERInventory -OutputPath (Join-Path $TestDrive 'ir7') -Include Groups `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Inv = Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
        @($Inv.Groups).Count | Should -Be 1
    }

    It 'writes the explicit null through to inventory.json rather than an empty array' {
        # End-to-end: the file Invoke-OERStructure -Prune actually reads must carry null, since an
        # empty array there is a DECLARED empty membership and prunes every live member.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = $null })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $inv
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
}

Describe 'Export-OERInventory (directory role sections)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
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
            param($Include, $IncludeId, $AllDirectoryRolePolicies)
            $Policy = [PSCustomObject]@{ role = 'Reports Reader'; activationMaxHours = 8 }
            $Assignment = [PSCustomObject]@{ role = 'Reports Reader'; principal = 'person26@example.com'; assignmentType = 'Eligible' }
            if ($IncludeId) {
                $Policy | Add-Member -NotePropertyName id -NotePropertyValue 'pol-1' -Force
                $Assignment | Add-Member -NotePropertyName id -NotePropertyValue 'sched-1' -Force
            }
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
            $Ap.PSObject.Properties.Name | Should -Not -Contain 'id' -Because 'the id stamped for the roster join is stripped, the null is not'
        }
        # Only the collection that was not read is null: the catalog read succeeded and stays a fact.
        $Catalog = @((Get-Content (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json).catalogs)[0]
        @($Catalog.resources).Count | Should -Be 1
        $Catalog.resources[0].name | Should -Be 'role_sec_x'
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
    # BL-05 / decision A9. The export reads through the REAL Get-OERInventory, so what is mocked is the
    # three readers it calls, healthy (and empty) by default; a test swaps in the one that fails. A
    # list that could not be read is written as [] -- the same file a tenant with none produces -- so
    # the only thing that tells the two apart is the partial signal reaching the bundle summary.
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
    # IncompleteReads as groupsRoster -- by this cmdlet, not by Get-OERInventory, which never sees it.
    # Get-OERInventory is mocked here: the inventory read is healthy and returns the one group, and
    # the roster read (Get-OERGroup -All) is the only thing under test.
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
        # The filtered group read succeeds: the inventory comes back with its one security group.
        Mock -ModuleName $script:moduleName Get-OERInventory {
            $Inv = [PSCustomObject]@{
                Version = '1.0'
                Groups = @([PSCustomObject]@{ id = 'g-1'; displayName = 'role_sec_team'; roleAssignable = $true; dynamic = $false; description = $null; members = @() })
                AdministrativeUnits = @(); Catalogs = @(); AccessPackages = @()
                AccessReviews = @(); RoleAssignments = @(); RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Inv
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
            Should -BeLike '*1 partial Entra ID read entry(ies) name collections that could not be read, or could not be written without an empty name, and are NOT stated as facts in the bundle*'
        $Partial[0].Exception.Message |
            Should -BeLike '*A section named alone is written as an empty array, which does not mean the tenant has none, and the entry groupsRoster means groupsRoster.json is empty since the group roster could not be read*'
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
