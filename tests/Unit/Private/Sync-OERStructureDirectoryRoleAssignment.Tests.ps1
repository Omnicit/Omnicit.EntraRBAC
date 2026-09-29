BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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

