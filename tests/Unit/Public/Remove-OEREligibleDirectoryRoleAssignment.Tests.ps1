BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Remove-OEREligibleDirectoryRoleAssignment' {
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
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -and
            $Body.action -eq 'adminRemove' -and
            $Body.roleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
            $Body.principalId -eq 'bbbbbbbb-0000-0000-0000-000000000002' -and
            -not $Body.ContainsKey('scheduleInfo')
        }
    }

    It 'declares ConfirmImpact High' {
        $Attr = (Get-Command Remove-OEREligibleDirectoryRoleAssignment).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attr.ConfirmImpact | Should -Be 'High'
    }

    It 'warns before removing and still issues the POST' {
        $Warnings = @()
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'Removing eligible directory role'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'sends no request under -WhatIf' {
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'binds -Role and -PrincipalId from piped Get-OEREligibleDirectoryRoleAssignment-shaped output, with the piped role value flowing through unchanged' {
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
        $Piped.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.EligibleDirectoryRoleAssignment')
        $Piped | Remove-OEREligibleDirectoryRoleAssignment -Confirm:$false -WarningAction SilentlyContinue

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Body.roleDefinitionId -eq 'ffffffff-1111-2222-3333-444444444444' -and
            $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000003'
        }
    }

    It 'reports RoleDefinitionNotFound and issues no POST when the role does not resolve' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        $Err = $null
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Ghost Role' -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'RoleDefinitionNotFound,Remove-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports AmbiguousRoleName and issues no POST when the role name is ambiguous' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Err = $null
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Dup' -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        # $Err[0] is not necessarily the cmdlet's own WriteError record: a mocked throw that is caught
        # and re-routed by Resolve-OERDirectoryRoleInput can still leave earlier phantom entries in
        # -ErrorVariable, so filter for the cmdlet-qualified id instead of indexing, matching
        # tests/Unit/Public/Get-OERDirectoryRoleManagementPolicy.Tests.ps1.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRoleName,Remove-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'errors AmbiguousPrincipal and issues no POST when -User is bound alongside a piped object carrying its own PrincipalId' {
        $Piped = [PSCustomObject]@{ RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; PrincipalId = 'eeeeeeee-0000-0000-0000-000000000005' }
        $Err = $null
        $Piped | Remove-OEREligibleDirectoryRoleAssignment -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,Remove-OEREligibleDirectoryRoleAssignment'
        $Err[0].Exception.Message | Should -Match 'lose its eligible assignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a piped row inherited through a group with NotDirectAssignment, before any Graph call' {
        # The adminRemove request names only the role and the principal, so a piped inherited row
        # (the MEMBER's PrincipalId) would remove that member's own DIRECT eligibility instead.
        $Piped = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'eeeeeeee-0000-0000-0000-000000000005'
            MemberType       = 'Group'
        }
        $Err = $null
        $Piped | Remove-OEREligibleDirectoryRoleAssignment -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Hit = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OEREligibleDirectoryRoleAssignment' })
        $Hit.Count | Should -Be 1
        $Hit[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Hit[0].TargetObject | Should -Be 'eeeeeeee-0000-0000-0000-000000000005'
        $Hit[0].Exception.Message | Should -Match ([regex]::Escape("is inherited through a group (MemberType 'Group')"))
        $Hit[0].Exception.Message | Should -Match ([regex]::Escape("Remove the group's own eligible assignment"))
        # The whole message, unchanged by the group member row wording below.
        $Hit[0].Exception.Message | Should -BeExactly ("The piped eligible assignment of directory role 'aaaaaaaa-0000-0000-0000-000000000001' " +
            "for principal 'eeeeeeee-0000-0000-0000-000000000005' is inherited through a group (MemberType 'Group'), not a " +
            "direct one, so it is not removed: the request names only the role and the principal, and would remove that " +
            "principal's own direct eligible assignment instead, if one exists. Remove the group's own eligible assignment, " +
            'or the principal from the group.')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a piped Get-OERGroupMember row (<Shape>) with NotDirectAssignment saying it is a group member row, before any Graph call' -TestCases @(
        @{ MemberType = 'Member'; Shape = 'tagged Omnicit.EntraRBAC.GroupMember, MemberType Member'; Tagged = $true; Role = 'Reports Reader'; Note = " (MemberType 'Member')"; Example = "'Reports Reader'" }
        @{ MemberType = 'Owner'; Shape = 'untagged, MemberType Owner, told apart by MemberType alone'; Tagged = $false; Role = 'Reports Reader'; Note = " (MemberType 'Owner')"; Example = "'Reports Reader'" }
        @{ MemberType = ''; Shape = 'tagged, no MemberType, told apart by the type name alone, no MemberType parenthesis'; Tagged = $true; Role = 'Reports Reader'; Note = ''; Example = "'Reports Reader'" }
        @{ MemberType = 'Member'; Shape = 'a role name with an apostrophe, doubled in the example'; Tagged = $true; Role = "Contoso's Reader"; Note = " (MemberType 'Member')"; Example = "'Contoso''s Reader'" }
    ) {
        # A Get-OERGroupMember row is no role assignment at all: calling it inherited through a group
        # was wrong, so the message says what it is and how to remove the principal's own direct
        # eligibility on purpose. The refusal, its ErrorId, category and target are unchanged.
        # The guard has two terms, the type name OR a MemberType of Member/Owner; the second and third
        # case each pass through one term alone. The role name stands verbatim in the prose and with
        # any single quote doubled in the example, which therefore stays valid as typed.
        $Row = [PSCustomObject]@{
            PrincipalId = 'cccccccc-0000-0000-0000-000000000003'
            DisplayName = 'Row Principal'
            ObjectType  = 'user'
            MemberType  = $MemberType
            GroupId     = 'dddddddd-0000-0000-0000-000000000004'
        }
        if (-not $MemberType) { $Row.PSObject.Properties.Remove('MemberType') }
        if ($Tagged) { $Row.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupMember') }
        $Err = $null
        $Row | Remove-OEREligibleDirectoryRoleAssignment -Role $Role -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Hit = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OEREligibleDirectoryRoleAssignment' })
        $Hit.Count | Should -Be 1
        $Hit[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Hit[0].TargetObject | Should -Be 'cccccccc-0000-0000-0000-000000000003'
        $Hit[0].Exception.Message | Should -BeExactly ("The piped object for principal 'cccccccc-0000-0000-0000-000000000003' is a " +
            "group member row$Note from Get-OERGroupMember, not an eligible assignment of directory role " +
            "'$Role', so nothing is removed: the request names only the role and the principal, and would remove " +
            "that principal's own direct eligible assignment, if one exists. To remove that assignment on purpose, name the " +
            "principal with -PrincipalId, for example: ... | ForEach-Object { Remove-OEREligibleDirectoryRoleAssignment -Role " +
            "$Example -PrincipalId `$_.PrincipalId }")
        $Hit[0].Exception.Message | Should -Not -Match 'inherited through a group'
        $Hit[0].Exception.Message | Should -Not -Match ([regex]::Escape("(MemberType '')"))
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a group member row example that parses and gives the role name back for a name holding <Label> (BL-100)' -ForEach @(
        @{ Label = 'a straight apostrophe (U+0027)'; RoleName = "Reader's role" }
        @{ Label = 'a right single quotation mark (U+2019)'; RoleName = ('Reader' + [char]0x2019 + 's role') }
        @{ Label = 'a left single quotation mark (U+2018)'; RoleName = ('Reader' + [char]0x2018 + 's role') }
        @{ Label = 'a single low-9 quotation mark (U+201A)'; RoleName = ('Reader' + [char]0x201A + 's role') }
        @{ Label = 'a single high-reversed-9 quotation mark (U+201B)'; RoleName = ('Reader' + [char]0x201B + 's role') }
    ) {
        # PowerShell's tokenizer reads U+2018, U+2019, U+201A and U+201B as single quotes, like U+0027, so an
        # example that doubled only the straight one ended the string early for a curly apostrophe and did
        # not parse. Zero parse errors is not enough on its own -- an unbalanced string can parse into the
        # wrong tokens -- so the -Role argument must also come back exactly as the role name was typed.
        $Row = [PSCustomObject]@{
            PrincipalId = 'cccccccc-0000-0000-0000-000000000003'
            DisplayName = 'Row Principal'
            ObjectType  = 'user'
            MemberType  = 'Member'
            GroupId     = 'dddddddd-0000-0000-0000-000000000004'
        }
        $Row.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupMember')
        $Err = $null
        $Row | Remove-OEREligibleDirectoryRoleAssignment -Role $RoleName -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Hit = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OEREligibleDirectoryRoleAssignment' })
        $Hit.Count | Should -Be 1
        $Marker = 'for example: '
        $At = $Hit[0].Exception.Message.IndexOf($Marker)
        $At | Should -BeGreaterThan -1
        $Example = $Hit[0].Exception.Message.Substring($At + $Marker.Length)
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Example, [ref]$null, [ref]$Errors)
        @($Errors).Count | Should -Be 0
        $Command = $Ast.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Remove-OEREligibleDirectoryRoleAssignment'
            }, $true)
        $Command | Should -Not -BeNullOrEmpty
        $Elements = @($Command.CommandElements)
        $RoleAt = -1
        for ($I = 0; $I -lt $Elements.Count; $I++) {
            if ($Elements[$I] -is [System.Management.Automation.Language.CommandParameterAst] -and $Elements[$I].ParameterName -eq 'Role') { $RoleAt = $I }
        }
        $RoleAt | Should -BeGreaterThan -1
        $Argument = $Elements[$RoleAt + 1]
        $Argument | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
        $Argument.Value | Should -BeExactly $RoleName
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'removes a piped Direct row, and only that one when it is piped together with an inherited row' {
        $Inherited = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'eeeeeeee-0000-0000-0000-000000000005'
            MemberType       = 'Group'
        }
        $Direct = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'cccccccc-0000-0000-0000-000000000003'
            MemberType       = 'Direct'
        }
        $Err = $null
        $Inherited, $Direct | Remove-OEREligibleDirectoryRoleAssignment -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NotDirectAssignment,Remove-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000003'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'reports NoPrincipal and issues no POST when no principal is supplied' {
        $Err = $null
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'NoPrincipal,Remove-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports AmbiguousPrincipal and issues no POST when two friendly principal parameters are supplied' {
        $Err = $null
        Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'a' -Group 'b' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,Remove-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a non-terminating error and returns nothing when the POST fails' {
        # Called directly (not inside a { } | Should -Not -Throw scriptblock, which runs in a child
        # scope and would let $Out silently stay unset in THIS scope even if the assignment worked) so
        # -ErrorVariable is observable and the WriteError call itself is proven, not merely assumed.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Out = Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Out | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
    }

    Context 'a removal Microsoft Graph accepts but answers with a status in the Failed family (BL-33)' {
        # Microsoft Graph can accept the adminRemove request and answer it with status Failed, which
        # removes nothing. The cmdlet still emits the request object, then writes
        # EligibilityRequestFailed, so a caller never takes the Failed request for a removal.
        BeforeEach {
            $script:AnsweredStatus = 'Failed'
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Method, $Uri, $Body)
                [PSCustomObject]@{
                    id               = 'req-rf'
                    action           = $Body.action
                    status           = $script:AnsweredStatus
                    roleDefinitionId = $Body.roleDefinitionId
                    principalId      = $Body.principalId
                    directoryScopeId = $Body.directoryScopeId
                    createdDateTime  = '2026-09-01T00:00:00Z'
                    scheduleInfo     = $null
                }
            }
        }

        It 'emits the request object AND writes exactly one EligibilityRequestFailed when Graph answers status <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'FAILED' }
        ) {
            $script:AnsweredStatus = $Status
            $Err = $null
            $Out = @(Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 1
            $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.DirectoryRoleScheduleRequest'
            $Out[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Remove-OEREligibleDirectoryRoleAssignment'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Err[0].TargetObject | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
            $Err[0].Exception.Message | Should -BeExactly ("Microsoft Graph accepted the eligible directory role assignment removal request " +
                "'req-rf' (adminRemove) of role 'aaaaaaaa-0000-0000-0000-000000000001' for principal " +
                "'bbbbbbbb-0000-0000-0000-000000000002' at directory scope '/' but answered status $Status, so nothing was " +
                'removed: the eligible assignment is still in place.')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }

        It 'still hands the object to -OutVariable under -ErrorAction Stop, and the throw carries EligibilityRequestFailed' {
            $Out = $null
            $Thrown = $null
            try {
                Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction Stop -OutVariable Out | Out-Null
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Remove-OEREligibleDirectoryRoleAssignment'
            @($Out).Count | Should -Be 1
            $Out[0].ScheduleRequestId | Should -BeExactly 'req-rf'
            $Out[0].Status | Should -BeExactly 'Failed'
        }

        It 'writes no error for status Revoked, a removal that succeeded, and still emits the object' {
            $script:AnsweredStatus = 'Revoked'
            $Err = $null
            $Out = @(Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The request was sent and answered Revoked, so the absence below is a decision.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            $Out.Count | Should -Be 1
            $Out[0].Status | Should -BeExactly 'Revoked'
            @($Err).Count | Should -Be 0
        }
    }

    Context 'a removal Microsoft Graph answers with RoleAssignmentDoesNotExist' {
        # The same rule as the active twin, measured live there: only a re-read that succeeds and
        # finds no direct eligibility makes the answer a success, and an eligibility the principal
        # still holds another way is named in a warning. The POST and the re-read are told apart by
        # -Method.
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
            # default the direct eligibility still in place.
            function script:New-ReadBackRow {
                param([string]$MemberType = 'Direct', [string]$DirectoryScopeId = '/')
                [PSCustomObject]@{
                    id               = 'schedule-1'
                    roleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
                    principalId      = 'bbbbbbbb-0000-0000-0000-000000000002'
                    directoryScopeId = $DirectoryScopeId
                    memberType       = $MemberType
                    status           = 'Provisioned'
                    scheduleInfo     = [PSCustomObject]@{ startDateTime = '2026-01-01T00:00:00Z'; expiration = [PSCustomObject]@{ type = 'noExpiration' } }
                }
            }
            function script:Invoke-RemoveEligibleGone {
                $Err = $null
                $Warn = $null
                $All = @(Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
                        -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                [PSCustomObject]@{
                    Output    = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                    Verbose   = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
                    Written   = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OEREligibleDirectoryRoleAssignment' })
                    # Every warning except the standing "Removing ..." one the cmdlet writes before the POST.
                    StillHeld = @($Warn | ForEach-Object { [string]$_.Message } | Where-Object { $_ -notlike 'Removing *' })
                }
            }
        }

        It 'counts the removal as done, with a verbose line and no error or warning, when the re-read finds no row at all' {
            $R = Invoke-RemoveEligibleGone
            $R.Written.Count | Should -Be 0
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 0
            @($R.Verbose | Where-Object { $_ -like '`[Remove-OEREligibleDirectoryRoleAssignment`] Microsoft Graph answered RoleAssignmentDoesNotExist, and reading the eligible assignment of directory role ''aaaaaaaa-0000-0000-0000-000000000001'' for principal ''bbbbbbbb-0000-0000-0000-000000000002'' again found no direct one at tenant scope, so it is gone*' }).Count |
                Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -ne 'POST' -and $Uri -like 'v1.0/roleManagement/directory/roleEligibilitySchedules?*' -and
                $Uri -like "*roleDefinitionId eq 'aaaaaaaa-0000-0000-0000-000000000001' and principalId eq 'bbbbbbbb-0000-0000-0000-000000000002'"
            }
        }

        It 'counts the removal as done and warns how the principal still holds the role when <Case> is left' -TestCases @(
            @{ Case = 'a row through a group'; MemberType = 'Group'; Scope = '/'; Ways = 'through a group' }
            @{ Case = 'a row scoped to an administrative unit'; MemberType = 'Direct'; Scope = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; Ways = 'at a directory scope narrower than the tenant, such as an administrative unit' }
        ) {
            $script:ReadBack = @(New-ReadBackRow -MemberType $MemberType -DirectoryScopeId $Scope)
            $R = Invoke-RemoveEligibleGone
            $R.Written.Count | Should -Be 0
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 1
            # The ids are the ones the cmdlet's own "Removing ..." warning already shows, and no other.
            $R.StillHeld[0] | Should -BeExactly ("Removed eligible directory role 'Reports Reader' for principal 'person1@example.com' at directory scope '/', " +
                "but the principal still holds the role $Ways.")
        }

        It 'keeps the RoleAssignmentDoesNotExist error, and warns nothing more, when the re-read finds the eligibility still in place' {
            $script:ReadBack = @((New-ReadBackRow), (New-ReadBackRow -MemberType 'Group'))
            $R = Invoke-RemoveEligibleGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentDoesNotExist,Remove-OEREligibleDirectoryRoleAssignment'
            $R.Written[0].Exception.Message | Should -BeExactly 'RoleAssignmentDoesNotExist: The Role assignment does not exist.'
            $R.Output | Should -BeNullOrEmpty
            $R.StillHeld.Count | Should -Be 0
            @($R.Verbose | Where-Object { $_ -like '*again found it still in place; the error stands.' }).Count | Should -Be 1
        }

        It 'keeps the RoleAssignmentDoesNotExist error, never the read failure, and warns nothing more, when the re-read fails' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } { throw 'Graph 403 Authorization_RequestDenied' }
            $R = Invoke-RemoveEligibleGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentDoesNotExist,Remove-OEREligibleDirectoryRoleAssignment'
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
            $R = Invoke-RemoveEligibleGone
            $R.Written.Count | Should -Be 1
            $R.Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort,Remove-OEREligibleDirectoryRoleAssignment'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -ne 'POST' }
        }
    }
}
