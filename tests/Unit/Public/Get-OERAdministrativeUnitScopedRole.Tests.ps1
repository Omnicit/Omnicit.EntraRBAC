BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAdministrativeUnitScopedRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'lists scoped role members as tagged objects' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'srm-1'; roleId = 'r-1'; administrativeUnitId = 'au-1'; roleMemberInfo = @{ id = 'u-1'; displayName = 'Jane' } }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r-1'; roleTemplateId = 'rt-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        $Result = @(Get-OERAdministrativeUnitScopedRole -Id 'au-1')
        $Result.Count | Should -Be 1
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole'
        $Result[0].RoleName | Should -Be 'User Administrator'
        $Result[0].PrincipalDisplayName | Should -Be 'Jane'
    }

    It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding for -AdministrativeUnit (a capability, not a break)' {
        # Before the identity-parameter collapse this cmdlet had two parameter sets (ById/ByName),
        # which suppressed ALL implicit positional binding. After the collapse there is exactly one
        # parameter set, so -AdministrativeUnit (its only mandatory parameter) now binds positionally.
        # 'au-1' is not a canonical GUID, so dispatch correctly routes it to -DisplayName, not -Id
        # (proven separately by the "identity parameter collapse" Context above) -- the point here is
        # only that the positional value reaches Resolve-OERAdministrativeUnitId AT ALL, and then the
        # resolved id reaches the URI.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        @(Get-OERAdministrativeUnitScopedRole 'au-1') | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
            $DisplayName -eq 'au-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers'
        }
    }

    It 'emits AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Get-OERAdministrativeUnitScopedRole -DisplayName 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Get-OERAdministrativeUnitScopedRole -DisplayName 'au1' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'cccccccc-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAdministrativeUnitScopedRole -AdministrativeUnit 'cccccccc-1111-1111-1111-111111111111' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'cccccccc-1111-1111-1111-111111111111' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = 'au_hr' }
                Get-OERAdministrativeUnitScopedRole @Splat | Out-Null
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers'
            }
        }
    }

    It 'passes -All to the /scopedRoleMembers read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'srm-1'; roleId = 'r-1'; administrativeUnitId = 'au-1'; roleMemberInfo = @{ id = 'u-1'; displayName = 'Jane' } }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r-1'; roleTemplateId = 'rt-1'; displayName = 'User Administrator' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        @(Get-OERAdministrativeUnitScopedRole -Id 'au-1') | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/scopedRoleMembers' -and $All
        }
    }
}

Describe 'Get-OERAdministrativeUnitScopedRole bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The unit resolver is mocked to SUCCEED so the thrown transport drives the
        # scopedRoleMembers read catch, not the resolver's own catch (which also scrubs).
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = Get-OERAdministrativeUnitScopedRole -Id 'au-1' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
