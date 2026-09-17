function Resolve-OERAccessReviewChange {
    <#
    .SYNOPSIS
    Computes the access review definition parameter changes needed to make an existing review match a
    declared apply-document entry.

    .DESCRIPTION
    Pure, tenant-free diff used by the Invoke-OERStructure access review handler. Compares a declared
    accessReviews[] entry against the live definition returned by Get-OERAccessReviewDefinition and
    returns a tagged result with a Changed flag, a SetParams hashtable ready to splat into
    Set-OERAccessReviewDefinition (only the fields that differ, never the definition Id), a
    human-readable Changes list, and a NotApplied list naming declared drifts the engine cannot write.
    Presence semantics apply: a field the document does not declare is never compared and never sent.
    A field present with an explicit JSON null counts as UNDECLARED too, matching the offline
    validator Test-OERStructureSchema, so a null can never be cast into a $false toggle or an empty
    description that silently overwrites the live definition.

    Two groups are diffed as a UNIT so a partial write can never corrupt the definition. Reviewers and
    fallback reviewers move together, because Set-OERAccessReviewDefinition rebuilds both arrays as
    soon as any reviewer parameter is bound. Recurrence, start date and range move together, because
    Set-OERAccessReviewDefinition requires -Recurrence and -StartDate in the same call; the start date
    falls back to the live recurrence range startDate when the document omits it, and when neither is
    available the recurrence change is reported in NotApplied rather than written half-applied.

    Two consequences of how the recurrence object is rebuilt are handled explicitly. A OneTime review
    carries no recurrence object at all, so it has no range to diff: for an effective OneTime cadence
    only the cadence itself is compared and no range is written, otherwise a declared startDate would
    be measured against a live range that cannot exist and would report drift on every single apply.
    And because Set-OERAccessReviewDefinition replaces the whole recurrence object -- defaulting the
    range to noEnd when neither -EndDate nor -Occurrences is bound -- a live endDate or numbered range
    is carried forward whenever the document declares neither, so changing only the cadence or the
    start date does not silently destroy the range.

    A third consequence: New-OERAccessReviewRecurrence can only emit weekly interval 1 and
    absoluteMonthly interval 1/3/12, so a live pattern outside that set (a semi-annual absoluteMonthly
    interval 6, a bi-weekly weekly interval 2, ...) cannot be reproduced. Rebuilding the recurrence
    object from the collapsed cadence in that case would silently downgrade the live review to a
    coarser one while reporting Updated. The recurrence/startDate/endDate/occurrences unit is therefore
    suppressed and reported in NotApplied instead whenever the live pattern is not representable, even
    when some other field in the same unit legitimately differs.

    Reviewer sets are compared on RESOLVED OBJECT IDS supplied by the caller in -DeclaredReviewer, so
    a display-name change in the tenant does not look like drift. The live keys are derived from each
    reviewer scope query by Resolve-OERReviewerScopeQuery, the module's single owner of that grammar:
    './manager' becomes manager, '/users/{id}' and '/groups/{id}' become the id (with or without the
    API version prefix Graph adds when it normalizes a scope on read), and an EMPTY live reviewer list
    becomes self. The primary and fallback halves are independently presence-gated through the
    HasReviewers and HasFallbackReviewers flags: a half the document does not declare is seeded from
    the live definition's own object ids instead of being sent empty, so it survives the write
    untouched and never forces an update on its own.

    A live scope that does NOT parse is kept strictly apart from an absent one. An empty reviewers
    collection is the documented self-review shape; an unparsed scope is a real named reviewer this
    module's vocabulary cannot express, and reading it as a self review would write SelfReview back
    over live reviewers. So an unparsed scope never becomes self, and it changes the diff two ways: a
    DECLARED half can no longer prove equality from a key-set match (the parsed keys are only a subset
    of what is live), so the change is forced and the replaced queries are named in Changes; a SEEDED
    half cannot be re-sent verbatim at all, so the whole reviewer unit is suppressed and reported in
    NotApplied rather than silently dropping the reviewer on the write.

    The review SCOPE (accessPackage and assignmentPolicy) is immutable on an existing definition. A
    declared scope that differs from the live one is reported in NotApplied so the operator sees the
    divergence instead of a misleading Unchanged. Because the document carries display names while the
    live definition carries ids, a scope difference is only reported when the declared value is a GUID
    that does not match the live id -- a display name cannot be compared without a Graph call.

    This diff is run TWICE per update by Sync-OERStructureAccessReview: once against the live
    definition to decide what to send, and once against the definition Set-OERAccessReviewDefinition
    returns after its PUT, to prove the write actually landed before the engine reports Updated. Being
    pure is what makes the second run free. Keep it symmetric: a comparison that can report drift
    against a definition that already carries the declared value would turn every successful apply into
    a reported failure.

    No Graph, ARM, or authentication occurs.

    .PARAMETER Declared
    One accessReviews[] entry from the structure document. Recognized fields: accessPackage,
    assignmentPolicy, descriptionForAdmins, descriptionForReviewers, durationInDays, recurrence,
    startDate, endDate, occurrences, mailNotification, reminderNotification, requireJustification,
    recommendationsEnabled, autoApplyDecisions and defaultDecision.

    .PARAMETER Current
    The live definition as returned by Get-OERAccessReviewDefinition, carrying Reviewers,
    FallbackReviewers, Recurrence, DurationInDays, both descriptions, the scope ids and the raw
    Settings dictionary.

    .PARAMETER DeclaredReviewer
    The caller-resolved reviewer block, omitted when the document declares neither reviewers nor
    fallbackReviewers. Expected members: Manager, SelfReview, Reviewer, ReviewerGroup,
    FallbackReviewer, FallbackReviewerGroup (the friendly values passed straight to
    Set-OERAccessReviewDefinition), ReviewerKey and FallbackKey (resolved object ids, with manager and
    self as literal keys) used only for comparison, plus the HasReviewers and HasFallbackReviewers
    flags saying which of the two halves the document actually declared. An absent flag counts as
    declared, so the undeclared-half seeding never engages behind a caller that does not set them.

    .EXAMPLE
    Resolve-OERAccessReviewChange -Declared $DocItem -Current $LiveDefinition
    Returns the SetParams needed to reconcile the review, or Changed = $false when it already matches.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Declared,
        [Parameter(Mandatory)][PSCustomObject]$Current,
        [PSCustomObject]$DeclaredReviewer
    )

    $SetParams  = @{}
    $Changes    = [System.Collections.Generic.List[string]]::new()
    $NotApplied = [System.Collections.Generic.List[string]]::new()

    # A property that is present but NULL counts as UNDECLARED, exactly as the offline validator's
    # Test-HasProp does -- the schema layer and the diff layer have to agree on what "declared" means.
    # Without the null guard a "mailNotification": null would cast to $false and switch the live
    # notifications OFF, and a "descriptionForAdmins": null would cast to '' and wipe the description.
    # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
    function Test-DeclHas {
        param([object]$Node, [string]$Name)
        Test-OERDeclaredProperty -Node $Node -Name $Name
    }

    function Get-SettingValue {
        param([object]$Settings, [string]$Key)
        if ($null -eq $Settings) { return $null }
        # The live settings are a raw Graph dictionary, which has no PSObject.Properties to enumerate,
        # so index it directly and fall back to property access for a PSCustomObject fixture.
        # ContainsKey, not Contains: on a generic Dictionary[string, object] the Contains overload
        # takes a KeyValuePair and would throw on a bare key.
        if ($Settings -is [System.Collections.IDictionary]) {
            if ($Settings.ContainsKey($Key)) { return $Settings[$Key] }
            return $null
        }
        return $Settings.$Key
    }

    function Test-KeySetEqual {
        param([object]$Left, [object]$Right)
        $LeftKey  = @($Left  | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        $RightKey = @($Right | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        if ($LeftKey.Count -ne $RightKey.Count) { return $false }
        for ($Index = 0; $Index -lt $LeftKey.Count; $Index++) {
            if ($LeftKey[$Index] -ne $RightKey[$Index]) { return $false }
        }
        return $true
    }

    # -- descriptions -----------------------------------------------------------------------
    $DescriptionMap = @(
        @{ Decl = 'descriptionForAdmins';    Param = 'DescriptionForAdmins';    Cur = 'DescriptionForAdmins' }
        @{ Decl = 'descriptionForReviewers'; Param = 'DescriptionForReviewers'; Cur = 'DescriptionForReviewers' }
    )
    foreach ($Map in $DescriptionMap) {
        if (-not (Test-DeclHas $Declared $Map.Decl)) { continue }
        $DeclaredText = [string]$Declared.($Map.Decl)
        $CurrentText  = [string]$Current.($Map.Cur)
        if ($DeclaredText -ne $CurrentText) {
            $SetParams[$Map.Param] = $DeclaredText
            $Changes.Add("$($Map.Decl)=$DeclaredText")
        }
    }

    # -- settings booleans, duration and default decision -----------------------------------
    $SettingMap = @(
        @{ Decl = 'mailNotification';       Param = 'MailNotification';       Key = 'mailNotificationsEnabled';        Kind = 'Bool' }
        @{ Decl = 'reminderNotification';   Param = 'ReminderNotification';   Key = 'reminderNotificationsEnabled';    Kind = 'Bool' }
        @{ Decl = 'requireJustification';   Param = 'RequireJustification';   Key = 'justificationRequiredOnApproval'; Kind = 'Bool' }
        @{ Decl = 'recommendationsEnabled'; Param = 'RecommendationsEnabled'; Key = 'recommendationsEnabled';          Kind = 'Bool' }
        @{ Decl = 'autoApplyDecisions';     Param = 'AutoApplyDecisions';     Key = 'autoApplyDecisionsEnabled';       Kind = 'Bool' }
        @{ Decl = 'durationInDays';         Param = 'DurationInDays';         Key = 'instanceDurationInDays';          Kind = 'Int' }
        @{ Decl = 'defaultDecision';        Param = 'DefaultDecision';        Key = 'defaultDecision';                 Kind = 'String' }
    )
    foreach ($Map in $SettingMap) {
        if (-not (Test-DeclHas $Declared $Map.Decl)) { continue }
        $Raw = Get-SettingValue -Settings $Current.Settings -Key $Map.Key
        if ($Map.Kind -eq 'Bool') {
            $DeclaredValue = [bool]$Declared.($Map.Decl)
            $CurrentValue  = if ($null -ne $Raw) { [bool]$Raw } else { $null }
        }
        elseif ($Map.Kind -eq 'Int') {
            $DeclaredValue = [int]$Declared.($Map.Decl)
            $CurrentValue  = if ($null -ne $Raw) { [int]$Raw } else { $null }
        }
        else {
            $DeclaredValue = [string]$Declared.($Map.Decl)
            $CurrentValue  = if ($null -ne $Raw) { [string]$Raw } else { $null }
        }
        # A live definition that does not carry the setting at all cannot be proven equal, so send it.
        if ($null -eq $CurrentValue -or $DeclaredValue -ne $CurrentValue) {
            $SetParams[$Map.Param] = $DeclaredValue
            $Changes.Add("$($Map.Decl)=$DeclaredValue")
        }
    }

    # -- reviewers and fallback reviewers (one unit) ----------------------------------------
    if ($null -ne $DeclaredReviewer) {
        # Derive from the live reviewer scopes both the comparison keys AND the write-back values.
        # The values matter: Set-OERAccessReviewDefinition rebuilds BOTH arrays as soon as any reviewer
        # parameter is bound, so a half the document does not declare must be re-sent verbatim or it
        # would be wiped. The live object ids bind straight through (the principal resolvers return a
        # GUID unchanged), so no name lookup is needed to preserve them.
        #
        # Every query is parsed by Resolve-OERReviewerScopeQuery, the module's single owner of the
        # reviewer scope grammar. It is what tolerates the API version prefix Graph adds when it
        # NORMALIZES a scope on read: a scope this module writes as '/users/{id}' reads back as
        # '/v1.0/users/{id}'. With the older '^/users/' parse every live scope fell through unmatched,
        # the key list came out empty, and the block below then concluded the review was a SELF review
        # -- which on the write path replaces real named reviewers with the requestor.
        $CurrentManager          = $false
        $CurrentReviewerKey      = [System.Collections.Generic.List[string]]::new()
        $CurrentReviewerUser     = [System.Collections.Generic.List[string]]::new()
        $CurrentReviewerGroup    = [System.Collections.Generic.List[string]]::new()
        $CurrentReviewerUnparsed = [System.Collections.Generic.List[string]]::new()
        # Filtered: @($null).Count is 1, so an absent Reviewers property would otherwise iterate ONE
        # $null scope. That scope carries no query, would be classed unparsed, and would then make a
        # definition with no reviewers at all stop reading as a self review.
        foreach ($Scope in @($Current.Reviewers | Where-Object { $_ })) {
            $Parsed = Resolve-OERReviewerScopeQuery -Query ([string]$Scope.query)
            if ($Parsed.Kind -eq 'Manager') { $CurrentManager = $true; $CurrentReviewerKey.Add('manager'); continue }
            if ($Parsed.Kind -eq 'User') {
                $CurrentReviewerUser.Add([string]$Parsed.Id); $CurrentReviewerKey.Add([string]$Parsed.Id); continue
            }
            if ($Parsed.Kind -eq 'Group') {
                $CurrentReviewerGroup.Add([string]$Parsed.Id); $CurrentReviewerKey.Add([string]$Parsed.Id); continue
            }
            # Unparsed: a real live reviewer this module's vocabulary cannot express. Tracked in its
            # OWN list, never folded into the key list, so it can never be mistaken for an absent one.
            # A scope carrying no query at all names no reviewer, so it is dropped instead.
            if ($Parsed.Query) { $CurrentReviewerUnparsed.Add([string]$Parsed.Query) }
        }
        # An EMPTY reviewer collection is the documented self-review shape. A collection whose scopes
        # merely failed to PARSE is not: those are real reviewers, and calling that a self review is
        # what would write SelfReview back over them.
        #
        # Honest note on the second conjunct: it is defence in depth, not the working guard. The only
        # path that reads $CurrentSelfReview is the SEEDED (undeclared primary) branch below, and the
        # $Unseedable suppression in front of that branch already fires on exactly the same condition
        # -- an undeclared primary half with an unparsed scope -- so no test can currently tell the two
        # formulas apart. Keep it anyway: it states the intended meaning locally, and it is what makes
        # this line still correct if the suppression is ever narrowed to one half.
        $CurrentSelfReview = (($CurrentReviewerKey.Count -eq 0) -and ($CurrentReviewerUnparsed.Count -eq 0))
        if ($CurrentSelfReview) { $CurrentReviewerKey.Add('self') }

        $CurrentFallbackKey      = [System.Collections.Generic.List[string]]::new()
        $CurrentFallbackUser     = [System.Collections.Generic.List[string]]::new()
        $CurrentFallbackGroup    = [System.Collections.Generic.List[string]]::new()
        $CurrentFallbackUnparsed = [System.Collections.Generic.List[string]]::new()
        # Filtered for the same @($null).Count is 1 reason as the primary half above.
        foreach ($Scope in @($Current.FallbackReviewers | Where-Object { $_ })) {
            $Parsed = Resolve-OERReviewerScopeQuery -Query ([string]$Scope.query)
            if ($Parsed.Kind -eq 'User') {
                $CurrentFallbackUser.Add([string]$Parsed.Id); $CurrentFallbackKey.Add([string]$Parsed.Id); continue
            }
            if ($Parsed.Kind -eq 'Group') {
                $CurrentFallbackGroup.Add([string]$Parsed.Id); $CurrentFallbackKey.Add([string]$Parsed.Id); continue
            }
            # Any fallback scope carrying no object id is unexpressible HERE -- including a './manager'
            # scope, since Set-OERAccessReviewDefinition's fallback vocabulary is user and group only.
            # A scope carrying no query at all names no reviewer, so it is dropped instead.
            if ($Parsed.Query) { $CurrentFallbackUnparsed.Add([string]$Parsed.Query) }
        }

        # Each half is independently presence-gated. An absent flag means "declared", which keeps a
        # caller that supplies only the reviewer values on the previous both-halves-declared semantics.
        $DeclaresPrimary  = (-not (Test-DeclHas $DeclaredReviewer 'HasReviewers')) -or [bool]$DeclaredReviewer.HasReviewers
        $DeclaresFallback = (-not (Test-DeclHas $DeclaredReviewer 'HasFallbackReviewers')) -or [bool]$DeclaredReviewer.HasFallbackReviewers

        # An unparsed live scope means something different for a DECLARED half than for a SEEDED one.
        #
        # DECLARED half: the document is authoritative, and Set-OERAccessReviewDefinition rebuilds the
        # whole array anyway, so replacing the unparsed scope is what the operator asked for. What is no
        # longer possible is PROVING equality -- the parsed keys are only a subset of what is really
        # live -- so a key-set match must not be read as convergence. Force the change instead. The
        # write normalizes the definition to the module-emitted forms only, so the verification diff
        # Sync-OERStructureAccessReview runs after the PUT sees no unparsed scope and reports Unchanged;
        # this stays symmetric and does not turn a successful apply into a reported failure.
        #
        # SEEDED (undeclared) half: the live values are re-sent verbatim to preserve them, and an
        # unparsed scope cannot be re-sent -- sending only the parsed subset would silently delete a
        # reviewer the document never mentioned. Suppress the whole reviewer unit and report it, exactly
        # as the unrepresentable-recurrence case below does, rather than half-apply a destructive write.
        $PrimaryUnprovable  = $CurrentReviewerUnparsed.Count -gt 0
        $FallbackUnprovable = $CurrentFallbackUnparsed.Count -gt 0
        $Unseedable = [System.Collections.Generic.List[string]]::new()
        if ($PrimaryUnprovable -and -not $DeclaresPrimary) { foreach ($UnQuery in $CurrentReviewerUnparsed) { $Unseedable.Add($UnQuery) } }
        if ($FallbackUnprovable -and -not $DeclaresFallback) { foreach ($UnQuery in $CurrentFallbackUnparsed) { $Unseedable.Add($UnQuery) } }

        # Only a declared half can force the write; the seeded half rides along unchanged.
        $PrimaryChanged  = $DeclaresPrimary -and ($PrimaryUnprovable -or -not (Test-KeySetEqual $DeclaredReviewer.ReviewerKey $CurrentReviewerKey))
        $FallbackChanged = $DeclaresFallback -and ($FallbackUnprovable -or -not (Test-KeySetEqual $DeclaredReviewer.FallbackKey $CurrentFallbackKey))
        if (($PrimaryChanged -or $FallbackChanged) -and $Unseedable.Count -gt 0) {
            $NotApplied.Add(
                ("the live definition carries {0} reviewer scope(s) this module's vocabulary cannot express ({1}); " -f
                    $Unseedable.Count, ($Unseedable -join ', ')) +
                'a reviewer half the document does not declare has to be re-sent verbatim on a write, so the ' +
                'reviewer change was left unapplied rather than silently dropping them')
        }
        elseif ($PrimaryChanged -or $FallbackChanged) {
            $UseManager       = if ($DeclaresPrimary) { [bool]$DeclaredReviewer.Manager } else { $CurrentManager }
            $UseSelfReview    = if ($DeclaresPrimary) { [bool]$DeclaredReviewer.SelfReview } else { $CurrentSelfReview }
            $UseReviewer      = if ($DeclaresPrimary) { @($DeclaredReviewer.Reviewer) } else { @($CurrentReviewerUser) }
            $UseReviewerGroup = if ($DeclaresPrimary) { @($DeclaredReviewer.ReviewerGroup) } else { @($CurrentReviewerGroup) }
            $UseFallback      = if ($DeclaresFallback) { @($DeclaredReviewer.FallbackReviewer) } else { @($CurrentFallbackUser) }
            $UseFallbackGroup = if ($DeclaresFallback) { @($DeclaredReviewer.FallbackReviewerGroup) } else { @($CurrentFallbackGroup) }

            if ($UseManager) { $SetParams.Manager = $true }
            if ($UseSelfReview) { $SetParams.SelfReview = $true }
            if ($UseReviewer.Count -gt 0) { $SetParams.Reviewer = $UseReviewer }
            if ($UseReviewerGroup.Count -gt 0) { $SetParams.ReviewerGroup = $UseReviewerGroup }
            if ($UseFallback.Count -gt 0) { $SetParams.FallbackReviewer = $UseFallback }
            if ($UseFallbackGroup.Count -gt 0) { $SetParams.FallbackReviewerGroup = $UseFallbackGroup }

            $EffectivePrimaryKey  = if ($DeclaresPrimary) { @($DeclaredReviewer.ReviewerKey) } else { @($CurrentReviewerKey) }
            $EffectiveFallbackKey = if ($DeclaresFallback) { @($DeclaredReviewer.FallbackKey) } else { @($CurrentFallbackKey) }
            $Changes.Add("reviewers=[$($EffectivePrimaryKey -join ',')] fallbackReviewers=[$($EffectiveFallbackKey -join ',')]")

            # A declared half legitimately overwrites an unparseable live scope, but the operator cannot
            # see that from the resulting reviewer list alone -- name what is being replaced.
            $Replaced = [System.Collections.Generic.List[string]]::new()
            if ($DeclaresPrimary) { foreach ($UnQuery in $CurrentReviewerUnparsed) { $Replaced.Add($UnQuery) } }
            if ($DeclaresFallback) { foreach ($UnQuery in $CurrentFallbackUnparsed) { $Replaced.Add($UnQuery) } }
            if ($Replaced.Count -gt 0) {
                $Changes.Add("replacing $($Replaced.Count) live reviewer scope(s) this module's vocabulary cannot express ($($Replaced -join ', '))")
            }
        }
    }

    # -- recurrence, start date and range (one unit) ----------------------------------------
    $CurrentPattern = $null
    $CurrentRange   = $null
    if ($null -ne $Current.Recurrence) {
        $CurrentPattern = $Current.Recurrence.pattern
        $CurrentRange   = $Current.Recurrence.range
    }
    $CurrentCadence = 'OneTime'
    if ($CurrentPattern) {
        $PatternType = [string]$CurrentPattern.type
        $Interval    = [int]$CurrentPattern.interval
        $CurrentCadence = switch ($PatternType) {
            'weekly' { 'Weekly' }
            'absoluteMonthly' {
                switch ($Interval) {
                    1 { 'Monthly' }
                    3 { 'Quarterly' }
                    12 { 'Annually' }
                    default { 'Monthly' }
                }
            }
            default { 'OneTime' }
        }
    }

    # New-OERAccessReviewRecurrence can emit only weekly interval 1 and absoluteMonthly interval
    # 1/3/12, and both the inventory and the collapse above map every other interval onto one of those
    # names. Rebuilding the recurrence object from a collapsed cadence therefore REWRITES a live
    # semi-annual or n-weekly review -- silently, while reporting Updated. Track it and refuse.
    $CurrentPatternRepresentable = $true
    if ($CurrentPattern) {
        $CurrentPatternRepresentable = switch ([string]$CurrentPattern.type) {
            'weekly'          { [int]$CurrentPattern.interval -eq 1 }
            'absoluteMonthly' { [int]$CurrentPattern.interval -in 1, 3, 12 }
            default           { $false }
        }
    }
    $CurrentStart       = [string]$CurrentRange.startDate
    $CurrentEnd         = [string]$CurrentRange.endDate
    $CurrentOccurrences = $CurrentRange.numberOfOccurrences

    $HasRecurrence  = Test-DeclHas $Declared 'recurrence'
    $HasStartDate   = Test-DeclHas $Declared 'startDate'
    $HasEndDate     = Test-DeclHas $Declared 'endDate'
    $HasOccurrences = Test-DeclHas $Declared 'occurrences'
    if ($HasRecurrence -or $HasStartDate -or $HasEndDate -or $HasOccurrences) {
        $DeclaredCadence = if ($HasRecurrence) { [string]$Declared.recurrence } else { $CurrentCadence }
        $CadenceDiffers  = $DeclaredCadence -ine $CurrentCadence

        # A OneTime review carries no recurrence object at all (New-OERAccessReviewRecurrence returns
        # nothing for OneTime, and Set-OERAccessReviewDefinition then removes the settings.recurrence
        # key), so it has no range to diff. Comparing a declared startDate against a live range that
        # cannot exist would report drift on every run and PUT a no-op forever -- for an effective
        # OneTime cadence only the cadence itself is compared.
        $IsOneTime = $DeclaredCadence -ieq 'OneTime'

        $StartDiffers = $false
        if ($HasStartDate -and -not $IsOneTime) {
            $DeclaredStart = [datetime]$Declared.startDate
            $ParsedStart   = [datetime]::MinValue
            $StartDiffers  = -not ([datetime]::TryParse($CurrentStart, [ref]$ParsedStart)) -or ($DeclaredStart.Date -ne $ParsedStart.Date)
        }
        $EndDiffers = $false
        if ($HasEndDate -and -not $IsOneTime) {
            $DeclaredEnd = [datetime]$Declared.endDate
            $ParsedEnd   = [datetime]::MinValue
            $EndDiffers  = -not ([datetime]::TryParse($CurrentEnd, [ref]$ParsedEnd)) -or ($DeclaredEnd.Date -ne $ParsedEnd.Date)
        }
        $OccurrencesDiffer = $false
        if ($HasOccurrences -and -not $IsOneTime) {
            $OccurrencesDiffer = ($null -eq $CurrentOccurrences) -or ([int]$Declared.occurrences -ne [int]$CurrentOccurrences)
        }

        if ($CadenceDiffers -or $StartDiffers -or $EndDiffers -or $OccurrencesDiffer) {
            # -Recurrence and -StartDate must be supplied together, so fall back to the live start
            # date when the document omits one. With neither available the change cannot be written.
            $EffectiveStart = $null
            if ($HasStartDate) {
                $EffectiveStart = [datetime]$Declared.startDate
            }
            else {
                $ParsedCurrentStart = [datetime]::MinValue
                if ([datetime]::TryParse($CurrentStart, [ref]$ParsedCurrentStart)) { $EffectiveStart = $ParsedCurrentStart }
            }
            if ($null -eq $EffectiveStart) {
                $NotApplied.Add("recurrence change to '$DeclaredCadence' needs a startDate; declare 'startDate' to apply it")
            }
            elseif (-not $CurrentPatternRepresentable) {
                # Rebuilding the recurrence object here would send the emitter's coarser cadence in
                # place of a live pattern it cannot reproduce (e.g. absoluteMonthly interval 6, or a
                # weekly interval other than 1) -- silently downgrading a semi-annual or n-weekly review
                # while reporting Updated. Suppress the whole unit (Recurrence, StartDate, EndDate,
                # Occurrences) rather than send a range without the pattern it belongs to.
                $NotApplied.Add(
                    ("the live recurrence pattern ({0} interval {1}) cannot be expressed by the module's cadence vocabulary; " -f
                        [string]$CurrentPattern.type, [int]$CurrentPattern.interval) +
                    'the recurrence and start date were left untouched so it is not rewritten to a coarser cadence')
            }
            else {
                $SetParams.Recurrence = $DeclaredCadence
                $SetParams.StartDate = $EffectiveStart
                # A OneTime write drops the recurrence object entirely, so a range is meaningless there.
                if (-not $IsOneTime) {
                    if ($HasEndDate) { $SetParams.EndDate = [datetime]$Declared.endDate }
                    elseif ($HasOccurrences) { $SetParams.Occurrences = [int]$Declared.occurrences }
                    else {
                        # The range half the document does not declare must be carried forward from the
                        # live definition: Set-OERAccessReviewDefinition rebuilds the WHOLE recurrence
                        # object and New-OERAccessReviewRecurrence defaults the range to noEnd, so a live
                        # endDate or numbered range would be destroyed by a write that only changed the
                        # cadence or the start date. The two range kinds are mutually exclusive, so at
                        # most one is ever seeded.
                        $CurrentRangeType = [string]$CurrentRange.type
                        if ($CurrentRangeType -ieq 'endDate') {
                            $SeededEnd = [datetime]::MinValue
                            if ([datetime]::TryParse($CurrentEnd, [ref]$SeededEnd)) { $SetParams.EndDate = $SeededEnd }
                        }
                        elseif ($CurrentRangeType -ieq 'numbered' -and $null -ne $CurrentOccurrences) {
                            $SetParams.Occurrences = [int]$CurrentOccurrences
                        }
                    }
                }
                $Changes.Add("recurrence=$DeclaredCadence startDate=$($EffectiveStart.ToString('yyyy-MM-dd'))")
            }
        }
    }

    # -- immutable scope --------------------------------------------------------------------
    # The document carries display names, the live definition carries ids. Only a GUID-shaped declared
    # value can be compared offline; a display name is left alone rather than reported as false drift.
    $ScopeMap = @(
        @{ Decl = 'accessPackage';    Cur = 'AccessPackageId' }
        @{ Decl = 'assignmentPolicy'; Cur = 'AssignmentPolicyId' }
    )
    foreach ($Map in $ScopeMap) {
        if (-not (Test-DeclHas $Declared $Map.Decl)) { continue }
        $DeclaredScope = [string]$Declared.($Map.Decl)
        $CurrentScope  = [string]$Current.($Map.Cur)
        if ((Test-OERGuid -Value $DeclaredScope) -and $DeclaredScope -ine $CurrentScope) {
            $NotApplied.Add("$($Map.Decl) '$DeclaredScope' differs from the live scope '$CurrentScope'; the review scope is immutable and was not changed")
        }
    }

    $Out = [PSCustomObject]@{
        Changed    = ($SetParams.Keys.Count -gt 0)
        SetParams  = $SetParams
        Changes    = $Changes.ToArray()
        NotApplied = $NotApplied.ToArray()
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewChange')
    $Out
}
