BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Sync-OERStructureGroup' {
    BeforeEach {
        # Step 4 asks Test-OERGroupPimInUse, once per item, before it writes a CHANGED policy to a
        # group that already existed. Answered "in use" for every test in this file, so no fixture
        # written before that question existed reaches the real helper (and through it the real
        # transport) or gains a warning it does not expect. The Context 'pimPolicy onboarding
        # warning ...' overrides it.
        Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x'; Manageable = $true } }
    }

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
            # The group is created in this run, so its time-bound eligibility (step 3) goes through
            # the private request that can wait out a 404, and its permanent one (step 5) through the
            # cmdlet. Each logs under its own name, so the order assertions below keep meaning the
            # same thing: Send-OERNewGroupEligibilityRequest is the time-bound write.
            Mock Send-OERNewGroupEligibilityRequest { $script:CallLog.Add('Send-OERNewGroupEligibilityRequest'); @{ id = 'req-1' } }
            Mock Add-OERGroupEligibility { $script:CallLog.Add('Add-OERGroupEligibility') }
            # The group is created in this run, so steps 4 and 5 first ask whether its policy is listed
            # and readable; it is, at once, so nothing waits (Start-Sleep is mocked all the same). The
            # read is mocked too, so no call reaches the real transport.
            Mock Get-OERPimGroupPolicyId { 'pol-member' }
            Mock Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
            Mock Start-Sleep { }
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
            # IndexOf answers -1 for a call that never happened, which is "less than" everything: pin
            # that each of the four calls ran once before the order means anything.
            foreach ($Call in 'Add-OERGroupMember', 'Send-OERNewGroupEligibilityRequest', 'Set-OERGroupPimPolicy', 'Add-OERGroupEligibility') {
                @($Log | Where-Object { $_ -eq $Call }).Count | Should -Be 1 -Because "$Call must have run exactly once"
            }
            [int]($Log.IndexOf('Add-OERGroupMember'))      | Should -BeLessThan ([int]($Log.IndexOf('Set-OERGroupPimPolicy')))
            # permanent eligibility happens after pimPolicy
            [int]($Log.IndexOf('Set-OERGroupPimPolicy'))   | Should -BeLessThan ([int]($Log.IndexOf('Add-OERGroupEligibility')))
            # time-bound eligibility happens before pimPolicy
            [int]($Log.IndexOf('Send-OERNewGroupEligibilityRequest')) | Should -BeLessThan ([int]($Log.IndexOf('Set-OERGroupPimPolicy')))
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
                # Mirrors the real Remove-OERGroupEligibility (ConfirmImpact = High), which warns before
                # its own ShouldProcess gate every time it is called, to prove the handler's
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

        It 'withholds a lone service principal owner as a service principal (A9), so the last-owner guard is never consulted for it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    # Before A9 this test pinned the last-owner guard's count for a lone service
                    # principal owner. The group prune now never removes a service principal at all,
                    # so the owner is withheld for its type before that guard is reached, and the
                    # guard counts only owners of other types (the test above pins it for one).
                    # ObjectType mirrors the shape ConvertTo-OERGroupMember actually produces (the
                    # '@odata.type' annotation stripped of its '#microsoft.graph.' prefix, or the type
                    # the typed read proves), matching what a real Get-OERGroup -IncludeOwners returns.
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
                $Owner = @($Records | Where-Object { $_.Detail -match "owner 'o-1'" })
                $Owner.Count | Should -Be 1
                $Owner[0].Action | Should -BeExactly 'Skipped'
                $Owner[0].Detail | Should -BeLike "prune withheld: undeclared owner 'o-1' is a service principal, and -Prune never removes a service principal from a group; *"
                @($Records | Where-Object { $_.Detail -match 'last' }).Count | Should -Be 0
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

    # BL-07: a group created INTO an administrative unit is recorded in the run-scoped list the engine
    # passes as -CreatedUnitMembership, so the administrativeUnits section does not prune the
    # membership in the same run. Only a real create with a unit records; -WhatIf, a failed create and
    # a create without a unit record nothing.
    Context 'the administrative unit membership a create records (BL-07)' {
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Resolve-OERGroupId { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
            }
        }

        It 'records the unit as declared, the new group id and the group name after a create into a unit named <Label>' -ForEach @(
            @{ Label = 'by display name'; Unit = 'AU-1' }
            @{ Label = 'by object id'; Unit = '66666666-6666-6666-6666-666666666666' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Unit = $Unit } {
                param($Unit)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -CreatedUnitMembership $Created
                }
                Mock New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Item = [PSCustomObject]@{ template = 'grp-{Region}'; tokens = [PSCustomObject]@{ Region = 'EU' }; administrativeUnit = $Unit; members = @() }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Created $Created -ErrorAction Stop)
                @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
                $Created.Count | Should -Be 1
                $Created[0].AdministrativeUnit | Should -BeExactly $Unit
                $Created[0].GroupId | Should -BeExactly '88888888-8888-8888-8888-888888888888'
                $Created[0].Label | Should -BeExactly 'grp-EU'
            }
        }

        It 'records nothing under -WhatIf, where the group is not created' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -CreatedUnitMembership $Created
                }
                Mock New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; administrativeUnit = 'AU-1'; members = @() }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Created $Created -WhatIf -ErrorAction Stop)
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq 'would create group grp-new' }).Count | Should -Be 1
                Should -Invoke New-OERGroup -Times 0
                $Created.Count | Should -Be 0
            }
        }

        It 'records nothing when the create fails' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -CreatedUnitMembership $Created
                }
                Mock New-OERGroup {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('No administrative unit found for ''AU-1''.'),
                        'AdministrativeUnitNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'AU-1')
                }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; administrativeUnit = 'AU-1'; members = @() }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Created $Created -ErrorAction SilentlyContinue)
                Should -Invoke New-OERGroup -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like 'group creation failed:*' }).Count | Should -Be 1
                $Created.Count | Should -Be 0
            }
        }

        It 'records nothing when New-OERGroup returns no object' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -CreatedUnitMembership $Created
                }
                Mock New-OERGroup { }
                $Created = [System.Collections.Generic.List[object]]::new()
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; administrativeUnit = 'AU-1'; members = @() }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -Created $Created -ErrorAction Stop)
                Should -Invoke New-OERGroup -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -eq 'New-OERGroup returned no object' }).Count | Should -Be 1
                $Created.Count | Should -Be 0
            }
        }

        It 'creates a group into a unit with no error when no list is given, as a direct call does' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                Mock New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; administrativeUnit = 'AU-1'; members = @() }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction Stop)
                Should -Invoke New-OERGroup -Times 1 -Exactly -ParameterFilter { $AdministrativeUnit -eq 'AU-1' }
                @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
            }
        }

        It 'records nothing for a group created without a unit: <Label>' -ForEach @(
            @{ Label = 'administrativeUnit omitted'; Json = '{ "displayName": "grp-new", "members": [] }' }
            @{ Label = 'administrativeUnit blank, which New-OERGroup ignores'; Json = '{ "displayName": "grp-new", "administrativeUnit": "", "members": [] }' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Json = $Json } {
                param($Json)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.List[object]]$Created)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -CreatedUnitMembership $Created
                }
                Mock New-OERGroup { [PSCustomObject]@{ Id = '88888888-8888-8888-8888-888888888888'; DisplayName = $DisplayName } }
                $Created = [System.Collections.Generic.List[object]]::new()
                $r = @(Invoke-SyncGroupViaCaller -Item ($Json | ConvertFrom-Json) -Created $Created -ErrorAction Stop)
                Should -Invoke New-OERGroup -Times 1 -Exactly
                @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
                $Created.Count | Should -Be 0
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

    Context 'pimPolicy approval -- emptying one approver side through the document' {
        # End to end through the REAL diff and the REAL Set-OERGroupPimPolicy: only the transport is
        # mocked. The live rule (beta shape) holds one user and one group; the document declares only
        # the side to clear, as "[]". The PATCH body must keep the other side from the live rule and
        # carry nothing on the cleared side -- which also proves the empty side reached Set as a BOUND
        # empty list, since an unbound side would have been carried from the live rule instead.
        It 'patches the rule with the live <Kept> kept and no <Cleared> when the document declares "approvers.<Side>": []' -ForEach @(
            @{ Side = 'groups'; Kept = 'user'; Cleared = 'group'; KeptType = '#microsoft.graph.singleUser'; KeptId = 'user-1' }
            @{ Side = 'users'; Kept = 'group'; Cleared = 'user'; KeptType = '#microsoft.graph.groupMembers'; KeptId = 'grp-1' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Side = $Side; KeptType = $KeptType; KeptId = $KeptId } {
                param($Side, $KeptType, $KeptId)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:Patches = [System.Collections.Generic.List[object]]::new()
                $script:LiveApproval = @{
                    id      = 'Approval_EndUser_Assignment'
                    setting = @{
                        isApprovalRequired               = $true
                        isApprovalRequiredForExtension   = $false
                        isRequestorJustificationRequired = $true
                        approvalMode                     = 'SingleStage'
                        approvalStages                   = @(@{
                                approvalStageTimeOutInDays      = 1
                                isApproverJustificationRequired = $true
                                escalationTimeInMinutes         = 0
                                isEscalationEnabled             = $false
                                primaryApprovers                = @(
                                    @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1'; description = 'Person One' }
                                    @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1'; description = 'Approvers' }
                                )
                                escalationApprovers             = @()
                            })
                    }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { '44444444-4444-4444-4444-444444444444' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = '44444444-4444-4444-4444-444444444444'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERPimGroupPolicyId { 'pol-1' }
                Mock Get-OERGroupPimPolicy {
                    ConvertTo-OERGroupPimPolicy -Rules @($script:LiveApproval) -GroupId '44444444-4444-4444-4444-444444444444' -PolicyId 'pol-1' -AccessType 'member'
                }
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'PATCH') { $script:Patches.Add($Body); return @{} }
                    if ($Uri -like '*rules/Approval_EndUser_Assignment') { return $script:LiveApproval }
                    return @{}
                }
                Mock Resolve-OERPrincipal { throw 'no approver value should need resolving: only an empty side is declared' }
                $Item = ('{ "displayName": "role_sec_x", "members": null, "pimPolicy": { "member": { "approvers": { "' + $Side + '": [] } } } }') | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction Stop)
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                $Body = @(@($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' })
                $Body.Count | Should -Be 1
                $Body[0].setting.isApprovalRequired | Should -BeTrue
                $Primary = @(@($Body[0].setting.approvalStages)[0].primaryApprovers)
                $Primary.Count | Should -Be 1
                $Primary[0].'@odata.type' | Should -Be $KeptType
                $Primary[0].id | Should -Be $KeptId
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
                # The record the real Resolve-OERPrincipal throws for a value that matches nothing.
                Mock Resolve-OERPrincipal {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("User 'nobody@example.com' was not found."), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'nobody@example.com')
                }
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

    Context 'pimPolicy step 4: a declared approver, missing, ambiguous and failed are three outcomes (Sprint 8 step 3, BL-14)' {
        # The real Resolve-OERDeclaredApprover and Resolve-OERPrincipal run here; only the lookups under
        # them answer, and the group itself ('role_sec_x' -> g-1) keeps an unfiltered mock, so the
        # filtered mocks answer only an approver value. The approver sits in the OWNER block: each
        # outcome is one Failed owner row carrying the record the handler published, the owner policy is
        # neither read nor written, and member still processes. The handler's own record is the one
        # whose id ends in ',Invoke-SyncGroupViaCaller': -ErrorVariable also collects what was thrown
        # inside.
        BeforeEach {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 8 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'missing-approvers' } { $null }
                Mock Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'dup-approvers' } {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new(
                            "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, " +
                            '22222222-2222-2222-2222-222222222222). Re-run with the object id instead of the display name.'),
                        'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup-approvers')
                }
                Mock Resolve-OERUserId -ParameterFilter { $UserPrincipalName -eq 'person9@example.com' } {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
                }
                function script:New-BL14Item ([string]$Side, [string]$Value) {
                    ('{ "displayName": "role_sec_x", "pimPolicy": { "member": { "activationMaxHours": 8 }, ' +
                    '"owner": { "requireApproval": true, "approvers": { "' + $Side + '": [ "' + $Value + '" ] } } } }') | ConvertFrom-Json
                }
            }
        }

        It 'reports an approver that matches nothing as ApproverNotFound, with the message, category and target it always had' {
            InModuleScope $script:moduleName {
                $r = @(Invoke-SyncGroupViaCaller -Item (New-BL14Item -Side 'groups' -Value 'missing-approvers') -ErrorAction SilentlyContinue -ErrorVariable Err)
                $OwnerFailed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(owner\)' })
                $OwnerFailed.Count | Should -Be 1
                $OwnerFailed[0].Detail | Should -Be "pimPolicy (owner) not applied: could not resolve an approver: Group 'missing-approvers' was not found."
                [string]$OwnerFailed[0].Error.FullyQualifiedErrorId | Should -Match '^ApproverNotFound'
                @($r | Where-Object { $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncGroupViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'ApproverNotFound,Invoke-SyncGroupViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
                $Own[0].TargetObject | Should -Be 'role_sec_x'
                $Own[0].Exception.Message | Should -Be "Could not resolve an approver declared in pimPolicy (owner) of group 'role_sec_x': Group 'missing-approvers' was not found."
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
            }
        }

        It 'reports an ambiguous approver name as AmbiguousApproverName naming the candidates, never as ApproverNotFound' {
            InModuleScope $script:moduleName {
                $r = @(Invoke-SyncGroupViaCaller -Item (New-BL14Item -Side 'groups' -Value 'dup-approvers') -ErrorAction SilentlyContinue -ErrorVariable Err)
                $OwnerFailed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(owner\)' })
                $OwnerFailed.Count | Should -Be 1
                $OwnerFailed[0].Detail | Should -Match '11111111-1111-1111-1111-111111111111'
                [string]$OwnerFailed[0].Error.FullyQualifiedErrorId | Should -Match '^AmbiguousApproverName'
                @($r | Where-Object { $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncGroupViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'AmbiguousApproverName,Invoke-SyncGroupViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
                $Own[0].TargetObject | Should -Be 'dup-approvers'
                $Own[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
                $Own[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
            }
        }

        It 'reports a failed approver lookup as itself, once, never as ApproverNotFound' {
            InModuleScope $script:moduleName {
                $r = @(Invoke-SyncGroupViaCaller -Item (New-BL14Item -Side 'users' -Value 'person9@example.com') -ErrorAction SilentlyContinue -ErrorVariable Err)
                $OwnerFailed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(owner\)' })
                $OwnerFailed.Count | Should -Be 1
                $OwnerFailed[0].Detail | Should -Match 'Insufficient privileges'
                [string]$OwnerFailed[0].Error.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
                @($r | Where-Object { $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-SyncGroupViaCaller' })
                $Own.Count | Should -Be 1
                $Own[0].FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied,Invoke-SyncGroupViaCaller'
                $Own[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
                Should -Invoke Set-OERGroupPimPolicy -Times 0 -ParameterFilter { $AccessType -eq 'owner' }
            }
        }

        It 'scrubs a failed approver lookup before it publishes it as itself' {
            InModuleScope $script:moduleName {
                Mock Resolve-OERDeclaredApprover -ParameterFilter { $Declared.PSObject.Properties.Name -contains 'approvers' } {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
                }
                Mock Resolve-OERDeclaredApprover { $Declared }
                Mock Remove-OERErrorRecord { }
                $null = @(Invoke-SyncGroupViaCaller -Item (New-BL14Item -Side 'users' -Value 'person9@example.com') -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the handler published the record as itself.
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Invoke-SyncGroupViaCaller' }).Count | Should -Be 1
                # A prefix match: $Caller.WriteError appends ',<command>' to this same record, in place,
                # before the filter is evaluated.
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    $Record -and [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' -and
                    $Record.Exception.Message -like '*Insufficient privileges*'
                }
            }
        }
    }

    Context 'pimPolicy step-4 wait for the policy of a group created in the same run' {
        # For a group THIS run created, step 4 ASKS Get-OERPimGroupPolicyId whether the access type's
        # policy is listed yet (a silent $null while it is not), then reads the listed policy through
        # Get-OERListedGroupPimPolicy instead of Get-OERGroupPimPolicy, waiting 2, 4, 8 and 16 s from
        # one budget shared by member and owner. Every test that can reach that poll mocks Start-Sleep
        # and records each wait in order.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
            }
        }

        It 'waits for a policy that is not listed yet, then applies it with no PimPolicyNotFound record left behind' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # One replication clock for every read: the policy is listed from the third look on,
                # whichever command looks. The public policy read models the real cmdlet: while nothing
                # is listed it writes a non-terminating PimPolicyNotFound, which -ErrorAction Stop turns
                # into a throw AND a record in the caller's -ErrorVariable.
                $script:Looks = 0
                Mock Get-OERPimGroupPolicyId {
                    $script:Looks++
                    if ($script:Looks -le 2) { $null } else { 'pol-member' }
                }
                Mock Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Get-OERGroupPimPolicy {
                    $script:Looks++
                    if ($script:Looks -le 2) {
                        Write-Error -Message "Group 'g-1' has no PIM-for-groups policy for 'member' access yet." `
                            -ErrorId 'PimPolicyNotFound' -Category ObjectNotFound -TargetObject 'g-1'
                        return
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
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                Should -Invoke Start-Sleep -Times 2 -Exactly
                @($script:Slept) | Should -Be @(2, 4)
                # The point of asking first, checked before the call counts so a poll through the
                # policy read fails HERE: a run that ends Updated hands the caller no PimPolicyNotFound
                # record. Polling Get-OERGroupPimPolicy -ErrorAction Stop left records per caught attempt.
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' }).Count | Should -Be 0
                Should -Invoke Get-OERPimGroupPolicyId -Times 3 -Exactly -ParameterFilter { $GroupId -eq 'g-1' -and $AccessType -eq 'member' }
                # The listed id is read directly; the public read, with its own lookup, is not used.
                Should -Invoke Get-OERListedGroupPimPolicy -Times 1 -Exactly -ParameterFilter {
                    $GroupId -eq 'g-1' -and $PolicyId -eq 'pol-member' -and $AccessType -eq 'member'
                }
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly
            }
        }

        It 'gives up after the 30-second wait with a replication message and one PimPolicyNotFound record' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Get-OERPimGroupPolicyId { $null }
                Mock Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                Should -Invoke Start-Sleep -Times 4 -Exactly
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                # Nothing listed, so nothing is read and nothing is set.
                Should -Invoke Get-OERListedGroupPimPolicy -Times 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(member\)' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'replication delay'
                $Failed[0].Detail | Should -Match 'within the 30-second wait'
                # M2: no retry count (a shared budget made the owner row read "after 0 retries"), and
                # no cmdlet named.
                $Failed[0].Detail | Should -Not -Match 'retries'
                $Failed[0].Detail | Should -Not -Match 'Add-OERGroupEligibility'
                $Failed[0].Detail | Should -BeExactly ("pimPolicy (member) not applied: Microsoft Graph does not list a " +
                    "PIM-for-groups policy for 'member' access on group 'role_sec_x', created in this run, within the " +
                    "30-second wait. A new group's policies can take a while to be listed (replication delay); " +
                    're-running the same document usually applies them.')
                # The Failed row carries the same record whether or not $Caller.WriteError ran; the
                # narrowed -ErrorVariable count is what proves it reached the caller.
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match 'PimPolicyNotFound'
                @($Err | Where-Object {
                        [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' -and
                        $_.Exception.Message -like '*within the 30-second wait*'
                    }).Count | Should -Be 1
            }
        }

        It 'never advises about eligibility when the wait runs out, <Case>' -ForEach @(
            @{ Case = 'the document declaring no eligibility'; Eligibility = $null; AddFails = $false }
            @{ Case = 'the declared eligibility applied in this run'; Eligibility = 30; AddFails = $false }
            @{ Case = 'the declared eligibility failed in this run'; Eligibility = 30; AddFails = $true }
        ) {
            # Graph lists a group's policies whether or not it was ever onboarded, and the first policy
            # update onboards it (Microsoft Graph documentation, "Onboarding groups to PIM for Groups"),
            # so an unlisted policy is replication whatever the document declares: the message names
            # replication and a re-run, and never tells the operator to declare or add an eligibility.
            InModuleScope $script:moduleName -Parameters @{ Eligibility = $Eligibility; AddFails = $AddFails } {
                param($Eligibility, $AddFails)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # The group is created in this run, so its time-bound eligibility is written by the
                # private request, not by Add-OERGroupEligibility.
                if ($AddFails) {
                    Mock Send-OERNewGroupEligibilityRequest { throw 'the group is too new for PIM for Groups' }
                } else {
                    Mock Send-OERNewGroupEligibilityRequest { @{ id = 'req-1' } }
                }
                Mock Get-OERPimGroupPolicyId { $null }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    members     = $null
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                if ($null -ne $Eligibility) {
                    $Item | Add-Member -NotePropertyName eligibility -NotePropertyValue @(
                        [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = $Eligibility })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(member\)' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'within the 30-second wait'
                $Failed[0].Detail | Should -Match 'replication delay'
                $Failed[0].Detail | Should -Match 're-running the same document usually applies them'
                $Failed[0].Detail | Should -Not -Match 'eligibility'
                $Failed[0].Detail | Should -Not -Match 'onboard'
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
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Get-OERPimGroupPolicyId { $null }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
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
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                # member spends the whole budget (five looks, four waits); owner finds it spent and
                # looks once.
                Should -Invoke Get-OERPimGroupPolicyId -Times 5 -Exactly -ParameterFilter { $AccessType -eq 'member' }
                Should -Invoke Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \((member|owner)\)' })
                $Failed.Count | Should -Be 2
                @($Failed | Where-Object { $_.Detail -match 'retries' }).Count | Should -Be 0
            }
        }

        It 'stops waiting at once when the lookup is refused (403), and reads and sets as for any group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Get-OERPimGroupPolicyId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges'), 'GraphHttpError',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, 'g-1')
                }
                Mock Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
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
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                Should -Invoke Get-OERPimGroupPolicyId -Times 1 -Exactly
                Should -Invoke Get-OERListedGroupPimPolicy -Times 0
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
                @($r | Where-Object { $_.Detail -match 'within the 30-second wait' }).Count | Should -Be 0
            }
        }

        It 'never polls or waits for the policy of an existing group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # A listed id, so a poll that ran anyway would neither sleep nor fail: only the call
                # count below can catch it.
                Mock Get-OERPimGroupPolicyId { 'pol-member' }
                Mock Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
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
                Should -Invoke Get-OERPimGroupPolicyId -Times 0
                Should -Invoke Get-OERListedGroupPimPolicy -Times 0
                Should -Invoke Start-Sleep -Times 0
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            }
        }
    }

    Context 'pimPolicy step-4 wait: 404 ResourceNotFound while PIM does not know the new group yet' {
        # Measured live 2026-09-28: right after a group is created, the policy-assignment query for it
        # answers 404 ResourceNotFound, not an empty list, and a few seconds later it lists both
        # policies; and a policy the query has just listed can answer the read of its rules with 404 a
        # second later (replicas that do not agree yet). These tests drive the REAL
        # Get-OERPimGroupPolicyId and Get-OERListedGroupPimPolicy against a transport mock that behaves
        # like Invoke-OERGraphRequest: a code the request DECLARED comes back as the GraphExpectedError
        # marker, and any other failure is thrown as the converted record. $script:Calls records the
        # order of listings and reads.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
                $script:Looks = 0
                $script:Reads = 0
                $script:Calls = [System.Collections.Generic.List[string]]::new()
                $script:DeclaredNotFound = [System.Collections.Generic.List[bool]]::new()
                $script:ReadDeclaredNotFound = [System.Collections.Generic.List[bool]]::new()
                $script:NotFoundAnswer = {
                    param([string]$Uri, [string[]]$ExpectedErrorCode)
                    if (@($ExpectedErrorCode) -contains 'ResourceNotFound') {
                        $Marker = [PSCustomObject]@{
                            ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404
                            Message = 'ResourceNotFound: The resource is not found.'; Uri = $Uri
                        }
                        $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                        return $Marker
                    }
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ResourceNotFound: The resource is not found.'),
                        'ResourceNotFound', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                }
                $script:ForbiddenAnswer = {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                }
                $script:Transport = {
                    param([string]$Uri, [string[]]$ExpectedErrorCode, [int]$NotFoundLooks, [switch]$Forbidden,
                        [int]$ReadNotFound, [switch]$ReadForbidden)
                    if ($Uri -like '*roleManagementPolicyAssignments*') {
                        $script:Looks++
                        $script:Calls.Add('list')
                        $script:DeclaredNotFound.Add((@($ExpectedErrorCode) -contains 'ResourceNotFound'))
                        if ($Forbidden) { & $script:ForbiddenAnswer }
                        if ($script:Looks -le $NotFoundLooks) { return (& $script:NotFoundAnswer -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode) }
                        return @{ value = @(
                                [PSCustomObject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }
                                [PSCustomObject]@{ roleDefinitionId = 'owner'; policyId = 'pol-owner' }
                            ) }
                    }
                    if ($Uri -like '*roleManagementPolicies/pol-*/rules') {
                        $script:Reads++
                        $script:Calls.Add('read')
                        $script:ReadDeclaredNotFound.Add((@($ExpectedErrorCode) -contains 'ResourceNotFound'))
                        if ($ReadForbidden) { & $script:ForbiddenAnswer }
                        if ($script:Reads -le $ReadNotFound) { return (& $script:NotFoundAnswer -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode) }
                        return @{ value = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H' }) }
                    }
                    throw "unexpected request: $Uri"
                }
            }
        }

        It 'waits through a 404 for a group created in this run, then applies the policy with no error record left' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 2 }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Two 404s, two waits, then listed on the third look and read once.
                @($script:Slept) | Should -Be @(2, 4)
                $script:Looks | Should -Be 3
                @($script:Calls) | Should -Be @('list', 'list', 'list', 'read')
                @($script:DeclaredNotFound | Where-Object { -not $_ }).Count | Should -Be 0
                @($script:ReadDeclaredNotFound) | Should -Be @($true)
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            }
        }

        It 'reports Failed with the replication message when the 404 outlasts the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 99 }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Looks | Should -Be 5
                $script:Reads | Should -Be 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(member\)' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match 'within the 30-second wait'
                $Failed[0].Detail | Should -Match 'replication delay'
                $Failed[0].Detail | Should -Not -Match 'eligibility'
                # Only the PimPolicyNotFound of the Failed row: none of the five 404s left a record.
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' }).Count | Should -Be 1
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -notlike 'PimPolicyNotFound*' }).Count | Should -Be 0
            }
        }

        It 'never waits on a 404 for a group that already existed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # The REAL policy read, so the 404 reaches it exactly as it would live.
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 99 }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $null = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                Should -Invoke Start-Sleep -Times 0
                # One look, the policy read's own, and it did not declare the 404 as an answer: for a
                # group that already existed a 404 stays a failed read.
                $script:Looks | Should -Be 1
                $script:Reads | Should -Be 0
                @($script:DeclaredNotFound) | Should -Be @($false)
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyReadFailed*' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'never waits on a 404 from the policy read of a group that already existed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # Listed, but the read of the listed policy answers 404: the public read gets it as is.
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -ReadNotFound 99 }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $null = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                # One listing and one read, both Get-OERGroupPimPolicy's own, and neither declared the
                # 404 as an answer.
                @($script:Calls) | Should -Be @('list', 'read')
                @($script:DeclaredNotFound) | Should -Be @($false)
                @($script:ReadDeclaredNotFound) | Should -Be @($false)
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            }
        }

        It 'starts over from the listing when the listed policy answers its read with 404, then applies it with no error record left' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -ReadNotFound 1 }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Listed, read 404, one wait, then listed AGAIN before the second read: the read's 404
                # leads back to the listing, never to a second read of the same id.
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read')
                @($script:Slept) | Should -Be @(2)
                @($script:ReadDeclaredNotFound) | Should -Be @($true, $true)
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
            }
        }

        It 'spends the one budget across a 404 on the listing and a 404 on the read' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 1 -ReadNotFound 1 }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                @($script:Calls) | Should -Be @('list', 'list', 'read', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4)
                # The live checklist counts the wait lines by their '; retry <n> in <s> s.' ending, and
                # tells the two causes apart by the words before it.
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: pimPolicy (member) of new group 'role_sec_x' is not listed yet; retry 1 in 2 s."
                    "Sync-OERStructureGroup: pimPolicy (member) of new group 'role_sec_x' is listed but its read answers 404; retry 2 in 4 s.")
                ($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\)' }).Count | Should -Be 1
                @($Err).Count | Should -Be 0
            }
        }

        It 'reports Failed with PimPolicyNotFound, never PimPolicyReadFailed, when the listed policy answers 404 for the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -ReadNotFound 99 }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Five listings, five reads, four waits: the whole budget, and not one second more.
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read', 'list', 'read', 'list', 'read', 'list', 'read')
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'pimPolicy \(member\)' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ("pimPolicy (member) not applied: Microsoft Graph does not list a " +
                    "PIM-for-groups policy for 'member' access on group 'role_sec_x', created in this run, within the " +
                    "30-second wait. A new group's policies can take a while to be listed (replication delay); " +
                    're-running the same document usually applies them.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^PimPolicyNotFound'
                # Exactly one record, the Failed row's own PimPolicyNotFound: none of the ten 404s left
                # one, and nothing reports the read as failed.
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' }).Count | Should -Be 1
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyReadFailed*' }).Count | Should -Be 0
                @($Err).Count | Should -Be 1
            }
        }

        It 'never waits when the read of a listed policy is refused (403), and reads and sets as for any group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -ReadForbidden }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                @($script:Calls) | Should -Be @('list', 'read')
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly -ParameterFilter { $ActivationMaxHours -eq 4 }
                @($r | Where-Object { $_.Detail -match 'within the 30-second wait' }).Count | Should -Be 0
            }
        }

        It 'never waits when the lookup is refused (403), even for a group created in this run' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode -Forbidden }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $null = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                $script:Looks | Should -Be 1
                Should -Invoke Get-OERGroupPimPolicy -Times 1 -Exactly
            }
        }
    }

    Context 'eligibility of a group created in the same run: 404 ResourceNotFound is replication (Sprint 7 step 3)' {
        # Measured live 2026-09-28 for the policy calls, and the same replication delay for the first
        # eligibility request: right after a group is created, PIM for Groups can answer with 404
        # ResourceNotFound, not with a refusal. For a group THIS run created, step 3 sends the
        # time-bound request through Send-OERNewGroupEligibilityRequest, which declares the 404 to the
        # transport, and waits from the same 2/4/8/16 s budget as step 4; step 5 first waits, silently,
        # until Graph lists the group's policy AND that policy answers its read, and then calls
        # Add-OERGroupEligibility once. These tests drive the REAL helper, the REAL
        # Get-OERPimGroupPolicyId and the REAL Get-OERListedGroupPimPolicy against a transport mock that
        # behaves like Invoke-OERGraphRequest: a code the request DECLARED comes back as the
        # GraphExpectedError marker, and any other failure is thrown as the converted record, so a
        # missing declaration shows up as a Failed row and a wrong record count. $script:Calls records
        # the order of policy listings and policy reads.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
                $script:Posts = 0
                $script:Looks = 0
                $script:Reads = 0
                $script:Calls = [System.Collections.Generic.List[string]]::new()
                $script:ReadDeclaredNotFound = [System.Collections.Generic.List[bool]]::new()
                $script:PostBodies = [System.Collections.Generic.List[object]]::new()
                $script:PostDeclaredNotFound = [System.Collections.Generic.List[bool]]::new()
                $script:NotFoundAnswer = {
                    param([string]$Uri, [string[]]$ExpectedErrorCode)
                    if (@($ExpectedErrorCode) -contains 'ResourceNotFound') {
                        $Marker = [PSCustomObject]@{
                            ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404
                            Message = 'ResourceNotFound: The resource is not found.'; Uri = $Uri
                        }
                        $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                        return $Marker
                    }
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ResourceNotFound: The resource is not found.'),
                        'ResourceNotFound', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                }
                $script:Transport = {
                    param([string]$Method, [string]$Uri, $Body, [string[]]$ExpectedErrorCode,
                        [int]$PostNotFound, [int]$NotFoundLooks, [switch]$PostForbidden, [switch]$PostOtherStatus, [switch]$ListForbidden,
                        [int]$ReadNotFound, [switch]$ReadForbidden, [int]$PostFailed, [string]$PostStatus = 'Provisioned',
                        [string]$FailedStatus = 'Failed')
                    if ($Uri -like '*eligibilityScheduleRequests*') {
                        $script:Posts++
                        $script:PostBodies.Add($Body)
                        $script:PostDeclaredNotFound.Add((@($ExpectedErrorCode) -contains 'ResourceNotFound'))
                        if ($PostForbidden) {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                        }
                        if ($PostOtherStatus -and (@($ExpectedErrorCode) -contains 'ResourceNotFound')) {
                            # Graph's code, but not the 404 that means "not known yet".
                            $Marker = [PSCustomObject]@{
                                ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 400
                                Message = 'ResourceNotFound: the request names a resource that does not exist.'; Uri = $Uri
                            }
                            $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                            return $Marker
                        }
                        if ($script:Posts -le $PostNotFound) { return (& $script:NotFoundAnswer -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode) }
                        # Measured live 2026-10-03: after the 404s, Graph can ACCEPT a new group's request
                        # (201) and fail it at once -- the 201 body already says status Failed.
                        if ($script:Posts -le ($PostNotFound + $PostFailed)) { return @{ id = "req-$($script:Posts)"; status = $FailedStatus } }
                        return @{ id = "req-$($script:Posts)"; status = $PostStatus }
                    }
                    if ($Uri -like '*roleManagementPolicyAssignments*') {
                        $script:Looks++
                        $script:Calls.Add('list')
                        if ($ListForbidden) {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                        }
                        if ($script:Looks -le $NotFoundLooks) { return (& $script:NotFoundAnswer -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode) }
                        return @{ value = @(
                                [PSCustomObject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }
                                [PSCustomObject]@{ roleDefinitionId = 'owner'; policyId = 'pol-owner' }
                            ) }
                    }
                    if ($Uri -like '*roleManagementPolicies/pol-*/rules') {
                        # A policy listed a moment ago can answer its read with 404 (measured live
                        # 2026-09-28, replicas that do not agree yet).
                        $script:Reads++
                        $script:Calls.Add('read')
                        $script:ReadDeclaredNotFound.Add((@($ExpectedErrorCode) -contains 'ResourceNotFound'))
                        if ($ReadForbidden) {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                        }
                        if ($script:Reads -le $ReadNotFound) { return (& $script:NotFoundAnswer -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode) }
                        return @{ value = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H' }) }
                    }
                    throw "unexpected request: $Uri"
                }
            }
        }

        It 'waits through a 404 on a new group''s time-bound eligibility, then applies it with no error record left' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 2 }
                # Any call is visible: a new group's time-bound write never goes through the cmdlet.
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for a new group''s time-bound eligibility' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Two 404s, two waits, then the third request goes through.
                @($script:Slept) | Should -Be @(2, 4)
                $script:Posts | Should -Be 3
                # Every request declared the 404 to the transport: an undeclared one is thrown by the
                # transport mock and would be a Failed row, not a wait.
                @($script:PostDeclaredNotFound | Where-Object { -not $_ }).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                # The group row is Created; the eligibility row stays Updated (Ruling R1).
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -Be 1
                @($Err).Count | Should -Be 0
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'reports Failed with the replication message when the 404 outlasts the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 99 }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for a new group''s time-bound eligibility' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Posts | Should -Be 5
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ("eligibility for 'person9@example.com' (member) not applied: for group 'role_sec_x', created in this run, " +
                    'Microsoft Graph answered 404 ResourceNotFound, or accepted the request but answered status Failed, every ' +
                    'time within the 30-second wait. A new group can take a while to be known to PIM for Groups (replication ' +
                    'delay); re-running the same document usually applies it.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^ResourceNotFound'
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                # Exactly the Failed row's own record, published through $Caller.WriteError: none of the
                # five 404s left one.
                @($Err).Count | Should -Be 1
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'waits through an accepted request that answers status Failed on a new group''s time-bound eligibility, then applies it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for a new group''s time-bound eligibility' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                # The first request is accepted but answered Failed (the live run of 2026-10-03): one
                # wait, then the second request is applied.
                @($script:Slept) | Should -Be @(2)
                $script:Posts | Should -Be 2
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: eligibility for 'person9@example.com' (member) on new group 'role_sec_x' was accepted but answered status Failed (not ready in PIM for Groups yet); retry 1 in 2 s.")
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'spends one budget on a 404 and then an accepted request that answers status Failed, both on a new group''s time-bound eligibility' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # The Failed answer arrives in lower case: the status is compared case-insensitively.
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 1 -PostFailed 1 -FailedStatus 'failed' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                # Both phases of the replication window draw on the same queue: 2 for the 404, 4 (not
                # a fresh 2) for the accepted-but-Failed request.
                @($script:Slept) | Should -Be @(2, 4)
                $script:Posts | Should -Be 3
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: eligibility for 'person9@example.com' (member) on new group 'role_sec_x' answers 404 (not known to PIM for Groups yet); retry 1 in 2 s."
                    "Sync-OERStructureGroup: eligibility for 'person9@example.com' (member) on new group 'role_sec_x' was accepted but answered status Failed (not ready in PIM for Groups yet); retry 2 in 4 s.")
            }
        }

        It 'reports Failed with the replication message when an accepted request answers status Failed for the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 99 }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for a new group''s time-bound eligibility' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Posts | Should -Be 5
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ("eligibility for 'person9@example.com' (member) not applied: for group 'role_sec_x', created in this run, " +
                    'Microsoft Graph answered 404 ResourceNotFound, or accepted the request but answered status Failed, every ' +
                    'time within the 30-second wait. A new group can take a while to be known to PIM for Groups (replication ' +
                    'delay); re-running the same document usually applies it.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^ResourceNotFound'
                # A request Graph answered Failed is not an applied one.
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                @($Err).Count | Should -Be 1
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'waits through an accepted request answered <FailedStatus> on a new group''s time-bound eligibility, as through Failed, then applies it (BL-33, Ruling R3)' -ForEach @(
            @{ FailedStatus = 'FAILED' }
            @{ FailedStatus = 'FailedAsResourceIsLocked' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ FailedStatus = $FailedStatus } {
                param($FailedStatus)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # The wait asks Test-OERScheduleRequestFailed, so every value of the Failed family, in
                # any letter case, is "not applied yet" -- not only the exact value Failed.
                $script:FailedAnswer = $FailedStatus
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 -FailedStatus $script:FailedAnswer }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for a new group''s time-bound eligibility' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The first request is answered in the Failed family: one wait, then the second request
                # is applied.
                @($script:Slept) | Should -Be @(2)
                $script:Posts | Should -Be 2
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'treats an accepted request with any status other than Failed as applied, and never waits on it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostStatus 'PendingProvisioning' }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The request was made and answered, so the no-wait below is a decision, not an absence.
                $script:Posts | Should -Be 1
                Should -Invoke Start-Sleep -Times 0
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'never waits on a 404 for a group that already existed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 99 }
                # A cmdlet failure mock, never Write-Error: the handler calls the cmdlet with
                # -ErrorAction Stop, and only the cmdlet's own WriteError is promoted by it.
                Mock Add-OERGroupEligibility {
                    [CmdletBinding()] param($Group, $PrincipalId, $AccessType, $DurationDays, $Action)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('ResourceNotFound: The resource is not found.'),
                            'ResourceNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'g-1'))
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # The cmdlet was reached, so the 404 was the one this run is meant to leave alone.
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                Should -Invoke Start-Sleep -Times 0
                # The new request is for a group created in this run only.
                $script:Posts | Should -Be 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike 'failed to add eligibility for *'
            }
        }

        It 'reports a status Failed on a time-bound eligibility of a group that already existed as a Failed row with EligibilityRequestFailed, and never waits on it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # Only a group THIS run created treats status Failed as replication. For a group that
                # already existed the REAL Add-OERGroupEligibility reports Graph's Failed answer as its
                # EligibilityRequestFailed error (Sprint 8 step 3, BL-04), so nothing was granted and the
                # write is Failed, never Updated. The cmdlet resolves its own inputs: a GUID-shaped
                # principal, and the group id answers for itself.
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) '99999999-0000-0000-0000-000000000009' }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                # The cmdlet sent the request once; Graph accepted it and answered Failed.
                $script:Posts | Should -Be 1
                @($script:PostDeclaredNotFound) | Should -Be @($false)
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^EligibilityRequestFailed'
                $Failed[0].Detail | Should -BeExactly ("failed to add eligibility for 'person9@example.com': Microsoft Graph accepted the PIM member " +
                    "eligibility request 'req-1' for principal '99999999-0000-0000-0000-000000000009' on group 'g-1' but answered " +
                    'status Failed, so nothing was granted; re-running the same request usually succeeds (a group created moments ' +
                    'ago can take a while to be known to PIM for Groups).')
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
            }
        }

        It 'reports a status Failed on a permanent eligibility of a group that already existed as a Failed row with EligibilityRequestFailed, and never waits on it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # Only a group THIS run created treats status Failed as replication. For a group that
                # already existed the REAL Add-OERGroupEligibility reports Graph's Failed answer as its
                # EligibilityRequestFailed error (Sprint 8 step 3, BL-04), so nothing was granted and the
                # write is Failed, never Updated. The cmdlet resolves its own inputs: a GUID-shaped
                # principal, and the group id answers for itself.
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) '16161616-0000-0000-0000-000000000016' }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                # An existing group never probes its policy before the cmdlet: the one listing and the
                # one read are the cmdlet's own permanent pre-check (a new group would be polled first).
                @($script:Calls) | Should -Be @('list', 'read')
                $script:Posts | Should -Be 1
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^EligibilityRequestFailed'
                $Failed[0].Detail | Should -BeExactly ("failed to add permanent eligibility for 'person16@example.com': Microsoft Graph accepted the PIM member " +
                    "eligibility request 'req-1' for principal '16161616-0000-0000-0000-000000000016' on group 'g-1' but answered " +
                    'status Failed, so nothing was granted; re-running the same request usually succeeds (a group created moments ' +
                    'ago can take a while to be known to PIM for Groups).')
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
            }
        }

        It 'shares one budget with the pimPolicy wait' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 2 -NotFoundLooks 1 }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # The eligibility spends 2 and 4; the policy wait finds the budget at 8, not at 2.
                @($script:Slept) | Should -Be @(2, 4, 8)
                $script:Posts | Should -Be 3
                $script:Looks | Should -Be 2
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'pimPolicy \(member\) set' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            }
        }

        It 'never waits when the new eligibility request is refused (403)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostForbidden }
                # The scrub proof: the record the catch scrubs is the refusal itself.
                Mock Remove-OERErrorRecord { param($Record) }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                Should -Invoke Start-Sleep -Times 0
                $script:Posts | Should -Be 1
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike 'failed to add eligibility for *'
                # Reported as itself, never as replication.
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
                $Failed[0].Detail | Should -Not -Match 'replication'
                # A refused request is not an applied one.
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*'
                }
            }
        }

        It 'never waits on a ResourceNotFound that arrives with a status other than 404, and reports it as itself' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostOtherStatus }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # The request was made and answered, so the no-wait below is a decision, not an absence.
                $script:Posts | Should -Be 1
                Should -Invoke Start-Sleep -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike 'failed to add eligibility for *'
                $Failed[0].Detail | Should -Not -Match 'replication'
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^ResourceNotFound'
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
            }
        }

        It 'carries the owner access type through the new request and the replication message' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 99 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; accessType = 'owner'; durationDays = 5 })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                $script:Posts | Should -Be 5
                @($script:PostBodies | Where-Object { $_.accessId -eq 'owner' }).Count | Should -Be 5
                @($script:PostBodies | Where-Object { $_.groupId -eq 'g-1' -and $_.principalId -eq 'id-person9@example.com' -and $_.action -eq 'adminAssign' }).Count | Should -Be 5
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -Match '\(owner\)'
                $Failed[0].Detail | Should -BeExactly ("eligibility for 'person9@example.com' (owner) not applied: for group 'role_sec_x', created in this run, " +
                    'Microsoft Graph answered 404 ResourceNotFound, or accepted the request but answered status Failed, every ' +
                    'time within the 30-second wait. A new group can take a while to be known to PIM for Groups (replication ' +
                    'delay); re-running the same document usually applies it.')
            }
        }

        It 'shares the budget between two entries of one new group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # The first two requests of the item answer 404, whichever entry sends them.
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 2 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @(
                        [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 },
                        [PSCustomObject]@{ principal = 'person10@example.com'; durationDays = 7 }
                    )
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The first entry waits twice; once Graph knows the group the second goes through at
                # once, with no fresh 30 seconds of its own.
                @($script:Slept) | Should -Be @(2, 4)
                $script:Posts | Should -Be 4
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 2
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'never gives a second entry a fresh budget when the new group stays unknown for the whole wait' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 99 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @(
                        [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 },
                        [PSCustomObject]@{ principal = 'person10@example.com'; durationDays = 7 }
                    )
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # ONE 30-second budget for the item: the first entry spends all of it (five requests,
                # four waits) and the second finds it spent, so it asks once and fails at once. A fresh
                # budget per entry would sleep 2, 4, 8, 16 twice and send ten requests.
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Posts | Should -Be 6
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 2
                @($Failed | Where-Object { $_.Detail -like "eligibility for 'person9@example.com' (member) not applied: *" }).Count | Should -Be 1
                @($Failed | Where-Object { $_.Detail -like "eligibility for 'person10@example.com' (member) not applied: *" }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                # Exactly the two Failed rows' own records: none of the six 404s left one.
                @($Err).Count | Should -Be 2
            }
        }

        It 'shares the budget between a time-bound and a permanent eligibility of one new group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # The first two requests and the first listing answer 404, whichever step asks.
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 2 -NotFoundLooks 1 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @(
                        [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 },
                        [PSCustomObject]@{ principal = 'person16@example.com' }
                    )
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Step 3 spends 2 and 4; step 5 finds the budget at 8, not at 2.
                @($script:Slept) | Should -Be @(2, 4, 8)
                $script:Posts | Should -Be 3
                $script:Looks | Should -Be 2
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'time-bound member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'never waits when the policy listing is refused (403) for a new group''s permanent eligibility, and calls Add-OERGroupEligibility as for any group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -ListForbidden }
                Mock Add-OERGroupEligibility { }
                # The scrub proof: the record the poll's catch scrubs is the refusal itself.
                Mock Remove-OERErrorRecord { param($Record) }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # One listing, refused: the refusal ends the poll, it is never waited on and never
                # reported as replication.
                Should -Invoke Start-Sleep -Times 0
                $script:Looks | Should -Be 1
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'replication' }).Count | Should -Be 0
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*'
                }
            }
        }
        It 'waits for the policy listing before a new group''s permanent eligibility, then calls Add-OERGroupEligibility once' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 1 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # One 404 on the listing, one wait, then the policy is listed and the cmdlet runs.
                @($script:Slept) | Should -Be @(2)
                $script:Looks | Should -Be 2
                $script:Posts | Should -Be 0
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter {
                    $Group -eq 'g-1' -and $PrincipalId -eq 'id-person16@example.com' -and $AccessType -eq 'member'
                }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'reports Failed with the replication message when a new group''s policy is not listed for the whole budget, and never calls Add-OERGroupEligibility' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 99 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Looks | Should -Be 5
                # Never listed, so never read.
                @($script:Calls) | Should -Be @('list', 'list', 'list', 'list', 'list')
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it. No eligibility request was sent, so no ' +
                    'PIM-for-groups policy was opened for it.')
                # The id Add-OERGroupEligibility publishes for the same condition, not the transport's.
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^GroupNotOnboarded'
                # Exactly the Failed row's own record: none of the five 404s left one.
                @($Err).Count | Should -Be 1
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
            }
        }

        It 'waits until a new group''s listed policy answers its read before the permanent eligibility, then calls Add-OERGroupEligibility once' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                # Listed at once, but the read of the listed policy answers 404 once.
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -ReadNotFound 1 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Listed, read 404, one wait, then listed AGAIN before the second read: the read's 404
                # leads back to the listing, as in step 4. The cmdlet's own pre-check reads the same
                # policy, and an unreadable one there leaves the policy closed and the POST refused.
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read')
                @($script:Slept) | Should -Be @(2)
                @($script:ReadDeclaredNotFound) | Should -Be @($true, $true)
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly -ParameterFilter {
                    $Group -eq 'g-1' -and $PrincipalId -eq 'id-person16@example.com' -and $AccessType -eq 'member'
                }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'never waits when the read of a new group''s listed policy is refused (403), and calls Add-OERGroupEligibility as for any group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -ReadForbidden }
                Mock Add-OERGroupEligibility { }
                # The scrub proof: the record the read's catch scrubs is the refusal itself.
                Mock Remove-OERErrorRecord { param($Record) }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # One listing and one read, refused: the refusal ends the poll, it is never waited on
                # and never reported as replication.
                @($script:Calls) | Should -Be @('list', 'read')
                Should -Invoke Start-Sleep -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($r | Where-Object { $_.Detail -match 'within the 30-second wait' }).Count | Should -Be 0
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*'
                }
            }
        }

        It 'reports Failed with GroupNotOnboarded and never calls Add-OERGroupEligibility when a new group''s listed policy answers 404 for the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -ReadNotFound 99 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Five listings, five reads, four waits: the whole budget, and not one second more.
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read', 'list', 'read', 'list', 'read', 'list', 'read')
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it. No eligibility request was sent, so no ' +
                    'PIM-for-groups policy was opened for it.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^GroupNotOnboarded'
                # Exactly the Failed row's own record: none of the ten 404s left one.
                @($Err).Count | Should -Be 1
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
            }
        }

        It 'waits through a permanent request that Add-OERGroupEligibility returns with status Failed on a new group, polls the policy again, then applies it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode }
                # The cmdlet's request object carries Graph's status (ConvertTo-OERGroupEligibilityRequest
                # stamps Status): Failed on the first call, Provisioned on the second.
                $script:AddCalls = 0
                Mock Add-OERGroupEligibility {
                    $script:AddCalls++
                    $script:Calls.Add('add')
                    [PSCustomObject]@{ Status = $(if ($script:AddCalls -le 1) { 'Failed' } else { 'Provisioned' }) }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                # Ready, called, answered Failed, one wait from the shared budget, then the readiness
                # poll runs AGAIN before the second call.
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add')
                @($script:Slept) | Should -Be @(2)
                Should -Invoke Add-OERGroupEligibility -Times 2 -Exactly -ParameterFilter {
                    $Group -eq 'g-1' -and $PrincipalId -eq 'id-person16@example.com' -and $AccessType -eq 'member'
                }
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                # The returned request object is never emitted as a row.
                @($r | Where-Object { $_.PSObject.Properties.Name -contains 'Status' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: permanent eligibility for 'person16@example.com' (member) on new group 'role_sec_x' was accepted but answered status Failed (not ready in PIM for Groups yet); retry 1 in 2 s.")
            }
        }

        It 'spends one budget on a new group''s unlisted policy and then a permanent request answered status Failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 1 }
                $script:AddCalls = 0
                # The Failed answer arrives in lower case: the status is compared case-insensitively.
                Mock Add-OERGroupEligibility {
                    $script:AddCalls++
                    $script:Calls.Add('add')
                    [PSCustomObject]@{ Status = $(if ($script:AddCalls -le 1) { 'failed' } else { 'Provisioned' }) }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                # The unlisted policy spends 2; the Failed status finds the budget at 4, not at a fresh 2,
                # and the retry count runs on across both causes.
                @($script:Calls) | Should -Be @('list', 'list', 'read', 'add', 'list', 'read', 'add')
                @($script:Slept) | Should -Be @(2, 4)
                Should -Invoke Add-OERGroupEligibility -Times 2 -Exactly
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: the member policy of new group 'role_sec_x' is not listed yet, so its permanent eligibility for 'person16@example.com' waits; retry 1 in 2 s."
                    "Sync-OERStructureGroup: permanent eligibility for 'person16@example.com' (member) on new group 'role_sec_x' was accepted but answered status Failed (not ready in PIM for Groups yet); retry 2 in 4 s.")
            }
        }

        It 'treats a new group''s permanent request returned with any status other than Failed as applied, and never waits on it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode }
                Mock Add-OERGroupEligibility {
                    $script:Calls.Add('add')
                    [PSCustomObject]@{ Status = 'PendingProvisioning' }
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Ready at once, called once, and a status that is not Failed ends it: only Failed is
                # replication, not "anything but Provisioned".
                @($script:Calls) | Should -Be @('list', 'read', 'add')
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                Should -Invoke Start-Sleep -Times 0
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
            }
        }

        It 'reports Failed with GroupNotOnboarded when a new group''s permanent request answers status Failed for the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode }
                Mock Add-OERGroupEligibility { [PSCustomObject]@{ Status = 'Failed' } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Five calls, four waits: the whole budget, and not one second more.
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                # BL-51 case 6: this fixture's rules lack Expiration_Admin_Eligibility, so the read after the requests finds no boolean.
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it. Its PIM-for-groups policy for ''member'' access ' +
                    'may have been opened to allow permanent eligibility before the request was sent, and it could not ' +
                    'be read afterwards. If it allows permanent eligibility, close it with ''Set-OERGroupPimPolicy ' +
                    '-Group ''''g-1'''' -AccessType member -AllowPermanentEligibility:$false'' if you do not intend to retry.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^GroupNotOnboarded'
                # A request Graph answered Failed is not an applied one.
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                @($Err).Count | Should -Be 1
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
            }
        }

        It 'writes permanent-eligibility wait lines that end in "; retry N in S s." and name the cause' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -NotFoundLooks 1 -ReadNotFound 1 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -Verbose 4>&1)
                @($script:Calls) | Should -Be @('list', 'list', 'read', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4)
                # The live checklist counts the wait lines by their '; retry <n> in <s> s.' ending, and
                # tells the two causes apart by the words before it.
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: the member policy of new group 'role_sec_x' is not listed yet, so its permanent eligibility for 'person16@example.com' waits; retry 1 in 2 s."
                    "Sync-OERStructureGroup: the member policy of new group 'role_sec_x' is listed but its read answers 404, so its permanent eligibility for 'person16@example.com' waits; retry 2 in 4 s.")
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
            }
        }

        It 'makes no request, probe or sleep under -WhatIf' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 99 -NotFoundLooks 99 }
                Mock Add-OERGroupEligibility { }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @(
                        [PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 },
                        [PSCustomObject]@{ principal = 'person16@example.com' }
                    )
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue)
                $script:Posts | Should -Be 0
                $script:Looks | Should -Be 0
                Should -Invoke Start-Sleep -Times 0
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 0
                # The group is never created under -WhatIf, so every row is the unchanged preview.
                $r.Count | Should -Be 3
                @($r | Where-Object { $_.Action -ne 'Skipped' }).Count | Should -Be 0
            }
        }

        It 'writes wait lines that end in "; retry N in S s.", N and S being numbers' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:Transport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostNotFound 2 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Out = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -Verbose 4>&1)
                # The live checklist counts the wait lines by their '; retry <n> in <s> s.' ending.
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$'
                    } | ForEach-Object { $_.Message }) | Should -Be @(
                    "Sync-OERStructureGroup: eligibility for 'person9@example.com' (member) on new group 'role_sec_x' answers 404 (not known to PIM for Groups yet); retry 1 in 2 s."
                    "Sync-OERStructureGroup: eligibility for 'person9@example.com' (member) on new group 'role_sec_x' answers 404 (not known to PIM for Groups yet); retry 2 in 4 s.")
            }
        }
    }

    Context 'a request Graph accepts but answers status Failed (Sprint 8 step 3, BL-04)' {
        # Microsoft Graph can accept a PIM-for-groups eligibility request (201) and answer it with
        # status Failed, which grants nothing. These tests drive the REAL Add-OERGroupEligibility --
        # no mock of it -- against a transport mock, so what the cmdlet itself writes, and where its
        # records land in the caller's -ErrorVariable, is what is asserted. The cmdlet resolves its
        # own inputs: the principals are GUID-shaped, and Resolve-OERGroupId answers the group id
        # for the group id itself (the cmdlet asks with the id) while the display name of a group a
        # test wants created resolves to nothing. The permanent pre-check reads the policy listing
        # and the rules through the transport; the rules carry no Expiration_Admin_Eligibility rule,
        # so permanent eligibility is allowed and the cmdlet never opens the policy. $script:Calls
        # records every listing, rules read and POST in order.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
                $script:Posts = 0
                $script:Calls = [System.Collections.Generic.List[string]]::new()
                $script:PrincipalIds = @{
                    'person9@example.com'  = '99999999-0000-0000-0000-000000000009'
                    'person16@example.com' = '16161616-0000-0000-0000-000000000016'
                }
                $script:AcceptedFailedTransport = {
                    param([string]$Method, [string]$Uri, $Body, [string[]]$ExpectedErrorCode,
                        [int]$PostFailed, [switch]$PostForbidden, [string]$FailedStatus = 'Failed')
                    if ($Uri -like '*eligibilityScheduleRequests*') {
                        $script:Posts++
                        $script:Calls.Add('post')
                        if ($PostForbidden) {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                        }
                        # Accepted (201), and the body already says Failed (measured live 2026-10-03).
                        if ($script:Posts -le $PostFailed) { return @{ id = "req-$($script:Posts)"; status = $FailedStatus } }
                        return @{ id = "req-$($script:Posts)"; status = 'Provisioned' }
                    }
                    if ($Uri -like '*roleManagementPolicyAssignments*') {
                        $script:Calls.Add('list')
                        return @{ value = @(
                                [PSCustomObject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }
                                [PSCustomObject]@{ roleDefinitionId = 'owner'; policyId = 'pol-owner' }
                            ) }
                    }
                    if ($Uri -like '*roleManagementPolicies/pol-*/rules') {
                        $script:Calls.Add('read')
                        return @{ value = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H' }) }
                    }
                    throw "unexpected request: $Uri"
                }
            }
        }

        It 'waits through a new group''s permanent request that the real cmdlet returns answered <FailedStatus>, as through Failed, then applies it with no error record left (BL-33, Ruling R3)' -ForEach @(
            @{ FailedStatus = 'FAILED' }
            @{ FailedStatus = 'FailedAsResourceIsLocked' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ FailedStatus = $FailedStatus } {
                param($FailedStatus)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # The wait asks Test-OERScheduleRequestFailed, as the cmdlet does, so every value of the
                # Failed family, in any letter case, is "not applied yet" -- not only the exact value Failed.
                $script:FailedAnswer = $FailedStatus
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'g-1') { 'g-1' } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 -FailedStatus $script:FailedAnswer }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The first POST is answered in the Failed family; one wait; then all of it again, and
                # the second POST is Provisioned.
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read', 'post', 'list', 'read', 'list', 'read', 'post')
                @($script:Slept) | Should -Be @(2)
                @($r | ForEach-Object { $_.Action }) | Should -Be @('Created', 'Updated')
                @($Err).Count | Should -Be 0
            }
        }

        It 'reports a refused (403) time-bound request of a group that already existed as itself, the cmdlet''s own record staying in the caller''s -ErrorVariable (measured)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; Members = @(); PimEligibility = @() } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostForbidden }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The real cmdlet reached the transport once, and the refusal ended the entry there.
                $script:Posts | Should -Be 1
                Should -Invoke Start-Sleep -Times 0
                @($r | ForEach-Object { $_.Action }) | Should -Be @('Unchanged', 'Failed')
                $r[1].Detail | Should -BeExactly "failed to add eligibility for 'person9@example.com': Authorization_RequestDenied: Insufficient privileges to complete the operation."
                $r[1].Error.FullyQualifiedErrorId | Should -BeExactly 'Authorization_RequestDenied,Invoke-SyncGroupViaCaller'
                # Measured at 3780a58: what the cmdlet wrote under -ErrorAction Stop is in the caller's
                # -ErrorVariable although the handler caught the throw -- the ActionPreferenceStopException
                # and the cmdlet's own record -- and the handler's re-publication comes last. So a record
                # the cmdlet writes for a Failed status could not stay out of a new group's run that ends
                # Updated unless the handler tells the cmdlet the status is its own (Ruling R1). The
                # records before these three (15 when measured) are, INFERRED and not measured, the
                # transport mock's throw crossing Pester's mock dispatch; the count was measured, its
                # cause was not, and it may follow the Pester version, so it is not pinned.
                $Records = @($Err)
                $Records[-1].FullyQualifiedErrorId | Should -BeExactly 'Authorization_RequestDenied,Invoke-SyncGroupViaCaller'
                $Records[-2].FullyQualifiedErrorId | Should -BeExactly 'Authorization_RequestDenied,Add-OERGroupEligibility'
                $Records[-3] | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
                @($Records | Where-Object { $_ -is [System.Management.Automation.ActionPreferenceStopException] }).Count | Should -Be 1
                @($Records | Where-Object {
                        $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                        $_.InvocationInfo.MyCommand.Name -eq 'Add-OERGroupEligibility'
                    }).Count | Should -Be 1
                @($Records | Where-Object {
                        $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                        $_.InvocationInfo.MyCommand.Name -eq 'Invoke-SyncGroupViaCaller'
                    }).Count | Should -Be 1
            }
        }

        It 'waits through a new group''s permanent request that the real cmdlet returns with status Failed, then applies it with no error record left' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'g-1') { 'g-1' } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The handler's readiness poll (list, read), then the cmdlet's own pre-check (list, read)
                # and its POST, answered Failed; one wait; then all of it again, and the second POST is
                # Provisioned.
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read', 'post', 'list', 'read', 'list', 'read', 'post')
                @($script:Slept) | Should -Be @(2)
                @($r | ForEach-Object { $_.Action }) | Should -Be @('Created', 'Updated')
                $r[1].Detail | Should -BeExactly "set permanent member eligibility for 'person16@example.com': permanent member eligibility is absent"
                # The Failed answer of a group created in this run is replication the handler owns: the
                # cmdlet wrote no record for it (measured green at 3780a58, and kept green since).
                @($Err).Count | Should -Be 0
            }
        }

        It 'reports Failed with GroupNotOnboarded, and no record of the cmdlet''s own, when a new group''s permanent request answers status Failed for the whole budget' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'g-1') { 'g-1' } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 99 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Five POSTs, four waits: the whole budget, and not one second more -- exactly as with the
                # cmdlet mocked.
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                $script:Posts | Should -Be 5
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                # BL-51 case 6: this fixture's rules lack Expiration_Admin_Eligibility, so the read after the requests finds no boolean.
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it. Its PIM-for-groups policy for ''member'' access ' +
                    'may have been opened to allow permanent eligibility before the request was sent, and it could not ' +
                    'be read afterwards. If it allows permanent eligibility, close it with ''Set-OERGroupPimPolicy ' +
                    '-Group ''''g-1'''' -AccessType member -AllowPermanentEligibility:$false'' if you do not intend to retry.')
                $Failed[0].Error.FullyQualifiedErrorId | Should -Match '^GroupNotOnboarded'
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                # Exactly the Failed row's own record: none of the five Failed answers left one.
                @($Err).Count | Should -Be 1
                $Err[0].FullyQualifiedErrorId | Should -Match '^GroupNotOnboarded'
                $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $Err[0].TargetObject | Should -BeExactly 'role_sec_x'
            }
        }

        It 'still asks whether a group that already existed uses PIM for Groups when its time-bound request was answered status Failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = 'g-1'; Description = $null; MailNickname = $null; GroupType = 'Assigned'
                        IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
                }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 99 }
                Mock Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
                Mock Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
                Mock Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x'; Manageable = $true } }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 5 })
                    pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
                # The request was sent and answered Failed, so step 3 wrote nothing and onboarded
                # nothing: step 4 must still ask before it writes the changed policy.
                $script:Posts | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Failed' -and [string]$_.Error.FullyQualifiedErrorId -match '^EligibilityRequestFailed' }).Count | Should -Be 1
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'eligibility' }).Count | Should -Be 0
                Should -Invoke Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-1' }
                Should -Invoke Set-OERGroupPimPolicy -Times 1 -Exactly
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match '^pimPolicy \(member\) set' }).Count | Should -Be 1
            }
        }

        It 'reports a Failed answer as EligibilityRequestFailed again once a new group''s permanent eligibility is applied' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'g-1') { 'g-1' } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 1 }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # The new group's call ran twice, its Failed answer owned by the handler, and applied.
                $script:Posts | Should -Be 2
                @($r | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match 'set permanent member eligibility' }).Count | Should -Be 1
                # Afterwards the cmdlet is on its own again: a Failed answer is its error.
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 99 }
                $Direct = $null
                $Out = @(Add-OERGroupEligibility -Group 'g-1' -PrincipalId '16161616-0000-0000-0000-000000000016' -DurationDays 5 `
                        -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Direct)
                $script:Posts | Should -Be 3
                $Out.Count | Should -Be 1
                $Out[0].Status | Should -BeExactly 'Failed'
                @($Direct | Where-Object { $_.FullyQualifiedErrorId -eq 'EligibilityRequestFailed,Add-OERGroupEligibility' }).Count | Should -Be 1
            }
        }

        It 'reports a Failed answer as EligibilityRequestFailed again after a new group''s permanent request was refused' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'g-1') { 'g-1' } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostForbidden }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:PrincipalIds[$Reference] }
                Mock Resolve-OERStructureDefault { $null }
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' })
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)
                # The new group's call threw (a refusal ends the entry), which leaves the handler
                # through its catch: the reset must run on that path too.
                $script:Posts | Should -Be 1
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike "failed to add permanent eligibility for 'person16@example.com': Authorization_RequestDenied*"
                Mock Invoke-OERGraphRequest { & $script:AcceptedFailedTransport -Method $Method -Uri $Uri -Body $Body -ExpectedErrorCode $ExpectedErrorCode -PostFailed 99 }
                $Direct = $null
                $Out = @(Add-OERGroupEligibility -Group 'g-1' -PrincipalId '16161616-0000-0000-0000-000000000016' -DurationDays 5 `
                        -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Direct)
                $script:Posts | Should -Be 2
                $Out.Count | Should -Be 1
                @($Direct | Where-Object { $_.FullyQualifiedErrorId -eq 'EligibilityRequestFailed,Add-OERGroupEligibility' }).Count | Should -Be 1
            }
        }
    }

    Context 'GroupNotOnboarded for a group created in this run says whether its policy was opened (Sprint 10 step 2, BL-51)' {
        # When the permanent wait for a group THIS run created ends GroupNotOnboarded, the message ends
        # with one sentence group saying whether the group's PIM-for-groups policy was opened for the
        # entry. The handler decides it itself: when Add-OERGroupEligibility was never called, nothing
        # was sent and nothing opened; otherwise it reads the policy once more after the attempts, with
        # the poll's own functions (Get-OERPimGroupPolicyId -NotFoundAsUnlisted, then
        # Get-OERListedGroupPimPolicy -- both REAL here), and compares that with what the poll read just
        # before the FIRST call. A read after the attempts that fails, is unlisted, answers 404 or reads
        # no boolean is unknown, and never "not opened". Add-OERGroupEligibility is mocked and answers status
        # Failed every time, so an entry that reaches it spends the whole budget. The transport mock
        # answers the listings and the rules reads from the per-test plans $script:ListPlan and
        # $script:ReadPlan, one entry per call, the last entry repeating: 'ok', 'notfound' or 'refused'
        # for a listing; 'open' (permanent eligibility allowed), 'closed', 'none' (no
        # Expiration_Admin_Eligibility rule, so no boolean), 'notfound' or 'refused' for a read.
        # $script:Calls records every listing, read and call in order.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:Get-BL51Base ([string]$AccessType) {
                    "permanent eligibility for 'person16@example.com' ($AccessType) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for '$AccessType' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it.'
                }
                function script:Get-BL51Advice ([string]$AccessType) {
                    "close it with 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType $AccessType " +
                    '-AllowPermanentEligibility:$false'' if you do not intend to retry.'
                }
                function script:Invoke-SyncGroupBL51ViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                # The one Failed row, and the record it carries: GroupNotOnboarded, ObjectNotFound, the
                # item's name, and the message under test as both the Detail and the record's message.
                function script:Assert-BL51GroupNotOnboarded ($Rows, [string]$Expected) {
                    @($Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                    $Failed = @($Rows | Where-Object { $_.Action -eq 'Failed' })
                    $Failed.Count | Should -Be 1
                    $Failed[0].Detail | Should -BeExactly $Expected
                    $Record = $Failed[0].Error
                    $Record.Exception.Message | Should -BeExactly $Expected
                    ([string]$Record.FullyQualifiedErrorId).Split(',')[0] | Should -BeExactly 'GroupNotOnboarded'
                    $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                    $Record.TargetObject | Should -BeExactly 'role_sec_x'
                }
                # What the caller's -ErrorVariable holds, as ids: read from a record, or from the record
                # an exception carries; anything else by its type name, so nothing goes unseen.
                function script:Get-BL51ErrorId ($Records) {
                    foreach ($Entry in @($Records)) {
                        if ($Entry -is [System.Management.Automation.ErrorRecord]) { [string]$Entry.FullyQualifiedErrorId }
                        elseif ($Entry -is [System.Management.Automation.IContainsErrorRecord]) { [string]$Entry.ErrorRecord.FullyQualifiedErrorId }
                        else { $Entry.GetType().FullName }
                    }
                }
            }
        }

        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
                $script:Calls = [System.Collections.Generic.List[string]]::new()
                $script:Looks = 0
                $script:Reads = 0
                $script:ListPlan = @('ok')
                $script:ReadPlan = @('open')
                $script:BL51Transport = {
                    param([string]$Uri, [string[]]$ExpectedErrorCode)
                    # A 404 comes back as the declared-error marker, as Invoke-OERGraphRequest returns it;
                    # an undeclared one would be a defect, so it fails the test loudly.
                    $NotFound = {
                        if (@($ExpectedErrorCode) -notcontains 'ResourceNotFound') { throw "undeclared 404: $Uri" }
                        $Marker = [PSCustomObject]@{
                            ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404
                            Message = 'ResourceNotFound: The resource is not found.'; Uri = $Uri
                        }
                        $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                        $Marker
                    }
                    $Refused = {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to read the policy after the requests.'),
                            'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                    }
                    if ($Uri -like '*roleManagementPolicyAssignments*') {
                        $script:Looks++
                        $script:Calls.Add('list')
                        $Answer = $script:ListPlan[[System.Math]::Min($script:Looks, $script:ListPlan.Count) - 1]
                        if ($Answer -eq 'notfound') { return (& $NotFound) }
                        if ($Answer -eq 'refused') { & $Refused }
                        return @{ value = @(
                                [PSCustomObject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }
                                [PSCustomObject]@{ roleDefinitionId = 'owner'; policyId = 'pol-owner' }
                            ) }
                    }
                    if ($Uri -like '*roleManagementPolicies/pol-*/rules') {
                        $script:Reads++
                        $script:Calls.Add('read')
                        $Answer = $script:ReadPlan[[System.Math]::Min($script:Reads, $script:ReadPlan.Count) - 1]
                        if ($Answer -eq 'notfound') { return (& $NotFound) }
                        if ($Answer -eq 'refused') { & $Refused }
                        # 'none': a rule set without Expiration_Admin_Eligibility, which reads as no
                        # boolean permanent-eligibility setting at all.
                        if ($Answer -eq 'none') { return @{ value = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) } }
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = ($Answer -eq 'closed'); maximumDuration = 'P180D' }
                            ) }
                    }
                    throw "unexpected request: $Uri"
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:BL51Transport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode }
                Mock Add-OERGroupEligibility {
                    $script:Calls.Add('add')
                    [PSCustomObject]@{ Status = 'Failed' }
                }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock Resolve-OERStructureDefault { $null }
            }
        }

        It 'case 1: says no request was sent, so no policy was opened, and reads nothing after the wait, when Add-OERGroupEligibility was never called' {
            InModuleScope $script:moduleName {
                # Listed every time, but the read of the listed policy answers 404 for the whole budget.
                $script:ReadPlan = @('notfound')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The poll's own ten calls and nothing after them.
                @($script:Calls) | Should -Be @('list', 'read', 'list', 'read', 'list', 'read', 'list', 'read', 'list', 'read')
                Should -Invoke Add-OERGroupEligibility -Times 0
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    ' No eligibility request was sent, so no PIM-for-groups policy was opened for it.')
                @($Err).Count | Should -Be 1
            }
        }

        It 'case 2: says the policy was not left open when the read after the requests finds it does not allow permanent eligibility and the poll read it <Before> before the first call' -ForEach @(
            # Open before every call, closed after them: the before-state is $true.
            @{ Before = 'open'; ReadPlan = @('open', 'open', 'open', 'open', 'open', 'closed') }
            # No Expiration_Admin_Eligibility rule before the first call, closed on every read after
            # it: the before-state is unknown, never $false.
            @{ Before = 'with no boolean setting'; ReadPlan = @('none', 'closed') }
        ) {
            InModuleScope $script:moduleName -Parameters @{ ReadPlan = $ReadPlan } {
                param($ReadPlan)
                $script:ReadPlan = $ReadPlan
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Five polls and calls, then ONE listing and ONE read after them, with no wait of their own.
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-member/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " Its PIM-for-groups policy for 'member' access does not allow permanent eligibility as read after the requests, so it was not left open.")
                @($Err).Count | Should -Be 1
            }
        }

        It 'case 2b: never says the <AccessType> policy was not left open when the poll read it closed before the FIRST call and the read after the requests reads it closed too' -ForEach @(
            @{ AccessType = 'member' }
            @{ AccessType = 'owner' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ AccessType = $AccessType } {
                param($AccessType)
                # Closed on every read, the one after the requests included. The first call would have
                # opened a policy the poll read closed just before it, so a closed read seconds later
                # may come from a replica that has not seen the open: it is never "not left open".
                $script:ReadPlan = @('closed')
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com'; accessType = $AccessType })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-*/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType $AccessType) +
                    " Its PIM-for-groups policy for '$AccessType' access reads as not allowing permanent eligibility after the requests, " +
                    'but the first request would have opened it, so that read may be out of date. If it allows permanent eligibility, ' +
                    (Get-BL51Advice -AccessType $AccessType))
                @(Get-BL51ErrorId -Records $Err) | Should -Be @('GroupNotOnboarded,Invoke-SyncGroupBL51ViaCaller')
            }
        }

        It 'case 3: says the policy already allowed permanent eligibility before the first request when the poll read it so' {
            InModuleScope $script:moduleName {
                $script:ReadPlan = @('open')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-member/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " Its PIM-for-groups policy for 'member' access already allowed permanent eligibility before the first request, so it was not opened for it.")
                @($Err).Count | Should -Be 1
            }
        }

        It 'case 4: names the <AccessType> policy as opened and still open, with the command that closes it, when the poll read it closed before the FIRST call' -ForEach @(
            @{ AccessType = 'member' }
            @{ AccessType = 'owner' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ AccessType = $AccessType } {
                param($AccessType)
                # Closed when the poll read it before the first call, open on every read after that (the
                # first call opened it): the before-state is the FIRST call's, never a later poll's.
                $script:ReadPlan = @('closed', 'open')
                $Item = [PSCustomObject]@{
                    displayName = 'role_sec_x'
                    eligibility = @([PSCustomObject]@{ principal = 'person16@example.com'; accessType = $AccessType })
                }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-*/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType $AccessType) +
                    " PIM-for-groups policy 'pol-$AccessType' had been opened to allow permanent eligibility before the request was sent. " +
                    'The policy is still open; ' + (Get-BL51Advice -AccessType $AccessType))
                @($Err).Count | Should -Be 1
            }
        }

        It 'case 5: names the policy as open and maybe opened, with the command that closes it, when the poll was refused before the first call' {
            InModuleScope $script:moduleName {
                # The first listing is refused, so the cmdlet is called directly and the before-state is
                # unknown; every later listing answers, and every read finds the policy open.
                $script:ListPlan = @('refused', 'ok')
                $script:ReadPlan = @('open')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 5 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-member/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " PIM-for-groups policy 'pol-member' allows permanent eligibility after the requests and may have been opened for them, " +
                    'since whether it allowed it before the first request is not known. The policy is open; ' + (Get-BL51Advice -AccessType 'member'))
                @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId).Split(',')[0] -eq 'GroupNotOnboarded' }).Count | Should -Be 1
            }
        }

        It 'case 5: takes a poll read with no boolean permanent-eligibility setting before the first call for unknown, never for "did not allow"' {
            InModuleScope $script:moduleName {
                # The poll reads the policy before the first call, but its rule set carries no
                # Expiration_Admin_Eligibility rule, so there is no boolean: the before-state is unknown,
                # not false. Every later read, the one after the requests included, finds it open.
                $script:ReadPlan = @('none', 'open')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 6 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-member/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " PIM-for-groups policy 'pol-member' allows permanent eligibility after the requests and may have been opened for them, " +
                    'since whether it allowed it before the first request is not known. The policy is open; ' + (Get-BL51Advice -AccessType 'member'))
                @(Get-BL51ErrorId -Records $Err) | Should -Be @('GroupNotOnboarded,Invoke-SyncGroupBL51ViaCaller')
            }
        }

        It 'case 6: never says "not opened" when the <Refused> after the requests is refused, and scrubs the refusal first' -ForEach @(
            @{ Refused = 'listing'; ListPlan = @('ok', 'ok', 'ok', 'ok', 'ok', 'refused'); ReadPlan = @('open'); After = @('list') }
            @{ Refused = 'read'; ListPlan = @('ok'); ReadPlan = @('open', 'open', 'open', 'open', 'open', 'refused'); After = @('list', 'read') }
        ) {
            InModuleScope $script:moduleName -Parameters @{ ListPlan = $ListPlan; ReadPlan = $ReadPlan; After = $After } {
                param($ListPlan, $ReadPlan, $After)
                # The poll read the policy open before the first call; the read after the requests is
                # refused. A failed read is UNKNOWN, never "not opened".
                $script:ListPlan = $ListPlan
                $script:ReadPlan = $ReadPlan
                # The scrub proof: the record the read-after's catch scrubs is the refusal itself.
                Mock Remove-OERErrorRecord { param($Record) }
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $Out = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                @($script:Calls) | Should -Be (@('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                        'list', 'read', 'add') + $After)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    $Record.Exception.Message -eq 'Authorization_RequestDenied: Insufficient privileges to read the policy after the requests.'
                }
                @($Out | Where-Object {
                        $_ -is [System.Management.Automation.VerboseRecord] -and
                        $_.Message -like "Sync-OERStructureGroup: could not read the member policy of new group 'role_sec_x' after its permanent eligibility requests (Authorization_RequestDenied: *"
                    }).Count | Should -Be 1
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " Its PIM-for-groups policy for 'member' access may have been opened to allow permanent eligibility before the request was sent, " +
                    'and it could not be read afterwards. If it allows permanent eligibility, ' + (Get-BL51Advice -AccessType 'member'))
                # What the caller's -ErrorVariable holds. The handler publishes only the Failed row's own
                # record, last. Before it, the refusal it caught and scrubbed is there too: -ErrorVariable
                # keeps the copies a throw leaves as it unwinds through the transport and the two read
                # functions, even when it is caught (measured: 18 copies for a refused listing, 19 for a
                # refused read, ErrorRecords and RuntimeExceptions). That count follows the call layers,
                # so it is not pinned; that every copy is the refusal itself, and nothing else, is.
                $ErrIds = @(Get-BL51ErrorId -Records $Err)
                $ErrIds[-1] | Should -BeExactly 'GroupNotOnboarded,Invoke-SyncGroupBL51ViaCaller'
                @($ErrIds | Where-Object { $_ -eq 'GroupNotOnboarded,Invoke-SyncGroupBL51ViaCaller' }).Count | Should -Be 1
                $Copies = @($Err | Select-Object -SkipLast 1)
                $Copies.Count | Should -BeGreaterThan 0
                @($ErrIds | Select-Object -SkipLast 1 | Sort-Object -Unique) | Should -Be @('Authorization_RequestDenied')
                @($Copies | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) { [string]$_.Exception.Message } else { [string]$_.Message }
                    } | Sort-Object -Unique) | Should -Be @('Authorization_RequestDenied: Insufficient privileges to read the policy after the requests.')
            }
        }

        It 'case 6: never says "not opened" when the policy is <Answer> after the requests, and the declared 404 leaves no record' -ForEach @(
            @{ Answer = 'unlisted'; ListPlan = @('ok', 'ok', 'ok', 'ok', 'ok', 'notfound'); ReadPlan = @('open'); After = @('list') }
            @{ Answer = 'listed but its read answers 404'; ListPlan = @('ok'); ReadPlan = @('open', 'open', 'open', 'open', 'open', 'notfound'); After = @('list', 'read') }
        ) {
            InModuleScope $script:moduleName -Parameters @{ ListPlan = $ListPlan; ReadPlan = $ReadPlan; After = $After } {
                param($ListPlan, $ReadPlan, $After)
                $script:ListPlan = $ListPlan
                $script:ReadPlan = $ReadPlan
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be (@('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                        'list', 'read', 'add') + $After)
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " Its PIM-for-groups policy for 'member' access may have been opened to allow permanent eligibility before the request was sent, " +
                    'and it could not be read afterwards. If it allows permanent eligibility, ' + (Get-BL51Advice -AccessType 'member'))
                # Exactly the Failed row's own record: the 404 after the requests was declared.
                @($Err).Count | Should -Be 1
            }
        }

        It 'case 6: never says "not opened" when the read after the requests carries no boolean permanent-eligibility setting' {
            InModuleScope $script:moduleName {
                # The poll read the policy open before every call; the read after the requests answers,
                # but its rule set carries no Expiration_Admin_Eligibility rule, so there is no boolean.
                # No boolean is unknown, never "does not allow".
                $script:ReadPlan = @('open', 'open', 'open', 'open', 'open', 'none')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupBL51ViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add', 'list', 'read', 'add',
                    'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2, 4, 8, 16)
                Should -Invoke Add-OERGroupEligibility -Times 5 -Exactly
                Assert-BL51GroupNotOnboarded -Rows $r -Expected ((Get-BL51Base -AccessType 'member') +
                    " Its PIM-for-groups policy for 'member' access may have been opened to allow permanent eligibility before the request was sent, " +
                    'and it could not be read afterwards. If it allows permanent eligibility, ' + (Get-BL51Advice -AccessType 'member'))
                @(Get-BL51ErrorId -Records $Err) | Should -Be @('GroupNotOnboarded,Invoke-SyncGroupBL51ViaCaller')
            }
        }
    }

    Context 'a later attempt in a new group''s permanent wait that fails says whether its policy was opened (Sprint 10 step 2 round 1, finding 1)' {
        # In the permanent wait for a group THIS run created, a call of Add-OERGroupEligibility can throw
        # after an EARLIER call of the same entry was sent and answered status Failed. That earlier
        # request may have opened the group's policy, while the later call opened nothing, so its error
        # carries no advice. The handler then makes the read after the attempts that GroupNotOnboarded
        # makes, and appends its statement to the caught message in a NEW record with the caught
        # record's own error id, category and target. The approach is the BL-51 Context's: the transport
        # mock answers the listings and the rules reads from $script:ListPlan and $script:ReadPlan, one
        # entry per call, the last entry repeating ('ok', 'notfound' or 'refused' for a listing; 'open',
        # 'closed', 'none', 'notfound' or 'refused' for a read), and Get-OERPimGroupPolicyId and
        # Get-OERListedGroupPimPolicy run for REAL over it. Add-OERGroupEligibility answers from the
        # per-test plan $script:AddPlan, one entry per call, the last repeating: 'failed' returns a
        # request with status Failed, and a scriptblock is run (it throws). $script:Calls records every
        # listing, read and call in order. Every expected sentence is typed out here.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:Invoke-SyncGroupLaterAttemptViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
                function script:Get-LaterAttemptAdvice ([string]$AccessType) {
                    "close it with 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType $AccessType " +
                    '-AllowPermanentEligibility:$false'' if you do not intend to retry.'
                }
                # Writes its record through $PSCmdlet.WriteError, as this module's cmdlets do: called with
                # -ErrorAction Stop, the record that stops it reads '<id>,Write-LaterAttemptRefusal'.
                function script:Write-LaterAttemptRefusal {
                    [CmdletBinding()]
                    param([string]$ErrorId, [System.Exception]$Exception)
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            $Exception, $ErrorId, [System.Management.Automation.ErrorCategory]::PermissionDenied, 'g-1'))
                }
                # What the caller's -ErrorVariable holds, as '<id>|<message>': read from a record, or from
                # the record an exception carries; anything else by its type name, so nothing goes unseen.
                function script:Get-LaterAttemptError ($Records) {
                    foreach ($Entry in @($Records)) {
                        $Held = if ($Entry -is [System.Management.Automation.ErrorRecord]) { $Entry }
                        elseif ($Entry -is [System.Management.Automation.IContainsErrorRecord]) { $Entry.ErrorRecord }
                        if ($Held) { '{0}|{1}' -f $Held.FullyQualifiedErrorId, $Held.Exception.Message } else { $Entry.GetType().FullName }
                    }
                }
                # The handler publishes exactly ONE record to the caller, and last: its id, read by the
                # caller's suffix, and its message. Before it, -ErrorVariable keeps the copies a throw
                # leaves as it unwinds through the mock layers even when it is caught (measured: 14 of the
                # caught refusal in (a)); that count follows the call layers, so it is not pinned, but
                # every copy must be one of $Copies -- never a record the handler published.
                function script:Assert-LaterAttemptPublished ($Records, [string]$Id, [string]$Message, [string[]]$Copies) {
                    $Held = @(Get-LaterAttemptError -Records $Records)
                    $Held.Count | Should -BeGreaterThan 0
                    $Held[-1] | Should -BeExactly ('{0},Invoke-SyncGroupLaterAttemptViaCaller|{1}' -f $Id, $Message)
                    @($Held | Where-Object { $_ -like '*,Invoke-SyncGroupLaterAttemptViaCaller|*' }).Count | Should -Be 1
                    (@($Held | Select-Object -SkipLast 1 | Where-Object { $Copies -notcontains $_ }) -join ' || ') | Should -BeExactly ''
                }
            }
            $script:LaterAttemptPrefix = "failed to add permanent eligibility for 'person16@example.com': "
            $script:LaterAttemptCaught = 'Request_BadRequest: Graph rejected the eligibility request.'
            # Test (f): the public Invoke-OERStructure, in a runspace with no try above it. The fakes:
            # auth, the group lookup (none), New-OERGroup, Start-Sleep, the principal, the transport
            # (the member policy is listed every time, and its rules read closed on the FIRST read and
            # open on every read after it) and Add-OERGroupEligibility (status Failed on the first call,
            # a refused grant thrown on the second). Each listing, read and call appends a line to the log
            # with AppendAllText, which never prompts. The document carries no tenantId, so the engine's
            # tenant comparison has nothing to refuse, and the sign-in snapshot finds no session before or
            # after the faked sign-in.
            $script:LaterAttemptNoTry = {
                param([string]$Log, [string]$Stop)
                [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    $script:NoTryReads = 0
    $script:NoTryAdds = 0
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value { $null }
    Set-Item -Path function:script:New-OERGroup -Value { [pscustomobject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
    Set-Item -Path function:script:Start-Sleep -Value { }
    Set-Item -Path function:script:Resolve-OERStructurePrincipal -Value { 'id-person16' }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body, [string[]]$ExpectedErrorCode, [switch]$All)
        if ($Uri -like '*roleManagementPolicyAssignments*') {
            [System.IO.File]::AppendAllText('#LOG#', "list`n")
            return @{ value = @([pscustomobject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }) }
        }
        if ($Uri -like '*roleManagementPolicies/pol-member/rules') {
            $script:NoTryReads++
            [System.IO.File]::AppendAllText('#LOG#', "read`n")
            return @{ value = @(
                    @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                    @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = ($script:NoTryReads -eq 1); maximumDuration = 'P180D' }
                ) }
        }
        throw "unexpected $Method $Uri"
    }
    Set-Item -Path function:script:Add-OERGroupEligibility -Value {
        $script:NoTryAdds++
        [System.IO.File]::AppendAllText('#LOG#', "add`n")
        if ($script:NoTryAdds -eq 1) { return [pscustomobject]@{ Status = 'Failed' } }
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'), 'Request_BadRequest',
            [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
    }
}
$Json = '{ "version": "1.0", "groups": [ { "displayName": "role_sec_x", "members": null, "eligibility": [ { "principal": "person16@example.com" } ] } ] }'
Invoke-OERStructure -Json $Json -Confirm:$false #STOP# | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#STOP#', $Stop))
            }
            $script:LaterAttemptNoTryText = 'Request_BadRequest: Graph rejected the eligibility request. ' +
                "PIM-for-groups policy 'pol-member' had been opened to allow permanent eligibility before the request was sent. " +
                "The policy is still open; close it with 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member " +
                "-AllowPermanentEligibility:`$false' if you do not intend to retry."
            function Get-TestLoggedLine ([string]$Log) {
                if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
            }
        }

        BeforeEach {
            InModuleScope $script:moduleName {
                $script:Slept = [System.Collections.Generic.List[int]]::new()
                $script:Calls = [System.Collections.Generic.List[string]]::new()
                $script:Looks = 0
                $script:Reads = 0
                $script:Adds = 0
                $script:ListPlan = @('ok')
                $script:ReadPlan = @('open')
                # The second call throws the refusal of (a): Request_BadRequest, InvalidOperation, 'g-1'.
                $script:ThrownException = [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.')
                $script:AddPlan = @('failed', {
                        throw [System.Management.Automation.ErrorRecord]::new($script:ThrownException, 'Request_BadRequest',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
                    })
                $script:LaterAttemptTransport = {
                    param([string]$Uri, [string[]]$ExpectedErrorCode)
                    # A 404 comes back as the declared-error marker, as Invoke-OERGraphRequest returns it;
                    # an undeclared one would be a defect, so it fails the test loudly.
                    $NotFound = {
                        if (@($ExpectedErrorCode) -notcontains 'ResourceNotFound') { throw "undeclared 404: $Uri" }
                        $Marker = [PSCustomObject]@{
                            ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404
                            Message = 'ResourceNotFound: The resource is not found.'; Uri = $Uri
                        }
                        $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                        $Marker
                    }
                    $Refused = {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to read the policy after the requests.'),
                            'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                    }
                    if ($Uri -like '*roleManagementPolicyAssignments*') {
                        $script:Looks++
                        $script:Calls.Add('list')
                        $Answer = $script:ListPlan[[System.Math]::Min($script:Looks, $script:ListPlan.Count) - 1]
                        if ($Answer -eq 'notfound') { return (& $NotFound) }
                        if ($Answer -eq 'refused') { & $Refused }
                        return @{ value = @(
                                [PSCustomObject]@{ roleDefinitionId = 'member'; policyId = 'pol-member' }
                                [PSCustomObject]@{ roleDefinitionId = 'owner'; policyId = 'pol-owner' }
                            ) }
                    }
                    if ($Uri -like '*roleManagementPolicies/pol-*/rules') {
                        $script:Reads++
                        $script:Calls.Add('read')
                        $Answer = $script:ReadPlan[[System.Math]::Min($script:Reads, $script:ReadPlan.Count) - 1]
                        if ($Answer -eq 'notfound') { return (& $NotFound) }
                        if ($Answer -eq 'refused') { & $Refused }
                        # 'none': a rule set without Expiration_Admin_Eligibility, which reads as no
                        # boolean permanent-eligibility setting at all.
                        if ($Answer -eq 'none') { return @{ value = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) } }
                        return @{ value = @(
                                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                                @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = ($Answer -eq 'closed'); maximumDuration = 'P180D' }
                            ) }
                    }
                    throw "unexpected request: $Uri"
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
                Mock Start-Sleep { $script:Slept.Add($Seconds) }
                Mock Invoke-OERGraphRequest { & $script:LaterAttemptTransport -Uri $Uri -ExpectedErrorCode $ExpectedErrorCode }
                Mock Add-OERGroupEligibility {
                    $script:Adds++
                    $script:Calls.Add('add')
                    $Step = $script:AddPlan[[System.Math]::Min($script:Adds, $script:AddPlan.Count) - 1]
                    if ($Step -is [scriptblock]) { & $Step } else { [PSCustomObject]@{ Status = 'Failed' } }
                }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            }
        }

        It 'a: names the policy the first call opened as still open, with the command that closes it, when the second call throws' {
            InModuleScope $script:moduleName -Parameters @{ Prefix = $script:LaterAttemptPrefix; Caught = $script:LaterAttemptCaught } {
                param($Prefix, $Caught)
                # Closed when the poll read it before the first call, open on every read after that: the
                # first call, answered Failed, opened it; the second throws and opened nothing.
                $script:ReadPlan = @('closed', 'open')
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupLaterAttemptViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Two polls and calls, then ONE listing and ONE read after the last call, with no wait
                # of their own, through the poll's own functions (the 404 declared to the transport).
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read')
                @($script:Slept) | Should -Be @(2)
                Should -Invoke Add-OERGroupEligibility -Times 2 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicyAssignments*' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                    $Uri -like '*roleManagementPolicies/pol-member/rules' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                $Expected = $Caught + " PIM-for-groups policy 'pol-member' had been opened to allow permanent eligibility before the " +
                    'request was sent. The policy is still open; ' + (Get-LaterAttemptAdvice -AccessType 'member')
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ($Prefix + $Expected)
                $Record = $Failed[0].Error
                $Record.Exception.Message | Should -BeExactly $Expected
                $Record.Exception.InnerException | Should -BeNullOrEmpty
                [string]$Record.FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Invoke-SyncGroupLaterAttemptViaCaller'
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
                $Record.TargetObject | Should -BeExactly 'g-1'
                # A NEW record, and the only one the handler publishes: the caught one never beside it.
                [object]::ReferenceEquals($Record.Exception, $script:ThrownException) | Should -BeFalse
                Assert-LaterAttemptPublished -Records $Err -Id 'Request_BadRequest' -Message $Expected -Copies @("Request_BadRequest|$Caught")
            }
        }

        It 'b: when <Case>, the caught message ends with the "<Outcome>" statement' -ForEach @(
            # A read after the calls that is refused, unlisted, answers 404 or reads no boolean is
            # UNKNOWN, never "not opened". The poll read the policy closed before the first call.
            @{ Case = 'the listing after the calls is refused'; Outcome = 'unknown'; Refused = $true
                ListPlan = @('ok', 'ok', 'refused'); ReadPlan = @('closed', 'open')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list') }
            @{ Case = 'the read after the calls is refused'; Outcome = 'unknown'; Refused = $true
                ListPlan = @('ok'); ReadPlan = @('closed', 'open', 'refused')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            @{ Case = 'the policy is unlisted after the calls'; Outcome = 'unknown'; Refused = $false
                ListPlan = @('ok', 'ok', 'notfound'); ReadPlan = @('closed', 'open')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list') }
            @{ Case = 'the read after the calls answers 404'; Outcome = 'unknown'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('closed', 'open', 'notfound')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            @{ Case = 'the read after the calls carries no boolean'; Outcome = 'unknown'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('closed', 'open', 'none')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            # Closed after the calls, and the poll read it open before the first: not left open.
            @{ Case = 'the policy reads closed after the calls and open before the first'; Outcome = 'not left open'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('open', 'open', 'closed')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            # Closed after the calls, and closed before the first, which would have opened it.
            @{ Case = 'the policy reads closed after the calls and closed before the first'; Outcome = 'may be out of date'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('closed')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            # Open after the calls, and the state before the first is unknown: no boolean, or a refused poll.
            @{ Case = 'the policy reads open after the calls and with no boolean before the first'; Outcome = 'may have been opened for them'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('none', 'open')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
            @{ Case = 'the policy reads open after the calls and the poll before the first was refused'; Outcome = 'may have been opened for them'; Refused = $false
                ListPlan = @('refused', 'ok'); ReadPlan = @('open')
                Calls = @('list', 'add', 'list', 'read', 'add', 'list', 'read') }
            # Open after the calls, and already open before the first.
            @{ Case = 'the policy reads open after the calls and open before the first'; Outcome = 'already allowed'; Refused = $false
                ListPlan = @('ok'); ReadPlan = @('open')
                Calls = @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read') }
        ) {
            $Parameters = @{
                Prefix = $script:LaterAttemptPrefix; Caught = $script:LaterAttemptCaught; Outcome = $Outcome; Refused = $Refused
                ListPlan = $ListPlan; ReadPlan = $ReadPlan; Calls = $Calls
            }
            InModuleScope $script:moduleName -Parameters $Parameters {
                param($Prefix, $Caught, $Outcome, $Refused, $ListPlan, $ReadPlan, $Calls)
                $script:ListPlan = $ListPlan
                $script:ReadPlan = $ReadPlan
                # The scrub proof for a refused read after the calls: the record the read's catch
                # scrubs is the refusal itself.
                Mock Remove-OERErrorRecord { param($Record) }
                $Advice = Get-LaterAttemptAdvice -AccessType 'member'
                $Statement = switch ($Outcome) {
                    'unknown' {
                        "Its PIM-for-groups policy for 'member' access may have been opened to allow permanent eligibility before the request " +
                        "was sent, and it could not be read afterwards. If it allows permanent eligibility, $Advice"
                    }
                    'not left open' {
                        "Its PIM-for-groups policy for 'member' access does not allow permanent eligibility as read after the requests, so it was not left open."
                    }
                    'may be out of date' {
                        "Its PIM-for-groups policy for 'member' access reads as not allowing permanent eligibility after the requests, but the " +
                        "first request would have opened it, so that read may be out of date. If it allows permanent eligibility, $Advice"
                    }
                    'may have been opened for them' {
                        "PIM-for-groups policy 'pol-member' allows permanent eligibility after the requests and may have been opened for them, " +
                        "since whether it allowed it before the first request is not known. The policy is open; $Advice"
                    }
                    'already allowed' {
                        "Its PIM-for-groups policy for 'member' access already allowed permanent eligibility before the first request, so it was not opened for it."
                    }
                }
                $Expected = "$Caught $Statement"
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $Out = @(Invoke-SyncGroupLaterAttemptViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
                $r = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
                # Reached: two calls, the second throwing, and the read after them.
                @($script:Calls) | Should -Be $Calls
                Should -Invoke Add-OERGroupEligibility -Times 2 -Exactly
                @($r | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ($Prefix + $Expected)
                $Failed[0].Error.Exception.Message | Should -BeExactly $Expected
                [string]$Failed[0].Error.FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Invoke-SyncGroupLaterAttemptViaCaller'
                $Refusal = 'Authorization_RequestDenied: Insufficient privileges to read the policy after the requests.'
                $Copies = @("Request_BadRequest|$Caught", "Authorization_RequestDenied|$Refusal")
                Assert-LaterAttemptPublished -Records $Err -Id 'Request_BadRequest' -Message $Expected -Copies $Copies
                if ($Refused) {
                    # Scrubbed once, logged, and never published: no command published the refusal.
                    Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { $Record.Exception.Message -eq $Refusal }
                    @($Out | Where-Object {
                            $_ -is [System.Management.Automation.VerboseRecord] -and
                            $_.Message -like "Sync-OERStructureGroup: could not read the member policy of new group 'role_sec_x' after its permanent eligibility requests (Authorization_RequestDenied: *"
                        }).Count | Should -Be 1
                    @(Get-LaterAttemptError -Records $Err | Where-Object { $_ -like 'Authorization_RequestDenied,*' }).Count | Should -Be 0
                }
            }
        }

        It 'c: publishes a PolicyOpenedButGrantFailed the second call <Shape> as itself, with no read after the calls' -ForEach @(
            @{ Shape = 'throws' }
            @{ Shape = 'writes through a [CmdletBinding()] function under -ErrorAction Stop' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Prefix = $script:LaterAttemptPrefix; Shape = $Shape } {
                param($Prefix, $Shape)
                # That record already carries the advice for the policy that call opened, so it is
                # published as itself, whatever the state the read would find (here: opened).
                $script:ReadPlan = @('closed', 'open')
                $Advice = "The PIM member eligibility grant failed after PIM-for-groups policy 'pol-member' had been opened to allow " +
                    'permanent eligibility. The policy is still open; ' + (Get-LaterAttemptAdvice -AccessType 'member') +
                    ' The request failed with: Request_BadRequest: Graph rejected the eligibility request.'
                $script:PogfException = [System.Exception]::new($Advice)
                $Second = if ($Shape -eq 'throws') {
                    {
                        throw [System.Management.Automation.ErrorRecord]::new($script:PogfException, 'PolicyOpenedButGrantFailed',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
                    }
                } else {
                    { Write-LaterAttemptRefusal -ErrorId 'PolicyOpenedButGrantFailed' -Exception $script:PogfException -ErrorAction Stop }
                }
                $script:AddPlan = @('failed', $Second)
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupLaterAttemptViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the second call threw. Nothing is read after it.
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add')
                Should -Invoke Add-OERGroupEligibility -Times 2 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ($Prefix + $Advice)
                # The caught record itself, re-published by the caller.
                [object]::ReferenceEquals($Failed[0].Error.Exception, $script:PogfException) | Should -BeTrue
                [string]$Failed[0].Error.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,Invoke-SyncGroupLaterAttemptViaCaller'
                $Copies = @("PolicyOpenedButGrantFailed|$Advice", "PolicyOpenedButGrantFailed,Write-LaterAttemptRefusal|$Advice")
                Assert-LaterAttemptPublished -Records $Err -Id 'PolicyOpenedButGrantFailed' -Message $Advice -Copies $Copies
            }
        }

        It 'd: publishes what the FIRST call throws as itself, with no read after it' {
            InModuleScope $script:moduleName -Parameters @{ Prefix = $script:LaterAttemptPrefix; Caught = $script:LaterAttemptCaught } {
                param($Prefix, $Caught)
                # No request was sent before it, so the call opened nothing it does not say itself.
                $script:ReadPlan = @('closed', 'open')
                $script:AddPlan = @($script:AddPlan[1])
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupLaterAttemptViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the poll, then the one call, which threw. Nothing is read after it.
                @($script:Calls) | Should -Be @('list', 'read', 'add')
                @($script:Slept).Count | Should -Be 0
                Should -Invoke Add-OERGroupEligibility -Times 1 -Exactly
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ($Prefix + $Caught)
                [object]::ReferenceEquals($Failed[0].Error.Exception, $script:ThrownException) | Should -BeTrue
                [string]$Failed[0].Error.FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Invoke-SyncGroupLaterAttemptViaCaller'
                Assert-LaterAttemptPublished -Records $Err -Id 'Request_BadRequest' -Message $Caught -Copies @("Request_BadRequest|$Caught")
            }
        }

        It 'e: publishes the caught record''s own error id when the second call fails with <Shape>' -ForEach @(
            @{ Kind = 'comma'; Shape = 'an error id that contains a comma'; Published = 'Odd,Id' }
            # Thrown, so written by no command: the suffix is none, and a trailing comma is the id's own.
            @{ Kind = 'trailing'; Shape = 'an error id that ends with a comma'; Published = 'Trailing,' }
            @{ Kind = 'cmdlet'; Shape = 'the error of a compiled cmdlet'; Published = 'System.ArgumentException' }
            @{ Kind = 'function'; Shape = 'the error a [CmdletBinding()] function writes under -ErrorAction Stop'; Published = 'Helper_Refused' }
            # Its command has an empty name, so PowerShell appends no suffix (the record reads 'Anon_Id'),
            # while the one computed from the command is ',': the id ends with no suffix and stays whole.
            @{ Kind = 'anonymous'; Shape = 'the error an anonymous [CmdletBinding()] scriptblock writes under -ErrorAction Stop'; Published = 'Anon_Id' }
            # Not the cmdlet's PolicyOpenedButGrantFailed, which it writes in exactly that spelling: the
            # comparison is Ordinal, so this record gets the read and the statement like any other.
            @{ Kind = 'case'; Shape = 'the id PolicyOpenedButGrantFailed in another case'; Published = 'policyopenedbutgrantfailed' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Prefix = $script:LaterAttemptPrefix; Kind = $Kind; Published = $Published } {
                param($Prefix, $Kind, $Published)
                $script:ReadPlan = @('closed', 'open')
                # The caught record as this process makes it, read here first: its message and category.
                $Second = switch ($Kind) {
                    'comma' {
                        {
                            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Odd: an error id with a comma.'), 'Odd,Id',
                                [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
                        }
                    }
                    'trailing' {
                        {
                            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Trailing: an error id that ends with a comma.'), 'Trailing,',
                                [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
                        }
                    }
                    'cmdlet' { { ConvertFrom-Json -InputObject '{' -ErrorAction Stop } }
                    'function' {
                        { Write-LaterAttemptRefusal -ErrorId 'Helper_Refused' -Exception ([System.Exception]::new('Helper refused the grant.')) -ErrorAction Stop }
                    }
                    'anonymous' {
                        {
                            & {
                                [CmdletBinding()]
                                param()
                                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                                        [System.Exception]::new('Anon: refused by an anonymous scriptblock.'), 'Anon_Id',
                                        [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1'))
                            } -ErrorAction Stop
                        }
                    }
                    'case' {
                        {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Lower-case id: not the PolicyOpenedButGrantFailed the cmdlet writes.'), 'policyopenedbutgrantfailed',
                                [System.Management.Automation.ErrorCategory]::InvalidOperation, 'g-1')
                        }
                    }
                }
                @($Second).Count | Should -Be 1
                $Probe = try { & $Second } catch { $PSItem }
                if ($Kind -eq 'anonymous') {
                    # The shape the strip's EndsWith check exists for: a command is recorded, with an
                    # empty name, and the id carries no suffix.
                    $Probe.InvocationInfo.MyCommand | Should -BeOfType ([System.Management.Automation.FunctionInfo])
                    $Probe.InvocationInfo.MyCommand.Name | Should -BeExactly ''
                    [string]$Probe.FullyQualifiedErrorId | Should -BeExactly 'Anon_Id'
                }
                $script:AddPlan = @('failed', $Second)
                $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; eligibility = @([PSCustomObject]@{ principal = 'person16@example.com' }) }
                $Err = $null
                $r = @(Invoke-SyncGroupLaterAttemptViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the second call failed, and the read after it was made.
                @($script:Calls) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read')
                $Expected = $Probe.Exception.Message + " PIM-for-groups policy 'pol-member' had been opened to allow permanent eligibility " +
                    'before the request was sent. The policy is still open; ' + (Get-LaterAttemptAdvice -AccessType 'member')
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly ($Prefix + $Expected)
                $Record = $Failed[0].Error
                $Record.Exception.Message | Should -BeExactly $Expected
                # What a plain re-publish of the caught record through the caller reads: '<id>,<caller>'.
                [string]$Record.FullyQualifiedErrorId | Should -BeExactly ('{0},Invoke-SyncGroupLaterAttemptViaCaller' -f $Published)
                $Record.CategoryInfo.Category | Should -Be $Probe.CategoryInfo.Category
            }
        }

        It 'f: in a script with no try, -ErrorAction Stop on Invoke-OERStructure ends the script with the caught message and the statement, read before it' {
            # The public engine applies a document with one NEW group and one permanent eligibility, in a
            # runspace through Invoke-OERWithConfirmAnswer, so no try stands anywhere above it, as at a
            # prompt. The script is transported as text and installs its own fakes in ITS copy of the
            # module scope; the listings, reads and calls are logged with AppendAllText, whose path is
            # substituted into the text, since a stopped script prints nothing.
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Scenario = & $script:LaterAttemptNoTry -Log $Log -Stop '-ErrorAction Stop'
            # Measured: a stop outside any try ends the whole script, so the runner throws to its caller
            # and no line after the engine, 'END' included, is reached.
            $Thrown = { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } | Should -Throw -PassThru
            $Thrown.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
            $Stopped = $Thrown.Exception.InnerException.ErrorRecord
            [string]$Stopped.FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Invoke-OERStructure'
            $Stopped.Exception.Message | Should -BeExactly $script:LaterAttemptNoTryText
            # Reached: two polls and calls, the second refused, and the read after them -- before the
            # error that stopped the script.
            @(Get-TestLoggedLine -Log $Log) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read')
        }

        It 'f, the control: without Stop the same script reaches the end, and its one error is the caught message and the statement' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (& $script:LaterAttemptNoTry -Log $Log -Stop '')
            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ROW:Failed:*' }) |
                Should -Be @('ROW:Failed:' + $script:LaterAttemptPrefix + $script:LaterAttemptNoTryText)
            @($Run.Output | Where-Object { $_ -like 'ROW:Updated:*' }).Count | Should -Be 0
            @($Run.Errors) | Should -Be @($script:LaterAttemptNoTryText)
            @($Run.Prompts).Count | Should -Be 0
            @(Get-TestLoggedLine -Log $Log) | Should -Be @('list', 'read', 'add', 'list', 'read', 'add', 'list', 'read')
        }
    }

    Context 'eligibility prune answered with a status in the Failed family (BL-33)' {
        # The prune pass removes through Remove-OERGroupEligibility, which runs for REAL here: only the
        # Graph transport, the sign-in and the resolvers are mocked, so its adminRemove POST is answered
        # with the status under test. A Failed answer removed nothing; the cmdlet's own
        # EligibilityRequestFailed error, raised under the -ErrorAction Stop the pass already passes,
        # turns the row Failed. The pass has no code of its own for it. No id below is version-4 shaped.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:EligKeep = 'cccccccc-0000-0000-0000-000000000001'
                $script:EligDrop = 'cccccccc-0000-0000-0000-000000000002'
                $script:AnsweredStatus = 'Failed'
            }
        }

        It 'reports the removal Failed, and never Removed, when Graph answers status <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'FAILED' }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Status = $Status } {
                param($Status)
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:AnsweredStatus = $Status
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = $script:EligKeep; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = $script:EligDrop; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for an eligibility that already matches' }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:EligKeep }
                Mock Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith {
                    @{ id = 'req-prune'; status = $script:AnsweredStatus; action = $Body.action }
                }
                Mock Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } -MockWith { throw "unexpected request: $Uri" }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": "person36@example.com" } ] }' | ConvertFrom-Json
                $Err = $null
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
                # The real cmdlet sent the adminRemove, and Graph answered it.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000002'
                }
                $Pruned = @($Records | Where-Object { $_.Detail -match 'cccccccc-0000-0000-0000-000000000002' })
                @($Pruned).Action | Should -Be @('Failed')
                # The row holds the record as the pass re-published it, under its caller's name; the
                # cmdlet's own record, under the cmdlet's name, stays in the caller's -ErrorVariable too.
                $Pruned[0].Error.FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Invoke-SyncGroupViaCaller'
                @($Err | Where-Object {
                        $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -eq 'EligibilityRequestFailed,Remove-OERGroupEligibility'
                    }).Count | Should -Be 1
                $Pruned[0].Detail | Should -BeExactly ("failed to remove undeclared member eligibility for principal " +
                    "'cccccccc-0000-0000-0000-000000000002': Microsoft Graph accepted the PIM member eligibility removal request " +
                    "'req-prune' for principal 'cccccccc-0000-0000-0000-000000000002' on group 'g-1' but answered status $Status, " +
                    'so nothing was removed: the eligibility is still in place.')
                @($Records | Where-Object { $_.Action -eq 'Removed' }).Count | Should -Be 0
                Should -Invoke Add-OERGroupEligibility -Times 0
            }
        }

        It 'the control: reports the removal Removed when Graph answers status Revoked' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                $script:AnsweredStatus = 'Revoked'
                Mock Resolve-OERGroupId { param($DisplayName) if ($DisplayName -in @('role_sec_x', 'g-1')) { 'g-1' } }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                        Members = @()
                        PimEligibility = @(
                            [PSCustomObject]@{ principalId = $script:EligKeep; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                            [PSCustomObject]@{ principalId = $script:EligDrop; accessId = 'member'; startDateTime = $null; endDateTime = $null }
                        )
                    }
                }
                Mock Add-OERGroupEligibility { throw 'Add-OERGroupEligibility must not be called for an eligibility that already matches' }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERStructurePrincipal { param($Reference) $script:EligKeep }
                Mock Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith {
                    @{ id = 'req-prune'; status = $script:AnsweredStatus; action = $Body.action }
                }
                Mock Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'POST' } -MockWith { throw "unexpected request: $Uri" }
                $Item = '{ "displayName": "role_sec_x", "eligibility": [ { "principal": "person36@example.com" } ] }' | ConvertFrom-Json
                $Err = $null
                $Records = @(Invoke-SyncGroupViaCaller -Item $Item -Prune -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and $Body.principalId -eq 'cccccccc-0000-0000-0000-000000000002'
                }
                $Pruned = @($Records | Where-Object { $_.Detail -match 'cccccccc-0000-0000-0000-000000000002' })
                @($Pruned).Action | Should -Be @('Removed')
                @($Records | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
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

    # R9: previousDisplayName is resolved on every run next to displayName. Both names on DIFFERENT
    # groups is one Failed row and nothing else; only the previous name is a rename folded into the
    # one property PATCH; the same group under both names is the normal path; neither is one Failed
    # row (GroupRenameNotFound) and never a create.
    Context 'previousDisplayName' {

        It 'renames the group found only under its previous name through Set-OERGroup -NewDisplayName and reports one Updated row' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-old'; DisplayName = 'role_sec_hr'; Description = 'HR'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr", "description": "HR", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)

                Should -Invoke Set-OERGroup -Exactly -Times 1 -ParameterFilter { $Group -eq 'g-old' -and $NewDisplayName -eq 'role_sec_hr_emea' }
                Should -Invoke Set-OERGroup -Exactly -Times 1
                Should -Invoke New-OERGroup -Times 0
                # The existing-group path read the group found under its PREVIOUS name.
                Should -Invoke Get-OERGroup -Exactly -Times 1 -ParameterFilter { $Group -eq 'g-old' }
                # Exactly one row: the rename, never also a 'group properties match' Unchanged.
                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'groups'
                $r[0].Item | Should -BeExactly 'role_sec_hr_emea'
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed group 'role_sec_hr' to 'role_sec_hr_emea'"
            }
        }

        It 'folds a rename and a changed description into ONE Set-OERGroup call' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-old'; DisplayName = 'role_sec_hr'; Description = 'old'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr", "description": "new", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)

                Should -Invoke Set-OERGroup -Exactly -Times 1 -ParameterFilter {
                    $Group -eq 'g-old' -and $NewDisplayName -eq 'role_sec_hr_emea' -and $Description -eq 'new'
                }
                Should -Invoke Set-OERGroup -Exactly -Times 1
                Should -Invoke New-OERGroup -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed group 'role_sec_hr' to 'role_sec_hr_emea'; updated group properties (Description)"
            }
        }

        It 'fails the item with one row and a GroupRenameConflict error, reading and writing nothing, when both names exist as different groups' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-new' } -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-new'; DisplayName = 'role_sec_hr_emea'; Description = 'old'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); Owners = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                Mock Add-OERGroupMember { }
                Mock Add-OERGroupEligibility { }
                Mock Send-OERNewGroupEligibilityRequest { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Set-OERGroupPimPolicy { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                # Every collection and a changed property are declared, so a missing guard has
                # something to read, reconcile and write.
                $Item = [PSCustomObject]@{
                    displayName         = 'role_sec_hr_emea'
                    previousDisplayName = 'role_sec_hr'
                    description         = 'new'
                    members             = @('person9@example.com')
                    owners              = @('person16@example.com')
                    eligibility         = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 30 })
                    pimPolicy           = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # Positive identity first: the ONLY row the item emits.
                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'groups'
                $r[0].Item | Should -BeExactly 'role_sec_hr_emea'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "both 'role_sec_hr_emea' and its previousDisplayName 'role_sec_hr' exist as different groups; the document never merges two groups, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^GroupRenameConflict'

                Should -Invoke Get-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Resolve-OERStructurePrincipal -Times 0
                Should -Invoke Add-OERGroupMember -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 0
                Should -Invoke Send-OERNewGroupEligibilityRequest -Times 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 0

                # The Failed row carries the record either way; only the caller's -ErrorVariable
                # proves it was published through $Caller.WriteError.
                @($Err).Count | Should -Be 1
                $Conflict = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupRenameConflict*' })
                $Conflict.Count | Should -Be 1
                $Conflict[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceExists)
                $Conflict[0].TargetObject | Should -BeExactly 'role_sec_hr_emea'
            }
        }

        It 'takes the normal path when both names resolve to the same group' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # Graph matches displayName case-insensitively, so a previous name differing only in
                # case from the new one resolves to the same group.
                Mock Resolve-OERGroupId { 'g-1' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_hr'; Description = 'HR'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr", "previousDisplayName": "ROLE_SEC_HR", "description": "HR", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERGroupId -Exactly -Times 1 -ParameterFilter { $DisplayName -ceq 'ROLE_SEC_HR' }
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'group properties match'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke New-OERGroup -Times 0
            }
        }

        # previousDisplayName may be the group's object id. Resolve-OERGroupId hands a GUID back
        # verbatim WITHOUT asking Graph, so the handler verifies the id with one read of its own: an id
        # that names no group must count as not matching, never as a second group. The Resolve mocks
        # below mirror that verbatim pass-through, which is what made a stale id look like a group.
        It 'treats an object id that names no group as not matching: displayName exists, so a normal update and no conflict' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Resolve-OERGroupId { 'g-1' } -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                # What Invoke-OERGraphRequest returns for a declared not-found answer.
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'Resource does not exist.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-1'; DisplayName = 'role_sec_hr_emea'; Description = 'old'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "description": "new", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # ONE existence read, declaring the not-found answer to the transport.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' -and
                    @($ExpectedErrorCode) -contains 'Request_ResourceNotFound' -and @($ExpectedErrorCode) -contains 'ResourceNotFound'
                }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly 'updated group properties (Description)'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERGroup -Exactly -Times 1 -ParameterFilter { $Group -eq 'g-1' -and -not $NewDisplayName -and $Description -eq 'new' }
                Should -Invoke Set-OERGroup -Exactly -Times 1
                Should -Invoke New-OERGroup -Times 0
            }
        }

        It 'fails with GroupRenameNotFound, creating nothing, when an object id names no group and displayName is absent' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'Resource does not exist.'; Uri = $Uri }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                } -ParameterFilter { $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' }
                # A stale id of a deleted group: reading it as the group to rename would fail here.
                Mock Get-OERGroup { throw "Resource 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' does not exist." }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                Mock Set-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The id WAS checked -- one existence read -- and found to name no group.
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' }
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                @($r).Count | Should -Be 1
                $r[0].Item | Should -BeExactly 'role_sec_hr_emea'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'role_sec_hr_emea' nor its previousDisplayName 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' matches a group, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new group, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^GroupRenameNotFound'
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupRenameNotFound*' }).Count | Should -Be 1
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Get-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
            }
        }

        It 'renames the group an object id names when displayName is absent (the route around an ambiguous old name)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                Mock Invoke-OERGraphRequest { @{ id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' } } -ParameterFilter { $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; DisplayName = 'role_sec_hr'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item)

                Should -Invoke Set-OERGroup -Exactly -Times 1 -ParameterFilter { $Group -eq 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -and $NewDisplayName -eq 'role_sec_hr_emea' }
                Should -Invoke Set-OERGroup -Exactly -Times 1
                Should -Invoke New-OERGroup -Times 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Updated'
                $r[0].Detail | Should -BeExactly "renamed group 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' to 'role_sec_hr_emea'"
            }
        }

        It 'fails with GroupRenameConflict when an object id names a different existing group and displayName exists' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Resolve-OERGroupId { 'g-1' } -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                Mock Invoke-OERGraphRequest { @{ id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' } } -ParameterFilter { $Uri -eq 'v1.0/groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?$select=id' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-1'; Description = $null; Members = @(); PimEligibility = @() } }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "description": "new", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "both 'role_sec_hr_emea' and its previousDisplayName 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' exist as different groups; the document never merges two groups, so nothing was changed -- rename or delete one of them, or remove previousDisplayName"
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupRenameConflict*' }).Count | Should -Be 1
                Should -Invoke Get-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke New-OERGroup -Times 0
            }
        }

        It 'takes the normal path when an object id is the group displayName resolves to, the ids compared case-insensitively' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Resolve-OERGroupId { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Invoke-OERGraphRequest { throw "unexpected Graph call: $Uri" }
                # The id is typed in upper case; Graph finds the group all the same.
                Mock Invoke-OERGraphRequest { @{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' } } -ParameterFilter { $Uri -ceq 'v1.0/groups/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA?$select=id' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; DisplayName = 'role_sec_hr'; Description = 'HR'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr", "previousDisplayName": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "description": "HR", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter { $Uri -ceq 'v1.0/groups/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA?$select=id' }
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                @($Err).Count | Should -Be 0
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                Should -Invoke Set-OERGroup -Times 0
            }
        }

        It 'throws, writing nothing, when the object-id read fails for any reason other than not found' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { if (Test-OERGuid -Value $DisplayName) { $DisplayName } else { $null } }
                Mock Invoke-OERGraphRequest { throw 'Graph 403 Authorization_RequestDenied' }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; Description = $null; Members = @(); PimEligibility = @() } }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                Mock Set-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "members": null }' | ConvertFrom-Json

                # A refused read is not evidence the id names no group: the engine reports the item
                # Failed ("handler error") and nothing is created or renamed.
                { Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue } |
                    Should -Throw -ExpectedMessage '*Authorization_RequestDenied*'
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke Get-OERGroup -Times 0
            }
        }

        # A document that declares a rename names a group that already exists. Right after a rename
        # Graph's lookup can find the group under neither name, so "neither resolves" is never a
        # create: one Failed row and a GroupRenameNotFound error, nothing read or written.
        It 'fails the item with one row and a GroupRenameNotFound error, creating, reading and writing nothing, when neither name resolves' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                Mock Set-OERGroup { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-new'; Description = $null; Members = @(); Owners = @(); PimEligibility = @() } }
                Mock Add-OERGroupMember { }
                Mock Add-OERGroupEligibility { }
                Mock Send-OERNewGroupEligibilityRequest { }
                Mock Get-OERGroupPimPolicy { $null }
                Mock Set-OERGroupPimPolicy { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                # Every collection is declared, so a missing guard has something to create and write.
                $Item = [PSCustomObject]@{
                    displayName         = 'role_sec_hr_emea'
                    previousDisplayName = 'role_sec_hr'
                    members             = @('person9@example.com')
                    owners              = @('person16@example.com')
                    eligibility         = @([PSCustomObject]@{ principal = 'person9@example.com'; durationDays = 30 })
                    pimPolicy           = [PSCustomObject]@{ activationMaxHours = 4 }
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                # Both names were consulted, and found nothing.
                Should -Invoke Resolve-OERGroupId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Should -Invoke Resolve-OERGroupId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                # Positive identity first: the ONLY row the item emits.
                @($r).Count | Should -Be 1
                $r[0].Section | Should -BeExactly 'groups'
                $r[0].Item | Should -BeExactly 'role_sec_hr_emea'
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -BeExactly "neither 'role_sec_hr_emea' nor its previousDisplayName 'role_sec_hr' matches a group, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new group, remove previousDisplayName"
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^GroupRenameNotFound'

                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Get-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke Resolve-OERStructurePrincipal -Times 0
                Should -Invoke Add-OERGroupMember -Times 0
                Should -Invoke Add-OERGroupEligibility -Times 0
                Should -Invoke Send-OERNewGroupEligibilityRequest -Times 0
                Should -Invoke Get-OERGroupPimPolicy -Times 0
                Should -Invoke Set-OERGroupPimPolicy -Times 0

                # Published through $Caller.WriteError: the caller's -ErrorVariable holds exactly it.
                @($Err).Count | Should -Be 1
                $NotFound = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupRenameNotFound*' })
                $NotFound.Count | Should -Be 1
                $NotFound[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                $NotFound[0].TargetObject | Should -BeExactly 'role_sec_hr_emea'
                $NotFound[0].Exception.Message | Should -BeExactly "Neither 'role_sec_hr_emea' nor its previousDisplayName 'role_sec_hr' matches a group, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new group, remove previousDisplayName."
            }
        }

        It 'fails with GroupRenameNotFound under -WhatIf too, never planning a create, when neither name resolves' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr", "members": ["person9@example.com"] }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)

                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Error.FullyQualifiedErrorId | Should -Match '^GroupRenameNotFound'
                @($r | Where-Object { [string]$_.Detail -like 'would create*' }).Count | Should -Be 0
                @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GroupRenameNotFound*' }).Count | Should -Be 1
                Should -Invoke New-OERGroup -Times 0
            }
        }

        It 'still creates the group when no previousDisplayName is declared and displayName does not resolve' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                Mock Set-OERGroup { }
                # An explicit null previousDisplayName is undeclared, like every other key.
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": null, "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke New-OERGroup -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Should -Invoke New-OERGroup -Exactly -Times 1
                Should -Invoke Resolve-OERGroupId -Exactly -Times 1
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Created'
                $r[0].Detail | Should -BeExactly 'created group role_sec_hr_emea (g-new)'
                @($Err).Count | Should -Be 0
            }
        }

        It 'fails loudly, creating and renaming nothing, when the previous name matches several groups' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                # The record Resolve-OERGroupId itself throws for a name matching several groups.
                Mock Resolve-OERGroupId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Group display name 'role_sec_hr' matches 2 groups (g-a, g-b). Entra does not enforce unique group display names, so this name cannot identify a single group. Re-run with the object id instead of the display name."),
                        'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        'role_sec_hr')
                } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock New-OERGroup { [PSCustomObject]@{ Id = 'g-new'; DisplayName = 'role_sec_hr_emea' } }
                Mock Set-OERGroup { }
                Mock Get-OERGroup { [PSCustomObject]@{ Id = 'g-a'; Description = $null; Members = @(); PimEligibility = @() } }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr", "members": null }' | ConvertFrom-Json

                # Thrown out of the handler, as an ambiguous displayName is: the engine turns it into
                # the item's one Failed ("handler error") row.
                { Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue } |
                    Should -Throw -ErrorId 'AmbiguousName'
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke Get-OERGroup -Times 0
            }
        }

        It 'under -WhatIf reports would rename, writes nothing, and plans the children against the group found under its previous name' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-old'; DisplayName = 'role_sec_hr'; Description = 'old'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                Mock Add-OERGroupMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                $Item = [PSCustomObject]@{
                    displayName         = 'role_sec_hr_emea'
                    previousDisplayName = 'role_sec_hr'
                    description         = 'new'
                    members             = @('person9@example.com')
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf)

                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke New-OERGroup -Times 0
                Should -Invoke Add-OERGroupMember -Times 0
                # Reads run under -WhatIf: the group found under its previous name was read.
                Should -Invoke Get-OERGroup -Exactly -Times 1 -ParameterFilter { $Group -eq 'g-old' }
                @($r).Count | Should -Be 2
                $Rename = @($r | Where-Object { $_.Detail -like 'would rename*' })
                $Rename.Count | Should -Be 1
                $Rename[0].Action | Should -BeExactly 'Skipped'
                $Rename[0].Item | Should -BeExactly 'role_sec_hr_emea'
                $Rename[0].Detail | Should -BeExactly "would rename group 'role_sec_hr' to 'role_sec_hr_emea'; would update group properties (Description)"
                @($r | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq "would add member 'person9@example.com'" }).Count | Should -Be 1
            }
        }

        It 'reports Failed and reconciles no child of a group whose rename failed' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-old'; DisplayName = 'role_sec_hr'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { throw 'graph 400' }
                Mock New-OERGroup { }
                Mock Add-OERGroupMember { }
                Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                $Item = [PSCustomObject]@{
                    displayName         = 'role_sec_hr_emea'
                    previousDisplayName = 'role_sec_hr'
                    members             = @('person9@example.com')
                }
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue)

                Should -Invoke Set-OERGroup -Exactly -Times 1 -ParameterFilter { $NewDisplayName -eq 'role_sec_hr_emea' }
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Failed'
                $r[0].Detail | Should -Match '^update failed: graph 400'
                Should -Invoke Resolve-OERStructurePrincipal -Times 0
                Should -Invoke Add-OERGroupMember -Times 0
            }
        }

        It 'reports Unchanged on the run after the rename, with previousDisplayName still declared' {
            InModuleScope $script:moduleName {
                function Invoke-SyncGroupViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Initialize-OERAuth { }
                Mock Resolve-OERStructureDefault { $null }
                # After the rename only the new name exists; the old one resolves to nothing.
                Mock Resolve-OERGroupId { $null }
                Mock Resolve-OERGroupId { 'g-old' } -ParameterFilter { $DisplayName -eq 'role_sec_hr_emea' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-old'; DisplayName = 'role_sec_hr_emea'; Description = 'HR'; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @()
                    }
                }
                Mock Set-OERGroup { }
                Mock New-OERGroup { }
                $Item = '{ "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr", "description": "HR", "members": null }' | ConvertFrom-Json
                $r = @(Invoke-SyncGroupViaCaller -Item $Item -ErrorAction SilentlyContinue -ErrorVariable Err)

                Should -Invoke Resolve-OERGroupId -Exactly -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_hr' }
                @($r).Count | Should -Be 1
                $r[0].Action | Should -BeExactly 'Unchanged'
                $r[0].Detail | Should -BeExactly 'group properties match'
                @($Err).Count | Should -Be 0
                Should -Invoke Set-OERGroup -Times 0
                Should -Invoke New-OERGroup -Times 0
            }
        }
    }

    Context 'pimPolicy onboarding warning for an existing group that does not use PIM for Groups (R3)' {
        # Microsoft Graph lists PIM-for-Groups policies for every group, and the first policy update
        # onboards the group, which cannot be undone. Before step 4 writes a CHANGED policy to a
        # group that already existed, the handler asks Test-OERGroupPimInUse -- once per item -- and
        # warns when the group does not use PIM for Groups yet. It never blocks and never changes a
        # row (docs/development/rationale.md#pim-in-use-criterion).
        BeforeAll {
            # Runs one item through the handler in module scope and hands back its rows and the text
            # of every warning, so the assertions below can run OUTSIDE InModuleScope against the
            # -ModuleName mocks of the BeforeEach.
            function Invoke-R3Sync {
                param([PSCustomObject]$Item, [switch]$WhatIf)
                InModuleScope $script:moduleName -Parameters @{ Item = $Item; WhatIfRun = [bool]$WhatIf } {
                    param($Item, $WhatIfRun)
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                    }
                    $W = $null
                    $R = @(Invoke-SyncGroupViaCaller -Item $Item -WhatIf:$WhatIfRun -ErrorAction SilentlyContinue `
                            -WarningAction SilentlyContinue -WarningVariable W)
                    [PSCustomObject]@{ Rows = $R; Warnings = @(@($W) | ForEach-Object { [string]$_ }) }
                }
            }
            $script:OnboardPattern = 'onboards it to PIM for Groups'
        }
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-1' }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
            }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
            Mock -ModuleName $script:moduleName Set-OERGroupPimPolicy { [PSCustomObject]@{ Applied = $true; FailedRules = @() } }
            Mock -ModuleName $script:moduleName Add-OERGroupEligibility { }
            Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
            Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $false; Reason = 'no PIM policy of the group has been modified and no PIM eligibility was counted'; Manageable = $true }
            }
        }

        It 'warns once per item, and still sets the policy, when an existing group does not use PIM for Groups' {
            # Both access types change, so step 4 reaches its ShouldProcess twice; the question is
            # asked, and the warning written, once for the item.
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{
                    member = [PSCustomObject]@{ activationMaxHours = 4 }
                    owner  = [PSCustomObject]@{ activationMaxHours = 8 } } }
            $Out = Invoke-R3Sync -Item $Item
            $Onboard = @($Out.Warnings | Where-Object { $_ -match $script:OnboardPattern })
            $Onboard.Count | Should -Be 1
            # "was not found to use", never "does not use": the criterion has a documented blind spot
            # (a group used only through PIM active assignments), so the warning states its finding.
            $Onboard[0] | Should -BeExactly ("Sync-OERStructureGroup: group 'role_sec_x' was not found to use PIM for Groups " +
                '(no PIM policy of the group has been modified and no PIM eligibility was counted); applying its pimPolicy ' +
                "onboards it to PIM for Groups, which cannot be undone (Microsoft Graph documentation, 'Onboarding groups to PIM for Groups').")
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 0
            }
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 2 -Exactly
            @($Out.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -match '^pimPolicy \((member|owner)\) set' }).Count | Should -Be 2
            @($Out.Rows | Where-Object { $_.Action -in @('Failed', 'Skipped') }).Count | Should -Be 0
        }

        It 'warns that PIM for Groups cannot manage the group, not the onboarding warning, when the criterion reports ResourceTypeNotSupported' {
            # A dynamic or on-premises-synced group can never be onboarded, so the "onboards it ...
            # cannot be undone" wording would be self-contradictory. Decided from Manageable, not by
            # matching the text of Reason.
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $false; Reason = 'PIM for Groups cannot manage the group (ResourceTypeNotSupported)'; Manageable = $false }
            }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            $Onboard = @($Out.Warnings | Where-Object { $_ -match $script:OnboardPattern })
            $Onboard.Count | Should -Be 0
            $NotManageable = @($Out.Warnings | Where-Object { $_ -match 'cannot manage' })
            $NotManageable.Count | Should -Be 1
            $NotManageable[0] | Should -BeExactly (
                "Sync-OERStructureGroup: PIM for Groups cannot manage group 'role_sec_x' (ResourceTypeNotSupported), " +
                'so its pimPolicy cannot be applied.'
            )
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly
        }

        It 'warns under -WhatIf too, since the question is asked before the ShouldProcess gate' {
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item -WhatIf
            @($Out.Warnings | Where-Object { $_ -match $script:OnboardPattern }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 0
            @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^would set pimPolicy \(member\)' }).Count | Should -Be 1
        }

        It 'warns for a group renamed through previousDisplayName, which takes the existing-group path' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-1' } -ParameterFilter { $DisplayName -eq 'role_sec_old' }
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_old'; Description = $null; MailNickname = $null
                    GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
            }
            Mock -ModuleName $script:moduleName Set-OERGroup { }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; previousDisplayName = 'role_sec_old'
                pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            @($Out.Warnings | Where-Object { $_ -match $script:OnboardPattern }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 1 -Exactly
        }

        It 'does not warn for a group that uses PIM for Groups' {
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = $true; Reason = 'a PIM policy of the group has been modified'; Manageable = $true }
            }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            @($Out.Warnings | Where-Object { $_ -match 'PIM for Groups' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 1 -Exactly
        }

        It 'does not ask for a group created in this run' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName New-OERGroup { [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x' } }
            Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-member' }
            Mock -ModuleName $script:moduleName Get-OERListedGroupPimPolicy { [PSCustomObject]@{ ActivationMaxHours = 1 } }
            Mock -ModuleName $script:moduleName Start-Sleep { }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 0
            @($Out.Warnings | Where-Object { $_ -match 'PIM for Groups' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 1 -Exactly
        }

        It 'does not ask when step 3 of the same item wrote an eligibility this run' {
            # That request has already onboarded the group, so warning about the policy would name a
            # consequence that has already happened.
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'
                eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; durationDays = 30 })
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            Should -Invoke -ModuleName $script:moduleName Add-OERGroupEligibility -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 0
            @($Out.Warnings | Where-Object { $_ -match 'PIM for Groups' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 1 -Exactly
        }

        It 'still asks when the step-3 eligibility write failed' {
            # Only a SUCCESSFUL request onboards the group; a refused one leaves it as it was.
            Mock -ModuleName $script:moduleName Add-OERGroupEligibility { throw 'eligibility refused' }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'
                eligibility = @([PSCustomObject]@{ principal = 'person1@example.com'; durationDays = 30 })
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly
            @($Out.Warnings | Where-Object { $_ -match $script:OnboardPattern }).Count | Should -Be 1
        }

        It 'passes the eligibility count it read when the document declares eligibility' {
            # A permanent entry is reconciled in step 5, after the policy, so nothing is written in
            # step 3 and the question is asked -- with the live eligibility the handler already read.
            Mock -ModuleName $script:moduleName Get-OERGroup {
                [PSCustomObject]@{ Id = 'g-1'; DisplayName = 'role_sec_x'; Description = $null; MailNickname = $null
                    GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @()
                    PimEligibility = @(@{ principalId = 'id-person1@example.com'; accessId = 'member'; startDateTime = '2026-01-01T09:00:00Z'; endDateTime = $null }) }
            }
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse {
                [PSCustomObject]@{ InUse = ($EligibilityCount -gt 0); Reason = 'from the count'; Manageable = $true }
            }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'
                eligibility = @([PSCustomObject]@{ principal = 'person1@example.com' })
                pimPolicy   = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g-1' -and $EligibilityCount -eq 1
            }
            @($Out.Warnings | Where-Object { $_ -match 'PIM for Groups' }).Count | Should -Be 0
        }

        It 'does not ask when the policy already matches' {
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 1 } }
            $Out = Invoke-R3Sync -Item $Item
            Should -Invoke -ModuleName $script:moduleName Test-OERGroupPimInUse -Times 0
            @($Out.Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -match '^pimPolicy \(member\) already matches' }).Count | Should -Be 1
        }

        It 'warns that onboarding could not be ruled out when the criterion cannot be read, and still sets the policy' {
            Mock -ModuleName $script:moduleName Test-OERGroupPimInUse { throw 'Authorization_RequestDenied: Insufficient privileges' }
            $Item = [PSCustomObject]@{ displayName = 'role_sec_x'; pimPolicy = [PSCustomObject]@{ activationMaxHours = 4 } }
            $Out = Invoke-R3Sync -Item $Item
            $Unknown = @($Out.Warnings | Where-Object { $_ -match 'could not determine' })
            $Unknown.Count | Should -Be 1
            $Unknown[0] | Should -BeExactly ("Sync-OERStructureGroup: could not determine whether group 'role_sec_x' uses PIM for Groups " +
                '(Authorization_RequestDenied: Insufficient privileges); if it does not, applying its pimPolicy onboards it, which cannot be undone.')
            Should -Invoke -ModuleName $script:moduleName Set-OERGroupPimPolicy -Times 1 -Exactly
            @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
        }
    }

    Context 'a service principal only the typed read lists' {
        # Microsoft Graph v1.0 groups/{id}/members and groups/{id}/owners leave service principals
        # out (measured 2026-10-06); Get-OERGroupRelation adds the typed
        # .../microsoft.graph.servicePrincipal read. Get-OERGroup is NOT mocked here: the handler
        # reads the live group through the real cmdlet and the real helper, and only the transport
        # is answered. Live state: members g-nested (untyped read) and sp-1 (typed read only);
        # owners u-1 (untyped read) and sp-1 (typed read only).
        BeforeAll {
            # Runs one item through the handler in module scope and hands back its rows, so the
            # assertions below run OUTSIDE InModuleScope against the -ModuleName mocks.
            function Invoke-SpSync {
                param([PSCustomObject]$Item, [switch]$Prune, [switch]$WhatIf, [switch]$NoConfirm)
                InModuleScope $script:moduleName -Parameters @{ Item = $Item; PruneRun = [bool]$Prune; WhatIfRun = [bool]$WhatIf; NoConfirmRun = [bool]$NoConfirm } {
                    param($Item, $PruneRun, $WhatIfRun, $NoConfirmRun)
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    # -Confirm:$false only where asked: a real removal must never wait on a prompt.
                    $Confirmation = @{}
                    if ($NoConfirmRun) { $Confirmation.Confirm = $false }
                    @(Invoke-SyncGroupViaCaller -Item $Item -Prune:$PruneRun -WhatIf:$WhatIfRun @Confirmation `
                            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
                }
            }
            # As Invoke-SpSync, and also hands back the warnings the run wrote, so a test can show
            # which removals warned and that the service principal's withheld prune did not.
            function Invoke-SpSyncCapture {
                param([PSCustomObject]$Item, [switch]$Prune, [switch]$WhatIf, [switch]$NoConfirm)
                InModuleScope $script:moduleName -Parameters @{ Item = $Item; PruneRun = [bool]$Prune; WhatIfRun = [bool]$WhatIf; NoConfirmRun = [bool]$NoConfirm } {
                    param($Item, $PruneRun, $WhatIfRun, $NoConfirmRun)
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $Confirmation = @{}
                    if ($NoConfirmRun) { $Confirmation.Confirm = $false }
                    $Rows = @(Invoke-SyncGroupViaCaller -Item $Item -Prune:$PruneRun -WhatIf:$WhatIfRun @Confirmation `
                            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable SpWarnings)
                    [PSCustomObject]@{ Rows = $Rows; Warnings = @($SpWarnings) }
                }
            }
            # The reason ConvertTo-OERPruneWithheldResult gives for a service principal (A9), held
            # here once so every test below compares the full text.
            $script:SpMemberWithheld = "prune withheld: undeclared member 'sp-1' is a service principal, and -Prune never removes a service principal from a group; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember (-AccessType owner for an owner) if it is meant to go."
            $script:SpOwnerWithheld = "prune withheld: undeclared owner 'sp-1' is a service principal, and -Prune never removes a service principal from a group; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember (-AccessType owner for an owner) if it is meant to go."
        }
        BeforeEach {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { '22222222-2222-2222-2222-222222222222' }
            # An object id resolves to itself, as the real resolver returns an id verbatim.
            Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) $Reference }
            Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
            Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { $null }
            Mock -ModuleName $script:moduleName Add-OERGroupMember { }
            Mock -ModuleName $script:moduleName Remove-OERGroupMember { }
            # Any request the fixture does not answer fails the read visibly as a Failed row.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_x'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
        }

        It 'reports a declared service principal member Unchanged and adds nothing' {
            $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('g-nested', 'sp-1') })
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "member 'g-nested' already present" }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "member 'sp-1' already present" }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal'
            }
        }

        It 'reports an undeclared service principal member as Extra without -Prune, with a hint that -Prune leaves it' {
            $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('g-nested') })
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "member 'g-nested' already present" }).Count | Should -Be 1
            $Extra = @($Rows | Where-Object { $_.Action -eq 'Extra' })
            $Extra.Count | Should -Be 1
            $Extra[0].Detail | Should -BeExactly "undeclared member 'sp-1' (a service principal, which -Prune leaves in place)"
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0
        }

        It 'withholds the prune of an undeclared service principal member under -Prune -WhatIf: Skipped with the reason, no plan and no warning' {
            $Out = Invoke-SpSyncCapture -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('g-nested') }) -Prune -WhatIf
            @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            # Positive identity first: the guard was reached for the service principal, and only once.
            $Withheld = @($Out.Rows | Where-Object { $_.Detail -like "prune withheld: undeclared member 'sp-1' is a service principal*" })
            $Withheld.Count | Should -Be 1
            $Withheld[0].Action | Should -BeExactly 'Skipped'
            $Withheld[0].Detail | Should -BeExactly $script:SpMemberWithheld
            @($Out.Rows | Where-Object { $_.Detail -like 'would remove*' }).Count | Should -Be 0
            @($Out.Warnings | Where-Object { "$_" -match 'sp-1' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
        }

        It 'withholds the prune of an undeclared service principal owner under -Prune -WhatIf: Skipped with the reason, no plan and no warning' {
            $Out = Invoke-SpSyncCapture -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = $null; owners = @('u-1') }) -Prune -WhatIf
            @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            $Withheld = @($Out.Rows | Where-Object { $_.Detail -like "prune withheld: undeclared owner 'sp-1' is a service principal*" })
            $Withheld.Count | Should -Be 1
            $Withheld[0].Action | Should -BeExactly 'Skipped'
            $Withheld[0].Detail | Should -BeExactly $script:SpOwnerWithheld
            @($Out.Rows | Where-Object { $_.Detail -like 'would remove*' }).Count | Should -Be 0
            @($Out.Warnings | Where-Object { "$_" -match 'sp-1' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
        }

        It 'never removes the service principal under a real -Prune, while the user, group, device and untyped members and the user owner of the same run are removed' {
            # Live state for this run: the untyped members read lists a group, a user, a device and
            # an object with no @odata.type, and the typed read the service principal; the owners are
            # two users (untyped) and the service principal (typed). The document declares no member
            # and one of the user owners, so every other live entry is a prune candidate -- and with
            # the declared owner still standing, the last-owner guard does not hide a removal of the
            # service principal owner.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }
                        @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-2'; displayName = 'a member user' }
                        @{ '@odata.type' = '#microsoft.graph.device'; id = 'd-1'; displayName = 'a device' }
                        @{ id = 'n-1'; displayName = 'no type' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }
                        @{ '@odata.type' = '#microsoft.graph.user'; id = 'u-3'; displayName = 'a kept user' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }

            $Out = Invoke-SpSyncCapture -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @(); owners = @('u-3') }) -Prune -NoConfirm

            @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            # Every other member, and the user owner, is removed exactly as before A9. A parameter
            # filter does not see this test's loop variable, so each id has a literal filter.
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'g-nested' -and $AccessType -ne 'owner' }
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'u-2' -and $AccessType -ne 'owner' }
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'd-1' -and $AccessType -ne 'owner' }
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'n-1' -and $AccessType -ne 'owner' }
            foreach ($Id in 'g-nested', 'u-2', 'd-1', 'n-1') {
                @($Out.Rows | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared member '$Id'" }).Count | Should -Be 1
                @($Out.Warnings | Where-Object { "$_" -eq "Sync-OERStructureGroup: removing undeclared member '$Id' from group 'role_sec_x'." }).Count | Should -Be 1
            }
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'u-1' -and $AccessType -eq 'owner' }
            @($Out.Rows | Where-Object { $_.Action -eq 'Removed' -and $_.Detail -eq "removed undeclared owner 'u-1'" }).Count | Should -Be 1
            @($Out.Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "owner 'u-3' already present" }).Count | Should -Be 1
            # The service principal: both rows withheld, no removal call, no warning naming it.
            @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq $script:SpMemberWithheld }).Count | Should -Be 1
            @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -eq $script:SpOwnerWithheld }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly -ParameterFilter { $PrincipalId -eq 'sp-1' }
            @($Out.Warnings | Where-Object { "$_" -match 'sp-1' }).Count | Should -Be 0
            @($Out.Rows | Where-Object { $_.Detail -match "'sp-1'" -and $_.Action -ne 'Skipped' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 5 -Exactly
        }

        It 'withholds a service principal that is the only owner for being a service principal, before the last-owner guard is consulted' {
            # The live set measured on the test tenant: the service principal is the group's only owner.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }

            $Out = Invoke-SpSyncCapture -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = $null; owners = @() }) -Prune -NoConfirm

            $Owner = @($Out.Rows | Where-Object { $_.Detail -match "owner 'sp-1'" })
            $Owner.Count | Should -Be 1
            $Owner[0].Action | Should -BeExactly 'Skipped'
            $Owner[0].Detail | Should -BeExactly $script:SpOwnerWithheld
            @($Out.Rows | Where-Object { $_.Detail -match 'last remaining owner' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly -ParameterFilter { $AccessType -eq 'owner' }
        }

        It 'adds a declared service principal member and owner that are not live, and reports them Updated as for any principal' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }

            $Out = Invoke-SpSyncCapture -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('g-nested', 'sp-2'); owners = @('u-1', 'sp-2') }) -Prune -NoConfirm

            @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'sp-2' -and $AccessType -ne 'owner' }
            Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'sp-2' -and $AccessType -eq 'owner' }
            @($Out.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added member 'sp-2'" }).Count | Should -Be 1
            @($Out.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq "added owner 'sp-2'" }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
        }

        It 'reports a user owner and a service principal owner both Unchanged when both are declared, and adds nothing' {
            $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('u-1', 'sp-1') })
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "owner 'u-1' already present" }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "owner 'sp-1' already present" }).Count | Should -Be 1
            @($Rows | Where-Object { $_.Detail -match 'undeclared owner' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 0
        }

        It 'reports an undeclared service principal owner as Extra without -Prune, with a hint that -Prune leaves it' {
            $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('u-1') })
            @($Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
            @($Rows | Where-Object { $_.Action -eq 'Unchanged' -and $_.Detail -eq "owner 'u-1' already present" }).Count | Should -Be 1
            $Extra = @($Rows | Where-Object { $_.Action -eq 'Extra' -and $_.Detail -match 'owner' })
            $Extra.Count | Should -Be 1
            $Extra[0].Detail | Should -BeExactly "undeclared owner 'sp-1' (a service principal, which -Prune leaves in place)"
            Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0
        }

        Context 'and the typed read then fails' {
            # The typed read fails AFTER the untyped read succeeded. The handler reads the live group
            # with -ErrorAction Stop, so a collection read half is a Failed row and no change at all:
            # were the half taken for the whole, the declared member below would be added and the
            # live one pruned. The mocks carry the same exact-URI filter as the BeforeEach's; defined
            # later, they win.
            It 'reports one Failed row and neither adds nor removes a member, even with -Prune, when the typed members read fails' {
                Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }

                # u-new is not live (an add) and g-nested is live but undeclared (a prune): a handler
                # that reconciled against the half read would call both mocks.
                $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; members = @('u-new') }) -Prune -NoConfirm

                # Positive identity first: the one row is the group's Failed row, from the failed read.
                $Rows.Count | Should -Be 1
                $Rows[0].Section | Should -BeExactly 'groups'
                $Rows[0].Item | Should -BeExactly 'role_sec_x'
                $Rows[0].Action | Should -BeExactly 'Failed'
                $Rows[0].Detail | Should -BeLike "failed to read the current state of group 'role_sec_x': Could not read members for group 22222222-2222-2222-2222-222222222222: Forbidden: denied*"
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' -and $All
                }
                Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 0 -Exactly
                Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
            }

            It 'reports one Failed row and neither adds nor removes an owner, even with -Prune, when the typed owners read fails' {
                Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }

                $Rows = Invoke-SpSync -Item ([PSCustomObject]@{ displayName = 'role_sec_x'; owners = @('u-new') }) -Prune -NoConfirm

                $Rows.Count | Should -Be 1
                $Rows[0].Section | Should -BeExactly 'groups'
                $Rows[0].Item | Should -BeExactly 'role_sec_x'
                $Rows[0].Action | Should -BeExactly 'Failed'
                $Rows[0].Detail | Should -BeLike "failed to read the current state of group 'role_sec_x': Could not read owners for group 22222222-2222-2222-2222-222222222222: Forbidden: denied*"
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' -and $All
                }
                Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 0 -Exactly
                Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 0 -Exactly
            }
        }
    }

    Context 'a permanent grant refused after Add-OERGroupEligibility opened the policy of a group that already existed (BL-98)' {
        # The handler calls Add-OERGroupEligibility with -ErrorAction Stop, so the first error the cmdlet
        # writes is the one that ends it, and the one the handler's catch turns into the item's Failed
        # row. On a grant refused after the cmdlet opened the group's policy, that first error is
        # PolicyOpenedButGrantFailed: the row then carries the advice to close the policy and the
        # grant's own message, and the grant's own record is never written. Add-OERGroupEligibility runs
        # for REAL; mocked are auth, the group and principal lookups, the handler's group read, the
        # policy-state read (the policy forbids permanent eligibility), the policy open (it succeeds)
        # and the Graph transport, which refuses the eligibility POST.
        BeforeAll {
            $script:RefusedItem = '{ "displayName": "role_sec_perm", "members": null, "eligibility": [ { "principal": "person1@example.com", "accessType": "member" } ] }'
            $script:RefusedAdvice = "The PIM member eligibility grant failed after PIM-for-groups policy 'pol-perm' had been opened to allow " +
                "permanent eligibility. The policy is still open; close it with 'Set-OERGroupPimPolicy -Group " +
                "''33333333-3333-3333-3333-3333333333c3'' -AccessType member -AllowPermanentEligibility:`$false' " +
                'if you do not intend to retry.'
            $script:RefusedRowPrefix = "failed to add permanent eligibility for 'person1@example.com': "
            InModuleScope $script:moduleName {
                function script:Invoke-SyncGroupRefusedViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
                }
            }
            function Get-TestLoggedLine ([string]$Log) {
                if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
            }
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth {}
                Mock Resolve-OERGroupId { '33333333-3333-3333-3333-3333333333c3' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = '33333333-3333-3333-3333-3333333333c3'; DisplayName = 'role_sec_perm'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
                }
                Mock Resolve-OERStructurePrincipal { '22222222-2222-2222-2222-2222222222b2' }
                Mock Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-perm'; PermanentAllowed = $false } }
                Mock Enable-OERGroupPermanentEligibility { $true }
                # The real cmdlet's request (POST), refused. Anything else is not simulated and throws.
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'POST' -and $Uri -like '*eligibilityScheduleRequests') {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                            'Request_BadRequest',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation,
                            $null)
                    }
                    throw "unexpected $Method $Uri"
                }
            }
        }

        It 'reports one Failed row carrying the advice and the cause, and the grant''s own record is never written' {
            $Expected = $script:RefusedRowPrefix + $script:RefusedAdvice + ' The request failed with: Request_BadRequest: Graph rejected the eligibility request.'
            InModuleScope $script:moduleName -Parameters @{ Json = $script:RefusedItem; Expected = $Expected } {
                param($Json, $Expected)
                $Err = $null
                $Rows = @(Invoke-SyncGroupRefusedViaCaller -Item ($Json | ConvertFrom-Json) -Confirm:$false `
                        -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
                # Reached: the real cmdlet opened the policy and sent the POST, once each.
                Should -Invoke Enable-OERGroupPermanentEligibility -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'pol-perm' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*eligibilityScheduleRequests' }
                @($Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 0
                $Failed = @($Rows | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeExactly $Expected
                [string]$Failed[0].Error.FullyQualifiedErrorId | Should -BeLike 'PolicyOpenedButGrantFailed*'
                # -ErrorVariable also holds the records the mock layers raise as the refused POST unwinds
                # (a bare Request_BadRequest, naming no command), and the record that stopped the cmdlet
                # also inside the ActionPreferenceStopException (measured), so each id is read from a
                # record or from the record an exception carries.
                $Ids = @($Err | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) { [string]$_.FullyQualifiedErrorId }
                        elseif ($_ -is [System.Management.Automation.IContainsErrorRecord]) { [string]$_.ErrorRecord.FullyQualifiedErrorId }
                    })
                # The handler re-published the advice, and the cmdlet wrote the advice alone: the grant's
                # own record is never written.
                @($Ids | Where-Object { $_ -eq 'PolicyOpenedButGrantFailed,Invoke-SyncGroupRefusedViaCaller' }).Count | Should -Be 1
                @($Ids | Where-Object { $_ -like '*,Add-OERGroupEligibility' } | Sort-Object -Unique) |
                    Should -Be @('PolicyOpenedButGrantFailed,Add-OERGroupEligibility')
            }
        }

        It 'reaches the end of a script with no try, and the Failed row carries the advice and the cause' {
            # The same refused grant where no try stands above the handler, as at a prompt. The script is
            # transported as text into a runspace through Invoke-OERWithConfirmAnswer and installs its
            # own fakes in ITS copy of the module scope; Add-OERGroupEligibility stays real. The policy
            # open and the POST are logged with AppendAllText, whose path is substituted into the text.
            # The handler's one gate is asked under -Confirm and answered Yes.
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value { '33333333-3333-3333-3333-3333333333c3' }
    Set-Item -Path function:script:Get-OERGroup -Value {
        [pscustomobject]@{ Id = '33333333-3333-3333-3333-3333333333c3'; DisplayName = 'role_sec_perm'; Description = $null; MailNickname = $null
            GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
    }
    Set-Item -Path function:script:Resolve-OERStructurePrincipal -Value { '22222222-2222-2222-2222-2222222222b2' }
    Set-Item -Path function:script:Get-OERGroupPermanentEligibilityState -Value {
        [pscustomobject]@{ HasPolicy = $true; PolicyId = 'pol-perm'; PermanentAllowed = $false }
    }
    Set-Item -Path function:script:Enable-OERGroupPermanentEligibility -Value {
        [System.IO.File]::AppendAllText('#LOG#', "open`n")
        $true
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        [System.IO.File]::AppendAllText('#LOG#', "grant $Method`n")
        throw 'Graph rejected the request'
    }
    function script:Invoke-SyncGroupNoTry {
        [CmdletBinding(SupportsShouldProcess)]
        param([PSCustomObject]$Item)
        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
    }
}
$Item = '{ "displayName": "role_sec_perm", "members": null, "eligibility": [ { "principal": "person1@example.com", "accessType": "member" } ] }' | ConvertFrom-Json
& $Module { param($Item) Invoke-SyncGroupNoTry -Item $Item -Confirm -WarningAction SilentlyContinue } $Item | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")))
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
            # Reached: the handler's gate was asked once and accepted, and the real cmdlet opened the
            # policy and sent the POST.
            @($Run.Prompts).Count | Should -Be 1
            @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant POST')
            $Run.Output[-1] | Should -BeExactly 'END'
            $Failed = @($Run.Output | Where-Object { $_ -like 'ROW:Failed:*' })
            $Failed.Count | Should -Be 1
            $Failed[0] | Should -BeExactly ('ROW:Failed:' + $script:RefusedRowPrefix + $script:RefusedAdvice + ' The request failed with: Graph rejected the request')
            @($Run.Output | Where-Object { $_ -like 'ROW:Updated:*' }).Count | Should -Be 0
            # The one error the script shows is the advice, re-published by the handler; the grant's own
            # error is never written.
            @($Run.Errors) | Should -Be @($script:RefusedAdvice + ' The request failed with: Graph rejected the request')
        }
    }

    Context 'a group synchronized from on-premises (A15)' {
        # Decision A15: a group whose LIVE read -- Get-OERGroup's, or the existing group New-OERGroup
        # returns -- carries OnPremisesSyncEnabled True is managed in on-premises Active Directory and
        # read-only in the cloud, so the handler writes nothing to it. Every write it would get is a
        # Skipped row with no ShouldProcess call (so a plan and a real run report the same rows), every
        # undeclared live entry is withheld from the prune, and one warning per item says why. The
        # document's onPremisesSynced key is never consulted and never sent.
        BeforeAll {
            # Runs the items through the handler in module scope, one call per item as the engine makes
            # them, as a plan (-WhatIf) or as a real run (-Confirm:$false), and hands back the rows, the
            # warnings and the errors, so the assertions run OUTSIDE InModuleScope against the
            # -ModuleName mocks.
            function Invoke-SyncedGroupRun {
                param([object[]]$Items, [switch]$Prune, [switch]$Plan)
                InModuleScope $script:moduleName -Parameters @{ Items = $Items; PruneRun = [bool]$Prune; PlanRun = [bool]$Plan } {
                    param($Items, $PruneRun, $PlanRun)
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $Mode = if ($PlanRun) { @{ WhatIf = $true } } else { @{ Confirm = $false } }
                    $Rows = [System.Collections.Generic.List[object]]::new()
                    $Warnings = [System.Collections.Generic.List[object]]::new()
                    $Errors = [System.Collections.Generic.List[object]]::new()
                    foreach ($Item in $Items) {
                        $W = $null
                        $E = $null
                        foreach ($Row in @(Invoke-SyncGroupViaCaller -Item $Item -Prune:$PruneRun @Mode `
                                    -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue)) {
                            $Rows.Add($Row)
                        }
                        foreach ($X in $W) { $Warnings.Add($X) }
                        foreach ($X in $E) { $Errors.Add($X) }
                    }
                    [PSCustomObject]@{ Rows = $Rows.ToArray(); Warnings = $Warnings.ToArray(); Errors = $Errors.ToArray() }
                }
            }
            # The same run with the warning stream merged into the output (3>&1), so a test can show the
            # order in which the warning and the rows were written: 'W' for the warning, and
            # '<Action>:<Detail>' for a row.
            function Get-SyncedGroupSequence {
                param([PSCustomObject]$Item, [switch]$Prune, [switch]$Plan)
                InModuleScope $script:moduleName -Parameters @{ Item = $Item; PruneRun = [bool]$Prune; PlanRun = [bool]$Plan } {
                    param($Item, $PruneRun, $PlanRun)
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $Mode = if ($PlanRun) { @{ WhatIf = $true } } else { @{ Confirm = $false } }
                    foreach ($Record in @(Invoke-SyncGroupViaCaller -Item $Item -Prune:$PruneRun @Mode -WarningAction Continue -ErrorAction SilentlyContinue 3>&1)) {
                        if ($Record -is [System.Management.Automation.WarningRecord]) { 'W' } else { "$($Record.Action):$($Record.Detail)" }
                    }
                }
            }
            # Every write and every read a write would need: none may be called for a synchronized group.
            $script:AssertNothingWritten = {
                foreach ($Cmd in 'Set-OERGroup', 'New-OERGroup', 'Add-OERGroupMember', 'Remove-OERGroupMember',
                    'Add-OERGroupEligibility', 'Send-OERNewGroupEligibilityRequest', 'Remove-OERGroupEligibility',
                    'Set-OERGroupPimPolicy', 'Get-OERGroupPimPolicy', 'Get-OERPimGroupPolicyId', 'Get-OERListedGroupPimPolicy',
                    'Get-OERGroupPermanentEligibilityState', 'Resolve-OERDeclaredApprover', 'Test-OERGroupPimInUse') {
                    Should -Invoke $Cmd -Times 0 -Exactly -ModuleName $script:moduleName -Scope It
                }
            }
            # The item that declares a change of every kind: properties, a member and an owner to add,
            # a time-bound and a permanent eligibility, and a pimPolicy for both access types.
            function New-SyncedTestItem {
                [PSCustomObject]@{
                    displayName  = 'grp-synced'
                    description  = 'cloud text'
                    mailNickname = 'grpcloud'
                    members      = @('kept@example.com', 'new@example.com')
                    owners       = @('owner@example.com', 'owner2@example.com')
                    eligibility  = @([PSCustomObject]@{ principal = 'tb@example.com'; durationDays = 30 },
                        [PSCustomObject]@{ principal = 'perm@example.com' })
                    pimPolicy    = [PSCustomObject]@{ member = [PSCustomObject]@{ activationMaxHours = 4 }; owner = [PSCustomObject]@{ activationMaxHours = 2 } }
                }
            }
            function Get-SyncedRowCount {
                param([object[]]$Rows, [string]$Action, [string]$Detail)
                @($Rows | Where-Object { $_.Action -ceq $Action -and $_.Detail -ceq $Detail }).Count
            }
            # The texts the handler and ConvertTo-OERPruneWithheldResult give, held once here.
            $script:SyncedWarning = "Sync-OERStructureGroup: group 'grp-synced' is synchronized from on-premises (onPremisesSyncEnabled is true) and is managed there, so the apply engine writes nothing to it: every change the document declares for its properties, members, owners, eligibility or pimPolicy is reported Skipped, and -Prune removes nothing from it. Make the change in the on-premises directory."
            $script:SyncedSuffix = ": group 'grp-synced' is synchronized from on-premises and is managed there (onPremisesSyncEnabled), so the apply engine writes nothing to it"
            $script:SyncedWithheldTail = " stays, since group 'grp-synced' is synchronized from on-premises and is managed there, and the apply engine writes nothing to such a group, -Prune included (our own guard, not a Graph rejection). Remove it in the on-premises directory if it is meant to go."
            $script:SyncedExtraTail = " (group 'grp-synced' is synchronized from on-premises, so -Prune leaves it in place)"
        }

        Context 'what the handler writes to it' {
            BeforeEach {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-sync' }
                Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
                Mock -ModuleName $script:moduleName Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-sync'; DisplayName = 'grp-synced'; Description = 'on-prem text'; MailNickname = 'grpsynced'
                        GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $true
                        Members = @([PSCustomObject]@{ id = 'id-kept@example.com'; ObjectType = 'user' },
                            [PSCustomObject]@{ id = 'u-extra'; ObjectType = 'user' })
                        Owners  = @([PSCustomObject]@{ id = 'id-owner@example.com'; ObjectType = 'user' },
                            [PSCustomObject]@{ id = 'o-extra'; ObjectType = 'user' })
                        PimEligibility = @([PSCustomObject]@{ principalId = 'e-extra'; accessId = 'member' })
                    }
                }
                Mock -ModuleName $script:moduleName Set-OERGroup { }
                Mock -ModuleName $script:moduleName New-OERGroup { }
                Mock -ModuleName $script:moduleName Add-OERGroupMember { }
                Mock -ModuleName $script:moduleName Remove-OERGroupMember { }
                Mock -ModuleName $script:moduleName Add-OERGroupEligibility { }
                Mock -ModuleName $script:moduleName Send-OERNewGroupEligibilityRequest { }
                Mock -ModuleName $script:moduleName Remove-OERGroupEligibility { }
                Mock -ModuleName $script:moduleName Set-OERGroupPimPolicy { }
                Mock -ModuleName $script:moduleName Get-OERGroupPimPolicy { }
                Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { }
                Mock -ModuleName $script:moduleName Get-OERListedGroupPimPolicy { }
                Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PermanentAllowed = $false } }
                Mock -ModuleName $script:moduleName Resolve-OERDeclaredApprover { param($Declared) $Declared }
                Mock -ModuleName $script:moduleName Start-Sleep { }
            }

            It 'writes nothing to it under -Prune, reports every write Skipped, and the plan and the run report the same rows' {
                $Plan = Invoke-SyncedGroupRun -Items @(New-SyncedTestItem) -Prune -Plan
                $Run = Invoke-SyncedGroupRun -Items @(New-SyncedTestItem) -Prune
                # Reached: the live group was read for both runs.
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 2 -Exactly -Scope It
                & $script:AssertNothingWritten
                foreach ($Out in $Plan, $Run) {
                    @($Out.Errors).Count | Should -Be 0
                    $SyncWarn = @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' })
                    $SyncWarn.Count | Should -Be 1
                    "$($SyncWarn[0])" | Should -BeExactly $script:SyncedWarning
                    $Rows = @($Out.Rows)
                    $Rows.Count | Should -Be 12
                    @($Rows | Where-Object { $_.Section -cne 'groups' -or $_.Item -cne 'grp-synced' }).Count | Should -Be 0
                    $Props = @($Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -match '^group properties \(.*Description.*\) not updated' })
                    $Props.Count | Should -Be 1
                    $Props[0].Detail | Should -Match 'MailNickname'
                    $Props[0].Detail | Should -BeLike "*) not updated$($script:SyncedSuffix)"
                    Get-SyncedRowCount -Rows $Rows -Action 'Unchanged' -Detail "member 'kept@example.com' already present" | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("member 'new@example.com' not added" + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("prune withheld: undeclared member 'u-extra'" + $script:SyncedWithheldTail) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Unchanged' -Detail "owner 'owner@example.com' already present" | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("owner 'owner2@example.com' not added" + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("prune withheld: undeclared owner 'o-extra'" + $script:SyncedWithheldTail) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("time-bound member eligibility for 'tb@example.com' not set (time-bound member eligibility (30 days) is absent)" + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ('pimPolicy (member) not applied (PIM for Groups cannot manage a group synchronized from on-premises, so its policy is not read)' + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ('pimPolicy (owner) not applied (PIM for Groups cannot manage a group synchronized from on-premises, so its policy is not read)' + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("permanent member eligibility for 'perm@example.com' not set (permanent member eligibility is absent)" + $script:SyncedSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Rows -Action 'Skipped' -Detail ("prune withheld: undeclared member eligibility for principal 'e-extra'" + $script:SyncedWithheldTail) | Should -Be 1
                    # Every Skipped row that is not a withheld prune names the reason.
                    $Declared = @($Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -notlike 'prune withheld: *' })
                    $Declared.Count | Should -Be 7
                    foreach ($Row in $Declared) { $Row.Detail | Should -Match 'is synchronized from on-premises and is managed there' }
                    @($Rows | Where-Object { $_.Action -in 'Updated', 'Removed', 'Created', 'Failed', 'Extra' }).Count | Should -Be 0
                }
                ($Plan.Rows | ForEach-Object { "$($_.Item)|$($_.Action)|$($_.Detail)" }) |
                    Should -Be ($Run.Rows | ForEach-Object { "$($_.Item)|$($_.Action)|$($_.Detail)" })
                # The one warning is written before the first row it explains, in the plan and in the run.
                foreach ($AsPlan in $true, $false) {
                    $Sequence = @(Get-SyncedGroupSequence -Item (New-SyncedTestItem) -Prune -Plan:$AsPlan)
                    @($Sequence | Where-Object { $_ -eq 'W' }).Count | Should -Be 1
                    $Sequence[0] | Should -BeExactly 'W'
                    $Sequence[1] | Should -BeLike 'Skipped:group properties (*) not updated: *'
                }
                & $script:AssertNothingWritten
            }

            It 'writes nothing to it without -Prune, and reports each undeclared live entry Extra with a hint that -Prune leaves it' {
                $Plan = Invoke-SyncedGroupRun -Items @(New-SyncedTestItem) -Plan
                $Run = Invoke-SyncedGroupRun -Items @(New-SyncedTestItem)
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 2 -Exactly -Scope It
                & $script:AssertNothingWritten
                foreach ($Out in $Plan, $Run) {
                    @($Out.Errors).Count | Should -Be 0
                    # The declared changes were skipped, so the item still warns once.
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 1
                    $Extra = @($Out.Rows | Where-Object { $_.Action -eq 'Extra' })
                    $Extra.Count | Should -Be 3
                    foreach ($Row in $Extra) { $Row.Detail | Should -BeLike '*is synchronized from on-premises, so -Prune leaves it in place)' }
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Extra' -Detail ("undeclared member 'u-extra'" + $script:SyncedExtraTail) | Should -Be 1
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Extra' -Detail ("undeclared owner 'o-extra'" + $script:SyncedExtraTail) | Should -Be 1
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Extra' -Detail ("undeclared member eligibility for principal 'e-extra'" + $script:SyncedExtraTail) | Should -Be 1
                    @($Out.Rows | Where-Object { $_.Detail -like 'prune withheld: *' }).Count | Should -Be 0
                    @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' }).Count | Should -Be 7
                    @($Out.Rows | Where-Object { $_.Action -in 'Updated', 'Removed', 'Created', 'Failed' }).Count | Should -Be 0
                }
                ($Plan.Rows | ForEach-Object { "$($_.Item)|$($_.Action)|$($_.Detail)" }) |
                    Should -Be ($Run.Rows | ForEach-Object { "$($_.Item)|$($_.Action)|$($_.Detail)" })
            }

            It 'warns only under -Prune when the item declares no change and the group carries an undeclared live entry' {
                # One item per collection, each declaring only what is live in it, so the one undeclared
                # live entry is the item's only row about the synchronized group: its prune pass alone
                # must write the item's warning.
                $Cases = @(
                    @{ Item = [PSCustomObject]@{ displayName = 'grp-synced'; members = @('kept@example.com') }
                        Kept = "member 'kept@example.com' already present"; Candidate = "undeclared member 'u-extra'" }
                    @{ Item = [PSCustomObject]@{ displayName = 'grp-synced'; members = $null; owners = @('owner@example.com') }
                        Kept = "owner 'owner@example.com' already present"; Candidate = "undeclared owner 'o-extra'" }
                    @{ Item = [PSCustomObject]@{ displayName = 'grp-synced'; members = $null; eligibility = @() }
                        Kept = $null; Candidate = "undeclared member eligibility for principal 'e-extra'" }
                )
                foreach ($Case in $Cases) {
                    $Unchanged = @('group properties match') + @($Case.Kept | Where-Object { $_ })
                    foreach ($AsPlan in $true, $false) {
                        $Out = Invoke-SyncedGroupRun -Items @($Case.Item) -Plan:$AsPlan
                        @($Out.Errors).Count | Should -Be 0
                        @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 0
                        foreach ($Detail in $Unchanged) { Get-SyncedRowCount -Rows $Out.Rows -Action 'Unchanged' -Detail $Detail | Should -Be 1 }
                        Get-SyncedRowCount -Rows $Out.Rows -Action 'Extra' -Detail ($Case.Candidate + $script:SyncedExtraTail) | Should -Be 1
                        @($Out.Rows).Count | Should -Be ($Unchanged.Count + 1)

                        $Out = Invoke-SyncedGroupRun -Items @($Case.Item) -Prune -Plan:$AsPlan
                        @($Out.Errors).Count | Should -Be 0
                        $SyncWarn = @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' })
                        $SyncWarn.Count | Should -Be 1 -Because "the prune of $($Case.Candidate) writes the item's one warning"
                        "$($SyncWarn[0])" | Should -BeExactly $script:SyncedWarning
                        Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ('prune withheld: ' + $Case.Candidate + $script:SyncedWithheldTail) | Should -Be 1
                        @($Out.Rows | Where-Object { $_.Action -eq 'Extra' }).Count | Should -Be 0
                        @($Out.Rows).Count | Should -Be ($Unchanged.Count + 1)

                        # Under -Prune the warning comes directly before the withheld row it explains.
                        $Sequence = @(Get-SyncedGroupSequence -Item $Case.Item -Prune -Plan:$AsPlan)
                        $Sequence | Should -Be (@($Unchanged | ForEach-Object { "Unchanged:$_" }) + 'W' + ('Skipped:prune withheld: ' + $Case.Candidate + $script:SyncedWithheldTail))
                    }
                }
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 18 -Exactly -Scope It
                & $script:AssertNothingWritten
            }

            It 'does not rename it, reports no Failed row and still reconciles its members (Review Focus 2)' {
                Mock -ModuleName $script:moduleName Resolve-OERGroupId { param($DisplayName) if ($DisplayName -eq 'grp-synced') { 'g-sync' } else { $null } }
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; previousDisplayName = 'grp-synced'; members = @('kept@example.com') }
                $NewSuffix = $script:SyncedSuffix.Replace("group 'grp-synced'", "group 'grp-new'")
                foreach ($AsPlan in $true, $false) {
                    $Out = Invoke-SyncedGroupRun -Items @($Item) -Plan:$AsPlan
                    @($Out.Errors).Count | Should -Be 0
                    @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ("group not renamed from 'grp-synced' to 'grp-new'" + $NewSuffix) | Should -Be 1
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Unchanged' -Detail "member 'kept@example.com' already present" | Should -Be 1
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 1
                }
                # A rename beside another changed property names both in the one Skipped row.
                $Item = [PSCustomObject]@{ displayName = 'grp-new'; previousDisplayName = 'grp-synced'; description = 'cloud text'; members = $null }
                foreach ($AsPlan in $true, $false) {
                    $Out = Invoke-SyncedGroupRun -Items @($Item) -Plan:$AsPlan
                    @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ("group not renamed from 'grp-synced' to 'grp-new'; group properties (Description) not updated" + $NewSuffix) | Should -Be 1
                    @($Out.Rows).Count | Should -Be 1
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 1
                }
                # Reached: the previous name was resolved and the live group read in every run.
                Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 4 -Exactly -Scope It -ParameterFilter { $DisplayName -eq 'grp-synced' }
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 4 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 0 -Scope It
                & $script:AssertNothingWritten
            }

            It 'writes nothing to the synchronized group New-OERGroup returns in place of creating one (Review Focus 1)' {
                Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
                Mock -ModuleName $script:moduleName New-OERGroup { [PSCustomObject]@{ Id = 'g-sync'; DisplayName = 'grp-synced'; OnPremisesSyncEnabled = $true } }
                $Item = [PSCustomObject]@{
                    displayName = 'grp-synced'
                    members     = @('new@example.com')
                    eligibility = @([PSCustomObject]@{ principal = 'tb@example.com'; durationDays = 30 },
                        [PSCustomObject]@{ principal = 'perm@example.com' })
                    pimPolicy   = [PSCustomObject]@{ member = [PSCustomObject]@{ activationMaxHours = 4 } }
                }
                $Out = Invoke-SyncedGroupRun -Items @($Item)
                # Reached: the create was asked for once and handed back the existing group.
                Should -Invoke -ModuleName $script:moduleName New-OERGroup -Times 1 -Exactly -Scope It
                @($Out.Errors).Count | Should -Be 0
                Get-SyncedRowCount -Rows $Out.Rows -Action 'Created' -Detail 'created group grp-synced (g-sync)' | Should -Be 1
                Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ("member 'new@example.com' not added" + $script:SyncedSuffix) | Should -Be 1
                Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ("time-bound member eligibility for 'tb@example.com' not set (time-bound member eligibility (30 days) is absent)" + $script:SyncedSuffix) | Should -Be 1
                Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ('pimPolicy (member) not applied (PIM for Groups cannot manage a group synchronized from on-premises, so its policy is not read)' + $script:SyncedSuffix) | Should -Be 1
                Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ("permanent member eligibility for 'perm@example.com' not set (permanent member eligibility is absent)" + $script:SyncedSuffix) | Should -Be 1
                @($Out.Rows).Count | Should -Be 5
                @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 1
                foreach ($Cmd in 'Add-OERGroupMember', 'Send-OERNewGroupEligibilityRequest', 'Add-OERGroupEligibility', 'Set-OERGroupPimPolicy',
                    'Get-OERPimGroupPolicyId', 'Get-OERListedGroupPimPolicy', 'Get-OERGroupPimPolicy', 'Start-Sleep', 'Set-OERGroup', 'Get-OERGroup') {
                    Should -Invoke -ModuleName $script:moduleName $Cmd -Times 0 -Exactly -Scope It
                }
            }

            It 'lets the live read decide, never the document key onPremisesSynced (Review Focus 3)' {
                # (a) The live group is synchronized; the document says it is not.
                $Item = [PSCustomObject]@{ displayName = 'grp-synced'; description = 'cloud text'; onPremisesSynced = $false; members = $null }
                foreach ($AsPlan in $true, $false) {
                    $Out = Invoke-SyncedGroupRun -Items @($Item) -Plan:$AsPlan
                    Get-SyncedRowCount -Rows $Out.Rows -Action 'Skipped' -Detail ('group properties (Description) not updated' + $script:SyncedSuffix) | Should -Be 1
                    @($Out.Rows).Count | Should -Be 1
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 1
                }
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 2 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 0 -Scope It

                # (b) The live group is a cloud group (OnPremisesSyncEnabled empty); the document says it
                # is synchronized.
                Mock -ModuleName $script:moduleName Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-sync'; DisplayName = 'grp-synced'; Description = 'on-prem text'; MailNickname = 'grpsynced'
                        GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $null; Members = @()
                    }
                }
                $Item = [PSCustomObject]@{ displayName = 'grp-synced'; description = 'cloud text'; onPremisesSynced = $true; members = $null }
                $Plan = Invoke-SyncedGroupRun -Items @($Item) -Plan
                $Run = Invoke-SyncedGroupRun -Items @($Item)
                Get-SyncedRowCount -Rows $Plan.Rows -Action 'Skipped' -Detail 'would update group properties (Description)' | Should -Be 1
                Get-SyncedRowCount -Rows $Run.Rows -Action 'Updated' -Detail 'updated group properties (Description)' | Should -Be 1
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 1 -Exactly -Scope It -ParameterFilter { $Description -eq 'cloud text' }
                foreach ($Out in $Plan, $Run) {
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 0
                    @($Out.Rows | Where-Object { $_.Detail -match 'synchronized' }).Count | Should -Be 0
                }
            }

            It 'writes to a group that is no longer synchronized (OnPremisesSyncEnabled False) as to any cloud group (Review Focus 4)' {
                Mock -ModuleName $script:moduleName Get-OERGroup {
                    [PSCustomObject]@{
                        Id = 'g-sync'; DisplayName = 'grp-synced'; Description = 'on-prem text'; MailNickname = 'grpsynced'
                        GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $false
                        Members = @([PSCustomObject]@{ id = 'id-kept@example.com'; ObjectType = 'user' },
                            [PSCustomObject]@{ id = 'u-extra'; ObjectType = 'user' })
                    }
                }
                $Item = [PSCustomObject]@{ displayName = 'grp-synced'; description = 'cloud text'; members = @('kept@example.com', 'new@example.com') }
                $Plan = Invoke-SyncedGroupRun -Items @($Item) -Prune -Plan
                $Run = Invoke-SyncedGroupRun -Items @($Item) -Prune
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Add-OERGroupMember -Times 1 -Exactly -Scope It -ParameterFilter { $PrincipalId -eq 'id-new@example.com' }
                Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Remove-OERGroupMember -Times 1 -Exactly -Scope It -ParameterFilter { $PrincipalId -eq 'u-extra' }
                Get-SyncedRowCount -Rows $Run.Rows -Action 'Updated' -Detail 'updated group properties (Description)' | Should -Be 1
                Get-SyncedRowCount -Rows $Run.Rows -Action 'Updated' -Detail "added member 'new@example.com'" | Should -Be 1
                Get-SyncedRowCount -Rows $Run.Rows -Action 'Removed' -Detail "removed undeclared member 'u-extra'" | Should -Be 1
                foreach ($Out in $Plan, $Run) {
                    @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count | Should -Be 0
                    @($Out.Rows | Where-Object { $_.Detail -match 'synchronized' }).Count | Should -Be 0
                }
            }

            It 'writes nothing to the synchronized item and writes to the cloud item of the same document' {
                Mock -ModuleName $script:moduleName Resolve-OERGroupId {
                    param($DisplayName)
                    if ($DisplayName -eq 'grp-synced') { 'g-sync' } elseif ($DisplayName -eq 'grp-cloud') { 'g-cloud' }
                }
                Mock -ModuleName $script:moduleName Get-OERGroup {
                    param($Group)
                    if ($Group -eq 'g-sync') {
                        [PSCustomObject]@{ Id = 'g-sync'; DisplayName = 'grp-synced'; Description = 'on-prem text'; GroupType = 'Regular'
                            IsAssignableToRole = $false; OnPremisesSyncEnabled = $true; Members = @() }
                    } elseif ($Group -eq 'g-cloud') {
                        [PSCustomObject]@{ Id = 'g-cloud'; DisplayName = 'grp-cloud'; Description = 'old text'; GroupType = 'Regular'
                            IsAssignableToRole = $false; OnPremisesSyncEnabled = $null; Members = @() }
                    }
                }
                # The synchronized item first: a decision that outlived its item would skip the cloud one.
                $Items = @(
                    [PSCustomObject]@{ displayName = 'grp-synced'; description = 'cloud text'; members = $null }
                    [PSCustomObject]@{ displayName = 'grp-cloud'; description = 'new text'; members = $null }
                )
                $Plan = Invoke-SyncedGroupRun -Items $Items -Plan
                $Run = Invoke-SyncedGroupRun -Items $Items
                foreach ($Out in $Plan, $Run) {
                    @($Out.Errors).Count | Should -Be 0
                    $Synced = @($Out.Rows | Where-Object { $_.Item -eq 'grp-synced' })
                    $Synced.Count | Should -Be 1
                    $Synced[0].Action | Should -BeExactly 'Skipped'
                    $Synced[0].Detail | Should -BeExactly ('group properties (Description) not updated' + $script:SyncedSuffix)
                    $SyncWarn = @($Out.Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' })
                    $SyncWarn.Count | Should -Be 1
                    "$($SyncWarn[0])" | Should -BeExactly $script:SyncedWarning
                    @($Out.Warnings | Where-Object { "$_" -match 'grp-cloud' }).Count | Should -Be 0
                }
                Get-SyncedRowCount -Rows $Plan.Rows -Action 'Skipped' -Detail 'would update group properties (Description)' | Should -Be 1
                Get-SyncedRowCount -Rows $Run.Rows -Action 'Updated' -Detail 'updated group properties (Description)' | Should -Be 1
                @($Run.Rows | Where-Object { $_.Item -eq 'grp-cloud' }).Count | Should -Be 1
                Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 4 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName $script:moduleName Set-OERGroup -Times 1 -Exactly -Scope It -ParameterFilter { $Group -eq 'g-cloud' -and $Description -eq 'new text' }
            }
        }

        Context 'the document key onPremisesSynced' {
            It 'is never sent, on the create path or the update path, through the real New-OERGroup and Set-OERGroup' {
                InModuleScope $script:moduleName {
                    function Invoke-SyncGroupViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune)
                        Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet -Prune:$Prune
                    }
                    $script:SyncedKeySent = [System.Collections.Generic.List[object]]::new()
                    Mock Initialize-OERAuth { }
                    Mock Resolve-OERStructurePrincipal { param($Reference) "id-$Reference" }
                    Mock Resolve-OERStructureDefault { $null }
                    Mock Invoke-OERGraphRequest {
                        param($Uri, $Method, $Body)
                        $script:SyncedKeySent.Add([PSCustomObject]@{ Method = $Method; Uri = $Uri; Body = ($Body | ConvertTo-Json -Depth 10 -Compress) })
                        if ($Method -eq 'PATCH') { return $null }
                        @{ id = 'g-new'; displayName = 'grp-new'; onPremisesSyncEnabled = $null }
                    }

                    # Create path: no group of that name, so the real New-OERGroup POSTs one.
                    Mock Resolve-OERGroupId { $null }
                    $E = $null
                    $Rows = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'grp-new'; description = 'd'; onPremisesSynced = $true }) `
                            -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable E)
                    @($E).Count | Should -Be 0
                    @($Rows | Where-Object { $_.Action -eq 'Created' -and $_.Detail -eq 'created group grp-new (g-new)' }).Count | Should -Be 1
                    $Posts = @($script:SyncedKeySent | Where-Object { $_.Method -eq 'POST' })
                    $Posts.Count | Should -Be 1
                    $Posts[0].Uri | Should -BeExactly 'v1.0/groups'
                    $Posts[0].Body | Should -Match '"displayName":"grp-new"'
                    $Posts[0].Body | Should -Match '"description":"d"'

                    # Update path: a live cloud group with another description, so the real Set-OERGroup
                    # PATCHes it.
                    Mock Resolve-OERGroupId { 'g-cloud' }
                    Mock Get-OERGroup {
                        [PSCustomObject]@{ Id = 'g-cloud'; DisplayName = 'grp-cloud'; Description = 'old'; MailNickname = 'grpcloud'
                            GroupType = 'Regular'; IsAssignableToRole = $false; OnPremisesSyncEnabled = $null; Members = @() }
                    }
                    $E = $null
                    $Rows = @(Invoke-SyncGroupViaCaller -Item ([PSCustomObject]@{ displayName = 'grp-cloud'; description = 'new'; onPremisesSynced = $true }) `
                            -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable E)
                    @($E).Count | Should -Be 0
                    @($Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -eq 'updated group properties (Description)' }).Count | Should -Be 1
                    $Patches = @($script:SyncedKeySent | Where-Object { $_.Method -eq 'PATCH' })
                    $Patches.Count | Should -Be 1
                    $Patches[0].Uri | Should -BeExactly 'v1.0/groups/g-cloud'
                    $Patches[0].Body | Should -BeExactly '{"description":"new"}'

                    # No request of either path carried the key.
                    @($script:SyncedKeySent | Where-Object { $_.Body -match 'onPremisesSynced' }).Count | Should -Be 0
                }
            }
        }
    }
}

Describe 'Sync-OERStructureGroup: the plan shows the warning a real run gives (BL-17)' {
    # Under -WhatIf the engine never calls a child cmdlet, so a warning only the cmdlet writes would be
    # missing from the plan. The warnings are counted from the stream (3>&1), with -WarningAction
    # Continue pinned on the call, so a duplicate cannot hide.
    BeforeAll {
        InModuleScope $script:moduleName {
            function script:Invoke-SyncGroupWarnViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item)
                Sync-OERStructureGroup -Item $Item -Caller $PSCmdlet
            }
            # One run of the handler: its rows, and the text of every warning that reached the stream.
            function script:Invoke-GroupWarnCapture {
                param([PSCustomObject]$Item, [bool]$WhatIfRun)
                $All = @(Invoke-SyncGroupWarnViaCaller -Item $Item -WhatIf:$WhatIfRun -Confirm:$false -WarningAction Continue -ErrorAction Stop 3>&1)
                [PSCustomObject]@{
                    Rows     = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
                    Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                }
            }
        }
    }

    Context 'a permanent eligibility that opens the policy (step 5, Add-OERGroupEligibility)' {
        # Add-OERGroupEligibility reads whether the group's policy must be opened for a permanent
        # eligibility and warns before its own gate. Under -WhatIf the handler makes the same read and
        # writes the cmdlet's own text before its gate -- and only under -WhatIf: a real run calls the
        # cmdlet, which writes it, and a copy from the handler would warn twice. In the real runs below
        # Add-OERGroupEligibility runs for REAL: only auth, the group and principal lookups, the
        # handler's group read, the policy-state read both of them make
        # (Get-OERGroupPermanentEligibilityState, so both see the same state) and the Graph transport
        # are mocked.
        BeforeAll {
            $script:PermWarnText = "This eligibility requires opening the PIM-for-groups policy for group '33333333-3333-3333-3333-3333333333c3' (member access) " +
                'to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.'
            $script:PermWarnItem = '{ "displayName": "role_sec_perm", "members": null, "eligibility": [ { "principal": "person1@example.com", "accessType": "member" } ] }'
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth {}
                Mock Resolve-OERGroupId { '33333333-3333-3333-3333-3333333333c3' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = '33333333-3333-3333-3333-3333333333c3'; DisplayName = 'role_sec_perm'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
                }
                Mock Resolve-OERStructurePrincipal { '22222222-2222-2222-2222-2222222222b2' }
                Mock Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-perm'; PermanentAllowed = $false } }
                # The real cmdlet's policy open (read the rule, PATCH it) and its request (POST).
                # Anything else is not simulated and throws.
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'POST') { return @{ id = 'req-perm'; status = 'Provisioned' } }
                    if ($Method -eq 'PATCH') { return @{} }
                    if ($Uri -like '*policies/roleManagementPolicies/pol-perm/rules/Expiration_Admin_Eligibility') {
                        return @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                    }
                    throw "unexpected $Method $Uri"
                }
            }
        }

        It 'writes the warning of Add-OERGroupEligibility once under -WhatIf, before the gate, and never calls the cmdlet' {
            InModuleScope $script:moduleName -Parameters @{ Expected = $script:PermWarnText; Json = $script:PermWarnItem } {
                param($Expected, $Json)
                Mock Add-OERGroupEligibility {}
                $Out = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # Reached: the gate declined and the plan row was written.
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would set permanent member eligibility for 'person1@example.com':*" }).Count | Should -Be 1
                Should -Invoke Add-OERGroupEligibility -Times 0
                # The read the cmdlet makes, with the arguments it would pass.
                Should -Invoke Get-OERGroupPermanentEligibilityState -Times 1 -Exactly -ParameterFilter {
                    $GroupId -eq '33333333-3333-3333-3333-3333333333c3' -and $AccessType -eq 'member'
                }
                $Out.Warnings.Count | Should -Be 1
                $Out.Warnings[0] | Should -BeExactly $Expected
            }
        }

        It 'writes it once in a real run, from the real Add-OERGroupEligibility, with the same text as the -WhatIf plan' {
            InModuleScope $script:moduleName -Parameters @{ Json = $script:PermWarnItem } {
                param($Json)
                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # The plan wrote nothing.
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in @('PATCH', 'POST') }
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                # Reached: the real cmdlet passed its own gate, opened the policy and sent the request.
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/pol-perm/rules/Expiration_Admin_Eligibility' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*eligibilityScheduleRequests' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'set permanent member eligibility*' }).Count | Should -Be 1
                $Plan.Warnings.Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 1 -Because 'a real run must warn once, from the cmdlet, never also from the handler'
                ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
            }
        }

        It 'writes no warning in either mode when the policy already allows permanent eligibility' {
            InModuleScope $script:moduleName -Parameters @{ Json = $script:PermWarnItem } {
                param($Json)
                Mock Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-perm'; PermanentAllowed = $true } }
                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would set permanent member eligibility for 'person1@example.com':*" }).Count | Should -Be 1
                Should -Invoke Get-OERGroupPermanentEligibilityState -Times 1 -Exactly
                $Plan.Warnings.Count | Should -Be 0
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 0
            }
        }

        It 'writes no warning, and still plans the entry, when the policy state cannot be read under -WhatIf' {
            InModuleScope $script:moduleName -Parameters @{ Json = $script:PermWarnItem } {
                param($Json)
                Mock Get-OERGroupPermanentEligibilityState { throw 'Forbidden: policy read denied' }
                Mock Remove-OERErrorRecord {}
                Mock Add-OERGroupEligibility {}
                $Out = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would set permanent member eligibility for 'person1@example.com':*" }).Count | Should -Be 1
                @($Out.Rows | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke Get-OERGroupPermanentEligibilityState -Times 1 -Exactly
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { $Record.Exception.Message -eq 'Forbidden: policy read denied' }
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Out.Warnings.Count | Should -Be 0
            }
        }

        It 'writes no warning under -WhatIf when Microsoft Graph lists no policy to open, as the cmdlet would not' {
            # Add-OERGroupEligibility reports a policy that is not listed as its GroupNotOnboarded error,
            # never as the warning about opening it.
            InModuleScope $script:moduleName -Parameters @{ Json = $script:PermWarnItem } {
                param($Json)
                Mock Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $false; PolicyId = $null; PermanentAllowed = $false } }
                Mock Add-OERGroupEligibility {}
                $Out = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would set permanent member eligibility for 'person1@example.com':*" }).Count | Should -Be 1
                Should -Invoke Get-OERGroupPermanentEligibilityState -Times 1 -Exactly
                Should -Invoke Add-OERGroupEligibility -Times 0
                $Out.Warnings.Count | Should -Be 0
            }
        }
    }

    Context 'a permanent eligibility after step 4 of the same item changes the permanent-eligibility setting' {
        # In a real run step 4 writes the policy before step 5's Add-OERGroupEligibility reads it, so the
        # cmdlet warns on the state step 4 leaves. Under -WhatIf step 4 writes nothing, so the plan
        # decides on the value step 4 WOULD write. Everything below runs for REAL --
        # Set-OERGroupPimPolicy, Add-OERGroupEligibility, Get-OERGroupPermanentEligibilityState and
        # Enable-OERGroupPermanentEligibility included -- except auth, the group, principal and policy-id
        # lookups, the handler's group and policy reads, the PIM-in-use question and the Graph transport.
        # The transport keeps the live Expiration_Admin_Eligibility rule of each access type's policy
        # (member: pol-step, owner: pol-step-owner): a PATCH of it changes what the next read returns,
        # so the cmdlet in step 5 sees what step 4, or an earlier entry, wrote.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:New-StepWarnRule {
                    param([string]$AccessType = 'member')
                    $Required = if ($AccessType -eq 'owner') { $script:StepOwnerEligRequired } else { $script:StepEligRequired }
                    @(
                        @{ id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT8H' }
                        @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $Required; maximumDuration = 'P365D' }
                    )
                }
            }
            $script:StepMemberText = "This eligibility requires opening the PIM-for-groups policy for group '66666666-6666-6666-6666-6666666666e5' (member access) " +
                'to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.'
            $script:StepOwnerText = "This eligibility requires opening the PIM-for-groups policy for group '66666666-6666-6666-6666-6666666666e5' (owner access) " +
                'to allow PERMANENT eligible assignments, which affects ALL owner eligibility for this group.'
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:StepEligRequired = $true
                $script:StepOwnerEligRequired = $true
                Mock Initialize-OERAuth {}
                Mock Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x'; Manageable = $true } }
                Mock Resolve-OERGroupId { '66666666-6666-6666-6666-6666666666e5' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = '66666666-6666-6666-6666-6666666666e5'; DisplayName = 'role_sec_step'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
                }
                Mock Resolve-OERStructurePrincipal {
                    param($Reference)
                    switch ($Reference) {
                        'person1@example.com' { '22222222-2222-2222-2222-2222222222b2' }
                        'person2@example.com' { '22222222-2222-2222-2222-2222222222b3' }
                        'person3@example.com' { '22222222-2222-2222-2222-2222222222b4' }
                        default { throw "unexpected principal $Reference" }
                    }
                }
                Mock Get-OERPimGroupPolicyId { if ($AccessType -eq 'owner') { 'pol-step-owner' } else { 'pol-step' } }
                Mock Get-OERGroupPimPolicy {
                    $StepPolicyId = if ($AccessType -eq 'owner') { 'pol-step-owner' } else { 'pol-step' }
                    ConvertTo-OERGroupPimPolicy -Rules @(New-StepWarnRule -AccessType $AccessType) -GroupId '66666666-6666-6666-6666-6666666666e5' -PolicyId $StepPolicyId -AccessType $AccessType
                }
                # The rule PATCHes (step 4's, and the cmdlet's own opening of the policy), the request
                # POST, the single-rule read and the rule list. Anything else is not simulated and throws.
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'POST' -and $Uri -like '*eligibilityScheduleRequests') { return @{ id = 'req-step'; status = 'Provisioned' } }
                    if ($Uri -match '/roleManagementPolicies/(pol-step|pol-step-owner)/rules(?:/([^/?]+))?$') {
                        $StepAccess = if ($Matches[1] -eq 'pol-step-owner') { 'owner' } else { 'member' }
                        $StepRuleId = $Matches[2]
                        if ($Method -eq 'PATCH' -and $StepRuleId -eq 'Expiration_Admin_Eligibility') {
                            if ($StepAccess -eq 'owner') { $script:StepOwnerEligRequired = [bool]$Body.isExpirationRequired } else { $script:StepEligRequired = [bool]$Body.isExpirationRequired }
                            return @{}
                        }
                        if ($Method -eq 'PATCH' -and $StepRuleId -eq 'Expiration_EndUser_Assignment') { return @{} }
                        if ($Method -ne 'PATCH' -and $Method -ne 'POST') {
                            if ($StepRuleId) { return @(New-StepWarnRule -AccessType $StepAccess | Where-Object { $_.id -eq $StepRuleId })[0] }
                            return @{ value = @(New-StepWarnRule -AccessType $StepAccess) }
                        }
                    }
                    throw "unexpected $Method $Uri"
                }
            }
        }

        It 'plans exactly the permanent-eligibility warnings a real run writes when the document declares <Declared>' -ForEach @(
            # Step 4 opens the policy for permanent eligibility, so step 5 needs no opening: no warning.
            @{ Declared = 'allowPermanentEligibility true on a policy that forbids it'; Policy = '{ "allowPermanentEligibility": true }'
                LiveRequired = $true; WarnCount = 0; EligPatches = 1 }
            # Step 4 closes the policy, so step 5 must open it again: one warning, the same in both modes.
            @{ Declared = 'allowPermanentEligibility false on a policy that allows it'; Policy = '{ "allowPermanentEligibility": false }'
                LiveRequired = $false; WarnCount = 1; EligPatches = 2 }
            # Step 4 changes the policy without touching permanence, so the live read decides: allowed, no warning.
            @{ Declared = 'only activationMaxHours, on a policy that allows permanent eligibility'; Policy = '{ "activationMaxHours": 4 }'
                LiveRequired = $false; WarnCount = 0; EligPatches = 0 }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Policy = $Policy; LiveRequired = $LiveRequired; WarnCount = $WarnCount; EligPatches = $EligPatches } {
                param($Policy, $LiveRequired, $WarnCount, $EligPatches)
                $Json = '{ "displayName": "role_sec_step", "members": null, "pimPolicy": { "member": ' + $Policy +
                    ' }, "eligibility": [ { "principal": "person1@example.com", "accessType": "member" } ] }'
                $Expected = "This eligibility requires opening the PIM-for-groups policy for group '66666666-6666-6666-6666-6666666666e5' (member access) " +
                    'to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.'

                $script:StepEligRequired = $LiveRequired
                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # Reached: both gates declined and planned their rows; nothing was written.
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set pimPolicy (member):*' }).Count | Should -Be 1
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like "would set permanent member eligibility for 'person1@example.com':*" }).Count | Should -Be 1
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in @('PATCH', 'POST') }
                $Plan.Warnings.Count | Should -Be $WarnCount

                $script:StepEligRequired = $LiveRequired
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                # Reached: step 4 wrote the policy and step 5 sent the request, through the real cmdlets.
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'pimPolicy (member) set:*' }).Count | Should -Be 1
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'set permanent member eligibility*' }).Count | Should -Be 1
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times $EligPatches -Exactly -ParameterFilter {
                    $Method -eq 'PATCH' -and $Uri -like '*/roleManagementPolicies/pol-step/rules/Expiration_Admin_Eligibility'
                }
                $Run.Warnings.Count | Should -Be $WarnCount -Because 'the plan must show exactly the permanent-eligibility warnings the run gives'
                if ($WarnCount -eq 1) {
                    $Plan.Warnings[0] | Should -BeExactly $Expected
                    ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
                }
            }
        }

        It 'plans one warning per access type, as a real run writes, for several permanent entries on policies that forbid permanent eligibility' {
            # In a real run the first member entry's Add-OERGroupEligibility opens the member policy, so
            # the second member entry finds it open and writes nothing; the owner policy is separate and
            # warns for itself. No pimPolicy is declared, so step 4 does not run.
            InModuleScope $script:moduleName -Parameters @{ MemberText = $script:StepMemberText; OwnerText = $script:StepOwnerText } {
                param($MemberText, $OwnerText)
                $Json = '{ "displayName": "role_sec_step", "members": null, "eligibility": [ ' +
                    '{ "principal": "person1@example.com", "accessType": "member" }, ' +
                    '{ "principal": "person2@example.com", "accessType": "member" }, ' +
                    '{ "principal": "person3@example.com", "accessType": "owner" } ] }'

                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # Reached: every entry was planned; nothing was written.
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set permanent * eligibility for *' }).Count | Should -Be 3
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in @('PATCH', 'POST') }
                $Plan.Warnings.Count | Should -Be 2
                $Plan.Warnings[0] | Should -BeExactly $MemberText
                $Plan.Warnings[1] | Should -BeExactly $OwnerText

                $script:StepEligRequired = $true
                $script:StepOwnerEligRequired = $true
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                # Reached: each policy was opened once, by its first entry, and every request was sent.
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'set permanent * eligibility for *' }).Count | Should -Be 3
                Should -Invoke Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/roleManagementPolicies/pol-step/rules/Expiration_Admin_Eligibility' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/roleManagementPolicies/pol-step-owner/rules/Expiration_Admin_Eligibility' }
                $Run.Warnings.Count | Should -Be 2 -Because 'a real run warns once per policy it opens'
                ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warnings the run gives, in order'
                ($Run.Warnings[1] -ceq $Plan.Warnings[1]) | Should -BeTrue -Because 'the plan must show the very warnings the run gives, in order'
            }
        }

        It 'decides each access type on its own: step 4 opening the member policy leaves <Entry> to the read of its own policy' -ForEach @(
            # The owner policy still forbids permanent eligibility, so the owner entry warns in both modes.
            @{ Entry = 'a permanent owner entry'; EntryJson = '{ "principal": "person3@example.com", "accessType": "owner" }'
                Row = 'would set permanent owner eligibility*'; RunRow = 'set permanent owner eligibility*'; Warns = $true; OwnerPatches = 1 }
            # Control: the member entry finds the member policy step 4 opens, so neither mode warns.
            @{ Entry = 'a permanent member entry'; EntryJson = '{ "principal": "person1@example.com", "accessType": "member" }'
                Row = 'would set permanent member eligibility*'; RunRow = 'set permanent member eligibility*'; Warns = $false; OwnerPatches = 0 }
        ) {
            InModuleScope $script:moduleName -Parameters @{ EntryJson = $EntryJson; Row = $Row; RunRow = $RunRow; Warns = $Warns; OwnerPatches = $OwnerPatches; OwnerText = $script:StepOwnerText } {
                param($EntryJson, $Row, $RunRow, $Warns, $OwnerPatches, $OwnerText)
                $Json = '{ "displayName": "role_sec_step", "members": null, "pimPolicy": { "member": { "allowPermanentEligibility": true } }, ' +
                    '"eligibility": [ ' + $EntryJson + ' ] }'

                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # Reached: both gates declined and planned their rows; nothing was written.
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set pimPolicy (member):*' }).Count | Should -Be 1
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like $Row }).Count | Should -Be 1
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -in @('PATCH', 'POST') }

                $script:StepEligRequired = $true
                $script:StepOwnerEligRequired = $true
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                # Reached: step 4 opened the member policy and step 5 sent its request.
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'pimPolicy (member) set:*' }).Count | Should -Be 1
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like $RunRow }).Count | Should -Be 1
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/roleManagementPolicies/pol-step/rules/Expiration_Admin_Eligibility' }
                Should -Invoke Invoke-OERGraphRequest -Times $OwnerPatches -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/roleManagementPolicies/pol-step-owner/rules/Expiration_Admin_Eligibility' }
                if ($Warns) {
                    $Plan.Warnings.Count | Should -Be 1
                    $Plan.Warnings[0] | Should -BeExactly $OwnerText
                    $Run.Warnings.Count | Should -Be 1 -Because 'the owner policy is still closed when the owner entry is sent'
                    ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
                } else {
                    $Plan.Warnings.Count | Should -Be 0
                    $Run.Warnings.Count | Should -Be 0
                }
            }
        }
    }

    Context 'the MFA / authentication context pair the diff reconciles (step 4, Set-OERGroupPimPolicy)' {
        # Resolve-OERGroupPimPolicyChange reconciles the pair itself and sends the reconciled rule, so
        # Set-OERGroupPimPolicy, called with those parameters, has nothing left to resolve and writes no
        # warning about it. The handler therefore writes the warning before its gate in EVERY mode
        # (Ruling R5). In the real runs below Set-OERGroupPimPolicy runs for REAL: only auth, the group
        # lookup, the handler's group and policy reads, the reads the cmdlet makes (the policy id and
        # the authentication contexts) and the Graph transport are mocked, and the live rules are built
        # once per test and fed to both the handler's policy read and the cmdlet's rule reads.
        BeforeAll {
            InModuleScope $script:moduleName {
                function script:New-PimWarnRule {
                    param([string[]]$EnabledRules, [string]$ContextId)
                    @(
                        @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'; id = 'Enablement_EndUser_Assignment'; enabledRules = @($EnabledRules) }
                        @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'; id = 'AuthenticationContext_EndUser_Assignment'
                            isEnabled = (-not [string]::IsNullOrEmpty($ContextId)); claimValue = $ContextId }
                    )
                }
            }
        }
        BeforeEach {
            InModuleScope $script:moduleName {
                Mock Initialize-OERAuth {}
                Mock Test-OERGroupPimInUse { [PSCustomObject]@{ InUse = $true; Reason = 'x'; Manageable = $true } }
                Mock Resolve-OERGroupId { '55555555-5555-5555-5555-5555555555d4' }
                Mock Get-OERGroup {
                    [PSCustomObject]@{ Id = '55555555-5555-5555-5555-5555555555d4'; DisplayName = 'role_sec_pim'; Description = $null; MailNickname = $null
                        GroupType = 'Assigned'; IsAssignableToRole = $false; Members = @(); PimEligibility = @() }
                }
                Mock Get-OERGroupPimPolicy {
                    ConvertTo-OERGroupPimPolicy -Rules @($script:PimWarnRules) -GroupId '55555555-5555-5555-5555-5555555555d4' -PolicyId 'pol-pim' -AccessType 'member'
                }
                Mock Get-OERPimGroupPolicyId { 'pol-pim' }
                Mock Get-OERAuthenticationContext { [PSCustomObject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Context one'; IsAvailable = $true } }
                # The real cmdlet's reads of single live rules, and its PATCHes. Anything else is not
                # simulated and throws.
                Mock Invoke-OERGraphRequest {
                    if ($Method -eq 'PATCH') { return @{} }
                    if ($Uri -like '*policies/roleManagementPolicies/pol-pim/rules/*') {
                        $RuleId = ($Uri -split '/')[-1]
                        $Live = @($script:PimWarnRules | Where-Object { $_.id -eq $RuleId })
                        if ($Live.Count -eq 1) { return $Live[0] }
                    }
                    throw "unexpected $Method $Uri"
                }
            }
        }

        It 'writes the reconciled change once under -WhatIf, before the gate, and never calls the cmdlet (<Arm>)' -ForEach @(
            @{ Arm = 'ClearMfa'; Enabled = @('MultiFactorAuthentication', 'Justification'); Ctx = ''
                Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "authenticationContextId": "c1" } } }'
                Expected = "Policy 'pol-pim': mfa cleared: mutually exclusive with authenticationContextId=c1" }
            @{ Arm = 'DisableAuthContext'; Enabled = @('Justification'); Ctx = 'c7'
                Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "activationEnablement": [ "MultiFactorAuthentication" ] } } }'
                Expected = "Policy 'pol-pim': authentication context 'c7' disabled: mutually exclusive with multi-factor authentication on activation" }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Enabled = $Enabled; Ctx = $Ctx; Json = $Json; Expected = $Expected } {
                param($Enabled, $Ctx, $Json, $Expected)
                $script:PimWarnRules = New-PimWarnRule -EnabledRules $Enabled -ContextId $Ctx
                Mock Set-OERGroupPimPolicy {}
                $Out = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # Reached: the gate declined and the plan row was written.
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set pimPolicy (member):*' }).Count | Should -Be 1
                Should -Invoke Set-OERGroupPimPolicy -Times 0
                $Out.Warnings.Count | Should -Be 1
                $Out.Warnings[0] | Should -BeExactly $Expected
            }
        }

        It 'writes it once in a real run, where the real Set-OERGroupPimPolicy stays silent, with the same text as the -WhatIf plan (<Arm>)' -ForEach @(
            @{ Arm = 'ClearMfa'; Enabled = @('MultiFactorAuthentication', 'Justification'); Ctx = ''
                Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "authenticationContextId": "c1" } } }'
                Expected = "Policy 'pol-pim': mfa cleared: mutually exclusive with authenticationContextId=c1" }
            @{ Arm = 'DisableAuthContext'; Enabled = @('Justification'); Ctx = 'c7'
                Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "activationEnablement": [ "MultiFactorAuthentication" ] } } }'
                Expected = "Policy 'pol-pim': authentication context 'c7' disabled: mutually exclusive with multi-factor authentication on activation" }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Enabled = $Enabled; Ctx = $Ctx; Json = $Json; Expected = $Expected } {
                param($Enabled, $Ctx, $Json, $Expected)
                $script:PimWarnRules = New-PimWarnRule -EnabledRules $Enabled -ContextId $Ctx
                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                # The plan wrote nothing.
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                # Reached: the real cmdlet resolved its own policy id and PATCHed both rules of the pair.
                Should -Invoke Get-OERPimGroupPolicyId -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/pol-pim/rules/Enablement_EndUser_Assignment' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/pol-pim/rules/AuthenticationContext_EndUser_Assignment' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' -and $_.Detail -like 'pimPolicy (member) set:*' }).Count | Should -Be 1
                $Plan.Warnings.Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 1 -Because 'a real run must warn once: the handler writes it and the cmdlet, given the reconciled rules, writes none'
                $Run.Warnings[0] | Should -BeExactly $Expected
                ($Run.Warnings[0] -ceq $Plan.Warnings[0]) | Should -BeTrue -Because 'the plan must show the very warning the run gives'
            }
        }

        It 'writes no warning in either mode when the diff reconciles nothing' {
            InModuleScope $script:moduleName {
                # A context is declared, but MFA is not required on activation, so nothing is cleared.
                $script:PimWarnRules = New-PimWarnRule -EnabledRules @('Justification') -ContextId ''
                $Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "authenticationContextId": "c1" } } }'
                $Plan = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                @($Plan.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set pimPolicy (member):*' }).Count | Should -Be 1
                $Plan.Warnings.Count | Should -Be 0
                $Run = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $false
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/pol-pim/rules/AuthenticationContext_EndUser_Assignment' }
                @($Run.Rows | Where-Object { $_.Action -eq 'Updated' }).Count | Should -Be 1
                $Run.Warnings.Count | Should -Be 0
            }
        }

        It 'names the access type and the group when no policy was read' {
            InModuleScope $script:moduleName {
                Mock Get-OERGroupPimPolicy { throw 'Forbidden: policy read denied' }
                Mock Set-OERGroupPimPolicy {}
                # Both sides declared and no live policy: the diff keeps the context and clears MFA.
                $Json = '{ "displayName": "role_sec_pim", "members": null, "pimPolicy": { "member": { "authenticationContextId": "c1", "activationEnablement": [ "MultiFactorAuthentication", "Justification" ] } } }'
                $Out = Invoke-GroupWarnCapture -Item ($Json | ConvertFrom-Json) -WhatIfRun $true
                @($Out.Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'would set pimPolicy (member):*' }).Count | Should -Be 1
                Should -Invoke Set-OERGroupPimPolicy -Times 0
                $Out.Warnings.Count | Should -Be 1
                $Out.Warnings[0] | Should -BeExactly "pimPolicy (member) of group 'role_sec_pim': mfa cleared: mutually exclusive with authenticationContextId=c1"
            }
        }
    }
}
