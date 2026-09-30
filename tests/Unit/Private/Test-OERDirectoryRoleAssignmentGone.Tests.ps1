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

    It 'is Gone when the re-read of the <Kind> schedules succeeds and finds none, reading only that role and principal at tenant scope' -TestCases @(
        @{ Kind = 'Active'; Path = 'roleAssignmentSchedules'; KindText = 'active' }
        @{ Kind = 'Eligible'; Path = 'roleEligibilitySchedules'; KindText = 'eligible' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Path = $Path; KindText = $KindText } {
            param($Kind, $Path, $KindText)
            # An upper-case principal id is filtered lower-case, as Graph stores it.
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind $Kind `
                -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal.ToUpperInvariant()
            $Check.Gone | Should -BeTrue
            $Check.Detail | Should -BeExactly ("Microsoft Graph answered RoleAssignmentDoesNotExist, and reading the $KindText assignment of directory role " +
                "'$($script:GoneRole)' for principal '$($script:GonePrincipal.ToUpperInvariant())' again found none, so it is gone and the removal " +
                'is reported as done. (Graph has been measured answering this to a removal it carried out.)')
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq ("v1.0/roleManagement/directory/$Path`?`$filter=directoryScopeId eq '/' and roleDefinitionId eq " +
                    "'$($script:GoneRole)' and principalId eq '$($script:GonePrincipal)'") -and $All -and
                -not $PesterBoundParameters.ContainsKey('Method') -and -not $PesterBoundParameters.ContainsKey('Body')
            }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'is Gone when the only rows left are ones a removal does not stand for (<Case>)' -TestCases @(
        @{ Case = 'an activation'; MemberType = 'Direct'; AssignmentType = 'Activated'; DirectoryScopeId = '/'; Principal = 'bbbbbbbb-0000-0000-0000-000000000002' }
        @{ Case = 'inherited through a group'; MemberType = 'Group'; AssignmentType = 'Assigned'; DirectoryScopeId = '/'; Principal = 'bbbbbbbb-0000-0000-0000-000000000002' }
        @{ Case = 'scoped to an administrative unit'; MemberType = 'Direct'; AssignmentType = 'Assigned'; DirectoryScopeId = '/administrativeUnits/cccccccc-0000-0000-0000-000000000003'; Principal = 'bbbbbbbb-0000-0000-0000-000000000002' }
        @{ Case = 'another principal'; MemberType = 'Direct'; AssignmentType = 'Assigned'; DirectoryScopeId = '/'; Principal = 'bbbbbbbb-0000-0000-0000-000000000009' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ MemberType = $MemberType; AssignmentType = $AssignmentType; DirectoryScopeId = $DirectoryScopeId; Principal = $Principal } {
            param($MemberType, $AssignmentType, $DirectoryScopeId, $Principal)
            $script:GoneLive = @(New-GoneRawRow -Principal $Principal -MemberType $MemberType -AssignmentType $AssignmentType -DirectoryScopeId $DirectoryScopeId)
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind Active -RoleDefinitionId $script:GoneRole -PrincipalId $script:GonePrincipal
            $Check.Gone | Should -BeTrue
        }
    }

    It 'is not Gone when the re-read finds the <Kind> assignment still in place' -TestCases @(
        @{ Kind = 'Active'; KindText = 'active' }
        @{ Kind = 'Eligible'; KindText = 'eligible' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; KindText = $KindText } {
            param($Kind, $KindText)
            $script:GoneLive = @(New-GoneRawRow)
            # Upper case on the way in still matches the lower-case row Graph returns.
            $Check = Test-OERDirectoryRoleAssignmentGone -Record (New-GoneRecord) -Kind $Kind `
                -RoleDefinitionId $script:GoneRole.ToUpperInvariant() -PrincipalId $script:GonePrincipal.ToUpperInvariant()
            $Check.Gone | Should -BeFalse
            $Check.Detail | Should -BeExactly ("Microsoft Graph answered RoleAssignmentDoesNotExist, but reading the $KindText assignment of directory role " +
                "'$($script:GoneRole.ToUpperInvariant())' for principal '$($script:GonePrincipal.ToUpperInvariant())' again found it still in place; the error stands.")
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
