BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
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
}
