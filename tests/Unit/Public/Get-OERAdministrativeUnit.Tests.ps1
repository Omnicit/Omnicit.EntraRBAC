BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAdministrativeUnit' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'lists every administrative unit when no selector is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-1'; displayName = 'au_hr' }, @{ id = 'au-2'; displayName = 'au_fin' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits' }
        $Result = @(Get-OERAdministrativeUnit)
        $Result.Count | Should -Be 2
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnit'
    }

    It 'returns nothing without error when the tenant has no administrative units' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits' }
        $Result = @(Get-OERAdministrativeUnit -ErrorVariable err -ErrorAction SilentlyContinue)
        $Result.Count | Should -Be 0
        $err | Should -BeNullOrEmpty
    }

    It 'reads an AU by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'au_hr' }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111' }
        $Result = Get-OERAdministrativeUnit -Id '11111111-1111-1111-1111-111111111111'
        $Result.Id | Should -Be '11111111-1111-1111-1111-111111111111'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnit'
    }

    It 'reads an AU by a non-GUID value via a filtered query (dispatches on Test-OERGuid, not parameter name)' {
        # A non-GUID value must go through the filtered query even when bound via the historical -Id
        # alias -- dispatch is on the VALUE shape (Test-OERGuid), never on which alias spelling bound it.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-1'; displayName = 'au_hr' }) }
        }
        $Result = Get-OERAdministrativeUnit -Id 'au_hr'
        $Result.Id | Should -Be 'au-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -match "displayName eq 'au_hr'"
        }
    }

    It 'reads an AU by display name with a filtered query' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-1'; displayName = 'au_hr' }) }
        }
        $Result = Get-OERAdministrativeUnit -DisplayName 'au_hr'
        $Result.Id | Should -Be 'au-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -match "displayName eq 'au_hr'"
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'reaches the same direct-read URI through -Id, -DisplayName and -AdministrativeUnitId when the value is a GUID' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'au_hr' }
            }
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = '22222222-2222-2222-2222-222222222222' }
                $Result = Get-OERAdministrativeUnit @Splat
                $Result.Id | Should -Be '22222222-2222-2222-2222-222222222222'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/22222222-2222-2222-2222-222222222222'
            }
        }

        It 'still binds when splatted, e.g. an apply-engine-style @{ Id = ... } call' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'au_hr' }
            }
            $Splat = @{ Id = '33333333-3333-3333-3333-333333333333' }
            $Result = Get-OERAdministrativeUnit @Splat
            $Result.Id | Should -Be '33333333-3333-3333-3333-333333333333'
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'au-9'; displayName = 'R&D + Core' }) }
        }
        $Result = Get-OERAdministrativeUnit -DisplayName 'R&D + Core'
        $Result.Id | Should -Be 'au-9'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'emits AdministrativeUnitNotFound when no unit matches' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAdministrativeUnit -DisplayName 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'attaches Members with -IncludeMembers' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'au_hr' }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'u-1'; displayName = 'Jane'; '@odata.type' = '#microsoft.graph.user' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/members' }
        $Result = Get-OERAdministrativeUnit -Id '11111111-1111-1111-1111-111111111111' -IncludeMembers
        @($Result.Members).Count | Should -Be 1
        $Result.Members[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitMember'
        $Result.Members[0].Type | Should -Be 'user'
        # Stamped so the member round-trips into Add-/Remove-OERAdministrativeUnitMember and the other
        # AU cmdlets' unified -AdministrativeUnit parameter via the AdministrativeUnitId alias.
        $Result.Members[0].AdministrativeUnitId | Should -Be '11111111-1111-1111-1111-111111111111'
        $Result.Members[0].PrincipalId | Should -Be 'u-1'
    }

    It 'attaches ScopedRoles with -IncludeScopedRoles' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'au_hr' }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'srm-1'; roleId = 'r-1'; roleMemberInfo = @{ id = 'u-1'; displayName = 'Jane' } }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/scopedRoleMembers' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r-1'; roleTemplateId = 'rt-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        $Result = Get-OERAdministrativeUnit -Id '11111111-1111-1111-1111-111111111111' -IncludeScopedRoles
        @($Result.ScopedRoles).Count | Should -Be 1
        $Result.ScopedRoles[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole'
        $Result.ScopedRoles[0].RoleName | Should -Be 'User Administrator'
    }

    Context 'paging (-All opt-in, closes rt-graph-list-reads-first-page-only)' {
        It 'passes -All to the unfiltered List read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'au-1'; displayName = 'au_hr' }, @{ id = 'au-2'; displayName = 'au_fin' }) }
            }
            @(Get-OERAdministrativeUnit) | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits' -and $All
            }
        }

        It 'passes -All to the -Filter list read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'au-3'; displayName = 'au_it' }) }
            }
            Get-OERAdministrativeUnit -Filter "startswith(displayName,'au_')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*startswith*' -and $All
            }
        }

        It 'passes -All to the /members read for -IncludeMembers' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'au_hr' }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'u-1'; displayName = 'Jane'; '@odata.type' = '#microsoft.graph.user' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/members' }
            Get-OERAdministrativeUnit -Id '11111111-1111-1111-1111-111111111111' -IncludeMembers | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/members' -and $All
            }
        }

        It 'passes -All to the /scopedRoleMembers read for -IncludeScopedRoles' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'au_hr' }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'srm-1'; roleId = 'r-1'; roleMemberInfo = @{ id = 'u-1'; displayName = 'Jane' } }) }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/scopedRoleMembers' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'r-1'; roleTemplateId = 'rt-1'; displayName = 'User Administrator' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
            Get-OERAdministrativeUnit -Id '11111111-1111-1111-1111-111111111111' -IncludeScopedRoles | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111/scopedRoleMembers' -and $All
            }
        }
    }

    Context 'a failed collection read is not an empty collection' {
        BeforeEach {
            # GUID-shaped so Test-OERGuid dispatches to the direct-GET branch (a non-GUID id such as
            # 'au-1' routes through the displayName-filter branch instead, which this mock does not
            # match, leaving Invoke-OERGraphRequest unmocked for that call).
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'cccccccc-1111-1111-1111-111111111111'; displayName = 'AU-One'; visibility = $null }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/cccccccc-1111-1111-1111-111111111111' }
        }

        It 'carries a Members property holding an empty array when the unit genuinely has no members' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/cccccccc-1111-1111-1111-111111111111/members' }

            $Au = Get-OERAdministrativeUnit -AdministrativeUnit 'cccccccc-1111-1111-1111-111111111111' -IncludeMembers
            $Au.PSObject.Properties.Name -contains 'Members' |
                Should -BeTrue -Because 'a successful read of an empty unit is a fact the document may state'
            @($Au.Members).Count | Should -Be 0
        }

        It 'omits the Members property and errors when the member read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'Forbidden'
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/cccccccc-1111-1111-1111-111111111111/members' }

            $Au = Get-OERAdministrativeUnit -AdministrativeUnit 'cccccccc-1111-1111-1111-111111111111' -IncludeMembers -ErrorVariable ReadErr -ErrorAction SilentlyContinue
            # Prove the cmdlet actually emitted the AU object before trusting an absent-property read
            # on it -- a $null result also satisfies '-contains' -> $false, so that check alone cannot
            # tell "read the unit and correctly omitted Members" from "emitted nothing at all".
            $Au | Should -Not -BeNullOrEmpty
            $Au.Id | Should -Be 'cccccccc-1111-1111-1111-111111111111'
            $Au.PSObject.Properties.Name -contains 'Members' |
                Should -BeFalse -Because 'an empty collection here becomes members:[] in an inventory document, which -Prune deletes on'
            # -ErrorVariable also accumulates Pester's own internal mock-invocation bookkeeping noise;
            # restrict to the record actually published through the cmdlet's own WriteError call.
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAdministrativeUnit'
            }
            @($Published).Count | Should -BeGreaterThan 0
            @($Published)[0].FullyQualifiedErrorId | Should -Match 'AdministrativeUnitMemberReadFailed'
        }

        It 'scrubs the bearer-hygiene record before writing the member-read error' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'Forbidden'
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/cccccccc-1111-1111-1111-111111111111/members' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

            Get-OERAdministrativeUnit -AdministrativeUnit 'cccccccc-1111-1111-1111-111111111111' -IncludeMembers -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'omits the ScopedRoles property and errors when the scoped-role read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'Forbidden'
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/cccccccc-1111-1111-1111-111111111111/scopedRoleMembers' }

            $Au = Get-OERAdministrativeUnit -AdministrativeUnit 'cccccccc-1111-1111-1111-111111111111' -IncludeScopedRoles -ErrorVariable ReadErr -ErrorAction SilentlyContinue
            # Same positive-identity proof as the member-read test above before trusting the
            # absent-property check.
            $Au | Should -Not -BeNullOrEmpty
            $Au.Id | Should -Be 'cccccccc-1111-1111-1111-111111111111'
            $Au.PSObject.Properties.Name -contains 'ScopedRoles' | Should -BeFalse
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAdministrativeUnit'
            }
            @($Published).Count | Should -BeGreaterThan 0
            @($Published)[0].FullyQualifiedErrorId | Should -Match 'AdministrativeUnitScopedRoleReadFailed'
        }
    }
}

Describe 'Get-OERAdministrativeUnit bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # Drives the ByName read catch: the failed HttpRequestMessage still in $Error carries
        # Authorization: Bearer <token> in plain text, so the scrub has to RUN, not merely be
        # written. The static AST gate proves placement; only this proves invocation.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Get-OERAdministrativeUnit -DisplayName 'au_hr' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
