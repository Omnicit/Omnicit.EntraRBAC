function Set-OERAccessReviewDefinition {
    <#
    .SYNOPSIS
    Updates an existing access review schedule definition using a full PUT replace.

    .DESCRIPTION
    Updates an access review schedule definition through Microsoft Graph using the v1.0 PUT
    endpoint (PUT v1.0/identityGovernance/accessReviews/definitions/{id}). Graph requires the
    FULL object in a PUT body -- a partial body would silently wipe any omitted writable property.

    To avoid data loss, this cmdlet performs a read-modify-write cycle:
      1. GET the current definition from Graph.
      2. Copy all writable properties (displayName, descriptionForAdmins, descriptionForReviewers,
         scope, settings, reviewers, fallbackReviewers, stageSettings, instanceEnumerationScope,
         additionalNotificationRecipients) into the PUT body. settings is rebuilt key by key so
         unmodelled settings keys survive; the deprecated backupReviewers is deliberately not copied,
         because Graph keeps it mirrored with fallbackReviewers automatically.
      3. Overlay only the properties whose corresponding parameters were explicitly supplied.
      4. PUT the full merged body back to Graph (returns 204 No Content).
      5. GET the updated definition again and return it as a tagged object.

    This means only the parameters you supply change; all other properties are preserved exactly
    as they were in Graph.

    RESIDUAL LIMITATION: the carry-forward list is explicit, never a blanket copy of the GET (the
    read-only properties id, status, createdDateTime, lastModifiedDateTime, createdBy, instances and
    the @odata.* annotations must not be sent back). A writable top-level property added to the
    Microsoft Graph accessReviewScheduleDefinition resource AFTER this list was written would
    therefore still be cleared by the PUT. Extend the carry-forward list when the resource gains a
    new writable property.

    A 204 from the PUT means the request was ACCEPTED, not that the value was stored. Because changes
    apply to future instances only, a definition with no future instance left has been observed to
    accept the write and read back unchanged, with no error of any kind. Step 5 below is therefore the
    only proof available to a caller that an update took effect: compare the returned definition
    against what you asked for rather than treating the absence of an error as success.
    Sync-OERStructureAccessReview does exactly that before it reports Updated.

    IMPORTANT GRAPH LIMITATIONS (surfaced as errors if violated):
    -- Changes apply to FUTURE review instances only; active/completed instances are not affected.
    -- 'reviewers' is updatable only if individual users are assigned (not group membership review).
    -- In a multi-stage review, only reviewers/fallbackReviewers inside stageSettings are updatable.
    -- Graph returns a descriptive error for unsupported update combinations; this cmdlet surfaces it.

    At least one updatable property must be supplied or a non-terminating NothingToUpdate error is
    emitted. -EndDate and -Occurrences do not by themselves count as updatable: neither changes
    anything unless -Recurrence and -StartDate are also supplied, so a call carrying only one of them
    still trips the guard.

    Supports -WhatIf and -Confirm.

    .PARAMETER Id
    The access review definition id (GUID) or display name to update. Accepts pipeline input by
    property name. A GUID is used verbatim with no Graph call; a display name is resolved to an id
    via Resolve-OERAccessReviewDefinitionId, which returns the FIRST matching definition with no
    ambiguity check -- the same behaviour as this resolver's other six call sites in the module.

    .PARAMETER DisplayName
    New display name for the access review definition.

    .PARAMETER DescriptionForAdmins
    New description visible to administrators.

    .PARAMETER DescriptionForReviewers
    New description visible to reviewers.

    .PARAMETER Reviewer
    Replace primary reviewers with these user principal names or user object ids (GUIDs).

    .PARAMETER ReviewerGroup
    Replace primary reviewers with members of these groups (display names or GUIDs).

    .PARAMETER Manager
    Include the reviewed principal's manager as a primary reviewer.

    .PARAMETER SelfReview
    Replace primary reviewers with an empty list (self-review).

    .PARAMETER FallbackReviewer
    Replace fallback reviewers with these user principal names or user object ids (GUIDs).

    .PARAMETER FallbackReviewerGroup
    Replace fallback reviewers with members of these groups (display names or GUIDs).

    .PARAMETER Stage
    Replace stageSettings with these pre-built stage objects from New-OERAccessReviewStage.

    .PARAMETER Recurrence
    New recurrence cadence: OneTime, Weekly, Monthly, Quarterly, or Annually.
    Must be supplied together with -StartDate.

    .PARAMETER StartDate
    New start date for the recurrence series. Must be supplied together with -Recurrence.

    .PARAMETER EndDate
    Optional end date for the recurrence series. Requires -Recurrence and -StartDate. Mutually
    exclusive with -Occurrences; supplying both writes a non-terminating MutuallyExclusiveParameter error.

    .PARAMETER Occurrences
    Optional number of occurrences for the recurrence series. Requires -Recurrence and -StartDate.
    Mutually exclusive with -EndDate; supplying both writes a non-terminating MutuallyExclusiveParameter error.
    Must be 1 or greater; a non-positive value fails parameter binding on this cmdlet.

    .PARAMETER DurationInDays
    Number of days reviewers have to complete each review instance. Also bindable as -DurationDays,
    the module-standard duration name used by the PIM cmdlets. Must be 1 or greater; a non-positive
    value fails parameter binding on this cmdlet.

    .PARAMETER MailNotification
    When present, Graph sends email notifications to reviewers.

    .PARAMETER ReminderNotification
    When present, Graph sends reminder emails to reviewers.

    .PARAMETER RequireJustification
    When present, reviewers must supply a justification.

    .PARAMETER RecommendationsEnabled
    When present, Graph provides automated recommendations to reviewers.

    .PARAMETER AutoApplyDecisions
    When present, Graph automatically applies decisions when the review period ends.

    .PARAMETER DefaultDecision
    The decision applied to items not reviewed: None, Approve, Deny, or Recommendation.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERAccessReviewDefinition -Id 'd1' -DisplayName 'Q4 AP Review'
    Reads the current definition, updates only the display name, and PUTs the full object back.

    .EXAMPLE
    Set-OERAccessReviewDefinition -Id 'd1' -Recurrence Annually -StartDate (Get-Date '2027-01-01')
    Updates the recurrence schedule while preserving all other properties.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Id,

        [string]$DisplayName,
        [string]$DescriptionForAdmins,
        [string]$DescriptionForReviewers,

        [string[]]$Reviewer,
        [string[]]$ReviewerGroup,
        [switch]$Manager,
        [switch]$SelfReview,
        [string[]]$FallbackReviewer,
        [string[]]$FallbackReviewerGroup,

        [PSCustomObject[]]$Stage,

        [ValidateSet('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')]
        [string]$Recurrence,

        [datetime]$StartDate,
        [datetime]$EndDate,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Occurrences,
        [Alias('DurationDays')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DurationInDays,

        [switch]$MailNotification,
        [switch]$ReminderNotification,
        [switch]$RequireJustification,
        [switch]$RecommendationsEnabled,
        [switch]$AutoApplyDecisions,

        [ValidateSet('None', 'Approve', 'Deny', 'Recommendation')]
        [string]$DefaultDecision,

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
                -TargetObject $Id `
                -Cmdlet $PSCmdlet
            return
        }

        # -EndDate and -Occurrences are deliberately EXCLUDED from this predicate: neither changes
        # anything on its own -- both are only read above when -Recurrence and -StartDate are ALSO
        # supplied (see 3c below), so a call carrying just one of them would still be a no-op. This
        # cmdlet's no-op is worse than a wasted round trip: the write is a FULL PUT whose carry-forward
        # list is explicitly incomplete (see the RESIDUAL LIMITATION paragraph above), so a
        # nothing-to-update call could CLEAR a writable property Graph added after that list was
        # written. Placed after the MutuallyExclusiveParameter guard above on purpose, so that more
        # specific conflict error keeps priority over this one.
        $UpdatableBound = @(
            'DisplayName', 'DescriptionForAdmins', 'DescriptionForReviewers', 'Reviewer', 'ReviewerGroup',
            'Manager', 'SelfReview', 'FallbackReviewer', 'FallbackReviewerGroup', 'Stage', 'Recurrence',
            'StartDate', 'DurationInDays', 'MailNotification', 'ReminderNotification', 'RequireJustification',
            'RecommendationsEnabled', 'AutoApplyDecisions', 'DefaultDecision') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }
        if (-not $UpdatableBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    'No updatable property was supplied. Pass at least one of -DisplayName, ' +
                    '-DescriptionForAdmins, -DescriptionForReviewers, -Reviewer, -ReviewerGroup, -Manager, ' +
                    '-SelfReview, -FallbackReviewer, -FallbackReviewerGroup, -Stage, -Recurrence, -StartDate, ' +
                    '-DurationInDays, -MailNotification, -ReminderNotification, -RequireJustification, ' +
                    '-RecommendationsEnabled, -AutoApplyDecisions, or -DefaultDecision. -EndDate and ' +
                    '-Occurrences only bound the recurrence series and take effect together with -Recurrence ' +
                    'and -StartDate, so neither counts on its own.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Id `
                -Cmdlet $PSCmdlet
            return
        }

        # -SelfReview is a distinct reviewer mode (the reviewers collection is left empty) and cannot
        # be combined with a named or manager reviewer: Resolve-OERReviewerScope silently ignores
        # -SelfReview whenever -Reviewer/-ReviewerGroup/-Manager also resolve to a non-empty scope, so
        # letting the combination through here would silently drop -SelfReview instead of refusing it.
        # Checked before any Graph call (the id resolution and the read-modify-write GET both follow),
        # so a bad combination costs nothing.
        # Round-1 review finding I-2: keyed on the BOUND VALUES, not $PSBoundParameters.ContainsKey().
        # Presence is not intent for a switch or a collection -- -Manager:$false is explicitly bound
        # (ContainsKey('Manager') is true) but its value is false, and splatting with
        # SelfReview = $false is the idiomatic way to build this call programmatically. A
        # ContainsKey-keyed guard refused both of those legitimate shapes. This mirrors the pattern
        # Sync-OERStructureAccessReview.ps1 already uses for the same mix ($UpdSelf -and
        # ($UpdManager -or ...)) -- the -EndDate/-Occurrences precedent this guard was originally
        # modeled on does not transfer here because those are VALUE parameters with no ":$false" form.
        if ($SelfReview -and ($Manager -or $Reviewer -or $ReviewerGroup)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    '-SelfReview cannot be combined with -Reviewer, -ReviewerGroup, or -Manager. A self ' +
                    'review leaves the reviewers collection empty; supply -SelfReview alone, or drop it and ' +
                    'use the named-reviewer parameters instead.')) `
                -ErrorId 'MutuallyExclusiveReviewer' `
                -Category InvalidArgument `
                -TargetObject $Id `
                -Cmdlet $PSCmdlet
            return
        }

        # Resolve -Id to the definition id before the read-modify-write GET. A GUID is returned
        # verbatim with no Graph call (Resolve-OERAccessReviewDefinitionId), so a GUID caller stays
        # byte-identical to the pre-Task-4b behaviour. Any resolve failure (Graph throttling, auth,
        # or a genuine no-match) collapses into the SAME AccessReviewDefinitionNotFound error this
        # cmdlet already emitted for a definition that vanished between the resolve and the GET --
        # mirroring Remove-OERAccessReviewDefinition's fold of the two failure modes into one outcome.
        $DefId = try {
            Resolve-OERAccessReviewDefinitionId -DisplayName $Id
        }
        catch {
            Remove-OERErrorRecord -Record $PSItem
            $null
        }
        if (-not $DefId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Access review definition '$Id' not found.")) `
                -ErrorId 'AccessReviewDefinitionNotFound' -Category ObjectNotFound `
                -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # 1. GET the current definition for read-modify-write
        try {
            $Current = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $DefId)
        }
        catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if ($null -eq $Current) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Access review definition '$Id' not found.")) `
                -ErrorId 'AccessReviewDefinitionNotFound' -Category ObjectNotFound `
                -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # 2. Build the PUT body from the current writable properties
        $Body = @{
            displayName             = $Current.displayName
            descriptionForAdmins    = $Current.descriptionForAdmins
            descriptionForReviewers = $Current.descriptionForReviewers
            scope                   = $Current.scope
        }
        # Rebuild settings as a mutable hashtable preserving all existing keys
        $Settings = @{}
        if ($Current.settings) {
            foreach ($Key in $Current.settings.Keys) {
                $Settings[$Key] = $Current.settings[$Key]
            }
        }
        if ($Current.reviewers)         { $Body.reviewers         = $Current.reviewers }
        if ($Current.fallbackReviewers) { $Body.fallbackReviewers = $Current.fallbackReviewers }
        if ($Current.stageSettings)     { $Body.stageSettings     = $Current.stageSettings }

        # Writable top-level properties this cmdlet does not model, carried forward BY NAME so the
        # full-replace PUT cannot clear them. Named carry-forward, never a blanket copy of $Current:
        # the read-only properties (id, status, createdDateTime, lastModifiedDateTime, createdBy,
        # instances and the @odata.* annotations) must not be PUT back or Graph can reject the update.
        # Per the Microsoft Graph v1.0 accessReviewScheduleDefinition resource, the writable top-level
        # set is displayName, descriptionForAdmins, descriptionForReviewers, scope, settings,
        # reviewers, fallbackReviewers, stageSettings, instanceEnumerationScope,
        # additionalNotificationRecipients and the deprecated backupReviewers. backupReviewers is NOT
        # carried: Graph keeps it and fallbackReviewers mirrored automatically, so re-sending a stale
        # copy alongside a new fallbackReviewers would conflict with the value being written.
        foreach ($CarryKey in @('instanceEnumerationScope', 'additionalNotificationRecipients')) {
            if ($null -ne $Current.$CarryKey) { $Body[$CarryKey] = $Current.$CarryKey }
        }

        # 3a. Overlay text fields
        if ($PSBoundParameters.ContainsKey('DisplayName'))             { $Body.displayName             = $DisplayName }
        if ($PSBoundParameters.ContainsKey('DescriptionForAdmins'))    { $Body.descriptionForAdmins    = $DescriptionForAdmins }
        if ($PSBoundParameters.ContainsKey('DescriptionForReviewers')) { $Body.descriptionForReviewers = $DescriptionForReviewers }

        # 3b. Overlay only the bound settings keys -- all other keys are preserved
        if ($PSBoundParameters.ContainsKey('MailNotification'))       { $Settings.mailNotificationsEnabled        = [bool]$MailNotification }
        if ($PSBoundParameters.ContainsKey('ReminderNotification'))   { $Settings.reminderNotificationsEnabled    = [bool]$ReminderNotification }
        if ($PSBoundParameters.ContainsKey('RequireJustification'))   { $Settings.justificationRequiredOnApproval = [bool]$RequireJustification }
        if ($PSBoundParameters.ContainsKey('RecommendationsEnabled')) { $Settings.recommendationsEnabled          = [bool]$RecommendationsEnabled }
        if ($PSBoundParameters.ContainsKey('AutoApplyDecisions'))     { $Settings.autoApplyDecisionsEnabled       = [bool]$AutoApplyDecisions }
        if ($PSBoundParameters.ContainsKey('DefaultDecision')) {
            $Settings.defaultDecision        = $DefaultDecision
            $Settings.defaultDecisionEnabled = ($DefaultDecision -ne 'None')
        }
        if ($PSBoundParameters.ContainsKey('DurationInDays')) { $Settings.instanceDurationInDays = $DurationInDays }

        # 3c. Recurrence -- both params required together or neither
        $RecBound  = $PSBoundParameters.ContainsKey('Recurrence')
        $DateBound = $PSBoundParameters.ContainsKey('StartDate')
        if ($RecBound -xor $DateBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-Recurrence and -StartDate must both be supplied together.')) `
                -ErrorId 'IncompleteRecurrence' -Category InvalidArgument `
                -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }
        if ($RecBound -and $DateBound) {
            $RecArgs = @{ Recurrence = $Recurrence; StartDate = $StartDate }
            if ($PSBoundParameters.ContainsKey('EndDate'))     { $RecArgs.EndDate = $EndDate }
            if ($PSBoundParameters.ContainsKey('Occurrences')) { $RecArgs.Occurrences = $Occurrences }
            $RecurrenceObj = New-OERAccessReviewRecurrence @RecArgs
            if ($RecurrenceObj) {
                $Settings.recurrence = $RecurrenceObj
            }
            else {
                # OneTime -- remove any existing recurrence key
                $null = $Settings.Remove('recurrence')
            }
        }

        $Body.settings = $Settings

        # 3d. Reviewers -- any reviewer param replaces the reviewer arrays
        $ReviewerKeys = @('Reviewer', 'ReviewerGroup', 'Manager', 'SelfReview', 'FallbackReviewer', 'FallbackReviewerGroup')
        $AnyReviewers = $ReviewerKeys | Where-Object { $PSBoundParameters.ContainsKey($_) }
        if ($AnyReviewers) {
            $ReviewerParams = @{}
            if ($Reviewer)              { $ReviewerParams.Reviewer              = $Reviewer }
            if ($ReviewerGroup)         { $ReviewerParams.ReviewerGroup         = $ReviewerGroup }
            if ($Manager)               { $ReviewerParams.Manager               = $Manager }
            if ($SelfReview)            { $ReviewerParams.SelfReview            = $SelfReview }
            if ($FallbackReviewer)      { $ReviewerParams.FallbackReviewer      = $FallbackReviewer }
            if ($FallbackReviewerGroup) { $ReviewerParams.FallbackReviewerGroup = $FallbackReviewerGroup }
            if ($TenantId)              { $ReviewerParams.TenantId              = $TenantId }

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
            $Body.reviewers         = @($Resolved.Reviewers)
            $Body.fallbackReviewers = @($Resolved.FallbackReviewers)
        }

        # 3e. Stage replacement
        if ($PSBoundParameters.ContainsKey('Stage')) {
            $InvalidStage = $Stage | Where-Object { $null -eq $_.PSObject.Properties['GraphStage'] }
            if ($InvalidStage) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('One or more -Stage elements are not valid stage objects. Use New-OERAccessReviewStage to build stage objects.')) `
                    -ErrorId 'InvalidStage' `
                    -Category InvalidArgument `
                    -TargetObject $Id `
                    -Cmdlet $PSCmdlet
                return
            }
            $Body.stageSettings = @($Stage | ForEach-Object { $_.GraphStage })
        }

        # 4. PUT the full object -- Graph returns 204 No Content
        if ($PSCmdlet.ShouldProcess($Id, 'Update access review definition')) {
            try {
                $null = Invoke-OERGraphRequest -Method PUT `
                    -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $DefId) `
                    -Body $Body
            }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }

            # 5. Re-GET and emit the updated definition
            try {
                $Response = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $DefId)
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
