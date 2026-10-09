function Sync-OERStructureGroup {
    <#
    .SYNOPSIS
    Reconciles one groups[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single group entry from the structure document. It is called by
    the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult records
    describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key: an existing group is matched and updated by it. To rename a group,
    the document declares its new name as displayName and its current name as previousDisplayName,
    and both names are resolved on every run before anything is read or written:
    - Both resolve to DIFFERENT groups: the item emits exactly one Failed row and a non-terminating
      GroupRenameConflict error (category ResourceExists, target the new name), and nothing else is
      read or written for it -- the document never merges two groups.
    - Only previousDisplayName resolves: that group takes the existing-group path, and the rename is
      folded into the step-1 property update (Set-OERGroup -NewDisplayName, in the same PATCH as every
      other changed property), reported as one Updated row "renamed group '<previous>' to '<new>'".
      When that update fails, the Failed row is the last one: no child of the group is reconciled.
    - Both resolve to the SAME group, or only displayName resolves: the item is applied normally.
    - Neither resolves: the item emits exactly one Failed row and a non-terminating
      GroupRenameNotFound error (category ObjectNotFound, target the new name), and nothing is
      created, read or written for it. A document that declares a rename names a group that already
      exists; a group is created only by an entry WITHOUT previousDisplayName.
    A previousDisplayName matching several groups throws AmbiguousName, as an ambiguous displayName
    does, and the item fails with nothing created or renamed. previousDisplayName also accepts the
    group's object id, which is the way to rename a group whose old name is ambiguous. An object id
    is verified with one read (v1.0/groups/<id>?$select=id): an id that no longer names a group counts
    as not matching, so a stale id never reports a false conflict (with displayName resolving, the
    item is applied normally; with it not resolving, the item fails as above), and any other failure
    of that read throws, again with nothing created or renamed.

    Microsoft Graph's displayName lookup can follow a rename with a delay. On the run that renames
    the group, a reference to the NEW name elsewhere in the same document can therefore fail to
    resolve. It fails loudly -- a Failed row, and a handler that withholds its prune while a declared
    entry does not resolve withholds it -- and re-running the document once the new name resolves is
    safe. Keep previousDisplayName in the document until the new name resolves: a run after that
    finds the group under displayName and reports it Unchanged, and a re-run inside the window in
    which neither name resolves yet fails with GroupRenameNotFound instead of creating a second
    group. Once the new name resolves, remove previousDisplayName: a group created later under the
    old name makes the item fail.

    Processing order within a single group (the PIM chicken-and-egg ordering):
    1. Create the group when absent, or diff and update mutable properties (the display name when
       previousDisplayName renames the group, Description, MailNickname, and
       MembershipRule/MembershipRuleProcessingState when the live group is already dynamic) when it
       already exists. Two properties
       are Graph-immutable once the group is created -- isAssignableToRole ("can only be set while
       creating the group and is immutable" per Microsoft Learn) and the static/dynamic membership type
       itself (Set-OERGroup has no PATCH path for either and raises its own NotDynamicGroup error for a
       membershipRule sent to a non-dynamic group). A document that declares a value differing from live
       state for either one gets a Skipped record naming the divergence plus a Write-Warning, and the
       write is never attempted; this also suppresses the contradictory 'group properties match'
       Unchanged for the same group.
    2. Reconcile declared members (add missing; emit Extra or prune undeclared with -Prune, or report
       them Skipped while a declared member cannot be resolved -- see "Withheld prune" below; a
       service principal is never pruned -- see "Service principals" below) -- UNLESS
       the group is dynamic (already dynamic, or declared dynamic=true in the document). Microsoft Learn
       is explicit that a member of a dynamic membership group cannot be added or removed manually, so
       every declared member is reported as a Skipped record instead, nothing is added, and the
       Extra/prune pass does not run (a group with no declared members but a live membership still gets
       one summary Skipped record so the inaction is visible under -Prune too).
    2b. Reconcile declared owners (add missing; emit Extra or prune undeclared with -Prune, or report
        them Skipped while a declared owner cannot be resolved -- see "Withheld prune" below; a
        service principal is never pruned -- see "Service principals" below), gated on
        the document's owners key being DECLARED (present and non-null) -- an omitted owners key never
        reconciles or prunes, unlike members. Owners are not rule-derived, so this step runs even on a
        dynamic group. Microsoft Learn states a group's last (user) owner cannot be removed; a -Prune
        run that would remove the last remaining owner reports a Skipped record instead of firing a
        call Microsoft Graph rejects. A service principal owner is withheld before that guard and
        counts as an owner still standing.
    3. Reconcile time-bound eligibility entries (those with durationDays) -- the first eligibility
       request onboards the group to PIM for Groups if it was not onboarded yet. Each entry is matched
       on the (principal, accessType) pair and its declared window is diffed against the live schedule
       instance by Resolve-OERGroupEligibilityChange, so a changed durationDays or a member/owner
       switch is re-issued instead of being reported Unchanged. Add-OERGroupEligibility is called with
       -Action adminAssign when the eligibility is absent and -Action adminUpdate when it already
       exists and only its window or permanence differs, since Microsoft Graph rejects an adminAssign
       against a principal that is already eligible.
       For a group THIS RUN created, the request is sent through Send-OERNewGroupEligibilityRequest
       instead, and a 404 ResourceNotFound counts as replication: PIM for Groups can take a moment to
       know a brand-new group, so the answer is waited on and the request asked again, from the one
       shared budget described under step 4 (at most about 30 seconds, 2 + 4 + 8 + 16 s, per group
       item). The private request declares the 404 to the transport, which is what keeps a run that
       ends Updated free of error records in the caller's -ErrorVariable -- Add-OERGroupEligibility
       cannot declare it, and a 404 thrown inside it and caught here would still leave its records
       there. A request Microsoft Graph accepts but answers with status Failed counts as the same
       replication for a group created in this run (measured live 2026-10-03: the 404s gave way to a
       201 whose status was already Failed, and the same request minutes later was Provisioned), so it
       is waited on from the same budget and asked again; any other status is the applied request.
       Once the budget is spent the entry reports Failed with a ResourceNotFound error record and a
       replication-delay message naming a re-run. Any other failure (a 403, a throttle that
       outlasted the transport's own retries, a 5xx, the same code under another status) is reported
       as itself and never waited on. A group that already existed never waits, a 404 or a status
       Failed included, and keeps the Add-OERGroupEligibility call: there a request Microsoft Graph
       accepts but answers with status Failed is that cmdlet's EligibilityRequestFailed error, which
       the entry reports as a Failed row carrying that error record, never as Updated -- nothing was
       granted, and a re-run usually applies it. An applied eligibility's row stays Updated, as for
       every other child write: only the group row is Created.
    4. Apply pimPolicy (e.g. ActivationMaxHours, AllowPermanentEligibility, and approval on activation
       via requireApproval/approvers) -- after the time-bound eligibility entries. Microsoft Graph
       lists a group's policies whether or not the group was ever used with PIM for Groups, and the
       first policy update onboards the group, which cannot be undone (Microsoft Graph documentation,
       "Onboarding groups to PIM for Groups"). So before the first CHANGED policy write of an item for
       a group that already existed -- and before its ShouldProcess gate, so -WhatIf shows it too --
       the handler asks Test-OERGroupPimInUse, once per item, whether the group uses PIM for Groups,
       and writes a warning when the group was not found to use it (a finding of the criterion, which
       has a documented blind spot, not a fact), or when that cannot be read. The warning never blocks
       and never changes a row: the write still runs. It is not asked for a group created in the
       same run, nor once step 3 of the same item has written an eligibility (which onboarded the
       group already). The eligibility it passes is what the item read, and the item reads PIM
       eligibility only when it declares eligibility. A declared approver (a UPN or a group display
       name) is resolved to an object id before the diff, for each access type in turn; an approver
       that does not resolve reports Failed for that access type ONLY -- the other access type
       (member/owner) and every later step still run. The row carries ApproverNotFound for an
       approver that matches nothing, AmbiguousApproverName (naming the candidate ids) for a group
       display name several groups share, and the lookup's own error for a lookup that failed.
       When the diff reconciles the MFA / authentication context pair (Resolve-OERGroupPimPolicyChange
       clears MultiFactorAuthentication, or disables the authentication context, and reports why in
       ConflictReason), Set-OERGroupPimPolicy -- called with the reconciled parameters -- has nothing
       left to resolve and writes no warning. The handler therefore writes it, before the ShouldProcess
       gate and in every mode, so -WhatIf shows it and a real run writes it once: "Policy '<id>':
       <reason>", the text the cmdlet writes for a direct call, with the id of the policy it read, or
       "pimPolicy (<accessType>) of group '<name>': <reason>" when no policy was read. The warning
       states the diff's decision, not the outcome: Set-OERGroupPimPolicy can still refuse the call
       after it (an authentication context the tenant does not define or has not published, a failed
       policy lookup, an unreadable approval rule), and the Failed row then shows that nothing was
       changed.
       For a group THIS RUN created, the handler first asks Get-OERPimGroupPolicyId whether Graph lists
       that access type's policy yet, then reads the listed policy through Get-OERListedGroupPimPolicy,
       and waits while either comes back empty -- one shared budget of at most about 30 seconds
       (2 + 4 + 8 + 16 s) per group item, spent by whichever access type needs it first -- since a
       brand-new group's policies can take a moment to be listed and readable. A 404 ResourceNotFound
       from either call counts as not there yet: a group PIM does not know yet answers the listing with
       404, not an empty list, and a policy listed a second earlier can answer its read with 404 (both
       measured live 2026-09-28). A 404 on the read starts over from the listing. Both calls declare
       the 404 to the transport, which is what keeps a run that ends Updated free of error records in
       the caller's -ErrorVariable. Once the budget is spent without a readable policy, that access
       type reports Failed, with a PimPolicyNotFound error record and a replication-delay message
       naming a re-run, and the loop moves to the next access type. A refused call (a 403, for
       example) stops the wait at once and falls through to the single Get-OERGroupPimPolicy read, as
       for any group. Set-OERGroupPimPolicy does its own lookup: a 404 inside it, after the wait has
       read the policy, is reported as that call's Failed row and is not waited on. A group that already
       existed never waits, a 404 included: its missing policy is a fact, not a timing issue, and the
       single read decides it as for any other group. That one budget is also spent by the eligibility
       waits of steps 3 and 5, so a 404 on a new group's eligibility leaves that much less for its
       policy, and a second entry never gets a fresh 30 seconds of its own.
    5. Reconcile permanent eligibility entries (those without durationDays) -- must come after
       pimPolicy has been set to allow permanent eligibility. Matched and diffed the same way, so a
       time-bound eligibility that the document declares permanent is re-issued as permanent, again
       selecting adminAssign or adminUpdate from the diff reason as in step 3.
       Add-OERGroupEligibility warns, before its own gate, when the group's policy must be opened to
       allow permanent eligible assignments (affecting ALL eligibility of that access type). Under
       -WhatIf, where the cmdlet is never called, the handler makes the same read
       (Get-OERGroupPermanentEligibilityState) before its gate and writes the cmdlet's warning, with the
       same text, when the policy is listed and does not allow permanent eligibility; a failed read
       writes nothing, as in the cmdlet. The plan decides on the state step 4 WOULD leave: when step 4
       of the same item had a changed policy for that access type that sets allowPermanentEligibility,
       and its gate declined that change, its value stands in for what the read says about permanent
       eligibility (true: no warning; false: the warning when the policy is listed), since a real run
       applies step 4 before the cmdlet reads the policy. Otherwise the read decides, and whether the
       policy is listed always comes from the read. The plan also follows the state each entry leaves:
       once it has planned the warning for an access type, a later permanent entry of the same access
       type plans none, since in a real run the first entry's Add-OERGroupEligibility opens the policy
       and the later ones find it open; each access type is decided on its own. A real run leaves the
       warning to the cmdlet, so it is never written twice for one entry, and the plan writes it as
       often as a run in which the policy opens. Step 3 has no such warning: a time-bound eligibility
       never opens the policy.
       For a group THIS RUN created, the entry first waits, from the same shared budget, until
       Microsoft Graph lists that access type's policy AND that policy answers its read, as step 4
       does: Get-OERPimGroupPolicyId -NotFoundAsUnlisted, then Get-OERListedGroupPimPolicy, a 404 from
       either counting as not there yet and a 404 on the read starting over from the listing. Only
       then does it call Add-OERGroupEligibility, once. Listed is not enough: the cmdlet's pre-check
       reads that same policy, and a listed policy that still answers 404 would leave it closed and
       the permanent request refused. Unlike step 3 it keeps the cmdlet, because the cmdlet's
       permanent pre-check and policy self-heal (Get-OERGroupPermanentEligibilityState,
       Enable-OERGroupPermanentEligibility) are behaviour the engine relies on and the cmdlet cannot
       declare a 404 to the transport; the silent probe is what spares the caller's -ErrorVariable the
       records a thrown 404 would leave. A request the cmdlet returns with status Failed (Microsoft
       Graph accepted it and failed it) counts as the same replication for a group created in this
       run, as in step 3: the next wait comes from the same budget and the entry starts over from the
       listing. A budget spent with no readable policy (the cmdlet then not called), or with the
       request still answered Failed, reports Failed with a GroupNotOnboarded error record -- the id
       Add-OERGroupEligibility publishes for the same condition -- and a replication-delay message
       naming a re-run. That message ends with one sentence group saying whether the group's policy
       was opened for the entry, since the cmdlet opens it to allow permanent eligibility before its
       request and has no rollback. When the cmdlet was never called, no request was sent and no
       policy was opened. Otherwise the handler reads the policy once more after the attempts, with the
       poll's own two calls and no wait of its own, and compares it with the policy as the poll read
       it just before the FIRST call: one that does not allow permanent eligibility was not left open,
       unless the poll read it closed just before the first request -- that request would then have
       opened it, and a read made seconds later can come from a replica that has not seen the open, so
       the message says the read may be out of date; one that already allowed it before the first
       request was not opened for it; one that did not is named as opened and still open; one whose
       earlier state is unknown (the poll was refused, or its read carried no permanent-eligibility
       setting) is named as open and possibly opened. With the cmdlet never called (above) and a read
       that fails (below), that makes seven outcomes. The possibly out-of-date read and the last two
       carry the Set-OERGroupPimPolicy command that closes the policy
       (Get-OERGroupPimPolicyCloseAdvice, the advice Add-OERGroupEligibility gives).
       A read after the attempts that is refused (scrubbed and logged), unlisted, answers 404 or
       reads no permanent-eligibility setting is never taken for "not opened": the message says the
       policy may have been opened and could not be read, and gives the same command for the case
       that it allows permanent eligibility.
       When a LATER call in that wait throws after an earlier call was sent and answered Failed, the
       earlier request may have opened the policy while the later call opened nothing, so its error
       carries no advice. The record the caller gets and the Failed row then carry the same
       after-attempts read and outcome text as GroupNotOnboarded (the six outcomes after a call was
       made), appended to the caught message, in a new record with the caught record's own error id,
       category and target. The read is made before that record is written, so a caller stopped by it
       under -ErrorAction Stop gets it too. A first call's error, and a PolicyOpenedButGrantFailed
       (which carries the advice for the policy that call opened), are reported as before.
       A refused probe (a 403 on the listing or on the read, for example) ends the
       wait at once and the cmdlet is called as for any group, and a 404 from the cmdlet itself after
       the policy was read is reported as for any group. For that one call the handler sets the
       module-scope flag $script:_OERGroupEligibilityFailedIsReplication (reset in a finally), which
       tells the cmdlet that a Failed status is this handler's replication, so the cmdlet does not
       report it as its EligibilityRequestFailed error: a record the cmdlet writes stays in the
       caller's -ErrorVariable even when it is caught here, and a run that ends Updated would still
       hand back errors. A group that already existed never probes and never waits, and there a
       Failed status is the cmdlet's EligibilityRequestFailed error, reported as a Failed row as in
       step 3.

    When -Prune is set, current members not present in the declared set are removed (with
    Write-Warning) after a ShouldProcess gate. Without -Prune those extra members are reported as
    Extra (informational) and left alone. The same applies to eligibility entries, with one
    difference: an eligibility entry is only reconciled (reported as Extra, or removed under
    -Prune) when the document's eligibility key is DECLARED (present and non-null, including an
    empty array) -- an omitted eligibility key leaves live eligibility alone entirely, unlike an
    omitted members key, which still reconciles against an empty declared set.

    A group created into an administrative unit (BL-07): administrativeUnit is passed to New-OERGroup
    -AdministrativeUnit when the group is created and never round-trips, so the unit's own
    administrativeUnits[] entry need not list the group. Right after New-OERGroup returns the group,
    the handler adds a record -- the unit as the document declares it (a display name or an object
    id), the new group's id and its name -- to the run-scoped list the engine passes as
    -CreatedUnitMembership. Sync-OERStructureAdministrativeUnit, which the engine runs after this
    section, then withholds the prune of that membership in the same run. Nothing is recorded under
    -WhatIf (nothing is created), for a failed create, or for a group created without a unit; a group
    New-OERGroup found already existing is recorded too, which can only withhold a prune.

    Service principals (decision A9): a live member or owner whose ObjectType is servicePrincipal is
    never removed from the group. Microsoft Graph's v1.0 member and owner lists leave service
    principals out, so before Get-OERGroupRelation added the typed read no version saw one in a
    group, none pruned one, and no document exported by an earlier version lists one; pruning them
    now would remove more than any earlier version did. An undeclared service principal is reported
    Extra without -Prune (with a hint that -Prune leaves it in place) and Skipped with -Prune, with a
    Detail that starts "prune withheld: ... is a service principal", under -WhatIf too; no warning is
    written, no ShouldProcess prompt is issued and Remove-OERGroupMember is not called for it
    (ConvertTo-OERPruneWithheldResult owns the rule and both texts). The check comes straight after
    the unresolved-entry rule below and, for owners, before the last-owner guard. A declared service
    principal is added and reported like any other principal, and a member or owner of any other
    type, or with no type, is reconciled and pruned exactly as described above.

    A group synchronized from on-premises (decision A15): when the live read -- Get-OERGroup's, or the
    existing group New-OERGroup returns -- shows OnPremisesSyncEnabled True
    (Test-OERGroupOnPremisesSynced), the group is managed in on-premises Active Directory and
    read-only in the cloud, and the handler writes nothing to it. Every property, member, owner,
    eligibility or pimPolicy change the entry declares is reported Skipped, naming the reason, with no
    ShouldProcess call and no request, so -WhatIf and a real run report the same rows; a declared
    pimPolicy is not even read, since PIM for Groups cannot manage such a group. An undeclared live
    member, owner or eligibility that is already withheld for another reason -- an unresolved
    declared entry in its collection (see "Withheld prune" below), or a service principal (see
    "Service principals" above) -- keeps that reason's row; every other one is Extra without -Prune,
    with a hint that -Prune leaves it in place, and Skipped with -Prune, its Detail starting
    'prune withheld:' (ConvertTo-OERPruneWithheldResult -SyncedGroup). One warning per item, written
    before the first such row, says so; Extra rows alone, and the rows withheld for another reason,
    write none. The warning and every reason name the group as the live read does, so a group found
    only under previousDisplayName is named by the name it still carries, not by the new
    displayName, while every row stays keyed on the entry's displayName. What already matches stays
    Unchanged. The document's onPremisesSynced key is never consulted and never sent: a cloud group
    is written to as usual whatever that key says. A write that only points at the group (a role
    assignment, an administrative unit membership, an access package resource role) is another
    section's and unchanged.

    Withheld prune: members, owners and eligibility each withhold their OWN prune when one of their
    declared entries cannot be resolved (Resolve-OERStructurePrincipal gives no object id). Such an
    entry carries no id, so the pass cannot tell which live entry it names, and its live counterpart
    would otherwise look undeclared. Every undeclared live entry in that collection is then reported
    Skipped, with a Detail that starts "prune withheld: declared entry '<reference>' could not be
    resolved" (several unresolved entries: "declared entries '<a>', '<b>' could not be resolved"),
    with or without -Prune; no warning is written, no ShouldProcess prompt is issued, and nothing in
    that collection is removed until the entry is fixed or removed from the document
    (ConvertTo-OERPruneWithheldResult owns the rule and the text). The unresolved entry keeps its own
    error and Failed record (the record is lost only when the handler later throws for the same item,
    see below). The rule is per collection: an unresolved owner withholds the owner prune only, and the
    member and eligibility passes run as usual. For eligibility, an unresolved entry in either the
    time-bound or the permanent list withholds the whole eligibility prune. A withheld owner is
    reported Skipped before the last-owner guard is consulted. A lookup that THROWS, rather than
    giving no id, is not caught by this handler: it ends the item where it is thrown, and neither that
    collection's prune pass nor any later step runs. The engine then reports the item as one Failed
    ("handler error") record and discards every record the handler had already emitted for it, so a
    change already applied -- a prune pass completed for an earlier collection included -- stands
    with no row, and an unresolved entry's Failed row is lost; warnings and errors already written
    remain.

    A failed read of the live group -- its properties, members, owners or PIM eligibility -- reports
    Failed with the underlying ErrorRecord and reconciles nothing further for that item, so a Created
    row is never derived from a read that did not succeed; an empty read that SUCCEEDED still
    reconciles normally.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets, and writes the warning a child cmdlet
    would have written for a permanent eligibility that opens the policy (step 5). When the group
    itself does not exist and its creation is skipped under -WhatIf, no child read or write calls
    are made. A rename under -WhatIf is reported Skipped ("would rename group '<previous>' to
    '<new>'"), and the group found
    under its previous name is still read, so its children are planned against it. A rename that
    neither name resolves, and a rename conflict, are Failed under -WhatIf too: both are decided
    before any ShouldProcess gate.

    .PARAMETER Item
    One element from the groups[] array in the structure document, as a PSCustomObject produced by
    ConvertFrom-Json. Its optional previousDisplayName names the group's current display name when
    displayName declares a new one; see the rename rule above.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current members not in the declared set are removed after a ShouldProcess gate. Without
    this switch, extra members are only reported as Extra and never deleted. Also removes eligibility
    entries not in the declared set, but only when the document declares the eligibility key at all
    (present and non-null) -- an omitted eligibility key is never pruned or reported, regardless of
    -Prune. The same present-and-non-null gate applies to owners: an omitted OR explicit null
    owners key is never reconciled or pruned. members is the one collection where absent and null
    differ: an omitted members key still reconciles (existing members it does not name are
    pruned/reported same as any other run), but an explicit "members": null does not reconcile at
    all. null -- not an omitted key -- is how a group is declared without touching its members,
    owners or eligibility; applying the scalar "omission means untouched" rule to members gets
    this backwards. In each of members, owners and eligibility, while a declared entry cannot be
    resolved to an object id, nothing in that collection is removed or reported Extra: every
    undeclared live entry in it is reported Skipped with a Detail starting "prune withheld:", with or
    without this switch. A lookup that throws aborts the item instead, before that collection's prune.
    A service principal member or owner is never removed: with this switch it is reported Skipped
    ("prune withheld:"), without it Extra. Nothing is removed from a group synchronized from
    on-premises: with this switch each candidate is reported Skipped ('prune withheld:'), without it
    Extra.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias, accepted only for call-site uniformity with the other
    Sync-OERStructure* handlers that Invoke-OERStructure drives uniformly. This handler does not
    currently consult a tenant default for any field.

    .PARAMETER CreatedUnitMembership
    The run-scoped list Invoke-OERStructure creates once per document and passes to this handler and
    to Sync-OERStructureAdministrativeUnit. When the handler creates a group into an administrative
    unit it adds one record (AdministrativeUnit, GroupId, Label) to it; see the BL-07 paragraph above.
    Optional: without it nothing is recorded.

    .EXAMPLE
    Sync-OERStructureGroup -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one group entry from the document, pruning undeclared members. -TenantAlias is accepted
    for call-site uniformity with the other Sync-OERStructure* handlers but is not otherwise used here.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'The Invoke-OERStructure engine passes -TenantAlias uniformly to every Sync handler; this handler no longer consults a tenant default for pimPolicy but keeps the parameter for call-site uniformity.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias,
        [System.Collections.Generic.List[object]]$CreatedUnitMembership
    )
    process {
        # -- Resolve the display name (template or literal) ---------------------------------
        $Name = $null
        $HasTemplate = Test-OERDeclaredProperty -Node $Item -Name 'template'
        if ($HasTemplate -and $Item.template) {
            $TokenHash = @{}
            if (Test-OERDeclaredProperty -Node $Item -Name 'tokens') {
                foreach ($Prop in $Item.tokens.PSObject.Properties) {
                    $TokenHash[$Prop.Name] = $Prop.Value
                }
            }
            $Name = Resolve-OERName -Template $Item.template -Tokens $TokenHash
        } else {
            $Name = $Item.displayName
        }

        # A15: the engine writes nothing to a group its LIVE read shows as synchronized from
        # on-premises; Test-OERGroupOnPremisesSynced owns that rule, and the document's
        # onPremisesSynced key is never consulted. $GroupSynced is set from the live read below
        # ($Cur, or the group New-OERGroup returned). Every write such a group would get is reported
        # Skipped through Write-SyncedGroupSkip, with no ShouldProcess call, so the plan and the run
        # report the same rows; each prune candidate is withheld (ConvertTo-OERPruneWithheldResult
        # -SyncedGroup). One warning per item, before the first such row: a Skipped write, or a
        # withheld prune under -Prune. The warning and the reasons name the group as the live read
        # does ($SyncedGroupName): a group found only under previousDisplayName does not carry the
        # document's new name. Every row stays keyed on the document entry (-Item $Name).
        $GroupSynced = $false
        $SyncedGroupName = $Name
        $SyncedState = @{ Warned = $false }
        function Write-SyncedGroupWarning {
            if ($SyncedState.Warned) { return }
            $SyncedState.Warned = $true
            Write-Warning "Sync-OERStructureGroup: group '$SyncedGroupName' is synchronized from on-premises (onPremisesSyncEnabled is true) and is managed there, so the apply engine writes nothing to it: every change the document declares for its properties, members, owners, eligibility or pimPolicy is reported Skipped, and -Prune removes nothing from it. Make the change in the on-premises directory."
        }
        function Write-SyncedGroupSkip {
            param([string]$What)
            Write-SyncedGroupWarning
            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                -Detail "${What}: group '$SyncedGroupName' is synchronized from on-premises and is managed there (onPremisesSyncEnabled), so the apply engine writes nothing to it"
        }

        # -- Check existence ----------------------------------------------------------------
        $Gid = Resolve-OERGroupId -DisplayName $Name

        # -- Rename through previousDisplayName -------------------------------------------
        # Resolved on every run, before anything is read or written. Not wrapped in try: a previous
        # name matching several groups throws AmbiguousName exactly as an ambiguous displayName does,
        # and the engine reports the item Failed with nothing written for it.
        $RenameFrom = $null
        if (Test-OERDeclaredProperty -Node $Item -Name 'previousDisplayName') {
            $PrevName = [string]$Item.previousDisplayName
            if (Test-OERGuid -Value $PrevName) {
                # An object id. Resolve-OERGroupId would hand it back verbatim without asking Graph,
                # so a stale id of a deleted group would look like a live one: a false conflict when
                # displayName exists, and a failed read instead of a create when it does not. One
                # read settles it. The not-found answer is declared to the transport and means "no
                # group under that id"; any other failure is not evidence either way and throws, so
                # the engine reports the item Failed with nothing written.
                $PrevProbe = Invoke-OERGraphRequest -Uri "v1.0/groups/$PrevName`?`$select=id" `
                    -ExpectedErrorCode 'Request_ResourceNotFound', 'ResourceNotFound'
                $PrevGid = if (@($PrevProbe.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { $null } else { $PrevName }
            } else {
                $PrevGid = Resolve-OERGroupId -DisplayName $PrevName
            }
            # Both names on DIFFERENT groups: the document never merges two groups, so this is the
            # item's only row -- no read, no write, no child reconciled. -ne compares the two ids
            # case-insensitively, so one group reached under an upper-case id is never two groups.
            if ($Gid -and $PrevGid -and ([string]$Gid -ne [string]$PrevGid)) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Group '$Name' ($Gid) and its previousDisplayName '$PrevName' ($PrevGid) are different groups. The document never merges two groups, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName."),
                    'GroupRenameConflict',
                    [System.Management.Automation.ErrorCategory]::ResourceExists,
                    $Name
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' `
                    -Detail "both '$Name' and its previousDisplayName '$PrevName' exist as different groups; the document never merges two groups, so nothing was changed -- rename or delete one of them, or remove previousDisplayName" `
                    -ErrorRecord $ErrRec
                return
            }
            # NEITHER name resolves: a document that declares a rename names a group that already
            # exists, so this is never a create. Right after a rename, Graph's name lookup can find
            # the group under neither name for a while, and creating it then would leave a duplicate
            # beside the renamed one. One Failed row, nothing read or written.
            if (-not $Gid -and -not $PrevGid) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Neither '$Name' nor its previousDisplayName '$PrevName' matches a group, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new group, remove previousDisplayName."),
                    'GroupRenameNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Name
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' `
                    -Detail "neither '$Name' nor its previousDisplayName '$PrevName' matches a group, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new group, remove previousDisplayName" `
                    -ErrorRecord $ErrRec
                return
            }
            # Only the previous name exists: that group takes the existing-group path below, and the
            # rename is folded into its property update.
            if (-not $Gid -and $PrevGid) {
                $Gid = $PrevGid
                $RenameFrom = $PrevName
            }
        }

        # Whether THIS run created the group, consulted only by the replication waits of steps 3, 4 and
        # 5 below: a brand-new group's eligibility requests can be answered 404 and its policy
        # assignments can take a moment to be listed by Graph, but a 404 or a missing policy on a group
        # that already existed is a fact, not a timing issue, and is never waited for.
        $CreatedThisRun = $false

        # -- Create or update the group object ------------------------------------------
        if (-not $Gid) {
            # Group does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create group')) {
                # Under -WhatIf: emit Skipped for the group and all children, then return.
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would create group $Name"

                # Emit Skipped for declared members
                if (Test-OERDeclaredProperty -Node $Item -Name 'members') {
                    foreach ($M in @($Item.members)) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure member '$M' after group is created"
                    }
                }

                # Emit Skipped for declared owners
                if (Test-OERDeclaredProperty -Node $Item -Name 'owners') {
                    foreach ($O in @($Item.owners)) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure owner '$O' after group is created"
                    }
                }

                # Emit Skipped for declared eligibility entries
                if (Test-OERDeclaredProperty -Node $Item -Name 'eligibility') {
                    foreach ($E in @($Item.eligibility)) {
                        $Ref = if (Test-OERDeclaredProperty -Node $E -Name 'principal') { $E.principal } else { '?' }
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would configure eligibility for '$Ref' after group is created"
                    }
                }

                # Emit Skipped for pimPolicy
                if (Test-OERDeclaredProperty -Node $Item -Name 'pimPolicy') {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail 'would configure pimPolicy after group is created'
                }
                return
            }

            # Build creation params
            $NewParams = @{ DisplayName = $Name; Confirm = $false }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'roleAssignable') -and $Item.roleAssignable -eq $true) {
                $NewParams.RoleAssignable = $true
            }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'dynamic') -and $Item.dynamic -eq $true) {
                $NewParams.Dynamic = $true
                if (Test-OERDeclaredProperty -Node $Item -Name 'membershipRule') {
                    $NewParams.MembershipRule = $Item.membershipRule
                }
                if (Test-OERDeclaredProperty -Node $Item -Name 'membershipRuleProcessingState') {
                    $NewParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
                }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if (Test-OERDeclaredProperty -Node $Item -Name 'mailNickname') { $NewParams.MailNickname = $Item.mailNickname }
            if (Test-OERDeclaredProperty -Node $Item -Name 'administrativeUnit') { $NewParams.AdministrativeUnit = $Item.administrativeUnit }

            $Created = $null
            try {
                $Created = New-OERGroup @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "group creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail 'New-OERGroup returned no object'
                return
            }
            # New-OERGroup hands back an EXISTING group of that name, read without $select, in place
            # of creating one: that read decides as Get-OERGroup's does below (A15).
            $GroupSynced = Test-OERGroupOnPremisesSynced -Group $Created
            $SyncedGroupName = if ($Created.DisplayName) { [string]$Created.DisplayName } else { $Name }

            $Gid = $Created.Id
            $CreatedThisRun = $true

            # BL-07: a group created INTO an administrative unit is a member that unit's own entry need
            # not list, since administrativeUnit is applied only here and never round-trips, and the
            # administrativeUnits section runs after this one. Record the membership this run created,
            # so that section does not prune it in the same run. A group New-OERGroup found already
            # existing is recorded too: the record only withholds a prune. The condition is
            # New-OERGroup's own: a blank unit creates the group at the top level.
            if ($null -ne $CreatedUnitMembership -and $NewParams.AdministrativeUnit) {
                $CreatedUnitMembership.Add([PSCustomObject]@{
                        AdministrativeUnit = [string]$NewParams.AdministrativeUnit
                        GroupId            = [string]$Gid
                        Label              = [string]$Name
                    })
            }

            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Created' -Detail "created group $Name ($Gid)"

            # After create: current state is empty
            $CurrentMembers    = @()
            $CurrentOwners     = @()
            $CurrentEligibles  = @()

        } else {
            # Group exists -- diff mutable properties.
            # A failed read of the live group is not an empty group. Get-OERGroup now OMITS a
            # collection whose read failed, and without -ErrorAction Stop that absence collapsed
            # silently to @() below -- so the engine reconciled against an empty current state and
            # reported Created for members that already exist (issue #60, and the caller half of
            # issue #76).
            # Ask ONLY for the collections this document entry can actually consume. -ErrorAction Stop
            # makes the read all-or-nothing on purpose (a partially read item must never be pruned),
            # so requesting a collection the entry never uses would let one unusable endpoint fail the
            # whole item: a tenant whose PIM-for-Groups beta endpoint answers 403 rather than the
            # ResourceTypeNotSupported that Get-OERGroup carves out by name would report Failed for
            # every group, including ones declaring only members that applied cleanly before.
            # -IncludeMembers stays unconditional: $CurrentMembers feeds the Extra/prune pass whenever
            # 'members' is not declared-null, which includes an omitted key.
            # 'eligibility' alone drives -IncludePimEligibility, and 'pimPolicy' deliberately does NOT:
            # Step 4 reads the live policy through Get-OERGroupPimPolicy and never consults
            # $CurrentEligibles. Its only three consumers are the time-bound loop, the permanent loop
            # and the Extra/prune pass, and all three are reached solely when 'eligibility' is declared.
            # Requesting the read for a pimPolicy-only entry let a 403 on the beta eligibility endpoint
            # fail an item that has no use for the answer -- and that applies cleanly today.
            $NeedOwners = Test-OERDeclaredProperty -Node $Item -Name 'owners'
            $NeedElig   = Test-OERDeclaredProperty -Node $Item -Name 'eligibility'
            $Cur = $null
            try {
                $Cur = Get-OERGroup -Id $Gid -IncludeMembers -IncludeOwners:$NeedOwners `
                    -IncludePimEligibility:$NeedElig -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current state of group '$Name': $($PSItem.Exception.Message); no property, member, owner or eligibility change was made" `
                    -ErrorRecord $PSItem
                return
            }
            # A15: the live read decides whether the group is synchronized from on-premises, and
            # names it (a group found under previousDisplayName still carries its previous name).
            $GroupSynced = Test-OERGroupOnPremisesSynced -Group $Cur
            $SyncedGroupName = if ($Cur.DisplayName) { [string]$Cur.DisplayName } else { $Name }
            $CurrentMembers   = if ($Cur.Members) { @($Cur.Members) } else { @() }
            $CurrentOwners    = if ($Cur.Owners) { @($Cur.Owners) } else { @() }
            $CurrentEligibles = if ($Cur.PimEligibility) { @($Cur.PimEligibility) } else { @() }
            $CurIsDynamic     = ([string]$Cur.GroupType -eq 'Dynamic')

            # Diff Description and MailNickname
            $UpdateParams = @{}
            # Set when a drift Skipped record fires below, so the no-updates branch never also emits a
            # contradictory 'group properties match' Unchanged for the same group.
            $DriftReported = $false

            # A rename through previousDisplayName travels in the same PATCH as every other changed
            # property, so the group is renamed and updated in one call.
            if ($RenameFrom) {
                $UpdateParams.NewDisplayName = $Name
            }

            if (Test-OERDeclaredProperty -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) {
                    $UpdateParams.Description = $Item.description
                }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'mailNickname') {
                if ($Cur.MailNickname -ne $Item.mailNickname) {
                    $UpdateParams.MailNickname = $Item.mailNickname
                }
            }

            # isAssignableToRole: Microsoft Learn states it "can only be set while creating the group
            # and is immutable" -- so declared drift here can never be applied. Report it and move on
            # rather than firing a doomed PATCH or silently pretending the properties match.
            if ((Test-OERDeclaredProperty -Node $Item -Name 'roleAssignable') -and ([bool]$Item.roleAssignable -ne [bool]$Cur.IsAssignableToRole)) {
                $DriftReported = $true
                Write-Warning "Sync-OERStructureGroup: group '$Name' declares roleAssignable=$([bool]$Item.roleAssignable) but the live group is roleAssignable=$([bool]$Cur.IsAssignableToRole); isAssignableToRole can only be set while creating a group and is immutable on Microsoft Graph -- recreating the group is the only route."
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "declared 'roleAssignable' ($([bool]$Item.roleAssignable)) differs from the live group ($([bool]$Cur.IsAssignableToRole)); isAssignableToRole is immutable on Microsoft Graph -- recreating the group is the only route"
            }

            # dynamic: a static group cannot be converted to dynamic (and Set-OERGroup raises its own
            # NotDynamicGroup error for exactly that attempt), and this module never PATCHes a dynamic
            # group back to static either. Report the drift instead of attempting a doomed conversion.
            $WantDynamic = if (Test-OERDeclaredProperty -Node $Item -Name 'dynamic') { [bool]$Item.dynamic } else { $null }
            if (($null -ne $WantDynamic) -and ($WantDynamic -ne $CurIsDynamic)) {
                $DriftReported = $true
                Write-Warning "Sync-OERStructureGroup: group '$Name' declares dynamic=$WantDynamic but the live group is dynamic=$CurIsDynamic; Set-OERGroup cannot convert a group's membership type (NotDynamicGroup) -- recreating the group is the only route."
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "declared 'dynamic' ($WantDynamic) differs from the live group ($CurIsDynamic); Set-OERGroup cannot convert a group's membership type (NotDynamicGroup) -- recreating the group is the only route"
            }

            # membershipRule: Set-OERGroup PATCHes it only when the live group is already dynamic, and
            # guards the non-dynamic case with its own NotDynamicGroup error. When the live group is not
            # dynamic, the 'dynamic' drift report above already covers it -- do not also add the rule.
            if ((Test-OERDeclaredProperty -Node $Item -Name 'membershipRule') -and $CurIsDynamic -and ([string]$Cur.MembershipRule -ne [string]$Item.membershipRule)) {
                $UpdateParams.MembershipRule = [string]$Item.membershipRule
            }
            # membershipRuleProcessingState: same rule as membershipRule -- Set-OERGroup cannot convert a
            # group's type, so this is diffed only when the LIVE group is already dynamic (the 'dynamic'
            # drift report above covers a non-dynamic live group; a declared value there is drift, not a
            # prediction of what this run will produce).
            if ((Test-OERDeclaredProperty -Node $Item -Name 'membershipRuleProcessingState') -and $CurIsDynamic -and ([string]$Cur.MembershipRuleProcessingState -ne [string]$Item.membershipRuleProcessingState)) {
                $UpdateParams.MembershipRuleProcessingState = [string]$Item.membershipRuleProcessingState
            }

            if ($UpdateParams.Count -gt 0) {
                # The rename is reported on its own terms; the other changed keys keep the wording
                # every property update has always had.
                $PropertyKeys = @($UpdateParams.Keys | Where-Object { $_ -ne 'NewDisplayName' })
                $PropertyList = $PropertyKeys -join ', '
                if ($RenameFrom) {
                    $UpdateAction = "Rename group '$RenameFrom' to '$Name'"
                    $UpdatedDetail = "renamed group '$RenameFrom' to '$Name'"
                    $PlannedDetail = "would rename group '$RenameFrom' to '$Name'"
                    if ($PropertyKeys.Count -gt 0) {
                        $UpdateAction += " and update group properties ($PropertyList)"
                        $UpdatedDetail += "; updated group properties ($PropertyList)"
                        $PlannedDetail += "; would update group properties ($PropertyList)"
                    }
                } else {
                    $UpdateAction = 'Update group properties'
                    $UpdatedDetail = "updated group properties ($PropertyList)"
                    $PlannedDetail = "would update group properties ($PropertyList)"
                }
                if ($GroupSynced) {
                    # A15: no PATCH, and no ShouldProcess call. The children are still reconciled
                    # (each reported on the same terms), since nothing was renamed or changed.
                    $SkipWhat = if ($RenameFrom) {
                        "group not renamed from '$RenameFrom' to '$Name'" + $(if ($PropertyKeys.Count -gt 0) { "; group properties ($PropertyList) not updated" } else { '' })
                    } else {
                        "group properties ($PropertyList) not updated"
                    }
                    Write-SyncedGroupSkip -What $SkipWhat
                } elseif ($Caller.ShouldProcess($Name, $UpdateAction)) {
                    try {
                        Set-OERGroup -Id $Gid @UpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail $UpdatedDetail
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        # The group still carries its previous name, not the one the document
                        # declares, so none of its children is reconciled under the new name.
                        if ($RenameFrom) { return }
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail $PlannedDetail
                }
            } elseif (-not $DriftReported) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail 'group properties match'
            }

        }

        # -- Step 2: members ----------------------------------------------------------------
        # A dynamic group's membership is owned by its membershipRule: Microsoft Learn states plainly
        # that a member of a dynamic membership group cannot be added or removed manually. Reconciling
        # here would fire calls Graph rejects and, under -Prune, fire them against rule-derived members.
        # $Cur exists only on the update path (the else branch above); on that path the LIVE type is
        # the only truth that matters, because Set-OERGroup has no parameter and no code path that can
        # convert an existing group's static/dynamic type -- a declared dynamic=true against a live
        # static group is drift (already reported above as a Skipped record), never a prediction of
        # what this run will produce, so it must not also flip the member step into dynamic mode. On
        # the create path there is no live group yet, so whether the document declares dynamic=true is
        # what decides -- New-OERGroup -Dynamic really does produce a dynamic group there.
        $EffectiveIsDynamic = if ($Cur) {
            $CurIsDynamic
        } else {
            (Test-OERDeclaredProperty -Node $Item -Name 'dynamic') -and [bool]$Item.dynamic
        }

        $DeclaredMemberIds = [System.Collections.Generic.List[string]]::new()
        # An omitted 'members' key has always meant "no add-list, but the prune/Extra loop below
        # still runs against whatever it finds" -- that is intentional, existing, tested behavior
        # (an absent collection is not an instruction to leave live state alone; only an EXPLICIT
        # null is). So the add loop is gated on Test-OERDeclaredProperty (skips on both absent and
        # null), while the prune/Extra loop below is gated on the narrower $MembersDeclaredNull so
        # it keeps running when the key is merely absent and only backs off on an explicit null.
        $MembersDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'members'

        if ($EffectiveIsDynamic) {
            $DeclaredMembers = if (Test-OERDeclaredProperty -Node $Item -Name 'members') { @($Item.members) } else { @() }
            foreach ($MRef in $DeclaredMembers) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "member '$MRef' was not reconciled: group '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be added or removed manually. Change the rule (membershipRule) to change the membership"
            }
            if ($DeclaredMembers.Count -eq 0 -and $CurrentMembers.Count -gt 0) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                    -Detail "the $($CurrentMembers.Count) current member(s) were not reconciled: group '$Name' is dynamic and its membership is owned by its membership rule -- members cannot be removed manually, so -Prune does not apply to them"
            }
        } else {
            # A declared member that cannot be resolved carries no id, so it cannot protect its live
            # counterpart from the Extra/prune loop below; while this list is non-empty that loop
            # withholds every candidate (ConvertTo-OERPruneWithheldResult owns the rule).
            $MemberUnresolved = [System.Collections.Generic.List[string]]::new()
            if (Test-OERDeclaredProperty -Node $Item -Name 'members') {
                foreach ($MRef in @($Item.members)) {
                    $Mid = Resolve-OERStructurePrincipal -Reference $MRef
                    if (-not $Mid) {
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Could not resolve principal '$MRef' to an object id."),
                            'PrincipalNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $MRef
                        )
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve member '$MRef'" -ErrorRecord $ErrRec
                        $MemberUnresolved.Add($MRef)
                        continue
                    }
                    $DeclaredMemberIds.Add($Mid)

                    $AlreadyMember = $CurrentMembers | Where-Object { $_.id -eq $Mid }
                    if ($AlreadyMember) {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "member '$MRef' already present"
                    } else {
                        if ($GroupSynced) {
                            Write-SyncedGroupSkip -What "member '$MRef' not added"
                        } elseif ($Caller.ShouldProcess($Name, "Add member '$Mid'")) {
                            try {
                                Add-OERGroupMember -Id $Gid -PrincipalId $Mid -Confirm:$false -ErrorAction Stop
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add member '$MRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "added member '$MRef'"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would add member '$MRef'"
                        }
                    }
                }
            }

            # Extra/prune undeclared current members. Skipped ONLY when 'members' is explicitly null --
            # an omitted key still reconciles against an empty declared set (existing behavior), but an
            # explicit null is a distinct "leave membership alone" signal and must not report every live
            # member as Extra or, worse under -Prune, remove them all.
            if (-not $MembersDeclaredNull) {
                foreach ($CurMember in $CurrentMembers) {
                    $CurId = $CurMember.id
                    if ($DeclaredMemberIds -notcontains $CurId) {
                        $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $MemberUnresolved -Candidate "undeclared member '$CurId'"
                        if ($Withheld) { $Withheld; continue }
                        # A9: a service principal is never pruned from a group. No version before the
                        # typed read saw one, so no earlier document lists one; it is Extra without
                        # -Prune and Skipped with it (ConvertTo-OERPruneWithheldResult owns the rule).
                        $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -ObjectType $CurMember.ObjectType -Candidate "undeclared member '$CurId'" -Prune:$Prune
                        if ($Withheld) { $Withheld; continue }
                        # A15: nothing is removed from a group synchronized from on-premises; the
                        # item's one warning comes first under -Prune.
                        if ($GroupSynced) {
                            if ($Prune) { Write-SyncedGroupWarning }
                            ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Candidate "undeclared member '$CurId'" -SyncedGroup $SyncedGroupName -Prune:$Prune
                            continue
                        }
                        if ($Prune) {
                            $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                            Write-Warning "Sync-OERStructureGroup: $PruneVerb undeclared member '$CurId' from group '$Name'."
                            if ($Caller.ShouldProcess($Name, "Remove undeclared member '$CurId'")) {
                                try {
                                    Remove-OERGroupMember -Id $Gid -PrincipalId $CurId -Confirm:$false -ErrorAction Stop
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    $Caller.WriteError($PSItem)
                                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove member '$CurId': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                    continue
                                }
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed undeclared member '$CurId'"
                            } else {
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove undeclared member '$CurId'"
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "undeclared member '$CurId' (use -Prune to remove)"
                        }
                    }
                }
            }
        }

        # -- Step 2b: owners -----------------------------------------------------------------
        # Owners are NOT rule-derived (unlike members, which are skipped or rule-owned on a dynamic
        # group), so this pass runs on a dynamic group too -- it must not be gated on
        # $EffectiveIsDynamic. The whole pass (add AND Extra/prune) is gated on the 'owners' key being
        # DECLARED (present and non-null): unlike members, an omitted owners key must never reconcile or
        # prune, because a brand-new destructive pass firing on every omitted key would strip the owners
        # off every group in an already-written document on its next -Prune run.
        if (Test-OERDeclaredProperty -Node $Item -Name 'owners') {
            $DeclaredOwnerIds = [System.Collections.Generic.List[string]]::new()
            # Same rule as $MemberUnresolved: an unresolved declared owner withholds every owner
            # candidate in the Extra/prune loop below.
            $OwnerUnresolved = [System.Collections.Generic.List[string]]::new()
            foreach ($ORef in @($Item.owners)) {
                $Oid = Resolve-OERStructurePrincipal -Reference $ORef
                if (-not $Oid) {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve owner '$ORef' to an object id."),
                        'PrincipalNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $ORef
                    )
                    $Caller.WriteError($ErrRec)
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve owner '$ORef'" -ErrorRecord $ErrRec
                    $OwnerUnresolved.Add($ORef)
                    continue
                }
                $DeclaredOwnerIds.Add($Oid)

                $AlreadyOwner = $CurrentOwners | Where-Object { $_.id -eq $Oid }
                if ($AlreadyOwner) {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "owner '$ORef' already present"
                } else {
                    if ($GroupSynced) {
                        Write-SyncedGroupSkip -What "owner '$ORef' not added"
                    } elseif ($Caller.ShouldProcess($Name, "Add owner '$Oid'")) {
                        try {
                            Add-OERGroupMember -Id $Gid -PrincipalId $Oid -AccessType owner -Confirm:$false -ErrorAction Stop
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add owner '$ORef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "added owner '$ORef'"
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would add owner '$ORef'"
                    }
                }
            }

            # Extra/prune undeclared current owners. Microsoft Learn: "Once owners are assigned to a
            # group, the last owner (a user object) of the group cannot be removed" -- note the exact
            # wording, "a user object": Learn scopes the restriction to a USER owner specifically, so a
            # group whose sole remaining owner is a service principal may in fact be removable. This
            # guard is nonetheless DELIBERATELY conservative and counts owners of every type, not just
            # user owners: whether the restriction also applies to a lone service-principal owner is an
            # OPEN question on this PR's live-verification checklist, and narrowing the guard now would
            # encode an unverified assumption into a destructive path. Do NOT make this guard type-aware
            # without first confirming the behaviour against a real tenant -- see the checklist. The
            # number of owners still standing is tracked as removals are applied, and the removal that
            # would leave none is refused with a Skipped record instead of firing a call that may fail.
            # Since A9 an owner the read types servicePrincipal is withheld before this guard and never
            # removed, so the guard decides only for owners of other types or of no type, and a
            # withheld service principal owner counts as one still standing.
            $RemainingOwnerCount = $CurrentOwners.Count
            foreach ($CurOwner in $CurrentOwners) {
                $CurId = $CurOwner.id
                if ($DeclaredOwnerIds -notcontains $CurId) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $OwnerUnresolved -Candidate "undeclared owner '$CurId'"
                    if ($Withheld) { $Withheld; continue }
                    # A9, as for members, and before the last-owner guard: a service principal owner
                    # is never removed, so it stays in $RemainingOwnerCount.
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -ObjectType $CurOwner.ObjectType -Candidate "undeclared owner '$CurId'" -Prune:$Prune
                    if ($Withheld) { $Withheld; continue }
                    # A15, as for members, and before the last-owner guard: nothing is removed from a
                    # group synchronized from on-premises.
                    if ($GroupSynced) {
                        if ($Prune) { Write-SyncedGroupWarning }
                        ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Candidate "undeclared owner '$CurId'" -SyncedGroup $SyncedGroupName -Prune:$Prune
                        continue
                    }
                    if ($Prune) {
                        if ($RemainingOwnerCount -le 1) {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' `
                                -Detail "did not remove owner '$CurId': it is the last remaining owner of group '$Name', and this pass refuses to remove it (this is our own guard, not a Graph rejection). Microsoft Graph's documented restriction names a USER owner specifically, so if this is a service principal it may in fact be removable; this guard is deliberately conservative pending live verification."
                            continue
                        }
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureGroup: $PruneVerb undeclared owner '$CurId' from group '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared owner '$CurId'")) {
                            try {
                                Remove-OERGroupMember -Id $Gid -PrincipalId $CurId -AccessType owner -Confirm:$false -ErrorAction Stop
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove owner '$CurId': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                            $RemainingOwnerCount--
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed undeclared owner '$CurId'"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove undeclared owner '$CurId'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "undeclared owner '$CurId' (use -Prune to remove)"
                    }
                }
            }
        }

        # -- Steps 3-5: eligibility + pimPolicy (PIM chicken-and-egg order) ----------------
        $HasEligibility = (Test-OERDeclaredProperty -Node $Item -Name 'eligibility')
        $HasPimPolicy   = (Test-OERDeclaredProperty -Node $Item -Name 'pimPolicy')

        $TimeBoundEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
        $PermanentEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
        # Declared (principalId, accessType) keys, populated as both eligibility loops below resolve
        # each entry's principal and access type. Consumed by the Extra/prune pass after Step 5.
        $DeclaredEligibilityKeys = [System.Collections.Generic.List[string]]::new()
        # Declared eligibility principals that could not be resolved, fed by BOTH loops below. While
        # it is non-empty the Extra/prune pass withholds every eligibility candidate, since an
        # unresolved entry carries no key to protect its live counterpart with.
        $EligibilityUnresolved = [System.Collections.Generic.List[string]]::new()
        if ($HasEligibility) {
            foreach ($EEntry in @($Item.eligibility)) {
                if (Test-OERDeclaredProperty -Node $EEntry -Name 'durationDays') {
                    $TimeBoundEntries.Add($EEntry)
                } else {
                    $PermanentEntries.Add($EEntry)
                }
            }
        }

        # Nested helper: find the live eligibility schedule instance for one (principal, accessType)
        # pair. Matching on the pair -- not on principal id alone -- is what lets an owner eligibility
        # coexist with a member one and what makes a member/owner switch visible to the diff.
        # A Graph instance that omits accessId is treated as a member eligibility.
        function Get-CurrentEligibility {
            param([object[]]$Instances, [string]$PrincipalId, [string]$AccessType)
            foreach ($Instance in @($Instances)) {
                if ([string]$Instance.principalId -ne $PrincipalId) { continue }
                $InstanceAccess = if ($Instance.accessId) { [string]$Instance.accessId } else { 'member' }
                if ($InstanceAccess -eq $AccessType) { return $Instance }
            }
            return $null
        }

        # Whether step 3 below wrote an eligibility for this group in THIS run. That request onboards
        # the group to PIM for Groups, so step 4 no longer asks whether the group uses PIM for Groups
        # before it writes the policy: the onboarding its warning would announce has already happened.
        # Set only on a SUCCESSFUL write -- a refused request, or one skipped under -WhatIf, onboards
        # nothing.
        $EligibilityWrittenThisRun = $false

        # The permanent-eligibility setting step 4 of this item would have written, by access type, when
        # its gate declined the write (under -WhatIf). Step 5's plan reads the live policy, which that
        # unapplied write has not changed yet, so it decides on the value step 4 WOULD leave instead.
        # Step 5's plan also records an access type here as allowing permanent eligibility once it has
        # planned the warning for it, since the real run's first entry opens the policy for the rest.
        $PlannedPermanentAllowed = @{}

        # ONE wait budget per group item (at most 30 s of waiting in total: 2 + 4 + 8 + 16), shared by
        # step 3 (a time-bound eligibility on a new group), step 4 (the pimPolicy of the member and the
        # owner access type) and step 5 (a permanent eligibility on a new group) -- not one budget per
        # step, entry or access type. Consumed only for a group THIS run created: all three steps wait
        # for the same thing, Microsoft Graph and PIM for Groups coming to know a brand-new group, and
        # a group that already existed never waits.
        $ReplicationRetryDelays = [System.Collections.Generic.Queue[int]]::new([int[]]@(2, 4, 8, 16))

        # Step 3: time-bound eligibility
        foreach ($EEntry in $TimeBoundEntries) {
            $EPrinRef = $EEntry.principal
            $EPrinId  = Resolve-OERStructurePrincipal -Reference $EPrinRef
            if (-not $EPrinId) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve eligibility principal '$EPrinRef' to an object id."),
                    'PrincipalNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $EPrinRef
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve eligibility principal '$EPrinRef'" -ErrorRecord $ErrRec
                $EligibilityUnresolved.Add($EPrinRef)
                continue
            }

            $EAccessType = if ((Test-OERDeclaredProperty -Node $EEntry -Name 'accessType') -and $EEntry.accessType) { [string]$EEntry.accessType } else { 'member' }
            $DeclaredEligibilityKeys.Add(('{0}|{1}' -f $EPrinId, $EAccessType).ToLowerInvariant())
            $CurrentElig = Get-CurrentEligibility -Instances $CurrentEligibles -PrincipalId $EPrinId -AccessType $EAccessType
            $EChange = Resolve-OERGroupEligibilityChange -Declared $EEntry -Current $CurrentElig

            if (-not $EChange.Changed) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "eligibility for '$EPrinRef' ($($EChange.AccessType)) already matches"
                continue
            }

            # A15: no request, no wait and no ShouldProcess call for a group synchronized from
            # on-premises.
            if ($GroupSynced) {
                Write-SyncedGroupSkip -What "time-bound $($EChange.AccessType) eligibility for '$EPrinRef' not set ($($EChange.Detail))"
                continue
            }

            $EAction = if ($EChange.Reason -eq 'Absent') { 'adminAssign' } else { 'adminUpdate' }
            if ($Caller.ShouldProcess($Name, "Add time-bound $($EChange.AccessType) eligibility for '$EPrinId' ($($EChange.DurationDays) days)")) {
                if ($CreatedThisRun) {
                    # A group THIS RUN created may not be known to PIM for Groups yet: the first
                    # eligibility request can be answered 404 ResourceNotFound while the group's replicas
                    # do not agree, and for such a group that is replication, not a failed write. The
                    # request goes through Send-OERNewGroupEligibilityRequest, which declares the 404 to
                    # the transport and hands it back as a silent $null -- Add-OERGroupEligibility cannot
                    # do that, and a 404 thrown and then caught here would still have left its records in
                    # the caller's -ErrorVariable, since the engine collects them as they are raised,
                    # before any catch runs. A $null answer is waited on from the one shared
                    # $ReplicationRetryDelays budget and asked again. So is an ACCEPTED request whose
                    # status is Failed: the replication window has a second phase in which Graph takes
                    # the request (201) and fails it at once, the 201 body already saying Failed, while
                    # the same request minutes later is Provisioned (measured live 2026-10-03). Any other
                    # status is the applied request. Every throw -- a refusal (403), a throttle that
                    # outlasted the transport's own retries, a 5xx, a ResourceNotFound that is not a
                    # 404 -- is reported as itself and never waited on. A group that already existed
                    # takes the cmdlet below and never waits, a 404 or a Failed status included: there
                    # a Failed status is Add-OERGroupEligibility's own EligibilityRequestFailed error,
                    # which reaches the catch below like any other failure of the call.
                    $EligibilityApplied = $false
                    $Waits = 0
                    while ($true) {
                        $EligibilityRequest = $null
                        try {
                            $EligibilityRequest = Send-OERNewGroupEligibilityRequest -GroupId $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -DurationDays $EChange.DurationDays -Action $EAction
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add eligibility for '$EPrinRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            break
                        }
                        # Test-OERScheduleRequestFailed owns which statuses are the Failed family; the
                        # transport hands back a hashtable, read by key.
                        if ($null -ne $EligibilityRequest -and -not (Test-OERScheduleRequestFailed -Status ([string]$EligibilityRequest.status))) {
                            $EligibilityApplied = $true
                            break
                        }
                        if ($ReplicationRetryDelays.Count -eq 0) {
                            # ResourceNotFound, the code Graph gives the 404, whichever answer used up the
                            # budget: an accepted request answered Failed is the same replication. No retry
                            # count: the budget is shared, so a second entry that finds it spent would
                            # otherwise read "after 0 retries".
                            $Message = "eligibility for '$EPrinRef' ($($EChange.AccessType)) not applied: for group '$Name', created in this run, Microsoft Graph answered 404 ResourceNotFound, or accepted the request but answered status Failed, every time within the 30-second wait. A new group can take a while to be known to PIM for Groups (replication delay); re-running the same document usually applies it."
                            $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new($Message),
                                'ResourceNotFound',
                                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                                $Name)
                            $Caller.WriteError($ErrRec)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail $Message -ErrorRecord $ErrRec
                            break
                        }
                        $Delay = $ReplicationRetryDelays.Dequeue()
                        $Waits++
                        $NotReady = if ($null -eq $EligibilityRequest) { 'answers 404 (not known to PIM for Groups yet)' } else { 'was accepted but answered status Failed (not ready in PIM for Groups yet)' }
                        Write-Verbose "Sync-OERStructureGroup: eligibility for '$EPrinRef' ($($EChange.AccessType)) on new group '$Name' $NotReady; retry $Waits in $Delay s."
                        Start-Sleep -Seconds $Delay
                    }
                    # A bare continue inside the loop above would continue the WHILE, not this foreach.
                    if (-not $EligibilityApplied) { continue }
                } else {
                    try {
                        # Discarded: the request object Add-OERGroupEligibility returns is not a result row,
                        # and this handler's output IS Invoke-OERStructure's result list. Its status is
                        # not lost: a request Graph accepted but answered Failed is the cmdlet's
                        # EligibilityRequestFailed error, which -ErrorAction Stop turns into a throw the
                        # catch reports as Failed, so a write that granted nothing never sets
                        # $EligibilityWrittenThisRun and never reports Updated.
                        $null = Add-OERGroupEligibility -Id $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -DurationDays $EChange.DurationDays -Action $EAction -Confirm:$false -ErrorAction Stop
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add eligibility for '$EPrinRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }
                }
                $EligibilityWrittenThisRun = $true
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "set time-bound $($EChange.AccessType) eligibility for '$EPrinRef' ($($EChange.DurationDays) days): $($EChange.Detail)"
            } else {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set time-bound $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            }
        }

        # -- Step 4: pimPolicy (per access type: member and/or owner) -----------------------
        if ($HasPimPolicy) {
            $Pp = $Item.pimPolicy

            # Which access types the document declares with a usable policy block.
            $HasMember = Test-OERDeclaredProperty -Node $Pp -Name 'member'
            $HasOwner  = Test-OERDeclaredProperty -Node $Pp -Name 'owner'

            # Whether the NESTED form was used at all. A key present with an explicit null still
            # selects the nested form -- it just declares no policy for that access type, exactly as
            # omitting the key inside a nested block would. Without this second question a
            # "member": null falls through to the flat back-compat branch and the whole pimPolicy
            # object is misread as a member policy.
            $UsesNestedForm = $HasMember -or $HasOwner -or
                (Test-OERDeclaredNull -Node $Pp -Name 'member') -or
                (Test-OERDeclaredNull -Node $Pp -Name 'owner')

            $DesiredByAccess = [ordered]@{}
            if ($UsesNestedForm) {
                if ($HasMember) { $DesiredByAccess['member'] = $Pp.member }
                if ($HasOwner)  { $DesiredByAccess['owner']  = $Pp.owner }
            } else {
                # Flat back-compat form = the member policy.
                $DesiredByAccess['member'] = $Pp
            }

            # The wait budget is $ReplicationRetryDelays, declared before step 3: ONE per group item,
            # shared by the member and owner access types below and by the eligibility waits of steps
            # 3 and 5 -- not one budget each.

            # Whether this item has already asked Test-OERGroupPimInUse. Asked at most ONCE per item,
            # at the first access type whose diff is Changed: one question and one warning cover both
            # access types of the same group.
            $PimUsageAsked = $false

            foreach ($AccessType in $DesiredByAccess.Keys) {
                # A15: PIM for Groups cannot manage a group synchronized from on-premises, so its
                # policy is neither read nor written -- no approver lookup, no wait, no
                # Test-OERGroupPimInUse.
                if ($GroupSynced) {
                    Write-SyncedGroupSkip -What "pimPolicy ($AccessType) not applied (PIM for Groups cannot manage a group synchronized from on-premises, so its policy is not read)"
                    continue
                }
                $Declared = $DesiredByAccess[$AccessType]

                # Declared approver names are resolved to object ids BEFORE the diff, so the diff
                # compares ids with ids (a UPN or a group name never equals a live approver id).
                # Three outcomes, three records, one Failed row each and no read or write of this
                # access type's policy: an ambiguous name is AmbiguousApproverName (the resolver's text
                # names the candidate ids), only an approver that matches nothing (ApproverUnresolved)
                # is ApproverNotFound, and anything else -- a 403, an exhausted 429, a 5xx -- is not
                # evidence that the approver is missing, so it is published as itself.
                try {
                    $Declared = Resolve-OERDeclaredApprover -Declared $Declared
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $ErrRec = $PSItem
                    if (Test-OERAmbiguousNameError -Record $PSItem) {
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Could not resolve an approver declared in pimPolicy ($AccessType) of group '$Name': $($PSItem.Exception.Message)", $PSItem.Exception),
                            'AmbiguousApproverName',
                            [System.Management.Automation.ErrorCategory]::InvalidArgument,
                            $PSItem.TargetObject)
                    } elseif (([string]$PSItem.FullyQualifiedErrorId).StartsWith('ApproverUnresolved', [System.StringComparison]::Ordinal)) {
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("Could not resolve an approver declared in pimPolicy ($AccessType) of group '$Name': $($PSItem.Exception.Message)", $PSItem.Exception),
                            'ApproverNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $Name)
                    }
                    $Caller.WriteError($ErrRec)
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' `
                        -Detail "pimPolicy ($AccessType) not applied: could not resolve an approver: $($PSItem.Exception.Message)" `
                        -ErrorRecord $ErrRec
                    continue
                }

                # A group THIS RUN created may not have this access type's policy listed yet: its policy
                # assignments can take a moment to appear after creation (replication delay). ASK FIRST
                # whether there is one -- the Get-OERInventory pattern -- rather than retrying the policy
                # read. Get-OERPimGroupPolicyId answers a silent $null while nothing is listed, so the
                # poll leaves nothing behind; a read through Get-OERGroupPimPolicy -ErrorAction Stop
                # deposits its PimPolicyNotFound records in the caller's -ErrorVariable on every attempt
                # (the engine collects them from the error stream before any catch here runs), so a run
                # that ended Updated still handed the caller a list of errors. A 404 ResourceNotFound is
                # the answer of a group PIM does not know yet (measured live), so the poll asks with
                # -NotFoundAsUnlisted: a 404 comes back as the same silent $null and is waited on, never
                # raised. Once an id is listed, the policy is read HERE through
                # Get-OERListedGroupPimPolicy, which declares the 404 the same way: a listed policy can
                # still answer 404 a second later (measured live, replicas that do not agree yet), and a
                # 404 there starts the poll over from the listing. Both spend the one shared
                # $ReplicationRetryDelays budget, until the policy is read or the budget is empty. Every
                # other throw (403, 429, ...) from either call is a refusal, not replication: the wait
                # stops at once and the read below reports as for any group. A group that already
                # existed never polls and never sleeps, a 404 included: its missing policy is a fact,
                # not a timing issue.
                $CurrentPolicy = $null
                if ($CreatedThisRun) {
                    $PollRefused = $false
                    $Waits = 0
                    while ($true) {
                        $ListedPolicyId = $null
                        try {
                            $ListedPolicyId = Get-OERPimGroupPolicyId -GroupId $Gid -AccessType $AccessType -NotFoundAsUnlisted
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $PollRefused = $true
                            Write-Verbose "Sync-OERStructureGroup: could not ask whether pimPolicy ($AccessType) of new group '$Name' is listed ($($PSItem.Exception.Message)); reading it directly."
                            break
                        }
                        if ($ListedPolicyId) {
                            try {
                                $CurrentPolicy = Get-OERListedGroupPimPolicy -GroupId $Gid -PolicyId $ListedPolicyId -AccessType $AccessType
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $PollRefused = $true
                                Write-Verbose "Sync-OERStructureGroup: could not read the listed pimPolicy ($AccessType) of new group '$Name' ($($PSItem.Exception.Message)); reading it directly."
                                break
                            }
                            if ($CurrentPolicy) { break }
                        }
                        if ($ReplicationRetryDelays.Count -eq 0) { break }
                        $Delay = $ReplicationRetryDelays.Dequeue()
                        $Waits++
                        $NotYet = if ($ListedPolicyId) { 'is listed but its read answers 404' } else { 'is not listed yet' }
                        Write-Verbose "Sync-OERStructureGroup: pimPolicy ($AccessType) of new group '$Name' $NotYet; retry $Waits in $Delay s."
                        Start-Sleep -Seconds $Delay
                    }
                    if (-not $PollRefused -and -not $CurrentPolicy) {
                        # No retry count here: the budget is shared, so an owner that finds it spent by
                        # member would otherwise read "after 0 retries".
                        # No advice about eligibility: Graph lists a group's policies whether or not it was
                        # ever onboarded, and the first policy update onboards it (Microsoft Graph
                        # documentation, "Onboarding groups to PIM for Groups"), so a policy not listed or
                        # not readable here is replication and a re-run is the remedy, whatever the
                        # document declares. Always PimPolicyNotFound, a 404 on the read included: it was
                        # never refused, so PimPolicyReadFailed would name the wrong cause.
                        $Message = "pimPolicy ($AccessType) not applied: Microsoft Graph does not list a PIM-for-groups policy for '$AccessType' access on group '$Name', created in this run, within the 30-second wait. A new group's policies can take a while to be listed (replication delay); re-running the same document usually applies them."
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($Message),
                            'PimPolicyNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $Name)
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail $Message -ErrorRecord $ErrRec
                        continue
                    }
                }

                # Read the current policy for this access type, unless the wait above already did
                # (best-effort -- Graph may not list it, or the read may be refused). A failure leaves
                # $CurrentPolicy null, the diff treats every declared field as changed, and the Set call
                # reports its own error. Never retried here: the wait above is the only one.
                if (-not $CurrentPolicy) {
                    try {
                        $CurrentPolicy = Get-OERGroupPimPolicy -Id $Gid -AccessType $AccessType -ErrorAction Stop
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                    }
                }

                $Change = Resolve-OERGroupPimPolicyChange -Declared $Declared -Current $CurrentPolicy
                if (-not $Change.Changed) {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "pimPolicy ($AccessType) already matches"
                    continue
                }

                # Microsoft Graph lists a group's PIM-for-Groups policies whether or not the group was
                # ever used with PIM for Groups, and this write onboards a group that was not, which
                # cannot be undone. So before the FIRST changed write of the item -- and before its
                # ShouldProcess gate, so -WhatIf shows it -- ask Test-OERGroupPimInUse, the single
                # owner of that rule, and WARN when the group was not found to use PIM for Groups. Never
                # blocks and never changes a row: the document asked for this policy, and a group
                # onboarded on purpose is the normal case (ruling R3,
                # docs/development/rationale.md#pim-in-use-criterion). Not asked for a group this run
                # created (it has no PIM history to protect) or once step 3 of this item wrote an
                # eligibility (that already onboarded it). The eligibility count is what this item
                # READ, which it did only when eligibility is declared; 0 otherwise.
                # A not-in-use group the criterion also reports as not Manageable (ResourceTypeNotSupported
                # -- a dynamic or on-premises-synced group) cannot be onboarded at all, so the "onboards
                # it ... cannot be undone" wording would be self-contradictory; that case gets its own
                # warning instead. Decided from Test-OERGroupPimInUse's Manageable property, the stable
                # signal for that case, never by matching the text of Reason.
                if (-not $PimUsageAsked) {
                    $PimUsageAsked = $true
                    if (-not $CreatedThisRun -and -not $EligibilityWrittenThisRun) {
                        $KnownEligibility = if ($NeedElig) { @($CurrentEligibles | Where-Object { $null -ne $_ }).Count } else { 0 }
                        try {
                            $Usage = Test-OERGroupPimInUse -GroupId $Gid -EligibilityCount $KnownEligibility
                            if (-not $Usage.InUse) {
                                if (-not $Usage.Manageable) {
                                    Write-Warning "Sync-OERStructureGroup: PIM for Groups cannot manage group '$Name' (ResourceTypeNotSupported), so its pimPolicy cannot be applied."
                                } else {
                                    Write-Warning "Sync-OERStructureGroup: group '$Name' was not found to use PIM for Groups ($($Usage.Reason)); applying its pimPolicy onboards it to PIM for Groups, which cannot be undone (Microsoft Graph documentation, 'Onboarding groups to PIM for Groups')."
                                }
                            }
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            Write-Warning "Sync-OERStructureGroup: could not determine whether group '$Name' uses PIM for Groups ($($PSItem.Exception.Message)); if it does not, applying its pimPolicy onboards it, which cannot be undone."
                        }
                    }
                }

                # The diff resolves the MFA / authentication context pair itself and sends the
                # reconciled rule, so Set-OERGroupPimPolicy, called with those parameters, has nothing
                # left to resolve and never writes its own warning about the pair. The warning is
                # written here instead, before the gate and in EVERY mode (Ruling R5), with the text the
                # cmdlet writes for a direct call: the plan shows it, and a real run writes it once.
                # The policy id is the one the read above gave; without a read policy the item names it.
                # The warning states the diff's decision: Set-OERGroupPimPolicy can still refuse the
                # call after it (an authentication context the tenant does not define or has not
                # published, a failed policy lookup, an unreadable approval rule), and the Failed row
                # then shows that nothing was changed.
                if ($Change.ConflictReason) {
                    $ConflictTarget = if ($CurrentPolicy -and $CurrentPolicy.PolicyId) { "Policy '$($CurrentPolicy.PolicyId)'" } else { "pimPolicy ($AccessType) of group '$Name'" }
                    Write-Warning "${ConflictTarget}: $($Change.ConflictReason)"
                }

                if ($Caller.ShouldProcess($Name, "Set PIM policy ($AccessType): $($Change.Changes -join '; ')")) {
                    try {
                        $SetSplat = $Change.SetParams
                        $PimResult = Set-OERGroupPimPolicy -Id $Gid -AccessType $AccessType @SetSplat -Confirm:$false -ErrorAction Stop
                        if ($null -ne $PimResult -and ($PimResult.PSObject.Properties.Name -contains 'Applied') -and (-not $PimResult.Applied)) {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "pimPolicy ($AccessType) only partially applied; failed rules: $(@($PimResult.FailedRules) -join ', ')"
                        } else {
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "pimPolicy ($AccessType) set: $($Change.Changes -join '; ')"
                        }
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "pimPolicy ($AccessType) update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set pimPolicy ($AccessType): $($Change.Changes -join '; ')"
                    # Not applied, so the live policy still has its old permanent-eligibility setting.
                    # Step 5's plan decides on the setting this change would have left (see step 5).
                    if ($Change.SetParams.ContainsKey('AllowPermanentEligibility')) {
                        $PlannedPermanentAllowed[$AccessType] = [bool]$Change.SetParams.AllowPermanentEligibility
                    }
                }
            }
        }

        # Step 5: permanent eligibility
        foreach ($EEntry in $PermanentEntries) {
            $EPrinRef = $EEntry.principal
            $EPrinId  = Resolve-OERStructurePrincipal -Reference $EPrinRef
            if (-not $EPrinId) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve eligibility principal '$EPrinRef' to an object id."),
                    'PrincipalNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $EPrinRef
                )
                $Caller.WriteError($ErrRec)
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "could not resolve eligibility principal '$EPrinRef'" -ErrorRecord $ErrRec
                $EligibilityUnresolved.Add($EPrinRef)
                continue
            }

            $EAccessType = if ((Test-OERDeclaredProperty -Node $EEntry -Name 'accessType') -and $EEntry.accessType) { [string]$EEntry.accessType } else { 'member' }
            $DeclaredEligibilityKeys.Add(('{0}|{1}' -f $EPrinId, $EAccessType).ToLowerInvariant())
            $CurrentElig = Get-CurrentEligibility -Instances $CurrentEligibles -PrincipalId $EPrinId -AccessType $EAccessType
            $EChange = Resolve-OERGroupEligibilityChange -Declared $EEntry -Current $CurrentElig

            if (-not $EChange.Changed) {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Unchanged' -Detail "permanent eligibility for '$EPrinRef' ($($EChange.AccessType)) already matches"
                continue
            }

            # A15: no policy read (the -WhatIf plan's included), no request, no wait and no
            # ShouldProcess call for a group synchronized from on-premises.
            if ($GroupSynced) {
                Write-SyncedGroupSkip -What "permanent $($EChange.AccessType) eligibility for '$EPrinRef' not set ($($EChange.Detail))"
                continue
            }

            $EAction = if ($EChange.Reason -eq 'Absent') { 'adminAssign' } else { 'adminUpdate' }
            # A permanent eligibility may need the group's policy opened to allow permanent eligible
            # assignments, which affects ALL eligibility of that access type, and Add-OERGroupEligibility
            # reads that (Get-OERGroupPermanentEligibilityState) and warns about it before its own gate.
            # Under -WhatIf the engine never calls that cmdlet, so the plan would not show the warning a
            # real run gives: the same read is made here, before the gate, and the cmdlet's own warning
            # written when the policy must be opened. A failed read writes nothing, as in the cmdlet.
            # The plan decides on the state step 4 WOULD leave: when step 4 of this item had a changed
            # policy for this access type that sets allowPermanentEligibility and its gate declined it,
            # that value stands in for the read's PermanentAllowed (true: no warning; false: the warning
            # when the policy is listed), since a real run applies it before the cmdlet reads the policy.
            # Otherwise the read decides. Whether the policy is listed (HasPolicy) always comes from the
            # read. Once the warning is planned for an access type, that access type is recorded as
            # allowing permanent eligibility, so a later permanent entry of the same access type plans
            # none: in a real run the first entry's Add-OERGroupEligibility opens the policy, and the
            # later ones find it open. Only under -WhatIf -- a real run calls the cmdlet, which writes
            # it, and a second copy here would warn twice. Under -WhatIf a group this run would create is
            # never reached here (its creation is skipped and the handler returns), so the group always
            # exists already.
            if ($WhatIfPreference) {
                $PermanentState = $null
                try {
                    $PermanentState = Get-OERGroupPermanentEligibilityState -GroupId $Gid -AccessType $EChange.AccessType
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    Write-Verbose "Sync-OERStructureGroup: could not read whether the $($EChange.AccessType) policy of group '$Name' allows permanent eligibility ($($PSItem.Exception.Message)); the plan cannot say whether it would be opened."
                }
                $PermanentAllowed = [bool]$PermanentState.PermanentAllowed
                if ($PlannedPermanentAllowed.ContainsKey([string]$EChange.AccessType)) {
                    $PermanentAllowed = $PlannedPermanentAllowed[[string]$EChange.AccessType]
                }
                if ($PermanentState -and $PermanentState.HasPolicy -and -not $PermanentAllowed) {
                    Write-Warning "This eligibility requires opening the PIM-for-groups policy for group '$Gid' ($($EChange.AccessType) access) to allow PERMANENT eligible assignments, which affects ALL $($EChange.AccessType) eligibility for this group."
                    # The policy this entry opens in a real run stays open for the next entry.
                    $PlannedPermanentAllowed[[string]$EChange.AccessType] = $true
                }
            }
            if ($Caller.ShouldProcess($Name, "Add permanent $($EChange.AccessType) eligibility for '$EPrinId'")) {
                if ($CreatedThisRun) {
                    # A group THIS RUN created may not be known to PIM for Groups yet. Unlike step 3 this
                    # step keeps Add-OERGroupEligibility, whose permanent pre-check and policy self-heal
                    # (Get-OERGroupPermanentEligibilityState, Enable-OERGroupPermanentEligibility) the
                    # engine relies on, and the cmdlet cannot declare a 404 to the transport: a 404 thrown
                    # inside it and caught here would leave its records in the caller's -ErrorVariable.
                    # So wait FIRST, silently, until Graph lists the group's policy for this access type
                    # AND that policy answers its read -- the readiness signal step 4 uses: the listing
                    # asked with -NotFoundAsUnlisted, the read through Get-OERListedGroupPimPolicy, both
                    # declaring the 404 so it comes back as the same quiet $null -- and then call the
                    # cmdlet once. Listed is not enough: a policy listed a second earlier can answer its
                    # read with 404 (measured live 2026-09-28), and the cmdlet's pre-check reads that
                    # same policy, proceeds on a failed read, never opens the policy and has the POST
                    # refused. A 404 on the read starts over from the listing, as in step 4. The wait
                    # spends the one shared $ReplicationRetryDelays budget. A throw from either call is a
                    # refusal, not replication: it is scrubbed, logged and ends the poll, and the cmdlet
                    # is called as for any group (as step 4 does). A 404 from the cmdlet itself after the
                    # policy was read is reported as it is today. The request object the cmdlet returns
                    # is read for its Status: Graph can accept a new group's request and fail it at once
                    # (measured live 2026-10-03, see step 3), so a Failed status takes the next wait from
                    # the same budget and starts over from the poll. Any other status is the applied
                    # request. For this call only, the cmdlet is told through
                    # $script:_OERGroupEligibilityFailedIsReplication not to report a Failed status as
                    # its EligibilityRequestFailed error (see the call below). A group that already
                    # existed never polls, and there a Failed status is the cmdlet's error, reported by
                    # the catch of its own call.
                    $PermanentApplied = $false
                    $PermanentNotReady = $false
                    # For the GroupNotOnboarded message below: whether Add-OERGroupEligibility was called
                    # for this entry at all, and whether the policy allowed permanent eligibility as the
                    # poll read it just before the FIRST call -- $true or $false only when the poll read a
                    # real boolean, $null (unknown) when the poll was refused or read none.
                    $PermanentAttempted = $false
                    $AllowedBefore = $null
                    # Whether an EARLIER call of this entry was sent and answered. Set on the statement
                    # directly after the call's try/catch/finally, which only a call that returned
                    # reaches (its catch always leaves the loop), and the loop calls again only after a
                    # request answered status Failed: so a later call that throws knows that a request
                    # before it was accepted and answered Failed -- a request that may have opened the
                    # group's policy (see the catch of the call below).
                    $EarlierRequestSent = $false
                    # The after-attempts read and its outcome, in ONE place for the two ways this wait
                    # ends after a call was made: the GroupNotOnboarded message below, and the catch of a
                    # LATER call that throws after an earlier call was sent and answered Failed. It says
                    # whether the group's policy was opened for this entry, since Add-OERGroupEligibility
                    # opens it to allow permanent eligibility before its request and has no rollback. It
                    # reads the policy ONCE more, with the poll's own functions (no wait, no budget), and
                    # compares that with $AllowedBefore; invoked with &, it reads $Gid, $EChange, $Name
                    # and $AllowedBefore from this handler's scope as they stand then, and returns ONE
                    # string, the sentence group with no leading space. A read that is refused, unlisted,
                    # answers 404 or reads no boolean is UNKNOWN, and an unknown is never reported as "not
                    # opened"; a refused read is scrubbed and logged here and never published. Six
                    # outcomes, decided in this order: after-read unknown; after-read closed, either "not
                    # left open" or -- when the poll read it closed just before the first request, which
                    # would then have opened it -- a read that may be out of date, since it can come from
                    # a replica that has not seen the open; before-state unknown; already open before;
                    # opened and still open. The close command comes from Get-OERGroupPimPolicyCloseAdvice,
                    # as in Add-OERGroupEligibility.
                    $PermanentPolicyAfterAttempts = {
                        $AllowedAfter = $null
                        $AfterPolicyId = $null
                        try {
                            $AfterPolicyId = Get-OERPimGroupPolicyId -GroupId $Gid -AccessType $EChange.AccessType -NotFoundAsUnlisted
                            if ($AfterPolicyId) {
                                $AfterPolicy = Get-OERListedGroupPimPolicy -GroupId $Gid -PolicyId $AfterPolicyId -AccessType $EChange.AccessType
                                if ($null -ne $AfterPolicy -and $AfterPolicy.AllowPermanentEligibility -is [bool]) {
                                    $AllowedAfter = [bool]$AfterPolicy.AllowPermanentEligibility
                                }
                            }
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            Write-Verbose "Sync-OERStructureGroup: could not read the $($EChange.AccessType) policy of new group '$Name' after its permanent eligibility requests ($($PSItem.Exception.Message)); whether it was opened is not known."
                        }
                        $CloseAdvice = Get-OERGroupPimPolicyCloseAdvice -GroupId $Gid -AccessType $EChange.AccessType
                        if ($null -eq $AllowedAfter) {
                            "Its PIM-for-groups policy for '$($EChange.AccessType)' access may have been opened to allow permanent eligibility before the request was sent, and it could not be read afterwards. If it allows permanent eligibility, $CloseAdvice"
                        } elseif (-not $AllowedAfter) {
                            if ($false -eq $AllowedBefore) {
                                # Closed before the first request, which would have opened it, and closed
                                # again a few seconds later: that read may come from a replica that has
                                # not seen the open, so it is never taken for "not left open".
                                "Its PIM-for-groups policy for '$($EChange.AccessType)' access reads as not allowing permanent eligibility after the requests, but the first request would have opened it, so that read may be out of date. If it allows permanent eligibility, $CloseAdvice"
                            } else {
                                "Its PIM-for-groups policy for '$($EChange.AccessType)' access does not allow permanent eligibility as read after the requests, so it was not left open."
                            }
                        } elseif ($null -eq $AllowedBefore) {
                            "PIM-for-groups policy '$AfterPolicyId' allows permanent eligibility after the requests and may have been opened for them, since whether it allowed it before the first request is not known. The policy is open; $CloseAdvice"
                        } elseif ($AllowedBefore) {
                            "Its PIM-for-groups policy for '$($EChange.AccessType)' access already allowed permanent eligibility before the first request, so it was not opened for it."
                        } else {
                            "PIM-for-groups policy '$AfterPolicyId' had been opened to allow permanent eligibility before the request was sent. The policy is still open; $CloseAdvice"
                        }
                    }
                    $Waits = 0
                    while ($true) {
                        $PollRefused = $false
                        $ListedPolicy = $null
                        while ($true) {
                            $ListedPolicyId = $null
                            try {
                                $ListedPolicyId = Get-OERPimGroupPolicyId -GroupId $Gid -AccessType $EChange.AccessType -NotFoundAsUnlisted
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $PollRefused = $true
                                Write-Verbose "Sync-OERStructureGroup: could not ask whether the $($EChange.AccessType) policy of new group '$Name' is listed ($($PSItem.Exception.Message)); adding the permanent eligibility for '$EPrinRef' directly."
                                break
                            }
                            if ($ListedPolicyId) {
                                try {
                                    $ListedPolicy = Get-OERListedGroupPimPolicy -GroupId $Gid -PolicyId $ListedPolicyId -AccessType $EChange.AccessType
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    $PollRefused = $true
                                    Write-Verbose "Sync-OERStructureGroup: could not read the listed $($EChange.AccessType) policy of new group '$Name' ($($PSItem.Exception.Message)); adding the permanent eligibility for '$EPrinRef' directly."
                                    break
                                }
                                if ($ListedPolicy) { break }
                            }
                            if ($ReplicationRetryDelays.Count -eq 0) { break }
                            $Delay = $ReplicationRetryDelays.Dequeue()
                            $Waits++
                            $NotYet = if ($ListedPolicyId) { 'is listed but its read answers 404' } else { 'is not listed yet' }
                            Write-Verbose "Sync-OERStructureGroup: the $($EChange.AccessType) policy of new group '$Name' $NotYet, so its permanent eligibility for '$EPrinRef' waits; retry $Waits in $Delay s."
                            Start-Sleep -Seconds $Delay
                        }
                        if (-not $PollRefused -and -not $ListedPolicy) {
                            $PermanentNotReady = $true
                            break
                        }
                        $PermanentRequest = $null
                        # The before-state is the first call's only: a later poll reads the policy the
                        # first call may already have opened.
                        if (-not $PermanentAttempted) {
                            $PermanentAttempted = $true
                            if ($null -ne $ListedPolicy -and $ListedPolicy.AllowPermanentEligibility -is [bool]) {
                                $AllowedBefore = [bool]$ListedPolicy.AllowPermanentEligibility
                            }
                        }
                        try {
                            # For this one call, a Failed status is replication THIS handler owns, so the
                            # cmdlet must not report it as its EligibilityRequestFailed error: a record the
                            # cmdlet writes lands in the caller's -ErrorVariable even when it is caught
                            # here (measured: the ActionPreferenceStopException and the record both stay),
                            # and a run that ends Updated would still hand the caller errors. The flag is
                            # set nowhere else and reset in the finally below, on every way out.
                            $script:_OERGroupEligibilityFailedIsReplication = $true
                            # Kept, not discarded: its Status decides. It is still not a result row.
                            $PermanentRequest = Add-OERGroupEligibility -Id $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -Action $EAction -Confirm:$false -ErrorAction Stop
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            # The caught record is published as itself, as for any group, unless an
                            # EARLIER call of this entry was sent and answered Failed. That request may
                            # have opened the group's policy -- the cmdlet opens it before its request and
                            # has no rollback, and the EligibilityRequestFailed that would have said so is
                            # not written for this handler's replication (see the flag above) -- while this
                            # later call opened nothing, so its error carries no advice and the open policy
                            # would go unmentioned. So the after-attempts read runs and its statement is
                            # appended to the caught message, in a NEW record with the caught record's own
                            # error id, category and target (no InnerException: only the message is
                            # reused). The read runs BEFORE $Caller.WriteError, so a caller under
                            # -ErrorAction Stop, which that write stops, still gets it. A
                            # PolicyOpenedButGrantFailed already carries the advice for the policy that call
                            # opened, and is published as itself.
                            $Published = $PSItem
                            if ($EarlierRequestSent) {
                                # The caught record's own error id: its FullyQualifiedErrorId without the
                                # suffix PowerShell appends for the command that wrote it -- ',' and the
                                # implementing type's full name for a compiled cmdlet, ',' and the name for
                                # any other command that has a name, and none when there is no command (the
                                # empty suffix here, which strips nothing) -- stripped only when the id ends
                                # with it. That check is what keeps the id whole where PowerShell appended
                                # no suffix for a command it does record: an anonymous [CmdletBinding()]
                                # scriptblock has an empty name, so its record reads '<id>' alone (measured)
                                # while the suffix computed here is ','. Never the first comma segment: an
                                # error id can itself contain a comma (a thrown string, for example). Both
                                # comparisons are Ordinal: the suffix PowerShell appends is the very string read
                                # here, and the cmdlet writes PolicyOpenedButGrantFailed in exactly that
                                # spelling, so any other spelling is another record and gets the read.
                                $CaughtId = [string]$PSItem.FullyQualifiedErrorId
                                $CaughtCommand = $PSItem.InvocationInfo.MyCommand
                                $CaughtSuffix = if ($CaughtCommand -is [System.Management.Automation.CmdletInfo]) {
                                    ',' + $CaughtCommand.ImplementingType.FullName
                                } elseif ($null -ne $CaughtCommand) {
                                    ',' + $CaughtCommand.Name
                                } else {
                                    ''
                                }
                                if ($CaughtId.EndsWith($CaughtSuffix, [System.StringComparison]::Ordinal)) {
                                    $CaughtId = $CaughtId.Substring(0, $CaughtId.Length - $CaughtSuffix.Length)
                                }
                                if (-not [string]::Equals($CaughtId, 'PolicyOpenedButGrantFailed', [System.StringComparison]::Ordinal)) {
                                    $CaughtMessage = $PSItem.Exception.Message
                                    $CaughtCategory = $PSItem.CategoryInfo.Category
                                    $CaughtTarget = $PSItem.TargetObject
                                    $Statement = & $PermanentPolicyAfterAttempts
                                    $Published = [System.Management.Automation.ErrorRecord]::new(
                                        [System.Exception]::new("$CaughtMessage $Statement"),
                                        $CaughtId,
                                        $CaughtCategory,
                                        $CaughtTarget)
                                }
                            }
                            $Caller.WriteError($Published)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add permanent eligibility for '$EPrinRef': $($Published.Exception.Message)" -ErrorRecord $Published
                            break
                        } finally {
                            $script:_OERGroupEligibilityFailedIsReplication = $false
                        }
                        # Reached only when the call returned (the catch above always leaves the loop), and
                        # the loop calls again only after a request answered status Failed: a later call of
                        # this entry that throws then reports the policy state (see the catch).
                        $EarlierRequestSent = $true
                        # ConvertTo-OERGroupEligibilityRequest stamps Status from Graph's status, and
                        # Test-OERScheduleRequestFailed owns which statuses are the Failed family.
                        if (@($PermanentRequest | Where-Object { Test-OERScheduleRequestFailed -Status ([string]$_.Status) }).Count -eq 0) {
                            $PermanentApplied = $true
                            break
                        }
                        if ($ReplicationRetryDelays.Count -eq 0) {
                            $PermanentNotReady = $true
                            break
                        }
                        $Delay = $ReplicationRetryDelays.Dequeue()
                        $Waits++
                        Write-Verbose "Sync-OERStructureGroup: permanent eligibility for '$EPrinRef' ($($EChange.AccessType)) on new group '$Name' was accepted but answered status Failed (not ready in PIM for Groups yet); retry $Waits in $Delay s."
                        Start-Sleep -Seconds $Delay
                    }
                    if ($PermanentNotReady) {
                        # GroupNotOnboarded, the id Add-OERGroupEligibility publishes for the same
                        # condition (a new group's policy not listed yet), whether the policy was never
                        # listed, listed but never readable, or the request accepted but answered Failed
                        # until the wait ran out.
                        $Message = "permanent eligibility for '$EPrinRef' ($($EChange.AccessType)) not applied: for group '$Name', created in this run, Microsoft Graph did not list a readable PIM-for-groups policy for '$($EChange.AccessType)' access, or accepted the request but answered status Failed, every time within the 30-second wait. A new group's policies can take a while to be listed and readable, and the group to be known to PIM for Groups (replication delay); re-running the same document usually applies it."
                        # One sentence group more says whether the group's policy was opened for this
                        # entry, since Add-OERGroupEligibility opens it to allow permanent eligibility
                        # before its request and has no rollback. The handler decides it itself: with no
                        # call made, nothing was sent and nothing opened. Otherwise the after-attempts
                        # read decides it ($PermanentPolicyAfterAttempts above, the one place that read and
                        # its six outcomes live), which makes seven outcomes here.
                        if (-not $PermanentAttempted) {
                            $Message += ' No eligibility request was sent, so no PIM-for-groups policy was opened for it.'
                        } else {
                            $Message += ' ' + (& $PermanentPolicyAfterAttempts)
                        }
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($Message),
                            'GroupNotOnboarded',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $Name)
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail $Message -ErrorRecord $ErrRec
                    }
                    # A bare continue inside the loop above would continue the WHILE, not this foreach.
                    if (-not $PermanentApplied) { continue }
                } else {
                    try {
                        # Discarded, as in step 3: the returned request object is not a result row, and a
                        # Failed status reaches the catch below as the cmdlet's EligibilityRequestFailed
                        # error.
                        $null = Add-OERGroupEligibility -Id $Gid -PrincipalId $EPrinId -AccessType $EChange.AccessType -Action $EAction -Confirm:$false -ErrorAction Stop
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to add permanent eligibility for '$EPrinRef': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }
                }
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Updated' -Detail "set permanent $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            } else {
                ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would set permanent $($EChange.AccessType) eligibility for '$EPrinRef': $($EChange.Detail)"
            }
        }

        # Extra/prune undeclared current eligibilities. Only runs when the document declares the
        # collection -- an absent (or explicitly null) eligibility key means "do not reconcile
        # eligibility at all", exactly as it does for members. UNLIKE members/resources/resourceRoles,
        # an OMITTED eligibility key does NOT prune here: this pass is new and destructive (it can
        # revoke standing privileged access), so it only fires when the document affirmatively
        # declares the collection (Test-OERDeclaredProperty), including as an empty array.
        if ($HasEligibility) {
            foreach ($CurElig in $CurrentEligibles) {
                $CurPrincipal = [string]$CurElig.principalId
                $CurAccess = if ($CurElig.accessId) { [string]$CurElig.accessId } else { 'member' }
                $CurKey = ('{0}|{1}' -f $CurPrincipal, $CurAccess).ToLowerInvariant()
                if ($DeclaredEligibilityKeys -contains $CurKey) { continue }
                $Label = "undeclared $CurAccess eligibility for principal '$CurPrincipal'"
                $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Unresolved $EligibilityUnresolved -Candidate $Label
                if ($Withheld) { $Withheld; continue }
                # A15: nothing is removed from a group synchronized from on-premises.
                if ($GroupSynced) {
                    if ($Prune) { Write-SyncedGroupWarning }
                    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item $Name -Candidate $Label -SyncedGroup $SyncedGroupName -Prune:$Prune
                    continue
                }
                if ($Prune) {
                    # Remove-OERGroupEligibility (ConfirmImpact = High) also emits its own generic
                    # Write-Warning, before its own ShouldProcess gate, every time it is called. A previous
                    # revision dropped the handler-level warning below to avoid a double-warn against that
                    # (unlike Remove-OERGroupMember, which is silent) -- but that traded a duplicate for a
                    # safety hole: the child cmdlet is never reached under the engine's -WhatIf or when the
                    # engine's -Confirm prompt is declined, so nothing warned before the destructive gate.
                    # The handler warning is restored here, phrased from $WhatIfPreference so it fires before
                    # the gate on every path, and the child's own duplicate is silenced at the call site
                    # (-WarningAction SilentlyContinue) because the handler's message already names the
                    # principal, the access type and the group -- strictly more informative than the
                    # cmdlet's generic one -- and is the one that reaches the operator before the prompt.
                    $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                    Write-Warning "Sync-OERStructureGroup: $PruneVerb $Label from group '$Name'."
                    if ($Caller.ShouldProcess($Name, "Remove $Label")) {
                        try {
                            Remove-OERGroupEligibility -Group $Gid -PrincipalId $CurPrincipal -AccessType $CurAccess `
                                -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Removed' -Detail "removed $Label"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Failed' -Detail "failed to remove $Label`: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Skipped' -Detail "would remove $Label"
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'groups' -Item $Name -Action 'Extra' -Detail "$Label (use -Prune to remove)"
                }
            }
        }
    }
}
