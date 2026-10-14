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

Describe 'Sync-OERStructureAccessReview' {

    BeforeAll {
        # BL-127: before it updates a review found by name, the handler asks
        # Get-OERAccessReviewTargetMismatch whether that review reviews the declared access package and
        # assignment policy. Answered "it does" for this Describe, so every update fixture below keeps its
        # meaning; the check itself runs for real in the BL-127 Describe at the end of this file.
        Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewTargetMismatch { $null }
    }

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

    It 'creates a missing access review declared "semiannually" in any casing with -Recurrence SemiAnnually' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-1'; DisplayName = 'Semi-annual AP-Sales' } }
            Mock Initialize-OERAuth {}
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName       = 'Semi-annual AP-Sales'
                accessPackage     = 'AP-Sales'
                assignmentPolicy  = 'Default'
                reviewers         = @('manager')
                fallbackReviewers = @('fallback@contoso.com')
                recurrence        = 'semiannually'
            }))
            @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
            @($r | Where-Object Action -eq 'Created').Count | Should -Be 1
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Recurrence -ceq 'SemiAnnually' }
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
            # The refusal names every accepted cadence, SemiAnnually included, in canonical order.
            @($r | Where-Object Action -eq 'Failed')[0].Detail |
                Should -BeExactly "unrecognised recurrence value 'Biweekly'; expected OneTime, Weekly, Monthly, Quarterly, SemiAnnually, or Annually"
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

        It 'moves a live Quarterly review to SemiAnnually, and the PUT the real Set cmdlet sends carries absoluteMonthly interval 6' {
            InModuleScope $script:moduleName {
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                }
                # The existence probe sees the converted shape of a live Quarterly review. The REAL
                # Set-OERAccessReviewDefinition then runs, and only the transport under it is mocked: a
                # stateful stand-in for the raw definition, so the post-write read-back carries exactly
                # what the PUT sent and the handler's verification is a genuine round trip.
                $script:SemiAnnualRaw = @{
                    id                      = 'ar-1'
                    displayName             = 'Q3 AP review'
                    status                  = 'InProgress'
                    descriptionForAdmins    = 'admin text'
                    descriptionForReviewers = 'reviewer text'
                    scope                   = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1')" }
                    reviewers               = @(@{ query = '/users/usr-1'; queryType = 'MicrosoftGraph' })
                    settings                = @{
                        instanceDurationInDays = 14
                        recurrence             = @{
                            pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                            range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                        }
                    }
                }
                try {
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
                    Mock Resolve-OERAccessReviewDefinitionId { 'ar-1' }
                    Mock Invoke-OERGraphRequest {
                        if ($Method -eq 'PUT') {
                            $script:SemiAnnualRaw.settings = $Body.settings
                            return $null
                        }
                        return $script:SemiAnnualRaw
                    }
                    Mock Initialize-OERAuth {}
                    $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -Item ([PSCustomObject]@{
                        displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                        recurrence = 'SemiAnnually'
                    }))
                    @($r | Where-Object Action -eq 'Failed').Count | Should -Be 0
                    @($r | Where-Object Action -eq 'Updated').Count | Should -Be 1
                    Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                        $Method -eq 'PUT' -and
                        $Body.settings.recurrence.pattern.type -eq 'absoluteMonthly' -and
                        $Body.settings.recurrence.pattern.interval -eq 6 -and
                        $Body.settings.recurrence.pattern.dayOfMonth -eq 1 -and
                        $Body.settings.recurrence.range.type -eq 'noEnd' -and
                        $Body.settings.recurrence.range.startDate -eq '2026-07-01'
                    }
                }
                finally {
                    Remove-Variable -Name SemiAnnualRaw -Scope Script -ErrorAction SilentlyContinue
                }
            }
        }

        It 'reports Unchanged and sends no write when a live interval 6 review is declared SemiAnnually' {
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
                            pattern = @{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
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
                    recurrence = 'SemiAnnually'; startDate = '2026-07-01'
                }))
                # The Unchanged record shows the handler reached the reconcile and found nothing to do,
                # so the two zero-call assertions below are not vacuous.
                @($r).Action | Should -Contain 'Unchanged'
                @($r | Where-Object { $_.Action -in 'Failed', 'Skipped', 'Updated' }).Count | Should -Be 0
                Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
                Should -Invoke Set-OERAccessReviewDefinition -Times 0
                Should -Invoke New-OERAccessReviewDefinition -Times 0
            }
        }

        Context 'a live interval 6 review declared Monthly (A19)' {
            # Every export before 1.1.4 wrote a live absoluteMonthly interval 6 as Monthly. The diff
            # leaves the recurrence unit alone and names this reason, and the handler turns it into one
            # warning and one Skipped record before its ShouldProcess gate, so a plan and a real run
            # report the same thing.
            BeforeAll {
                $script:A19SyncReason = "the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose"
            }

            It 'plans and runs a live interval 6 review declared Monthly the same way: one Skipped with the A19 reason and no write' {
                InModuleScope $script:moduleName -Parameters @{ Reason = $script:A19SyncReason } {
                    param($Reason)
                    function Invoke-SyncArViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                        Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                    }
                    # The REAL Set-OERAccessReviewDefinition stays in place and only the transport under it
                    # is mocked, so a write in either run would be counted where it would leave the module.
                    $script:A19MonthlyRaw = @{
                        id                      = 'ar-1'
                        displayName             = 'Q3 AP review'
                        status                  = 'InProgress'
                        descriptionForAdmins    = 'admin text'
                        descriptionForReviewers = 'reviewer text'
                        scope                   = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1')" }
                        reviewers               = @(@{ query = '/users/usr-1'; queryType = 'MicrosoftGraph' })
                        settings                = @{
                            instanceDurationInDays = 14
                            recurrence             = @{
                                pattern = @{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
                                range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                            }
                        }
                    }
                    try {
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
                                    pattern = @{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
                                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                                }
                                Settings           = @{ instanceDurationInDays = 14 }
                            }
                        }
                        Mock Resolve-OERAccessReviewDefinitionId { 'ar-1' }
                        Mock Invoke-OERGraphRequest {
                            param($Method, $Uri, $Body)
                            if ($Method -and $Method -ne 'GET') { return $null }
                            return $script:A19MonthlyRaw
                        }
                        Mock Initialize-OERAuth {}
                        # The shape an older export wrote: Monthly, and no reviewers key, so the reviewer
                        # half is not compared.
                        $Doc = [PSCustomObject]@{
                            displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                            recurrence = 'Monthly'
                        }
                        $Expected = "Sync-OERStructureAccessReview: access review 'Q3 AP review' -- $Reason."

                        $PlanWarn = $null
                        $Plan = @(Invoke-SyncArViaCaller -WhatIf -WarningVariable PlanWarn -WarningAction SilentlyContinue -Item $Doc)
                        $RunWarn = $null
                        $Run = @(Invoke-SyncArViaCaller -Confirm:$false -WarningVariable RunWarn -WarningAction SilentlyContinue -Item $Doc)

                        foreach ($Pair in @(@{ Records = $Plan; Warn = $PlanWarn }, @{ Records = $Run; Warn = $RunWarn })) {
                            @($Pair.Records).Count       | Should -Be 1
                            @($Pair.Records)[0].Action   | Should -BeExactly 'Skipped'
                            @($Pair.Records)[0].Detail   | Should -BeExactly $Reason
                            @($Pair.Warn).Count          | Should -Be 1
                            @($Pair.Warn)[0].Message     | Should -BeExactly $Expected
                        }
                        $Plan[0].Detail           | Should -BeExactly $Run[0].Detail
                        @($PlanWarn)[0].Message   | Should -BeExactly @($RunWarn)[0].Message
                        @(@($Plan) + @($Run) | Where-Object { $_.Action -in 'Updated', 'Unchanged', 'Failed' }).Count | Should -Be 0
                        # The reconcile was reached in both runs, so the zero-write assertion is not vacuous.
                        # A filter does not see the wrapper's default -Method, so a GET sent without it reads
                        # as $null here and this counts every transport call: none was made in either run.
                        Should -Invoke Get-OERAccessReviewDefinition -Times 2 -Exactly
                        Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -ne 'GET' }
                    }
                    finally {
                        Remove-Variable -Name A19MonthlyRaw -Scope Script -ErrorAction SilentlyContinue
                    }
                }
            }

            It 'writes a field outside the recurrence unit of a live interval 6 review declared Monthly, and the PUT keeps interval 6' {
                InModuleScope $script:moduleName -Parameters @{ Reason = $script:A19SyncReason } {
                    param($Reason)
                    function Invoke-SyncArViaCaller {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                        Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
                    }
                    # A stateful stand-in for the raw definition: the PUT stores what it sent, so the
                    # handler's post-write verification reads back exactly that and is a genuine round trip.
                    $script:A19DescriptionRaw = @{
                        id                      = 'ar-1'
                        displayName             = 'Q3 AP review'
                        status                  = 'InProgress'
                        descriptionForAdmins    = 'old'
                        descriptionForReviewers = 'reviewer text'
                        scope                   = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1')" }
                        reviewers               = @(@{ query = '/users/usr-1'; queryType = 'MicrosoftGraph' })
                        settings                = @{
                            instanceDurationInDays = 14
                            recurrence             = @{
                                pattern = @{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
                                range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                            }
                        }
                    }
                    try {
                        Mock Get-OERAccessReviewDefinition {
                            [PSCustomObject]@{
                                Id                   = 'ar-1'
                                DisplayName          = 'Q3 AP review'
                                DescriptionForAdmins = 'old'
                                AccessPackageId      = 'ap-1'
                                AssignmentPolicyId   = 'pol-1'
                                Reviewers            = @(@{ query = '/users/usr-1' })
                                FallbackReviewers    = @()
                                DurationInDays       = 14
                                Recurrence           = @{
                                    pattern = @{ type = 'absoluteMonthly'; interval = 6; dayOfMonth = 1 }
                                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                                }
                                Settings             = @{ instanceDurationInDays = 14 }
                            }
                        }
                        Mock Resolve-OERAccessReviewDefinitionId { 'ar-1' }
                        Mock Invoke-OERGraphRequest {
                            param($Method, $Uri, $Body)
                            if ($Method -eq 'PUT') {
                                foreach ($Key in @($Body.Keys)) { $script:A19DescriptionRaw[$Key] = $Body[$Key] }
                                return $null
                            }
                            return $script:A19DescriptionRaw
                        }
                        Mock Initialize-OERAuth {}
                        $Doc = [PSCustomObject]@{
                            displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                            recurrence = 'Monthly'; descriptionForAdmins = 'new'
                        }
                        $Expected = "Sync-OERStructureAccessReview: access review 'Q3 AP review' -- $Reason."

                        # The plan runs first: it writes nothing, so the raw stand-in is still the live state.
                        $PlanWarn = $null
                        $Plan = @(Invoke-SyncArViaCaller -WhatIf -WarningVariable PlanWarn -WarningAction SilentlyContinue -Item $Doc)
                        $Plan.Count       | Should -Be 2
                        $Plan[0].Action   | Should -BeExactly 'Skipped'
                        $Plan[0].Detail   | Should -BeExactly $Reason
                        $Plan[1].Action   | Should -BeExactly 'Skipped'
                        $Plan[1].Detail   | Should -BeExactly "would update access review 'Q3 AP review' (descriptionForAdmins=new)"
                        @($PlanWarn).Count      | Should -Be 1
                        @($PlanWarn)[0].Message | Should -BeExactly $Expected
                        Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
                        # $Method is $null in a filter for a GET sent without -Method, so this counts every
                        # transport call: the plan made none.
                        Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -ne 'GET' }

                        $RunWarn = $null
                        $Run = @(Invoke-SyncArViaCaller -Confirm:$false -WarningVariable RunWarn -WarningAction SilentlyContinue -Item $Doc)
                        $Run.Count      | Should -Be 2
                        $Run[0].Action  | Should -BeExactly 'Skipped'
                        $Run[0].Detail  | Should -BeExactly $Reason
                        $Run[1].Action  | Should -BeExactly 'Updated'
                        @($RunWarn).Count      | Should -Be 1
                        @($RunWarn)[0].Message | Should -BeExactly $Expected
                        # Exactly one write in the run. The real cmdlet's two GETs carry no -Method, which a
                        # filter reads as $null, so the write test names a bound method.
                        Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -and $Method -ne 'GET' }
                        Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                            $Method -eq 'PUT' -and
                            $Body.descriptionForAdmins -eq 'new' -and
                            $Body.settings.recurrence.pattern.type -eq 'absoluteMonthly' -and
                            $Body.settings.recurrence.pattern.interval -eq 6 -and
                            $Body.settings.recurrence.range.startDate -eq '2026-07-01'
                        }
                    }
                    finally {
                        Remove-Variable -Name A19DescriptionRaw -Scope Script -ErrorAction SilentlyContinue
                    }
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

    BeforeAll {
        # BL-127: answered "the review found by name reviews the declared package and policy", so these
        # update fixtures keep their meaning; the BL-127 Describe at the end of this file runs the check.
        Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewTargetMismatch { $null }
    }

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

# Decision D2 (2026-10-02). Access review definition display names are not unique in Microsoft Graph,
# and the apply engine used to take the FIRST definition whose name matched and then update it by its
# GUID through Set-OERAccessReviewDefinition -- so a document naming a review that several definitions
# share silently rewrote an arbitrary one. It now refuses, the same way Resolve-OERAccessReviewDefinitionId
# does for the cmdlets (decision D1): one Failed row, one published AmbiguousName record naming every
# candidate id, and nothing created, updated or read further for that entry.
#
# The definitions are returned by a mocked Get-OERAccessReviewDefinition, so every id below is the id the
# handler would otherwise have acted on. Where a fall-through must be able to write, each definition
# carries the full live shape the update diff reads: a handler that wrongly took the first match then
# reaches Set-OERAccessReviewDefinition (the drifted durationInDays is the write) instead of failing for
# an unrelated reason.
Describe 'Sync-OERStructureAccessReview refuses an ambiguous definition name' {

    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        # BL-127: answered "the review found by name reviews the declared package and policy", so the
        # single-match update fixtures below keep their meaning; the BL-127 Describe at the end of this
        # file runs the check.
        Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewTargetMismatch { $null }
    }

    BeforeEach {
        # Catch-all for the transport: a request no test mocked itself fails loudly instead of reaching
        # the real wrapper. A test's own Mock of Invoke-OERGraphRequest, defined after this one, wins.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) throw "Unexpected Graph request: $Uri" }
    }

    It 'creates, updates and reads nothing further for the entry when two definitions share the declared name' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                foreach ($DefId in @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')) {
                    [PSCustomObject]@{
                        Id                 = $DefId
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
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Resolve-OERStructurePrincipal { 'usr-1' }
            Mock Invoke-OERGraphRequest { }
            Mock Initialize-OERAuth {}

            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Q3 AP review'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Standard'
                durationInDays   = 21
                reviewers        = @('rev@contoso.com')
            }))

            # Positive proof first: the definitions were read, once, and the entry was reported Failed.
            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            @($r.Action) | Should -Contain 'Failed'

            # Nothing is created, updated or read further for the entry, and no transport call is made.
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
            Should -Invoke Resolve-OERStructurePrincipal -Times 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'reports one Failed row naming the name, the count and both ids when two definitions share the declared name' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Q3 AP review' }
                [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Q3 AP review' }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Initialize-OERAuth {}

            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Q3 AP review'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Standard'
                durationInDays   = 21
            }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Count | Should -Be 1 -Because 'exactly one row is reported for the ambiguous entry'
            $r[0].Action | Should -Be 'Failed'
            $r[0].Section | Should -Be 'accessReviews'
            $r[0].Item | Should -Be 'Q3 AP review'
            $r[0].Detail | Should -BeLike "2 access review definitions are named 'Q3 AP review'*"
            $r[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
            $r[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
            $r[0].Detail | Should -BeLike '*nothing was written*'
        }
    }

    It 'publishes exactly one AmbiguousName record carrying the name and both ids, and attaches it to the row' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Q3 AP review' }
                [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Q3 AP review' }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Initialize-OERAuth {}

            $Published = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable Published -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Standard'
                    durationInDays   = 21
                }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Records.Count | Should -Be 1 -Because 'one error is published for the ambiguous entry, no more'
            $Records[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            $Records[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Records[0].TargetObject | Should -Be 'Q3 AP review'
            $Records[0].Exception.Message | Should -BeLike "Access review definition display name 'Q3 AP review' matches 2 definitions (*"
            $Records[0].Exception.Message | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
            $Records[0].Exception.Message | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
            $Records[0].Exception.Message | Should -BeLike '*Access reviews do not enforce unique definition display names*'
            $Records[0].Exception.Message | Should -BeLike '*Rename one of them*'
            # The document cannot name a definition by id, so the message must not advise doing so.
            $Records[0].Exception.Message | Should -Not -BeLike '*definition id instead*'

            # The Failed row carries the very record that was published.
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Failed'
            $r[0].Error.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            $r[0].Error.Exception.Message | Should -Be $Records[0].Exception.Message
        }
    }

    It 'names every candidate and the right count when three definitions share the name' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Q3 AP review' }
                [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Q3 AP review' }
                [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; DisplayName = 'Q3 AP review' }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Initialize-OERAuth {}

            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Q3 AP review'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Standard'
            }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Failed'
            $r[0].Detail | Should -BeLike "3 access review definitions are named 'Q3 AP review'*"
            $r[0].Detail | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
            $r[0].Detail | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
            $r[0].Detail | Should -BeLike '*33333333-3333-3333-3333-333333333333*'
            $r[0].Error.Exception.Message | Should -BeLike '*matches 3 definitions (*33333333-3333-3333-3333-333333333333*'
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
        }
    }

    It 'refuses under -WhatIf as well, since refusing is not a write and ShouldProcess is never reached' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Q3 AP review' }
                [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Q3 AP review' }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Initialize-OERAuth {}

            $r = @(Invoke-SyncArViaCaller -WhatIf -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                displayName      = 'Q3 AP review'
                accessPackage    = 'AP-Sales'
                assignmentPolicy = 'Standard'
                durationInDays   = 21
            }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Failed' -Because 'an ambiguous name is refused outright, not downgraded to a Skipped would-update row'
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
            Should -Invoke New-OERAccessReviewDefinition -Times 0
        }
    }

    It 'counts only definitions whose display name equals the declared one and reconciles the single exact match' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            # The server-side filter is an equality test, but the handler re-checks the name on the
            # client; a returned definition with a different name must not make the entry ambiguous.
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = '11111111-1111-1111-1111-111111111111'
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
                [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Q3 AP review (copy)' }
            }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
            Mock Set-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = '11111111-1111-1111-1111-111111111111'
                    DisplayName        = 'Q3 AP review'
                    Status             = 'InProgress'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @()
                    DurationInDays     = 21
                    Settings           = @{ instanceDurationInDays = 21 }
                }
            }
            Mock Initialize-OERAuth {}

            $Published = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable Published -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Standard'
                    durationInDays   = 21
                }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Action | Should -Contain 'Updated'
            $r.Action | Should -Not -Contain 'Failed'
            Should -Invoke Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $Id -eq '11111111-1111-1111-1111-111111111111' -and $DurationInDays -eq 21
            }
            Should -Invoke New-OERAccessReviewDefinition -Times 0
            @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'AmbiguousName*' }).Count |
                Should -Be 0
        }
    }

    It 'reconciles a single existing definition exactly as before and publishes no error' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = '11111111-1111-1111-1111-111111111111'
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
            Mock Set-OERAccessReviewDefinition {
                [PSCustomObject]@{
                    Id                 = '11111111-1111-1111-1111-111111111111'
                    DisplayName        = 'Q3 AP review'
                    Status             = 'InProgress'
                    AccessPackageId    = 'ap-1'
                    AssignmentPolicyId = 'pol-1'
                    Reviewers          = @(@{ query = '/users/usr-1' })
                    FallbackReviewers  = @()
                    DurationInDays     = 21
                    Settings           = @{ instanceDurationInDays = 21 }
                }
            }
            Mock Initialize-OERAuth {}

            $Published = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable Published -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = 'Standard'
                    durationInDays   = 21
                }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Action | Should -Contain 'Updated'
            $r.Action | Should -Not -Contain 'Failed'
            Should -Invoke Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $Id -eq '11111111-1111-1111-1111-111111111111' -and $DurationInDays -eq 21
            }
            Should -Invoke New-OERAccessReviewDefinition -Times 0
            @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        }
    }

    It 'creates the definition when none carries the declared name, exactly as before' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new'; DisplayName = 'Q3 AP review' } }
            Mock Set-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-set' } }
            Mock Initialize-OERAuth {}

            $Published = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable Published -Item ([PSCustomObject]@{
                    displayName       = 'Q3 AP review'
                    accessPackage     = 'AP-Sales'
                    assignmentPolicy  = 'Standard'
                    reviewers         = @('manager')
                    fallbackReviewers = @('fallback@contoso.com')
                    recurrence        = 'Quarterly'
                }))

            Should -Invoke Get-OERAccessReviewDefinition -Times 1 -Exactly
            $r.Action | Should -Contain 'Created'
            $r.Action | Should -Not -Contain 'Failed'
            Should -Invoke New-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke Set-OERAccessReviewDefinition -Times 0
            @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        }
    }
}

# Decision A6 / Ruling R7. Resolve-OERAccessReviewScopeTarget used to fold a THROWN read of the access
# package behind a derived catalog into CatalogDerivationFailed, so the engine's Failed row said the
# package "was found but its catalog could not be read" for what was a 403 or an exhausted 429. The
# helper now carries the caught record in FailedRecord, New-OERAccessReviewDefinition re-publishes it as
# itself, and the engine's create catch attaches that record to the Failed row. Neither the helper nor the
# cmdlet is mocked below: only the transport and the access package id resolver are, so the whole chain
# from the throwing read to the row is under test.
Describe 'Sync-OERStructureAccessReview publishes a failed derived-catalog read as itself' {

    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
    }

    It 'reports the package read failure on the Failed row as the record it is, never as CatalogDerivationFailed' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*accessPackages/ap-1*') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: package read marker.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'ap-1')
                }
                throw "Unexpected Graph request: $Uri"
            }

            $Published = $null
            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ErrorVariable Published -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = '44444444-4444-4444-4444-444444444444'
                    reviewers        = @('self')
                    recurrence       = 'Quarterly'
                }))

            # Positive proof first: the entry was created through the REAL cmdlet and helper, the package
            # read was reached once, and nothing was POSTed -- so the row below is the answer to that read.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Failed'
            $r[0].Section | Should -Be 'accessReviews'
            $r[0].Item | Should -Be 'Q3 AP review'
            $r[0].Detail | Should -BeLike '*Authorization_RequestDenied: package read marker.*'
            $r[0].Detail | Should -Not -BeLike '*CatalogDerivationFailed*'
            $r[0].Detail | Should -Not -BeLike '*Could not derive the catalog*'
            $r[0].Error | Should -Not -BeNullOrEmpty
            $r[0].Error.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $r[0].Error.FullyQualifiedErrorId | Should -Not -Match 'CatalogDerivationFailed'
            $r[0].Error.CategoryInfo.Category | Should -Be 'PermissionDenied'

            # The caller's own stream carries the same refusal, and no CatalogDerivationFailed record.
            $Records = @($Published | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Records | Where-Object { $_.FullyQualifiedErrorId -match '^Authorization_RequestDenied' }).Count |
                Should -BeGreaterThan 0
            @($Records | Where-Object { $_.FullyQualifiedErrorId -match 'CatalogDerivationFailed' }).Count |
                Should -Be 0
        }
    }

    It 'still reports CatalogDerivationFailed on the Failed row when the package read succeeded but carried no catalog' {
        InModuleScope $script:moduleName {
            function Invoke-SyncArViaCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([PSCustomObject]$Item, [switch]$Prune, [string]$TenantAlias)
                Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias
            }
            Mock Get-OERAccessReviewDefinition { @() }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Initialize-OERAuth {}
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*accessPackages/ap-1*') { return @{ id = 'ap-1' } }
                throw "Unexpected Graph request: $Uri"
            }

            $r = @(Invoke-SyncArViaCaller -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Item ([PSCustomObject]@{
                    displayName      = 'Q3 AP review'
                    accessPackage    = 'AP-Sales'
                    assignmentPolicy = '44444444-4444-4444-4444-444444444444'
                    reviewers        = @('self')
                    recurrence       = 'Quarterly'
                }))

            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Failed'
            $r[0].Detail | Should -BeLike '*Could not derive the catalog from access package ''AP-Sales''*'
            $r[0].Error.FullyQualifiedErrorId | Should -Match '^CatalogDerivationFailed'
        }
    }
}

# BL-127 (Sprint 11 step 2, Rulings R8-R10). The handler finds the live review by display name in the
# whole tenant, and display names are not unique, so a review of a group, a role or another access
# package can carry the name an entry uses for a package review. Before it touches the review it found,
# the handler asks Get-OERAccessReviewTargetMismatch, which runs for REAL here: only the two lookups it
# makes are mocked (ledger Ruling P2), together with the sign-in, the reads, the write and the transport.
# A refusal comes first -- before the reviewer lookups, the diff and ShouldProcess -- so a plan and a
# real run report the same Failed row and nothing is written. No id below is version-4 shaped.
Describe 'Sync-OERStructureAccessReview updates a review found by name only when it reviews the declared package and policy (BL-127)' {

    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        $script:BtName = 'Q3 AP review'
        $script:BtDefId = 'cccc3333-0000-0000-0000-000000000001'
        $script:BtPkgId = 'aaaa1111-0000-0000-0000-000000000001'
        $script:BtOtherPkgId = 'aaaa1111-0000-0000-0000-000000000002'
        $script:BtPolId = 'bbbb2222-0000-0000-0000-000000000001'
        $script:BtOtherPolId = 'bbbb2222-0000-0000-0000-000000000002'
        $script:BtGroupScope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers'
        $script:BtNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'
        $script:BtGroupMessage = ("Access review 'Q3 AP review' in the tenant does not review an access package (its scope is " +
            "'$($script:BtGroupScope)'), so it is not the review this entry declares for access package 'AP-Sales' and assignment " +
            "policy 'Standard'. Nothing was written. $($script:BtNotUnique)")

        # The live definitions as ConvertTo-OERAccessReviewDefinition shapes them (Id is the alias the
        # handler writes by).
        function New-BtLive {
            param([string]$Scope, [string]$AccessPackageId, [string]$AssignmentPolicyId, [int]$DurationInDays = 14)
            [PSCustomObject]@{
                Id                      = $script:BtDefId
                DisplayName             = $script:BtName
                Status                  = 'InProgress'
                DescriptionForAdmins    = 'admin text'
                DescriptionForReviewers = 'reviewer text'
                Scope                   = $Scope
                AccessPackageId         = $AccessPackageId
                AssignmentPolicyId      = $AssignmentPolicyId
                Reviewers               = @(@{ query = '/users/usr-1' })
                FallbackReviewers       = @()
                DurationInDays          = $DurationInDays
                Recurrence              = @{
                    pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                }
                Settings                = @{ instanceDurationInDays = $DurationInDays }
            }
        }
        function New-BtPackageLive {
            param([int]$DurationInDays = 14)
            New-BtLive -Scope ("/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq '{0}' and assignmentPolicy/id eq '{1}')" -f $script:BtPkgId, $script:BtPolId) `
                -AccessPackageId $script:BtPkgId -AssignmentPolicyId $script:BtPolId -DurationInDays $DurationInDays
        }
        function New-BtEntry {
            param([string]$AccessPackage = 'AP-Sales', [string]$AssignmentPolicy = 'Standard', [int]$DurationInDays = 21, [string]$DescriptionForAdmins)
            $Entry = [PSCustomObject]@{
                displayName      = $script:BtName
                accessPackage    = $AccessPackage
                assignmentPolicy = $AssignmentPolicy
                durationInDays   = $DurationInDays
                reviewers        = @('person1@example.com')
            }
            if ($DescriptionForAdmins) { $Entry | Add-Member -NotePropertyName descriptionForAdmins -NotePropertyValue $DescriptionForAdmins }
            $Entry
        }
        # Applies one entry through a caller that owns ShouldProcess, and returns the rows and the error
        # records the CALLER itself published (a record's id carries ',Invoke-SyncArViaCaller' when it is).
        function Invoke-BtSync {
            param([Parameter(Mandatory)]$Item, [switch]$WhatIf, [string]$ErrorActionValue = 'SilentlyContinue')
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Item = $Item; PlanOnly = $WhatIf.IsPresent; Ea = $ErrorActionValue } {
                param($Item, $PlanOnly, $Ea)
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet
                }
                $Published = $null
                $Rows = @(Invoke-SyncArViaCaller -Item $Item -WhatIf:$PlanOnly -ErrorAction $Ea -ErrorVariable Published -WarningAction SilentlyContinue)
                [PSCustomObject]@{
                    Rows   = $Rows
                    Errors = @($Published | Where-Object {
                            $_ -is [System.Management.Automation.ErrorRecord] -and
                            ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-SyncArViaCaller')
                        })
                }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        $script:BtLiveNow = New-BtPackageLive
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) throw "Unexpected Graph request: $Uri" }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition { $script:BtLiveNow }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal { 'usr-1' }
        # By default the names resolve to the live package and policy; a test that needs another answer
        # mocks it again.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { 'bbbb2222-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
        # The definition Graph reads back after the PUT: it now carries the declared duration.
        Mock -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition { New-BtPackageLive -DurationInDays 21 }
    }

    It 'refuses a live group review that carries the entry''s name, before any lookup or write (<Mode>)' -ForEach @(
        @{ Mode = 'a real run'; PlanOnly = $false }
        @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true }
    ) {
        $script:BtLiveNow = New-BtLive -Scope $script:BtGroupScope
        $Run = Invoke-BtSync -Item (New-BtEntry) -WhatIf:$PlanOnly

        # Positive proof first: the review was read, once, and the entry was reported.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Failed' -Because 'a refusal is not a write, so a plan reports it exactly as a real run does'
        $Run.Rows[0].Section | Should -Be 'accessReviews'
        $Run.Rows[0].Item | Should -Be $script:BtName
        $Run.Rows[0].Detail | Should -BeExactly $script:BtGroupMessage
        [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessReviewScopeMismatch*'

        # One record, written through the caller.
        $Run.Errors.Count | Should -Be 1
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
        $Run.Errors[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
        $Run.Errors[0].TargetObject | Should -Be $script:BtName
        $Run.Errors[0].Exception.Message | Should -BeExactly $script:BtGroupMessage

        # Nothing written, no reviewer lookup, no package lookup: the refusal comes first.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
    }

    It 'refuses a review of another access package when the entry names its package <Case>, and writes nothing' -ForEach @(
        @{ Case = 'by name'; Package = 'AP-Sales'; Lookups = 1; DetailLike = "*not the access package 'AP-Sales' ('aaaa1111-0000-0000-0000-000000000002') this entry declares*" }
        @{ Case = 'by id'; Package = 'aaaa1111-0000-0000-0000-000000000002'; Lookups = 0; DetailLike = "*not the access package 'aaaa1111-0000-0000-0000-000000000002' this entry declares*" }
    ) {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000002' }
        $Run = Invoke-BtSync -Item (New-BtEntry -AccessPackage $Package)

        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Failed'
        $Run.Rows[0].Detail | Should -BeLike "Access review 'Q3 AP review' in the tenant reviews access package 'aaaa1111-0000-0000-0000-000000000001', *"
        $Run.Rows[0].Detail | Should -BeLike $DetailLike
        $Run.Errors.Count | Should -Be 1
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times $Lookups -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
    }

    It 'refuses a review of another assignment policy and writes nothing, not even the other declared changes' {
        # Before BL-127 the policy difference was a NotApplied Skipped row while the description was still
        # written to the review. Now the review is refused, and nothing is written to it.
        $Run = Invoke-BtSync -Item (New-BtEntry -AccessPackage $script:BtPkgId -AssignmentPolicy $script:BtOtherPolId -DescriptionForAdmins 'new admin text')

        $Run.Rows.Count | Should -Be 1 -Because 'one Failed row stands alone, with no Skipped scope note beside it'
        $Run.Rows[0].Action | Should -Be 'Failed'
        $Run.Rows[0].Detail | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews assignment policy '$($script:BtPolId)' of access " +
            "package '$($script:BtPkgId)', not the assignment policy '$($script:BtOtherPolId)' this entry declares, so it is not the review " +
            "this entry declares. Nothing was written. $($script:BtNotUnique)")
        $Run.Errors.Count | Should -Be 1
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
    }

    It 'updates the review exactly as before when it reviews the declared package and policy, named <Case>' -ForEach @(
        @{ Case = 'by name'; Package = 'AP-Sales'; Policy = 'Standard'; Lookups = 1 }
        @{ Case = 'by id'; Package = 'aaaa1111-0000-0000-0000-000000000001'; Policy = 'bbbb2222-0000-0000-0000-000000000001'; Lookups = 0 }
    ) {
        $Run = Invoke-BtSync -Item (New-BtEntry -AccessPackage $Package -AssignmentPolicy $Policy)

        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Updated'
        $Run.Rows[0].Detail | Should -BeExactly "updated access review 'Q3 AP review' (durationInDays=21)"
        $Run.Errors.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
            $Id -eq 'cccc3333-0000-0000-0000-000000000001' -and $DurationInDays -eq 21
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times $Lookups -Exactly -ParameterFilter { $DisplayName -eq 'AP-Sales' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times $Lookups -Exactly -ParameterFilter {
            $AccessPackageId -eq 'aaaa1111-0000-0000-0000-000000000001' -and $AssignmentPolicy -eq 'Standard'
        }
    }

    It 'reports Unchanged when the review reviews the declared package and policy and nothing differs, named <Case>' -ForEach @(
        @{ Case = 'by name'; Package = 'AP-Sales'; Policy = 'Standard' }
        @{ Case = 'by id'; Package = 'aaaa1111-0000-0000-0000-000000000001'; Policy = 'bbbb2222-0000-0000-0000-000000000001' }
    ) {
        $Run = Invoke-BtSync -Item (New-BtEntry -AccessPackage $Package -AssignmentPolicy $Policy -DurationInDays 14)

        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Unchanged'
        $Run.Errors.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
    }

    It 'reports AccessPackageNotFound and writes nothing when the package name matches nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { $null }
        $Run = Invoke-BtSync -Item (New-BtEntry)

        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Failed'
        $Run.Rows[0].Detail | Should -BeExactly "could not resolve the access package or assignment policy of access review 'Q3 AP review': AccessPackage 'AP-Sales' not found.; nothing was written"
        [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessPackageNotFound*'
        $Run.Errors.Count | Should -Be 1
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessPackageNotFound,Invoke-SyncArViaCaller'
        $Run.Errors[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
    }

    It 'reports a 403 out of the package lookup as itself and writes nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'AP-Sales')
        }
        $Run = Invoke-BtSync -Item (New-BtEntry)

        $Run.Rows.Count | Should -Be 1
        $Run.Rows[0].Action | Should -Be 'Failed'
        $Run.Rows[0].Detail | Should -BeExactly ("could not resolve the access package or assignment policy of access review 'Q3 AP review': " +
            'Authorization_RequestDenied: Insufficient privileges to complete the operation.; nothing was written')
        [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
        $Run.Rows[0].Error.CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Run.Errors.Count | Should -Be 1
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -Not -BeLike 'AccessReviewScopeMismatch*'
        [string]$Run.Errors[0].FullyQualifiedErrorId | Should -Not -BeLike 'AccessPackageNotFound*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
    }

    It 'stops with AccessReviewScopeMismatch under the caller''s -ErrorAction Stop, and writes nothing' {
        $script:BtLiveNow = New-BtLive -Scope $script:BtGroupScope
        $Thrown = { Invoke-BtSync -Item (New-BtEntry) -ErrorActionValue Stop } | Should -Throw -PassThru
        [string]$Thrown.FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
        $Thrown.Exception.Message | Should -BeExactly $script:BtGroupMessage
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
    }
}

# BL-128 (Sprint 11 step 4b, D6). An accessReviews[] entry that declares previousDisplayName renames the
# review found under that name: the entry's displayName is looked up first, exactly as before, then the
# previous name (tenant-wide by name, or read once by id when it is an object id), and
# Resolve-OERStructureRename decides, with no rename map (Ruling P5). The review found under the previous
# name passes the BL-127 target check before anything is written to it -- the check runs for REAL here,
# only its two lookups are mocked -- and the rename travels as -DisplayName in the one
# Set-OERAccessReviewDefinition call. The tenant is a list of definitions the mocks read and the Set mock
# writes, so a second run sees what the first one wrote. No id below is version-4 shaped.
Describe 'Sync-OERStructureAccessReview renames a review through previousDisplayName (BL-128)' {

    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        $script:RnNew = 'Q3 AP review'
        $script:RnOld = 'Q3 AP review (old)'
        $script:RnOldId = 'cccc3333-0000-0000-0000-000000000011'
        $script:RnOtherId = 'cccc3333-0000-0000-0000-000000000012'
        $script:RnThirdId = 'cccc3333-0000-0000-0000-000000000013'
        $script:RnPkgId = 'aaaa1111-0000-0000-0000-000000000001'
        $script:RnOtherPkgId = 'aaaa1111-0000-0000-0000-000000000002'
        $script:RnPolId = 'bbbb2222-0000-0000-0000-000000000001'
        $script:RnNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'

        # A live definition as ConvertTo-OERAccessReviewDefinition shapes it (Id is the alias the handler
        # writes by), reviewing the given access package and the declared policy.
        function New-RnLive {
            param([string]$Id, [string]$Name, [string]$AccessPackageId = $script:RnPkgId, [int]$DurationInDays = 14)
            [PSCustomObject]@{
                Id                      = $Id
                DisplayName             = $Name
                Status                  = 'InProgress'
                DescriptionForAdmins    = 'admin text'
                DescriptionForReviewers = 'reviewer text'
                Scope                   = ("/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq '{0}' and assignmentPolicy/id eq '{1}')" -f $AccessPackageId, $script:RnPolId)
                AccessPackageId         = $AccessPackageId
                AssignmentPolicyId      = $script:RnPolId
                Reviewers               = @(@{ query = '/users/usr-1' })
                FallbackReviewers       = @()
                DurationInDays          = $DurationInDays
                Recurrence              = @{
                    pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                }
                Settings                = @{ instanceDurationInDays = $DurationInDays }
            }
        }
        # The same definition as Microsoft Graph answers a read by id, before any conversion.
        function New-RnRaw {
            param([string]$Id, [string]$Name, [string]$AccessPackageId = $script:RnPkgId)
            @{
                id                      = $Id
                displayName             = $Name
                status                  = 'InProgress'
                descriptionForAdmins    = 'admin text'
                descriptionForReviewers = 'reviewer text'
                scope                   = @{
                    query     = ("/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq '{0}' and assignmentPolicy/id eq '{1}')" -f $AccessPackageId, $script:RnPolId)
                    queryType = 'MicrosoftGraph'
                }
                reviewers               = @(@{ query = '/users/usr-1'; queryType = 'MicrosoftGraph' })
                fallbackReviewers       = @()
                settings                = @{
                    instanceDurationInDays = 14
                    recurrence             = @{
                        pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                        range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                    }
                }
            }
        }
        function New-RnEntry {
            param([string]$PreviousDisplayName = $script:RnOld, [int]$DurationInDays = 21)
            [PSCustomObject]@{
                displayName         = $script:RnNew
                previousDisplayName = $PreviousDisplayName
                accessPackage       = 'AP-Sales'
                assignmentPolicy    = 'Standard'
                durationInDays      = $DurationInDays
                reviewers           = @('person1@example.com')
            }
        }
        # What Invoke-OERGraphRequest returns for an error code the caller declared as an answer.
        function New-RnNotFoundMarker {
            param([string]$Uri)
            $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'NotFound'; StatusCode = 404; Message = 'Not found.'; Uri = $Uri }
            $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
            $Marker
        }
        # Applies one entry through a caller that owns ShouldProcess, and returns the rows, the error
        # records the CALLER itself published (a record's id carries ',Invoke-SyncArViaCaller' when it is)
        # and the warnings.
        function Invoke-RnSync {
            param([Parameter(Mandatory)]$Item, [switch]$WhatIf)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Item = $Item; PlanOnly = $WhatIf.IsPresent } {
                param($Item, $PlanOnly)
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet
                }
                $Published = $null
                $Warned = $null
                $Rows = @(Invoke-SyncArViaCaller -Item $Item -WhatIf:$PlanOnly -ErrorAction SilentlyContinue -ErrorVariable Published `
                        -WarningAction SilentlyContinue -WarningVariable Warned)
                [PSCustomObject]@{
                    Rows     = $Rows
                    Errors   = @($Published | Where-Object {
                            $_ -is [System.Management.Automation.ErrorRecord] -and
                            ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-SyncArViaCaller')
                        })
                    Warnings = @($Warned | ForEach-Object { [string]$_.Message })
                }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        # The tenant: the definitions a name lookup finds, and the Set mock writes.
        $script:RnLive = [System.Collections.Generic.List[object]]::new()
        # When set, the definition read back after the write carries this name instead of the one sent.
        $script:RnReadBackName = $null
        # When set, the definition read back after the write keeps its live duration instead of the one sent.
        $script:RnDropDuration = $false
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) throw "Unexpected Graph request: $Uri" }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal { 'usr-1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { 'bbbb2222-0000-0000-0000-000000000001' }
        Mock -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
        # Writes what it is sent to the live definition and reads it back, as Graph does.
        Mock -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition {
            param($Id, $DisplayName, $DurationInDays)
            $Live = @($script:RnLive | Where-Object { $_.Id -eq $Id })[0]
            if ($null -ne $script:RnReadBackName) { $Live.DisplayName = $script:RnReadBackName }
            elseif ($null -ne $DisplayName) { $Live.DisplayName = $DisplayName }
            if ($null -ne $DurationInDays -and -not $script:RnDropDuration) {
                $Live.DurationInDays = $DurationInDays
                $Live.Settings = @{ instanceDurationInDays = $DurationInDays }
            }
            $Live
        }
    }

    Context 'the name lookups answered from the tenant list' {

        BeforeEach {
            # A name lookup answers every definition carrying the name, ignoring case as the server does.
            Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition {
                param($Filter)
                if ($Filter -notmatch "^displayName eq '(.*)'$") { throw "Unexpected filter: $Filter" }
                $Wanted = $Matches[1].Replace("''", "'")
                @($script:RnLive | Where-Object { $_.DisplayName -eq $Wanted })
            }
        }

        It 'renames the review found only under its previous name, after the target check, in the one Set call that sends the other changed field' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $Run = Invoke-RnSync -Item (New-RnEntry)

            # Both names were looked up, once each.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 2 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Filter -eq "displayName eq 'Q3 AP review'" }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Filter -eq "displayName eq 'Q3 AP review (old)'" }
            # The target check ran on the review found under the previous name, and passed.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-Sales' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
            # ONE write, carrying the new name and the other changed field, to the review found under the old name.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'cccc3333-0000-0000-0000-000000000011' -and $DisplayName -ceq 'Q3 AP review' -and $DurationInDays -eq 21
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Section | Should -BeExactly 'accessReviews'
            $Run.Rows[0].Item | Should -BeExactly 'Q3 AP review'
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            $Run.Rows[0].Detail | Should -BeExactly "renamed access review 'Q3 AP review (old)' to 'Q3 AP review'; updated (durationInDays=21)"
            $Run.Errors.Count | Should -Be 0
            $Run.Warnings.Count | Should -Be 0
        }

        It 'renames a review with no other change in one Set call that carries -DisplayName alone' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld -DurationInDays 21))
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'cccc3333-0000-0000-0000-000000000011' -and $DisplayName -ceq 'Q3 AP review' -and $null -eq $DurationInDays
            }
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            $Run.Rows[0].Detail | Should -BeExactly "renamed access review 'Q3 AP review (old)' to 'Q3 AP review'"
            @($Run.Rows | Where-Object { $_.Action -eq 'Unchanged' }).Count | Should -Be 0
            $Run.Errors.Count | Should -Be 0
        }

        It 'reports Unchanged and writes nothing when only the new name finds the review, with previousDisplayName still declared' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnNew -DurationInDays 21))
            $Run = Invoke-RnSync -Item (New-RnEntry)

            # The previous name was still looked up, and found nothing.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Filter -eq "displayName eq 'Q3 AP review (old)'" }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Unchanged'
            $Run.Rows[0].Detail | Should -BeExactly "access review 'Q3 AP review' already matches"
            $Run.Errors.Count | Should -Be 0
        }

        It 'converges: the first run renames the review, and the same document again reports Unchanged and writes nothing (G8)' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $First = Invoke-RnSync -Item (New-RnEntry)
            $Second = Invoke-RnSync -Item (New-RnEntry)

            $First.Rows.Count | Should -Be 1
            $First.Rows[0].Action | Should -BeExactly 'Updated'
            $First.Rows[0].Detail | Should -BeExactly "renamed access review 'Q3 AP review (old)' to 'Q3 AP review'; updated (durationInDays=21)"
            $Second.Rows.Count | Should -Be 1
            $Second.Rows[0].Action | Should -BeExactly 'Unchanged'
            $Second.Rows[0].Detail | Should -BeExactly "access review 'Q3 AP review' already matches"
            # Exactly the one write of the first run, across both runs.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            $First.Errors.Count + $Second.Errors.Count | Should -Be 0
            $script:RnLive[0].DisplayName | Should -BeExactly 'Q3 AP review'
        }

        It 'refuses with one Failed row and AccessReviewRenameConflict, writing nothing, when both names find different reviews (<Mode>)' -ForEach @(
            @{ Mode = 'a real run'; PlanOnly = $false }
            @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true }
        ) {
            $script:RnLive.Add((New-RnLive -Id $script:RnOtherId -Name $script:RnNew))
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $Run = Invoke-RnSync -Item (New-RnEntry) -WhatIf:$PlanOnly

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Item | Should -BeExactly 'Q3 AP review'
            $Run.Rows[0].Action | Should -BeExactly 'Failed' -Because 'a refusal is not a write, so a plan reports it exactly as a real run does'
            $Run.Rows[0].Detail | Should -BeExactly ("both 'Q3 AP review' and its previousDisplayName 'Q3 AP review (old)' exist as different access reviews; " +
                'the document never merges two access reviews, so nothing was changed -- rename or delete one of them, or remove previousDisplayName')
            [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessReviewRenameConflict*'
            $Run.Errors.Count | Should -Be 1
            [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewRenameConflict,Invoke-SyncArViaCaller'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'ResourceExists'
            $Run.Errors[0].TargetObject | Should -BeExactly 'Q3 AP review'
            # Neither review is read further or written: no target check, no reviewer lookup.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
        }

        It 'refuses with AccessReviewRenameNotFound and creates nothing when neither name finds a review (<Mode>)' -ForEach @(
            @{ Mode = 'a real run'; PlanOnly = $false }
            @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true }
        ) {
            $Run = Invoke-RnSync -Item (New-RnEntry) -WhatIf:$PlanOnly

            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 2 -Exactly
            $Run.Rows.Count | Should -Be 1 -Because 'one Failed row stands alone, with no would-create row beside it'
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("neither 'Q3 AP review' nor its previousDisplayName 'Q3 AP review (old)' matches an access review, " +
                'so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; ' +
                'to create a new access review, remove previousDisplayName')
            $Run.Errors.Count | Should -Be 1
            [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewRenameNotFound,Invoke-SyncArViaCaller'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Run.Errors[0].TargetObject | Should -BeExactly 'Q3 AP review'
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        }

        It 'refuses a review found under its previous name that reviews another access package, and renames nothing (<Mode>)' -ForEach @(
            @{ Mode = 'a real run'; PlanOnly = $false }
            @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true }
        ) {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld -AccessPackageId $script:RnOtherPkgId))
            $Run = Invoke-RnSync -Item (New-RnEntry) -WhatIf:$PlanOnly

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $HelperText = ("Access review 'Q3 AP review' in the tenant reviews access package 'aaaa1111-0000-0000-0000-000000000002', " +
                "not the access package 'AP-Sales' ('aaaa1111-0000-0000-0000-000000000001') this entry declares, so it is not the review this " +
                "entry declares. Nothing was written. $($script:RnNotUnique)")
            # The row says where the review was found, since the helper names it by the entry's new name.
            $Run.Rows[0].Detail | Should -BeExactly ($HelperText + " (found under its previousDisplayName 'Q3 AP review (old)', id cccc3333-0000-0000-0000-000000000011)")
            $Run.Errors.Count | Should -Be 1
            [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
            # The record is the helper's own, unchanged.
            $Run.Errors[0].Exception.Message | Should -BeExactly $HelperText
            # Nothing written: the review keeps its name.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
            $script:RnLive[0].DisplayName | Should -BeExactly 'Q3 AP review (old)'
        }

        It 'refuses a previous name that several reviews carry with one AmbiguousName record naming every id, and writes nothing' {
            # The new name finds a review too, so a handler that skipped the refusal would update it.
            $script:RnLive.Add((New-RnLive -Id $script:RnThirdId -Name $script:RnNew))
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $script:RnLive.Add((New-RnLive -Id $script:RnOtherId -Name $script:RnOld))
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 2 -Exactly
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Item | Should -BeExactly 'Q3 AP review'
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("2 access review definitions are named 'Q3 AP review (old)' (cccc3333-0000-0000-0000-000000000011, " +
                'cccc3333-0000-0000-0000-000000000012), the previousDisplayName of this entry; nothing was written -- declare ' +
                'previousDisplayName as the object id of the review to rename')
            $Run.Errors.Count | Should -Be 1
            [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Invoke-SyncArViaCaller'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Run.Errors[0].TargetObject | Should -BeExactly 'Q3 AP review (old)'
            $Run.Errors[0].Exception.Message | Should -BeExactly ("Access review definition display name 'Q3 AP review (old)' matches 2 definitions " +
                '(cccc3333-0000-0000-0000-000000000011, cccc3333-0000-0000-0000-000000000012). Access reviews do not enforce unique ' +
                'definition display names, so this name cannot identify a single definition. Declare previousDisplayName as the ' +
                'object id of the review to rename.')
            $Run.Rows[0].Error.Exception.Message | Should -BeExactly $Run.Errors[0].Exception.Message
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
        }

        It 'refuses a new name that several reviews carry exactly as before, without reading the previous name' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnNew))
            $script:RnLive.Add((New-RnLive -Id $script:RnOtherId -Name $script:RnNew))
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 0 -ParameterFilter { $Filter -eq "displayName eq 'Q3 AP review (old)'" }
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Detail | Should -BeExactly ("2 access review definitions are named 'Q3 AP review' (cccc3333-0000-0000-0000-000000000011, " +
                'cccc3333-0000-0000-0000-000000000012); nothing was written')
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].TargetObject | Should -BeExactly 'Q3 AP review'
            $Run.Errors[0].Exception.Message | Should -BeLike '*Rename one of them so the display name is unique.'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        }

        Context 'a previousDisplayName that is an object id' {

            It 'reads it once, by id, declaring the not-found answers, and renames the review it finds (the id typed in <Case>)' -ForEach @(
                @{ Case = 'lower case'; Typed = 'cccc3333-0000-0000-0000-000000000011' }
                @{ Case = 'upper case'; Typed = 'CCCC3333-0000-0000-0000-000000000011' }
            ) {
                $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
                $script:RnProbeUri = "v1.0/identityGovernance/accessReviews/definitions/$Typed"
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { New-RnRaw -Id 'cccc3333-0000-0000-0000-000000000011' -Name 'Q3 AP review (old)' } -ParameterFilter {
                    $Uri -eq $script:RnProbeUri
                }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $Typed)

                # ONE read by id, declaring Graph's three not-found answers; the id is never looked up as a name.
                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq $script:RnProbeUri -and @($ExpectedErrorCode).Count -eq 3 -and
                    @($ExpectedErrorCode) -contains 'NotFound' -and @($ExpectedErrorCode) -contains 'ResourceNotFound' -and
                    @($ExpectedErrorCode) -contains 'Request_ResourceNotFound'
                }
                Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter { $Filter -eq "displayName eq 'Q3 AP review'" }
                Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
                # The review read by id was converted as Get-OERAccessReviewDefinition converts it, so the target
                # check found its package and policy, and passed.
                Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
                # The write goes to the id as Graph spells it.
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Id -ceq 'cccc3333-0000-0000-0000-000000000011' -and $DisplayName -ceq 'Q3 AP review' -and $DurationInDays -eq 21
                }
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Updated'
                # Named by its current name and its id, not only by the GUID the document typed.
                $Run.Rows[0].Detail | Should -BeExactly ("renamed access review 'Q3 AP review (old)' (cccc3333-0000-0000-0000-000000000011) " +
                    "to 'Q3 AP review'; updated (durationInDays=21)")
                $Run.Errors.Count | Should -Be 0
            }

            It 'converges: the run after a rename by object id finds the review under its new name and reports Unchanged (G8)' {
                $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
                # The read by id answers what the tenant holds now, so the second run reads the renamed review.
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { New-RnRaw -Id 'cccc3333-0000-0000-0000-000000000011' -Name $script:RnLive[0].DisplayName } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011'
                }
                $First = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)
                $Second = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                $First.Rows.Count | Should -Be 1
                $First.Rows[0].Action | Should -BeExactly 'Updated'
                $Second.Rows.Count | Should -Be 1
                $Second.Rows[0].Action | Should -BeExactly 'Unchanged'
                $Second.Rows[0].Detail | Should -BeExactly "access review 'Q3 AP review' already matches"
                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 2 -Exactly
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
                $First.Errors.Count + $Second.Errors.Count | Should -Be 0
            }

            It 'treats an id that names no review as not matching: with the new name absent, AccessReviewRenameNotFound and nothing created' {
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) New-RnNotFoundMarker -Uri $Uri } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011'
                }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Failed'
                [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessReviewRenameNotFound*'
                $Run.Errors.Count | Should -Be 1
                [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewRenameNotFound,Invoke-SyncArViaCaller'
                Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            }

            It 'treats an id that names no review as not matching: with the new name present, a normal update with no rename and no conflict' {
                $script:RnLive.Add((New-RnLive -Id $script:RnThirdId -Name $script:RnNew))
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) New-RnNotFoundMarker -Uri $Uri } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011'
                }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Id -eq 'cccc3333-0000-0000-0000-000000000013' -and $null -eq $DisplayName -and $DurationInDays -eq 21
                }
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Updated'
                $Run.Rows[0].Detail | Should -BeExactly "updated access review 'Q3 AP review' (durationInDays=21)"
                $Run.Errors.Count | Should -Be 0
            }

            It 'reports any other failure of the read by id as itself, scrubbed first, and writes nothing although the new name found a review' {
                $script:RnLive.Add((New-RnLive -Id $script:RnThirdId -Name $script:RnNew))
                Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        'cccc3333-0000-0000-0000-000000000011')
                } -ParameterFilter { $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011' }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Failed'
                $Run.Rows[0].Detail | Should -BeExactly ("could not read access review definition 'cccc3333-0000-0000-0000-000000000011', the " +
                    'previousDisplayName of this entry: Authorization_RequestDenied: Insufficient privileges to complete the operation.; nothing was written')
                [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
                $Run.Rows[0].Error.CategoryInfo.Category | Should -Be 'PermissionDenied'
                $Run.Errors.Count | Should -Be 1
                [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
                # The handler's own catch scrubbed the record before publishing it.
                Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    $Record.Exception.Message -eq 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
                }
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
                Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
                Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            }

            It 'treats a read by id that answers with no object at all as not matching: with the new name absent, AccessReviewRenameNotFound and nothing written' {
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { $null } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011'
                }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Failed'
                $Run.Rows[0].Detail | Should -BeExactly ("neither 'Q3 AP review' nor its previousDisplayName 'cccc3333-0000-0000-0000-000000000011' matches " +
                    'an access review, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, ' +
                    'so wait and re-run; to create a new access review, remove previousDisplayName')
                $Run.Errors.Count | Should -Be 1
                [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewRenameNotFound,Invoke-SyncArViaCaller'
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
                Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            }

            It 'treats a read by id that answers with no object at all as not matching: with the new name present, a normal update with no rename' {
                $script:RnLive.Add((New-RnLive -Id $script:RnThirdId -Name $script:RnNew))
                Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { $null } -ParameterFilter {
                    $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000011'
                }
                $Run = Invoke-RnSync -Item (New-RnEntry -PreviousDisplayName $script:RnOldId)

                Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
                Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                    $Id -eq 'cccc3333-0000-0000-0000-000000000013' -and $null -eq $DisplayName -and $DurationInDays -eq 21
                }
                $Run.Rows.Count | Should -Be 1
                $Run.Rows[0].Action | Should -BeExactly 'Updated'
                $Run.Rows[0].Detail | Should -BeExactly "updated access review 'Q3 AP review' (durationInDays=21)"
                $Run.Errors.Count | Should -Be 0
            }
        }

        It 'under -WhatIf reports <Expected> and writes nothing' -ForEach @(
            @{ Live = 14; Expected = "would rename access review 'Q3 AP review (old)' to 'Q3 AP review'; would update (durationInDays=21)" }
            @{ Live = 21; Expected = "would rename access review 'Q3 AP review (old)' to 'Q3 AP review'" }
        ) {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld -DurationInDays $Live))
            $Run = Invoke-RnSync -Item (New-RnEntry) -WhatIf

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Skipped'
            $Run.Rows[0].Detail | Should -BeExactly $Expected
            $Run.Errors.Count | Should -Be 0
            # The target check ran in the plan too.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            $script:RnLive[0].DisplayName | Should -BeExactly 'Q3 AP review (old)'
        }

        It 'reports Failed and a warning, never Updated, when the definition read back is named <Case>' -ForEach @(
            @{ Case = 'as before the rename'; ReadBack = 'Q3 AP review (old)' }
            @{ Case = 'the new name in another letter case'; ReadBack = 'q3 ap review' }
        ) {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $script:RnReadBackName = $ReadBack
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("access review rename not confirmed: Microsoft Graph accepted the write but the definition read " +
                "back is named '$ReadBack', not 'Q3 AP review'; definition status is 'InProgress'")
            $Run.Warnings.Count | Should -Be 1
            $Run.Warnings[0] | Should -BeExactly ("Sync-OERStructureAccessReview: access review 'Q3 AP review' -- Microsoft Graph accepted the rename " +
                "from 'Q3 AP review (old)' but the definition read back is named '$ReadBack'. The definition status is 'InProgress'. Graph " +
                'documents that a definition update applies to FUTURE instances only, so a review with no future instance left may accept ' +
                'a write without storing it.')
            $Run.Errors.Count | Should -Be 0
        }

        It 'reports both in one Failed row and one warning when neither the rename nor the other changed field took effect' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $script:RnReadBackName = $script:RnOld
            $script:RnDropDuration = $true
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("access review update not confirmed: Microsoft Graph accepted the write but the definition read " +
                "back still differs (durationInDays=21) and is named 'Q3 AP review (old)', not 'Q3 AP review' (rename not confirmed); " +
                "definition status is 'InProgress'")
            $Run.Warnings.Count | Should -Be 1
            $Run.Warnings[0] | Should -BeExactly ("Sync-OERStructureAccessReview: access review 'Q3 AP review' -- Microsoft Graph accepted the update " +
                "but the definition read back still differs (durationInDays=21) and is named 'Q3 AP review (old)', not 'Q3 AP review' (rename " +
                "not confirmed). The definition status is 'InProgress'. Graph documents that a definition update applies to FUTURE instances " +
                'only, so a review with no future instance left may accept a write without storing it.')
            $Run.Errors.Count | Should -Be 0
        }

        It 'keeps the update-not-confirmed texts as they were when the rename took effect and only another field did not' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            $script:RnDropDuration = $true
            $Run = Invoke-RnSync -Item (New-RnEntry)

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("access review update not confirmed: Microsoft Graph accepted the write but the definition read " +
                "back still differs (durationInDays=21); definition status is 'InProgress'")
            $Run.Warnings.Count | Should -Be 1
            $Run.Warnings[0] | Should -Not -BeLike '*rename not confirmed*'
        }

        It 'does not compare the name read back when there is no rename: a review found in another letter case is updated as before' {
            # The name lookup ignores case, so the entry finds the live 'q3 ap review' under its displayName: no
            # rename is declared, and the read-back keeps the live spelling.
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name 'q3 ap review'))
            $Entry = New-RnEntry
            $Entry.PSObject.Properties.Remove('previousDisplayName')
            $Run = Invoke-RnSync -Item $Entry

            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $Id -eq 'cccc3333-0000-0000-0000-000000000011' -and $null -eq $DisplayName -and $DurationInDays -eq 21
            }
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            $Run.Rows[0].Detail | Should -BeExactly "updated access review 'Q3 AP review' (durationInDays=21)"
            $Run.Warnings.Count | Should -Be 0
        }

        It 'reports Failed naming the rename when Set-OERAccessReviewDefinition returns no definition to verify against' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            Mock -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition { }
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("access review rename of 'Q3 AP review (old)' to 'Q3 AP review' and update (durationInDays=21) " +
                'could not be confirmed: Set-OERAccessReviewDefinition returned no definition to verify against')
        }

        It 'reports a failed rename write as Failed with the error as itself, and no Updated row' {
            $script:RnLive.Add((New-RnLive -Id $script:RnOldId -Name $script:RnOld))
            Mock -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition { throw 'graph 400 rename refused' }
            $Run = Invoke-RnSync -Item (New-RnEntry)

            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly 'access review update failed: graph 400 rename refused'
            $Run.Errors.Count | Should -Be 1
        }

        It 'asks ShouldProcess with the rename action on the new name, and without a rename with the action it always had' {
            # The 'What if:' line goes straight to the host, so the entries run in a runspace whose host records
            # it (OERConfirmHost). Pester mocks do not cross the runspace boundary: the script installs its own
            # fakes in its copy of the module scope. Each entry is planned under -WhatIf, and nothing is written.
            $Scenario = {
                Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                $Module = Get-Module Omnicit.EntraRBAC
                & $Module {
                    Set-Item -Path function:script:Initialize-OERAuth -Value { }
                    Set-Item -Path function:script:Get-OERAccessReviewTargetMismatch -Value { }
                    # The one Graph request: the read by id of R4's previousDisplayName, answered as Graph does.
                    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                        param([string]$Uri)
                        if ($Uri -ne 'v1.0/identityGovernance/accessReviews/definitions/cccc3333-0000-0000-0000-000000000024') { throw "no Graph request expected: $Uri" }
                        @{ id = 'cccc3333-0000-0000-0000-000000000024'; displayName = 'R4 old'; status = 'InProgress'
                            reviewers = @(); fallbackReviewers = @(); settings = @{ instanceDurationInDays = 14 } }
                    }
                    Set-Item -Path function:script:Set-OERAccessReviewDefinition -Value { throw 'no write expected' }
                    Set-Item -Path function:script:New-OERAccessReviewDefinition -Value { throw 'no create expected' }
                    Set-Item -Path function:script:Get-OERAccessReviewDefinition -Value {
                        [CmdletBinding()]
                        param($Filter)
                        $Live = @{ 'R1 old' = 14; 'R2 old' = 21; 'R3' = 14 }
                        foreach ($Name in $Live.Keys) {
                            if ($Filter -eq "displayName eq '$Name'") {
                                [pscustomobject]@{
                                    Id = "cccc3333-0000-0000-0000-00000000002$($Name.Substring(1, 1))"; DisplayName = $Name; Status = 'InProgress'
                                    AccessPackageId = 'aaaa1111-0000-0000-0000-000000000001'; AssignmentPolicyId = 'bbbb2222-0000-0000-0000-000000000001'
                                    Reviewers = @(); FallbackReviewers = @(); DurationInDays = $Live[$Name]
                                    Settings = @{ instanceDurationInDays = $Live[$Name] }
                                }
                            }
                        }
                    }
                    function script:Invoke-SyncArPlan {
                        [CmdletBinding(SupportsShouldProcess)]
                        param([PSCustomObject]$Item)
                        Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet
                    }
                }
                $Items = @(
                    [pscustomobject]@{ displayName = 'R1 new'; previousDisplayName = 'R1 old'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'; durationInDays = 21 }
                    [pscustomobject]@{ displayName = 'R2 new'; previousDisplayName = 'R2 old'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'; durationInDays = 21 }
                    [pscustomobject]@{ displayName = 'R3'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'; durationInDays = 21 }
                    [pscustomobject]@{ displayName = 'R4 new'; previousDisplayName = 'cccc3333-0000-0000-0000-000000000024'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'; durationInDays = 21 }
                )
                foreach ($Item in $Items) {
                    & $Module { param($Item) Invoke-SyncArPlan -Item $Item -WhatIf } $Item | ForEach-Object { "ROW:$($_.Action):$($_.Detail)" }
                }
                'END'
            }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Errors).Count | Should -Be 0
            @($Run.Prompts).Count | Should -Be 0
            @($Run.Events | Where-Object { $_ -like 'Line: What if:*' }) | Should -Be @(
                'Line: What if: Performing the operation "Rename access review definition ''R1 old'' to ''R1 new'' and update it" on target "R1 new".'
                'Line: What if: Performing the operation "Rename access review definition ''R2 old'' to ''R2 new''" on target "R2 new".'
                'Line: What if: Performing the operation "Update access review definition" on target "R3".'
                'Line: What if: Performing the operation "Rename access review definition ''R4 old'' (cccc3333-0000-0000-0000-000000000024) to ''R4 new'' and update it" on target "R4 new".'
            )
            @($Run.Output | Where-Object { $_ -like 'ROW:*' }) | Should -Be @(
                "ROW:Skipped:would rename access review 'R1 old' to 'R1 new'; would update (durationInDays=21)"
                "ROW:Skipped:would rename access review 'R2 old' to 'R2 new'"
                "ROW:Skipped:would update access review 'R3' (durationInDays=21)"
                "ROW:Skipped:would rename access review 'R4 old' (cccc3333-0000-0000-0000-000000000024) to 'R4 new'; would update (durationInDays=21)"
            )
        }
    }

    Context 'the name lookups run through the real Get-OERAccessReviewDefinition' {

        It 'reports a failed read of the previous name as itself and writes nothing, although the new name found a review' {
            # The REAL Get-OERAccessReviewDefinition runs, so the failure reaches the handler as the record that
            # cmdlet publishes, the shape the lookup's publisher test reads.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri)
                $Decoded = [System.Uri]::UnescapeDataString([string]$Uri)
                if ($Decoded -like "*displayName eq 'Q3 AP review'") { return @{ value = @((New-RnRaw -Id 'cccc3333-0000-0000-0000-000000000013' -Name 'Q3 AP review')) } }
                if ($Decoded -like "*displayName eq 'Q3 AP review (old)'") {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('429 Too Many Requests'), 'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
                }
                throw "Unexpected Graph request: $Uri"
            }
            $Run = Invoke-RnSync -Item (New-RnEntry)

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly 'could not read access review definitions: 429 Too Many Requests'
            @($Run.Errors | Where-Object { $_.Exception.Message -eq '429 Too Many Requests' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
        }
    }
}

# BL-128 part 2 (Sprint 11 step 4b, D5). An access review's accessPackage and assignmentPolicy are read in
# the run's rename map before any Graph call for the entry. The map is filled here exactly as the
# accessPackages handler and the engine fill it -- through the real Resolve-OERStructureRename -- and the
# target check runs for REAL, only its two lookups mocked. In the run that renames an object Graph's name
# lookup does not find its new name yet, or finds another object that carries it: the lookup mocks below
# answer every new name with ANOTHER package or policy, so a test that looked a translated name up would
# reach it. No id below is version-4 shaped.
Describe 'Sync-OERStructureAccessReview reaches an access package or assignment policy the run renames through the rename map (BL-128 part 2)' {

    BeforeAll {
        $script:MpName = 'Q3 AP review'
        $script:MpDefId = 'cccc3333-0000-0000-0000-000000000021'
        $script:MpPkgId = 'aaaa1111-0000-0000-0000-000000000021'
        $script:MpOtherPkgId = 'aaaa1111-0000-0000-0000-000000000022'
        $script:MpPolId = 'bbbb2222-0000-0000-0000-000000000021'
        $script:MpOtherPolId = 'bbbb2222-0000-0000-0000-000000000022'
        $script:MpNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'

        # The live definition as ConvertTo-OERAccessReviewDefinition shapes it, reviewing the given
        # package and policy.
        function New-MpLive {
            param([string]$AccessPackageId = $script:MpPkgId, [string]$AssignmentPolicyId = $script:MpPolId, [int]$DurationInDays = 14)
            [PSCustomObject]@{
                Id                      = $script:MpDefId
                DisplayName             = $script:MpName
                Status                  = 'InProgress'
                DescriptionForAdmins    = 'admin text'
                DescriptionForReviewers = 'reviewer text'
                Scope                   = ("/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq '{0}' and assignmentPolicy/id eq '{1}')" -f $AccessPackageId, $AssignmentPolicyId)
                AccessPackageId         = $AccessPackageId
                AssignmentPolicyId      = $AssignmentPolicyId
                Reviewers               = @(@{ query = '/users/usr-1' })
                FallbackReviewers       = @()
                DurationInDays          = $DurationInDays
                Recurrence              = @{
                    pattern = @{ type = 'absoluteMonthly'; interval = 3; dayOfMonth = 1 }
                    range   = @{ type = 'noEnd'; startDate = '2026-07-01' }
                }
                Settings                = @{ instanceDurationInDays = $DurationInDays }
            }
        }
        function New-MpEntry {
            param([string]$AccessPackage = 'AP-New', [string]$AssignmentPolicy = 'Standard')
            [PSCustomObject]@{
                displayName      = $script:MpName
                accessPackage    = $AccessPackage
                assignmentPolicy = $AssignmentPolicy
                durationInDays   = 21
                reviewers        = @('person1@example.com')
            }
        }
        function New-MpMap {
            , [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        # Registers one decision, or one undecided mark, through the real owner, as the accessPackages
        # handler (or, for -Include, the engine) does.
        function Register-MpRename {
            param([Parameter(Mandatory)]$RenameMap, [Parameter(Mandatory)][hashtable]$Splat)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ RenameMap = $RenameMap; Splat = $Splat } {
                param($RenameMap, $Splat)
                $null = Resolve-OERStructureRename @Splat -RenameMap $RenameMap
            }
        }
        # Applies one entry through a caller that owns ShouldProcess, with the map, and returns the rows,
        # the error records the CALLER published, and every record -ErrorVariable collected at all.
        function Invoke-MpSync {
            param([Parameter(Mandatory)]$Item, $RenameMap, [switch]$WhatIf)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Item = $Item; RenameMap = $RenameMap; PlanOnly = $WhatIf.IsPresent } {
                param($Item, $RenameMap, $PlanOnly)
                function Invoke-SyncArViaCaller {
                    [CmdletBinding(SupportsShouldProcess)]
                    param([PSCustomObject]$Item, [System.Collections.Generic.Dictionary[string, object]]$RenameMap)
                    Sync-OERStructureAccessReview -Item $Item -Caller $PSCmdlet -RenameMap $RenameMap
                }
                $Published = $null
                $Rows = @(Invoke-SyncArViaCaller -Item $Item -RenameMap $RenameMap -WhatIf:$PlanOnly -ErrorAction SilentlyContinue `
                        -ErrorVariable Published -WarningAction SilentlyContinue)
                [PSCustomObject]@{
                    Rows   = $Rows
                    Errors = @($Published | Where-Object {
                            $_ -is [System.Management.Automation.ErrorRecord] -and
                            ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-SyncArViaCaller')
                        })
                    All    = @($Published)
                }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        $script:MpLiveNow = New-MpLive
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { param($Uri) throw "Unexpected Graph request: $Uri" }
        Mock -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition { $script:MpLiveNow }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal { 'usr-1' }
        # Graph's name lookups in the run that renames: the names nothing renames resolve to the
        # reviewed package and policy, and every other name -- a new name -- to ANOTHER package or policy.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId {
            if ($DisplayName -eq 'AP-Sales') { 'aaaa1111-0000-0000-0000-000000000021' } else { 'aaaa1111-0000-0000-0000-000000000022' }
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId {
            if ($AssignmentPolicy -eq 'Standard') { 'bbbb2222-0000-0000-0000-000000000021' } else { 'bbbb2222-0000-0000-0000-000000000022' }
        }
        Mock -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition { [PSCustomObject]@{ Id = 'ar-new' } }
        # The definition Graph reads back after the PUT: it now carries the declared duration.
        Mock -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition { New-MpLive -DurationInDays 21 }
    }

    Context 'an id the map holds replaces the name' {

        It 'updates the review of the access package the run renames, checked by the id the map holds and with no package lookup (<Mode>)' -ForEach @(
            @{ Mode = 'a real run'; PlanOnly = $false; Action = 'Updated'; Detail = "updated access review 'Q3 AP review' (durationInDays=21)"; Sets = 1 }
            @{ Mode = 'a plan under -WhatIf'; PlanOnly = $true; Action = 'Skipped'; Detail = "would update access review 'Q3 AP review' (durationInDays=21)"; Sets = 0 }
        ) {
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            $Run = Invoke-MpSync -Item (New-MpEntry) -RenameMap $Map -WhatIf:$PlanOnly

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly $Action
            $Run.Rows[0].Detail | Should -BeExactly $Detail
            @($Run.All).Count | Should -Be 0
            # The package is compared by the map's id, as written: no name lookup, which here would find
            # another package. The policy, which the map holds nothing for, is looked up by its name
            # within the package that id names.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly -ParameterFilter {
                $AccessPackageId -eq 'aaaa1111-0000-0000-0000-000000000021' -and $AssignmentPolicy -eq 'Standard'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times $Sets -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
        }

        It 'looks the same entry up by name without the map, and is refused by the target check (control)' {
            # The control for every test in this Describe: the lookup mocks answer the new name with
            # another package, so an entry the map does not translate reaches that package and is refused.
            $Run = Invoke-MpSync -Item (New-MpEntry) -RenameMap $null

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            [string]$Run.Rows[0].Error.FullyQualifiedErrorId | Should -BeLike 'AccessReviewScopeMismatch*'
            $Run.Rows[0].Detail | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews access package '$($script:MpPkgId)', not the access " +
                "package 'AP-New' ('$($script:MpOtherPkgId)') this entry declares, so it is not the review this entry declares. Nothing was " +
                "written. $($script:MpNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-New' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        }

        It 'updates the review of the assignment policy the run renames, checked by the id the map holds under the package <Key> (<Mode>)' -ForEach @(
            @{ Key = 'name'; Package = 'AP-Sales'; PackageLookups = 1; Mode = 'a real run'; PlanOnly = $false; Action = 'Updated'; Sets = 1 }
            @{ Key = 'id'; Package = 'aaaa1111-0000-0000-0000-000000000021'; PackageLookups = 0; Mode = 'a real run'; PlanOnly = $false; Action = 'Updated'; Sets = 1 }
            @{ Key = 'name'; Package = 'AP-Sales'; PackageLookups = 1; Mode = 'a plan under -WhatIf'; PlanOnly = $true; Action = 'Skipped'; Sets = 0 }
            @{ Key = 'id'; Package = 'aaaa1111-0000-0000-0000-000000000021'; PackageLookups = 0; Mode = 'a plan under -WhatIf'; PlanOnly = $true; Action = 'Skipped'; Sets = 0 }
        ) {
            # As the accessPackages handler registers a policy rename once it knows the package's id: under
            # the package's declared name and under its id.
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-Sales'; AccessPackageId = $script:MpPkgId
                Name = 'POL-New'; PreviousName = 'POL-Old'; Id = $null; PreviousId = $script:MpPolId
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AccessPackage $Package -AssignmentPolicy 'POL-New') -RenameMap $Map -WhatIf:$PlanOnly

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly $Action
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times $PackageLookups -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times $Sets -Exactly
        }

        It 'updates the review of a package and a policy the run both renames with no lookup at all' {
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-New'; AccessPackageId = $script:MpPkgId
                Name = 'POL-New'; PreviousName = 'POL-Old'; Id = $null; PreviousId = $script:MpPolId
            }
            $Item = New-MpEntry -AccessPackage 'AP-New' -AssignmentPolicy 'POL-New'
            $Run = Invoke-MpSync -Item $Item -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
            # The ids went into a copy: the entry the engine holds -- the parsed document -- keeps its names.
            $Item.accessPackage | Should -BeExactly 'AP-New'
            $Item.assignmentPolicy | Should -BeExactly 'POL-New'
        }

        It 'creates the review on the ids the map holds, <Case>' -ForEach @(
            @{ Case = 'for the package alone'; Policy = 'Standard'; PolicyRenamed = $false; ExpectedPolicy = 'Standard' }
            @{ Case = 'for the package and the policy'; Policy = 'POL-New'; PolicyRenamed = $true; ExpectedPolicy = 'bbbb2222-0000-0000-0000-000000000021' }
        ) {
            $script:MpLiveNow = $null
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            if ($PolicyRenamed) {
                Register-MpRename -RenameMap $Map -Splat @{
                    Section = 'assignmentPolicies'; AccessPackage = 'AP-New'; AccessPackageId = $script:MpPkgId
                    Name = 'POL-New'; PreviousName = 'POL-Old'; Id = $null; PreviousId = $script:MpPolId
                }
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AssignmentPolicy $Policy) -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Created'
            $Run.Rows[0].Detail | Should -BeExactly "created access review 'Q3 AP review' (recurrence: OneTime)"
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 1 -Exactly -ParameterFilter {
                $AccessPackage -eq 'aaaa1111-0000-0000-0000-000000000021' -and $AssignmentPolicy -eq $ExpectedPolicy -and $DisplayName -eq 'Q3 AP review'
            }
        }

        It 'plans the create of the review of a package the run renames under -WhatIf, with no lookup and no Failed row' {
            $script:MpLiveNow = $null
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            $Run = Invoke-MpSync -Item (New-MpEntry) -RenameMap $Map -WhatIf

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Skipped'
            $Run.Rows[0].Detail | Should -BeExactly "would create access review 'Q3 AP review'"
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
        }

        It 'says in the Failed row of the target check which declared name was read as which id, <Case>' -ForEach @(
            @{
                Case = 'for a review of another package'; LivePackage = 'aaaa1111-0000-0000-0000-000000000022'; LivePolicy = 'bbbb2222-0000-0000-0000-000000000021'; PolicyRenamed = $false; Policy = 'Standard'
                Expected = ("Access review 'Q3 AP review' in the tenant reviews access package 'aaaa1111-0000-0000-0000-000000000022', not the access " +
                    "package 'aaaa1111-0000-0000-0000-000000000021' this entry declares, so it is not the review this entry declares. Nothing was " +
                    'written. Access review display names are not unique: give the entry or the review in the tenant another display name. ' +
                    "(accessPackage 'AP-New' was read as 'aaaa1111-0000-0000-0000-000000000021', the access package this run renames from 'AP-Old')")
            }
            @{
                Case = 'for a review of another policy'; LivePackage = 'aaaa1111-0000-0000-0000-000000000021'; LivePolicy = 'bbbb2222-0000-0000-0000-000000000022'; PolicyRenamed = $true; Policy = 'POL-New'
                Expected = ("Access review 'Q3 AP review' in the tenant reviews assignment policy 'bbbb2222-0000-0000-0000-000000000022' of access " +
                    "package 'aaaa1111-0000-0000-0000-000000000021', not the assignment policy 'bbbb2222-0000-0000-0000-000000000021' this entry " +
                    'declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give ' +
                    "the entry or the review in the tenant another display name. (accessPackage 'AP-New' was read as " +
                    "'aaaa1111-0000-0000-0000-000000000021', the access package this run renames from 'AP-Old'; assignmentPolicy 'POL-New' was " +
                    "read as 'bbbb2222-0000-0000-0000-000000000021', the assignment policy this run renames from 'POL-Old')")
            }
        ) {
            $script:MpLiveNow = New-MpLive -AccessPackageId $LivePackage -AssignmentPolicyId $LivePolicy
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            if ($PolicyRenamed) {
                Register-MpRename -RenameMap $Map -Splat @{
                    Section = 'assignmentPolicies'; AccessPackage = 'AP-New'; AccessPackageId = $script:MpPkgId
                    Name = 'POL-New'; PreviousName = 'POL-Old'; Id = $null; PreviousId = $script:MpPolId
                }
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AssignmentPolicy $Policy) -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly $Expected
            # The record is the target check's own, unchanged: the note is in the row only.
            $Run.Errors.Count | Should -Be 1
            [string]$Run.Errors[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch,Invoke-SyncArViaCaller'
            $Run.Errors[0].Exception.Message | Should -Not -BeLike '*was read as*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
        }

        It 'does not read an access package named by its object id in the map, and checks the id as written' {
            # A map entry under a GUID-shaped NAME, refused: if the id were read in the map as a name, the
            # entry would be refused. A GUID is an object id, compared as written.
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'accessPackages'; Name = $script:MpPkgId; PreviousName = 'AP-Old'; Undecided = $true
                Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AccessPackage $script:MpPkgId) -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
        }

        It 'resolves both names exactly as before when the map holds nothing for them' {
            # The map holds other packages and policies -- refused ones among them -- but none this entry
            # names, so both names are looked up as they always have been.
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-Other'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $null }
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-Other'; Name = 'Standard'; PreviousName = 'POL-Old'; Undecided = $true
                Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            }
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-Sales'; Name = 'POL-Other'; PreviousName = 'POL-Old'; Undecided = $true
                Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Updated'
            $Run.Rows[0].Detail | Should -BeExactly "updated access review 'Q3 AP review' (durationInDays=21)"
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-Sales' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly -ParameterFilter {
                $AccessPackageId -eq 'aaaa1111-0000-0000-0000-000000000021' -and $AssignmentPolicy -eq 'Standard'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 1 -Exactly
        }
    }

    Context 'a refused or undecided rename refuses the review' {

        It 'refuses the review, reading and writing nothing, when the rename of its access package is <Case> (<Mode>)' -ForEach @(
            foreach ($Mode in @('a real run', 'a plan under -WhatIf')) {
                @{ Case = 'a conflict'; Mode = $Mode; Splat = @{ Id = 'aaaa1111-0000-0000-0000-000000000022'; PreviousId = 'aaaa1111-0000-0000-0000-000000000021' }; Reason = 'AccessPackageRenameConflict' }
                @{ Case = 'not found'; Mode = $Mode; Splat = @{ Id = $null; PreviousId = $null }; Reason = 'AccessPackageRenameNotFound' }
                @{ Case = 'undecided by its entry'; Mode = $Mode; Splat = @{ Undecided = $true; Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows" }; Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows" }
                @{ Case = 'undecided by -Include'; Mode = $Mode; Splat = @{ Undecided = $true; Reason = 'the accessPackages section is not selected by -Include, so its rename is not reconciled in this run' }; Reason = 'the accessPackages section is not selected by -Include, so its rename is not reconciled in this run' }
            }
        ) {
            $Map = New-MpMap
            $Splat = @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old' } + $Splat
            Register-MpRename -RenameMap $Map -Splat $Splat
            $Run = Invoke-MpSync -Item (New-MpEntry) -RenameMap $Map -WhatIf:($Mode -ne 'a real run')

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Section | Should -BeExactly 'accessReviews'
            $Run.Rows[0].Item | Should -BeExactly 'Q3 AP review'
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("access package 'AP-New' was not reconciled in this run: its rename from 'AP-Old' was refused ($Reason), " +
                'so the access package this access review reviews cannot be identified; nothing was created, read or written for it')
            $Run.Rows[0].Error | Should -BeNullOrEmpty
            # R9: no error record of its own -- the rename's own row carries one when it was refused.
            @($Run.All).Count | Should -Be 0
            # Nothing read: not the definition, not a name, not a reviewer; nothing written.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERStructurePrincipal -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
        }

        It 'refuses the review, reading and writing nothing, when the rename of its assignment policy is <Case>, the package named by <Key> (<Mode>)' -ForEach @(
            foreach ($Mode in @('a real run', 'a plan under -WhatIf')) {
                @{ Case = 'a conflict'; Key = 'name'; Package = 'AP-Sales'; Mode = $Mode; Splat = @{ AccessPackageId = 'aaaa1111-0000-0000-0000-000000000021'; Id = 'bbbb2222-0000-0000-0000-000000000022'; PreviousId = 'bbbb2222-0000-0000-0000-000000000021' }; Reason = 'AssignmentPolicyRenameConflict' }
                @{ Case = 'a conflict'; Key = 'id'; Package = 'aaaa1111-0000-0000-0000-000000000021'; Mode = $Mode; Splat = @{ AccessPackageId = 'aaaa1111-0000-0000-0000-000000000021'; Id = 'bbbb2222-0000-0000-0000-000000000022'; PreviousId = 'bbbb2222-0000-0000-0000-000000000021' }; Reason = 'AssignmentPolicyRenameConflict' }
                @{ Case = 'not found'; Key = 'name'; Package = 'AP-Sales'; Mode = $Mode; Splat = @{ AccessPackageId = 'aaaa1111-0000-0000-0000-000000000021'; Id = $null; PreviousId = $null }; Reason = 'AssignmentPolicyRenameNotFound' }
                @{ Case = 'not found'; Key = 'id'; Package = 'aaaa1111-0000-0000-0000-000000000021'; Mode = $Mode; Splat = @{ AccessPackageId = 'aaaa1111-0000-0000-0000-000000000021'; Id = $null; PreviousId = $null }; Reason = 'AssignmentPolicyRenameNotFound' }
                @{ Case = 'undecided by its package entry'; Key = 'name'; Package = 'AP-Sales'; Mode = $Mode; Splat = @{ Undecided = $true; Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows" }; Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows" }
                @{ Case = 'undecided by -Include'; Key = 'name'; Package = 'AP-Sales'; Mode = $Mode; Splat = @{ Undecided = $true; Reason = 'the accessPackages section is not selected by -Include, so its rename is not reconciled in this run' }; Reason = 'the accessPackages section is not selected by -Include, so its rename is not reconciled in this run' }
            }
        ) {
            $Map = New-MpMap
            $Splat = @{ Section = 'assignmentPolicies'; AccessPackage = 'AP-Sales'; Name = 'POL-New'; PreviousName = 'POL-Old' } + $Splat
            Register-MpRename -RenameMap $Map -Splat $Splat
            $Run = Invoke-MpSync -Item (New-MpEntry -AccessPackage $Package -AssignmentPolicy 'POL-New') -RenameMap $Map -WhatIf:($Mode -ne 'a real run')

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Section | Should -BeExactly 'accessReviews'
            $Run.Rows[0].Item | Should -BeExactly 'Q3 AP review'
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("assignment policy 'POL-New' of access package '$Package' was not reconciled in this run: its rename from " +
                "'POL-Old' was refused ($Reason), so the assignment policy this access review reviews cannot be identified; nothing was " +
                'created, read or written for it')
            $Run.Rows[0].Error | Should -BeNullOrEmpty
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC New-OERAccessReviewDefinition -Times 0
        }

        It 'refuses the review for its access package first when the renames of both its package and its policy are refused' {
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $null }
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-New'; Name = 'POL-New'; PreviousName = 'POL-Old'; Undecided = $true
                Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AssignmentPolicy 'POL-New') -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Detail | Should -BeExactly ("access package 'AP-New' was not reconciled in this run: its rename from 'AP-Old' was refused " +
                '(AccessPackageRenameNotFound), so the access package this access review reviews cannot be identified; nothing was created, read or written for it')
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 0
        }

        It 'reads an undecided policy under the package''s declared name when the map holds an id for the package' {
            # Undecided marks are registered under the package's name only: the policy is read under the
            # name the review declares, never under the id the package was translated to, which would miss
            # the mark and look the policy's new name up -- here another policy carries it.
            $Map = New-MpMap
            Register-MpRename -RenameMap $Map -Splat @{ Section = 'accessPackages'; Name = 'AP-New'; PreviousName = 'AP-Old'; Id = $null; PreviousId = $script:MpPkgId }
            Register-MpRename -RenameMap $Map -Splat @{
                Section = 'assignmentPolicies'; AccessPackage = 'AP-New'; Name = 'POL-New'; PreviousName = 'POL-Old'; Undecided = $true
                Reason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            }
            $Run = Invoke-MpSync -Item (New-MpEntry -AssignmentPolicy 'POL-New') -RenameMap $Map

            $Run.Rows.Count | Should -Be 1
            $Run.Rows[0].Action | Should -BeExactly 'Failed'
            $Run.Rows[0].Detail | Should -BeExactly ("assignment policy 'POL-New' of access package 'AP-New' was not reconciled in this run: its rename from " +
                "'POL-Old' was refused (the accessPackages entry did not reach a decision in this run; see that entry's rows), so the assignment " +
                'policy this access review reviews cannot be identified; nothing was created, read or written for it')
            @($Run.All).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERAccessReviewDefinition -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Set-OERAccessReviewDefinition -Times 0
        }
    }
}
