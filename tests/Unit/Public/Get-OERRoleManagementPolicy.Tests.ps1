BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

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
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No role management policy assignment was found.'),
                    'RolePolicyUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $RoleDefinitionId)
            }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PolicyNotFound'
        }
        It 'routes a scope resolver error as InvalidScope' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { throw 'bad scope' }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidScope'
        }
        It 'routes a role resolver error as RoleDefinitionNotFound' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('no role'),
                    'RoleDefinitionUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Role)
            }
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
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 5 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 5 -Exactly
        }

        It 'warns and continues when one role has no policy, returning the rest' {
            # Resolve-OERRoleDefinitionId is mocked to echo $Role, so $RoleDefinitionId is the role NAME
            # here; failing on 'Owner' drops exactly one. If the echo mock changed, all five would
            # succeed and the Count -eq 4 assertion would fail loudly (never a silent false pass).
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                if ($RoleDefinitionId -eq 'Owner') {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No role management policy assignment was found.'),
                        'RolePolicyUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $RoleDefinitionId)
                }
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
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope -Times 1 -Exactly
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

Describe 'Get-OERRoleManagementPolicy publishes a failed role or policy lookup as itself (Sprint 12 step 3, BL-157, BL-161c)' {
    # A lookup that SUCCEEDED and matched nothing is RoleDefinitionNotFound / PolicyNotFound (message, category
    # and target unchanged). Any other failure -- a 403, a paging refusal, an ambiguous name -- is not evidence
    # that the role or policy is missing and is published as the caught record itself. The helpers tell the two
    # apart by the internal ids RoleDefinitionUnresolved / RolePolicyUnresolved, which are never published.
    # Every call below stands in no try: a WriteError record reaches -ErrorVariable, a throw would fail the It.
    BeforeAll {
        $script:Forbidden = {
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization failed (403): the caller may not read role definitions.'),
                'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Reader')
        }
        $script:Published = {
            param($Err, [string]$Id)
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq "$Id,Get-OERRoleManagementPolicy" })
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { "/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/$Role" }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
            [PSCustomObject]@{ PolicyId = "/p/$RoleDefinitionId"; RoleName = 'Reader'; Scope = '/subscriptions/s1'; EffectiveRules = @() }
        }
    }

    Context 'ByRole' {
        It 'asks both helpers for the internal no-match record (-ThrowUnresolved)' {
            $null = Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId -Times 1 -Exactly -ParameterFilter { $ThrowUnresolved }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 1 -Exactly -ParameterFilter { $ThrowUnresolved }
        }

        It 'publishes a no-match role as RoleDefinitionNotFound with the same message, category and target' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("Role definition 'Nope' was not found at scope '/subscriptions/s1'."),
                    'RoleDefinitionUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Role)
            }
            Get-OERRoleManagementPolicy -Role 'Nope' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            $Hit = & $script:Published $Err 'RoleDefinitionNotFound'
            $Hit.Count | Should -Be 1
            $Hit[0].Exception.Message | Should -Be "Role definition 'Nope' was not found at scope '/subscriptions/s1'."
            $Hit[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Hit[0].TargetObject | Should -Be 'Nope'
            # The internal id is never published.
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERRoleManagementPolicy' -and $_.FullyQualifiedErrorId -like '*Unresolved*' }).Count | Should -Be 0
        }

        It 'publishes a role whose policy matches nothing as PolicyNotFound with the same message, category and target' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("No role management policy assignment was found for role definition '$RoleDefinitionId'."),
                    'RolePolicyUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $RoleDefinitionId)
            }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            $Hit = & $script:Published $Err 'PolicyNotFound'
            $Hit.Count | Should -Be 1
            $Hit[0].Exception.Message | Should -BeLike "No role management policy assignment was found for role definition '*Reader'."
            $Hit[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Hit[0].TargetObject | Should -BeLike '*/roleDefinitions/Reader'
        }

        It 'publishes a 403 on the role definition read as itself, never as RoleDefinitionNotFound, and reads no policy' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { throw (& $script:Forbidden) }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            $Hit = & $script:Published $Err 'AuthorizationFailed'
            $Hit.Count | Should -Be 1
            $Hit[0].Exception.Message | Should -Match 'may not read role definitions'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'RoleDefinitionNotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId -Times 0 -Exactly
        }

        It 'publishes a 403 on the policy list as itself, never as PolicyNotFound' {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId { throw (& $script:Forbidden) }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            (& $script:Published $Err 'AuthorizationFailed').Count | Should -Be 1
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'PolicyNotFound*' }).Count | Should -Be 0
        }

        It 'publishes <Id> from a failed policy list as itself' -ForEach @(
            @{ Id = 'ArmPagingIncomplete' }
            @{ Id = 'GraphPagingIncomplete' }
        ) {
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('The list could not be read to its end.'),
                    $Id, [System.Management.Automation.ErrorCategory]::InvalidResult, $null)
            }
            Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            (& $script:Published $Err $Id).Count | Should -Be 1
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'PolicyNotFound*' }).Count | Should -Be 0
        }

        It 'publishes an ambiguous role name as the resolver''s own AmbiguousName record with the candidates' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("Role name 'Dup' matches 2 role definitions (/a, /b)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Role)
            }
            Get-OERRoleManagementPolicy -Role 'Dup' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
            $Hit = & $script:Published $Err 'AmbiguousName'
            $Hit.Count | Should -Be 1
            $Hit[0].Exception.Message | Should -Match '/a, /b'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'RoleDefinitionNotFound*' }).Count | Should -Be 0
        }
    }

    Context 'ByCommonRoles' {
        It 'skips a missing role with a warning, writes a record for each failed one, and still returns the other roles' {
            # Reader reads; Contributor is refused (403 on its definition); Owner matches nothing (skipped with a
            # warning); User Access Administrator's policy list is refused; Role Based Access Control
            # Administrator reads. One record per failed role, one warning for the missing one.
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
                if ($Role -ceq 'Contributor') { throw (& $script:Forbidden) }
                if ($Role -ceq 'Owner') {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("Role definition 'Owner' was not found at scope '/subscriptions/s1'."),
                        'RoleDefinitionUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Role)
                }
                $Role
            }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                if ($RoleDefinitionId -ceq 'User Access Administrator') { throw (& $script:Forbidden) }
                [PSCustomObject]@{ PolicyId = "/p/$RoleDefinitionId"; RoleName = $RoleDefinitionId; Scope = '/subscriptions/s1'; EffectiveRules = @() }
            }
            $Policies = @(Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue -WarningVariable Warned -WarningAction SilentlyContinue)
            @($Policies | ForEach-Object { $_.RoleName }) | Should -Be @('Reader', 'Role Based Access Control Administrator')
            (& $script:Published $Err 'AuthorizationFailed').Count | Should -Be 2
            @($Warned | ForEach-Object { [string]$_.Message }) | Should -Be @("Skipping role 'Owner': Role definition 'Owner' was not found at scope '/subscriptions/s1'.")
        }

        It 'writes the failed role''s record after the objects read before it, so -ErrorAction Stop still gets them' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId {
                if ($Role -ceq 'Contributor') { throw (& $script:Forbidden) }
                $Role
            }
            $Got = [System.Collections.Generic.List[object]]::new()
            $Caught = $null
            try {
                Get-OERRoleManagementPolicy -CommonRoles -Subscription 'Prod' -ErrorAction Stop | ForEach-Object { $Got.Add($_) }
            } catch {
                $Caught = $PSItem
            }
            $Got.Count | Should -Be 1
            $Caught.FullyQualifiedErrorId | Should -Be 'AuthorizationFailed,Get-OERRoleManagementPolicy'
        }
    }
}

Describe 'Get-OERRoleManagementPolicy through the real lookup helpers (Sprint 12 step 3, BL-157, BL-161c)' {
    # Only the ARM transport and the policy lister are mocked, so the helpers' own -ThrowUnresolved records
    # reach the cmdlet's classification.
    BeforeAll {
        $script:RealPublished = {
            param($Err, [string]$Id)
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq "$Id,Get-OERRoleManagementPolicy" })
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope { @() }
    }

    It 'a role list that succeeded and held no match is RoleDefinitionNotFound' {
        Get-OERRoleManagementPolicy -Role 'Nope' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
        $Hit = & $script:RealPublished $Err 'RoleDefinitionNotFound'
        $Hit.Count | Should -Be 1
        $Hit[0].Exception.Message | Should -BeLike "Role definition 'Nope' was not found at scope '/subscriptions/s1'.*"
        $Hit[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Hit[0].TargetObject | Should -Be 'Nope'
    }

    It 'a policy list that succeeded and held no assignment for the role is PolicyNotFound' {
        Get-OERRoleManagementPolicy -Role '00000000-0000-0000-0000-000000000001' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
        $Hit = & $script:RealPublished $Err 'PolicyNotFound'
        $Hit.Count | Should -Be 1
        $Hit[0].Exception.Message | Should -BeLike "No role management policy assignment was found for role definition '*roleDefinitions/00000000-0000-0000-0000-000000000001' at scope '/subscriptions/s1'."
        $Hit[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }

    It 'a refused role definition list is the transport''s own record, never RoleDefinitionNotFound' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Authorization failed (403).'),
                'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'x')
        }
        Get-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
        (& $script:RealPublished $Err 'AuthorizationFailed').Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'RoleDefinitionNotFound*' }).Count | Should -Be 0
    }

    It 'a refused policy list is the transport''s own record, never PolicyNotFound' {
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyForScope {
            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Authorization failed (403).'),
                'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'x')
        }
        Get-OERRoleManagementPolicy -Role '00000000-0000-0000-0000-000000000001' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
        (& $script:RealPublished $Err 'AuthorizationFailed').Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'PolicyNotFound*' }).Count | Should -Be 0
    }

    It 'a role name two definitions share is the resolver''s own AmbiguousName record' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '/s/rd-a' }, [PSCustomObject]@{ id = '/s/rd-b' }) }
        }
        Get-OERRoleManagementPolicy -Role 'Dup' -Subscription 'Prod' -ErrorVariable Err -ErrorAction SilentlyContinue
        $Hit = & $script:RealPublished $Err 'AmbiguousName'
        $Hit.Count | Should -Be 1
        $Hit[0].Exception.Message | Should -Match '/s/rd-a, /s/rd-b'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'RoleDefinitionNotFound*' }).Count | Should -Be 0
    }
}
