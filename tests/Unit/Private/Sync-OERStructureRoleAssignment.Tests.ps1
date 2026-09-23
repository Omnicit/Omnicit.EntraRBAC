BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Sync-OERStructureRoleAssignment' {

    It 'parses subscription:Prod into -Subscription and creates a missing assignment with -Group for non-@ principal' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }))
            Should -Invoke Resolve-OERScope -Times 1 -ParameterFilter { $Subscription -eq 'Prod' }
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $Subscription -eq 'Prod' -and $Group -eq 'role_sec_x' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'parses mg:platform into -ManagementGroup and creates a missing assignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/providers/Microsoft.Management/managementGroups/platform' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-mg-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'mg:platform'; role = 'Reader'; principal = 'role_sec_platform' }))
            Should -Invoke Resolve-OERScope -Times 1 -ParameterFilter { $ManagementGroup -eq 'platform' }
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $ManagementGroup -eq 'platform' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'uses -User when the principal contains @' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'u-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-u-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'anna@contoso.com' }))
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $User -eq 'anna@contoso.com' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged and does not call New-OERRoleAssignment when assignment already exists' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @([PSCustomObject]@{
                    PrincipalId      = 'p-1'
                    RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                    RoleAssignmentId = 'ra-exists'
                })
            }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }))
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'passes a raw scope string as -Scope to Resolve-OERScope' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/x/resourceGroups/y' }
            Mock Resolve-OERStructurePrincipal { 'p-raw' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/x/resourceGroups/y/providers/Microsoft.Authorization/roleDefinitions/rd-raw' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-raw' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = '/subscriptions/x/resourceGroups/y'; role = 'Reader'; principal = 'role_sec_x' }))
            Should -Invoke Resolve-OERScope -Times 1 -ParameterFilter { $Scope -eq '/subscriptions/x/resourceGroups/y' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Failed and does not call New-OERRoleAssignment when Resolve-OERScope throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { throw 'subscription not found' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { 'rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Missing'; role = 'Reader'; principal = 'role_sec_x' }) -ErrorAction SilentlyContinue)
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Failed and does not call New-OERRoleAssignment when principal is unresolvable' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { $null }
            Mock Resolve-OERRoleDefinitionId { 'rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'no_such_group' }) -ErrorAction SilentlyContinue)
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -ReconcileScope and -Prune removes an undeclared current assignment via -Id and emits Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            # Current contains the declared item (p-1/rd-1) and an extra undeclared item
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERRoleAssignment -Times 1 -ParameterFilter { $Id -eq 'ra-extra' }
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing for the scope prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $Warnings = @()
            $null = Invoke-SyncRaViaCaller -Item $DeclaredItem -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for the scope prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $Warnings = @()
            $null = Invoke-SyncRaViaCaller -Item $DeclaredItem -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'with -ReconcileScope without -Prune reports undeclared assignment as Extra and does not call Remove-OERRoleAssignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
            Should -Invoke Remove-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    It 'without -ReconcileScope does not report Extra or Removed for an undeclared current assignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            # Current contains the declared assignment plus an undeclared extra
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            # No -ReconcileScope
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -DeclaredAtScope @($DeclaredItem))
            Should -Invoke Remove-OERRoleAssignment -Times 0
            ($r | Where-Object { $_.Action -eq 'Extra' -or $_.Action -eq 'Removed' }).Count | Should -Be 0
        }
    }

    It 'under -WhatIf does not call New-OERRoleAssignment and emits Skipped' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -WhatIf)
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'when New-OERRoleAssignment throws emits Failed and not Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { throw 'ARM 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERRoleAssignment throws' {
        # Drives the role-assignment creation catch in Sync-OERStructureRoleAssignment. The scrub
        # under test is this handler's OWN -- the Remove-OERErrorRecord opening the handler catch
        # that WRAPS the New-OERRoleAssignment call, not a scrub inside New-OERRoleAssignment, which
        # is mocked away here. That mocking is precisely what makes the proof non-vacuous.
        # The failed ARM request
        # behind that write carries the Authorization: Bearer header on its request object. The
        # static AST gate proves the scrub line is WRITTEN first; this It proves it RUNS. -Prune and
        # -ReconcileScope are deliberately left off so the create catch is the only one reachable.
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { throw 'ARM 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'passes -ServicePrincipal to New-OERRoleAssignment when principalType is ServicePrincipal' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'sp-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/.../rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ Id = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'Contoso SP'; principalType = 'ServicePrincipal' }
            $r = @(Invoke-SyncRaViaCaller -Item $Item)
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $ServicePrincipal -eq 'Contoso SP' }
            Should -Invoke Resolve-OERStructurePrincipal -Times 1 -ParameterFilter { $Type -eq 'ServicePrincipal' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'keeps the heuristic (-Group) when principalType is absent and the principal is not a UPN' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'g-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/.../rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ Id = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            @(Invoke-SyncRaViaCaller -Item $Item) | Out-Null
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $Group -eq 'role_sec_x' }
        }
    }

    It 'skips an assignment inherited from an ancestor scope (Scope != reconcile scope) instead of flagging it Extra' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            # atScope() returns the declared at-scope assignment AND one inherited from a parent MG.
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-1'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ Scope = '/providers/Microsoft.Management/managementGroups/parent'; PrincipalId = 'inh-p'; RoleDefinitionId = 'inh-rd'; RoleAssignmentId = 'ra-inherited' }
                )
            }
            Mock Remove-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
            ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'labels an undeclared at-scope assignment with its own identity (role -> principal @ scope), not the triggering item' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope { '/subscriptions/sub-1' }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-1'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = 'ra-declared' },
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'extra-p'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-extra'; RoleAssignmentId = 'ra-extra' }
                )
            }
            Mock Initialize-OERAuth {}
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
            $Extra = $r | Where-Object Action -eq 'Extra'
            $Extra.Item | Should -Be 'rd-extra -> extra-p @ /subscriptions/sub-1'
            $Extra.Item | Should -Not -Match 'role_sec_x'
        }
    }

    Context 'ABAC condition and description' {

        It 'passes -Condition, -ConditionVersion and -Description to New-OERRoleAssignment on create' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment { @() }
                Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'
                    condition = "@Resource[x] StringEquals 'y'"; conditionVersion = '2.0'; description = 'why'
                }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                Should -Invoke New-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
                    $Condition -eq "@Resource[x] StringEquals 'y'" -and $ConditionVersion -eq '2.0' -and $Description -eq 'why'
                }
                ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            }
        }

        It 'reports Unchanged when the live condition and description already match' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'c'; ConditionVersion = '2.0'; Description = 'd'
                    })
                }
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'; condition = 'c'; conditionVersion = '2.0'; description = 'd' }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'updates the existing assignment in place instead of skipping when the live condition differs' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'live-condition'; ConditionVersion = '2.0'; Description = 'd'
                    })
                }
                Mock New-OERRoleAssignment {}
                Mock Set-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'; condition = 'declared-condition'; conditionVersion = '2.0'; description = 'd' }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                ($r | Where-Object { $_.Detail -like '*condition*' }).Action | Should -Be 'Updated'
                Should -Invoke New-OERRoleAssignment -Times 0 -Exactly
                Should -Invoke Set-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
                    $Id -eq '/ra/1' -and $Condition -eq 'declared-condition'
                }
            }
        }

        It 'updates an existing assignment in place when the condition drifts' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s' }
                Mock Resolve-OERStructurePrincipal { '11111111-2222-3333-4444-555555555555' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' }
                Mock Get-OERRoleAssignment {
                    [PSCustomObject]@{
                        RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                        Scope            = '/subscriptions/s'
                        PrincipalId      = '11111111-2222-3333-4444-555555555555'
                        RoleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                        Condition        = 'OLD'
                        ConditionVersion = '2.0'
                        Description      = 'old description'
                    }
                }
                Mock Set-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = 'subscription:s'; role = 'Reader'; principal = 'role_sec_ops'
                    condition = 'NEW'; conditionVersion = '2.0'; description = 'old description'
                }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                ($r | Where-Object { $_.Action -eq 'Updated' }) | Should -Not -BeNullOrEmpty
                ($r | Where-Object { $_.Action -eq 'Skipped' }) | Should -BeNullOrEmpty
                Should -Invoke Set-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
                    $Id -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -and
                    $Condition -eq 'NEW'
                }
            }
        }

        It 'under -WhatIf does not call Set-OERRoleAssignment and emits Skipped with a would-update Detail' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'live-condition'; ConditionVersion = '2.0'; Description = 'd'
                    })
                }
                Mock Set-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'; condition = 'declared-condition'; conditionVersion = '2.0'; description = 'd' }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -WhatIf)
                Should -Invoke Set-OERRoleAssignment -Times 0 -Exactly
                $Skipped = $r | Where-Object { $_.Action -eq 'Skipped' }
                $Skipped | Should -Not -BeNullOrEmpty
                $Skipped.Detail | Should -BeLike '*would update*'
            }
        }

        It 'reports Failed and not Updated when Set-OERRoleAssignment throws' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'live-condition'; ConditionVersion = '2.0'; Description = 'd'
                    })
                }
                Mock Set-OERRoleAssignment { throw 'ARM 500' }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'; condition = 'declared-condition'; conditionVersion = '2.0'; description = 'd' }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false -ErrorAction SilentlyContinue)
                ($r | Where-Object { $_.Action -eq 'Failed' }) | Should -Not -BeNullOrEmpty
                ($r | Where-Object { $_.Action -eq 'Updated' }) | Should -BeNullOrEmpty
            }
        }

        It 'treats an explicit null condition/conditionVersion/description as NOT declared and writes nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'live-condition'; ConditionVersion = '2.0'; Description = 'live description'
                    })
                }
                Mock Set-OERRoleAssignment {}
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                # An explicit JSON null must NOT read as '' -- that would clear the live ABAC condition
                # through Set-OERRoleAssignment and WIDEN the principal's access.
                $Item = '{ "scope": "/subscriptions/s1", "role": "Reader", "principal": "person17@example.com", "condition": null, "conditionVersion": null, "description": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERRoleAssignment -Times 0 -Exactly
                Should -Invoke New-OERRoleAssignment -Times 0 -Exactly
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'reports Unchanged when the document declares neither condition nor description' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        PrincipalId = 'p-1'
                        RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1'
                        Scope = '/subscriptions/s1'; RoleAssignmentId = '/ra/1'
                        Condition = 'live'; ConditionVersion = '2.0'; Description = 'live'
                    })
                }
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com' }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'scope safety on the in-place update path' {

        # Get-OERRoleAssignment -AtScope uses ARM's atScope() filter, which returns assignments at AND
        # ABOVE the scope. A principal+role match owned by an ancestor must never be written: an
        # in-place Set would rewrite the ancestor's grant (a subscription-wide ABAC condition) while
        # reporting the resource group the document declared.
        It 'never passes an ancestor-scope match to Set-OERRoleAssignment and does not create a duplicate' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s/resourceGroups/rg' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd-owner' }
                # The only match is DEFINED at the parent subscription and merely inherited into the rg.
                Mock Get-OERRoleAssignment {
                    @([PSCustomObject]@{
                        Scope            = '/subscriptions/s'
                        PrincipalId      = 'p-1'
                        RoleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd-owner'
                        RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ancestor-ra'
                        Condition        = 'ANCESTOR-CONDITION'; ConditionVersion = '2.0'; Description = 'ancestor'
                    })
                }
                Mock Set-OERRoleAssignment {}
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = '/subscriptions/s/resourceGroups/rg'; role = 'Owner'; principal = 'role_sec_ops'
                    condition = 'DECLARED-CONDITION'; conditionVersion = '2.0'
                }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false -WarningAction SilentlyContinue)
                Should -Invoke Set-OERRoleAssignment -Times 0 -Exactly
                Should -Invoke New-OERRoleAssignment -Times 0 -Exactly
                ($r | Where-Object { $_.Action -eq 'Updated' })   | Should -BeNullOrEmpty
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -BeNullOrEmpty
                $Skipped = $r | Where-Object { $_.Action -eq 'Skipped' }
                $Skipped | Should -Not -BeNullOrEmpty
                $Skipped.Detail | Should -BeLike "*ancestor scope '/subscriptions/s'*"
            }
        }

        It 'updates the at-scope match and ignores an ancestor-scope match returned alongside it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/s/resourceGroups/rg' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd-owner' }
                # The ancestor row comes FIRST, so a Select-Object -First 1 with no scope predicate
                # would pick it.
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{
                            Scope            = '/subscriptions/s'
                            PrincipalId      = 'p-1'
                            RoleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd-owner'
                            RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ancestor-ra'
                            Condition        = 'ANCESTOR-CONDITION'; ConditionVersion = '2.0'
                        },
                        [PSCustomObject]@{
                            Scope            = '/subscriptions/s/resourceGroups/rg'
                            PrincipalId      = 'p-1'
                            RoleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/rd-owner'
                            RoleAssignmentId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Authorization/roleAssignments/rg-ra'
                            Condition        = 'OLD'; ConditionVersion = '2.0'
                        }
                    )
                }
                Mock Set-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = '/subscriptions/s/resourceGroups/rg'; role = 'Owner'; principal = 'role_sec_ops'
                    condition = 'NEW'; conditionVersion = '2.0'
                }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -Confirm:$false)
                ($r | Where-Object { $_.Action -eq 'Updated' }) | Should -Not -BeNullOrEmpty
                Should -Invoke Set-OERRoleAssignment -Times 1 -Exactly -ParameterFilter {
                    $Id -eq '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Authorization/roleAssignments/rg-ra' -and
                    $Condition -eq 'NEW'
                }
                Should -Invoke Set-OERRoleAssignment -Times 0 -Exactly -ParameterFilter {
                    $Id -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/ancestor-ra'
                }
            }
        }
    }

    Context 'scope-wide sibling principalType resolution (site 345)' {
        # Get-ScopeSplat maps 'subscription:Prod' to -Subscription 'Prod'; Resolve-OERScope is mocked
        # to a fixed value regardless of the splat, matching the convention used elsewhere in this file.
        # Two siblings share the scope: the primary item (main_group/Reader) and a second sibling
        # (sibling_group/Owner). Both have a matching CURRENT assignment. The declared key set built
        # from the siblings loop must include BOTH. A sibling that drops out of it -- exactly what a
        # sibling principalType coerced into a bad -Type argument at site 345 causes -- is recorded as
        # unresolved under the withheld rule, so the regression now surfaces as a Skipped row whose
        # Detail starts 'prune withheld' rather than as Extra. Each It therefore also asserts that no
        # prune-withheld row appears; that added assertion is the one that catches the regression.
        It 'passes the declared principalType to Resolve-OERStructurePrincipal for a sibling declared with a value, and its current assignment is not flagged Extra' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    switch ($Reference) {
                        'main_group'    { 'p-main' }
                        'sibling_group' { 'p-sibling' }
                    }
                }
                Mock Resolve-OERRoleDefinitionId {
                    param($Role, $Scope)
                    switch ($Role) {
                        'Reader' { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                        'Owner'  { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner' }
                    }
                }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-sibling'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner'; RoleAssignmentId = 'ra-sibling' }
                    )
                }
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling     = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Owner'; principal = 'sibling_group'; principalType = 'Group' }
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
                Should -Invoke Resolve-OERStructurePrincipal -Times 1 -Exactly -ParameterFilter {
                    $Reference -eq 'sibling_group' -and $Type -eq 'Group'
                }
                ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^prune withheld' }).Count | Should -Be 0
            }
        }

        It 'does not pass -Type to Resolve-OERStructurePrincipal for a sibling with principalType declared explicit null, and its current assignment is not flagged Extra (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    switch ($Reference) {
                        'main_group'    { 'p-main' }
                        'sibling_group' { 'p-sibling' }
                    }
                }
                Mock Resolve-OERRoleDefinitionId {
                    param($Role, $Scope)
                    switch ($Role) {
                        'Reader' { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                        'Owner'  { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner' }
                    }
                }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-sibling'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner'; RoleAssignmentId = 'ra-sibling' }
                    )
                }
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling = '{ "scope": "subscription:Prod", "role": "Owner", "principal": "sibling_group", "principalType": null }' | ConvertFrom-Json
                # MUTATION PROOF: with the old `PSObject.Properties.Name -contains 'principalType'`
                # guard, this sibling's null value is coerced into -Type $null on the call below.
                # Resolve-OERStructurePrincipal's -Type carries [ValidateSet('User','Group',
                # 'ServicePrincipal')], and Pester's Mock preserves that validation on the proxy it
                # builds, so a null value there throws a ParameterBindingValidationException that the
                # handler's own catch swallows -- dropping this sibling out of the declared key set.
                # Under the withheld rule the dropped sibling is recorded as unresolved, so ra-sibling
                # (a live, correctly-declared assignment) now surfaces as a Skipped row whose Detail
                # starts 'prune withheld' -- no longer as Extra, which leaves the Extra assertion green
                # on its own. Revert the fix and this It fails on the prune-withheld assertion below;
                # see the task report for the quoted failing output.
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
                ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^prune withheld' }).Count | Should -Be 0
            }
        }

        It 'does not pass -Type to Resolve-OERStructurePrincipal for a sibling with principalType omitted, and its current assignment is not flagged Extra (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    switch ($Reference) {
                        'main_group'    { 'p-main' }
                        'sibling_group' { 'p-sibling' }
                    }
                }
                Mock Resolve-OERRoleDefinitionId {
                    param($Role, $Scope)
                    switch ($Role) {
                        'Reader' { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                        'Owner'  { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner' }
                    }
                }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-sibling'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-owner'; RoleAssignmentId = 'ra-sibling' }
                    )
                }
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling     = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Owner'; principal = 'sibling_group' }
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
                ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^prune withheld' }).Count | Should -Be 0
            }
        }
    }

    Context 'prune withheld when a declared sibling cannot be resolved' {
        # The handler item (main_group) resolves; the SECOND sibling in -DeclaredAtScope
        # (missing_group) does not. It carries no key, so the live undeclared assignment at the scope
        # may be its counterpart: the scope-wide pass must report that candidate Skipped with the
        # withheld reason instead of Extra or Removed. The sibling's own invocation (the engine gives
        # every item one) then reports the sibling itself as Failed under the label the reason names.
        It 'withholds the prune of an undeclared at-scope assignment when a second sibling resolves to null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    if ($Reference -eq 'main_group') { 'p-main' } else { $null }
                }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-live'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-live' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling     = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'missing_group' }
                $SiblingLabel = 'Reader -> missing_group @ subscription:Prod'
                $Warnings = @()
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                        -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match ('^prune withheld: declared entry ''{0}'' could not be resolved' -f [regex]::Escape($SiblingLabel))
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'p-live'
                # The sibling's own invocation reports it Failed under the label the reason names.
                $SiblingRows = @(Invoke-SyncRaViaCaller -Item $Sibling -DeclaredAtScope @($PrimaryItem, $Sibling) -ErrorAction SilentlyContinue)
                @($SiblingRows | Where-Object { $_.Action -eq 'Failed' -and $_.Item -eq $SiblingLabel }).Count | Should -Be 1
            }
        }

        It 'withholds the prune of an undeclared at-scope assignment when a second sibling lookup throws' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    if ($Reference -eq 'main_group') { 'p-main' } else { throw 'Graph 503 while resolving missing_group' }
                }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-live'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-live' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling     = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'missing_group' }
                $SiblingLabel = 'Reader -> missing_group @ subscription:Prod'
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                        -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match ('^prune withheld: declared entry ''{0}'' could not be resolved' -f [regex]::Escape($SiblingLabel))
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                # The swallowed sibling throw writes no error of its own in the scope-wide pass.
                @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                $SiblingRows = @(Invoke-SyncRaViaCaller -Item $Sibling -DeclaredAtScope @($PrimaryItem, $Sibling) -ErrorAction SilentlyContinue)
                @($SiblingRows | Where-Object { $_.Action -eq 'Failed' -and $_.Item -eq $SiblingLabel }).Count | Should -Be 1
            }
        }

        It 'reports the candidate Skipped with the withheld reason, not Extra, when -Prune is not set' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERScope { '/subscriptions/sub-1' }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    if ($Reference -eq 'main_group') { 'p-main' } else { $null }
                }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader' }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-main'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-main' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-live'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'; RoleAssignmentId = 'ra-live' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'main_group' }
                $Sibling     = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'missing_group' }
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''Reader -> missing_group @ subscription:Prod'' could not be resolved'
            }
        }
    }
}
