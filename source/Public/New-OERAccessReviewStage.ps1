function New-OERAccessReviewStage {
    <#
    .SYNOPSIS
    Builds one stage definition for a multi-stage access review.

    .DESCRIPTION
    Returns a tagged Omnicit.EntraRBAC.AccessReviewStageSetting object describing a single stage, for use
    with the -Stage parameter of New-OERAccessReviewDefinition. Reviewers are supplied as any
    combination of -Reviewer (user principal names or object ids), -ReviewerGroup (group display names
    or object ids), -Manager (the reviewed principal's direct manager), and -SelfReview (empty
    reviewers collection, meaning the subject reviews themselves); at least one is required. Names are
    resolved to object ids and a GUID is used directly. -FallbackReviewer/-FallbackReviewerGroup supply
    fallback reviewers if no primary reviewer responds. Resolution authenticates lazily -- only when a
    non-GUID name is present -- so a pure-GUID or switch-only input performs no Graph call. The object
    carries a GraphStage member holding the Graph-ready accessReviewStageSettings body for direct
    insertion into the definition body.

    .PARAMETER StageId
    A short identifier for the stage, referenced by -DependsOn in later stages. Defaults to '1'.

    .PARAMETER DependsOn
    Zero or more StageId values that must complete before this stage begins (multi-stage reviews only).

    .PARAMETER DurationInDays
    The number of days that reviewers have to respond in this stage. Also bindable as -DurationDays,
    the module-standard duration name used by the PIM cmdlets. Must be 1 or greater; a non-positive
    value fails parameter binding on this cmdlet.

    .PARAMETER RecommendationsEnabled
    When present, Graph will provide automated recommendations to reviewers in this stage.

    .PARAMETER DecisionsThatMoveToNextStage
    One or more decisions (Approve, Deny, Recommendation, NotReviewed) that advance the item to the
    next stage. When omitted, Graph uses its default advancement behaviour.

    .PARAMETER Reviewer
    Zero or more primary reviewer user principal names or user object ids (GUIDs).

    .PARAMETER ReviewerGroup
    Zero or more primary reviewer group display names or group object ids (GUIDs); transitiveMembers review.

    .PARAMETER Manager
    Add the reviewed principal's manager as a primary reviewer.

    .PARAMETER SelfReview
    Configure a self-review: the reviewers collection is left empty (the subject reviews themselves).

    .PARAMETER FallbackReviewer
    Zero or more fallback reviewer user principal names or user object ids (GUIDs).

    .PARAMETER FallbackReviewerGroup
    Zero or more fallback reviewer group display names or group object ids (GUIDs).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth when name
    resolution requires a Graph call.

    .EXAMPLE
    New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Reviewer 'anna.berg@contoso.com'
    Builds stage 1 with a 7-day window and a named user reviewer.

    .EXAMPLE
    $s1 = New-OERAccessReviewStage -StageId '1' -DurationInDays 7 -Manager
    $s2 = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 3 -Reviewer 'admin@contoso.com' -DecisionsThatMoveToNextStage Deny,NotReviewed
    Builds two stages where stage 2 begins only after stage 1, escalating unresolved items.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Read-only builder; resolves names via Graph lookups and returns an object, but changes no state.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$StageId = '1',

        [string[]]$DependsOn,

        [Parameter(Mandatory)]
        [Alias('DurationDays')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DurationInDays,

        [switch]$RecommendationsEnabled,

        [ValidateSet('Approve', 'Deny', 'Recommendation', 'NotReviewed')]
        [string[]]$DecisionsThatMoveToNextStage,

        [string[]]$Reviewer,

        [string[]]$ReviewerGroup,

        [switch]$Manager,

        [switch]$SelfReview,

        [string[]]$FallbackReviewer,

        [string[]]$FallbackReviewerGroup,

        [string]$TenantId
    )
    process {
        # -SelfReview is a distinct reviewer mode (the reviewers collection is left empty) and cannot
        # be combined with a named or manager reviewer: Resolve-OERReviewerScope silently ignores
        # -SelfReview whenever -Reviewer/-ReviewerGroup/-Manager also resolve to a non-empty scope, so
        # letting the combination through here would silently drop -SelfReview instead of refusing it.
        # Checked first, before any name resolution, so a bad combination costs no Graph call.
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
                -TargetObject $StageId `
                -Cmdlet $PSCmdlet
            return
        }

        if (-not ($Reviewer -or $ReviewerGroup -or $Manager -or $SelfReview)) {
            Write-CmdletError `
                -Message ([System.Exception]::new('At least one reviewer is required: supply -Reviewer, -ReviewerGroup, -Manager, or -SelfReview.')) `
                -ErrorId 'NoReviewer' -Category InvalidArgument -TargetObject $StageId -Cmdlet $PSCmdlet
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
            $ErrId = if ($Resolved.FailedErrorId) { $Resolved.FailedErrorId }
            elseif ($Resolved.FailedKind -eq 'User') { 'UserNotFound' } else { 'GroupNotFound' }
            $Msg = if ($Resolved.FailedMessage) { $Resolved.FailedMessage }
            else { "$($Resolved.FailedKind) '$($Resolved.FailedValue)' not found." }
            # An ambiguity is a bad argument, not a missing object; the not-found path is unchanged.
            $Cat = if ($Resolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
            Write-CmdletError `
                -Message ([System.Exception]::new($Msg)) `
                -ErrorId $ErrId -Category $Cat -TargetObject $Resolved.FailedValue -Cmdlet $PSCmdlet
            return
        }

        $GraphStage = [ordered]@{
            stageId                = $StageId
            durationInDays         = $DurationInDays
            recommendationsEnabled = [bool]$RecommendationsEnabled
            reviewers              = @($Resolved.Reviewers)
            fallbackReviewers      = @($Resolved.FallbackReviewers)
        }
        if ($PSBoundParameters.ContainsKey('DependsOn')) {
            $GraphStage.dependsOn = @($DependsOn)
        }
        if ($PSBoundParameters.ContainsKey('DecisionsThatMoveToNextStage')) {
            $GraphStage.decisionsThatWillMoveToNextStage = @($DecisionsThatMoveToNextStage)
        }

        $Out = [PSCustomObject]@{
            StageId       = $StageId
            DurationInDays = $DurationInDays
            ReviewerCount = @($Resolved.Reviewers).Count
            GraphStage    = $GraphStage
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewStageSetting')
        $Out
    }
}
