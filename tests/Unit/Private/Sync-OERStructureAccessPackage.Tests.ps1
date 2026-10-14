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

    It 'approver-default fallback: a Tenant Profile that cannot be read -> Failed carries the profile error, not "no PrimaryApprovers default"' {
        # Resolve-OERStructureDefault used to turn a failed profile read (a profile that cannot be
        # parsed, declares no TenantId, or names an unsupported Environment) into $null, and this
        # handler then reported "no Tenant Profile PrimaryApprovers default" -- sending the operator to
        # add a default to a profile that already holds one but cannot be read. The helper now rethrows,
        # and the throw lands in this handler's existing try/catch around the policy build, whose Failed
        # row carries the real error. NO handler change is needed or made: this pins that the pair
        # works end to end, with the REAL Resolve-OERStructureDefault and only the profile read mocked.
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
            # A CMDLET failure mock, never Write-Error: Resolve-OERStructureDefault calls the profile
            # read with -ErrorAction Stop, and only the cmdlet's own WriteError is promoted by it.
            Mock Get-OERConfiguration {
                [CmdletBinding()] param([string]$TenantAlias, [string]$BasePath)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Tenant Profile 'test' at 'profile-path' could not be parsed and was skipped: profile read marker."),
                        'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, 'profile-path'))
            }
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
            # The positive half: the profile was read, once, through the real helper.
            Should -Invoke Get-OERConfiguration -Times 1 -Exactly -ParameterFilter { $TenantAlias -eq 'test' }
            $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
            $Failed.Count | Should -Be 1
            $Failed[0].Detail | Should -BeLike "failed to build assignmentPolicy 'Default':*"
            $Failed[0].Detail | Should -Match 'profile read marker'
            $Failed[0].Detail | Should -Not -Match 'no Tenant Profile PrimaryApprovers default'
            $Failed[0].Error | Should -Not -BeNullOrEmpty
            $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^TenantProfileMalformed'
            Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -Exactly
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

    It 'under -WhatIf on a missing AP, declared resourceRoles and assignmentPolicies each produce a preview row (would configure resourceRole, would create assignmentPolicy)' {
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
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would create assignmentPolicy 'Default' after access package is created" }).Count | Should -Be 1
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

    Context 'a package New-OERAccessPackage returns from another catalog (twin catalogs)' {
        # New-OERAccessPackage looks for an existing package by name in the WHOLE tenant and returns the one
        # package of that name it finds, whichever catalog holds it. When the declared catalog X does not
        # hold the package and a package of that name exists in catalog Y, that is Y's package: the entry
        # must fail with nothing written to it, nor anything else for the entry. Each It proves the create
        # was reached (New-OERAccessPackage called once), so a negative below is never vacuous. Fixture ids
        # are not version-4 shaped.

        It 'fails the entry and writes nothing when the catalog is declared by id' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                # Catalog X holds no package named AP-Twin; New-OERAccessPackage returns catalog Y's.
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-twin'; DisplayName = 'AP-Twin'; CatalogId = 'cccc0000-0000-0000-0000-0000000000c2' } }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph request: $Uri" }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Twin'
                    catalog            = 'cccc0000-0000-0000-0000-0000000000c1'
                    resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true }) })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly ("access package 'AP-Twin' was not created in catalog 'cccc0000-0000-0000-0000-0000000000c1': a package of that " +
                    'name already exists in another catalog (cccc0000-0000-0000-0000-0000000000c2), and New-OERAccessPackage returned it (ap-twin); nothing was written to it')
                @($Err).Count | Should -Be 0
                # Reached: the create was asked for in the declared catalog.
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cccc0000-0000-0000-0000-0000000000c1' -and $DisplayName -eq 'AP-Twin' }
                # Nothing written to Y's package, and nothing read for it: a catalog id needs no lookup.
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'fails the entry and writes nothing when the catalog is declared by a unique display name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-twin'; DisplayName = 'AP-Twin'; CatalogId = 'cat-y-id' } }
                # The real Resolve-OERCatalogId looks the declared name up once: one catalog carries it.
                Mock Invoke-OERGraphRequest {
                    if ($Uri -like 'v1.0/identityGovernance/entitlementManagement/catalogs?*') {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'cat-x-id'; displayName = 'CAT-X' }) }
                    }
                    throw "unexpected Graph request: $Uri"
                }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Twin'
                    catalog            = 'CAT-X'
                    resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true }) })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly ("access package 'AP-Twin' was not created in catalog 'CAT-X': a package of that name already exists in " +
                    'another catalog (cat-y-id), and New-OERAccessPackage returned it (ap-twin); nothing was written to it')
                @($Err).Count | Should -Be 0
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT-X' -and $DisplayName -eq 'AP-Twin' }
                # The one catalog lookup, and no other request.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq "v1.0/identityGovernance/entitlementManagement/catalogs?`$filter=displayName eq 'CAT-X'&`$select=id,displayName"
                }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'fails the entry, scrubbed and with nothing further written, when the declared catalog name cannot be looked up' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-twin'; DisplayName = 'AP-Twin'; CatalogId = 'cat-y-id' } }
                Mock Invoke-OERGraphRequest { throw 'graph 503' }
                Mock Remove-OERErrorRecord { }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock New-OERAccessPackageAssignmentPolicy { }
                $Item = [PSCustomObject]@{
                    displayName        = 'AP-Twin'
                    catalog            = 'CAT-X'
                    resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true }) })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly ("failed to look up catalog 'CAT-X' to confirm that access package 'AP-Twin' (ap-twin), which " +
                    'New-OERAccessPackage returned, belongs to it: graph 503; nothing further was written for it')
                $r[0].Error.Exception.Message | Should -BeExactly 'graph 503'
                # The handler publishes the failure once, through its caller; -ErrorVariable also holds the
                # records the inner layers left on their way up, which this does not count.
                @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-SyncApViaCaller') }).Count | Should -Be 1
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                # The handler's own catch scrubs first (the lookup is mocked at the transport, below it).
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
            }
        }

        It 'creates the package as before when New-OERAccessPackage returns one of the declared catalog (<Case>)' -ForEach @(
            @{ Case = 'declared by id, in another letter case'; Catalog = 'CCCC0000-0000-0000-0000-0000000000C1'; CatalogId = 'cccc0000-0000-0000-0000-0000000000c1'; Lookups = 0 }
            @{ Case = 'declared by name'; Catalog = 'CAT-X'; CatalogId = 'CAT-X-ID'; Lookups = 1 }
            @{ Case = 'declared by name, no catalog in the create response'; Catalog = 'CAT-X'; CatalogId = $null; Lookups = 0 }
            @{ Case = 'declared by id, an empty catalog in the create response'; Catalog = 'cccc0000-0000-0000-0000-0000000000c1'; CatalogId = ''; Lookups = 0 }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Catalog = $Catalog; CatalogId = $CatalogId; Lookups = $Lookups } {
                param($Catalog, $CatalogId, $Lookups)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Get-OERAccessPackage { @() }
                $script:TwinCreated = [PSCustomObject]@{ Id = 'ap-new'; DisplayName = 'AP-Twin'; CatalogId = $CatalogId }
                Mock New-OERAccessPackage { $script:TwinCreated }
                Mock Invoke-OERGraphRequest {
                    if ($Uri -like 'v1.0/identityGovernance/entitlementManagement/catalogs?*') {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'cat-x-id'; displayName = 'CAT-X' }) }
                    }
                    throw "unexpected Graph request: $Uri"
                }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Twin'
                    catalog       = $Catalog
                    resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 2
                $r[0].Action | Should -BeExactly 'Created'
                $r[0].Detail | Should -BeExactly 'created access package AP-Twin (ap-new)'
                $r[1].Action | Should -BeExactly 'Created'
                $r[1].Detail | Should -BeExactly "added resourceRole 'Member' on 'role_sec_x'"
                @($Err).Count | Should -Be 0
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-new' -and $ResourceOriginId -eq 'grp-1' }
                Should -Invoke Invoke-OERGraphRequest -Times $Lookups -Exactly
            }
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
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would create assignmentPolicy 'Default' after access package is created" }).Count | Should -Be 1
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
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would create assignmentPolicy '\?' after access package is created" }).Count | Should -Be 1
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
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would create assignmentPolicy '\?' after access package is created" }).Count | Should -Be 1
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

    Context 'prune withheld when a declared resourceRole resource cannot be resolved' {
        # A declared resource that matches no catalog resource and no group carries no origin id, so
        # the live binding it was meant to name looks undeclared. The pass must report that binding
        # Skipped with the withheld reason instead of Extra or Removed, while the unresolved entry
        # keeps its own Failed row.
        It 'withholds the resourceRole binding prune when a declared resource cannot be resolved' {
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
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id    = 'b-live'
                                role  = [PSCustomObject]@{ displayName = 'Member' }
                                scope = [PSCustomObject]@{ originId = 'grp-live' }
                            }
                        )
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
                        [PSCustomObject]@{ resource = 'no-such-group'; role = 'Member' }
                    )
                }
                $Warnings = @()
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail.Contains("undeclared resourceRole binding 'Member|grp-live'") })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''no-such-group'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve resource 'no-such-group' to an origin id in catalog 'CAT-IT'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'grp-live'
            }
        }

        It 'still aborts the item, and removes nothing, when a resource lookup throws under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                Mock Resolve-OERGroupId { throw 'Graph 503 while resolving the resource' }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                id    = 'b-live'
                                role  = [PSCustomObject]@{ displayName = 'Member' }
                                scope = [PSCustomObject]@{ originId = 'grp-live' }
                            }
                        )
                    }
                }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Remove-OERAccessPackageResourceRole {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName   = 'AP-Sales'
                    catalog       = 'CAT-IT'
                    resourceRoles = @(
                        [PSCustomObject]@{ resource = 'no-such-group'; role = 'Member' }
                    )
                }
                { Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } |
                    Should -Throw -ExpectedMessage '*Graph 503*'
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }
    }

    # A catalog keeps the display name a resource had when it was added, also after the group is
    # renamed (measured live 2026-09-30), and the inventory now exports a group resource under its
    # CURRENT name. So a declared resource name is resolved to the group FIRST when that group is a
    # resource of the catalog; only then is the name the catalog recorded consulted. Otherwise a name
    # the catalog still records for ANOTHER group would bind the role to that group and read the
    # renamed group's binding as undeclared.
    Context 'resourceRoles resolve a group by its current name before the name the catalog recorded' {

        It 'binds to the group the CURRENT name resolves to, not to another group recorded under that name, and prunes nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                # 'shared' is the name the catalog recorded for grp-a (since renamed); grp-b, recorded
                # as 'b-old', carries the name 'shared' now and holds the live binding. Both are groups,
                # which is what keeps grp-a from competing with grp-b (decision D5): the catalog always
                # reports the originSystem of a resource.
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'shared'; OriginId = 'grp-a'; Id = 'res-a'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ DisplayName = 'b-old'; OriginId = 'grp-b'; Id = 'res-b'; OriginSystem = 'AadGroup' }
                    )
                }
                Mock Resolve-OERGroupId { 'grp-b' } -ParameterFilter { $DisplayName -eq 'shared' }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'bind-b'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-b' } }) }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole {}
                Mock Remove-OERAccessPackageResourceRole {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'shared'; role = 'Member' }) }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on 'shared' already bound" }).Count | Should -Be 1
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'keeps resolving an application or a site by the name the catalog recorded when no group carries that name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'Contoso App'; OriginId = 'sp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'bind-1'; role = [PSCustomObject]@{ displayName = 'User' }; scope = [PSCustomObject]@{ originId = 'sp-1' } }) }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole {}
                Mock Remove-OERAccessPackageResourceRole {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'Contoso App'; role = 'User' }) }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'User' on 'Contoso App' already bound" }).Count | Should -Be 1
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'sets an ambiguous group name aside while the name the catalog recorded can decide' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; Id = 'res-1' } }
                Mock Resolve-OERGroupId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Group display name 'Finance' matches 2 groups (g-a, g-b)."), 'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Finance')
                }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'bind-1'; role = [PSCustomObject]@{ displayName = 'Read' }; scope = [PSCustomObject]@{ originId = 'https://contoso.sharepoint.com/sites/finance' } }) }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Remove-OERAccessPackageResourceRole {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Read' }) }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Read' on 'Finance' already bound" }).Count | Should -Be 1
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'throws the ambiguous group name when the name the catalog recorded cannot decide either, removing nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'other'; OriginId = 'grp-z'; Id = 'res-1' } }
                Mock Resolve-OERGroupId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Group display name 'dup' matches 2 groups (g-a, g-b)."), 'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup')
                }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'bind-z'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-z' } }) }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Remove-OERAccessPackageResourceRole {}
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'dup'; role = 'Member' }) }
                { Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } |
                    Should -Throw -ErrorId 'AmbiguousName'
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }
    }

    # Decision D3 (Philip, 2026-10-03): the handler picked the FIRST of several assignment policies of
    # one access package that share the declared display name, then diffed and updated that policy
    # (requestor scope, approval) -- a silent write to an arbitrary policy. Graph does not enforce
    # unique policy display names within a package. It now refuses, the way the access review
    # handler does for definitions (decision D2): one Failed row, one published AmbiguousName record
    # naming every candidate id, and nothing created or updated for THAT policy. The package's other
    # declared policies are processed as before.
    #
    # Every ambiguous fixture below carries a live shape that DRIFTS from the declaration
    # (durationInDays 10 live, 30 declared), so a handler that wrongly took the first match reaches
    # Set-OERAccessPackageAssignmentPolicy -- the zero-call assertions then fail for the right reason
    # instead of passing because the diff found nothing to do.
    Context 'an ambiguous assignment policy name is refused' {

        It 'creates and updates nothing for a policy whose name two live policies share' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # Positive proof first: the live policies were read, once, and the policy was reported
                # Failed -- so the zero-call assertions below are a refusal, not a handler that never
                # got as far as the policies.
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 1

                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'reports one Failed row naming the package, the policy name, the count and both ids' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Section | Should -Be 'accessPackages'
                $Failed[0].Item | Should -Be 'AP-Sales'
                $Failed[0].Detail | Should -BeLike "2 assignment policies of 'AP-Sales' are named 'Standard' (*"
                $Failed[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Failed[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
                $Failed[0].Detail | Should -BeLike '*nothing was written for it*'
            }
        }

        It 'publishes exactly one AmbiguousName record carrying the name, the package and both ids, and attaches it to the row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Records.Count | Should -Be 1 -Because 'one error is published for the ambiguous policy, no more'
                $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Records[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Records[0].TargetObject | Should -Be 'Standard'
                $Records[0].Exception.Message | Should -BeLike "Assignment policy display name 'Standard' matches 2 policies (*) in access package 'AP-Sales'.*"
                $Records[0].Exception.Message | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Records[0].Exception.Message | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
                $Records[0].Exception.Message | Should -BeLike '*Access packages do not enforce unique policy display names*'
                $Records[0].Exception.Message | Should -BeLike '*Rename one of them so the display name is unique.'
                # The document cannot name a policy by id, so the message must not advise doing so.
                $Records[0].Exception.Message | Should -Not -BeLike '*policy id instead*'

                # The Failed row carries the very record that was published.
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Failed[0].Error.Exception.Message | Should -Be $Records[0].Exception.Message
            }
        }

        It 'names every candidate and the right count when three policies share the name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Standard'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "3 assignment policies of 'AP-Sales' are named 'Standard'*"
                $Failed[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Failed[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
                $Failed[0].Detail | Should -BeLike '*33333333-3333-3333-3333-333333333333*'
                $Failed[0].Error.Exception.Message | Should -BeLike '*matches 3 policies (*33333333-3333-3333-3333-333333333333*'
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'refuses under -WhatIf as well, since refusing is not a write and ShouldProcess is never reached' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "2 assignment policies of 'AP-Sales' are named 'Standard'*"
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "*assignmentPolicy 'Standard'*" }).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'still processes the package''s other declared policies when one declared policy is ambiguous' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                # 'Standard' is shared by two live policies; 'Single' exists once and drifts; 'Fresh'
                # does not exist at all. The ambiguous policy is declared FIRST, so a refusal that did
                # not move on to the next declared policy would starve the other two.
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Single'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @(
                        [PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 }
                        [PSCustomObject]@{ displayName = 'Single'; durationInDays = 30 }
                        [PSCustomObject]@{ displayName = 'Fresh'; durationInDays = 30 }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The ambiguous policy: refused, and touched by neither write.
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like "*named 'Standard'*" }).Count | Should -Be 1
                # A refused policy is still a DECLARED one: it is not also reported as an undeclared
                # live policy ('Extra') for each of the two live policies that carry its name.
                @($r | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0 -ParameterFilter { $Id -in @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222') }
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0 -ParameterFilter { $DisplayName -eq 'Standard' }

                # The others: the single match is updated by ITS id, the absent one is created.
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $Id -eq '33333333-3333-3333-3333-333333333333' -and $DisplayName -eq 'Single' }
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Fresh' }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like "*assignmentPolicy 'Single'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Created' -and $_.Detail -like "*assignmentPolicy 'Fresh'*" }).Count | Should -Be 1
            }
        }

        It 'leaves a single matching policy alone, even when other live policies carry other names (no AmbiguousName)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @(
                        [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 }
                        [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Other'; DurationInDays = 10 }
                    )
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 10 })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "assignmentPolicy 'Standard' matches" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -like "*'Other'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'updates a single matching policy by its own id, with no AmbiguousName' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null; IsHidden = $false } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy {
                    @([PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Standard'; DurationInDays = 10 })
                }
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $Id -eq '11111111-1111-1111-1111-111111111111' }
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            }
        }

        It 'creates a declared policy no live policy carries, with no AmbiguousName' {
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
                Mock Set-OERAccessPackageAssignmentPolicy { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Standard'; durationInDays = 30 })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Standard' }
                Should -Invoke Set-OERAccessPackageAssignmentPolicy -Times 0
                @($r | Where-Object { $_.Action -eq 'Created' -and $_.Detail -like "*assignmentPolicy 'Standard'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            }
        }
    }

    # Decision D4 (Philip, 2026-10-03): a declared resourceRoles[].resource that is not a catalog group
    # is resolved by the display name the catalog recorded, and the handler took the FIRST catalog
    # resource carrying that name. A catalog does not enforce unique resource display names (two
    # same-named groups, an application and a group, two sites), so the role was bound to an arbitrary
    # one -- and under -Prune the binding of the RIGHT resource then read as undeclared and was
    # removed. It now refuses: one Failed row naming every candidate origin id, one AmbiguousName
    # record, and the name counts as unresolved, so the existing withhold-prune rule keeps the
    # package's live bindings exactly as it does for a name that matches no resource at all.
    #
    # Every ambiguous fixture below holds the live binding on the SECOND of the two same-named
    # resources, so a handler that wrongly took the first match would add a binding to the first and
    # remove the live one under -Prune -- the zero-call assertions then fail for the right reason.
    Context 'an ambiguous catalog resource name in a binding is refused' {

        It 'adds no binding for a name two catalog resources share, and says so in one Failed row naming both origin ids' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # Positive proof first: the catalog was read, once, and the entry was reported Failed --
                # so the zero-call assertions below are a refusal, not a handler that never got that far.
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Section | Should -Be 'accessPackages'
                $Failed[0].Item | Should -Be 'AP-Sales'
                $Failed[0].Detail | Should -BeLike "2 resources of catalog 'CAT-IT' are named 'Finance' (*"
                $Failed[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Failed[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
                $Failed[0].Detail | Should -BeLike '*no resourceRole was added for it*'

                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 0
            }
        }

        It 'publishes exactly one AmbiguousName record carrying the name, the catalog and both origin ids, and attaches it to the row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Records[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Records[0].TargetObject | Should -Be 'Finance'
                $Records[0].Exception.Message | Should -Be ("Resource name 'Finance' matches 2 resources of catalog 'CAT-IT' (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222). " +
                    'A catalog does not enforce unique resource display names, so this name cannot identify a single resource. ' +
                    'Declare a group or an application by one of the origin ids listed above, ' +
                    'or refresh or remove and re-add one of the resources in the catalog so their recorded names differ.')

                # The Failed row carries the very record that was published.
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Failed[0].Error.Exception.Message | Should -Be $Records[0].Exception.Message
            }
        }

        It 'removes no live binding under -Prune and reports each candidate Skipped as a withheld prune, the binding of the second same-named resource included' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                # The package already holds a binding on the SECOND Finance resource (the one the document
                # means) and one on an unrelated resource. Taking the first match would declare Member on
                # the FIRST resource, leaving both of these undeclared and removed under -Prune.
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-live-2'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                            [PSCustomObject]@{ id = 'b-other'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = '33333333-3333-3333-3333-333333333333' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $Warnings = @()
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)

                # Positive proof: the live bindings were read (they are named in the rows below) and the
                # ambiguous entry was refused -- so the zero-call assertions are the withhold at work.
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like "2 resources of catalog 'CAT-IT' are named 'Finance'*" }).Count | Should -Be 1

                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'removing'

                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' })
                $Withheld.Count | Should -Be 2
                @($Withheld | Where-Object { $_.Detail -like "*undeclared resourceRole binding 'Member|22222222-2222-2222-2222-222222222222'*" }).Count | Should -Be 1
                @($Withheld | Where-Object { $_.Detail -like "*undeclared resourceRole binding 'Owner|33333333-3333-3333-3333-333333333333'*" }).Count | Should -Be 1
                $Withheld[0].Detail | Should -BeLike "prune withheld: declared entry 'Finance' could not be resolved*"
            }
        }

        It 'withholds the Extra report too when -Prune is not set' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-live-2'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 1
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "prune withheld: declared entry 'Finance' could not be resolved*" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -BeLike "*undeclared resourceRole binding 'Member|22222222-2222-2222-2222-222222222222'*"
                @($r | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'refuses under -WhatIf as well, since refusing is not a write and ShouldProcess is never reached' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like "2 resources of catalog 'CAT-IT' are named 'Finance'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would add resourceRole*" }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'names every candidate and the right count when three catalog resources share the name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = 'https://contoso.sharepoint.com/sites/finance'; Id = 'res-c' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "3 resources of catalog 'CAT-IT' are named 'Finance'*"
                $Failed[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Failed[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
                $Failed[0].Detail | Should -BeLike '*https://contoso.sharepoint.com/sites/finance*'
                $Failed[0].Error.Exception.Message | Should -BeLike "*matches 3 resources of catalog 'CAT-IT' (*https://contoso.sharepoint.com/sites/finance)*"
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'still processes the package''s other declared resourceRoles when one declared name is ambiguous' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                        [PSCustomObject]@{ DisplayName = 'Wiki'; OriginId = '44444444-4444-4444-4444-444444444444'; Id = 'res-w' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                # The ambiguous entry is declared FIRST, so a refusal that did not move on to the next
                # declared entry would starve the one after it.
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @(
                        [PSCustomObject]@{ resource = 'Finance'; role = 'Member' }
                        [PSCustomObject]@{ resource = 'Wiki'; role = 'Reader' }
                    )
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like "*are named 'Finance'*" }).Count | Should -Be 1
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0 -ParameterFilter { $ResourceOriginId -in @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222') }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $ResourceOriginId -eq '44444444-4444-4444-4444-444444444444' -and $Role -eq 'Reader' }
                @($r | Where-Object { $_.Action -eq 'Created' -and $_.Detail -eq "added resourceRole 'Reader' on 'Wiki'" }).Count | Should -Be 1
            }
        }

        It 'leaves a name exactly one catalog resource carries alone, even when other resources carry other names' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Wiki'; OriginId = '44444444-4444-4444-4444-444444444444'; Id = 'res-w' }
                    )
                }
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-live-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '11111111-1111-1111-1111-111111111111' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @(
                        [PSCustomObject]@{ resource = 'Finance'; role = 'Member' }
                        [PSCustomObject]@{ resource = 'Wiki'; role = 'Reader' }
                    )
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                # 'Finance' matches one resource and is already bound; 'Wiki' matches one and is added
                # by ITS origin id. Nothing is refused, withheld or removed.
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on 'Finance' already bound" }).Count | Should -Be 1
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $ResourceOriginId -eq '44444444-4444-4444-4444-444444444444' -and $Role -eq 'Reader' }
                @($r | Where-Object { $_.Action -eq 'Created' -and $_.Detail -eq "added resourceRole 'Reader' on 'Wiki'" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($r | Where-Object { $_.Detail -like 'prune withheld:*' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'binds a declared object id even when two catalog resources share a display name, which is the way out the message names' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                # Resolve-OERGroupId is deliberately NOT mocked: a GUID is returned verbatim with no Graph
                # call, which is the path that decides here (the catalog resource whose origin id it is).
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-live-2'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = '22222222-2222-2222-2222-222222222222'; role = 'Member' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on '22222222-2222-2222-2222-222222222222' already bound" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'refuses a name several groups AND several catalog resources share, instead of binding the first resource or throwing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '11111111-1111-1111-1111-111111111111'; Id = 'res-a' }
                        [PSCustomObject]@{ DisplayName = 'Finance'; OriginId = '22222222-2222-2222-2222-222222222222'; Id = 'res-b' }
                    )
                }
                Mock Resolve-OERGroupId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Group display name 'Finance' matches 2 groups (g-a, g-b)."), 'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Finance')
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-live-2'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Sales'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Resolve-OERGroupId -Times 1 -Exactly
                # -ErrorVariable also holds the engine's own capture of the group resolver's throw, so the
                # published record is found by its text, not by counting every record.
                $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.Exception.Message -like "Resource name 'Finance' matches*" })
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Records[0].Exception.Message | Should -BeLike "Resource name 'Finance' matches 2 resources of catalog 'CAT-IT' (*"
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like "2 resources of catalog 'CAT-IT' are named 'Finance'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' }).Count | Should -Be 1
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }
    }

    # Decision D5 (Philip, 2026-10-03), found by the ambiguity sweep (P0-1): decision D4's refusal only
    # ran when step 1 (the group the declared name resolves to, when that group is a resource of the
    # catalog) did not decide. So a group and an APPLICATION (or a site) recorded under one display
    # name in one catalog were never compared: the group won step 1, the add then bound the wrong
    # resource or failed, and under -Prune the binding of the resource the entry really names read as
    # undeclared and was removed. Step 3 (a group that is NOT in the catalog becomes the origin id)
    # had the same ending: the add can only fail, and the live binding of the renamed application the
    # entry named was removed. Both now count as unresolved, so the existing withhold-prune rule keeps
    # the package's live bindings.
    #
    # Every fixture holds the live binding on the NON-group resource (the application), which is the
    # one the old code removed under -Prune.
    Context 'a group sharing its name with a non-group catalog resource is refused, and a group outside the catalog counts as unresolved' {

        It 'adds no binding and removes no live binding under -Prune: the probe case of a group and an application named alike' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'res-g'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Payroll'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' }
                    )
                }
                Mock Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-app'; role = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $Warnings = @()
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)

                # The catalog was read once, so the zero-call assertions below are the refusal and the
                # withhold at work (the Failed row and the withheld row follow as the positive proof). The
                # removal comes first: it is the defect itself.
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'removing'

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "2 resources of catalog 'CAT-IT' are named 'Payroll' (*"
                $Failed[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
                $Failed[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'

                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -BeLike "prune withheld: declared entry 'Payroll' could not be resolved*"
                $Withheld[0].Detail | Should -BeLike "*undeclared resourceRole binding 'Reader|22222222-2222-2222-2222-222222222222'*"
            }
        }

        It 'publishes exactly one AmbiguousName record naming the group and the application, and a way out that fits every resource type' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' }
                        [PSCustomObject]@{ Id = 'res-g'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Payroll'; OriginSystem = 'AadGroup' }
                    )
                }
                Mock Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Records[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Records[0].TargetObject | Should -Be 'Payroll'
                # The group is listed first, then the others in catalog order, whatever the catalog order is.
                $Records[0].Exception.Message | Should -Be ("Resource name 'Payroll' matches 2 resources of catalog 'CAT-IT' (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222). " +
                    'A catalog does not enforce unique resource display names, so this name cannot identify a single resource. ' +
                    'Declare a group or an application by one of the origin ids listed above, ' +
                    'or refresh or remove and re-add one of the resources in the catalog so their recorded names differ.')

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.Exception.Message | Should -Be $Records[0].Exception.Message
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'counts a renamed group, an application and a site recorded under the name as three resources' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                # The group is recorded under its OLD name (the rename case), yet the name now also
                # belongs to an application and to a site: the group must not win over them.
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'res-g'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Payroll-old'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' }
                        [PSCustomObject]@{ Id = 'res-s'; OriginId = 'https://contoso.sharepoint.com/sites/payroll'; DisplayName = 'Payroll'; OriginSystem = 'SharePointOnline' }
                    )
                }
                Mock Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "3 resources of catalog 'CAT-IT' are named 'Payroll' (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222, https://contoso.sharepoint.com/sites/payroll);*"
                $Failed[0].Error.Exception.Message | Should -BeLike "Resource name 'Payroll' matches 3 resources of catalog 'CAT-IT' (*https://contoso.sharepoint.com/sites/payroll)*"
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'still resolves a renamed group through step 1: a group the catalog recorded under another name is not a competitor, and the prune is not withheld' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                # 'shared' is the name the catalog recorded for grp-a (since renamed); grp-b, recorded as
                # 'b-old', carries the name 'shared' now and holds the live binding. Both are groups. An
                # application of another name sits in the catalog too, with an undeclared live binding.
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ DisplayName = 'shared'; OriginId = 'grp-a'; Id = 'res-a'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ DisplayName = 'b-old'; OriginId = 'grp-b'; Id = 'res-b'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ DisplayName = 'Contoso App'; OriginId = 'app-9'; Id = 'res-c'; OriginSystem = 'AadApplication' }
                    )
                }
                Mock Resolve-OERGroupId { 'grp-b' } -ParameterFilter { $DisplayName -eq 'shared' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'bind-b'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-b' } }
                            [PSCustomObject]@{ id = 'bind-x'; role = [PSCustomObject]@{ displayName = 'User' }; scope = [PSCustomObject]@{ originId = 'app-9' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'shared'; role = 'Member' }) }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                # Step 1 decided: the entry is bound to grp-b and reported Unchanged, nothing refused.
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on 'shared' already bound" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                # The prune is NOT withheld: the application's undeclared binding is still removed under
                # -Prune, exactly as before this decision.
                @($r | Where-Object { $_.Detail -like 'prune withheld:*' }).Count | Should -Be 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 1 -Exactly
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $ResourceRoleScopeId -eq 'bind-x' }
                @($r | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -like "*'User|app-9'*" }).Count | Should -Be 1
            }
        }

        It 'never lets a group compete with its own catalog entry, whatever that entry records for originSystem' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Sales'; Description = $null } }
                # The group's own catalog entry is recorded under the declared name and carries no
                # originSystem at all (so it is not 'AadGroup'): the one thing that keeps it from being
                # counted as a second resource under the name is that its origin id IS the group's.
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'bind-1'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = 'grp-1' } }) }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{ displayName = 'AP-Sales'; catalog = 'CAT-IT'; resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' }) }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on 'role_sec_x' already bound" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                @($r | Where-Object { $_.Detail -like 'prune withheld:*' }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'counts a group outside the catalog as unresolved: the add fails and the renamed application binding survives -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                # The application was renamed after onboarding: the catalog still records 'Payroll-old',
                # while the document (like the inventory) names it by its CURRENT name 'Payroll'. A group
                # of that current name exists, but is not a resource of the catalog.
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll-old'; OriginSystem = 'AadApplication' })
                }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-555555555555' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-app'; role = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                # The real cmdlet reports a group outside the catalog as a non-terminating error and
                # emits nothing; the handler calls it with -ErrorAction Stop, which only the cmdlet's
                # own WriteError is promoted by.
                Mock Add-OERAccessPackageResourceRole {
                    [CmdletBinding(SupportsShouldProcess)] param([string]$AccessPackage, [string]$Catalog, [string]$ResourceOriginId, [string]$Role)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Resource '$ResourceOriginId' not found in catalog '$Catalog'."), 'CatalogResourceNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound, $ResourceOriginId))
                }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # Positive proof first: step 3 was reached (the add was tried against the group's id,
                # once) and the entry kept its own Failed row from that failed add.
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $ResourceOriginId -eq '55555555-5555-5555-5555-555555555555' -and $Role -eq 'Reader' }
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "failed to add resourceRole 'Reader' on 'Payroll': *not found in catalog*"

                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -BeLike "prune withheld: declared entry 'Payroll' could not be resolved*"
                $Withheld[0].Detail | Should -BeLike "*undeclared resourceRole binding 'Reader|22222222-2222-2222-2222-222222222222'*"
            }
        }

        It 'withholds the prune for a group outside the catalog under -WhatIf too, where the add is never attempted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll-old'; OriginSystem = 'AadApplication' })
                }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-555555555555' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-app'; role = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The would-add row shows step 3 was reached; the binding is reported withheld, never as
                # a prune candidate ("would remove").
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would add resourceRole 'Reader' on 'Payroll'" }).Count | Should -Be 1
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' -and $_.Detail -like "*'Reader|22222222-2222-2222-2222-222222222222'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would remove undeclared*" }).Count | Should -Be 0
            }
        }
    }

    # Decision D5, fix round 1 (controller ruling T12a): step 2 accepted a SINGLE catalog match even when a
    # group currently carries the declared name but is not in the catalog. The catalog keeps the name a
    # group had when it was added: group A, recorded as 'Finance' and since renamed, and group B, which
    # now carries 'Finance' outside the catalog, made step 2 bind the role to A -- a silent wrong write.
    # A single match that is another GROUP is now refused like the other ambiguities, listing both ids.
    # Only a positively identified AadGroup counts: an application recorded under the name stays
    # accepted, since the inventory round trip of an application that shares its name with any group of
    # the tenant produces exactly that.
    Context 'a group outside the catalog does not hand its name to the other group the catalog recorded under it' {

        It 'adds no binding to the renamed group the catalog recorded, and removes no live binding under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Finance'; Description = $null } }
                # Group A is in the catalog under the name it had when it was added ('Finance'); it has
                # since been renamed. Group B carries 'Finance' now and is not in the catalog.
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'res-a'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Finance'; OriginSystem = 'AadGroup' }
                        [PSCustomObject]@{ Id = 'res-o'; OriginId = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Other App'; OriginSystem = 'AadApplication' }
                    )
                }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-555555555555' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{ id = 'b-other'; role = [PSCustomObject]@{ displayName = 'Owner' }; scope = [PSCustomObject]@{ originId = '33333333-3333-3333-3333-333333333333' } }
                        )
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Finance'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The catalog was read once, so the zero-call assertions are the refusal at work: the old
                # code bound the role to group A (the write) and, with the entry bound, pruned the
                # unrelated live binding.
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
                @($r | Where-Object { $_.Action -eq 'Created' -or $_.Action -eq 'Removed' }).Count | Should -Be 0

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "2 resources of catalog 'CAT-IT' are named 'Finance' (55555555-5555-5555-5555-555555555555, 11111111-1111-1111-1111-111111111111);*"
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -BeLike "prune withheld: declared entry 'Finance' could not be resolved*"
                $Withheld[0].Detail | Should -BeLike "*undeclared resourceRole binding 'Owner|33333333-3333-3333-3333-333333333333'*"
            }
        }

        It 'publishes exactly one AmbiguousName record listing the group outside the catalog first and the recorded group second' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Finance'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Finance'; OriginSystem = 'AadGroup' })
                }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-555555555555' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Finance'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Records[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Records[0].TargetObject | Should -Be 'Finance'
                $Records[0].Exception.Message | Should -Be ("Resource name 'Finance' matches 2 resources of catalog 'CAT-IT' (55555555-5555-5555-5555-555555555555, 11111111-1111-1111-1111-111111111111). " +
                    'A catalog does not enforce unique resource display names, so this name cannot identify a single resource. ' +
                    'Declare a group or an application by one of the origin ids listed above, ' +
                    'or refresh or remove and re-add one of the resources in the catalog so their recorded names differ.')
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.Exception.Message | Should -Be $Records[0].Exception.Message
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'still accepts the one application recorded under the name while a group outside the catalog carries it too' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                # The inventory round trip of an application that shares its name with a group of the
                # tenant: the group is not in the catalog, the application is the one resource recorded
                # under the name. It must stay bound, not refused.
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' })
                }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-555555555555' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = 'b-app'; role = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ originId = '22222222-2222-2222-2222-222222222222' } })
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'Reader' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Reader' on 'Payroll' already bound" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($r | Where-Object { $_.Detail -like 'prune withheld:*' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'still resolves the one group the catalog recorded under the name when no group carries that name now' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Finance'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Finance'; OriginSystem = 'AadGroup' })
                }
                # No group carries the name any more: the group's own recorded name is all there is.
                Mock Resolve-OERGroupId { $null }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest {
                    [PSCustomObject]@{
                        value = @([PSCustomObject]@{ id = 'b-a'; role = [PSCustomObject]@{ displayName = 'Member' }; scope = [PSCustomObject]@{ originId = '11111111-1111-1111-1111-111111111111' } })
                    }
                } -ParameterFilter { $Uri -like '*resourceRoleScopes*' }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Remove-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Finance'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Finance'; role = 'Member' })
                }
                $Published = $null
                $r = @(Invoke-SyncApViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Published)

                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resourceRole 'Member' on 'Finance' already bound" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($r | Where-Object { $_.Detail -like 'prune withheld:*' }).Count | Should -Be 0
                @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Remove-OERAccessPackageResourceRole -Times 0
            }
        }
    }

    Context 'a role name several roles of the resource share is refused by the real cmdlet, and the engine reports it as a Failed row' {
        # Application roles do not have unique display names. Add-OERAccessPackageResourceRole used to bind
        # the FIRST role carrying the name, so an access package granted an arbitrary one of them. It now
        # refuses, and the engine -- which calls it with -ErrorAction Stop -- turns the refusal into a Failed
        # row. The cmdlet under test here is the REAL one: only the reads and the transport are mocked.

        It 'reports a Failed row carrying the ambiguity message and posts no binding' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' })
                }
                Mock Resolve-OERGroupId { $null }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERAccessPackageResourceRole { $null }
                # The cmdlet reads the resource itself, with its roles: two application roles named 'User'.
                Mock Resolve-OERCatalogResource {
                    [PSCustomObject]@{
                        id           = 'res-a'
                        displayName  = 'Payroll'
                        originId     = '22222222-2222-2222-2222-222222222222'
                        originSystem = 'AadApplication'
                        roles        = @(
                            [PSCustomObject]@{ id = 'role-1'; displayName = 'User'; originId = 'aaaaaaaa-0000-0000-0000-00000000a001' }
                            [PSCustomObject]@{ id = 'role-2'; displayName = 'User'; originId = 'aaaaaaaa-0000-0000-0000-00000000a002' }
                        )
                    }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = 'rrs-posted' } } -ParameterFilter { $Method -eq 'POST' }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'User' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The cmdlet was reached and read the resource (the positive proof), then refused.
                Should -Invoke Resolve-OERCatalogResource -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 0

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "failed to add resourceRole 'User' on 'Payroll': Role 'User' matches 2 roles of resource 'Payroll' (*"
                $Failed[0].Detail | Should -BeLike '*aaaaaaaa-0000-0000-0000-00000000a001*'
                $Failed[0].Detail | Should -BeLike '*aaaaaaaa-0000-0000-0000-00000000a002*'
                $Failed[0].Error.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            }
        }

        It 'binds the role once when only one role of the resource carries the name (control)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAccessPackageId { 'ap-1' }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-Payroll'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{ Id = 'res-a'; OriginId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Payroll'; OriginSystem = 'AadApplication' })
                }
                Mock Resolve-OERGroupId { $null }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERAccessPackageResourceRole { $null }
                Mock Resolve-OERCatalogResource {
                    [PSCustomObject]@{
                        id           = 'res-a'
                        displayName  = 'Payroll'
                        originId     = '22222222-2222-2222-2222-222222222222'
                        originSystem = 'AadApplication'
                        roles        = @(
                            [PSCustomObject]@{ id = 'role-1'; displayName = 'User'; originId = 'aaaaaaaa-0000-0000-0000-00000000a001' }
                            [PSCustomObject]@{ id = 'role-3'; displayName = 'Admin'; originId = 'aaaaaaaa-0000-0000-0000-00000000a003' }
                        )
                    }
                }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = 'rrs-posted' } } -ParameterFilter { $Method -eq 'POST' }
                $Item = [PSCustomObject]@{
                    displayName = 'AP-Payroll'; catalog = 'CAT-IT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'Payroll'; role = 'User' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.role.originId -eq 'aaaaaaaa-0000-0000-0000-00000000a001'
                }
                @($r | Where-Object { $_.Action -eq 'Created' -and $_.Detail -eq "added resourceRole 'User' on 'Payroll'" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            }
        }
    }
}

# BL-11: the requestor scope takes every Microsoft Graph v1.0 allowedTargetScope value. Every test
# below walks the REAL New-OERAccessPackageRequestorScope, ConvertTo-OERPolicyBody and
# ConvertTo-OERAssignmentPolicy -- each live policy is the real projection of a raw Graph fixture --
# with only authentication, the package-level reads and the transport mocked, so what is asserted is
# what the engine decides. Where the write itself is the question (R5), the REAL
# Set-/New-OERAccessPackageAssignmentPolicy run too and the body is read where it leaves, at the
# transport. Elsewhere Set/New are mocked so "nothing written" is a call count of zero.
Describe 'Sync-OERStructureAccessPackage -- every Microsoft Graph v1.0 requestor scope (BL-11)' {
    BeforeAll {
        function New-Bl11RawPolicy {
            param(
                [string]$Id = '11111111-1111-1111-1111-111111111111',
                [string]$DisplayName = 'Partners',
                [string]$Description = 'live description',
                [Parameter(Mandatory)][string]$AllowedTargetScope,
                [object[]]$SpecificAllowedTargets = @()
            )
            @{
                id                      = $Id
                displayName             = $DisplayName
                description             = $Description
                accessPackage           = @{ id = 'ap-1' }
                allowedTargetScope      = $AllowedTargetScope
                specificAllowedTargets  = @($SpecificAllowedTargets)
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $false
                    isApprovalRequiredForUpdate      = $false
                    isRequestorJustificationRequired = $false
                    stages                           = @()
                }
                notificationSettings    = @{ isAssignmentNotificationDisabled = $false }
            }
        }

        function New-Bl11ConnectedOrgTarget {
            @{
                '@odata.type'           = '#microsoft.graph.connectedOrganizationMembers'
                connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                description             = 'Partner organization'
            }
        }

        # Runs the handler for one document item against the given raw live policies and returns the
        # rows, the error records it published, and every PUT/POST the transport received.
        function Invoke-Bl11Sync {
            param([PSCustomObject]$Item, [object[]]$Live = @(), [bool]$UseWhatIf = $false)
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Item = $Item; Live = $Live; UseWhatIf = $UseWhatIf } {
                param($Item, $Live, $UseWhatIf)
                $script:OERTestBl11Live = @($Live)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $Published = $null
                $Rows = @(Invoke-SyncApViaCaller -Item $Item -WhatIf:$UseWhatIf -WarningAction SilentlyContinue `
                        -ErrorAction SilentlyContinue -ErrorVariable Published)
                [PSCustomObject]@{
                    Rows      = $Rows
                    Published = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                    Sent      = @($script:OERTestBl11Sent)
                }
            }
        }
    }

    BeforeEach {
        # Defined inside the module's scope so each mock body runs there: it reads the module-scoped
        # fixtures below and calls the private ConvertTo-OERAssignmentPolicy. A mock body written in
        # the test file runs in the test file's session state instead, where neither is visible.
        InModuleScope $script:moduleName {
            $script:OERTestBl11Live = @()
            $script:OERTestBl11Sent = [System.Collections.Generic.List[hashtable]]::new()
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Get-OERAccessPackage {
                [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false }
            }
            Mock Resolve-OERStructureDefault { $null }
            # The live policies are the REAL projection of the raw fixtures the test hands in.
            Mock Get-OERAccessPackageAssignmentPolicy {
                foreach ($Raw in @($script:OERTestBl11Live)) {
                    if ($null -ne $Raw) { ConvertTo-OERAssignmentPolicy -InputObject $Raw }
                }
            }
            # The transport: every PUT/POST is recorded with its body; a GET of a policy by id answers
            # with its raw fixture (the read-modify-write baseline of the real Set); anything else is an
            # empty page.
            Mock Invoke-OERGraphRequest {
                if ($Method -eq 'PUT' -or $Method -eq 'POST') {
                    $script:OERTestBl11Sent.Add(@{ Method = $Method; Uri = $Uri; Body = $Body })
                    return @{ id = '99999999-9999-9999-9999-999999999999'; displayName = $Body.displayName; allowedTargetScope = $Body.allowedTargetScope }
                }
                foreach ($Raw in @($script:OERTestBl11Live)) {
                    if ($null -ne $Raw -and $Uri -like "*entitlementManagement/assignmentPolicies/$($Raw.id)*") { return $Raw }
                }
                [PSCustomObject]@{ value = @() }
            }
        }
    }

    AfterEach {
        InModuleScope $script:moduleName {
            $script:OERTestBl11Live = $null
            $script:OERTestBl11Sent = $null
        }
    }

    Context 'a scope the builder now maps round-trips (R2)' {
        It 'reports an unchanged export of an <Graph> policy Unchanged and calls no Set or New (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ Graph = 'allExternalUsers'; Friendly = 'AllExternalUsers'; UseWhatIf = $false }
            @{ Graph = 'allExternalUsers'; Friendly = 'AllExternalUsers'; UseWhatIf = $true }
            @{ Graph = 'allDirectoryServicePrincipals'; Friendly = 'AllDirectoryServicePrincipals'; UseWhatIf = $false }
            @{ Graph = 'allDirectoryServicePrincipals'; Friendly = 'AllDirectoryServicePrincipals'; UseWhatIf = $true }
            @{ Graph = 'allDirectoryAgentIdentities'; Friendly = 'AllDirectoryAgentIdentities'; UseWhatIf = $false }
            @{ Graph = 'allDirectoryAgentIdentities'; Friendly = 'AllDirectoryAgentIdentities'; UseWhatIf = $true }
        ) {
            Mock -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy { }
            Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { }
            $Raw = New-Bl11RawPolicy -DisplayName 'Wide' -AllowedTargetScope $Graph
            # The entry Get-OERInventory exports for this policy: requestorScope.scope is the live
            # projection's friendly scope, and an empty users/groups list is left out.
            $Exported = InModuleScope $script:moduleName -Parameters @{ Raw = $Raw } {
                param($Raw)
                (ConvertTo-OERAssignmentPolicy -InputObject $Raw).RequestorScope.scope
            }
            $Exported | Should -BeExactly $Friendly
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Wide'
                        description    = 'live description'
                        requestorScope = [PSCustomObject]@{ scope = $Exported }
                    })
            }

            $Run = Invoke-Bl11Sync -Item $Item -Live @($Raw) -UseWhatIf $UseWhatIf

            # Positive proof: the policy reached the diff, which is the only place Unchanged comes from.
            @($Run.Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "assignmentPolicy 'Wide' matches" }).Count | Should -Be 1
            @($Run.Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count | Should -Be 0
            $Run.Published.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 0
            $Run.Sent.Count | Should -Be 0
        }
    }

    Context 'SpecificDirectoryServicePrincipals is refused by the builder (R3)' {
        It 'reports a declared SpecificDirectoryServicePrincipals Failed with InvalidPolicyInput and calls no Set or New (<Kind>, WhatIf: <UseWhatIf>)' -ForEach @(
            @{ Kind = 'unchanged export of a live policy'; HasLive = $true; UseWhatIf = $false }
            @{ Kind = 'unchanged export of a live policy'; HasLive = $true; UseWhatIf = $true }
            @{ Kind = 'policy to create'; HasLive = $false; UseWhatIf = $false }
            @{ Kind = 'policy to create'; HasLive = $false; UseWhatIf = $true }
        ) {
            Mock -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy { }
            Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { }
            $Live = if ($HasLive) {
                @(New-Bl11RawPolicy -DisplayName 'Agents' -AllowedTargetScope 'specificDirectoryServicePrincipals' -SpecificAllowedTargets @(
                        @{ '@odata.type' = '#microsoft.graph.singleServicePrincipal'; servicePrincipalId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
                    ))
            } else { @() }
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Agents", "description": "live description", "requestorScope": { "scope": "SpecificDirectoryServicePrincipals" } } ] }' |
                ConvertFrom-Json

            $Run = Invoke-Bl11Sync -Item $Item -Live $Live -UseWhatIf $UseWhatIf

            # Positive proof: the builder was reached and refused, and its record is on the row.
            $Failed = @($Run.Rows | Where-Object { $_.Action -eq 'Failed' })
            $Failed.Count | Should -Be 1
            $Failed[0].Detail | Should -BeLike "failed to build assignmentPolicy 'Agents': Requestor scope 'SpecificDirectoryServicePrincipals' needs specificAllowedTargets naming service principals*nothing was sent."
            $Failed[0].Error.FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput,*'
            $Failed[0].Error.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Failed[0].Error.TargetObject | Should -Be 'SpecificDirectoryServicePrincipals'
            # Exactly two records are published (measured, the same in all four cases): the builder's
            # own non-terminating InvalidPolicyInput record, written under the handler's -ErrorAction
            # Stop and caught, and the handler's re-publication of that error through the caller (its
            # id carries the caller's command name, not the builder's).
            @($Run.Published | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidPolicyInput,*' }).Count | Should -Be 2
            @($Run.Published | ForEach-Object { $_.FullyQualifiedErrorId }) | Should -Be @('InvalidPolicyInput,New-OERAccessPackageRequestorScope', 'InvalidPolicyInput,Invoke-SyncApViaCaller')
            # Refused before the diff and ShouldProcess: no Unchanged, Skipped, Updated or Created row for it.
            @($Run.Rows | Where-Object { $_.Detail -like "*assignmentPolicy 'Agents'*" -and $_.Action -ne 'Failed' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 0
            $Run.Sent.Count | Should -Be 0
        }
    }

    Context 'a live unknownFutureValue is refused (R4)' {
        It 'reports a live unknownFutureValue policy Failed and calls no Set or New, whatever the entry declares (<Declares>, WhatIf: <UseWhatIf>)' -ForEach @(
            @{ Declares = 'a changed description'; Policy = '{ "displayName": "Future", "description": "new description" }'; UseWhatIf = $false }
            @{ Declares = 'a changed description'; Policy = '{ "displayName": "Future", "description": "new description" }'; UseWhatIf = $true }
            @{ Declares = 'requestorScope AllMemberUsers'; Policy = '{ "displayName": "Future", "requestorScope": { "scope": "AllMemberUsers" } }'; UseWhatIf = $false }
            @{ Declares = 'requestorScope AllMemberUsers'; Policy = '{ "displayName": "Future", "requestorScope": { "scope": "AllMemberUsers" } }'; UseWhatIf = $true }
            @{ Declares = 'nothing but its name'; Policy = '{ "displayName": "Future" }'; UseWhatIf = $false }
        ) {
            Mock -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy { }
            Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { }
            $Raw = New-Bl11RawPolicy -DisplayName 'Future' -AllowedTargetScope 'unknownFutureValue'
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @($Policy | ConvertFrom-Json)
            }

            $Run = Invoke-Bl11Sync -Item $Item -Live @($Raw) -UseWhatIf $UseWhatIf

            # Positive proof: the live policy was read and the refusal row names it.
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            $Failed = @($Run.Rows | Where-Object { $_.Action -eq 'Failed' })
            $Failed.Count | Should -Be 1
            $Failed[0].Detail | Should -BeExactly ("Microsoft Graph returned allowedTargetScope 'unknownFutureValue', a value this module " +
                "cannot read without the 'Prefer: include-unknown-enum-members' header, so nothing was written for " +
                "assignmentPolicy 'Future'.")
            # A refusal without a Graph error: no record on the row, and none published.
            $Failed[0].Error | Should -BeNullOrEmpty
            $Run.Published.Count | Should -Be 0
            @($Run.Rows | Where-Object { $_.Detail -like "*assignmentPolicy 'Future'*" -and $_.Action -ne 'Failed' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 0
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 0
            $Run.Sent.Count | Should -Be 0
        }
    }

    Context 'SpecificConnectedOrganizationUsers on update (R5)' {
        It 'the real Set refuses a built SpecificConnectedOrganizationUsers scope with no target and sends nothing, and keeps the live target when -RequestorScope is omitted' {
            # The measurement that decided the engine guard below, kept at the cmdlet layer. Before
            # Sprint 9 step 5 (BL-50) the first Set call PUT the built scope: the builder has no
            # connected organization targets to give, and Set PUTs the declared scope whole, so the
            # live target was dropped. Now the cmdlet refuses that scope itself, so a direct caller is
            # protected too; the engine guard below stays as it was and still stops the apply path
            # before the cmdlet is ever called. With -RequestorScope omitted the live target is still
            # carried forward, which is the remedy the refusal names.
            $Raw = New-Bl11RawPolicy -AllowedTargetScope 'specificConnectedOrganizationUsers' -SpecificAllowedTargets @(New-Bl11ConnectedOrgTarget)
            InModuleScope $script:moduleName -Parameters @{ Raw = $Raw } { param($Raw) $script:OERTestBl11Live = @($Raw) }
            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers -ErrorAction Stop

            $Refused = $null
            Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' `
                -Description 'new description' -RequestorScope $Scope -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Refused | Out-Null
            $SentAfterRefusal = @(InModuleScope $script:moduleName { @($script:OERTestBl11Sent) })

            # Positive proof that the refusal was reached rather than a path that never ran: the cmdlet
            # read the live policy, once, and wrote its own InvalidPolicyInput record.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*entitlementManagement/assignmentPolicies/11111111-1111-1111-1111-111111111111*'
            }
            @($Refused).Count | Should -Be 1
            @($Refused)[0].FullyQualifiedErrorId | Should -Be 'InvalidPolicyInput,Set-OERAccessPackageAssignmentPolicy'
            @($Refused)[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $SentAfterRefusal.Count | Should -Be 0

            Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' `
                -Description 'new description' -Confirm:$false -ErrorAction Stop | Out-Null
            # Wrapped in @(): a single recorded request would otherwise arrive as the bare hashtable,
            # whose .Count is its number of keys.
            $Sent = @(InModuleScope $script:moduleName { @($script:OERTestBl11Sent) })

            $Sent.Count | Should -Be 1
            $Sent[0].Method | Should -Be 'PUT'
            $Sent[0].Body.allowedTargetScope | Should -BeExactly 'specificConnectedOrganizationUsers'
            @($Sent[0].Body.specificAllowedTargets).Count | Should -Be 1
            $Sent[0].Body.specificAllowedTargets[0].'@odata.type' | Should -Be '#microsoft.graph.connectedOrganizationMembers'
            $Sent[0].Body.specificAllowedTargets[0].connectedOrganizationId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        }

        It 'refuses an update that declares requestorScope SpecificConnectedOrganizationUsers before ShouldProcess, and sends nothing (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            $Raw = New-Bl11RawPolicy -AllowedTargetScope 'specificConnectedOrganizationUsers' -SpecificAllowedTargets @(New-Bl11ConnectedOrgTarget)
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Partners", "description": "new description", "requestorScope": { "scope": "SpecificConnectedOrganizationUsers" } } ] }' |
                ConvertFrom-Json

            $Run = Invoke-Bl11Sync -Item $Item -Live @($Raw) -UseWhatIf $UseWhatIf

            # Positive proof: the diff found the description change and the refusal row was written.
            $Failed = @($Run.Rows | Where-Object { $_.Action -eq 'Failed' })
            $Failed.Count | Should -Be 1
            $Failed[0].Detail | Should -BeExactly ("assignmentPolicy 'Partners' declares requestorScope SpecificConnectedOrganizationUsers, " +
                'but this module does not model connected organization targets, so the update would drop any ' +
                'the live policy names; nothing was written for it. Omit requestorScope from the entry to update ' +
                'the other fields while keeping the live scope.')
            $Failed[0].Error | Should -BeNullOrEmpty
            $Run.Published.Count | Should -Be 0
            # Before ShouldProcess: no "would update" Skipped row, and the real Set never ran (its
            # read-modify-write GET of the policy was never made, and nothing was PUT).
            @($Run.Rows | Where-Object { $_.Detail -like "*assignmentPolicy 'Partners'*" -and $_.Action -ne 'Failed' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Uri -like '*entitlementManagement/assignmentPolicies/11111111-1111-1111-1111-111111111111*'
            }
            $Run.Sent.Count | Should -Be 0
        }

        It 'updates the other fields and keeps the live connected organization target when requestorScope is omitted' {
            $Raw = New-Bl11RawPolicy -AllowedTargetScope 'specificConnectedOrganizationUsers' -SpecificAllowedTargets @(New-Bl11ConnectedOrgTarget)
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Partners", "description": "new description" } ] }' |
                ConvertFrom-Json

            $Run = Invoke-Bl11Sync -Item $Item -Live @($Raw)

            @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "updated assignmentPolicy 'Partners' (description)" }).Count | Should -Be 1
            @($Run.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            $Run.Sent.Count | Should -Be 1
            $Run.Sent[0].Method | Should -Be 'PUT'
            $Run.Sent[0].Body.description | Should -Be 'new description'
            $Run.Sent[0].Body.allowedTargetScope | Should -BeExactly 'specificConnectedOrganizationUsers'
            @($Run.Sent[0].Body.specificAllowedTargets).Count | Should -Be 1
            $Run.Sent[0].Body.specificAllowedTargets[0].connectedOrganizationId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        }

        It 'reports a declared SpecificConnectedOrganizationUsers that does not differ Unchanged and sends nothing (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            $Raw = New-Bl11RawPolicy -AllowedTargetScope 'specificConnectedOrganizationUsers' -SpecificAllowedTargets @(New-Bl11ConnectedOrgTarget)
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Partners", "description": "live description", "requestorScope": { "scope": "SpecificConnectedOrganizationUsers" } } ] }' |
                ConvertFrom-Json

            $Run = Invoke-Bl11Sync -Item $Item -Live @($Raw) -UseWhatIf $UseWhatIf

            @($Run.Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "assignmentPolicy 'Partners' matches" }).Count | Should -Be 1
            @($Run.Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count | Should -Be 0
            $Run.Published.Count | Should -Be 0
            $Run.Sent.Count | Should -Be 0
        }

        It 'creates a policy declaring SpecificConnectedOrganizationUsers, since there is no live target to lose' {
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "Partners", "requestorScope": { "scope": "SpecificConnectedOrganizationUsers" } } ] }' |
                ConvertFrom-Json

            $Run = Invoke-Bl11Sync -Item $Item -Live @()

            @($Run.Rows | Where-Object { $_.Action -eq 'Created' -and $_.Detail -eq "created assignmentPolicy 'Partners'" }).Count | Should -Be 1
            @($Run.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            $Run.Sent.Count | Should -Be 1
            $Run.Sent[0].Method | Should -Be 'POST'
            $Run.Sent[0].Body.allowedTargetScope | Should -BeExactly 'specificConnectedOrganizationUsers'
        }
    }
}

Describe 'Sync-OERStructureAccessPackage -PlannedCatalog' {
    Context 'a package in a catalog the same -WhatIf plan creates (BL-128, A5)' {
        # Under -WhatIf the catalogs handler has not created the catalog the document declares, so the
        # catalog-scoped package lookup would fail with CatalogNotFound and report the package Failed
        # ("NOT created") while the real run creates both. The engine passes the catalogs the plan
        # would create as -PlannedCatalog; only a name in it is trusted, and a catalog the document
        # does not declare, and that does not exist, still fails.

        It 'plans the package and each declared child as created without reading the catalog (catalog <Declared>, planned <Planned>)' -ForEach @(
            @{ Declared = 'cat-new'; Planned = 'cat-new' }
            @{ Declared = 'CAT-NEW'; Planned = 'cat-new' }
            @{ Declared = 'cat-new'; Planned = 'CAT-NEW' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Declared = $Declared; Planned = $Planned } {
                param($Declared, $Planned)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap-new' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $PlannedList = [System.Collections.Generic.List[string]]::new()
                $PlannedList.Add($Planned)
                $Item = [PSCustomObject]@{
                    displayName        = 'ap-new'
                    catalog            = $Declared
                    resourceRoles      = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' }, [PSCustomObject]@{ displayName = 'Partners' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -PlannedCatalog $PlannedList -WhatIf)

                # The catalog is not read, and nothing is sent or created.
                Should -Invoke Get-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create access package ap-new' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would configure resourceRole 'role_sec_x' after access package is created" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would create assignmentPolicy 'Default' after access package is created" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would create assignmentPolicy 'Partners' after access package is created" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                $r.Count | Should -Be 4
            }
        }

        It 'still fails the package with NOT created when the list is <Case> and the catalog lookup finds no catalog' -ForEach @(
            @{ Case = 'empty'; Mode = 'Empty' }
            @{ Case = 'not passed'; Mode = 'Null' }
            @{ Case = 'holding another catalog only'; Mode = 'Other' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Mode = $Mode } {
                param($Mode)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERAccessPackageId { $null }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap-new' } }
                # A cmdlet failure mock: the handler reads with -ErrorAction Stop, and only the
                # cmdlet's own WriteError is promoted by it.
                Mock Get-OERAccessPackage {
                    [CmdletBinding()] param([string]$Catalog)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Catalog '$Catalog' not found."),
                            'CatalogNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Catalog))
                }
                # Built with plain assignments: a switch or a pipeline would enumerate the list away.
                $PlannedList = $null
                if ($Mode -ne 'Null') { $PlannedList = [System.Collections.Generic.List[string]]::new() }
                if ($Mode -eq 'Other') { $PlannedList.Add('some-other-catalog') }
                $Item = [PSCustomObject]@{
                    displayName        = 'ap-new'
                    catalog            = 'cat-new'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -PlannedCatalog $PlannedList -WhatIf -ErrorAction SilentlyContinue)

                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke New-OERAccessPackage -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match "failed to look up access packages in catalog 'cat-new'"
                $Failed[0].Detail | Should -Match 'CatalogNotFound|not found'
                $Failed[0].Detail | Should -Match 'NOT created'
                @($r | Where-Object { $_.Detail -match 'would create' }).Count | Should -Be 0
            }
        }
    }
}

Describe 'Sync-OERStructureAccessPackage -previousDisplayName and the rename map (BL-128, A5)' {
    # previousDisplayName renames a package in place, within its declared catalog: both names are
    # matched in the catalog's own package list (an object id by the Id of a package in that list,
    # never by a probe), and Resolve-OERStructureRename decides. A catalog the same run renames is
    # addressed through the run's rename map (Get-OERStructureRenameTarget): by the id the catalogs
    # handler registered for it, or not at all when that rename was refused.

    Context 'renaming an access package in place, within its declared catalog' {

        It 'renames the package found under its previous name in one Set-OERAccessPackage call and reconciles its children by that id (description <Desc>)' -ForEach @(
            @{ Desc = 'same'; Expected = "renamed access package 'AP-Old' to 'AP-New'"; SendsDescription = $false }
            @{ Desc = 'new desc'; Expected = "renamed access package 'AP-Old' to 'AP-New'; updated access package properties (Description)"; SendsDescription = $true }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Desc = $Desc; Expected = $Expected; SendsDescription = $SendsDescription } {
                param($Desc, $Expected, $SendsDescription)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old'; Description = 'same'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT'; description = $Desc }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'accessPackages'
                $r[0].Item | Should -BeExactly 'AP-New'
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly $Expected
                @($Err).Count | Should -Be 0

                # One call carries the rename and every other changed property, by the id found under
                # the previous name; nothing is created.
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-old' -and $NewDisplayName -eq 'AP-New' }
                if ($SendsDescription) {
                    Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Description -eq 'new desc' }
                } else {
                    Should -Invoke Set-OERAccessPackage -Times 0 -ParameterFilter { -not [string]::IsNullOrEmpty($Description) }
                }
                Should -Invoke New-OERAccessPackage -Times 0

                # The children are read by the renamed package's id.
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-old' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/accessPackages/ap-old/resourceRoleScopes*' }
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-old' }
            }
        }

        It 'reports Unchanged and renames nothing when the package already carries the new name (the second run)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-New' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-New'; Description = 'same'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT'; description = 'same' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'access package properties match'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-old' }
            }
        }

        It 'fails the item with one row and an AccessPackageRenameConflict error, reading and writing nothing further, when both names are different packages of the catalog' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage {
                    @(
                        [PSCustomObject]@{ Id = 'ap-new'; DisplayName = 'AP-New' }
                        [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }
                    )
                } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = $Id; DisplayName = 'AP-New'; Description = 'old'; IsHidden = $false } } -ParameterFilter { -not [string]::IsNullOrEmpty($Id) }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                # A changed property and both collections are declared, so a missing guard has
                # something to read, reconcile and write.
                $Item = [PSCustomObject]@{
                    displayName         = 'AP-New'
                    previousDisplayName = 'AP-Old'
                    catalog             = 'CAT'
                    description         = 'new'
                    resourceRoles       = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies  = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'accessPackages'
                $r[0].Item | Should -BeExactly 'AP-New'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "both 'AP-New' and its previousDisplayName 'AP-Old' exist in catalog 'CAT' as different access packages; the document never merges two access packages, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AccessPackageRenameConflict'

                @($Err).Count | Should -Be 1
                $Conflict = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessPackageRenameConflict*' })
                $Conflict.Count | Should -Be 1
                $Conflict[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
                $Conflict[0].TargetObject | Should -BeExactly 'AP-New'
                $Conflict[0].Exception.Message | Should -Match "in catalog 'CAT'"

                # Only the catalog's package list was read.
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'fails with AccessPackageRenameNotFound and creates nothing when neither name is in the catalog (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            InModuleScope $script:moduleName -Parameters @{ UseWhatIf = $UseWhatIf } {
                param($UseWhatIf)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-other'; DisplayName = 'Other' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-created'; DisplayName = 'AP-New' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{
                    displayName         = 'AP-New'
                    previousDisplayName = 'AP-Old'
                    catalog             = 'CAT'
                    assignmentPolicies  = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf:$UseWhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'AP-New' nor its previousDisplayName 'AP-Old' matches an access package in catalog 'CAT', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access package, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AccessPackageRenameNotFound'
                @($r | Where-Object { $_.Detail -match 'would create' }).Count | Should -Be 0

                @($Err).Count | Should -Be 1
                $NotFound = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessPackageRenameNotFound*' })
                $NotFound.Count | Should -Be 1
                $NotFound[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $NotFound[0].TargetObject | Should -BeExactly 'AP-New'

                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'renames the package whose Id in the catalog list is the object id previousDisplayName names, with no request of its own' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'AP-Old'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq '11111111-1111-1111-1111-111111111111' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed access package '11111111-1111-1111-1111-111111111111' to 'AP-New'"
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq '11111111-1111-1111-1111-111111111111' -and $NewDisplayName -eq 'AP-New' }
                Should -Invoke New-OERAccessPackage -Times 0
                # R5: the id is matched in the list already read, never probed or resolved tenant-wide.
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/accessPackages/11111111-1111-1111-1111-111111111111/resourceRoleScopes*' }
            }
        }

        It 'matches an object id in previousDisplayName without regard to letter case and acts on the id the list carries' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; DisplayName = 'AP-Old'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -ceq 'aaaaaaaa-0000-0000-0000-000000000001' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AAAAAAAA-0000-0000-0000-000000000001'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed access package 'AAAAAAAA-0000-0000-0000-000000000001' to 'AP-New'"
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -ceq 'aaaaaaaa-0000-0000-0000-000000000001' -and $NewDisplayName -eq 'AP-New' }
                Should -Invoke Resolve-OERAccessPackageId -Times 0
            }
        }

        It 'fails with AccessPackageRenameNotFound when the object id previousDisplayName names is not a package of the declared catalog (R5)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # A package of another catalog, or a deleted one: the id is not in this catalog's list.
                Mock Resolve-OERAccessPackageId { '11111111-1111-1111-1111-111111111111' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-x'; DisplayName = 'AP-X' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'AP-Old' } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AccessPackageRenameNotFound'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessPackageRenameNotFound*' }).Count | Should -Be 1
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'applies the entry normally, with no conflict and no rename, when a stale object id in previousDisplayName is not in the list and displayName is' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # A deleted package, or one of another catalog: the stale id must never be resolved
                # or probed into a second package and read as a conflict.
                Mock Resolve-OERAccessPackageId { '11111111-1111-1111-1111-111111111111' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-new'; DisplayName = 'AP-New' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-new'; DisplayName = 'AP-New'; Description = 'same'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-new' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; catalog = 'CAT'; description = 'same' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'access package properties match'
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                # The children are reconciled by the package found under displayName.
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-new' }
            }
        }

        It 'applies the entry normally when the object id previousDisplayName names is the package that carries displayName' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'AP-New' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'AP-New'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq '11111111-1111-1111-1111-111111111111' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'access package properties match'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'refuses a previous name several packages of the catalog carry, naming every id and writing nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage {
                    @(
                        [PSCustomObject]@{ Id = 'ap-old-1'; DisplayName = 'AP-Old' }
                        [PSCustomObject]@{ Id = 'ap-old-2'; DisplayName = 'ap-old' }
                    )
                } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = $Id; DisplayName = 'AP-Old'; Description = $null; IsHidden = $false } } -ParameterFilter { -not [string]::IsNullOrEmpty($Id) }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT'; description = 'new' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "catalog 'CAT' holds 2 access packages named 'AP-Old' (ap-old-1, ap-old-2), the previousDisplayName of this entry; the name cannot identify one -- declare previousDisplayName as the object id of the package to rename"
                # The same shape as an ambiguous displayName: a row, no new published id.
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'keeps the displayName duplicate row exactly as it is when the entry also declares previousDisplayName' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage {
                    @(
                        [PSCustomObject]@{ Id = 'ap-new-1'; DisplayName = 'AP-New' }
                        [PSCustomObject]@{ Id = 'ap-new-2'; DisplayName = 'AP-New' }
                        [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }
                    )
                } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "catalog 'CAT' holds 2 access packages named 'AP-New' (ap-new-1, ap-new-2); the display name cannot identify one"
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'plans the rename under -WhatIf and plans the children against the package found under its previous name (description <Desc>)' -ForEach @(
            @{ Desc = 'same'; Expected = "would rename access package 'AP-Old' to 'AP-New'" }
            @{ Desc = 'new desc'; Expected = "would rename access package 'AP-Old' to 'AP-New'; would update access package properties (Description)" }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Desc = $Desc; Expected = $Expected } {
                param($Desc, $Expected)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old'; Description = 'same'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                $Item = [PSCustomObject]@{
                    displayName         = 'AP-New'
                    previousDisplayName = 'AP-Old'
                    catalog             = 'CAT'
                    description         = $Desc
                    resourceRoles       = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 2
                $r[0].Action | Should -BeExactly 'Skipped'
                $r[0].Detail | Should -BeExactly $Expected
                $r[1].Action | Should -BeExactly 'Skipped'
                $r[1].Detail | Should -BeExactly "would add resourceRole 'Member' on 'role_sec_x'"
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/accessPackages/ap-old/resourceRoleScopes*' }
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-old' }
            }
        }

        It 'stops the item at a failed rename: the Failed row is the last one and no child is read or written (R8)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old'; Description = 'same'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { throw 'Graph rejected the update' }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock New-OERAccessPackageAssignmentPolicy { }
                $Item = [PSCustomObject]@{
                    displayName         = 'AP-New'
                    previousDisplayName = 'AP-Old'
                    catalog             = 'CAT'
                    resourceRoles       = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies  = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[-1].Action | Should -BeExactly 'Failed'
                $r[-1].Detail | Should -BeExactly 'access package update failed: Graph rejected the update'
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-old' -and $NewDisplayName -eq 'AP-New' }
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
                Should -Invoke New-OERAccessPackageAssignmentPolicy -Times 0
            }
        }

        It 'treats a previous name that differs from displayName only in letter case as the same package: no rename and no failure' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap-new' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'ap-new'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-1' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'ap-new'; catalog = 'CAT' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'access package properties match'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'resolves previousDisplayName tenant-wide beside displayName when the entry declares no catalog (the private entry point)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { $null } -ParameterFilter { $DisplayName -eq 'AP-New' }
                Mock Resolve-OERAccessPackageId { 'ap-old' } -ParameterFilter { $DisplayName -eq 'AP-Old' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed access package 'AP-Old' to 'AP-New'"
                @($Err).Count | Should -Be 0
                Should -Invoke Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-Old' }
                Should -Invoke Set-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Id -eq 'ap-old' -and $NewDisplayName -eq 'AP-New' }
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'fails the item with nothing created or renamed when the tenant-wide lookup of previousDisplayName throws (no catalog declared)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { $null } -ParameterFilter { $DisplayName -eq 'AP-New' }
                Mock Resolve-OERAccessPackageId { throw 'no access package has the id 11111111-1111-1111-1111-111111111111' } -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                Mock Get-OERAccessPackage { }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "failed to resolve access package 'AP-New': no access package has the id 11111111-1111-1111-1111-111111111111; the access package was NOT created"
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke Get-OERAccessPackage -Times 0
            }
        }

        It 'still reconciles the children after a failed property update that renames nothing (control)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' }) } -ParameterFilter { $Catalog -eq 'CAT' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = 'old'; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-1' }
                Mock Set-OERAccessPackage { throw 'Graph rejected the update' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Item = [PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT'; description = 'new' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly 'access package update failed: Graph rejected the update'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/accessPackages/ap-1/resourceRoleScopes*' }
                Should -Invoke Get-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $AccessPackage -eq 'ap-1' }
            }
        }
    }

    Context 'a catalog the same run renames, read through the rename map' {

        It 'addresses the catalog by the id the map holds in every call that names it, and creates the package there' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' } }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'cat-old-id' -RenameMap $Map
                $Item = [PSCustomObject]@{
                    displayName   = 'AP'
                    catalog       = 'CAT-New'
                    resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 2
                $r[0].Action | Should -BeExactly 'Created'
                $r[0].Detail | Should -BeExactly 'created access package AP (ap-1)'
                $r[1].Action | Should -BeExactly 'Created'
                $r[1].Detail | Should -BeExactly "added resourceRole 'Member' on 'role_sec_x'"
                @($Err).Count | Should -Be 0

                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Should -Invoke Get-OERAccessPackage -Times 0 -ParameterFilter { $Catalog -eq 'CAT-New' }
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' -and $DisplayName -eq 'AP' }
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' -and $AccessPackage -eq 'ap-1' -and $ResourceOriginId -eq 'grp-1' }
            }
        }

        It 'names the catalog as the document does in a row about a failed package list read' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Get-OERAccessPackage { throw 'transient Graph failure' }
                Mock New-OERAccessPackage { }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'cat-old-id' -RenameMap $Map
                $Item = [PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT-New' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "failed to look up access packages in catalog 'CAT-New': transient Graph failure; the access package was NOT created"
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'names the catalog as the document does in a row about a resource the renamed catalog does not hold' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' }) } -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-1' }
                Mock Get-OERCatalogResource { @() }
                Mock Resolve-OERGroupId { $null }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'cat-old-id' -RenameMap $Map
                $Item = [PSCustomObject]@{
                    displayName   = 'AP'
                    catalog       = 'CAT-New'
                    resourceRoles = @([PSCustomObject]@{ resource = 'nope'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue)

                @($r).Count | Should -Be 2
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[1].Action | Should -BeExactly 'Failed'
                $r[1].Detail | Should -BeExactly "could not resolve resource 'nope' to an origin id in catalog 'CAT-New'"
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 0
            }
        }

        It 'plans a rename of the package inside a catalog the same -WhatIf plan renames, with no Failed row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }) } -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Mock Get-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old'; Description = $null; IsHidden = $false } } -ParameterFilter { $Id -eq 'ap-old' }
                Mock Set-OERAccessPackage { }
                Mock New-OERAccessPackage { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId 'cat-old-id' -RenameMap $Map
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT-New' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Skipped'
                $r[0].Detail | Should -BeExactly "would rename access package 'AP-Old' to 'AP-New'"
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'fails a package in a catalog whose rename was refused (<ErrorId>, WhatIf: <UseWhatIf>, previousDisplayName: <WithPrev>), reading and writing nothing for it' -ForEach @(
            @{ ErrorId = 'CatalogRenameConflict'; UseWhatIf = $false; WithPrev = $false }
            @{ ErrorId = 'CatalogRenameConflict'; UseWhatIf = $true; WithPrev = $false }
            @{ ErrorId = 'CatalogRenameNotFound'; UseWhatIf = $false; WithPrev = $false }
            @{ ErrorId = 'CatalogRenameNotFound'; UseWhatIf = $true; WithPrev = $true }
        ) {
            InModuleScope $script:moduleName -Parameters @{ ErrorId = $ErrorId; UseWhatIf = $UseWhatIf; WithPrev = $WithPrev } {
                param($ErrorId, $UseWhatIf, $WithPrev)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { 'ap-elsewhere' }
                # Another catalog now carries the new name: the package must not land there.
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' } }
                Mock Set-OERAccessPackage { }
                Mock Get-OERCatalogResource { @() }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($ErrorId -eq 'CatalogRenameConflict') {
                    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id 'cat-new-id' -PreviousId 'cat-old-id' -RenameMap $Map
                } else {
                    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Id $null -PreviousId $null -RenameMap $Map
                }
                $Item = [PSCustomObject]@{
                    displayName   = 'AP'
                    catalog       = 'CAT-New'
                    description   = 'new'
                    resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                if ($WithPrev) { $Item | Add-Member -NotePropertyName previousDisplayName -NotePropertyValue 'AP-Old' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -WhatIf:$UseWhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'accessPackages'
                $r[0].Item | Should -BeExactly 'AP'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused ($ErrorId), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it"
                # R9: the catalog's own row carries the refusal; this row publishes no record.
                $r[0].Error | Should -BeNullOrEmpty
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 0
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Set-OERAccessPackage -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'fails a package in a catalog whose rename this run could not decide, naming why, reading and writing nothing for it (R12, WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            InModuleScope $script:moduleName -Parameters @{ UseWhatIf = $UseWhatIf } {
                param($UseWhatIf)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { 'ap-elsewhere' }
                # Another catalog may carry the new name: the package must not land there.
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' } }
                Mock Get-OERCatalogResource { @() }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Undecided `
                    -Reason 'its previous name could not be looked up' -RenameMap $Map
                $Item = [PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT-New'; resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' }) }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -WhatIf:$UseWhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly ("catalog 'CAT-New' was not reconciled in this run: its rename from 'CAT-Old' was refused (its previous name could not be looked up), " +
                    'so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it')
                $r[0].Error | Should -BeNullOrEmpty
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 0
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'fails a package that declares previousDisplayName in a catalog the same plan creates with AccessPackageRenameNotFound, planning no create' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-New' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $PlannedList = [System.Collections.Generic.List[string]]::new()
                $PlannedList.Add('cat-new')
                $Item = [PSCustomObject]@{
                    displayName         = 'AP-New'
                    previousDisplayName = 'AP-Old'
                    catalog             = 'cat-new'
                    resourceRoles       = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                    assignmentPolicies  = @([PSCustomObject]@{ displayName = 'Default' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -PlannedCatalog $PlannedList -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'AP-New' nor its previousDisplayName 'AP-Old' matches an access package in catalog 'cat-new', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access package, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AccessPackageRenameNotFound'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessPackageRenameNotFound*' }).Count | Should -Be 1
                @($r | Where-Object { $_.Detail -match 'would create' }).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 0
                Should -Invoke Resolve-OERAccessPackageId -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'still plans a package without previousDisplayName in a catalog the same plan creates as created (control)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { $null }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP-New' } }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                $PlannedList = [System.Collections.Generic.List[string]]::new()
                $PlannedList.Add('cat-new')
                $Item = [PSCustomObject]@{ displayName = 'AP-New'; catalog = 'cat-new' }
                $r = @(Invoke-SyncApViaCaller -Item $Item -PlannedCatalog $PlannedList -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Skipped'
                $r[0].Detail | Should -BeExactly 'would create access package AP-New'
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 0
                Should -Invoke New-OERAccessPackage -Times 0
            }
        }

        It 'makes exactly the calls it always made for a package without previousDisplayName whose catalog the map does not hold (map: <MapCase>)' -ForEach @(
            @{ MapCase = 'not passed' }
            @{ MapCase = 'holding another catalog' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ MapCase = $MapCase } {
                param($MapCase)
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
                Mock Get-OERAccessPackage { @() }
                Mock New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' } }
                Mock Get-OERCatalogResource { [PSCustomObject]@{ DisplayName = 'role_sec_x'; OriginId = 'grp-1'; Id = 'res-1' } }
                Mock Resolve-OERGroupId { 'grp-1' }
                Mock Add-OERAccessPackageResourceRole { }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ value = @() } }
                Mock Get-OERAccessPackageAssignmentPolicy { @() }
                $Map = $null
                if ($MapCase -ne 'not passed') {
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-Other' -PreviousName 'CAT-Older' -Id $null -PreviousId 'cat-other-id' -RenameMap $Map
                }
                $Item = [PSCustomObject]@{
                    displayName   = 'AP'
                    catalog       = 'CAT'
                    resourceRoles = @([PSCustomObject]@{ resource = 'role_sec_x'; role = 'Member' })
                }
                $r = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 2
                $r[0].Detail | Should -BeExactly 'created access package AP (ap-1)'
                $r[1].Detail | Should -BeExactly "added resourceRole 'Member' on 'role_sec_x'"
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly
                Should -Invoke Get-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT' }
                Should -Invoke New-OERAccessPackage -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT' }
                Should -Invoke Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT' }
                Should -Invoke Add-OERAccessPackageResourceRole -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'CAT' -and $AccessPackage -eq 'ap-1' }
            }
        }
    }
}

Describe 'Sync-OERStructureAccessPackage -- assignment policies renamed through previousDisplayName, and the rename map (BL-128 part 2)' {
    # An assignmentPolicies entry that declares previousDisplayName renames the policy found under that
    # name in its package's policy list (an object id only by the Id of a policy in that list), in the
    # one Set-OERAccessPackageAssignmentPolicy call that carries every declared field. Both names are
    # matched before anything is built or written, and Resolve-OERStructureRename decides. The handler
    # also fills the run's rename map: undecided marks first, for the package and for every policy that
    # declares previousDisplayName, then each decision in place of its mark.
    # Set-OERAccessPackageAssignmentPolicy runs for real here unless an It mocks it: the transport below
    # answers a GET of a policy by id with its raw fixture and records every PUT and POST.
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"

        # A live policy as Microsoft Graph returns it: a plain request-based policy.
        function New-PolRaw {
            param(
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$DisplayName,
                [string]$Description = 'live description'
            )
            @{
                id                      = $Id
                displayName             = $DisplayName
                description             = $Description
                accessPackage           = @{ id = 'ap-1' }
                allowedTargetScope      = 'allMemberUsers'
                specificAllowedTargets  = @()
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $false
                    isApprovalRequiredForUpdate      = $false
                    isRequestorJustificationRequired = $false
                    stages                           = @()
                }
                notificationSettings    = @{ isAssignmentNotificationDisabled = $false }
            }
        }

        function New-PolMap {
            [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        # Runs the handler for one item against the given packages of catalog 'CAT' and raw live
        # policies, and returns the rows, the error records it published, and every PUT/POST sent.
        function Invoke-PolSync {
            param(
                [PSCustomObject]$Item,
                [object[]]$Live = @(),
                [object[]]$Packages = @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' }),
                [bool]$UseWhatIf = $false,
                $RenameMap = $null,
                [string]$PackageListError
            )
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Item = $Item; Live = $Live; Packages = $Packages; UseWhatIf = $UseWhatIf; RenameMap = $RenameMap; PackageListError = $PackageListError } {
                param($Item, $Live, $Packages, $UseWhatIf, $RenameMap, $PackageListError)
                $script:OERTestPolLive = @($Live)
                $script:OERTestPolPackages = @($Packages)
                $script:OERTestPolPackageListError = $PackageListError
                function Invoke-SyncApViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                $Published = $null
                $Rows = @(Invoke-SyncApViaCaller -Item $Item -RenameMap $RenameMap -WhatIf:$UseWhatIf -WarningAction SilentlyContinue `
                        -ErrorAction SilentlyContinue -ErrorVariable Published)
                [PSCustomObject]@{
                    Rows      = $Rows
                    Published = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                    Sent      = @($script:OERTestPolSent)
                }
            }
        }

        # Registers a refused rename of catalog 'CAT' in the map, as the catalogs handler would.
        function Register-PolRefusedCatalog {
            param($RenameMap)
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ RenameMap = $RenameMap } {
                param($RenameMap)
                $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT' -PreviousName 'CAT-Old' -Id $null -PreviousId $null -RenameMap $RenameMap
            }
        }

        $script:PolUndecided = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
        $script:PolNotFoundDetail = "assignmentPolicy 'POL-New': neither 'POL-New' nor its previousDisplayName 'POL-Old' matches an assignment policy in access package 'AP', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new assignment policy, remove previousDisplayName"
        $script:PolGetFilter = { (-not $Method -or $Method -eq 'GET') -and $Uri -like '*entitlementManagement/assignmentPolicies/*' }
    }

    BeforeEach {
        # Defined inside the module's scope so each mock body runs there and reads the module-scoped
        # fixtures (and calls the private ConvertTo-OERAssignmentPolicy).
        InModuleScope $script:moduleName {
            $script:OERTestPolLive = @()
            $script:OERTestPolPackages = @()
            $script:OERTestPolPackageListError = $null
            $script:OERTestPolSent = [System.Collections.Generic.List[hashtable]]::new()
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERAccessPackageId { throw 'tenant-wide resolve must not be used when a catalog is declared' }
            # The catalog's package list (or its failure), and a package read by its id.
            Mock Get-OERAccessPackage {
                if ($Catalog) {
                    if ($script:OERTestPolPackageListError) { throw $script:OERTestPolPackageListError }
                    return @($script:OERTestPolPackages)
                }
                foreach ($Package in @($script:OERTestPolPackages)) {
                    if ([string]$Package.Id -eq $Id) {
                        return [PSCustomObject]@{ Id = $Package.Id; DisplayName = $Package.DisplayName; Description = $null; IsHidden = $false }
                    }
                }
            }
            # The live policies are the REAL projection of the raw fixtures the test hands in.
            Mock Get-OERAccessPackageAssignmentPolicy {
                foreach ($Raw in @($script:OERTestPolLive)) {
                    if ($null -ne $Raw) { ConvertTo-OERAssignmentPolicy -InputObject $Raw }
                }
            }
            Mock Invoke-OERGraphRequest {
                if ($Method -eq 'PUT' -or $Method -eq 'POST') {
                    $script:OERTestPolSent.Add(@{ Method = $Method; Uri = $Uri; Body = $Body })
                    return @{ id = [string]$Body.id; displayName = $Body.displayName; allowedTargetScope = $Body.allowedTargetScope }
                }
                $Path = ($Uri -split '\?')[0]
                foreach ($Raw in @($script:OERTestPolLive)) {
                    if ($null -ne $Raw -and $Path -like "*/entitlementManagement/assignmentPolicies/$($Raw.id)") { return $Raw }
                }
                [PSCustomObject]@{ value = @() }
            }
        }
    }

    AfterEach {
        InModuleScope $script:moduleName {
            $script:OERTestPolLive = $null
            $script:OERTestPolPackages = $null
            $script:OERTestPolPackageListError = $null
            $script:OERTestPolSent = $null
        }
    }

    Context 'renaming an assignment policy in place, within its package' {

        It 'renames the policy found under its previous name in one call carrying every declared field (description <Desc>)' -ForEach @(
            @{ Desc = 'same'; Expected = "renamed assignmentPolicy 'POL-Old' to 'POL-New'" }
            @{ Desc = 'new desc'; Expected = "renamed assignmentPolicy 'POL-Old' to 'POL-New'; updated assignmentPolicy fields (description)" }
        ) {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = $Desc })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old' -Description 'same')

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[0].Detail | Should -BeExactly 'access package properties match'
            $Run.Rows[1].Section | Should -BeExactly 'accessPackages'
            $Run.Rows[1].Item | Should -BeExactly 'AP'
            $Run.Rows[1].Action | Should -BeExactly 'Updated'
            $Run.Rows[1].Detail | Should -BeExactly $Expected
            $Run.Published.Count | Should -Be 0
            # One read of the policy by the real Set, and one PUT of the policy found under its
            # previous name: the new name and the declared description travel together. A rename with
            # no other difference still sends it.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter $script:PolGetFilter
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -like '*/assignmentPolicies/pol-old?*'
            }
            $Run.Sent.Count | Should -Be 1
            $Run.Sent[0].Method | Should -Be 'PUT'
            $Run.Sent[0].Uri | Should -BeLike '*/entitlementManagement/assignmentPolicies/pol-old'
            $Run.Sent[0].Body.id | Should -BeExactly 'pol-old'
            $Run.Sent[0].Body.displayName | Should -BeExactly 'POL-New'
            $Run.Sent[0].Body.description | Should -BeExactly $Desc
        }

        It 'renames with -DisplayName alone through the real Set: one GET, one PUT carrying the new name, the live custom extension stages and automatic assignment settings, and no NothingToUpdate' {
            $Raw = @{
                id                           = 'pol-auto'
                displayName                  = 'POL-Old'
                description                  = 'live description'
                accessPackage                = @{ id = 'ap-1' }
                allowedTargetScope           = 'specificDirectoryUsers'
                specificAllowedTargets       = @(@{ '@odata.type' = '#microsoft.graph.attributeRuleMembers'; description = 'rule'; membershipRule = '(user.department -eq "x")' })
                automaticRequestSettings     = @{
                    requestAccessForAllowedTargets             = $true
                    removeAccessWhenTargetLeavesAllowedTargets = $true
                    gracePeriodBeforeAccessRemoval             = 'P7D'
                }
                expiration                   = @{ type = 'noExpiration' }
                customExtensionStageSettings = @(@{
                        id              = 'aaaaaaaa-0000-0000-0000-000000000072'
                        stage           = 'assignmentRequestCreated'
                        customExtension = @{
                            '@odata.type'         = '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension'
                            id                    = 'aaaaaaaa-0000-0000-0000-000000000073'
                            displayName           = 'ext'
                            endpointConfiguration = @{ url = 'https://example.invalid/x' }
                        }
                    })
            }
            # The entry declares nothing but the two names, so the Set call carries -Id and -DisplayName
            # only: A16 is what makes it a rename instead of NothingToUpdate.
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @($Raw)

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Updated'
            $Run.Rows[1].Detail | Should -BeExactly "renamed assignmentPolicy 'POL-Old' to 'POL-New'"
            $Run.Published.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter $script:PolGetFilter
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and
                $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-auto?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
            $Run.Sent.Count | Should -Be 1
            $Body = $Run.Sent[0].Body
            $Run.Sent[0].Uri | Should -BeExactly 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-auto'
            $Body.id | Should -BeExactly 'pol-auto'
            $Body.displayName | Should -BeExactly 'POL-New'
            $Body.description | Should -BeExactly 'live description'
            $Body.accessPackage.id | Should -BeExactly 'ap-1'
            @($Body.customExtensionStageSettings).Count | Should -Be 1
            $Body.customExtensionStageSettings[0].stage | Should -BeExactly 'assignmentRequestCreated'
            $Body.customExtensionStageSettings[0].customExtension.id | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000073'
            $Body.customExtensionStageSettings[0].customExtension['@odata.type'] | Should -BeExactly '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension'
            $Body.allowedTargetScope | Should -BeExactly 'specificDirectoryUsers'
            @($Body.specificAllowedTargets).Count | Should -Be 1
            $Body.automaticRequestSettings.requestAccessForAllowedTargets | Should -BeTrue
            $Body.automaticRequestSettings.removeAccessWhenTargetLeavesAllowedTargets | Should -BeTrue
            $Body.automaticRequestSettings.gracePeriodBeforeAccessRemoval | Should -BeExactly 'P7D'
        }

        It 'reports Unchanged and sends nothing when the policy already carries the new name (the second run)' {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = 'same' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-New' -Description 'same')

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Unchanged'
            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'POL-New' matches"
            $Run.Published.Count | Should -Be 0
            $Run.Sent.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
        }

        It 'fails the policy with one row and an AssignmentPolicyRenameConflict error when both names are different policies, and carries on with the next policy (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            # A changed description is declared, so a missing guard has something to write.
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = 'changed' }
                    [PSCustomObject]@{ displayName = 'Other' }
                )
            }
            $Live = @(
                New-PolRaw -Id 'pol-new' -DisplayName 'POL-New'
                New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old'
                New-PolRaw -Id 'pol-other' -DisplayName 'Other'
            )

            $Run = Invoke-PolSync -Item $Item -Live $Live -UseWhatIf $UseWhatIf

            # The conflict row, then the next policy: no Extra row for the policy the previous name names.
            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Section | Should -BeExactly 'accessPackages'
            $Run.Rows[1].Item | Should -BeExactly 'AP'
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'POL-New': both 'POL-New' and its previousDisplayName 'POL-Old' exist in access package 'AP' as different assignment policies; the document never merges two assignment policies, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
            $Run.Rows[1].Error.FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameConflict'
            $Run.Rows[2].Action | Should -BeExactly 'Unchanged'
            $Run.Rows[2].Detail | Should -BeExactly "assignmentPolicy 'Other' matches"

            $Run.Published.Count | Should -Be 1
            $Run.Published[0].FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameConflict'
            $Run.Published[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
            $Run.Published[0].TargetObject | Should -BeExactly 'POL-New'
            $Run.Published[0].Exception.Message | Should -Match "in access package 'AP'"
            $Run.Sent.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
        }

        It 'fails the policy with AssignmentPolicyRenameNotFound and creates nothing when neither name is a policy of the package (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { }
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = 'x' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-x' -DisplayName 'Unrelated') -UseWhatIf $UseWhatIf

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly $script:PolNotFoundDetail
            $Run.Rows[1].Error.FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            # Every other live policy is still judged by its name, as before.
            $Run.Rows[2].Action | Should -BeExactly 'Extra'
            $Run.Rows[2].Detail | Should -BeExactly "undeclared assignmentPolicy 'Unrelated' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)"
            @($Run.Rows | Where-Object { $_.Action -eq 'Created' -or $_.Detail -like 'would create*' }).Count | Should -Be 0

            $Run.Published.Count | Should -Be 1
            $Run.Published[0].FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            $Run.Published[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $Run.Published[0].TargetObject | Should -BeExactly 'POL-New'
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 0
            $Run.Sent.Count | Should -Be 0
        }

        It 'plans a policy that declares previousDisplayName as AssignmentPolicyRenameNotFound, never as a create, when the package itself would be created under -WhatIf' {
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }

            $Run = Invoke-PolSync -Item $Item -Packages @() -UseWhatIf $true -RenameMap $Map

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[0].Action | Should -BeExactly 'Skipped'
            $Run.Rows[0].Detail | Should -BeExactly 'would create access package AP'
            $Run.Rows[1].Section | Should -BeExactly 'accessPackages'
            $Run.Rows[1].Item | Should -BeExactly 'AP'
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly $script:PolNotFoundDetail
            $Run.Rows[1].Error.FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            $Run.Rows[2].Action | Should -BeExactly 'Skipped'
            $Run.Rows[2].Detail | Should -BeExactly "would create assignmentPolicy 'Plain' after access package is created"
            @($Run.Rows | Where-Object { $_.Detail -like "*would create assignmentPolicy 'POL-New'*" }).Count | Should -Be 0
            $Run.Published.Count | Should -Be 1
            $Run.Published[0].FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            $Run.Published[0].TargetObject | Should -BeExactly 'POL-New'

            # The decision replaced the policy's undecided mark: refused, under the package's name.
            $Map.Count | Should -Be 1
            $Entry = $Map['assignmentPolicies|AP|POL-New']
            $Entry.Refused | Should -BeTrue
            $Entry.ErrorId | Should -BeExactly 'AssignmentPolicyRenameNotFound'
            $Entry.Id | Should -BeNullOrEmpty
            $Run.Sent.Count | Should -Be 0
        }

        It 'reaches AssignmentPolicyRenameNotFound on the empty policy list of a package it creates, and creates only the policy without previousDisplayName' {
            Mock -ModuleName $script:moduleName New-OERAccessPackage { [PSCustomObject]@{ Id = 'ap-1'; DisplayName = 'AP' } }
            Mock -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy { }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }

            $Run = Invoke-PolSync -Item $Item -Packages @() -RenameMap $Map

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[0].Detail | Should -BeExactly 'created access package AP (ap-1)'
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly $script:PolNotFoundDetail
            $Run.Rows[2].Action | Should -BeExactly 'Created'
            $Run.Rows[2].Detail | Should -BeExactly "created assignmentPolicy 'Plain'"
            $Run.Published.Count | Should -Be 1
            $Run.Published[0].FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName New-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Plain' -and $AccessPackage -eq 'ap-1' }
            # Registered under the package's name and under the id of the package just created.
            $Map.Count | Should -Be 2
            $Map['assignmentPolicies|AP|POL-New'].ErrorId | Should -BeExactly 'AssignmentPolicyRenameNotFound'
            $Map['assignmentPolicies|ap-1|POL-New'].ErrorId | Should -BeExactly 'AssignmentPolicyRenameNotFound'
        }

        It 'renames the policy whose Id in the package''s list is the object id previousDisplayName names, matched without regard to letter case and with no request of its own' {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'AAAAAAAA-0000-0000-0000-000000000061' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'aaaaaaaa-0000-0000-0000-000000000061' -DisplayName 'POL-Old')

            # An object id names the policy by its current name and its id as the list spells it.
            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Updated'
            $Run.Rows[1].Detail | Should -BeExactly "renamed assignmentPolicy 'POL-Old' (aaaaaaaa-0000-0000-0000-000000000061) to 'POL-New'"
            $Run.Published.Count | Should -Be 0
            # The only read of the policy is the real Set's own; the PUT names the id as the list spells it.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter $script:PolGetFilter
            $Run.Sent.Count | Should -Be 1
            $Run.Sent[0].Uri | Should -BeLikeExactly '*/entitlementManagement/assignmentPolicies/aaaaaaaa-0000-0000-0000-000000000061'
            $Run.Sent[0].Body.displayName | Should -BeExactly 'POL-New'
        }

        It 'matches an object id in previousDisplayName only against the Id of a policy of the package, never its display name (R5)' {
            # The id names no policy of this package (another package's policy, or a deleted one), while
            # a live policy carries the id's text as its display name: neither may be renamed.
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'aaaaaaaa-0000-0000-0000-000000000062'; description = 'x' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-x' -DisplayName 'aaaaaaaa-0000-0000-0000-000000000062')

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'POL-New': neither 'POL-New' nor its previousDisplayName 'aaaaaaaa-0000-0000-0000-000000000062' matches an assignment policy in access package 'AP', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new assignment policy, remove previousDisplayName"
            $Run.Rows[1].Error.FullyQualifiedErrorId | Should -Match '^AssignmentPolicyRenameNotFound'
            # The policy that merely carries the id's text is not named by the entry: it stays undeclared.
            $Run.Rows[2].Action | Should -BeExactly 'Extra'
            $Run.Rows[2].Detail | Should -BeLike "undeclared assignmentPolicy 'aaaaaaaa-0000-0000-0000-000000000062' is still in force*"
            # No probe by id, and nothing written.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
            $Run.Sent.Count | Should -Be 0
        }

        It 'applies the entry normally, with no conflict and no rename, when a stale object id in previousDisplayName is not in the list and displayName is' {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'aaaaaaaa-0000-0000-0000-000000000064'; description = 'live description' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-new' -DisplayName 'POL-New')

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Unchanged'
            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'POL-New' matches"
            $Run.Published.Count | Should -Be 0
            $Run.Sent.Count | Should -Be 0
        }

        It 'refuses a previous name several policies of the package carry with one AmbiguousName record naming every id, writing nothing for it (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = 'changed' }
                    [PSCustomObject]@{ displayName = 'Other' }
                )
            }
            $Live = @(
                New-PolRaw -Id 'pol-old1' -DisplayName 'POL-Old'
                New-PolRaw -Id 'pol-old2' -DisplayName 'pol-old'
                New-PolRaw -Id 'pol-other' -DisplayName 'Other'
            )

            $Run = Invoke-PolSync -Item $Item -Live $Live -UseWhatIf $UseWhatIf -RenameMap $Map

            # The refusal, then the next policy; neither policy the previous name names is reported Extra.
            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'POL-New': 2 assignment policies of 'AP' are named 'POL-Old' (pol-old1, pol-old2), the previousDisplayName of this entry; the name cannot identify one, so nothing was written for it -- declare previousDisplayName as the object id of the policy to rename"
            $Run.Rows[2].Detail | Should -BeExactly "assignmentPolicy 'Other' matches"

            $Run.Published.Count | Should -Be 1
            $Record = $Run.Published[0]
            $Record.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Record.TargetObject | Should -BeExactly 'POL-Old'
            $Record.Exception.Message | Should -BeExactly ("Assignment policy display name 'POL-Old', the previousDisplayName of assignment policy 'POL-New', matches 2 policies (pol-old1, pol-old2) in access package 'AP'. " +
                'Access packages do not enforce unique policy display names, so this name cannot identify a single policy. ' +
                'Declare previousDisplayName as the object id of the policy to rename.')
            $Run.Rows[1].Error.Exception.Message | Should -BeExactly $Record.Exception.Message
            $Run.Sent.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
            # No decision was reached for it: the undecided mark stays.
            $Map['assignmentPolicies|AP|POL-New'].Refused | Should -BeTrue
            $Map['assignmentPolicies|AP|POL-New'].ErrorId | Should -BeNullOrEmpty
            $Map['assignmentPolicies|AP|POL-New'].Reason | Should -BeExactly $script:PolUndecided
        }

        It 'keeps the displayName duplicate refusal exactly as it is when the entry also declares previousDisplayName, and still reports the policy under the previous name as Extra' {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }
            $Live = @(
                New-PolRaw -Id 'pol-new1' -DisplayName 'POL-New'
                New-PolRaw -Id 'pol-new2' -DisplayName 'POL-New'
                New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old'
            )

            $Run = Invoke-PolSync -Item $Item -Live $Live

            # The refusal names only the policies carrying displayName, so the policy under the previous
            # name is still named by a row of its own: the Extra row.
            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly "2 assignment policies of 'AP' are named 'POL-New' (pol-new1, pol-new2); nothing was written for it"
            $Run.Rows[2].Action | Should -BeExactly 'Extra'
            $Run.Rows[2].Detail | Should -BeExactly "undeclared assignmentPolicy 'POL-Old' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)"
            $Run.Published.Count | Should -Be 1
            $Run.Published[0].TargetObject | Should -BeExactly 'POL-New'
            $Run.Sent.Count | Should -Be 0
        }

        It 'never reports the renamed policy as Extra, while another undeclared policy still is (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false; Expected = "renamed assignmentPolicy 'POL-Old' to 'POL-New'" }
            @{ UseWhatIf = $true; Expected = "would rename assignmentPolicy 'POL-Old' to 'POL-New'" }
        ) {
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }
            $Live = @(
                New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old'
                New-PolRaw -Id 'pol-x' -DisplayName 'Unrelated'
            )

            $Run = Invoke-PolSync -Item $Item -Live $Live -UseWhatIf $UseWhatIf

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Detail | Should -BeExactly $Expected
            $Extra = @($Run.Rows | Where-Object { $_.Action -eq 'Extra' })
            $Extra.Count | Should -Be 1
            $Extra[0].Detail | Should -BeLike "undeclared assignmentPolicy 'Unrelated' is still in force*"
            @($Run.Rows | Where-Object { $_.Detail -like "*undeclared assignmentPolicy 'POL-Old'*" }).Count | Should -Be 0
        }

        It 'plans the rename under -WhatIf and sends nothing (description <Desc>)' -ForEach @(
            @{ Desc = 'same'; Expected = "would rename assignmentPolicy 'POL-Old' to 'POL-New'" }
            @{ Desc = 'new desc'; Expected = "would rename assignmentPolicy 'POL-Old' to 'POL-New'; would update assignmentPolicy fields (description)" }
        ) {
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old'; description = $Desc })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old' -Description 'same') -UseWhatIf $true -RenameMap $Map

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Skipped'
            $Run.Rows[1].Detail | Should -BeExactly $Expected
            $Run.Published.Count | Should -Be 0
            $Run.Sent.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
            # Registered when decided, under -WhatIf too and before the rename is sent.
            $Map['assignmentPolicies|AP|POL-New'].Id | Should -BeExactly 'pol-old'
            $Map['assignmentPolicies|AP|POL-New'].Refused | Should -BeFalse
        }

        It 'asks ShouldProcess "Rename assignmentPolicy" for a rename, "and update it" when fields differ too, the current name and id for an object id, and the unchanged text without a rename' {
            # In a runspace whose host answers the prompt, so the question itself is read: -WhatIf
            # writes one 'What if:' line per ShouldProcess call and a declined -Confirm one prompt.
            $Scenario = [scriptblock]::Create(@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Get-OERAccessPackage -Value {
        param($Catalog, $Id)
        if ($Catalog) { @([pscustomobject]@{ Id = 'ap-1'; DisplayName = 'AP' }) }
        else { [pscustomobject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value { [pscustomobject]@{ value = @() } }
    Set-Item -Path function:script:Get-OERAccessPackageAssignmentPolicy -Value {
        foreach ($Pair in @(@('pol-old', 'POL-Old'), @('pol-a', 'POL-A'), @('aaaaaaaa-0000-0000-0000-000000000065', 'POL-C'), @('pol-plain', 'Plain'))) {
            ConvertTo-OERAssignmentPolicy -InputObject @{
                id = $Pair[0]; displayName = $Pair[1]; description = 'live'; accessPackage = @{ id = 'ap-1' }
                allowedTargetScope = 'allMemberUsers'; specificAllowedTargets = @(); expiration = @{ type = 'noExpiration' }
            }
        }
    }
    Set-Item -Path function:script:Set-OERAccessPackageAssignmentPolicy -Value { 'SET-CALLED' }
    function script:Invoke-SyncApAsk {
        [CmdletBinding(SupportsShouldProcess)]
        param([PSCustomObject]$Item)
        Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
    }
}
$Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old", "description": "changed" }, { "displayName": "POL-B", "previousDisplayName": "POL-A" }, { "displayName": "POL-D", "previousDisplayName": "AAAAAAAA-0000-0000-0000-000000000065" }, { "displayName": "Plain", "description": "changed" } ] }' | ConvertFrom-Json
'WHATIF'
& $Module { param($Item) Invoke-SyncApAsk -Item $Item -WhatIf } $Item | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'CONFIRM'
& $Module { param($Item) Invoke-SyncApAsk -Item $Item -Confirm } $Item | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'END'
'@)
            $Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Errors) | Should -BeNullOrEmpty
            $Rows = @(
                'ROW:Unchanged:access package properties match'
                "ROW:Skipped:would rename assignmentPolicy 'POL-Old' to 'POL-New'; would update assignmentPolicy fields (description)"
                "ROW:Skipped:would rename assignmentPolicy 'POL-A' to 'POL-B'"
                "ROW:Skipped:would rename assignmentPolicy 'POL-C' (aaaaaaaa-0000-0000-0000-000000000065) to 'POL-D'"
                "ROW:Skipped:would update assignmentPolicy 'Plain'"
            )
            @($Run.Output) | Should -Be (@('WHATIF') + $Rows + @('CONFIRM') + $Rows + @('END'))
            $Actions = @(
                "Rename assignmentPolicy 'POL-Old' to 'POL-New' and update it"
                "Rename assignmentPolicy 'POL-A' to 'POL-B'"
                "Rename assignmentPolicy 'POL-C' (aaaaaaaa-0000-0000-0000-000000000065) to 'POL-D'"
                "Update assignmentPolicy 'Plain'"
            )
            $WhatIf = @($Run.Events | Where-Object { $_ -like 'Line: What if:*' })
            $WhatIf.Count | Should -Be 4
            @($Run.Prompts).Count | Should -Be 4
            for ($Index = 0; $Index -lt 4; $Index++) {
                $WhatIf[$Index] | Should -BeExactly ('Line: What if: Performing the operation "{0}" on target "AP".' -f $Actions[$Index])
                $Run.Prompts[$Index] | Should -BeLikeExactly ('*Performing the operation "{0}" on target "AP".*' -f $Actions[$Index])
            }
        }

        It 'never carries one policy''s rename decision over to the next when that one''s decision cannot be made, in a script with no try' {
            # With no try anywhere on the stack a failed parameter binding only skips its statement, so the
            # decision of the policy before would still be in $PolRename. The second entry's empty
            # displayName (refused by the validator, reachable only through this private entry point)
            # makes its decision call fail to bind: it must get no row at all -- neither the first
            # policy's rename applied to it, nor a create -- and its binding error is its report.
            $Scenario = [scriptblock]::Create(@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Get-OERAccessPackage -Value {
        param($Catalog, $Id)
        if ($Catalog) { @([pscustomobject]@{ Id = 'ap-1'; DisplayName = 'AP' }) }
        else { [pscustomobject]@{ Id = 'ap-1'; DisplayName = 'AP'; Description = $null; IsHidden = $false } }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value { [pscustomobject]@{ value = @() } }
    Set-Item -Path function:script:Get-OERAccessPackageAssignmentPolicy -Value {
        foreach ($Pair in @(@('pol-old', 'POL-Old'), @('pol-q', 'POL-Q'))) {
            ConvertTo-OERAssignmentPolicy -InputObject @{
                id = $Pair[0]; displayName = $Pair[1]; description = 'live'; accessPackage = @{ id = 'ap-1' }
                allowedTargetScope = 'allMemberUsers'; specificAllowedTargets = @(); expiration = @{ type = 'noExpiration' }
            }
        }
    }
    Set-Item -Path function:script:Set-OERAccessPackageAssignmentPolicy -Value { }
    Set-Item -Path function:script:New-OERAccessPackageAssignmentPolicy -Value { }
    function script:Invoke-SyncApAsk {
        [CmdletBinding(SupportsShouldProcess)]
        param([PSCustomObject]$Item)
        Sync-OERStructureAccessPackage -Item $Item -Caller $PSCmdlet
    }
}
$Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old" }, { "displayName": "", "previousDisplayName": "POL-Q" } ] }' | ConvertFrom-Json
'WHATIF'
& $Module { param($Item) Invoke-SyncApAsk -Item $Item -WhatIf } $Item | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'END'
'@)
            $Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            @($Run.Output) | Should -Be @(
                'WHATIF'
                'ROW:Unchanged:access package properties match'
                "ROW:Skipped:would rename assignmentPolicy 'POL-Old' to 'POL-New'"
                'END'
            )
            @($Run.Errors).Count | Should -Be 1
            $Run.Errors[0] | Should -BeLike "*parameter 'Name'*"
            @($Run.Events | Where-Object { $_ -like 'Line: What if:*' }).Count | Should -Be 1
        }

        It 'reports a failed Set as one Failed row carrying the error, naming the rename when it carried one (<Case>)' -ForEach @(
            @{ Case = 'a rename by previous name'; Prev = 'POL-Old'; LiveId = 'pol-old'; LiveName = 'POL-Old'
                Expected = "failed to rename assignmentPolicy 'POL-Old' to 'POL-New': Graph rejected the update" }
            @{ Case = 'a rename by object id'; Prev = 'AAAAAAAA-0000-0000-0000-000000000066'; LiveId = 'aaaaaaaa-0000-0000-0000-000000000066'; LiveName = 'POL-Old'
                Expected = "failed to rename assignmentPolicy 'POL-Old' (aaaaaaaa-0000-0000-0000-000000000066) to 'POL-New': Graph rejected the update" }
            @{ Case = 'no rename (control: the text it always had)'; Prev = $null; LiveId = 'pol-old'; LiveName = 'POL-New'
                Expected = "failed to update assignmentPolicy 'POL-New': Graph rejected the update" }
        ) {
            Mock -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy { throw 'Graph rejected the update' }
            $Entry = [PSCustomObject]@{ displayName = 'POL-New'; description = 'changed' }
            if ($Prev) { $Entry | Add-Member -NotePropertyName previousDisplayName -NotePropertyValue $Prev }
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    $Entry
                    [PSCustomObject]@{ displayName = 'Other' }
                )
            }
            $Live = @(
                New-PolRaw -Id $LiveId -DisplayName $LiveName
                New-PolRaw -Id 'pol-other' -DisplayName 'Other'
            )

            $Run = Invoke-PolSync -Item $Item -Live $Live

            @($Run.Rows).Count | Should -Be 3
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly $Expected
            $Run.Rows[1].Error | Should -Not -BeNullOrEmpty
            $Run.Rows[2].Detail | Should -BeExactly "assignmentPolicy 'Other' matches"
            @($Run.Rows | Where-Object { $_.Detail -like 'renamed*' }).Count | Should -Be 0
            # Measured: the caller's -ErrorVariable holds the thrown error and the handler's own
            # publication of it, both carrying the cmdlet's message; nothing else is published.
            $Run.Published.Count | Should -Be 2
            @($Run.Published | Where-Object { $_.Exception.Message -ceq 'Graph rejected the update' }).Count | Should -Be 2
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERAccessPackageAssignmentPolicy -Times 1 -Exactly -ParameterFilter {
                $Id -eq $LiveId -and $DisplayName -eq 'POL-New' -and $Description -eq 'changed'
            }
        }

        It 'refuses a rename of a policy whose entry declares requestorScope SpecificConnectedOrganizationUsers with the BL-50 row, before ShouldProcess and with no request (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            # The live policy matches every declared field, so only the rename would send the Set call --
            # and that call would carry the declared scope, whose connected organization targets this
            # module cannot name.
            $Raw = New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old'
            $Raw.allowedTargetScope = 'specificConnectedOrganizationUsers'
            $Raw.specificAllowedTargets = @(@{
                    '@odata.type'           = '#microsoft.graph.connectedOrganizationMembers'
                    connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                    description             = 'Partner organization'
                })
            $Item = '{ "displayName": "AP", "catalog": "CAT", "assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "POL-Old", "description": "live description", "requestorScope": { "scope": "SpecificConnectedOrganizationUsers" } } ] }' |
                ConvertFrom-Json

            $Run = Invoke-PolSync -Item $Item -Live @($Raw) -UseWhatIf $UseWhatIf

            @($Run.Rows).Count | Should -Be 2
            $Run.Rows[1].Action | Should -BeExactly 'Failed'
            $Run.Rows[1].Detail | Should -BeExactly ("assignmentPolicy 'POL-New' declares requestorScope SpecificConnectedOrganizationUsers, " +
                'but this module does not model connected organization targets, so the update would drop any ' +
                'the live policy names; nothing was written for it. Omit requestorScope from the entry to update ' +
                'the other fields while keeping the live scope.')
            $Run.Rows[1].Error | Should -BeNullOrEmpty
            $Run.Published.Count | Should -Be 0
            # Before ShouldProcess: no 'would rename' row under -WhatIf, and the real Set never ran (its
            # read of the policy was never made, and nothing was PUT).
            @($Run.Rows | Where-Object { $_.Action -eq 'Skipped' -or $_.Detail -like '*rename*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter $script:PolGetFilter
            $Run.Sent.Count | Should -Be 0
        }
    }

    Context 'the run''s rename map' {

        It 'registers the package it renames under its new name as the id found under its previous name, under -WhatIf too (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            Mock -ModuleName $script:moduleName Set-OERAccessPackage { }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{ displayName = 'AP-New'; previousDisplayName = 'AP-Old'; catalog = 'CAT' }

            $Run = Invoke-PolSync -Item $Item -Packages @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' }) -UseWhatIf $UseWhatIf -RenameMap $Map

            $Run.Rows[0].Detail | Should -BeLike "*rename* access package 'AP-Old' to 'AP-New'"
            $Map.Count | Should -Be 1
            $Entry = $Map['accessPackages|AP-New']
            $Entry.Id | Should -BeExactly 'ap-old'
            $Entry.Refused | Should -BeFalse
            $Entry.ErrorId | Should -BeNullOrEmpty
        }

        It 'registers a refused package rename as refused with its error id, and leaves every renaming policy undecided (<ErrorId>)' -ForEach @(
            @{ ErrorId = 'AccessPackageRenameConflict' }
            @{ ErrorId = 'AccessPackageRenameNotFound' }
        ) {
            $Packages = if ($ErrorId -eq 'AccessPackageRenameConflict') {
                @([PSCustomObject]@{ Id = 'pkg-new'; DisplayName = 'AP-New' }, [PSCustomObject]@{ Id = 'pkg-old'; DisplayName = 'AP-Old' })
            } else { @() }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName         = 'AP-New'
                previousDisplayName = 'AP-Old'
                catalog             = 'CAT'
                assignmentPolicies  = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }

            $Run = Invoke-PolSync -Item $Item -Packages $Packages -RenameMap $Map

            @($Run.Rows).Count | Should -Be 1
            $Run.Rows[0].Error.FullyQualifiedErrorId | Should -Match "^$ErrorId"
            # A conflict also marks the renaming policy under both packages' ids (fix round 2); a rename that
            # found neither name has no id to mark.
            $Map.Count | Should -Be $(if ($ErrorId -eq 'AccessPackageRenameConflict') { 4 } else { 2 })
            $Map['accessPackages|AP-New'].Refused | Should -BeTrue
            $Map['accessPackages|AP-New'].ErrorId | Should -BeExactly $ErrorId
            $Map['accessPackages|AP-New'].Id | Should -BeNullOrEmpty
            $Map['assignmentPolicies|AP-New|POL-New'].Refused | Should -BeTrue
            $Map['assignmentPolicies|AP-New|POL-New'].ErrorId | Should -BeNullOrEmpty
            $Map['assignmentPolicies|AP-New|POL-New'].Reason | Should -BeExactly $script:PolUndecided
        }

        # IdMark: whether the package had been found when the entry stopped, so that the renaming policy is
        # marked under the package's id as well (Task 6 fix round 1, Fix B).
        It 'leaves the undecided marks of the package and of its renaming policies when the entry stops before they are decided (<Case>)' -ForEach @(
            @{ Case = 'the catalog rename was refused'; PackageMark = $true; IdMark = $false }
            @{ Case = 'the package list read throws'; PackageMark = $true; IdMark = $false }
            @{ Case = 'the previous name of the package is ambiguous'; PackageMark = $true; IdMark = $false }
            @{ Case = 'the package update that renames it fails'; PackageMark = $false; IdMark = $true }
        ) {
            $Map = New-PolMap
            $Packages = @([PSCustomObject]@{ Id = 'ap-old'; DisplayName = 'AP-Old' })
            $ListError = $null
            switch ($Case) {
                'the catalog rename was refused' { Register-PolRefusedCatalog -RenameMap $Map }
                'the package list read throws' { $ListError = 'transient Graph failure' }
                'the previous name of the package is ambiguous' {
                    $Packages = @([PSCustomObject]@{ Id = 'ap-old1'; DisplayName = 'AP-Old' }, [PSCustomObject]@{ Id = 'ap-old2'; DisplayName = 'AP-Old' })
                }
                'the package update that renames it fails' {
                    Mock -ModuleName $script:moduleName Set-OERAccessPackage { throw 'Graph rejected the update' }
                }
            }
            $Item = [PSCustomObject]@{
                displayName         = 'AP-New'
                previousDisplayName = 'AP-Old'
                catalog             = 'CAT'
                description         = 'changed'
                assignmentPolicies  = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }

            $Run = Invoke-PolSync -Item $Item -Packages $Packages -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old') -RenameMap $Map -PackageListError $ListError

            # The entry stopped with one Failed row, before any policy was read.
            @($Run.Rows).Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeLike $(switch ($Case) {
                    'the catalog rename was refused' { "catalog 'CAT' was not reconciled in this run*" }
                    'the package list read throws' { "failed to look up access packages in catalog 'CAT': transient Graph failure*" }
                    'the previous name of the package is ambiguous' { "catalog 'CAT' holds 2 access packages named 'AP-Old'*" }
                    'the package update that renames it fails' { 'access package update failed: Graph rejected the update' }
                })
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 0
            # The renaming policy keeps its mark; the policy without previousDisplayName has none.
            $PolicyMark = $Map['assignmentPolicies|AP-New|POL-New']
            $PolicyMark.Refused | Should -BeTrue
            $PolicyMark.Id | Should -BeNullOrEmpty
            $PolicyMark.ErrorId | Should -BeNullOrEmpty
            $PolicyMark.Reason | Should -BeExactly $script:PolUndecided
            $Map.ContainsKey('assignmentPolicies|AP-New|Plain') | Should -BeFalse
            $Map.ContainsKey('assignmentPolicies|ap-old|Plain') | Should -BeFalse
            if ($IdMark) {
                # The package was found (ap-old) before the update failed: the mark is under its id too.
                [object]::ReferenceEquals($Map['assignmentPolicies|ap-old|POL-New'], $PolicyMark) | Should -BeTrue
            } else {
                $Map.ContainsKey('assignmentPolicies|ap-old|POL-New') | Should -BeFalse
            }
            if ($PackageMark) {
                $Map['accessPackages|AP-New'].Refused | Should -BeTrue
                $Map['accessPackages|AP-New'].ErrorId | Should -BeNullOrEmpty
                $Map['accessPackages|AP-New'].Reason | Should -BeExactly $script:PolUndecided
            } else {
                # The package's own rename was decided before its update was sent.
                $Map['accessPackages|AP-New'].Id | Should -BeExactly 'ap-old'
                $Map['accessPackages|AP-New'].Refused | Should -BeFalse
            }
        }

        # Task 6 fix round 1 (Fix B): once an existing package has been found, every policy that declares
        # previousDisplayName is marked undecided again under the package's id as well, before anything
        # else is read or written for the package. Each stop after that point leaves the policy refused
        # under BOTH keys, so a review that names the package by object id is refused too, never looked up
        # by name within the package. Read back through the real Get-OERStructureRenameTarget.
        It 'leaves the renaming policy refused under the package''s name and under its id when the entry stops after the package was found (<Case>)' -ForEach @(
            @{ Case = 'the package re-read fails'; Renames = $false; UseWhatIf = $false; Rows = 1
                Detail = "failed to re-read access package 'AP' (ap-1): transient re-read failure" }
            @{ Case = 'the package re-read fails, under -WhatIf'; Renames = $false; UseWhatIf = $true; Rows = 1
                Detail = "failed to re-read access package 'AP' (ap-1): transient re-read failure" }
            @{ Case = 'the package update that renames it fails'; Renames = $true; UseWhatIf = $false; Rows = 1
                Detail = 'access package update failed: Graph rejected the update' }
            @{ Case = 'the resource role bindings read fails'; Renames = $false; UseWhatIf = $false; Rows = 2
                Detail = "failed to read the current resource role bindings of access package 'AP': transient bindings failure; no resourceRole or assignmentPolicy was created, updated or removed" }
            @{ Case = 'the policy list read fails'; Renames = $false; UseWhatIf = $false; Rows = 2
                Detail = "failed to read the current assignment policies of access package 'AP': transient policies failure; no assignmentPolicy was created or updated" }
            @{ Case = 'the catalog resources read fails'; Renames = $false; UseWhatIf = $false; Rows = 2
                Detail = "failed to read the resources of catalog 'CAT': transient resources failure; no resourceRole binding was added, reported Extra or removed" }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Case = $Case } {
                param($Case)
                switch -Wildcard ($Case) {
                    'the package re-read fails*' { Mock Get-OERAccessPackage { throw 'transient re-read failure' } -ParameterFilter { $Id } }
                    'the package update that renames it fails' { Mock Set-OERAccessPackage { throw 'Graph rejected the update' } }
                    'the resource role bindings read fails' { Mock Invoke-OERGraphRequest { throw 'transient bindings failure' } -ParameterFilter { $Uri -like '*resourceRoleScopes*' } }
                    'the policy list read fails' { Mock Get-OERAccessPackageAssignmentPolicy { throw 'transient policies failure' } -ParameterFilter { $AccessPackage -eq 'ap-1' } }
                    'the catalog resources read fails' { Mock Get-OERCatalogResource { throw 'transient resources failure' } }
                }
            }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                resourceRoles      = @([PSCustomObject]@{ resource = 'grp_x'; role = 'Member' })
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }
            $LivePackage = 'AP'
            if ($Renames) {
                $Item | Add-Member -NotePropertyName previousDisplayName -NotePropertyValue 'AP-Old'
                $LivePackage = 'AP-Old'
            }

            $Run = Invoke-PolSync -Item $Item -Packages @([PSCustomObject]@{ Id = 'ap-1'; DisplayName = $LivePackage }) `
                -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old') -UseWhatIf $UseWhatIf -RenameMap $Map

            # The entry stopped where the case says, with one Failed row last and no policy decided.
            @($Run.Rows).Count | Should -Be $Rows
            $Run.Rows[-1].Action | Should -BeExactly 'Failed'
            $Run.Rows[-1].Detail | Should -BeExactly $Detail
            @($Run.Rows | Where-Object { $_.Detail -like "*assignmentPolicy '*" }) | Should -BeNullOrEmpty
            # -ErrorVariable also holds the inner layers of a mock's throw: count what the handler itself
            # published through its caller, and prove no mark failed to bind.
            $Own = @($Run.Published | Where-Object { $_.FullyQualifiedErrorId.EndsWith(',Invoke-SyncApViaCaller') })
            $Own.Count | Should -Be 1
            $Own[0].Exception.Message | Should -BeExactly $Run.Rows[-1].Error.Exception.Message
            @($Run.Published | Where-Object { $_.Exception -is [System.Management.Automation.ParameterBindingException] }) | Should -BeNullOrEmpty
            $Run.Sent.Count | Should -Be 0

            $Targets = InModuleScope $script:moduleName -Parameters @{ Map = $Map } {
                param($Map)
                [PSCustomObject]@{
                    ByName      = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP' -RenameMap $Map
                    ById        = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'pol-new' -AccessPackage 'AP-1' -RenameMap $Map
                    PlainByName = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'Plain' -AccessPackage 'AP' -RenameMap $Map
                    PlainById   = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'Plain' -AccessPackage 'ap-1' -RenameMap $Map
                }
            }
            foreach ($Target in @($Targets.ByName, $Targets.ById)) {
                $Target | Should -Not -BeNullOrEmpty
                $Target.Section | Should -BeExactly 'assignmentPolicies'
                $Target.Name | Should -BeExactly 'POL-New'
                $Target.PreviousName | Should -BeExactly 'POL-Old'
                $Target.Refused | Should -BeTrue
                $Target.Id | Should -BeNullOrEmpty
                $Target.ErrorId | Should -BeNullOrEmpty
                $Target.Reason | Should -BeExactly $script:PolUndecided
            }
            [object]::ReferenceEquals($Targets.ByName, $Targets.ById) | Should -BeTrue
            # The policy without previousDisplayName is marked under neither key.
            $Targets.PlainByName | Should -BeNullOrEmpty
            $Targets.PlainById | Should -BeNullOrEmpty
            # The two policy keys, and for a renaming package its own decision (a Rename to ap-1).
            if ($Renames) {
                $Map.Count | Should -Be 3
                $Map['accessPackages|AP'].Id | Should -BeExactly 'ap-1'
            } else {
                $Map.Count | Should -Be 2
            }
        }

        # Fix round 2: the entry also knows package ids when it stops at a refused rename conflict (both
        # packages) or at an ambiguous name (every candidate). Each renaming policy is marked under each of
        # those ids, so a review that names any of them by object id is refused, never looked up by name. A
        # rename that found neither name has no id to mark. Read back through the real reader.
        It 'marks the renaming policy under every package id the entry knows when it stops at <Case>' -ForEach @(
            @{ Case = 'a package rename conflict'; UseWhatIf = $false; Prev = 'AP-Old'
                Packages = @('pkg-new=AP-New', 'pkg-old=AP-Old'); Ids = @('pkg-new', 'pkg-old')
                Detail = "both 'AP-New' and its previousDisplayName 'AP-Old' exist in catalog 'CAT' as different access packages*" }
            @{ Case = 'a package rename conflict, under -WhatIf'; UseWhatIf = $true; Prev = 'AP-Old'
                Packages = @('pkg-new=AP-New', 'pkg-old=AP-Old'); Ids = @('pkg-new', 'pkg-old')
                Detail = "both 'AP-New' and its previousDisplayName 'AP-Old' exist in catalog 'CAT' as different access packages*" }
            @{ Case = 'a package rename that found neither name'; UseWhatIf = $false; Prev = 'AP-Old'
                Packages = @('pkg-other=AP-Other'); Ids = @()
                Detail = "neither 'AP-New' nor its previousDisplayName 'AP-Old' matches an access package in catalog 'CAT'*" }
            @{ Case = 'an ambiguous previous name'; UseWhatIf = $false; Prev = 'AP-Old'
                Packages = @('pkg-o1=AP-Old', 'pkg-o2=AP-Old'); Ids = @('pkg-o1', 'pkg-o2')
                Detail = "catalog 'CAT' holds 2 access packages named 'AP-Old' (pkg-o1, pkg-o2), the previousDisplayName of this entry*" }
            @{ Case = 'an ambiguous previous name while a package carries the new name'; UseWhatIf = $false; Prev = 'AP-Old'
                Packages = @('pkg-n=AP-New', 'pkg-o1=AP-Old', 'pkg-o2=AP-Old'); Ids = @('pkg-n', 'pkg-o1', 'pkg-o2')
                Detail = "catalog 'CAT' holds 2 access packages named 'AP-Old' (pkg-o1, pkg-o2), the previousDisplayName of this entry*" }
            @{ Case = 'an ambiguous name'; UseWhatIf = $false; Prev = $null
                Packages = @('pkg-a1=AP-New', 'pkg-a2=AP-New'); Ids = @('pkg-a1', 'pkg-a2')
                Detail = "catalog 'CAT' holds 2 access packages named 'AP-New' (pkg-a1, pkg-a2); the display name cannot identify one" }
        ) {
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP-New'
                catalog            = 'CAT'
                assignmentPolicies = @(
                    [PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' }
                    [PSCustomObject]@{ displayName = 'POL-Blank'; previousDisplayName = '' }
                    [PSCustomObject]@{ displayName = 'Plain' }
                )
            }
            if ($Prev) { $Item | Add-Member -NotePropertyName previousDisplayName -NotePropertyValue $Prev }
            $LivePackages = @(foreach ($Pair in $Packages) { [PSCustomObject]@{ Id = ($Pair -split '=')[0]; DisplayName = ($Pair -split '=')[1] } })

            $Run = Invoke-PolSync -Item $Item -Packages $LivePackages -Live @(New-PolRaw -Id 'pol-old' -DisplayName 'POL-Old') -UseWhatIf $UseWhatIf -RenameMap $Map

            # The entry stopped with one Failed row, before any package or policy read and any write.
            @($Run.Rows).Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeLike $Detail
            Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageAssignmentPolicy -Times 0
            $Run.Sent.Count | Should -Be 0
            @($Run.Published | Where-Object { $_.Exception -is [System.Management.Automation.ParameterBindingException] }) | Should -BeNullOrEmpty

            $Found = InModuleScope $script:moduleName -Parameters @{ Map = $Map; Terms = @(@('AP-New') + @($Ids)) } {
                param($Map, $Terms)
                foreach ($Term in $Terms) {
                    [PSCustomObject]@{
                        Term   = $Term
                        Policy = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage $Term -RenameMap $Map
                        Blank  = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-Blank' -AccessPackage $Term -RenameMap $Map
                        Plain  = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'Plain' -AccessPackage $Term -RenameMap $Map
                    }
                }
            }
            @($Found).Count | Should -Be (1 + @($Ids).Count)
            foreach ($Hit in @($Found)) {
                $Hit.Policy | Should -Not -BeNullOrEmpty -Because "the renaming policy must be marked under '$($Hit.Term)'"
                $Hit.Policy.Refused | Should -BeTrue
                $Hit.Policy.Id | Should -BeNullOrEmpty
                $Hit.Policy.ErrorId | Should -BeNullOrEmpty
                $Hit.Policy.Reason | Should -BeExactly $script:PolUndecided
                $Hit.Policy.PreviousName | Should -BeExactly 'POL-Old'
                $Hit.Blank | Should -BeNullOrEmpty
                $Hit.Plain | Should -BeNullOrEmpty
            }
            # The policy keys are the name key and one per id; nothing else of the policies is registered.
            $PolicyKeys = @($Map.Keys | Where-Object { $_ -like 'assignmentpolicies|*' } | Sort-Object)
            $PolicyKeys | Should -BeExactly @(@(@('ap-new') + @($Ids)) | ForEach-Object { "assignmentpolicies|$_|pol-new" } | Sort-Object)
        }

        It 'marks again under the package''s id no policy name that is empty after string conversion, and publishes no error for it (<Case>)' -ForEach @(
            @{ Case = 'a policy''s previousDisplayName'; Policies = @('POL-New=', 'POL-X=POL-Y') }
            @{ Case = 'a policy''s displayName'; Policies = @('=POL-Old', 'POL-X=POL-Y') }
        ) {
            # The package is found and its re-read fails, so the entry stops right after the second marks:
            # what the map holds then, and what was published, is the work of the two mark blocks.
            InModuleScope $script:moduleName {
                Mock Get-OERAccessPackage { throw 'transient re-read failure' } -ParameterFilter { $Id }
            }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(foreach ($Pair in $Policies) {
                        [PSCustomObject]@{ displayName = ($Pair -split '=')[0]; previousDisplayName = ($Pair -split '=')[1] }
                    })
            }

            $Run = Invoke-PolSync -Item $Item -RenameMap $Map

            @($Run.Rows).Count | Should -Be 1
            $Run.Rows[0].Detail | Should -BeExactly "failed to re-read access package 'AP' (ap-1): transient re-read failure"
            # The re-read failure is the one error the handler published (-ErrorVariable also holds the
            # inner layers of the mock's throw), and no mark failed to bind.
            $Own = @($Run.Published | Where-Object { $_.FullyQualifiedErrorId.EndsWith(',Invoke-SyncApViaCaller') })
            $Own.Count | Should -Be 1
            $Own[0].Exception.Message | Should -BeExactly 'transient re-read failure'
            @($Run.Published | Where-Object { $_.Exception -is [System.Management.Automation.ParameterBindingException] }) | Should -BeNullOrEmpty
            @($Run.Published | Where-Object { $_.Exception.Message -ne 'transient re-read failure' }) | Should -BeNullOrEmpty
            @($Map.Keys | Sort-Object) | Should -BeExactly @(@('assignmentpolicies|ap|pol-x', 'assignmentpolicies|ap-1|pol-x') | Sort-Object)
            foreach ($Key in @($Map.Keys)) { $Map[$Key].Reason | Should -BeExactly $script:PolUndecided }
        }

        It 'marks nothing again for a package whose name is empty: the item ends where it always did, at its first row' {
            # A catalog list entry whose DisplayName is empty matches an entry whose displayName is empty, so
            # the package is found; the first marks skipped the entry, and so do the second. The re-read
            # fails, and its Failed row cannot name an empty -Item (a terminating binding error, measured),
            # so the item ends there, as it did before this step -- never in a mark block, whose binding of
            # a missing reason or an empty package would be the first error otherwise.
            InModuleScope $script:moduleName {
                Mock Get-OERAccessPackage { throw 'transient re-read failure' } -ParameterFilter { $Id }
            }
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = ''
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }

            $Thrown = $null
            try {
                $null = Invoke-PolSync -Item $Item -Packages @([PSCustomObject]@{ Id = 'ap-e'; DisplayName = '' }) -RenameMap $Map
            } catch { $Thrown = $PSItem }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
            $Thrown.Exception.CommandInvocation.MyCommand.Name | Should -BeExactly 'ConvertTo-OERStructureResult'
            $Thrown.Exception.ParameterName | Should -BeExactly 'Item'
            $Map.Count | Should -Be 0
        }

        It 'registers a policy decision under the package''s declared name and under the package''s id (<Outcome>)' -ForEach @(
            @{ Outcome = 'Rename'; Live = @('pol-old=POL-Old'); Id = 'pol-old'; ErrorId = $null }
            @{ Outcome = 'Conflict'; Live = @('pol-new=POL-New', 'pol-old=POL-Old'); Id = $null; ErrorId = 'AssignmentPolicyRenameConflict' }
            @{ Outcome = 'NotFound'; Live = @(); Id = $null; ErrorId = 'AssignmentPolicyRenameNotFound' }
            @{ Outcome = 'Current'; Live = @('pol-new=POL-New'); Id = $null; ErrorId = $null }
        ) {
            $Map = New-PolMap
            $LivePolicies = @(foreach ($Pair in $Live) { New-PolRaw -Id ($Pair -split '=')[0] -DisplayName ($Pair -split '=')[1] })
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }

            $null = Invoke-PolSync -Item $Item -Live $LivePolicies -RenameMap $Map

            # Read back through the reader, by the package's name and by its object id.
            $Targets = InModuleScope $script:moduleName -Parameters @{ Map = $Map } {
                param($Map)
                [PSCustomObject]@{
                    ByName = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'AP' -RenameMap $Map
                    ById   = Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name 'POL-New' -AccessPackage 'ap-1' -RenameMap $Map
                }
            }
            if ($Outcome -eq 'Current') {
                # The new name finds the policy: the mark is removed and nothing is registered.
                $Map.Count | Should -Be 0
                $Targets.ByName | Should -BeNullOrEmpty
                $Targets.ById | Should -BeNullOrEmpty
            } else {
                $Map.Count | Should -Be 2
                foreach ($Target in @($Targets.ByName, $Targets.ById)) {
                    $Target | Should -Not -BeNullOrEmpty
                    $Target.Refused | Should -Be ($Outcome -ne 'Rename')
                    if ($Id) { $Target.Id | Should -BeExactly $Id } else { $Target.Id | Should -BeNullOrEmpty }
                    if ($ErrorId) { $Target.ErrorId | Should -BeExactly $ErrorId } else { $Target.ErrorId | Should -BeNullOrEmpty }
                }
            }
        }

        It 'marks no name that is empty after string conversion, and the mark block publishes no error for it (<Case>)' -ForEach @(
            @{ Case = 'the package''s previousDisplayName'; PackagePrev = ''; Policies = @('POL-New=POL-Old'); Marked = @('assignmentPolicies|AP|POL-New') }
            @{ Case = 'a policy''s previousDisplayName'; PackagePrev = $null; Policies = @('POL-New=', 'POL-X=POL-Y'); Marked = @('assignmentPolicies|AP|POL-X') }
            @{ Case = 'a policy''s displayName'; PackagePrev = $null; Policies = @('=POL-Old', 'POL-X=POL-Y'); Marked = @('assignmentPolicies|AP|POL-X') }
        ) {
            # The catalog's rename is refused, so the entry stops right after the mark block, before any
            # lookup or decision: what the map holds then, and what was published, is the block's work.
            $Map = New-PolMap
            Register-PolRefusedCatalog -RenameMap $Map
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @(foreach ($Pair in $Policies) {
                        [PSCustomObject]@{ displayName = ($Pair -split '=')[0]; previousDisplayName = ($Pair -split '=')[1] }
                    })
            }
            if ($null -ne $PackagePrev) { $Item | Add-Member -NotePropertyName previousDisplayName -NotePropertyValue $PackagePrev }

            $Run = Invoke-PolSync -Item $Item -RenameMap $Map

            @($Run.Rows).Count | Should -Be 1
            $Run.Rows[0].Detail | Should -BeLike "catalog 'CAT' was not reconciled in this run*"
            $Run.Published.Count | Should -Be 0
            # The map's keys are lower case, as Resolve-OERStructureRename builds them.
            @($Map.Keys | Sort-Object) | Should -BeExactly @(@('catalogs|cat') + @($Marked | ForEach-Object { $_.ToLowerInvariant() }) | Sort-Object)
            foreach ($Key in $Marked) { $Map[$Key].Reason | Should -BeExactly $script:PolUndecided }
        }

        It 'never fails in the mark block on an empty package name: the item ends where it always did, at its first row' {
            # An empty displayName cannot name a row either (ConvertTo-OERStructureResult refuses an empty
            # -Item with a terminating binding error, measured), so the item ends at its first row -- here
            # the refused catalog's row -- as it did before this step, and the engine reports it as a
            # handler error. The mark block itself raises nothing and registers nothing for it.
            $Map = New-PolMap
            Register-PolRefusedCatalog -RenameMap $Map
            $Item = [PSCustomObject]@{
                displayName         = ''
                previousDisplayName = 'AP-Old'
                catalog             = 'CAT'
                assignmentPolicies  = @([PSCustomObject]@{ displayName = 'POL-New'; previousDisplayName = 'POL-Old' })
            }

            $Thrown = $null
            try { $null = Invoke-PolSync -Item $Item -RenameMap $Map } catch { $Thrown = $PSItem }

            # The binding that failed is the row's -Item, never a -Name or -AccessPackage of the mark block.
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
            $Thrown.Exception.CommandInvocation.MyCommand.Name | Should -BeExactly 'ConvertTo-OERStructureResult'
            $Thrown.Exception.ParameterName | Should -BeExactly 'Item'
            @($Map.Keys) | Should -BeExactly @('catalogs|cat')
        }

        It 'registers nothing for an entry and policies that declare no previousDisplayName' {
            $Map = New-PolMap
            $Item = [PSCustomObject]@{
                displayName        = 'AP'
                catalog            = 'CAT'
                assignmentPolicies = @([PSCustomObject]@{ displayName = 'Plain' })
            }

            $Run = Invoke-PolSync -Item $Item -Live @(New-PolRaw -Id 'pol-plain' -DisplayName 'Plain') -RenameMap $Map

            $Run.Rows[1].Detail | Should -BeExactly "assignmentPolicy 'Plain' matches"
            $Map.Count | Should -Be 0
        }
    }
}
