BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERAccessReviewStage' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'builds a stage with a GUID reviewer and required fields' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
        $s.PSObject.TypeNames[0]             | Should -Be 'Omnicit.EntraRBAC.AccessReviewStageSetting'
        $s.GraphStage.stageId                | Should -Be '1'
        $s.GraphStage.durationInDays         | Should -Be 7
        $s.GraphStage.recommendationsEnabled | Should -BeOfType [bool]
        $s.GraphStage.reviewers[0].query     | Should -Be '/users/11111111-1111-1111-1111-111111111111'
    }

    It 'sets dependsOn and decisionsThatWillMoveToNextStage when bound' {
        $s = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 3 -Manager -DecisionsThatMoveToNextStage Deny, NotReviewed
        $s.GraphStage.dependsOn                          | Should -Be @('1')
        $s.GraphStage.decisionsThatWillMoveToNextStage   | Should -Be @('Deny', 'NotReviewed')
    }

    It 'does not include dependsOn key when -DependsOn is not supplied' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview
        $s.GraphStage.Keys | Should -Not -Contain 'dependsOn'
    }

    It 'does not include decisionsThatWillMoveToNextStage key when not supplied' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview
        $s.GraphStage.Keys | Should -Not -Contain 'decisionsThatWillMoveToNextStage'
    }

    It 'reports ReviewerCount correctly for a GUID reviewer' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer '11111111-1111-1111-1111-111111111111'
        $s.ReviewerCount | Should -Be 1
    }

    It 'reports ReviewerCount 0 for self-review' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview
        $s.ReviewerCount | Should -Be 0
    }

    It 'errors when no reviewer is supplied' {
        { New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -ErrorAction Stop } | Should -Throw
    }

    It 'uses StageId default of 1 when not specified' {
        $s = New-OERAccessReviewStage -DurationInDays 14 -SelfReview
        $s.StageId               | Should -Be '1'
        $s.GraphStage.stageId    | Should -Be '1'
    }

    It 'surfaces fallback reviewers in GraphStage for a GUID fallback reviewer' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -FallbackReviewer '33333333-3333-3333-3333-333333333333'
        $s.GraphStage.fallbackReviewers[0].query | Should -Be '/users/33333333-3333-3333-3333-333333333333'
    }

    Context 'duration vocabulary alias (audit PR6)' {
        It 'binds -DurationDays to the stage durationInDays' {
            $Stage = New-OERAccessReviewStage -StageId '1' -DurationDays 7 -Manager
            $Stage.DurationInDays | Should -Be 7
        }
    }
}

Describe 'New-OERAccessReviewStage self-review mixing guard (Task 4c)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'refuses -SelfReview mixed with -Reviewer before any Graph call' {
        $Err = $null
        New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -Reviewer 'person18@example.com' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewStage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -ReviewerGroup' {
        $Err = $null
        New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -ReviewerGroup 'IT-Owners' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewStage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'refuses -SelfReview mixed with -Manager' {
        $Err = $null
        New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -Manager `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'MutuallyExclusiveReviewer,New-OERAccessReviewStage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'still accepts -SelfReview alone (regression)' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        $s.ReviewerCount | Should -Be 0
    }

    It 'accepts -SelfReview combined with an explicit -Manager:$false (round-1 finding I-2)' {
        # Presence is not intent for a switch: -Manager:$false EXPLICITLY binds Manager (so
        # $PSBoundParameters.ContainsKey('Manager') is true), but its VALUE is false, so this is not
        # actually "combined with -Manager". A ContainsKey-keyed guard refused this call; the fix
        # must key on the bound VALUES instead.
        $Err = $null
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -SelfReview -Manager:$false -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        $s.ReviewerCount | Should -Be 0
    }

    It 'accepts a splat carrying SelfReview = $false alongside -Reviewer (round-1 finding I-2)' {
        # Splatting with SelfReview = $false is the idiomatic way to build this call programmatically
        # (e.g. from a loop that toggles reviewer mode per item). A ContainsKey-keyed guard refused
        # this too, since SelfReview is bound (present in the splat) even though its value is false.
        # A GUID reviewer (matching this file's other GUID-reviewer tests) so Resolve-OERUserId
        # short-circuits with no Graph call, keeping this test about the guard, not name resolution.
        $Err = $null
        $Splat = @{ StageId = '1'; DurationInDays = 7; SelfReview = $false; Reviewer = @('11111111-1111-1111-1111-111111111111') }
        $s = New-OERAccessReviewStage @Splat -ErrorVariable Err
        $Err | Should -BeNullOrEmpty
        $s.ReviewerCount | Should -Be 1
    }
}

Describe 'New-OERAccessReviewStage non-positive duration guard (Task 4d)' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It '-DurationInDays 0 fails bind-time validation with the cmdlet-qualified id' {
        # -DurationInDays was never forwarded to a ValidateRange-bearing private helper here, so today
        # it does not throw AT ALL -- $Threw itself is the discriminator. A pure bind-time
        # ParameterBindingException also does not populate the outer command's own -ErrorVariable
        # (verified empirically against the New-/Set-OERAccessReviewDefinition Task 4d tests), so the
        # id is read from the try/catch $PSItem instead.
        $Threw = $false
        $CaughtId = $null
        try {
            New-OERAccessReviewStage -StageId '1' -DurationInDays 0 -SelfReview `
                -ErrorAction Stop
        } catch { $Threw = $true; $CaughtId = $PSItem.FullyQualifiedErrorId }
        $Threw | Should -BeTrue
        $CaughtId | Should -Match '^ParameterArgumentValidationError.*,New-OERAccessReviewStage$'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It '-DurationInDays 1 (the boundary) still succeeds' {
        $s = New-OERAccessReviewStage -StageId '1' -DurationInDays 1 -SelfReview -ErrorAction Stop
        $s.DurationInDays | Should -Be 1
    }
}

Describe 'New-OERAccessReviewStage ambiguous reviewer group' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'reports an ambiguous reviewer group as a NON-terminating error naming the candidate ids' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Caught = $null; $Err = $null; $Out = $null
        try {
            $Out = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -ReviewerGroup 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch { $Caught = $PSItem }
        # Resolve-OERReviewerScope must report the ambiguity through its Failed* descriptor, not throw.
        $Caught | Should -Be $null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewStage' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewStage' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        # An ambiguity is a bad argument, not a missing object.
        $Reported.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Out | Should -Be $null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'still reports the existing GroupNotFound error for a genuine no-match' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { $null }
        $Err = $null
        New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -ReviewerGroup 'missing' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessReviewStage' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessReviewStage' }).Count | Should -Be 0
        # The pre-existing not-found path keeps ObjectNotFound: only the ambiguity branch is new.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessReviewStage' })[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }
}
