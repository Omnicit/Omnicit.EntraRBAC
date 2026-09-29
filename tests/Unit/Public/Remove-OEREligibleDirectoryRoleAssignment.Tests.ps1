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

    It 'binds -Role and -PrincipalId from piped Get-OEREligibleDirectoryRoleAssignment-shaped output' {
        $Piped = [PSCustomObject]@{
            RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'
            PrincipalId      = 'cccccccc-0000-0000-0000-000000000003'
        }
        $Piped.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.EligibleDirectoryRoleAssignment')
        $Piped | Remove-OEREligibleDirectoryRoleAssignment -Confirm:$false -WarningAction SilentlyContinue

        # The role is still resolved through Resolve-OERDirectoryRoleInput even when -Role already
        # arrived as a GUID (Resolve-OERDirectoryRoleDefinitionId itself short-circuits a GUID with no
        # Graph call -- see its own comment-based help); what matters here is that the PIPED value
        # reaches the POST body unchanged, not that resolution is skipped.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Body.roleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
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
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Out = $null
        { $Out = Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } | Should -Not -Throw
        $Out | Should -BeNullOrEmpty
    }
}
