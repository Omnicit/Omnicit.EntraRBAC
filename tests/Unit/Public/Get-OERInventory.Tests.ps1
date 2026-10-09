BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
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
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'anna@contoso.com' } }
        }

        It 'projects role and principal as names (D6) and omits principalType for a user' {
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.scope | Should -Be '/subscriptions/sub-1'
            $ra.role | Should -Be 'Reader'
            $ra.principal | Should -Be 'anna@contoso.com'
            $ra.PSObject.Properties.Name | Should -Not -Contain 'principalType'
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
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'sp-1' = 'Contoso SP' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principalType | Should -Be 'ServicePrincipal'
            $ra.principal | Should -Be 'Contoso SP'
        }

        It 'maps a ForeignGroup principal type to Group and omits principalType (round-trip safe)' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = 'Owner'; PrincipalDisplayName = 'Partner Admins'
                    PrincipalType = 'ForeignGroup'; RoleDefinitionId = 'rd'; PrincipalId = 'fg-1'; RoleAssignmentId = 'ra-fg'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'fg-1' = 'Partner Admins' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principal | Should -Be 'Partner Admins'
            $ra.PSObject.Properties.Name | Should -Not -Contain 'principalType'
        }

        It 'falls back to ids when names are unresolved' {
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment {
                [PSCustomObject]@{
                    Scope = '/subscriptions/sub-1'; RoleName = $null; PrincipalDisplayName = $null
                    PrincipalType = 'User'; RoleDefinitionId = 'rd-full'; PrincipalId = 'p-1'; RoleAssignmentId = 'ra-1'
                }
            }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'p-1' } }
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
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'u-9' = 'anna@contoso.com' } }
            $ra = (Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM).RoleAssignments[0]
            $ra.principal | Should -Be 'anna@contoso.com'
            $ra.PSObject.Properties.Name | Should -Not -Contain 'principalType'
        }
    }

    Context 'roleAssignments condition and description projection' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'p-1' = 'user@contoso.com' } }
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
            Mock -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy { @() }
            Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:DupRoleAssignments }
            Mock -ModuleName $script:moduleName Get-OERRoleManagementPolicy { $script:DupPolicies }
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                param([string[]]$Id)
                $Map = @{}
                foreach ($One in @($Id)) {
                    if ($script:DupNames.ContainsKey($One)) { $Map[$One] = $script:DupNames[$One] }
                }
                $Map
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
            $Partial[0].Exception.Message | Should -Match 'Two or more live objects share the name groups/Dup'
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
            @($Inv.roleAssignments | ForEach-Object { "$($_.role)|$($_.principal)|$($_.principalType)" }) | Should -Be @(
                "Reader|$($script:DupGrp1)|Group"
                "Reader|$($script:DupGrp2)|Group"
                'Reader|person1@example.com|'
            )
            @($Inv.roleAssignments)[2].PSObject.Properties.Name | Should -Not -Contain 'principalType'
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'puts principalType directly after principal, so the entry keeps its key order' {
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Ops'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @(@($Inv.roleAssignments)[0].PSObject.Properties.Name) | Should -Be @('scope', 'role', 'principal', 'principalType')
        }

        It 'counts two scope spellings that differ in letter case as one scope when it looks for a collision' {
            # Azure Resource Manager never returns a scope with a trailing '/', and the validator refuses
            # one in a document (A15), so the spellings here differ in letter case only.
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Ops' -Scope $script:DupSub1.ToUpperInvariant()
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @($script:DupGrp1, $script:DupGrp2)
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'leaves two principals that share a name at DIFFERENT scopes alone' {
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops' }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Ops' -Scope "$($script:DupSub1)/resourceGroups/rg-one"
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments).Count | Should -Be 2
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @('Ops', 'Ops')
            Assert-DupDocumentValid -Inventory $Inv
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
            # The third group is called by the FIRST group's object id. Naming the first two groups by
            # id makes the third one collide with the first, so the third has to move on a second pass.
            $script:DupNames = @{ $script:DupGrp1 = 'Ops'; $script:DupGrp2 = 'Ops'; $script:DupGrp3 = $script:DupGrp1 }
            $script:DupRoleAssignments = @(
                New-DupRoleAssignment -PrincipalId $script:DupGrp1 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp2 -PrincipalType 'Group' -PrincipalName 'Ops'
                New-DupRoleAssignment -PrincipalId $script:DupGrp3 -PrincipalType 'Group' -PrincipalName 'Third'
            )
            $Inv = Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
            @($Inv.roleAssignments | ForEach-Object { $_.principal }) | Should -Be @($script:DupGrp1, $script:DupGrp2, $script:DupGrp3)
            Assert-DupDocumentValid -Inventory $Inv
        }

        It 'names the full role definition id when two roles of one name still collide after the principal is an id' {
            # One user holds two different role definitions that carry the same display name. The
            # principal moves to its id first, which does not separate them, so the role moves too.
            $script:DupNames = @{ $script:DupUser1 = 'person1@example.com' }
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
            $Cause = 'Get-OERInventory: Two or more live objects share the name groups/Dup (compared without regard to letter case), so none of them is written: the apply engine refuses an ambiguous name.'
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
            @([regex]::Matches($Message, 'Two or more live objects share the name')).Count | Should -Be 1 -Because 'the second collision has the same cause, so it is not stated again'
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
            # Raise the numbers here and $UnreadCauseCap together, or a whole shape can be crowded
            # out of the clause purely by the order the sections run in.
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
            # name equals a user's UPN in the same role and kind collides the same way. The user, and a
            # same-named group holding a DIFFERENT role, keep their names.
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
                    'Fixture Role B|Fixture Group|Group'
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
