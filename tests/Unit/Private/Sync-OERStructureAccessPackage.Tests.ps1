BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Sync-OERStructureAccessPackage' {

    It 'creates a missing access package and passes -Catalog (Created)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales' } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessPackage -Times 1 -ParameterFilter { $Catalog -eq 'CAT-IT' }
        }
    }

    It 'existing AP with differing description calls Set-OERAccessPackage and reports Updated' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'old desc' } }
            Mock Set-OERAccessPackage {}
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; description = 'new desc' }))
            Should -Invoke Set-OERAccessPackage -Times 1 -ParameterFilter { $Description -eq 'new desc' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'existing AP with matching description reports Unchanged and does not call Set-OERAccessPackage' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'same desc' } }
            Mock Set-OERAccessPackage {}
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; description = 'same desc' }))
            Should -Invoke Set-OERAccessPackage -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'resourceRole add-if-missing: resolved via Get-OERCatalogResource OriginId, then Add-OERAccessPackageResourceRole called' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Get-OERCatalogResource {
                [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' }
            }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Add-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName   = 'AP-Sales'
                catalog       = 'CAT-IT'
                resourceRoles = @(
                    [PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -ParameterFilter { $ResourceOriginId -eq 'grp-1' -and $Role -eq 'Member' }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'resourceRole already present reports Unchanged and does not call Add-OERAccessPackageResourceRole' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Get-OERCatalogResource {
                [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' }
            }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id    = 'b1'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'grp-1' }
                        }
                    )
                }
            }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Add-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName   = 'AP-Sales'
                catalog       = 'CAT-IT'
                resourceRoles = @(
                    [PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'resourceRole resource name unresolvable emits Failed and continues' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Get-OERCatalogResource { @() }
            Mock Resolve-OERGroupId { $null }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Add-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName   = 'AP-Sales'
                catalog       = 'CAT-IT'
                resourceRoles = @(
                    [PSCustomObject]@{ resource = 'no-such-group'; role = 'Member' }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
            Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'assignmentPolicy created when absent: requestorScope, approval stage with manager, and policy cmdlets all invoked' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock New-OERAccessPackageRequestorScope {
                $Out = [PSCustomObject]@{ AllowedTargetScope = 'allMemberUsers'; SpecificAllowedTargets = @() }
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
                $Out
            }
            Mock New-OERAccessPackageApprovalStage {
                $Out = [PSCustomObject]@{ DurationDays = 7; Approvers = 1; GraphStage = @{} }
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ApprovalStage')
                $Out
            }
            Mock New-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                        approvalStages = @(
                            [PSCustomObject]@{ durationDays = 7; manager = $true }
                        )
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke New-OERAccessPackageRequestorScope -Times 1
            Should -Invoke New-OERAccessPackageApprovalStage -Times 1 -ParameterFilter { $Manager -eq $true }
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'assignmentPolicy already present reports Unchanged and does not call New-OERAccessPackageAssignmentPolicy' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    Id             = 'pol-1'
                    DisplayName    = 'Default'
                    RequestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                    ApprovalStages = @()
                    DurationInDays = $null
                }
            }
            Mock New-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'Default' }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'assignmentPolicy with non-manager stage and no default approvers emits Failed and does not call New-OERAccessPackageAssignmentPolicy' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            # No PrimaryApprovers default
            Mock Resolve-OERStructureDefault { $null }
            Mock New-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @(
                            [PSCustomObject]@{ durationDays = 7 }
                        )
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'approver-default fallback: PrimaryApprovers default present -> policy is created (no Failed)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            $DefaultGuid = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Resolve-OERStructureDefault {
                param($TenantAlias, $Name)
                if ($Name -eq 'PrimaryApprovers') { $DefaultGuid } else { $null }
            }
            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock New-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            # A stage with no manager and no explicit users/groups -- triggers back-compat fallback.
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @(
                            [PSCustomObject]@{ durationDays = 7 }
                        )
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test')
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1
            ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
        }
    }

    It 'approver-default fallback: PrimaryApprovers default absent -> Failed emitted and New-OERAccessPackageAssignmentPolicy NOT called' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Resolve-OERStructureDefault { $null }
            Mock New-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @(
                            [PSCustomObject]@{ durationDays = 7 }
                        )
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -ErrorAction SilentlyContinue)
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -Prune removes an undeclared resourceRole binding via -ResourceRoleScopeId and reports Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id    = 'b-extra'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'grp-extra' }
                        }
                    )
                }
            }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Remove-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }) -Prune -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERAccessPackageResourceRole -Times 1 -ParameterFilter { $ResourceRoleScopeId -eq 'b-extra' }
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing for resourceRole binding prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id    = 'b-extra'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'grp-extra' }
                        }
                    )
                }
            }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Remove-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }) -Prune -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for resourceRole binding prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id    = 'b-extra'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'grp-extra' }
                        }
                    )
                }
            }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Remove-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }) -Prune -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'without -Prune undeclared resourceRole binding reports Extra and does not call Remove-OERAccessPackageResourceRole' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id    = 'b-extra'
                            role  = [PSCustomObject]@{ displayName = 'Member' }
                            scope = [PSCustomObject]@{ originId = 'grp-extra' }
                        }
                    )
                }
            }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock Remove-OERAccessPackageResourceRole {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }))
            Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    # HIGHEST PRIORITY of Task 7's eight sites: a truncated resourceRoleScopes read makes the
    # reconcile (a) spuriously re-Add a declared binding it did not see, and (b) silently
    # UNDER-prune -- an undeclared live binding on a later page is never reported Extra and never
    # removed, so -Prune reports a clean package while stale bindings survive. It can NOT wrongfully
    # DELETE a binding it never read: the prune loop below only ever iterates $CurrentBindings, so an
    # unread binding is never a delete candidate (an earlier, WRONG version of this comment claimed
    # otherwise -- corrected in Task 7 fix round 1).
    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the resourceRoleScopes read' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' })
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/entitlementManagement/accessPackages/ap-1/resourceRoleScopes?$expand=scope,role' -and $All
                }
            }
        }

        It 'reconciles a two-page aggregate correctly: both declared bindings are seen (no spurious Add), and an undeclared page-2-only binding IS pruned (no silent under-prune)' {
            # The mock's response is CONDITIONAL on whether -All was forwarded, modeling what
            # Invoke-OERGraphRequest's real paging aggregation returns: with -All, three bindings
            # (as if collected across two real Graph pages) come back; without it, only the first
            # page's single binding does. This makes the test mutation-sensitive: deleting -All from
            # the call site collapses the mock back to a truncated single-item response, which
            # starves the reconcile of two things that live on page 2 -- the second DECLARED binding
            # (grp-2, whose absence causes a spurious re-Add) and the undeclared live binding
            # (grp-extra, whose absence means -Prune can never see it and so never removes it: silent
            # under-pruning, not a wrongful delete -- the prune loop below only ever iterates
            # $CurrentBindings, so a binding it never read is never a delete candidate).
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' }
                        [PSCustomObject]@{ DisplayName = 'role_sec_y'; OriginId = 'grp-2'; Id = 'res-2' }
                    )
                }
                Mock Invoke-OERGraphRequest {
                    param($Uri, $All)
                    if ($Uri -notlike '*resourceRoleScopes*') { return [PSCustomObject]@{ value = @() } }
                    $Page1 = [PSCustomObject]@{ id = 'b1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-1' } }
                    # $Page2Declared is the second DECLARED binding; $Page2Extra is a live binding
                    # that is NOT declared by the document and exists ONLY on this simulated second
                    # page -- the fixture Minor 2 asked for so the -Prune half of this test is a real
                    # guard instead of one that would pass identically with -Prune's logic deleted.
                    $Page2Declared = [PSCustomObject]@{ id = 'b2'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-2' } }
                    $Page2Extra = [PSCustomObject]@{ id = 'b3'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = 'grp-extra' } }
                    if ($All) {
                        [PSCustomObject]@{ value = @($Page1, $Page2Declared, $Page2Extra) }
                    } else {
                        [PSCustomObject]@{ value = @($Page1) }
                    }
                }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole {}
                Mock Remove-OERAccessPackageResourceRole {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @(
                        [PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' }
                        [PSCustomObject]@{ resource = 'role_sec_y'; role = 'Member' }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                # Both declared bindings were present in the (aggregated) current set, so both must
                # report Unchanged -- neither is missed as "not yet bound".
                ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like '*role_sec_x*' }).Count | Should -Be 1
                ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like '*role_sec_y*' }).Count | Should -Be 1
                # No spurious Add: neither declared binding is re-created because the aggregate
                # already showed both as bound.
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                # The genuine -Prune consequence: the undeclared live binding that exists ONLY on the
                # simulated second page (b3, Owner/grp-extra) IS removed, because -All handed the
                # reconcile a complete current-bindings set to diff the declared set against. Under
                # truncation this binding is invisible to the prune loop and this assertion fails --
                # that is the silent-under-prune defect the -All fix closes, proven by the mutation
                # test in the fix-round report.
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $ResourceRoleScopeId -eq 'b3' }
                ($r | Where-Object Action -eq 'Removed').Count | Should -Be 1
            }
        }
    }

    It 'under -WhatIf on a missing AP does not call New-OERAccessPackage and emits Skipped records' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' })
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
            Should -Invoke New-OERAccessPackage -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on a missing AP, declared resourceRoles and assignmentPolicies each produce a would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales' } }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'
                catalog            = 'CAT-IT'
                resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' })
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resourceRole 'role_sec_x'" }).Count | Should -Be 1
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure assignmentPolicy 'Default'" }).Count | Should -Be 1
        }
    }

    It 'under -WhatIf on a missing AP, an explicit null resourceRoles/assignmentPolicies produces no would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales' } }
            Mock Initialize-OERAuth {}
            # An explicit JSON null (not an omitted key) is a one-element array containing $null when
            # wrapped in @(...), so a bare -contains presence gate is TRUE and iterates one phantom
            # entry -- this is what Test-OERDeclaredProperty must prevent.
            $Item = '{ "displayName": "AP-Sales", "catalog": "CAT-IT", "resourceRoles": null, "assignmentPolicies": null }' | ConvertFrom-Json
            $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'would create access package' }).Count | Should -Be 1
            @($r | Where-Object { $_.Detail -match 'would configure' }).Count | Should -Be 0
        }
    }

    It 'when New-OERAccessPackage throws emits only Failed (not also Created) and continues' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERAccessPackage throws' {
        # Drives the access-package creation catch in Sync-OERStructureAccessPackage. The scrub
        # under test is this handler's OWN -- the Remove-OERErrorRecord opening the handler catch
        # that WRAPS the New-OERAccessPackage call, not a scrub inside New-OERAccessPackage, which
        # is mocked away here. That mocking is precisely what makes the proof non-vacuous.
        # The static AST gate
        # proves that line is WRITTEN first; this It proves it actually RUNS. Mock + Should -Invoke
        # is the only proof shape that works here: the handler swallows the record into a Failed
        # result instead of re-throwing, so a $global:Error reference-identity proof would be inert.
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { $null }
            Mock Get-OERAccessPackage { @() }
            Mock New-OERAccessPackage { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncApViaCaller -Item ([PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'existing assignmentPolicy with a differing scope is updated via Set-OERAccessPackageAssignmentPolicy (Updated)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    Id = 'pol-1'; DisplayName = 'Default'
                    RequestorScope = [PSCustomObject]@{ scope = 'AllDirectoryUsers' }
                    ApprovalStages = @(); DurationInDays = 30
                }
            }
            Mock New-OERAccessPackageRequestorScope {
                $o = [PSCustomObject]@{ AllowedTargetScope = 'allMemberUsers'; SpecificAllowedTargets = @() }
                $o.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope'); $o
            }
            Mock Set-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }; durationInDays = 30 })
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -ParameterFilter { $Id -eq 'pol-1' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'existing assignmentPolicy that matches declared fields reports Unchanged and does not call Set' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            # Build the CURRENT projection via the real builders so it is a faithful full projection
            # (a hand-built partial would falsely differ on per-stage defaults such as managerLevel).
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}
            $Item = [PSCustomObject]@{
                displayName = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @([PSCustomObject]@{
                    displayName = 'Default'; requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                    approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true }); durationInDays = 30
                })
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf an existing differing policy emits Skipped (would update) and does not call Set' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{ Id = 'pol-1'; DisplayName = 'Default'; RequestorScope = [PSCustomObject]@{ scope = 'AllDirectoryUsers' }; ApprovalStages = @(); DurationInDays = 30 }
            }
            Mock Set-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{
                displayName = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }; durationInDays = 30 })
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'existing policy with a tenant durationInDays, doc omits durationInDays -> Unchanged (no Set)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy {
                [PSCustomObject]@{
                    Id             = 'pol-1'
                    DisplayName    = 'Default'
                    RequestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                    ApprovalStages = @()
                    DurationInDays = 30
                }
            }
            Mock Set-OERAccessPackageAssignmentPolicy {}
            Mock Initialize-OERAuth {}
            # Doc declares requestorScope matching the tenant but omits durationInDays entirely
            $Item = [PSCustomObject]@{
                displayName = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'Default'; requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' } }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'granular: a fully-declared policy that matches the current projection reports Unchanged (round-trip; Set NOT called)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }

            $UserId = '11111111-1111-1111-1111-111111111111'

            # Build the CURRENT projection the same way the handler builds the DESIRED one, so a
            # fully-declared, matching policy must round-trip to Unchanged. The builders run for real;
            # only the name->id lookups are mocked to echo.
            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User $UserId
            $Settings = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -User $UserId
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -RequestorSettings $Settings -ApprovalStage $Stage -RequireApproval $true -DurationInHours 8 -DisableAssignmentNotifications $true
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName           = 'Default'
                        requestorScope        = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @($UserId) }
                        requestorSettings     = [PSCustomObject]@{ allowSelfRequest = $true }
                        requireApproval       = $true
                        approvalStages        = @([PSCustomObject]@{ durationDays = 7; users = @($UserId) })
                        durationInHours       = 8
                        notificationsDisabled = $true
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'granular: a fully-declared policy with stage fallbackUsers/fallbackGroups that matches the current projection reports Unchanged (round-trip; Set NOT called)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }

            $UserId = '11111111-1111-1111-1111-111111111111'
            $FbUserId = '33333333-3333-3333-3333-333333333333'

            # Same real-builder round-trip as the sibling test above, this time with -FallbackUser
            # declared on the stage so the fallbackPrimaryApprovers leg is exercised end to end.
            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User $UserId
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -User $UserId -FallbackUser $FbUserId
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @($UserId) }
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; users = @($UserId); fallbackUsers = @($FbUserId) })
                        durationInDays = 30
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'granular: doc declares a stage fallbackUsers not present on the current live policy -> Updated and Set called with FallbackUser bound' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }

            $UserId = '11111111-1111-1111-1111-111111111111'
            $FbUserId = '33333333-3333-3333-3333-333333333333'

            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            # CURRENT projection has no fallback approvers on the stage; the doc declares one -> differs.
            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User $UserId
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -User $UserId
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @($UserId) }
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; users = @($UserId); fallbackUsers = @($FbUserId) })
                        durationInDays = 30
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            # The rebuilt stage must actually carry the declared fallback approver through to the PUT --
            # a plain "Set was called" assertion cannot tell FallbackUser from any other declared change.
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -ParameterFilter {
                $Id -eq 'pol-1' -and
                @($ApprovalStage[0].GraphStage.fallbackPrimaryApprovers.userId) -contains $FbUserId
            }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'granular: one declared field differs from current -> Updated and Set called once' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }

            $UserId = '11111111-1111-1111-1111-111111111111'

            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            # CURRENT projection built with notificationsDisabled = $false; the doc declares $true -> differs.
            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User $UserId
            $Settings = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -User $UserId
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -RequestorSettings $Settings -ApprovalStage $Stage -RequireApproval $true -DurationInHours 8 -DisableAssignmentNotifications $false
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName           = 'Default'
                        requestorScope        = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @($UserId) }
                        requestorSettings     = [PSCustomObject]@{ allowSelfRequest = $true }
                        requireApproval       = $true
                        approvalStages        = @([PSCustomObject]@{ durationDays = 7; users = @($UserId) })
                        durationInHours       = 8
                        notificationsDisabled = $true
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            # Positive control for the requestorScope declared-field gate: the entry DOES declare
            # requestorScope (SpecificDirectoryUsers + a user), so -RequestorScope must be forwarded
            # to Set-OERAccessPackageAssignmentPolicy with the specific-directory-users scope -- proving
            # the declared branch still works, as a counterpart to the "undeclared -> omitted" test.
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -ParameterFilter {
                $Id -eq 'pol-1' -and
                $null -ne $RequestorScope -and
                $RequestorScope.AllowedTargetScope -eq 'specificDirectoryUsers'
            }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'back-compat: a legacy flat policy (manager stage + durationInDays) reconciles Unchanged when matching' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }

            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}

            # Legacy flat: requestorScope.scope + a manager stage + durationInDays only.
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
            $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
            $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
            Mock Set-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                        durationInDays = 30
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'back-compat: a legacy flat policy is created when absent (New called)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncApViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
            Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
            Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
            Mock Get-OERAccessPackageAssignmentPolicy { @() }
            Mock New-OERAccessPackageAssignmentPolicy {}

            $Item = [PSCustomObject]@{
                displayName        = 'AP-Sales'; catalog = 'CAT-IT'
                assignmentPolicies = @(
                    [PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                        durationInDays = 30
                    }
                )
            }
            $r = @(Invoke-SyncApViaCaller -Item $Item)
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    Context 'access package hidden reconciliation' {
        It 'passes -Hidden on create when the document declares hidden true' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                # Catalog-scoped resolve: no existing package named 'AP-Sales' in 'CAT-IT'.
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; hidden = $true }
                $r = @(Invoke-SyncApViaCaller -Item $Item)
                Should -Invoke New-OERAccessPackage -Times 1 -ParameterFilter { $Hidden }
            }
        }

        It 'calls Set-OERAccessPackage -Hidden:$false when the live package is hidden but the document is not' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = 'd'; IsHidden = $true } }
                Mock Set-OERAccessPackage {}
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; description = 'd'; hidden = $false }
                $r = @(Invoke-SyncApViaCaller -Item $Item)
                Should -Invoke Set-OERAccessPackage -Times 1 -ParameterFilter { $Hidden -eq $false }
                ($r | Where-Object { $_.Action -eq 'Updated' }).Detail | Should -BeLike '*Hidden*'
            }
        }
    }

    Context 'access package null-declared fields are treated as undeclared' {
        It 'does not un-hide a hidden access package when the document declares hidden as null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = 'live'; IsHidden = $true } }
                Mock Set-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "hidden": null, "description": null }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Set-OERAccessPackage -Times 0
            }
        }

        It 'still un-hides a hidden access package when the document declares hidden false' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = 'live'; IsHidden = $true } }
                Mock Set-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "hidden": false }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Set-OERAccessPackage -Times 1
            }
        }
    }

    Context 'resourceRoles null declaration does not trigger a prune wipe' {
        It 'does not prune every live resourceRole binding when the document declares resourceRoles as null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-1' } }
                            [PSCustomObject]@{ id = 'b-2'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = 'grp-2' } }
                        )
                    }
                }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Remove-OERAccessPackageResourceRole { }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "AP-Sales", "catalog": "CAT-IT", "resourceRoles": null }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item -Prune)
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
            }
        }

        It 'still prunes every live resourceRole binding when the document declares resourceRoles as an empty array' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-1' } }
                            [PSCustomObject]@{ id = 'b-2'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = 'grp-2' } }
                        )
                    }
                }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # An empty declared array still enters the resourceRoles branch, so the catalog
                # resource read runs. It was previously unmocked, which sent it into the REAL
                # Get-OERCatalogResource; that resolved the catalog through the Invoke-OERGraphRequest
                # mock above, found the two binding fixtures, and reported AmbiguousCatalogName --
                # silently swallowed by the old -ErrorAction SilentlyContinue. Under the read-failure
                # contract that swallow is gone, so the missing mock is supplied here. An empty read
                # that SUCCEEDS is the scenario this test always meant to exercise, and it still
                # prunes.
                Mock Get-OERCatalogResource { @() }
                Mock Remove-OERAccessPackageResourceRole { }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "AP-Sales", "catalog": "CAT-IT", "resourceRoles": [] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item -Prune
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 2
            }
        }
    }

    Context 'assignment policy null-declared fields are treated as undeclared, not defaults' {
        It 'does not widen a live SpecificDirectoryUsers scope when requestorScope is declared null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @([PSCustomObject]@{
                            Id = 'p-1'; DisplayName = 'P'
                            RequestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @('u-1'); groups = @() }
                        })
                }
                Mock Set-OERAccessPackageAssignmentPolicy { param($RequestorScope) $script:SetSplat = $RequestorScope }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": null } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'does not disable a live approval requirement when requireApproval is declared null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @([PSCustomObject]@{ Id = 'p-1'; DisplayName = 'P'; RequireApproval = $true })
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requireApproval": null } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'falls back to AllMemberUsers when requestorScope.scope is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # requestorScope ITSELF is declared (a non-null object), but every field inside it is
                # an explicit JSON null -- distinct from the sibling test above, which declares the
                # whole requestorScope block as null.
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "scope": null, "users": null, "groups": null } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                # Positive-identity assertion first: the create path must actually have built a scope,
                # or the content check below would pass just as well on zero calls.
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter { $Scope -eq 'AllMemberUsers' }
            }
        }

        It 'passes no -User/-Group when requestorScope.users/.groups are explicit nulls under SpecificDirectoryUsers' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # Declared scope is SpecificDirectoryUsers -- a real, non-default value -- so the
                # $ScopeValue -eq 'SpecificDirectoryUsers' branch that actually reads $ScopeUsers/
                # $ScopeGroups is entered. The sibling test above never enters that branch: its
                # declared scope is null and falls back to the AllMemberUsers default before either
                # variable is read. Under the OLD bare -contains idiom, @($RsEntry.users) against a
                # declared-but-null 'users' property yields @($null), whose .Count is 1 -- this repo's
                # own catalogued trap -- so the old code's "if ($ScopeUsers.Count -gt 0)" guard fired
                # and bound -User to an array containing a single null. The fix skips the assignment
                # entirely, so -User/-Group are never bound.
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "scope": "SpecificDirectoryUsers", "users": null, "groups": null } } ] }' | ConvertFrom-Json
                $Results = @(Invoke-SyncApViaCaller -Item $Item)

                # Positive-identity assertion first: the policy create path must actually have produced
                # a Created (or Updated) row, or the content check below would pass just as well for the
                # wrong reason.
                @($Results | Where-Object { $_.Action -in @('Created', 'Updated') }).Count |
                    Should -BeGreaterThan 0 -Because 'the assignmentPolicy create path must run for the content check below to mean anything'

                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'SpecificDirectoryUsers' -and $null -eq $User -and $null -eq $Group
                }
            }
        }
    }

    Context 'assignment policy requestorScope is only written when declared' {
        It 'omits -RequestorScope from the Set call when the entry does not declare requestorScope' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap'; Description = 'd'; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    [PSCustomObject]@{ Id = 'pol-1'; DisplayName = 'Standard'; DurationInDays = 10 }
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'ap'; catalog = 'c'; description = 'd'; hidden = $false
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                Invoke-SyncApViaCaller -Item $Item | Out-Null
                # NOTE: $PSBoundParameters is NOT populated inside a Pester Mock/ParameterFilter
                # scriptblock in this Pester version (verified empirically) -- only the individual
                # bound-parameter variables are. So "was RequestorScope passed" is checked via the
                # variable itself, which Pester sets to $null when the caller's splat omits the key.
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly `
                    -ParameterFilter { $null -eq $RequestorScope }
            }
        }
    }

    Context 'assignment policy requestorScope infers SpecificDirectoryUsers (issue #69)' {
        # A declared-but-scopeless requestorScope with a non-empty users/groups list used to silently
        # default to AllMemberUsers, discarding the users/groups: New-OERAccessPackageRequestorScope
        # only splats -User/-Group under -Scope SpecificDirectoryUsers. Build-OERPolicyParts now infers
        # SpecificDirectoryUsers for exactly that shape. Every mock below captures the real parameter
        # names (Scope/User/Group) with its own param() block, since a Mock scriptblock without one
        # never sees $PSBoundParameters populated in this Pester version (Task 3's finding).
        It 'infers -Scope SpecificDirectoryUsers and passes the users when requestorScope declares users but no scope' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "users": ["u1@contoso.com"] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'SpecificDirectoryUsers' -and
                    $null -ne $User -and (@($User) -contains 'u1@contoso.com') -and
                    $null -eq $Group
                }
            }
        }

        It 'infers -Scope SpecificDirectoryUsers and passes the groups when requestorScope declares groups but no scope' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "groups": ["g1"] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'SpecificDirectoryUsers' -and
                    $null -eq $User -and
                    $null -ne $Group -and (@($Group) -contains 'g1')
                }
            }
        }

        It 'infers -Scope SpecificDirectoryUsers and passes both users and groups when both are declared without scope' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "users": ["u1@contoso.com"], "groups": ["g1"] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'SpecificDirectoryUsers' -and
                    (@($User) -contains 'u1@contoso.com') -and
                    (@($Group) -contains 'g1')
                }
            }
        }

        It 'keeps -Scope AllMemberUsers and does not splat users when scope is declared explicitly (explicit scope always wins)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "scope": "AllMemberUsers", "users": ["u1@contoso.com"] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'AllMemberUsers' -and $null -eq $User -and $null -eq $Group
                }
            }
        }

        It 'does not infer from a declared-empty users list: falls back to AllMemberUsers (an empty list names nobody)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "users": [] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'AllMemberUsers' -and $null -eq $User -and $null -eq $Group
                }
            }
        }

        It 'stays AllMemberUsers when requestorScope is omitted entirely (unchanged default)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P" } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'AllMemberUsers' -and $null -eq $User -and $null -eq $Group
                }
            }
        }

        It 'infers identically when scope is an explicit JSON null, matching the omitted-scope case (Constraint 15)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { [PSCustomObject]@{ Id = 'pol-1' } }
                Mock New-OERAccessPackageRequestorScope { param($Scope, $User, $Group) [PSCustomObject]@{ Scope = $Scope } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "scope": null, "users": ["u1@contoso.com"] } } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke New-OERAccessPackageRequestorScope -Times 1 -Exactly -ParameterFilter {
                    $Scope -eq 'SpecificDirectoryUsers' -and (@($User) -contains 'u1@contoso.com')
                }
            }
        }
    }

    Context 'assignment policy description convergence' {
        It 'converges on a declared empty policy description instead of reporting Updated every run' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @([PSCustomObject]@{ Id = 'p-1'; DisplayName = 'P'; Description = '' })
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "description": "" } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
            }
        }
    }

    Context 'assignment policy Extra reporting' {
        It 'reports an undeclared live assignment policy as Extra' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = 'p-1'; DisplayName = 'Declared' }
                        [PSCustomObject]@{ Id = 'p-2'; DisplayName = 'DroppedFromDocument' }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Remove-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Declared" } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item -Prune)
                $Extra = @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -match 'DroppedFromDocument' })
                $Extra.Count | Should -Be 1
            }
        }

        It 'never deletes an assignment policy even with -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = 'p-1'; DisplayName = 'Declared' }
                        [PSCustomObject]@{ Id = 'p-2'; DisplayName = 'DroppedFromDocument' }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Remove-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Declared" } ] }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item -Prune
                Should -Invoke Remove-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'does not report Extra policies when the document does not declare assignmentPolicies' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = 'p-1'; DisplayName = 'Declared' }
                        [PSCustomObject]@{ Id = 'p-2'; DisplayName = 'DroppedFromDocument' }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Remove-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT" }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item -Prune)
                @($Records | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
            }
        }
    }

    Context 'access package resolution is scoped to its declared catalog' {
        It 'matches the access package inside the declared catalog, not the identically named one elsewhere' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:ReadId = $null
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @([PSCustomObject]@{ Id = 'ap-in-cat'; DisplayName = 'AP'; Description = $null; IsHidden = $false })
                    }
                    $script:ReadId = $Id
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'AP'; Description = $null; IsHidden = $false }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                $Item = '{ "displayName": "AP", "catalog": "CAT-A" }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                $script:ReadId | Should -BeExactly 'ap-in-cat'
            }
        }

        It 'reports Failed when the declared catalog holds more than one package with that display name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @(
                            [PSCustomObject]@{ Id = 'ap-dup-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false }
                            [PSCustomObject]@{ Id = 'ap-dup-2'; DisplayName = 'AP'; Description = $null; IsHidden = $false }
                        )
                    }
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'AP'; Description = $null; IsHidden = $false }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                $Item = '{ "displayName": "AP", "catalog": "CAT-A" }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item)
                $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'ap-dup-1'
                $Failed[0].Detail | Should -Match 'ap-dup-2'
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'resolves tenant-wide via Resolve-OERAccessPackageId when the item declares no catalog' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales' }
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Resolve-OERAccessPackageId -Times 1 -ParameterFilter { $DisplayName -eq 'AP-Sales' }
            }
        }

        It 'reports Failed without creating when the catalog-scoped read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage { throw 'transient Graph failure' }
                Mock New-OERAccessPackage { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "AP", "catalog": "CAT-A" }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke New-OERAccessPackage -Times 0
                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 1
            }
        }

        It 'reports Failed without a false Unchanged when the existing-package re-read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { throw 'transient Graph failure' }
                Mock Set-OERAccessPackage { }
                Mock Initialize-OERAuth { }
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales' }
                $Records = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Set-OERAccessPackage -Times 0
                @($Records | Where-Object { $_.Action -eq 'Unchanged' }).Count | Should -Be 0
                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 1
            }
        }
    }

    Context 'downstream child calls identify the access package by resolved id, never by display name' {
        # The nested half of rt-accesspackage-matched-tenantwide-ignoring-catalog. -AccessPackage on
        # every one of these child cmdlets funnels a non-GUID value into Resolve-OERAccessPackageId,
        # whose display-name lookup is TENANT-WIDE. Passing the display name there throws away the
        # catalog scoping this handler just established: it either acts on an identically named
        # package in another catalog or fails outright with AmbiguousName. Resolve-OERAccessPackageId
        # returns a GUID verbatim (Test-OERGuid, no Graph call), so the resolved id binds straight
        # through every -AccessPackage parameter.
        #
        # Live evidence: a tenant with 'oer-live-ap' in BOTH OER-CAT-A and OER-CAT-B applied a
        # document declaring catalog OER-CAT-A. The package itself resolved correctly, then every
        # assignment policy call failed with "matches 2 access packages".

        It 'reads the current assignment policies by resolved id' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @([PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000053'; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false })
                    }
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                $Item = '{ "displayName": "oer-live-ap", "catalog": "OER-CAT-A" }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $AccessPackage -eq '00000000-0000-0000-0000-000000000053'
                }
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0 -Exactly -ParameterFilter {
                    $AccessPackage -eq 'oer-live-ap'
                }
            }
        }

        It 'creates an assignment policy against the resolved id' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @([PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000053'; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false })
                    }
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageRequestorScope {
                    $Out = [PSCustomObject]@{ AllowedTargetScope = 'allMemberUsers'; SpecificAllowedTargets = @() }
                    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
                    $Out
                }
                Mock New-OERAccessPackageApprovalStage {
                    $Out = [PSCustomObject]@{ DurationDays = 7; Approvers = 1; GraphStage = @{} }
                    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ApprovalStage')
                    $Out
                }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                $Item = @'
{
  "displayName": "oer-live-ap",
  "catalog": "OER-CAT-A",
  "assignmentPolicies": [
    { "displayName": "Pol1",
      "requestorScope": { "scope": "AllMemberUsers" },
      "approvalStages": [ { "durationDays": 7, "manager": true } ] }
  ]
}
'@ | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item)
                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $AccessPackage -eq '00000000-0000-0000-0000-000000000053'
                }
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly -ParameterFilter {
                    $AccessPackage -eq 'oer-live-ap'
                }
            }
        }

        It 'adds a resource role binding against the resolved id' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @([PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000053'; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false })
                    }
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false }
                }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                $Item = @'
{
  "displayName": "oer-live-ap",
  "catalog": "OER-CAT-A",
  "resourceRoles": [ { "resource": "role_sec_x", "role": "Member" } ]
}
'@ | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter {
                    $AccessPackage -eq '00000000-0000-0000-0000-000000000053'
                }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0 -Exactly -ParameterFilter {
                    $AccessPackage -eq 'oer-live-ap'
                }
            }
        }

        It 'prunes a resource role binding against the resolved id' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessPackage {
                    param($Id, $DisplayName, $Catalog)
                    if ($PSBoundParameters.ContainsKey('Catalog')) {
                        return @([PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000053'; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false })
                    }
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'oer-live-ap'; Description = $null; IsHidden = $false }
                }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id    = 'b-extra'
                                role  = [PSCustomObject]@{ displayName = 'Member' }
                                scope = [PSCustomObject]@{ originId = 'grp-extra' }
                            }
                        )
                    }
                }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Remove-OERAccessPackageResourceRole { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                $Item = '{ "displayName": "oer-live-ap", "catalog": "OER-CAT-A" }' | ConvertFrom-Json
                $null = Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter {
                    $AccessPackage -eq '00000000-0000-0000-0000-000000000053' -and $ResourceRoleScopeId -eq 'b-extra'
                }
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0 -Exactly -ParameterFilter {
                    $AccessPackage -eq 'oer-live-ap'
                }
            }
        }
    }

    Context 'assignment policy approvalStages is only written when declared (issue #56)' {

        # These four Its pin the declared-vs-count gate at Sync-OERStructureAccessPackage's update
        # splat. They assert on the SPLAT the handler builds, not on the result record: a result
        # record alone reports 'Updated' even when the stages were silently carried forward, which is
        # exactly how the bug survived. Inside a Pester ParameterFilter an OMITTED splat key shows up
        # as $null and a bound EMPTY array shows up as an empty PSObject[] -- verified empirically --
        # so "present but empty" is ($null -ne $ApprovalStage) AND a zero count, in that order,
        # because @($null).Count is 1, not 0. Every Should -Invoke here carries -Exactly, since
        # -Times N on its own is at-least semantics.

        It 'declared-empty: an empty approvalStages array against a staged live policy binds -ApprovalStage to an empty collection and reports Updated' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }

                # LIVE policy carries one manager approval stage; the document declares [].
                $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
                $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
                $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
                $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
                $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
                Mock Set-OERAccessPackageAssignmentPolicy { }

                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Standard", "approvalStages": [], "durationInDays": 30 } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item)

                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $Id -eq 'pol-1' -and $null -ne $ApprovalStage -and @($ApprovalStage).Count -eq 0
                }
                # durationInDays matches live, so approvalStages is the ONLY changed field -- proving
                # the empty array is what drove the update rather than some unrelated drift.
                @($Records | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like "*assignmentPolicy 'Standard' (approvalStages)*" }).Count | Should -Be 1
            }
        }

        It 'declared-non-empty: a declared stage is still passed through to -ApprovalStage with its approver intact' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $UserId = '11111111-1111-1111-1111-111111111111'
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }

                # LIVE policy carries a 7-day manager stage; the document declares a 14-day user stage.
                $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
                $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
                $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
                $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
                $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
                Mock Set-OERAccessPackageAssignmentPolicy { }

                $Item = ('{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Standard", "approvalStages": [ { "durationDays": 14, "users": [ "' + $UserId + '" ] } ], "durationInDays": 30 } ] }') | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item)

                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $Id -eq 'pol-1' -and
                    $null -ne $ApprovalStage -and
                    @($ApprovalStage).Count -eq 1 -and
                    $ApprovalStage[0].DurationDays -eq 14 -and
                    @($ApprovalStage[0].GraphStage.primaryApprovers.userId) -contains $UserId
                }
                @($Records | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
            }
        }

        It 'omitted: a document with no approvalStages key leaves -ApprovalStage unbound so the live stages carry forward' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }

                # LIVE policy carries a manager stage and a 10-day duration; the document declares only
                # durationInDays 30, so the update fires on expiration alone.
                $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
                $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
                $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 10
                $CurrentProj = ConvertTo-OERAssignmentPolicy -InputObject $Body -AccessPackageId 'ap-1'
                $CurrentProj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { $CurrentProj }
                Mock Set-OERAccessPackageAssignmentPolicy { }

                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Standard", "durationInDays": 30 } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item)

                # THE regression guard for the whole change. Deleting the gate makes the handler send
                # $Parts.Stages unconditionally, which for an undeclared key is an EMPTY array -- not
                # $null -- so this filter stops matching and the assertion fails. The -Existing
                # read-modify-write inside Set-OERAccessPackageAssignmentPolicy is what turns the
                # unbound parameter into "keep the live stages".
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $Id -eq 'pol-1' -and $null -eq $ApprovalStage
                }
                @($Records | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
            }
        }

        It 'convergence: the empty-array document reports Updated on the first pass and Unchanged on the second' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }

                $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
                $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager

                # A SIMULATED TENANT, not a hand-written "pass 2 sees no stages" fixture. Handing the
                # second pass a stage-free policy outright would make this test pass against the very
                # bug it exists to catch (verified: it did), because the non-convergence comes from the
                # WRITE carrying the live stages forward, not from the diff. So the Set mock reproduces
                # what Set-OERAccessPackageAssignmentPolicy actually does -- a read-modify-write through
                # ConvertTo-OERPolicyBody -Existing -- which means an UNBOUND -ApprovalStage genuinely
                # preserves the live stages and the document never converges.
                # The state is held in a hashtable the mock bodies MUTATE rather than reassign, so the
                # test does not depend on write-back into the test scope.
                $State = @{
                    Body  = ConvertTo-OERPolicyBody -DisplayName 'Standard' -AccessPackageId 'ap-1' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
                    Reads = 0
                }

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    $State.Reads++
                    $Proj = ConvertTo-OERAssignmentPolicy -InputObject $State.Body -AccessPackageId 'ap-1'
                    $Proj | Add-Member -NotePropertyName Id -NotePropertyValue 'pol-1' -Force
                    $Proj
                }
                Mock Set-OERAccessPackageAssignmentPolicy {
                    # $PSBoundParameters is not populated inside a Pester mock body in this version, so
                    # "was -ApprovalStage bound" is read off the variable itself: $null when the
                    # caller's splat omitted the key, an empty PSObject[] when it bound [].
                    $Rebuild = @{ DisplayName = $DisplayName; AccessPackageId = 'ap-1'; Existing = $State.Body }
                    if ($null -ne $ApprovalStage) { $Rebuild.ApprovalStage = $ApprovalStage }
                    $State.Body = ConvertTo-OERPolicyBody @Rebuild
                }

                $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Standard", "approvalStages": [], "durationInDays": 30 } ] }' | ConvertFrom-Json
                $First = @(Invoke-SyncApViaCaller -Item $Item)
                $Second = @(Invoke-SyncApViaCaller -Item $Item)

                $State.Reads | Should -Be 2
                @($State.Body.requestApprovalSettings.stages).Count | Should -Be 0
                @($First | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                @($Second | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like "*assignmentPolicy 'Standard' matches*" }).Count | Should -Be 1
                @($Second | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                # One Set across BOTH passes: the second pass must not re-issue the same write.
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            }
        }
    }

    Context 'a failed live read is a Failed row, never a Created' {

        It 'reports Failed, not Created, when the assignment policy read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Set-OERAccessPackage { }
                Mock Resolve-OERStructureDefault { $null }
                # NON-terminating and honouring the caller's -ErrorAction, since that is exactly what
                # Get-OERAccessPackageAssignmentPolicy does on a 403, a transient 5xx or a resolve
                # failure: it writes an error record and emits nothing. A mock that threw would abort
                # the handler with the guard reverted too, so it would prove nothing about the
                # -ErrorAction Stop the guard actually rests on. The fallback is to
                # $ErrorActionPreference, not to a hardcoded value, so the reverted call site really
                # does inherit the suppression it used to ask for.
                Mock Get-OERAccessPackageAssignmentPolicy {
                    param($AccessPackage, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    Write-Error -Message "The assignment policies of access package '$AccessPackage' could not be read." -ErrorId 'AssignmentPolicyReadFailed' -Category PermissionDenied -TargetObject $AccessPackage -ErrorAction $Ea
                }
                Mock New-OERAccessPackageAssignmentPolicy { }

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'pol-1' })
                }
                $Results = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)

                # Positive identity FIRST: an absence assertion on its own also passes when the
                # handler emitted nothing at all.
                $Failed = @($Results | Where-Object { $_.Action -eq 'Failed' })
                @($Failed).Count | Should -Be 1
                $Failed[0].Section | Should -BeExactly 'accessPackages'
                $Failed[0].Item | Should -BeExactly 'AP-Sales'
                $Failed[0].Detail | Should -Match 'failed to read the current assignment policies'
                $null -ne $Failed[0].Error | Should -BeTrue -Because 'the sprint requires the underlying ErrorRecord to travel with the Failed row'

                @($Results | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -Be 0 -Because 'a read that failed is not evidence that the policy does not exist'
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly
            }
        }

        It 'reports Failed and prunes nothing when the catalog resource read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id    = 'binding-1'
                                role  = [PSCustomObject]@{ displayName = 'Member' }
                                scope = [PSCustomObject]@{ originId = 'origin-1' }
                            }
                        )
                    }
                }
                Mock Set-OERAccessPackage { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # Same non-terminating shape: Get-OERCatalogResource reports a missing catalog, an
                # ambiguous catalog name and a failed Graph list call as its own WriteError and emits
                # nothing.
                Mock Get-OERCatalogResource {
                    param($Catalog, $IncludeRoles, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    Write-Error -Message "The resources of catalog '$Catalog' could not be read." -ErrorId 'CatalogResourceReadFailed' -Category PermissionDenied -TargetObject $Catalog -ErrorAction $Ea
                }
                # The fallback the reverted code takes: it must not rescue the run either.
                Mock Resolve-OERGroupId { $null }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }

                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'res-a'; role = 'Member' })
                }
                $Results = @(Invoke-SyncApViaCaller -Item $Item -Prune -ErrorAction SilentlyContinue)

                $Failed = @($Results | Where-Object { $_.Action -eq 'Failed' })
                @($Failed).Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'failed to read the resources of catalog'
                $null -ne $Failed[0].Error | Should -BeTrue

                @($Results | Where-Object { $_.Action -eq 'Extra' }).Count |
                    Should -Be 0 -Because 'a live binding is not Extra merely since the catalog read failed'
                @($Results | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0 -Exactly
            }
        }

        It 'reports Failed, not Created, when the resource role scope read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Set-OERAccessPackage { }
                # Invoke-OERGraphRequest converts an HTTP failure into a THROWN ErrorRecord, so a
                # throwing mock is the faithful one here -- the reverted code caught it and
                # substituted an empty binding list.
                Mock Invoke-OERGraphRequest { throw 'TooManyRequests' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERCatalogResource { @([PSCustomObject]@{ DisplayName = 'res-a'; OriginId = 'origin-1'; Id = 'res-1' }) }
                Mock Add-OERAccessPackageResourceRole { }

                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'res-a'; role = 'Member' })
                }
                $Results = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)

                $Failed = @($Results | Where-Object { $_.Action -eq 'Failed' })
                @($Failed).Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'failed to read the current resource role bindings'
                $null -ne $Failed[0].Error | Should -BeTrue

                @($Results | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0 -Exactly
            }
        }

        It 'still reports a package with genuinely no live policies as reconcilable, not Failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Set-OERAccessPackage { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }

                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT' }
                $Results = @(Invoke-SyncApViaCaller -Item $Item)

                @($Results | Where-Object { $_.Action -eq 'Unchanged' }).Count |
                    Should -BeGreaterThan 0 -Because 'the handler must still have run and reported on the package'
                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'an empty read that SUCCEEDED is not a failure; only the two must be distinguishable'
            }
        }

        It 'still prunes every live binding for an empty resourceRoles array when the catalog read is unusable' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-1' } }
                            [PSCustomObject]@{ id = 'b-2'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = 'grp-2' } }
                        )
                    }
                }
                Mock Set-OERAccessPackage { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # An unusable catalog read. "resourceRoles": [] consumes nothing from it, so the
                # handler must never make the call -- reading it anyway turned a correct full prune
                # into a Failed row. The read is left non-terminating and -ErrorAction-honouring so
                # that removing the count gate really does reproduce the regression.
                Mock Get-OERCatalogResource {
                    param($Catalog, $IncludeRoles, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    Write-Error -Message "The resources of catalog '$Catalog' could not be read." -ErrorId 'CatalogResourceReadFailed' -Category PermissionDenied -TargetObject $Catalog -ErrorAction $Ea
                }
                Mock Remove-OERAccessPackageResourceRole { }
                Mock Add-OERAccessPackageResourceRole { }

                $Item = '{ "displayName": "AP-Sales", "catalog": "CAT-IT", "resourceRoles": [] }' | ConvertFrom-Json
                $Results = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)

                # CONTENT, not merely a count: both binding keys must be named, since a Failed count
                # of 0 would also hold for a handler that emitted nothing at all.
                $Removed = @($Results | Where-Object { $_.Action -eq 'Removed' })
                @($Removed).Count | Should -Be 2
                @($Removed.Detail) -join ' ' | Should -Match 'Member\|grp-1'
                @($Removed.Detail) -join ' ' | Should -Match 'Owner\|grp-2'
                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'an empty resourceRoles array consumes no catalog resource, so an unusable catalog read must not stop the prune'
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 2 -Exactly
                Should -Invoke Get-OERCatalogResource -Times 0 -Exactly
            }
        }
    }

    Context 'approval stage AlternateUser overwrite guard (issue #68)' {
        # Build-OERPolicyParts sets $StageParams.AlternateUser from the DOCUMENT's own alternateUsers
        # first, then (only for a stage with no explicit approver at all) falls back to the Tenant
        # Profile PrimaryApprovers/EscalationApprovers defaults. The fallback used to overwrite the
        # document's own AlternateUser unconditionally whenever it ran. These three Its use the REAL
        # New-OERAccessPackageApprovalStage builder (not mocked) so the assertion is on the actual
        # GraphStage.escalationApprovers the handler would send to Microsoft Graph, not merely on
        # which parameter name got bound.

        It 'declared users:[] with alternateUsers keeps the document value, not the profile EscalationApprovers default (spec acceptance test)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $PrimaryDefault = '11111111-1111-1111-1111-111111111111'
                $ProfileEscalation = '22222222-2222-2222-2222-222222222222'
                $DocAlternate = 'a@contoso.com'

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { $PrimaryDefault }
                    elseif ($Name -eq 'EscalationApprovers') { $ProfileEscalation }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7; users = @(); alternateUsers = @($DocAlternate) }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningAction SilentlyContinue)

                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    (@($ApprovalStage[0].GraphStage.escalationApprovers.userId) -contains $DocAlternate) -and
                    (@($ApprovalStage[0].GraphStage.escalationApprovers.userId) -notcontains $ProfileEscalation)
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }

        It 'declared no approver keys at all still receives the profile EscalationApprovers default (fallback still works)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $PrimaryDefault = '11111111-1111-1111-1111-111111111111'
                $ProfileEscalation = '22222222-2222-2222-2222-222222222222'

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { $PrimaryDefault }
                    elseif ($Name -eq 'EscalationApprovers') { $ProfileEscalation }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7 }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningAction SilentlyContinue)

                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApprovalStage[0].GraphStage.escalationApprovers.userId) -contains $ProfileEscalation
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }

        It 'declared alternateUsers:[] explicitly receives no escalation approver even though the profile has one (declared-empty means nobody)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $PrimaryDefault = '11111111-1111-1111-1111-111111111111'
                $ProfileEscalation = '22222222-2222-2222-2222-222222222222'

                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { $PrimaryDefault }
                    elseif ($Name -eq 'EscalationApprovers') { $ProfileEscalation }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7; alternateUsers = @() }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningAction SilentlyContinue)

                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApprovalStage[0].GraphStage.escalationApprovers).Count -eq 0
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }
    }

    Context 'approval stage PrimaryApprovers/EscalationApprovers substitution warning (issue #68)' {
        # The fallback branch is reached by two different document shapes that mean different things
        # to an operator; the warning text must distinguish them, and a stage with a real approver
        # (which never reaches the branch) must emit none at all.

        It 'warns "declared no approver keys at all" when the stage declares no approver keys whatsoever' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { '11111111-1111-1111-1111-111111111111' }
                    elseif ($Name -eq 'EscalationApprovers') { '22222222-2222-2222-2222-222222222222' }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7 }
                            )
                        }
                    )
                }
                $Warnings = @()
                $null = Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningVariable Warnings
                $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
                $Joined | Should -Match 'declared no approver keys at all'
            }
        }

        It 'warns "that are all empty" when the stage declares approver keys that are all declared-empty' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { '11111111-1111-1111-1111-111111111111' }
                    elseif ($Name -eq 'EscalationApprovers') { '22222222-2222-2222-2222-222222222222' }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7; users = @(); groups = @() }
                            )
                        }
                    )
                }
                $Warnings = @()
                $null = Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningVariable Warnings
                $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
                $Joined | Should -Match 'that are all empty'
            }
        }

        It 'names no EscalationApprovers at all, and never 1, when the Tenant Profile EscalationApprovers default is null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # PrimaryApprovers resolves; EscalationApprovers resolves to a bare $null -- the
                # shape @($null).Count misreports as 1, not 0, if counted without a truthiness guard.
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { '11111111-1111-1111-1111-111111111111' }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7 }
                            )
                        }
                    )
                }
                $Warnings = @()
                $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningVariable Warnings)
                $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
                # The @($null).Count -eq 1 trap this test was written for: the message must never
                # claim an escalation approver that was never substituted.
                $Joined | Should -Not -Match '1 EscalationApprovers'
                # Live-corrected: the message now names ONLY what was actually substituted, so with no
                # EscalationApprovers default the phrase is absent entirely rather than printed as
                # "0 EscalationApprovers". The primary count is still named.
                $Joined | Should -Not -Match 'EscalationApprovers'
                $Joined | Should -Match '1 PrimaryApprovers'
                # No escalation default was ever substituted, so -AlternateUser must never bind.
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApprovalStage[0].GraphStage.escalationApprovers).Count -eq 0
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }

        # LIVE-FOUND: the counts printed here were the PROFILE's contents, not what was applied. A stage
        # declaring "users": [] together with its own alternateUsers keeps the document's escalation
        # approver (issue #68's fix, verified live), yet the warning still said "1 EscalationApprovers"
        # -- reading exactly like the pre-#68 behaviour the warning was added to make visible. The
        # message must name only what was ACTUALLY substituted.
        It 'names only PrimaryApprovers when the document declared its own alternateUsers (no escalation substitution happened)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # The profile DOES carry an EscalationApprovers default -- it is simply not used here,
                # since the document declared alternateUsers of its own.
                Mock Resolve-OERStructureDefault {
                    param($TenantAlias, $Name)
                    if ($Name -eq 'PrimaryApprovers') { '11111111-1111-1111-1111-111111111111' }
                    elseif ($Name -eq 'EscalationApprovers') { '22222222-2222-2222-2222-222222222222' }
                    else { $null }
                }
                Mock Resolve-OERUserId { param($Id, $UserPrincipalName) if ($Id) { $Id } else { $UserPrincipalName } }
                Mock Resolve-OERGroupId { param($DisplayName) $DisplayName }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{
                                    durationDays   = 7
                                    users          = @()
                                    alternateUsers = @('33333333-3333-3333-3333-333333333333')
                                }
                            )
                        }
                    )
                }
                $Warnings = @()
                $r = @(Invoke-SyncApViaCaller -Item $Item -TenantAlias 'test' -WarningVariable Warnings)
                $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
                # The substitution warning still fires -- PrimaryApprovers WAS substituted.
                $Joined | Should -Match 'that are all empty'
                $Joined | Should -Match '1 PrimaryApprovers'
                # ...but no escalation approver was substituted, so the message must not name one.
                $Joined | Should -Not -Match 'EscalationApprovers'
                # The applied escalation approver is the DOCUMENT's, not the profile's -- the fact the
                # message has to agree with.
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApprovalStage[0].GraphStage.escalationApprovers).Count -eq 1 -and
                    ([string]$ApprovalStage[0].GraphStage.escalationApprovers[0].userId) -eq '33333333-3333-3333-3333-333333333333'
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }

        It 'emits no substitution warning when the stage declares a real approver' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7; manager = $true }
                            )
                        }
                    )
                }
                $Warnings = @()
                $null = Invoke-SyncApViaCaller -Item $Item -WarningVariable Warnings
                @($Warnings).Count | Should -Be 0
            }
        }
    }

    Context 'approval stage durationDays declaration guard (issue #70 site 3)' {
        # -DurationDays on New-OERAccessPackageApprovalStage is Mandatory, so Build-OERPolicyParts can
        # never omit the splat key -- the applied value stays 0 for an absent or explicit-null
        # durationDays, unchanged from the prior unguarded [int] cast. Each stage also declares
        # 'manager' so $HasExplicitApprover is true and the unrelated #68 fallback path never runs.
        #
        # MEASURED, not assumed: a DurationDays of 0 does NOT quietly become a "P0D" stage. The REAL
        # (unmocked) New-OERAccessPackageApprovalStage feeds -DurationDays into ConvertTo-OERDuration,
        # whose -Days parameter carries [ValidateRange(1, [int]::MaxValue)] -- 0 throws there, the
        # throw is caught by Build-OERPolicyParts's own try/catch, and the whole assignmentPolicy is
        # reported Failed without ever calling New-OERAccessPackageAssignmentPolicy. So the null and
        # omitted cases below assert Failed + zero policy-cmdlet calls, not a DurationDays of 0 on a
        # created policy.

        It 'declared value: durationDays is passed through unchanged' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 5; manager = $true }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item)
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                    $ApprovalStage[0].DurationDays -eq 5
                }
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            }
        }

        It 'declared null: durationDays applies as 0, which fails the assignmentPolicy build (same outcome as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = $null; manager = $true }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly
                $Failed = @($r | Where-Object Action -eq 'Failed')
                $Failed.Count | Should -BeGreaterThan 0
                ($Failed.Detail -join ' ') | Should -Match "failed to build assignmentPolicy 'Default'"
                ($Failed.Detail -join ' ') | Should -Match 'Days'
            }
        }

        It 'omitted: durationDays applies as 0, which fails the assignmentPolicy build (same outcome as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ manager = $true }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly
                $Failed = @($r | Where-Object Action -eq 'Failed')
                $Failed.Count | Should -BeGreaterThan 0
                ($Failed.Detail -join ' ') | Should -Match "failed to build assignmentPolicy 'Default'"
                ($Failed.Detail -join ' ') | Should -Match 'Days'
            }
        }
    }

    Context 'a stage build failure is reported with Action Failed, not an empty Action' {
        # A live finding claimed the "failed to build assignmentPolicy" path emits a StructureResult
        # with an EMPTY Action. DISPROVED, and this pins the disproof: the single call site passes
        # -Action 'Failed' as a literal, and ConvertTo-OERStructureResult's -Action is Mandatory with a
        # ValidateSet, so an empty Action cannot be constructed there at all. The assertion is on the
        # Action PROPERTY, never on a formatted table -- the rendered table is what made the claim look
        # true, and a table assertion would re-import that same ambiguity.
        It 'reports Action Failed with a "failed to build" Detail when the approval stage build throws' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # The build throws from inside the stage builder -- the generic form of the durationDays
                # case above, so the guard does not depend on that one mechanism staying reachable.
                Mock New-OERAccessPackageApprovalStage { throw 'stage builder refused this stage' }
                Mock New-OERAccessPackageAssignmentPolicy {}
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{
                            displayName    = 'Default'
                            approvalStages = @(
                                [PSCustomObject]@{ durationDays = 7; manager = $true }
                            )
                        }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Action | Should -BeExactly 'Failed'
                $Failed[0].Detail | Should -BeLike 'failed to build*'
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly
            }
        }
    }

    Context 'WhatIf preview labels for resourceRoles/assignmentPolicies route through Test-OERDeclaredProperty (issue #70)' {
        # $RrRef and $PolRef used to read `.PSObject.Properties.Name -contains ...` directly. Each site
        # gets its three declared-value/declared-null/omitted cases; the null and omitted cases must
        # both fall back to the '?' label.

        It 'resourceRole label: declared resource name is used in the preview row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resourceRole 'role_sec_x'" }).Count | Should -Be 1
            }
        }

        It 'resourceRole label: an explicit null resource name falls back to the ''?'' placeholder' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = $null; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resourceRole '\?'" }).Count | Should -Be 1
            }
        }

        It 'resourceRole label: an omitted resource key falls back to the ''?'' placeholder, same as an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resourceRole '\?'" }).Count | Should -Be 1
            }
        }

        It 'assignmentPolicy label: declared displayName is used in the preview row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure assignmentPolicy 'Default'" }).Count | Should -Be 1
            }
        }

        It 'assignmentPolicy label: an explicit null displayName falls back to the ''?'' placeholder' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = $null })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure assignmentPolicy '\?'" }).Count | Should -Be 1
            }
        }

        It 'assignmentPolicy label: an omitted displayName key falls back to the ''?'' placeholder, same as an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Sales'
                    catalog            = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{})
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure assignmentPolicy '\?'" }).Count | Should -Be 1
            }
        }
    }

    Context 'a stale GUID in the document is a Failed row, never a create (issue #71)' {

        It '4h: reports Failed naming the id, and never reaches the create path' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock New-OERAccessPackage { }
                Mock Set-OERAccessPackage { }
                Mock Get-OERAccessPackage { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault { $null }
                # The REAL Resolve-OERAccessPackageId runs here: the transport is what is mocked,
                # answering the existence read with the expected-error marker Graph's declared
                # not-found code produces.
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{
                        ExpectedErrorCode = 'ResourceNotFound'
                        StatusCode        = 404
                        Message           = 'ResourceNotFound: not found'
                        Uri               = $Uri
                    }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                }
                # No 'catalog' key on purpose: that is the branch which resolves tenant-wide through
                # Resolve-OERAccessPackageId, and the declared displayName is itself a stale GUID.
                $Item = [PSCustomObject]@{ displayName = '88888888-8888-8888-8888-888888888888' }
                $Records = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)

                $Failed = @($Records | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'failed to resolve access package'
                $Failed[0].Detail | Should -Match '88888888-8888-8888-8888-888888888888'
                $Failed[0].Detail | Should -Match 'NOT created'

                @($Records | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 0
                Should -Invoke New-OERAccessPackage -Times 0 -Exactly -Because (
                    'a stale id answered with $null would make the apply engine create a live access ' +
                    'package whose display name is that GUID')
            }
        }

        It '4h: a display name that resolves normally is untouched by the new catch' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock New-OERAccessPackage { }
                Mock Set-OERAccessPackage { }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault { $null }
                # The REAL resolver again, on the non-GUID path: one filtered match, no throw.
                Mock Invoke-OERGraphRequest {
                    if ($Uri -like '*resourceRoleScopes*') { return [PSCustomObject]@{ value = @() } }
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'ap-1'; displayName = 'AP-Sales' }) }
                }
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales' }
                $Records = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)
                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke New-OERAccessPackage -Times 0 -Exactly
            }
        }
    }

    Context 'the minimal assignmentPolicies create body that live check 5.10 rejected (issue #86 / F-B, 2026-09-11)' {
        # The live run applied { "displayName": "...", "requestorScope": { "scope": "NoSubjects" } }
        # and entitlement management answered "InvalidModel: The model is invalid." on the first run
        # and again on the converging run, so the entry never converged. The cause was NOT the
        # absent expiration -- expiration is optional on create and noExpiration is a documented
        # expirationPattern -- it was allowedTargetScope 'noSubjects', which is not a member of the
        # v1.0 enum. This test walks the REAL builder, the REAL cmdlet and the REAL body converter
        # and mocks only the transport, so what it asserts is the body that would reach Graph.
        It 'sends allowedTargetScope notSpecified, and carries expiration as noExpiration' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-NoSubjects'; Description = $null; IsHidden = $false } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                # Captured in module scope so the mock and the assertions share one variable; the
                # mock's own scope is inside the module either way.
                $script:OERTestPolicyCreateBody = $null
                Mock Invoke-OERGraphRequest {
                    if ($Uri -like '*entitlementManagement/assignmentPolicies*' -and $null -ne $Body) {
                        $script:OERTestPolicyCreateBody = $Body
                        return [PSCustomObject]@{ id = 'pol-1'; displayName = 'P' }
                    }
                    [PSCustomObject]@{ value = @() }
                }
                $Item = '{ "displayName": "AP-NoSubjects", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "scope": "NoSubjects" } } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue)

                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Records | Where-Object { $_.Action -eq 'Created' -and $_.Detail -like "*assignmentPolicy 'P'*" }).Count | Should -Be 1
                $Sent = $script:OERTestPolicyCreateBody
                $Sent | Should -Not -BeNullOrEmpty -Because 'the create path must have reached the transport exactly once'
                $Sent.allowedTargetScope | Should -Be 'notSpecified'
                $Sent.allowedTargetScope | Should -Not -Be 'noSubjects' -Because (
                    'noSubjects is not a member of the v1.0 allowedTargetScope enum, so sending it makes ' +
                    'entitlement management reject the whole model and the entry never converges')
                $Sent.expiration | Should -Not -BeNullOrEmpty -Because 'an entry declaring no duration still ships an explicit expirationPattern'
                $Sent.expiration.type | Should -Be 'noExpiration'
                $script:OERTestPolicyCreateBody = $null
            }
        }
    }
}
