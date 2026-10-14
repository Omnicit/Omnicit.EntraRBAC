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

# A cross-cutting suite named after no single function: it exports the two Microsoft Entra
# directory-role sections from ONE mocked live state with Get-OERInventory and applies them back
# through Invoke-OERStructure, asserting that every row is Unchanged. Export and apply see the same
# objects, because the mocks sit at the cmdlet level (the readers, the resolvers and the writers);
# everything between them -- Select-OERManagedDirectoryRoleAssignment, the projection helpers, the
# validator, both Sync-OERStructure* handlers and their diff helpers -- runs for real. The transport
# is stubbed to throw, so any read the fixture does not answer fails loudly instead of passing.
# It runs with a session (BL-101): a state the test sets for one tenant, with Initialize-OERAuth
# still mocked, so the export names that tenant (tenantId, Get-OERInventoryTenantId) and the apply
# compares it with the session's (Get-OERDocumentTenantMismatch, after the mocked sign-in). The
# export applied under another tenant is refused with DocumentTenantMismatch, reading and writing
# nothing. No id below is version-4 shaped.
Describe 'Directory role inventory round trip' {
    BeforeAll {
        # The tenant the session is set for, and the one the refusal test moves it to.
        $script:Tenant = 'ffffffff-0000-0000-0000-000000000001'
        $script:OtherTenant = 'ffffffff-0000-0000-0000-000000000002'
        $script:RoleA = '11111111-1111-1111-1111-111111111111'
        $script:RoleB = '22222222-2222-2222-2222-222222222222'
        $script:User1 = 'aaaaaaaa-0000-0000-0000-000000000001'
        $script:User2 = 'aaaaaaaa-0000-0000-0000-000000000002'
        $script:User3 = 'aaaaaaaa-0000-0000-0000-000000000003'
        $script:User4 = 'aaaaaaaa-0000-0000-0000-000000000004'
        $script:Group1 = 'bbbbbbbb-0000-0000-0000-000000000001'
        $script:Sp1 = 'cccccccc-0000-0000-0000-000000000001'
        $script:ApproverUser = 'dddddddd-0000-0000-0000-000000000001'
        $script:ApproverGroup = 'dddddddd-0000-0000-0000-000000000002'
        $script:StaleApprover = 'dddddddd-0000-0000-0000-000000000003'
        $script:SignedIn = 'eeeeeeee-0000-0000-0000-000000000001'

        # Role reference (display name or id) -> role definition id, for the resolver mock.
        $script:RoleIdByReference = @{
            'Reports Reader'      = $script:RoleA
            'Fixture Custom Role' = $script:RoleB
            $script:RoleA         = $script:RoleA
            $script:RoleB         = $script:RoleB
        }
        # Object id -> the name Resolve-OERPrincipalName gives it (a UPN for a user, the display name
        # for a group). User4 is deliberately absent: its name does not resolve, so the export names
        # it by its object id. The service principal is absent too: it is never named.
        $script:NameById = @{
            $script:User1  = 'person1@example.com'
            $script:User2  = 'person2@example.com'
            $script:User3  = 'person3@example.com'
            $script:Group1 = 'Fixture Eligible Group'
        }
        # Principal reference (UPN, group name or object id) -> object id, for the apply resolver mock.
        $script:PrincipalIdByReference = @{
            'person1@example.com'    = $script:User1
            'person2@example.com'    = $script:User2
            'person3@example.com'    = $script:User3
            'Fixture Eligible Group' = $script:Group1
        }
        foreach ($One in $script:User1, $script:User2, $script:User3, $script:User4, $script:Group1, $script:Sp1) {
            $script:PrincipalIdByReference[$One] = $One
        }

        # One Microsoft Graph schedule, the raw shape the two readers receive, so the fixture rows go
        # through the real ConvertTo-OERDirectoryRoleAssignment and their DurationDays is exactly
        # what the readers would report for the window.
        function script:New-GraphSchedule {
            param(
                [string]$Id, [string]$RoleId, [string]$RoleName, [string]$PrincipalId, [string]$ODataType,
                [string]$MemberType = 'Direct', [string]$AssignmentType,
                [string]$Start = '2026-01-01T00:00:00Z', [object]$End
            )
            $Schedule = [ordered]@{
                id               = $Id
                roleDefinitionId = $RoleId
                principalId      = $PrincipalId
                directoryScopeId = '/'
                memberType       = $MemberType
                status           = 'Provisioned'
                createdDateTime  = $Start
                scheduleInfo     = [PSCustomObject]@{
                    startDateTime = $Start
                    expiration    = [PSCustomObject]@{
                        type        = $(if ($End) { 'afterDateTime' } else { 'noExpiration' })
                        endDateTime = $End
                    }
                }
                principal        = [PSCustomObject]@{ '@odata.type' = $ODataType; displayName = 'fixture' }
                roleDefinition   = [PSCustomObject]@{ displayName = $RoleName }
            }
            if ($AssignmentType) { $Schedule.assignmentType = $AssignmentType }
            [PSCustomObject]$Schedule
        }

        # The raw rule set of one directory role policy, so the fixture policies go through the real
        # ConvertTo-OERRoleManagementPolicy and its Graph approver reader.
        function script:New-GraphPolicyRules {
            param(
                [bool]$RequireApproval, [object[]]$Approvers = @(), [string]$AuthenticationContext,
                [bool]$PermanentEligibility, [string[]]$EndUserRules = @('Justification')
            )
            @(
                [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @($EndUserRules) }
                [PSCustomObject]@{ id = 'Enablement_Admin_Assignment'; enabledRules = @('Justification') }
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = (-not $PermanentEligibility); maximumDuration = 'P365D' }
                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $true; maximumDuration = 'P180D' }
                [PSCustomObject]@{
                    id      = 'Approval_EndUser_Assignment'
                    setting = [PSCustomObject]@{
                        isApprovalRequired = $RequireApproval
                        approvalStages     = @([PSCustomObject]@{ primaryApprovers = @($Approvers) })
                    }
                }
                [PSCustomObject]@{
                    id         = 'AuthenticationContext_EndUser_Assignment'
                    isEnabled  = [bool]$AuthenticationContext
                    claimValue = $AuthenticationContext
                }
            )
        }

        # Role A (built-in-looking name):
        #   E1 eligible, person1, time-bound 30 days
        #   E2 eligible, a group, permanent
        #   E3 eligible, person3 through that group (group-inherited: never exported)
        #   E4 eligible, a user whose name does not resolve, time-bound 30.5 days
        #   A1 active, a service principal, permanent (named by object id)
        #   A2 active, person1's ACTIVATION of E1 (never exported)
        # Role B: A3 active, person2, time-bound 29.6 days (only an active assignment).
        # The two fractional windows pin durationDays to the reconstruction the apply engine uses
        # (Resolve-OEREligibilityDuration): 29.6 rounds to 30, and 30.5 rounds away from zero to 31.
        $RawEligible = @(
            New-GraphSchedule -Id 'schedule-e1' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:User1 -ODataType '#microsoft.graph.user' -End '2026-01-31T00:00:00Z'
            New-GraphSchedule -Id 'schedule-e2' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:Group1 -ODataType '#microsoft.graph.group'
            New-GraphSchedule -Id 'schedule-e3' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:User3 -ODataType '#microsoft.graph.user' -MemberType 'Group'
            New-GraphSchedule -Id 'schedule-e4' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:User4 -ODataType '#microsoft.graph.user' -End '2026-01-31T12:00:00Z'
        )
        $RawActive = @(
            New-GraphSchedule -Id 'schedule-a1' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:Sp1 -ODataType '#microsoft.graph.servicePrincipal' -AssignmentType 'Assigned'
            New-GraphSchedule -Id 'schedule-a2' -RoleId $script:RoleA -RoleName 'Reports Reader' -PrincipalId $script:User1 -ODataType '#microsoft.graph.user' -AssignmentType 'Activated' -Start '2026-02-01T09:00:00Z' -End '2026-02-01T17:00:00Z'
            New-GraphSchedule -Id 'schedule-a3' -RoleId $script:RoleB -RoleName 'Fixture Custom Role' -PrincipalId $script:User2 -ODataType '#microsoft.graph.user' -AssignmentType 'Assigned' -End '2026-01-30T14:24:00Z'
        )
        # Role A: approval on, one user and one group approver, authentication context c1 (the live
        # MFA flag is still set, which the export drops in favour of the context).
        $RulesA = New-GraphPolicyRules -RequireApproval $true -AuthenticationContext 'c1' -EndUserRules @('MultiFactorAuthentication', 'Justification') -Approvers @(
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $script:ApproverUser; description = 'Fixture Approver' }
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $script:ApproverGroup; description = 'Fixture Approvers' }
        )
        # Role B: default-like -- approval off with a stale approver still listed, permanent
        # eligibility allowed, eligibility capped at 365 days.
        $RulesB = New-GraphPolicyRules -RequireApproval $false -PermanentEligibility $true -Approvers @(
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $script:StaleApprover; description = 'Fixture Former Approver' }
        )

        $Converted = InModuleScope $script:moduleName -Parameters @{
            RawEligible = $RawEligible; RawActive = $RawActive; RulesA = $RulesA; RulesB = $RulesB
            RoleA = $script:RoleA; RoleB = $script:RoleB
        } {
            param($RawEligible, $RawActive, $RulesA, $RulesB, $RoleA, $RoleB)
            [PSCustomObject]@{
                Eligible = @($RawEligible | ConvertTo-OERDirectoryRoleAssignment -Kind Eligible)
                Active   = @($RawActive | ConvertTo-OERDirectoryRoleAssignment -Kind Active)
                Policies = @(
                    ConvertTo-OERRoleManagementPolicy -Rules $RulesA -PolicyId 'DirectoryRole_fixture_a' -Scope '/' `
                        -RoleName 'Reports Reader' -RoleDefinitionId $RoleA -ApproverShape Graph
                    ConvertTo-OERRoleManagementPolicy -Rules $RulesB -PolicyId 'DirectoryRole_fixture_b' -Scope '/' `
                        -RoleName 'Fixture Custom Role' -RoleDefinitionId $RoleB -ApproverShape Graph
                )
            }
        }
        $script:LiveEligible = @($Converted.Eligible)
        $script:LiveActive = @($Converted.Active)
        $script:LivePolicies = @($Converted.Policies)

        # Exports, then serializes the sections the way a bundle does: tenantId directly after version
        # and only when the inventory carries it (Get-OERInventory leaves the key out when the session's
        # token reports no tenant ID), then the two directory sections.
        function script:Export-DirectoryDocument {
            $Inv = Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ErrorAction Stop
            $Doc = [ordered]@{ version = '1.0' }
            if ($Inv.PSObject.Properties['tenantId']) { $Doc.tenantId = $Inv.tenantId }
            $Doc.directoryRoleManagementPolicies = $Inv.directoryRoleManagementPolicies
            $Doc.directoryRoleAssignments = $Inv.directoryRoleAssignments
            [PSCustomObject]$Doc | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        }

        # Every read mock calls this first. Once the refusal test sets $script:RefuseReads, a read is
        # recorded and refused: the refused document must read nothing, and a read that some layer
        # catches is still on the record.
        function script:Assert-ReadAllowed {
            param([string]$Name)
            if ($script:RefuseReads) {
                $script:ReadsAfterRefusal.Add($Name)
                throw "read after refusal: $Name"
            }
        }
    }

    AfterAll {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    BeforeEach {
        # A session for the fixture tenant, as Initialize-OERAuth would leave it: the export names the
        # tenant its Microsoft Graph token was issued for (TokenTenantId), and the apply compares the
        # document's tenantId with it after the mocked sign-in.
        InModuleScope $script:moduleName -Parameters @{ T = $script:Tenant } {
            param($T)
            $script:_OERAuthState = @{ TenantId = $T; AuthMethod = 'Interactive'; ClientId = ''; Environment = 'Global'; TokenTenantId = $T }
        }
        $script:RefuseReads = $false
        $script:ReadsAfterRefusal = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        # The one transport read answered: the listing of every group's id and display name, which the
        # export reads once to learn whether a group principal's name is unique in the tenant (BL-131,
        # Task 3c; Get-OERGroupNameIndex runs for real). The tenant's groups are the eligible group and
        # the approver group, each of a name no other group carries. Any other request fails loudly.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -eq 'v1.0/groups?$select=id,displayName&$top=999') {
                Assert-ReadAllowed -Name 'groups listing'
                return @{ value = @(
                        @{ id = $script:Group1; displayName = 'Fixture Eligible Group' }
                        @{ id = $script:ApproverGroup; displayName = 'Fixture Approvers' }
                    ) }
            }
            throw "unexpected transport call: $Uri"
        }

        # The readers answer the export (unfiltered) and the apply (filtered by -Role and -PrincipalId)
        # from the same fixture list.
        Mock -ModuleName $script:moduleName Get-OEREligibleDirectoryRoleAssignment {
            Assert-ReadAllowed -Name 'Get-OEREligibleDirectoryRoleAssignment'
            @($script:LiveEligible | Where-Object {
                    (-not $Role -or $_.RoleDefinitionId -eq $Role) -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId)
                })
        }
        Mock -ModuleName $script:moduleName Get-OERActiveDirectoryRoleAssignment {
            Assert-ReadAllowed -Name 'Get-OERActiveDirectoryRoleAssignment'
            @($script:LiveActive | Where-Object {
                    (-not $Role -or $_.RoleDefinitionId -eq $Role) -and (-not $PrincipalId -or $_.PrincipalId -eq $PrincipalId)
                })
        }
        Mock -ModuleName $script:moduleName Get-OERDirectoryRoleManagementPolicy {
            Assert-ReadAllowed -Name 'Get-OERDirectoryRoleManagementPolicy'
            if ($All) { return $script:LivePolicies }
            $RoleId = $script:RoleIdByReference[[string]$Role]
            @($script:LivePolicies | Where-Object { $_.RoleDefinitionId -eq $RoleId })
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            Assert-ReadAllowed -Name 'Resolve-OERPrincipalName'
            $Map = @{}
            foreach ($One in @($Id)) {
                $Map[$One] = $(if ($script:NameById.ContainsKey($One)) { $script:NameById[$One] } else { $One })
            }
            $Map
        }
        Mock -ModuleName $script:moduleName Resolve-OERDirectoryRoleDefinitionId {
            Assert-ReadAllowed -Name 'Resolve-OERDirectoryRoleDefinitionId'
            $script:RoleIdByReference[[string]$Role]
        }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal {
            Assert-ReadAllowed -Name 'Resolve-OERStructurePrincipal'
            $script:PrincipalIdByReference[[string]$Reference]
        }
        Mock -ModuleName $script:moduleName Get-OERSignedInObjectId {
            Assert-ReadAllowed -Name 'Get-OERSignedInObjectId'
            $script:SignedIn
        }
        Mock -ModuleName $script:moduleName Get-OERMemberGroupId { Assert-ReadAllowed -Name 'Get-OERMemberGroupId' }

        # The writers: any call is visible, and none is expected.
        Mock -ModuleName $script:moduleName New-OEREligibleDirectoryRoleAssignment {}
        Mock -ModuleName $script:moduleName New-OERActiveDirectoryRoleAssignment {}
        Mock -ModuleName $script:moduleName Remove-OEREligibleDirectoryRoleAssignment {}
        Mock -ModuleName $script:moduleName Remove-OERActiveDirectoryRoleAssignment {}
        Mock -ModuleName $script:moduleName Set-OERDirectoryRoleManagementPolicy {}
    }

    It 'exports the managed rows and the policies of the roles in use, and nothing else' {
        $Doc = Export-DirectoryDocument
        # The export names the tenant the session's Microsoft Graph token was issued for (BL-88, A14).
        $Doc.tenantId | Should -BeExactly $script:Tenant
        @($Doc.directoryRoleManagementPolicies).role | Should -Be @('Fixture Custom Role', 'Reports Reader')
        @($Doc.directoryRoleAssignments | ForEach-Object {
                "$($_.role)|$($_.assignmentType)|$($_.principal)|$($_.principalType)|$($_.durationDays)"
            }) | Should -Be @(
            "Fixture Custom Role|Active|person2@example.com|User|30"
            "Reports Reader|Eligible|$($script:User4)|User|31"
            'Reports Reader|Eligible|Fixture Eligible Group|Group|'
            'Reports Reader|Eligible|person1@example.com|User|30'
            "Reports Reader|Active|$($script:Sp1)|ServicePrincipal|"
        )
        # The approval-gated policy carries its approvers as object ids and its authentication
        # context instead of the live MFA flag; the approval-off policy carries no approvers.
        $PolicyA = @($Doc.directoryRoleManagementPolicies | Where-Object { $_.role -eq 'Reports Reader' })[0]
        @($PolicyA.approvers.users) | Should -Be @($script:ApproverUser)
        @($PolicyA.approvers.groups) | Should -Be @($script:ApproverGroup)
        $PolicyA.authenticationContextId | Should -BeExactly 'c1'
        $PolicyA.PSObject.Properties.Name | Should -Not -Contain 'requireMfaOnActivation'
        $PolicyB = @($Doc.directoryRoleManagementPolicies | Where-Object { $_.role -eq 'Fixture Custom Role' })[0]
        $PolicyB.PSObject.Properties.Name | Should -Not -Contain 'approvers'
    }

    It 'exports a document the offline validator accepts with no Warning finding' {
        $Doc = Export-DirectoryDocument
        $Validation = InModuleScope $script:moduleName -Parameters @{ Doc = $Doc } {
            param($Doc)
            Test-OERStructureSchema -Document $Doc
        }
        $Validation.Valid | Should -BeTrue
        @($Validation.Errors | Where-Object { $_.Severity -eq 'Warning' } | ForEach-Object { "$($_.Path): $($_.Message)" }) |
            Should -BeNullOrEmpty
        @($Validation.Errors) | Should -BeNullOrEmpty
    }

    It 'applies the export back with every row Unchanged and no write, <Case>' -TestCases @(
        @{ Case = 'without -Prune'; Prune = $false }
        @{ Case = 'with -Prune'; Prune = $true }
    ) {
        $Doc = Export-DirectoryDocument
        $Results = @(Invoke-OERStructure -InputObject $Doc -Prune:$Prune -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)

        # Every row that is not Unchanged, each named with its action and detail, so a failure lists
        # them all rather than stopping at the first.
        @($Results | Where-Object { $_.Action -ne 'Unchanged' } | ForEach-Object { "$($_.Section) '$($_.Item)': $($_.Action) ($($_.Detail))" }) |
            Should -BeNullOrEmpty
        @($Results | Where-Object { $_.Action -eq 'Unchanged' }).Count | Should -Be $Results.Count
        # Exactly one row per exported entry, labelled as the handlers label an entry.
        $ExpectedItems = @(
            @($Doc.directoryRoleManagementPolicies | ForEach-Object { "directoryRoleManagementPolicies|$($_.role)" })
            @($Doc.directoryRoleAssignments | ForEach-Object { "directoryRoleAssignments|$($_.role) -> $($_.principal) ($($_.assignmentType))" })
        )
        $Results.Count | Should -Be 7
        @($Results | ForEach-Object { "$($_.Section)|$($_.Item)" } | Sort-Object) | Should -Be @($ExpectedItems | Sort-Object)
        @($ApplyErr) | Should -BeNullOrEmpty
        @($ApplyWarn) | Should -BeNullOrEmpty

        Should -Invoke -ModuleName $script:moduleName New-OEREligibleDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERActiveDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OEREligibleDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERActiveDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERDirectoryRoleManagementPolicy -Times 0
    }

    It 'refuses the export in another tenant with DocumentTenantMismatch, reading and writing nothing for it' {
        $Doc = Export-DirectoryDocument
        $Doc.tenantId | Should -BeExactly $script:Tenant

        # The session moves to another tenant before the apply: Invoke-OERStructure begins under it, so
        # the pipeline session rule (BL-76) has nothing to refuse, and with the sign-in mocked only the
        # comparison of the document's tenantId with the token's tenant after it stands between this
        # document and a -Prune run in the wrong tenant. From here on every read is recorded and refused.
        InModuleScope $script:moduleName -Parameters @{ T = $script:OtherTenant } {
            param($T)
            $script:_OERAuthState.TenantId = $T
            $script:_OERAuthState.TokenTenantId = $T
        }
        $script:RefuseReads = $true

        $Results = @(Invoke-OERStructure -InputObject $Doc -Prune -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)

        $Results | Should -BeNullOrEmpty -Because 'a refused document is applied to no section'
        $script:ReadsAfterRefusal -join ', ' | Should -BeNullOrEmpty -Because 'nothing is read for a refused document'
        # The command's own record, narrowed by the command that wrote it (rationale #bearer-scrub-tests).
        $Own = @($ApplyErr | Where-Object { $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' })
        $Own.Count | Should -Be 1
        $Own[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch,Invoke-OERStructure'
        $Own[0].Exception.Message | Should -Match ([regex]::Escape("names tenant '$($script:Tenant)'"))
        $Own[0].Exception.Message | Should -Match ([regex]::Escape("issued for tenant '$($script:OtherTenant)'"))
        @($ApplyWarn) | Should -BeNullOrEmpty -Because 'the refusal is an error record, and nothing that could warn runs after it'
        # One sign-in for the export and one for the apply: the refusal is the comparison after the
        # apply's sign-in, since no -TenantId was named for the one before it.
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 2 -Exactly

        Should -Invoke -ModuleName $script:moduleName New-OEREligibleDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName New-OERActiveDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OEREligibleDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Remove-OERActiveDirectoryRoleAssignment -Times 0
        Should -Invoke -ModuleName $script:moduleName Set-OERDirectoryRoleManagementPolicy -Times 0
    }
}
