BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryRolePolicy' {
    # BL-107. The export's per-scope policy read when it selects: the same ONE paged list and the same
    # converters as Get-OERInventory -Include RoleManagementPolicies -AllRolesAtScope, plus the facts
    # the selection needs. One ARM answer for the scope: four roles -- an untouched one with an
    # activation window, MFA and an eligibility expiry; a changed one with approval and two approvers;
    # one with an authentication context and no policy metadata; and a second row for the first role,
    # which both paths drop as a duplicate. No id below is version-4 shaped.
    BeforeAll {
        $script:RpScope = '/subscriptions/11111111-1111-1111-1111-111111111111'
        $script:RpRoleDef = "$script:RpScope/providers/Microsoft.Authorization/roleDefinitions"
        $script:RpPolicy = "$script:RpScope/providers/Microsoft.Authorization/roleManagementPolicies"
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth {}
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            param([string]$Method, [string]$Path, $Body, [switch]$All)
            $Untouched = [PSCustomObject]@{ id = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000001"; lastModifiedBy = [PSCustomObject]@{} }
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ properties = [PSCustomObject]@{
                        roleDefinitionId = "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000001"
                        policyId         = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000001"
                        scope            = $script:RpScope
                        effectiveRules   = @(
                            [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                            [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                            [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                        )
                        policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; policy = $Untouched }
                    } }
                [PSCustomObject]@{ properties = [PSCustomObject]@{
                        roleDefinitionId = "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000002"
                        policyId         = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000002"
                        scope            = $script:RpScope
                        effectiveRules   = @(
                            [PSCustomObject]@{ id = 'Approval_EndUser_Assignment'; setting = [PSCustomObject]@{
                                    isApprovalRequired = $true
                                    approvalStages     = @([PSCustomObject]@{ primaryApprovers = @(
                                                [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; userType = 'User'; description = 'Person One' }
                                                [PSCustomObject]@{ id = '33333333-3333-3333-3333-333333333333'; userType = 'Group'; description = 'Approvers' }
                                            ) })
                                } }
                        )
                        policyAssignmentProperties = [PSCustomObject]@{
                            roleDefinition = [PSCustomObject]@{ displayName = 'Contributor' }
                            policy         = [PSCustomObject]@{ id = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000002"; lastModifiedDateTime = '2026-06-01T10:00:00Z'; lastModifiedBy = [PSCustomObject]@{ displayName = 'Person One' } }
                        }
                    } }
                [PSCustomObject]@{ properties = [PSCustomObject]@{
                        roleDefinitionId = "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000003"
                        policyId         = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000003"
                        scope            = $script:RpScope
                        effectiveRules   = @(
                            [PSCustomObject]@{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                            [PSCustomObject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication') }
                        )
                        policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Owner' } }
                    } }
                [PSCustomObject]@{ properties = [PSCustomObject]@{
                        roleDefinitionId = "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000001"
                        policyId         = "$script:RpPolicy/bbbbbbbb-0000-0000-0000-000000000004"
                        scope            = $script:RpScope
                        effectiveRules   = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT2H' })
                        policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; policy = $Untouched }
                    } }
            ) }
        }
    }

    It 'returns exactly the entries Get-OERInventory -AllRolesAtScope returns for the same answer' {
        $Rows = @(InModuleScope Omnicit.EntraRBAC -Parameters @{ S = $script:RpScope } {
                param($S)
                Get-OERInventoryRolePolicy -Scope $S
            })
        $Inventory = Get-OERInventory -Include RoleManagementPolicies -AllRolesAtScope -Scope $script:RpScope -IncludeARM

        # The fixture is not vacuous: three roles survive the duplicate on both paths, and the
        # approvers and the authentication context are in the entries compared.
        $Rows.Count | Should -Be 3
        @($Inventory.RoleManagementPolicies).Count | Should -Be 3
        @($Rows.Entry | Where-Object { $_.PSObject.Properties.Name -contains 'approvers' }).Count | Should -Be 1
        @($Rows.Entry | Where-Object { $_.authenticationContextId -eq 'c1' }).Count | Should -Be 1
        $Rows[0].Entry.activationMaxHours | Should -Be 8 -Because 'the first row of a role is the one kept, as Get-OERInventory keeps it'

        $Mine = ConvertTo-Json -InputObject @($Rows.Entry) -Depth 12
        $Today = ConvertTo-Json -InputObject @($Inventory.RoleManagementPolicies) -Depth 12
        $Mine | Should -BeExactly $Today
    }

    It 'carries the canonical scope, the role definition id and whether the policy was changed' {
        $Rows = @(InModuleScope Omnicit.EntraRBAC -Parameters @{ S = "$script:RpScope/" } {
                param($S)
                Get-OERInventoryRolePolicy -Scope $S
            })
        $Rows.Count | Should -Be 3
        foreach ($Row in $Rows) {
            ($Row.PSObject.Properties.Name -join ',') | Should -BeExactly 'Entry,Scope,RoleDefinitionId,Modified'
            $Row.Scope | Should -BeExactly $script:RpScope -Because 'the scope is carried in the canonical form, trailing slash trimmed'
        }
        $Rows[0].RoleDefinitionId | Should -BeExactly "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000001"
        $Rows[1].RoleDefinitionId | Should -BeExactly "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000002"
        $Rows[2].RoleDefinitionId | Should -BeExactly "$script:RpRoleDef/aaaaaaaa-0000-0000-0000-000000000003"
        $Rows[0].Modified | Should -BeExactly $false
        $Rows[1].Modified | Should -BeExactly $true
        $null -eq $Rows[2].Modified | Should -BeTrue -Because 'a row with no policy metadata cannot be judged'
        # The entry itself keeps the scope as the list was asked for it, as Get-OERInventory's does.
        $Rows[0].Entry.scope | Should -BeExactly "$script:RpScope/"
    }

    It 'sends one paged list for the scope, never a GET of a single policy, and never signs in' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ S = $script:RpScope } {
            param($S)
            Get-OERInventoryRolePolicy -Scope $S | Out-Null
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq "$script:RpScope/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01" -and $All
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/roleManagementPolicies/*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
    }

    It 'throws the Resolve-OERScope message for a scope that does not start with a slash, and sends nothing' {
        {
            InModuleScope Omnicit.EntraRBAC {
                Get-OERInventoryRolePolicy -Scope 'subscriptions/11111111-1111-1111-1111-111111111111'
            }
        } | Should -Throw "Scope 'subscriptions/11111111-1111-1111-1111-111111111111' is not a valid ARM resource id: it must start with '/'."
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'throws when the list cannot be read' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'Service unavailable (503)' }
        {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ S = $script:RpScope } {
                param($S)
                Get-OERInventoryRolePolicy -Scope $S
            }
        } | Should -Throw '*Service unavailable (503)*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
    }

    It 'returns nothing for a scope with no policy assignments' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $Rows = @(InModuleScope Omnicit.EntraRBAC -Parameters @{ S = $script:RpScope } {
                param($S)
                Get-OERInventoryRolePolicy -Scope $S
            })
        $Rows.Count | Should -Be 0
    }
}
