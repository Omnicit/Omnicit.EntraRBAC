BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERGroup' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'creates a static security group with no role assignability and no dynamic membership' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'new-1'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = New-OERGroup -DisplayName 'role_sec_team'
        $Result.Id | Should -Be 'new-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Group'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups' -and
            $Body.securityEnabled -eq $true -and
            (-not $Body.ContainsKey('isAssignableToRole')) -and
            (-not $Body.ContainsKey('groupTypes'))
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'sets isAssignableToRole true for a -RoleAssignable group' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'r-1'; displayName = 'role_sec_priv'; isAssignableToRole = $true; securityEnabled = $true; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERGroup -DisplayName 'role_sec_priv' -RoleAssignable | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.isAssignableToRole -eq $true -and (-not $Body.ContainsKey('groupTypes'))
        }
    }

    It 'creates a dynamic group with groupTypes and the membership rule' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'd-1'; displayName = 'dyn_eng'; securityEnabled = $true; isAssignableToRole = $false
                groupTypes = @('DynamicMembership'); membershipRule = '(user.department -eq "Engineering")' }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERGroup -DisplayName 'dyn_eng' -Dynamic -MembershipRule '(user.department -eq "Engineering")' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.groupTypes -contains 'DynamicMembership' -and
            $Body.membershipRule -eq '(user.department -eq "Engineering")' -and
            $Body.membershipRuleProcessingState -eq 'On' -and
            (-not $Body.ContainsKey('isAssignableToRole'))
        }
    }

    It 'errors when -RoleAssignable and -Dynamic are combined' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERGroup -DisplayName 'x' -RoleAssignable -Dynamic -MembershipRule 'r' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'RoleAndDynamicExclusive'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors when -Dynamic is supplied without -MembershipRule' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERGroup -DisplayName 'x' -Dynamic -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'MembershipRuleRequired'
    }

    It 'errors when -MembershipRule is supplied without -Dynamic' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERGroup -DisplayName 'x' -MembershipRule 'r' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'MembershipRuleRequiresDynamic'
    }

    It 'is idempotent: returns the existing group without a POST' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'exists-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'exists-1'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = New-OERGroup -DisplayName 'role_sec_team'
        $Result.Id | Should -Be 'exists-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'resolves the name from -Area/-Tier via the default template' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'a-1'; displayName = 'role_sec_identity_administrator'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERGroup -Area 'identity' -Tier 'administrator' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'role_sec_identity_administrator'
        }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERGroup -DisplayName 'role_sec_whatif' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'creates the group inside an AU via the AU members endpoint when -AdministrativeUnit is a display name' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'g-au'; displayName = 'role_sec_hr'; securityEnabled = $true; isAssignableToRole = $true; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = New-OERGroup -DisplayName 'role_sec_hr' -RoleAssignable -AdministrativeUnit 'au_hr'
        $Result.Id | Should -Be 'g-au'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-1/members' -and
            $Body.'@odata.type' -eq '#microsoft.graph.group' -and
            $Body.isAssignableToRole -eq $true
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups'
        }
    }

    It 'resolves -AdministrativeUnit by id when a GUID is supplied' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { param($Id, $DisplayName) $Id }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'g-au2'; displayName = 'role_sec_x'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'POST' }
        New-OERGroup -DisplayName 'role_sec_x' -AdministrativeUnit '00000000-0000-0000-0000-000000000abc' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/directory/administrativeUnits/00000000-0000-0000-0000-000000000abc/members'
        }
    }

    It 'errors AdministrativeUnitNotFound when -AdministrativeUnit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERGroup -DisplayName 'role_sec_x' -AdministrativeUnit 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'warns and returns the existing group without re-parenting when it already exists' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'exists-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'exists-1'; displayName = 'role_sec_hr'; securityEnabled = $true; isAssignableToRole = $true; groupTypes = @() }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = New-OERGroup -DisplayName 'role_sec_hr' -RoleAssignable -AdministrativeUnit 'au_hr' -WarningVariable warn -WarningAction SilentlyContinue
        $Result.Id | Should -Be 'exists-1'
        $warn | Should -Match 'not be re-parented|was not re-parented|already exists'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    Context 'pre-check failure must not create a duplicate' {
        It 'errors with GroupResolveFailed and does NOT create when the pre-check throws' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERGroup -DisplayName 'RoleSec-Test' -MailNickname 'rolesectest' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupResolveFailed,New-OERGroup' }).Count | Should -Be 1
        }

        It 'scrubs the bearer-carrying record before reporting the pre-check failure' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            New-OERGroup -DisplayName 'RoleSec-Test' -MailNickname 'rolesectest' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }

        It 'still creates when the pre-check genuinely finds nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'new-2'; displayName = 'RoleSec-Test'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -eq 'POST' }
            New-OERGroup -DisplayName 'RoleSec-Test' -MailNickname 'rolesectest' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 1
        }
    }

    Context 'AdministrativeUnit lookup failure must not create outside the intended unit' {
        It 'errors with AdministrativeUnitResolveFailed and does NOT create when the AU lookup throws' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Graph returned 503 ServiceUnavailable' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERGroup -DisplayName 'role_sec_hr' -AdministrativeUnit 'au_hr' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AdministrativeUnitResolveFailed,New-OERGroup' }).Count | Should -Be 1
        }

        It 'scrubs the bearer-carrying record before reporting the AU lookup failure' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Graph returned 503 ServiceUnavailable' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            New-OERGroup -DisplayName 'role_sec_hr' -AdministrativeUnit 'au_hr' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }

        It 'still reports AdministrativeUnitNotFound when the AU lookup genuinely finds nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERGroup -DisplayName 'role_sec_hr' -AdministrativeUnit 'au_hr' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AdministrativeUnitNotFound,New-OERGroup' }).Count | Should -Be 1
        }
    }
}
