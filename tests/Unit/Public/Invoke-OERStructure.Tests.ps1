BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
