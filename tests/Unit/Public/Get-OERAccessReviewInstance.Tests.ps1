BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERAccessReviewInstance' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-id' }
    }

    It 'lists instances for a definition' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        $i = Get-OERAccessReviewInstance -Definition 'Q3'
        $i.Id | Should -Be 'i1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances?$select=id,status,startDateTime,endDateTime,scope'
        }
    }

    It 'propagates DefinitionId onto each emitted instance' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        $i = Get-OERAccessReviewInstance -Definition 'Q3'
        $i.DefinitionId | Should -Be 'def-id'
    }

    It 'reads a single instance by id' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'i1'; status = 'Completed' }
        }
        $i = Get-OERAccessReviewInstance -Definition 'def-id' -Id 'i1'
        $i.Status | Should -Be 'Completed'
        # -not $All is deliberate: this is a single-item GET by id, not a collection read, and it must
        # NEVER be paged. Invoke-OERGraphRequest's -All switch collapses a single-object response to
        # @{ value = @() } -- which is truthy, survives the Where-Object null filter below it, and
        # would silently emit a junk empty-shell instance instead of either the real one or the
        # AccessReviewInstanceNotFound error a genuine 404 produces (Task 7 fix-round Minor 1: this
        # mutation passed the whole 26-test suite until this clause was added).
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1?$select=id,status,startDateTime,endDateTime,scope' -and -not $All
        }
    }

    It 'tags output as Omnicit.EntraRBAC.AccessReviewInstance' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'i1'; status = 'InProgress' }
        }
        $i = Get-OERAccessReviewInstance -Definition 'def-id' -Id 'i1'
        $i.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewInstance'
    }

    It 'attaches Decisions property and calls the exact decisions URI when -IncludeDecisions is set' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri)
            if ($Uri -like '*/decisions*') {
                return @{ value = @(@{ id = 'dec1'; decision = 'Approve'; principal = @{ displayName = 'Anna' } }) }
            }
            return @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        $i = Get-OERAccessReviewInstance -Definition 'Q3' -IncludeDecisions
        $i.Decisions | Should -Not -BeNullOrEmpty
        $i.Decisions[0].Decision | Should -Be 'Approve'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq ('v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/decisions' +
                      '?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,' +
                      'applyResult,principal,resource,recommendation')
        }
    }

    It 'attaches Stages property and calls the exact stages URI when -IncludeStages is set' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri)
            if ($Uri -like '*/stages') {
                return @{ value = @(@{ id = 's1'; status = 'InProgress' }) }
            }
            return @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        $i = Get-OERAccessReviewInstance -Definition 'Q3' -IncludeStages
        $i.Stages | Should -Not -BeNullOrEmpty
        $i.Stages[0].Id | Should -Be 's1'
        # Round-1 review finding I-1: the cmdlet must pass -InstanceId/-DefinitionId into the
        # converter (Get-OERAccessReviewInstance.ps1:165) so a returned stage carries its parent ids
        # for onward piping into Get-OERAccessReviewInstanceDecision. Reverting that call site back to
        # a bare -InputObject leaves these two assertions the ONLY thing in the whole suite that goes
        # red -- see AccessReview.Pipeline.Tests.ps1 for the true end-to-end pipe proof.
        $i.Stages[0].AccessReviewInstanceId | Should -Be 'i1'
        $i.Stages[0].AccessReviewDefinitionId | Should -Be 'def-id'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/stages'
        }
    }

    It 'writes a non-terminating error when definition not found' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        Get-OERAccessReviewInstance -Definition 'ghost' -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
    }

    It 'passes TenantId to Initialize-OERAuth' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        Get-OERAccessReviewInstance -Definition 'Q3' -TenantId 'contoso.onmicrosoft.com'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -ParameterFilter {
            $TenantId -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'accepts pipeline input via the AccessReviewDefinitionId alias and calls the list URI' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
        }
        [pscustomobject]@{ AccessReviewDefinitionId = 'def-id' } | Get-OERAccessReviewInstance
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances?$select=id,status,startDateTime,endDateTime,scope'
        }
    }

    Context 'instance parameter naming (audit PR6)' {
        It 'accepts -Instance for the instance id' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'i1'; status = 'Completed' }
            }
            $i = Get-OERAccessReviewInstance -Definition 'def-id' -Instance 'i1'
            $i.Status | Should -Be 'Completed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1?$select=id,status,startDateTime,endDateTime,scope'
            }
        }

        It 'still accepts the historical -Id name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'i1'; status = 'Completed' }
            }
            $i = Get-OERAccessReviewInstance -Definition 'def-id' -Id 'i1'
            $i.Status | Should -Be 'Completed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1?$select=id,status,startDateTime,endDateTime,scope'
            }
        }

        It 'accepts the InstanceId alias the sibling cmdlets use' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'i1'; status = 'Completed' }
            }
            $i = Get-OERAccessReviewInstance -Definition 'def-id' -InstanceId 'i1'
            $i.Status | Should -Be 'Completed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1?$select=id,status,startDateTime,endDateTime,scope'
            }
        }

        It 'accepts the AccessReviewInstanceId alias' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'i1'; status = 'Completed' }
            }
            $i = Get-OERAccessReviewInstance -Definition 'def-id' -AccessReviewInstanceId 'i1'
            $i.Status | Should -Be 'Completed'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1?$select=id,status,startDateTime,endDateTime,scope'
            }
        }
    }

    Context 'missing instance (audit PR8)' {
        It 'reports AccessReviewInstanceNotFound when Graph returns a not-found error' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('NotFound: The resource could not be found.'),
                    'NotFound',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null)
            }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'missing-instance' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AccessReviewInstanceNotFound'
        }

        It 'reports AccessReviewInstanceNotFound when the GET returns nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'missing-instance' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AccessReviewInstanceNotFound'
        }

        It 'still surfaces a non-not-found failure unchanged' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('TooManyRequests: throttled.'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'inst-1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Joined = @($Err).FullyQualifiedErrorId -join ';'
            # Match the CMDLET-QUALIFIED id, never the bare code. PowerShell auto-records the mock's
            # thrown ErrorRecord at 13 call boundaries before this cmdlet's own catch runs (measured on
            # this tree: 14 records, indices 0-12 bare, only index 13 qualified), so a bare
            # Should -Match 'TooManyRequests' passes even with $PSCmdlet.WriteError($PSItem) deleted.
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,Get-OERAccessReviewInstance' }).Count |
                Should -Be 1
            $Joined | Should -Not -Match 'AccessReviewInstanceNotFound'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'does not misroute a 403 whose message uses existence-ambiguous wording' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        'Forbidden: The caller does not have access to the resource, or it does not exist.'),
                    'Forbidden',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'inst-1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Joined = @($Err).FullyQualifiedErrorId -join ';'
            # Cmdlet-qualified, not bare -- see the note on the throttling It above.
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERAccessReviewInstance' }).Count |
                Should -Be 1
            $Joined | Should -Not -Match 'AccessReviewInstanceNotFound'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'does not misroute a 403 whose message uses the reference-property existence-ambiguous wording' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        "Resource 'inst-1' does not exist or one of its queried reference-property " +
                        'objects are not present.'),
                    'Forbidden',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'inst-1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Joined = @($Err).FullyQualifiedErrorId -join ';'
            # Cmdlet-qualified, not bare -- see the note on the throttling It above.
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERAccessReviewInstance' }).Count |
                Should -Be 1
            $Joined | Should -Not -Match 'AccessReviewInstanceNotFound'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'still routes a 404-derived NotFound id to AccessReviewInstanceNotFound even with an unhelpful message' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('NotFound: oops.'),
                    'NotFound',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null)
            }
            Get-OERAccessReviewInstance -Definition 'Review' -Instance 'inst-1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AccessReviewInstanceNotFound'
        }
    }

    Context 'every catch clause is driven (audit T6)' {
        # source/Public/Get-OERAccessReviewInstance.ps1 carries five catch/Remove-OERErrorRecord pairs:
        #   :71  definition resolve   -- driven by 'surfaces a definition-resolution failure ...'
        #   :97  single-instance GET  -- driven by the 'missing instance (audit PR8)' Context above
        #   :150 list GET             -- driven by 'surfaces a list-path Graph failure ...'
        #   :167 -IncludeStages       -- driven by 'warns and falls back to an empty stage list ...'
        #   :181 -IncludeDecisions    -- driven by 'warns and falls back to an empty decision list ...'
        # Each asserts the scrub with Mock + Should -Invoke rather than a $global:Error reference
        # check, because two of the five re-emit the caught record unchanged and a reference proof is
        # inert against that shape.

        It 'surfaces a list-path Graph failure with the cmdlet-qualified id and scrubs the record' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Forbidden'),
                    'Forbidden',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            # The ABSENCE of -Instance is what routes this through the list branch.
            $Result = Get-OERAccessReviewInstance -Definition 'Q3' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-1/instances?$select=id,status,startDateTime,endDateTime,scope'
            }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERAccessReviewInstance' }).Count |
                Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'surfaces a definition-resolution failure and scrubs the record' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null)
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $Result = Get-OERAccessReviewInstance -Definition 'Q3' -Instance 'i1' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            # Zero Graph calls is what distinguishes the resolver catch from the two GET catches.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            @($Err | Where-Object {
                    $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionResolveFailed,Get-OERAccessReviewInstance'
                }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'warns and falls back to an empty stage list when the stages sub-request fails' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*/stages') { throw [System.Exception]::new('Forbidden') }
                return @{ id = 'i1'; status = 'InProgress' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            # -WarningVariable is declared on the CALL, in this It's own scope. Declaring it inside a
            # { } | Should -Not -Throw scriptblock would populate a child-scope copy and leave $Warnings
            # $null here.
            $Result = Get-OERAccessReviewInstance -Definition 'Q3' -Instance 'i1' -IncludeStages `
                -WarningVariable Warnings
            # The main read still succeeded, so the instance is emitted despite the failed sub-request.
            $Result | Should -Not -BeNullOrEmpty
            $Result.Id | Should -Be 'i1'
            @($Warnings).Count | Should -Be 1
            @($Warnings)[0] | Should -Match 'Could not read stages'
            @($Result.Stages).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }

        It 'warns and falls back to an empty decision list when the decisions sub-request fails' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*/decisions*') { throw [System.Exception]::new('Forbidden') }
                return @{ id = 'i1'; status = 'InProgress' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $Result = Get-OERAccessReviewInstance -Definition 'Q3' -Instance 'i1' -IncludeDecisions `
                -WarningVariable Warnings
            $Result | Should -Not -BeNullOrEmpty
            $Result.Id | Should -Be 'i1'
            @($Warnings).Count | Should -Be 1
            @($Warnings)[0] | Should -Match 'Could not read decisions'
            @($Result.Decisions).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        }
    }

    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the instances list read' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
            }
            @(Get-OERAccessReviewInstance -Definition 'Q3') | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances?$select=id,status,startDateTime,endDateTime,scope' -and $All
            }
        }

        It 'passes -All to the stages sub-read for -IncludeStages' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*/stages') { return @{ value = @(@{ id = 's1'; status = 'InProgress' }) } }
                return @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
            }
            Get-OERAccessReviewInstance -Definition 'Q3' -IncludeStages | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/stages' -and $All
            }
        }

        It 'passes -All to the decisions sub-read for -IncludeDecisions' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*/decisions*') {
                    return @{ value = @(@{ id = 'dec1'; decision = 'Approve'; principal = @{ displayName = 'Anna' } }) }
                }
                return @{ value = @(@{ id = 'i1'; status = 'InProgress' }) }
            }
            Get-OERAccessReviewInstance -Definition 'Q3' -IncludeDecisions | Out-Null
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq ('v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/decisions' +
                          '?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,' +
                          'applyResult,principal,resource,recommendation') -and $All
            }
        }
    }
}

Describe 'Get-OERAccessReviewInstance returned shape' {
    <#
        THE PIN. Issue #74 adds $select to the instance and decision reads. A $select that drops a
        field a converter reads reintroduces the null-field class of bug PR #45 fixed, and does it
        SILENTLY -- discovered live, by a converter returning $null. These assertions are written
        against the code BEFORE the query changes, so that the change has something to be measured
        against. If a later change to the REQUEST moves any assertion here, the change was not
        shape-preserving and the assertion is right.

        Every raw fixture below carries EXTRA fields the converters do not read (errors, insights,
        principalLink, resourceLink, appliedDateTime, accessReviewId). That is deliberate: it is
        what a real Graph response looks like without $select, and it proves the pin measures the
        converter's output rather than the fixture's input.
    #>
    BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            if ($Uri -match '/decisions') {
                return @{ value = @(
                    @{
                        id               = 'dec-1'
                        decision         = 'Approve'
                        justification    = 'still needed'
                        reviewedBy       = @{ id = 'rev-1'; displayName = 'Reviewer One' }
                        reviewedDateTime = '2026-08-02T00:00:00Z'
                        appliedBy        = @{ id = 'app-1'; displayName = 'Applier One' }
                        applyResult      = 'Applied'
                        principal        = @{ id = 'prin-1'; displayName = 'Principal One' }
                        resource         = @{ id = 'res-1'; displayName = 'Resource One' }
                        recommendation   = 'Approve'
                        # Fields no converter reads -- present exactly as Graph sends them today.
                        accessReviewId   = 'inst-1'
                        appliedDateTime  = '2026-08-03T00:00:00Z'
                        principalLink    = 'https://graph.microsoft.com/v1.0/users/prin-1'
                        resourceLink     = 'https://graph.microsoft.com/v1.0/groups/res-1'
                        insights         = @()
                    }
                ) }
            }
            if ($Uri -match '/stages') {
                return @{ value = @(
                    @{
                        id                = 'stg-1'
                        status            = 'InProgress'
                        startDateTime     = '2026-08-01T00:00:00Z'
                        endDateTime       = '2026-08-08T00:00:00Z'
                        reviewers         = @(@{ query = './manager'; queryType = 'MicrosoftGraph' })
                        fallbackReviewers = @(@{ query = '/users/u1'; queryType = 'MicrosoftGraph' })
                    }
                ) }
            }
            return @{ value = @(
                @{
                    id            = 'inst-1'
                    status        = 'InProgress'
                    startDateTime = '2026-08-01T00:00:00Z'
                    endDateTime   = '2026-08-08T00:00:00Z'
                    scope         = @{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }
                    # A field no converter reads.
                    errors        = @()
                }
            ) }
        }
    }

    It 'emits exactly the instance properties the converter owns, in order' {
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review'
        @($Inst).Count | Should -Be 1
        @($Inst.PSObject.TypeNames)[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewInstance'
        @($Inst.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } |
            ForEach-Object { $_.Name }) |
            Should -Be @('AccessReviewInstanceId', 'Status', 'StartDateTime', 'EndDateTime',
                         'AccessReviewDefinitionId', 'Scope')
        $Inst.AccessReviewInstanceId   | Should -Be 'inst-1'
        $Inst.Status                   | Should -Be 'InProgress'
        $Inst.StartDateTime            | Should -Be '2026-08-01T00:00:00Z'
        $Inst.EndDateTime              | Should -Be '2026-08-08T00:00:00Z'
        $Inst.AccessReviewDefinitionId | Should -Be 'def-1'
        $Inst.Scope                    | Should -Be '/groups/g1/transitiveMembers'
    }

    It 'emits exactly the stage properties the converter owns, in order' {
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeStages
        $Stage = @($Inst.Stages)[0]
        @($Stage.PSObject.TypeNames)[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewStage'
        @($Stage.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } |
            ForEach-Object { $_.Name }) |
            Should -Be @('Status', 'StartDateTime', 'EndDateTime', 'Reviewers', 'FallbackReviewers',
                         'AccessReviewStageId', 'AccessReviewInstanceId', 'AccessReviewDefinitionId')
        $Stage.AccessReviewStageId      | Should -Be 'stg-1'
        $Stage.Status                   | Should -Be 'InProgress'
        $Stage.StartDateTime            | Should -Be '2026-08-01T00:00:00Z'
        $Stage.EndDateTime              | Should -Be '2026-08-08T00:00:00Z'
        @($Stage.Reviewers).Count         | Should -Be 1
        @($Stage.Reviewers)[0].query      | Should -Be './manager'
        @($Stage.FallbackReviewers).Count | Should -Be 1
        @($Stage.FallbackReviewers)[0].query | Should -Be '/users/u1'
        $Stage.AccessReviewInstanceId   | Should -Be 'inst-1'
        $Stage.AccessReviewDefinitionId | Should -Be 'def-1'
    }

    It 'emits exactly the decision properties the converter owns, in order' {
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeDecisions
        $Dec = @($Inst.Decisions)[0]
        @($Dec.PSObject.TypeNames)[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDecision'
        @($Dec.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } |
            ForEach-Object { $_.Name }) |
            Should -Be @('Id', 'Decision', 'Justification', 'ReviewedByDisplayName',
                         'ReviewedDateTime', 'AppliedByDisplayName', 'ApplyResult', 'PrincipalId',
                         'PrincipalDisplayName', 'ResourceId', 'ResourceDisplayName', 'Recommendation')
        $Dec.Id                    | Should -Be 'dec-1'
        $Dec.Decision              | Should -Be 'Approve'
        $Dec.Justification         | Should -Be 'still needed'
        $Dec.ReviewedByDisplayName | Should -Be 'Reviewer One'
        $Dec.ReviewedDateTime      | Should -Be '2026-08-02T00:00:00Z'
        $Dec.AppliedByDisplayName  | Should -Be 'Applier One'
        $Dec.ApplyResult           | Should -Be 'Applied'
        $Dec.PrincipalId           | Should -Be 'prin-1'
        $Dec.PrincipalDisplayName  | Should -Be 'Principal One'
        $Dec.ResourceId            | Should -Be 'res-1'
        $Dec.ResourceDisplayName   | Should -Be 'Resource One'
        $Dec.Recommendation        | Should -Be 'Approve'
    }

    It 'keeps every registered alias on the emitted objects' {
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeDecisions
        $Dec  = @($Inst.Decisions)[0]

        # Omnicit.EntraRBAC.AccessReviewDecision aliases (source/suffix.ps1 lines 20-27):
        #   Principal   -> PrincipalDisplayName
        #   Resource    -> ResourceDisplayName
        #   ReviewedBy  -> ReviewedByDisplayName
        #   AppliedBy   -> AppliedByDisplayName
        @($Dec.PSObject.Properties['Principal'])  | Should -Not -BeNullOrEmpty
        $Dec.Principal   | Should -Be $Dec.PrincipalDisplayName
        @($Dec.PSObject.Properties['Resource'])   | Should -Not -BeNullOrEmpty
        $Dec.Resource    | Should -Be $Dec.ResourceDisplayName
        @($Dec.PSObject.Properties['ReviewedBy']) | Should -Not -BeNullOrEmpty
        $Dec.ReviewedBy  | Should -Be $Dec.ReviewedByDisplayName
        @($Dec.PSObject.Properties['AppliedBy'])  | Should -Not -BeNullOrEmpty
        $Dec.AppliedBy   | Should -Be $Dec.AppliedByDisplayName

        # Omnicit.EntraRBAC.AccessReviewInstance aliases (source/suffix.ps1 lines 63-66):
        #   Id           -> AccessReviewInstanceId
        #   DefinitionId -> AccessReviewDefinitionId
        @($Inst.PSObject.Properties['Id'])           | Should -Not -BeNullOrEmpty
        $Inst.Id           | Should -Be $Inst.AccessReviewInstanceId
        @($Inst.PSObject.Properties['DefinitionId']) | Should -Not -BeNullOrEmpty
        $Inst.DefinitionId | Should -Be $Inst.AccessReviewDefinitionId
    }

    It 'still emits the single-instance read with the same shape' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            @{
                id            = 'inst-1'
                status        = 'Completed'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-08T00:00:00Z'
                scope         = @{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }
                errors        = @()
            }
        }
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'inst-1'
        @($Inst).Count | Should -Be 1
        @($Inst.PSObject.TypeNames)[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewInstance'
        @($Inst.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } |
            ForEach-Object { $_.Name }) |
            Should -Be @('AccessReviewInstanceId', 'Status', 'StartDateTime', 'EndDateTime',
                         'AccessReviewDefinitionId', 'Scope')
        $Inst.AccessReviewInstanceId   | Should -Be 'inst-1'
        $Inst.Status                   | Should -Be 'Completed'
        $Inst.StartDateTime            | Should -Be '2026-08-01T00:00:00Z'
        $Inst.EndDateTime              | Should -Be '2026-08-08T00:00:00Z'
        $Inst.AccessReviewDefinitionId | Should -Be 'def-1'
        $Inst.Scope                    | Should -Be '/groups/g1/transitiveMembers'
    }
}

Describe 'Get-OERAccessReviewInstance request shape' {
    <#
        Issue #74. The instance and decision reads now ask Graph only for the fields the converters
        read. The pin block above proves the returned SHAPE is unchanged; these tests prove the
        REQUEST changed, and the three select-respecting tests below -- one per read path: list,
        single-instance and decision -- prove the shape survives even when
        Graph honours the select literally -- which the pin structurally CANNOT prove, since its mock
        returns full fixtures whatever the query string says, so a select missing a field would leave
        the property name in place with a $null value and the pin would stay green.
    #>
    BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            if ($Uri -match '/decisions') { return @{ value = @() } }
            if ($Uri -match '/stages')    { return @{ value = @() } }
            return @{ value = @(@{ id = 'inst-1'; status = 'InProgress'; scope = @{ query = '/groups/g1' } }) }
        }
    }

    It 'selects only the instance fields the converter reads on the list read' {
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-1/instances?$select=id,status,startDateTime,endDateTime,scope'
        }
    }

    It 'selects only the instance fields the converter reads on the single-instance read' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            @{ id = 'inst-1'; status = 'InProgress'; scope = @{ query = '/groups/g1' } }
        }
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'inst-1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-1/instances/inst-1?$select=id,status,startDateTime,endDateTime,scope'
        }
    }

    It 'selects only the decision fields the converter reads' {
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeDecisions
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq ('v1.0/identityGovernance/accessReviews/definitions/def-1/instances/inst-1/decisions' +
                      '?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,' +
                      'applyResult,principal,resource,recommendation')
        }
    }

    It 'leaves the stages read without a select, since the converter reads every stage property' {
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeStages
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-1/instances/inst-1/stages'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -match '/stages\?'
        }
    }

    It 'selects every field the instance converter reads, with none missing and none spare' {
        <#
            The DRIFT guard. The two lists in the cmdlet are literal strings; if a converter later
            starts reading a field the select does not name, that field arrives $null and nothing
            here would notice. This derives the required set from the converter's own source and
            compares it to what the cmdlet actually asked for -- so adding a read to the converter
            without adding it to the select fails HERE rather than live.
        #>
        # SOURCE IDIOM THIS GUARD DEPENDS ON. The regex below matches the converter's own
        # $InputObject.<name> read form, and nothing else. [A-Za-z]+ cannot cross a '.', so a nested
        # read yields the PARENT property name -- which is the name the select must carry. A future
        # refactor of the converter to $InputObject['scope'], or to an intermediate variable, would
        # shrink the derived set and redden this guard on a select that is in fact correct. That
        # failure is loud and easy to diagnose, but it is the maintenance cost of deriving the
        # required set from source instead of restating it as a list that could itself drift.
        #
        # The mock body runs in the TEST file's script scope, not the module's -- reading the capture
        # back with InModuleScope returns $null and the control below then fails, which is how this
        # was caught. tests/Unit/Private/Initialize-OERAuth.Tests.ps1 uses the same direct read.
        $script:CapturedUri = $null
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            $script:CapturedUri = $Uri
            @{ value = @() }
        }
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review'
        $Captured = $script:CapturedUri
        # Control: the capture site was reached. Without this the checks below pass vacuously.
        $Captured | Should -Not -BeNullOrEmpty

        $Selected = @((($Captured -split '\$select=')[1]) -split ',')
        $ConverterSource = Get-Content -Raw (Join-Path $PSScriptRoot '..\..\..\source\Private\ConvertTo-OERAccessReviewInstance.ps1')
        $Read = @([regex]::Matches($ConverterSource, '\$InputObject\.([A-Za-z]+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        # Control: the regex found fields to compare against, so an empty $Read cannot pass the
        # foreach below vacuously.
        @($Read).Count | Should -BeGreaterThan 0
        foreach ($Field in $Read) {
            $Selected | Should -Contain $Field -Because "the instance converter reads $Field, so the select must name it"
        }
        # None spare: every selected field is one the converter actually reads.
        foreach ($Field in $Selected) {
            $Read | Should -Contain $Field -Because "the select asks for $Field, which no converter read justifies"
        }
    }

    It 'selects every field the decision converter reads, with none missing and none spare' {
        <#
            The sibling DRIFT guard, for the DECISION select. That list is the longer of the two and
            the riskier one: four of its ten entries (reviewedBy, appliedBy, principal, resource) are
            complex types selected WHOLE, and dropping one nulls TWO output properties at once. Same
            derivation and the same two controls as the instance guard above.
        #>
        # SOURCE IDIOM THIS GUARD DEPENDS ON. The regex below matches the converter's own
        # $InputObject.<name> read form, and nothing else. [A-Za-z]+ cannot cross a '.', so
        # $InputObject.principal.displayName yields the PARENT name 'principal' -- exactly the name
        # the select must carry, since the complex type is selected whole and 'principal/id' would be
        # wrong. A future refactor of the converter to $InputObject['principal'], or to an
        # intermediate variable, would shrink the derived set and redden this guard on a select that
        # is in fact correct. That failure is loud and easy to diagnose, but it is the maintenance
        # cost of deriving the required set from source instead of restating it as a list.
        #
        # As above, the mock body runs in the TEST file's script scope, so the capture is read back
        # directly rather than through InModuleScope.
        $script:CapturedDecisionUri = $null
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            if ($Uri -match '/decisions') {
                $script:CapturedDecisionUri = $Uri
                return @{ value = @() }
            }
            if ($Uri -match '/stages') { return @{ value = @() } }
            @{ value = @(@{ id = 'inst-1'; status = 'InProgress'; scope = @{ query = '/groups/g1' } }) }
        }
        $null = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeDecisions
        $Captured = $script:CapturedDecisionUri
        # Control: the decision read was reached. Without this the checks below pass vacuously.
        $Captured | Should -Not -BeNullOrEmpty

        $Selected = @((($Captured -split '\$select=')[1]) -split ',')
        $ConverterSource = Get-Content -Raw (Join-Path $PSScriptRoot '..\..\..\source\Private\ConvertTo-OERAccessReviewDecision.ps1')
        $Read = @([regex]::Matches($ConverterSource, '\$InputObject\.([A-Za-z]+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        # Control: the regex found fields to compare against, so an empty $Read cannot pass the
        # foreach below vacuously.
        @($Read).Count | Should -BeGreaterThan 0
        foreach ($Field in $Read) {
            $Selected | Should -Contain $Field -Because "the decision converter reads $Field, so the select must name it"
        }
        # None spare: every selected field is one the converter actually reads.
        foreach ($Field in $Selected) {
            $Read | Should -Contain $Field -Because "the select asks for $Field, which no decision converter read justifies"
        }
    }

    It 'returns a fully populated instance even when Graph honours the select literally' {
        <#
            The gap the shape pin structurally cannot close. The pin's mock ignores the query string
            and always returns full fixtures, so a select that drops a field leaves the property NAME
            in place with a $null value and the pin stays green. This mock instead PARSES the select
            out of the URI and returns only those fields -- exactly what Graph does -- so a dropped
            field shows up here as a null property.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            $Full = @{
                id            = 'inst-1'
                status        = 'InProgress'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-08T00:00:00Z'
                scope         = @{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }
                errors        = @()
            }
            # Graph returns ONLY what was selected. A field the select omits is simply absent, which
            # is exactly how a dropped field reaches a converter as $null.
            $Selected = @((($Uri -split '\$select=')[1]) -split ',')
            $Trimmed = @{}
            foreach ($Key in $Selected) { if ($Full.ContainsKey($Key)) { $Trimmed[$Key] = $Full[$Key] } }
            @{ value = @($Trimmed) }
        }
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review'
        # Control: the trimming mock produced an object at all, so the null checks below are real.
        $Inst | Should -Not -BeNullOrEmpty
        # Every property the converter owns must still be populated.
        $Inst.AccessReviewInstanceId   | Should -Not -BeNullOrEmpty
        $Inst.Status                   | Should -Not -BeNullOrEmpty
        $Inst.StartDateTime            | Should -Not -BeNullOrEmpty
        $Inst.EndDateTime              | Should -Not -BeNullOrEmpty
        $Inst.Scope                    | Should -Not -BeNullOrEmpty
        $Inst.AccessReviewDefinitionId | Should -Not -BeNullOrEmpty
        # And carrying the values the fixture held, not merely non-null.
        $Inst.AccessReviewInstanceId | Should -Be 'inst-1'
        $Inst.Status                 | Should -Be 'InProgress'
        $Inst.StartDateTime          | Should -Be '2026-08-01T00:00:00Z'
        $Inst.EndDateTime            | Should -Be '2026-08-08T00:00:00Z'
        $Inst.Scope                  | Should -Be '/groups/g1/transitiveMembers'
    }

    It 'returns a fully populated single-instance read even when Graph honours the select literally' {
        <#
            The same proof for the -Instance path, which is a DIFFERENT code path from the list read
            and was defended only by a URI string comparison and by the shape pin -- and the pin's
            mock returns full fixtures whatever the query string says, so it structurally cannot see
            a dropped field. Note the shape: the single-instance GET returns the resource ITSELF,
            not a { value = ... } collection, so the mock returns a bare object.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            $Full = @{
                id            = 'inst-1'
                status        = 'Completed'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-08T00:00:00Z'
                scope         = @{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }
                errors        = @()
            }
            $Selected = @((($Uri -split '\$select=')[1]) -split ',')
            $Trimmed = @{}
            foreach ($Key in $Selected) { if ($Full.ContainsKey($Key)) { $Trimmed[$Key] = $Full[$Key] } }
            $Trimmed
        }
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'inst-1'
        # Control: the trimming mock produced an object at all, so the null checks below are real.
        # Without it a mock that returned nothing would satisfy every -Not -BeNullOrEmpty vacuously
        # -- there would be no object to read a property from.
        $Inst | Should -Not -BeNullOrEmpty
        # Every property the converter owns must still be populated.
        $Inst.AccessReviewInstanceId   | Should -Not -BeNullOrEmpty
        $Inst.Status                   | Should -Not -BeNullOrEmpty
        $Inst.StartDateTime            | Should -Not -BeNullOrEmpty
        $Inst.EndDateTime              | Should -Not -BeNullOrEmpty
        $Inst.Scope                    | Should -Not -BeNullOrEmpty
        $Inst.AccessReviewDefinitionId | Should -Not -BeNullOrEmpty
        # And carrying the values the fixture held, not merely non-null.
        $Inst.AccessReviewInstanceId   | Should -Be 'inst-1'
        $Inst.Status                   | Should -Be 'Completed'
        $Inst.StartDateTime            | Should -Be '2026-08-01T00:00:00Z'
        $Inst.EndDateTime              | Should -Be '2026-08-08T00:00:00Z'
        $Inst.Scope                    | Should -Be '/groups/g1/transitiveMembers'
        $Inst.AccessReviewDefinitionId | Should -Be 'def-1'
    }

    It 'returns a fully populated decision even when Graph honours the select literally' {
        <#
            The same proof for the decision read, whose select is the longer of the two and whose
            complex types (reviewedBy, appliedBy, principal, resource) are selected WHOLE -- the
            converter reaches into .id and .displayName on each, so dropping a parent name from the
            select would null TWO output properties at once.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Method, $Uri, $Body, $All, $ExpectedErrorCode)
            $FullInstance = @{
                id            = 'inst-1'
                status        = 'InProgress'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-08T00:00:00Z'
                scope         = @{ query = '/groups/g1/transitiveMembers'; queryType = 'MicrosoftGraph' }
                errors        = @()
            }
            $FullDecision = @{
                id               = 'dec-1'
                decision         = 'Approve'
                justification    = 'still needed'
                reviewedBy       = @{ id = 'rev-1'; displayName = 'Reviewer One' }
                reviewedDateTime = '2026-08-02T00:00:00Z'
                appliedBy        = @{ id = 'app-1'; displayName = 'Applier One' }
                applyResult      = 'Applied'
                principal        = @{ id = 'prin-1'; displayName = 'Principal One' }
                resource         = @{ id = 'res-1'; displayName = 'Resource One' }
                recommendation   = 'Approve'
                appliedDateTime  = '2026-08-03T00:00:00Z'
                insights         = @()
            }
            $Full = if ($Uri -match '/decisions') { $FullDecision } else { $FullInstance }
            $Selected = @((($Uri -split '\$select=')[1]) -split ',')
            $Trimmed = @{}
            foreach ($Key in $Selected) { if ($Full.ContainsKey($Key)) { $Trimmed[$Key] = $Full[$Key] } }
            @{ value = @($Trimmed) }
        }
        $Inst = Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -IncludeDecisions
        $Dec = @($Inst.Decisions)[0]
        # Control: the decision read was reached and produced an object, so the checks below are real.
        $Dec | Should -Not -BeNullOrEmpty
        # All twelve properties the decision converter owns must still be populated.
        $Dec.Id                    | Should -Not -BeNullOrEmpty
        $Dec.Decision              | Should -Not -BeNullOrEmpty
        $Dec.Justification         | Should -Not -BeNullOrEmpty
        $Dec.ReviewedByDisplayName | Should -Not -BeNullOrEmpty
        $Dec.ReviewedDateTime      | Should -Not -BeNullOrEmpty
        $Dec.AppliedByDisplayName  | Should -Not -BeNullOrEmpty
        $Dec.ApplyResult           | Should -Not -BeNullOrEmpty
        $Dec.PrincipalId           | Should -Not -BeNullOrEmpty
        $Dec.PrincipalDisplayName  | Should -Not -BeNullOrEmpty
        $Dec.ResourceId            | Should -Not -BeNullOrEmpty
        $Dec.ResourceDisplayName   | Should -Not -BeNullOrEmpty
        $Dec.Recommendation        | Should -Not -BeNullOrEmpty
        # And carrying the values the fixture held, not merely non-null.
        $Dec.Id                    | Should -Be 'dec-1'
        $Dec.Decision              | Should -Be 'Approve'
        $Dec.Justification         | Should -Be 'still needed'
        $Dec.ReviewedByDisplayName | Should -Be 'Reviewer One'
        $Dec.ReviewedDateTime      | Should -Be '2026-08-02T00:00:00Z'
        $Dec.AppliedByDisplayName  | Should -Be 'Applier One'
        $Dec.ApplyResult           | Should -Be 'Applied'
        $Dec.PrincipalId           | Should -Be 'prin-1'
        $Dec.PrincipalDisplayName  | Should -Be 'Principal One'
        $Dec.ResourceId            | Should -Be 'res-1'
        $Dec.ResourceDisplayName   | Should -Be 'Resource One'
        $Dec.Recommendation        | Should -Be 'Approve'
    }
}
