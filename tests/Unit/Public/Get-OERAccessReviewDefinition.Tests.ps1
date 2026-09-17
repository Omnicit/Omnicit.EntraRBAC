BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERAccessReviewDefinition' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'reads by Id directly' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'd1'; displayName = 'Q3' } }
        $d = Get-OERAccessReviewDefinition -Id 'd1'
        $d.Id | Should -Be 'd1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1'
        }
    }

    It 'accepts Id from the pipeline by property name (alias)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'd1' } }
        [pscustomobject]@{ AccessReviewDefinitionId = 'd1' } | Get-OERAccessReviewDefinition
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1
    }

    It 'errors (non-terminating) when a named definition is missing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessReviewDefinition -DisplayName 'ghost' -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
    }

    It '-DisplayName with a WILDCARD matches CLIENT-SIDE over the full list' {
        # A wildcard cannot be expressed as an OData displayName eq, so a wildcard name still pages
        # the unfiltered list and narrows client-side -- and must issue NO displayName eq request.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'd1'; displayName = 'AR-OER-Demo' }
                    @{ id = 'd2'; displayName = 'AR-Test' }
                    @{ id = 'd3'; displayName = 'Inactive Guests' }
                ) }
        }
        $defs = Get-OERAccessReviewDefinition -DisplayName 'AR*'
        @($defs).Count | Should -Be 2
        $defs.DisplayName | Should -Contain 'AR-OER-Demo'
        $defs.DisplayName | Should -Contain 'AR-Test'
        $defs.DisplayName | Should -Not -Contain 'Inactive Guests'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -and $All
        }
        # -Times 0 IS exact in Pester, so this half is a real guard: no server-side name filter here.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -like '*displayName eq*'
        }
    }

    It '-DisplayName with an exact name issues ONE server-side displayName eq request' {
        # The whole point of the change: the definitions collection sits in a very low request-RATE
        # bucket (measured live -- six definitions, identical request succeeded/failed/succeeded), so
        # an exact-name lookup must not spend that budget paging the whole collection. Asserted in
        # BOTH directions: the filtered read happens exactly once, and the $top=100 walk not at all.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd2'; displayName = 'AR-Test' }) }
        }
        $def = Get-OERAccessReviewDefinition -DisplayName 'AR-Test'
        @($def).Count | Should -Be 1
        $def.DisplayName | Should -Be 'AR-Test'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq 'AR-Test'"
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100'
        }
        # The filtered read is the ONLY read on this path -- one request, total.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
    }

    It 'falls back to the paged client-side walk when the server-side filter returns nothing' {
        # THE load-bearing test. OData eq may not match on case where -like does, so an empty server
        # result is not proof of absence and must not be reported as one.
        # Scope, stated precisely: this guard arms on ZERO rows only. It does NOT make the cmdlet
        # incapable of returning fewer definitions than the old client-side walk -- a server result
        # that is non-empty but case-narrower (two definitions differing only in case) short-circuits
        # before the fallback, which is the one behavior difference the change carries and is
        # documented on -DisplayName. What this test pins is the zero-row half.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri)
            if ($Uri -like '*displayName eq*') { return @{ value = @() } }
            return @{ value = @(
                    @{ id = 'd1'; displayName = 'AR-Test' }
                    @{ id = 'd2'; displayName = 'Inactive Guests' }
                ) }
        }
        $def = Get-OERAccessReviewDefinition -DisplayName 'ar-test'
        @($def).Count | Should -Be 1 -Because 'the client-side -like walk still finds it since -like is case-insensitive'
        $def.DisplayName | Should -Be 'AR-Test'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*displayName eq*'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -and $All
        }
    }

    It 'escapes a single quote in the name through ConvertTo-OERODataFilterValue' {
        # CLAUDE.md names that helper the single owner of OData filter-value escaping: the quote is
        # DOUBLED so the literal is not terminated early, then the whole value percent-encoded.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd9'; displayName = "O'Brien Review" }) }
        }
        $def = Get-OERAccessReviewDefinition -DisplayName "O'Brien Review"
        $def.DisplayName | Should -Be "O'Brien Review"
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq 'O%27%27Brien%20Review'"
        }
    }

    It 'returns the converter-owned shape unchanged on the server-side filtered path' {
        # A $select is deliberately NOT sent on the filtered read: the converter reads eleven
        # top-level fields plus the nested settings bag, and a $select that dropped one would null
        # the property silently rather than fail. This pins the shape the filtered path returns.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{
                        id                   = 'd1'
                        displayName          = 'AR-Shape'
                        status               = 'InProgress'
                        descriptionForAdmins = 'admins'
                        descriptionForReviewers = 'reviewers'
                        createdDateTime      = '2026-01-01T00:00:00Z'
                        scope                = @{ query = "/groups/g1/transitiveMembers" }
                        reviewers            = @(@{ query = './manager' })
                        fallbackReviewers    = @(@{ query = '/users/u1' })
                        settings             = @{
                            instanceDurationInDays         = 14
                            mailNotificationsEnabled       = $true
                            justificationRequiredOnApproval = $true
                            defaultDecision                = 'None'
                        }
                    }) }
        }
        $def = Get-OERAccessReviewDefinition -DisplayName 'AR-Shape'
        $def.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDefinition'
        $def.AccessReviewDefinitionId | Should -Be 'd1'
        $def.DisplayName | Should -Be 'AR-Shape'
        $def.Status | Should -Be 'InProgress'
        $def.DescriptionForAdmins | Should -Be 'admins'
        $def.DescriptionForReviewers | Should -Be 'reviewers'
        $def.Scope | Should -Be '/groups/g1/transitiveMembers'
        $def.ReviewerCount | Should -Be 1
        $def.StageCount | Should -Be 0
        @($def.FallbackReviewers).Count | Should -Be 1
        $def.DurationInDays | Should -Be 14
        $def.MailNotificationsEnabled | Should -BeTrue
        $def.JustificationRequired | Should -BeTrue
        $def.DefaultDecision | Should -Be 'None'
        $def.CreatedDateTime | Should -Be '2026-01-01T00:00:00Z'
        $def.Settings | Should -Not -BeNullOrEmpty
        # Without this the title is a lie: the mock above answers ANY uri, so every assertion here
        # holds identically on the walk path and the whole It stays green with the server-side
        # branch deleted. This is what makes it pin the FILTERED path specifically.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100'
        }
    }

    It 'treats ? and ] as wildcards too, not just *' {
        # The predicate is a four-character class -- * ? [ ] -- and only * was exercised. Deleting
        # ? or ] from it would send a literal wildcard into an OData eq, which matches nothing and
        # then quietly falls back, hiding the mistake behind a second request against the endpoint
        # this whole change exists to spare.
        # '[' is deliberately absent: 'AR[Test' -like 'AR[Test' throws WildcardPatternException in
        # the client-side walk. That is pre-existing -Like behavior in the fallback path, unrelated
        # to this change, so there is no green path to assert it on.
        # The two fixture names must not match each other's pattern: '?' matches ANY single
        # character, ']' included, so a bare 'AR]x' row would also satisfy 'AR?x'.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd1'; displayName = 'ARzx' }, @{ id = 'd2'; displayName = 'AR]xyz' }) }
        }
        $Question = Get-OERAccessReviewDefinition -DisplayName 'AR?x'
        @($Question).Count | Should -Be 1 -Because 'a ? matches exactly one character client-side'
        $Question.DisplayName | Should -Be 'ARzx'

        $Bracket = Get-OERAccessReviewDefinition -DisplayName 'AR]xyz'
        @($Bracket).Count | Should -Be 1
        $Bracket.DisplayName | Should -Be 'AR]xyz'

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -like '*displayName eq*'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -and $All
        }
    }

    It '-DisplayName matches against the full aggregated list so matches on later pages are not missed' {
        # Paging itself now lives inside Invoke-OERGraphRequest's -All switch (adopted by this cmdlet
        # to replace its former hand-rolled nextLink loop -- see rt-graph-list-reads-first-page-only).
        # Invoke-OERGraphRequest is mocked at the module boundary in this suite, so the mock returns the
        # already-aggregated shape directly; the two-page nextLink mechanics are covered by
        # Invoke-OERGraphRequest.Tests.ps1 instead.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd1'; displayName = 'Other' }, @{ id = 'd2'; displayName = 'AR-OnPage2' }) }
        }
        $def = Get-OERAccessReviewDefinition -DisplayName 'AR-*'
        @($def).Count | Should -Be 1
        $def.DisplayName | Should -Be 'AR-OnPage2'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -and $All
        }
    }

    It 'attaches Instances property when -IncludeInstances is set' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Uri -like '*/instances') {
                return @{ value = @(@{ id = 'inst1'; status = 'InProgress' }) }
            }
            return @{ id = 'd1'; displayName = 'Q3' }
        }
        $d = Get-OERAccessReviewDefinition -Id 'd1' -IncludeInstances
        $d.Instances | Should -Not -BeNullOrEmpty
        $d.Instances.Count | Should -Be 1
        # $All here is the WRAPPER's Invoke-OERGraphRequest -All paging switch, captured automatically
        # inside this mock's ParameterFilter scriptblock -- not the cmdlet's own -All parameter (a
        # parameter-set discriminator for "list every definition", not used in this -Id/-IncludeInstances
        # call). Task 7 fix-round Minor 4: this /instances sub-read was a first-page-only gap the
        # original Task 7 sweep missed.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances' -and $All
        }
    }

    It 'pages the -Filter read via the wrapper''s -All switch (Task 7 fix round 2)' {
        # The endpoint silently ignores unsupported -Filter expressions (see .PARAMETER Filter above)
        # and returns the WHOLE unfiltered collection in that case -- so an unpaged read here would
        # silently return only page 1 of the ENTIRE tenant's definitions, not just of some filtered
        # subset. This is the last -Filter branch in the module that was missing -All; both sibling
        # branches (Get-OERGroup.ps1, Get-OERAdministrativeUnit.ps1) already page theirs.
        # $All here is the WRAPPER's Invoke-OERGraphRequest -All paging switch, captured automatically
        # inside this mock's ParameterFilter scriptblock -- not the cmdlet's own -All parameter, which
        # is a DIFFERENT, mutually exclusive parameter set (ParameterSetName 'All' vs 'ByFilter') and
        # is not read as a variable at all in this branch, only via $PSCmdlet.ParameterSetName.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd1'; displayName = 'Scoped' }) }
        }
        $defs = Get-OERAccessReviewDefinition -Filter "contains(scope/microsoft.graph.accessReviewQueryScope/query, '/groups')"
        @($defs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like 'v1.0/identityGovernance/accessReviews/definitions?$filter=*' -and $All
        }
        # Regression: the server-side name lookup added for -DisplayName is ByName-only and must
        # never leak into this parameter set.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -like '*displayName eq*'
        }
    }

    It '-All requests every definition via the wrapper''s -All paging switch' {
        # The hand-rolled nextLink loop this cmdlet used to run itself is gone -- it now delegates
        # paging to Invoke-OERGraphRequest -All (closes rt-graph-list-reads-first-page-only). Since
        # Invoke-OERGraphRequest is mocked at the module boundary here, the mock supplies the
        # already-aggregated result directly; the real nextLink-following mechanics (including the
        # "feeds the absolute nextLink straight back" behavior) are proven in
        # Invoke-OERGraphRequest.Tests.ps1. This test's job is only to prove the cmdlet opted in.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'd1'; displayName = 'One' }, @{ id = 'd2'; displayName = 'Two' }) }
        }
        $defs = Get-OERAccessReviewDefinition -All
        @($defs).Count | Should -Be 2
        $defs.Id | Should -Contain 'd1'
        $defs.Id | Should -Contain 'd2'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -and $All
        }
        # Regression: the server-side name lookup added for -DisplayName is ByName-only and must
        # never leak into this parameter set.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -like '*displayName eq*'
        }
    }

    It '-All returns nothing and raises no error for an empty tenant' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
        $defs = Get-OERAccessReviewDefinition -All -ErrorVariable e -ErrorAction SilentlyContinue
        $defs | Should -BeNullOrEmpty
        $e | Should -BeNullOrEmpty
    }

    It 'surfaces a Graph failure as a non-terminating error and emits nothing' {
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
        $Result = Get-OERAccessReviewDefinition -Id 'd1' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }

    It 'warns and returns the definition with no instances when the instances read fails' {
        # Get-OERAccessReviewDefinition.ps1:144 -- the instances read DEGRADES rather than errors:
        # it scrubs, emits a Write-Warning, and still returns the definition with an empty Instances
        # collection. Still assert the mandatory Remove-OERErrorRecord scrub, since this catch calls it.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri)
            if ($Uri -like '*/instances') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('TooManyRequests: throttled.'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null)
            }
            return @{ id = 'd1'; displayName = 'Q3' }
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Warnings = @()
        $Result = Get-OERAccessReviewDefinition -Id 'd1' -IncludeInstances `
            -WarningVariable Warnings -WarningAction SilentlyContinue
        $Result | Should -Not -BeNullOrEmpty
        @($Result.Instances).Count | Should -Be 0
        $Warnings.Count | Should -BeGreaterThan 0
        # Pin the warning to the instances-read failure specifically (Get-OERAccessReviewDefinition.ps1:147),
        # not just "some warning happened" -- a future unrelated Write-Warning on this path would otherwise
        # keep this It green while the real degradation signal is lost.
        $Warnings -join ';' | Should -Match 'Could not read instances'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
