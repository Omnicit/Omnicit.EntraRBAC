BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    # BL-125 (A3): the groups section reads each group's PIM for Groups assignments to leave an
    # activation out of members and owners. Answered here as a successful read that lists nothing, so
    # every member and owner a fixture lists reads as standing and every expectation in this file keeps
    # the meaning it had; Get-OERInventoryGroup.Tests.ps1 tests the read itself.
    Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
        [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
    }
    # BL-131: the groups section counts a group's name over every group in the tenant, through one
    # paged listing (Get-OERGroupNameIndex). Answered here as an index that was read and holds no
    # name, so every name is counted over the groups a fixture lists, exactly as before the listing
    # existed, and no fixture's transport mock has to answer it. The Context 'shared names are counted
    # over every group in the tenant (BL-131)' answers it with names, and drives the real helper
    # through the transport.
    $script:NewEmptyGroupNameIndex = {
        $Index = [PSCustomObject]@{
            Read      = $true
            IdsByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Message   = $null
        }
        $Index.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupNameIndex')
        $Index
    }
    Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { & $script:NewEmptyGroupNameIndex }
    # BL-131 (Task 3c): a group named as a principal in RoleAssignments or DirectoryRoleAssignments is
    # written by its display name only when the index holds that name for this group alone, so the empty
    # index above names every such group by its object id. A Context whose fixtures name groups as
    # principals answers the index with this instead: every group the fixture describes, each id under
    # its display name (-NameById: id -> name), so a name is shared or unique exactly as the fixture
    # says.
    $script:NewGroupNameIndexOf = {
        param([hashtable]$NameById)
        $Ids = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($GroupId in $NameById.Keys) {
            $GroupName = [string]$NameById[$GroupId]
            if ([string]::IsNullOrWhiteSpace($GroupName)) { continue }
            if (-not $Ids.ContainsKey($GroupName)) { $Ids[$GroupName] = [System.Collections.Generic.List[string]]::new() }
            $Ids[$GroupName].Add(([string]$GroupId).ToLowerInvariant())
        }
        $Index = [PSCustomObject]@{ Read = $true; IdsByName = $Ids; Message = $null }
        $Index.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupNameIndex')
        $Index
    }
    # Sprint 11 step 6 (BL-133, A18): the RoleAssignments section looks its principals up with
    # Resolve-OERPrincipalName -Detailed, which answers one object per id (Id, Read, Found, Name,
    # ObjectType, Cause); every other section keeps the map the default call returns. A fixture's mock
    # answers both forms through this: -Names maps an id to the name the directory returns for it, and an
    # id it does not hold is one the directory did not return (Found false under -Detailed, absent from
    # the map otherwise).
    $script:AnswerPrincipalLookup = {
        param([string[]]$Id, [bool]$Detailed, [hashtable]$Names)
        if (-not $Detailed) {
            $Map = @{}
            foreach ($One in @($Id)) { if ($One -and $Names.ContainsKey($One)) { $Map[$One] = $Names[$One] } }
            return $Map
        }
        foreach ($One in @($Id | Where-Object { $_ } | Select-Object -Unique)) {
            $Found = $Names.ContainsKey($One)
            [PSCustomObject]@{ Id = $One; Read = $true; Found = $Found; Name = $(if ($Found) { [string]$Names[$One] } else { $null }); ObjectType = $null; Cause = $null }
        }
    }
    # Three Split-Path hops from tests\Unit\Public: tests\Unit\Public -> tests\Unit -> tests ->
    # repo root. A two-hop version resolves to tests\ and was corrected once already on this
    # branch (Task 1) -- do not repeat that mistake.
    $RepoRoot = $PSScriptRoot | Split-Path | Split-Path | Split-Path
    $script:sourceRoot = Join-Path -Path $RepoRoot -ChildPath 'source'
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventory' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment {}
        # The groups section asks Get-OERPimGroupPolicyId whether a group is onboarded to PIM for
        # Groups at all before reading its policy, so a fixture that mocks Get-OERGroupPimPolicy
        # into returning a policy must answer this consistently or the read it stubs is skipped as
        # "not onboarded". Mocked in the OUTER BeforeEach so every Context inherits one answer;
        # the Contexts that need the not-onboarded case override it with { $null }. Without it the
        # real helper runs and reaches the real transport, which no unit test may do.
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
        # Before any of that, the groups section asks Test-OERGroupPimInUse whether the group uses
        # PIM for Groups at all, and exports no pimPolicy for a group that does not. Answered "in
        # use" here so every existing fixture keeps reaching the policy reads it stubs; the Context
        # 'pimPolicy only for a group that uses PIM for Groups' overrides it for the other answers.
        Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x' } }
        # Sprint 11 step 6 (BL-133): a role assignment principal the directory did not return is looked for
        # among its deleted items. No fixture in this Describe means that: a principal its name map does not
        # hold fails here, loudly, rather than through the transport. The Describe 'Get-OERInventory role
        # assignment principals the directory did not return, or whose lookup failed' drives the real read.
        Mock -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus { throw "unexpected deleted items read: $Id" }
    }

    It 'returns a tagged Omnicit.EntraRBAC.Inventory object' {
        $Result = Get-OERInventory -Include Groups
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Inventory'
        $Result.Version | Should -Be '1.0'
    }

    It 'authenticates once via Initialize-OERAuth' {
        Get-OERInventory -Include Groups | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'has a registered format view for the Inventory type' {
        $Formatted = Get-OERInventory -Include Groups | Format-Table | Out-String
        $Formatted | Should -Match 'Version'
    }

    It 'passes -IncludeARM to Initialize-OERAuth when an Azure section is requested' {
        Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $IncludeARM -eq $true }
    }

    Context 'Groups section' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                $g = [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_identity_administrator'
                    Description = 'Identity admins'; GroupType = 'RoleEnabled'
                    IsAssignableToRole = $true; MembershipRule = $null
                    Members = @(@{ displayName = 'Anna Berg' }, @{ displayName = 'Bo Ek' })
                    Owners = @()
                    PimEligibility = @(@{ principalId = 'p-1' })
                }
                $g
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = 'c1'; ActivationEnabledRules = @('Justification');
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                    ActiveEnabledRules = @('MultiFactorAuthentication'); Notifications = [pscustomobject]@{ EligibleAlert = @('person18@example.com'); ActiveAlert = @(); ActivationAlert = @() } }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'p-1' } }
        }

        It 'reads the groups with the securityEnabled default filter, and lets -GroupFilter widen it' {
            # The apply-document scope, pinned. Export-OERInventory now reads its ROSTER unfiltered
            # (Get-OERGroup -All), and this is the other half of that split: inventory.json must NOT
            # follow it. Widening the section here widens what Invoke-OERStructure reconciles and,
            # under -Prune, deletes -- so the default filter is a deliberate scope, and -GroupFilter
            # is the documented, opt-in way past it.
            Get-OERInventory -Include Groups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter {
                $Filter -eq 'securityEnabled eq true'
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 0 -Exactly -ParameterFilter {
                $All -eq $true
            }

            Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'role_')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly -ParameterFilter {
                $Filter -eq "startswith(displayName,'role_')"
            }
        }

        It 'projects a group with members, eligibility and pimPolicy' {
            $Result = Get-OERInventory -Include Groups
            @($Result.Groups).Count | Should -Be 1
            $grp = $Result.Groups[0]
            $grp.displayName | Should -Be 'role_sec_identity_administrator'
            $grp.roleAssignable | Should -BeTrue
            $grp.dynamic | Should -BeFalse
            $grp.members | Should -Contain 'Anna Berg'
            $grp.members | Should -Contain 'Bo Ek'
            @($grp.eligibility).Count | Should -Be 1
            $grp.eligibility[0].principal | Should -Be 'p-1'
            $grp.pimPolicy.member.activationMaxHours | Should -Be 8
            $grp.pimPolicy.member.authenticationContextId | Should -Be 'c1'
            $grp.pimPolicy.member.activeEnablement | Should -Contain 'MultiFactorAuthentication'
            $grp.pimPolicy.member.notifications.eligibleAlert | Should -Contain 'person18@example.com'
            $grp.pimPolicy.member.notifications.PSObject.Properties.Name | Should -Not -Contain 'activeAlert'
            $grp.pimPolicy.owner.activationMaxHours | Should -Be 8
        }

        It 'shows no progress while it reads the groups, since progress is the export''s alone' {
            # Get-OERInventory calls the shared reader without -ProgressActivity, so its output stays
            # what it was. The real reader runs here; only Write-Progress is observed.
            Mock -ModuleName $script:moduleName Write-Progress { }
            $Result = Get-OERInventory -Include Groups
            # Reach proof: the reader ran and the group it read was projected.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            @($Result.Groups).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Write-Progress -Times 0 -Exactly
        }

        It 'projects a user member as its UPN and a non-user member (device/group/app) as its object id' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_identity_administrator'
                    Description = 'd'; GroupType = 'RoleEnabled'; IsAssignableToRole = $true; MembershipRule = $null
                    Members = @(
                        @{ id = 'u-9'; displayName = 'Person Eleven'; userPrincipalName = 'person11@example.com' },
                        @{ id = 'dev-1'; displayName = 'DEVICE-0001' }
                    )
                    Owners = @()
                    PimEligibility = @()
                }
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { }
            $grp = (Get-OERInventory -Include Groups).Groups[0]
            $grp.members | Should -Contain 'person11@example.com'
            $grp.members | Should -Contain 'dev-1'
            $grp.members | Should -Not -Contain 'Person Eleven'
            $grp.members | Should -Not -Contain 'DEVICE-0001'
        }

        It 'projects group owners into the inventory' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_identity_administrator'
                    Description = 'Identity admins'; GroupType = 'RoleEnabled'
                    IsAssignableToRole = $true; MembershipRule = $null
                    Members = @()
                    Owners  = @(@{ userPrincipalName = 'person19@example.com' })
                    PimEligibility = @()
                }
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            $grp = (Get-OERInventory -Include Groups).Groups[0]
            $grp.owners | Should -Contain 'person19@example.com'
        }

        It 'omits owners when the group has none' {
            $Result = Get-OERInventory -Include Groups
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'owners'
        }

        It 'projects membershipRuleProcessingState alongside membershipRule for a dynamic group' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'dyn_all_it'
                    Description = $null; GroupType = 'Dynamic'
                    IsAssignableToRole = $false; MembershipRule = '(user.department -eq "IT")'
                    MembershipRuleProcessingState = 'Paused'
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            $grp = (Get-OERInventory -Include Groups).Groups[0]
            $grp.membershipRule | Should -Be '(user.department -eq "IT")'
            $grp.membershipRuleProcessingState | Should -Be 'Paused'
        }

        It 'omits membershipRuleProcessingState for a static group' {
            $Result = Get-OERInventory -Include Groups
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'membershipRuleProcessingState'
        }

        It 'resolves eligibility principals to names by default (D6)' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'anna@contoso.com' } }
            $grp = (Get-OERInventory -Include Groups).Groups[0]
            $grp.eligibility[0].principal | Should -Be 'anna@contoso.com'
            $grp.eligibility[0].PSObject.Properties.Name | Should -Not -Contain 'id'
        }

        It 'stamps the eligibility principal id only with -IncludeId' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'anna@contoso.com' } }
            $grp = (Get-OERInventory -Include Groups -IncludeId).Groups[0]
            $grp.eligibility[0].principal | Should -Be 'anna@contoso.com'
            $grp.eligibility[0].id | Should -Be 'p-1'
        }

        It 'falls back to the GUID when the principal cannot be resolved' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'p-1' } }
            (Get-OERInventory -Include Groups).Groups[0].eligibility[0].principal | Should -Be 'p-1'
        }

        It 'reads groups with members and eligibility expanded' {
            Get-OERInventory -Include Groups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -ParameterFilter {
                $IncludeMembers -eq $true -and $IncludePimEligibility -eq $true
            }
        }

        It 'reads groups with owners expanded' {
            Get-OERInventory -Include Groups | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -ParameterFilter {
                $IncludeOwners -eq $true
            }
        }

        It 'omits pimPolicy when the group is not PIM-onboarded' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { }
            $Result = Get-OERInventory -Include Groups
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }

        It 'omits pimPolicy when the policy has a null ActivationMaxHours and no other field is customized' {
            # A null ActivationMaxHours alone is not evidence of an unconfigured policy (it can also mean
            # the maximumDuration on Expiration_EndUser_Assignment did not parse as PT<n>H) -- so the
            # projection must still omit the block when every OTHER field is genuinely empty too, matching
            # the full Get-OERGroupPimPolicy contract shape (all 9 friendly properties always present).
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                [PSCustomObject]@{
                    ActivationMaxHours        = $null
                    AuthenticationContextId   = $null
                    ActivationEnabledRules    = @()
                    AllowPermanentEligibility = $null
                    EligibleDurationDays      = $null
                    AllowPermanentActive      = $null
                    ActiveDurationDays        = $null
                    ActiveEnabledRules        = @()
                    Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                }
            }
            $Result = Get-OERInventory -Include Groups
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }

        It 'adds an id property only with -IncludeId' {
            (Get-OERInventory -Include Groups).Groups[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            (Get-OERInventory -Include Groups -IncludeId).Groups[0].id | Should -Be 'g-1'
        }

        It 'does not warn when the group is simply not PIM-onboarded (PimPolicyNotFound)' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { Write-Error -Message 'no policy' -ErrorId 'PimPolicyNotFound' -ErrorAction Stop }
            $Result = Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue
            $Warned | Should -BeNullOrEmpty
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }

        It 'accounts for the unread collection when the PIM policy read fails for a non-NotFound reason' {
            # A per-collection failure is reported the way every other per-collection failure in this
            # cmdlet is reported: not as one warning per group (96 refused groups would print 192
            # near-identical lines), but as an entry in the unread-collection list, which ends the run
            # in a single InventoryPartial error naming every one of them and the distinct causes.
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { throw [System.Exception]::new('throttled') }
            $Err = $null
            $Result = Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1 -Because 'a PIM policy nobody could read is a collection this document does not state'
            [string]$Partial[0].Exception.Message | Should -Match 'pimPolicy/member'
            [string]$Partial[0].Exception.Message | Should -Match 'throttled' -Because 'the transport reason tells a 429 apart from a 403'
            $Warned | Should -BeNullOrEmpty -Because 'a per-collection failure is accounted for at the projection, not warned once per group'
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }

        It 'returns an empty Groups section without surfacing an error when no groups match' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('no group'), 'GroupNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
            }
            $Result = Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue
            @($Result.Groups).Count | Should -Be 0
            $Warned | Should -BeNullOrEmpty
        }

        It 'warns when the group read fails for a non-NotFound reason' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('throttled'), 'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
            }
            # -ErrorAction is pinned: the failed list now also ends the run in InventoryPartial, which
            # is non-terminating but would stop the statement under a global $ErrorActionPreference of Stop.
            Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            $Warned | Should -Not -BeNullOrEmpty
        }

        It 'projects the group mailNickname' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_core'; Description = 'd'
                    MailNickname = 'rolesec-core'; GroupType = 'Regular'
                    IsAssignableToRole = $false; MembershipRule = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy { }
            $Group = (Get-OERInventory -Include Groups).Groups[0]
            $Group.mailNickname | Should -Be 'rolesec-core'
        }

        It 'omits mailNickname when the group has none' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-2'; DisplayName = 'role_sec_none'; Description = $null
                    MailNickname = $null; GroupType = 'Regular'
                    IsAssignableToRole = $false; MembershipRule = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy { }
            $Group = (Get-OERInventory -Include Groups).Groups[0]
            $Group.PSObject.Properties.Name | Should -Not -Contain 'mailNickname'
        }

        It 'writes onPremisesSynced: true for a synchronized group and no such key for any other group (A15)' {
            # Graph's onPremisesSyncEnabled is three-valued: true (synchronized), false (was, no
            # longer) and null (never, or converted to the cloud). Only true is a managed-on-premises
            # group, and it is written ONLY as true: a cloud group's entry stays exactly what earlier
            # versions exported, so no existing document gains a key.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                foreach ($Spec in @(
                        @{ Name = 'role_sec_synced'; Sync = $true },
                        @{ Name = 'role_sec_cloud'; Sync = $null },
                        @{ Name = 'role_sec_formerly'; Sync = $false })) {
                    [PSCustomObject]@{
                        Id = "g-$($Spec.Name)"; DisplayName = $Spec.Name; Description = 'd'
                        MailNickname = $null; GroupType = 'Regular'
                        IsAssignableToRole = $false; MembershipRule = $null
                        OnPremisesSyncEnabled = $Spec.Sync
                        Members = @(); Owners = @(); PimEligibility = @()
                    }
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy { }
            $Groups = @((Get-OERInventory -Include Groups).Groups)
            $Groups.Count | Should -Be 3

            $Synced = $Groups | Where-Object { $_.displayName -eq 'role_sec_synced' }
            $Cloud = $Groups | Where-Object { $_.displayName -eq 'role_sec_cloud' }
            $Formerly = $Groups | Where-Object { $_.displayName -eq 'role_sec_formerly' }
            $Synced | Should -Not -BeNullOrEmpty
            $Cloud | Should -Not -BeNullOrEmpty
            $Formerly | Should -Not -BeNullOrEmpty

            $Synced.onPremisesSynced | Should -BeOfType ([bool])
            $Synced.onPremisesSynced | Should -BeTrue
            @($Cloud.PSObject.Properties.Name) | Should -Not -Contain 'onPremisesSynced'
            @($Formerly.PSObject.Properties.Name) | Should -Not -Contain 'onPremisesSynced'
        }

        It 'places onPremisesSynced directly after description in the group projection' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_synced'; Description = 'd'
                    MailNickname = 'rolesec-synced'; GroupType = 'Regular'
                    IsAssignableToRole = $false; MembershipRule = $null
                    OnPremisesSyncEnabled = $true
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy { }
            $Names = [string[]]@((Get-OERInventory -Include Groups).Groups[0].PSObject.Properties.Name)
            $Names | Should -Contain 'onPremisesSynced'
            [Array]::IndexOf($Names, 'onPremisesSynced') | Should -Be ([Array]::IndexOf($Names, 'description') + 1)
        }
    }

    Context 'pimPolicy only for a group that uses PIM for Groups' {
        # Microsoft Graph lists PIM-for-Groups policies for EVERY group, including one never used
        # with PIM for Groups, and the first policy update onboards the group, which cannot be
        # undone. An exported pimPolicy for such a group is a proposal waiting to onboard it, so the
        # section asks Test-OERGroupPimInUse first and exports pimPolicy only for a group in use
        # (docs/development/rationale.md#pim-in-use-criterion, ruling R2).
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_identity_administrator'
                    Description = 'Identity admins'; GroupType = 'RoleEnabled'
                    IsAssignableToRole = $true; MembershipRule = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = $null; ActivationEnabledRules = @('Justification')
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Rules = @(); Notifications = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'person1@example.com' } }
        }

        It 'exports no pimPolicy, and reads no policy, for a group that does not use PIM for Groups' {
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $false; Reason = 'no PIM policy of the group has been modified' }
            }
            $Err = $null
            $Verbose = @(Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
            $Result = @($Verbose | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 0
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 0
            }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
                Should -Be 0 -Because 'a group that does not use PIM for Groups is an answer, not an unread collection'
            $Said = (@($Verbose | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }) | ForEach-Object { $_.Message }) -join "`n"
            $Said | Should -Match ([regex]::Escape("group 'role_sec_identity_administrator': pimPolicy not exported -- no PIM policy of the group has been modified."))
        }

        It 'exports pimPolicy as before for a group whose policy has been modified' {
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $true; Reason = 'a PIM policy of the group has been modified' }
            }
            $Result = Get-OERInventory -Include Groups
            $Result.Groups[0].PSObject.Properties.Name | Should -Contain 'pimPolicy'
            $Result.Groups[0].pimPolicy.member.activationMaxHours | Should -Be 8
            $Result.Groups[0].pimPolicy.owner.activationMaxHours | Should -Be 8
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 2 -Exactly
        }

        It 'passes the eligibility it already read to the criterion, and exports pimPolicy for an eligible group' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_identity_administrator'
                    Description = 'Identity admins'; GroupType = 'RoleEnabled'
                    IsAssignableToRole = $true; MembershipRule = $null
                    Members = @(); Owners = @(); PimEligibility = @(@{ principalId = 'p-1' })
                }
            }
            # In use ONLY when the count arrives: a call site that stopped passing it would export
            # no pimPolicy here and fail the assertion below, not just the parameter filter.
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = ($EligibilityCount -gt 0); Reason = 'from the count' }
            }
            $Result = Get-OERInventory -Include Groups
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 1
            }
            $Result.Groups[0].PSObject.Properties.Name | Should -Contain 'pimPolicy'
        }

        It 'counts no eligibility when the eligibility read failed or held only nulls' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_one'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; MembershipRule = $null; Members = @(); Owners = @()
                }
                [PSCustomObject]@{
                    Id = 'g-2'; DisplayName = 'role_sec_two'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; MembershipRule = $null; Members = @(); Owners = @()
                    PimEligibility = @($null)
                }
            }
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Err = $null
            $Result = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 0
            }
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-2' -and $EligibilityCount -eq 0
            }
            # A "not in use" decided WITHOUT the eligibility half is a guess, not an answer: role_sec_one's
            # eligibility was never read, so its pimPolicy is reported unread beside its eligibility.
            # role_sec_two's eligibility WAS read (and held nothing), so its "not in use" stands.
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1
            $Unread = @(([string]$Partial[0].TargetObject) -split ', ')
            $Unread | Should -Contain 'groups/role_sec_one/eligibility'
            $Unread | Should -Contain 'groups/role_sec_one/pimPolicy'
            $Unread | Should -Not -Contain 'groups/role_sec_two/pimPolicy'
            @($Result.Groups | ForEach-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' }) | Should -Not -Contain $true
        }

        It 'names the unread eligibility cause once, not again for the pimPolicy it left undecided' {
            # The eligibility read's own cause is already on the list; the pimPolicy entry it drags in
            # adds a COLLECTION, never a second cause.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                Write-Error -Message "Could not read PIM eligibility for group g-1: Too many requests (429). The PimEligibility property is omitted rather than reported as empty." `
                    -ErrorId 'GroupPimEligibilityReadFailed' -Category ReadError -TargetObject 'g-1' -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_one'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; MembershipRule = $null; Members = @(); Owners = @()
                }
            }
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x' } }
            $Err = $null
            $null = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err 2>$null
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'groups/role_sec_one/eligibility, groups/role_sec_one/pimPolicy'
            $Causes = ([string]$Partial[0].Exception.Message -split 'Causes: ')[1]
            $Causes | Should -Not -BeNullOrEmpty -Because 'a missing Causes clause would make the counts below vacuous'
            @([regex]::Matches($Causes, 'Could not read PIM eligibility')).Count | Should -Be 1
            $Causes | Should -Not -Match 'Could not determine'
        }

        It 'exports pimPolicy, and reports nothing about it, when a modified policy decides "in use" without the eligibility' {
            # A modified policy is conclusive on its own, so an unread eligibility changes nothing here.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_one'; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; MembershipRule = $null; Members = @(); Owners = @()
                }
            }
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $true; Reason = 'a PIM policy of the group has been modified' }
            }
            $Err = $null
            $Result = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result.Groups[0].PSObject.Properties.Name | Should -Contain 'pimPolicy'
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            [string]$Partial[0].TargetObject | Should -Be 'groups/role_sec_one/eligibility'
        }

        It 'omits pimPolicy and reports it unread when the criterion itself cannot be read' {
            # Review Focus 4: never guessed in either direction. Not exported (an export would claim
            # a use nobody measured), and not silently absent either (that would claim the group
            # does not use PIM for Groups) -- the collection is named in InventoryPartial.
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, 'g-1')
            }
            $Err = $null
            $Result = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err `
                -WarningAction SilentlyContinue -WarningVariable Warned
            $Result.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 0
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1 -Because 'a criterion nobody could read leaves the pimPolicy collection unread'
            [string]$Partial[0].TargetObject | Should -Be 'groups/role_sec_identity_administrator/pimPolicy'
            [string]$Partial[0].Exception.Message |
                Should -Match 'Could not determine whether group .g-1. uses PIM for Groups: Authorization_RequestDenied'
            $Warned | Should -BeNullOrEmpty -Because 'a per-collection failure is accounted for at the projection, not warned once per group'
        }
    }

    Context 'AdministrativeUnits section' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-IT'; Description = 'IT scoped'
                    IsMemberManagementRestricted = $false
                    Members = @(
                        [PSCustomObject]@{ Id = 'u-1'; DisplayName = 'Admin User'; UserPrincipalName = 'person12@example.com' },
                        [PSCustomObject]@{ Id = 'g-2'; DisplayName = 'role_sec_x' }
                    )
                    ScopedRoles = @([PSCustomObject]@{ RoleName = 'User Administrator'; PrincipalId = 'p-9'; PrincipalDisplayName = 'role_sec_identity_administrator' })
                }
            }
        }

        It 'projects an administrative unit with members and scoped roles' {
            $Result = Get-OERInventory -Include AdministrativeUnits
            @($Result.AdministrativeUnits).Count | Should -Be 1
            $au = $Result.AdministrativeUnits[0]
            $au.displayName | Should -Be 'AU-IT'
            $au.restricted | Should -BeFalse
            $au.members | Should -Contain 'person12@example.com'
            $au.members | Should -Contain 'g-2'
            $au.members | Should -Not -Contain 'Admin User'
            $au.scopedRoles[0].role | Should -Be 'User Administrator'
            $au.scopedRoles[0].principal | Should -Be 'p-9'
        }

        It 'reads administrative units with members and scoped roles expanded' {
            Get-OERInventory -Include AdministrativeUnits | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -ParameterFilter {
                $IncludeMembers -eq $true -and $IncludeScopedRoles -eq $true
            }
        }
    }

    Context 'administrativeUnits dynamic and visibility round-trip projection' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                $Dyn = [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'au_dynamic'; Description = 'dyn'
                    MembershipType = 'Dynamic'; MembershipRule = '(user.country -eq "SE")'
                    MembershipRuleProcessingState = 'Paused'
                    IsMemberManagementRestricted = $false; Visibility = 'HiddenMembership'
                }
                $Dyn | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $Dyn | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                $Static = [PSCustomObject]@{
                    Id = 'au-2'; DisplayName = 'au_static'; Description = $null
                    MembershipType = 'Assigned'; MembershipRule = $null
                    MembershipRuleProcessingState = $null
                    IsMemberManagementRestricted = $true; Visibility = $null
                }
                $Static | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $Static | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                @($Dyn, $Static)
            }
        }

        It 'projects dynamic true with the membership rule and processing state' {
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits) | Where-Object { $_.displayName -eq 'au_dynamic' }
            $Au.dynamic | Should -BeTrue
            $Au.membershipRule | Should -Be '(user.country -eq "SE")'
            $Au.membershipRuleProcessingState | Should -Be 'Paused'
        }

        It 'projects hiddenMembership true for a HiddenMembership unit' {
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits) | Where-Object { $_.displayName -eq 'au_dynamic' }
            $Au.hiddenMembership | Should -BeTrue
        }

        It 'projects dynamic false and hiddenMembership false for an assigned public unit' {
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits) | Where-Object { $_.displayName -eq 'au_static' }
            $Au.dynamic | Should -BeFalse
            $Au.hiddenMembership | Should -BeFalse
            # BeFalse alone cannot distinguish "emitted as $false" from "not emitted" ($null is
            # also falsy), and the brief requires both keys to be emitted ALWAYS -- so also assert
            # the keys are actually present on the projected object.
            $Au.PSObject.Properties.Name | Should -Contain 'dynamic'
            $Au.PSObject.Properties.Name | Should -Contain 'hiddenMembership'
            $Au.PSObject.Properties.Name | Should -Not -Contain 'membershipRule'
        }

        It 'omits members for a dynamic administrative unit' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                $Dyn = [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'au_dynamic'; Description = 'dyn'
                    MembershipType = 'Dynamic'; MembershipRule = '(user.country -eq "SE")'
                    MembershipRuleProcessingState = 'Paused'
                    IsMemberManagementRestricted = $false; Visibility = $null
                }
                $Dyn | Add-Member -NotePropertyName Members -NotePropertyValue @(
                    [PSCustomObject]@{ Id = 'u-1'; DisplayName = 'Admin User'; UserPrincipalName = 'person12@example.com' }
                    [PSCustomObject]@{ Id = 'u-2'; DisplayName = 'Other User'; UserPrincipalName = 'person13@example.com' }
                ) -Force
                $Dyn | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                $Dyn
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name | Should -Not -Contain 'members'
        }

        It 'still emits members for an assigned administrative unit' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                $Static = [PSCustomObject]@{
                    Id = 'au-2'; DisplayName = 'au_static'; Description = $null
                    MembershipType = 'Assigned'; MembershipRule = $null
                    MembershipRuleProcessingState = $null
                    IsMemberManagementRestricted = $false; Visibility = $null
                }
                $Static | Add-Member -NotePropertyName Members -NotePropertyValue @(
                    [PSCustomObject]@{ Id = 'u-1'; DisplayName = 'Admin User'; UserPrincipalName = 'person12@example.com' }
                ) -Force
                $Static | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                $Static
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name | Should -Contain 'members'
            $Au.members | Should -Contain 'person12@example.com'
        }
    }

    Context 'administrativeUnits -IncludeId' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                $Au = [PSCustomObject]@{
                    Id = 'au-99'; DisplayName = 'AU-Ids'; Description = $null
                    MembershipType = 'Assigned'; MembershipRule = $null
                    MembershipRuleProcessingState = $null
                    IsMemberManagementRestricted = $false; Visibility = $null
                }
                $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                $Au
            }
        }

        It 'stamps id on the administrative unit only with -IncludeId, exactly once' {
            $Inv = Get-OERInventory -Include AdministrativeUnits -IncludeId
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.id | Should -Be 'au-99'
            @($Au.PSObject.Properties.Name | Where-Object { $_ -eq 'id' }).Count | Should -Be 1
        }

        It 'omits id from the administrative unit without -IncludeId' {
            $Inv = Get-OERInventory -Include AdministrativeUnits
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name | Should -Not -Contain 'id'
        }
    }

    Context 'administrativeUnits scoped role id fallback' {
        BeforeEach {
            # Sprint 11 step 8: a scoped role principal named by object id is looked up for its type. The
            # fixtures below name a user by object id, answered here as the directory returns one, so
            # their rows also carry principalType User and nothing is reported unread.
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName {
                foreach ($One in @($Id)) {
                    [PSCustomObject]@{ Id = $One; Read = $true; Found = $true; Name = 'Anna'; ObjectType = 'user'; DisplayName = 'Anna'; UserPrincipalName = $null; Cause = $null }
                }
            }
        }

        It 'falls back to the role id when the directory role name could not be resolved' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'au_hr'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @([PSCustomObject]@{
                        RoleName = $null
                        RoleId = '22222222-2222-2222-2222-222222222222'
                        PrincipalId = '33333333-3333-3333-3333-333333333333'
                        PrincipalDisplayName = 'Anna'
                    })
                }
            }
            $Scoped = @((Get-OERInventory -Include AdministrativeUnits).AdministrativeUnits[0].scopedRoles)[0]
            $Scoped.role | Should -Be '22222222-2222-2222-2222-222222222222'
        }

        It 'treats a directory role name that is only whitespace as missing: the role id is written, scopedRoles is not null and nothing is reported' {
            # F4. A RoleName of '   ' is truthy, so a bare truthiness test would keep it, then refuse
            # it as blank a line later and write the whole collection as null with an InventoryPartial,
            # although the role id was there to fall back to.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'au_hr'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @([PSCustomObject]@{
                        RoleName = '   '
                        RoleId = '22222222-2222-2222-2222-222222222222'
                        PrincipalId = '33333333-3333-3333-3333-333333333333'
                        PrincipalDisplayName = 'Anna'
                    })
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr

            # Positive proof first: the unit was read and projected, with its scoped role written.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAdministrativeUnit -Times 1 -Exactly
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.displayName | Should -BeExactly 'au_hr'
            $Au.PSObject.Properties.Name -contains 'scopedRoles' | Should -BeTrue
            $null -eq $Au.scopedRoles | Should -BeFalse -Because 'the role id is a name the apply engine accepts, so the collection is a fact and not an explicit null'
            @($Au.scopedRoles).Count | Should -Be 1
            $Au.scopedRoles[0].role | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            $Au.scopedRoles[0].principal | Should -BeExactly '33333333-3333-3333-3333-333333333333'
            $InvPartial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $InvPartial.Count | Should -Be 0 -Because 'nothing was left unread, so no InventoryPartial names the unit''s scopedRoles'
        }
    }

    Context 'administrativeUnits scoped role principalType (Sprint 11 step 8)' {
        # A scoped role row whose principal is an object id carries principalType when the directory
        # returned that principal as a user, a group or a service principal. Every such principal of every
        # unit is looked up in ONE Resolve-OERPrincipalName -Detailed call. No id below is version-4 shaped.
        BeforeAll {
            $script:SrUser = 'aaaa7777-0000-0000-0000-000000000001'
            $script:SrGroup = 'bbbb7777-0000-0000-0000-000000000001'
            $script:SrSp = 'cccc7777-0000-0000-0000-000000000001'
            $script:SrDevice = 'dddd7777-0000-0000-0000-000000000001'
            $script:SrGone = 'eeee7777-0000-0000-0000-000000000001'
            # The type the directory returns for each principal it holds; SrGone it does not return.
            $script:SrTypeById = @{
                $script:SrUser   = 'user'
                $script:SrGroup  = 'group'
                $script:SrSp     = 'servicePrincipal'
                $script:SrDevice = 'device'
            }
            function script:New-SrMembership {
                param([string]$Role, [string]$PrincipalId, [string]$PrincipalDisplayName = 'fixture')
                [PSCustomObject]@{ RoleName = $Role; RoleId = 'r-1'; PrincipalId = $PrincipalId; PrincipalDisplayName = $PrincipalDisplayName; ScopedRoleMembershipId = "srm-$PrincipalId" }
            }
            function script:New-SrUnit {
                param([string]$Name, [object[]]$ScopedRoles)
                [PSCustomObject]@{
                    Id = "au-$Name"; DisplayName = $Name; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @(); ScopedRoles = @($ScopedRoles)
                }
            }
            # AU-A: a user, a group and a service principal. AU-B: the same user again, a device, a principal
            # the directory does not return, and one named by its display name (no object id). AU-C: none.
            $script:SrUnits = @(
                New-SrUnit -Name 'AU-A' -ScopedRoles @(
                    New-SrMembership -Role 'User Administrator' -PrincipalId $script:SrUser
                    New-SrMembership -Role 'Groups Administrator' -PrincipalId $script:SrGroup
                    New-SrMembership -Role 'Helpdesk Administrator' -PrincipalId $script:SrSp
                )
                New-SrUnit -Name 'AU-B' -ScopedRoles @(
                    New-SrMembership -Role 'Helpdesk Administrator' -PrincipalId $script:SrUser
                    New-SrMembership -Role 'User Administrator' -PrincipalId $script:SrDevice
                    New-SrMembership -Role 'User Administrator' -PrincipalId $script:SrGone
                    New-SrMembership -Role 'Groups Administrator' -PrincipalId $null -PrincipalDisplayName 'Person Two'
                )
                New-SrUnit -Name 'AU-C' -ScopedRoles @()
            )
            # The names of a row's keys and its principalType, for one exact comparison per unit.
            function script:Get-SrRowShape {
                param([object]$Unit)
                @(@($Unit.scopedRoles) | ForEach-Object { "$($_.principal)|$(@($_.PSObject.Properties.Name) -join ',')|$($_.principalType)" })
            }
        }

        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { $script:SrUnits }
            # The directory's answer: a held principal is returned with its type; any other is read and not
            # found. The not-found answer carries a type on purpose: Found alone decides, never the type.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                foreach ($One in @($Id)) {
                    if ($script:SrTypeById.ContainsKey($One)) {
                        [PSCustomObject]@{ Id = $One; Read = $true; Found = $true; Name = "name-$One"; ObjectType = $script:SrTypeById[$One]; DisplayName = "name-$One"; UserPrincipalName = $null; Cause = $null }
                    } else {
                        [PSCustomObject]@{ Id = $One; Read = $true; Found = $false; Name = $null; ObjectType = 'user'; DisplayName = $null; UserPrincipalName = $null; Cause = $null }
                    }
                }
            }
        }

        It 'writes principalType User, Group and ServicePrincipal after principal, and nothing for a device, a principal not found or one named by display name' {
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Units = @($Inv.AdministrativeUnits)
            @($Units.displayName) | Should -BeExactly @('AU-A', 'AU-B', 'AU-C')
            Get-SrRowShape -Unit $Units[0] | Should -BeExactly @(
                "$($script:SrUser)|role,principal,principalType|User"
                "$($script:SrGroup)|role,principal,principalType|Group"
                "$($script:SrSp)|role,principal,principalType|ServicePrincipal"
            )
            Get-SrRowShape -Unit $Units[1] | Should -BeExactly @(
                "$($script:SrUser)|role,principal,principalType|User"
                "$($script:SrDevice)|role,principal|"
                "$($script:SrGone)|role,principal|"
                'Person Two|role,principal|'
            )
            $Units[2].PSObject.Properties.Name | Should -Contain 'scopedRoles'
            @($Units[2].scopedRoles).Count | Should -Be 0
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }) | Should -BeNullOrEmpty -Because 'a principal not found, a device and a display name are facts about the rows, not unread reads'
        }

        It 'looks the distinct object ids of every unit up in exactly one lookup, and never a display name' {
            $null = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly -ParameterFilter {
                $Detailed -and (@($Id) -join ',') -ceq "$($script:SrUser),$($script:SrGroup),$($script:SrSp),$($script:SrDevice),$($script:SrGone)"
            }
        }

        It 'makes no lookup when no unit names a scoped role principal by object id (<Case>)' -ForEach @(
            @{ Case = 'no unit has a scoped role'; ByName = $false }
            @{ Case = 'every principal is named by display name'; ByName = $true }
        ) {
            $script:SrNoIdUnits = @(
                New-SrUnit -Name 'AU-A' -ScopedRoles $(if ($ByName) { @(New-SrMembership -Role 'User Administrator' -PrincipalId $null -PrincipalDisplayName 'Person Two') } else { @() })
                New-SrUnit -Name 'AU-B' -ScopedRoles @()
            )
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { $script:SrNoIdUnits }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            # Positive control: both units were read and projected with their scoped roles.
            @($Inv.AdministrativeUnits.displayName) | Should -BeExactly @('AU-A', 'AU-B')
            @($Inv.AdministrativeUnits[0].scopedRoles).Count | Should -Be $(if ($ByName) { 1 } else { 0 })
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }) | Should -BeNullOrEmpty
        }

        It 'writes no principalType when the lookup fails, names each affected unit once, and keeps the scoped roles written' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                foreach ($One in @($Id)) {
                    [PSCustomObject]@{ Id = $One; Read = $false; Found = $false; Name = $null; ObjectType = $null; DisplayName = $null; UserPrincipalName = $null; Cause = 'TooManyRequests (injected)' }
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Units = @($Inv.AdministrativeUnits)
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            Get-SrRowShape -Unit $Units[0] | Should -BeExactly @(
                "$($script:SrUser)|role,principal|"
                "$($script:SrGroup)|role,principal|"
                "$($script:SrSp)|role,principal|"
            )
            Get-SrRowShape -Unit $Units[1] | Should -BeExactly @(
                "$($script:SrUser)|role,principal|"
                "$($script:SrDevice)|role,principal|"
                "$($script:SrGone)|role,principal|"
                'Person Two|role,principal|'
            )
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            # Each unit whose principals were not read is named once; AU-C has none and is not named.
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-A/scopedRoles/principalType, administrativeUnits/AU-B/scopedRoles/principalType'
            $Message = $Partial[0].Exception.Message
            $Message | Should -Match ([regex]::Escape('Could not look up the type of a scoped role principal through directoryObjects/getByIds: TooManyRequests (injected)'))
            $Message | Should -Match ([regex]::Escape('An entry ending in scopedRoles/principalType is not such a key: it names a unit whose scoped role rows are written without principalType, since their principals'' type could not be read.'))
        }

        It 'names a unit with the cause of its first principal whose lookup failed' {
            # Each principal's lookup fails with a cause of its own. AU-A's first row is the user, and so is
            # AU-B's, so both units name the user's cause, and no other principal's cause is shown.
            $script:SrCauseById = @{
                $script:SrUser = 'injected cause A'; $script:SrGroup = 'injected cause B'; $script:SrSp = 'injected cause C'
                $script:SrDevice = 'injected cause D'; $script:SrGone = 'injected cause E'
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                foreach ($One in @($Id)) {
                    [PSCustomObject]@{ Id = $One; Read = $false; Found = $false; Name = $null; ObjectType = $null; DisplayName = $null; UserPrincipalName = $null; Cause = $script:SrCauseById[$One] }
                }
            }
            $null = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-A/scopedRoles/principalType, administrativeUnits/AU-B/scopedRoles/principalType'
            $Message = $Partial[0].Exception.Message
            $Message | Should -Match ([regex]::Escape('Causes: Could not look up the type of a scoped role principal through directoryObjects/getByIds: injected cause A.'))
            foreach ($Other in 'injected cause B', 'injected cause C', 'injected cause D', 'injected cause E') {
                $Message | Should -Not -Match $Other
            }
        }

        It 'reads a principal the lookup gave no answer for as not read, never as one the directory did not return' {
            # Only AU-A's group is answered; every other object id is missing from the answer.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                [PSCustomObject]@{ Id = $script:SrGroup; Read = $true; Found = $true; Name = 'g'; ObjectType = 'group'; DisplayName = 'g'; UserPrincipalName = $null; Cause = $null }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Get-SrRowShape -Unit @($Inv.AdministrativeUnits)[0] | Should -BeExactly @(
                "$($script:SrUser)|role,principal|"
                "$($script:SrGroup)|role,principal,principalType|Group"
                "$($script:SrSp)|role,principal|"
            )
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-A/scopedRoles/principalType, administrativeUnits/AU-B/scopedRoles/principalType'
            $Partial[0].Exception.Message | Should -Match ([regex]::Escape('directoryObjects/getByIds: the lookup returned no answer for this principal.'))
        }

        It 'leaves a unit whose scoped roles could not be read as it was, and looks nothing up for it' {
            $script:SrUnreadUnit = [PSCustomObject]@{
                Id = 'au-AU-D'; DisplayName = 'AU-D'; Description = $null
                IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null; Members = @()
            }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { $script:SrUnreadUnit }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name | Should -Contain 'scopedRoles'
            $null -eq $Au.scopedRoles | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-D/scopedRoles'
        }

        It 'states the rule in its help' {
            $Help = (Get-Command -Name Get-OERInventory -Module $script:moduleName).ScriptBlock.Ast.GetHelpContent().Description
            $Help | Should -Match 'In AdministrativeUnits, a scoped role row whose principal is an object id carries principalType'
            $Help | Should -Match ([regex]::Escape("reports 'administrativeUnits/<name>/scopedRoles/principalType' through the"))
        }
    }

    Context 'Catalogs section' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ DisplayName = 'role_sec_identity_administrator'; ResourceType = 'Group'; OriginSystem = 'AadGroup' }
            }
        }

        It 'projects a catalog with its resources' {
            $Result = Get-OERInventory -Include Catalogs
            @($Result.Catalogs).Count | Should -Be 1
            $cat = $Result.Catalogs[0]
            $cat.displayName | Should -Be 'CAT-IT-Core'
            $cat.resources[0].type | Should -Be 'Group'
            $cat.resources[0].name | Should -Be 'role_sec_identity_administrator'
        }

        It 'projects catalog externallyVisible' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core'; ExternallyVisible = $true }
            }
            (Get-OERInventory -Include Catalogs).Catalogs[0].externallyVisible | Should -Be $true
        }

        It 'projects externallyVisible false when the catalog is internal-only' {
            (Get-OERInventory -Include Catalogs).Catalogs[0].externallyVisible | Should -Be $false
        }

        It 'maps a SharePoint resource type from originSystem to the schema enum' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ DisplayName = 'Finance Site'; ResourceType = 'SharePoint Online Site'; OriginSystem = 'SharePointOnline' }
            }
            (Get-OERInventory -Include Catalogs).Catalogs[0].resources[0].type | Should -Be 'SharePointSite'
        }

        It 'reads resources for the catalog by id' {
            Get-OERInventory -Include Catalogs | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -ParameterFilter { $Catalog -eq 'cat-1' }
        }

        It 'narrows to one catalog with -Catalog' {
            Get-OERInventory -Include Catalogs -Catalog 'CAT-IT-Core' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-IT-Core' }
        }

        It 'reads a catalog by id when -Catalog is a GUID' {
            Get-OERInventory -Include Catalogs -Catalog '00000000-0000-0000-0000-000000000001' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq '00000000-0000-0000-0000-000000000001' }
        }
    }

    Context 'Catalog resolution hoisting (6b: shared between Catalogs and AccessPackages)' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { @() }
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'CAT-Hoist'; Description = 'd' }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { @() }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { @() }
        }

        It 'resolves a GUID -Catalog filter once for the default -Include (Catalogs + AccessPackages both selected), not once per section' {
            $Guid = '11111111-1111-1111-1111-111111111111'
            Get-OERInventory -Catalog $Guid | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq $Guid }
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 0 -Exactly -ParameterFilter { $DisplayName }
        }

        It 'resolves a display-name -Catalog filter once for the default -Include, not once per section' {
            Get-OERInventory -Catalog 'CAT-Hoist' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-Hoist' }
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 0 -Exactly -ParameterFilter { $Id }
        }

        It 'never calls Get-OERCatalog when -Include selects neither Catalogs nor AccessPackages' {
            Get-OERInventory -Include Groups -Catalog '11111111-1111-1111-1111-111111111111' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 0 -Exactly
        }

        It 'still populates both the Catalogs and AccessPackages sections identically from the shared resolution' {
            # NOTE: deliberately NOT named $CatalogId. Get-OERAccessPackage's -Catalog parameter
            # carries [Alias('CatalogId')], and Pester's ParameterFilter scriptblock exposes an
            # alias-bound value under the ALIAS name too -- a local variable named $CatalogId would be
            # invisibly shadowed by that alias binding inside the filter below, making
            # "$Catalog -eq $CatalogId" compare the call's own bound value against itself and pass
            # unconditionally regardless of what was actually passed. Verified empirically: with this
            # variable named $CatalogId, a deliberate mutation that hardcoded the wrong -Catalog value
            # at the call site still made this assertion pass.
            $TargetCatalogId = '11111111-1111-1111-1111-111111111111'
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Hoist'; Description = 'd'; CatalogId = $TargetCatalogId }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { @() }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
            $Result = Get-OERInventory -Catalog $TargetCatalogId
            $Result.Catalogs[0].displayName | Should -Be 'CAT-Hoist'
            # description is a distinct field from displayName -- a hoist that dropped a projected
            # catalog property (rather than just its displayName) would still slip past a
            # displayName-only assertion.
            $Result.Catalogs[0].description | Should -Be 'd'
            $Result.AccessPackages[0].displayName | Should -Be 'AP-Hoist'
            $Result.AccessPackages[0].catalog | Should -Be 'CAT-Hoist'
            $Result.AccessPackages[0].description | Should -Be 'd'
            # Pins that the AccessPackages section reads packages via the shared $ApCat.Id (not a
            # second, independently-resolved catalog object) -- proving the object, not just its
            # display name, made it through the hoist.
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq $TargetCatalogId }
        }
    }

    Context 'Catalog resource projection' {
        It 'projects the SharePoint site URL as url alongside the display name' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = 'd' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERCatalogResource {
                [PSCustomObject]@{
                    Id           = 'res-1'
                    DisplayName  = 'Finance'
                    OriginId     = 'https://contoso.sharepoint.com/sites/finance'
                    OriginSystem = 'SharePointOnline'
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessPackage { }

            $Inventory = Get-OERInventory -Include Catalogs
            $Resource  = @($Inventory.Catalogs[0].resources)[0]

            $Resource.type | Should -Be 'SharePointSite'
            $Resource.name | Should -Be 'Finance'
            $Resource.url  | Should -Be 'https://contoso.sharepoint.com/sites/finance'
        }

        It 'does not emit url for a group resource' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = 'd' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERCatalogResource {
                [PSCustomObject]@{
                    Id           = 'res-2'
                    DisplayName  = 'grp-finance'
                    OriginId     = '11111111-1111-1111-1111-111111111111'
                    OriginSystem = 'AadGroup'
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessPackage { }
            # A group resource's current name is looked up by originId through the Graph wrapper.
            # Unmocked, that lookup reached the real transport (found by the transport tripwire).
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }

            $Resource = @((Get-OERInventory -Include Catalogs).Catalogs[0].resources)[0]
            $Resource.type | Should -Be 'Group'
            $Resource.PSObject.Properties.Name | Should -Not -Contain 'url'
        }
    }

    # A catalog keeps the display name a resource had when it was added, also after the group or
    # application is renamed (measured live 2026-09-30); the apply engine identifies a Group or
    # Application resource by the object id its name resolves to. So both sections write the group's
    # or application's CURRENT name, looked up by originId, with the id as the fallback.
    Context 'Catalog and access package resources are exported under their current name' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = 'd' } }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                @(
                    [PSCustomObject]@{ Id = 'res-g'; DisplayName = 'grp-old'; OriginId = '11111111-aaaa-1111-1111-000000000001'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
                    [PSCustomObject]@{ Id = 'res-a'; DisplayName = 'App Old'; OriginId = '11111111-aaaa-1111-1111-000000000002'; OriginSystem = 'AadApplication'; ResourceType = 'Application' }
                    [PSCustomObject]@{ Id = 'res-s'; DisplayName = 'Finance'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; OriginSystem = 'SharePointOnline' }
                )
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                @{ '11111111-aaaa-1111-1111-000000000001' = 'grp-new'; '11111111-aaaa-1111-1111-000000000002' = 'App New' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-1'; Description = 'd' } }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = '11111111-aaaa-1111-1111-000000000001' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
        }

        It 'writes a renamed group''s and application''s CURRENT name in resources[], and a site''s name as it stands' {
            $Res = @((Get-OERInventory -Include Catalogs).Catalogs[0].resources)
            ($Res | Where-Object type -eq 'Group').name | Should -BeExactly 'grp-new'
            ($Res | Where-Object type -eq 'Application').name | Should -BeExactly 'App New'
            ($Res | Where-Object type -eq 'SharePointSite').name | Should -BeExactly 'Finance'
            # Only the group and the application are looked up, by their originIds, in one call.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Exactly -Times 1 -ParameterFilter {
                $PreferDisplayName -and @($Id).Count -eq 2 -and @($Id) -contains '11111111-aaaa-1111-1111-000000000001' -and @($Id) -contains '11111111-aaaa-1111-1111-000000000002'
            }
        }

        It 'writes the object id when the lookup returns the id itself (a deleted or unreadable object)' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = $I }; $M }
            $Res = @((Get-OERInventory -Include Catalogs).Catalogs[0].resources)
            ($Res | Where-Object type -eq 'Group').name | Should -BeExactly '11111111-aaaa-1111-1111-000000000001'
        }

        It 'names the access package resource role by the same current name, with one lookup shared by both sections' {
            $Result = Get-OERInventory -Include Catalogs, AccessPackages
            $Result.AccessPackages[0].resourceRoles[0].resource | Should -BeExactly 'grp-new'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Exactly -Times 1
        }
    }

    Context 'AccessPackages section' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; CatalogId = 'cat-1' }
            }
            # The catalog resource carries the real display name keyed by OriginId; the binding's scope
            # display name (ResourceDisplayName) is only the scope label (e.g. 'Root').
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            # The group's current name, looked up by originId, equals the recorded one here.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_x' }; $M }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName    = 'Default'
                    RequestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                    ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                    DurationInDays = 30
                }
            }
        }

        It 'projects an access package with catalog, resourceRoles and policy internals' {
            $Result = Get-OERInventory -Include AccessPackages
            @($Result.AccessPackages).Count | Should -Be 1
            $ap = $Result.AccessPackages[0]
            $ap.displayName | Should -Be 'AP-Sales'
            $ap.catalog | Should -Be 'CAT-IT-Core'
            # Joined on OriginId to the catalog resource -- the scope label 'Root' is replaced with the
            # real resource name so the apply engine can resolve the binding back.
            $ap.resourceRoles[0].resource | Should -Be 'role_sec_x'
            $ap.resourceRoles[0].role | Should -Be 'Member'
            $ap.assignmentPolicies[0].displayName | Should -Be 'Default'
            $ap.assignmentPolicies[0].requestorScope.scope | Should -Be 'AllMemberUsers'
            $ap.assignmentPolicies[0].approvalStages[0].durationDays | Should -Be 7
            $ap.assignmentPolicies[0].approvalStages[0].manager | Should -BeTrue
            $ap.assignmentPolicies[0].durationInDays | Should -Be 30
        }

        It 'reads resource roles for the access package by id (M1)' {
            Get-OERInventory -Include AccessPackages | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -ParameterFilter { $AccessPackage -eq 'ap-1' }
        }

        It 'falls back to the binding display name when its OriginId is not in the catalog' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'Legacy Resource'; RoleName = 'Member'; OriginId = 'orig-unknown' }
            }
            $ap = (Get-OERInventory -Include AccessPackages).AccessPackages[0]
            $ap.resourceRoles[0].resource | Should -Be 'Legacy Resource'
        }

        It 'reads assignment policies for the access package' {
            Get-OERInventory -Include AccessPackages | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -ParameterFilter { $AccessPackage -eq 'ap-1' }
        }

        It 'omits policy internals that are absent (displayName-only policy stays valid)' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName = 'Bare'; RequestorScope = $null; ApprovalStages = @(); DurationInDays = $null
                    Description = $null
                    RequestorSettings = $null
                    RequireApproval = $false; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    DurationInHours = $null; ExpirationDateTime = $null
                    NotificationsDisabled = $false
                }
            }
            $pol = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0]
            $pol.displayName | Should -Be 'Bare'
            # optional fields absent when null/empty
            $pol.PSObject.Properties.Name | Should -Not -Contain 'requestorScope'
            $pol.PSObject.Properties.Name | Should -Not -Contain 'approvalStages'
            $pol.PSObject.Properties.Name | Should -Not -Contain 'durationInDays'
            # always-emit fields must be present even when their source is null
            $pol.PSObject.Properties.Name | Should -Contain 'requestorSettings'
            $pol.PSObject.Properties.Name | Should -Contain 'requireApproval'
            $pol.PSObject.Properties.Name | Should -Contain 'requireRequestorJustification'
            $pol.PSObject.Properties.Name | Should -Contain 'requireApprovalForUpdate'
            $pol.PSObject.Properties.Name | Should -Contain 'notificationsDisabled'
        }

        It 'projects granular AP policy fields: description, requestorSettings, requireApproval booleans, full approvalStage, durationInHours, notificationsDisabled' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName     = 'Full Policy'
                    Description     = 'A detailed policy'
                    RequestorScope  = [PSCustomObject]@{
                        scope  = 'SpecificDirectoryUsers'
                        users  = @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
                        groups = @()
                    }
                    RequestorSettings = [PSCustomObject]@{
                        AllowSelfRequest    = $true
                        AllowManagerRequest = $true
                        ManagerLevel        = 2
                        AllowCustomSchedule = $false
                        AllowSelfExtend     = $true
                        AllowSelfRemove     = $true
                        AllowOnBehalfUpdate = $true
                        AllowOnBehalfRemove = $true
                    }
                    RequireApproval               = $true
                    RequireRequestorJustification = $true
                    RequireApprovalForUpdate      = $false
                    ApprovalStages = @(
                        [PSCustomObject]@{
                            durationDays                = 5
                            manager                     = $false
                            managerLevel                = $null
                            users                       = @('bbbbbbbb-0000-0000-0000-000000000001')
                            groups                      = @()
                            internalSponsor             = $false
                            externalSponsor             = $false
                            alternateUsers              = @()
                            alternateGroups             = @()
                            fallbackUsers               = @('cccccccc-0000-0000-0000-000000000001')
                            fallbackGroups              = @('dddddddd-0000-0000-0000-000000000001')
                            escalationDays              = 3
                            requireApproverJustification = $true
                            approverInfoVisibility      = 'Visible'
                        }
                    )
                    DurationInDays    = $null
                    DurationInHours   = 8
                    ExpirationDateTime = $null
                    NotificationsDisabled = $true
                }
            }
            $pol = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0]
            # description
            $pol.description | Should -Be 'A detailed policy'
            # requestorScope -- scope + non-empty users; empty groups omitted
            $pol.requestorScope.scope | Should -Be 'SpecificDirectoryUsers'
            $pol.requestorScope.users | Should -Contain 'aaaaaaaa-0000-0000-0000-000000000001'
            $pol.requestorScope.PSObject.Properties.Name | Should -Not -Contain 'groups'
            # requestorSettings -- always emitted; includes managerLevel when allowManagerRequest
            $pol.requestorSettings.allowSelfRequest | Should -BeTrue
            $pol.requestorSettings.allowManagerRequest | Should -BeTrue
            $pol.requestorSettings.managerLevel | Should -Be 2
            $pol.requestorSettings.allowCustomSchedule | Should -BeFalse
            $pol.requestorSettings.allowSelfExtend | Should -BeTrue
            $pol.requestorSettings.allowSelfRemove | Should -BeTrue
            $pol.requestorSettings.allowOnBehalfUpdate | Should -BeTrue
            $pol.requestorSettings.allowOnBehalfRemove | Should -BeTrue
            # booleans -- always emitted
            $pol.requireApproval | Should -BeTrue
            $pol.requireRequestorJustification | Should -BeTrue
            $pol.requireApprovalForUpdate | Should -BeFalse
            # approvalStages -- non-empty users present; empty groups/alternateUsers/alternateGroups omitted
            @($pol.approvalStages).Count | Should -Be 1
            $stage = $pol.approvalStages[0]
            $stage.durationDays | Should -Be 5
            $stage.manager | Should -BeFalse
            $stage.users | Should -Contain 'bbbbbbbb-0000-0000-0000-000000000001'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'groups'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'alternateUsers'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'alternateGroups'
            $stage.fallbackUsers | Should -Contain 'cccccccc-0000-0000-0000-000000000001'
            $stage.fallbackGroups | Should -Contain 'dddddddd-0000-0000-0000-000000000001'
            $stage.escalationDays | Should -Be 3
            $stage.requireApproverJustification | Should -BeTrue
            $stage.approverInfoVisibility | Should -Be 'Visible'
            # expiration -- durationInHours set; durationInDays must NOT be emitted
            $pol.durationInHours | Should -Be 8
            $pol.PSObject.Properties.Name | Should -Not -Contain 'durationInDays'
            # notificationsDisabled
            $pol.notificationsDisabled | Should -BeTrue
        }

        It 'emits durationInDays when set and skips durationInHours/expirationDateTime' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName = 'Days Policy'; Description = $null
                    RequestorScope = $null; RequestorSettings = $null
                    RequireApproval = $false; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    ApprovalStages = @()
                    DurationInDays = 30; DurationInHours = $null; ExpirationDateTime = $null
                    NotificationsDisabled = $false
                }
            }
            $pol = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0]
            $pol.durationInDays | Should -Be 30
            $pol.PSObject.Properties.Name | Should -Not -Contain 'durationInHours'
            $pol.PSObject.Properties.Name | Should -Not -Contain 'expirationDateTime'
        }

        It 'emits expirationDateTime when durationInDays and durationInHours are both absent' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName = 'Date Policy'; Description = $null
                    RequestorScope = $null; RequestorSettings = $null
                    RequireApproval = $false; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    ApprovalStages = @()
                    DurationInDays = $null; DurationInHours = $null; ExpirationDateTime = '2027-01-01T00:00:00Z'
                    NotificationsDisabled = $false
                }
            }
            $pol = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0]
            $pol.expirationDateTime | Should -Be '2027-01-01T00:00:00Z'
            $pol.PSObject.Properties.Name | Should -Not -Contain 'durationInDays'
            $pol.PSObject.Properties.Name | Should -Not -Contain 'durationInHours'
        }

        It 'omits managerLevel from requestorSettings when allowManagerRequest is false' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName = 'Self Policy'; Description = $null
                    RequestorScope = $null
                    RequestorSettings = [PSCustomObject]@{
                        AllowSelfRequest = $true; AllowManagerRequest = $false; ManagerLevel = 1
                        AllowCustomSchedule = $false; AllowSelfExtend = $false
                    }
                    RequireApproval = $false; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    ApprovalStages = @()
                    DurationInDays = $null; DurationInHours = $null; ExpirationDateTime = $null
                    NotificationsDisabled = $false
                }
            }
            $pol = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0]
            $pol.requestorSettings.allowManagerRequest | Should -BeFalse
            $pol.requestorSettings.PSObject.Properties.Name | Should -Not -Contain 'managerLevel'
        }

        It 'omits optional stage fields (managerLevel, internalSponsor, etc.) when not set/false' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName = 'Manager Policy'; Description = $null
                    RequestorScope = $null; RequestorSettings = $null
                    RequireApproval = $true; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    ApprovalStages = @(
                        [PSCustomObject]@{
                            durationDays = 7; manager = $true; managerLevel = $null
                            users = @(); groups = @()
                            internalSponsor = $false; externalSponsor = $false
                            alternateUsers = @(); alternateGroups = @()
                            fallbackUsers = @(); fallbackGroups = @()
                            escalationDays = $null
                            requireApproverJustification = $false; approverInfoVisibility = 'Default'
                        }
                    )
                    DurationInDays = $null; DurationInHours = $null; ExpirationDateTime = $null
                    NotificationsDisabled = $false
                }
            }
            $stage = (Get-OERInventory -Include AccessPackages).AccessPackages[0].assignmentPolicies[0].approvalStages[0]
            $stage.durationDays | Should -Be 7
            $stage.manager | Should -BeTrue
            $stage.PSObject.Properties.Name | Should -Not -Contain 'managerLevel'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'users'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'groups'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'internalSponsor'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'externalSponsor'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'alternateUsers'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'alternateGroups'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'fallbackUsers'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'fallbackGroups'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'escalationDays'
            $stage.PSObject.Properties.Name | Should -Not -Contain 'requireApproverJustification'
            # approverInfoVisibility Default -- still omit per schema (only Visible/NotVisible meaningful)
            $stage.PSObject.Properties.Name | Should -Not -Contain 'approverInfoVisibility'
        }

        It 'projects the hidden flag' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap'; Description = 'd'; CatalogId = 'c-1'; IsHidden = $true }
            }
            (Get-OERInventory -Include AccessPackages).AccessPackages[0].hidden | Should -BeTrue
        }
    }

    Context 'AccessReviews and RoleManagementPolicies sections' {
        BeforeEach {
            # A review's access package and assignment policy names are read through the transport,
            # by the same by-id URIs Get-OERAccessPackage -Id and Get-OERAccessPackageAssignmentPolicy
            # -Id send. Every fixture below points at ap-1 / pol-1, so one pair of answers serves them
            # all; an It that needs another answer mocks it itself. The catch-all FIRST makes any other
            # request a loud failure instead of letting the real wrapper run.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage'
            }
            # BL-142: a name read is written only when the apply engine's own lookup of it finds this
            # object and no other, so the two lookups are answered too: one access package in the
            # tenant carries 'AP-Sales', and one policy of ap-1 carries 'Default'.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-1'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'ap-1'"
            }
        }

        It 'projects a round-trippable access review (names, reviewers, recurrence)' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    DescriptionForAdmins = 'admins'; DescriptionForReviewers = 'reviewers'
                    DurationInDays = 14
                    Reviewers = @([PSCustomObject]@{ query = './manager' })
                    FallbackReviewers = @([PSCustomObject]@{ query = '/users/fb-9' })
                    Recurrence = [PSCustomObject]@{ pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }; range = [PSCustomObject]@{ startDate = '2026-07-01' } }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter "startswith(displayName,'Q')").AccessReviews[0]
            $ar.displayName | Should -Be 'Quarterly'
            $ar.accessPackage | Should -Be 'AP-Sales'
            $ar.assignmentPolicy | Should -Be 'Default'
            $ar.reviewers | Should -Contain 'manager'
            # The manager review's required fallback round-trips (id falls back when unresolved).
            $ar.fallbackReviewers | Should -Contain 'fb-9'
            $ar.recurrence | Should -Be 'Quarterly'
            $ar.durationInDays | Should -Be 14
            $ar.startDate | Should -Be '2026-07-01'
        }

        It 'maps a user reviewer to a resolved name and an empty reviewers list to self' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-2'; DisplayName = 'Self'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter "x").AccessReviews[0]
            $ar.reviewers | Should -Contain 'self'
            $ar.recurrence | Should -Be 'OneTime'
        }

        It 'skips a multi-stage access review instead of exporting it as a self review' {
            # A multi-stage review's top-level reviewers is empty by construction (Learn: ignored when
            # stageSettings is present), so without the StageCount guard this would export as a
            # fabricated ['self'] review -- one that was never configured that way.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-multi'; DisplayName = 'Multi-Stage Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; StageCount = 2
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable Warned -WarningAction SilentlyContinue
            @($Inv.AccessReviews).Count | Should -Be 0
            @($Warned) | Where-Object { $_ -match 'multi-stage' } | Should -HaveCount 1
        }

        It 'still exports a genuine single-stage self review' {
            # Regression guard: StageCount 0 (a real single-stage review) must still export reviewers
            # ['self'] as it always has -- only a positive StageCount is a reason to skip.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-single'; DisplayName = 'Single-Stage Self Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; StageCount = 0
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x'
            @($Inv.AccessReviews).Count | Should -Be 1
            $Inv.AccessReviews[0].reviewers | Should -Contain 'self'
        }

        It 'warns rather than silently collapsing an unrepresentable recurrence interval' {
            # Live absoluteMonthly interval 2 (every other month) is a review whose cadence
            # New-OERAccessReviewRecurrence cannot emit (it emits 1, 3, 6 and 12), so it is exported as
            # Monthly, a cadence the module can name -- but the warning must name the true interval so
            # the loss is visible, not silent.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-bimonthly'; DisplayName = 'Bi-Monthly Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); StageCount = 0
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 2 }
                        range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable Warned -WarningAction SilentlyContinue
            $Inv.AccessReviews[0].recurrence | Should -Be 'Monthly'
            ($Warned -join ' ') | Should -Match 'interval 2'
        }

        It 'exports a live absoluteMonthly interval 6 as SemiAnnually and does not warn about the cadence' {
            # Interval 6 is the SemiAnnually cadence, which the module can now emit, so it is a
            # representable pattern: no collapse onto Monthly and no warning that one happened.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-semi'; DisplayName = 'Semi-Annual Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); StageCount = 0
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 6 }
                        range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable Warned -WarningAction SilentlyContinue
            # The export reached the review, so an empty warning list below is not vacuous.
            @($Inv.AccessReviews).Count | Should -Be 1
            $Inv.AccessReviews[0].displayName | Should -Be 'Semi-Annual Review'
            $Inv.AccessReviews[0].recurrence | Should -BeExactly 'SemiAnnually'
            @($Warned).Count | Should -Be 0
        }

        It 'uses -All (list-all) when no AccessReviewFilter is given' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'All'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $inv = Get-OERInventory -Include AccessReviews
            @($inv.AccessReviews).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -ParameterFilter { $All }
        }

        It 'skips an access review that is not access-package-scoped (does not round-trip)' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-ap'; DisplayName = 'AP Review'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'; Reviewers = @(); Recurrence = $null }
                [PSCustomObject]@{ Id = 'ar-role'; DisplayName = 'Directory Role Review'; AccessPackageId = $null; AssignmentPolicyId = $null; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $inv = Get-OERInventory -Include AccessReviews
            @($inv.AccessReviews).Count | Should -Be 1
            $inv.AccessReviews[0].displayName | Should -Be 'AP Review'
        }

        It 'uses client-side -DisplayName (not -All, not -Filter) when an AccessReviewFilter is given' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-2'; DisplayName = 'Filtered'; AccessPackageId = $null; AssignmentPolicyId = $null; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            Get-OERInventory -Include AccessReviews -AccessReviewFilter 'AR*' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -ParameterFilter { $DisplayName -eq 'AR*' -and -not $All }
        }

        It 'warns but does not crash when access reviews cannot be read (e.g. 429)' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition { throw [System.Exception]::new('throttled') }
            # -ErrorAction is pinned: the failed list now also ends the run in InventoryPartial, which
            # is non-terminating but would stop the statement under a global $ErrorActionPreference of Stop.
            $inv = Get-OERInventory -Include AccessReviews -WarningVariable warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $inv | Should -Not -BeNullOrEmpty
            $warned | Should -Not -BeNullOrEmpty
            @($inv.AccessReviews).Count | Should -Be 0
        }

        # -- The access review read must not leak the not-found record it depends on --------------
        # Same defect, same mechanism, as the existence probe in Sync-OERStructureAccessReview: an
        # -AccessReviewFilter matching nothing made Get-OERAccessReviewDefinition publish a
        # non-terminating AccessReviewDefinitionNotFound record, and the catch that swallowed the
        # resulting exception could not retract the deposit it had already made in the caller's
        # error stream. All three tests drive the REAL read cmdlet with only Invoke-OERGraphRequest
        # mocked -- a mock of the cmdlet itself raises no record and would prove nothing.
        It 'leaves the caller error stream empty when the AccessReviewFilter matches nothing' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            $ArLeak = $null
            $inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'NoSuchReview*' `
                -ErrorVariable ArLeak -WarningAction SilentlyContinue
            $inv | Should -Not -BeNullOrEmpty
            @($inv.AccessReviews).Count | Should -Be 0
            $Leaked = @($ArLeak | Where-Object { $null -ne $_ })
            $Leaked.Count | Should -Be 0 -Because ('an inventory read that succeeded must deposit nothing in the ' +
                'operator error stream; leaked: ' +
                (@($Leaked | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }

        It 'still warns with the published cause when the access review read genuinely fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('429 Too Many Requests'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null)
            }
            # -ErrorAction is pinned: the failed list now also ends the run in InventoryPartial, which
            # is non-terminating but would stop the statement under a global $ErrorActionPreference of Stop.
            $inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'AR*' `
                -WarningVariable ArWarned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            @($inv.AccessReviews).Count | Should -Be 0
            # The warning must name the cause the read cmdlet published, not one of the
            # message-less strays the engine collects from the nested transport call beside it.
            @($ArWarned | Where-Object { [string]$_ -like '*Could not read access reviews*429 Too Many Requests*' }).Count |
                Should -BeGreaterThan 0 -Because 'a read that never answered must still be reported, and named by its real cause'
        }

        It 'still projects definitions the real read cmdlet returns' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{
                    value = @(
                        @{
                            id                = 'ar-real'
                            displayName       = 'Real Review'
                            scope             = @{ query = "accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1'" }
                            reviewers         = @()
                            fallbackReviewers = @()
                            settings          = @{ instanceDurationInDays = 14 }
                        }
                    )
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'Real*' -WarningAction SilentlyContinue
            @($inv.AccessReviews).Count | Should -Be 1
            $inv.AccessReviews[0].displayName | Should -Be 'Real Review'
        }

        It 'projects role management policies for each role given' {
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy {
                [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; RoleName = 'Contributor'; AllowPermanentEligibility = $false; ActivationMaxHours = 8 }
            }
            $Result = Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -Role 'Contributor' -IncludeARM
            @($Result.RoleManagementPolicies).Count | Should -Be 1
            $Result.RoleManagementPolicies[0].role | Should -Be 'Contributor'
            $Result.RoleManagementPolicies[0].allowPermanentEligibility | Should -Be $false
        }

        It 'warns and skips RoleManagementPolicies when no role is given' {
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy {}
            Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -IncludeARM -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
            $warned | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 0
        }

        It 'adds an id to access reviews only with -IncludeId' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Filter = "startswith(displayName,'Q')"
            (Get-OERInventory -Include AccessReviews -AccessReviewFilter $Filter).AccessReviews[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            (Get-OERInventory -Include AccessReviews -AccessReviewFilter $Filter -IncludeId).AccessReviews[0].id | Should -Be 'ar-1'
        }

        It 'adds an id to role management policies only with -IncludeId' {
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = 'Contributor'
                    AllowPermanentEligibility = $false; ActivationMaxHours = 8
                    PolicyId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleManagementPolicies/pol-1'
                }
            }
            (Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -Role 'Contributor' -IncludeARM).RoleManagementPolicies[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            (Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -Role 'Contributor' -IncludeARM -IncludeId).RoleManagementPolicies[0].id | Should -Be '/subscriptions/sub-1/providers/Microsoft.Authorization/roleManagementPolicies/pol-1'
        }

        It 'projects every settings field the apply schema declares' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null
                    MailNotificationsEnabled     = $true
                    ReminderNotificationsEnabled = $false
                    JustificationRequired        = $true
                    RecommendationsEnabled       = $true
                    AutoApplyDecisionsEnabled    = $false
                    DefaultDecision               = 'Approve'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.mailNotification       | Should -Be $true
            $ar.reminderNotification   | Should -Be $false
            $ar.requireJustification   | Should -Be $true
            $ar.recommendationsEnabled | Should -Be $true
            $ar.autoApplyDecisions     | Should -Be $false
            $ar.defaultDecision        | Should -BeExactly 'Approve'
        }

        It 'projects an endDate range' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @()
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                        range   = [PSCustomObject]@{ type = 'endDate'; startDate = '2026-01-01'; endDate = '2026-12-31' }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.endDate | Should -Be '2026-12-31'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'occurrences'
        }

        It 'projects a numbered range' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @()
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                        range   = [PSCustomObject]@{ type = 'numbered'; startDate = '2026-01-01'; numberOfOccurrences = 4 }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.occurrences | Should -Be 4
            $ar.PSObject.Properties.Name | Should -Not -Contain 'endDate'
        }

        It 'emits neither range key for a noEnd series' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @()
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                        range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-01-01' }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.PSObject.Properties.Name | Should -Not -Contain 'endDate'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'occurrences'
        }

        It 'emits neither range key for a OneTime review even if the range carries one' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @()
                    Recurrence = [PSCustomObject]@{
                        pattern = $null
                        range   = [PSCustomObject]@{ type = 'endDate'; startDate = '2026-01-01'; endDate = '2026-12-31' }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.recurrence | Should -Be 'OneTime'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'endDate'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'occurrences'
        }

        It 'emits no occurrences for a numbered range reporting zero occurrences' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @()
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                        range   = [PSCustomObject]@{ type = 'numbered'; startDate = '2026-01-01'; endDate = '2026-06-01'; numberOfOccurrences = 0 }
                    }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            $ar.PSObject.Properties.Name | Should -Not -Contain 'occurrences'
        }

        It 'emits no durationInDays when Graph reports a zero instance duration' {
            # Live regression. Graph returns "instanceDurationInDays": 0 for a review whose duration is
            # not driven by that field -- Microsoft's own list-definitions example response carries
            # exactly that value -- and the apply schema requires an integer 1-365. A bare '$null -ne'
            # guard cannot catch it, because the value is a real 0 rather than a missing key, so every
            # exported bundle holding such a review failed the schema.json written beside it with
            # "'durationInDays' at accessReviews[0] must be an integer between 1 and 365".
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-zero'; DisplayName = 'Zero Duration Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 0
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x').AccessReviews[0]
            # Prove the projection produced the review BEFORE measuring what it omitted: a $null $ar
            # makes the Should -Not -Contain below pass vacuously.
            $ar.displayName | Should -Be 'Zero Duration Review'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'durationInDays'
        }

        It 'warns and emits no durationInDays for a live duration above the schema maximum' {
            # Unlike the 0 sentinel above, a positive out-of-band duration is real configuration being
            # dropped, so it has to be visible rather than silently absent from the bundle.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-long'; DisplayName = 'Long Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 400
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable ArDurationWarning -WarningAction SilentlyContinue).AccessReviews[0]
            $ar.displayName | Should -Be 'Long Review'
            $ar.PSObject.Properties.Name | Should -Not -Contain 'durationInDays'
            @($ArDurationWarning) | Should -Not -BeNullOrEmpty
            (@($ArDurationWarning) -join ' ') | Should -Match 'Long Review'
            (@($ArDurationWarning) -join ' ') | Should -Match '400'
        }

        It 'warns when live reviewer scopes project to nothing instead of exporting a silent self review' {
            # './owners' is a documented reviewer scope (Learn: "Configure access reviewers using access
            # reviews APIs", example 4) that none of the three query forms this module emits matches.
            # The raw collection is non-empty, so the 'self' default does not fire and the projection
            # emits reviewers: [] -- which Learn defines as a self review. Same fabrication class as the
            # multi-stage skip above, so it must not be silent.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-owners'; DisplayName = 'Owner Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @([PSCustomObject]@{ query = './owners' })
                    Recurrence = $null; DurationInDays = 14
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $ar = (Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable ArReviewerWarning -WarningAction SilentlyContinue).AccessReviews[0]
            $ar.displayName | Should -Be 'Owner Review'
            $ar.PSObject.Properties.Name | Should -Contain 'reviewers'
            # @($null).Count is 1, so this only passes on a genuinely empty array, never on a missing one.
            @($ar.reviewers).Count | Should -Be 0
            @($ArReviewerWarning) | Should -Not -BeNullOrEmpty
            (@($ArReviewerWarning) -join ' ') | Should -Match 'self review'
            (@($ArReviewerWarning) -join ' ') | Should -Match '\./owners'
        }

        It 'warns once with a count when access reviews were skipped as not access-package-scoped' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-ap'; DisplayName = 'AP Review'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'; Reviewers = @(); Recurrence = $null }
                [PSCustomObject]@{ Id = 'ar-role'; DisplayName = 'Directory Role Review'; AccessPackageId = $null; AssignmentPolicyId = $null; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $inv = Get-OERInventory -Include AccessReviews -WarningVariable warned -WarningAction SilentlyContinue
            @($inv.AccessReviews).Count | Should -Be 1
            @($warned).Count | Should -Be 1
            $warned | Should -Match '1 access review'
        }

        It 'writes no skip warning when every review is access-package-scoped' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = 'ar-ap'; DisplayName = 'AP Review'; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'; Reviewers = @(); Recurrence = $null }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $inv = Get-OERInventory -Include AccessReviews -WarningVariable warned -WarningAction SilentlyContinue
            @($inv.AccessReviews).Count | Should -Be 1
            @($warned).Count | Should -Be 0
        }
    }

    Context 'access review list read through the real transport' {
        # Moved out of 'AccessReviews and RoleManagementPolicies sections', unchanged. That Context now
        # mocks Invoke-OERGraphRequest for every review's by-id name read, and this test needs the
        # REAL wrapper (it mocks only the SDK cmdlet underneath), which a mocked wrapper hides.
        It 'does not warn when the access review read was throttled, retried and then answered' {
            # THE MUTATION TARGET for the publisher-membership clause in the section loop above.
            # -ErrorVariable is filled by the ENGINE, and it also collects records raised inside
            # NESTED calls even when an inner catch swallowed them -- and Invoke-OERGraphRequest
            # swallows and retries a 429. So a read that was throttled, retried and then answered
            # PERFECTLY still leaves a pile of TooManyRequests records (and message-less blanks) in
            # the local collection beside the one AccessReviewDefinitionNotFound the read cmdlet
            # published. Without the publisher clause every one of those strays becomes a section
            # warning telling the operator a read failed that in fact succeeded.
            #
            # Invoke-MgGraphRequest is mocked, not Invoke-OERGraphRequest, so the REAL wrapper, its
            # REAL throttle backoff and the REAL Get-OERAccessReviewDefinition all run. Mocking the
            # wrapper would skip the swallow-and-retry that deposits the strays this test is about.
            InModuleScope $script:moduleName {
                $script:_OERAuthState = @{ TenantId = 't'; Environment = 'Global'; GraphConnected = $true }
            }
            # The counter lives in the TEST file's script scope, not the module's: a Mock body runs
            # in the scope the Mock was DEFINED in, even when -ModuleName routes the interception
            # into the module. Reading it back through InModuleScope returns 0 and the control is
            # then vacuous in the safe direction -- measured once, on this very test.
            $script:ArThrottleCall = 0
            Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
                $script:ArThrottleCall++
                if ($script:ArThrottleCall -le 3) {
                    $Resp = [PSCustomObject]@{ StatusCode = 429; Headers = @{ 'Retry-After' = '0' }; Content = $null }
                    $Ex = [System.Exception]::new('Too many requests')
                    $Ex | Add-Member -NotePropertyName Response -NotePropertyValue $Resp -Force
                    throw [System.Management.Automation.ErrorRecord]::new($Ex, 'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
                }
                return @{ value = @() }
            }
            $ArWarned = $null
            $inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'NoSuchReview*' `
                -WarningVariable ArWarned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            # Non-vacuity control FIRST: a fixture whose transport was never retried renders exactly
            # like a passing section loop in the assertion below.
            $script:ArThrottleCall | Should -BeGreaterThan 3 -Because 'the throttled attempts must actually have been swallowed and retried, or no stray record exists to be misread'
            $inv | Should -Not -BeNullOrEmpty
            @($inv.AccessReviews).Count | Should -Be 0
            $ArNoise = @($ArWarned | Where-Object { [string]$_ -like '*Could not read access reviews*' })
            $ArNoise.Count | Should -Be 0 -Because ('the read answered; the throttle records collected beside it were swallowed ' +
                'and retried, and none of them was published by the read cmdlet. Warned: ' +
                (@($ArNoise | ForEach-Object { [string]$_ }) -join ' | '))
        }
    }

    Context 'reviewer scope queries carrying the API version prefix Graph adds on read' {
        # Microsoft Graph NORMALIZES a reviewer scope query. This module writes '/users/{id}' with no
        # prefix (Resolve-OERReviewerScope), but a GET reads it back as '/v1.0/users/{id}'. The
        # anchored '^/users/' parse this section used to carry matched none of those, so every live
        # review with a named user reviewer exported an EMPTY reviewers list -- which the apply schema
        # reads as a self review. The ids below are the live strings from the tenant export that
        # exposed the defect, deliberately not sanitized.
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage'
            }
            # BL-142: the apply engine's own lookups of the two names, each finding this object alone.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-1'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'ap-1'"
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                @{
                    '00000000-0000-0000-0000-000000000049' = 'anna@contoso.com'
                    'grp-1'                                = 'GRP-Reviewers'
                    'fb-9'                                 = 'fallback@contoso.com'
                }
            }
        }

        It 'projects a /v1.0/users/{id} reviewer as the resolved principal and warns about nothing' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-v1'; DisplayName = 'OER-DIAG-A-v1scope-userReviewer'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @([PSCustomObject]@{ query = '/v1.0/users/00000000-0000-0000-0000-000000000049' })
                    Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable PrefixWarning -WarningAction SilentlyContinue
            $Ar = $Inv.AccessReviews[0]
            @($Ar.reviewers).Count | Should -Be 1
            $Ar.reviewers | Should -Contain 'anna@contoso.com'
            $Ar.reviewers | Should -Not -Contain 'self'
            @($PrefixWarning).Count | Should -Be 0
        }

        It 'projects a /beta/users/{id} reviewer identically' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-beta'; DisplayName = 'OER-DIAG-B-betascope-userReviewer'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @([PSCustomObject]@{ query = '/beta/users/00000000-0000-0000-0000-000000000049' })
                    Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable PrefixWarning -WarningAction SilentlyContinue
            $Inv.AccessReviews[0].reviewers | Should -Contain 'anna@contoso.com'
            @($PrefixWarning).Count | Should -Be 0
        }

        It 'projects a prefixed group reviewer and a prefixed fallback reviewer' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-grp'; DisplayName = 'Group Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @([PSCustomObject]@{ query = '/v1.0/groups/grp-1/transitiveMembers' })
                    FallbackReviewers = @([PSCustomObject]@{ query = '/v1.0/users/fb-9' })
                    Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable PrefixWarning -WarningAction SilentlyContinue
            $Ar = $Inv.AccessReviews[0]
            $Ar.reviewers | Should -Contain 'GRP-Reviewers'
            $Ar.fallbackReviewers | Should -Contain 'fallback@contoso.com'
            @($PrefixWarning).Count | Should -Be 0
        }

        It 'still warns, naming only the offending query, when one scope of several does not parse' {
            # An unparsed scope is data loss even when the OTHER scopes projected fine. Before this
            # fix the warning only fired when the whole list projected to nothing, so a partial drop
            # was silent.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-mixed'; DisplayName = 'Mixed Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(
                        [PSCustomObject]@{ query = '/v1.0/users/00000000-0000-0000-0000-000000000049' }
                        [PSCustomObject]@{ query = './owners' }
                    )
                    Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable MixedWarning -WarningAction SilentlyContinue
            $Ar = $Inv.AccessReviews[0]
            $Ar.reviewers | Should -Contain 'anna@contoso.com'
            @($MixedWarning) | Should -Not -BeNullOrEmpty
            $Joined = @($MixedWarning) -join ' '
            $Joined | Should -Match '\./owners'
            $Joined | Should -Match 'has 1 live reviewer scope'
            # The prefixed user scope parsed, so it is not one of the offending queries.
            $Joined | Should -Not -Match '00000000-0000-0000-0000-000000000049'
            # A partial drop is not a self review, so that clause must not appear.
            $Joined | Should -Not -Match 'reads as a self review'
        }

        It 'warns when a fallback reviewer scope does not parse' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-fb'; DisplayName = 'Fallback Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @([PSCustomObject]@{ query = './manager' })
                    FallbackReviewers = @([PSCustomObject]@{ query = './owners' })
                    Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable FbWarning -WarningAction SilentlyContinue
            $Ar = $Inv.AccessReviews[0]
            $Ar.reviewers | Should -Contain 'manager'
            $Ar.PSObject.Properties.Name | Should -Not -Contain 'fallbackReviewers'
            @($FbWarning) | Should -Not -BeNullOrEmpty
            $Joined = @($FbWarning) -join ' '
            $Joined | Should -Match 'fallback reviewer scope'
            $Joined | Should -Match '\./owners'
        }

        It 'keeps a genuinely empty reviewer collection as the self-review shape' {
            # The counterpart guard: fixing the unparsed case must not make an ACTUALLY empty
            # reviewers collection stop projecting 'self'.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-self'; DisplayName = 'Self Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'x' -WarningVariable SelfWarning -WarningAction SilentlyContinue
            $Inv.AccessReviews[0].reviewers | Should -Contain 'self'
            @($SelfWarning).Count | Should -Be 0
        }
    }

    Context 'access review name lookups: a failed read is reported, a deleted target is written by id' {
        # A review points at its access package and assignment policy by id. The inventory writes the
        # NAMES (the form that round-trips) and falls back to the id. Each name is read through the
        # transport with the not-found codes declared, so a deleted package or policy is an ANSWER --
        # the id is written and nothing is reported -- while any other failure (403, an exhausted
        # 429, a 5xx, a not-found code that was not declared) is counted as an unread collection and
        # the run ends in InventoryPartial. The id is written either way: it is a safe reference.
        BeforeAll {
            $script:ArApId = '11111111-1111-1111-1111-111111111111'
            $script:ArPolId = '22222222-2222-2222-2222-222222222222'
            # The by-id URIs Get-OERAccessPackage -Id and Get-OERAccessPackageAssignmentPolicy -Id
            # send, so the inventory introduces no request shape that was not already proven live.
            $script:ArApUri = 'v1.0/identityGovernance/entitlementManagement/accessPackages/11111111-1111-1111-1111-111111111111?$expand=catalog'
            $script:ArPolUri = 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/22222222-2222-2222-2222-222222222222?$expand=accessPackage'
            # What Invoke-OERGraphRequest returns INSTEAD of raising when the caller declared the
            # answering code (Get-ExpectedGraphErrorResult builds the same shape).
            $script:NewArMarker = {
                param([string]$Code)
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = $Code; StatusCode = 404; Message = "${Code}: not found"; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $script:NewArFailure = {
                param([string]$Message, [string]$Id)
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($Message), $Id,
                    [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            }
        }

        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Q3 AP review'
                    AccessPackageId = '11111111-1111-1111-1111-111111111111'
                    AssignmentPolicyId = '22222222-2222-2222-2222-222222222222'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            # The two readers this section used to call. Mocked only to prove they are not consulted.
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            # BL-142: a name read is written only when the apply engine's own lookup of it finds this
            # object and no other. Answered here as that: one access package carries 'AP-Sales', and one
            # policy of the package carries 'Default'. The Context below tests the lookups themselves.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '11111111-1111-1111-1111-111111111111'"
            }
        }

        It 'writes the names the by-id reads return, each read declaring its own not-found codes' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AP-Sales' } } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Default' } } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -Be 'AP-Sales'
            $Ar.assignmentPolicy | Should -Be 'Default'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq $script:ArApUri -and (@($ExpectedErrorCode) -join ',') -eq 'AccessPackageNotFound,NotFound'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq $script:ArPolUri -and (@($ExpectedErrorCode) -join ',') -eq 'PolicyNotFound,NotFound'
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 0
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'writes both ids and reports nothing when the package and the policy no longer exist' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { & $script:NewArMarker 'AccessPackageNotFound' } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { & $script:NewArMarker 'PolicyNotFound' } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.displayName | Should -Be 'Q3 AP review'
            $Ar.accessPackage | Should -Be $script:ArApId
            $Ar.assignmentPolicy | Should -Be $script:ArPolId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:ArApUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:ArPolUri }
            @($InvErr).Count | Should -Be 0 -Because 'a deleted package or policy is a fact about the review, not a failed read'
        }

        It 'writes the id for a deleted policy and the name for a package that still exists, reporting nothing' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AP-Sales' } } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { & $script:NewArMarker 'PolicyNotFound' } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -Be 'AP-Sales'
            $Ar.assignmentPolicy | Should -Be $script:ArPolId
            @($InvErr).Count | Should -Be 0
        }

        It 'writes the id and reports nothing when an answer carries no name' {
            # A 200 without a displayName is neither a deleted target nor a failed read -- but it is no
            # name either, and '' would count as a declared value: it would pass the schema and fail
            # only at apply. The id is the safe reference. Null (package) and whitespace (policy) are
            # both "no name"; the whitespace half is what separates IsNullOrWhiteSpace from IsNullOrEmpty.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '11111111-1111-1111-1111-111111111111' } } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '22222222-2222-2222-2222-222222222222'; displayName = '   ' } } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.displayName | Should -Be 'Q3 AP review'
            $Ar.accessPackage | Should -Be $script:ArApId
            $Ar.assignmentPolicy | Should -Be $script:ArPolId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:ArApUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:ArPolUri }
            @($InvErr).Count | Should -Be 0 -Because 'an answer without a name is not a failed read, so nothing is reported'
        }

        It 'writes the id and reports the access package name as unread when its read fails' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw (& $script:NewArFailure 'Insufficient privileges to complete the operation (access package).' 'Authorization_RequestDenied')
            } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Default' } } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -Be $script:ArApId
            $Ar.assignmentPolicy | Should -Be 'Default'
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'accessReviews/Q3 AP review/accessPackage'
            $Partial[0].Exception.Message | Should -Match "Could not read an access review's access package name"
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges to complete the operation \(access package\)'
            # The catch was reached (the partial above) and the record it caught was scrubbed. An
            # $Error count cannot prove the scrub for a catch that does not re-throw.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Insufficient privileges to complete the operation (access package).'
            }
        }

        It 'writes the id and reports the assignment policy name as unread when its read fails' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AP-Sales' } } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw (& $script:NewArFailure 'Too many requests (assignment policy).' 'TooManyRequests')
            } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -Be 'AP-Sales'
            $Ar.assignmentPolicy | Should -Be $script:ArPolId
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'accessReviews/Q3 AP review/assignmentPolicy'
            $Partial[0].Exception.Message | Should -Match "Could not read an access review's assignment policy name"
            $Partial[0].Exception.Message | Should -Match 'Too many requests \(assignment policy\)'
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Too many requests (assignment policy).'
            }
        }

        It 'counts any throw as a failed read, even one whose id reads like a not-found' {
            # The catch must not classify by id: only the marker, which the wrapper returns for the
            # codes the caller DECLARED, means "deleted". That an undeclared code really is raised by
            # the wrapper is proved through the real transport below; this pins the catch's side.
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw (& $script:NewArFailure 'Resource not found (undeclared spelling).' 'Request_ResourceNotFound')
            } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Default' } } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews)[0].accessPackage | Should -Be $script:ArApId
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'accessReviews/Q3 AP review/accessPackage'
        }

        It 'names every failed collection of every review once, and states a repeated cause once' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                foreach ($Name in 'Q3 AP review', 'Q4 AP review') {
                    [PSCustomObject]@{
                        Id = "ar-$Name"; DisplayName = $Name
                        AccessPackageId = '11111111-1111-1111-1111-111111111111'
                        AssignmentPolicyId = '22222222-2222-2222-2222-222222222222'
                        Reviewers = @(); Recurrence = $null; DurationInDays = 14
                    }
                }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw (& $script:NewArFailure 'Insufficient privileges to complete the operation.' 'Authorization_RequestDenied')
            } -ParameterFilter { $Uri -eq $script:ArApUri -or $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews).Count | Should -Be 2
            @(@($Inv.AccessReviews).accessPackage | Where-Object { $_ -eq $script:ArApId }).Count | Should -Be 2 -Because 'a failed name read still writes the id'
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be ('accessReviews/Q3 AP review/accessPackage, accessReviews/Q3 AP review/assignmentPolicy, ' +
                'accessReviews/Q4 AP review/accessPackage, accessReviews/Q4 AP review/assignmentPolicy')
            $Causes = ($Partial[0].Exception.Message -split 'Causes: ')[1]
            @([regex]::Matches($Causes, "Could not read an access review's access package name")).Count | Should -Be 1
            @([regex]::Matches($Causes, "Could not read an access review's assignment policy name")).Count | Should -Be 1
        }

        It 'sends no uniqueness lookup for a reference already written by id' {
            # Only a NAME is checked: the id of a deleted package or policy is written as it is.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { & $script:NewArMarker 'AccessPackageNotFound' } -ParameterFilter { $Uri -eq $script:ArApUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { & $script:NewArMarker 'PolicyNotFound' } -ParameterFilter { $Uri -eq $script:ArPolUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews)[0].accessPackage | Should -Be $script:ArApId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*$filter=*' }
            @($InvErr).Count | Should -Be 0
        }
    }

    Context 'access review references are written by id when the apply engine could not resolve the name (BL-142)' {
        # The apply engine resolves a review's accessPackage name in the whole tenant
        # (Resolve-OERAccessPackageId) and its assignmentPolicy name among the policies of the package
        # (Resolve-OERAssignmentPolicyId), and refuses a name either finds more than once. The export
        # repeats those two lookups, with the same URIs, and keeps a name only when the lookup finds this
        # object and no other; otherwise it writes the id, which the engine takes as the object itself.
        # No id below is version-4 shaped.
        BeforeAll {
            $script:UqApId = 'aaaa1111-0000-0000-0000-000000000041'
            $script:UqPolId = 'bbbb2222-0000-0000-0000-000000000041'
            $script:UqOtherApId = 'aaaa1111-0000-0000-0000-000000000042'
            $script:UqOtherPolId = 'bbbb2222-0000-0000-0000-000000000042'
            # The engine's lookups: the access package name tenant-wide, the policies of the package.
            $script:UqApLookupUri = "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            $script:UqPolLookupUri = "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'aaaa1111-0000-0000-0000-000000000041'"
            function script:New-UqReview {
                param([string]$Name, [string]$AccessPackageId = $script:UqApId, [string]$AssignmentPolicyId = $script:UqPolId)
                [PSCustomObject]@{
                    Id = "ar-$Name"; DisplayName = $Name; AccessPackageId = $AccessPackageId; AssignmentPolicyId = $AssignmentPolicyId
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            function script:Get-UqPartial {
                param([object[]]$Record)
                @($Record | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            }
        }

        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition { New-UqReview -Name 'Q3 AP review' }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            # The by-id name reads: the review's package is AP-Sales and its policy Default.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000041?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'bbbb2222-0000-0000-0000-000000000041'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/bbbb2222-0000-0000-0000-000000000041?$expand=accessPackage'
            }
            # The lookups as a tenant where each name is unique answers them.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq $script:UqApLookupUri
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'bbbb2222-0000-0000-0000-000000000041'; displayName = 'Default' }, @{ id = 'bbbb2222-0000-0000-0000-000000000043'; displayName = 'Premium' }) }
            } -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
        }

        It 'writes the access package by id when another access package in the tenant carries its name, and keeps the policy name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' }, @{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'ap-sales' }) }
            } -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -BeExactly $script:UqApId
            $Ar.assignmentPolicy | Should -BeExactly 'Default'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0 -Because 'a shared name written by id is applicable, so nothing is reported for it'
        }

        It 'writes the assignment policy by id when another policy of the package carries its name in another letter case, and keeps the package name' {
            # The resolver compares with -eq, which ignores letter case, so 'DEFAULT' is the same name.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'bbbb2222-0000-0000-0000-000000000041'; displayName = 'Default' }, @{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'DEFAULT' }) }
            } -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -BeExactly 'AP-Sales'
            $Ar.assignmentPolicy | Should -BeExactly $script:UqPolId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'writes the id when the lookup finds one object of the name and it is another one' {
            # The lookup is what the engine would resolve the name to: here another package and another
            # policy, so the name would not reach the review's own target.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq $script:UqApLookupUri
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq $script:UqPolLookupUri
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -BeExactly $script:UqApId
            $Ar.assignmentPolicy | Should -BeExactly $script:UqPolId
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'keeps both names when each lookup finds this object alone, comparing the id without regard to letter case' {
            # The policy listing also holds a policy of another name, which the name filter leaves out.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'AAAA1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq $script:UqApLookupUri
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -BeExactly 'AP-Sales'
            $Ar.assignmentPolicy | Should -BeExactly 'Default'
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'looks each name up once per invocation: one package lookup per name and one policy listing per package' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                New-UqReview -Name 'Q3 AP review'
                New-UqReview -Name 'Q4 AP review'
                New-UqReview -Name 'Other review' -AccessPackageId 'aaaa1111-0000-0000-0000-000000000042' -AssignmentPolicyId 'bbbb2222-0000-0000-0000-000000000042'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'AP-Other' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000042?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/bbbb2222-0000-0000-0000-000000000042?$expand=accessPackage'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'AP-Other' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Other'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'aaaa1111-0000-0000-0000-000000000042'"
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews | ForEach-Object { "$($_.displayName)|$($_.accessPackage)|$($_.assignmentPolicy)" }) | Should -Be @(
                'Q3 AP review|AP-Sales|Default'
                'Q4 AP review|AP-Sales|Default'
                'Other review|AP-Other|Default'
            )
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Other'&`$select=id,displayName"
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'aaaa1111-0000-0000-0000-000000000042'"
            }
            # The positive control: each review's names were read by id, once per review.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000041?$expand=catalog'
            }
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'looks an access package name up once for two reviews whose package names differ only in letter case, and writes both by id' {
            # Two packages, 'AP-Sales' and 'ap-sales': the tenant-wide lookup finds both, whichever spelling
            # asks, so the answer to the first serves the second and both are written by id.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                New-UqReview -Name 'Q3 AP review'
                New-UqReview -Name 'Other review' -AccessPackageId 'aaaa1111-0000-0000-0000-000000000042' -AssignmentPolicyId 'bbbb2222-0000-0000-0000-000000000042'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'ap-sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000042?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/bbbb2222-0000-0000-0000-000000000042?$expand=accessPackage'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' }, @{ id = 'aaaa1111-0000-0000-0000-000000000042'; displayName = 'ap-sales' }) }
            } -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'bbbb2222-0000-0000-0000-000000000042'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'aaaa1111-0000-0000-0000-000000000042'"
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews | ForEach-Object { "$($_.displayName)|$($_.accessPackage)" }) | Should -Be @(
                "Q3 AP review|$($script:UqApId)"
                "Other review|$($script:UqOtherApId)"
            )
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:UqApLookupUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'ap-sales'&`$select=id,displayName"
            }
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'lists the policies of an access package once for two reviews whose package id differs only in letter case' {
            # The second review's scope spells the same package id in upper case.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                New-UqReview -Name 'Q3 AP review'
                New-UqReview -Name 'Q4 AP review' -AccessPackageId 'AAAA1111-0000-0000-0000-000000000041' -AssignmentPolicyId 'BBBB2222-0000-0000-0000-000000000041'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/accessPackages/AAAA1111-0000-0000-0000-000000000041?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'bbbb2222-0000-0000-0000-000000000041'; displayName = 'Default' } } -ParameterFilter {
                $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/BBBB2222-0000-0000-0000-000000000041?$expand=accessPackage'
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews | ForEach-Object { "$($_.displayName)|$($_.accessPackage)|$($_.assignmentPolicy)" }) | Should -Be @(
                'Q3 AP review|AP-Sales|Default'
                'Q4 AP review|AP-Sales|Default'
            )
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:UqPolLookupUri }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'AAAA1111-0000-0000-0000-000000000041'"
            }
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'escapes the access package name in the lookup as the resolver does' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = "Lee's AP & Co" } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/aaaa1111-0000-0000-0000-000000000041?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'aaaa1111-0000-0000-0000-000000000041'; displayName = "Lee's AP & Co" }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'Lee%27%27s%20AP%20%26%20Co'&`$select=id,displayName"
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews)[0].accessPackage | Should -BeExactly "Lee's AP & Co"
            @(Get-UqPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'writes the id of every review of the package and reports the check unread once looked up, when the access package lookup fails' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                New-UqReview -Name 'Q3 AP review'
                New-UqReview -Name 'Q4 AP review'
            }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Too many requests (package lookup).'), 'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
            } -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.AccessReviews | ForEach-Object { "$($_.displayName)|$($_.accessPackage)|$($_.assignmentPolicy)" }) | Should -Be @(
                "Q3 AP review|$($script:UqApId)|Default"
                "Q4 AP review|$($script:UqApId)|Default"
            )
            # One failed lookup serves both reviews.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $script:UqApLookupUri }
            $Partial = @(Get-UqPartial -Record @($InvErr))
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessReviews/Q3 AP review/accessPackage, accessReviews/Q4 AP review/accessPackage'
            $Causes = ($Partial[0].Exception.Message -split 'Causes: ')[1]
            @([regex]::Matches($Causes, [regex]::Escape("Could not check whether an access review's access package name is unique: Too many requests (package lookup).")) ).Count |
                Should -Be 1 -Because 'one cause, stated once for the two reviews it left unread'
            # The catch was reached (the partial above) and the record it caught was scrubbed.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Too many requests (package lookup).'
            }
        }

        It 'writes the policy id and reports the check unread when the assignment policy listing fails' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation (policy listing).'), 'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            } -ParameterFilter { $Uri -eq $script:UqPolLookupUri }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $Ar.accessPackage | Should -BeExactly 'AP-Sales'
            $Ar.assignmentPolicy | Should -BeExactly $script:UqPolId
            $Partial = @(Get-UqPartial -Record @($InvErr))
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessReviews/Q3 AP review/assignmentPolicy'
            $Partial[0].Exception.Message | Should -BeLike "*Causes: Could not check whether an access review's assignment policy name is unique: Insufficient privileges to complete the operation (policy listing).*"
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Insufficient privileges to complete the operation (policy listing).'
            }
        }

        It 'states the rule in the help' {
            $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
            $Help | Should -Match ([regex]::Escape('So the projection writes a name only when that same lookup finds this access package or assignment policy and no other'))
            $Help | Should -Match ([regex]::Escape('a name whose uniqueness could not be checked, because the lookup above failed'))
            $Help | Should -Not -Match ([regex]::Escape('until the entry names it by id'))
        }
    }

    Context "the export's review-reference lookups agree with the resolvers (named deviation)" {
        # A NAMED DEVIATION from the single-owner rule (Task 3b ruling): Get-OERInventory repeats the
        # access package lookup of Resolve-OERAccessPackageId and the assignment policy lookup of
        # Resolve-OERAssignmentPolicyId over the transport instead of calling them, since a resolver throws
        # AmbiguousName for a shared name and would leave stray records in a caller's -ErrorVariable. This
        # Context holds the copies in step: under ONE transport mock, the resolvers and the export answer
        # the same four tenants, and (a) send byte-identical URIs and (b) agree -- the export keeps a name
        # exactly when the resolver returns this object's id, and writes the id when the resolver throws
        # AmbiguousName, returns $null or returns another id. The access package name needs escaping, so a
        # change to the escaping shows. No id below is version-4 shaped.
        BeforeAll {
            $script:AgApId = 'aaaa1111-0000-0000-0000-000000000061'
            $script:AgPolId = 'bbbb2222-0000-0000-0000-000000000061'
            $script:AgOtherApId = 'aaaa1111-0000-0000-0000-000000000062'
            $script:AgOtherPolId = 'bbbb2222-0000-0000-0000-000000000062'
            $script:AgApName = "AP Sales & Co's #1"
            $script:AgPolName = 'Default'
            # What the resolver did: 'This' (returned this object's id), 'Other' (another id), 'Null' or
            # 'Ambiguous' (threw AmbiguousName). Any other throw fails the test.
            function script:Get-AgResolverOutcome {
                param([scriptblock]$Resolve, [string]$ThisId)
                try {
                    $Result = & $Resolve
                } catch {
                    if ([string]$PSItem.FullyQualifiedErrorId -like 'AmbiguousName*') { return 'Ambiguous' }
                    throw
                }
                if ($null -eq $Result) { return 'Null' }
                if ([string]$Result -ieq $ThisId) { return 'This' }
                'Other'
            }
        }

        BeforeEach {
            $script:AgCalls = [System.Collections.Generic.List[string]]::new()
            $script:AgPackages = @()
            $script:AgPolicies = @()
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-agree'; DisplayName = 'Agreement review'
                    AccessPackageId = 'aaaa1111-0000-0000-0000-000000000061'; AssignmentPolicyId = 'bbbb2222-0000-0000-0000-000000000061'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            # The ONE transport mock both sides send through. It dispatches on the URI's shape, not on the
            # exact string, so a URI that drifts on one side is still answered and the comparison below
            # is what reports it.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                $script:AgCalls.Add([string]$Uri)
                $Base = 'v1.0/identityGovernance/entitlementManagement/'
                if ($Uri.StartsWith($Base + 'accessPackages/')) { return @{ id = $script:AgApId; displayName = $script:AgApName } }
                if ($Uri.StartsWith($Base + 'assignmentPolicies/')) { return @{ id = $script:AgPolId; displayName = $script:AgPolName } }
                if ($Uri.StartsWith($Base + 'accessPackages?')) { return @{ value = @($script:AgPackages) } }
                if ($Uri.StartsWith($Base + 'assignmentPolicies?')) { return @{ value = @($script:AgPolicies) } }
                throw "Unexpected Graph request: $Uri"
            }
        }

        It 'agrees with both resolvers on <Case>' -ForEach @(
            @{ Case = 'a name this object alone carries'; Tenant = 'Unique'; Outcome = 'This' }
            @{ Case = 'a name two objects carry, in two letter cases'; Tenant = 'Shared'; Outcome = 'Ambiguous' }
            @{ Case = 'a name no object carries'; Tenant = 'None'; Outcome = 'Null' }
            @{ Case = 'a name one other object alone carries'; Tenant = 'Another'; Outcome = 'Other' }
        ) {
            $This = @{ Ap = @{ id = $script:AgApId; displayName = $script:AgApName }; Pol = @{ id = $script:AgPolId; displayName = $script:AgPolName } }
            switch ($Tenant) {
                'Unique' {
                    $script:AgPackages = @($This.Ap)
                    $script:AgPolicies = @($This.Pol, @{ id = $script:AgOtherPolId; displayName = 'Premium' })
                }
                'Shared' {
                    $script:AgPackages = @($This.Ap, @{ id = $script:AgOtherApId; displayName = $script:AgApName.ToUpperInvariant() })
                    $script:AgPolicies = @($This.Pol, @{ id = $script:AgOtherPolId; displayName = $script:AgPolName.ToUpperInvariant() })
                }
                'None' {
                    $script:AgPackages = @()
                    $script:AgPolicies = @(@{ id = $script:AgOtherPolId; displayName = 'Premium' })
                }
                'Another' {
                    $script:AgPackages = @(@{ id = $script:AgOtherApId; displayName = $script:AgApName })
                    $script:AgPolicies = @(@{ id = $script:AgOtherPolId; displayName = $script:AgPolName })
                }
            }

            # The resolvers, as the apply engine calls them for a name.
            $script:AgCalls.Clear()
            $ApOutcome = Get-AgResolverOutcome -ThisId $script:AgApId -Resolve {
                InModuleScope $script:moduleName -Parameters @{ Name = $script:AgApName } {
                    param($Name)
                    Resolve-OERAccessPackageId -DisplayName $Name
                }
            }
            $ResolverApUri = @($script:AgCalls)
            $script:AgCalls.Clear()
            $PolOutcome = Get-AgResolverOutcome -ThisId $script:AgPolId -Resolve {
                InModuleScope $script:moduleName -Parameters @{ PackageId = $script:AgApId; Name = $script:AgPolName } {
                    param($PackageId, $Name)
                    Resolve-OERAssignmentPolicyId -AccessPackageId $PackageId -AssignmentPolicy $Name
                }
            }
            $ResolverPolUri = @($script:AgCalls)

            # The export.
            $script:AgCalls.Clear()
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            $Ar = @($Inv.AccessReviews)[0]
            $ExportApUri = @($script:AgCalls | Where-Object { $_.StartsWith('v1.0/identityGovernance/entitlementManagement/accessPackages?') })
            $ExportPolUri = @($script:AgCalls | Where-Object { $_.StartsWith('v1.0/identityGovernance/entitlementManagement/assignmentPolicies?') })

            # Each case reaches the resolver outcome it is about, so the four together cover all four.
            $ApOutcome | Should -BeExactly $Outcome
            $PolOutcome | Should -BeExactly $Outcome
            # (a) The same request, byte for byte.
            $ResolverApUri.Count | Should -Be 1
            $ExportApUri.Count | Should -Be 1
            $ExportApUri[0] | Should -BeExactly $ResolverApUri[0]
            $ResolverPolUri.Count | Should -Be 1
            $ExportPolUri.Count | Should -Be 1
            $ExportPolUri[0] | Should -BeExactly $ResolverPolUri[0]
            # (b) The same decision: the name exactly when the resolver returns this object's id.
            $Ar.accessPackage | Should -BeExactly $(if ($ApOutcome -eq 'This') { $script:AgApName } else { $script:AgApId })
            $Ar.assignmentPolicy | Should -BeExactly $(if ($PolOutcome -eq 'This') { $script:AgPolName } else { $script:AgPolId })
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }
    }

    Context 'access review name lookups through the real transport' {
        # The unit tests above mock Invoke-OERGraphRequest, which can never show what lands in the
        # caller's -ErrorVariable: that collection is filled by the ENGINE, so a swallowed throw
        # still leaves its records (measured: 10 per lookup through Get-OERAccessPackage and
        # Get-OERAccessPackageAssignmentPolicy, identical for a 404 and a 403). Only a read that never
        # raises leaves none, so these drive the REAL wrapper and stub only the SDK cmdlet, as a plain
        # function declared inside InModuleScope (the pattern Invoke-OERGraphRequest.Tests.ps1
        # explains: -StatusCodeVariable is set one frame up, where a Pester mock body cannot reach).
        BeforeAll {
            $script:ArApId = '11111111-1111-1111-1111-111111111111'
            $script:ArPolId = '22222222-2222-2222-2222-222222222222'
            $script:ArRunTransport = {
                param([string]$ApCode, [string]$PolCode)
                InModuleScope $script:moduleName -Parameters @{ ApCode = $ApCode; PolCode = $PolCode } {
                    param($ApCode, $PolCode)
                    $script:ArProbeCalls = [System.Collections.Generic.List[string]]::new()
                    $script:ArProbeApCode = $ApCode
                    $script:ArProbePolCode = $PolCode
                    try {
                        function Invoke-MgGraphRequest {
                            [CmdletBinding()]
                            param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                                [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                            $script:ArProbeCalls.Add("$Method $Uri")
                            $Code = if ($Uri -like '*/accessPackages/*') { $script:ArProbeApCode } elseif ($Uri -like '*/assignmentPolicies/*') { $script:ArProbePolCode } else { 'Unexpected' }
                            $Status = if ($Code -eq 'Authorization_RequestDenied') { 403 } else { 404 }
                            $Json = '{"error":{"code":"' + $Code + '","message":"stub ' + $Code + '"}}'
                            if ($SkipHttpErrorCheck) {
                                Set-Variable -Name $StatusCodeVariable -Value $Status -Scope 1
                                return ($Json | ConvertFrom-Json -AsHashtable)
                            }
                            $Http = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
                            $Http.Content = [System.Net.Http.StringContent]::new($Json)
                            $Ex = [System.Exception]::new("Response status code does not indicate success: $Status.")
                            $Ex | Add-Member -NotePropertyName Response -NotePropertyValue $Http -Force
                            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                                    $Ex, 'InvokeGraphHttpResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null))
                        }
                        $Ev = $null
                        $Out = @(Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable Ev -WarningAction SilentlyContinue)
                        $Inv = $Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.Inventory' } | Select-Object -First 1
                        [ordered]@{
                            Calls = @($script:ArProbeCalls)
                            Records = @($Ev | Where-Object { $null -ne $_ })
                            AccessPackage = [string]@($Inv.AccessReviews)[0].accessPackage
                            AssignmentPolicy = [string]@($Inv.AccessReviews)[0].assignmentPolicy
                        }
                    } finally {
                        Remove-Item 'function:Invoke-MgGraphRequest' -ErrorAction SilentlyContinue
                        Remove-Variable -Name ArProbeCalls, ArProbeApCode, ArProbePolCode -Scope Script -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Q3 AP review'
                    AccessPackageId = '11111111-1111-1111-1111-111111111111'
                    AssignmentPolicyId = '22222222-2222-2222-2222-222222222222'
                    Reviewers = @(); Recurrence = $null; DurationInDays = 14
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
        }

        It 'leaves the caller error stream EMPTY for a review whose package and policy were deleted' {
            $Run = & $script:ArRunTransport 'AccessPackageNotFound' 'PolicyNotFound'
            # The positive half first: the id is what a deleted target is written as, and both reads
            # really went through the wrapper to the stubbed SDK cmdlet.
            $Run.AccessPackage | Should -Be $script:ArApId
            $Run.AssignmentPolicy | Should -Be $script:ArPolId
            @($Run.Calls).Count | Should -Be 2
            $Run.Calls | Should -Contain ('GET ' + 'v1.0/identityGovernance/entitlementManagement/accessPackages/11111111-1111-1111-1111-111111111111?$expand=catalog')
            $Run.Calls | Should -Contain ('GET ' + 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/22222222-2222-2222-2222-222222222222?$expand=accessPackage')
            @($Run.Records).Count | Should -Be 0 -Because ('a deleted target must deposit nothing in the operator error stream; left behind: ' +
                (@($Run.Records | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }

        It 'raises a refused read through the same transport and ends the run in InventoryPartial' {
            $Run = & $script:ArRunTransport 'Authorization_RequestDenied' 'Authorization_RequestDenied'
            $Run.AccessPackage | Should -Be $script:ArApId
            $Run.AssignmentPolicy | Should -Be $script:ArPolId
            @($Run.Calls).Count | Should -Be 2
            $Partial = @(@($Run.Records) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'accessReviews/Q3 AP review/accessPackage, accessReviews/Q3 AP review/assignmentPolicy'
            $Partial[0].Exception.Message | Should -Match 'Authorization_RequestDenied'
        }

        It 'raises a not-found code that was not declared and ends the run in InventoryPartial' {
            # The wrapper softens only the codes the caller named. The stubbed SDK answers 404 with
            # Request_ResourceNotFound, which is NOT declared for either read, so it must be raised and
            # counted -- an undeclared not-found spelling is a surprise to report, never a deleted target.
            $Run = & $script:ArRunTransport 'Request_ResourceNotFound' 'Request_ResourceNotFound'
            $Run.AccessPackage | Should -Be $script:ArApId
            $Run.AssignmentPolicy | Should -Be $script:ArPolId
            @($Run.Calls).Count | Should -Be 2
            $Partial = @(@($Run.Records) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'accessReviews/Q3 AP review/accessPackage, accessReviews/Q3 AP review/assignmentPolicy'
            $Partial[0].Exception.Message | Should -Match 'Request_ResourceNotFound'
        }
    }

    Context 'RoleManagementPolicies common-role switches' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy {
                [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; RoleName = 'Reader'; AllowPermanentEligibility = $false; ActivationMaxHours = 8 }
            }
        }

        It 'delegates to Get-OERRoleManagementPolicy -CommonRoles' {
            Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -CommonRoles -IncludeARM | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -ParameterFilter { $CommonRoles -eq $true }
        }

        It 'delegates to Get-OERRoleManagementPolicy -AllRolesAtScope' {
            Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -AllRolesAtScope -IncludeARM | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -ParameterFilter { $AllRolesAtScope -eq $true }
        }

        It 'warns and skips when more than one role source is supplied' {
            Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -Role 'Reader' -CommonRoles -IncludeARM -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
            $warned | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 0
        }

        It 'warns and skips when -CommonRoles is given without a target scope' {
            Get-OERInventory -Include RoleManagementPolicies -CommonRoles -IncludeARM -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
            $warned | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 0
        }

        It 'warns and skips when -AllRolesAtScope is given without a target scope' {
            Get-OERInventory -Include RoleManagementPolicies -AllRolesAtScope -IncludeARM -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
            $warned | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 0
        }

        It 'projects the delegated policies into the RoleManagementPolicies section' {
            $Result = Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -CommonRoles -IncludeARM
            @($Result.RoleManagementPolicies).Count | Should -Be 1
            $Result.RoleManagementPolicies[0].role | Should -Be 'Reader'
        }
    }

    Context 'RoleManagementPolicies projection' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    PolicyId                               = '/p/1'
                    Scope                                  = '/subscriptions/sub-1'
                    RoleName                               = 'Contributor'
                    RoleDefinitionId                       = '/rd/1'
                    ActivationMaxHours                     = 4
                    RequireMfaOnActivation                 = $true
                    RequireJustificationOnActivation       = $true
                    RequireTicketOnActivation              = $false
                    RequireApproval                        = $true
                    Approvers                              = @(
                        [PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' }
                        [PSCustomObject]@{ DisplayName = 'Anna'; Id = 'usr-1'; UserType = 'User' }
                    )
                    AuthenticationContextId                = $null
                    AllowPermanentEligibility              = $true
                    EligibleDuration                       = 'P365D'
                    EligibleDurationDays                   = 365
                    AllowPermanentActiveAssignment         = $false
                    ActiveDuration                         = 'P180D'
                    ActiveDurationDays                     = 180
                    RequireMfaOnActiveAssignment           = $false
                    RequireJustificationOnActiveAssignment = $true
                }
            }
        }

        It 'projects the full settable policy surface, not just two fields' {
            $Policy = (Get-OERInventory -Include RoleManagementPolicies -Subscription 'sub-1' -CommonRoles -IncludeARM).RoleManagementPolicies[0]
            $Policy.scope                                  | Should -Be '/subscriptions/sub-1'
            $Policy.role                                   | Should -Be 'Contributor'
            $Policy.allowPermanentEligibility              | Should -Be $true
            $Policy.activationMaxHours                     | Should -Be 4
            $Policy.eligibleDurationDays                   | Should -Be 365
            $Policy.allowPermanentActiveAssignment         | Should -Be $false
            $Policy.activeDurationDays                     | Should -Be 180
            $Policy.requireMfaOnActivation                 | Should -Be $true
            $Policy.requireJustificationOnActivation       | Should -Be $true
            $Policy.requireTicketOnActivation              | Should -Be $false
            $Policy.requireApproval                        | Should -Be $true
            $Policy.requireMfaOnActiveAssignment           | Should -Be $false
            $Policy.requireJustificationOnActiveAssignment | Should -Be $true
            @($Policy.approvers.groups)                    | Should -Be @('grp-1')
            @($Policy.approvers.users)                     | Should -Be @('usr-1')
        }

        It 'omits authenticationContextId when the authentication context is disabled' {
            $Policy = (Get-OERInventory -Include RoleManagementPolicies -Subscription 'sub-1' -CommonRoles -IncludeARM).RoleManagementPolicies[0]
            $Policy.PSObject.Properties.Name | Should -Not -Contain 'authenticationContextId'
        }

        It 'omits requireMfaOnActivation when an authentication context is emitted' {
            # ARM treats the two as mutually exclusive and Test-OERStructureSchema raises an Error when
            # both are declared, so a captured inventory must never carry both or it fails its own
            # validation (and the Export-OERInventory schema self-check).
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    PolicyId                = '/p/1'
                    Scope                   = '/subscriptions/sub-1'
                    RoleName                = 'Contributor'
                    RoleDefinitionId        = '/rd/1'
                    ActivationMaxHours      = 4
                    RequireMfaOnActivation  = $true
                    AuthenticationContextId = 'c1'
                    Approvers               = @()
                }
            }
            $Policy = (Get-OERInventory -Include RoleManagementPolicies -Subscription 'sub-1' -CommonRoles -IncludeARM).RoleManagementPolicies[0]
            $Policy.authenticationContextId | Should -BeExactly 'c1'
            $Policy.PSObject.Properties.Name | Should -Not -Contain 'requireMfaOnActivation'
        }

        It 'produces a role management policy projection that passes its own offline validator' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicy {
                [PSCustomObject]@{
                    PolicyId                = '/p/1'
                    Scope                   = '/subscriptions/sub-1'
                    RoleName                = 'Contributor'
                    RoleDefinitionId        = '/rd/1'
                    ActivationMaxHours      = 4
                    RequireMfaOnActivation  = $true
                    AuthenticationContextId = 'c1'
                    Approvers               = @()
                }
            }
            $Inventory = Get-OERInventory -Include RoleManagementPolicies -Subscription 'sub-1' -CommonRoles -IncludeARM
            $Doc = [PSCustomObject]@{ version = '1.0'; roleManagementPolicies = @($Inventory.RoleManagementPolicies) }
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }
    }

    Context 'RoleAssignments section' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'
                    RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                    PrincipalId = 'p-1'
                    RoleName = 'Reader'
                    PrincipalDisplayName = 'Anna Berg'
                    PrincipalType = 'User'
                    RoleAssignmentId = '/subscriptions/sub-1/.../ra-1'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'p-1' = 'anna@contoso.com' } }
        }

        It 'projects role and principal as names (D6) and writes principalType User for a user (A18)' {
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.scope | Should -Be '/subscriptions/sub-1'
            $ra.role | Should -Be 'Reader'
            $ra.principal | Should -Be 'anna@contoso.com'
            # Sprint 11 step 6: principalType is written for every row whose type maps to the enum.
            $ra.principalType | Should -BeExactly 'User'
            @($ra.PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        }

        It 'requests resolved names from Get-OERRoleAssignment' {
            Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -ParameterFilter { $ResolveNames -eq $true -and $Subscription -eq 'Prod' }
        }

        It 'emits principalType for a service principal (D7)' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = 'Reader'; PrincipalDisplayName = 'Contoso SP'
                    PrincipalType = 'ServicePrincipal'; RoleDefinitionId = 'rd'; PrincipalId = 'sp-1'; RoleAssignmentId = 'ra-1'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'sp-1' = 'Contoso SP' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principalType | Should -Be 'ServicePrincipal'
            $ra.principal | Should -Be 'Contoso SP'
        }

        It 'maps a ForeignGroup principal type to Group and writes principalType Group (round-trip safe, A18)' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = 'Owner'; PrincipalDisplayName = 'Partner Admins'
                    PrincipalType = 'ForeignGroup'; RoleDefinitionId = 'rd'; PrincipalId = 'fg-1'; RoleAssignmentId = 'ra-fg'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'fg-1' = 'Partner Admins' } }
            # The one group in the tenant that carries the name (BL-131, Task 3c), so it is written by it.
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { & $script:NewGroupNameIndexOf @{ 'fg-1' = 'Partner Admins' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principal | Should -Be 'Partner Admins'
            # Never the ARM value ForeignGroup, which the schema enum does not hold.
            $ra.principalType | Should -BeExactly 'Group'
        }

        It 'falls back to ids when names are unresolved' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = $null; PrincipalDisplayName = $null
                    PrincipalType = 'User'; RoleDefinitionId = 'rd-full'; PrincipalId = 'p-1'; RoleAssignmentId = 'ra-1'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'p-1' = 'p-1' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.role | Should -Be 'rd-full'
            $ra.principal | Should -Be 'p-1'
        }

        It 'adds the role assignment id only with -IncludeId' {
            (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM -IncludeId).RoleAssignments[0].id | Should -Be '/subscriptions/sub-1/.../ra-1'
        }

        It 'warns and skips RoleAssignments when no scope is targeted' {
            Get-OERInventory -Include RoleAssignments -IncludeARM -WarningVariable warned -WarningAction SilentlyContinue | Out-Null
            $warned | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 0
        }

        It 'resolves a user principal to its UPN so it round-trips' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = 'Reader'; PrincipalDisplayName = 'Anna Berg'
                    PrincipalType = 'User'; RoleDefinitionId = 'rd-full'; PrincipalId = 'u-9'; RoleAssignmentId = 'ra-u9'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'u-9' = 'anna@contoso.com' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principal | Should -Be 'anna@contoso.com'
            $ra.principalType | Should -BeExactly 'User'
        }
    }

    Context 'roleAssignments condition and description projection' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed) & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent @{ 'p-1' = 'user@contoso.com' } }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{
                        Scope = '/subscriptions/s1'; RoleName = 'Reader'; RoleDefinitionId = '/rd/1'
                        PrincipalId = 'p-1'; PrincipalType = 'User'; PrincipalDisplayName = 'User'
                        RoleAssignmentId = '/ra/1'
                        Description = 'Read only on tagged blobs'
                        Condition = "@Resource[Microsoft.Storage/storageAccounts:name] StringEquals 'sa1'"
                        ConditionVersion = '2.0'
                    },
                    [PSCustomObject]@{
                        Scope = '/subscriptions/s1'; RoleName = 'Owner'; RoleDefinitionId = '/rd/2'
                        PrincipalId = 'p-1'; PrincipalType = 'User'; PrincipalDisplayName = 'User'
                        RoleAssignmentId = '/ra/2'
                        Description = $null; Condition = $null; ConditionVersion = $null
                    }
                )
            }
        }

        It 'projects condition, conditionVersion and description when present' {
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 's1'
            $Ra = @($Inv.RoleAssignments) | Where-Object { $_.role -eq 'Reader' }
            $Ra.description | Should -Be 'Read only on tagged blobs'
            $Ra.condition | Should -BeLike '*StringEquals*'
            $Ra.conditionVersion | Should -Be '2.0'
        }

        It 'omits the keys entirely for an unconditioned assignment' {
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 's1'
            $Ra = @($Inv.RoleAssignments) | Where-Object { $_.role -eq 'Owner' }
            $Ra.PSObject.Properties.Name | Should -Not -Contain 'condition'
            $Ra.PSObject.Properties.Name | Should -Not -Contain 'description'
        }

        It 'defaults conditionVersion to 2.0 when a condition is present without an explicit version' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/s1'; RoleName = 'Reader'; RoleDefinitionId = '/rd/1'
                    PrincipalId = 'p-1'; PrincipalType = 'User'; PrincipalDisplayName = 'User'
                    RoleAssignmentId = '/ra/1'
                    Description = $null
                    Condition = "@Resource[Microsoft.Storage/storageAccounts:name] StringEquals 'sa1'"
                    ConditionVersion = $null
                }
            }
            $Ra = (Get-OERInventory -Include RoleAssignments -Subscription 's1').RoleAssignments[0]
            $Ra.conditionVersion | Should -Be '2.0'
        }
    }

    Context 'a role assignment at the root scope is left out (BL-126)' {
        # The root scope '/' stands above every management group and subscription, so a role
        # assignment there is elevated access. The read at a management group or a subscription
        # returns it as inherited. The document never carries it: it is named in one warning and in one
        # information record per call instead. No id below is version-4 shaped.
        BeforeAll {
            $script:RootMg = '/providers/Microsoft.Management/managementGroups/plat'
            $script:RootSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:RootTag = 'Omnicit.EntraRBAC.RootScopeAssignment'
            function script:New-RootRa {
                param(
                    [string]$Scope, [string]$RoleName, [string]$PrincipalId, [string]$PrincipalType,
                    [string]$PrincipalName, [string]$RoleAssignmentId
                )
                [PSCustomObject]@{
                    Scope = $Scope; RoleName = $RoleName
                    RoleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/rd-$($RoleName -replace '\s', '')"
                    PrincipalId = $PrincipalId; PrincipalType = $PrincipalType; PrincipalDisplayName = $PrincipalName
                    RoleAssignmentId = $RoleAssignmentId
                }
            }
            # The warning Get-OERInventory writes for <Count> rows listed as <Rows>.
            function script:Get-RootWarningText {
                param([int]$Count, [string]$Rows)
                "Get-OERInventory: left out $Count role assignment(s) at the root scope '/', which grants access over every " +
                "management group and subscription in the tenant (elevated access): $Rows. A document never carries a role " +
                'assignment at the root scope, and Invoke-OERStructure never creates or removes one; review them as a finding.'
            }
            # The information records the call wrote with the root scope tag.
            function script:Get-RootNotice {
                param([object[]]$Information)
                @($Information | Where-Object { $_.Tags -contains $script:RootTag })
            }
            $script:RootUaa = New-RootRa -Scope '/' -RoleName 'User Access Administrator' -PrincipalId 'dddd2222-0000-0000-0000-000000000001' `
                -PrincipalType 'User' -PrincipalName 'Root Admin' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000001'
            $script:RootMgRow = New-RootRa -Scope $script:RootMg -RoleName 'Reader' -PrincipalId 'dddd2222-0000-0000-0000-000000000002' `
                -PrincipalType 'User' -PrincipalName 'User Two' -RoleAssignmentId "$($script:RootMg)/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000002"
            $script:RootSubRow = New-RootRa -Scope $script:RootSub -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000003' `
                -PrincipalType 'User' -PrincipalName 'User Three' -RoleAssignmentId "$($script:RootSub)/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000003"
        }

        BeforeEach {
            $script:RootNames = @{
                'dddd2222-0000-0000-0000-000000000001' = 'person1@example.com'
                'dddd2222-0000-0000-0000-000000000002' = 'person2@example.com'
                'dddd2222-0000-0000-0000-000000000003' = 'person3@example.com'
            }
            $script:RootRas = @($script:RootUaa, $script:RootMgRow, $script:RootSubRow)
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:RootRas }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent $script:RootNames
            }
            # BL-131 (Task 3c): the tenant's groups are the groups the rows name, each under the name the
            # fixture gives it, so a group principal is shared or unique as the fixture says.
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex {
                $NameById = @{}
                foreach ($Row in @($script:RootRas)) {
                    if ([string]$Row.PrincipalType -notin @('Group', 'ForeignGroup')) { continue }
                    if ($script:RootNames.ContainsKey([string]$Row.PrincipalId)) { $NameById[[string]$Row.PrincipalId] = $script:RootNames[[string]$Row.PrincipalId] }
                }
                & $script:NewGroupNameIndexOf $NameById
            }
        }

        It 'leaves the inherited root row out of a read at <Target>, names it in one warning and in one information record' -ForEach @(
            @{ Target = 'a management group'; Splat = @{ ManagementGroup = 'plat' } }
            @{ Target = 'a subscription'; Splat = @{ Subscription = 'aaaa1111-0000-0000-0000-000000000001' } }
        ) {
            $W = $null
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments @Splat -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            # Reach proof: the section was read once, at the target.
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @(
                "$($script:RootMg)|Reader|person2@example.com"
                "$($script:RootSub)|Owner|person3@example.com"
            )
            @($Inv.roleAssignments | Where-Object { $_.scope -eq '/' }).Count | Should -Be 0
            $Expected = Get-RootWarningText -Count 1 -Rows "'User Access Administrator' for 'person1@example.com' (User)"
            @($W).Count | Should -Be 1
            [string]$W[0].Message | Should -BeExactly $Expected
            $Records = Get-RootNotice -Information @($Info)
            $Records.Count | Should -Be 1
            $Notice = $Records[0].MessageData
            $Notice.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.RootScopeAssignmentNotice'
            $Notice.Warning | Should -BeExactly $Expected
            $Rows = @($Notice.Assignments)
            $Rows.Count | Should -Be 1
            @($Rows[0].PSObject.Properties.Name) | Should -Be @('RoleAssignmentId', 'Role', 'Principal', 'PrincipalType')
            $Rows[0].RoleAssignmentId | Should -BeExactly '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000001'
            $Rows[0].Role | Should -BeExactly 'User Access Administrator'
            $Rows[0].Principal | Should -BeExactly 'person1@example.com'
            $Rows[0].PrincipalType | Should -BeExactly 'User'
        }

        It 'sorts several root rows by role then principal, reads a ForeignGroup as Group and writes no parenthesis for an unknown type' {
            $script:RootNames['dddd2222-0000-0000-0000-000000000004'] = 'Zeta Partners'
            $script:RootNames['dddd2222-0000-0000-0000-000000000005'] = 'Alpha Ops'
            $script:RootRas = @(
                $script:RootUaa
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000004' -PrincipalType 'ForeignGroup' `
                    -PrincipalName 'Zeta Partners' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000004'
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000005' -PrincipalType '' `
                    -PrincipalName 'Alpha Ops' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000005'
                $script:RootSubRow
            )
            $W = $null
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @('person3@example.com')
            $Expected = Get-RootWarningText -Count 3 -Rows ("'Owner' for 'Alpha Ops'; 'Owner' for 'Zeta Partners' (Group); " +
                "'User Access Administrator' for 'person1@example.com' (User)")
            @($W).Count | Should -Be 1
            [string]$W[0].Message | Should -BeExactly $Expected
            $Records = Get-RootNotice -Information @($Info)
            $Records.Count | Should -Be 1
            $Records[0].MessageData.Warning | Should -BeExactly $Expected
            # The record lists the rows in the warning's order.
            @($Records[0].MessageData.Assignments | ForEach-Object { "$($_.Role)|$($_.Principal)|$($_.PrincipalType)" }) | Should -Be @(
                'Owner|Alpha Ops|'
                'Owner|Zeta Partners|Group'
                'User Access Administrator|person1@example.com|User'
            )
        }

        It 'separates the root rows before the collision pass, so a non-root row keeps its name' {
            # The collision key is the validator's: the canonical scope, the role and the principal,
            # joined with '|'. A root row and a non-root row can share that key only through a '|' inside
            # a name: here the root row's group is called 'Ops|Team', and the non-root row's scope ends
            # in '|Reader' (Azure Resource Manager never returns such a scope; it is the one shape that
            # makes the two keys equal). Kept in the pass, the root row would move BOTH principals to
            # their object ids; separated first, it never changes how another row is named.
            $script:RootNames = @{
                'dddd2222-0000-0000-0000-000000000006' = 'Ops|Team'
                'dddd2222-0000-0000-0000-000000000007' = 'Team'
            }
            $script:RootRas = @(
                New-RootRa -Scope '/' -RoleName 'Reader' -PrincipalId 'dddd2222-0000-0000-0000-000000000006' -PrincipalType 'Group' `
                    -PrincipalName 'Ops|Team' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000006'
                New-RootRa -Scope '/|Reader' -RoleName 'Ops' -PrincipalId 'dddd2222-0000-0000-0000-000000000007' -PrincipalType 'Group' `
                    -PrincipalName 'Team' -RoleAssignmentId '/|Reader/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000007'
            )
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments).Count | Should -Be 1
            $Inv.roleAssignments[0].principal | Should -BeExactly 'Team'
            # Sprint 11 step 6 (A18): principalType is written for every row whose type maps to the enum,
            # so it is there whether or not the pass moved the row; the name above is the proof.
            $Inv.roleAssignments[0].principalType | Should -BeExactly 'Group'
            @((Get-RootNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { $_.Principal }) | Should -Be @('Ops|Team')
        }

        It 'names two root rows that share a principal name by that name: the collision pass never sees them' {
            # Two users the name lookup names alike: the collision pass would name them by id if it saw
            # them. (Two GROUPS of one name are named by id before the split, by the group rule; the next
            # test holds that.)
            $script:RootNames = @{
                'dddd2222-0000-0000-0000-000000000008' = 'Ops'
                'dddd2222-0000-0000-0000-000000000009' = 'Ops'
            }
            $script:RootRas = @(
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000008' -PrincipalType 'User' `
                    -PrincipalName 'Ops' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000008'
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000009' -PrincipalType 'User' `
                    -PrincipalName 'Ops' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000009'
            )
            $W = $null
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments).Count | Should -Be 0
            [string]$W[0].Message | Should -BeExactly (Get-RootWarningText -Count 2 -Rows "'Owner' for 'Ops' (User); 'Owner' for 'Ops' (User)")
            # The record tells the two apart by their role assignment ids.
            @((Get-RootNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { $_.RoleAssignmentId }) | Should -Be @(
                '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000008'
                '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000009'
            )
        }

        It 'names two root group rows whose name the tenant shares by their object ids: the group rule runs before the split' {
            # BL-131 (Task 3c): a group principal is named once, where the row is projected, and the root
            # rows are taken out after that, so the warning and the record name a group of a shared name
            # the way the document would have.
            $script:RootNames = @{
                'dddd2222-0000-0000-0000-000000000008' = 'Ops'
                'dddd2222-0000-0000-0000-000000000009' = 'Ops'
            }
            $script:RootRas = @(
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000008' -PrincipalType 'Group' `
                    -PrincipalName 'Ops' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000008'
                New-RootRa -Scope '/' -RoleName 'Owner' -PrincipalId 'dddd2222-0000-0000-0000-000000000009' -PrincipalType 'Group' `
                    -PrincipalName 'Ops' -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/cccc2222-0000-0000-0000-000000000009'
            )
            $W = $null
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments).Count | Should -Be 0
            [string]$W[0].Message | Should -BeExactly (Get-RootWarningText -Count 2 -Rows ("'Owner' for 'dddd2222-0000-0000-0000-000000000008' (Group); " +
                    "'Owner' for 'dddd2222-0000-0000-0000-000000000009' (Group)"))
            @((Get-RootNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { "$($_.Principal)|$($_.PrincipalType)" }) | Should -Be @(
                'dddd2222-0000-0000-0000-000000000008|Group'
                'dddd2222-0000-0000-0000-000000000009|Group'
            )
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'writes no warning and no information record when no row is at the root scope, and the document is as before' {
            $script:RootRas = @($script:RootMgRow, $script:RootSubRow)
            $W = $null
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -ManagementGroup 'plat' -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @(
                "$($script:RootMg)|Reader|person2@example.com"
                "$($script:RootSub)|Owner|person3@example.com"
            )
            @($W).Count | Should -Be 0
            @($Info | Where-Object Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment').Count | Should -Be 0
        }

        It 'exports a document the validator accepts with no root scope finding' {
            $Inv = Get-OERInventory -Include RoleAssignments -ManagementGroup 'plat' -IncludeARM -WarningAction SilentlyContinue
            # Reach proof: the read held a root row, and the document holds the other two.
            @($Inv.roleAssignments).Count | Should -Be 2
            $V = InModuleScope $script:moduleName -Parameters @{ D = $Inv } { param($D) Test-OERStructureSchema -Document $D }
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object { $_.Section -eq 'roleAssignments' }).Count | Should -Be 0
            @($V.Errors | Where-Object { $_.Message -match 'root scope' }).Count | Should -Be 0
        }
    }

    Context 'a role assignment at a scope no document can declare is left out (A13, A15)' {
        # Azure Resource Manager can return a role assignment at a scope whose spelling the validator
        # refuses (Get-OERScopeSpellingProblem owns the rules): a resource whose name holds a '#' or a
        # '%', for one. A document that carried it would be refused as a whole, so the section leaves it
        # out, after the root split and before the collision pass, counts the rows in one warning and
        # hands them over in one information record. Scopes holding '#' or '%' are fixtures only. No id
        # below is version-4 shaped.
        BeforeAll {
            $script:UdSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:UdHash = "$($script:UdSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1"
            $script:UdPercent = "$($script:UdSub)/resourceGroups/rg%2Fone"
            $script:UdTag = 'Omnicit.EntraRBAC.UndeclarableScope'
            function script:New-UdRa {
                param([string]$Scope, [string]$RoleName, [string]$PrincipalId, [string]$PrincipalType)
                [PSCustomObject]@{
                    Scope = $Scope; RoleName = $RoleName
                    RoleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/rd-$($RoleName -replace '\s', '')"
                    PrincipalId = $PrincipalId; PrincipalType = $PrincipalType; PrincipalDisplayName = 'read under another name'
                    RoleAssignmentId = "/providers/Microsoft.Authorization/roleAssignments/$PrincipalId-$($RoleName -replace '\s', '')"
                }
            }
            # The warning Get-OERInventory writes for <Count> rows left out.
            function script:Get-UdWarningText {
                param([int]$Count)
                "Get-OERInventory: left out $Count role assignment(s) whose scope no document can declare: the validator refuses " +
                "the scope's spelling, so a document that carried one would be refused as a whole. Invoke-OERStructure never " +
                'creates such an assignment, and never removes one, since it prunes only at a scope a document declares. An ' +
                'information record tagged Omnicit.EntraRBAC.UndeclarableScope names each with the rules its scope breaks; review ' +
                'them as a finding.'
            }
            function script:Get-UdNotice {
                param([object[]]$Information)
                @($Information | Where-Object { $_.Tags -contains $script:UdTag })
            }
            # The InventoryPartial records Get-OERInventory itself published.
            function script:Get-UdPartial {
                param([object[]]$Record)
                @($Record | Where-Object {
                        $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' -and
                        $_.FullyQualifiedErrorId -like 'InventoryPartial*'
                    })
            }
        }

        BeforeEach {
            $script:UdNames = @{
                'dddd3333-0000-0000-0000-000000000001' = 'person1@example.com'
                'dddd3333-0000-0000-0000-000000000002' = 'person2@example.com'
                'dddd3333-0000-0000-0000-000000000003' = 'Automation'
                'dddd3333-0000-0000-0000-000000000004' = 'Automation'
            }
            $script:UdRas = @()
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:UdRas }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent $script:UdNames
            }
        }

        It 'leaves a role assignment at a scope holding a ''#'' and one holding a ''%'' out, counts them in one warning and hands them over in one information record' {
            $script:UdRas = @(
                New-UdRa -Scope $script:UdSub -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User'
                New-UdRa -Scope $script:UdHash -RoleName 'Contributor' -PrincipalId 'dddd3333-0000-0000-0000-000000000002' -PrincipalType 'User'
                New-UdRa -Scope $script:UdPercent -RoleName 'Owner' -PrincipalId 'dddd3333-0000-0000-0000-000000000003' -PrincipalType 'ServicePrincipal'
            )
            $W = $null; $Info = $null; $InvErr = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM `
                -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
            # Reach proof: the section was read once.
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.role)|$($_.principal)" }) | Should -Be @("$($script:UdSub)|Reader|person1@example.com")
            @($W).Count | Should -Be 1
            [string]$W[0].Message | Should -BeExactly (Get-UdWarningText -Count 2)
            $Records = Get-UdNotice -Information @($Info)
            $Records.Count | Should -Be 1
            $Notice = $Records[0].MessageData
            $Notice.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.UndeclarableScopeNotice'
            @($Notice.PSObject.Properties.Name) | Should -Be @('Warning', 'Assignments')
            $Notice.Warning | Should -BeExactly (Get-UdWarningText -Count 2)
            $Rows = @($Notice.Assignments)
            $Rows.Count | Should -Be 2
            @($Rows[0].PSObject.Properties.Name) | Should -Be @('RoleAssignmentId', 'Scope', 'Role', 'Principal', 'PrincipalType', 'Reason')
            @($Rows | ForEach-Object { "$($_.RoleAssignmentId)|$($_.Scope)|$($_.Role)|$($_.Principal)|$($_.PrincipalType)|$($_.Reason)" }) | Should -Be @(
                "/providers/Microsoft.Authorization/roleAssignments/dddd3333-0000-0000-0000-000000000002-Contributor|$($script:UdHash)|Contributor|person2@example.com|User|the scope holds a question mark or a number sign"
                "/providers/Microsoft.Authorization/roleAssignments/dddd3333-0000-0000-0000-000000000003-Owner|$($script:UdPercent)|Owner|Automation|ServicePrincipal|the scope holds a percent sign"
            )
            # No other notice and nothing unread: the rows are left out, not unread.
            @($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment' }).Count | Should -Be 0
            @($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.UnresolvedPrincipal' }).Count | Should -Be 0
            (Get-UdPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'names every rule a scope breaks in words, in the owner''s order (<Case>)' -ForEach @(
            @{ Case = 'a trailing slash'; Suffix = '/resourceGroups/rg-one/'; Reason = 'the scope holds a trailing or doubled slash' }
            @{ Case = 'a parent segment'; Suffix = '/resourceGroups/rg-one/../rg-two'; Reason = "the scope holds a dot segment ('.' or '..')" }
            @{ Case = 'a backslash'; Suffix = '/resourceGroups\rg-one'; Reason = 'the scope holds a backslash' }
            @{ Case = 'a space at the start of a segment'; Suffix = '/resourceGroups/ rg-one'; Reason = 'the scope holds white space at the start or end of the scope or of a segment, white space other than a space, or a control character' }
            @{ Case = 'a percent sign and a number sign'; Suffix = '/resourceGroups/rg%25/providers/Microsoft.Web/sites/a#b'; Reason = 'the scope holds a percent sign; a question mark or a number sign' }
            @{ Case = 'every rule'; Suffix = '/ rg/..\%2e?#/'; Reason = ("the scope holds a trailing or doubled slash; a dot segment ('.' or '..'); a percent sign; a backslash; a question mark " +
                    'or a number sign; white space at the start or end of the scope or of a segment, white space other than a space, or a control character') }
        ) {
            $script:UdRas = @(New-UdRa -Scope "$($script:UdSub)$Suffix" -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User')
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments).Count | Should -Be 0
            $Rows = @((Get-UdNotice -Information @($Info))[0].MessageData.Assignments)
            $Rows.Count | Should -Be 1
            $Rows[0].Reason | Should -BeExactly $Reason
        }

        It 'names a rule it has no words for by the rule''s own name, so a reason is never empty' {
            # Get-OERScopeSpellingProblem owns the rules; a rule added there before the words here is still
            # named, by the Rule the owner returns.
            Mock -ModuleName $script:moduleName Get-OERScopeSpellingProblem {
                [PSCustomObject]@{ Rule = 'SomeLaterRule'; Message = 'not read here' }
            } -ParameterFilter { $Scope -eq $script:UdHash }
            $script:UdRas = @(New-UdRa -Scope $script:UdHash -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User')
            $Info = $null
            $null = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction SilentlyContinue -InformationVariable Info
            Should -Invoke -ModuleName $script:moduleName Get-OERScopeSpellingProblem -Times 1 -Exactly -ParameterFilter { $Scope -eq $script:UdHash }
            @((Get-UdNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { $_.Reason }) | Should -Be @('the scope holds SomeLaterRule')
        }

        It 'leaves a role assignment at the root scope whose spelling is refused too in the root list only (<Scope>)' -ForEach @(
            @{ Scope = '//' }
            @{ Scope = '/%2e' }
        ) {
            $script:UdRas = @(
                New-UdRa -Scope $Scope -RoleName 'User Access Administrator' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User'
                New-UdRa -Scope $script:UdSub -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000002' -PrincipalType 'User'
            )
            $W = $null; $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM `
                -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @('person2@example.com')
            # Reach proof: the row reached the root list.
            @(@($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment' })[0].MessageData.Assignments | ForEach-Object { $_.Principal }) |
                Should -Be @('person1@example.com')
            (Get-UdNotice -Information @($Info)).Count | Should -Be 0
            @($W | Where-Object { [string]$_.Message -like '*no document can declare*' }).Count | Should -Be 0
            @($W).Count | Should -Be 1
        }

        It 'separates the undeclarable rows before the collision pass, so a row the document keeps keeps its name' {
            # Two service principals that the name lookup names alike, one at the subscription and one at the
            # same scope written with a trailing '/', which the canonical form merges with it: kept in the
            # pass, the refused row would move BOTH principals to their object ids.
            $script:UdRas = @(
                New-UdRa -Scope $script:UdSub -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000003' -PrincipalType 'ServicePrincipal'
                New-UdRa -Scope "$($script:UdSub)/" -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000004' -PrincipalType 'ServicePrincipal'
            )
            $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.principal)" }) | Should -Be @("$($script:UdSub)|Automation")
            @((Get-UdNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { "$($_.Scope)|$($_.Principal)" }) |
                Should -Be @("$($script:UdSub)/|Automation")
        }

        It 'never looks a principal of an undeclarable row up among the deleted items, and never reports its failed lookup' {
            $script:UdRas = @(
                New-UdRa -Scope $script:UdHash -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000009' -PrincipalType 'User'
                New-UdRa -Scope $script:UdPercent -RoleName 'Owner' -PrincipalId 'dddd3333-0000-0000-0000-000000000010' -PrincipalType 'User'
            )
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                foreach ($One in @($Id)) {
                    if ($One -eq 'dddd3333-0000-0000-0000-000000000009') { [PSCustomObject]@{ Id = $One; Read = $true; Found = $false; Name = $null; ObjectType = $null; Cause = $null } }
                    else { [PSCustomObject]@{ Id = $One; Read = $false; Found = $false; Name = $null; ObjectType = $null; Cause = 'Too many requests (429)' } }
                }
            }
            $W = $null; $Info = $null; $InvErr = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM `
                -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
            @($Inv.roleAssignments).Count | Should -Be 0
            # Reach proof: both rows reached the undeclarable list, by their object ids.
            @((Get-UdNotice -Information @($Info))[0].MessageData.Assignments | ForEach-Object { $_.Principal }) | Should -Be @(
                'dddd3333-0000-0000-0000-000000000009'
                'dddd3333-0000-0000-0000-000000000010'
            )
            Should -Invoke -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus -Times 0
            @($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.UnresolvedPrincipal' }).Count | Should -Be 0
            @($W | ForEach-Object { [string]$_.Message }) | Should -Be @(Get-UdWarningText -Count 2)
            (Get-UdPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'writes no such warning and no such record when every scope can be declared, a space between other characters of a name included' {
            $script:UdRas = @(
                New-UdRa -Scope $script:UdSub -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User'
                New-UdRa -Scope "$($script:UdSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/sales data" -RoleName 'Reader' `
                    -PrincipalId 'dddd3333-0000-0000-0000-000000000002' -PrincipalType 'User'
            )
            $W = $null; $Info = $null
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM `
                -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.roleAssignments).Count | Should -Be 2
            @($W).Count | Should -Be 0
            (Get-UdNotice -Information @($Info)).Count | Should -Be 0
        }

        It 'exports a document the validator accepts, with the undeclarable rows left out' {
            $script:UdRas = @(
                New-UdRa -Scope $script:UdSub -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User'
                New-UdRa -Scope $script:UdHash -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000002' -PrincipalType 'User'
                New-UdRa -Scope $script:UdPercent -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000002' -PrincipalType 'User'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction SilentlyContinue
            # Reach proof: the read held two refused rows, and the document holds the third.
            @($Inv.roleAssignments).Count | Should -Be 1
            $V = InModuleScope $script:moduleName -Parameters @{ D = $Inv } { param($D) Test-OERStructureSchema -Document $D }
            @($V.Errors | ForEach-Object { "$($_.Severity): $($_.Path): $($_.Message)" }) | Should -Be @()
            $V.Valid | Should -BeTrue
        }

        It 'stops at its warning under -WarningAction Stop, before it returns the inventory' {
            $script:UdRas = @(New-UdRa -Scope $script:UdHash -RoleName 'Reader' -PrincipalId 'dddd3333-0000-0000-0000-000000000001' -PrincipalType 'User')
            $script:UdOut = $null
            $Thrown = { $script:UdOut = Get-OERInventory -Include RoleAssignments -Subscription 'aaaa1111-0000-0000-0000-000000000001' -IncludeARM -WarningAction Stop } |
                Should -Throw -PassThru
            $Thrown.Exception.Message | Should -BeLike '*role assignment(s) whose scope no document can declare*'
            $null -eq $script:UdOut | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleAssignment -Times 1 -Exactly
        }

        It 'states the rule in the help' {
            $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
            $Help | Should -Match ([regex]::Escape('Omnicit.EntraRBAC.UndeclarableScope'))
            $Help | Should -Match ([regex]::Escape('is left out of the RoleAssignments section too: no document can declare that scope, so a document that carried it would be refused as a whole'))
            $Help | Should -Match ([regex]::Escape('The root scope is decided first, so a role assignment at the root scope whose spelling is refused too is named only as described above'))
            $Help | Should -Match ([regex]::Escape('(RoleAssignmentId, Scope, Role, Principal, PrincipalType and Reason, which names the rules the scope breaks in words)'))
            $Help | Should -Match ([regex]::Escape('it is not looked for among the deleted items, a failed lookup of it is not reported, and it never changes how another role assignment is named'))
            # Sprint 11 step 6: the help names where the rules are listed instead of repeating them,
            # so a rule added to Get-OERScopeSpellingProblem cannot leave this text silently incomplete.
            $Help | Should -Match ([regex]::Escape('(Test-OERStructure refuses such a scope as an Error; about_Omnicit.EntraRBAC lists the rules under RENAMES, MAIL ALIASES AND SCOPE SPELLING)'))
            $Help | Should -Not -Match ([regex]::Escape("a '.' or '..' segment, a '%', a '\', a '?' or a '#', a trailing or doubled '/'"))
        }
    }

    Context 'the export never writes a duplicate entry' {
        # Entra does not keep display names unique, and Azure returns scopes in whatever spelling it
        # stored. An export that wrote two entries the validator refuses as duplicates would make the
        # whole document unappliable, so the cmdlet resolves every collision itself: top-level objects
        # whose names collide are left out and reported, role assignments whose principals collide are
        # written by object id, and a role policy read twice is written once. Every document below is
        # held against Test-OERStructure, the same validator Invoke-OERStructure runs first. No id is
        # version-4 shaped.
        BeforeAll {
            $script:DupSub1 = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:DupRoleDef1 = "$($script:DupSub1)/providers/Microsoft.Authorization/roleDefinitions/bbbb1111-0000-0000-0000-000000000001"
            $script:DupRoleDef2 = "$($script:DupSub1)/providers/Microsoft.Authorization/roleDefinitions/bbbb1111-0000-0000-0000-000000000002"
            $script:DupGrp1 = 'cccc1111-0000-0000-0000-000000000001'
            $script:DupGrp2 = 'cccc1111-0000-0000-0000-000000000002'
            $script:DupGrp3 = 'cccc1111-0000-0000-0000-000000000003'
            $script:DupUser1 = 'dddd1111-0000-0000-0000-000000000001'
            $script:DupUser2 = 'dddd1111-0000-0000-0000-000000000002'

            function script:New-DupGroup {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            function script:New-DupAdministrativeUnit {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; IsMemberManagementRestricted = $false
                    MembershipType = 'Assigned'; Visibility = $null; Members = @(); ScopedRoles = @()
                }
            }
            # An assignment policy as Get-OERAccessPackageAssignmentPolicy returns one, complete enough
            # for the projection to run on and valid once written.
            function script:New-DupPolicy {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; RequestorScope = $null; RequestorSettings = $null
                    RequireApproval = $false; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
                    ApprovalStages = @(); DurationInDays = 30; DurationInHours = $null; ExpirationDateTime = $null
                    NotificationsDisabled = $false
                }
            }
            function script:New-DupRoleAssignment {
                param(
                    [string]$PrincipalId, [string]$PrincipalType, [string]$PrincipalName,
                    [string]$Scope = $script:DupSub1, [string]$RoleName = 'Reader', [string]$RoleDefinitionId = $script:DupRoleDef1
                )
                [PSCustomObject]@{
                    Scope = $Scope; RoleName = $RoleName; RoleDefinitionId = $RoleDefinitionId
                    PrincipalId = $PrincipalId; PrincipalType = $PrincipalType; PrincipalDisplayName = $PrincipalName
                    RoleAssignmentId = "$Scope/providers/Microsoft.Authorization/roleAssignments/$PrincipalId"
                }
            }
            # The InventoryPartial records Get-OERInventory itself published: -ErrorVariable also
            # collects strays raised inside nested calls.
            function script:Get-DupPartial {
                param([object[]]$Record)
                @($Record | Where-Object {
                        $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' -and
                        $_.FullyQualifiedErrorId -like 'InventoryPartial*'
                    })
            }
            # What the offline validator says about a document: the result, and the Errors it refuses
            # the document for as printable lines. 'the validation helper reports a known duplicate'
            # below is the positive control for both, so a clean result is never a vacuous one.
            function script:Get-DupValidation {
                param([object]$Inventory)
                Test-OERStructure -InputObject $Inventory
            }
            function script:Get-DupValidationError {
                param([object]$Validation)
                @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { "$($_.Path): $($_.Message)" })
            }
            function script:Assert-DupDocumentValid {
                param([object]$Inventory)
                $Validation = Get-DupValidation -Inventory $Inventory
                Get-DupValidationError -Validation $Validation | Should -BeNullOrEmpty
                $Validation.Valid | Should -BeTrue
            }
        }

        BeforeEach {
            $script:DupGroups = @()
            $script:DupAdministrativeUnits = @()
            $script:DupCatalogs = @()
            $script:DupAccessPackages = @{}
            $script:DupAssignmentPolicies = @{}
            $script:DupRoleAssignments = @()
            $script:DupNames = @{}
            $script:DupPolicies = @()
            Mock -ModuleName $script:moduleName Get-OERGroup { $script:DupGroups }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { $script:DupAdministrativeUnits }
            Mock -ModuleName $script:moduleName Get-OERCatalog { $script:DupCatalogs }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { @() }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                param($Catalog)
                $script:DupAccessPackages[[string]$Catalog]
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { @() }
            # The policies of a package by the package id; a package with none answers nothing.
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                param($AccessPackage)
                if ($script:DupAssignmentPolicies.ContainsKey([string]$AccessPackage)) { $script:DupAssignmentPolicies[[string]$AccessPackage] }
            }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:DupRoleAssignments }
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy { $script:DupPolicies }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent $script:DupNames
            }
            # BL-131 (Task 3c): the tenant's groups are the groups the role assignments name, each under
            # the name the fixture gives it, so a group principal is shared or unique as the fixture says.
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex {
                $NameById = @{}
                foreach ($Ra in @($script:DupRoleAssignments)) {
                    if ([string]$Ra.PrincipalType -notin @('Group', 'ForeignGroup')) { continue }
                    $NameById[[string]$Ra.PrincipalId] = $(if ($script:DupNames.ContainsKey([string]$Ra.PrincipalId)) { $script:DupNames[[string]$Ra.PrincipalId] } else { $Ra.PrincipalDisplayName })
                }
                & $script:NewGroupNameIndexOf $NameById
            }
            # A review's access package and assignment policy names are read through the transport.
            # The catch-all FIRST makes any other request a loud failure instead of a real call.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage'
            }
            # BL-142: the apply engine's own lookups of the two names, each finding this object alone.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-1'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'ap-1'"
            }
        }

        It 'leaves out two groups whose names differ only in letter case, names them in InventoryPartial, and the document validates' {
            $script:DupGroups = @(
                New-DupGroup -Name 'Dup' -Id $script:DupGrp1
                New-DupGroup -Name 'dup' -Id $script:DupGrp2
                New-DupGroup -Name 'Solo' -Id $script:DupGrp3
            )
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.groups).Count | Should -Be 1 -Because 'both spellings of the shared name are left out and only Solo is written'
            @($Inv.groups)[0].displayName | Should -BeExactly 'Solo'
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1 -Because 'the left-out objects must be named, or the document reads as a full snapshot'
            [string]$Partial[0].TargetObject | Should -BeExactly 'groups/Dup'
            $Partial[0].Exception.Message | Should -Match 'share the name groups/Dup'
            $Partial[0].Exception.Message | Should -Match 'Unread: groups/Dup\. '
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'opens the InventoryPartial message by saying objects were left out for a shared name when that is the only cause' {
            # F5. Two live objects sharing a name is neither an unread collection nor a collection
            # written as null for want of a name: the objects are simply not written. The lead-in
            # must be true of that case alone, or it tells the operator a read failed that did not.
            $script:DupGroups = @(
                New-DupGroup -Name 'Dup' -Id $script:DupGrp1
                New-DupGroup -Name 'dup' -Id $script:DupGrp2
            )
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr
            # Reach proof: the groups were read, both were left out, and the shared name is the one cause.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            @($Inv.groups).Count | Should -Be 0
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groups/Dup'
            $Partial[0].Exception.Message | Should -Match '2 live objects share the name groups/Dup'
            $Partial[0].Exception.Message |
                Should -BeLike '*PARTIAL: 1 collection(s) or object(s) could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are not stated as facts in the document*'
        }

        It 'writes every group of a unique name and reports nothing when no two names collide' {
            $script:DupGroups = @(
                New-DupGroup -Name 'Alpha' -Id $script:DupGrp1
                New-DupGroup -Name 'Beta' -Id $script:DupGrp2
            )
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('Alpha', 'Beta')
            (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'leaves out two administrative units that share a name without regard to letter case' {
            $script:DupAdministrativeUnits = @(
                New-DupAdministrativeUnit -Name 'Team' -Id $script:DupGrp1
                New-DupAdministrativeUnit -Name 'TEAM' -Id $script:DupGrp2
                New-DupAdministrativeUnit -Name 'Solo AU' -Id $script:DupGrp3
            )
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.administrativeUnits | ForEach-Object { $_.displayName }) | Should -Be @('Solo AU')
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/Team'
            $Partial[0].Exception.Message | Should -Match 'share the name administrativeUnits/Team'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'leaves out two catalogs that share a name without regard to letter case' {
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'Core'; Description = 'one' }
                [PSCustomObject]@{ Id = 'cat-2'; DisplayName = 'core'; Description = 'two' }
                [PSCustomObject]@{ Id = 'cat-3'; DisplayName = 'Solo Catalog'; Description = 'three' }
            )
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.catalogs | ForEach-Object { $_.displayName }) | Should -Be @('Solo Catalog')
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'catalogs/Core'
            $Partial[0].Exception.Message | Should -Match 'share the name catalogs/Core'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'leaves out two access packages of one catalog that share a name, and keeps a package name shared across two catalogs' {
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'Core'; Description = 'one' }
                [PSCustomObject]@{ Id = 'cat-2'; DisplayName = 'Edge'; Description = 'two' }
            )
            $script:DupAccessPackages = @{
                'cat-1' = @(
                    [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'Sales'; Description = $null }
                    [PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'sales'; Description = $null }
                    [PSCustomObject]@{ Id = 'ap-3'; DisplayName = 'Shared'; Description = $null }
                )
                'cat-2' = @(
                    [PSCustomObject]@{ Id = 'ap-4'; DisplayName = 'Shared'; Description = $null }
                )
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.accessPackages | ForEach-Object { "$($_.catalog)/$($_.displayName)" }) |
                Should -Be @('Core/Shared', 'Edge/Shared') -Because 'the same package name in two catalogs is two different packages'
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/Core/Sales'
            $Partial[0].Exception.Message | Should -Match 'share the name accessPackages/Core/Sales'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'counts an access package collision on the validator''s key, so catalog A|B with package C and catalog A with package B|C are both left out' {
            # The validator keys a package on '<catalog>|<name>', so these two are one package to it
            # although no single separator character makes them look alike to a reader. A '/'-joined
            # key here saw two different packages, wrote both, and the document it exported was
            # refused by the validator it is meant to pass.
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'A|B'; Description = 'one' }
                [PSCustomObject]@{ Id = 'cat-2'; DisplayName = 'A'; Description = 'two' }
            )
            $script:DupAccessPackages = @{
                'cat-1' = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'C'; Description = $null })
                'cat-2' = @([PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'B|C'; Description = $null })
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr

            # Positive proof first: the collision was seen and named, with the reported name keeping its
            # '<catalog>/<name>' shape.
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/A|B/C'
            $Partial[0].Exception.Message | Should -Match 'share the name accessPackages/A\|B/C'
            @($Inv.accessPackages).Count | Should -Be 0
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'keeps two access packages whose catalog and name differ only in where a slash falls' {
            # The reverse of the case above: a '/'-joined key would call these two a collision, and the
            # validator does not. Catalog 'A/B' with package 'C' and catalog 'A' with package 'B/C' are
            # two packages, so both are written.
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'A/B'; Description = 'one' }
                [PSCustomObject]@{ Id = 'cat-2'; DisplayName = 'A'; Description = 'two' }
            )
            $script:DupAccessPackages = @{
                'cat-1' = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'C'; Description = $null })
                'cat-2' = @([PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'B/C'; Description = $null })
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.accessPackages | ForEach-Object { "$($_.catalog)|$($_.displayName)" }) | Should -Be @('A/B|C', 'A|B/C')
            (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0
            Assert-DupDocumentValid -Inventory $Inv
        }

        # BL-39 (Sprint 11 step 5): a catalog whose name another catalog carries is left out, and the apply
        # engine refuses its name as ambiguous, so a package in it is written with the catalog's object
        # id, which the engine takes as the catalog itself. The ids are the GUIDs Graph gives a catalog.
        It 'writes a package in a catalog whose name another catalog carries with the catalog''s id, and a package in a unique catalog with its name (BL-39)' {
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000001'; DisplayName = 'Core'; Description = 'one' }
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000002'; DisplayName = 'core'; Description = 'two' }
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000003'; DisplayName = 'Solo Catalog'; Description = 'three' }
            )
            # A package of one name in each of the two catalogs that share a name: two packages, two keys.
            $script:DupAccessPackages = @{
                'eeee5555-0000-0000-0000-000000000001' = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'Sales'; Description = $null })
                'eeee5555-0000-0000-0000-000000000002' = @([PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'Sales'; Description = $null })
                'eeee5555-0000-0000-0000-000000000003' = @([PSCustomObject]@{ Id = 'ap-3'; DisplayName = 'Edge'; Description = $null })
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info

            @($Inv.accessPackages | ForEach-Object { "$($_.catalog)|$($_.displayName)" }) | Should -Be @(
                'eeee5555-0000-0000-0000-000000000001|Sales'
                'eeee5555-0000-0000-0000-000000000002|Sales'
                'Solo Catalog|Edge'
            )
            @($Inv.catalogs | ForEach-Object { $_.displayName }) | Should -Be @('Solo Catalog')
            # The catalogs are the only names left out: the two packages named Sales do not collide.
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'catalogs/Core'
            $Names = @((@($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' }))[0].MessageData.Names)
            @($Names | ForEach-Object { "$($_.Section)|$($_.Name)|$($_.Count)" }) | Should -Be @('catalogs|Core|2')
            # The validator warns that the catalog id is not declared in the document, and refuses nothing.
            $Validation = Get-DupValidation -Inventory $Inv
            Get-DupValidationError -Validation $Validation | Should -BeNullOrEmpty
            $Validation.Valid | Should -BeTrue
            @($Validation.Errors | Where-Object { $_.Severity -eq 'Warning' } | ForEach-Object { $_.Message }) | Should -Be @(
                "Catalog 'eeee5555-0000-0000-0000-000000000001' is not declared in this document. It may already exist in the tenant."
                "Catalog 'eeee5555-0000-0000-0000-000000000002' is not declared in this document. It may already exist in the tenant."
            )
        }

        It 'counts catalog names over the catalogs read, so with -Catalog given as an id a package keeps its catalog''s name (BL-39, documented limit)' {
            # -Catalog given as an id reads that catalog alone, so the export cannot see a catalog elsewhere
            # in the tenant that carries the same name.
            $script:DupCatalogs = @([PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000001'; DisplayName = 'Core'; Description = 'one' })
            $script:DupAccessPackages = @{
                'eeee5555-0000-0000-0000-000000000001' = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'Sales'; Description = $null })
            }
            $Inv = Get-OERInventory -Include AccessPackages -Catalog 'eeee5555-0000-0000-0000-000000000001' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq 'eeee5555-0000-0000-0000-000000000001' }
            @($Inv.accessPackages | ForEach-Object { "$($_.catalog)|$($_.displayName)" }) | Should -Be @('Core|Sales')
            (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'writes the packages by catalog id when -Catalog given as a name reads two catalogs that carry it (BL-39)' {
            # -Catalog given as a name reads every catalog Microsoft Graph matches by that name (here both
            # spellings), and those are counted like any other list.
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000001'; DisplayName = 'Core'; Description = 'one' }
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000002'; DisplayName = 'core'; Description = 'two' }
            )
            $script:DupAccessPackages = @{
                'eeee5555-0000-0000-0000-000000000001' = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'Sales'; Description = $null })
                'eeee5555-0000-0000-0000-000000000002' = @([PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'Sales'; Description = $null })
            }
            $Inv = Get-OERInventory -Include AccessPackages -Catalog 'Core' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Core' }
            @($Inv.accessPackages | ForEach-Object { "$($_.catalog)|$($_.displayName)" }) | Should -Be @(
                'eeee5555-0000-0000-0000-000000000001|Sales'
                'eeee5555-0000-0000-0000-000000000002|Sales'
            )
            (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0
        }

        It 'names an unread collection of a catalog whose name another catalog carries by the catalog id, and of a unique catalog by its name (BL-39)' {
            # Two catalogs of one name must not read alike in the InventoryPartial error: each is named by the
            # reference its packages are written with.
            $script:DupCatalogs = @(
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000001'; DisplayName = 'Core'; Description = 'one' }
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000002'; DisplayName = 'core'; Description = 'two' }
                [PSCustomObject]@{ Id = 'eeee5555-0000-0000-0000-000000000003'; DisplayName = 'Solo Catalog'; Description = 'three' }
            )
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                param($Catalog)
                if ($Catalog -eq 'eeee5555-0000-0000-0000-000000000001') { throw 'resources refused (core one)' }
                @()
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                param($Catalog)
                if ($Catalog -in @('eeee5555-0000-0000-0000-000000000002', 'eeee5555-0000-0000-0000-000000000003')) { throw 'packages refused' }
                @()
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.accessPackages).Count | Should -Be 0
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly ('accessPackages/eeee5555-0000-0000-0000-000000000001/catalogResourceNames, ' +
                'accessPackages/eeee5555-0000-0000-0000-000000000002/packages, accessPackages/Solo Catalog/packages')
        }

        # BL-131 (Sprint 11 step 5): two assignment policies of ONE access package that carry one name,
        # without regard to letter case, are two entries the validator now refuses and the apply engine
        # cannot tell apart, so neither is written and the name is reported once, with its count. A package
        # with one catalog and one package is all the cases below need.
        Context 'assignment policies of one access package that share a name (BL-131)' {
            BeforeEach {
                $script:DupCatalogs = @([PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'Core'; Description = 'one' })
                $script:DupAccessPackages = @{
                    'cat-1' = @(
                        [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'Sales'; Description = $null }
                        [PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'Support'; Description = $null }
                    )
                }
            }

            It 'leaves out both policies of the shared name, reports the name with its count and writes the policy of another name' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'Default' -Id 'pol-2'
                        New-DupPolicy -Name 'Solo Policy' -Id 'pol-3'
                    )
                }
                $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
                # Reach proof: the policies of the package were read, and the package was written.
                Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
                $Sales = @($Inv.accessPackages | Where-Object displayName -ceq 'Sales')
                $Sales.Count | Should -Be 1
                @($Sales[0].assignmentPolicies | ForEach-Object { $_.displayName }) | Should -Be @('Solo Policy')
                $Partial = Get-DupPartial -Record @($InvErr)
                $Partial.Count | Should -Be 1
                [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/Sales/assignmentPolicies/Default'
                $Partial[0].Exception.Message | Should -Match 'Unread: accessPackages/Sales/assignmentPolicies/Default\. '
                $Partial[0].Exception.Message |
                    Should -BeLike '*Causes: 2 live objects share the name accessPackages/Sales/assignmentPolicies/Default (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.*'
                $Notice = @($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' })
                $Notice.Count | Should -Be 1
                $Names = @($Notice[0].MessageData.Names)
                $Names.Count | Should -Be 1
                $Names[0].Section | Should -BeExactly 'assignmentPolicies'
                $Names[0].Name | Should -BeExactly 'Sales/Default'
                $Names[0].Count | Should -Be 2
                Assert-DupDocumentValid -Inventory $Inv
            }

            It 'treats two policy names that differ only in letter case as shared, reporting the name as first read' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'DEFAULT' -Id 'pol-2'
                    )
                }
                $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
                Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
                $Sales = @($Inv.accessPackages | Where-Object displayName -ceq 'Sales')
                $Sales.Count | Should -Be 1
                $null -ne $Sales[0].PSObject.Properties['assignmentPolicies'] | Should -BeTrue
                @($Sales[0].assignmentPolicies).Count | Should -Be 0 -Because 'both spellings of the shared name are left out'
                $Partial = Get-DupPartial -Record @($InvErr)
                $Partial.Count | Should -Be 1
                [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/Sales/assignmentPolicies/Default'
                $Names = @((@($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' }))[0].MessageData.Names)
                $Names.Count | Should -Be 1
                $Names[0].Name | Should -BeExactly 'Sales/Default'
                $Names[0].Count | Should -Be 2
                Assert-DupDocumentValid -Inventory $Inv
            }

            It 'counts three policies of one name once, under the spelling of the first one read' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'DEFAULT' -Id 'pol-1'
                        New-DupPolicy -Name 'Default' -Id 'pol-2'
                        New-DupPolicy -Name 'default' -Id 'pol-3'
                    )
                }
                $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
                @(@($Inv.accessPackages | Where-Object displayName -ceq 'Sales')[0].assignmentPolicies).Count | Should -Be 0
                $Partial = Get-DupPartial -Record @($InvErr)
                $Partial.Count | Should -Be 1
                [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/Sales/assignmentPolicies/DEFAULT'
                $Partial[0].Exception.Message | Should -BeLike '*Causes: 3 live objects share the name accessPackages/Sales/assignmentPolicies/DEFAULT *'
                $Names = @((@($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' }))[0].MessageData.Names)
                $Names.Count | Should -Be 1
                $Names[0].Name | Should -BeExactly 'Sales/DEFAULT'
                $Names[0].Count | Should -Be 3
            }

            It 'writes every policy of a unique name as before and reports nothing' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'Premium' -Id 'pol-2'
                    )
                }
                $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
                Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
                $Sales = @($Inv.accessPackages | Where-Object displayName -ceq 'Sales')
                @($Sales[0].assignmentPolicies | ForEach-Object { $_.displayName }) | Should -Be @('Default', 'Premium')
                (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0
                @($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' }).Count | Should -Be 0
                Assert-DupDocumentValid -Inventory $Inv
            }

            It 'counts the policies of each package alone: a name two packages carry once each is not shared' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'Extra' -Id 'pol-2'
                    )
                    'ap-2' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-3'
                        New-DupPolicy -Name 'default' -Id 'pol-4'
                    )
                }
                $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
                Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 2 -Exactly
                $Sales = @($Inv.accessPackages | Where-Object displayName -ceq 'Sales')
                $Support = @($Inv.accessPackages | Where-Object displayName -ceq 'Support')
                @($Sales[0].assignmentPolicies | ForEach-Object { $_.displayName }) | Should -Be @('Default', 'Extra')
                @($Support[0].assignmentPolicies).Count | Should -Be 0
                $Partial = Get-DupPartial -Record @($InvErr)
                $Partial.Count | Should -Be 1
                [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/Support/assignmentPolicies/Default'
                $Names = @((@($Info | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' }))[0].MessageData.Names)
                $Names.Count | Should -Be 1
                $Names[0].Name | Should -BeExactly 'Support/Default'
                Assert-DupDocumentValid -Inventory $Inv
            }

            It 'states each colliding policy name once on the verbose stream' {
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'default' -Id 'pol-2'
                    )
                }
                $Err = $null
                $Stream = @(Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
                $Cause = 'Get-OERInventory: 2 live objects share the name accessPackages/Sales/assignmentPolicies/Default (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
                @($Said | Where-Object { $_ -ceq $Cause }).Count | Should -Be 1 -Because 'one cause line per colliding name, never one per policy'
                (Get-DupPartial -Record @($Err)).Count | Should -Be 1 -Because 'the run reached the partial the verbose line belongs to'
            }

            It 'hands a policy name over in the same information record as a name of another section, the policy first' {
                $script:DupCatalogs += [PSCustomObject]@{ Id = 'cat-2'; DisplayName = 'core'; Description = 'two' }
                $script:DupAccessPackages['cat-2'] = @()
                $script:DupAssignmentPolicies = @{
                    'ap-1' = @(
                        New-DupPolicy -Name 'Default' -Id 'pol-1'
                        New-DupPolicy -Name 'Default' -Id 'pol-2'
                    )
                }
                $Stream = @(Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -InformationAction Continue 6>&1)
                $Records = @($Stream | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' })
                $Records.Count | Should -Be 1 -Because 'one record carries every name, whatever its section'
                (@($Records[0].MessageData.Names) | ForEach-Object { "$($_.Section)|$($_.Name)|$($_.Count)" }) -join ';' |
                    Should -BeExactly 'assignmentPolicies|Sales/Default|2;catalogs|Core|2'
            }

            It 'names assignment policies of one access package in the help' {
                $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
                $Help | Should -Match ([regex]::Escape('access packages of one catalog, or assignment policies of one access package whose names match, without regard to letter case, are left out of the document -- all of them -- and each such name is reported through the InventoryPartial error'))
                $Help | Should -Match ([regex]::Escape('leaving an assignment policy out removes nothing either, because the apply engine never removes an assignment policy.'))
            }
        }

        It 'leaves out two access reviews that share a name without regard to letter case' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                foreach ($Name in 'Quarterly', 'quarterly', 'Solo Review') {
                    [PSCustomObject]@{
                        Id = "ar-$Name"; DisplayName = $Name; AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                        Reviewers = @(); Recurrence = $null; DurationInDays = 14
                    }
                }
            }
            $Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.accessReviews | ForEach-Object { $_.displayName }) | Should -Be @('Solo Review')
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessReviews/Quarterly'
            $Partial[0].Exception.Message | Should -Match 'share the name accessReviews/Quarterly'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'names two groups holding one role at one scope by their object ids, with principalType Group, and keeps a unique principal by name' {
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops'; $script:DupUser1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            # Sprint 11 step 6 (A18): the user keeps its name and carries principalType User, as every row
            # whose type maps to the enum does.
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "Reader|$($script:DupGrp1)|Group"
                "Reader|$($script:DupGrp2)|Group"
                'Reader|person1@example.com|User'
            )
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'puts principalType directly after principal, so the entry keeps its key order' {
            # A group whose name no other group carries keeps it until the collision pass meets the user
            # that carries the same string; the pass then inserts principalType for both. Two groups of
            # one name never reach the pass: the group rule names them by id first (BL-131, Task 3c).
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com'; $script:DupGrp1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One'
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'person1@example.com'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @(@($Inv.roleAssignments)[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
            @(@($Inv.roleAssignments)[1].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        }

        It 'counts two scope spellings that differ in letter case as one scope when it looks for a collision' {
            # Azure Resource Manager never returns a scope with a trailing '/', and the validator refuses
            # one in a document (A15), so the spellings here differ in letter case only. Two service
            # principals, which only the collision pass names by id (a group of a shared name is named by
            # id before it, BL-131).
            $script:DupNames = @{ $script:DupGrp1 = 'Automation'; $script:DupGrp2 = 'Automation' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation' -Scope $script:DupSub1.ToUpperInvariant()
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @($script:DupGrp1, $script:DupGrp2)
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'leaves two principals that share a name at DIFFERENT scopes alone' {
            # Service principals: the collision pass is per scope. A group of a shared name is named by
            # id whatever its scope (BL-131), which the Context on group principals holds.
            $script:DupNames = @{ $script:DupGrp1 = 'Automation'; $script:DupGrp2 = 'Automation' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation' -Scope "$($script:DupSub1)/resourceGroups/rg-one"
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments).Count | Should -Be 2
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @('Automation', 'Automation')
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'writes a role assignment at a resource whose name holds a space with its scope as Azure returns it, and the document validates (A13)' {
            # An Azure resource name can hold spaces between other characters (Microsoft Learn: a
            # Microsoft.Sql database, an Application Insights component). The validator accepts them since
            # A13 was narrowed, so an export that reads such an assignment stays appliable.
            $SqlScope = "$($script:DupSub1)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/sales data"
            $AppScope = "$($script:DupSub1)/resourceGroups/rg-one/providers/Microsoft.Insights/components/web  app 1"
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -Scope $SqlScope
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -Scope $AppScope
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.scope)|$($_.principal)" }) | Should -Be @(
                "$SqlScope|person1@example.com"
                "$AppScope|person1@example.com"
            )
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'leaves a role assignment at a resource whose name holds a ''#'' out, so the document validates, while the validator still refuses that scope with the way out (A13, A15)' {
            # The limit of the rule: a few resource types allow '#' in a name, but a '#' ends the path of the
            # request URI, so such a scope is refused and the message says to remove the entry. The export
            # therefore leaves the assignment out (the Context 'a role assignment at a scope no document can
            # declare is left out' holds the warning and the record), and the document it writes validates.
            $HashScope = "$($script:DupSub1)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1"
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -Scope $HashScope
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM -WarningAction SilentlyContinue
            @($Inv.roleAssignments | ForEach-Object { $_.scope }) | Should -Be @($script:DupSub1)
            Assert-DupDocumentValid -Inventory $Inv
            # A document that declares the scope is refused, with the way out.
            $Declared = [PSCustomObject]@{
                version         = '1.0'
                roleAssignments = @([PSCustomObject]@{ scope = $HashScope; role = 'Reader'; principal = 'person1@example.com'; principalType = 'User' })
            }
            $Validation = Get-DupValidation -Inventory $Declared
            Get-DupValidationError -Validation $Validation | Should -Be @(
                ("roleAssignments[0].scope: 'scope' at roleAssignments[0] must be written without a '?' or '#': either ends the path " +
                    "of the request, which would then name another scope than the one written. Got: '$HashScope'. A resource whose " +
                    'name holds one cannot be declared in a document; remove the entry.')
            )
            $Validation.Valid | Should -BeFalse
        }

        It 'names a user and a group that carry the same name by their object ids, each with its own principalType' {
            # A group can carry a user principal name as its display name, so the user and the group
            # export the same string. Users are moved to their ids too, or the pair would stay a duplicate.
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com'; $script:DupGrp1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One'
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'person1@example.com'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "$($script:DupUser1)|User"
                "$($script:DupGrp1)|Group"
            )
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'writes principalType Group for a ForeignGroup that has to be named by its object id' {
            $script:DupNames = @{ $script:DupGrp1 = 'Partners'; $script:DupGrp2 = 'Partners' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ForeignGroup' -PrincipalName 'Partners'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Partners'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "$($script:DupGrp1)|Group"
                "$($script:DupGrp2)|Group"
            )
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'names a ForeignGroup whose name only a user carries by its object id in the collision pass, with principalType Group' {
            # The ForeignGroup's name is unique among groups, so the group rule keeps it; it equals a user's
            # principal name at the same scope and role, so the collision pass moves both to their ids and
            # stamps the normalised type: Group for the ForeignGroup, never ForeignGroup.
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com'; $script:DupGrp1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One'
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ForeignGroup' -PrincipalName 'person1@example.com'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "$($script:DupUser1)|User"
                "$($script:DupGrp1)|Group"
            )
            @(@($Inv.roleAssignments)[1].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
            # Reach proof: the group rule read the index, which holds the ForeignGroup's name for it alone.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'names two service principals that share a name by their object ids and keeps the principalType they already carried in place' {
            $script:DupNames = @{ $script:DupGrp1 = 'Automation'; $script:DupGrp2 = 'Automation' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'ServicePrincipal' -PrincipalName 'Automation'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "$($script:DupGrp1)|ServicePrincipal"
                "$($script:DupGrp2)|ServicePrincipal"
            )
            @(@($Inv.roleAssignments)[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'repeats until nothing collides, since an object id can equal another principal name' {
            # The third service principal is called by the FIRST one's object id. Naming the first two by
            # id makes the third one collide with the first, so the third has to move on a second pass.
            # Service principals, since the group rule would name two groups of one name by id before the
            # pass (BL-131).
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops'; $script:DupGrp3 = $script:DupGrp1 }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'ServicePrincipal' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'ServicePrincipal' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp3 -PrincipalType 'ServicePrincipal' -PrincipalName 'Third'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @($script:DupGrp1, $script:DupGrp2, $script:DupGrp3)
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'names the full role definition id when two roles of one name still collide after the principal is an id' {
            # One user holds two different role definitions that carry the same display name. The
            # principal moves to its id first, which does not separate them, so the role moves too. The
            # directory names the second user too (Sprint 11 step 6: one it did not return would be read
            # among its deleted items and written by id).
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com'; $script:DupUser2 = 'User Two' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -RoleName 'Contoso Reader' -RoleDefinitionId $script:DupRoleDef1
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -RoleName 'Contoso Reader' -RoleDefinitionId $script:DupRoleDef2
                New-DupRoleAssignment -PrincipalId $script:DupUser2 -PrincipalType 'User' -PrincipalName 'User Two' -RoleName 'Contoso Reader' -RoleDefinitionId $script:DupRoleDef1
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)" }) | Should -Be @(
                "$($script:DupRoleDef1)|$($script:DupUser1)"
                "$($script:DupRoleDef2)|$($script:DupUser1)"
                'Contoso Reader|User Two'
            )
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'never writes an empty principal for a colliding row that carries no principal id' {
            # Defensive: Azure always returns a principal id, but a row without one cannot be named by
            # it. Its principal keeps the name it was read under, and the colliding rows fall back to
            # the full role definition id instead. Two such rows are a true duplicate that no spelling
            # can separate, so the loop ends with the pair left as it is.
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId '' -PrincipalType 'Group' -PrincipalName 'Orphan'
                New-DupRoleAssignment -PrincipalId '' -PrincipalType 'Group' -PrincipalName 'Orphan'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments).Count | Should -Be 2
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @('Orphan', 'Orphan') -Because 'an empty principal would be written as a declared value'
            @($Inv.roleAssignments | ForEach-Object { $_.role }) | Should -Be @($script:DupRoleDef1, $script:DupRoleDef1)
        }

        It 'never writes an empty role for a colliding row that carries no role definition id' {
            # The principal moves to its id on the first pass, which leaves two rows that differ in
            # nothing: the role cannot move to an id the row does not have, so it keeps its name.
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -RoleDefinitionId ''
                New-DupRoleAssignment -PrincipalId $script:DupUser1 -PrincipalType 'User' -PrincipalName 'User One' -RoleDefinitionId ''
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments).Count | Should -Be 2
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) |
                Should -Be @("Reader|$($script:DupUser1)|User", "Reader|$($script:DupUser1)|User") -Because 'an empty role would be written as a declared value'
        }

        It 'the validation helper reports a known duplicate, so a clean result is not vacuous' {
            $Doc = [PSCustomObject]@{
                version                = '1.0'
                groups                 = @([PSCustomObject]@{ displayName = 'Dup' }, [PSCustomObject]@{ displayName = 'dup' })
                roleAssignments        = @(
                    [PSCustomObject]@{ scope = $script:DupSub1; role = 'Reader'; principal = 'Ops' }
                    [PSCustomObject]@{ scope = $script:DupSub1.ToUpperInvariant(); role = 'reader'; principal = 'ops' }
                )
                roleManagementPolicies = @(
                    [PSCustomObject]@{ scope = $script:DupSub1; role = 'Reader' }
                    [PSCustomObject]@{ scope = $script:DupSub1.ToUpperInvariant(); role = 'reader' }
                )
            }
            $Validation = Get-DupValidation -Inventory $Doc
            $Validation.Valid | Should -BeFalse
            $Lines = @(Get-DupValidationError -Validation $Validation)
            $Lines.Count | Should -Be 3
            @($Lines | Where-Object { $_ -match '^groups\[1\]: ' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -match '^roleAssignments\[1\]: ' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -match '^roleManagementPolicies\[1\]: ' }).Count | Should -Be 1
        }

        It 'writes the collision cause to the verbose stream, as every other cause is' {
            $script:DupGroups = @(
                New-DupGroup -Name 'Dup' -Id $script:DupGrp1
                New-DupGroup -Name 'dup' -Id $script:DupGrp2
            )
            $Err = $null
            $Stream = @(Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
            $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            $Cause = 'Get-OERInventory: 2 live objects share the name groups/Dup (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
            @($Said | Where-Object { $_ -ceq $Cause }).Count | Should -Be 1 -Because 'one cause line per colliding name, never one per object'
            (Get-DupPartial -Record @($Err)).Count | Should -Be 1 -Because 'the run reached the partial the verbose line belongs to'
        }

        It 'names a collision in each of two sections but states the one collision cause once' {
            # The cause key is constant -- the Target is the whole unread entry, which the dedupe key
            # normalises away -- so it takes one slot of the cap however many sections collide.
            $script:DupGroups = @(
                New-DupGroup -Name 'Dup' -Id $script:DupGrp1
                New-DupGroup -Name 'dup' -Id $script:DupGrp2
            )
            $script:DupAdministrativeUnits = @(
                New-DupAdministrativeUnit -Name 'Team' -Id $script:DupGrp1
                New-DupAdministrativeUnit -Name 'TEAM' -Id $script:DupGrp2
            )
            $Inv = Get-OERInventory -Include Groups, AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            @($Inv.groups).Count | Should -Be 0
            @($Inv.administrativeUnits).Count | Should -Be 0
            $Partial = Get-DupPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groups/Dup, administrativeUnits/Team'
            $Message = $Partial[0].Exception.Message
            $Message | Should -Match 'Unread: groups/Dup, administrativeUnits/Team\. '
            @([regex]::Matches($Message, '2 live objects share the name')).Count | Should -Be 1 -Because 'the second collision has the same cause, so it is not stated again'
        }

        It 'writes a role policy that was read twice once' {
            $script:DupPolicies = @([PSCustomObject]@{ PolicyId = '/p/1'; Scope = $script:DupSub1; RoleName = 'Reader'; RoleDefinitionId = '/rd/1'; Approvers = @() })
            $Inv = Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -Role 'Reader', 'Reader' -IncludeARM -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 2 -Exactly
            @($Inv.roleManagementPolicies).Count | Should -Be 1 -Because 'the second read is the same policy, so dropping it loses nothing'
            @($Inv.roleManagementPolicies)[0].role | Should -BeExactly 'Reader'
            (Get-DupPartial -Record @($InvErr)).Count | Should -Be 0 -Because 'a policy read twice is no gap in the export'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'writes two role policies of different roles, and counts a scope in another letter case with a trailing slash as the same scope' {
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy {
                [PSCustomObject]@{ PolicyId = '/p/1'; Scope = $script:DupSub1; RoleName = 'Reader'; RoleDefinitionId = '/rd/1'; Approvers = @() }
                [PSCustomObject]@{ PolicyId = '/p/2'; Scope = $script:DupSub1; RoleName = 'Owner'; RoleDefinitionId = '/rd/2'; Approvers = @() }
                [PSCustomObject]@{ PolicyId = '/p/3'; Scope = ($script:DupSub1.ToUpperInvariant() + '/'); RoleName = 'reader'; RoleDefinitionId = '/rd/1'; Approvers = @() }
            }
            $Inv = Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -CommonRoles -IncludeARM
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly
            @($Inv.roleManagementPolicies | ForEach-Object { $_.role }) | Should -Be @('Reader', 'Owner')
            Assert-DupDocumentValid -Inventory $Inv
        }
    }

    Context 'shared names are counted over every group in the tenant (BL-131)' {
        # The groups section reads the security groups only, but the apply engine refuses a name any
        # live group answers to, so a group's name is counted over every group in the tenant too: the
        # index Get-OERGroupNameIndex reads with one listing. It is answered here by a mock that hands
        # back the index each case builds; the real helper is driven through the transport in the
        # Describe 'Get-OERInventory groups section, read through the real Get-OERGroup' below. No id
        # is version-4 shaped.
        BeforeAll {
            $script:NiSec1 = 'eeee1111-0000-0000-0000-000000000001'
            $script:NiSec2 = 'eeee1111-0000-0000-0000-000000000002'
            $script:NiSec3 = 'eeee1111-0000-0000-0000-000000000003'
            $script:NiM365a = 'eeee1111-0000-0000-0000-0000000000a1'
            $script:NiM365b = 'eeee1111-0000-0000-0000-0000000000a2'
            function script:New-NiGroup {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            function script:New-NiAdministrativeUnit {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; IsMemberManagementRestricted = $false
                    MembershipType = 'Assigned'; Visibility = $null; Members = @(); ScopedRoles = @()
                }
            }
            # An index the way Get-OERGroupNameIndex returns one: Read, the ids by name compared
            # without regard to letter case, and the message.
            function script:New-NiIndex {
                param([hashtable]$IdsByName = @{}, [bool]$Read = $true, [string]$Message)
                $Ids = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Name in $IdsByName.Keys) {
                    $Ids[$Name] = [System.Collections.Generic.List[string]]::new()
                    foreach ($Id in @($IdsByName[$Name])) { $Ids[$Name].Add($Id) }
                }
                $Index = [PSCustomObject]@{ Read = $Read; IdsByName = $Ids; Message = $(if ($Message) { $Message } else { $null }) }
                $Index.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupNameIndex')
                $Index
            }
            # The InventoryPartial records Get-OERInventory itself published.
            function script:Get-NiPartial {
                param([object[]]$Record)
                @($Record | Where-Object {
                        $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' -and
                        $_.FullyQualifiedErrorId -like 'InventoryPartial*'
                    })
            }
            # The information records tagged Omnicit.EntraRBAC.SharedName.
            function script:Get-NiNotice {
                param([object[]]$Record)
                @($Record | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' })
            }
        }

        BeforeEach {
            $script:NiGroups = @()
            $script:NiAdministrativeUnits = @()
            $script:NiIndex = New-NiIndex
            Mock -ModuleName $script:moduleName Get-OERGroup { $script:NiGroups }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit { $script:NiAdministrativeUnits }
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { $script:NiIndex }
        }

        It 'leaves out a security group whose name only a Microsoft 365 group outside the section shares, and names the count' {
            $script:NiGroups = @(
                New-NiGroup -Name 'Admins' -Id $script:NiSec1
                New-NiGroup -Name 'Solo' -Id $script:NiSec2
            )
            # Every group in the tenant: the two security groups and a Microsoft 365 group that carries
            # the first one's name in another letter case.
            $script:NiIndex = New-NiIndex -IdsByName @{ 'Admins' = @($script:NiSec1, $script:NiM365a); 'Solo' = @($script:NiSec2) }
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
            @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('Solo')
            $Partial = Get-NiPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groups/Admins'
            $Partial[0].Exception.Message | Should -BeLike '*Causes: 2 live objects share the name groups/Admins (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.*'
            # The index is read once, as a listing: no groups are handed to it.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('Group') }
            $Notice = Get-NiNotice -Record @($Info)
            $Notice.Count | Should -Be 1
            @($Notice[0].MessageData.Names).Count | Should -Be 1
            $Notice[0].MessageData.Names[0].Section | Should -BeExactly 'groups'
            $Notice[0].MessageData.Names[0].Name | Should -BeExactly 'Admins'
            $Notice[0].MessageData.Names[0].Count | Should -Be 2
        }

        It 'counts the larger of the listed groups and the index, so an index that lags behind the listing never lowers the count' {
            # Two listed groups of one name, and an index read before the second was created.
            $script:NiGroups = @(
                New-NiGroup -Name 'Dup' -Id $script:NiSec1
                New-NiGroup -Name 'dup' -Id $script:NiSec2
                New-NiGroup -Name 'Solo' -Id $script:NiSec3
            )
            $script:NiIndex = New-NiIndex -IdsByName @{ 'Dup' = @($script:NiSec1) }
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
            @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('Solo')
            $Partial = Get-NiPartial -Record @($InvErr)
            $Partial[0].Exception.Message | Should -BeLike '*Causes: 2 live objects share the name groups/Dup *'
            (Get-NiNotice -Record @($Info))[0].MessageData.Names[0].Count | Should -Be 2
        }

        It 'counts the index when it holds more of a name than the listing' {
            $script:NiGroups = @(
                New-NiGroup -Name 'Dup' -Id $script:NiSec1
                New-NiGroup -Name 'dup' -Id $script:NiSec2
            )
            $script:NiIndex = New-NiIndex -IdsByName @{ 'DUP' = @($script:NiSec1, $script:NiSec2, $script:NiM365a) }
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
            @($Inv.groups).Count | Should -Be 0
            (Get-NiPartial -Record @($InvErr))[0].Exception.Message | Should -BeLike '*Causes: 3 live objects share the name groups/Dup *'
            (Get-NiNotice -Record @($Info))[0].MessageData.Names[0].Count | Should -Be 3
        }

        It 'writes a group of a unique name as before, reports nothing and writes no information record' {
            # The index holds another name only, so a name it does not hold is counted over the listing.
            $script:NiGroups = @(New-NiGroup -Name 'Solo' -Id $script:NiSec1)
            $script:NiIndex = New-NiIndex -IdsByName @{ 'Other' = @($script:NiM365a) }
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info
            @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('Solo')
            (Get-NiPartial -Record @($InvErr)).Count | Should -Be 0
            (Get-NiNotice -Record @($Info)).Count | Should -Be 0
            # Reach proof: the index was read for the group.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'names groupNames unread with its cause when the index could not be read, and counts over the groups read' {
            # An index that was not read is never counted, whatever it holds: these ids would make
            # Admins shared.
            $script:NiGroups = @(
                New-NiGroup -Name 'Admins' -Id $script:NiSec1
                New-NiGroup -Name 'Dup' -Id $script:NiSec2
                New-NiGroup -Name 'dup' -Id $script:NiSec3
            )
            $script:NiIndex = New-NiIndex -Read $false -IdsByName @{ 'Admins' = @($script:NiSec1, $script:NiM365a) } `
                -Message 'Could not list every group to count the names groups share: Too many requests (429)'
            $Stream = @(Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable InvErr -InformationVariable Info -Verbose 4>&1)
            $Inv = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
            $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            @($Inv.groups | ForEach-Object { $_.displayName }) | Should -Be @('Admins')
            $Partial = Get-NiPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groupNames, groups/Dup'
            $Partial[0].Exception.Message | Should -BeLike '*Could not list every group to count the names groups share: Too many requests (429)*'
            $Partial[0].Exception.Message | Should -BeLike '*2 live objects share the name groups/Dup *'
            @($Said | Where-Object { $_ -ceq 'Get-OERInventory: Could not list every group to count the names groups share: Too many requests (429)' }).Count | Should -Be 1
            (Get-NiNotice -Record @($Info))[0].MessageData.Names.Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'hands every name it left out over in ONE information record, a group and an administrative unit, before the inventory' {
            $script:NiGroups = @(New-NiGroup -Name 'Admins' -Id $script:NiSec1)
            $script:NiIndex = New-NiIndex -IdsByName @{ 'Admins' = @($script:NiSec1, $script:NiM365a, $script:NiM365b) }
            $script:NiAdministrativeUnits = @(
                New-NiAdministrativeUnit -Name 'Team' -Id $script:NiSec2
                New-NiAdministrativeUnit -Name 'TEAM' -Id $script:NiSec3
            )
            $Stream = @(Get-OERInventory -Include Groups, AdministrativeUnits -ErrorAction SilentlyContinue -InformationAction Continue 6>&1)
            $Records = @($Stream | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
            $Notice = Get-NiNotice -Record $Records
            $Notice.Count | Should -Be 1
            $Notice[0].MessageData.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.SharedNameNotice'
            @($Notice[0].MessageData.PSObject.Properties.Name) | Should -Be @('Names')
            $Names = @($Notice[0].MessageData.Names)
            $Names.Count | Should -Be 2
            ($Names | ForEach-Object { "$($_.Section)|$($_.Name)|$($_.Count)" }) -join ';' | Should -BeExactly 'groups|Admins|3;administrativeUnits|Team|2'
            # The record precedes the inventory object it describes.
            $InventoryAt = [array]::IndexOf($Stream, @($Stream | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })[0])
            [array]::IndexOf($Stream, $Notice[0]) | Should -BeLessThan $InventoryAt
        }

        It 'does not read the index when <Case>' -ForEach @(
            @{ Case = 'the Groups section is not included'; Include = @('AdministrativeUnits'); Listed = $true }
            @{ Case = 'the Groups section read no group'; Include = @('Groups'); Listed = $false }
        ) {
            if ($Listed) { $script:NiGroups = @(New-NiGroup -Name 'Admins' -Id $script:NiSec1) }
            $script:NiAdministrativeUnits = @(New-NiAdministrativeUnit -Name 'Team' -Id $script:NiSec2)
            $Inv = Get-OERInventory -Include $Include -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Times 0
            (Get-NiPartial -Record @($InvErr)).Count | Should -Be 0
            # Reach proof: the sections included were read.
            if ($Include -contains 'Groups') { Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Exactly -Times 1 }
            else { @($Inv.administrativeUnits).Count | Should -Be 1 }
        }

        It 'states the index listing and the information record in the help' {
            $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
            $Help | Should -Match ([regex]::Escape("A group's name is counted among every group in the tenant -- one extra paged listing of every group's id and display name, made at most once per call, when the Groups section read at least one group or when a role assignment or directory role assignment names a group -- so a security group that shares its name with a Microsoft 365 group or a distribution group, which the default filter never reads, is left out too"))
            $Help | Should -Match ([regex]::Escape('When that listing fails, groupNames is reported unread through the InventoryPartial error, with its cause, and the names are counted among the groups read.'))
            $Help | Should -Match ([regex]::Escape('Each name left out is also handed over in one information record tagged Omnicit.EntraRBAC.SharedName, whose Names list carries the Section, Name and Count of each; under the default $InformationPreference the record is not displayed.'))
        }
    }

    Context 'a group named as a principal is written by its object id when another group carries its name (BL-131, Task 3c)' {
        # The apply engine refuses a group name more than one live group answers to, and a role
        # assignment's or a directory role assignment's group may share its name with a group the export
        # never lists (a Microsoft 365 group, or a group of another scope). So a group principal is
        # written by its display name only when the index of every group in the tenant holds that name for
        # this group alone (Get-OERGroupReference), and by its object id with principalType Group
        # otherwise. The tenant here: 'Ops' and 'OPS' (one name in two letter cases) and 'Solo'. No id
        # below is version-4 shaped.
        BeforeAll {
            $script:GpOps = 'eeee2222-0000-0000-0000-000000000001'
            $script:GpOpsOther = 'eeee2222-0000-0000-0000-000000000002'
            $script:GpSolo = 'eeee2222-0000-0000-0000-000000000003'
            $script:GpUser = 'dddd3333-0000-0000-0000-000000000001'
            $script:GpSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:GpDirRole = '11111111-1111-1111-1111-111111111111'
            $script:GpTenant = @{ $script:GpOps = 'Ops'; $script:GpOpsOther = 'OPS'; $script:GpSolo = 'Solo' }
            $script:GpNoteSuffix = '; every group principal is written by its object id.'
            function script:New-GpRa {
                param([string]$PrincipalId, [string]$PrincipalType, [string]$RoleName = 'Reader')
                [PSCustomObject]@{
                    Scope = $script:GpSub; RoleName = $RoleName
                    RoleDefinitionId = "$($script:GpSub)/providers/Microsoft.Authorization/roleDefinitions/bbbb1111-0000-0000-0000-000000000001"
                    PrincipalId = $PrincipalId; PrincipalType = $PrincipalType; PrincipalDisplayName = 'fixture'
                    RoleAssignmentId = "$($script:GpSub)/providers/Microsoft.Authorization/roleAssignments/$PrincipalId"
                }
            }
            # A direct, tenant-scope, permanent eligible row, the shape ConvertTo-OERDirectoryRoleAssignment emits.
            function script:New-GpDirRow {
                param([string]$PrincipalId, [string]$PrincipalType = 'Group', [string]$ScheduleId)
                $Out = [PSCustomObject][ordered]@{
                    ScheduleId = $ScheduleId; RoleDefinitionId = $script:GpDirRole; RoleName = 'Fixture Role A'
                    PrincipalId = $PrincipalId; PrincipalDisplayName = 'fixture'; PrincipalType = $PrincipalType
                    DirectoryScopeId = '/'; MemberType = 'Direct'; Status = 'Provisioned'
                    StartDateTime = '2026-01-01T00:00:00Z'; EndDateTime = $null; ExpirationType = 'noExpiration'; DurationDays = $null
                }
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.EligibleDirectoryRoleAssignment')
                $Out
            }
            function script:New-GpGroup {
                param([string]$Name, [string]$Id)
                [PSCustomObject]@{
                    Id = $Id; DisplayName = $Name; Description = $null; GroupType = 'Assigned'
                    IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            # The InventoryPartial records Get-OERInventory itself published.
            function script:Get-GpPartial {
                param([object[]]$Record)
                @($Record | Where-Object {
                        $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' -and
                        $_.FullyQualifiedErrorId -like 'InventoryPartial*'
                    })
            }
            # Stands in for Export-OERInventory (Sprint 11 step 6): makes the run context owned by its OWN
            # invocation, the way the export does, calls Get-OERInventory -Times times from inside itself, and
            # hands back the context and what the calls returned. Get-OERInventory runs one frame below this
            # function, so the Owner is a frame of its call stack.
            function script:Invoke-AsExport {
                [CmdletBinding()]
                param([object]$Index, [int]$Times = 1)
                # The shape Export-OERInventory makes (Sprint 11 step 6 added the three principal members).
                $Context = [PSCustomObject]@{
                    Owner                = $MyInvocation
                    GroupNameIndex       = $Index
                    PrincipalStatus      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    UnreadPrincipal      = [System.Collections.Generic.List[string]]::new()
                    UnreadPrincipalCause = [System.Collections.Generic.List[object]]::new()
                }
                & (Get-Module $script:moduleName) { param($Context) $script:_OERInventoryRunContext = $Context } $Context
                $Inventory = foreach ($Call in 1..$Times) { Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM }
                [PSCustomObject]@{ Context = $Context; Inventory = @($Inventory) }
            }
        }

        BeforeEach {
            $script:GpRas = @()
            $script:GpEligible = @()
            $script:GpGroups = @()
            $script:GpIndex = & $script:NewGroupNameIndexOf $script:GpTenant
            $script:GpNames = @{ $script:GpOps = 'Ops'; $script:GpOpsOther = 'OPS'; $script:GpSolo = 'Solo'; $script:GpUser = 'person1@example.com' }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:GpRas }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
                & $script:AnswerPrincipalLookup $Id $Detailed.IsPresent $script:GpNames
            }
            Mock -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment { $script:GpEligible }
            Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment { @() }
            Mock -ModuleName $script:moduleName Get-OERGroup { $script:GpGroups }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { $script:GpIndex }
            # Nothing here may reach the transport: the index is the mock above.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected transport call: $Uri" }
        }

        AfterEach {
            # A test below stands in for Export-OERInventory and sets its run context; it never outlives the test.
            InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
        }

        It 'writes a role assignment group whose name another group in the tenant carries by its object id, with principalType Group directly after principal' {
            # 'Ops' is the only group of that name the section reads: the other one is not assigned here,
            # so only the index of every group tells the two apart.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            $Ra = @($Inv.roleAssignments)
            $Ra.Count | Should -Be 1
            $Ra[0].principal | Should -BeExactly $script:GpOps
            $Ra[0].principalType | Should -BeExactly 'Group'
            @($Ra[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
            # Read as one listing of every group, not built from groups handed to it.
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('Group') }
            (Test-OERStructure -InputObject $Inv).Valid | Should -BeTrue
        }

        It 'writes a role assignment group whose name no other group carries by that name, with principalType Group (A18)' {
            # Sprint 11 step 6: principalType is written for every row whose type maps to the enum.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpSolo -PrincipalType 'Group')
            $Ra = @((Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).roleAssignments)
            $Ra[0].principal | Should -BeExactly 'Solo'
            $Ra[0].principalType | Should -BeExactly 'Group'
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'writes a ForeignGroup whose name another group carries by its object id, with principalType Group' {
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'ForeignGroup')
            $Ra = @((Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).roleAssignments)
            $Ra[0].principal | Should -BeExactly $script:GpOps
            $Ra[0].principalType | Should -BeExactly 'Group'
            @($Ra[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        }

        It 'leaves a user and a service principal as they were and does not read the index when no row names a group' {
            $script:GpNames['cccc3333-0000-0000-0000-000000000001'] = 'Ops'
            $script:GpRas = @(
                New-GpRa -PrincipalId $script:GpUser -PrincipalType 'User'
                New-GpRa -PrincipalId 'cccc3333-0000-0000-0000-000000000001' -PrincipalType 'ServicePrincipal' -RoleName 'Owner'
            )
            $script:GpEligible = @(New-GpDirRow -PrincipalId $script:GpUser -PrincipalType 'User' -ScheduleId 's-1')
            $Inv = Get-OERInventory -Include RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM
            # Reach proof: both sections wrote their rows, by name (each with its principalType, A18).
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @('person1@example.com|User', 'Ops|ServicePrincipal')
            @($Inv.directoryRoleAssignments).principal | Should -Be @('person1@example.com')
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Times 0
        }

        It 'leaves a group row that carries no object id as it was, with no error and no index read' {
            # Azure Resource Manager and Microsoft Graph always return one; the rule needs it, so a row
            # without it is named as before (the display name the read carried, or nothing).
            $Ra = New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group'
            $Ra.PrincipalId = $null
            $Ra.PrincipalDisplayName = 'Ops'
            $script:GpRas = @($Ra)
            $script:GpEligible = @(New-GpDirRow -PrincipalId '' -ScheduleId 's-1')
            $InvErr = $null
            $Inv = Get-OERInventory -Include RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM -ErrorVariable InvErr
            @($InvErr) | Should -BeNullOrEmpty
            # Reach proof: both rows were written. The ARM type maps to the enum, so principalType is
            # written (A18) although the principal keeps its name.
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @('Ops|Group')
            @($Inv.directoryRoleAssignments).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Times 0
        }

        It 'writes a group principal whose name <Case> by its object id, with no index read' -ForEach @(
            @{ Case = 'could not be read'; Blank = $false }
            @{ Case = 'was read blank'; Blank = $true }
        ) {
            # The name each section holds for the group is its object id (no name was read) or blank, and
            # Get-OERGroupReference returns the id for either whatever the index holds: the listing of every
            # group is not read for it. Sprint 11 step 6: in RoleAssignments a group the directory did not
            # return is written by its object id with principalStatus (from the deleted items read, answered
            # here), and needs no index either.
            Mock -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus { [PSCustomObject]@{ Id = $Id; Status = 'Deleted'; Read = $true; Cause = $null } }
            $Unnamed = 'eeee2222-0000-0000-0000-000000000009'
            if ($Blank) { $script:GpNames[$Unnamed] = ' ' }
            $Ra = New-GpRa -PrincipalId $Unnamed -PrincipalType 'Group'
            $Ra.PrincipalDisplayName = $null
            $script:GpRas = @($Ra)
            $script:GpEligible = @(New-GpDirRow -PrincipalId $Unnamed -ScheduleId 's-1')
            $InvErr = $null
            $Inv = Get-OERInventory -Include RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM -ErrorVariable InvErr -WarningAction SilentlyContinue
            @($InvErr) | Should -BeNullOrEmpty
            # Reach proof: the sections asked for the group's name and wrote the group by its object id with
            # principalType Group. Each section asks on its own (Sprint 11 step 6: the RoleAssignments section
            # keeps its own answers and leaves the shared cache of the other sections alone), so twice.
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @("$Unnamed|Group")
            @($Inv.directoryRoleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @("$Unnamed|Group")
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly -ParameterFilter { $Detailed }
            Should -Invoke -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus -Times $(if ($Blank) { 0 } else { 1 }) -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Times 0
        }

        It 'writes a directory role group whose name another group carries by its object id, and a unique one by its name' {
            $script:GpEligible = @(
                New-GpDirRow -PrincipalId $script:GpOps -ScheduleId 's-1'
                New-GpDirRow -PrincipalId $script:GpSolo -ScheduleId 's-2'
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            @($Inv.directoryRoleAssignments | Sort-Object -Property principal | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "$($script:GpOps)|Group"
                'Solo|Group'
            )
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            (Test-OERStructure -InputObject $Inv).Valid | Should -BeTrue
        }

        It 'reads the index once for the group principals of both sections, and says nothing about a failed read when it was read' {
            # The Task 2 once-only rule (Get-GroupNameIndexOnce) with a second caller: one listing per call.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $script:GpEligible = @(New-GpDirRow -PrincipalId $script:GpSolo -ScheduleId 's-1')
            $Stream = @(Get-OERInventory -Include RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM -Verbose 4>&1)
            $Inv = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
            $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            # Reach proof: each section named its group through the index.
            @($Inv.roleAssignments).principal | Should -Be @($script:GpOps)
            @($Inv.directoryRoleAssignments).principal | Should -Be @('Solo')
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            # The index was read, so no line says every group principal is written by its object id.
            @($Said | Where-Object { $_.EndsWith($script:GpNoteSuffix, [System.StringComparison]::Ordinal) }) | Should -BeNullOrEmpty
        }

        It 'builds the index once per call outside an export: a second call lists again, and no run context is left behind' {
            # Standalone, the index lives for one call (Sprint 11 step 6, R-1): nothing is kept between two
            # calls, so a change in the tenant between them is seen by the second.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $First = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            $Second = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            # Reach proof: both calls wrote the group principal through the index.
            @($First.roleAssignments).principal | Should -Be @($script:GpOps)
            @($Second.roleAssignments).principal | Should -Be @($script:GpOps)
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 2
            $null -eq (& (Get-Module $script:moduleName) { $script:_OERInventoryRunContext }) | Should -BeTrue
        }

        It 'reads the index a run context holds while its Owner is on the call stack, and builds none of its own' {
            # The index the context holds says 'Ops' belongs to one group only, while the mock above says
            # two: the name is written only when the context's index is the one read.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $ContextIndex = & $script:NewGroupNameIndexOf @{ $script:GpOps = 'Ops' }
            $Run = Invoke-AsExport -Index $ContextIndex
            $Ra = @($Run.Inventory[0].roleAssignments)
            $Ra.Count | Should -Be 1
            $Ra[0].principal | Should -BeExactly 'Ops'
            # principalType is written either way (A18); the name is the proof the context's index was read.
            $Ra[0].principalType | Should -BeExactly 'Group'
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Times 0
        }

        It 'builds the index once for a run context that holds none, stores it there, and shares it between calls' {
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $Run = Invoke-AsExport -Index $null -Times 2
            # Reach proof: both calls wrote the group principal through the index.
            @($Run.Inventory).Count | Should -Be 2
            @($Run.Inventory[0].roleAssignments).principal | Should -Be @($script:GpOps)
            @($Run.Inventory[1].roleAssignments).principal | Should -Be @($script:GpOps)
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('Group') }
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
            # The context holds the index the first call built (the mock's), and still does after the second.
            [object]::ReferenceEquals($Run.Context.GroupNameIndex, $script:GpIndex) | Should -BeTrue
        }

        It 'ignores a run context whose <Case> and lists for itself, as a standalone call does' -ForEach @(
            @{ Case = 'Owner is a command that has finished'; Owned = $true }
            @{ Case = 'Owner is missing'; Owned = $false }
        ) {
            # What an export that was stopped leaves behind. Its index says 'Ops' belongs to one group only,
            # while the mock above says two: the id is written only when the call listed for itself.
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $StaleIndex = & $script:NewGroupNameIndexOf @{ $script:GpOps = 'Ops' }
            & (Get-Module $script:moduleName) {
                param($StaleIndex, $Owned)
                function Get-FinishedInvocation { $MyInvocation }
                $Stale = [PSCustomObject]@{ GroupNameIndex = $StaleIndex }
                if ($Owned) { $Stale | Add-Member -NotePropertyName Owner -NotePropertyValue (Get-FinishedInvocation) }
                $script:_OERInventoryRunContext = $Stale
            } $StaleIndex $Owned
            $Ra = @((Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).roleAssignments)
            $Ra.Count | Should -Be 1
            $Ra[0].principal | Should -BeExactly $script:GpOps
            $Ra[0].principalType | Should -BeExactly 'Group'
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('Group') }
            # The call neither filled nor cleared what it ignored.
            [object]::ReferenceEquals((& (Get-Module $script:moduleName) { $script:_OERInventoryRunContext.GroupNameIndex }), $StaleIndex) | Should -BeTrue
        }

        It 'shares the one listing with the Groups section' {
            $script:GpGroups = @(New-GpGroup -Name 'Solo' -Id $script:GpSolo)
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpOps -PrincipalType 'Group')
            $script:GpEligible = @(New-GpDirRow -PrincipalId $script:GpSolo -ScheduleId 's-1')
            $Inv = Get-OERInventory -Include Groups, RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.groups).displayName | Should -Be @('Solo')
            @($Inv.roleAssignments).principal | Should -Be @($script:GpOps)
            @($Inv.directoryRoleAssignments).principal | Should -Be @('Solo')
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'writes every group principal by its object id when the index could not be read, says so once, and reports nothing unread' {
            $script:GpIndex = [PSCustomObject]@{ Read = $false; IdsByName = $null; Message = 'Could not list every group to count the names groups share: Too many requests (429)' }
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpSolo -PrincipalType 'Group')
            $script:GpEligible = @(New-GpDirRow -PrincipalId $script:GpSolo -ScheduleId 's-1')
            $Stream = @(Get-OERInventory -Include RoleAssignments, DirectoryRoleAssignments -Subscription 'Prod' -IncludeARM `
                    -ErrorAction SilentlyContinue -ErrorVariable InvErr -Verbose 4>&1)
            $Inv = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
            $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            # A unique name, written by id: the index that would say so was not read.
            @($Inv.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @("$($script:GpSolo)|Group")
            @($Inv.directoryRoleAssignments | ForEach-Object { "$($_.principal)|$($_.principalType)" }) | Should -Be @("$($script:GpSolo)|Group")
            $Note = "Get-OERInventory: Could not list every group to count the names groups share: Too many requests (429)$($script:GpNoteSuffix)"
            @($Said | Where-Object { $_ -ceq $Note }).Count | Should -Be 1
            (Get-GpPartial -Record @($InvErr)).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'names groupNames unread once for the Groups section, and still writes the group principals by id, when the shared index could not be read' {
            $script:GpIndex = [PSCustomObject]@{ Read = $false; IdsByName = $null; Message = 'Could not list every group to count the names groups share: denied' }
            $script:GpGroups = @(New-GpGroup -Name 'Solo' -Id $script:GpSolo)
            $script:GpRas = @(New-GpRa -PrincipalId $script:GpSolo -PrincipalType 'Group')
            $Stream = @(Get-OERInventory -Include Groups, RoleAssignments -Subscription 'Prod' -IncludeARM `
                    -ErrorAction SilentlyContinue -ErrorVariable InvErr -Verbose 4>&1)
            $Inv = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
            $Said = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            @($Inv.roleAssignments).principal | Should -Be @($script:GpSolo)
            $Partial = Get-GpPartial -Record @($InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groupNames'
            @($Said | Where-Object { $_ -ceq 'Get-OERInventory: Could not list every group to count the names groups share: denied' }).Count | Should -Be 1
            @($Said | Where-Object { $_ -ceq "Get-OERInventory: Could not list every group to count the names groups share: denied$($script:GpNoteSuffix)" }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
        }

        It 'states the rule for a group principal in the help' {
            $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
            $Help | Should -Match ([regex]::Escape('In RoleAssignments and DirectoryRoleAssignments, a group is written by its display name only when no other group in the tenant carries that name, compared without regard to letter case; otherwise, or when the listing of every group fails, it is written by its object id with principalType Group, which Invoke-OERStructure resolves verbatim.'))
        }
    }

    Context 'groups eligibility round-trip projection' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPimPolicy { $null }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipalName {
                @{ 'p-time' = 'time.bound@contoso.com'; 'p-perm' = 'perm@contoso.com'; 'p-owner' = 'owner@contoso.com' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroup {
                $G = [PSCustomObject]@{
                    Id                 = 'g-1'
                    DisplayName        = 'role_sec_test'
                    Description        = 'test group'
                    IsAssignableToRole = $true
                    GroupType          = 'Assigned'
                }
                $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName Owners -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @(
                    @{ principalId = 'p-time';  accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z' }
                    @{ principalId = 'p-perm';  accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = $null }
                    @{ principalId = 'p-owner'; accessId = 'owner';  startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-08T09:00:00Z' }
                ) -Force
                $G
            }
        }

        It 'emits durationDays for a time-bound eligibility' {
            $Inv = Get-OERInventory -Include Groups
            $E = @($Inv.Groups[0].eligibility) | Where-Object { $_.principal -eq 'time.bound@contoso.com' }
            $E.durationDays | Should -Be 30
        }

        It 'omits durationDays for a permanent eligibility' {
            $Inv = Get-OERInventory -Include Groups
            $E = @($Inv.Groups[0].eligibility) | Where-Object { $_.principal -eq 'perm@contoso.com' }
            $E.PSObject.Properties.Name | Should -Not -Contain 'durationDays'
        }

        It 'emits accessType member for a member eligibility' {
            $Inv = Get-OERInventory -Include Groups
            $E = @($Inv.Groups[0].eligibility) | Where-Object { $_.principal -eq 'time.bound@contoso.com' }
            $E.accessType | Should -Be 'member'
        }

        It 'emits accessType owner for an owner eligibility' {
            $Inv = Get-OERInventory -Include Groups
            $E = @($Inv.Groups[0].eligibility) | Where-Object { $_.principal -eq 'owner@contoso.com' }
            $E.accessType | Should -Be 'owner'
            $E.durationDays | Should -Be 7
        }

        It 'still emits the principal id when -IncludeId is used' {
            $Inv = Get-OERInventory -Include Groups -IncludeId
            $E = @($Inv.Groups[0].eligibility) | Where-Object { $_.principal -eq 'perm@contoso.com' }
            $E.id | Should -Be 'p-perm'
        }
    }

    Context 'round-trip: projected document validates' {
        It 'the example structure document validates as Valid' {
            $Path = Join-Path $PSScriptRoot '../../../docs/examples/example-structure.json'
            $Doc = Get-Content -Path $Path -Raw | ConvertFrom-Json
            $Result = InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } { param($Doc) Test-OERStructureSchema -Document $Doc }
            $Result.Valid | Should -BeTrue
        }

        It 'a projected AccessPackages inventory parses back through the validator as Valid' {
            Mock -ModuleName $script:moduleName Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT' } }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'd'; CatalogId = 'CAT' } }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { [PSCustomObject]@{ OriginId = 'orig-x'; DisplayName = 'role_sec_x' } }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x' } }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{ DisplayName = 'Default'; RequestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }; ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true }); DurationInDays = 30 }
            }
            $Inv = Get-OERInventory -Include AccessPackages
            $Doc = $Inv | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            # The validator keys are lower-case section names; the inventory uses PascalCase, so
            # assert the projected access package shape directly against the schema's accessPackages rule.
            $ApDoc = [PSCustomObject]@{
                version = '1.0'
                catalogs = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @($Doc.AccessPackages)
            }
            $Result = InModuleScope $script:moduleName -Parameters @{ D = $ApDoc } { param($D) Test-OERStructureSchema -Document $D }
            $Result.Valid | Should -BeTrue
        }

        It 'a projected AccessReviews inventory parses back through the validator as Valid' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Quarterly Access Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    DescriptionForAdmins = 'admins'; DescriptionForReviewers = 'reviewers'
                    DurationInDays = 14
                    Reviewers = @([PSCustomObject]@{ query = './manager' })
                    FallbackReviewers = @([PSCustomObject]@{ query = '/users/fb-9' })
                    Recurrence = [PSCustomObject]@{
                        pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                        range   = [PSCustomObject]@{ type = 'endDate'; startDate = '2026-01-01'; endDate = '2026-12-31' }
                    }
                    MailNotificationsEnabled     = $true
                    ReminderNotificationsEnabled = $true
                    JustificationRequired        = $true
                    RecommendationsEnabled       = $true
                    AutoApplyDecisionsEnabled    = $true
                    DefaultDecision               = 'Approve'
                }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage'
            }
            # BL-142: the apply engine's own lookups of the two names, each finding this object alone.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-1'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'ap-1'"
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews
            $Doc = $Inv | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $ArDoc = [PSCustomObject]@{
                version = '1.0'
                accessReviews = @($Doc.AccessReviews)
            }
            $Result = InModuleScope $script:moduleName -Parameters @{ D = $ArDoc } { param($D) Test-OERStructureSchema -Document $D }
            $Result.Valid | Should -BeTrue
            @($Result.Errors | Where-Object { $_.Severity -eq 'Error' }) | Should -HaveCount 0
        }

        It 'a projected AccessReviews inventory with a zero live instance duration validates as Valid' {
            # End-to-end guard for the live failure: an exported bundle was rejected by the schema.json
            # written beside it with "[Error] accessReviews[0].durationInDays: 'durationInDays' at
            # accessReviews[0] must be an integer between 1 and 365." Graph reports
            # settings.instanceDurationInDays as 0 for such a review, so this is the shape that broke.
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id = 'ar-1'; DisplayName = 'Zero Duration Review'
                    AccessPackageId = 'ap-1'; AssignmentPolicyId = 'pol-1'
                    DurationInDays = 0
                    Reviewers = @([PSCustomObject]@{ query = './manager' })
                    FallbackReviewers = @([PSCustomObject]@{ query = '/users/fb-9' })
                    Recurrence = $null
                }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "Unexpected Graph request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1?$expand=catalog'
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default' } } -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage'
            }
            # BL-142: the apply engine's own lookups of the two names, each finding this object alone.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-1'; displayName = 'AP-Sales' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'Default' }) } } -ParameterFilter {
                $Uri -eq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq 'ap-1'"
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            $Inv = Get-OERInventory -Include AccessReviews
            $Doc = $Inv | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $ArDoc = [PSCustomObject]@{
                version = '1.0'
                accessReviews = @($Doc.AccessReviews)
            }
            # Prove the section is populated before asserting Valid: an empty accessReviews array is
            # trivially valid, so the assertion below would pass with the projection producing nothing.
            @($ArDoc.accessReviews) | Should -HaveCount 1
            $Result = InModuleScope $script:moduleName -Parameters @{ D = $ArDoc } { param($D) Test-OERStructureSchema -Document $D }
            $Result.Valid | Should -BeTrue
            @($Result.Errors | Where-Object { $_.Severity -eq 'Error' }) | Should -HaveCount 0
        }

        It 'never projects a group administrativeUnit that the administrativeUnits section fails to reciprocate (issue #59)' {
            # Get-OERInventory does not currently read or project groups[].administrativeUnit at all --
            # New-OERGroup's -AdministrativeUnit is a create-only Graph write with no corresponding read
            # (Sync-OERStructureGroup.ps1), and Get-OERGroup never asks Graph for it. This pins that
            # measured fact against the REAL projection rather than a hand-written expectation of it,
            # and doubles as a regression guard: routing the combined groups+administrativeUnits
            # document through the module's own offline validator (Test-OERStructureSchema) means a
            # later change that starts projecting administrativeUnit without also naming the group in
            # the matching unit's members trips the same Warning issue #59 describes, since the
            # validator matches by displayName and the administrativeUnits[] member projection below
            # emits an object id or UPN ahead of displayName -- a fixture-only expectation would miss
            # that mismatch entirely.
            Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-au-1'; DisplayName = 'Group-AU-Pin'; Description = $null
                    GroupType = 'Assigned'; IsAssignableToRole = $false
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-pin-1'; DisplayName = 'AU-Pin'; Description = $null
                    IsMemberManagementRestricted = $false
                    Members = @(); ScopedRoles = @()
                }
            }
            $Inv = Get-OERInventory -Include Groups, AdministrativeUnits
            $Doc = $Inv | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            @($Doc.Groups).Count | Should -Be 1
            $Doc.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'administrativeUnit'

            $CombinedDoc = [PSCustomObject]@{
                version              = '1.0'
                groups               = @($Doc.Groups)
                administrativeUnits  = @($Doc.AdministrativeUnits)
            }
            $Result = InModuleScope $script:moduleName -Parameters @{ D = $CombinedDoc } { param($D) Test-OERStructureSchema -Document $D }
            $Result.Valid | Should -BeTrue
            @($Result.Errors | Where-Object { $_.Path -like '*.administrativeUnit' }) | Should -HaveCount 0
        }
    }

    Context 'pimPolicy projection is not gated on activationMaxHours' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                $G = [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'g'; Description = $null
                    IsAssignableToRole = $true; GroupType = 'Assigned'
                }
                $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName Owners -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @() -Force
                $G
            }
        }

        It 'emits the member block when only permanence and duration are customized' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $false
                        EligibleDurationDays      = 180
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Member = $Inv.Groups[0].pimPolicy.member
            # Should -BeFalse also passes on $null, so it cannot discriminate this case: the key is
            # emitted only under an "if ($null -ne ...)" guard in the projection. If that guard ever
            # regressed to a truthiness test the key would be dropped for every $false policy and
            # -BeFalse would stay green. Assert presence AND the strict value.
            $Member.PSObject.Properties.Name | Should -Contain 'allowPermanentEligibility'
            $Member.allowPermanentEligibility | Should -Be $false
            $Inv.Groups[0].pimPolicy.member.eligibleDurationDays | Should -Be 180
            $Inv.Groups[0].pimPolicy.member.PSObject.Properties.Name | Should -Not -Contain 'activationMaxHours'
        }

        It 'emits the member block when only notification recipients are customized' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @('person17@example.com'); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].pimPolicy.member.notifications.eligibleAlert | Should -Be @('person17@example.com')
        }

        It 'omits pimPolicy entirely when the policy carries no meaningful field' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                [PSCustomObject]@{
                    ActivationMaxHours        = $null
                    AuthenticationContextId   = $null
                    ActivationEnabledRules    = @()
                    AllowPermanentEligibility = $null
                    EligibleDurationDays      = $null
                    AllowPermanentActive      = $null
                    ActiveDurationDays        = $null
                    ActiveEnabledRules        = @()
                    Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }
    }

    Context 'pimPolicy approval projection' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                $G = [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'g'; Description = $null
                    IsAssignableToRole = $true; GroupType = 'Assigned'
                }
                $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName Owners -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @() -Force
                $G
            }
        }

        It 'projects requireApproval true and approvers as object ids when approval is required' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        RequireApproval           = $true
                        Approvers                 = @(
                            [PSCustomObject]@{ DisplayName = 'Anna'; Id = 'usr-1'; UserType = 'User' }
                            [PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' }
                        )
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Member = $Inv.Groups[0].pimPolicy.member
            $Member.requireApproval | Should -Be $true
            @($Member.approvers.users)  | Should -Be @('usr-1')
            @($Member.approvers.groups) | Should -Be @('grp-1')
        }

        It 'projects requireApproval false and omits approvers, even when the live policy still carries them' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        RequireApproval           = $false
                        Approvers                 = @(
                            [PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' }
                        )
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Member = $Inv.Groups[0].pimPolicy.member
            $Member.requireApproval | Should -Be $false
            $Member.PSObject.Properties.Name | Should -Not -Contain 'approvers'
        }

        It 'omits requireApproval and approvers when the policy has no approval rule at all' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = 8
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        RequireApproval           = $null
                        Approvers                 = @()
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Member = $Inv.Groups[0].pimPolicy.member
            $Member.PSObject.Properties.Name | Should -Not -Contain 'requireApproval'
            $Member.PSObject.Properties.Name | Should -Not -Contain 'approvers'
        }

        It 'produces a groups pimPolicy approval projection that passes its own offline validator' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        RequireApproval           = $true
                        Approvers                 = @(
                            [PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' }
                        )
                        Notifications             = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() }
                    }
                } else { $null }
            }
            $Inventory = Get-OERInventory -Include Groups
            $Doc = [PSCustomObject]@{ version = '1.0'; groups = @($Inventory.Groups) }
            InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }
    }

    Context 'a genuinely empty PIM enablement list is still exportable' {
        # ConvertTo-OERGroupPimPolicy wraps ActivationEnabledRules/ActiveEnabledRules with a
        # null-filter, so a rule the tenant never configured and a rule that is genuinely empty
        # BOTH read back as @() -- these mocks distinguish the two cases the same way the
        # production code does: by whether the raw Rules collection carries the canonical
        # enablement rule id.
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                $G = [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'g'; Description = $null
                    IsAssignableToRole = $true; GroupType = 'Assigned'
                }
                $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName Owners -NotePropertyValue @() -Force
                $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @() -Force
                $G
            }
        }

        It 'emits an explicit empty activationEnablement when the live policy has none' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = 8
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{
                            EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @()
                        }
                        Rules = @(
                            [PSCustomObject]@{
                                id = 'Enablement_EndUser_Assignment'; enabledRules = @()
                            }
                        )
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].pimPolicy.member.PSObject.Properties.Name |
                Should -Contain 'activationEnablement'
            @($Inv.Groups[0].pimPolicy.member.activationEnablement).Count | Should -Be 0
        }

        It 'emits an explicit empty activeEnablement when the live policy has none' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = $null
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = 30
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{
                            EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @()
                        }
                        Rules = @(
                            [PSCustomObject]@{
                                id = 'Enablement_Admin_Assignment'; enabledRules = @()
                            }
                        )
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].pimPolicy.member.PSObject.Properties.Name |
                Should -Contain 'activeEnablement'
            @($Inv.Groups[0].pimPolicy.member.activeEnablement).Count | Should -Be 0
        }

        It 'omits activationEnablement when the corresponding rule was never part of the policy' {
            # Mutation guard: Rules is non-empty (an unrelated rule id is present), so a
            # broader-than-intended predicate like "Rules.Count -gt 0" would wrongly emit here.
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = 8
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{
                            EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @()
                        }
                        Rules = @(
                            [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment' }
                        )
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].pimPolicy.member.PSObject.Properties.Name |
                Should -Not -Contain 'activationEnablement'
        }

        It 'still omits pimPolicy entirely when an all-empty policy carries no rule at all' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                [PSCustomObject]@{
                    ActivationMaxHours        = $null
                    AuthenticationContextId   = $null
                    ActivationEnabledRules    = @()
                    AllowPermanentEligibility = $null
                    EligibleDurationDays      = $null
                    AllowPermanentActive      = $null
                    ActiveDurationDays        = $null
                    ActiveEnabledRules        = @()
                    Notifications             = [PSCustomObject]@{
                        EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @()
                    }
                    Rules = @()
                }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].PSObject.Properties.Name | Should -Not -Contain 'pimPolicy'
        }

        It 'does not emit empty notification alert lists even when their rule ids are present' {
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
                param($AccessType)
                if ($AccessType -eq 'member') {
                    [PSCustomObject]@{
                        ActivationMaxHours        = 8
                        AuthenticationContextId   = $null
                        ActivationEnabledRules    = @()
                        AllowPermanentEligibility = $null
                        EligibleDurationDays      = $null
                        AllowPermanentActive      = $null
                        ActiveDurationDays        = $null
                        ActiveEnabledRules        = @()
                        Notifications             = [PSCustomObject]@{
                            EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @()
                        }
                        Rules = @(
                            [PSCustomObject]@{
                                id = 'Enablement_EndUser_Assignment'; enabledRules = @()
                            },
                            [PSCustomObject]@{
                                id = 'Notification_Admin_Admin_Eligibility'
                                notificationRecipients = @()
                            }
                        )
                    }
                } else { $null }
            }
            $Inv = Get-OERInventory -Include Groups
            $Inv.Groups[0].pimPolicy.member.PSObject.Properties.Name |
                Should -Not -Contain 'notifications'
        }
    }

    Context 'shipped help does not overclaim what the projection covers' {
        # Prose is not self-guarding: assert against the shipped comment-based help text itself
        # (not a live -Include call), so a future edit that reintroduces either overclaim fails
        # here instead of drifting silently again.
        It 'does not claim the roleManagementPolicies projection is the full settable surface' {
            $SrcPath = Join-Path $script:sourceRoot 'Public/Get-OERInventory.ps1'
            $Text = Get-Content -Raw -Path $SrcPath
            $Text | Should -Not -Match 'full settable Azure PIM policy surface'
            $Text | Should -Match 'notification rule'
        }

        It 'names the eligible and active assignment exclusion in the description' {
            $SrcPath = Join-Path $script:sourceRoot 'Public/Get-OERInventory.ps1'
            $Text = Get-Content -Raw -Path $SrcPath
            $Text | Should -Match 'eligible and active'
        }
    }

    Context 'a collection the export failed to read is never stated as a fact' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
        }

        It 'projects members as an explicit null when the member read failed' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                # Members deliberately absent: Get-OERGroup omits it when the read failed.
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue
            $Group = @($Inv.groups)[0]
            # Positive identity FIRST: $null.PSObject.Properties.Name -contains 'members' is $false,
            # so a presence assertion alone would also pass had the cmdlet emitted no group at all.
            $Group | Should -Not -BeNullOrEmpty
            $Group.displayName | Should -Be 'role_sec_team'
            $Group.PSObject.Properties.Name -contains 'members' |
                Should -BeTrue -Because 'an OMITTED members key still reconciles and still prunes; only an explicit null means hands off'
            $null -eq $Group.members |
                Should -BeTrue -Because 'explicit null is the apply schema documented hands-off signal for members'
        }

        It 'projects members as an array when the member read succeeded and the group is empty' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups
            $Group = @($Inv.groups)[0]
            $Group.displayName | Should -Be 'role_sec_team'
            $null -ne $Group.members |
                Should -BeTrue -Because 'a successful read of an empty group is a declared empty set, not unknown'
            @($Group.members).Count | Should -Be 0
        }

        It 'raises InventoryPartial naming the group and the key when a collection was not read' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            # -ErrorVariable also accumulates Pester's own mock-invocation bookkeeping records, so
            # restrict to what Get-OERInventory itself published (the idiom in Get-OERGroup.Tests.ps1).
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Partial = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1
            $Partial[0].Exception.Message | Should -Match 'role_sec_team'
            $Partial[0].Exception.Message | Should -Match 'members'
            # TargetObject is what Export-OERInventory folds into IncompleteReads: an empty one there
            # would make a count-only assertion downstream pass while naming nothing.
            [string]$Partial[0].TargetObject | Should -Match 'groups/role_sec_team/members'
        }

        It 'writes no InventoryPartial error when every requested collection was read' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue
            @($Inv.groups).Count | Should -Be 1
            @($InvErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'omits owners rather than nulling it when the owner read failed' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue
            $Group = @($Inv.groups)[0]
            $Group | Should -Not -BeNullOrEmpty
            $Group.displayName | Should -Be 'role_sec_team'
            $Group.PSObject.Properties.Name -contains 'owners' |
                Should -BeFalse -Because 'an omitted owners key is already never reconciled or pruned, so omission is the hands-off form here'
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message |
                Should -Match 'groups/role_sec_team/owners'
        }

        It 'omits eligibility rather than nulling it when the eligibility read failed' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(); Owners = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue
            $Group = @($Inv.groups)[0]
            $Group | Should -Not -BeNullOrEmpty
            $Group.displayName | Should -Be 'role_sec_team'
            $Group.PSObject.Properties.Name -contains 'eligibility' |
                Should -BeFalse -Because 'an omitted eligibility key is already never reconciled or pruned'
            # No principal lookup is issued for a collection that was never read.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0 -Exactly
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message |
                Should -Match 'groups/role_sec_team/eligibility'
        }

        It 'keeps enumerating the remaining groups when one group has a failed collection read' {
            # Pester does not propagate the caller's -ErrorAction into a mock body the way a real
            # cmdlet's own $ErrorActionPreference would, so the mock honours it explicitly. Without
            # that the test is INERT: a bare -ErrorAction Continue inside the mock never terminates,
            # so reverting the call site to -ErrorAction Stop would still pass. With it, Stop makes
            # the write terminate and the two groups after it are never emitted -- which is exactly
            # the data loss the SilentlyContinue + -ErrorVariable shape exists to prevent.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                param($Filter, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $ErrorAction)
                $Ea = if ($ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'members read failed' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_first'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-2'; DisplayName = 'role_sec_second'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(@{ userPrincipalName = 'person20@example.com' }); Owners = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            @($Inv.groups).Count |
                Should -Be 2 -Because 'a per-group collection failure must cost one collection, not every remaining group'
            @($Inv.groups)[1].displayName | Should -Be 'role_sec_second'
            @($Inv.groups)[1].members | Should -Contain 'person20@example.com'
        }

        It 'does not re-report a per-collection read failure as an opaque section warning' {
            # -ErrorAction Continue here (NOT the honouring shape above) so the record genuinely
            # reaches the caller's -ErrorVariable and the id filter is actually exercised. The
            # positive control below proves this mock shape does produce a warning when the id is
            # not one of the per-collection ones -- without that pair, an empty $Warned would prove
            # nothing more than that no record was captured at all.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                Write-Error -Message 'members read failed' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_first'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            @($Warned | Where-Object { $_ -match 'Could not read groups' }).Count |
                Should -Be 0 -Because 'the projection accounts for it by name; a section warning naming no object would be a second, vaguer report'
        }

        It 'carries the underlying failure cause into InventoryPartial and onto the verbose stream' {
            # The triples say WHICH collection is missing; only the transport message says WHY, and
            # -ErrorAction SilentlyContinue keeps the originating record off the caller's stream. A
            # 429 means "retry the export"; a 403 means "grant a scope". Losing that distinction is
            # not a lossless consolidation -- for issue #76 the throttle IS the case.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                Write-Error -Message "Could not read members for group 'g-1': Too many requests (429)." `
                    -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            $Verbose = @(Get-OERInventory -Include Groups -Verbose -ErrorVariable InvErr -ErrorAction SilentlyContinue 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            @($Verbose | Where-Object { $_.Message -match '429' }).Count |
                Should -BeGreaterThan 0 -Because 'the full transport reason must survive somewhere addressable'

            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Partial = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            @($Partial).Count | Should -Be 1
            $Partial[0].Exception.Message | Should -Match 'Causes: '
            $Partial[0].Exception.Message |
                Should -Match '429' -Because 'a 429 tells the operator to retry where a 403 tells them to grant a scope'
            # The triples themselves are unchanged: Export-OERInventory folds TargetObject into
            # IncompleteReads verbatim, and existing tests pin that to the bare triple form.
            [string]$Partial[0].TargetObject | Should -Be 'groups/role_sec_team/members'
        }

        It 'deduplicates a cause that repeats across every affected group' {
            # A throttle produces the identical message for every group in the page. Repeating it
            # once per group would bury the signal in its own noise.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                Write-Error -Message 'Too many requests (429).' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -ErrorAction Continue
                Write-Error -Message 'Too many requests (429).' -ErrorId 'GroupMemberReadFailed' `
                    -Category LimitsExceeded -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_one'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
                [PSCustomObject]@{
                    Id = 'g-2'; DisplayName = 'role_sec_two'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            # Both groups are still listed as unread -- deduplication is on the CAUSE only.
            $Msg | Should -Match 'groups/role_sec_one/members'
            $Msg | Should -Match 'groups/role_sec_two/members'
            $Causes = ($Msg -split 'Causes: ')[1]
            @([regex]::Matches($Causes, [regex]::Escape('Too many requests (429).'))).Count |
                Should -Be 1 -Because 'one throttle reason repeated per group would bury the signal'
        }

        It 'names the cause for an administrative unit collection read failure too' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                Write-Error -Message "Could not read scoped roles for unit 'au-1': Forbidden (403)." `
                    -ErrorId 'AdministrativeUnitScopedRoleReadFailed' -Category LimitsExceeded -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                }
            }

            Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Msg | Should -Match 'Causes: '
            $Msg | Should -Match '403'
        }

        It 'appends no Causes clause when the unread collection carried no reported cause' {
            # Absence of a cause must not produce a dangling "Causes: ." -- the group here simply
            # has no Members property and no error record was written at all.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            Get-OERInventory -Include Groups -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Msg | Should -Match 'groups/role_sec_team/members'
            $Msg | Should -Not -Match 'Causes: '
        }

        It 'still warns at section level for a group read error that is not a per-collection failure' {
            # Positive control for the test above: same mock shape, different error id.
            #
            # The record is BUILT with its FullyQualifiedErrorId rather than written with
            # -ErrorId, and that is load-bearing. Get-OERInventory now warns only for a record
            # Get-OERGroup itself published, told apart by the cmdlet name PowerShell writes into
            # the FullyQualifiedErrorId when a cmdlet calls WriteError. A Pester mock body is
            # invoked as a scriptblock, which appends no name at all, so a plain
            # -ErrorId 'TooManyRequests' here would produce a shape the LIVE cmdlet can never
            # produce and would test the stray path by accident. Write-Error -ErrorRecord carries
            # the id through verbatim, so this is the real published shape.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('throttled'), 'TooManyRequests,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)) -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_first'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Members = @(); Owners = @(); PimEligibility = @()
                }
            }

            Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            @($Warned | Where-Object { $_ -match 'Could not read groups' }).Count | Should -Be 1
        }

        It 'projects administrative unit members and scopedRoles as explicit null when their reads failed' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                }
            }

            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue
            $Au = @($Inv.administrativeUnits)[0]
            $Au | Should -Not -BeNullOrEmpty
            $Au.displayName | Should -Be 'AU-One'
            $Au.PSObject.Properties.Name -contains 'members' | Should -BeTrue
            $null -eq $Au.members |
                Should -BeTrue -Because 'an omitted administrativeUnits members key still reconciles and still prunes'
            $Au.PSObject.Properties.Name -contains 'scopedRoles' | Should -BeTrue
            $null -eq $Au.scopedRoles |
                Should -BeTrue -Because 'an omitted scopedRoles key still reconciles and still prunes'
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Msg | Should -Match 'administrativeUnits/AU-One/members'
            $Msg | Should -Match 'administrativeUnits/AU-One/scopedRoles'
        }

        It 'keeps enumerating the remaining administrative units when one has a failed collection read' {
            # Same honouring shape as the group test: under -ErrorAction Stop the write terminates
            # and the units after it are lost, which is what the AU read must no longer do.
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                param($IncludeMembers, $IncludeScopedRoles, $ErrorAction)
                $Ea = if ($ErrorAction) { $ErrorAction } else { 'Continue' }
                Write-Error -Message 'scoped role read failed' -ErrorId 'AdministrativeUnitScopedRoleReadFailed' `
                    -Category LimitsExceeded -ErrorAction $Ea
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                }
                [PSCustomObject]@{
                    Id = 'au-2'; DisplayName = 'AU-Two'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @(); ScopedRoles = @()
                }
            }

            $Inv = Get-OERInventory -Include AdministrativeUnits -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            @($Inv.administrativeUnits).Count |
                Should -Be 2 -Because 'a per-unit collection failure must cost one collection, not every remaining unit'
            @($Inv.administrativeUnits)[1].displayName | Should -Be 'AU-Two'
            $null -ne @($Inv.administrativeUnits)[1].scopedRoles | Should -BeTrue
        }

        It 'does not re-report a per-collection unit read failure as an opaque section warning' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                Write-Error -Message 'member read failed' -ErrorId 'AdministrativeUnitMemberReadFailed' `
                    -Category LimitsExceeded -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    ScopedRoles = @()
                }
            }

            Get-OERInventory -Include AdministrativeUnits -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            @($Warned | Where-Object { $_ -match 'Could not read administrative units' }).Count | Should -Be 0
        }

        It 'still warns at section level for a unit read error that is not a per-collection failure' {
            # Positive control for the test above. The record is built with its
            # FullyQualifiedErrorId for the same reason as the group positive control above -- see
            # that comment; a mock body appends no cmdlet name, and the publisher is what decides
            # whether this warns.
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('throttled'), 'TooManyRequests,Get-OERAdministrativeUnit',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)) -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @(); ScopedRoles = @()
                }
            }

            Get-OERInventory -Include AdministrativeUnits -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            @($Warned | Where-Object { $_ -match 'Could not read administrative units' }).Count | Should -Be 1
        }

        It 'routes the SDK strays behind one failed read to verbose instead of section warnings' {
            # THE LIVE SHAPE THIS EXISTS FOR. -ErrorVariable is populated by the ENGINE and also
            # collects records raised inside NESTED calls, even ones an inner catch swallowed. One
            # failed scoped-role read therefore handed the caller nine records, eight of them the
            # Graph SDK's own. Warning on each produced 56 section-level warnings for seven units on
            # a live tenant and buried the finding that mattered. Mocking the RAW SDK call rather
            # than Invoke-OERGraphRequest is what makes those strays real here: a mock of the wrapper
            # produces exactly one tidy record and could never reproduce this.
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
                if ($Uri -like '*scopedRoleMembers*') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'),
                        'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        [System.Net.Http.HttpRequestMessage]::new(
                            [System.Net.Http.HttpMethod]::Get, "https://graph.microsoft.com/$Uri"))
                }
                if ($Uri -like '*/members*') { return @{ value = @() } }
                @{ value = @(
                        @{ id = 'au-1'; displayName = 'AU-One' }
                        @{ id = 'au-2'; displayName = 'AU-Two' }
                    )
                }
            }

            $Verbose = @(Get-OERInventory -Include AdministrativeUnits -Verbose `
                    -WarningVariable Warned -WarningAction SilentlyContinue `
                    -ErrorVariable InvErr -ErrorAction SilentlyContinue 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

            # NON-VACUITY FIRST, and deliberately anchored on something the fix does NOT touch: the
            # partial-inventory finding proves both reads really failed and the loop really ran. A
            # bare "no warning was written" assertion would otherwise also pass on a run where
            # nothing happened at all.
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Msg | Should -Match 'administrativeUnits/AU-One/scopedRoles'
            $Msg | Should -Match 'administrativeUnits/AU-Two/scopedRoles'

            # The property under test.
            @($Warned | Where-Object { $_ -match 'Could not read administrative units' }).Count |
                Should -Be 0 -Because 'a Graph SDK record the module never published is not a section-level finding'
            # And the strays were routed, not dropped: they stay reachable through -Verbose.
            @($Verbose | Where-Object { $_.Message -match 'ignoring a foreign error record' }).Count |
                Should -BeGreaterThan 0 -Because 'a stray is still evidence, so it must be diagnosable rather than discarded'
        }

        It 'deduplicates two causes that differ only by the object id embedded in the message' {
            # Get-OERAdministrativeUnit interpolates the failing unit's id into its message, so the
            # old whole-message dedupe could never fire -- seven units failing for ONE identical
            # reason produced seven causes on a live tenant. The dedupe key now normalises that id
            # away, taken from the record's own TargetObject so no id-shaped pattern is needed.
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                Write-Error -Message 'Could not read scoped roles for administrative unit au-1: Insufficient privileges to complete the operation.' `
                    -ErrorId 'AdministrativeUnitScopedRoleReadFailed' -Category PermissionDenied `
                    -TargetObject 'au-1' -ErrorAction Continue
                Write-Error -Message 'Could not read scoped roles for administrative unit au-2: Insufficient privileges to complete the operation.' `
                    -ErrorId 'AdministrativeUnitScopedRoleReadFailed' -Category PermissionDenied `
                    -TargetObject 'au-2' -ErrorAction Continue
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                }
                [PSCustomObject]@{
                    Id = 'au-2'; DisplayName = 'AU-Two'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                }
            }

            Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            # Both units are still listed as unread -- deduplication is on the CAUSE only.
            $Msg | Should -Match 'administrativeUnits/AU-One/scopedRoles'
            $Msg | Should -Match 'administrativeUnits/AU-Two/scopedRoles'
            $Causes = ($Msg -split 'Causes: ')[1]
            $Causes | Should -Not -BeNullOrEmpty -Because 'a missing Causes clause would make the count below vacuous'
            @([regex]::Matches($Causes, 'Could not read scoped roles for administrative unit')).Count |
                Should -Be 1 -Because 'one reason repeated once per unit must be stated once, not once per unit'
        }

        It 'caps the Causes clause and states how many distinct causes it dropped' {
            # Deduplication alone does not bound the clause: a large tenant can fail in many genuinely
            # different ways, and an error message thousands of causes long is unreadable. The cap is
            # ONE PER CAUSE SHAPE the module can emit -- twenty-three of them since an entry that has
            # no name began to be written as null (group members, group owners, group PIM
            # eligibility, group PIM-in-use criterion, group PIM policy, AU members, AU scoped roles,
            # directory role eligibility schedules, directory role assignment schedules, directory
            # role policies, access package resource role bindings, catalog resources, the catalog
            # resource-name map, the catalog list, a catalog's package list, an access package's
            # assignment policies, an access review's access package name, an access review's
            # assignment policy name, objects not written because two of them share a name, the group
            # list, the administrative unit list, the access review list, an entry written as null
            # because it has no name) -- and the remainder is counted rather than silently lost.
            # Raise the numbers here and $UnreadCauseCap (in Format-OERUnreadCauseClause, where the
            # cap lives) together, or a whole shape can be crowded out of the clause purely by the
            # order the sections run in.
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [CmdletBinding()] param([switch]$IncludeMembers, [switch]$IncludeScopedRoles)
                foreach ($N in 1..24) {
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Could not read scoped roles for administrative unit au-${N}: reason-${N}."),
                            'AdministrativeUnitScopedRoleReadFailed',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, "au-$N"))
                }
                foreach ($N in 1..24) {
                    [PSCustomObject]@{
                        Id = "au-$N"; DisplayName = "AU-$N"; Description = $null
                        IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                        Members = @()
                    }
                }
            }

            Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue | Out-Null
            $Published = @($InvErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
            }
            $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Causes = ($Msg -split 'Causes: ')[1]
            $Causes | Should -Not -BeNullOrEmpty
            @([regex]::Matches($Causes, 'reason-')).Count |
                Should -Be 23 -Because 'the clause names at most twenty-three distinct causes, one per cause shape'
            $Causes | Should -Match 'plus 1 more distinct cause\(s\)'
            # All twenty-four units are still named as unread -- the cap applies to the causes only.
            foreach ($N in 1..24) { $Msg | Should -Match "administrativeUnits/AU-$N/scopedRoles" }
        }

        It 'produces a members value the apply engine reads as hands-off, not as an empty declared set' {
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                    GroupType = 'Assigned'; Description = $null; MailNickname = $null
                    Owners = @(); PimEligibility = @()
                }
            }

            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue
            $Group = @($Inv.groups)[0]
            $Group.displayName | Should -Be 'role_sec_team'

            InModuleScope $script:moduleName -Parameters @{ Node = $Group } {
                param($Node)
                # This is the exact gate source/Private/Sync-OERStructureGroup.ps1 uses to decide
                # whether the prune/Extra loop runs. True here means -Prune leaves the live
                # membership alone.
                Test-OERDeclaredNull -Node $Node -Name 'members' |
                    Should -BeTrue -Because 'this is the gate -Prune consults; false here means it deletes every live member'
                Test-OERDeclaredProperty -Node $Node -Name 'members' |
                    Should -BeFalse -Because 'an unread membership must not be an add-list either'
            }
        }

        It 'produces an administrative unit scopedRoles value the prune gate reads as hands-off' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                }
            }

            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue
            $Au = @($Inv.administrativeUnits)[0]
            $Au.displayName | Should -Be 'AU-One'

            InModuleScope $script:moduleName -Parameters @{ Node = $Au } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'scopedRoles' |
                    Should -BeTrue -Because 'this is the gate -Prune consults for scoped roles'
                Test-OERDeclaredNull -Node $Node -Name 'members' | Should -BeTrue
                Test-OERDeclaredProperty -Node $Node -Name 'scopedRoles' | Should -BeFalse
            }
        }
    }

    Context 'a section whose list could not be read at all is partial, not an empty tenant' {
        # BL-05 / decision A9. A top-level section is never null: a LIST read that failed leaves the
        # section as [], byte for byte what a tenant with none produces, so the InventoryPartial error
        # is the only thing that tells the two apart. A failed list read takes one of two shapes, and
        # each is a row below for every section: a record the reader PUBLISHED, and a terminating throw
        # out of the reader.
        #
        # The published record is BUILT with its FullyQualifiedErrorId and written with
        # Write-Error -ErrorRecord, which is load-bearing: the section only counts a record the reader
        # itself published, told apart by the cmdlet name in the id, and a mock body appends no name
        # (see the comment at 'still warns at section level for a group read error that is not a
        # per-collection failure'). A plain -ErrorId would test the foreign-record path by accident.
        #
        # The throw mocks declare the reader's whole parameter list: a mock with a bare param() and
        # CmdletBinding refuses the parameters the section passes, and the failure under test would
        # then be a binding error carrying a different message.
        BeforeAll {
            $script:GroupListPublished = {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
            }
            $script:GroupListThrown = {
                [CmdletBinding()] param($Filter, [switch]$IncludeMembers, [switch]$IncludePimEligibility, [switch]$IncludeOwners)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('throttled'), 'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
            }
            $script:AuListPublished = {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERAdministrativeUnit',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
            }
            $script:AuListThrown = {
                [CmdletBinding()] param([switch]$IncludeMembers, [switch]$IncludeScopedRoles)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('throttled'), 'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
            }
            $script:ArListPublished = {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied,Get-OERAccessReviewDefinition',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
            }
            $script:ArListThrown = {
                [CmdletBinding()] param([switch]$All, $DisplayName)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('throttled'), 'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
            }

            # One read, with every stream the assertions below look at captured, and -ErrorAction
            # pinned: the section's InventoryPartial is non-terminating, and under a global Stop it
            # would otherwise end the read before the object under test was returned.
            function Get-SectionRead {
                param([string[]]$Include)
                $Stream = @(Get-OERInventory -Include $Include -Verbose -ErrorVariable InvErr -ErrorAction SilentlyContinue `
                        -WarningVariable Warned -WarningAction SilentlyContinue 4>&1)
                [PSCustomObject]@{
                    Inventory = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })[0]
                    Verbose   = @($Stream | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
                    Partial   = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -eq 'InventoryPartial,Get-OERInventory' })
                    Warned    = @($Warned)
                }
            }

            # What every row below proves: the section is still emitted, as an empty array that is not
            # null; exactly ONE InventoryPartial came out of the read; its TargetObject names the
            # section by its own name, once; its message carries the reader's own failure message; and
            # the section warning that already existed is still written, once.
            function Assert-SectionUnread {
                param($Read, [string]$Section, [string]$CauseText, [string]$WarningText)
                $Read.Inventory | Should -Not -BeNullOrEmpty
                $Read.Inventory.PSObject.Properties.Name | Should -Contain $Section
                $null -ne $Read.Inventory.$Section | Should -BeTrue -Because 'a top-level section is never null'
                @($Read.Inventory.$Section).Count | Should -Be 0
                $Read.Partial.Count | Should -Be 1
                $Targets = @(([string]$Read.Partial[0].TargetObject) -split ', ')
                @($Targets | Where-Object { $_ -eq $Section }).Count | Should -Be 1 -Because 'the section is named once, by its own name'
                $Read.Partial[0].Exception.Message | Should -Match ([regex]::Escape($CauseText))
                @($Read.Warned | Where-Object { "$_" -like "*$WarningText*" }).Count |
                    Should -Be 1 -Because 'the section warning is unchanged: the section is counted unread as well'
            }
        }
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
        }

        It 'reports the group list as unread when Get-OERGroup publishes a failure and returns nothing' {
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:GroupListPublished
            $Read = Get-SectionRead -Include Groups
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section groups -CauseText 'Could not read groups: Insufficient privileges' -WarningText 'Could not read groups'
            # Every cause is written to the verbose stream as it is seen, so one the cap drops is still reachable.
            @($Read.Verbose | Where-Object { $_.Message -like '*Get-OERInventory: Could not read groups: Insufficient privileges*' }).Count |
                Should -BeGreaterThan 0
        }

        It 'reports the group list as unread when Get-OERGroup throws' {
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:GroupListThrown
            $Read = Get-SectionRead -Include Groups
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section groups -CauseText 'Could not read groups: throttled' -WarningText 'Could not read groups'
        }

        It 'reports the groups section as unread, with one warning and the cause, when the group reader stops on <Label>' -ForEach @(
            @{ Label = 'a throw'; Stop = { throw [System.Exception]::new('stop') }; Expected = 'stop' }
            # A statement-terminating error is not a throw: without a try around the reader's call it
            # would end the call and leave $GroupRead empty, which reads as zero groups. The message is
            # the runtime's own, so the test asks the runtime for it rather than spelling it.
            @{ Label = 'a statement-terminating error'; Stop = { $null.NoSuchMethod() }; Expected = $(try { $null.NoSuchMethod() } catch { [string]$PSItem.Exception.Message }) }
        ) {
            # The error is raised inside the real group reader, by a helper it calls for every group
            # outside any catch of its own (Test-OERGroupOnPremisesSynced), so the read stops part-way.
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith {
                [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_team'; GroupType = 'Assigned'; IsAssignableToRole = $false; SecurityEnabled = $true; Members = @(); Owners = @(); PimEligibility = @() }
            }
            Mock -ModuleName $script:moduleName Test-OERGroupOnPremisesSynced -MockWith $Stop
            $Read = Get-SectionRead -Include Groups
            # Reach proofs: the reader was reached, and the helper inside it ran (once, then the read stopped).
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupOnPremisesSynced -Times 1 -Exactly
            $Expected | Should -Not -BeNullOrEmpty
            Assert-SectionUnread -Read $Read -Section groups -CauseText "Could not read groups: $Expected" -WarningText "Could not read groups: $Expected"
            @($Read.Verbose | Where-Object { $_.Message -like "*Get-OERInventory: Could not read groups: $Expected*" }).Count |
                Should -BeGreaterThan 0
        }

        It 'reports the administrative unit list as unread when Get-OERAdministrativeUnit publishes a failure and returns nothing' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit -MockWith $script:AuListPublished
            $Read = Get-SectionRead -Include AdministrativeUnits
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section administrativeUnits -CauseText 'Could not read administrative units: Insufficient privileges' -WarningText 'Could not read administrative units'
        }

        It 'reports the administrative unit list as unread when Get-OERAdministrativeUnit throws' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit -MockWith $script:AuListThrown
            $Read = Get-SectionRead -Include AdministrativeUnits
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section administrativeUnits -CauseText 'Could not read administrative units: throttled' -WarningText 'Could not read administrative units'
        }

        It 'reports the access review list as unread when Get-OERAccessReviewDefinition publishes a failure and returns nothing' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition -MockWith $script:ArListPublished
            $Read = Get-SectionRead -Include AccessReviews
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section accessReviews -CauseText 'Could not read access reviews: Insufficient privileges' -WarningText 'Could not read access reviews'
        }

        It 'reports the access review list as unread when Get-OERAccessReviewDefinition throws' {
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition -MockWith $script:ArListThrown
            $Read = Get-SectionRead -Include AccessReviews
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
            Assert-SectionUnread -Read $Read -Section accessReviews -CauseText 'Could not read access reviews: throttled' -WarningText 'Could not read access reviews'
        }

        It 'names all three sections in ONE InventoryPartial when each of the three lists fails in the same run' {
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:GroupListPublished
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit -MockWith $script:AuListPublished
            Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition -MockWith $script:ArListPublished
            $Read = Get-SectionRead -Include Groups, AdministrativeUnits, AccessReviews
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessReviewDefinition -Times 1 -Exactly
            $Read.Partial.Count | Should -Be 1
            $Targets = @(([string]$Read.Partial[0].TargetObject) -split ', ')
            $Targets.Count | Should -Be 3
            @($Targets | Sort-Object) | Should -Be @('accessReviews', 'administrativeUnits', 'groups')
            foreach ($Section in 'groups', 'administrativeUnits', 'accessReviews') {
                @($Read.Inventory.$Section).Count | Should -Be 0
            }
        }

        It 'names a section once however many records its failed list read published' {
            # A throttled or refused list can publish one record per page, so the same section is seen
            # twice here; the key is the section name and is added once, while each DISTINCT cause is
            # still kept. Without the Contains guard the TargetObject would read 'groups, groups'.
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('first page refused'), 'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('second page refused'), 'Authorization_RequestDenied,Get-OERGroup',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)) -ErrorAction Continue
            }
            $Read = Get-SectionRead -Include Groups
            Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
            @($Read.Warned | Where-Object { "$_" -like '*Could not read groups*' }).Count |
                Should -Be 2 -Because 'both published records were reached, so the section was seen twice'
            $Read.Partial.Count | Should -Be 1
            @(([string]$Read.Partial[0].TargetObject) -split ', ') | Should -Be @('groups')
            $Read.Partial[0].Exception.Message | Should -Match 'Could not read groups: first page refused'
            $Read.Partial[0].Exception.Message | Should -Match 'Could not read groups: second page refused'
        }

        It 'does not call the <Section> list unread when its read ends in <NotFoundId>, which is an answer' -ForEach @(
            @{ Section = 'groups'; Include = 'Groups'; Command = 'Get-OERGroup'; NotFoundId = 'GroupNotFound' }
            @{ Section = 'administrativeUnits'; Include = 'AdministrativeUnits'; Command = 'Get-OERAdministrativeUnit'; NotFoundId = 'AdministrativeUnitNotFound' }
            @{ Section = 'accessReviews'; Include = 'AccessReviews'; Command = 'Get-OERAccessReviewDefinition'; NotFoundId = 'AccessReviewDefinitionNotFound' }
        ) {
            # A published not-found record: the reader answered "nothing matches", which is a fact about
            # the tenant, so the empty section stays a plain [] with no partial and no warning.
            $Body = [scriptblock]::Create(
                "Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('nothing matches'), '$NotFoundId,$Command', [System.Management.Automation.ErrorCategory]::ObjectNotFound, `$null)) -ErrorAction Continue")
            Mock -ModuleName $script:moduleName $Command -MockWith $Body
            $Read = Get-SectionRead -Include $Include
            Should -Invoke -ModuleName $script:moduleName $Command -Times 1 -Exactly
            $null -ne $Read.Inventory.$Section | Should -BeTrue
            @($Read.Inventory.$Section).Count | Should -Be 0
            $Read.Partial.Count | Should -Be 0
            @($Read.Warned).Count | Should -Be 0
        }

        It 'does not call the <Section> list unread for a record its reader did not publish' -ForEach @(
            @{ Section = 'groups'; Include = 'Groups'; Command = 'Get-OERGroup' }
            @{ Section = 'administrativeUnits'; Include = 'AdministrativeUnits'; Command = 'Get-OERAdministrativeUnit' }
            @{ Section = 'accessReviews'; Include = 'AccessReviews'; Command = 'Get-OERAccessReviewDefinition' }
        ) {
            # A stray: -ErrorVariable also collects records raised inside nested calls, and none of them
            # carries the reader's name. It is routed to verbose, never counted as a failed read of the
            # section -- the reach proof is the verbose line that names it.
            $Body = {
                Write-Error -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('a nested call failed and was swallowed'), 'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)) -ErrorAction Continue
            }
            Mock -ModuleName $script:moduleName $Command -MockWith $Body
            $Read = Get-SectionRead -Include $Include
            Should -Invoke -ModuleName $script:moduleName $Command -Times 1 -Exactly
            @($Read.Verbose | Where-Object { $_.Message -like '*ignoring a foreign error record*a nested call failed and was swallowed*' }).Count |
                Should -Be 1 -Because 'the stray was reached and routed to verbose'
            $null -ne $Read.Inventory.$Section | Should -BeTrue
            $Read.Partial.Count | Should -Be 0
            @($Read.Warned).Count | Should -Be 0
        }

        It 'says in the InventoryPartial message that a section named alone is an empty array and not an empty tenant' {
            Mock -ModuleName $script:moduleName Get-OERGroup -MockWith $script:GroupListPublished
            $Read = Get-SectionRead -Include Groups
            $Read.Partial.Count | Should -Be 1
            # The lead-in is true of a section named alone too, which is neither a members nor a
            # nameless collection: the list could not be read at all.
            $Read.Partial[0].Exception.Message |
                Should -BeLike '*PARTIAL: 1 collection(s) or object(s) could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are not stated as facts in the document*'
            $Read.Partial[0].Exception.Message |
                Should -BeLike '*Unread: groups. A section reported here by its name alone could not be read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles, resources or resourceRoles key reported here is an explicit null*'
        }
    }

    Context 'an unread access package or catalog collection is never stated as a fact' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; CatalogId = 'cat-1' }
            }
            # The catalog resource carries the real display name keyed by OriginId; the binding's scope
            # display name (ResourceDisplayName) is only the scope label (e.g. 'Root').
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            # The group's current name, looked up by originId, equals the recorded one here.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_x' }; $M }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    DisplayName    = 'Default'
                    RequestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                    ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                    DurationInDays = 30
                }
            }
        }

        It 'projects resourceRoles as an explicit null when the binding read failed (non-terminating)' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [CmdletBinding()] param($AccessPackage)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' |
                Should -BeTrue -Because 'an omitted resourceRoles key still reconciles and prunes; only an explicit null is hands-off'
            $null -eq $Ap.PSObject.Properties['resourceRoles'].Value | Should -BeTrue -Because 'an unread binding set is unknown, not empty'
            InModuleScope $script:moduleName -Parameters @{ Node = $Ap } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'resourceRoles' | Should -BeTrue -Because 'this is the gate the handler consults before its prune pass'
            }
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/AP-Sales/resourceRoles'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
        }

        It 'projects resourceRoles as an explicit null when the binding read threw' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { throw 'Too many requests.' }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' | Should -BeTrue
            $null -eq $Ap.PSObject.Properties['resourceRoles'].Value | Should -BeTrue
            [string](@(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].TargetObject) |
                Should -Match 'accessPackages/AP-Sales/resourceRoles'
        }

        It 'tells the operator in the InventoryPartial message that a resourceRoles key it names is an explicit null' {
            # The message used to name only members and scopedRoles, so an operator reading the
            # partial for an unread binding set was told nothing about the key it was looking at.
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { throw 'Too many requests.' }
            $null = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Msg = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
            $Msg | Should -Match 'accessPackages/AP-Sales/resourceRoles'
            $Msg | Should -Match 'members, scopedRoles, resources or resourceRoles key reported here is an explicit null'
            $Msg | Should -Match 'reads as leave untouched; do not hand-edit it to an empty array'
        }

        It 'projects an empty resourceRoles array and no partial when the read succeeded with no bindings' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' | Should -BeTrue
            $null -ne $Ap.PSObject.Properties['resourceRoles'].Value | Should -BeTrue -Because 'a successful read of no bindings is a declared empty set'
            @($Ap.PSObject.Properties['resourceRoles'].Value).Count | Should -Be 0
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'treats a successful read that left a swallowed record behind as read' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                try { Write-Error -Message 'Too many requests.' -ErrorId 'TooManyRequests' -ErrorAction Stop } catch { $null = $_ }
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            @($Inv.AccessPackages)[0].resourceRoles[0].role | Should -Be 'Member'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'still emits the document before the partial stops the call under a global ErrorActionPreference of Stop' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [CmdletBinding()] param($AccessPackage)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            # No -ErrorAction on the call: any -ErrorAction sets the preference in Get-OERInventory's
            # own scope and shadows the global Stop for everything beneath it, so the test would pass
            # whether or not the global value is survived. -OutVariable keeps what was emitted before
            # the trailing InventoryPartial becomes terminating under Stop.
            $Caught = $null
            $Saved = $global:ErrorActionPreference
            try {
                $global:ErrorActionPreference = 'Stop'
                try {
                    $null = Get-OERInventory -Include AccessPackages -OutVariable Emitted
                } catch { $Caught = $PSItem }
            } finally { $global:ErrorActionPreference = $Saved }
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            @($Emitted).Count | Should -Be 1 -Because 'the document is written before the partial stops the call, not lost to a termination mid-section'
            $Ap = @(@($Emitted)[0].AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' | Should -BeTrue
            $null -eq $Ap.PSObject.Properties['resourceRoles'].Value | Should -BeTrue
            $Caught | Should -Not -BeNullOrEmpty -Because 'under a global Stop the trailing InventoryPartial is the one termination'
            $Caught.FullyQualifiedErrorId | Should -BeLike 'InventoryPartial*'
            [string]$Caught.TargetObject | Should -Match 'accessPackages/AP-Sales/resourceRoles'
        }

        It 'projects catalog resources as an explicit null when the resource read failed (non-terminating)' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [CmdletBinding()] param($Catalog)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            $Cat.displayName | Should -Be 'CAT-IT-Core'
            $Cat.PSObject.Properties.Name -contains 'resources' |
                Should -BeTrue -Because 'an omitted resources key still reconciles and prunes; only an explicit null is hands-off'
            $null -eq $Cat.PSObject.Properties['resources'].Value | Should -BeTrue -Because 'an unread resource set is unknown, not empty'
            InModuleScope $script:moduleName -Parameters @{ Node = $Cat } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'resources' | Should -BeTrue -Because 'this is the gate the handler consults before its prune pass'
            }
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'catalogs/CAT-IT-Core/resources'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
            $Partial[0].Exception.Message | Should -Match "Could not read a catalog's resources"
        }

        It 'projects catalog resources as an explicit null when the resource read threw' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { throw 'Too many requests.' }
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            $Cat.displayName | Should -Be 'CAT-IT-Core'
            $Cat.PSObject.Properties.Name -contains 'resources' | Should -BeTrue
            $null -eq $Cat.PSObject.Properties['resources'].Value | Should -BeTrue
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'catalogs/CAT-IT-Core/resources'
        }

        It 'projects an empty resources array and no partial when the read succeeded with no resources' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { }
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            $Cat.displayName | Should -Be 'CAT-IT-Core'
            $Cat.PSObject.Properties.Name -contains 'resources' | Should -BeTrue
            $null -ne $Cat.PSObject.Properties['resources'].Value | Should -BeTrue -Because 'a successful read of no resources is a declared empty set'
            @($Cat.PSObject.Properties['resources'].Value).Count | Should -Be 0
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'does not cache an empty name map for the access package section when the catalog read failed' {
            # The catalog read fails on its FIRST call only; the access package section reads the
            # same catalog again and succeeds. The group has been renamed since the catalog recorded
            # 'role_sec_x', and the directory now answers 'role_sec_new'. A failed catalog read that
            # still primed the shared name map with an empty one would make the package section skip
            # the lookup and write the stale recorded name.
            $script:CatResCalls = 0
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [CmdletBinding()] param($Catalog)
                $script:CatResCalls++
                if ($script:CatResCalls -eq 1) {
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                } else {
                    [PSCustomObject]@{ OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_new' }; $M }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 2 -Exactly
            $script:CatResCalls | Should -Be 2 -Because 'the catalog section and the access package section each read the catalog once'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            $Cat.PSObject.Properties.Name -contains 'resources' | Should -BeTrue
            $null -eq $Cat.PSObject.Properties['resources'].Value | Should -BeTrue
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.resourceRoles[0].resource | Should -Be 'role_sec_new' -Because 'a failed catalog read must not leave an empty name map cached for the package section'
        }

        It 'reports an unread resource-name map and writes a group binding under its object id (non-terminating)' {
            # The map only NAMES bindings. With it unread, the only name left for a group binding is
            # the one the catalog RECORDED, which Graph keeps after a rename and which can name
            # ANOTHER group today, so the binding is written under the group's object id instead.
            # The fixture is what the real reader returns for a group: the scope label is NOT in
            # ResourceDisplayName, which holds the recorded name, and OriginSystem is AadGroup.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [CmdletBinding()] param($Catalog)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'role_sec_x'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -Be '11111111-1111-1111-1111-111111111111' -Because 'the recorded name can name another group after a rename; the object id cannot'
            $Ap.resourceRoles[0].role | Should -Be 'Member'
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/CAT-IT-Core/catalogResourceNames'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
            $Partial[0].Exception.Message | Should -Match "Could not read a catalog's resources to name its access packages' bindings"
        }

        It 'writes an application binding under its object id when the names are unread (non-terminating)' {
            # An application object id is accepted at apply exactly as a group's is: Resolve-OERGroupId
            # returns a GUID verbatim with no Graph call, and Sync-OERStructureAccessPackage matches it
            # against the catalog resource's OriginId (proof: Sync-OERStructureAccessPackage.Tests.ps1,
            # 'binds a declared object id even when two catalog resources share a display name ...').
            # With the map unread the only other name is the one the catalog RECORDED, which Graph
            # keeps after a rename, so the object id is the safe key for an application too. A
            # SharePoint binding has no such id (its OriginId is its URL) and is covered below.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [CmdletBinding()] param($Catalog)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'app_x'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadApplication' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -Be '11111111-1111-1111-1111-111111111111' -Because 'the recorded name can name another application after a rename; the object id cannot'
            $Ap.resourceRoles[0].role | Should -Be 'Member'
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/CAT-IT-Core/catalogResourceNames'
        }

        It 'keeps the reader-joined name for a group binding that carries no OriginId when the names are unread (non-terminating)' {
            # With no OriginId there is no object id to write; the fallback is all that is left.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [CmdletBinding()] param($Catalog)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'role_sec_x'; RoleName = 'Member'; OriginId = $null; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            @($Inv.AccessPackages)[0].resourceRoles[0].resource | Should -Be 'role_sec_x'
        }

        It 'keeps the reader-joined name, not the object id, for a group binding the READ names do not contain' {
            # The object id is the fallback for an UNREAD map only. Here the catalog read SUCCEEDED
            # and simply does not list the binding's group, so nothing is unread, no partial is
            # raised, and the binding keeps the name it always had.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'role_sec_other'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'role_sec_recorded'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -Be 'role_sec_recorded' -Because 'a read map that lacks the binding is not an unread map'
            $Ap.resourceRoles[0].role | Should -Be 'Member'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'writes a group binding under its current name, not its object id, when the names were read' {
            # The object id is the fallback for an UNREAD map only: a read map names the binding by
            # the group's current display name, exactly as the Catalogs section names its resource.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'role_sec_recorded'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_current' }; $M }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'role_sec_recorded'; RoleName = 'Member'; OriginId = '11111111-1111-1111-1111-111111111111'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            @($Inv.AccessPackages)[0].resourceRoles[0].resource | Should -Be 'role_sec_current'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }

        It 'reports an unread catalog list for every section that needs it and projects both as empty (non-terminating)' {
            # No handler removes a catalog or an access package that is absent from the document, so
            # the projection stays as it was (two empty sections). An absent entry is not a fact
            # though, and the document must say it could not read them.
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly
            @($Inv.Catalogs).Count | Should -Be 0
            @($Inv.AccessPackages).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
            $Partial[0].Exception.Message | Should -Match 'Could not read the catalogs'
        }

        It 'reports an unread catalog list for the one section that was asked for' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $null = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable CatOnlyErr
            $null = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable ApOnlyErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 2 -Exactly
            $CatOnly = @(@($CatOnlyErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $CatOnly.Count | Should -Be 1
            [string]$CatOnly[0].TargetObject | Should -Be 'catalogs' -Because 'a section that was not asked for is not reported as unread'
            $ApOnly = @(@($ApOnlyErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $ApOnly.Count | Should -Be 1
            [string]$ApOnly[0].TargetObject | Should -Be 'accessPackages'
        }

        It 'reports an unread catalog list the same way when a -Catalog filter was given' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -Catalog 'CAT-IT-Core' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-IT-Core' }
            @($Inv.Catalogs).Count | Should -Be 0
            @($Inv.AccessPackages).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
        }

        It 'reports an unread catalog list when the read threw' {
            Mock -ModuleName $script:moduleName Get-OERCatalog { throw 'Too many requests.' }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly
            @($Inv.Catalogs).Count | Should -Be 0
            @($Inv.AccessPackages).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
            $Partial[0].Exception.Message | Should -Match 'Too many requests'
        }

        It 'republishes Graph''s CatalogNotFound answer for a missing -Catalog id as itself and reports nothing as unread' {
            # This exercises the arm Graph's own CatalogNotFound answer reaches: a live check
            # (2026-10-02) measured that Graph answers a missing catalog id with that code, and
            # Get-OERCatalog republishes it by id. A filter that names no catalog (or more than one)
            # is a FACT about the caller's own filter, not a gap in the export, so that record is
            # republished as itself and must not be counted as an unread collection.
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("No catalog matches '$Id'."), 'CatalogNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Id))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -Catalog '22222222-2222-2222-2222-222222222222' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly
            @($Inv.Catalogs).Count | Should -Be 0
            @($Inv.AccessPackages).Count | Should -Be 0
            # -ErrorAction Stop copies the promoted record into -ErrorVariable once per mock layer it
            # crosses, so the count is taken on the record Get-OERInventory itself published.
            @(@($InvErr) | Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'CatalogNotFound*' -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
                }).Count | Should -Be 1 -Because 'the retained arm republishes the record under its own id'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
                Should -Be 0 -Because 'a filter that names no catalog is a fact about the filter, not an unread collection'
        }

        It 'republishes a by-id 404 on the -Catalog filter as itself and reports nothing as unread' {
            # This covers the module's generic not-found codes on a by-id read as a defensive
            # superset: Graph's own answer for a missing catalog id is CatalogNotFound (the test
            # above), so these did not fire live. A missing catalog id is a FACT about the caller's
            # filter (spec G3: a 404 on an id is NotFound), so it is republished and counted as nothing.
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Resource '$Id' does not exist."), 'ResourceNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Id))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -Catalog '22222222-2222-2222-2222-222222222222' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq '22222222-2222-2222-2222-222222222222' }
            @($Inv.Catalogs).Count | Should -Be 0
            @($Inv.AccessPackages).Count | Should -Be 0
            @(@($InvErr) | Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'ResourceNotFound*' -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
                }).Count | Should -Be 1 -Because 'the caller sees the not-found record itself'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
                Should -Be 0 -Because 'a catalog id that does not exist is a fact about the filter, not an unread collection'
        }

        It 'still counts a 404 on a -Catalog NAME as unread, since a list read has no id to be missing' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Resource not found for the segment.'), 'ResourceNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $DisplayName))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -Catalog 'CAT-IT-Core' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-IT-Core' }
            @($Inv.Catalogs).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
        }

        It 'still counts a 404 on the unfiltered catalog list as unread' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Resource not found for the segment.'), 'ResourceNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly
            @($Inv.Catalogs).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
        }

        It 'still counts a by-id failure that is not a not-found as unread' {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [CmdletBinding()] param($Id, $DisplayName)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $Id))
            }
            $Inv = Get-OERInventory -Include Catalogs, AccessPackages -Catalog '22222222-2222-2222-2222-222222222222' -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -eq '22222222-2222-2222-2222-222222222222' }
            @($Inv.Catalogs).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Be 'catalogs, accessPackages'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
        }

        It 'reports an unread package list for the catalog it belongs to and projects no packages (non-terminating)' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [CmdletBinding()] param($Catalog)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackage -Times 1 -Exactly
            @($Inv.AccessPackages).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/CAT-IT-Core/packages'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
            $Partial[0].Exception.Message | Should -Match "Could not list a catalog's access packages"
        }

        It 'reports an unread assignment policy set and projects an empty list, as before (non-terminating)' {
            # Sync-OERStructureAccessPackage never removes an assignment policy (it reports an
            # undeclared one as still in force), so [] deletes nothing and the projection stays as it
            # was -- but an absent policy is not a fact, so the gap is reported.
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy {
                [CmdletBinding()] param($AccessPackage)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges to complete the operation.'), 'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name -contains 'assignmentPolicies' | Should -BeTrue
            $null -ne $Ap.PSObject.Properties['assignmentPolicies'].Value | Should -BeTrue -Because 'the projection is unchanged: an empty list, not a null'
            @($Ap.PSObject.Properties['assignmentPolicies'].Value).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/AP-Sales/assignmentPolicies'
            $Partial[0].Exception.Message | Should -Match 'Insufficient privileges'
            $Partial[0].Exception.Message | Should -Match "Could not read an access package's assignment policies"
        }

        It 'reports an unread assignment policy set when the read threw' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { throw 'Too many requests.' }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            @($Ap.PSObject.Properties['assignmentPolicies'].Value).Count | Should -Be 0
            $Partial = @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -Match 'accessPackages/AP-Sales/assignmentPolicies'
            $Partial[0].Exception.Message | Should -Match 'Too many requests'
        }

        It 'projects the policies and reports nothing when the assignment policy read succeeded' {
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            @(@($Inv.AccessPackages)[0].assignmentPolicies).Count | Should -Be 1
            @(@($Inv.AccessPackages)[0].assignmentPolicies)[0].displayName | Should -Be 'Default'
            @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
        }
    }

    Context 'a name the export cannot give is never written empty' {
        # BL-06 / decision A10. The validator and schema.json now refuse an empty name (a binding's
        # resource or role, a catalog resource's name, an administrative unit scoped role's role or
        # principal), so the export must never write one. A name that is blank falls back to an
        # object id the apply engine accepts (a group or application binding by its OriginId, a
        # catalog resource by its OriginId); when there is no such id the entry cannot be named at
        # all, so its collection is written as an explicit null -- the documented "leave untouched"
        # signal -- and named in InventoryPartial, the way an unread collection is. Every id below
        # is a placeholder, none of it version-4 shaped.
        BeforeAll {
            function Select-InvPartial {
                param($ErrorList)
                @(@($ErrorList) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
            }
        }
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERCatalog {
                [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; CatalogId = 'cat-1' }
            }
            # The catalog read SUCCEEDS and lists one resource, which is NOT the binding's: the name
            # map is read, and it has no entry for the binding's origin id.
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ Id = 'res-x'; OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_x' }; $M }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = $null; RoleName = 'Member'; OriginId = '22222222-2222-2222-2222-222222222222'; OriginSystem = 'AadApplication' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
        }

        It 'writes an application binding whose name is blank under its object id when the names were read' {
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -BeExactly '22222222-2222-2222-2222-222222222222' -Because 'an empty name is refused by the validator; the object id is accepted at apply'
            $Ap.resourceRoles[0].role | Should -BeExactly 'Member'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 0
        }

        It 'writes a group binding whose name is blank under its object id when the names were read' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = $null; RoleName = 'Member'; OriginId = '22222222-2222-2222-2222-222222222222'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            $Ap.resourceRoles[0].role | Should -BeExactly 'Member'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 0
        }

        It 'treats a whitespace-only binding name as blank and writes the object id' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = '   '; RoleName = 'Member'; OriginId = '22222222-2222-2222-2222-222222222222'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            @($Ap.resourceRoles).Count | Should -Be 1
            $Ap.resourceRoles[0].resource | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 0
        }

        It 'writes the package''s resourceRoles as an explicit null, and names it, when a SharePoint binding has no name' {
            # A SharePoint binding's OriginId is its site URL, which the apply engine does not take as
            # a resource name, so there is no id to fall back to. The package also holds a perfectly
            # nameable group binding: the collection is all or nothing, since a declared set that
            # silently left the SharePoint binding out would have -Prune remove it.
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = ''; RoleName = 'Member'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; OriginSystem = 'SharePointOnline' }
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = 'Member'; OriginId = 'orig-x'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.displayName | Should -Be 'AP-Sales'
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' |
                Should -BeTrue -Because 'an omitted resourceRoles key still reconciles and prunes; only an explicit null is hands-off'
            $null -eq $Ap.resourceRoles | Should -BeTrue
            InModuleScope $script:moduleName -Parameters @{ Node = $Ap } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'resourceRoles' | Should -BeTrue -Because 'this is the gate the handler consults before its prune pass'
            }
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/AP-Sales/resourceRoles'
            $Partial[0].Exception.Message | Should -BeLike '*has no name, and no object id the apply engine accepts*'
            # The lead-in is true of a collection that was READ but could not be written without an empty
            # name, not only of an unread one.
            $Partial[0].Exception.Message |
                Should -BeLike '*PARTIAL: 1 collection(s) or object(s) could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are not stated as facts in the document*'
        }

        It 'writes the package''s resourceRoles as an explicit null, and names it, when a binding has no role name' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = 'Root'; RoleName = ''; OriginId = 'orig-x'; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' | Should -BeTrue
            $null -eq $Ap.resourceRoles | Should -BeTrue -Because 'a binding with no role cannot be named, and an empty role is refused by the validator'
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/AP-Sales/resourceRoles'
            $Partial[0].Exception.Message | Should -BeLike '*has no name, and no object id the apply engine accepts*'
        }

        It 'writes the collection as an explicit null when a group binding has neither a name nor an origin id' {
            # With no OriginId there is no object id to write, so the blank name cannot be rescued.
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = ''; RoleName = 'Member'; OriginId = $null; OriginSystem = 'AadGroup' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
            $Ap = @($Inv.AccessPackages)[0]
            $Ap.PSObject.Properties.Name -contains 'resourceRoles' | Should -BeTrue
            $null -eq $Ap.resourceRoles | Should -BeTrue
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'accessPackages/AP-Sales/resourceRoles'
        }

        It 'names every package whose bindings it cannot name, and states the cause once' {
            Mock -ModuleName $script:moduleName Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; CatalogId = 'cat-1' }
                [PSCustomObject]@{ Id = 'ap-2'; DisplayName = 'AP-Ops'; Description = 'Ops'; CatalogId = 'cat-1' }
            }
            Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
                [PSCustomObject]@{ ResourceDisplayName = ''; RoleName = 'Member'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; OriginSystem = 'SharePointOnline' }
            }
            $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 2 -Exactly
            @($Inv.AccessPackages).Count | Should -Be 2
            foreach ($Ap in @($Inv.AccessPackages)) { $null -eq $Ap.resourceRoles | Should -BeTrue }
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            @(([string]$Partial[0].TargetObject) -split ', ' | Sort-Object) | Should -Be @('accessPackages/AP-Ops/resourceRoles', 'accessPackages/AP-Sales/resourceRoles')
            @([regex]::Matches($Partial[0].Exception.Message, 'has no name, and no object id the apply engine accepts')).Count |
                Should -Be 1 -Because 'one reason repeated once per package is stated once, the way every other cause is'
        }

        It 'writes a SharePoint resource whose title is blank under its site URL' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ Id = 'res-s'; DisplayName = ''; OriginId = 'https://contoso.sharepoint.com/sites/finance'; OriginSystem = 'SharePointOnline'; ResourceType = 'SharePoint Online Site' }
            }
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            @($Cat.resources).Count | Should -Be 1
            $Cat.resources[0].type | Should -BeExactly 'SharePointSite'
            $Cat.resources[0].name | Should -BeExactly 'https://contoso.sharepoint.com/sites/finance' -Because 'a SharePoint site is also identified by its URL, which the validator accepts as a name'
            $Cat.resources[0].url | Should -BeExactly 'https://contoso.sharepoint.com/sites/finance'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 0
        }

        It 'writes a catalog''s resources as an explicit null, and names it, when a resource has neither a title nor an origin id' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                [PSCustomObject]@{ Id = 'res-f'; DisplayName = 'Finance'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; OriginSystem = 'SharePointOnline'; ResourceType = 'SharePoint Online Site' }
                [PSCustomObject]@{ Id = 'res-n'; DisplayName = ''; OriginId = $null; OriginSystem = 'SharePointOnline'; ResourceType = 'SharePoint Online Site' }
            }
            $Inv = Get-OERInventory -Include Catalogs -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -Exactly
            $Cat = @($Inv.Catalogs)[0]
            $Cat.displayName | Should -Be 'CAT-IT-Core'
            $Cat.PSObject.Properties.Name -contains 'resources' |
                Should -BeTrue -Because 'an omitted resources key still reconciles and prunes; only an explicit null is hands-off'
            $null -eq $Cat.resources | Should -BeTrue -Because 'the collection is all or nothing, so the nameable resource is not written either'
            InModuleScope $script:moduleName -Parameters @{ Node = $Cat } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'resources' | Should -BeTrue
            }
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'catalogs/CAT-IT-Core/resources'
            $Partial[0].Exception.Message | Should -BeLike '*has no name, and no object id the apply engine accepts*'
        }

        It 'writes an administrative unit''s scopedRoles as an explicit null, and names it, when a scoped role has no role name and no role id' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @([PSCustomObject]@{ RoleName = ''; RoleId = $null; PrincipalId = 'p-1'; PrincipalDisplayName = 'Person One' })
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.displayName | Should -Be 'AU-One'
            $Au.PSObject.Properties.Name -contains 'scopedRoles' |
                Should -BeTrue -Because 'an omitted scopedRoles key still reconciles and prunes; only an explicit null is hands-off'
            $null -eq $Au.scopedRoles | Should -BeTrue
            InModuleScope $script:moduleName -Parameters @{ Node = $Au } {
                param($Node)
                Test-OERDeclaredNull -Node $Node -Name 'scopedRoles' | Should -BeTrue
            }
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-One/scopedRoles'
            $Partial[0].Exception.Message | Should -BeLike '*has no name, and no object id the apply engine accepts*'
        }

        It 'writes an administrative unit''s scopedRoles as an explicit null, and names it, when a scoped role has no principal' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @([PSCustomObject]@{ RoleName = 'User Administrator'; RoleId = 'r-1'; PrincipalId = $null; PrincipalDisplayName = '' })
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name -contains 'scopedRoles' | Should -BeTrue
            $null -eq $Au.scopedRoles | Should -BeTrue
            $Partial = @(Select-InvPartial -ErrorList $InvErr)
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'administrativeUnits/AU-One/scopedRoles'
            $Partial[0].Exception.Message | Should -BeLike '*has no name, and no object id the apply engine accepts*'
        }

        It 'does not write the named scoped roles of a unit when another of its scoped roles has no name' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @(
                        [PSCustomObject]@{ RoleName = 'User Administrator'; RoleId = 'r-1'; PrincipalId = 'p-1'; PrincipalDisplayName = 'Person One' }
                        [PSCustomObject]@{ RoleName = ''; RoleId = $null; PrincipalId = 'p-2'; PrincipalDisplayName = 'Person Two' }
                    )
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            $Au = @($Inv.AdministrativeUnits)[0]
            $Au.PSObject.Properties.Name -contains 'scopedRoles' | Should -BeTrue
            $null -eq $Au.scopedRoles | Should -BeTrue -Because 'a declared set missing the unnamed role would have -Prune remove it'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 1
        }

        It 'still writes scoped roles that are all named, with no partial' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; DisplayName = 'AU-One'; Description = $null
                    IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                    Members = @()
                    ScopedRoles = @([PSCustomObject]@{ RoleName = 'User Administrator'; RoleId = 'r-1'; PrincipalId = 'p-1'; PrincipalDisplayName = 'Person One' })
                }
            }
            $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable InvErr
            Should -Invoke -ModuleName $script:moduleName Get-OERAdministrativeUnit -Times 1 -Exactly
            $Au = @($Inv.AdministrativeUnits)[0]
            @($Au.scopedRoles).Count | Should -Be 1
            $Au.scopedRoles[0].role | Should -BeExactly 'User Administrator'
            $Au.scopedRoles[0].principal | Should -BeExactly 'p-1'
            @(Select-InvPartial -ErrorList $InvErr).Count | Should -Be 0
        }
    }

    Context 'the shipped JSON Schema accepts the null a failed read projects' {
        It 'types groups members, administrativeUnits members and scopedRoles as array or null' {
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
            $GroupProps = $Schema.properties.groups.items.properties
            $AuProps = $Schema.properties.administrativeUnits.items.properties
            @($GroupProps.members.type) | Should -Contain 'null'
            @($GroupProps.members.type) | Should -Contain 'array'
            @($AuProps.members.type) | Should -Contain 'null'
            @($AuProps.scopedRoles.type) | Should -Contain 'null'
        }

        It 'does NOT widen owners or eligibility, which have no null producer' {
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
            $GroupProps = $Schema.properties.groups.items.properties
            @($GroupProps.owners.type) | Should -Not -Contain 'null'
            @($GroupProps.eligibility.type) | Should -Not -Contain 'null'
        }

        It 'types catalogs resources and accessPackages resourceRoles as array or null' {
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
            @($Schema.properties.catalogs.items.properties.resources.type) | Should -Contain 'null'
            @($Schema.properties.catalogs.items.properties.resources.type) | Should -Contain 'array'
            @($Schema.properties.accessPackages.items.properties.resourceRoles.type) | Should -Contain 'null'
            @($Schema.properties.accessPackages.items.properties.resourceRoles.type) | Should -Contain 'array'
        }

        It 'validates a catalog and an access package whose resources and resourceRoles are explicit nulls' {
            $Doc = @{
                version        = '1.0'
                catalogs       = @(@{ displayName = 'CAT-One'; resources = $null })
                accessPackages = @(@{ displayName = 'AP-One'; catalog = 'CAT-One'; resourceRoles = $null })
            } | ConvertTo-Json -Depth 10
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson }
            Test-Json -Json $Doc -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeTrue -Because 'the schema written beside a bundle must accept the document that bundle contains'
        }

        It 'validates a group document whose members key is an explicit null' {
            $Doc = @{
                version = '1.0'
                groups  = @(@{ displayName = 'role_sec_team'; members = $null })
            } | ConvertTo-Json -Depth 10
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson }
            Test-Json -Json $Doc -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeTrue -Because 'the schema written beside a bundle must accept the document that bundle contains'
        }

        It 'validates an administrative unit document whose members and scopedRoles are explicit nulls' {
            $Doc = @{
                version             = '1.0'
                administrativeUnits = @(@{ displayName = 'AU-One'; members = $null; scopedRoles = $null })
            } | ConvertTo-Json -Depth 10
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson }
            Test-Json -Json $Doc -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    Context 'Directory role sections' {
        # The four readers are mocked; Select-OERManagedDirectoryRoleAssignment and
        # ConvertTo-OERInventoryRoleManagementPolicy run for real, since which live row may be
        # exported, and in what shape, is exactly what these tests pin. No id below is version-4
        # shaped.
        BeforeAll {
            $script:DirRoleA = '11111111-1111-1111-1111-111111111111'
            $script:DirRoleB = '22222222-2222-2222-2222-222222222222'
            $script:DirRoleC = '33333333-3333-3333-3333-333333333333'
            $script:DirUser1 = 'aaaaaaaa-0000-0000-0000-000000000001'
            $script:DirUser2 = 'aaaaaaaa-0000-0000-0000-000000000002'
            $script:DirGroup1 = 'bbbbbbbb-0000-0000-0000-000000000001'
            $script:DirSp1 = 'cccccccc-0000-0000-0000-000000000001'
            $script:DirNames = @{
                $script:DirUser1  = 'person1@example.com'
                $script:DirUser2  = 'person2@example.com'
                $script:DirGroup1 = 'Fixture Group'
            }
            $script:DirRoleNames = @{
                $script:DirRoleA = 'Fixture Role A'
                $script:DirRoleB = 'Fixture Role B'
                $script:DirRoleC = 'Fixture Role C'
            }

            # One projected schedule row, the shape ConvertTo-OERDirectoryRoleAssignment emits. The
            # default is a direct, tenant-scope, 30-day row of person1 for role A.
            function script:New-DirRow {
                param(
                    [ValidateSet('Eligible', 'Active')][string]$Kind = 'Eligible',
                    [string]$ScheduleId = 'schedule-0001',
                    [string]$RoleDefinitionId = $script:DirRoleA,
                    [object]$RoleName = 'Fixture Role A',
                    [string]$PrincipalId = $script:DirUser1,
                    [object]$PrincipalType = 'User',
                    [string]$MemberType = 'Direct',
                    [string]$AssignmentType = 'Assigned',
                    [object]$Start = '2026-01-01T00:00:00Z',
                    [object]$End = '2026-01-31T00:00:00Z',
                    [object]$DurationDays = 30
                )
                $Row = [ordered]@{
                    ScheduleId           = $ScheduleId
                    RoleDefinitionId     = $RoleDefinitionId
                    RoleName             = $RoleName
                    PrincipalId          = $PrincipalId
                    PrincipalDisplayName = 'fixture'
                    PrincipalType        = $PrincipalType
                    DirectoryScopeId     = '/'
                    MemberType           = $MemberType
                }
                if ($Kind -eq 'Active') { $Row.AssignmentType = $AssignmentType }
                $Row.Status = 'Provisioned'
                $Row.StartDateTime = $Start
                $Row.EndDateTime = $End
                $Row.ExpirationType = $(if ($End) { 'afterDateTime' } else { 'noExpiration' })
                $Row.DurationDays = $DurationDays
                $Out = [PSCustomObject]$Row
                $Out.PSObject.TypeNames.Insert(0, "Omnicit.EntraRBAC.$($Kind)DirectoryRoleAssignment")
                $Out
            }

            # One directory role policy, the shape Get-OERDirectoryRoleManagementPolicy returns.
            function script:New-DirPolicy {
                param([string]$RoleDefinitionId, [string]$PolicyId)
                $Out = [PSCustomObject]@{
                    PolicyId                               = $PolicyId
                    Scope                                  = '/'
                    RoleName                               = $script:DirRoleNames[$RoleDefinitionId]
                    RoleDefinitionId                       = $RoleDefinitionId
                    ActivationMaxHours                     = 8
                    RequireMfaOnActivation                 = $true
                    RequireJustificationOnActivation       = $true
                    RequireTicketOnActivation              = $false
                    RequireApproval                        = $false
                    Approvers                              = @()
                    AuthenticationContextId                = $null
                    AllowPermanentEligibility              = $false
                    EligibleDurationDays                   = 365
                    AllowPermanentActiveAssignment         = $false
                    ActiveDurationDays                     = 180
                    RequireMfaOnActiveAssignment           = $false
                    RequireJustificationOnActiveAssignment = $true
                }
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleManagementPolicy')
                $Out
            }
        }

        BeforeEach {
            $script:DirEligible = @()
            $script:DirActive = @()
            $script:DirPolicies = @(
                New-DirPolicy -RoleDefinitionId $script:DirRoleA -PolicyId 'policy-a'
                New-DirPolicy -RoleDefinitionId $script:DirRoleB -PolicyId 'policy-b'
                New-DirPolicy -RoleDefinitionId $script:DirRoleC -PolicyId 'policy-c'
            )
            # BL-131 (Task 3c): the tenant's groups are the groups the rows name, each under its name in
            # $script:DirNames, so a group principal is shared or unique as the fixture says.
            Mock -ModuleName $script:moduleName Get-OERGroupNameIndex {
                $NameById = @{}
                foreach ($Row in @($script:DirEligible) + @($script:DirActive)) {
                    if ($null -eq $Row -or [string]$Row.PrincipalType -ne 'Group') { continue }
                    if ($script:DirNames.ContainsKey([string]$Row.PrincipalId)) { $NameById[[string]$Row.PrincipalId] = $script:DirNames[[string]$Row.PrincipalId] }
                }
                & $script:NewGroupNameIndexOf $NameById
            }
            Mock -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment { $script:DirEligible }
            Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment { $script:DirActive }
            Mock -ModuleName $script:moduleName Get-OERDirectoryRoleManagementPolicy { $script:DirPolicies }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                $Map = @{}
                foreach ($One in @($Id)) {
                    $Map[$One] = $(if ($script:DirNames.ContainsKey($One)) { $script:DirNames[$One] } else { $One })
                }
                $Map
            }
            # Nothing in this Context may reach the transport: a helper that would is a missing mock.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected transport call: $Uri" }
        }

        It 'exports a direct tenant-scope eligible row of a user as its UPN, with principalType, assignmentType and durationDays' {
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Entries = @($Inv.directoryRoleAssignments)
            $Entries.Count | Should -Be 1
            @($Entries[0].PSObject.Properties.Name) | Should -Be @('role', 'principal', 'principalType', 'assignmentType', 'durationDays')
            $Entries[0].role | Should -BeExactly 'Fixture Role A'
            $Entries[0].principal | Should -BeExactly 'person1@example.com'
            $Entries[0].principalType | Should -BeExactly 'User'
            $Entries[0].assignmentType | Should -BeExactly 'Eligible'
            $Entries[0].durationDays | Should -Be 30
            $Entries[0].durationDays | Should -BeOfType [int]
        }

        It 'falls back to the role definition id when the row carries no role name' {
            $script:DirEligible = @(New-DirRow -RoleName '')
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            @($Inv.directoryRoleAssignments)[0].role | Should -BeExactly $script:DirRoleA
        }

        It 'does not export an activation (an Active row whose AssignmentType is Activated)' {
            $script:DirActive = @(
                New-DirRow -Kind Active -ScheduleId 'activation-0001' -AssignmentType 'Activated' -End '2026-01-01T08:00:00Z' -DurationDays 1
                New-DirRow -Kind Active -ScheduleId 'schedule-0002' -PrincipalId $script:DirUser2
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Entries = @($Inv.directoryRoleAssignments)
            $Entries.Count | Should -Be 1 -Because 'the activation of person1 must not be exported as a standing active assignment'
            $Entries[0].principal | Should -BeExactly 'person2@example.com'
            $Entries[0].assignmentType | Should -BeExactly 'Active'
        }

        It 'does not export a row a principal holds through a group (MemberType Group)' {
            $script:DirEligible = @(
                New-DirRow
                New-DirRow -ScheduleId 'schedule-0002' -PrincipalId $script:DirUser2 -MemberType 'Group'
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Entries = @($Inv.directoryRoleAssignments)
            $Entries.Count | Should -Be 1 -Because 'the group-inherited row of person2 is managed through the group'
            $Entries[0].principal | Should -BeExactly 'person1@example.com'
        }

        It 'exports a service principal as its object id with principalType ServicePrincipal, and never asks Resolve-OERPrincipalName to name it' {
            $script:DirEligible = @(New-DirRow)
            $script:DirActive = @(
                New-DirRow -Kind Active -ScheduleId 'schedule-0002' -PrincipalId $script:DirSp1 -PrincipalType 'ServicePrincipal' -End $null -DurationDays $null
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Sp = @($Inv.directoryRoleAssignments | Where-Object { $_.assignmentType -eq 'Active' })
            $Sp.Count | Should -Be 1
            $Sp[0].principal | Should -BeExactly $script:DirSp1
            $Sp[0].principalType | Should -BeExactly 'ServicePrincipal'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0 -ParameterFilter { @($Id) -contains $script:DirSp1 }
            # One batched call names every user and group principal of the section.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
        }

        It 'exports a principal of unknown type as its object id, without principalType, and does not name it' {
            $script:DirEligible = @(New-DirRow -PrincipalId $script:DirUser2 -PrincipalType $null)
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Entry = @($Inv.directoryRoleAssignments)[0]
            $Entry.principal | Should -BeExactly $script:DirUser2
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'principalType'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
        }

        It 'exports a permanent row with neither durationDays nor permanent' {
            $script:DirEligible = @(New-DirRow -End $null -DurationDays $null)
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            $Entry = @($Inv.directoryRoleAssignments)[0]
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'durationDays'
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'permanent'
        }

        It 'exports one entry, the first, and warns once for two schedules of one role, principal and kind' {
            # The second row spells the role id in upper case: the duplicate check ignores letter case.
            $script:DirEligible = @(
                New-DirRow
                New-DirRow -ScheduleId 'schedule-0002' -RoleDefinitionId $script:DirRoleA.ToUpperInvariant() -End '2026-03-02T00:00:00Z' -DurationDays 60
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments -WarningAction SilentlyContinue -WarningVariable DirWarn
            $Entries = @($Inv.directoryRoleAssignments)
            $Entries.Count | Should -Be 1
            $Entries[0].durationDays | Should -Be 30 -Because 'the first schedule the tenant-wide read returned is the one exported'
            @($DirWarn).Count | Should -Be 1
            [string]@($DirWarn)[0].Message | Should -BeExactly ("Get-OERInventory: directory role 'Fixture Role A' has more than one eligible schedule for principal " +
                "'$($script:DirUser1)'; exporting the first. Invoke-OERStructure compares against the first schedule Microsoft Graph " +
                'returns for that role and principal, so if the two differ it may report a change for this entry.')
        }

        It 'names two same-named groups holding one role and kind by their object ids, so the section stays valid' {
            # Entra does not keep group display names unique. Two groups both named 'Fixture Group'
            # would otherwise export two identical (role, principal, assignmentType) entries, which the
            # validator refuses as a duplicate -- invalidating the whole document. A third group whose
            # name equals a user's UPN in the same role and kind collides the same way (the collision
            # pass names it by id, since no other group carries its name). The user keeps its name. A
            # same-named group holding a DIFFERENT role is named by its id too: the name is shared in
            # the tenant, so the apply engine would refuse it (BL-131, Task 3c).
            $DirGroup2 = 'bbbbbbbb-0000-0000-0000-000000000002'
            $DirGroup3 = 'bbbbbbbb-0000-0000-0000-000000000003'
            $DirGroup4 = 'bbbbbbbb-0000-0000-0000-000000000004'
            $script:DirNames[$DirGroup2] = 'fixture group'
            $script:DirNames[$DirGroup3] = 'person1@example.com'
            $script:DirNames[$DirGroup4] = 'Fixture Group'
            try {
                $script:DirEligible = @(
                    New-DirRow -ScheduleId 's-1' -PrincipalId $script:DirGroup1 -PrincipalType 'Group'
                    New-DirRow -ScheduleId 's-2' -PrincipalId $DirGroup2 -PrincipalType 'Group'
                    New-DirRow -ScheduleId 's-3' -PrincipalId $DirGroup3 -PrincipalType 'Group'
                    New-DirRow -ScheduleId 's-4' -PrincipalId $script:DirUser1
                    New-DirRow -ScheduleId 's-5' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $DirGroup4 -PrincipalType 'Group'
                )
                $Inv = Get-OERInventory -Include DirectoryRoleAssignments
                @($Inv.directoryRoleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) | Should -Be @(
                    "Fixture Role A|$($script:DirGroup1)|Group"
                    "Fixture Role A|$DirGroup2|Group"
                    "Fixture Role A|$DirGroup3|Group"
                    'Fixture Role A|person1@example.com|User'
                    "Fixture Role B|$DirGroup4|Group"
                )
                $Doc = [PSCustomObject]@{ version = '1.0'; directoryRoleAssignments = @($Inv.directoryRoleAssignments) }
                $Validation = InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } {
                    param($Doc)
                    Test-OERStructureSchema -Document $Doc
                }
                @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { "$($_.Path): $($_.Message)" }) |
                    Should -BeNullOrEmpty
                $Validation.Valid | Should -BeTrue
            } finally {
                foreach ($One in $DirGroup2, $DirGroup3, $DirGroup4) { $script:DirNames.Remove($One) }
            }
        }

        It 'keeps the name of a group that only a principal holding ANOTHER role carries: the collision is per role' {
            # The group's name is unique among groups, so the group rule keeps it; it equals the UPN of a
            # user who holds role A, while the group holds role B. The two entries differ in role, so the
            # validator accepts them, and the collision pass, keyed on the role definition id as well as
            # the kind and the name, leaves the group by its name.
            $DirGroup5 = 'bbbbbbbb-0000-0000-0000-000000000005'
            $script:DirNames[$DirGroup5] = 'person2@example.com'
            try {
                $script:DirEligible = @(
                    New-DirRow -ScheduleId 's-1' -PrincipalId $script:DirUser2
                    New-DirRow -ScheduleId 's-2' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $DirGroup5 -PrincipalType 'Group'
                )
                $Inv = Get-OERInventory -Include DirectoryRoleAssignments
                @($Inv.directoryRoleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) | Should -Be @(
                    'Fixture Role A|person2@example.com|User'
                    'Fixture Role B|person2@example.com|Group'
                )
                # Reach proof: the group was named through the index of every group, which holds it alone.
                Should -Invoke -ModuleName $script:moduleName Get-OERGroupNameIndex -Exactly -Times 1
                $Doc = [PSCustomObject]@{ version = '1.0'; directoryRoleAssignments = @($Inv.directoryRoleAssignments) }
                $Validation = InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } {
                    param($Doc)
                    Test-OERStructureSchema -Document $Doc
                }
                @($Validation.Errors | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { "$($_.Path): $($_.Message)" }) |
                    Should -BeNullOrEmpty
            } finally {
                $script:DirNames.Remove($DirGroup5)
            }
        }

        It 'sorts the entries by role, then Eligible before Active, then principal' {
            $script:DirEligible = @(
                New-DirRow -ScheduleId 's-1' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $script:DirUser2
                New-DirRow -ScheduleId 's-2' -PrincipalId $script:DirUser2
                New-DirRow -ScheduleId 's-3' -PrincipalId $script:DirGroup1 -PrincipalType 'Group' -End $null -DurationDays $null
            )
            $script:DirActive = @(
                New-DirRow -Kind Active -ScheduleId 's-4' -PrincipalId $script:DirUser1
                New-DirRow -Kind Active -ScheduleId 's-5' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $script:DirUser1
            )
            $Inv = Get-OERInventory -Include DirectoryRoleAssignments
            @($Inv.directoryRoleAssignments | ForEach-Object { "$($_.role)|$($_.assignmentType)|$($_.principal)" }) | Should -Be @(
                'Fixture Role A|Eligible|Fixture Group'
                'Fixture Role A|Eligible|person2@example.com'
                'Fixture Role A|Active|person1@example.com'
                'Fixture Role B|Eligible|person2@example.com'
                'Fixture Role B|Active|person1@example.com'
            )
            @($Inv.directoryRoleAssignments)[0].principalType | Should -BeExactly 'Group'
        }

        It 'exports only the policies of roles that appear in either schedule read, activations included' {
            # Role A has a direct eligible row; role B appears ONLY as an activation, which the
            # assignments section never exports but the policy selection still counts; role C has
            # no row at all.
            $script:DirEligible = @(New-DirRow)
            $script:DirActive = @(
                New-DirRow -Kind Active -ScheduleId 'activation-0001' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -AssignmentType 'Activated'
            )
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies
            @($Inv.directoryRoleManagementPolicies).role | Should -Be @('Fixture Role A', 'Fixture Role B')
            @($Inv.directoryRoleManagementPolicies)[0].PSObject.Properties.Name | Should -Not -Contain 'scope'
            @($Inv.directoryRoleAssignments).Count | Should -Be 0 -Because 'the assignments section was not included'
            Should -Invoke -ModuleName $script:moduleName Get-OERDirectoryRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $All }
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
        }

        It 'exports every policy with -AllDirectoryRolePolicies and issues no schedule read when the assignments section is not included' {
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies -AllDirectoryRolePolicies
            @($Inv.directoryRoleManagementPolicies).role | Should -Be @('Fixture Role A', 'Fixture Role B', 'Fixture Role C')
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 0
        }

        It 'still reads the schedules once with -AllDirectoryRolePolicies when the assignments section is included' {
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -AllDirectoryRolePolicies
            @($Inv.directoryRoleManagementPolicies).Count | Should -Be 3
            @($Inv.directoryRoleAssignments).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
        }

        It 'on a failed eligible read exports no eligible entry, still exports the active ones, and reports both gaps' {
            Mock -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment {
                # A real advanced function honours the caller's -ErrorAction; a mock body does not
                # inherit it across the session-state boundary, so it is passed on explicitly here.
                $Ea = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                Write-Error -Message 'Forbidden: fixture refusal of the eligibility schedules.' -ErrorId 'Forbidden' -ErrorAction $Ea
            }
            $script:DirActive = @(
                New-DirRow -Kind Active -ScheduleId 'schedule-0002' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $script:DirUser2
            )
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ErrorAction SilentlyContinue -ErrorVariable DirErr
            $Entries = @($Inv.directoryRoleAssignments)
            @($Entries | Where-Object { $_.assignmentType -eq 'Eligible' }).Count | Should -Be 0
            $Entries.Count | Should -Be 1
            $Entries[0].principal | Should -BeExactly 'person2@example.com'
            $Entries[0].assignmentType | Should -BeExactly 'Active'
            # The selection still exports the roles the read that succeeded found.
            @($Inv.directoryRoleManagementPolicies).role | Should -Be @('Fixture Role B')
            $Partial = @(@($DirErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            $Unread = @(([string]$Partial[0].TargetObject) -split ', ')
            $Unread | Should -Contain 'directoryRoleAssignments/Eligible'
            $Unread | Should -Contain 'directoryRoleManagementPolicies/role selection'
            $Unread | Should -Not -Contain 'directoryRoleAssignments/Active'
            $Partial[0].Exception.Message | Should -Match 'fixture refusal of the eligibility schedules'
        }

        It 'on a failed active read exports no active entry, still exports the eligible ones, and reports both gaps' {
            Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment {
                $Ea = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                Write-Error -Message 'Forbidden: fixture refusal of the assignment schedules.' -ErrorId 'Forbidden' -ErrorAction $Ea
            }
            $script:DirEligible = @(
                New-DirRow -ScheduleId 'schedule-0002' -RoleDefinitionId $script:DirRoleB -RoleName 'Fixture Role B' -PrincipalId $script:DirUser2
            )
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ErrorAction SilentlyContinue -ErrorVariable DirErr
            $Entries = @($Inv.directoryRoleAssignments)
            @($Entries | Where-Object { $_.assignmentType -eq 'Active' }).Count | Should -Be 0
            $Entries.Count | Should -Be 1
            $Entries[0].principal | Should -BeExactly 'person2@example.com'
            $Entries[0].assignmentType | Should -BeExactly 'Eligible'
            @($Inv.directoryRoleManagementPolicies).role | Should -Be @('Fixture Role B')
            $Partial = @(@($DirErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            $Unread = @(([string]$Partial[0].TargetObject) -split ', ')
            $Unread | Should -Contain 'directoryRoleAssignments/Active'
            $Unread | Should -Contain 'directoryRoleManagementPolicies/role selection'
            $Unread | Should -Not -Contain 'directoryRoleAssignments/Eligible'
            $Partial[0].Exception.Message | Should -Match 'fixture refusal of the assignment schedules'
        }

        It 'on a failed schedule read with only the policy section included reports the role selection, not the assignments' {
            Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment {
                $Ea = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                Write-Error -Message 'Forbidden: fixture refusal of the assignment schedules.' -ErrorId 'Forbidden' -ErrorAction $Ea
            }
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies -ErrorAction SilentlyContinue -ErrorVariable DirErr
            @($Inv.directoryRoleManagementPolicies).role | Should -Be @('Fixture Role A')
            $Partial = @(@($DirErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            @(([string]$Partial[0].TargetObject) -split ', ') | Should -Be @('directoryRoleManagementPolicies/role selection')
        }

        It 'on a failed policy read reports directoryRoleManagementPolicies and exports no policy entry' {
            Mock -ModuleName $script:moduleName Get-OERDirectoryRoleManagementPolicy {
                $Ea = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                Write-Error -Message 'Forbidden: fixture refusal of the policies.' -ErrorId 'PolicyReadFailed' -ErrorAction $Ea
            }
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies -ErrorAction SilentlyContinue -ErrorVariable DirErr
            @($Inv.directoryRoleManagementPolicies).Count | Should -Be 0
            $Partial = @(@($DirErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            @(([string]$Partial[0].TargetObject) -split ', ') | Should -Be @('directoryRoleManagementPolicies')
            $Partial[0].Exception.Message | Should -Match 'fixture refusal of the policies'
        }

        It 'reads each schedule list exactly once, unfiltered, when both directory sections are included' {
            $script:DirEligible = @(New-DirRow)
            $script:DirActive = @(New-DirRow -Kind Active -ScheduleId 'schedule-0002')
            $null = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                -not $Role -and -not $PrincipalId -and -not $User -and -not $Group -and -not $ServicePrincipal
            }
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 1 -Exactly -ParameterFilter {
                -not $Role -and -not $PrincipalId -and -not $User -and -not $Group -and -not $ServicePrincipal
            }
        }

        It 'calls no directory reader under the default -Include' {
            Mock -ModuleName $script:moduleName Get-OERAdministrativeUnit {}
            Mock -ModuleName $script:moduleName Get-OERCatalog {}
            $Inv = Get-OERInventory
            Should -Invoke -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERDirectoryRoleManagementPolicy -Times 0
            @($Inv.directoryRoleManagementPolicies).Count | Should -Be 0
            @($Inv.directoryRoleAssignments).Count | Should -Be 0
        }

        It 'stamps the schedule id on an assignment entry and the policy id on a policy entry under -IncludeId' {
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -IncludeId
            @($Inv.directoryRoleAssignments)[0].id | Should -BeExactly 'schedule-0001'
            @($Inv.directoryRoleManagementPolicies)[0].id | Should -BeExactly 'policy-a'
        }

        It 'stamps no id without -IncludeId' {
            $script:DirEligible = @(New-DirRow)
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
            @($Inv.directoryRoleAssignments)[0].PSObject.Properties.Name | Should -Not -Contain 'id'
            @($Inv.directoryRoleManagementPolicies)[0].PSObject.Properties.Name | Should -Not -Contain 'id'
        }

        It 'emits the inventory keys in the documented section order' {
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
            @($Inv.PSObject.Properties.Name) | Should -Be @('version', 'groups', 'administrativeUnits', 'catalogs',
                'accessPackages', 'accessReviews', 'directoryRoleManagementPolicies', 'directoryRoleAssignments',
                'roleAssignments', 'roleManagementPolicies')
        }
    }
}

Describe 'Get-OERInventory role assignment principals the directory did not return, or whose lookup failed (Sprint 11 step 6, BL-133, A18)' {
    # A role assignment can name a principal the directory does not return. The section looks every
    # principal up with Resolve-OERPrincipalName -Detailed and tells three cases apart: a principal it
    # returned (written by its name), one a successful lookup did not return (written by its object id
    # with principalStatus Deleted or Unresolved, from ONE read of the directory's deleted items), and one
    # whose lookup failed (written by its object id with no principalStatus and named unread). The
    # deleted items read runs for real here, answered through the transport. principalType is written for
    # every row whose ARM type maps to the schema enum. No id below is version-4 shaped.
    BeforeAll {
        $script:UpSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
        $script:UpSub2 = '/subscriptions/aaaa1111-0000-0000-0000-000000000002'
        $script:UpUser = 'dddd8888-0000-0000-0000-000000000001'
        $script:UpGone = 'dddd8888-0000-0000-0000-000000000002'
        $script:UpNowhere = 'dddd8888-0000-0000-0000-000000000003'
        $script:UpGroup = 'dddd8888-0000-0000-0000-000000000004'
        $script:UpDevice = 'dddd8888-0000-0000-0000-000000000005'
        $script:UpDenied = 'dddd8888-0000-0000-0000-000000000006'
        $script:UpTag = 'Omnicit.EntraRBAC.UnresolvedPrincipal'
        function script:New-UpRa {
            param([string]$PrincipalId, [string]$PrincipalType, [string]$RoleName = 'Reader', [string]$Scope = $script:UpSub)
            [PSCustomObject]@{
                Scope = $Scope; RoleName = $RoleName
                RoleDefinitionId = "$Scope/providers/Microsoft.Authorization/roleDefinitions/bbbb8888-0000-0000-0000-000000000001"
                PrincipalId = $PrincipalId; PrincipalType = $PrincipalType; PrincipalDisplayName = 'read under another name'
                RoleAssignmentId = "$Scope/providers/Microsoft.Authorization/roleAssignments/$PrincipalId-$RoleName"
            }
        }
        # The answers of the -Detailed lookup, per id.
        function script:New-UpFound {
            param([string]$Id, [string]$Name, [string]$ObjectType)
            [PSCustomObject]@{ Id = $Id; Read = $true; Found = $true; Name = $Name; ObjectType = $ObjectType; Cause = $null }
        }
        function script:New-UpNotFound {
            param([string]$Id)
            [PSCustomObject]@{ Id = $Id; Read = $true; Found = $false; Name = $null; ObjectType = $null; Cause = $null }
        }
        function script:New-UpUnread {
            param([string]$Id, [string]$Cause)
            [PSCustomObject]@{ Id = $Id; Read = $false; Found = $false; Name = $null; ObjectType = $null; Cause = $Cause }
        }
        # The warning Get-OERInventory writes for <Count> rows written with principalStatus.
        function script:Get-UpWarningText {
            param([int]$Count)
            "Get-OERInventory: $Count role assignment(s) name a principal the directory did not return, so each is written by " +
            "the principal's object id with principalStatus: Deleted when the principal was found among the directory's deleted items, " +
            'Unresolved when it was found neither in the directory nor among its deleted items (deleted beyond the retention period, a ' +
            'principal of another tenant, or not readable) or when its deleted items could not be read. Invoke-OERStructure never ' +
            'creates such an assignment; review them as a finding.'
        }
        # The InventoryPartial records Get-OERInventory itself published.
        function script:Get-UpPartial {
            param([object[]]$Record)
            @($Record | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' -and
                    $_.FullyQualifiedErrorId -like 'InventoryPartial*'
                })
        }
        # Stands in for Export-OERInventory: makes the run context the export makes, owned by its OWN
        # invocation, calls Get-OERInventory once per scope from inside itself, and hands back the context.
        function script:Invoke-UpAsExport {
            [CmdletBinding()]
            param([string[]]$Scope)
            $Context = [PSCustomObject]@{
                Owner                = $MyInvocation
                GroupNameIndex       = $null
                PrincipalStatus      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                UnreadPrincipal      = [System.Collections.Generic.List[string]]::new()
                UnreadPrincipalCause = [System.Collections.Generic.List[object]]::new()
            }
            & (Get-Module $script:moduleName) { param($Context) $script:_OERInventoryRunContext = $Context } $Context
            $Errors = @()
            $Inventory = foreach ($One in $Scope) {
                $CallErrors = $null
                Get-OERInventory -Include RoleAssignments -Scope $One -IncludeARM -ErrorAction SilentlyContinue -ErrorVariable CallErrors -WarningAction SilentlyContinue
                $Errors += @($CallErrors)
            }
            [PSCustomObject]@{ Context = $Context; Inventory = @($Inventory); Errors = $Errors }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null; $script:_OERInventoryRunContext = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $script:UpRas = @()
        $script:UpAnswers = @{}
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:UpRas }
        # The -Detailed lookup answers what the test put in $script:UpAnswers for each id, and nothing
        # for an id it holds no answer for.
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
            if (-not $Detailed) { throw 'the RoleAssignments section looks its principals up with -Detailed' }
            foreach ($One in @($Id)) { if ($script:UpAnswers.ContainsKey($One)) { $script:UpAnswers[$One] } }
        }
        Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { & $script:NewGroupNameIndexOf @{ $script:UpGroup = 'Ops' } }
        # The deleted items: UpGone is among them, UpNowhere answers 404 (the not-found marker), UpDenied
        # cannot be read. Any other request fails loudly.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = $script:UpGone; '@odata.type' = '#microsoft.graph.user'; deletedDateTime = '2026-10-01T00:00:00Z' }
        } -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpGone)" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'Resource does not exist.'; Uri = $Uri }
            $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
            $Marker
        } -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpNowhere)" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw 'Insufficient privileges to complete the operation.'
        } -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpDenied)" }
    }

    AfterEach {
        InModuleScope $script:moduleName { $script:_OERInventoryRunContext = $null }
    }

    It 'writes a principal the directory returned by its name, with principalType for a user and for a group, and reads no deleted items' {
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpUser -PrincipalType 'User'
            New-UpRa -PrincipalId $script:UpGroup -PrincipalType 'Group' -RoleName 'Owner'
        )
        $script:UpAnswers = @{
            $script:UpUser  = New-UpFound -Id $script:UpUser -Name 'person1@example.com' -ObjectType 'user'
            $script:UpGroup = New-UpFound -Id $script:UpGroup -Name 'Ops' -ObjectType 'group'
        }
        $W = $null; $Info = $null; $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
        @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) | Should -Be @(
            'Reader|person1@example.com|User'
            'Owner|Ops|Group'
        )
        @(@($Inv.roleAssignments)[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        @($Inv.roleAssignments | Where-Object { $_.PSObject.Properties.Name -contains 'principalStatus' }).Count | Should -Be 0
        @($W).Count | Should -Be 0
        @($Info | Where-Object { $_.Tags -contains $script:UpTag }).Count | Should -Be 0
        (Get-UpPartial -Record @($InvErr)).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly -ParameterFilter { $Detailed }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'writes a deleted principal by its object id with principalStatus Deleted after principalType, warns once and hands the row over in one information record' {
        $script:UpRas = @(New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User')
        $script:UpAnswers = @{ $script:UpGone = New-UpNotFound -Id $script:UpGone }
        $W = $null; $Info = $null; $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
        $Ra = @($Inv.roleAssignments)
        $Ra.Count | Should -Be 1
        @($Ra[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType', 'principalStatus')
        "$($Ra[0].principal)|$($Ra[0].principalType)|$($Ra[0].principalStatus)" | Should -Be "$($script:UpGone)|User|Deleted"
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpGone)" }
        @($W).Count | Should -Be 1
        [string]$W[0].Message | Should -BeExactly (Get-UpWarningText -Count 1)
        $Records = @($Info | Where-Object { $_.Tags -contains $script:UpTag })
        $Records.Count | Should -Be 1
        $Notice = $Records[0].MessageData
        $Notice.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.UnresolvedPrincipalNotice'
        @($Notice.PSObject.Properties.Name) | Should -Be @('Warning', 'Assignments')
        $Notice.Warning | Should -BeExactly (Get-UpWarningText -Count 1)
        $Rows = @($Notice.Assignments)
        $Rows.Count | Should -Be 1
        @($Rows[0].PSObject.Properties.Name) | Should -Be @('RoleAssignmentId', 'Scope', 'Role', 'Principal', 'PrincipalType', 'PrincipalStatus', 'StatusRead')
        "$($Rows[0].RoleAssignmentId)|$($Rows[0].Scope)|$($Rows[0].Role)|$($Rows[0].Principal)|$($Rows[0].PrincipalType)|$($Rows[0].PrincipalStatus)" |
            Should -Be "$($script:UpSub)/providers/Microsoft.Authorization/roleAssignments/$($script:UpGone)-Reader|$($script:UpSub)|Reader|$($script:UpGone)|User|Deleted"
        # A Deleted status was read.
        $Rows[0].StatusRead | Should -BeOfType ([bool])
        $Rows[0].StatusRead | Should -BeTrue
        (Get-UpPartial -Record @($InvErr)).Count | Should -Be 0
    }

    It 'writes a principal found nowhere as Unresolved, maps a ForeignGroup to Group, and counts both kinds in the one warning and record' {
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User'
            New-UpRa -PrincipalId $script:UpNowhere -PrincipalType 'ForeignGroup' -RoleName 'Contributor'
        )
        $script:UpAnswers = @{ $script:UpGone = New-UpNotFound -Id $script:UpGone; $script:UpNowhere = New-UpNotFound -Id $script:UpNowhere }
        $W = $null; $Info = $null; $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
        @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)|$($_.principalStatus)" }) | Should -Be @(
            "Reader|$($script:UpGone)|User|Deleted"
            "Contributor|$($script:UpNowhere)|Group|Unresolved"
        )
        @($W).Count | Should -Be 1
        [string]$W[0].Message | Should -BeExactly (Get-UpWarningText -Count 2)
        $Records = @($Info | Where-Object { $_.Tags -contains $script:UpTag })
        $Records.Count | Should -Be 1
        @($Records[0].MessageData.Assignments | ForEach-Object { "$($_.Role)|$($_.PrincipalType)|$($_.PrincipalStatus)|$($_.StatusRead)" }) | Should -Be @(
            'Reader|User|Deleted|True'
            'Contributor|Group|Unresolved|True'
        )
        (Get-UpPartial -Record @($InvErr)).Count | Should -Be 0
    }

    It 'reports a failed lookup as unread: the object id with principalType, no principalStatus, no deleted items read, and InventoryPartial with the cause' {
        $script:UpRas = @(New-UpRa -PrincipalId $script:UpUser -PrincipalType 'User')
        $script:UpAnswers = @{ $script:UpUser = New-UpUnread -Id $script:UpUser -Cause 'Too many requests (429)' }
        $W = $null; $Info = $null; $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
        $Ra = @($Inv.roleAssignments)
        @($Ra[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        "$($Ra[0].principal)|$($Ra[0].principalType)" | Should -Be "$($script:UpUser)|User"
        $Partial = Get-UpPartial -Record @($InvErr)
        $Partial.Count | Should -Be 1
        [string]$Partial[0].TargetObject | Should -BeExactly "roleAssignments/Reader -> $($script:UpUser) @ $($script:UpSub)/principal"
        $Partial[0].Exception.Message | Should -BeLike '*Could not look up the principal of a role assignment through directoryObjects/getByIds: Too many requests (429)*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        @($W).Count | Should -Be 0
        @($Info | Where-Object { $_.Tags -contains $script:UpTag }).Count | Should -Be 0
    }

    It 'reads a principal the lookup gave no answer for as a failed lookup, never as one the directory did not return' {
        $script:UpRas = @(New-UpRa -PrincipalId $script:UpUser -PrincipalType 'User')
        $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningAction SilentlyContinue -ErrorVariable InvErr -ErrorAction SilentlyContinue
        @($Inv.roleAssignments)[0].PSObject.Properties.Name | Should -Not -Contain 'principalStatus'
        $Partial = Get-UpPartial -Record @($InvErr)
        [string]$Partial[0].TargetObject | Should -BeExactly "roleAssignments/Reader -> $($script:UpUser) @ $($script:UpSub)/principal"
        $Partial[0].Exception.Message | Should -BeLike '*through directoryObjects/getByIds: the lookup returned no answer for this principal.*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'writes principalStatus Unresolved and names the status unread with its cause when the deleted items read fails, and still counts the row' {
        $script:UpRas = @(New-UpRa -PrincipalId $script:UpDenied -PrincipalType 'ServicePrincipal')
        $script:UpAnswers = @{ $script:UpDenied = New-UpNotFound -Id $script:UpDenied }
        $W = $null; $InvErr = $null; $Info = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -ErrorVariable InvErr -ErrorAction SilentlyContinue -InformationVariable Info
        $Ra = @($Inv.roleAssignments)
        "$($Ra[0].principal)|$($Ra[0].principalType)|$($Ra[0].principalStatus)" | Should -Be "$($script:UpDenied)|ServicePrincipal|Unresolved"
        $Partial = Get-UpPartial -Record @($InvErr)
        $Partial.Count | Should -Be 1
        [string]$Partial[0].TargetObject | Should -BeExactly "roleAssignments/Reader -> $($script:UpDenied) @ $($script:UpSub)/principalStatus"
        $Partial[0].Exception.Message | Should -BeLike "*Could not read whether the principal of a role assignment is among the directory's deleted items: Insufficient privileges to complete the operation.*"
        [string]$W[0].Message | Should -BeExactly (Get-UpWarningText -Count 1)
        # The record says the status was not read, so no reason is given for it as a fact.
        $Row = @(@($Info | Where-Object { $_.Tags -contains $script:UpTag })[0].MessageData.Assignments)[0]
        "$($Row.PrincipalStatus)|$($Row.StatusRead)" | Should -Be 'Unresolved|False'
        $Row.StatusRead | Should -BeOfType ([bool])
    }

    It 'writes a device by its object id with no principalType and no principalStatus when the directory returned it, and with principalStatus when it did not' {
        # Written by its display name, with no principalType, the device would be applied as a group of
        # that name (the engine's heuristic for a principal with no '@').
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpDevice -PrincipalType 'Device'
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'Device' -RoleName 'Owner'
        )
        $script:UpAnswers = @{
            $script:UpDevice = New-UpFound -Id $script:UpDevice -Name 'Kiosk 7' -ObjectType 'device'
            $script:UpGone   = New-UpNotFound -Id $script:UpGone
        }
        $W = $null; $Info = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue -InformationVariable Info
        $Ra = @($Inv.roleAssignments)
        @($Ra[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal')
        $Ra[0].principal | Should -BeExactly $script:UpDevice
        @($Ra[1].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalStatus')
        "$($Ra[1].principal)|$($Ra[1].principalStatus)" | Should -Be "$($script:UpGone)|Deleted"
        # The record names the ARM type as it is, since principalType cannot.
        @(@($Info | Where-Object { $_.Tags -contains $script:UpTag })[0].MessageData.Assignments | ForEach-Object { $_.PrincipalType }) | Should -Be @('Device')
    }

    It 'reads each principal among the deleted items once per call, and again in the next call' {
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User'
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User' -RoleName 'Owner'
        )
        $script:UpAnswers = @{ $script:UpGone = New-UpNotFound -Id $script:UpGone }
        $First = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningAction SilentlyContinue
        @($First.roleAssignments | ForEach-Object { $_.principalStatus }) | Should -Be @('Deleted', 'Deleted')
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
        $null = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
    }

    It 'under an export run context: hands the unread entries and causes to the context, raises no InventoryPartial of its own, and reads each principal among the deleted items once for every call' {
        # The export calls this command once per scope with -ErrorAction Stop, where an InventoryPartial of
        # its own would skip the whole scope: the scope's rows must still be written.
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpUser -PrincipalType 'User'
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User' -RoleName 'Owner'
            New-UpRa -PrincipalId $script:UpDenied -PrincipalType 'User' -RoleName 'Contributor'
        )
        $script:UpAnswers = @{
            $script:UpUser   = New-UpUnread -Id $script:UpUser -Cause 'Too many requests (429)'
            $script:UpGone   = New-UpNotFound -Id $script:UpGone
            $script:UpDenied = New-UpNotFound -Id $script:UpDenied
        }
        $Run = Invoke-UpAsExport -Scope @($script:UpSub, $script:UpSub2)
        # Both calls wrote every row.
        @($Run.Inventory).Count | Should -Be 2
        foreach ($One in $Run.Inventory) {
            @($One.roleAssignments | ForEach-Object { "$($_.principal)|$($_.principalStatus)" }) | Should -Be @(
                "$($script:UpUser)|"
                "$($script:UpGone)|Deleted"
                "$($script:UpDenied)|Unresolved"
            )
        }
        (Get-UpPartial -Record @($Run.Errors)).Count | Should -Be 0
        # The unread entries of both calls, in the order found, and a cause for each.
        @($Run.Context.UnreadPrincipal) | Should -Be @(
            "roleAssignments/Reader -> $($script:UpUser) @ $($script:UpSub)/principal"
            "roleAssignments/Contributor -> $($script:UpDenied) @ $($script:UpSub)/principalStatus"
            "roleAssignments/Reader -> $($script:UpUser) @ $($script:UpSub)/principal"
            "roleAssignments/Contributor -> $($script:UpDenied) @ $($script:UpSub)/principalStatus"
        )
        @($Run.Context.UnreadPrincipalCause | ForEach-Object { "$($_.Target)|$($_.Cause)" }) | Should -Be @(
            "$($script:UpUser)|Could not look up the principal of a role assignment through directoryObjects/getByIds: Too many requests (429)"
            "$($script:UpDenied)|Could not read whether the principal of a role assignment is among the directory's deleted items: Insufficient privileges to complete the operation."
            "$($script:UpUser)|Could not look up the principal of a role assignment through directoryObjects/getByIds: Too many requests (429)"
            "$($script:UpDenied)|Could not read whether the principal of a role assignment is among the directory's deleted items: Insufficient privileges to complete the operation."
        )
        # One read of UpGone for the export, kept in the context; the failed read of UpDenied is read again.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpGone)" }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -ceq "v1.0/directory/deletedItems/$($script:UpDenied)" }
        @($Run.Context.PrincipalStatus.Keys) | Should -Be @($script:UpGone.ToLowerInvariant())
        $Run.Context.PrincipalStatus[$script:UpGone].Status | Should -Be 'Deleted'
    }

    It 'leaves a root-scope row whose principal was not found, or could not be looked up, in the root list only: no deleted items read, no count, nothing unread' {
        $script:UpRas = @(
            New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User' -RoleName 'User Access Administrator' -Scope '/'
            New-UpRa -PrincipalId $script:UpUser -PrincipalType 'User' -RoleName 'Owner' -Scope '/'
        )
        $script:UpAnswers = @{ $script:UpGone = New-UpNotFound -Id $script:UpGone; $script:UpUser = New-UpUnread -Id $script:UpUser -Cause 'Too many requests (429)' }
        $W = $null; $Info = $null; $InvErr = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningVariable W -WarningAction SilentlyContinue `
            -InformationVariable Info -ErrorVariable InvErr -ErrorAction SilentlyContinue
        @($Inv.roleAssignments).Count | Should -Be 0
        # Reach proof: both rows reached the root list, by their object ids.
        @(@($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment' })[0].MessageData.Assignments | ForEach-Object { $_.Principal }) |
            Sort-Object | Should -Be @($script:UpUser, $script:UpGone | Sort-Object)
        @($Info | Where-Object { $_.Tags -contains $script:UpTag }).Count | Should -Be 0
        @($W | Where-Object { [string]$_.Message -like '*principalStatus*' }).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        (Get-UpPartial -Record @($InvErr)).Count | Should -Be 0
    }

    It 'stops at its warning under -WarningAction Stop, before it returns the inventory' {
        $script:UpRas = @(New-UpRa -PrincipalId $script:UpGone -PrincipalType 'User')
        $script:UpAnswers = @{ $script:UpGone = New-UpNotFound -Id $script:UpGone }
        $script:UpOut = $null
        $Thrown = { $script:UpOut = Get-OERInventory -Include RoleAssignments -Scope $script:UpSub -IncludeARM -WarningAction Stop } | Should -Throw -PassThru
        $Thrown.Exception.Message | Should -BeLike '*role assignment(s) name a principal the directory did not return*'
        $null -eq $script:UpOut | Should -BeTrue
        # Reach proof: the principal was looked for among the deleted items before the warning.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'states the rule in the help' {
        $Help = (Get-Help Get-OERInventory -Full | Out-String) -replace '\s+', ' '
        $Help | Should -Match ([regex]::Escape('principalStatus'))
        $Help | Should -Match ([regex]::Escape('Omnicit.EntraRBAC.UnresolvedPrincipal'))
        $Help | Should -Match ([regex]::Escape('principalType is written for every role assignment whose principal type is a user, a group (a ForeignGroup included) or a service principal'))
        # The case is named for what it is, and the read counts claim no more than holds.
        $Help | Should -Match ([regex]::Escape('A principal the directory did not return is written by its object id with principalStatus'))
        $Help | Should -Match ([regex]::Escape('in batches of up to 1000 ids, one request per batch'))
        $Help | Should -Match ([regex]::Escape('an answer that was read is kept for the rest of the call, and under Export-OERInventory for the rest of the export, while a read that fails is not kept and is sent again for the next role assignment that needs it'))
        $Help | Should -Match ([regex]::Escape('its principal is looked up like any other, which is how the root list names it, but it is not looked for among the deleted items, and a failed lookup of it is not reported'))
        # -Prune removes such an assignment only at a scope the document still declares.
        $Help | Should -Match ([regex]::Escape('Invoke-OERStructure never creates it, and removing the entry lets -Prune remove it, like any undeclared assignment, at a scope the document still declares.'))
        $Help | Should -Not -Match ([regex]::Escape('nothing about its principal is read'))
        $Help | Should -Not -Match ([regex]::Escape('one batched directoryObjects/getByIds request per call'))
    }
}

Describe 'Get-OERInventory groups section, total enumeration failure' {
    # A SEPARATE top-level Describe on purpose. The Describe above mocks Get-OERGroup in its
    # BeforeEach and Pester has no un-mock, so the real cmdlet -- and the real catch that republishes
    # its failure -- can only run outside it.
    #
    # WHAT THIS PINS. Get-OERInventory now warns at section level only for a record Get-OERGroup
    # itself PUBLISHED, telling it apart from the Graph SDK strays the engine also drops into
    # -ErrorVariable, which are routed to verbose. The per-collection failures are already covered
    # both ways above. Nothing covered the case that must STILL warn: the whole enumeration failing.
    # Behaviour is correct today. If that catch ever stopped publishing, or published a record that
    # does not carry the cmdlet name into the FullyQualifiedErrorId, the section warning would
    # silently become a verbose line and the export would report an empty groups section with no
    # warning at all -- the exact shape issue #76 is about. Both were mutated and both turn this
    # red. Measured while doing so, and worth knowing before a refactor: rewriting the catch as
    # `Write-Error -ErrorRecord $PSItem` does NOT break it, since PowerShell appends the enclosing
    # advanced function's name to the id either way. The dangerous refactor is a helper that writes
    # the record from its OWN scope, which appends the HELPER's name instead.
    #
    # Invoke-MgGraphRequest is mocked, not Invoke-OERGraphRequest, so the REAL wrapper, the REAL
    # Convert-GraphHttpException and the REAL Get-OERGroup catch all run. Mocking the wrapper would
    # skip the republish this test exists to measure.
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        # Default arm: anything the section reaches for other than the groups enumeration answers
        # empty, so an unexpected call cannot be mistaken for the failure under test.
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @() } }
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest -ParameterFilter { $Uri -like 'v1.0/groups*' } -MockWith {
            # No HttpRequestMessage TargetObject here: this fixture measures the WARNING path, and
            # the bearer scrub has its own suite. The JSON body is what a real 403 returns, so
            # Convert-GraphHttpException derives 'Authorization_RequestDenied' as the error id -- the
            # cmdlet name Get-OERInventory tests for is appended by WriteError, not by this mock.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
    }

    It 'still warns at section level when the whole groups enumeration fails' {
        $Inv = Get-OERInventory -Include Groups -WarningVariable Warned -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Non-vacuity first, in the order that makes a later regression legible. A missing warning
        # and a fixture that never reached the transport render identically in the assertion below.
        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest `
            -ParameterFilter { $Uri -like 'v1.0/groups*' } -Times 1 -Exactly
        $Inv | Should -Not -BeNullOrEmpty
        @($Inv.groups).Count | Should -Be 0 -Because 'a failed enumeration yields no groups, which is exactly why the warning has to survive'

        $Matched = @($Warned | Where-Object { $_ -match 'Could not read groups' })
        @($Matched).Count |
            Should -Be 1 -Because 'a total enumeration failure is the one groups error that must still reach the operator as a section warning'
        [string]$Matched[0] |
            Should -Match 'Authorization_RequestDenied' -Because 'the transport reason must survive into the warning, or the operator cannot tell a 403 from a 429'
    }

    It 'routes the Graph SDK strays behind that same failure to verbose, not to a second warning' {
        # The companion half: exactly one warning, and the count is asserted against the SAME run
        # that produced it. A live run raised eight spurious records for one failed read.
        $Warnings = @(Get-OERInventory -Include Groups -ErrorAction SilentlyContinue 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

        @($Warnings | Where-Object { $_.Message -match 'Could not read groups' }).Count |
            Should -Be 1 -Because 'one failed enumeration is one finding, however many records the engine collected for it'
    }
}

Describe 'Get-OERInventory does not provoke a PimPolicyNotFound for a group that is not onboarded' {
    # THE USER-VISIBLE COMPLAINT. A clean Get-OERInventory -Include Groups flooded the caller's
    # -ErrorVariable. Most groups in a real tenant are not onboarded to PIM for Groups, and reading
    # a policy that does not exist made Get-OERGroupPimPolicy correctly report PimPolicyNotFound --
    # which -ErrorAction Stop turned into TWO records per call, FOUR per group. Measured offline on
    # 100 groups with 96 not onboarded, driving the real wrapper and real cmdlets with only the
    # transport stubbed: 384 records for a read in which nothing was wrong. That collection is
    # filled by the ENGINE, so no catch in this module can empty it; the only fix is not to provoke
    # the records, which is why the section now asks whether a policy exists before reading one.
    #
    # A SEPARATE top-level Describe: the Describe above mocks Get-OERPimGroupPolicyId in its
    # BeforeEach and Pester has no un-mock, so the not-onboarded answer can only be arranged here.
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{
                Id = 'g-1'; DisplayName = 'role_sec_team'; IsAssignableToRole = $false
                GroupType = 'Assigned'; Description = $null; MailNickname = $null
                Members = @(); Owners = @(); PimEligibility = @()
            }
        }
        # These cases pin the policy-id pre-check and the read behind it, which the section reaches
        # only for a group Test-OERGroupPimInUse reports in use -- so it answers in use here.
        Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x' } }
        # BL-131: the root default mock of the group name index is gone here -- this Describe imports
        # the module again, and a mock lives in the module instance it was made in -- so it is made
        # again, with the same answer: an index that was read and holds no name.
        Mock -ModuleName $script:moduleName Get-OERGroupNameIndex { & $script:NewEmptyGroupNameIndex }
    }

    It 'never calls Get-OERGroupPimPolicy at all when the group has no policy id' {
        # $null from Get-OERPimGroupPolicyId is the not-onboarded answer, and it is now a SILENT
        # one: that helper declares ResourceTypeNotSupported to the transport, so it raises nothing.
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
        Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { }

        $Err = $null
        $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err

        @($Err).Count | Should -Be 0 -Because 'a tenant whose groups are simply not PIM-onboarded is not a tenant with 384 problems'
        Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 0 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 2 -Exactly
        # The projection is unchanged: a group with no PIM policy projects exactly as before, which
        # is to say with no pimPolicy key at all.
        $Group = @($Inv.groups)[0]
        $Group | Should -Not -BeNullOrEmpty
        $Group.displayName | Should -Be 'role_sec_team'
        $Group.PSObject.Properties.Name -contains 'pimPolicy' | Should -BeFalse
    }

    It 'still reads the policy, and still projects it, when the group HAS one' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
        Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
            [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = $null
                ActivationEnabledRules = @('Justification'); AllowPermanentEligibility = $false
                EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                ActiveEnabledRules = @(); Rules = @(); Notifications = $null }
        }

        $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 2 -Exactly
        $Group = @($Inv.groups)[0]
        $Group.PSObject.Properties.Name -contains 'pimPolicy' | Should -BeTrue
        $Group.pimPolicy.member.activationMaxHours | Should -Be 8
    }

    It 'still runs the read, so a genuine failure keeps its diagnostic, when the pre-check throws' {
        # THE REASON -ErrorAction Ignore was rejected at the read below. A 403 on the policy-id
        # lookup is NOT "no policy" -- it is "you were not allowed to ask". Treating a throw as an
        # answer would quietly drop PIM policy the operator has no permission to read out of the
        # document. Anything other than a confident $null therefore falls through to the read.
        #
        # THE MOCK RAISES THE SHAPE THE REAL CMDLET RAISES, which the first version of this test did
        # not: it threw a bare [System.Exception], a shape Get-OERGroupPimPolicy never produces, so
        # it proved nothing about the id the inventory actually has to discriminate on. The real
        # cmdlet WRITES a non-terminating record and the -ErrorAction Stop at the call site turns it
        # terminating, so the id that arrives here reads 'PimPolicyReadFailed,Get-OERGroupPimPolicy'.
        # That is the whole discrimination: 'PimPolicyNotFound,...' is suppressed, this one is not.
        # The end-to-end Describe below drives the REAL cmdlet chain with only the transport stubbed
        # and does not depend on this shape being right; both are kept on purpose.
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, 'g-1')
        }
        Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
            Write-Error -Message "Could not read the PIM-for-groups policy assignment for group 'g-1': Authorization_RequestDenied: Insufficient privileges" `
                -ErrorId 'PimPolicyReadFailed' -Category ReadError -TargetObject 'g-1' -ErrorAction Stop
        }

        $Err = $null
        $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err

        Should -Invoke -ModuleName $script:moduleName Get-OERGroupPimPolicy -Times 2 -Exactly
        $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
        @($Partial).Count |
            Should -Be 1 -Because 'a read the operator was refused must still be reported, not silently skipped'
        [string]$Partial[0].Exception.Message | Should -Match 'pimPolicy/member'
        [string]$Partial[0].Exception.Message | Should -Match 'pimPolicy/owner'
        [string]$Partial[0].Exception.Message | Should -Match 'Authorization_RequestDenied'
        @($Inv.groups)[0].PSObject.Properties.Name -contains 'pimPolicy' |
            Should -BeFalse -Because 'a policy nobody was allowed to read is omitted, never written as an empty block'
    }

    It 'stays silent for the id the real cmdlet raises when the group is simply not onboarded' {
        # The other half of the same discrimination, in the same shape. If the -like test at the call
        # site were ever widened to swallow both ids again, the test above goes red; if it were
        # narrowed to swallow neither, this one does.
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('transport hiccup on the pre-check only'), 'GraphHttpError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
        }
        Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy {
            Write-Error -Message "Group 'g-1' has no PIM-for-groups policy for 'member' access." `
                -ErrorId 'PimPolicyNotFound' -Category ObjectNotFound -TargetObject 'g-1' -ErrorAction Stop
        }

        $Err = $null
        $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err

        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
            Should -Be 0 -Because 'a group that was never onboarded is not a finding and must not make the document partial'
        @($Inv.groups)[0].PSObject.Properties.Name -contains 'pimPolicy' | Should -BeFalse
    }
}

Describe 'Get-OERInventory PIM policy, driven end to end with only the transport stubbed' {
    <#
        WHY THIS EXISTS SEPARATELY FROM THE MOCKED SUITE ABOVE. Every assertion above mocks
        Get-OERGroupPimPolicy or Get-OERPimGroupPolicyId, so all of them measure a shape a test
        author chose. The defect this suite pins was invisible to exactly that: the previous version
        of the pre-check test mocked Get-OERGroupPimPolicy to throw a bare [System.Exception], a
        shape the real cmdlet never produces, and passed while a real 403 on 96 of 100 groups
        produced 0 error records, 0 warnings and pimPolicy silently absent from all 96 -- an
        inventory that looked complete and was not (issue #76's defect class).

        Only Invoke-MgGraphRequest is replaced here, so the REAL wrapper, the REAL
        Convert-GraphHttpException, the REAL Get-OERPimGroupPolicyId and the REAL
        Get-OERGroupPimPolicy all run, and both halves of InvokeMgGraphRequest.cs are modelled so
        the -ExpectedErrorCode soft path and the raising path are both reachable.

        THE TWO CASES ARE ONE PAIR AND NEITHER IS SUFFICIENT ALONE. The healthy case pins that a
        tenant whose groups are simply not PIM-onboarded stays completely silent; the refused case
        pins that the failure reaches the caller instead. A fix that only satisfies one of them is
        the defect in one direction or the other.
    #>
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'measures zero error records when 96 of 100 groups are simply not PIM-onboarded' {
        InModuleScope $script:moduleName {
            try {
                # The stub is written out in full in each case rather than shared, matching the
                # pattern the Get-OERGroup suite already uses: a scriptblock built in the TEST's
                # session state and installed into the module's function table resolves its own
                # variables in the wrong session state, so what reads as one shared fixture would
                # quietly become two different ones.
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $U = [string]$Uri
                    $Index = 0
                    if ($U -match '(\d{8})-0000-0000-0000-000000000000') { $Index = [int]$Matches[1] }
                    $Onboarded = ($Index -ge 1 -and $Index -le 4)
                    $NotOnboarded = '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
                    if ($U -match 'eligibilityScheduleInstances') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(@{ id = "e$Index"; accessId = 'member'; principalId = "p$Index" }) }
                        }
                        # Both halves of InvokeMgGraphRequest.cs, verbatim:
                        #   if (ShouldCheckHttpStatus && !isSuccess) { ThrowTerminatingError(...) }
                        #   await ProcessResponseAsync(httpResponseMessage);
                        # with ShouldCheckHttpStatus => !SkipHttpErrorCheck. Modelling both is what
                        # keeps the fixture honest when -ExpectedErrorCode is added or removed.
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotOnboarded) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotOnboarded | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicyAssignments') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(
                                    @{ roleDefinitionId = 'member'; policyId = "pol-m-$Index" }
                                    @{ roleDefinitionId = 'owner'; policyId = "pol-o-$Index" })
                            }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotOnboarded) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotOnboarded | ConvertFrom-Json -AsHashtable)
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ($U -match 'roleManagementPolicies\?') {
                        # The PIM-in-use criterion's listing. Graph lists a member and an owner
                        # policy for EVERY group, untouched ones included, exactly as Learn shows an
                        # untouched group policy. The onboarded four are in use through their
                        # eligibility and never ask; the other 96 are not in use at all.
                        return @{ value = @(
                                @{ id = "Group_m_$Index"; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } }
                                @{ id = "Group_o_$Index"; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } })
                        }
                    }
                    if ($U -match 'roleManagementPolicies/.+/rules') {
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') })
                        }
                    }
                    if ($U -match '/members|/owners|getByIds|/directoryObjects') { return @{ value = @() } }
                    if ($U -match '^v1\.0/groups') {
                        return @{ value = @(1..100 | ForEach-Object {
                                    @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $PSItem); displayName = "g$PSItem"
                                        securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                        description = $null; mailNickname = "g$PSItem"
                                    }
                                })
                        }
                    }
                    return @{ value = @() }
                }

                $Err = $null
                $Warned = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err `
                    -WarningAction SilentlyContinue -WarningVariable Warned

                # The record count comes FIRST: it is the number this whole design exists to hold at
                # zero, and Pester reports the first failing assertion.
                @($Err).Count |
                    Should -Be 0 -Because 'a tenant whose groups are merely not PIM-onboarded is not a tenant with problems'
                @($Warned).Count | Should -Be 0

                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 100
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'eligibility' }).Count |
                    Should -Be 100 -Because 'a not-onboarded group has genuinely no eligibility, and that is a read which SUCCEEDED'
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' }).Count |
                    Should -Be 4 -Because 'only the onboarded four have a policy to project'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'surfaces the refusal, and omits pimPolicy, when the policy-id lookup answers 403' {
        InModuleScope $script:moduleName {
            try {
                # The healthy fixture with the policy-assignment lookup answering 403
                # Authorization_RequestDenied for the 96 groups that answered 400
                # ResourceTypeNotSupported there before. The eligibility endpoint is untouched, so
                # anything that moves below is the policy path and nothing else. The PIM-in-use
                # criterion's listing reports every policy MODIFIED here, and succeeds: that is what
                # sends the 96 on to the lookup this case refuses. A group the criterion reports not
                # in use never reaches it (the healthy case), and a refused criterion is its own case
                # below.
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $U = [string]$Uri
                    $Index = 0
                    if ($U -match '(\d{8})-0000-0000-0000-000000000000') { $Index = [int]$Matches[1] }
                    $Onboarded = ($Index -ge 1 -and $Index -le 4)
                    $NotOnboarded = '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
                    $Forbidden = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'
                    if ($U -match 'eligibilityScheduleInstances') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(@{ id = "e$Index"; accessId = 'member'; principalId = "p$Index" }) }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotOnboarded) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotOnboarded | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicyAssignments') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(
                                    @{ roleDefinitionId = 'member'; policyId = "pol-m-$Index" }
                                    @{ roleDefinitionId = 'owner'; policyId = "pol-o-$Index" })
                            }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($Forbidden) }
                        Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                        return ($Forbidden | ConvertFrom-Json -AsHashtable)
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ($U -match 'roleManagementPolicies\?') {
                        return @{ value = @(
                                @{ id = "Group_m_$Index"; lastModifiedDateTime = '2026-01-01T00:00:00Z'; lastModifiedBy = @{ id = $null; displayName = 'Person One' } }
                                @{ id = "Group_o_$Index"; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } })
                        }
                    }
                    if ($U -match 'roleManagementPolicies/.+/rules') {
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') })
                        }
                    }
                    if ($U -match '/members|/owners|getByIds|/directoryObjects') { return @{ value = @() } }
                    if ($U -match '^v1\.0/groups') {
                        return @{ value = @(1..100 | ForEach-Object {
                                    @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $PSItem); displayName = "g$PSItem"
                                        securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                        description = $null; mailNickname = "g$PSItem"
                                    }
                                })
                        }
                    }
                    return @{ value = @() }
                }

                $Err = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err

                # Surfacing first, for the same reason the count comes first above: this is the
                # assertion the change exists to move, and the measured behaviour it replaced was
                # zero records of any kind.
                $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
                @($Partial).Count |
                    Should -Be 1 -Because 'a refusal on 96 groups must reach the caller, not vanish as "no policy"'
                [string]$Partial[0].Exception.Message |
                    Should -Match 'Authorization_RequestDenied' -Because 'the operator has to tell a scope they must grant from a throttle they must wait out'
                [string]$Partial[0].Exception.Message | Should -Match 'pimPolicy/member'

                @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'PimPolicyReadFailed*' }).Count |
                    Should -BeGreaterThan 0 -Because 'the cmdlet that could not read the policy must say so in its own words too'
                @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' }).Count |
                    Should -Be 0 -Because 'reporting a refused lookup as an absent policy is the defect itself'

                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 100
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' }).Count |
                    Should -Be 4 -Because 'a policy nobody was allowed to read is OMITTED, exactly as Get-OERGroup omits PimEligibility'
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' -and -not $_.pimPolicy }).Count |
                    Should -Be 0 -Because 'omitted, never present-and-empty -- a failed read is not an empty fact'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'leaves no error record, and exports no pimPolicy, when the PIM-in-use listing answers 404 ResourceNotFound' {
        InModuleScope $script:moduleName {
            try {
                # The criterion declares a 404 ResourceNotFound on its listing as the answer "PIM does
                # not know this group", so the REAL wrapper must hand it back as a marker with nothing
                # raised: the caller's -ErrorVariable stays empty and the group is simply not in use.
                # Three groups: the first is eligible (in use without asking), the other two answer
                # the listing with 404. Both halves of InvokeMgGraphRequest.cs are modelled, as above.
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $U = [string]$Uri
                    $Index = 0
                    if ($U -match '(\d{8})-0000-0000-0000-000000000000') { $Index = [int]$Matches[1] }
                    $Onboarded = ($Index -eq 1)
                    $NotOnboarded = '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
                    $NotFound = '{"error":{"code":"ResourceNotFound","message":"The resource could not be found."}}'
                    if ($U -match 'eligibilityScheduleInstances') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(@{ id = "e$Index"; accessId = 'member'; principalId = "p$Index" }) }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotOnboarded) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotOnboarded | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicies\?') {
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotFound) }
                        Set-Variable -Name $StatusCodeVariable -Value 404 -Scope 1
                        return ($NotFound | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicyAssignments') {
                        if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                        return @{ value = @(
                                @{ roleDefinitionId = 'member'; policyId = "pol-m-$Index" }
                                @{ roleDefinitionId = 'owner'; policyId = "pol-o-$Index" })
                        }
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ($U -match 'roleManagementPolicies/.+/rules') {
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') })
                        }
                    }
                    if ($U -match '/members|/owners|getByIds|/directoryObjects') { return @{ value = @() } }
                    if ($U -match '^v1\.0/groups') {
                        return @{ value = @(1..3 | ForEach-Object {
                                    @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $PSItem); displayName = "g$PSItem"
                                        securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                        description = $null; mailNickname = "g$PSItem"
                                    }
                                })
                        }
                    }
                    return @{ value = @() }
                }

                $Err = $null
                $Warned = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err `
                    -WarningAction SilentlyContinue -WarningVariable Warned

                @($Err).Count |
                    Should -Be 0 -Because 'a 404 on the listing is the declared answer for a group PIM does not know, not a failure'
                @($Warned).Count | Should -Be 0
                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 3
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' } | ForEach-Object { $_.displayName }) |
                    Should -Be @('g1') -Because 'only the eligible group is in use; the two PIM does not know carry no pimPolicy'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'leaves no error record, reports nothing unread, and exports no pimPolicy, when the PIM-in-use listing answers 400 ResourceTypeNotSupported' {
        InModuleScope $script:moduleName {
            try {
                # Microsoft Learn: a dynamic group and a group synchronized from on-premises cannot be
                # managed in PIM for Groups, and Graph answers 400 ResourceTypeNotSupported for them on
                # this family of endpoints. The criterion declares that code as the answer "not in use",
                # exactly as the eligibility read and the policy-id lookup already do, so the REAL
                # wrapper hands it back as a marker: nothing is raised, nothing is reported unread, and
                # the export is not InventoryPartial on account of such a group. Three groups: the
                # first is eligible (in use without asking), the other two answer 400 everywhere.
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $U = [string]$Uri
                    $Index = 0
                    if ($U -match '(\d{8})-0000-0000-0000-000000000000') { $Index = [int]$Matches[1] }
                    $Onboarded = ($Index -eq 1)
                    $NotSupported = '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
                    if ($U -match 'eligibilityScheduleInstances') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(@{ id = "e$Index"; accessId = 'member'; principalId = "p$Index" }) }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotSupported) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotSupported | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicies\?') {
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotSupported) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotSupported | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicyAssignments') {
                        $script:PolicyLookups.Add($Index)
                        if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                        return @{ value = @(
                                @{ roleDefinitionId = 'member'; policyId = "pol-m-$Index" }
                                @{ roleDefinitionId = 'owner'; policyId = "pol-o-$Index" })
                        }
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ($U -match 'roleManagementPolicies/.+/rules') {
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') })
                        }
                    }
                    if ($U -match '/members|/owners|getByIds|/directoryObjects') { return @{ value = @() } }
                    if ($U -match '^v1\.0/groups') {
                        return @{ value = @(1..3 | ForEach-Object {
                                    @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $PSItem); displayName = "g$PSItem"
                                        securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                        description = $null; mailNickname = "g$PSItem"
                                    }
                                })
                        }
                    }
                    return @{ value = @() }
                }
                $script:PolicyLookups = [System.Collections.Generic.List[int]]::new()

                $Err = $null
                $Warned = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err `
                    -WarningAction SilentlyContinue -WarningVariable Warned

                @($Err).Count |
                    Should -Be 0 -Because 'a 400 ResourceTypeNotSupported on the listing is the declared answer for a group PIM for Groups cannot manage, not a failure'
                @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
                    Should -Be 0 -Because 'nothing about such a group is unread'
                @($Warned).Count | Should -Be 0
                @($script:PolicyLookups | Sort-Object -Unique) |
                    Should -Be @(1) -Because 'a group the criterion does not find in use makes no policy call'
                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 3
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' } | ForEach-Object { $_.displayName }) |
                    Should -Be @('g1') -Because 'only the eligible group is in use; the two PIM for Groups cannot manage carry no pimPolicy'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
                Remove-Variable -Name PolicyLookups -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It 'reports pimPolicy unread, and reads no policy, when the PIM-in-use listing answers 403' {
        InModuleScope $script:moduleName {
            try {
                # The healthy fixture with the criterion's own listing refused for the 96 groups
                # without eligibility, driven through the REAL Test-OERGroupPimInUse and the REAL
                # wrapper: the listing declares only a 404 ResourceNotFound and a 400
                # ResourceTypeNotSupported as answers, so a 403 must throw out of the helper and be
                # accounted for, never read as "not in use".
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $U = [string]$Uri
                    $Index = 0
                    if ($U -match '(\d{8})-0000-0000-0000-000000000000') { $Index = [int]$Matches[1] }
                    $Onboarded = ($Index -ge 1 -and $Index -le 4)
                    $NotOnboarded = '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
                    $Forbidden = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'
                    if ($U -match 'eligibilityScheduleInstances') {
                        if ($Onboarded) {
                            if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                            return @{ value = @(@{ id = "e$Index"; accessId = 'member'; principalId = "p$Index" }) }
                        }
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($NotOnboarded) }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return ($NotOnboarded | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicies\?') {
                        if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($Forbidden) }
                        Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                        return ($Forbidden | ConvertFrom-Json -AsHashtable)
                    }
                    if ($U -match 'roleManagementPolicyAssignments') {
                        $script:PolicyLookups.Add($Index)
                        if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                        return @{ value = @(
                                @{ roleDefinitionId = 'member'; policyId = "pol-m-$Index" }
                                @{ roleDefinitionId = 'owner'; policyId = "pol-o-$Index" })
                        }
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ($U -match 'roleManagementPolicies/.+/rules') {
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') })
                        }
                    }
                    if ($U -match '/members|/owners|getByIds|/directoryObjects') { return @{ value = @() } }
                    if ($U -match '^v1\.0/groups') {
                        return @{ value = @(1..100 | ForEach-Object {
                                    @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $PSItem); displayName = "g$PSItem"
                                        securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                        description = $null; mailNickname = "g$PSItem"
                                    }
                                })
                        }
                    }
                    return @{ value = @() }
                }
                $script:PolicyLookups = [System.Collections.Generic.List[int]]::new()

                $Err = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err

                $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
                @($Partial).Count |
                    Should -Be 1 -Because 'a criterion nobody could read must reach the caller, not pass as "not in use"'
                $Unread = @(([string]$Partial[0].TargetObject) -split ', ')
                @($Unread | Where-Object { $_ -match '^groups/g\d+/pimPolicy$' }).Count | Should -Be 96
                $Unread | Should -Contain 'groups/g5/pimPolicy'
                $Unread | Should -Not -Contain 'groups/g1/pimPolicy' -Because 'an eligible group is in use without asking the listing'
                [string]$Partial[0].Exception.Message | Should -Match 'Could not determine whether group'
                [string]$Partial[0].Exception.Message | Should -Match 'Authorization_RequestDenied'
                @($script:PolicyLookups | Sort-Object -Unique) |
                    Should -Be @(1, 2, 3, 4) -Because 'only the four eligible groups reach a policy-id lookup at all'

                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 100
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' }).Count |
                    Should -Be 4 -Because 'a group whose use of PIM for Groups nobody could read exports no pimPolicy'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
                Remove-Variable -Name PolicyLookups -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-OERInventory administrative unit scoped roles, driven with the real readers and only the transport mocked' {
    <#
        WHY THIS EXISTS SEPARATELY FROM THE MOCKED SUITE ABOVE. Every administrative unit test above mocks
        Get-OERAdministrativeUnit, so none of them can say what a failed directory-role NAME map does to an
        export: that failure is raised inside the reader, not by it. Here the REAL Get-OERAdministrativeUnit
        and the REAL Get-OERDirectoryRoleNameMap run and only Invoke-OERGraphRequest answers. A name map
        that cannot be read must reach the inventory as an unread scopedRoles collection (explicit null plus
        InventoryPartial), never as scoped roles whose names silently became role ids.
    #>
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'exports scopedRoles as explicit null and reports it unread, naming the directory roles read, when the name map cannot be read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -eq 'v1.0/directoryRoles') { throw 'TooManyRequests (injected map failure)' }
            if ($Uri -like '*/scopedRoleMembers') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{
                            id = 'srm-1'; administrativeUnitId = '11111111-1111-1111-1111-111111111111'; roleId = 'dirrole-1'
                            roleMemberInfo = [PSCustomObject]@{ id = 'p-1'; displayName = 'Person One' }
                        }) }
            }
            if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
            if ($Uri -eq 'v1.0/directory/administrativeUnits') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AU-One' }) }
            }
            throw "unexpected Graph call $Uri"
        }

        $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue
        $Au = @($Inv.administrativeUnits)[0]

        # Positive proof first: the unit was exported and the name map read was attempted.
        $Au | Should -Not -BeNullOrEmpty
        $Au.displayName | Should -Be 'AU-One'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles'
        }
        $Au.PSObject.Properties.Name -contains 'scopedRoles' | Should -BeTrue
        $null -eq $Au.scopedRoles |
            Should -BeTrue -Because 'an omitted scopedRoles key still reconciles and still prunes, and role ids are not what the name map failed to give'
        $Au.members.Count | Should -Be 0
        $Published = @($InvErr) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory'
        }
        $Msg = @($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })[0].Exception.Message
        $Msg | Should -Match 'administrativeUnits/AU-One/scopedRoles'
        $Msg | Should -Not -Match 'administrativeUnits/AU-One/members'
        $Msg | Should -Match 'v1\.0/directoryRoles'
        $Msg | Should -Match 'injected map failure'
    }

    It 'control: exports the scoped role under its name, and no InventoryPartial, when the name map is readable' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -eq 'v1.0/directoryRoles') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'dirrole-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }) }
            }
            if ($Uri -like '*/scopedRoleMembers') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{
                            id = 'srm-1'; administrativeUnitId = '11111111-1111-1111-1111-111111111111'; roleId = 'dirrole-1'
                            roleMemberInfo = [PSCustomObject]@{ id = 'p-1'; displayName = 'Person One' }
                        }) }
            }
            if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
            if ($Uri -eq 'v1.0/directory/administrativeUnits') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AU-One' }) }
            }
            throw "unexpected Graph call $Uri"
        }

        $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue
        $Au = @($Inv.administrativeUnits)[0]

        $Au | Should -Not -BeNullOrEmpty
        @($Au.scopedRoles).Count | Should -Be 1
        $Au.scopedRoles[0].role | Should -Be 'User Administrator'
        $Au.scopedRoles[0].principal | Should -Be 'p-1'
        @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
    }

    It 'falls back to the role id, with no InventoryPartial, when the name map is readable but does not name the role' {
        # The reader does not check that every membership's role id is listed, so a readable list can
        # still lack a live role's id (not seen live; this is the defensive case). That role is not
        # unread: the export names it by its id, which the apply engine accepts as a GUID declaration,
        # and nothing is reported partial.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -eq 'v1.0/directoryRoles') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'dirrole-other'; roleTemplateId = 'tmpl-other'; displayName = 'Reports Reader' }) }
            }
            if ($Uri -like '*/scopedRoleMembers') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{
                            id = 'srm-1'; administrativeUnitId = '11111111-1111-1111-1111-111111111111'; roleId = 'dirrole-1'
                            roleMemberInfo = [PSCustomObject]@{ id = 'p-1'; displayName = 'Person One' }
                        }) }
            }
            if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
            if ($Uri -eq 'v1.0/directory/administrativeUnits') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AU-One' }) }
            }
            throw "unexpected Graph call $Uri"
        }

        $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable InvErr -ErrorAction SilentlyContinue
        $Au = @($Inv.administrativeUnits)[0]

        # Positive proof first: the unit was exported and the name map was read.
        $Au | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles'
        }
        @($Au.scopedRoles).Count | Should -Be 1
        $Au.scopedRoles[0].role | Should -BeExactly 'dirrole-1'
        $Au.scopedRoles[0].principal | Should -BeExactly 'p-1'
        @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
    }
}

Describe 'an application binding with no readable name round-trips by its object id' {
    # BL-06 / decision A10, the acceptance test: an access package binding whose resource name the
    # export cannot read is written under the application's OBJECT ID, and that exported entry is
    # applied back, through the real Sync-OERStructureAccessPackage, as the SAME binding -- not as a
    # refusal, a failure or a binding to remove. Before the fix the entry carried an empty resource,
    # which the validator now refuses and which would have thrown at apply. Every id below is a
    # placeholder, none of it version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Get-OERCatalog {
            [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT-Core'; Description = 'Core' }
        }
        Mock -ModuleName $script:moduleName Get-OERAccessPackage {
            [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; IsHidden = $false; CatalogId = 'cat-1' }
        }
        # Export side: the name map is READ, and it does not hold the binding's origin id.
        Mock -ModuleName $script:moduleName Get-OERCatalogResource {
            [PSCustomObject]@{ Id = 'res-x'; OriginId = 'orig-x'; DisplayName = 'role_sec_x'; OriginSystem = 'AadGroup'; ResourceType = 'Group' }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { $M = @{}; foreach ($I in $Id) { $M[$I] = 'role_sec_x' }; $M }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
            [PSCustomObject]@{ ResourceDisplayName = $null; RoleName = 'Member'; OriginId = '22222222-2222-2222-2222-222222222222'; OriginSystem = 'AadApplication' }
        }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
    }

    It 'applies the exported entry as an already bound binding, removing and adding nothing, under -Prune' {
        $Inv = Get-OERInventory -Include AccessPackages -ErrorAction SilentlyContinue -ErrorVariable InvErr
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -Exactly
        @(@($InvErr) | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count |
            Should -Be 0 -Because 'the application is named by its object id, so nothing was left unread'
        $Exported = @($Inv.accessPackages)[0]
        @($Exported.resourceRoles).Count | Should -Be 1
        $Exported.resourceRoles[0].resource | Should -BeExactly '22222222-2222-2222-2222-222222222222'

        # What a file on disk gives the apply engine: the document written and read back.
        $Entry = @((@($Inv.accessPackages) | ConvertTo-Json -Depth 12 -AsArray) | ConvertFrom-Json)[0]
        $Entry.resourceRoles[0].resource | Should -BeExactly '22222222-2222-2222-2222-222222222222'

        InModuleScope $script:moduleName -Parameters @{ Entry = $Entry } {
            param($Entry)
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune
            }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'Sales'; IsHidden = $false } }
            # The live catalog DOES list the application resource, under the origin id the entry names.
            Mock Get-OERCatalogResource {
                [PSCustomObject]@{ Id = 'res-app'; DisplayName = 'App One'; OriginId = '22222222-2222-2222-2222-222222222222'; OriginSystem = 'AadApplication' }
            }
            # Resolve-OERGroupId is deliberately NOT mocked: a GUID is returned verbatim with no Graph
            # call, which is the path that decides here.
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{ id = 'b-live-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Add-OERAccessPackageResourceRole { }
            Mock Remove-OERAccessPackageResourceRole { }

            $Published = $null
            $r = @(Invoke-SyncApViaCaller -Item $Entry -Prune -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

            # Positive proof first: the binding rows were reached and read. The export's own read of
            # the catalog (by id) is in the same mock history, so the apply's read is told apart by
            # the catalog NAME the entry carries.
            Should -Invoke Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT-IT-Core' }
            @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on '22222222-2222-2222-2222-222222222222' already bound" }).Count |
                Should -Be 1 -Because 'the exported object id is matched against the catalog resource origin id, so the binding is the live one'
            @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
            @($r | Where-Object { $_.Detail -like 'would remove*' }).Count | Should -Be 0
            Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            Should -Invoke Add-OERAccessPackageResourceRole -Times 0
        }
    }
}

Describe 'Get-OERInventory groups section, read through the real Get-OERGroup' {
    # A SEPARATE top-level Describe: the 'Get-OERInventory' Describe mocks Get-OERGroup in its
    # BeforeEach and Pester has no un-mock, so the real cmdlet -- and through it the real
    # Get-OERGroupRelation -- can only run here. Only the transport is answered.
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        # BL-131: imported again HERE, so the root default mocks are gone whether or not a Describe
        # above ran (a filtered run skips them): the real Get-OERGroupNameIndex has to run below,
        # through the transport, and the root mock of it would answer instead.
        Import-Module $script:moduleName -Force
        # BL-125: the root default mock of the PIM for Groups assignment read is gone too -- a mock
        # lives in the module instance it was made in -- so it is made again here, with the same
        # answer: a read that lists nothing, so the members and owners below read as standing.
        Mock -ModuleName $script:moduleName Read-OERGroupPimAssignment {
            [PSCustomObject]@{ Read = $true; Value = @(); Message = $null; Exception = $null }
        }
    }

    Context 'a service principal only the typed read lists is exported by its id' {
        # Microsoft Graph v1.0 groups/{id}/members and groups/{id}/owners leave service principals
        # out (measured 2026-10-06); the typed .../microsoft.graph.servicePrincipal read lists them,
        # without an @odata.type annotation. A service principal has no userPrincipalName, so the
        # export writes it by its object id.
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{} }
            # The group does not use PIM for Groups, so no policy read is reached.
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $false; Reason = 'x'; Manageable = $true } }
            # Any request the fixture does not answer fails its read visibly.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true
                            isAssignableToRole = $false; groupTypes = @(); description = $null; mailNickname = $null }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups?$filter=securityEnabled%20eq%20true' }
            # BL-131: the one listing of every group in the tenant the shared names are counted over,
            # answered through the transport so the real Get-OERGroupNameIndex reads it: the tenant
            # holds the one group, so its name is unique.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups?$select=id,displayName&$top=999' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }
        }

        It 'exports the service principal member once and the service principal owner, both by object id' {
            $Err = $null
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue

            # Positive identity first: the group was exported and nothing was reported unread.
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count | Should -Be 0
            $Groups = @($Inv.groups)
            $Groups.Count | Should -Be 1
            $Groups[0].displayName | Should -Be 'role_sec_team'

            @($Groups[0].members).Count | Should -Be 2
            @($Groups[0].members)[0] | Should -Be 'g-nested'
            @(@($Groups[0].members) | Where-Object { $_ -eq 'sp-1' }).Count | Should -Be 1
            @($Groups[0].owners) | Should -Contain 'sp-1'
            @($Groups[0].owners).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' -and $All
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' -and $All
            }
        }

        It 'lists every group''s name once through the transport, and leaves out the group a Microsoft 365 group shares its name with (BL-131)' {
            # The listing of every group in the tenant holds a second group, outside the security
            # listing, that carries the name in another letter case.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team' }
                        @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'ROLE_SEC_TEAM' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups?$select=id,displayName&$top=999' }
            $Err = $null
            $Info = $null
            $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -InformationVariable Info
            @($Inv.groups).Count | Should -Be 0
            $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
            $Partial.Count | Should -Be 1
            [string]$Partial[0].TargetObject | Should -BeExactly 'groups/role_sec_team'
            $Partial[0].Exception.Message | Should -BeLike '*Causes: 2 live objects share the name groups/role_sec_team (compared without regard to letter case)*'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -like 'v1.0/groups?$select=*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                $Uri -ceq 'v1.0/groups?$select=id,displayName&$top=999' -and $All
            }
            $Notice = @($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' })
            $Notice.Count | Should -Be 1
            ($Notice[0].MessageData.Names | ForEach-Object { "$($_.Section)|$($_.Name)|$($_.Count)" }) | Should -BeExactly 'groups|role_sec_team|2'
        }

        Context 'a failed typed read leaves the collection unread' {
            # The typed read fails AFTER the untyped read succeeded. The group is exported with the
            # collection stated as unread, never as the half the untyped read listed: a members key
            # is an explicit null (which the apply engine reads as leave untouched), an owners key
            # is omitted (which it never reconciles), and InventoryPartial names the collection.
            # The mocks carry the same exact-URI filter as the BeforeEach's; defined later, they win.
            It 'exports members as an explicit null and names groups/role_sec_team/members as unread when the typed members read fails' {
                Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }

                $Err = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue

                # Positive identity first: the group was exported, and the typed read was reached.
                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 1
                $Groups[0].displayName | Should -Be 'role_sec_team'
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' -and $All
                }
                # Present as a key, with the value null: not omitted, not an empty or half list.
                $Groups[0].PSObject.Properties.Name -contains 'members' | Should -BeTrue
                $null -eq $Groups[0].members | Should -BeTrue
                # The owners were read whole and are exported.
                (@($Groups[0].owners) -join ',') | Should -Be 'sp-1'

                $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
                $Partial.Count | Should -Be 1
                $Partial[0].Exception.Message | Should -BeLike '*Unread: groups/role_sec_team/members. A section*'
            }

            It 'omits owners and names groups/role_sec_team/owners as unread when the typed owners read fails' {
                # A user owner the untyped read lists: were the half exported, owners would hold it.
                Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                    @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) }
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }

                $Err = $null
                $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue

                $Groups = @($Inv.groups)
                $Groups.Count | Should -Be 1
                $Groups[0].displayName | Should -Be 'role_sec_team'
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' -and $All
                }
                $Groups[0].PSObject.Properties.Name -contains 'owners' | Should -BeFalse
                # The members were read whole and are exported.
                (@($Groups[0].members) -join ',') | Should -Be 'g-nested,sp-1'

                $Partial = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
                $Partial.Count | Should -Be 1
                $Partial[0].Exception.Message | Should -BeLike '*Unread: groups/role_sec_team/owners. A section*'
            }
        }
    }
}

Describe 'Get-OERInventory tenantId (BL-88, A14)' {
    # The export names the tenant the session's Graph token was issued for (TokenTenantId, through
    # Get-OERInventoryTenantId), never the tenant as the caller named it. The mocked sign-in below
    # sets the module's auth state itself, the way the real one does, so the capture time is the real
    # one: after Initialize-OERAuth in the begin block.
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Get-OERGroup { }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{
                    TenantId      = 'contoso.onmicrosoft.com'
                    TokenTenantId = '44444444-4444-4444-4444-444444444444'
                }
            }
        }
    }

    AfterAll {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    It 'writes the tenant the Graph token was issued for as tenantId, never the tenant as named' {
        $Inv = Get-OERInventory -Include Groups -TenantId 'contoso.onmicrosoft.com' -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
        $Inv.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Inventory'
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        @($Inv.PSObject.Properties.Name)[0..2] | Should -Be @('version', 'tenantId', 'groups')
    }

    It 'leaves tenantId out, with no warning, when the token reported no tenant ID' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{ TenantId = '11111111-1111-1111-1111-111111111111'; TokenTenantId = $null }
            }
        }
        $Inv = Get-OERInventory -Include Groups -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
        $Inv.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Inventory'
        $Inv.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
        @($Inv.PSObject.Properties.Name)[0..1] | Should -Be @('version', 'groups')
        @($Warn).Count | Should -Be 0 -Because 'the export just leaves tenantId out and says nothing; a session whose token reports no tenant ID is refused only by the apply, for a document that names a tenant'
    }

    It 'leaves tenantId out when the session holds no state' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        $Inv = Get-OERInventory -Include Groups -WarningVariable Warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
        $Inv.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
        @($Warn).Count | Should -Be 0
    }

    It 'captures the tenant in begin, directly after the sign-in, not when the document is assembled' {
        # A read that finds the session's token tenant changed while the section is read must still
        # yield the tenant the command signed in under: the capture happens in begin.
        Mock -ModuleName $script:moduleName Get-OERGroup {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState.TokenTenantId = '77777777-7777-7777-7777-777777777777'
            }
        }
        $Inv = Get-OERInventory -Include Groups -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Reach proof: the section read ran, and it did change the module's state under the command.
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -Exactly
        InModuleScope $script:moduleName {
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '77777777-7777-7777-7777-777777777777'
        }
        $Inv.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
    }

    It 'writes a tenantId that serializes to a document the shipped schema accepts' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        $Inv = Get-OERInventory -Include Groups -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $Json = $Inv | ConvertTo-Json -Depth 32
        $Json | Should -Match '"tenantId":\s*"44444444-4444-4444-4444-444444444444"'
        Test-Json -Json $Json -Schema (InModuleScope $script:moduleName { Get-OERStructureSchemaJson }) -ErrorAction SilentlyContinue |
            Should -Be $true
    }

    It 'names the tenant of the session each call signed in under' {
        $First = Get-OERInventory -Include Groups -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{ TenantId = 'fabrikam.onmicrosoft.com'; TokenTenantId = '77777777-7777-7777-7777-777777777777' }
            }
        }
        $Second = Get-OERInventory -Include Groups -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        $First.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
        $Second.tenantId | Should -BeExactly '77777777-7777-7777-7777-777777777777'
    }
}

Describe 'Get-OERInventory help documents the tenantId (BL-88, A14)' {
    It 'says what tenantId names, what Invoke-OERStructure does with it, and when it is left out' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Get-OERInventory -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '

        $Description | Should -Match ([regex]::Escape("The inventory carries a top-level tenantId, directly after its version: the tenant ID the session's Microsoft Graph token was issued for, never the tenant as named with -TenantId"))
        $Description | Should -Match ([regex]::Escape('Invoke-OERStructure applies the document only in that tenant and refuses it anywhere else with DocumentTenantMismatch.'))
        $Description | Should -Match ([regex]::Escape('the key is left out, with no warning, and the document carries no tenant check.'))
        $Description | Should -Match ([regex]::Escape("To use the inventory as a template for another tenant, change its tenantId to that tenant's ID or remove the key."))

        $Param = @($Help.Parameters.Parameter) | Where-Object { $_.Name -eq 'TenantId' }
        $Param | Should -Not -BeNullOrEmpty
        $ParamText = ((@($Param.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $ParamText | Should -Match ([regex]::Escape("The inventory's tenantId is the tenant ID the session's Microsoft Graph token was issued for, not this value."))
    }
}

Describe 'Get-OERInventory help documents the subscriptions of another tenant (BL-150, A19)' {
    It 'says it reads a scope in a subscription of another tenant, unlike the export''s walk, that Invoke-OERStructure refuses one, and that a management group row read there as inherited is not checked' {
        # Whitespace collapsed first, so the assertion does not depend on where the prose wraps.
        $Help = Get-Help Get-OERInventory -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '

        $Description | Should -Match ([regex]::Escape("This cmdlet reads the Azure scope it is given, a scope in a subscription of another tenant included (it does not check a subscription's home tenant, while Export-OERInventory's Azure walk enters only the subscriptions of the tenant the session's Microsoft Graph token was issued for), and Invoke-OERStructure refuses a role assignment or a role management policy at a scope in a subscription of another tenant with SubscriptionTenantMismatch."))
        # A row read at such a subscription as inherited from a management group above it is not checked
        # (docs/development/rationale.md#home-tenant-subscriptions, limit (c)).
        $Description | Should -Match ([regex]::Escape('A role assignment row that an inventory of such a subscription carries at a management group above it, read at the subscription as inherited, lies in no subscription and is not checked: Invoke-OERStructure applies it like any management group row.'))
    }
}
