BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    It 'errors when Graph lists no policy for the group' {
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
        $Message | Should -Not -BeLike '*eligibility*'
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

    It 'reports a failed group resolver as itself, exactly once, and never as GroupNotFound' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'transport failure' }
        $Error.Clear()
        Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 -ErrorAction SilentlyContinue | Out-Null
        # Supersedes 'leaves no record in $Error when the group resolver fails', which pinned the old
        # swallow-then-GroupNotFound path. The failure is now reported as itself and once: exactly one
        # record remains, the failure and not a GroupNotFound. This is the CONTRACT, not the scrub
        # proof: the catch re-publishes the caught record, so the same single record is there whether
        # or not Remove-OERErrorRecord ran. The scrub has its own test below.
        @($Error).Count | Should -Be 1
        $Error[0].Exception.Message | Should -Match 'transport failure'
        $Error[0].FullyQualifiedErrorId | Should -Not -Match 'GroupNotFound'
    }

    It 'scrubs the failed group resolver record before re-publishing it (bearer hygiene)' {
        # The catch re-publishes the caught record with $PSCmdlet.WriteError($PSItem), the same shape as a
        # bare re-throw: the same exception instance reaches $Error with or without the scrub, so an
        # $Error-based proof passes with the Remove-OERErrorRecord line deleted. The prescribed proof
        # (rationale.md, #bearer-scrub-tests) guards the call directly: mock it and require exactly
        # one call, filtered to THIS record so no other catch on the path can satisfy it.
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Set-OERGroupPimPolicy -Group 'grp' -ActivationMaxHours 4 -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'transport failure'
        }
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

    Context 'every $Reported.Contains rule-id literal that gates the summary is pinned (audit prom-pimpolicy-rule-literals-partially-unpinned)' {
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
        # the far side of the module, not Set-OERGroupPimPolicy's own $Reported.Contains('<literal>')
        # line ($Reported is $Sent without a rule put back to its live value; the gate was on $Sent
        # before the pair put-back). The two are independent strings and a typo in either alone
        # still passes such a test.
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
                "Set-OERGroupPimPolicy gates `$Patched.$Property on `$Reported.Contains('$Literal'), and " +
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
            # input untouched); a name resolves through the map; anything else is not found, thrown as
            # the record the real Resolve-OERPrincipal throws for a value that matches nothing.
            Mock -ModuleName $script:moduleName Resolve-OERPrincipal {
                $Map = @{
                    'person1@example.com' = '11111111-1111-1111-1111-111111111111'
                    'person2@example.com' = '22222222-2222-2222-2222-222222222222'
                    'pim-approvers'       = '33333333-3333-3333-3333-333333333333'
                }
                $Kind = if ($User) { 'User' } else { 'Group' }
                $Name = if ($User) { $User } else { $Group }
                $Id = if ($Name -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Name } else { $Map[$Name] }
                if (-not $Id) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("$Kind '$Name' was not found."), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Name)
                }
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

    Context 'an approver lookup: missing, ambiguous and failed are three outcomes (Sprint 8 step 3, BL-14)' {
        # The real Resolve-OERApproverInput and Resolve-OERPrincipal run here; only the lookups under
        # them answer. Approvers are resolved before the target group, so the filtered mocks answer
        # only an approver value, and the target 'gid-1' keeps the Describe's own mock -- which these
        # tests also prove is never reached. Each test filters -ErrorVariable to the records this
        # cmdlet wrote itself (FQID ending in ',Set-OERGroupPimPolicy'), since a record thrown inside a
        # nested command is collected there as well.
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'missing-approvers' } { $null }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'dup-approvers' } {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, " +
                        '22222222-2222-2222-2222-222222222222). Re-run with the object id instead of the display name.'),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'dup-approvers')
            }
            Mock -ModuleName $script:moduleName Resolve-OERUserId -ParameterFilter { $UserPrincipalName -eq 'person9@example.com' } {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
            }
        }

        It 'reports an approver that matches nothing as ApproverNotFound, with the message, category and target it always had' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverGroup 'missing-approvers' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERGroupPimPolicy' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'ApproverNotFound,Set-OERGroupPimPolicy'
            $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Own[0].TargetObject | Should -Be 'missing-approvers'
            $Own[0].Exception.Message | Should -Be "Group 'missing-approvers' was not found."
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0 -ParameterFilter { $DisplayName -eq 'gid-1' }
        }

        It 'reports an ambiguous approver name as AmbiguousApproverName naming the candidates, never as ApproverNotFound' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverGroup 'dup-approvers' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERGroupPimPolicy' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'AmbiguousApproverName,Set-OERGroupPimPolicy'
            $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Own[0].TargetObject | Should -Be 'dup-approvers'
            $Own[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $Own[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0 -ParameterFilter { $DisplayName -eq 'gid-1' }
        }

        It 'reports a failed approver lookup as itself, once, never as ApproverNotFound' {
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person9@example.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERGroupPimPolicy' })
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied,Set-OERGroupPimPolicy'
            $Own[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
            $Own[0].Exception.Message | Should -Match 'Insufficient privileges'
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0 -ParameterFilter { $DisplayName -eq 'gid-1' }
        }

        It 'scrubs a failed approver lookup before it publishes it as itself' {
            Mock -ModuleName $script:moduleName Resolve-OERApproverInput {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
            }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            $Err = $null
            Set-OERGroupPimPolicy -Group 'gid-1' -ApproverUser 'person9@example.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            # Reached: the catch published the record as itself.
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERGroupPimPolicy' }).Count | Should -Be 1
            # A prefix match: $PSCmdlet.WriteError appends ',<cmdlet>' to this same record, in place,
            # before the filter is evaluated.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record -and [string]$Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' -and
                $Record.Exception.Message -like '*Insufficient privileges*'
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

    It 'case E: an explicit enablement list without MFA needs no reconcile read' {
        $Warn = $null
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -WarningVariable Warn -WarningAction SilentlyContinue
        # Positive anchor: prove the call actually reached Graph before asserting what it did NOT read.
        @($script:Patched) | Where-Object { $_.id -eq 'AuthenticationContext_EndUser_Assignment' } |
            Should -Not -BeNullOrEmpty
        # Case E runs no reconcile. Both halves of the pair are sent, so its ONE read is the first
        # half, the enablement rule, read after every rule was confirmed so that it could be put back
        # (see 'MFA and authentication context pair, one half rejected'). A mutation firing arm C reads
        # the AuthenticationContext rule, which the total of one excludes; one firing arm B reads the
        # same enablement rule (the put-back then reuses it) and is told apart by the reconcile
        # warning, since this call writes none.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Method -ne 'PATCH'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like '*rules/Enablement_EndUser_Assignment'
        }
        @($Warn).Count | Should -Be 0
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
        $Warn = $null
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId '' `
            -ActivationEnabledRules MultiFactorAuthentication -Confirm:$false -WarningAction SilentlyContinue -WarningVariable Warn
        # The one read is the first half of the pair, the disabling context rule, read after every
        # rule was confirmed so that it could be put back; a reconcile would also have warned.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter { $Method -ne 'PATCH' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like '*rules/AuthenticationContext_EndUser_Assignment'
        }
        @($Warn).Count | Should -Be 0
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
        $Warn = $null
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -WarningAction SilentlyContinue -WarningVariable Warn
        # The one read is the first half of the pair, the enablement rule, read after every rule was
        # confirmed so that it could be put back; a reconcile would also have warned.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter { $Method -ne 'PATCH' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like '*rules/Enablement_EndUser_Assignment'
        }
        @($Warn).Count | Should -Be 0
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

Describe 'Set-OERGroupPimPolicy MFA and authentication context pair, one half rejected' {
    # Modelled on Set-OERDirectoryRoleManagementPolicy's Context 'MFA and authentication context
    # rules sent together, and one of them rejected'. The authentication-context rule and the
    # activation enablement rule together decide whether activation requires multi-factor
    # authentication or an authentication context, so when Microsoft Graph accepts the first of the
    # two (in patch order) and rejects the second, the first is PATCHed straight back to its live
    # value. $script:Calls records every request, reads and PATCHes alike, in the order sent.
    BeforeAll {
        # A rule as JSON with its keys sorted at every level, so a PATCH body can be compared with the
        # live rule it must equal whatever order either hashtable enumerates its keys in.
        function ConvertTo-CanonicalJson ($Value) {
            function ConvertTo-SortedNode ($Node) {
                if ($Node -is [System.Collections.IDictionary]) {
                    $Sorted = [ordered]@{}
                    foreach ($Key in @($Node.Keys | Sort-Object)) { $Sorted[[string]$Key] = ConvertTo-SortedNode $Node[$Key] }
                    return $Sorted
                }
                if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
                    return , @(foreach ($Item in $Node) { ConvertTo-SortedNode $Item })
                }
                $Node
            }
            ConvertTo-SortedNode $Value | ConvertTo-Json -Depth 20 -Compress
        }
        # The live rule as it must be sent back: as read, without the read-only '@odata.context'.
        function Get-TestExpectedPutBack ([hashtable]$Live) {
            $Expected = $Live.Clone()
            $Expected.Remove('@odata.context')
            $Expected
        }
        function Get-TestCallLine { @($script:Calls | ForEach-Object { '{0} {1}' -f $_.Method, $_.RuleId }) }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'p1' }
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
            [pscustomobject]@{ AuthenticationContextId = 'c2'; DisplayName = 'Require a compliant device'; IsAvailable = $true }
        }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:RejectRuleId = @()
        # A rule id here is accepted on its first PATCH and rejected on every later one.
        $script:RejectRepeatRuleId = @()
        $script:FailReadRuleId = @()
        $script:LiveEnablement = @{
            '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#policies/roleManagementPolicies/p1/rules/$entity'
            '@odata.type'    = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id               = 'Enablement_EndUser_Assignment'
            enabledRules     = @('MultiFactorAuthentication', 'Justification')
        }
        $script:LiveContext = @{
            '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#policies/roleManagementPolicies/p1/rules/$entity'
            '@odata.type'    = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
            id               = 'AuthenticationContext_EndUser_Assignment'
            isEnabled        = $true
            claimValue       = 'c1'
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            param([string]$Method = 'GET', [string]$Uri, $Body)
            $RuleId = ($Uri -split '/')[-1]
            $script:Calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; RuleId = $RuleId; Body = $Body })
            if ($Method -eq 'PATCH') {
                if ($script:RejectRuleId -contains $RuleId) { throw "Graph rejected rule '$RuleId'." }
                if ($script:RejectRepeatRuleId -contains $RuleId -and
                    @($script:Calls | Where-Object { $_.Method -eq 'PATCH' -and $_.RuleId -eq $RuleId }).Count -gt 1) {
                    throw "Graph rejected the repeated PATCH of rule '$RuleId'."
                }
                return @{}
            }
            if ($script:FailReadRuleId -contains $RuleId) { throw "Graph refused the read of rule '$RuleId'." }
            if ($RuleId -eq 'Enablement_EndUser_Assignment') { return $script:LiveEnablement }
            if ($RuleId -eq 'AuthenticationContext_EndUser_Assignment') { return $script:LiveContext }
            @{}
        }
    }

    It 'explicit pair, context enabled: reads the enablement rule once before any PATCH and puts it back when the context rule is rejected' {
        $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
        $Result = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
        # ONE read of the first half, before the first PATCH; then the pair in patch order and exactly
        # one compensating PATCH, of the first rule.
        @(Get-TestCallLine) | Should -Be @(
            'GET Enablement_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
        )
        @($script:Calls[1].Body.enabledRules) | Should -Be @('Justification')
        $script:Calls[3].Uri | Should -Be $script:Calls[1].Uri
        (ConvertTo-CanonicalJson $script:Calls[3].Body) | Should -Be (ConvertTo-CanonicalJson (Get-TestExpectedPutBack $script:LiveEnablement))
        $Result.Applied | Should -BeFalse
        @($Result.FailedRules) | Should -Be @('AuthenticationContext_EndUser_Assignment')
        # The rule put back is not reported as changed; the rejected one, which was sent, still is.
        $Result.PSObject.Properties.Name | Should -Not -Contain 'ActivationEnabledRules'
        $Result.PSObject.Properties.Name | Should -Contain 'AuthenticationContextId'
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Rejected[0].Exception.Message | Should -BeLike "*Rule 'Enablement_EndUser_Assignment', which Microsoft Graph had accepted, was put back to its value before this call*"
        $Rejected[0].Exception.Message | Should -BeLike '*activation keeps the protection it had before the call.*'
        ($Warn -join ' ') | Should -BeLike "*Rule 'AuthenticationContext_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'AuthenticationContext_EndUser_Assignment'.*"
    }

    It 'reconcile ClearMfa: puts the enablement rule back with the rule the reconcile already read, read once' {
        $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
        $Result = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like '*rules/Enablement_EndUser_Assignment'
        }
        @(Get-TestCallLine) | Should -Be @(
            'GET Enablement_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
        )
        (ConvertTo-CanonicalJson $script:Calls[3].Body) | Should -Be (ConvertTo-CanonicalJson (Get-TestExpectedPutBack $script:LiveEnablement))
        @($Result.FailedRules) | Should -Be @('AuthenticationContext_EndUser_Assignment')
        $Result.PSObject.Properties.Name | Should -Not -Contain 'ActivationEnabledRules'
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Rejected[0].Exception.Message | Should -BeLike "*Rule 'Enablement_EndUser_Assignment', which Microsoft Graph had accepted, was put back*"
    }

    It 'reconcile DisableAuthContext: puts the context rule back with the rule the reconcile already read, read once' {
        $script:RejectRuleId = @('Enablement_EndUser_Assignment')
        $Result = Set-OERGroupPimPolicy -Group 'g' -ActivationEnabledRules MultiFactorAuthentication -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -ne 'PATCH' -and $Uri -like '*rules/AuthenticationContext_EndUser_Assignment'
        }
        @(Get-TestCallLine) | Should -Be @(
            'GET AuthenticationContext_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
        )
        $script:Calls[1].Body.isEnabled | Should -BeFalse
        (ConvertTo-CanonicalJson $script:Calls[3].Body) | Should -Be (ConvertTo-CanonicalJson (Get-TestExpectedPutBack $script:LiveContext))
        @($Result.FailedRules) | Should -Be @('Enablement_EndUser_Assignment')
        $Result.PSObject.Properties.Name | Should -Not -Contain 'AuthenticationContextId'
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Rejected[0].Exception.Message | Should -BeLike "*Rule 'AuthenticationContext_EndUser_Assignment', which Microsoft Graph had accepted, was put back*"
    }

    It 'says activation may now require neither control, and still reports the first rule, when the put-back is rejected too' {
        $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
        $script:RejectRepeatRuleId = @('Enablement_EndUser_Assignment')
        $Result = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
        @(Get-TestCallLine) | Should -Be @(
            'GET Enablement_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
        )
        $Result.PSObject.Properties.Name | Should -Contain 'ActivationEnabledRules'
        @($Result.ActivationEnabledRules) | Should -Be @('Justification')
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Message = $Rejected[0].Exception.Message
        $Message | Should -BeLike "*Rule 'Enablement_EndUser_Assignment' had been accepted, and putting it back to its value before this call failed too (Graph rejected the repeated PATCH of rule 'Enablement_EndUser_Assignment'.)*"
        $Message | Should -BeLike '*activation may now require neither multi-factor authentication nor an authentication context*'
        $Message | Should -BeLike '*Run the same command again, or run Set-OERGroupPimPolicy with -ActivationEnabledRules or -AuthenticationContextId set to the protection this group needs.*'
        $Message | Should -Not -BeLike '*keeps the protection*'
        ($Warn -join ' ') | Should -BeLike "*Rule 'Enablement_EndUser_Assignment' of PIM policy 'p1' could not be put back to its value before this call*"
    }

    It 'writes a failed first-half read before any PATCH: -WarningAction Stop stops there, with nothing sent' {
        $script:FailReadRuleId = @('Enablement_EndUser_Assignment')
        { Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false -WarningAction Stop } |
            Should -Throw -ExpectedMessage "*Could not read the live rule 'Enablement_EndUser_Assignment' of PIM policy 'p1' before the update*"
        @(Get-TestCallLine) | Should -Be @('GET Enablement_EndUser_Assignment')
    }

    It 'sends both rules after a failed first-half read, sends no put-back, names the unread value and scrubs the failed read' {
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $script:FailReadRuleId = @('Enablement_EndUser_Assignment')
        $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
        $null = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
        @(Get-TestCallLine) | Should -Be @(
            'GET Enablement_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
        )
        @($Warn)[0] | Should -Be ("Could not read the live rule 'Enablement_EndUser_Assignment' of PIM policy 'p1' before the update, so it " +
            "cannot be put back should Microsoft Graph reject 'AuthenticationContext_EndUser_Assignment': Graph refused the read of rule 'Enablement_EndUser_Assignment'.")
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Rejected[0].Exception.Message | Should -BeLike '*its value before this call was not read*'
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq "Graph refused the read of rule 'Enablement_EndUser_Assignment'."
        }
    }

    It 'sends no put-back when the FIRST half is rejected' {
        $script:RejectRuleId = @('Enablement_EndUser_Assignment')
        $Result = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
        @(Get-TestCallLine) | Should -Be @(
            'GET Enablement_EndUser_Assignment'
            'PATCH Enablement_EndUser_Assignment'
            'PATCH AuthenticationContext_EndUser_Assignment'
        )
        @($Result.FailedRules) | Should -Be @('Enablement_EndUser_Assignment')
        $Rejected = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyRulesRejected,Set-OERGroupPimPolicy' })
        $Rejected.Count | Should -Be 1
        $Rejected[0].Exception.Message | Should -Not -BeLike '*put back*'
    }

    It 'reads no first half and sends nothing under -WhatIf' {
        $Result = Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -WhatIf
        $Result | Should -BeNullOrEmpty
        # Reached: the context was validated, so the call got as far as the confirmations.
        Should -Invoke -ModuleName $script:moduleName Get-OERAuthenticationContext -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'reads no first half and sends no put-back when the operator declines the second half' {
        $Scenario = {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                $script:TestCalls = [System.Collections.Generic.List[string]]::new()
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Resolve-OERGroupId -Value { 'g1' }
                Set-Item -Path function:script:Get-OERPimGroupPolicyId -Value { 'p1' }
                Set-Item -Path function:script:Get-OERAuthenticationContext -Value {
                    [CmdletBinding()] param()
                    [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
                }
                Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                    param([string]$Method = 'GET', [string]$Uri, $Body)
                    $script:TestCalls.Add(('{0} {1}' -f $Method, ($Uri -split '/')[-1]))
                    if ($Method -eq 'PATCH') { return @{} }
                    @{ id = ($Uri -split '/')[-1]; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                }
            }
            Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm `
                -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            & $Module { $script:TestCalls.ToArray() }
        }
        # Accept the enablement rule (prompted first), decline the context rule.
        $Run = Invoke-OERWithConfirmAnswer -AnswerSequence '&Yes', '&No' -Script $Scenario
        $Run.Prompts.Count | Should -Be 2
        $Run.Prompts[0] | Should -Match 'Enablement_EndUser_Assignment'
        $Run.Prompts[1] | Should -Match 'AuthenticationContext_EndUser_Assignment'
        @($Run.Output) | Should -Be @('PATCH Enablement_EndUser_Assignment')
    }
}

Describe 'Set-OERGroupPimPolicy: no warning stops an update between its first PATCH and its last put-back (BL-10)' {
    # Send-OERPimRulePatch returns every message about a rejected rule, and about a put-back that
    # failed; the cmdlet writes them only after the last PATCH and the put-back were sent. So a caller
    # running with -WarningAction Stop is stopped by the FIRST message, which is written after every
    # request, and never half-way through the rule set. Proven in the two forms a caller can take:
    # inside a try, and in a script with no try (where the stop ends the whole script, so what was
    # sent is read from a log file the transport stub appends to, not from anything the script prints).
    # Both scenarios write NO warning before the first PATCH: an explicit pair has no reconcile, and
    # Get-OERAuthenticationContext lists c1 as published, so there is no validation warning either.
    # That is proven too: the stopping message is the rejection of the rule, not an earlier one.
    # The cmdlet call as a splat for the try and as text for the runspace, so the two forms stay side
    # by side. Expected holds "<METHOD> <rule id>" in the order the requests are sent. Defined here,
    # in the discovery phase, since -TestCases is read then.
    $StopCases = @(
        @{
            Scenario = 'explicit pair, the context rule rejected'
            Splat    = @{ AuthenticationContextId = 'c1'; ActivationEnabledRules = 'Justification' }
            ArgText  = "-AuthenticationContextId 'c1' -ActivationEnabledRules Justification"
            Reject   = 'AuthenticationContext_EndUser_Assignment'
            Expected = @(
                'GET Enablement_EndUser_Assignment'
                'PATCH Enablement_EndUser_Assignment'
                'PATCH AuthenticationContext_EndUser_Assignment'
                'PATCH Enablement_EndUser_Assignment'
            )
        }
        @{
            Scenario = 'three rules, the first rejected'
            Splat    = @{ ActivationMaxHours = 4; ActiveEnabledRules = 'Justification'; EligibleAlertRecipient = 'person18@example.com' }
            ArgText  = "-ActivationMaxHours 4 -ActiveEnabledRules Justification -EligibleAlertRecipient 'person18@example.com'"
            Reject   = 'Expiration_EndUser_Assignment'
            Expected = @(
                'PATCH Expiration_EndUser_Assignment'
                'PATCH Enablement_Admin_Assignment'
                'PATCH Notification_Admin_Admin_Eligibility'
            )
        }
    )

    BeforeAll {
        function Get-TestCallLine { @($script:Calls | ForEach-Object { '{0} {1}' -f $_.Method, $_.RuleId }) }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'p1' }
        Mock -ModuleName $script:moduleName Get-OERAuthenticationContext {
            [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
        }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:RejectRuleId = @()
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            param([string]$Method = 'GET', [string]$Uri, $Body)
            $RuleId = ($Uri -split '/')[-1]
            $script:Calls.Add([pscustomobject]@{ Method = $Method; RuleId = $RuleId; Body = $Body })
            if ($Method -eq 'PATCH') {
                if ($script:RejectRuleId -contains $RuleId) { throw "Graph rejected rule '$RuleId'." }
                return @{}
            }
            @{ id = $RuleId; enabledRules = @('MultiFactorAuthentication', 'Justification') }
        }
    }

    Context 'inside a try' {
        It 'explicit pair: is stopped only after both rules and the put-back of the first were sent' {
            $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
            $Caught = $null
            try {
                Set-OERGroupPimPolicy -Group 'g' -AuthenticationContextId 'c1' -ActivationEnabledRules Justification -Confirm:$false `
                    -WarningAction Stop -ErrorAction SilentlyContinue
            } catch {
                $Caught = $PSItem
            }
            # The first-half read, the pair in patch order, then the put-back of the first rule LAST.
            @(Get-TestCallLine) | Should -Be @(
                'GET Enablement_EndUser_Assignment'
                'PATCH Enablement_EndUser_Assignment'
                'PATCH AuthenticationContext_EndUser_Assignment'
                'PATCH Enablement_EndUser_Assignment'
            )
            @($script:Calls[1].Body.enabledRules) | Should -Be @('Justification')
            @($script:Calls[3].Body.enabledRules) | Should -Be @('MultiFactorAuthentication', 'Justification') -Because 'the last request puts the live rule back'
            # The stop came from a warning, and from the rejection of the context rule in particular:
            # nothing was written before it, and it was written after the put-back.
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
            $Caught.Exception.Message | Should -BeLike "*Rule 'AuthenticationContext_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'AuthenticationContext_EndUser_Assignment'.*"
        }

        It 'three rules, the first rejected: is stopped only after all three were sent' {
            $script:RejectRuleId = @('Expiration_EndUser_Assignment')
            $Caught = $null
            try {
                Set-OERGroupPimPolicy -Group 'g' -ActivationMaxHours 4 -ActiveEnabledRules Justification -EligibleAlertRecipient 'person18@example.com' -Confirm:$false `
                    -WarningAction Stop -ErrorAction SilentlyContinue
            } catch {
                $Caught = $PSItem
            }
            @(Get-TestCallLine) | Should -Be @(
                'PATCH Expiration_EndUser_Assignment'
                'PATCH Enablement_Admin_Assignment'
                'PATCH Notification_Admin_Admin_Eligibility'
            )
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
            $Caught.Exception.Message | Should -BeLike "*Rule 'Expiration_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'Expiration_EndUser_Assignment'.*"
        }

        It '<Scenario>: the control without Stop sends the same requests and writes the rejection as its FIRST warning' -TestCases $StopCases {
            # Without this, the two tests above could pass for a call that never wrote that message.
            $script:RejectRuleId = @($Reject)
            $null = Set-OERGroupPimPolicy -Group 'g' @Splat -Confirm:$false -WarningAction SilentlyContinue -WarningVariable Warn -ErrorAction SilentlyContinue
            @(Get-TestCallLine) | Should -Be $Expected
            @($Warn).Count | Should -BeGreaterThan 0
            @($Warn)[0] | Should -Be "Rule '$Reject' of PIM policy 'p1' was not applied: Graph rejected rule '$Reject'."
        }
    }

    Context 'in a script with no try' {
        BeforeAll {
            # The script runs in a runspace through Invoke-OERWithConfirmAnswer, so it is transported as
            # text and installs its own fakes in ITS copy of the module scope. The transport stub
            # appends "<METHOD> <rule id>" to a log file whose path is substituted into the text, and
            # throws for the rejected rule exactly as the real wrapper does. The call stands in no try.
            # The control removes the five private stubs again and counts what still resolves; the stub
            # of the exported Get-OERAuthenticationContext is left out, since the module's exported copy
            # would still resolve after its removal.
            $script:NewNoTryScenario = {
                param([string]$Log, [string]$Reject, [string]$ArgText, [string]$Stop)
                [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value { 'g1' }
    Set-Item -Path function:script:Get-OERPimGroupPolicyId -Value { 'p1' }
    Set-Item -Path function:script:Get-OERAuthenticationContext -Value {
        [CmdletBinding()] param()
        [pscustomobject]@{ AuthenticationContextId = 'c1'; DisplayName = 'Require MFA'; IsAvailable = $true }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        $RuleId = ($Uri -split '/')[-1]
        Add-Content -LiteralPath '#LOG#' -Value "$Method $RuleId"
        if ($Method -eq 'PATCH') {
            if ($RuleId -eq '#REJECT#') { throw "Graph rejected rule '$RuleId'." }
            return @{}
        }
        @{ id = $RuleId; enabledRules = @('MultiFactorAuthentication', 'Justification') }
    }
}
$Result = Set-OERGroupPimPolicy -Group 'g' #ARGS# -Confirm:$false #STOP#
"REACHED:$($Result.Applied)"
& $Module {
    Remove-Item function:Initialize-OERAuth
    Remove-Item function:Remove-OERErrorRecord
    Remove-Item function:Resolve-OERGroupId
    Remove-Item function:Get-OERPimGroupPolicyId
    Remove-Item function:Invoke-OERGraphRequest
    "STUBS:$(@('Initialize-OERAuth', 'Remove-OERErrorRecord', 'Resolve-OERGroupId', 'Get-OERPimGroupPolicyId', 'Invoke-OERGraphRequest' | Where-Object { Get-Command -Name $PSItem -CommandType Function -ErrorAction Ignore }).Count)"
}
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#REJECT#', $Reject).Replace('#ARGS#', $ArgText).Replace('#STOP#', $Stop))
            }
            function Get-TestLoggedLine ([string]$Log) {
                if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
            }
        }

        It '<Scenario>: -WarningAction Stop ends the script only after every request was sent, the put-back included' -TestCases $StopCases {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Scenario = & $script:NewNoTryScenario -Log $Log -Reject $Reject -ArgText $ArgText -Stop '-WarningAction Stop'
            # Measured: a stop outside any try ends the whole script, so the runner throws to its caller.
            { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } |
                Should -Throw -ExpectedMessage "*WarningPreference*Rule '$Reject' of PIM policy 'p1' was not applied*"
            @(Get-TestLoggedLine -Log $Log) | Should -Be $Expected
        }

        It '<Scenario>: the control without Stop reaches the end of the script with the same requests' -TestCases $StopCases {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Scenario = & $script:NewNoTryScenario -Log $Log -Reject $Reject -ArgText $ArgText -Stop ''
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
            # The sentinel and the stub removal prove the script ran to its end; Applied is False since
            # a rule was rejected, so the rejection path was reached.
            ($Run.Output -join '|') | Should -Be 'REACHED:False|STUBS:0|END'
            @(Get-TestLoggedLine -Log $Log) | Should -Be $Expected
            @($Run.Warnings)[0] | Should -Be "Rule '$Reject' of PIM policy 'p1' was not applied: Graph rejected rule '$Reject'."
        }
    }
}
