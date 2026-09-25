BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Sync-OERStructureGroup' {

    It 'creates a missing group and reports Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; roleAssignable = $true }))
            ($r | Where-Object { $_.Action -eq 'Created' -and $_.Section -eq 'groups' }).Count | Should -BeGreaterThan 0
            Should -Invoke New-OERGroup -Times 1
        }
    }

    It 'orders members -> time-bound eligibility -> pimPolicy -> permanent eligibility' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            $script:CallLog = [System.Collections.Generic.List[string]]::new()
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { $script:CallLog.Add('New-OERGroup'); [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Add-OERGroupMember { $script:CallLog.Add('Add-OERGroupMember') }
            Mock Add-OERGroupEligibility { $script:CallLog.Add('Add-OERGroupEligibility') }
            Mock Get-OERGroupPimPolicy { $null }
            Mock Set-OERGroupPimPolicy { $script:CallLog.Add('Set-OERGroupPimPolicy') }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{
                displayName    = 'role_sec_x'
                roleAssignable = $true
                members        = @('person9@example.com')
                eligibility    = @(
                    [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 365 },
                    [PSCustomObject]@{ principal = 'person16@example.com' }
                )
                pimPolicy      = [PSCustomObject]@{ allowPermanentEligibility = $true; activationMaxHours = 8 }
            }
            Invoke-SyncGroupViaCaller -Item $Item | Out-Null
            # Use the List[string] directly to get unambiguous single-value IndexOf/LastIndexOf
            $Log = $script:CallLog
            [int]($Log.IndexOf('Add-OERGroupMember'))      | Should -BeLessThan ([int]($Log.IndexOf('Set-OERGroupPimPolicy')))
            [int]($Log.IndexOf('Set-OERGroupPimPolicy'))   | Should -BeLessThan ([int]($Log.LastIndexOf('Add-OERGroupEligibility')))
            # time-bound eligibility happens before pimPolicy
            [int]($Log.IndexOf('Add-OERGroupEligibility')) | Should -BeLessThan ([int]($Log.IndexOf('Set-OERGroupPimPolicy')))
        }
    }

    It 'reports an already-present member as Unchanged and does not add it' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(@{ id = 'id-person9@example.com' }); PimEligibility = @() } }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }))
            Should -Invoke Add-OERGroupMember -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'with -Prune removes an undeclared member (Removed) and warns' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(@{ id = 'extra-1' }); PimEligibility = @() } }
            Mock Remove-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @() }) -Prune -WarningAction SilentlyContinue)
            Should -Invoke Remove-OERGroupMember -Times 1
            ($r | Where-Object Action -eq 'Removed').Count | Should -BeGreaterThan 0
        }
    }

    It 'says would remove rather than removing when -Prune runs under -WhatIf' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    Members = @([PSCustomObject]@{ id = 'u-1' }); PimEligibility = @()
                }
            }
            Mock Remove-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = '{ "displayName": "role_sec_x", "members": [] }' | ConvertFrom-Json
            $Warnings = @()
            $null = Invoke-SyncGroupViaCaller -Item $Item -Prune -WhatIf -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'would remove'
            $Joined | Should -Not -Match 'removing undeclared'
        }
    }

    It 'still says removing when -Prune runs for real' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    Members = @([PSCustomObject]@{ id = 'u-1' }); PimEligibility = @()
                }
            }
            Mock Remove-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = '{ "displayName": "role_sec_x", "members": [] }' | ConvertFrom-Json
            $Warnings = @()
            $null = Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningVariable Warnings
            $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
            $Joined | Should -Match 'removing undeclared'
        }
    }

    It 'without -Prune reports the undeclared member as Extra and does not remove it' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(@{ id = 'extra-1' }); PimEligibility = @() } }
            Mock Remove-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @() }))
            Should -Invoke Remove-OERGroupMember -Times 0
            ($r | Where-Object Action -eq 'Extra').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf creates nothing and records Skipped' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }) -WhatIf)
            Should -Invoke New-OERGroup -Times 0
            Should -Invoke Add-OERGroupMember -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on a new group, declared members/eligibility/pimPolicy each produce a would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{
                displayName = 'role_sec_x'
                members     = @('person9@example.com')
                eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 365 })
                pimPolicy   = [PSCustomObject]@{ allowPermanentEligibility = $true }
            }
            $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure member 'person9@example.com'" }).Count | Should -Be 1
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "would configure eligibility for 'person9@example.com'" }).Count | Should -Be 1
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'would configure pimPolicy' }).Count | Should -Be 1
        }
    }

    It 'under -WhatIf on a new group, an explicit null members/eligibility/pimPolicy produces no would-configure preview row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            # An explicit JSON null (not an omitted key) is a one-element array containing $null when
            # wrapped in @(...), so a bare -contains presence gate is TRUE and iterates one phantom
            # entry -- this is what Test-OERDeclaredProperty must prevent.
            $Item = '{ "displayName": "role_sec_x", "members": null, "eligibility": null, "pimPolicy": null }' | ConvertFrom-Json
            $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)
            @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'would create group' }).Count | Should -Be 1
            @($r | Where-Object { $_.Detail -match 'would configure' }).Count | Should -Be 0
        }
    }

    It 'records Failed and continues when New-OERGroup throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { throw 'graph 500' }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERGroup throws' {
        # Drives the group-creation catch in Sync-OERStructureGroup. The scrub under test is this
        # handler's OWN -- the Remove-OERErrorRecord opening the handler catch that WRAPS the
        # New-OERGroup call, not a scrub inside New-OERGroup, which is mocked away here. That
        # mocking is precisely what makes the proof non-vacuous.
        # The static AST gate proves that line is WRITTEN first; this
        # It proves it actually RUNS. Mock + Should -Invoke is the only proof shape that works here:
        # the handler swallows the record into a Failed result instead of re-throwing, so a
        # $global:Error reference-identity proof would be inert.
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { throw 'graph 500' }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'updates the description of an existing group' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = 'old'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; description = 'new' }))
            Should -Invoke Set-OERGroup -Times 1
            ($r | Where-Object Action -eq 'Updated').Count | Should -BeGreaterThan 0
        }
    }

    It 'reports declared roleAssignable drift as Skipped and suppresses the properties-match Unchanged' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Regular'; MembershipRule = $null
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = '{ "displayName": "role_sec_x", "roleAssignable": true }' | ConvertFrom-Json
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
            @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'roleAssignable' }).Count | Should -Be 1
            @($Records | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq 'group properties match' }).Count | Should -Be 0
            Should -Invoke Set-OERGroup -Times 0
        }
    }

    It 'applies a membershipRule change on a group that is already dynamic' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Dynamic'; MembershipRule = 'user.department -eq "A"'
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; dynamic = $true; membershipRule = 'user.department -eq "B"' }
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
            Should -Invoke Set-OERGroup -Times 1
            @($Records | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'MembershipRule' }).Count | Should -Be 1
        }
    }

    It 'creates a dynamic group with -MembershipRuleProcessingState when the document declares it' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'dyn_x' } }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); Owners = @(); PimEligibility = @() } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{
                displayName = 'dyn_x'; dynamic = $true; membershipRule = 'user.department -eq "A"'
                membershipRuleProcessingState = 'Paused'
            }
            Invoke-SyncGroupViaCaller -Item $Item | Out-Null
            Should -Invoke New-OERGroup -Times 1 -ParameterFilter { $MembershipRuleProcessingState -eq 'Paused' }
        }
    }

    It 'applies a membershipRuleProcessingState change on a group that is already dynamic' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'dyn_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Dynamic'; MembershipRule = 'user.department -eq "A"'
                    MembershipRuleProcessingState = 'On'
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{ displayName = 'dyn_x'; dynamic = $true; membershipRuleProcessingState = 'Paused' }
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
            Should -Invoke Set-OERGroup -Times 1 -ParameterFilter { $MembershipRuleProcessingState -eq 'Paused' }
            @($Records | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'MembershipRuleProcessingState' }).Count | Should -Be 1
        }
    }

    It 'does not diff membershipRuleProcessingState against a static group (drift already reported by dynamic)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Assigned'
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; membershipRuleProcessingState = 'Paused' }
            Invoke-SyncGroupViaCaller -Item $Item -WarningAction SilentlyContinue | Out-Null
            Should -Invoke Set-OERGroup -Times 0
        }
    }

    It 'reports declared dynamic drift on a static group as Skipped rather than attempting a conversion' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Regular'; MembershipRule = $null
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; dynamic = $true }
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
            @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'dynamic' }).Count | Should -Be 1
            Should -Invoke Set-OERGroup -Times 0
        }
    }

    It 'skips member reconciliation entirely on a dynamic group' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Dynamic'; MembershipRule = '(user.department -eq "A")'
                    Members = @([PSCustomObject]@{ id = 'u-1' }, [PSCustomObject]@{ id = 'u-2' })
                    PimEligibility = @()
                }
            }
            Mock Add-OERGroupMember { }
            Mock Remove-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; dynamic = $true; members = @('person34@example.com') }
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune)
            Should -Invoke Add-OERGroupMember -Times 0
            Should -Invoke Remove-OERGroupMember -Times 0
            @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'person34@example.com' -and $_.Detail -match 'membership rule' }).Count | Should -Be 1
        }
    }

    It 'still reconciles members on a static group' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Regular'; MembershipRule = $null
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person34@example.com') }
            $null = Invoke-SyncGroupViaCaller -Item $Item
            Should -Invoke Add-OERGroupMember -Times 1
        }
    }

    It 'still reconciles members on a static group whose declared dynamic flag is refused as drift' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    IsAssignableToRole = $false; GroupType = 'Regular'; MembershipRule = $null
                    Members = @(); PimEligibility = @()
                }
            }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = '{ "displayName": "role_sec_x", "dynamic": true, "members": [ "person35@example.com" ] }' | ConvertFrom-Json
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
            Should -Invoke Add-OERGroupMember -Times 1
            @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'dynamic' }).Count | Should -Be 1
            @($Records | Where-Object { $_.Detail -match 'membership is owned by its membership rule' }).Count | Should -Be 0
        }
    }

    It 'uses Resolve-OERName when template and tokens are present' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERName { 'role_sec_identity_administrator' }
            Mock Resolve-OERGroupId { $null }
            Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_identity_administrator' } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                template = 'role_sec_{area}_{tier}'
                tokens   = [PSCustomObject]@{ area = 'identity'; tier = 'administrator' }
            }))
            Should -Invoke Resolve-OERName -Times 1
            ($r | Where-Object { $_.Item -eq 'role_sec_identity_administrator' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'emits Unchanged for group when nothing changed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = 'same'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; description = 'same' }))
            Should -Invoke Set-OERGroup -Times 0
            ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Section -eq 'groups' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'leaves pimPolicy Unchanged when the declared block is empty' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Get-OERGroupPimPolicy {
                [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = $null; ActivationEnabledRules = @();
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } }
            }
            Mock Set-OERGroupPimPolicy { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                pimPolicy   = [PSCustomObject]@{}
            }))
            Should -Invoke Set-OERGroupPimPolicy -Times 0
            ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -match 'pimPolicy' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'reconciles a nested member+owner pimPolicy and reports Unchanged when both match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERGroupId { 'gid-1' }
            Mock Get-OERGroup { [pscustomobject]@{ Id = 'gid-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
            Mock Get-OERGroupPimPolicy {
                [pscustomobject]@{ ActivationMaxHours = 8; AuthenticationContextId = $null; ActivationEnabledRules = @('Justification');
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                    ActiveEnabledRules = @('MultiFactorAuthentication'); Notifications = [pscustomobject]@{ EligibleAlert=@(); ActiveAlert=@(); ActivationAlert=@() } }
            }
            Mock Set-OERGroupPimPolicy {}
            $Block = [pscustomobject]@{ activationMaxHours = 8; activationEnablement = @('Justification'); allowPermanentEligibility = $false;
                eligibleDurationDays = 365; allowPermanentActive = $false; activeDurationDays = 180; activeEnablement = @('MultiFactorAuthentication') }
            $Item = [pscustomobject]@{ displayName = 'g1'; pimPolicy = [pscustomobject]@{ member = $Block; owner = $Block } }
            $Results = @(Invoke-SyncGroupViaCaller -Item $Item)
            $PimResults = @($Results | Where-Object { $_.Detail -match 'pimPolicy' })
            $PimResults.Count | Should -Be 2
            ($PimResults | Where-Object { $_.Action -eq 'Unchanged' }).Count | Should -Be 2
            Should -Invoke Set-OERGroupPimPolicy -Times 0
        }
    }

    It 'updates only the owner policy when only owner differs' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Initialize-OERAuth {}
            Mock Resolve-OERGroupId { 'gid-1' }
            Mock Get-OERGroup { [pscustomobject]@{ Id = 'gid-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
            Mock Get-OERGroupPimPolicy {
                param($Id, $AccessType)
                $hours = if ($AccessType -eq 'owner') { 8 } else { 4 }
                [pscustomobject]@{ ActivationMaxHours = $hours; AuthenticationContextId = $null; ActivationEnabledRules = @();
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                    ActiveEnabledRules = @(); Notifications = [pscustomobject]@{ EligibleAlert=@(); ActiveAlert=@(); ActivationAlert=@() } }
            }
            Mock Set-OERGroupPimPolicy { [pscustomobject]@{ Applied = $true; FailedRules = @() } }
            $Item = [pscustomobject]@{ displayName = 'g1'; pimPolicy = [pscustomobject]@{
                member = [pscustomobject]@{ activationMaxHours = 4 }
                owner  = [pscustomobject]@{ activationMaxHours = 1 }
            } }
            Invoke-SyncGroupViaCaller -Item $Item | Out-Null
            Should -Invoke Set-OERGroupPimPolicy -Times 1 -ParameterFilter { $AccessType -eq 'owner' }
            Should -Invoke Set-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'member' }
        }
    }

    It 'resolves principal to null and emits Failed without aborting' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Resolve-OERStructurePrincipal { $null }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person15@example.com') }) -ErrorAction SilentlyContinue)
            Should -Invoke Add-OERGroupMember -Times 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
        }
    }

    It 'skips adding already-eligible principal and emits Unchanged' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @(@{ principalId = 'id-person9@example.com'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2027-01-01T09:00:00Z' }) } }
            Mock Add-OERGroupEligibility { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 365 })
            }))
            Should -Invoke Add-OERGroupEligibility -Times 0
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
        }
    }

    It 'emits ONLY Failed (not also Updated) when Set-OERGroup throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = 'old'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { throw 'graph 500' }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; description = 'new' }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
        }
    }

    It 'emits ONLY Failed (not also Updated) when Set-OERGroupPimPolicy throws' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1; Rules = @() } }
            Mock Set-OERGroupPimPolicy { throw 'graph 500' }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 8 }
            }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
        }
    }

    It 'updates pimPolicy when only allowPermanentEligibility differs from the current policy' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            # Current policy: hours already match (8), but AllowPermanentEligibility is false. Document asks for true.
            Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8; AllowPermanentEligibility = $false;
                EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                AuthenticationContextId = $null; ActivationEnabledRules = @(); ActiveEnabledRules = @();
                Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
            Mock Set-OERGroupPimPolicy { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 8; allowPermanentEligibility = $true }
            }))
            Should -Invoke Set-OERGroupPimPolicy -Times 1
            ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like '*pimPolicy*' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'under -WhatIf on an EXISTING group writes nothing and records Skipped for pending changes' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = 'old'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { }
            Mock Add-OERGroupMember { }
            Mock Set-OERGroupPimPolicy { }
            Mock Get-OERGroupPimPolicy { $null }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                description = 'new'
                members     = @('person9@example.com')
            }) -WhatIf)
            Should -Invoke Set-OERGroup -Times 0
            Should -Invoke Add-OERGroupMember -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 1
        }
    }

    It 'leaves pimPolicy Unchanged when hours and allowPermanentEligibility both already match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            # hours match AND AllowPermanentEligibility already true (Task 4 Get-OERGroupPimPolicy returns the friendly property)
            Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8; AllowPermanentEligibility = $true;
                EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180;
                AuthenticationContextId = $null; ActivationEnabledRules = @(); ActiveEnabledRules = @();
                Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
            Mock Set-OERGroupPimPolicy { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 8; allowPermanentEligibility = $true }
            }))
            Should -Invoke Set-OERGroupPimPolicy -Times 0
            ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -like '*pimPolicy*' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'reports Failed (not Updated) when a child cmdlet writes a NON-terminating error' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            # Mimic an OER cmdlet's non-terminating error convention (WriteError, not throw).
            Mock Add-OERGroupMember { Write-Error 'ResourceNotFound' }
            Mock Get-OERGroupPimPolicy { $null }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }) -ErrorAction SilentlyContinue)
            ($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like '*member*' }).Count | Should -BeGreaterThan 0
            ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like '*member*' }).Count | Should -Be 0
        }
    }

    It 'reports Failed when Set-OERGroupPimPolicy applies only partially (Applied=False)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
            Mock Get-OERGroupPimPolicy { $null }
            # Set succeeds at the cmdlet level but reports a partial rule application.
            Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $false; FailedRules = @('Expiration_EndUser_Assignment', 'Enablement_EndUser_Assignment') } }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            $r = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{
                displayName = 'role_sec_x'
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 8; allowPermanentEligibility = $true }
            }))
            ($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like '*partially applied*' }).Count | Should -BeGreaterThan 0
            ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like '*pimPolicy*' }).Count | Should -Be 0
        }
    }

    It 'does not clear a live description when the document declares it as null' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = 'live text'; MailNickname = 'rsx'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $Item = '{ "displayName": "role_sec_x", "description": null, "mailNickname": null }' | ConvertFrom-Json
            $null = Invoke-SyncGroupViaCaller -Item $Item
            Should -Invoke Set-OERGroup -Times 0
        }
    }

    It 'still clears a live description when the document declares an empty string' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = 'live text'; MailNickname = 'rsx'; Members = @(); PimEligibility = @() } }
            Mock Set-OERGroup { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock Resolve-OERStructureDefault { $null }
            Mock Get-OERGroupPimPolicy { $null }
            $Item = '{ "displayName": "role_sec_x", "description": "" }' | ConvertFrom-Json
            $null = Invoke-SyncGroupViaCaller -Item $Item
            Should -Invoke Set-OERGroup -Times 1
        }
    }

    It 'does not prune every live member when the document declares members as null' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    Members = @([PSCustomObject]@{ id = 'u-1' }, [PSCustomObject]@{ id = 'u-2' })
                    PimEligibility = @()
                }
            }
            Mock Remove-OERGroupMember { }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = '{ "displayName": "role_sec_x", "members": null }' | ConvertFrom-Json
            $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune)
            Should -Invoke Remove-OERGroupMember -Times 0
            @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
        }
    }

    It 'still prunes every live member when the document declares members as an empty array' {
        InModuleScope $script:moduleName {
            function Invoke-SyncGroupViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Resolve-OERGroupId { 'g-1' }
            Mock Get-OERGroup {
                [PSCustomObject]@{
                    Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    Members = @([PSCustomObject]@{ id = 'u-1' }, [PSCustomObject]@{ id = 'u-2' })
                    PimEligibility = @()
                }
            }
            Mock Remove-OERGroupMember { }
            Mock Add-OERGroupMember { }
            Mock Initialize-OERAuth { }
            Mock Resolve-OERStructureDefault { $null }
            Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            $Item = '{ "displayName": "role_sec_x", "members": [] }' | ConvertFrom-Json
            $null = Invoke-SyncGroupViaCaller -Item $Item -Prune
            Should -Invoke Remove-OERGroupMember -Times 2
        }
    }

    Context 'eligibility Extra/prune reconciliation' {
        It 'reports an undeclared live eligibility as Extra without -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-keep'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = 'u-drop'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'u-keep' }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": "person36@example.com" } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
                $Extra = @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -match 'u-drop' })
                $Extra.Count | Should -Be 1
                Should -Invoke Remove-OERGroupEligibility -Times 0
            }
        }

        It 'removes an undeclared live eligibility with -Prune and reports Removed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-keep'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = 'u-drop'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'u-keep' }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": "person36@example.com" } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERGroupEligibility -Times 1
                @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 1
            }
        }

        It 'restores the handler-level warning before the prune gate and silences the child cmdlet duplicate' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-drop'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                # Mirrors the real Remove-OERGroupEligibility (ConfirmImpact = High), which warns inside
                # its own ShouldProcess gate on every real removal, to prove the handler's
                # -WarningAction SilentlyContinue on the call site actually silences that duplicate.
                Mock Remove-OERGroupEligibility { Write-Warning 'Remove-OERGroupEligibility: removing eligibility for principal.' }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [] }' | ConvertFrom-Json
                $Warnings = @()
                $null = Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningVariable Warnings
                $Joined = @($Warnings | ForEach-Object { [string]$_ })
                $Joined.Count | Should -Be 1
                $Joined[0] | Should -Match 'removing undeclared'
            }
        }

        It 'says would remove rather than removing for eligibility prune under -WhatIf' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-drop'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [] }' | ConvertFrom-Json
                $Warnings = @()
                $null = Invoke-SyncGroupViaCaller -Item $Item -Prune -WhatIf -WarningVariable Warnings
                $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
                $Joined | Should -Match 'would remove'
                $Joined | Should -Not -Match 'removing undeclared'
                Should -Invoke Remove-OERGroupEligibility -Times 0
            }
        }

        It 'does not touch eligibility at all when the document does not declare the key' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-keep'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = 'u-drop'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'u-keep' }
                $Item = '{ "displayName": "role_sec_x" }' | ConvertFrom-Json
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERGroupEligibility -Times 0
                @($Records | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
            }
        }

        It 'matches a declared owner eligibility separately from a member eligibility on the same principal' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = 'u-1'; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = 'u-1'; accessId = 'owner'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'u-1' }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": "person37@example.com", "accessType": "member" } ] }' | ConvertFrom-Json
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
                $Extra = @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -match 'owner' })
                $Extra.Count | Should -Be 1
                Should -Invoke Remove-OERGroupEligibility -Times 0
            }
        }
    }

    Context 'owners reconciliation' {
        It 'adds a declared owner that is not present' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(); PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('person19@example.com') }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Add-OERGroupMember -Times 1 -ParameterFilter { $AccessType -eq 'owner' }
                @($Records | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'owner' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'reports an already-present owner as Unchanged and does not add it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }); PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('person19@example.com') }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Add-OERGroupMember -Times 0
                @($Records | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -match 'owner' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'reports an undeclared live owner as Extra without -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }, @{ id = 'o-2' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('person36@example.com') }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Remove-OERGroupMember -Times 0
                @($Records | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -match 'owner' }).Count | Should -Be 1
            }
        }

        It 'removes an undeclared live owner with -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }, @{ id = 'o-2' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('person36@example.com') }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 1 -ParameterFilter { $AccessType -eq 'owner' -and $PrincipalId -eq 'o-2' }
                @($Records | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -match 'owner' }).Count | Should -Be 1
            }
        }

        It 'does not remove the last remaining owner and reports Skipped instead' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @() }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'last' }).Count | Should -Be 1
            }
        }

        It 'refuses to prune a lone service principal owner too, pending live verification of Graph''s user-owner rule' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    # Microsoft Learn's last-owner restriction names "a user object" specifically, so a
                    # sole SERVICE PRINCIPAL owner may in fact be prunable. The guard is deliberately
                    # conservative (count-based, not type-aware) pending live verification -- this test
                    # pins that deliberate choice. ObjectType mirrors the shape ConvertTo-OERGroupMember
                    # actually produces (the '@odata.type' annotation stripped of its '#microsoft.graph.'
                    # prefix), matching what a real Get-OERGroup -IncludeOwners call would return.
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        Owners  = @([PSCustomObject]@{ id = 'o-1'; ObjectType = 'servicePrincipal' })
                        PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; owners = @() }
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                @($Records | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match 'last' }).Count | Should -Be 1
            }
        }

        It 'does not touch owners at all when the document does not declare the key' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }); PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = '{ "displayName": "role_sec_x" }' | ConvertFrom-Json
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue)
                Should -Invoke Add-OERGroupMember -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Remove-OERGroupMember -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                @($Records | Where-Object { $_.Detail -match 'owner' }).Count | Should -Be 0
            }
        }

        It 'reconciles owners on a dynamic group (not gated on $EffectiveIsDynamic)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        GroupType = 'Dynamic'; MembershipRule = '(user.department -eq "IT")'
                        Members = @(); Owners = @(); PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) 'o-1' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; dynamic = $true; owners = @('person19@example.com') }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Add-OERGroupMember -Times 1 -ParameterFilter { $AccessType -eq 'owner' }
            }
        }
    }

    Context 'eligibility duration and access type reconciliation' {
        It 'passes -AccessType owner and -Action adminAssign through to Add-OERGroupEligibility' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup {
                    $G = [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'g'; Description = $null; MailNickname = $null }
                    $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @() -Force
                    $G
                }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner'; durationDays = 30 })
                }
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly `
                    -ParameterFilter { $AccessType -eq 'owner' -and $DurationDays -eq 30 -and $Action -eq 'adminAssign' }
            }
        }

        It 're-issues the eligibility with -Action adminUpdate when the declared duration differs from the live window' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup {
                    $G = [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'g'; Description = $null; MailNickname = $null }
                    $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @(
                        @{ principalId = 'p-1'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z' }
                    ) -Force
                    $G
                }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 90 })
                }
                $R = @(Invoke-SyncWrapper -Item $Item -Confirm:$false)
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly `
                    -ParameterFilter { $DurationDays -eq 90 -and $Action -eq 'adminUpdate' }
                ($R | Where-Object { $_.Detail -like '*duration differs*' }).Action | Should -Be 'Updated'
            }
        }

        It 'reports Unchanged when the declared duration already matches the live window' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup {
                    $G = [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'g'; Description = $null; MailNickname = $null }
                    $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @(
                        @{ principalId = 'p-1'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z' }
                    ) -Force
                    $G
                }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 30 })
                }
                $R = @(Invoke-SyncWrapper -Item $Item -Confirm:$false)
                Should -Invoke Add-OERGroupEligibility -Times 0 -Exactly
                ($R | Where-Object { $_.Detail -like '*eligibility*' }).Action | Should -Be 'Unchanged'
            }
        }

        It 'treats an owner eligibility as absent (Action adminAssign) when only a member eligibility exists for the principal' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup {
                    $G = [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'g'; Description = $null; MailNickname = $null }
                    $G | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                    $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue @(
                        @{ principalId = 'p-1'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = $null }
                    ) -Force
                    $G
                }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner' })
                }
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly `
                    -ParameterFilter { $AccessType -eq 'owner' -and $Action -eq 'adminAssign' }
            }
        }
    }

    Context 'a failed live read is a Failed row, never a Created' {

        It 'reports Failed and reconciles nothing when the live group read fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                Mock Add-OERGroupMember { }
                Mock Set-OERGroup { }
                Mock Get-OERGroupPimPolicy { $null }
                # Exactly what Task 1 made Get-OERGroup do: a NON-terminating error plus an object
                # with the unreadable collection OMITTED. A throwing mock would abort the handler
                # with -ErrorAction Stop removed from the call site too, so it would prove nothing
                # about the single condition this guard rests on. The fallback is to
                # $ErrorActionPreference rather than a hardcoded value, so an unpinned call site
                # really does inherit the caller's suppression the way the real one does.
                Mock Get-OERGroup {
                    param($Id, $Group, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    Write-Error -Message "Could not read members for group $Id. The Members property is omitted rather than reported as empty." -ErrorId 'GroupMemberReadFailed' -Category LimitsExceeded -TargetObject $Id -ErrorAction $Ea
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null; GroupType = 'Assigned'; IsAssignableToRole = $false }
                }

                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }
                $Results = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)

                # Positive identity FIRST: an absence assertion on its own also passes when the
                # handler emitted nothing at all.
                @($Results).Count | Should -Be 1
                $Results[0].Section | Should -BeExactly 'groups'
                $Results[0].Item | Should -BeExactly 'role_sec_x'
                $Results[0].Action | Should -BeExactly 'Failed'
                $Results[0].Detail | Should -Match 'failed to read the current state of group'
                $null -ne $Results[0].Error | Should -BeTrue -Because 'the sprint requires the underlying ErrorRecord to travel with the Failed row'

                @($Results | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -Be 0 -Because 'an unreadable membership is not evidence that the declared member is missing'
                Should -Invoke Add-OERGroupMember -Times 0 -Exactly
                Should -Invoke Set-OERGroup -Times 0 -Exactly
            }
        }

        It 'still reconciles a group that genuinely has no members, and reports no Failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                Mock Add-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null; GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @() }
                }

                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }
                $Results = @(Invoke-SyncGroupViaCaller -Item $Item)

                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'an empty read that SUCCEEDED is not a failure; only the two must be distinguishable'
                Should -Invoke Add-OERGroupMember -Times 1 -Exactly
            }
        }

        It 'reconciles members normally when the entry declares no eligibility and the PIM read is unusable' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                Mock Add-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                # Models a tenant whose PIM-for-Groups endpoint answers 403 rather than the
                # ResourceTypeNotSupported that Get-OERGroup carves out by name: asking for the
                # eligibility fails the whole read. The document declares only members, so the handler
                # must never ask for it -- the switch value is the single condition under test, hence
                # the mock keys off $IncludePimEligibility and not off anything else.
                Mock Get-OERGroup {
                    param($Id, $Group, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    if ($IncludePimEligibility) {
                        Write-Error -Message "Could not read PIM eligibility for group $Id." -ErrorId 'GroupPimEligibilityReadFailed' -Category PermissionDenied -TargetObject $Id -ErrorAction $Ea
                        return
                    }
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null; GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @() }
                }

                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com') }
                $Results = @(Invoke-SyncGroupViaCaller -Item $Item)

                # CONTENT, not merely a count: a Failed count of 0 would also hold if the handler had
                # emitted nothing at all, and that is the shape this regression must tell apart.
                $Added = @($Results | Where-Object { $_.Action -eq 'Updated' })
                @($Added).Count | Should -Be 1
                $Added[0].Detail | Should -Match "added member 'person9@example.com'"
                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'a document that declares no eligibility must not fail on an eligibility endpoint it never asked about'
                Should -Invoke Add-OERGroupMember -Times 1 -Exactly
                Should -Invoke Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $IncludePimEligibility -and -not $IncludeOwners }
            }
        }

        It 'reconciles a pimPolicy-only entry when the PIM eligibility read is unusable' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                Mock Set-OERGroupPimPolicy { }
                # Step 4 reads the live policy through THIS cmdlet and never touches $CurrentEligibles,
                # so a pimPolicy-only entry has no use for the eligibility read and must not request it.
                Mock Get-OERGroupPimPolicy {
                    [PSCustomObject]@{ ActivationMaxHours = 8; AllowPermanentEligibility = $false
                        EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                        AuthenticationContextId = $null; ActivationEnabledRules = @(); ActiveEnabledRules = @()
                        Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } }
                }
                # Same shape as the members-only sibling above: a tenant whose PIM-for-Groups beta
                # endpoint answers 403 instead of the ResourceTypeNotSupported Get-OERGroup carves out
                # by name, so asking for the eligibility fails the whole read. The error is written
                # NON-terminating and honours the caller's -ErrorAction, since a throwing mock would
                # pass whether or not the call site pins -ErrorAction Stop and would prove nothing.
                Mock Get-OERGroup {
                    param($Id, $Group, $IncludeMembers, $IncludeOwners, $IncludePimEligibility, $TenantId, $ErrorAction)
                    $Ea = if ($ErrorAction) { $ErrorAction } else { $ErrorActionPreference }
                    if ($IncludePimEligibility) {
                        Write-Error -Message "Could not read PIM eligibility for group $Id." -ErrorId 'GroupPimEligibilityReadFailed' -Category PermissionDenied -TargetObject $Id -ErrorAction $Ea
                        return
                    }
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null; GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @() }
                }

                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 8; allowPermanentEligibility = $true }
                }
                $Results = @(Invoke-SyncGroupViaCaller -Item $Item)

                # CONTENT before absence: a Failed count of 0 also holds when the handler emitted
                # nothing at all, which is exactly the shape this regression has to tell apart.
                $Updated = @($Results | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like '*pimPolicy*' })
                @($Updated).Count | Should -Be 1
                $Updated[0].Detail | Should -Match 'pimPolicy \(member\) set'
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly

                @($Results | Where-Object { $_.Action -eq 'Failed' }).Count |
                    Should -Be 0 -Because 'a document declaring only pimPolicy must not fail on an eligibility endpoint it never asked about'
                # The single condition under test: pimPolicy alone must not raise the switch.
                Should -Invoke Get-OERGroup -Times 1 -Exactly -ParameterFilter { -not $IncludePimEligibility -and -not $IncludeOwners }
            }
        }
    }

    # Issue #70 site 2 and the rest of the declared-value family (Sprint 2 Task 3). Every Context
    # below pins one migrated site: value / explicit-null / omitted, with the null and omitted cases
    # asserting the SAME outcome, since that pairing is what proves an explicit null means exactly
    # what an omitted key means. The pimPolicy Context has its own five-behaviour list from the task
    # brief in place of the generic three.

    Context 'template display name resolution (site 118)' {
        It 'uses the template to build the display name when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'role_sec_identity_administrator' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'fallback_name'
                    template    = 'role_sec_{area}_{tier}'
                    tokens      = [PSCustomObject]@{ area = 'identity'; tier = 'administrator' }
                }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 1 -Exactly
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'role_sec_identity_administrator' }
            }
        }

        It 'falls back to the literal displayName when template is declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'should-not-be-used' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "literal_name", "template": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 0 -Exactly
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'literal_name' }
            }
        }

        It 'falls back to the literal displayName when template is omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'should-not-be-used' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'literal_name' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 0 -Exactly
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'literal_name' }
            }
        }
    }

    Context 'tokens hash passed to Resolve-OERName (site 121)' {
        It 'passes the declared tokens hash to Resolve-OERName when tokens is declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'resolved_name' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    template = 'role_sec_{area}'
                    tokens   = [PSCustomObject]@{ area = 'identity' }
                }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 1 -Exactly -ParameterFilter { $Tokens.Count -eq 1 -and $Tokens['area'] -eq 'identity' }
            }
        }

        It 'passes an empty tokens hash to Resolve-OERName when tokens is declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'resolved_name' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "template": "role_sec_{area}", "tokens": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 1 -Exactly -ParameterFilter { $Tokens.Count -eq 0 }
            }
        }

        It 'passes an empty tokens hash to Resolve-OERName when tokens is omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERName { 'resolved_name' }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ template = 'role_sec_{area}' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Resolve-OERName -Times 1 -Exactly -ParameterFilter { $Tokens.Count -eq 0 }
            }
        }
    }

    Context 'eligibility principal label under -WhatIf preview (site 158)' {
        It 'labels the preview row with the declared principal when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 365 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Detail -match "would configure eligibility for 'person9@example.com' after group is created" }).Count | Should -Be 1
            }
        }

        It 'labels the preview row with ? when principal is declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": null, "durationDays": 365 } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Detail -match "would configure eligibility for '\?' after group is created" }).Count | Should -Be 1
            }
        }

        It 'labels the preview row with ? when principal is omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "durationDays": 365 } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)
                @($r | Where-Object { $_.Detail -match "would configure eligibility for '\?' after group is created" }).Count | Should -Be 1
            }
        }
    }

    Context 'roleAssignable at group creation (site 172)' {
        It 'creates the group with -RoleAssignable when declared true' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; roleAssignable = $true }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $RoleAssignable -eq $true }
            }
        }

        It 'creates the group without -RoleAssignable when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "roleAssignable": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { -not $RoleAssignable }
            }
        }

        It 'creates the group without -RoleAssignable when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { -not $RoleAssignable }
            }
        }
    }

    Context 'dynamic at group creation (site 175)' {
        It 'creates the group with -Dynamic when declared true' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'dyn_x'; dynamic = $true; membershipRule = 'user.department -eq "A"' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $Dynamic -eq $true }
            }
        }

        It 'creates the group without -Dynamic when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "dynamic": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { -not $Dynamic }
            }
        }

        It 'creates the group without -Dynamic when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { -not $Dynamic }
            }
        }
    }

    Context 'membershipRule at group creation (site 177, behavior change: a declared null no longer binds -MembershipRule $null)' {
        It 'binds -MembershipRule when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'dyn_x'; dynamic = $true; membershipRule = 'user.department -eq "A"' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                $script:CapturedKeys | Should -Contain 'MembershipRule'
            }
        }

        It 'does not bind -MembershipRule when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "dyn_x", "dynamic": true, "membershipRule": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                # Control for the negative assertion below (new inert-test form, caught by the
                # Sprint 2 whole-branch review): $script:CapturedKeys is $null until the New-OERGroup
                # mock runs, and BOTH $null and @() pass Should -Not -Contain -- so without this line
                # the check below would stay green if the handler never reached the create path at
                # all. DisplayName is bound on every create, so it proves the capture site was
                # reached. Same control the AccessReview tests on this branch already carry.
                $script:CapturedKeys | Should -Contain 'DisplayName' -Because 'the New-OERGroup mock must actually have run for the negative check below to mean anything'
                $script:CapturedKeys | Should -Not -Contain 'MembershipRule'
            }
        }

        It 'does not bind -MembershipRule when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'dyn_x'; dynamic = $true }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                # Control for the negative assertion below (new inert-test form, caught by the
                # Sprint 2 whole-branch review): $script:CapturedKeys is $null until the New-OERGroup
                # mock runs, and BOTH $null and @() pass Should -Not -Contain -- so without this line
                # the check below would stay green if the handler never reached the create path at
                # all. DisplayName is bound on every create, so it proves the capture site was
                # reached. Same control the AccessReview tests on this branch already carry.
                $script:CapturedKeys | Should -Contain 'DisplayName' -Because 'the New-OERGroup mock must actually have run for the negative check below to mean anything'
                $script:CapturedKeys | Should -Not -Contain 'MembershipRule'
            }
        }
    }

    Context 'administrativeUnit at group creation (site 186, behavior change: a declared null no longer binds -AdministrativeUnit $null)' {
        It 'binds -AdministrativeUnit when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; administrativeUnit = 'au-1' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                $script:CapturedKeys | Should -Contain 'AdministrativeUnit'
            }
        }

        It 'does not bind -AdministrativeUnit when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "administrativeUnit": null }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                # Control for the negative assertion below (new inert-test form, caught by the
                # Sprint 2 whole-branch review): $script:CapturedKeys is $null until the New-OERGroup
                # mock runs, and BOTH $null and @() pass Should -Not -Contain -- so without this line
                # the check below would stay green if the handler never reached the create path at
                # all. DisplayName is bound on every create, so it proves the capture site was
                # reached. Same control the AccessReview tests on this branch already carry.
                $script:CapturedKeys | Should -Contain 'DisplayName' -Because 'the New-OERGroup mock must actually have run for the negative check below to mean anything'
                $script:CapturedKeys | Should -Not -Contain 'AdministrativeUnit'
            }
        }

        It 'does not bind -AdministrativeUnit when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:CapturedKeys = $null
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup {
                    # An explicit param block is required here: without one, a Pester mock scriptblock's
                    # own $PSBoundParameters is always empty regardless of what the real command actually
                    # received, which would make every assertion below pass vacuously.
                    param($DisplayName, $RoleAssignable, $Dynamic, $MembershipRule, $MembershipRuleProcessingState,
                        $Description, $MailNickname, $AdministrativeUnit, $TenantId, $Confirm)
                    $script:CapturedKeys = @($PSBoundParameters.Keys)
                    [PSCustomObject]@{ Id = 'g-1'; DisplayName = $DisplayName }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x' }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                # Control for the negative assertion below (new inert-test form, caught by the
                # Sprint 2 whole-branch review): $script:CapturedKeys is $null until the New-OERGroup
                # mock runs, and BOTH $null and @() pass Should -Not -Contain -- so without this line
                # the check below would stay green if the handler never reached the create path at
                # all. DisplayName is bound on every create, so it proves the capture site was
                # reached. Same control the AccessReview tests on this branch already carry.
                $script:CapturedKeys | Should -Contain 'DisplayName' -Because 'the New-OERGroup mock must actually have run for the negative check below to mean anything'
                $script:CapturedKeys | Should -Not -Contain 'AdministrativeUnit'
            }
        }
    }

    Context 'eligibility accessType, time-bound entries (site 565)' {
        It 'uses the declared accessType for a time-bound entry when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner'; durationDays = 30 })
                }
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' -and $DurationDays -eq 30 }
            }
        }

        It 'defaults to member accessType for a time-bound entry when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = '{ "displayName": "g", "eligibility": [ { "principal": "person17@example.com", "accessType": null, "durationDays": 30 } ] }' | ConvertFrom-Json
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $DurationDays -eq 30 }
            }
        }

        It 'defaults to member accessType for a time-bound entry when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = '{ "displayName": "g", "eligibility": [ { "principal": "person17@example.com", "durationDays": 30 } ] }' | ConvertFrom-Json
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $DurationDays -eq 30 }
            }
        }
    }

    Context 'eligibility accessType, permanent entries (site 659)' {
        It 'uses the declared accessType for a permanent entry when declared with a value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = [PSCustomObject]@{
                    displayName = 'g'
                    eligibility = @([PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner' })
                }
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
            }
        }

        It 'defaults to member accessType for a permanent entry when declared explicit null (same as omitted)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = '{ "displayName": "g", "eligibility": [ { "principal": "person17@example.com", "accessType": null } ] }' | ConvertFrom-Json
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
            }
        }

        It 'defaults to member accessType for a permanent entry when omitted (same as an explicit null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncWrapper {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Resolve-OERStructurePrincipal { 'p-1' }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                $Item = '{ "displayName": "g", "eligibility": [ { "principal": "person17@example.com" } ] }' | ConvertFrom-Json
                Invoke-SyncWrapper -Item $Item -Confirm:$false | Out-Null
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
            }
        }
    }

    Context 'pimPolicy nested-vs-flat form (site 594-595, issue #70 site 2)' {
        # The five behaviours from the task brief, as five It blocks, plus a declared-value and an
        # omitted case for each of member and owner (the omitted cases pair with the explicit-null
        # ones above them to prove the two mean the same thing).

        It 'bullet 1: reconciles only the member policy via the nested form when owner is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ member = [PSCustomObject]@{ activationMaxHours = 8 } } }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -Exactly
                @($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
            }
        }

        It 'bullet 2: reconciles both member and owner policies when both are declared with differing values' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy {
                    [PSCustomObject]@{ ActivationMaxHours = 1; AuthenticationContextId = $null; ActivationEnabledRules = @()
                        AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                        ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } }
                }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{
                    member = [PSCustomObject]@{ activationMaxHours = 4 }
                    owner  = [PSCustomObject]@{ activationMaxHours = 8 }
                } }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $ActivationMaxHours -eq 4 }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' -and $ActivationMaxHours -eq 8 }
            }
        }

        It 'bullet 3: reconciles nothing and makes no Graph call when member is declared explicit null and owner is absent' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "pimPolicy": { "member": null } }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -Exactly
                @($r | Where-Object { $_.Detail -match 'pimPolicy' }).Count | Should -Be 0
            }
        }

        It 'bullet 4: reconciles only the owner policy when member is declared explicit null and owner is declared' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "pimPolicy": { "member": null, "owner": { "activationMaxHours": 8 } } }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' -and $ActivationMaxHours -eq 8 }
            }
        }

        It 'member omitted, owner declared: same outcome as bullet 4 (member declared null)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                # No 'member' key at all -- the OMITTED counterpart to the previous test's explicit null.
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ owner = [PSCustomObject]@{ activationMaxHours = 8 } } }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' -and $ActivationMaxHours -eq 8 }
            }
        }

        It 'bullet 5: treats a flat pimPolicy document as the member policy and never touches owner' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 4; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 8 } }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $ActivationMaxHours -eq 8 }
            }
        }

        It 'reconciles only the member policy when owner is declared explicit null (member declared)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = '{ "displayName": "role_sec_x", "pimPolicy": { "member": { "activationMaxHours": 4 }, "owner": null } }' | ConvertFrom-Json
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $ActivationMaxHours -eq 4 }
            }
        }

        It 'owner omitted, member declared: same outcome as owner declared null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1; AuthenticationContextId = $null; ActivationEnabledRules = @()
                    AllowPermanentEligibility = $false; EligibleDurationDays = 365; AllowPermanentActive = $false; ActiveDurationDays = 180
                    ActiveEnabledRules = @(); Notifications = [PSCustomObject]@{ EligibleAlert = @(); ActiveAlert = @(); ActivationAlert = @() } } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                # No 'owner' key at all -- the OMITTED counterpart to the previous test's explicit null.
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ member = [PSCustomObject]@{ activationMaxHours = 4 } } }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'member' -and $ActivationMaxHours -eq 4 }
            }
        }
    }

    Context 'pimPolicy approval (requireApproval, approvers) -- step 4 approver name resolution' {
        It 'resolves approver names before the diff and converges' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy {
                    [PSCustomObject]@{
                        RequireApproval = $true
                        Approvers       = @([PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; UserType = 'Group'; DisplayName = 'Approvers' })
                    }
                }
                Mock Set-OERGroupPimPolicy { }
                Mock Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '22222222-2222-2222-2222-222222222222'; PrincipalType = 'Group' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{
                        member = [PSCustomObject]@{
                            requireApproval = $true
                            approvers       = [PSCustomObject]@{ groups = @('Approvers') }
                        }
                    }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)
                ($r | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                Should -Invoke Set-OERGroupPimPolicy -Times 0
            }
        }

        It 'reports Failed for an unresolvable approver in the owner block only; member still processes' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Resolve-OERPrincipal { throw "User 'nobody@example.com' was not found." }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{
                        member = [PSCustomObject]@{ activationMaxHours = 8 }
                        owner  = [PSCustomObject]@{
                            requireApproval = $true
                            approvers       = [PSCustomObject]@{ users = @('nobody@example.com') }
                        }
                    }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                $OwnerFailed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(owner\)' })
                $OwnerFailed.Count | Should -Be 1
                $OwnerFailed[0].Detail | Should -Match 'could not resolve an approver'
                @($r | Where-Object { $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                # The approver is resolved BEFORE the owner policy is read, so a failed resolution costs
                # no policy read for that access type.
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                # The Failed row carries the same $ErrRec whether or not $Caller.WriteError ran, so only
                # the caller's -ErrorVariable proves the record was published. Narrowed to the id AND the
                # handler's own text, exactly one record.
                @($Err | Where-Object {
                        [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' -and
                        $_.Exception.Message -like '*Could not resolve an approver declared in pimPolicy (owner)*'
                    }).Count | Should -Be 1
            }
        }

        It 'sends ids, not names, to Set-OERGroupPimPolicy' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ RequireApproval = $true; Approvers = @() } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = '22222222-2222-2222-2222-222222222222'; PrincipalType = 'Group' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{
                        requireApproval = $true
                        approvers       = [PSCustomObject]@{ groups = @('Approvers') }
                    }
                }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter {
                    @($ApproverGroup) -contains '22222222-2222-2222-2222-222222222222' -and
                    @($ApproverGroup) -notcontains 'Approvers'
                }
            }
        }
    }

    Context 'pimPolicy step-4 policy-read retry after a same-run group creation' {
        It 'retries a missing policy of a group created in this run, then applies it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { }
                $script:PimCallCount = 0
                Mock Get-OERGroupPimPolicy {
                    $script:PimCallCount++
                    if ($script:PimCallCount -le 2) {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('no policy'), 'PimPolicyNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'g-1')
                    }
                    [PSCustomObject]@{ ActivationMaxHours = 1 }
                }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
            }
        }

        It 'gives up after 30 seconds with a replication message' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { }
                Mock Get-OERGroupPimPolicy {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('no policy'), 'PimPolicyNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'g-1')
                }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                Should -Invoke Start-Sleep -Times 4 -Exactly
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 8 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 16 }
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(member\)' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'replication delay'
                $Failed[0].Detail | Should -Match 're-running'
                $Failed[0].Detail | Should -Not -Match 'Add-OERGroupEligibility'
                # The Failed row's Error is the exact ErrorRecord passed to ConvertTo-OERStructureResult,
                # so this alone does NOT prove $Caller.WriteError($ErrRec) actually ran -- both calls are
                # fed the same $ErrRec variable regardless of whether WriteError executes. It only proves
                # the RESULT ROW carries the right record.
                $Failed[0].Error | Should -Not -BeNullOrEmpty
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match 'PimPolicyNotFound'
                # This is the proof that the record actually reached the caller: -ErrorVariable, narrowed
                # to a record carrying BOTH the PimPolicyNotFound id and the replication-delay text, is
                # reliable even at this suite's scale (an UNFILTERED count is not -- see the Set-
                # OERGroupPimPolicy tests for that quirk -- but this specific filter isolates the one
                # record this test cares about from any accumulated noise). Deleting the
                # $Caller.WriteError($ErrRec) call in Sync-OERStructureGroup.ps1 makes this assertion
                # fail while every other assertion above keeps passing (M6.5).
                $Reached = @($Err | Where-Object {
                        [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' -and
                        $_.Exception.Message -like '*replication delay*'
                    })
                $Reached.Count | Should -Be 1
            }
        }

        It 'shares one 30-second budget between member and owner' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { }
                Mock Get-OERGroupPimPolicy {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('no policy'), 'PimPolicyNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'g-1')
                }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{
                        member = [PSCustomObject]@{ activationMaxHours = 4 }
                        owner  = [PSCustomObject]@{ activationMaxHours = 2 }
                    }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 4 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \((member|owner)\)' })
                $Failed.Count | Should -Be 2
            }
        }

        It 'never retries a refused read (403), even for a group created in this run' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { }
                Mock Get-OERGroupPimPolicy {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges'), 'PimPolicyReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError, 'g-1')
                }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue | Out-Null
                Should -Invoke Start-Sleep -Times 0
            }
        }

        It 'never retries a missing policy of an existing group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { }
                Mock Get-OERGroupPimPolicy {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('no policy'), 'PimPolicyNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'g-1')
                }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                Invoke-SyncGroupViaCaller -Item $Item | Out-Null
                Should -Invoke Start-Sleep -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            }
        }
    }

    Context 'prune withheld when a declared entry cannot be resolved' {
        # A declared entry whose principal lookup gives no id carries no key, so the live entry it
        # was meant to name looks undeclared. Every such pass must report its live candidates
        # Skipped with the withheld reason instead of Extra or Removed, while the unresolved entry
        # keeps its own Failed row. person15@example.com is the unresolvable reference throughout.
        It 'withholds the member prune when a declared member cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @([PSCustomObject]@{ id = 'id-person9@example.com' }, [PSCustomObject]@{ id = 'u-live' })
                        PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) if ($Reference -eq 'person15@example.com') { $null } else { "id-$Reference" } }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person9@example.com', 'person15@example.com') }
                $Warnings = @()
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -WarningVariable Warnings -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared member 'u-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve member 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
                (@($Warnings | ForEach-Object { [string]$_ }) -join ' ') | Should -Not -Match 'u-live'
            }
        }

        It 'reports the member candidate Skipped with the withheld reason, not Extra, when -Prune is not set' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @([PSCustomObject]@{ id = 'u-live' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person15@example.com') }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                @($r | Where-Object Action -eq 'Extra').Count | Should -Be 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared member 'u-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve member 'person15@example.com'" }).Count | Should -Be 1
            }
        }

        It 'withholds the owner prune when a declared owner cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-1' }, @{ id = 'o-live' }); PimEligibility = @()
                    }
                }
                Mock Add-OERGroupMember { }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) if ($Reference -eq 'person15@example.com') { $null } else { 'o-1' } }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = $null; owners = @('person19@example.com', 'person15@example.com') }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared owner 'o-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve owner 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
            }
        }

        It 'withholds a lone undeclared owner with the unresolved-entry reason ahead of the last-owner guard' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @(); Owners = @(@{ id = 'o-live' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { $null }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = $null; owners = @('person15@example.com') }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupMember -Times 0
                $Skipped = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "'o-live'" })
                $Skipped.Count | Should -Be 1
                $Skipped[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                $Skipped[0].Detail | Should -Not -Match 'last remaining owner'
            }
        }

        It 'withholds the eligibility prune when a declared time-bound eligibility principal cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @([PSCustomObject]@{ principalId = 'u-live'; accessId = 'member'; startDateTime = $null; endDateTime = $null })
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { $null }
                $Item = '{ "displayName": "role_sec_x", "members": null, "eligibility": [ { "principal": "person15@example.com", "durationDays": 30 } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupEligibility -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared member eligibility for principal 'u-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve eligibility principal 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
            }
        }

        It 'withholds the eligibility prune when a declared permanent eligibility principal cannot be resolved' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @([PSCustomObject]@{ principalId = 'u-live'; accessId = 'member'; startDateTime = $null; endDateTime = $null })
                    }
                }
                Mock Add-OERGroupEligibility { }
                Mock Remove-OERGroupEligibility { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { $null }
                $Item = '{ "displayName": "role_sec_x", "members": null, "eligibility": [ { "principal": "person15@example.com" } ] }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
                Should -Invoke Remove-OERGroupEligibility -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Withheld = @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match "undeclared member eligibility for principal 'u-live'" })
                $Withheld.Count | Should -Be 1
                $Withheld[0].Detail | Should -Match '^prune withheld: declared entry ''person15@example\.com'' could not be resolved'
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq "could not resolve eligibility principal 'person15@example.com'" }).Count | Should -Be 1
                @($r | Where-Object Action -eq 'Removed').Count | Should -Be 0
            }
        }

        It 'still aborts the item, and removes nothing, when a member lookup throws under -Prune' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @([PSCustomObject]@{ id = 'u-live' }); PimEligibility = @()
                    }
                }
                Mock Remove-OERGroupMember { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { throw 'Graph 503 while resolving the member' }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; members = @('person15@example.com') }
                { Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } |
                    Should -Throw -ExpectedMessage '*Graph 503*'
                Should -Invoke Remove-OERGroupMember -Times 0
            }
        }
    }
}
