function Sync-OERStructureAccessReview {
    <#
    .SYNOPSIS
    Reconciles one accessReviews[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single access review entry from the structure document. It is
    called by the Invoke-OERStructure engine and emits one ConvertTo-OERStructureResult record
    describing what was created, skipped, or left unchanged.

    Create-or-update:
    A definition is matched by displayName. When it does not exist it is created. When it does exist,
    the declared fields are diffed against the live definition by the pure helper
    Resolve-OERAccessReviewChange and only the differences are sent to Set-OERAccessReviewDefinition
    (a read-modify-write PUT, so undeclared properties are preserved). Reviewer tokens are resolved to
    object ids before the diff, so a display-name change in the tenant is not mistaken for drift.
    Renaming a review through the document is not possible -- displayName is the match key.
    The update is a FULL-OBJECT PUT: Set-OERAccessReviewDefinition carries the live values of every
    writable top-level property forward by name (including instanceEnumerationScope and
    additionalNotificationRecipients, neither of which the document models). A writable property added
    to the Microsoft Graph accessReviewScheduleDefinition resource in future and not yet on that
    carry-forward list would still be cleared by the PUT -- see Set-OERAccessReviewDefinition.
    The review SCOPE (accessPackage, assignmentPolicy) is immutable on an existing definition: a
    declared scope that differs from the live one is reported as a Skipped record with a warning
    rather than a misleading Unchanged. There are no child collections to reconcile, so -Prune is
    accepted for a uniform Sync-OERStructure* signature but is a no-op in this handler.

    Microsoft Graph limits which updates it accepts (reviewers are updatable only when individual
    users are assigned, and a multi-stage review is updatable only through stageSettings). A rejected
    update surfaces Graph's own message on a Failed record.

    Every update is VERIFIED before it is reported as Updated. The PUT answers 204 No Content, which
    says the request was accepted, not that the value was stored: Graph documents that a definition
    update applies to future instances only, so a definition with no future instance left can accept a
    write and still read back unchanged. Set-OERAccessReviewDefinition already re-reads the definition
    after the PUT and returns it, so the handler re-runs the same pure diff against that returned
    definition at no extra Graph cost. Only a definition that actually carries the declared state is
    reported Updated; one that still differs is reported Failed, naming the fields that did not take
    effect and the live definition status, and a matching warning is written. This is what stops the
    engine reporting a permanent, self-repeating false Updated on a review Graph will not modify.

    Reviewer mapping from the document reviewers[] array:
    - The string 'manager' (case-insensitive) adds -Manager to the creation call.
    - The string 'self' (case-insensitive) adds -SelfReview to the creation call.
    - Entries containing '@' are treated as UPNs and collected into -Reviewer.
    - All other entries (plain names / GUIDs without '@') are collected into -ReviewerGroup.
    - When reviewers is ABSENT -- or present with an explicit null, which counts as absent -- -Manager
      is used as a safe default. A DECLARED but EMPTY reviewers array is NOT the same thing: it adds
      -SelfReview, the same meaning the update path gives it.
    - When reviewers declares 'self' together with 'manager' or a named reviewer, 'self' is dropped
      (with a Write-Warning naming the affected review) and only the named/manager reviewers are
      forwarded, on both the create and the update path. New-/Set-OERAccessReviewDefinition refuse
      -SelfReview combined with -Reviewer/-ReviewerGroup/-Manager as a non-terminating
      MutuallyExclusiveReviewer error, but Microsoft Graph's own resolution has always silently
      preferred the named/manager reviewers for that combination -- so an existing apply-document that
      declares both keeps working with the same effective outcome instead of newly reporting Failed.

    Fallback reviewer mapping from the optional fallbackReviewers[] array:
    - Entries containing '@' are treated as UPNs and collected into -FallbackReviewer.
    - All other entries (group display names / GUIDs) are collected into -FallbackReviewerGroup.
    A manager reviewer (declared, or the default) REQUIRES a fallback reviewer; when manager is used
    and no fallbackReviewers are declared, the entry is reported Failed (a manager review with no
    fallback is rejected by Graph as "Policy is invalid due to invalid criteria").
    On the update path the same mapping applies, except that the reviewer tokens are first resolved to
    object ids (via Resolve-OERStructurePrincipal) so the diff compares ids rather than display names,
    and a token that cannot be resolved reports Failed without writing. A reviewers or fallbackReviewers
    key present with an explicit null counts as UNDECLARED on BOTH paths (the same rule the schema
    validator and the pure diffs apply), so on the update path the live reviewers on that half are left
    exactly as they are; an explicitly empty list is a declared self review on both paths.

    Recurrence mapping (case-insensitive):
    The document recurrence value is mapped to the ValidateSet values accepted by
    New-OERAccessReviewDefinition: OneTime, Weekly, Monthly, Quarterly, Annually.
    An unrecognised recurrence value emits a Failed record without calling the cmdlet.

    Recurrence range and review settings:
    - endDate (an end-date range) or occurrences (a numbered range) -- at most one; if a hand-built
      item somehow carries both, endDate wins. Both are inert on a OneTime review because it carries
      no recurrence object.
    - mailNotification, reminderNotification, requireJustification, recommendationsEnabled and
      autoApplyDecisions map to the matching New-OERAccessReviewDefinition switches and are bound only
      when the document declares them true, so an omitted field keeps the cmdlet default.
    - defaultDecision maps to -DefaultDecision (None | Approve | Deny | Recommendation).

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf ShouldProcess returns $false and
    a Skipped record is emitted instead of calling New-OERAccessReviewDefinition.

    .PARAMETER Item
    One element from the accessReviews[] array in the structure document, as a PSCustomObject
    produced by ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    Accepted for a uniform Sync-OERStructure* handler signature. Access review definitions have no
    child collections, so this switch is a no-op in v1. It is not used by this handler.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Not used by this handler but accepted for
    a uniform Sync-OERStructure* signature.

    .EXAMPLE
    Sync-OERStructureAccessReview -Item $DocItem -Caller $PSCmdlet -TenantAlias 'omnicit'
    Reconciles one access review entry from the document using the engine PSCmdlet as the caller.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'TenantAlias is part of the uniform Sync-OERStructure* handler signature; accepted for future use and caller consistency even though this handler does not resolve tenant defaults.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Prune',
        Justification = 'Prune is part of the uniform Sync-OERStructure* handler signature; access review definitions have no child collections so this switch is a no-op in v1.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias
    )
    process {
        # -- Resolve the display name -----------------------------------------------------------
        $Name = $Item.displayName

        # -- Map recurrence --------------------------------------------------------------------
        # Validated BEFORE the existence check so both the create and the update branch see a
        # cadence in the exact ValidateSet spelling, and an unrecognised value costs no Graph call.
        $RecurrenceInput = if (Test-OERDeclaredProperty -Node $Item -Name 'recurrence') { $Item.recurrence } else { 'OneTime' }
        $ValidRecurrenceValues = @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')
        $MappedRecurrence = $ValidRecurrenceValues | Where-Object { $_ -ieq $RecurrenceInput } | Select-Object -First 1
        if (-not $MappedRecurrence) {
            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                -Detail "unrecognised recurrence value '$RecurrenceInput'; expected OneTime, Weekly, Monthly, Quarterly, or Annually"
            return
        }
        # Normalize the declared cadence to the exact ValidateSet spelling before either branch runs,
        # so the update diff compares the same vocabulary the create path writes. The normalization
        # lands on a shallow COPY: the engine's parsed document is shared state and no other
        # Sync-OERStructure* handler writes back into it.
        $DeclaredItem = $Item
        if (Test-OERDeclaredProperty -Node $Item -Name 'recurrence') {
            $DeclaredItem = $Item.PSObject.Copy()
            $DeclaredItem.recurrence = $MappedRecurrence
        }

        # -- Check existence (throttle-tolerant) -----------------------------------------------
        # -ErrorAction SilentlyContinue with a LOCAL -ErrorVariable, not -ErrorAction Stop, and no
        # @( ) wrapper around the call. Get-OERAccessReviewDefinition reports "nothing matched" by
        # WRITING a non-terminating AccessReviewDefinitionNotFound record, and $PSCmdlet.WriteError()
        # deposits that record into every -ErrorVariable/$Error collector already listening on the
        # call stack the instant it runs -- before, and independently of, whatever -ErrorAction does
        # next. A catch further up can stop the resulting exception from becoming a hard stop; it can
        # never retract a deposit already made. So the old shape reported a perfectly successful
        # Created while leaving AccessReviewDefinitionNotFound records in the operator's own $Error
        # and -ErrorVariable: measured TWO per create on a live run, and EIGHTEEN on a genuine
        # throttle failure. The @( ) was the other half of that doubling -- it ran the failing call
        # as its own nested pipeline, which re-deposited the same record on the way out -- so
        # dropping either one alone only halves the leak.
        # SilentlyContinue here means "captured", not "ignored": the records are inspected below, so
        # a failed read is still a failed read. Same idiom, same reasoning, as the group and
        # administrative-unit reads in Get-OERInventory.
        $Existing = $null
        $Filter = "displayName eq '{0}'" -f $Name.Replace("'", "''")
        $ProbeErrors = $null
        # The try/catch still guards a genuinely TERMINATING failure of the read (auth, a dead
        # transport, a ThrowTerminatingError upstream); the inspection inside it handles the
        # NON-terminating records. Both are needed: neither subsumes the other.
        try {
            $Existing = Get-OERAccessReviewDefinition -Filter $Filter -ErrorAction SilentlyContinue -ErrorVariable ProbeErrors |
                Where-Object { $_.DisplayName -eq $Name } |
                Select-Object -First 1
            if (-not $Existing) {
                # A failed read is NOT an empty fact. AccessReviewDefinitionNotFound means the
                # definition genuinely does not exist yet -- proceed with the create. Anything else
                # (throttle, permission, transport) means the read never answered, and creating on
                # that would duplicate a review that is already there.
                #
                # Only a record Get-OERAccessReviewDefinition itself PUBLISHED counts, and the
                # publisher test is load-bearing, not decoration. -ErrorVariable is filled by the
                # ENGINE and also collects records raised inside NESTED calls even when an inner
                # catch swallowed them -- and Invoke-OERGraphRequest swallows and retries a 429, a
                # 503 with Retry-After, and an ACRS claims challenge. Measured on that exact shape: a
                # throttled attempt that was retried and then SUCCEEDED with zero matches left three
                # TooManyRequests records plus one bare, message-less RuntimeException in this local
                # collection beside the genuine NotFound. Treating any non-NotFound record as a read
                # failure would therefore report Failed and refuse to create against a tenant that
                # answered perfectly well. A published record carries the calling cmdlet's name as a
                # comma-separated segment of the FullyQualifiedErrorId; a stray does not. Membership,
                # not a suffix match: Write-Error appends a further name when a record is
                # republished, so the cmdlet's name is not always the last segment. This is the same
                # discriminator, found the same way, as the 49 foreign records Get-OERInventory's
                # administrative-unit read had to filter out.
                $ProbeFailure = @($ProbeErrors | Where-Object {
                        $null -ne $_ -and
                        $_.FullyQualifiedErrorId -notlike 'AccessReviewDefinitionNotFound*' -and
                        @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Get-OERAccessReviewDefinition'
                    }) | Select-Object -First 1
                if ($ProbeFailure) {
                    # No Remove-OERErrorRecord here: this record was WRITTEN deliberately by
                    # Get-OERAccessReviewDefinition, whose own catch already ran the scrub on the
                    # shared request object behind it, so the bearer token is already gone from every
                    # copy. Running the scrub again would only strip the record from $global:Error --
                    # hiding the very diagnostic this branch exists to report.
                    $Caller.WriteError($ProbeFailure)
                    ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                        -Detail "could not read access review definitions: $($ProbeFailure.Exception.Message)" `
                        -ErrorRecord $ProbeFailure
                    return
                }
            }
        }
        catch {
            Remove-OERErrorRecord -Record $PSItem
            # Distinguish a clean NotFound (definition simply does not exist yet) from a real
            # error (throttle, auth failure, etc.). NotFound means proceed with create.
            if ($PSItem.FullyQualifiedErrorId -like 'AccessReviewDefinitionNotFound*') {
                $Existing = $null
            }
            else {
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                    -Detail "could not read access review definitions: $($PSItem.Exception.Message)" `
                    -ErrorRecord $PSItem
                return
            }
        }

        # -- Existing -> reconcile ---------------------------------------------------------------
        if ($Existing) {
            # Resolve the declared reviewer tokens to object ids so the diff compares ids, not names.
            # This is the only Graph work the update path does; the diff itself is pure.
            $DeclaredReviewer = $null
            # Test-OERDeclaredProperty is the single owner of the declared rule -- the same predicate
            # Test-HasProp wraps in Test-OERStructureSchema and Test-DeclHas wraps in the pure diffs.
            # An explicit JSON null therefore means exactly what OMITTING the key means. Without that
            # null guard, "reviewers": null counted as declared, resolved to an empty list, and then hit
            # the empty-list-means-self-review branch below -- silently rewriting a review with named
            # reviewers into a SELF review and, because Set-OERAccessReviewDefinition rebuilds BOTH
            # reviewer arrays whenever any reviewer parameter binds, wiping its fallback reviewers.
            # An explicitly EMPTY list stays declared: it is an intentional statement (a self review).
            # Do not fold this back into an inline -contains plus a null check.
            $DeclaresPrimary  = Test-OERDeclaredProperty -Node $Item -Name 'reviewers'
            $DeclaresFallback = Test-OERDeclaredProperty -Node $Item -Name 'fallbackReviewers'
            if ($DeclaresPrimary -or $DeclaresFallback) {
                $UpdManager     = $false
                $UpdSelf        = $false
                $UpdUser        = [System.Collections.Generic.List[string]]::new()
                $UpdGroup       = [System.Collections.Generic.List[string]]::new()
                $UpdFbUser      = [System.Collections.Generic.List[string]]::new()
                $UpdFbGroup     = [System.Collections.Generic.List[string]]::new()
                $UpdKey         = [System.Collections.Generic.List[string]]::new()
                $UpdFallbackKey = [System.Collections.Generic.List[string]]::new()
                $ResolveFailed  = $null

                # Filtered so an absent or sparse array does not surface a $null entry -- @($null)
                # has Count 1, and an empty reference would fail Resolve-OERStructurePrincipal binding.
                foreach ($Entry in @($Item.reviewers | Where-Object { $_ })) {
                    if ($Entry -ieq 'manager') { $UpdManager = $true; $UpdKey.Add('manager'); continue }
                    if ($Entry -ieq 'self') { $UpdSelf = $true; $UpdKey.Add('self'); continue }
                    $EntryType = if ($Entry -like '*@*') { 'User' } else { 'Group' }
                    $EntryId = Resolve-OERStructurePrincipal -Reference ([string]$Entry) -Type $EntryType
                    if (-not $EntryId) { $ResolveFailed = [string]$Entry; break }
                    if ($EntryType -eq 'User') { $UpdUser.Add([string]$Entry) } else { $UpdGroup.Add([string]$Entry) }
                    $UpdKey.Add($EntryId)
                }
                if (-not $ResolveFailed) {
                    foreach ($Fb in @($Item.fallbackReviewers | Where-Object { $_ })) {
                        $FbType = if ($Fb -like '*@*') { 'User' } else { 'Group' }
                        $FbId = Resolve-OERStructurePrincipal -Reference ([string]$Fb) -Type $FbType
                        if (-not $FbId) { $ResolveFailed = [string]$Fb; break }
                        if ($FbType -eq 'User') { $UpdFbUser.Add([string]$Fb) } else { $UpdFbGroup.Add([string]$Fb) }
                        $UpdFallbackKey.Add($FbId)
                    }
                }
                if ($ResolveFailed) {
                    ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                        -Detail "could not resolve reviewer '$ResolveFailed' to an object id"
                    return
                }

                # Same mix as the create path above, on the update side: a declared 'manager'/named
                # reviewer together with 'self' is accepted today and silently resolves to the
                # named/manager reviewers (Set-OERAccessReviewDefinition's Task 4c guard now refuses
                # -Manager/-Reviewer/-ReviewerGroup combined with -SelfReview outright). Drop the
                # explicit 'self' token from BOTH $UpdSelf and $UpdKey before the diff runs, so the
                # subsequent auto-self branch (an ABSENT or genuinely EMPTY declared set) is not
                # affected, and the update forwards only the named/manager reviewers with a warning.
                if ($UpdSelf -and ($UpdManager -or $UpdUser.Count -gt 0 -or $UpdGroup.Count -gt 0)) {
                    Write-Warning ("Sync-OERStructureAccessReview: access review '$Name' -- reviewers[] declares " +
                        "'self' together with a named or manager reviewer; Microsoft Graph's own resolution " +
                        "silently prefers the named/manager reviewers, so 'self' is dropped to match that " +
                        'outcome. Declare only one reviewer mode.')
                    $UpdSelf = $false
                    # Round-1 review finding M-5: List<T>.Remove() drops only the FIRST match. A
                    # document declaring "reviewers": ["self","self","manager"] (a duplicate token,
                    # however unlikely) would leave a stale 'self' entry in $UpdKey after a single
                    # Remove() call, and that entry feeds straight into the diff -- the document could
                    # then never converge. Loop until every 'self' entry is gone.
                    while ($UpdKey.Remove('self')) { }
                }

                # A DECLARED but empty reviewer list means the same thing on both sides: a self review.
                # An ABSENT list means "leave the live reviewers alone" -- the diff seeds that half
                # from the live definition instead, so it is never rewritten as a self review.
                if ($DeclaresPrimary -and $UpdKey.Count -eq 0) { $UpdSelf = $true; $UpdKey.Add('self') }

                $DeclaredReviewer = [PSCustomObject]@{
                    HasReviewers          = $DeclaresPrimary
                    HasFallbackReviewers  = $DeclaresFallback
                    Manager               = $UpdManager
                    SelfReview            = $UpdSelf
                    Reviewer              = $UpdUser.ToArray()
                    ReviewerGroup         = $UpdGroup.ToArray()
                    FallbackReviewer      = $UpdFbUser.ToArray()
                    FallbackReviewerGroup = $UpdFbGroup.ToArray()
                    ReviewerKey           = $UpdKey.ToArray()
                    FallbackKey           = $UpdFallbackKey.ToArray()
                }
            }

            $ChangeParams = @{ Declared = $DeclaredItem; Current = $Existing }
            if ($DeclaredReviewer) { $ChangeParams.DeclaredReviewer = $DeclaredReviewer }
            $Change = Resolve-OERAccessReviewChange @ChangeParams

            # Surface every declared drift the engine cannot write, so the operator is never told
            # Unchanged about a divergence that is really unappliable.
            foreach ($Note in @($Change.NotApplied)) {
                Write-Warning "Sync-OERStructureAccessReview: access review '$Name' -- $Note."
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Skipped' `
                    -Detail $Note
            }

            if (-not $Change.Changed) {
                # Only claim a match when there is nothing unappliable to report -- a Skipped record
                # saying the scope diverges plus an Unchanged saying it already matches would contradict
                # each other, so the Skipped record stands alone.
                if (@($Change.NotApplied).Count -eq 0) {
                    ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Unchanged' `
                        -Detail "access review '$Name' already matches"
                }
                return
            }

            if (-not $Caller.ShouldProcess($Name, 'Update access review definition')) {
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Skipped' `
                    -Detail "would update access review '$Name' ($($Change.Changes -join ', '))"
                return
            }

            # The write and the verification below are deliberately separate steps: only a transport or
            # Graph failure belongs in this catch, so a definition that comes back UNCHANGED is reported
            # as its own outcome instead of being dressed up as an exception.
            $AfterWrite = $null
            try {
                $SetSplat = $Change.SetParams
                $AfterWrite = @(Set-OERAccessReviewDefinition -Id $Existing.Id @SetSplat -Confirm:$false -ErrorAction Stop) |
                    Select-Object -First 1
            }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                    -Detail "access review update failed: $($PSItem.Exception.Message)" `
                    -ErrorRecord $PSItem
                return
            }

            # Graph answers this PUT with 204 No Content, which is NOT a promise that the change was
            # stored. Learn states that updates to an accessReviewScheduleDefinition "only apply to
            # future instances", so a definition with no future instance left can accept the write and
            # still read back unchanged. Claiming Updated purely because no exception was thrown was
            # therefore a false success AND a non-convergence -- the same document reported Updated on
            # every run, forever, while the tenant never moved. Set-OERAccessReviewDefinition already
            # re-GETs the definition after the PUT and returns it, so proving the write landed costs no
            # extra Graph call: re-run the SAME pure diff against what came back and only claim Updated
            # when the declared state is genuinely there. This guards every declared field at once, not
            # just the one that exposed the bug.
            if ($null -eq $AfterWrite) {
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                    -Detail ("access review update to '$Name' ($($Change.Changes -join ', ')) could not be confirmed: " +
                        'Set-OERAccessReviewDefinition returned no definition to verify against')
                return
            }

            $VerifyParams = @{ Declared = $DeclaredItem; Current = $AfterWrite }
            if ($DeclaredReviewer) { $VerifyParams.DeclaredReviewer = $DeclaredReviewer }
            $Verify = Resolve-OERAccessReviewChange @VerifyParams
            if ($Verify.Changed) {
                # Deliberately NOT phrased as "Graph rejected the update": the read-back is the only
                # fact in evidence. The live status is surfaced because it is the leading explanation,
                # not because a status-to-writability rule has been established anywhere.
                $LiveStatus = if ($AfterWrite.Status) { [string]$AfterWrite.Status }
                elseif ($Existing.Status) { [string]$Existing.Status }
                else { 'unknown' }
                Write-Warning ("Sync-OERStructureAccessReview: access review '$Name' -- Microsoft Graph accepted the " +
                    "update but the definition read back still differs ($($Verify.Changes -join ', ')). The definition " +
                    "status is '$LiveStatus'. Graph documents that a definition update applies to FUTURE instances " +
                    'only, so a review with no future instance left may accept a write without storing it.')
                ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                    -Detail ('access review update not confirmed: Microsoft Graph accepted the write but the definition ' +
                        "read back still differs ($($Verify.Changes -join ', ')); definition status is '$LiveStatus'")
                return
            }

            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Updated' `
                -Detail "updated access review '$Name' ($($Change.Changes -join ', '))"
            return
        }

        # -- Gate the create via ShouldProcess -------------------------------------------------
        if (-not $Caller.ShouldProcess($Name, 'Create access review definition')) {
            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Skipped' `
                -Detail "would create access review '$Name'"
            return
        }

        # -- Build creation params -------------------------------------------------------------
        # Test-OERDeclaredProperty is the single owner of the declared rule used throughout this
        # block -- an explicit JSON null means exactly what an omitted key means, so every read below
        # that chooses between a declared value and a document/cmdlet default routes through it
        # instead of an inline -contains plus a null check. See
        # docs/development/rationale.md#declared-property.
        $NewParams = @{
            DisplayName             = $Name
            DescriptionForAdmins    = if (Test-OERDeclaredProperty -Node $Item -Name 'descriptionForAdmins') {
                $Item.descriptionForAdmins
            } else {
                "Access review for $Name"
            }
            DescriptionForReviewers = if (Test-OERDeclaredProperty -Node $Item -Name 'descriptionForReviewers') {
                $Item.descriptionForReviewers
            } else {
                "Please review access for $Name"
            }
            AccessPackage           = $Item.accessPackage
            AssignmentPolicy        = $Item.assignmentPolicy
            Recurrence              = $MappedRecurrence
            StartDate               = if (Test-OERDeclaredProperty -Node $Item -Name 'startDate') {
                [datetime]$Item.startDate
            } else {
                (Get-Date)
            }
            Confirm                 = $false
        }

        if (Test-OERDeclaredProperty -Node $Item -Name 'durationInDays') {
            $NewParams.DurationInDays = $Item.durationInDays
        }

        # Recurrence range: New-OERAccessReviewRecurrence encodes EITHER an endDate range or a numbered
        # range and throws when both are supplied, so pass at most one. Test-OERStructureSchema already
        # rejects a document that declares both; this guard keeps a hand-built item from throwing.
        if (Test-OERDeclaredProperty -Node $Item -Name 'endDate') {
            $NewParams.EndDate = [datetime]$Item.endDate
        }
        elseif (Test-OERDeclaredProperty -Node $Item -Name 'occurrences') {
            $NewParams.Occurrences = [int]$Item.occurrences
        }

        # Review settings. Each is a switch on New-OERAccessReviewDefinition, so bind it only when the
        # document declares it -- an omitted field must keep the cmdlet default, not become $false.
        $SettingSwitchMap = @{
            mailNotification       = 'MailNotification'
            reminderNotification   = 'ReminderNotification'
            requireJustification   = 'RequireJustification'
            recommendationsEnabled = 'RecommendationsEnabled'
            autoApplyDecisions     = 'AutoApplyDecisions'
        }
        foreach ($DocKey in $SettingSwitchMap.Keys) {
            # [bool]$null is $false, so this truthiness clause already behaved identically to a
            # declared-null guard before this migration -- swapped for uniformity with the rest of
            # this block, not because the behaviour changes.
            if ((Test-OERDeclaredProperty -Node $Item -Name $DocKey) -and ([bool]$Item.$DocKey)) {
                $NewParams[$SettingSwitchMap[$DocKey]] = $true
            }
        }
        if (Test-OERDeclaredProperty -Node $Item -Name 'defaultDecision') {
            $NewParams.DefaultDecision = [string]$Item.defaultDecision
        }

        # -- Map reviewers ---------------------------------------------------------------------
        $ReviewerList   = [System.Collections.Generic.List[string]]::new()
        $ReviewerGroups = [System.Collections.Generic.List[string]]::new()
        $AddManager     = $false
        $AddSelfReview  = $false

        # A DECLARED but empty reviewer list is a self review on the create path too -- the same
        # contract the update path states above: "A DECLARED but empty reviewer list means the same
        # thing on both sides: a self review. An ABSENT list means 'leave the live reviewers alone'."
        # The create path used to contradict that. Its old gate tested the raw value for truthiness,
        # and [bool]@() is $false in PowerShell, so a declared "reviewers": [] short-circuited before
        # the Count test and fell into the OMITTED-key manager default; the manager-requires-fallback
        # guard below then reported Failed without ever creating the definition, so the document
        # repeated that Failed on every run forever (the issue #56 non-convergence class).
        # Test-OERDeclaredProperty is the single owner of the declared rule -- an explicit null counts
        # as absent, an empty array stays declared. Do not fold this back into an inline -contains
        # plus truthiness test.
        $DeclaresReviewers = Test-OERDeclaredProperty -Node $Item -Name 'reviewers'
        $HasReviewers      = $DeclaresReviewers -and @($Item.reviewers).Count -gt 0
        if ($HasReviewers) {
            foreach ($Entry in @($Item.reviewers)) {
                if ($Entry -ieq 'manager') {
                    $AddManager = $true
                }
                elseif ($Entry -ieq 'self') {
                    $AddSelfReview = $true
                }
                elseif ($Entry -like '*@*') {
                    $ReviewerList.Add($Entry)
                }
                else {
                    $ReviewerGroups.Add($Entry)
                }
            }
        }
        elseif ($DeclaresReviewers) {
            # Declared but EMPTY: an intentional statement that this is a self review. Neither the
            # self/manager-mix warning nor the manager-requires-fallback guard below can fire from
            # here, because no manager and no named reviewer was collected.
            $AddSelfReview = $true
        }
        else {
            # ABSENT, or an explicit null (which counts as absent): manager is a safe fallback when
            # no reviewers are declared.
            $AddManager = $true
        }

        # A document declaring both 'manager'/named reviewers and 'self' is accepted today: Graph's
        # own Resolve-OERReviewerScope silently ignores -SelfReview whenever -Manager/-Reviewer/
        # -ReviewerGroup also resolve to a non-empty scope, so the effective outcome has always been
        # the named/manager reviewers with 'self' dropped. New-OERAccessReviewDefinition's Task 4c
        # guard now REFUSES that combination outright (MutuallyExclusiveReviewer) -- forwarding both
        # switches unchanged would turn an accepted document into a Failed record. Detect the mix here
        # instead, warn, and forward only the named/manager reviewers so the effective outcome (and an
        # existing apply-document's success) is unchanged.
        if ($AddSelfReview -and ($AddManager -or $ReviewerList.Count -gt 0 -or $ReviewerGroups.Count -gt 0)) {
            Write-Warning ("Sync-OERStructureAccessReview: access review '$Name' -- reviewers[] declares " +
                "'self' together with a named or manager reviewer; Microsoft Graph's own resolution " +
                "silently prefers the named/manager reviewers, so 'self' is dropped to match that outcome. " +
                'Declare only one reviewer mode.')
            $AddSelfReview = $false
        }

        if ($AddManager)    { $NewParams.Manager    = $true }
        if ($AddSelfReview) { $NewParams.SelfReview = $true }
        if ($ReviewerList.Count   -gt 0) { $NewParams.Reviewer      = @($ReviewerList) }
        if ($ReviewerGroups.Count -gt 0) { $NewParams.ReviewerGroup = @($ReviewerGroups) }

        # -- Map fallback reviewers (UPN -> user; anything else -> group). A manager reviewer requires
        # a fallback, so the document carries it for round-trip fidelity. ---------------------
        $FallbackUsers  = [System.Collections.Generic.List[string]]::new()
        $FallbackGroups = [System.Collections.Generic.List[string]]::new()
        # Already behaviour-identical (see the SettingSwitchMap loop note above): migrated for
        # uniformity only. Do NOT touch the truthiness clause -- an explicitly empty fallbackReviewers
        # stays a no-op here, the shape PR #66 settled.
        if ((Test-OERDeclaredProperty -Node $Item -Name 'fallbackReviewers') -and $Item.fallbackReviewers) {
            foreach ($Fb in @($Item.fallbackReviewers)) {
                if ($Fb -like '*@*') { $FallbackUsers.Add($Fb) } else { $FallbackGroups.Add($Fb) }
            }
        }
        if ($FallbackUsers.Count  -gt 0) { $NewParams.FallbackReviewer      = @($FallbackUsers) }
        if ($FallbackGroups.Count -gt 0) { $NewParams.FallbackReviewerGroup = @($FallbackGroups) }

        # A manager reviewer (declared, or the default when no reviewers are given) requires a fallback.
        # Fail clearly here instead of letting the create surface Graph's cryptic
        # "Policy is invalid due to invalid criteria".
        if ($AddManager -and (($FallbackUsers.Count + $FallbackGroups.Count) -eq 0)) {
            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                -Detail "manager reviewer requires fallbackReviewers; declare a fallbackReviewers user or group for '$Name'"
            return
        }

        # -- Create ----------------------------------------------------------------------------
        try {
            $null = New-OERAccessReviewDefinition @NewParams -ErrorAction Stop
            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Created' `
                -Detail "created access review '$Name' (recurrence: $MappedRecurrence)"
        }
        catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section 'accessReviews' -Item $Name -Action 'Failed' `
                -Detail "access review creation failed: $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
        }
    }
}
