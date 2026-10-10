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
            [switch]$SecurityEnabledOnly
        )
        $Arguments = @{
            Filter              = $Filter
            IncludeId           = [bool]$IncludeId
            Cache               = $Cache
            RelevantOnly        = [bool]$RelevantOnly
            IncludeSyncedGroups = [bool]$IncludeSyncedGroups
            ExcludeSharedName   = [bool]$ExcludeSharedName
            SecurityEnabledOnly = [bool]$SecurityEnabledOnly
        }
        InModuleScope Omnicit.EntraRBAC -Parameters $Arguments {
            $Params = @{ Filter = $Filter }
            if ($IncludeId) { $Params.IncludeId = $true }
            if ($null -ne $Cache) { $Params.PrincipalNameCache = $Cache }
            if ($RelevantOnly) { $Params.RelevantOnly = $true }
            if ($IncludeSyncedGroups) { $Params.IncludeSyncedGroups = $true }
            if ($ExcludeSharedName) { $Params.ExcludeSharedName = $true }
            if ($SecurityEnabledOnly) { $Params.SecurityEnabledOnly = $true }
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

        It 'sends the filter it is given exactly as given, and asks for nothing more' {
            $null = Invoke-GroupRead -SecurityEnabledOnly -Filter 'securityEnabled eq true and (x eq 1)'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1 -ParameterFilter {
                $Filter -eq 'securityEnabled eq true and (x eq 1)'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERGroup -Exactly -Times 1
        }
    }

    Context 'the result' {
        It 'is one tagged object holding Groups, Unread and Causes' {
            $Read = Invoke-GroupRead
            $Read.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryGroupRead'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Groups'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Unread'
            $Read.Result.PSObject.Properties.Name | Should -Contain 'Causes'
            @($Read.Result.Groups).Count | Should -Be 1
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
            $Group.members | Should -Be @('person1@contoso.com', 'dev-1')
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
            $Expected = InModuleScope Omnicit.EntraRBAC { Get-OERSharedNameCause -Path 'groups/Admins' }
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD')
            @($Read.Result.Unread) | Should -Be @('groups/Admins')
            @($Read.Result.Causes).Count | Should -Be 1
            $Read.Result.Causes[0].Cause | Should -BeExactly $Expected
            $Read.Result.Causes[0].Target | Should -Be 'groups/Admins'
            @($Read.Verbose) | Should -Contain "Get-OERInventory: $Expected"
        }

        It 'leaves out the shared name in a full read too' {
            $Read = Invoke-GroupRead -ExcludeSharedName
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('G-EL', 'G-MOD', 'G-SYNC', 'G-DYN')
            @($Read.Result.Unread) | Should -Be @('groups/Admins')
        }

        It 'keeps both spellings without -ExcludeSharedName, for a caller that applies its own rule' {
            $Read = Invoke-GroupRead -RelevantOnly
            @($Read.Result.Groups | ForEach-Object { $_.displayName }) | Should -Be @('Admins', 'G-EL', 'G-MOD')
            $Read.Result.Unread.Count | Should -Be 0
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
    }
}
