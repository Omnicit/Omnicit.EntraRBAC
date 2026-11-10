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

    It 'POSTs -Recurrence SemiAnnually as absoluteMonthly interval 6 with a noEnd range' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Reviewer '11111111-1111-1111-1111-111111111111' `
            -Recurrence SemiAnnually -StartDate ([datetime]'2026-07-05') -DurationInDays 14
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions' -and
            $Body.settings.recurrence.pattern.type -eq 'absoluteMonthly' -and
            $Body.settings.recurrence.pattern.interval -eq 6 -and
            $Body.settings.recurrence.pattern.dayOfMonth -eq 5 -and
            $Body.settings.recurrence.range.type -eq 'noEnd' -and
            $Body.settings.recurrence.range.startDate -eq '2026-07-05'
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

    It 'writes the one-time form: a null pattern and a numbered range ending -DurationInDays after -StartDate' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationInDays 14
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.settings.ContainsKey('recurrence') -and
            $Body.settings.recurrence.ContainsKey('pattern') -and
            $null -eq $Body.settings.recurrence.pattern -and
            $Body.settings.recurrence.range.type -eq 'numbered' -and
            $Body.settings.recurrence.range.numberOfOccurrences -eq 0 -and
            $Body.settings.recurrence.range.startDate -eq '2026-07-05' -and
            $Body.settings.recurrence.range.endDate -eq '2026-07-19' -and
            $Body.settings.instanceDurationInDays -eq 14
        }
    }

    It 'uses the default length of 14 days for the one-time range when -DurationInDays is not given' {
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
            -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Body.settings.recurrence.range.endDate -eq '2026-07-19' -and
            $Body.settings.instanceDurationInDays -eq 14
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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
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

Describe 'New-OERAccessReviewDefinition -Group (a review of a group''s members)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'; FailedKind = $null; FailedValue = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri, $Method)
            if ($Method -eq 'POST') { return @{ id = 'new-def'; displayName = 'Q3'; status = 'NotStarted' } }
            return @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'grp' }) }
        }
    }

    Context 'parameter sets' {
        It 'declares the six sets with the default SingleStage' {
            $Cmd = Get-Command New-OERAccessReviewDefinition
            @($Cmd.ParameterSets.Name | Sort-Object) | Should -Be @('DirectoryRoleMultiStage', 'DirectoryRoleSingleStage', 'GroupMultiStage', 'GroupSingleStage', 'MultiStage', 'SingleStage')
            ($Cmd.ParameterSets | Where-Object IsDefault).Name | Should -Be 'SingleStage'
        }

        It 'puts <Name> in exactly <Sets> and marks it mandatory only where stated' -ForEach @(
            @{ Name = 'AccessPackage'; Sets = 'MultiStage,SingleStage'; Mandatory = 'MultiStage,SingleStage' }
            @{ Name = 'AssignmentPolicy'; Sets = 'MultiStage,SingleStage'; Mandatory = 'MultiStage,SingleStage' }
            @{ Name = 'Catalog'; Sets = 'MultiStage,SingleStage'; Mandatory = '' }
            @{ Name = 'Group'; Sets = 'GroupMultiStage,GroupSingleStage'; Mandatory = 'GroupMultiStage,GroupSingleStage' }
            @{ Name = 'DirectoryRole'; Sets = 'DirectoryRoleMultiStage,DirectoryRoleSingleStage'; Mandatory = 'DirectoryRoleMultiStage,DirectoryRoleSingleStage' }
            @{ Name = 'DirectoryRoleAssignmentType'; Sets = 'DirectoryRoleMultiStage,DirectoryRoleSingleStage'; Mandatory = '' }
            @{ Name = 'Stage'; Sets = 'DirectoryRoleMultiStage,GroupMultiStage,MultiStage';Mandatory = 'DirectoryRoleMultiStage,GroupMultiStage,MultiStage' }
            @{ Name = 'Reviewer'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
            @{ Name = 'ReviewerGroup'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
            @{ Name = 'Manager'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
            @{ Name = 'SelfReview'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
            @{ Name = 'FallbackReviewer'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
            @{ Name = 'FallbackReviewerGroup'; Sets = 'DirectoryRoleSingleStage,GroupSingleStage,SingleStage'; Mandatory = '' }
        ) {
            $Attrs = (Get-Command New-OERAccessReviewDefinition).Parameters[$Name].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            (@($Attrs.ParameterSetName | Sort-Object) -join ',') | Should -Be $Sets
            (@($Attrs | Where-Object Mandatory | ForEach-Object ParameterSetName | Sort-Object) -join ',') | Should -Be $Mandatory
        }

        It 'keeps -Group non-empty at binding' {
            $Threw = $false; $Id = $null
            try {
                New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                    -Group '' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction Stop
            } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
            $Threw | Should -BeTrue
            $Id | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewDefinition$'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }

        It 'refuses -Group beside -AccessPackage at binding' {
            $Threw = $false; $Id = $null
            try {
                New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                    -Group 'grp' -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
                    -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction Stop
            } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
            $Threw | Should -BeTrue
            $Id | Should -Be 'AmbiguousParameterSet,New-OERAccessReviewDefinition'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }

        It 'binds a package call with -Reviewer to SingleStage (top-level reviewers, no stageSettings)' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
                @{ Reviewers = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null }
            }
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Reviewer 'u1' `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.reviewers.Count -eq 1 -and -not $Body.ContainsKey('stageSettings') -and
                $Body.scope.query -like '*accessPackage/id eq ''ap''*'
            }
        }

        It 'binds a package call with -Stage to MultiStage' {
            $Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Stage $Stage `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.stageSettings.Count -eq 1 -and -not $Body.ContainsKey('reviewers')
            }
        }

        It 'binds a package call with -SelfReview to SingleStage' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -SelfReview `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.reviewers.Count -eq 0 -and $Body.ContainsKey('fallbackReviewers')
            }
        }

        It 'binds a package call with -Manager and -FallbackReviewer to SingleStage' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
                @{ Reviewers = @(@{ query = './manager'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(@{ query = '/users/u2'; queryType = 'MicrosoftGraph' }); FailedKind = $null; FailedValue = $null }
            }
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Manager -FallbackReviewer 'u2' `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.reviewers[0].query -eq './manager' -and -not $Body.ContainsKey('stageSettings')
            }
        }

        It 'binds a package call with -ReviewerGroup to SingleStage' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
                @{ Reviewers = @(@{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null }
            }
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -ReviewerGroup 'g1' `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.reviewers.Count -eq 1 -and -not $Body.ContainsKey('stageSettings')
            }
        }

        It 'binds a package call with -Catalog to SingleStage and passes the catalog to the scope resolver' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Catalog 'Cat' -SelfReview `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget -Times 1 -Exactly -ParameterFilter { $Catalog -eq 'Cat' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }
        It 'binds a package call with no reviewer to SingleStage, which then reports NoReviewer' {
            $Err = $null
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -AccessPackage 'AP' -AssignmentPolicy 'Standard' `
                -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoReviewer,New-OERAccessReviewDefinition' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'binds -Group with -Reviewer to GroupSingleStage' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERReviewerScope {
                @{ Reviewers = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' }); FallbackReviewers = @(); FailedKind = $null; FailedValue = $null }
            }
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -Reviewer 'u1' -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.reviewers.Count -eq 1 -and -not $Body.ContainsKey('stageSettings')
            }
        }

        It 'binds -Group with no reviewer parameter and reports NoReviewer without a POST' {
            $Err = $null
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoReviewer,New-OERAccessReviewDefinition' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
        It 'binds -Group with -Stage to GroupMultiStage' {
            $Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -Stage $Stage -Recurrence OneTime -StartDate ([datetime]'2026-07-05')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.stageSettings.Count -eq 1 -and -not $Body.ContainsKey('reviewers') -and
                $Body.scope.query -eq '/groups/33333333-3333-3333-3333-333333333333/transitiveMembers'
            }
        }
    }

    Context 'behaviour' {
        It 'looks the group up once by display name, then POSTs the transitiveMembers scope' {
            $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -SelfReview -Recurrence Quarterly -StartDate ([datetime]'2026-07-05') -Confirm:$false
            $Out.Id | Should -Be 'new-def'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like 'v1.0/groups?$filter=displayName eq ''grp''*'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions' -and
                $Body.scope.query -eq '/groups/33333333-3333-3333-3333-333333333333/transitiveMembers' -and
                $Body.scope.queryType -eq 'MicrosoftGraph'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget -Times 0 -Exactly
        }

        It 'sends no group lookup for a GUID and scopes the review to it' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group '44444444-4444-4444-4444-444444444444' -SelfReview -Recurrence Quarterly `
                -StartDate ([datetime]'2026-07-05') -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like 'v1.0/groups*' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.scope.query -eq '/groups/44444444-4444-4444-4444-444444444444/transitiveMembers'
            }
        }

        It 'reports GroupNotFound for a name that matches no group and POSTs nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            $Err = $null
            $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'ghost' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Out | Should -BeNullOrEmpty
            $Found = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessReviewDefinition' })
            $Found.Count | Should -Be 1
            $Found[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Found[0].Exception.Message | Should -Be "Group 'ghost' not found."
            $Found[0].TargetObject | Should -Be 'ghost'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'publishes an ambiguous group name as AmbiguousName naming both ids and POSTs nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'grp' }
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'grp' }
                    ) }
            }
            $Err = $null
            $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Out | Should -BeNullOrEmpty
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
                })
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Match '^AmbiguousName'
            $Published[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $Published[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'publishes a 403 on the group lookup as itself, never as GroupNotFound, and POSTs nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'grp')
            }
            $Err = $null
            $Out = New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Out | Should -BeNullOrEmpty
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
                })
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'carries the one-time recurrence on a OneTime group review' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -DurationInDays 14 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $null -eq $Body.settings.recurrence.pattern -and
                $Body.settings.recurrence.range.type -eq 'numbered' -and
                $Body.settings.recurrence.range.startDate -eq '2026-07-05' -and
                $Body.settings.recurrence.range.endDate -eq '2026-07-19' -and
                $Body.settings.instanceDurationInDays -eq 14
            }
        }

        It 'honors -WhatIf on a group review (the lookup may run, no POST)' {
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -Group 'grp' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -WhatIf
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }
}

Describe 'New-OERAccessReviewDefinition -DirectoryRole (a review of one directory role)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            $global:OERTask2Posted = @()
            $global:OERTask2ScopeCalls = @()
            $global:OERTask2Refusal = $null
        }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewScopeTarget {
            @{ AccessPackageId = 'ap'; AssignmentPolicyId = 'pol'; CatalogId = 'cat'; FailedKind = $null; FailedValue = $null }
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { '33333333-3333-3333-3333-333333333333' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput {
            param($Role)
            $Refusal = $global:OERTask2Refusal
            [PSCustomObject]@{
                RoleDefinitionId = if ($Refusal) { $null } else { '00000000-0000-0000-0000-000000000042' }
                ErrorId          = if ($Refusal) { $Refusal.ErrorId } else { $null }
                Message          = if ($Refusal) { "refused $($Refusal.ErrorId)" } else { $null }
                Category         = if ($Refusal) { $Refusal.Category } else { $null }
                TargetObject     = $Role
                InnerException   = $null
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri, $Method, $Body)
            if ($Method -eq 'POST') {
                $global:OERTask2Posted += , $Body
                return @{ id = 'new-def'; displayName = 'Role review'; status = 'NotStarted' }
            }
            return $null
        }
    }

    AfterAll {
        Remove-Variable -Name OERTask2Posted, OERTask2ScopeCalls, OERTask2Refusal -Scope Global -ErrorAction SilentlyContinue
    }

    It 'declares -DirectoryRole non-empty at binding' {
        $Threw = $false; $Id = $null
        try {
            New-OERAccessReviewDefinition -DisplayName 'R' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -DirectoryRole '' -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction Stop
        } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $Id | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewDefinition$'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'keeps SingleStage as the default parameter set' {
        (Get-Command New-OERAccessReviewDefinition).DefaultParameterSet | Should -Be 'SingleStage'
    }

    It 'POSTs the scope the builder writes for the resolved role id (single stage)' {
        New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -DirectoryRole 'Reports Reader' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly -ParameterFilter { $Role -eq 'Reports Reader' }
        $Got = InModuleScope Omnicit.EntraRBAC {
            @{
                Count    = @($global:OERTask2Posted).Count
                Scope    = ($global:OERTask2Posted[0].scope | ConvertTo-Json -Depth 10 -Compress)
                Expected = (New-OERAccessReviewScopeQuery -DirectoryRoleId '00000000-0000-0000-0000-000000000042' | ConvertTo-Json -Depth 10 -Compress)
                HasRev   = $global:OERTask2Posted[0].ContainsKey('reviewers')
                HasStage = $global:OERTask2Posted[0].ContainsKey('stageSettings')
            }
        }
        $Got.Count | Should -Be 1
        $Got.Scope | Should -Be $Got.Expected
        $Got.Scope | Should -Match '00000000-0000-0000-0000-000000000042'
        $Got.HasRev | Should -BeTrue
        $Got.HasStage | Should -BeFalse
    }

    It 'POSTs the scope the builder writes for the resolved role id (multi stage)' {
        $Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
        New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -DirectoryRole 'Reports Reader' -Stage $Stage -Recurrence Annually -StartDate ([datetime]'2027-01-01') -Confirm:$false
        $Got = InModuleScope Omnicit.EntraRBAC {
            @{
                Count    = @($global:OERTask2Posted).Count
                Scope    = ($global:OERTask2Posted[0].scope | ConvertTo-Json -Depth 10 -Compress)
                Expected = (New-OERAccessReviewScopeQuery -DirectoryRoleId '00000000-0000-0000-0000-000000000042' | ConvertTo-Json -Depth 10 -Compress)
                HasRev   = $global:OERTask2Posted[0].ContainsKey('reviewers')
                Stages   = @($global:OERTask2Posted[0].stageSettings).Count
            }
        }
        $Got.Count | Should -Be 1
        $Got.Scope | Should -Be $Got.Expected
        $Got.HasRev | Should -BeFalse
        $Got.Stages | Should -Be 1
    }

    It 'sends no POST under -WhatIf' {
        New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -DirectoryRole 'Reports Reader' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'publishes <ErrorId> as itself with target the -DirectoryRole value and sends no POST' -ForEach @(
        @{ ErrorId = 'RoleDefinitionNotFound'; Category = 'ObjectNotFound' }
        @{ ErrorId = 'AmbiguousRoleName'; Category = 'InvalidArgument' }
        @{ ErrorId = 'RoleDefinitionReadFailed'; Category = 'ReadError' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ E = $ErrorId; C = $Category } {
            param($E, $C)
            $global:OERTask2Refusal = @{ ErrorId = $E; Category = $C }
        }
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
            -DirectoryRole 'Some Role' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly
        $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OERAccessReviewDefinition' })
        $Mine.Count | Should -Be 1
        $Mine[0].FullyQualifiedErrorId | Should -Be "$ErrorId,New-OERAccessReviewDefinition"
        $Mine[0].CategoryInfo.Category | Should -Be $Category
        $Mine[0].TargetObject | Should -Be 'Some Role'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    # The cmdlet in a runspace with no try above it, the way a script calls it. The fakes live in the
    # runspace's copy of the module scope and are checked before the call; the POST counter is a file.
    It 'stops with the resolver refusal in a script with no try, and sends no POST' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Text = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERDirectoryRoleInput -Value {
        param([string]$Role)
        [PSCustomObject]@{ RoleDefinitionId = $null; ErrorId = 'RoleDefinitionNotFound'; Message = 'no such role'
            Category = 'ObjectNotFound'; TargetObject = $Role; InnerException = $null }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        [System.IO.File]::AppendAllText('#LOG#', "$Method`n")
        return $null
    }
    foreach ($Fn in 'Initialize-OERAuth', 'Resolve-OERDirectoryRoleInput', 'Invoke-OERGraphRequest') {
        $Cmd = Get-Command $Fn
        if ($Cmd.ModuleName -ne 'Omnicit.EntraRBAC' -or $Cmd.CommandType -ne 'Function') { throw "stub $Fn does not resolve to the module-scope function" }
    }
}
[System.IO.File]::AppendAllText('#LOG#', "STUBS:ok`n")
New-OERAccessReviewDefinition -DisplayName r -DescriptionForAdmins a -DescriptionForReviewers r -DirectoryRole 'Nope' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -ErrorAction Stop
[System.IO.File]::AppendAllText('#LOG#', "AFTER`n")
'@
        $Ps = [powershell]::Create()
        try {
            $null = $Ps.AddScript($Text.Replace('#LOG#', $Log.Replace("'", "''")))
            $Thrown = $null
            try { $null = $Ps.Invoke() } catch { $Thrown = $PSItem }
            $Thrown | Should -Not -BeNullOrEmpty
            $Cause = $Thrown.Exception
            if ($Cause -is [System.Management.Automation.MethodInvocationException] -and $Cause.InnerException) { $Cause = $Cause.InnerException }
            $Cause.ErrorRecord.FullyQualifiedErrorId | Should -Be 'RoleDefinitionNotFound,New-OERAccessReviewDefinition'
            $Logged = @(Get-Content -LiteralPath $Log)
            $Logged | Should -Contain 'STUBS:ok'
            $Logged | Should -Not -Contain 'AFTER'
            @($Logged | Where-Object { $_ -eq 'POST' }).Count | Should -Be 0
        } finally {
            $Ps.Dispose()
        }
    }

    # The same runspace WITHOUT -ErrorAction Stop: the refusal is written non-terminating and the script
    # carries on. Exactly one record reaches the error stream (a missing return would add the builder's
    # own failure), it carries the resolver's id, and no POST was sent.
    It 'writes the resolver refusal non-terminating in a script with no try, and sends no POST' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Text = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERDirectoryRoleInput -Value {
        param([string]$Role)
        [PSCustomObject]@{ RoleDefinitionId = $null; ErrorId = 'RoleDefinitionNotFound'; Message = 'no such role'
            Category = 'ObjectNotFound'; TargetObject = $Role; InnerException = $null }
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        [System.IO.File]::AppendAllText('#LOG#', "$Method`n")
        return $null
    }
    foreach ($Fn in 'Initialize-OERAuth', 'Resolve-OERDirectoryRoleInput', 'Invoke-OERGraphRequest') {
        $Cmd = Get-Command $Fn
        if ($Cmd.ModuleName -ne 'Omnicit.EntraRBAC' -or $Cmd.CommandType -ne 'Function') { throw "stub $Fn does not resolve to the module-scope function" }
    }
}
[System.IO.File]::AppendAllText('#LOG#', "STUBS:ok`n")
New-OERAccessReviewDefinition -DisplayName r -DescriptionForAdmins a -DescriptionForReviewers r -DirectoryRole 'Nope' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01')
[System.IO.File]::AppendAllText('#LOG#', "AFTER`n")
'@
        $Ps = [powershell]::Create()
        try {
            $null = $Ps.AddScript($Text.Replace('#LOG#', $Log.Replace("'", "''")))
            $null = $Ps.Invoke()
            $Logged = @(Get-Content -LiteralPath $Log)
            $Logged | Should -Contain 'STUBS:ok'
            $Logged | Should -Contain 'AFTER'
            @($Logged | Where-Object { $_ -eq 'POST' }).Count | Should -Be 0
            $Errors = @($Ps.Streams.Error)
            $Errors.Count | Should -Be 1
            $Errors[0].FullyQualifiedErrorId | Should -Be 'RoleDefinitionNotFound,New-OERAccessReviewDefinition'
        } finally {
            $Ps.Dispose()
        }
    }

    It 'refuses -DirectoryRole beside <Other> at binding and sends nothing' -ForEach @(
        @{ Other = '-AccessPackage'; Extra = @{ AccessPackage = 'AP'; AssignmentPolicy = 'Standard' } }
        @{ Other = '-Group'; Extra = @{ Group = 'grp' } }
        @{ Other = '-AssignmentPolicy'; Extra = @{ AssignmentPolicy = 'Standard' } }
        @{ Other = '-Catalog'; Extra = @{ Catalog = 'Cat' } }
    ) {
        $Threw = $false; $Id = $null
        $Splat = @{
            DisplayName = 'R'; DescriptionForAdmins = 'a'; DescriptionForReviewers = 'r'; DirectoryRole = 'Reports Reader'
            SelfReview = $true; Recurrence = 'OneTime'; StartDate = [datetime]'2026-07-05'; ErrorAction = 'Stop'
        }
        foreach ($Key in $Extra.Keys) { $Splat[$Key] = $Extra[$Key] }
        try { New-OERAccessReviewDefinition @Splat } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $Id | Should -Match '^(AmbiguousParameterSet|ParameterSetCannotBeResolved),New-OERAccessReviewDefinition$'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0 -Exactly
    }

    Context '-DirectoryRoleAssignmentType' {
        It 'POSTs the <Type> scope text for the resolved role id (<Stage>)' -ForEach @(
            @{ Type = 'Eligible'; Stage = 'single stage'; Query = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000042')" }
            @{ Type = 'Active'; Stage = 'single stage'; Query = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000042')" }
            @{ Type = 'Eligible'; Stage = 'multi stage'; Query = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000042')" }
            @{ Type = 'Active'; Stage = 'multi stage'; Query = "/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000042')" }
        ) {
            $Splat = @{
                DisplayName = 'Role review'; DescriptionForAdmins = 'a'; DescriptionForReviewers = 'r'
                DirectoryRole = 'Reports Reader'; DirectoryRoleAssignmentType = $Type
                Recurrence = 'Annually'; StartDate = [datetime]'2027-01-01'; Confirm = $false
            }
            if ($Stage -eq 'multi stage') {
                $Splat.Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
            } else {
                $Splat.SelfReview = $true
            }
            New-OERAccessReviewDefinition @Splat
            $Got = InModuleScope Omnicit.EntraRBAC {
                @{ Count = @($global:OERTask2Posted).Count; Scope = $global:OERTask2Posted[0].scope }
            }
            $Got.Count | Should -Be 1
            $Got.Scope.Keys.Count | Should -Be 3
            $Got.Scope.'@odata.type' | Should -Be '#microsoft.graph.accessReviewQueryScope'
            $Got.Scope.queryType | Should -Be 'MicrosoftGraph'
            $Got.Scope.query | Should -BeExactly $Query
        }

        It 'sends the same all-assignments body as before when the parameter is unbound' {
            New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -DirectoryRole 'Reports Reader' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -Confirm:$false
            $Got = InModuleScope Omnicit.EntraRBAC { $global:OERTask2Posted[0].scope }
            $Got.'@odata.type' | Should -Be '#microsoft.graph.principalResourceMembershipsScope'
            $Got.ContainsKey('query') | Should -BeFalse
            @($Got.principalScopes).Count | Should -Be 1
            $Got.principalScopes[0].query | Should -Be '/users'
            @($Got.resourceScopes).Count | Should -Be 1
            $Got.resourceScopes[0].query | Should -Be '/roleManagement/directory/roleDefinitions/00000000-0000-0000-0000-000000000042'
        }

        It 'passes the type to the builder only when bound' {
            Mock -ModuleName Omnicit.EntraRBAC New-OERAccessReviewScopeQuery {
                param([string]$DirectoryRoleId, [string]$DirectoryRoleAssignmentType)
                $global:OERTask2ScopeCalls += , (($PSBoundParameters.Keys | Sort-Object) -join ',')
                @{ query = 'stub'; queryType = 'MicrosoftGraph' }
            }
            New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -DirectoryRole 'Reports Reader' -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -Confirm:$false
            New-OERAccessReviewDefinition -DisplayName 'Role review' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                -DirectoryRole 'Reports Reader' -DirectoryRoleAssignmentType Active -SelfReview -Recurrence Annually -StartDate ([datetime]'2027-01-01') -Confirm:$false
            $Calls = InModuleScope Omnicit.EntraRBAC { , @($global:OERTask2ScopeCalls) }
            $Calls.Count | Should -Be 2
            $Calls[0] | Should -Be 'DirectoryRoleId'
            $Calls[1] | Should -Be 'DirectoryRoleAssignmentType,DirectoryRoleId'
        }

        It 'is declared in exactly the two DirectoryRole parameter sets, optional, with the two values' {
            $Param = (Get-Command New-OERAccessReviewDefinition).Parameters['DirectoryRoleAssignmentType']
            $Attrs = @($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            (@($Attrs.ParameterSetName | Sort-Object) -join ',') | Should -Be 'DirectoryRoleMultiStage,DirectoryRoleSingleStage'
            @($Attrs | Where-Object Mandatory).Count | Should -Be 0
            $Set = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            (@($Set.ValidValues) -join ',') | Should -Be 'Eligible,Active'
        }

        It 'is refused beside <Other> at binding and sends nothing' -ForEach @(
            @{ Other = '-Group'; Splat = @{ Group = 'grp'; SelfReview = $true } }
            @{ Other = '-AccessPackage'; Splat = @{ AccessPackage = 'AP'; AssignmentPolicy = 'Standard'; SelfReview = $true } }
        ) {
            $Threw = $false; $Id = $null
            $Splat += @{
                DisplayName = 'R'; DescriptionForAdmins = 'a'; DescriptionForReviewers = 'r'; DirectoryRoleAssignmentType = 'Eligible'
                Recurrence = 'OneTime'; StartDate = [datetime]'2026-07-05'; ErrorAction = 'Stop'
            }
            try { New-OERAccessReviewDefinition @Splat } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
            $Threw | Should -BeTrue
            $Id | Should -Match '^(AmbiguousParameterSet|ParameterSetCannotBeResolved|NamedParameterNotFound),New-OERAccessReviewDefinition$'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }

        It 'refuses the value <Value> at binding' -ForEach @(
            @{ Value = 'All' }
            @{ Value = '' }
        ) {
            $Threw = $false; $Id = $null
            try {
                New-OERAccessReviewDefinition -DisplayName 'R' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' -DirectoryRole 'Reports Reader' `
                    -DirectoryRoleAssignmentType $Value -SelfReview -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -ErrorAction Stop
            } catch { $Threw = $true; $Id = $PSItem.FullyQualifiedErrorId }
            $Threw | Should -BeTrue
            $Id | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewDefinition$'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }

    Context 'the existing shapes still use their own scope builder' {
        BeforeEach {
            Mock -ModuleName Omnicit.EntraRBAC New-OERAccessReviewScopeQuery {
                param([string]$AccessPackageId, [string]$AssignmentPolicyId, [string]$GroupId, [string]$DirectoryRoleId)
                $global:OERTask2ScopeCalls += , (($PSBoundParameters.Keys | Sort-Object) -join ',')
                @{ query = 'stub'; queryType = 'MicrosoftGraph' }
            }
        }

        It 'resolves <Shape> through <Expected> and never DirectoryRoleId' -ForEach @(
            @{ Shape = 'a package single stage'; Expected = 'AccessPackageId,AssignmentPolicyId'; Splat = @{ AccessPackage = 'AP'; AssignmentPolicy = 'Standard'; SelfReview = $true } }
            @{ Shape = 'a package multi stage'; Expected = 'AccessPackageId,AssignmentPolicyId'; Splat = @{ AccessPackage = 'AP'; AssignmentPolicy = 'Standard'; Stage = 'STAGE' } }
            @{ Shape = 'a group single stage'; Expected = 'GroupId'; Splat = @{ Group = 'grp'; SelfReview = $true } }
            @{ Shape = 'a group multi stage'; Expected = 'GroupId'; Splat = @{ Group = 'grp'; Stage = 'STAGE' } }
        ) {
            if ($Splat.Stage -eq 'STAGE') {
                $Splat.Stage = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
            }
            New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'a' -DescriptionForReviewers 'r' `
                @Splat -Recurrence OneTime -StartDate ([datetime]'2026-07-05') -Confirm:$false
            $Calls = InModuleScope Omnicit.EntraRBAC { , @($global:OERTask2ScopeCalls) }
            $Calls.Count | Should -Be 1
            $Calls[0] | Should -Be $Expected
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
