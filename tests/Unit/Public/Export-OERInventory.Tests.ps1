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

Describe 'Export-OERInventory (partial coverage is reported, not swallowed)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERConfiguration {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
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
            Should -Match '1 partial Entra ID read report\(s\)' -Because 'the count names what it actually counts'
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
