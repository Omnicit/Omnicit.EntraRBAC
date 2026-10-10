BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryGroup' {
    BeforeAll {
        # One read with every stream the assertions look at captured, and -ErrorAction pinned: a
        # global Stop preference would otherwise end the call at the first record the mocks write.
        # The verbose lines keep Get-OERInventory's own prefix on purpose (its verbose output did
        # not change when this section moved here), which is why they are asserted verbatim.
        function Invoke-GroupRead {
            param([string]$Filter = 'securityEnabled eq true', [switch]$IncludeId, [hashtable]$Cache)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Filter = $Filter; IncludeId = [bool]$IncludeId; Cache = $Cache } {
                $Params = @{ Filter = $Filter }
                if ($IncludeId) { $Params.IncludeId = $true }
                if ($null -ne $Cache) { $Params.PrincipalNameCache = $Cache }
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
                Write-Error -Message "Could not read members for group 'g-1': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-1' -ErrorAction Continue
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
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
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
                Write-Error -Message 'gone' -ErrorId 'GroupNotFound' -Category ObjectNotFound -ErrorAction Continue
            }
            $Read = Invoke-GroupRead
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Result.Causes.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
        }

        It 'sends a foreign error record to the verbose stream, not to a warning or the unread list' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                Write-Error -Message 'stray from a nested call' -ErrorId 'SomeNestedFailure' -Category NotSpecified -ErrorAction Continue
            }
            $Read = Invoke-GroupRead
            $Read.Result.Unread.Count | Should -Be 0
            $Read.Warned.Count | Should -Be 0
            @($Read.Verbose) | Should -Contain 'Get-OERInventory: ignoring a foreign error record seen while reading groups (SomeNestedFailure): stray from a nested call'
        }

        It 'keeps the groups that were read when one group has a failed collection' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                Write-Error -Message 'members read failed' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -TargetObject 'g-1' -ErrorAction Continue
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
                Write-Error -Message "Could not read members for group 'g-a': first" `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction Continue
                Write-Error -Message "Could not read owners for group 'g-a': second" `
                    -ErrorId 'GroupOwnerReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction Continue
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
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('page two refused'), 'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
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
                Write-Error -Message ' ' -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject 'g-a' -ErrorAction Continue
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
