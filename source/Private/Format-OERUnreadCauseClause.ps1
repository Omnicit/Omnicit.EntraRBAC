function Format-OERUnreadCauseClause {
    <#
    .SYNOPSIS
    Formats the "Causes: ..." clause that the inventory's InventoryPartial message appends.

    .DESCRIPTION
    The single owner of how the read-failure causes behind an unread collection are worded in the
    InventoryPartial message. The unread names say WHICH collection is missing; this clause says
    WHY, and the reason is what tells an operator to retry (429) rather than grant a scope (403).

    -Cause takes the raw causes in the order they were found: objects with a Cause (the message) and
    a Target (the TargetObject of the record the message came from, which is the failing object's
    id). A cause whose text is blank is skipped. The causes are DEDUPLICATED on a key, and the clause
    shows the FIRST full message per key, in order. The key is the message with its Target replaced
    by <id> (when the Target is not blank), compared without regard to letter case, because
    Get-OERGroup and Get-OERAdministrativeUnit both interpolate the failing object's id into the
    message: seven units failing for one identical reason produced seven distinct strings (measured
    on a live tenant) until the id was normalised away. The key needs no id-shaped pattern, since
    the Target is the record's own TargetObject. A throttle that hits every group is then one cause,
    not one per group. A cause given a blank Target is keyed on its full text: the shared-name causes
    (Get-OERSharedNameCause) are given none, since their text already names the objects, so two
    names of one count are two causes and the same name is still stated once.

    At most 23 distinct causes are shown. When the cap drops some, the clause says how many distinct
    ones were dropped and where to find them (the verbose stream carries every cause as it is seen).
    The dropped count is derived from the keys, so it can never disagree with what the clause shows.

    Returns an empty string when no non-blank cause was given, so the caller can append the result
    to a message without a condition.

    .PARAMETER Cause
    The raw causes, in the order they were found. Each is an object with a Cause string and a Target
    string. A null entry, and an entry whose Cause is blank, is skipped.

    .PARAMETER Label
    The lead-in of the clause, shown before the colon. The default is Causes.

    .EXAMPLE
    Format-OERUnreadCauseClause -Cause @([PSCustomObject]@{ Cause = 'Too many requests (429).'; Target = '' })
    Returns " Causes: Too many requests (429)." ready to append to the InventoryPartial message.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Cause,

        [ValidateNotNullOrEmpty()]
        [string]$Label = 'Causes'
    )

    # Cap on the DISTINCT causes named in one clause -- one call of this function, so each clause
    # of Export-OERInventory's InventoryPartial message and Get-OERInventory's own has a cap of its
    # own. It bounds the length of the message; it is NOT one per cause message shape. It was set
    # at twenty-three when that was the number of shapes Get-OERInventory could add (group members,
    # group owners, group PIM eligibility, group PIM-in-use criterion, group PIM policy, AU members,
    # AU scoped roles, directory role eligibility schedules, directory role assignment schedules,
    # directory role policies, access package resource role bindings, catalog resources, the
    # catalog resource-name map, the catalog list, a catalog's package list, an access package's
    # assignment policies, an access review's access package name, an access review's assignment
    # policy name, objects not written because two of them share a name, the group list, the
    # administrative unit list, the access review list and an entry written as null because it has
    # no name). Later steps added more, to Get-OERInventory's clause or to the export's group clause,
    # and the list was not kept (recounted in Sprint 11 step 8):
    # the group PIM for Groups assignments, the group relevance reads, the group name index, the
    # access review name uniqueness checks, the scoped role principal type lookup, and, in a
    # standalone call, the role assignment principal lookups and the subscription home tenant
    # reasons -- so one call can now differ in more ways than the cap, and a cause message that
    # carries a raw error text is a key of its own per text anyway. The cap is kept: a partial run
    # with one or a few failure kinds is still reported in full, a run that fails in more than
    # twenty-three distinct ways names the first twenty-three in the order they were found and
    # states how many more were dropped, and nothing is discarded either way -- every cause is
    # written to the verbose stream as it is seen. Do not raise it for each new shape; raise it
    # only when a normal partial run is seen to be truncated.
    $UnreadCauseCap = 23

    # The dedupe KEYS, and the causes the clause will show. The dedupe used to compare whole
    # messages and could therefore never fire: Get-OERGroup and Get-OERAdministrativeUnit both
    # interpolate the failing object's id into the message, so seven units failing for one
    # identical reason produced seven distinct strings (measured on a live tenant). The key
    # normalises that id away; the list still stores the FIRST full message per key, so one
    # concrete id survives as an example. A key is recorded even once the cap is reached, which
    # is what lets the dropped count be derived from the two collections below.
    $UnreadCauseKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Shown = [System.Collections.Generic.List[string]]::new()

    foreach ($Entry in @($Cause)) {
        if ($null -eq $Entry) { continue }
        $Text = [string]$Entry.Cause
        if ([string]::IsNullOrWhiteSpace($Text)) { continue }
        $Target = [string]$Entry.Target
        $Key = $Text
        if (-not [string]::IsNullOrWhiteSpace($Target)) { $Key = $Key.Replace($Target, '<id>') }
        if (-not $UnreadCauseKeys.Add($Key)) { continue }
        if ($Shown.Count -lt $UnreadCauseCap) { $Shown.Add($Text) }
    }

    if ($Shown.Count -eq 0) { return '' }

    # Capped, and the truncation is STATED. The causes are deduplicated on a normalised key, so
    # the clause only grows when the failures genuinely differ -- but a large tenant can still
    # differ in many ways, and an error message thousands of causes long is unreadable and
    # unloggable. The dropped count is derived rather than counted, so it can never disagree with
    # what the list actually holds.
    $Suppressed = $UnreadCauseKeys.Count - $Shown.Count
    $MoreClause = if ($Suppressed -gt 0) { ", plus $Suppressed more distinct cause(s) not shown -- rerun with -Verbose for all of them" } else { '' }
    " ${Label}: $($Shown -join '; ')$MoreClause."
}
