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

Describe 'Sync-OERStructureCatalog' {

    It 'creates a missing catalog and reports Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT' } }
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERCatalog -Times 1
        }
    }

    It 'existing catalog with differing description calls Set-OERCatalog and reports Updated' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'old desc' } }
            Mock Set-OERCatalog {}
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT'; description = 'new desc' }))
            Should -Invoke Set-OERCatalog -Times 1
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'creates a catalog with -ExternallyVisible when the document declares it' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT' } }
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT'; externallyVisible = $true }))
            Should -Invoke New-OERCatalog -Times 1 -ParameterFilter { $ExternallyVisible }
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
        }
    }

    It 'updates a catalog whose externallyVisible drifted' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'd'; ExternallyVisible = $false } }
            Mock Set-OERCatalog {}
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT'; description = 'd'; externallyVisible = $true }))
            Should -Invoke Set-OERCatalog -Times 1 -ParameterFilter { $ExternallyVisible -eq $true }
            ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'externallyVisible' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged when both description and externallyVisible match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'd'; ExternallyVisible = $true } }
            Mock Set-OERCatalog {}
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT'; description = 'd'; externallyVisible = $true }))
            Should -Invoke Set-OERCatalog -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'existing catalog with matching description reports Unchanged and does not call Set-OERCatalog' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'same desc' } }
            Mock Set-OERCatalog {}
            Mock Get-OERCatalogResource { @() }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT'; description = 'same desc' }))
            Should -Invoke Set-OERCatalog -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'adds a missing Group resource by the object id its name resolves to (-GroupId)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { @() }
            Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'role_sec_x' }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $ResItem = [PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem)
            Should -Invoke Add-OERCatalogResource -Exactly -Times 1 -ParameterFilter { $GroupId -eq 'aaaaaaaa-1111-1111-1111-000000000001' -and $Catalog -eq 'cat-1' }
            Should -Invoke Add-OERCatalogResource -Exactly -Times 1
            ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added Group resource 'role_sec_x'" }).Count | Should -Be 1
        }
    }

    It 'adds a missing SharePointSite resource using -SharePointSite parameter' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { @() }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $ResItem = [PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'SharePointSite'; name = 'https://contoso.sharepoint.com/sites/finance' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem)
            Should -Invoke Add-OERCatalogResource -Times 1 -ParameterFilter { $SharePointSite -eq 'https://contoso.sharepoint.com/sites/finance' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Unchanged for a Group resource already present by originId and does not call Add-OERCatalogResource' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'role_sec_x' }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'role_sec_x'; ResourceType = 'Group'; OriginSystem = 'AadGroup'; OriginId = 'AAAAAAAA-1111-1111-1111-000000000001' } }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $ResItem = [PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem)
            Should -Invoke Add-OERCatalogResource -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -Prune removes an undeclared resource via -ResourceId and reports Removed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-extra'; DisplayName = 'undeclared_group'; ResourceType = 'Group' } }
            Mock Remove-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }) -Prune -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERCatalogResource -Times 1 -ParameterFilter { $ResourceId -eq 'r-extra' -and $Catalog -eq 'cat-1' }
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing for resource prune under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-extra'; DisplayName = 'undeclared_group'; ResourceType = 'Group' } }
            Mock Remove-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }) -Prune -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing for resource prune when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-extra'; DisplayName = 'undeclared_group'; ResourceType = 'Group' } }
            Mock Remove-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $Warnings = @()
            $null = Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }) -Prune -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'without -Prune reports undeclared resource as Extra and does not call Remove-OERCatalogResource' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-extra'; DisplayName = 'undeclared_group'; ResourceType = 'Group' } }
            Mock Remove-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }))
            Should -Invoke Remove-OERCatalogResource -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on a missing catalog does not call New-OERCatalog and emits Skipped records' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT' } }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $ResItem = [PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
            Should -Invoke New-OERCatalog -Times 0
            Should -Invoke Add-OERCatalogResource -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on a missing catalog, declared resources produce a would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT' } }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $ResItem = [PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resource 'role_sec_x'" }).Count | Should -Be 1
        }
    }

    It 'under -WhatIf on a missing catalog, an explicit null resources produces no would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT' } }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            # An explicit JSON null (not an omitted key) is a one-element array containing $null when
            # wrapped in @(...), so a bare -contains presence gate is TRUE and iterates one phantom
            # entry -- this is what Test-OERDeclaredProperty must prevent.
            $ResItem = '{ "displayName": "CAT-IT", "resources": null }' | ConvertFrom-Json
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'would create catalog' }).Count | Should -Be 1
            @($r | Where-Object { $_.Detail -match 'would configure' }).Count | Should -Be 0
        }
    }

    It 'when New-OERCatalog throws emits only Failed and does not emit Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERCatalog throws' {
        # Drives the catalog-creation catch in Sync-OERStructureCatalog. The scrub under test is
        # this handler's OWN -- the Remove-OERErrorRecord opening the handler catch that WRAPS the
        # New-OERCatalog call, not a scrub inside New-OERCatalog, which is mocked away here. That
        # mocking is precisely what makes the proof non-vacuous.
        # The static AST gate proves that line is WRITTEN
        # first; this It proves it actually RUNS. Mock + Should -Invoke is the only proof shape that
        # works here: the handler swallows the record into a Failed result instead of re-throwing,
        # so a $global:Error reference-identity proof would be inert.
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { $null }
            Mock New-OERCatalog { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-IT' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'adds an Application resource by the service principal id its name resolves to (-ApplicationId)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; Description = $null } }
            Mock Get-OERCatalogResource { @() }
            Mock Resolve-OERApplicationId { 'bbbbbbbb-2222-2222-2222-000000000001' } -ParameterFilter { $DisplayName -eq 'Contoso App' }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Application'; name = 'Contoso App' })
            }))
            Should -Invoke Add-OERCatalogResource -Exactly -Times 1 -ParameterFilter { $ApplicationId -eq 'bbbbbbbb-2222-2222-2222-000000000001' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Failed (and adds nothing) for an unrecognized resource type' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; Description = $null } }
            Mock Get-OERCatalogResource { @() }
            Mock Add-OERCatalogResource {}
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{
                displayName = 'CAT-IT'
                resources   = @([PSCustomObject]@{ type = 'Widget'; name = 'mystery' })
            }) -ErrorAction SilentlyContinue)
            Should -Invoke Add-OERCatalogResource -Times 0
            ($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like '*unrecognized resource type*' }).Count | Should -BeGreaterThan 0
        }
    }

    Context 'catalog null-declared description is treated as undeclared' {
        It 'does not clear a live description when the document declares it as null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'live desc' } }
                Mock Set-OERCatalog { }
                Mock Get-OERCatalogResource { @() }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "CAT-IT", "description": null }' | ConvertFrom-Json
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Set-OERCatalog -Times 0
            }
        }

        It 'still clears a live description when the document declares an empty string' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = 'live desc' } }
                Mock Set-OERCatalog { }
                Mock Get-OERCatalogResource { @() }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "CAT-IT", "description": "" }' | ConvertFrom-Json
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Set-OERCatalog -Times 1
            }
        }
    }

    Context 'catalog resources null declaration does not trigger a prune wipe' {
        It 'does not prune every live resource when the document declares resources as null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'res-a'; ResourceType = 'Group' }
                        [PSCustomObject]@{ Id = 'r-2'; DisplayName = 'res-b'; ResourceType = 'Group' }
                    )
                }
                Mock Remove-OERCatalogResource { }
                Mock Add-OERCatalogResource { }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "CAT-IT", "resources": null }' | ConvertFrom-Json
                $Records = @(Invoke-SyncCatViaCaller -Item $Item -Prune)
                Should -Invoke Remove-OERCatalogResource -Times 0
                @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
            }
        }

        It 'still prunes every live resource when the document declares resources as an empty array' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @(
                        [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'res-a'; ResourceType = 'Group' }
                        [PSCustomObject]@{ Id = 'r-2'; DisplayName = 'res-b'; ResourceType = 'Group' }
                    )
                }
                Mock Remove-OERCatalogResource { }
                Mock Add-OERCatalogResource { }
                Mock Initialize-OERAuth { }
                $Item = '{ "displayName": "CAT-IT", "resources": [] }' | ConvertFrom-Json
                $null = Invoke-SyncCatViaCaller -Item $Item -Prune
                Should -Invoke Remove-OERCatalogResource -Times 2
            }
        }
    }

    Context 'SharePoint site resources' {
        It 'passes the declared url to -SharePointSite' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{
                        name = 'Finance'; type = 'SharePointSite'
                        url  = 'https://contoso.sharepoint.com/sites/finance'
                    })
                }
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Add-OERCatalogResource -Times 1 -ParameterFilter {
                    $SharePointSite -eq 'https://contoso.sharepoint.com/sites/finance'
                }
            }
        }

        It 'matches an existing SharePoint resource on OriginId, not display name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = $null } }
                Mock Get-OERCatalogResource {
                    @([PSCustomObject]@{
                        Id = 'res-1'; DisplayName = 'Finance'
                        OriginId = 'https://contoso.sharepoint.com/sites/finance'
                        OriginSystem = 'SharePointOnline'
                    })
                }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{
                        name = 'Finance'; type = 'SharePointSite'
                        url  = 'https://contoso.sharepoint.com/sites/finance'
                    })
                }
                $Records = @(Invoke-SyncCatViaCaller -Item $Item)
                Should -Invoke Add-OERCatalogResource -Times 0
                @($Records | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
            }
        }
    }

    # Sprint 2 Task 6: the last two declared-value-family sites in this file, migrated from the
    # inline `PSObject.Properties.Name -contains` idiom to Test-OERDeclaredProperty. Each Context
    # pins one site with value / explicit-null / omitted cases, with the null and omitted cases
    # asserting the SAME outcome, since that pairing is what proves an explicit null means exactly
    # what an omitted key means.

    Context 'resource name label under -WhatIf preview when catalog is missing (site 87)' {
        It 'labels the preview row with the declared resource name when name is declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-New' } }
                Mock Initialize-OERAuth {}
                $ResItem = [PSCustomObject]@{
                    displayName = 'CAT-New'
                    resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
                }
                $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resource 'role_sec_x' after catalog is created" }).Count | Should -Be 1
            }
        }

        It 'labels the preview row with ? when name is declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-New' } }
                Mock Initialize-OERAuth {}
                $ResItem = '{ "displayName": "CAT-New", "resources": [ { "type": "Group", "name": null } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resource '\?' after catalog is created" }).Count | Should -Be 1
            }
        }

        It 'labels the preview row with ? when name is omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-New' } }
                Mock Initialize-OERAuth {}
                $ResItem = '{ "displayName": "CAT-New", "resources": [ { "type": "Group" } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncCatViaCaller -Item $ResItem -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure resource '\?' after catalog is created" }).Count | Should -Be 1
            }
        }
    }

    Context 'SharePoint resource url identifier (site 177)' {
        It 'adds the resource using -SharePointSite from the declared url when url is declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                Mock Add-OERCatalogResource {}
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{
                        name = 'Finance'; type = 'SharePointSite'
                        url  = 'https://contoso.sharepoint.com/sites/finance'
                    })
                }
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Add-OERCatalogResource -Times 1 -Exactly -ParameterFilter {
                    $SharePointSite -eq 'https://contoso.sharepoint.com/sites/finance'
                }
            }
        }

        It 'falls back to the resource name for -SharePointSite when url is declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                Mock Add-OERCatalogResource {}
                Mock Initialize-OERAuth {}
                # name is itself URL-shaped: the pre-url hand-authored back-compat form.
                $Item = '{ "displayName": "CAT-Core", "resources": [ { "name": "https://contoso.sharepoint.com/sites/finance2", "type": "SharePointSite", "url": null } ] }' | ConvertFrom-Json
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Add-OERCatalogResource -Times 1 -Exactly -ParameterFilter {
                    $SharePointSite -eq 'https://contoso.sharepoint.com/sites/finance2'
                }
            }
        }

        It 'falls back to the resource name for -SharePointSite when url is omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-Core'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                Mock Add-OERCatalogResource {}
                Mock Initialize-OERAuth {}
                $Item = '{ "displayName": "CAT-Core", "resources": [ { "name": "https://contoso.sharepoint.com/sites/finance3", "type": "SharePointSite" } ] }' | ConvertFrom-Json
                $null = Invoke-SyncCatViaCaller -Item $Item
                Should -Invoke Add-OERCatalogResource -Times 1 -Exactly -ParameterFilter {
                    $SharePointSite -eq 'https://contoso.sharepoint.com/sites/finance3'
                }
            }
        }
    }

    # Measured live 2026-09-30 (step 5, check 5.5): a catalog keeps the display name a resource had
    # when it was added, also after the group is renamed. Matching a Group or Application resource on
    # that recorded name made a document naming the group by its NEW name plan the removal of the
    # renamed group's own resource under -Prune. A Group or Application resource is now identified by
    # the object id its declared name resolves to, compared with the live originId.
    Context 'Group and Application resources are matched by object id, never by the recorded name' {

        It 'reports a renamed group''s resource Unchanged under its NEW name and removes nothing under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                # The catalog still records the group's OLD name.
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'grp-old'; OriginSystem = 'AadGroup'; OriginId = 'aaaaaaaa-1111-1111-1111-000000000001' }
                }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'grp-new' }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'grp-new' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resource 'grp-new' already present" }).Count | Should -Be 1
                Should -Invoke Remove-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                @($r | Where-Object { $_.Action -in 'Removed', 'Extra', 'Failed' -or [string]$_.Detail -like 'would remove*' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'treats a live Group resource as undeclared when only its RECORDED name equals a declared name of another group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                # 'shared' is the name the catalog recorded for group ...0001, which has since been
                # renamed; group ...0002 carries the name 'shared' now.
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'shared'; OriginSystem = 'AadGroup'; OriginId = 'aaaaaaaa-1111-1111-1111-000000000001' }
                }
                Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000002' } -ParameterFilter { $DisplayName -eq 'shared' }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'shared' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -WhatIf -Prune -WarningAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would add Group resource 'shared'" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would remove undeclared resource 'shared'" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Unchanged' }).Count | Should -Be 1
            }
        }

        It 'withholds the prune, removing and reporting Extra nothing, while a declared Group resource resolves to no group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'grp-old'; OriginSystem = 'AadGroup'; OriginId = 'aaaaaaaa-1111-1111-1111-000000000001' }
                }
                # The group was renamed: its old name resolves to nothing.
                Mock Resolve-OERGroupId { $null }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'grp-old' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly "Group resource 'grp-old' could not be resolved to an object id; nothing was added for it"
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^GroupNotFound'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupNotFound*' }).Count | Should -Be 1
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and [string]$_.Detail -like 'prune withheld:*' })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match "undeclared resource 'grp-old'"
                Should -Invoke Remove-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                @($r | Where-Object { $_.Action -in 'Removed', 'Extra' }).Count | Should -Be 0
            }
        }

        It 'throws -- never reads the resource as absent -- when the group lookup itself fails, and removes nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'grp-x'; OriginSystem = 'AadGroup'; OriginId = 'aaaaaaaa-1111-1111-1111-000000000001' }
                }
                Mock Resolve-OERGroupId { throw 'Graph 503 Service Unavailable' }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'grp-x' }) }
                { Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } |
                    Should -Throw -ExpectedMessage '*Graph 503*'
                Should -Invoke Remove-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
            }
        }

        It 'reports an ambiguous group name Failed with AmbiguousGroupName and withholds the prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'dup'; OriginSystem = 'AadGroup'; OriginId = 'aaaaaaaa-1111-1111-1111-000000000001' }
                }
                Mock Resolve-OERGroupId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Group display name 'dup' matches 2 groups (g-a, g-b)."), 'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup')
                }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'dup' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^AmbiguousGroupName'
                $Failed[0].Detail | Should -Match 'g-a, g-b'
                @($r | Where-Object { [string]$_.Detail -like 'prune withheld:*' }).Count | Should -Be 1
                Should -Invoke Remove-OERCatalogResource -Times 0
            }
        }

        It 'matches an Application resource on the service principal id, not on the name the catalog recorded' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'App Old Name'; OriginSystem = 'AadApplication'; OriginId = 'bbbbbbbb-2222-2222-2222-000000000001' }
                }
                Mock Resolve-OERApplicationId { 'bbbbbbbb-2222-2222-2222-000000000001' } -ParameterFilter { $DisplayName -eq 'App New Name' }
                Mock Add-OERCatalogResource {}
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Application'; name = 'App New Name' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)

                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "resource 'App New Name' already present" }).Count | Should -Be 1
                Should -Invoke Remove-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
            }
        }

        It 'takes a declared object id as it is, with no lookup, and matches it against the originId' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
                Mock Get-OERCatalogResource {
                    [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'App'; OriginSystem = 'AadApplication'; OriginId = 'bbbbbbbb-2222-2222-2222-000000000001' }
                }
                Mock Resolve-OERApplicationId { throw 'a declared object id must not be looked up' }
                Mock Remove-OERCatalogResource {}
                $Item = [PSCustomObject]@{ displayName = 'CAT-IT'; resources = @([PSCustomObject]@{ type = 'Application'; name = 'BBBBBBBB-2222-2222-2222-000000000001' }) }
                $r = @(Invoke-SyncCatViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)

                Should -Invoke Resolve-OERApplicationId -Times 0
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and [string]$_.Detail -like 'resource *already present' }).Count | Should -Be 1
                Should -Invoke Remove-OERCatalogResource -Times 0
            }
        }
    }

    Context 'the catalogs a -WhatIf plan would create (BL-128, A5)' {
        # Sync-OERStructureCatalog adds a name to the passed list ONLY when it reports "would create
        # catalog" under -WhatIf, so Sync-OERStructureAccessPackage, dispatched after it, can plan a
        # package declared in that catalog as created. The wrapper below is the handler's Caller: a
        # SupportsShouldProcess function, whose ShouldProcess returns false under -WhatIf. -DeclineOnly
        # stands for a declined -Confirm: ShouldProcess still returns false, but $WhatIfPreference is
        # false, which is the state the handler sees when the operator answers No.

        It 'adds the name of a missing catalog to the list under -WhatIf, and creates nothing' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog, [switch]$DeclineOnly)
                    if ($DeclineOnly) { $WhatIfPreference = $false }
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'cat-new' } }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'cat-new' }) -PlannedCatalog $Planned -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create catalog cat-new' }).Count | Should -Be 1
                $Planned.Count | Should -Be 1
                $Planned[0] | Should -BeExactly 'cat-new'
                Should -Invoke New-OERCatalog -Times 0
            }
        }

        It 'adds nothing when ShouldProcess is declined and -WhatIf is not in force (a declined -Confirm)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog, [switch]$DeclineOnly)
                    if ($DeclineOnly) { $WhatIfPreference = $false }
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'cat-new' } }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'cat-new' }) -PlannedCatalog $Planned -WhatIf -DeclineOnly)
                # The branch was reached: the handler declined to create, and said so.
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create catalog cat-new' }).Count | Should -Be 1
                Should -Invoke New-OERCatalog -Times 0
                # A catalog the operator declined to create is not planned: its packages stay Failed.
                $Planned.Count | Should -Be 0
            }
        }

        It 'adds nothing for a catalog that already exists' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { 'cat-1' }
                Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'cat-old'; Description = $null } }
                Mock Get-OERCatalogResource { @() }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'cat-old' }) -PlannedCatalog $Planned -WhatIf)
                # The existing-catalog branch was reached.
                Should -Invoke Get-OERCatalog -Times 1 -Exactly
                @($r | Where-Object { $_.Detail -match 'would create catalog' }).Count | Should -Be 0
                $Planned.Count | Should -Be 0
            }
        }

        It 'adds nothing on a real run that creates the catalog' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'cat-new' } }
                Mock Get-OERCatalogResource { @() }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'cat-new' }) -PlannedCatalog $Planned)
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
                Should -Invoke New-OERCatalog -Times 1 -Exactly
                $Planned.Count | Should -Be 0
            }
        }

        It 'does not need the list: a -WhatIf plan without one reports the same row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncCatViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[string]]$PlannedCatalog)
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -PlannedCatalog $PlannedCatalog
                }
                Mock Initialize-OERAuth {}
                Mock Resolve-OERCatalogId { $null }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'cat-new' } }
                $r = @(Invoke-SyncCatViaCaller -Item ([PSCustomObject]@{ displayName = 'cat-new' }) -PlannedCatalog $null -WhatIf)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create catalog cat-new' }).Count | Should -Be 1
                Should -Invoke New-OERCatalog -Times 0
            }
        }
    }

    Context 'previousDisplayName (BL-128)' {
        # A rename through the document (decision A5): displayName is the name the catalog is to carry
        # and previousDisplayName the one it carries now, or its object id. Both names are resolved
        # before anything is read or written, on every run; Resolve-OERStructureRename owns the
        # decision, the error ids and the texts. The catalog found under the previous name takes the
        # existing-catalog path and the rename travels in the SAME Set-OERCatalog call as every other
        # changed property. Resolve-OERCatalogId gets one FILTERED mock per name that resolves; every
        # other name falls to the unfiltered mock, which finds nothing. The only Graph request the
        # handler sends itself is the probe of a previous name that is an object id: any other reach
        # is refused.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncCatRenameViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param(
                        [PSCustomObject]$Item,
                        [switch]$Prune,
                        [System.Collections.Generic.Dictionary[string, object]]$RenameMap,
                        [System.Collections.Generic.List[string]]$PlannedCatalog
                    )
                    $Extra = @{}
                    if ($PSBoundParameters.ContainsKey('RenameMap')) { $Extra.RenameMap = $RenameMap }
                    if ($PSBoundParameters.ContainsKey('PlannedCatalog')) { $Extra.PlannedCatalog = $PlannedCatalog }
                    Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune @Extra
                }
            }
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth { }
                Mock Resolve-OERCatalogId { $null }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                Mock Get-OERCatalog {
                    param($Id)
                    [PSCustomObject]@{ Id = $Id; DisplayName = 'CAT-Old'; Description = 'old desc'; ExternallyVisible = $false }
                }
                Mock Set-OERCatalog { }
                Mock New-OERCatalog { [PSCustomObject]@{ Id = 'cat-created'; DisplayName = 'CAT-New' } }
                Mock Get-OERCatalogResource { @() }
                Mock Add-OERCatalogResource { }
                Mock Remove-OERCatalogResource { }
            }
        }

        It 'renames the catalog found only under its previous name in the same Set-OERCatalog call as a changed property, and reconciles its resources against that catalog' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'role_sec_x' }
                $Item = [PSCustomObject]@{
                    displayName         = 'CAT-New'
                    previousDisplayName = 'CAT-Old'
                    description         = 'new desc'
                    resources           = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter {
                    $Id -eq 'cat-old-id' -and $NewDisplayName -eq 'CAT-New' -and $Description -eq 'new desc'
                }
                Should -Invoke Set-OERCatalog -Exactly -Times 1
                Should -Invoke New-OERCatalog -Times 0
                # Both names were resolved, once each, and the catalog found under the PREVIOUS name was read.
                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Should -Invoke Get-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-old-id' }
                Should -Invoke Get-OERCatalog -Exactly -Times 1
                # The resources are reconciled against the same catalog.
                Should -Invoke Get-OERCatalogResource -Exactly -Times 1 -ParameterFilter { $Catalog -eq 'cat-old-id' }
                Should -Invoke Add-OERCatalogResource -Exactly -Times 1 -ParameterFilter {
                    $Catalog -eq 'cat-old-id' -and $GroupId -eq 'aaaaaaaa-1111-1111-1111-000000000001'
                }
                @($Err).Count | Should -Be 0
                # The rename and the added resource: two rows, one of them the rename.
                @($r).Count | Should -Be 2
                $Rename = @($r | Where-Object { $_.Detail -like 'renamed*' })
                $Rename.Count | Should -Be 1
                $Rename[0].Section | Should -BeExactly 'catalogs'
                $Rename[0].Item | Should -BeExactly 'CAT-New'
                $Rename[0].Action | Should -BeExactly 'Updated'
                $Rename[0].Detail | Should -BeExactly "renamed catalog 'CAT-Old' to 'CAT-New'; updated catalog properties (Description)"
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added Group resource 'role_sec_x'" }).Count | Should -Be 1
            }
        }

        It 'reports a rename with no other change as one Updated row and no properties-match row' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-old-id' -and $NewDisplayName -eq 'CAT-New' -and -not $Description }
                Should -Invoke Set-OERCatalog -Exactly -Times 1
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed catalog 'CAT-Old' to 'CAT-New'"
                @($r | Where-Object { $_.Detail -eq 'catalog properties match' }).Count | Should -Be 0
            }
        }

        It 'names a second changed property after the rename in the same Updated row' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc'; externallyVisible = $true }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter {
                    $Id -eq 'cat-old-id' -and $NewDisplayName -eq 'CAT-New' -and $ExternallyVisible -eq $true
                }
                Should -Invoke Set-OERCatalog -Exactly -Times 1
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Detail | Should -BeExactly "renamed catalog 'CAT-Old' to 'CAT-New'; updated catalog properties (ExternallyVisible)"
            }
        }

        It 'reports Unchanged and sends no rename on the run after the rename, with previousDisplayName still declared' {
            InModuleScope $script:moduleName {
                # After the rename only the new name resolves; the old one finds nothing.
                Mock Resolve-OERCatalogId { 'cat-id' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Should -Invoke Get-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-id' }
                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke New-OERCatalog -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'catalog properties match'
            }
        }

        It 'takes the normal path, with no rename and no failure, when both names resolve to the same catalog (a case-only rename)' {
            InModuleScope $script:moduleName {
                # Graph matches displayName case-insensitively, so a previous name that differs from the
                # new one only in case finds the very catalog the new name finds.
                Mock Resolve-OERCatalogId { 'cat-1' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'cat-new'; description = 'old desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke New-OERCatalog -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'catalog properties match'
            }
        }

        It 'fails the item with one row and a CatalogRenameConflict error, reading and writing nothing, when both names exist as different catalogs' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-a' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Mock Resolve-OERCatalogId { 'cat-b' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                # A resource and a changed property are declared, so a missing guard has something to
                # read, reconcile and write.
                $Item = [PSCustomObject]@{
                    displayName         = 'CAT-New'
                    previousDisplayName = 'CAT-Old'
                    description         = 'new desc'
                    resources           = @([PSCustomObject]@{ type = 'SharePointSite'; name = 'https://contoso.sharepoint.com/sites/finance' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -Prune -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The ONLY row the item emits.
                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'catalogs'
                $r[0].Item | Should -BeExactly 'CAT-New'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "both 'CAT-New' and its previousDisplayName 'CAT-Old' exist as different catalogs; the document never merges two catalogs, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogRenameConflict'

                Should -Invoke Get-OERCatalog -Times 0
                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                Should -Invoke Remove-OERCatalogResource -Times 0

                # The row carries the record either way; only the caller's -ErrorVariable proves it was
                # published through $Caller.WriteError.
                @($Err).Count | Should -Be 1
                $Conflict = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'CatalogRenameConflict,*' })
                $Conflict.Count | Should -Be 1
                $Conflict[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
                $Conflict[0].TargetObject | Should -BeExactly 'CAT-New'
            }
        }

        It 'fails with CatalogRenameNotFound, creating nothing, when neither name resolves' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{
                    displayName         = 'CAT-New'
                    previousDisplayName = 'CAT-Old'
                    resources           = @([PSCustomObject]@{ type = 'SharePointSite'; name = 'https://contoso.sharepoint.com/sites/finance' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Item | Should -BeExactly 'CAT-New'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'CAT-New' nor its previousDisplayName 'CAT-Old' matches a catalog, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new catalog, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogRenameNotFound'
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Get-OERCatalog -Times 0
                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                $NotFound = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'CatalogRenameNotFound,*' })
                @($Err).Count | Should -Be 1
                $NotFound.Count | Should -Be 1
                $NotFound[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $NotFound[0].TargetObject | Should -BeExactly 'CAT-New'
            }
        }

        It 'under -WhatIf reports the same single Failed row, no would-create row and nothing in the planned list when neither name resolves' {
            InModuleScope $script:moduleName {
                $Planned = [System.Collections.Generic.List[string]]::new()
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; resources = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' }) }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -PlannedCatalog $Planned -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogRenameNotFound'
                @($r | Where-Object { [string]$_.Detail -like 'would create*' -or [string]$_.Detail -like 'would configure*' }).Count | Should -Be 0
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'CatalogRenameNotFound,*' }).Count | Should -Be 1
                Should -Invoke New-OERCatalog -Times 0
                # A rename never creates, so the access packages of this catalog are not planned as if it did.
                $Planned.Count | Should -Be 0
            }
        }

        It 'under -WhatIf reports the same single Failed row and nothing in the planned list when both names exist as different catalogs' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-a' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Mock Resolve-OERCatalogId { 'cat-b' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -PlannedCatalog $Planned -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogRenameConflict'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'CatalogRenameConflict,*' }).Count | Should -Be 1
                Should -Invoke Get-OERCatalog -Times 0
                $Planned.Count | Should -Be 0
            }
        }

        It 'under -WhatIf adds nothing to the planned list for a rename, which creates nothing' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Planned = [System.Collections.Generic.List[string]]::new()
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -PlannedCatalog $Planned -WhatIf)

                @($r | Where-Object { [string]$_.Detail -like 'would create*' }).Count | Should -Be 0
                $Planned.Count | Should -Be 0
            }
        }

        # previousDisplayName may be the catalog's object id. Resolve-OERCatalogId returns a GUID
        # verbatim, without any Graph call, so it would "find" a catalog that was deleted: the handler
        # verifies the id with one read of its own, and the Resolve-OERCatalogId mock below returns the
        # GUID for the GUID, as the real helper does, so a handler that asked it would be fooled.
        It 'looks a previous name that is an object id up by one probe, declared to the transport, and never through the catalog resolver' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'CAT-Old' } } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111'
                }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # ONE existence read, with no $select, declaring the not-found answers to the transport.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111' -and
                    @($ExpectedErrorCode) -contains 'CatalogNotFound' -and @($ExpectedErrorCode) -contains 'NotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke Resolve-OERCatalogId -Times 0 -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter {
                    $Id -eq '11111111-1111-1111-1111-111111111111' -and $NewDisplayName -eq 'CAT-New' -and $Description -eq 'new desc'
                }
                Should -Invoke Set-OERCatalog -Exactly -Times 1
                Should -Invoke New-OERCatalog -Times 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed catalog '11111111-1111-1111-1111-111111111111' to 'CAT-New'; updated catalog properties (Description)"
            }
        }

        It 'treats an object id that names no catalog as not matching: displayName absent is CatalogRenameNotFound, creating nothing' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                # What Invoke-OERGraphRequest returns for a declared not-found answer.
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'CatalogNotFound'; StatusCode = 404; Message = 'Catalog does not exist.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111' }
                # A stale id of a deleted catalog: reading it as the catalog to rename would fail here.
                Mock Get-OERCatalog { throw "Catalog '11111111-1111-1111-1111-111111111111' does not exist." }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The id WAS checked -- one existence read -- and found to name no catalog.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111' }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'CAT-New' nor its previousDisplayName '11111111-1111-1111-1111-111111111111' matches a catalog, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new catalog, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogRenameNotFound'
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Get-OERCatalog -Times 0
                Should -Invoke Set-OERCatalog -Times 0
            }
        }

        It 'treats an object id that names no catalog as not matching: displayName present is a normal update, with no conflict and no rename' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-id' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Mock Resolve-OERCatalogId { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'NotFound'; StatusCode = 404; Message = 'Not found.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-id' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                Should -Invoke Set-OERCatalog -Exactly -Times 1
                Should -Invoke New-OERCatalog -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly 'updated catalog properties (Description)'
            }
        }

        It 'throws, creating and writing nothing, when the probe of an object id fails with anything but not-found' {
            InModuleScope $script:moduleName {
                # A 403 is no evidence that the catalog does not exist: the transport throws it, the
                # handler does not catch it, and the engine reports the item Failed ("handler error").
                Mock Invoke-OERGraphRequest { throw 'graph 403' } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111'
                }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = '11111111-1111-1111-1111-111111111111'; description = 'new desc' }

                { Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue } | Should -Throw -ExpectedMessage '*graph 403*'
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Get-OERCatalog -Times 0
                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
            }
        }

        It 'throws, creating and renaming nothing, when the previous name matches several catalogs' {
            InModuleScope $script:moduleName {
                # The record Resolve-OERCatalogId itself throws for a name matching several catalogs.
                Mock Resolve-OERCatalogId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Catalog display name 'CAT-Old' matches 2 catalogs (cat-a, cat-b). Entitlement management does not enforce unique catalog display names, so this name cannot identify a single catalog. Re-run with the catalog id instead of the display name."),
                        'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        'CAT-Old')
                } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'new desc' }

                # Thrown out of the handler, as an ambiguous displayName is: the engine turns it into the
                # item's one Failed ("handler error") row.
                { Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue } | Should -Throw -ErrorId 'AmbiguousName'
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke Get-OERCatalog -Times 0
            }
        }

        It 'under -WhatIf reports would rename, writes nothing, and plans the resources against the catalog found under its previous name' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'role_sec_x' }
                $Item = [PSCustomObject]@{
                    displayName         = 'CAT-New'
                    previousDisplayName = 'CAT-Old'
                    description         = 'old desc'
                    resources           = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERCatalog -Times 0
                Should -Invoke New-OERCatalog -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                # Reads run under -WhatIf: the catalog found under its previous name, and its resources.
                Should -Invoke Get-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-old-id' }
                Should -Invoke Get-OERCatalogResource -Exactly -Times 1 -ParameterFilter { $Catalog -eq 'cat-old-id' }
                @($r).Count | Should -Be 2
                $Rename = @($r | Where-Object { $_.Detail -like 'would rename*' })
                $Rename.Count | Should -Be 1
                $Rename[0].Action | Should -BeExactly 'Skipped'
                $Rename[0].Item | Should -BeExactly 'CAT-New'
                $Rename[0].Detail | Should -BeExactly "would rename catalog 'CAT-Old' to 'CAT-New'"
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would add Group resource 'role_sec_x'" }).Count | Should -Be 1
            }
        }

        It 'under -WhatIf names a changed property after the rename in one would-rename row' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'new desc' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERCatalog -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Skipped'
                $r[0].Detail | Should -BeExactly "would rename catalog 'CAT-Old' to 'CAT-New'; would update catalog properties (Description)"
            }
        }

        It 'reports Failed as the last row and reconciles no resource of a catalog whose rename failed' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Mock Set-OERCatalog {
                    [CmdletBinding()] param($Id, $NewDisplayName, $Description, $ExternallyVisible, $TenantId, $Confirm)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('graph 400'), 'GraphBadRequest', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Id))
                }
                $Item = [PSCustomObject]@{
                    displayName         = 'CAT-New'
                    previousDisplayName = 'CAT-Old'
                    resources           = @([PSCustomObject]@{ type = 'SharePointSite'; name = 'https://contoso.sharepoint.com/sites/finance' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -Prune -ErrorAction SilentlyContinue)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-old-id' -and $NewDisplayName -eq 'CAT-New' }
                # The catalog still carries its previous name, so none of its resources is reconciled
                # under the new name: the Failed row is the item's last (here its only) row.
                @($r).Count | Should -Be 1
                $r[-1].Action | Should -BeExactly 'Failed'
                $r[-1].Detail | Should -Match '^update failed: graph 400'
                Should -Invoke Get-OERCatalogResource -Times 0
                Should -Invoke Add-OERCatalogResource -Times 0
                Should -Invoke Remove-OERCatalogResource -Times 0
            }
        }

        It 'still reconciles the resources of a catalog whose property update failed when no rename is involved' {
            InModuleScope $script:moduleName {
                # The control for the test above: the early return belongs to a failed RENAME alone.
                Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                Mock Resolve-OERGroupId { 'aaaaaaaa-1111-1111-1111-000000000001' } -ParameterFilter { $DisplayName -eq 'role_sec_x' }
                Mock Set-OERCatalog {
                    [CmdletBinding()] param($Id, $NewDisplayName, $Description, $ExternallyVisible, $TenantId, $Confirm)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('graph 400'), 'GraphBadRequest', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Id))
                }
                $Item = [PSCustomObject]@{
                    displayName = 'CAT-Old'
                    description = 'new desc'
                    resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
                }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-old-id' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match '^update failed: graph 400' }).Count | Should -Be 1
                Should -Invoke Add-OERCatalogResource -Exactly -Times 1 -ParameterFilter { $Catalog -eq 'cat-old-id' }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added Group resource 'role_sec_x'" }).Count | Should -Be 1
            }
        }

        Context 'the run-scoped rename map' {
            It 'registers the old id for a rename, under the lower-cased section and new name' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                    $null = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 1
                    $Map['catalogs|cat-new'].Id | Should -BeExactly 'cat-old-id'
                    $Map['catalogs|cat-new'].Refused | Should -BeFalse
                }
            }

            It 'registers a refused entry for a conflict and for a not-found' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-a' } -ParameterFilter { $DisplayName -eq 'CAT-Conflict' }
                    Mock Resolve-OERCatalogId { 'cat-b' } -ParameterFilter { $DisplayName -eq 'CAT-Conflict-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = @(Invoke-SyncCatRenameViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-Conflict'; previousDisplayName = 'CAT-Conflict-Old' }) -RenameMap $Map -ErrorAction SilentlyContinue)
                    $null = @(Invoke-SyncCatRenameViaCaller -Item ([PSCustomObject]@{ displayName = 'CAT-Missing'; previousDisplayName = 'CAT-Missing-Old' }) -RenameMap $Map -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 2
                    $Map['catalogs|cat-conflict'].Refused | Should -BeTrue
                    $Map['catalogs|cat-conflict'].ErrorId | Should -BeExactly 'CatalogRenameConflict'
                    $Map['catalogs|cat-missing'].Refused | Should -BeTrue
                    $Map['catalogs|cat-missing'].ErrorId | Should -BeExactly 'CatalogRenameNotFound'
                }
            }

            It 'registers the entry under -WhatIf too, before any rename is sent' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old' }
                    $null = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -WhatIf)

                    Should -Invoke Set-OERCatalog -Times 0
                    $Map['catalogs|cat-new'].Id | Should -BeExactly 'cat-old-id'
                    $Map['catalogs|cat-new'].Refused | Should -BeFalse
                }
            }

            It 'registers a refused entry under -WhatIf too when neither name resolves' {
                InModuleScope $script:moduleName {
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old' }
                    $null = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -WhatIf -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 1
                    $Map['catalogs|cat-new'].Refused | Should -BeTrue
                    $Map['catalogs|cat-new'].ErrorId | Should -BeExactly 'CatalogRenameNotFound'
                }
            }

            It 'registers nothing for an entry whose new name already resolves' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-id' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                    $null = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue)

                    $Map.Count | Should -Be 0
                }
            }
        }

        # R12: the entry is marked undecided in the map BEFORE either of its names is looked up. A lookup
        # that throws -- of the new name too, a transient failure included -- leaves that mark, so an
        # access package declared in the catalog's new name is refused instead of landing in whatever
        # catalog a later name lookup finds; a decision replaces it.
        Context 'a rename this run cannot decide (R12)' {
            It 'leaves a refused entry, with the reason that one of its names could not be looked up, when <Case>, and still throws with nothing written' -ForEach @(
                @{ Case = 'the previous name matches several catalogs'; Prev = 'CAT-Old'; NewThrows = $false }
                @{ Case = 'the probe of a previous object id fails with anything but not-found'; Prev = '11111111-1111-1111-1111-111111111111'; NewThrows = $false }
                @{ Case = 'the lookup of the new name fails (a transient failure)'; Prev = 'CAT-Old'; NewThrows = $true }
            ) {
                InModuleScope $script:moduleName -Parameters @{ Prev = $Prev; NewThrows = $NewThrows } {
                    param($Prev, $NewThrows)
                    Mock Resolve-OERCatalogId {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Catalog display name 'CAT-Old' matches 2 catalogs (cat-a, cat-b)."),
                            'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'CAT-Old')
                    } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                    if ($NewThrows) {
                        Mock Resolve-OERCatalogId { throw 'transient 502' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                    }
                    Mock Invoke-OERGraphRequest { throw 'graph 403' } -ParameterFilter {
                        $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/11111111-1111-1111-1111-111111111111'
                    }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = $Prev; description = 'new desc'; resources = @() }

                    { Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue } | Should -Throw
                    if ($NewThrows) {
                        # The new name's lookup threw first: the previous name was never looked up.
                        Should -Invoke Resolve-OERCatalogId -Times 0 -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                    }
                    Should -Invoke New-OERCatalog -Times 0
                    Should -Invoke Get-OERCatalog -Times 0
                    Should -Invoke Set-OERCatalog -Times 0
                    Should -Invoke Get-OERCatalogResource -Times 0
                    $Map.Count | Should -Be 1
                    $Entry = $Map['catalogs|cat-new']
                    $Entry.Refused | Should -BeTrue
                    $Entry.Id | Should -BeNullOrEmpty
                    $Entry.ErrorId | Should -BeNullOrEmpty
                    $Entry.Reason | Should -BeExactly 'one of its names could not be looked up'
                    $Entry.PreviousName | Should -BeExactly $Prev
                }
            }

            It 'carries the catalog id as the probe answers it, not as previousDisplayName types it (an id in upper case)' {
                InModuleScope $script:moduleName {
                    Mock Invoke-OERGraphRequest { [PSCustomObject]@{ id = 'aaaaaaaa-0000-0000-0000-0000000000c1'; displayName = 'CAT-Old' } } -ParameterFilter {
                        $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs/AAAAAAAA-0000-0000-0000-0000000000C1'
                    }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'AAAAAAAA-0000-0000-0000-0000000000C1' }
                    $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    # Positive proof first: the id was probed, once, as typed.
                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
                    @($Err).Count | Should -Be 0
                    $Map['catalogs|cat-new'].Id | Should -BeExactly 'aaaaaaaa-0000-0000-0000-0000000000c1'
                    $Map['catalogs|cat-new'].Refused | Should -BeFalse
                    Should -Invoke Get-OERCatalog -Times 1 -Exactly -ParameterFilter { $Id -ceq 'aaaaaaaa-0000-0000-0000-0000000000c1' }
                    Should -Invoke Set-OERCatalog -Times 1 -Exactly -ParameterFilter {
                        $Id -ceq 'aaaaaaaa-0000-0000-0000-0000000000c1' -and $NewDisplayName -eq 'CAT-New'
                    }
                    Should -Invoke Get-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $Catalog -ceq 'aaaaaaaa-0000-0000-0000-0000000000c1' }
                    @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                }
            }

            It 'removes an earlier undecided mark when the decision is Current (the new name already finds the catalog)' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-id' } -ParameterFilter { $DisplayName -eq 'CAT-New' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Undecided -Reason 'an earlier mark' -RenameMap $Map
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old'; description = 'old desc' }
                    $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($Err).Count | Should -Be 0
                    @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq 'catalog properties match' }).Count | Should -Be 1
                    $Map.Count | Should -Be 0
                }
            }

            It 'replaces an earlier undecided mark with the catalog id when the decision is a Rename' {
                InModuleScope $script:moduleName {
                    Mock Resolve-OERCatalogId { 'cat-old-id' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                    $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $null = Resolve-OERStructureRename -Section 'catalogs' -Name 'CAT-New' -PreviousName 'CAT-Old' -Undecided -Reason 'an earlier mark' -RenameMap $Map
                    $Item = [PSCustomObject]@{ displayName = 'CAT-New'; previousDisplayName = 'CAT-Old' }
                    $null = @(Invoke-SyncCatRenameViaCaller -Item $Item -RenameMap $Map -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                    @($Err).Count | Should -Be 0
                    $Map.Count | Should -Be 1
                    $Map['catalogs|cat-new'].Id | Should -BeExactly 'cat-old-id'
                    $Map['catalogs|cat-new'].Refused | Should -BeFalse
                    $Map['catalogs|cat-new'].Reason | Should -BeNullOrEmpty
                }
            }
        }

        It 'leaves an entry with no previousDisplayName as it was: one lookup, no probe, a create when the catalog is missing' {
            InModuleScope $script:moduleName {
                $Item = [PSCustomObject]@{ displayName = 'CAT-New' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1
                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Should -Invoke Invoke-OERGraphRequest -Times 0
                Should -Invoke New-OERCatalog -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-New' }
                Should -Invoke Set-OERCatalog -Times 0
                @($Err).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
            }
        }

        It 'still adds a missing catalog to the planned list under -WhatIf when no previousDisplayName is declared' {
            InModuleScope $script:moduleName {
                $Planned = [System.Collections.Generic.List[string]]::new()
                $Item = [PSCustomObject]@{ displayName = 'CAT-New' }
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -PlannedCatalog $Planned -WhatIf)

                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create catalog CAT-New' }).Count | Should -Be 1
                $Planned.Count | Should -Be 1
                $Planned[0] | Should -BeExactly 'CAT-New'
            }
        }

        It 'treats an explicit null previousDisplayName as undeclared, like every other key' {
            InModuleScope $script:moduleName {
                $Item = '{ "displayName": "CAT-New", "previousDisplayName": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERCatalogId -Exactly -Times 1
                Should -Invoke New-OERCatalog -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-New' }
                @($Err).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
            }
        }

        It 'keeps the update wording of a catalog with no rename as it has always been' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERCatalogId { 'cat-1' } -ParameterFilter { $DisplayName -eq 'CAT-Old' }
                $Item = [PSCustomObject]@{ displayName = 'CAT-Old'; description = 'new desc' }
                $Run = @(Invoke-SyncCatRenameViaCaller -Item $Item -ErrorAction SilentlyContinue)
                $Plan = @(Invoke-SyncCatRenameViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERCatalog -Exactly -Times 1 -ParameterFilter { $Id -eq 'cat-1' -and -not $NewDisplayName -and $Description -eq 'new desc' }
                $Run.Count | Should -Be 1
                $Run[0].Detail | Should -BeExactly 'updated catalog properties (Description)'
                $Plan.Count | Should -Be 1
                $Plan[0].Detail | Should -BeExactly 'would update catalog properties (Description)'
            }
        }
    }
}
