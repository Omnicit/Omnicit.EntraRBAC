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

Describe 'Get-OERInventoryAzureEligibility' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'reads exactly once per scope' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment { @() }
        InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope @('/subscriptions/11111111-1111-1111-1111-111111111111', '/subscriptions/22222222-2222-2222-2222-222222222222') | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Get-OEREligibleRoleAssignment -Times 2 -Exactly
    }

    It 'reads a management group scope with -AtScope' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment { @() }
        InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope '/providers/Microsoft.Management/managementGroups/mg-platform' | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Get-OEREligibleRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $Scope -eq '/providers/Microsoft.Management/managementGroups/mg-platform' -and $AtScope -eq $true
        }
    }

    It 'reads a subscription scope without -AtScope' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment { @() }
        InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope '/subscriptions/11111111-1111-1111-1111-111111111111' | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Get-OEREligibleRoleAssignment -Times 1 -Exactly -ParameterFilter {
            $Scope -eq '/subscriptions/11111111-1111-1111-1111-111111111111' -and -not $AtScope
        }
    }

    It 'dedupes the same schedule id seen from two scopes into one entry' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment {
            [PSCustomObject]@{
                RoleEligibilityScheduleId = 'sched-1'
                Scope                     = '/subscriptions/11111111-1111-1111-1111-111111111111'
                RoleDefinitionId          = '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                RoleName                  = 'Owner'
                PrincipalId               = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                PrincipalDisplayName      = 'Anna Berg'
                PrincipalType             = 'User'
                MemberType                = 'Direct'
                Status                    = 'Provisioned'
                StartDateTime             = $null
                EndDateTime               = $null
            }
        }
        $Result = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope @(
                '/subscriptions/11111111-1111-1111-1111-111111111111',
                '/subscriptions/22222222-2222-2222-2222-222222222222'
            )
        }
        @($Result.Eligibilities).Count | Should -Be 1
    }

    It 'lists a failing scope in SkippedScopes, warns once, and still reads the other scope' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment {
            param($Scope, $AtScope)
            if ($Scope -eq '/subscriptions/11111111-1111-1111-1111-111111111111') {
                # The real cmdlet reports an ARM failure NON-terminatingly, through
                # $PSCmdlet.WriteError -- it only becomes terminating because the helper's own
                # -ErrorAction Stop asks for that. A bare `throw` here would terminate the mocked
                # call regardless of what the helper passes, which would stay green even if the
                # helper's -ErrorAction Stop were silently dropped (the call would then return
                # nothing instead of failing, and be read as "no eligibility" rather than "failed
                # read" -- see the ErrorAction mutation-proof test below). Mirroring the real
                # ErrorAction-dependent behaviour is what makes THIS test actually prove that pin.
                $Ea = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                Write-Error -Message 'boom (throttled)' -ErrorId 'Throttled' -ErrorAction $Ea
                return
            }
            [PSCustomObject]@{
                RoleEligibilityScheduleId = 'sched-2'
                Scope                     = $Scope
                RoleDefinitionId          = '/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Authorization/roleDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc'
                RoleName                  = 'Reader'
                PrincipalId               = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
                PrincipalDisplayName      = 'Bo Nilsson'
                PrincipalType             = 'User'
                MemberType                = 'Direct'
                Status                    = 'Provisioned'
                StartDateTime             = $null
                EndDateTime               = $null
            }
        }
        $Stream = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope @(
                '/subscriptions/11111111-1111-1111-1111-111111111111',
                '/subscriptions/22222222-2222-2222-2222-222222222222'
            ) -WarningAction Continue 3>&1
        }
        $Warnings = @($Stream | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $Result = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
        @($Warnings).Count | Should -Be 1 -Because 'a failing scope must warn exactly once, not once per row or silently'
        $Result.SkippedScopes | Should -Contain '/subscriptions/11111111-1111-1111-1111-111111111111'
        @($Result.Eligibilities).Count | Should -Be 1
        $Result.Eligibilities[0].scope | Should -Be '/subscriptions/22222222-2222-2222-2222-222222222222'
    }

    It 'projects the documented fields and leaves endDateTime null for a permanent eligibility' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment {
            [PSCustomObject]@{
                RoleEligibilityScheduleId = 'sched-3'
                Scope                     = '/subscriptions/11111111-1111-1111-1111-111111111111'
                RoleDefinitionId          = '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                RoleName                  = 'Owner'
                PrincipalId               = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                PrincipalDisplayName      = 'Anna Berg'
                PrincipalType             = 'User'
                MemberType                = 'Direct'
                Status                    = 'Provisioned'
                StartDateTime             = (Get-Date '2026-01-01T00:00:00Z')
                EndDateTime               = $null
            }
        }
        $Result = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope '/subscriptions/11111111-1111-1111-1111-111111111111'
        }
        $Item = $Result.Eligibilities[0]
        $Item.scope | Should -Be '/subscriptions/11111111-1111-1111-1111-111111111111'
        $Item.role | Should -Be 'Owner'
        $Item.principal | Should -Be 'Anna Berg'
        $Item.principalType | Should -Be 'User'
        $Item.memberType | Should -Be 'Direct'
        $Item.status | Should -Be 'Provisioned'
        $Item.PSObject.Properties.Name | Should -Contain 'endDateTime'
        $Item.endDateTime | Should -BeNullOrEmpty
    }

    It 'carries the scope and role definition id of every row read in RoleScopes, duplicates included, and leaves the other outputs as they were' {
        # BL-107: the export's role policy selection keeps a policy whose role has an eligibility
        # exactly at the policy's scope, so it needs every row read, not the deduplicated projection.
        $script:EligRoleDef = '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment {
            param($Scope, $AtScope)
            if ($Scope -eq '/subscriptions/33333333-3333-3333-3333-333333333333') {
                Write-Error -Message 'boom (forbidden)' -ErrorId 'Forbidden' -ErrorAction Stop
                return
            }
            # The same schedule seen from both scopes, a row of the subscription's resource group read
            # from the subscription, and a null row.
            [PSCustomObject]@{
                RoleEligibilityScheduleId = 'sched-1'
                Scope                     = '/subscriptions/11111111-1111-1111-1111-111111111111'
                RoleDefinitionId          = $script:EligRoleDef
                RoleName                  = 'Owner'
                PrincipalId               = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                PrincipalType             = 'User'
            }
            if ($Scope -eq '/subscriptions/11111111-1111-1111-1111-111111111111') {
                [PSCustomObject]@{
                    RoleEligibilityScheduleId = 'sched-2'
                    Scope                     = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app'
                    RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc'
                    RoleName                  = 'Reader'
                    PrincipalId               = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
                    PrincipalType             = 'User'
                }
                $null
            }
        }
        $Result = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope @(
                '/subscriptions/11111111-1111-1111-1111-111111111111',
                '/providers/Microsoft.Management/managementGroups/mg-platform',
                '/subscriptions/33333333-3333-3333-3333-333333333333'
            ) -WarningAction SilentlyContinue
        }
        ($Result.PSObject.Properties.Name -join ',') | Should -BeExactly 'Eligibilities,SkippedScopes,RoleScopes'
        $Pairs = @(@($Result.RoleScopes) | ForEach-Object { "$($_.Scope)|$($_.RoleDefinitionId)" })
        ($Pairs -join "`n") | Should -BeExactly (@(
                "/subscriptions/11111111-1111-1111-1111-111111111111|$script:EligRoleDef"
                '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app|/providers/Microsoft.Authorization/roleDefinitions/cccccccc-cccc-cccc-cccc-cccccccccccc'
                "/subscriptions/11111111-1111-1111-1111-111111111111|$script:EligRoleDef"
            ) -join "`n")
        foreach ($Pair in @($Result.RoleScopes)) {
            ($Pair.PSObject.Properties.Name -join ',') | Should -BeExactly 'Scope,RoleDefinitionId'
            $Pair.Scope | Should -BeOfType [string]
            $Pair.RoleDefinitionId | Should -BeOfType [string]
        }
        # The existing outputs: the duplicate schedule is one eligibility, the failed scope is skipped.
        @($Result.Eligibilities).Count | Should -Be 2
        @($Result.SkippedScopes) | Should -Be @('/subscriptions/33333333-3333-3333-3333-333333333333')
    }

    It 'is tagged Omnicit.EntraRBAC.InventoryAzureEligibility' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment { @() }
        $Result = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope '/subscriptions/11111111-1111-1111-1111-111111111111'
        }
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.InventoryAzureEligibility'
    }

    It 'accepts an empty scope collection and returns empty results' {
        Mock -ModuleName $script:moduleName Get-OEREligibleRoleAssignment { @() }
        $Result = InModuleScope $script:moduleName {
            Get-OERInventoryAzureEligibility -Scope @()
        }
        @($Result.Eligibilities).Count | Should -Be 0
        @($Result.SkippedScopes).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Get-OEREligibleRoleAssignment -Times 0
    }
}
