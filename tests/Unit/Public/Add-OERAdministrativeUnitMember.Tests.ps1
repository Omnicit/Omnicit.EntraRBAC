BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Add-OERAdministrativeUnitMember' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'adds a member via the members/$ref endpoint' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'adds multiple members' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'positional binding: collapsing ById/ByName into a single -AdministrativeUnit parameter ADDS positional binding (a capability, not a break), and the named contract still resolves correctly' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding -- no parameter, not -Id, not -MemberId,
        # ever got an implicit position, and a positional call threw PositionalParameterNotFound.
        # After the collapse there is exactly one parameter set, so PowerShell assigns positions by
        # declaration order (switches skipped): -AdministrativeUnit is position 0, -MemberId is
        # position 1. Nothing that used to work stops working -- this only adds a capability that
        # could not exist before, so it is safe, but it must be asserted explicitly (mirrors the
        # equivalent Remove-OERAdministrativeUnit wrinkle from the same collapse).
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        Add-OERAdministrativeUnitMember 'au-1' '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/11111111-1111-1111-1111-111111111111'
        }

        Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'emits AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitMember -DisplayName 'nope' -MemberId '22222222-2222-2222-2222-222222222222' -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Add-OERAdministrativeUnitMember -DisplayName 'au1' -MemberId '22222222-2222-2222-2222-222222222222' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '22222222-2222-2222-2222-222222222222' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'auau0000-0000-0000-0000-00000000000b' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        }

        It 'resolves -User to an object id and posts it to members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Add-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/directory/administrativeUnits/auau0000-0000-0000-0000-00000000000b/members/$ref' -and
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/bbbb0000-0000-0000-0000-000000000002'
            }
        }

        It 'resolves -Group by display name' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            Add-OERAdministrativeUnitMember -DisplayName 'au_hr' -Group 'Sales Team' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/cccc0000-0000-0000-0000-000000000003'
            }
        }

        It 'unions -MemberId with the friendly parameters' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Add-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -MemberId 'aaaa0000-0000-0000-0000-000000000001' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 2 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'rejects a UPN passed to -MemberId with InvalidMemberId and does not call Graph' {
            $Err = $null
            Add-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' `
                -MemberId 'anna.berg@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidMemberId*'
            $Err[0].Exception.Message | Should -BeLike "*'-MemberId'*"
            $Err[0].Exception.Message | Should -BeLike '*-User or -Group*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'reports NoPrincipal when neither -MemberId nor a friendly parameter is supplied' {
            $Err = $null
            Add-OERAdministrativeUnitMember -Id 'auau0000-0000-0000-0000-00000000000b' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }
    }

    Context 'member shape pipeline binding (closes prom-au-member-surface-has-no-read-or-pipeline-story, safe only after 5a)' {
        It 'pipes a real ConvertTo-OERAdministrativeUnitMember object straight back in: AU id in the AU segment, principal id in the request body' {
            # Neither Resolve-OERAdministrativeUnitId NOR the identity dispatch is mocked: the piped
            # member object's AdministrativeUnitId property binds -AdministrativeUnit via the
            # AdministrativeUnitId alias (which precedes Id/DisplayName), and the member's own
            # PrincipalId binds -MemberId via its -PrincipalId alias.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
            $AuId = 'eeeeeeee-2222-2222-2222-222222222222'
            $PrincipalId = 'ffffffff-2222-2222-2222-222222222222'
            $Member = InModuleScope $script:moduleName -Parameters @{ AuId = $AuId; PrincipalId = $PrincipalId } {
                param($AuId, $PrincipalId)
                ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = $PrincipalId; displayName = 'Jane' } -AdministrativeUnitId $AuId
            }
            $Member | Add-OERAdministrativeUnitMember -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq "v1.0/directory/administrativeUnits/$AuId/members/`$ref" -and
                $Body.'@odata.id' -match $PrincipalId
            }
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '99999999-9999-9999-9999-999999999999' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERAdministrativeUnitMember -AdministrativeUnit '99999999-9999-9999-9999-999999999999' `
                -MemberId '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq '99999999-9999-9999-9999-999999999999' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' `
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
                Add-OERAdministrativeUnitMember @Splat
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members/$ref'
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
            Add-OERAdministrativeUnitMember -Id '22222222-2222-2222-2222-222222222222' `
                -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and "$($Body['@odata.id'])" -like '*11111111-1111-1111-1111-111111111111'
            }
        }
    }

    Context 'sovereign cloud @odata.id host' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        }
        AfterEach {
            # Never leak a sovereign-cloud session into a later test in this or another file.
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        }

        It 'pins today''s exact public-cloud @odata.id literal when there is no session at all' {
            Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq 'https://graph.microsoft.com/v1.0/directoryObjects/11111111-1111-1111-1111-111111111111'
            }
        }

        It 'uses the public-cloud root when the cached session state carries no Environment' {
            InModuleScope $script:moduleName {
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
            }
            Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '22222222-2222-2222-2222-222222222222' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq 'https://graph.microsoft.com/v1.0/directoryObjects/22222222-2222-2222-2222-222222222222'
            }
        }

        It 'names the session cloud''s own Graph service root for <_>' -ForEach @('USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            $MemberGuid = '33333333-3333-3333-3333-333333333333'
            InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
            }
            # Driven from the table owner itself, not a second hardcoded expectation.
            $ExpectedRoot = InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                (Get-OERCloudEndpoint -Environment $Cloud).GraphServiceRoot
            }
            Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId $MemberGuid -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq "$ExpectedRoot/directoryObjects/$MemberGuid"
            }
        }

        It 'never emits a double slash after the host for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            $MemberGuid = '44444444-4444-4444-4444-444444444444'
            InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
            }
            $script:CapturedBody = $null
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                $script:CapturedBody = $Body
            }
            Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId $MemberGuid -Confirm:$false
            $script:CapturedBody | Should -Not -BeNullOrEmpty
            ($script:CapturedBody.'@odata.id' -replace '^https://', '') | Should -Not -Match '//'
        }
    }
}

Describe 'Add-OERAdministrativeUnitMember verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
    }

    It 'reports the resolved administrative unit and one line per resolved principal under -Verbose' {
        $Verbose = Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId @(
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222'
        ) -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Add-OERAdministrativeUnitMember\] Resolved administrative unit to 'au-1'."
        @($Verbose | Where-Object { $_.Message -match 'Resolved principal to ' }).Count | Should -Be 2
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Add-OERAdministrativeUnitMember -Id 'au-1' -MemberId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}

Describe 'Add-OERAdministrativeUnitMember bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The unit resolver is mocked to SUCCEED and -MemberId is a canonical GUID (which
        # Resolve-OERPrincipalOrId returns verbatim without a Graph call), so the thrown transport
        # drives the members/$ref POST catch rather than either resolver's own catch.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Add-OERAdministrativeUnitMember -Id 'au-1' `
            -MemberId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
