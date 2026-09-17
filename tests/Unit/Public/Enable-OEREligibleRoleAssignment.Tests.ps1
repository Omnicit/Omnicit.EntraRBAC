BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

Describe 'Enable-OEREligibleRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    Context 'activation via pipeline (explicit RoleEligibilityScheduleId)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='bbbb0000-0000-0000-0000-000000000001'; principalType='User'; requestType='SelfActivate'; status='Provisioned'; requestorId='bbbb0000-0000-0000-0000-000000000001'; linkedRoleEligibilityScheduleId='elig1'; scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='AfterDuration'; duration='PT4H' } }; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'PUTs a SelfActivate request with the linked eligibility schedule id and given duration' {
            [PSCustomObject]@{ Id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId='bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Enable-OEREligibleRoleAssignment -Duration 'PT4H' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -like '/subscriptions/s1/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/*`?api-version=2020-10-01' -and
                $Body.properties.requestType -eq 'SelfActivate' -and
                $Body.properties.linkedRoleEligibilityScheduleId -eq '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1' -and
                $Body.properties.principalId -eq 'bbbb0000-0000-0000-0000-000000000001' -and
                $Body.properties.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }
        It 'defaults the activation duration to PT8H' {
            [PSCustomObject]@{ Id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId='bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Enable-OEREligibleRoleAssignment -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }
        It 'returns a tagged RoleScheduleRequest' {
            ([PSCustomObject]@{ Id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId='bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Enable-OEREligibleRoleAssignment -Confirm:$false).PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleScheduleRequest'
        }
        It 'honors -WhatIf (no PUT)' {
            [PSCustomObject]@{ Id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId='bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Enable-OEREligibleRoleAssignment -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'converts -DurationHours to an AfterDuration ISO hour duration' {
            [PSCustomObject]@{ Id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId='bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope='/subscriptions/s1' } |
                Enable-OEREligibleRoleAssignment -DurationHours 4 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Body.properties.scheduleInfo.expiration.type -eq 'AfterDuration' -and
                $Body.properties.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }
    }

    Context 'activation via fallback lookup (no RoleEligibilityScheduleId)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000001'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='bbbb0000-0000-0000-0000-000000000001'; principalType='User'; requestType='SelfActivate'; status='Provisioned'; requestorId='bbbb0000-0000-0000-0000-000000000001'; linkedRoleEligibilityScheduleId='x'; scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='AfterDuration'; duration='PT8H' } }; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
                [PSCustomObject]@{ value = @([PSCustomObject]@{ id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'; properties=[PSCustomObject]@{ roleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' } }) }
            }
        }
        It 'looks up the eligibility and uses its id as the linked id' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'me@contoso.com' -Subscription 'Prod' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.properties.linkedRoleEligibilityScheduleId -eq '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'
            }
        }
    }

    Context 'fallback finds no matching eligibility' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000001'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rdX' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } { [PSCustomObject]@{ value = @() } }
        }
        It 'errors with EligibilityNotFound' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'me@contoso.com' -Subscription 'Prod' -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'EligibilityNotFound'
        }
    }

    Context 'validation' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='bbbb0000-0000-0000-0000-000000000001'; principalType='User'; requestType='SelfActivate'; status='Provisioned'; requestorId='bbbb0000-0000-0000-0000-000000000001'; linkedRoleEligibilityScheduleId='elig1'; scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='AfterDuration'; duration='PT8H' } }; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }
            }
        }
        It 'errors with NoPrincipal when no principal is supplied' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId 'elig1' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
        }
        It 'errors with AmbiguousPrincipal when two principals are supplied' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId 'elig1' -User 'a' -Group 'b' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousPrincipal'
        }
        It 'errors with InvalidSchedule when both -Duration and -EndDateTime are supplied' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId 'elig1' -PrincipalId 'bbbb0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Duration 'P365D' -EndDateTime ([datetime]'2030-01-01') -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'InvalidSchedule'
        }
        It 'errors with AmbiguousDuration when both -Duration and -DurationHours are supplied' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId 'elig1' -PrincipalId 'bbbb0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Duration 'PT8H' -DurationHours 4 -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousDuration'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'errors with InvalidPrincipalId when -PrincipalId is not a GUID' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId 'elig1' -PrincipalId 'anna@contoso.com' -Scope '/subscriptions/s1' -ErrorVariable e -ErrorAction SilentlyContinue -Confirm:$false
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
        It 'accepts a GUID -PrincipalId and proceeds to the ARM call' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -RoleEligibilityScheduleId '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Scope '/subscriptions/s1' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'footgun regression: piped Subscription binds SubscriptionId scope -- NOT RoleEligibilityScheduleId alias' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000060' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000001'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                    id         = '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'
                    properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/roleDefinitions/rd1' }
                }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                    scope = '/subscriptions/00000000-0000-0000-0000-000000000060'
                    roleDefinitionId = 'rd1'; principalId = 'bbbb0000-0000-0000-0000-000000000001'
                    principalType = 'User'; requestType = 'SelfActivate'; status = 'Provisioned'
                    requestorId = 'bbbb0000-0000-0000-0000-000000000001'
                    linkedRoleEligibilityScheduleId = '/subscriptions/00000000-0000-0000-0000-000000000060/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'
                    scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'PT8H' } }
                    expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'User' }; roleDefinition = [PSCustomObject]@{ displayName = 'Contributor' }; scope = [PSCustomObject]@{ displayName = 'Prod' } }
                } }
            }
        }
        It 'pipes a Subscription object binding SubscriptionId to scope -- not ARM path as RoleEligibilityScheduleId' {
            # A Subscription object carries ResourceId (ARM path) and SubscriptionId (GUID).
            # Before the fix, Id = ARM-path would bind to -RoleEligibilityScheduleId via its Id alias.
            # After the fix, ResourceId does not bind any parameter alias, and SubscriptionId binds
            # -Subscription (alias SubscriptionId), which is then resolved to a proper ARM scope.
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/00000000-0000-0000-0000-000000000060'
                SubscriptionId = '00000000-0000-0000-0000-000000000060'
                DisplayName    = 'Prod'
                State          = 'Enabled'
            }
            $Sub.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
            $Sub | Enable-OEREligibleRoleAssignment -Role 'Contributor' -User 'me@contoso.com' -Confirm:$false
            # Scope was resolved from SubscriptionId (not passed as a schedule id).
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $Subscription -eq '00000000-0000-0000-0000-000000000060'
            }
            # The eligibility lookup used the resolved scope -- confirming ByRole fallback path, not direct schedule id.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'resource-level scope forwarding' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
                [PSCustomObject]@{ value = @([PSCustomObject]@{ id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'; properties=[PSCustomObject]@{ roleDefinitionId='/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' } }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id='req1'; name='req1'; properties=[PSCustomObject]@{ scope='/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stg1'; roleDefinitionId='rd1'; principalId='11111111-1111-1111-1111-111111111111'; principalType='User'; requestType='SelfActivate'; status='Provisioned'; requestorId='11111111-1111-1111-1111-111111111111'; linkedRoleEligibilityScheduleId='x'; scheduleInfo=[PSCustomObject]@{ startDateTime='t'; expiration=[PSCustomObject]@{ type='AfterDuration'; duration='PT8H' } }; expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Test'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='stg1'} } } }
            }
        }
        It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
            Enable-OEREligibleRoleAssignment -Role 'Reader' -PrincipalId '11111111-1111-1111-1111-111111111111' -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1' -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
                $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
            }
        }
    }

    Context 'principal guard (shared Resolve-OERPrincipalOrId)' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        }

        It 'rejects a non-GUID -PrincipalId with InvalidPrincipalId and does not call ARM' {
            $Err = $null
            Enable-OEREligibleRoleAssignment -PrincipalId 'anna@contoso.com' -Role 'Reader' `
                -Subscription 'aaaa0000-0000-0000-0000-000000000001' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            Should -Invoke Invoke-OERArmRequest -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'reports NoPrincipal with the pipe hint when no principal is supplied' {
            $Err = $null
            Enable-OEREligibleRoleAssignment -Role 'Reader' `
                -Subscription 'aaaa0000-0000-0000-0000-000000000001' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
            $Err[0].Exception.Message | Should -BeLike '*or pipe from Get-OEREligibleRoleAssignment*'
        }

        It 'reports AmbiguousPrincipal when -User and -Group are both supplied' {
            $Err = $null
            Enable-OEREligibleRoleAssignment -User 'anna@contoso.com' -Group 'Sales Team' -Role 'Reader' `
                -Subscription 'aaaa0000-0000-0000-0000-000000000001' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -Confirm:$false
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
        }
    }

    Context 'piped subscription must not mis-bind a schedule id (B-subscription-mg-id-collides)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/33333333-3333-3333-3333-333333333333' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' } }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleDefinitions/rdReader' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                        id         = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/RoleEligibilitySchedules/schReal'
                        properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleDefinitions/rdReader' }
                    }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{
                        scope                            = '/subscriptions/33333333-3333-3333-3333-333333333333'
                        roleDefinitionId                 = 'rdReader'; principalId = 'bbbb0000-0000-0000-0000-000000000002'
                        principalType                    = 'User'; requestType = 'SelfActivate'; status = 'Provisioned'
                        requestorId                      = 'bbbb0000-0000-0000-0000-000000000002'
                        linkedRoleEligibilityScheduleId  = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/RoleEligibilitySchedules/schReal'
                        scheduleInfo                     = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'PT8H' } }
                        expandedProperties               = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } }
                    } }
            }
        }
        It 'does not set linkedRoleEligibilityScheduleId from the piped subscription ResourceId' {
            # A Subscription object has no Id or RoleEligibilityScheduleId property, so
            # -RoleEligibilityScheduleId (Alias Id) must stay unbound and the eligibility must be
            # located via the ByRole fallback lookup -- not by treating the piped ResourceId (an ARM
            # path, not a schedule id) as the linked eligibility schedule id.
            $Sub = [PSCustomObject]@{
                ResourceId     = '/subscriptions/33333333-3333-3333-3333-333333333333'
                SubscriptionId = '33333333-3333-3333-3333-333333333333'
                DisplayName    = 'Prod'
            }
            $Sub | Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'anna.berg@contoso.com' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.properties.linkedRoleEligibilityScheduleId -ne '/subscriptions/33333333-3333-3333-3333-333333333333'
            }
        }
    }

    Context 'piped role definition must not mis-bind a schedule id (T1NEW-roledefinition-id-collides-policyid-alias)' {
        BeforeAll {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/00000000-0000-0000-0000-000000000000' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
                [PSCustomObject]@{ value = @([PSCustomObject]@{
                        id         = '/subscriptions/s/providers/Microsoft.Authorization/RoleEligibilitySchedules/schReal'
                        properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' }
                    }) }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
                [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{} }
            }
        }
        It 'does not set linkedRoleEligibilityScheduleId from the piped role definition Id (fixed by ConvertTo-OERRoleDefinition exposing ResourceId, not Id)' {
            # Before the fix, ConvertTo-OERRoleDefinition stored the ARM role definition path TWICE:
            # once as Id and once as RoleDefinitionId. -RoleEligibilityScheduleId carries [Alias('Id')]
            # and is consumed UNGUARDED (source/Public/Enable-OEREligibleRoleAssignment.ps1 -- "if
            # ($RoleEligibilityScheduleId) { $LinkedId = $RoleEligibilityScheduleId }"), so the piped
            # role definition's Id (a roleDefinitions path) would be sent straight through as
            # linkedRoleEligibilityScheduleId instead of triggering the ByRole fallback lookup that
            # finds the REAL roleEligibilitySchedules id. Empirically confirmed to reproduce before the
            # converter fix: Times 1 -Exactly with $Body.properties.linkedRoleEligibilityScheduleId
            # matching a roleDefinitions path.
            $RoleDef = InModuleScope Omnicit.EntraRBAC {
                ConvertTo-OERRoleDefinition -InputObject @{
                    id         = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    name       = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    properties = @{ roleName = 'Reader'; type = 'BuiltInRole' }
                }
            }
            $RoleDef | Enable-OEREligibleRoleAssignment -PrincipalId '33333333-3333-3333-3333-333333333333' `
                -Subscription '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.linkedRoleEligibilityScheduleId -match 'roleDefinitions'
            }
            # Positive half: a not-X-only assertion would also pass if the cmdlet simply stopped
            # issuing a PUT at all. Prove the pipe actually succeeded via the ByRole fallback lookup,
            # landing the REAL roleEligibilitySchedules id (schReal) on the PUT body.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.properties.linkedRoleEligibilityScheduleId -eq '/subscriptions/s/providers/Microsoft.Authorization/RoleEligibilitySchedules/schReal'
            }
        }
    }
}

Describe 'Enable-OEREligibleRoleAssignment verbose output' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000001'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERRoleDefinitionId { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
            [PSCustomObject]@{ id = 'req1'; name = 'req1'; properties = [PSCustomObject]@{ scope = '/subscriptions/s1'; roleDefinitionId = 'rd1'; principalId = 'bbbb0000-0000-0000-0000-000000000001'; principalType = 'User'; requestType = 'SelfActivate'; status = 'Provisioned'; requestorId = 'bbbb0000-0000-0000-0000-000000000001'; linkedRoleEligibilityScheduleId = 'x'; scheduleInfo = [PSCustomObject]@{ startDateTime = 't'; expiration = [PSCustomObject]@{ type = 'AfterDuration'; duration = 'PT8H' } }; expandedProperties = [PSCustomObject]@{ principal = [PSCustomObject]@{ displayName = 'Anna' }; roleDefinition = [PSCustomObject]@{ displayName = 'Reader' }; scope = [PSCustomObject]@{ displayName = 'Prod' } } } }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Path -like '*roleEligibilitySchedules*' } {
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/schA'; properties = [PSCustomObject]@{ roleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' } }) }
        }
    }

    It 'reports the resolved scope, role, principal and looked-up eligibility schedule id under -Verbose' {
        $Verbose = Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'me@contoso.com' -Subscription 'Prod' -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match '\[Enable-OEREligibleRoleAssignment\] Target scope:'
        $Text | Should -Match "\[Enable-OEREligibleRoleAssignment\] Resolved role 'Reader' to "
        $Text | Should -Match '\[Enable-OEREligibleRoleAssignment\] Resolved principal to '
        $Text | Should -Match "\[Enable-OEREligibleRoleAssignment\] Resolved eligibility schedule id: '"
    }

    It 'does not report a looked-up schedule id when -RoleEligibilityScheduleId is supplied directly' {
        $Verbose = [PSCustomObject]@{ Id = '/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; PrincipalId = 'bbbb0000-0000-0000-0000-000000000001'; RoleDefinitionId = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1'; Scope = '/subscriptions/s1' } |
            Enable-OEREligibleRoleAssignment -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Not -Match 'Resolved eligibility schedule id:'
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'me@contoso.com' -Subscription 'Prod' -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'does not write a bearer token or a request body to the verbose stream' {
        # NOTE: a plain '(?i)authorization' check would false-positive here: the resolved role
        # definition id and eligibility schedule id legitimately contain the
        # 'Microsoft.Authorization' resource-provider namespace, which is not a header or token
        # leak. Assert against the actual header/token shape instead ('Authorization:' with a
        # colon, or the word 'bearer').
        $Text = (Enable-OEREligibleRoleAssignment -Role 'Reader' -User 'me@contoso.com' -Subscription 'Prod' -Confirm:$false -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message -join "`n"
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization\s*:'
    }
}

Describe 'Enable-OEREligibleRoleAssignment operator-facing principal label' {
    # This cmdlet emits no Write-Warning (it is ConfirmImpact = 'Medium'), so the ShouldProcess
    # TARGET text is the only place the label is shown. Both -WhatIf and the confirmation prompt
    # render that text straight to the PSHost, where no stream redirection can reach it -- verified
    # in this harness: "Cmdlet -WhatIf 6>&1 4>&1 5>&1 3>&1 | Out-String" captures an empty string
    # while the "What if:" line still prints. So run the cmdlet in the answering runspace (see
    # tests/Unit/TestHelpers/OERConfirmHost.ps1), whose host records the prompt text it answers.
    # The scriptblock is transported as text and cannot close over test variables, so each case
    # installs its own fakes. Answering No keeps the ARM mutation unreached either way.

    It 'names the group the operator typed in the confirmation target, not the resolved GUID' {
        $Result = Invoke-OERWithConfirmAnswer -Answer '&No' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
                Set-Item -Path function:script:Resolve-OERPrincipal -Value { [PSCustomObject]@{ PrincipalId = '99999999-9999-9999-9999-999999999999'; PrincipalType = 'Group' } }
                Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
                Set-Item -Path function:script:Invoke-OERArmRequest -Value { }
                Set-Item -Path function:script:ConvertTo-OERRoleScheduleRequest -Value { }
            }
            Enable-OEREligibleRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' -RoleEligibilityScheduleId 'elig1' -Group 'RoleSec-Finance' -Confirm | Out-Null
        }
        @($Result.Errors).Count | Should -Be 0
        $Result.Prompts.Count | Should -Be 1
        $Result.Prompts[0] | Should -Match 'RoleSec-Finance'
        $Result.Prompts[0] | Should -Not -Match '99999999-9999'
    }

    It 'names the GUID, not the ignored friendly value, when BOTH are supplied' {
        # -PrincipalId and -Group share a parameter set and Resolve-OERPrincipalOrId lets
        # -PrincipalId WIN, warning that the friendly value is ignored. Naming the ignored value
        # in the confirmation target would ask the operator to approve an activation for a
        # principal that is not the one about to be touched.
        $Result = Invoke-OERWithConfirmAnswer -Answer '&No' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
                Set-Item -Path function:script:Resolve-OERPrincipal -Value { throw '-PrincipalId wins, so no friendly lookup should happen' }
                Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
                Set-Item -Path function:script:Invoke-OERArmRequest -Value { }
                Set-Item -Path function:script:ConvertTo-OERRoleScheduleRequest -Value { }
            }
            Enable-OEREligibleRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' -RoleEligibilityScheduleId 'elig1' -PrincipalId '99999999-9999-9999-9999-999999999999' -Group 'RoleSec-Finance' -Confirm | Out-Null
        }
        @($Result.Errors).Count | Should -Be 0
        $Result.Prompts.Count | Should -Be 1
        $Result.Prompts[0] | Should -Match '99999999-9999-9999-9999-999999999999'
        $Result.Prompts[0] | Should -Not -Match 'RoleSec-Finance'
        # The operator still gets the precedence signal alongside the corrected target.
        @($Result.Warnings | Where-Object { $_ -match '-PrincipalId takes precedence' -and $_ -match '-Group' }).Count |
            Should -Be 1
    }

    It 'falls back to the GUID in the confirmation target when -PrincipalId was used' {
        $Result = Invoke-OERWithConfirmAnswer -Answer '&No' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERScope -Value { '/subscriptions/s1' }
                Set-Item -Path function:script:Resolve-OERPrincipal -Value { throw 'no friendly principal was supplied, so nothing should be resolved' }
                Set-Item -Path function:script:Resolve-OERRoleDefinitionId -Value { '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' }
                Set-Item -Path function:script:Invoke-OERArmRequest -Value { }
                Set-Item -Path function:script:ConvertTo-OERRoleScheduleRequest -Value { }
            }
            Enable-OEREligibleRoleAssignment -Role 'Reader' -Scope '/subscriptions/s1' -RoleEligibilityScheduleId 'elig1' -PrincipalId '99999999-9999-9999-9999-999999999999' -Confirm | Out-Null
        }
        @($Result.Errors).Count | Should -Be 0
        $Result.Prompts.Count | Should -Be 1
        $Result.Prompts[0] | Should -Match '99999999-9999-9999-9999-999999999999'
    }
}
