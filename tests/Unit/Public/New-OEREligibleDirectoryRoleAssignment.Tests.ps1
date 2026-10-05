BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OEREligibleDirectoryRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { 'aaaaaaaa-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbbbbbb-0000-0000-0000-000000000002'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState { [PSCustomObject]@{ IsGroup = $false; IsAssignableToRole = $false } }
        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { $true }
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
                scheduleInfo     = [PSCustomObject]@{
                    startDateTime = '2026-09-01T00:00:00Z'
                    expiration    = if ($Body.scheduleInfo) { [PSCustomObject]$Body.scheduleInfo.expiration } else { $null }
                }
            }
        }
    }

    It 'POSTs exactly one adminAssign request with the resolved ids, tenant scope, duration and default justification; skips the role-assignable check for a known user' {
        $Out = New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -DurationDays 30 -Confirm:$false

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -and
            $Body.action -eq 'adminAssign' -and
            $Body.roleDefinitionId -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
            $Body.principalId -eq 'bbbbbbbb-0000-0000-0000-000000000002' -and
            $Body.directoryScopeId -eq '/' -and
            $Body.scheduleInfo.expiration.duration -eq 'P30D' -and
            $Body.justification -eq 'Omnicit.EntraRBAC: directory role eligible assignment'
        }
        $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.DirectoryRoleScheduleRequest'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState -Times 0
    }

    It 'checks role-assignability for a -Group and refuses with GroupNotRoleAssignable, issuing no POST, when the group is not role-assignable' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'cccccccc-0000-0000-0000-000000000003'; PrincipalType = 'Group' } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState { [PSCustomObject]@{ IsGroup = $true; IsAssignableToRole = $false } }

        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -Group 'oer-rag' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState -Times 1 -Exactly
        $Err[0].FullyQualifiedErrorId | Should -Be 'GroupNotRoleAssignable,New-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'runs the role-assignable check for a raw -PrincipalId of unknown type and proceeds to POST when it is not a group' {
        $Out = New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -PrincipalId 'dddddddd-0000-0000-0000-000000000004' `
            -DurationDays 30 -Confirm:$false

        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState -Times 1 -Exactly -ParameterFilter {
            $PrincipalId -eq 'dddddddd-0000-0000-0000-000000000004'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        $Out | Should -Not -BeNullOrEmpty
    }

    It 'proceeds to POST, with no GroupNotRoleAssignable record, when the role-assignable check itself throws' {
        # A mocked throw that PowerShell's own try/catch swallows can still leave phantom entries in
        # -ErrorVariable (a Pester-mock/engine interaction, not a defect in the cmdlet under test), so
        # this asserts on the ABSENCE of the cmdlet's own error id and on the POST happening, rather
        # than on -ErrorVariable being empty -- the same style Add-OERGroupEligibility.Tests.ps1 uses
        # for its "degrades and still POSTs when the pre-check read fails" case.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'cccccccc-0000-0000-0000-000000000003'; PrincipalType = 'Group' } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }

        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -Group 'oer-rag' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OER*' }).Count | Should -Be 0
    }

    It 'refuses a permanent request with PermanentAssignmentNotAllowed, naming -AllowPermanentEligibility and directoryRoleManagementPolicies, and issues no write of any kind' {
        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { $false }

        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        $Err[0].FullyQualifiedErrorId | Should -Be 'PermanentAssignmentNotAllowed,New-OEREligibleDirectoryRoleAssignment'
        $Err[0].Exception.Message | Should -Match '-AllowPermanentEligibility'
        # Case-sensitive: proves the lowercase apply-document key text is really present, rather than
        # relying on -Match's case-insensitivity to accept a match against the PascalCase parameter
        # name assertion above.
        $Err[0].Exception.Message | Should -MatchExactly 'allowPermanentEligibility'
        $Err[0].Exception.Message | Should -Match 'directoryRoleManagementPolicies'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Method -in 'POST', 'PATCH', 'PUT', 'DELETE'
        }
        # Pins -Kind so a copy-paste swap between the Eligible and Active cmdlets is caught here.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed -Times 1 -Exactly -ParameterFilter {
            $Kind -eq 'Eligible'
        }
    }

    It 'proceeds to POST with a noExpiration schedule when the permanent pre-check allows it, returns $null, or throws' {
        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { $true }
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'noExpiration'
        }

        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { $null }
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'POST' }

        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'never calls the permanent pre-check for a time-bound request' {
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -DurationDays 30 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed -Times 0
    }

    It 'errors AmbiguousSchedule and issues no Graph call at all when two schedule parameters are supplied' {
        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -DurationDays 5 -Permanent -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousSchedule,New-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId -Times 0
    }

    It 'errors InvalidSchedule and issues no Graph call when -EndDateTime is in the past' {
        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -EndDateTime (Get-Date).AddDays(-1) -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'InvalidSchedule,New-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'sends no POST under -WhatIf, while the permanent pre-check (a read) still runs' {
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -WhatIf | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'sends action adminUpdate in the body when -Action adminUpdate is supplied' {
        New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -DurationDays 30 -Action adminUpdate -Confirm:$false | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.action -eq 'adminUpdate'
        }
    }

    It 'errors AmbiguousPrincipal and issues no POST when -User is bound alongside a piped object carrying its own PrincipalId' {
        $Piped = [PSCustomObject]@{ RoleDefinitionId = 'aaaaaaaa-0000-0000-0000-000000000001'; PrincipalId = 'eeeeeeee-0000-0000-0000-000000000005' }
        $Err = $null
        $Piped | New-OEREligibleDirectoryRoleAssignment -User 'person1@example.com' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousPrincipal,New-OEREligibleDirectoryRoleAssignment'
        $Err[0].Exception.Message | Should -Match 'made eligible'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports RoleDefinitionNotFound and issues no POST when the role does not resolve' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId { $null }
        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Ghost Role' -User 'person1@example.com' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'RoleDefinitionNotFound,New-OEREligibleDirectoryRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'reports AmbiguousRoleName and issues no POST when the role name is ambiguous' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Directory role name 'Dup' matches 2 role definitions (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Err = $null
        New-OEREligibleDirectoryRoleAssignment -Role 'Dup' -User 'person1@example.com' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        # $Err[0] is not necessarily the cmdlet's own WriteError record: a mocked throw that is caught
        # and re-routed by Resolve-OERDirectoryRoleInput can still leave earlier phantom entries in
        # -ErrorVariable, so filter for the cmdlet-qualified id instead of indexing, matching
        # tests/Unit/Public/Get-OERDirectoryRoleManagementPolicy.Tests.ps1.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousRoleName,New-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a non-terminating error and returns nothing when the POST fails' {
        # Called directly (not inside a { } | Should -Not -Throw scriptblock, which runs in a child
        # scope and would let $Out silently stay unset in THIS scope even if the assignment worked) so
        # -ErrorVariable is observable and the WriteError call itself is proven, not merely assumed.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Out = New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'person1@example.com' -DurationDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Out | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
    }
}

Describe 'New-OEREligibleDirectoryRoleAssignment with an ambiguous service principal display name' {
    # End to end through Resolve-OERPrincipalOrId -> Resolve-OERPrincipal -> Resolve-OERApplicationId:
    # only the Graph transport is mocked, so the real resolvers decide. The role is given as an id,
    # which Resolve-OERDirectoryRoleDefinitionId returns without a Graph call. No id below is
    # version-4 shaped.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleAssignableState { [PSCustomObject]@{ IsGroup = $false; IsAssignableToRole = $false } }
        Mock -ModuleName Omnicit.EntraRBAC Test-OERDirectoryRolePermanentAllowed { $true }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' } -MockWith {
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup App' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup App' }) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -MockWith { [PSCustomObject]@{ id = 'req1' } }
    }

    It 'reports exactly one AmbiguousPrincipalName record naming both candidates, and sends no POST' {
        $Err = $null
        $Out = New-OEREligibleDirectoryRoleAssignment -Role 'aaaaaaaa-0000-0000-0000-000000000001' -ServicePrincipal 'Dup App' `
            -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Out | Should -BeNullOrEmpty
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousPrincipalName,New-OEREligibleDirectoryRoleAssignment' })
        $Reported.Count | Should -Be 1
        # No fall-through: the cmdlet writes no other record of its own (PrincipalNotFound included).
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1
        $Reported[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Reported[0].TargetObject | Should -Be 'Dup App'
        $Reported[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }
}
