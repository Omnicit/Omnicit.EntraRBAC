BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAdministrativeUnitScopedRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'deletes by explicit ScopedRoleMembershipId without listing' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -ScopedRoleMembershipId 'srm-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/srm-1'
        }
    }

    It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding for -AdministrativeUnit and -ScopedRoleMembershipId (a capability, not a break)' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding. After the collapse there is exactly one
        # parameter set, so -AdministrativeUnit (position 0) and -ScopedRoleMembershipId (position 1)
        # now bind positionally.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnitScopedRole 'au-1' 'srm-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/srm-1'
        }
    }

    It 'resolves the membership from RoleId + PrincipalId then deletes' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'srm-9'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/srm-9'
        }
    }

    It 'errors AmbiguousRole when BOTH -RoleName and -RoleId are bound, and makes no DELETE' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' -RoleId 'role-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousRole,Remove-OERAdministrativeUnitScopedRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'errors AmbiguousRole (not silent-delete-by-ScopedRoleMembershipId) when an ordinary pipe of role/membership objects is combined with an explicit -RoleName' {
        # Documented behavior change (fix-round M1): -RoleId binds from the pipeline by property
        # name, so a piped scoped-role membership carries its own RoleId even though only -RoleName
        # was supplied explicitly. The AmbiguousRole guard runs BEFORE the -ScopedRoleMembershipId
        # precedence handling, so this now fails loudly for every item instead of the pre-guard
        # behavior (silently ignoring -RoleName and deleting by the piped ScopedRoleMembershipId).
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Members = InModuleScope $script:moduleName {
            1, 2 | ForEach-Object {
                ConvertTo-OERScopedRoleMember -InputObject @{
                    id = "srm-$_"; administrativeUnitId = 'au-1'; roleId = "role-$_"
                    roleMemberInfo = @{ id = "principal-$_" }
                } -RoleName 'User Administrator'
            }
        }
        $Err = $null
        $Members | Remove-OERAdministrativeUnitScopedRole -RoleName 'User Administrator' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRole,Remove-OERAdministrativeUnitScopedRole' }).Count | Should -Be 2
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'errors when insufficient identification is supplied' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'ScopedRoleNotSpecified'
    }

    It 'reports AdministrativeUnitResolveFailed when the unit lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Remove-OERAdministrativeUnitScopedRole -DisplayName 'au1' -ScopedRoleMembershipId 'srm-1' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'errors RoleNotFound when the resolver genuinely returns no match ($null)' {
        # Resolve-OERDirectoryRoleId's own contract returns $null for a genuine no-match (mirrors
        # Resolve-OERAdministrativeUnitId). This is the normal, real-behavior shape.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { $null }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'Bad' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'RoleNotFound'
    }

    It 'still errors RoleNotFound (not DirectoryRoleResolveFailed) if the resolver throws with its distinctive not-found message' {
        # Defensive backstop: even though the resolver's contract is null-on-no-match, a throw
        # shaped exactly like its historical not-found message must still be classified as
        # RoleNotFound, not misreported as a resolve failure for a role that simply does not exist.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { throw "No directory role found with display name 'Bad'." }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'Bad' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'RoleNotFound'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'DirectoryRoleResolveFailed'
    }

    It 'reports DirectoryRoleResolveFailed when the role lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { throw 'TooManyRequests' }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'DirectoryRoleResolveFailed'
    }

    It 'errors ScopedRoleNotFound when no membership matches' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'ScopedRoleNotFound'
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -ScopedRoleMembershipId 'srm-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'round-trips from a piped Get/Add output using ScopedRoleMembershipId (direct-by-id path, no list GET)' {
        # AdministrativeUnitId must be a real GUID: dispatch is on Test-OERGuid, and the resolver mock
        # below only echoes back whichever of -Id/-DisplayName it actually received.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $Id }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        $PipedObject = [pscustomobject]@{
            ScopedRoleMembershipId = 'SRM'
            AdministrativeUnitId   = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            RoleId                 = 'ROLE'
            PrincipalId            = 'PRIN'
            RoleName               = 'User Administrator'
        }
        $PipedObject | Remove-OERAdministrativeUnitScopedRole -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/scopedRoleMembers/SRM'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Method -ne 'DELETE'
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'dddddddd-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit 'dddddddd-1111-1111-1111-111111111111' `
                -ScopedRoleMembershipId 'srm-1' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'dddddddd-1111-1111-1111-111111111111' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' `
                -ScopedRoleMembershipId 'srm-1' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = 'au_hr'; ScopedRoleMembershipId = 'srm-1'; Confirm = $false }
                Remove-OERAdministrativeUnitScopedRole @Splat
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/srm-1'
            }
        }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleId { 'rrrr0000-0000-0000-0000-00000000000c' }
        }

        It 'finds the membership for a -User given by UPN' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'srm1'; roleId = 'rrrr0000-0000-0000-0000-00000000000c'; roleMemberInfo = @{ id = 'bbbb0000-0000-0000-0000-000000000002' } }) }
            } -ParameterFilter { $Method -ne 'DELETE' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/auau0000-0000-0000-0000-00000000000b/scopedRoleMembers/srm1'
            }
        }

        It 'rejects a UPN passed to -PrincipalId with InvalidPrincipalId' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            $Err = $null
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -PrincipalId 'anna.berg@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
        }

        It 'still removes by -ScopedRoleMembershipId with no principal supplied' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -ScopedRoleMembershipId 'srm1' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'piped ambiguity guard' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
        }

        It 'errors AmbiguousPrincipal and makes no Graph call when -User is supplied alongside piped input' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Err = $null
            [pscustomobject]@{
                AdministrativeUnitId   = 'auau0000-0000-0000-0000-00000000000b'
                ScopedRoleMembershipId = 'srm1'
            } | Remove-OERAdministrativeUnitScopedRole -User 'anna@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'does not fire the piped-ambiguity guard for a normal round-trip with no friendly parameter' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            [pscustomobject]@{
                AdministrativeUnitId   = 'auau0000-0000-0000-0000-00000000000b'
                ScopedRoleMembershipId = 'srm1'
            } | Remove-OERAdministrativeUnitScopedRole -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'explicit -PrincipalId pipe guard (closes prom-au-scopedrole-principalid-inert-on-pipe)' {
        # Adding 'PrincipalId' to the ContainsKey guard list above would BREAK every ordinary pipe,
        # because pipeline-bound parameters populate $PSBoundParameters too. These tests use REAL
        # ConvertTo-OERScopedRoleMember objects (not raw pscustomobjects) so the pipeline binding is
        # genuine, and the first It is the regression guard that catches the naive ContainsKey fix:
        # it fails the moment -PrincipalId is added to that list, even with no explicit -PrincipalId
        # ever supplied on the command line.
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
        }

        It 'an ordinary pipe with NO explicit -PrincipalId succeeds with zero errors and issues one DELETE per item' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Members = InModuleScope Omnicit.EntraRBAC {
                1, 2 | ForEach-Object {
                    ConvertTo-OERScopedRoleMember -InputObject @{
                        id = "srm-$_"; administrativeUnitId = 'auau0000-0000-0000-0000-00000000000b'
                        roleId = 'role-1'; roleMemberInfo = @{ id = "principal-$_" }
                    } -RoleName 'User Administrator'
                }
            }
            $Err = $null
            $Members | Remove-OERAdministrativeUnitScopedRole -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'an explicit -PrincipalId that differs from the piped items raises AmbiguousPrincipal for each and issues no DELETE' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Members = InModuleScope Omnicit.EntraRBAC {
                1, 2 | ForEach-Object {
                    ConvertTo-OERScopedRoleMember -InputObject @{
                        id = "srm-$_"; administrativeUnitId = 'auau0000-0000-0000-0000-00000000000b'
                        roleId = 'role-1'; roleMemberInfo = @{ id = "principal-$_" }
                    } -RoleName 'User Administrator'
                }
            }
            $Err = $null
            $Members | Remove-OERAdministrativeUnitScopedRole -PrincipalId 'zzzzzzzz-0000-0000-0000-000000000000' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousPrincipal,Remove-OERAdministrativeUnitScopedRole' }).Count | Should -Be 2
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'an explicit -PrincipalId that MATCHES the (single) piped item is not ambiguous and still deletes' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Member = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERScopedRoleMember -InputObject @{
                    id = 'srm-1'; administrativeUnitId = 'auau0000-0000-0000-0000-00000000000b'
                    roleId = 'role-1'; roleMemberInfo = @{ id = 'principal-1' }
                } -RoleName 'User Administrator'
            }
            $Err = $null
            $Member | Remove-OERAdministrativeUnitScopedRole -PrincipalId 'principal-1' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'a non-piped explicit -PrincipalId (no pipe at all) is unaffected' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'srm-1'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
            } -ParameterFilter { $Method -ne 'DELETE' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleId { 'role-1' }
            $Err = $null
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -RoleName 'User Administrator' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }
    }

    Context 'destructive guard' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
        }

        It 'declares ConfirmImpact High' {
            $Attr = (Get-Command Remove-OERAdministrativeUnitScopedRole).ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $Attr.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::High)
        }

        It 'warns BEFORE the DELETE fires' {
            # The warning AND the mutation record into the SAME list. A list that only ever records
            # the DELETE would stay green with the Write-Warning moved below it, which is exactly the
            # defect this guard exists to catch. The filter names the destructive warning's own
            # wording -- 'scoped role' also matches this file's -ScopedRoleMembershipId precedence
            # warning, so it could not tell the two apart.
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Write-Warning -ParameterFilter { $Message -match 'revokes the principal' } -MockWith { $Order.Add('warn') }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'DELETE' } -MockWith { $Order.Add('delete') }
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -ScopedRoleMembershipId 'srm-guard' -Confirm:$false `
                -WarningAction SilentlyContinue
            $Order -join ',' | Should -Be 'warn,delete'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Warning -Times 1 -ParameterFilter { $Message -match 'revokes the principal' }
        }

        It 'does not DELETE under -WhatIf (destructive guard)' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'DELETE' } -MockWith { }
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -ScopedRoleMembershipId 'srm-guard' -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'does not warn under -WhatIf (the warning belongs inside the ShouldProcess block)' {
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -ScopedRoleMembershipId 'srm-guard' -WhatIf `
                -WarningVariable Warn -WarningAction SilentlyContinue
            @($Warn | Where-Object { $_.Message -match 'revokes the principal' }).Count | Should -Be 0
        }
    }

    Context 'ScopedRoleMembershipId precedence warning (non-piped)' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
        }

        It 'warns that -User is ignored and still removes the named membership when -ScopedRoleMembershipId and -User are both supplied directly' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Warnings = $null
            Remove-OERAdministrativeUnitScopedRole -Id 'auau0000-0000-0000-0000-00000000000b' `
                -ScopedRoleMembershipId 'srm1' -User 'anna@contoso.com' -Confirm:$false `
                -WarningVariable Warnings -WarningAction SilentlyContinue
            ($Warnings | ForEach-Object { $_.Message }) -join ' ' | Should -BeLike '*-ScopedRoleMembershipId*'
            ($Warnings | ForEach-Object { $_.Message }) -join ' ' | Should -BeLike '*-User*'
            ($Warnings | ForEach-Object { $_.Message }) -join ' ' | Should -BeLike "*'srm1'*"
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/directory/administrativeUnits/auau0000-0000-0000-0000-00000000000b/scopedRoleMembers/srm1'
            }
        }
    }

    Context 'scopedRoleMembers pagination' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleId { 'role-1' }
        }

        It 'finds a scoped role membership that only exists on the second page' {
            # The un-paged mock returns only page 1 (p1), so today (without -All) the second-page
            # match (p2) is never seen and the cmdlet reports ScopedRoleNotFound. The -All mock
            # returns both pages aggregated, as Invoke-OERGraphRequest -All actually behaves.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -like '*scopedRoleMembers*' -and $All
            } -MockWith {
                @{ value = @(
                    @{ id = 'page1-a'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } },
                    @{ id = 'page2-target'; roleId = 'role-1'; roleMemberInfo = @{ id = '22222222-2222-2222-2222-222222222222' } }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -like '*scopedRoleMembers*' -and -not $All
            } -MockWith {
                @{ value = @(@{ id = 'page1-a'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'DELETE' } -MockWith { }

            Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' `
                -PrincipalId '22222222-2222-2222-2222-222222222222' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err

            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'ScopedRoleNotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'DELETE' } -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/page2-target'
            }
        }
    }
}

Describe 'Remove-OERAdministrativeUnitScopedRole verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
    }

    It 'reports the resolved administrative unit and principal under -Verbose when found by RoleId + PrincipalId' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'srm-9'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }

        $Verbose = Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleId 'role-1' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERAdministrativeUnitScopedRole\] Resolved administrative unit to 'au-1'."
        $Text | Should -Match "\[Remove-OERAdministrativeUnitScopedRole\] Resolved principal to '11111111-1111-1111-1111-111111111111'."
    }

    It 'reports the resolved role line only when -RoleName was used to look it up' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'srm-9'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }

        $Verbose = Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -RoleName 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERAdministrativeUnitScopedRole\] Resolved role 'User Administrator' to 'role-1'."
    }

    It 'reports only the resolved administrative unit when removing by -ScopedRoleMembershipId directly' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        $Verbose = Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -ScopedRoleMembershipId 'srm-1' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERAdministrativeUnitScopedRole\] Resolved administrative unit to 'au-1'."
        $Text | Should -Not -Match 'Resolved principal to '
        $Text | Should -Not -Match 'Resolved role '
    }

    It 'emits no verbose output without -Verbose' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        $Verbose = Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -ScopedRoleMembershipId 'srm-1' -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}

Describe 'Remove-OERAdministrativeUnitScopedRole -Role alias' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'exposes Role as an alias of RoleName' {
        (Get-Command Remove-OERAdministrativeUnitScopedRole).Parameters['RoleName'].Aliases |
            Should -Contain 'Role'
    }

    It 'does not declare its own Role parameter (which would collide with the alias)' {
        (Get-Command Remove-OERAdministrativeUnitScopedRole).Parameters.Keys | Should -Not -Contain 'Role'
    }

    It 'does not bind RoleName from the pipeline by property name' {
        # The alias must not turn an incoming object's Role/RoleName property into a silent binding.
        (Get-Command Remove-OERAdministrativeUnitScopedRole).Parameters['RoleName'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName } |
            Should -BeNullOrEmpty
    }

    It 'completes -RoleName with the curated directory roles' {
        $Line = 'Remove-OERAdministrativeUnitScopedRole -RoleName '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'User Administrator'"
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'Contributor'
    }

    It 'completes the -Role alias spelling too' {
        $Line = 'Remove-OERAdministrativeUnitScopedRole -Role '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'User Administrator'"
    }

    It 'binds -Role to RoleName and resolves the membership from RoleId + PrincipalId then deletes' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleId { 'role-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'srm-9'; roleId = 'role-1'; roleMemberInfo = @{ id = '11111111-1111-1111-1111-111111111111' } }) }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }

        Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -Role 'User Administrator' `
            -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false

        Should -Invoke -ModuleName $script:moduleName Resolve-OERDirectoryRoleId -Times 1 -Exactly `
            -ParameterFilter { $RoleName -eq 'User Administrator' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers/srm-9'
        }
    }
}

Describe 'Remove-OERAdministrativeUnitScopedRole bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The unit resolver is mocked to SUCCEED and -ScopedRoleMembershipId short-circuits the
        # principal and directory-role resolution entirely, so the thrown transport drives the
        # scopedRoleMembers DELETE catch and not the resolver catch or the list-read catch.
        # ConfirmImpact is High on this cmdlet, so -Confirm:$false is required or the call blocks.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Remove-OERAdministrativeUnitScopedRole -Id 'au-1' -ScopedRoleMembershipId 'srm-1' `
            -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
