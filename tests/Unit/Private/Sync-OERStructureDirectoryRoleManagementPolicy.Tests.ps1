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

Describe 'Sync-OERStructureDirectoryRoleManagementPolicy' {
    # Every It drives the handler through a wrapper function that carries SupportsShouldProcess, so
    # the handler's -Caller is a real PSCmdlet: -WhatIf on the wrapper makes Caller.ShouldProcess
    # decline, and -ErrorAction/-ErrorVariable on the wrapper observe Caller.WriteError. The live
    # policy is the Omnicit.EntraRBAC.RoleManagementPolicy shape Get-OERDirectoryRoleManagementPolicy
    # returns, with approver ids that are not version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncDrmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureDirectoryRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            function script:New-DrmpLivePolicy {
                [PSCustomObject]@{
                    PolicyId                               = 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010'
                    Scope                                  = '/'
                    RoleName                               = 'Reports Reader'
                    RoleDefinitionId                       = 'aaaaaaaa-0000-0000-0000-000000000011'
                    ActivationMaxHours                     = 8
                    RequireMfaOnActivation                 = $true
                    RequireJustificationOnActivation       = $true
                    RequireTicketOnActivation              = $false
                    RequireApproval                        = $true
                    Approvers                              = @(
                        [PSCustomObject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserType = 'User'; DisplayName = 'Person One' }
                        [PSCustomObject]@{ Id = 'bbbbbbbb-0000-0000-0000-000000000002'; UserType = 'Group'; DisplayName = 'Approvers' }
                    )
                    AuthenticationContextId                = $null
                    AllowPermanentEligibility              = $false
                    EligibleDurationDays                   = 365
                    AllowPermanentActiveAssignment         = $false
                    ActiveDurationDays                     = 180
                    RequireMfaOnActiveAssignment           = $false
                    RequireJustificationOnActiveAssignment = $true
                }
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERPrincipal {
                param($User, $Group)
                $Map = @{
                    'person1@example.com' = 'aaaaaaaa-0000-0000-0000-000000000001'
                    'Approvers'           = 'bbbbbbbb-0000-0000-0000-000000000002'
                    'Other Approvers'     = 'bbbbbbbb-0000-0000-0000-000000000003'
                }
                $Key = if ($User) { $User } else { $Group }
                if (-not $Map.ContainsKey($Key)) {
                    # The record the real Resolve-OERPrincipal throws for a value that matches nothing.
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Principal '$Key' was not found."), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Key)
                }
                [PSCustomObject]@{ PrincipalId = $Map[$Key]; PrincipalType = $(if ($User) { 'User' } else { 'Group' }) }
            }
        }
    }

    It 'is Unchanged when the declaration matches the live policy, approvers declared by UPN and group name' {
        # The live approvers carry object ids, the document names them by UPN and group name, and the
        # declared names are resolved to those ids before the diff, so nothing is written.
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 8, "requireMfaOnActivation": true, "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "Approvers" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item)
            @($Records).Action | Should -Be @('Unchanged')
            $Records[0].Section | Should -BeExactly 'directoryRoleManagementPolicies'
            $Records[0].Item | Should -BeExactly 'Reports Reader'
            Should -Invoke Resolve-OERPrincipal -Times 2 -Exactly
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
        }
    }

    It 'reads the policy by -Role and writes it once by the read PolicyId, sending only the differing parameters' {
        InModuleScope $script:moduleName {
            $script:SetKeys = @()
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {
                $script:SetKeys = @($PesterBoundParameters.Keys | Where-Object {
                        [System.Management.Automation.PSCmdlet]::CommonParameters -notcontains $_ -and
                        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters -notcontains $_
                    } | Sort-Object)
            }
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 4, "requireMfaOnActivation": true, "eligibleDurationDays": 365 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item)
            Should -Invoke Get-OERDirectoryRoleManagementPolicy -Times 1 -Exactly -ParameterFilter { $Role -eq 'Reports Reader' }
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PolicyId -eq 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010' -and
                $ActivationMaxHours -eq 4
            }
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0 -ParameterFilter { $PesterBoundParameters.ContainsKey('Role') }
            @($script:SetKeys) | Should -Be @('ActivationMaxHours', 'PolicyId')
            @($Records).Action | Should -Be @('Updated')
            $Records[0].Detail | Should -Match 'activationMaxHours=4'
        }
    }

    It 'reports Skipped and writes nothing when the caller declines ShouldProcess' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 4 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -WhatIf)
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
            @($Records).Action | Should -Be @('Skipped')
            $Records[0].Detail | Should -BeLike 'would update *activationMaxHours=4*'
        }
    }

    It 'reports Failed, publishes the error and writes nothing when the policy read fails' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { throw 'Graph 403 Forbidden' }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            Mock Remove-OERErrorRecord {}
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 4 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue)
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'could not read'
            # The scrub under test is the handler's own catch around the read (the read itself is mocked).
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
            # Published through Caller.WriteError: under -ErrorAction Stop that write is what throws.
            # -ErrorVariable cannot prove it, since it also collects the record the handler caught.
            { Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*Graph 403 Forbidden*'
        }
    }

    It 'reports Failed with ApproverNotFound and writes nothing when a declared approver does not resolve' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader", "approvers": { "users": [ "nobody@example.com" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'could not resolve an approver'
            @($Err | Where-Object {
                    [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' -and
                    $_.Exception.Message -like "*Could not resolve an approver declared for 'Reports Reader'*"
                }).Count | Should -Be 1
        }
    }

    It 'reports Failed only, never Updated, when the write throws' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy { throw 'Graph 500 InternalServerError' }
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 4 }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'Graph 500 InternalServerError'
            { Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction Stop } | Should -Throw '*Graph 500 InternalServerError*'
        }
    }

    It 'treats -Prune as a no-op: the same rows with and without it, and nothing removed' {
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 4 }' | ConvertFrom-Json
            $Plain  = @(Invoke-SyncDrmpViaCaller -Item $Item -WhatIf)
            $Pruned = @(Invoke-SyncDrmpViaCaller -Item $Item -WhatIf -Prune)
            @($Pruned).Action | Should -Be @($Plain).Action
            @($Pruned).Detail | Should -Be @($Plain).Detail
            @($Pruned | Where-Object { $_.Action -in @('Removed', 'Extra') }).Count | Should -Be 0
        }
    }

    It 'sends only ApproverGroup when only approvers.groups is declared' {
        # Graph semantics end to end: the user side is carried from the live rule by
        # Set-OERDirectoryRoleManagementPolicy, so the handler must not bind -ApproverUser at all.
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy { New-DrmpLivePolicy }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader", "approvers": { "groups": [ "Other Approvers" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item)
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                @($ApproverGroup) -contains 'bbbbbbbb-0000-0000-0000-000000000003' -and
                -not $PesterBoundParameters.ContainsKey('ApproverUser')
            }
            @($Records).Action | Should -Be @('Updated')
        }
    }

    It 'converges: the same document applied a second time is only Unchanged' {
        # The write mock applies what the real write path does to the live policy, including the
        # MFA / authentication-context exclusion: a non-empty authentication context clears MFA on
        # activation. The document declares only the context, so the cleared MFA must not reappear
        # as a difference on the second run.
        InModuleScope $script:moduleName {
            $script:LiveDrmp = New-DrmpLivePolicy
            Mock Get-OERDirectoryRoleManagementPolicy { $script:LiveDrmp }
            Mock Set-OERDirectoryRoleManagementPolicy {
                if ($PesterBoundParameters.ContainsKey('ActivationMaxHours')) { $script:LiveDrmp.ActivationMaxHours = $ActivationMaxHours }
                if ($PesterBoundParameters.ContainsKey('AuthenticationContextId')) {
                    $script:LiveDrmp.AuthenticationContextId = $AuthenticationContextId
                    if ($AuthenticationContextId) { $script:LiveDrmp.RequireMfaOnActivation = $false }
                }
                if ($PesterBoundParameters.ContainsKey('ApproverGroup')) {
                    $Kept = @($script:LiveDrmp.Approvers | Where-Object { $_.UserType -ne 'Group' })
                    $New = @($ApproverGroup | ForEach-Object { [PSCustomObject]@{ Id = $_; UserType = 'Group'; DisplayName = $_ } })
                    $script:LiveDrmp.Approvers = @($Kept + $New)
                }
            }
            $Item = '{ "role": "Reports Reader", "activationMaxHours": 2, "authenticationContextId": "c1", "approvers": { "groups": [ "Other Approvers" ] } }' | ConvertFrom-Json
            $First  = @(Invoke-SyncDrmpViaCaller -Item $Item)
            $Second = @(Invoke-SyncDrmpViaCaller -Item $Item)
            @($First).Action  | Should -Be @('Updated')
            @($Second).Action | Should -Be @('Unchanged')
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 1 -Exactly
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleManagementPolicy: an emptied approver side, and a read that fails without throwing' {
    BeforeEach {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncDrmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureDirectoryRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Initialize-OERAuth {}
        }
    }

    It 'converges a declared empty groups side: the first run clears it, the second is only Unchanged' {
        # A declared empty groups list beside a live user side. The write mock does what the real write
        # path does with a bound empty -ApproverGroup: it clears the group side and keeps the user side.
        InModuleScope $script:moduleName {
            $script:LiveDrmp = [PSCustomObject]@{
                PolicyId        = 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010'
                Scope           = '/'
                RequireApproval = $true
                Approvers       = @(
                    [PSCustomObject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserType = 'User'; DisplayName = 'Person One' }
                    [PSCustomObject]@{ Id = 'bbbbbbbb-0000-0000-0000-000000000002'; UserType = 'Group'; DisplayName = 'Approvers' }
                )
            }
            Mock Get-OERDirectoryRoleManagementPolicy { $script:LiveDrmp }
            Mock Set-OERDirectoryRoleManagementPolicy {
                if ($PesterBoundParameters.ContainsKey('ApproverGroup')) {
                    $Kept = @($script:LiveDrmp.Approvers | Where-Object { $_.UserType -ne 'Group' })
                    $New = @($ApproverGroup | Where-Object { $_ } | ForEach-Object { [PSCustomObject]@{ Id = $_; UserType = 'Group'; DisplayName = $_ } })
                    $script:LiveDrmp.Approvers = @($Kept + $New)
                }
            }
            $Item = '{ "role": "Reports Reader", "approvers": { "groups": [] } }' | ConvertFrom-Json
            $First  = @(Invoke-SyncDrmpViaCaller -Item $Item)
            $Second = @(Invoke-SyncDrmpViaCaller -Item $Item)
            @($First).Action  | Should -Be @('Updated')
            @($Second).Action | Should -Be @('Unchanged')
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('ApproverGroup') -and @($ApproverGroup).Count -eq 0 -and
                -not $PesterBoundParameters.ContainsKey('ApproverUser')
            }
            @($script:LiveDrmp.Approvers | Where-Object { $_.UserType -eq 'User' }).Count | Should -Be 1
        }
    }

    It 'reports Failed and writes nothing when the read writes a non-terminating error and returns nothing' {
        # The real Get-OERDirectoryRoleManagementPolicy reports a missing role or policy as a
        # NON-terminating error and returns nothing. Only -ErrorAction Stop on the read turns that
        # into the handler's catch; without it the policy stays $null and a role-only entry, which
        # declares nothing to compare, would be reported Unchanged.
        InModuleScope $script:moduleName {
            Mock Get-OERDirectoryRoleManagementPolicy {
                Write-Error -Message "Directory role 'Reports Reader' was not found." -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound
            }
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Item = '{ "role": "Reports Reader" }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'could not read'
            $Records[0].Detail | Should -Match 'was not found'
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleManagementPolicy: a declared approver, missing, ambiguous and failed are three outcomes (Sprint 8 step 3, BL-14)' {
    # The real Resolve-OERDeclaredApprover and Resolve-OERPrincipal run here (this Describe mocks
    # neither); only the lookups under them answer. Every outcome is one Failed row carrying the record
    # the handler published, and nothing is written. The handler's own record is the one whose id ends
    # in ',Invoke-SyncDrmpViaCaller': -ErrorVariable also collects what was thrown inside.
    BeforeEach {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncDrmpViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureDirectoryRoleManagementPolicy -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Initialize-OERAuth {}
            Mock Get-OERDirectoryRoleManagementPolicy {
                [PSCustomObject]@{
                    PolicyId = 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010'
                    Scope = '/'; RoleName = 'Reports Reader'; RequireApproval = $false; Approvers = @()
                }
            }
            Mock Set-OERDirectoryRoleManagementPolicy {}
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
            $Item = '{ "role": "Reports Reader", "approvers": { "groups": [ "missing-approvers" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Be "could not resolve an approver: Group 'missing-approvers' was not found.; the policy was not changed"
            [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^ApproverNotFound'
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncDrmpViaCaller' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'ApproverNotFound,Invoke-SyncDrmpViaCaller'
            $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Own[0].TargetObject | Should -Be 'Reports Reader'
            $Own[0].Exception.Message | Should -Be "Could not resolve an approver declared for 'Reports Reader': Group 'missing-approvers' was not found."
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
        }
    }

    It 'reports an ambiguous approver name as AmbiguousApproverName naming the candidates, never as ApproverNotFound' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "approvers": { "groups": [ "dup-approvers" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match '11111111-1111-1111-1111-111111111111'
            [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^AmbiguousApproverName'
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncDrmpViaCaller' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'AmbiguousApproverName,Invoke-SyncDrmpViaCaller'
            $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Own[0].TargetObject | Should -Be 'dup-approvers'
            $Own[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $Own[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
        }
    }

    It 'reports a failed approver lookup as itself, once, never as ApproverNotFound' {
        InModuleScope $script:moduleName {
            $Item = '{ "role": "Reports Reader", "approvers": { "users": [ "person9@example.com" ] } }' | ConvertFrom-Json
            $Records = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
            @($Records).Action | Should -Be @('Failed')
            $Records[0].Detail | Should -Match 'Insufficient privileges'
            [string]$Records[0].Error.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncDrmpViaCaller' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied,Invoke-SyncDrmpViaCaller'
            $Own[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
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
            $Item = '{ "role": "Reports Reader", "approvers": { "users": [ "person9@example.com" ] } }' | ConvertFrom-Json
            $null = @(Invoke-SyncDrmpViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
            # Reached: the handler published the record as itself.
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Invoke-SyncDrmpViaCaller' }).Count | Should -Be 1
            # A prefix match: $Caller.WriteError appends ',<command>' to this same record, in place,
            # before the filter is evaluated.
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record -and [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' -and
                $Record.Exception.Message -like '*Insufficient privileges*'
            }
        }
    }
}

Describe 'Sync-OERStructureDirectoryRoleManagementPolicy: the plan shows the MFA / authentication context warning a real run gives (BL-17)' {
    # Set-OERDirectoryRoleManagementPolicy warns, before its own gate, when it clears MFA on activation
    # or disables the authentication context. Under -WhatIf the engine never calls it, so the handler
    # takes the same decision from the same inputs and writes the cmdlet's own text before its gate --
    # and only under -WhatIf: a real run calls the cmdlet, which writes it, and a copy from the handler
    # would warn twice. The warnings are counted from the stream (3>&1), with -WarningAction Continue
    # pinned on the call. In the real runs below Set-OERDirectoryRoleManagementPolicy runs for REAL:
    # only auth, the handler's policy read and the Graph transport are mocked, and the live rules are
    # built once per test and fed to both the handler's read and the cmdlet's read of the policy.
    BeforeAll {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncDrmpWarnViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item)
                Sync-OERStructureDirectoryRoleManagementPolicy -Item $Item -Caller $PSCmdlet
            }
            # One run of the handler: its rows, and the text of every warning that reached the stream.
            function script:Invoke-DrmpWarnCapture {
                param([PSCustomObject]$Item, [bool]$WhatIfRun)
                $All = @(Invoke-SyncDrmpWarnViaCaller -Item $Item -WhatIf:$WhatIfRun -Confirm:$false -WarningAction Continue -ErrorAction Stop 3>&1)
                [PSCustomObject]@{
                    Rows     = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
                    Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                }
            }
            # The live rules of the policy in the Microsoft Graph v1.0 shape: MFA on activation on or off,
            # and the authentication context enabled with a claim value, or disabled.
            function script:New-DrmpWarnRule {
                param([bool]$Mfa, [string]$ContextId)
                $Enabled = @('Justification')
                if ($Mfa) { $Enabled = @('MultiFactorAuthentication', 'Justification') }
                @(
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT8H' }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'; id = 'Enablement_EndUser_Assignment'; enabledRules = $Enabled }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'; id = 'AuthenticationContext_EndUser_Assignment'
                        isEnabled = (-not [string]::IsNullOrEmpty($ContextId)); claimValue = $ContextId }
                )
            }
        }
    }
    BeforeEach {
        InModuleScope $script:moduleName {
            Mock Initialize-OERAuth {}
            Mock Get-OERDirectoryRoleManagementPolicy {
                ConvertTo-OERRoleManagementPolicy -Rules @($script:DrmpWarnRules) -PolicyId 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010' `
                    -Scope '/' -RoleName 'Reports Reader' -ApproverShape Graph
            }
            # The real cmdlet's read of the policy by id and its PATCHes. Anything else is not simulated
            # and throws.
            Mock Invoke-OERGraphRequest {
                if ($Method -eq 'PATCH') { return @{} }
                if ($Uri -eq 'v1.0/policies/roleManagementPolicies/DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010?$expand=rules') {
                    return @{
                        id        = 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010'
                        scopeId   = '/'
                        scopeType = 'DirectoryRole'
                        rules     = @($script:DrmpWarnRules)
                    }
                }
                throw "unexpected $Method $Uri"
            }
        }
    }

    It 'writes the warning of Set-OERDirectoryRoleManagementPolicy once under -WhatIf, before the gate, and never calls the cmdlet (<Arm>)' -ForEach @(
        @{ Arm = 'ClearMfa'; Mfa = $true; Ctx = ''; Json = '{ "role": "Reports Reader", "authenticationContextId": "c1" }'
            Expected = "Policy 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010': mfa cleared: mutually exclusive with authenticationContextId=c1" }
        @{ Arm = 'DisableAuthContext'; Mfa = $false; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "requireMfaOnActivation": true }'
            Expected = "Policy 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010': authentication context 'c7' disabled: mutually exclusive with multi-factor authentication on activation" }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Mfa = $Mfa; Ctx = $Ctx; Json = $Json; Expected = $Expected } {
            param($Mfa, $Ctx, $Json, $Expected)
            $script:DrmpWarnRules = New-DrmpWarnRule -Mfa $Mfa -ContextId $Ctx
            Mock Set-OERDirectoryRoleManagementPolicy {}
            $Out = Invoke-DrmpWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
            # Reached: the gate declined and the plan row was written.
            @($Out.Rows).Action | Should -Be @('Skipped')
            $Out.Rows[0].Detail | Should -BeLike "would update directory role management policy for 'Reports Reader' (*"
            Should -Invoke Set-OERDirectoryRoleManagementPolicy -Times 0
            $Out.Warnings.Count | Should -Be 1
            $Out.Warnings[0] | Should -BeExactly $Expected
        }
    }

    # The parity matrix: for every combination of the live policy (MFA on activation on or off, the
    # authentication context enabled as 'c7' or disabled) and the declared change (requireMfaOnActivation
    # true, authenticationContextId 'c1', authenticationContextId ''), plus one row that turns MFA off
    # while it enables a context, the handler's -WhatIf warning, or
    # its absence, is what the REAL Set-OERDirectoryRoleManagementPolicy writes for the same splat and
    # the same live rules in a real run -- once, with the same text. Expected names the outcome, so a
    # matrix whose rows all agree on silence cannot pass. A row whose declaration already matches the
    # live policy is Unchanged and calls nothing in either mode.
    It 'warns under -WhatIf exactly as the real cmdlet does in a real run: live MFA <LiveMfa>, live context <LiveCtx>, declared <Declared>' -ForEach @(
        @{ LiveMfa = 'off'; LiveCtx = 'disabled'; Declared = 'requireMfaOnActivation true'; Mfa = $false; Ctx = ''; Json = '{ "role": "Reports Reader", "requireMfaOnActivation": true }'; Action = 'Updated'; Patches = 1; Expected = $null }
        @{ LiveMfa = 'off'; LiveCtx = 'disabled'; Declared = "authenticationContextId 'c1'"; Mfa = $false; Ctx = ''; Json = '{ "role": "Reports Reader", "authenticationContextId": "c1" }'; Action = 'Updated'; Patches = 1; Expected = $null }
        @{ LiveMfa = 'off'; LiveCtx = 'disabled'; Declared = "authenticationContextId ''"; Mfa = $false; Ctx = ''; Json = '{ "role": "Reports Reader", "authenticationContextId": "" }'; Action = 'Unchanged'; Patches = 0; Expected = $null }
        @{ LiveMfa = 'off'; LiveCtx = 'c7'; Declared = 'requireMfaOnActivation true'; Mfa = $false; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "requireMfaOnActivation": true }'; Action = 'Updated'; Patches = 2
            Expected = "Policy 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010': authentication context 'c7' disabled: mutually exclusive with multi-factor authentication on activation" }
        @{ LiveMfa = 'off'; LiveCtx = 'c7'; Declared = "authenticationContextId 'c1'"; Mfa = $false; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "authenticationContextId": "c1" }'; Action = 'Updated'; Patches = 1; Expected = $null }
        @{ LiveMfa = 'off'; LiveCtx = 'c7'; Declared = "authenticationContextId ''"; Mfa = $false; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "authenticationContextId": "" }'; Action = 'Updated'; Patches = 1; Expected = $null }
        @{ LiveMfa = 'on'; LiveCtx = 'disabled'; Declared = 'requireMfaOnActivation true'; Mfa = $true; Ctx = ''; Json = '{ "role": "Reports Reader", "requireMfaOnActivation": true }'; Action = 'Unchanged'; Patches = 0; Expected = $null }
        @{ LiveMfa = 'on'; LiveCtx = 'disabled'; Declared = "authenticationContextId 'c1'"; Mfa = $true; Ctx = ''; Json = '{ "role": "Reports Reader", "authenticationContextId": "c1" }'; Action = 'Updated'; Patches = 2
            Expected = "Policy 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010': mfa cleared: mutually exclusive with authenticationContextId=c1" }
        @{ LiveMfa = 'on'; LiveCtx = 'disabled'; Declared = "authenticationContextId ''"; Mfa = $true; Ctx = ''; Json = '{ "role": "Reports Reader", "authenticationContextId": "" }'; Action = 'Unchanged'; Patches = 0; Expected = $null }
        # MFA turned off in the same change that enables a context: the cmdlet toggles MFA off first, so
        # nothing is left to clear and neither mode warns.
        @{ LiveMfa = 'on'; LiveCtx = 'disabled'; Declared = "requireMfaOnActivation false and authenticationContextId 'c1'"; Mfa = $true; Ctx = ''
            Json = '{ "role": "Reports Reader", "requireMfaOnActivation": false, "authenticationContextId": "c1" }'; Action = 'Updated'; Patches = 2; Expected = $null }
        @{ LiveMfa = 'on'; LiveCtx = 'c7'; Declared = 'requireMfaOnActivation true'; Mfa = $true; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "requireMfaOnActivation": true }'; Action = 'Unchanged'; Patches = 0; Expected = $null }
        @{ LiveMfa = 'on'; LiveCtx = 'c7'; Declared = "authenticationContextId 'c1'"; Mfa = $true; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "authenticationContextId": "c1" }'; Action = 'Updated'; Patches = 2
            Expected = "Policy 'DirectoryRole_11111111-1111-1111-1111-111111111111_aaaaaaaa-0000-0000-0000-000000000010': mfa cleared: mutually exclusive with authenticationContextId=c1" }
        @{ LiveMfa = 'on'; LiveCtx = 'c7'; Declared = "authenticationContextId ''"; Mfa = $true; Ctx = 'c7'; Json = '{ "role": "Reports Reader", "authenticationContextId": "" }'; Action = 'Updated'; Patches = 1; Expected = $null }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Mfa = $Mfa; Ctx = $Ctx; Json = $Json; Action = $Action; Patches = $Patches; Expected = $Expected } {
            param($Mfa, $Ctx, $Json, $Action, $Patches, $Expected)
            $script:DrmpWarnRules = New-DrmpWarnRule -Mfa $Mfa -ContextId $Ctx
            $Plan = Invoke-DrmpWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
            $PlanAction = if ($Action -eq 'Updated') { 'Skipped' } else { 'Unchanged' }
            @($Plan.Rows).Action | Should -Be @($PlanAction)
            Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
            $Run = Invoke-DrmpWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
            @($Run.Rows).Action | Should -Be @($Action)
            if ($Action -eq 'Updated') {
                # Reached: the real cmdlet read the policy by its id and sent the changed rules.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/policies/roleManagementPolicies/*?$expand=rules' }
                Should -Invoke Invoke-OERGraphRequest -Times $Patches -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            }
            if ($null -eq $Expected) {
                $Plan.Warnings.Count | Should -Be 0
                $Run.Warnings.Count | Should -Be 0
            } else {
                $Plan.Warnings.Count | Should -Be 1
                $Plan.Warnings[0] | Should -BeExactly $Expected
                $Run.Warnings.Count | Should -Be 1 -Because 'a real run must warn once, from the cmdlet, never also from the handler'
                ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
            }
        }
    }
}
