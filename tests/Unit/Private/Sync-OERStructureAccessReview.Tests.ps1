BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Sync-OERStructureAccessReview' {

    It 'creates a missing access review with mapped recurrence and manager reviewer' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Quarterly AP-Sales' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Quarterly AP-Sales'
                accessPackage     = 'AP-Sales'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'quarterly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter { $Recurrence -eq 'Quarterly' -and $Manager -eq $true -and $FallbackReviewer -contains 'fallback@contoso.com' }
        }
    }

    It 'reports Unchanged when definition with matching DisplayName already exists and does not call New-OERAccessReviewDefinition' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            # The live definition carries the same reviewer (manager), cadence and start date the
            # document declares, so the reconcile has nothing to write.
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = 'ar-1'
                    DisplayName        = 'Quarterly AP-Sales'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = './manager' })
                    FallbackReviewers  = @()
                    DurationInDays     = 14
                    Recurrence         = @{
                        pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                        range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                    }
                    Settings           = @{ instanceDurationInDays = 14 }
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Quarterly AP-Sales' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Quarterly AP-Sales'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Quarterly'
            }))
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
        }
    }

    It 'maps UPN reviewers to -Reviewer array and non-UPN non-keyword entries to -ReviewerGroup array' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-2'; DisplayName = 'Mixed Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Mixed Review'
                accessPackage    = 'AP-HR'
                assignmentPolicy = 'Default'
                reviewers        = @('admin@contoso.com', 'IT-Reviewers')
                recurrence       = 'Monthly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $Reviewer -contains 'admin@contoso.com' -and $ReviewerGroup -contains 'IT-Reviewers'
            }
        }
    }

    It 'maps fallbackReviewers UPN to -FallbackReviewer and a non-UPN entry to -FallbackReviewerGroup' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-fb'; DisplayName = 'Fallback Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Fallback Review'
                accessPackage     = 'AP-Sales'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fb@contoso.com', 'IT-Fallbacks')
                recurrence        = 'Quarterly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $FallbackReviewer -contains 'fb@contoso.com' -and $FallbackReviewerGroup -contains 'IT-Fallbacks'
            }
        }
    }

    It 'reports Failed (no create) when a manager reviewer has no fallbackReviewers' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-x'; DisplayName = 'No Fallback' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'No Fallback'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Quarterly'
            }))
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            ($r | Where-Object { $_.Action -eq 'Failed' }).Detail | Should -BeLike '*fallbackReviewers*'
            Should -Invoke New-OERAccessReviewDefinition -Times 0
        }
    }

    It 'maps reviewer self to -SelfReview switch' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-3'; DisplayName = 'Self Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Self Review'
                accessPackage    = 'AP-Dev'
                assignmentPolicy = 'Default'
                reviewers        = @('self')
                recurrence       = 'OneTime'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter { $SelfReview -eq $true }
        }
    }

    # Issue #56 class on the CREATE path: a declared-EMPTY reviewers array must stay distinguishable
    # from an OMITTED one. The old gate read
    #     $Item.PSObject.Properties.Name -contains 'reviewers' -and $Item.reviewers -and @(...).Count -gt 0
    # and [bool]@() is $false, so "reviewers": [] short-circuited at the MIDDLE clause into the
    # omitted-key manager default -- contradicting this same handler's UPDATE path, which reads the
    # identical [] as a self review. With no fallbackReviewers that produced a Failed record and ZERO
    # creates, so nothing existed for the next run to converge against: a permanent Failed.
    #
    # Every case below asserts on the New-OERAccessReviewDefinition SPLAT (which switch is BOUND),
    # never on the result record alone -- a Created record alone would still pass with the review
    # created as the wrong reviewer kind. Capturing the splat needs an explicit param() block on the
    # mock body: Pester does not populate $PSBoundParameters unless the scriptblock declares matching
    # parameters (the same note as Invoke-OERArmRequest.Tests.ps1).
    Context 'reviewers declared EMPTY versus ABSENT on the create path' {

        BeforeEach {
            InModuleScope $script:moduleName {
                $script:CapturedNewParams = $null
            }
        }

        It 'creates a SELF review when reviewers is declared empty and no fallbackReviewers exist' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition {
                    param($DisplayName, $DescriptionForAdmins, $DescriptionForReviewers, $AccessPackage,
                        $AssignmentPolicy, $Catalog, $Reviewer, $ReviewerGroup, $Manager, $SelfReview,
                        $FallbackReviewer, $FallbackReviewerGroup, $Recurrence, $StartDate, $EndDate,
                        $Occurrences, $DurationInDays, $MailNotification, $ReminderNotification,
                        $RequireJustification, $RecommendationsEnabled, $AutoApplyDecisions,
                        $DefaultDecision, $TenantId)
                    $script:CapturedNewParams = $PSBoundParameters
                    [PSCustomObject]@{ Id = 'ar-empty'; DisplayName = $DisplayName }
                }
                Mock Write-Warning { }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -Item ([PSCustomObject]@{
                    displayName      = 'Empty Reviewers No Fallback'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @()
                    recurrence       = 'Quarterly'
                }))

                # Before the fix: one Failed record and ZERO creates, repeated identically forever.
                ($r | Where-Object Action -eq 'Failed').Count  | Should -Be 0
                ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly

                $script:CapturedNewParams.ContainsKey('SelfReview')    | Should -BeTrue
                $script:CapturedNewParams['SelfReview']                | Should -BeTrue
                $script:CapturedNewParams.ContainsKey('Manager')       | Should -BeFalse
                $script:CapturedNewParams.ContainsKey('Reviewer')      | Should -BeFalse
                $script:CapturedNewParams.ContainsKey('ReviewerGroup') | Should -BeFalse

                # Downstream guard 1 -- the self/manager-mix warning. It is the only Write-Warning
                # reachable on the create path, and it would have cleared $AddSelfReview had it fired.
                Should -Invoke Write-Warning -Times 0 -Exactly
                # Downstream guard 2 -- manager-requires-fallback. Proven not to fire by the create
                # above: it returns before New-OERAccessReviewDefinition is ever reached.
            }
        }

        It 'creates a SELF review, not a manager review, when reviewers is declared empty alongside fallbackReviewers' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition {
                    param($DisplayName, $DescriptionForAdmins, $DescriptionForReviewers, $AccessPackage,
                        $AssignmentPolicy, $Catalog, $Reviewer, $ReviewerGroup, $Manager, $SelfReview,
                        $FallbackReviewer, $FallbackReviewerGroup, $Recurrence, $StartDate, $EndDate,
                        $Occurrences, $DurationInDays, $MailNotification, $ReminderNotification,
                        $RequireJustification, $RecommendationsEnabled, $AutoApplyDecisions,
                        $DefaultDecision, $TenantId)
                    $script:CapturedNewParams = $PSBoundParameters
                    [PSCustomObject]@{ Id = 'ar-empty-fb'; DisplayName = $DisplayName }
                }
                Mock Write-Warning { }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -Item ([PSCustomObject]@{
                    displayName       = 'Empty Reviewers With Fallback'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    reviewers         = @()
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Quarterly'
                }))

                ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly

                # Before the fix this created a MANAGER review -- a state the document never asked
                # for, which the update path then rewrote on run 2 as the self review it reads [] to be.
                $script:CapturedNewParams.ContainsKey('SelfReview') | Should -BeTrue
                $script:CapturedNewParams['SelfReview']             | Should -BeTrue
                $script:CapturedNewParams.ContainsKey('Manager')    | Should -BeFalse
                # The declared fallback is still forwarded for round-trip fidelity.
                $script:CapturedNewParams.ContainsKey('FallbackReviewer') | Should -BeTrue
                Should -Invoke Write-Warning -Times 0 -Exactly
            }
        }

        It 'still takes the -Manager default when reviewers is OMITTED entirely' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition {
                    param($DisplayName, $DescriptionForAdmins, $DescriptionForReviewers, $AccessPackage,
                        $AssignmentPolicy, $Catalog, $Reviewer, $ReviewerGroup, $Manager, $SelfReview,
                        $FallbackReviewer, $FallbackReviewerGroup, $Recurrence, $StartDate, $EndDate,
                        $Occurrences, $DurationInDays, $MailNotification, $ReminderNotification,
                        $RequireJustification, $RecommendationsEnabled, $AutoApplyDecisions,
                        $DefaultDecision, $TenantId)
                    $script:CapturedNewParams = $PSBoundParameters
                    [PSCustomObject]@{ Id = 'ar-omitted'; DisplayName = $DisplayName }
                }
                Mock Write-Warning { }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -Item ([PSCustomObject]@{
                    displayName       = 'Omitted Reviewers'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Quarterly'
                }))

                ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly

                # The regression guard for the whole change: deleting the declared/empty split must
                # not turn the omitted-key default into a self review.
                $script:CapturedNewParams.ContainsKey('Manager')    | Should -BeTrue
                $script:CapturedNewParams['Manager']                | Should -BeTrue
                $script:CapturedNewParams.ContainsKey('SelfReview') | Should -BeFalse
                Should -Invoke Write-Warning -Times 0 -Exactly
            }
        }

        It 'treats an explicitly null reviewers exactly as an omitted one on the create path' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition {
                    param($DisplayName, $DescriptionForAdmins, $DescriptionForReviewers, $AccessPackage,
                        $AssignmentPolicy, $Catalog, $Reviewer, $ReviewerGroup, $Manager, $SelfReview,
                        $FallbackReviewer, $FallbackReviewerGroup, $Recurrence, $StartDate, $EndDate,
                        $Occurrences, $DurationInDays, $MailNotification, $ReminderNotification,
                        $RequireJustification, $RecommendationsEnabled, $AutoApplyDecisions,
                        $DefaultDecision, $TenantId)
                    $script:CapturedNewParams = $PSBoundParameters
                    [PSCustomObject]@{ Id = 'ar-null'; DisplayName = $DisplayName }
                }
                Mock Write-Warning { }
                Mock Initialize-OERAuth {}

                # Note @($null).Count is 1, not 0, so a Count-only gate would read this as a declared
                # one-element list. Test-OERDeclaredProperty short-circuits first: an explicit null
                # counts as absent, so the Count is never reached.
                $r = @(Invoke-SyncArViaCaller -Item ([PSCustomObject]@{
                    displayName       = 'Null Reviewers'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    reviewers         = $null
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Quarterly'
                }))

                ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly

                $script:CapturedNewParams.ContainsKey('Manager')       | Should -BeTrue
                $script:CapturedNewParams['Manager']                   | Should -BeTrue
                $script:CapturedNewParams.ContainsKey('SelfReview')    | Should -BeFalse
                $script:CapturedNewParams.ContainsKey('Reviewer')      | Should -BeFalse
                $script:CapturedNewParams.ContainsKey('ReviewerGroup') | Should -BeFalse
                Should -Invoke Write-Warning -Times 0 -Exactly
            }
        }

        # Issue #56's acceptance criteria are stated as convergence -- "reports Updated then
        # Unchanged" -- so the access-review half of that is proven here by APPLYING THE SAME
        # DOCUMENT TWICE rather than by reading the code. Run 1 creates the self review; run 2 sees
        # the state run 1 produced and must report Unchanged, not another write.
        #
        # The mechanism this pins is Resolve-OERAccessReviewChange.ps1:240-241, which maps an EMPTY
        # live Reviewers collection to the key ['self'], matching the update path's $UpdKey.Add('self')
        # at Sync-OERStructureAccessReview.ps1:252. If that mapping ever regresses, run 1 creates the
        # self review and run 2 sees a key mismatch and rewrites it on every run -- the same permanent
        # non-convergence class this branch exists to close, but uncaught.
        #
        # The run-2 live state is deliberately NOT hand-authored. Hand-authoring the expected end
        # state assumes away the write, and the write is the only place the non-convergence lives --
        # a sibling convergence test written that way on this branch PASSED against unfixed code.
        # Instead the tenant is SIMULATED from run 1's own output: the reviewer collections are built
        # by the module's own Resolve-OERReviewerScope, the very helper New-OERAccessReviewDefinition
        # calls at New-OERAccessReviewDefinition.ps1:314, fed the splat run 1 actually sent. So if
        # run 1 ever regresses to binding -Manager, this live state becomes a './manager' definition
        # and run 2 genuinely diverges.
        It 'converges: run 1 creates the self review and run 2 against that live state reports Unchanged' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }

                # ONE document object, applied twice -- exactly what an operator re-running an apply
                # would hand the engine. Nothing but reviewers is declared, so no other field can
                # manufacture drift and mask a reviewer mismatch.
                $Document = [PSCustomObject]@{
                    displayName      = 'Converging Self Review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @()
                }

                # A single read mock serving both runs: run 1 finds nothing, run 2 finds whatever run
                # 1 produced. Re-mocking the same command mid-test would depend on Pester's mock
                # precedence; a call counter does not.
                $script:ArReadCount   = 0
                $script:LiveAfterRun1 = $null
                Mock Get-OERAccessReviewDefinition {
                    $script:ArReadCount++
                    if ($script:ArReadCount -eq 1) { @() } else { $script:LiveAfterRun1 }
                }
                Mock New-OERAccessReviewDefinition {
                    param($DisplayName, $DescriptionForAdmins, $DescriptionForReviewers, $AccessPackage,
                        $AssignmentPolicy, $Catalog, $Reviewer, $ReviewerGroup, $Manager, $SelfReview,
                        $FallbackReviewer, $FallbackReviewerGroup, $Recurrence, $StartDate, $EndDate,
                        $Occurrences, $DurationInDays, $MailNotification, $ReminderNotification,
                        $RequireJustification, $RecommendationsEnabled, $AutoApplyDecisions,
                        $DefaultDecision, $TenantId)
                    $script:CapturedNewParams = $PSBoundParameters
                    [PSCustomObject]@{ Id = 'ar-conv'; DisplayName = $DisplayName }
                }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-conv' } }
                Mock Resolve-OERStructurePrincipal { 'must-not-be-called' }
                Mock Write-Warning { }
                Mock Initialize-OERAuth {}

                # -- Run 1: the definition does not exist yet --------------------------------
                $Run1 = @(Invoke-SyncArViaCaller -Item $Document)

                @($Run1).Action | Should -Contain 'Created'
                @($Run1).Action | Should -Not -Contain 'Failed'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly
                $script:CapturedNewParams.ContainsKey('SelfReview') | Should -BeTrue
                $script:CapturedNewParams['SelfReview']             | Should -BeTrue
                $script:CapturedNewParams.ContainsKey('Manager')    | Should -BeFalse

                # -- Simulate the tenant run 1 actually produced ------------------------------
                $ScopeParams = @{}
                foreach ($Key in @('Reviewer', 'ReviewerGroup', 'Manager', 'SelfReview',
                        'FallbackReviewer', 'FallbackReviewerGroup')) {
                    if ($script:CapturedNewParams.ContainsKey($Key)) {
                        $ScopeParams[$Key] = $script:CapturedNewParams[$Key]
                    }
                }
                $Produced = Resolve-OERReviewerScope @ScopeParams
                $script:LiveAfterRun1 = [PSCustomObject]@{
                    Id                 = 'ar-conv'
                    DisplayName        = [string]$script:CapturedNewParams['DisplayName']
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @($Produced.Reviewers)
                    FallbackReviewers  = @($Produced.FallbackReviewers)
                    DurationInDays     = 14
                    Settings           = @{ instanceDurationInDays = 14 }
                }
                # Guard the simulation itself: -SelfReview is the empty-reviewers shape, so if this
                # ever came back non-empty the run-2 assertions below would be judging a different
                # tenant than the one run 1 actually produced.
                @($script:LiveAfterRun1.Reviewers).Count | Should -Be 0

                # -- Run 2: the SAME document against the state run 1 produced -----------------
                $Run2 = @(Invoke-SyncArViaCaller -Item $Document)

                @($Run2).Action | Should -Contain 'Unchanged'
                @($Run2).Action | Should -Not -Contain 'Updated'
                @($Run2).Action | Should -Not -Contain 'Failed'
                # No second write of any kind: the create count is still run 1's single call, and the
                # update path never reaches Set-. This is the convergence.
                Should -Invoke Set-OERAccessReviewDefinition -Times 0 -Exactly
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly
                # An empty declared reviewer list resolves no tokens, so the update path performs no
                # principal lookups at all.
                Should -Invoke Resolve-OERStructurePrincipal -Times 0 -Exactly
                # Neither run emits the self/manager-mix warning nor a NotApplied note.
                Should -Invoke Write-Warning -Times 0 -Exactly
                $script:ArReadCount | Should -Be 2
            }
        }
    }

    It 'defaults DescriptionForAdmins from displayName when description properties are absent' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-4'; DisplayName = 'Default Desc Review' } }
            Mock Initialize-OERAuth {}
            Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Default Desc Review'
                accessPackage     = 'AP-Finance'
                assignmentPolicy  = 'Default'
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Annually'
            }) | Out-Null
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $DescriptionForAdmins -like '*Access review for*'
            }
        }
    }

    It 'defaults StartDate to a [datetime] when startDate is absent in the item' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            $CapturedStartDate = $null
            Mock New-OERAccessReviewDefinition {
                $script:CapturedStartDate = $StartDate
                [PSCustomObject]@{ Id = 'ar-5'; DisplayName = 'Date Default Review' }
            }
            Mock Initialize-OERAuth {}
            Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Date Default Review'
                accessPackage     = 'AP-Legal'
                assignmentPolicy  = 'Default'
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Weekly'
            }) | Out-Null
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $StartDate -is [datetime]
            }
        }
    }

    It 'under -WhatIf does not call New-OERAccessReviewDefinition and emits Skipped' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-6'; DisplayName = 'WhatIf Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'WhatIf Review'
                accessPackage    = 'AP-Ops'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Monthly'
            }) -WhatIf)
            Should -Invoke New-OERAccessReviewDefinition -Times 0
            ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
        }
    }

    It 'when Get-OERAccessReviewDefinition throws a throttle error emits Failed and does not call New-OERAccessReviewDefinition' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('429'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null
                )
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-7'; DisplayName = 'Throttle Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Throttle Review'
                accessPackage    = 'AP-Ops'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Monthly'
            }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
        }
    }

    It 'when Get-OERAccessReviewDefinition throws a NotFound error proceeds to Created (not Failed)' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Not found'),
                    'AccessReviewDefinitionNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null
                )
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-8'; DisplayName = 'NotFound Review' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'NotFound Review'
                accessPackage     = 'AP-Ops'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Monthly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
        }
    }

    # -- The existence probe must not leak the not-found record it depends on --------------------
    # A live run reported four fully successful access review CREATES and still left two
    # AccessReviewDefinitionNotFound records per create in the operator's error stream. All three
    # tests below drive the REAL Get-OERAccessReviewDefinition with only Invoke-OERGraphRequest
    # mocked: the leaked record is written by that cmdlet's own not-found branch, so a mock of the
    # cmdlet itself raises no record at all and every assertion here would pass against the broken
    # code.
    It 'leaves the caller error stream empty when no definition exists yet and the create succeeds' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-leak'; DisplayName = 'Leak Probe' } }
            Mock Initialize-OERAuth {}
            $ProbeLeak = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorVariable ProbeLeak -Item ([PSCustomObject]@{
                displayName       = 'Leak Probe'
                accessPackage     = 'AP-Ops'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Monthly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0
            $Leaked = @($ProbeLeak | Where-Object { $null -ne $_ })
            $Leaked.Count | Should -Be 0 -Because ('a create that fully succeeded must deposit nothing in the ' +
                'operator error stream; leaked: ' +
                (@($Leaked | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }
    }

    It 'reports Failed and creates nothing when the existence probe read genuinely fails' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            # A throttled read reaches the handler as a NON-terminating record published by
            # Get-OERAccessReviewDefinition -- the path the SilentlyContinue probe has to keep
            # telling apart from "nothing matched". This is the Sprint 1 guard: a failed read is not
            # an empty fact, and creating on one would duplicate a review that already exists.
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('429 Too Many Requests'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null)
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-nope'; DisplayName = 'Throttled Probe' } }
            Mock Initialize-OERAuth {}
            # fallbackReviewers is declared so the entry is otherwise CREATABLE. Without it the
            # manager-needs-a-fallback guard downstream would refuse the create for its own reason,
            # and the -Times 0 assertion below would pass even with this guard deleted.
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Throttled Probe'
                accessPackage     = 'AP-Ops'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Monthly'
            }))
            $Failed = @($r | Where-Object Action -eq 'Failed')
            $Failed.Count | Should -BeGreaterThan 0 -Because 'a read that never answered is not evidence that the definition is absent'
            # SCOPE OF THIS ASSERTION, stated honestly. It pins that the transport reason survives
            # into the reported cause -- an operator who cannot tell a 429 from a 403 cannot act on
            # either. It does NOT pin the publisher-membership clause in the handler: measured on
            # this exact fixture, $ProbeErrors holds 13 engine-collected strays plus the one record
            # Get-OERAccessReviewDefinition published, and 10 of those strays carry the identical
            # message, so the selection stays green with the clause deleted. Nor can the selected
            # record be identified after the fact: $Caller.WriteError republishes it, and PowerShell
            # rebuilds FullyQualifiedErrorId from the LAST publisher, so the read cmdlet's name is
            # already gone from the record attached here. The clause is pinned instead by the
            # retried-then-succeeded test below, where getting it wrong changes the ACTION.
            $Failed[0].Detail | Should -BeLike '*429 Too Many Requests*' -Because 'the transport reason must survive into the reported cause, or the operator cannot tell a 429 from a 403'
            Should -Invoke New-OERAccessReviewDefinition -Times 0 -Exactly
        }
    }

    It 'creates when the probe read was throttled, retried and then answered with zero matches' {
        # THE MUTATION TARGET for the publisher-membership clause in the handler. -ErrorVariable is
        # filled by the ENGINE, and it also collects records raised inside NESTED calls even when an
        # inner catch swallowed them -- and Invoke-OERGraphRequest swallows and retries a 429. So a
        # read that was throttled, retried and then answered PERFECTLY still leaves a pile of
        # TooManyRequests records (and message-less blanks) in the local collection beside the one
        # genuine AccessReviewDefinitionNotFound the read cmdlet published. Measured on the live
        # shape: 43 records, of which exactly one carried the publisher segment.
        #
        # Without the publisher clause the handler treats the first stray as proof the read never
        # answered, reports Failed and creates nothing against a tenant that was fine -- the same
        # false-failure class as the Sprint 1 defect this handler exists to prevent.
        #
        # Invoke-MgGraphRequest is mocked, not Invoke-OERGraphRequest, so the REAL wrapper, its REAL
        # throttle backoff and the REAL Get-OERAccessReviewDefinition all run. Mocking the wrapper
        # would skip the swallow-and-retry that deposits the strays this test is about.
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Initialize-OERAuth {}
            $script:_OERAuthState = @{ TenantId = 't'; Environment = 'Global'; GraphConnected = $true }
            $script:ThrottleCall = 0
            Mock Invoke-MgGraphRequest {
                $script:ThrottleCall++
                if ($script:ThrottleCall -le 3) {
                    $Resp = [PSCustomObject]@{ StatusCode = 429; Headers = @{ 'Retry-After' = '0' }; Content = $null }
                    $Ex = [System.Exception]::new('Too many requests')
                    $Ex | Add-Member -NotePropertyName Response -NotePropertyValue $Resp -Force
                    throw [System.Management.Automation.ErrorRecord]::new($Ex, 'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
                }
                return @{ value = @() }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Retried Probe' } }
            $ProbeLeak = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable ProbeLeak -Item ([PSCustomObject]@{
                    displayName       = 'Retried Probe'
                    accessPackage     = 'AP-Ops'
                    assignmentPolicy  = 'Default'
                    reviewers         = @('manager')
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Monthly'
                }))
            # Non-vacuity control FIRST: a fixture whose transport was never retried renders exactly
            # like a passing handler in the two assertions below.
            $script:ThrottleCall | Should -BeGreaterThan 3 -Because 'the throttled attempts must actually have been swallowed and retried, or no stray record exists to be misread'
            ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0 -Because ('the read answered; the throttle records collected beside it ' +
                'were swallowed and retried, and none of them was published by the read cmdlet. Actions: ' +
                (@($r | ForEach-Object { "$($_.Action)/$($_.Detail)" }) -join ' | '))
            ($r | Where-Object Action -eq 'Created').Count | Should -BeGreaterThan 0 -Because 'a read that answered with zero matches is evidence the definition is absent'
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly
            # And the successful create still deposits nothing in the operator error stream.
            $Leaked = @($ProbeLeak | Where-Object { $null -ne $_ })
            $Leaked.Count | Should -Be 0 -Because ('a create that fully succeeded must deposit nothing in the ' +
                'operator error stream; leaked: ' +
                (@($Leaked | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | '))
        }
    }

    It 'still finds an existing definition through the SilentlyContinue probe' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            # A Graph-shaped page carrying the declared definition, so the REAL read cmdlet converts
            # it and the probe's DisplayName match has something to find. The live values mirror the
            # declared document, so the reconcile has nothing to write.
            Mock Invoke-OERGraphRequest {
                @{
                    value = @(
                        @{
                            id                = 'ar-existing'
                            displayName       = 'Probe Finds Me'
                            scope             = @{ query = "accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1'" }
                            reviewers         = @(@{ query = './manager' })
                            fallbackReviewers = @()
                            settings          = @{
                                instanceDurationInDays = 14
                                recurrence             = @{
                                    pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                                }
                            }
                        }
                    )
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new'; DisplayName = 'Probe Finds Me' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-existing' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Probe Finds Me'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Quarterly'
            }))
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0 -Because 'the probe found the live definition, so nothing may be created over it'
            ($r | Where-Object Action -eq 'Unchanged').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0 -Exactly
        }
    }

    It 'when New-OERAccessReviewDefinition throws emits Failed and does not emit Created' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Fail Create Review'
                accessPackage     = 'AP-Ops'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Monthly'
            }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
            ($r | Where-Object Action -eq 'Created').Count | Should -Be 0
        }
    }

    It 'scrubs the bearer-hygiene record when New-OERAccessReviewDefinition throws' {
        # Drives the access-review creation catch in Sync-OERStructureAccessReview. The scrub under
        # test is this handler's OWN -- the Remove-OERErrorRecord opening the handler catch that
        # WRAPS the New-OERAccessReviewDefinition call, not a scrub inside
        # New-OERAccessReviewDefinition, which is mocked away here. That mocking is precisely what
        # makes the proof non-vacuous.
        # The static AST
        # gate proves that line is WRITTEN first; this It proves it actually RUNS. Mock +
        # Should -Invoke is the only proof shape that works here: the handler swallows the record
        # into a Failed result instead of re-throwing, so a $global:Error proof would be inert.
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { throw 'graph 500' }
            Mock Initialize-OERAuth {}
            Mock Remove-OERErrorRecord { }
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Fail Create Review'
                accessPackage     = 'AP-Ops'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'Monthly'
            }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'emits Failed and does not call New-OERAccessReviewDefinition when recurrence is unrecognised' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-x'; DisplayName = 'Bad Recurrence' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Bad Recurrence'
                accessPackage    = 'AP-X'
                assignmentPolicy = 'Default'
                reviewers        = @('manager')
                recurrence       = 'Biweekly'
            }) -ErrorAction SilentlyContinue)
            ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
        }
    }

    Context 'an explicit null recurrence behaves exactly like an omitted key' {
        It 'treats "recurrence": null as OneTime rather than an unrecognised value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'oer-ar' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName      = 'oer-ar'
                    accessPackage    = 'oer-ap'
                    assignmentPolicy = 'pol-1'
                    recurrence       = $null
                    reviewers        = @('self')
                }
                $Results = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item -ErrorAction SilentlyContinue)

                # Positive-identity assertion first: the create path must actually have run, or the
                # absence check below would pass just as well on an empty result set.
                @($Results | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0 -Because 'the create path must run for the absence check below to mean anything'

                @($Results | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'unrecognised recurrence' }).Count |
                    Should -Be 0 -Because 'an explicit null means exactly what an omitted key means, and an omitted recurrence defaults to OneTime'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Recurrence -eq 'OneTime' }
            }
        }

        It 'treats an omitted recurrence key the same as an explicit null -- both default to OneTime' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'oer-ar-omitted' } }
                Mock Initialize-OERAuth {}
                # No 'recurrence' key at all on this node -- this is the paired case to the explicit-null
                # test above. The two must assert the identical pair of outcomes, since that pairing is
                # what proves an explicit null means exactly what an omitted key means.
                $Item = [PSCustomObject]@{
                    displayName      = 'oer-ar-omitted'
                    accessPackage    = 'oer-ap'
                    assignmentPolicy = 'pol-1'
                    reviewers        = @('self')
                }
                $Results = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item -ErrorAction SilentlyContinue)

                # Positive-identity assertion first: the create path must actually have run, or the
                # absence check below would pass just as well on an empty result set.
                @($Results | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0 -Because 'the create path must run for the absence check below to mean anything'

                @($Results | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -match 'unrecognised recurrence' }).Count |
                    Should -Be 0 -Because 'an omitted key must default cleanly, exactly as the paired explicit-null case above does'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Recurrence -eq 'OneTime' }
            }
        }

        It 'does not downgrade a live Quarterly cadence to OneTime when an unrelated field update carries an explicit null recurrence' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # The update path is the one that actually reaches the shallow-copy guard (line 148):
                # the create path above never reads $DeclaredItem at all. Without the fix, the guard's
                # bare -contains test still sees the 'recurrence' PROPERTY (even though its value is
                # null), copies the document, and stamps the copy's recurrence with the mapped default
                # 'OneTime' -- so a document that only meant to update durationInDays would read back as
                # ALSO declaring a cadence change, silently downgrading a live Quarterly review to OneTime.
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'oer-ar-upd'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = './manager' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock Set-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'oer-ar-upd'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = './manager' })
                        FallbackReviewers  = @()
                        DurationInDays     = 21
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 21 }
                    }
                }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName      = 'oer-ar-upd'
                    accessPackage    = 'oer-ap'
                    assignmentPolicy = 'pol-1'
                    recurrence       = $null
                    durationInDays   = 21
                }
                $Results = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item)

                # Positive-identity assertion first: the update path must actually have written, or the
                # content check below would pass just as well on zero calls.
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -Exactly
                @($Results | Where-Object { $_.Action -eq 'Updated' }).Count | Should -BeGreaterThan 0 -Because 'the duration change alone must converge cleanly for this assertion to mean anything'

                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DurationInDays -eq 21 -and $null -eq $Recurrence -and $null -eq $StartDate
                }
            }
        }
    }

    Context 'create path consumes the full declared field set' {

        It 'passes the recurrence range and every settings toggle to New-OERAccessReviewDefinition' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'Quarterly'; startDate = '2026-07-01'; occurrences = 4
                    durationInDays = 21
                    reviewers = @('anna@contoso.com')
                    mailNotification = $true; reminderNotification = $true; requireJustification = $true
                    recommendationsEnabled = $true; autoApplyDecisions = $true; defaultDecision = 'Deny'
                }
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $Occurrences -eq 4 -and
                    $DurationInDays -eq 21 -and
                    $MailNotification -eq $true -and
                    $ReminderNotification -eq $true -and
                    $RequireJustification -eq $true -and
                    $RecommendationsEnabled -eq $true -and
                    $AutoApplyDecisions -eq $true -and
                    $DefaultDecision -eq 'Deny'
                }
            }
        }

        It 'passes endDate when declared' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'Monthly'; startDate = '2026-07-01'; endDate = '2027-07-01'
                    reviewers = @('anna@contoso.com')
                }
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $EndDate -eq ([datetime]'2027-07-01')
                }
            }
        }

        It 'omits an undeclared toggle so the cmdlet default applies' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('anna@contoso.com')
                }
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item
                # NOTE: $PSBoundParameters is NOT populated inside a Pester Mock/ParameterFilter
                # scriptblock in this Pester version (verified empirically) -- only the individual
                # bound-parameter variables are, and an omitted splat key surfaces as $null there while
                # a bound -Switch:$false surfaces as $false. So "was this parameter left unbound" must
                # be checked via "$null -eq $Var", not "-not $Var" -- the latter is $true for BOTH an
                # unbound $null and a wrongly-bound $false, so it would not catch a regression that
                # started binding these switches false instead of leaving them unbound.
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $null -eq $EndDate -and
                    $null -eq $Occurrences -and
                    $null -eq $MailNotification -and
                    $null -eq $ReminderNotification -and
                    $null -eq $RequireJustification -and
                    $null -eq $RecommendationsEnabled -and
                    $null -eq $AutoApplyDecisions -and
                    $null -eq $DefaultDecision
                }
            }
        }
    }

    Context 'existing definition is reconciled, not skipped' {

        It 'updates a drifted duration instead of reporting Unchanged' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'Q3 AP review'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 14
                        Recurrence              = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings                = @{ instanceDurationInDays = 14; defaultDecision = 'None' }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                # The real Set-OERAccessReviewDefinition re-GETs the definition after its PUT and
                # returns it, and the handler now re-diffs that return value before claiming Updated.
                # The mock therefore has to answer with the definition as it looks AFTER the write
                # (instanceDurationInDays 21), not with a bare id stub -- a stub carries no settings,
                # so the verification would correctly conclude the write never landed.
                Mock Set-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        Status             = 'InProgress'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 21
                        Settings           = @{ instanceDurationInDays = 21; defaultDecision = 'None' }
                    }
                }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    durationInDays = 21
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $Id -eq 'ar-1' -and $DurationInDays -eq 21
                }
                Should -Invoke New-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Updated'
            }
        }

        It 'sends only the drifted field and leaves the rest of the definition alone' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'Q3 AP review'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 14
                        Recurrence              = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings                = @{ instanceDurationInDays = 14; defaultDecision = 'None' }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    descriptionForReviewers = 'new reviewer text'
                })
                # An undeclared field must stay unbound so the read-modify-write PUT preserves it --
                # "$null -eq" is required because an unbound switch and a bound $false both look falsy.
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $DescriptionForReviewers -eq 'new reviewer text' -and
                    $null -eq $DescriptionForAdmins -and
                    $null -eq $DurationInDays -and
                    $null -eq $Recurrence -and
                    $null -eq $Reviewer -and
                    $null -eq $Manager
                }
            }
        }

        It 'reports Unchanged when every declared field already matches' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14; defaultDecision = 'None' }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    durationInDays = 14
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Unchanged'
            }
        }

        It 'resolves declared reviewers and updates them when they differ' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Resolve-OERStructurePrincipal { 'usr-2' }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('bo@contoso.com'); fallbackReviewers = @('sec-fallback')
                })
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    @($Reviewer) -contains 'bo@contoso.com' -and @($FallbackReviewerGroup) -contains 'sec-fallback'
                }
            }
        }

        It 'reports Unchanged when the declared reviewers resolve to the live reviewer ids' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                # The tenant renamed the user, but the resolved object id still matches the live query,
                # so a display-name change must NOT look like drift.
                Mock Resolve-OERStructurePrincipal { 'usr-1' }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('anna.new@contoso.com')
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Unchanged'
            }
        }

        It 'does not wipe the live fallback reviewers when the document declares only reviewers' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @(@{ query = '/groups/grp-9/transitiveMembers' })
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Resolve-OERStructurePrincipal { 'usr-2' }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('bo@contoso.com')
                })
                # Set-OERAccessReviewDefinition rebuilds BOTH reviewer arrays whenever any reviewer
                # parameter is bound, so the undeclared fallback half must ride along from the live
                # definition (by object id) instead of being dropped and wiped.
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    @($Reviewer) -contains 'bo@contoso.com' -and @($FallbackReviewerGroup) -contains 'grp-9'
                }
            }
        }

        It 'reports Unchanged when the document declares only reviewers and they match the live ones' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @(@{ query = '/groups/grp-9/transitiveMembers' })
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Resolve-OERStructurePrincipal { 'usr-1' }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('anna@contoso.com')
                }))
                # The live fallback list is not declared, so it must not keep forcing an update --
                # otherwise a re-run would never converge.
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Unchanged'
            }
        }

        It 'emits a Skipped record and no Unchanged for an immutable scope change' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = '99999999-9999-9999-9999-999999999999'
                    assignmentPolicy = 'pol-1'
                }))
                $Skipped = @($r | Where-Object { $_.Action -eq 'Skipped' })
                $Skipped.Count     | Should -BeGreaterThan 0
                $Skipped[0].Detail | Should -Match 'immutable'
                # Reporting both Skipped ("scope differs, cannot be written") and Unchanged
                # ("already matches") about the same item would contradict itself.
                @($r).Action       | Should -Not -Contain 'Unchanged'
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
            }
        }

        It 'under -WhatIf emits Skipped and does not call Set-OERAccessReviewDefinition' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    durationInDays = 21
                }) -WhatIf)
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                ($r | Where-Object Action -eq 'Skipped').Count | Should -BeGreaterThan 0
                ($r | Where-Object { $_.Action -eq 'Skipped' }).Detail | Should -BeLike '*would update*'
            }
        }

        It 'emits Failed when a declared reviewer cannot be resolved and does not write' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Resolve-OERStructurePrincipal { $null }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('ghost@contoso.com')
                }))
                ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
                ($r | Where-Object { $_.Action -eq 'Failed' }).Detail | Should -BeLike "*ghost@contoso.com*"
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
            }
        }

        It 'emits Failed when Set-OERAccessReviewDefinition throws' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { throw 'graph 500' }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    durationInDays = 21
                }) -ErrorAction SilentlyContinue)
                ($r | Where-Object Action -eq 'Failed').Count  | Should -BeGreaterThan 0
                ($r | Where-Object Action -eq 'Updated').Count | Should -Be 0
            }
        }

        It 'validates the recurrence value before touching the tenant' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Q3 AP review' } }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'Biweekly'
                }))
                ($r | Where-Object Action -eq 'Failed').Count | Should -BeGreaterThan 0
                Should -Invoke Get-OERAccessReviewDefinition -Times 0
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
            }
        }

        It 'settles on a OneTime review that declares a startDate instead of writing every run' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # A OneTime review has no settings.recurrence at all, so there is no live range to
                # compare the declared startDate against. The apply engine must still settle.
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = $null
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'OneTime'; startDate = '2026-07-01'
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Unchanged'
            }
        }

        It 'does not mutate the caller document while normalizing the declared cadence' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'quarterly'
                }
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item
                # The engine's parsed document is shared state; normalization belongs on a local copy.
                # -BeExactly, not -Be: Should -Be is case-insensitive on strings, so it would happily
                # accept the mutated 'Quarterly' and never catch the write-back.
                $Item.recurrence | Should -BeExactly 'quarterly'
            }
        }

        It 'normalizes the declared cadence casing before diffing it' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'quarterly'
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                @($r).Action | Should -Contain 'Unchanged'
            }
        }

        It 'sends the recurrence unit with the live start date when the cadence changes' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Recurrence         = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    recurrence = 'Monthly'
                })
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $Recurrence -eq 'Monthly' -and $StartDate -eq ([datetime]'2026-07-01')
                }
            }
        }
    }

    Context 'self-review mixing guard -- apply-path compatibility (Task 4c)' {
        # Task 4c adds a write-side MutuallyExclusiveReviewer guard to New-/Set-OERAccessReviewDefinition
        # that refuses -SelfReview combined with -Reviewer/-ReviewerGroup/-Manager. A document declaring
        # "reviewers": ["manager","self"] is accepted TODAY and silently resolves to the manager reviewer
        # (Resolve-OERReviewerScope simply never adds anything for -SelfReview when a primary scope is
        # already non-empty) -- forwarding BOTH switches unchanged after 4c would turn that into a hard
        # Failed record, breaking an existing apply-document. The handler must detect the mix itself,
        # warn, and forward only the named/manager reviewers so the effective outcome is unchanged.

        It 'create path drops self and forwards only manager, with a warning' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-mix'; DisplayName = 'Mixed Reviewers' } }
                Mock Initialize-OERAuth {}
                $Warnings = $null
                $r = @(Invoke-SyncArViaCaller -WarningVariable Warnings -Item ([PSCustomObject]@{
                    displayName       = 'Mixed Reviewers'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    reviewers         = @('manager', 'self')
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Quarterly'
                }))
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                @($Warnings).Count | Should -BeGreaterThan 0
                # Round-1 review finding M-6: 'reviewers' alone is not a durable match -- this
                # handler's OTHER warnings (immutable scope, unresolvable reviewer, etc.) can also
                # legitimately contain the word "reviewers", so a bug that emitted the WRONG warning
                # entirely could still satisfy that assertion. Match the phrase unique to this warning.
                @($Warnings) -join ' ' | Should -Match 'Declare only one reviewer mode'
                # $null -eq $SelfReview (not $false) proves the parameter was left UNBOUND, matching the
                # "$PSBoundParameters is not populated inside a ParameterFilter" note used elsewhere in
                # this file -- a bound -SelfReview:$false would look identical to -not $SelfReview.
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Manager -eq $true -and $null -eq $SelfReview
                }
            }
        }

        It 'update path drops self and forwards only manager, with a warning' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = '/users/usr-1' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = './manager'; queryType = 'MicrosoftGraph'; queryRoot = 'decisions' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock Initialize-OERAuth {}
                $Warnings = $null
                $r = @(Invoke-SyncArViaCaller -WarningVariable Warnings -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('manager', 'self')
                }))
                ($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                @($Warnings).Count | Should -BeGreaterThan 0
                # Round-1 review finding M-6 -- see the create-path test above for why 'reviewers'
                # alone is not a durable match.
                @($Warnings) -join ' ' | Should -Match 'Declare only one reviewer mode'
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Manager -eq $true -and $null -eq $SelfReview
                }
            }
        }

        It 'update path removes ALL duplicate self tokens so a converged manager-only definition reports Unchanged (round-1 finding M-5)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # The live definition's reviewers are ALREADY the manager scope only -- a converged
                # state. List<T>.Remove('self') drops only the FIRST match: with a document declaring
                # 'self' TWICE, a single Remove() call leaves one stray 'self' token in the declared
                # ReviewerKey set (['self','manager'] vs the live ['manager']), which
                # Resolve-OERAccessReviewChange's Test-KeySetEqual would then report as a mismatch
                # FOREVER -- forcing an update attempt on every apply run even though nothing needs to
                # change. The while-loop fix must remove every 'self' entry, not just the first.
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                 = 'ar-1'
                        DisplayName        = 'Q3 AP review'
                        AccessPackageId    = 'ap-1'
                        AssignmentPolicyId = 'pol-1'
                        Reviewers          = @(@{ query = './manager'; queryType = 'MicrosoftGraph'; queryRoot = 'decisions' })
                        FallbackReviewers  = @()
                        DurationInDays     = 14
                        Settings           = @{ instanceDurationInDays = 14 }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                    reviewers = @('self', 'self', 'manager')
                }))
                Should -Invoke Set-OERAccessReviewDefinition -Times 0 -Exactly
                @($r).Action | Should -Contain 'Unchanged'
            }
        }
    }
}

Describe 'Sync-OERStructureAccessReview explicit null reviewer gates' {
    # An explicit JSON null must mean the same as omitting the key. The bare
    # PSObject.Properties.Name -contains check counted a null as DECLARED, which resolved to an empty
    # reviewer list and then took the empty-list-means-self-review branch -- silently converting a
    # review with named reviewers into a self review and (because Set-OERAccessReviewDefinition
    # rebuilds BOTH reviewer arrays) wiping its fallback reviewers.

    It 'treats an explicit null reviewers as undeclared and leaves the live reviewers alone' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = 'ar-1'
                    DisplayName        = 'Q3 AP review'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @(@{ query = '/groups/grp-9/transitiveMembers' })
                    DurationInDays     = 14
                    Settings           = @{ instanceDurationInDays = 14 }
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
            Mock Resolve-OERStructurePrincipal { 'usr-2' }
            Mock Initialize-OERAuth {}
            $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                reviewers = $null; durationInDays = 21
            })
            # The genuinely drifted field is written, but NO reviewer parameter is bound, so the
            # read-modify-write PUT preserves the live reviewers and fallback reviewers untouched.
            # "$null -eq" is required: an unbound switch and a bound $false both look falsy.
            Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $DurationInDays -eq 21 -and
                $null -eq $Reviewer -and
                $null -eq $ReviewerGroup -and
                $null -eq $SelfReview -and
                $null -eq $Manager -and
                $null -eq $FallbackReviewer -and
                $null -eq $FallbackReviewerGroup
            }
        }
    }

    It 'writes nothing at all when the only declared reviewer keys are explicit nulls' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = 'ar-1'
                    DisplayName        = 'Q3 AP review'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @()
                    DurationInDays     = 14
                    Settings           = @{ instanceDurationInDays = 14 }
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
            Mock Resolve-OERStructurePrincipal { 'usr-2' }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                reviewers = $null; fallbackReviewers = $null; durationInDays = 14
            }))
            # Nothing is declared beyond a matching duration, so there is nothing to write at all.
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
            @($r).Action | Should -Contain 'Unchanged'
        }
    }

    It 'treats an explicit null fallbackReviewers as undeclared and seeds it from the live definition' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = 'ar-1'
                    DisplayName        = 'Q3 AP review'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @(@{ query = '/groups/grp-9/transitiveMembers' })
                    DurationInDays     = 14
                    Settings           = @{ instanceDurationInDays = 14 }
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
            Mock Resolve-OERStructurePrincipal { 'usr-2' }
            Mock Initialize-OERAuth {}
            $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                reviewers = @('bo@contoso.com'); fallbackReviewers = $null
            })
            # The declared half is written; the null half rides along from the live definition by
            # object id rather than being sent empty, which the full-array rebuild would treat as a wipe.
            Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                @($Reviewer) -contains 'bo@contoso.com' -and
                @($FallbackReviewerGroup) -contains 'grp-9'
            }
        }
    }

    It 'still treats an explicitly empty reviewers list as a declared self review' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = 'ar-1'
                    DisplayName        = 'Q3 AP review'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @()
                    DurationInDays     = 14
                    Settings           = @{ instanceDurationInDays = 14 }
                }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1' } }
            Mock Resolve-OERStructurePrincipal { 'usr-2' }
            Mock Initialize-OERAuth {}
            $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                reviewers = @()
            })
            # An empty list is an intentional statement, unlike a null -- it stays a self review.
            Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                $SelfReview -eq $true
            }
        }
    }

    # An update is only Updated once the definition READ BACK carries the declared state. Microsoft
    # Graph answers the PUT with 204 No Content, which says the request was accepted and nothing about
    # whether the value was stored -- Learn states a definition update applies to FUTURE instances
    # only, so a definition with none left was observed accepting the write and reading back unchanged.
    # Reporting Updated off the absence of an exception was a false success AND a permanent
    # non-convergence: the same document reported Updated on every run while the tenant never moved.
    # The fixtures below reproduce that live case exactly: a Completed review whose defaultDecision
    # stays None after a declared Approve.
    Context 'an update is verified against the definition Graph reads back' {

        It 'reports Failed, never Updated, when the definition reads back unchanged after the write' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # Both the pre-write read and the post-write return answer with the SAME definition:
                # defaultDecision is still None even though Approve was sent and Graph returned 204.
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'AccessRevuew Test'
                        Status                  = 'Completed'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 0
                        Recurrence              = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                        Settings                = @{ defaultDecision = 'None'; defaultDecisionEnabled = $false }
                    }
                }
                Mock Set-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'AccessRevuew Test'
                        Status                  = 'Completed'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 0
                        Recurrence              = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                        Settings                = @{ defaultDecision = 'None'; defaultDecisionEnabled = $false }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'AccessRevuew Test'
                    accessPackage    = 'oer-live-ap'
                    assignmentPolicy = 'Pol1'
                    defaultDecision  = 'Approve'
                }))

                # The write really was attempted with the declared value: this is a verification
                # failure, not a refusal to write.
                Should -Invoke Set-OERAccessReviewDefinition -Times 1 -ParameterFilter {
                    $Id -eq 'ar-1' -and $DefaultDecision -eq 'Approve'
                }
                @($r).Action | Should -Not -Contain 'Updated'
                @($r).Action | Should -Contain 'Failed'

                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                # The detail has to name the field that did not take effect and the live status, so the
                # operator can act on it without re-reading the tenant by hand.
                $Failed[0].Detail | Should -BeLike '*defaultDecision=Approve*'
                $Failed[0].Detail | Should -BeLike "*'Completed'*"
            }
        }

        It 'reports Updated when the definition reads back carrying the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'AccessRevuew Test'
                        Status                  = 'InProgress'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 0
                        Recurrence              = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                        Settings                = @{ defaultDecision = 'None'; defaultDecisionEnabled = $false }
                    }
                }
                # Same definition, but the write LANDED: defaultDecision is Approve on the read-back.
                # This is the counterweight test -- the verification must never turn a genuine success
                # into a reported failure.
                Mock Set-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'AccessRevuew Test'
                        Status                  = 'InProgress'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 0
                        Recurrence              = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                        Settings                = @{ defaultDecision = 'Approve'; defaultDecisionEnabled = $true }
                    }
                }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'AccessRevuew Test'
                    accessPackage    = 'oer-live-ap'
                    assignmentPolicy = 'Pol1'
                    defaultDecision  = 'Approve'
                }))

                @($r).Action | Should -Contain 'Updated'
                @($r).Action | Should -Not -Contain 'Failed'
            }
        }

        It 'reports Failed when Set-OERAccessReviewDefinition returns nothing to verify against' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition {
                    [PSCustomObject]@{
                        Id                      = 'ar-1'
                        DisplayName             = 'AccessRevuew Test'
                        Status                  = 'Completed'
                        DescriptionForAdmins    = 'admin text'
                        DescriptionForReviewers = 'reviewer text'
                        AccessPackageId         = 'ap-1'
                        AssignmentPolicyId      = 'pol-1'
                        Reviewers               = @(@{ query = '/users/usr-1' })
                        FallbackReviewers       = @()
                        DurationInDays          = 0
                        Recurrence              = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                        Settings                = @{ defaultDecision = 'None'; defaultDecisionEnabled = $false }
                    }
                }
                # No object back means there is nothing to prove the write with. Claiming Updated here
                # would be the same unevidenced success the verification exists to remove.
                Mock Set-OERAccessReviewDefinition { }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
                Mock Initialize-OERAuth {}

                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'AccessRevuew Test'
                    accessPackage    = 'oer-live-ap'
                    assignmentPolicy = 'Pol1'
                    defaultDecision  = 'Approve'
                }))

                @($r).Action | Should -Not -Contain 'Updated'
                @($r).Action | Should -Contain 'Failed'
                $Failed = @($r | Where-Object { $_.Action -eq 'Failed' })
                $Failed.Count | Should -Be 1
                $Failed[0].Detail | Should -BeLike '*no definition to verify against*'
            }
        }
    }
}

Describe 'Sync-OERStructureAccessReview create-path declared value family (issue #70)' {
    # Task 2 migrates the remaining nine create-param sites in this handler from an inline
    # `$Item.PSObject.Properties.Name -contains 'x'` check to Test-OERDeclaredProperty, so an
    # explicit JSON null on any of them means exactly what omitting the key means -- see
    # docs/development/rationale.md#declared-property. Each Context below proves one site with
    # three cases (declared value, declared explicit null, omitted); the null and omitted cases
    # always assert the identical outcome, since that pairing is what proves the rule.
    #
    # A shared "reviewers": ["self"] on every fixture below sidesteps the unrelated
    # manager-requires-fallback guard (a self review needs no fallbackReviewers), so every case
    # here reaches a plain Created record without that guard's Failed path interfering.
    #
    # startDate and endDate hold an inline `[datetime]$Item.x` cast that runs OUTSIDE any
    # try/catch in this handler. An explicit null there does not silently become the documented
    # coerced value -- it throws "Cannot convert null to type System.DateTime" and crashes the
    # whole call. Those two Contexts wrap the invocation in Should -Not -Throw so the mutation
    # proof is the crash itself, not merely a wrong value.

    Context 'descriptionForAdmins (site 1, line 369)' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-da-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName          = 'DescAdmins Value'
                    accessPackage        = 'AP-Sales'
                    assignmentPolicy     = 'Default'
                    reviewers            = @('self')
                    descriptionForAdmins = 'Custom admin description'
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForAdmins -eq 'Custom admin description'
                }
            }
        }

        It 'falls to the "Access review for <name>" default when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-da-2' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName          = 'DescAdmins Null'
                    accessPackage        = 'AP-Sales'
                    assignmentPolicy     = 'Default'
                    reviewers            = @('self')
                    descriptionForAdmins = $null
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForAdmins -eq 'Access review for DescAdmins Null'
                }
            }
        }

        It 'falls to the same default when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-da-3' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DescAdmins Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForAdmins -eq 'Access review for DescAdmins Omitted'
                }
            }
        }
    }

    Context 'descriptionForReviewers (site 2, line 374)' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dr-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName             = 'DescReviewers Value'
                    accessPackage           = 'AP-Sales'
                    assignmentPolicy        = 'Default'
                    reviewers               = @('self')
                    descriptionForReviewers = 'Custom reviewer description'
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForReviewers -eq 'Custom reviewer description'
                }
            }
        }

        It 'falls to the "Please review access for <name>" default when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dr-2' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName             = 'DescReviewers Null'
                    accessPackage           = 'AP-Sales'
                    assignmentPolicy        = 'Default'
                    reviewers               = @('self')
                    descriptionForReviewers = $null
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForReviewers -eq 'Please review access for DescReviewers Null'
                }
            }
        }

        It 'falls to the same default when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dr-3' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DescReviewers Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DescriptionForReviewers -eq 'Please review access for DescReviewers Omitted'
                }
            }
        }
    }

    Context 'startDate (site 3, line 382) -- the site issue #70 names explicitly' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-sd-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'StartDate Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    startDate        = '2026-08-01'
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $StartDate -eq ([datetime]'2026-08-01')
                }
            }
        }

        It 'falls to (Get-Date) instead of crashing the datetime cast when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-sd-2' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName      = 'StartDate Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    startDate        = $null
                }

                # Before the fix, the -contains check still sees the startDate PROPERTY (even
                # though its value is null) and reaches `[datetime]$Item.startDate`, which throws
                # "Cannot convert null to type System.DateTime" -- an uncaught exception raised
                # while building $NewParams, well before the try/catch around the create call.
                # The mutation proof here is the absence of that crash, not merely a value check.
                $script:StartDateNullResults = $null
                {
                    $script:StartDateNullResults = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item)
                } | Should -Not -Throw -Because 'an explicit null must fall to the (Get-Date) default instead of crashing the datetime cast'

                @($script:StartDateNullResults | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -BeGreaterThan 0 -Because 'the create path must actually complete for the date check below to mean anything'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $StartDate -is [datetime] -and $StartDate.Year -gt 1900
                }
            }
        }

        It 'falls to the same (Get-Date) default when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-sd-3' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'StartDate Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $StartDate -is [datetime] -and $StartDate.Year -gt 1900
                }
            }
        }
    }

    Context 'durationInDays (site 4, line 390)' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dd-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DurationInDays Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    durationInDays   = 21
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DurationInDays -eq 21
                }
            }
        }

        It 'leaves the cmdlet default (14) unbound when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dd-2' } }
                Mock Initialize-OERAuth {}
                # Before the fix, the -contains check binds -DurationInDays $null, which the
                # cmdlet's [int] parameter coerces to 0 -- ValidateRange(1, MaxValue) then rejects
                # 0 at the (mocked) call, so the old code path reports Failed here, not Created.
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DurationInDays Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    durationInDays   = $null
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $DurationInDays
                }
            }
        }

        It 'leaves the same cmdlet default unbound when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dd-3' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DurationInDays Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $DurationInDays
                }
            }
        }
    }

    Context 'endDate (site 5, line 397) -- shares the if/elseif range chain with occurrences' {
        It 'forwards the declared value and leaves occurrences unbound' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-ed-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'EndDate Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    endDate          = '2027-08-01'
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $EndDate -eq ([datetime]'2027-08-01') -and $null -eq $Occurrences
                }
            }
        }

        It 'takes neither range parameter instead of crashing the datetime cast when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-ed-2' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName      = 'EndDate Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    endDate          = $null
                }

                # Same crash shape as startDate: the pre-fix -contains check sees the endDate
                # property, reaches `[datetime]$Item.endDate`, and throws before the elseif for
                # occurrences is ever evaluated.
                $script:EndDateNullResults = $null
                {
                    $script:EndDateNullResults = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item)
                } | Should -Not -Throw -Because 'an explicit null must take neither range parameter instead of crashing the datetime cast'

                @($script:EndDateNullResults | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -BeGreaterThan 0 -Because 'the create path must actually complete for the parameter check below to mean anything'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $EndDate -and $null -eq $Occurrences
                }
            }
        }

        It 'takes neither range parameter when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-ed-3' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'EndDate Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $EndDate -and $null -eq $Occurrences
                }
            }
        }

        It 'binds occurrences when endDate is an explicit null alongside a real occurrences value (if/elseif interaction)' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-ed-4' } }
                Mock Initialize-OERAuth {}
                $Item = [PSCustomObject]@{
                    displayName      = 'EndDate Null Occurrences Real'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    endDate          = $null
                    occurrences      = 4
                }

                # Today (pre-fix) this never reaches the elseif at all -- the endDate branch
                # throws first. After the fix, an explicit null on endDate is undeclared, so the
                # chain falls through to occurrences exactly as it would if endDate were absent.
                $script:Results = $null
                {
                    $script:Results = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item $Item)
                } | Should -Not -Throw -Because 'a null endDate must fall through to the occurrences branch instead of crashing the datetime cast'

                @($script:Results | Where-Object { $_.Action -eq 'Created' }).Count |
                    Should -BeGreaterThan 0 -Because 'the create path must actually complete for the parameter check below to mean anything'
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Occurrences -eq 4 -and $null -eq $EndDate
                }
            }
        }
    }

    Context 'occurrences (site 6, line 400), isolated from endDate' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-oc-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'Occurrences Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    occurrences      = 6
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Occurrences -eq 6 -and $null -eq $EndDate
                }
            }
        }

        It 'binds neither range parameter when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-oc-2' } }
                Mock Initialize-OERAuth {}
                # Before the fix, the elseif's -contains check binds -Occurrences $null, which the
                # cmdlet's [int] parameter coerces to 0 -- ValidateRange(1, MaxValue) then rejects
                # 0 at the (mocked) call, so the old code path reports Failed here, not Created.
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'Occurrences Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    occurrences      = $null
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $Occurrences -and $null -eq $EndDate
                }
            }
        }

        It 'binds neither range parameter when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-oc-3' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'Occurrences Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $Occurrences -and $null -eq $EndDate
                }
            }
        }
    }

    Context 'SettingSwitchMap loop (site 7, line 414), represented by mailNotification' {
        # The loop maps five document keys through the identical predicate; mailNotification
        # stands in for all five since the code path is shared. Already behaviour-identical before
        # this migration (the truthiness clause already collapsed a declared null to "not bound"),
        # so no mutation proof is expected here -- see the source comment at the loop itself.
        It 'binds the switch when the value is declared true' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-mn-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'MailNotification Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    mailNotification = $true
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $MailNotification -eq $true
                }
            }
        }

        It 'leaves the switch unbound when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-mn-2' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'MailNotification Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    mailNotification = $null
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $MailNotification
                }
            }
        }

        It 'leaves the switch unbound when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-mn-3' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'MailNotification Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $MailNotification
                }
            }
        }
    }

    Context 'defaultDecision (site 8, line 418)' {
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dec-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DefaultDecision Value'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    defaultDecision  = 'Deny'
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $DefaultDecision -eq 'Deny'
                }
            }
        }

        It 'leaves the cmdlet default (None) unbound when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dec-2' } }
                Mock Initialize-OERAuth {}
                # Before the fix, the -contains check casts [string]$Item.defaultDecision to an
                # empty string and binds -DefaultDecision '' -- ValidateSet then rejects '' at the
                # (mocked) call, so the old code path reports Failed here, not Created.
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DefaultDecision Null'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                    defaultDecision  = $null
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                @($r | Where-Object { $_.Action -eq 'Failed' }).Count | Should -Be 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $DefaultDecision
                }
            }
        }

        It 'leaves the same cmdlet default unbound when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-dec-3' } }
                Mock Initialize-OERAuth {}
                $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'DefaultDecision Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                }))
                @($r | Where-Object { $_.Action -eq 'Created' }).Count | Should -BeGreaterThan 0
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $DefaultDecision
                }
            }
        }
    }

    Context 'fallbackReviewers on the create path (site 9, line 494), already behaviour-identical' {
        # The old truthiness clause ($Item.fallbackReviewers) already collapsed a declared null to
        # "not bound" -- [bool]$null is $false regardless of which declared-check gates it. Every
        # fixture here declares "reviewers": ["self"] so the manager-requires-fallback guard never
        # fires and the case under test is isolated to fallbackReviewers alone.
        It 'forwards the declared value' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-fb-1' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName       = 'FallbackReviewers Value'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    reviewers         = @('self')
                    fallbackReviewers = @('fb@contoso.com')
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    @($FallbackReviewer) -contains 'fb@contoso.com'
                }
            }
        }

        It 'leaves both fallback parameters unbound when the value is an explicit null' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-fb-2' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName       = 'FallbackReviewers Null'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Default'
                    reviewers         = @('self')
                    fallbackReviewers = $null
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $FallbackReviewer -and $null -eq $FallbackReviewerGroup
                }
            }
        }

        It 'leaves both fallback parameters unbound when the key is omitted' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                Mock Get-OERAccessReviewDefinition { @() }
                Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-fb-3' } }
                Mock Initialize-OERAuth {}
                $null = Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'FallbackReviewers Omitted'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Default'
                    reviewers        = @('self')
                })
                Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $null -eq $FallbackReviewer -and $null -eq $FallbackReviewerGroup
                }
            }
        }
    }
}
