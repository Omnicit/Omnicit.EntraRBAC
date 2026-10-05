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
            # The document wrote the scope in another letter case; the engine hands the handler the
            # group's resolved scope, spelled as the first entry of the group spelled it.
            $r = @(Invoke-SyncRaViaCaller -Item ([PSCustomObject]@{ scope = '/SUBSCRIPTIONS/x/resourceGroups/Y'; role = 'Reader'; principal = 'role_sec_x' }) -ResolvedScope '/subscriptions/x/resourceGroups/y')
            @($r | Where-Object Action -eq 'Created' | ForEach-Object { $_.Item }) | Should -BeExactly @('Reader -> role_sec_x @ /SUBSCRIPTIONS/x/resourceGroups/Y')
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

    Context 'prune withheld when the scope of a declared entry elsewhere in the section could not be resolved' {
        # The engine resolves every entry's scope before dispatch. An entry whose scope failed to
        # resolve is never dispatched and carries no scope, so it may be another spelling of ANY scope
        # in the section: the engine hands every dispatched entry its label as -ScopeUnresolved, and
        # the prune pass of each scope then withholds every undeclared candidate, with or without
        # -Prune. The entry that did resolve is still processed in full (its own row below).
        It 'withholds the prune of an undeclared at-scope assignment and still reconciles the entry itself' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope, [string[]]$ScopeUnresolved)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope -ScopeUnresolved $ScopeUnresolved
                }
                Mock Resolve-OERStructurePrincipal { 'p-main' }
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
                $Warnings = @()
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($PrimaryItem) -ReconcileScope `
                        -ScopeUnresolved @('Reader -> x @ sub:Gone') -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)

                # Positive proof first: the entry was processed and its own live assignment is Unchanged.
                @($r | Where-Object { $_.Item -eq 'Reader -> main_group @ subscription:Prod' }).Action | Should -Be @('Unchanged')
                Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/sub-1' -and $AtScope }

                # The undeclared candidate is withheld, not removed, not Extra, and not warned about.
                $Withheld = @($r | Where-Object { $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Action | Should -Be 'Skipped'
                $Withheld[0].Detail.StartsWith("prune withheld: the scope of declared entry 'Reader -> x @ sub:Gone'") | Should -BeTrue
                Should -Invoke Remove-OERRoleAssignment -Times 0
                @($r | Where-Object Action -in 'Removed', 'Extra').Count | Should -Be 0
                @($Warnings).Count | Should -Be 0
            }
        }

        It 'reports the candidate Skipped, never Extra, when -Prune is not set' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope, [string[]]$ScopeUnresolved)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope -ScopeUnresolved $ScopeUnresolved
                }
                Mock Resolve-OERStructurePrincipal { 'p-main' }
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -DeclaredAtScope @($PrimaryItem) -ReconcileScope `
                        -ScopeUnresolved @('Reader -> x @ sub:Gone') -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Item -eq 'Reader -> main_group @ subscription:Prod' }).Action | Should -Be @('Unchanged')
                $Withheld = @($r | Where-Object { $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Action | Should -Be 'Skipped'
                $Withheld[0].Detail.StartsWith("prune withheld: the scope of declared entry 'Reader -> x @ sub:Gone'") | Should -BeTrue
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                Should -Invoke Remove-OERRoleAssignment -Times 0
            }
        }

        It 'names the unresolved scope after the unresolved sibling when both withhold the same candidate' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope, [string[]]$ScopeUnresolved)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope -ScopeUnresolved $ScopeUnresolved
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
                $r = @(Invoke-SyncRaViaCaller -Item $PrimaryItem -ResolvedScope '/subscriptions/sub-1' -Prune -DeclaredAtScope @($PrimaryItem, $Sibling) -ReconcileScope `
                        -ScopeUnresolved @('Reader -> x @ sub:Gone') -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Remove-OERRoleAssignment -Times 0
                $Withheld = @($r | Where-Object { $_.Item -eq 'rd-reader -> p-live @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Action | Should -Be 'Skipped'
                $Withheld[0].Detail.StartsWith("prune withheld: declared entry 'Reader -> missing_group @ subscription:Prod' could not be resolved") | Should -BeTrue
                $Withheld[0].Detail.EndsWith(" The scope of declared entry 'Reader -> x @ sub:Gone' could not be resolved either.") | Should -BeTrue
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

    Context 'a second entry that resolves to the same assignment fails and is not written (Scope 3)' {
        # Two entries that resolve to the same scope, principal and role name ONE assignment. The
        # later one is reported Failed and writes nothing -- no read, no create, no in-place update --
        # and its key stays in the declared set, so the prune never removes the assignment. The engine
        # hands every invocation of one resolved scope the same -SiblingKeyCache, the document index of
        # the entry (-ItemIndex) and the document index of every sibling (-DeclaredAtScopeIndex). The
        # entries below sit at document indexes 0, 3 and 5, so a position and a document index differ.
        # No id is version-4 shaped; the Reader built-in role id is the one real GUID.
        BeforeEach {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncRaDup {
                    [CmdletBinding(SupportsShouldProcess)]
                    param(
                        [PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope,
                        [string]$ResolvedScope = '/subscriptions/sub-1', [int]$ItemIndex = -1,
                        [int[]]$DeclaredAtScopeIndex = @(), [hashtable]$SiblingKeyCache
                    )
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune `
                        -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope -ItemIndex $ItemIndex `
                        -DeclaredAtScopeIndex $DeclaredAtScopeIndex -SiblingKeyCache $SiblingKeyCache
                }
                $script:DupLive = @()
                Mock Initialize-OERAuth {}
                Mock Resolve-OERStructurePrincipal {
                    param($Reference, $Type)
                    if ($Reference -eq 'grp1') { '11111111-aaaa-0000-0000-000000000001' }
                    elseif ($Reference -eq 'good_group') { '11111111-aaaa-0000-0000-000000000003' }
                    elseif ($Reference -eq 'bad_group') { throw 'Graph 503 while resolving bad_group' }
                    elseif ($Reference -like '11111111-aaaa-0000-0000-*') { $Reference }
                    else { $null }
                }
                Mock Resolve-OERRoleDefinitionId {
                    param($Role, $Scope)
                    $RoleGuid = if ($Role -eq 'Reader') { 'acdd72a7-3385-48ef-bd42-f606fba81ae7' } else { $Role }
                    "$Scope/providers/Microsoft.Authorization/roleDefinitions/$RoleGuid"
                }
                Mock Get-OERRoleAssignment { $script:DupLive }
                Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-new' } }
                Mock Set-OERRoleAssignment {}
                Mock Remove-OERRoleAssignment {}
            }
        }

        It 'reports the later entry Failed with the earlier one named, and creates the assignment only once' {
            InModuleScope $script:moduleName {
                $First  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'grp1' }
                $Second = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = '11111111-aaaa-0000-0000-000000000001' }
                $Cache = @{}
                $Declared = @($First, $Second)
                $r0 = @(Invoke-SyncRaDup -Item $First -ItemIndex 0 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ReconcileScope -ErrorAction SilentlyContinue)
                $r3 = @(Invoke-SyncRaDup -Item $Second -ItemIndex 3 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ErrorAction SilentlyContinue -ErrorVariable DupErr)

                # Positive proof first: the earlier entry was created, so the handler reached the write.
                @($r0).Action | Should -Be @('Created')
                @($r3).Count | Should -Be 1
                $r3[0].Action | Should -Be 'Failed'
                $r3[0].Item | Should -BeExactly 'acdd72a7-3385-48ef-bd42-f606fba81ae7 -> 11111111-aaaa-0000-0000-000000000001 @ /subscriptions/sub-1'
                $r3[0].Detail | Should -BeExactly "roleAssignments[3] resolves to the same assignment as roleAssignments[0] ('Reader -> grp1 @ sub:Prod'): the same scope '/subscriptions/sub-1', principal and role. Nothing was written for this entry; keep one of the two entries."
                # A document error, like the unresolved principal: no error record is written.
                @($DupErr).Count | Should -Be 0
                # Only the earlier entry read the live state and wrote.
                Should -Invoke New-OERRoleAssignment -Times 1 -Exactly
                Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly
                Should -Invoke Set-OERRoleAssignment -Times 0
                Should -Invoke Remove-OERRoleAssignment -Times 0
            }
        }

        It 'never updates or prunes the assignment the later entry duplicates, and still prunes what is undeclared' {
            InModuleScope $script:moduleName {
                $RoleId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                $script:DupLive = @(
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = '11111111-aaaa-0000-0000-000000000001'; RoleDefinitionId = $RoleId; RoleAssignmentId = 'ra-1'; Description = 'live text' }
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = '11111111-aaaa-0000-0000-000000000009'; RoleDefinitionId = $RoleId; RoleAssignmentId = 'ra-2' }
                )
                # The earlier entry declares no description (Unchanged); the later one declares a
                # description that differs from the live one, and would be applied in place.
                $First  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'grp1' }
                $Second = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = '11111111-aaaa-0000-0000-000000000001'; description = 'declared text' }
                $Cache = @{}
                $Declared = @($First, $Second)
                $r0 = @(Invoke-SyncRaDup -Item $First -ItemIndex 0 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -Prune -ReconcileScope -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                $r3 = @(Invoke-SyncRaDup -Item $Second -ItemIndex 3 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # Positive proof first: the prune pass ran, and removed the undeclared assignment once.
                @($r0 | Where-Object Action -eq 'Unchanged').Count | Should -Be 1
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Id -eq 'ra-2' }
                @($r3).Action | Should -Be @('Failed')
                # The declared assignment is neither edited nor removed.
                Should -Invoke Set-OERRoleAssignment -Times 0
                Should -Invoke Remove-OERRoleAssignment -Times 0 -ParameterFilter { $Id -eq 'ra-1' }
                Should -Invoke Remove-OERRoleAssignment -Times 1 -Exactly
            }
        }

        It 'resolves the siblings of a group once for all the invocations that share the cache' {
            InModuleScope $script:moduleName {
                $First  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'grp1' }
                $Second = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = '11111111-aaaa-0000-0000-000000000001' }
                $Cache = @{}
                $Declared = @($First, $Second)
                $r0 = @(Invoke-SyncRaDup -Item $First -ItemIndex 0 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ReconcileScope -ErrorAction SilentlyContinue)
                $r3 = @(Invoke-SyncRaDup -Item $Second -ItemIndex 3 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ErrorAction SilentlyContinue)

                # Positive proof first: both invocations ran in full, the second one to its duplicate verdict.
                @($r0).Action | Should -Be @('Created')
                @($r3).Action | Should -Be @('Failed')
                # Each entry's own lookup once, plus the group's two siblings once -- not once per use.
                Should -Invoke Resolve-OERStructurePrincipal -Times 4 -Exactly
                Should -Invoke Resolve-OERRoleDefinitionId -Times 4 -Exactly
            }
        }

        It 'does not mistake an unresolved earlier entry for a duplicate, and withholds the prune naming it' {
            InModuleScope $script:moduleName {
                # Entry 0 names a principal whose lookup throws, so it carries no key. Entry 1 must not be
                # failed as its duplicate: it reconciles. The pass then withholds the prune, since the
                # live assignment that is undeclared here may be entry 0's own.
                $script:DupLive = @(
                    [PSCustomObject]@{ Scope = '/subscriptions/sub-1'; PrincipalId = '11111111-aaaa-0000-0000-000000000009'; RoleDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; RoleAssignmentId = 'ra-live' }
                )
                $Bad  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'bad_group' }
                $Good = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'good_group' }
                $Cache = @{}
                $Declared = @($Bad, $Good)
                $rBad = @(Invoke-SyncRaDup -Item $Bad -ItemIndex 0 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 1) -SiblingKeyCache $Cache -ReconcileScope -ErrorAction SilentlyContinue)
                $rGood = @(Invoke-SyncRaDup -Item $Good -ItemIndex 1 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 1) -SiblingKeyCache $Cache -ErrorAction SilentlyContinue)
                $rPass = @(Invoke-SyncRaDup -Item $Good -ItemIndex 1 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 1) -SiblingKeyCache $Cache -Prune -ReconcileScope -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # Positive proof first: the unresolved entry is Failed for its own lookup, not as a duplicate.
                @($rBad).Action | Should -Be @('Failed')
                $rBad[0].Detail | Should -Match "^could not resolve principal 'bad_group'"
                @($rGood).Action | Should -Be @('Created')
                Should -Invoke New-OERRoleAssignment -Times 2 -Exactly -ParameterFilter { $Group -eq 'good_group' }
                # The third call is the prune pass: the undeclared candidate is Skipped, never removed.
                $Withheld = @($rPass | Where-Object { $_.Action -eq 'Skipped' -and $_.Item -eq 'acdd72a7-3385-48ef-bd42-f606fba81ae7 -> 11111111-aaaa-0000-0000-000000000009 @ /subscriptions/sub-1' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail.StartsWith("prune withheld: declared entry 'Reader -> bad_group @ sub:Prod' could not be resolved") | Should -BeTrue
                Should -Invoke Remove-OERRoleAssignment -Times 0
            }
        }

        It 'compares the duplicate key without regard to letter case' {
            InModuleScope $script:moduleName {
                # Entry 3 spells the principal object id and the role GUID in upper case. Azure treats the
                # ids as the same, so it is the same assignment as entry 0 and is a duplicate.
                $First  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'grp1' }
                $Second = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = 'ACDD72A7-3385-48EF-BD42-F606FBA81AE7'; principal = '11111111-AAAA-0000-0000-000000000001' }
                $Cache = @{}
                $Declared = @($First, $Second)
                $r0 = @(Invoke-SyncRaDup -Item $First -ItemIndex 0 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ReconcileScope -ErrorAction SilentlyContinue)
                $r3 = @(Invoke-SyncRaDup -Item $Second -ItemIndex 3 -DeclaredAtScope $Declared -DeclaredAtScopeIndex @(0, 3) -SiblingKeyCache $Cache -ErrorAction SilentlyContinue)

                @($r0).Action | Should -Be @('Created')
                @($r3).Action | Should -Be @('Failed')
                $r3[0].Detail | Should -Match 'roleAssignments\[3\] resolves to the same assignment as roleAssignments\[0\]'
                Should -Invoke New-OERRoleAssignment -Times 1 -Exactly
            }
        }

        It 'names the earliest of several duplicates by its document index, not its position' {
            InModuleScope $script:moduleName {
                # Positions 0, 1 and 2 hold the entries at document indexes 2, 4 and 7.
                $E2 = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'grp1' }
                $E4 = [PSCustomObject]@{ scope = '/subscriptions/sub-1'; role = 'Reader'; principal = '11111111-aaaa-0000-0000-000000000001' }
                $E7 = [PSCustomObject]@{ scope = 'subscription:Prod'; role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; principal = 'grp1' }
                $Cache = @{}
                $Declared = @($E2, $E4, $E7)
                $Index = @(2, 4, 7)
                $r2 = @(Invoke-SyncRaDup -Item $E2 -ItemIndex 2 -DeclaredAtScope $Declared -DeclaredAtScopeIndex $Index -SiblingKeyCache $Cache -ReconcileScope -ErrorAction SilentlyContinue)
                $r4 = @(Invoke-SyncRaDup -Item $E4 -ItemIndex 4 -DeclaredAtScope $Declared -DeclaredAtScopeIndex $Index -SiblingKeyCache $Cache -ErrorAction SilentlyContinue)
                $r7 = @(Invoke-SyncRaDup -Item $E7 -ItemIndex 7 -DeclaredAtScope $Declared -DeclaredAtScopeIndex $Index -SiblingKeyCache $Cache -ErrorAction SilentlyContinue)

                @($r2).Action | Should -Be @('Created')
                @($r4).Action | Should -Be @('Failed')
                @($r7).Action | Should -Be @('Failed')
                $r4[0].Detail | Should -Match "^roleAssignments\[4\] resolves to the same assignment as roleAssignments\[2\] \('Reader -> grp1 @ sub:Prod'\)"
                $r7[0].Detail | Should -Match "^roleAssignments\[7\] resolves to the same assignment as roleAssignments\[2\] \('Reader -> grp1 @ sub:Prod'\)"
                Should -Invoke New-OERRoleAssignment -Times 1 -Exactly
            }
        }
    }

    Context 'a failed read of the assignments at the scope is Failed, never an empty list (A14)' {
        # Get-OERRoleAssignment reports a failed ARM read (measured live: a 403 at a management group)
        # as a NON-terminating error and returns nothing. The handler reads with -ErrorAction Stop, so
        # that error lands in its catch: the entry is Failed with the read error, nothing is created or
        # planned, and the prune pass for the scope never runs. The failure mock is a cmdlet writing
        # through $PSCmdlet.WriteError, never Write-Error: only a cmdlet's own WriteError is promoted by
        # the caller's -ErrorAction Stop, which is exactly what the handler relies on.
        BeforeAll {
            InModuleScope $script:moduleName {
                $script:A14Scope = '/providers/Microsoft.Management/managementGroups/mg-1'
                $script:A14Item  = [PSCustomObject]@{ scope = 'mg:mg-1'; role = 'Reader'; principal = 'role_sec_x' }
            }
        }

        It 'reports Failed with the read error and creates nothing when the read writes a non-terminating error' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    [CmdletBinding()] param([string]$Scope, [switch]$AtScope)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('read marker: the client does not have authorization to read role assignments.'),
                            'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, $Scope))
                }
                Mock New-OERRoleAssignment { [PSCustomObject]@{ RoleAssignmentId = 'ra-new' } }
                Mock Initialize-OERAuth {}
                $Ev = $null
                $r = @(Invoke-SyncRaViaCaller -Item $script:A14Item -ResolvedScope $script:A14Scope -ErrorAction SilentlyContinue -ErrorVariable Ev)
                Should -Invoke Get-OERRoleAssignment -Times 1 -Exactly -ParameterFilter { $Scope -ceq $script:A14Scope -and $AtScope }
                @($r).Action | Should -Be @('Failed')
                $r[0].Detail | Should -BeLike "could not read role assignments at scope '$($script:A14Scope)': read marker:*"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AuthorizationFailed'
                # The read error is published as itself, once, through the caller. -ErrorVariable also
                # collects the stop exception at each layer of Pester's mock wrapper, so the assertion
                # is on the record the Failed row carries, not on the size of the list.
                @($Ev | Where-Object { [object]::ReferenceEquals($_, $r[0].Error) }).Count | Should -Be 1
                Should -Invoke New-OERRoleAssignment -Times 0
            }
        }

        It 'plans no create under -WhatIf when the read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    [CmdletBinding()] param([string]$Scope, [switch]$AtScope)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('read marker'), 'AuthorizationFailed',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $Scope))
                }
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncRaViaCaller -Item $script:A14Item -ResolvedScope $script:A14Scope -WhatIf -ErrorAction SilentlyContinue)
                @($r).Action | Should -Be @('Failed')
                @($r | Where-Object { $_.Detail -match 'would create' }).Count | Should -Be 0
                Should -Invoke New-OERRoleAssignment -Times 0
            }
        }

        It 'never runs the prune pass for the scope when the read fails part way, under -Prune and -ReconcileScope' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                # One undeclared assignment at the scope is emitted before the read fails: a read that
                # failed part way is no more a complete list than an empty one.
                Mock Get-OERRoleAssignment {
                    [CmdletBinding()] param([string]$Scope, [switch]$AtScope)
                    [PSCustomObject]@{ Scope = $Scope; PrincipalId = 'p-other'; RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/rd-other'; RoleAssignmentId = 'ra-undeclared' }
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('read marker'), 'AuthorizationFailed',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $Scope))
                }
                Mock New-OERRoleAssignment {}
                Mock Remove-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncRaViaCaller -Item $script:A14Item -ResolvedScope $script:A14Scope -DeclaredAtScope @($script:A14Item) -ReconcileScope -Prune -Confirm:$false -ErrorAction SilentlyContinue)
                @($r).Action | Should -Be @('Failed')
                Should -Invoke Remove-OERRoleAssignment -Times 0
                Should -Invoke New-OERRoleAssignment -Times 0
            }
        }

        It 'scrubs the bearer-hygiene record of the failed read before it publishes it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncRaViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [object[]]$DeclaredAtScope, [switch]$ReconcileScope, [string]$ResolvedScope)
                    Sync-OERStructureRoleAssignment -Item $Item -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune:$Prune -DeclaredAtScope $DeclaredAtScope -ReconcileScope:$ReconcileScope
                }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Resolve-OERRoleDefinitionId { '/providers/Microsoft.Authorization/roleDefinitions/rd-1' }
                Mock Get-OERRoleAssignment {
                    [CmdletBinding()] param([string]$Scope, [switch]$AtScope)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('read marker'), 'AuthorizationFailed',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $Scope))
                }
                Mock New-OERRoleAssignment {}
                Mock Initialize-OERAuth {}
                Mock Remove-OERErrorRecord { param($Record) }
                $r = @(Invoke-SyncRaViaCaller -Item $script:A14Item -ResolvedScope $script:A14Scope -ErrorAction SilentlyContinue)
                @($r).Action | Should -Be @('Failed')
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { $Record.FullyQualifiedErrorId -match '^AuthorizationFailed' }
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
