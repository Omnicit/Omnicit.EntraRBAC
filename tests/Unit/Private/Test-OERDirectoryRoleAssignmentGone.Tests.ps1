BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Test-OERDirectoryRoleAssignmentGone' {
    # Measured live: Graph answered an adminRemove of an active assignment with
    # RoleAssignmentDoesNotExist although the request is listed Revoked and the assignment is gone.
    # The helper reads the schedule again and says Gone only when that read succeeded and kept no
    # direct, tenant-scope (and for Active, Assigned) row of the role and principal. The wrapper is
    # mocked; ConvertTo-OERDirectoryRoleAssignment and Select-OERManagedDirectoryRoleAssignment run for
    # real. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:GoneRole = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:GonePrincipal = 'bbbbbbbb-0000-0000-0000-000000000002'
            function script:New-GoneRecord {
                param([string]$ErrorId = 'RoleAssignmentDoesNotExist', [string]$Message = 'RoleAssignmentDoesNotExist: The Role assignment does not exist.')
                [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), $ErrorId,
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            }
            # One raw schedule as Graph returns it (no $expand).
            function script:New-GoneRawRow {
                param(
                    [string]$Principal = $script:GonePrincipal,
                    [string]$Role = $script:GoneRole,
                    [string]$MemberType = 'Direct',
                    [string]$AssignmentType = 'Assigned',
                    [string]$DirectoryScopeId = '/'
                )
                [PSCustomObject]@{
                    id               = "schedule-$Principal"
                    roleDefinitionId = $Role
                    principalId      = $Principal
                    directoryScopeId = $DirectoryScopeId
                    memberType       = $MemberType
                    assignmentType   = $AssignmentType
                    status           = 'Provisioned'
                    scheduleInfo     = [PSCustomObject]@{
                        startDateTime = '2026-01-01T00:00:00Z'
                        expiration    = [PSCustomObject]@{ type = 'noExpiration' }
                    }
                }
            }
            $script:GoneLive = @()
            Mock Invoke-OERGraphRequest { @{ value = @($script:GoneLive) } }
        }
    }

    It 'reads nothing and is not Gone for an error that is not RoleAssignmentDoesNotExist' {
        InModuleScope Omnicit.EntraRBAC {
            $Record = New-GoneRecord -ErrorId 'ActiveDurationTooShort' -Message 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.'
            $Check = Test-OERDirectoryRoleAssignmentGone -Record $Record -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeFalse
            $Check.Detail | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'recognizes the code when <Case>' -TestCases @(
        @{ Case = 'only the error id carries it'; ErrorId = 'RoleAssignmentDoesNotExist'; Message = 'The Role assignment does not exist.' }
        @{ Case = 'the written error id carries it'; ErrorId = 'RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment'; Message = 'The Role assignment does not exist.' }
        @{ Case = 'only the message carries it'; ErrorId = 'GraphRequestFailed'; Message = 'RoleAssignmentDoesNotExist: The Role assignment does not exist.' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ ErrorId = $ErrorId; Message = $Message } {
            param($ErrorId, $Message)
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord -ErrorId $ErrorId -Message $Message) -Kind Active `
                -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeTrue
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'is Gone, with nothing still held, when the re-read of the <Kind> schedules succeeds and finds none, in ONE read of that role and principal at every scope' -TestCases @(
        @{ Kind = 'Active'; Path = 'roleAssignmentSchedules'; KindText = 'active'; Kept = 'direct, standing' }
        @{ Kind = 'Eligible'; Path = 'roleEligibilitySchedules'; KindText = 'eligible'; Kept = 'direct' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Path = $Path; KindText = $KindText; Kept = $Kept } {
            param($Kind, $Path, $KindText, $Kept)
            # An upper-case principal id is filtered lower-case, as Graph stores it. The filter names no
            # directory scope, so a schedule at a narrower scope comes back in the same read.
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind $Kind `
                -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal.ToUpperInvariant()
            $Check.Gone | Should -BeTrue
            $Check.StillHeld | Should -BeNullOrEmpty
            $Check.Detail | Should -BeExactly ("Microsoft Graph answered RoleAssignmentDoesNotExist, and reading the $KindText assignment of directory role " +
                "'$($script:GoneRole)' for principal '$($script:GonePrincipal.ToUpperInvariant())' again found no $Kept one at tenant scope, so it is " +
                'gone and the removal is reported as done. (Graph has been measured answering this to a removal it carried out.)')
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq ("v1.0/roleManagement/directory/$Path`?`$filter=roleDefinitionId eq " +
                    "'$($script:GoneRole)' and principalId eq '$($script:GonePrincipal)'") -and $All -and
                -not $PesterBoundParameters.ContainsKey('Method') -and -not $PesterBoundParameters.ContainsKey('Body')
            }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'is Gone, and names how the principal still holds the role, when the only rows left are <Case>' -TestCases @(
        @{ Case = 'an activation'; Kind = 'Active'; MemberType = 'Direct'; AssignmentType = 'Activated'; DirectoryScopeId = '/'; Expected = 'as an activation of an eligible assignment' }
        @{ Case = 'an active assignment through a group'; Kind = 'Active'; MemberType = 'Group'; AssignmentType = 'Assigned'; DirectoryScopeId = '/'; Expected = 'through a group' }
        @{ Case = 'an eligible assignment through a group'; Kind = 'Eligible'; MemberType = 'Group'; AssignmentType = $null; DirectoryScopeId = '/'; Expected = 'through a group' }
        @{ Case = 'scoped to an administrative unit'; Kind = 'Active'; MemberType = 'Direct'; AssignmentType = 'Assigned'; DirectoryScopeId = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; Expected = 'at a directory scope narrower than the tenant, such as an administrative unit' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; MemberType = $MemberType; AssignmentType = $AssignmentType; DirectoryScopeId = $DirectoryScopeId; Expected = $Expected } {
            param($Kind, $MemberType, $AssignmentType, $DirectoryScopeId, $Expected)
            $script:GoneLive = @(New-GoneRawRow -MemberType $MemberType -AssignmentType $AssignmentType -DirectoryScopeId $DirectoryScopeId)
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind $Kind -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeTrue
            $Check.StillHeld | Should -BeExactly $Expected
            $Check.StillHeld | Should -Not -Match '[0-9a-f]{8}-'
        }
    }

    It 'joins every way the principal still holds the role, in a fixed order, and names each once' {
        InModuleScope Omnicit.EntraRBAC {
            $script:GoneLive = @(
                New-GoneRawRow -DirectoryScopeId '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'
                New-GoneRawRow -MemberType 'Group'
                New-GoneRawRow -AssignmentType 'Activated'
                New-GoneRawRow -AssignmentType 'Activated'
            )
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeTrue
            $Check.StillHeld | Should -BeExactly ('as an activation of an eligible assignment, through a group and at a directory scope narrower ' +
                'than the tenant, such as an administrative unit')
            $script:GoneLive = @((New-GoneRawRow -AssignmentType 'Activated'), (New-GoneRawRow -MemberType 'Group'))
            (Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal).StillHeld |
                Should -BeExactly 'as an activation of an eligible assignment and through a group'
        }
    }

    It 'names nothing still held for a row of another principal or another role' {
        InModuleScope Omnicit.EntraRBAC {
            $script:GoneLive = @(
                New-GoneRawRow -Principal 'bbbbbbbb-0000-0000-0000-000000000009' -AssignmentType 'Activated'
                New-GoneRawRow -Role 'aaaaaaaa-0000-0000-0000-000000000009' -MemberType 'Group'
            )
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeTrue
            $Check.StillHeld | Should -BeNullOrEmpty
        }
    }

    It 'is not Gone when the re-read finds the <Kind> assignment still in place' -TestCases @(
        @{ Kind = 'Active'; KindText = 'active' }
        @{ Kind = 'Eligible'; KindText = 'eligible' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; KindText = $KindText } {
            param($Kind, $KindText)
            # The assignment is still in place beside an activation: not Gone, and nothing is named.
            $script:GoneLive = @((New-GoneRawRow), (New-GoneRawRow -AssignmentType 'Activated'))
            # Upper case on the way in still matches the lower-case row Graph returns.
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind $Kind `
                -RoleDefinitionId $script:GoneRole.ToUpperInvariant() -PrincipalId $script:GonePrincipal.ToUpperInvariant()
            $Check.Gone | Should -BeFalse
            $Check.Detail | Should -BeExactly ("Microsoft Graph answered RoleAssignmentDoesNotExist, but reading the $KindText assignment of directory role " +
                "'$($script:GoneRole.ToUpperInvariant())' for principal '$($script:GonePrincipal.ToUpperInvariant())' again found it still in place; the error stands.")
            $Check.StillHeld | Should -BeNullOrEmpty
        }
    }

    It 'is not Gone, and scrubs the record, when the re-read fails' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { throw 'Graph 403 Authorization_RequestDenied' }
            Mock Remove-OERErrorRecord {}
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeFalse
            $Check.Detail | Should -BeExactly ("Microsoft Graph answered RoleAssignmentDoesNotExist, and reading the active assignment of directory role " +
                "'$($script:GoneRole)' for principal '$($script:GonePrincipal)' again failed, so whether it is gone is unknown; the error stands: " +
                'Graph 403 Authorization_RequestDenied')
            $Check.StillHeld | Should -BeNullOrEmpty
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
        }
    }

    It 'is not Gone when the re-read returns no answer at all (<Case>)' -TestCases @(
        @{ Case = 'nothing'; Answer = 'null' }
        @{ Case = 'a hashtable without value'; Answer = 'novalue' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Answer = $Answer } {
            param($Answer)
            if ($Answer -eq 'null') { Mock Invoke-OERGraphRequest { } } else { Mock Invoke-OERGraphRequest { @{ '@odata.context' = 'x' } } }
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Eligible -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeFalse
            $Check.Detail | Should -Match 'returned no answer, so whether it is gone is unknown; the error stands\.$'
        }
    }
}
