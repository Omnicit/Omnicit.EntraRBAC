BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment' {
    # Every It drives the handler through a wrapper function that carries SupportsShouldProcess, so
    # the handler's -Caller is a real PSCmdlet: -WhatIf on the wrapper makes Caller.ShouldProcess
    # decline, and -ErrorAction on the wrapper observes Caller.WriteError. The role and principal
    # resolvers and the four cmdlets are mocked; Select-OERManagedDirectoryRoleAssignment and
    # Resolve-OERDirectoryRoleAssignmentChange run for real, since which live row may stand for a
    # declared entry is exactly what these tests pin. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncDraViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            # One projected schedule row, the shape ConvertTo-OERDirectoryRoleAssignment emits. The
            # default window is 30 days from a fixed start, so the diff never depends on the clock.
            function script:New-DraLiveRow {
                param(
                    [string]$Kind = 'Eligible',
                    [string]$AssignmentType = 'Assigned',
                    [string]$MemberType = 'Direct',
                    [object]$Start = '2026-01-01T00:00:00Z',
                    [object]$End = '2026-01-31T00:00:00Z'
                )
                $Row = [ordered]@{
                    ScheduleId       = 'schedule-0001'
                    RoleDefinitionId = '11111111-1111-1111-1111-111111111111'
                    RoleName         = 'Reports Reader'
                    PrincipalId      = 'aaaaaaaa-0000-0000-0000-000000000001'
                    DirectoryScopeId = '/'
                    MemberType       = $MemberType
                }
                if ($Kind -eq 'Active') { $Row.AssignmentType = $AssignmentType }
                $Row.StartDateTime = $Start
                $Row.EndDateTime = $End
                [PSCustomObject]$Row
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId { '11111111-1111-1111-1111-111111111111' }
            Mock Resolve-OERStructurePrincipal { 'aaaaaaaa-0000-0000-0000-000000000001' }
            Mock Get-OEREligibleDirectoryRoleAssignment {}
            Mock Get-OERActiveDirectoryRoleAssignment {}
            Mock New-OEREligibleDirectoryRoleAssignment {}
            Mock New-OERActiveDirectoryRoleAssignment {}
        }
    }

    It 'creates an absent eligible assignment with adminAssign and the declared window, reading only the eligible schedules' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Created')
            $Records[0].Section | Should -BeExactly 'directoryRoleAssignments'
            $Records[0].Item | Should -BeExactly 'Reports Reader -> person1@example.com (Eligible)'
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq '11111111-1111-1111-1111-111111111111' -and $PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001'
            }
            Should -Invoke Get-OERActiveDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq '11111111-1111-1111-1111-111111111111' -and
                $PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
                $DurationDays -eq 30 -and
                $Action -eq 'adminAssign' -and
                $PesterBoundParameters.ContainsKey('Confirm') -and -not [bool]$PesterBoundParameters['Confirm'] -and
                -not $PesterBoundParameters.ContainsKey('Permanent')
            }
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'is Unchanged and writes nothing when the live window equals the declared one' {
        InModuleScope $script:moduleName {
            Mock Get-OEREligibleDirectoryRoleAssignment { New-DraLiveRow }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Unchanged')
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 're-issues a changed window with adminUpdate and reports Updated' {
        InModuleScope $script:moduleName {
            Mock Get-OEREligibleDirectoryRoleAssignment { New-DraLiveRow }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 60 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Updated')
            $Records[0].Detail | Should -Match 'live 30 days, declared 60 days'
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Action -eq 'adminUpdate' -and $DurationDays -eq 60
            }
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'requests a permanent assignment, with -Permanent and no -DurationDays, when the entry is <Case>' -TestCases @(
        @{ Case = 'declared permanent true'; Json = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Active", "permanent": true }' }
        @{ Case = 'silent on both durationDays and permanent'; Json = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Active" }' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Json = $Json } {
            param($Json)
            $Item = $Json | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Created')
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                [bool]$Permanent -and -not $PesterBoundParameters.ContainsKey('DurationDays') -and $Action -eq 'adminAssign'
            }
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'never takes an activation for a declared active assignment: it creates the assignment instead of reporting Unchanged' {
        # The principal's only live Active row is an ACTIVATION (AssignmentType Activated) of an
        # eligible assignment, eight hours long. Its window would read as one day and match the
        # declared durationDays 1 exactly, so without the Activated guard in
        # Select-OERManagedDirectoryRoleAssignment this entry would be reported Unchanged and the
        # standing active assignment the document declares would never be created.
        InModuleScope $script:moduleName {
            $script:DraActivationStart = [datetimeoffset]::UtcNow
            Mock Get-OERActiveDirectoryRoleAssignment {
                New-DraLiveRow -Kind Active -AssignmentType 'Activated' `
                    -Start $script:DraActivationStart.ToString('o') -End $script:DraActivationStart.AddHours(8).ToString('o')
            }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Active", "durationDays": 1 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Created')
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Action -eq 'adminAssign' -and $DurationDays -eq 1
            }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'never takes an assignment held through a group for a direct one: it creates the direct assignment' {
        InModuleScope $script:moduleName {
            Mock Get-OEREligibleDirectoryRoleAssignment { New-DraLiveRow -MemberType 'Group' }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Created')
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter { $Action -eq 'adminAssign' }
        }
    }

    It 'never takes a live row of another principal or another role for the declared entry' {
        # The read is already filtered by role and principal; the handler checks both again on the
        # rows it gets back, so a read that returns more than it was asked for cannot satisfy the entry.
        InModuleScope $script:moduleName {
            Mock Get-OEREligibleDirectoryRoleAssignment {
                $OtherPrincipal = New-DraLiveRow
                $OtherPrincipal.PrincipalId = 'aaaaaaaa-0000-0000-0000-000000000099'
                $OtherRole = New-DraLiveRow
                $OtherRole.RoleDefinitionId = '22222222-2222-2222-2222-222222222222'
                $OtherPrincipal
                $OtherRole
            }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Created')
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter { $Action -eq 'adminAssign' }
        }
    }

    It 'reports Skipped, naming the plan, and writes nothing when the caller declines ShouldProcess' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -WhatIf)
            @($Records).Action | Should -Be @('Skipped')
            $Records[0].Detail | Should -BeLike 'would create the eligible assignment*'
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            # Reads still run under -WhatIf, so the plan is built from the live state.
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'reports Failed and reads nothing when the role resolves to nothing' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERDirectoryRoleDefinitionId { $null }
            $Item = '{ "role": "No Such Role", "principal": "person1@example.com", "assignmentType": "Eligible" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match "role 'No Such Role' could not be resolved to a role definition id"
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'reports Failed, scrubs and publishes the error when the role lookup throws' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERDirectoryRoleDefinitionId { throw "Directory role name 'Reports Reader' is ambiguous." }
            Mock Remove-OERErrorRecord {}
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'could not resolve directory role'
            $Records[0].Detail | Should -Match 'ambiguous'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            # Published through Caller.WriteError: under -ErrorAction Stop that write is what throws.
            { Invoke-SyncDraViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*ambiguous*'
        }
    }

    It 'reports Failed and reads nothing when the principal resolves to nothing' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERStructurePrincipal { $null }
            $Item = '{ "role": "Reports Reader", "principal": "nobody@example.com", "assignmentType": "Eligible" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match "principal 'nobody@example.com' could not be resolved"
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'reports Failed, scrubs and publishes the error, and reads and writes nothing when the principal lookup throws' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERStructurePrincipal { throw "Principal 'person1@example.com' is ambiguous." }
            Mock Remove-OERErrorRecord {}
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Item | Should -BeExactly 'Reports Reader -> person1@example.com (Eligible)'
            $Records[0].Detail | Should -Match "could not resolve principal 'person1@example.com'"
            $Records[0].Detail | Should -Match 'ambiguous'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            # Published through Caller.WriteError. -ErrorVariable also collects the exception every
            # Pester mock layer re-throws on its way to the handler's catch, so count only the records
            # the wrapper itself wrote (their FullyQualifiedErrorId ends with its name).
            $CallerErrors = @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraViaCaller' })
            @($CallerErrors).Count | Should -Be 1
            "$($CallerErrors[0])" | Should -Match 'ambiguous'
            { Invoke-SyncDraViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*ambiguous*'
        }
    }

    It 'reports Failed and resolves, reads and writes nothing when assignmentType is neither Eligible nor Active' {
        # Only reachable by calling the handler directly (the engine validates first), but an
        # out-of-enum kind must not fall through to a read of the wrong kind or a parameter error.
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Permanent" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Item | Should -BeExactly 'Reports Reader -> person1@example.com (Permanent)'
            $Records[0].Detail | Should -Match "assignmentType 'Permanent' is not Eligible or Active"
            Should -Invoke Resolve-OERDirectoryRoleDefinitionId -Times 0
            Should -Invoke Resolve-OERStructurePrincipal -Times 0
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Get-OERActiveDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'reports Failed, never Created, when the <Kind> live read throws' -TestCases @(
        @{ Kind = 'Eligible'; GetName = 'Get-OEREligibleDirectoryRoleAssignment'; NewName = 'New-OEREligibleDirectoryRoleAssignment' }
        @{ Kind = 'Active'; GetName = 'Get-OERActiveDirectoryRoleAssignment'; NewName = 'New-OERActiveDirectoryRoleAssignment' }
    ) {
        # A failed read is not an absent assignment: creating here would re-issue a live assignment.
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; GetName = $GetName; NewName = $NewName } {
            param($Kind, $GetName, $NewName)
            Mock $GetName { throw 'Graph 403 Forbidden' }
            Mock Remove-OERErrorRecord {}
            $Item = "{ `"role`": `"Reports Reader`", `"principal`": `"person1@example.com`", `"assignmentType`": `"$Kind`", `"durationDays`": 30 }" | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match "could not read the $($Kind.ToLowerInvariant()) assignments"
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            Should -Invoke $GetName -Times 1 -Exactly
            Should -Invoke $NewName -Times 0
            { Invoke-SyncDraViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*Graph 403 Forbidden*'
        }
    }

    It 'reports Failed, never Created, when the <Kind> live read writes a non-terminating error and returns nothing' -TestCases @(
        @{ Kind = 'Eligible'; GetName = 'Get-OEREligibleDirectoryRoleAssignment'; NewName = 'New-OEREligibleDirectoryRoleAssignment' }
        @{ Kind = 'Active'; GetName = 'Get-OERActiveDirectoryRoleAssignment'; NewName = 'New-OERActiveDirectoryRoleAssignment' }
    ) {
        # The real Get cmdlets report a refused read as a NON-terminating error and return nothing.
        # Only -ErrorAction Stop on the read turns that into the handler's catch; without it the
        # read looks empty and the entry would be Created on top of whatever is really there.
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; GetName = $GetName; NewName = $NewName } {
            param($Kind, $GetName, $NewName)
            Mock $GetName {
                Write-Error -Message 'Could not read the directory role assignments: Forbidden.' -ErrorId 'GraphRequestFailed' -Category PermissionDenied
            }
            $Item = "{ `"role`": `"Reports Reader`", `"principal`": `"person1@example.com`", `"assignmentType`": `"$Kind`", `"durationDays`": 30 }" | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'Forbidden'
            Should -Invoke $NewName -Times 0
        }
    }

    It 'reports Failed with the message, and scrubs and publishes the error, when the write throws' {
        InModuleScope $script:moduleName {
            Mock New-OEREligibleDirectoryRoleAssignment { throw 'Graph 400 RoleAssignmentRequestPolicyValidationFailed' }
            Mock Remove-OERErrorRecord {}
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'failed to create the eligible assignment'
            $Records[0].Detail | Should -Match 'RoleAssignmentRequestPolicyValidationFailed'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            { Invoke-SyncDraViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*RoleAssignmentRequestPolicyValidationFailed*'
        }
    }

    It 'names the cause and the way out when Graph refuses a <Kind> window update with ActiveDurationTooShort (<Case>)' -TestCases @(
        @{ Kind = 'Eligible'; Case = 'only the error id carries the code'; ErrorId = 'ActiveDurationTooShort'; Message = 'The Active duration is too short. Miniumum Required is 5 minutes.' }
        @{ Kind = 'Eligible'; Case = 'only the message carries the code'; ErrorId = 'GraphRequestFailed'; Message = 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.' }
        @{ Kind = 'Active'; Case = 'only the error id carries the code'; ErrorId = 'ActiveDurationTooShort'; Message = 'The Active duration is too short. Miniumum Required is 5 minutes.' }
    ) {
        # Measured live (step 4, check 3.3 and its follow-up): Graph refuses to update or remove a
        # principal's assignments of a role until the principal's active assignment of that role has run
        # for five minutes. The row must say so, and the handler must leave the assignment alone: no
        # removal, no second request.
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; ErrorId = $ErrorId; Message = $Message } {
            param($Kind, $ErrorId, $Message)
            $GetName = "Get-OER$($Kind)DirectoryRoleAssignment"
            $NewName = "New-OER$($Kind)DirectoryRoleAssignment"
            $RemoveName = "Remove-OER$($Kind)DirectoryRoleAssignment"
            Mock $GetName -MockWith ([scriptblock]::Create("New-DraLiveRow -Kind $Kind"))
            Mock $NewName -MockWith ([scriptblock]::Create("Write-Error -Message '$Message' -ErrorId '$ErrorId' -Category InvalidOperation"))
            Mock $RemoveName {}
            $Item = "{ `"role`": `"Reports Reader`", `"principal`": `"person1@example.com`", `"assignmentType`": `"$Kind`", `"durationDays`": 7 }" | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -BeExactly ("failed to update the $($Kind.ToLowerInvariant()) assignment: Microsoft Graph does not change or remove a principal's " +
                "assignments of a role until the principal's active assignment of that role has run for five minutes " +
                '(ActiveDurationTooShort), so nothing was changed; apply the document again in five minutes (the apply ' +
                'engine never removes an assignment to re-create it)')
            Should -Invoke $NewName -Times 1 -Exactly -ParameterFilter { $Action -eq 'adminUpdate' }
            Should -Invoke $NewName -Times 1 -Exactly
            Should -Invoke $RemoveName -Times 0
        }
    }

    It 'keeps the plain Detail for ActiveDurationTooShort on a <Kind> create' -TestCases @(
        @{ Kind = 'Eligible' }
        @{ Kind = 'Active' }
    ) {
        # A create is never refused this way (measured); the special wording is for updates and removals.
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind } {
            param($Kind)
            Mock "New-OER$($Kind)DirectoryRoleAssignment" { Write-Error -Message 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.' -ErrorId 'ActiveDurationTooShort' -Category InvalidOperation }
            $Item = "{ `"role`": `"Reports Reader`", `"principal`": `"person1@example.com`", `"assignmentType`": `"$Kind`", `"durationDays`": 7 }" | ConvertFrom-Json
            $Records = @(Invoke-SyncDraViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -BeExactly "failed to create the $($Kind.ToLowerInvariant()) assignment: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes."
        }
    }
    It 'sends a declared justification as -Justification' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30, "justification": "Quarterly reporting" }' | ConvertFrom-Json
            $null = Invoke-SyncDraViaCaller -Item $Item
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter { $Justification -ceq 'Quarterly reporting' }
        }
    }

    It 'binds no -Justification when the entry <Case>' -TestCases @(
        @{ Case = 'omits justification'; Json = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' }
        @{ Case = 'declares justification as an explicit null'; Json = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30, "justification": null }' }
    ) {
        # Without a bound -Justification the cmdlet sends its own standard one, which a directory role
        # policy that requires justification on admin assignment accepts.
        InModuleScope $script:moduleName -Parameters @{ Json = $Json } {
            param($Json)
            $null = Invoke-SyncDraViaCaller -Item ($Json | ConvertFrom-Json)
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('Justification') }
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'forwards a declared principalType to the principal resolver as -Type' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "Reporting App", "principalType": "ServicePrincipal", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $null = Invoke-SyncDraViaCaller -Item $Item
            Should -Invoke Resolve-OERStructurePrincipal -Times 1 -Exactly -ParameterFilter {
                $Reference -ceq 'Reporting App' -and $Type -ceq 'ServicePrincipal'
            }
            Should -Invoke Resolve-OERStructurePrincipal -Times 1 -Exactly
        }
    }

    It 'binds no -Type on the principal resolver when principalType is not declared' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $null = Invoke-SyncDraViaCaller -Item $Item
            Should -Invoke Resolve-OERStructurePrincipal -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('Type') }
        }
    }

    It 'converges: the same entry applied a second time is only Unchanged' {
        InModuleScope $script:moduleName {
            $script:LiveDra = $null
            Mock Get-OEREligibleDirectoryRoleAssignment { $script:LiveDra }
            Mock New-OEREligibleDirectoryRoleAssignment {
                $Now = [datetimeoffset]::UtcNow
                $script:LiveDra = New-DraLiveRow -Start $Now.ToString('o') -End $Now.AddDays($DurationDays).ToString('o')
            }
            $Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 30 }' | ConvertFrom-Json
            $First = @(Invoke-SyncDraViaCaller -Item $Item)
            $Second = @(Invoke-SyncDraViaCaller -Item $Item)
            @($First).Action | Should -Be @('Created')
            @($Second).Action | Should -Be @('Unchanged')
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment section-wide prune pass' {
    # The pass runs in the invocation that carries -ReconcileSection (the engine sets it on the
    # section's first item only). It reads the live assignments of every (role, assignmentType) pair
    # the section declares and reports each undeclared direct, tenant-scope one Extra, or removes it
    # under -Prune, unless a guard withholds it. The resolvers map document values to fixed ids (role
    # RR and MCR, personN@example.com -> principal N); the Get mocks return the live rows of the role
    # they are asked for, and of the principal when the per-item part names one, so a test places a
    # row on a role by its RoleDefinitionId. Select-OERManagedDirectoryRoleAssignment,
    # ConvertTo-OERPruneWithheldResult and Resolve-OERDirectoryRoleAssignmentChange run for real.
    # No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:RR = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:MCR = 'aaaaaaaa-0000-0000-0000-000000000002'
            $script:DraP = @{}
            foreach ($N in 1..9) { $script:DraP[$N] = "bbbbbbbb-0000-0000-0000-00000000000$N" }
            $script:DraLiveEligible = @()
            $script:DraLiveActive = @()
            function script:Invoke-SyncDraSection {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [object[]]$DeclaredInSection = @(), [switch]$ReconcileSection, [switch]$Prune)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune `
                    -DeclaredInSection $DeclaredInSection -ReconcileSection:$ReconcileSection
            }
            # One projected schedule row, the shape ConvertTo-OERDirectoryRoleAssignment emits. It is
            # permanent, so a permanent declared entry for the same role and principal is Unchanged.
            function script:New-DraPassRow {
                param(
                    [string]$Role,
                    [string]$Principal,
                    [string]$Kind = 'Eligible',
                    [string]$AssignmentType = 'Assigned',
                    [string]$MemberType = 'Direct',
                    [string]$DirectoryScopeId = '/',
                    [string]$PrincipalType = 'User'
                )
                $Row = [ordered]@{
                    ScheduleId       = "schedule-$Principal"
                    RoleDefinitionId = $Role
                    RoleName         = $(if ($Role -eq $script:RR) { 'Reports Reader' } elseif ($Role -eq $script:MCR) { 'Message Center Reader' } else { '' })
                    PrincipalId      = $Principal
                    PrincipalType    = $PrincipalType
                    DirectoryScopeId = $DirectoryScopeId
                    MemberType       = $MemberType
                }
                if ($Kind -eq 'Active') { $Row.AssignmentType = $AssignmentType }
                $Row.StartDateTime = '2026-01-01T00:00:00Z'
                $Row.EndDateTime = $null
                [PSCustomObject]$Row
            }
            # The errors the wrapper itself wrote, i.e. what Caller.WriteError published. -ErrorVariable
            # also collects the exception every Pester mock layer re-throws on its way to a catch in
            # the handler, so a raw count would include errors the handler caught and never wrote.
            function script:Select-DraCallerError {
                param([object[]]$ErrorList)
                @($ErrorList | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraSection' })
            }
            # The section's entries from 'role|principal|assignmentType' strings, as ConvertFrom-Json
            # would produce them; the first entry is the item the handler is invoked for.
            function script:New-DraSection {
                param([string[]]$Entry)
                foreach ($E in $Entry) {
                    $Role, $Principal, $Kind = $E -split '\|'
                    [PSCustomObject]@{ role = $Role; principal = $Principal; assignmentType = $Kind }
                }
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId {
                if ($Role -eq 'Reports Reader') { return $script:RR }
                if ($Role -eq 'Message Center Reader') { return $script:MCR }
                if ($Role -eq 'Throwing Role') { throw "Directory role name 'Throwing Role' is ambiguous." }
                if (Test-OERGuid -Value $Role) { return $Role.ToLowerInvariant() }
                return $null
            }
            Mock Resolve-OERStructurePrincipal {
                # A GUID reference comes back verbatim, letter case included, as the real resolver
                # returns it; Graph reports principalId lower-case.
                if (Test-OERGuid -Value $Reference) { return $Reference }
                if ($Reference -match '^person(\d)@example\.com$') { return $script:DraP[[int]$Matches[1]] }
                if ($Reference -eq 'throws@example.com') { throw "Principal 'throws@example.com' is ambiguous." }
                return $null
            }
            Mock Get-OEREligibleDirectoryRoleAssignment {
                @($script:DraLiveEligible | Where-Object { $_.RoleDefinitionId -eq $Role -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId) })
            }
            Mock Get-OERActiveDirectoryRoleAssignment {
                @($script:DraLiveActive | Where-Object { $_.RoleDefinitionId -eq $Role -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId) })
            }
            Mock Remove-OEREligibleDirectoryRoleAssignment {}
            Mock Remove-OERActiveDirectoryRoleAssignment {}
            Mock New-OEREligibleDirectoryRoleAssignment {}
            Mock New-OERActiveDirectoryRoleAssignment {}
            Mock Get-OERSignedInObjectId { 'aaaaaaaa-0000-0000-0000-0000000000ff' }
            # The group guard's membership read. Only a Group or unknown-type candidate reaches it, so a
            # test that does not override this never reads it; one that reads it by accident sees its
            # candidates withheld and an error written instead of a silent pass.
            Mock Get-OERMemberGroupId { throw 'unexpected membership read' }
        }
    }

    It 'reports an undeclared direct assignment in a declared pair Extra without -Prune, and removes nothing' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection)
            @($Records).Action | Should -Be @('Extra', 'Unchanged')
            $Records[0].Section | Should -BeExactly 'directoryRoleAssignments'
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -Match "undeclared eligible assignment of directory role 'Reports Reader' for principal '$($script:DraP[2])'"
            $Records[0].Detail | Should -Match 'use -Prune to remove'
            $Records[1].Item | Should -BeExactly 'Reports Reader -> person1@example.com (Eligible)'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'removes an undeclared direct assignment in a declared pair under -Prune, naming it in its own warning' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -WarningVariable DraWarnings)
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -Match "^removed undeclared eligible assignment of directory role 'Reports Reader'"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
                $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002' -and
                $PesterBoundParameters.ContainsKey('Confirm') -and -not [bool]$PesterBoundParameters['Confirm']
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
            @($DraWarnings).Count | Should -Be 1
            "$($DraWarnings[0])" | Should -Match "removing undeclared eligible assignment of directory role 'Reports Reader' for principal '$($script:DraP[2])'"
        }
    }

    It 'reports Skipped naming the plan, and removes nothing, when the caller declines ShouldProcess under -Prune' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WhatIf `
                    -WarningAction SilentlyContinue -WarningVariable DraWarnings)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -Match "^would remove undeclared eligible assignment of directory role 'Reports Reader'"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            # The plan's warning names what would happen, not what is happening.
            @($DraWarnings).Count | Should -Be 1
            "$($DraWarnings[0])" | Should -Match "would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '$($script:DraP[2])'"
            "$($DraWarnings[0])" | Should -Not -Match 'removing'
        }
    }

    It 'removes an undeclared assigned active assignment with the active Remove cmdlet, and never reads the eligible ones' {
        InModuleScope $script:moduleName {
            $script:DraLiveActive = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1] -Kind Active
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2] -Kind Active
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Active')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Active)"
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and
                $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002' -and
                $PesterBoundParameters.ContainsKey('Confirm') -and -not [bool]$PesterBoundParameters['Confirm']
            }
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'reports Failed, scrubs and publishes the error when a removal throws, and carries on with the next candidate' {
        InModuleScope $script:moduleName {
            Mock Remove-OEREligibleDirectoryRoleAssignment {
                if ($PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002') { throw 'Graph 400 RoleAssignmentDoesNotExist' }
            }
            Mock Remove-OERErrorRecord {}
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[3]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Failed', 'Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -Match 'failed to remove undeclared eligible assignment'
            $Records[0].Detail | Should -Match 'RoleAssignmentDoesNotExist'
            $Records[1].Item | Should -BeExactly "Reports Reader -> $($script:DraP[3]) (Eligible)"
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            $CallerErrors = @(Select-DraCallerError $DraErrors)
            @($CallerErrors).Count | Should -Be 1
            "$($CallerErrors[0])" | Should -Match 'RoleAssignmentDoesNotExist'
        }
    }

    It 'names the cause and the way out when Graph refuses a prune removal with ActiveDurationTooShort' {
        # Measured live (teardown T.1): an adminRemove within five minutes of the principal's active
        # assignment starting is refused with ActiveDurationTooShort. The row says so; the assignment stays.
        InModuleScope $script:moduleName {
            Mock Remove-OEREligibleDirectoryRoleAssignment {
                if ($PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002') {
                    Write-Error -Message 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.' -ErrorId 'ActiveDurationTooShort' -Category InvalidOperation
                }
            }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed', 'Unchanged')
            $Records[0].Detail | Should -BeExactly ("failed to remove undeclared eligible assignment of directory role 'Reports Reader' for principal '$($script:DraP[2])': " +
                "Microsoft Graph does not change or remove a principal's assignments of a role until the principal's " +
                'active assignment of that role has run for five minutes (ActiveDurationTooShort), so nothing was ' +
                'changed; apply the document again in five minutes')
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'reads and reconciles only the declared pairs: another role in the read, and the other kind, are never touched' {
        InModuleScope $script:moduleName {
            # This read ignores -Role, so the pass's read of Reports Reader also returns a Message
            # Center Reader row: only the per-candidate role check keeps it out. The document names
            # Reports Reader only for Eligible, so its Active assignments must never even be read.
            Mock Get-OEREligibleDirectoryRoleAssignment {
                @($script:DraLiveEligible | Where-Object { -not $PrincipalId -or $_.PrincipalId -eq $PrincipalId })
            }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:MCR -Principal $script:DraP[3]
            )
            $script:DraLiveActive = @(New-DraPassRow -Role $script:RR -Principal $script:DraP[4] -Kind Active)
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Unchanged')
            @($Records | Where-Object { $_.Item -match $script:DraP[3] -or $_.Item -match $script:DraP[4] }).Count | Should -Be 0
            Should -Invoke Get-OERActiveDirectoryRoleAssignment -Times 0
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and -not $PesterBoundParameters.ContainsKey('PrincipalId')
            }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0 -ParameterFilter { $Role -eq 'aaaaaaaa-0000-0000-0000-000000000002' }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'never reports or removes <Case> (Prune: <Prune>)' -TestCases @(
        @{ Case = 'an activation in a declared Active pair'; Kind = 'Active'; Row = @{ Kind = 'Active'; AssignmentType = 'Activated' }; Prune = $false }
        @{ Case = 'an activation in a declared Active pair'; Kind = 'Active'; Row = @{ Kind = 'Active'; AssignmentType = 'Activated' }; Prune = $true }
        @{ Case = 'an assignment held through a group'; Kind = 'Eligible'; Row = @{ MemberType = 'Group' }; Prune = $false }
        @{ Case = 'an assignment held through a group'; Kind = 'Eligible'; Row = @{ MemberType = 'Group' }; Prune = $true }
        @{ Case = 'an administrative-unit-scoped assignment'; Kind = 'Eligible'; Row = @{ DirectoryScopeId = '/administrativeUnits/aaaaaaaa-0000-0000-0000-0000000000a1' }; Prune = $false }
        @{ Case = 'an administrative-unit-scoped assignment'; Kind = 'Eligible'; Row = @{ DirectoryScopeId = '/administrativeUnits/aaaaaaaa-0000-0000-0000-0000000000a1' }; Prune = $true }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; Row = $Row; Prune = $Prune } {
            param($Kind, $Row, $Prune)
            $Declared = New-DraPassRow -Role $script:RR -Principal $script:DraP[1] -Kind $Kind
            $Unmanaged = New-DraPassRow -Role $script:RR -Principal $script:DraP[5] @Row
            if ($Kind -eq 'Active') { $script:DraLiveActive = @($Declared, $Unmanaged) } else { $script:DraLiveEligible = @($Declared, $Unmanaged) }
            $Section = @(New-DraSection "Reports Reader|person1@example.com|$Kind")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Unchanged')
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
            # The pass did read the pair, so no row is a verdict, not an unread pair.
            $GetName = if ($Kind -eq 'Active') { 'Get-OERActiveDirectoryRoleAssignment' } else { 'Get-OEREligibleDirectoryRoleAssignment' }
            Should -Invoke $GetName -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('PrincipalId') }
        }
    }

    It 'reports the signed-in identity''s own undeclared assignment Skipped and never removes it (<PrincipalType>, Prune: <Prune>)' -TestCases @(
        @{ PrincipalType = 'User'; Prune = $false }
        @{ PrincipalType = 'User'; Prune = $true }
        @{ PrincipalType = 'ServicePrincipal'; Prune = $false }
        @{ PrincipalType = 'ServicePrincipal'; Prune = $true }
    ) {
        # ServicePrincipal is the app-only sign-in: the oid claim is then the service principal's id.
        InModuleScope $script:moduleName -Parameters @{ PrincipalType = $PrincipalType; Prune = $Prune } {
            param($PrincipalType, $Prune)
            Mock Get-OERSignedInObjectId { 'bbbbbbbb-0000-0000-0000-000000000006' }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[6] -PrincipalType $PrincipalType
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune -WarningAction SilentlyContinue)
            $Other = if ($Prune) { 'Removed' } else { 'Extra' }
            @($Records).Action | Should -Be @($Other, 'Skipped', 'Unchanged')
            $Records[1].Item | Should -BeExactly "Reports Reader -> $($script:DraP[6]) (Eligible)"
            $Records[1].Detail | Should -Match 'signed-in identity'
            $Records[1].Detail | Should -Match 'our own guard'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0 -ParameterFilter { $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000006' }
            $RemoveCount = if ($Prune) { 1 } else { 0 }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times $RemoveCount -Exactly
        }
    }

    It 'withholds every candidate when the signed-in identity is unknown (Prune: <Prune>)' -TestCases @(
        @{ Prune = $false }
        @{ Prune = $true }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Prune = $Prune } {
            param($Prune)
            Mock Get-OERSignedInObjectId { $null }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[3]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Skipped', 'Unchanged')
            foreach ($Record in $Records[0..1]) {
                $Record.Detail | Should -BeLike "prune withheld: the signed-in identity's object id is unknown*"
                $Record.Detail | Should -Match "it could not be determined from the session's Microsoft Graph token"
                $Record.Detail | Should -Match 'our own guard'
                $Record.Detail | Should -Match 'Sign in again with Connect-OER; if the token carries no oid claim, reconcile this pair from a session that does\.'
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'withholds the prune of a pair holding an entry whose principal lookup <Case>, and writes no error for it' -TestCases @(
        @{ Case = 'finds nothing'; Principal = 'nobody@example.com' }
        @{ Case = 'throws'; Principal = 'throws@example.com' }
    ) {
        # No error is written here: the unresolved entry's own invocation writes its error and its
        # Failed row, under the label the withheld Detail names.
        InModuleScope $script:moduleName -Parameters @{ Principal = $Principal } {
            param($Principal)
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', "Reports Reader|$Principal|Eligible")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry 'Reports Reader -> $Principal (Eligible)'*"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            @(Select-DraCallerError $DraErrors).Count | Should -Be 0
        }
    }

    It 'withholds only the pair of an entry whose principal cannot be resolved: another pair is still pruned' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:MCR -Principal $script:DraP[3]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', 'Message Center Reader|nobody@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Removed', 'Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[1].Item | Should -BeExactly "Message Center Reader -> $($script:DraP[3]) (Eligible)"
            $Records[1].Detail | Should -BeLike "prune withheld: declared entry 'Message Center Reader -> nobody@example.com (Eligible)'*"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002'
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
        }
    }

    It 'withholds every pair of its assignmentType, and no other, when an entry''s role lookup <Case>' -TestCases @(
        @{ Case = 'finds nothing'; RoleText = 'No Such Role' }
        @{ Case = 'throws'; RoleText = 'Throwing Role' }
    ) {
        # The unresolved role's pair is unknown, so it may be the counterpart of a candidate in any
        # Eligible pair; an Active pair cannot hold it and is reconciled as usual.
        InModuleScope $script:moduleName -Parameters @{ RoleText = $RoleText } {
            param($RoleText)
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $script:DraLiveActive = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1] -Kind Active
                New-DraPassRow -Role $script:RR -Principal $script:DraP[4] -Kind Active
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', "$RoleText|person3@example.com|Eligible", 'Reports Reader|person1@example.com|Active')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Skipped', 'Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry '$RoleText -> person3@example.com (Eligible)'*"
            $Records[1].Item | Should -BeExactly "Reports Reader -> $($script:DraP[4]) (Active)"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000004'
            }
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
            @(Select-DraCallerError $DraErrors).Count | Should -Be 0
        }
    }

    It 'treats one role written by name in one entry and by id in another as one pair: neither assignment is Extra or Removed' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            # The id is written upper-case on purpose: the role is resolved before it is keyed.
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', "$($script:RR.ToUpperInvariant())|person2@example.com|Eligible")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Unchanged')
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and -not $PesterBoundParameters.ContainsKey('PrincipalId')
            }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('PrincipalId') }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'matches a principal declared as an upper-case object id to its lower-case live assignment: never Extra, never Removed, and the item is Unchanged' {
        # Resolve-OERStructurePrincipal returns a GUID reference verbatim while Graph reports
        # principalId lower-case, so only a case-insensitive key keeps the declared assignment out of
        # the candidates -- and only a case-insensitive filter lets the item find its own row.
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(New-DraPassRow -Role $script:RR -Principal $script:DraP[1])
            $Section = @(New-DraSection "Reports Reader|$($script:DraP[1].ToUpperInvariant())|Eligible")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[1].ToUpperInvariant()) (Eligible)"
            Should -Invoke Resolve-OERStructurePrincipal -Times 2 -Exactly -ParameterFilter { $Reference -ceq 'BBBBBBBB-0000-0000-0000-000000000001' }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'treats a declared but empty principalType as not given, in the pass and in the item alike' {
        # The pass and the item must agree on what a declared principalType is: were an empty one
        # forwarded as -Type in the pass only, its lookup would fail there and withhold the pair
        # while the item itself resolved fine.
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @('{ "role": "Reports Reader", "principal": "person1@example.com", "principalType": "", "assignmentType": "Eligible" }' | ConvertFrom-Json)
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            Should -Invoke Resolve-OERStructurePrincipal -Times 0 -ParameterFilter { $PesterBoundParameters.ContainsKey('Type') }
            Should -Invoke Resolve-OERStructurePrincipal -Times 2 -Exactly
        }
    }

    It 'withholds before any identity guard: an unresolved entry in the pair wins over <Case>' -TestCases @(
        @{ Case = 'the signed-in identity''s own assignment'; SignedIn = 'bbbbbbbb-0000-0000-0000-000000000006' }
        @{ Case = 'an unknown signed-in identity'; SignedIn = $null }
    ) {
        # R10: the step 1 rule is checked first for every candidate, so the Detail names the
        # unresolved entry, not the identity guard that would otherwise apply.
        InModuleScope $script:moduleName -Parameters @{ SignedIn = $SignedIn } {
            param($SignedIn)
            $script:DraSignedIn = $SignedIn
            Mock Get-OERSignedInObjectId { $script:DraSignedIn }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[6]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', 'Reports Reader|nobody@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[6]) (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry 'Reports Reader -> nobody@example.com (Eligible)'*"
            $Records[0].Detail | Should -Not -Match 'signed-in identity'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'reports a failed read of one pair Failed and publishes it, prunes nothing in that pair, and still reconciles another pair' {
        InModuleScope $script:moduleName {
            Mock Get-OEREligibleDirectoryRoleAssignment {
                if ($Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and -not $PrincipalId) { throw 'Graph 403 Forbidden' }
                @($script:DraLiveEligible | Where-Object { $_.RoleDefinitionId -eq $Role -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId) })
            }
            Mock Remove-OERErrorRecord {}
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:MCR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:MCR -Principal $script:DraP[3]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', 'Message Center Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Failed', 'Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "$($script:RR) (Eligible)"
            $Records[0].Detail | Should -Match "could not read the eligible assignments of directory role '$($script:RR)'"
            $Records[0].Detail | Should -Match 'nothing in this pair was pruned or reported Extra'
            $Records[0].Detail | Should -Match 'Graph 403 Forbidden'
            $Records[1].Item | Should -BeExactly "Message Center Reader -> $($script:DraP[3]) (Eligible)"
            @($Records | Where-Object { $_.Item -match $script:DraP[2] }).Count | Should -Be 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000002' -and $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000003'
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            $CallerErrors = @(Select-DraCallerError $DraErrors)
            @($CallerErrors).Count | Should -Be 1
            "$($CallerErrors[0])" | Should -Match 'Graph 403 Forbidden'
        }
    }

    It 'reports Failed, never an empty pair, when the pass read of a <Kind> pair writes a non-terminating error' -TestCases @(
        @{ Kind = 'Eligible'; GetName = 'Get-OEREligibleDirectoryRoleAssignment' }
        @{ Kind = 'Active'; GetName = 'Get-OERActiveDirectoryRoleAssignment' }
    ) {
        # The real Get cmdlets report a refused read as a NON-terminating error and return nothing;
        # only -ErrorAction Stop on the pass read makes that a Failed row rather than an empty pair.
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; GetName = $GetName } {
            param($Kind, $GetName)
            Mock $GetName {
                if (-not $PrincipalId) {
                    Write-Error -Message 'Could not read the directory role assignments: Forbidden.' -ErrorId 'GraphRequestFailed' -Category PermissionDenied
                }
            }
            $Section = @(New-DraSection "Reports Reader|person1@example.com|$Kind")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            @($Records)[0].Action | Should -Be 'Failed'
            @($Records)[0].Item | Should -BeExactly "$($script:RR) ($Kind)"
            @($Records)[0].Detail | Should -Match 'Forbidden'
        }
    }

    It 'runs the pass before the item and whatever the item''s own fate: an unresolved first item still gets the pass rows, then its own Failed row' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[3]
            )
            $Section = @(New-DraSection 'No Such Role|person1@example.com|Eligible', 'Reports Reader|person2@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Failed')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[3]) (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry 'No Such Role -> person1@example.com (Eligible)'*"
            $Records[1].Item | Should -BeExactly 'No Such Role -> person1@example.com (Eligible)'
            $Records[1].Detail | Should -Match 'could not be resolved to a role definition id'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'skips an entry whose assignmentType is neither Eligible nor Active in the pass, and that item reports its own Failed row' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Message Center Reader|person1@example.com|Permanent', 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection)
            @($Records).Action | Should -Be @('Extra', 'Failed')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            $Records[1].Item | Should -BeExactly 'Message Center Reader -> person1@example.com (Permanent)'
            $Records[1].Detail | Should -Match "assignmentType 'Permanent' is not Eligible or Active"
            Should -Invoke Resolve-OERDirectoryRoleDefinitionId -Times 0 -ParameterFilter { $Role -eq 'Message Center Reader' }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0 -ParameterFilter { $Role -eq 'aaaaaaaa-0000-0000-0000-000000000002' }
            Should -Invoke Get-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'runs no pass without -ReconcileSection: no section read, no identity lookup and no pass rows' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Unchanged')
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0 -ParameterFilter { -not $PesterBoundParameters.ContainsKey('PrincipalId') }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke Get-OERSignedInObjectId -Times 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    # -- The group guard (F3) ------------------------------------------------------------------
    # A role-assignable group's own direct assignment is a candidate, but when the signed-in
    # identity is a member of that group (directly or through nesting) it holds the role through it,
    # and removing the group's assignment would end that role. Get-OERMemberGroupId answers the
    # memberships (mocked here; its own suite pins the request). Group ids are cccccccc-...; none is
    # version-4 shaped.

    It 'reports a group the signed-in identity is a member of Skipped and never removes it (<Kind>, Prune: <Prune>)' -TestCases @(
        @{ Kind = 'Eligible'; Prune = $true }
        @{ Kind = 'Eligible'; Prune = $false }
        @{ Kind = 'Active'; Prune = $true }
        @{ Kind = 'Active'; Prune = $false }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; Prune = $Prune } {
            param($Kind, $Prune)
            $Group = 'cccccccc-0000-0000-0000-000000000001'
            Mock Get-OERMemberGroupId { @('cccccccc-0000-0000-0000-000000000009', 'cccccccc-0000-0000-0000-000000000001') }
            $Rows = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1] -Kind $Kind
                New-DraPassRow -Role $script:RR -Principal $Group -Kind $Kind -PrincipalType 'Group'
            )
            if ($Kind -eq 'Active') { $script:DraLiveActive = $Rows } else { $script:DraLiveEligible = $Rows }
            $Section = @(New-DraSection "Reports Reader|person1@example.com|$Kind")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune `
                    -WarningAction SilentlyContinue -WarningVariable DraWarnings)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $Group ($Kind)"
            $Records[0].Detail | Should -BeExactly (
                "undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' for principal '$Group' " +
                "is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity " +
                "holds directory role 'Reports Reader' through it; the apply engine never removes a role the signed-in " +
                "identity holds (our own guard, not a Graph rejection)")
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly -ParameterFilter { $ObjectId -eq 'aaaaaaaa-0000-0000-0000-0000000000ff' }
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
            # Nothing is announced as being removed either.
            @($DraWarnings).Count | Should -Be 0
        }
    }

    It 'reads the memberships for a candidate of unknown principal type too, and skips it when it is one of the groups' {
        InModuleScope $script:moduleName {
            $Unknown = 'cccccccc-0000-0000-0000-000000000002'
            Mock Get-OERMemberGroupId { @('cccccccc-0000-0000-0000-000000000002') }
            # ConvertTo-OERDirectoryRoleAssignment reports an @odata.type it does not know as $null.
            $UnknownRow = New-DraPassRow -Role $script:RR -Principal $Unknown
            $UnknownRow.PrincipalType = $null
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                $UnknownRow
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $Unknown (Eligible)"
            $Records[0].Detail | Should -Match 'is a group the signed-in identity is a member of \(directly or through nesting\)'
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'still prunes a group the signed-in identity is not a member of (<Kind>, Prune: <Prune>)' -TestCases @(
        @{ Kind = 'Eligible'; Prune = $true }
        @{ Kind = 'Eligible'; Prune = $false }
        @{ Kind = 'Active'; Prune = $true }
        @{ Kind = 'Active'; Prune = $false }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; Prune = $Prune } {
            param($Kind, $Prune)
            $Group = 'cccccccc-0000-0000-0000-000000000001'
            Mock Get-OERMemberGroupId { @('cccccccc-0000-0000-0000-000000000008', 'cccccccc-0000-0000-0000-000000000009') }
            $Rows = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1] -Kind $Kind
                New-DraPassRow -Role $script:RR -Principal $Group -Kind $Kind -PrincipalType 'Group'
            )
            if ($Kind -eq 'Active') { $script:DraLiveActive = $Rows } else { $script:DraLiveEligible = $Rows }
            $Section = @(New-DraSection "Reports Reader|person1@example.com|$Kind")
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune -WarningAction SilentlyContinue)
            $Expected = if ($Prune) { 'Removed' } else { 'Extra' }
            @($Records).Action | Should -Be @($Expected, 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $Group ($Kind)"
            $RemoveName, $OtherRemove = if ($Kind -eq 'Active') {
                'Remove-OERActiveDirectoryRoleAssignment', 'Remove-OEREligibleDirectoryRoleAssignment'
            } else {
                'Remove-OEREligibleDirectoryRoleAssignment', 'Remove-OERActiveDirectoryRoleAssignment'
            }
            $RemoveCount = if ($Prune) { 1 } else { 0 }
            Should -Invoke $RemoveName -Times $RemoveCount -Exactly -ParameterFilter {
                $Role -eq 'aaaaaaaa-0000-0000-0000-000000000001' -and $PrincipalId -eq 'cccccccc-0000-0000-0000-000000000001'
            }
            Should -Invoke $RemoveName -Times $RemoveCount -Exactly
            Should -Invoke $OtherRemove -Times 0
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
        }
    }

    It 'withholds every group and unknown-type candidate, and writes the error once, when the membership read fails (Prune: <Prune>)' -TestCases @(
        @{ Prune = $true }
        @{ Prune = $false }
    ) {
        # A failed read is not an empty membership: a group or unknown-type candidate may be one the
        # signed-in identity holds the role through, so it is withheld (the step 1 rule). A user or
        # service principal cannot be such a group, so it goes on to the prune as before.
        InModuleScope $script:moduleName -Parameters @{ Prune = $Prune } {
            param($Prune)
            Mock Get-OERMemberGroupId { throw 'Graph 403 Authorization_RequestDenied' }
            Mock Remove-OERErrorRecord {}
            $Group = 'cccccccc-0000-0000-0000-000000000001'
            $Unknown = 'cccccccc-0000-0000-0000-000000000002'
            $UnknownRow = New-DraPassRow -Role $script:RR -Principal $Unknown
            $UnknownRow.PrincipalType = $null
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $Group -PrincipalType 'Group'
                $UnknownRow
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune:$Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            $UserAction = if ($Prune) { 'Removed' } else { 'Extra' }
            @($Records).Action | Should -Be @('Skipped', 'Skipped', $UserAction, 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $Group (Eligible)"
            $Records[1].Item | Should -BeExactly "Reports Reader -> $Unknown (Eligible)"
            $Records[2].Item | Should -BeExactly "Reports Reader -> $($script:DraP[2]) (Eligible)"
            foreach ($Index in 0, 1) {
                $Id = @($Group, $Unknown)[$Index]
                $Records[$Index].Detail | Should -BeExactly (
                    "prune withheld: the signed-in identity's group memberships could not be read, so undeclared eligible " +
                    "assignment of directory role 'Reports Reader' for principal '$Id' may be a group the signed-in identity " +
                    "holds the role through and is left in place (our own guard, not a Graph rejection): Graph 403 Authorization_RequestDenied")
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0 -ParameterFilter {
                $PrincipalId -in @('cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002')
            }
            $RemoveCount = if ($Prune) { 1 } else { 0 }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times $RemoveCount -Exactly -ParameterFilter {
                $PrincipalId -eq 'bbbbbbbb-0000-0000-0000-000000000002'
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times $RemoveCount -Exactly
            # One read, one scrub, one published error -- not one per withheld candidate.
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            $CallerErrors = @(Select-DraCallerError $DraErrors)
            @($CallerErrors).Count | Should -Be 1
            "$($CallerErrors[0])" | Should -Match 'Authorization_RequestDenied'
        }
    }

    It 'withholds the group candidate, never removes it, when the membership read writes a non-terminating error and returns nothing' {
        # A read that reports its failure as a NON-terminating error and returns nothing is still a
        # failed read, never an empty membership: only -ErrorAction Stop on the membership read makes
        # it land in the catch. -ErrorAction SilentlyContinue on the call below keeps a Stop
        # preference in the session from doing that work instead.
        InModuleScope $script:moduleName {
            Mock Get-OERMemberGroupId {
                Write-Error -Message 'Could not read the group memberships: Forbidden.' -ErrorId 'GraphRequestFailed' -Category PermissionDenied
            }
            $Group = 'cccccccc-0000-0000-0000-000000000001'
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $Group -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $Group (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: the signed-in identity's group memberships could not be read, *Forbidden*"
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
            @(Select-DraCallerError $DraErrors).Count | Should -Be 1
        }
    }

    It 'reads the memberships at most once per pass, reusing the <Case> for a group candidate in another pair' -TestCases @(
        @{ Case = 'answer'; Throws = $false }
        @{ Case = 'failure'; Throws = $true }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Throws = $Throws } {
            param($Throws)
            $script:DraReadThrows = $Throws
            Mock Get-OERMemberGroupId {
                if ($script:DraReadThrows) { throw 'Graph 503 ServiceUnavailable' }
                @('cccccccc-0000-0000-0000-000000000009')
            }
            Mock Remove-OERErrorRecord {}
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
            )
            $script:DraLiveActive = @(
                New-DraPassRow -Role $script:MCR -Principal $script:DraP[1] -Kind Active
                New-DraPassRow -Role $script:MCR -Principal 'cccccccc-0000-0000-0000-000000000002' -Kind Active -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', 'Message Center Reader|person1@example.com|Active')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            $Expected = if ($Throws) { 'Skipped' } else { 'Extra' }
            @($Records).Action | Should -Be @($Expected, $Expected, 'Unchanged')
            $Records[0].Item | Should -BeExactly 'Reports Reader -> cccccccc-0000-0000-0000-000000000001 (Eligible)'
            $Records[1].Item | Should -BeExactly 'Message Center Reader -> cccccccc-0000-0000-0000-000000000002 (Active)'
            Should -Invoke Get-OERMemberGroupId -Times 1 -Exactly
            $ErrorCount = if ($Throws) { 1 } else { 0 }
            @(Select-DraCallerError $DraErrors).Count | Should -Be $ErrorCount
        }
    }

    It 'makes no membership read when every candidate is a user or a service principal' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[2]
                New-DraPassRow -Role $script:RR -Principal $script:DraP[3] -PrincipalType 'ServicePrincipal'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Removed', 'Removed', 'Unchanged')
            Should -Invoke Get-OERMemberGroupId -Times 0
        }
    }

    It 'makes no membership read when the signed-in identity is unknown: the group candidate is withheld by that guard' {
        InModuleScope $script:moduleName {
            Mock Get-OERSignedInObjectId { $null }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Detail | Should -BeLike "prune withheld: the signed-in identity's object id is unknown*"
            Should -Invoke Get-OERMemberGroupId -Times 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'lets the own-assignment guard decide first: a group candidate that is the signed-in object id reads no memberships' {
        InModuleScope $script:moduleName {
            Mock Get-OERSignedInObjectId { 'cccccccc-0000-0000-0000-000000000001' }
            Mock Get-OERMemberGroupId { @('cccccccc-0000-0000-0000-000000000001') }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Detail | Should -Match 'belongs to the signed-in identity itself'
            $Records[0].Detail | Should -Not -Match 'is a group the signed-in identity is a member of'
            Should -Invoke Get-OERMemberGroupId -Times 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'lets the step 1 rule decide first: a withheld group candidate keeps the withheld Detail and reads no memberships' {
        InModuleScope $script:moduleName {
            Mock Get-OERMemberGroupId { @('cccccccc-0000-0000-0000-000000000001') }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible', 'Reports Reader|nobody@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry 'Reports Reader -> nobody@example.com (Eligible)'*"
            $Records[0].Detail | Should -Not -Match 'signed-in identity'
            Should -Invoke Get-OERMemberGroupId -Times 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }

    It 'matches the membership answer case-insensitively: an upper-case group id still makes its candidate Skipped' {
        InModuleScope $script:moduleName {
            Mock Get-OERMemberGroupId { @('CCCCCCCC-0000-0000-0000-000000000001') }
            $script:DraLiveEligible = @(
                New-DraPassRow -Role $script:RR -Principal $script:DraP[1]
                New-DraPassRow -Role $script:RR -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
            )
            $Section = @(New-DraSection 'Reports Reader|person1@example.com|Eligible')
            $Records = @(Invoke-SyncDraSection -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune -WarningAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Detail | Should -Match 'is a group the signed-in identity is a member of'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment with an ambiguous service principal display name' {
    # Resolve-OERStructurePrincipal and Resolve-OERApplicationId run for REAL here: only the Graph
    # transport is mocked, and its servicePrincipals query answers with two service principals that
    # share the display name 'Dup App'. The role resolver, the four cmdlets and the signed-in identity
    # are mocked as in the suites above. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:RR = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:DupSp1 = '11111111-1111-1111-1111-111111111111'
            $script:DupSp2 = '22222222-2222-2222-2222-222222222222'
            $script:DraKept = 'bbbbbbbb-0000-0000-0000-000000000001'
            $script:DraLiveEligible = @()
            function script:Invoke-SyncDraAmbiguous {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [object[]]$DeclaredInSection = @(), [switch]$ReconcileSection, [switch]$Prune)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune `
                    -DeclaredInSection $DeclaredInSection -ReconcileSection:$ReconcileSection
            }
            # A permanent, direct, tenant-scope eligible schedule of Reports Reader for one principal.
            function script:New-DraAmbiguousRow {
                param([string]$Principal, [string]$PrincipalType = 'User')
                [PSCustomObject]([ordered]@{
                        ScheduleId       = "schedule-$Principal"
                        RoleDefinitionId = $script:RR
                        RoleName         = 'Reports Reader'
                        PrincipalId      = $Principal
                        PrincipalType    = $PrincipalType
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                        StartDateTime    = '2026-01-01T00:00:00Z'
                        EndDateTime      = $null
                    })
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId {
                if ($Role -eq 'Reports Reader') { return $script:RR }
                return $null
            }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' } -MockWith {
                @{ value = @(
                        @{ id = $script:DupSp1; displayName = 'Dup App' },
                        @{ id = $script:DupSp2; displayName = 'Dup App' }) }
            }
            Mock Invoke-OERGraphRequest -MockWith { throw 'unexpected Graph request' }
            Mock Get-OEREligibleDirectoryRoleAssignment {
                @($script:DraLiveEligible | Where-Object { $_.RoleDefinitionId -eq $Role -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId) })
            }
            Mock Get-OERActiveDirectoryRoleAssignment {}
            Mock New-OEREligibleDirectoryRoleAssignment {}
            Mock New-OERActiveDirectoryRoleAssignment {}
            Mock Remove-OEREligibleDirectoryRoleAssignment {}
            Mock Remove-OERActiveDirectoryRoleAssignment {}
            Mock Get-OERSignedInObjectId { 'aaaaaaaa-0000-0000-0000-0000000000ff' }
        }
    }

    It 'reports the entry Failed with both candidate ids, and reads and writes nothing' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "principal": "Dup App", "principalType": "ServicePrincipal", "assignmentType": "Eligible" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDraAmbiguous -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Item | Should -BeExactly 'Reports Reader -> Dup App (Eligible)'
            $Records[0].Detail | Should -Match "could not resolve principal 'Dup App'"
            $Records[0].Detail | Should -Match $script:DupSp1
            $Records[0].Detail | Should -Match $script:DupSp2
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
            Should -Invoke Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke New-OERActiveDirectoryRoleAssignment -Times 0
        }
    }

    It 'withholds the prune of its pair under -Prune: the undeclared candidate is Skipped, never Extra or Removed' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraAmbiguousRow -Principal $script:DraKept
                New-DraAmbiguousRow -Principal $script:DupSp2 -PrincipalType 'ServicePrincipal'
            )
            $Section = @(
                [PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = 'Eligible' }
                [PSCustomObject]@{ role = 'Reports Reader'; principal = 'Dup App'; principalType = 'ServicePrincipal'; assignmentType = 'Eligible' }
            )
            $Records = @(Invoke-SyncDraAmbiguous -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DupSp2) (Eligible)"
            $Records[0].Detail | Should -BeLike "prune withheld: declared entry 'Reports Reader -> Dup App (Eligible)'*"
            @($Records | Where-Object { $_.Action -in @('Extra', 'Removed') }).Count | Should -Be 0
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke Remove-OERActiveDirectoryRoleAssignment -Times 0
            # The withheld row comes from the servicePrincipals answer, not the catch-all mock's throw.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment group guard with the real membership read' {
    # Get-OERMemberGroupId runs for REAL here: only the Graph transport is mocked, and its
    # getMemberGroups POST answers with several group ids, the member one upper-case and in the
    # middle. The helper emits each id as its own pipeline object and the handler collects them with
    # @(), so this pins that the real helper's output and the handler's collection agree: a helper
    # that emitted its ids as ONE array object would be wrapped by @() as a single element, leaving
    # one space-joined string that matches no group, and the member group would be removed. The
    # resolvers, the Get/Remove cmdlets and the signed-in identity are mocked as in the suites above.
    # No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:RR = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:DraKept = 'bbbbbbbb-0000-0000-0000-000000000001'
            $script:DraLiveEligible = @()
            function script:Invoke-SyncDraRealRead {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [object[]]$DeclaredInSection = @(), [switch]$ReconcileSection, [switch]$Prune)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune `
                    -DeclaredInSection $DeclaredInSection -ReconcileSection:$ReconcileSection
            }
            # A permanent, direct, tenant-scope eligible schedule of Reports Reader for one principal.
            function script:New-DraRealReadRow {
                param([string]$Principal, [string]$PrincipalType = 'User')
                [PSCustomObject]([ordered]@{
                        ScheduleId       = "schedule-$Principal"
                        RoleDefinitionId = $script:RR
                        RoleName         = 'Reports Reader'
                        PrincipalId      = $Principal
                        PrincipalType    = $PrincipalType
                        DirectoryScopeId = '/'
                        MemberType       = 'Direct'
                        StartDateTime    = '2026-01-01T00:00:00Z'
                        EndDateTime      = $null
                    })
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId {
                if ($Role -eq 'Reports Reader') { return $script:RR }
                return $null
            }
            Mock Resolve-OERStructurePrincipal {
                if (Test-OERGuid -Value $Reference) { return $Reference }
                return $null
            }
            Mock Invoke-OERGraphRequest -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/aaaaaaaa-0000-0000-0000-0000000000ff/getMemberGroups'
            } -MockWith {
                @{ value = @('cccccccc-0000-0000-0000-000000000009', 'CCCCCCCC-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000008') }
            }
            Mock Invoke-OERGraphRequest -MockWith { throw 'unexpected Graph request' }
            Mock Get-OEREligibleDirectoryRoleAssignment {
                @($script:DraLiveEligible | Where-Object { $_.RoleDefinitionId -eq $Role -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId) })
            }
            Mock Get-OERActiveDirectoryRoleAssignment {}
            Mock New-OEREligibleDirectoryRoleAssignment {}
            Mock New-OERActiveDirectoryRoleAssignment {}
            Mock Remove-OEREligibleDirectoryRoleAssignment {}
            Mock Remove-OERActiveDirectoryRoleAssignment {}
            Mock Get-OERSignedInObjectId { 'aaaaaaaa-0000-0000-0000-0000000000ff' }
        }
    }

    It 'skips the group it is a member of and prunes the other group, from one getMemberGroups request answering several ids' {
        InModuleScope $script:moduleName {
            $script:DraLiveEligible = @(
                New-DraRealReadRow -Principal $script:DraKept
                New-DraRealReadRow -Principal 'cccccccc-0000-0000-0000-000000000001' -PrincipalType 'Group'
                New-DraRealReadRow -Principal 'cccccccc-0000-0000-0000-000000000002' -PrincipalType 'Group'
            )
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = 'Eligible' })
            $Records = @(Invoke-SyncDraRealRead -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Skipped', 'Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly 'Reports Reader -> cccccccc-0000-0000-0000-000000000001 (Eligible)'
            $Records[0].Detail | Should -Match 'is a group the signed-in identity is a member of \(directly or through nesting\)'
            $Records[1].Item | Should -BeExactly 'Reports Reader -> cccccccc-0000-0000-0000-000000000002 (Eligible)'
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                $PrincipalId -eq 'cccccccc-0000-0000-0000-000000000002'
            }
            Should -Invoke Remove-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            # One request for both group candidates.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/getMemberGroups' }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment prune removal Microsoft Graph answers with RoleAssignmentDoesNotExist' {
    # Measured live (teardown T.1): Graph answered an adminRemove of an active assignment with
    # RoleAssignmentDoesNotExist although the request is listed Revoked and the assignment is gone.
    # The pass removes through the Remove cmdlets, which run for REAL here: only the Graph transport
    # is mocked, so its adminRemove POST answers RoleAssignmentDoesNotExist and its re-read of the
    # schedule answers from $script:DraReadBack. The pass's own reads, the resolvers and the
    # signed-in identity are mocked as in the suites above. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:RR = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:DraKept = 'bbbbbbbb-0000-0000-0000-000000000001'
            $script:DraExtra = 'bbbbbbbb-0000-0000-0000-000000000002'
            $script:DraReadBack = @()
            function script:Invoke-SyncDraGone {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [object[]]$DeclaredInSection = @(), [switch]$ReconcileSection, [switch]$Prune)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune `
                    -DeclaredInSection $DeclaredInSection -ReconcileSection:$ReconcileSection
            }
            # A permanent, direct, tenant-scope schedule of Reports Reader, projected as the pass reads it.
            function script:New-DraGoneRow {
                param([string]$Principal, [string]$Kind)
                $Row = [ordered]@{
                    ScheduleId       = "schedule-$Principal"
                    RoleDefinitionId = $script:RR
                    RoleName         = 'Reports Reader'
                    PrincipalId      = $Principal
                    PrincipalType    = 'User'
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                }
                if ($Kind -eq 'Active') { $Row.AssignmentType = 'Assigned' }
                $Row.StartDateTime = '2026-01-01T00:00:00Z'
                $Row.EndDateTime = $null
                [PSCustomObject]$Row
            }
            # The undeclared schedule as Graph returns it to the Remove cmdlet's re-read.
            $script:DraStillThere = [PSCustomObject]@{
                id               = 'schedule-extra'
                roleDefinitionId = $script:RR
                principalId      = $script:DraExtra
                directoryScopeId = '/'
                memberType       = 'Direct'
                assignmentType   = 'Assigned'
                status           = 'Provisioned'
                scheduleInfo     = [PSCustomObject]@{ startDateTime = '2026-01-01T00:00:00Z'; expiration = [PSCustomObject]@{ type = 'noExpiration' } }
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId {
                if ($Role -eq 'Reports Reader') { return $script:RR }
                if (Test-OERGuid -Value $Role) { return $Role.ToLowerInvariant() }
                return $null
            }
            Mock Resolve-OERStructurePrincipal {
                if (Test-OERGuid -Value $Reference) { return $Reference }
                return $null
            }
            Mock Get-OEREligibleDirectoryRoleAssignment {
                @((New-DraGoneRow -Principal $script:DraKept -Kind Eligible), (New-DraGoneRow -Principal $script:DraExtra -Kind Eligible)) |
                    Where-Object { -not $PrincipalId -or $_.PrincipalId -eq $PrincipalId }
            }
            Mock Get-OERActiveDirectoryRoleAssignment {
                @((New-DraGoneRow -Principal $script:DraKept -Kind Active), (New-DraGoneRow -Principal $script:DraExtra -Kind Active)) |
                    Where-Object { -not $PrincipalId -or $_.PrincipalId -eq $PrincipalId }
            }
            Mock New-OEREligibleDirectoryRoleAssignment {}
            Mock New-OERActiveDirectoryRoleAssignment {}
            Mock Get-OERSignedInObjectId { 'aaaaaaaa-0000-0000-0000-0000000000ff' }
            Mock Get-OERMemberGroupId { throw 'unexpected membership read' }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('RoleAssignmentDoesNotExist: The Role assignment does not exist.'),
                    'RoleAssignmentDoesNotExist',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } -MockWith { @{ value = @($script:DraReadBack) } }
        }
    }

    It 'reports the <Kind> removal Removed, and writes no error, when the re-read proves it gone' -TestCases @(
        @{ Kind = 'Active' }
        @{ Kind = 'Eligible' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind } {
            param($Kind)
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            $Records = @(Invoke-SyncDraGone -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraExtra) ($Kind)"
            # No row left at all: the plain Detail, nothing added.
            $Records[0].Detail | Should -BeExactly "removed undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' for principal '$($script:DraExtra)'"
            @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraGone' }).Count | Should -Be 0
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Body.action -eq 'adminRemove' }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -ne 'POST' }
        }
    }

    It 'adds to the Removed Detail how the principal still holds the role when <Case> is left, from the cmdlet warning and without a second read' -TestCases @(
        @{ Case = 'an activation'; Kind = 'Active'; MemberType = 'Direct'; AssignmentType = 'Activated'; Ways = 'as an activation of an eligible assignment' }
        @{ Case = 'an eligible row through a group'; Kind = 'Eligible'; MemberType = 'Group'; AssignmentType = $null; Ways = 'through a group' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; MemberType = $MemberType; AssignmentType = $AssignmentType; Ways = $Ways } {
            param($Kind, $MemberType, $AssignmentType, $Ways)
            $Left = $script:DraStillThere.PSObject.Copy()
            $Left.memberType = $MemberType
            $Left.assignmentType = $AssignmentType
            $script:DraReadBack = @($Left)
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            # The warning stream itself is captured (3>&1): -WarningVariable would also collect the
            # warnings the cmdlet writes under the pass's SilentlyContinue, which never reach the stream.
            $All = @(Invoke-SyncDraGone -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -ErrorAction SilentlyContinue -ErrorVariable DraErrors 3>&1)
            $Records = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $Streamed = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Detail | Should -BeExactly ("removed undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' for principal " +
                "'$($script:DraExtra)', but the principal still holds the role $Ways")
            @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraGone' }).Count | Should -Be 0
            # The pass's own "removing ..." warning only: the cmdlet's warning goes into the Detail, not the stream.
            $Streamed.Count | Should -Be 1
            $Streamed[0] | Should -BeLike 'Sync-OERStructureDirectoryRoleAssignment: removing undeclared*'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -ne 'POST' }
        }
    }

    It 'reports the <Kind> removal Failed, and writes the error, when the re-read finds it still in place' -TestCases @(
        @{ Kind = 'Active' }
        @{ Kind = 'Eligible' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind } {
            param($Kind)
            $script:DraReadBack = @($script:DraStillThere)
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            $Records = @(Invoke-SyncDraGone -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Failed', 'Unchanged')
            $Records[0].Detail | Should -BeExactly ("failed to remove undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' for principal " +
                "'$($script:DraExtra)': RoleAssignmentDoesNotExist: The Role assignment does not exist.")
            $Written = @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraGone' })
            @($Written).Count | Should -Be 1
            "$($Written[0])" | Should -Match 'RoleAssignmentDoesNotExist'
        }
    }

    It 'reports the <Kind> removal Failed, and writes the removal error, when the re-read fails' -TestCases @(
        @{ Kind = 'Active' }
        @{ Kind = 'Eligible' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind } {
            param($Kind)
            Mock Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } -MockWith { throw 'Graph 403 Authorization_RequestDenied' }
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            $Records = @(Invoke-SyncDraGone -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            @($Records).Action | Should -Be @('Failed', 'Unchanged')
            $Records[0].Detail | Should -BeExactly ("failed to remove undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' for principal " +
                "'$($script:DraExtra)': RoleAssignmentDoesNotExist: The Role assignment does not exist.")
            $Written = @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraGone' })
            @($Written).Count | Should -Be 1
            "$($Written[0])" | Should -Not -Match 'Authorization_RequestDenied'
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleAssignment when Microsoft Graph answers the request with a status in the Failed family (BL-33)' {
    # The New and Remove cmdlets run for REAL here: only the Graph transport, the sign-in and the
    # resolvers are mocked, and the pass's own reads of the live assignments as in the suites above.
    # Graph accepts each schedule request and answers it with the status under test. A Failed answer
    # granted, changed or removed nothing; the cmdlet's own request-failed error, raised under the
    # -ErrorAction Stop every engine call already passes, is what turns the row Failed -- the handler
    # has no code of its own for it. The role-assignable read of a principal of unknown type answers
    # "not a group". No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:RR = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:DraKept = 'bbbbbbbb-0000-0000-0000-000000000001'
            $script:DraExtra = 'bbbbbbbb-0000-0000-0000-000000000002'
            $script:AnsweredStatus = 'Failed'
            $script:LiveRows = @()
            function script:Invoke-SyncDraStatus {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [object[]]$DeclaredInSection = @(), [switch]$ReconcileSection, [switch]$Prune)
                Sync-OERStructureDirectoryRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune `
                    -DeclaredInSection $DeclaredInSection -ReconcileSection:$ReconcileSection
            }
            # A direct, tenant-scope schedule of Reports Reader, projected as the pass reads it; the
            # default window is 30 days from a fixed start, and -Permanent leaves it open.
            function script:New-DraStatusRow {
                param([string]$Principal, [string]$Kind, [switch]$Permanent)
                $Row = [ordered]@{
                    ScheduleId       = "schedule-$Principal"
                    RoleDefinitionId = $script:RR
                    RoleName         = 'Reports Reader'
                    PrincipalId      = $Principal
                    PrincipalType    = 'User'
                    DirectoryScopeId = '/'
                    MemberType       = 'Direct'
                }
                if ($Kind -eq 'Active') { $Row.AssignmentType = 'Assigned' }
                $Row.StartDateTime = '2026-01-01T00:00:00Z'
                $Row.EndDateTime = if ($Permanent) { $null } else { '2026-01-31T00:00:00Z' }
                [PSCustomObject]$Row
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERDirectoryRoleDefinitionId {
                if ($Role -eq 'Reports Reader') { return $script:RR }
                if (Test-OERGuid -Value $Role) { return $Role.ToLowerInvariant() }
                return $null
            }
            Mock Resolve-OERStructurePrincipal {
                if (Test-OERGuid -Value $Reference) { return $Reference }
                return $null
            }
            Mock Get-OEREligibleDirectoryRoleAssignment { @($script:LiveRows) | Where-Object { -not $PrincipalId -or $_.PrincipalId -eq $PrincipalId } }
            Mock Get-OERActiveDirectoryRoleAssignment { @($script:LiveRows) | Where-Object { -not $PrincipalId -or $_.PrincipalId -eq $PrincipalId } }
            Mock Get-OERSignedInObjectId { 'aaaaaaaa-0000-0000-0000-0000000000ff' }
            Mock Get-OERMemberGroupId { throw 'unexpected membership read' }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith {
                [PSCustomObject]@{
                    id               = 'req-status'
                    action           = $Body.action
                    status           = $script:AnsweredStatus
                    roleDefinitionId = $Body.roleDefinitionId
                    principalId      = $Body.principalId
                    directoryScopeId = $Body.directoryScopeId
                    scheduleInfo     = $null
                }
            }
            # Get-OERRoleAssignableState asks whether a principal of unknown type is a group: not one.
            Mock Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } -MockWith {
                if ($Uri -notlike 'v1.0/groups/*') { throw "unexpected request: $Uri" }
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'Request_ResourceNotFound'; Uri = $Uri }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
        }
    }

    It 'reports the <Kind> <Action> answered status <Status> Failed, and never Created or Updated' -ForEach @(
        @{ Kind = 'Eligible'; Action = 'adminAssign'; Status = 'Failed'; Id = 'EligibilityRequestFailed' }
        @{ Kind = 'Eligible'; Action = 'adminUpdate'; Status = 'Failed'; Id = 'EligibilityRequestFailed' }
        @{ Kind = 'Active'; Action = 'adminAssign'; Status = 'Failed'; Id = 'AssignmentRequestFailed' }
        @{ Kind = 'Active'; Action = 'adminUpdate'; Status = 'Failed'; Id = 'AssignmentRequestFailed' }
        @{ Kind = 'Eligible'; Action = 'adminAssign'; Status = 'FAILED'; Id = 'EligibilityRequestFailed' }
        @{ Kind = 'Active'; Action = 'adminUpdate'; Status = 'FAILED'; Id = 'AssignmentRequestFailed' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; Action = $Action; Status = $Status; Id = $Id } {
            param($Kind, $Action, $Status, $Id)
            $script:AnsweredStatus = $Status
            $script:ExpectedAction = $Action
            # adminUpdate: a live 30-day window that the declared 60 days changes; adminAssign: nothing live.
            $script:LiveRows = if ($Action -eq 'adminUpdate') { @(New-DraStatusRow -Principal $script:DraKept -Kind $Kind) } else { @() }
            $Item = [PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind; durationDays = 60 }
            $Records = @(Invoke-SyncDraStatus -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            # The real cmdlet sent the request with the action the diff chose, and Graph answered it.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Body.action -eq $script:ExpectedAction }
            @($Records).Action | Should -Be @('Failed')
            # The row holds the record as the handler re-published it, under its caller's name; the
            # cmdlet's own record, under the cmdlet's name, stays in the caller's -ErrorVariable too (measured:
            # twice beside the ActionPreferenceStopException, a count PowerShell's collection decides, so not pinned).
            $Records[0].Error.FullyQualifiedErrorId | Should -BeExactly "$Id,Invoke-SyncDraStatus"
            $Cmdlet = if ($Kind -eq 'Eligible') { 'New-OEREligibleDirectoryRoleAssignment' } else { 'New-OERActiveDirectoryRoleAssignment' }
            @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -eq "$Id,$Cmdlet" }).Count | Should -BeGreaterThan 0
            $Verb = if ($Action -eq 'adminAssign') { 'create' } else { 'update' }
            $Records[0].Detail | Should -BeLike ("failed to $Verb the $($Kind.ToLowerInvariant()) assignment: Microsoft Graph accepted the " +
                "$($Kind.ToLowerInvariant()) directory role assignment request 'req-status' ($Action) *but answered status $Status, so nothing was granted or changed.")
            @($Records | Where-Object { $_.Action -in @('Created', 'Updated') }).Count | Should -Be 0
            $Written = @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraStatus' })
            @($Written).Count | Should -Be 1
        }
    }

    It 'reports the <Kind> prune answered status <Status> Failed, and never Removed' -ForEach @(
        @{ Kind = 'Eligible'; Status = 'Failed'; Id = 'EligibilityRequestFailed' }
        @{ Kind = 'Active'; Status = 'Failed'; Id = 'AssignmentRequestFailed' }
        @{ Kind = 'Eligible'; Status = 'FAILED'; Id = 'EligibilityRequestFailed' }
        @{ Kind = 'Active'; Status = 'FAILED'; Id = 'AssignmentRequestFailed' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind; Status = $Status; Id = $Id } {
            param($Kind, $Status, $Id)
            $script:AnsweredStatus = $Status
            $script:LiveRows = @((New-DraStatusRow -Principal $script:DraKept -Kind $Kind -Permanent), (New-DraStatusRow -Principal $script:DraExtra -Kind $Kind -Permanent))
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            $Records = @(Invoke-SyncDraStatus -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            # The real Remove cmdlet sent the adminRemove for the undeclared principal, and Graph answered it.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and $Body.principalId -eq 'bbbbbbbb-0000-0000-0000-000000000002'
            }
            @($Records).Action | Should -Be @('Failed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraExtra) ($Kind)"
            $Records[0].Error.FullyQualifiedErrorId | Should -BeExactly "$Id,Invoke-SyncDraStatus"
            $Cmdlet = if ($Kind -eq 'Eligible') { 'Remove-OEREligibleDirectoryRoleAssignment' } else { 'Remove-OERActiveDirectoryRoleAssignment' }
            @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -eq "$Id,$Cmdlet" }).Count | Should -BeGreaterThan 0
            $Records[0].Detail | Should -BeLike ("failed to remove undeclared $($Kind.ToLowerInvariant()) assignment of directory role 'Reports Reader' " +
                "for principal '$($script:DraExtra)': Microsoft Graph accepted the $($Kind.ToLowerInvariant()) directory role assignment " +
                "removal request 'req-status' (adminRemove) *but answered status $Status, so nothing was removed: the $($Kind.ToLowerInvariant()) assignment is still in place.")
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
            $Written = @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraStatus' })
            @($Written).Count | Should -Be 1
        }
    }

    It 'the control: reports the <Kind> prune answered status Revoked Removed, and writes no error' -ForEach @(
        @{ Kind = 'Eligible' }
        @{ Kind = 'Active' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Kind = $Kind } {
            param($Kind)
            $script:AnsweredStatus = 'Revoked'
            $script:LiveRows = @((New-DraStatusRow -Principal $script:DraKept -Kind $Kind -Permanent), (New-DraStatusRow -Principal $script:DraExtra -Kind $Kind -Permanent))
            $Section = @([PSCustomObject]@{ role = 'Reports Reader'; principal = $script:DraKept; assignmentType = $Kind })
            $Records = @(Invoke-SyncDraStatus -Item $Section[0] -DeclaredInSection $Section -ReconcileSection -Prune `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable DraErrors)
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and $Body.principalId -eq 'bbbbbbbb-0000-0000-0000-000000000002'
            }
            @($Records).Action | Should -Be @('Removed', 'Unchanged')
            $Records[0].Item | Should -BeExactly "Reports Reader -> $($script:DraExtra) ($Kind)"
            @($DraErrors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncDraStatus' }).Count | Should -Be 0
        }
    }
}
