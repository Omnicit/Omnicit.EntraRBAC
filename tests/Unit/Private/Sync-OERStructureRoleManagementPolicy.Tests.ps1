BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
                Mock Resolve-OERPrincipal { throw "User 'nobody@example.com' was not found." }
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
                Mock Resolve-OERPrincipal { throw "User 'nobody@example.com' was not found." }
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
}
