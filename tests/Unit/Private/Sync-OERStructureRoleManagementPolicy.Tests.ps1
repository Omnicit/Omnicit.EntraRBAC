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

    Context 'the scope the engine resolved (-ResolvedScope, BL-150)' {
        # Invoke-OERStructure resolves a roleManagementPolicies entry's scope once, in its home tenant check
        # (Get-OERSubscriptionHomeTenant), and hands the canonical scope to the handler, so the policy read
        # and written is the one the check decided on. The rows still name the scope as the document wrote
        # it. Without -ResolvedScope the handler parses the document scope itself, as before.
        BeforeEach {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncRmpResolved {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [string]$ResolvedScope)
                    $Extra = @{}
                    if ($PSBoundParameters.ContainsKey('ResolvedScope')) { $Extra.ResolvedScope = $ResolvedScope }
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet @Extra
                }
                Mock Initialize-OERAuth {}
                Mock Get-OERRoleManagementPolicy { [PSCustomObject]@{ ActivationMaxHours = 8; RequireApproval = $false; Approvers = @(); RoleName = $Role } }
                Mock Set-OERRoleManagementPolicy { [PSCustomObject]@{ PolicyId = 'p-1' } }
                Mock Resolve-OERDeclaredApprover { param($Declared) $Declared }
                Mock Invoke-OERArmRequest { throw "unexpected ARM call: $Path" }
            }
        }

        It 'reads and updates the policy at -ResolvedScope with -Scope alone for <Name>, and names the document scope in its rows' -ForEach @(
            @{ Name = 'a sub: scope'; DocScope = 'sub:Prod'; Resolved = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
                Filter = { $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and -not $Subscription -and -not $ManagementGroup -and -not $ResourceGroup -and $Role -eq 'Reader' } }
            @{ Name = 'a subscription: scope'; DocScope = 'subscription:aaaa1111-0000-0000-0000-000000000001'; Resolved = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
                Filter = { $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and -not $Subscription -and -not $ManagementGroup -and -not $ResourceGroup -and $Role -eq 'Reader' } }
            @{ Name = 'a management group path'; DocScope = '/providers/Microsoft.Management/managementGroups/mg1/'; Resolved = '/providers/Microsoft.Management/managementGroups/mg1'
                Filter = { $Scope -ceq '/providers/Microsoft.Management/managementGroups/mg1' -and -not $Subscription -and -not $ManagementGroup -and -not $ResourceGroup -and $Role -eq 'Reader' } }
        ) {
            $Rows = @(InModuleScope $script:moduleName -Parameters @{ DocScope = $DocScope; Resolved = $Resolved } {
                    param($DocScope, $Resolved)
                    Invoke-SyncRmpResolved -Item ([PSCustomObject]@{ scope = $DocScope; role = 'Reader'; activationMaxHours = 4 }) -ResolvedScope $Resolved
                })
            # The read and the write both went to the resolved scope, and named no other scope parameter.
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter $Filter
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter $Filter
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            $Rows.Count | Should -Be 1
            $Rows[0].Action | Should -Be 'Updated'
            $Rows[0].Item | Should -BeExactly "Reader @ $DocScope"
            $Rows[0].Detail | Should -BeExactly "updated role management policy for 'Reader' at '$DocScope' (activationMaxHours=4)"
        }

        It 'names the document scope in the -WhatIf row too, after reading at -ResolvedScope' {
            $Rows = @(InModuleScope $script:moduleName {
                    Invoke-SyncRmpResolved -Item ([PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; activationMaxHours = 4 }) `
                        -ResolvedScope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -WhatIf
                })
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and -not $Subscription
            }
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 0
            $Rows.Count | Should -Be 1
            $Rows[0].Action | Should -Be 'Skipped'
            $Rows[0].Item | Should -BeExactly 'Reader @ sub:Prod'
            $Rows[0].Detail | Should -BeExactly "would update role management policy for 'Reader' at 'sub:Prod'"
        }

        It 'parses the document scope as before without -ResolvedScope (<Name>)' -ForEach @(
            @{ Name = 'a sub: scope'; DocScope = 'sub:Prod'
                Filter = { $Subscription -ceq 'Prod' -and -not $Scope -and -not $ManagementGroup } }
            @{ Name = 'an mg: scope'; DocScope = 'mg:mg1'
                Filter = { $ManagementGroup -ceq 'mg1' -and -not $Scope -and -not $Subscription } }
            @{ Name = 'a path with a trailing slash'; DocScope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/'
                Filter = { $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -and -not $Subscription -and -not $ManagementGroup } }
        ) {
            $Rows = @(InModuleScope $script:moduleName -Parameters @{ DocScope = $DocScope } {
                    param($DocScope)
                    Invoke-SyncRmpResolved -Item ([PSCustomObject]@{ scope = $DocScope; role = 'Reader'; activationMaxHours = 4 })
                })
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter $Filter
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 1 -Exactly -ParameterFilter $Filter
            $Rows.Count | Should -Be 1
            $Rows[0].Action | Should -Be 'Updated'
            $Rows[0].Item | Should -BeExactly "Reader @ $DocScope"
        }
    }

    # BL-40 (Sprint 11 step 11): the handler reads the live policy with -ErrorAction Stop, since
    # Get-OERRoleManagementPolicy reports a failed read (a role or policy it cannot find, a 403, a scope
    # it cannot resolve) as a NON-terminating error and returns nothing. Left at the preference's default,
    # the error went to the stream and the read became $null: the diff then treated every declared field
    # as changed and, for an entry declaring one approver side, seeded the undeclared side EMPTY instead
    # of from the live policy, so the write removed every live approver on that side. A read that returns
    # no policy and no error is refused the same way (PolicyNotFound). Both come before the approver
    # lookup, the diff, the ApproverRequired check and ShouldProcess, so -WhatIf reports the same row.
    #
    # The calls below carry NO -ErrorAction: any -ErrorAction on the wrapper sets the preference in the
    # wrapper's scope and shadows the global one the module reads. The global preference is pinned to
    # Continue instead, so the proof does not depend on the preference the runner carries (Stop on CI
    # would turn the read's error terminating by itself and hide a missing -ErrorAction Stop).
    Context 'a failed read of the live policy never feeds a write (BL-40)' {
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncRmpReadViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureRoleManagementPolicy -Item $Item -Caller $PSCmdlet
                }
            }
            $script:RmpReadScope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $script:RmpReadLabel = "Reader @ $($script:RmpReadScope)"
            # Installs the read failure a case names, in module scope, for the current It.
            function script:Set-RmpReadFailure {
                param([string]$Failure)
                InModuleScope $script:moduleName -Parameters @{ Failure = $Failure } {
                    param($Failure)
                    switch ($Failure) {
                        'NonTerminatingMock' {
                            # The shape the real cmdlet fails in: a [CmdletBinding()] body that writes
                            # its record through $PSCmdlet.WriteError and returns nothing.
                            Mock Get-OERRoleManagementPolicy {
                                [CmdletBinding()] param($Role, $Scope, $Subscription, $ManagementGroup, $ResourceGroup)
                                $script:RmpReadLog.Add('Get-OERRoleManagementPolicy')
                                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                                        [System.Exception]::new('ARM 403 AuthorizationFailed'), 'RoleDefinitionNotFound',
                                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Role))
                            }
                        }
                        'NonTerminatingReal' {
                            # The REAL Get-OERRoleManagementPolicy runs: the role definition lookup is
                            # answered and the policy assignment list fails, so the cmdlet's own
                            # Write-CmdletError publishes PolicyNotFound, non-terminating.
                            Mock Invoke-OERArmRequest {
                                $script:RmpReadLog.Add("ARM $Path")
                                if ($Path -like '*/providers/Microsoft.Authorization/roleDefinitions?*') {
                                    return [PSCustomObject]@{ value = @([PSCustomObject]@{
                                                id = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/providers/Microsoft.Authorization/roleDefinitions/bbbb4040-0000-0000-0000-000000000001' }) }
                                }
                                if ($Path -like '*/providers/Microsoft.Authorization/roleManagementPolicyAssignments?*') {
                                    throw 'ARM 403 AuthorizationFailed'
                                }
                                throw "unexpected ARM request: $Path"
                            }
                        }
                        'Terminating' {
                            Mock Get-OERRoleManagementPolicy {
                                $script:RmpReadLog.Add('Get-OERRoleManagementPolicy')
                                throw [System.Management.Automation.ErrorRecord]::new(
                                    [System.Exception]::new('ARM 503 ServiceUnavailable'), 'ArmServiceUnavailable',
                                    [System.Management.Automation.ErrorCategory]::ReadError, $Role)
                            }
                        }
                        'NoObject' {
                            # No error and no object: the live policy is just as unknown.
                            Mock Get-OERRoleManagementPolicy { $script:RmpReadLog.Add('Get-OERRoleManagementPolicy') }
                        }
                    }
                }
            }
        }
        BeforeEach {
            $script:RmpReadSavedPreference = $global:ErrorActionPreference
            $global:ErrorActionPreference = 'Continue'
            InModuleScope $script:moduleName {
                $script:RmpReadLog = [System.Collections.Generic.List[string]]::new()
                Mock Initialize-OERAuth { }
                Mock Invoke-OERArmRequest { throw "unexpected ARM request: $Path" }
                Mock Set-OERRoleManagementPolicy { $script:RmpReadLog.Add('Set-OERRoleManagementPolicy') }
                # The approver lookup is an identity pass-through: reaching it at all is the defect.
                Mock Resolve-OERDeclaredApprover { param($Declared) $script:RmpReadLog.Add('Resolve-OERDeclaredApprover'); $Declared }
            }
        }
        AfterEach {
            $global:ErrorActionPreference = $script:RmpReadSavedPreference
        }

        It 'reports one Failed row carrying the read''s record, writes it once and sends nothing when <Name>' -ForEach @(
            @{ Name = 'the read fails non-terminating'; Failure = 'NonTerminatingMock'; ErrorId = 'RoleDefinitionNotFound'; Message = 'ARM 403 AuthorizationFailed'; Category = 'ObjectNotFound' }
            @{ Name = 'the real cmdlet fails its read non-terminating'; Failure = 'NonTerminatingReal'; ErrorId = 'PolicyNotFound'; Message = 'ARM 403 AuthorizationFailed'; Category = 'ObjectNotFound' }
            @{ Name = 'the read fails terminating'; Failure = 'Terminating'; ErrorId = 'ArmServiceUnavailable'; Message = 'ARM 503 ServiceUnavailable'; Category = 'ReadError' }
        ) {
            Set-RmpReadFailure -Failure $Failure
            $Result = InModuleScope $script:moduleName -Parameters @{ Scope = $script:RmpReadScope } {
                param($Scope)
                # A declared field that differs from any policy: with the read taken as $null it was sent.
                $Item = [PSCustomObject]@{ scope = $Scope; role = 'Reader'; activationMaxHours = 4 }
                $Rows = @(Invoke-SyncRmpReadViaCaller -Item $Item -ErrorVariable Err 2>$null)
                [PSCustomObject]@{ Rows = $Rows; Err = @($Err); Log = @($script:RmpReadLog) }
            }

            $Result.Rows.Count | Should -Be 1
            $Result.Rows[0].Section | Should -BeExactly 'roleManagementPolicies'
            $Result.Rows[0].Item | Should -BeExactly $script:RmpReadLabel
            $Result.Rows[0].Action | Should -BeExactly 'Failed'
            $Result.Rows[0].Detail | Should -BeExactly "could not read role management policy for 'Reader' at '$($script:RmpReadScope)': $Message"
            [string]$Result.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike "$ErrorId,*"
            $Result.Rows[0].Error.Exception.Message | Should -BeExactly $Message
            # Written once through the caller. -ErrorVariable also holds the inner layers' records, so the
            # handler's own is counted by the suffix the caller's WriteError gives its id.
            $Own = @($Result.Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncRmpReadViaCaller' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly "$ErrorId,Invoke-SyncRmpReadViaCaller"
            [string]$Own[0].CategoryInfo.Category | Should -BeExactly $Category
            $Own[0].Exception.Message | Should -BeExactly $Message

            # Reached: the read was made. Nothing after it ran: no approver lookup, no write.
            if ($Failure -eq 'NonTerminatingReal') {
                @($Result.Log | Where-Object { $_ -like 'ARM *roleManagementPolicyAssignments*' }).Count | Should -Be 1
            } else {
                @($Result.Log | Where-Object { $_ -eq 'Get-OERRoleManagementPolicy' }).Count | Should -Be 1
            }
            $Result.Log | Should -Not -Contain 'Resolve-OERDeclaredApprover'
            $Result.Log | Should -Not -Contain 'Set-OERRoleManagementPolicy'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERDeclaredApprover -Times 0
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 0
        }

        It 'fails an entry declaring only approvers.users, never Skipped or Updated, when <Name> (<Mode>)' -ForEach @(
            @{ Name = 'the read fails non-terminating'; Failure = 'NonTerminatingMock'; Mode = 'a real run'; WhatIf = $false; ErrorId = 'RoleDefinitionNotFound'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the read fails non-terminating'; Failure = 'NonTerminatingMock'; Mode = 'a -WhatIf plan'; WhatIf = $true; ErrorId = 'RoleDefinitionNotFound'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the real cmdlet fails its read non-terminating'; Failure = 'NonTerminatingReal'; Mode = 'a real run'; WhatIf = $false; ErrorId = 'PolicyNotFound'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the real cmdlet fails its read non-terminating'; Failure = 'NonTerminatingReal'; Mode = 'a -WhatIf plan'; WhatIf = $true; ErrorId = 'PolicyNotFound'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the read fails terminating'; Failure = 'Terminating'; Mode = 'a real run'; WhatIf = $false; ErrorId = 'ArmServiceUnavailable'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the read fails terminating'; Failure = 'Terminating'; Mode = 'a -WhatIf plan'; WhatIf = $true; ErrorId = 'ArmServiceUnavailable'; DetailStart = 'could not read role management policy' }
            @{ Name = 'the read returns no policy and no error'; Failure = 'NoObject'; Mode = 'a real run'; WhatIf = $false; ErrorId = 'PolicyNotFound'; DetailStart = 'Get-OERRoleManagementPolicy returned no policy' }
            @{ Name = 'the read returns no policy and no error'; Failure = 'NoObject'; Mode = 'a -WhatIf plan'; WhatIf = $true; ErrorId = 'PolicyNotFound'; DetailStart = 'Get-OERRoleManagementPolicy returned no policy' }
        ) {
            Set-RmpReadFailure -Failure $Failure
            $Result = InModuleScope $script:moduleName -Parameters @{ Scope = $script:RmpReadScope; WhatIf = $WhatIf } {
                param($Scope, $WhatIf)
                # Only the users side is declared: a $null read seeded the groups side EMPTY, so the
                # write removed every live group approver.
                $Item = [PSCustomObject]@{
                    scope = $Scope; role = 'Reader'
                    approvers = [PSCustomObject]@{ users = @('dddd4040-0000-0000-0000-000000000001') }
                }
                $Switches = @{}
                if ($WhatIf) { $Switches.WhatIf = $true }
                $Rows = @(Invoke-SyncRmpReadViaCaller -Item $Item @Switches -ErrorVariable Err 2>$null)
                [PSCustomObject]@{ Rows = $Rows; Err = @($Err); Log = @($script:RmpReadLog) }
            }

            @($Result.Rows.Action) | Should -Be @('Failed')
            $Result.Rows[0].Item | Should -BeExactly $script:RmpReadLabel
            $Result.Rows[0].Detail | Should -BeLike "$DetailStart for 'Reader' at '$($script:RmpReadScope)'*"
            $Result.Rows[0].Detail | Should -Not -Match 'would update'
            [string]$Result.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike "$ErrorId,*"
            @($Result.Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncRmpReadViaCaller' }).FullyQualifiedErrorId |
                Should -Be @("$ErrorId,Invoke-SyncRmpReadViaCaller")
            # Reached: the read was made, and nothing after it ran.
            @($Result.Log | Where-Object { $_ -eq 'Get-OERRoleManagementPolicy' -or $_ -like 'ARM *roleManagementPolicyAssignments*' }).Count | Should -Be 1
            $Result.Log | Should -Not -Contain 'Resolve-OERDeclaredApprover'
            $Result.Log | Should -Not -Contain 'Set-OERRoleManagementPolicy'
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 0
        }

        It 'refuses a read that returns no policy and no error as PolicyNotFound, before the approver lookup, the diff and ShouldProcess' {
            Set-RmpReadFailure -Failure 'NoObject'
            $Result = InModuleScope $script:moduleName -Parameters @{ Scope = $script:RmpReadScope } {
                param($Scope)
                $Item = [PSCustomObject]@{ scope = $Scope; role = 'Reader'; activationMaxHours = 4 }
                $Rows = @(Invoke-SyncRmpReadViaCaller -Item $Item -ErrorVariable Err 2>$null)
                [PSCustomObject]@{ Rows = $Rows; Err = @($Err); Log = @($script:RmpReadLog) }
            }

            $Result.Rows.Count | Should -Be 1
            $Result.Rows[0].Section | Should -BeExactly 'roleManagementPolicies'
            $Result.Rows[0].Item | Should -BeExactly $script:RmpReadLabel
            $Result.Rows[0].Action | Should -BeExactly 'Failed'
            $Result.Rows[0].Detail | Should -BeExactly "Get-OERRoleManagementPolicy returned no policy for 'Reader' at '$($script:RmpReadScope)'; the policy was not changed"
            [string]$Result.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'PolicyNotFound,*'
            # The record is the handler's own, written once through the caller and carried by the row.
            @($Result.Err).Count | Should -Be 1
            $Result.Err[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyNotFound,Invoke-SyncRmpReadViaCaller'
            [string]$Result.Err[0].CategoryInfo.Category | Should -BeExactly 'ObjectNotFound'
            $Result.Err[0].TargetObject | Should -BeExactly $script:RmpReadLabel
            $Result.Err[0].Exception.Message | Should -BeExactly ("Get-OERRoleManagementPolicy returned no role management policy for 'Reader' at " +
                "'$($script:RmpReadScope)' and no error, so the live policy is unknown. The policy was not changed.")
            [object]::ReferenceEquals($Result.Rows[0].Error, $Result.Err[0]) | Should -BeTrue
            @($Result.Log) -join ',' | Should -BeExactly 'Get-OERRoleManagementPolicy'
            Should -Invoke -ModuleName $script:moduleName Set-OERRoleManagementPolicy -Times 0
        }
    }
}
