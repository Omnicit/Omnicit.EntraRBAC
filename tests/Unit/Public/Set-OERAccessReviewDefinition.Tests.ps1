BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Set-OERAccessReviewDefinition' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        # Task 4b: -Id now routes through Resolve-OERAccessReviewDefinitionId before the GET/PUT. This
        # suite's fixture id 'd1' is not a GUID, so the real resolver would treat it as a display name
        # needing a Graph lookup -- passthrough it verbatim so every pre-existing test in this Describe
        # keeps exercising the read-modify-write logic rather than the resolver.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            # GET returns a full current definition
            return @{
                id                      = 'd1'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{
                    mailNotificationsEnabled        = $false
                    instanceDurationInDays          = 14
                    recommendationsEnabled          = $true
                }
                reviewers               = @(
                    @{ query = '/users/u1'; queryType = 'MicrosoftGraph' }
                )
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERAccessReviewDefinition { }
    }

    It 'PUT replaces displayName and preserves scope, settings, and reviewers (read-modify-write)' {
        Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1' -and
            $Body.displayName -eq 'New' -and
            $Body.scope.query -eq 'q' -and
            $Body.settings.instanceDurationInDays -eq 14 -and
            $Body.reviewers[0].query -eq '/users/u1'
        } -Times 1
    }

    It '-MailNotification sets mailNotificationsEnabled and preserves other settings keys' {
        Set-OERAccessReviewDefinition -Id 'd1' -MailNotification
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.settings.mailNotificationsEnabled -eq $true -and
            $Body.settings.instanceDurationInDays -eq 14 -and
            $Body.settings.recommendationsEnabled -eq $true
        } -Times 1
    }

    It '-WhatIf suppresses the PUT call' {
        Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT'
        } -Times 0
    }

    It '-Recurrence without -StartDate emits IncompleteRecurrence error and no PUT' {
        Set-OERAccessReviewDefinition -Id 'd1' -Recurrence Weekly -ErrorAction SilentlyContinue -ErrorVariable Errs
        $Errs[0].FullyQualifiedErrorId | Should -BeLike 'IncompleteRecurrence*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT'
        } -Times 0
    }

    It 'reports EndDate plus Occurrences as a non-terminating error' {
        $Threw = $false
        try {
            Set-OERAccessReviewDefinition -Id 'd1' -Recurrence Monthly -StartDate ([datetime]'2026-01-01') `
                -EndDate ([datetime]'2026-12-31') -Occurrences 4 `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch { $Threw = $true }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'MutuallyExclusiveParameter'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It '-Reviewer replaces reviewers in the PUT body' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERUserId { '11111111-1111-1111-1111-111111111111' }
        Set-OERAccessReviewDefinition -Id 'd1' -Reviewer '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.reviewers[0].query -eq '/users/11111111-1111-1111-1111-111111111111'
        } -Times 1
    }

    It 'surfaces a Graph GET failure (read-modify-write read) as a non-terminating error and emits nothing' {
        # Targets the RMW-read catch at Set-OERAccessReviewDefinition.ps1:186 -- the very first Graph
        # call the cmdlet makes, before any PUT is attempted. Guards two things the cmdlet must do on
        # a Graph failure: call Remove-OERErrorRecord (the mandatory bearer-token-hygiene line --
        # asserted via Should -Invoke, since a deleted line would otherwise pass unnoticed) and write
        # its OWN non-terminating record. Match the cmdlet-QUALIFIED ErrorId: PowerShell auto-records
        # the mock's throw into -ErrorVariable a dozen times before the catch runs, so matching the
        # bare Graph code would pass even with WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }

    It 'surfaces a Graph PUT failure as a non-terminating error and emits nothing' {
        # Targets the PUT-write catch at Set-OERAccessReviewDefinition.ps1:321. Two mocks scoped by
        # -ParameterFilter on $Method distinguish the successful RMW-read GET from the failing PUT --
        # the GET must succeed so the cmdlet reaches the PUT call at all.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id                      = 'd1'
                displayName             = 'Old'
                descriptionForAdmins    = 'a'
                descriptionForReviewers = 'b'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        } -ParameterFilter { $Method -ne 'PUT' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        } -ParameterFilter { $Method -eq 'PUT' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }

    It 'surfaces a Graph re-GET failure after a successful PUT as a non-terminating error and emits nothing' {
        # Targets the trailing re-GET catch at Set-OERAccessReviewDefinition.ps1:331. The RMW-read GET
        # and the trailing re-GET share the same $Method (default GET, unset) and the same $Uri, so
        # -ParameterFilter alone cannot tell them apart -- distinguish by CALL ORDER via a counter
        # closed over from the test script's scope, per the brief's call-count-sequencing guidance.
        $script:ReGetCallCount = 0
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            $script:ReGetCallCount++
            if ($script:ReGetCallCount -eq 1) {
                return @{
                    id                      = 'd1'
                    displayName             = 'Old'
                    descriptionForAdmins    = 'a'
                    descriptionForReviewers = 'b'
                    scope                   = @{ query = 'q' }
                    settings                = @{ instanceDurationInDays = 14 }
                }
            }
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }
}

Describe 'Set-OERAccessReviewDefinition accepts a display name (Task 4b)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERAccessReviewDefinition { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = '11111111-1111-1111-1111-111111111111'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        }
    }

    It '-Id resolves a display name to the definition id before the GET/PUT' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { '11111111-1111-1111-1111-111111111111' }
        Set-OERAccessReviewDefinition -Id 'Q3 Review' -DisplayName 'New' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId -Times 1 -Exactly -ParameterFilter {
            $DisplayName -eq 'Q3 Review'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'a GUID -Id is passed through with no Graph call from the resolver (regression)' {
        # Resolve-OERAccessReviewDefinitionId returns a GUID verbatim with no Graph call of its own
        # (Test-OERGuid short-circuits it), so a GUID caller must be byte-identical to the pre-4b
        # behaviour: still exactly two non-PUT calls (the read-modify-write read and the trailing
        # re-GET) plus one PUT, all against the same literal GUID-based URI, and the resolver itself
        # is left UNMOCKED here to prove the real implementation's GUID fast path, not a test double
        # standing in for it.
        Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'New' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
            $Method -ne 'PUT' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'the resolved id is used for the trailing re-GET as well as the PUT' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { '11111111-1111-1111-1111-111111111111' }
        Set-OERAccessReviewDefinition -Id 'Q3 Review' -DisplayName 'New' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
            $Method -ne 'PUT' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'reports AccessReviewDefinitionNotFound and does not GET/PUT when the name does not resolve' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        $Err = $null
        Set-OERAccessReviewDefinition -Id 'ghost' -DisplayName 'New' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionNotFound,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }
}

Describe 'Set-OERAccessReviewDefinition self-review mixing guard (Task 4c)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'refuses -SelfReview mixed with -Reviewer before any Graph call' {
        $Err = $null
        Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -SelfReview -Reviewer 'person18@example.com' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -ReviewerGroup' {
        $Err = $null
        Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -SelfReview -ReviewerGroup 'IT-Owners' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -Manager' {
        $Err = $null
        Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -SelfReview -Manager `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,Set-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'accepts -SelfReview combined with an explicit -Manager:$false (round-1 finding I-2)' {
        # Presence is not intent for a switch: -Manager:$false EXPLICITLY binds Manager (so
        # $PSBoundParameters.ContainsKey('Manager') is true), but its VALUE is false, so this is not
        # actually "combined with -Manager". A ContainsKey-keyed guard refused this call; the fix
        # must key on the bound VALUES instead.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = '11111111-1111-1111-1111-111111111111'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope { @{ Reviewers = @(); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null } }
        $Err = $null
        Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -SelfReview -Manager:$false `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PUT' } -Times 1 -Exactly
    }

    It 'accepts a splat carrying SelfReview = $false alongside -Reviewer (round-1 finding I-2)' {
        # Splatting with SelfReview = $false is the idiomatic way to build this call programmatically.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = '11111111-1111-1111-1111-111111111111'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
            @{ Reviewers = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null }
        }
        $Splat = @{
            Id         = '11111111-1111-1111-1111-111111111111'
            SelfReview = $false
            Reviewer   = @('person18@example.com')
            Confirm    = $false
        }
        $Err = $null
        Set-OERAccessReviewDefinition @Splat -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PUT' } -Times 1 -Exactly
    }
}

Describe 'Set-OERAccessReviewDefinition non-positive occurrence and duration guard (Task 4d)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        # A GET returning a real definition is required so the read-modify-write proceeds past the
        # AccessReviewDefinitionNotFound check into recurrence/settings building -- an empty GET mock
        # would make the cmdlet exit on that unrelated guard before ever reaching -Occurrences/
        # -DurationInDays, making the assertions below vacuous against the WRONG guard.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = '11111111-1111-1111-1111-111111111111'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        }
    }

    It '-Occurrences 0 fails bind-time validation on THIS cmdlet, not the private recurrence builder' {
        # A pure bind-time ParameterBindingException on the OUTER command does not populate its own
        # -ErrorVariable (verified empirically) -- only the try/catch $PSItem carries a record. Before
        # Task 4d, -Occurrences 0 bound fine here and only failed later, at the un-try'd
        # New-OERAccessReviewRecurrence call site; THAT failure, because it propagates out of a nested
        # command, DOES land in the outer call's -ErrorVariable, carrying the PRIVATE cmdlet's id. So
        # the try/catch $PSItem id alone is VACUOUS here -- PowerShell's propagation already reports it
        # as "...,Set-OERAccessReviewDefinition" even today, before any fix -- and the real
        # discriminator is that $Err carries no New-OERAccessReviewRecurrence record.
        $Threw = $false
        $CaughtId = $null
        $Err = $null
        try {
            Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' `
                -Recurrence Monthly -StartDate ([datetime]'2026-01-01') -Occurrences 0 `
                -Confirm:$false -ErrorAction Stop -ErrorVariable Err
        } catch { $Threw = $true; $CaughtId = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $CaughtId | Should -Match '^ParameterArgumentValidationError.*,Set-OERAccessReviewDefinition$'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OERAccessReviewRecurrence' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It '-DurationInDays 0 fails bind-time validation on THIS cmdlet' {
        # Unlike -Occurrences, -DurationInDays was never forwarded to a ValidateRange-bearing private
        # helper, so today -DurationInDays 0 does not throw AT ALL -- $Threw itself is the
        # discriminator; see the -Occurrences 0 test above for why the id alone would be vacuous there.
        $Threw = $false
        $CaughtId = $null
        try {
            Set-OERAccessReviewDefinition -Id '11111111-1111-1111-1111-111111111111' -DurationInDays 0 `
                -Confirm:$false -ErrorAction Stop
        } catch { $Threw = $true; $CaughtId = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $CaughtId | Should -Match '^ParameterArgumentValidationError.*,Set-OERAccessReviewDefinition$'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }
}

Describe 'Set-OERAccessReviewDefinition converter tagging (audit PR9)' {
    # The outer Describe block above mocks ConvertTo-OERAccessReviewDefinition away entirely, so the
    # output type-tag is never actually asserted end-to-end. This block leaves the converter unmocked
    # and drives it for real, mirroring New-OERAccessReviewDefinition.Tests.ps1's tagging assertion.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = 'd1'
                displayName             = 'New'
                descriptionForAdmins    = 'a'
                descriptionForReviewers = 'b'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
            }
        }
    }

    It 'tags the returned object as Omnicit.EntraRBAC.AccessReviewDefinition using the real converter' {
        $Result = Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New' -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDefinition'
        $Result.Id | Should -Be 'd1'
    }
}

Describe 'Set-OERAccessReviewDefinition unmodelled writable property carry-forward' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERAccessReviewDefinition { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                               = 'd1'
                displayName                      = 'Old'
                descriptionForAdmins             = 'oa'
                descriptionForReviewers          = 'or'
                status                           = 'InProgress'
                createdDateTime                  = '2026-01-01T00:00:00Z'
                lastModifiedDateTime             = '2026-02-01T00:00:00Z'
                createdBy                        = @{ id = 'u9'; displayName = 'Creator' }
                scope                            = @{ query = 'q' }
                settings                         = @{ instanceDurationInDays = 14 }
                reviewers                        = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' })
                additionalNotificationRecipients = @(
                    @{ notificationRecipientScope = @{ query = '/users/u2' }; notificationTemplateType = 'CompletedAdditionalRecipients' }
                )
                instanceEnumerationScope         = @{ query = '/groups'; queryType = 'MicrosoftGraph' }
            }
        }
    }

    It 'carries additionalNotificationRecipients forward on a displayName-only update' {
        Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.displayName -eq 'New' -and
            $Body.additionalNotificationRecipients[0].notificationTemplateType -eq 'CompletedAdditionalRecipients'
        } -Times 1
    }

    It 'carries instanceEnumerationScope forward on a displayName-only update' {
        Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and $Body.instanceEnumerationScope.query -eq '/groups'
        } -Times 1
    }

    It 'never PUTs a read-only property back to Graph' {
        Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'New'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'PUT' -and
            -not $Body.ContainsKey('id') -and
            -not $Body.ContainsKey('status') -and
            -not $Body.ContainsKey('createdDateTime') -and
            -not $Body.ContainsKey('lastModifiedDateTime') -and
            -not $Body.ContainsKey('createdBy')
        } -Times 1
    }
}

Describe 'Set-OERAccessReviewDefinition duration vocabulary alias (audit PR6)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERAccessReviewDefinition { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = 'd1'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
                reviewers               = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' })
            }
        }
    }

    It 'binds -DurationDays to instanceDurationInDays' {
        Set-OERAccessReviewDefinition -Id 'd1' -DurationDays 21 -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Body.settings.instanceDurationInDays -eq 21
        }
    }
}

Describe 'Set-OERAccessReviewDefinition ambiguous reviewer group' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC ConvertTo-OERAccessReviewDefinition { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return $null }
            return @{
                id                      = 'd1'
                displayName             = 'Old'
                descriptionForAdmins    = 'oa'
                descriptionForReviewers = 'or'
                scope                   = @{ query = 'q' }
                settings                = @{ instanceDurationInDays = 14 }
                reviewers               = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' })
            }
        }
    }

    It 'reports an ambiguous reviewer group as a NON-terminating error and does not PUT' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Caught = $null; $Err = $null
        try {
            Set-OERAccessReviewDefinition -Id 'd1' -ReviewerGroup 'Dup' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        } catch { $Caught = $PSItem }
        # A throw out of Resolve-OERReviewerScope would terminate this cmdlet mid read-modify-write.
        $Caught | Should -Be $null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Set-OERAccessReviewDefinition' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Set-OERAccessReviewDefinition' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        # An ambiguity is a bad argument, not a missing object.
        $Reported.CategoryInfo.Category | Should -Be 'InvalidArgument'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PUT' } -Times 0
    }

    It 'still reports the existing GroupNotFound error for a genuine no-match' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { $null }
        $Err = $null
        Set-OERAccessReviewDefinition -Id 'd1' -ReviewerGroup 'missing' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,Set-OERAccessReviewDefinition' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Set-OERAccessReviewDefinition' }).Count | Should -Be 0
        # The pre-existing not-found path keeps ObjectNotFound: only the ambiguity branch is new.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,Set-OERAccessReviewDefinition' })[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PUT' } -Times 0
    }
}
