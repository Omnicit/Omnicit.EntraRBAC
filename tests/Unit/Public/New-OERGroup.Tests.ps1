BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    Context 'the mail alias derived from the name must be one Microsoft Graph accepts (BL-132, A9)' {
        # Measured 2026-10-13: a mailNickname of 65 characters and the empty string are refused with
        # Request_BadRequest. The alias New-OERGroup derives from the name is checked BEFORE the
        # administrative unit lookup and the create; an existing group is still returned (it needs no
        # alias) and an explicit -MailNickname is sent as given.
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'new-nick'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            }
        }

        It 'refuses a name whose derived alias is 65 characters, before any lookup of the unit and any request' {
            $Name = 'g' * 65
            $Result = New-OERGroup -DisplayName $Name -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'DerivedMailNicknameInvalid,New-OERGroup'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Err[0].TargetObject | Should -BeExactly $Name
            $Err[0].Exception.Message | Should -Match '65 characters'
            $Err[0].Exception.Message | Should -Match '1 to 64'
            $Err[0].Exception.Message | Should -Match 'Nothing was sent'
            $Err[0].Exception.Message | Should -Match '-MailNickname'
            # Positive proof that the guard is placed after the existence lookup, and before the rest.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 0
        }

        It 'refuses before the administrative unit lookup when -AdministrativeUnit is given' {
            $Result = New-OERGroup -DisplayName ('g' * 65) -AdministrativeUnit 'au' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'DerivedMailNicknameInvalid,New-OERGroup'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'refuses a name made only of characters the alias cannot carry, and says the alias is empty' {
            $Name = "$([char]0x00C5)$([char]0x00C4)$([char]0x00D6)"
            $Result = New-OERGroup -DisplayName $Name -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'DerivedMailNicknameInvalid,New-OERGroup'
            $Err[0].Exception.Message | Should -Match 'is empty'
            $Err[0].Exception.Message | Should -Match '1 to 64'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 0
        }

        It 'still creates a group whose derived alias is exactly 64 characters (unchanged behaviour)' {
            $Name = 'g' * 64
            $Result = New-OERGroup -DisplayName $Name -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).Count | Should -Be 0
            $Result.Id | Should -Be 'new-nick'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/groups' -and $Body.mailNickname.Length -eq 64 -and $Body.mailNickname -ceq ('g' * 64)
            }
        }

        It 'still derives the alias by removing every character outside A-Z, a-z, 0-9, dot, underscore and hyphen' {
            New-OERGroup -DisplayName 'Grupp med mellanslag (test)' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.mailNickname -ceq 'Gruppmedmellanslagtest' -and $Body.displayName -ceq 'Grupp med mellanslag (test)'
            }
        }

        It 'sends an explicit -MailNickname as given for a name whose derived alias would be refused: <Case>' -ForEach @(
            @{ Case = '65 characters'; Name = ('g' * 65) }
            @{ Case = 'the empty string'; Name = "$([char]0x00C5)$([char]0x00C4)$([char]0x00D6)" }
        ) {
            $Result = New-OERGroup -DisplayName $Name -MailNickname 'ok' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).Count | Should -Be 0
            $Result.Id | Should -Be 'new-nick'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.mailNickname -ceq 'ok'
            }
        }

        It 'sends an explicit -MailNickname exactly as given, even one the derived-alias rule would refuse' {
            # The refusal is about the alias the command derives itself. An alias the caller passes is
            # the caller's decision and Microsoft Graph answers for it, as before this change.
            $Long = 'a' * 70
            $Result = New-OERGroup -DisplayName 'role_sec_team' -MailNickname $Long -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).Count | Should -Be 0
            $Result.Id | Should -Be 'new-nick'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.mailNickname -ceq ('a' * 70)
            }
        }

        It 'returns an existing group named with 65 characters without an error (idempotency kept)' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'exists-65' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'exists-65'; displayName = ('g' * 65); securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
            $Result = New-OERGroup -DisplayName ('g' * 65) -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).Count | Should -Be 0
            $Result.Id | Should -Be 'exists-65'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses under -WhatIf with the same error and sends nothing' {
            $Result = New-OERGroup -DisplayName ('g' * 65) -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'DerivedMailNicknameInvalid,New-OERGroup'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'refuses an underivable name composed from -Area and -Tier too (the resolved name is what is derived)' {
            $Result = New-OERGroup -Area 'g' -Tier ('t' * 70) -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'DerivedMailNicknameInvalid,New-OERGroup'
            $Err[0].TargetObject | Should -BeExactly ('role_sec_g_' + ('t' * 70))
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
    }
}

Describe 'New-OERGroup: the derived mail alias refusal in a script with no try (Sprint 11 step 3, BL-132)' {
    # A refused call writes a NON-terminating error and the script goes on, so what it must not do is
    # send the create on the way. The script stands in no try, leaves $ErrorActionPreference alone,
    # prints a sentinel at its end, and the stubbed transport appends every request to a log file whose
    # path is substituted into the text. The control runs the same script with an explicit
    # -MailNickname, so a refused run with no POST in the log cannot be an artefact of a stub that
    # never logs one. The stub writes its log with -WhatIf:$false: a -WhatIf call passes its preference
    # down to Add-Content, which would otherwise skip the write and hide a -WhatIf request.
    BeforeAll {
        $script:NickNoTryScenario = {
            param([string]$Log, [string]$Calls)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value {
        param([string]$DisplayName)
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value 'Resolve-OERGroupId'
        $null
    }
    Set-Item -Path function:script:Resolve-OERAdministrativeUnitId -Value {
        param([string]$Id, [string]$DisplayName)
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value 'Resolve-OERAdministrativeUnitId'
        'au-1'
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        $Nick = if ($Body -and $Body.ContainsKey('mailNickname')) { $Body.mailNickname } else { 'none' }
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest $Method nick=$Nick"
        @{ id = 'new-nick'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
    }
}
#CALLS#
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#CALLS#', $Calls))
        }

        $script:NickRefusedCalls = @'
$Results = @(
    New-OERGroup -DisplayName ('g' * 65) -Confirm:$false -ErrorVariable E1
    New-OERGroup -DisplayName ('g' * 65) -AdministrativeUnit 'au' -Confirm:$false -ErrorVariable E2
    New-OERGroup -DisplayName ('g' * 65) -WhatIf -ErrorVariable E3
    New-OERGroup -DisplayName ([string][char]0x00C5) -Confirm:$false -ErrorVariable E4
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
"IDS:$(@(@($E1) + @($E2) + @($E3) + @($E4) | ForEach-Object { $_.FullyQualifiedErrorId }) -join '|')"
'@
        $script:NickControlCalls = @'
$Results = @(
    New-OERGroup -DisplayName ('g' * 65) -MailNickname 'ok' -Confirm:$false -ErrorVariable E1
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
"ERRORS:$(@($E1).Count)"
'@
        function Get-NickRequestLog ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'reaches the end of the script, sends nothing after the existence lookup, and writes the refusal once per call' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NickNoTryScenario -Log $Log -Calls $script:NickRefusedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        $Run.Output.Count | Should -Be 3
        $Run.Output[0] | Should -Be 'REACHED:0'
        $Run.Output[1] | Should -Be 'IDS:DerivedMailNicknameInvalid,New-OERGroup|DerivedMailNicknameInvalid,New-OERGroup|DerivedMailNicknameInvalid,New-OERGroup|DerivedMailNicknameInvalid,New-OERGroup'
        $Run.Output[2] | Should -Be 'END'
        # Positive proof that each call reached the existence lookup, and that was all it sent: no
        # administrative unit lookup, no request of any kind.
        @(Get-NickRequestLog -Log $Log) | Should -Be @('Resolve-OERGroupId', 'Resolve-OERGroupId', 'Resolve-OERGroupId', 'Resolve-OERGroupId')
        @($Run.Errors | Where-Object { $_ -like "The mail alias derived from the group name '*" }).Count | Should -Be 4
    }

    It 'the control: the same script with -MailNickname sends the create with that alias' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NickNoTryScenario -Log $Log -Calls $script:NickControlCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|ERRORS:0|END'
        @($Run.Errors).Count | Should -Be 0
        @(Get-NickRequestLog -Log $Log) | Should -Be @('Resolve-OERGroupId', 'Invoke-OERGraphRequest POST nick=ok')
    }
}
