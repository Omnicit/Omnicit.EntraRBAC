BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERAdministrativeUnit' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'creates a regular AU with just a display name' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-1'; displayName = 'au_hr' }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = New-OERAdministrativeUnit -DisplayName 'au_hr'
        $Result.Id | Should -Be 'au-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnit'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directory/administrativeUnits' -and
            $Body.displayName -eq 'au_hr' -and (-not $Body.ContainsKey('isMemberManagementRestricted')) -and
            (-not $Body.ContainsKey('membershipType'))
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'sets isMemberManagementRestricted for -Restricted' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-r'; displayName = 'au_exec'; isMemberManagementRestricted = $true }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERAdministrativeUnit -DisplayName 'au_exec' -Restricted | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.isMemberManagementRestricted -eq $true
        }
    }

    It 'creates a dynamic AU with membershipType, rule and processing state' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-d'; displayName = 'au_se'; membershipType = 'Dynamic' }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERAdministrativeUnit -DisplayName 'au_se' -Dynamic -MembershipRule '(user.country -eq "SE")' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.membershipType -eq 'Dynamic' -and
            $Body.membershipRule -eq '(user.country -eq "SE")' -and $Body.membershipRuleProcessingState -eq 'On'
        }
    }

    It 'errors when -Dynamic is supplied without -MembershipRule' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAdministrativeUnit -DisplayName 'au_x' -Dynamic -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'MembershipRuleRequired'
    }

    It 'errors when -MembershipRule is supplied without -Dynamic' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAdministrativeUnit -DisplayName 'au_x' -MembershipRule 'r' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'MembershipRuleRequiresDynamic'
    }

    It 'is idempotent: returns the existing AU without a POST' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-exists' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-exists'; displayName = 'au_hr' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = New-OERAdministrativeUnit -DisplayName 'au_hr'
        $Result.Id | Should -Be 'au-exists'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAdministrativeUnit -DisplayName 'au_whatif' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'sets visibility for -HiddenMembership' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-h'; displayName = 'au_hidden'; visibility = 'HiddenMembership' }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERAdministrativeUnit -DisplayName 'au_hidden' -HiddenMembership | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.visibility -eq 'HiddenMembership'
        }
    }

    It 'resolves the name from -Name/-Prefix via the default template' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'au-t'; displayName = 'corp_au_hr' }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERAdministrativeUnit -Name 'hr' -Prefix 'corp' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'corp_au_hr'
        }
    }

    It 'errors NameResolutionFailed when -Name is used without -Prefix under the default template' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAdministrativeUnit -Name 'hr' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err[-1].FullyQualifiedErrorId | Should -Match 'NameResolutionFailed'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'does not create when the idempotency pre-check lookup fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'TooManyRequests' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'should-not-happen' } }
        New-OERAdministrativeUnit -DisplayName 'au1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }
}

Describe 'New-OERAdministrativeUnit bearer-token hygiene' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'scrubs the bearer-hygiene record when the transport fails' {
        # The idempotency pre-check resolver is mocked to SUCCEED with no existing unit, so the
        # thrown transport drives the create POST catch rather than the resolver's own catch or
        # the existing-unit read catch (both of which also scrub).
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $null = New-OERAdministrativeUnit -DisplayName 'au_hr' -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
