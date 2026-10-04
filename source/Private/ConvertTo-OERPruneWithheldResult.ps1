function ConvertTo-OERPruneWithheldResult {
    <#
    .SYNOPSIS
    Builds the Skipped record that withholds a prune when a declared entry, or the scope of one, could not be resolved.

    .DESCRIPTION
    The single owner of the apply engine's withhold-prune rule and of its reason text. Every
    Sync-OERStructure* prune pass builds a set of DECLARED keys from the document and treats a live
    entry whose key is not in that set as undeclared: it is reported Extra, or removed under -Prune.
    A declared entry whose lookup gave no object id never enters that set, so the live entry it was
    meant to name looks undeclared -- and without this rule -Prune would delete exactly the object
    the document asked to keep.

    A prune pass therefore collects, per collection, the labels of the declared entries it could not
    resolve, and calls this helper FIRST for every live candidate it would otherwise report Extra or
    remove -- before its -Prune branch and before any other guard. The rule is deliberately
    collection-wide: an unresolved entry carries no key, so the pass cannot tell which live candidate
    it corresponds to, and every candidate in that collection is withheld until the document is fixed.

    A second kind of unresolved entry is one whose SCOPE could not be resolved (the roleAssignments
    section, where every entry names the Azure scope it applies to). Such an entry carries no scope at
    all, so it may be another spelling of ANY scope in the section, and the rule widens with it: every
    candidate at every scope of the section is withheld until the entry is fixed or removed. The
    caller passes the labels of those entries as -UnresolvedScope.

    Returns nothing when -Unresolved and -UnresolvedScope are both empty, so the caller carries on
    with its normal Extra or prune path. Otherwise returns exactly one
    Omnicit.EntraRBAC.StructureResult record, built through ConvertTo-OERStructureResult, with Action
    Skipped and a Detail that starts with the phrase 'prune withheld: ', names every unresolved entry
    in the order given, names the candidate, and states that the refusal is the module's own guard
    rather than a Graph rejection. When both lists are given, the sentence about the unresolved
    entries comes first and a second sentence names the entries whose scope could not be resolved.
    The caller then continues with the next candidate: no Write-Warning and no ShouldProcess prompt
    is issued for a withheld candidate, and the unresolved entry keeps its own Failed record.

    .PARAMETER Section
    The document section the prune pass belongs to (for example groups or administrativeUnits).

    .PARAMETER Item
    The Item label the pass would have used for the candidate's Extra or Removed record, so the
    Skipped record lands on the same row.

    .PARAMETER Unresolved
    The labels of the declared entries in this collection that could not be resolved, in document
    order. An empty collection, together with an empty -UnresolvedScope, means nothing was
    unresolved and the helper returns nothing.

    .PARAMETER Candidate
    A readable description of the live entry the pass would otherwise report Extra or remove, for
    example "undeclared member '<id>'".

    .PARAMETER UnresolvedScope
    The labels of the declared entries of the section whose scope could not be resolved, in document
    order. Optional, and empty by default. Such an entry may name any scope in the section, so a
    non-empty list withholds the candidate whichever collection it belongs to.

    .EXAMPLE
    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -Unresolved $MemberUnresolved -Candidate "undeclared member '$CurId'"
    if ($Withheld) { $Withheld; continue }

    Emits the Skipped record and moves on to the next live member when at least one declared member
    of the group could not be resolved; otherwise the prune pass continues as usual.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -Unresolved @() -Candidate "undeclared member 'u-1'"

    Returns nothing, since no declared entry was unresolved.

    .EXAMPLE
    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item $ExtraItem -Unresolved $SiblingUnresolved -UnresolvedScope $ScopeUnresolved -Candidate $CurLabel
    if ($Withheld) { $Withheld; continue }

    Emits the Skipped record and moves on to the next live assignment when the scope of at least one
    declared entry in the section could not be resolved, or when a sibling at this scope could not be
    resolved; otherwise the prune pass continues as usual.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Unresolved,
        [Parameter(Mandatory)][string]$Candidate,
        [AllowEmptyCollection()][string[]]$UnresolvedScope = @()
    )

    $HasEntry = @($Unresolved).Count -gt 0
    $HasScope = @($UnresolvedScope).Count -gt 0
    if (-not $HasEntry -and -not $HasScope) { return }

    $QuotedScope = ($UnresolvedScope | ForEach-Object { "'$_'" }) -join ', '
    if ($HasEntry) {
        $Quoted = ($Unresolved | ForEach-Object { "'$_'" }) -join ', '
        $Detail = if (@($Unresolved).Count -eq 1) {
            "prune withheld: declared entry $Quoted could not be resolved, so $Candidate may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection."
        } else {
            "prune withheld: declared entries $Quoted could not be resolved, so $Candidate may be the live counterpart of one of them and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this collection."
        }
        if ($HasScope) {
            $Detail += if (@($UnresolvedScope).Count -eq 1) {
                " The scope of declared entry $QuotedScope could not be resolved either."
            } else {
                " The scopes of declared entries $QuotedScope could not be resolved either."
            }
        }
    } elseif (@($UnresolvedScope).Count -eq 1) {
        $Detail = "prune withheld: the scope of declared entry $QuotedScope could not be resolved, so it may name this scope, and $Candidate may be the live counterpart of that entry; it is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this section."
    } else {
        $Detail = "prune withheld: the scopes of declared entries $QuotedScope could not be resolved, so any of them may name this scope, and $Candidate may be the live counterpart of one of them; it is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this section."
    }

    ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' -Detail $Detail
}
