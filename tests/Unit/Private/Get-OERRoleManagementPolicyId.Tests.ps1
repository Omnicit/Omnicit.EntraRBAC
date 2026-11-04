BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERRoleManagementPolicyId' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'lists assignments at scope (no $filter) and matches roleDefinitionId client-side' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd-other'; policyId = '/s/pol-other'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Other' } } } }
                    [PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd1'; policyId = '/s/pol1'; scope = '/s'; effectiveRules = @([PSCustomObject]@{ id = 'X' }); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' } } } }
                ) }
            }
            $r = Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1'
            $r.PolicyId | Should -Be '/s/pol1'
            $r.RoleDefinitionId | Should -Be '/s/rd1'
            $r.RoleName | Should -Be 'Reader'
            $r.Scope | Should -Be '/s'
            @($r.EffectiveRules).Count | Should -Be 1
            Should -Invoke Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01' -and $Path -notlike '*$filter*' -and $All -eq $true
            }
        }
    }

    It 'throws when no assignment matches the role' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' } | Should -Throw '*was found*'
        }
    }

    It 'throws the no-match case as a plain string without -ThrowUnresolved' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Caught = $null
            try { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be $Caught.Exception.Message
            $Caught.FullyQualifiedErrorId | Should -Not -Match 'RolePolicyUnresolved'
        }
    }

    It 'with -ThrowUnresolved throws the no-match case as RolePolicyUnresolved, ObjectNotFound, same message, target the role definition id' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Plain = $null
            try { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' } catch { $Plain = $PSItem }
            $Caught = $null
            try { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' -ThrowUnresolved } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be 'RolePolicyUnresolved'
            $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Caught.TargetObject | Should -Be '/s/rd1'
            $Caught.Exception.Message | Should -Be $Plain.Exception.Message
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeTrue
        }
    }

    It 'with -ThrowUnresolved lets a failed list through as its own record, never as the no-match record' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Authorization failed (403).'),
                    'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'x')
            }
            $Caught = $null
            try { Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' -ThrowUnresolved } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be 'AuthorizationFailed'
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeFalse
        }
    }

    It 'with -ThrowUnresolved still returns the matching assignment' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{ properties = [PSCustomObject]@{ roleDefinitionId = '/s/rd1'; policyId = '/s/pol1'; scope = '/s'; effectiveRules = @(); policyAssignmentProperties = [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader' } } } }) }
            }
            (Get-OERRoleManagementPolicyId -Scope '/s' -RoleDefinitionId '/s/rd1' -ThrowUnresolved).PolicyId | Should -Be '/s/pol1'
        }
    }
}
