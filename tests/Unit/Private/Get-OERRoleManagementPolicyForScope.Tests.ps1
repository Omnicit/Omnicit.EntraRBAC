BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERRoleManagementPolicyForScope' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'lists assignments at scope once (no $filter, -All) and maps every role' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-read'; policyId = '/s/pol-read'; scope = '/s'; effectiveRules = @([PSCustomObject]@{ id = 'X' }); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' } } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-own'; policyId = '/s/pol-own'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Owner' } } } }
                ) }
            }
            $r = @(Get-OERRoleManagementPolicyForScope -Scope '/s')
            $r.Count | Should -Be 2
            $r[0].PolicyId | Should -Be '/s/pol-read'
            $r[0].RoleDefinitionId | Should -Be '/s/rd-read'
            $r[0].RoleName | Should -Be 'Reader'
            $r[0].Scope | Should -Be '/s'
            @($r[0].EffectiveRules).Count | Should -Be 1
            $r[1].RoleName | Should -Be 'Owner'
            Should -Invoke Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01' -and $Path -notlike '*$filter*' -and $All -eq $true
            }
        }
    }

    It 'carries each row''s policy metadata as PolicyMetadata, as ARM returned it, and $null for a row without one' {
        # BL-107: the export's policy selection reads whether a policy has been changed from the
        # policyAssignmentProperties.policy object the list already carries -- no extra request.
        InModuleScope Omnicit.EntraRBAC {
            $script:ChangedPolicy = [PSCustomObject]@{
                id                   = '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol-read'
                lastModifiedDateTime = '2026-06-01T10:00:00Z'
                lastModifiedBy       = [PSCustomObject]@{ displayName = 'Person One' }
            }
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-read'; policyId = '/s/pol-read'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; policy = $script:ChangedPolicy } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-own'; policyId = '/s/pol-own'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Owner' } } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-con'; policyId = '/s/pol-con'; scope = '/s'; effectiveRules = @() } }
                ) }
            }
            $r = @(Get-OERRoleManagementPolicyForScope -Scope '/s')
            $r.Count | Should -Be 3
            foreach ($Row in $r) { $Row.PSObject.Properties.Name | Should -Contain 'PolicyMetadata' }
            [object]::ReferenceEquals($r[0].PolicyMetadata, $script:ChangedPolicy) | Should -BeTrue -Because 'the metadata is carried as ARM returned it, not rebuilt'
            $r[0].PolicyMetadata.lastModifiedDateTime | Should -Be '2026-06-01T10:00:00Z'
            $r[0].PolicyMetadata.lastModifiedBy.displayName | Should -Be 'Person One'
            $null -eq $r[1].PolicyMetadata | Should -BeTrue -Because 'a row whose policyAssignmentProperties carries no policy has no metadata'
            $null -eq $r[2].PolicyMetadata | Should -BeTrue -Because 'a row with no policyAssignmentProperties at all has no metadata'
            # The existing properties are unchanged beside it.
            ($r[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'PolicyId,RoleDefinitionId,RoleName,Scope,EffectiveRules,PolicyMetadata'
        }
    }

    It 'returns nothing for a scope with no policy assignments' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            @(Get-OERRoleManagementPolicyForScope -Scope '/s').Count | Should -Be 0
        }
    }
}
