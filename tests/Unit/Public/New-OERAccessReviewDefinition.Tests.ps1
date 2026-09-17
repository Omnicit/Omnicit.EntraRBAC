BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERAccessReviewDefinition' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'; FailedKind = $null; FailedValue = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'new-def'; displayName = 'Q3'; status = 'NotStarted' }
        }
    }

    It 'POSTs a single-stage definition with the verified scope and reviewer shapes' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Reviewer '11111111-1111-1111-1111-111111111111' `
            -Recurrence Quarterly -StartDate ([datetime]'2026-07-05') -DurationInDays 14
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions' -and
            $Body.scope.query -like "*/entitlementManagement/assignments*accessPackage/id eq 'ap'*" -and
            $Body.reviewers[0].query -eq '/users/11111111-1111-1111-1111-111111111111' -and
            $Body.settings.instanceDurationInDays -eq 14 -and
            $Body.settings.recurrence.pattern.type -eq 'absoluteMonthly' -and
            $Body.settings.recurrence.pattern.interval -eq 3
        }
    }

    It 'POSTs stageSettings and omits top-level reviewers for multi-stage' {
        $Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Stage $Stage `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationInDays 7
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Body.stageSettings.Count -ge 1 -and
            -not $Body.ContainsKey('reviewers') -and
            $Body.stageSettings[0].stageId -eq '1' -and
            $Body.stageSettings[0].durationInDays -eq 7
        }
    }

    It 'emits a non-terminating error and does not POST when reviewer resolution fails' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope { @{ Reviewers=@(); FallbackReviewers=@(); FailedKind='User'; FailedValue='ghost@contoso.com' } }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Reviewer 'ghost@contoso.com' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }

    It 'forwards EndDate as an endDate range in the POST body' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence Monthly -StartDate ([datetime]'2026-07-05') -EndDate ([datetime]'2026-12-31')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Body.settings.recurrence.range.type -eq 'endDate' -and
            $null -ne $Body.settings.recurrence.range.endDate
        }
    }

    It 'honors -WhatIf (no POST)' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationInDays 7 -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'sets defaultDecisionEnabled to true when -DefaultDecision Deny and false by default' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DefaultDecision Deny
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Body.settings.defaultDecisionEnabled -eq $true -and
            $Body.settings.defaultDecision -eq 'Deny'
        }

        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Body.settings.defaultDecisionEnabled -eq $false -and
            $Body.settings.defaultDecision -eq 'None'
        }
    }

    It 'omits settings.recurrence when -Recurrence OneTime' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            -not $Body.settings.ContainsKey('recurrence')
        }
    }

    It 'returns a tagged AccessReviewDefinition object' {
        $Result = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDefinition'
        $Result.Id | Should -Be 'new-def'
    }

    It 'emits a non-terminating error when scope target resolution fails' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = $null; AssignmentPolicyId = $null; CatalogId = $null; FailedKind = 'AccessPackage'; FailedValue = 'ghost' }
        }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'ghost' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorVariable ErrVar -ErrorAction SilentlyContinue
        $ErrVar | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'surfaces the derived-catalog failure without claiming a catalog by the package name is missing' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{
                AccessPackageId = $null; AssignmentPolicyId = $null; CatalogId = $null
                FailedKind = 'Catalog'; FailedValue = 'AP-Sales'
                FailedErrorId = 'CatalogDerivationFailed'
                FailedMessage = "Could not derive the catalog from access package 'AP-Sales'."
            }
        }
        New-OERAccessReviewDefinition -DisplayName 'R' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -Reviewer 'anna@contoso.com' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'CatalogDerivationFailed'
        $Joined | Should -Not -Match 'CatalogNotFound'
        @($Err).Exception.Message -join ' ' | Should -Match 'derive the catalog'
    }

    It 'reports EndDate plus Occurrences as a non-terminating error' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'should-not-happen' } }
        $Threw = $false
        try {
            New-OERAccessReviewDefinition -DisplayName 'R' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' `
                -Reviewer 'anna@contoso.com' -Recurrence Monthly -StartDate ([datetime]'2026-01-01') `
                -EndDate ([datetime]'2026-12-31') -Occurrences 4 `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch { $Threw = $true }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'MutuallyExclusiveParameter'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'emits NoReviewer error and no POST when no reviewer params are supplied (Fix 2)' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorVariable ErrVar -ErrorAction SilentlyContinue
        $ErrVar | Should -Not -BeNullOrEmpty
        $ErrVar[0].FullyQualifiedErrorId | Should -BeLike '*NoReviewer*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }

    It '-SelfReview alone succeeds and POSTs reviewers as empty array (Fix 2)' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope { @{ Reviewers=@(); FallbackReviewers=@(); FailedKind=$null; FailedValue=$null } }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.reviewers.Count -eq 0
        }
    }

    It 'emits ManagerFallbackRequired error and no POST when -Manager has no fallback' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
            @{ Reviewers=@(@{ query='./manager'; queryType='MicrosoftGraph'; queryRoot='decisions' }); FallbackReviewers=@(); FailedKind=$null; FailedValue=$null }
        }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Manager `
            -Recurrence Quarterly -StartDate ([datetime]'2026-07-05') -ErrorVariable ErrVar -ErrorAction SilentlyContinue
        $ErrVar | Should -Not -BeNullOrEmpty
        $ErrVar[0].FullyQualifiedErrorId | Should -BeLike '*ManagerFallbackRequired*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }

    It '-Manager with a fallback reviewer succeeds and POSTs the manager scope plus fallbackReviewers' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
            @{ Reviewers=@(@{ query='./manager'; queryType='MicrosoftGraph'; queryRoot='decisions' }); FallbackReviewers=@(@{ query='/users/22222222-2222-2222-2222-222222222222'; queryType='MicrosoftGraph' }); FailedKind=$null; FailedValue=$null }
        }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Manager -FallbackReviewer '22222222-2222-2222-2222-222222222222' `
            -Recurrence Quarterly -StartDate ([datetime]'2026-07-05')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.reviewers[0].query -eq './manager' -and
            $Body.fallbackReviewers.Count -eq 1
        }
    }

    It 'emits InvalidStage error and no POST when a bogus stage object is supplied (Fix 3)' {
        $BogusStage = [pscustomobject]@{ foo = 1 }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Stage $BogusStage `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorVariable ErrVar -ErrorAction SilentlyContinue
        $ErrVar | Should -Not -BeNullOrEmpty
        $ErrVar[0].FullyQualifiedErrorId | Should -BeLike '*InvalidStage*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,New-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }

    Context 'duration vocabulary alias (audit PR6)' {
        It 'binds -DurationDays to instanceDurationInDays' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationDays 7 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Body.settings.instanceDurationInDays -eq 7
            }
        }
    }
}

Describe 'New-OERAccessReviewDefinition self-review mixing guard (Task 4c)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'; FailedKind = $null; FailedValue = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'new-def' } }
    }

    It 'refuses -SelfReview mixed with -Reviewer before any Graph call, including scope resolution' {
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview -Reviewer 'person18@example.com' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        # The guard must fire before scope resolution -- not just before the write -- per the brief.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -ReviewerGroup' {
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview -ReviewerGroup 'IT-Owners' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -Manager' {
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview -Manager -FallbackReviewer 'person18@example.com' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'still accepts -SelfReview alone (regression)' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope { @{ Reviewers = @(); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null } }
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'accepts -SelfReview combined with an explicit -Manager:$false (round-1 finding I-2)' {
        # Presence is not intent for a switch: -Manager:$false EXPLICITLY binds Manager (so
        # $PSBoundParameters.ContainsKey('Manager') is true), but its VALUE is false, so this is not
        # actually "combined with -Manager". A ContainsKey-keyed guard refused this call; the fix
        # must key on the bound VALUES instead.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope { @{ Reviewers = @(); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null } }
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview -Manager:$false `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'accepts a splat carrying SelfReview = $false alongside -Reviewer (round-1 finding I-2)' {
        # Splatting with SelfReview = $false is the idiomatic way to build this call programmatically.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
            @{ Reviewers = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null }
        }
        $Splat = @{
            DisplayName             = 'Q3'
            DescriptionForAdmins    = 'a'
            DescriptionForReviewers = 'r'
            AccessPackage           = 'AP'
            AssignmentPolicy        = 'Standard'
            SelfReview              = $false
            Reviewer                = @('person18@example.com')
            Recurrence              = 'OneTime'
            StartDate               = ([datetime]'2026-07-05')
        }
        $Err = $null
        New-OERAccessReviewDefinition @Splat -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }
}

Describe 'New-OERAccessReviewDefinition non-positive occurrence and duration guard (Task 4d)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'; FailedKind = $null; FailedValue = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'new-def' } }
    }

    It '-Occurrences 0 fails bind-time validation on THIS cmdlet, not the private recurrence builder' {
        # A pure bind-time ParameterBindingException on the OUTER command does not populate its own
        # -ErrorVariable (verified empirically) -- only the try/catch $PSItem carries a record. Before
        # Task 4d, -Occurrences 0 bound fine here and only failed later, at the un-try'd
        # New-OERAccessReviewRecurrence call site; THAT failure, because it propagates out of a nested
        # command, DOES land in the outer call's -ErrorVariable, carrying the PRIVATE cmdlet's id. So
        # the try/catch $PSItem id alone is VACUOUS here -- PowerShell's propagation already reports it
        # as "...,New-OERAccessReviewDefinition" even today, before any fix -- and the real
        # discriminator is that $Err carries no New-OERAccessReviewRecurrence record.
        $Threw = $false
        $CaughtId = $null
        $Err = $null
        try {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
                -Recurrence Monthly -StartDate ([datetime]'2026-07-05') -Occurrences 0 `
                -ErrorAction Stop -ErrorVariable Err
        } catch { $Threw = $true; $CaughtId = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $CaughtId | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewDefinition$'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OERAccessReviewRecurrence' }).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It '-DurationInDays 0 fails bind-time validation on THIS cmdlet' {
        # Unlike -Occurrences, -DurationInDays was never forwarded to a ValidateRange-bearing private
        # helper, so today -DurationInDays 0 does not throw AT ALL -- $Threw itself is the
        # discriminator, not the caught id (which would be equally "correct-looking" either way once
        # something does throw).
        $Threw = $false
        $CaughtId = $null
        try {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationInDays 0 `
                -ErrorAction Stop
        } catch { $Threw = $true; $CaughtId = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $CaughtId | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewDefinition$'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It '-Occurrences 1 (the boundary) still succeeds' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence Monthly -StartDate ([datetime]'2026-07-05') -Occurrences 1 `
            -ErrorAction Stop
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }
}

Describe 'New-OERAccessReviewDefinition ambiguous reviewer group' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'
                FailedKind = $null; FailedValue = $null; FailedErrorId = $null; FailedMessage = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'new-def' } }
    }

    It 'reports an ambiguous reviewer group as a NON-terminating error and does not POST' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Caught = $null; $Err = $null
        try {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -ReviewerGroup 'Dup' `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        } catch { $Caught = $PSItem }
        # Resolve-OERReviewerScope must report the ambiguity through its Failed* descriptor. A throw
        # would terminate this cmdlet and defeat -ErrorAction SilentlyContinue.
        $Caught | Should -Be $null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewDefinition' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewDefinition' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        # An ambiguity is a bad argument, not a missing object.
        $Reported.CategoryInfo.Category | Should -Be 'InvalidArgument'
        # The mandatory bearer-hygiene line inside the helper's resolver catch.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }

    It 'still reports the existing GroupNotFound error for a genuine no-match' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { $null }
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -ReviewerGroup 'missing' `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessReviewDefinition' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewDefinition' }).Count | Should -Be 0
        # The pre-existing not-found path keeps ObjectNotFound: only the ambiguity branch is new.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessReviewDefinition' })[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
    }
}
