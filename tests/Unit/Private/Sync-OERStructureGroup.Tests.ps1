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
                    're-running the same document usually applies it.')
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
                    're-running the same document usually applies it.')
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
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it.')
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
                        [int]$PostFailed, [switch]$PostForbidden)
                    if ($Uri -like '*eligibilityScheduleRequests*') {
                        $script:Posts++
                        $script:Calls.Add('post')
                        if ($PostForbidden) {
                            throw [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                        }
                        # Accepted (201), and the body already says Failed (measured live 2026-10-03).
                        if ($script:Posts -le $PostFailed) { return @{ id = "req-$($script:Posts)"; status = 'Failed' } }
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
                $Failed[0].Detail | Should -BeExactly ("permanent eligibility for 'person16@example.com' (member) not applied: for group 'role_sec_x', created in " +
                    "this run, Microsoft Graph did not list a readable PIM-for-groups policy for 'member' access, or accepted " +
                    "the request but answered status Failed, every time within the 30-second wait. A new group's policies can " +
                    'take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); ' +
                    're-running the same document usually applies it.')
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
}
