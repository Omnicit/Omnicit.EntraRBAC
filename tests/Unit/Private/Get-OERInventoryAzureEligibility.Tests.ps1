BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
            if ($Scope -eq '/subscriptions/11111111-1111-1111-1111-111111111111') { throw 'boom (throttled)' }
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
