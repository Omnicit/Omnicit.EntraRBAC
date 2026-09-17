BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
}
