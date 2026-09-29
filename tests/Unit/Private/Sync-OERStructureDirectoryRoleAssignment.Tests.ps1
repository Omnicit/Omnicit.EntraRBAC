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
}
