BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Remove-OERActiveDirectoryRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbbbbbb-0000-0000-0000-000000000002'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body)
            [PSCustomObject]@{
                id               = 'req1'
                action           = $Body.action
                status           = 'Provisioned'
                roleDefinitionId = $Body.roleDefinitionId
                principalId      = $Body.principalId
                directoryScopeId = $Body.directoryScopeId
                justification    = $Body.justification
                createdDateTime  = '2026-09-01T00:00:00Z'
                scheduleInfo     = $null
            }
        }
    }

    It 'POSTs an adminRemove request with no scheduleInfo key' {
        Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -and
            $Body.action -eq 'adminRemove' -and
            $Body.roleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
            $Body.principalId -eq 'bbbbbbbb-0000-0000-0000-000000000002' -and
            -not $Body.ContainsKey('scheduleInfo')
        }
    }

    It 'declares ConfirmImpact High' {
        $Attr = (Get-Command Remove-OERActiveDirectoryRoleAssignment).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attr.ConfirmImpact | Should -Be 'High'
    }

    It 'warns before removing and still issues the POST' {
        $Warnings = @()
        Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'Removing active directory role'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'sends no request under -WhatIf' {
        Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'binds -Role and -PrincipalId from piped Get-OERActiveDirectoryRoleAssignment-shaped output, with the piped role value flowing through unchanged' {
        # The default BeforeEach mock of Resolve-OERDirectoryRoleDefinitionId always returns the same
        # fixed GUID regardless of input, so a piped RoleDefinitionId equal to that fixed value cannot
        # prove the piped value actually flows anywhere -- the assertion would pass even if the
        # pipeline binding were broken. Mock it here to ECHO its -Role input lower-cased instead (the
        # real function's own documented GUID short-circuit behavior), pipe a role id that is NOT the
        # BeforeEach fixture's id, and assert that exact (lower-cased) value reaches the POST body.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            param($Role)
            $Role.ToLowerInvariant()
        }
        $Piped = [PSCustomObject]@{
            RoleDefinitionId = 'FFFFFFFF-1111-2222-3333-444444444444'
            PrincipalId      = 'cccccccc-0000-0000-0000-000000000003'
        }
        $Piped.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ActiveDirectoryRoleAssignment')
        $Piped | Remove-OERActiveDirectoryRoleAssignment -Confirm:$false -WarningAction SilentlyContinue

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Body.roleDefinitionId -eq 'ffffffff-1111-2222-3333-444444444444' -and
            $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000003'
        }
    }

    It 'reports RoleDefinitionNotFound and issues no POST when the role does not resolve' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        $Err = $null
        Remove-OERActiveDirectoryRoleAssignment -Role 'Ghost Role' -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'RoleDefinitionNotFound,Remove-OERActiveDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports AmbiguousRoleName and issues no POST when the role name is ambiguous' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Err = $null
        Remove-OERActiveDirectoryRoleAssignment -Role 'Dup' -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        # $Err[0] is not necessarily the cmdlet's own WriteError record: a mocked throw that is caught
        # and re-routed by Resolve-OERDirectoryRoleInput can still leave earlier phantom entries in
        # -ErrorVariable, so filter for the cmdlet-qualified id instead of indexing, matching
        # tests/Unit/Public/Get-OERDirectoryRoleManagementPolicy.Tests.ps1.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRoleName,Remove-OERActiveDirectoryRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'errors AmbiguousPrincipal and issues no POST when -User is bound alongside a piped object carrying its own PrincipalId' {
        $Piped = [PSCustomObject]@{ RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; PrincipalId = 'eeeeeeee-0000-0000-0000-000000000005' }
        $Err = $null
        $Piped | Remove-OERActiveDirectoryRoleAssignment -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,Remove-OERActiveDirectoryRoleAssignment'
        $Err[0].Exception.Message | Should -Match 'lose its active assignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a piped row inherited through a group with NotDirectAssignment, before any Graph call' {
        # The adminRemove request names only the role and the principal, so a piped inherited row
        # (the MEMBER's PrincipalId) would remove that member's own DIRECT active assignment instead.
        $Piped = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'eeeeeeee-0000-0000-0000-000000000005'
            MemberType       = 'Group'
            AssignmentType   = 'Assigned'
        }
        $Err = $null
        $Piped | Remove-OERActiveDirectoryRoleAssignment -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Hit = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OERActiveDirectoryRoleAssignment' })
        $Hit.Count | Should -Be 1
        $Hit[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Hit[0].TargetObject | Should -Be 'eeeeeeee-0000-0000-0000-000000000005'
        $Hit[0].Exception.Message | Should -Match ([regex]::Escape("is inherited through a group (MemberType 'Group')"))
        $Hit[0].Exception.Message | Should -Match ([regex]::Escape("Remove the group's own active assignment"))
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a piped Activated row with NotDirectAssignment, before any Graph call' {
        # An activation is the principal's own activation of an eligible assignment; removing "it" by
        # role and principal would remove that principal's DIRECT, standing active assignment instead.
        $Piped = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'eeeeeeee-0000-0000-0000-000000000005'
            MemberType       = 'Direct'
            AssignmentType   = 'Activated'
        }
        $Err = $null
        $Piped | Remove-OERActiveDirectoryRoleAssignment -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Hit = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OERActiveDirectoryRoleAssignment' })
        $Hit.Count | Should -Be 1
        $Hit[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Hit[0].Exception.Message | Should -Match ([regex]::Escape('is an activation, which PIM ends on its own'))
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'removes a piped Direct, Assigned row, and only that one when it is piped together with an inherited and an Activated row' {
        $Inherited = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'eeeeeeee-0000-0000-0000-000000000005'
            MemberType       = 'Group'
            AssignmentType   = 'Assigned'
        }
        $Activated = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'dddddddd-0000-0000-0000-000000000004'
            MemberType       = 'Direct'
            AssignmentType   = 'Activated'
        }
        $Direct = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'cccccccc-0000-0000-0000-000000000003'
            MemberType       = 'Direct'
            AssignmentType   = 'Assigned'
        }
        $Err = $null
        $Inherited, $Activated, $Direct | Remove-OERActiveDirectoryRoleAssignment -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OERActiveDirectoryRoleAssignment' }).Count | Should -Be 2
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000003'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'reports NoPrincipal and issues no POST when no principal is supplied' {
        $Err = $null
        Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'NoPrincipal,Remove-OERActiveDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports AmbiguousPrincipal and issues no POST when two friendly principal parameters are supplied' {
        $Err = $null
        Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'a' -Group 'b' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,Remove-OERActiveDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a non-terminating error and returns nothing when the POST fails' {
        # Called directly (not inside a { } | Should -Not -Throw scriptblock, which runs in a child
        # scope and would let $Out silently stay unset in THIS scope even if the assignment worked) so
        # -ErrorVariable is observable and the WriteError call itself is proven, not merely assumed.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Out = Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Out | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OERActiveDirectoryRoleAssignment' }).Count | Should -Be 1
    }

    Context 'a removal Microsoft Graph answers with RoleAssignmentDoesNotExist' {
        # Measured live: Graph answered an adminRemove of an active assignment with
        # RoleAssignmentDoesNotExist although the request is listed Revoked and the assignment is gone.
        # The cmdlet reads the schedule again; only a read that succeeds and finds no direct, standing
        # assignment makes it a success, and a row the principal still holds the role through another
        # way is named in a warning. The POST and the re-read are told apart by -Method.
        BeforeEach {
            $script:ReadBack = @()
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('RoleAssignmentDoesNotExist: The Role assignment does not exist.'),
                    'RoleAssignmentDoesNotExist',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } {
                @{ value = @($script:ReadBack) }
            }
            # One raw schedule as Graph returns it for the role and principal the POST named; by
            # default the direct, standing assignment still in place.
            function script:New-ReadBackRow {
                param([string]$MemberType = 'Direct', [string]$AssignmentType = 'Assigned', [string]$DirectoryScopeId = '/')
                [PSCustomObject]@{
                    id               = 'schedule-1'
                    roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                    principalId      = 'bbbbbbbb-0000-0000-0000-000000000002'
                    directoryScopeId = $DirectoryScopeId
                    memberType       = $MemberType
                    assignmentType   = $AssignmentType
                    status           = 'Provisioned'
                    scheduleInfo     = [PSCustomObject]@{ startDateTime = '2026-01-01T00:00:00Z'; expiration = [PSCustomObject]@{ type = 'noExpiration' } }
                }
            }
            function script:Invoke-RemoveActiveGone {
                $Err = $null
                $Warn = $null
                $All = @(Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
                        -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                [PSCustomObject]@{
                    Output    = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                    Verbose   = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
                    Written   = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OERActiveDirectoryRoleAssignment' })
                    # Every warning except the standing "Removing ..." one the cmdlet writes before the POST.
                    StillHeld = @($Warn | ForEach-Object { [string]$_.Message } | Where-Object { $_ -notlike 'Removing *' })
                }
            }
        }

        It 'counts the removal as done, with a verbose line and no error or warning, when the re-read finds no row at all' {
            $R = Invoke-RemoveActiveGone
            $R.Written.Count | Should -Be 0
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 0
            @($R.Verbose | Where-Object { $_ -like '`[Remove-OERActiveDirectoryRoleAssignment`] Microsoft Graph answered RoleAssignmentDoesNotExist, and reading the active assignment of directory role ''aaaaaaaa-0000-0000-0000-000000000001'' for principal ''bbbbbbbb-0000-0000-0000-000000000002'' again found no direct, standing one at tenant scope, so it is gone*' }).Count |
                Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -ne 'POST' -and $Uri -like 'v1.0/roleManagement/directory/roleAssignmentSchedules?*' -and
                $Uri -like "*roleDefinitionId eq 'aaaaaaaa-0000-0000-0000-000000000001' and principalId eq 'bbbbbbbb-0000-0000-0000-000000000002'"
            }
        }

        It 'counts the removal as done and warns how the principal still holds the role when <Case> is left' -TestCases @(
            @{ Case = 'an activation'; MemberType = 'Direct'; AssignmentType = 'Activated'; Scope = '/'; Ways = 'as an activation of an eligible assignment' }
            @{ Case = 'a row through a group'; MemberType = 'Group'; AssignmentType = 'Assigned'; Scope = '/'; Ways = 'through a group' }
            @{ Case = 'a row scoped to an administrative unit'; MemberType = 'Direct'; AssignmentType = 'Assigned'; Scope = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; Ways = 'at a directory scope narrower than the tenant, such as an administrative unit' }
        ) {
            $script:ReadBack = @(New-ReadBackRow -MemberType $MemberType -AssignmentType $AssignmentType -DirectoryScopeId $Scope)
            $R = Invoke-RemoveActiveGone
            $R.Written.Count | Should -Be 0
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 1
            # The ids are the ones the cmdlet's own "Removing ..." warning already shows, and no other.
            $R.StillHeld[0] | Should -BeExactly ("Removed active directory role 'Reports Reader' for principal 'person1@example.com' at directory scope '/', " +
                "but the principal still holds the role $Ways.")
        }

        It 'keeps the RoleAssignmentDoesNotExist error, and warns nothing more, when the re-read finds the assignment still in place' {
            $script:ReadBack = @((New-ReadBackRow), (New-ReadBackRow -AssignmentType 'Activated'))
            $R = Invoke-RemoveActiveGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment'
            $R.Written[0].Exception.Message | Should -BeExactly 'RoleAssignmentDoesNotExist: The Role assignment does not exist.'
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 0
            @($R.Verbose | Where-Object { $_ -like '*again found it still in place; the error stands.' }).Count | Should -Be 1
        }

        It 'keeps the RoleAssignmentDoesNotExist error, never the read failure, and warns nothing more, when the re-read fails' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } { throw 'Graph 403 Authorization_RequestDenied' }
            $R = Invoke-RemoveActiveGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment'
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 0
            @($R.Verbose | Where-Object { $_ -like '*again failed, so whether it is gone is unknown; the error stands: Graph 403 Authorization_RequestDenied' }).Count | Should -Be 1
        }

        It 'reads nothing again for any other error' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.'),
                    'ActiveDurationTooShort',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $R = Invoke-RemoveActiveGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort,Remove-OERActiveDirectoryRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -ne 'POST' }
        }
    }
}
