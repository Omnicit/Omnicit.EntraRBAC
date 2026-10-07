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
        $Withheld[0].Detail | Should -BeExactly ("prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'grp-new', which this run created into this unit, " +
            'and the run that creates a membership does not remove it (our own guard, not a Graph rejection). ' +
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
        $Sections = @($Schema.properties.PSObject.Properties.Name | Where-Object { $_ -notin @('version', 'tenantAlias') })
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
