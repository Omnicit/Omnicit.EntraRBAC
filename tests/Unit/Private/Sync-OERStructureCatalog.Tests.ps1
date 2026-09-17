BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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

    It 'adds a missing Group resource using -Group parameter' {
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
                resources   = @([PSCustomObject]@{ type = 'Group'; name = 'role_sec_x' })
            }
            $r = @(Invoke-SyncCatViaCaller -Item $ResItem)
            Should -Invoke Add-OERCatalogResource -Times 1 -ParameterFilter { $Group -eq 'role_sec_x' }
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
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

    It 'reports Unchanged for a resource already present by DisplayName and does not call Add-OERCatalogResource' {
        InModuleScope $script:moduleName {
            function Invoke-SyncCatViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureCatalog -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Get-OERCatalog { [PSCustomObject]@{ Id = 'cat-1'; DisplayName = 'CAT-IT'; Description = $null } }
            Mock Get-OERCatalogResource { [PSCustomObject]@{ Id = 'r-1'; DisplayName = 'role_sec_x'; ResourceType = 'Group' } }
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

    It 'adds an Application resource using the -Application parameter' {
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
                resources   = @([PSCustomObject]@{ type = 'Application'; name = 'Contoso App' })
            }))
            Should -Invoke Add-OERCatalogResource -Times 1 -ParameterFilter { $Application -eq 'Contoso App' }
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
}
