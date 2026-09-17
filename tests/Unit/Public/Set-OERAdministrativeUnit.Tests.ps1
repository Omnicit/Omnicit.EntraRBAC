BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERAdministrativeUnit' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'patches the description and returns the refreshed AU' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-1'; displayName = 'au_hr'; description = 'new' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = Set-OERAdministrativeUnit -Id 'au-1' -Description 'new'
        $Result.Description | Should -Be 'new'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.description -eq 'new'
        }
    }

    It 'renames the AU via -NewDisplayName' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-1'; displayName = 'au_hr_renamed' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = Set-OERAdministrativeUnit -Id 'au-1' -NewDisplayName 'au_hr_renamed'
        $Result.DisplayName | Should -Be 'au_hr_renamed'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.displayName -eq 'au_hr_renamed'
        }
    }

    It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding for -AdministrativeUnit (a capability, not a break)' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding. After the collapse there is exactly one
        # parameter set, so -AdministrativeUnit (position 0) now binds positionally. 'au-1' is not a
        # canonical GUID, so dispatch correctly routes it to -DisplayName, not -Id (proven separately
        # by the "identity parameter collapse" Context above) -- the point here is only that the
        # positional value reaches Resolve-OERAdministrativeUnitId AT ALL, and then the resolved id
        # reaches the PATCH URI.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-1'; displayName = 'au_hr'; description = 'positional' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Set-OERAdministrativeUnit 'au-1' -Description 'positional' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
            $DisplayName -eq 'au-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.description -eq 'positional'
        }
    }

    It 'binds -DisplayName (the identity alias) together with -NewDisplayName in one call without ParameterNameConflictsWithAlias' {
        # -DisplayName is now ONLY an alias of the unified -AdministrativeUnit parameter, never a
        # separately declared parameter, so it cannot collide with -NewDisplayName (the rename target)
        # even though both are bound in the same call.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-2' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-2'; displayName = 'au_hr_renamed' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        { Set-OERAdministrativeUnit -DisplayName 'au_hr' -NewDisplayName 'au_hr_renamed' -Confirm:$false -ErrorAction Stop } |
            Should -Not -Throw
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
            $DisplayName -eq 'au_hr'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.displayName -eq 'au_hr_renamed'
        }
    }

    It 'errors NothingToUpdate when no updatable property is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAdministrativeUnit -Id 'au-1' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        # Cmdlet-qualified: a bare-code match passes even with the WriteError deleted, because the
        # engine re-records a thrown record into -ErrorVariable at every call boundary it crosses.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERAdministrativeUnit' }).Count | Should -Be 1
    }

    It 'errors AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAdministrativeUnit -DisplayName 'nope' -Description 'x' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Set-OERAdministrativeUnit -DisplayName 'au1' -Description 'x' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'does not PATCH under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAdministrativeUnit -Id 'au-1' -Description 'x' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'accepts -DisplayName from the pipeline by property name (name-only object | Set-OERAdministrativeUnit)' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-2' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-2'; displayName = 'au_hr'; description = 'by-name' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        [pscustomobject]@{ DisplayName = 'au_hr' } | Set-OERAdministrativeUnit -Description 'by-name' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -ParameterFilter {
            $DisplayName -eq 'au_hr'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.description -eq 'by-name'
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '44444444-4444-4444-4444-444444444444' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'au_hr' }
            }
            Set-OERAdministrativeUnit -AdministrativeUnit '44444444-4444-4444-4444-444444444444' -Description 'x' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq '44444444-4444-4444-4444-444444444444' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '44444444-4444-4444-4444-444444444444' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'au_hr' }
            }
            Set-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -Description 'x' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '55555555-5555-5555-5555-555555555555' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '55555555-5555-5555-5555-555555555555'; displayName = 'au_hr' }
            }
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = 'au_hr'; Description = 'x'; Confirm = $false }
                Set-OERAdministrativeUnit @Splat | Out-Null
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -eq 'v1.0/directory/administrativeUnits/55555555-5555-5555-5555-555555555555'
            }
        }

        It 'round-trips a real ConvertTo-OERAdministrativeUnit object: the AU id (not the display name) reaches the PATCH URI' {
            # Resolve-OERAdministrativeUnitId is NOT mocked here: the piped object binds via the Id
            # alias (Id precedes DisplayName in the alias declaration order), so the value is already a
            # canonical GUID, Test-OERGuid dispatches to -Id, and Resolve-OERAdministrativeUnitId's own
            # real implementation returns it verbatim with no Graph call at all.
            #
            # Built through the REAL private converter (fix-round M5), not a hand-rolled pscustomobject:
            # a hand-rolled stand-in is property-equivalent today but would not notice a future change
            # to ConvertTo-OERAdministrativeUnit's own output shape.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '66666666-6666-6666-6666-666666666666'; displayName = 'au_hr'; description = 'x' }
            }
            $Au = InModuleScope $script:moduleName {
                ConvertTo-OERAdministrativeUnit -InputObject @{ id = '66666666-6666-6666-6666-666666666666'; displayName = 'au_hr' }
            }
            $Au | Set-OERAdministrativeUnit -Description 'x' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -eq 'v1.0/directory/administrativeUnits/66666666-6666-6666-6666-666666666666'
            }
        }
    }

    Context 'MembershipType' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'a1111111-0000-0000-0000-000000000001' }
        }

        It 'sends membershipType and membershipRule in a SINGLE PATCH when converting to Dynamic' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe' }
            }
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' `
                -MembershipType 'Dynamic' -MembershipRule '(user.department -eq "IT")' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Body.membershipType -eq 'Dynamic' -and
                $Body.membershipRule -eq '(user.department -eq "IT")'
            }
        }

        It 'errors with MembershipRuleRequired when converting to Dynamic with no rule anywhere' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe'; membershipType = 'Assigned' }
            }
            { Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' `
                -MembershipType 'Dynamic' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ErrorId 'MembershipRuleRequired,Set-OERAdministrativeUnit'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'PATCH'
            }
        }

        It 'allows converting to Dynamic with no -MembershipRule when the live unit already has one' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe'; membershipRule = '(user.country -eq "SE")' }
            }
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -MembershipType 'Dynamic' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Body.membershipType -eq 'Dynamic'
            }
        }

        It 'never sends membershipRule when converting to Assigned' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe' }
            }
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -MembershipType 'Assigned' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Body.membershipType -eq 'Assigned' -and
                -not $Body.ContainsKey('membershipRule')
            }
        }

        It 'warns that the existing membership can change when -MembershipType is bound' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe' }
            }
            $Warnings = @()
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' `
                -MembershipType 'Dynamic' -MembershipRule '(user.department -eq "IT")' `
                -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
            $Warnings.Count | Should -BeGreaterThan 0
            "$($Warnings[0])" | Should -BeLike '*membership*'
        }

        It 'does not warn on an unrelated edit that leaves the membership type alone' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe' }
            }
            $Warnings = @()
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -Description 'just a description' `
                -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
            $Warnings.Count | Should -Be 0
        }

        It 'names -MembershipType in the NothingToUpdate error' {
            $Err = $null
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue
            "$($Err[0].Exception.Message)" | Should -BeLike '*-MembershipType*'
        }
    }

    Context 'Visibility' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'a1111111-0000-0000-0000-000000000001' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'a1111111-0000-0000-0000-000000000001'; displayName = 'au_probe' }
            }
        }

        It 'sends visibility as a JSON null for -Visibility Public' {
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -Visibility 'Public' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Body.ContainsKey('visibility') -and $null -eq $Body.visibility
            }
        }

        It 'sends the literal string for -Visibility HiddenMembership' {
            Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' -Visibility 'HiddenMembership' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Body.visibility -eq 'HiddenMembership'
            }
        }
    }
}

Describe 'Set-OERAdministrativeUnit bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The unit resolver is mocked to SUCCEED and -MembershipType is not supplied, so the
        # Dynamic pre-check read is never reached and the thrown transport drives the PATCH catch
        # rather than the resolver catch or that pre-check catch (both of which also scrub).
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Set-OERAdministrativeUnit -Id 'au-1' -Description 'new' `
            -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
