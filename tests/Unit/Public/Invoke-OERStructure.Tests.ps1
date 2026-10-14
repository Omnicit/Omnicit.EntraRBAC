BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    # BL-125: the group handler asks Read-OERGroupPimHold whether PIM for Groups holds a member or
    # owner before it adds or prunes one. Answered "read, nothing held" for every test in this file,
    # so a fixture that adds or prunes a member never reaches the real reader (and through it the
    # transport) and keeps its meaning. Sync-OERStructureGroup.Tests.ps1 tests the hold itself.
    Mock -ModuleName $script:moduleName Read-OERGroupPimHold { [PSCustomObject]@{ Read = $true; Held = @{}; Cause = $null } }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Invoke-OERStructure' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        InModuleScope $script:moduleName {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock Sync-OERStructureGroup {
                $script:Order.Add('groups')
                ConvertTo-OERStructureResult -Section 'groups' -Item $Item.displayName -Action 'Created'
            }
            Mock Sync-OERStructureAdministrativeUnit { $script:Order.Add('administrativeUnits') }
            Mock Sync-OERStructureCatalog { $script:Order.Add('catalogs') }
            Mock Sync-OERStructureAccessPackage { $script:Order.Add('accessPackages') }
            Mock Sync-OERStructureAccessReview { $script:Order.Add('accessReviews') }
            Mock Sync-OERStructureRoleAssignment { $script:Order.Add('roleAssignments') }
            Mock Sync-OERStructureRoleManagementPolicy { $script:Order.Add('roleManagementPolicies') }
            # The engine resolves every roleAssignments scope before dispatch; no test here may reach
            # the ARM transport through that pre-pass.
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { "/subscriptions/$Subscription" } elseif ($ManagementGroup) { "/providers/Microsoft.Management/managementGroups/$ManagementGroup" } else { $Scope }
            }
        }
    }

    It 'aborts before any handler when the schema is invalid' {
        Invoke-OERStructure -Json '{ "groups": [] }' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureGroup -Times 0 }
    }

    It 'dispatches sections in the hardcoded dependency order' {
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureRoleAssignment { $script:Order.Add('roleAssignments') }
        }
        $json = '{ "version":"1.0", "roleManagementPolicies":[{"scope":"sub:Prod","role":"Reader"}], "roleAssignments":[{"scope":"sub:Prod","role":"Reader","principal":"a"}], "groups":[{"displayName":"g"}], "catalogs":[{"displayName":"c"}] }'
        Invoke-OERStructure -Json $json -IncludeARM -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            ($script:Order.IndexOf('groups'))          | Should -BeLessThan ($script:Order.IndexOf('catalogs'))
            ($script:Order.IndexOf('catalogs'))        | Should -BeLessThan ($script:Order.IndexOf('roleAssignments'))
            ($script:Order.IndexOf('roleAssignments')) | Should -BeLessThan ($script:Order.IndexOf('roleManagementPolicies'))
        }
    }

    It 'passes -IncludeARM to auth when an Azure section is present' {
        Invoke-OERStructure -Json '{ "version":"1.0", "roleAssignments":[{"scope":"sub:Prod","role":"Reader","principal":"g"}] }' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $IncludeARM -eq $true }
    }

    It 'does NOT request ARM for a pure Entra document without -IncludeARM' {
        Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}] }' -Include Groups -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { -not $IncludeARM }
    }

    It 'does NOT request ARM on the default -Include when the document has no Azure sections' {
        # Default -Include lists the Azure section names, but the document declares none of them,
        # so ARM must NOT be requested (no unnecessary ARM token).
        Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}], "catalogs":[{"displayName":"c"}] }' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { -not $IncludeARM }
    }

    It 'limits to -Include sections' {
        Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}], "catalogs":[{"displayName":"c"}] }' -Include Groups -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            Should -Invoke Sync-OERStructureCatalog -Times 0
            Should -Invoke Sync-OERStructureGroup -Times 1
        }
    }

    It 'returns tagged StructureResult records' {
        $r = @(Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}] }' -Include Groups -Confirm:$false)
        $r[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureResult'
    }

    It 'continues past a failing section handler' {
        InModuleScope $script:moduleName { Mock Sync-OERStructureGroup { throw 'boom' } }
        Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}], "catalogs":[{"displayName":"c"}] }' -Include Groups,Catalogs -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureCatalog -Times 1 }
    }

    It 'scrubs the bearer-hygiene record when a section handler fails' {
        # Drives the section-dispatch catch in source/Public/Invoke-OERStructure.ps1 (the
        # "& $Section.Handler" try). The handler is where every Graph and ARM call of an apply run
        # happens, so a record surfacing from it can carry the bearer header. CLAUDE.md SECURITY
        # rule 6 makes Remove-OERErrorRecord -Record $PSItem the first statement of that catch.
        InModuleScope $script:moduleName { Mock Sync-OERStructureGroup { throw 'transport failure' } }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}] }' `
            -Include Groups -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'sets -ReconcileScope on only the first roleAssignment of each scope' {
        InModuleScope $script:moduleName {
            $script:ReconcileFlags = [System.Collections.Generic.List[bool]]::new()
            Mock Sync-OERStructureRoleAssignment { $script:ReconcileFlags.Add([bool]$ReconcileScope) }
        }
        $json = '{ "version":"1.0", "roleAssignments":[ {"scope":"sub:Prod","role":"Reader","principal":"a"}, {"scope":"sub:Prod","role":"Owner","principal":"b"}, {"scope":"mg:Plat","role":"Reader","principal":"c"} ] }'
        Invoke-OERStructure -Json $json -IncludeARM -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            # first sub:Prod -> $true, second sub:Prod -> $false, mg:Plat -> $true
            @($script:ReconcileFlags) | Should -Be @($true, $false, $true)
        }
    }

    It 'treats an explicit null roleAssignments section as not declared: no scope pre-pass, no row, no abort' {
        # The validator reads an explicit null as "not declared", yet @($null) is ONE element, and the
        # scope pre-pass runs outside the per-entry try/catch: a null entry made it throw a
        # parameter-binding error that aborted the whole run inside an operator's try/catch, after the
        # earlier sections had been written. The engine drops the null before the pre-pass and skips
        # the section.
        InModuleScope $script:moduleName {
            $script:RaPreCalls = 0
            Mock Resolve-OERStructureRoleAssignmentScope { $script:RaPreCalls++; @() }
        }
        $Caught = $null
        $Rows = @()
        try {
            $Rows = @(Invoke-OERStructure -Json '{ "version":"1.0", "groups":[{"displayName":"g"}], "roleAssignments": null }' `
                    -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable NullSectionErr)
        } catch {
            $Caught = $PSItem
        }

        # Positive proof first: the run completed and the declared group section was applied.
        $Caught | Should -BeNullOrEmpty
        $GroupRows = @($Rows | Where-Object { $_.Section -eq 'groups' })
        $GroupRows.Count | Should -Be 1
        $GroupRows[0].Item | Should -Be 'g'
        $GroupRows[0].Action | Should -Be 'Created'
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureGroup -Times 1 -Exactly }

        # The null section is skipped: no scope pre-pass, no handler call, no row, no error record.
        InModuleScope $script:moduleName {
            $script:RaPreCalls | Should -Be 0
            Should -Invoke Resolve-OERStructureRoleAssignmentScope -Times 0
            Should -Invoke Sync-OERStructureRoleAssignment -Times 0
        }
        @($Rows | Where-Object { $_.Section -eq 'roleAssignments' }).Count | Should -Be 0
        @($NullSectionErr).Count | Should -Be 0
    }

    It 'accepts a piped inventory object via -InputObject and settles cleanly under -WhatIf' {
        $Inv = [pscustomobject]@{
            Version               = '1.0'
            Groups                = @()
            AdministrativeUnits   = @()
            Catalogs              = @()
            AccessPackages        = @()
            AccessReviews         = @()
            RoleAssignments       = @()
            RoleManagementPolicies = @()
        }
        $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
        { $Inv | Invoke-OERStructure -WhatIf } | Should -Not -Throw
    }

    It 'accepts a piped file path -InputObject and reads the files content instead of failing on a serialized string' {
        # Same -InputObject parameter set as Test-OERStructure, same reader underneath: a piped path
        # string must reach the same file-reading branch here too, not just in Test-OERStructure.
        # NOTE: Invoke-OERStructure catches a read failure internally and converts it to a
        # non-terminating WriteError -- it never throws -- so "Should -Not -Throw" alone would pass
        # whether or not the fix exists. Assert the -ErrorVariable is empty instead, which is the
        # only observable signal a caller (or this test) can use to tell success from failure here.
        $P = Join-Path $TestDrive 'invoke-piped.json'
        Set-Content -LiteralPath $P -Value '{ "version": "1.0" }' -Encoding utf8
        $P | Invoke-OERStructure -WhatIf -ErrorVariable InvokeErrors -ErrorAction SilentlyContinue | Out-Null
        $InvokeErrors | Should -BeNullOrEmpty
    }

    It 'passes a normalized (canonically cased) value to the section handler, never the raw casing' {
        InModuleScope $script:moduleName {
            $script:CapturedPrincipalTypes = [System.Collections.Generic.List[string]]::new()
            Mock Sync-OERStructureRoleAssignment { $script:CapturedPrincipalTypes.Add([string]$Item.principalType) }
        }
        $json = '{ "version":"1.0", "roleAssignments":[{"scope":"/subscriptions/x","role":"Reader","principal":"p","principalType":"group"}] }'
        Invoke-OERStructure -Json $json -IncludeARM -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            @($script:CapturedPrincipalTypes) | Should -BeExactly @('Group')
        }
    }

    It 'dispatches a handler for a document whose root keys are PascalCase (back-compat with earlier module versions)' {
        $json = '{ "Version":"1.0", "Groups":[{"displayName":"g"}] }'
        Invoke-OERStructure -Json $json -Include Groups -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            Should -Invoke Sync-OERStructureGroup -Times 1 -Exactly
        }
    }

    It 'is exported' { Get-Command -Module $script:moduleName -Name Invoke-OERStructure | Should -Not -BeNullOrEmpty }

    Context 'administrative unit pre-pass for a group created into it' {
        It 'creates a declared administrative unit before a group that declares it' {
            InModuleScope $script:moduleName {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                Mock Initialize-OERAuth { }
                Mock Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Findings = @() } }
                Mock Sync-OERStructureAdministrativeUnit {
                    param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly)
                    $script:Order.Add($(if ($EnsureOnly) { 'au-ensure' } else { 'au-full' }))
                }
                Mock Sync-OERStructureGroup { $script:Order.Add('group') }
                $Json = @'
{ "version": "1.0",
  "groups": [ { "displayName": "role_sec_x", "administrativeUnit": "AU-1" } ],
  "administrativeUnits": [ { "displayName": "AU-1" } ] }
'@
                $null = Invoke-OERStructure -Json $Json -Confirm:$false
                $script:Order[0] | Should -BeExactly 'au-ensure'
                [int]$script:Order.IndexOf('au-ensure') | Should -BeLessThan ([int]$script:Order.IndexOf('group'))
                [int]$script:Order.IndexOf('group')     | Should -BeLessThan ([int]$script:Order.IndexOf('au-full'))
            }
        }

        It 'runs no pre-pass when no group declares an administrativeUnit' {
            InModuleScope $script:moduleName {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                Mock Initialize-OERAuth { }
                Mock Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Findings = @() } }
                Mock Sync-OERStructureAdministrativeUnit {
                    param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly)
                    $script:Order.Add($(if ($EnsureOnly) { 'au-ensure' } else { 'au-full' }))
                }
                Mock Sync-OERStructureGroup { $script:Order.Add('group') }
                $Json = @'
{ "version": "1.0",
  "groups": [ { "displayName": "role_sec_x" } ],
  "administrativeUnits": [ { "displayName": "AU-1" } ] }
'@
                $null = Invoke-OERStructure -Json $Json -Confirm:$false
                $script:Order | Should -Not -Contain 'au-ensure'
            }
        }

        It 'runs no pre-pass for an administrative unit no group names' {
            InModuleScope $script:moduleName {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                $script:EnsuredItems = [System.Collections.Generic.List[string]]::new()
                Mock Initialize-OERAuth { }
                Mock Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Findings = @() } }
                Mock Sync-OERStructureAdministrativeUnit {
                    param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly)
                    if ($EnsureOnly) {
                        $script:Order.Add('au-ensure')
                        $script:EnsuredItems.Add([string]$Item.displayName)
                    } else {
                        $script:Order.Add('au-full')
                    }
                }
                Mock Sync-OERStructureGroup { $script:Order.Add('group') }
                $Json = @'
{ "version": "1.0",
  "groups": [ { "displayName": "role_sec_x", "administrativeUnit": "AU-1" } ],
  "administrativeUnits": [ { "displayName": "AU-1" }, { "displayName": "AU-2" } ] }
'@
                $null = Invoke-OERStructure -Json $Json -Confirm:$false
                @($script:Order | Where-Object { $_ -eq 'au-ensure' }).Count | Should -Be 1
                @($script:EnsuredItems) | Should -Be @('AU-1')
            }
        }

        It 'under -WhatIf, the pre-pass and main pass emit two administrativeUnits records with different Details for the same missing unit' {
            InModuleScope $script:moduleName {
                $script:Order = [System.Collections.Generic.List[string]]::new()
                Mock Initialize-OERAuth { }
                Mock Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Findings = @() } }
                # Mirrors the real handler's -WhatIf create-skip Detail differentiation
                # (source/Private/Sync-OERStructureAdministrativeUnit.ps1) so this test can assert the
                # two rows Invoke-OERStructure assembles from the pre-pass and the main pass read as a
                # sequence rather than a repeat.
                Mock Sync-OERStructureAdministrativeUnit {
                    param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly)
                    $Detail = if ($EnsureOnly) {
                        "would create administrative unit '$($Item.displayName)' first, so the group that declares it can be created"
                    } else {
                        "would create administrative unit $($Item.displayName)"
                    }
                    ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item $Item.displayName -Action 'Skipped' -Detail $Detail
                }
                Mock Sync-OERStructureGroup { }
                $Json = @'
{ "version": "1.0",
  "groups": [ { "displayName": "role_sec_x", "administrativeUnit": "AU-1" } ],
  "administrativeUnits": [ { "displayName": "AU-1" } ] }
'@
                $Records = @(Invoke-OERStructure -Json $Json -WhatIf)
                $AuRecords = @($Records | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Item -eq 'AU-1' })
                $AuRecords.Count | Should -Be 2
                (@($AuRecords.Detail) | Select-Object -Unique).Count | Should -Be 2
            }
        }

        It 'hands the pre-pass and the groups, administrativeUnits, catalogs, accessPackages and accessReviews handlers one rename map per document (BL-128, A5)' {
            # The map is how a reference to a name the same run gives an object reaches that object, so
            # every handler that fills or reads it must see the SAME map, and a second piped document
            # must start from an empty one. The accessReviews handler reads it for the access package
            # and assignment policy a review names (BL-128 part 2).
            InModuleScope $script:moduleName {
                $script:SeenMap = [System.Collections.Generic.List[object]]::new()
                Mock Initialize-OERAuth { }
                Mock Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Findings = @() } }
                Mock Sync-OERStructureAdministrativeUnit {
                    param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly, $CreatedUnitMembership, $RenameMap)
                    $Call = if ($EnsureOnly) { "au-ensure $($Item.displayName)" } else { "au-full $($Item.displayName)" }
                    $script:SeenMap.Add([PSCustomObject]@{ Call = $Call; Map = $RenameMap })
                }
                Mock Sync-OERStructureGroup {
                    param($Item, $Caller, $Prune, $TenantAlias, $CreatedUnitMembership, $RenameMap)
                    $script:SeenMap.Add([PSCustomObject]@{ Call = "group $($Item.displayName)"; Map = $RenameMap })
                }
                Mock Sync-OERStructureCatalog {
                    param($Item, $Caller, $Prune, $TenantAlias, $PlannedCatalog, $RenameMap)
                    $script:SeenMap.Add([PSCustomObject]@{ Call = "catalog $($Item.displayName)"; Map = $RenameMap })
                }
                Mock Sync-OERStructureAccessPackage {
                    param($Item, $Caller, $Prune, $TenantAlias, $PlannedCatalog, $RenameMap)
                    $script:SeenMap.Add([PSCustomObject]@{ Call = "package $($Item.displayName)"; Map = $RenameMap })
                }
                Mock Sync-OERStructureAccessReview {
                    param($Item, $Caller, $Prune, $TenantAlias, $RenameMap)
                    $script:SeenMap.Add([PSCustomObject]@{ Call = "review $($Item.displayName)"; Map = $RenameMap })
                }
                $Doc1 = ('{ "version": "1.0", ' +
                    '"groups": [ { "displayName": "G1", "administrativeUnit": "AU-1" } ], ' +
                    '"administrativeUnits": [ { "displayName": "AU-1" } ], ' +
                    '"catalogs": [ { "displayName": "CAT-1" } ], ' +
                    '"accessPackages": [ { "displayName": "AP-1", "catalog": "CAT-1" } ], ' +
                    '"accessReviews": [ { "displayName": "AR-1" } ] }') | ConvertFrom-Json
                $Doc2 = '{ "version": "1.0", "catalogs": [ { "displayName": "CAT-2" } ] }' | ConvertFrom-Json
                $null = @($Doc1, $Doc2 | Invoke-OERStructure -Confirm:$false -ErrorAction Stop)

                $Calls = @($script:SeenMap)
                @($Calls | ForEach-Object { $_.Call }) | Should -Be @('au-ensure AU-1', 'group G1', 'au-full AU-1', 'catalog CAT-1', 'package AP-1', 'review AR-1', 'catalog CAT-2')
                Should -Invoke Sync-OERStructureAccessReview -Times 1 -Exactly
                $First = $Calls[0].Map
                ($null -ne $First) | Should -BeTrue -Because 'the pre-pass must receive a map'
                ($First -is [System.Collections.Generic.Dictionary[string, object]]) | Should -BeTrue
                $First.Comparer.Equals('administrativeunits|AU-1', 'administrativeUnits|au-1') | Should -BeTrue -Because 'the keys are compared without regard to letter case'
                for ($Index = 1; $Index -le 5; $Index++) {
                    [object]::ReferenceEquals($Calls[$Index].Map, $First) | Should -BeTrue -Because "$($Calls[$Index].Call) must get the map the pre-pass got"
                }
                ($null -ne $Calls[6].Map) | Should -BeTrue -Because 'the second document must receive a map'
                [object]::ReferenceEquals($Calls[6].Map, $First) | Should -BeFalse -Because 'each document gets a map of its own'
            }
        }
    }
}

Describe 'Invoke-OERStructure handler-failure row' {
    # The outer per-item catch used to hardcode -Item '(item)', so a run over many entries reported
    # every handler-level failure against the same anonymous label. The failing row is exactly the
    # one an operator has to act on, and without the name it is unactionable. Observed live in two
    # separate checks.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        # The engine resolves every roleAssignments scope before dispatch; no test here may reach the
        # ARM transport through that pre-pass.
        InModuleScope $script:moduleName {
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { "/subscriptions/$Subscription" } elseif ($ManagementGroup) { "/providers/Microsoft.Management/managementGroups/$ManagementGroup" } else { $Scope }
            }
        }
    }

    It 'names the failing item by displayName instead of a placeholder' {
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureGroup { throw [System.Exception]::new('handler blew up') }
        }
        $Json = '{ "version":"1.0", "groups":[{"displayName":"role_sec_named"}] }'
        $Records = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue)

        $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
        # Non-vacuity: the row must exist at all, or the two assertions after it prove nothing.
        @($Failed).Count | Should -Be 1 -Because 'the throwing handler must still produce one Failed row'
        $Failed[0].Item | Should -Be 'role_sec_named'
        $Failed[0].Item | Should -Not -Be '(item)'
    }

    It 'names an ARM item by role, principal and scope, which carry no displayName' {
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureRoleAssignment { throw [System.Exception]::new('handler blew up') }
        }
        $Json = '{ "version":"1.0", "roleAssignments":[{"scope":"sub:Prod","role":"Reader","principal":"svc-a"}] }'
        $Records = @(Invoke-OERStructure -Json $Json -IncludeARM -Confirm:$false -ErrorAction SilentlyContinue)

        $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
        @($Failed).Count | Should -Be 1
        $Failed[0].Item | Should -Be 'Reader -> svc-a @ sub:Prod' -Because (
            'the label must match what Sync-OERStructureRoleAssignment composes for its own rows')
    }

    It 'falls back to the placeholder rather than failing to build the row' {
        # -Item is a mandatory non-empty string on ConvertTo-OERStructureResult, so an entry
        # carrying neither displayName nor role must not turn this catch into a binding failure
        # that loses the original error. accessReviews is the section whose schema allows it.
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureAccessReview { throw [System.Exception]::new('handler blew up') }
        }
        $Json = '{ "version":"1.0", "accessReviews":[{"displayName":"","accessPackage":"ap","assignmentPolicy":"pol"}] }'
        $Records = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue)

        $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
        @($Failed).Count | Should -Be 1
        $Failed[0].Item | Should -Be '(item)'
    }
}

Describe 'Invoke-OERStructure omitted-collection prune warning' {
    # Five collections are reconciled against an empty declared set when their key is omitted, so
    # -Prune removes every live entry in them. The engine lists those keys in one warning, after
    # authentication and before the administrative unit pre-pass -- the first code that can write.
    # Warnings are captured with 3>&1 so their relative ORDER is preserved: each mocked handler writes
    # its own MARKER warning, and the engine's warning has to precede every one of them.
    BeforeAll {
        function Get-WarningMessage {
            param([object[]]$Stream)
            @($Stream | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        }
        function Get-EngineWarning {
            param([string[]]$Message)
            @($Message | Where-Object { $_ -like 'Invoke-OERStructure: -Prune is set*' })
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureGroup { Write-Warning 'MARKER: Sync-OERStructureGroup ran' }
            Mock Sync-OERStructureAdministrativeUnit {
                param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly)
                Write-Warning "MARKER: Sync-OERStructureAdministrativeUnit ran (EnsureOnly=$([bool]$EnsureOnly))"
            }
            Mock Sync-OERStructureCatalog { Write-Warning 'MARKER: Sync-OERStructureCatalog ran' }
            Mock Sync-OERStructureAccessPackage { Write-Warning 'MARKER: Sync-OERStructureAccessPackage ran' }
        }
    }

    It 'writes one warning under -Prune -WhatIf before the administrative unit pre-pass and the first handler run' {
        # g1 omits members and names AU-1, so the pre-pass runs; AU-1 declares both of its collections.
        $Json = '{ "version": "1.0", ' +
            '"groups": [ { "displayName": "g1", "administrativeUnit": "AU-1" } ], ' +
            '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "g1" ], "scopedRoles": [] } ] }'
        $Messages = @(Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -WhatIf 3>&1))

        $EngineAt = @(for ($I = 0; $I -lt $Messages.Count; $I++) { if ($Messages[$I] -like 'Invoke-OERStructure: -Prune is set*') { $I } })
        $MarkerAt = @(for ($I = 0; $I -lt $Messages.Count; $I++) { if ($Messages[$I] -like 'MARKER:*') { $I } })
        $EngineAt.Count | Should -Be 1
        # Non-vacuity: the pre-pass and the handlers really ran, or the order proves nothing.
        $MarkerAt.Count | Should -Be 3
        $Messages[$MarkerAt[0]] | Should -BeExactly 'MARKER: Sync-OERStructureAdministrativeUnit ran (EnsureOnly=True)'
        $EngineAt[0] | Should -BeLessThan $MarkerAt[0]
        $EngineAt[0] | Should -Be 0
    }

    It 'names each omitted key as section, quoted item and collection, and counts them' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ], "catalogs": [ { "displayName": "c1" } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -WhatIf 3>&1)))
        $Engine.Count | Should -Be 1
        $Engine[0] | Should -BeLike "*the document omits 2 collection key(s)*"
        $Engine[0] | Should -BeLike "*: groups 'g1' members; catalogs 'c1' resources. Declare each key*"
    }

    It 'says would be removed under -WhatIf and will be removed without it' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
        $Planned = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -WhatIf 3>&1)))
        $Planned.Count | Should -Be 1
        $Planned[0] | Should -BeLike '*every live entry in them would be removed: *'
        $Live = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -Confirm:$false 3>&1)))
        $Live.Count | Should -Be 1
        $Live[0] | Should -BeLike '*every live entry in them will be removed: *'
    }

    It 'writes no warning without -Prune' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -WhatIf 3>&1)))
        $Engine.Count | Should -Be 0
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureGroup -Times 1 -Exactly }
    }

    It 'writes no warning when members is an explicit null' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "members": null } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -WhatIf 3>&1)))
        $Engine.Count | Should -Be 0
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureGroup -Times 1 -Exactly }
    }

    It 'writes no warning for the omitted members of a group declared dynamic' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "dynamic": true, "membershipRule": "(user.department -eq \"IT\")" } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Prune -WhatIf 3>&1)))
        $Engine.Count | Should -Be 0
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureGroup -Times 1 -Exactly }
    }

    It 'writes no warning when -Include excludes the only section that omits a key' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ], "catalogs": [ { "displayName": "c1", "resources": [] } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Include Catalogs -Prune -WhatIf 3>&1)))
        $Engine.Count | Should -Be 0
        InModuleScope $script:moduleName { Should -Invoke Sync-OERStructureCatalog -Times 1 -Exactly }
    }

    It 'lists only the keys of the sections -Include selects' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ], "catalogs": [ { "displayName": "c1" } ] }'
        $Engine = @(Get-EngineWarning (Get-WarningMessage (Invoke-OERStructure -Json $Json -Include Groups -Prune -WhatIf 3>&1)))
        $Engine.Count | Should -Be 1
        $Engine[0] | Should -BeLike "*omits 1 collection key(s)*: groups 'g1' members. Declare each key*"
        $Engine[0] | Should -Not -BeLike '*catalogs*'
    }
}

Describe 'Invoke-OERStructure output for a group that gains PIM eligibility' {
    # Add-OERGroupEligibility returns the eligibility request it made, and the group handler's output IS
    # Invoke-OERStructure's result list. Undiscarded, that request object stood among the result rows
    # (measured live 2026-09-28: a row reading only 'Action : adminAssign'). The real group handler
    # runs here; only the calls it makes are mocked.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-1' }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() }
        }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
        Mock -ModuleName $script:moduleName Add-OERGroupEligibility {
            $Request = [PSCustomObject]@{ Id = 'req-1'; Action = $Action; Status = 'Provisioned' }
            $Request.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupEligibility')
            $Request
        }
    }

    It 'returns only result rows when it adds a time-bound and a permanent eligibility' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "members": null, "eligibility": [ ' +
            '{ "principal": "person9@example.com", "durationDays": 30 }, { "principal": "person10@example.com" } ] } ] }'
        $r = @(Invoke-OERStructure -Json $Json -Include Groups -Confirm:$false -WarningAction SilentlyContinue)
        # Both call sites ran -- the time-bound entry and the permanent one.
        Should -Invoke -ModuleName $script:moduleName Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $DurationDays -eq 30 }
        Should -Invoke -ModuleName $script:moduleName Add-OERGroupEligibility -Times 2 -Exactly
        @($r | Where-Object { $_.PSObject.TypeNames[0] -ne 'Omnicit.EntraRBAC.StructureResult' }).Count | Should -Be 0
        @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'eligibility' }).Count | Should -Be 2
    }
}

Describe 'Invoke-OERStructure -Prune and a group''s service principals (A9)' {
    # No version before the typed member read saw a group's service principals, so no earlier
    # document lists them, and the group prune never removes one. The real engine and the real group
    # handler run; the live group is a mocked Get-OERGroup whose members and owners carry the
    # ObjectType Get-OERGroupRelation gives them.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-1' }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{
                Id = 'g-1'; Description = $null; MailNickname = $null; PimEligibility = @()
                Members = @(
                    [PSCustomObject]@{ id = 'u-1'; ObjectType = 'user' }
                    [PSCustomObject]@{ id = 'sp-1'; ObjectType = 'servicePrincipal' }
                )
                Owners = @(
                    [PSCustomObject]@{ id = 'u-2'; ObjectType = 'user' }
                    [PSCustomObject]@{ id = 'u-3'; ObjectType = 'user' }
                    [PSCustomObject]@{ id = 'sp-1'; ObjectType = 'servicePrincipal' }
                )
            }
        }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) $Reference }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
        Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
        Mock -ModuleName $script:moduleName Remove-OERGroupMember { }
    }

    It 'removes the undeclared user member and owner and leaves the service principal, under -Prune -Confirm:$false' {
        # u-3 is declared and stays an owner, so the last-owner guard does not hide a removal of the
        # service principal owner: only the A9 guard stands between it and Remove-OERGroupMember.
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "members": [], "owners": ["u-3"] } ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include Groups -Prune -Confirm:$false `
                -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable PruneWarnings)
        Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'u-1' -and $AccessType -ne 'owner' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'u-2' -and $AccessType -eq 'owner' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly -ParameterFilter { $PrincipalId -eq 'sp-1' }
        @($Rows | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 2
        $Withheld = @($Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "prune withheld: undeclared * 'sp-1' is a service principal*" })
        $Withheld.Count | Should -Be 2
        @($PruneWarnings | Where-Object { "$_" -match "removing undeclared (member|owner) 'u-" }).Count | Should -Be 2
        @($PruneWarnings | Where-Object { "$_" -match 'sp-1' }).Count | Should -Be 0
    }

    It 'still reports the undeclared service principal Extra without -Prune, with a hint that -Prune leaves it' {
        $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "members": ["u-1"], "owners": ["u-2", "u-3"] } ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include Groups -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
        @($Rows | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared member 'sp-1' (a service principal, which -Prune leaves in place)" }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared owner 'sp-1' (a service principal, which -Prune leaves in place)" }).Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
    }
}

Describe 'Invoke-OERStructure -Prune and a group created into an administrative unit (BL-07)' {
    # A groups[] entry's administrativeUnit is applied only when the group is created and never
    # round-trips, and the administrativeUnits section runs after groups. The document below creates
    # grp-new into AU-IT, whose members do not list it: the run that creates the membership must not
    # remove it, while an unrecorded undeclared member of the same unit is still pruned. The real
    # engine and the real handlers run; the cmdlets they call are mocked, and the live unit holds the
    # new group and one other member.
    BeforeAll {
        $script:Bl07Doc = ('{ "version": "1.0", ' +
            '"groups": [ { "displayName": "grp-new", "administrativeUnit": "AU-IT", "members": [] } ], ' +
            '"administrativeUnits": [ { "displayName": "AU-IT", "members": [], "scopedRoles": null } ] }')
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '66666666-6666-6666-6666-aaaaaaaaaaaa' }
        Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
            [PSCustomObject]@{
                Id = '66666666-6666-6666-6666-aaaaaaaaaaaa'; Description = $null; ScopedRoles = @()
                Members = @(
                    [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = 'grp-new'; Type = 'group' }
                    [PSCustomObject]@{ Id = 'u-extra'; DisplayName = 'Extra'; Type = 'user' }
                )
            }
        }
        Mock -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember { }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) $Reference }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
    }

    It 'creates the group into the unit and gives the Skipped "prune withheld" row, not a removal, under -Prune -Confirm:$false' {
        $Rows = @(Invoke-OERStructure -Json $script:Bl07Doc -Prune -Confirm:$false -ErrorAction Stop `
                -WarningAction SilentlyContinue -WarningVariable PruneWarnings)
        Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq 'AU-IT' }
        @($Rows | Where-Object { $_.Section -eq 'groups' -and $_.Action -eq 'Created' }).Count | Should -Be 1
        # Positive control: the members pass ran under -Prune and removed the unrecorded member.
        Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 0 -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
        $Withheld = @($Rows | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Skipped' })
        $Withheld.Count | Should -Be 1
        $Withheld[0].Item | Should -BeExactly 'AU-IT'
        $Withheld[0].Detail | Should -BeExactly ("prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'grp-new', " +
            'which the groups section of this run either created into this unit or, when the group already existed, found in place of creating it; ' +
            'this run does not remove that membership (our own guard, not a Graph rejection). ' +
            "The next apply with -Prune removes it unless the unit's members name the group.")
        @($Rows | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
        @($PruneWarnings | Where-Object { "$_" -match '88888888-8888-8888-8888-888888888888' }).Count | Should -Be 0
        @($PruneWarnings | Where-Object { "$_" -match "removing undeclared member 'u-extra'" }).Count | Should -Be 1
    }

    It 'keeps the list per document: a second piped document that only reconciles the unit prunes the membership the first one created' {
        # Document 1 creates grp-new into AU-IT, and its own administrativeUnits pass withholds that
        # membership. Document 2 declares only AU-IT: it is another apply, so the membership is pruned
        # there. A list kept for the whole invocation would withhold it twice.
        $Doc1 = $script:Bl07Doc | ConvertFrom-Json
        $Doc2 = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "AU-IT", "members": [], "scopedRoles": null } ] }' | ConvertFrom-Json
        $Rows = @($Doc1, $Doc2 | Invoke-OERStructure -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly
        @($Rows | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld: *' }).Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 2 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
    }

    It 'hands the administrativeUnits pass the same list the groups pass recorded into: one record in a real run, none under -WhatIf' {
        InModuleScope $script:moduleName -Parameters @{ Doc = $script:Bl07Doc } {
            param($Doc)
            Mock Sync-OERStructureAdministrativeUnit {
                param($Item, $Caller, $Prune, $TenantAlias, $EnsureOnly, $CreatedUnitMembership)
                if (-not $EnsureOnly) {
                    $script:Bl07SeenList = $CreatedUnitMembership
                    $script:Bl07SeenCount = if ($null -ne $CreatedUnitMembership) { $CreatedUnitMembership.Count } else { -1 }
                }
            }
            $script:Bl07SeenList = $null
            $null = Invoke-OERStructure -Json $Doc -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue
            $script:Bl07SeenCount | Should -Be 1
            $script:Bl07SeenList[0].GroupId | Should -BeExactly '88888888-8888-8888-8888-888888888888'
            $script:Bl07SeenList[0].AdministrativeUnit | Should -BeExactly 'AU-IT'
            $script:Bl07SeenList[0].Label | Should -BeExactly 'grp-new'

            $script:Bl07SeenList = $null
            $script:Bl07SeenCount = $null
            $Rows = @(Invoke-OERStructure -Json $Doc -Prune -WhatIf -ErrorAction Stop -WarningAction SilentlyContinue)
            @($Rows | Where-Object { $_.Section -eq 'groups' -and $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create group grp-new' }).Count | Should -Be 1
            Should -Invoke New-OERGroup -Times 1 -Exactly
            $script:Bl07SeenCount | Should -Be 0
        }
    }
}

Describe 'Invoke-OERStructure directoryRoleManagementPolicies section' {
    # The directory-role policy section is Graph-only: it is dispatched after accessReviews and before
    # the two Azure sections, and it never asks Initialize-OERAuth for an ARM token.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        InModuleScope $script:moduleName {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock Sync-OERStructureGroup { $script:Order.Add('groups') }
            Mock Sync-OERStructureAccessReview { $script:Order.Add('accessReviews') }
            Mock Sync-OERStructureDirectoryRoleManagementPolicy { $script:Order.Add('directoryRoleManagementPolicies') }
            Mock Sync-OERStructureRoleAssignment { $script:Order.Add('roleAssignments') }
            Mock Sync-OERStructureRoleManagementPolicy { $script:Order.Add('roleManagementPolicies') }
            # The engine resolves every roleAssignments scope before dispatch; no test here may reach
            # the ARM transport through that pre-pass.
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { "/subscriptions/$Subscription" } elseif ($ManagementGroup) { "/providers/Microsoft.Management/managementGroups/$ManagementGroup" } else { $Scope }
            }
        }
    }

    It 'accepts DirectoryRoleManagementPolicies in -Include and includes it by default' {
        $Param = (Get-Command -Module $script:moduleName -Name Invoke-OERStructure).Parameters['Include']
        $ValidSet = @($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
        $ValidSet | Should -Contain 'DirectoryRoleManagementPolicies'

        $Json = '{ "version":"1.0", "directoryRoleManagementPolicies":[{"role":"Reports Reader"}] }'
        Invoke-OERStructure -Json $Json -Confirm:$false | Out-Null
        Invoke-OERStructure -Json $Json -Include DirectoryRoleManagementPolicies -Confirm:$false | Out-Null
        Invoke-OERStructure -Json $Json -Include Groups -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            Should -Invoke Sync-OERStructureDirectoryRoleManagementPolicy -Times 2 -Exactly
        }
    }

    It 'dispatches the section after accessReviews and before roleAssignments' {
        $Json = '{ "version":"1.0", ' +
            '"roleManagementPolicies":[{"scope":"sub:Prod","role":"Reader"}], ' +
            '"roleAssignments":[{"scope":"sub:Prod","role":"Reader","principal":"a"}], ' +
            '"directoryRoleManagementPolicies":[{"role":"Reports Reader"}], ' +
            '"accessReviews":[{"displayName":"r","accessPackage":"ap","assignmentPolicy":"pol"}], ' +
            '"groups":[{"displayName":"g","members":null}] }'
        Invoke-OERStructure -Json $Json -IncludeARM -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            @($script:Order) | Should -Be @('groups', 'accessReviews', 'directoryRoleManagementPolicies', 'roleAssignments', 'roleManagementPolicies')
        }
    }

    It 'does not request an ARM token for a document holding only the directory section' {
        Invoke-OERStructure -Json '{ "version":"1.0", "directoryRoleManagementPolicies":[{"role":"Reports Reader"}] }' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly
        InModuleScope $script:moduleName {
            Should -Invoke Sync-OERStructureDirectoryRoleManagementPolicy -Times 1 -Exactly
        }
    }

    It 'labels a handler failure with the entry role' {
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureDirectoryRoleManagementPolicy { throw [System.Exception]::new('handler blew up') }
        }
        $Json = '{ "version":"1.0", "directoryRoleManagementPolicies":[{"role":"Reports Reader"}] }'
        $Records = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue)
        $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
        @($Failed).Count | Should -Be 1
        $Failed[0].Section | Should -BeExactly 'directoryRoleManagementPolicies'
        $Failed[0].Item | Should -BeExactly 'Reports Reader'
    }
}

Describe 'Invoke-OERStructure directoryRoleAssignments section' {
    # The directory role assignment section is Graph-only: it is dispatched right after the directory
    # role policies (so a policy that must allow a permanent assignment is applied first) and before
    # the two Azure sections, and it never asks Initialize-OERAuth for an ARM token.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        InModuleScope $script:moduleName {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock Sync-OERStructureGroup { $script:Order.Add('groups') }
            Mock Sync-OERStructureAdministrativeUnit { $script:Order.Add('administrativeUnits') }
            Mock Sync-OERStructureCatalog { $script:Order.Add('catalogs') }
            Mock Sync-OERStructureAccessPackage { $script:Order.Add('accessPackages') }
            Mock Sync-OERStructureAccessReview { $script:Order.Add('accessReviews') }
            Mock Sync-OERStructureDirectoryRoleManagementPolicy { $script:Order.Add('directoryRoleManagementPolicies') }
            Mock Sync-OERStructureDirectoryRoleAssignment { $script:Order.Add('directoryRoleAssignments') }
            Mock Sync-OERStructureRoleAssignment { $script:Order.Add('roleAssignments') }
            Mock Sync-OERStructureRoleManagementPolicy { $script:Order.Add('roleManagementPolicies') }
            # The engine resolves every roleAssignments scope before dispatch; no test here may reach
            # the ARM transport through that pre-pass.
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { "/subscriptions/$Subscription" } elseif ($ManagementGroup) { "/providers/Microsoft.Management/managementGroups/$ManagementGroup" } else { $Scope }
            }
        }
    }

    It 'dispatches all nine sections in dependency order, the assignments right after the directory role policies' {
        # Keys deliberately written out of order: the engine's order, not the document's, decides.
        $Json = '{ "version":"1.0", ' +
            '"roleManagementPolicies":[{"scope":"sub:Prod","role":"Reader"}], ' +
            '"directoryRoleAssignments":[{"role":"Reports Reader","principal":"person1@example.com","assignmentType":"Eligible","durationDays":30}], ' +
            '"roleAssignments":[{"scope":"sub:Prod","role":"Reader","principal":"a"}], ' +
            '"directoryRoleManagementPolicies":[{"role":"Reports Reader"}], ' +
            '"accessReviews":[{"displayName":"r","accessPackage":"ap","assignmentPolicy":"pol"}], ' +
            '"accessPackages":[{"displayName":"ap","catalog":"c","resourceRoles":null}], ' +
            '"catalogs":[{"displayName":"c","resources":null}], ' +
            '"administrativeUnits":[{"displayName":"au","members":null,"scopedRoles":null}], ' +
            '"groups":[{"displayName":"g","members":null}] }'
        Invoke-OERStructure -Json $Json -IncludeARM -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            @($script:Order) | Should -Be @('groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'accessReviews',
                'directoryRoleManagementPolicies', 'directoryRoleAssignments', 'roleAssignments', 'roleManagementPolicies')
        }
    }

    It 'does not request an ARM token for a document holding only the directory role assignment section' {
        Invoke-OERStructure -Json '{ "version":"1.0", "directoryRoleAssignments":[{"role":"Reports Reader","principal":"person1@example.com","assignmentType":"Eligible"}] }' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly
        InModuleScope $script:moduleName {
            Should -Invoke Sync-OERStructureDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'accepts DirectoryRoleAssignments in -Include, right after DirectoryRoleManagementPolicies, and includes it by default' {
        $Param = (Get-Command -Module $script:moduleName -Name Invoke-OERStructure).Parameters['Include']
        $ValidSet = @(@($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues)
        $ValidSet | Should -Contain 'DirectoryRoleAssignments'
        [array]::IndexOf($ValidSet, 'DirectoryRoleAssignments') | Should -Be ([array]::IndexOf($ValidSet, 'DirectoryRoleManagementPolicies') + 1)

        $Json = '{ "version":"1.0", "groups":[{"displayName":"g","members":null}], ' +
            '"directoryRoleAssignments":[{"role":"Reports Reader","principal":"person1@example.com","assignmentType":"Eligible"}] }'
        Invoke-OERStructure -Json $Json -Include DirectoryRoleAssignments -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            @($script:Order) | Should -Be @('directoryRoleAssignments')
            $script:Order.Clear()
        }
        Invoke-OERStructure -Json $Json -Confirm:$false | Out-Null
        InModuleScope $script:moduleName {
            @($script:Order) | Should -Be @('groups', 'directoryRoleAssignments')
            Should -Invoke Sync-OERStructureDirectoryRoleAssignment -Times 2 -Exactly
        }
    }

    It 'labels a handler failure with role, principal and the canonical assignmentType, as the handler labels its own rows' {
        InModuleScope $script:moduleName {
            Mock Sync-OERStructureDirectoryRoleAssignment { throw [System.Exception]::new('handler blew up') }
        }
        # Lower-cased on purpose: the engine reads the document through Read-OERStructureDocument,
        # which canonicalizes it, so the label carries the same spelling the handler would.
        $Json = '{ "version":"1.0", "directoryRoleAssignments":[{"role":"Reports Reader","principal":"person1@example.com","assignmentType":"eligible"}] }'
        $Records = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue)
        $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
        @($Failed).Count | Should -Be 1
        $Failed[0].Section | Should -BeExactly 'directoryRoleAssignments'
        $Failed[0].Item | Should -BeExactly 'Reports Reader -> person1@example.com (Eligible)'
        $Failed[0].Detail | Should -Match 'handler blew up'
    }

    It 'passes -ReconcileSection on the first directoryRoleAssignments item only, and the whole section to every item' {
        # The section-wide prune pass must run exactly once per run, and every invocation must see
        # every declared entry so the pass keys the whole section, not just the first item.
        InModuleScope $script:moduleName {
            $script:DraCalls = [System.Collections.Generic.List[object]]::new()
            Mock Sync-OERStructureDirectoryRoleAssignment {
                $script:DraCalls.Add([PSCustomObject]@{
                        Principal = [string]$Item.principal
                        Reconcile = [bool]$ReconcileSection
                        Declared  = @($DeclaredInSection | ForEach-Object { [string]$_.principal })
                        Prune     = [bool]$Prune
                    })
            }
        }
        $Json = '{ "version":"1.0", "directoryRoleAssignments":[' +
            '{"role":"Reports Reader","principal":"person1@example.com","assignmentType":"Eligible"}, ' +
            '{"role":"Message Center Reader","principal":"person2@example.com","assignmentType":"Active"} ] }'
        Invoke-OERStructure -Json $Json -Prune -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        InModuleScope $script:moduleName {
            @($script:DraCalls.Principal) | Should -Be @('person1@example.com', 'person2@example.com')
            @($script:DraCalls.Reconcile) | Should -Be @($true, $false)
            foreach ($Call in $script:DraCalls) {
                @($Call.Declared) | Should -Be @('person1@example.com', 'person2@example.com')
                $Call.Prune | Should -BeTrue
            }
        }
    }
}

Describe 'Invoke-OERStructure help pointer to the worked example' {
    # The help points at docs/examples/example-structure.json as showing every section the engine
    # understands. Each schema section the example lacks must be named there as missing, and a
    # section named as missing must really be missing -- so the sentence goes stale in neither
    # direction when the example or the schema changes.
    It 'names exactly the schema sections the worked example does not declare' {
        $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
        $Sections = @($Schema.properties.PSObject.Properties.Name | Where-Object { $_ -notin @('version', 'tenantId', 'tenantAlias') })
        $ExamplePath = Join-Path $PSScriptRoot '../../../docs/examples/example-structure.json'
        $Example = Get-Content -LiteralPath $ExamplePath -Raw | ConvertFrom-Json
        $Missing = @($Sections | Where-Object { $Example.PSObject.Properties.Name -notcontains $_ } | Sort-Object)
        $Help = (Get-Command -Module $script:moduleName -Name 'Invoke-OERStructure').Definition
        $Help | Should -Match 'docs/examples/example-structure\.json'
        # "except a and b, which are not in the example yet" (or "except a, which is ..."): the list
        # between "except" and that phrase, split on commas and "and".
        $Clause = [regex]::Match($Help, 'except\s+(?<List>[\w\s,]+?),\s+which\s+(?:is|are)\s+not\s+in\s+the\s+example\s+yet')
        $Named = @($Clause.Groups['List'].Value -split ',|\band\b' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
        ($Named -join ',') | Should -BeExactly ($Missing -join ',')
    }

    It 'documents the document tenant rule beside the pipeline session rule, and points -TenantId and -InputObject at it (BL-88, A14)' {
        # Read through Get-Help, never the command's Definition: the Definition holds the function body,
        # where DocumentTenantMismatch and tenantId already stand, so a match there proves nothing about
        # the help. Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Invoke-OERStructure -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $ParamText = @{}
        foreach ($P in @($Help.Parameters.Parameter)) {
            $ParamText[[string]$P.Name] = ((@($P.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        }

        $Description | Should -Match ([regex]::Escape('Document tenant rule: a document whose top-level tenantId names a tenant -- as Get-OERInventory and Export-OERInventory write it -- is applied only in that tenant.'))
        $Description | Should -Match ([regex]::Escape('the document is refused with DocumentTenantMismatch before the sign-in, with no token request'))
        $Description | Should -Match ([regex]::Escape('the document is compared again after the sign-in, before anything is read or written for it (the omitted-collection warning and the administrative unit pre-pass included)'))
        $Description | Should -Match ([regex]::Escape("the tenant the session's Microsoft Graph token was issued for must be the document's, and so must the tenant the Azure Resource Manager token was issued for when Azure Resource Manager is used (an Azure section is selected and declared, or -IncludeARM is set)"))
        $Description | Should -Match ([regex]::Escape("A session that holds no such token, or whose token tenant is not a GUID, cannot be compared and refuses the document too."))
        $Description | Should -Match ([regex]::Escape('refuses the document with DocumentTenantMismatch as a non-terminating error: nothing is read or written for it, and the next piped document is tried on its own'))
        $Description | Should -Match ([regex]::Escape("The document's tenant is only compared, never signed in to, so name it with -TenantId to apply the document there."))
        $Description | Should -Match ([regex]::Escape("A document without tenantId is applied as before, with no tenant check: to use an export as a template for another tenant, change its tenantId to that tenant's ID or remove the key."))
        $Description | Should -Match ([regex]::Escape('Called inside a script block or a function in a pipeline (ForEach-Object { Invoke-OERStructure ... }), the command begins after every other command in the pipeline has begun and takes the session they left for its own, which the pipeline session rule above cannot see'))
        $Description | Should -Match ([regex]::Escape('a document without tenantId is applied in whatever tenant that session holds, so name -TenantId there'))

        # The new paragraph stands after the pipeline session rule, which is still there word for word at
        # its head and its end, and before the next paragraph.
        $Description | Should -Match ([regex]::Escape('Pipeline session rule: without -TenantId the command acts only under the session it began with.'))
        $Description | Should -Match ([regex]::Escape('Run such commands as separate statements.'))
        $Rule = $Description.IndexOf('Pipeline session rule:')
        $Rule | Should -BeGreaterThan -1
        $Rule | Should -BeLessThan $Description.IndexOf('Document tenant rule:')
        $Description.IndexOf('Document tenant rule:') | Should -BeLessThan $Description.IndexOf('RoleAssignments scope grouping:')

        $ParamText['TenantId'] | Should -Match 'tenantId'
        $ParamText['TenantId'] | Should -Match ([regex]::Escape('see the document tenant rule above'))
        $ParamText['InputObject'] | Should -Match ([regex]::Escape('whose tenantId, when it carries one, limits it to that tenant'))
        # The pipeline session rule's last sentence no longer claims the sign-in is unconditional.
        $Description | Should -Match ([regex]::Escape('With -TenantId the command signs in to that tenant as before, except that a document naming another tenant than a -TenantId that is a tenant ID is refused before that sign-in (see the document tenant rule below).'))
    }
}

Describe 'Invoke-OERStructure with an ambiguous subscription display name in a scope' {
    # The Azure handlers run for REAL here, and so do Resolve-OERScope and (for the policy entry)
    # Get-/Set-OERRoleManagementPolicy: only the ARM and Graph transports and the lookups below the
    # scope are mocked. The subscription list answers with two subscriptions that share the display
    # name 'Dup Sub' and one 'Good Sub'. Subscription display names are not unique, so a scope
    # 'subscription:Dup Sub' cannot name one subscription: the entry must fail with the candidates
    # and the run must go on, and under -Prune nothing at the ambiguous scope may be removed or
    # created. An entry whose scope cannot be resolved may be another spelling of ANY scope in the
    # section, so it also withholds the prune of every other scope in it: the extra assignment at
    # 'Good Sub' is reported Skipped and not removed. 'Good Sub' is still the positive control for
    # the run going past the failed entries: it is read and its declared entry is Unchanged. No id
    # below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Dup Sub' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Dup Sub' }
                    [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; displayName = 'Good Sub' }
                ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
            Mock Invoke-OERArmRequest { throw "unexpected ARM call: $Method $Path" }
            Mock Resolve-OERStructurePrincipal { "p-$Reference" }
            Mock Resolve-OERRoleDefinitionId { "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-$Role" }
            # What the old first-match code would have read for 'Dup Sub': the live assignments of the
            # FIRST of the two subscriptions, one declared and one undeclared. The handler reads at
            # the scope the engine resolved, so the mock answers on -Scope.
            Mock Get-OERRoleAssignment {
                param($Scope, [switch]$AtScope)
                if ($Scope -like '/subscriptions/aaaa1111-0000-0000-0000-00000000000[12]') {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; PrincipalId = 'p-grp-a'; RoleDefinitionId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/rd-Reader'; RoleAssignmentId = 'ra-dup-declared' }
                        [PSCustomObject]@{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; PrincipalId = 'p-live-dup'; RoleDefinitionId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/rd-Reader'; RoleAssignmentId = 'ra-dup-extra' }
                    )
                } elseif ($Scope -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000003') {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000003'; PrincipalId = 'p-grp-c'; RoleDefinitionId = '/subscriptions/aaaa1111-0000-0000-0000-000000000003/providers/Microsoft.Authorization/roleDefinitions/rd-Reader'; RoleAssignmentId = 'ra-good-declared' }
                        [PSCustomObject]@{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000003'; PrincipalId = 'p-live-good'; RoleDefinitionId = '/subscriptions/aaaa1111-0000-0000-0000-000000000003/providers/Microsoft.Authorization/roleDefinitions/rd-Reader'; RoleAssignmentId = 'ra-good-extra' }
                    )
                }
            }
            Mock New-OERRoleAssignment {}
            Mock Set-OERRoleAssignment {}
            Mock Remove-OERRoleAssignment {}
        }
    }

    # The flip from the earlier shape of this test is deliberate (spec A12): this test used to expect
    # the extra assignment at 'Good Sub' to be REMOVED while 'Dup Sub' stayed unresolved. An
    # unresolved scope may be an alias of any scope in the section, so the whole section's prune is
    # withheld instead -- nothing is removed anywhere, and the candidate is reported Skipped.
    It 'fails every entry at the ambiguous scope with both candidate ids, goes on to the next scope, and withholds the prune of the whole section' {
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"subscription:Dup Sub","role":"Reader","principal":"grp-a"}, ' +
            '{"scope":"subscription:Dup Sub","role":"Reader","principal":"grp-b"}, ' +
            '{"scope":"subscription:Good Sub","role":"Reader","principal":"grp-c"} ] }'
        $Err = $null
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

        # Positive proof first: the run reached the third entry, whose scope IS resolvable, and read
        # and reconciled it. Without this the negative assertions below could pass on a run that
        # stopped early.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000003' }
        @($Rows | Where-Object { $_.Item -eq 'Reader -> grp-c @ subscription:Good Sub' }).Action | Should -Be @('Unchanged')

        # Nothing was removed anywhere: not at the ambiguous scope, and not at the good one either.
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleAssignment -Times 0
        # Nothing at the ambiguous scope was even read.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0 -ParameterFilter { $Scope -like '/subscriptions/aaaa1111-0000-0000-0000-00000000000[12]' }

        # The undeclared assignment at the good scope is withheld, naming both unresolved entries.
        $Withheld = @($Rows | Where-Object { $_.Action -eq 'Skipped' })
        $Withheld.Count | Should -Be 1
        $Withheld[0].Item | Should -BeExactly 'rd-Reader -> p-live-good @ /subscriptions/aaaa1111-0000-0000-0000-000000000003'
        $Withheld[0].Detail.StartsWith("prune withheld: the scopes of declared entries 'Reader -> grp-a @ subscription:Dup Sub', 'Reader -> grp-b @ subscription:Dup Sub'") | Should -BeTrue
        @($Rows | Where-Object { $_.Action -in @('Removed', 'Extra') }).Count | Should -Be 0

        # ... and the ambiguous scope's two entries are Failed rows, the only rows it produced.
        $DupRows = @($Rows | Where-Object { $_.Item -like '* @ subscription:Dup Sub' })
        $DupRows.Count | Should -Be 2
        @($DupRows.Action) | Should -Be @('Failed', 'Failed')
        foreach ($DupRow in $DupRows) {
            $DupRow.Detail | Should -Match "could not resolve scope 'subscription:Dup Sub'"
            $DupRow.Detail | Should -Match 'aaaa1111-0000-0000-0000-000000000001'
            $DupRow.Detail | Should -Match 'aaaa1111-0000-0000-0000-000000000002'
        }
        @($Rows | Where-Object { $_.Action -in @('Created', 'Updated', 'Removed', 'Extra', 'Skipped') }).Count | Should -Be 1
        $Rows.Count | Should -Be 4

        # The refusal is published once per failed entry, as the AmbiguousName record itself. Narrowed
        # to the engine's own publication: -ErrorVariable also holds the inner throw's capture, which
        # carries no command name and would satisfy a bare count with the re-publication removed.
        $Published = @($Err | Where-Object {
                $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' -and
                $_.FullyQualifiedErrorId -like 'AmbiguousName*' -and $_.TargetObject -eq 'Dup Sub'
            })
        $Published.Count | Should -Be 2
    }

    It 'fails a roleManagementPolicies entry at the ambiguous scope with both candidate ids and reads and writes no policy' {
        $Json = '{ "version":"1.0", "roleManagementPolicies":[' +
            '{"scope":"subscription:Dup Sub","role":"Reader","allowPermanentEligibility":false} ] }'
        $Err = $null
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleManagementPolicies -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

        # Positive proof first: the subscription list WAS read, so the refusal is the ambiguity.
        # Twice: Get-OERRoleManagementPolicy and Set-OERRoleManagementPolicy each re-resolve the scope.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 2 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions?api-version=2022-12-01' -and $All
        }

        # No policy was looked up or written: the subscription list is the only ARM request made.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter {
            $Path -ne '/subscriptions?api-version=2022-12-01'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERRoleDefinitionId -Times 0

        $Rows.Count | Should -Be 1
        $Rows[0].Item | Should -BeExactly 'Reader @ subscription:Dup Sub'
        $Rows[0].Action | Should -Be 'Failed'
        $Rows[0].Detail | Should -Match 'aaaa1111-0000-0000-0000-000000000001'
        $Rows[0].Detail | Should -Match 'aaaa1111-0000-0000-0000-000000000002'
        # One InvalidScope record is the engine's publication for the entry; the Get and Set cmdlets
        # each published their own before it, so narrow on the command that published.
        @($Err | Where-Object {
                $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' -and
                $_.FullyQualifiedErrorId -like 'InvalidScope,*' -and $_.Exception.Message -like '*matches 2 subscriptions*'
            }).Count | Should -Be 1
    }
}

Describe 'Invoke-OERStructure roleManagementPolicies approvers that name nobody (BL-97, F1)' {
    # The engine, Sync-OERStructureRoleManagementPolicy, its diff and Set-OERRoleManagementPolicy run
    # for REAL here, in the shape of the ambiguous-scope test above: only the live policy read, the
    # approver resolution and the transports are mocked. One live state for the plan and the run:
    # approval required, approvers one user and one group. A document that declares both approver
    # sides empty is the call Set-OERRoleManagementPolicy refuses with ApproverRequired, so the -WhatIf
    # plan must report the same Failed row as the run, and neither may send anything.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:RmpArmCalls = [System.Collections.Generic.List[object]]::new()
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Mock Invoke-OERArmRequest {
                param($Method, $Path, $Body)
                $script:RmpArmCalls.Add([PSCustomObject]@{ Method = $Method; Path = $Path })
                if ($Method -eq 'PATCH') { throw 'no ARM write expected' }
            }
            Mock Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    RequireApproval    = $true
                    ActivationMaxHours = 8
                    Approvers          = @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; UserType = 'User'; DisplayName = 'Person One' }
                        [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; UserType = 'Group'; DisplayName = 'Approvers' }
                    )
                    Scope              = '/subscriptions/sub-1'
                    RoleName           = 'Reader'
                }
            }
            Mock Resolve-OERDeclaredApprover { param($Declared) $Declared }
        }
    }

    It 'reports the same Failed row with ApproverRequired under -WhatIf and in the run, and sends no PATCH' {
        $Json = '{ "version":"1.0", "roleManagementPolicies":[{"scope":"sub:Prod","role":"Reader","approvers":{"users":[],"groups":[]}}] }'
        $PlanErr = $null
        $RunErr = $null
        $Plan = @(Invoke-OERStructure -InputObject ($Json | ConvertFrom-Json) -WhatIf `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable PlanErr)
        # Reached: the plan read the live policy once.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly
        $Run = @(Invoke-OERStructure -InputObject ($Json | ConvertFrom-Json) -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable RunErr)
        # Reached: the run read it once more.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 2 -Exactly

        $Plan.Count | Should -Be 1
        $Plan[0].Section | Should -Be 'roleManagementPolicies'
        $Plan[0].Item | Should -BeExactly 'Reader @ sub:Prod'
        $Plan[0].Action | Should -Be 'Failed'
        $Plan[0].Detail | Should -Match 'ApproverRequired'
        $Run.Count | Should -Be 1
        $Run[0].Section | Should -Be 'roleManagementPolicies'
        $Run[0].Item | Should -BeExactly 'Reader @ sub:Prod'
        $Run[0].Action | Should -Be 'Failed'
        $Run[0].Detail | Should -Match 'ApproverRequired'
        $Run[0].Detail | Should -BeExactly $Plan[0].Detail

        # One ApproverRequired record per mode, published by the engine's handler and no other.
        @($PlanErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverRequired*' }).FullyQualifiedErrorId |
            Should -Be @('ApproverRequired,Invoke-OERStructure')
        @($RunErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverRequired*' }).FullyQualifiedErrorId |
            Should -Be @('ApproverRequired,Invoke-OERStructure')

        # Nothing was sent: no PATCH, and no Azure Resource Manager call of any kind.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        InModuleScope $script:moduleName { $script:RmpArmCalls.Count } | Should -Be 0
    }
}

Describe 'Invoke-OERStructure roleManagementPolicies touches only the declared policies (BL-107)' {
    # Export-OERInventory now writes, by default, only the Azure role management policies of roles in
    # use or changed, so its document declares fewer policies than the scope holds. Apply reads and
    # writes only the policies the document declares -- with and without -Prune -- so every policy it
    # leaves out stays as it is. The engine, Sync-OERStructureRoleManagementPolicy and its diff run for
    # real; only the live policy read and write, the approver resolution and the transports are mocked.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Mock Invoke-OERArmRequest { throw 'unexpected ARM request' }
            Mock Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    RoleName           = $Role
                    Scope              = '/subscriptions/11111111-1111-1111-1111-111111111111'
                    ActivationMaxHours = 8
                    RequireApproval    = $false
                    Approvers          = @()
                }
            }
            Mock Set-OERRoleManagementPolicy {}
            Mock Resolve-OERDeclaredApprover { param($Declared) $Declared }
        }
    }

    It 'reads and writes the policy of the one declared role and of no other (<Mode>)' -ForEach @(
        @{ Mode = 'without -Prune'; Prune = $false }
        @{ Mode = 'with -Prune'; Prune = $true }
    ) {
        $Json = '{ "version":"1.0", "roleManagementPolicies":[' +
            '{"scope":"/subscriptions/11111111-1111-1111-1111-111111111111","role":"Reader","activationMaxHours":4} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Prune:$Prune -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        # Reached: the declared policy was read, found to differ, and written.
        $Rows.Count | Should -Be 1
        $Rows[0].Section | Should -Be 'roleManagementPolicies'
        $Rows[0].Item | Should -BeExactly 'Reader @ /subscriptions/11111111-1111-1111-1111-111111111111'
        $Rows[0].Action | Should -Be 'Updated'
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
            $Role -eq 'Reader' -and $Scope -eq '/subscriptions/11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
            $Role -eq 'Reader' -and $ActivationMaxHours -eq 4
        }

        # No other policy was read or written: no other role, no listing of every role at the scope.
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 0 -ParameterFilter {
            $Role -ne 'Reader' -or $AllRolesAtScope -or $CommonRoles -or $PolicyId
        }
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 0 -ParameterFilter { $Role -ne 'Reader' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
    }
}

Describe 'Invoke-OERStructure roleAssignments grouped on the resolved scope' {
    # Two entries that spell one Azure scope differently must form ONE group with ONE prune pass.
    # Grouped on the text instead, each group's pass removed the other group's declared assignment
    # under -Prune. The real handler, Resolve-OERScope, ConvertTo-OERScopeSplat and
    # ConvertTo-OERCanonicalScope run here; only the transports and the lookups below the scope are
    # mocked. The subscription 'Prod' and the management group 'plat' (display name
    # 'Platform Display') are the only Azure objects the ARM mock knows. At the shared scope the live
    # state holds the two declared assignments (p-a and p-b, both Reader) and one undeclared one
    # (p-c), so a single pass removes exactly ra-c. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:RaShared = $null
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Prod' }
                    ) }
            } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/plat' }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/plat?api-version=2020-05-01' }
            Mock Invoke-OERArmRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("The management group 'Platform Display' was not found."),
                    'NotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null)
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups/Platform%20Display?api-version=2020-05-01' }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ name = 'plat'; id = '/providers/Microsoft.Management/managementGroups/plat'; properties = [PSCustomObject]@{ displayName = 'Platform Display' } }
                    ) }
            } -ParameterFilter { $Path -eq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All }
            Mock Invoke-OERArmRequest { throw "unexpected ARM call: $Method $Path" }
            Mock Resolve-OERStructurePrincipal { param($Reference, $Type) "p-$Reference" }
            Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-$Role" }
            Mock Get-OERRoleAssignment {
                param($Scope, [switch]$AtScope)
                if ($Scope -eq $script:RaShared) {
                    $Live = $script:RaShared.ToLowerInvariant()
                    $LiveRole = "$Live/providers/Microsoft.Authorization/roleDefinitions/rd-Reader"
                    [PSCustomObject]@{ Scope = $Live; PrincipalId = 'p-a'; RoleDefinitionId = $LiveRole; RoleAssignmentId = 'ra-a' }
                    [PSCustomObject]@{ Scope = $Live; PrincipalId = 'p-b'; RoleDefinitionId = $LiveRole; RoleAssignmentId = 'ra-b' }
                    [PSCustomObject]@{ Scope = $Live; PrincipalId = 'p-c'; RoleDefinitionId = $LiveRole; RoleAssignmentId = 'ra-c' }
                }
            }
            Mock New-OERRoleAssignment {}
            Mock Set-OERRoleAssignment {}
            Mock Remove-OERRoleAssignment { param($Id) }
        }
    }

    It 'groups <ScopeA> and <ScopeB> as one scope: one prune pass, and neither entry removes the other''s assignment' -ForEach @(
        @{ ScopeA = 'sub:aaaa1111-0000-0000-0000-000000000001'; ScopeB = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; Shared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ ScopeA = 'subscription:aaaa1111-0000-0000-0000-000000000001'; ScopeB = 'sub:aaaa1111-0000-0000-0000-000000000001'; Shared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ ScopeA = 'sub:Prod'; ScopeB = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; Shared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ ScopeA = 'mg:plat'; ScopeB = '/providers/Microsoft.Management/managementGroups/plat'; Shared = '/providers/Microsoft.Management/managementGroups/plat' }
        @{ ScopeA = 'mg:Platform Display'; ScopeB = 'mg:plat'; Shared = '/providers/Microsoft.Management/managementGroups/plat' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Shared = $Shared } { param($Shared) $script:RaShared = $Shared }
        $Document = [PSCustomObject]@{
            version         = '1.0'
            roleAssignments = @(
                [PSCustomObject]@{ scope = $ScopeA; role = 'Reader'; principal = 'a' }
                [PSCustomObject]@{ scope = $ScopeB; role = 'Reader'; principal = 'b' }
            )
        }
        $Rows = @(Invoke-OERStructure -Json ($Document | ConvertTo-Json -Depth 5) -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue)

        # Positive proof first: exactly one pass ran, and it pruned the undeclared assignment.
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-c' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -in 'ra-a', 'ra-b' }
        Should -Invoke -ModuleName $script:moduleName New-OERRoleAssignment -Times 0

        # Each declared row keeps the scope text of its own entry.
        @($Rows | Where-Object { $_.Item -eq "Reader -> a @ $ScopeA" }).Action | Should -Be @('Unchanged')
        @($Rows | Where-Object { $_.Item -eq "Reader -> b @ $ScopeB" }).Action | Should -Be @('Unchanged')
    }

    It 'refuses a scope written with <Case> before it authenticates, and prunes nothing' -ForEach @(
        @{ Case = 'a trailing slash'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1/' }
        @{ Case = 'a doubled slash'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001//resourceGroups/rg1' }
        @{ Case = 'only a doubled slash'; Scope = '//' }
    ) {
        # A15: the canonical form would merge such a scope with the scope written without the stray
        # '/', so the scope written ONLY that way would start to be pruned, and '//' would be the root.
        # The validator refuses it instead; the whole document is refused before any sign-in or read.
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"' + $Scope + '","role":"Reader","principal":"a"} ] }'
        $Err = $null
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

        $Rows.Count | Should -Be 0
        $Refused = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'StructureValidationFailed,*' })
        $Refused.Count | Should -Be 1
        $Refused[0].Exception.Message | Should -BeLike "*roleAssignments``[0``].scope: 'scope' at roleAssignments``[0``] must be written without a trailing or doubled '/'. Got: '$Scope'.*"
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0
    }

    It 'reconciles a declared scope whose letter case differs from the live scope' {
        # Entry a spells the scope in upper case; entry b spells it as the live state does. They are
        # one scope, compared without regard to letter case, so they form one group with one pass.
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"/SUBSCRIPTIONS/AAAA1111-0000-0000-0000-000000000001/resourceGroups/RG1","role":"Reader","principal":"a"}, ' +
            '{"scope":"/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1","role":"Reader","principal":"b"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue)

        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-c' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -in 'ra-a', 'ra-b' }
        Should -Invoke -ModuleName $script:moduleName New-OERRoleAssignment -Times 0
        @($Rows | Where-Object { $_.Item -eq 'Reader -> a @ /SUBSCRIPTIONS/AAAA1111-0000-0000-0000-000000000001/resourceGroups/RG1' }).Action | Should -Be @('Unchanged')
        @($Rows | Where-Object { $_.Item -eq 'Reader -> b @ /subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1' }).Action | Should -Be @('Unchanged')
    }

    It 'hands the handler the canonical resolved scope and resolves each scope text once' {
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"sub:Prod","role":"Reader","principal":"a"}, ' +
            '{"scope":"sub:Prod","role":"Reader","principal":"b"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue)

        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions?api-version=2022-12-01' -and $All
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 2 -Exactly -ParameterFilter {
            $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and $AtScope
        }
        @($Rows | Where-Object { $_.Item -like 'Reader -> * @ sub:Prod' }).Action | Should -Be @('Unchanged', 'Unchanged')
    }

    It 'withholds the prune of every candidate when one entry fails to resolve a scope that a later entry with the same text resolves' {
        # The pre-pass caches only SUCCESSFUL resolutions, so two entries with the same scope text can
        # have one failure and one success. The first lookup of 'Prod' fails transiently, the second
        # succeeds: entry 0 is Failed and never dispatched, entry 1 resolves and reconciles. The
        # surviving group of the resolved scope declares only entry 1, so entry 0's own live
        # assignment (p-a) looks undeclared in it -- exactly the object the document asked to keep.
        # The failed entry may be a spelling of any scope, so the prune of the whole section is
        # withheld and no candidate is removed.
        InModuleScope $script:moduleName {
            $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:RaResolveCalls = 0
            Mock Resolve-OERScope {
                param([string]$Scope, [string]$Subscription, [string]$ManagementGroup)
                $script:RaResolveCalls++
                if ($script:RaResolveCalls -eq 1) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('transient ARM failure while listing subscriptions'),
                        'ArmTransportError',
                        [System.Management.Automation.ErrorCategory]::ConnectionError,
                        $null)
                }
                '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            }
        }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"sub:Prod","role":"Reader","principal":"a"}, ' +
            '{"scope":"sub:Prod","role":"Reader","principal":"b"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        # Positive proof first: the same scope text was resolved twice (the failure was not cached),
        # entry 0 failed on the first lookup, and entry 1 reconciled on the second.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERScope -Times 2 -Exactly -ParameterFilter { $Subscription -eq 'Prod' }
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and $AtScope
        }
        $First = @($Rows | Where-Object { $_.Item -eq 'Reader -> a @ sub:Prod' })
        $First.Count | Should -Be 1
        $First[0].Action | Should -Be 'Failed'
        $First[0].Detail | Should -Match "could not resolve scope 'sub:Prod'"
        @($Rows | Where-Object { $_.Item -eq 'Reader -> b @ sub:Prod' }).Action | Should -Be @('Unchanged')

        # Nothing was removed, and the whole section's candidates are withheld: p-a (the failed
        # entry's own live assignment, undeclared in the surviving group) and the plain extra p-c.
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0
        $Withheld = @($Rows | Where-Object { $_.Action -eq 'Skipped' })
        # Select-Object, not member enumeration: .Item on an array is the indexer method.
        @($Withheld | Select-Object -ExpandProperty Item) | Should -Be @(
            'rd-Reader -> p-a @ /subscriptions/aaaa1111-0000-0000-0000-000000000001'
            'rd-Reader -> p-c @ /subscriptions/aaaa1111-0000-0000-0000-000000000001'
        )
        foreach ($Row in $Withheld) {
            $Row.Detail.StartsWith("prune withheld: the scope of declared entry 'Reader -> a @ sub:Prod'") | Should -BeTrue
        }
        @($Rows | Where-Object { $_.Action -in @('Removed', 'Extra', 'Created', 'Updated') }).Count | Should -Be 0
        $Rows.Count | Should -Be 4
    }

    It 'fails the later of two entries that resolve to the same assignment, writes nothing for it and never prunes the assignment' {
        # sub:Prod and the subscription path are one scope, so both entries name the same principal and
        # role at it: one assignment. The later entry is Failed with the earlier one named; the
        # earlier one reconciles; and the duplicate's key stays declared, so the pass removes only
        # the two undeclared assignments (ra-b, ra-c) and never ra-a.
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"sub:Prod","role":"Reader","principal":"a"}, ' +
            '{"scope":"/subscriptions/aaaa1111-0000-0000-0000-000000000001","role":"Reader","principal":"a"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DupErr)

        # Positive proof first: the earlier entry reconciled against the live state, and the pass ran.
        @($Rows | Where-Object { $_.Item -eq 'Reader -> a @ sub:Prod' }).Action | Should -Be @('Unchanged')
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-b' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-c' }

        $Duplicate = @($Rows | Where-Object { $_.Item -eq 'Reader -> a @ /subscriptions/aaaa1111-0000-0000-0000-000000000001' })
        $Duplicate.Count | Should -Be 1
        $Duplicate[0].Action | Should -Be 'Failed'
        $Duplicate[0].Detail | Should -BeExactly "roleAssignments[1] resolves to the same assignment as roleAssignments[0] ('Reader -> a @ sub:Prod'): the same scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001', principal and role. Nothing was written for this entry; keep one of the two entries."
        @($DupErr).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -eq 'ra-a' }
        Should -Invoke -ModuleName $script:moduleName New-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleAssignment -Times 0
    }

    It 'under -WhatIf fails the later of two entries that resolve to the same assignment, naming the earlier index, instead of planning a second create' {
        # sub:Prod and the subscription path are one scope, and principal z holds nothing there, so
        # the earlier entry plans a create (Skipped under -WhatIf). The later entry names the same
        # assignment: it is Failed with the earlier index named -- not a second Skipped plan, which
        # would read as two creates -- and nothing is written for it.
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"sub:Prod","role":"Reader","principal":"z"}, ' +
            '{"scope":"/subscriptions/aaaa1111-0000-0000-0000-000000000001","role":"Reader","principal":"z"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DupWhatIfErr)

        # Positive proof first: the earlier entry was reconciled and planned its create.
        $Earlier = @($Rows | Where-Object { $_.Item -eq 'Reader -> z @ sub:Prod' })
        $Earlier.Count | Should -Be 1
        $Earlier[0].Action | Should -Be 'Skipped'
        $Earlier[0].Detail | Should -Match '^would create role assignment'
        Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly

        $Duplicate = @($Rows | Where-Object { $_.Item -eq 'Reader -> z @ /subscriptions/aaaa1111-0000-0000-0000-000000000001' })
        $Duplicate.Count | Should -Be 1
        $Duplicate[0].Action | Should -Be 'Failed'
        $Duplicate[0].Detail | Should -BeExactly "roleAssignments[1] resolves to the same assignment as roleAssignments[0] ('Reader -> z @ sub:Prod'): the same scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001', principal and role. Nothing was written for this entry; keep one of the two entries."
        @($DupWhatIfErr).Count | Should -Be 0
        # Exactly two rows concern principal z: the planned create and the duplicate's Failed row.
        @($Rows | Where-Object { $_.Item -like 'Reader -> z @ *' }).Count | Should -Be 2
        Should -Invoke -ModuleName $script:moduleName New-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 0
    }

    It 'resolves the siblings of a scope once for all its entries' {
        # The engine hands every entry of one resolved scope the same key cache. Each entry's own
        # lookup is made once and the group's two siblings are resolved once: four principal lookups,
        # not one more set for the duplicate check of each entry and for the prune pass.
        InModuleScope $script:moduleName { $script:RaShared = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        $Json = '{ "version":"1.0", "roleAssignments":[' +
            '{"scope":"sub:Prod","role":"Reader","principal":"a"}, ' +
            '{"scope":"/subscriptions/aaaa1111-0000-0000-0000-000000000001","role":"Reader","principal":"b"} ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue)

        # Positive proof first: both entries reconciled, and the single pass removed the undeclared one.
        @($Rows | Where-Object { $_.Item -like 'Reader -> * @ *' }).Action | Should -Be @('Unchanged', 'Unchanged')
        Should -Invoke -ModuleName $script:moduleName Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-c' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERStructurePrincipal -Times 4 -Exactly
        Should -Invoke -ModuleName $script:moduleName Resolve-OERRoleDefinitionId -Times 4 -Exactly
    }
}

Describe 'Invoke-OERStructure never reaches the root scope (BL-126)' {
    # A role assignment at the Azure root scope '/' is elevated access, which the apply engine never
    # creates, edits or removes. The real engine, the real handler and the real ARM cmdlets run here;
    # only the sign-in, the principal lookups and the ARM transport are mocked, and the transport
    # records every request. The document declares one entry at the root scope and two at a
    # subscription, where the live state holds one of them, one undeclared assignment and the root
    # assignment as inherited. No recorded request may be an ARM call at the root scope: its path would
    # start with '//' (the root scope followed by '/providers/...') or with
    # '/providers/Microsoft.Authorization/'. The subscription is reconciled as before. No id below is
    # version-4 shaped.
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        $script:RtSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:RtReaderId = "$($script:RtSub)/providers/Microsoft.Authorization/roleDefinitions/bbbb7777-0000-0000-0000-000000000001"
        $script:RtContributorId = "$($script:RtSub)/providers/Microsoft.Authorization/roleDefinitions/bbbb7777-0000-0000-0000-000000000002"
        $script:RtUndeclaredId = "$($script:RtSub)/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000009"
        $script:RtJson = '{ "version": "1.0", "roleAssignments": [ ' +
            '{ "scope": "/", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Reader", "principal": "person2@example.com" }, ' +
            '{ "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Contributor", "principal": "person3@example.com" } ] }'
        $script:RtRootLabel = 'User Access Administrator -> person1@example.com @ /'
        $script:RtRootDetail = "the root scope '/' grants access over every management group and subscription in the tenant (elevated " +
            'access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or ' +
            'written for this entry'
        $script:RtUndeclaredItem = "bbbb7777-0000-0000-0000-000000000001 -> dddd7777-0000-0000-0000-000000000009 @ $($script:RtSub)"
        # The recorded requests whose path is an ARM call at the root scope. Each recorded path is first
        # normalised as the transport's URI normalises it: Invoke-OERArmRequest sends "<host><path>"
        # through System.Uri, which removes dot segments, decodes '%2e' and reads '\' as '/', so
        # '/./providers/Microsoft.Authorization/...' is SENT as '/providers/Microsoft.Authorization/...'.
        function Get-RootRequest {
            param([string[]]$Log)
            @($Log | Where-Object { $_ } | Where-Object {
                    $RequestPath = ([uri]('https://scope.invalid' + ($_ -split ' ', 2)[1])).AbsolutePath
                    $RequestPath.StartsWith('//') -or $RequestPath.StartsWith('/providers/Microsoft.Authorization/', [System.StringComparison]::OrdinalIgnoreCase)
                })
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        $script:RtArmLog = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal {
            param($Reference, $Type)
            switch ($Reference) {
                'person1@example.com' { 'dddd7777-0000-0000-0000-000000000001' }
                'person2@example.com' { 'dddd7777-0000-0000-0000-000000000002' }
                'person3@example.com' { 'dddd7777-0000-0000-0000-000000000003' }
            }
        }
        # New-OERRoleAssignment looks up the principal it creates for on its own.
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal {
            [PSCustomObject]@{ PrincipalId = 'dddd7777-0000-0000-0000-000000000003'; PrincipalType = 'User' }
        }
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest {
            $RequestMethod = if ($Method) { $Method } else { 'GET' }
            $script:RtArmLog.Add("$RequestMethod $Path")
            if ($RequestMethod -eq 'GET' -and $Path -eq "$($script:RtSub)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20%27Reader%27") {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = $script:RtReaderId }) }
            }
            if ($RequestMethod -eq 'GET' -and $Path -eq "$($script:RtSub)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20%27Contributor%27") {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = $script:RtContributorId }) }
            }
            if ($RequestMethod -eq 'GET' -and $Path -eq "$($script:RtSub)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()") {
                return [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000001'; name = 'cccc7777-0000-0000-0000-000000000001'
                            properties = [PSCustomObject]@{ scope = '/'; principalId = 'dddd7777-0000-0000-0000-000000000001'; principalType = 'User'
                                roleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/bbbb7777-0000-0000-0000-00000000000a' } }
                        [PSCustomObject]@{ id = "$($script:RtSub)/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000002"; name = 'cccc7777-0000-0000-0000-000000000002'
                            properties = [PSCustomObject]@{ scope = $script:RtSub; principalId = 'dddd7777-0000-0000-0000-000000000002'; principalType = 'User'; roleDefinitionId = $script:RtReaderId } }
                        [PSCustomObject]@{ id = $script:RtUndeclaredId; name = 'cccc7777-0000-0000-0000-000000000009'
                            properties = [PSCustomObject]@{ scope = $script:RtSub; principalId = 'dddd7777-0000-0000-0000-000000000009'; principalType = 'User'; roleDefinitionId = $script:RtReaderId } }
                    ) }
            }
            if ($RequestMethod -eq 'PUT' -and $Path -like "$($script:RtSub)/providers/Microsoft.Authorization/roleAssignments/*?api-version=2022-04-01") {
                return [PSCustomObject]@{ id = $Path.Split('?')[0]; name = 'created'; properties = [PSCustomObject]@{
                        scope = $script:RtSub; principalId = $Body.properties.principalId; roleDefinitionId = $Body.properties.roleDefinitionId } }
            }
            if ($RequestMethod -eq 'DELETE' -and $Path -eq "$($script:RtUndeclaredId)?api-version=2022-04-01") {
                return [PSCustomObject]@{ id = $script:RtUndeclaredId; name = 'cccc7777-0000-0000-0000-000000000009'; properties = [PSCustomObject]@{ scope = $script:RtSub } }
            }
            throw "unexpected ARM call: $RequestMethod $Path"
        }
    }

    It 'skips the root entry and reconciles the subscription as before (<Mode>)' -ForEach @(
        @{ Mode = 'a real run with -Prune'; Splat = @{ Prune = $true; Confirm = $false }; Undeclared = 'Removed'; Contributor = 'Created'; Puts = 1; Deletes = 1 }
        @{ Mode = 'a real run without -Prune'; Splat = @{ Confirm = $false }; Undeclared = 'Extra'; Contributor = 'Created'; Puts = 1; Deletes = 0 }
        @{ Mode = 'a plan with -Prune'; Splat = @{ Prune = $true; WhatIf = $true }; Undeclared = 'Skipped'; Contributor = 'Skipped'; Puts = 0; Deletes = 0 }
    ) {
        $Rows = @(Invoke-OERStructure -Json $script:RtJson -Include RoleAssignments @Splat -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        # Positive proof first: the subscription was read once for each of its two entries, and
        # reconciled as its fixtures say.
        @($script:RtArmLog | Where-Object { $_ -eq "GET $($script:RtSub)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()" }).Count | Should -Be 2
        @($Rows | Where-Object { $_.Item -eq "Reader -> person2@example.com @ $($script:RtSub)" }).Action | Should -Be @('Unchanged')
        @($Rows | Where-Object { $_.Item -eq "Contributor -> person3@example.com @ $($script:RtSub)" }).Action | Should -Be @($Contributor)
        @($Rows | Where-Object { $_.Item -eq $script:RtUndeclaredItem }).Action | Should -Be @($Undeclared)
        @($script:RtArmLog | Where-Object { $_ -like 'PUT *' }).Count | Should -Be $Puts
        @($script:RtArmLog | Where-Object { $_ -eq "DELETE $($script:RtUndeclaredId)?api-version=2022-04-01" }).Count | Should -Be $Deletes
        @($script:RtArmLog | Where-Object { $_ -like 'DELETE *' }).Count | Should -Be $Deletes

        # The root entry: one Skipped row, and not one request at the root scope.
        $Root = @($Rows | Where-Object { $_.Item -eq $script:RtRootLabel })
        $Root.Count | Should -Be 1
        $Root[0].Action | Should -Be 'Skipped'
        $Root[0].Detail | Should -BeExactly $script:RtRootDetail
        (Get-RootRequest -Log $script:RtArmLog) | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Resolve-OERStructurePrincipal -Times 0 -ParameterFilter { $Reference -eq 'person1@example.com' }
        $Rows.Count | Should -Be 4
    }

    It 'refuses a document that spells the root scope with a dot segment or a percent escape, before any sign-in or request (A13)' {
        # '/.', '/..' and '/%2e' are not '/' as written, but the transport's URI sends a request for each
        # of them to the root scope's path. Since A13 (BL-141) the validator refuses each of the three
        # spellings as an Error, beside the root Warning, so the whole document stops at validation:
        # nothing is signed in to, read, looked up or written, the valid subscription entries included.
        # The engine's own root-scope guard for the same three spellings is held by the next test.
        $Json = '{ "version": "1.0", "roleAssignments": [ ' +
            '{ "scope": "/.", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/..", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/%2e", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Reader", "principal": "person2@example.com" } ] }'
        $Err = $null
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

        $Rows.Count | Should -Be 0
        $Refused = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'StructureValidationFailed,*' })
        $Refused.Count | Should -Be 1
        $Refused[0].Exception.Message | Should -BeLike "*roleAssignments``[0``].scope: 'scope' at roleAssignments``[0``] must be written without a '.' or '..' segment*Got: '/.'.*"
        $Refused[0].Exception.Message | Should -BeLike "*roleAssignments``[1``].scope: 'scope' at roleAssignments``[1``] must be written without a '.' or '..' segment*Got: '/..'.*"
        $Refused[0].Exception.Message | Should -BeLike "*roleAssignments``[2``].scope: 'scope' at roleAssignments``[2``] must be written without a '%':*Got: '/%2e'.*"
        $Refused[0].Exception.Message | Should -Not -BeLike "*roleAssignments``[3``]*"
        $script:RtArmLog.Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERStructurePrincipal -Times 0
    }

    It 'skips every dot-segment spelling of the root scope, sends nothing there, and still prunes the subscription, when the validator lets them through' {
        # '/.', '/..' and '/%2e' are not '/' as written, but the transport's URI sends a request for each
        # of them to the root scope's path. Test-OERAzureRootScope answers for the path the transport
        # sends, so the handler's guard skips all three. The validator refuses these spellings since A13
        # (BL-141), so it is stood in for here: this is the engine's own guard, kept as a second line
        # of defence for a spelling the validator might one day let through, and the real validator's
        # refusal is held by the test above.
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
        $Json = '{ "version": "1.0", "roleAssignments": [ ' +
            '{ "scope": "/.", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/..", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/%2e", "role": "User Access Administrator", "principal": "person1@example.com" }, ' +
            '{ "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Reader", "principal": "person2@example.com" }, ' +
            '{ "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Contributor", "principal": "person3@example.com" } ] }'
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

        Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Times 1 -Exactly
        # Positive proof first: the subscription was read once for each of its two entries, reconciled,
        # and its undeclared assignment removed.
        @($script:RtArmLog | Where-Object { $_ -eq "GET $($script:RtSub)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()" }).Count | Should -Be 2
        @($Rows | Where-Object { $_.Item -eq "Reader -> person2@example.com @ $($script:RtSub)" }).Action | Should -Be @('Unchanged')
        @($Rows | Where-Object { $_.Item -eq "Contributor -> person3@example.com @ $($script:RtSub)" }).Action | Should -Be @('Created')
        @($Rows | Where-Object { $_.Item -eq $script:RtUndeclaredItem }).Action | Should -Be @('Removed')
        @($script:RtArmLog | Where-Object { $_ -like 'PUT *' }).Count | Should -Be 1
        @($script:RtArmLog | Where-Object { $_ -like 'DELETE *' }) | Should -Be @("DELETE $($script:RtUndeclaredId)?api-version=2022-04-01")

        # Every root spelling: one Skipped row, and not one request that reaches the root scope.
        foreach ($Spelling in @('/.', '/..', '/%2e')) {
            $Root = @($Rows | Where-Object { $_.Item -eq "User Access Administrator -> person1@example.com @ $Spelling" })
            $Root.Count | Should -Be 1 -Because "the entry at '$Spelling' reports one row"
            $Root[0].Action | Should -Be 'Skipped' -Because "the entry at '$Spelling' is the root scope as the transport sends it"
            $Root[0].Detail | Should -BeExactly $script:RtRootDetail
        }
        (Get-RootRequest -Log $script:RtArmLog) | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Resolve-OERStructurePrincipal -Times 0 -ParameterFilter { $Reference -eq 'person1@example.com' }
        $Rows.Count | Should -Be 6
    }

    It 'skips the root entry and still removes the undeclared assignment at the subscription, in a script with no try above it' {
        # The public engine in a runspace through Invoke-OERWithConfirmAnswer, so no try stands anywhere
        # above it, as at a prompt. The script installs its own fakes in ITS copy of the module scope and
        # logs every ARM request with AppendAllText, whose path is substituted into the text.
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERStructurePrincipal -Value {
        param([string]$Reference, [string]$Type)
        if ($Reference -eq 'person1@example.com') { 'dddd7777-0000-0000-0000-000000000001' } else { 'dddd7777-0000-0000-0000-000000000002' }
    }
    Set-Item -Path function:script:Resolve-OERPrincipal -Value {
        [System.IO.File]::AppendAllText('#LOG#', "PRINCIPAL lookup`n")
        [pscustomobject]@{ PrincipalId = 'dddd7777-0000-0000-0000-000000000001'; PrincipalType = 'User' }
    }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body, [switch]$All)
        [System.IO.File]::AppendAllText('#LOG#', "$Method $Path`n")
        $Sub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $Reader = "$Sub/providers/Microsoft.Authorization/roleDefinitions/bbbb7777-0000-0000-0000-000000000001"
        if ($Method -eq 'GET' -and $Path -like '*/roleDefinitions?*') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = $Reader }) } }
        if ($Method -eq 'GET' -and $Path -like '*/roleAssignments?*atScope()') {
            return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = "$Sub/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000002"; name = 'a'
                    properties = [pscustomobject]@{ scope = $Sub; principalId = 'dddd7777-0000-0000-0000-000000000002'; roleDefinitionId = $Reader } }
                [pscustomobject]@{ id = "$Sub/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000009"; name = 'b'
                    properties = [pscustomobject]@{ scope = $Sub; principalId = 'dddd7777-0000-0000-0000-000000000009'; roleDefinitionId = $Reader } }
            ) }
        }
        if ($Method -eq 'DELETE') { return [pscustomobject]@{ id = $Path.Split('?')[0]; properties = [pscustomobject]@{} } }
        throw "unexpected $Method $Path"
    }
}
$Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/", "role": "User Access Administrator", "principal": "person1@example.com" }, { "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", "role": "Reader", "principal": "person2@example.com" } ] }'
Invoke-OERStructure -Json $Json -Prune -Confirm:$false | ForEach-Object { "ROW:$($_.Action):$($_.Item)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")))
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        $Run.Output[-1] | Should -BeExactly 'END'
        $Logged = @(Get-Content -LiteralPath $Log)
        # Reached: the subscription's DELETE of the undeclared assignment is in the log.
        $Logged | Should -Contain "DELETE $($script:RtUndeclaredId)?api-version=2022-04-01"
        # Not one request at the root scope; a failure here prints the requests that were.
        (Get-RootRequest -Log $Logged) | Should -BeNullOrEmpty
        @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @(
            "ROW:Skipped:$($script:RtRootLabel)"
            "ROW:Unchanged:Reader -> person2@example.com @ $($script:RtSub)"
            "ROW:Removed:$($script:RtUndeclaredItem)"
        )
        $Logged | Should -Not -Contain 'PRINCIPAL lookup'
        @($Run.Errors).Count | Should -Be 0
        @($Run.Prompts).Count | Should -Be 0
    }
}

Describe 'Invoke-OERStructure acts only under the session it began with (BL-76)' {
    # Invoke-OERStructure signs in in its process block. Every begin block of a pipeline runs before
    # any process block, so a DOWNSTREAM command's begin block -- here a ForEach-Object -Begin, the
    # shape of Connect-OER or any cmdlet naming another tenant -- switches the module's sign-in
    # identity after Invoke-OERStructure's begin block and before its process block. Without
    # -TenantId the document must then be refused with SignInSuperseded, before anything is signed
    # in to or sent. Initialize-OERAuth stays mocked; the switch is a direct write of the module state.
    BeforeAll {
        function script:Set-ProbeState {
            param([string]$TenantId, [string]$AuthMethod = 'ClientCertificate', [string]$ClientId = '33333333-3333-3333-3333-333333333333')
            InModuleScope Omnicit.EntraRBAC -Parameters @{ T = $TenantId; M = $AuthMethod; C = $ClientId } {
                param($T, $M, $C)
                $script:_OERAuthState = if ($T) { @{ TenantId = $T; AuthMethod = $M; ClientId = $C; Environment = 'Global' } } else { $null }
            }
        }
        $script:GroupDoc = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe" } ] }'
        # BL-92: what the refusal of a whole document says, by cause. Another command's sign-in replaced
        # the session, or Disconnect-OER ended it and the module holds no state at all.
        $script:DocumentIdentityText = 'Another OER command in the same pipeline signed in to a different tenant or identity after ' +
            'Invoke-OERStructure began, so Invoke-OERStructure did not apply this document and Omnicit.EntraRBAC sent nothing ' +
            'for it. Run the commands as separate statements, so that each one signs in and finishes before the next one starts.'
        $script:DocumentEndedText = "Disconnect-OER ended the module's session after Invoke-OERStructure began, so Invoke-OERStructure " +
            'did not apply this document and Omnicit.EntraRBAC sent nothing for it. Run Disconnect-OER as a statement of its ' +
            'own, after the commands that use the session.'
    }
    BeforeEach {
        Set-ProbeState -TenantId '44444444-4444-4444-4444-444444444444'
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup { }
    }
    AfterAll { Set-ProbeState -TenantId $null }

    It 'refuses the document with SignInSuperseded, before signing in, when a later pipeline command switched the tenant' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].TargetObject | Should -Be 'Invoke-OERStructure'
        # BL-92: the refusal says the document was not applied and that another sign-in replaced the session.
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].Exception.Message | Should -BeExactly $script:DocumentIdentityText
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'refuses when a later pipeline command signed in as another application in the same tenant' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '44444444-4444-4444-4444-444444444444' -ClientId '55555555-5555-5555-5555-555555555555' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].TargetObject | Should -Be 'Invoke-OERStructure'
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].Exception.Message | Should -BeExactly $script:DocumentIdentityText
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'refuses when a later pipeline command cleared the state (Disconnect-OER)' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId $null } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].TargetObject | Should -Be 'Invoke-OERStructure'
        # BL-92: the module holds no state, so the refusal says Disconnect-OER ended the session, not that another command signed in.
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].Exception.Message | Should -BeExactly $script:DocumentEndedText
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'refuses when the process held no session and a later pipeline command signed in' {
        Set-ProbeState -TenantId $null
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].TargetObject | Should -Be 'Invoke-OERStructure'
        # The state is held when the refusal is built (a sign-in happened), so this is the identity text, not the ended one.
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })[0].Exception.Message | Should -BeExactly $script:DocumentIdentityText
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'signs in and applies as today when the identity is unchanged' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
    }

    It 'behaves as today with -TenantId: no check, the named tenant is signed in to' {
        # The same downstream switch as the first test. With -TenantId the sign-in names its tenant,
        # so Invoke-OERStructure does not compare: it signs in to that tenant and applies.
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json $script:GroupDoc -TenantId '44444444-4444-4444-4444-444444444444' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $TenantId -eq '44444444-4444-4444-4444-444444444444' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        # Not vacuous: the downstream switch really happened before the document was processed.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }

    It 'applies a second piped document when the first one signed in from no session (snapshot taken again)' {
        # Review Focus 1: Get-ChildItem *.json | Invoke-OERStructure from a process that holds no
        # session. The snapshot is "no session"; the first document's sign-in sets a state (as a real
        # first sign-in to 'organizations' would), and the second document compares with THAT state.
        Set-ProbeState -TenantId $null
        # Defined in the module scope, so the mock's $script: is the module's own state.
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth {
                $script:_OERAuthState = @{ TenantId = 'organizations'; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global' }
            }
        }
        $Doc1 = $script:GroupDoc | ConvertFrom-Json
        $Doc2 = $script:GroupDoc | ConvertFrom-Json
        $Errs = $null
        $Out = @($Doc1, $Doc2 | Invoke-OERStructure -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 2 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 2 -Exactly
        # Not vacuous: the first sign-in really changed the state from no session.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be 'organizations'
    }

    It 'refuses every piped document when a later pipeline command switched the tenant: a refusal does not move the session the next document is compared with' {
        # A refused document signs nothing in, so the document after it is compared with the session
        # the call began with, not with the one the downstream command switched to.
        $Doc1 = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe-1" } ] }' | ConvertFrom-Json
        $Doc2 = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe-2" } ] }' | ConvertFrom-Json
        $Errs = $null
        $Out = @($Doc1, $Doc2 | Invoke-OERStructure -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        # Both documents reached the check, and both were refused.
        $Superseded = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })
        $Superseded.Count | Should -Be 2
        @($Superseded | Where-Object { $_.TargetObject -eq 'Invoke-OERStructure' }).Count | Should -Be 2
        @($Errs).Count | Should -Be 2
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'refuses the documents after one whose rows a later pipeline command answered by switching the tenant, and applies that first document' {
        # A downstream command's process block runs while Invoke-OERStructure emits a document's rows,
        # after that document signed in. A switch made there must refuse the documents after it: each
        # is compared with the session the first document signed in under, not with the one the
        # switch left. Three documents, so the third shows that the second's refusal moved nothing.
        InModuleScope Omnicit.EntraRBAC {
            Mock Sync-OERStructureGroup {
                ConvertTo-OERStructureResult -Section 'groups' -Item ([string]$Item.displayName) -Action 'Skipped' -Detail "would create group $([string]$Item.displayName)"
            }
        }
        $Doc1 = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe-1" } ] }' | ConvertFrom-Json
        $Doc2 = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe-2" } ] }' | ConvertFrom-Json
        $Doc3 = '{ "version": "1.0", "groups": [ { "displayName": "oer-bl76-probe-3" } ] }' | ConvertFrom-Json
        $RowsSeen = 0
        $Errs = $null
        $Out = @($Doc1, $Doc2, $Doc3 | Invoke-OERStructure -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Process {
                    if ($RowsSeen -eq 0) { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' }
                    $RowsSeen++
                    $_
                })
        # The first document was applied and its one row reached the downstream command.
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureResult'
        $Out[0].Item | Should -Be 'oer-bl76-probe-1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly -ParameterFilter { $Item.displayName -eq 'oer-bl76-probe-1' }
        # The second and third documents were refused, before signing in.
        $Superseded = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' })
        $Superseded.Count | Should -Be 2
        @($Superseded | Where-Object { $_.TargetObject -eq 'Invoke-OERStructure' }).Count | Should -Be 2
        @($Errs).Count | Should -Be 2
        # Not vacuous: the downstream switch really happened, on the first document's row.
        $RowsSeen | Should -Be 1
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }

    It 'applies a document piped from an upstream command that signed in in its own begin block' {
        # Review Focus 2: Get-OERInventory -TenantId A | Invoke-OERStructure -WhatIf. The upstream
        # command's begin block runs BEFORE Invoke-OERStructure's, so the snapshot already holds A.
        function Invoke-BL76UpstreamProbe {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Json)
            begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' }
            process { $Json | ConvertFrom-Json }
        }
        $Errs = $null
        $Out = @(Invoke-BL76UpstreamProbe -Json $script:GroupDoc | Invoke-OERStructure -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        # Not vacuous: the upstream begin block really switched the state away from the one the test began with.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }

    It 'reports a document that does not validate as StructureValidationFailed, not SignInSuperseded, under a changed session' {
        # Review Focus 3: the check stands after the document is read and validated, directly before
        # the sign-in, so a document that is invalid anyway reports its own error. The required
        # "version" key is missing.
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json '{ "groups": [ { "displayName": "oer-bl76-probe" } ] }' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'StructureValidationFailed*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It 'reports a document that cannot be read as InvalidStructureDocument, not SignInSuperseded, under a changed session' {
        # -ErrorVariable also collects the JSON parser's own records from inside the reader, so only
        # the two ids are counted here.
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json '{ this is not json' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidStructureDocument*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }
}

Describe 'Invoke-OERStructure refuses a document from another tenant (BL-88, A14)' {
    # A structure document that names its tenant (tenantId, which Get-OERInventory writes) is applied
    # in that tenant only. Get-OERDocumentTenantMismatch owns the comparison; Invoke-OERStructure calls
    # it twice per document: before the sign-in, against a -TenantId that is a tenant ID, and after the
    # sign-in, against the tenant the session's tokens were issued for (TokenTenantId, and
    # ArmTokenTenantId when an Azure section is applied). A refusal is DocumentTenantMismatch, written
    # as a non-terminating error before anything is read or written for the document. Initialize-OERAuth
    # stays mocked; the session is a direct write of the module state. The tenants are invented: A is
    # 4444..., B is 7777..., and cccc... is a tenant ID with letters, for the letter-case cases.
    BeforeAll {
        function script:Set-BL88ProbeState {
            param([string]$TenantId, [string]$TokenTenantId, [string]$ArmTokenTenantId)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ T = $TenantId; G = $TokenTenantId; A = $ArmTokenTenantId } {
                param($T, $G, $A)
                $script:_OERAuthState = if ($T) {
                    @{
                        TenantId = $T; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'; Environment = 'Global'
                        TokenTenantId = $(if ($G) { $G } else { $null }); ArmTokenTenantId = $(if ($A) { $A } else { $null })
                    }
                } else { $null }
            }
        }
        function script:New-BL88Doc {
            param([string]$TenantId, [string]$Name = 'oer-bl88-probe')
            '{ "version": "1.0", "tenantId": "' + $TenantId + '", "groups": [ { "displayName": "' + $Name + '" } ] }'
        }
        $script:TenantA = '44444444-4444-4444-4444-444444444444'
        $script:TenantB = '77777777-7777-7777-7777-777777777777'
    }
    BeforeEach {
        Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        InModuleScope Omnicit.EntraRBAC {
            Mock Sync-OERStructureGroup {
                ConvertTo-OERStructureResult -Section 'groups' -Item ([string]$Item.displayName) -Action 'Skipped' -Detail "would create group $([string]$Item.displayName)"
            }
            Mock Sync-OERStructureAdministrativeUnit { }
            Mock Sync-OERStructureRoleAssignment { }
            # The roleAssignments scope pre-pass resolves every scope before dispatch; no test here may
            # reach the ARM transport through it.
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { "/subscriptions/$Subscription" } elseif ($ManagementGroup) { "/providers/Microsoft.Management/managementGroups/$ManagementGroup" } else { $Scope }
            }
        }
    }
    AfterAll { Set-BL88ProbeState -TenantId $null }

    It '1: refuses the document before signing in when -TenantId names another tenant ID than the document' {
        # The sign-in, were it made, would succeed for B, as a real one would, so the comparison after it
        # would refuse the document too: what only the check before the sign-in gives is that no token
        # is requested at all, which is therefore asserted first.
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth {
                $script:_OERAuthState = @{
                    TenantId = '77777777-7777-7777-7777-777777777777'; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'
                    Environment = 'Global'; TokenTenantId = '77777777-7777-7777-7777-777777777777'
                }
            }
        }
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -TenantId $script:TenantB -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        # No token is requested for a tenant the document does not name.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch,Invoke-OERStructure'
        $Mismatch[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        $Mismatch[0].TargetObject | Should -BeExactly 'Json'
        $Mismatch[0].Exception.Message | Should -BeLike "The structure document names tenant '44444444-4444-4444-4444-444444444444', but -TenantId names tenant '77777777-7777-7777-7777-777777777777'. *"
        $Mismatch[0].Exception.Message | Should -BeLike '*nothing was signed in to, read or written for this document*'
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '2: applies the document when -TenantId names its tenant in another letter case' {
        # cccc... carries letters, so a case-sensitive comparison anywhere would refuse here.
        Set-BL88ProbeState -TenantId 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC' -TokenTenantId 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC'
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId 'cccccccc-cccc-cccc-cccc-cccccccccccc') -TenantId 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        @($Errs).Count | Should -Be 0
        $Out.Count | Should -Be 1
        $Out[0].Item | Should -BeExactly 'oer-bl88-probe'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
    }

    It '3: refuses after the sign-in when -TenantId is a domain whose token was issued for another tenant' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth {
                $script:_OERAuthState = @{
                    TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'
                    Environment = 'Global'; TokenTenantId = '77777777-7777-7777-7777-777777777777'
                }
            }
        }
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -TenantId 'contoso.onmicrosoft.com' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike "*names tenant '44444444-4444-4444-4444-444444444444', but the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'.*"
        $Mismatch[0].Exception.Message | Should -BeLike '*nothing was read or written for this document*'
        @($Errs).Count | Should -Be 1
        # The domain is not a tenant ID, so it was compared after the sign-in, through its token.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $TenantId -eq 'contoso.onmicrosoft.com' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '3b: with -TenantId organizations, does not refuse before the sign-in and refuses after it when the session is another tenant than the document''s' {
        # organizations names no tenant ID, so it is compared after the sign-in, through its token: the
        # mocked sign-in leaves the session at A, and the document names B.
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantB) -TenantId 'organizations' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $TenantId -eq 'organizations' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike "*names tenant '77777777-7777-7777-7777-777777777777', but the session's Microsoft Graph token was issued for tenant '44444444-4444-4444-4444-444444444444'.*"
        $Mismatch[0].Exception.Message | Should -BeLike '*nothing was read or written for this document*'
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '4: refuses without -TenantId when the session is another tenant, naming the document''s path' {
        Set-BL88ProbeState -TenantId $script:TenantB -TokenTenantId $script:TenantB
        $DocPath = Join-Path $TestDrive 'bl88-a.json'
        Set-Content -LiteralPath $DocPath -Value (New-BL88Doc -TenantId $script:TenantA) -Encoding utf8
        $Errs = $null
        $Out = @(Invoke-OERStructure -Path $DocPath -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].TargetObject | Should -BeExactly $DocPath
        $Mismatch[0].Exception.Message | Should -BeLike "*but the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'*"
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '5: applies without -TenantId when the session is the document''s tenant' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        @($Errs).Count | Should -Be 0
        $Out.Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
    }

    It '6: refuses a document with tenantId when the module holds no session after the sign-in' {
        Set-BL88ProbeState -TenantId $null
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike '*but the session holds no Microsoft Graph token whose tenant can be compared with it*'
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
        # Not vacuous: the sign-in really left no state.
        InModuleScope Omnicit.EntraRBAC { $null -eq $script:_OERAuthState } | Should -BeTrue
    }

    It '7: applies a document without tenantId under a session of another tenant, as before' {
        Set-BL88ProbeState -TenantId $script:TenantB -TokenTenantId $script:TenantB
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json '{ "version": "1.0", "groups": [ { "displayName": "oer-bl88-probe" } ] }' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        $Out.Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
    }

    Context '8: nothing before the sections runs for a refused document' {
        BeforeAll {
            # g1 names AU-1, so the administrative unit pre-pass runs, and g1 and AU-1 omit their
            # members (and AU-1 its scopedRoles), so -Prune writes the omitted-collection warning.
            $script:PrePassDoc = '{ "version": "1.0", "tenantId": "44444444-4444-4444-4444-444444444444", ' +
                '"groups": [ { "displayName": "g1", "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1" } ] }'
        }

        It 'writes no -Prune warning and runs no administrative unit pre-pass under a session of another tenant' {
            Set-BL88ProbeState -TenantId $script:TenantB -TokenTenantId $script:TenantB
            $Errs = $null
            $W = $null
            $Out = @(Invoke-OERStructure -Json $script:PrePassDoc -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs -WarningAction SilentlyContinue -WarningVariable W)
            $Out | Should -BeNullOrEmpty
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' }).Count | Should -Be 1
            @($Errs).Count | Should -Be 1
            @($W | Where-Object { "$_" -like 'Invoke-OERStructure: -Prune is set*' }).Count | Should -Be 0
            @($W).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureAdministrativeUnit -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
        }

        It 'control: the same document under its own tenant writes the warning and runs the pre-pass' {
            $Errs = $null
            $W = $null
            $null = @(Invoke-OERStructure -Json $script:PrePassDoc -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs -WarningAction SilentlyContinue -WarningVariable W)
            @($Errs).Count | Should -Be 0
            @($W | Where-Object { "$_" -like 'Invoke-OERStructure: -Prune is set*' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $EnsureOnly }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        }
    }

    Context '9: the Azure Resource Manager token' {
        BeforeAll {
            $script:RaDoc = '{ "version": "1.0", "tenantId": "44444444-4444-4444-4444-444444444444", ' +
                '"roleAssignments": [ { "scope": "sub:Prod", "role": "Reader", "principal": "p" } ] }'
        }

        It 'refuses a document with an Azure section when the ARM token was issued for another tenant, before the scope pre-pass' {
            Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA -ArmTokenTenantId $script:TenantB
            $Errs = $null
            $Out = @(Invoke-OERStructure -Json $script:RaDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            $Out | Should -BeNullOrEmpty
            $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
            $Mismatch.Count | Should -Be 1
            $Mismatch[0].Exception.Message | Should -BeLike "*but the session's Azure Resource Manager token was issued for tenant '77777777-7777-7777-7777-777777777777'*"
            @($Errs).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $IncludeARM }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureRoleAssignment -Times 0
        }

        It 'dispatches the Azure section when both tokens were issued for the document''s tenant' {
            Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA -ArmTokenTenantId $script:TenantA
            $Errs = $null
            $null = @(Invoke-OERStructure -Json $script:RaDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureRoleAssignment -Times 1 -Exactly
        }

        It 'refuses a document with an Azure section when the ARM token''s tenant is not a tenant ID' {
            Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA -ArmTokenTenantId 'not-a-guid'
            $Errs = $null
            $Out = @(Invoke-OERStructure -Json $script:RaDoc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            $Out | Should -BeNullOrEmpty
            $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
            $Mismatch.Count | Should -Be 1
            $Mismatch[0].Exception.Message | Should -BeLike '*but the session holds no Azure Resource Manager token whose tenant can be compared with it*'
            @($Errs).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureRoleAssignment -Times 0
        }

        It 'refuses a groups-only document under an explicit -IncludeARM when the ARM token was issued for another tenant, and applies it without -IncludeARM' {
            Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA -ArmTokenTenantId $script:TenantB
            $Errs = $null
            $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -IncludeARM -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            $Out | Should -BeNullOrEmpty
            $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
            $Mismatch.Count | Should -Be 1
            $Mismatch[0].Exception.Message | Should -BeLike "*but the session's Azure Resource Manager token was issued for tenant '77777777-7777-7777-7777-777777777777'*"
            @($Errs).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $IncludeARM }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0

            # The same document without -IncludeARM uses no ARM token, so the ARM token is not compared.
            $Errs = $null
            $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            @($Errs).Count | Should -Be 0
            $Out.Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        }

        It 'does not compare the ARM token for a document with no Azure section and no -IncludeARM' {
            Set-BL88ProbeState -TenantId $script:TenantA -TokenTenantId $script:TenantA -ArmTokenTenantId $script:TenantB
            $Errs = $null
            $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
            @($Errs).Count | Should -Be 0
            $Out.Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { -not $IncludeARM }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        }
    }

    It '10: refuses only the piped document that names another tenant and applies the next one' {
        $Doc1 = New-BL88Doc -TenantId $script:TenantB -Name 'oer-bl88-probe-1' | ConvertFrom-Json
        $Doc2 = New-BL88Doc -TenantId $script:TenantA -Name 'oer-bl88-probe-2' | ConvertFrom-Json
        $Errs = $null
        $Out = @($Doc1, $Doc2 | Invoke-OERStructure -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike "*names tenant '77777777-7777-7777-7777-777777777777', but the session's Microsoft Graph token was issued for tenant '44444444-4444-4444-4444-444444444444'*"
        $Mismatch[0].TargetObject | Should -BeExactly 'InputObject'
        @($Errs).Count | Should -Be 1
        $Out.Count | Should -Be 1
        $Out[0].Item | Should -BeExactly 'oer-bl88-probe-2'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 2 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 1 -Exactly -ParameterFilter { $Item.displayName -eq 'oer-bl88-probe-2' }
    }

    It '11: reports a tenantId that is not a tenant ID as StructureValidationFailed, before either comparison' {
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId 'contoso') -TenantId $script:TenantB -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'StructureValidationFailed*' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '12: under -ErrorAction Stop the refusal <Case> terminates the statement as DocumentTenantMismatch' -ForEach @(
        @{ Case = 'before the sign-in'; Requested = '77777777-7777-7777-7777-777777777777'; SignIns = 0 }
        @{ Case = 'after the sign-in'; Requested = $null; SignIns = 1 }
    ) {
        if (-not $Requested) { Set-BL88ProbeState -TenantId $script:TenantB -TokenTenantId $script:TenantB }
        $Params = @{ Json = (New-BL88Doc -TenantId $script:TenantA); WhatIf = $true; ErrorAction = 'Stop' }
        if ($Requested) { $Params.TenantId = $Requested }
        { Invoke-OERStructure @Params } | Should -Throw -ErrorId 'DocumentTenantMismatch*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times $SignIns -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '13: refuses after the sign-in when -TenantId is the document''s own tenant ID but the session the sign-in left is not (TokenTenantId <Case>)' -ForEach @(
        @{ Case = 'is another tenant'; Expected = "the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'" }
        @{ Case = 'is absent'; Expected = 'the session holds no Microsoft Graph token whose tenant can be compared with it' }
    ) {
        # -TenantId names the document's own tenant, so the comparison before the sign-in passes and the
        # sign-in is made. The comparison after it is NOT skipped for a -TenantId that is a tenant ID: the
        # name is what was asked for, the token is what the session was granted, and a sign-in that did
        # not take effect (or whose token carries no tenant) must not turn into an apply. The mocked
        # sign-in only sets the module state, so nothing signs in anywhere.
        if ($Case -eq 'is another tenant') {
            InModuleScope Omnicit.EntraRBAC {
                Mock Initialize-OERAuth {
                    $script:_OERAuthState = @{
                        TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'
                        Environment = 'Global'; TokenTenantId = '77777777-7777-7777-7777-777777777777'
                    }
                }
            }
        } else {
            InModuleScope Omnicit.EntraRBAC {
                Mock Initialize-OERAuth {
                    $script:_OERAuthState = @{
                        TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'
                        Environment = 'Global'; TokenTenantId = $null
                    }
                }
            }
        }
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -TenantId $script:TenantA -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike "The structure document names tenant '44444444-4444-4444-4444-444444444444', but $Expected*"
        $Mismatch[0].Exception.Message | Should -BeLike '*nothing was read or written for this document*'
        @($Errs).Count | Should -Be 1
        # The sign-in WAS made (the comparison before it passed); only the one after it refused.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $TenantId -eq '44444444-4444-4444-4444-444444444444' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
    }

    It '14: refuses a document in a real run (-Confirm:$false, no -WhatIf) without -TenantId when the session is another tenant, writing nothing' {
        Set-BL88ProbeState -TenantId $script:TenantB -TokenTenantId $script:TenantB
        $Errs = $null
        $Out = @(Invoke-OERStructure -Json (New-BL88Doc -TenantId $script:TenantA) -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Errs)
        $Out | Should -BeNullOrEmpty
        $Mismatch = @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'DocumentTenantMismatch*' })
        $Mismatch.Count | Should -Be 1
        $Mismatch[0].Exception.Message | Should -BeLike "*but the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'*"
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureGroup -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Sync-OERStructureAdministrativeUnit -Times 0
    }
}

Describe 'Invoke-OERStructure updates an access review found by name only when it reviews the declared package and policy (BL-127)' {
    # The handler finds the live access review by display name in the whole tenant, and display names
    # are not unique: here the tenant's review with the entry's name reviews a GROUP. The real engine,
    # the real handler and the real Get-OERAccessReviewTargetMismatch run; only the sign-in, the
    # definition read, the write, the lookups and the transport are mocked or faked. The review is
    # refused before any lookup and nothing is written. No id below is version-4 shaped.
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        $script:ArJson = '{ "version": "1.0", "accessReviews": [ { "displayName": "Q3 AP review", "accessPackage": "AP-Sales", ' +
            '"assignmentPolicy": "Standard", "durationInDays": 21, "reviewers": [ "person1@example.com" ] } ] }'
        $script:ArGroupScope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers'
        $script:ArRefusal = ("Access review 'Q3 AP review' in the tenant does not review an access package (its scope is " +
            "'$($script:ArGroupScope)'), so it is not the review this entry declares for access package 'AP-Sales' and assignment " +
            "policy 'Standard'. Nothing was written. Access review display names are not unique: give the entry or the review in " +
            'the tenant another display name.')
        # The public engine in a runspace through Invoke-OERWithConfirmAnswer, so no try stands anywhere
        # above it, as at a prompt. The script installs its own fakes in ITS copy of the module scope and
        # logs every lookup and write with AppendAllText, whose path is substituted into the text. #LIVE#
        # picks the review the tenant holds under the name: a group review, or the review of the declared
        # package and policy (the control). #FLAGS# are the engine's own switches.
        function New-ArNoTryScenario {
            param([string]$Log, [ValidateSet('group', 'package')][string]$Live, [string]$Flags)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Get-OERAccessReviewDefinition -Value {
        [CmdletBinding()]
        param([string]$Filter)
        $Review = [pscustomobject]@{
            Id = 'cccc3333-0000-0000-0000-000000000001'; DisplayName = 'Q3 AP review'; Status = 'InProgress'
            Scope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers'; AccessPackageId = $null; AssignmentPolicyId = $null
            Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @(); DurationInDays = 14; Settings = @{ instanceDurationInDays = 14 }
        }
        if ('#LIVE#' -eq 'package') {
            $Review.Scope = 'the declared package and policy'
            $Review.AccessPackageId = 'aaaa1111-0000-0000-0000-000000000001'
            $Review.AssignmentPolicyId = 'bbbb2222-0000-0000-0000-000000000001'
        }
        $Review
    }
    Set-Item -Path function:script:Resolve-OERAccessPackageId -Value {
        [System.IO.File]::AppendAllText('#LOG#', "LOOKUP package`n")
        'aaaa1111-0000-0000-0000-000000000001'
    }
    Set-Item -Path function:script:Resolve-OERAssignmentPolicyId -Value {
        [System.IO.File]::AppendAllText('#LOG#', "LOOKUP policy`n")
        'bbbb2222-0000-0000-0000-000000000001'
    }
    Set-Item -Path function:script:Resolve-OERStructurePrincipal -Value {
        [System.IO.File]::AppendAllText('#LOG#', "LOOKUP principal`n")
        'usr-1'
    }
    Set-Item -Path function:script:New-OERAccessReviewDefinition -Value { [System.IO.File]::AppendAllText('#LOG#', "NEW`n") }
    Set-Item -Path function:script:Set-OERAccessReviewDefinition -Value {
        [System.IO.File]::AppendAllText('#LOG#', "SET`n")
        [pscustomobject]@{
            Id = 'cccc3333-0000-0000-0000-000000000001'; DisplayName = 'Q3 AP review'; Status = 'InProgress'
            Scope = 'the declared package and policy'; AccessPackageId = 'aaaa1111-0000-0000-0000-000000000001'
            AssignmentPolicyId = 'bbbb2222-0000-0000-0000-000000000001'
            Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @(); DurationInDays = 21; Settings = @{ instanceDurationInDays = 21 }
        }
    }
}
$Json = '#JSON#'
Invoke-OERStructure -Json $Json #FLAGS# | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#LIVE#', $Live).Replace('#FLAGS#', $Flags).Replace('#JSON#', $script:ArJson.Replace("'", "''")))
        }
        function Get-ArLoggedLine {
            param([string]$Log)
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log | Where-Object { $_ }) } else { @() }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
            [PSCustomObject]@{
                Id = 'cccc3333-0000-0000-0000-000000000001'; DisplayName = 'Q3 AP review'; Status = 'InProgress'
                Scope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers'; AccessPackageId = $null; AssignmentPolicyId = $null
                Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @(); DurationInDays = 14; Settings = @{ instanceDurationInDays = 14 }
            }
        }
        Mock -ModuleName $script:moduleName Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'cccc3333-0000-0000-0000-000000000001' } }
        Mock -ModuleName $script:moduleName New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { throw 'unexpected access package lookup' }
        Mock -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId { throw 'unexpected assignment policy lookup' }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { throw 'unexpected reviewer lookup' }
    }

    It 'reports the entry Failed with the refusal, publishes it, and writes nothing to a group review that carries the entry''s name' {
        $Errs = $null
        $Rows = @(Invoke-OERStructure -Json $script:ArJson -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Errs -WarningAction SilentlyContinue)

        # Positive proof first: the review was read once, and the entry was reported.
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
        $Rows.Count | Should -Be 1
        $Rows[0].Section | Should -Be 'accessReviews'
        $Rows[0].Item | Should -Be 'Q3 AP review'
        $Rows[0].Action | Should -Be 'Failed'
        $Rows[0].Detail | Should -BeExactly $script:ArRefusal
        [string]$Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessReviewScopeMismatch*'
        $Own = @($Errs | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'AccessReviewScopeMismatch,Invoke-OERStructure' })
        $Own.Count | Should -Be 1
        $Own[0].Exception.Message | Should -BeExactly $script:ArRefusal

        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERStructurePrincipal -Times 0
    }

    It 'reaches the end of a script with no try above it, with one Failed row, and writes nothing' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-ArNoTryScenario -Log $Log -Live group -Flags '-Confirm:$false')
        $Run.Output[-1] | Should -BeExactly 'END'
        # Nothing looked up or written; a failure here prints the calls that were.
        @(Get-ArLoggedLine -Log $Log) | Should -BeNullOrEmpty
        @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @("ROW:Failed:$($script:ArRefusal)")
        @($Run.Errors) | Should -Be @($script:ArRefusal)
        @($Run.Prompts).Count | Should -Be 0
    }

    It 'ends a script with no try above it at the refusal under -ErrorAction Stop, having written nothing' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = New-ArNoTryScenario -Log $Log -Live group -Flags '-Confirm:$false -ErrorAction Stop'
        # A stop outside any try ends the whole script, so the runner throws to its caller and no line
        # after the engine, 'END' included, is reached.
        $Thrown = { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } | Should -Throw -PassThru
        $Thrown.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
        $Stopped = $Thrown.Exception.InnerException.ErrorRecord
        [string]$Stopped.FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-OERStructure'
        $Stopped.Exception.Message | Should -BeExactly $script:ArRefusal
        @(Get-ArLoggedLine -Log $Log) | Should -BeNullOrEmpty
    }

    It 'asks no confirmation before the refusal, while the review of the declared package and policy is confirmed once and written' {
        # Without -Confirm:$false the engine's ConfirmImpact High prompts at every ShouldProcess. The
        # refusal comes before any, so the group review asks nothing; the control proves the prompt count
        # is not vacuous: the matching review is looked up, confirmed once, and written.
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-ArNoTryScenario -Log $Log -Live group -Flags '')
        $Run.Output[-1] | Should -BeExactly 'END'
        @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @("ROW:Failed:$($script:ArRefusal)")
        @($Run.Prompts).Count | Should -Be 0
        @(Get-ArLoggedLine -Log $Log) | Should -BeNullOrEmpty

        $ControlLog = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Control = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-ArNoTryScenario -Log $ControlLog -Live package -Flags '')
        $Control.Output[-1] | Should -BeExactly 'END'
        @($Control.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @("ROW:Updated:updated access review 'Q3 AP review' (durationInDays=21)")
        @($Control.Prompts).Count | Should -Be 1
        @(Get-ArLoggedLine -Log $ControlLog) | Should -Be @('LOOKUP package', 'LOOKUP policy', 'LOOKUP principal', 'SET')
        @($Control.Errors).Count | Should -Be 0
    }
}

Describe 'Invoke-OERStructure -WhatIf plans a package in a catalog the document creates (BL-128, A5)' {
    # Under -WhatIf the catalogs section reports "would create catalog" and creates nothing, so the
    # catalog-scoped lookup of a package declared in it used to fail with CatalogNotFound and report
    # the package Failed ("NOT created") while the real run creates both. The real engine and the real
    # catalog and access package handlers run; the cmdlets they call are mocked. No id below is
    # version-4 shaped.
    BeforeAll {
        $script:PlanDoc = ('{ "version": "1.0", ' +
            '"catalogs": [ { "displayName": "cat-new" } ], ' +
            '"accessPackages": [ { "displayName": "ap-new", "catalog": "cat-new", ' +
            '"assignmentPolicies": [ { "displayName": "pol-new" } ] } ] }')
        $script:PlanDocNoCatalog = ('{ "version": "1.0", ' +
            '"accessPackages": [ { "displayName": "ap-new", "catalog": "cat-new", ' +
            '"assignmentPolicies": [ { "displayName": "pol-new" } ] } ] }')
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        # The catalog does not exist in the tenant.
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName New-OERCatalog { [PSCustomObject]@{ Id = '66666666-6666-6666-6666-bbbbbbbbbbbb'; DisplayName = $DisplayName } }
        Mock -ModuleName $script:moduleName Get-OERCatalogResource { @() }
        Mock -ModuleName $script:moduleName New-OERAccessPackage { [PSCustomObject]@{ Id = '66666666-6666-6666-6666-cccccccccccc'; DisplayName = $DisplayName } }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
        # What the real cmdlet does for a catalog that does not exist: one non-terminating
        # CatalogNotFound, promoted by the handler's -ErrorAction Stop. A CMDLET failure mock, never
        # Write-Error.
        Mock -ModuleName $script:moduleName Get-OERAccessPackage {
            [CmdletBinding()] param([string]$Catalog)
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Catalog '$Catalog' was not found."),
                    'CatalogNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Catalog))
        }
    }

    It 'plans the catalog, the package and its policy as created, with no Failed row and no package lookup' {
        $Rows = @(Invoke-OERStructure -Json $script:PlanDoc -WhatIf -ErrorAction Stop -WarningAction SilentlyContinue)

        @($Rows | Where-Object { $_.Section -eq 'catalogs' -and $_.Item -eq 'cat-new' -and $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create catalog cat-new' }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'ap-new' -and $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create access package ap-new' }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Item -eq 'ap-new' -and $_.Action -eq 'Skipped' -and $_.Detail -eq "would create assignmentPolicy 'pol-new' after access package is created" }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
        $Rows.Count | Should -Be 3
        # The positive control for the next lines: the catalog was looked up, so the plan was made.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
    }

    It 'still reports the package Failed, NOT created, when the document does not declare its missing catalog' {
        # The catalog is not in the document and not in the tenant: the lookup is made and fails, as it
        # does in a real run.
        $Rows = @(Invoke-OERStructure -Json $script:PlanDocNoCatalog -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-new' }
        $Failed = @($Rows | Where-Object { $_.Action -eq 'Failed' })
        $Failed.Count | Should -Be 1
        $Failed[0].Section | Should -Be 'accessPackages'
        $Failed[0].Item | Should -Be 'ap-new'
        $Failed[0].Detail | Should -Match "failed to look up access packages in catalog 'cat-new'"
        $Failed[0].Detail | Should -Match 'NOT created'
        @($Rows | Where-Object { $_.Detail -match 'would create' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
    }

    It 'does not plan the package when the plan does not include the catalogs section (-Include AccessPackages)' {
        # The catalog is declared, but the catalogs section is not dispatched, so nothing in this run
        # would create it, and the lookup fails as it would in a real run with the same -Include.
        $Rows = @(Invoke-OERStructure -Json $script:PlanDoc -Include AccessPackages -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)

        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly
        @($Rows | Where-Object { $_.Section -eq 'catalogs' }).Count | Should -Be 0
        $Failed = @($Rows | Where-Object { $_.Action -eq 'Failed' })
        $Failed.Count | Should -Be 1
        $Failed[0].Detail | Should -Match 'NOT created'
    }

    It 'is unchanged in a real run: the catalog is created and the package is then looked up in it' {
        # The catalog exists once the run has created it: the lookup finds no package in it.
        Mock -ModuleName $script:moduleName Get-OERAccessPackage { @() }
        $Doc = '{ "version": "1.0", "catalogs": [ { "displayName": "cat-new" } ], "accessPackages": [ { "displayName": "ap-new", "catalog": "cat-new" } ] }'
        $Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

        @($Rows | Where-Object { $_.Section -eq 'catalogs' -and $_.Action -eq 'Created' }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Action -eq 'Created' }).Count | Should -Be 1
        @($Rows | Where-Object { $_.Detail -match 'would' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 1 -Exactly
        # The catalog-scoped lookup ran: a real run never takes the planned shortcut.
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-new' }
        Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 1 -Exactly
    }
}

Describe 'Invoke-OERStructure renames an administrative unit, a catalog and an access package in one run (BL-128, A5)' {
    # The real engine and the real handlers run, so the rename map is the one the engine creates for the
    # document, filled by the handlers and read by the groups and access packages handlers; only the
    # sign-in, the lookups and the cmdlets the handlers call are mocked. The lookups behave as Graph's
    # do in the run that renames an object: its new name is not found by name yet, so a reference to it
    # reaches the object only through the map. No id below is version-4 shaped.
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        $script:RnUnitId = 'aaaaaaaa-0000-0000-0000-000000000001'
        $script:RnAuDoc = ('{ "version": "1.0", ' +
            '"groups": [ { "displayName": "G1", "administrativeUnit": "AU-New", "members": [] } ], ' +
            '"administrativeUnits": [ { "displayName": "AU-New", "previousDisplayName": "AU-Old", "members": [] } ] }')
        $script:RnCatDoc = ('{ "version": "1.0", ' +
            '"catalogs": [ { "displayName": "CAT-New", "previousDisplayName": "CAT-Old", "resources": [] } ], ' +
            '"accessPackages": [ { "displayName": "AP-New", "previousDisplayName": "AP-Old", "catalog": "CAT-New", "resourceRoles": [] } ] }')
        $script:RnCatConflictDoc = ('{ "version": "1.0", ' +
            '"catalogs": [ { "displayName": "CAT-New", "previousDisplayName": "CAT-Old", "resources": [] } ], ' +
            '"accessPackages": [ { "displayName": "AP-1", "catalog": "CAT-New", "resourceRoles": [] } ] }')
        function ConvertTo-RnRowLine {
            param([object[]]$Row)
            @($Row | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Section, $_.Item, $_.Action, $_.Detail })
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected Graph request: $Uri" }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) $Reference }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
        # Nothing the document renames may be created.
        Mock -ModuleName $script:moduleName New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-created'; DisplayName = $DisplayName } }
        Mock -ModuleName $script:moduleName New-OERCatalog { [PSCustomObject]@{ Id = 'cat-created'; DisplayName = $DisplayName } }
        Mock -ModuleName $script:moduleName New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-created'; DisplayName = $DisplayName } }
    }

    Context 'an administrative unit a group is created into' {
        BeforeEach {
            # Graph's name lookup finds the unit under its previous name only -- or, with OldFound
            # false, under neither name; with OldThrows the lookup of the previous name throws (an
            # ambiguous name). With NewThrowsOnce the first lookup of the new name fails (a transient
            # 502) and later ones succeed; with OtherNew another unit carries the new name.
            # LiveMembers is the unit's live member list.
            $script:RnAuState = @{ OldFound = $true; OldThrows = $false; NewThrowsOnce = $false; OtherNew = $false; LiveMembers = @() }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId {
                if ($DisplayName -eq 'AU-New' -and $script:RnAuState.NewThrowsOnce) {
                    $script:RnAuState.NewThrowsOnce = $false
                    throw 'transient 502'
                }
                if ($DisplayName -eq 'AU-New' -and $script:RnAuState.OtherNew) { 'aaaaaaaa-0000-0000-0000-000000000002' }
                if ($DisplayName -eq 'AU-Old' -and $script:RnAuState.OldThrows) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Administrative unit display name 'AU-Old' matches 2 units."),
                        'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'AU-Old')
                }
                if ($DisplayName -eq 'AU-Old' -and $script:RnAuState.OldFound) { $script:RnUnitId }
            }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = $script:RnUnitId; DisplayName = 'AU-Old'; Description = $null; MembershipType = 'Assigned'
                    Visibility = $null; IsMemberManagementRestricted = $false; Members = @($script:RnAuState.LiveMembers); ScopedRoles = @()
                }
            }
            Mock -ModuleName $script:moduleName Set-OERAdministrativeUnit { }
            Mock -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
        }

        It 'creates no unit, creates the group into the unit found under its previous name, by its id, and renames the unit once' {
            $Rows = @(Invoke-OERStructure -Json $script:RnAuDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            # Positive proof first: the group was created, into the unit's id, and the unit was renamed.
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq $script:RnUnitId }
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter {
                $AdministrativeUnit -eq $script:RnUnitId -and $NewDisplayName -eq 'AU-New'
            }
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            # The pre-pass and the administrativeUnits pass together report the unit once: the rename.
            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                'groups|G1|Created|created group G1 (88888888-8888-8888-8888-888888888888)'
                "administrativeUnits|AU-New|Updated|renamed administrative unit 'AU-Old' to 'AU-New'"
            )
        }

        It 'plans the group create and the unit rename under -WhatIf, with no unit to create and no Failed row' {
            $Rows = @(Invoke-OERStructure -Json $script:RnAuDoc -WhatIf -ErrorAction Stop -WarningAction SilentlyContinue)

            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                'groups|G1|Skipped|would create group G1'
                "administrativeUnits|AU-New|Skipped|would rename administrative unit 'AU-Old' to 'AU-New'"
            )
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 0
        }

        It 'creates neither the unit nor the group when neither name finds the unit: the group is Failed and the unit Failed with AdministrativeUnitRenameNotFound (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnAuState.OldFound = $false
            $Errs = $null
            $Params = @{ Json = $script:RnAuDoc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: both names were looked up, by the pre-pass and by the administrativeUnits pass.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 2 -Exactly -ParameterFilter { $DisplayName -eq 'AU-Old' }
            $Rows.Count | Should -Be 2
            $Rows[0].Section | Should -BeExactly 'groups'
            $Rows[0].Item | Should -BeExactly 'G1'
            $Rows[0].Action | Should -BeExactly 'Failed'
            $Rows[0].Detail | Should -BeExactly ("group not created: administrative unit 'AU-New' was not reconciled in this run -- its rename from 'AU-Old' " +
                'was refused (AdministrativeUnitRenameNotFound), so the unit the group is to be created into cannot be identified')
            $Rows[0].Error | Should -BeNullOrEmpty
            $Rows[1].Section | Should -BeExactly 'administrativeUnits'
            $Rows[1].Item | Should -BeExactly 'AU-New'
            $Rows[1].Action | Should -BeExactly 'Failed'
            [string]$Rows[1].Error.FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitRenameNotFound*'
            # One error record, the unit's: the group's row publishes none of its own (R9), and the
            # pre-pass reports nothing (R4).
            @($Errs | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Should -Be @('AdministrativeUnitRenameNotFound,Invoke-OERStructure')
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 0
        }

        It 'does not remove, under -Prune, the membership of a group the run created into the unit by its new name, while it renames the unit (BL-07)' {
            # The live unit holds the group this run creates and one member the document does not name.
            # The group's record carries the unit's id (the map's), which the administrative unit handler
            # compares as a GUID with the unit it renames.
            $script:RnAuState.LiveMembers = @(
                [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = 'G1'; Type = 'group' }
                [PSCustomObject]@{ Id = 'u-extra'; DisplayName = 'Extra'; Type = 'user' }
            )
            $Rows = @(Invoke-OERStructure -Json $script:RnAuDoc -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq $script:RnUnitId }
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $NewDisplayName -eq 'AU-New' }
            # Positive control: the member prune ran, and removed the member this run did not create.
            Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
            Should -Invoke -ModuleName $script:moduleName Remove-OERAdministrativeUnitMember -Times 1 -Exactly
            $Withheld = @($Rows | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Skipped' })
            $Withheld.Count | Should -Be 1
            $Withheld[0].Detail | Should -BeLike "prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'G1', *"
        }

        # R12: when the run cannot decide the unit's rename, the group is refused rather than created into
        # whatever unit a name lookup of 'AU-New' finds -- while another unit carries that name, that unit.
        It 'refuses the group, creating nothing and looking nothing up, when -Include leaves AdministrativeUnits out (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $Errs = $null
            $Params = @{ Json = $script:RnAuDoc; Include = 'Groups'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: the groups section ran and looked the group up.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                ("groups|G1|Failed|group not created: administrative unit 'AU-New' was not reconciled in this run -- its rename from 'AU-Old' was refused " +
                    '(the administrativeUnits section is not selected by -Include, so its rename is not reconciled in this run), so the unit the group is to be created into cannot be identified')
            )
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 0
        }

        It 'still creates the group into the unit by its name when -Include leaves AdministrativeUnits out and the unit entry renames nothing (control)' {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "G1", "administrativeUnit": "AU-1", "members": [] } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [] } ] }')
            $Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq 'AU-1' }
            @($Rows | Where-Object { $_.Section -eq 'groups' -and $_.Action -eq 'Created' }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
        }

        It 'refuses the group, creating nothing, when the pre-pass cannot look the unit''s previous name up (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnAuState.OldThrows = $true
            $Errs = $null
            $Params = @{ Json = $script:RnAuDoc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: the previous name was looked up, by the pre-pass and by the
            # administrativeUnits pass, and threw each time.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 2 -Exactly -ParameterFilter { $DisplayName -eq 'AU-Old' }
            $Rows.Count | Should -Be 3
            $Rows[0].Section | Should -BeExactly 'administrativeUnits'
            $Rows[0].Action | Should -BeExactly 'Failed'
            $Rows[0].Detail | Should -BeLike 'pre-pass handler error: *'
            $Rows[1].Section | Should -BeExactly 'groups'
            $Rows[1].Action | Should -BeExactly 'Failed'
            $Rows[1].Detail | Should -BeExactly ("group not created: administrative unit 'AU-New' was not reconciled in this run -- its rename from 'AU-Old' was refused " +
                '(one of its names could not be looked up), so the unit the group is to be created into cannot be identified')
            $Rows[1].Error | Should -BeNullOrEmpty
            $Rows[2].Section | Should -BeExactly 'administrativeUnits'
            $Rows[2].Action | Should -BeExactly 'Failed'
            $Rows[2].Detail | Should -BeLike 'handler error: *'
            # -ErrorVariable also holds each layer's copy of the thrown record, some as the exception that
            # carries it, so the count is not pinned: the lookup's error is published, and no other (the
            # group's row publishes none).
            @($Errs | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AmbiguousName*' }).Count | Should -BeGreaterThan 0
            @($Errs | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { [string]$_.FullyQualifiedErrorId } else { [string]$_.ErrorRecord.FullyQualifiedErrorId } } | Where-Object { $_ -notlike 'AmbiguousName*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 0
        }

        # The reviewer's probe: the pre-pass's lookup of the NEW name fails once (an unretried 502), and
        # every later lookup succeeds -- with another unit carrying 'AU-New'. Without a mark set before
        # that lookup the group would be created into 'AU-New' by name, which reaches that other unit.
        It 'refuses the group, creating nothing, when the pre-pass''s lookup of the unit''s new name fails once (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnAuState.NewThrowsOnce = $true
            $script:RnAuState.OtherNew = $true
            $Params = @{ Json = $script:RnAuDoc; ErrorAction = 'SilentlyContinue'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: the new name was looked up twice -- the pre-pass's failed lookup and
            # the administrativeUnits pass's successful one -- and the previous name only by that pass.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 2 -Exactly -ParameterFilter { $DisplayName -eq 'AU-New' }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AU-Old' }
            $Rows.Count | Should -Be 3
            $Rows[0].Section | Should -BeExactly 'administrativeUnits'
            $Rows[0].Action | Should -BeExactly 'Failed'
            $Rows[0].Detail | Should -BeExactly 'pre-pass handler error: transient 502'
            $Rows[1].Section | Should -BeExactly 'groups'
            $Rows[1].Action | Should -BeExactly 'Failed'
            $Rows[1].Detail | Should -BeExactly ("group not created: administrative unit 'AU-New' was not reconciled in this run -- its rename from 'AU-Old' was refused " +
                '(one of its names could not be looked up), so the unit the group is to be created into cannot be identified')
            $Rows[1].Error | Should -BeNullOrEmpty
            # The administrativeUnits pass then finds both names on different units: the conflict.
            $Rows[2].Section | Should -BeExactly 'administrativeUnits'
            $Rows[2].Action | Should -BeExactly 'Failed'
            [string]$Rows[2].Error.FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitRenameConflict*'
            Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAdministrativeUnit -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAdministrativeUnit -Times 0
        }
    }

    Context 'a catalog and an access package in it' {
        BeforeEach {
            # The live state. CatIndexed is the name Graph's name lookup finds the catalog under: it lags
            # a rename, and a test moves it on between two runs, as Graph's lookup catches up. CatName
            # and ApName are the names the two objects carry; the Set mocks change them. OtherNew puts
            # another catalog, holding no package, under the name CAT-New. With OldThrows the lookup of
            # CAT-Old throws (an ambiguous name); with NewThrowsOnce the first lookup of CAT-New fails (a
            # transient 502) and later ones succeed.
            $script:RnCatState = @{ CatName = 'CAT-Old'; CatIndexed = 'CAT-Old'; ApName = 'AP-Old'; OtherNew = $false; OldThrows = $false; NewThrowsOnce = $false }
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId {
                if ($DisplayName -eq 'CAT-New' -and $script:RnCatState.NewThrowsOnce) {
                    $script:RnCatState.NewThrowsOnce = $false
                    throw 'transient 502'
                }
                if ($DisplayName -eq 'CAT-Old' -and $script:RnCatState.OldThrows) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Catalog display name 'CAT-Old' matches 2 catalogs."),
                        'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'CAT-Old')
                }
                if ($DisplayName -eq $script:RnCatState.CatIndexed) { 'cat-old-id' }
                elseif ($script:RnCatState.OtherNew -and $DisplayName -eq 'CAT-New') { 'cat-other-id' }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = $Id; DisplayName = $script:RnCatState.CatName; Description = $null; ExternallyVisible = $false }
            }
            Mock -ModuleName $script:moduleName Set-OERCatalog { if ($NewDisplayName) { $script:RnCatState.CatName = $NewDisplayName } }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { @() }
            # The catalog's package list, asked for by the catalog's id or by the name the lookup finds it
            # under. Only filtered mocks: a list asked for under any other catalog name throws.
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-old-id'; DisplayName = $script:RnCatState.ApName }
            } -ParameterFilter { $Catalog -eq 'cat-old-id' -or ($Catalog -and $Catalog -eq $script:RnCatState.CatIndexed) }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { } -ParameterFilter {
                $Catalog -eq 'cat-other-id' -or ($script:RnCatState.OtherNew -and $Catalog -eq 'CAT-New')
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-old-id'; DisplayName = $script:RnCatState.ApName; Description = $null; IsHidden = $false }
            } -ParameterFilter { $Id -eq 'ap-old-id' }
            Mock -ModuleName $script:moduleName Set-OERAccessPackage { if ($NewDisplayName) { $script:RnCatState.ApName = $NewDisplayName } }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } } -ParameterFilter { $Uri -like '*/resourceRoleScopes*' }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
        }

        It 'plans the rename of the catalog and of the package in it under -WhatIf, with no Failed row, reading the package list by the catalog id' {
            $Rows = @(Invoke-OERStructure -Json $script:RnCatDoc -WhatIf -ErrorAction Stop -WarningAction SilentlyContinue)

            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                "catalogs|CAT-New|Skipped|would rename catalog 'CAT-Old' to 'CAT-New'"
                "accessPackages|AP-New|Skipped|would rename access package 'AP-Old' to 'AP-New'"
            )
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0 -ParameterFilter { $Catalog -eq 'CAT-New' }
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
        }

        It 'renames the catalog and the package in it once each in a real run, finding the package in the catalog by the catalog id' {
            $Rows = @(Invoke-OERStructure -Json $script:RnCatDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq 'cat-old-id' -and $NewDisplayName -eq 'CAT-New' }
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-old-id' -and $NewDisplayName -eq 'AP-New' }
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                "catalogs|CAT-New|Updated|renamed catalog 'CAT-Old' to 'CAT-New'"
                "accessPackages|AP-New|Updated|renamed access package 'AP-Old' to 'AP-New'"
            )
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
        }

        It 'converges: the same document applied again, once Graph finds the new names, reports only Unchanged and renames nothing' {
            $First = @(Invoke-OERStructure -Json $script:RnCatDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
            @($First | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 2 -Because 'the first run renames both objects'
            $script:RnCatState.CatName | Should -BeExactly 'CAT-New'
            $script:RnCatState.ApName | Should -BeExactly 'AP-New'
            # Graph's name lookup catches up with the rename.
            $script:RnCatState.CatIndexed = $script:RnCatState.CatName

            $Second = @(Invoke-OERStructure -Json $script:RnCatDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            @(ConvertTo-RnRowLine -Row $Second) | Should -Be @(
                'catalogs|CAT-New|Unchanged|catalog properties match'
                'accessPackages|AP-New|Unchanged|access package properties match'
            )
            # One Set call each, both the first run's: the second run sends none.
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 1 -Exactly
            # The second run found the catalog under its new name.
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT-New' }
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
        }

        It 'creates no package in the other catalog that carries the new name when the catalog rename conflicts: the package is Failed, with nothing read or written (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnCatState.OtherNew = $true
            $Errs = $null
            $Params = @{ Json = $script:RnCatConflictDoc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: the catalog's two names were looked up, and found on two catalogs.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-New' }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-Old' }
            $Rows.Count | Should -Be 2
            $Rows[0].Section | Should -BeExactly 'catalogs'
            $Rows[0].Action | Should -BeExactly 'Failed'
            [string]$Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'CatalogRenameConflict*'
            $Rows[1].Section | Should -BeExactly 'accessPackages'
            $Rows[1].Item | Should -BeExactly 'AP-1'
            $Rows[1].Action | Should -BeExactly 'Failed'
            $Rows[1].Detail | Should -BeExactly ("catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused (CatalogRenameConflict), " +
                'so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it')
            $Rows[1].Error | Should -BeNullOrEmpty
            @($Errs | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Should -Be @('CatalogRenameConflict,Invoke-OERStructure')
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
        }

        # R12: when the run cannot decide the catalog's rename, the package is refused rather than read and
        # created in whatever catalog a name lookup of 'CAT-New' finds -- here another catalog carries that
        # name and holds no package, so without the refusal the package would be created there.
        It 'refuses the package, reading and writing nothing for it, when -Include leaves Catalogs out (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnCatState.OtherNew = $true
            $Errs = $null
            $Params = @{ Json = $script:RnCatConflictDoc; Include = 'AccessPackages'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                ("accessPackages|AP-1|Failed|catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused " +
                    '(the catalogs section is not selected by -Include, so its rename is not reconciled in this run), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it')
            )
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
        }

        It 'still reads and creates the package in the catalog by its name when -Include leaves Catalogs out and the catalog entry renames nothing (control)' {
            $Doc = ('{ "version": "1.0", ' +
                '"catalogs": [ { "displayName": "CAT-Old", "resources": [] } ], ' +
                '"accessPackages": [ { "displayName": "AP-1", "catalog": "CAT-Old", "resourceRoles": [] } ] }')
            $Rows = @(Invoke-OERStructure -Json $Doc -Include AccessPackages -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT-Old' }
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT-Old' -and $DisplayName -eq 'AP-1' }
            @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Action -eq 'Created' }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
        }

        It 'refuses the package, reading and writing nothing for it, when the catalogs section cannot look the catalog''s previous name up (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnCatState.OtherNew = $true
            $script:RnCatState.OldThrows = $true
            $Errs = $null
            $Params = @{ Json = $script:RnCatConflictDoc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: both names were looked up, and the previous one threw.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-Old' }
            $Rows.Count | Should -Be 2
            $Rows[0].Section | Should -BeExactly 'catalogs'
            $Rows[0].Action | Should -BeExactly 'Failed'
            $Rows[0].Detail | Should -BeLike 'handler error: *'
            $Rows[1].Section | Should -BeExactly 'accessPackages'
            $Rows[1].Action | Should -BeExactly 'Failed'
            $Rows[1].Detail | Should -BeExactly ("catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused (one of its names could not be looked up), " +
                'so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it')
            $Rows[1].Error | Should -BeNullOrEmpty
            # -ErrorVariable also holds each layer's copy of the thrown record, some as the exception that
            # carries it, so the count is not pinned: the lookup's error is published, and no other (the
            # package's row publishes none).
            @($Errs | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AmbiguousName*' }).Count | Should -BeGreaterThan 0
            @($Errs | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { [string]$_.FullyQualifiedErrorId } else { [string]$_.ErrorRecord.FullyQualifiedErrorId } } | Where-Object { $_ -notlike 'AmbiguousName*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
        }

        # The reviewer's probe: the catalogs pass's lookup of the NEW name fails once (an unretried 502),
        # and the package's own lookup of 'CAT-New' a moment later succeeds -- on another catalog that
        # carries that name and holds no package. Without a mark set before that lookup the package would
        # be read from and created in that other catalog.
        It 'refuses the package, reading and writing nothing for it, when the catalogs section''s lookup of the catalog''s new name fails once (<Mode>)' -ForEach @(
            @{ Mode = 'run' }
            @{ Mode = 'WhatIf' }
        ) {
            $script:RnCatState.OtherNew = $true
            $script:RnCatState.NewThrowsOnce = $true
            $Params = @{ Json = $script:RnCatConflictDoc; ErrorAction = 'SilentlyContinue'; WarningAction = 'SilentlyContinue' }
            if ($Mode -eq 'WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
            $Rows = @(Invoke-OERStructure @Params)

            # Positive proof first: the new name's lookup was made, and threw before the previous name
            # was looked up.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-New' }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 0 -ParameterFilter { $DisplayName -eq 'CAT-Old' }
            @(ConvertTo-RnRowLine -Row $Rows) | Should -Be @(
                'catalogs|CAT-New|Failed|handler error: transient 502'
                ("accessPackages|AP-1|Failed|catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused (one of its names could not be looked up), " +
                    'so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it')
            )
            $Rows[1].Error | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERCatalog -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERCatalog -Times 0
        }
    }

    Context 'in a script with no try above it' {
        It 'reaches the end of the script and creates, reads and writes nothing for a unit, a catalog and a package none of whose names is found' {
            # The public engine in a runspace through Invoke-OERWithConfirmAnswer, so no try stands
            # anywhere above it, as at a prompt. The script installs its own fakes in ITS copy of the
            # module scope and logs every call with AppendAllText: a lookup as 'LOOKUP <kind> <name>',
            # any other call as 'CALL <command>'. A group is created into the unit, so the pre-pass and
            # the group's create path take part too.
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Json = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "G1", "administrativeUnit": "AU-New", "members": [] } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-New", "previousDisplayName": "AU-Old", "members": [] } ], ' +
                '"catalogs": [ { "displayName": "CAT-New", "previousDisplayName": "CAT-Old", "resources": [] } ], ' +
                '"accessPackages": [ { "displayName": "AP-New", "previousDisplayName": "AP-Old", "catalog": "CAT-New", "resourceRoles": [] } ] }')
            $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value { param([string]$DisplayName) [System.IO.File]::AppendAllText('#LOG#', "LOOKUP group $DisplayName`n") }
    Set-Item -Path function:script:Resolve-OERAdministrativeUnitId -Value { param([string]$DisplayName) [System.IO.File]::AppendAllText('#LOG#', "LOOKUP unit $DisplayName`n") }
    Set-Item -Path function:script:Resolve-OERCatalogId -Value { param([string]$DisplayName) [System.IO.File]::AppendAllText('#LOG#', "LOOKUP catalog $DisplayName`n") }
    Set-Item -Path function:script:New-OERGroup -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL New-OERGroup`n") }
    Set-Item -Path function:script:New-OERAdministrativeUnit -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL New-OERAdministrativeUnit`n") }
    Set-Item -Path function:script:New-OERCatalog -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL New-OERCatalog`n") }
    Set-Item -Path function:script:New-OERAccessPackage -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL New-OERAccessPackage`n") }
    Set-Item -Path function:script:Set-OERAdministrativeUnit -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Set-OERAdministrativeUnit`n") }
    Set-Item -Path function:script:Set-OERCatalog -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Set-OERCatalog`n") }
    Set-Item -Path function:script:Set-OERAccessPackage -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Set-OERAccessPackage`n") }
    Set-Item -Path function:script:Get-OERAdministrativeUnit -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Get-OERAdministrativeUnit`n") }
    Set-Item -Path function:script:Get-OERCatalog -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Get-OERCatalog`n") }
    Set-Item -Path function:script:Get-OERAccessPackage -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Get-OERAccessPackage`n") }
    Set-Item -Path function:script:Get-OERCatalogResource -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Get-OERCatalogResource`n") }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "CALL Invoke-OERGraphRequest`n") }
}
$Json = '#JSON#'
Invoke-OERStructure -Json $Json -Confirm:$false | ForEach-Object { "ROW:$($_.Section):$($_.Item):$($_.Action)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#JSON#', $Json.Replace("'", "''")))
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario

            $Run.Output[-1] | Should -BeExactly 'END'
            # Every lookup was made -- the pre-pass and each handler ran -- and nothing else was called:
            # no unit, group, catalog or package was created, read or written. A failure prints the calls.
            $Logged = if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log | Where-Object { $_ }) } else { @() }
            @($Logged) | Should -Be @(
                'LOOKUP unit AU-New', 'LOOKUP unit AU-Old', 'LOOKUP group G1', 'LOOKUP unit AU-New', 'LOOKUP unit AU-Old',
                'LOOKUP catalog CAT-New', 'LOOKUP catalog CAT-Old'
            )
            @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @(
                'ROW:groups:G1:Failed'
                'ROW:administrativeUnits:AU-New:Failed'
                'ROW:catalogs:CAT-New:Failed'
                'ROW:accessPackages:AP-New:Failed'
            )
            # Two refusals are published, the unit's and the catalog's; the two references publish none.
            @($Run.Errors).Count | Should -Be 2
            @($Run.Prompts).Count | Should -Be 0
        }

        It 'reaches the end of the script with every refused entry Failed and no write request: a failed catalog read, a policy rename conflict, a package rename that finds nothing, a review of another package found under its old name and a review of that package (BL-128 part 2, BL-144)' {
            # The same runner, with every read logged as 'READ <kind> <name or id>' and every write as
            # 'WRITE <command>'. CAT-Bad's read fails as the real cmdlet fails it (a non-terminating error
            # the handler's -ErrorAction Stop promotes); AP-Pol's two policy names find two policies;
            # AP-New's names find no package in CAT-2; R-New's previous name finds a review of another
            # access package; R-Pkg names AP-New, whose rename was refused, so it is refused through the
            # run's rename map before anything is read for it.
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Json = ('{ "version": "1.0", ' +
                '"catalogs": [ { "displayName": "CAT-Bad", "resources": [] } ], ' +
                '"accessPackages": [ ' +
                '{ "displayName": "AP-Pol", "catalog": "CAT-2", "resourceRoles": [], "assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old" } ] }, ' +
                '{ "displayName": "AP-New", "previousDisplayName": "AP-Old", "catalog": "CAT-2", "resourceRoles": [] } ], ' +
                '"accessReviews": [ ' +
                '{ "displayName": "R-New", "previousDisplayName": "R-Old", "accessPackage": "AP-Pol", "assignmentPolicy": "Standard", "reviewers": [ "person1@example.com" ] }, ' +
                '{ "displayName": "R-Pkg", "accessPackage": "AP-New", "assignmentPolicy": "Standard", "reviewers": [ "person1@example.com" ] } ] }')
            $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERStructureDefault -Value { $null }
    Set-Item -Path function:script:Resolve-OERCatalogId -Value {
        param([string]$DisplayName)
        [System.IO.File]::AppendAllText('#LOG#', "READ catalog-name $DisplayName`n")
        if ($DisplayName -eq 'CAT-Bad') { 'dddd4444-0000-0000-0000-000000000041' }
    }
    Set-Item -Path function:script:Get-OERCatalog -Value {
        [CmdletBinding()]
        param([string]$Id)
        [System.IO.File]::AppendAllText('#LOG#', "READ catalog $Id`n")
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden: the catalog read was refused.'), 'Forbidden',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $Id))
    }
    Set-Item -Path function:script:Get-OERCatalogResource -Value { [System.IO.File]::AppendAllText('#LOG#', "READ catalog-resources`n") }
    Set-Item -Path function:script:Get-OERAccessPackage -Value {
        [CmdletBinding()]
        param([string]$Catalog, [string]$Id)
        if ($Catalog) {
            [System.IO.File]::AppendAllText('#LOG#', "READ packages $Catalog`n")
            [pscustomobject]@{ Id = 'aaaa1111-0000-0000-0000-000000000041'; DisplayName = 'AP-Pol' }
        } else {
            [System.IO.File]::AppendAllText('#LOG#', "READ package $Id`n")
            [pscustomobject]@{ Id = $Id; DisplayName = 'AP-Pol'; Description = $null; IsHidden = $false }
        }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Uri)
        [System.IO.File]::AppendAllText('#LOG#', "READ graph $(($Uri -split '\?')[0])`n")
        @{ value = @() }
    }
    Set-Item -Path function:script:Get-OERAccessPackageAssignmentPolicy -Value {
        [CmdletBinding()]
        param([string]$AccessPackage)
        [System.IO.File]::AppendAllText('#LOG#', "READ policies $AccessPackage`n")
        [pscustomobject]@{ Id = 'bbbb2222-0000-0000-0000-000000000041'; DisplayName = 'POL-New'; RequestorScope = @{ scope = 'allMemberUsers' } }
        [pscustomobject]@{ Id = 'bbbb2222-0000-0000-0000-000000000042'; DisplayName = 'POL-Old'; RequestorScope = @{ scope = 'allMemberUsers' } }
    }
    Set-Item -Path function:script:Get-OERAccessReviewDefinition -Value {
        [CmdletBinding()]
        param([string]$Filter)
        [System.IO.File]::AppendAllText('#LOG#', "READ reviews $Filter`n")
        [pscustomobject]@{
            Id = 'cccc3333-0000-0000-0000-000000000041'; DisplayName = 'R-Old'; Status = 'InProgress'
            Scope = 'another access package'; AccessPackageId = 'aaaa1111-0000-0000-0000-000000000049'; AssignmentPolicyId = 'bbbb2222-0000-0000-0000-000000000049'
            Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @(); DurationInDays = 14; Settings = @{ instanceDurationInDays = 14 }
        }
    }
    Set-Item -Path function:script:Resolve-OERAccessPackageId -Value {
        param([string]$DisplayName)
        [System.IO.File]::AppendAllText('#LOG#', "READ package-name $DisplayName`n")
        if ($DisplayName -eq 'AP-Pol') { 'aaaa1111-0000-0000-0000-000000000041' } else { 'aaaa1111-0000-0000-0000-000000000048' }
    }
    Set-Item -Path function:script:Resolve-OERAssignmentPolicyId -Value { [System.IO.File]::AppendAllText('#LOG#', "READ policy-name`n"); 'bbbb2222-0000-0000-0000-000000000041' }
    Set-Item -Path function:script:Resolve-OERStructurePrincipal -Value { [System.IO.File]::AppendAllText('#LOG#', "READ principal`n"); 'usr-1' }
    foreach ($Write in @('New-OERCatalog', 'Set-OERCatalog', 'Add-OERCatalogResource', 'Remove-OERCatalogResource', 'New-OERAccessPackage',
            'Set-OERAccessPackage', 'Add-OERAccessPackageResourceRole', 'Remove-OERAccessPackageResourceRole', 'New-OERAccessPackageAssignmentPolicy',
            'Set-OERAccessPackageAssignmentPolicy', 'New-OERAccessReviewDefinition', 'Set-OERAccessReviewDefinition')) {
        Set-Item -Path "function:script:$Write" -Value ([scriptblock]::Create("[System.IO.File]::AppendAllText('#LOG#', 'WRITE $Write' + [char]10)"))
    }
}
$Json = '#JSON#'
Invoke-OERStructure -Json $Json -Confirm:$false | ForEach-Object { "ROW:$($_.Section):$($_.Item):$($_.Action)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#JSON#', $Json.Replace("'", "''")))
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario

            $Run.Output[-1] | Should -BeExactly 'END'
            # Positive proof first: every section ran and made its reads -- and R-Pkg made none. No write.
            $Logged = if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log | Where-Object { $_ }) } else { @() }
            @($Logged) | Should -Be @(
                'READ catalog-name CAT-Bad', 'READ catalog dddd4444-0000-0000-0000-000000000041'
                'READ packages CAT-2', 'READ package aaaa1111-0000-0000-0000-000000000041'
                'READ graph v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000041/resourceRoleScopes'
                'READ policies aaaa1111-0000-0000-0000-000000000041'
                'READ packages CAT-2'
                "READ reviews displayName eq 'R-New'", "READ reviews displayName eq 'R-Old'", 'READ package-name AP-Pol'
            )
            @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @(
                'ROW:catalogs:CAT-Bad:Failed'
                'ROW:accessPackages:AP-Pol:Unchanged'
                'ROW:accessPackages:AP-Pol:Failed'
                'ROW:accessPackages:AP-New:Failed'
                'ROW:accessReviews:R-New:Failed'
                'ROW:accessReviews:R-Pkg:Failed'
            )
            # Four refusals are published -- the catalog read, the policy conflict, the package rename and
            # the review of another package; the review refused through the map publishes none.
            @($Run.Errors).Count | Should -Be 4
            @($Run.Prompts).Count | Should -Be 0
        }
    }
}

Describe 'Invoke-OERStructure: an access review reaches an access package or assignment policy the same document renames (BL-128 part 2)' {
    # The real engine, the real access package and access review handlers, the real rename map and the
    # real target check run; only the sign-in, the lookups and the cmdlets the handlers call are mocked.
    # The lookups behave as Graph's do in the run that renames: the new name of a package or policy is
    # not found under it yet -- here another package or policy carries it -- so a review naming it
    # reaches the renamed object only through the map. No id below is version-4 shaped.
    BeforeAll {
        $script:RvPkgId = 'aaaa1111-0000-0000-0000-000000000031'
        $script:RvOtherPkgId = 'aaaa1111-0000-0000-0000-000000000032'
        $script:RvPolOldId = 'bbbb2222-0000-0000-0000-000000000031'
        $script:RvOtherPolId = 'bbbb2222-0000-0000-0000-000000000032'
        $script:RvStdPolId = 'bbbb2222-0000-0000-0000-000000000033'
        $script:RvReview = ('{ "displayName": "Q3 AP review", "accessPackage": "#PKG#", "assignmentPolicy": "#POL#", "durationInDays": 21, ' +
            '"reviewers": [ "person1@example.com" ] }')
        # A package the document renames, and a review of it by its new name.
        $script:RvPkgDoc = ('{ "version": "1.0", ' +
            '"accessPackages": [ { "displayName": "AP-New", "previousDisplayName": "AP-Old", "catalog": "CAT-1", "resourceRoles": [] } ], ' +
            '"accessReviews": [ ' + $script:RvReview.Replace('#PKG#', 'AP-New').Replace('#POL#', 'Standard') + ' ] }')
        # A policy the document renames in a package it does not rename, and a review of it by its new
        # name, the package named by name or by id.
        function New-RvPolDoc {
            param([string]$ReviewPackage = 'AP-1')
            ('{ "version": "1.0", ' +
                '"accessPackages": [ { "displayName": "AP-1", "catalog": "CAT-1", "resourceRoles": [], ' +
                '"assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old" } ] } ], ' +
                '"accessReviews": [ ' + $script:RvReview.Replace('#PKG#', $ReviewPackage).Replace('#POL#', 'POL-New') + ' ] }')
        }
        # The live review: it reviews the package and the policy the document means.
        function New-RvLive {
            param([string]$AssignmentPolicyId = $script:RvStdPolId, [int]$DurationInDays = 14)
            [PSCustomObject]@{
                Id = 'cccc3333-0000-0000-0000-000000000031'; DisplayName = 'Q3 AP review'; Status = 'InProgress'
                Scope = 'the declared package and policy'; AccessPackageId = $script:RvPkgId; AssignmentPolicyId = $AssignmentPolicyId
                Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @(); DurationInDays = $DurationInDays
                Settings = @{ instanceDurationInDays = $DurationInDays }
            }
        }
        # A live policy as Get-OERAccessPackageAssignmentPolicy returns it: the raw Graph object, projected
        # by the real converter.
        function New-RvPolicy {
            param([string]$Id, [string]$DisplayName)
            $Raw = @{
                id                      = $Id
                displayName             = $DisplayName
                description             = 'live description'
                accessPackage           = @{ id = 'aaaa1111-0000-0000-0000-000000000031' }
                allowedTargetScope      = 'allMemberUsers'
                specificAllowedTargets  = @()
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $false
                    isApprovalRequiredForUpdate      = $false
                    isRequestorJustificationRequired = $false
                    stages                           = @()
                }
                notificationSettings    = @{ isAssignmentNotificationDisabled = $false }
            }
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Raw = $Raw } {
                param($Raw)
                ConvertTo-OERAssignmentPolicy -InputObject $Raw
            }
        }
        function ConvertTo-RvRowLine {
            param([object[]]$Row)
            @($Row | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Section, $_.Item, $_.Action, $_.Detail })
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        # The live state: the packages catalog CAT-1 holds, the raw policies of the package, and the
        # review the definition lookup finds ($null: none).
        $script:RvState = @{
            Packages = @([PSCustomObject]@{ Id = $script:RvPkgId; DisplayName = 'AP-Old' })
            Policies = @()
            Review   = (New-RvLive)
        }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected Graph request: $Uri" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } } -ParameterFilter { $Uri -like '*/resourceRoleScopes*' }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { 'usr-1' }
        Mock -ModuleName $script:moduleName Get-OERAccessPackage {
            if ($Catalog) { return @($script:RvState.Packages) }
            foreach ($Package in @($script:RvState.Packages)) {
                if ([string]$Package.Id -eq $Id) { [PSCustomObject]@{ Id = $Package.Id; DisplayName = $Package.DisplayName; Description = $null; IsHidden = $false } }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @($script:RvState.Policies) }
        Mock -ModuleName $script:moduleName Set-OERAccessPackage { }
        Mock -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy { }
        Mock -ModuleName $script:moduleName New-OERAccessPackage { throw 'unexpected access package create' }
        Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { throw 'unexpected assignment policy create' }
        Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition { $script:RvState.Review }
        # Graph's tenant-wide name lookups in the run that renames: the names nothing renames resolve to
        # the objects the document means; the new names to OTHER objects that carry them.
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId {
            if ($DisplayName -eq 'AP-1') { 'aaaa1111-0000-0000-0000-000000000031' } else { 'aaaa1111-0000-0000-0000-000000000032' }
        }
        Mock -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId {
            if ($AssignmentPolicy -eq 'Standard') { 'bbbb2222-0000-0000-0000-000000000033' } else { 'bbbb2222-0000-0000-0000-000000000032' }
        }
        Mock -ModuleName $script:moduleName New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
        Mock -ModuleName $script:moduleName Set-OERAccessReviewDefinition {
            New-RvLive -AssignmentPolicyId $script:RvState.Review.AssignmentPolicyId -DurationInDays 21
        }
    }

    It 'renames the package and updates its review by the package''s id, with no package lookup (<Mode>)' -ForEach @(
        @{ Mode = 'a real run'; PlanOnly = $false; Sets = 1; Expected = @(
                "accessPackages|AP-New|Updated|renamed access package 'AP-Old' to 'AP-New'"
                "accessReviews|Q3 AP review|Updated|updated access review 'Q3 AP review' (durationInDays=21)"
            )
        }
        @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true; Sets = 0; Expected = @(
                "accessPackages|AP-New|Skipped|would rename access package 'AP-Old' to 'AP-New'"
                "accessReviews|Q3 AP review|Skipped|would update access review 'Q3 AP review' (durationInDays=21)"
            )
        }
    ) {
        $Params = @{ Json = $script:RvPkgDoc; ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
        if ($PlanOnly) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be $Expected
        # The review's package was compared by the map's id: the tenant-wide lookup of 'AP-New', which
        # here finds another package, was never made. Its policy was looked up within that package.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 1 -Exactly -ParameterFilter {
            $AccessPackageId -eq 'aaaa1111-0000-0000-0000-000000000031' -and $AssignmentPolicy -eq 'Standard'
        }
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times $Sets -Exactly
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times $Sets -Exactly
    }

    It 'renames the package and creates its review on the package''s id (<Mode>)' -ForEach @(
        @{ Mode = 'a real run'; PlanOnly = $false; News = 1; ReviewRow = "accessReviews|Q3 AP review|Created|created access review 'Q3 AP review' (recurrence: OneTime)" }
        @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true; News = 0; ReviewRow = "accessReviews|Q3 AP review|Skipped|would create access review 'Q3 AP review'" }
    ) {
        $script:RvState.Review = $null
        $Params = @{ Json = $script:RvPkgDoc; ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
        if ($PlanOnly) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows)[-1] | Should -BeExactly $ReviewRow
        @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times $News -Exactly
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times $News -Exactly -ParameterFilter {
            $AccessPackage -eq 'aaaa1111-0000-0000-0000-000000000031' -and $AssignmentPolicy -eq 'Standard'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
    }

    It 'renames the policy and updates its review by the policy''s id, the package named by <Key> (<Mode>)' -ForEach @(
        @{ Key = 'name'; Package = 'AP-1'; PackageLookups = 1; Mode = 'a real run'; PlanOnly = $false; Sets = 1; Expected = @(
                'accessPackages|AP-1|Unchanged|access package properties match'
                "accessPackages|AP-1|Updated|renamed assignmentPolicy 'POL-Old' to 'POL-New'"
                "accessReviews|Q3 AP review|Updated|updated access review 'Q3 AP review' (durationInDays=21)"
            )
        }
        @{ Key = 'id'; Package = 'aaaa1111-0000-0000-0000-000000000031'; PackageLookups = 0; Mode = 'a real run'; PlanOnly = $false; Sets = 1; Expected = @(
                'accessPackages|AP-1|Unchanged|access package properties match'
                "accessPackages|AP-1|Updated|renamed assignmentPolicy 'POL-Old' to 'POL-New'"
                "accessReviews|Q3 AP review|Updated|updated access review 'Q3 AP review' (durationInDays=21)"
            )
        }
        @{ Key = 'name'; Package = 'AP-1'; PackageLookups = 1; Mode = 'a plan under -WhatIf'; PlanOnly = $true; Sets = 0; Expected = @(
                'accessPackages|AP-1|Unchanged|access package properties match'
                "accessPackages|AP-1|Skipped|would rename assignmentPolicy 'POL-Old' to 'POL-New'"
                "accessReviews|Q3 AP review|Skipped|would update access review 'Q3 AP review' (durationInDays=21)"
            )
        }
    ) {
        $script:RvState.Packages = @([PSCustomObject]@{ Id = $script:RvPkgId; DisplayName = 'AP-1' })
        $script:RvState.Policies = @(New-RvPolicy -Id $script:RvPolOldId -DisplayName 'POL-Old')
        $script:RvState.Review = New-RvLive -AssignmentPolicyId $script:RvPolOldId
        $Params = @{ Json = (New-RvPolDoc -ReviewPackage $Package); ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
        if ($PlanOnly) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be $Expected
        # The review's policy was compared by the map's id: the lookup of 'POL-New', which here finds
        # another policy, was never made.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times $PackageLookups -Exactly
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times $Sets -Exactly
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times $Sets -Exactly -ParameterFilter {
            $Id -eq 'bbbb2222-0000-0000-0000-000000000031' -and $DisplayName -eq 'POL-New'
        }
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times $Sets -Exactly
    }

    It 'refuses the review of a <Case> the document renames, reading and writing nothing for it, when -Include leaves AccessPackages out (<Mode>)' -ForEach @(
        foreach ($Mode in @('a real run', 'a plan under -WhatIf')) {
            @{ Case = 'package'; Mode = $Mode; Doc = 'package'
                Detail = ("access package 'AP-New' was not reconciled in this run: its rename from 'AP-Old' was refused (the accessPackages section " +
                    'is not selected by -Include, so its rename is not reconciled in this run), so the access package this access review reviews ' +
                    'cannot be identified; nothing was created, read or written for it')
            }
            @{ Case = 'policy'; Mode = $Mode; Doc = 'policy'
                Detail = ("assignment policy 'POL-New' of access package 'AP-1' was not reconciled in this run: its rename from 'POL-Old' was " +
                    'refused (the accessPackages section is not selected by -Include, so its rename is not reconciled in this run), so the ' +
                    'assignment policy this access review reviews cannot be identified; nothing was created, read or written for it')
            }
        }
    ) {
        $Errs = $null
        $Json = if ($Doc -eq 'package') { $script:RvPkgDoc } else { New-RvPolDoc }
        $Params = @{ Json = $Json; Include = 'AccessReviews'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
        if ($Mode -eq 'a plan under -WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be @("accessReviews|Q3 AP review|Failed|$Detail")
        $Rows[0].Error | Should -BeNullOrEmpty
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times 0
    }

    # The access package handler's own undecided marks (R12, D4): its entry stops before it decides a
    # rename, so the review that names the new name is refused with the handler's reason, and nothing is
    # read or written for it. A review that names the package by its OBJECT ID reads the policy's mark
    # under the package id, which the handler registers as soon as it has found the package (Sprint 11
    # step 4b, Fix B); before that it looked the policy's new name up by name within the package.
    It 'refuses the review of <Case> when the access package entry stops before it decides the rename (<Mode>)' -ForEach @(
        foreach ($Mode in @('a real run', 'a plan under -WhatIf')) {
            @{ Case = 'a package by its new name'; Mode = $Mode; Doc = 'package'
                Expected = @(
                    "accessPackages|AP-New|Failed|failed to look up access packages in catalog 'CAT-1': transient Graph failure; the access package was NOT created"
                    ("accessReviews|Q3 AP review|Failed|access package 'AP-New' was not reconciled in this run: its rename from 'AP-Old' was refused " +
                        "(the accessPackages entry did not reach a decision in this run; see that entry's rows), so the access package this access " +
                        'review reviews cannot be identified; nothing was created, read or written for it')
                )
            }
            @{ Case = 'a policy by its new name, the package named by its object id'; Mode = $Mode; Doc = 'policy'
                Expected = @(
                    'accessPackages|AP-1|Unchanged|access package properties match'
                    "accessPackages|AP-1|Failed|failed to read the current assignment policies of access package 'AP-1': transient policies failure; no assignmentPolicy was created or updated"
                    ("accessReviews|Q3 AP review|Failed|assignment policy 'POL-New' of access package 'aaaa1111-0000-0000-0000-000000000031' was not " +
                        "reconciled in this run: its rename from 'POL-Old' was refused (the accessPackages entry did not reach a decision in this run; " +
                        "see that entry's rows), so the assignment policy this access review reviews cannot be identified; nothing was created, read or " +
                        'written for it')
                )
            }
        }
    ) {
        if ($Doc -eq 'package') {
            # The catalog's package list cannot be read: the entry stops before either name is matched.
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { throw 'transient Graph failure' } -ParameterFilter { $Catalog }
            $Json = $script:RvPkgDoc
        } else {
            # The package is found by its name; its policy list cannot be read, so the policy's rename is
            # never decided. The review names the package by its object id.
            $script:RvState.Packages = @([PSCustomObject]@{ Id = $script:RvPkgId; DisplayName = 'AP-1' })
            $script:RvState.Policies = @(New-RvPolicy -Id $script:RvPolOldId -DisplayName 'POL-Old')
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { throw 'transient policies failure' } -ParameterFilter {
                $AccessPackage -eq 'aaaa1111-0000-0000-0000-000000000031'
            }
            $Json = New-RvPolDoc -ReviewPackage $script:RvPkgId
        }
        $Errs = $null
        $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
        if ($Mode -eq 'a plan under -WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be $Expected
        # The review's row publishes no record of its own; the one record the engine published is the
        # package entry's failed read (-ErrorVariable also holds the inner layers of the mock's throw).
        $Rows[-1].Error | Should -BeNullOrEmpty
        $Own = @($Errs | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId.EndsWith(',Invoke-OERStructure') })
        $Own.Count | Should -Be 1
        $Own[0].Exception.Message | Should -BeExactly $Rows[-2].Error.Exception.Message
        # Nothing was read or written for the review: no definition read, no name lookup of its package or
        # policy (the policy's new name would find another policy here), no write.
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 0
    }

    # Fix round 2: a package rename refused as a conflict names two packages; the entry marks its renaming
    # policies under both ids, so a review that names either package by object id and the policy by its
    # new name is refused with the handler's reason instead of looking the policy up by name.
    It 'refuses the review of a policy by its new name, the package named by the <Which> id of a refused rename conflict (<Mode>)' -ForEach @(
        @{ Which = 'previous name''s'; PackageId = 'aaaa1111-0000-0000-0000-000000000031'; Mode = 'a real run' }
        @{ Which = 'new name''s'; PackageId = 'aaaa1111-0000-0000-0000-000000000032'; Mode = 'a real run' }
        @{ Which = 'previous name''s'; PackageId = 'aaaa1111-0000-0000-0000-000000000031'; Mode = 'a plan under -WhatIf' }
    ) {
        # Catalog CAT-1 holds both names: 'AP-New' is another package, 'AP-Old' the one the entry renames.
        $script:RvState.Packages = @(
            [PSCustomObject]@{ Id = $script:RvOtherPkgId; DisplayName = 'AP-New' }
            [PSCustomObject]@{ Id = $script:RvPkgId; DisplayName = 'AP-Old' }
        )
        $Json = ('{ "version": "1.0", ' +
            '"accessPackages": [ { "displayName": "AP-New", "previousDisplayName": "AP-Old", "catalog": "CAT-1", "resourceRoles": [], ' +
            '"assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old" } ] } ], ' +
            '"accessReviews": [ ' + $script:RvReview.Replace('#PKG#', $PackageId).Replace('#POL#', 'POL-New') + ' ] }')
        $Errs = $null
        $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Errs'; WarningAction = 'SilentlyContinue' }
        if ($Mode -eq 'a plan under -WhatIf') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
        $Rows = @(Invoke-OERStructure @Params)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be @(
            ("accessPackages|AP-New|Failed|both 'AP-New' and its previousDisplayName 'AP-Old' exist in catalog 'CAT-1' as different access packages; " +
                'the document never merges two access packages, so nothing was changed -- rename or delete one of them, or remove previousDisplayName')
            ("accessReviews|Q3 AP review|Failed|assignment policy 'POL-New' of access package '$PackageId' was not reconciled in this run: its rename " +
                "from 'POL-Old' was refused (the accessPackages entry did not reach a decision in this run; see that entry's rows), so the assignment " +
                'policy this access review reviews cannot be identified; nothing was created, read or written for it')
        )
        # The conflict's record is the one the engine published; the review's row carries none.
        $Rows[1].Error | Should -BeNullOrEmpty
        $Own = @($Errs | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId.EndsWith(',Invoke-OERStructure') })
        $Own.Count | Should -Be 1
        $Own[0].FullyQualifiedErrorId | Should -BeExactly 'AccessPackageRenameConflict,Invoke-OERStructure'
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackage -Times 0
    }

    It 'still updates a review by name when -Include leaves AccessPackages out and nothing it names is renamed (control)' {
        $Doc = ('{ "version": "1.0", ' +
            '"accessPackages": [ { "displayName": "AP-1", "catalog": "CAT-1", "resourceRoles": [], "assignmentPolicies": [ { "displayName": "Standard" } ] } ], ' +
            '"accessReviews": [ ' + $script:RvReview.Replace('#PKG#', 'AP-1').Replace('#POL#', 'Standard') + ' ] }')
        $Rows = @(Invoke-OERStructure -Json $Doc -Include AccessReviews -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

        @(ConvertTo-RvRowLine -Row $Rows) | Should -Be @("accessReviews|Q3 AP review|Updated|updated access review 'Q3 AP review' (durationInDays=21)")
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-1' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAssignmentPolicyId -Times 1 -Exactly -ParameterFilter { $AssignmentPolicy -eq 'Standard' }
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
    }

    It 'skips an entry or a policy without a usable name when -Include leaves AccessPackages out, so no binding error ends the run' {
        # The validator refuses such names, so the document is let through here as the engine would see
        # it if a name were empty; each entry whose names cannot be registered is skipped, the named
        # policy renames of the other entry are still registered, and the run completes.
        Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @(); Findings = @() } }
        $Doc = ('{ "version": "1.0", ' +
            '"accessPackages": [ ' +
            '{ "displayName": "", "previousDisplayName": "AP-Old", "catalog": "CAT-1", "assignmentPolicies": [ { "displayName": "POL-X", "previousDisplayName": "POL-Y" } ] }, ' +
            '{ "displayName": "AP-2", "previousDisplayName": "", "catalog": "CAT-1" }, ' +
            '{ "catalog": "CAT-1", "previousDisplayName": "AP-Old" }, ' +
            '{ "displayName": "AP-1", "catalog": "CAT-1", "assignmentPolicies": [ ' +
            '{ "displayName": "", "previousDisplayName": "POL-Old" }, { "displayName": "POL-A", "previousDisplayName": "" }, null, ' +
            '{ "displayName": "POL-New", "previousDisplayName": "POL-Old" } ] } ], ' +
            '"accessReviews": [ ' + $script:RvReview.Replace('#PKG#', 'AP-1').Replace('#POL#', 'POL-New') + ' ] }')
        $Rows = @(Invoke-OERStructure -Json $Doc -Include AccessReviews -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)

        # Positive proof that the marking ran past the skipped entries: the policy of the last one is
        # registered, so the review that names it is refused.
        @($Rows).Count | Should -Be 1
        $Rows[0].Section | Should -BeExactly 'accessReviews'
        $Rows[0].Action | Should -BeExactly 'Failed'
        $Rows[0].Detail | Should -BeLike "assignment policy 'POL-New' of access package 'AP-1' was not reconciled in this run: *"
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 0
    }
}

Describe 'Invoke-OERStructure applies what an export writes by id: a package''s catalog and a review''s access package and assignment policy (BL-39, BL-142)' {
    # Get-OERInventory writes an access package's catalog as the catalog's object id when another catalog
    # carries its name, and an access review's accessPackage and assignmentPolicy as their ids when the
    # engine's own name lookup would not find that object alone. These prove such entries apply: the real
    # engine, the real handlers, the real cmdlets they call and the real lookups run (Resolve-OERCatalogId,
    # Resolve-OERAccessPackageId, Resolve-OERAssignmentPolicyId, Get-OERAccessReviewTargetMismatch,
    # Resolve-OERAccessReviewChange); only the sign-in and the transport are faked, by a tenant that keeps
    # what the first run creates. Each document is applied twice: created, then Unchanged. No id below is
    # version-4 shaped.
    BeforeAll {
        $script:IdCatId = 'eeee5555-0000-0000-0000-000000000051'
        $script:IdNewPkgId = 'aaaa1111-0000-0000-0000-000000000052'
        $script:IdPkgId = 'aaaa1111-0000-0000-0000-000000000051'
        $script:IdPolId = 'bbbb2222-0000-0000-0000-000000000051'
        # The entry as the export writes it, the catalog by its id.
        $script:IdPackageDoc = ('{ "version": "1.0", "accessPackages": [ { "displayName": "AP-ById", ' +
            '"catalog": "eeee5555-0000-0000-0000-000000000051", "hidden": false, "resourceRoles": [], "assignmentPolicies": [] } ] }')
        $script:IdReviewDoc = ('{ "version": "1.0", "accessReviews": [ { "displayName": "Q3 by id", ' +
            '"accessPackage": "aaaa1111-0000-0000-0000-000000000051", "assignmentPolicy": "bbbb2222-0000-0000-0000-000000000051", ' +
            '"reviewers": [], "durationInDays": 14 } ] }')
        function script:ConvertTo-IdRowLine {
            param([object[]]$Row)
            @($Row | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Section, $_.Item, $_.Action, $_.Detail })
        }
        # The requests of one run, as '<METHOD> <uri>', taken from the fake tenant's log.
        function script:Get-IdRequest {
            param([int]$From)
            @($script:IdTenant.Requests | Select-Object -Skip $From)
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        # The tenant: the access package a review is made for (in another catalog), and nothing else.
        $script:IdTenant = @{
            Packages = [System.Collections.Generic.List[object]]::new()
            Reviews  = [System.Collections.Generic.List[object]]::new()
            Requests = [System.Collections.Generic.List[string]]::new()
            Posts    = [System.Collections.Generic.List[object]]::new()
        }
        $script:IdTenant.Packages.Add(@{
                id = 'aaaa1111-0000-0000-0000-000000000051'; displayName = 'AP-Review'; description = $null; isHidden = $false
                catalog = @{ id = 'eeee5555-0000-0000-0000-000000000052' }
            })
        # The transport, answering every request these entries make as Microsoft Graph does, and refusing
        # any other. Single-quoted prefixes keep '$filter' and '$expand' literal.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Verb = if ($Method) { ([string]$Method).ToUpperInvariant() } else { 'GET' }
            $script:IdTenant.Requests.Add("$Verb $Uri")
            $ApBase = 'v1.0/identityGovernance/entitlementManagement/accessPackages'
            $ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
            if ($Verb -eq 'POST' -and $Uri -eq $ApBase) {
                $script:IdTenant.Posts.Add($Body)
                $Created = @{
                    id = 'aaaa1111-0000-0000-0000-000000000052'; displayName = $Body.displayName; description = $Body.description
                    isHidden = [bool]$Body.isHidden; catalog = @{ id = $Body.catalog.id }
                }
                $script:IdTenant.Packages.Add($Created)
                # Graph answers the create with the entity, which carries no catalog.
                return @{ id = $Created.id; displayName = $Created.displayName; description = $Created.description; isHidden = $Created.isHidden }
            }
            if ($Verb -eq 'POST' -and $Uri -eq $ArBase) {
                $script:IdTenant.Posts.Add($Body)
                $Created = @{ id = 'cccc3333-0000-0000-0000-000000000051'; status = 'InProgress' }
                foreach ($Key in $Body.Keys) { $Created[$Key] = $Body[$Key] }
                $script:IdTenant.Reviews.Add($Created)
                return $Created
            }
            if ($Verb -ne 'GET') { throw "unexpected Graph request: $Verb $Uri" }
            $ByCatalog = $ApBase + '?$filter=catalog/id eq '''
            if ($Uri.StartsWith($ByCatalog)) {
                $CatalogId = $Uri.Substring($ByCatalog.Length).Split("'")[0]
                return @{ value = @($script:IdTenant.Packages | Where-Object { $_.catalog.id -eq $CatalogId }) }
            }
            $ByName = $ApBase + '?$filter=displayName eq '''
            if ($Uri.StartsWith($ByName)) {
                $Name = [uri]::UnescapeDataString($Uri.Substring($ByName.Length).Split("'")[0]).Replace("''", "'")
                return @{ value = @($script:IdTenant.Packages | Where-Object { $_.displayName -eq $Name } | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } }) }
            }
            if ($Uri.StartsWith($ApBase + '/')) {
                $Rest = $Uri.Substring($ApBase.Length + 1)
                $PackageId = ($Rest -split '[/?]')[0]
                if ($Rest -like '*/resourceRoleScopes*') { return @{ value = @() } }
                $Package = @($script:IdTenant.Packages | Where-Object { $_.id -eq $PackageId })
                if ($Package.Count -eq 1) { return $Package[0] }
                throw "unexpected Graph request for a package the tenant does not hold: $Verb $Uri"
            }
            if ($Uri.StartsWith('v1.0/identityGovernance/entitlementManagement/assignmentPolicies?$filter=accessPackage/id eq ')) {
                return @{ value = @() }
            }
            $ReviewByFilter = $ArBase + '?$filter='
            if ($Uri.StartsWith($ReviewByFilter)) {
                $Filter = [uri]::UnescapeDataString($Uri.Substring($ReviewByFilter.Length))
                $ReviewName = if ($Filter -match "^displayName eq '(.*)'$") { $Matches[1].Replace("''", "'") } else { throw "unexpected review filter: $Filter" }
                return @{ value = @($script:IdTenant.Reviews | Where-Object { $_.displayName -eq $ReviewName }) }
            }
            throw "unexpected Graph request: $Verb $Uri"
        }
    }

    It 'creates an access package in the catalog its catalog id names, and reaches Unchanged on a second run (BL-39)' {
        # The validator warns that the catalog is not declared in the document, and refuses nothing.
        $Validation = Test-OERStructure -Json $script:IdPackageDoc
        $Validation.Valid | Should -BeTrue
        @($Validation.Errors | ForEach-Object { "$($_.Severity)|$($_.Message)" }) | Should -Be @(
            "Warning|Catalog 'eeee5555-0000-0000-0000-000000000051' is not declared in this document. It may already exist in the tenant."
        )

        $First = @(Invoke-OERStructure -Json $script:IdPackageDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-IdRowLine -Row $First) | Should -Be @("accessPackages|AP-ById|Created|created access package AP-ById ($($script:IdNewPkgId))")
        # Created in the catalog the id names, which was read and written by that id: no catalog name lookup.
        @($script:IdTenant.Posts).Count | Should -Be 1
        $script:IdTenant.Posts[0].displayName | Should -BeExactly 'AP-ById'
        $script:IdTenant.Posts[0].catalog.id | Should -BeExactly $script:IdCatId
        $script:IdTenant.Requests | Should -Contain ("GET v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=catalog/id eq '$($script:IdCatId)'&`$expand=catalog")
        @($script:IdTenant.Requests | Where-Object { $_ -like '*/catalogs*' }) | Should -BeNullOrEmpty
        $FirstCount = $script:IdTenant.Requests.Count

        $Second = @(Invoke-OERStructure -Json $script:IdPackageDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-IdRowLine -Row $Second) | Should -Be @('accessPackages|AP-ById|Unchanged|access package properties match')
        $SecondRequests = @(Get-IdRequest -From $FirstCount)
        # The positive control: the second run found the package in the catalog by the id, and wrote nothing.
        $SecondRequests | Should -Contain ("GET v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=catalog/id eq '$($script:IdCatId)'&`$expand=catalog")
        @($SecondRequests | Where-Object { $_ -notlike 'GET *' }) | Should -BeNullOrEmpty
        @($script:IdTenant.Packages).Count | Should -Be 2
    }

    It 'fails, writing nothing, a package to be created in the catalog its id names while a package of that name is in another catalog (twin catalogs)' {
        # The catalog the id names does not hold AP-ById; a package of that name exists in another catalog --
        # the case the export's catalog id makes reachable for two catalogs that share a name.
        # New-OERAccessPackage's tenant-wide name check finds that package and returns it, read with its
        # catalog: the entry must fail with nothing written to that package or for the entry.
        $TwinId = 'aaaa1111-0000-0000-0000-000000000053'
        $OtherCatalogId = 'eeee5555-0000-0000-0000-000000000052'
        $script:IdTenant.Packages.Add(@{
                id = $TwinId; displayName = 'AP-ById'; description = $null; isHidden = $false
                catalog = @{ id = $OtherCatalogId }
            })

        $Rows = @(Invoke-OERStructure -Json $script:IdPackageDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-IdRowLine -Row $Rows) | Should -Be @(
            ("accessPackages|AP-ById|Failed|access package 'AP-ById' was not created in catalog '$($script:IdCatId)': a package of that name " +
            "already exists in another catalog ($OtherCatalogId), and New-OERAccessPackage returned it ($TwinId); nothing was written to it")
        )
        # Reached: the declared catalog was read by its id, and New-OERAccessPackage made its tenant-wide name
        # check and read the package it found with its catalog.
        $script:IdTenant.Requests | Should -Contain ("GET v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=catalog/id eq '$($script:IdCatId)'&`$expand=catalog")
        $script:IdTenant.Requests | Should -Contain "GET v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-ById'&`$select=id,displayName"
        $script:IdTenant.Requests | Should -Contain "GET v1.0/identityGovernance/entitlementManagement/accessPackages/$TwinId`?`$expand=catalog"
        # Nothing written, and nothing else read for the twin: no resource role or policy read, no catalog lookup.
        @($script:IdTenant.Posts).Count | Should -Be 0
        @($script:IdTenant.Requests | Where-Object { $_ -notlike 'GET *' }) | Should -BeNullOrEmpty
        @($script:IdTenant.Requests | Where-Object { $_ -like '*resourceRoleScopes*' -or $_ -like '*assignmentPolicies*' -or $_ -like '*/catalogs*' }) | Should -BeNullOrEmpty
        @($script:IdTenant.Packages).Count | Should -Be 2
    }

    It 'creates an access review on its access package and assignment policy ids, and on a second run matches it and reaches Unchanged (BL-142)' {
        $Validation = Test-OERStructure -Json $script:IdReviewDoc
        $Validation.Valid | Should -BeTrue
        @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' }) | Should -BeNullOrEmpty

        $First = @(Invoke-OERStructure -Json $script:IdReviewDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-IdRowLine -Row $First) | Should -Be @("accessReviews|Q3 by id|Created|created access review 'Q3 by id' (recurrence: OneTime)")
        # Created on the two ids: the package id confirmed by one existence read, the policy id taken as it
        # is, and neither looked up by name.
        @($script:IdTenant.Posts).Count | Should -Be 1
        $script:IdTenant.Posts[0].scope.query | Should -BeExactly ("/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq " +
            "'$($script:IdPkgId)' and assignmentPolicy/id eq '$($script:IdPolId)'")
        $script:IdTenant.Requests | Should -Contain ("GET v1.0/identityGovernance/entitlementManagement/accessPackages/$($script:IdPkgId)?`$select=id")
        @($script:IdTenant.Requests | Where-Object { $_ -like '*accessPackages?$filter=displayName*' -or $_ -like '*assignmentPolicies*' }) | Should -BeNullOrEmpty
        $FirstCount = $script:IdTenant.Requests.Count

        $Second = @(Invoke-OERStructure -Json $script:IdReviewDoc -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        # Matched by display name, its target check passed on the two ids (a review of another target is
        # refused, Failed), and nothing differs.
        @(ConvertTo-IdRowLine -Row $Second) | Should -Be @("accessReviews|Q3 by id|Unchanged|access review 'Q3 by id' already matches")
        $SecondRequests = @(Get-IdRequest -From $FirstCount)
        $SecondRequests | Should -Contain ('GET v1.0/identityGovernance/accessReviews/definitions?$filter=' + [uri]::EscapeDataString("displayName eq 'Q3 by id'"))
        @($SecondRequests | Where-Object { $_ -notlike 'GET *' }) | Should -BeNullOrEmpty
        @($SecondRequests | Where-Object { $_ -like '*accessPackages*' -or $_ -like '*assignmentPolicies*' }) | Should -BeNullOrEmpty
        @($script:IdTenant.Reviews).Count | Should -Be 1
    }
}

Describe 'Invoke-OERStructure applies a group principal an export writes by its object id (BL-131, Task 3c)' {
    # Get-OERInventory writes a group named as a principal in roleAssignments and directoryRoleAssignments
    # by its object id, with principalType Group, when another group in the tenant carries its name. These
    # prove such an entry applies: created for that object id, Unchanged on a second run, and the prune pass
    # keyed on the object id, so the second -Prune run removes nothing. The real engine, the real handlers
    # and the real principal resolver run (Resolve-OERStructurePrincipal returns a GUID verbatim); the
    # Microsoft Graph transport refuses every request, so the group is never looked up by name. For
    # roleAssignments the real ARM cmdlets run against a fake ARM transport that keeps what the first run
    # writes; for directoryRoleAssignments the directory role readers and writers are faked the same way.
    # No id below is version-4 shaped.
    BeforeAll {
        $script:GpEngGroup = 'eeee4444-0000-0000-0000-000000000001'
        $script:GpEngOther = 'dddd4444-0000-0000-0000-000000000009'
        $script:GpEngSignedIn = 'dddd4444-0000-0000-0000-0000000000ff'
        $script:GpEngSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:GpEngReader = "$($script:GpEngSub)/providers/Microsoft.Authorization/roleDefinitions/bbbb4444-0000-0000-0000-000000000001"
        $script:GpEngOtherRa = "$($script:GpEngSub)/providers/Microsoft.Authorization/roleAssignments/cccc4444-0000-0000-0000-000000000009"
        $script:GpEngDirRole = '44444444-0000-0000-0000-000000000001'
        # The entries as the export writes them.
        $script:GpEngRaDoc = ('{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/aaaa1111-0000-0000-0000-000000000001", ' +
            '"role": "Reader", "principal": "eeee4444-0000-0000-0000-000000000001", "principalType": "Group" } ] }')
        $script:GpEngDirDoc = ('{ "version": "1.0", "directoryRoleAssignments": [ { "role": "Reports Reader", ' +
            '"principal": "eeee4444-0000-0000-0000-000000000001", "principalType": "Group", "assignmentType": "Eligible" } ] }')
        function script:ConvertTo-GpEngRowLine {
            param([object[]]$Row)
            @($Row | ForEach-Object { '{0}|{1}|{2}' -f $_.Section, $_.Item, $_.Action })
        }
        # One eligible directory role schedule, the shape the eligibility reader returns.
        function script:New-GpEngDirRow {
            param([string]$PrincipalId, [string]$PrincipalType, [string]$ScheduleId)
            [PSCustomObject]@{
                ScheduleId = $ScheduleId; RoleDefinitionId = $script:GpEngDirRole; RoleName = 'Reports Reader'
                PrincipalId = $PrincipalId; PrincipalDisplayName = 'fixture'; PrincipalType = $PrincipalType
                DirectoryScopeId = '/'; MemberType = 'Direct'; Status = 'Provisioned'
                StartDateTime = '2026-01-01T00:00:00Z'; EndDateTime = $null; ExpirationType = 'noExpiration'; DurationDays = $null
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected Graph request: $Uri" }
    }

    It 'creates a roleAssignments entry for the group''s object id, prunes on the object id, and reaches Unchanged with nothing removed on a second run' {
        # The validator accepts the entry as the export writes it.
        $Validation = Test-OERStructure -Json $script:GpEngRaDoc
        $Validation.Valid | Should -BeTrue
        @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' }) | Should -BeNullOrEmpty

        # The tenant: at the subscription, one assignment of another principal that the document does not
        # declare. Each ARM request is logged as '<METHOD> <path>'.
        $script:GpEngArm = @{
            Log         = [System.Collections.Generic.List[string]]::new()
            Puts        = [System.Collections.Generic.List[object]]::new()
            Assignments = [System.Collections.Generic.List[object]]::new()
        }
        $script:GpEngArm.Assignments.Add([PSCustomObject]@{ id = $script:GpEngOtherRa; name = 'cccc4444-0000-0000-0000-000000000009'
                properties = [PSCustomObject]@{ scope = $script:GpEngSub; principalId = $script:GpEngOther; principalType = 'User'; roleDefinitionId = $script:GpEngReader } })
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest {
            $RequestMethod = if ($Method) { $Method } else { 'GET' }
            $script:GpEngArm.Log.Add("$RequestMethod $Path")
            $AssignmentsPath = "$($script:GpEngSub)/providers/Microsoft.Authorization/roleAssignments"
            if ($RequestMethod -eq 'GET' -and $Path -eq "$($script:GpEngSub)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20%27Reader%27") {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = $script:GpEngReader }) }
            }
            if ($RequestMethod -eq 'GET' -and $Path -eq "$AssignmentsPath`?api-version=2022-04-01&`$filter=atScope()") {
                return [PSCustomObject]@{ value = @($script:GpEngArm.Assignments) }
            }
            if ($RequestMethod -eq 'PUT' -and $Path -like "$AssignmentsPath/*?api-version=2022-04-01") {
                $script:GpEngArm.Puts.Add($Body)
                $Created = [PSCustomObject]@{ id = $Path.Split('?')[0]; name = ($Path.Split('?')[0] -split '/')[-1]
                    properties = [PSCustomObject]@{ scope = $script:GpEngSub; principalId = $Body.properties.principalId
                        principalType = $Body.properties.principalType; roleDefinitionId = $Body.properties.roleDefinitionId } }
                $script:GpEngArm.Assignments.Add($Created)
                return $Created
            }
            if ($RequestMethod -eq 'DELETE') {
                $Gone = @($script:GpEngArm.Assignments | Where-Object { "$($_.id)?api-version=2022-04-01" -eq $Path })
                if ($Gone.Count -ne 1) { throw "unexpected ARM delete: $Path" }
                $null = $script:GpEngArm.Assignments.Remove($Gone[0])
                return $Gone[0]
            }
            throw "unexpected ARM call: $RequestMethod $Path"
        }

        $First = @(Invoke-OERStructure -Json $script:GpEngRaDoc -Include RoleAssignments -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-GpEngRowLine -Row $First) | Should -Be @(
            "roleAssignments|Reader -> $($script:GpEngGroup) @ $($script:GpEngSub)|Created"
            "roleAssignments|bbbb4444-0000-0000-0000-000000000001 -> $($script:GpEngOther) @ $($script:GpEngSub)|Removed"
        )
        # Created for the group's object id, as a group: the id the entry names, never looked up.
        $script:GpEngArm.Puts.Count | Should -Be 1
        $script:GpEngArm.Puts[0].properties.principalId | Should -BeExactly $script:GpEngGroup
        $script:GpEngArm.Puts[0].properties.principalType | Should -BeExactly 'Group'
        $script:GpEngArm.Puts[0].properties.roleDefinitionId | Should -BeExactly $script:GpEngReader
        @($script:GpEngArm.Log | Where-Object { $_ -like 'DELETE *' }) | Should -Be @("DELETE $($script:GpEngOtherRa)?api-version=2022-04-01")
        $FirstCount = $script:GpEngArm.Log.Count

        $Second = @(Invoke-OERStructure -Json $script:GpEngRaDoc -Include RoleAssignments -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-GpEngRowLine -Row $Second) | Should -Be @("roleAssignments|Reader -> $($script:GpEngGroup) @ $($script:GpEngSub)|Unchanged")
        # The positive control: the second run read the scope, and wrote and removed nothing -- the prune
        # pass keyed the created assignment on the group's object id and found it declared.
        $SecondRequests = @($script:GpEngArm.Log | Select-Object -Skip $FirstCount)
        $SecondRequests | Should -Contain "GET $($script:GpEngSub)/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
        @($SecondRequests | Where-Object { $_ -notlike 'GET *' }) | Should -BeNullOrEmpty
        @($script:GpEngArm.Assignments).Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'creates a directoryRoleAssignments entry for the group''s object id, prunes on the object id, and reaches Unchanged with nothing removed on a second run' {
        $Validation = Test-OERStructure -Json $script:GpEngDirDoc
        $Validation.Valid | Should -BeTrue
        @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' }) | Should -BeNullOrEmpty

        # The tenant: one eligible assignment of the role for another principal, which the document does not
        # declare. The readers filter it by role and principal as the real readers do.
        $script:GpEngDir = @{
            Live    = [System.Collections.Generic.List[object]]::new()
            Created = [System.Collections.Generic.List[object]]::new()
            Removed = [System.Collections.Generic.List[string]]::new()
        }
        $script:GpEngDir.Live.Add((New-GpEngDirRow -PrincipalId $script:GpEngOther -PrincipalType 'User' -ScheduleId 'schedule-9'))
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleDefinitionId {
            if ($Role -eq 'Reports Reader' -or $Role -eq $script:GpEngDirRole) { $script:GpEngDirRole }
        }
        Mock -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment {
            @($script:GpEngDir.Live | Where-Object {
                    (-not $Role -or $_.RoleDefinitionId -eq $Role) -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId)
                })
        }
        Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment { @() }
        Mock -ModuleName $script:moduleName New-OEREligibleDirectoryRoleAssignment {
            $script:GpEngDir.Created.Add([PSCustomObject]@{ Role = $Role; PrincipalId = $PrincipalId; Action = $Action; Permanent = [bool]$Permanent })
            $script:GpEngDir.Live.Add((New-GpEngDirRow -PrincipalId $PrincipalId -PrincipalType 'Group' -ScheduleId 'schedule-1'))
        }
        Mock -ModuleName $script:moduleName Remove-OEREligibleDirectoryRoleAssignment {
            $script:GpEngDir.Removed.Add("$Role|$PrincipalId")
            foreach ($Gone in @($script:GpEngDir.Live | Where-Object { $_.RoleDefinitionId -eq $Role -and $_.PrincipalId -eq $PrincipalId })) {
                $null = $script:GpEngDir.Live.Remove($Gone)
            }
        }
        Mock -ModuleName $script:moduleName Remove-OERActiveDirectoryRoleAssignment { throw 'unexpected removal of an active assignment' }
        Mock -ModuleName $script:moduleName Get-OERSignedInObjectId { $script:GpEngSignedIn }
        Mock -ModuleName $script:moduleName Get-OERMemberGroupId { @() }

        $First = @(Invoke-OERStructure -Json $script:GpEngDirDoc -Include DirectoryRoleAssignments -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        # The section-wide prune pass runs first, then the entry.
        @(ConvertTo-GpEngRowLine -Row $First) | Should -Be @(
            "directoryRoleAssignments|Reports Reader -> $($script:GpEngOther) (Eligible)|Removed"
            "directoryRoleAssignments|Reports Reader -> $($script:GpEngGroup) (Eligible)|Created"
        )
        # Created for the group's object id, permanent as declared: the id the entry names, never looked up.
        @($script:GpEngDir.Created | ForEach-Object { "$($_.Role)|$($_.PrincipalId)|$($_.Action)|$($_.Permanent)" }) |
            Should -Be @("$($script:GpEngDirRole)|$($script:GpEngGroup)|adminAssign|True")
        @($script:GpEngDir.Removed) | Should -Be @("$($script:GpEngDirRole)|$($script:GpEngOther)")

        $Second = @(Invoke-OERStructure -Json $script:GpEngDirDoc -Include DirectoryRoleAssignments -Prune -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        @(ConvertTo-GpEngRowLine -Row $Second) | Should -Be @("directoryRoleAssignments|Reports Reader -> $($script:GpEngGroup) (Eligible)|Unchanged")
        # The positive control: the prune pass read the pair once in each run -- in the second, with the
        # group's own assignment live -- and kept it, since it keyed it on the group's object id.
        Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 2 -Exactly -ParameterFilter { $Role -eq $script:GpEngDirRole -and -not $PrincipalId }
        @($script:GpEngDir.Created).Count | Should -Be 1
        @($script:GpEngDir.Removed).Count | Should -Be 1
        @($script:GpEngDir.Live | ForEach-Object { $_.PrincipalId }) | Should -Be @($script:GpEngGroup)
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }
}
