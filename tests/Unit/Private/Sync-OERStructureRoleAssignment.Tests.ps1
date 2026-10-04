BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Sync-OERStructureRoleAssignment' {

    # The engine resolves the scope before dispatch and hands the handler the canonical resolved scope
    # as -ResolvedScope. The handler never resolves it again: that exact string reaches every ARM call,
    # whatever the document wrote (subscription:Prod, mg:platform, a raw path with a trailing '/').
    It 'passes the resolved scope of subscription:Prod as -Scope to every ARM call, never resolves it again, and creates a missing assignment with -Group for non-@ principal' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope {}
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-1" }
            Mock Get-OERRoleAssignment { param($Scope, [switch]$AtScope) @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/sub-1')
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke Resolve-OERRoleDefinitionId -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/sub-1' }
            Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/sub-1' -and $AtScope }
            Should -Invoke New-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/sub-1' -and $Group -eq 'role_sec_x' }
            Should -Invoke Resolve-OERScope -Times 0
        }
    }

    It 'passes the resolved scope of mg:platform as -Scope to every ARM call, never resolves it again, and creates a missing assignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope {}
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-1" }
            Mock Get-OERRoleAssignment { param($Scope, [switch]$AtScope) @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-mg-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'mg:platform'; role = 'Reader'; principal = 'role_sec_platform' }) -ResolvedScope '/providers/Microsoft.Management/managementGroups/platform')
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke Resolve-OERRoleDefinitionId -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/providers/Microsoft.Management/managementGroups/platform' }
            Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/providers/Microsoft.Management/managementGroups/platform' -and $AtScope }
            Should -Invoke New-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/providers/Microsoft.Management/managementGroups/platform' -and $Group -eq 'role_sec_platform' }
            Should -Invoke Resolve-OERScope -Times 0
        }
    }

    It 'uses -User when the principal contains @' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'u-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-u-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'anna@contoso.com' }) -ResolvedScope '/subscriptions/sub-1')
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $User -eq 'anna@contoso.com' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged and does not call New-OERRoleAssignment when assignment already exists' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/sub-1')
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'passes the resolved scope, not the scope text the document wrote, as -Scope to every ARM call and keeps the written text in the label' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERScope {}
            Mock Resolve-OERStructurePrincipal { 'p-raw' }
            Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/rd-raw" }
            Mock Get-OERRoleAssignment { param($Scope, [switch]$AtScope) @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-raw' } }
            Mock Initialize-OERAuth {}
            # The document wrote a trailing '/'; the engine's canonical resolved scope carries none.
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = '/subscriptions/x/resourceGroups/y/'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/x/resourceGroups/y')
            @($r | Where-Object Action -eq 'Created' | ForEach-Object { $_.Item }) | Should -BeExactly @('Reader -> role_sec_x @ /subscriptions/x/resourceGroups/y/')
            Should -Invoke Resolve-OERRoleDefinitionId -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/x/resourceGroups/y' }
            Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/x/resourceGroups/y' -and $AtScope }
            Should -Invoke New-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/x/resourceGroups/y' }
            Should -Invoke Resolve-OERScope -Times 0
        }
    }

    It 'reports Failed and does not call New-OERRoleAssignment when principal is unresolvable' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { $null }
            Mock Resolve-OERRoleDefinitionId { 'rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'no_such_group' }) -ResolvedScope '/subscriptions/sub-1' -ErrorAction SilentlyContinue)
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -ReconcileScope and -Prune removes an undeclared current assignment via -Id and emits Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERRoleAssignment -Times 1 -ParameterFilter { $Id -eq 'ra-extra' }
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing for the scope prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $null = Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WhatIf -WarningAction SilentlyContinue -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for the scope prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $null = Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'streams only its own warning for the scope prune, silencing the duplicate the real Remove cmdlet writes' {
        # Remove-OERRoleAssignment runs for REAL: only auth and the ARM transport are mocked, so its own
        # "Deleting Azure role assignment" warning is written inside its gate. The warning stream itself
        # is captured (3>&1): -WarningVariable would also collect a warning the cmdlet writes under a
        # call-site SilentlyContinue, which never reaches the stream.
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment {
                @(
                    [PSCustomObject]@{ PrincipalId = 'p-1';     RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1'; RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-declared' },
                    [PSCustomObject]@{ PrincipalId = 'other-p'; RoleDefinitionId = 'other-rd'; RoleAssignmentId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleAssignments/ra-extra' }
                )
            }
            Mock Initialize-OERAuth {}
            Mock Invoke-OERArmRequest { if ($Method -eq 'DELETE') { return [PSCustomObject]@{ id = 'ra-extra' } }; throw "unexpected $Method $Path" }
            $DeclaredItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            $All = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -ErrorAction Stop 3>&1)
            $Records = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $Streamed = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
            # The DELETE ran, so the cmdlet passed its own gate and reached its own warning.
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Path -like '*/roleAssignments/ra-extra?api-version=*' }
            $Streamed.Count | Should -Be 1
            $Streamed[0] | Should -BeLike "Sync-OERStructureRoleAssignment: removing undeclared assignment 'other-rd'*"
        }
    }

    It 'with -ReconcileScope without -Prune reports undeclared assignment as Extra and does not call Remove-OERRoleAssignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
            Should -Invoke Remove-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    It 'without -ReconcileScope does not report Extra or Removed for an undeclared current assignment' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($DeclaredItem))
            Should -Invoke Remove-OERRoleAssignment -Times 0
            ($r | Where-Object { $_.Action -eq 'Extra' -or $_.Action -eq 'Removed' }).Count | Should -Be 0
        }
    }

    It 'under -WhatIf does not call New-OERRoleAssignment and emits Skipped' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/sub-1' -WhatIf)
            Should -Invoke New-OERRoleAssignment -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'when New-OERRoleAssignment throws emits Failed and not Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { throw 'ARM 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/sub-1' -ErrorAction SilentlyContinue)
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
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'p-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { throw 'ARM 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/sub-1' -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'passes -ServicePrincipal to New-OERRoleAssignment when principalType is ServicePrincipal' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'sp-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/.../rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ Id = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'Contoso SP'; principalType = 'ServicePrincipal' }
            $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/sub-1')
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $ServicePrincipal -eq 'Contoso SP' }
            Should -Invoke Resolve-OERStructurePrincipal -Times 1 -ParameterFilter { $Type -eq 'ServicePrincipal' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'keeps the heuristic (-Group) when principalType is absent and the principal is not a UPN' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            Mock Resolve-OERStructurePrincipal { 'g-1' }
            Mock Resolve-OERRoleDefinitionId { '/subscriptions/sub-1/.../rd-1' }
            Mock Get-OERRoleAssignment { @() }
            Mock New-OERRoleAssignment { [PSCustomObject]@{ Id = 'ra-1' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'role_sec_x' }
            @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/sub-1') | Out-Null
            Should -Invoke New-OERRoleAssignment -Times 1 -ParameterFilter { $Group -eq 'role_sec_x' }
        }
    }

    It 'skips an assignment inherited from an ancestor scope (Scope != reconcile scope) instead of flagging it Extra' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
            ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'labels an undeclared at-scope assignment with its own identity (role -> principal @ scope), not the triggering item' {
        InModuleScope $script:moduleName {
            function Invoke-SyncRaViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
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
            $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($DeclaredItem) -ReconcileScope)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment { @() }
                Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    scope = '/subscriptions/s1'; role = 'Reader'; principal = 'person17@example.com'
                    condition = "@Resource[x] StringEquals 'y'"; conditionVersion = '2.0'; description = 'why'
                }
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false)
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'updates the existing assignment in place instead of skipping when the live condition differs' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s' -Confirm:$false)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -WhatIf)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false -ErrorAction SilentlyContinue)
                ($r | Where-Object { $_.Action -eq 'Failed' }) | Should -Not -BeNullOrEmpty
                ($r | Where-Object { $_.Action -eq 'Updated' }) | Should -BeNullOrEmpty
            }
        }

        It 'treats an explicit null condition/conditionVersion/description as NOT declared and writes nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false)
                Should -Invoke Set-OERRoleAssignment -Times 0 -Exactly
                Should -Invoke New-OERRoleAssignment -Times 0 -Exactly
                ($r | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'reports Unchanged when the document declares neither condition nor description' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s1' -Confirm:$false)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s/resourceGroups/rg' -Confirm:$false -WarningAction SilentlyContinue)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $Item -ResolvedScope '/subscriptions/s/resourceGroups/rg' -Confirm:$false)
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
        # The resolved scope is handed in as -ResolvedScope '/subscriptions/sub-1' whatever the item's
        # scope text, matching the convention used elsewhere in this file. Two siblings share the scope: the primary item (main_group/Reader) and a second sibling
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
                ($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^prune withheld' }).Count | Should -Be 0
            }
        }

        It 'does not pass -Type to Resolve-OERStructurePrincipal for a sibling with principalType omitted, and its current assignment is not flagged Extra (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope)
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
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                        -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match ('^prune withheld: declared entry ''{0}'' could not be resolved' -f [regex]::Escape($SiblingLabel))
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'p-live'
                # The sibling's own invocation reports it Failed under the label the reason names.
                $SiblingRows = @(Invoke-SyncRaViaCaller -Item $Sibling -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ErrorAction SilentlyContinue)
                @($SiblingRows | Where-Object { $_.Action -eq 'Failed' -and $_.Item -eq $SiblingLabel }).Count | Should -Be 1
            }
        }

        It 'withholds the prune of an undeclared at-scope assignment when a second sibling lookup throws' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                        -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match ('^prune withheld: declared entry ''{0}'' could not be resolved' -f [regex]::Escape($SiblingLabel))
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                # The swallowed sibling throw writes no error of its own in the scope-wide pass.
                @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                $SiblingRows = @(Invoke-SyncRaViaCaller -Item $Sibling -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ErrorAction SilentlyContinue)
                @($SiblingRows | Where-Object { $_.Action -eq 'Failed' -and $_.Item -eq $SiblingLabel }).Count | Should -Be 1
            }
        }

        It 'reports the candidate Skipped with the withheld reason, not Extra, when -Prune is not set' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERRoleAssignment -Times 0
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''Reader -> missing_group @ subscription:Prod'' could not be resolved'
            }
        }
    }

    Context 'role definitions match on their GUID, never on the whole id (BL-35)' {
        # A role definition id is anchored at whatever scope it was read from. The resolver anchors a
        # GUID at the scope it is given (resource group, management group), while Azure Resource
        # Manager reports a live assignment at a resource group with the SUBSCRIPTION-anchored id
        # (measured live) and one at a management group with the tenant-anchored id. A GUID names one
        # role definition everywhere, so the match and the prune key compare the last segment of the id,
        # without regard to letter case, and never the whole path. The Reader built-in role GUID is
        # the one real GUID used here; every other id is a placeholder.
        It 'reports a GUID role at a resource group Unchanged against the live subscription-anchored id and prunes only what is undeclared' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                # What the real resolver builds for a GUID: the id anchored at the scope it was given.
                Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/$Role" }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1/resourceGroups/rg1'; PrincipalId = 'p-1'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-declared' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1/resourceGroups/rg1'; PrincipalId = 'p-other'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-other-principal' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1/resourceGroups/rg1'; PrincipalId = 'p-1'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/aaaa1111-0000-0000-0000-000000000002'; RoleAssignmentId = 'ra-other-role' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $DeclaredItem = [PSCustomObject]@{ scope = '/subscriptions/sub-1/resourceGroups/rg1'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = 'role_sec_x' }
                $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1/resourceGroups/rg1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue)
                # The declared row matches the live one: Unchanged, never re-created, never removed.
                @($r | Where-Object Action -eq 'Unchanged').Count | Should -Be 1
                Should -Invoke New-OERRoleAssignment -Times 0
                Should -Invoke Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -eq 'ra-declared' }
                # Positive control: the pass ran, and removed a different principal and a different role GUID.
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-other-principal' }
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-other-role' }
                Should -Invoke Remove-OERRoleAssignment -Times 2 -Exactly
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 2
            }
        }

        It 'compares the GUID without regard to letter case: an upper-case tenant-anchored role against a lower-case subscription-anchored live id is Unchanged' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                # The real resolver returns a full role definition id exactly as written.
                Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) $Role }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-1'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-declared' },
                        [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'p-other'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-other-principal' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $DeclaredItem = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = '/providers/Microsoft.Authorization/roleDefinitions/ACDD72A7-3385-48EF-BD42-F606FBA81AE7'; principal = 'role_sec_x' }
                $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue)
                @($r | Where-Object Action -eq 'Unchanged').Count | Should -Be 1
                Should -Invoke New-OERRoleAssignment -Times 0
                Should -Invoke Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -eq 'ra-declared' }
                # Positive control: the pass ran and removed the undeclared principal's assignment.
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-other-principal' }
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly
            }
        }

        It 'reports a GUID role at a management group Unchanged against the live tenant-anchored id and prunes only what is undeclared' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/$Role" }
                Mock Get-OERRoleAssignment {
                    @(
                        [PSCustomObject]@{ Scope = '/providers/Microsoft.Management/managementGroups/plat'; PrincipalId = 'p-1'; RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-declared' },
                        [PSCustomObject]@{ Scope = '/providers/Microsoft.Management/managementGroups/plat'; PrincipalId = 'p-other'; RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-other-principal' }
                    )
                }
                Mock Remove-OERRoleAssignment {}
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $DeclaredItem = [PSCustomObject]@{ scope = '/providers/Microsoft.Management/managementGroups/plat'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = 'role_sec_x' }
                $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/providers/Microsoft.Management/managementGroups/plat' -Prune -DeclaredAtScope @($DeclaredItem) -ReconcileScope -WarningAction SilentlyContinue)
                @($r | Where-Object Action -eq 'Unchanged').Count | Should -Be 1
                Should -Invoke New-OERRoleAssignment -Times 0
                Should -Invoke Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -eq 'ra-declared' }
                # Positive control: the pass ran and removed the undeclared principal's assignment.
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-other-principal' }
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly
            }
        }

        It 'still hands Azure Resource Manager the role exactly as the document wrote it when it creates the assignment' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { param($Role, $Scope) "$Scope/providers/Microsoft.Authorization/roleDefinitions/$Role" }
                Mock Get-OERRoleAssignment { @() }
                Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-new' } }
                Mock Initialize-OERAuth {}
                $DeclaredItem = [PSCustomObject]@{ scope = '/subscriptions/sub-1/resourceGroups/rg1'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = 'role_sec_x' }
                $r = @(Invoke-SyncRaViaCaller -Item $DeclaredItem -ResolvedScope '/subscriptions/sub-1/resourceGroups/rg1')
                @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
                Should -Invoke New-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Role -ceq 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -and $Scope -ceq '/subscriptions/sub-1/resourceGroups/rg1' }
            }
        }
    }
}

Describe 'Sync-OERStructureRoleAssignment with an ambiguous service principal display name' {
    # Resolve-OERStructurePrincipal and Resolve-OERApplicationId run for REAL here: only the Graph
    # transport is mocked, and its servicePrincipals query answers with two service principals that
    # share the display name 'Dup App'. The resolved scope is handed in as -ResolvedScope, and role and
    # the ARM cmdlets are mocked as in the suite above. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncRaAmbiguous {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
            }
            $script:RaRoleId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/rd-reader'
            $script:RaLive = @()
            Mock Initialize-OERAuth {}
            Mock Resolve-OERRoleDefinitionId { $script:RaRoleId }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' } -MockWith {
                @{ value = @(
                        @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup App' },
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup App' }) }
            }
            Mock Invoke-OERGraphRequest -MockWith { throw 'unexpected Graph request' }
            Mock Get-OERRoleAssignment { $script:RaLive }
            Mock New-OERRoleAssignment {}
            Mock Set-OERRoleAssignment {}
            Mock Remove-OERRoleAssignment {}
        }
    }

    It 'reports the entry Failed with both candidate ids, and reads and writes nothing' {
        InModuleScope $script:moduleName {
            $Item = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'Dup App'; principalType = 'ServicePrincipal' }
            $r = @(Invoke-SyncRaAmbiguous -Item $Item -ResolvedScope '/subscriptions/sub-1' -ErrorAction SilentlyContinue)
            @($r).Action | Should -Be @('Failed')
            $r[0].Item | Should -BeExactly 'Reader -> Dup App @ subscription:Prod'
            $r[0].Detail | Should -Match "could not resolve principal 'Dup App'"
            $r[0].Detail | Should -Match '11111111-1111-1111-1111-111111111111'
            $r[0].Detail | Should -Match '22222222-2222-2222-2222-222222222222'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
            Should -Invoke Get-OERRoleAssignment -Times 0
            Should -Invoke New-OERRoleAssignment -Times 0
            Should -Invoke Set-OERRoleAssignment -Times 0
        }
    }

    It 'withholds the scope-wide prune when a declared sibling names it: the undeclared candidate is Skipped, never Extra or Removed' {
        InModuleScope $script:moduleName {
            $script:RaLive = @(
                [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = 'bbbbbbbb-0000-0000-0000-000000000001'; RoleDefinitionId = $script:RaRoleId; RoleAssignmentId = 'ra-main' }
                [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = '22222222-2222-2222-2222-222222222222'; RoleDefinitionId = $script:RaRoleId; RoleAssignmentId = 'ra-sp' }
            )
            $PrimaryItem = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'bbbbbbbb-0000-0000-0000-000000000001' }
            $Sibling = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'Dup App'; principalType = 'ServicePrincipal' }
            $r = @(Invoke-SyncRaAmbiguous -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            @($r).Action | Should -Be @('Unchanged', 'Skipped')
            $r[1].Item | Should -BeExactly 'rd-reader -> 22222222-2222-2222-2222-222222222222 @ /subscriptions/sub-1'
            $r[1].Detail | Should -Match ('^prune withheld: declared entry ''{0}'' could not be resolved' -f [regex]::Escape('Reader -> Dup App @ subscription:Prod'))
            @($r | Where-Object { $_.Action -in @('Extra', 'Removed') }).Count | Should -Be 0
            Should -Invoke Remove-OERRoleAssignment -Times 0
            # The withheld row comes from the servicePrincipals answer, not the catch-all mock's throw.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
        }
    }
}
