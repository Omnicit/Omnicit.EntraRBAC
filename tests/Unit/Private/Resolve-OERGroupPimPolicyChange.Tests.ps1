BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERGroupPimPolicyChange' {
    It 'reports no change when every declared field already matches current' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                activationMaxHours        = 8
                authenticationContextId   = 'c1'
                activationEnablement      = @('Justification')
                allowPermanentEligibility = $false
                eligibleDurationDays      = 365
                allowPermanentActive      = $false
                activeDurationDays        = 180
                activeEnablement          = @('MultiFactorAuthentication', 'Justification')
                notifications             = [pscustomobject]@{
                    eligibleAlert = @('admin@contoso.com'); activeAlert = @('admin@contoso.com'); activationAlert = @('secops@contoso.com')
                }
            }
            $Current = [pscustomobject]@{
                ActivationMaxHours        = 8
                AuthenticationContextId   = 'c1'
                ActivationEnabledRules    = @('Justification')
                AllowPermanentEligibility = $false
                EligibleDurationDays      = 365
                AllowPermanentActive      = $false
                ActiveDurationDays        = 180
                ActiveEnabledRules        = @('Justification', 'MultiFactorAuthentication')  # order differs on purpose
                Notifications             = [pscustomobject]@{
                    EligibleAlert = @('admin@contoso.com'); ActiveAlert = @('admin@contoso.com'); ActivationAlert = @('secops@contoso.com')
                }
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -Be $false
            $R.SetParams            | Should -BeOfType [hashtable]
            $R.SetParams.Keys.Count | Should -Be 0
        }
    }

    It 'detects an activationMaxHours change and emits only that param' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ activationMaxHours = 4 }
            $Current  = [pscustomobject]@{ ActivationMaxHours = 8 }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.ActivationMaxHours | Should -Be 4
            $R.SetParams.ContainsKey('AuthenticationContextId') | Should -BeFalse
        }
    }

    It 'treats eligible permanence+duration as a unit: a permanence change carries the duration too' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ allowPermanentEligibility = $true; eligibleDurationDays = 365 }
            $Current  = [pscustomobject]@{ AllowPermanentEligibility = $false; EligibleDurationDays = 365 }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.AllowPermanentEligibility | Should -BeTrue
            $R.SetParams.EligibleDuration | Should -Be 365
        }
    }

    It 'compares notification recipients as a case-insensitive set (order ignored)' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ notifications = [pscustomobject]@{ activeAlert = @('A@contoso.com', 'b@contoso.com') } }
            $Current  = [pscustomobject]@{ Notifications = [pscustomobject]@{ ActiveAlert = @('b@contoso.com', 'a@contoso.com') } }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeFalse
        }
    }

    It 'detects an added notification recipient' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ notifications = [pscustomobject]@{ activeAlert = @('a@contoso.com', 'new@contoso.com') } }
            $Current  = [pscustomobject]@{ Notifications = [pscustomobject]@{ ActiveAlert = @('a@contoso.com') } }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.ActiveAlertRecipient | Should -Contain 'new@contoso.com'
        }
    }

    It 'treats a null current (not onboarded/unreadable) as everything-changed' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ activationMaxHours = 8; activeEnablement = @('MultiFactorAuthentication') }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $null
            $R.Changed | Should -BeTrue
            $R.SetParams.ActivationMaxHours | Should -Be 8
            $R.SetParams.ActiveEnabledRules | Should -Contain 'MultiFactorAuthentication'
        }
    }

    It 'carries a permanence revoke (true -> false) into SetParams' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ allowPermanentEligibility = $false; eligibleDurationDays = 365 }
            $Current  = [pscustomobject]@{ AllowPermanentEligibility = $true; EligibleDurationDays = 365 }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.ContainsKey('AllowPermanentEligibility') | Should -BeTrue
            $R.SetParams.AllowPermanentEligibility | Should -BeFalse
            $R.SetParams.EligibleDuration | Should -Be 365
        }
    }

    It 'emits an authenticationContextId change when Current is null' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ authenticationContextId = 'c1' }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $null
            $R.Changed | Should -BeTrue
            $R.SetParams.AuthenticationContextId | Should -Be 'c1'
        }
    }

    It 'treats a null authenticationContextId as undeclared and leaves the live context alone' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "authenticationContextId": null }' | ConvertFrom-Json
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current ([PSCustomObject]@{ AuthenticationContextId = 'c1' })
            $Change.Changed | Should -Be $false
            $Change.SetParams.ContainsKey('AuthenticationContextId') | Should -Be $false
        }
    }

    It 'still treats an explicitly empty authenticationContextId as a declared disable' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "authenticationContextId": "" }' | ConvertFrom-Json
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current ([PSCustomObject]@{ AuthenticationContextId = 'c1' })
            $Change.Changed | Should -Be $true
            $Change.SetParams.AuthenticationContextId | Should -BeExactly ''
        }
    }

    It 'treats a null allowPermanentEligibility as undeclared and does not revoke permanence' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "allowPermanentEligibility": null }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ AllowPermanentEligibility = $true; EligibleDurationDays = 365 }
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            $Change.SetParams.ContainsKey('AllowPermanentEligibility') | Should -Be $false
        }
    }

    It 'treats a null activationEnablement as undeclared and does not clear MFA' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "activationEnablement": null }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ ActivationEnabledRules = @('MultiFactorAuthentication') }
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            $Change.SetParams.ContainsKey('ActivationEnabledRules') | Should -Be $false
        }
    }

    It 'still treats an explicitly empty activationEnablement array as a declared clear' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "activationEnablement": [] }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ ActivationEnabledRules = @('MultiFactorAuthentication') }
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $true
            @($Change.SetParams.ActivationEnabledRules).Count | Should -Be 0
        }
    }

    It 'treats a null eligibleDurationDays as undeclared rather than a zero-day maximum' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "eligibleDurationDays": null }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ AllowPermanentEligibility = $false; EligibleDurationDays = 30 }
            $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
        }
    }
}

Describe 'Resolve-OERGroupPimPolicyChange authentication context reconcile' {
    It 'clears MFA from the declared enablement when a context is declared' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ authenticationContextId = 'c1' }
            $Current  = [pscustomobject]@{
                AuthenticationContextId = ''
                ActivationEnabledRules  = @('MultiFactorAuthentication', 'Justification')
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.SetParams.ActivationEnabledRules | Should -Be @('Justification')
            ($R.Changes -join ' ') | Should -Match 'mfa cleared'
        }
    }

    It 'disables a live context when the document declares MFA' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ activationEnablement = @('MultiFactorAuthentication') }
            $Current  = [pscustomobject]@{
                AuthenticationContextId = 'c1'
                ActivationEnabledRules  = @('Justification')
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.SetParams.AuthenticationContextId | Should -Be ''
            ($R.Changes -join ' ') | Should -Match 'c1'
        }
    }

    It 'converges: a document declaring both settles after one apply' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                authenticationContextId = 'c1'
                activationEnablement    = @('MultiFactorAuthentication', 'Justification')
            }
            $Current = [pscustomobject]@{
                AuthenticationContextId = ''
                ActivationEnabledRules  = @('MultiFactorAuthentication', 'Justification')
            }
            $First = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $First.Changed | Should -BeTrue

            # Simulate the state the write path would leave behind.
            $After = [pscustomobject]@{
                AuthenticationContextId = $First.SetParams.AuthenticationContextId
                ActivationEnabledRules  = @($First.SetParams.ActivationEnabledRules)
            }
            $Second = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $After
            $Second.Changed | Should -BeFalse
        }
    }

    It 'leaves a policy alone when the document declares neither side' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ activationMaxHours = 8 }
            $Current  = [pscustomobject]@{
                ActivationMaxHours      = 8
                AuthenticationContextId = 'c1'
                ActivationEnabledRules  = @('MultiFactorAuthentication')
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeFalse
        }
    }
}

Describe 'Resolve-OERGroupPimPolicyChange approval (requireApproval, approvers)' {
    # THE ACCEPTANCE TEST -- Current is built with the REAL ConvertTo-OERGroupPimPolicy (not a hand
    # built object) so this proves the read side (ConvertFrom-OERGraphApprover's id-for-groupId
    # fallback) and the diff side agree on what an approver id is, for BOTH shapes Graph can return a
    # group approver in: the beta endpoint's bare { id }, and the v1.0/PATCH-body { groupId }.
    It 'reports Unchanged for an approver group returned as id (beta) and as groupId' -ForEach @(
        @{ Shape = 'beta id'; Approver = @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1' } }
        @{ Shape = 'groupId'; Approver = @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'grp-1' } }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Approver = $Approver } {
            param($Approver)
            $Rules = @(
                @{
                    id      = 'Approval_EndUser_Assignment'
                    setting = @{
                        isApprovalRequired = $true
                        approvalStages     = @(@{ primaryApprovers = @($Approver) })
                    }
                }
            )
            $Current = ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId 'g1' -PolicyId 'p1' -AccessType 'member'
            $Declared = [pscustomobject]@{ requireApproval = $true; approvers = [pscustomobject]@{ groups = @('grp-1') } }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeFalse
        }
    }

    It 'compares approver ids case-insensitively' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ approvers = [pscustomobject]@{ groups = @('GRP-1') } }
            $Current  = [pscustomobject]@{
                Approvers = @([PSCustomObject]@{ Id = 'grp-1'; UserType = 'Group'; DisplayName = '' })
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeFalse
        }
    }

    It 'sends only ApproverUser when only users are declared and differ' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{ approvers = [pscustomobject]@{ users = @('11111111-1111-1111-1111-111111111111') } }
            $Current  = [pscustomobject]@{ Approvers = @() }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.ContainsKey('ApproverUser') | Should -BeTrue
            $R.SetParams.ContainsKey('ApproverGroup') | Should -BeFalse
        }
    }

    It 'sends both declared sides when only groups differ' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                approvers = [pscustomobject]@{
                    users  = @('11111111-1111-1111-1111-111111111111')
                    groups = @('22222222-2222-2222-2222-222222222222')
                }
            }
            $Current = [pscustomobject]@{
                Approvers = @(
                    [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; UserType = 'User'; DisplayName = '' }
                    [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; UserType = 'Group'; DisplayName = '' }
                )
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.ContainsKey('ApproverUser') | Should -BeTrue
            $R.SetParams.ContainsKey('ApproverGroup') | Should -BeTrue
            $R.SetParams.ApproverGroup | Should -Be @('22222222-2222-2222-2222-222222222222')
        }
    }

    It 'ignores approvers and sends no approver key when requireApproval is declared false' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                requireApproval = $false
                approvers       = [pscustomobject]@{ groups = @('22222222-2222-2222-2222-222222222222') }
            }
            $Current = [pscustomobject]@{
                RequireApproval = $false
                Approvers       = @()
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.SetParams.ContainsKey('ApproverUser') | Should -BeFalse
            $R.SetParams.ContainsKey('ApproverGroup') | Should -BeFalse
            $R.SetParams.ContainsKey('RequireApproval') | Should -BeFalse
            ($R.Changes -join ' ') | Should -Match 'approvers ignored: requireApproval=False takes precedence'
        }
    }

    It 'sends RequireApproval only when it differs from Current, even with the ignore note present' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                requireApproval = $false
                approvers       = [pscustomobject]@{ groups = @('22222222-2222-2222-2222-222222222222') }
            }
            $Current = [pscustomobject]@{
                RequireApproval = $true
                Approvers       = @([PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; UserType = 'Group'; DisplayName = '' })
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.Changed | Should -BeTrue
            $R.SetParams.RequireApproval | Should -BeFalse
            $R.SetParams.ContainsKey('ApproverUser') | Should -BeFalse
            $R.SetParams.ContainsKey('ApproverGroup') | Should -BeFalse
        }
    }

    It 'sends every declared approval field when Current is null' {
        InModuleScope $script:moduleName {
            $Declared = [pscustomobject]@{
                requireApproval = $true
                approvers       = [pscustomobject]@{
                    users  = @('11111111-1111-1111-1111-111111111111')
                    groups = @('22222222-2222-2222-2222-222222222222')
                }
            }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $null
            $R.Changed | Should -BeTrue
            $R.SetParams.RequireApproval | Should -BeTrue
            $R.SetParams.ApproverUser | Should -Be @('11111111-1111-1111-1111-111111111111')
            $R.SetParams.ApproverGroup | Should -Be @('22222222-2222-2222-2222-222222222222')
        }
    }

    It 'treats an explicit "approvers": null as undeclared and sends no approver key' {
        InModuleScope $script:moduleName {
            $Declared = '{ "requireApproval": true, "approvers": null }' | ConvertFrom-Json
            $Current  = [pscustomobject]@{ RequireApproval = $true; Approvers = @() }
            $R = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $Current
            $R.SetParams.ContainsKey('ApproverUser') | Should -BeFalse
            $R.SetParams.ContainsKey('ApproverGroup') | Should -BeFalse
        }
    }
}
