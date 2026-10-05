BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

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

Describe 'New-OERAccessReviewDefinition -- a failed reviewer lookup is not a not-found' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'
                FailedKind = $null; FailedValue = $null; FailedErrorId = $null; FailedMessage = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'new-def' } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERUserId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
        }
    }

    It 'publishes a 403 on a <Slot> as itself, never as a not-found, and does not POST' -ForEach @(
        @{ Slot = 'reviewer user'; Resolver = 'Resolve-OERUserId'; Params = @{ Reviewer = 'denied@contoso.com' } }
        @{ Slot = 'reviewer group'; Resolver = 'Resolve-OERGroupId'; Params = @{ ReviewerGroup = 'Denied Group' } }
        @{ Slot = 'fallback reviewer user'; Resolver = 'Resolve-OERUserId'; Params = @{ Manager = $true; FallbackReviewer = 'denied@contoso.com' } }
        @{ Slot = 'fallback reviewer group'; Resolver = 'Resolve-OERGroupId'; Params = @{ Manager = $true; FallbackReviewerGroup = 'Denied Group' } }
    ) {
        $Err = $null
        $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' @Params `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
        # whose id is the bare 'Authorization_RequestDenied' whether or not this cmdlet re-published it,
        # so an unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
            })
        # The positive half: the lookup was attempted and refused, so the zero below is not a cmdlet
        # that never got that far.
        Should -Invoke -ModuleName Omnicit.EntraRBAC -CommandName $Resolver -Times 1 -Exactly
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }
}

Describe 'New-OERAccessReviewDefinition -- a failed catalog or policy read is not a not-found' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'ap-1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERCatalogId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Catalog')
        }
        # The package read (catalog derivation) succeeds; only the assignment policy LISTING is refused.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri, $Method)
            if ($Uri -like '*assignmentPolicies*') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'ap-1')
            }
            return @{ id = 'new-def'; catalog = @{ id = 'cat-1' } }
        }
    }

    It 'publishes a 403 on <Slot> as itself, never as a not-found, and does not POST' -ForEach @(
        @{ Slot = 'an explicit -Catalog name'; Reached = 'catalog'; Params = @{ Catalog = 'Denied Catalog'; AssignmentPolicy = 'Standard' } }
        @{ Slot = 'the assignment policy listing'; Reached = 'policy'; Params = @{ AssignmentPolicy = 'Standard' } }
    ) {
        $Err = $null
        $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP-Sales' @Params -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: see the note in the reviewer Describe above.
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
            })
        # The positive half: the failing read was the one this case targets, so the zero POSTs below
        # cannot be a cmdlet that stopped for another reason.
        if ($Reached -eq 'catalog') {
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERCatalogId -Times 1 -Exactly
        } else {
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }
}

# Decision D3 (Philip, 2026-10-03): an assignment policy display name that two policies of the package
# share used to scope the new review to whichever policy Graph listed first. Resolve-OERAccessReviewScopeTarget
# now answers with an AmbiguousName descriptor and the cmdlet publishes it, naming every candidate id,
# before any POST. The resolver is NOT mocked here: the policy listing is the Graph call, so the whole
# path from the listing to the published record is exercised.
Describe 'New-OERAccessReviewDefinition -- an ambiguous assignment policy name is refused' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'ap-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri, $Method)
            if ($Uri -like '*assignmentPolicies*') {
                return @{ value = @(
                        @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Standard' }
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Standard' }
                    ) }
            }
            if ($Method -eq 'POST') { return @{ id = 'new-def'; displayName = 'Q3'; status = 'NotStarted' } }
            return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
        }
    }

    It 'publishes AmbiguousName naming both policy ids as itself, and POSTs nothing' {
        $Err = $null
        $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of any inner throw, so
        # an unnarrowed match can pass with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
            })
        # The positive half: the policy listing was reached, once, so the zero POSTs below are a refusal
        # of THIS lookup and not a cmdlet that stopped for another reason.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Published[0].TargetObject | Should -Be 'Standard'
        $Published[0].Exception.Message | Should -BeLike "Assignment policy display name 'Standard' matches 2 policies (*) in access package 'AP-Sales'.*"
        $Published[0].Exception.Message | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
        $Published[0].Exception.Message | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
        $Published[0].Exception.Message | Should -BeLike '*Re-run with the assignment policy id instead of the display name.'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'still accepts the policy id as the way out of the ambiguity, skipping the listing and POSTing the review' {
        $Err = $null
        $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP-Sales' -AssignmentPolicy '22222222-2222-2222-2222-222222222222' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).Count | Should -Be 0
        $Out | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.scope.query -like "*assignmentPolicy/id eq '22222222-2222-2222-2222-222222222222'*"
        }
    }
}
