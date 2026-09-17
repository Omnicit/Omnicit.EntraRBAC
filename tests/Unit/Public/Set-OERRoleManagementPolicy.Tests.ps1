BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Set-OERRoleManagementPolicy' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'ByRole update' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/s1'; EffectiveRules = @() }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                ) } }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P90D' }
                ) } }
            }
        }

        It 'GETs then PATCHes the rule with the right delta as a FLAT rules array' {
            Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Path -like '*/roleManagementPolicies/pol1`?api-version=2020-10-01' -and
                @($Body.properties.rules).Count -eq 1 -and
                # Regression guard: each element must be a rule object, NOT a nested array. The old
                # double-nesting bug ([[...]]) still satisfied the .id/.isExpirationRequired checks
                # below via member enumeration, so this -is check is what actually catches it.
                ($Body.properties.rules[0] -is [System.Management.Automation.PSCustomObject]) -and
                $Body.properties.rules[0].id -eq 'Expiration_Admin_Eligibility' -and
                $Body.properties.rules[0].isExpirationRequired -eq $false -and
                $Body.properties.rules[0].target.level -eq 'Eligibility'
            }
        }
        It 'returns a tagged policy with ChangedRuleIds' {
            $p = Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false
            $p.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicy'
            $p.ChangedRuleIds | Should -Contain 'Expiration_Admin_Eligibility'
        }
        It 'honors -WhatIf (GET allowed, no PATCH)' {
            Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        }
        It 'binds PolicyId from the pipeline (Get | Set round-trip)' {
            [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' } |
                Set-OERRoleManagementPolicy -AllowPermanentEligibility $true -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Path -like '*/roleManagementPolicies/pol1`?api-version=2020-10-01'
            }
        }
    }

    Context 'full read-modify-write (sends every rule, changes one)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/s1'; EffectiveRules = @() }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                    [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'PT8H'; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
                ) } }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @() } }
            }
        }
        It 'PATCHes ALL current rules (changed + untouched), reporting only the changed id' {
            $p = Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false
            $p.ChangedRuleIds | Should -Be 'Expiration_Admin_Eligibility'   # only the one that changed
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                @($Body.properties.rules).Count -eq 2 -and                  # full set, not just the change
                (($Body.properties.rules | Where-Object id -eq 'Expiration_Admin_Eligibility').isExpirationRequired -eq $false) -and
                (($Body.properties.rules | Where-Object id -eq 'Expiration_EndUser_Assignment').maximumDuration -eq 'PT8H')   # untouched rule passed through
            }
        }
    }

    Context 'value-aware NoChange (roundtrip PR task 12)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $false; maximumDuration = 'P365D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                ) } }
            }
            # Only reached if the guard under test regresses (PATCH gets called anyway); returns a
            # well-formed body so that failure surfaces as a clean "PATCH was invoked" assertion
            # rather than a downstream null-binding exception masking the real regression.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P365D' }
                ) } }
            }
        }

        It 'returns NoChange without an ARM write when every supplied value already matches' {
            # Cmdlet-qualified: a bare-code match would pass even with the WriteError deleted, because
            # the engine re-records a thrown record into -ErrorVariable at every call boundary crossed.
            Set-OERRoleManagementPolicy -PolicyId '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol1' `
                -AllowPermanentEligibility $true -EligibleDuration 365 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoChange,Set-OERRoleManagementPolicy' }).Count | Should -Be 1
        }
    }

    Context 'validation' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }
        It 'errors with NothingToUpdate when no rule parameter is supplied' {
            Set-OERRoleManagementPolicy -PolicyId '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol1' -ErrorVariable e -ErrorAction SilentlyContinue
            # Cmdlet-qualified: a bare-code match passes even with the WriteError deleted, because the
            # engine re-records a thrown record into -ErrorVariable at every call boundary it crosses.
            @($e | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERRoleManagementPolicy' }).Count | Should -Be 1
        }
        It 'errors with InvalidAuthenticationContext on a malformed claim value' {
            Set-OERRoleManagementPolicy -PolicyId '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol1' -AuthenticationContextId 'bad' -ErrorVariable e -ErrorAction SilentlyContinue
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidAuthenticationContext'
        }
    }

    Context 'pipeline binding: Subscription object binds SubscriptionId to scope' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000060' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{ PolicyId = '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000060'; EffectiveRules = @() }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/00000000-0000-0000-0000-000000000060'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                ) } }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/00000000-0000-0000-0000-000000000060'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P90D' }
                ) } }
            }
        }
        It 'pipes a Subscription object and binds SubscriptionId to Resolve-OERScope' {
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/00000000-0000-0000-0000-000000000060'
                SubscriptionId = '00000000-0000-0000-0000-000000000060'
                DisplayName    = 'Prod'
                State          = 'Enabled'
            }
            $Sub.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
            $Sub | Set-OERRoleManagementPolicy -Role 'Reader' -AllowPermanentEligibility $true -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $Subscription -eq '00000000-0000-0000-0000-000000000060'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'never GETs the bare subscription ARM path as if it were a policy id (B-subscription-mg-id-collides)' {
            # -PolicyId carries Alias('Id') + ValueFromPipelineByPropertyName (ByPolicyId set). If the
            # piped Subscription exposed a bare Id (its ARM resource path) instead of ResourceId, that
            # value would bind to -PolicyId and the cmdlet would skip scope/role resolution entirely,
            # going straight to `Invoke-OERArmRequest -Path "$PolicyId?api-version=2020-10-01"` -- i.e.
            # a GET on the raw subscription resource path, not a roleManagementPolicies path. Read
            # source/Public/Set-OERRoleManagementPolicy.ps1:227-259: that is exactly the ARM path a
            # mis-bound Id would produce. The converter now emits ResourceId instead of a bare Id, so
            # this must never happen.
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/00000000-0000-0000-0000-000000000060'
                SubscriptionId = '00000000-0000-0000-0000-000000000060'
                DisplayName    = 'Prod'
                State          = 'Enabled'
            }
            $Sub.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
            $Sub | Set-OERRoleManagementPolicy -Role 'Reader' -AllowPermanentEligibility $true -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter {
                $Path -eq '/subscriptions/00000000-0000-0000-0000-000000000060?api-version=2020-10-01'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Path -like '*/roleManagementPolicies/pol1`?api-version=2020-10-01'
            }
        }
    }

    Context 'pipeline binding: ManagementGroup (audit CONS-rmp-managementgroup-not-pipeline-bound)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/providers/Microsoft.Management/managementGroups/mg-network' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/providers/Microsoft.Management/managementGroups/mg-network/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
                [PSCustomObject]@{ PolicyId = '/providers/Microsoft.Management/managementGroups/mg-network/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/providers/Microsoft.Management/managementGroups/mg-network'; EffectiveRules = @() }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/providers/Microsoft.Management/managementGroups/mg-network'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_EndUser_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'PT2H'; target = [PSCustomObject]@{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' } }
                ) } }
            }
        }
        It 'binds -ManagementGroup from a piped ConvertTo-OERManagementGroup object (-WhatIf)' {
            $Mg = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERManagementGroup -InputObject @{
                    id         = '/providers/Microsoft.Management/managementGroups/mg-network'
                    name       = 'mg-network'
                    properties = @{ displayName = 'Network MG'; tenantId = 'tid-1' }
                }
            }
            $e = $null
            $Mg | Set-OERRoleManagementPolicy -Role 'Reader' -ActivationMaxHours 4 -WhatIf -ErrorVariable e -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly -ParameterFilter {
                $ManagementGroup -eq 'mg-network'
            }
            @($e).Count | Should -Be 0
        }
    }

    Context 'duration vocabulary (audit PR6)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                    [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                    [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Assignment' } }
                ) } }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
                [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @($Body.properties.rules) } }
            }
        }

        It 'accepts the historical bare day count on -EligibleDuration' {
            Set-OERRoleManagementPolicy -PolicyId 'pol-1' -EligibleDuration 365 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration -eq 'P365D')
            }
        }

        It 'accepts the ISO string that Get-OERRoleManagementPolicy emits on -EligibleDuration' {
            Set-OERRoleManagementPolicy -PolicyId 'pol-1' -EligibleDuration 'P365D' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration -eq 'P365D')
            }
        }

        It 'binds the -EligibleDurationDays alias' {
            # Deliberately NOT 90: this context's GET mock already returns 'P90D' on
            # Expiration_Admin_Eligibility, so binding -EligibleDurationDays 90 would be a genuine
            # no-op under the Task 12 value-aware comparison and never reach PATCH at all (that was
            # the original value here, asserting a touched-but-unchanged id). Use a value that
            # actually differs from the GET mock's baseline so this stays a real change.
            Set-OERRoleManagementPolicy -PolicyId 'pol-1' -EligibleDurationDays 120 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration -eq 'P120D')
            }
        }

        It 'binds the -ActiveDurationDays alias' {
            Set-OERRoleManagementPolicy -PolicyId 'pol-1' -ActiveDurationDays 30 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' }).maximumDuration -eq 'P30D')
            }
        }

        It 'round-trips a policy object read by Get-OERRoleManagementPolicy' {
            $Read = [PSCustomObject]@{ PolicyId = 'pol-1'; EligibleDuration = 'P180D'; ActiveDuration = 'P30D' }
            Set-OERRoleManagementPolicy -PolicyId $Read.PolicyId -EligibleDuration $Read.EligibleDuration `
                -ActiveDuration $Read.ActiveDuration -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration -eq 'P180D') -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' }).maximumDuration -eq 'P30D')
            }
        }

        It 'emits a non-terminating InvalidDuration error for a value that is neither a count nor ISO' {
            # NOTE: asserting against $Err[0] specifically is not reliable here: PowerShell's engine
            # records a caught exception into -ErrorVariable at the moment it is thrown (before the
            # catch runs), independent of the module's own $Error.Remove() hygiene, which is a
            # different collection. Resolve-OERDurationInput's `throw` for the bad value therefore
            # leaks a preceding entry ahead of the InvalidDuration error this cmdlet writes -- this
            # reproduces even for a bare `throw` inside a plain (non-CmdletBinding) helper function,
            # so it is a PowerShell quirk, not a bug in this cmdlet. Assert presence, not position.
            Set-OERRoleManagementPolicy -PolicyId 'pol-1' -EligibleDuration 'banana' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err | Should -Not -BeNullOrEmpty
            $Err | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidDuration*' } | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'does not bind a duration from the pipeline (a piped policy must not silently re-apply it)' {
            (Get-Command Set-OERRoleManagementPolicy).Parameters['EligibleDuration'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ValueFromPipelineByPropertyName } | Should -Not -Contain $true
        }

        It 'ignores EligibleDuration/ActiveDuration properties on a piped policy object (real-invocation guard)' {
            # Reinforces the attribute-reflection test above with an actual invocation: pipe an
            # object shaped like a Get-OERRoleManagementPolicy read (PolicyId binds by property
            # name; EligibleDuration/ActiveDuration deliberately do not) and confirm the untouched
            # maximumDuration from the GET response ('P90D') survives into the PATCH body instead
            # of being silently overwritten by the piped EligibleDuration/ActiveDuration values.
            $Read = [PSCustomObject]@{ PolicyId = 'pol-1'; EligibleDuration = 'P999D'; ActiveDuration = 'P999D' }
            $Read | Set-OERRoleManagementPolicy -AllowPermanentEligibility $true -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).isExpirationRequired -eq $false) -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Eligibility' }).maximumDuration -eq 'P90D') -and
                (($Body.properties.rules | Where-Object { $_.id -eq 'Expiration_Admin_Assignment' }).maximumDuration -eq 'P90D')
            }
        }
    }
}

Describe 'Set-OERRoleManagementPolicy verbose output' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERRoleManagementPolicyId {
            [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1'; RoleName = 'Reader'; Scope = '/subscriptions/s1'; EffectiveRules = @() }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
            [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                    ) }
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } {
            [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P90D' }
                    ) }
            }
        }
    }

    It 'reports the resolved scope, role and policy id under -Verbose (ByRole)' {
        $Verbose = Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[Set-OERRoleManagementPolicy\] Target scope:'
        $Text | Should -Match "\[Set-OERRoleManagementPolicy\] Resolved role 'Reader' to "
        $Text | Should -Match "\[Set-OERRoleManagementPolicy\] Resolved policy id: '"
    }

    It 'does not report a looked-up scope/role/policy id when -PolicyId is supplied directly' {
        $Verbose = [PSCustomObject]@{ PolicyId = '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' } |
            Set-OERRoleManagementPolicy -AllowPermanentEligibility $true -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Not -Match 'Target scope:'
        $Text | Should -Not -Match 'Resolved policy id:'
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved ARM
        # policy id legitimately contains the 'Microsoft.Authorization' resource-provider
        # namespace (e.g. '.../providers/Microsoft.Authorization/roleManagementPolicies/pol1'),
        # which is not a header or token leak. Assert against the actual header/token shape
        # instead ('Authorization:' with a colon, or the word 'bearer').
        $Text = (Set-OERRoleManagementPolicy -Role 'Reader' -Subscription 'Prod' -AllowPermanentEligibility $true -Confirm:$false -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'Set-OERRoleManagementPolicy bearer-token hygiene' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'scrubs the bearer-hygiene record when the ARM PATCH fails' {
        # CLAUDE.md SECURITY rule 6. This cmdlet has NINE scrub sites; this It drives the WRITE one --
        # the transport catch at source/Public/Set-OERRoleManagementPolicy.ps1:290. -PolicyId selects
        # the ByPolicyId parameter set, which skips Resolve-OERScope, Resolve-OERRoleDefinitionId and
        # Get-OERRoleManagementPolicyId entirely, so none of the resolver catches can fire; the GET
        # behaviour returns a rule that AllowPermanentEligibility genuinely changes, so the run reaches
        # the PATCH. The verbose-stream bearer check further up this file is NOT a scrub proof -- it
        # would still pass with the Remove-OERErrorRecord line deleted.
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
            [PSCustomObject]@{ properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; rules = @(
                        [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; ruleType = 'RoleManagementPolicyExpirationRule'; isExpirationRequired = $true; maximumDuration = 'P90D'; target = [PSCustomObject]@{ caller = 'Admin'; operations = @('All'); level = 'Eligibility' } }
                    ) }
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PATCH' } { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Set-OERRoleManagementPolicy -PolicyId '/subscriptions/s1/providers/Microsoft.Authorization/roleManagementPolicies/pol1' -AllowPermanentEligibility $true -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
