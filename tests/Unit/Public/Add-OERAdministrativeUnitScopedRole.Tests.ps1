BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Add-OERAdministrativeUnitScopedRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'creates a scoped role assignment from a role name' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'srm-1'; roleId = 'role-1'; administrativeUnitId = 'au-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Jane' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' -PrincipalId '11111111-1111-1111-1111-111111111111'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole'
        $Result.RoleName | Should -Be 'User Administrator'
        $Result.RoleId | Should -Be 'role-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers' -and
            $Body.roleId -eq 'role-1' -and $Body.roleMemberInfo.id -eq '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding for -AdministrativeUnit and -RoleName (a capability, not a break)' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding. After the collapse there is exactly one
        # parameter set, so -AdministrativeUnit (position 0) and -RoleName (position 1) now bind
        # positionally. -RoleId is deliberately NOT also supplied positionally here: that would bind
        # both -RoleName and -RoleId in the same call and trip the AmbiguousRole guard, which is a
        # different, already-covered behavior.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAdministrativeUnitScopedRole 'au-1' 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERDirectoryRoleId -Times 1 -Exactly -ParameterFilter {
            $RoleName -eq 'User Administrator'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers'
        }
    }

    It 'errors when neither -RoleName nor -RoleId is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitScopedRole -Id 'au-1' -PrincipalId 'user-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'RoleNotSpecified'
    }

    It 'errors AmbiguousRole when BOTH -RoleName and -RoleId are bound, and makes no POST' {
        # -RoleId always wins inside Resolve-OERDirectoryRoleId's own dispatch, so accepting both
        # silently would resolve one role while potentially echoing the OTHER one's name on the
        # output object (the bug fix 5c #1 below guards the belt-and-braces case; this guard removes
        # the ambiguous input entirely).
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' -RoleId 'role-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousRole,Add-OERAdministrativeUnitScopedRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'POST'
        }
    }

    It 'emits the RoleName resolved from -RoleId (via Get-OERDirectoryRoleNameMap) when only -RoleId is supplied' {
        # NOTE on mutation coverage: this does NOT discriminate the 5c #1 EffectiveRoleName fix from
        # the pre-fix code -- with -RoleName unbound, `if ($RoleName) {...} else {map}` and
        # `if ($RoleId) {map} else {...}` both take the map branch. Verified empirically: reverting
        # the fix to `if ($RoleName) { $RoleName } else { map }` leaves this It GREEN. The fix is
        # genuinely unreachable through the public cmdlet now that the AmbiguousRole guard above
        # rejects "both -RoleName and -RoleId bound" outright -- the one input shape where the two
        # implementations would differ can no longer reach this line. Shipped anyway per the brief
        # ("ship this regardless") as defense in depth; kept as a plain behavioral assertion that
        # -RoleId alone resolves the correct name, not as a guard for the fix itself.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Get-OERDirectoryRoleNameMap {
            @{ 'role-guid-1' = 'User Administrator' }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'srm-1'; roleId = 'role-guid-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-guid-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        $Result.RoleName | Should -Be 'User Administrator'
    }

    It 'errors AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitScopedRole -DisplayName 'nope' -RoleId 'role-1' -PrincipalId 'user-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the unit lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Add-OERAdministrativeUnitScopedRole -DisplayName 'au1' -RoleId 'role-1' -PrincipalId 'user-1' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'errors RoleNotFound when the resolver genuinely returns no match ($null)' {
        # Resolve-OERDirectoryRoleId's own contract returns $null for a genuine no-match (mirrors
        # Resolve-OERAdministrativeUnitId). This is the normal, real-behavior shape.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'Bad' -PrincipalId 'user-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err[-1].FullyQualifiedErrorId | Should -Match 'RoleNotFound'
    }

    It 'still errors RoleNotFound (not DirectoryRoleResolveFailed) if the resolver throws with its distinctive not-found message' {
        # Defensive backstop: even though the resolver's contract is null-on-no-match, a throw
        # shaped exactly like its historical not-found message must still be classified as
        # RoleNotFound, not misreported as a resolve failure for a role that simply does not exist.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { throw "No directory role found with display name 'Bad'." }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'Bad' -PrincipalId 'user-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err[-1].FullyQualifiedErrorId | Should -Match 'RoleNotFound'
        $err[-1].FullyQualifiedErrorId | Should -Not -Match 'DirectoryRoleResolveFailed'
    }

    It 'reports DirectoryRoleResolveFailed when the role lookup itself fails' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-id-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { throw 'TooManyRequests' }
        Add-OERAdministrativeUnitScopedRole -DisplayName 'au1' -RoleName 'User Administrator' `
            -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'DirectoryRoleResolveFailed'
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'bbbbbbbb-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
            }
            Add-OERAdministrativeUnitScopedRole -AdministrativeUnit 'bbbbbbbb-1111-1111-1111-111111111111' `
                -RoleId 'role-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'bbbbbbbb-1111-1111-1111-111111111111' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
            }
            Add-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' `
                -RoleId 'role-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
            }
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{
                    $Spelling   = 'au_hr'
                    RoleId      = 'role-1'
                    PrincipalId = '11111111-1111-1111-1111-111111111111'
                    Confirm     = $false
                }
                Add-OERAdministrativeUnitScopedRole @Splat | Out-Null
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers'
            }
        }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleId { 'rrrr0000-0000-0000-0000-00000000000c' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'srm1'; roleId = 'rrrr0000-0000-0000-0000-00000000000c'; roleMemberInfo = @{ id = 'bbbb0000-0000-0000-0000-000000000002' } }
            }
        }

        It 'resolves -User into roleMemberInfo.id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Add-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.roleMemberInfo.id -eq 'bbbb0000-0000-0000-0000-000000000002'
            }
        }

        It 'resolves -Group into roleMemberInfo.id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            Add-OERAdministrativeUnitScopedRole -DisplayName 'au_hr' -RoleName 'User Administrator' `
                -Group 'Sales Team' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body.roleMemberInfo.id -eq 'cccc0000-0000-0000-0000-000000000003'
            }
        }

        It 'still accepts a raw GUID -PrincipalId with no principal lookup' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            Add-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body.roleMemberInfo.id -eq 'aaaa0000-0000-0000-0000-000000000001'
            }
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'rejects a UPN passed to -PrincipalId with InvalidPrincipalId and does not call Graph' {
            $Err = $null
            Add-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -PrincipalId 'anna.berg@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            $Err[0].Exception.Message | Should -BeLike '*-User or -Group*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'reports NoPrincipal when no principal is supplied' {
            $Err = $null
            Add-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }

        It 'reports AmbiguousPrincipal when -User and -Group are both supplied' {
            $Err = $null
            Add-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -User 'anna@contoso.com' -Group 'Sales Team' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
        }
    }
}

Describe 'Add-OERAdministrativeUnitScopedRole verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
        }
    }

    It 'reports the resolved administrative unit, role and principal under -Verbose' {
        $Verbose = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Add-OERAdministrativeUnitScopedRole\] Resolved administrative unit to 'au-1'."
        $Text | Should -Match "\[Add-OERAdministrativeUnitScopedRole\] Resolved role 'User Administrator' to 'role-1'."
        $Text | Should -Match "\[Add-OERAdministrativeUnitScopedRole\] Resolved principal to '11111111-1111-1111-1111-111111111111'."
    }

    It 'does not report a resolved role line when -RoleId is supplied directly' {
        $Verbose = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Not -Match 'Resolved role '
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}

Describe 'Add-OERAdministrativeUnitScopedRole -Role alias' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'exposes Role as an alias of RoleName' {
        (Get-Command Add-OERAdministrativeUnitScopedRole).Parameters['RoleName'].Aliases |
            Should -Contain 'Role'
    }

    It 'does not declare its own Role parameter (which would collide with the alias)' {
        (Get-Command Add-OERAdministrativeUnitScopedRole).Parameters.Keys | Should -Not -Contain 'Role'
    }

    It 'binds -Role to RoleName and resolves the same directory role as -RoleName' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalOrId {
            [PSCustomObject]@{ PrincipalId = '11111111-1111-1111-1111-111111111111'; ErrorId = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }
        }

        $Result = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -Role 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false

        Should -Invoke Resolve-OERDirectoryRoleId -ModuleName Omnicit.EntraRBAC -Times 1 -Exactly `
            -ParameterFilter { $RoleName -eq 'User Administrator' }
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'does not bind RoleName from the pipeline by property name' {
        # The alias must not turn an incoming object's Role/RoleName property into a silent binding.
        (Get-Command Add-OERAdministrativeUnitScopedRole).Parameters['RoleName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName } |
            Should -BeNullOrEmpty
    }
}

Describe 'RoleName argument completer registration' {
    It 'completes -RoleName on Add-OERAdministrativeUnitScopedRole with the curated directory roles' {
        $Line = 'Add-OERAdministrativeUnitScopedRole -RoleName '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Texts = $Completion.CompletionMatches.CompletionText
        $Texts | Should -Contain "'User Administrator'"
        $Texts | Should -Contain "'Groups Administrator'"
        $Texts | Should -Not -Contain 'Contributor'
    }

    It 'completes the -Role alias spelling too' {
        $Line = 'Add-OERAdministrativeUnitScopedRole -Role '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'User Administrator'"
    }

    It 'filters -RoleName by the typed prefix' {
        $Line = 'Add-OERAdministrativeUnitScopedRole -RoleName Groups'
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'Groups Administrator'"
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain "'User Administrator'"
    }
}

Describe 'Add-OERAdministrativeUnitScopedRole bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # Both resolvers are mocked to SUCCEED and -PrincipalId is a canonical GUID, so the thrown
        # transport drives the scopedRoleMembers POST catch and not one of the three earlier
        # catches (unit resolve, directory-role resolve, principal resolve) that also scrub.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Add-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
