BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # One read with every stream the assertions look at captured, and -ErrorAction pinned: a
    # global Stop preference would otherwise end the call at the first record the mocks write.
    # The verbose lines keep Get-OERInventory's own prefix on purpose (its verbose output did
    # not change when this section moved here), which is why they are asserted verbatim.
    function Invoke-GroupRead {
        param(
            [string]$Filter = 'securityEnabled eq true',
            [switch]$IncludeId,
            [hashtable]$Cache,
            [switch]$RelevantOnly,
            [switch]$IncludeSyncedGroups,
            [switch]$ExcludeSharedName,
            [switch]$SecurityEnabledOnly,
            [string]$ProgressActivity,
            [object]$GroupNameIndex
        )
        $Arguments = @{
            Filter              = $Filter
            IncludeId           = [bool]$IncludeId
            Cache               = $Cache
            RelevantOnly        = [bool]$RelevantOnly
            IncludeSyncedGroups = [bool]$IncludeSyncedGroups
            ExcludeSharedName   = [bool]$ExcludeSharedName
            SecurityEnabledOnly = [bool]$SecurityEnabledOnly
            ProgressActivity    = $ProgressActivity
            GroupNameIndex      = $GroupNameIndex
        }
        InModuleScope Omnicit.EntraRBAC -Parameters $Arguments {
            $Params = @{ Filter = $Filter }
            if ($IncludeId) { $Params.IncludeId = $true }
            if ($null -ne $Cache) { $Params.PrincipalNameCache = $Cache }
            if ($RelevantOnly) { $Params.RelevantOnly = $true }
            if ($IncludeSyncedGroups) { $Params.IncludeSyncedGroups = $true }
            if ($ExcludeSharedName) { $Params.ExcludeSharedName = $true }
            if ($SecurityEnabledOnly) { $Params.SecurityEnabledOnly = $true }
            if ($ProgressActivity) { $Params.ProgressActivity = $ProgressActivity }
            if ($null -ne $GroupNameIndex) { $Params.GroupNameIndex = $GroupNameIndex }
            $Stream = @(Get-OERInventoryGroup @Params -Verbose -ErrorVariable ReadErr -ErrorAction SilentlyContinue `
                    -WarningVariable ReadWarn -WarningAction SilentlyContinue 4>&1)
            [PSCustomObject]@{
                Result  = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
                Verbose = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
                Warned  = @($ReadWarn | ForEach-Object { "$_" })
                Errors  = @($ReadErr)
            }
        }
    }

    # BL-131: an index of the given groups by display name, built by the real Get-OERGroupNameIndex
    # with no request, the way Export-OERInventory builds it from its roster.
    function New-TestGroupNameIndex {
        param([object[]]$Group)
        InModuleScope Omnicit.EntraRBAC -Parameters @{ G = $Group } {
            param($G)
            Get-OERGroupNameIndex -Group $G
        }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryGroup' {
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
            [PSCustomObject]@{
                Id = 'g-1'; DisplayName = 'role_sec_team'; Description = 'Team'; GroupType = 'Assigned'
                IsAssignableToRole = $false; MembershipRule = $null; MailNickname = 'roleSecTeam'
                Members = @(
                    @{ id = 'u-1'; displayName = 'Person One'; userPrincipalName = 'person1@contoso.com' },
                    @{ id = 'dev-1'; displayName = 'DEVICE-0001' }
                )
                Owners = @(@{ id = 'u-2'; userPrincipalName = 'person2@contoso.com' })
                PimEligibility = @(@{ principalId = 'p-1'; accessId = 'member'; startDateTime = $null; endDateTime = $null })
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'eligible' } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { 'pol-1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy {
            [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = 'c1'; ActivationEnabledRules = @('Justification')
                ActiveEnabledRules = @(); Notifications = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName { @{ 'p-1' = 'Person Eleven' } }
        # BL-125 (A3): the PIM for Groups assignment read answers as a successful read that lists
        # nothing, so every member and owner a fixture lists reads as standing and every projection
        # below keeps the meaning it had before the read existed.
        Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment {
            [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
        }
    }

    Context 'the list read' {
        It 'reads the groups with ONE Get-OERGroup call carrying the three include switches and the filter' {
            Invoke-GroupRead | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1 -ParameterFilter {
                $IncludeMembers -eq $true -and $IncludeOwners -eq $true -and $IncludePimEligibility -eq $true -and
                $Filter -eq 'securityEnabled eq true'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 0 -ParameterFilter { $All -eq $true }
        }

        It 'sends the filter alone, with none of the three include switches, under -RelevantOnly' {
            # The collections are read one group at a time afterwards, so the list read carries none.
            Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupCollection {
                param($GroupId, $Collection)
                [PSCustomObject]@{ Collection = $Collection; Read = $true; Value = @(); ErrorId = $null; Message = $null; Exception = $null }
            }
            Invoke-GroupRead -RelevantOnly | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -eq 'securityEnabled eq true' -and -not $IncludeMembers -and -not $IncludeOwners -and -not $IncludePimEligibility
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1
        }

        It 'sends a widened filter exactly as given' {
            Invoke-GroupRead -Filter "startswith(displayName,'role_')" | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -eq "startswith(displayName,'role_')"
            }
        }

        It 'refuses an empty filter at binding, before any request' {
            InModuleScope Omnicit.EntraRBAC {
                { Get-OERInventoryGroup -Filter '' } | Should -Throw
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 0
        }
    }

    Context '-SecurityEnabledOnly' {
        # A listing the way an operator's widened filter could answer it: one security group, then
        # a group with securityEnabled false, one whose property is missing, one whose value is
        # null, one whose value is the text 'true' and one whose value is a number. Only the first
        # is a security-enabled group by the rule the apply document keeps (a boolean true).
        BeforeEach {
            $script:SecurityListing = @(
                [PSCustomObject]@{ Id = 'g-sec'; DisplayName = 'sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = $true; Members = @(); Owners = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-m365'; DisplayName = 'm365_team'; GroupType = 'Unified'; IsAssignableToRole = $false; SecurityEnabled = $false; Members = @(); Owners = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-missing'; DisplayName = 'missing_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-null'; DisplayName = 'null_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = $null; Members = @(); Owners = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-text'; DisplayName = 'text_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = 'true'; Members = @(); Owners = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-number'; DisplayName = 'number_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = 1; Members = @(); Owners = @(); PimEligibility = @() }
            )
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { $script:SecurityListing }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
        }

        It 'projects the security-enabled groups only, and only a boolean true counts' {
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team')
            # Non-vacuity: without the switch the same listing projects all six.
            @((Invoke-GroupRead).Result.Groups).Count | Should -Be 6
        }

        It 'asks the PIM-in-use criterion for the groups it keeps only' {
            $null = Invoke-GroupRead -SecurityEnabledOnly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse -Exactly -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-sec' }
        }

        It 'writes ONE warning that names how many groups it left out' {
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            $Read.Warned.Count | Should -Be 1
            $Read.Warned[0] | Should -BeExactly '-GroupFilter returned 5 group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
        }

        It 'names a single group as one' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { $script:SecurityListing[0, 1] }
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team')
            $Read.Warned.Count | Should -Be 1
            $Read.Warned[0] | Should -BeExactly '-GroupFilter returned 1 group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
        }

        It 'writes no warning and keeps every group when every listed group is security-enabled' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { $script:SecurityListing[0] }
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups).Count | Should -Be 1
            $Read.Warned.Count | Should -Be 0
        }

        It 'writes no warning without the switch, however the listing reads' {
            $Read = Invoke-GroupRead
            $Read.Warned.Count | Should -Be 0
        }

        It 'leaves a group it left out unread and without a cause' {
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Errors.Count | Should -Be 0
        }

        It 'removes the cause of a failed collection read of a group it left out under a full read, and names no unread collection for it' {
            # A full read has Get-OERGroup read the collections WITH the list, before the reader sees
            # the group, so the failed members read of a group the switch then drops has already been
            # reported, and its cause already written to the verbose stream. The group is not in the
            # document, so that failed read is no gap in it: the cause leaves Causes (by the group's
            # id, the Target), and nothing names the group in Unread (that name is added where a group
            # is projected).
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'g-m365': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-m365' -ErrorAction $Ea
                $script:SecurityListing[0]
                [PSCustomObject]@{ Id = 'g-m365'; DisplayName = 'm365_team'; GroupType = 'Unified'; IsAssignableToRole = $false; SecurityEnabled = $false; Owners = @(); PimEligibility = @() }
            }
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team')
            $Read.Result.Unread.Count | Should -Be 0
            @($Read.Result.Causes).Count | Should -Be 0
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read members for group 'g-m365': Too many requests (429)."
            # Non-vacuity: without the switch the same listing projects the group, which names the
            # members it could not read, and the cause is the single cause the switch removed.
            $Control = Invoke-GroupRead
            @($Control.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team', 'm365_team')
            @($Control.Result.Unread) | Should -Be @('groups/m365_team/members')
            @($Control.Result.Causes).Count | Should -Be 1
            $Control.Result.Causes[0].Cause | Should -Be "Could not read members for group 'g-m365': Too many requests (429)."
            $Control.Result.Causes[0].Target | Should -Be 'g-m365'
        }

        It 'removes the cause of the group it left out only, and keeps the cause of a group it keeps' {
            # Two failed reads in one listing: the kept group's owners and the dropped group's members.
            # Only the dropped group's cause leaves; the kept group's stays, with its Unread name.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read owners for group 'g-sec': Too many requests (429)." `
                    -ErrorId 'GroupOwnerReadFailed' -Category LimitsExceeded -TargetObject 'g-sec' -ErrorAction $Ea
                Write-Error -Message "Could not read members for group 'g-m365': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-m365' -ErrorAction $Ea
                [PSCustomObject]@{ Id = 'g-sec'; DisplayName = 'sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = $true; Members = @(); PimEligibility = @() }
                [PSCustomObject]@{ Id = 'g-m365'; DisplayName = 'm365_team'; GroupType = 'Unified'; IsAssignableToRole = $false; SecurityEnabled = $false; Owners = @(); PimEligibility = @() }
            }
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team')
            @($Read.Result.Unread) | Should -Be @('groups/sec_team/owners')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be "Could not read owners for group 'g-sec': Too many requests (429)."
            $Read.Result.Causes[0].Target | Should -Be 'g-sec'
        }

        It 'removes no cause that has no target when the group it left out has no id' {
            # A cause with an empty Target is not about any group, and a left-out group without an id
            # must not make the empty text match it.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'Could not read owners for a group: Too many requests (429).' `
                    -ErrorId 'GroupOwnerReadFailed' -Category LimitsExceeded -ErrorAction $Ea
                $script:SecurityListing[0]
                [PSCustomObject]@{ DisplayName = 'noid_team'; GroupType = 'Unified'; IsAssignableToRole = $false; SecurityEnabled = $false; Members = @(); Owners = @(); PimEligibility = @() }
            }
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('sec_team')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be 'Could not read owners for a group: Too many requests (429).'
            $Read.Result.Causes[0].Target | Should -Be ''
            $Read.Warned.Count | Should -Be 1
        }

        It 'sends the filter it is given exactly as given, and asks for nothing more' {
            $null = Invoke-GroupRead -SecurityEnabledOnly -Filter 'securityEnabled eq true and (x eq 1)'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -eq 'securityEnabled eq true and (x eq 1)'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1
        }
    }

    Context 'progress (A13)' {
        # Write-Progress is mocked in module scope and every call is recorded, in order, as a line of
        # 'activity|status|percent' (or 'activity|completed'), so the sequence is asserted whole. The
        # mock body reads and writes the TEST file's script scope, as the other mocks of this file do.
        BeforeEach {
            $script:ProgressLog = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Write-Progress {
                param($Activity, $Status, $PercentComplete, [switch]$Completed)
                $script:ProgressLog.Add($(if ($Completed) { "$Activity|completed" } else { "$Activity|$Status|$PercentComplete" }))
            }
            $script:ProgressListing = @(
                foreach ($N in 1..3) {
                    [PSCustomObject]@{ Id = "g-$N"; DisplayName = "role_sec_$N"; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = $true; Members = @(); Owners = @(); PimEligibility = @() }
                }
            )
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { $script:ProgressListing }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
        }

        It 'writes the list status, one record per group with a percentage, then exactly one Completed' {
            $Read = Invoke-GroupRead -ProgressActivity 'Export-OERInventory'
            # Reach proof: all three groups were projected.
            @($Read.Result.Groups).Count | Should -Be 3
            @($script:ProgressLog) | Should -Be @(
                'Export-OERInventory|Reading the groups in full|'
                'Export-OERInventory|Group 1 of 3|33'
                'Export-OERInventory|Group 2 of 3|67'
                'Export-OERInventory|Group 3 of 3|100'
                'Export-OERInventory|completed'
            )
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Exactly -Times 1 -ParameterFilter { $Completed }
        }

        It 'writes no progress at all without -ProgressActivity, which is how Get-OERInventory reads' {
            $Read = Invoke-GroupRead
            @($Read.Result.Groups).Count | Should -Be 3
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Times 0
            $script:ProgressLog.Count | Should -Be 0
        }

        It 'names the list read as the group list under -RelevantOnly' {
            Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupCollection {
                param($GroupId, $Collection)
                [PSCustomObject]@{ Collection = $Collection; Read = $true; Value = @(); ErrorId = $null; Message = $null; Exception = $null }
            }
            $null = Invoke-GroupRead -RelevantOnly -ProgressActivity 'Export-OERInventory'
            $script:ProgressLog[0] | Should -Be 'Export-OERInventory|Reading the group list|'
            $script:ProgressLog[-1] | Should -Be 'Export-OERInventory|completed'
        }

        It 'counts the groups -SecurityEnabledOnly kept, the ones the loop goes through' {
            $script:ProgressListing = @(
                $script:ProgressListing[0]
                [PSCustomObject]@{ Id = 'g-x'; DisplayName = 'x_team'; GroupType = 'Unified'; IsAssignableToRole = $false; SecurityEnabled = $false; Members = @(); Owners = @(); PimEligibility = @() }
                $script:ProgressListing[1]
            )
            $Read = Invoke-GroupRead -SecurityEnabledOnly -ProgressActivity 'Export-OERInventory'
            @($Read.Result.Groups).Count | Should -Be 2
            @($script:ProgressLog | Where-Object { $_ -like '*|Group *' }) | Should -Be @(
                'Export-OERInventory|Group 1 of 2|50'
                'Export-OERInventory|Group 2 of 2|100'
            )
        }

        It 'writes the list status and Completed, and no group record, for an empty listing' {
            $script:ProgressListing = @()
            $Read = Invoke-GroupRead -ProgressActivity 'Export-OERInventory'
            @($Read.Result.Groups).Count | Should -Be 0
            @($script:ProgressLog) | Should -Be @(
                'Export-OERInventory|Reading the groups in full|'
                'Export-OERInventory|completed'
            )
        }

        It 'writes Completed exactly once when the loop stops on <Label> nothing catches (Review Focus 5)' -ForEach @(
            @{ Label = 'a throw'; Stop = { throw [System.Exception]::new('stop') }; Expected = 'stop' }
            # A statement-terminating error: it is not a throw, and without a try on the stack it would
            # end only the statement that called the helper. The message is the runtime's own, so the
            # test asks the runtime for it rather than spelling it.
            @{ Label = 'a statement-terminating error'; Stop = { $null.NoSuchMethod() }; Expected = $(try { $null.NoSuchMethod() } catch { [string]$PSItem.Exception.Message }) }
        ) {
            # The projection asks Test-OERGroupOnPremisesSynced for every group, outside any catch of
            # the reader's own, so an error there ends the read part-way. The reader is called inside
            # try {} here, with no -ErrorAction, so the exception reaches the test and is observed.
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupOnPremisesSynced -MockWith $Stop
            $Caught = InModuleScope Omnicit.EntraRBAC {
                try {
                    $null = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -ProgressActivity 'Export-OERInventory'
                    'did not stop'
                } catch {
                    [string]$PSItem.Exception.Message
                }
            }
            # Reach proof: the loop stopped on the error, after the first group's record.
            $Caught | Should -Be $Expected
            $Expected | Should -Not -BeNullOrEmpty
            @($script:ProgressLog) | Should -Be @(
                'Export-OERInventory|Reading the groups in full|'
                'Export-OERInventory|Group 1 of 3|33'
                'Export-OERInventory|completed'
            )
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Exactly -Times 1 -ParameterFilter { $Completed }
        }

        It 'writes nothing when the error stops it without -ProgressActivity' {
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupOnPremisesSynced { throw [System.Exception]::new('stop') }
            $Caught = InModuleScope Omnicit.EntraRBAC {
                try {
                    $null = Get-OERInventoryGroup -Filter 'securityEnabled eq true'
                    'did not stop'
                } catch {
                    [string]$PSItem.Exception.Message
                }
            }
            $Caught | Should -Be 'stop'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Times 0
        }
    }

    Context 'the result' {
        It 'is one tagged object holding Groups, Unread and Causes' {
            $Read = Invoke-GroupRead
            $Read.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryGroupRead'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Groups'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Unread'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Causes'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'SharedNames'
            @($Read.Result.Groups).Count | Should -Be 1
        }

        It 'holds SharedNames as an empty array when no name is shared, with -ExcludeSharedName and without (BL-131)' {
            foreach ($Exclude in @($true, $false)) {
                $Read = Invoke-GroupRead -ExcludeSharedName:$Exclude
                , $Read.Result.SharedNames | Should -BeOfType ([object[]])
                $Read.Result.SharedNames.Count | Should -Be 0
                @($Read.Result.Groups).Count | Should -Be 1
            }
        }

        It 'holds real arrays, empty ones included, so a caller can enumerate without a null check' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { }
            $Read = Invoke-GroupRead
            , $Read.Result.Groups | Should -BeOfType ([object[]])
            , $Read.Result.Unread | Should -BeOfType ([string[]])
            , $Read.Result.Causes | Should -BeOfType ([object[]])
            $Read.Result.Groups.Count | Should -Be 0
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
        }

        It 'returns the projections in list order' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                foreach ($N in 'role_sec_c', 'role_sec_a', 'role_sec_b') {
                    [PSCustomObject]@{
                        Id = "g-$N"; DisplayName = $N; Description = $null; GroupType = 'Assigned'
                        IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                    }
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_c', 'role_sec_a', 'role_sec_b')
        }
    }

    Context 'the projection' {
        It 'projects a plain group, with no id unless asked' {
            $Group = (Invoke-GroupRead).Result.Groups[0]
            $Group.PSObject.TypeNames[0] | Should -Be 'System.Management.Automation.PSCustomObject'
            $Group.displayName | Should -Be 'role_sec_team'
            $Group.roleAssignable | Should -BeFalse
            $Group.dynamic | Should -BeFalse
            $Group.description | Should -Be 'Team'
            $Group.mailNickname | Should -Be 'roleSecTeam'
            # BL-121 (R-16): the members stand in the fixed order, 'dev-1' before 'person1@contoso.com' (the order Graph listed them in was the reverse).
            $Group.members | Should -Be @('dev-1', 'person1@contoso.com')
            $Group.owners | Should -Be @('person2@contoso.com')
            @($Group.eligibility).Count | Should -Be 1
            $Group.eligibility[0].principal | Should -Be 'Person Eleven'
            $Group.eligibility[0].accessType | Should -Be 'member'
            $Group.PSObject.Properties.Name | Should -Not -Contain 'id'
            $Group.PSObject.Properties.Name | Should -Not -Contain 'membershipRule'
            $Group.PSObject.Properties.Name | Should -Not -Contain 'onPremisesSynced'
            $Group.eligibility[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            $Group.eligibility[0].PSObject.Properties.Name | Should -Not -Contain 'durationDays'
        }

        It 'stamps the group id and the eligibility principal id only with -IncludeId' {
            $Group = (Invoke-GroupRead -IncludeId).Result.Groups[0]
            $Group.id | Should -Be 'g-1'
            $Group.eligibility[0].id | Should -Be 'p-1'
        }

        It 'projects a dynamic group with its rule and its processing state' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    MembershipRuleProcessingState = 'On'; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            $Group = (Invoke-GroupRead).Result.Groups[0]
            $Group.dynamic | Should -BeTrue
            $Group.membershipRule | Should -Be 'user.department -eq "IT"'
            $Group.membershipRuleProcessingState | Should -Be 'On'
        }

        It 'writes onPremisesSynced only for a group synchronized from on-premises' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-s'; DisplayName = 'role_sec_synced'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; OnPremisesSyncEnabled = $true; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            (Invoke-GroupRead).Result.Groups[0].onPremisesSynced | Should -BeTrue
        }

        It 'resolves eligibility principals through the cache it is given and leaves what it learned in it' {
            $Cache = @{ 'p-9' = 'Already Known' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @()
                    PimEligibility = @(@{ principalId = 'p-9' }, @{ principalId = 'p-1'; accessId = 'owner' })
                }
            }
            $Group = (Invoke-GroupRead -Cache $Cache).Result.Groups[0]
            $Group.eligibility[0].principal | Should -Be 'Already Known'
            $Group.eligibility[1].principal | Should -Be 'Person Eleven'
            $Group.eligibility[1].accessType | Should -Be 'owner'
            $Cache['p-1'] | Should -Be 'Person Eleven' -Because 'the caller shares this cache with its other sections'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName -Exactly -Times 1 -ParameterFilter {
                @($Id).Count -eq 1 -and $Id[0] -eq 'p-1'
            }
        }

        It 'sends no principal lookup when every principal is already cached' {
            $Cache = @{ 'p-1' = 'Cached Person' }
            $Group = (Invoke-GroupRead -Cache $Cache).Result.Groups[0]
            $Group.eligibility[0].principal | Should -Be 'Cached Person'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName -Exactly -Times 0
        }
    }

    Context 'pimPolicy' {
        It 'projects the member and owner policy for a group that uses PIM for Groups' {
            $Group = (Invoke-GroupRead).Result.Groups[0]
            $Group.pimPolicy.member.activationMaxHours | Should -Be 8
            $Group.pimPolicy.member.authenticationContextId | Should -Be 'c1'
            $Group.pimPolicy.owner.activationMaxHours | Should -Be 8
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse -Exactly -Times 1 -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 1
            }
        }

        It 'exports no pimPolicy, and makes none of the four policy reads, for a group the criterion does not find in use' {
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility and no modified policy' } }
            $Read = Invoke-GroupRead
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId -Exactly -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy -Exactly -Times 0
            @($Read.Verbose) | Should -Contain "Get-OERInventory: group 'role_sec_team': pimPolicy not exported -- no eligibility and no modified policy."
            $Read.Result.Unread.Count | Should -Be 0
        }

        It 'skips the policy read for an access type whose policy Graph does not list' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { $null }
            $Read = Invoke-GroupRead
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy -Exactly -Times 0
            $Read.Result.Unread.Count | Should -Be 0
        }

        It 'reports a criterion that could not be read as unread with its cause, and exports no pimPolicy' {
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { throw 'criterion refused (403)' }
            $Read = Invoke-GroupRead
            $Cause = "Could not determine whether group 'g-1' uses PIM for Groups: criterion refused (403)"
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            @($Read.Result.Unread) | Should -Be @('groups/role_sec_team/pimPolicy')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be $Cause
            $Read.Result.Causes[0].Target | Should -Be 'g-1'
            @($Read.Verbose) | Should -Contain "Get-OERInventory: $Cause"
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy -Exactly -Times 0
        }

        It 'reports a failed policy read for one access type, by group and access type, and keeps the other' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy {
                param($Id, $AccessType)
                if ($AccessType -eq 'owner') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not read the owner policy of group 'g-1': throttled"),
                        'PimPolicyReadFailed', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
                }
                [PSCustomObject]@{ ActivationMaxHours = 4; ActivationEnabledRules = @(); ActiveEnabledRules = @() }
            }
            $Read = Invoke-GroupRead
            $Read.Result.Groups[0].pimPolicy.member.activationMaxHours | Should -Be 4
            $Read.Result.Groups[0].pimPolicy.PSObject.Properties.Name | Should -Not -Contain 'owner'
            @($Read.Result.Unread) | Should -Be @('groups/role_sec_team/pimPolicy/owner')
            $Read.Result.Causes[0].Cause | Should -Be "Could not read the owner policy of group 'g-1': throttled"
            $Read.Result.Causes[0].Target | Should -Be 'g-1'
        }

        It 'does not report a policy Graph does not list' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('no policy'), 'PimPolicyNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
            }
            $Read = Invoke-GroupRead
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
        }
    }

    Context 'a failed read is named, never an empty fact' {
        It 'turns a members failure into an explicit null, an unread name and one cause with its target' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'g-1': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-1' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            $Read = Invoke-GroupRead
            $Group = $Read.Result.Groups[0]
            $Group.PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Group.members | Should -BeTrue
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_team/members'
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be "Could not read members for group 'g-1': Too many requests (429)."
            $Read.Result.Causes[0].Target | Should -Be 'g-1'
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read members for group 'g-1': Too many requests (429)."
            $Read.Warned | Should -BeNullOrEmpty -Because 'a per-collection failure is accounted for by name, not by a section warning'
        }

        It 'names an owners read that is missing, without a cause of its own' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_team/owners'
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_team/eligibility'
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'owners'
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'eligibility'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName -Exactly -Times 0
        }

        It 'turns a list failure published by Get-OERGroup into the unread name groups and a warning' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction $Ea
            }
            $Read = Invoke-GroupRead
            $Read.Result.Groups.Count | Should -Be 0
            @($Read.Result.Unread) | Should -Be @('groups')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be 'Could not read groups: Insufficient privileges to complete the operation.'
            [string]::IsNullOrEmpty($Read.Result.Causes[0].Target) | Should -BeTrue
            @($Read.Warned) | Should -Be @('Could not read groups: Insufficient privileges to complete the operation.')
            @($Read.Verbose) | Should -Contain 'Get-OERInventory: Could not read groups: Insufficient privileges to complete the operation.'
        }

        It 'turns a list failure thrown by Get-OERGroup into the unread name groups and a warning' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { throw 'throttled' }
            $Read = Invoke-GroupRead
            $Read.Result.Groups.Count | Should -Be 0
            @($Read.Result.Unread) | Should -Be @('groups')
            $Read.Result.Causes[0].Cause | Should -Be 'Could not read groups: throttled'
            @($Read.Warned) | Should -Be @('Could not read groups: throttled')
        }

        It 'reports nothing for a group that was not found' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'gone' -ErrorId 'GroupNotFound' -Category ObjectNotFound -ErrorAction $Ea
            }
            $Read = Invoke-GroupRead
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
        }

        It 'sends a foreign error record to the verbose stream, not to a warning or the unread list' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'stray from a nested call' -ErrorId 'SomeNestedFailure' -Category NotSpecified -ErrorAction $Ea
            }
            $Read = Invoke-GroupRead
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
            @($Read.Verbose) | Should -Contain 'Get-OERInventory: ignoring a foreign error record seen while reading groups (SomeNestedFailure): stray from a nested call'
        }

        It 'keeps the groups that were read when one group has a failed collection' {
            # Pester does not carry the caller's -ErrorAction into a mock body the way a real
            # cmdlet's own preference would, so every mock in this file that writes a record honours
            # it explicitly. Without that this test is INERT: a bare -ErrorAction Continue in the
            # mock never terminates, so changing the reader's -ErrorAction SilentlyContinue on its
            # Get-OERGroup call to Stop would still pass. With it, Stop makes the write terminate,
            # the reader's catch turns the whole read into 'groups' unread, and the group after the
            # failure is never projected -- the data loss the SilentlyContinue + -ErrorVariable
            # shape exists to prevent. The test is against null, not truthiness: SilentlyContinue is
            # the enum's value 0, so a bare "if ($ErrorAction)" reads it as not given.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'members read failed' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -TargetObject 'g-1' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_first'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Owners = @(); PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-2'; DisplayName = 'role_sec_second'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(@{ userPrincipalName = 'person3@contoso.com' })
                    Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_first', 'role_sec_second')
            $Read.Result.Groups[1].members | Should -Be @('person3@contoso.com')
        }

        # Sprint 11 step 10 (BL-58). The list read pipes Get-OERGroup onward before its @( ) closes, the one
        # measured shape that deposits nothing in the caller's -ErrorVariable (docs/development/rationale.md,
        # #writeerror-deposit). The bare call inside @( ) deposited one record per record Get-OERGroup wrote,
        # although this reader reports each of them itself, as an unread collection with its cause. The reach
        # proof stands first in each test (the reader saw the record and named the read unread), so an empty
        # list of leaked records cannot be a read that wrote nothing.
        It 'leaves no record of a failed collection read in the caller -ErrorVariable, and still names the collection unread (BL-58)' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not read members for group 'g-1': Too many requests (429)."),
                        'GroupMemberReadFailed,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, 'g-1')) -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_team/members'
            @($Read.Result.Causes).Count | Should -Be 1
            $Leaked = @($Read.Errors | Where-Object { $null -ne $_ -and ([string]$_.FullyQualifiedErrorId) -like 'GroupMemberReadFailed*' })
            $Leaked.Count | Should -Be 0 -Because ('a record Get-OERGroup wrote is captured by the reader and must not reach the caller; leaked: ' +
                (@($Leaked | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }

        It 'leaves no record of a failed list read in the caller -ErrorVariable, and still names the groups unread (BL-58)' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction $Ea
            }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Be @('groups')
            @($Read.Warned) | Should -Be @('Could not read groups: Insufficient privileges to complete the operation.')
            $Leaked = @($Read.Errors | Where-Object { $null -ne $_ -and ([string]$_.FullyQualifiedErrorId) -like 'Authorization_RequestDenied*' })
            $Leaked.Count | Should -Be 0 -Because ('a record Get-OERGroup wrote is captured by the reader and must not reach the caller; leaked: ' +
                (@($Leaked | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }

        It 'leaves an empty item out of the list Get-OERGroup returns, as the filter after the pipe does (BL-58)' {
            # The filter stands after the pipe for the access review read of Get-OERInventory, and is not to be
            # simplified away: an empty item would otherwise be projected as a group without a name.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                $null
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_team')
        }
    }

    Context 'the bookkeeping of a failed list read stands before its warning (Sprint 11 step 10, BL-44)' {
        # BL-44 asks for the bookkeeping before the warning at every site. A Write-Warning under a Stop warning
        # preference is a terminating error and ends the read in either order, so the order shows only in the
        # verbose stream. Add-UnreadSection writes a verbose line first, so the proof is behavioural: under
        # -WarningAction Stop -Verbose the section's verbose line is written before the warning stops the
        # command. The line is asserted WHOLE, and the two sites are told apart by it: the site in the record
        # loop writes the reader's own message, and the catch -- which also catches the stop the warning of the
        # record loop raises -- writes 'Could not read groups: ' followed by that stop's own message.
        BeforeAll {
            function Invoke-GroupReadUnderStop {
                InModuleScope Omnicit.EntraRBAC {
                    $Seen = [System.Collections.Generic.List[string]]::new()
                    $Stopped = $null
                    try {
                        Get-OERInventoryGroup -Filter 'securityEnabled eq true' -Verbose -WarningAction Stop -ErrorAction SilentlyContinue 4>&1 |
                            ForEach-Object { if ($_ -is [System.Management.Automation.VerboseRecord]) { $Seen.Add([string]$_.Message) } }
                    } catch {
                        $Stopped = $PSItem
                    }
                    [PSCustomObject]@{ Verbose = $Seen.ToArray(); Stopped = $Stopped }
                }
            }
        }

        It 'writes the verbose line of a list failure Get-OERGroup publishes before the warning stops the read' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction $Ea
            }
            $Run = Invoke-GroupReadUnderStop
            # Reach proof: the warning was reached, and it stopped the command.
            $Run.Stopped | Should -Not -BeNullOrEmpty
            $Run.Stopped.Exception.Message | Should -BeLike '*Could not read groups: Insufficient privileges to complete the operation.'
            @($Run.Verbose) | Should -Contain 'Get-OERInventory: Could not read groups: Insufficient privileges to complete the operation.'
        }

        It 'writes the verbose line of a list failure Get-OERGroup throws before the warning stops the read' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup { throw 'throttled' }
            $Run = Invoke-GroupReadUnderStop
            $Run.Stopped | Should -Not -BeNullOrEmpty
            $Run.Stopped.Exception.Message | Should -BeLike '*Could not read groups: throttled'
            @($Run.Verbose) | Should -Contain 'Get-OERInventory: Could not read groups: throttled'
        }
    }

    Context 'order' {
        It 'lists the unread names and the causes in the order they were found' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'g-a': first" `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction $Ea
                Write-Error -Message "Could not read owners for group 'g-a': second" `
                    -ErrorId 'GroupOwnerReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-a'; DisplayName = 'role_sec_a'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-b'; DisplayName = 'role_sec_b'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse {
                param($GroupId)
                if ($GroupId -eq 'g-b') { throw 'third' }
                [PSCustomObject]@{ InUse = $false; Reason = 'x' }
            }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Be @('groups/role_sec_a/members', 'groups/role_sec_a/owners', 'groups/role_sec_b/pimPolicy')
            @($Read.Result.Causes | ForEach-Object { $_.Cause }) | Should -Be @(
                "Could not read members for group 'g-a': first",
                "Could not read owners for group 'g-a': second",
                "Could not determine whether group 'g-b' uses PIM for Groups: third")
            @($Read.Result.Causes | ForEach-Object { $_.Target }) | Should -Be @('g-a', 'g-a', 'g-b')
        }

        It 'puts the list failure first, then the per-group findings' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('page two refused'), 'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-a'; DisplayName = 'role_sec_a'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Be @('groups', 'groups/role_sec_a/owners')
            @($Read.Result.Causes | ForEach-Object { $_.Cause }) | Should -Be @('Could not read groups: page two refused')
        }

        It 'never adds a blank cause' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message ' ' -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-a'; DisplayName = 'role_sec_a'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Read = Invoke-GroupRead
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_a/members'
            $Read.Result.Causes.Count | Should -Be 0
        }
    }

    Context 'the lists a projection writes stand in one fixed order (Sprint 11 step 10, BL-121, R-16)' {
        # Graph answers a group's members, owners and eligibility in no fixed order, so two reads of one
        # unchanged tenant used to write one set in two orders. Members and owners are texts (a UPN, else the
        # object id): ordered without regard to letter case, ties by ordinal comparison, so 'Alice' stands
        # before 'alice'. Eligibility is ordered by principal, then accessType, then durationDays (a permanent
        # eligibility, which has none, first), then -- under -IncludeId -- id. The group listing is fed in two
        # orders (the second the reverse of the first), and each answer is a read in full.
        BeforeEach {
            $script:OrderMembers = @(
                @{ id = 'm-5'; userPrincipalName = 'bob@contoso.com' }
                @{ id = 'm-4'; userPrincipalName = 'alice@contoso.com' }
                @{ id = 'dev-9'; displayName = 'DEVICE-0009' }
                @{ id = 'm-3'; userPrincipalName = 'Alice@contoso.com' }
                @{ id = 'm-2'; userPrincipalName = 'Carol@contoso.com' }
                @{ id = 'm-1' }
            )
            $script:OrderOwners = @(
                @{ id = 'o-3'; userPrincipalName = 'zed@contoso.com' }
                @{ id = 'o-2'; userPrincipalName = 'Zed@contoso.com' }
                @{ id = 'o-1'; userPrincipalName = 'amy@contoso.com' }
            )
            # Scrambled: an owner eligibility first, a time-bound one before a permanent one of the same
            # principal, two principals that differ only in letter case, and one principal with both access
            # types. Start and end are fixed, so the durations are 30 and 7 days.
            $script:OrderEligibility = @(
                @{ principalId = 'p-1'; accessId = 'owner'; startDateTime = $null; endDateTime = $null }
                @{ principalId = 'p-2'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z' }
                @{ principalId = 'p-3'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                @{ principalId = 'p-1'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-08T09:00:00Z' }
                @{ principalId = 'p-2'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                @{ principalId = 'p-1'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
            )
            $script:OrderReverse = $false
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                $Members = $script:OrderMembers; $Owners = $script:OrderOwners; $Eligibility = $script:OrderEligibility
                if ($script:OrderReverse) { $Members = @($Members[($Members.Count - 1)..0]); $Owners = @($Owners[($Owners.Count - 1)..0]); $Eligibility = @($Eligibility[($Eligibility.Count - 1)..0]) }
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; Description = 'Team'; GroupType = 'Assigned'
                    IsAssignableToRole = $false; MembershipRule = $null; MailNickname = 'roleSecTeam'
                    Members = $Members; Owners = $Owners; PimEligibility = $Eligibility
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName {
                @{ 'p-1' = 'bob@contoso.com'; 'p-2' = 'Alice@contoso.com'; 'p-3' = 'alice@contoso.com' }
            }
        }

        It 'writes the members in the fixed order, an id standing for a member that has no user principal name' {
            $Group = (Invoke-GroupRead).Result.Groups[0]
            (@($Group.members) -join '|') | Should -BeExactly 'Alice@contoso.com|alice@contoso.com|bob@contoso.com|Carol@contoso.com|dev-9|m-1'
        }

        It 'writes the owners in the fixed order' {
            $Group = (Invoke-GroupRead).Result.Groups[0]
            (@($Group.owners) -join '|') | Should -BeExactly 'amy@contoso.com|Zed@contoso.com|zed@contoso.com'
        }

        It 'writes the eligibility by principal, then access type, then duration with a permanent one first' {
            $Group = (Invoke-GroupRead).Result.Groups[0]
            $Written = @($Group.eligibility | ForEach-Object { "$($_.principal)/$($_.accessType)/$(if ($null -eq $_.durationDays) { 'permanent' } else { $_.durationDays })" })
            $Written -join '|' | Should -BeExactly 'Alice@contoso.com/member/permanent|Alice@contoso.com/member/30|alice@contoso.com/member/permanent|bob@contoso.com/member/permanent|bob@contoso.com/member/7|bob@contoso.com/owner/permanent'
        }

        It 'writes the same JSON for the same tenant listed in two orders' {
            $First = Invoke-GroupRead
            $script:OrderReverse = $true
            $Second = Invoke-GroupRead
            # Reach proof: the second read really was fed in the other order.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 2
            (ConvertTo-Json -InputObject @($First.Result.Groups) -Depth 12) | Should -BeExactly (ConvertTo-Json -InputObject @($Second.Result.Groups) -Depth 12)
        }

        It 'writes the same JSON under -IncludeId, where two principals that share a name are told apart by their id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName {
                @{ 'p-1' = 'bob@contoso.com'; 'p-2' = 'bob@contoso.com'; 'p-3' = 'bob@contoso.com' }
            }
            $First = Invoke-GroupRead -IncludeId
            $script:OrderReverse = $true
            $Second = Invoke-GroupRead -IncludeId
            $FirstJson = ConvertTo-Json -InputObject @($First.Result.Groups) -Depth 12
            $FirstJson | Should -BeExactly (ConvertTo-Json -InputObject @($Second.Result.Groups) -Depth 12)
            # Non-vacuity: the three principals share one name, so the id is what decides the order of the
            # three permanent member eligibilities.
            (@($First.Result.Groups[0].eligibility | Where-Object { $_.accessType -eq 'member' -and $null -eq $_.durationDays } | ForEach-Object { $_.id }) -join '|') | Should -BeExactly 'p-1|p-2|p-3'
        }
    }

    Context 'a dynamic group writes its members as an explicit null and counts them (Sprint 11 step 10, BL-43, R-1, R-15)' {
        # A dynamic group's membership is its rule's. Its members are READ (one request, for a group read in
        # full) and COUNTED in DynamicMembers, never written: members is an explicit null, not an omitted key
        # and not named unread, and the members take no part in the PIM decision.
        BeforeEach {
            $script:DynMembers = @(@{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'u-2'; userPrincipalName = 'person2@contoso.com' })
            $script:DynOwners = @(@{ id = 'o-1'; userPrincipalName = 'person3@contoso.com' })
            $script:DynGroupType = 'Dynamic'
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = $script:DynGroupType
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    MembershipRuleProcessingState = 'On'; Members = $script:DynMembers; Owners = $script:DynOwners; PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'no eligibility' } }
        }

        It 'writes members as an explicit null, names nothing unread, and counts the members it read' {
            $Read = Invoke-GroupRead
            $Group = $Read.Result.Groups[0]
            $Group.dynamic | Should -BeTrue
            $Group.PSObject.Properties.Name | Should -Contain 'members' -Because 'an omitted key still reconciles and prunes'
            $Group.members | Should -BeNullOrEmpty
            $null -eq $Group.members | Should -BeTrue
            (ConvertTo-Json -InputObject $Group -Depth 5) | Should -Match '"members": null'
            $Group.membershipRule | Should -Be 'user.department -eq "IT"'
            @($Read.Result.Unread).Count | Should -Be 0
            @($Read.Result.Causes).Count | Should -Be 0
            @($Read.Result.DynamicMembers).Count | Should -Be 1
            $Read.Result.DynamicMembers[0].GroupId | Should -Be 'g-d'
            $Read.Result.DynamicMembers[0].Group | Should -Be 'role_sec_dynamic'
            $Read.Result.DynamicMembers[0].Members | Should -Be 2
            # Non-vacuity: the same group, assigned, writes the members and counts none.
            $script:DynGroupType = 'Assigned'
            $Control = Invoke-GroupRead
            (@($Control.Result.Groups[0].members) -join '|') | Should -BeExactly 'person1@contoso.com|person2@contoso.com'
            @($Control.Result.DynamicMembers).Count | Should -Be 0
        }

        It 'leaves the owners and the eligibility of a dynamic group as for any group' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    Members = $script:DynMembers; Owners = $script:DynOwners
                    PimEligibility = @(@{ principalId = 'p-1'; accessId = 'member'; startDateTime = $null; endDateTime = $null })
                }
            }
            $Group = (Invoke-GroupRead).Result.Groups[0]
            (@($Group.owners) -join '|') | Should -BeExactly 'person3@contoso.com'
            @($Group.eligibility).Count | Should -Be 1
            $Group.eligibility[0].principal | Should -Be 'Person Eleven'
        }

        It 'sends no assignment read for a dynamic group with members and no owners, and one for the same group assigned' {
            $script:DynOwners = @()
            $null = Invoke-GroupRead
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 0
            # Non-vacuity: the same members decide the read for an assigned group.
            $script:DynGroupType = 'Assigned'
            $null = Invoke-GroupRead
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1
        }

        It 'lets the owners of a dynamic group decide the assignment read, leaves out a held owner, and counts every member it read' {
            # u-1 holds an activation, which would be left out of an assigned group's members; here the members
            # are never written, so nothing is left out of them and the count is the read's own.
            Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment {
                [PSCustomObject]@{
                    Read = $true; Message = $null; Exception = $null
                    Value = @(
                        @{ principalId = 'u-1'; accessId = 'member'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' }
                        @{ principalId = 'o-1'; accessId = 'owner'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' }
                    )
                }
            }
            $Read = Invoke-GroupRead
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1
            $Read.Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'owners'
            @($Read.Result.PimLeftOut).Count | Should -Be 1
            $Read.Result.PimLeftOut[0].Members | Should -Be 0
            $Read.Result.PimLeftOut[0].Owners | Should -Be 1
            $Read.Result.DynamicMembers[0].Members | Should -Be 2
        }

        It 'names no members unread when the members read failed, records no cause for it, keeps its verbose line, and has no count for the group (R-24)' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'g-d': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-d' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = $script:DynGroupType
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    Owners = $script:DynOwners; PimEligibility = @()
                }
            }
            $Read = Invoke-GroupRead
            $Group = $Read.Result.Groups[0]
            $Group.PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Group.members | Should -BeTrue
            @($Read.Result.Unread) | Should -Not -Contain 'groups/role_sec_dynamic/members'
            @($Read.Result.Unread).Count | Should -Be 0
            # R-24: the failed read is no gap, so no cause is recorded for it (a cause clause must never name a
            # read that no unread entry names); the verbose line is all that remains of it.
            @($Read.Result.Causes).Count | Should -Be 0
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read members for group 'g-d': Too many requests (429)."
            @($Read.Result.DynamicMembers).Count | Should -Be 0
            # Non-vacuity: the same failure on an assigned group names the members unread and records its cause.
            $script:DynGroupType = 'Assigned'
            $Control = Invoke-GroupRead
            @($Control.Result.Unread) | Should -Contain 'groups/role_sec_dynamic/members'
            @($Control.Result.Causes).Count | Should -Be 1
            $Control.Result.Causes[0].Cause | Should -Be "Could not read members for group 'g-d': Too many requests (429)."
        }

        It 'records no cause for the dynamic group''s members read and every cause of the other reads that failed beside it, an owners read of the same dynamic group included (R-24)' {
            # Three groups, four failed reads: g-d is dynamic and its members AND owners reads failed, g-s is
            # assigned and its owners read failed, g-m is assigned and its members read failed. Only the first read
            # is no gap. The other three are, and each keeps its cause and its unread entry: the owners of the SAME
            # dynamic group (so the skip is of the members read, not of the group), another group's owners, and
            # another group's members (so the skip is of a dynamic group, found by the record's target).
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'g-d': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-d' -ErrorAction $Ea
                Write-Error -Message "Could not read owners for group 'g-d': Too many requests (429)." `
                    -ErrorId 'GroupOwnerReadFailed' -Category LimitsExceeded -TargetObject 'g-d' -ErrorAction $Ea
                Write-Error -Message "Could not read owners for group 'g-s': Forbidden (403)." `
                    -ErrorId 'GroupOwnerReadFailed' -Category PermissionDenied -TargetObject 'g-s' -ErrorAction $Ea
                Write-Error -Message "Could not read members for group 'g-m': Forbidden (403)." `
                    -ErrorId 'GroupMemberReadFailed' -Category PermissionDenied -TargetObject 'g-m' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'; PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-s'; DisplayName = 'role_sec_static'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = $script:DynMembers; PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-m'; DisplayName = 'role_sec_member'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Owners = $script:DynOwners; PimEligibility = @()
                }
            }
            $Read = Invoke-GroupRead
            @($Read.Result.Groups).Count | Should -Be 3
            @($Read.Result.Unread) | Should -Be @('groups/role_sec_dynamic/owners', 'groups/role_sec_static/owners', 'groups/role_sec_member/members')
            @($Read.Result.Causes | ForEach-Object { "$($_.Target)|$($_.Cause)" }) | Should -Be @(
                "g-d|Could not read owners for group 'g-d': Too many requests (429)."
                "g-s|Could not read owners for group 'g-s': Forbidden (403)."
                "g-m|Could not read members for group 'g-m': Forbidden (403)."
            )
            # All four failures reached the verbose stream, so the dynamic group's members read is not lost, only not a cause.
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read members for group 'g-d': Too many requests (429)."
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read owners for group 'g-d': Too many requests (429)."
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read owners for group 'g-s': Forbidden (403)."
            @($Read.Verbose) | Should -Contain "Get-OERInventory: Could not read members for group 'g-m': Forbidden (403)."
        }

        It 'finds the dynamic group by its id without regard to letter case (R-24, fix round 2)' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message "Could not read members for group 'G-D': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'G-D' -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_dynamic'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    Owners = $script:DynOwners; PimEligibility = @()
                }
            }
            $Read = Invoke-GroupRead
            @($Read.Result.Groups).Count | Should -Be 1
            @($Read.Result.Unread).Count | Should -Be 0
            @($Read.Result.Causes).Count | Should -Be 0 -Because 'a record''s target that differs from the group''s id in letter case only still names that group'
        }

        It 'looks the dynamic groups up once, so the lookup does not grow with the number of failed members reads (R-24, fix round 2)' {
            # Each listed group counts how often its GroupType is read. A healthy read reads it once per group
            # for the projection; the lookup adds one read per group, once, when any record was written, and not
            # one per record (a scan per failed record cost failures times listed groups: 15.5 s for 2000 groups
            # with every members read failing).
            $script:CountedGroups = @(foreach ($GroupId in 'g-1', 'g-2', 'g-3', 'g-4') {
                $Counted = [PSCustomObject]@{
                    Id = $GroupId; DisplayName = "role_sec_$GroupId"; Description = $null; IsAssignableToRole = $false
                    MembershipRule = $null; Members = @(); Owners = @(); PimEligibility = @(); TypeReads = 0
                }
                $Counted | Add-Member -MemberType ScriptProperty -Name GroupType -Value { $this.TypeReads++; 'Assigned' }
                $Counted
            })
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param($ErrorAction)
                $Ea = if ($null -ne $ErrorAction) { $ErrorAction } else { 'Continue' }
                foreach ($Target in $script:FailedGroupTargets) {
                    Write-Error -Message "Could not read members for group '${Target}': Too many requests (429)." `
                        -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject $Target -ErrorAction $Ea
                }
                $script:CountedGroups
            }
            $Reads = @{}
            foreach ($Run in @(@{ Name = 'none'; Targets = @() }, @{ Name = 'one'; Targets = @('g-1') }, @{ Name = 'four'; Targets = @('g-1', 'g-2', 'g-3', 'g-4') })) {
                foreach ($Counted in $script:CountedGroups) { $Counted.TypeReads = 0 }
                $script:FailedGroupTargets = $Run.Targets
                $null = Invoke-GroupRead
                $Reads[$Run.Name] = [int](($script:CountedGroups | Measure-Object -Property TypeReads -Sum).Sum)
            }
            $Reads['none'] | Should -BeGreaterThan 0 -Because 'the projection reads the type of every group, so the counter is live'
            $Reads['one'] | Should -Be ($Reads['none'] + 4) -Because 'a read with a failed record looks every listed group up once'
            $Reads['four'] | Should -Be $Reads['one'] -Because 'four failed records look the groups up no more often than one'
        }

        It 'drops the count of a dynamic group left out for a shared name' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-d'; DisplayName = 'role_sec_shared'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "IT"'
                    Members = $script:DynMembers; Owners = @(); PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-s'; DisplayName = 'ROLE_SEC_SHARED'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-o'; DisplayName = 'role_sec_other'; Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = 'user.department -eq "HR"'
                    Members = @(@{ id = 'u-9'; userPrincipalName = 'person9@contoso.com' }); Owners = @(); PimEligibility = @()
                }
            }
            $Read = Invoke-GroupRead -ExcludeSharedName
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_other')
            @($Read.Result.DynamicMembers | ForEach-Object { "$($_.GroupId):$($_.Members)" }) | Should -Be @('g-o:1')
            # Non-vacuity: without the switch both dynamic groups are counted.
            $Control = Invoke-GroupRead
            @($Control.Result.DynamicMembers | ForEach-Object { "$($_.GroupId):$($_.Members)" }) | Should -Be @('g-d:2', 'g-o:1')
        }

        It 'counts only the members that are there: a null in the list is no member' {
            $script:DynMembers = @($null, @{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' })
            $Read = Invoke-GroupRead
            $Read.Result.DynamicMembers[0].Members | Should -Be 1
        }
    }

    Context 'a PIM activation is never a standing membership (BL-125, A3)' {
        # The listing is a list of group specs: Id, Name, RoleAssignable, and the collections the read
        # can find -- Members, Owners, Eligibility -- each present only when that read succeeds. A
        # full read gets the collections attached by Get-OERGroup, a relevant-only read gets them one
        # at a time from Read-OERGroupCollection, so every test runs in both modes from one fixture.
        # $script:PimRows holds the assignment schedule instances per group id, as Graph lists them
        # (lower-case enum values, a standing membership as assigned with no end), and $script:PimFail
        # the group ids whose assignment read fails.
        BeforeEach {
            $script:PimListing = @()
            $script:PimRows = @{}
            $script:PimFail = @{}
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                param([switch]$IncludeMembers, [switch]$IncludeOwners, [switch]$IncludePimEligibility)
                foreach ($Spec in $script:PimListing) {
                    $G = [PSCustomObject]@{
                        Id = $Spec.Id; DisplayName = $Spec.Name; Description = $null; GroupType = 'Assigned'
                        IsAssignableToRole = $(if ($Spec.ContainsKey('RoleAssignable')) { $Spec.RoleAssignable } else { $true })
                        SecurityEnabled = $true
                    }
                    if ($IncludeMembers -and $Spec.ContainsKey('Members')) { $G | Add-Member -NotePropertyName Members -NotePropertyValue @($Spec.Members) }
                    if ($IncludeOwners -and $Spec.ContainsKey('Owners')) { $G | Add-Member -NotePropertyName Owners -NotePropertyValue @($Spec.Owners) }
                    if ($IncludePimEligibility -and $Spec.ContainsKey('Eligibility')) { $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @($Spec.Eligibility) }
                    $G
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupCollection {
                param($GroupId, $Collection)
                $Spec = @($script:PimListing | Where-Object { $_.Id -eq $GroupId })[0]
                $Key = @{ Members = 'Members'; Owners = 'Owners'; PimEligibility = 'Eligibility' }[$Collection]
                if ($Spec.ContainsKey($Key)) {
                    [PSCustomObject]@{ Collection = $Collection; Read = $true; Value = @($Spec[$Key]); ErrorId = $null; Message = $null; Exception = $null }
                } else {
                    [PSCustomObject]@{ Collection = $Collection; Read = $false; Value = $null; ErrorId = 'ReadFailed'; Message = "Could not read $Collection for group $($GroupId): refused (403)."; Exception = $null }
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment {
                param($GroupId)
                if ($script:PimFail.ContainsKey($GroupId)) {
                    [PSCustomObject]@{ Read = $false; Value = $null; Message = "Could not read the PIM for Groups assignments of group $($GroupId): refused (403)."; Exception = [System.Exception]::new('refused (403)') }
                } else {
                    $Rows = if ($script:PimRows.ContainsKey($GroupId)) { @($script:PimRows[$GroupId]) } else { @() }
                    [PSCustomObject]@{ Read = $true; Value = $Rows; Message = $null; Exception = $null }
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName {
                param($Id)
                $Names = @{}
                foreach ($I in @($Id)) { $Names[$I] = "name-$I" }
                $Names
            }
            # Instance rows, as Graph lists them.
            $script:Standing = { param($Id, $Access) @{ principalId = $Id; accessId = $Access; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = $null; endDateTime = $null } }
            $script:Activated = { param($Id, $Access) @{ principalId = $Id; accessId = $Access; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' } }
            $script:TimeBound = { param($Id, $Access) @{ principalId = $Id; accessId = $Access; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = '2026-10-01T00:00:00Z'; endDateTime = '2026-12-31T00:00:00Z' } }
            # One read in the mode the test names.
            $script:ReadIn = { param([string]$Mode, [switch]$ExcludeSharedName) Invoke-GroupRead -RelevantOnly:($Mode -eq 'relevant-only') -ExcludeSharedName:$ExcludeSharedName }
            # The projection of one group, by name.
            $script:ProjectionOf = { param($Read, [string]$Name) @($Read.Result.Groups | Where-Object { $_.displayName -eq $Name })[0] }
        }

        It 'leaves an activated member and an activated owner out, writes the standing member and owner, and names the group in PimLeftOut (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'U-ACT'; userPrincipalName = 'person2@contoso.com' })
                    Owners = @(@{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' }, @{ id = 'o-act'; userPrincipalName = 'person7@contoso.com' })
                    Eligibility = @() }
            )
            # The activated member's id is written in upper case on the member and lower case in the
            # instance: ids are compared without regard to letter case.
            $script:PimRows['g-pim'] = @(
                (& $script:Standing 'u-std' 'member'), (& $script:Activated 'u-act' 'member'),
                (& $script:Standing 'o-std' 'owner'), (& $script:Activated 'o-act' 'owner')
            )
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.members | Should -Be @('person1@contoso.com')
            $Group.owners | Should -Be @('person6@contoso.com')
            @($Read.Result.PimLeftOut).Count | Should -Be 1
            $Entry = @($Read.Result.PimLeftOut)[0]
            @($Entry.PSObject.Properties.Name) | Should -Be @('GroupId', 'Group', 'Members', 'Owners', 'Basis')
            $Entry.GroupId | Should -BeExactly 'g-pim'
            $Entry.Group | Should -BeExactly 'role_sec_pim'
            $Entry.Members | Should -Be 1
            $Entry.Owners | Should -Be 1
            $Entry.Basis | Should -BeExactly 'Assignments'
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            @($Read.Verbose) | Should -Contain "Get-OERInventory: group 'role_sec_pim': 1 member(s) and 1 owner(s) left out, since PIM for Groups holds their access."
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-pim' }
        }

        It 'leaves a time-bound active member out (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'u-tb'; userPrincipalName = 'person3@contoso.com' })
                    Owners = @(); Eligibility = @() }
            )
            $script:PimRows['g-pim'] = @((& $script:Standing 'u-std' 'member'), (& $script:TimeBound 'u-tb' 'member'))
            $Read = & $script:ReadIn $Mode
            (& $script:ProjectionOf $Read 'role_sec_pim').members | Should -Be @('person1@contoso.com')
            @($Read.Result.PimLeftOut).Count | Should -Be 1
            $Read.Result.PimLeftOut[0].Members | Should -Be 1
            $Read.Result.PimLeftOut[0].Owners | Should -Be 0
            $Read.Result.PimLeftOut[0].Basis | Should -BeExactly 'Assignments'
        }

        It 'writes a standing member that is also eligible for member access (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-elig'; userPrincipalName = 'person5@contoso.com' })
                    Owners = @(); Eligibility = @(@{ principalId = 'u-elig'; accessId = 'member'; startDateTime = $null; endDateTime = $null }) }
            )
            $script:PimRows['g-pim'] = @(& $script:Standing 'u-elig' 'member')
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.members | Should -Be @('person5@contoso.com')
            @($Group.eligibility).Count | Should -Be 1
            @($Read.Result.PimLeftOut).Count | Should -Be 0
            # Reach proof: the assignments were read, and found the member standing.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-pim' }
        }

        It 'writes a principal standing as member and activated as owner under members, and leaves it out of owners (Review Focus 2) (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-both'; userPrincipalName = 'person4@contoso.com' })
                    Owners = @(@{ id = 'u-both'; userPrincipalName = 'person4@contoso.com' }, @{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' })
                    Eligibility = @() }
            )
            $script:PimRows['g-pim'] = @(
                (& $script:Standing 'u-both' 'member'), (& $script:Activated 'u-both' 'owner'), (& $script:Standing 'o-std' 'owner')
            )
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.members | Should -Be @('person4@contoso.com')
            $Group.owners | Should -Be @('person6@contoso.com')
            $Read.Result.PimLeftOut[0].Members | Should -Be 0
            $Read.Result.PimLeftOut[0].Owners | Should -Be 1
        }

        It 'names the assignments unread with the cause, and leaves out only the members and owners eligible for the same access, when the assignment read fails (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            # u-oe is eligible for OWNER access only, so as a member it is written: access is matched.
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(
                        @{ id = 'u-elig'; userPrincipalName = 'person5@contoso.com' }
                        @{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }
                        @{ id = 'u-oe'; userPrincipalName = 'person8@contoso.com' }
                    )
                    Owners = @(@{ id = 'o-elig'; userPrincipalName = 'person9@contoso.com' }, @{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' })
                    Eligibility = @(
                        @{ principalId = 'U-ELIG'; accessId = 'member' }
                        @{ principalId = 'u-oe'; accessId = 'owner' }
                        @{ principalId = 'o-elig'; accessId = 'owner' }
                    ) }
            )
            $script:PimFail['g-pim'] = $true
            $Cause = 'Could not read the PIM for Groups assignments of group g-pim: refused (403).'
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.members | Should -Be @('person1@contoso.com', 'person8@contoso.com')
            $Group.owners | Should -Be @('person6@contoso.com')
            @($Read.Result.Unread) | Should -Be @('groups/role_sec_pim/pimAssignments')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -BeExactly $Cause
            $Read.Result.Causes[0].Target | Should -BeExactly 'g-pim'
            @($Read.Verbose) | Should -Contain "Get-OERInventory: $Cause"
            @($Read.Result.PimLeftOut).Count | Should -Be 1
            $Read.Result.PimLeftOut[0].Members | Should -Be 1
            $Read.Result.PimLeftOut[0].Owners | Should -Be 1
            $Read.Result.PimLeftOut[0].Basis | Should -BeExactly 'Eligibility'
            # On the eligibility basis they are eligible, not known to be held, and the line says so.
            @($Read.Verbose) | Should -Contain "Get-OERInventory: group 'role_sec_pim': 1 member(s) and 1 owner(s) left out, since they are eligible for the same access in PIM for Groups and the group's PIM assignments could not be read."
            @($Read.Verbose | Where-Object { $_ -like '*holds their access*' }).Count | Should -Be 0
        }

        It 'writes members as an explicit null and omits owners when neither the assignments nor the eligibility could be read (Review Focus 1) (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            # The members and owners reads succeeded: without the assignments and the eligibility
            # nothing can tell a standing member from an activation, so neither is written in full.
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'u-act'; userPrincipalName = 'person2@contoso.com' })
                    Owners = @(@{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' }) }
            )
            $script:PimFail['g-pim'] = $true
            $Cause = 'Could not read the PIM for Groups assignments of group g-pim: refused (403).'
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Group.members | Should -BeTrue
            $Group.PSObject.Properties.Name | Should -Not -Contain 'owners'
            @($Read.Result.Unread) | Should -Be @(
                'groups/role_sec_pim/pimAssignments'
                'groups/role_sec_pim/members'
                'groups/role_sec_pim/owners'
                'groups/role_sec_pim/eligibility'
            )
            # The eligibility read's own cause comes first under -RelevantOnly, where the reader read it.
            $ExpectedCauses = if ($Mode -eq 'relevant-only') {
                @('Could not read PimEligibility for group g-pim: refused (403).', $Cause)
            } else {
                @($Cause)
            }
            @($Read.Result.Causes | ForEach-Object { $_.Cause }) | Should -Be $ExpectedCauses
            @($Read.Result.Causes | ForEach-Object { $_.Target }) | Should -Be @($ExpectedCauses | ForEach-Object { 'g-pim' })
            @($Read.Result.PimLeftOut).Count | Should -Be 0
        }

        It 'writes a collection read empty as read, and names only the one holding entries unread, when neither the assignments nor the eligibility could be read (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            # An empty read cannot hold an activation, so the undecided form applies to the owners only.
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @()
                    Owners = @(@{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' }) }
            )
            $script:PimFail['g-pim'] = $true
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.PSObject.Properties.Name | Should -Contain 'members'
            $null -ne $Group.members | Should -BeTrue -Because 'an empty membership that was read is written as read, not as unread'
            @($Group.members).Count | Should -Be 0
            $Group.PSObject.Properties.Name | Should -Not -Contain 'owners'
            @($Read.Result.Unread) | Should -Be @(
                'groups/role_sec_pim/pimAssignments'
                'groups/role_sec_pim/owners'
                'groups/role_sec_pim/eligibility'
            )
            @($Read.Result.Unread) | Should -Not -Contain 'groups/role_sec_pim/members'
            @($Read.Result.PimLeftOut).Count | Should -Be 0
            # Reach proof: the assignments were asked for, since the owners hold an entry.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-pim' }
        }

        It 'names only the members unread, not owners read empty, when neither the assignments nor the eligibility could be read (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            # The mirror of the test above: the members hold an entry and are not written, the owners
            # were read empty and stay what an empty owner set always is -- omitted, and not named.
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' })
                    Owners = @() }
            )
            $script:PimFail['g-pim'] = $true
            $Read = & $script:ReadIn $Mode
            $Group = & $script:ProjectionOf $Read 'role_sec_pim'
            $Group.PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Group.members | Should -BeTrue
            $Group.PSObject.Properties.Name | Should -Not -Contain 'owners'
            @($Read.Result.Unread) | Should -Be @(
                'groups/role_sec_pim/pimAssignments'
                'groups/role_sec_pim/members'
                'groups/role_sec_pim/eligibility'
            )
            @($Read.Result.Unread) | Should -Not -Contain 'groups/role_sec_pim/owners'
        }

        It 'leaves nobody out for an instance whose access type is neither member nor owner, and still returns the read (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            # Graph's accessId enum has unknownFutureValue. Get-OERGroupPimHeldAccess passes it through,
            # and it names no collection here: the standing member is written, and the read does not stop.
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' })
                    Owners = @(); Eligibility = @() }
            )
            $script:PimRows['g-pim'] = @(
                (& $script:Standing 'u-std' 'member')
                (& $script:Activated 'u-std' 'unknownFutureValue')
            )
            $Read = & $script:ReadIn $Mode
            $Read.Result | Should -Not -BeNullOrEmpty
            $Read.Result.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.InventoryGroupRead'
            (& $script:ProjectionOf $Read 'role_sec_pim').members | Should -Be @('person1@contoso.com')
            @($Read.Result.PimLeftOut).Count | Should -Be 0
            @($Read.Result.Causes).Count | Should -Be 0
            $Read.Result.Unread.Count | Should -Be 0
            # Reach proof: the assignments were read, so the unknown access type reached the projection.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-pim' }
        }

        It 'projects exactly what an empty assignment read projects when every member and owner is standing (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-pim'; Name = 'role_sec_pim'
                    Members = @(@{ id = 'u-std'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'dev-1'; displayName = 'DEVICE-0001' })
                    Owners = @(@{ id = 'o-std'; userPrincipalName = 'person6@contoso.com' })
                    Eligibility = @(@{ principalId = 'p-1'; accessId = 'member' }) }
            )
            $Baseline = & $script:ReadIn $Mode
            $script:PimRows['g-pim'] = @((& $script:Standing 'u-std' 'member'), (& $script:Standing 'dev-1' 'member'), (& $script:Standing 'o-std' 'owner'))
            $Read = & $script:ReadIn $Mode
            (ConvertTo-Json -InputObject @($Read.Result.Groups) -Depth 8) | Should -BeExactly (ConvertTo-Json -InputObject @($Baseline.Result.Groups) -Depth 8)
            (& $script:ProjectionOf $Read 'role_sec_pim').members | Should -Be @('dev-1', 'person1@contoso.com')
            @($Read.Result.PimLeftOut).Count | Should -Be 0
            $Read.Result.Unread.Count | Should -Be 0
        }

        It 'returns PimLeftOut as a real array, empty when nothing was left out' {
            $script:PimListing = @(@{ Id = 'g-pim'; Name = 'role_sec_pim'; Members = @(); Owners = @(); Eligibility = @() })
            $Read = Invoke-GroupRead
            $Read.Result.PSObject.Properties.Name | Should -Contain 'PimLeftOut'
            , $Read.Result.PimLeftOut | Should -BeOfType ([object[]])
            $Read.Result.PimLeftOut.Count | Should -Be 0
        }

        It 'reads the assignments once per group with members or owners read, and never for a group whose members and owners are both empty or both unread (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-a'; Name = 'role_sec_a'; Members = @(@{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' }); Owners = @(); Eligibility = @() }
                @{ Id = 'g-b'; Name = 'role_sec_b'; Members = @(); Owners = @(@{ id = 'o-1'; userPrincipalName = 'person6@contoso.com' }); Eligibility = @() }
                @{ Id = 'g-c'; Name = 'role_sec_c'; Members = @(); Owners = @(); Eligibility = @() }
                @{ Id = 'g-d'; Name = 'role_sec_d'; Eligibility = @() }
            )
            $Read = & $script:ReadIn $Mode
            # Reach proof: all four groups were projected.
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_a', 'role_sec_b', 'role_sec_c', 'role_sec_d')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 2
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-a' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-b' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Times 0 -ParameterFilter { $GroupId -eq 'g-c' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Times 0 -ParameterFilter { $GroupId -eq 'g-d' }
            # The group with both collections unread keeps the form it had: members null, owners omitted,
            # and no pimAssignments entry, since nothing was asked.
            @($Read.Result.Unread) | Should -Not -Contain 'groups/role_sec_d/pimAssignments'
            @($Read.Result.Unread) | Should -Contain 'groups/role_sec_d/members'
        }

        It 'reads no assignments for a group -RelevantOnly does not keep' {
            $script:PimListing = @(
                @{ Id = 'g-a'; Name = 'role_sec_a'; Members = @(@{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' }); Owners = @(); Eligibility = @() }
                @{ Id = 'g-x'; Name = 'plain_x'; RoleAssignable = $false; Members = @(@{ id = 'u-9'; userPrincipalName = 'person2@contoso.com' }); Owners = @(); Eligibility = @() }
            )
            Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse {
                param($GroupId)
                [PSCustomObject]@{ InUse = ($GroupId -ne 'g-x'); Reason = 'x' }
            }
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('role_sec_a')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Times 0 -ParameterFilter { $GroupId -eq 'g-x' }
            # Reach proof: the kept group's assignments were read.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'g-a' }
        }

        It 'drops the PimLeftOut entry of a group -ExcludeSharedName leaves out (<Mode>)' -ForEach @(
            @{ Mode = 'full' }
            @{ Mode = 'relevant-only' }
        ) {
            $script:PimListing = @(
                @{ Id = 'g-s1'; Name = 'Shared'; Members = @(@{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' }); Owners = @(); Eligibility = @() }
                @{ Id = 'g-s2'; Name = 'shared'; Members = @(@{ id = 'u-2'; userPrincipalName = 'person2@contoso.com' }); Owners = @(); Eligibility = @() }
                @{ Id = 'g-k'; Name = 'kept'; Members = @(@{ id = 'u-3'; userPrincipalName = 'person3@contoso.com' }); Owners = @(); Eligibility = @() }
            )
            $script:PimRows['g-s1'] = @(& $script:Activated 'u-1' 'member')
            $script:PimRows['g-k'] = @(& $script:Activated 'u-3' 'member')
            $Read = & $script:ReadIn $Mode -ExcludeSharedName
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('kept')
            @($Read.Result.PimLeftOut | ForEach-Object { $_.GroupId }) | Should -Be @('g-k')
            # The control: without the switch the shared group's entry is there.
            $Control = & $script:ReadIn $Mode
            @($Control.Result.PimLeftOut | ForEach-Object { $_.GroupId }) | Should -Be @('g-s1', 'g-k')
        }
    }
}

Describe 'Get-OERInventoryGroup -RelevantOnly, driven through the transport' {
    # Only the sign-in and the transport are mocked. Get-OERGroup, Read-OERGroupCollection,
    # Get-OERGroupRelation, Test-OERGroupPimInUse, Get-OERPimGroupPolicyId, Get-OERGroupPimPolicy and
    # Resolve-OERPrincipalName are the real ones, so every request a group costs reaches the one
    # Invoke-OERGraphRequest mock below and is counted there. ONE mock with a dispatcher on the URI,
    # not a filtered mock per request: an unmatched filtered mock throws, and a filtered mock beats
    # an unfiltered one, so a set of them could hide a request nobody expected. The dispatcher throws
    # on a request it has no answer for, so an unexpected request fails the test instead.
    BeforeAll {
        $script:IdRa = '11111111-1111-1111-1111-111111111111'
        $script:IdEl = '22222222-2222-2222-2222-222222222222'
        $script:IdMod = '33333333-3333-3333-3333-333333333333'
        $script:IdPlain = '44444444-4444-4444-4444-444444444444'
        $script:IdSync = '55555555-5555-5555-5555-555555555555'
        $script:IdDyn = '66666666-6666-6666-6666-666666666666'
        $script:EligPrincipal = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'

        # The fixture tenant, in list order. Eligibility is a list of principal ids, or 'NotSupported'
        # (400 ResourceTypeNotSupported: a group PIM for Groups cannot manage). Policy is 'Untouched',
        # 'Modified' (one policy carries a lastModifiedDateTime) or 'NotSupported'.
        $script:NewTenant = {
            @(
                @{ Id = $script:IdRa; Name = 'G-RA'; RoleAssignable = $true; Synced = $false; Dynamic = $false
                    Member = 'person1@contoso.com'; Owner = 'person2@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                @{ Id = $script:IdEl; Name = 'G-EL'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                    Member = 'person3@contoso.com'; Owner = 'person4@contoso.com'; Eligibility = @($script:EligPrincipal); Policy = 'Untouched' }
                @{ Id = $script:IdMod; Name = 'G-MOD'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                    Member = 'person5@contoso.com'; Owner = 'person6@contoso.com'; Eligibility = @(); Policy = 'Modified' }
                @{ Id = $script:IdPlain; Name = 'G-PLAIN'; RoleAssignable = $false; Synced = $false; Dynamic = $false
                    Member = 'person7@contoso.com'; Owner = 'person8@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                @{ Id = $script:IdSync; Name = 'G-SYNC'; RoleAssignable = $false; Synced = $true; Dynamic = $false
                    Member = 'person9@contoso.com'; Owner = 'person10@contoso.com'; Eligibility = @(); Policy = 'Untouched' }
                @{ Id = $script:IdDyn; Name = 'G-DYN'; RoleAssignable = $false; Synced = $false; Dynamic = $true
                    Member = 'person11@contoso.com'; Owner = 'person12@contoso.com'; Eligibility = 'NotSupported'; Policy = 'NotSupported' }
            )
        }

        # Answers one request the way Microsoft Graph would for the fixture tenant, and records it.
        # $script:Refuse holds '<kind>:<group id>' keys (members, owners, eligibility, criterion) whose
        # request is refused with a 403 carrying the key's text.
        $script:FakeGraph = {
            param([string]$Method, [string]$Uri, [hashtable]$Body, [string[]]$ExpectedErrorCode)
            $Verb = if ($Method) { $Method } else { 'GET' }
            $script:GraphCalls.Add("$Verb $Uri")
            $GroupOf = { param([string]$Id) @($script:Tenant | Where-Object { $_.Id -eq $Id })[0] }
            $RefuseIfAsked = {
                param([string]$Key)
                if ($script:Refuse.ContainsKey($Key)) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new($script:Refuse[$Key]), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $Key)
                }
            }
            $NotSupported = {
                if ($ExpectedErrorCode -notcontains 'ResourceTypeNotSupported') {
                    throw "The fake tenant answers ResourceTypeNotSupported, which the request did not declare: $Verb $Uri"
                }
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceTypeNotSupported'; StatusCode = 400; Message = 'ResourceTypeNotSupported'; Uri = $Uri }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }

            if ($Verb -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds') {
                return [PSCustomObject]@{ value = @(foreach ($PrincipalId in @($Body.ids)) { @{ id = $PrincipalId; userPrincipalName = 'person13@contoso.com' } }) }
            }
            if ($Uri.StartsWith('v1.0/groups?') -or $Uri -eq 'v1.0/groups') {
                # The answer ignores the filter, which is how a filter widened past the security-enabled
                # scope answers: every group of the fixture tenant is listed. A group marks its own
                # securityEnabled: a boolean, a text or null as given, or the property left out when the
                # value is the text '<missing>'.
                return [PSCustomObject]@{
                    value = @(foreach ($G in $script:Tenant) {
                            $Row = @{
                                id                            = $G.Id
                                displayName                   = $G.Name
                                description                   = "$($G.Name) team"
                                mailNickname                  = $G.Name.Replace('-', '').ToLowerInvariant()
                                securityEnabled               = $true
                                isAssignableToRole            = $G.RoleAssignable
                                groupTypes                    = [string[]]@(if ($G.Dynamic) { 'DynamicMembership' })
                                membershipRule                = $(if ($G.Dynamic) { 'user.department -eq "IT"' } else { $null })
                                membershipRuleProcessingState = $(if ($G.Dynamic) { 'On' } else { $null })
                                onPremisesSyncEnabled         = $(if ($G.Synced) { $true } else { $null })
                            }
                            if ($G.ContainsKey('SecurityEnabled')) {
                                if ($G.SecurityEnabled -is [string] -and $G.SecurityEnabled -ceq '<missing>') { $Row.Remove('securityEnabled') }
                                else { $Row.securityEnabled = $G.SecurityEnabled }
                            }
                            $Row
                        })
                }
            }
            if ($Uri -match '^v1\.0/groups/(?<Id>[^/]+)/(?<Rel>members|owners)(?<Typed>/microsoft\.graph\.servicePrincipal)?$') {
                $Id = $Matches.Id
                $Rel = $Matches.Rel
                $Typed = [bool]$Matches.Typed
                & $RefuseIfAsked "$($Rel):$Id"
                if ($Typed) { return [PSCustomObject]@{ value = @() } }
                $G = & $GroupOf $Id
                $Upn = if ($Rel -eq 'members') { $G.Member } else { $G.Owner }
                return [PSCustomObject]@{ value = @(@{ id = "u-$Rel-$($G.Name)"; displayName = $Upn; userPrincipalName = $Upn; '@odata.type' = '#microsoft.graph.user' }) }
            }
            if ($Uri.StartsWith('beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?') -and $Uri -match "groupId eq '(?<Id>[^']*)'") {
                $Id = $Matches.Id
                & $RefuseIfAsked "eligibility:$Id"
                $G = & $GroupOf $Id
                if ($G.Eligibility -is [string]) { return (& $NotSupported) }
                return [PSCustomObject]@{ value = @(foreach ($PrincipalId in @($G.Eligibility)) { @{ principalId = $PrincipalId; accessId = 'member'; startDateTime = $null; endDateTime = $null } }) }
            }
            if ($Uri.StartsWith('beta/policies/roleManagementPolicies?') -and $Uri -match "scopeId eq '(?<Id>[^']*)'") {
                $Id = $Matches.Id
                & $RefuseIfAsked "criterion:$Id"
                $G = & $GroupOf $Id
                if ($G.Policy -eq 'NotSupported') { return (& $NotSupported) }
                $Modified = if ($G.Policy -eq 'Modified') { '2026-09-01T00:00:00Z' } else { $null }
                return [PSCustomObject]@{
                    value = @(
                        @{ id = "Group_$($Id)_member"; lastModifiedDateTime = $Modified; lastModifiedBy = $null }
                        @{ id = "Group_$($Id)_owner"; lastModifiedDateTime = $null; lastModifiedBy = $null }
                    )
                }
            }
            if ($Uri.StartsWith('beta/policies/roleManagementPolicyAssignments?') -and $Uri -match "scopeId eq '(?<Id>[^']*)'") {
                $Id = $Matches.Id
                $G = & $GroupOf $Id
                if ($G.Policy -eq 'NotSupported') { return (& $NotSupported) }
                return [PSCustomObject]@{
                    value = @(
                        @{ roleDefinitionId = 'member'; policyId = "Group_$($Id)_member" }
                        @{ roleDefinitionId = 'owner'; policyId = "Group_$($Id)_owner" }
                    )
                }
            }
            if ($Uri -match '^beta/policies/roleManagementPolicies/Group_[^/]+/rules$') {
                return [PSCustomObject]@{
                    value = @(
                        @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                        @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                    )
                }
            }
            throw "The fake tenant has no answer for: $Verb $Uri"
        }

        # The requests recorded so far whose method and URI match a -like pattern.
        function Get-GraphCallCount {
            param([string]$Like)
            @($script:GraphCalls | Where-Object { $_ -like $Like }).Count
        }
    }

    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        $script:Tenant = & $script:NewTenant
        $script:Refuse = @{}
        $script:GraphCalls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param([string]$Method, [string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
            & $script:FakeGraph -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode
        }
        # BL-125 (A3): the PIM for Groups assignment read is answered here, above the transport, as a
        # successful read that lists nothing, so the request counts below stay the ones they were. The
        # read's own requests are counted in the Describe after this one, through the real reader.
        Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupPimAssignment {
            [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
        }
    }

    Context 'which groups are read in full' {
        It 'costs a group it does not keep exactly two requests, the eligibility and the criterion, and reads no members or owners of it' {
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Not -Contain 'G-PLAIN'

            # G-PLAIN: no eligibility, untouched policies.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like '*eligibilityScheduleInstances*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like 'v1.0/groups/44444444-4444-4444-4444-444444444444/*' }

            # G-SYNC without -IncludeSyncedGroups: synchronized, but not kept on that account.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*55555555-5555-5555-5555-555555555555*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like '*eligibilityScheduleInstances*55555555-5555-5555-5555-555555555555*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*55555555-5555-5555-5555-555555555555*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like 'v1.0/groups/55555555-5555-5555-5555-555555555555/*' }

            # G-DYN: both reads answer ResourceTypeNotSupported, which decides "not in use".
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 2 -ParameterFilter { $Uri -like '*66666666-6666-6666-6666-666666666666*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like '*eligibilityScheduleInstances*66666666-6666-6666-6666-666666666666*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*66666666-6666-6666-6666-666666666666*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like 'v1.0/groups/66666666-6666-6666-6666-666666666666/*' }
        }

        It 'returns the groups it keeps, in list order, with their members and owners, and nothing unread' {
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            $ByName = @{}
            foreach ($G in $Read.Result.Groups) { $ByName[$G.displayName] = $G }
            $ByName['G-RA'].members | Should -Be @('person1@contoso.com')
            $ByName['G-RA'].owners | Should -Be @('person2@contoso.com')
            $ByName['G-EL'].members | Should -Be @('person3@contoso.com')
            $ByName['G-EL'].owners | Should -Be @('person4@contoso.com')
            $ByName['G-MOD'].members | Should -Be @('person5@contoso.com')
            $ByName['G-MOD'].owners | Should -Be @('person6@contoso.com')
            # Eligibility and pimPolicy are projected exactly as a full read projects them.
            $ByName['G-EL'].eligibility[0].principal | Should -Be 'person13@contoso.com'
            $ByName['G-EL'].pimPolicy.member.activationMaxHours | Should -Be 8
            $ByName['G-MOD'].pimPolicy.owner.activationMaxHours | Should -Be 8
            @($ByName['G-RA'].eligibility).Count | Should -Be 0
            $ByName['G-RA'].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            # A kept role-assignable group: the eligibility, the members and the owners (two requests
            # each: the untyped and the service principal read), and the criterion in the projection.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 6 -ParameterFilter { $Uri -like '*11111111-1111-1111-1111-111111111111*' }
        }

        It 'asks the criterion once for a group decided before the projection, and the projection reuses the answer' {
            $Read = Invoke-GroupRead -RelevantOnly
            # G-MOD is kept on the criterion alone (a modified policy), so the criterion is asked
            # before the projection, and the projection must not ask it again.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*33333333-3333-3333-3333-333333333333*' }
            @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-MOD' }).Count | Should -Be 1
            ($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-MOD' }).pimPolicy.member.activationMaxHours | Should -Be 8
        }

        It 'keeps a synchronized group under -IncludeSyncedGroups and reads its members and owners' {
            $Read = Invoke-GroupRead -RelevantOnly -IncludeSyncedGroups
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD', 'G-SYNC')
            $Synced = $Read.Result.Groups | Where-Object { $_.displayName -eq 'G-SYNC' }
            $Synced.onPremisesSynced | Should -BeTrue
            $Synced.members | Should -Be @('person9@contoso.com')
            $Synced.owners | Should -Be @('person10@contoso.com')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/55555555-5555-5555-5555-555555555555/members' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 6 -ParameterFilter { $Uri -like '*55555555-5555-5555-5555-555555555555*' }
            # The switch keeps synchronized groups only: G-PLAIN is still not kept.
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Not -Contain 'G-PLAIN'
        }
    }

    Context 'a group whose relevance could not be read is read in full (R2)' {
        It 'reads a group whose eligibility read was refused in full, and names its eligibility and pimPolicy unread with the cause' {
            $script:Refuse["eligibility:$script:IdPlain"] = 'Insufficient privileges to complete the operation'
            $Read = Invoke-GroupRead -RelevantOnly
            $Plain = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-PLAIN' })
            $Plain.Count | Should -Be 1 -Because 'a group whose relevance is unknown is read as before, never dropped'
            $Plain[0].members | Should -Be @('person7@contoso.com')
            $Plain[0].owners | Should -Be @('person8@contoso.com')
            $Plain[0].PSObject.Properties.Name | Should -Not -Contain 'eligibility'
            $Plain[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            @($Read.Result.Unread) | Should -Be @('groups/G-PLAIN/eligibility', 'groups/G-PLAIN/pimPolicy')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be 'Could not read PIM eligibility for group 44444444-4444-4444-4444-444444444444: Insufficient privileges to complete the operation. The PimEligibility property is omitted rather than reported as empty.'
            $Read.Result.Causes[0].Target | Should -Be $script:IdPlain
            @($Read.Verbose) | Should -Contain "Get-OERInventory: $($Read.Result.Causes[0].Cause)"
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/44444444-4444-4444-4444-444444444444/members' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/44444444-4444-4444-4444-444444444444/owners' }
            # The criterion decided ahead is reused by the projection, not asked a second time.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*44444444-4444-4444-4444-444444444444*' }
            # The eligibility, the criterion, and two requests each for members and owners.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 6 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
        }

        It 'reads a group whose criterion was refused in full, and names its pimPolicy unread with the cause' {
            $script:Refuse["criterion:$script:IdPlain"] = 'Insufficient privileges to complete the operation.'
            $Read = Invoke-GroupRead -RelevantOnly
            $Plain = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-PLAIN' })
            $Plain.Count | Should -Be 1
            $Plain[0].members | Should -Be @('person7@contoso.com')
            @($Plain[0].eligibility).Count | Should -Be 0
            $Plain[0].PSObject.Properties.Name | Should -Contain 'eligibility'
            $Plain[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            @($Read.Result.Unread) | Should -Be @('groups/G-PLAIN/pimPolicy')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -Be "Could not determine whether group '44444444-4444-4444-4444-444444444444' uses PIM for Groups: Insufficient privileges to complete the operation."
            $Read.Result.Causes[0].Target | Should -Be $script:IdPlain
            # A criterion that failed is not asked again in the projection either.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'beta/policies/roleManagementPolicies[?]*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 6 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
        }

        It 'reads a dynamic group whose criterion was refused in full, asks its members once, counts them, and writes members as an explicit null (BL-43, R-15)' {
            $script:Refuse["criterion:$script:IdDyn"] = 'Insufficient privileges to complete the operation.'
            $script:Refuse["criterion:$script:IdPlain"] = 'Insufficient privileges to complete the operation.'
            $Read = Invoke-GroupRead -RelevantOnly
            $Dyn = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-DYN' })
            $Dyn.Count | Should -Be 1 -Because 'a group whose relevance is unknown is read in full, a dynamic one too'
            $Dyn[0].PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Dyn[0].members | Should -BeTrue
            # The group's criterion is what could not be read; its members are no gap.
            @($Read.Result.Unread) | Should -Be @('groups/G-PLAIN/pimPolicy', 'groups/G-DYN/pimPolicy')
            @($Read.Result.DynamicMembers | ForEach-Object { "$($_.GroupId):$($_.Group):$($_.Members)" }) | Should -Be @("$($script:IdDyn):G-DYN:1")
            # The request pattern is the one it was: the members of a group read in full, once.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/66666666-6666-6666-6666-666666666666/members' }
            # Non-vacuity: the assigned group read the same way writes its members, and none is counted for it.
            $Plain = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-PLAIN' })
            @($Plain[0].members) | Should -Be @('person7@contoso.com')
        }

        It 'records no cause for the refused members read of a dynamic group read in full, and every cause of the other refused reads (BL-43, R-24)' {
            # G-DYN is read in full since its criterion is refused, and its members read is refused too, and so is
            # its owners read, which is a gap. G-PLAIN is the same shape, assigned: its members read is refused as
            # well, and is a gap.
            $script:Refuse["criterion:$script:IdDyn"] = 'Insufficient privileges to complete the operation.'
            $script:Refuse["criterion:$script:IdPlain"] = 'Insufficient privileges to complete the operation.'
            $script:Refuse["members:$script:IdDyn"] = 'Forbidden (403)'
            $script:Refuse["owners:$script:IdDyn"] = 'Forbidden (403)'
            $script:Refuse["members:$script:IdPlain"] = 'Forbidden (403)'
            $Read = Invoke-GroupRead -RelevantOnly
            $Dyn = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-DYN' })
            $Dyn.Count | Should -Be 1
            $Dyn[0].PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Dyn[0].members | Should -BeTrue
            @($Read.Result.DynamicMembers).Count | Should -Be 0 -Because 'a members read that failed has no count'
            # Reach proof: the members read of both groups was sent and refused.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/66666666-6666-6666-6666-666666666666/members' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/44444444-4444-4444-4444-444444444444/members' }
            # The gaps are the two criteria, the assigned group's members and the dynamic group's owners, and no
            # members entry of G-DYN.
            @($Read.Result.Unread) | Should -Be @('groups/G-PLAIN/members', 'groups/G-PLAIN/pimPolicy', 'groups/G-DYN/owners', 'groups/G-DYN/pimPolicy')
            # The causes of G-DYN: its criterion and its owners read, and none for its members. The assigned group's
            # failed members read is the only cause of that read.
            $DynCauses = @($Read.Result.Causes | Where-Object { $_.Target -eq $script:IdDyn } | ForEach-Object { $_.Cause })
            $DynCauses.Count | Should -Be 2
            @($DynCauses | Where-Object { $_ -like 'Could not read members*' }).Count | Should -Be 0
            @($DynCauses | Where-Object { $_ -like 'Could not read owners for group*' }).Count | Should -Be 1
            @($DynCauses | Where-Object { $_ -like 'Could not determine whether group*uses PIM for Groups*' }).Count | Should -Be 1
            @($Read.Result.Causes | Where-Object { $_.Cause -like 'Could not read members for group*' } | ForEach-Object { $_.Target }) | Should -Be @($script:IdPlain)
            # The verbose stream still carries the dynamic group's failed read.
            @($Read.Verbose | Where-Object { $_ -like "Get-OERInventory: Could not read members for group $script:IdDyn*" }).Count | Should -Be 1
        }

        It 'drops no group when the eligibility of every group could not be read (Review Focus 1)' {
            foreach ($G in $script:Tenant) { $script:Refuse["eligibility:$($G.Id)"] = 'Too many requests (429)' }
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD', 'G-PLAIN', 'G-SYNC', 'G-DYN')
            foreach ($G in $script:Tenant) {
                Get-GraphCallCount -Like "GET v1.0/groups/$($G.Id)/members" | Should -Be 1 -Because "$($G.Name) is read in full"
                Get-GraphCallCount -Like "GET v1.0/groups/$($G.Id)/owners" | Should -Be 1 -Because "$($G.Name) is read in full"
                @($Read.Result.Unread) | Should -Contain "groups/$($G.Name)/eligibility"
            }
        }
    }

    Context 'shared names' {
        BeforeEach {
            $script:Tenant[0].Name = 'Admins'     # G-RA, kept
            $script:Tenant[3].Name = 'admins'     # G-PLAIN, not kept
        }

        It 'leaves out every group whose name another shares, and names the name once with its first spelling and the cause (Review Focus 4)' {
            $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName
            $Expected = InModuleScope Omnicit.EntraRBAC { Get-OERSharedNameCause -Path 'groups/Admins' -Count 2 }
            $Expected | Should -BeLike '2 live objects share the name groups/Admins *'
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD')
            @($Read.Result.Unread) | Should -Be @('groups/Admins')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -BeExactly $Expected
            # BL-156: registered with a blank Target, so Format-OERUnreadCauseClause keys it on its full text.
            [string]$Read.Result.Causes[0].Target | Should -BeExactly ''
            @($Read.Verbose) | Should -Contain "Get-OERInventory: $Expected"
            # BL-131: the name with its count, once.
            @($Read.Result.SharedNames).Count | Should -Be 1
            $Read.Result.SharedNames[0].Section | Should -BeExactly 'groups'
            $Read.Result.SharedNames[0].Name | Should -BeExactly 'Admins'
            $Read.Result.SharedNames[0].Count | Should -Be 2
        }

        It 'leaves out the shared name in a full read too' {
            $Read = Invoke-GroupRead -ExcludeSharedName
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD', 'G-SYNC', 'G-DYN')
            @($Read.Result.Unread) | Should -Be @('groups/Admins')
        }

        It 'registers each shared name as a cause of its own, so two names of one count both reach the causes clause (BL-156)' {
            # Two names two groups each share. The cause text carries the name, and a cause is deduplicated
            # on its text with its Target replaced by <id>: with the name as the Target, both names read
            # alike and the clause kept the first. With a blank Target the full text is the key.
            $script:Tenant[1].Name = 'Ops'     # G-EL
            $script:Tenant[2].Name = 'ops'     # G-MOD
            $Read = Invoke-GroupRead -ExcludeSharedName
            @($Read.Result.Unread) | Should -Be @('groups/Admins', 'groups/Ops')
            @($Read.Result.Causes).Count | Should -Be 2
            foreach ($Entry in @($Read.Result.Causes)) { [string]$Entry.Target | Should -BeExactly '' }
            $Clause = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = @($Read.Result.Causes) } { param($C) Format-OERUnreadCauseClause -Cause $C }
            $Clause | Should -Not -BeNullOrEmpty -Because 'an empty clause would make the counts below vacuous'
            @([regex]::Matches($Clause, '2 live objects share the name groups/Admins ')).Count | Should -Be 1
            @([regex]::Matches($Clause, '2 live objects share the name groups/Ops ')).Count | Should -Be 1 -Because 'the second name is not dropped for reading like the first'
        }

        It 'keeps both spellings without -ExcludeSharedName, for a caller that applies its own rule' {
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('Admins', 'G-EL', 'G-MOD')
            $Read.Result.Unread.Count | Should -Be 0
        }

        It 'counts the two listed groups when the index holds <Label> (BL-131)' -ForEach @(
            @{ Label = 'the same two'; Extra = 0; Lag = $false; Count = 2 }
            @{ Label = 'a third, a Microsoft 365 group the listing never holds'; Extra = 1; Lag = $false; Count = 3 }
            @{ Label = 'only one of them, since it lags behind the listing'; Extra = 0; Lag = $true; Count = 2 }
        ) {
            # The index is every group in the tenant. It counts the larger of the two counts, so a
            # third namesake outside the listing raises the count and an index that lags never lowers it.
            # A lagging index misses G-SYNC as well, a group of a unique name created after it was read:
            # a name the index does not hold is counted over the listing alone.
            $Roster = @(foreach ($G in $script:Tenant) {
                    if ($Lag -and $G.Id -in @($script:IdPlain, $script:IdSync)) { continue }
                    [PSCustomObject]@{ Id = $G.Id; DisplayName = $G.Name }
                })
            if ($Extra) { $Roster += [PSCustomObject]@{ Id = '77777777-7777-7777-7777-777777777777'; DisplayName = 'ADMINS' } }
            $Index = New-TestGroupNameIndex -Group $Roster
            $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName -GroupNameIndex $Index
            $Expected = InModuleScope Omnicit.EntraRBAC -Parameters @{ N = $Count } { param($N) Get-OERSharedNameCause -Path 'groups/Admins' -Count $N }
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD')
            @($Read.Result.Unread) | Should -Be @('groups/Admins')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -BeExactly $Expected
            @($Read.Result.SharedNames).Count | Should -Be 1
            $Read.Result.SharedNames[0].Name | Should -BeExactly 'Admins'
            $Read.Result.SharedNames[0].Count | Should -Be $Count
        }
    }

    Context 'shared names counted over every group in the tenant (BL-131)' {
        # The listing holds the security groups only; the index holds every group in the tenant, here
        # the six listed ones and a Microsoft 365 group that carries G-RA's name in another letter case.
        BeforeAll {
            $script:IdM365 = '77777777-7777-7777-7777-777777777777'
            $script:NewRoster = {
                @(foreach ($G in $script:Tenant) { [PSCustomObject]@{ Id = $G.Id; DisplayName = $G.Name } }) +
                @([PSCustomObject]@{ Id = $script:IdM365; DisplayName = 'g-ra' })
            }
        }

        It 'leaves out a security group whose name only a group outside the listing shares, and reports it once with the index''s count (<Mode>)' -ForEach @(
            @{ Mode = 'relevant-only'; Relevant = $true; Kept = @('G-EL', 'G-MOD') }
            @{ Mode = 'full'; Relevant = $false; Kept = @('G-EL', 'G-MOD', 'G-PLAIN', 'G-SYNC', 'G-DYN') }
        ) {
            $Index = New-TestGroupNameIndex -Group (& $script:NewRoster)
            $Read = Invoke-GroupRead -RelevantOnly:$Relevant -ExcludeSharedName -GroupNameIndex $Index
            $Expected = InModuleScope Omnicit.EntraRBAC { Get-OERSharedNameCause -Path 'groups/G-RA' -Count 2 }
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be $Kept
            @($Read.Result.Unread) | Should -Be @('groups/G-RA')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -BeExactly $Expected
            [string]$Read.Result.Causes[0].Target | Should -BeExactly '' -Because 'a shared-name cause carries a blank Target (BL-156)'
            @($Read.Verbose | Where-Object { $_ -eq "Get-OERInventory: $Expected" }).Count | Should -Be 1
            @($Read.Result.SharedNames).Count | Should -Be 1
            $Read.Result.SharedNames[0].Section | Should -BeExactly 'groups'
            $Read.Result.SharedNames[0].Name | Should -BeExactly 'G-RA'
            $Read.Result.SharedNames[0].Count | Should -Be 2
            # The Microsoft 365 group is never read: the listing does not hold it.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*77777777-7777-7777-7777-777777777777*' }
        }

        It 'keeps the group when no index is given, and reports nothing' {
            $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.SharedNames.Count | Should -Be 0
        }

        It 'counts over the listed groups alone when the index was not read (<Label>)' -ForEach @(
            @{ Label = 'no ids, as Get-OERGroupNameIndex returns a failed listing'; Populated = $false }
            @{ Label = 'ids it must not trust'; Populated = $true }
        ) {
            # The second form is the guard's proof: an index whose Read is not true is never counted,
            # whatever it holds.
            $Ids = $null
            if ($Populated) { $Ids = (New-TestGroupNameIndex -Group (& $script:NewRoster)).IdsByName }
            $Unread = [PSCustomObject]@{ Read = $false; IdsByName = $Ids; Message = 'Could not list every group to count the names groups share: Too many requests (429)' }
            $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName -GroupNameIndex $Unread
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Result.SharedNames.Count | Should -Be 0
        }

        It 'changes nothing without -ExcludeSharedName' {
            $Index = New-TestGroupNameIndex -Group (& $script:NewRoster)
            $Read = Invoke-GroupRead -RelevantOnly -GroupNameIndex $Index
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.SharedNames.Count | Should -Be 0
        }
    }

    Context '-SecurityEnabledOnly, driven through the transport' {
        # G-EL (index 1) is the group the scenarios turn into one the listing should not have held: it
        # is eligible, so it is RBAC-relevant and would cost the most requests if it were read.
        It 'does not read a group it left out, in a relevant-only read' {
            $script:Tenant[1].SecurityEnabled = $false
            $Read = Invoke-GroupRead -RelevantOnly -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-MOD')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*22222222-2222-2222-2222-222222222222*' }
            # Reach proof: the group beside it was read, and the list was read once.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111/members' }
            Get-GraphCallCount -Like 'GET v1.0/groups[?]*' | Should -Be 1
            $Read.Warned.Count | Should -Be 1
            $Read.Warned[0] | Should -BeExactly '-GroupFilter returned 1 group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
            $Read.Result.Unread.Count | Should -Be 0
        }

        It 'does not project a group it left out, in a full read' {
            # A full read has the list carry the collections, so Get-OERGroup has read this group's
            # before the reader sees it; what the reader owes is that it is not projected, and that
            # it makes none of the projection's own requests for it (the PIM policy of a group found
            # in use).
            $script:Tenant[1].SecurityEnabled = $false
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-MOD', 'G-PLAIN', 'G-SYNC', 'G-DYN')
            # Reach proof: G-MOD is in use through its modified policy, so its policy was looked up.
            Get-GraphCallCount -Like 'GET beta/policies/roleManagementPolicyAssignments[?]*33333333-3333-3333-3333-333333333333*' | Should -BeGreaterThan 0
            Get-GraphCallCount -Like 'GET beta/policies/roleManagementPolicyAssignments[?]*22222222-2222-2222-2222-222222222222*' | Should -Be 0
            $Read.Warned.Count | Should -Be 1
        }

        It 'removes the cause of a failed members read of a group it left out in a full read, through the real Get-OERGroup' {
            # The real Get-OERGroup reads G-EL's members with the list and writes the failure with the
            # group's id as its target, which is what the reader removes the cause by.
            $script:Tenant[1].SecurityEnabled = $false
            $script:Refuse["members:$script:IdEl"] = 'Too many requests (429)'
            $Read = Invoke-GroupRead -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-MOD', 'G-PLAIN', 'G-SYNC', 'G-DYN')
            $Read.Result.Unread.Count | Should -Be 0
            @($Read.Result.Causes).Count | Should -Be 0
            # Reach proof: the members of G-EL were asked for and refused, and the cause was written to
            # the verbose stream before it was removed.
            Get-GraphCallCount -Like "GET v1.0/groups/$script:IdEl/members" | Should -BeGreaterThan 0
            @($Read.Verbose | Where-Object { $_ -like "Get-OERInventory: Could not read members for group $($script:IdEl):*" }).Count | Should -Be 1
            # Non-vacuity: without the switch the group is projected, names its members unread, and
            # the same cause is on the list with the group's id as its target.
            $Control = Invoke-GroupRead
            @($Control.Result.Unread) | Should -Be @('groups/G-EL/members')
            @($Control.Result.Causes).Count | Should -Be 1
            $Control.Result.Causes[0].Target | Should -Be $script:IdEl
        }

        It 'reads the same group as before without the switch' {
            # The control for the two reads above: the group the switch leaves out is a real, relevant
            # group, and it is read when the switch is not given.
            $script:Tenant[1].SecurityEnabled = $false
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            $Read.Warned.Count | Should -Be 0
        }

        It 'leaves out a group whose securityEnabled is <Label>' -ForEach @(
            @{ Label = 'missing'; Value = '<missing>' }
            @{ Label = 'null'; Value = $null }
            @{ Label = 'the text true'; Value = 'true' }
            @{ Label = 'the number 1'; Value = 1 }
            @{ Label = 'false'; Value = $false }
        ) {
            $script:Tenant[1].SecurityEnabled = $Value
            $Read = Invoke-GroupRead -RelevantOnly -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-MOD')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*22222222-2222-2222-2222-222222222222*' }
            $Read.Warned.Count | Should -Be 1
            $Read.Warned[0] | Should -BeLike '-GroupFilter returned 1 group(s) that are not security-enabled;*'
        }

        It 'counts every group it leaves out in the one warning' {
            $script:Tenant[1].SecurityEnabled = $false
            $script:Tenant[3].SecurityEnabled = '<missing>'
            $script:Tenant[4].SecurityEnabled = $null
            $Read = Invoke-GroupRead -RelevantOnly -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-MOD')
            $Read.Warned.Count | Should -Be 1
            $Read.Warned[0] | Should -BeExactly '-GroupFilter returned 3 group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out.'
            # G-PLAIN and G-SYNC are not relevant, and they are not even asked: not the two requests.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*55555555-5555-5555-5555-555555555555*' }
        }

        It 'writes no warning, and changes nothing, when the listing holds security-enabled groups only' {
            $Read = Invoke-GroupRead -RelevantOnly -SecurityEnabledOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            $Read.Warned.Count | Should -Be 0
        }

        Context 'a group the filter widened to shares a name with a security group (ruling 1)' {
            BeforeEach {
                $script:Tenant[0].Name = 'Admins'                  # G-RA: security, role-assignable, kept
                $script:Tenant[3].Name = 'admins'                  # G-PLAIN: the namesake
                $script:Tenant[3].SecurityEnabled = $false         # ... which the filter widened to
            }

            It 'does not count the group it left out, so the security group is kept and no shared name is reported' {
                $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName -SecurityEnabledOnly
                @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('Admins', 'G-EL', 'G-MOD')
                $Read.Result.Unread.Count | Should -Be 0
                $Read.Result.Causes.Count | Should -Be 0
                $Read.Warned.Count | Should -Be 1
                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
            }

            It 'does the same in a full read' {
                $Read = Invoke-GroupRead -ExcludeSharedName -SecurityEnabledOnly
                @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('Admins', 'G-EL', 'G-MOD', 'G-SYNC', 'G-DYN')
                $Read.Result.Unread.Count | Should -Be 0
            }

            It 'still reports the name as shared when both groups are security-enabled' {
                # The control: the same two names, with the namesake security-enabled, are shared.
                $script:Tenant[3].SecurityEnabled = $true
                $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName -SecurityEnabledOnly
                @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD')
                @($Read.Result.Unread) | Should -Be @('groups/Admins')
                $Read.Warned.Count | Should -Be 0
            }
        }
    }

    Context 'progress (A13), driven through the transport' {
        BeforeEach {
            $script:ProgressLog = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Omnicit.EntraRBAC Write-Progress {
                param($Activity, $Status, $PercentComplete, [switch]$Completed)
                $script:ProgressLog.Add($(if ($Completed) { "$Activity|completed" } else { "$Activity|$Status|$PercentComplete" }))
            }
        }

        It 'counts every listed group, the ones the relevance decision drops included' {
            $Read = Invoke-GroupRead -RelevantOnly -ProgressActivity 'Export-OERInventory'
            # Reach proof: the decision dropped three of the six groups, and still all six were counted.
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD')
            @($script:ProgressLog) | Should -Be @(
                'Export-OERInventory|Reading the group list|'
                'Export-OERInventory|Group 1 of 6|17'
                'Export-OERInventory|Group 2 of 6|33'
                'Export-OERInventory|Group 3 of 6|50'
                'Export-OERInventory|Group 4 of 6|67'
                'Export-OERInventory|Group 5 of 6|83'
                'Export-OERInventory|Group 6 of 6|100'
                'Export-OERInventory|completed'
            )
        }

        It 'writes the same records for a full read, with the list status of a full read' {
            $Read = Invoke-GroupRead -ProgressActivity 'Export-OERInventory'
            @($Read.Result.Groups).Count | Should -Be 6
            $script:ProgressLog[0] | Should -Be 'Export-OERInventory|Reading the groups in full|'
            @($script:ProgressLog | Where-Object { $_ -like '*|Group *' }).Count | Should -Be 6
            $script:ProgressLog[-1] | Should -Be 'Export-OERInventory|completed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Exactly -Times 1 -ParameterFilter { $Completed }
        }

        It 'writes no progress without -ProgressActivity' {
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups).Count | Should -Be 3
            Should -Invoke -ModuleName Omnicit.EntraRBAC Write-Progress -Times 0
        }
    }

    Context 'an empty tenant (Review Focus 2)' {
        It 'returns no group and nothing unread when the list answers nothing' {
            $script:Tenant = @()
            $Read = Invoke-GroupRead -RelevantOnly -ExcludeSharedName
            $Read.Result.Groups.Count | Should -Be 0
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
            # The list itself, and nothing else.
            $script:GraphCalls.Count | Should -Be 1
        }
    }

    Context 'full mode' {
        It 'reads every group in full without -RelevantOnly' {
            $Read = Invoke-GroupRead
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-RA', 'G-EL', 'G-MOD', 'G-PLAIN', 'G-SYNC', 'G-DYN')
            Get-GraphCallCount -Like 'GET v1.0/groups[?]*' | Should -Be 1
            foreach ($G in $script:Tenant) {
                Get-GraphCallCount -Like "GET v1.0/groups/$($G.Id)/members" | Should -Be 1 -Because "$($G.Name) is read in full"
                Get-GraphCallCount -Like "GET v1.0/groups/$($G.Id)/owners" | Should -Be 1 -Because "$($G.Name) is read in full"
                Get-GraphCallCount -Like "GET *eligibilityScheduleInstances*$($G.Id)*" | Should -Be 1 -Because "$($G.Name) is read in full"
            }
            # The members, the owners, the eligibility and the criterion: what a full read costs G-PLAIN.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 6 -ParameterFilter { $Uri -like '*44444444-4444-4444-4444-444444444444*' }
        }

        It 'reads the members of a dynamic group once, writes them as an explicit null, and counts them (BL-43, R-1, R-15)' {
            $Read = Invoke-GroupRead
            $Dyn = @($Read.Result.Groups | Where-Object { $_.displayName -eq 'G-DYN' })
            $Dyn.Count | Should -Be 1
            $Dyn[0].dynamic | Should -BeTrue
            $Dyn[0].PSObject.Properties.Name | Should -Contain 'members'
            $null -eq $Dyn[0].members | Should -BeTrue
            (@($Dyn[0].owners) -join '|') | Should -BeExactly 'person12@contoso.com'
            @($Read.Result.Unread).Count | Should -Be 0
            @($Read.Result.DynamicMembers | ForEach-Object { "$($_.GroupId):$($_.Group):$($_.Members)" }) | Should -Be @("$($script:IdDyn):G-DYN:1")
            # The requests are the ones a full read has always made for it.
            Get-GraphCallCount -Like "GET v1.0/groups/$($script:IdDyn)/members" | Should -Be 1
            Get-GraphCallCount -Like "GET v1.0/groups/$($script:IdDyn)/owners" | Should -Be 1
            # Non-vacuity: the assigned groups of the same read write their members.
            $ByName = @{}
            foreach ($G in $Read.Result.Groups) { $ByName[$G.displayName] = $G }
            (@($ByName['G-PLAIN'].members) -join '|') | Should -BeExactly 'person7@contoso.com'
        }
    }
}

Describe 'Get-OERInventoryGroup, the PIM for Groups assignment read driven through the transport (BL-125)' {
    # Read-OERGroupPimAssignment and Get-OERPimGroupsGraphPath are the REAL ones here, and
    # Invoke-OERGraphRequest is mocked: every assignment request a group costs reaches the one mock
    # below and is recorded there. The rest of the read is mocked above the transport (the list,
    # the per-group collections, the criterion and the policy lookup), so the only requests that
    # reach the transport are the assignment reads; the mock throws on any other.
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        # g-a: a standing and an activated member. g-b: an activated owner only. g-c: role-assignable,
        # with no member and no owner. g-x: not role-assignable and not in use, so -RelevantOnly does
        # not keep it, while a full read reads it.
        $script:AssignListing = @(
            @{ Id = 'g-a'; Name = 'role_sec_a'; RoleAssignable = $true
                Members = @(@{ id = 'u-1'; userPrincipalName = 'person1@contoso.com' }, @{ id = 'u-2'; userPrincipalName = 'person2@contoso.com' }); Owners = @() }
            @{ Id = 'g-b'; Name = 'role_sec_b'; RoleAssignable = $true
                Members = @(); Owners = @(@{ id = 'o-1'; userPrincipalName = 'person6@contoso.com' }) }
            @{ Id = 'g-c'; Name = 'role_sec_c'; RoleAssignable = $true; Members = @(); Owners = @() }
            @{ Id = 'g-x'; Name = 'plain_x'; RoleAssignable = $false
                Members = @(@{ id = 'u-9'; userPrincipalName = 'person3@contoso.com' }); Owners = @() }
        )
        $script:AssignRows = @{
            'g-a' = @(
                @{ principalId = 'u-1'; accessId = 'member'; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = $null; endDateTime = $null }
                @{ principalId = 'u-2'; accessId = 'member'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' }
            )
            'g-b' = @(@{ principalId = 'o-1'; accessId = 'owner'; memberType = 'direct'; assignmentType = 'activated'; startDateTime = '2026-10-13T08:00:00Z'; endDateTime = '2026-10-13T16:00:00Z' })
            'g-x' = @(@{ principalId = 'u-9'; accessId = 'member'; memberType = 'direct'; assignmentType = 'assigned'; startDateTime = $null; endDateTime = $null })
        }
        $script:AssignCalls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
            param([switch]$IncludeMembers, [switch]$IncludeOwners, [switch]$IncludePimEligibility)
            foreach ($Spec in $script:AssignListing) {
                $G = [PSCustomObject]@{ Id = $Spec.Id; DisplayName = $Spec.Name; Description = $null; GroupType = 'Assigned'; IsAssignableToRole = $Spec.RoleAssignable; SecurityEnabled = $true }
                if ($IncludeMembers) { $G | Add-Member -NotePropertyName Members -NotePropertyValue @($Spec.Members) }
                if ($IncludeOwners) { $G | Add-Member -NotePropertyName Owners -NotePropertyValue @($Spec.Owners) }
                if ($IncludePimEligibility) { $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @() }
                $G
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Read-OERGroupCollection {
            param($GroupId, $Collection)
            $Spec = @($script:AssignListing | Where-Object { $_.Id -eq $GroupId })[0]
            $Value = switch ($Collection) { 'Members' { @($Spec.Members) } 'Owners' { @($Spec.Owners) } default { @() } }
            [PSCustomObject]@{ Collection = $Collection; Read = $true; Value = $Value; ErrorId = $null; Message = $null; Exception = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Test-OERGroupPimInUse {
            param($GroupId)
            [PSCustomObject]@{ InUse = ($GroupId -ne 'g-x'); Reason = 'x' }
        }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { $null }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param([string]$Method, [string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
            $script:AssignCalls.Add($Uri)
            if ($Uri -match "^beta/identityGovernance/privilegedAccess/group/assignmentScheduleInstances\?\`$filter=groupId eq '(?<Id>[^']*)'$") {
                $Id = $Matches.Id
                return @{ value = $(if ($script:AssignRows.ContainsKey($Id)) { @($script:AssignRows[$Id]) } else { @() }) }
            }
            throw "The fake transport has no answer for: $Uri"
        }
    }

    It 'sends exactly one assignment request per group read in full with members or owners, and none otherwise (<Mode>)' -ForEach @(
        @{ Mode = 'full'; Expected = @('g-a', 'g-b', 'g-x') }
        @{ Mode = 'relevant-only'; Expected = @('g-a', 'g-b') }
    ) {
        $Read = Invoke-GroupRead -RelevantOnly:($Mode -eq 'relevant-only')
        # Every request the read made reached the transport mock as an assignment read, one per group.
        @($script:AssignCalls | ForEach-Object { if ($_ -match "groupId eq '(?<Id>[^']*)'") { $Matches.Id } }) | Should -Be $Expected
        @($script:AssignCalls | Where-Object { $_ -notlike '*assignmentScheduleInstances*' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times $Expected.Count -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like "*groupId eq 'g-c'*" }
        # The answer the real reader passed on decided the projection: the activated member and the
        # activated owner are left out, the standing member is written.
        $ByName = @{}
        foreach ($G in $Read.Result.Groups) { $ByName[$G.displayName] = $G }
        $ByName['role_sec_a'].members | Should -Be @('person1@contoso.com')
        $ByName['role_sec_b'].PSObject.Properties.Name | Should -Not -Contain 'owners'
        @($Read.Result.PimLeftOut | ForEach-Object { "$($_.GroupId):$($_.Members)/$($_.Owners)/$($_.Basis)" }) | Should -Be @('g-a:1/0/Assignments', 'g-b:0/1/Assignments')
        $Read.Result.Unread.Count | Should -Be 0
    }

    It 'names the assignments of a group unread when the transport refuses them' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param([string]$Method, [string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
            $script:AssignCalls.Add($Uri)
            if ($Uri -like "*groupId eq 'g-a'*") {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Insufficient privileges'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            @{ value = @() }
        }
        $Read = Invoke-GroupRead
        @($Read.Result.Unread) | Should -Contain 'groups/role_sec_a/pimAssignments'
        @($Read.Result.Causes | Where-Object { $_.Target -eq 'g-a' } | ForEach-Object { $_.Cause }) |
            Should -Be @('Could not read the PIM for Groups assignments of group g-a: Insufficient privileges.')
        # The eligibility was read (and is empty), so nothing is left out and the members are written.
        $ByName = @{}
        foreach ($G in $Read.Result.Groups) { $ByName[$G.displayName] = $G }
        $ByName['role_sec_a'].members | Should -Be @('person1@contoso.com', 'person2@contoso.com')
    }
}

Describe 'Get-OERInventoryGroup (the cause removal of a left-out group stands before its warning, Sprint 11 step 10, BL-44)' {
    # BL-44. A Write-Warning under a Stop warning preference is a terminating error, so a statement after it never
    # runs. The cause removal of -SecurityEnabledOnly holds a list, which a verbose line cannot show, so the proof
    # reads the source with the AST: the warning found by the start of its text, the removal loop stands in the SAME
    # statement block and starts before it. The checker has a known-answer test of its own, so it cannot pass for
    # nothing.
    BeforeAll {
        $script:BkSourcePath = (Resolve-Path (Join-Path $PSScriptRoot '../../../source/Private/Get-OERInventoryGroup.ps1')).Path
        $BkErrors = $null
        $script:BkAst = [System.Management.Automation.Language.Parser]::ParseFile($script:BkSourcePath, [ref]$null, [ref]$BkErrors)
        if (@($BkErrors).Count -gt 0) { throw "Get-OERInventoryGroup.ps1 does not parse: $(@($BkErrors)[0].Message)" }
        # The violations of one warning: an empty list when it is found once and each named statement stands in its
        # block, the right number of times, before it.
        function script:Get-BkViolation {
            param([System.Management.Automation.Language.Ast]$Ast, [string]$WarningStart, [object[]]$Bookkeeping)
            $Violations = [System.Collections.Generic.List[string]]::new()
            $Warnings = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Write-Warning' }, $true) |
                    Where-Object {
                        $Elements = @($_.CommandElements)
                        $Elements.Count -ge 2 -and $Elements[1].Extent.Text.TrimStart([char[]]@('"', "'")).StartsWith($WarningStart, [System.StringComparison]::Ordinal)
                    })
            if ($Warnings.Count -ne 1) {
                $Violations.Add("expected exactly one Write-Warning starting '$WarningStart', found $($Warnings.Count)")
                return $Violations.ToArray()
            }
            $Statement = $Warnings[0]
            while ($null -ne $Statement.Parent -and $Statement.Parent -isnot [System.Management.Automation.Language.StatementBlockAst]) { $Statement = $Statement.Parent }
            $Block = $Statement.Parent
            foreach ($Item in $Bookkeeping) {
                $Hits = @($Block.Statements | Where-Object { $_.Extent.Text -match $Item.Pattern })
                if ($Hits.Count -ne $Item.Count) {
                    $Violations.Add("expected $($Item.Count) statement(s) matching '$($Item.Pattern)' in the block of the warning, found $($Hits.Count)")
                    continue
                }
                foreach ($Hit in $Hits) {
                    if ($Hit.Extent.StartOffset -ge $Statement.Extent.StartOffset) {
                        $Violations.Add("a statement matching '$($Item.Pattern)' starts at $($Hit.Extent.StartOffset), not before the warning at $($Statement.Extent.StartOffset)")
                    }
                }
            }
            $Violations.ToArray()
        }
    }

    It 'holds the known answer: the checker finds a warning that stands before its bookkeeping, a bookkeeping statement that is missing and a warning that is not unique' {
        $Parse = {
            param([string]$Text)
            $E = $null
            [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$E)
        }
        $Pattern = @(@{ Pattern = '^\$Unread = \$true$'; Count = 1 })
        $Good = & $Parse 'if ($n -gt 0) { $Unread = $true; Write-Warning "Could not read: $n" }'
        @(Get-BkViolation -Ast $Good -WarningStart 'Could not read:' -Bookkeeping $Pattern).Count | Should -Be 0
        $Late = & $Parse 'if ($n -gt 0) { Write-Warning "Could not read: $n"; $Unread = $true }'
        @(Get-BkViolation -Ast $Late -WarningStart 'Could not read:' -Bookkeeping $Pattern).Count | Should -Be 1
        @(Get-BkViolation -Ast $Late -WarningStart 'Could not read:' -Bookkeeping $Pattern)[0] | Should -BeLike "a statement matching '*' starts at *, not before the warning at *"
        $Missing = & $Parse 'if ($n -gt 0) { Write-Warning "Could not read: $n" }'
        @(Get-BkViolation -Ast $Missing -WarningStart 'Could not read:' -Bookkeeping $Pattern)[0] | Should -BeLike 'expected 1 statement(s) matching*found 0'
        $Twice = & $Parse 'if ($n -gt 0) { $Unread = $true; Write-Warning "Could not read: a"; Write-Warning "Could not read: b" }'
        @(Get-BkViolation -Ast $Twice -WarningStart 'Could not read:' -Bookkeeping $Pattern)[0] | Should -BeLike 'expected exactly one Write-Warning starting*found 2'
        $Absent = & $Parse 'if ($n -gt 0) { $Unread = $true; Write-Warning "Another text" }'
        @(Get-BkViolation -Ast $Absent -WarningStart 'Could not read:' -Bookkeeping $Pattern)[0] | Should -BeLike 'expected exactly one Write-Warning starting*found 0'
    }

    It 'stands the cause removal of the left-out groups before the -GroupFilter warning' {
        $Violations = @(Get-BkViolation -Ast $script:BkAst -WarningStart '-GroupFilter returned' -Bookkeeping @(
                @{ Pattern = '(?s)^for \(\$CauseIndex = .*\$Causes\.RemoveAt\('; Count = 1 }
            ))
        $Violations | Should -Be @()
    }
}
