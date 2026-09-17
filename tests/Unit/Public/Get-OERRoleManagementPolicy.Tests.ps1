BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERRoleManagementPolicy' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'ByRole' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/s1'
                    EffectiveRules = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) }
            }
        }
        It 'resolves role+scope to a policy and returns a tagged object' {
            $p = Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod'
            $p.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            $p.PolicyId | Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'
            $p.RoleName | Should -Be 'Reader'
            $p.ActivationMaxHours | Should -Be 8
        }
        It 'routes a policy-not-found resolver error as PolicyNotFound' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId { throw 'No role management policy assignment was found.' }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PolicyNotFound'
        }
        It 'routes a scope resolver error as InvalidScope' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw 'bad scope' }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidScope'
        }
        It 'routes a role resolver error as RoleDefinitionNotFound' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { throw 'no role' }
            Get-OERRoleManagementPolicy -Role 'Nope' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'RoleDefinitionNotFound'
        }
    }

    Context 'ByPolicyId' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @([PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P365D' }) } }
            }
        }
        It 'GETs the policy directly and converts its rules' {
            $p = Get-OERRoleManagementPolicy -PolicyId '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'
            $p.AllowPermanentEligibility | Should -BeTrue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Path -like '*/roleManagementPolicies/pol1`?api-version=2020-10-01'
            }
        }
        It 'writes an error when the ARM GET fails' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'arm down' }
            Get-OERRoleManagementPolicy -PolicyId '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' -ErrorVariable e -ErrorAction SilentlyContinue
            # Match the cmdlet-QUALIFIED ErrorId. The mock's own thrown record is auto-recorded into
            # -ErrorVariable at roughly a dozen call boundaries before the catch at
            # Get-OERRoleManagementPolicy.ps1:117-121 runs (13 records here; only the last carries
            # ',Get-OERRoleManagementPolicy'), so a bare count cannot fail.
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'arm down,Get-OERRoleManagementPolicy' }).Count |
                Should -Be 1
        }
    }

    Context 'ByCommonRoles' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            # Echo the role name back as the resolved id so we can assert per-role behavior.
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { $Role }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{
                    PolicyId = "/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/$RoleDefinitionId"
                    RoleName = $RoleDefinitionId; Scope = '/subscriptions/s1'
                    EffectiveRules = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' })
                }
            }
        }

        It 'reads exactly the five curated roles and returns five tagged objects' {
            $Policies = @(Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod')
            $Policies.Count | Should -Be 5
            $Policies[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            # Each curated display name is translated to an ARM id (the resolve step) before the policy read.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 5
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 5
        }

        It 'warns and continues when one role has no policy, returning the rest' {
            # Resolve-OERRoleDefinitionId is mocked to echo $Role, so $RoleDefinitionId is the role NAME
            # here; failing on 'Owner' drops exactly one. If the echo mock changed, all five would
            # succeed and the Count -eq 4 assertion would fail loudly (never a silent false pass).
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                if ($RoleDefinitionId -eq 'Owner') { throw 'No role management policy assignment was found.' }
                [PSCustomObject]@{ PolicyId = 'p'; RoleName = $RoleDefinitionId; Scope = '/subscriptions/s1'; EffectiveRules = @() }
            }
            $Policies = @(Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod' -WarningVariable Warned -WarningAction SilentlyContinue)
            $Policies.Count | Should -Be 4
            $Warned | Should -Not -BeNullOrEmpty
        }

        It 'surfaces a scope-resolver failure as InvalidScope (no per-role loop)' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw 'bad scope' }
            Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidScope'
        }
    }

    Context 'ByAllRolesAtScope' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope {
                @(
                    [PSCustomObject]@{ PolicyId = '/s1/pol-read'; RoleDefinitionId = '/s1/rd-read'; RoleName = 'Reader'; Scope = '/subscriptions/s1'; EffectiveRules = @([PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) }
                    [PSCustomObject]@{ PolicyId = '/s1/pol-own';  RoleDefinitionId = '/s1/rd-own';  RoleName = 'Owner';  Scope = '/subscriptions/s1'; EffectiveRules = @() }
                )
            }
        }

        It 'reads every role policy from a single scope list call' {
            $Policies = @(Get-OERRoleManagementPolicy -AllRolesAtScope -Subscription 'Prod')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope -Times 1
            $Policies.Count | Should -Be 2
            $Policies[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            $Policies[0].RoleName | Should -Be 'Reader'
            $Policies[0].ActivationMaxHours | Should -Be 8
        }

        It 'does not enumerate role definitions or do per-role policy lookups' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleDefinition { throw 'should not be called' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId { throw 'should not be called' }
            { Get-OERRoleManagementPolicy -AllRolesAtScope -Subscription 'Prod' } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 0
        }

        It 'surfaces a list-for-scope failure as RoleEnumerationFailed' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope { throw 'arm down' }
            Get-OERRoleManagementPolicy -AllRolesAtScope -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'RoleEnumerationFailed'
        }
    }

    Context 'Mutual exclusivity' {
        BeforeAll { Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { } }
        It 'rejects -Role together with -CommonRoles' {
            { Get-OERRoleManagementPolicy -Role 'Reader' -CommonRoles -Subscription 'Prod' } | Should -Throw
        }
        It 'rejects -CommonRoles together with -AllRolesAtScope' {
            { Get-OERRoleManagementPolicy -CommonRoles -AllRolesAtScope -Subscription 'Prod' } | Should -Throw
        }
    }

    It 'binds -ResourceGroup and -Subscription from the pipeline by property name' {
        $Cmd = Get-Command Get-OERRoleManagementPolicy
        $RgAttr = $Cmd.Parameters['ResourceGroup'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($RgAttr.ValueFromPipelineByPropertyName) | Should -Contain $true
        $SubAttr = $Cmd.Parameters['Subscription'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($SubAttr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Pipe a real object
        # and assert the resolver received the bound values.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
            [PSCustomObject]@{ PolicyId = '/subscriptions/sub-guid/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/sub-guid/resourceGroups/rg-net'; EffectiveRules = @() }
        }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $Rg | Get-OERRoleManagementPolicy -Role 'Reader'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    Context 'footgun regression: piped Subscription does not bind PolicyId alias' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000060' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{
                    PolicyId       = '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleManagementPolicies/pol1'
                    RoleName       = 'Reader'
                    Scope          = '/subscriptions/00000000-0000-0000-0000-000000000060'
                    EffectiveRules = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERRoleManagementPolicy { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }
        It 'pipes a Subscription object to -Role and binds Subscription via SubscriptionId -- NOT ByPolicyId' {
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/00000000-0000-0000-0000-000000000060'
                SubscriptionId = '00000000-0000-0000-0000-000000000060'
                DisplayName    = 'Prod'
                State          = 'Enabled'
            }
            $Sub.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
            $Sub | Get-OERRoleManagementPolicy -Role 'Reader'
            # The ByRole path calls Get-OERRoleManagementPolicyId (then ConvertTo-OERRoleManagementPolicy).
            # ByPolicyId calls Invoke-OERArmRequest directly instead.
            # Assert the ByRole resolver was invoked and the ByPolicyId direct GET was NOT.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 1 -ParameterFilter {
                $Scope -eq '/subscriptions/00000000-0000-0000-0000-000000000060'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }

    Context 'pipeline binding: ManagementGroup (audit CONS-rmp-managementgroup-not-pipeline-bound)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/providers/Microsoft.Management/managementGroups/mg-network' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { $Role }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{
                    PolicyId       = "/providers/Microsoft.Management/managementGroups/mg-network/providers/Microsoft.Authorization/roleManagementPolicies/$RoleDefinitionId"
                    RoleName       = $RoleDefinitionId
                    Scope          = '/providers/Microsoft.Management/managementGroups/mg-network'
                    EffectiveRules = @()
                }
            }
        }
        It 'binds -ManagementGroup from a piped ConvertTo-OERManagementGroup object (-CommonRoles)' {
            $Mg = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERManagementGroup -InputObject @{
                    id         = '/providers/Microsoft.Management/managementGroups/mg-network'
                    name       = 'mg-network'
                    properties = @{ displayName = 'Network MG'; tenantId = 'tid-1' }
                }
            }
            $e = $null
            $Mg | Get-OERRoleManagementPolicy -CommonRoles -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly -ParameterFilter {
                $ManagementGroup -eq 'mg-network'
            }
            @($e).Count | Should -Be 0
        }
    }

    Context 'piped role definition must not select ByPolicyId (T1NEW-roledefinition-id-collides-policyid-alias)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = 's'; rules = @() } }
            }
        }
        It 'never GETs the role definition ARM path as if it were a role management policy id (fixed by ConvertTo-OERRoleDefinition exposing ResourceId, not Id)' {
            # Before the fix, ConvertTo-OERRoleDefinition stored the ARM role definition path TWICE:
            # once as Id and once as RoleDefinitionId. -PolicyId carries [Alias('Id')] and
            # ValueFromPipelineByPropertyName in the Mandatory ByPolicyId set; -Role also carries
            # ValueFromPipelineByPropertyName (Alias RoleDefinitionId) in ByRole, but -Role is NOT
            # explicitly supplied here and neither is -Subscription/-ManagementGroup/-Scope, so ByRole
            # cannot bind without an explicit disambiguator and ByPolicyId wins instead -- empirically
            # confirmed to reproduce before the converter fix (a GET on the roleDefinitions path,
            # treated as a role management policy id). After the fix the object carries no Id
            # property at all, so ByPolicyId cannot be selected either -- and since -Role also cannot
            # bind without an explicit disambiguator, NEITHER parameter set can bind at all. That
            # surfaces as PowerShell's own pipeline-metadata-binding error (FullyQualifiedErrorId
            # 'InputObjectNotBound,Get-OERRoleManagementPolicy'), not a script-level WriteError, so it
            # is invisible to -ErrorVariable and must be captured via 2>&1 instead (empirically
            # confirmed: -ErrorVariable stays empty for this specific error class). -ErrorAction
            # Continue is pinned on the call: left unset, a GLOBAL Stop preference turns the binding
            # error into a thrown ParameterBindingException before 2>&1 sees it. Measured, a
            # test-local $ErrorActionPreference does not pin it and the per-call parameter does
            # (docs/development/rationale.md#bearer-scrub-tests).
            $RoleDef = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERRoleDefinition -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    name       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    properties = @{ roleName = 'Reader'; type = 'BuiltInRole' }
                }
            }
            $Streams = $RoleDef | Get-OERRoleManagementPolicy -ErrorAction Continue 2>&1
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Errs.Count | Should -Be 1
            $Errs[0].FullyQualifiedErrorId | Should -Be 'InputObjectNotBound,Get-OERRoleManagementPolicy'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly -ParameterFilter {
                $Path -match 'roleDefinitions.*api-version=2020-10-01'
            }
        }
    }

    Context 'piped subscription must not select ByPolicyId (B-subscription-mg-id-collides)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/33333333-3333-3333-3333-333333333333' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleDefinitions/rdOwner' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{
                    PolicyId       = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleManagementPolicies/pol1'
                    RoleName       = 'Owner'
                    Scope          = '/subscriptions/33333333-3333-3333-3333-333333333333'
                    EffectiveRules = @()
                }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }
        It 'resolves the policy by role and scope, not by treating the ARM path as a policy id' {
            # A Subscription object has no Id property, so -PolicyId (Alias Id) must stay unbound
            # and the ByRole parameter set (Resolve-OERScope + Get-OERRoleManagementPolicyId) must
            # be used instead of ByPolicyId (a direct Invoke-OERArmRequest GET on the ARM path).
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/33333333-3333-3333-3333-333333333333'
                SubscriptionId = '33333333-3333-3333-3333-333333333333'
                DisplayName    = 'Prod'
            }
            $Sub | Get-OERRoleManagementPolicy -Role 'Owner' | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }
}
