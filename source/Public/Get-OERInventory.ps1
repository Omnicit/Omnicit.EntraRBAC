function Get-OERInventory {
    <#
    .SYNOPSIS
    Reads the current state of a tenant's RBAC building blocks into a serializable inventory object.

    .DESCRIPTION
    Composes the existing Get-OER* cmdlets into a single tagged Omnicit.EntraRBAC.Inventory object whose
    shape matches the Phase 5 JSON document schema, so the output round-trips into the orchestration
    apply engine. Select which building blocks to read with -Include (default: Groups,
    AdministrativeUnits, Catalogs and AccessPackages).
    Azure sections (RoleAssignments, RoleManagementPolicies) need an ARM token and their targeting
    parameters. With either section and a -Scope or a -Subscription, the token is acquired up front,
    in the command's one sign-in, as -IncludeARM does, since the subscription is checked before
    either section reads (see below) -- for RoleManagementPolicies only with exactly one of -Role,
    -CommonRoles and -AllRolesAtScope, since with none or more than one that section is skipped with
    a warning and reads nothing; with a -ManagementGroup alone, pass -IncludeARM to acquire it
    up front, or the Azure sections acquire it on first use. Names are emitted by default for portability;
    -IncludeId additionally stamps each top-level object with its id.
    The Groups section is SECURITY-ENABLED-SCOPED unless you say otherwise: with no -GroupFilter it
    reads 'securityEnabled eq true', so a distribution group and a Microsoft 365 group whose
    securityEnabled is false are not in the inventory at all -- their absence from the document is
    not evidence of their absence from the tenant. That default is deliberate, since this document
    feeds Invoke-OERStructure and widening it widens what the apply engine reconciles and, under
    -Prune, deletes. -GroupFilter is the supported lever for widening it: pass the OData filter you
    want (Export-OERInventory's groupsRoster.json, by contrast, is an unfiltered read-only roster of
    every group in the tenant).
    The Groups eligibility projection carries accessType (member or owner) and, for a time-bound
    eligibility, durationDays reconstructed from the schedule window, so a re-applied inventory keeps
    a time-bound eligibility time-bound and an owner eligibility on the owner access type. The Groups
    owners projection carries the group's standing owners (a privilege path distinct from members,
    since an owner can add members; see below for the owners PIM for Groups holds) so a re-applied
    inventory keeps them, and is emitted only when the group has at least one such owner. A group's
    members and owners include its service principals, written by object id. A document exported by
    an earlier version lacks them: Invoke-OERStructure reports them Extra, and -Prune leaves them in
    place, since the group prune never removes a service principal.
    A group synchronized from on-premises Active Directory carries onPremisesSynced: true (information
    only; Invoke-OERStructure never sends it and writes nothing to such a group, deciding on its own
    live read); a cloud group carries no such key.
    The Groups members and owners projections carry STANDING members and owners only. A member or
    owner whose access PIM for Groups holds -- an activation, or another active assignment that is
    not standing, such as a time-bound one -- is left out of members or owners. An activation makes
    its principal a member or owner of the group for as long as it lasts, so it stands in the group's
    lists, and writing it would record access that PIM for Groups grants on its own terms as if it
    were a standing membership. To tell the two apart the inventory reads the group's PIM for Groups
    assignment schedule instances: ONE paged read per group whose read members or owners hold at
    least one entry, and none otherwise. Access is matched per access type, so a principal that is a
    standing member and an activated owner is written under members and left out of owners; with
    the assignments read, eligibility alone leaves nobody out. When the assignment read fails,
    'groups/<name>/pimAssignments' is reported through the InventoryPartial error below and every
    member and owner that is eligible for the same access is left out instead, since an eligible
    principal that is a member now may be one through an activation. (A time-bound active assignment
    made straight to a principal with no eligibility cannot be recognised without the assignment
    read, and is written as standing; the InventoryPartial error is the sign.) When neither the
    assignments nor the eligibility could be read, a members collection that holds entries is
    written as an explicit null and an owners collection that holds entries is left out, both
    reported the same way; a collection read empty is written as read. The verbose stream says, for
    each group that left any out, how many members and owners it left out and on which basis. The
    read needs the Microsoft Graph permission PrivilegedAssignmentSchedule.Read.AzureADGroup
    (Get-OERRequiredScope lists it).
    A dynamic group's members is written as an explicit null, and is not reported as unread: its
    membership is owned by its membership rule, so a list would be only what the rule derived at the
    time of the read, which Invoke-OERStructure never reconciles or removes. The members are not part
    of the document, so a failed read of them is no gap either: it names nothing unread and adds no
    cause to the InventoryPartial error, and only the verbose stream shows it. The null is the schema's
    "leave the membership untouched" signal, and not an omitted key, since an omitted key still
    reconciles and, under -Prune, removes the live members of a group that is no longer dynamic by the
    time the document is applied. The group's members are not looked at for the PIM for Groups read
    above (a dynamic group with members and no owners sends none), and its owners and eligibility are
    written as for any group.
    The lists a projection writes stand in one fixed order, so two reads of one unchanged tenant write
    one document whatever order Graph answered in: a group's members and owners, and an administrative
    unit's members, are ordered as text without regard to letter case and, for two texts that differ
    only in it, by ordinal comparison (Alice, alice, Bob); a group's eligibility is ordered by
    principal, then accessType, then durationDays (a permanent eligibility, which has none, first),
    then id. The groups and units themselves, and the entries of every other section, stay in the
    order they were listed in.
    The Groups pimPolicy projection is emitted only for a group found to use
    PIM for Groups: one with PIM eligibility, or one whose PIM-for-Groups policy has been modified (it
    carries a lastModifiedDateTime or a lastModifiedBy). Microsoft Graph lists those policies for
    every group, including one never used with PIM for Groups, and applying a changed pimPolicy to
    such a group onboards it to PIM for Groups, which cannot be undone -- so a group not found to use
    PIM for Groups carries no pimPolicy, and none of its policies is read. A group used only through
    PIM active assignments, with untouched policies, is not found to use it either. When that
    question cannot be answered for a group -- its policies could not be listed, or no modified
    policy was found while its PIM eligibility could not be read -- its pimPolicy is omitted and
    reported through the InventoryPartial error below. The projection carries requireApproval and,
    only while it is true, approvers as object ids (a display name is not guaranteed to resolve) --
    approvers are omitted while requireApproval is false, since the apply engine ignores declared
    approvers in that case and the offline validator would otherwise warn on every exported document.
    A collection whose LIVE READ FAILED is never stated as a fact. How that is expressed depends on
    what an omitted key means to the apply engine, which is not uniform: groups[].members,
    administrativeUnits[].members, administrativeUnits[].scopedRoles, catalogs[].resources and
    accessPackages[].resourceRoles still reconcile and still prune when their key is merely
    omitted, so an unread one is emitted as an EXPLICIT null -- the schema's documented "leave it
    untouched" signal. groups[].owners and groups[].eligibility are never reconciled or pruned
    from an omitted key, so an unread one is simply left out. Either way the gap is reported:
    after the inventory object is emitted, a non-terminating InventoryPartial error names every
    affected section/displayName/key, so a caller using -ErrorAction Stop or a try/catch finds out
    instead of treating a document with holes in it as a full tenant snapshot. (A dynamic group's
    members and a dynamic administrative unit's members are the two collections that are no gap when
    their read fails, since neither is part of the document, a group's written as an explicit null
    and a unit's omitted: the failed read names nothing unread and adds no cause either, and only the
    verbose stream shows it. A static unit's failed members read is a gap, named unread with its
    cause.) Do not hand-edit
    such a null to an empty array -- that turns "unknown" into "declared empty", which
    Invoke-OERStructure -Prune acts on by deleting every live member (a group's service principals,
    the members of a group synchronized from on-premises and the members PIM for Groups holds or
    makes eligible excepted), binding or resource. The
    catalog list itself, the resource names an access package's bindings are written under, a
    catalog's access packages and their assignment policies are reported through the same
    InventoryPartial error when their read fails, and are written as far as they were read: a
    failed catalog list leaves the catalogs and accessPackages sections empty, a failed package
    list leaves a catalog with no access packages, a failed policy read leaves a package with no
    assignment policies, the resource names are read only for a catalog whose package list was read
    and holds a package (a catalog with none, or whose list failed, has no binding to name and sends
    no such read), and when the names cannot be read a group's or an application's binding is
    written under its object id and any other binding under the name the access package reader
    could join (the name the catalog recorded; a binding with no name at all makes the package's
    resourceRoles null, as described below). Invoke-OERStructure never removes a catalog, access
    package or assignment policy that is absent from the document.
    An entry is never written with an empty name, since the validator and schema.json refuse one. A
    binding, catalog resource or scoped role whose name is blank is written under an object id the
    apply engine accepts when it has one: a group's or an application's binding by its object id,
    and a catalog resource by its origin id (a SharePoint site's URL). When it has none -- a
    SharePoint binding with no name, a binding with no role, a catalog resource with neither a
    title nor an origin id, a scoped role with no role or no principal -- the whole collection (the
    package's resourceRoles, the catalog's resources or the unit's scopedRoles) is written as an
    explicit null and named in the InventoryPartial error, the way an unread collection is, since
    a declared set that quietly left the entry out would have Invoke-OERStructure -Prune remove it.
    In AdministrativeUnits, a scoped role row whose principal is an object id carries principalType
    (User, Group or ServicePrincipal) when the directory returns that principal as one of those three
    types, all such principals being looked up together through directoryObjects/getByIds, in
    batches of up to 1000 ids, one request per batch: a row whose principal is not returned, is of
    another type or is named by its display name carries none. A lookup that failed leaves the rows
    of the principals it held without principalType -- some or all of a unit's scoped role rows,
    since a batch can fail while another succeeds -- and reports each such unit once as
    'administrativeUnits/<name>/scopedRoles/principalType' through the InventoryPartial error.
    Invoke-OERStructure validates principalType and normalizes its letter case, but does not use it
    to match or write a scoped role: it matches one by role and principal.
    A group, administrative unit or access review LIST that could not be read at all is reported
    through the same InventoryPartial error by the section's own name alone (groups,
    administrativeUnits or accessReviews) and is written as an empty array, which does not mean the
    tenant has none: the section is never null, so the error is the only thing that tells the two
    apart. The warning the read already wrote stays. A list that answered "none" (a not-found
    answer) is a fact about the tenant and is not reported.
    A dynamic group's membershipRuleProcessingState (On or Paused) is carried
    alongside its membershipRule so a paused rule round-trips paused. The Catalogs projection carries
    externallyVisible so a catalog whose access packages are requestable by connected-organization
    users does not silently re-create as internal-only. A Group or Application catalog resource, and
    an access package resourceRoles entry on one, is written under the group's or application's
    CURRENT display name, looked up by the resource's originId (its object id when the lookup returns
    nothing) -- never under the name the catalog recorded when the resource was added, which Graph
    keeps after a rename, except as described above when the names cannot be read.
    Invoke-OERStructure identifies such a resource by the object id its name resolves to.
    Only access-package-scoped, single-stage review definitions are captured: a group, application,
    directory-role or multi-stage review is skipped, with an aggregate warning naming how many were
    skipped. The AccessReviews projection carries accessPackage, assignmentPolicy, reviewers and
    recurrence so a captured review round-trips through Invoke-OERStructure (create-or-update: a
    review is matched by displayName and created when it does not exist; when it does, it is
    reconciled field by field only if it reviews the accessPackage and assignmentPolicy the entry
    declares, and is otherwise refused, since the scope of a review cannot be changed -- see the
    Invoke-OERStructure help). The apply engine resolves an accessPackage or assignmentPolicy name as
    creation resolves it -- the access package name in the whole tenant, the assignment policy name
    among the policies of its access package -- and refuses a name that lookup finds more than once
    with the lookup's AmbiguousName error. So the projection writes a name only when that same lookup
    finds this access package or assignment policy and no other; an access package name another
    access package in the tenant carries, or an assignment policy name another policy of the same
    access package carries, is written by id instead, so the entry applies. The check costs one
    request per access package name and one per access package, however many reviews share them.
    A multi-stage review (StageCount greater than zero) is skipped
    with a warning instead of being exported, because its reviewers live in stageSettings -- which
    the apply schema does not model -- and the top-level reviewers collection Graph returns for it is
    empty by construction, which would otherwise be misreported as a configured self review. A
    live recurrence interval outside the module's cadence vocabulary (for example an
    absoluteMonthly interval other than 1, 3, 6 or 12) is exported as the nearest coarser cadence
    with a warning naming the true pattern, rather than silently. A live absoluteMonthly interval 6
    is exported as SemiAnnually; an export made before 1.1.4 wrote it as Monthly, and when a
    document declares such a review Monthly, Invoke-OERStructure leaves its recurrence, start date
    and range untouched (reported as skipped, with the reason) rather than make it monthly.
    durationInDays is emitted only when the live settings.instanceDurationInDays is an integer the
    apply schema accepts (1-365): Graph reports 0 when that field does not drive the review's
    duration, and exporting the 0 made the bundle fail the schema.json written beside it. An
    omitted durationInDays means "leave untouched" on apply, which is the correct reading of that
    sentinel; a positive value above 365 is dropped with a warning, because that is real
    configuration the schema cannot carry.
    A review's accessPackage and assignmentPolicy are written under their display names, read by
    id, and by their id in four cases. A package or policy that no longer exists is written by its
    id: that is a fact about the review, so nothing is reported for it. A name the lookup above
    would not resolve to this object alone -- another object carries it, or the lookup does not
    find this one -- is written by id too, and nothing is reported for it either, since the id
    applies. A name that could not be read -- a refused, throttled or failed read -- and a
    name whose uniqueness could not be checked, because the lookup above failed, are written by id
    as well, and each is reported as an unread collection (accessReviews, the review's display name,
    then accessPackage or assignmentPolicy) in the InventoryPartial error, so a document written by
    id for either reason is never mistaken for one whose target was deleted.
    The AccessPackages projection
    carries the hidden flag so a hidden package stays
    hidden across a round-trip. The RoleAssignments projection carries the ABAC condition,
    conditionVersion and description so a condition-scoped assignment is not exported as an
    unconditioned one. In RoleAssignments and DirectoryRoleAssignments, a group is written by its
    display name only when no other group in the tenant carries that name, compared without regard
    to letter case; otherwise, or when the listing of every group fails, it is written by its object
    id with principalType Group, which Invoke-OERStructure resolves verbatim. The listing is the one
    described below, made at most once per call, when the Groups section read at least one group or
    when a section holds a group principal whose name was read (one whose name could not be read is
    written by its object id with no listing), and shared by both; when it fails, the verbose stream
    says so and no group principal is reported unread, since an object id names the group exactly.
    The RoleAssignments and RoleManagementPolicies sections read a -Scope or a -Subscription only when
    the subscription it lies in belongs to the tenant the session's Microsoft Graph token was issued
    for, by the tenantId Azure Resource Manager returns for the subscription: the rule
    Export-OERInventory's Azure walk and Invoke-OERStructure apply too. The subscription is checked once
    per call, before either section reads anything, with one read of it (a subscription named by its
    display name also costs one read of the subscription list, which only the check makes: both sections
    then read with the subscription ID the check found, never with the name); with both -Scope and
    -Subscription, each is checked. The Azure Resource Manager token that read needs is acquired in the
    command's sign-in, as -IncludeARM does, whenever RoleAssignments, or RoleManagementPolicies with
    exactly one of -Role, -CommonRoles and -AllRolesAtScope, is included with a -Scope or a
    -Subscription. A -Scope at a management group or the root scope '/', and a -ManagementGroup, lie
    in no subscription and are read as before. A subscription of another tenant -- a customer
    subscription another tenant delegated to this one through Azure Lighthouse, for example -- is not
    read: each included section is written empty, and one non-terminating SubscriptionTenantMismatch
    error, written after the inventory object, names the scope and the tenant, however many of the two
    sections were included; with both -Scope and -Subscription in subscriptions of another tenant,
    that one error names the -Scope. The inventory is not reported partial for it. A subscription whose tenant could not be
    told -- its read failed, it gave no tenantId, the session's token names no tenant ID, or the scope
    cannot be resolved or is spelled in a way no structure document can declare, a trailing '/' for
    example -- is not read either: each included section is written empty and reported by its name
    (roleAssignments, roleManagementPolicies) through the InventoryPartial error below, with the reason
    as its cause. Under Export-OERInventory the scopes it hands this cmdlet were already decided by its
    walk, and the answers are shared, so the check costs the export no request. Invoke-OERStructure
    refuses a role assignment or a role management policy at a scope in a subscription of another
    tenant with SubscriptionTenantMismatch. A role assignment row that an inventory of a subscription
    carries at a management group above it, read at the subscription as inherited, lies in no
    subscription and is not checked: Invoke-OERStructure applies it like any management group row.
    A RoleAssignments or RoleManagementPolicies read that fails -- the scope is invalid, a role does not
    resolve or has no policy, or Azure Resource Manager refuses or fails the read -- is reported through
    the same InventoryPartial error by the section's own name (roleAssignments, roleManagementPolicies)
    with the reader's message as its cause, and the section is written empty, which does not mean the
    scope has none. The section is read whole or not at all: with -Role A,B, where the read for B fails,
    the policy of A is not written either. The reader's own error is not written to the caller's error
    stream beside it (a caller's -ErrorVariable still collects it), and no warning is written for it.
    -CommonRoles is the exception: the reader reads each curated role on its own and skips any role whose
    definition or policy it cannot read -- a refused or failed read as much as a role that is missing at
    the scope -- with a warning of its own (Skipping role, the role's name and the reason), and carries
    on. That skip is not reported through InventoryPartial, so the section holds the policies of the
    roles that were read, which may be fewer than the curated set; only a scope that cannot be resolved
    is reported unread. Under a Stop warning preference (-WarningAction Stop, or $WarningPreference set
    to 'Stop') the stop at that warning is caught here as well: the section is reported unread, with the
    warning's text in its cause, and the command carries on.
    A role assignment at the Azure root scope '/', above every management group and subscription in
    the tenant, is left out of the RoleAssignments section: it is elevated
    access, a finding to review rather than part of the RBAC model a document describes, and
    Invoke-OERStructure never creates or removes one. A read at a management group or a subscription
    returns it as inherited. One warning names every such assignment, each by role and principal and,
    when it is known, the principal type, and an information record tagged
    Omnicit.EntraRBAC.RootScopeAssignment hands the caller the same rows (RoleAssignmentId, Role,
    Principal and PrincipalType) and the warning's text; under the default $InformationPreference
    the record is not displayed. Under a Stop warning preference (-WarningAction Stop, or
    $WarningPreference set to 'Stop') the command stops at that warning, before it returns the
    inventory. The RoleManagementPolicies projection carries activation window and enablement,
    approval and approvers, authentication context, and eligible and active permanence
    plus their day counts, so a policy round-trips instead of losing everything but permanence and
    the activation window. Notification rules are excluded from that projection: they are readable
    through Get-OERRoleManagementPolicy and writable through Set-OERRoleManagementPolicy
    -NotificationRule, but are not part of this document and do not round-trip. Azure PIM eligible
    and active ROLE ASSIGNMENTS (as opposed to the policy that governs them) remain outside every
    APPLY section here: neither roleAssignments (permanent Azure RBAC only) nor
    roleManagementPolicies (the governing policy) grants, captures or removes one, and this cmdlet
    itself still does not read them. Export-OERInventory writes the eligible ones into
    azurePimEligibility.json as read-only context, outside the apply document -- active assignments
    are not captured there either. Manage them directly with New-OEREligibleRoleAssignment,
    Get-OEREligibleRoleAssignment, New-OERActiveRoleAssignment and Get-OERActiveRoleAssignment.
    The DirectoryRoleAssignments and DirectoryRoleManagementPolicies sections cover Microsoft Entra
    directory roles. DirectoryRoleAssignments exports only the eligible and active assignments the
    apply engine manages: direct and at tenant scope, and for an active one a standing assignment --
    an activation of an eligible assignment, an assignment a principal holds through a group, and one
    scoped to an administrative unit are never exported, by the same rule Invoke-OERStructure matches
    and prunes by (Select-OERManagedDirectoryRoleAssignment). A user is named by its user principal
    name and a group by its display name, each falling back to the object id when no name can be
    read, and a group by its object id as well when another group in the tenant carries its display
    name, as described above; a service principal, or a principal of unknown type, is named by its
    object id, and principalType is carried whenever the type is known. Entra does not keep group
    display names unique, so a group whose display name matches, without regard to letter case,
    that of another principal holding the same role and assignment type is named by its object id
    instead (still with principalType Group): two entries with the same role, principal and
    assignmentType would be refused by the validator. A time-bound assignment carries durationDays
    reconstructed from the schedule window the same way the apply engine measures it, so a
    re-applied export is Unchanged; a permanent one carries neither durationDays nor permanent. Two
    live schedules for one role,
    principal and kind export only the first this read returns, with a warning: Invoke-OERStructure
    compares against the first schedule Microsoft Graph returns for that role and principal, which is
    not guaranteed to be the same one, so such an entry may report a change when applied.
    DirectoryRoleManagementPolicies exports the policy of every directory role that has at least one
    row in the tenant-scope eligibility or assignment schedules -- any member type, activations
    included -- or, with -AllDirectoryRolePolicies, of every directory role; a directory policy
    carries approvers only while approval is required. A failed read of either schedule list or of
    the policies is reported through the InventoryPartial error and never stated as a fact: the kind
    whose read failed exports no entry, and a role selection made from an incomplete read is
    reported as partial.
    The export never writes two entries that the validator would refuse as duplicates, so a document
    it emits is not refused by Invoke-OERStructure for that reason. Live groups, administrative
    units, catalogs, access reviews, access packages of one catalog, or assignment policies of one
    access package whose names match, without regard to letter case, are left out of the document --
    all of them -- and each such name is reported through the InventoryPartial error, since the apply
    engine refuses an ambiguous name and neither entry could be applied; leaving a top-level entry out
    removes nothing, because -Prune acts on child collections only, and leaving an assignment policy
    out removes nothing either, because the apply engine never removes an assignment policy. A
    policy name is reported as accessPackages/ followed by the package name, /assignmentPolicies/ and
    the policy name, and the policies of two different packages never count against each other. An
    access package in a catalog whose name another catalog carries is written with that catalog's
    object id as its catalog, which the apply engine takes as the catalog itself, so access packages
    of one name in two such catalogs are two entries and not a collision; the catalogs themselves are
    left out as described. Catalog names are counted among the catalogs read only. -Catalog given as
    an id reads that catalog alone, so a package in it keeps the catalog's name even when another
    catalog in the tenant carries it; -Catalog given as a name reads every catalog Microsoft Graph
    matches by that name, and when that is more than one, their packages are written with the
    catalog ids. A group's name is counted among every group in the tenant -- one extra paged
    listing of every group's id and display name, made at most once per call, when the Groups
    section read at least one group or when a role assignment or directory role assignment names a
    group -- so a security group that shares its name with a Microsoft 365 group or a
    distribution group, which the default filter never reads, is left out too; the reported cause
    names how many live objects carry the name. When that listing fails, groupNames is reported
    unread through the InventoryPartial
    error, with its cause, and the names are counted among the groups read. Export-OERInventory
    shares that one listing among all the calls it makes to this cmdlet, so an export lists the
    groups at most once, not once per Azure scope. Each name left out is
    also handed over in one information record tagged Omnicit.EntraRBAC.SharedName, whose Names list
    carries the Section, Name and Count of each; under the default $InformationPreference the record
    is not displayed. Role assignments whose scope
    (compared in its canonical form), role and principal collide are written with the principal's
    object id and, when the principal is already an id, with the role's full definition id. A role
    management policy read twice, for example by naming the same role twice in -Role, is written once.

    In RoleAssignments, principalType is written for every role assignment whose principal type is a
    user, a group (a ForeignGroup included) or a service principal, and left out for any other type,
    such as a device, which the document's principalType cannot name. Each principal is looked up in
    Microsoft Entra ID through directoryObjects/getByIds, over every directory object type, in batches
    of up to 1000 ids, one request per batch. A principal the directory returns is written by its
    name -- a user by its user principal name, a group by the rule above and a service principal by
    its display name; a principal of any other type, such as a device, is written by its object id.
    A principal the directory did not return is written by its object id with principalStatus:
    Deleted when it is found among the directory's deleted items, Unresolved when it is found neither
    there nor in the directory -- deleted beyond the retention period, a principal of another tenant,
    for example through Azure Lighthouse, or not readable -- or when its deleted items could not be
    read. Each such principal is looked for among the deleted items with one read of
    directory/deletedItems: an answer that was read is kept for the rest of the call, and under
    Export-OERInventory for the rest of the export, while a read that fails is not kept and is sent
    again for the next role assignment that needs it. principalStatus stands directly after
    principalType, or after principal when there is none. Such an assignment stays in the document:
    Invoke-OERStructure never creates it, and removing the entry lets -Prune remove it, like any
    undeclared assignment, at a scope the document still declares. One warning counts them, and an
    information record tagged Omnicit.EntraRBAC.UnresolvedPrincipal hands the caller the same rows
    (RoleAssignmentId, Scope, Role, Principal, PrincipalType, PrincipalStatus and StatusRead, which is
    false where the deleted items read failed) and the warning's text; under the default
    $InformationPreference the record is not displayed. Under a Stop warning preference the
    command stops at that warning, before it returns the inventory, as it does at the root scope
    warning. When the lookup itself fails, the principal is written by its object id with no
    principalStatus, and 'roleAssignments/<role> -> <principal id> @ <scope>/principal' is reported
    through the InventoryPartial error with its cause; when only the deleted items read fails, the
    principal is written as Unresolved, with its reason not known, and '.../principalStatus' is
    reported the same way. A role assignment at the root scope is named only as described above: its
    principal is looked up like any other, which is how the root list names it, but it is not looked
    for among the deleted items, and a failed lookup of it is not reported -- the root list names it
    by its object id.

    A role assignment whose scope breaks a scope spelling rule the validator applies, as the scope of
    a resource whose name holds a '#' or a '%' does for example (Test-OERStructure refuses such a
    scope as an Error; about_Omnicit.EntraRBAC lists the rules under RENAMES, MAIL ALIASES AND SCOPE
    SPELLING), is left out of the RoleAssignments section too: no document can declare that scope, so
    a document that carried it would be refused as a whole. Invoke-OERStructure never creates a role
    assignment at such a scope, and never removes one, since it prunes only at a scope a document
    declares. The root scope is decided first, so a role assignment at the root scope whose spelling
    is refused too is named only as described above. One warning counts such assignments, and an
    information record tagged Omnicit.EntraRBAC.UndeclarableScope hands the caller the rows
    (RoleAssignmentId, Scope, Role, Principal, PrincipalType and Reason, which names the rules
    the scope breaks in words) and the warning's text; under the default $InformationPreference the
    record is not displayed. Under a Stop warning preference the command stops at that warning, before
    it returns the inventory. Such a role assignment's principal is looked up like any other, which is
    how the record names it, but it is not looked for among the deleted items, a failed lookup of it is
    not reported, and it never changes how another role assignment is named.

    The inventory carries a top-level tenantId, directly after its version: the tenant ID the session's
    Microsoft Graph token was issued for, never the tenant as named with -TenantId (a domain, or
    organizations, names no tenant ID). Invoke-OERStructure applies the document only in that tenant
    and refuses it anywhere else with DocumentTenantMismatch. When the token reports no tenant ID, or
    the module holds no session, the key is left out, with no warning, and the document carries no
    tenant check. To use the inventory as a template for another tenant, change its tenantId to that
    tenant's ID or remove the key.

    .PARAMETER Include
    The building-block sections to read. Defaults to Groups, AdministrativeUnits, Catalogs and
    AccessPackages. AccessReviews captures only access-package-scoped, single-stage review
    definitions (optionally narrowed by -AccessReviewFilter); a group, application, directory-role
    or multi-stage review is skipped with a warning. DirectoryRoleManagementPolicies and
    DirectoryRoleAssignments read Microsoft Entra directory roles through Microsoft Graph and need no
    ARM token. RoleAssignments and RoleManagementPolicies need an ARM token and their targeting
    parameters: with a -Scope or a -Subscription the token is acquired up front, as -IncludeARM does
    (for RoleManagementPolicies only with exactly one of -Role, -CommonRoles and -AllRolesAtScope,
    without which it reads nothing); with a -ManagementGroup alone they acquire it on first use unless
    -IncludeARM is passed.

    .PARAMETER GroupFilter
    An OData filter (without the $filter= prefix) selecting which groups to read. When omitted,
    defaults to 'securityEnabled eq true' -- every security group, and nothing else: a distribution
    group and a Microsoft 365 group whose securityEnabled is false are excluded. This parameter is
    the supported way to widen that scope; weigh it against Invoke-OERStructure -Prune, which acts
    on whatever the resulting document declares.

    .PARAMETER Catalog
    A catalog id or display name that narrows the Catalogs and AccessPackages sections to one catalog.

    .PARAMETER AccessReviewFilter
    An optional display-name pattern (wildcards supported, e.g. 'AR*') narrowing which access review
    definitions to capture. Matching is performed CLIENT-SIDE over the full (paged) list, because the
    accessReviews endpoint does not reliably support server-side name filtering. When omitted, every
    definition is captured. This endpoint is heavily throttled, so a full capture may hit a 429 --
    the section then warns and is skipped without failing the rest of the run.

    .PARAMETER Scope
    A raw ARM scope for the Azure sections (e.g. '/subscriptions/{id}'). A scope in a subscription of
    another tenant, or in one whose tenant could not be told, is not read (see above). An empty or white
    space value is refused at parameter binding.

    .PARAMETER Subscription
    A subscription GUID or display name for the Azure sections. A subscription of another tenant, or
    one whose tenant could not be told, is not read (see above). A display name is resolved once, by the
    subscription check, and the sections read with the subscription ID it found. An empty or white space
    value is refused at parameter binding.

    .PARAMETER ManagementGroup
    A management group name or display name for the Azure sections. A management group lies in no
    subscription, so it is read without that check. An empty or white space value is refused at
    parameter binding.

    .PARAMETER Role
    One or more roles (display name, GUID, or full ARM id) whose role management policy to read.
    Required to populate the RoleManagementPolicies section when neither -CommonRoles nor
    -AllRolesAtScope is used. Use -CommonRoles or -AllRolesAtScope instead of -Role to read the
    curated set or every role at the scope. Tab-completion offers the five curated common Azure RBAC
    roles; any other built-in or custom role name is still accepted.

    .PARAMETER CommonRoles
    For the RoleManagementPolicies section, read the curated common-role set (Reader, Contributor,
    Owner, User Access Administrator, Role Based Access Control Administrator) at the target scope
    instead of an explicit -Role list. Mutually exclusive with -Role and -AllRolesAtScope.

    .PARAMETER AllRolesAtScope
    For the RoleManagementPolicies section, read the policy for every role at the target scope from a
    single roleManagementPolicyAssignments list-for-scope call (one paged ARM list, not one lookup per
    role). Mutually exclusive with -Role and -CommonRoles.

    .PARAMETER AllDirectoryRolePolicies
    For the DirectoryRoleManagementPolicies section, export the policy of every Microsoft Entra
    directory role, instead of only the roles that have at least one row in the tenant-scope
    eligibility or assignment schedules. The schedules are then not read for the policy section at
    all; they are still read, once, when DirectoryRoleAssignments is included too.

    .PARAMETER IncludeId
    Stamp each top-level object with its id property (handy for same-tenant round-trips).

    .PARAMETER IncludeARM
    Acquire an ARM token up front, in the command's sign-in. Forwarded to Initialize-OERAuth. It is
    implied when RoleAssignments, or RoleManagementPolicies with exactly one of -Role, -CommonRoles and
    -AllRolesAtScope, is included with a -Scope or a -Subscription, since the subscription is checked
    before either section reads; with a
    -ManagementGroup alone the Azure sections otherwise acquire the token on first use. A call that
    includes neither section acquires no ARM token without it.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth. The
    inventory's tenantId is the tenant ID the session's Microsoft Graph token was issued for, not this
    value.

    .EXAMPLE
    Get-OERInventory -Include Groups,Catalogs,AccessPackages
    Reads the core Entra ID building blocks into an inventory object.

    .EXAMPLE
    Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
    Reads the Azure role assignments at the Prod subscription.

    .EXAMPLE
    Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -CommonRoles -IncludeARM
    Reads the PIM policy for each curated common role on the Prod subscription into the inventory.

    .EXAMPLE
    Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
    Reads the Microsoft Entra directory role assignments the apply engine manages, and the PIM policy
    of every directory role in use, through Microsoft Graph only.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages'),

        [string]$GroupFilter,
        [string]$Catalog,
        [string]$AccessReviewFilter,
        # Sprint 11 step 10 (BL-155): a -Scope, -Subscription or -ManagementGroup of white space only is
        # refused here, at binding, as an empty one is (the same BL-96 pattern as Export-OERInventory's
        # -GroupFilter and New-OERConfiguration's -TenantId). Before this, '   ' passed the sections' own
        # `if ($Scope)` tests (a string of spaces is true) and reached the Azure readers, while the
        # subscription check and the sign-in's ARM term treat it as no scope at all, so one parameter was
        # given and not given at once. The module supports PowerShell 7.2, which has no
        # [ValidateNotNullOrWhiteSpace()] (7.4+), so the same test runs as a script. Declared ABOVE
        # [ValidateNotNullOrEmpty()] on purpose: validation attributes run in reverse declaration order
        # (measured), so an empty or null value still reads the NotNullOrEmpty message and white space reads
        # this one. No parameter moves: positional binding follows declaration order.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The Scope consists only of white space. Pass an Azure Resource Manager scope, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,
        # BL-155: as -Scope.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The Subscription consists only of white space. Pass a subscription ID or display name, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$Subscription,
        # BL-155: as -Scope.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The ManagementGroup consists only of white space. Pass a management group name or ID, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementGroup,
        [string[]]$Role,
        [switch]$CommonRoles,
        [switch]$AllRolesAtScope,
        [switch]$AllDirectoryRolePolicies,
        [switch]$IncludeId,
        [switch]$IncludeARM,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        # A20 (BL-152, R-9): RoleAssignments and RoleManagementPolicies check the subscription of a -Scope or a
        # -Subscription (Get-OERSubscriptionHomeTenant) before either reader runs, and that check reads the
        # subscription through the ARM transport, which sends nothing without an ARM token. The readers
        # acquire the token on first use, which is after the check, so it is acquired here, in this one
        # sign-in, exactly as -IncludeARM does. A -ManagementGroup alone is never checked and keeps the
        # readers' acquisition on first use, and a call that includes neither section acquires none, as
        # before: an ARM token asked for without an -AuthMethod can turn an app-only session into an
        # interactive prompt (see Export-OERInventory's begin).
        # RoleManagementPolicies reads only with exactly one of -Role, -CommonRoles and -AllRolesAtScope:
        # with none or more than one it skips with a warning before the check (process, below) and reads
        # nothing, so it asks for the token only then. $RoleSources is computed here once and is the list
        # that section decides by, so the two cannot drift apart.
        $RoleSources = @(
            if ($Role) { 'Role' }
            if ($CommonRoles) { 'CommonRoles' }
            if ($AllRolesAtScope) { 'AllRolesAtScope' }
        )
        $RolePoliciesRead = $Include -contains 'RoleManagementPolicies' -and $RoleSources.Count -eq 1
        $ChecksSubscription = ($Include -contains 'RoleAssignments' -or $RolePoliciesRead) -and
            (-not [string]::IsNullOrWhiteSpace($Scope) -or -not [string]::IsNullOrWhiteSpace($Subscription))
        if ($IncludeARM -or $ChecksSubscription) { $AuthParams.IncludeARM = $true }
        Initialize-OERAuth @AuthParams
        # BL-88 (A14): the tenant this inventory names, captured here under the session this command
        # signed in under, never read again where the document is assembled.
        $DocumentTenantId = Get-OERInventoryTenantId
    }
    process {
        # Per-invocation id -> name cache (Groups eligibility + AccessReviews reviewers + directory role principals).
        # Under Export-OERInventory it is replaced, once the run context is read below, by the context's own
        # PrincipalNameCache (Sprint 11 step 10, BL-122, R-12).
        $PrincipalNameCache = @{}
        $Groups                 = [System.Collections.Generic.List[object]]::new()
        $AdministrativeUnits    = [System.Collections.Generic.List[object]]::new()
        $Catalogs               = [System.Collections.Generic.List[object]]::new()
        $AccessPackages         = [System.Collections.Generic.List[object]]::new()
        $AccessReviews          = [System.Collections.Generic.List[object]]::new()
        $DirectoryRoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        $DirectoryRoleAssignments        = [System.Collections.Generic.List[object]]::new()
        $RoleAssignments        = [System.Collections.Generic.List[object]]::new()
        $RoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        # Collections a section asked for and did not get back. An inventory document must never
        # state as a fact something the export failed to read (issue #76), so each entry here both
        # steers the projection below and feeds the InventoryPartial error at the end.
        $UnreadCollections = [System.Collections.Generic.List[string]]::new()
        # The distinct underlying failure messages behind those unread collections. The triples in
        # $UnreadCollections say WHICH collection is missing; only these say WHY -- and the reason
        # is what tells an operator to retry (429) rather than grant a scope (403). Get-OERGroup and
        # Get-OERAdministrativeUnit compose it into their per-collection records, and -ErrorAction
        # SilentlyContinue below keeps those records off the caller's stream, so without this the
        # cause would be discarded entirely. Kept RAW, in the order found, each with the id of the
        # object it was about: Format-OERUnreadCauseClause deduplicates (a throttle produces the
        # identical message for every affected group, and repeating it once per group would bury
        # the signal), caps and words them where the partial message is built.
        $UnreadCauses = [System.Collections.Generic.List[object]]::new()

        # Records one read-failure cause. Local to this cmdlet rather than repeated at the group and
        # administrative-unit call sites, so a blank cause is refused in one place. -Target is the
        # record's own TargetObject (the failing object's id), which Format-OERUnreadCauseClause
        # needs to normalise the id out of the message, so it is stored beside the cause.
        function Add-UnreadCause {
            param(
                [string]$Cause,
                [string]$Target
            )
            if ([string]::IsNullOrWhiteSpace($Cause)) { return }
            $UnreadCauses.Add([PSCustomObject]@{ Cause = $Cause; Target = $Target })
        }

        # A section whose LIST could not be read at all is written as [] (a top-level section is never null),
        # so the partial signal is the only thing that tells it from a tenant that has none. The key is the
        # section's own name, added once however many records the failed read produced. NotFound records and
        # foreign strays never reach this: the callers below skip them first.
        function Add-UnreadSection {
            param([string]$Key, [string]$Cause)
            Write-Verbose "Get-OERInventory: $Cause"
            Add-UnreadCause -Cause $Cause
            if (-not $UnreadCollections.Contains($Key)) { $UnreadCollections.Add($Key) }
        }

        # An entry the export can name by nothing the apply engine accepts is never written with an empty
        # name: '' is refused by the validator (A10) and would throw at apply. Its collection is written as
        # an explicit null instead -- the documented "leave untouched" signal -- and named here, the
        # mechanism an unread collection uses. -Path is the collection's own path ('<section>/<name>/<key>').
        function Add-NamelessCollection {
            param([string]$Path)
            $NamelessCause = "An entry of $Path has no name, and no object id the apply engine accepts, so the collection is written as null rather than with an empty name."
            Write-Verbose "Get-OERInventory: $NamelessCause"
            Add-UnreadCause -Cause $NamelessCause -Target $Path
            $UnreadCollections.Add($Path)
        }

        # Two live objects whose names match without regard to letter case would be two document entries
        # the validator refuses as a duplicate -- and the apply engine refuses an ambiguous name anyway, so
        # neither entry could be applied. Neither is written. Each such name is reported through
        # InventoryPartial (the unread entry is '<section>/<name>', the cause says why), so the document is
        # never mistaken for a full snapshot. A top-level entry left out of the document removes nothing:
        # Invoke-OERStructure prunes child collections only.
        #
        # -KeyOf must build the SAME key the validator (Test-OERStructureSchema) refuses a duplicate on,
        # or a pair the validator refuses is written. An access package is keyed '<catalog>|<name>'
        # there, so it is keyed that way here. -NameOf, when given, builds the name that is REPORTED
        # for an entry ('<catalog>/<name>', the path an operator reads); without it the key is the name.
        #
        # -ExternalIds (BL-131), when given, is a dictionary from a key to the ids of every live object
        # that carries it, counted wider than the entries: for the groups, the index of every group in the
        # tenant (Get-OERGroupNameIndex), which holds the Microsoft 365 and distribution groups the
        # security-enabled listing never does. A key then counts the larger of the entries and the ids,
        # so a group whose name only a group outside the listing shares is left out too. The other
        # sections pass nothing and are counted over their entries alone.
        #
        # -UnreadOf (BL-131), when given, builds the unread entry of a name left out from the first entry
        # that carries it, where the default '<section>/<reported name>' is not the path an operator
        # reads: the assignment policies of one access package are named
        # 'accessPackages/<package>/assignmentPolicies/<policy>' (the section of the record and the
        # README stays 'assignmentPolicies', the reported name '<package>/<policy>').
        #
        # Each name left out is also recorded, with its section and count, in $SharedNameList, which
        # the information record tagged Omnicit.EntraRBAC.SharedName hands over below.
        function Select-UniqueNamedEntry {
            param([object[]]$Entry, [string]$Section, [scriptblock]$KeyOf, [scriptblock]$NameOf, [scriptblock]$UnreadOf, [System.Collections.IDictionary]$ExternalIds)
            $Count = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($E in $Entry) {
                $K = [string](& $KeyOf $E)
                $Count[$K] = 1 + $(if ($Count.ContainsKey($K)) { $Count[$K] } else { 0 })
            }
            if ($null -ne $ExternalIds) {
                # The keys are copied first: the dictionary is written while they are walked.
                foreach ($K in @($Count.Keys)) {
                    if (-not $ExternalIds.ContainsKey($K)) { continue }
                    $ExternalCount = @($ExternalIds[$K]).Count
                    if ($ExternalCount -gt $Count[$K]) { $Count[$K] = $ExternalCount }
                }
            }
            $Reported = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($E in $Entry) {
                $K = [string](& $KeyOf $E)
                if ($Count[$K] -gt 1) {
                    if ($Reported.Add($K)) {
                        $ReportedName = if ($NameOf) { [string](& $NameOf $E) } else { $K }
                        $Unread = if ($UnreadOf) { [string](& $UnreadOf $E) } else { "$Section/$ReportedName" }
                        $UnreadCollections.Add($Unread)
                        $NameCause = Get-OERSharedNameCause -Path $Unread -Count $Count[$K]
                        # Every cause is written to the verbose stream as it is seen, like at every other
                        # Add-UnreadCause site. The cap keeps causes in the order they are added: the five
                        # calls made once every section is read add theirs last, so the cap drops those
                        # first, while the assignment policies' call adds its causes as each access package
                        # is read, ahead of the causes of the sections read after it.
                        Write-Verbose "Get-OERInventory: $NameCause"
                        # BL-156: registered with a BLANK Target. A cause is deduplicated on its text with its
                        # Target replaced by <id> (Format-OERUnreadCauseClause), and this text carries the name
                        # in the very Target it was given, so two names that two objects each share would
                        # read alike once the name was gone, and the second would be dropped from the clause
                        # although it is a name of its own. A blank Target keys it on its full text instead:
                        # each name is a cause of its own, and the same name is still stated once.
                        Add-UnreadCause -Cause $NameCause -Target ''
                        $SharedNameList.Add([PSCustomObject]@{ Section = $Section; Name = $ReportedName; Count = $Count[$K] })
                    }
                    continue
                }
                $E
            }
        }

        # BL-131: the names Select-UniqueNamedEntry left out, each with its section and count, in the
        # order reported. Handed over in ONE information record before the inventory is emitted.
        $SharedNameList = [System.Collections.Generic.List[object]]::new()

        # BL-131: the index of every group in the tenant by display name (Get-OERGroupNameIndex, one
        # paged listing of every group's id and display name), built at most ONCE per invocation and
        # only when a section asks for it. Any section may call this; the first call reads the index
        # and every later call returns the same object, so the Groups section and the principals of
        # the RoleAssignments and DirectoryRoleAssignments sections share one listing. A failed
        # listing is returned as it is (Read false, with its message), and each caller decides what
        # it means: the Groups section counts names, so it reports 'groupNames' unread; a group
        # principal is written by its object id instead, which is exact, so nothing is unread there
        # (Get-GroupPrincipalReference). Kept in a holder, since a local function cannot assign a
        # variable of this block.
        #
        # Sprint 11 step 6 (R-2 of step 5): under Export-OERInventory the holder is the export's run
        # context ($script:_OERInventoryRunContext, GroupNameIndex), not this invocation's own, so the
        # export's many calls (one per Azure scope) share ONE index: once per export, with the
        # roster's index there already when the roster was read, and the first caller's listing
        # otherwise. Without a context the invocation's own holder serves, as it always did, and
        # nothing outlives the call.
        #
        # The context is read ONCE per invocation, here, and used only when its Owner -- the
        # invocation of the Export-OERInventory that made it -- is a frame of the CURRENT call stack
        # (the very object a frame carries, compared by reference; module-qualified, so a function named
        # Get-PSCallStack defined in the session cannot turn the check off, as in Lock-OERSignIn). An
        # export that was stopped before it cleared its context leaves it behind, and a later call --
        # standalone, or another export's -- finds an Owner that is on no stack and behaves as standalone.
        $RunContext = $null
        $RunContextFound = $script:_OERInventoryRunContext
        if ($null -ne $RunContextFound -and $null -ne $RunContextFound.Owner) {
            foreach ($Frame in Microsoft.PowerShell.Utility\Get-PSCallStack) {
                if ([object]::ReferenceEquals($Frame.InvocationInfo, $RunContextFound.Owner)) {
                    $RunContext = $RunContextFound
                    break
                }
            }
        }
        # Sprint 11 step 10 (BL-122, R-12): under Export-OERInventory the cache of principal names is the run
        # context's PrincipalNameCache, the very hashtable the export handed to its group read, so a principal
        # the group reader named through a PIM eligibility is not looked up again by the reviewers of an access
        # review or by the principals of a directory role section; what this call learns stays there for the
        # calls after it. Read through PSObject.Properties, as SubscriptionTenant is below, so a context
        # without the member -- an older shape, a test fixture's -- reads as none, and the member is used only
        # when it is a [hashtable] (R-27): its consumers need one, since Get-OERInventoryGroup takes the cache
        # as a [hashtable] parameter (any other dictionary binds as a COPY, so what the reader learns would be
        # lost to this call without an error) and the sections below call ContainsKey, which an [ordered]
        # dictionary has not. Anything else reads as none. Without a context of its own the invocation keeps
        # the hashtable it made at the top of this block, as it always did, and nothing outlives the call. It
        # stands before the first reader of the cache (the Groups section's call of Get-OERInventoryGroup,
        # below).
        if ($null -ne $RunContext) {
            $PrincipalNameCacheMember = $RunContext.PSObject.Properties['PrincipalNameCache']
            if ($null -ne $PrincipalNameCacheMember -and $PrincipalNameCacheMember.Value -is [hashtable]) {
                $PrincipalNameCache = $PrincipalNameCacheMember.Value
            }
        }
        # Sprint 11 step 6 (BL-133, A18): where the RoleAssignments section keeps what it learns about a
        # principal the directory did not return. The answers of the deleted items read that succeeded are
        # kept per principal, under the export's run context in its PrincipalStatus dictionary (one read per
        # principal for the whole export while that read succeeds), and otherwise in this invocation's own
        # dictionary; a read that fails is not kept, so the next row that needs it reads again. A principal
        # whose lookup or deleted items read failed is named unread: under a run context in the context's
        # UnreadPrincipal and UnreadPrincipalCause lists, which Export-OERInventory names in its
        # IncompleteReads and its own InventoryPartial -- the export calls this command per Azure scope
        # with -ErrorAction Stop, where this call's own InventoryPartial would skip the whole scope --
        # and otherwise in this call's unread collections and causes, so this call's InventoryPartial
        # names them like every other unread collection.
        $PrincipalStatusCache = if ($null -ne $RunContext) {
            $RunContext.PrincipalStatus
        } else {
            [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        function Add-PrincipalUnread {
            param([string]$Path, [string]$Cause, [string]$Target)
            Write-Verbose "Get-OERInventory: $Cause"
            if ($null -ne $RunContext) {
                $RunContext.UnreadPrincipal.Add($Path)
                $RunContext.UnreadPrincipalCause.Add([PSCustomObject]@{ Cause = $Cause; Target = $Target })
                return
            }
            Add-UnreadCause -Cause $Cause -Target $Target
            $UnreadCollections.Add($Path)
        }

        # Sprint 11 step 8 (A20, BL-152): the RoleAssignments and RoleManagementPolicies sections read a
        # -Scope or a -Subscription only in a subscription of the tenant the session's Microsoft Graph token
        # was issued for. Get-OERSubscriptionHomeTenant decides it (the single owner; nothing here decides
        # a tenant), for each of -Scope and -Subscription that is given and not blank, the second as
        # 'sub:<value>'. -ManagementGroup is never checked: a management group scope lies in no
        # subscription, and the owner answers NoSubscription for one (which management group ARM reaches
        # under the session's token is not measured: R-24 in
        # docs/development/rationale.md#home-tenant-subscriptions). The decision is made ONCE per
        # invocation, by the first section that asks, and reused by the second, so the subscription is
        # read at most once.
        #
        # The owner's cache: under Export-OERInventory the run context's SubscriptionTenant, which the
        # export's scope tree has filled for every scope it hands this call, so the check sends no request;
        # otherwise, and for a run context without that member (an older shape), this invocation's own.
        # The member is read through PSObject.Properties, so its absence reads as none.
        $SubscriptionTenantCache = $null
        if ($null -ne $RunContext) {
            $SubscriptionTenantMember = $RunContext.PSObject.Properties['SubscriptionTenant']
            if ($null -ne $SubscriptionTenantMember -and $SubscriptionTenantMember.Value -is [System.Collections.IDictionary]) {
                $SubscriptionTenantCache = $SubscriptionTenantMember.Value
            }
        }
        if ($null -eq $SubscriptionTenantCache) {
            $SubscriptionTenantCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        # Kept in a holder, since a local function cannot assign a variable of this block. Foreign holds the
        # verdicts whose subscription is another tenant's: their SubscriptionTenantMismatch records are
        # written once, after the inventory object, however many sections were refused.
        #
        # Sprint 11 step 10 (BL-155, R-4): SubscriptionId is the id the check itself resolved for -Subscription,
        # when that verdict is Home. A -Subscription given by its display name costs the check one read of the
        # subscription list; the two readers resolve a display name through the same list, once each, and
        # that resolution is a second decision about WHICH subscription the name means, made after the check
        # had shown one subscription to be the session tenant's own. So the readers are handed the id the
        # check decided on (Resolve-OERScope takes a GUID as it is, with no list read), never the name
        # (docs/development/rationale.md#home-tenant-subscriptions, "Sprint 11 step 10").
        $SubscriptionCheck = @{ Decided = $false; Verdicts = @(); Foreign = @(); SubscriptionId = $null }
        # Returns $true when the section may read as it always has (every checked scope is Home or
        # NoSubscription, or none was checked), and $false otherwise, when it reads nothing and writes no
        # row: for a Foreign verdict the refusal is recorded once, and the section is not unread (it is a
        # refusal, not a failed read); for an Undecided one, with no Foreign verdict, the section is named
        # unread under its own name, with the verdict's reason as its cause, so InventoryPartial names it.
        # A -Subscription verdict that leaves the holder without an id -- a Home verdict that carries none, or
        # a NoSubscription one whatever it carries -- is Undecided here too (R-4): the readers would otherwise
        # have to be handed the name, which is exactly what this decision replaces.
        function Test-SubscriptionInSessionTenant {
            param([string]$Section)
            if (-not $SubscriptionCheck.Decided) {
                $SubscriptionCheck.Decided = $true
                $SubscriptionCheck.Verdicts = @(
                    if (-not [string]::IsNullOrWhiteSpace($Scope)) {
                        [PSCustomObject]@{ Given = $Scope; IsSubscription = $false; Verdict = (Get-OERSubscriptionHomeTenant -Scope $Scope -Cache $SubscriptionTenantCache) }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($Subscription)) {
                        $SubscriptionScope = "sub:$Subscription"
                        [PSCustomObject]@{ Given = $SubscriptionScope; IsSubscription = $true; Verdict = (Get-OERSubscriptionHomeTenant -Scope $SubscriptionScope -Cache $SubscriptionTenantCache) }
                    }
                )
                $SubscriptionCheck.Foreign = @($SubscriptionCheck.Verdicts | Where-Object { [string]$_.Verdict.Verdict -eq 'Foreign' } | ForEach-Object { $_.Verdict })
                $SubscriptionVerdict = @($SubscriptionCheck.Verdicts | Where-Object { $_.IsSubscription })[0]
                if ($null -ne $SubscriptionVerdict -and [string]$SubscriptionVerdict.Verdict.Verdict -eq 'Home' -and
                    -not [string]::IsNullOrWhiteSpace([string]$SubscriptionVerdict.Verdict.SubscriptionId)) {
                    $SubscriptionCheck.SubscriptionId = [string]$SubscriptionVerdict.Verdict.SubscriptionId
                }
            }
            if ($SubscriptionCheck.Foreign.Count -gt 0) {
                Write-Verbose "Get-OERInventory: $Section was not read: $(@($SubscriptionCheck.Foreign | ForEach-Object { [string]$_.Reason }) -join '; ')."
                return $false
            }
            # One rule for -Subscription, decided on the holder and not on the verdict's own id: the readers are
            # handed $SubscriptionCheck.SubscriptionId, which is set for a Home verdict that carries an id and
            # for nothing else, so a -Subscription verdict is Undecided unless the holder has one. A
            # NoSubscription answer is therefore Undecided whether or not it carries an id (the owner never
            # answers NoSubscription for 'sub:<value>', so that is a stand-in's answer), and so is a Home
            # answer without one. A -Scope verdict needs no id and is never made Undecided by this term.
            $Undecided = @($SubscriptionCheck.Verdicts | Where-Object {
                    $Kind = [string]$_.Verdict.Verdict
                    $Kind -notin @('Home', 'NoSubscription') -or
                    ($_.IsSubscription -and [string]::IsNullOrWhiteSpace([string]$SubscriptionCheck.SubscriptionId))
                })
            if ($Undecided.Count -gt 0) {
                foreach ($One in $Undecided) {
                    # The reason of a failed read ends in that read's own message, which may end with a period,
                    # and the causes clause and the verbose line add their own: trimmed here, so neither ends in
                    # '..'. The owner's Reason itself is left as it is. A Home verdict has no Reason, so the
                    # id-less case says what is missing instead.
                    $UndecidedCause = if ([string]$One.Verdict.Verdict -in @('Home', 'NoSubscription')) {
                        "the subscription check gave no subscription id for '$($One.Given)', so the subscription cannot be read by its id"
                    } else {
                        ([string]$One.Verdict.Reason).TrimEnd().TrimEnd('.')
                    }
                    Write-Verbose "Get-OERInventory: $Section was not read: $UndecidedCause."
                    Add-UnreadCause -Cause $UndecidedCause -Target ([string]$One.Given)
                }
                if (-not $UnreadCollections.Contains($Section)) { $UnreadCollections.Add($Section) }
                return $false
            }
            $true
        }

        $GroupNameIndexHolder = @{ Index = $null }
        function Get-GroupNameIndexOnce {
            if ($null -ne $RunContext) {
                if ($null -eq $RunContext.GroupNameIndex) { $RunContext.GroupNameIndex = Get-OERGroupNameIndex }
                return $RunContext.GroupNameIndex
            }
            if ($null -ne $GroupNameIndexHolder.Index) { return $GroupNameIndexHolder.Index }
            $GroupNameIndexHolder.Index = Get-OERGroupNameIndex
            $GroupNameIndexHolder.Index
        }

        # BL-131 (Task 3c): how a group named as a principal in the RoleAssignments and
        # DirectoryRoleAssignments sections is written -- its display name only when no other group in
        # the tenant carries that name, otherwise its object id (Get-OERGroupReference owns the rule).
        # Called once per group row, so the index is read only when a section holds a group principal
        # whose name was read.
        # When the index could not be read, every group principal is written by its object id: an
        # exact reference the apply engine resolves verbatim, so nothing is missing from the document
        # and nothing is reported unread (R-3c). That is said once per invocation, on the verbose
        # stream, whichever section meets it first.
        $GroupPrincipalNote = @{ Written = $false }
        function Get-GroupPrincipalReference {
            param([string]$Id, [string]$Name)
            # A blank name, or a name that is the id itself (a principal whose name could not be
            # resolved), is written as the id whatever the index holds -- Get-OERGroupReference returns
            # the id for both -- so the index is not read for it.
            if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ceq $Id) { return $Id }
            $PrincipalIndex = Get-GroupNameIndexOnce
            if ($PrincipalIndex.Read -ne $true -and -not $GroupPrincipalNote.Written) {
                $GroupPrincipalNote.Written = $true
                Write-Verbose "Get-OERInventory: $($PrincipalIndex.Message); every group principal is written by its object id."
            }
            Get-OERGroupReference -Id $Id -Name $Name -Index $PrincipalIndex
        }

        # Reads the display name of the access package or assignment policy an access review points
        # at, and returns it -- or the id, which is a safe reference and is what the document carries
        # whenever no name is to be had. Local to this cmdlet for the same reason as Add-UnreadCause:
        # the two lookups share one rule, and the rule needs the cause list and the unread collections.
        #
        # THE READ IS A TRANSPORT READ WITH THE NOT-FOUND CODES DECLARED, NOT A CALL TO
        # Get-OERAccessPackage / Get-OERAccessPackageAssignmentPolicy. Those cmdlets publish what they
        # catch, and -ErrorVariable is filled by the ENGINE before any catch runs, so a lookup through
        # them left about ten records per lookup in the caller's error variable -- identical for a
        # deleted package and for a 403 -- and nothing that told the two apart. Declaring the codes
        # makes a deleted package or policy an ANSWER: the wrapper returns a marker instead of raising,
        # so nothing is deposited anywhere. Measured offline against the real wrapper: 20 records
        # for a review whose package and policy were deleted through the two readers, 0 through this
        # read. A 403, an exhausted 429, a 5xx, or a not-found code that was not declared still
        # raises (and still leaves its own strays, which is acceptable: it is a real failure, and the
        # partial names it). -Uri is the by-id URI the two readers send, so no request shape is
        # introduced that was not already live.
        #
        # THE THREE OUTCOMES:
        #   a name       -> the name; an answer with no name in it (null or blank) -> the id, and
        #                   nothing is reported
        #   the marker   -> the id; a deleted package or policy is a fact about the review, so no
        #                   partial is added and no record is left
        #   a throw      -> the id; the record is scrubbed first, then the read is counted as unread
        #                   (the cause AND the collection), so the run ends in InventoryPartial
        function Get-AccessReviewReferenceName {
            param(
                [string]$Uri,
                [string[]]$NotFoundCode,
                [string]$Id,
                [string]$ReviewName,
                [string]$Part,
                [string]$Label
            )
            try {
                $Response = Invoke-OERGraphRequest -Uri $Uri -ExpectedErrorCode $NotFoundCode
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $LookupCause = "Could not read an access review's $Label name: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $LookupCause"
                Add-UnreadCause -Cause $LookupCause -Target $Id
                $UnreadCollections.Add("accessReviews/$ReviewName/$Part")
                return $Id
            }
            if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { return $Id }
            # An answer that carries no name is no name: '' would be a DECLARED value, so it would
            # pass the schema and fail only at apply, where the id (a safe reference) applies cleanly.
            # Not a failed read either, so nothing is reported. Graph requires displayName, so this is
            # a guard against an odd body, not an expected path.
            $Name = [string]$Response.displayName
            if ([string]::IsNullOrWhiteSpace($Name)) { return $Id }
            return $Name
        }

        # BL-142: the apply engine resolves a review's accessPackage and assignmentPolicy NAME as creation
        # resolves it -- the access package by Resolve-OERAccessPackageId, in the whole tenant, and the
        # assignment policy by Resolve-OERAssignmentPolicyId, among the policies of the access package --
        # and refuses a name that lookup finds more than once (AmbiguousName), so an entry written with a
        # shared name could never be applied. A name Get-AccessReviewReferenceName returned is therefore
        # kept only when the engine's own lookup, sent here with the same URI, answers with this object
        # and no other; otherwise the id is written, which the engine takes as the object itself.
        #
        # A NAMED DEVIATION from the single-owner rule (Task 3b ruling): the two lookups are repeated here
        # rather than calling the resolvers, which throw AmbiguousName for a shared name and so would
        # leave stray records in a caller's -ErrorVariable -- the reason Get-AccessReviewReferenceName is a
        # transport read too. The Context "the export's review-reference lookups agree with the resolvers
        # (named deviation)" in tests/Unit/Public/Get-OERInventory.Tests.ps1 holds the URIs and the
        # decisions in step with the resolvers.
        #
        # -MatchOf picks the candidates the lookup's answer holds for the name, exactly as the resolver
        # does. Each answer is cached for the invocation under -CacheKey in -Cache, so the reviews of one
        # access package cost one lookup of each kind however many there are. A lookup that fails is
        # cached too, and every review that needed it writes the id and is reported like a failed name
        # read (the cause, and the unread collection under the review): an id there otherwise reads as a
        # deleted target.
        function Get-AccessReviewUniqueReference {
            param(
                [string]$Name,
                [string]$Id,
                [string]$Uri,
                [string]$CacheKey,
                [hashtable]$Cache,
                [scriptblock]$MatchOf,
                [string]$ReviewName,
                [string]$Part,
                [string]$Label
            )
            if (-not $Cache.ContainsKey($CacheKey)) {
                try {
                    $Answer = Invoke-OERGraphRequest -Uri $Uri
                    $Cache[$CacheKey] = [PSCustomObject]@{ Answer = $Answer; Failure = $null }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Cache[$CacheKey] = [PSCustomObject]@{ Answer = $null; Failure = [string]$PSItem.Exception.Message }
                }
            }
            $Lookup = $Cache[$CacheKey]
            if ($null -ne $Lookup.Failure) {
                $UniqueCause = "Could not check whether an access review's $Label name is unique: $($Lookup.Failure)"
                Write-Verbose "Get-OERInventory: $UniqueCause"
                Add-UnreadCause -Cause $UniqueCause -Target $Id
                $UnreadCollections.Add("accessReviews/$ReviewName/$Part")
                return $Id
            }
            $Found = @(& $MatchOf $Lookup.Answer $Name)
            if ($Found.Count -eq 1 -and [string]$Found[0].id -ieq $Id) { return $Name }
            return $Id
        }

        # The ids by name the groups are counted against as well (BL-131): set below only when the
        # index of every group in the tenant was read.
        $GroupExternalIds = $null
        if ($Include -contains 'Groups') {
            $GroupReadFilter = if ($GroupFilter) { $GroupFilter } else { 'securityEnabled eq true' }
            # The reader catches what it expects and names it in Unread and Causes. This catch is for
            # an error nothing in the reader catches: it ends the read, and the reader's try/finally
            # unwinds it -- a statement-terminating error as well as a throw -- so the call returns
            # nothing. Reading that as zero groups would state a failed read as an empty fact, so it
            # is counted unread like a list that could not be read, with the same wording.
            $GroupRead = $null
            try {
                $GroupRead = Get-OERInventoryGroup -Filter $GroupReadFilter -IncludeId:$IncludeId -PrincipalNameCache $PrincipalNameCache
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE the warning, as at every site
                # BL-44 names, so no warning stands between a failed read and its record. Under a Stop
                # warning preference the warning is a terminating error and ends the command in either
                # order (InventoryPartial is never reached), so no caller sees a difference; only the
                # verbose stream does. Held by the verbose line Add-UnreadSection writes first, in the
                # tests of this cmdlet.
                Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($PSItem.Exception.Message)"
                Write-Warning "Could not read groups: $($PSItem.Exception.Message)"
            }
            # Groups is the first section read, so replaying in order leaves the cause list and the unread
            # list exactly as the section used to leave them.
            if ($GroupRead) {
                foreach ($GroupCause in @($GroupRead.Causes)) { Add-UnreadCause -Cause $GroupCause.Cause -Target $GroupCause.Target }
                foreach ($GroupUnread in @($GroupRead.Unread)) { $UnreadCollections.Add($GroupUnread) }
                foreach ($GroupEntry in @($GroupRead.Groups)) { $Groups.Add($GroupEntry) }
            }
            # BL-131: a group's name is counted over every group in the tenant, not only over the groups
            # this section read, since the apply engine refuses a name a Microsoft 365 group or a
            # distribution group shares as well. The index is read after the section, so its cause (when
            # it fails) follows the section's own, and only when there is a group to count: a section
            # that read none has no name to count. A failed index is reported here, once -- verbose,
            # the cause list and 'groupNames' in the unread list -- since the names are then counted
            # over the groups read only, which may miss a name another group shares.
            if ($Groups.Count -gt 0) {
                $GroupNameIndex = Get-GroupNameIndexOnce
                if ($GroupNameIndex.Read -eq $true) {
                    $GroupExternalIds = $GroupNameIndex.IdsByName
                } else {
                    Write-Verbose "Get-OERInventory: $($GroupNameIndex.Message)"
                    Add-UnreadCause -Cause $GroupNameIndex.Message
                    $UnreadCollections.Add('groupNames')
                }
            }
        }

        if ($Include -contains 'AdministrativeUnits') {
            $AuItems = @()
            # Same shape as the group read in Get-OERInventoryGroup.ps1: Get-OERAdministrativeUnit
            # now writes a non-terminating error per unit whose members or scoped-role read failed,
            # and -ErrorAction Stop would abort the whole enumeration on the first one. The records
            # are inspected below rather than discarded.
            # The pipe into Where-Object is load-bearing, not tidying (BL-58), exactly as in the access review
            # read below ("The pipe into Where-Object is load-bearing", which carries the measured numbers;
            # docs/development/rationale.md#writeerror-deposit): a bare call inside @( ) leaks one record per
            # record written to the caller's -ErrorVariable, since the array subexpression runs the call as
            # its own nested pipeline and deposits the record again on the way out; only piping the call onward
            # before the @( ) closes leaks none. This call was that bare form, so every per-collection record
            # Get-OERAdministrativeUnit writes (AdministrativeUnitMemberReadFailed and its sibling) reached the
            # caller's -ErrorVariable although this read counts and words each of them itself. Do not
            # "simplify" the filter away.
            $AuReadErrors = $null
            try {
                $AuItems = @(Get-OERAdministrativeUnit -IncludeMembers -IncludeScopedRoles -ErrorAction SilentlyContinue -ErrorVariable AuReadErrors |
                        Where-Object { $null -ne $_ })
                # Sprint 11 step 10 (BL-43, R-28): the dynamic units among those just listed, by id and without
                # regard to letter case, built ONCE and only when a record was written, for the record loop
                # below (the same set as the group reader's, so no listed unit is scanned per failed record).
                $DynamicUnitIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if (@($AuReadErrors | Where-Object { $null -ne $_ }).Count -gt 0) {
                    foreach ($ListedUnit in $AuItems) {
                        if ([string]$ListedUnit.MembershipType -eq 'Dynamic' -and -not [string]::IsNullOrEmpty([string]$ListedUnit.Id)) {
                            $null = $DynamicUnitIds.Add([string]$ListedUnit.Id)
                        }
                    }
                }
                foreach ($AErr in @($AuReadErrors)) {
                    if ($null -eq $AErr) { continue }
                    if ($AErr.FullyQualifiedErrorId -like 'AdministrativeUnitNotFound*') { continue }
                    # Per-collection failures are accounted for at the projection below, where the
                    # affected unit is known by name; only anything else warrants a section warning.
                    if ($AErr.FullyQualifiedErrorId -like 'AdministrativeUnitMemberReadFailed*' -or
                        $AErr.FullyQualifiedErrorId -like 'AdministrativeUnitScopedRoleReadFailed*') {
                        # Keep the CAUSE, same reasoning as the group record loop in Get-OERInventoryGroup.ps1.
                        $AuCause = [string]$AErr.Exception.Message
                        Write-Verbose "Get-OERInventory: $AuCause"
                        # Sprint 11 step 10 (BL-43, R-28): as for a dynamic GROUP's members (R-24, in
                        # Get-OERInventoryGroup.ps1), the members read of a DYNAMIC unit is no gap, since a
                        # dynamic unit's members are omitted from the document below whether the read worked or
                        # not and no unread entry names them, so its cause is not recorded: a cause clause must
                        # never name a read that no unread entry names (the verbose line above is all that
                        # remains of it). The unit is found by the record's Target, its id, in the set of
                        # dynamic units just listed; a record with no Target matches none and keeps its cause,
                        # and so does every scoped-role record and every record of a static unit.
                        $DynamicUnitMembersFailure = $AErr.FullyQualifiedErrorId -like 'AdministrativeUnitMemberReadFailed*' -and
                            -not [string]::IsNullOrEmpty([string]$AErr.TargetObject) -and
                            $DynamicUnitIds.Contains([string]$AErr.TargetObject)
                        if (-not $DynamicUnitMembersFailure) {
                            Add-UnreadCause -Cause $AuCause -Target ([string]$AErr.TargetObject)
                        }
                        continue
                    }
                    # Same publisher test as the group record loop in Get-OERInventoryGroup.ps1, and for
                    # the same measured reason: seven failing units produced 56 section-level warnings,
                    # 49 of them foreign records the engine had collected from nested calls. See the
                    # matching comment there for why the PUBLISHER named in the FullyQualifiedErrorId,
                    # not the error id, is the discriminator.
                    if (@(([string]$AErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERAdministrativeUnit') {
                        # Counted unread as well as warned, for the same reason as the group list read in
                        # Get-OERInventoryGroup.ps1. Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE
                        # the warning, as at the group read above.
                        Add-UnreadSection -Key 'administrativeUnits' -Cause "Could not read administrative units: $($AErr.Exception.Message)"
                        Write-Warning "Could not read administrative units: $($AErr.Exception.Message)"
                    } else {
                        Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading " +
                            "administrative units ($($AErr.FullyQualifiedErrorId)): $($AErr.Exception.Message)")
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'AdministrativeUnitNotFound*') {
                    # Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE the warning, as above. This
                    # catch also catches the stop the warning of the record loop raises.
                    Add-UnreadSection -Key 'administrativeUnits' -Cause "Could not read administrative units: $($PSItem.Exception.Message)"
                    Write-Warning "Could not read administrative units: $($PSItem.Exception.Message)"
                }
            }
            foreach ($Au in $AuItems) {
                $Proj = [ordered]@{
                    displayName = $Au.DisplayName
                    description = $Au.Description
                    restricted  = [bool]$Au.IsMemberManagementRestricted
                }
                # Dynamic membership and hidden membership are writable on New/Set-OERAdministrativeUnit,
                # so project them or a re-applied inventory silently degrades a dynamic unit to static
                # and a HiddenMembership unit to public. membershipRule/processing state are meaningless
                # on an assigned unit, so they are emitted only for a dynamic one.
                $Proj.dynamic = ([string]$Au.MembershipType -eq 'Dynamic')
                if ($Proj.dynamic) {
                    $Proj.membershipRule = $Au.MembershipRule
                    if ($Au.MembershipRuleProcessingState) {
                        $Proj.membershipRuleProcessingState = [string]$Au.MembershipRuleProcessingState
                    }
                }
                $Proj.hiddenMembership = ([string]$Au.Visibility -eq 'HiddenMembership')
                if ($IncludeId) { $Proj.id = $Au.Id }
                # A dynamic unit's membership is rule-derived, so projecting it produces a member list
                # the apply handler can only skip. Omit it, matching membershipRule above.
                if (-not $Proj.dynamic) {
                    if ($Au.PSObject.Properties.Name -contains 'Members') {
                        # Same rule as group members (Get-OERInventoryGroup.ps1): a user as its UPN (resolvable + friendly), every other
                        # member type as its object id (which the apply resolves verbatim); display name is
                        # not resolvable so it is only a last-resort fallback. Written in the fixed order of
                        # Get-OEROrderedInventoryEntry, as a group's members are (Sprint 11 step 10, BL-121, R-16):
                        # Graph lists a unit's members in no fixed order, and the one owner of the order keeps
                        # two reads of one unchanged unit writing one list.
                        $AuMemberRefs = @(foreach ($M in @($Au.Members)) {
                            if (-not $M) { continue }
                            if ($M.UserPrincipalName) { [string]$M.UserPrincipalName }
                            elseif ($M.Id)            { [string]$M.Id }
                            else                      { [string]$M.DisplayName }
                        })
                        $Proj.members = @(Get-OEROrderedInventoryEntry -InputObject $AuMemberRefs)
                    } else {
                        # Explicit null, not an omitted key: an omitted administrativeUnits[].members
                        # key still reconciles and still prunes.
                        $Proj.members = $null
                        $UnreadCollections.Add("administrativeUnits/$($Au.DisplayName)/members")
                    }
                }
                if ($Au.PSObject.Properties.Name -contains 'ScopedRoles') {
                    # Scoped-role principals project as the object id: the Graph scopedRoleMembership carries
                    # no UPN for the role member, and the id resolves verbatim (a display name does not).
                    # The role projects as its friendly name when the directory-role name map has one for
                    # it, and otherwise falls back to the role id -- emitting role:null would fail schema
                    # validation and make the unit un-appliable. A role name that is only whitespace counts
                    # as missing, so it falls back to the role id too. A name map that could not be READ at all
                    # never gets here: Get-OERAdministrativeUnit then omits ScopedRoles, and the branch
                    # below reports it unread. A role or principal that is STILL blank after those
                    # fallbacks cannot be written either (an empty name is refused by the validator), so
                    # the collection is written as an explicit null and named, never with an empty name.
                    $SrNameless = $false
                    $SrProjected = @(foreach ($S in @($Au.ScopedRoles)) {
                        if (-not $S) { continue }
                        $SrPrincipal = if ($S.PrincipalId) { [string]$S.PrincipalId } else { [string]$S.PrincipalDisplayName }
                        $SrRole = if (-not [string]::IsNullOrWhiteSpace([string]$S.RoleName)) { [string]$S.RoleName } else { [string]$S.RoleId }
                        if ([string]::IsNullOrWhiteSpace($SrRole) -or [string]::IsNullOrWhiteSpace($SrPrincipal)) {
                            $SrNameless = $true
                            continue
                        }
                        [PSCustomObject]@{ role = $SrRole; principal = $SrPrincipal }
                    })
                    if ($SrNameless) {
                        $Proj.scopedRoles = $null
                        Add-NamelessCollection -Path "administrativeUnits/$($Au.DisplayName)/scopedRoles"
                    } else {
                        $Proj.scopedRoles = $SrProjected
                    }
                } else {
                    # Explicit null for the same reason as members: an omitted scopedRoles key prunes.
                    $Proj.scopedRoles = $null
                    $UnreadCollections.Add("administrativeUnits/$($Au.DisplayName)/scopedRoles")
                }
                $AdministrativeUnits.Add([PSCustomObject]$Proj)
            }

            # Sprint 11 step 8: principalType on a scoped role row whose principal the directory returned.
            # A Graph scopedRoleMembership does not say what kind of object its member is, so the distinct
            # principals the rows above name by object id, over EVERY unit, are looked up ONCE through
            # Resolve-OERPrincipalName -Detailed (one batched getByIds request per 1000 ids, and none at all
            # when no row names a principal by object id), into this section's own answers -- the shared
            # $PrincipalNameCache is not read or written here. A principal the directory returned as a
            # user, a group or a service principal gets principalType after principal, in the casing
            # ConvertTo-OERPrincipalType owns. One a successful lookup did not return, one of another type
            # (a device, for one), one named by its display name and a unit whose scopedRoles is null keep
            # their rows as they are, and nothing is reported: the type is information, since
            # Invoke-OERStructure matches a scoped role by role and principal alone. A failed lookup leaves
            # the rows of the principals it held without principalType (some or all of a unit's rows, since
            # one batch can fail while another succeeds) and names each affected unit unread ONCE, as
            # 'administrativeUnits/<name>/scopedRoles/principalType', with its cause; the scopedRoles
            # collection itself was read, so it stays written. A unit whose scopedRoles is null needs no
            # test of its own: @($null) holds one $null, whose principal is no object id.
            $SrPrincipalIds = [System.Collections.Generic.List[string]]::new()
            $SrPrincipalSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($AuEntry in $AdministrativeUnits) {
                foreach ($SrRow in @($AuEntry.scopedRoles)) {
                    $SrRowPrincipal = [string]$SrRow.principal
                    if ((Test-OERGuid -Value $SrRowPrincipal) -and $SrPrincipalSeen.Add($SrRowPrincipal)) { $SrPrincipalIds.Add($SrRowPrincipal) }
                }
            }
            if ($SrPrincipalIds.Count -gt 0) {
                $SrPrincipalAnswers = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($SrAnswer in @(Resolve-OERPrincipalName -Id $SrPrincipalIds.ToArray() -Detailed)) {
                    $SrPrincipalAnswers[[string]$SrAnswer.Id] = $SrAnswer
                }
                foreach ($AuEntry in $AdministrativeUnits) {
                    # The first principal of this unit whose lookup failed, with its cause: the unit is
                    # named once however many of its principals the failed lookup held.
                    $SrTypeUnread = $null
                    foreach ($SrRow in @($AuEntry.scopedRoles)) {
                        $SrRowPrincipal = [string]$SrRow.principal
                        if (-not (Test-OERGuid -Value $SrRowPrincipal)) { continue }
                        # An id the lookup gave no answer for (the dictionary then returns $null) was not
                        # looked up: it is read as a failed lookup, never as one the directory did not return.
                        $SrAnswer = $SrPrincipalAnswers[$SrRowPrincipal]
                        if ($null -eq $SrAnswer -or $SrAnswer.Read -ne $true) {
                            if ($null -eq $SrTypeUnread) {
                                $SrTypeCause = if ($null -ne $SrAnswer) { [string]$SrAnswer.Cause } else { 'the lookup returned no answer for this principal.' }
                                $SrTypeUnread = [PSCustomObject]@{ Id = $SrRowPrincipal; Cause = $SrTypeCause }
                            }
                            continue
                        }
                        if ($SrAnswer.Found -ne $true) { continue }
                        $SrType = ConvertTo-OERPrincipalType -ODataType ([string]$SrAnswer.ObjectType)
                        if ($null -eq $SrType) { continue }
                        $SrRow | Add-Member -NotePropertyName 'principalType' -NotePropertyValue $SrType
                    }
                    if ($null -ne $SrTypeUnread) {
                        $SrUnreadCause = "Could not look up the type of a scoped role principal through directoryObjects/getByIds: $($SrTypeUnread.Cause)"
                        Write-Verbose "Get-OERInventory: $SrUnreadCause"
                        Add-UnreadCause -Cause $SrUnreadCause -Target $SrTypeUnread.Id
                        $UnreadCollections.Add("administrativeUnits/$($AuEntry.displayName)/scopedRoles/principalType")
                    }
                }
            }
        }

        # Both the Catalogs and AccessPackages sections filter by the same -Catalog value and need
        # catalog OBJECTS (DisplayName/Description/Id read below), not a bare id -- Resolve-OERCatalogId
        # returns only a [string] id and cannot substitute here. Resolve once so the default -Include
        # (which contains both sections) does not issue the catalog list/read call twice.
        $ResolvedCatalogList = $null
        # The CURRENT display name of each Group and Application resource of a catalog, keyed by
        # originId: a catalog keeps the name a resource had when it was added, also after the group or
        # application is renamed (measured live 2026-09-30), and the apply engine identifies a Group or
        # Application resource by the object id its declared name resolves to. One getByIds call per
        # catalog through Resolve-OERPrincipalName, shared by both sections; an object the directory
        # does not return (deleted, unreadable, or a failed call) falls back to its id, which the apply
        # engine takes as the object id itself.
        $CatalogResourceNames = @{}
        $GetCatalogResourceNames = {
            param([string]$ForCatalogId, [object[]]$Resources)
            if (-not $CatalogResourceNames.ContainsKey($ForCatalogId)) {
                $Ids = @($Resources | Where-Object { [string]$_.OriginSystem -in @('AadGroup', 'AadApplication') -and $_.OriginId } |
                        ForEach-Object { [string]$_.OriginId })
                $CatalogResourceNames[$ForCatalogId] = if ($Ids.Count -gt 0) { Resolve-OERPrincipalName -Id $Ids -PreferDisplayName } else { @{} }
            }
            $CatalogResourceNames[$ForCatalogId]
        }
        if ($Include -contains 'Catalogs' -or $Include -contains 'AccessPackages') {
            # A catalog list that could not be read leaves BOTH sections empty, which is what the
            # document has always said. No handler removes a catalog or an access package that is
            # absent from the document ("Prune is child-scope only", Invoke-OERStructure), so the
            # projection stays as it was -- but an absent entry is not a fact, so the failure is
            # reported through InventoryPartial for every section that needed the list. Before this
            # the read had no error handling: under a caller's Stop it ended the whole call with no
            # document at all, and under Continue it left one stray record and no partial.
            # The one exception is a FACT about the caller's own -Catalog filter rather than a gap in
            # the export (spec G3: only a null from a name search, or a 404 on an id, is NotFound):
            # a missing catalog id is answered by Graph with CatalogNotFound (measured live,
            # 2026-10-02), which Get-OERCatalog republishes by id, so that arm is the one that fires
            # in production. It, AmbiguousCatalogName and the module's generic not-found codes on a
            # by-id read are all facts about the caller's filter; by name a non-match returns
            # nothing at all. Such a record is republished as itself and counted as nothing. A 404
            # on a NAME or on the unfiltered list is not a missing object, so it stays unread.
            try {
                $ResolvedCatalogList = if ($Catalog) {
                    if ($Catalog -as [guid]) { @(Get-OERCatalog -Id $Catalog -ErrorAction Stop) } else { @(Get-OERCatalog -DisplayName $Catalog -ErrorAction Stop) }
                } else { @(Get-OERCatalog -ErrorAction Stop) }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # The module's own not-found vocabulary (Get-OERAccessReviewInstance). Every comma
                # separated segment of the id is compared WHOLE, never as a prefix, since a composed
                # id ('ResourceNotFound,Get-OERCatalog') can carry the code outside the first slot.
                $CatListIdSegment = @(([string]$PSItem.FullyQualifiedErrorId) -split ',' | ForEach-Object { $_.Trim() })
                $CatListByIdNotFound = $Catalog -and ($null -ne ($Catalog -as [guid])) -and
                    (@($CatListIdSegment | Where-Object { $_ -in @('ResourceNotFound', 'Request_ResourceNotFound', 'ItemNotFound', 'NotFound') }).Count -gt 0)
                if ($PSItem.FullyQualifiedErrorId -like 'CatalogNotFound*' -or $PSItem.FullyQualifiedErrorId -like 'AmbiguousCatalogName*' -or $CatListByIdNotFound) {
                    $PSCmdlet.WriteError($PSItem)
                } else {
                    $CatListCause = "Could not read the catalogs: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $CatListCause"
                    Add-UnreadCause -Cause $CatListCause -Target ([string]$Catalog)
                    if ($Include -contains 'Catalogs') { $UnreadCollections.Add('catalogs') }
                    if ($Include -contains 'AccessPackages') { $UnreadCollections.Add('accessPackages') }
                }
                $ResolvedCatalogList = @()
            }
        }

        if ($Include -contains 'Catalogs') {
            foreach ($Cat in $ResolvedCatalogList) {
                $Proj = [ordered]@{
                    displayName       = $Cat.DisplayName
                    description       = $Cat.Description
                    # Cheap deterministic boolean -- always emitted, exactly like the administrative
                    # unit's restricted flag, so a catalog whose access packages are requestable by
                    # connected-organization users never silently re-creates as internal-only.
                    externallyVisible = [bool]$Cat.ExternallyVisible
                }
                if ($IncludeId) { $Proj.id = $Cat.Id }
                # A FAILED read is never projected as []: under -Prune an empty declared resource set
                # removes every resource of the catalog, and an omitted key still reconciles the same
                # way. An explicit null is the documented "leave the resources untouched" signal.
                # Before this, the read had no error handling at all: its record reached the caller's
                # stream, but the document still said "resources": [] and no InventoryPartial named it.
                # The shared name map is consulted only for a catalog that WAS read, so a failure never
                # caches an empty map for the access package section to reuse (see below).
                $CatRes = $null
                try {
                    $CatRes = @(Get-OERCatalogResource -Catalog $Cat.Id -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $CatResCause = "Could not read a catalog's resources: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $CatResCause"
                    Add-UnreadCause -Cause $CatResCause -Target ([string]$Cat.Id)
                    $UnreadCollections.Add("catalogs/$($Cat.DisplayName)/resources")
                    $CatRes = $null
                }
                if ($null -eq $CatRes) {
                    $Proj.resources = $null
                } else {
                    $CurrentNames = & $GetCatalogResourceNames ([string]$Cat.Id) $CatRes
                    $CatResNameless = $false
                    $CatResProjected = @(foreach ($R in $CatRes) {
                        # Map the resource type to the schema enum from the stable originSystem (the raw
                        # Graph resourceType is a display label, e.g. 'SharePoint Online Site', that the
                        # schema/apply do not accept). Falls back to the raw value for unknown systems.
                        $ResType = switch ($R.OriginSystem) {
                            'AadGroup'         { 'Group' }
                            'AadApplication'   { 'Application' }
                            'SharePointOnline' { 'SharePointSite' }
                            default            { $R.ResourceType }
                        }
                        # A SharePoint Online site is onboarded by its URL, which Graph stores as the
                        # resource originId -- the display name is only the site title and cannot be fed
                        # back into Add-OERCatalogResource -SharePointSite. Emit the URL as a distinct
                        # 'url' field so the apply engine has the real identifier while the human-readable
                        # name is preserved. A Group or Application resource is written under the group's
                        # or application's CURRENT name (looked up by originId, the id when it cannot be),
                        # never the name the catalog recorded when it was added.
                        $ResName = if ([string]$R.OriginSystem -in @('AadGroup', 'AadApplication') -and $R.OriginId -and $CurrentNames.ContainsKey([string]$R.OriginId)) {
                            $CurrentNames[[string]$R.OriginId]
                        } else {
                            $R.DisplayName
                        }
                        # A resource whose name is blank is written under its origin id when it has one
                        # (a site URL, or a group's or application's object id -- the validator accepts
                        # both as a name and the apply engine resolves them), since an empty name is
                        # refused. With no origin id either it cannot be named at all: see below.
                        if ([string]::IsNullOrWhiteSpace([string]$ResName) -and $R.OriginId) { $ResName = [string]$R.OriginId }
                        if ([string]::IsNullOrWhiteSpace([string]$ResName)) {
                            $CatResNameless = $true
                            continue
                        }
                        $ResProj = [ordered]@{ type = $ResType; name = $ResName }
                        if ($ResType -eq 'SharePointSite' -and $R.OriginId) {
                            $ResProj.url = [string]$R.OriginId
                        }
                        [PSCustomObject]$ResProj
                    })
                    if ($CatResNameless) {
                        # All or nothing, as for an unread set: a declared set that quietly left the
                        # unnamed resource out would have -Prune remove it. An explicit null is the
                        # documented "leave the resources untouched" signal.
                        $Proj.resources = $null
                        Add-NamelessCollection -Path "catalogs/$($Cat.DisplayName)/resources"
                    } else {
                        $Proj.resources = $CatResProjected
                    }
                }
                $Catalogs.Add([PSCustomObject]$Proj)
            }
        }

        if ($Include -contains 'AccessPackages') {
            # On v1.0 the accessPackage resource has no catalogId scalar -- catalog is a relationship
            # that a plain list does not return -- so iterate catalogs and read each catalog's packages.
            # This yields the catalog DISPLAY NAME for each package (round-trippable: New-OERAccessPackage
            # -Catalog and the schema's catalogs[].displayName cross-reference both take the name).
            # $ResolvedCatalogList is hoisted above (shared with the Catalogs section) so an unqualified
            # Get-OERInventory does not resolve the -Catalog filter twice.
            #
            # BL-39: a catalog whose name another listed catalog carries, without regard to letter case,
            # is left out of the catalogs section (Select-UniqueNamedEntry), and the apply engine refuses
            # its name as ambiguous (Resolve-OERCatalogId), so a package in it could never be applied by
            # that name. Such a package is written with the catalog's OBJECT ID instead, which the engine
            # takes as the catalog itself (Resolve-OERCatalogId returns a GUID as it is). Since the
            # package key is '<catalog>|<name>', packages of one name in two such catalogs are then two
            # keys, not a collision. The names are counted over the catalogs listed here only: -Catalog
            # given as an id lists that catalog alone, so a package in it keeps the catalog's name even
            # when another catalog in the tenant carries it (a known limit, documented in the help);
            # given as a name it lists every catalog Graph matches by that name, which are counted.
            $ApCatalogNameCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($CountCat in @($ResolvedCatalogList)) {
                $CountName = [string]$CountCat.DisplayName
                $ApCatalogNameCount[$CountName] = 1 + $(if ($ApCatalogNameCount.ContainsKey($CountName)) { $ApCatalogNameCount[$CountName] } else { 0 })
            }
            foreach ($ApCat in $ResolvedCatalogList) {
                # The catalog reference every package of this catalog is written with: its name, or its
                # object id when another listed catalog carries the name (see above). The unread paths of
                # this catalog below name it the same way, so two catalogs of one name never read alike.
                $ApCatalogRef = if ($ApCatalogNameCount[[string]$ApCat.DisplayName] -gt 1) { [string]$ApCat.Id } else { $ApCat.DisplayName }
                # A package list that could not be read projects the catalog with no packages, as it
                # always has: no handler removes an access package that is absent from the document
                # ("Prune is child-scope only", Invoke-OERStructure). An absent package is not a fact
                # though, so the failure is reported through InventoryPartial against the catalog.
                # It used to have no error handling: under a caller's Stop it ended the whole call
                # with no document at all, and under Continue it left one stray record and no partial.
                # BL-24: the list is read FIRST, ahead of the catalog's resources below, which only name
                # the bindings of a package that was listed.
                $ApList = @()
                try {
                    $ApList = @(Get-OERAccessPackage -Catalog $ApCat.Id -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $ApListCause = "Could not list a catalog's access packages: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $ApListCause"
                    Add-UnreadCause -Cause $ApListCause -Target ([string]$ApCat.Id)
                    $UnreadCollections.Add("accessPackages/$ApCatalogRef/packages")
                    $ApList = @()
                }
                # Build an OriginId -> resource display-name map ONCE per catalog. A resource role
                # binding's scope carries the resource OriginId plus a scope LABEL (commonly 'Root'
                # for the whole-resource scope) -- not the resource name. The apply engine resolves
                # the binding's resource against Get-OERCatalogResource display names, so project that
                # same name here (joined on OriginId) instead of the scope label, or the binding will
                # not round-trip.
                # A Group or Application resource is named by its CURRENT name, exactly as the Catalogs
                # section names it, so a binding resolves to the same object id on apply.
                $ApCatResMap = @{}
                # BL-24: this read only NAMES the bindings below, so it is made for a catalog whose package
                # list was read and holds at least one package. A catalog with no package has no binding to
                # name, and a package list that failed is left as [] above and leaves none to name either:
                # the read is not sent, and its failure is not reported, since nothing was left unread by
                # it. (The Catalogs section reads the catalog's resources for its own entry, separately,
                # and is not changed.)
                # The failure of this read is reported through InventoryPartial like any other unread
                # collection. When it cannot be read the map stays empty and $ApCatResRead is $false, which
                # changes what a binding falls back to (see the projection below): the name a binding
                # carries then is the one the catalog RECORDED when the resource was added, Graph keeps that
                # after a rename, and the apply engine resolves a declared name FIRST as a group name -- so
                # after a rename that name can resolve to ANOTHER group that now carries it, binding the
                # wrong group and, under -Prune, removing the real binding. A group's object id cannot name
                # another group.
                # It used to be -ErrorAction SilentlyContinue, which hid the failure from every caller.
                $ApCatResRead = $true
                $ApCatRes = @()
                if (@($ApList | Where-Object { $null -ne $_ }).Count -gt 0) {
                    try {
                        $ApCatRes = @(Get-OERCatalogResource -Catalog $ApCat.Id -ErrorAction Stop)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $ApCatResRead = $false
                        $ApCatResCause = "Could not read a catalog's resources to name its access packages' bindings: $($PSItem.Exception.Message)"
                        Write-Verbose "Get-OERInventory: $ApCatResCause"
                        Add-UnreadCause -Cause $ApCatResCause -Target ([string]$ApCat.Id)
                        $UnreadCollections.Add("accessPackages/$ApCatalogRef/catalogResourceNames")
                        $ApCatRes = @()
                    }
                    $ApCurrentNames = & $GetCatalogResourceNames ([string]$ApCat.Id) $ApCatRes
                    foreach ($Cr in $ApCatRes) {
                        if (-not $Cr.OriginId) { continue }
                        $ApCatResMap[[string]$Cr.OriginId] = if ([string]$Cr.OriginSystem -in @('AadGroup', 'AadApplication') -and $ApCurrentNames.ContainsKey([string]$Cr.OriginId)) {
                            [string]$ApCurrentNames[[string]$Cr.OriginId]
                        } else {
                            [string]$Cr.DisplayName
                        }
                    }
                }
                foreach ($Ap in $ApList) {
                    $Proj = [ordered]@{
                        displayName = $Ap.DisplayName
                        catalog     = $ApCatalogRef
                        description = $Ap.Description
                        # Cheap boolean -- always emitted so a hidden package stays hidden across a
                        # round-trip and a visible one is never silently re-hidden.
                        hidden      = [bool]$Ap.IsHidden
                    }
                    if ($IncludeId) { $Proj.id = $Ap.Id }

                    # D4: resource role bindings via M1. Recover the resource's real display name by
                    # joining the binding OriginId to the catalog resource map (the apply engine matches
                    # on that name). A group or application binding is written under its OriginId -- the
                    # object id, which the apply engine resolves verbatim (Resolve-OERGroupId returns a
                    # GUID as it is) and matches against the catalog resource's OriginId -- both when
                    # the map was NOT read, since the only name left is the one the catalog recorded and
                    # that can name another object after a rename, and when the name it has is blank,
                    # since an empty name is refused by the validator (A10). Any other binding falls
                    # back to the name the access package reader could join, which is the name the
                    # catalog recorded or none. A binding with no usable name and no such id (a
                    # SharePoint site, whose OriginId is its URL, a group with no OriginId, or a blank
                    # role) cannot be named at all, so the package's resourceRoles is written as an
                    # explicit null and named in InventoryPartial: all or nothing, since a declared set
                    # that quietly left the binding out would have -Prune remove it.
                    # A FAILED read is never projected as []: under -Prune an empty declared binding set
                    # removes every binding of the package, and an omitted key still reconciles the
                    # same way. An explicit null is the documented "leave the bindings untouched"
                    # signal, so that is what an unread set is, and the gap is reported through
                    # InventoryPartial like the group collections (Get-OERInventoryGroup.ps1) and the
                    # administrative-unit collections above.
                    # -ErrorAction Stop inside try/catch, the shape the directory-role sections below
                    # use: one reader per package, so a failure is attributed to exactly this package,
                    # and a record a reader swallowed internally (a retried 429) never counts as one.
                    $ApRoles = $null
                    try {
                        $ApRoles = @(Get-OERAccessPackageResourceRole -AccessPackage $Ap.Id -ErrorAction Stop)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $ApRolesCause = "Could not read an access package's resource role bindings: $($PSItem.Exception.Message)"
                        Write-Verbose "Get-OERInventory: $ApRolesCause"
                        Add-UnreadCause -Cause $ApRolesCause -Target ([string]$Ap.Id)
                        $UnreadCollections.Add("accessPackages/$($Ap.DisplayName)/resourceRoles")
                        $ApRoles = $null
                    }
                    if ($null -eq $ApRoles) {
                        $Proj.resourceRoles = $null
                    } else {
                        $RrNameless = $false
                        $RrProjected = @(foreach ($Rr in $ApRoles) {
                            $IsDirectoryObject = [string]$Rr.OriginSystem -in @('AadGroup', 'AadApplication')
                            $ResName = if ($Rr.OriginId -and $ApCatResMap.ContainsKey([string]$Rr.OriginId)) {
                                [string]$ApCatResMap[[string]$Rr.OriginId]
                            } elseif (-not $ApCatResRead -and $IsDirectoryObject -and $Rr.OriginId) {
                                [string]$Rr.OriginId
                            } else {
                                [string]$Rr.ResourceDisplayName
                            }
                            if ([string]::IsNullOrWhiteSpace($ResName) -and $IsDirectoryObject -and $Rr.OriginId) {
                                $ResName = [string]$Rr.OriginId
                            }
                            if ([string]::IsNullOrWhiteSpace($ResName) -or [string]::IsNullOrWhiteSpace([string]$Rr.RoleName)) {
                                $RrNameless = $true
                                continue
                            }
                            [PSCustomObject]@{ resource = $ResName; role = [string]$Rr.RoleName }
                        })
                        if ($RrNameless) {
                            $Proj.resourceRoles = $null
                            Add-NamelessCollection -Path "accessPackages/$($Ap.DisplayName)/resourceRoles"
                        } else {
                            $Proj.resourceRoles = $RrProjected
                        }
                    }

                    # D5: assignment policy internals -- full granular projection for round-trip fidelity.
                    # A policy set that could not be read projects [] exactly as it always has:
                    # Sync-OERStructureAccessPackage never removes an assignment policy (it reports an
                    # undeclared one as still in force), so [] deletes nothing. An absent policy is not
                    # a fact though, so the failure is reported through InventoryPartial. It used to have
                    # no error handling: under a caller's Stop it ended the whole call with no document
                    # at all, and under Continue it left one stray record and no partial.
                    $ApPolicies = @()
                    try {
                        $ApPolicies = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id -ErrorAction Stop)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $ApPoliciesCause = "Could not read an access package's assignment policies: $($PSItem.Exception.Message)"
                        Write-Verbose "Get-OERInventory: $ApPoliciesCause"
                        Add-UnreadCause -Cause $ApPoliciesCause -Target ([string]$Ap.Id)
                        $UnreadCollections.Add("accessPackages/$($Ap.DisplayName)/assignmentPolicies")
                        $ApPolicies = @()
                    }
                    # BL-131: the policies of ONE package are matched by name inside it, and the validator
                    # refuses two entries of one name (Sprint 11 step 5), so a name that two policies of
                    # the package carry, without regard to letter case, is written for none of them and
                    # reported once, with its count, as accessPackages/<package>/assignmentPolicies/<policy>.
                    # Leaving a policy out deletes nothing: Sync-OERStructureAccessPackage never removes an
                    # assignment policy. The policies of ANOTHER package never count (the call is per package).
                    $ApUniquePolicies = @(Select-UniqueNamedEntry -Entry $ApPolicies -Section 'assignmentPolicies' `
                            -KeyOf { param($E) $E.DisplayName } `
                            -NameOf { param($E) "$($Ap.DisplayName)/$($E.DisplayName)" } `
                            -UnreadOf { param($E) "accessPackages/$($Ap.DisplayName)/assignmentPolicies/$($E.DisplayName)" })
                    $Proj.assignmentPolicies = @(foreach ($P in $ApUniquePolicies) {
                        $PolProj = [ordered]@{ displayName = $P.DisplayName }
                        if ($P.Description) { $PolProj.description = $P.Description }
                        # requestorScope: always emit scope; emit users/groups only when non-empty.
                        if ($P.RequestorScope) {
                            $RsProj = [ordered]@{ scope = $P.RequestorScope.scope }
                            if ($P.RequestorScope.users -and @($P.RequestorScope.users).Count -gt 0) {
                                $RsProj.users = @($P.RequestorScope.users)
                            }
                            if ($P.RequestorScope.groups -and @($P.RequestorScope.groups).Count -gt 0) {
                                $RsProj.groups = @($P.RequestorScope.groups)
                            }
                            $PolProj.requestorScope = [PSCustomObject]$RsProj
                        }
                        # requestorSettings: always emit (cheap booleans; deterministic round-trip even
                        # when RequestorSettings is null -- [bool]$null -> $false). managerLevel only
                        # when allowManagerRequest is true.
                        $RstProj = [ordered]@{
                            allowSelfRequest    = [bool]$P.RequestorSettings.AllowSelfRequest
                            allowManagerRequest = [bool]$P.RequestorSettings.AllowManagerRequest
                        }
                        if ($P.RequestorSettings.AllowManagerRequest) {
                            $RstProj.managerLevel = $P.RequestorSettings.ManagerLevel
                        }
                        $RstProj.allowCustomSchedule = [bool]$P.RequestorSettings.AllowCustomSchedule
                        $RstProj.allowSelfExtend     = [bool]$P.RequestorSettings.AllowSelfExtend
                        $RstProj.allowSelfRemove     = [bool]$P.RequestorSettings.AllowSelfRemove
                        $RstProj.allowOnBehalfUpdate = [bool]$P.RequestorSettings.AllowOnBehalfUpdate
                        $RstProj.allowOnBehalfRemove = [bool]$P.RequestorSettings.AllowOnBehalfRemove
                        $PolProj.requestorSettings = [PSCustomObject]$RstProj
                        # Cheap booleans -- always emit for deterministic round-trip.
                        $PolProj.requireApproval               = [bool]$P.RequireApproval
                        $PolProj.requireRequestorJustification = [bool]$P.RequireRequestorJustification
                        $PolProj.requireApprovalForUpdate      = [bool]$P.RequireApprovalForUpdate
                        # approvalStages: emit each stage when list is non-empty.
                        if ($P.ApprovalStages -and @($P.ApprovalStages).Count -gt 0) {
                            $PolProj.approvalStages = @(foreach ($S in @($P.ApprovalStages)) {
                                $StProj = [ordered]@{
                                    durationDays = $S.durationDays
                                    manager      = [bool]$S.manager
                                }
                                if ($null -ne $S.managerLevel) { $StProj.managerLevel = $S.managerLevel }
                                if ($S.users -and @($S.users).Count -gt 0) { $StProj.users = @($S.users) }
                                if ($S.groups -and @($S.groups).Count -gt 0) { $StProj.groups = @($S.groups) }
                                if ($S.internalSponsor) { $StProj.internalSponsor = $true }
                                if ($S.externalSponsor) { $StProj.externalSponsor = $true }
                                if ($S.alternateUsers -and @($S.alternateUsers).Count -gt 0) { $StProj.alternateUsers = @($S.alternateUsers) }
                                if ($S.alternateGroups -and @($S.alternateGroups).Count -gt 0) { $StProj.alternateGroups = @($S.alternateGroups) }
                                if ($S.fallbackUsers -and @($S.fallbackUsers).Count -gt 0) { $StProj.fallbackUsers = @($S.fallbackUsers) }
                                if ($S.fallbackGroups -and @($S.fallbackGroups).Count -gt 0) { $StProj.fallbackGroups = @($S.fallbackGroups) }
                                if ($null -ne $S.escalationDays) { $StProj.escalationDays = $S.escalationDays }
                                if ($S.requireApproverJustification) { $StProj.requireApproverJustification = $true }
                                if ($S.approverInfoVisibility -and $S.approverInfoVisibility -ne 'Default') {
                                    $StProj.approverInfoVisibility = $S.approverInfoVisibility
                                }
                                [PSCustomObject]$StProj
                            })
                        }
                        # Expiration: emit exactly one form -- durationInDays preferred, then hours, then datetime.
                        if ($null -ne $P.DurationInDays) { $PolProj.durationInDays = $P.DurationInDays }
                        elseif ($null -ne $P.DurationInHours) { $PolProj.durationInHours = $P.DurationInHours }
                        elseif ($P.ExpirationDateTime) { $PolProj.expirationDateTime = $P.ExpirationDateTime }
                        # notificationsDisabled -- always emit for deterministic round-trip.
                        $PolProj.notificationsDisabled = [bool]$P.NotificationsDisabled
                        [PSCustomObject]$PolProj
                    })
                    $AccessPackages.Add([PSCustomObject]$Proj)
                }
            }
        }

        if ($Include -contains 'RoleAssignments') {
            if (-not ($Scope -or $Subscription -or $ManagementGroup)) {
                Write-Warning 'RoleAssignments requires a target scope (-Scope, -Subscription or -ManagementGroup); section skipped.'
            }
            elseif (-not (Test-SubscriptionInSessionTenant -Section 'roleAssignments')) {
                # A20 (BL-152): the subscription of -Scope or -Subscription is another tenant's, or could not
                # be decided, so nothing is read there and the section is written empty (see the check above).
                Write-Verbose 'Get-OERInventory: roleAssignments is written empty, since its subscription was not shown to belong to this tenant.'
            }
            else {
                $RaParams = @{ ResolveNames = $true }
                if ($Scope) { $RaParams.Scope = $Scope }
                # Sprint 11 step 10 (BL-155, R-4): the id the subscription check decided on, never the name as
                # given (Test-SubscriptionInSessionTenant has just made sure it is there).
                if ($Subscription) { $RaParams.Subscription = $SubscriptionCheck.SubscriptionId }
                if ($ManagementGroup) { $RaParams.ManagementGroup = $ManagementGroup }
                # Sprint 11 step 10 (BL-34, BL-155, R-3): a role assignment read that FAILED is an unread
                # section, never a fact. Before this the read ran under the caller's own preference, so a
                # failure either left its record on the caller's stream beside a RoleAssignments section that
                # was written empty with nothing to say it could not be read, or ended the whole call under a
                # caller's Stop. -ErrorAction Stop turns the reader's non-terminating records (InvalidScope,
                # AmbiguousFilter, the ARM read's own) into the one exception caught here, and the assignment
                # inside the try gets none of what the reader wrote before it failed: the section is read
                # whole or not at all. The record is scrubbed first, then folded into the cause and not
                # republished -- the catalog list's form -- and the section is named unread by its own name, so
                # InventoryPartial carries it with the reason. No warning is written (R-3): the partial error
                # is the report, after the inventory object. A section read nothing from is written empty, and
                # the code below reads nothing more for it: no principal lookup, and no root-scope or
                # undeclarable-scope notice for this call, since there is no row to name in one. Export's
                # per-scope call passes -ErrorAction Stop, so the InventoryPartial this writes still makes the
                # export skip the scope, as a failed read always did
                # (docs/development/rationale.md#unresolved-principals, "A failed Azure read is an unread section").
                $RaItems = @()
                try {
                    $RaItems = @(Get-OERRoleAssignment @RaParams -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $RaItems = @()
                    # The reader's message is trimmed of trailing white space and then of trailing full stops: the
                    # causes clause adds its own, and a message that ends in one (the role and policy lookups'
                    # do) would show '..'. The same trim as the Undecided cause above (R-18).
                    Add-UnreadSection -Key 'roleAssignments' -Cause "Could not read role assignments: $(([string]$PSItem.Exception.Message).TrimEnd().TrimEnd('.'))"
                }

                # Sprint 11 step 6 (BL-133, A18): the principals are looked up with
                # Resolve-OERPrincipalName -Detailed, one batched lookup per call, into this section's
                # own answers (the shared $PrincipalNameCache of the other sections is not read or
                # written here). The answer tells three cases apart that the default map could not:
                # a principal the directory returned (written by its name: a UPN for a user, so the
                # apply @-heuristic routes it to -User, a display name otherwise), one a successful
                # lookup did not return (written by its object id with principalStatus, below), and
                # one whose lookup failed (written by its object id and reported unread, never as a
                # fact). Keyed without regard to letter case.
                $RaPrincipalIds = @($RaItems | ForEach-Object { [string]$_.PrincipalId } | Where-Object { $_ } | Select-Object -Unique)
                $RaPrincipalAnswers = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($RaPrincipalIds.Count -gt 0) {
                    foreach ($RaAnswer in @(Resolve-OERPrincipalName -Id $RaPrincipalIds -Detailed)) {
                        if ($null -eq $RaAnswer -or [string]::IsNullOrEmpty([string]$RaAnswer.Id)) { continue }
                        $RaPrincipalAnswers[[string]$RaAnswer.Id] = $RaAnswer
                    }
                }

                # Projected first and added to the section below: whether two principals collide can
                # only be decided once every row has its name.
                $RaProjected = [System.Collections.Generic.List[object]]::new()
                foreach ($Ra in $RaItems) {
                    $RaPrincipalId = [string]$Ra.PrincipalId
                    # What the lookup said about this row's principal: Found (a name), NotFound (the
                    # principalStatus decided after the splits below) or a failed lookup (its cause).
                    # A row with no principal id is not looked up and keeps the name it was read under,
                    # as before.
                    $PrincipalNotFound = $false
                    $PrincipalLookupCause = $null
                    $PrincipalName = if (-not $RaPrincipalId) {
                        if ($Ra.PrincipalDisplayName) { $Ra.PrincipalDisplayName } else { $Ra.PrincipalId }
                    } else {
                        # An id the lookup gave no answer for was not looked up: it is read as a failed
                        # lookup, never as one the directory did not return.
                        $RaAnswer = if ($RaPrincipalAnswers.ContainsKey($RaPrincipalId)) { $RaPrincipalAnswers[$RaPrincipalId] } else { $null }
                        if ($null -eq $RaAnswer -or $RaAnswer.Read -ne $true) {
                            $PrincipalLookupCause = if ($null -ne $RaAnswer -and -not [string]::IsNullOrWhiteSpace([string]$RaAnswer.Cause)) {
                                [string]$RaAnswer.Cause
                            } else {
                                'the lookup returned no answer for this principal.'
                            }
                            $RaPrincipalId
                        } elseif ($RaAnswer.Found -ne $true) {
                            $PrincipalNotFound = $true
                            $RaPrincipalId
                        } elseif ($RaAnswer.ObjectType -and [string]$RaAnswer.ObjectType -notin @('user', 'group', 'servicePrincipal')) {
                            # A principal the directory returned as another type (a device, for one) is
                            # written by its object id, as it was before the lookup searched every type:
                            # principalType cannot name it, and its display name alone would be applied
                            # as a group of that name.
                            $RaPrincipalId
                        } else {
                            [string]$RaAnswer.Name
                        }
                    }
                    # Normalize the ARM principal type to the apply schema enum (User|Group|
                    # ServicePrincipal). ForeignGroup -- a B2B / cross-tenant group -- maps to Group.
                    # $PrincipalType keeps the normalised ARM type for the root-scope and unresolved
                    # principal rows below ('Device' stays 'Device'); $SchemaType is what the document
                    # carries as principalType: written for EVERY row whose type maps to the enum
                    # (Sprint 11 step 6, A18), in the enum's own casing, and omitted for any other ARM
                    # type (e.g. Device) rather than emitting an invalid enum value that would fail
                    # Test-OERStructure validation.
                    $PrincipalType = if ($Ra.PrincipalType -eq 'ForeignGroup') { 'Group' } else { [string]$Ra.PrincipalType }
                    $SchemaType = switch ($PrincipalType) {
                        'User' { 'User' }
                        'Group' { 'Group' }
                        'ServicePrincipal' { 'ServicePrincipal' }
                        default { $null }
                    }
                    # BL-131 (Task 3c): a group is written by its display name only when no other group
                    # in the tenant carries that name (Get-OERGroupReference), since the apply engine
                    # refuses a group name more than one live group answers to; otherwise by its object
                    # id with principalType Group, which Invoke-OERStructure resolves verbatim. Decided
                    # here, before the root-scope split and the collision pass below, which run on the
                    # name chosen here. A group written by its object id because it was not found, or
                    # its lookup failed, carries its id as the name, which Get-GroupPrincipalReference
                    # returns as it is, with no index read.
                    if ($PrincipalType -eq 'Group' -and $RaPrincipalId) {
                        $PrincipalName = Get-GroupPrincipalReference -Id $RaPrincipalId -Name ([string]$PrincipalName)
                    }
                    # BL-45: the role is written by its name, and by the role definition id the row already
                    # carries when the name is missing -- and a name that is only white space is missing too:
                    # the validator refuses an empty name, and a name of spaces cannot be told from one, so
                    # the same rule as the administrative unit's scoped role line above. The directory role
                    # row below follows it.
                    $Proj = [ordered]@{
                        scope     = $Ra.Scope
                        role      = $(if (-not [string]::IsNullOrWhiteSpace([string]$Ra.RoleName)) { $Ra.RoleName } else { $Ra.RoleDefinitionId })
                        principal = $PrincipalName
                    }
                    if ($SchemaType) {
                        $Proj.principalType = $SchemaType
                    }
                    # ABAC condition and the free-text description are writable by New-OERRoleAssignment
                    # and readable here, so project them or a condition-scoped assignment would be
                    # exported as an unconditioned one. conditionVersion is only meaningful alongside a
                    # condition (ARM defaults it to 2.0), so it is emitted only with one.
                    if ($Ra.Description) { $Proj.description = [string]$Ra.Description }
                    if ($Ra.Condition) {
                        $Proj.condition = [string]$Ra.Condition
                        $Proj.conditionVersion = $(if ($Ra.ConditionVersion) { [string]$Ra.ConditionVersion } else { '2.0' })
                    }
                    if ($IncludeId) { $Proj.id = $Ra.RoleAssignmentId }
                    $RaProjected.Add([PSCustomObject]@{
                            Ra = $Ra; Proj = $Proj; Type = $PrincipalType
                            NotFound = $PrincipalNotFound; LookupCause = $PrincipalLookupCause
                        })
                }

                # BL-126 (A4): a role assignment at the Azure root scope '/' (Test-OERAzureRootScope owns
                # the rule) is elevated access over every management group and subscription in the
                # tenant, a finding to review and not part of the RBAC model a document describes. A
                # read at a management group or a subscription returns it as inherited. It is taken out
                # of the projected rows here, BEFORE the collision pass below, so it never changes how
                # another row is named, and the document never carries it: the rows are named in one
                # warning and one information record after the section is built
                # (docs/development/rationale.md#root-scope-is-not-in-the-document).
                $RaRootRows = [System.Collections.Generic.List[object]]::new()
                $RaKeptRows = [System.Collections.Generic.List[object]]::new()
                foreach ($Row in $RaProjected) {
                    if (Test-OERAzureRootScope -Scope ([string]$Row.Proj.scope)) { $RaRootRows.Add($Row) } else { $RaKeptRows.Add($Row) }
                }
                $RaProjected = $RaKeptRows

                # A13, A15: a role assignment whose scope breaks a scope spelling rule the validator applies
                # (Get-OERScopeSpellingProblem owns the rules) is at a scope no document can declare: a
                # document that carried it would be refused as a whole. Azure Resource Manager returns one
                # at a resource whose name holds a '#' or a '%', for instance. It is taken out here, AFTER
                # the root split (a row at the root scope stays in the root list only) and BEFORE the
                # collision pass and the principalStatus step below, so it never changes how another row is
                # named and its principal is never looked for among the deleted items. Invoke-OERStructure
                # never prunes such an assignment: it prunes only at a scope a document declares. The rows
                # are counted in one warning and handed over in one information record after the section is
                # built (docs/development/rationale.md#undeclarable-scope).
                $RaUndeclarableRows = [System.Collections.Generic.List[object]]::new()
                $RaDeclarableRows = [System.Collections.Generic.List[object]]::new()
                foreach ($Row in $RaProjected) {
                    $ScopeProblems = @(Get-OERScopeSpellingProblem -Scope ([string]$Row.Proj.scope) -Path 'roleAssignments')
                    if ($ScopeProblems.Count -gt 0) {
                        $RaUndeclarableRows.Add([PSCustomObject]@{ Row = $Row; Problems = $ScopeProblems })
                    } else {
                        $RaDeclarableRows.Add($Row)
                    }
                }
                $RaProjected = $RaDeclarableRows

                # Entra does not keep display names unique, a group can carry a user's user principal
                # name as its display name, and Azure may return one scope in two spellings -- so two
                # rows can export the same (scope, role, principal), which the validator refuses as a
                # duplicate and so invalidates the whole document. The key is the validator's: the
                # canonical scope, the role and the principal, compared without regard to letter case.
                # Every row whose key collides moves its principal to the object id, the one name
                # that is unique; an id-named user, group or service principal is created as the right
                # type on a re-apply, since principalType is written for every row whose type maps to
                # the enum (above). Users move too: a user's fallback name can be a display name, and a
                # group can carry a user principal name. A colliding row whose principal already is its id
                # then moves its role to the full role definition id, for two role definitions that
                # share a display name. Repeated until nothing changes, since an object id can in turn
                # equal another principal's name. Each change moves a field to its id, and a field
                # moves only once, so it ends; what is left is one assignment read twice, which
                # Azure does not return.
                do {
                    $RaKeyCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($Row in $RaProjected) {
                        $RaKey = "$(ConvertTo-OERCanonicalScope -Scope ([string]$Row.Proj.scope))|$($Row.Proj.role)|$($Row.Proj.principal)"
                        $RaKeyCount[$RaKey] = 1 + $(if ($RaKeyCount.ContainsKey($RaKey)) { $RaKeyCount[$RaKey] } else { 0 })
                    }
                    $RaMoved = $false
                    foreach ($Row in $RaProjected) {
                        $RaKey = "$(ConvertTo-OERCanonicalScope -Scope ([string]$Row.Proj.scope))|$($Row.Proj.role)|$($Row.Proj.principal)"
                        if ($RaKeyCount[$RaKey] -le 1) { continue }
                        if ($Row.Ra.PrincipalId -and [string]$Row.Proj.principal -ne [string]$Row.Ra.PrincipalId) {
                            $Row.Proj.principal = [string]$Row.Ra.PrincipalId
                            $RaMoved = $true
                        } elseif ($Row.Ra.RoleDefinitionId -and [string]$Row.Proj.role -ne [string]$Row.Ra.RoleDefinitionId) {
                            $Row.Proj.role = [string]$Row.Ra.RoleDefinitionId
                            $RaMoved = $true
                        }
                    }
                } while ($RaMoved)

                # Sprint 11 step 6 (BL-133, A18): a principal the lookup did not return, or could not
                # look up, decided for the rows the document keeps -- after the root-scope split and the
                # undeclarable scope split above (a root row stays in the root list only, and an undeclarable
                # row in its own list, so nothing below is read or reported for either) and after the
                # collision pass, so the role and principal named here are the ones written.
                #   - A failed lookup: the row keeps its object id and principalType, carries no
                #     principalStatus, and is named unread as '<...>/principal' with its cause.
                #   - Not found: the principal is looked for among the directory's deleted items
                #     (Get-OERDeletedPrincipalStatus; a read that succeeds is kept, for the whole export under
                #     a run context and for the call otherwise, and a read that fails is sent again by the next
                #     row that needs it), and principalStatus says Deleted or Unresolved, directly after
                #     principalType (after principal when there is none). When that read fails the row
                #     is Unresolved -- the lookup succeeded and did not return the principal, so it is
                #     certainly not a live object the engine could create an assignment for; only the
                #     reason is unread -- and it is named unread as '<...>/principalStatus'.
                # '<...>' is 'roleAssignments/<role> -> <principal id> @ <scope>'.
                $RaStatusRows = [System.Collections.Generic.List[object]]::new()
                foreach ($Row in $RaProjected) {
                    $RowPath = "roleAssignments/$($Row.Proj.role) -> $($Row.Ra.PrincipalId) @ $($Row.Proj.scope)"
                    if ($null -ne $Row.LookupCause) {
                        Add-PrincipalUnread -Path "$RowPath/principal" `
                            -Cause "Could not look up the principal of a role assignment through directoryObjects/getByIds: $($Row.LookupCause)" `
                            -Target ([string]$Row.Ra.PrincipalId)
                        continue
                    }
                    if (-not $Row.NotFound) { continue }
                    $StatusAnswer = Get-OERDeletedPrincipalStatus -Id ([string]$Row.Ra.PrincipalId) -Cache $PrincipalStatusCache
                    $StatusIndex = if ($Row.Proj.Contains('principalType')) { 4 } else { 3 }
                    $Row.Proj.Insert($StatusIndex, 'principalStatus', [string]$StatusAnswer.Status)
                    if ($StatusAnswer.Read -ne $true) {
                        Add-PrincipalUnread -Path "$RowPath/principalStatus" `
                            -Cause "Could not read whether the principal of a role assignment is among the directory's deleted items: $($StatusAnswer.Cause)" `
                            -Target ([string]$Row.Ra.PrincipalId)
                    }
                    # StatusRead: whether the deleted items read behind the status succeeded, so a reader
                    # never takes the reason of an unread Unresolved as a fact.
                    $RaStatusRows.Add([PSCustomObject]@{ Row = $Row; StatusRead = ($StatusAnswer.Read -eq $true) })
                }
                foreach ($Row in $RaProjected) { $RoleAssignments.Add([PSCustomObject]$Row.Proj) }

                # BL-126: the root rows taken out above, one per assignment: Role and Principal are the
                # projected names, PrincipalType the normalised ARM type ('' when unknown).
                # Format-OERRootScopeAssignment owns their order and list text, which Export-OERInventory
                # shares. One warning names them all, and one information record (tag
                # Omnicit.EntraRBAC.RootScopeAssignment) carries the rows and the exact warning text, so
                # a caller -- Export-OERInventory among them -- reads the rows without parsing the text.
                if ($RaRootRows.Count -gt 0) {
                    $RootList = Format-OERRootScopeAssignment -Assignment @(foreach ($Row in $RaRootRows) {
                            [PSCustomObject]@{
                                RoleAssignmentId = [string]$Row.Ra.RoleAssignmentId
                                Role             = [string]$Row.Proj.role
                                Principal        = [string]$Row.Proj.principal
                                PrincipalType    = [string]$Row.Type
                            }
                        })
                    $RootWarning = "Get-OERInventory: left out $(@($RootList.Assignments).Count) role assignment(s) at the root scope '/', which grants access over every management group and subscription in the tenant (elevated access): $($RootList.Text). A document never carries a role assignment at the root scope, and Invoke-OERStructure never creates or removes one; review them as a finding."
                    Write-Warning $RootWarning
                    $RootNotice = [PSCustomObject]@{
                        Warning     = $RootWarning
                        Assignments = @($RootList.Assignments)
                    }
                    $RootNotice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RootScopeAssignmentNotice')
                    Write-Information -MessageData $RootNotice -Tags 'Omnicit.EntraRBAC.RootScopeAssignment'
                }

                # A13, A15: the rows at a scope no document can declare, taken out above, counted in ONE
                # warning and handed over in ONE information record (tag Omnicit.EntraRBAC.UndeclarableScope),
                # the root-scope pattern above, so a caller -- Export-OERInventory among them -- reads the rows
                # without parsing the text. Role and Principal are the projected names, PrincipalType the
                # normalised ARM type ('' when unknown), and Reason names the rules the scope breaks in words,
                # in the order Get-OERScopeSpellingProblem returns them. The words carry no character the
                # README's Markdown would read as markup.
                if ($RaUndeclarableRows.Count -gt 0) {
                    $UndeclarableAssignments = @(foreach ($Undeclarable in $RaUndeclarableRows) {
                            $Row = $Undeclarable.Row
                            $RuleWords = @(foreach ($Problem in $Undeclarable.Problems) {
                                    switch -CaseSensitive ([string]$Problem.Rule) {
                                        'Slash' { 'a trailing or doubled slash' }
                                        'DotSegment' { "a dot segment ('.' or '..')" }
                                        'Escape' { 'a percent sign' }
                                        'Backslash' { 'a backslash' }
                                        'QueryOrFragment' { 'a question mark or a number sign' }
                                        'WhiteSpace' { 'white space at the start or end of the scope or of a segment, white space other than a space, or a control character' }
                                        default { [string]$Problem.Rule }
                                    }
                                })
                            [PSCustomObject]@{
                                RoleAssignmentId = [string]$Row.Ra.RoleAssignmentId
                                Scope            = [string]$Row.Proj.scope
                                Role             = [string]$Row.Proj.role
                                Principal        = [string]$Row.Proj.principal
                                PrincipalType    = [string]$Row.Type
                                Reason           = 'the scope holds ' + ($RuleWords -join '; ')
                            }
                        })
                    $UndeclarableWarning = "Get-OERInventory: left out $($UndeclarableAssignments.Count) role assignment(s) whose scope no document can declare: the validator refuses the scope's spelling, so a document that carried one would be refused as a whole. Invoke-OERStructure never creates such an assignment, and never removes one, since it prunes only at a scope a document declares. An information record tagged Omnicit.EntraRBAC.UndeclarableScope names each with the rules its scope breaks; review them as a finding."
                    Write-Warning $UndeclarableWarning
                    $UndeclarableNotice = [PSCustomObject]@{
                        Warning     = $UndeclarableWarning
                        Assignments = $UndeclarableAssignments
                    }
                    $UndeclarableNotice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.UndeclarableScopeNotice')
                    Write-Information -MessageData $UndeclarableNotice -Tags 'Omnicit.EntraRBAC.UndeclarableScope'
                }

                # Sprint 11 step 6 (BL-133, A18): every row written with principalStatus, counted in ONE
                # warning and handed over in ONE information record (tag
                # Omnicit.EntraRBAC.UnresolvedPrincipal), the root-scope pattern above, so a caller --
                # Export-OERInventory among them -- reads the rows without parsing the text. The rows stay
                # in the document. PrincipalType is the normalised ARM type ('' when unknown); StatusRead is
                # false where the deleted items read failed (a Deleted status is always read).
                if ($RaStatusRows.Count -gt 0) {
                    $StatusAssignments = @(foreach ($StatusRow in $RaStatusRows) {
                            $Row = $StatusRow.Row
                            [PSCustomObject]@{
                                RoleAssignmentId = [string]$Row.Ra.RoleAssignmentId
                                Scope            = [string]$Row.Proj.scope
                                Role             = [string]$Row.Proj.role
                                Principal        = [string]$Row.Proj.principal
                                PrincipalType    = [string]$Row.Type
                                PrincipalStatus  = [string]$Row.Proj.principalStatus
                                StatusRead       = [bool]$StatusRow.StatusRead
                            }
                        })
                    $StatusWarning = "Get-OERInventory: $($StatusAssignments.Count) role assignment(s) name a principal the directory did not return, so each is written by the principal's object id with principalStatus: Deleted when the principal was found among the directory's deleted items, Unresolved when it was found neither in the directory nor among its deleted items (deleted beyond the retention period, a principal of another tenant, or not readable) or when its deleted items could not be read. Invoke-OERStructure never creates such an assignment; review them as a finding."
                    Write-Warning $StatusWarning
                    $StatusNotice = [PSCustomObject]@{
                        Warning     = $StatusWarning
                        Assignments = $StatusAssignments
                    }
                    $StatusNotice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.UnresolvedPrincipalNotice')
                    Write-Information -MessageData $StatusNotice -Tags 'Omnicit.EntraRBAC.UnresolvedPrincipal'
                }
            }
        }

        if ($Include -contains 'AccessReviews') {
            $ArItems = @()
            $SkippedReviewCount = 0
            # -ErrorAction SilentlyContinue + a LOCAL -ErrorVariable, not -ErrorAction Stop -- the
            # same fix, for the same mechanism, as the existence probe in
            # Sync-OERStructureAccessReview. Get-OERAccessReviewDefinition reports "nothing matched"
            # on -DisplayName by WRITING a non-terminating AccessReviewDefinitionNotFound record, and
            # $PSCmdlet.WriteError() deposits that record into every -ErrorVariable/$Error collector
            # already listening on the call stack the instant it runs. The catch below stops the
            # resulting exception from becoming a hard stop, but it can never retract a deposit
            # already made, so an inventory read that SUCCEEDED still left ghost
            # AccessReviewDefinitionNotFound records in the operator's own $Error.
            # The pipe into Where-Object is load-bearing, not tidying. Measured, one written record:
            # @(call -ErrorAction Stop) inside a try/catch leaks 3 to the caller; $Var = call
            # -SilentlyContinue -ErrorVariable leaks 1; @(call -SilentlyContinue -ErrorVariable)
            # leaks 1 (the array subexpression runs the call as its own nested pipeline and
            # re-deposits on the way out); only piping the call onward before the @( ) closes leaks
            # 0. Do not "simplify" the filter away.
            # SilentlyContinue here means "captured", not "ignored": the records are inspected below.
            $ArReadErrors = $null
            $ArParams = if ($AccessReviewFilter) {
                # -AccessReviewFilter is a display-name pattern (wildcards supported), matched
                # client-side -- the accessReviews endpoint does not reliably support server-side
                # name filtering.
                @{ DisplayName = $AccessReviewFilter }
            }
            else {
                # No filter supplied: capture every definition via the unfiltered list-all mode.
                @{ All = $true }
            }
            # The try/catch still guards a genuinely TERMINATING failure of the whole read; the loop
            # handles the NON-terminating records. Both are needed: neither subsumes the other.
            try {
                $ArItems = @(Get-OERAccessReviewDefinition @ArParams -ErrorAction SilentlyContinue -ErrorVariable ArReadErrors |
                        Where-Object { $null -ne $_ })
                foreach ($ArErr in @($ArReadErrors)) {
                    if ($null -eq $ArErr) { continue }
                    # No Remove-OERErrorRecord here, same as the group record loop (Get-OERInventoryGroup.ps1)
                    # and the administrative-unit loop above: a record Get-OERAccessReviewDefinition
                    # PUBLISHED was already scrubbed by
                    # that cmdlet's own catch, and scrubbing a reported diagnostic again would only
                    # strip it from $global:Error.
                    if ($ArErr.FullyQualifiedErrorId -like 'AccessReviewDefinitionNotFound*') { continue }
                    # Warn only for a record Get-OERAccessReviewDefinition itself PUBLISHED. Same
                    # publisher test, same measured reason, as the group record loop (Get-OERInventoryGroup.ps1)
                    # and the administrative-unit loop above: -ErrorVariable is
                    # filled by the ENGINE and also collects records raised inside nested calls even
                    # when an inner catch swallowed them, and Invoke-OERGraphRequest swallows and
                    # retries a 429, a 503 carrying Retry-After, and an ACRS claims challenge -- one
                    # retried-then-successful throttle measured three stray TooManyRequests records
                    # plus a bare, message-less RuntimeException. Membership, not a suffix match:
                    # Write-Error appends a further name when a record is republished.
                    if (@(([string]$ArErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERAccessReviewDefinition') {
                        # Counted unread as well as warned, for the same reason as the group list read in
                        # Get-OERInventoryGroup.ps1. Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE
                        # the warning, as at the group read above.
                        Add-UnreadSection -Key 'accessReviews' -Cause "Could not read access reviews: $($ArErr.Exception.Message)"
                        Write-Warning "Could not read access reviews: $($ArErr.Exception.Message)"
                    } else {
                        # Routed to verbose rather than dropped: a stray is still evidence when a read
                        # misbehaves, it just is not a section-level finding the operator must act on.
                        Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading " +
                            "access reviews ($($ArErr.FullyQualifiedErrorId)): $($ArErr.Exception.Message)")
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'AccessReviewDefinitionNotFound*') {
                    # Sprint 11 step 10 (BL-44): the bookkeeping stands BEFORE the warning, as above. This
                    # catch also catches the stop the warning of the record loop raises.
                    Add-UnreadSection -Key 'accessReviews' -Cause "Could not read access reviews: $($PSItem.Exception.Message)"
                    Write-Warning "Could not read access reviews: $($PSItem.Exception.Message)"
                }
            }
            # BL-142: the engine's two name lookups, cached for the invocation (Get-AccessReviewUniqueReference):
            # the access package lookup by the lower-cased name, the assignment policy listing by package id.
            # A PowerShell hashtable already compares keys without regard to letter case; the keys are
            # lower-cased as well so that stays true if the cache ever becomes an ordinal dictionary.
            $ArPackageNameLookup = @{}
            $ArPolicyListLookup = @{}
            foreach ($Ar in $ArItems) {
                # Only access-package-scoped reviews round-trip: the apply schema requires both
                # accessPackage and assignmentPolicy, and Invoke-OERStructure models access-package
                # reviews only. A review without both (for example a directory-role or group review)
                # cannot be applied and would make the inventory fail apply-schema validation, so skip it.
                if (-not $Ar.AccessPackageId -or -not $Ar.AssignmentPolicyId) {
                    Write-Verbose "Skipping access review '$($Ar.DisplayName)': not access-package-scoped (does not round-trip)."
                    $SkippedReviewCount++
                    continue
                }

                # A multi-stage review's reviewers live in stageSettings; the definition's top-level
                # reviewers collection is empty by construction and Microsoft Learn states it is ignored
                # when stageSettings is present. Projecting it would emit reviewers ["self"] below --
                # asserting a self review that was never configured. The apply schema models no stages,
                # so such a review cannot round-trip at all; skip it visibly rather than fabricate it.
                # Warned separately from the not-access-package-scoped skip above: the two have
                # different causes and different remedies, so folding them into one count could name
                # neither.
                if ([int]$Ar.StageCount -gt 0) {
                    Write-Warning "Get-OERInventory: skipping multi-stage access review '$($Ar.DisplayName)' ($($Ar.StageCount) stages). Its reviewers live in stageSettings, which the apply document does not model -- exporting it would misreport it as a single-stage self review. Manage it with New-OERAccessReviewStage."
                    continue
                }

                $Proj = [ordered]@{ displayName = $Ar.DisplayName }

                # accessPackage + assignmentPolicy: resolve ids to names (fallback to the id). Both ids
                # are present here (the skip above requires them). A deleted target is written by id
                # and reported nowhere; a FAILED read is written by id too and reported as an unread
                # collection -- see Get-AccessReviewReferenceName, which owns the rule and the reason
                # these are transport reads rather than calls to the Get-OER* readers.
                $Proj.accessPackage = Get-AccessReviewReferenceName `
                    -Uri ('v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?$expand=catalog' -f $Ar.AccessPackageId) `
                    -NotFoundCode 'AccessPackageNotFound', 'NotFound' `
                    -Id ([string]$Ar.AccessPackageId) -ReviewName ([string]$Ar.DisplayName) `
                    -Part 'accessPackage' -Label 'access package'
                # BL-142: a NAME (not the id) stays only when the engine's tenant-wide lookup of it
                # (Resolve-OERAccessPackageId, same URI, the name escaped the same way) finds exactly this
                # access package.
                # Named deviation, held in step with the resolver by the Get-OERInventory.Tests.ps1 Context "the export's review-reference lookups agree with the resolvers (named deviation)".
                if ([string]$Proj.accessPackage -ne [string]$Ar.AccessPackageId) {
                    $ApLookupName = [string]$Proj.accessPackage
                    $Proj.accessPackage = Get-AccessReviewUniqueReference -Name $ApLookupName -Id ([string]$Ar.AccessPackageId) `
                        -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq '{0}'&`$select=id,displayName" -f (ConvertTo-OERODataFilterValue -Value $ApLookupName)) `
                        -CacheKey $ApLookupName.ToLowerInvariant() -Cache $ArPackageNameLookup `
                        -MatchOf { param($Answer) @($Answer.value | Where-Object { $null -ne $_ }) } `
                        -ReviewName ([string]$Ar.DisplayName) -Part 'accessPackage' -Label 'access package'
                }
                $Proj.assignmentPolicy = Get-AccessReviewReferenceName `
                    -Uri ('v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}?$expand=accessPackage' -f $Ar.AssignmentPolicyId) `
                    -NotFoundCode 'PolicyNotFound', 'NotFound' `
                    -Id ([string]$Ar.AssignmentPolicyId) -ReviewName ([string]$Ar.DisplayName) `
                    -Part 'assignmentPolicy' -Label 'assignment policy'
                # BL-142: a NAME (not the id) stays only when exactly one policy of the review's access
                # package carries it, compared as Resolve-OERAssignmentPolicyId compares (-eq), and that
                # policy is this one. The listing is the resolver's, by the review's access package id.
                # Named deviation, held in step with the resolver by the Get-OERInventory.Tests.ps1 Context "the export's review-reference lookups agree with the resolvers (named deviation)".
                if ([string]$Proj.assignmentPolicy -ne [string]$Ar.AssignmentPolicyId) {
                    $Proj.assignmentPolicy = Get-AccessReviewUniqueReference -Name ([string]$Proj.assignmentPolicy) -Id ([string]$Ar.AssignmentPolicyId) `
                        -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '{0}'" -f $Ar.AccessPackageId) `
                        -CacheKey ([string]$Ar.AccessPackageId).ToLowerInvariant() -Cache $ArPolicyListLookup `
                        -MatchOf { param($Answer, $ForName) @(@($Answer.value) | Where-Object { $_.displayName -eq $ForName }) } `
                        -ReviewName ([string]$Ar.DisplayName) -Part 'assignmentPolicy' -Label 'assignment policy'
                }

                # reviewers -> friendly tokens (manager / self / resolved name). Every query is parsed
                # through Resolve-OERReviewerScopeQuery, the module's single owner of that grammar. It
                # is also what tolerates the API version prefix Graph adds when it NORMALIZES a reviewer
                # scope on read: a scope written as '/users/{id}' reads back as '/v1.0/users/{id}'.
                # Filtered: @($null).Count is 1, so an absent Reviewers property would otherwise read
                # as ONE scope -- a scope with no query, which would then count as an unparsed one and
                # both suppress the self default and raise a warning naming an empty string.
                $RawReviewers = @($Ar.Reviewers | Where-Object { $_ })
                $ParsedReviewers = @(foreach ($Rv in $RawReviewers) { Resolve-OERReviewerScopeQuery -Query ([string]$Rv.query) })
                $ReviewerIds = [System.Collections.Generic.List[string]]::new()
                foreach ($Parsed in $ParsedReviewers) {
                    if ($Parsed.Id) { $ReviewerIds.Add([string]$Parsed.Id) }
                }
                $MissingRevIds = @($ReviewerIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                if ($MissingRevIds.Count -gt 0) {
                    $ResolvedRev = Resolve-OERPrincipalName -Id $MissingRevIds
                    foreach ($K in $ResolvedRev.Keys) { $PrincipalNameCache[$K] = $ResolvedRev[$K] }
                }
                $Reviewers = [System.Collections.Generic.List[string]]::new()
                $UnparsedReviewers = [System.Collections.Generic.List[string]]::new()
                foreach ($Parsed in $ParsedReviewers) {
                    if ($Parsed.Kind -eq 'Manager') { $Reviewers.Add('manager'); continue }
                    # A scope object carrying no query at all names no reviewer, so it is dropped
                    # rather than reported -- naming an empty string in the warning helps nobody.
                    if ($Parsed.Kind -eq 'Unparsed') {
                        if ($Parsed.Query) { $UnparsedReviewers.Add([string]$Parsed.Query) }
                        continue
                    }
                    $RvId = [string]$Parsed.Id
                    $Reviewers.Add($(if ($PrincipalNameCache.ContainsKey($RvId)) { $PrincipalNameCache[$RvId] } else { $RvId }))
                }
                if ($RawReviewers.Count -eq 0) { $Reviewers.Add('self') }
                elseif ($UnparsedReviewers.Count -gt 0) {
                    # An UNPARSED scope is not an ABSENT one. No scope at all is the documented
                    # self-review shape (Learn: "To configure a self-review, don't specify the reviewers
                    # property or supply an empty object"); an unparsed scope means a real reviewer
                    # exists that this module's vocabulary cannot express. Microsoft Learn documents
                    # forms a portal-created review can carry that this module never emits -- './owners',
                    # '/servicePrincipals/{id}/owners', a filtered owners query. Dropping one silently
                    # would either fabricate a self review (when it was the only scope) or quietly shrink
                    # the reviewer set (when it was not), so name the offending queries in both cases.
                    # This warning is what surfaced the version-prefix defect -- keep it, and keep it
                    # naming the queries.
                    $UnparsedDetail = "Get-OERInventory: access review '$($Ar.DisplayName)' has $($UnparsedReviewers.Count) live reviewer scope(s) that this module's vocabulary cannot express ($($UnparsedReviewers -join ', '))"
                    if ($Reviewers.Count -eq 0) {
                        Write-Warning "$UnparsedDetail; exporting an empty reviewers list, which reads as a self review."
                    }
                    else {
                        Write-Warning "$UnparsedDetail; they are omitted from the exported reviewers list, which therefore names fewer reviewers than the live review."
                    }
                }
                $Proj.reviewers = @($Reviewers)

                # fallbackReviewers -> friendly tokens (resolved user/group name; manager is never a
                # fallback). A manager review carries a required fallback, so project it for round-trip.
                # Filtered for the same @($null).Count is 1 reason as the primary half above.
                $RawFallback = @($Ar.FallbackReviewers | Where-Object { $_ })
                if ($RawFallback.Count -gt 0) {
                    $ParsedFallback = @(foreach ($Fb in $RawFallback) { Resolve-OERReviewerScopeQuery -Query ([string]$Fb.query) })
                    $FbIds = [System.Collections.Generic.List[string]]::new()
                    foreach ($Parsed in $ParsedFallback) {
                        if ($Parsed.Id) { $FbIds.Add([string]$Parsed.Id) }
                    }
                    $MissingFbIds = @($FbIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                    if ($MissingFbIds.Count -gt 0) {
                        $ResolvedFb = Resolve-OERPrincipalName -Id $MissingFbIds
                        foreach ($K in $ResolvedFb.Keys) { $PrincipalNameCache[$K] = $ResolvedFb[$K] }
                    }
                    $Fallbacks = [System.Collections.Generic.List[string]]::new()
                    $UnparsedFallback = [System.Collections.Generic.List[string]]::new()
                    foreach ($Parsed in $ParsedFallback) {
                        # Anything with no object id is unexpressible HERE, including a './manager'
                        # scope: the document's fallbackReviewers vocabulary is user and group only.
                        if ($Parsed.Id) {
                            $FbId = [string]$Parsed.Id
                            $Fallbacks.Add($(if ($PrincipalNameCache.ContainsKey($FbId)) { $PrincipalNameCache[$FbId] } else { $FbId }))
                        }
                        elseif ($Parsed.Query) { $UnparsedFallback.Add([string]$Parsed.Query) }
                    }
                    # Same rule as the primary half: a silently dropped fallback is data loss, and a
                    # manager review whose only fallback did not parse exports with no fallbackReviewers
                    # at all -- which Microsoft Graph rejects on the way back in.
                    if ($UnparsedFallback.Count -gt 0) {
                        Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' has $($UnparsedFallback.Count) live fallback reviewer scope(s) that this module's vocabulary cannot express ($($UnparsedFallback -join ', ')); they are omitted from the exported fallbackReviewers list."
                    }
                    if ($Fallbacks.Count -gt 0) { $Proj.fallbackReviewers = @($Fallbacks) }
                }

                # recurrence -> friendly cadence.
                $Cadence = 'OneTime'
                $Rec = $Ar.Recurrence
                if ($Rec -and $Rec.pattern) {
                    $PType = [string]$Rec.pattern.type
                    $Interval = [int]$Rec.pattern.interval
                    # New-OERAccessReviewRecurrence can only emit weekly interval 1 and absoluteMonthly
                    # interval 1/3/6/12 (mirrors Resolve-OERAccessReviewChange's representable check), so
                    # every other live interval collapses onto a coarser cadence below. Warn before the
                    # collapse rather than exporting a bi-monthly or n-weekly review as Monthly/Weekly
                    # with no sign anything was lost.
                    $PatternRepresentable = switch ($PType) {
                        'weekly'          { $Interval -eq 1 }
                        'absoluteMonthly' { $Interval -in 1, 3, 6, 12 }
                        default           { $false }
                    }
                    if (-not $PatternRepresentable) {
                        Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' has a live recurrence pattern ($PType interval $Interval) that the module's cadence vocabulary cannot represent; exporting the nearest coarser cadence instead of the true interval."
                    }
                    $Cadence = switch ($PType) {
                        'weekly' { 'Weekly' }
                        'absoluteMonthly' { switch ($Interval) { 1 { 'Monthly' } 3 { 'Quarterly' } 6 { 'SemiAnnually' } 12 { 'Annually' } default { 'Monthly' } } }
                        default { 'OneTime' }
                    }
                }
                $Proj.recurrence = $Cadence

                if ($Ar.DescriptionForAdmins)    { $Proj.descriptionForAdmins    = $Ar.DescriptionForAdmins }
                if ($Ar.DescriptionForReviewers) { $Proj.descriptionForReviewers = $Ar.DescriptionForReviewers }
                # settings.instanceDurationInDays is NOT always a usable duration on the read side.
                # Microsoft's own list-definitions example response carries "instanceDurationInDays": 0
                # for a live review (learn.microsoft.com/graph/api/accessreviewset-list-definitions), and
                # accessReviewScheduleSettings documents the field as superseded whenever stageSettings
                # defines durationInDays -- so 0 is Graph's "this field does not drive the duration"
                # report, not a duration of zero days. The apply schema requires an integer 1-365, so
                # passing the live 0 straight through is what made the exported inventory fail the
                # schema.json shipped beside it. A bare "$null -ne" guard cannot catch it: the value is
                # a real 0, not a missing key. Omitting the key instead is the correct round-trip --
                # absent means "leave untouched" to Sync-OERStructureAccessReview -- and is the same
                # treatment the numbered-range occurrences below already gets for a live zero.
                $LiveDurationInDays = $Ar.DurationInDays -as [int]
                if ($LiveDurationInDays -ge 1 -and $LiveDurationInDays -le 365) {
                    $Proj.durationInDays = $LiveDurationInDays
                }
                elseif ($LiveDurationInDays -gt 365) {
                    # A configured-but-unrepresentable duration is dropped data, unlike the 0 sentinel
                    # above which represents nothing. Warn before dropping it rather than exporting a
                    # review whose duration silently reverts to the create-path default on apply.
                    Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' reports a live instance duration of $LiveDurationInDays day(s), which the apply schema (1-365) cannot represent; exporting no durationInDays for it."
                }
                $StartDate = $Ar.Recurrence.range.startDate
                if ($StartDate) { $Proj.startDate = [string]$StartDate }

                # Settings the apply schema declares and Sync-OERStructureAccessReview already applies.
                # Emitted unconditionally: they are cheap deterministic booleans, and omitting one means
                # "leave untouched", which would silently reset it when the document creates the review
                # in another tenant.
                $Proj.mailNotification       = [bool]$Ar.MailNotificationsEnabled
                $Proj.reminderNotification   = [bool]$Ar.ReminderNotificationsEnabled
                $Proj.requireJustification   = [bool]$Ar.JustificationRequired
                $Proj.recommendationsEnabled = [bool]$Ar.RecommendationsEnabled
                $Proj.autoApplyDecisions     = [bool]$Ar.AutoApplyDecisionsEnabled
                # Unlike the five booleans above, defaultDecision is presence-gated rather than
                # unconditional: it is a string, so the guard below excludes only a genuinely null/empty
                # value, not the specific value 'None' -- 'None' is truthy in PowerShell like any other
                # non-empty string and IS emitted when the live setting reports it (which round-trips
                # cleanly, since 'None' is also New-OERAccessReviewDefinition's own default). The guard
                # exists only to avoid writing an explicit-but-meaningless key when Settings itself did
                # not carry the field at all.
                if ($Ar.DefaultDecision) { $Proj.defaultDecision = [string]$Ar.DefaultDecision }

                # Recurrence range: emit at most one of endDate / occurrences (the schema and
                # Test-OERStructureSchema treat them as mutually exclusive) and neither for a OneTime
                # review, which carries no recurrence object at all. A live numbered range can report
                # zero occurrences, which the schema forbids -- emit nothing rather than an invalid value.
                if ($Cadence -ne 'OneTime') {
                    $RangeType = [string]$Ar.Recurrence.range.type
                    if ($RangeType -ieq 'endDate' -and $Ar.Recurrence.range.endDate) {
                        $Proj.endDate = [string]$Ar.Recurrence.range.endDate
                    } elseif ($RangeType -ieq 'numbered' -and [int]$Ar.Recurrence.range.numberOfOccurrences -ge 1) {
                        $Proj.occurrences = [int]$Ar.Recurrence.range.numberOfOccurrences
                    }
                }

                if ($IncludeId) { $Proj.id = $Ar.Id }
                $AccessReviews.Add([PSCustomObject]$Proj)
            }
            if ($SkippedReviewCount -gt 0) {
                Write-Warning "Get-OERInventory: skipped $SkippedReviewCount access review definition(s) that are not access-package-scoped. Only access-package reviews round-trip through Invoke-OERStructure; group, application and directory-role reviews are not captured."
            }
        }

        # Microsoft Entra directory roles, read through Microsoft Graph only. The two tenant-wide
        # schedule reads are shared by both sections and issued at most once per call: the
        # assignments section exports from them, and the policy section selects the roles in use from
        # them -- unless -AllDirectoryRolePolicies asks for every role, when they are read only if the
        # assignments section needs them.
        $IncludeDirectoryAssignments = $Include -contains 'DirectoryRoleAssignments'
        $IncludeDirectoryPolicies = $Include -contains 'DirectoryRoleManagementPolicies'
        # Per kind: the rows read, and whether the read succeeded. A failed read is not an empty one,
        # so the flag -- never the row count -- decides what the document may state.
        $DirectoryRows = @{ Eligible = @(); Active = @() }
        $DirectoryRead = @{ Eligible = $false; Active = $false }
        if ($IncludeDirectoryAssignments -or ($IncludeDirectoryPolicies -and -not $AllDirectoryRolePolicies)) {
            # Unfiltered: every tenant-scope schedule, direct and group-inherited, activations
            # included. -ErrorAction Stop, each read in its own try/catch, so a refused read lands in
            # the catch and is reported, never mistaken for an empty list.
            try {
                $DirectoryRows.Eligible = @(Get-OEREligibleDirectoryRoleAssignment -ErrorAction Stop)
                $DirectoryRead.Eligible = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role eligibility schedules: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                if ($IncludeDirectoryAssignments) { $UnreadCollections.Add('directoryRoleAssignments/Eligible') }
            }
            try {
                $DirectoryRows.Active = @(Get-OERActiveDirectoryRoleAssignment -ErrorAction Stop)
                $DirectoryRead.Active = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role assignment schedules: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                if ($IncludeDirectoryAssignments) { $UnreadCollections.Add('directoryRoleAssignments/Active') }
            }
        }

        if ($IncludeDirectoryAssignments) {
            $DirectoryKept = [System.Collections.Generic.List[object]]::new()
            foreach ($DirectoryKind in @('Eligible', 'Active')) {
                if (-not $DirectoryRead[$DirectoryKind]) { continue }
                $DirectorySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                # Only the rows the apply engine may match or prune -- tenant scope, direct, and for
                # Active an Assigned schedule, never an activation -- decided by the same single owner
                # Sync-OERStructureDirectoryRoleAssignment uses, so the export can never emit a row
                # the apply engine would not match.
                foreach ($DirectoryRow in @(Select-OERManagedDirectoryRoleAssignment -Assignment $DirectoryRows[$DirectoryKind] -Kind $DirectoryKind)) {
                    # Two schedules for one role, principal and kind (a future-dated second one, for
                    # example) would be two entries the validator refuses as a duplicate. Keep the
                    # first this read returned and say so. The handler compares against the first
                    # schedule ITS filtered read returns, and Microsoft Graph does not promise the two
                    # reads the same order, so the warning says the entry may then report a change.
                    if (-not $DirectorySeen.Add("$($DirectoryRow.RoleDefinitionId)|$($DirectoryRow.PrincipalId)")) {
                        # BL-45: the role is named here as the entry below writes it.
                        $DuplicateRole = if (-not [string]::IsNullOrWhiteSpace([string]$DirectoryRow.RoleName)) { [string]$DirectoryRow.RoleName } else { [string]$DirectoryRow.RoleDefinitionId }
                        Write-Warning ("Get-OERInventory: directory role '$DuplicateRole' has more than one $($DirectoryKind.ToLowerInvariant()) " +
                            "schedule for principal '$($DirectoryRow.PrincipalId)'; exporting the first. Invoke-OERStructure compares against " +
                            'the first schedule Microsoft Graph returns for that role and principal, so if the two differ it may report a change for this entry.')
                        continue
                    }
                    $DirectoryKept.Add([PSCustomObject]@{ Kind = $DirectoryKind; Row = $DirectoryRow })
                }
            }

            # Users and groups are named in ONE batched lookup through the shared per-invocation
            # cache. A service principal is never looked up: it is exported by object id, since its
            # display name is not unique and an ambiguous one fails on apply.
            $DirectoryNameIds = @($DirectoryKept |
                    Where-Object { [string]$_.Row.PrincipalType -in @('User', 'Group') } |
                    ForEach-Object { [string]$_.Row.PrincipalId } |
                    Where-Object { $_ -and -not $PrincipalNameCache.ContainsKey($_) } |
                    Select-Object -Unique)
            if ($DirectoryNameIds.Count -gt 0) {
                $ResolvedDirectory = Resolve-OERPrincipalName -Id $DirectoryNameIds
                foreach ($K in $ResolvedDirectory.Keys) { $PrincipalNameCache[$K] = $ResolvedDirectory[$K] }
            }

            # A user by its UPN and a group by its display name, each falling back to the object id
            # when no name was read; a service principal, or a principal of unknown type, by its
            # object id, which the apply engine resolves verbatim. BL-131 (Task 3c): a group keeps its
            # display name only when no other group in the tenant carries it (Get-OERGroupReference),
            # since the apply engine refuses a group name more than one live group answers to; it is
            # otherwise written by its object id, before the collision pass below. principalType Group
            # is written for it either way.
            $DirectoryPrincipals = [string[]]::new($DirectoryKept.Count)
            for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                $DirectoryRow = $DirectoryKept[$Index].Row
                $DirectoryPrincipalId = [string]$DirectoryRow.PrincipalId
                $DirectoryPrincipals[$Index] = if ([string]$DirectoryRow.PrincipalType -in @('User', 'Group') -and $PrincipalNameCache.ContainsKey($DirectoryPrincipalId)) {
                    [string]$PrincipalNameCache[$DirectoryPrincipalId]
                } else {
                    $DirectoryPrincipalId
                }
                if ([string]$DirectoryRow.PrincipalType -eq 'Group' -and $DirectoryPrincipalId) {
                    $DirectoryPrincipals[$Index] = Get-GroupPrincipalReference -Id $DirectoryPrincipalId -Name $DirectoryPrincipals[$Index]
                }
            }
            # Entra does not keep group display names unique, so two groups holding one role and kind
            # can carry the same name -- or a group can carry another principal's name -- and export
            # two identical (role, principal, assignmentType) entries, which the validator refuses as
            # a duplicate and so invalidates the whole document. Every GROUP row whose name collides,
            # without regard to letter case, with another row of the same role definition id and kind
            # is named by its object id instead; principalType stays Group. Repeated until nothing
            # changes, since a group's id can in turn equal another group's display name. Each pass
            # moves at least one group to its id, so it ends; only groups ever move.
            do {
                $DirectoryNameCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                    $CollisionKey = "$($DirectoryKept[$Index].Row.RoleDefinitionId)|$($DirectoryKept[$Index].Kind)|$($DirectoryPrincipals[$Index])"
                    $DirectoryNameCount[$CollisionKey] = 1 + $(if ($DirectoryNameCount.ContainsKey($CollisionKey)) { $DirectoryNameCount[$CollisionKey] } else { 0 })
                }
                $DirectoryRenamed = $false
                for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                    $DirectoryRow = $DirectoryKept[$Index].Row
                    if ([string]$DirectoryRow.PrincipalType -ne 'Group') { continue }
                    if ($DirectoryPrincipals[$Index] -eq [string]$DirectoryRow.PrincipalId) { continue }
                    $CollisionKey = "$($DirectoryRow.RoleDefinitionId)|$($DirectoryKept[$Index].Kind)|$($DirectoryPrincipals[$Index])"
                    if ($DirectoryNameCount[$CollisionKey] -gt 1) {
                        $DirectoryPrincipals[$Index] = [string]$DirectoryRow.PrincipalId
                        $DirectoryRenamed = $true
                    }
                }
            } while ($DirectoryRenamed)

            $DirectoryEntries = [System.Collections.Generic.List[object]]::new()
            for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                $Kept = $DirectoryKept[$Index]
                $DirectoryRow = $Kept.Row
                $DirectoryPrincipalType = [string]$DirectoryRow.PrincipalType
                # BL-45: the role definition id stands in for a role name that is missing or only white
                # space, the rule of the role assignment and scoped role lines above.
                $Proj = [ordered]@{
                    role      = $(if (-not [string]::IsNullOrWhiteSpace([string]$DirectoryRow.RoleName)) { [string]$DirectoryRow.RoleName } else { [string]$DirectoryRow.RoleDefinitionId })
                    principal = $DirectoryPrincipals[$Index]
                }
                if ($DirectoryPrincipalType) { $Proj.principalType = $DirectoryPrincipalType }
                $Proj.assignmentType = $Kept.Kind
                # DurationDays is the schedule window in whole days as the reader reconstructed it
                # through Resolve-OEREligibilityDuration -- the measure the apply engine compares
                # against -- so a re-applied export is Unchanged. A permanent assignment carries
                # neither durationDays nor permanent: the absence is how the document says permanent.
                if ($null -ne $DirectoryRow.DurationDays) { $Proj.durationDays = [int]$DirectoryRow.DurationDays }
                if ($IncludeId) { $Proj.id = [string]$DirectoryRow.ScheduleId }
                $DirectoryEntries.Add([PSCustomObject]$Proj)
            }
            # Role, then Eligible before Active, then principal -- ordinal, ignoring letter case, so
            # the document reads the same on every run and every machine.
            $DirectoryEntries.Sort([System.Comparison[object]] {
                    param($Left, $Right)
                    $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.role, [string]$Right.role)
                    if ($Order -eq 0) {
                        $LeftRank = if ($Left.assignmentType -eq 'Eligible') { 0 } else { 1 }
                        $RightRank = if ($Right.assignmentType -eq 'Eligible') { 0 } else { 1 }
                        $Order = $LeftRank.CompareTo($RightRank)
                    }
                    if ($Order -eq 0) {
                        $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.principal, [string]$Right.principal)
                    }
                    $Order
                })
            foreach ($DirectoryEntry in $DirectoryEntries) { $DirectoryRoleAssignments.Add($DirectoryEntry) }
        }

        if ($IncludeDirectoryPolicies) {
            $DirectoryPolicies = @()
            $DirectoryPoliciesRead = $false
            try {
                $DirectoryPolicies = @(Get-OERDirectoryRoleManagementPolicy -All -ErrorAction Stop)
                $DirectoryPoliciesRead = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role management policies: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                $UnreadCollections.Add('directoryRoleManagementPolicies')
            }
            if ($DirectoryPoliciesRead) {
                if (-not $AllDirectoryRolePolicies) {
                    # The policy of every role that has at least one row in the tenant-scope schedule
                    # reads -- the UNFILTERED rows, so a role held only through a group or only as an
                    # activation still counts. A policy customized on a role nobody holds is exported
                    # only by -AllDirectoryRolePolicies.
                    $DirectoryRolesInUse = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($DirectoryKind in @('Eligible', 'Active')) {
                        foreach ($DirectoryRow in @($DirectoryRows[$DirectoryKind])) {
                            if ($DirectoryRow -and $DirectoryRow.RoleDefinitionId) { $null = $DirectoryRolesInUse.Add([string]$DirectoryRow.RoleDefinitionId) }
                        }
                    }
                    # A selection made from an incomplete read still exports the roles the read that
                    # succeeded found, but is reported as partial, never presented as complete.
                    if (-not ($DirectoryRead.Eligible -and $DirectoryRead.Active)) {
                        $UnreadCollections.Add('directoryRoleManagementPolicies/role selection')
                    }
                    $DirectoryPolicies = @($DirectoryPolicies | Where-Object { $_ -and $DirectoryRolesInUse.Contains([string]$_.RoleDefinitionId) })
                }
                $DirectoryPolicyEntries = [System.Collections.Generic.List[object]]::new()
                foreach ($DirectoryPolicy in $DirectoryPolicies) {
                    if ($null -eq $DirectoryPolicy) { continue }
                    $DirectoryPolicyEntry = ConvertTo-OERInventoryRoleManagementPolicy -Policy $DirectoryPolicy -Directory
                    if ($IncludeId) { $DirectoryPolicyEntry | Add-Member -NotePropertyName 'id' -NotePropertyValue ([string]$DirectoryPolicy.PolicyId) }
                    $DirectoryPolicyEntries.Add($DirectoryPolicyEntry)
                }
                $DirectoryPolicyEntries.Sort([System.Comparison[object]] {
                        param($Left, $Right)
                        [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.role, [string]$Right.role)
                    })
                foreach ($DirectoryPolicyEntry in $DirectoryPolicyEntries) { $DirectoryRoleManagementPolicies.Add($DirectoryPolicyEntry) }
            }
        }

        if ($Include -contains 'RoleManagementPolicies') {
            # $RoleSources is begin's list (-Role, -CommonRoles, -AllRolesAtScope given), which also decides
            # whether the sign-in asks for the ARM token: this section reads only with exactly one.
            $HasScope = [bool]($Scope -or $Subscription -or $ManagementGroup)

            if ($RoleSources.Count -gt 1) {
                Write-Warning 'RoleManagementPolicies: specify only one of -Role, -CommonRoles, or -AllRolesAtScope; section skipped.'
            }
            elseif ($RoleSources.Count -eq 0) {
                Write-Warning 'RoleManagementPolicies requires -Role, -CommonRoles, or -AllRolesAtScope; section skipped.'
            }
            elseif (-not $HasScope) {
                Write-Warning "RoleManagementPolicies: -$($RoleSources[0]) requires a target scope (-Scope, -Subscription or -ManagementGroup); section skipped."
            }
            elseif (-not (Test-SubscriptionInSessionTenant -Section 'roleManagementPolicies')) {
                # A20 (BL-152): as for RoleAssignments, with the decision that section made, when it was
                # included: nothing is read there and the section is written empty.
                Write-Verbose 'Get-OERInventory: roleManagementPolicies is written empty, since its subscription was not shown to belong to this tenant.'
            }
            else {
                $ScopeParams = @{}
                if ($Scope) { $ScopeParams.Scope = $Scope }
                # Sprint 11 step 10 (BL-155, R-4): the id the subscription check decided on, never the name as
                # given, as for RoleAssignments above.
                if ($Subscription) { $ScopeParams.Subscription = $SubscriptionCheck.SubscriptionId }
                if ($ManagementGroup) { $ScopeParams.ManagementGroup = $ManagementGroup }

                # Sprint 11 step 10 (BL-34, BL-155, R-3): as for RoleAssignments above, a failed policy read is an
                # unread section. Every Get-OERRoleManagementPolicy call carries -ErrorAction Stop and the whole
                # read stands in ONE try, so the first failure -- a role that does not resolve
                # (RoleDefinitionNotFound), no policy for it (PolicyNotFound), an invalid scope, a failed role
                # enumeration, the ARM read's own record -- ends it, and the assignment gets none of the policies
                # read before it: under -Role A,B where B fails, A's policy is not written either. The section is
                # read whole or not at all, and an unread section is never a half-read one that states a subset as
                # if it were the whole. The record is scrubbed and folded into the cause, not republished, and no
                # warning is written. -CommonRoles is the exception, and the reader is left as it is: its per-role
                # catch (Get-OERRoleManagementPolicy.ps1) turns ANY failure to read a curated role's definition or
                # policy -- a refused or failed ARM read or an ambiguous name as much as a role missing at the
                # scope -- into a 'Skipping role' warning of its own and carries on, so none of those is a failure
                # here or named unread, and the section holds the policies of the roles that were read. Only a
                # scope the reader cannot resolve (InvalidScope) is a record, and reaches the catch below. Under
                # a Stop warning preference the stop at that warning leaves the reader and is caught below too:
                # the section is named unread with the warning's text, and the command carries on (measured with
                # the real reader, in the Describe 'Get-OERInventory -CommonRoles through the real
                # Get-OERRoleManagementPolicy').
                $Policies = @()
                try {
                    $Policies = @(
                        if ($CommonRoles) { Get-OERRoleManagementPolicy -CommonRoles @ScopeParams -ErrorAction Stop }
                        elseif ($AllRolesAtScope) { Get-OERRoleManagementPolicy -AllRolesAtScope @ScopeParams -ErrorAction Stop }
                        else { foreach ($R in $Role) { Get-OERRoleManagementPolicy -Role $R @ScopeParams -ErrorAction Stop } }
                    )
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Policies = @()
                    # Trimmed as the role assignment read's cause is (R-18).
                    Add-UnreadSection -Key 'roleManagementPolicies' -Cause "Could not read role management policies: $(([string]$PSItem.Exception.Message).TrimEnd().TrimEnd('.'))"
                }
                $RmpSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Rmp in $Policies) {
                    # ConvertTo-OERInventoryRoleManagementPolicy owns the entry shape, shared with the
                    # directoryRoleManagementPolicies section; without -Directory it is the Azure
                    # roleManagementPolicies entry, scope first.
                    $RmpEntry = ConvertTo-OERInventoryRoleManagementPolicy -Policy $Rmp
                    # The same policy read twice (-Role Reader,Reader, for one) would be two entries
                    # the validator refuses as a duplicate. The scope is compared in the canonical
                    # form the validator uses, the role without regard to letter case. Dropping the
                    # second loses nothing, since it is the one policy, so nothing is reported.
                    if (-not $RmpSeen.Add("$(ConvertTo-OERCanonicalScope -Scope ([string]$RmpEntry.scope))|$($RmpEntry.role)")) { continue }
                    if ($IncludeId) { $RmpEntry | Add-Member -NotePropertyName 'id' -NotePropertyValue $Rmp.PolicyId }
                    $RoleManagementPolicies.Add($RmpEntry)
                }
            }
        }

        # Select-UniqueNamedEntry runs into variables first, before the InventoryPartial check below,
        # so the objects it leaves out are reported with the rest, and before the inventory is emitted,
        # so the information record below precedes it.
        $UniqueGroups = @(Select-UniqueNamedEntry -Entry $Groups.ToArray() -Section 'groups' -KeyOf { param($E) $E.displayName } -ExternalIds $GroupExternalIds)
        $UniqueAdministrativeUnits = @(Select-UniqueNamedEntry -Entry $AdministrativeUnits.ToArray() -Section 'administrativeUnits' -KeyOf { param($E) $E.displayName })
        $UniqueCatalogs = @(Select-UniqueNamedEntry -Entry $Catalogs.ToArray() -Section 'catalogs' -KeyOf { param($E) $E.displayName })
        $UniqueAccessPackages = @(Select-UniqueNamedEntry -Entry $AccessPackages.ToArray() -Section 'accessPackages' -KeyOf { param($E) "$($E.catalog)|$($E.displayName)" } -NameOf { param($E) "$($E.catalog)/$($E.displayName)" })
        $UniqueAccessReviews = @(Select-UniqueNamedEntry -Entry $AccessReviews.ToArray() -Section 'accessReviews' -KeyOf { param($E) $E.displayName })

        # BL-131 (R-3): every name left out above, with its section and count, in ONE information record
        # (the BL-126 root-scope pattern), so a caller -- Export-OERInventory among them -- reads the
        # names without parsing the partial message. Under the default $InformationPreference it is not
        # displayed.
        if ($SharedNameList.Count -gt 0) {
            $Notice = [PSCustomObject]@{ Names = $SharedNameList.ToArray() }
            $Notice.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.SharedNameNotice')
            Write-Information -MessageData $Notice -Tags 'Omnicit.EntraRBAC.SharedName'
        }

        ConvertTo-OERInventory `
            -TenantId $DocumentTenantId `
            -Groups $UniqueGroups `
            -AdministrativeUnits $UniqueAdministrativeUnits `
            -Catalogs $UniqueCatalogs `
            -AccessPackages $UniqueAccessPackages `
            -AccessReviews $UniqueAccessReviews `
            -DirectoryRoleManagementPolicies $DirectoryRoleManagementPolicies.ToArray() `
            -DirectoryRoleAssignments $DirectoryRoleAssignments.ToArray() `
            -RoleAssignments $RoleAssignments.ToArray() `
            -RoleManagementPolicies $RoleManagementPolicies.ToArray()

        # A20 (BL-152): the refusal of a subscription of another tenant, the owner's own
        # SubscriptionTenantMismatch record, written ONCE per invocation however many of the two Azure
        # sections were refused, after the inventory object for the reason InventoryPartial is (below).
        # With both -Scope and -Subscription another tenant's, only the first verdict's record is written
        # (R-10): the -Scope's, which is checked first.
        if ($SubscriptionCheck.Foreign.Count -gt 0 -and $null -ne $SubscriptionCheck.Foreign[0].ErrorRecord) {
            $PSCmdlet.WriteError($SubscriptionCheck.Foreign[0].ErrorRecord)
        }

        # Emitted AFTER the inventory object so a caller still receives the document it has to
        # inspect, then learns that part of it was never read -- the same ordering
        # Export-OERInventory already uses for its own InventoryPartial.
        if ($UnreadCollections.Count -gt 0) {
            # Appended, not substituted: the triples stay exactly as they are (Export-OERInventory
            # folds -TargetObject into IncompleteReads verbatim). This clause only adds the WHY, so
            # an operator can tell a 429 (retry the export) from a 403 (grant a scope).
            # Deduplicated, capped, and the truncation STATED, all by Format-OERUnreadCauseClause,
            # which owns the wording. It returns an empty string when there is no cause to give.
            $CauseClause = Format-OERUnreadCauseClause -Cause $UnreadCauses.ToArray()
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "This inventory is PARTIAL: $($UnreadCollections.Count) collection(s) or object(s) could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are not stated as facts in the document (an accessReviews entry named as unread may still carry an id where a name could not be read). " +
                    "Unread: $($UnreadCollections -join ', '). A section reported here by its name alone could not be read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as " +
                    'leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. ' +
                    'An entry ending in scopedRoles/principalType is not such a key: it names a unit some or all of whose scoped role rows are written without principalType, since their principals'' type could not be read.' +
                    $CauseClause)) `
                -ErrorId 'InventoryPartial' `
                -Category LimitsExceeded `
                -TargetObject ($UnreadCollections -join ', ') `
                -Cmdlet $PSCmdlet
        }
    }
}
