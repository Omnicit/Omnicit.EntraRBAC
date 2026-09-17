function New-OERAccessReviewDefinition {
    <#
    .SYNOPSIS
    Creates an access review schedule definition scoped to an access package.

    .DESCRIPTION
    Creates a v1.0 accessReviewScheduleDefinition via Microsoft Graph, scoped to the assignments
    of one access package under one assignment policy. Supports both single-stage (inline reviewer
    parameters) and multi-stage (pre-built stage objects from New-OERAccessReviewStage) reviews.
    Recurrence cadences OneTime through Annually are supported; OneTime produces a single instance.
    Scope, reviewer, and catalog ids are resolved from friendly display names or GUIDs. Supports
    -WhatIf and -Confirm.

    .PARAMETER DisplayName
    The display name for the access review definition.

    .PARAMETER DescriptionForAdmins
    A description visible to administrators in the review definition.

    .PARAMETER DescriptionForReviewers
    A description visible to reviewers when they are prompted to review.

    .PARAMETER AccessPackage
    The access package display name or id to scope the review to.

    .PARAMETER AssignmentPolicy
    The assignment policy display name or id whose assignments are reviewed.

    .PARAMETER Catalog
    Optional catalog display name or id. When omitted the catalog is derived from the access package.

    .PARAMETER Reviewer
    One or more primary reviewer user principal names or user object ids (GUIDs). Single-stage only.

    .PARAMETER ReviewerGroup
    One or more primary reviewer group display names or group object ids (GUIDs). Single-stage only.

    .PARAMETER Manager
    Add the reviewed principal's manager as a primary reviewer. Single-stage only. A manager reviewer
    requires a fallback reviewer (-FallbackReviewer or -FallbackReviewerGroup) for principals whose
    manager cannot be found; without one the create is rejected.

    .PARAMETER SelfReview
    Configure a self-review: the reviewers collection is left empty. Single-stage only.

    .PARAMETER FallbackReviewer
    One or more fallback reviewer user principal names or user object ids (GUIDs). Single-stage only.

    .PARAMETER FallbackReviewerGroup
    One or more fallback reviewer group display names or group object ids (GUIDs). Single-stage only.

    .PARAMETER Stage
    One or more pre-built stage objects from New-OERAccessReviewStage. Multi-stage only. When
    supplied, top-level reviewers are omitted; each stage carries its own reviewer collection.

    .PARAMETER Recurrence
    The review cadence: OneTime, Weekly, Monthly, Quarterly, or Annually. OneTime schedules a
    single review instance with no recurrence object on the definition.

    .PARAMETER StartDate
    The date the first review instance (or series) begins.

    .PARAMETER EndDate
    Optional end date for the recurrence series. Produces an endDate range. Mutually exclusive
    with -Occurrences; supplying both writes a non-terminating MutuallyExclusiveParameter error.

    .PARAMETER Occurrences
    Optional number of occurrences for the recurrence series. Produces a numbered range. Mutually
    exclusive with -EndDate; supplying both writes a non-terminating MutuallyExclusiveParameter error.
    Must be 1 or greater; a non-positive value fails parameter binding on this cmdlet.

    .PARAMETER DurationInDays
    Number of days reviewers have to complete each review instance. Defaults to 14. Also bindable
    as -DurationDays, the module-standard duration name used by the PIM cmdlets. Must be 1 or greater;
    a non-positive value fails parameter binding on this cmdlet.

    .PARAMETER MailNotification
    When present, Graph sends email notifications to reviewers about the review.

    .PARAMETER ReminderNotification
    When present, Graph sends reminder emails to reviewers who have not yet responded.

    .PARAMETER RequireJustification
    When present, reviewers must supply a justification when approving or denying access.

    .PARAMETER RecommendationsEnabled
    When present, Graph provides automated recommendations to reviewers.

    .PARAMETER AutoApplyDecisions
    When present, Graph automatically applies decisions when the review period ends.

    .PARAMETER DefaultDecision
    The decision applied to items not reviewed by the end of the review period.
    None (default) means no automatic decision; Approve, Deny, or Recommendation are
    the other options. Setting any value other than None also sets defaultDecisionEnabled.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERAccessReviewDefinition -DisplayName 'Q3 AP Review' -DescriptionForAdmins 'Quarterly review' `
        -DescriptionForReviewers 'Please review access' -AccessPackage 'AP-Sales' `
        -AssignmentPolicy 'Standard' -Reviewer 'manager@contoso.com' `
        -Recurrence Quarterly -StartDate (Get-Date '2026-07-01')
    Creates a quarterly single-stage access review with a named reviewer.

    .EXAMPLE
    $s1 = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Manager
    $s2 = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 3 -Reviewer 'admin@contoso.com'
    New-OERAccessReviewDefinition -DisplayName 'Multi-stage Q3' -DescriptionForAdmins 'a' `
        -DescriptionForReviewers 'r' -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' `
        -Stage $s1,$s2 -Recurrence Monthly -StartDate (Get-Date '2026-07-01')
    Creates a two-stage monthly access review where stage 2 escalates unresolved items from stage 1.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'SingleStage')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$DescriptionForAdmins,

        [Parameter(Mandatory)]
        [string]$DescriptionForReviewers,

        [Parameter(Mandatory)]
        [string]$AccessPackage,

        [Parameter(Mandatory)]
        [string]$AssignmentPolicy,

        [string]$Catalog,

        [Parameter(ParameterSetName = 'SingleStage')]
        [string[]]$Reviewer,

        [Parameter(ParameterSetName = 'SingleStage')]
        [string[]]$ReviewerGroup,

        [Parameter(ParameterSetName = 'SingleStage')]
        [switch]$Manager,

        [Parameter(ParameterSetName = 'SingleStage')]
        [switch]$SelfReview,

        [Parameter(ParameterSetName = 'SingleStage')]
        [string[]]$FallbackReviewer,

        [Parameter(ParameterSetName = 'SingleStage')]
        [string[]]$FallbackReviewerGroup,

        [Parameter(ParameterSetName = 'MultiStage', Mandatory)]
        [PSCustomObject[]]$Stage,

        [Parameter(Mandatory)]
        [ValidateSet('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')]
        [string]$Recurrence,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [datetime]$EndDate,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Occurrences,

        [Alias('DurationDays')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DurationInDays = 14,

        [switch]$MailNotification,

        [switch]$ReminderNotification,

        [switch]$RequireJustification,

        [switch]$RecommendationsEnabled,

        [switch]$AutoApplyDecisions,

        [ValidateSet('None', 'Approve', 'Deny', 'Recommendation')]
        [string]$DefaultDecision = 'None',

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # -EndDate and -Occurrences live in the same parameter set and are both optional, so the binder
        # cannot enforce their exclusivity. Guard up front: the private recurrence builder throws, and a
        # bare throw from a public cmdlet terminates the pipeline and ignores -ErrorAction.
        if ($PSBoundParameters.ContainsKey('EndDate') -and $PSBoundParameters.ContainsKey('Occurrences')) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "-EndDate and -Occurrences are mutually exclusive. Supply -EndDate to end the review " +
                    "series on a date, or -Occurrences to end it after a number of reviews, but not both.")) `
                -ErrorId 'MutuallyExclusiveParameter' `
                -Category InvalidArgument `
                -TargetObject $DisplayName `
                -Cmdlet $PSCmdlet
            return
        }

        # -SelfReview is a distinct reviewer mode (the reviewers collection is left empty) and cannot
        # be combined with a named or manager reviewer: Resolve-OERReviewerScope silently ignores
        # -SelfReview whenever -Reviewer/-ReviewerGroup/-Manager also resolve to a non-empty scope, so
        # letting the combination through here would silently drop -SelfReview instead of refusing it.
        # Checked before scope resolution (which hits Graph) so a bad combination costs no Graph call.
        # Round-1 review finding I-2: keyed on the BOUND VALUES, not $PSBoundParameters.ContainsKey().
        # Presence is not intent for a switch or a collection -- -Manager:$false is explicitly bound
        # (ContainsKey('Manager') is true) but its value is false, and splatting with
        # SelfReview = $false is the idiomatic way to build this call programmatically. A
        # ContainsKey-keyed guard refused both of those legitimate shapes. This mirrors the pattern
        # Sync-OERStructureAccessReview.ps1 already uses for the same mix ($AddSelfReview -and
        # ($AddManager -or ...)) -- the -EndDate/-Occurrences precedent this guard was originally
        # modeled on does not transfer here because those are VALUE parameters with no ":$false" form.
        if ($SelfReview -and ($Manager -or $Reviewer -or $ReviewerGroup)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    '-SelfReview cannot be combined with -Reviewer, -ReviewerGroup, or -Manager. A self ' +
                    'review leaves the reviewers collection empty; supply -SelfReview alone, or drop it and ' +
                    'use the named-reviewer parameters instead.')) `
                -ErrorId 'MutuallyExclusiveReviewer' `
                -Category InvalidArgument `
                -TargetObject $DisplayName `
                -Cmdlet $PSCmdlet
            return
        }

        $ScopeParams = @{ AccessPackage = $AccessPackage; AssignmentPolicy = $AssignmentPolicy }
        if ($Catalog) { $ScopeParams.Catalog = $Catalog }
        $Target = Resolve-OERAccessReviewScopeTarget @ScopeParams
        if ($Target.FailedValue) {
            # A resolver that supplies its own ErrorId/message knows more about the failure than the
            # generic "<Kind> '<Value>' not found." construction can express -- prefer it when present.
            $ScopeErrorId = if ($Target.FailedErrorId) { $Target.FailedErrorId } else { "$($Target.FailedKind)NotFound" }
            $ScopeMessage = if ($Target.FailedMessage) { $Target.FailedMessage } else { "$($Target.FailedKind) '$($Target.FailedValue)' not found." }
            # Only an ambiguity is a bad argument. The pre-existing CatalogDerivationFailed and the
            # plain not-found paths keep ObjectNotFound, so this is additive, not a behaviour change.
            # A resolver that supplies its own CATEGORY outranks both: a 403 or an exhausted 429 out
            # of the access-package resolver is neither a bad argument nor a missing object, and the
            # ErrorId alone cannot say so (it is whatever Graph named the failure).
            #
            # WHAT ACTUALLY SUPPLIES A CATEGORY, precisely, since the precedence below turns on it:
            # Resolve-OERAccessReviewScopeTarget populates FailedCategory on EVERY throw out of
            # Resolve-OERAccessPackageId -- 'InvalidArgument' on the ambiguity path and the caught
            # record's own ErrorCategory (PermissionDenied, ObjectNotFound, ...) on every other --
            # and leaves it $null on every path that does not come out of that catch: the plain
            # no-match, both catalog paths, and the assignment policy.
            # A CONSEQUENCE WORTH KNOWING: 'AmbiguousAccessPackageName' therefore never reaches the
            # elseif below -- the resolver already answered 'InvalidArgument' for it, and the first
            # arm wins. That arm is kept naming it anyway, and is not dead weight: it is what makes
            # this cmdlet report an ambiguity as InvalidArgument if the resolver ever stops
            # supplying a category for one, which is the obvious "only pass a category where the
            # ErrorId cannot reveal it" simplification. Without it, that edit would silently
            # downgrade an ambiguous access package to ObjectNotFound with no test going red.
            # 'AmbiguousCatalogName' does still reach it today: the catalog branch passes no
            # category at all.
            $ScopeCategory = if ($Target.FailedCategory) { $Target.FailedCategory }
            elseif ($ScopeErrorId -in @('AmbiguousAccessPackageName', 'AmbiguousCatalogName')) { 'InvalidArgument' }
            else { 'ObjectNotFound' }
            Write-CmdletError `
                -Message ([System.Exception]::new($ScopeMessage)) `
                -ErrorId $ScopeErrorId -Category $ScopeCategory `
                -TargetObject $Target.FailedValue -Cmdlet $PSCmdlet
            return
        }
        $Scope = New-OERAccessReviewScopeQuery `
            -AccessPackageId $Target.AccessPackageId `
            -AssignmentPolicyId $Target.AssignmentPolicyId

        $Settings = @{
            mailNotificationsEnabled        = [bool]$MailNotification
            reminderNotificationsEnabled    = [bool]$ReminderNotification
            justificationRequiredOnApproval = [bool]$RequireJustification
            recommendationsEnabled          = [bool]$RecommendationsEnabled
            defaultDecisionEnabled          = ($DefaultDecision -ne 'None')
            defaultDecision                 = $DefaultDecision
            instanceDurationInDays          = $DurationInDays
            autoApplyDecisionsEnabled       = [bool]$AutoApplyDecisions
        }

        $RecArgs = @{ Recurrence = $Recurrence; StartDate = $StartDate }
        if ($PSBoundParameters.ContainsKey('EndDate'))     { $RecArgs.EndDate = $EndDate }
        if ($PSBoundParameters.ContainsKey('Occurrences')) { $RecArgs.Occurrences = $Occurrences }
        $RecurrenceObj = New-OERAccessReviewRecurrence @RecArgs
        if ($RecurrenceObj) { $Settings.recurrence = $RecurrenceObj }

        $Body = @{
            displayName             = $DisplayName
            descriptionForAdmins    = $DescriptionForAdmins
            descriptionForReviewers = $DescriptionForReviewers
            scope                   = $Scope
            settings                = $Settings
        }

        if ($PSCmdlet.ParameterSetName -eq 'MultiStage') {
            $InvalidStage = $Stage | Where-Object { $null -eq $_.PSObject.Properties['GraphStage'] }
            if ($InvalidStage) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('One or more -Stage elements are not valid stage objects. Use New-OERAccessReviewStage to build stage objects.')) `
                    -ErrorId 'InvalidStage' `
                    -Category InvalidArgument `
                    -TargetObject $DisplayName `
                    -Cmdlet $PSCmdlet
                return
            }
            $Body.stageSettings = @($Stage | ForEach-Object { $_.GraphStage })
        }
        else {
            $HasReviewer = $Reviewer -or $ReviewerGroup -or $Manager -or $SelfReview
            if (-not $HasReviewer) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('At least one of -Reviewer, -ReviewerGroup, -Manager, or -SelfReview must be specified. Use -SelfReview to configure a self-review.')) `
                    -ErrorId 'NoReviewer' `
                    -Category InvalidArgument `
                    -TargetObject $DisplayName `
                    -Cmdlet $PSCmdlet
                return
            }

            $ReviewerParams = @{}
            if ($Reviewer)             { $ReviewerParams.Reviewer             = $Reviewer }
            if ($ReviewerGroup)        { $ReviewerParams.ReviewerGroup        = $ReviewerGroup }
            if ($Manager)              { $ReviewerParams.Manager              = $Manager }
            if ($SelfReview)           { $ReviewerParams.SelfReview           = $SelfReview }
            if ($FallbackReviewer)     { $ReviewerParams.FallbackReviewer     = $FallbackReviewer }
            if ($FallbackReviewerGroup){ $ReviewerParams.FallbackReviewerGroup = $FallbackReviewerGroup }
            if ($TenantId)             { $ReviewerParams.TenantId             = $TenantId }

            $Resolved = Resolve-OERReviewerScope @ReviewerParams
            if ($Resolved.FailedValue) {
                # Prefer the resolver's own ErrorId/message (an ambiguous name names the candidate ids).
                $ReviewerErrorId = if ($Resolved.FailedErrorId) { $Resolved.FailedErrorId } else { "$($Resolved.FailedKind)NotFound" }
                $ReviewerMessage = if ($Resolved.FailedMessage) { $Resolved.FailedMessage } else { "$($Resolved.FailedKind) '$($Resolved.FailedValue)' not found." }
                # An ambiguity is a bad argument, not a missing object; the not-found path is unchanged.
                $ReviewerCategory = if ($Resolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
                Write-CmdletError `
                    -Message ([System.Exception]::new($ReviewerMessage)) `
                    -ErrorId $ReviewerErrorId -Category $ReviewerCategory `
                    -TargetObject $Resolved.FailedValue -Cmdlet $PSCmdlet
                return
            }
            # A manager reviewer requires a fallback reviewer: Graph cannot route a review to the
            # reviewed principal's manager when the manager is absent, and rejects a manager scope with
            # no fallback as "Policy is invalid due to invalid criteria". Fail fast with a clear message
            # instead of letting that cryptic Graph 400 surface.
            if ($Manager -and @($Resolved.FallbackReviewers).Count -eq 0) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('A manager reviewer requires a fallback reviewer. Specify -FallbackReviewer or -FallbackReviewerGroup.')) `
                    -ErrorId 'ManagerFallbackRequired' -Category InvalidArgument `
                    -TargetObject $DisplayName -Cmdlet $PSCmdlet
                return
            }
            $Body.reviewers         = @($Resolved.Reviewers)
            $Body.fallbackReviewers = @($Resolved.FallbackReviewers)
        }

        if ($PSCmdlet.ShouldProcess($DisplayName, 'Create access review definition')) {
            try {
                $Response = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/accessReviews/definitions' -Body $Body
            }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAccessReviewDefinition -InputObject $Response
        }
    }
}
