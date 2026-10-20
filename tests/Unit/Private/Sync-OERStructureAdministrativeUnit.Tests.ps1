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

Describe 'Sync-OERStructureAdministrativeUnit' {

    It 'creates a missing AU and reports Created; passes -Restricted when restricted=true' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { $null }
            Mock New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT' } }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @() } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; restricted = $true }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAdministrativeUnit -Times 1 -ParameterFilter { $Restricted -eq $true }
        }
    }

    It 'updates description when it differs from the declared value' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = 'old desc'; Members = @(); ScopedRoles = @() } }
            Mock Set-OERAdministrativeUnit { }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; description = 'new desc' }))
            Should -Invoke Set-OERAdministrativeUnit -Times 1
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged when description already matches' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = 'same desc'; Members = @(); ScopedRoles = @() } }
            Mock Set-OERAdministrativeUnit { }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; description = 'same desc' }))
            Should -Invoke Set-OERAdministrativeUnit -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'adds a missing member and reports Updated' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @() } }
            Mock Add-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }))
            Should -Invoke Add-OERAdministrativeUnitMember -Times 1
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged for a member already present and does not call Add-OERAdministrativeUnitMember' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExistingMember = [PSCustomObject]@{ Id = 'id-person9@example.com'; DisplayName = 'Anna'; Type = 'user' }
            $ExistingMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($ExistingMember); ScopedRoles = @() } }
            Mock Add-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }))
            Should -Invoke Add-OERAdministrativeUnitMember -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'adds a missing scopedRole and calls Add-OERAdministrativeUnitScopedRole with -RoleName and -PrincipalId' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @() } }
            Mock Add-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $ScopedItem = [PSCustomObject]@{
                displayName = 'AU-IT'
                scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
            }
            $r = @(Invoke-SyncAuViaCaller -Item $ScopedItem)
            Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 1 -ParameterFilter {
                $RoleName -eq 'User Administrator' -and $PrincipalId -eq 'id-person9@example.com'
            }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged for a scopedRole whose RoleName and PrincipalId already match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExistingRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-1'
                RoleName               = 'User Administrator'
                PrincipalId            = 'id-person9@example.com'
            }
            $ExistingRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExistingRole) } }
            Mock Add-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $ScopedItem = [PSCustomObject]@{
                displayName = 'AU-IT'
                scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
            }
            $r = @(Invoke-SyncAuViaCaller -Item $ScopedItem)
            Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -Prune removes an undeclared member, warns, and reports Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraMember = [PSCustomObject]@{ Id = 'extra-id'; DisplayName = 'Extra'; Type = 'user' }
            $ExtraMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($ExtraMember); ScopedRoles = @() } }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @() }) -Prune -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERAdministrativeUnitMember -Times 1
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -Prune removes an undeclared scopedRole via -ScopedRoleMembershipId and reports Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; scopedRoles = @() }) -Prune -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1 -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-extra' }
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing for member prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraMember = [PSCustomObject]@{ Id = 'extra-id'; DisplayName = 'Extra'; Type = 'user' }
            $ExtraMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($ExtraMember); ScopedRoles = @() } }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @() }) -Prune -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for member prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraMember = [PSCustomObject]@{ Id = 'extra-id'; DisplayName = 'Extra'; Type = 'user' }
            $ExtraMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($ExtraMember); ScopedRoles = @() } }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @() }) -Prune -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'says would remove rather than removing for scopedRole prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; scopedRoles = @() }) -Prune -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for scopedRole prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; scopedRoles = @() }) -Prune -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'streams only its own warning for a scopedRole prune, silencing the duplicate the real Remove cmdlet writes' {
        # Remove-OERAdministrativeUnitScopedRole runs for REAL: only auth and the Graph transport are
        # mocked, so its own "Removing scoped role membership" warning is written, before its own gate. The
        # warning stream itself is captured (3>&1): -WarningVariable would also collect a warning the
        # cmdlet writes under a call-site SilentlyContinue, which never reaches the stream.
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest { if ($Method -eq 'DELETE') { return $null }; throw "unexpected $Method $Uri" }
            $All = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; scopedRoles = @() }) -Prune -ErrorAction Stop 3>&1)
            $Records = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            $Streamed = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
            # The DELETE ran, so the cmdlet ran and wrote its own warning, before its own gate; the
            # handler's call-site SilentlyContinue kept it off the stream.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*/scopedRoleMembers/srm-extra' }
            $Streamed.Count | Should -Be 1
            $Streamed[0] | Should -BeLike "Sync-OERStructureAdministrativeUnit: removing undeclared scopedRole 'User Administrator'*"
        }
    }

    It 'does not prune every live member when the document declares members as null' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; Description = $null
                    Members = @([PSCustomObject]@{ Id = 'u-1' }, [PSCustomObject]@{ Id = 'u-2' })
                    ScopedRoles = @()
                }
            }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Add-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Item = '{ "displayName": "AU-IT", "members": null }' | ConvertFrom-Json
            $Records = @(Invoke-SyncAuViaCaller -Item $Item -Prune)
            Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
        }
    }

    It 'still prunes every live member when the document declares members as an empty array' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; Description = $null
                    Members = @([PSCustomObject]@{ Id = 'u-1' }, [PSCustomObject]@{ Id = 'u-2' })
                    ScopedRoles = @()
                }
            }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Add-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Item = '{ "displayName": "AU-IT", "members": [] }' | ConvertFrom-Json
            $null = Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue
            Should -Invoke Remove-OERAdministrativeUnitMember -Times 2
        }
    }

    It 'still prunes every live member when the document omits the members key' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit {
                [PSCustomObject]@{
                    Id = 'au-1'; Description = $null
                    Members = @([PSCustomObject]@{ Id = 'u-1' }, [PSCustomObject]@{ Id = 'u-2' })
                    ScopedRoles = @()
                }
            }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ displayName = 'AU-IT' }
            $null = Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue
            Should -Invoke Remove-OERAdministrativeUnitMember -Times 2
        }
    }

    It 'does not prune the live scopedRole when the document declares scopedRoles as null' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Item = '{ "displayName": "AU-IT", "scopedRoles": null }' | ConvertFrom-Json
            $Records = @(Invoke-SyncAuViaCaller -Item $Item -Prune)
            Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
        }
    }

    It 'still prunes the live scopedRole when the document declares scopedRoles as an empty array' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $Item = '{ "displayName": "AU-IT", "scopedRoles": [] }' | ConvertFrom-Json
            $null = Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue
            Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1
        }
    }

    It 'still prunes the live scopedRole when the document omits the scopedRoles key' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraRole = [PSCustomObject]@{
                ScopedRoleMembershipId = 'srm-extra'
                RoleName               = 'User Administrator'
                PrincipalId            = 'extra-principal'
            }
            $ExtraRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($ExtraRole) } }
            Mock Remove-OERAdministrativeUnitScopedRole { }
            Mock Initialize-OERAuth {}
            $Item = [PSCustomObject]@{ displayName = 'AU-IT' }
            $null = Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue
            Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1
        }
    }

    It 'without -Prune reports undeclared member as Extra and does not remove it' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            $ExtraMember = [PSCustomObject]@{ Id = 'extra-id'; DisplayName = 'Extra'; Type = 'user' }
            $ExtraMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($ExtraMember); ScopedRoles = @() } }
            Mock Remove-OERAdministrativeUnitMember { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @() }))
            Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on a missing AU does not call New-OERAdministrativeUnit and emits Skipped records' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { $null }
            Mock New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT' } }
            Mock Add-OERAdministrativeUnitMember { }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }) -WhatIf)
            Should -Invoke New-OERAdministrativeUnit -Times 0
            Should -Invoke Add-OERAdministrativeUnitMember -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'when New-OERAdministrativeUnit throws emits only Failed and continues' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { $null }
            Mock New-OERAdministrativeUnit { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERAdministrativeUnit throws' {
        # Drives the AU-creation catch in Sync-OERStructureAdministrativeUnit. The scrub under test
        # is this handler's OWN -- the Remove-OERErrorRecord opening the handler catch that WRAPS
        # the New-OERAdministrativeUnit call, not a scrub inside New-OERAdministrativeUnit, which is
        # mocked away here. That mocking is precisely what makes the proof non-vacuous.
        # The static AST gate
        # proves that line is WRITTEN first; this It proves it actually RUNS. Mock + Should -Invoke
        # is the only proof shape that works here: the handler swallows the record into a Failed
        # result instead of re-throwing, so a $global:Error reference-identity proof would be inert.
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { $null }
            Mock New-OERAdministrativeUnit { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'when New-OERAdministrativeUnit returns null emits only Failed (not also Created)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { $null }
            Mock New-OERAdministrativeUnit { $null }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncAuViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-IT' }))
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'when scopedRole principal does not resolve emits Failed and continues without calling Add-OERAdministrativeUnitScopedRole' {
        InModuleScope $script:moduleName {
            function Invoke-SyncAuViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @() } }
            Mock Resolve-OERStructurePrincipal { $null }
            Mock Add-OERAdministrativeUnitScopedRole { }
            Mock Initialize-OERAuth {}
            $ScopedItem = [PSCustomObject]@{
                displayName = 'AU-IT'
                scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person15@example.com' })
            }
            $r = @(Invoke-SyncAuViaCaller -Item $ScopedItem -ErrorAction SilentlyContinue)
            Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    Context 'dynamic membership and hidden membership reconciliation' {

        It 'passes -Dynamic, -MembershipRule, -MembershipRuleProcessingState and -HiddenMembership on create' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { $null }
                Mock New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName                   = 'au'
                    dynamic                        = $true
                    membershipRule                 = '(user.country -eq "SE")'
                    membershipRuleProcessingState  = 'Paused'
                    hiddenMembership                = $true
                }
                Invoke-SyncAuViaCaller -Item $Item -Confirm:$false | Out-Null
                Should -Invoke New-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter {
                    $Dynamic -and $MembershipRule -eq '(user.country -eq "SE")' -and
                    $MembershipRuleProcessingState -eq 'Paused' -and $HiddenMembership
                }
            }
        }

        It 'updates a drifted membershipRule on an existing dynamic unit' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Dynamic'
                        MembershipRule                 = '(user.country -eq "NO")'
                        MembershipRuleProcessingState  = 'On'
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $true; membershipRule = '(user.country -eq "SE")' }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $MembershipRule -eq '(user.country -eq "SE")' }
                ($R | Where-Object { $_.Action -eq 'Updated' }).Detail | Should -BeLike '*MembershipRule*'
            }
        }

        It 'sets Visibility HiddenMembership when the document declares hiddenMembership on a public unit' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; hiddenMembership = $true }
                Invoke-SyncAuViaCaller -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $Visibility -eq 'HiddenMembership' }
            }
        }

        It 'reverts HiddenMembership to public instead of reporting Skipped' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = 'HiddenMembership'
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; hiddenMembership = $false }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $Visibility -eq 'Public' }
                ($R | Where-Object { $_.Action -eq 'Updated' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'converts an assigned unit to dynamic in one Set call, carrying the rule, and reports Updated' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $true; membershipRule = 'x' }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter {
                    $MembershipType -eq 'Dynamic' -and $MembershipRule -eq 'x'
                }
                ($R | Where-Object { $_.Action -eq 'Updated' }) | Should -Not -BeNullOrEmpty
                ($R | Where-Object { $_.Action -eq 'Skipped' }) | Should -BeNullOrEmpty
            }
        }

        It 'reports a conversion to dynamic with no membershipRule available as Failed, not a doomed Set call' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $true }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false -WarningAction SilentlyContinue)
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Failed' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'drops the force-carried membershipRuleProcessingState when the no-rule conversion is abandoned' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                # membershipRuleProcessingState was force-carried by the conversion; with the conversion
                # abandoned it must not be PATCHed on its own onto a unit that stays Assigned.
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $true; membershipRuleProcessingState = 'Paused' }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false -WarningAction SilentlyContinue)
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Failed' })  | Should -Not -BeNullOrEmpty
                ($R | Where-Object { $_.Action -eq 'Updated' }) | Should -BeNullOrEmpty
            }
        }

        It 'still reports restricted drift as Skipped (genuinely immutable)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; restricted = $true }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false -WarningAction SilentlyContinue)
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Skipped' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'does not also emit a bare "administrative unit properties match" Unchanged alongside a drift Skipped' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Initialize-OERAuth {}
                # No description/membershipType/membershipRule/hiddenMembership drift -> UpdateParams.Count
                # would be 0, so pre-fix this also emitted a contradictory bare Unchanged alongside the
                # drift Skipped. restricted is used here (not dynamic) because a dynamic+membershipRule
                # drift is no longer Skipped -- it now converts the unit and reports Updated instead.
                $Item = [PSCustomObject]@{ displayName = 'au'; restricted = $true }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false -WarningAction SilentlyContinue)
                ($R | Where-Object { $_.Detail -like "*'restricted'*" }).Action | Should -Be 'Skipped'
                ($R | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq 'administrative unit properties match' }) |
                    Should -BeNullOrEmpty
            }
        }
    }

    Context 'explicit JSON null counts as NOT declared' {

        It 'does not convert a live dynamic unit to Assigned for "dynamic": null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Dynamic'
                        MembershipRule                 = '(user.country -eq "SE")'
                        MembershipRuleProcessingState  = 'On'
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = '{ "displayName": "au", "dynamic": null }' | ConvertFrom-Json
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'does not revert a hidden unit to public for "hiddenMembership": null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = 'live description'
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = 'HiddenMembership'
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                # description is null too: it must not wipe the live description either.
                $Item = '{ "displayName": "au", "hiddenMembership": null, "description": null }' | ConvertFrom-Json
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Unchanged' }) | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'dynamic units own their membership' {

        It 'does not add declared members to an already-dynamic unit and reports Skipped for each' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Dynamic'
                        MembershipRule                 = '(user.country -eq "SE")'
                        MembershipRuleProcessingState  = 'On'
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'au'; dynamic = $true; membershipRule = '(user.country -eq "SE")'
                    members = @('person9@example.com')
                }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0 -Exactly
                $Skipped = $R | Where-Object { $_.Detail -like "*person9@example.com*" }
                $Skipped.Action | Should -Be 'Skipped'
                $Skipped.Detail | Should -BeLike '*membership rule*'
            }
        }

        It 'does not add declared members to a unit this run converted to dynamic' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'au'; dynamic = $true; membershipRule = 'x'; members = @('person9@example.com')
                }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $MembershipType -eq 'Dynamic' }
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0 -Exactly
                ($R | Where-Object { $_.Detail -like "*person9@example.com*" }).Action | Should -Be 'Skipped'
            }
        }

        It 'does not prune the members of a dynamic unit and says so once' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Member = [PSCustomObject]@{ Id = 'rule-member-id'; DisplayName = 'Anna'; Type = 'user' }
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Dynamic'
                        MembershipRule                 = '(user.country -eq "SE")'
                        MembershipRuleProcessingState  = 'On'
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @($Member) -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Remove-OERAdministrativeUnitMember { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $true; membershipRule = '(user.country -eq "SE")'; members = @() }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Prune -Confirm:$false -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0 -Exactly
                ($R | Where-Object { $_.Action -eq 'Removed' }) | Should -BeNullOrEmpty
                ($R | Where-Object { $_.Action -eq 'Extra' })   | Should -BeNullOrEmpty
                ($R | Where-Object { $_.Detail -like '*current member*' }).Action | Should -Be 'Skipped'
            }
        }

        It 'still reconciles scopedRoles on a dynamic unit (only member management is disabled)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Dynamic'
                        MembershipRule                 = '(user.country -eq "SE")'
                        MembershipRuleProcessingState  = 'On'
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Set-OERAdministrativeUnit { }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'au'; dynamic = $true; membershipRule = '(user.country -eq "SE")'
                    scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
                }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter {
                    $RoleName -eq 'User Administrator' -and $PrincipalId -eq 'id-person9@example.com'
                }
                ($R | Where-Object { $_.Action -eq 'Updated' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'reconciles members normally on an assigned unit that declares dynamic false' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                             = 'au-1'
                        DisplayName                    = 'au'
                        Description                    = $null
                        MembershipType                 = 'Assigned'
                        MembershipRule                 = $null
                        MembershipRuleProcessingState  = $null
                        IsMemberManagementRestricted   = $false
                        Visibility                     = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue @() -Force
                    $Au
                }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'au'; dynamic = $false; members = @('person9@example.com') }
                $R = @(Invoke-SyncAuViaCaller -Item $Item -Confirm:$false)
                Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly
                ($R | Where-Object { $_.Detail -eq "added member 'person9@example.com'" }).Action | Should -Be 'Updated'
            }
        }
    }

    Context 'scopedRoles declared by role id' {
        It 'passes a GUID role through -RoleId, not -RoleName' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    [PSCustomObject]@{
                        Id = 'au-1'; DisplayName = 'au_hr'; Description = $null
                        IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                        Members = @(); ScopedRoles = @()
                    }
                }
                Mock Resolve-OERStructurePrincipal { '33333333-3333-3333-3333-333333333333' }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName = 'au_hr'
                    scopedRoles = @([PSCustomObject]@{
                        role = '22222222-2222-2222-2222-222222222222'; principal = 'anna@contoso.com'
                    })
                }
                $null = Invoke-SyncAuViaCaller -Item $Item
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 1 -ParameterFilter {
                    $RoleId -eq '22222222-2222-2222-2222-222222222222' -and -not $RoleName
                }
            }
        }

        It 'matches an existing scoped role on RoleId when the live RoleName is null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit {
                    [PSCustomObject]@{
                        Id = 'au-1'; DisplayName = 'au_hr'; Description = $null
                        IsMemberManagementRestricted = $false; MembershipType = 'Assigned'; Visibility = $null
                        Members = @()
                        ScopedRoles = @([PSCustomObject]@{
                            ScopedRoleMembershipId = 'srm-1'
                            RoleName = $null
                            RoleId = '22222222-2222-2222-2222-222222222222'
                            PrincipalId = '33333333-3333-3333-3333-333333333333'
                        })
                    }
                }
                Mock Resolve-OERStructurePrincipal { '33333333-3333-3333-3333-333333333333' }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Remove-OERAdministrativeUnitScopedRole { }
                Mock Initialize-OERAuth {}

                $Item = [PSCustomObject]@{
                    displayName = 'au_hr'
                    scopedRoles = @([PSCustomObject]@{
                        role = '22222222-2222-2222-2222-222222222222'; principal = 'anna@contoso.com'
                    })
                }
                $Records = @(Invoke-SyncAuViaCaller -Item $Item)
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                @($Records | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
            }
        }
    }

    Context '-EnsureOnly (engine pre-pass support)' {
        It 'with -EnsureOnly creates a missing unit and reconciles nothing else' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Resolve-OERAdministrativeUnitId { $null }
                Mock New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT' } }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = @('person9@example.com')
                    scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
                }
                $r = @(Invoke-SyncAuViaCaller -Item $Item -EnsureOnly)
                Should -Invoke New-OERAdministrativeUnit -Times 1
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                @($r).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
            }
        }

        It 'with -EnsureOnly emits no record at all for a unit that already exists' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @() } }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Set-OERAdministrativeUnit { }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }
                $r = @(Invoke-SyncAuViaCaller -Item $Item -EnsureOnly)
                @($r).Count | Should -Be 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke Get-OERAdministrativeUnit -Times 0
            }
        }

        It 'gives the -EnsureOnly pre-pass a WhatIf Detail distinct from the main pass, so two rows for the same unit read as a sequence' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Resolve-OERAdministrativeUnitId { $null }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AU-1' }
                $PrePassRecords  = @(Invoke-SyncAuViaCaller -Item $Item -EnsureOnly -WhatIf)
                $MainPassRecords = @(Invoke-SyncAuViaCaller -Item $Item -WhatIf)
                $PrePassRecords.Count  | Should -Be 1
                $MainPassRecords.Count | Should -Be 1
                $PreDetail  = $PrePassRecords[0].Detail
                $MainDetail = $MainPassRecords[0].Detail
                $PreDetail  | Should -Not -Be $MainDetail
                $PreDetail  | Should -Match 'first, so the group'
                $MainDetail | Should -BeExactly 'would create administrative unit AU-1'
            }
        }
    }

    Context 'a failed live read is a Failed row, never a Created' {

        It 'reports Failed and reconciles nothing when the live administrative unit read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Set-OERAdministrativeUnit { }
                # Exactly what Task 2 made Get-OERAdministrativeUnit do: a NON-terminating error plus
                # an object with the unreadable collection OMITTED. A throwing mock would abort the
                # handler with -ErrorAction Stop removed from the call site too, so it would prove
                # nothing about the single condition this guard rests on.
                Mock Get-OERAdministrativeUnit {
                    param($Id, $AdministrativeUnit, $IncludeMembers, $IncludeScopedRoles, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    Write-Error -Message "Could not read members for administrative unit $Id. The Members property is omitted rather than reported as empty." -ErrorId 'AdministrativeUnitMemberReadFailed' -Category LimitsExceeded -TargetObject $Id -ErrorAction $Ea
                    [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT'; Description = $null; MembershipType = 'Assigned'; Visibility = $null }
                }

                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }
                $Results = @(Invoke-SyncAuViaCaller -Item $Item -ErrorAction SilentlyContinue)

                # Positive identity FIRST: an absence assertion on its own also passes when the
                # handler emitted nothing at all.
                @($Results).Count | Should -Be 1
                $Results[0].Section | Should -BeExactly 'administrativeUnits'
                $Results[0].Item | Should -BeExactly 'AU-IT'
                $Results[0].Action | Should -BeExactly 'Failed'
                $Results[0].Detail | Should -Match 'failed to read the current state of administrative unit'
                $null -ne $Results[0].Error | Should -BeTrue -Because 'the sprint requires the underlying ErrorRecord to travel with the Failed row'

                @($Results | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -Be 0 -Because 'an unreadable membership is not evidence that the declared member is missing'
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0 -Exactly
                Should -Invoke Set-OERAdministrativeUnit -Times 0 -Exactly
            }
        }

        It 'still reconciles a unit that genuinely has no members, and reports no Failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Get-OERAdministrativeUnit {
                    [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT'; Description = $null; MembershipType = 'Assigned'; Visibility = $null; Members = @(); ScopedRoles = @() }
                }

                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @('person9@example.com') }
                $Results = @(Invoke-SyncAuViaCaller -Item $Item)

                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'an empty read that SUCCEEDED is not a failure; only the two must be distinguishable'
                Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly
            }
        }

        It 'reconciles members normally when the entry declares scopedRoles null and that read is unusable' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias, [switch]$EnsureOnly)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias -EnsureOnly:$EnsureOnly
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Add-OERAdministrativeUnitMember { }
                # Asking for the scoped roles fails the whole read. An explicit null scopedRoles is the
                # one declaration that lets the handler skip that ask, so the switch value is the
                # single condition under test.
                Mock Get-OERAdministrativeUnit {
                    param($Id, $AdministrativeUnit, $IncludeMembers, $IncludeScopedRoles, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    if ($IncludeScopedRoles) {
                        Write-Error -Message "Could not read scoped roles for administrative unit $Id." -ErrorId 'AdministrativeUnitScopedRoleReadFailed' -Category PermissionDenied -TargetObject $Id -ErrorAction $Ea
                        return
                    }
                    [PSCustomObject]@{ Id = 'au-1'; DisplayName = 'AU-IT'; Description = $null; MembershipType = 'Assigned'; Visibility = $null; Members = @() }
                }

                $Item = '{ "displayName": "AU-IT", "members": [ "person9@example.com" ], "scopedRoles": null }' | ConvertFrom-Json
                $Results = @(Invoke-SyncAuViaCaller -Item $Item)

                # CONTENT, not merely a count -- see the group twin.
                $Added = @($Results | Where-Object { $_.Action -eq 'Updated' })
                @($Added).Count | Should -Be 1
                $Added[0].Detail | Should -Match "added member 'person9@example.com'"
                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'an explicit null scopedRoles must not fail on a scoped-role endpoint it never asked about'
                Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly
                Should -Invoke Get-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { -not $IncludeScopedRoles }
            }
        }
    }

    Context 'prune withheld when a declared entry cannot be resolved' {
        # A declared entry whose principal lookup gives no id carries no key, so the live entry it
        # was meant to name looks undeclared. The pass must report its live candidates Skipped with
        # the withheld reason instead of Extra or Removed, while the unresolved entry keeps its own
        # Failed row. person15@example.com is the unresolvable reference throughout.
        It 'withholds the member prune when a declared member cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                $LiveMember = [PSCustomObject]@{ Id = 'u-live'; DisplayName = 'Live'; Type = 'user' }
                $LiveMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
                Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($LiveMember); ScopedRoles = @() } }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Remove-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { $null }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @('person15@example.com') }
                $Warnings = @()
                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared member 'u-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve member 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'u-live'
            }
        }

        It 'withholds the scopedRole prune when a declared scopedRole principal cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                $LiveRole = [PSCustomObject]@{
                    ScopedRoleMembershipId = 'srm-live'
                    RoleName               = 'User Administrator'
                    PrincipalId            = 'p-live'
                }
                $LiveRole.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
                Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @(); ScopedRoles = @($LiveRole) } }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Remove-OERAdministrativeUnitScopedRole { }
                Mock Resolve-OERStructurePrincipal { $null }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person15@example.com' })
                }
                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared scopedRole 'User Administrator' for 'p-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve scopedRole principal 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
            }
        }

        It 'still aborts the item, and removes nothing, when a member lookup throws under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                $LiveMember = [PSCustomObject]@{ Id = 'u-live'; DisplayName = 'Live'; Type = 'user' }
                $LiveMember.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
                Mock Get-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-1'; Description = $null; Members = @($LiveMember); ScopedRoles = @() } }
                Mock Remove-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { throw 'Graph 503 while resolving the member' }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @('person15@example.com') }
                { Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } |
                    Should -Throw -ExpectedMessage '*Graph 503*'
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
            }
        }
    }

    # BL-07: a group the groups section created INTO this unit earlier in the same run is a live member
    # the unit's entry need not list (administrativeUnit never round-trips). Sync-OERStructureGroup
    # records it in the run-scoped list the engine passes as -CreatedUnitMembership; the member prune
    # pass withholds it under -Prune and reports it Extra without -Prune, while every other undeclared
    # member is pruned as before. The live unit holds the created group and one unrecorded user.
    Context 'a group this run created into the unit (BL-07)' {
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { '66666666-6666-6666-6666-aaaaaaaaaaaa' }
                Mock Get-OERAdministrativeUnit {
                    $GroupMember = [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = 'grp-new'; Type = 'group' }
                    $UserMember = [PSCustomObject]@{ Id = 'u-extra'; DisplayName = 'Extra'; Type = 'user' }
                    [PSCustomObject]@{ Id = '66666666-6666-6666-6666-aaaaaaaaaaaa'; Description = $null; Members = @($GroupMember, $UserMember); ScopedRoles = @() }
                }
                Mock Remove-OERAdministrativeUnitMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $Reference }
                Mock Initialize-OERAuth {}
            }
        }

        It 'withholds the recorded group''s membership under -Prune and still prunes the unrecorded member, for a record naming the unit <Label>' -ForEach @(
            @{ Label = 'by its display name, in another case'; Unit = 'au-it' }
            @{ Label = 'by its object id, in another case'; Unit = '66666666-6666-6666-6666-AAAAAAAAAAAA' }
            @{ Label = 'by its object id in braces, which New-OERGroup also reads as an id'; Unit = '{66666666-6666-6666-6666-aaaaaaaaaaaa}' }
            @{ Label = 'by its object id without dashes, which New-OERGroup also reads as an id'; Unit = '66666666666666666666AAAAAAAAAAAA' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Unit = $Unit } {
                param($Unit)
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -CreatedUnitMembership $Created
                }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Created.Add([PSCustomObject]@{ AdministrativeUnit = $Unit; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @(); scopedRoles = $null }
                $All = @(Invoke-SyncAuViaCaller -Item $Item -Prune -Created $Created -ErrorAction Stop 3>&1)
                $Records = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
                $Streamed = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
                # Positive control: the pass reached the removal path, and removed the unrecorded member.
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
                @($Records | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared member 'u-extra'" }).Count | Should -Be 1
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0 -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
                $Withheld = @($Records | Where-Object { $_.Action -eq 'Skipped' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Section | Should -BeExactly 'administrativeUnits'
                $Withheld[0].Item | Should -BeExactly 'AU-IT'
                $Withheld[0].Detail | Should -BeExactly ("prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'grp-new', " +
                    'which the groups section of this run either created into this unit or, when the group already existed, found in place of creating it; ' +
                    'this run does not remove that membership (our own guard, not a Graph rejection). ' +
                    "The next apply with -Prune removes it unless the unit's members name the group.")
                $Streamed.Count | Should -Be 1
                $Streamed[0] | Should -BeExactly "Sync-OERStructureAdministrativeUnit: removing undeclared member 'u-extra' from unit 'AU-IT'."
            }
        }

        It 'reports the recorded group''s membership Extra without -Prune, as before, and removes nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -CreatedUnitMembership $Created
                }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Created.Add([PSCustomObject]@{ AdministrativeUnit = 'AU-IT'; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @(); scopedRoles = $null }
                $Records = @(Invoke-SyncAuViaCaller -Item $Item -Created $Created -ErrorAction Stop)
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                @($Records | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared member '88888888-8888-8888-8888-888888888888' (use -Prune to remove)" }).Count | Should -Be 1
                @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared member 'u-extra' (use -Prune to remove)" }).Count | Should -Be 1
            }
        }

        It 'prunes the group''s membership under -Prune when the record names <Label>' -ForEach @(
            @{ Label = 'another unit'; Unit = 'AU-Other'; GroupId = '88888888-8888-8888-8888-888888888888' }
            @{ Label = 'another unit by object id'; Unit = '77777777-7777-7777-7777-777777777777'; GroupId = '88888888-8888-8888-8888-888888888888' }
            @{ Label = 'another group of this unit'; Unit = 'AU-IT'; GroupId = '99999999-9999-9999-9999-999999999999' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Unit = $Unit; GroupId = $GroupId } {
                param($Unit, $GroupId)
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -CreatedUnitMembership $Created
                }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Created.Add([PSCustomObject]@{ AdministrativeUnit = $Unit; GroupId = $GroupId; Label = 'grp-other' })
                $Item = [PSCustomObject]@{ displayName = 'AU-IT'; members = @(); scopedRoles = $null }
                $Records = @(Invoke-SyncAuViaCaller -Item $Item -Prune -Created $Created -ErrorAction Stop -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
                @($Records | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 2
            }
        }
    }

    # The directory-role name map is what turns a live scoped role's role id into the name the document
    # declares it by. When that read fails the live roles are NOT nameless, they are unread, and -Prune must
    # not read a declared role as undeclared. These tests run the REAL Get-OERAdministrativeUnit and the REAL
    # Get-OERDirectoryRoleNameMap under the handler; only the transport and the lookups are mocked.
    Context 'a directory role name map that cannot be read is an unread scoped-role collection, never an undeclared role' {
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:AuId = '11111111-1111-1111-1111-111111111111'
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { $script:AuId }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Remove-OERAdministrativeUnitScopedRole { }
            }
        }

        It 'reports Failed naming the directory roles read, and adds and removes no scoped role, under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                Mock Invoke-OERGraphRequest {
                    if ($Uri -eq 'v1.0/directoryRoles') { throw 'TooManyRequests (injected map failure)' }
                    if ($Uri -like '*/scopedRoleMembers') {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{
                                    id = 'srm-1'; administrativeUnitId = $script:AuId; roleId = 'dirrole-1'
                                    roleMemberInfo = [PSCustomObject]@{ id = 'p-1'; displayName = 'Person One' }
                                }) }
                    }
                    if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
                    if ($Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)") {
                        return [PSCustomObject]@{ id = $script:AuId; displayName = 'AU-IT' }
                    }
                    throw "unexpected Graph call $Uri"
                }
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                }
                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The map read was reached, so the absence assertions that follow are not vacuous; the
                # Failed row that names the read is asserted after them.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -Match 'failed to read the current state of administrative unit'
                $r[0].Detail | Should -Match 'v1\.0/directoryRoles'
                $r[0].Detail | Should -Match 'injected map failure'
                $null -ne $r[0].Error | Should -BeTrue -Because 'the underlying ErrorRecord travels with the Failed row'
            }
        }

        It 'control: with the name map readable, the declared scoped role is Unchanged and nothing is removed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                Mock Invoke-OERGraphRequest {
                    if ($Uri -eq 'v1.0/directoryRoles') {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'dirrole-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }) }
                    }
                    if ($Uri -like '*/scopedRoleMembers') {
                        return [PSCustomObject]@{ value = @([PSCustomObject]@{
                                    id = 'srm-1'; administrativeUnitId = $script:AuId; roleId = 'dirrole-1'
                                    roleMemberInfo = [PSCustomObject]@{ id = 'p-1'; displayName = 'Person One' }
                                }) }
                    }
                    if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
                    if ($Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)") {
                        return [PSCustomObject]@{ id = $script:AuId; displayName = 'AU-IT' }
                    }
                    throw "unexpected Graph call $Uri"
                }
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                }
                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like "*scopedRole 'User Administrator'*" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
            }
        }

        It 'does not read the name map at all when the entry declares scopedRoles null, so a failing map is not a failure there' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                Mock Invoke-OERGraphRequest {
                    if ($Uri -eq 'v1.0/directoryRoles') { throw 'TooManyRequests (injected map failure)' }
                    if ($Uri -like '*/scopedRoleMembers') { throw 'scopedRoleMembers must not be read for an explicit null scopedRoles' }
                    if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
                    if ($Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)") {
                        return [PSCustomObject]@{ id = $script:AuId; displayName = 'AU-IT' }
                    }
                    throw "unexpected Graph call $Uri"
                }
                $Item = '{ "displayName": "AU-IT", "members": null, "scopedRoles": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)/members" }
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
            }
        }

        # The name map can be READABLE and still not name every live role: the reader does not check that
        # every membership's role id is listed, and a role id the list does not name gets RoleName ''
        # with its RoleId kept. That has not been seen live; this is the defensive case. A role declared
        # by NAME cannot be matched to such a role, yet it may be that very role, so adding the declared
        # role and then pruning the live one (decision A8) would swap a held role for a duplicate. The
        # handler withholds both halves instead.
        Context 'a readable name map that does not name a live role (decision A8)' {
            BeforeEach {
                InModuleScope $script:moduleName {
                    # The directory role list names dirrole-other only; dirrole-1 and dirrole-9 are unnamed.
                    $script:DirectoryRoles = @([PSCustomObject]@{ id = 'dirrole-other'; roleTemplateId = 'tmpl-other'; displayName = 'Reports Reader' })
                    $script:LiveScopedRoleMembers = @()
                    $script:NewScopedRoleMember = {
                        param([string]$Id, [string]$RoleId, [string]$PrincipalId)
                        [PSCustomObject]@{
                            id                   = $Id
                            administrativeUnitId = $script:AuId
                            roleId               = $RoleId
                            roleMemberInfo       = [PSCustomObject]@{ id = $PrincipalId; displayName = "Display $PrincipalId" }
                        }
                    }
                    Mock Resolve-OERStructurePrincipal {
                        param($Reference)
                        switch ($Reference) {
                            'person1@example.com' { 'p-1' }
                            'person2@example.com' { 'p-2' }
                            default { $null }
                        }
                    }
                    Mock Invoke-OERGraphRequest {
                        if ($Uri -eq 'v1.0/directoryRoles') { return [PSCustomObject]@{ value = @($script:DirectoryRoles) } }
                        if ($Uri -like '*/scopedRoleMembers') { return [PSCustomObject]@{ value = @($script:LiveScopedRoleMembers) } }
                        if ($Uri -like '*/members') { return [PSCustomObject]@{ value = @() } }
                        if ($Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)") {
                            return [PSCustomObject]@{ id = $script:AuId; displayName = 'AU-IT' }
                        }
                        throw "unexpected Graph call $Uri"
                    }
                }
            }

            It 'a: withholds the add and the prune, with one Skipped row naming the unnamed role id, under -Prune' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    # The name map was read (so the role really is unnamed, not unread), and the withheld
                    # row exists (so the absence assertions below are not vacuous).
                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Detail | Should -BeLike "prune withheld: scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name*"
                    $Withheld[0].Detail | Should -BeLike "*'dirrole-1'*"
                    $Withheld[0].Detail | Should -BeLike '*Declare the role by the directory role id its live scoped role carries (RoleId in Get-OERAdministrativeUnit -IncludeScopedRoles) to reconcile it.'
                    @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'b: gives the same single withheld row, and no Extra row, without -Prune' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Detail | Should -BeLike "prune withheld: scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name*"
                    $Withheld[0].Detail | Should -BeLike "*'dirrole-1'*"
                    @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'c: plans no add under -WhatIf either, only the one withheld row' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld: *' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Detail | Should -BeLike "*scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name*"
                    @($r | Where-Object { $_.Detail -like 'would add scopedRole*' }).Count | Should -Be 0
                    @($r | Where-Object { $_.Detail -like 'would remove undeclared scopedRole*' }).Count | Should -Be 0
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'd: still prunes another principal''s unnamed role, which no declaration for that principal could be' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(
                        (& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1'),
                        (& $script:NewScopedRoleMember 'srm-9' 'dirrole-9' 'p-2')
                    )
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-9' }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0 -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-1' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Detail | Should -BeLike "prune withheld: scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name*'dirrole-1'*"
                    $Withheld[0].Detail | Should -Not -BeLike "*'dirrole-9'*"
                    $Removed = @($r | Where-Object { $_.Action -eq 'Removed' })
                    $Removed.Count | Should -Be 1
                    $Removed[0].Detail | Should -BeLike "*(principal 'p-2')"
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'e: prunes the same principal''s NAMED undeclared role once and leaves its unnamed role alone' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(
                        (& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1'),
                        (& $script:NewScopedRoleMember 'srm-2' 'dirrole-other' 'p-1')
                    )
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-2' }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0 -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-1' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Detail | Should -BeLike "prune withheld: scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name*(role id 'dirrole-1')*"
                    $Removed = @($r | Where-Object { $_.Action -eq 'Removed' })
                    $Removed.Count | Should -Be 1
                    $Removed[0].Detail | Should -Be "removed undeclared scopedRole 'Reports Reader' (principal 'p-1')"
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'g: leaves today''s behaviour alone when a NAMED live role matches the declaration, and still prunes the unnamed one' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    # This time the directory role list names dirrole-other as the declared role.
                    $script:DirectoryRoles = @([PSCustomObject]@{ id = 'dirrole-other'; roleTemplateId = 'tmpl-other'; displayName = 'User Administrator' })
                    $script:LiveScopedRoleMembers = @(
                        (& $script:NewScopedRoleMember 'srm-2' 'dirrole-other' 'p-1'),
                        (& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    )
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "scopedRole 'User Administrator' for 'person1@example.com' already present" }).Count | Should -Be 1
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-1' }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0 -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-2' }
                    @($r | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                    @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'h: gives one withheld row per declared name, each naming the principal''s unnamed role' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @(
                            [PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' },
                            [PSCustomObject]@{ role = 'Helpdesk Administrator'; principal = 'person1@example.com' }
                        )
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 2
                    @($Withheld | Where-Object { $_.Detail -like "*scopedRole 'User Administrator' for 'person1@example.com'*'dirrole-1'*" }).Count | Should -Be 1
                    @($Withheld | Where-Object { $_.Detail -like "*scopedRole 'Helpdesk Administrator' for 'person1@example.com'*'dirrole-1'*" }).Count | Should -Be 1
                    @($r | Where-Object { $_.Action -in 'Removed', 'Extra', 'Updated', 'Failed' }).Count | Should -Be 0
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
                }
            }

            It 'i: still adds a role declared by its role id, and prunes the unnamed live role, since the id declaration does not match a role the map does not name' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' 'dirrole-1' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = '22222222-2222-2222-2222-222222222222'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter {
                        $RoleId -eq '22222222-2222-2222-2222-222222222222' -and $PrincipalId -eq 'p-1'
                    }
                    Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter { $ScopedRoleMembershipId -eq 'srm-1' }
                    @($r | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                    @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                    @($r | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
                }
            }

            It 'j: does not claim a live role whose role id is blank as well, since there is no id to name it by' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    # A malformed membership: no roleId at all, so neither the map nor the handler can name it.
                    $script:LiveScopedRoleMembers = @(& $script:NewScopedRoleMember 'srm-1' '' 'p-1')
                    $Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        members     = $null
                        scopedRoles = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person1@example.com' })
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 1 -Exactly -ParameterFilter {
                        $RoleName -eq 'User Administrator' -and $PrincipalId -eq 'p-1'
                    }
                    @($r | Where-Object { $_.Detail -like 'prune withheld: *' }).Count | Should -Be 0
                    @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                }
            }
        }
    }

    # Decision A16 (finding F1): one directory role has two ids, its directoryRole object id and its role
    # template id, and Graph may store a scoped role membership under the other id than the one the
    # document declared. Get-OERDirectoryRoleNameMap keys an activated role by both ids, so a declared GUID
    # and a live RoleId the map gives the same name are the same role. These tests run the REAL
    # Get-OERAdministrativeUnit, Get-OERDirectoryRoleNameMap, Add-OERAdministrativeUnitScopedRole and
    # Remove-OERAdministrativeUnitScopedRole under the handler; only the transport, Initialize-OERAuth and
    # the two lookups are mocked. The transport simulates the tenant in $script: state, so a second run
    # sees what the first one wrote.
    Context 'a scoped role declared by GUID matches through the directory role name map (decision A16)' {
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:AuId = '11111111-1111-1111-1111-111111111111'
                $script:A16RolesUri = "v1.0/directory/administrativeUnits/$($script:AuId)/scopedRoleMembers"
                $script:A16UserAdministrator = [PSCustomObject]@{
                    id = 'aaaaaaaa-0000-0000-0000-000000000001'; roleTemplateId = 'bbbbbbbb-0000-0000-0000-000000000002'; displayName = 'User Administrator'
                }
                $script:A16ReportsReader = [PSCustomObject]@{
                    id = 'aaaaaaaa-0000-0000-0000-000000000011'; roleTemplateId = 'bbbbbbbb-0000-0000-0000-000000000012'; displayName = 'Reports Reader'
                }
                $script:A16DirectoryRoles = @($script:A16UserAdministrator)
                $script:A16Memberships = [System.Collections.Generic.List[object]]::new()
                # 'ObjectId': Graph stores a posted template id as the role's object id (an object id
                # stays). 'TemplateId': Graph stores a posted object id as the role's template id.
                $script:A16Premise = 'ObjectId'
                $script:A16NextMembership = 0
                $script:A16DirectoryRoleReads = 0
                # The directoryRoles read with this sequence number throws (0: none does).
                $script:A16FailDirectoryRoleRead = 0
                # The unit's live members, as the members list answers them (none by default).
                $script:A16LiveMembers = @()
                $script:A16Declared = $null
                $script:A16NewMembership = {
                    param([string]$Id, [string]$RoleId, [string]$PrincipalId)
                    [PSCustomObject]@{
                        id                   = $Id
                        administrativeUnitId = $script:AuId
                        roleId               = $RoleId
                        roleMemberInfo       = [PSCustomObject]@{ id = $PrincipalId; displayName = "Display $PrincipalId" }
                    }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { $script:AuId }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference)
                    switch ($Reference) {
                        'person1@example.com' { 'cccccccc-0000-0000-0000-000000000003' }
                        'person2@example.com' { 'cccccccc-0000-0000-0000-000000000013' }
                        default { $null }
                    }
                }
                Mock Invoke-OERGraphRequest {
                    $Verb = if ($Method) { $Method.ToUpperInvariant() } else { 'GET' }
                    if ($Verb -eq 'GET' -and $Uri -eq 'v1.0/directoryRoles') {
                        $script:A16DirectoryRoleReads++
                        if ($script:A16DirectoryRoleReads -eq $script:A16FailDirectoryRoleRead) { throw 'TooManyRequests (injected map failure)' }
                        return [PSCustomObject]@{ value = @($script:A16DirectoryRoles) }
                    }
                    if ($Verb -eq 'GET' -and $Uri -eq $script:A16RolesUri) {
                        return [PSCustomObject]@{ value = @($script:A16Memberships) }
                    }
                    if ($Verb -eq 'POST' -and $Uri -eq $script:A16RolesUri) {
                        $Posted = [string]$Body.roleId
                        $Known = @($script:A16DirectoryRoles | Where-Object { $_.id -eq $Posted -or $_.roleTemplateId -eq $Posted }) | Select-Object -First 1
                        $Stored = $Posted
                        if ($Known -and $script:A16Premise -eq 'ObjectId') { $Stored = [string]$Known.id }
                        if ($Known -and $script:A16Premise -eq 'TemplateId') { $Stored = [string]$Known.roleTemplateId }
                        $script:A16NextMembership++
                        $Membership = & $script:A16NewMembership "srm-$($script:A16NextMembership)" $Stored ([string]$Body.roleMemberInfo.id)
                        $script:A16Memberships.Add($Membership)
                        return $Membership
                    }
                    if ($Verb -eq 'DELETE' -and $Uri -like "$($script:A16RolesUri)/*") {
                        $MembershipId = $Uri.Substring($script:A16RolesUri.Length + 1)
                        $Existing = @($script:A16Memberships | Where-Object { $_.id -eq $MembershipId }) | Select-Object -First 1
                        if (-not $Existing) { throw "unexpected Graph call DELETE of an unknown membership $Uri" }
                        $null = $script:A16Memberships.Remove($Existing)
                        return $null
                    }
                    if ($Verb -eq 'GET' -and $Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)/members") {
                        return [PSCustomObject]@{ value = @($script:A16LiveMembers) }
                    }
                    if ($Verb -eq 'GET' -and $Uri -eq "v1.0/directory/administrativeUnits/$($script:AuId)") {
                        return [PSCustomObject]@{ id = $script:AuId; displayName = 'AU-IT' }
                    }
                    throw "unexpected Graph call $Verb $Uri"
                }
            }
        }

        It '1: Graph stores the <Stores>, the role is declared by its <Form>: run 1 adds it once and run 2 leaves it alone under -Prune' -ForEach @(
            # Finding F1 exactly: the document declares the template id, Graph stores the object id.
            @{ Premise = 'ObjectId'; Stores = 'object id'; Form = 'template id'; Declared = 'bbbbbbbb-0000-0000-0000-000000000002'; Stored = 'aaaaaaaa-0000-0000-0000-000000000001' }
            @{ Premise = 'ObjectId'; Stores = 'object id'; Form = 'object id'; Declared = 'aaaaaaaa-0000-0000-0000-000000000001'; Stored = 'aaaaaaaa-0000-0000-0000-000000000001' }
            @{ Premise = 'TemplateId'; Stores = 'template id'; Form = 'template id'; Declared = 'bbbbbbbb-0000-0000-0000-000000000002'; Stored = 'bbbbbbbb-0000-0000-0000-000000000002' }
            @{ Premise = 'TemplateId'; Stores = 'template id'; Form = 'object id'; Declared = 'aaaaaaaa-0000-0000-0000-000000000001'; Stored = 'bbbbbbbb-0000-0000-0000-000000000002' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Premise = $Premise; Declared = $Declared; Stored = $Stored } {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                $script:A16Premise = $Premise
                $script:A16Declared = $Declared
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @([PSCustomObject]@{ role = $Declared; principal = 'person1@example.com' })
                }

                $r1 = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err1)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Uri -eq $script:A16RolesUri -and $Body.roleId -eq $script:A16Declared
                }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
                @($r1 | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added scopedRole '$Declared' for 'person1@example.com'" }).Count | Should -Be 1
                @($r1 | Where-Object { $_.Action -in 'Removed', 'Extra', 'Failed', 'Skipped' }).Count | Should -Be 0
                @($Err1).Count | Should -Be 0
                # The premise took effect: the tenant holds the membership under the id it stores.
                $script:A16Memberships.Count | Should -Be 1
                $script:A16Memberships[0].roleId | Should -BeExactly $Stored

                $r2 = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err2)

                # Run 2 neither adds nor removes. It matched the live role (the Unchanged row below), so these
                # absence assertions are not vacuous.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
                @($r2 | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "scopedRole '$Declared' for 'person1@example.com' already present" }).Count | Should -Be 1
                @($r2 | Where-Object { $_.Action -in 'Removed', 'Extra', 'Failed', 'Skipped', 'Updated' }).Count | Should -Be 0
                @($Err2).Count | Should -Be 0
                $script:A16Memberships.Count | Should -Be 1
                $script:A16Memberships[0].roleId | Should -BeExactly $Stored
            }
        }

        It '2: the F1 case without -Prune on run 2 reports the role Unchanged and no Extra row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                $script:A16Premise = 'ObjectId'
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @([PSCustomObject]@{ role = 'bbbbbbbb-0000-0000-0000-000000000002'; principal = 'person1@example.com' })
                }

                $r1 = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                @($r1 | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                $script:A16Memberships[0].roleId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'

                $r2 = @(Invoke-SyncAuViaCaller -Item $Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                # The Unchanged row proves run 2 reached the live role, so the absence assertions are not vacuous.
                @($r2 | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
                @($r2 | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "scopedRole 'bbbbbbbb-0000-0000-0000-000000000002' for 'person1@example.com' already present" }).Count | Should -Be 1
                @($r2 | Where-Object { $_.Action -in 'Removed', 'Failed', 'Skipped', 'Updated' }).Count | Should -Be 0
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
                $script:A16Memberships.Count | Should -Be 1
            }
        }

        It '3: a declared GUID the map does not name is added, and the live role is pruned, as before' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                $script:A16Memberships.Add((& $script:A16NewMembership 'srm-seed-1' 'aaaaaaaa-0000-0000-0000-000000000001' 'cccccccc-0000-0000-0000-000000000003'))
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @([PSCustomObject]@{ role = 'dddddddd-0000-0000-0000-000000000004'; principal = 'person1@example.com' })
                }

                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.roleId -eq 'dddddddd-0000-0000-0000-000000000004'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Uri -eq "$($script:A16RolesUri)/srm-seed-1"
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
                # The gate opened, so the handler did read the map and the GUID still matched nothing: the
                # reader's read, the handler's read and the real Add's best-effort read after its POST.
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared scopedRole 'User Administrator' (principal 'cccccccc-0000-0000-0000-000000000003')" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -in 'Failed', 'Skipped', 'Extra' }).Count | Should -Be 0
                $script:A16Memberships.Count | Should -Be 1
                [string]$script:A16Memberships[0].roleId | Should -BeExactly 'dddddddd-0000-0000-0000-000000000004'
            }
        }

        It '4: a declared GUID the map names differently from the live role is added, and the live role is pruned, as before' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                $script:A16DirectoryRoles = @($script:A16UserAdministrator, $script:A16ReportsReader)
                $script:A16Memberships.Add((& $script:A16NewMembership 'srm-seed-1' 'aaaaaaaa-0000-0000-0000-000000000001' 'cccccccc-0000-0000-0000-000000000003'))
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    # Reports Reader's template id, while the live membership carries User Administrator's object id.
                    scopedRoles = @([PSCustomObject]@{ role = 'bbbbbbbb-0000-0000-0000-000000000012'; principal = 'person1@example.com' })
                }

                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.roleId -eq 'bbbbbbbb-0000-0000-0000-000000000012'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Uri -eq "$($script:A16RolesUri)/srm-seed-1"
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
                # The gate opened, so the handler did read the map and the two names still differed: the
                # reader's read, the handler's read and the real Add's best-effort read after its POST.
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared scopedRole 'User Administrator' (principal 'cccccccc-0000-0000-0000-000000000003')" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -in 'Failed', 'Skipped', 'Extra' }).Count | Should -Be 0
                $script:A16Memberships.Count | Should -Be 1
                [string]$script:A16Memberships[0].roleId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000011'
            }
        }

        It '5: a name looked up without a key is never a match: a declared GUID and an unnamed live role, neither in the map, are added and pruned' {
            InModuleScope $script:moduleName {
                function Invoke-SyncAuViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                }
                # person1 holds a role the map does not name; person2 holds a named User Administrator
                # membership, declared by name, which opens the gate of the handler's map read.
                $script:A16Memberships.Add((& $script:A16NewMembership 'srm-seed-1' 'eeeeeeee-0000-0000-0000-000000000005' 'cccccccc-0000-0000-0000-000000000003'))
                $script:A16Memberships.Add((& $script:A16NewMembership 'srm-seed-2' 'aaaaaaaa-0000-0000-0000-000000000001' 'cccccccc-0000-0000-0000-000000000013'))
                $Item = [PSCustomObject]@{
                    displayName = 'AU-IT'
                    members     = $null
                    scopedRoles = @(
                        [PSCustomObject]@{ role = 'dddddddd-0000-0000-0000-000000000004'; principal = 'person1@example.com' },
                        [PSCustomObject]@{ role = 'User Administrator'; principal = 'person2@example.com' }
                    )
                }

                $r = @(Invoke-SyncAuViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.roleId -eq 'dddddddd-0000-0000-0000-000000000004' -and
                    $Body.roleMemberInfo.id -eq 'cccccccc-0000-0000-0000-000000000003'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'DELETE' -and $Uri -eq "$($script:A16RolesUri)/srm-seed-1"
                }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
                # The gate opened, so the map was there to be misread: the reader's read, the handler's
                # read and the real Add's best-effort read after its POST (measured).
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "scopedRole 'User Administrator' for 'person2@example.com' already present" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added scopedRole 'dddddddd-0000-0000-0000-000000000004' for 'person1@example.com'" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -like "*(principal 'cccccccc-0000-0000-0000-000000000003')" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -in 'Failed', 'Skipped', 'Extra' }).Count | Should -Be 0
                @($script:A16Memberships | Where-Object { $_.id -eq 'srm-seed-2' }).Count | Should -Be 1
            }
        }

        # BL-47 (R-7): the handler's own read of the name map fails (the reader's read, the first, succeeds
        # and names the live role). Only the scopedRoles collection stops: the unit's property PATCH, its
        # member add and its member prune are made as usual. The seeded live role is the one a null map
        # would get wrong: declared by its template id while the live membership carries the object id, it
        # would be added a second time and the live entry pruned.
        Context 'the handler''s map read fails (BL-47)' {
            BeforeEach {
                InModuleScope $script:moduleName {
                    Mock Remove-OERErrorRecord { }
                    Mock Set-OERAdministrativeUnit { }
                    Mock Add-OERAdministrativeUnitMember { }
                    Mock Remove-OERAdministrativeUnitMember { }
                    # The reader's read (the first) succeeds and names the live role; the handler's (the
                    # second) fails.
                    $script:A16FailDirectoryRoleRead = 2
                    $script:A16LiveMembers = @([PSCustomObject]@{
                            id = 'cccccccc-0000-0000-0000-000000000099'; displayName = 'Live member'; '@odata.type' = '#microsoft.graph.user'
                        })
                    $script:A16Memberships.Add((& $script:A16NewMembership 'srm-seed-1' 'aaaaaaaa-0000-0000-0000-000000000001' 'cccccccc-0000-0000-0000-000000000003'))
                    $script:A16Item = [PSCustomObject]@{
                        displayName = 'AU-IT'
                        # Differs from the live unit, which has none: a property PATCH follows the read.
                        description = 'A16 drifted description'
                        # Not a live member of the unit: a member add follows the read.
                        members     = @('person2@example.com')
                        scopedRoles = @([PSCustomObject]@{ role = 'bbbbbbbb-0000-0000-0000-000000000002'; principal = 'person1@example.com' })
                    }
                }
            }

            It '6: stops only the scopedRoles under -Prune: the property update, the member add and the member prune are made, one Failed row carries the record, and no scoped role is added or removed' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $script:A16Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                    # Both reads were reached, so the absence assertions below are not vacuous.
                    Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    # Properties and members run as usual.
                    Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $Id -eq $script:AuId -and $Description -eq 'A16 drifted description' }
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'cccccccc-0000-0000-0000-000000000013' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'cccccccc-0000-0000-0000-000000000099' }
                    @($r | ForEach-Object { $_.Action }) | Should -BeExactly @('Updated', 'Updated', 'Removed', 'Failed')
                    # No scoped role is added or removed: the transport saw no POST and no DELETE, and the
                    # seeded membership stands.
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
                    $script:A16Memberships.Count | Should -Be 1
                    [string]$script:A16Memberships[0].id | Should -BeExactly 'srm-seed-1'
                    # Exactly one row speaks of a scopedRole: the Failed row, last.
                    $Rows = @($r | Where-Object { $_.Detail -like '*scopedRole*' })
                    $Rows.Count | Should -Be 1
                    $Rows[0] | Should -Be $r[-1]
                    $r[-1].Action | Should -BeExactly 'Failed'
                    $r[-1].Detail | Should -BeLike 'failed to read the directory roles that match a scopedRole declared by role id: *injected map failure*; no scopedRole change was made'
                    $r[-1].Detail | Should -Not -BeLike '*property, member*'
                    $null -ne $r[-1].Error | Should -BeTrue -Because 'the published ErrorRecord travels with the Failed row'
                    $r[-1].Error.FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitScopedRoleReadFailed*'
                    $r[-1].Error.Exception.Message | Should -BeLike "*'v1.0/directoryRoles'*injected map failure*"
                    # One record is published, under the error id an unread scoped role collection already
                    # has. -ErrorVariable also collects every exception thrown and caught on the way
                    # (measured); a record the caller PUBLISHED carries the caller's name in its
                    # FullyQualifiedErrorId.
                    $Published = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncAuViaCaller' })
                    $Published.Count | Should -Be 1
                    $Published[0].FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitScopedRoleReadFailed*'
                    $Published[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ReadError)
                    [string]$Published[0].TargetObject | Should -BeExactly $script:AuId
                    $Published[0].Exception.Message | Should -BeLike "Could not read scoped roles for administrative unit $($script:AuId): *injected map failure*. No scopedRole change was made."
                    $Published[0].Exception.InnerException.Message | Should -BeLike "Could not read the directory roles ('v1.0/directoryRoles')*injected map failure*"
                    # The caught record was scrubbed before the handler published its own.
                    Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                        $Record.Exception.Message -like "Could not read the directory roles ('v1.0/directoryRoles')*injected map failure*"
                    }
                }
            }

            It '7: plans the property update, the member add and the member removal under -WhatIf, with the same one Failed row and nothing sent' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $script:A16Item -Prune -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                    Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    @($r | ForEach-Object { $_.Action }) | Should -BeExactly @('Skipped', 'Skipped', 'Skipped', 'Failed')
                    $r[0].Detail | Should -BeLike 'would update administrative unit properties (Description)'
                    $r[1].Detail | Should -BeLike "would add member 'person2@example.com'"
                    $r[2].Detail | Should -BeLike "would remove undeclared member 'cccccccc-0000-0000-0000-000000000099'"
                    $r[3].Detail | Should -BeLike 'failed to read the directory roles that match a scopedRole declared by role id: *injected map failure*; no scopedRole change was made'
                    $r[3].Error.FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitScopedRoleReadFailed*'
                    @($r | Where-Object { $_.Detail -like '*scopedRole*' }).Count | Should -Be 1
                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in 'POST', 'DELETE', 'PATCH' }
                    $Published = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncAuViaCaller' })
                    $Published.Count | Should -Be 1
                    $Published[0].FullyQualifiedErrorId | Should -BeLike 'AdministrativeUnitScopedRoleReadFailed*'
                    $script:A16Memberships.Count | Should -Be 1
                }
            }

            It '8: without -Prune, applies the property update and the member add, reports the live member Extra, and reports no scoped role at all but the one Failed row' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $r = @(Invoke-SyncAuViaCaller -Item $script:A16Item -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                    Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
                    Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'cccccccc-0000-0000-0000-000000000013' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                    @($r | ForEach-Object { $_.Action }) | Should -BeExactly @('Updated', 'Updated', 'Extra', 'Failed')
                    @($r | Where-Object { $_.Detail -like '*scopedRole*' }).Count | Should -Be 1
                    @($r | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -like '*scopedRole*' }).Count | Should -Be 0
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in 'POST', 'DELETE', 'PATCH' }
                    @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'AdministrativeUnitScopedRoleReadFailed*,Invoke-SyncAuViaCaller' }).Count | Should -Be 1
                }
            }

            It '9: control: with the map readable, the same document adds the declared template id and prunes the live object id it does not match (so the writes the stop prevents are real)' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncAuViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    # Same document, with the map readable: its two ids name the same role, so the declared
                    # template id MATCHES the live object id and the scopedRoles step runs to Unchanged.
                    # A map taken as null matches neither, which is the add and the prune a failed read
                    # must not make.
                    $script:A16FailDirectoryRoleRead = 0
                    $r = @(Invoke-SyncAuViaCaller -Item $script:A16Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "scopedRole 'bbbbbbbb-0000-0000-0000-000000000002' for 'person1@example.com' already present" }).Count | Should -Be 1
                    @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                    Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 1 -Exactly
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly
                    Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in 'POST', 'DELETE' }
                    @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Invoke-SyncAuViaCaller' }).Count | Should -Be 0
                }
            }
        }
    }

    Context 'a membership type change: the plan shows the warning a real run gives, and a run writes it once (BL-17)' {
        # Set-OERAdministrativeUnit warns about a membership type change. Under -WhatIf the engine never
        # calls it, so the handler writes the cmdlet's own text before its gate -- and only under -WhatIf:
        # a real run calls the cmdlet, which writes it, and a copy from the handler would warn twice. The
        # warnings are counted from the stream (3>&1), with -WarningAction Continue pinned on the call.
        # In the real runs below Set-OERAdministrativeUnit runs for REAL: only auth, the unit lookup, the
        # handler's own read and the Graph transport are mocked.
        BeforeAll {
            $script:AuWarnText = "Changing the membership type of administrative unit '11111111-1111-1111-1111-1111111111a1' to 'Dynamic'. " +
                "The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership " +
                'and members can no longer be added or removed manually.'
            InModuleScope $script:moduleName {
                function script:Invoke-SyncAuWarnViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet
                }
                # One run of the handler: its rows, and the text of every warning that reached the stream.
                function script:Invoke-AuWarnCapture {
                    param([PSCustomObject]$Item, [bool]$WhatIfRun)
                    $All = @(Invoke-SyncAuWarnViaCaller -Item $Item -WhatIf:$WhatIfRun -Confirm:$false -WarningAction Continue -ErrorAction Stop 3>&1)
                    [PSCustomObject]@{
                        Rows     = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
                        Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                    }
                }
            }
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth {}
                Mock Resolve-OERAdministrativeUnitId { '11111111-1111-1111-1111-1111111111a1' }
                Mock Get-OERAdministrativeUnit {
                    $Au = [PSCustomObject]@{
                        Id                            = '11111111-1111-1111-1111-1111111111a1'
                        DisplayName                   = 'AU-Warn'
                        Description                   = 'old'
                        MembershipType                = 'Assigned'
                        MembershipRule                = $null
                        MembershipRuleProcessingState = $null
                        IsMemberManagementRestricted  = $false
                        Visibility                    = $null
                    }
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $Au
                }
                # The real cmdlet's PATCH and its read-back. Anything else is not simulated and throws.
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'PATCH') { return $null }
                    if ($Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-1111111111a1') {
                        return @{ id = '11111111-1111-1111-1111-1111111111a1'; displayName = 'AU-Warn'; membershipType = 'Dynamic' }
                    }
                    throw "unexpected $Method $Uri"
                }
            }
        }

        It 'writes the warning of Set-OERAdministrativeUnit once under -WhatIf, before the gate, and never calls the cmdlet' {
            InModuleScope $script:moduleName -Parameters @{ Expected = $script:AuWarnText } {
                param($Expected)
                Mock Set-OERAdministrativeUnit {}
                $Item = [PSCustomObject]@{ displayName = 'AU-Warn'; dynamic = $true; membershipRule = '(user.department -eq "HR")'; members = $null; scopedRoles = $null }
                $Out = Invoke-AuWarnCapture -Item $Item -WhatIfRun $true
                # Reached: the gate declined and the plan row was written.
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would update administrative unit properties (*MembershipType*' }).Count | Should -Be 1
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                $Out.Warnings.Count | Should -Be 1
                $Out.Warnings[0] | Should -BeExactly $Expected
            }
        }

        It 'writes it once in a real run, from the real Set-OERAdministrativeUnit, with the same text as the -WhatIf plan' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{ displayName = 'AU-Warn'; dynamic = $true; membershipRule = '(user.department -eq "HR")'; members = $null; scopedRoles = $null }
                $Plan = Invoke-AuWarnCapture -Item $Item -WhatIfRun $true
                # The plan wrote nothing.
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
                $Run = Invoke-AuWarnCapture -Item $Item -WhatIfRun $false
                # Reached: the real cmdlet passed its own gate and sent the membership type.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.membershipType -eq 'Dynamic' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                $Plan.Warnings.Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 1 -Because 'a real run must warn once, from the cmdlet, never also from the handler'
                ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
            }
        }

        It 'writes no warning in either mode when the membership type does not change' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{ displayName = 'AU-Warn'; description = 'new'; members = $null; scopedRoles = $null }
                $Plan = Invoke-AuWarnCapture -Item $Item -WhatIfRun $true
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would update administrative unit properties (Description)' }).Count | Should -Be 1
                $Plan.Warnings.Count | Should -Be 0
                $Run = Invoke-AuWarnCapture -Item $Item -WhatIfRun $false
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.description -eq 'new' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 0
            }
        }
    }

    Context 'previousDisplayName (BL-128)' {
        # A rename through the document (decision A5): displayName is the name the unit is to carry and
        # previousDisplayName the one it carries now, or its object id. Both names are resolved before
        # anything is read or written, on every run; Resolve-OERStructureRename owns the decision, the
        # error ids and the texts. The unit found under the previous name takes the existing-unit path and
        # the rename travels in the SAME Set-OERAdministrativeUnit call as every other changed property.
        # Resolve-OERAdministrativeUnitId gets one FILTERED mock per name that resolves; every other name
        # falls to the unfiltered mock, which finds nothing. The only Graph request the handler sends
        # itself is the probe of a previous name that is an object id: any other reach is refused.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncAuRenameViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param(
                        [PSCustomObject]$Item,
                        [switch]$Prune,
                        [switch]$EnsureOnly,
                        [System.Collections.Generic.Dictionary[string, object]]$RenameMap,
                        [System.Collections.Generic.List[object]]$Created
                    )
                    $Extra = @{}
                    if ($PSBoundParameters.ContainsKey('RenameMap')) { $Extra.RenameMap = $RenameMap }
                    if ($PSBoundParameters.ContainsKey('Created')) { $Extra.CreatedUnitMembership = $Created }
                    Sync-OERStructureAdministrativeUnit -Item $Item -Caller $PSCmdlet -Prune:$Prune -EnsureOnly:$EnsureOnly @Extra
                }
            }
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth { }
                Mock Resolve-OERAdministrativeUnitId { $null }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                Mock Get-OERAdministrativeUnit {
                    param($AdministrativeUnit)
                    [PSCustomObject]@{
                        Id = $AdministrativeUnit; DisplayName = 'AU-Old'; Description = 'old desc'; MembershipType = 'Assigned'
                        Visibility = $null; IsMemberManagementRestricted = $false; Members = @(); ScopedRoles = @()
                    }
                }
                Mock Set-OERAdministrativeUnit { }
                Mock New-OERAdministrativeUnit { [PSCustomObject]@{ Id = 'au-created'; DisplayName = 'AU-New' } }
                Mock Add-OERAdministrativeUnitMember { }
                Mock Remove-OERAdministrativeUnitMember { }
                Mock Add-OERAdministrativeUnitScopedRole { }
                Mock Remove-OERAdministrativeUnitScopedRole { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            }
        }

        It 'renames the unit found only under its previous name in the same Set-OERAdministrativeUnit call as a changed property, and reconciles its children against that unit' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{
                    displayName         = 'AU-New'
                    previousDisplayName = 'AU-Old'
                    description         = 'new desc'
                    members             = @('person9@example.com')
                    scopedRoles         = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
                }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter {
                    $Id -eq 'au-old-id' -and $NewDisplayName -eq 'AU-New' -and $Description -eq 'new desc'
                }
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1
                Should -Invoke New-OERAdministrativeUnit -Times 0
                # Both names were resolved, once each, and the unit found under the PREVIOUS name was read.
                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-Old' }
                Should -Invoke Get-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' }
                Should -Invoke Get-OERAdministrativeUnit -Exactly -Times 1
                # The children are reconciled against the same unit.
                Should -Invoke Add-OERAdministrativeUnitMember -Exactly -Times 1 -ParameterFilter {
                    $Id -eq 'au-old-id' -and $MemberId -eq 'id-person9@example.com'
                }
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Exactly -Times 1 -ParameterFilter {
                    $Id -eq 'au-old-id' -and $RoleName -eq 'User Administrator'
                }
                @($Err).Count | Should -Be 0
                # The rename, the member and the scoped role: three rows, one of them the rename.
                @($r).Count | Should -Be 3
                $Rename = @($r | Where-Object { $_.Detail -like 'renamed*' })
                $Rename.Count | Should -Be 1
                $Rename[0].Section | Should -BeExactly 'administrativeUnits'
                $Rename[0].Item | Should -BeExactly 'AU-New'
                $Rename[0].Action | Should -BeExactly 'Updated'
                $Rename[0].Detail | Should -BeExactly "renamed administrative unit 'AU-Old' to 'AU-New'; updated administrative unit properties (Description)"
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added member 'person9@example.com'" }).Count | Should -Be 1
            }
        }

        It 'reports a rename with no other change as one Updated row and no properties-match row' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'old desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' -and $NewDisplayName -eq 'AU-New' -and -not $Description }
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed administrative unit 'AU-Old' to 'AU-New'"
                @($r | Where-Object { $_.Detail -eq 'administrative unit properties match' }).Count | Should -Be 0
            }
        }

        It 'reports Unchanged and sends no rename on the run after the rename, with previousDisplayName still declared' {
            InModuleScope $script:moduleName {
                # After the rename only the new name resolves; the old one finds nothing.
                Mock Resolve-OERAdministrativeUnitId { 'au-id' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'old desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-Old' }
                Should -Invoke Get-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-id' }
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke New-OERAdministrativeUnit -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'administrative unit properties match'
            }
        }

        It 'takes the normal path, with no rename and no failure, when both names resolve to the same unit (a case-only rename)' {
            InModuleScope $script:moduleName {
                # Graph matches displayName case-insensitively, so a previous name that differs from the
                # new one only in case finds the very unit the new name finds.
                Mock Resolve-OERAdministrativeUnitId { 'au-1' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'au-new'; description = 'old desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke New-OERAdministrativeUnit -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'administrative unit properties match'
            }
        }

        It 'fails the item with one row and an AdministrativeUnitRenameConflict error, reading and writing nothing, when both names exist as different units' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-a' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                Mock Resolve-OERAdministrativeUnitId { 'au-b' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                # Every collection and a changed property are declared, so a missing guard has something
                # to read, reconcile and write.
                $Item = [PSCustomObject]@{
                    displayName         = 'AU-New'
                    previousDisplayName = 'AU-Old'
                    description         = 'new desc'
                    members             = @('person9@example.com')
                    scopedRoles         = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
                }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -Prune -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The ONLY row the item emits.
                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'administrativeUnits'
                $r[0].Item | Should -BeExactly 'AU-New'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "both 'AU-New' and its previousDisplayName 'AU-Old' exist as different administrative units; the document never merges two administrative units, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AdministrativeUnitRenameConflict'

                Should -Invoke Get-OERAdministrativeUnit -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0

                # The row carries the record either way; only the caller's -ErrorVariable proves it was
                # published through $Caller.WriteError.
                @($Err).Count | Should -Be 1
                $Conflict = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AdministrativeUnitRenameConflict,*' })
                $Conflict.Count | Should -Be 1
                $Conflict[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
                $Conflict[0].TargetObject | Should -BeExactly 'AU-New'
            }
        }

        It 'fails with AdministrativeUnitRenameNotFound, creating nothing, when neither name resolves' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{
                    displayName         = 'AU-New'
                    previousDisplayName = 'AU-Old'
                    members             = @('person9@example.com')
                }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Item | Should -BeExactly 'AU-New'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'AU-New' nor its previousDisplayName 'AU-Old' matches an administrative unit, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new administrative unit, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AdministrativeUnitRenameNotFound'
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Get-OERAdministrativeUnit -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                $NotFound = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AdministrativeUnitRenameNotFound,*' })
                @($Err).Count | Should -Be 1
                $NotFound.Count | Should -Be 1
                $NotFound[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $NotFound[0].TargetObject | Should -BeExactly 'AU-New'
            }
        }

        It 'under -WhatIf reports the same single Failed row and no would-create row when neither name resolves' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; members = @('person9@example.com') }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AdministrativeUnitRenameNotFound'
                @($r | Where-Object { [string]$_.Detail -like 'would create*' }).Count | Should -Be 0
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AdministrativeUnitRenameNotFound,*' }).Count | Should -Be 1
                Should -Invoke New-OERAdministrativeUnit -Times 0
            }
        }

        # previousDisplayName may be the unit's object id. Resolve-OERAdministrativeUnitId would look an id
        # up as a display name, so the handler verifies the id with one read of its own: an id that names
        # no unit must count as not matching, never as a second unit.
        It 'looks a previous name that is an object id up by one probe, declared to the transport, and never as a display name' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111' } } -ParameterFilter {
                    $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id'
                }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # ONE existence read, declaring the not-found answers to the transport.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id' -and
                    @($ExpectedErrorCode) -contains 'Request_ResourceNotFound' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke Resolve-OERAdministrativeUnitId -Times 0 -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter {
                    $Id -eq '11111111-1111-1111-1111-111111111111' -and $NewDisplayName -eq 'AU-New' -and $Description -eq 'new desc'
                }
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1
                Should -Invoke New-OERAdministrativeUnit -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed administrative unit '11111111-1111-1111-1111-111111111111' to 'AU-New'; updated administrative unit properties (Description)"
            }
        }

        It 'treats an object id that names no unit as not matching: displayName absent is AdministrativeUnitRenameNotFound, creating nothing' {
            InModuleScope $script:moduleName {
                # What Invoke-OERGraphRequest returns for a declared not-found answer.
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'Resource does not exist.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id' }
                # A stale id of a deleted unit: reading it as the unit to rename would fail here.
                Mock Get-OERAdministrativeUnit { throw "Resource '11111111-1111-1111-1111-111111111111' does not exist." }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The id WAS checked -- one existence read -- and found to name no unit.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id' }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'AU-New' nor its previousDisplayName '11111111-1111-1111-1111-111111111111' matches an administrative unit, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new administrative unit, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^AdministrativeUnitRenameNotFound'
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Get-OERAdministrativeUnit -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
            }
        }

        It 'treats an object id that names no unit as not matching: displayName present is a normal update, with no conflict and no rename' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-id' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404; Message = 'Resource does not exist.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-id' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1
                Should -Invoke New-OERAdministrativeUnit -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly 'updated administrative unit properties (Description)'
            }
        }

        It 'throws, creating and writing nothing, when the probe of an object id fails with anything but not-found' {
            InModuleScope $script:moduleName {
                # A 403 is no evidence that the unit does not exist: the transport throws it, the handler
                # does not catch it, and the engine reports the item Failed ("handler error").
                Mock Invoke-OERGraphRequest { throw 'graph 403' } -ParameterFilter {
                    $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id'
                }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }

                { Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue } | Should -Throw -ExpectedMessage '*graph 403*'
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Get-OERAdministrativeUnit -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
            }
        }

        It 'throws, creating and renaming nothing, when the previous name matches several units' {
            InModuleScope $script:moduleName {
                # The record Resolve-OERAdministrativeUnitId itself throws for a name matching several units.
                Mock Resolve-OERAdministrativeUnitId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Administrative unit display name 'AU-Old' matches 2 units (au-a, au-b). Entra does not enforce unique administrative unit display names, so this name cannot identify a single unit. Re-run with the object id instead of the display name."),
                        'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        'AU-Old')
                } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'new desc' }

                # Thrown out of the handler, as an ambiguous displayName is: the engine turns it into the
                # item's one Failed ("handler error") row.
                { Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue } | Should -Throw -ErrorId 'AmbiguousName'
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke Get-OERAdministrativeUnit -Times 0
            }
        }

        It 'under -WhatIf reports would rename, writes nothing, and plans the children against the unit found under its previous name' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{
                    displayName         = 'AU-New'
                    previousDisplayName = 'AU-Old'
                    description         = 'old desc'
                    members             = @('person9@example.com')
                }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERAdministrativeUnit -Times 0
                Should -Invoke New-OERAdministrativeUnit -Times 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                # Reads run under -WhatIf: the unit found under its previous name was read.
                Should -Invoke Get-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' }
                @($r).Count | Should -Be 2
                $Rename = @($r | Where-Object { $_.Detail -like 'would rename*' })
                $Rename.Count | Should -Be 1
                $Rename[0].Action | Should -BeExactly 'Skipped'
                $Rename[0].Item | Should -BeExactly 'AU-New'
                $Rename[0].Detail | Should -BeExactly "would rename administrative unit 'AU-Old' to 'AU-New'"
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would add member 'person9@example.com'" }).Count | Should -Be 1
            }
        }

        It 'under -WhatIf names a changed property after the rename in one would-rename row' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'new desc' }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERAdministrativeUnit -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Skipped'
                $r[0].Detail | Should -BeExactly "would rename administrative unit 'AU-Old' to 'AU-New'; would update administrative unit properties (Description)"
            }
        }

        It 'reports Failed as the last row and reconciles no child of a unit whose rename failed' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                Mock Set-OERAdministrativeUnit {
                    [CmdletBinding()] param($AdministrativeUnit, $NewDisplayName, $Description, $Visibility, $MembershipRule, $MembershipRuleProcessingState, $TenantId, $MembershipType, $Confirm)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('graph 400'), 'GraphBadRequest', [System.Management.Automation.ErrorCategory]::InvalidOperation, $AdministrativeUnit))
                }
                $Item = [PSCustomObject]@{
                    displayName         = 'AU-New'
                    previousDisplayName = 'AU-Old'
                    members             = @('person9@example.com')
                    scopedRoles         = @([PSCustomObject]@{ role = 'User Administrator'; principal = 'person9@example.com' })
                }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue)

                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' -and $NewDisplayName -eq 'AU-New' }
                # The unit still carries its previous name, so none of its children is reconciled under
                # the new name: the Failed row is the item's last (here its only) row.
                @($r).Count | Should -Be 1
                $r[-1].Action | Should -BeExactly 'Failed'
                $r[-1].Detail | Should -Match '^administrative unit update failed: graph 400'
                Should -Invoke Resolve-OERStructurePrincipal -Times 0
                Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                Should -Invoke Add-OERAdministrativeUnitScopedRole -Times 0
                Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                Should -Invoke Remove-OERAdministrativeUnitScopedRole -Times 0
            }
        }

        It 'still reconciles the members of a unit whose property update failed when no rename is involved' {
            InModuleScope $script:moduleName {
                # The control for the test above: the early return belongs to a failed RENAME alone.
                Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                Mock Set-OERAdministrativeUnit {
                    [CmdletBinding()] param($AdministrativeUnit, $NewDisplayName, $Description, $Visibility, $MembershipRule, $MembershipRuleProcessingState, $TenantId, $MembershipType, $Confirm)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('graph 400'), 'GraphBadRequest', [System.Management.Automation.ErrorCategory]::InvalidOperation, $AdministrativeUnit))
                }
                $Item = [PSCustomObject]@{ displayName = 'AU-Old'; description = 'new desc'; members = @('person9@example.com') }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue)

                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match '^administrative unit update failed: graph 400' }).Count | Should -Be 1
                Should -Invoke Add-OERAdministrativeUnitMember -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-old-id' }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added member 'person9@example.com'" }).Count | Should -Be 1
            }
        }

        Context '-EnsureOnly' {
            It 'follows the previous name: a rename creates nothing, reports nothing, writes nothing and registers the old id in the map' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'new desc'; members = @('person9@example.com') }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($r).Count | Should -Be 0
                    @($Err).Count | Should -Be 0
                    Should -Invoke New-OERAdministrativeUnit -Times 0
                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    Should -Invoke Get-OERAdministrativeUnit -Times 0
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                    $Map.Count | Should -Be 1
                    $Map.ContainsKey('administrativeunits|au-new') | Should -BeTrue
                    $Map['administrativeunits|au-new'].Id | Should -BeExactly 'au-old-id'
                    $Map['administrativeunits|au-new'].Refused | Should -BeFalse
                }
            }

            It 'creates nothing and registers a refused entry when neither name resolves' {
                InModuleScope $script:moduleName {
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    # No record and no error: the administrativeUnits pass reports the not-found.
                    @($r).Count | Should -Be 0
                    @($Err).Count | Should -Be 0
                    Should -Invoke New-OERAdministrativeUnit -Times 0
                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    $Map.Count | Should -Be 1
                    $Map['administrativeunits|au-new'].Refused | Should -BeTrue
                    $Map['administrativeunits|au-new'].Id | Should -BeNullOrEmpty
                    $Map['administrativeunits|au-new'].ErrorId | Should -BeExactly 'AdministrativeUnitRenameNotFound'
                }
            }

            It 'writes nothing and registers a refused entry when both names resolve to different units' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-a' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                    Mock Resolve-OERAdministrativeUnitId { 'au-b' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($r).Count | Should -Be 0
                    @($Err).Count | Should -Be 0
                    Should -Invoke New-OERAdministrativeUnit -Times 0
                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    Should -Invoke Get-OERAdministrativeUnit -Times 0
                    $Map.Count | Should -Be 1
                    $Map['administrativeunits|au-new'].Refused | Should -BeTrue
                    $Map['administrativeunits|au-new'].ErrorId | Should -BeExactly 'AdministrativeUnitRenameConflict'
                }
            }

            It 'emits nothing and registers nothing for an entry whose new name already resolves' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-id' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($r).Count | Should -Be 0
                    @($Err).Count | Should -Be 0
                    Should -Invoke New-OERAdministrativeUnit -Times 0
                    Should -Invoke Get-OERAdministrativeUnit -Times 0
                    $Map.Count | Should -Be 0
                }
            }

            It 'still creates a missing unit that declares no previousDisplayName, and registers nothing' {
                InModuleScope $script:moduleName {
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; members = @('person9@example.com') }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    Should -Invoke New-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                    @($Err).Count | Should -Be 0
                    @($r).Count | Should -Be 1
                    $r[0].Action | Should -BeExactly 'Created'
                    $Map.Count | Should -Be 0
                }
            }
        }

        Context 'the run-scoped rename map in the main pass' {
            It 'registers the old id for a rename, under the lower-cased section and new name' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'old desc' }
                    $null = @(Invoke-SyncAuRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 1
                    $Map['administrativeunits|au-new'].Id | Should -BeExactly 'au-old-id'
                    $Map['administrativeunits|au-new'].Refused | Should -BeFalse
                }
            }

            It 'registers a refused entry for a conflict and for a not-found' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-a' } -ParameterFilter { $DisplayName -eq 'AU-Conflict' }
                    Mock Resolve-OERAdministrativeUnitId { 'au-b' } -ParameterFilter { $DisplayName -eq 'AU-Conflict-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = @(Invoke-SyncAuRenameViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-Conflict'; previousDisplayName = 'AU-Conflict-Old' }) -RenameMap $Map -ErrorAction SilentlyContinue)
                    $null = @(Invoke-SyncAuRenameViaCaller -Item ([PSCustomObject]@{ displayName = 'AU-Missing'; previousDisplayName = 'AU-Missing-Old' }) -RenameMap $Map -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 2
                    $Map['administrativeunits|au-conflict'].Refused | Should -BeTrue
                    $Map['administrativeunits|au-conflict'].ErrorId | Should -BeExactly 'AdministrativeUnitRenameConflict'
                    $Map['administrativeunits|au-missing'].Refused | Should -BeTrue
                    $Map['administrativeunits|au-missing'].ErrorId | Should -BeExactly 'AdministrativeUnitRenameNotFound'
                }
            }

            It 'registers the entry under -WhatIf too, before any rename is sent' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old' }
                    $null = @(Invoke-SyncAuRenameViaCaller -Item $Item -RenameMap $Map -WhatIf)

                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    $Map['administrativeunits|au-new'].Id | Should -BeExactly 'au-old-id'
                }
            }
        }

        # R12: the entry is marked undecided in the map BEFORE either of its names is looked up. A lookup
        # that throws -- of the new name too, a transient failure included -- leaves that mark, so a group
        # the run creates into the unit's new name is refused instead of being created into whatever unit
        # a later name lookup finds; a decision replaces it.
        Context 'a rename this run cannot decide (R12)' {
            It 'leaves a refused entry, with the reason that one of its names could not be looked up, when <Case>, and still throws with nothing written' -ForEach @(
                @{ Case = 'the previous name matches several units'; Prev = 'AU-Old'; EnsureOnly = $false; NewThrows = $false }
                @{ Case = 'the previous name matches several units in the pre-pass (-EnsureOnly)'; Prev = 'AU-Old'; EnsureOnly = $true; NewThrows = $false }
                @{ Case = 'the probe of a previous object id fails with anything but not-found'; Prev = '11111111-1111-1111-1111-111111111111'; EnsureOnly = $false; NewThrows = $false }
                @{ Case = 'the lookup of the new name fails (a transient failure)'; Prev = 'AU-Old'; EnsureOnly = $false; NewThrows = $true }
                @{ Case = 'the lookup of the new name fails in the pre-pass (-EnsureOnly)'; Prev = 'AU-Old'; EnsureOnly = $true; NewThrows = $true }
            ) {
                InModuleScope $script:moduleName -Parameters @{ Prev = $Prev; EnsureOnly = $EnsureOnly; NewThrows = $NewThrows } {
                    param($Prev, $EnsureOnly, $NewThrows)
                    Mock Resolve-OERAdministrativeUnitId {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Administrative unit display name 'AU-Old' matches 2 units (au-a, au-b)."),
                            'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'AU-Old')
                    } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    if ($NewThrows) {
                        Mock Resolve-OERAdministrativeUnitId { throw 'transient 502' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                    }
                    Mock Invoke-OERGraphRequest { throw 'graph 403' } -ParameterFilter {
                        $Uri -eq 'v1.0/directory/administrativeUnits/11111111-1111-1111-1111-111111111111?$select=id'
                    }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = $Prev; description = 'new desc'; members = @('person9@example.com') }

                    { Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly:$EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue } | Should -Throw
                    if ($NewThrows) {
                        # The new name's lookup threw first: the previous name was never looked up.
                        Should -Invoke Resolve-OERAdministrativeUnitId -Times 0 -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    }
                    Should -Invoke New-OERAdministrativeUnit -Times 0
                    Should -Invoke Get-OERAdministrativeUnit -Times 0
                    Should -Invoke Set-OERAdministrativeUnit -Times 0
                    Should -Invoke Add-OERAdministrativeUnitMember -Times 0
                    $Map.Count | Should -Be 1
                    $Entry = $Map['administrativeunits|au-new']
                    $Entry.Refused | Should -BeTrue
                    $Entry.Id | Should -BeNullOrEmpty
                    $Entry.ErrorId | Should -BeNullOrEmpty
                    $Entry.Reason | Should -BeExactly 'one of its names could not be looked up'
                    $Entry.PreviousName | Should -BeExactly $Prev
                }
            }

            It 'carries the unit id as the probe answers it, not as previousDisplayName types it (an id in upper case)' {
                InModuleScope $script:moduleName {
                    Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = 'aaaaaaaa-0000-0000-0000-0000000000b1' } } -ParameterFilter {
                        $Uri -eq 'v1.0/directory/administrativeUnits/AAAAAAAA-0000-0000-0000-0000000000B1?$select=id'
                    }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AAAAAAAA-0000-0000-0000-0000000000B1' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    # Positive proof first: the id was probed, once, as typed.
                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                    @($Err).Count | Should -Be 0
                    $Map['administrativeunits|au-new'].Id | Should -BeExactly 'aaaaaaaa-0000-0000-0000-0000000000b1'
                    $Map['administrativeunits|au-new'].Refused | Should -BeFalse
                    Should -Invoke Get-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -ceq 'aaaaaaaa-0000-0000-0000-0000000000b1' }
                    Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter {
                        $AdministrativeUnit -ceq 'aaaaaaaa-0000-0000-0000-0000000000b1' -and $NewDisplayName -eq 'AU-New'
                    }
                    @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                }
            }

            It 'removes an earlier undecided mark when the decision is Current (the new name already finds the unit)' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-id' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = Resolve-OERStructureRename -Section 'administrativeUnits' -Name 'AU-New' -PreviousName 'AU-Old' -Undecided -Reason 'an earlier mark' -RenameMap $Map
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; description = 'old desc' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($Err).Count | Should -Be 0
                    $r.Count | Should -Be 1
                    $r[0].Action | Should -BeExactly 'Unchanged'
                    $Map.Count | Should -Be 0
                }
            }

            It 'replaces an earlier undecided mark with the unit id when the decision is a Rename' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = Resolve-OERStructureRename -Section 'administrativeUnits' -Name 'AU-New' -PreviousName 'AU-Old' -Undecided -Reason 'an earlier mark' -RenameMap $Map
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old' }
                    $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -EnsureOnly -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($Err).Count | Should -Be 0
                    $r.Count | Should -Be 0
                    $Map.Count | Should -Be 1
                    $Map['administrativeunits|au-new'].Id | Should -BeExactly 'au-old-id'
                    $Map['administrativeunits|au-new'].Refused | Should -BeFalse
                    $Map['administrativeunits|au-new'].Reason | Should -BeNullOrEmpty
                }
            }
        }

        # BL-07 with a rename: the groups section runs before this pass, so a group declared into the unit
        # by the unit's PREVIOUS name is created, and recorded, while the unit still carries that name;
        # this pass then renames the unit. The member prune pass must still recognise the record, or a
        # -Prune run removes the membership the same run created. Only the previous name of THIS rename
        # counts. The unit holds the recorded group and one member nobody recorded or declared.
        Context 'a group created into the unit by its previous name in the same run (BL-07)' {
            BeforeEach {
                InModuleScope $script:moduleName {
                    Mock Get-OERAdministrativeUnit {
                        param($AdministrativeUnit)
                        $GroupMember = [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = 'grp-new'; Type = 'group' }
                        $UserMember = [PSCustomObject]@{ Id = 'u-extra'; DisplayName = 'Extra'; Type = 'user' }
                        [PSCustomObject]@{ Id = $AdministrativeUnit; DisplayName = 'AU-Old'; Description = $null; Members = @($GroupMember, $UserMember); ScopedRoles = @() }
                    }
                }
            }

            It 'keeps the membership under -Prune, prunes the unrecorded member, and renames, for a record naming the unit <Label>' -ForEach @(
                @{ Label = 'by the previous name'; Unit = 'AU-Old' }
                @{ Label = 'by the previous name in another letter case'; Unit = 'au-old' }
                @{ Label = 'by the new name'; Unit = 'AU-New' }
            ) {
                InModuleScope $script:moduleName -Parameters @{ Unit = $Unit } {
                    param($Unit)
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Created = [System.Collections.Generic.List[object]]::new()
                    $Created.Add([PSCustomObject]@{ AdministrativeUnit = $Unit; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; members = @(); scopedRoles = $null }
                    $Records = @(Invoke-SyncAuRenameViaCaller -Item $Item -Prune -Created $Created -ErrorAction Stop -WarningAction SilentlyContinue)

                    # The pass reached the removal path and removed the unrecorded member, from the unit
                    # found under the previous name; the recorded group's membership was not removed.
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq 'au-old-id' -and $MemberId -eq 'u-extra' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 0 -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly
                    $Withheld = @($Records | Where-Object { $_.Action -eq 'Skipped' })
                    $Withheld.Count | Should -Be 1
                    $Withheld[0].Item | Should -BeExactly 'AU-New'
                    $Withheld[0].Detail | Should -BeLike "prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'grp-new'*"
                    @($Records | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared member 'u-extra'" }).Count | Should -Be 1
                    @($Records | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "renamed administrative unit 'AU-Old' to 'AU-New'" }).Count | Should -Be 1
                    Should -Invoke Set-OERAdministrativeUnit -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq 'au-old-id' -and $NewDisplayName -eq 'AU-New' }
                }
            }

            It 'reports the membership Extra without -Prune, removing nothing, for a record naming the unit by the previous name' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Created = [System.Collections.Generic.List[object]]::new()
                    $Created.Add([PSCustomObject]@{ AdministrativeUnit = 'AU-Old'; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; members = @(); scopedRoles = $null }
                    $Records = @(Invoke-SyncAuRenameViaCaller -Item $Item -Created $Created -ErrorAction Stop)

                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 0
                    @($Records | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                    @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared member '88888888-8888-8888-8888-888888888888' (use -Prune to remove)" }).Count | Should -Be 1
                    @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -eq "undeclared member 'u-extra' (use -Prune to remove)" }).Count | Should -Be 1
                }
            }

            It 'still prunes the membership under -Prune when the entry renames nothing and the record names a name that is not the unit''s own' {
                InModuleScope $script:moduleName {
                    # No previousDisplayName: the unit is found under its own name, 'AU-Old' is no name of
                    # this unit, so a record naming it is another unit's and only the previous name of a
                    # rename THIS entry declares counts.
                    Mock Resolve-OERAdministrativeUnitId { 'au-new-id' } -ParameterFilter { $DisplayName -eq 'AU-New' }
                    $Created = [System.Collections.Generic.List[object]]::new()
                    $Created.Add([PSCustomObject]@{ AdministrativeUnit = 'AU-Old'; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; members = @(); scopedRoles = $null }
                    $Records = @(Invoke-SyncAuRenameViaCaller -Item $Item -Prune -Created $Created -ErrorAction Stop -WarningAction SilentlyContinue)

                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
                    @($Records | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                    @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 2
                }
            }

            It 'still prunes the membership under -Prune when the record names a unit that is not the one renamed' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERAdministrativeUnitId { 'au-old-id' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                    $Created = [System.Collections.Generic.List[object]]::new()
                    $Created.Add([PSCustomObject]@{ AdministrativeUnit = 'AU-Other'; GroupId = '88888888-8888-8888-8888-888888888888'; Label = 'grp-new' })
                    $Item = [PSCustomObject]@{ displayName = 'AU-New'; previousDisplayName = 'AU-Old'; members = @(); scopedRoles = $null }
                    $Records = @(Invoke-SyncAuRenameViaCaller -Item $Item -Prune -Created $Created -ErrorAction Stop -WarningAction SilentlyContinue)

                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq '88888888-8888-8888-8888-888888888888' }
                    Should -Invoke Remove-OERAdministrativeUnitMember -Times 1 -Exactly -ParameterFilter { $MemberId -eq 'u-extra' }
                    @($Records | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 0
                }
            }
        }

        It 'leaves an entry with no previousDisplayName as it was: one lookup, no probe, a create when the unit is missing' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{ displayName = 'AU-New'; members = @('person9@example.com') }
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1
                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke New-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                Should -Invoke Set-OERAdministrativeUnit -Times 0
                @($Err).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
            }
        }

        It 'treats an explicit null previousDisplayName as undeclared, like every other key' {
            InModuleScope $script:moduleName {
                $Item = '{ "displayName": "AU-New", "previousDisplayName": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERAdministrativeUnitId -Exactly -Times 1
                Should -Invoke New-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'AU-New' }
                @($Err).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
            }
        }

        It 'keeps the update wording of a unit with no rename as it has always been' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERAdministrativeUnitId { 'au-1' } -ParameterFilter { $DisplayName -eq 'AU-Old' }
                $Item = [PSCustomObject]@{ displayName = 'AU-Old'; description = 'new desc' }
                $Run = @(Invoke-SyncAuRenameViaCaller -Item $Item -ErrorAction SilentlyContinue)
                $Plan = @(Invoke-SyncAuRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERAdministrativeUnit -Exactly -Times 1 -ParameterFilter { $Id -eq 'au-1' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                $Run.Count | Should -Be 1
                $Run[0].Detail | Should -BeExactly 'updated administrative unit properties (Description)'
                $Plan.Count | Should -Be 1
                $Plan[0].Detail | Should -BeExactly 'would update administrative unit properties (Description)'
            }
        }
    }
}
