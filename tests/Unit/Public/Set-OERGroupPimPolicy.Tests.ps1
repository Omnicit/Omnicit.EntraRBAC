BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

Describe 'Set-OERGroupPimPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
        # Set-OERGroupPimPolicy validates -AuthenticationContextId against the tenant's published
        # contexts before it patches anything (#54), so every test that binds that parameter needs a
        # tenant list here or the cmdlet correctly refuses with AuthenticationContextNotFound.
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
        }
    }

    It 'patches only the activation expiration rule when only -ActivationMaxHours is given' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false
        $Result.Applied | Should -BeTrue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match 'Expiration_EndUser_Assignment' }
    }

    It 'resolves the owner policy id when -AccessType owner' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -AccessType owner -ActivationMaxHours 4 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -ParameterFilter { $AccessType -eq 'owner' }
    }

    It 'patches the active enablement rule with the requested rules' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -ActiveEnabledRules MultiFactorAuthentication, Justification -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -match 'Enablement_Admin_Assignment' -and ($Body.enabledRules -contains 'MultiFactorAuthentication')
        }
    }

    It 'patches the three notification rules with the recipients' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -EligibleAlertRecipient person18@example.com -ActiveAlertRecipient person22@example.com -ActivationAlertRecipient person24@example.com -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match 'Notification_Admin_Admin_Eligibility' -and ($Body.notificationRecipients -contains 'person18@example.com') }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match 'Notification_Admin_EndUser_Assignment' }
    }

    It 'converts -EligibleDuration days to an ISO maximumDuration and patches the eligibility rule' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -EligibleDuration 365 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P365D'
        }
    }

    It 'allows permanent eligibility (isExpirationRequired false) and includes the duration' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -EligibleDuration 365 -Confirm:$false
        $Result.AllowPermanentEligibility | Should -BeTrue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.isExpirationRequired -eq $false
        }
    }

    It 'reports partial failure when a rule PATCH throws' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw [System.Exception]::new('rule rejected') } -ParameterFilter { $Method -eq 'PATCH' }
        # -ErrorAction is pinned: left unset, a GLOBAL Stop preference throws the trailing
        # PolicyRulesRejected record and $Result is never assigned (the next It asserts that record).
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -ErrorAction SilentlyContinue
        $Result.Applied | Should -BeFalse
        $Result.FailedRules.Count | Should -BeGreaterThan 0
    }

    It 'writes a non-terminating PolicyRulesRejected error when a rule is rejected' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'group-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { 'policy-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'RuleValidationFailed' }

        $Result = Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue

        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'PolicyRulesRejected'
        $Result.Applied     | Should -BeFalse
        @($Result.FailedRules).Count | Should -BeGreaterThan 0
    }

    It 'does not write an error when every rule applies' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'group-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { 'policy-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{} }

        $Result = Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 `
            -ErrorAction SilentlyContinue -ErrorVariable Err

        @($Err).Count   | Should -Be 0
        $Result.Applied | Should -BeTrue
    }

    It 'still returns the summary object alongside the error' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'group-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERPimGroupPolicyId { 'policy-id-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'RuleValidationFailed' }

        $Result = Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 `
            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

        $Result                          | Should -Not -BeNullOrEmpty
        $Result.PSObject.TypeNames[0]    | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicyResult'
    }

    It 'errors when the group is not onboarded to PIM' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'PimPolicyNotFound'
    }

    It 'reports PimPolicyNotFound naming replication delay' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err.FullyQualifiedErrorId | Should -Match 'PimPolicyNotFound'
        $Message = @($Err).Exception.Message -join ' '
        $Message | Should -BeLike '*replication delay*'
        $Message | Should -Not -BeLike '*Add-OERGroupEligibility*'
    }

    It 'reports PimPolicyReadFailed, not PimPolicyNotFound, when the policy lookup is refused' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        # -ErrorVariable also carries the raw Authorization_RequestDenied record the engine records at
        # the point of the throw (see the -ErrorVariable comment on Get-OERPimGroupPolicyId's own not-
        # onboarded contract tests), so filter to the cmdlet's OWN wrapped record instead of asserting
        # on $Err as a whole.
        $ReadFailed = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyReadFailed*' })
        $ReadFailed.Count | Should -Be 1
        $ReadFailed[0].CategoryInfo.Category | Should -Be 'ReadError'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'never calls Start-Sleep on its own -- retry belongs to the apply engine, not a standalone Set' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Start-Sleep {}
        Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Start-Sleep -Times 0
    }

    It 'does not PATCH and returns no object under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -WhatIf
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'accepts the group id from the pipeline via the GroupId alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        [pscustomobject]@{ GroupId = 'gid-1' } | Set-OERGroupPimPolicy -ActivationMaxHours 8 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'carries AccessType through a Get-to-Set pipe' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            param($GroupId, $AccessType)
            if ($AccessType -eq 'owner') { 'OWNER-POLICY' } else { 'MEMBER-POLICY' }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        $Policy = InModuleScope $script:moduleName {
            ConvertTo-OERGroupPimPolicy -GroupId 'g1' -PolicyId 'OWNER-POLICY' -AccessType 'owner' -Rules @()
        }

        $Policy | Set-OERGroupPimPolicy -ActivationMaxHours 4 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly `
            -ParameterFilter { $Uri -like '*roleManagementPolicies/OWNER-POLICY/*' }
    }

    It 'accepts -Group by display name and resolves it via Resolve-OERGroupId' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Group 'role_sec_admins' -ActivationMaxHours 8 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
    }

    It 'still binds the legacy -DisplayName alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -DisplayName 'role_sec_admins' -ActivationMaxHours 8 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
    }

    It 'errors GroupNotFound when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Group 'nope' -ActivationMaxHours 8 -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'gives an actionable GroupNotFound message' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroupPimPolicy -Group 'ghost' -ActivationMaxHours 8 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'GroupNotFound'
        $Text = @($Err).Exception.Message -join ' '
        $Text | Should -Match 'display name'
        $Text | Should -Match 'object id'
    }

    It 'leaves no record in $Error when the group resolver fails' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'transport failure' }
        $Error.Clear()
        Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 -ErrorAction SilentlyContinue | Out-Null
        # Only the cmdlet's own GroupNotFound record may remain; the swallowed resolver throw must not.
        @($Error).Exception.Message -join ';' | Should -Not -Match 'transport failure'
    }

    It 'leaves no DUPLICATE record in $Error when the policy resolver fails' {
        # The raw record the engine recorded for the swallowed resolver throw must be gone (the
        # PimPolicyReadFailed catch's Remove-OERErrorRecord call), leaving exactly the cmdlet's own
        # wrapped PimPolicyReadFailed record -- which legitimately quotes the original exception
        # message as part of its explanation (see the next test), so this no longer asserts the raw
        # text is absent, only that it is not duplicated.
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'group-id-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { throw 'policy transport failure' }
        $Error.Clear()
        Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 -ErrorAction SilentlyContinue | Out-Null
        @($Error).Count | Should -Be 1
        $Error[0].FullyQualifiedErrorId | Should -Match 'PimPolicyReadFailed'
    }

    It 'quotes the underlying transport failure inside the PimPolicyReadFailed message' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'group-id-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { throw 'policy transport failure' }
        Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $ReadFailed = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyReadFailed*' })
        $ReadFailed.Count | Should -Be 1
        $ReadFailed[0].Exception.Message | Should -Match 'policy transport failure'
    }

    Context 'duration vocabulary aliases (audit PR6)' {
        It 'binds -EligibleDurationDays to the eligible expiration rule' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -EligibleDurationDays 365 -Confirm:$false
            $Result.EligibleDurationDays | Should -Be 365
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P365D'
            }
        }
        It 'binds -ActiveDurationDays to the active expiration rule' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -ActiveDurationDays 180 -Confirm:$false
            $Result.ActiveDurationDays | Should -Be 180
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Assignment' -and $Body.maximumDuration -eq 'P180D'
            }
        }
    }

    It 'omits the settings it did not patch instead of reporting them as null or false' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 4 -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicyResult'
        $Result.ActivationMaxHours | Should -Be 4
        $Result.PSObject.Properties.Name | Should -Not -Contain 'AllowPermanentEligibility'
        $Result.PSObject.Properties.Name | Should -Not -Contain 'AuthenticationContextId'
        $Result.PSObject.Properties.Name | Should -Not -Contain 'EligibleAlertRecipient'
    }

    It 'still carries the shared GroupPimPolicy type name for existing consumers' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 4 -Confirm:$false
        $Result.PSTypeNames | Should -Contain 'Omnicit.EntraRBAC.GroupPimPolicy'
        $Result.PSObject.Properties.Name | Should -Contain 'Applied'
        $Result.PSObject.Properties.Name | Should -Contain 'FailedRules'
    }

    It 'reports the eligible expiration unit when only the permanence switch is bound' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -Confirm:$false
        $Result.EligibleDurationDays | Should -Be 365
        $Result.AllowPermanentEligibility | Should -BeTrue
        $Result.PSObject.Properties.Name | Should -Not -Contain 'ActivationMaxHours'
    }

    It 'reports AllowPermanentEligibility as false when only -EligibleDurationDays is bound (the discriminating case)' {
        # This is the case that actually distinguishes the $RuleParams gate from the old
        # $PSBoundParameters gate: the permanence SWITCH is never bound here, yet
        # New-OERPimRuleSet still sends isExpirationRequired = $true on the same PATCH because the
        # expiration rule is a unit. Should -BeFalse also passes on $null, so the property-name
        # assertion is the one that actually proves the field was reported (not merely absent).
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -EligibleDurationDays 30 -Confirm:$false
        $Result.PSObject.Properties.Name | Should -Contain 'AllowPermanentEligibility'
        $Result.AllowPermanentEligibility | Should -BeFalse
        $Result.EligibleDurationDays | Should -Be 30
    }

    It 'reports AllowPermanentActive as false when only -ActiveDurationDays is bound (the discriminating case)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActiveDurationDays 14 -Confirm:$false
        $Result.PSObject.Properties.Name | Should -Contain 'AllowPermanentActive'
        $Result.AllowPermanentActive | Should -BeFalse
        $Result.ActiveDurationDays | Should -Be 14
    }

    Context 'reported settings are keyed on what was actually sent, not merely bound (audit PR7 M1)' {
        # $PSCmdlet.ShouldProcess is a method call on the live PSCmdlet, not a command, so Pester's
        # Mock cannot intercept it, and there is no supported in-process way to make it decline one
        # rule while accepting a sibling rule in the same invocation (a custom PSHost bound to a
        # fresh runspace can drive real per-prompt answers, but that runspace cannot see Pester's
        # module-scope mocks -- module state does not cross runspaces -- and a plain function
        # redefinition against the freshly-imported module does not shadow the module's OWN internal
        # calls the way Pester's Mock proxies do, so the unmocked Initialize-OERAuth runs for real).
        # These tests instead pin the two safe, reachable extremes end to end -- every rule accepted
        # and every rule declined (-WhatIf) -- and prove that Patched-field presence for each setting
        # exactly tracks an actual PATCH call for its governing rule id, which is what the -WhatIf
        # early-return and the per-setting gates in Set-OERGroupPimPolicy jointly guarantee.
        It 'reports two settings on different rules only when both were actually sent, one PATCH call each' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -ActiveEnabledRules MultiFactorAuthentication -Confirm:$false
            $Result.ActivationMaxHours | Should -Be 8
            $Result.ActiveEnabledRules | Should -Contain 'MultiFactorAuthentication'
            $Result.Applied | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -match 'Expiration_EndUser_Assignment' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -match 'Enablement_Admin_Assignment' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2
        }

        It 'sends nothing and reports nothing when every rule is declined via -WhatIf' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -ActiveEnabledRules MultiFactorAuthentication -WhatIf
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }

    Context 'permanence switch carries the live maximumDuration forward instead of the parameter default (roundtrip PR task 13)' {
        It 'preserves the live eligible maximumDuration when only -AllowPermanentEligibility is supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P30D' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P30D'
            }
            $Result.EligibleDurationDays | Should -Be 30
            $Result.AllowPermanentEligibility | Should -BeTrue
        }

        It 'preserves the live active maximumDuration when only -AllowPermanentActive is supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Assignment' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $true; maximumDuration = 'P90D' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentActive -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Assignment' -and $Body.maximumDuration -eq 'P90D'
            }
            $Result.ActiveDurationDays | Should -Be 90
            $Result.AllowPermanentActive | Should -BeTrue
        }

        It 'still sends the supplied duration when -EligibleDuration is bound, and never reads the live value' {
            # A live value that DIFFERS from the supplied one proves the explicit parameter wins; the
            # zero-invocation assertion proves the extra Graph read is skipped entirely when the
            # duration parameter is bound (Task 13: only issue it when the permanence switch is bound
            # WITHOUT its duration -- an unconditional read would add a Graph call to every invocation).
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -EligibleDuration 30 -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P30D'
            }
            $Result.EligibleDurationDays | Should -Be 30
        }

        It 'preserves a non-day live duration verbatim' {
            # This is what the new ConvertFrom-OERDuration parser makes reachable: previously a live P1Y
            # would have read back as a null day count and been treated as "not configured".
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P1Y' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P1Y'
            }
        }

        It 'falls back to the parameter default and warns when the live rule read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } { throw [System.Exception]::new('transport failure') }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            $Result = Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -match 'Expiration_Admin_Eligibility' -and $Body.maximumDuration -eq 'P365D'
            }
            $Result.EligibleDurationDays | Should -Be 365
            @($Warn) | Should -Not -BeNullOrEmpty
        }

        It 'leaves no record in $Error when the live rule read fails (bearer-token hygiene)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -match 'Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } { throw [System.Exception]::new('transport failure') }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } {}
            $Error.Clear()
            Set-OERGroupPimPolicy -Id 'gid-1' -AllowPermanentEligibility -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            @($Error).Exception.Message -join ';' | Should -Not -Match 'transport failure'
        }
    }

    Context 'every $Sent.Contains rule-id literal that gates the summary is pinned (audit prom-pimpolicy-rule-literals-partially-unpinned)' {
        # BLAST RADIUS -- recorded here so future triage stays honest. These ten literals gate ONLY
        # $Patched, i.e. WHICH PROPERTIES APPEAR on the returned summary object. $Out.Applied is
        # computed from $Failed.Count / $Sent.Count against @($Rules).Count and does not depend on
        # any of them, and Sync-OERStructureGroup consumes only .FailedRules and .Applied. So the
        # worst outcome of one of these literals drifting away from the id New-OERPimRuleSet emits
        # is a summary that OMITS a property that really WAS patched -- never a wrong write, and
        # never a missed one.
        #
        # WHY A URI MATCH IS NOT A PIN FOR THIS GATE. The PATCH uri is built from $Rule.id, so a
        # -ParameterFilter { $Uri -match '<literal>' } assertion pins New-OERPimRuleSet's literal on
        # the far side of the module, not Set-OERGroupPimPolicy's own $Sent.Contains('<literal>')
        # line. The two are independent strings and a typo in either alone still passes such a test.
        # What pins the gate is asserting that the corresponding $Patched property lands on the
        # returned object. Five of the original nine literals had no such assertion before this table:
        # AuthenticationContext_EndUser_Assignment, Enablement_EndUser_Assignment,
        # Notification_Admin_Admin_Eligibility, Notification_Admin_Admin_Assignment and
        # Notification_Admin_EndUser_Assignment. The tenth, Approval_EndUser_Assignment, joined with
        # its own row when the approval parameters were added (Sprint 6 step 2); it is exercised with
        # -RequireApproval $false, since this table's mock returns no live approval rule and $true
        # would then be refused as ApproverRequired before any PATCH. Do NOT add a uri-match case
        # here -- that would simply reproduce the blind spot this table exists to close.
        It 'reports <Property> on the summary when -<Parameter> is bound (gate literal <Literal>)' -TestCases @(
            @{ Parameter = 'ActivationMaxHours';       Literal = 'Expiration_EndUser_Assignment';            Property = 'ActivationMaxHours';       Value = 4 }
            @{ Parameter = 'AuthenticationContextId';  Literal = 'AuthenticationContext_EndUser_Assignment'; Property = 'AuthenticationContextId';  Value = 'c1' }
            @{ Parameter = 'ActivationEnabledRules';   Literal = 'Enablement_EndUser_Assignment';            Property = 'ActivationEnabledRules';   Value = @('MultiFactorAuthentication') }
            @{ Parameter = 'ActiveEnabledRules';       Literal = 'Enablement_Admin_Assignment';              Property = 'ActiveEnabledRules';       Value = @('Justification') }
            @{ Parameter = 'EligibleDurationDays';     Literal = 'Expiration_Admin_Eligibility';             Property = 'EligibleDurationDays';     Value = 365 }
            @{ Parameter = 'ActiveDurationDays';       Literal = 'Expiration_Admin_Assignment';              Property = 'ActiveDurationDays';       Value = 30 }
            @{ Parameter = 'EligibleAlertRecipient';   Literal = 'Notification_Admin_Admin_Eligibility';     Property = 'EligibleAlertRecipient';   Value = @('person31@example.com') }
            @{ Parameter = 'ActiveAlertRecipient';     Literal = 'Notification_Admin_Admin_Assignment';      Property = 'ActiveAlertRecipient';     Value = @('person32@example.com') }
            @{ Parameter = 'ActivationAlertRecipient'; Literal = 'Notification_Admin_EndUser_Assignment';    Property = 'ActivationAlertRecipient'; Value = @('person33@example.com') }
            @{ Parameter = 'RequireApproval';          Literal = 'Approval_EndUser_Assignment';              Property = 'RequireApproval';          Value = $false }
        ) {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Splat = @{ Group = 'gid-1'; Confirm = $false }
            $Splat[$Parameter] = $Value
            $Result = Set-OERGroupPimPolicy @Splat

            $Result.PSObject.Properties.Name | Should -Contain $Property -Because (
                "Set-OERGroupPimPolicy gates `$Patched.$Property on `$Sent.Contains('$Literal'), and " +
                "New-OERPimRuleSet must emit exactly that id -- if this fails the two literals disagree")
            # Compare through a join so one expression covers the scalar and the collection cases and
            # neither degenerates: @($null) -join ',' is the empty string, so a property that bound
            # to $null cannot slip past this the way $null.Count -eq 0 or Should -BeFalse would.
            (@($Result.$Property) -join ',') | Should -Be (@($Value) -join ',')
        }
    }

    Context 'approval' {
        # The live approval rule is read in the beta shape PIM for Groups is pinned to: an approver
        # carries id, never userId or groupId -- and it is PATCHed in that same beta shape (id and
        # isBackup, never userId, groupId or the read-only description). $script:LiveApproval is what
        # that read returns; $script:Patches records every PATCH body, in order.
        BeforeEach {
            $script:Patches = [System.Collections.Generic.List[object]]::new()
            $script:LiveApproval = @{
                id      = 'Approval_EndUser_Assignment'
                setting = @{
                    isApprovalRequired               = $false
                    isApprovalRequiredForExtension   = $false
                    isRequestorJustificationRequired = $true
                    approvalMode                     = 'SingleStage'
                    approvalStages                   = @(@{
                            approvalStageTimeOutInDays      = 2
                            isApproverJustificationRequired = $true
                            escalationTimeInMinutes         = 0
                            isEscalationEnabled             = $false
                            primaryApprovers                = @(
                                @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1'; description = 'Old user' }
                                @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1'; description = 'Approvers' }
                            )
                            escalationApprovers             = @()
                        })
                }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                if ($Method -eq 'PATCH') { $script:Patches.Add($Body); return @{} }
                if ($Uri -like '*rules/Approval_EndUser_Assignment') { return $script:LiveApproval }
                return @{}
            }
            # An id resolves to itself, letter case preserved (as the real resolver returns a GUID
            # input untouched); a name resolves through the map; anything else is not found.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipal {
                $Map = @{
                    'person1@example.com' = '11111111-1111-1111-1111-111111111111'
                    'person2@example.com' = '22222222-2222-2222-2222-222222222222'
                    'pim-approvers'       = '33333333-3333-3333-3333-333333333333'
                }
                $Kind = if ($User) { 'User' } else { 'Group' }
                $Name = if ($User) { $User } else { $Group }
                $Id = if ($Name -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Name } else { $Map[$Name] }
                if (-not $Id) { throw "$Kind '$Name' was not found." }
                [pscustomobject]@{ PrincipalId = $Id; PrincipalType = $Kind }
            }
        }

        It 'still reports NothingToUpdate when no rule parameter is bound' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NothingToUpdate*'
            $Err[0].Exception.Message | Should -Match '-RequireApproval, -ApproverUser, -ApproverGroup'
        }

        It 'does not report NothingToUpdate when only -<Parameter> is bound' -TestCases @(
            @{ Parameter = 'RequireApproval'; Value = $true }
            @{ Parameter = 'ApproverUser'; Value = @('person1@example.com') }
            @{ Parameter = 'ApproverGroup'; Value = @('pim-approvers') }
        ) {
            $Err = $null
            $Splat = @{ Group = 'gid-1'; Confirm = $false; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Err' }
            $Splat[$Parameter] = $Value
            Set-OERGroupPimPolicy @Splat | Out-Null
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*rules/Approval_EndUser_Assignment'
            }
        }

        It 'refuses with ApproverNotFound when one of two users does not resolve, and sends nothing' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person1@example.com', 'person9@example.com' -ActivationMaxHours 8 `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            # -ErrorVariable also collects the resolver's own throw, caught inside the cmdlet, so the
            # record the cmdlet WROTE is selected by its id rather than by position.
            $Record = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'ApproverNotFound*' })
            $Record.Count | Should -Be 1
            $Record[0].TargetObject | Should -Be 'person9@example.com'
            $Record[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Record[0].Exception.Message | Should -Match 'person9@example\.com'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
            # Approvers are resolved before the group, so a refused call costs no Graph round trip.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'skips an empty or whitespace-only approver value instead of resolving it' {
            $Err = $null
            $null = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person1@example.com', '   ', '' -ApproverGroup "`t", 'pim-approvers' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
            # Only the two real values reach the resolver; a blank one would have been looked up (and
            # refused the whole call as ApproverNotFound with the real resolver).
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 0 -ParameterFilter {
                [string]::IsNullOrWhiteSpace([string]$User) -and [string]::IsNullOrWhiteSpace([string]$Group)
            }
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            @($Primary.id) | Should -Be @('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
        }

        It 'refuses with ApproverNotFound when a group does not resolve' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverGroup 'no-such-group' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Record = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'ApproverNotFound*' })
            $Record.Count | Should -Be 1
            $Record[0].TargetObject | Should -Be 'no-such-group'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        # Three call shapes. With -RequireApproval $true alone, a missing return after the read failure
        # would still be caught downstream by ApproverRequired (the unread rule has no approvers), so
        # the other two shapes -- where that guard cannot fire -- are what prove the read failure
        # itself stops the call.
        It 'refuses with ApprovalRuleReadFailed when the live approval rule cannot be read, and patches no rule at all (<Shape>)' -TestCases @(
            @{ Shape = 'RequireApproval true'; Parameter = 'RequireApproval'; Value = $true }
            @{ Shape = 'RequireApproval false'; Parameter = 'RequireApproval'; Value = $false }
            @{ Shape = 'ApproverUser only'; Parameter = 'ApproverUser'; Value = @('person1@example.com') }
        ) {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*rules/Approval_EndUser_Assignment' -and $Method -ne 'PATCH' } {
                throw [System.Exception]::new('transport failure')
            }
            $Err = $null
            $Splat = @{
                Group = 'gid-1'; ActivationMaxHours = 8; EligibleAlertRecipient = 'person18@example.com'
                Confirm = $false; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Err'
            }
            $Splat[$Parameter] = $Value
            $Result = Set-OERGroupPimPolicy @Splat
            $Result | Should -BeNullOrEmpty
            $Record = @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'ApprovalRuleReadFailed*' })
            $Record.Count | Should -Be 1
            $Record[0].CategoryInfo.Category | Should -Be 'ReadError'
            $Record[0].TargetObject | Should -Be 'pol-1'
            $Record[0].Exception.Message | Should -Match 'Nothing was changed'
            $Record[0].Exception.InnerException.Message | Should -Be 'transport failure'
            # No PATCH of ANY rule -- not the approval rule, and not the two other rules bound in the
            # same call either.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'refuses with ApproverRequired when approval is required and the live rule has no approver' {
            $script:LiveApproval = @{ id = 'Approval_EndUser_Assignment'; setting = @{ isApprovalRequired = $false; approvalMode = 'NoApproval'; approvalStages = @() } }
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -ActivationMaxHours 8 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'ApproverRequired*'
            $Err[0].TargetObject | Should -Be 'gid-1'
            $Err[0].Exception.Message | Should -Match "PIM policy 'pol-1'"
            $Err[0].Exception.Message | Should -BeLike '*has none on its live approval rule and none was supplied*'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'refuses with ApproverRequired when both approver sides end up empty' {
            # Binding -ApproverUser to an empty list clears the user side; the live rule has no group.
            $script:LiveApproval.setting.approvalStages[0].primaryApprovers = @(
                @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1' }
            )
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser @() -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'ApproverRequired*'
            # The live rule DID have an approver here -- the bound side cleared it -- so the message
            # must not claim the policy had none.
            $Err[0].Exception.Message | Should -BeLike '*would have none*'
            $Err[0].Exception.Message | Should -Not -BeLike '*has none on its live approval rule*'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'carries a live approver of another kind unchanged when an approver side is bound' {
            $Manager = @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
            $script:LiveApproval.setting.approvalStages[0].primaryApprovers = @(
                $Manager
                @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1' }
                @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1' }
            )
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person1@example.com' -Confirm:$false
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            $Primary.Count | Should -Be 3
            # The other-kind approver is the very object that was read, not a rebuilt copy.
            $Kept = @($Primary | Where-Object { [object]::ReferenceEquals($_, $Manager) })
            $Kept.Count | Should -Be 1
            $Kept[0].Keys.Count | Should -Be 2
            $Kept[0].managerLevel | Should -Be 1
            # The group side survived; the user side was replaced.
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' }).id | Should -Be @('grp-1')
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' }).id | Should -Be @('11111111-1111-1111-1111-111111111111')
            $Result.Applied | Should -BeTrue
        }

        It 'counts a carried other-kind approver, so clearing both sides beside it is not ApproverRequired' {
            $script:LiveApproval.setting.approvalStages[0].primaryApprovers = @(
                @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
                @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1' }
            )
            $Err = $null
            $null = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser @() -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'ApproverRequired*' }).Count | Should -Be 0
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            $Primary.Count | Should -Be 1
            $Primary[0].'@odata.type' | Should -Be '#microsoft.graph.requestorManager'
        }

        It 'lets -RequireApproval $false through with no approver anywhere' {
            $script:LiveApproval = @{ id = 'Approval_EndUser_Assignment'; setting = @{ isApprovalRequired = $true; approvalStages = @() } }
            $Err = $null
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $false -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).Count | Should -Be 0
            $Result.RequireApproval | Should -BeFalse
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Body.setting.isApprovalRequired | Should -BeFalse
            @($Body.setting.approvalStages).Count | Should -Be 0
        }

        It 'patches -RequireApproval $true alone with the live approvers normalized to the beta PATCH shape' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -Confirm:$false
            $Result.Applied | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*policies/roleManagementPolicies/pol-1/rules/Approval_EndUser_Assignment'
            }
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Body.'@odata.type' | Should -Be '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
            $Body.setting.isApprovalRequired | Should -BeTrue
            $Stage = @($Body.setting.approvalStages)[0]
            $Stage.approvalStageTimeOutInDays | Should -Be 2
            $Primary = @($Stage.primaryApprovers)
            $Primary.Count | Should -Be 2
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' -and $_.id -eq 'grp-1' }).Count | Should -Be 1
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' -and $_.id -eq 'user-1' }).Count | Should -Be 1
            # Beta shape: id and isBackup = false; never v1.0's userId/groupId, and never the read-only
            # description the live read carried.
            @($Primary | Where-Object { $_.isBackup -ne $false }).Count | Should -Be 0
            @($Primary | Where-Object { $_.Keys -contains 'userId' -or $_.Keys -contains 'groupId' -or $_.Keys -contains 'description' }).Count | Should -Be 0
        }

        It 'replaces only the user side and carries the live group side when only -ApproverUser is bound' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person1@example.com' -Confirm:$false
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Body.setting.isApprovalRequired | Should -BeTrue
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            $Primary.Count | Should -Be 2
            $Users = @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' })
            $Groups = @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' })
            @($Users.id) | Should -Be @('11111111-1111-1111-1111-111111111111')
            @($Groups.id) | Should -Be @('grp-1')
            # The bound user is built in the v1.0 userId shape here and still goes out in the beta shape.
            @($Primary | Where-Object { $_.isBackup -ne $false }).Count | Should -Be 0
            @($Primary | Where-Object { $_.Keys -contains 'userId' -or $_.Keys -contains 'groupId' -or $_.Keys -contains 'description' }).Count | Should -Be 0
            @($Result.ApproverUser) | Should -Be @('11111111-1111-1111-1111-111111111111')
            @($Result.ApproverGroup) | Should -Be @('grp-1')
        }

        It 'clears the group side and keeps the live user when -ApproverGroup is bound to an empty list' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverGroup @() -Confirm:$false
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            $Primary.Count | Should -Be 1
            $Primary[0].'@odata.type' | Should -Be '#microsoft.graph.singleUser'
            $Primary[0].id | Should -Be 'user-1'
            @($Result.ApproverUser) | Should -Be @('user-1')
            @($Result.ApproverGroup).Count | Should -Be 0
            $Result.PSObject.Properties.Name | Should -Contain 'ApproverGroup'
        }

        It 'de-duplicates an approver named twice, by UPN and by id or in different letter case' {
            $null = Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person1@example.com', '11111111-1111-1111-1111-111111111111' `
                -ApproverGroup 'aaaaaaaa-0000-0000-0000-00000000000a', 'AAAAAAAA-0000-0000-0000-00000000000A' -Confirm:$false
            $Body = @($script:Patches) | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' }
            $Primary = @(@($Body.setting.approvalStages)[0].primaryApprovers)
            $Primary.Count | Should -Be 2
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.singleUser' }).id | Should -Be @('11111111-1111-1111-1111-111111111111')
            @($Primary | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.groupMembers' }).id | Should -Be @('aaaaaaaa-0000-0000-0000-00000000000a')
        }

        It 'reports RequireApproval, ApproverUser and ApproverGroup on the result when approvers are bound' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -ApproverGroup 'pim-approvers' -Confirm:$false
            $Result.RequireApproval | Should -BeTrue
            @($Result.ApproverUser) | Should -Be @('user-1')
            @($Result.ApproverGroup) | Should -Be @('33333333-3333-3333-3333-333333333333')
        }

        It 'reports RequireApproval but no approver lists when only -RequireApproval is bound' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -Confirm:$false
            $Result.PSObject.Properties.Name | Should -Contain 'RequireApproval'
            $Result.RequireApproval | Should -BeTrue
            $Result.PSObject.Properties.Name | Should -Not -Contain 'ApproverUser'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'ApproverGroup'
        }

        It 'sends nothing and returns no object under -WhatIf' {
            $Result = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -ApproverUser 'person1@example.com' -WhatIf
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'does not read the live approval rule when no approval parameter is bound' {
            $null = Set-OERGroupPimPolicy -Group 'gid-1' -ActivationMaxHours 8 -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*Approval_EndUser_Assignment' }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 0
        }

        It 'reads the live approval rule through the PIM for Groups path helper' {
            # The expected uri comes from the helper itself, so this pins the ROUTING through it and
            # not the api version the helper owns.
            $Expected = InModuleScope $script:moduleName {
                Get-OERPimGroupsGraphPath -Path 'policies/roleManagementPolicies/pol-1/rules/Approval_EndUser_Assignment'
            }
            $null = Set-OERGroupPimPolicy -Group 'gid-1' -RequireApproval $true -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -ne 'PATCH' -and $Uri -eq $Expected
            }
        }
    }
}

Describe 'Set-OERGroupPimPolicy verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
    }

    It 'reports the resolved group and PIM policy id under -Verbose' {
        $Verbose = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Set-OERGroupPimPolicy\] Resolved group to 'gid-1'."
        $Text | Should -Match "\[Set-OERGroupPimPolicy\] Resolved PIM policy id: 'pol-1'."
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Set-OERGroupPimPolicy -Id 'gid-1' -ActivationMaxHours 8 -Confirm:$false 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}

Describe 'Set-OERGroupPimPolicy authentication context reconcile' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'p1' }
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
        }
        $script:Patched = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Method -eq 'PATCH') { $script:Patched.Add($Body); return @{} }
            if ($Uri -like '*rules/Enablement_EndUser_Assignment') {
                return @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
            }
            if ($Uri -like '*rules/AuthenticationContext_EndUser_Assignment') {
                return @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
            }
            return @{}
        }
    }

    It 'case A: refuses when the caller asks for both, and sends nothing' {
        $Err = $null
        Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' `
            -ActivationEnabledRules MultiFactorAuthentication, Justification `
            -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'MfaAuthContextConflict'
        # No -ParameterFilter: the case table says case A reaches Graph NOT AT ALL, not merely that
        # it sends no PATCH. Filtering on PATCH would still pass if the refusal moved below one of
        # the live rule reads, which would cost a round trip on a call that is always refused.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0
    }

    It 'case B: clears MFA out of the live enablement rules when a context is set' {
        $Warn = $null
        $R = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false `
            -WarningVariable Warn -WarningAction SilentlyContinue
        $Enablement = @($script:Patched) | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }
        $Enablement | Should -Not -BeNullOrEmpty
        @($Enablement.enabledRules) | Should -Be @('Justification')
        $R.ActivationEnabledRules | Should -Be @('Justification')
        # Clearing a rule the caller never asked about is a silent change to a high-privilege policy
        # unless it is announced. Assert the CONTENT: a bare -Not -BeNullOrEmpty here would be
        # satisfied by any unrelated warning the run happens to emit.
        ($Warn -join ' ') | Should -Match 'mfa cleared'
        ($Warn -join ' ') | Should -Match 'c1'
    }

    It 'case C: disables a live authentication context when MFA is requested' {
        $Warn = $null
        $R = Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication `
            -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        $Acrs = @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' }
        # Should -BeFalse passes on $null, so the rule's absence would satisfy the next line on its
        # own. Pin that the PATCH happened before reading anything off it.
        $Acrs | Should -Not -BeNullOrEmpty
        $Acrs.isEnabled | Should -BeFalse
        $R.AuthenticationContextId | Should -Be ''
        # The contract for this case is "switch it off AND say so, naming the claim value".
        ($Warn -join ' ') | Should -Match 'disabled'
        ($Warn -join ' ') | Should -Match "'c1'"
    }

    It 'reports the reconciled authentication context id that was SENT, not the unbound parameter' {
        # $AuthenticationContextIdReported and the unbound -AuthenticationContextId parameter are
        # both '' in every case the shipped resolver can produce, so case C cannot tell them apart.
        # Resolve-OERPimActivationConflict is module-private and mockable, so force it to return a
        # NON-empty id: the summary must then carry 'c9', which only the Reported variable holds.
        Mock -ModuleName $script:moduleName Resolve-OERPimActivationConflict {
            [pscustomobject]@{
                Action                  = 'DisableAuthContext'
                ActivationEnabledRules  = $null
                AuthenticationContextId = 'c9'
                Reason                  = 'forced for this test'
            }
        }
        $R = Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication `
            -Confirm:$false -WarningAction SilentlyContinue
        $Acrs = @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' }
        $Acrs | Should -Not -BeNullOrEmpty
        $Acrs.claimValue | Should -Be 'c9'
        $R.AuthenticationContextId | Should -Be 'c9'
    }

    It 'case D: disabling a context never re-adds MFA' {
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId '' -Confirm:$false
        # Positive anchor first: without it "the cmdlet did nothing at all" satisfies the absence
        # assertion below, so a mutation that refused every empty context would pass.
        @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' } |
            Should -Not -BeNullOrEmpty
        @($script:Patched) | Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' } | Should -BeNullOrEmpty
    }

    It 'case E: an explicit enablement list without MFA needs no live read' {
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false
        # Positive anchor: prove the call actually reached Graph before asserting what it did NOT read.
        @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' } |
            Should -Not -BeNullOrEmpty
        # No rule-id clause: case E must issue NO live read at all. Naming the Enablement rule would
        # let a mutation that fires arm C instead -- reading the AuthenticationContext rule -- pass.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0 -ParameterFilter {
            $Method -ne 'PATCH'
        }
    }

    It 'refuses an authentication context that does not exist in the tenant' {
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext { }
        $Err = $null
        Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c9' -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'AuthenticationContextNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'refuses an authentication context that exists but is not published' {
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Draft'; IsAvailable = $false }
        }
        $Err = $null
        Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'AuthenticationContextNotAvailable'
        # A refusal that still wrote the policy would be worse than no refusal at all. The NotFound
        # sibling above carries this assertion; without it here the refusal is only half-pinned.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'warns and proceeds when the tenant list cannot be read' {
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext { throw 'forbidden' }
        $Warn = $null
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        # Assert the CONTENT, not merely that some warning exists: this run ALSO reconciles (arm B
        # fires, because -ActivationEnabledRules is unbound) and warns about clearing MFA, so a bare
        # -Not -BeNullOrEmpty stays green with the read-failure warning deleted outright. That
        # warning is the whole point of degrading instead of hardening into a permission requirement.
        ($Warn -join ' ') | Should -Match 'Could not verify authentication context'
        @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' } | Should -Not -BeNullOrEmpty
    }

    It 'warns and proceeds when the live enablement rule cannot be read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Method -eq 'PATCH') { return @{} }
            throw 'forbidden'
        }
        $Warn = $null
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false -WarningVariable Warn -WarningAction SilentlyContinue
        $Warn | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-OERGroupPimPolicy declined-partner guard' {
    # The guard warns when a -Confirm decline accepts one half of a reconciled pair and refuses the
    # other, leaving the tenant in exactly the mutually exclusive state this cmdlet exists to
    # prevent. Reaching that $Sent shape needs a GENUINE per-rule ShouldProcess decline:
    # -Confirm:$false confirms and -WhatIf sets $WhatIfPreference, so neither produces it.
    #
    # Rule order decides WHICH half can be declined, and it is no longer fixed. The patch loop now
    # sends the rule that REMOVES the conflict first (rationale.md#mfa-authcontext-exclusion), so in
    # this DisableAuthContext scenario the reconciled AuthenticationContext rule prompts FIRST and
    # the MFA-adding Enablement rule prompts second. The mutually exclusive end state therefore
    # needs prompt 1 DECLINED and prompt 2 ACCEPTED -- which no single answer, and no flip driven
    # from the Invoke-OERGraphRequest fake (it runs only after an ACCEPTED prompt), can produce.
    # -AnswerSequence on the answering host exists for exactly this shape.
    #
    # That the shape got harder to reach is the ordering fix working: with the protective rule sent
    # first, an operator who accepts in order can no longer be walked into leaving both controls on.
    BeforeAll {
        $script:DeclineScenario = {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERGroupId -Value { 'g1' }
                Set-Item -Path function:script:Get-OERPimGroupPolicyId -Value { 'p1' }
                Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                    param([string]$Method = 'GET', [string]$Uri, $Body)
                    if ($Method -eq 'PATCH') { return @{} }
                    if ($Uri -like '*rules/AuthenticationContext_EndUser_Assignment') {
                        return @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                    }
                    return @{}
                }
            }
            Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication -Confirm | Out-Null
        }

        $script:AcceptScenario = {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERGroupId -Value { 'g1' }
                Set-Item -Path function:script:Get-OERPimGroupPolicyId -Value { 'p1' }
                Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                    param([string]$Method = 'GET', [string]$Uri, $Body)
                    if ($Method -eq 'PATCH') { return @{} }
                    if ($Uri -like '*rules/AuthenticationContext_EndUser_Assignment') {
                        return @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
                    }
                    return @{}
                }
            }
            Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication -Confirm | Out-Null
        }
    }

    It 'warns when the reconciled rule is declined while its partner was applied' {
        # Decline the reconciled rule (prompted FIRST now), accept the MFA rule that follows.
        $Result = Invoke-OERWithConfirmAnswer -AnswerSequence '&No', '&Yes' -Script $script:DeclineScenario
        # Both rules must really have reached a prompt, or the asymmetry below is an artefact of the
        # harness never getting there rather than of a decline.
        $Result.Prompts.Count | Should -BeGreaterOrEqual 2
        # Pin WHICH rule was prompted first: the guard's whole premise is that the declined half is
        # the reconciled one, and a silent return to the old fixed order would otherwise still pass.
        $Result.Prompts[0] | Should -Match 'AuthenticationContext_EndUser_Assignment'
        $Text = $Result.Warnings -join ' '
        $Text | Should -Match "Rule 'AuthenticationContext_EndUser_Assignment' was declined"
        $Text | Should -Match "'Enablement_EndUser_Assignment' was applied"
        $Text | Should -Match 'still requires both multi-factor authentication and an authentication context'
    }

    It 'stays silent when the operator accepts both halves of the reconcile' {
        # The discriminating control: same reconcile, same two rules, nothing declined. Without it
        # the assertion above would also pass against a guard that warned unconditionally.
        $Result = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $script:AcceptScenario
        $Result.Prompts.Count | Should -BeGreaterOrEqual 2
        ($Result.Warnings -join ' ') | Should -Not -Match 'was declined while'
    }

    It 'stays silent when the operator declines everything' {
        # Nothing was applied, so there is no half-applied state to warn about -- the cmdlet returns
        # before the guard. Pins that the guard keys on the ASYMMETRY, not on any decline at all.
        $Result = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $script:AcceptScenario
        $Result.Prompts.Count | Should -BeGreaterOrEqual 1
        ($Result.Warnings -join ' ') | Should -Not -Match 'was declined while'
    }
}

Describe 'Set-OERGroupPimPolicy MFA and authentication context patch order' {
    # Graph validates the exclusion ASYMMETRICALLY: enabling an authentication context while MFA is
    # already on is accepted, but enabling MFA while a context is already on is rejected with
    # MfaAndAcrsConflict. Each rule is its own PATCH, so the rule that goes second sees the state the
    # first one left -- the ORDER is the whole contract here, not merely that both rules were sent.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'p1' }
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
        }
        # Capture the SEQUENCE of patched rule ids. Should -Invoke cannot express relative order, so
        # the mock records it and the assertions compare positions.
        $script:PatchOrder = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Method -eq 'PATCH') { $script:PatchOrder.Add([string]$Body.id); return @{} }
            if ($Uri -like '*rules/Enablement_EndUser_Assignment') {
                return @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
            }
            if ($Uri -like '*rules/AuthenticationContext_EndUser_Assignment') {
                return @{ id = 'AuthenticationContext_EndUser_Assignment'; isEnabled = $true; claimValue = 'c1' }
            }
            return @{}
        }
    }

    It 'case C (reconciled disable): patches the authentication context rule BEFORE the enablement rule' {
        $Result = Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication, Justification `
            -Confirm:$false -WarningAction SilentlyContinue
        $AcAt = $script:PatchOrder.IndexOf('AuthenticationContext_EndUser_Assignment')
        $EnAt = $script:PatchOrder.IndexOf('Enablement_EndUser_Assignment')
        # Positive anchors first: IndexOf returns -1 for an id that was never patched, and -1 is less
        # than 0, so the ordering assertion below would pass on its own if the context rule were
        # dropped entirely rather than merely sent late.
        $AcAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeGreaterOrEqual 0
        $AcAt | Should -BeLessThan $EnAt
        # The live failure this pins: the enablement PATCH was rejected, so neither the old context
        # nor the requested MFA was in force. Applied must be honest about both halves landing.
        $Result.Applied | Should -BeTrue
    }

    It 'explicit -AuthenticationContextId and -ActivationEnabledRules: the disabling context PATCH still goes first' {
        # No reconcile runs here -- both rules come straight from the caller's own binding -- so this
        # is what proves the ordering rule is general rather than a patch on the reconcile path.
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId '' `
            -ActivationEnabledRules MultiFactorAuthentication -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0 -ParameterFilter { $Method -ne 'PATCH' }
        $AcAt = $script:PatchOrder.IndexOf('AuthenticationContext_EndUser_Assignment')
        $EnAt = $script:PatchOrder.IndexOf('Enablement_EndUser_Assignment')
        $AcAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeGreaterOrEqual 0
        $AcAt | Should -BeLessThan $EnAt
    }

    It 'case B (reconciled ClearMfa): patches the enablement rule BEFORE the authentication context rule' {
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false -WarningAction SilentlyContinue
        $AcAt = $script:PatchOrder.IndexOf('AuthenticationContext_EndUser_Assignment')
        $EnAt = $script:PatchOrder.IndexOf('Enablement_EndUser_Assignment')
        $AcAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeLessThan $AcAt
    }

    It 'explicit -AuthenticationContextId and -ActivationEnabledRules: an ENABLING context PATCH still goes last' {
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 0 -ParameterFilter { $Method -ne 'PATCH' }
        $AcAt = $script:PatchOrder.IndexOf('AuthenticationContext_EndUser_Assignment')
        $EnAt = $script:PatchOrder.IndexOf('Enablement_EndUser_Assignment')
        $AcAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeGreaterOrEqual 0
        $EnAt | Should -BeLessThan $AcAt
    }

    It 'reorders only the two exclusion rules, leaving every other rule where it was emitted' {
        $null = Set-OERGroupPimPolicy -Group 'g' -ActivationMaxHours 8 -AuthenticationContextId '' `
            -ActivationEnabledRules MultiFactorAuthentication -ActiveEnabledRules Justification `
            -EligibleAlertRecipient 'person18@example.com' -Confirm:$false -WarningAction SilentlyContinue
        @($script:PatchOrder) | Should -Be @(
            'Expiration_EndUser_Assignment'
            'AuthenticationContext_EndUser_Assignment'
            'Enablement_EndUser_Assignment'
            'Enablement_Admin_Assignment'
            'Notification_Admin_Admin_Eligibility'
        )
    }

    It 'leaves the emitted order untouched when neither of the two rules is built' {
        # The swap must key on BOTH rules being present. A rule set carrying neither the
        # authentication-context rule nor the end-user enablement rule has no pair to sequence and
        # must not be disturbed. Note: Enablement_Admin_Assignment (from -ActiveEnabledRules) is a
        # DIFFERENT rule id from Enablement_EndUser_Assignment, so this case does not touch the
        # ordered pair at all.
        $null = Set-OERGroupPimPolicy -Group 'g' -ActivationMaxHours 8 -ActiveEnabledRules Justification -Confirm:$false
        @($script:PatchOrder) | Should -Be @('Expiration_EndUser_Assignment', 'Enablement_Admin_Assignment')
    }

    It 'leaves the emitted order untouched when only the enablement half of the pair is built' {
        # Exactly one of the two ordered rules present: Enablement_EndUser_Assignment is built,
        # AuthenticationContext_EndUser_Assignment is not (no -AuthenticationContextId bound at all).
        # The ordering code guards with "$AcAt -ge 0 -and $EnAt -ge 0" before it swaps; drop that
        # guard and IndexOf's -1 for the missing rule addresses the LAST array element through
        # PowerShell's negative indexing instead of skipping the swap.
        $null = Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules Justification -Confirm:$false
        @($script:PatchOrder) | Should -Be @('Enablement_EndUser_Assignment')
    }

    It 'leaves the emitted order untouched when only the disabling authentication-context half of the pair is built, ahead of an unrelated trailing rule' {
        # The reverse of the case above: AuthenticationContext_EndUser_Assignment is built (disabling,
        # isEnabled false) and Enablement_EndUser_Assignment is not. New-OERPimRuleSet still emits
        # Expiration_Admin_Eligibility AFTER the authentication-context rule (from -EligibleDuration),
        # so the array has a genuine unrelated rule sitting at the last position -- unlike the
        # single-rule and same-position cases, IndexOf(-1) for the missing Enablement rule here
        # addresses a rule that is NOT the authentication-context rule itself. The guard
        # ("$AcAt -ge 0 -and $EnAt -ge 0") is what keeps this pairing from being touched; without it,
        # the swap logic silently exchanges the authentication-context rule with that unrelated
        # trailing rule. Should -Be (not a membership check) pins both the order and the count.
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId '' -EligibleDuration 30 -Confirm:$false
        @($script:PatchOrder) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Expiration_Admin_Eligibility')
    }
}
