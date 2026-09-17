BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAdministrativeUnitMember' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'removes a member via the members/{id}/$ref endpoint' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/11111111-1111-1111-1111-111111111111/$ref'
        }
    }

    It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding (a capability, not a break)' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding. After the collapse there is exactly one
        # parameter set, so -AdministrativeUnit (position 0) and -MemberId (position 1) now bind
        # positionally.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnitMember 'au-1' '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/11111111-1111-1111-1111-111111111111/$ref'
        }
    }

    It 'emits AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnitMember -DisplayName 'nope' -MemberId '22222222-2222-2222-2222-222222222222' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Remove-OERAdministrativeUnitMember -DisplayName 'au1' -MemberId '22222222-2222-2222-2222-222222222222' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnitMember -Id 'au-1' -MemberId '22222222-2222-2222-2222-222222222222' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        }

        It 'resolves -User to an object id and deletes it from members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Remove-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/directory/administrativeUnits/auau0000-0000-0000-0000-00000000000b/members/bbbb0000-0000-0000-0000-000000000002/$ref'
            }
        }

        It 'resolves -Group by display name' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            Remove-OERAdministrativeUnitMember -DisplayName 'au_hr' -Group 'Sales Team' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/directory/administrativeUnits/auau0000-0000-0000-0000-00000000000b/members/cccc0000-0000-0000-0000-000000000003/$ref'
            }
        }

        It 'unions -MemberId with the friendly parameters' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Remove-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -MemberId 'aaaa0000-0000-0000-0000-000000000001' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 2 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'rejects a UPN passed to -MemberId with InvalidMemberId and does not call Graph' {
            $Err = $null
            Remove-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -MemberId 'anna.berg@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidMemberId*'
            $Err[0].Exception.Message | Should -BeLike "*'-MemberId'*"
            $Err[0].Exception.Message | Should -BeLike '*-User or -Group*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'reports NoPrincipal when neither -MemberId nor a friendly parameter is supplied' {
            $Err = $null
            Remove-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }
    }

    Context 'member shape pipeline binding (closes prom-au-member-surface-has-no-read-or-pipeline-story, safe only after 5a)' {
        It 'pipes a real ConvertTo-OERAdministrativeUnitMember object straight back in: AU id in the AU segment, principal id in the member segment' {
            # Neither Resolve-OERAdministrativeUnitId NOR the identity dispatch is mocked: the piped
            # member object's AdministrativeUnitId property (present because ConvertTo-OER-
            # AdministrativeUnitMember stamps it) binds -AdministrativeUnit via the AdministrativeUnitId
            # alias -- which precedes Id/DisplayName in the alias order, so the member's OWN Id/DisplayName
            # never mis-binds as the parent unit. The member's own PrincipalId binds -MemberId via its
            # -PrincipalId alias. Both values are canonical GUIDs, so Resolve-OERAdministrativeUnitId's
            # real -Id short-circuit returns the AU id verbatim with no extra Graph call.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $AuId = 'eeeeeeee-1111-1111-1111-111111111111'
            $PrincipalId = 'ffffffff-1111-1111-1111-111111111111'
            $Member = InModuleScope $script:moduleName -Parameters @{ AuId = $AuId; PrincipalId = $PrincipalId } {
                param($AuId, $PrincipalId)
                ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = $PrincipalId; displayName = 'Jane' } -AdministrativeUnitId $AuId
            }
            $Member | Remove-OERAdministrativeUnitMember -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq "v1.0/directory/administrativeUnits/$AuId/members/$PrincipalId/`$ref"
            }
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'aaaaaaaa-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnitMember -AdministrativeUnit 'aaaaaaaa-1111-1111-1111-111111111111' `
                -MemberId '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'aaaaaaaa-1111-1111-1111-111111111111' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' `
                -MemberId '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = 'au_hr'; MemberId = '11111111-1111-1111-1111-111111111111'; Confirm = $false }
                Remove-OERAdministrativeUnitMember @Splat
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/11111111-1111-1111-1111-111111111111/$ref'
            }
        }
    }

    Context 'principal parameter naming (audit PR6)' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '22222222-2222-2222-2222-222222222222' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        }

        It 'accepts -PrincipalId as an alias for -MemberId' {
            Remove-OERAdministrativeUnitMember -Id '22222222-2222-2222-2222-222222222222' `
                -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -like '*/members/11111111-1111-1111-1111-111111111111/$ref'
            }
        }
    }
}

Describe 'Remove-OERAdministrativeUnitMember verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
    }

    It 'reports the resolved administrative unit and one line per resolved principal under -Verbose' {
        $Verbose = Remove-OERAdministrativeUnitMember -Id 'au-1' -MemberId @(
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222'
        ) -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERAdministrativeUnitMember\] Resolved administrative unit to 'au-1'."
        @($Verbose | Where-Object { $_.Message -match 'Resolved principal to ' }).Count | Should -Be 2
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Remove-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}

Describe 'Remove-OERAdministrativeUnitMember bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The unit resolver is mocked to SUCCEED and -MemberId is a canonical GUID (which
        # Resolve-OERPrincipalOrId returns verbatim without a Graph call), so the thrown transport
        # drives the members/{id}/$ref DELETE catch rather than either resolver's own catch.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Remove-OERAdministrativeUnitMember -Id 'au-1' `
            -MemberId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
