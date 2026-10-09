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

Describe 'Sync-OERStructureRoleManagementPolicy' {

    It 'leaves the policy Unchanged when all declared fields already match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $false; activationMaxHours = 8 }))
            Should -Invoke Set-OERRoleManagementPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'calls Set-OERRoleManagementPolicy with -AllowPermanentEligibility $true and emits Updated when field differs' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true; activationMaxHours = 8 }))
            Should -Invoke Set-OERRoleManagementPolicy -Times 1 -ParameterFilter { $AllowPermanentEligibility -eq $true }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'calls Set-OERRoleManagementPolicy with -ActivationMaxHours and emits Updated when field differs' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; activationMaxHours = 4 }))
            Should -Invoke Set-OERRoleManagementPolicy -Times 1 -ParameterFilter { $ActivationMaxHours -eq 4 }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'parses subscription:Prod into -Subscription on both Get and Set' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true }))
            Should -Invoke Get-OERRoleManagementPolicy -Times 1 -ParameterFilter { $Subscription -eq 'Prod' }
            Should -Invoke Set-OERRoleManagementPolicy -Times 1 -ParameterFilter { $Subscription -eq 'Prod' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'parses mg:platform into -ManagementGroup on both Get and Set' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/providers/Microsoft.Management/managementGroups/platform'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-mg-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'mg:platform'; role = 'Reader'; allowPermanentEligibility = $true }))
            Should -Invoke Get-OERRoleManagementPolicy -Times 1 -ParameterFilter { $ManagementGroup -eq 'platform' }
            Should -Invoke Set-OERRoleManagementPolicy -Times 1 -ParameterFilter { $ManagementGroup -eq 'platform' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'is Unchanged and does not compare activationMaxHours when only allowPermanentEligibility is declared and it already matches' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $true; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Owner' } }
            Mock Set-OERRoleManagementPolicy {}
            Mock Initialize-OERAuth {}
            # Document only declares allowPermanentEligibility; activationMaxHours is absent.
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Owner'; allowPermanentEligibility = $true }))
            Should -Invoke Set-OERRoleManagementPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'emits Failed and does not call Set when Get-OERRoleManagementPolicy throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { throw 'ARM 403 Forbidden' }
            Mock Set-OERRoleManagementPolicy {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true }) -ErrorAction SilentlyContinue)
            Should -Invoke Set-OERRoleManagementPolicy -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'scrubs the bearer-hygiene record when Get-OERRoleManagementPolicy throws' {
        # Drives the policy-read catch in Sync-OERStructureRoleManagementPolicy. The scrub under
        # test is this handler's OWN -- the Remove-OERErrorRecord opening the handler catch that
        # WRAPS the Get-OERRoleManagementPolicy call, not a scrub inside
        # Get-OERRoleManagementPolicy, which is mocked away here. That mocking is precisely what
        # makes the proof non-vacuous.
        # The failed ARM
        # request behind that read carries the Authorization: Bearer header on its request object.
        # The static AST gate proves the scrub line is WRITTEN first; this It proves it RUNS.
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { throw 'ARM 403 Forbidden' }
            Mock Set-OERRoleManagementPolicy {}
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'under -WhatIf with a pending change emits Skipped and does not call Set' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true }) -WhatIf)
            Should -Invoke Set-OERRoleManagementPolicy -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'emits Failed only (not also Updated) when Set-OERRoleManagementPolicy throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Reader' } }
            Mock Set-OERRoleManagementPolicy { throw 'ARM 500 InternalServerError' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRmpViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; allowPermanentEligibility = $true }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
        }
    }

    Context 'full field reconcile' {
        It 'sends every drifted field to Set-OERRoleManagementPolicy' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy {
                    [PSCustomObject]@{
                        ActivationMaxHours                     = 8
                        RequireMfaOnActivation                 = $false
                        RequireJustificationOnActivation       = $false
                        RequireTicketOnActivation              = $false
                        RequireApproval                        = $false
                        Approvers                              = @()
                        AuthenticationContextId                = $null
                        AllowPermanentEligibility              = $false
                        EligibleDurationDays                   = 365
                        AllowPermanentActiveAssignment         = $false
                        ActiveDurationDays                     = 180
                        RequireMfaOnActiveAssignment           = $false
                        RequireJustificationOnActiveAssignment = $false
                    }
                }
                Mock Set-OERRoleManagementPolicy {}
                Mock Initialize-OERAuth {}
                # Resolve-OERDeclaredApprover now runs before the diff, so a declared group NAME
                # must resolve through Resolve-OERPrincipal. Mocked as an identity pass-through so
                # this test keeps proving the OTHER fields propagate, unrelated to approver id
                # resolution (that is Resolve-OERDeclaredApprover's own test file and the dedicated
                # tests below).
                Mock Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = $Group; PrincipalType = 'Group' } }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    requireMfaOnActivation = $true; requireApproval = $true
                    eligibleDurationDays = 30
                    approvers = [PSCustomObject]@{ groups = @('sec-approvers') }
                }
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item)
                Should -Invoke Set-OERRoleManagementPolicy -Times 1 -ParameterFilter {
                    $RequireMfaOnActivation -eq $true -and
                    $RequireApproval -eq $true -and
                    $EligibleDuration -eq 30 -and
                    @($ApproverGroup) -contains 'sec-approvers' -and
                    $Subscription -eq 'Prod'
                }
                @($Records).Action | Should -Contain 'Updated'
            }
        }

        It 'reports Unchanged when every declared field already matches' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy {
                    [PSCustomObject]@{
                        ActivationMaxHours                     = 8
                        RequireMfaOnActivation                 = $false
                        RequireJustificationOnActivation       = $false
                        RequireTicketOnActivation              = $false
                        RequireApproval                        = $false
                        Approvers                              = @()
                        AuthenticationContextId                = $null
                        AllowPermanentEligibility              = $false
                        EligibleDurationDays                   = 365
                        AllowPermanentActiveAssignment         = $false
                        ActiveDurationDays                     = 180
                        RequireMfaOnActiveAssignment           = $false
                        RequireJustificationOnActiveAssignment = $false
                    }
                }
                Mock Set-OERRoleManagementPolicy {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    activationMaxHours = 8; requireApproval = $false; activeDurationDays = 180
                }
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item)
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
                @($Records).Action | Should -Be @('Unchanged')
            }
        }
    }

    Context 'declared approver resolution' {
        It 'converges when approvers are declared as a UPN and a group name that resolve to the live approver ids' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy {
                    [PSCustomObject]@{
                        ActivationMaxHours = 8
                        RequireMfaOnActivation = $false
                        RequireJustificationOnActivation = $false
                        RequireTicketOnActivation = $false
                        RequireApproval = $true
                        Approvers = @(
                            [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; UserType = 'User'; DisplayName = 'Person One' }
                            [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; UserType = 'Group'; DisplayName = 'Approvers' }
                        )
                        AuthenticationContextId = $null
                        AllowPermanentEligibility = $false
                        EligibleDurationDays = 365
                        AllowPermanentActiveAssignment = $false
                        ActiveDurationDays = 180
                        RequireMfaOnActiveAssignment = $false
                        RequireJustificationOnActiveAssignment = $false
                        Scope = '/subscriptions/sub-1'
                        RoleName = 'Owner'
                    }
                }
                Mock Set-OERRoleManagementPolicy {}
                Mock Initialize-OERAuth {}
                Mock Resolve-OERPrincipal {
                    param($User, $Group)
                    $Map = @{
                        'person1@example.com' = '11111111-1111-1111-1111-111111111111'
                        'Approvers' = '22222222-2222-2222-2222-222222222222'
                    }
                    $Key = if ($User) { $User } else { $Group }
                    [PSCustomObject]@{ PrincipalId = $Map[$Key]; PrincipalType = $(if ($User) { 'User' } else { 'Group' }) }
                }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    requireApproval = $true
                    approvers = [PSCustomObject]@{ users = @('person1@example.com'); groups = @('Approvers') }
                }
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item)
                @($Records).Action | Should -Be @('Unchanged')
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
            }
        }

        It 'reports Failed and changes nothing when a declared approver does not resolve' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Owner'; Approvers = @() } }
                Mock Set-OERRoleManagementPolicy {}
                Mock Initialize-OERAuth {}
                # The record the real Resolve-OERPrincipal throws for a value that matches nothing.
                Mock Resolve-OERPrincipal {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("User 'nobody@example.com' was not found."), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'nobody@example.com')
                }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    requireApproval = $true
                    approvers = [PSCustomObject]@{ users = @('nobody@example.com') }
                }
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
                @($Records).Action | Should -Be @('Failed')
                ($Records[0].Detail) | Should -Match 'could not resolve an approver'
                # The Failed row carries the same $ErrRec whether or not $Caller.WriteError ran, so only
                # the caller's -ErrorVariable proves the record was published. Narrowed to the id AND the
                # handler's own text, exactly one record.
                @($Err | Where-Object {
                        [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' -and
                        $_.Exception.Message -like "*Could not resolve an approver declared for 'Owner'*"
                    }).Count | Should -Be 1
            }
        }

        It 'does not resolve approvers when requireApproval is declared false' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; RequireApproval = $false; Approvers = @(); Scope = '/subscriptions/sub-1'; RoleName = 'Owner' } }
                Mock Set-OERRoleManagementPolicy {}
                Mock Initialize-OERAuth {}
                # The record the real Resolve-OERPrincipal throws for a value that matches nothing (never
                # reached here: requireApproval is false, so no approver is resolved at all).
                Mock Resolve-OERPrincipal {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("User 'nobody@example.com' was not found."), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'nobody@example.com')
                }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    requireApproval = $false
                    approvers = [PSCustomObject]@{ users = @('nobody@example.com') }
                }
                $null = @(Invoke-SyncRmpViaCaller -Item $Item)
                Should -Invoke Resolve-OERPrincipal -Times 0
            }
        }

        It 'sends object ids, not names, to Set-OERRoleManagementPolicy' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERRoleManagementPolicy {
                    [PSCustomObject]@{
                        AllowPermanentEligibility = $false
                        ActivationMaxHours = 8
                        RequireApproval = $false
                        Approvers = @()
                        Scope = '/subscriptions/sub-1'
                        RoleName = 'Owner'
                    }
                }
                Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '11111111-1111-1111-1111-111111111111'; PrincipalType = 'User' } }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Owner'
                    requireApproval = $true
                    approvers = [PSCustomObject]@{ users = @('person1@example.com') }
                }
                $null = @(Invoke-SyncRmpViaCaller -Item $Item)
                Should -Invoke Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApproverUser) -contains '11111111-1111-1111-1111-111111111111' -and
                    @($ApproverUser) -notcontains 'person1@example.com'
                }
            }
        }
    }

    Context 'a declared approver: missing, ambiguous and failed are three outcomes (Sprint 8 step 3, BL-14)' {
        # The real Resolve-OERDeclaredApprover and Resolve-OERPrincipal run here; only the lookups under
        # them answer. Every outcome is one Failed row carrying the record the handler published, and
        # nothing is written. The handler's own record is the one whose id ends in
        # ',Invoke-SyncRmpViaCaller': -ErrorVariable also collects what was thrown inside.
        BeforeEach {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ AllowPermanentEligibility = $false; ActivationMaxHours = 8; Scope = '/subscriptions/sub-1'; RoleName = 'Owner'; RequireApproval = $false; Approvers = @() } }
                Mock Set-OERRoleManagementPolicy {}
                Mock Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'missing-approvers' } { $null }
                Mock Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'dup-approvers' } {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new(
                            "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, " +
                            '22222222-2222-2222-2222-222222222222). Re-run with the object id instead of the display name.'),
                        'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup-approvers')
                }
                Mock Resolve-OERUserId -ParameterFilter { $UserPrincipalName -eq 'person9@example.com' } {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
                }
            }
        }

        It 'reports an approver that matches nothing as ApproverNotFound, with the message, category and target it always had' {
            InModuleScope $script:moduleName {
                $Item = '{ "scope": "subscription:Prod", "role": "Owner", "requireApproval": true, "approvers": { "groups": [ "missing-approvers" ] } }' | ConvertFrom-Json
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($Records).Action | Should -Be @('Failed')
                $Records[0].Detail | Should -Be "could not resolve an approver: Group 'missing-approvers' was not found.; the policy was not changed"
                [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^ApproverNotFound'
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncRmpViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'ApproverNotFound,Invoke-SyncRmpViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
                $Own[0].TargetObject | Should -Be 'Owner @ subscription:Prod'
                $Own[0].Exception.Message | Should -Be "Could not resolve an approver declared for 'Owner' at 'subscription:Prod': Group 'missing-approvers' was not found."
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
            }
        }

        It 'reports an ambiguous approver name as AmbiguousApproverName naming the candidates, never as ApproverNotFound' {
            InModuleScope $script:moduleName {
                $Item = '{ "scope": "subscription:Prod", "role": "Owner", "requireApproval": true, "approvers": { "groups": [ "dup-approvers" ] } }' | ConvertFrom-Json
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($Records).Action | Should -Be @('Failed')
                $Records[0].Detail | Should -Match '11111111-1111-1111-1111-111111111111'
                [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^AmbiguousApproverName'
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncRmpViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'AmbiguousApproverName,Invoke-SyncRmpViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Own[0].TargetObject | Should -Be 'dup-approvers'
                $Own[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
                $Own[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
            }
        }

        It 'reports a failed approver lookup as itself, once, never as ApproverNotFound' {
            InModuleScope $script:moduleName {
                $Item = '{ "scope": "subscription:Prod", "role": "Owner", "requireApproval": true, "approvers": { "users": [ "person9@example.com" ] } }' | ConvertFrom-Json
                $Records = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($Records).Action | Should -Be @('Failed')
                $Records[0].Detail | Should -Match 'Insufficient privileges'
                [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncRmpViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied,Invoke-SyncRmpViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
                Should -Invoke Set-OERRoleManagementPolicy -Times 0
            }
        }

        It 'scrubs a failed approver lookup before it publishes it as itself' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERDeclaredApprover {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
                }
                Mock Remove-OERErrorRecord {}
                $Item = '{ "scope": "subscription:Prod", "role": "Owner", "requireApproval": true, "approvers": { "users": [ "person9@example.com" ] } }' | ConvertFrom-Json
                $null = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the handler published the record as itself.
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Invoke-SyncRmpViaCaller' }).Count | Should -Be 1
                # A prefix match: $Caller.WriteError appends ',<command>' to this same record, in place,
                # before the filter is evaluated.
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    $Record -and [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' -and
                    $Record.Exception.Message -like '*Insufficient privileges*'
                }
            }
        }
    }

    Context 'approvers that name nobody: the plan says what the run does (BL-97, F1)' {
        # One live state for both modes: approval required, approvers one user and one group. A
        # document that declares both approver sides empty is the call Set-OERRoleManagementPolicy
        # refuses with ApproverRequired before anything is sent, so the run reported Failed while the
        # -WhatIf plan said "would update". The handler now reports it Failed before ShouldProcess in
        # both modes. Set-OERRoleManagementPolicy is deliberately NOT mocked in the first two Its: it
        # is the backstop the run reaches when the handler's guard is removed. Invoke-OERArmRequest
        # records every call and refuses a PATCH, so no write can get past unseen.
        BeforeEach {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncRmpViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:RmpArmCalls = [System.Collections.Generic.List[object]]::new()
                Mock Initialize-OERAuth {}
                Mock Get-OERRoleManagementPolicy {
                    [PSCustomObject]@{
                        RequireApproval    = $true
                        ActivationMaxHours = 8
                        Approvers          = @(
                            [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; UserType = 'User'; DisplayName = 'Person One' }
                            [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; UserType = 'Group'; DisplayName = 'Approvers' }
                        )
                        Scope              = '/subscriptions/sub-1'
                        RoleName           = 'Reader'
                    }
                }
                Mock Resolve-OERDeclaredApprover { param($Declared) $Declared }
                Mock Invoke-OERArmRequest {
                    param($Method, $Path, $Body)
                    $script:RmpArmCalls.Add([PSCustomObject]@{ Method = $Method; Path = $Path })
                    if ($Method -eq 'PATCH') { throw 'no ARM write expected' }
                }
            }
        }

        It 'reports the same Failed row with ApproverRequired under -WhatIf and in the run, and sends nothing' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Reader'
                    approvers = [PSCustomObject]@{ users = @(); groups = @() }
                }
                $Plan = @(Invoke-SyncRmpViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue -ErrorVariable PlanErr)
                # Reached: the plan read the live policy once.
                Should -Invoke Get-OERRoleManagementPolicy -Times 1 -Exactly
                $Run = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable RunErr)
                # Reached: the run read it once more.
                Should -Invoke Get-OERRoleManagementPolicy -Times 2 -Exactly

                $Plan.Count | Should -Be 1
                $Plan[0].Action | Should -Be 'Failed'
                $Plan[0].Detail | Should -Match 'ApproverRequired'
                $Run.Count | Should -Be 1
                $Run[0].Action | Should -Be 'Failed'
                $Run[0].Detail | Should -Match 'ApproverRequired'
                $Run[0].Detail | Should -BeExactly $Plan[0].Detail
                [string]$Plan[0].Error.FullyQualifiedErrorId | Should -Match '^ApproverRequired'
                [string]$Run[0].Error.FullyQualifiedErrorId | Should -Match '^ApproverRequired'

                # One ApproverRequired record per mode, the handler's own: the real
                # Set-OERRoleManagementPolicy was never entered, so it published none of its own.
                foreach ($Captured in @(@{ Mode = 'plan'; Err = $PlanErr }, @{ Mode = 'run'; Err = $RunErr })) {
                    $Own = @($Captured.Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverRequired*' })
                    $Own.Count | Should -Be 1 -Because "the $($Captured.Mode) publishes one record"
                    $Own[0].FullyQualifiedErrorId | Should -BeExactly 'ApproverRequired,Invoke-SyncRmpViaCaller'
                    $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                    $Own[0].TargetObject | Should -Be 'Reader @ subscription:Prod'
                    $Own[0].Exception.Message | Should -BeLike "Approval would be required with no approver for 'Reader' at 'subscription:Prod': *"
                }

                # Nothing was sent: no Azure Resource Manager call of any kind.
                Should -Invoke Invoke-OERArmRequest -Times 0
                $script:RmpArmCalls.Count | Should -Be 0
            }
        }

        It 'fails the whole entry when another declared field differs too, and sends nothing' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Reader'; activationMaxHours = 4
                    approvers = [PSCustomObject]@{ users = @(); groups = @() }
                }
                $Plan = @(Invoke-SyncRmpViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue)
                $Run = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Get-OERRoleManagementPolicy -Times 2 -Exactly
                @($Plan.Action) | Should -Be @('Failed')
                @($Run.Action) | Should -Be @('Failed')
                $Run[0].Detail | Should -Match 'ApproverRequired'
                $Run[0].Detail | Should -BeExactly $Plan[0].Detail
                Should -Invoke Invoke-OERArmRequest -Times 0
                $script:RmpArmCalls.Count | Should -Be 0
            }
        }

        It 'does not fail an empty users side whose seeded group side names the live group' {
            InModuleScope $script:moduleName {
                Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
                $Item = [PSCustomObject]@{
                    scope = 'subscription:Prod'; role = 'Reader'
                    approvers = [PSCustomObject]@{ users = @() }
                }
                $Plan = @(Invoke-SyncRmpViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue -ErrorVariable PlanErr)
                $Run = @(Invoke-SyncRmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable RunErr)
                @($Plan.Action) | Should -Be @('Skipped')
                @($Run.Action) | Should -Be @('Updated')
                @($PlanErr).Count | Should -Be 0
                @($RunErr).Count | Should -Be 0
                Should -Invoke Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApproverUser).Count -eq 0 -and
                    @($ApproverGroup).Count -eq 1 -and @($ApproverGroup) -contains '33333333-3333-3333-3333-333333333333'
                }
            }
        }
    }
}
