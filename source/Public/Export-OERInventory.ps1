function Export-OERInventory {
    <#
    .SYNOPSIS
    Reads a tenant's RBAC posture and writes a self-contained bundle (JSON + LLM prompt + README).

    .DESCRIPTION
    Composes the existing Get-OER* read cmdlets into a timestamped bundle folder containing the
    canonical round-trippable inventory.json, per-area JSON files -- including
    directoryRoleManagementPolicies.json and directoryRoleAssignments.json for the Microsoft Entra
    directory role sections -- read-only context (scopeHierarchy.json, groupsRoster.json,
    azurePimEligibility.json, lighthouseDelegations.json), a formal
    JSON Schema (schema.json), a predefined LLM prompt (rbac-architect-prompt.md), and a README. With
    -IncludeServicePrincipalAccess it also writes servicePrincipalAccess.json, read-only context on the
    application permissions, delegated permission grants and owners of the tenant's service principals
    and app registrations (see SERVICE PRINCIPAL ACCESS below). The
    bundle is designed to be handed to any LLM to produce appliable RBAC proposals. Only
    RBAC-relevant groups are kept in full detail in inventory.json: a role-assignable group, a group
    with PIM eligibility, a group carrying a pimPolicy block, and, with -IncludeSyncedGroups, a
    security group synchronized from on-premises Active Directory. Microsoft Graph lists
    PIM-for-groups policies for a group that was never used with PIM for Groups as well, so the
    export writes a pimPolicy block only for a group found to use PIM for Groups -- one with PIM
    eligibility, or one whose PIM-for-Groups policy has been modified -- and a group whose policies
    Graph merely lists is not kept in full detail on that account. -AllGroupsDetailed keeps every
    group inventory.json covers. The cmdlet reads only -- no tenant state changes -- and
    authenticates at entry; an ARM token is acquired only when -Include names RoleAssignments or
    RoleManagementPolicies, the two Azure sections.

    HOW THE GROUPS ARE READ. Without -AllGroupsDetailed the export decides which groups are relevant
    BEFORE it reads any group in full, so in a tenant with very many groups a group that is not
    relevant is never read in full. For each listed group it reads the PIM eligibility (one
    request); a group that is role-assignable, has eligibility, or is synchronized under
    -IncludeSyncedGroups is decided by that. Any other group costs one more request, a listing of
    its PIM-for-Groups policies that tells whether it uses PIM for Groups. A group the two requests
    find not relevant costs exactly those two: its members, owners and PIM policies are not read,
    and it is not in inventory.json. Every other group is read in full exactly as before. A group
    whose relevance could not be read -- its eligibility read or the policy listing failed -- is
    read in full as before too, kept or left out by the same criteria, and what could not be read
    about it is named in IncompleteReads; it is never dropped on a guess. -AllGroupsDetailed reads
    every listed security group in full, as before. While it reads the groups the export shows
    progress (Write-Progress, activity Export-OERInventory, one 'Group n of N' record per listed
    security group) and ends it when the read is done, also when the read stops on an error.

    WHICH GROUPS INVENTORY.JSON COVERS, AND WHICH IT DOES NOT. The Groups section is read with the
    'securityEnabled eq true' filter, the one Get-OERInventory applies by default, so it carries the
    SECURITY-ENABLED groups only -- a distribution group, and a Microsoft 365 group whose
    securityEnabled is false, are absent from it at every detail level, -AllGroupsDetailed
    included. That scope is deliberate: inventory.json is the apply-engine document, and widening
    it widens what Invoke-OERStructure reconciles and, under -Prune, deletes. -GroupFilter narrows
    that scope and never widens it. To widen it anyway, read the inventory yourself with
    Get-OERInventory -GroupFilter and supply the filter you want. groupsRoster.json is NOT
    filtered: it lists every group in the tenant, of every type, as read-only context, so the gap
    between the two files is visible rather than silent. Each of its rows carries onPremisesSynced,
    true for a group synchronized from on-premises Active Directory and false otherwise, and
    memberCount: the group's member count when the export read the group in full, and null
    otherwise -- for a group the export found not relevant, one outside -GroupFilter, one left out
    because another group shares its name, one whose members could not be read, one whose members
    are written as null for the reason given below, and every group that is not security-enabled.
    Null means not known, which is not zero: a count would cost a request per group. The count is
    the group's live member count, so it includes the members left out of inventory.json as PIM for
    Groups access (see MEMBERS AND OWNERS THAT PIM FOR GROUPS HOLDS). Each row also carries the
    group's object id, so two groups with one display name, or a group that was renamed, can be
    told apart; its type, as the three values Microsoft Graph gives it (securityEnabled and
    mailEnabled, each true, false or null when Graph gave none, and groupTypes, always an array,
    empty for a group that is neither a Microsoft 365 group nor dynamic); its visibility (Public,
    Private or HiddenMembership, null when Graph gave none, which is the case for most security
    groups); and createdDateTime, the time Graph gave for its creation as a UTC ISO 8601 string,
    null when none was given. The roster is read-only context: inventory.json stays without object
    ids.

    MEMBERS AND OWNERS THAT PIM FOR GROUPS HOLDS. inventory.json and groups.json write a group's
    STANDING members and owners only (the Get-OERInventory help describes the rule). A member or
    owner whose access PIM for Groups holds -- an activation, or another active assignment that is
    not standing, such as a time-bound one -- is left out, since writing it would record access that
    PIM for Groups grants on its own terms (a time limit, approval, multi-factor authentication) as
    if it were a standing membership. The group's PIM for Groups assignments are read once for each
    group read in full whose read members or owners hold at least one entry. When that read fails,
    'groups/<name>/pimAssignments' is named in IncompleteReads and every member and owner that is
    eligible for the same access is left out instead; when the group's eligibility could not be read
    either, a members collection that holds entries is written as an explicit null and an owners
    collection that holds entries is left out, both named in IncompleteReads, and the roster's
    memberCount is null for a group whose members are written as null. The generated README.md names
    the groups concerned that inventory.json writes in a section "Members and owners left out as PIM
    for Groups access": for each group, by name and never by principal, how many members and owners
    were left out and on which basis, or the statement that none was. Leaving a member or owner out
    of the export changes nothing in the tenant. The roster's memberCount counts the members read,
    the ones left out included, so it keeps meaning the group's live member count, also for a group
    read in full that inventory.json does not keep. The read needs the Microsoft Graph
    permission PrivilegedAssignmentSchedule.Read.AzureADGroup (Get-OERRequiredScope lists it).

    Azure coverage is reported, not assumed. ScopesEnumerated is how many ARM scopes the walk found,
    ScopeCount is how many of them were actually read, and SkippedScopes names the ones that were
    not. When anything was skipped the bundle summary is still emitted first and is then followed by
    a non-terminating InventoryPartial error, so a caller using -ErrorAction Stop or a try/catch
    finds out that roleAssignments.json and roleManagementPolicies.json are incomplete instead of
    treating a truncated bundle as a full tenant snapshot. A level of the tree that could not be
    LISTED is skipped the same way: a refused or failed management-group listing is named in
    SkippedScopes and SkippedEligibilityScopes as '<management groups: the listing failed>' (a failed
    subscription listing as '<subscriptions: the listing failed>'), never read as "no management
    groups". A management group created in the last few minutes can be missing from the
    management-group list, and an export run in that window does not walk it -- nor name it as
    skipped -- because it cannot know it exists. Wait until Get-OERManagementGroup lists it before
    relying on an export that should include it. Of the subscriptions, ScopesEnumerated counts only
    those of this tenant: a subscription of another tenant, or one whose home tenant could not be read,
    is not walked and not counted (see SUBSCRIPTIONS OF ANOTHER TENANT below).

    Azure PIM eligibility is read the same walk over, into azurePimEligibility.json, but only when an
    Azure section (RoleAssignments or RoleManagementPolicies) is included -- the file is absent
    otherwise. That is UNLIKE the two role-assignment files it sits beside: roleAssignments.json and
    roleManagementPolicies.json are always written, as an empty [] when no Azure section was
    requested, while azurePimEligibility.json, like lighthouseDelegations.json (see AZURE LIGHTHOUSE
    DELEGATIONS below), is sometimes not written at all. One paged Get-OEREligibleRoleAssignment read
    runs per scope the walk visits: a management group scope is read with -AtScope (eligibilities at
    or above it); every other scope is read unfiltered, which also surfaces eligibilities below that
    scope -- Microsoft Learn's listForScope
    documents four filters (atScope(), principalId eq '{id}', assignedTo('{userId}') and asTarget())
    and no unfiltered semantics at all, so this was MEASURED rather than taken from documentation: in
    the step 5 live-verification checklist, section 4
    (docs/live-verification/feat-inventory-directory-roles-and-rename-checklist.md), one unfiltered
    subscription read returned an eligibility at a resource group below it (2026-09-30).
    Without -Scope, Resolve-OERInventoryScopeTree enumerates management group and subscription
    scopes only, so a resource-group- or resource-scoped eligibility reaches this file only through
    that unfiltered subscription read's below-scope behaviour; a -Scope naming a resource group or a
    resource is itself the one scope read, unfiltered. The results
    are deduplicated on the eligibility schedule id, so one eligibility
    visible from several scopes in the walk appears once -- for example a management-group
    eligibility, read once directly at the management group and again, inherited, from every
    subscription below it. The file is read-only context, exactly like scopeHierarchy.json and
    groupsRoster.json: it is never an apply-document section and no apply cmdlet reads it back. Every
    per-area file and azurePimEligibility.json alike is always a JSON array on disk, written as [] when
    it carries nothing. A scope whose eligibility read fails is named in SkippedEligibilityScopes and
    folds into the same trailing InventoryPartial error as a failed role-assignment scope.

    AZURE LIGHTHOUSE DELEGATIONS. Azure Lighthouse lets another tenant -- a service provider, for
    example -- manage subscriptions or resource groups of this one: a delegation gives principals of
    that managing tenant Azure built-in roles over the delegated scope. Microsoft Learn states that
    the role assignments of this tenant do not list that access, so roleAssignments.json and
    inventory.json never show it. The export reads the delegations of the subscriptions its walk
    visits into lighthouseDelegations.json, after the eligibility read. Since the walk reads only this
    tenant's own subscriptions (see SUBSCRIPTIONS OF ANOTHER TENANT below), and Azure Lighthouse
    refuses a delegation whose managing tenant is the subscription's own tenant, every row is access
    another tenant holds over a subscription or resource group of this tenant. The file is written exactly
    when azurePimEligibility.json is -- when an Azure section (RoleAssignments or
    RoleManagementPolicies) is included, with no switch of its own -- and is absent otherwise. It is
    always a JSON array, [] when no delegation was read. Each row is one delegation: scope (the
    subscription or resource group delegated), subscriptionId, resourceGroup (null for a
    subscription), managedByTenantId, managedByTenantName, offerName (the registration definition's
    name), registrationAssignmentId, registrationDefinitionId, authorizations and
    eligibleAuthorizations (the just-in-time ones). An authorization carries principalId,
    principalDisplayName, roleDefinitionId, roleName and delegatedRoleDefinitionIds, an eligible one
    the first four of those. A value that is blank or not known is null, the three lists are always
    arrays, and the rows are sorted by scope, managedByTenantId, offerName and
    registrationAssignmentId. The file is read-only context, like azurePimEligibility.json: it is
    never an apply-document section, no apply cmdlet reads it back, and Invoke-OERStructure never
    creates or removes a delegation.

    For each subscription the walk visits, the export makes two paged reads through
    Invoke-OERArmRequest (Microsoft.ManagedServices, api-version 2022-10-01): the registration
    assignments, with their registration definitions expanded, and the registration definitions.
    Microsoft Learn does not say whether a subscription's assignment list also returns the
    assignments of its resource groups, so when a definition is named by no assignment of that list,
    the export lists the subscription's resource groups once and reads the assignment list of each;
    otherwise no resource group is listed. A subscription is read whole or not at all. Each distinct
    role is read once for its name (roleDefinitions, api-version 2022-04-01); a role that does not
    exist leaves roleName null and is not a failed read. A -Scope at a resource group, or at a
    resource in one, reads its subscription's two lists and that resource group's assignment list,
    and keeps the delegations at the subscription and at that resource group; a -Scope at a
    management group or the root scope reads no delegation, since a delegation is made at a
    subscription or a resource group. Reader covers every read: its */read includes
    Microsoft.ManagedServices/registrationAssignments/read and registrationDefinitions/read, and an
    identity without it is refused, so the subscription is named unread.

    When it read at least one delegation, the export writes ONE warning that gives how many, after
    the walk and before the bundle is written, so -WhatIf shows it too, and under a Stop warning
    preference the export stops at that warning, before it writes the bundle. The generated
    README.md lists them, with their count, in a section "Azure Lighthouse delegations (access from
    another tenant)", directly after "Groups using PIM for Groups in a restricted management unit":
    each by scope, managing tenant, offer, how many authorizations and eligible authorizations it
    holds, and its roles, never a principal -- or the statement that none was read. A read that fails
    is never left unnamed: each scope of a subscription whose delegations could not be read is named
    in IncompleteReads as 'lighthouseDelegations at <scope>' and has no row in the file; a role whose
    name could not be read, other than one that does not exist, is named as 'lighthouseDelegations
    role <id>', and its roleName is null wherever it appears; and a walk that could not start, or a
    subscription listing that failed, is named as 'lighthouseDelegations at <all Azure scopes: scope
    enumeration failed>' or 'lighthouseDelegations at <subscriptions: the listing failed>'. A
    management group listing that failed adds nothing here, since no delegation is made at a
    management group. Each such entry makes the bundle partial: the InventoryPartial message names
    them in a clause of its own, with the causes of the reads (see the IncompleteReads paragraph
    below), and README.md lists them under "What this export could not read". A read of a
    subscription or a role that failed also writes a warning of its own.

    SUBSCRIPTIONS OF ANOTHER TENANT. The Azure walk reads only the subscriptions whose home tenant is
    the tenant the session's Microsoft Graph token was issued for -- the tenantId of inventory.json --
    judged by the tenantId Azure Resource Manager returns for each listed subscription, with no request
    of its own. A subscription listed for the session whose home tenant is another tenant -- a customer
    subscription delegated to this tenant through Azure Lighthouse, for example -- is not read: no role
    assignment, role management policy, PIM eligibility or Azure Lighthouse delegation of it is in the
    bundle, and scopeHierarchy.json does not list it. This is a deliberate selection, and it makes no
    bundle partial. The export writes ONE warning that names them, after the walk and before the bundle
    is written, so -WhatIf shows it too, and under a Stop warning preference the export stops at that
    warning, before it writes the bundle. README.md lists them under "Subscriptions delegated from
    another tenant (not read)", directly after "Azure Lighthouse delegations (access from another
    tenant)". A -Scope in such a subscription is refused the same way: one read of the subscription
    decides it, and nothing is read at the scope. A -Scope at a management group or the root scope,
    spelled as a structure document may spell it, is not in a subscription and is read as before. A
    subscription whose home tenant could not be read -- its read failed, it gave no tenantId, or the
    session's token names no tenant ID -- is not walked either: it is named in IncompleteReads as
    'subscriptionHomeTenant at <scope>' and in a clause of the InventoryPartial message with its
    causes, and the scope tree writes one warning that names them. So is a -Scope that cannot be
    resolved, a raw -Scope that does not start with '/', for example: nothing is read at it, and it is
    named 'subscriptionHomeTenant at <the scope as given>', with a cause that gives the resolver's
    message. So is a -Scope spelled so that a request would not reach it as written, a management
    group path included: one that breaks a scope spelling rule a structure document must keep, such as
    a '.' or '..' segment or a trailing '/' (about_Omnicit.EntraRBAC lists every rule under RENAMES,
    MAIL ALIASES AND SCOPE SPELLING). The request for such a scope could reach another path than its
    text -- one in another subscription, for example -- so nothing is resolved or read for it, and it
    is named the same way, with a cause that names the rules it breaks; write it without them.
    Invoke-OERStructure refuses a role assignment or a role management policy at a scope in a
    subscription of another tenant (SubscriptionTenantMismatch).

    WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED. A scope's policy list carries the policies of
    roles nobody uses or has changed there -- 963 of 967 on the one subscription measured -- so without
    -AllRolePolicies the RoleManagementPolicies section keeps a role's policy at a scope only when the
    role has an active role assignment or a PIM eligibility EXACTLY at that scope, or the policy has
    been changed. An assignment or an eligibility at a management group above the scope, or at a
    resource group below it, does not keep it. A policy counts as changed when the policy object the
    list returns for it carries a non-empty lastModifiedDateTime, or a lastModifiedBy with a non-empty
    id or displayName: measured on one subscription, every untouched policy carried no date and an
    empty lastModifiedBy, and every changed one a date and a display name. The policies are still read
    with the one paged policy list per scope, and nothing is requested per policy. The selection adds
    one paged role assignment list per scope (atScope(): the assignments at or above it), read just
    before that policy list, and uses the eligibility read described above, which the export makes for
    azurePimEligibility.json anyway. A policy that cannot be judged is kept, never dropped, and its
    scope is named in IncompleteReads (below): one not kept by a use or a change whose list row
    carries no policy object or no role definition id, or whose scope's role assignment read or
    eligibility read failed. A failed role assignment read writes one warning ('Could not read the
    role assignments at scope ...') and costs only the selection: the scope is still read. A failed
    policy list skips the scope exactly as before. -AllRolePolicies exports every policy at every
    scope the walk reads, with the call earlier versions made. Invoke-OERStructure reads and writes
    only the policies a document declares, so a policy the export leaves out stays as it is when the
    document, or a proposal built from it, is applied.

    ROLE ASSIGNMENTS AT THE ROOT SCOPE. A role assignment at the Azure root scope '/', above every
    management group and subscription in the tenant, is elevated access: a finding to review, which
    Invoke-OERStructure never creates or removes. inventory.json and roleAssignments.json never carry
    one. The read at each management group and subscription returns it as inherited, and
    Get-OERInventory leaves it out of every scope's read (the Get-OERInventory help describes the
    rule). When the walk finds any, the export writes ONE warning for the whole export that names
    each such assignment once, by role and principal and, when it is known, the principal type. It
    writes it after the walk and before the bundle is written, so -WhatIf shows it too. The
    generated README.md lists them, with their count, in a section "Role assignments at the root
    scope (elevated access)", directly after "Members and owners left out as PIM for Groups access",
    or says that none was read. Leaving them out of the export changes nothing in the tenant. Under a
    Stop warning preference (-WarningAction Stop, or $WarningPreference set to 'Stop') the export
    stops at that warning, before it writes the bundle. Any other warning of a scope's read is
    written after that read. An operator's -WarningVariable also collects the warnings of the
    per-scope reads -- Get-OERInventory's root-scope warning, its warning on role assignments whose
    principal the directory did not return, and the warning on role assignments at a scope no document
    can declare, once per scope, and any other per-scope warning twice -- while the display shows each
    other per-scope warning once, and the root-scope assignments, the assignments whose principal the
    directory did not return and the assignments at a scope no document can declare only in the
    export's own warnings.

    NAMES THAT TWO OR MORE OBJECTS SHARE. Microsoft Entra ID does not keep display names unique, and
    the apply engine refuses a name that more than one live object answers to, so inventory.json and
    the per-area files leave out every object whose name another object of its kind shares, compared
    without regard to letter case -- all of them (the Get-OERInventory help describes the rule).
    Groups are counted over every group in the tenant, the roster's unfiltered listing, so a security
    group that shares its name with a Microsoft 365 group or a distribution group is left out too;
    when the roster could not be read, they are counted among the security-enabled groups the export
    reads. Whether a group named as the principal of a role assignment or a directory role assignment
    is written by its display name or by its object id is decided over an index of every group's
    display name, which the export builds once for the whole export -- from the roster when it was
    read, otherwise with one listing of every group -- and never once per Azure scope. The export
    writes ONE warning that gives how many names were left out and how many objects carry them in
    all. It writes it before the bundle is written, so -WhatIf shows it too, and under a
    Stop warning preference (-WarningAction Stop, or $WarningPreference set to 'Stop') the export
    stops at that warning, before it writes the bundle. The generated README.md lists each name, with
    how many objects carry it and its section, in a section "Names two or more objects share",
    directly after "Role assignments at the root scope (elevated access)", or says that no two objects
    share a name. The names stay in IncompleteReads as well. Leaving them out changes nothing in the
    tenant.

    ROLE ASSIGNMENTS WHOSE PRINCIPAL THE DIRECTORY DID NOT RETURN. A role assignment can name a
    principal that Microsoft Entra ID does not return: one that was deleted, or one the directory
    cannot read. Such an assignment stays in inventory.json and roleAssignments.json, written by the
    principal's object id with principalStatus Deleted, when the principal is among the directory's
    deleted items, or Unresolved, when it is found neither there nor in the directory or its deleted
    items could not be read (the Get-OERInventory help describes the rule). Invoke-OERStructure never
    creates such an assignment, and removing its entry lets -Prune remove it, like any undeclared
    assignment, at a scope the document still declares. A principal is looked for among the deleted
    items once for the whole export when that read succeeds, however many Azure scopes read the
    assignment; a read that fails is not kept, and is sent again by the next scope that needs it. The
    export writes ONE warning that gives how many such assignments it read, each counted once. It
    writes it after the walk and before the bundle is written, so -WhatIf shows it too, and under a
    Stop warning preference the export stops at that warning, before it writes the bundle. The
    generated README.md lists them, with their count, in a section "Role assignments whose principal
    the directory did not return", directly after "Names two or more objects share": each by role,
    scope, principal and, when it is known, the principal type, with its status and the reason in
    words -- or that the reason is not known, where the deleted items read failed -- or the statement
    that none was found. A principal whose lookup failed is written by its object id with no
    principalStatus and is named in IncompleteReads (below), and so is one whose deleted items read
    failed, which is written as Unresolved. The Azure scope is never skipped for either. An assignment
    that several Azure scopes read is written once: where one scope's lookup of its principal failed
    and another scope's lookup did not return it, it is written with principalStatus, and the failed
    lookup is not named. A scope that the export skips after reading it adds none of its assignments
    to this warning, this README section or IncompleteReads, nor to the warning and README section of
    the next paragraph, since none of its rows is written.

    ROLE ASSIGNMENTS AT A SCOPE NO DOCUMENT CAN DECLARE. Azure Resource Manager can return a role
    assignment at a scope whose spelling the validator refuses as an Error, for example the scope of a
    resource whose name holds a '#' or a '%' (about_Omnicit.EntraRBAC lists the scope spelling rules
    under RENAMES, MAIL ALIASES AND SCOPE SPELLING). No document can declare such a scope, and a
    document that carried one would be refused as a whole, so inventory.json and roleAssignments.json
    never carry one: Get-OERInventory leaves it out of every scope's read (the Get-OERInventory help
    describes the rule). Invoke-OERStructure never creates a role assignment at such a scope, and
    never removes one, since it prunes only at a scope a document declares. A role assignment at the
    root scope whose spelling is refused too is named only as a root scope assignment. The export
    writes ONE warning that gives how many such assignments it read, each counted once however many
    Azure scopes read it. It writes it after the walk and before the bundle is written, so -WhatIf
    shows it too, and under a Stop warning preference the export stops at that warning, before it
    writes the bundle. The generated README.md lists them, with their count, in a section "Role
    assignments at a scope no document can declare", directly after "Role assignments whose principal
    the directory did not return": each by role, scope, principal and, when it is known, the principal
    type, with the rules its scope breaks in words -- or the statement that none was read. Such an
    assignment is left out, not unread: it is not named in IncompleteReads, and it makes no bundle
    partial. Leaving them out of the export changes nothing in the tenant.

    GROUPS USING PIM FOR GROUPS IN A RESTRICTED MANAGEMENT UNIT. Microsoft Learn states that
    Privileged Identity Management does not support a group in a restricted management administrative
    unit, so a group with PIM eligibility or a pimPolicy block that is a member of one is a finding to
    review. The group stays in inventory.json and Invoke-OERStructure still sends the PIM settings and
    eligibility a document declares for it; what Microsoft Graph answers to those writes has not been
    measured. When both Groups and AdministrativeUnits are included, the export finds each group that
    inventory.json writes with a non-empty eligibility or a pimPolicy and that a unit lists by the
    group's object id (compared without regard to letter case), where the unit's restricted is true and
    its members were read, with no request of its own. A unit whose members could not be read is named
    in IncompleteReads and lists nobody here, and a unit left out of the document because another unit
    shares its name is not checked here: it is named in IncompleteReads and under "Names two or more
    objects share" in README.md. The export writes ONE warning that gives how many such groups it found,
    after the reads and before the bundle is written, so -WhatIf shows it too, and under a Stop warning
    preference the export stops at that warning, before it writes the bundle. The generated README.md
    lists them in a section "Groups using PIM for Groups in a restricted management unit", directly
    after "Role assignments at a scope no document can declare": each group and its units by display
    name, never an id -- or the statement that none was found. Nothing is left out of the export, and
    listing a group changes nothing in the tenant.

    SERVICE PRINCIPAL ACCESS. With -IncludeServicePrincipalAccess the export also writes
    servicePrincipalAccess.json: read-only context on the app roles and delegated permission grants of
    the tenant's service principals and on the owners of its service principals and app
    registrations, which inventory.json does not model. The file is one
    JSON object with four parts, in this order: applicationPermissions, one row per app role a
    service principal holds on a resource -- application permissions among them -- read from the
    client side (servicePrincipalId, servicePrincipalDisplayName, resourceId, resourceDisplayName,
    appRoleId and appRoleValue, which is null for a role the resource does not declare (the default
    access role, for one) or declares without a value, and for a resource the service principal list
    did not return, whose resourceDisplayName is then the assignment's own, else null);
    delegatedPermissionGrants, one row per delegated permission grant (clientId, clientDisplayName,
    resourceId, resourceDisplayName, consentType, principalId, principalDisplayName and
    principalUserPrincipalName -- the user's display name and user principal name, all three null
    for AllPrincipals and the two names null for a user the directory did not return -- and scope);
    applicationOwners, one row per owner of an app registration (applicationId, appId,
    applicationDisplayName, ownerId, ownerType, ownerDisplayName and ownerUserPrincipalName);
    and servicePrincipalOwners, one row per owner of a service principal (servicePrincipalId,
    servicePrincipalDisplayName and the same four owner fields). Every blank value is null, and each
    part is sorted, so two exports of an unchanged tenant write the same file. The file is read-only
    context and never applied: inventory.json and schema.json do not carry it, no apply cmdlet reads
    it back, and Invoke-OERStructure never grants, revokes or changes any of it. The read costs one
    request per page of each of the three lists (the service principals with their app role
    assignments, the service principals with their owners, and the app registrations with their
    owners) and of the grants, one directoryObjects/getByIds per 1,000 users named in grants, and one
    extra paged read per object with 20 or more expanded entries, since Microsoft Graph documents at
    most 20 for an expanded directory relationship, or with an expanded entry that lacks the id its
    row needs, which Microsoft Graph was measured to return (an app role assignment without its
    resource id); measured 29 requests for a tenant of 1,129 service principals and 67 app
    registrations. It is read after the Azure walk and before the bundle is written, under -WhatIf
    too, where Files lists the file and nothing is written. A part is read whole or not at all: a
    part that could not be read -- a refused or failed request, an object Microsoft Graph returned
    without its expanded collection, a service principal listed without its app roles, an entry that
    even its object's full read returns without the id its row needs, or, for the grants, a user
    lookup that failed or the service principal list they are named through -- is written as null,
    never [], and is named in IncompleteReads as
    'servicePrincipalAccess/<part>' (see below), in a clause of the InventoryPartial message with its
    causes, and in README.md under "What this export could not read". A part that could not be read
    never stops another, except that the grants are not read when the service principal list they
    are named through was not; the export writes no warning for any of it. README.md gives each
    part's row count in a section "Service principal access (read-only)", directly after
    "Subscriptions delegated from another tenant (not read)". Directory.Read.All, which the export
    already requires, covers every read. Without the switch none of it is read or written, and
    README.md and rbac-architect-prompt.md say nothing of it.

    Entra ID coverage is reported the same way. IncompleteReads carries, first, one entry for the
    Groups read when it left anything unread, then one entry per partial report from
    Get-OERInventory, which reads the other Entra ID sections. Each entry names the affected
    section/displayName/key triples -- so a single read that lost three collections reports one
    entry listing all three, not three entries -- and the entry groupsRoster is added when the group
    roster could not be read. A section whose whole list could not be read appears in those entries
    by its own name alone (groups also when the group read stops on an unforeseen error, with the
    warning 'Could not read groups: ...'), and is written as an empty array that does not mean the
    tenant has none; the entry groupsRoster likewise means groupsRoster.json is empty only because
    the roster read failed. After every Entra ID entry, IncompleteReads carries one entry per role
    assignment principal that could not be read (see ROLE ASSIGNMENTS WHOSE PRINCIPAL THE DIRECTORY
    DID NOT RETURN above), each once however many Azure scopes read the assignment, reading
    'roleAssignments/<role> -> <principal id> @ <scope>' followed by '/principal' when the principal
    could not be looked up, or '/principalStatus' when only its deleted items read failed. After
    those entries, IncompleteReads carries one entry per
    Azure scope where at least one role management policy could not be judged (see WHICH AZURE ROLE
    MANAGEMENT POLICIES ARE EXPORTED above), reading 'roleManagementPolicies/role selection at' and
    the scope in its canonical form -- for a subscription,
    'roleManagementPolicies/role selection at /subscriptions/<id>'. Such an entry names no unread
    collection: every policy at that scope that could not be judged was kept, none of them left out
    -- where the scope's role assignment read or eligibility read failed, that is every policy of a
    role neither used nor changed there -- so roleManagementPolicies.json may hold policies of roles
    that are neither used nor changed at that scope. It does not mean every policy at the scope was
    kept: when only one row could not be judged, the other unused, unchanged policies there are still
    left out. After those, IncompleteReads carries one entry per subscription the Azure walk did not
    enter since whether it belongs to this tenant could not be read (see SUBSCRIPTIONS OF ANOTHER
    TENANT above), reading 'subscriptionHomeTenant at <scope>'. Then IncompleteReads carries
    the Azure Lighthouse entries (see AZURE LIGHTHOUSE DELEGATIONS above): one 'lighthouseDelegations
    at <scope>' per scope of a subscription whose delegations could not be read, one
    'lighthouseDelegations role <id>' per role whose name could not be read, and one entry for a walk
    that could not start or a subscription listing that failed. Last of all, for an export run with
    -IncludeServicePrincipalAccess, IncompleteReads carries one entry per part of
    servicePrincipalAccess.json that could not be read (see SERVICE PRINCIPAL ACCESS above), reading
    'servicePrincipalAccess/' and the part's name, for example 'servicePrincipalAccess/applicationOwners'.
    The Count of IncompleteReads is
    therefore one for the Groups read when it left anything unread, plus the number of partial reports
    from Get-OERInventory, plus one when the group roster could not be read, plus one per role
    assignment principal that could not be read, plus one per Azure scope where a role management
    policy could not be judged, plus one per subscription whose home tenant could not be read, plus one
    per Azure Lighthouse entry, plus one per service principal access part that could not be read, and
    not the number of unread collections; read the entries for that.
    The same non-terminating InventoryPartial error is raised here when IncompleteReads, SkippedScopes
    or SkippedEligibilityScopes is non-empty, and its message gives the causes of the unread group
    reads (Get-OERInventory's own InventoryPartial gives those of the other sections). The part of that
    message that counts partial Entra ID read entries counts the Entra ID entries only; the role
    assignment principals that could not be read have a clause of their own, which names each of them
    and gives the causes, and so have the Azure scopes where policies could not be judged, the
    subscriptions whose home tenant could not be read, whose clause names each entry and gives the
    causes, the Azure Lighthouse reads that failed, whose clause names each entry and gives the
    causes, and, last, the service principal access parts that could not be read, whose clause names
    each part and gives the causes. A
    members, scopedRoles, resources or resourceRoles collection that
    could not be read, or that has an entry the export could name by nothing the apply engine
    accepts, is NOT written into inventory.json as an empty one or with an empty name: its key is an
    explicit null, which the apply engine reads as "leave untouched" (so is the members key of a group
    that has members when neither its PIM for Groups assignments nor its eligibility could be read, as
    described above). Do not hand-edit that null to
    [] -- under Invoke-OERStructure -Prune an empty declared collection deletes every live member,
    binding or resource. A path ending in scopedRoles/principalType names no such null: the unit's
    scopedRoles is written, and some or all of its rows carry no principalType, since the type of
    their principals could not be looked up (the Get-OERInventory help describes the rule).
    Any other collection IncompleteReads names is left out of the document or
    written only as far as it was read, as the Get-OERInventory help describes; Invoke-OERStructure
    never removes a catalog, access package or assignment policy that is absent from the document.

    The bundle says so itself. The generated README.md carries a section named "What this export
    could not read": one bullet per IncompleteReads, SkippedScopes and SkippedEligibilityScopes
    entry -- among the IncompleteReads entries, those of a role assignment principal that could not be
    read, those of an Azure scope where role management policies could not be judged, those of a
    subscription whose home tenant could not be read, those of an Azure Lighthouse read that failed
    and those of a service principal access part that could not be read each under a label of its
    own -- or the statement that nothing
    was left unread, so whoever receives the bundle (an LLM, say) can tell a collection that was not
    read from one that is empty. The lists go into README.md only, never into inventory.json or any
    other file that is validated or applied.

    inventory.json carries the top-level tenantId that Get-OERInventory writes -- the tenant ID the
    session's Microsoft Graph token was issued for -- so Invoke-OERStructure applies it only in that
    tenant and refuses it elsewhere with DocumentTenantMismatch; the Get-OERInventory help describes
    the rule.

    WHERE THE FILES LAND: nothing is ever written directly into -OutputPath. -OutputPath is only the
    PARENT directory; every file goes into a new timestamped subfolder beneath it named
    oer-inventory-<tenant>-<yyyyMMdd-HHmmss>, so inventory.json is at
    <OutputPath>/oer-inventory-<tenant>-<stamp>/inventory.json and NOT at <OutputPath>/inventory.json.
    <tenant> is the tenant as the session names it (an ID, or the domain given to -TenantId), which can
    differ from the tenantId inside inventory.json. Because the stamp is generated per run, the only
    reliable way to address the bundle afterwards is the BundlePath property of the returned
    Omnicit.EntraRBAC.InventoryBundle object -- an absolute path, populated under -WhatIf too (as the
    planned location). Capture the returned object and join onto its BundlePath rather than guessing
    the folder name; see the Test-OERStructure example below.

    The full export to LLM to Test-OERStructure to Invoke-OERStructure walkthrough is documented in
    the repository at docs/inventory-to-llm/README.md, and a worked apply document is kept in the
    repository at docs/examples/example-structure.json. Neither ships inside the installed module,
    so clone or browse the repository to read them.

    .PARAMETER OutputPath
    The PARENT directory under which the timestamped bundle folder is created; the bundle files are
    written into that subfolder, never directly into this directory. Defaults to the current
    directory. Use the returned object's BundlePath to address the files afterwards.

    .PARAMETER Include
    Which sections to gather from the tenant. Defaults to the Entra sections (Groups,
    AdministrativeUnits, Catalogs, AccessPackages, AccessReviews, DirectoryRoleManagementPolicies,
    DirectoryRoleAssignments) plus RoleAssignments. The two DirectoryRole* sections are Graph-only
    and never acquire an ARM token by themselves. RoleManagementPolicies, the Azure role management
    policies, is not in the default: named here, it exports the policies of the roles in use or
    changed at each scope the walk reads (see WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED
    above), and every policy with -AllRolePolicies.

    .PARAMETER AllGroupsDetailed
    Read every group the Groups section covers in full, as earlier versions did, and keep each in
    full detail in inventory.json, not just the RBAC-relevant ones. Without it the export decides
    first which groups are relevant and reads only those in full (see HOW THE GROUPS ARE READ
    above). With it, groupsRoster.json carries the member count of every security group the read
    covers, null only for one whose members could not be read, one whose members are written as null
    for the PIM for Groups reason (see MEMBERS AND OWNERS THAT PIM FOR GROUPS HOLDS), or one that
    shares its name with another.
    That section is security-enabled-scoped, so this switch does not reach a distribution group or a
    Microsoft 365 group whose securityEnabled is false -- neither is in inventory.json at any detail
    level. Use Get-OERInventory -GroupFilter to widen the scope itself; groupsRoster.json already
    lists every group in the tenant unfiltered.

    .PARAMETER IncludeSyncedGroups
    Also keep, in full detail in inventory.json, every security group synchronized from on-premises
    Active Directory (onPremisesSynced: true), and read its members and owners for that. Such a
    group is never RBAC-relevant by the default criteria -- it cannot be role-assignable or managed
    in PIM for Groups -- so without this switch it costs the two requests that decide it is not
    relevant, appears only in groupsRoster.json, and has a null memberCount there. It is managed
    on-premises: Invoke-OERStructure writes nothing to it, and its onPremisesSynced key is
    information only. With -AllGroupsDetailed every group is read and kept already and this switch
    changes nothing.

    .PARAMETER AllDirectoryRolePolicies
    For the DirectoryRoleManagementPolicies section, export the policy of every Microsoft Entra
    directory role, instead of only the roles that have at least one row in the tenant-scope
    eligibility or assignment schedules (the default). Forwarded to the internal Get-OERInventory
    call; has no effect unless -Include names DirectoryRoleManagementPolicies.

    .PARAMETER AllRolePolicies
    For the RoleManagementPolicies section, export the policy of every Azure role at every scope the
    walk reads, as earlier versions did, instead of only the policies of roles with an active role
    assignment or a PIM eligibility exactly at that scope, or whose policy has been changed (the
    default; see WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED above). The export then reads each
    scope with the call earlier versions made: no role assignment list is read for the selection, and
    no scope is named in IncompleteReads as kept without being judged. Has no effect unless -Include
    names RoleManagementPolicies; the DirectoryRoleManagementPolicies section has its own switch,
    -AllDirectoryRolePolicies.

    .PARAMETER IncludeServicePrincipalAccess
    Also read the application permissions, delegated permission grants and owners of the tenant's
    service principals and app registrations, and write them to servicePrincipalAccess.json as
    read-only context (see SERVICE PRINCIPAL ACCESS above). The read adds one request per page of each
    of three lists and of the grants, one directoryObjects/getByIds per 1,000 users named in grants,
    and one paged read per object with 20 or more expanded entries or with an expanded entry that
    lacks the id its row needs. A part that could not be read is written as null and named in
    IncompleteReads. It reads Microsoft Graph only, whatever -Include names, and needs no ARM token
    of its own. Without this switch none of it is read and no such file is written.

    .PARAMETER ManagementGroup
    Narrow the Azure scope walk to a single management group branch identified by name or id. An empty
    or white space value is refused at parameter binding.

    .PARAMETER Scope
    Narrow the Azure scope walk to a single raw ARM scope string (e.g. a subscription id path). A
    scope in a subscription is read only when that subscription's home tenant is the tenant the
    session's Microsoft Graph token was issued for, which one read of the subscription decides. A
    scope in a subscription of another tenant is not read: the warning and README.md name it (see
    SUBSCRIPTIONS OF ANOTHER TENANT above). One whose subscription's home tenant cannot be told -- the
    read failed, the subscription gave no tenantId, the session's token names no tenant ID (then the
    subscription is not read), or the scope cannot be resolved -- is not read either, and is named in
    IncompleteReads, so the bundle is partial. So is a scope spelled so that a request would not reach
    it as written, a management group path included: one that breaks a scope spelling rule a structure
    document must keep, such as a '.' or '..' segment or a trailing '/' (about_Omnicit.EntraRBAC lists
    every rule); nothing is resolved or read for it. Any other scope at a management group or the root
    scope lies in no subscription and is read as before. An empty or white space value is refused at
    parameter binding.

    .PARAMETER Force
    Overwrite an existing bundle folder of the same name. Without this switch an existing folder of the
    same name is left in place and its contents are merged with the new files. Use -WhatIf to preview
    the bundle plan without touching disk.

    .PARAMETER TenantId
    Optional tenant id or domain name forwarded to Initialize-OERAuth for explicit tenant targeting.
    The tenantId written into inventory.json is the tenant ID the session's Microsoft Graph token was
    issued for, not this value.

    .PARAMETER GroupFilter
    An OData filter that narrows the groups inventory.json is read from, for a tenant with very many
    groups. It is ANDed to the security-enabled filter inside parentheses, so the groups are listed
    with 'securityEnabled eq true and (your filter)', and it only narrows: the export also keeps only
    the groups the read itself shows as securityEnabled (a boolean true), so a filter that closes the
    parenthesis, for example 'x eq 1) or (securityEnabled eq false', cannot widen inventory.json to a
    group that is not security-enabled. Such a group is left out, with one warning that names how
    many were left out. With -AllGroupsDetailed a group the filter widens to is read in full before
    it is left out; the default read reads nothing of it. The expression is yours: it is sent as
    typed and never escaped, so double a single quote inside a quoted value yourself ('O''Brien'). It
    applies to the Groups section only: it changes nothing when -Include leaves Groups out, and
    groupsRoster.json is not filtered by it and still lists every group in the tenant, with a null
    memberCount for a security group the filter left out, since that group was not read. An empty or
    white space value is refused at binding.

    .EXAMPLE
    Export-OERInventory
    Reads the tenant and writes a bundle under the current directory.

    .EXAMPLE
    Export-OERInventory -IncludeServicePrincipalAccess
    Reads the tenant as the example above does, and also writes servicePrincipalAccess.json: the
    application permissions, delegated permission grants and owners of the tenant's service principals
    and app registrations, as read-only context.

    .EXAMPLE
    Export-OERInventory -GroupFilter "startswith(displayName,'role_')"
    Reads inventory.json's groups from the security-enabled groups whose display name starts with
    role_ only, so far fewer groups are read in a tenant with very many of them. groupsRoster.json
    still lists every group in the tenant.

    .EXAMPLE
    Export-OERInventory -OutputPath C:\Temp -Include Groups,AdministrativeUnits,Catalogs,AccessPackages,RoleAssignments,RoleManagementPolicies
    Reads the full posture (including tenant-wide Azure role assignments, and the PIM policies of the
    Azure roles in use or changed at each scope) into a bundle under
    C:\Temp\oer-inventory-<tenant>-<stamp>\, not into C:\Temp itself.

    .EXAMPLE
    Export-OERInventory -Include RoleAssignments,RoleManagementPolicies -AllRolePolicies
    Reads the Azure role assignments and the role management policy of every Azure role at every
    scope the walk reads, as earlier versions did. Without -AllRolePolicies, roleManagementPolicies.json
    holds only the policies of roles with an active role assignment or a PIM eligibility exactly at
    the policy's scope, or whose policy has been changed, and every policy that could not be judged.

    .EXAMPLE
    $Bundle = Export-OERInventory -OutputPath C:\Temp
    Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json')

    Captures the bundle summary and validates the exported inventory through the apply schema. Joining
    onto BundlePath is the supported way to reach the file: passing C:\Temp\inventory.json instead
    fails with "Structure document not found", because the export never writes into -OutputPath itself.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$OutputPath = '.',
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments'),
        [switch]$AllGroupsDetailed,
        [switch]$IncludeSyncedGroups,
        [switch]$AllDirectoryRolePolicies,
        # A switch takes no position, so declaring it here leaves every positional parameter where it
        # was (see the -GroupFilter comment below).
        [switch]$AllRolePolicies,
        # Sprint 11 step 8. A switch, so it takes no position either.
        [switch]$IncludeServicePrincipalAccess,
        # Sprint 11 step 10 (BL-155): a -ManagementGroup or -Scope of white space only is refused here, at
        # binding, as an empty one is -- the BL-96 pattern of -GroupFilter below, for the same reasons. Before
        # this, '   ' passed the tests of the Azure walk (`if ($Scope)` is true for it) and was handed to the
        # scope tree as a scope. Declared ABOVE [ValidateNotNullOrEmpty()] on purpose: validation attributes
        # run in reverse declaration order (measured), so an empty or null value still reads the
        # NotNullOrEmpty message and white space reads this one. Neither parameter moves: positional binding
        # follows declaration order. No call inside the module passes either parameter an empty or blank value:
        # the per-scope Get-OERInventory calls below pass -Scope only with a scope the tree listed, which is
        # added to the tree only when it is not empty.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The ManagementGroup consists only of white space. Pass a management group name or ID, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementGroup,
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The Scope consists only of white space. Pass an Azure Resource Manager scope, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,
        [switch]$Force,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        # Declared LAST on purpose, as New-OERConfiguration's -Environment is. Positional binding
        # follows DECLARATION order, so a parameter inserted above -ManagementGroup, -Scope or
        # -TenantId would silently change what an existing positional argument binds to.
        # A filter of white space only is refused here, at binding, as an empty one is (the same
        # BL-96 pattern as New-OERConfiguration's -TenantId). The module supports PowerShell 7.2, which
        # has no [ValidateNotNullOrWhiteSpace()] (7.4+), so the same test runs as a script. Declared
        # ABOVE [ValidateNotNullOrEmpty()] on purpose: validation attributes run in reverse
        # declaration order (measured), so an empty or null value still reads the NotNullOrEmpty
        # message and white space reads this one.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupFilter
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        # Only the Azure sections need an ARM token. Acquiring one unconditionally also forced a
        # Graph re-authentication for app-only sessions: this cmdlet passes no -AuthMethod, so when
        # no ARM token is cached the passive-reuse check fails and the identity check then compares
        # the cached AuthMethod against the 'Interactive' default -- turning a pure-Entra export in a
        # ClientSecret session into an interactive sign-in prompt.
        if (@($Include | Where-Object { $_ -in @('RoleAssignments', 'RoleManagementPolicies') }).Count -gt 0) {
            $AuthParams.IncludeARM = $true
        }
        Initialize-OERAuth @AuthParams
        # BL-88 (A14): the tenant inventory.json names, captured here under the session this command
        # signed in under. It is this cmdlet's own capture, never the tenantId of the inventory
        # Get-OERInventory returns, so the document is assembled with the one value in both calls.
        $DocumentTenantId = Get-OERInventoryTenantId
    }
    process {
        # --- Gather the Entra ID sections (names only, for portability) ---
        # The Groups section is read by the group reader directly, not through Get-OERInventory, so
        # the export can ask it to decide RBAC relevance FIRST (A13): without -AllGroupsDetailed a
        # group costs two requests (its PIM eligibility and the PIM-in-use criterion) before anything
        # else is read, and only a group that is relevant -- or whose relevance could not be read --
        # has its members, owners and PIM policy read. -AllGroupsDetailed reads every group in full,
        # as before. The 'securityEnabled eq true' filter is the scope Get-OERInventory applies by
        # default, so inventory.json covers the same groups it always did. -ExcludeSharedName leaves
        # out groups that share a name, the rule Get-OERInventory applies to its own groups section.
        # The reader never writes an error record: what it could not read comes back in its Unread
        # and Causes lists, folded into IncompleteReads and the partial message below. It shows
        # progress under this cmdlet's own activity while it reads ('Group n of N') and ends it when
        # the read is done, also when it stops on an error, before the Azure scope walk starts its own.
        #
        # -GroupFilter narrows that scope and never widens it. It is ANDed to the security-enabled
        # filter inside parentheses, and it is the operator's OWN OData expression, so it is sent as
        # typed and never escaped through ConvertTo-OERODataFilterValue (that helper escapes a VALUE
        # for a quoted literal, and applied to a whole expression it would break the expression);
        # Get-OERGroup -Filter percent-encodes the whole expression once. The parentheses alone are
        # not the guard, since an expression can close them ('x eq 1) or (securityEnabled eq false'
        # lists every group the second operand matches). The guard is -SecurityEnabledOnly, which
        # keeps only the groups the read itself shows as securityEnabled, whatever the filter listed.
        $GroupRead = $null
        # The group roster is read FIRST (BL-131), before the group reader, since it is the one list of
        # every group in the tenant, of every type, and the reader counts the names groups share over
        # it: Get-OERGroupNameIndex builds the index from it with no request of its own, so a security
        # group that shares its name with a Microsoft 365 group or a distribution group is left out of
        # inventory.json and reported exactly like two security groups that share it. Its rows are still
        # built further down, where the member counts are known, and a failed read is still named
        # groupsRoster in IncompleteReads at the place it always was ($RosterUnread carries it there);
        # the warning is written here, before the reader, and so still before the bundle's
        # ShouldProcess. When the roster could not be read the reader gets no index and counts the names
        # over its own listing, as before.
        $RosterGroups = @()
        $RosterUnread = $false
        $GroupNameIndex = $null
        if ($Include -contains 'Groups') {
            try {
                # -All, NOT -Filter 'securityEnabled eq true'. The roster is the one file in the
                # bundle that claims to be complete, and that filter made the claim false without
                # saying so: measured against a real tenant, 106 groups read back as 100 -- the 6
                # missing were 5 Microsoft 365 groups with securityEnabled false and 1 distribution
                # group. An operator comparing the roster against the portal found groups simply
                # absent, with nothing in the bundle to explain it. inventory.json keeps the
                # security-enabled scope on purpose (it is the apply document, and widening it
                # widens what -Prune deletes); the roster is read-only context and does not.
                $RosterGroups = @(Get-OERGroup -All -ErrorAction Stop)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'GroupNotFound*') {
                    Write-Warning "Could not read the group roster: $($PSItem.Exception.Message)"
                    $RosterUnread = $true
                }
            }
            if (-not $RosterUnread) { $GroupNameIndex = Get-OERGroupNameIndex -Group $RosterGroups }

            $GroupReadParams = @{
                Filter              = if ($GroupFilter) { "securityEnabled eq true and ($GroupFilter)" } else { 'securityEnabled eq true' }
                IncludeId           = $true
                ExcludeSharedName   = $true
                SecurityEnabledOnly = $true
                ProgressActivity    = 'Export-OERInventory'
            }
            if (-not $AllGroupsDetailed) {
                $GroupReadParams.RelevantOnly = $true
                if ($IncludeSyncedGroups) { $GroupReadParams.IncludeSyncedGroups = $true }
            }
            if ($null -ne $GroupNameIndex) { $GroupReadParams.GroupNameIndex = $GroupNameIndex }
            # The reader catches what it expects (a failed list read, a failed collection read) and
            # names it in Unread and Causes. This catch is for the rest: an error nothing in the
            # reader catches ends the read, and the reader's progress try/finally unwinds it -- a
            # statement-terminating error as well as a throw -- so the call returns NOTHING. A
            # $GroupRead of $null would be read below as zero groups with nothing unread, which is
            # a failed read stated as an empty fact. So the stop is reported as what it is, the
            # groups section unread, with the reader's own wording for a list that could not be read:
            # the warning stands before the bundle's ShouldProcess (the read comes first), the cause
            # reaches the InventoryPartial message, and the rest of the export carries on.
            try {
                $GroupRead = Get-OERInventoryGroup @GroupReadParams
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $GroupReadCause = "Could not read groups: $($PSItem.Exception.Message)"
                Write-Warning $GroupReadCause
                $GroupRead = [PSCustomObject]@{
                    Groups      = @()
                    Unread      = @('groups')
                    Causes      = @([PSCustomObject]@{ Cause = $GroupReadCause; Target = '' })
                    PimLeftOut  = @()
                    SharedNames = @()
                }
            }
        }
        # DirectoryRoleManagementPolicies and DirectoryRoleAssignments are Graph-only, same as the
        # other four: they are deliberately absent from the ARM-triggering check above, so naming
        # either one alone never acquires an ARM token.
        $EntraSections = @($Include | Where-Object { $_ -in @('AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments') })
        # Sprint 11 step 6 (R-2 of step 5): the export's run context. ONE object, held for the Entra ID
        # call below and the whole Azure walk after it -- every Get-OERInventory call this export makes,
        # the eligibility read and the role policy selection included -- and set back to $null as a plain
        # statement directly after the walk. It holds what one export shares across its Get-OERInventory
        # calls: for now the index of every group's display name (GroupNameIndex), which the group
        # principals of the role assignments are named through. When the roster was read, the index built
        # from it goes in at once, with no request; otherwise the first caller lists the groups once and
        # stores the index here, so an export lists them at most once and not once per Azure scope. A
        # module-scope object and not a parameter, since Get-OERInventory gets no new public parameter
        # (A9). Owner is this command's own invocation, the very object a frame of the call stack carries
        # (Lock-OERSignIn keys the sign-in latch on it the same way): Get-OERInventory uses the context
        # only while the Owner is on its call stack, so one that this export leaves behind when it is
        # stopped before the statement after the walk is ignored by every later call, an export's
        # included, which overwrites it here. There is deliberately NO try/finally around the region: a
        # statement-terminating error inside it must keep skipping only its own statement.
        #
        # Sprint 11 step 6 (BL-133, A18): three more members for the role assignment principals. The
        # per-scope calls keep every answer of the deleted items read that succeeded in PrincipalStatus (keyed
        # without regard to letter case), so a principal the directory did not return is read there once for
        # the whole export when that read succeeds; a read that fails is not kept, and the next scope that
        # needs it reads again. A principal whose lookup or deleted items read failed is named in
        # UnreadPrincipal, with its cause at the same index in UnreadPrincipalCause, instead of in the call's
        # own InventoryPartial, which the call's -ErrorAction Stop below would turn into a skip of the whole
        # scope. The local reference keeps both lists after the context is cleared, for IncompleteReads and
        # the partial message.
        #
        # Sprint 11 step 8 (A20, BL-152): one more member, SubscriptionTenant, the cache of what the export
        # learned about each subscription's home tenant (Get-OERSubscriptionHomeTenant -Cache, keyed on the
        # subscription id, without regard to letter case). The scope tree below fills it -- the facts the
        # subscription list gave, or its one read of the subscription of a -Scope -- and every per-scope
        # Get-OERInventory call checks the subscription of its scope against it before it reads there, so
        # that check, which a standalone Get-OERInventory makes with a request, costs the export none.
        $RunContext = [PSCustomObject]@{
            Owner                = $MyInvocation
            GroupNameIndex       = $GroupNameIndex
            PrincipalStatus      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            UnreadPrincipal      = [System.Collections.Generic.List[string]]::new()
            UnreadPrincipalCause = [System.Collections.Generic.List[object]]::new()
            SubscriptionTenant   = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        $script:_OERInventoryRunContext = $RunContext
        # The ids the roster member-count join below is keyed on come from the group reader alone:
        # it is asked for -IncludeId above, PURELY to key that join on object id instead of display
        # name (Entra permits duplicate group display names -- Add-OERGroupMember.ps1:43-45 -- so a
        # display-name join can attribute one group's member count to a different, same-named
        # group). Get-OERInventory below reads the other sections and is not asked for ids, since
        # nothing here joins on them. inventory.json staying id-free is a documented portability
        # property of the export (Get-OERInventory's own .DESCRIPTION), so the ids the reader
        # stamped are stripped back out below, before the canonical inventory and the per-area files
        # are assembled and written; the same strip also covers any other section that arrives with
        # an id.
        $InventoryReadErrors = $null
        $InventoryInformation = $null
        $Inv = if ($EntraSections.Count -gt 0) {
            # -ErrorAction Continue is PINNED here, not inherited, and deliberately not Stop.
            # Get-OERInventory now reports a collection it could not read as a non-terminating
            # InventoryPartial, and that must be folded into THIS cmdlet's single coverage signal
            # rather than aborting an otherwise usable bundle. Without the pin this call inherits
            # $ErrorActionPreference from the caller's scope, so under the very
            # Export-OERInventory -ErrorAction Stop that this cmdlet's own help tells operators to
            # adopt, the inner record would terminate HERE -- outside any try/catch, before a single
            # bundle file is written -- and the operator would get an exception and NO BUNDLE AT
            # ALL, instead of the documented "summary emitted first, then a loud error". Continue
            # keeps the record non-terminating while still delivering it to BOTH the caller's error
            # stream and $InventoryReadErrors; Export's own trailing Write-CmdletError is what
            # honours -ErrorAction Stop, and it runs after $Out has been emitted.
            #
            # -AllDirectoryRolePolicies is added to the splat only when the switch is actually set,
            # not forwarded unconditionally as -AllDirectoryRolePolicies:$AllDirectoryRolePolicies
            # would be: Get-OERInventory's own default behaviour (policy of only the in-use roles) is
            # what every OTHER -Include combination in this file's test suite already relies on, and
            # binding the parameter at all -- even to $false -- is observable to a caller's
            # -ParameterFilter, so adding it only when true keeps every existing call site untouched.
            #
            # BL-131: the names Get-OERInventory leaves out because two or more objects share them
            # arrive in its information record tagged Omnicit.EntraRBAC.SharedName, captured here and
            # not shown: -InformationAction SilentlyContinue keeps a caller's own information preference
            # off the call, and -InformationVariable still collects the record.
            $InvParams = @{
                Include             = $EntraSections
                ErrorAction         = 'Continue'
                ErrorVariable       = 'InventoryReadErrors'
                InformationAction   = 'SilentlyContinue'
                InformationVariable = 'InventoryInformation'
            }
            if ($AllDirectoryRolePolicies) { $InvParams.AllDirectoryRolePolicies = $true }
            Get-OERInventory @InvParams
        } else {
            ConvertTo-OERInventory -TenantId $DocumentTenantId
        }
        $IncompleteReads = [System.Collections.Generic.List[string]]::new()
        # The Groups read is reported FIRST, as ONE entry naming everything it could not read: the
        # same shape, and the same place, as the groups take in a Get-OERInventory report, which
        # reads them first. The null-filter keeps a blank entry out, so an IncompleteReads count
        # never stands for a gap that names nothing.
        $GroupUnread = @(if ($GroupRead) { @($GroupRead.Unread) | Where-Object { $_ } })
        if ($GroupUnread.Count -gt 0) { $IncompleteReads.Add(($GroupUnread -join ', ')) }
        foreach ($IErr in @($InventoryReadErrors)) {
            if ($null -eq $IErr) { continue }
            if ($IErr.FullyQualifiedErrorId -like 'InventoryPartial*') {
                # TargetObject carries the section/displayName/key triples, which is what makes the
                # summary entry name the affected object rather than merely count one. It is not
                # guaranteed to be populated (a caller-supplied mock, or a future variant of the
                # error), and an empty entry would make an IncompleteReads count assertion pass
                # while saying nothing -- fall back to the message rather than record a blank.
                $ReadDetail = [string]$IErr.TargetObject
                if (-not $ReadDetail) { $ReadDetail = [string]$IErr.Exception.Message }
                $IncompleteReads.Add($ReadDetail)
            }
        }

        # BL-131 (R-3): every name left out of inventory.json because two or more objects share it,
        # with its count and section: the group reader's own first, then the ones Get-OERInventory
        # handed over in its information record. They stay named in IncompleteReads as before; this
        # list adds the counts, for ONE warning here -- after both reads and before the Azure walk, so
        # before the bundle's ShouldProcess: -WhatIf shows it, and a Stop warning preference stops the
        # export here, before anything is written -- and for the README, which lists each name.
        $InventorySharedNames = @($InventoryInformation |
                Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.SharedName' } |
                ForEach-Object { @($_.MessageData.Names) })
        $SharedNames = @(@(if ($GroupRead) { @($GroupRead.SharedNames) }) + $InventorySharedNames | Where-Object { $null -ne $_ })
        if ($SharedNames.Count -gt 0) {
            $NameCount = $SharedNames.Count
            $ObjectCount = 0
            foreach ($SharedName in $SharedNames) { $ObjectCount += [int]$SharedName.Count }
            Write-Warning "Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares, since the apply engine refuses an ambiguous name: $NameCount name(s), carried by $ObjectCount object(s) in all. README.md lists each name, how many objects carry it and its section under 'Names two or more objects share'."
        }

        # --- Naming auto-seed: the profile whose TenantId matches the connected tenant ---
        $NamingConvention = $null
        try {
            $ConnectedTenant = if ($script:_OERAuthState) { [string]$script:_OERAuthState.TenantId } else { $TenantId }
            # -ErrorAction Stop for the same reason as the per-scope read below: without it a
            # NON-terminating failure (a corrupt profile on disk now reports TenantProfileMalformed)
            # bypasses this catch entirely and leaks out of Export-OERInventory, setting $? false on
            # an otherwise complete bundle. InventoryPartial is the only coverage signal this cmdlet
            # raises; a profile that cannot be read is a missing prompt hint, not missing coverage.
            $Profiles = @(Get-OERConfiguration -ErrorAction Stop)
            $Match = @($Profiles | Where-Object { $_.TenantId -and $_.TenantId -eq $ConnectedTenant })
            if ($Match.Count -eq 0 -and $Profiles.Count -eq 1) { $Match = $Profiles }
            if ($Match.Count -ge 1 -and $Match[0].Naming) { $NamingConvention = [string]$Match[0].Naming.Group }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # Verbose rather than a warning: the seed is a convenience that only shapes a hint line
            # in the LLM prompt, so its absence never makes the bundle wrong -- but a silent catch
            # gave an operator wondering why the prompt has no naming convention nothing to read.
            Write-Verbose "[Export-OERInventory] Could not auto-seed the naming convention from a tenant profile: $($PSItem.Exception.Message)"
        }

        # --- Tenant-wide Azure walk (RoleAssignments / RoleManagementPolicies) ---
        $AzureSections = @($Include | Where-Object { $_ -in @('RoleAssignments', 'RoleManagementPolicies') })
        $RoleAssignments = [System.Collections.Generic.List[object]]::new()
        $RoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        $ScopeHierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
        # ScopesEnumerated is what the walk FOUND; ScopeCount is what it actually READ. Reporting
        # only the first overstated coverage: a run that skipped 40 of 50 scopes still said 50.
        $ScopeCount = 0
        $ScopesEnumerated = 0
        $SkippedScopes = [System.Collections.Generic.List[string]]::new()
        $AzureEligibilities = @()
        # Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations the walk's subscriptions hold. The read
        # object stays in $LighthouseRead, null when no read was made (no Azure section, or no scope tree).
        $LighthouseRead = $null
        $LighthouseDelegations = @()
        # What the Lighthouse read could not read, in two lists kept apart from the Entra ID entries in
        # $IncompleteReads and appended LAST in the output object and the README call: the
        # 'lighthouseDelegations at <scope>' and 'lighthouseDelegations role <id>' entries the reader returns
        # (and two of this cmdlet's own: one for a scope enumeration that failed, one for a subscription
        # listing that failed), and the causes the reader names for them. Both are filled below and read
        # only by the output object, the README call and the InventoryPartial message.
        $LighthouseUnread = [System.Collections.Generic.List[string]]::new()
        $LighthouseCauses = [System.Collections.Generic.List[object]]::new()
        $SkippedEligibilityScopes = [System.Collections.Generic.List[string]]::new()
        # BL-150 (A19): the subscriptions the walk did not enter. $ForeignSubscriptions holds the ones whose home
        # tenant is another tenant (a deliberate selection: one warning and the README name them, and they make
        # no bundle partial). $HomeTenantUnread holds a 'subscriptionHomeTenant at <scope>' entry per subscription
        # whose home tenant could not be decided, with its cause in $HomeTenantCauses; they are appended to
        # IncompleteReads after the role selection entries and before the Lighthouse ones, and have a clause of
        # their own in the InventoryPartial message. Empty for a pure-Entra export and a failed scope enumeration.
        $ForeignSubscriptions = @()
        $HomeTenantUnread = [System.Collections.Generic.List[string]]::new()
        $HomeTenantCauses = [System.Collections.Generic.List[object]]::new()

        # BL-107: without -AllRolePolicies the RoleManagementPolicies section keeps a role's policy at a
        # scope only when the role has an active assignment or an eligibility EXACTLY at that scope, or
        # the policy has been changed (Select-OERInventoryRolePolicy owns the rule). The policies are
        # then read per scope by Get-OERInventoryRolePolicy -- the same one paged list and the same
        # converters as Get-OERInventory -AllRolesAtScope -- and kept or omitted after the walk, once
        # the eligibility read below is in; nothing is requested per policy. -AllRolePolicies runs the
        # per-scope Get-OERInventory call exactly as before and selects nothing.
        $SelectRolePolicies = ($AzureSections -contains 'RoleManagementPolicies') -and -not $AllRolePolicies
        $ScopeSections = @(if ($SelectRolePolicies) { $AzureSections | Where-Object { $_ -ne 'RoleManagementPolicies' } } else { $AzureSections })
        $RolePolicyCandidates = [System.Collections.Generic.List[object]]::new()
        $RoleAssignmentFacts = [System.Collections.Generic.List[object]]::new()
        $RoleAssignmentUnreadScopes = [System.Collections.Generic.List[string]]::new()
        # The 'roleManagementPolicies/role selection at <scope>' entries, the scope in its canonical
        # form (ConvertTo-OERCanonicalScope: a trailing '/' trimmed, letter case kept; an ARM scope
        # reads 'roleManagementPolicies/role selection at /subscriptions/...'), in the shape of
        # Get-OERInventory's 'directoryRoleManagementPolicies/role selection': scopes where at least one
        # policy could not be judged and was kept. Kept apart from the Entra ID entries in
        # $IncompleteReads and appended after them, so the Entra ID entries keep their documented order
        # and own clause.
        $RolePolicySelectionReads = [System.Collections.Generic.List[string]]::new()
        # BL-126 (R3): the role assignments at the Azure root scope '/' that the per-scope
        # Get-OERInventory calls left out, as each call's Omnicit.EntraRBAC.RootScopeAssignment
        # information record carries them: one list for the whole walk, deduplicated after it.
        $RootScopeRows = [System.Collections.Generic.List[object]]::new()
        # Sprint 11 step 6 (BL-133, A18): the role assignments written with principalStatus, as each per-scope
        # call's Omnicit.EntraRBAC.UnresolvedPrincipal information record carries them: one list for the
        # whole walk, deduplicated after it.
        $UnresolvedPrincipalRows = [System.Collections.Generic.List[object]]::new()
        # A13, A15: the role assignments at a scope no document can declare that the per-scope calls left
        # out, as each call's Omnicit.EntraRBAC.UndeclarableScope information record carries them: one list
        # for the whole walk, deduplicated after it.
        $UndeclarableScopeRows = [System.Collections.Generic.List[object]]::new()

        if ($AzureSections.Count -gt 0) {
            # A20 (BL-152): the tree leaves what it learned about each subscription in the run context's
            # SubscriptionTenant, which the per-scope Get-OERInventory calls below read (see the run context).
            $TreeParams = @{ Cache = $RunContext.SubscriptionTenant }
            if ($ManagementGroup) { $TreeParams.ManagementGroup = $ManagementGroup }
            if ($Scope) { $TreeParams.Scope = $Scope }
            $Tree = $null
            try {
                $Tree = Resolve-OERInventoryScopeTree @TreeParams
                $ScopeHierarchy = $Tree.Hierarchy
                $ScopesEnumerated = @($Tree.Scopes).Count
                # A level of the tree that could not be LISTED (a refused management-group listing,
                # say) was not walked at all: it is skipped for the role-assignment walk AND for
                # azurePimEligibility.json, which makes the bundle InventoryPartial below -- never
                # "no management groups".
                foreach ($TreeSkip in @($Tree.SkippedScopes)) {
                    if (-not $TreeSkip) { continue }
                    $SkippedScopes.Add([string]$TreeSkip)
                    $SkippedEligibilityScopes.Add([string]$TreeSkip)
                    # Sprint 11 step 6b (BL-133): subscriptions that could not be LISTED are subscriptions whose
                    # delegations were never read, and the reader is not asked about them. A management group
                    # listing that failed adds nothing: no delegation lives at a management group, and the
                    # subscriptions are listed apart.
                    if ([string]$TreeSkip -ceq '<subscriptions: the listing failed>') {
                        $LighthouseUnread.Add('lighthouseDelegations at <subscriptions: the listing failed>')
                    }
                }
                # BL-150 (A19): the subscriptions the tree left out of the walk. A tree result that carries no such
                # list (a caller-supplied stand-in, say) is read as none: @($null) is one element, so nulls are
                # dropped.
                $ForeignSubscriptions = @($Tree.ForeignSubscriptions | Where-Object { $null -ne $_ })
                foreach ($Row in @($Tree.UndecidedSubscriptions | Where-Object { $null -ne $_ })) {
                    $HomeTenantUnread.Add("subscriptionHomeTenant at $($Row.Scope)")
                    $HomeTenantCauses.Add([PSCustomObject]@{ Cause = [string]$Row.Reason; Target = [string]$Row.SubscriptionId })
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not enumerate Azure scopes: $($PSItem.Exception.Message)"
                $Tree = $null
                # Record the whole Azure walk as skipped so the partial-coverage error below fires.
                # Without this the bundle is written with ZERO role assignments and zero policies and
                # nothing but a warning says so, which leaves $? true and -ErrorAction Stop inert.
                $SkippedScopes.Add('<all Azure scopes: scope enumeration failed>')
                # Same reasoning for the eligibility read: with no scope tree there is nothing to walk
                # for azurePimEligibility.json either, and the gap must be named rather than silently
                # written as an empty (and therefore misleadingly "complete") file.
                $SkippedEligibilityScopes.Add('<all Azure scopes: scope enumeration failed>')
                # Sprint 11 step 6b (BL-133): and the delegations of the subscriptions that walk would have
                # visited were not read either, which is named, not left as an empty lighthouseDelegations.json.
                $LighthouseUnread.Add('lighthouseDelegations at <all Azure scopes: scope enumeration failed>')
            }
            if ($Tree) {
                # The merged role assignments' keys, each with the index of its row in $RoleAssignments, so a
                # row that a later scope's read writes with principalStatus can take the place of the row an
                # earlier read wrote without it (see the merge below).
                $RaIndexByKey = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $SeenRmp = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                # Shortens a list back to the count it had before a scope's reads (see the catch below).
                $UndoScopeHandover = {
                    param([System.Collections.IList]$List, [int]$Count)
                    while ($List.Count -gt $Count) { $List.RemoveAt($List.Count - 1) }
                }
                $ScopeIndex = 0
                try {
                    foreach ($S in @($Tree.Scopes)) {
                        $ScopeIndex++
                        Write-Progress -Activity 'Export-OERInventory' -Status "Azure scope $ScopeIndex of $ScopesEnumerated" -PercentComplete (($ScopeIndex / [Math]::Max($ScopesEnumerated, 1)) * 100)
                        $ScopeInv = $null
                        $ScopeCandidates = @()
                        $ScopeAssignments = @()
                        $ScopeAssignmentsUnread = $false
                        # What this scope's call hands over beyond its rows -- the rows of its
                        # Omnicit.EntraRBAC.UnresolvedPrincipal and Omnicit.EntraRBAC.UndeclarableScope notices,
                        # and the principals it names unread in the run context -- counts only once the scope's
                        # rows are merged below. A scope skipped after its call (a failed policy list, say) merges
                        # no row, so the catch below takes those back to the counts noted here, and the README,
                        # the warnings and IncompleteReads never name a row that only a skipped scope read --
                        # the README and the warning say a row with principalStatus is in inventory.json. The
                        # two run context lists are taken back together, so they stay index for index (each
                        # unread principal beside its cause). The root notices still count from a skipped scope:
                        # a root row is left out of the document whichever scope read it.
                        $UnresolvedMark = $UnresolvedPrincipalRows.Count
                        $UndeclarableMark = $UndeclarableScopeRows.Count
                        $UnreadPrincipalMark = $RunContext.UnreadPrincipal.Count
                        $UnreadPrincipalCauseMark = $RunContext.UnreadPrincipalCause.Count
                        try {
                            # Selecting, the call leaves RoleManagementPolicies (and -AllRolesAtScope)
                            # out and is not made at all when nothing is left; otherwise it is the call
                            # it always was.
                            if ($ScopeSections.Count -gt 0) {
                                $ScopeParams = @{ Include = $ScopeSections; Scope = $S }
                                if ($ScopeSections -contains 'RoleManagementPolicies') { $ScopeParams.AllRolesAtScope = $true }
                                # -ErrorAction Stop is load-bearing: without it a NON-terminating failure
                                # inside Get-OERInventory never reaches this catch under the default
                                # preference, so the scope contributed nothing and did not even warn.
                                # Sprint 11 step 10 (BL-34): a failed role assignment or role management
                                # policy read is now that kind of failure -- Get-OERInventory names the
                                # section unread and ends in a non-terminating InventoryPartial -- and this
                                # -ErrorAction Stop is what turns it into the skip below, as the reader's own
                                # record did before.
                                #
                                # BL-126 (R3): every read below the root scope returns a root assignment as
                                # inherited, so each call would warn about the same rows. Its warnings are
                                # therefore captured, not shown, and its root notices read from the
                                # information stream: the rows join $RootScopeRows, and ONE warning after
                                # the walk names them. -InformationAction SilentlyContinue keeps a caller's
                                # own information preference off the call, so a notice is never displayed
                                # per scope and never stops the call (under Stop, every scope below a root
                                # assignment would otherwise be skipped); -InformationVariable still
                                # captures it.
                                # Every other captured warning is written again here,
                                # with its own text, so it is shown once per scope as before; under a Stop
                                # preference that write stops, and the catch below skips the scope as
                                # before. The capture runs in a finally, so what a call wrote before it
                                # failed -- a warning, a root notice -- still counts before the scope is
                                # skipped. A caller's own
                                # -WarningVariable still collects the captured warnings too: PowerShell
                                # appends a nested command's warnings to every enclosing -WarningVariable,
                                # whatever that command's -WarningAction (measured).
                                #
                                # Sprint 11 step 6 (BL-133): the Omnicit.EntraRBAC.UnresolvedPrincipal notices are
                                # read the same way: their rows join $UnresolvedPrincipalRows, their warning texts
                                # are not written again, and ONE warning after the walk counts the rows. So are the
                                # Omnicit.EntraRBAC.UndeclarableScope notices (A13, A15): their rows join
                                # $UndeclarableScopeRows.
                                $ScopeWarnings = $null
                                $ScopeInformation = $null
                                try {
                                    $ScopeInv = Get-OERInventory @ScopeParams -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable ScopeWarnings `
                                        -InformationAction SilentlyContinue -InformationVariable ScopeInformation
                                } finally {
                                    $ScopeNotices = @($ScopeInformation | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment' } | ForEach-Object { $_.MessageData })
                                    $ScopePrincipalNotices = @($ScopeInformation | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.UnresolvedPrincipal' } | ForEach-Object { $_.MessageData })
                                    $ScopeUndeclarableNotices = @($ScopeInformation | Where-Object { $null -ne $_ -and $_.Tags -contains 'Omnicit.EntraRBAC.UndeclarableScope' } | ForEach-Object { $_.MessageData })
                                    $ScopeNoticeTexts = @(@($ScopeNotices) + @($ScopePrincipalNotices) + @($ScopeUndeclarableNotices) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Warning })
                                    foreach ($ScopeNotice in $ScopeNotices) {
                                        foreach ($RootRow in @($ScopeNotice.Assignments)) { if ($null -ne $RootRow) { $RootScopeRows.Add($RootRow) } }
                                    }
                                    foreach ($ScopePrincipalNotice in $ScopePrincipalNotices) {
                                        foreach ($PrincipalRow in @($ScopePrincipalNotice.Assignments)) { if ($null -ne $PrincipalRow) { $UnresolvedPrincipalRows.Add($PrincipalRow) } }
                                    }
                                    foreach ($ScopeUndeclarableNotice in $ScopeUndeclarableNotices) {
                                        foreach ($UndeclarableRow in @($ScopeUndeclarableNotice.Assignments)) { if ($null -ne $UndeclarableRow) { $UndeclarableScopeRows.Add($UndeclarableRow) } }
                                    }
                                    foreach ($ScopeWarning in @($ScopeWarnings)) {
                                        if ($null -eq $ScopeWarning) { continue }
                                        if ($ScopeNoticeTexts -cnotcontains [string]$ScopeWarning.Message) { Write-Warning ([string]$ScopeWarning.Message) }
                                    }
                                }
                            }
                            if ($SelectRolePolicies) {
                                # The role assignments listed at (or above) the scope, FIRST: its sign-in
                                # check renews a token near expiry before the policy list, as the
                                # per-scope Get-OERRoleManagementPolicy call does with -AllRolePolicies.
                                # A failure here costs the selection, not the scope: a policy at the scope
                                # not kept by a use or a change is then kept without being judged, and the
                                # scope is named, never dropped.
                                try {
                                    $ScopeAssignments = @(Get-OERRoleAssignment -Scope $S -AtScope -ErrorAction Stop)
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    Write-Warning "Could not read the role assignments at scope '$S', so a role management policy there not kept by a use or a change is kept without being judged: $($PSItem.Exception.Message)"
                                    $ScopeAssignmentsUnread = $true
                                }
                                # A failed policy list reaches the catch below and skips the scope, as a
                                # failed policy read always has. -ErrorAction Stop for the same reason as
                                # above.
                                $ScopeCandidates = @(Get-OERInventoryRolePolicy -Scope $S -ErrorAction Stop)
                            }
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            Write-Warning "Skipping scope '$S': $($PSItem.Exception.Message)"
                            $SkippedScopes.Add([string]$S)
                            # The skipped scope merges no row, so what its call handed over is taken back.
                            & $UndoScopeHandover $UnresolvedPrincipalRows $UnresolvedMark
                            & $UndoScopeHandover $UndeclarableScopeRows $UndeclarableMark
                            & $UndoScopeHandover $RunContext.UnreadPrincipal $UnreadPrincipalMark
                            & $UndoScopeHandover $RunContext.UnreadPrincipalCause $UnreadPrincipalCauseMark
                            continue
                        }
                        # $ScopeInv is $null when no call was made, and @($null.X) is a one-element
                        # array holding $null, so every read of it drops nulls.
                        #
                        # Sprint 11 step 6 (BL-133): an assignment several scopes read (an inherited one) is merged
                        # once, on its id or, with none, on scope, role and principal. A principal is written by its
                        # object id both where its lookup failed (no principalStatus) and where a lookup that
                        # succeeded did not return it (principalStatus), so the two rows of one assignment share a
                        # key. The row with principalStatus is the one kept, whichever scope read it first: a later
                        # one takes the earlier row's place in the list, and an earlier one stays. That the lookup
                        # failed at another scope is then no longer unread (see the unread principals after the
                        # walk).
                        foreach ($Ra in @($ScopeInv.RoleAssignments | Where-Object { $null -ne $_ })) {
                            $Key = if ($Ra.PSObject.Properties.Name -contains 'id' -and $Ra.id) { [string]$Ra.id } else { '{0}|{1}|{2}' -f $Ra.scope, $Ra.role, $Ra.principal }
                            if (-not $RaIndexByKey.ContainsKey($Key)) {
                                $RaIndexByKey[$Key] = $RoleAssignments.Count
                                $RoleAssignments.Add($Ra)
                            } elseif (-not [string]::IsNullOrEmpty([string]$Ra.principalStatus) -and
                                [string]::IsNullOrEmpty([string]$RoleAssignments[$RaIndexByKey[$Key]].principalStatus)) {
                                $RoleAssignments[$RaIndexByKey[$Key]] = $Ra
                            }
                        }
                        # Non-empty only under -AllRolePolicies: selecting, the call reads no policy.
                        foreach ($Rmp in @($ScopeInv.RoleManagementPolicies | Where-Object { $null -ne $_ })) {
                            $Key = '{0}|{1}' -f $Rmp.scope, $Rmp.role
                            if ($SeenRmp.Add($Key)) { $RoleManagementPolicies.Add($Rmp) }
                        }
                        # The selection's inputs, from a scope that was read; decided after the walk.
                        foreach ($Candidate in $ScopeCandidates) { if ($null -ne $Candidate) { $RolePolicyCandidates.Add($Candidate) } }
                        foreach ($Fact in $ScopeAssignments) { if ($null -ne $Fact) { $RoleAssignmentFacts.Add($Fact) } }
                        if ($ScopeAssignmentsUnread) { $RoleAssignmentUnreadScopes.Add([string]$S) }
                        # Counted only here, after the scope has been read and merged, so ScopeCount
                        # reports coverage rather than intent.
                        $ScopeCount++
                    }
                } finally {
                    Write-Progress -Activity 'Export-OERInventory' -Completed
                }

                # R4: one bounded eligibility read of the SAME scope list, after the role-assignment /
                # policy walk above rather than interleaved with it, so a throttled or failing scope
                # is never charged against both files from the same failed request.
                $EligResult = Get-OERInventoryAzureEligibility -Scope @($Tree.Scopes)
                $AzureEligibilities = @($EligResult.Eligibilities)
                foreach ($SkEl in @($EligResult.SkippedScopes)) {
                    if ($SkEl) { $SkippedEligibilityScopes.Add([string]$SkEl) }
                }

                # Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations at the same scope list, read after
                # the eligibility read for the same reason (docs/development/rationale.md#lighthouse-delegations).
                # Always on when an Azure section is included, so a delegation of another tenant is never left
                # out because nobody asked. $LighthouseRead keeps the reader's whole result (Delegations, Unread,
                # Causes); the delegations are read from it with a null-filter, since @($null) is one element.
                $LighthouseRead = Get-OERInventoryLighthouseDelegation -Scope @($Tree.Scopes)
                $LighthouseDelegations = @($LighthouseRead.Delegations | Where-Object { $null -ne $_ })
                # What the reader could not read, appended after the tree's own entries above. A blank entry is
                # left out: it would add an empty item to IncompleteReads and to the InventoryPartial message,
                # and raise that error for nothing. A null cause is no cause.
                if ($null -ne $LighthouseRead) {
                    foreach ($LighthouseUnreadEntry in @($LighthouseRead.Unread)) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$LighthouseUnreadEntry)) { $LighthouseUnread.Add([string]$LighthouseUnreadEntry) }
                    }
                    foreach ($LighthouseCause in @($LighthouseRead.Causes)) {
                        if ($null -ne $LighthouseCause) { $LighthouseCauses.Add($LighthouseCause) }
                    }
                }

                # BL-107: the selection, now that the eligibilities are read. A scope whose role
                # assignment read or eligibility read failed cannot be judged: its policies that are not
                # kept on other grounds are kept anyway, and the scope is named. The kept entries are
                # merged with the same scope|role rule as the -AllRolePolicies path above.
                if ($SelectRolePolicies) {
                    $SelectionUnread = @(@($RoleAssignmentUnreadScopes) + @($EligResult.SkippedScopes) |
                            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
                    $Selection = Select-OERInventoryRolePolicy `
                        -Policy $RolePolicyCandidates.ToArray() `
                        -Assignment $RoleAssignmentFacts.ToArray() `
                        -Eligibility @($EligResult.RoleScopes | Where-Object { $null -ne $_ }) `
                        -UnreadScope $SelectionUnread
                    foreach ($Kept in @($Selection.Kept | Where-Object { $null -ne $_ })) {
                        $Key = '{0}|{1}' -f $Kept.scope, $Kept.role
                        if ($SeenRmp.Add($Key)) { $RoleManagementPolicies.Add($Kept) }
                    }
                    foreach ($Unjudged in @($Selection.UnjudgedScopes)) {
                        if ($Unjudged) { $RolePolicySelectionReads.Add("roleManagementPolicies/role selection at $Unjudged") }
                    }
                }
            }
        }
        # The walk is over: no later Get-OERInventory call of this export exists. A plain statement and no
        # finally (see the run context above), so the control flow of the region is what it always was.
        $script:_OERInventoryRunContext = $null

        # Sprint 11 step 8: the service principal access, read only with -IncludeServicePrincipalAccess, ONCE,
        # here after the Azure walk and before the warnings that precede the bundle's ShouldProcess -- under
        # -WhatIf too, since the read changes nothing and the plan is then complete. Get-OERServicePrincipalAccess
        # owns the four reads and never writes an error record; a part it could not read is $null in its
        # result and named in its Unread, with the causes in its Causes. Both lists are kept apart from the
        # other entries, as the Lighthouse ones are: $SpAccessUnread goes last into IncompleteReads (the output
        # object and the README call) and has a clause of its own in the InventoryPartial message. No warning
        # is written for it. A reader that stops, or returns nothing, has read nothing: every part is then
        # unread and named, never written as an empty or silent null.
        $SpAccessRead = $null
        $SpAccessUnread = [System.Collections.Generic.List[string]]::new()
        $SpAccessCauses = [System.Collections.Generic.List[object]]::new()
        if ($IncludeServicePrincipalAccess) {
            $SpAccessStopCause = $null
            try {
                $SpAccessRead = Get-OERServicePrincipalAccess
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $SpAccessRead = $null
                $SpAccessStopCause = "Could not read the service principal access: $($PSItem.Exception.Message)"
            }
            if ($null -eq $SpAccessRead) {
                $SpAccessRead = [PSCustomObject]@{
                    ApplicationPermissions    = $null
                    DelegatedPermissionGrants = $null
                    ApplicationOwners         = $null
                    ServicePrincipalOwners    = $null
                    Unread                    = @('servicePrincipalAccess/applicationPermissions', 'servicePrincipalAccess/delegatedPermissionGrants', 'servicePrincipalAccess/applicationOwners', 'servicePrincipalAccess/servicePrincipalOwners')
                    Causes                    = @([PSCustomObject]@{ Cause = $(if ($SpAccessStopCause) { $SpAccessStopCause } else { 'Could not read the service principal access: the read returned nothing.' }); Target = '' })
                }
            }
            # A blank entry is left out, as for the Lighthouse reader: it would add an empty item to IncompleteReads
            # and to the InventoryPartial message, and raise that error for nothing. A null cause is no cause.
            foreach ($SpAccessUnreadEntry in @($SpAccessRead.Unread)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$SpAccessUnreadEntry)) { $SpAccessUnread.Add([string]$SpAccessUnreadEntry) }
            }
            foreach ($SpAccessCause in @($SpAccessRead.Causes)) {
                if ($null -ne $SpAccessCause) { $SpAccessCauses.Add($SpAccessCause) }
            }
        }

        # BL-126 (R3): the role assignments at the root scope the walk's reads left out, each once
        # (Format-OERRootScopeAssignment deduplicates them on the role assignment id and owns their
        # order and list text, shared with Get-OERInventory's warning). One warning names them, here
        # after the walk and before the bundle's ShouldProcess, so -WhatIf shows it too, and the
        # README lists them (docs/development/rationale.md#root-scope-is-not-in-the-document).
        $RootScopeAssignments = @()
        if ($RootScopeRows.Count -gt 0) {
            $RootList = Format-OERRootScopeAssignment -Assignment $RootScopeRows.ToArray()
            $RootScopeAssignments = @($RootList.Assignments)
            Write-Warning "Export-OERInventory: left out $($RootScopeAssignments.Count) role assignment(s) at the root scope '/', which grants access over every management group and subscription in the tenant (elevated access), from inventory.json and roleAssignments.json: $($RootList.Text). README.md names them under 'Role assignments at the root scope (elevated access)'; review them as a finding. Invoke-OERStructure never creates or removes a role assignment at the root scope."
        }

        # Sprint 11 step 6 (BL-133, A18): the role assignments the walk's reads wrote with principalStatus,
        # each once -- an assignment inherited by several scopes is handed over by each read -- deduplicated
        # on the role assignment id, and on scope, role and principal for a row with none, without regard to
        # letter case, in the order first handed over. They stay in inventory.json and roleAssignments.json.
        # One warning counts them, here after the walk and before the bundle's ShouldProcess, so -WhatIf
        # shows it too, and the README lists them (docs/development/rationale.md#unresolved-principals).
        $UnresolvedPrincipalAssignments = @()
        if ($UnresolvedPrincipalRows.Count -gt 0) {
            $SeenPrincipalRow = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $UnresolvedPrincipalAssignments = @(foreach ($PrincipalRow in $UnresolvedPrincipalRows) {
                    $PrincipalRowKey = if (-not [string]::IsNullOrWhiteSpace([string]$PrincipalRow.RoleAssignmentId)) {
                        'id|' + [string]$PrincipalRow.RoleAssignmentId
                    } else {
                        'row|{0}|{1}|{2}' -f $PrincipalRow.Scope, $PrincipalRow.Role, $PrincipalRow.Principal
                    }
                    if ($SeenPrincipalRow.Add($PrincipalRowKey)) { $PrincipalRow }
                })
            Write-Warning "Export-OERInventory: $($UnresolvedPrincipalAssignments.Count) role assignment(s) in inventory.json and roleAssignments.json name a principal the directory did not return, each written by the principal's object id with principalStatus Deleted (found among the directory's deleted items) or Unresolved (found neither in the directory nor among its deleted items, or its deleted items could not be read). README.md names them under 'Role assignments whose principal the directory did not return'; review them as a finding. Invoke-OERStructure never creates such an assignment."
        }

        # A13, A15: the role assignments at a scope no document can declare that the walk's reads left out,
        # each once -- an assignment inherited by several scopes is handed over by each read -- deduplicated on
        # the role assignment id, and on scope, role and principal for a row with none, without regard to
        # letter case, in the order first handed over. One warning counts them, here after the walk and before
        # the bundle's ShouldProcess, so -WhatIf shows it too, and the README lists them
        # (docs/development/rationale.md#undeclarable-scope).
        $UndeclarableScopeAssignments = @()
        if ($UndeclarableScopeRows.Count -gt 0) {
            $SeenUndeclarableRow = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $UndeclarableScopeAssignments = @(foreach ($UndeclarableRow in $UndeclarableScopeRows) {
                    $UndeclarableRowKey = if (-not [string]::IsNullOrWhiteSpace([string]$UndeclarableRow.RoleAssignmentId)) {
                        'id|' + [string]$UndeclarableRow.RoleAssignmentId
                    } else {
                        'row|{0}|{1}|{2}' -f $UndeclarableRow.Scope, $UndeclarableRow.Role, $UndeclarableRow.Principal
                    }
                    if ($SeenUndeclarableRow.Add($UndeclarableRowKey)) { $UndeclarableRow }
                })
            Write-Warning "Export-OERInventory: left out $($UndeclarableScopeAssignments.Count) role assignment(s) whose scope no document can declare from inventory.json and roleAssignments.json: the validator refuses the scope's spelling, so a document that carried one would be refused as a whole. README.md names them under 'Role assignments at a scope no document can declare'; review them as a finding. Invoke-OERStructure never creates or removes a role assignment at such a scope."
        }

        # Sprint 11 step 6 (BL-133, A18): the role assignment principals the walk's reads could not look up,
        # or could not look for among the directory's deleted items, as they named them to the run context,
        # each entry once (an inherited assignment is read by several scopes), in the order first named. Kept
        # apart from the Entra ID entries in $IncompleteReads and appended after them, before the role policy
        # selection entries, so the Entra ID entries keep their documented order and own clause.
        #
        # A '<...>/principal' entry -- a failed lookup -- is left out, with its cause, where the merged row of
        # its assignment carries principalStatus: another scope's lookup succeeded and did not return the
        # principal, so the principal was read after all (see the merge in the walk). The entry is
        # 'roleAssignments/<role> -> <principal id> @ <scope>/principal', and such a row's principal is that
        # object id, so the row's own fields spell the entry. The run context's two lists stand index for index
        # (each unread principal beside its cause), so an entry left out takes the cause at its index with it.
        $StatusRowLookupEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($MergedRa in $RoleAssignments) {
            if (-not [string]::IsNullOrEmpty([string]$MergedRa.principalStatus)) {
                [void]$StatusRowLookupEntries.Add("roleAssignments/$($MergedRa.role) -> $($MergedRa.principal) @ $($MergedRa.scope)/principal")
            }
        }
        $UnreadPrincipalEntries = @($RunContext.UnreadPrincipal)
        $LeftOutUnreadIndex = [System.Collections.Generic.HashSet[int]]::new()
        for ($UnreadIndex = 0; $UnreadIndex -lt $UnreadPrincipalEntries.Count; $UnreadIndex++) {
            if ($StatusRowLookupEntries.Contains([string]$UnreadPrincipalEntries[$UnreadIndex])) { [void]$LeftOutUnreadIndex.Add($UnreadIndex) }
        }
        $UnreadPrincipalReads = [System.Collections.Generic.List[string]]::new()
        $SeenUnreadPrincipal = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        for ($UnreadIndex = 0; $UnreadIndex -lt $UnreadPrincipalEntries.Count; $UnreadIndex++) {
            $UnreadPrincipal = [string]$UnreadPrincipalEntries[$UnreadIndex]
            if ([string]::IsNullOrWhiteSpace($UnreadPrincipal) -or $LeftOutUnreadIndex.Contains($UnreadIndex)) { continue }
            if ($SeenUnreadPrincipal.Add($UnreadPrincipal)) { $UnreadPrincipalReads.Add($UnreadPrincipal) }
        }
        $UnreadPrincipalCauses = @(for ($CauseIndex = 0; $CauseIndex -lt $RunContext.UnreadPrincipalCause.Count; $CauseIndex++) {
                if (-not $LeftOutUnreadIndex.Contains($CauseIndex)) { $RunContext.UnreadPrincipalCause[$CauseIndex] }
            })

        # --- Group split: RBAC-relevant kept in inventory.json; unfiltered roster written separately ---
        # The whole if/else is wrapped in @(...) because an empty 'else' result (no RBAC-relevant
        # groups) assigned straight from an if-statement collapses to $null, and a later @($null)
        # would inject a single null group that fails apply-schema validation. The null-item guard
        # keeps a stray null out of the filtered set. $AllGroups is what the group reader returned:
        # every group under -AllGroupsDetailed, otherwise the groups it found relevant and the ones
        # whose relevance it could not read. The filter below stays the final say either way, so a
        # group read in full only because its relevance was unknown is still not kept on that account.
        $AllGroups = @(if ($GroupRead) { @($GroupRead.Groups) | Where-Object { $null -ne $_ } })
        $DetailedGroups = @(
            if ($AllGroupsDetailed) {
                $AllGroups
            } else {
                $AllGroups | Where-Object {
                    # The null-filter inside the count is load-bearing: eligibility is ABSENT on a
                    # group whose eligibility read failed (issue #76), and @($null).Count is 1, so a
                    # bare count would class every such group as RBAC-relevant on evidence that does
                    # not exist.
                    $_.roleAssignable -eq $true -or
                    @($_.eligibility | Where-Object { $null -ne $_ }).Count -gt 0 -or
                    ($_.PSObject.Properties.Name -contains 'pimPolicy') -or
                    # A15: a group synchronized from on-premises is never kept by the three criteria
                    # above (it cannot be role-assignable or managed in PIM for Groups), so it is kept
                    # only on request. The group reader writes onPremisesSynced as a boolean true for
                    # such a group and never otherwise; anything else is not taken for it.
                    ($IncludeSyncedGroups -and $_.onPremisesSynced -is [bool] -and $_.onPremisesSynced)
                }
            }
        )

        # Member-count map keyed on object id (from the -IncludeId-stamped projection the group
        # reader returned): zero extra calls. id is the only join key: Entra permits duplicate group
        # display names (Add-OERGroupMember.ps1:43-45), so a display-name join would attribute one
        # same-named group's member count to another -- to a Microsoft 365 group the security-enabled
        # listing never held, for one.
        #
        # R3: the map holds the groups the reader READ IN FULL and nothing else. A group it did not
        # read in full -- every group of the roster that is not security-enabled, a security group
        # found not relevant (without -AllGroupsDetailed: decided from two requests, its members
        # never asked for), and a group left out for a shared name -- has no entry, so its roster
        # row gets $null below: the roster's existing "not known" value. A count for those would
        # cost a request per group, and the one-request form (groups/{id}/members/$count) needs the
        # ConsistencyLevel: eventual header, which this module's single Graph transport never sends,
        # answers from an index that can lag behind recent changes, and is not measured for service
        # principals, which the full read counts. Never fill an absent entry with 0: that states an
        # emptiness nothing measured. A group whose relevance could not be read IS read in full
        # (R2), so it has its count here although inventory.json may not keep it.
        $CountById = @{}
        foreach ($G in $AllGroups) {
            # members is null when the live read failed (issue #76). @($null).Count is 1, so a bare
            # count would report a group whose membership is UNKNOWN as having exactly one member.
            # $null is the roster's existing "not known" value and is what an unread membership gets.
            $MemberCount = if ($null -ne $G.members) { @($G.members).Count } else { $null }
            if ($G.PSObject.Properties.Name -contains 'id' -and $G.id) {
                $CountById[[string]$G.id] = $MemberCount
            }
        }
        # BL-125: the reader leaves a member whose membership PIM for Groups holds out of members,
        # and counts it per group in PimLeftOut, so the roster's memberCount keeps meaning the group's
        # live member count: the members read (written to inventory.json, or only read for a group
        # read in full that inventory.json does not keep) plus the members left out. A count that is
        # not known ($null, an unread membership) stays not known. The null-filter keeps a reader
        # result that carries no PimLeftOut list from becoming one null entry.
        $PimLeftOut = @(if ($GroupRead) { @($GroupRead.PimLeftOut) | Where-Object { $null -ne $_ } })
        foreach ($LeftOut in $PimLeftOut) {
            $LeftOutId = [string]$LeftOut.GroupId
            if ($LeftOutId -and $CountById.ContainsKey($LeftOutId) -and $null -ne $CountById[$LeftOutId]) {
                $CountById[$LeftOutId] += [int]$LeftOut.Members
            }
        }
        # The README counts what was left out of inventory.json, so it names only the groups
        # inventory.json writes ($DetailedGroups). A group the reader read in full and the filter
        # above did not keep -- one read in full only because its relevance could not be read, say --
        # is not in the document, and listing it would say members were left out of a group the
        # document does not hold. The roster join above keeps the unfiltered list on purpose: a
        # roster row's memberCount is the live count of every group read in full. The ids are taken
        # here, before the strip below removes them.
        $KeptGroupIds = @{}
        foreach ($KeptGroup in $DetailedGroups) {
            if ($KeptGroup.PSObject.Properties.Name -contains 'id' -and $KeptGroup.id) { $KeptGroupIds[[string]$KeptGroup.id] = $true }
        }
        $ReadmePimLeftOut = @($PimLeftOut | Where-Object { $KeptGroupIds.ContainsKey([string]$_.GroupId) })

        # Sprint 11 step 6 (BL-134): the groups inventory.json writes with PIM eligibility or a pimPolicy block
        # that are members of a restricted management unit. Microsoft Learn states that Privileged Identity
        # Management does not support a group in a restricted management administrative unit
        # (docs/development/rationale.md#restricted-unit-pim); what Microsoft Graph answers when the apply
        # engine sends such a group's eligibility or PIM policy writes is not measured. The administrative
        # units list a group member by its object id (Get-OERInventory), and the groups still carry theirs
        # here, before the strip below, so the link is found with no request. A unit counts when it is
        # restricted (the boolean true) and its members were read: a unit whose members are an explicit null
        # (unread) or absent (a dynamic unit) lists nobody, and is named in IncompleteReads when unread. A
        # unit Get-OERInventory left out of the document because another unit shares its name is not in
        # $Inv.AdministrativeUnits, so it is not checked here; it is named as a shared name. The ids are
        # compared without regard to letter case. Without Groups or without AdministrativeUnits in -Include
        # there are no groups or no units here, so nothing is found and nothing is read for it. One warning
        # counts the groups, here before the bundle's ShouldProcess, so -WhatIf shows it too; the README lists
        # each group and its units by display name, never an id.
        $RestrictedUnitMembers = [System.Collections.Generic.List[object]]::new()
        foreach ($RestrictedUnit in @($Inv.AdministrativeUnits)) {
            if ($null -eq $RestrictedUnit -or $RestrictedUnit.restricted -ne $true) { continue }
            $UnitMemberIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($UnitMember in @($RestrictedUnit.members)) {
                if ($UnitMember) { $null = $UnitMemberIds.Add([string]$UnitMember) }
            }
            $RestrictedUnitMembers.Add([PSCustomObject]@{ Name = [string]$RestrictedUnit.displayName; MemberIds = $UnitMemberIds })
        }
        $RestrictedUnitPimGroups = @(foreach ($PimGroup in $DetailedGroups) {
                # The null-filter inside the count is the keep filter's own (above): eligibility is absent on a
                # group whose eligibility read failed, and @($null).Count is 1. A pimPolicy that is present but
                # null is no policy, though the keep filter above keeps the group on the key alone.
                $UsesPim = (($PimGroup.PSObject.Properties.Name -contains 'pimPolicy') -and $null -ne $PimGroup.pimPolicy) -or
                @($PimGroup.eligibility | Where-Object { $null -ne $_ }).Count -gt 0
                if (-not $UsesPim) { continue }
                # A group with no id reads as the empty string, which no unit lists (an empty member is not
                # added above).
                $PimGroupUnits = @($RestrictedUnitMembers | Where-Object { $_.MemberIds.Contains([string]$PimGroup.id) } | ForEach-Object { $_.Name })
                if ($PimGroupUnits.Count -gt 0) {
                    [PSCustomObject]@{ Group = [string]$PimGroup.displayName; Units = $PimGroupUnits }
                }
            })
        if ($RestrictedUnitPimGroups.Count -gt 0) {
            Write-Warning "Export-OERInventory: $($RestrictedUnitPimGroups.Count) group(s) written to inventory.json use PIM for Groups (PIM eligibility or a pimPolicy block) and are members of a restricted management administrative unit. Microsoft Learn states that Privileged Identity Management does not support a group in a restricted management administrative unit. Invoke-OERStructure still sends the PIM settings and eligibility a document declares for these groups; what Microsoft Graph answers to those writes has not been measured. README.md names each group and its units under 'Groups using PIM for Groups in a restricted management unit'; review them as a finding. Nothing is left out of the export."
        }

        # Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations at the walk's subscriptions give
        # principals of a managing tenant Azure roles over a delegated subscription or resource group, access
        # that no role assignment there shows (docs/development/rationale.md#lighthouse-delegations). Since
        # BL-150 (A19) the walk reads only this tenant's own subscriptions, and Azure Lighthouse refuses a
        # delegation whose managing tenant is the subscription's own tenant, so every delegation read is access
        # another tenant holds here, and the README marks none. They are written to lighthouseDelegations.json
        # as read-only context, never into inventory.json, and listed in the README. One warning counts them,
        # here before the bundle's ShouldProcess, so -WhatIf shows it too.
        if ($LighthouseDelegations.Count -gt 0) {
            Write-Warning "Export-OERInventory: read $($LighthouseDelegations.Count) Azure Lighthouse delegation(s): access that principals of a managing tenant hold over a delegated subscription or resource group, which is not listed as a role assignment there. lighthouseDelegations.json holds them as read-only context, and README.md lists them under 'Azure Lighthouse delegations (access from another tenant)'; review them as a finding."
        }

        # BL-150 (A19): the subscriptions the walk did not enter since their home tenant is another tenant -- a
        # customer subscription another tenant delegated to this one through Azure Lighthouse, for example. That
        # is a deliberate selection, not a failed read: nothing was read from them, they make no bundle partial,
        # and the README names them. One warning names them, here before the bundle's ShouldProcess, so -WhatIf
        # shows it too, and a Stop warning preference stops the export before it writes the bundle.
        if ($ForeignSubscriptions.Count -gt 0) {
            Write-Warning "Export-OERInventory: did not read $($ForeignSubscriptions.Count) subscription(s) whose home tenant is another tenant, such as a subscription another tenant delegated to this one through Azure Lighthouse: $(($ForeignSubscriptions | ForEach-Object { "'$($_.Scope)'" }) -join ', '). README.md names them under 'Subscriptions delegated from another tenant (not read)'. Nothing was read from them, and Invoke-OERStructure refuses a role assignment or role management policy there (SubscriptionTenantMismatch)."
        }

        # inventory.json staying id-free is a documented portability property of the export
        # (Get-OERInventory's own .DESCRIPTION) -- the reader's -IncludeId above exists purely to key
        # the join, so every id it stamped is removed again here, from the groups the reader
        # returned and, as a guard, from the other sections of $Inv, before the canonical inventory
        # is assembled. -IncludeId stamps more than the top-level id: a Groups eligibility entry
        # gets one too (Get-OERInventoryGroup.ps1's $EligProj.id), so the strip reaches that nested
        # collection as well.
        $StampedSections = @(
            $AllGroups, $Inv.AdministrativeUnits, $Inv.Catalogs,
            $Inv.AccessPackages, $Inv.AccessReviews,
            $Inv.DirectoryRoleManagementPolicies, $Inv.DirectoryRoleAssignments
        )
        foreach ($Section in $StampedSections) {
            foreach ($Item in @($Section)) {
                if (-not $Item) { continue }
                $Item.PSObject.Properties.Remove('id')
                if ($Item.PSObject.Properties.Name -contains 'eligibility') {
                    foreach ($Elig in @($Item.eligibility)) {
                        if ($Elig) { $Elig.PSObject.Properties.Remove('id') }
                    }
                }
            }
        }

        $Roster = @()
        if ($Include -contains 'Groups') {
            # The roster was read before the group reader (BL-131, above); a failed read is named here,
            # after every Get-OERInventory entry, where it always was. A9: the same defect class as the
            # unread sections -- the roster is written as [] either way. It is read-only context, so it
            # is named here, not in Get-OERInventory.
            if ($RosterUnread) { $IncompleteReads.Add('groupsRoster') }
            $Roster = @(foreach ($Rg in $RosterGroups) {
                $RgId = [string]$Rg.Id
                $RgName = [string]$Rg.DisplayName
                # A roster group with no entry was not read in full: $null, not 0 (R3, above).
                $MemberCount = if ($CountById.ContainsKey($RgId)) { $CountById[$RgId] } else { $null }
                # The group's identity and type, read from the converter's values and never from the
                # raw response. groupTypes is forced to an array of strings so a security group is
                # written as [] and a Microsoft 365 group as ["Unified"], never as a bare string.
                $RgGroupTypes = [string[]]@(@($Rg.GroupTypes) | Where-Object { -not [string]::IsNullOrEmpty([string]$_) } | ForEach-Object { [string]$_ })
                [PSCustomObject]@{
                    displayName      = $RgName
                    roleAssignable   = [bool]$Rg.IsAssignableToRole
                    dynamic          = ($Rg.GroupType -eq 'Dynamic')
                    onPremisesSynced = (Test-OERGroupOnPremisesSynced -Group $Rg)
                    memberCount      = $MemberCount
                    id               = $RgId
                    securityEnabled  = if ($Rg.SecurityEnabled -is [bool]) { [bool]$Rg.SecurityEnabled } else { $null }
                    mailEnabled      = if ($Rg.MailEnabled -is [bool]) { [bool]$Rg.MailEnabled } else { $null }
                    groupTypes       = $RgGroupTypes
                    visibility       = $Rg.Visibility
                    createdDateTime  = $Rg.CreatedDateTime
                }
            })
        }

        # --- Reassemble the canonical inventory object with the (possibly filtered) groups ---
        # The two directory-role sections are filtered with Where-Object { $null -ne $_ } rather than
        # a bare @(...) wrap: @($null) is a ONE-element array holding a null, not an empty one, and a
        # caller whose Get-OERInventory result omits these properties entirely (a $null property
        # read) would otherwise hand ConvertTo-OERInventory a single null entry -- which then fails
        # apply-schema validation ("'role' is required at directoryRoleManagementPolicies[0]")
        # instead of writing a genuinely empty section, same footgun $AllGroups above guards against.
        $Canonical = ConvertTo-OERInventory `
            -TenantId $DocumentTenantId `
            -Groups $DetailedGroups `
            -AdministrativeUnits @($Inv.AdministrativeUnits) `
            -Catalogs @($Inv.Catalogs) `
            -AccessPackages @($Inv.AccessPackages) `
            -AccessReviews @($Inv.AccessReviews) `
            -DirectoryRoleManagementPolicies @($Inv.DirectoryRoleManagementPolicies | Where-Object { $null -ne $_ }) `
            -DirectoryRoleAssignments @($Inv.DirectoryRoleAssignments | Where-Object { $null -ne $_ }) `
            -RoleAssignments $RoleAssignments.ToArray() `
            -RoleManagementPolicies $RoleManagementPolicies.ToArray()

        # --- Create the bundle folder ---
        $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $TenantLabel = if ($script:_OERAuthState -and $script:_OERAuthState.TenantId) { $script:_OERAuthState.TenantId } elseif ($TenantId) { $TenantId } else { 'tenant' }
        $FolderName = "oer-inventory-$TenantLabel-$Stamp"
        $BundlePath = Join-Path $OutputPath $FolderName

        # The bundle write is the only disk mutation in this cmdlet; the tenant read above is
        # side-effect free, so -WhatIf still produces a complete, accurate plan of what would be written.
        $ShouldWrite = $PSCmdlet.ShouldProcess($BundlePath, "Write inventory bundle ($($Include -join ', '))")

        if ((Test-Path $BundlePath) -and $Force -and $ShouldWrite) {
            Remove-Item $BundlePath -Recurse -Force
        }
        if ($ShouldWrite) {
            $null = New-Item -ItemType Directory -Path $BundlePath -Force
        }

        # --- Write the files ---
        $WrittenFiles = [System.Collections.Generic.List[string]]::new()
        function Write-OERBundleJson {
            param([string]$Name, [object]$Data)
            if ($ShouldWrite) {
                $Path = Join-Path $BundlePath $Name
                # -InputObject, NOT a pipe: PowerShell unrolls a piped collection into its elements,
                # so an EMPTY array piped into ConvertTo-Json sends zero objects down the pipeline --
                # ConvertTo-Json then emits nothing at all, Set-Content receives no input and silently
                # never creates the file, even though $WrittenFiles (below) still names it. -InputObject
                # passes the array as a single argument instead, so an empty $Data correctly serializes
                # to the literal "[]" and the file this cmdlet's help promises is actually written.
                (ConvertTo-Json -InputObject $Data -Depth 12) | Set-Content -Path $Path -Encoding utf8
            }
            # Recorded either way: under -WhatIf the Files list IS the plan.
            $WrittenFiles.Add($Name)
        }

        Write-OERBundleJson -Name 'inventory.json'              -Data $Canonical
        Write-OERBundleJson -Name 'groups.json'                 -Data @($Canonical.Groups)
        Write-OERBundleJson -Name 'administrativeUnits.json'    -Data @($Canonical.AdministrativeUnits)
        Write-OERBundleJson -Name 'catalogs.json'               -Data @($Canonical.Catalogs)
        Write-OERBundleJson -Name 'accessPackages.json'         -Data @($Canonical.AccessPackages)
        Write-OERBundleJson -Name 'accessReviews.json'          -Data @($Canonical.AccessReviews)
        Write-OERBundleJson -Name 'directoryRoleManagementPolicies.json' -Data @($Canonical.DirectoryRoleManagementPolicies)
        Write-OERBundleJson -Name 'directoryRoleAssignments.json'        -Data @($Canonical.DirectoryRoleAssignments)
        Write-OERBundleJson -Name 'roleAssignments.json'        -Data @($Canonical.RoleAssignments)
        Write-OERBundleJson -Name 'roleManagementPolicies.json' -Data @($Canonical.RoleManagementPolicies)
        Write-OERBundleJson -Name 'groupsRoster.json'           -Data $Roster
        Write-OERBundleJson -Name 'scopeHierarchy.json'         -Data $ScopeHierarchy
        if ($AzureSections.Count -gt 0) {
            Write-OERBundleJson -Name 'azurePimEligibility.json' -Data @($AzureEligibilities)
            # Sprint 11 step 6b (BL-133): written exactly when azurePimEligibility.json is, and always as an
            # array, [] when none was read. The file can be [] although a read failed: a subscription whose
            # delegations could not be read has no row here, and that is never silent -- it is named in
            # IncompleteReads and in the InventoryPartial message, and in the README, so an empty or short
            # file is never mistaken for a tenant with no delegation.
            Write-OERBundleJson -Name 'lighthouseDelegations.json' -Data @($LighthouseDelegations)
        }
        # Sprint 11 step 8: written only with -IncludeServicePrincipalAccess, after the Azure files (after
        # scopeHierarchy.json when no Azure section is included). ONE object, the four parts in this order.
        # A part that could not be read is null in the file, NEVER []: an empty array would state that the
        # tenant has none of it, and the part is named in IncompleteReads instead. A part that was read is
        # always an array, [] when it holds nothing; @() keeps a part of one row an array, and the
        # null-filter keeps a null row out of it. Nothing else reads this file: inventory.json, schema.json and
        # Invoke-OERStructure never see it.
        if ($IncludeServicePrincipalAccess) {
            $SpAccessData = [ordered]@{
                applicationPermissions    = $SpAccessRead.ApplicationPermissions
                delegatedPermissionGrants = $SpAccessRead.DelegatedPermissionGrants
                applicationOwners         = $SpAccessRead.ApplicationOwners
                servicePrincipalOwners    = $SpAccessRead.ServicePrincipalOwners
            }
            foreach ($SpAccessPart in @($SpAccessData.Keys)) {
                if ($null -ne $SpAccessData[$SpAccessPart]) {
                    $SpAccessData[$SpAccessPart] = [object[]]@(@($SpAccessData[$SpAccessPart]) | Where-Object { $null -ne $_ })
                }
            }
            Write-OERBundleJson -Name 'servicePrincipalAccess.json' -Data $SpAccessData
        }

        # --- Formal JSON Schema (so a consumer without the module can validate a proposal) ---
        if ($ShouldWrite) {
            (Get-OERStructureSchemaJson) | Set-Content -Path (Join-Path $BundlePath 'schema.json') -Encoding utf8
        }
        $WrittenFiles.Add('schema.json')

        # --- Prompt + README ---
        # Sprint 11 step 8: the prompt names servicePrincipalAccess.json, and the README gets its section, only
        # with -IncludeServicePrincipalAccess. Each parameter is added only when the switch is set, as
        # -AllDirectoryRolePolicies is above, so without it both calls are exactly what they were.
        $PromptParams = @{ NamingConvention = $NamingConvention }
        $ReadmeSpAccessParams = @{}
        if ($IncludeServicePrincipalAccess) {
            $PromptParams.IncludeServicePrincipalAccess = $true
            $ReadmeSpAccessParams.ServicePrincipalAccess = $SpAccessRead
        }
        if ($ShouldWrite) {
            (Get-OERInventoryPromptTemplate @PromptParams) |
                Set-Content -Path (Join-Path $BundlePath 'rbac-architect-prompt.md') -Encoding utf8
        }
        $WrittenFiles.Add('rbac-architect-prompt.md')
        if ($ShouldWrite) {
            # All three lists are complete by now (the roster read above was the last to add an
            # IncompleteReads entry), and they go into the README alone: inventory.json is the apply
            # document and must stay exactly the shape the schema describes. The parameters are
            # mandatory, so a README that claims a complete read cannot be written by forgetting one.
            # The role policy selection's entries follow the Entra ID entries, as in the output object.
            # The members and owners the group reader left out as PIM for Groups access go into the
            # README alone too, per group by name, for the groups inventory.json writes (BL-125), and
            # so do the role assignments at the root scope the walk left out (BL-126), and the names two
            # or more objects share, with their counts (BL-131), and the role assignments written with
            # principalStatus (BL-133), and the role assignments at a scope no document can declare (A13,
            # A15), and the groups that use PIM for Groups in a restricted management unit (BL-134), and the
            # Azure Lighthouse delegations (Sprint 11 step 6b, BL-133), and the subscriptions of another tenant the
            # walk did not read (BL-150, A19). The role assignment principals that could not be read follow the
            # Entra ID entries and precede the role policy selection's, the subscriptions whose home tenant could
            # not be read follow those, then the Azure Lighthouse reads that failed, and the service principal
            # access parts that could not be read come last of all (Sprint 11 step 8), as in the output object.
            (Get-OERInventoryReadme -IncompleteReads (@($IncompleteReads) + @($UnreadPrincipalReads) + @($RolePolicySelectionReads) + @($HomeTenantUnread) + @($LighthouseUnread) + @($SpAccessUnread)) -SkippedScopes @($SkippedScopes) -SkippedEligibilityScopes @($SkippedEligibilityScopes) -PimLeftOut $ReadmePimLeftOut -RootScopeAssignments $RootScopeAssignments -SharedNames $SharedNames -UnresolvedPrincipalAssignments $UnresolvedPrincipalAssignments -UndeclarableScopeAssignments $UndeclarableScopeAssignments -RestrictedUnitPimGroups $RestrictedUnitPimGroups -LighthouseDelegations $LighthouseDelegations -ForeignSubscriptions $ForeignSubscriptions @ReadmeSpAccessParams) |
                Set-Content -Path (Join-Path $BundlePath 'README.md') -Encoding utf8
        }
        $WrittenFiles.Add('README.md')

        # --- Self-check: prove inventory.json round-trips through the apply schema ---
        try {
            $Validation = Test-OERStructureSchema -Document $Canonical
            if (-not $Validation.Valid) {
                Write-Warning "inventory.json did not pass apply-schema validation (run Test-OERStructure on it). First issue: $(@($Validation.Errors)[0].Message)"
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # The self-check is the only thing that proves inventory.json can be fed back through
            # the apply engine, so its failure has to be visible: a silent catch made an unvalidated
            # bundle indistinguishable from a validated one.
            Write-Warning "Could not run the apply-schema self-check on inventory.json: $($PSItem.Exception.Message)"
        }

        $Out = [PSCustomObject]@{
            # Under -WhatIf the directory was never created, so Resolve-Path would fail; report the
            # planned absolute path instead so the plan names the exact location. $BundlePath can
            # already be rooted (e.g. an absolute -OutputPath), and Join-Path (unlike
            # [IO.Path]::Combine) does not special-case a rooted child, so that case is resolved
            # directly rather than joined onto the current directory.
            BundlePath             = if ($ShouldWrite) {
                (Resolve-Path $BundlePath).Path
            } elseif ([System.IO.Path]::IsPathRooted($BundlePath)) {
                [System.IO.Path]::GetFullPath($BundlePath)
            } else {
                [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $BundlePath))
            }
            TenantId               = $TenantLabel
            Generated              = $Stamp
            Groups                 = @($Canonical.Groups).Count
            AdministrativeUnits    = @($Canonical.AdministrativeUnits).Count
            Catalogs               = @($Canonical.Catalogs).Count
            AccessPackages         = @($Canonical.AccessPackages).Count
            AccessReviews          = @($Canonical.AccessReviews).Count
            DirectoryRoleManagementPolicies = @($Canonical.DirectoryRoleManagementPolicies).Count
            DirectoryRoleAssignments        = @($Canonical.DirectoryRoleAssignments).Count
            RoleAssignments        = @($Canonical.RoleAssignments).Count
            RoleManagementPolicies = @($Canonical.RoleManagementPolicies).Count
            RosterCount            = @($Roster).Count
            ScopeCount             = $ScopeCount
            ScopesEnumerated       = $ScopesEnumerated
            SkippedScopes          = @($SkippedScopes)
            AzurePimEligibility    = @($AzureEligibilities).Count
            SkippedEligibilityScopes = @($SkippedEligibilityScopes)
            # The Entra ID entries first, in their documented order, then the role assignment principals
            # that could not be read (BL-133), then the scopes where role management policies that could
            # not be judged were kept (BL-107), then the subscriptions whose home tenant could not be read
            # (BL-150, A19), then the Azure Lighthouse reads that failed (Sprint 11 step 6b, BL-133), and last
            # the service principal access parts that could not be read (Sprint 11 step 8).
            IncompleteReads        = @($IncompleteReads) + @($UnreadPrincipalReads) + @($RolePolicySelectionReads) + @($HomeTenantUnread) + @($LighthouseUnread) + @($SpAccessUnread)
            Files                  = $WrittenFiles.ToArray()
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryBundle')
        $Out

        # Emitted AFTER the summary so a caller still receives the bundle object it has to inspect,
        # then learns the coverage is incomplete. A warning alone left $? true, -ErrorAction Stop
        # inert and a try/catch seeing success, which is how a heavily truncated bundle reached the
        # LLM -> Invoke-OERStructure workflow looking exactly like a full tenant snapshot.
        if ($SkippedScopes.Count -gt 0 -or $SkippedEligibilityScopes.Count -gt 0 -or $IncompleteReads.Count -gt 0 -or $UnreadPrincipalReads.Count -gt 0 -or $RolePolicySelectionReads.Count -gt 0 -or $HomeTenantUnread.Count -gt 0 -or $LighthouseUnread.Count -gt 0 -or $SpAccessUnread.Count -gt 0) {
            $PartialParts = [System.Collections.Generic.List[string]]::new()
            # A '<...>' entry is not a scope that failed to READ: it names the whole walk that could not
            # start, or a level of the tree (management groups, subscriptions) that could not be LISTED,
            # so none of its scopes was enumerated. Counting it as "N of M scopes" would misstate which
            # scopes were read.
            $WalkFailed = (@($SkippedScopes) + @($SkippedEligibilityScopes)) -contains '<all Azure scopes: scope enumeration failed>'
            $DescribeSkip = {
                param([string[]]$Skipped, [string]$What)
                $Read = @($Skipped | Where-Object { -not ([string]$_).StartsWith('<') })
                $Levels = @($Skipped | Where-Object { ([string]$_).StartsWith('<') })
                $Parts = @()
                if ($Read.Count -gt 0) { $Parts += "$($Read.Count) of $ScopesEnumerated Azure scopes could not be read$What" }
                if ($Levels.Count -gt 0) { $Parts += "$($Levels.Count) level(s) of the Azure scope tree could not be listed, so none of their scopes was walked$What" }
                $Parts -join ', and '
            }
            if ($SkippedScopes.Count -gt 0) {
                # The "missing data is absent from ... Skipped: ..." clause is appended to BOTH
                # arms, not folded into the enumerated one. A failed scope WALK is exactly the case
                # where the operator most needs to be told which files are short and what was
                # skipped; burying that inside the $ScopesEnumerated -gt 0 arm silently drops it
                # from the louder of the two failures.
                $ScopeDetail = if (-not $WalkFailed) {
                    & $DescribeSkip @($SkippedScopes) ''
                } else {
                    'the Azure scope walk could not be started, so no Azure scope was read'
                }
                $PartialParts.Add(
                    "$ScopeDetail, and the missing data is absent from roleAssignments.json and " +
                    "roleManagementPolicies.json. Skipped: $($SkippedScopes -join ', ')")
            }
            if ($SkippedEligibilityScopes.Count -gt 0) {
                # A separate clause, not folded into the roleAssignments/roleManagementPolicies one
                # above: the eligibility read (R4) runs as its own pass over the same scope list, so a
                # scope can fail here without having failed the role-assignment walk, or vice versa,
                # and the operator needs to know which FILE is short. Same two-arm split as the
                # roleAssignments/roleManagementPolicies clause above, for the same reason: a failed
                # scope WALK (no tree at all) reads differently from N of M individual scopes failing
                # the eligibility read specifically.
                $EligDetail = if (-not $WalkFailed) {
                    & $DescribeSkip @($SkippedEligibilityScopes) ' for azurePimEligibility.json'
                } else {
                    'the Azure scope walk could not be started, so no scope was read for azurePimEligibility.json'
                }
                $PartialParts.Add(
                    "$EligDetail, and their eligible assignments are absent from it. " +
                    "Skipped: $($SkippedEligibilityScopes -join ', ')")
            }
            if ($IncompleteReads.Count -gt 0) {
                # The count is of ENTRIES, not collections: one Get-OERInventory run raises one
                # InventoryPartial error naming every triple it lost, and the Groups read is one
                # entry naming every group collection it lost, so a single entry here can stand for
                # seven unread collections; the groupsRoster entry is this cmdlet's own and not a
                # Get-OERInventory report at all. Saying "N collection read(s) failed" made
                # this message disagree with the seven triples printed right after it, and with
                # Get-OERInventory's own "7 collection(s)" on the same run. The help already states
                # the entry-per-report rule; the message now agrees with it.
                $IncompletePart = "$($IncompleteReads.Count) partial Entra ID read entry(ies) name collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are NOT stated as facts in the bundle -- one entry can name several collections, so read the entries rather than this count: $($IncompleteReads -join '; '). A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched; a path ending in scopedRoles/principalType is not such a key: it names a unit some or all of whose scoped role rows were written without principalType, and whose scopedRoles is not null. A section named alone is written as an empty array, which does not mean the tenant has none, and the entry groupsRoster means groupsRoster.json is empty since the group roster could not be read"
                # WHY the group collections are missing. The group reader writes no error record, so
                # this message is the only error that carries its causes (the verbose stream shows
                # each as it is seen, and Get-OERInventory's own partial message carries the causes of
                # the other sections): the cause is what tells a 429 (retry the export) from a 403
                # (grant a scope). Format-OERUnreadCauseClause owns the wording,
                # the deduplication and the cap, and returns an empty string when there is none. Its
                # clause ends with a period, which is trimmed here because the parts are joined with
                # one below.
                if ($GroupRead) {
                    $GroupCauseClause = Format-OERUnreadCauseClause -Cause @($GroupRead.Causes) -Label 'Causes of the unread group reads'
                    if ($GroupCauseClause) { $IncompletePart += '.' + $GroupCauseClause.TrimEnd('.') }
                }
                $PartialParts.Add($IncompletePart)
            }
            if ($UnreadPrincipalReads.Count -gt 0) {
                # A clause of its own (BL-133), not folded into the Entra ID one above, whose count and
                # wording stay over the Entra ID entries only: these are rows of roleAssignments.json, each
                # written by its principal's object id. The causes are the ones the per-scope reads handed
                # to the run context; Format-OERUnreadCauseClause owns their wording, deduplication and cap,
                # and its trailing period is trimmed, as above, because the parts are joined with one.
                $PrincipalPart = "$($UnreadPrincipalReads.Count) role assignment principal read(s) failed, so each principal is written by its object id -- " +
                    'with no principalStatus where its lookup through directoryObjects/getByIds failed, and as Unresolved where only the read of ' +
                    "the directory's deleted items failed: $($UnreadPrincipalReads -join '; ')"
                $PrincipalCauseClause = Format-OERUnreadCauseClause -Cause $UnreadPrincipalCauses -Label 'Causes of the unread principal lookups'
                if ($PrincipalCauseClause) { $PrincipalPart += '.' + $PrincipalCauseClause.TrimEnd('.') }
                $PartialParts.Add($PrincipalPart)
            }
            if ($RolePolicySelectionReads.Count -gt 0) {
                # A clause of its own (BL-107), not folded into the Entra ID one above, whose count and
                # wording stay over the Entra ID entries only: these are Azure scopes, and no policy that
                # could not be judged was left out for them -- more was kept than the selection would
                # keep. It does not claim every policy at such a scope was kept: a scope is named also
                # when only one row could not be judged, and the other unused, unchanged policies there
                # are still left out.
                $PartialParts.Add(
                    "at $($RolePolicySelectionReads.Count) Azure scope(s) every role management policy that could not be judged was kept, none of them left out, " +
                    'since whether its role is used there, or whether it was changed, could not be read -- where a scope''s role assignment or ' +
                    'eligibility read failed, that is every policy of a role neither used nor changed there -- so ' +
                    'roleManagementPolicies.json may hold policies of roles that are neither used nor changed at those scopes: ' +
                    ($RolePolicySelectionReads -join '; '))
            }
            if ($HomeTenantUnread.Count -gt 0) {
                # A clause of its own (BL-150, A19), after the role policy selection one and before the Lighthouse
                # one: these subscriptions were not walked, since whether each belongs to this tenant could not be
                # read, so nothing of them is in the bundle, which does not mean they hold nothing. The causes are
                # the reasons Get-OERSubscriptionHomeTenant gave; Format-OERUnreadCauseClause owns their wording,
                # deduplication and cap, and its trailing period is trimmed, as above, because the parts are joined
                # with one.
                $HomeTenantPart = "$($HomeTenantUnread.Count) Azure subscription(s) were not walked, since whether each belongs to this tenant could not be read, so none of their role assignments, role management policies, PIM eligibilities or Azure Lighthouse delegations is in the bundle: $($HomeTenantUnread -join '; ')"
                $HomeTenantCauseClause = Format-OERUnreadCauseClause -Cause $HomeTenantCauses.ToArray() -Label 'Causes of the unread subscription tenants'
                if ($HomeTenantCauseClause) { $HomeTenantPart += '.' + $HomeTenantCauseClause.TrimEnd('.') }
                $PartialParts.Add($HomeTenantPart)
            }
            if ($LighthouseUnread.Count -gt 0) {
                # A clause of its own (Sprint 11 step 6b, BL-133), after the role policy selection one and not
                # folded into the Entra ID one, whose count and wording stay over the Entra ID entries only:
                # these are Azure scopes and roles of lighthouseDelegations.json. A subscription is read whole or
                # not at all, so a scope named here has no delegation in the file, which does not mean it has
                # none; a role named here has its roleName written as null wherever it appears. The causes are
                # the ones the reader returned; Format-OERUnreadCauseClause owns their wording, deduplication
                # and cap, and its trailing period is trimmed, as above, because the parts are joined with one.
                $LighthousePart = "$($LighthouseUnread.Count) Azure Lighthouse read(s) failed, so lighthouseDelegations.json holds no delegation of a scope named here and writes the name of a role named here as null: $($LighthouseUnread -join '; ')"
                $LighthouseCauseClause = Format-OERUnreadCauseClause -Cause $LighthouseCauses.ToArray() -Label 'Causes of the unread Azure Lighthouse reads'
                if ($LighthouseCauseClause) { $LighthousePart += '.' + $LighthouseCauseClause.TrimEnd('.') }
                $PartialParts.Add($LighthousePart)
            }
            if ($SpAccessUnread.Count -gt 0) {
                # A clause of its own (Sprint 11 step 8), after the Lighthouse one and last of all, not folded into
                # the Entra ID one, whose count and wording stay over the Entra ID entries only: these are parts of
                # servicePrincipalAccess.json, each read whole or not at all and written as null when not read. The
                # causes are the ones the reader returned; Format-OERUnreadCauseClause owns their wording,
                # deduplication and cap, and its trailing period is trimmed, as above, because the parts are joined
                # with one.
                $SpAccessPart = "$($SpAccessUnread.Count) service principal access part(s) could not be read, so servicePrincipalAccess.json writes them as null: $($SpAccessUnread -join '; ')"
                $SpAccessCauseClause = Format-OERUnreadCauseClause -Cause $SpAccessCauses.ToArray() -Label 'Causes of the unread service principal access reads'
                if ($SpAccessCauseClause) { $SpAccessPart += '.' + $SpAccessCauseClause.TrimEnd('.') }
                $PartialParts.Add($SpAccessPart)
            }
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "This inventory bundle is PARTIAL: $($PartialParts -join '. '). " +
                    'Do not treat it as a full tenant snapshot.')) `
                -ErrorId 'InventoryPartial' `
                -Category LimitsExceeded `
                -TargetObject $Out.BundlePath `
                -Cmdlet $PSCmdlet
        }
    }
}
