function ConvertTo-OERPruneWithheldResult {
    <#
    .SYNOPSIS
    Builds the Skipped record that withholds a prune when a declared entry, or the scope of one, could not be resolved, when a live scoped role's name could not be read, when a live group member or owner is a service principal, or when a live administrative unit member is a group this run created into the unit.

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

    A third kind of entry is not an unresolved declared entry at all: it is a LIVE administrative unit
    scoped role whose name the directory role list did not give (the role id is known, the name is
    blank), held by a principal for whom the document declares a role BY NAME that no live role of that
    principal matches by name. Such a live role may be the very role the document declares, so adding
    the declared role would duplicate it and pruning the live one would remove it. The caller names
    the declared entry with -Declared and the role ids with -UnnamedRoleId, and this helper then ALWAYS
    returns exactly one Skipped record (the empty-list rule above does not apply to this kind) whose
    Detail starts 'prune withheld: ', says the declared role matches no live scoped role by name, names
    every unnamed role id in the order given, and states that the role is neither added nor removed
    (the module's own guard, not a Graph rejection). Declaring the role by its role id reconciles it.

    A fourth kind is a LIVE group member or owner that is a service principal (decision A9, Sprint 9
    step 1). Microsoft Graph's v1.0 member and owner lists leave service principals out, so before the
    typed read in Get-OERGroupRelation the module never saw one in a group: no earlier version pruned
    one, and no document exported by an earlier version lists one. The group prune therefore never
    removes a service principal. The caller passes the candidate's ObjectType as -ObjectType, and this
    helper owns both the rule and its texts: it returns nothing unless the type is servicePrincipal
    (compared ignoring case, as the handler compares every string), so a member or owner of any other
    type, or of no type, is reported and pruned as before. For a service principal it returns exactly
    one record: with -Prune a Skipped record whose Detail starts 'prune withheld: ' and states that
    -Prune never removes a service principal from a group (the module's own guard, not a Graph
    rejection), and without -Prune the Extra record the pass would have written, whose hint says that
    -Prune leaves it in place rather than "use -Prune to remove". The caller calls it straight after
    the unresolved-entry call above and before any other guard, the last-owner guard included, and
    continues with the next candidate when it returns a record: no Write-Warning and no
    ShouldProcess prompt is issued for it.

    A fifth kind is a LIVE administrative unit member that is a group the groups section created INTO
    that unit earlier in the same run (New-OERGroup -AdministrativeUnit, BL-07). A group's
    administrativeUnit is applied only when the group is created and never round-trips, so the unit's
    own entry need not list the group, and the administrativeUnits section runs after the groups
    section: without this rule -Prune would remove the membership the same run had just created.
    Sync-OERStructureAdministrativeUnit decides that a candidate is such a group, from the record the
    group handler kept, and passes the group's name as -CreatedGroup; this helper owns the text. With
    -Prune it returns exactly one Skipped record whose Detail starts 'prune withheld: ', names the
    candidate and the group, says the run that creates a membership does not remove it (the module's
    own guard, not a Graph rejection), and that the next apply with -Prune removes it unless the
    unit's members name the group. Without -Prune it returns nothing, so the pass reports the
    candidate Extra as before. The caller calls it straight after the unresolved-entry call and before
    its -Prune branch, and continues with the next candidate when it returns a record: no
    Write-Warning and no ShouldProcess prompt is issued for it.

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
    example "undeclared member '<id>'". Used by the -Unresolved, the -ObjectType and the
    -CreatedGroup forms.

    .PARAMETER UnresolvedScope
    The labels of the declared entries of the section whose scope could not be resolved, in document
    order. Optional, and empty by default. Such an entry may name any scope in the section, so a
    non-empty list withholds the candidate whichever collection it belongs to.

    .PARAMETER Declared
    A readable description of the declared entry that was declared by role name and matches no live
    scoped role by name, for example "scopedRole 'User Administrator' for 'person1@example.com'".
    Mandatory with -UnnamedRoleId, and not combinable with -Unresolved, -Candidate or -UnresolvedScope.

    .PARAMETER UnnamedRoleId
    The role ids of the live scoped roles that principal holds on the unit whose names the directory
    role list did not give, in the order the caller wants them named. One id or several; at least one
    is expected, since the record says the declared role may be one of them.

    .PARAMETER ObjectType
    The ObjectType of the live group member or owner the pass would otherwise report Extra or remove,
    as Get-OERGroup gives it (servicePrincipal, user, group, device, or null when the read carried no
    type). Only servicePrincipal returns a record. Not combinable with -Unresolved, -UnresolvedScope,
    -Declared or -UnnamedRoleId.

    .PARAMETER CreatedGroup
    The name of the group the groups section created into the unit in this run, which the live
    candidate is (the label the group handler recorded). Mandatory in this form, and not combinable
    with -Unresolved, -UnresolvedScope, -Declared, -UnnamedRoleId or -ObjectType.

    .PARAMETER Prune
    With -ObjectType: whether the caller runs with -Prune. With it the service principal's record is
    the Skipped "prune withheld:" record; without it, the Extra record. With -CreatedGroup: with it
    the Skipped "prune withheld:" record; without it nothing, so the caller reports Extra.

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

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' -Declared "scopedRole 'User Administrator' for 'person1@example.com'" -UnnamedRoleId @('dirrole-1')

    Returns one Skipped record saying the declared role matches no live scoped role by name while the
    principal holds a live scoped role whose name could not be read (role id 'dirrole-1'), so the role
    is neither added nor removed.

    .EXAMPLE
    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -ObjectType $CurMember.ObjectType -Candidate "undeclared member '$CurId'" -Prune:$Prune
    if ($Withheld) { $Withheld; continue }

    Emits the service principal's Skipped record (with -Prune) or its Extra record (without), and
    moves on to the next live member, when the member is a service principal; otherwise the pass
    reports or prunes it as usual.

    .EXAMPLE
    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' -Candidate "undeclared member '$CurId'" -CreatedGroup 'grp-new' -Prune:$Prune
    if ($Withheld) { $Withheld; continue }

    Emits the Skipped record and moves on to the next live member under -Prune, for a member that is
    the group 'grp-new' this run created into the unit; without -Prune it returns nothing and the
    pass reports the member Extra as usual.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Unresolved')]
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory, ParameterSetName = 'Unresolved')][AllowEmptyCollection()][AllowEmptyString()][string[]]$Unresolved,
        [Parameter(Mandatory, ParameterSetName = 'Unresolved')]
        [Parameter(Mandatory, ParameterSetName = 'ObjectType')]
        [Parameter(Mandatory, ParameterSetName = 'CreatedGroup')][string]$Candidate,
        [Parameter(ParameterSetName = 'Unresolved')][AllowEmptyCollection()][string[]]$UnresolvedScope = @(),
        [Parameter(Mandatory, ParameterSetName = 'UnreadRoleName')][string]$Declared,
        [Parameter(Mandatory, ParameterSetName = 'UnreadRoleName')][string[]]$UnnamedRoleId,
        [Parameter(Mandatory, ParameterSetName = 'ObjectType')][AllowNull()][AllowEmptyString()][string]$ObjectType,
        [Parameter(Mandatory, ParameterSetName = 'CreatedGroup')][string]$CreatedGroup,
        [Parameter(ParameterSetName = 'ObjectType')]
        [Parameter(ParameterSetName = 'CreatedGroup')][switch]$Prune
    )

    if ($PSCmdlet.ParameterSetName -eq 'CreatedGroup') {
        if (-not $Prune) { return }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
            -Detail "prune withheld: $Candidate is group '$CreatedGroup', which this run created into this unit, and the run that creates a membership does not remove it (our own guard, not a Graph rejection). The next apply with -Prune removes it unless the unit's members name the group."
    }

    if ($PSCmdlet.ParameterSetName -eq 'ObjectType') {
        if ($ObjectType -ne 'servicePrincipal') { return }
        if ($Prune) {
            return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
                -Detail "prune withheld: $Candidate is a service principal, and -Prune never removes a service principal from a group; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember (-AccessType owner for an owner) if it is meant to go."
        }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Extra' `
            -Detail "$Candidate (a service principal, which -Prune leaves in place)"
    }

    if ($PSCmdlet.ParameterSetName -eq 'UnreadRoleName') {
        $QuotedIds = ($UnnamedRoleId | ForEach-Object { "'$_'" }) -join ', '
        $Detail = if (@($UnnamedRoleId).Count -eq 1) {
            "prune withheld: $Declared matches no live scoped role by name, and the principal holds a live scoped role on this unit whose name could not be read (role id $QuotedIds), which may be that role; it is neither added nor removed (our own guard, not a Graph rejection). Declare the role by the directory role id its live scoped role carries (RoleId in Get-OERAdministrativeUnit -IncludeScopedRoles) to reconcile it."
        } else {
            "prune withheld: $Declared matches no live scoped role by name, and the principal holds $(@($UnnamedRoleId).Count) live scoped roles on this unit whose names could not be read (role ids $QuotedIds), any of which may be that role; none of them is added or removed (our own guard, not a Graph rejection). Declare the role by the directory role id its live scoped role carries (RoleId in Get-OERAdministrativeUnit -IncludeScopedRoles) to reconcile it."
        }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' -Detail $Detail
    }

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
