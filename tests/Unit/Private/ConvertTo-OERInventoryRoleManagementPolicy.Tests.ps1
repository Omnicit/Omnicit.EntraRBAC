BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # One policy object in the shape ConvertTo-OERRoleManagementPolicy emits (the type both
    # Get-OERRoleManagementPolicy and Get-OERDirectoryRoleManagementPolicy return). -Override
    # replaces or adds individual properties, so each It states only what it varies.
    function script:New-PolicyFixture {
        param([hashtable]$Override = @{})
        $Props = [ordered]@{
            PolicyId                               = 'policy-0001'
            Scope                                  = '/subscriptions/00000000-0000-0000-0000-000000000001'
            RoleName                               = 'Contributor'
            RoleDefinitionId                       = '11111111-1111-1111-1111-111111111111'
            ActivationMaxHours                     = 8
            RequireMfaOnActivation                 = $true
            RequireJustificationOnActivation       = $true
            RequireTicketOnActivation              = $false
            RequireApproval                        = $false
            Approvers                              = @(
                [PSCustomObject]@{ DisplayName = 'person1'; Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserType = 'User' }
                [PSCustomObject]@{ DisplayName = 'Approvers'; Id = 'aaaaaaaa-0000-0000-0000-000000000002'; UserType = 'Group' }
            )
            AuthenticationContextId                = $null
            AllowPermanentEligibility              = $false
            EligibleDuration                       = 'P365D'
            EligibleDurationDays                   = 365
            AllowPermanentActiveAssignment         = $false
            ActiveDuration                         = 'P180D'
            ActiveDurationDays                     = 180
            RequireMfaOnActiveAssignment           = $false
            RequireJustificationOnActiveAssignment = $true
        }
        foreach ($Key in $Override.Keys) { $Props[$Key] = $Override[$Key] }
        $Out = [PSCustomObject]$Props
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleManagementPolicy')
        $Out
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERInventoryRoleManagementPolicy' {
    Context 'without -Directory (the roleManagementPolicies entry)' {
        It 'emits, key for key and in order, the entry the inline Get-OERInventory projection emitted for <Case>' -TestCases @(
            @{
                Case     = 'a full policy whose approval is off but still carries approvers'
                Override = @{}
                # Built literally: this is what the loop in Get-OERInventory produced before the
                # projection moved into the helper. No approval gate on this side: the Azure entry
                # keeps its approvers whatever requireApproval says.
                Expected = [PSCustomObject][ordered]@{
                    scope                                  = '/subscriptions/00000000-0000-0000-0000-000000000001'
                    role                                   = 'Contributor'
                    allowPermanentEligibility              = $false
                    activationMaxHours                     = 8
                    eligibleDurationDays                   = 365
                    allowPermanentActiveAssignment         = $false
                    activeDurationDays                     = 180
                    requireMfaOnActivation                 = $true
                    requireJustificationOnActivation       = $true
                    requireTicketOnActivation              = $false
                    requireApproval                        = $false
                    requireMfaOnActiveAssignment           = $false
                    requireJustificationOnActiveAssignment = $true
                    approvers                              = [PSCustomObject][ordered]@{
                        users  = @('aaaaaaaa-0000-0000-0000-000000000001')
                        groups = @('aaaaaaaa-0000-0000-0000-000000000002')
                    }
                }
            }
            @{
                Case     = 'a sparse policy with an authentication context, no role name and no approvers'
                Override = @{
                    RoleName = ''; ActivationMaxHours = $null; AllowPermanentEligibility = $null
                    EligibleDurationDays = $null; AllowPermanentActiveAssignment = $null; ActiveDurationDays = $null
                    AuthenticationContextId = 'c1'; Approvers = @()
                }
                # scope, role, allowPermanentEligibility and activationMaxHours are emitted even
                # when null on this side; requireMfaOnActivation gives way to the context.
                Expected = [PSCustomObject][ordered]@{
                    scope                                  = '/subscriptions/00000000-0000-0000-0000-000000000001'
                    role                                   = '11111111-1111-1111-1111-111111111111'
                    allowPermanentEligibility              = $null
                    activationMaxHours                     = $null
                    requireJustificationOnActivation       = $true
                    requireTicketOnActivation              = $false
                    requireApproval                        = $false
                    requireMfaOnActiveAssignment           = $false
                    requireJustificationOnActiveAssignment = $true
                    authenticationContextId                = 'c1'
                }
            }
        ) {
            $Policy = New-PolicyFixture -Override $Override
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy
            }
            @($Entry.PSObject.Properties.Name) | Should -Be @($Expected.PSObject.Properties.Name)
            ($Entry | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly ($Expected | ConvertTo-Json -Depth 5 -Compress)
        }
    }

    Context 'with -Directory (the directoryRoleManagementPolicies entry)' {
        It 'emits no scope key, keeps the Azure key order otherwise, and falls back to the role definition id when RoleName is empty' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; RoleName = '' }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'scope'
            $Entry.role | Should -BeExactly '11111111-1111-1111-1111-111111111111'
            @($Entry.PSObject.Properties.Name) | Should -Be @('role', 'allowPermanentEligibility', 'activationMaxHours',
                'eligibleDurationDays', 'allowPermanentActiveAssignment', 'activeDurationDays', 'requireMfaOnActivation',
                'requireJustificationOnActivation', 'requireTicketOnActivation', 'requireApproval',
                'requireMfaOnActiveAssignment', 'requireJustificationOnActiveAssignment')
        }

        It 'uses the role name when there is one' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; RoleName = 'Fixture Role A' }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.role | Should -BeExactly 'Fixture Role A'
        }

        It 'emits no approvers key while approval is off, even when the live policy still lists an approver' {
            $Policy = New-PolicyFixture -Override @{
                Scope = '/'; RequireApproval = $false
                Approvers = @([PSCustomObject]@{ DisplayName = 'person1'; Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserType = 'User' })
            }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.requireApproval | Should -BeFalse
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'approvers'
        }

        It 'emits the approver object ids by side while approval is on' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; RequireApproval = $true }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.requireApproval | Should -BeTrue
            @($Entry.approvers.users) | Should -Be @('aaaaaaaa-0000-0000-0000-000000000001')
            @($Entry.approvers.groups) | Should -Be @('aaaaaaaa-0000-0000-0000-000000000002')
        }

        It 'emits no approvers key while approval is on but no approver is listed' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; RequireApproval = $true; Approvers = @() }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'approvers'
        }

        It 'omits activationMaxHours and allowPermanentEligibility when the live policy carries no value' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; ActivationMaxHours = $null; AllowPermanentEligibility = $null }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'activationMaxHours'
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'allowPermanentEligibility'
        }

        It 'carries the authentication context and drops requireMfaOnActivation when a context is enabled' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/'; AuthenticationContextId = 'c1'; RequireMfaOnActivation = $true }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry.authenticationContextId | Should -BeExactly 'c1'
            $Entry.PSObject.Properties.Name | Should -Not -Contain 'requireMfaOnActivation'
        }

        It 'returns a plain PSCustomObject with no type name of its own' {
            $Policy = New-PolicyFixture -Override @{ Scope = '/' }
            $Entry = InModuleScope $script:moduleName -Parameters @{ Policy = $Policy } {
                param($Policy)
                ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy -Directory
            }
            $Entry | Should -BeOfType [System.Management.Automation.PSCustomObject]
            $Entry.PSObject.TypeNames[0] | Should -BeExactly 'System.Management.Automation.PSCustomObject'
        }
    }
}
