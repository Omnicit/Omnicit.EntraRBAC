function ConvertTo-OERPruneWithheldResult {
    <#
    .SYNOPSIS
    Builds the Skipped record that withholds a prune when a declared entry, or the scope of one, could not be resolved, when a live scoped role's name could not be read, when a live group member or owner is a service principal, when a live administrative unit member is a group this run created into the unit, or found already existing when it went to create it, when the live group is synchronized from on-premises, or when PIM for Groups holds a live group member or owner or makes it eligible, or whether it does could not be read, or when the signed-in identity's object id is unknown, or when its group memberships could not be read.

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
    that unit earlier in the same run, or found already existing in place of creating it
    (New-OERGroup -AdministrativeUnit, BL-07; the record is kept for both, since the handler cannot
    tell them apart: a group another process created between the handler's read and its create comes
    back from New-OERGroup as the existing group, which is not re-parented). A group's
    administrativeUnit is applied only when the group is created and never round-trips, so the unit's
    own entry need not list the group, and the administrativeUnits section runs after the groups
    section: without this rule -Prune would remove the membership the same run had just created.
    Sync-OERStructureAdministrativeUnit decides that a candidate is such a group, from the record the
    group handler kept, and passes the group's name as -CreatedGroup; this helper owns the text. With
    -Prune it returns exactly one Skipped record whose Detail starts 'prune withheld: ', names the
    candidate and the group, says the groups section of this run either created the group into the
    unit or, when it already existed, found it in place of creating it, and that this run does not
    remove that membership (the module's own guard, not a Graph rejection), and that the next apply
    with -Prune removes it unless the unit's members name the group. Without -Prune it returns
    nothing, so the pass reports the candidate Extra as before. The caller calls it straight after the unresolved-entry call and before
    its -Prune branch, and continues with the next candidate when it returns a record: no
    Write-Warning and no ShouldProcess prompt is issued for it.

    A sixth kind is every LIVE member, owner or eligibility of a group synchronized from on-premises
    (decision A15, Sprint 10 step 7b). Such a group is managed in on-premises Active Directory and is
    read-only in the cloud, so the group prune removes nothing from it. The caller decides that the
    group is synchronized, from its live read, with Test-OERGroupOnPremisesSynced, and passes the
    group's live display name as -SyncedGroup; this helper owns both texts. With -Prune it returns
    exactly one Skipped record whose Detail starts 'prune withheld: ', names the candidate and the
    group, says the apply engine writes nothing to such a group, -Prune included (the module's own
    guard, not a Graph rejection), and that the candidate is removed in the on-premises directory if
    it is meant to go.
    Without -Prune it returns the Extra record the pass would have written, whose hint says that
    -Prune leaves it in place rather than "use -Prune to remove". The caller calls it straight after
    the unresolved-entry and service-principal calls above and before any other guard, the last-owner
    guard included, and continues with the next candidate: no ShouldProcess prompt is issued for it.
    Under -Prune the caller writes its one warning for the item itself, before the first such record;
    this helper writes none.

    A seventh kind is a LIVE group member or owner whose access to the group PIM for Groups holds or
    makes eligible (BL-125, decision A3): an activation, a time-bound active assignment, an active
    assignment that is not a standing one, or an eligibility, for the same access type (member or
    owner) as the candidate. Removing such a principal as an undeclared standing member or owner would
    end access PIM for Groups manages, or a membership an activation granted for a limited time. The
    caller decides the hold (Read-OERGroupPimHold, whose rule Get-OERGroupPimHeldAccess owns) and
    passes the rule's reason as -PimHeldReason, for example 'holds member access through an activation
    in PIM for Groups'; this helper owns both record texts. With -Prune it returns exactly one Skipped
    record whose Detail starts 'prune withheld: ', names the candidate and the reason, and says that
    -Prune never removes a member or owner whose access PIM for Groups holds or makes eligible (the
    module's own guard, not a Graph rejection), and that the access is managed in PIM for Groups if it
    is meant to go. Without -Prune it returns the Extra record the pass would have written, whose hint
    names the reason and says that -Prune leaves the candidate in place rather than "use -Prune to
    remove". The caller calls it after the unresolved-entry, service-principal and synchronized-group
    rules above and, for owners, before the last-owner guard, and continues with the next candidate:
    no Write-Warning and no ShouldProcess prompt is issued for it.

    An eighth kind is a LIVE group member or owner for which whether PIM for Groups holds it or makes
    it eligible could not be read (BL-125): the group's PIM for Groups assignment read or its
    eligibility read failed. Such a candidate may be one PIM for Groups holds, so it is never removed,
    and the rule is collection-wide like an unresolved entry: every undeclared candidate of the
    collection is withheld. The caller passes the failed read's message as -PimUnread; this helper
    owns the text. It ALWAYS returns exactly one Skipped record, with or without -Prune, whose Detail
    starts 'prune withheld: ', names the candidate and the cause, says the candidate is left in place
    (the module's own guard, not a Graph rejection), and asks for the document to be applied again
    once the group's PIM for Groups assignments and eligibility can be read. The caller writes its one
    warning for the item itself, naming the cause, before the first such record; this helper writes
    none, and no ShouldProcess prompt is issued for it.

    A ninth and a tenth kind belong to the directory role assignment handler's prune pass (BL-86).
    Both are the rows it used to word inline, and both are ALWAYS one Skipped record, with or without
    -Prune, since the handler writes them before it looks at -Prune; neither takes -Prune. The ninth
    (-SignedInIdUnknown) is a live candidate withheld because the signed-in identity's object id is
    unknown, so the candidate may be that identity's own assignment: the Detail starts 'prune
    withheld: the signed-in identity's object id is unknown (', gives the cause (-Reason, by default
    that it could not be determined from the session's Microsoft Graph token), names the candidate,
    states that it is left in place (the module's own guard, not a Graph rejection), and asks for a
    new sign-in with Connect-OER. The tenth (-MembershipUnread) is a live group (or principal of
    unknown type) candidate withheld because the signed-in identity's group memberships could not be
    read, so the candidate may be a group the identity gets the role through: the Detail starts
    'prune withheld: the signed-in identity's group memberships could not be read', names the
    candidate, says how the identity would get the role through the group, states that the candidate
    is left in place (the module's own guard, not a Graph rejection), and ends with the read's
    message (-Reason). How the identity gets the role depends on the pair's kind, which the caller
    passes as -PairKind (BL-24): through an Active assignment it holds the role, so the Detail says
    'holds the role through'; through an Eligible one it is only eligible for the role until it
    activates it, so the Detail says 'is eligible for the role through' (the record's 'may be a
    group' already carries the uncertainty). The caller writes the
    group memberships' failure once for the pass; this helper writes nothing, and no ShouldProcess
    prompt is issued for either record.

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
    example "undeclared member '<id>'". Used by the -Unresolved, the -ObjectType, the -CreatedGroup,
    the -SyncedGroup, the -PimHeldReason, the -PimUnread, the -SignedInIdUnknown and the
    -MembershipUnread forms.

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
    The name of the group the groups section created into the unit in this run, or found already
    existing when it went to create it, which the live candidate is (the label the group handler
    recorded). Mandatory in this form, and not combinable
    with -Unresolved, -UnresolvedScope, -Declared, -UnnamedRoleId or -ObjectType.

    .PARAMETER SyncedGroup
    The live display name of the group whose live read shows it synchronized from on-premises
    (Test-OERGroupOnPremisesSynced): the name the group carries as read, which for a group found
    only under its previousDisplayName is not the document's new displayName (the record's -Item
    stays the document's label). Mandatory in this form, and not combinable with -Unresolved,
    -UnresolvedScope, -Declared, -UnnamedRoleId, -ObjectType or -CreatedGroup.

    .PARAMETER PimHeldReason
    The reason PIM for Groups holds the live candidate's access or makes it eligible, as
    Get-OERGroupPimHeldAccess words it (for example 'is eligible for member access in PIM for
    Groups'), for the access type the candidate has. Mandatory in this form, and not combinable with
    -Unresolved, -UnresolvedScope, -Declared, -UnnamedRoleId, -ObjectType, -CreatedGroup, -SyncedGroup
    or -PimUnread.

    .PARAMETER PimUnread
    The message of the read that failed when the caller asked whether PIM for Groups holds the
    group's members and owners or makes them eligible (Read-OERGroupPimHold's Cause). Mandatory in
    this form; an empty or null message is accepted. Not combinable with -Prune or with any other
    form's parameter: the record is the same with or without -Prune.

    .PARAMETER SignedInIdUnknown
    Selects the form for a live candidate withheld because the signed-in identity's object id is
    unknown (Get-OERSignedInObjectId returned nothing). Mandatory in this form, which takes
    -Candidate and, optionally, -Reason. Not combinable with -Prune or with any other form's
    parameter: the record is the same with or without -Prune.

    .PARAMETER MembershipUnread
    Selects the form for a live group (or unknown-type) candidate withheld because the signed-in
    identity's group memberships could not be read. Mandatory in this form, which takes -Candidate,
    -PairKind and -Reason. Not combinable with -Prune or with any other form's parameter: the record
    is the same with or without -Prune.

    .PARAMETER PairKind
    The kind of the (role, assignmentType) pair the candidate belongs to, Eligible or Active (letter
    case ignored), which decides how the record words the signed-in identity's access through the
    group: an Active assignment is held ('holds the role through'), an Eligible one makes the
    identity eligible for the role until it activates it ('is eligible for the role through').
    Mandatory with -MembershipUnread.

    .PARAMETER Reason
    With -MembershipUnread: the message of the read that failed (Get-OERMemberGroupId), appended to
    the Detail after a colon. Mandatory in that form; an empty or null message is accepted, so a
    failure that carries none still gives the Skipped record instead of a binding error that would
    end the calling handler's item outside its own try. With -SignedInIdUnknown: the cause named in
    the parentheses after 'unknown'. Optional there; omitted, empty or white space, it is that the id
    could not be determined from the session's Microsoft Graph token.

    .PARAMETER Prune
    With -ObjectType: whether the caller runs with -Prune. With it the service principal's record is
    the Skipped "prune withheld:" record; without it, the Extra record. With -CreatedGroup: with it
    the Skipped "prune withheld:" record; without it nothing, so the caller reports Extra. With
    -SyncedGroup or -PimHeldReason: with it the Skipped "prune withheld:" record; without it, the
    Extra record whose hint says -Prune leaves the candidate in place.

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
    the group 'grp-new' this run created into the unit (or found already existing); without -Prune it returns nothing and the
    pass reports the member Extra as usual.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'grp-synced' -Candidate "undeclared member '$CurId'" -SyncedGroup 'grp-synced' -Prune:$Prune
    continue

    For a group whose live read shows it synchronized from on-premises: emits the Skipped "prune
    withheld:" record (with -Prune) or the Extra record whose hint says -Prune leaves the member in
    place (without), and moves on to the next live member. Nothing is removed from such a group.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'grp-pim' -Candidate "undeclared member '$CurId'" -PimHeldReason 'holds member access through an activation in PIM for Groups' -Prune:$Prune
    continue

    For a live member whose membership PIM for Groups holds: emits the Skipped "prune withheld:"
    record (with -Prune) or the Extra record whose hint names the reason and says -Prune leaves the
    member in place (without), and moves on to the next live member.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'grp-pim' -Candidate "undeclared owner '$CurId'" -PimUnread $Hold.Cause
    continue

    When whether PIM for Groups holds the group's members and owners could not be read: emits the
    Skipped "prune withheld:" record naming the cause, with or without -Prune, and moves on to the
    next live owner.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'directoryRoleAssignments' -Item $CandItem -SignedInIdUnknown -Candidate $CandLabel
    continue

    When the signed-in identity's object id is unknown: emits the Skipped "prune withheld:" record
    saying the candidate may be that identity's own assignment and is left in place, with or without
    -Prune, and moves on to the next live candidate.

    .EXAMPLE
    ConvertTo-OERPruneWithheldResult -Section 'directoryRoleAssignments' -Item $CandItem -MembershipUnread -Candidate $CandLabel -PairKind 'Eligible' -Reason $Failure.Exception.Message
    continue

    When the signed-in identity's group memberships could not be read: emits the Skipped "prune
    withheld:" record saying the candidate may be a group the identity is eligible for the role
    through (an Active pair says 'holds the role through'), and ending with the read's message, with
    or without -Prune, and moves on to the next live candidate.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SignedInIdUnknown',
        Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MembershipUnread',
        Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Unresolved')]
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory, ParameterSetName = 'Unresolved')][AllowEmptyCollection()][AllowEmptyString()][string[]]$Unresolved,
        [Parameter(Mandatory, ParameterSetName = 'Unresolved')]
        [Parameter(Mandatory, ParameterSetName = 'ObjectType')]
        [Parameter(Mandatory, ParameterSetName = 'CreatedGroup')]
        [Parameter(Mandatory, ParameterSetName = 'SyncedGroup')]
        [Parameter(Mandatory, ParameterSetName = 'PimHeld')]
        [Parameter(Mandatory, ParameterSetName = 'PimUnread')]
        [Parameter(Mandatory, ParameterSetName = 'SignedInIdUnknown')]
        [Parameter(Mandatory, ParameterSetName = 'MembershipUnread')][string]$Candidate,
        [Parameter(ParameterSetName = 'Unresolved')][AllowEmptyCollection()][string[]]$UnresolvedScope = @(),
        [Parameter(Mandatory, ParameterSetName = 'UnreadRoleName')][string]$Declared,
        [Parameter(Mandatory, ParameterSetName = 'UnreadRoleName')][string[]]$UnnamedRoleId,
        [Parameter(Mandatory, ParameterSetName = 'ObjectType')][AllowNull()][AllowEmptyString()][string]$ObjectType,
        [Parameter(Mandatory, ParameterSetName = 'CreatedGroup')][string]$CreatedGroup,
        [Parameter(Mandatory, ParameterSetName = 'SyncedGroup')][string]$SyncedGroup,
        [Parameter(Mandatory, ParameterSetName = 'PimHeld')][string]$PimHeldReason,
        # Empty or null is accepted rather than refused at binding: a binding error here would end the
        # calling handler's item outside its own try, and the record withholds the prune either way.
        [Parameter(Mandatory, ParameterSetName = 'PimUnread')][AllowNull()][AllowEmptyString()][string]$PimUnread,
        [Parameter(Mandatory, ParameterSetName = 'SignedInIdUnknown')][switch]$SignedInIdUnknown,
        [Parameter(Mandatory, ParameterSetName = 'MembershipUnread')][switch]$MembershipUnread,
        # The handler's kinds are always the canonical Eligible or Active, so the set cannot refuse a
        # real call; a value outside it is a caller error that should be seen, not worded as Active.
        [Parameter(Mandatory, ParameterSetName = 'MembershipUnread')][ValidateSet('Eligible', 'Active')][string]$PairKind,
        # Empty or null is accepted for the same reason as -PimUnread. In the SignedInIdUnknown form it
        # is optional and a blank value is read as omitted (the default cause).
        [Parameter(Mandatory, ParameterSetName = 'MembershipUnread')]
        [Parameter(ParameterSetName = 'SignedInIdUnknown')][AllowNull()][AllowEmptyString()][string]$Reason,
        [Parameter(ParameterSetName = 'ObjectType')]
        [Parameter(ParameterSetName = 'CreatedGroup')]
        [Parameter(ParameterSetName = 'SyncedGroup')]
        [Parameter(ParameterSetName = 'PimHeld')][switch]$Prune
    )

    if ($PSCmdlet.ParameterSetName -eq 'SignedInIdUnknown') {
        $Cause = if ([string]::IsNullOrWhiteSpace($Reason)) { "it could not be determined from the session's Microsoft Graph token" } else { $Reason }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
            -Detail "prune withheld: the signed-in identity's object id is unknown ($Cause), so $Candidate may be its own assignment and is left in place (our own guard, not a Graph rejection). Sign in again with Connect-OER; if the token carries no oid claim, reconcile this pair from a session that does."
    }

    if ($PSCmdlet.ParameterSetName -eq 'MembershipUnread') {
        # An Active assignment is held; an Eligible one makes the identity eligible for the role until it
        # activates it (BL-24), so a group it may get the role through is worded by the pair's kind.
        $RoleThrough = if ($PairKind -eq 'Eligible') { 'is eligible for the role through' } else { 'holds the role through' }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
            -Detail "prune withheld: the signed-in identity's group memberships could not be read, so $Candidate may be a group the signed-in identity $RoleThrough and is left in place (our own guard, not a Graph rejection): $Reason"
    }

    if ($PSCmdlet.ParameterSetName -eq 'PimHeld') {
        if ($Prune) {
            return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
                -Detail "prune withheld: $Candidate $PimHeldReason, and -Prune never removes a member or owner whose access PIM for Groups holds or makes eligible; it is left in place (our own guard, not a Graph rejection). Manage that access in PIM for Groups if it is meant to go."
        }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Extra' `
            -Detail "$Candidate ($PimHeldReason, so -Prune leaves it in place)"
    }

    if ($PSCmdlet.ParameterSetName -eq 'PimUnread') {
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
            -Detail "prune withheld: whether PIM for Groups holds $Candidate or makes it eligible could not be read ($PimUnread), so it is left in place (our own guard, not a Graph rejection). Apply again once the group's PIM for Groups assignments and eligibility can be read."
    }

    if ($PSCmdlet.ParameterSetName -eq 'SyncedGroup') {
        if ($Prune) {
            return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
                -Detail "prune withheld: $Candidate stays, since group '$SyncedGroup' is synchronized from on-premises and is managed there, and the apply engine writes nothing to such a group, -Prune included (our own guard, not a Graph rejection). Remove it in the on-premises directory if it is meant to go."
        }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Extra' `
            -Detail "$Candidate (group '$SyncedGroup' is synchronized from on-premises, so -Prune leaves it in place)"
    }

    if ($PSCmdlet.ParameterSetName -eq 'CreatedGroup') {
        if (-not $Prune) { return }
        return ConvertTo-OERStructureResult -Section $Section -Item $Item -Action 'Skipped' `
            -Detail "prune withheld: $Candidate is group '$CreatedGroup', which the groups section of this run either created into this unit or, when the group already existed, found in place of creating it; this run does not remove that membership (our own guard, not a Graph rejection). The next apply with -Prune removes it unless the unit's members name the group."
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
