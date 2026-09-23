function ConvertTo-OERPruneWithheldResult {
    <#
    .SYNOPSIS
    Builds the Skipped record that withholds a prune when a declared entry could not be resolved.

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

    Returns nothing when -Unresolved is empty, so the caller carries on with its normal Extra or
    prune path. Otherwise returns exactly one Omnicit.EntraRBAC.StructureResult record, built through
    ConvertTo-OERStructureResult, with Action Skipped and a Detail that starts with the phrase
    'prune withheld: ', names every unresolved entry in the order given, names the candidate, and
    states that the refusal is the module's own guard rather than a Graph rejection. The caller then
    continues with the next candidate: no Write-Warning and no ShouldProcess prompt is issued for a
    withheld candidate, and the unresolved entry keeps its own Failed record.

    .PARAMETER Section
    The document section the prune pass belongs to (for example groups or administrativeUnits).

    .PARAMETER Item
    The Item label the pass would have used for the candidate's Extra or Removed record, so the
    Skipped record lands on the same row.

    .PARAMETER Unresolved
    The labels of the declared entries in this collection that could not be resolved, in document
    order. An empty collection means nothing was unresolved and the helper returns nothing.

    .PARAMETER Candidate
    A readable description of the live entry the pass would otherwise report Extra or remove, for
    example "undeclared member '<id>'".

    .EXAMPLE
    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -Unresolved $MemberUnresolved -Candidate "undeclared member '$CurId'"
    if ($Withheld) { $Withheld; continue }

    Emits the Skipped record and moves on to the next live member when at least one declared member
    of the group could not be resolved; otherwise the prune pass continues as usual.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -Unresolved @() -Candidate "undeclared member 'u-1'"

    Returns nothing, since no declared entry was unresolved.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Unresolved,
        [Parameter(Mandatory)][string]$Candidate
    )

    if (@($Unresolved).Count -eq 0) { return }

    $Quoted = ($Unresolved | ForEach-Object { "'$_'" }) -join ', '
    $Detail = if (@($Unresolved).Count -eq 1) {
        "prune withheld: declared entry $Quoted could not be resolved, so $Candidate may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection."
    } else {
        "prune withheld: declared entries $Quoted could not be resolved, so $Candidate may be the live counterpart of one of them and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this collection."
    }

    ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' -Detail $Detail
}
