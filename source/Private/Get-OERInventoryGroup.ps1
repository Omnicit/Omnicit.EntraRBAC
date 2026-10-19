function Get-OERInventoryGroup {
    <#
    .SYNOPSIS
    Reads the groups an inventory's Groups section holds, with their members, owners, PIM
    eligibility and PIM policy, and projects each as an apply-document entry.

    .DESCRIPTION
    The single owner of the inventory's Groups section. Get-OERInventory calls it to fill that
    section and replays the unread names and the causes it returns through its own lists.
    Export-OERInventory calls it directly, with -SecurityEnabledOnly and -ProgressActivity always and
    -RelevantOnly unless -AllGroupsDetailed is given.

    By default it makes ONE Get-OERGroup call carrying the members, owners and PIM eligibility
    switches and the filter it is given, then projects each group as an apply-document entry: an
    explicit null for a members read that failed and for the members of a dynamic group (below), the
    PIM-for-Groups pimPolicy only for a group that Test-OERGroupPimInUse finds in use, and
    onPremisesSynced only for a group synchronized from on-premises. A failed read is never an empty
    fact: it is named in the Unread list and its cause is kept in the Causes list, except the members
    read of a DYNAMIC group, which is no gap since those members are not part of the document (below;
    a dynamic administrative unit's members are the same, which Get-OERInventory handles the same way).

    The lists a projection writes stand in one fixed order, Get-OEROrderedInventoryEntry's (Sprint 11 step
    10, BL-121): members and owners as text, and eligibility by principal, then access type, then
    duration (a permanent eligibility, which has no durationDays, first), then id. Two reads of one
    unchanged tenant therefore write these lists in the same order, whatever order Graph answered in.
    The groups themselves stay in list order.

    A PIM activation is never written as a standing membership (BL-125, A3). Members and owners are
    written only when they are standing. For each group whose members or owners were read and hold
    at least one entry (the members of a dynamic group do not count, see below), the group's PIM for
    Groups assignment schedule instances are read ONCE (Read-OERGroupPimAssignment); no such read is
    made for a group whose members and owners were both read empty, or both unread.
    Get-OERGroupPimHeldAccess owns the rule that decides which instances
    hold access through PIM for Groups (docs/development/rationale.md#pim-activation-is-not-membership):
    every instance but a standing one -- an activation, a time-bound active assignment, or any active
    assignment that is not standing. Ids are compared without regard to letter case, and per access
    type, so a principal that is a standing member and an activated owner is written as a member and
    left out of the owners; an instance whose access type is neither member nor owner leaves nobody
    out.
    - With the assignments read, every member and owner whose id PIM for Groups holds for that access
      is left out of members or owners. Eligibility alone leaves nobody out: a standing member that is
      also eligible is written, as before.
    - When the assignment read fails, its cause is kept in the Causes list (Target the group's id),
      'groups/<name>/pimAssignments' is named in the Unread list (a collection name, not a document
      key), and every member and owner that is eligible for the same access is left out instead.
    - When the eligibility was not read either, nothing can be decided for a collection that holds
      entries: members is then written as an explicit null and owners is omitted, and each is named in
      the Unread list. A collection read empty is written as read and not named, since it cannot hold
      an activation.
    Each group that left at least one member or owner out is counted, by name and never by principal,
    in the PimLeftOut list below, with one verbose line.

    A dynamic group's members are never written (Sprint 11 step 10, BL-43). Its membership is owned by
    its membership rule, so a members list would only be what the rule derived at the time of the
    read, which Invoke-OERStructure can do nothing with: it adds no member to a dynamic group and
    removes none. The projection carries members as an EXPLICIT null, the schema's "leave the
    membership untouched" signal, and not as an omitted key: Set-OERGroup cannot convert a group's
    membership type, so a group that was made static after the export would meet an omitted key on
    the static path, which reconciles the members and, under -Prune, removes every live one, while an
    explicit null is hands-off on both paths. The null is no gap in the document, so a dynamic
    group's members are never named in the Unread list, and not when their read failed either: that
    failed read is no gap, so its cause is not recorded in the Causes list (the verbose stream carries
    it), as -SecurityEnabledOnly below removes the causes of a group it leaves out, and a cause clause
    never names a read that no unread entry names (R-24). The members are not looked at for the PIM
    decision above, since PIM for Groups cannot manage a dynamic group: a dynamic group with members
    and no owners sends no assignment read. They are still READ when the group is read in full, one
    request as before, and COUNTED, in the DynamicMembers list below, so that Export-OERInventory
    keeps the roster's memberCount a count. The owners and the eligibility of a dynamic group are
    unchanged.

    With -RelevantOnly the Get-OERGroup call carries the filter alone, and each listed group is first
    asked, in at most two requests, whether it is RBAC-relevant: its PIM eligibility, and, for a
    group that is not role-assignable and has none, the Test-OERGroupPimInUse criterion. A group
    that is neither role-assignable nor eligible nor found in use (nor synchronized from on-premises,
    under -IncludeSyncedGroups) costs exactly those two requests and is not returned. Every other
    group has its members and owners read one collection at a time (Read-OERGroupCollection) and is
    projected exactly as a full read projects it, the criterion's answer reused rather than asked
    again. A group whose relevance could not be read -- its eligibility or the criterion failed --
    is read in full and projected the same way, and the failure is named exactly as a full read
    names it.

    With -SecurityEnabledOnly a listed group whose securityEnabled is not a boolean true -- false,
    null, missing, a text or a number -- is dropped straight after the list is read, before the
    shared names are counted among the listed groups and before the relevance decision, as if it had
    never been listed: it is not projected, not asked the PIM-in-use criterion, has no members,
    owners or policy read by this function, and adds nothing to the Unread list. A -GroupNameIndex
    holds every group in the tenant, so through the index such a group still counts towards a name
    it shares with a security group (see -ExcludeSharedName below). Under a full read Get-OERGroup has already
    read its members, owners and PIM eligibility with the list, before this function sees the group,
    so a collection of it may have failed to read; that failure is no gap in the document, which
    does not hold the group, so this function removes every cause whose Target is the dropped
    group's id from the Causes list (the verbose stream has already carried it) and names nothing
    unread for it. Under -RelevantOnly the group is still listed, but its members, owners and PIM
    eligibility are not read. When any group was dropped, ONE warning says how many. It exists for a
    caller whose filter is an operator's own expression: a filter that closes the parenthesis it is
    wrapped in can list groups the caller never meant to cover, and this check is what keeps them
    out of the document.

    With -ExcludeSharedName a group whose display name another group shares, compared without regard
    to letter case, is left out in either mode, and the name is reported once, with the spelling of
    the first such group, in the Unread list ('groups/<name>'), with the Get-OERSharedNameCause text
    (which names the count) in the Causes list, and in the SharedNames list below. The count of a
    name is the LARGER of two counts: how many listed groups that are in scope carry it (every one
    -SecurityEnabledOnly keeps), so a group -RelevantOnly does not keep still makes its name shared,
    and a group -SecurityEnabledOnly dropped does not make it shared in this count; and, when
    -GroupNameIndex is given and was read, how many groups in the whole tenant carry it, a group
    -SecurityEnabledOnly dropped included. So with the index a security group that shares its name
    with a Microsoft 365 group or a distribution group, which the listing never holds, is left out
    and reported exactly like two security groups that share it, and so is one whose namesake a
    widened filter listed and -SecurityEnabledOnly dropped. Without the index, or with one that
    could not be read, the names are counted over the listed groups alone.

    It returns ONE tagged Omnicit.EntraRBAC.InventoryGroupRead object and never writes an error
    record. It writes a warning for a group list that could not be read and, under
    -SecurityEnabledOnly, one for the groups it left out, and its verbose lines carry
    the 'Get-OERInventory: ' prefix, so an inventory's verbose output reads the same wherever the
    line came from.
    - Groups: the projections, in list order.
    - Unread: the collection names that could not be read, in the order they were found ('groups'
      for the list itself, 'groups/<name>/members' and so on for a collection), exactly as the
      InventoryPartial message names them.
    - Causes: the raw causes behind them, in the order they were found, each an object with a Cause
      (the message) and a Target (the failing object's id, or an empty string). A blank cause is
      never added. Format-OERUnreadCauseClause turns them into the clause of the partial message.
    - PimLeftOut: one object per projected group that left at least one member or owner out as PIM
      for Groups access, in list order: GroupId, Group (the display name), Members and Owners (how
      many were left out) and Basis -- 'Assignments' when the assignments decided it, 'Eligibility'
      when the assignment read failed and the eligibility decided it. A group left out under
      -ExcludeSharedName has no entry. An empty array when nothing was left out.
    - DynamicMembers: one object per projected dynamic group whose members were read, in list order:
      GroupId, Group (the display name) and Members (how many members the read found; none is
      written, see above). A dynamic group whose members read failed has no entry, so its count is
      not known (which is not zero), and neither has a group left out under -ExcludeSharedName. An
      empty array when no dynamic group's members were read.
    - SharedNames: one object per name -ExcludeSharedName reported, in the order reported: Section
      ('groups'), Name (the spelling of the first listed group that carries it, as in the Unread
      list) and Count (the larger count described above). Always an array, empty when no name was
      reported.

    With -ProgressActivity it shows progress while it reads (Write-Progress): a status for the list
    read, then one record per listed group -- every listed group in scope, the ones -RelevantOnly
    drops included -- as 'Group n of N' with a percentage, and the activity is ended when the read is
    done, also when it stops on an error. Without it nothing is written to the progress stream, which
    is how Get-OERInventory calls it.

    An error nothing in it catches (a throw, or a statement-terminating error in a helper it calls)
    ends the read and propagates to the caller, and the call returns no result at all. A caller
    therefore reports the groups section unread when the call stops, as both callers do, and never
    reads a missing result as zero groups.

    The calling command must already have signed in (Initialize-OERAuth); this function makes no
    sign-in of its own.

    .PARAMETER Filter
    The OData filter sent to Get-OERGroup, exactly as given. Get-OERInventory passes its -GroupFilter,
    or 'securityEnabled eq true' when it has none. Export-OERInventory passes 'securityEnabled eq
    true', with its own -GroupFilter ANDed to it inside parentheses when it has one.

    .PARAMETER IncludeId
    Stamp each projection, and each eligibility entry of it, with its id.

    .PARAMETER PrincipalNameCache
    The caller's id to display name cache for principals. Eligibility principals are resolved through
    it and what is learned is left in it, so the caller's other sections share the lookups. A new,
    empty cache is used when none is given.

    .PARAMETER RelevantOnly
    Decide first which groups are RBAC-relevant (role-assignable, with PIM eligibility, or found to
    use PIM for Groups), and read the members, owners and PIM policy of those groups only, and of
    every group whose relevance could not be read.

    .PARAMETER IncludeSyncedGroups
    With -RelevantOnly, also keep every group synchronized from on-premises
    (Test-OERGroupOnPremisesSynced). Without -RelevantOnly every group is read in full already, and
    this switch changes nothing.

    .PARAMETER ExcludeSharedName
    Leave out every group whose display name another group shares, compared without regard to letter
    case, and report each such name once in the Unread, Causes and SharedNames lists. The names are
    counted over the listed groups, and over every group in the tenant when -GroupNameIndex is given.

    .PARAMETER GroupNameIndex
    An index of every group in the tenant by display name, as Get-OERGroupNameIndex returns it
    (Export-OERInventory builds it from its roster). Under -ExcludeSharedName, when its Read is true,
    a listed group's name counts the larger of the listed groups and the index's groups that carry
    it. The index holds every group in the tenant, a group -SecurityEnabledOnly drops from the
    listing included, so such a group counts here although it does not in the listed count. An
    index whose Read is not true, or none, leaves the count over the listed groups alone. Without
    -ExcludeSharedName it changes nothing.

    .PARAMETER SecurityEnabledOnly
    Drop every listed group whose securityEnabled is not a boolean true (false, null, missing, a text
    or a number) straight after the list is read, before the shared names are counted among the
    listed groups and before the relevance decision, and write ONE warning that names how many were
    dropped. A dropped group still counts towards a shared name through a -GroupNameIndex, which
    holds every group in the tenant. Use it when the filter is not the caller's own, so a filter that
    lists more than the security-enabled scope cannot widen the result.

    .PARAMETER ProgressActivity
    The activity name to show progress under (Write-Progress -Activity). Export-OERInventory passes
    its own name, which its Azure scope walk uses too: this read's record is completed when the read
    is done, and the walk then starts a new record under the same activity name. Without it nothing
    is written to the progress stream.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -PrincipalNameCache $Cache
    $Read.Groups.Count
    Reads the security-enabled groups with their members, owners, eligibility and PIM policy, and
    returns the projections together with the collections that could not be read and why.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -IncludeId -ExcludeSharedName -RelevantOnly
    Reads only the RBAC-relevant security-enabled groups in full, after at most two requests per
    listed group, stamps their ids, and leaves out every group whose name another shares.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -ExcludeSharedName -GroupNameIndex (Get-OERGroupNameIndex -Group $RosterGroups)
    $Read.SharedNames
    Reads the security-enabled groups and leaves out every one whose name another group in the
    tenant shares, a Microsoft 365 or distribution group included, and lists each such name with how
    many groups carry it.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter "securityEnabled eq true and (startswith(displayName,'role_'))" -SecurityEnabledOnly -RelevantOnly
    Reads the groups an operator's filter chose, and keeps only the ones that really are
    security-enabled, with one warning when the filter listed any other.

    .EXAMPLE
    $Read = Get-OERInventoryGroup -Filter 'securityEnabled eq true' -RelevantOnly -ProgressActivity 'Export-OERInventory'
    Reads the RBAC-relevant security-enabled groups while showing 'Group n of N' progress under the
    activity 'Export-OERInventory', and ends that progress when the read is done.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [switch]$IncludeId,

        [hashtable]$PrincipalNameCache = @{},

        [switch]$RelevantOnly,

        [switch]$IncludeSyncedGroups,

        [switch]$ExcludeSharedName,

        [object]$GroupNameIndex,

        [switch]$SecurityEnabledOnly,

        [string]$ProgressActivity
    )

    # What the read below records into: the projections, the unread collection names and the causes.
    # $Causes keeps every cause RAW (the message and the id it was about): the caller replays them
    # through its own list, and the clause is built where the partial message is, from all sections.
    $Groups            = [System.Collections.Generic.List[object]]::new()
    $UnreadCollections = [System.Collections.Generic.List[string]]::new()
    $Causes            = [System.Collections.Generic.List[object]]::new()
    # BL-125: one entry per projected group that left a member or owner out as PIM for Groups access.
    $PimLeftOut        = [System.Collections.Generic.List[object]]::new()
    # BL-43 (R-15): one entry per projected dynamic group whose members were read, with how many (none is written).
    $DynamicMembers    = [System.Collections.Generic.List[object]]::new()
    # BL-131: one entry per name -ExcludeSharedName reports (Section, Name, Count).
    $SharedNames       = [System.Collections.Generic.List[object]]::new()
    function Add-UnreadCause {
        param(
            [string]$Cause,
            [string]$Target
        )
        if ([string]::IsNullOrWhiteSpace($Cause)) { return }
        $Causes.Add([PSCustomObject]@{ Cause = $Cause; Target = $Target })
    }
    # A section whose LIST could not be read at all is named by its own key, once however many
    # records the failed read produced (the same rule as Get-OERInventory's function of this name).
    function Add-UnreadSection {
        param([string]$Key, [string]$Cause)
        Write-Verbose "Get-OERInventory: $Cause"
        Add-UnreadCause -Cause $Cause
        if (-not $UnreadCollections.Contains($Key)) { $UnreadCollections.Add($Key) }
    }

    # Everything from here to the result is read under a progress activity when the caller named one
    # (Export-OERInventory does; Get-OERInventory does not, and its output stays what it was). The
    # activity is ended in the finally at the end, so it is ended also when the read stops on an
    # error nothing in this function catches, and a progress bar never outlives the read.
    try {
        if ($ProgressActivity) {
            Write-Progress -Activity $ProgressActivity -Status $(if ($RelevantOnly) { 'Reading the group list' } else { 'Reading the groups in full' })
        }

        # A full read lists the groups with all three collections attached. A relevant-only read lists
        # them alone: the collections are read group by group in the projection loop below, so a group
        # that turns out not to be RBAC-relevant never costs a members or owners request.
        $GroupParams = if ($RelevantOnly) {
            @{ Filter = $Filter }
        } else {
            @{ IncludeMembers = $true; IncludePimEligibility = $true; IncludeOwners = $true; Filter = $Filter }
        }
        $GroupItems = @()
        # -ErrorAction SilentlyContinue + -ErrorVariable, not -ErrorAction Stop: Get-OERGroup now
        # writes a non-terminating error per group whose members, owners or eligibility read
        # failed, and Stop would abort the whole enumeration on the first one -- losing every
        # remaining group instead of losing one collection. The errors are inspected below, so
        # nothing is suppressed; SilentlyContinue here means "captured", not "ignored".
        # The pipe into Where-Object is load-bearing, not tidying (BL-58). The measured numbers are in the
        # access review read of Get-OERInventory ("The pipe into Where-Object is load-bearing") and in
        # docs/development/rationale.md#writeerror-deposit: a bare call inside @( ) leaks one record per
        # record written to the caller's -ErrorVariable, since the array subexpression runs the call as its
        # own nested pipeline and deposits the record again on the way out; only piping the call onward
        # before the @( ) closes leaks none. This call was that bare form, so every per-collection record
        # Get-OERGroup writes (GroupMemberReadFailed and its two siblings) reached the caller's -ErrorVariable
        # although this reader counts and words each of them itself. Do not "simplify" the filter away.
        $GroupReadErrors = $null
        # The try/catch still guards a genuinely TERMINATING failure of the whole read (auth,
        # a dead transport, an -ErrorAction Stop upstream); the inner loop handles the
        # NON-terminating per-group records. Both are needed: neither subsumes the other.
        try {
            $GroupItems = @(Get-OERGroup @GroupParams -ErrorAction SilentlyContinue -ErrorVariable GroupReadErrors |
                    Where-Object { $null -ne $_ })
            # Sprint 11 step 10 (BL-43, R-24, fix round 2): the dynamic groups among those just listed, by id and
            # without regard to letter case, built ONCE and only when a record was written, so the record loop
            # below asks a set instead of scanning every listed group per failed members read (a bad run in
            # which every group's members read failed cost failures times groups: 15.5 s for 2000 groups, 95 s
            # extrapolated for 5000, none of it for a healthy tenant). It is complete here: the listing above has
            # finished, and the -SecurityEnabledOnly removal that reassigns $GroupItems comes after the loop.
            $DynamicGroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if (@($GroupReadErrors | Where-Object { $null -ne $_ }).Count -gt 0) {
                foreach ($ListedGroup in $GroupItems) {
                    if ($ListedGroup.GroupType -eq 'Dynamic' -and -not [string]::IsNullOrEmpty([string]$ListedGroup.Id)) {
                        $null = $DynamicGroupIds.Add([string]$ListedGroup.Id)
                    }
                }
            }
            foreach ($GErr in @($GroupReadErrors)) {
                if ($null -eq $GErr) { continue }
                # No Remove-OERErrorRecord here: these records were WRITTEN deliberately by
                # Get-OERGroup (which already scrubbed the raw transport record behind each one),
                # not swallowed by a catch. Scrubbing a reported diagnostic would hide it.
                if ($GErr.FullyQualifiedErrorId -like 'GroupNotFound*') { continue }
                # Per-collection failures are accounted for at the projection below, where the
                # affected group is known by name; only anything else warrants a section warning.
                if ($GErr.FullyQualifiedErrorId -like 'GroupMemberReadFailed*' -or
                    $GErr.FullyQualifiedErrorId -like 'GroupOwnerReadFailed*' -or
                    $GErr.FullyQualifiedErrorId -like 'GroupPimEligibilityReadFailed*') {
                    # Keep the CAUSE. Get-OERGroup composed the transport reason into this
                    # message and it lives nowhere else once the record is dropped here.
                    $GroupCause = [string]$GErr.Exception.Message
                    Write-Verbose "Get-OERInventory: $GroupCause"
                    # Sprint 11 step 10 (BL-43, R-24): the members read of a DYNAMIC group is no gap, since its
                    # members are the explicit null whether the read worked or not and nothing in the document
                    # is missing, so its cause is not recorded: a cause clause must never name a read that no
                    # unread entry names (the verbose line above is all that remains of it). The group is found
                    # by the record's Target, its id, in the set of dynamic groups just listed; a record with no
                    # Target matches none and keeps its cause.
                    $DynamicMembersFailure = $GErr.FullyQualifiedErrorId -like 'GroupMemberReadFailed*' -and
                        -not [string]::IsNullOrEmpty([string]$GErr.TargetObject) -and
                        $DynamicGroupIds.Contains([string]$GErr.TargetObject)
                    if (-not $DynamicMembersFailure) {
                        Add-UnreadCause -Cause $GroupCause -Target ([string]$GErr.TargetObject)
                    }
                    continue
                }
                # Warn only for a record Get-OERGroup itself PUBLISHED. -ErrorVariable is filled
                # by the ENGINE and also collects records raised inside nested calls -- the Graph
                # SDK's own, several of them empty, one of them the raw bearer-carrying request
                # record -- even when an inner catch swallowed them. Warning on those produced
                # eight spurious lines per failed read on a live tenant (about 72 in one run) and
                # buried the real signal. A published record carries the calling cmdlet's name as
                # a comma-separated segment of the FullyQualifiedErrorId; a stray does not.
                # Filtering on the error id instead would need widening for every id ever added
                # and would still admit every stray, so the test is the publisher, not the id.
                # Membership, not a suffix match: Write-Error appends a further name when a
                # record is republished, so the cmdlet's name is not always the last segment.
                if (@(([string]$GErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERGroup') {
                    # The warning stays; the section is ALSO counted unread, since the groups array
                    # below is [] whether the tenant has none or the list could not be read. Sprint 11
                    # step 10 (BL-44): the bookkeeping stands BEFORE the warning, as at every site BL-44
                    # names, so no warning stands between a failed read and its record. Under a Stop warning
                    # preference the warning is a terminating error and ends the read in either order (the
                    # catch below catches it and warns again), so no caller sees a difference here; only the
                    # verbose stream does. Held by the verbose line Add-UnreadSection writes first, in the
                    # tests of this reader.
                    Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($GErr.Exception.Message)"
                    Write-Warning "Could not read groups: $($GErr.Exception.Message)"
                } else {
                    # Routed to verbose rather than dropped: a stray is still evidence when a read
                    # misbehaves, it just is not a section-level finding the operator must act on.
                    Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading groups " +
                        "($($GErr.FullyQualifiedErrorId)): $($GErr.Exception.Message)")
                }
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if ($PSItem.FullyQualifiedErrorId -notlike 'GroupNotFound*') {
                # Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE the warning (see the record loop
                # above). This catch also catches the stop the warning of the record loop raises.
                Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($PSItem.Exception.Message)"
                Write-Warning "Could not read groups: $($PSItem.Exception.Message)"
            }
        }

        # -SecurityEnabledOnly: keep the listed groups the apply document covers, whatever the filter let
        # through. The filter is the CALLER's expression, so a caller that composes one from an operator's
        # text (Export-OERInventory -GroupFilter) can be handed a listing that is wider than the scope it
        # meant, by an expression that closes its own parenthesis. The check is on the READ, not on the
        # text: the group's own securityEnabled must be a boolean true, so a missing property, a null, a
        # text or a number is not security-enabled either, and a group that fails it is out of scope as
        # if it had never been listed. That is why it runs here, straight after the list is read and
        # BEFORE the shared-name count below and the relevance decision: a group that is out of scope
        # must neither be read in full nor make a security group's name "shared" in the count over the
        # listed groups (a -GroupNameIndex holds every group in the tenant, so through the index it
        # still counts, BL-131: the apply engine refuses the name either way). The count goes into
        # ONE warning, written here (the caller's ShouldProcess comes after this read, so -WhatIf and a
        # -Confirm prompt both show it). Under a full read the list has already carried the collections of
        # such a group (Get-OERGroup read them with the list), which is the only read it costs: a
        # collection of it that failed to read was reported by the record loop above, whose verbose line
        # carried the cause, and left it in the Causes list. A group left out is not in the document, so
        # that failed read is no gap in it and the cause is removed here (by the group's id, the Target
        # the record loop gave it); it names no Unread collection either, since the group is never
        # projected. A cause with no target is never removed, and a group without an id removes none.
        if ($SecurityEnabledOnly) {
            # One pass, so a tenant with very many groups is walked once: the groups that stay, how many
            # went, and the ids of the ones that went (a group without an id has none to remove by).
            $KeptGroupItems = [System.Collections.Generic.List[object]]::new()
            $LeftOutIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $LeftOutCount = 0
            foreach ($Listed in $GroupItems) {
                if ($Listed.SecurityEnabled -is [bool] -and $Listed.SecurityEnabled) { $KeptGroupItems.Add($Listed); continue }
                $LeftOutCount++
                if ($Listed.Id) { $null = $LeftOutIds.Add([string]$Listed.Id) }
            }
            if ($LeftOutCount -gt 0) {
                # Sprint 11 step 10 (BL-44): the removal of the left-out groups' causes stands BEFORE the
                # warning, as the bookkeeping of a failed read does above: a Write-Warning under a Stop
                # warning preference is a terminating error, so a statement after it never runs. Held by the
                # AST test of this reader, since a list cannot be shown by a verbose line.
                for ($CauseIndex = $Causes.Count - 1; $CauseIndex -ge 0; $CauseIndex--) {
                    if ($LeftOutIds.Contains([string]$Causes[$CauseIndex].Target)) { $Causes.RemoveAt($CauseIndex) }
                }
                Write-Warning "-GroupFilter returned $LeftOutCount group(s) that are not security-enabled; inventory.json keeps security-enabled groups only, so they were left out."
            }
            $GroupItems = $KeptGroupItems.ToArray()
        }

        # -ExcludeSharedName: how many listed groups carry each display name, compared without regard to
        # letter case -- the key the validator refuses a duplicate on (Test-OERStructureSchema), so a pair
        # it would refuse is never written. Counted over EVERY listed group that is in scope (every one
        # -SecurityEnabledOnly kept), before the relevance decision below, because the name is shared
        # whether or not the namesake is RBAC-relevant: two live groups answer that name, so the apply
        # engine refuses it either way, and a read that kept only the relevant one would write an entry
        # that cannot be applied.
        $SharedNameCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($ExcludeSharedName) {
            foreach ($G in $GroupItems) {
                $NameKey = [string]$G.DisplayName
                $SharedNameCount[$NameKey] = 1 + $(if ($SharedNameCount.ContainsKey($NameKey)) { $SharedNameCount[$NameKey] } else { 0 })
            }
            # BL-131: the listing holds the security-enabled groups only, but the apply engine refuses a
            # name ANY live group answers to -- a Microsoft 365 group or a distribution group included.
            # So when the caller hands over an index of every group in the tenant (Get-OERGroupNameIndex,
            # which Export-OERInventory builds from its unfiltered roster) and it was read, a name counts
            # the larger of the two: the index can lag behind the listing (a group created between the
            # two reads), and the listing never holds what the filter left out. An index that was not
            # read changes nothing here: the names are counted over the listed groups, as before.
            if ($null -ne $GroupNameIndex -and $GroupNameIndex.Read -eq $true) {
                foreach ($NameKey in @($SharedNameCount.Keys)) {
                    if (-not $GroupNameIndex.IdsByName.ContainsKey($NameKey)) { continue }
                    $IndexCount = $GroupNameIndex.IdsByName[$NameKey].Count
                    if ($IndexCount -gt $SharedNameCount[$NameKey]) { $SharedNameCount[$NameKey] = $IndexCount }
                }
            }
        }

        # Project one access-type policy object from a Get-OERGroupPimPolicy result, or $null when
        # the group carries no policy for that access type. The block is emitted whenever ANY
        # meaningful field is present -- gating it on activationMaxHours alone used to discard a
        # policy that was customized only for permanence, expiration, enablement or notifications.
        function Convert-PimAccessProjection {
            param([object]$Policy)
            if (-not $Policy) { return $null }
            $Block = [ordered]@{}
            if ($null -ne $Policy.ActivationMaxHours) { $Block.activationMaxHours = $Policy.ActivationMaxHours }
            if ($Policy.AuthenticationContextId) { $Block.authenticationContextId = $Policy.AuthenticationContextId }
            # ConvertTo-OERGroupPimPolicy wraps ActivationEnabledRules/ActiveEnabledRules with a
            # null-filter (its own comment at ConvertTo-OERGroupPimPolicy.ps1:67-73), so a rule
            # the tenant never configured and a rule that is genuinely empty BOTH read back as
            # @() here -- $null -ne cannot tell "unread" from "read and empty" on these two
            # properties, and neither can Count -gt 0 alone. Fall back to the raw rule set
            # carried on Rules: when the canonical rule id IS present the policy was actually
            # read and the list is genuinely empty, so emit an explicit [] (security-relevant:
            # no MFA, justification or ticket is required on activation). When the rule id is
            # absent too, the policy never carried it -- omit, same as before.
            $HasActivationRule = @($Policy.Rules |
                Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }).Count -gt 0
            if (@($Policy.ActivationEnabledRules).Count -gt 0 -or $HasActivationRule) {
                $Block.activationEnablement = @($Policy.ActivationEnabledRules)
            }
            if ($null -ne $Policy.AllowPermanentEligibility) { $Block.allowPermanentEligibility = [bool]$Policy.AllowPermanentEligibility }
            if ($Policy.EligibleDurationDays) { $Block.eligibleDurationDays = [int]$Policy.EligibleDurationDays }
            if ($null -ne $Policy.AllowPermanentActive) { $Block.allowPermanentActive = [bool]$Policy.AllowPermanentActive }
            if ($Policy.ActiveDurationDays) { $Block.activeDurationDays = [int]$Policy.ActiveDurationDays }
            $HasActiveRule = @($Policy.Rules |
                Where-Object { $_.id -eq 'Enablement_Admin_Assignment' }).Count -gt 0
            if (@($Policy.ActiveEnabledRules).Count -gt 0 -or $HasActiveRule) {
                $Block.activeEnablement = @($Policy.ActiveEnabledRules)
            }
            if ($null -ne $Policy.RequireApproval) { $Block.requireApproval = [bool]$Policy.RequireApproval }
            # Approvers project as object ids, the same as the roleManagementPolicies projection:
            # an id resolves verbatim through the apply engine's declared-approver resolution,
            # whereas a display name may not. Exported only while approval is required, since the
            # apply engine ignores declared approvers whenever requireApproval is false and
            # Test-OERStructureSchema would otherwise warn about that combination on every
            # exported document that carries an approval-gated policy.
            if ($Policy.RequireApproval -eq $true) {
                $PimApproverUser  = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
                $PimApproverGroup = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
                if ($PimApproverUser.Count -gt 0 -or $PimApproverGroup.Count -gt 0) {
                    $PimApproverProj = [ordered]@{}
                    if ($PimApproverUser.Count -gt 0)  { $PimApproverProj.users = $PimApproverUser }
                    if ($PimApproverGroup.Count -gt 0) { $PimApproverProj.groups = $PimApproverGroup }
                    $Block.approvers = [PSCustomObject]$PimApproverProj
                }
            }
            $Notif = [ordered]@{}
            if ($Policy.Notifications) {
                if (@($Policy.Notifications.EligibleAlert).Count -gt 0)   { $Notif.eligibleAlert = @($Policy.Notifications.EligibleAlert) }
                if (@($Policy.Notifications.ActiveAlert).Count -gt 0)     { $Notif.activeAlert = @($Policy.Notifications.ActiveAlert) }
                if (@($Policy.Notifications.ActivationAlert).Count -gt 0) { $Notif.activationAlert = @($Policy.Notifications.ActivationAlert) }
            }
            if ($Notif.Count -gt 0) { $Block.notifications = [PSCustomObject]$Notif }
            if ($Block.Count -eq 0) { return $null }
            [PSCustomObject]$Block
        }

        # Asks Test-OERGroupPimInUse (the single owner of the criterion) whether one group uses PIM for
        # Groups, and returns the answer or the failure instead of recording either: the projection
        # below records the failure, with the group known by name, and a decision that is already made
        # can be reused without a second request. The catch scrubs first, as every transport-reaching
        # catch does; a failed criterion is never guessed in either direction.
        function Get-PimUsageDecision {
            param([object]$Group, [int]$EligibilityCount)
            try {
                [PSCustomObject]@{ Usage = (Test-OERGroupPimInUse -GroupId $Group.Id -EligibilityCount $EligibilityCount); Failed = $false; Message = $null }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                [PSCustomObject]@{ Usage = $null; Failed = $true; Message = [string]$PSItem.Exception.Message }
            }
        }
        # The criterion's answers already obtained for a group id, as Get-PimUsageDecision returns them.
        # The relevance decision under -RelevantOnly fills it for a group it had to ask, and the
        # projection reuses an entry instead of asking again, so no group's criterion is read twice.
        $PimUsageDecided = @{}

        # The count progress is reported against: every group the loop goes through, which is every
        # listed group in scope. The record stands at the top of the loop, before the relevance
        # decision, so a group that decision drops is counted too and the bar reaches its end.
        $GroupTotal = @($GroupItems).Count
        $GroupIndex = 0
        foreach ($G in $GroupItems) {
            $GroupIndex++
            if ($ProgressActivity) {
                Write-Progress -Activity $ProgressActivity -Status "Group $GroupIndex of $GroupTotal" -PercentComplete ([int](($GroupIndex / [Math]::Max($GroupTotal, 1)) * 100))
            }
            # Decided once, here at the top, since the members read below and the projection both need it: it
            # sets the dynamic key, the rule keys, and what members is for this group (BL-43).
            $GroupIsDynamic = ($G.GroupType -eq 'Dynamic')
            if ($RelevantOnly) {
                $GroupId = [string]$G.Id
                # THE FIRST REQUEST: the eligibility, which is both a relevance criterion and a collection
                # the projection needs. Kept on the group as Get-OERGroup would attach it, or recorded
                # exactly as Get-OERGroup's own record would have been: the cause here, and the
                # projection below names the collection, since the property stays absent.
                $EligRead = Read-OERGroupCollection -GroupId $GroupId -Collection PimEligibility
                if ($EligRead.Read) {
                    $G | Add-Member -NotePropertyName PimEligibility -NotePropertyValue $EligRead.Value -Force
                } else {
                    Write-Verbose "Get-OERInventory: $($EligRead.Message)"
                    Add-UnreadCause -Cause $EligRead.Message -Target $GroupId
                }
                # A role-assignable group is relevant on its own, and so is a synchronized group when the
                # caller asked for them; neither needs the criterion to be kept.
                $Kept = ($G.IsAssignableToRole -eq $true) -or ($IncludeSyncedGroups -and (Test-OERGroupOnPremisesSynced -Group $G))
                if (-not $Kept) {
                    # The null-filter is load-bearing, as in the projection below: @($null).Count is 1.
                    $RelevantEligCount = if ($EligRead.Read) { @($EligRead.Value | Where-Object { $null -ne $_ }).Count } else { 0 }
                    if ($RelevantEligCount -eq 0) {
                        # THE SECOND REQUEST: the criterion, decided here once and reused by the
                        # projection. A group with eligibility needs no request for it (the eligibility
                        # decides "in use" on its own), so it is asked only for a group without any.
                        $PimUsageDecided[$GroupId] = Get-PimUsageDecision -Group $G -EligibilityCount 0
                        $InUse = ($null -ne $PimUsageDecided[$GroupId].Usage -and [bool]$PimUsageDecided[$GroupId].Usage.InUse)
                        # R2: a group whose relevance could not be read -- its eligibility read failed, so
                        # its count is 0 by default rather than by measurement, or the criterion failed --
                        # is never guessed to be irrelevant. It is read in full below, exactly as a full
                        # read would have read it, and the projection names what could not be read.
                        $Undecided = (-not $EligRead.Read) -or $PimUsageDecided[$GroupId].Failed
                        # Not relevant, and known not to be: the two requests above are all this group
                        # costs. No members, owners or policy request is made for it, and it is not
                        # returned (the export would not keep it in inventory.json either).
                        if (-not $InUse -and -not $Undecided) { continue }
                    }
                }
                # Every other group -- kept, eligible, found in use, or undecided -- gets the two
                # collections a full read attaches, one at a time and recorded the same way as the
                # eligibility above.
                foreach ($RelevantCollection in @('Members', 'Owners')) {
                    $RelevantRead = Read-OERGroupCollection -GroupId $GroupId -Collection $RelevantCollection
                    if ($RelevantRead.Read) {
                        $G | Add-Member -NotePropertyName $RelevantCollection -NotePropertyValue $RelevantRead.Value -Force
                    } else {
                        Write-Verbose "Get-OERInventory: $($RelevantRead.Message)"
                        # BL-43 (R-24): the members read of a dynamic group is no gap, so its cause is not
                        # recorded, exactly as the record loop of a full read does not record it; the verbose
                        # line above is all that remains of it.
                        if (-not ($GroupIsDynamic -and $RelevantCollection -eq 'Members')) {
                            Add-UnreadCause -Cause $RelevantRead.Message -Target $GroupId
                        }
                    }
                }
            }

            $Proj = [ordered]@{
                displayName    = $G.DisplayName
                roleAssignable = [bool]$G.IsAssignableToRole
                dynamic        = $GroupIsDynamic
                description    = $G.Description
            }
            # A15: information only. Written as true for a group synchronized from on-premises
            # (Test-OERGroupOnPremisesSynced owns the rule) and never otherwise, so a cloud
            # group's entry is exactly what earlier versions exported. Invoke-OERStructure never
            # sends this key and decides nothing on it: it reads the group live.
            if (Test-OERGroupOnPremisesSynced -Group $G) { $Proj.onPremisesSynced = $true }
            if ($GroupIsDynamic) {
                $Proj.membershipRule = $G.MembershipRule
                if ($G.MembershipRuleProcessingState) {
                    $Proj.membershipRuleProcessingState = [string]$G.MembershipRuleProcessingState
                }
            }
            # mailNickname is writable on create AND diffed on update by the apply engine, so it
            # must be readable here or a custom nickname is silently replaced by the Graph-generated
            # one on the next round-trip. Emitted only when set, so a document for a group without
            # one stays clean and the apply leaves it untouched.
            if ($G.MailNickname) { $Proj.mailNickname = [string]$G.MailNickname }
            if ($IncludeId) { $Proj.id = $G.Id }

            # BL-125 (A3): a member or owner that holds its access through PIM for Groups -- an
            # activation, or another active assignment that is not standing, such as a time-bound one --
            # is never written as standing. Get-OERGroupPimHeldAccess owns the rule
            # (docs/development/rationale.md#pim-activation-is-not-membership). The assignment read
            # lists every direct member and owner, standing ones too (measured live 2026-10-13), so it
            # is what tells the two apart. It is asked at most ONCE per group, and not at all for a
            # group whose members and owners were both read empty, or both unread: there is nothing to
            # leave out. When it fails, the group's eligibility decides instead: a member or owner
            # eligible for the same access is left out, since an eligible principal that is a member
            # now may be one through an activation. When the eligibility was not read either, nothing
            # can be decided for a collection that holds entries, and it is not written: members as an
            # explicit null, owners omitted, each named unread. A collection read EMPTY cannot hold an
            # activation, so it is written as read (members [], owners omitted as ever) and not named.
            #
            # Sprint 11 step 10 (BL-43, R-1): the members of a DYNAMIC group are not looked at here. They are
            # never written (below), so there is nothing for PIM for Groups to hold out of them, and a
            # dynamic group with members and no owners sends no assignment read. The group's OWNERS decide
            # the read as for every group.
            $MembersRead = $G.PSObject.Properties.Name -contains 'Members'
            $OwnersRead  = $G.PSObject.Properties.Name -contains 'Owners'
            $MembersHaveEntries = (-not $GroupIsDynamic) -and $MembersRead -and @($G.Members | Where-Object { $null -ne $_ }).Count -gt 0
            $OwnersHaveEntries  = $OwnersRead -and @($G.Owners | Where-Object { $null -ne $_ }).Count -gt 0
            $HeldIds = @{ member = @{}; owner = @{} }
            $PimBasis = $null
            $PimUndecided = $false
            $NeedPimRead = $MembersHaveEntries -or $OwnersHaveEntries
            if ($NeedPimRead) {
                $AssignRead = Read-OERGroupPimAssignment -GroupId ([string]$G.Id)
                $Held = @()
                if ($AssignRead.Read) {
                    $PimBasis = 'Assignments'
                    $Held = @(Get-OERGroupPimHeldAccess -Assignment @($AssignRead.Value))
                } else {
                    Write-Verbose "Get-OERInventory: $($AssignRead.Message)"
                    Add-UnreadCause -Cause $AssignRead.Message -Target ([string]$G.Id)
                    $UnreadCollections.Add("groups/$($G.DisplayName)/pimAssignments")
                    if ($G.PSObject.Properties.Name -contains 'PimEligibility') {
                        $PimBasis = 'Eligibility'
                        $Held = @(Get-OERGroupPimHeldAccess -Eligibility @($G.PimEligibility))
                    } else {
                        $PimUndecided = $true
                    }
                }
                # Keyed by access type, so a principal held for one access is never left out of the
                # other. Get-OERGroupPimHeldAccess passes an accessId other than member or owner through
                # lower-cased (a later enum value, such as unknownFutureValue); it names no collection
                # here and leaves nobody out, and indexing by it would end the whole read.
                foreach ($H in $Held) {
                    if ($HeldIds.ContainsKey($H.AccessType)) { $HeldIds[$H.AccessType][$H.PrincipalId] = $H.Kind }
                }
            }
            $MembersLeftOut = 0
            $OwnersLeftOut  = 0

            # An OMITTED members key still reconciles in the apply engine and still prunes under
            # -Prune (Get-OERStructureSchemaJson: "An omitted key still reconciles"), so omitting
            # it here would leave issue #76's chain wide open. An EXPLICIT null is the schema's
            # documented "leave membership untouched" signal, and that is what an unread
            # membership has to be -- and what a membership is whose PIM hold could not be decided.
            #
            # Sprint 11 step 10 (BL-43, R-1): a DYNAMIC group's members are the same explicit null, for a
            # different reason, and it is no gap, so it is never named unread, and not when the members read
            # failed either: that failed read is no gap, so its cause is not recorded either (R-24; the two
            # places that would record it, the record loop of a full read and the members read of a relevant-only
            # one, skip a dynamic group, and the verbose line stays), exactly as -SecurityEnabledOnly removes the
            # causes of a group it leaves out. The membership is owned by the membership rule: what the read
            # found is a snapshot of what the rule derived, which Invoke-OERStructure can do nothing with (it
            # adds no member to a dynamic group and removes none). It is a null and not an omitted key, unlike a
            # dynamic administrative unit, whose members are OMITTED since the engine converts a unit's
            # membership type back to the declared one, but Set-OERGroup cannot convert a group's membership
            # type: a group that was made static after the export would meet an omitted key on the static path,
            # which reconciles and, under -Prune, removes every live member, while an explicit null is hands-off
            # on both paths. The members read is kept (one request, only for a group read in full) and the COUNT
            # of what it found goes in $DynamicMembers, so the export's roster keeps a memberCount (R-15); a read
            # that failed has no count, so the roster's memberCount stays null, which is not zero.
            if ($GroupIsDynamic) {
                $Proj.members = $null
                if ($MembersRead) {
                    $DynamicMembers.Add([PSCustomObject]@{
                            GroupId = [string]$G.Id
                            Group   = [string]$G.DisplayName
                            Members = @(@($G.Members) | Where-Object { $_ }).Count
                        })
                }
            } elseif ($MembersHaveEntries -and $PimUndecided) {
                $Proj.members = $null
                $UnreadCollections.Add("groups/$($G.DisplayName)/members")
            } elseif ($MembersRead) {
                # Project each member as a reference the apply engine can resolve back to its object id:
                # a user as its userPrincipalName (friendly and resolvable), and every other member type
                # (group, device, service principal, ...) as its object id, which Resolve-OERStructurePrincipal
                # returns verbatim. A member display name is NOT resolvable (it is not a UPN), so it is only a
                # last-resort fallback when neither a UPN nor an id is present. A member whose membership
                # PIM for Groups holds is left out and counted (BL-125, above). The list is written in the
                # fixed order of Get-OEROrderedInventoryEntry (BL-121, R-16), since Graph answers in none.
                $MemberRefs = @(foreach ($M in @($G.Members)) {
                    if (-not $M) { continue }
                    if ($HeldIds.member.ContainsKey(([string]$M.id).ToLowerInvariant())) { $MembersLeftOut++; continue }
                    if ($M.userPrincipalName) { [string]$M.userPrincipalName }
                    elseif ($M.id)            { [string]$M.id }
                    else                      { [string]$M.displayName }
                })
                $Proj.members = @(Get-OEROrderedInventoryEntry -InputObject $MemberRefs)
            } else {
                $Proj.members = $null
                $UnreadCollections.Add("groups/$($G.DisplayName)/members")
            }
            if ($OwnersHaveEntries -and $PimUndecided) {
                # The same hands-off form as an unread owners collection below: omitted, and named.
                $UnreadCollections.Add("groups/$($G.DisplayName)/owners")
            } elseif ($OwnersRead) {
                # Owners are writable through Add-/Remove-OERGroupMember -AccessType owner and a group
                # owner can add members, so an unprojected owner is a privilege path that disappears from
                # the captured posture. Emitted only when the group has any, so a document for an
                # owner-less group stays clean and the apply leaves owners untouched. An owner whose
                # ownership PIM for Groups holds is left out and counted (BL-125, above). Written in the
                # fixed order of Get-OEROrderedInventoryEntry, as the members are (BL-121, R-16).
                $OwnerRefs = @(foreach ($O in @($G.Owners)) {
                    if (-not $O) { continue }
                    if ($HeldIds.owner.ContainsKey(([string]$O.id).ToLowerInvariant())) { $OwnersLeftOut++; continue }
                    if ($O.userPrincipalName) { [string]$O.userPrincipalName }
                    elseif ($O.id)            { [string]$O.id }
                    else                      { [string]$O.displayName }
                })
                if ($OwnerRefs.Count -gt 0) { $Proj.owners = @(Get-OEROrderedInventoryEntry -InputObject $OwnerRefs) }
            } else {
                # An omitted owners key is ALREADY never reconciled or pruned, so omission is the
                # correct hands-off form here -- no explicit null needed. The read failure is
                # still accounted for, so the document is not silently short an owner set.
                $UnreadCollections.Add("groups/$($G.DisplayName)/owners")
            }
            # What was left out is counted per group, by name and never by principal, for the bundle
            # README (Get-OERInventoryReadme) and the roster's member count (Export-OERInventory).
            if ($MembersLeftOut -gt 0 -or $OwnersLeftOut -gt 0) {
                $PimLeftOut.Add([PSCustomObject]@{
                        GroupId = [string]$G.Id
                        Group   = [string]$G.DisplayName
                        Members = $MembersLeftOut
                        Owners  = $OwnersLeftOut
                        Basis   = $PimBasis
                    })
                # Worded per basis: on the eligibility basis they are eligible, not known to be held.
                $LeftOutWhy = if ($PimBasis -eq 'Eligibility') {
                    "since they are eligible for the same access in PIM for Groups and the group's PIM assignments could not be read"
                } else {
                    'since PIM for Groups holds their access'
                }
                Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': $MembersLeftOut member(s) and $OwnersLeftOut owner(s) left out, $LeftOutWhy."
            }
            if ($G.PSObject.Properties.Name -contains 'PimEligibility') {
                $EligIds = @(@($G.PimEligibility) | ForEach-Object { [string]$_.principalId } | Where-Object { $_ })
                $MissingEligIds = @($EligIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                if ($MissingEligIds.Count -gt 0) {
                    $Resolved = Resolve-OERPrincipalName -Id $MissingEligIds
                    foreach ($K in $Resolved.Keys) { $PrincipalNameCache[$K] = $Resolved[$K] }
                }
                # Project each eligibility so a re-apply reproduces it faithfully: accessType is always
                # emitted (member or owner) and durationDays is emitted only for a time-bound window --
                # its absence is how the apply document expresses a permanent eligibility.
                $EligRefs = @(foreach ($E in @($G.PimEligibility)) {
                    if (-not $E) { continue }
                    $PrincipalId = [string]$E.principalId
                    $Name = if ($PrincipalNameCache.ContainsKey($PrincipalId)) { $PrincipalNameCache[$PrincipalId] } else { $PrincipalId }
                    $EligProj = [ordered]@{ principal = $Name }
                    $EligProj.accessType = $(if ($E.accessId) { [string]$E.accessId } else { 'member' })
                    $EligDays = Resolve-OEREligibilityDuration -StartDateTime $E.startDateTime -EndDateTime $E.endDateTime
                    if ($null -ne $EligDays) { $EligProj.durationDays = [int]$EligDays }
                    if ($IncludeId) { $EligProj.id = $PrincipalId }
                    [PSCustomObject]$EligProj
                })
                # BL-121 (R-16): by principal, then access type, then duration (a permanent eligibility, which
                # has no durationDays, first), then id -- the last present only under -IncludeId, where it keeps
                # two principals that share a name in one order. Get-OEROrderedInventoryEntry owns the order.
                $Proj.eligibility = @(Get-OEROrderedInventoryEntry -InputObject $EligRefs -Property principal, accessType, durationDays, id)
            } else {
                # Same as owners: an omitted OR explicitly null eligibility key is never reconciled
                # or pruned, so omission is already hands-off. No principal-name lookup is issued
                # for a collection that was never read.
                $UnreadCollections.Add("groups/$($G.DisplayName)/eligibility")
            }

            $MemberPim = $null
            $OwnerPim  = $null
            # ASK FIRST WHETHER THE GROUP USES PIM FOR GROUPS AT ALL. Microsoft Graph lists
            # PIM-for-Groups policies for every group, including one never used with PIM for
            # Groups (measured live 2026-09-28), so reading and exporting them used to put a
            # default pimPolicy on EVERY group -- and a proposal that changes one of those blocks
            # onboards the group on apply, which cannot be undone (Microsoft Graph documentation,
            # "Onboarding groups to PIM for Groups"). Test-OERGroupPimInUse owns the rule: the
            # eligibility this section already read, or one listing of the group's policies for a
            # modified one (docs/development/rationale.md#pim-in-use-criterion, ruling R2). A group
            # the criterion does not find in use gets no pimPolicy key and none of the four reads
            # below. A criterion that could not be read is never guessed in either direction:
            # pimPolicy is omitted AND the collection is reported unread, with its cause, exactly
            # like a failed policy read. The null-filter on the count is load-bearing:
            # @($null).Count is 1.
            $EligibilityRead = $G.PSObject.Properties.Name -contains 'PimEligibility'
            $EligCount = if ($EligibilityRead) {
                @($G.PimEligibility | Where-Object { $null -ne $_ }).Count
            } else { 0 }
            # The criterion is asked once per group, through Get-PimUsageDecision, and the failure is
            # recorded here, where the group is known by name. A decision made ahead of the projection
            # is reused from $PimUsageDecided instead of being asked for a second time.
            $Decision = if ($PimUsageDecided.ContainsKey([string]$G.Id)) { $PimUsageDecided[[string]$G.Id] } else { Get-PimUsageDecision -Group $G -EligibilityCount $EligCount }
            $Usage = $Decision.Usage
            if ($Decision.Failed) {
                $CriterionCause = "Could not determine whether group '$($G.Id)' uses PIM for Groups: $($Decision.Message)"
                Write-Verbose "Get-OERInventory: $CriterionCause"
                Add-UnreadCause -Cause $CriterionCause -Target ([string]$G.Id)
                $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
            }
            $PimInUse = ($null -ne $Usage -and [bool]$Usage.InUse)
            if ($null -ne $Usage -and -not $PimInUse) {
                if ($EligibilityRead) {
                    Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported -- $($Usage.Reason)."
                } else {
                    # HALF AN ANSWER. The eligibility read failed, so the count above was 0 by
                    # default, not by measurement: "not in use" was decided on the policies alone
                    # and is a guess. pimPolicy is omitted and reported unread too. The eligibility
                    # read's own cause is already on the cause list (it is what omitted
                    # PimEligibility), so this adds the COLLECTION only, never a second cause. A
                    # modified policy, by contrast, decides "in use" on its own and never gets here.
                    Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported and not decided -- $($Usage.Reason), and its PIM eligibility could not be read."
                    $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
                }
            }

            # ASK NEXT WHETHER THERE IS A POLICY AT ALL, rather than reading one and swallowing
            # the answer. For a group whose policy Graph does not list (an empty assignments
            # collection, or 400 ResourceTypeNotSupported) Get-OERGroupPimPolicy correctly
            # reports a non-terminating PimPolicyNotFound -- which -ErrorAction Stop turns into
            # TWO records per call, four per group, in the CALLER's -ErrorVariable. That
            # collection is filled by the ENGINE from the error stream, so neither the catch
            # below nor any other catch in this module can reach those records: the only way not
            # to have them is not to provoke them. Measured offline on 100 groups, 96 of them
            # answering with no listed policy, driving the real wrapper and the real cmdlets with
            # only the transport stubbed: 384 records for an entirely clean read -- it does not
            # depend on whether the assignments call answers 200-empty or 400, since
            # Get-OERPimGroupPolicyId returns $null either way. A group the criterion above does
            # not find to use PIM for Groups (no PIM eligibility and no modified policy) never
            # gets this far: Graph lists a group's policies before it is onboarded (measured live
            # 2026-09-28), which is exactly why the criterion runs first, and a group it does not
            # find in use -- or could not decide -- makes none of the four calls below and
            # carries no pimPolicy. That finding is the criterion's, not a measured fact about
            # the tenant: a group used only through PIM ACTIVE assignments, with untouched
            # policies, is not found in use either (rationale.md#pim-in-use-criterion).
            #
            # NOT -ErrorAction Ignore on the reads below. That would silence a genuine 403 or 429
            # along with the not-listed case and leave the operator with a document quietly
            # missing PIM policy it had no permission to read. Get-OERPimGroupPolicyId declares
            # ResourceTypeNotSupported to the transport, so it comes back as a silent $null with
            # nothing raised anywhere, while every OTHER failure still throws.
            # A throw here is therefore NOT an answer: the read runs anyway and reports through
            # the path below. Only a confident $null skips it.
            #
            # AND THE PATH BELOW HAS TO TELL THE TWO APART, which is the whole point of the pair
            # of ids Get-OERGroupPimPolicy now emits. Suppressing PimPolicyNotFound is right --
            # a policy Graph does not list is not a finding -- but the same cmdlet used to
            # answer PimPolicyNotFound for a refusal as well, so this suppression swallowed the
            # refusal with it. Measured: a 403 on the policy-id lookup for 96 of 100 groups
            # produced 0 error records, 0 warnings, and pimPolicy absent from all 96 -- an
            # inventory that looked complete and was not, issue #76's defect class in a new
            # place. A failure now arrives as PimPolicyReadFailed and is accounted for exactly
            # like a failed members, owners or eligibility read: the CAUSE to verbose and the
            # deduplicated cause list, the COLLECTION to $UnreadCollections, and the caller names
            # it: Get-OERInventory in its InventoryPartial error, Export-OERInventory (which reads
            # its groups through this function) in the bundle's IncompleteReads and its own
            # InventoryPartial message. No per-group warning, for the reason stated at
            # the enumeration loop above: a per-collection failure is reported at the projection,
            # where the group is known by name, and 96 refused groups would otherwise print 192
            # near-identical lines and bury the one signal an operator can act on.
            #
            # pimPolicy stays OMITTED for that access type either way, never present and empty --
            # exactly as Get-OERGroup omits PimEligibility on a failed read.
            $ReadMemberPim = $false
            $ReadOwnerPim  = $false
            if ($PimInUse) {
                $ReadMemberPim = $true
                $ReadOwnerPim  = $true
                try { $ReadMemberPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType member) }
                catch { Remove-OERErrorRecord -Record $PSItem; $ReadMemberPim = $true }
                try { $ReadOwnerPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType owner) }
                catch { Remove-OERErrorRecord -Record $PSItem; $ReadOwnerPim = $true }
            }
            foreach ($PimAccessType in @('member', 'owner')) {
                if ($PimAccessType -eq 'member' -and -not $ReadMemberPim) { continue }
                if ($PimAccessType -eq 'owner' -and -not $ReadOwnerPim) { continue }
                try {
                    $PimRead = Get-OERGroupPimPolicy -Id $G.Id -AccessType $PimAccessType -ErrorAction Stop
                    if ($PimAccessType -eq 'member') { $MemberPim = $PimRead } else { $OwnerPim = $PimRead }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    if ($PSItem.FullyQualifiedErrorId -like 'PimPolicyNotFound*') { continue }
                    # Keep the CAUSE. Get-OERGroupPimPolicy composed the transport reason into
                    # this message and it lives nowhere else once the record is dropped here.
                    $PimCause = [string]$PSItem.Exception.Message
                    Write-Verbose "Get-OERInventory: $PimCause"
                    $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy/$PimAccessType")
                    Add-UnreadCause -Cause $PimCause -Target ([string]$G.Id)
                }
            }
            $MemberProj = Convert-PimAccessProjection -Policy $MemberPim
            $OwnerProj  = Convert-PimAccessProjection -Policy $OwnerPim
            if ($MemberProj -or $OwnerProj) {
                $PimProj = [ordered]@{}
                if ($MemberProj) { $PimProj.member = $MemberProj }
                if ($OwnerProj)  { $PimProj.owner = $OwnerProj }
                $Proj.pimPolicy = [PSCustomObject]$PimProj
            }
            $Groups.Add([PSCustomObject]$Proj)
        }

        # -ExcludeSharedName: none of the groups that share a name is written, and the name is reported
        # instead -- the unread entry 'groups/<name>' with the spelling of the first listed group that
        # carries it, and the cause -- once however many groups share it. The same rule, wording and
        # order as Get-OERInventory's Select-UniqueNamedEntry: added after every other finding of this
        # section. A group left out of the document removes nothing: Invoke-OERStructure prunes child
        # collections only.
        if ($ExcludeSharedName) {
            $UniqueGroups = [System.Collections.Generic.List[object]]::new()
            foreach ($P in $Groups) {
                if ($SharedNameCount[[string]$P.displayName] -gt 1) { continue }
                $UniqueGroups.Add($P)
            }
            $Groups = $UniqueGroups
            # A group that is not written has nothing left out of it either: its PimLeftOut entry goes
            # with it, by the same name rule.
            $UniquePimLeftOut = [System.Collections.Generic.List[object]]::new()
            foreach ($E in $PimLeftOut) {
                if ($SharedNameCount[[string]$E.Group] -gt 1) { continue }
                $UniquePimLeftOut.Add($E)
            }
            $PimLeftOut = $UniquePimLeftOut
            # The same for the count of a dynamic group's members (R-15): the group is not written, so the
            # roster has no count of it to give.
            $UniqueDynamicMembers = [System.Collections.Generic.List[object]]::new()
            foreach ($E in $DynamicMembers) {
                if ($SharedNameCount[[string]$E.Group] -gt 1) { continue }
                $UniqueDynamicMembers.Add($E)
            }
            $DynamicMembers = $UniqueDynamicMembers
            $ReportedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($G in $GroupItems) {
                $SharedName = [string]$G.DisplayName
                if ($SharedNameCount[$SharedName] -le 1 -or -not $ReportedNames.Add($SharedName)) { continue }
                $SharedPath = "groups/$SharedName"
                $UnreadCollections.Add($SharedPath)
                $SharedCause = Get-OERSharedNameCause -Path $SharedPath -Count $SharedNameCount[$SharedName]
                Write-Verbose "Get-OERInventory: $SharedCause"
                # BL-156: a BLANK Target, as Get-OERInventory's Select-UniqueNamedEntry registers the same
                # cause, so Format-OERUnreadCauseClause keys it on its full text and two names of one
                # count are two causes, not one with the name normalised away.
                Add-UnreadCause -Cause $SharedCause -Target ''
                # BL-131: the name with its count, for the export's one warning and its README.
                $SharedNames.Add([PSCustomObject]@{ Section = 'groups'; Name = $SharedName; Count = $SharedNameCount[$SharedName] })
            }
        }

        $Result = [PSCustomObject]@{
            Groups         = $Groups.ToArray()
            Unread         = $UnreadCollections.ToArray()
            Causes         = $Causes.ToArray()
            PimLeftOut     = $PimLeftOut.ToArray()
            DynamicMembers = $DynamicMembers.ToArray()
            SharedNames    = $SharedNames.ToArray()
        }
        $Result.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryGroupRead')
        $Result
    } finally {
        if ($ProgressActivity) { Write-Progress -Activity $ProgressActivity -Completed }
    }
}
