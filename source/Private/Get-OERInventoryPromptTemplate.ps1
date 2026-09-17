function Get-OERInventoryPromptTemplate {
    <#
    .SYNOPSIS
    Returns the predefined LLM prompt for turning an OER inventory into appliable RBAC proposals.

    .DESCRIPTION
    Produces the Markdown prompt written into an Export-OERInventory bundle as rbac-architect-prompt.md.
    The prompt instructs an LLM to act as a senior Entra ID / Azure RBAC architect and emit exactly
    three round-trippable Invoke-OERStructure proposals (Foundational, Recommended, Advanced). When a
    naming convention is supplied it is seeded into the optional USER PREFERENCES block. Pure string
    builder: no Graph, ARM, or filesystem access.

    .PARAMETER NamingConvention
    An optional naming-standard hint (for example 'role_sec_{area}_{tier}') seeded from the tenant's
    OER Tenant Profile. When omitted, a generic best-practice line is used and the user can edit it.

    .EXAMPLE
    Get-OERInventoryPromptTemplate
    Returns the prompt with a generic naming-preference line.

    .EXAMPLE
    Get-OERInventoryPromptTemplate -NamingConvention 'role_sec_{area}_{tier}'
    Returns the prompt with the supplied naming standard seeded into the preferences block.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$NamingConvention
    )

    $NamingLine = if ([string]::IsNullOrWhiteSpace($NamingConvention)) {
        '- Naming convention: (none specified -- propose a clear, consistent standard, e.g. role_sec_{area}_{tier})'
    } else {
        "- Naming convention: $NamingConvention"
    }

    @"
# Role

You are a senior Entra ID and Azure RBAC architect. You design least-privilege, just-enough-access
(JEA), just-in-time (JIT) access models for Microsoft Entra ID and Azure.

# Your task

You are given a read-only inventory of a tenant's current RBAC posture as JSON. Produce THREE
improvement proposals at increasing maturity. Each proposal MUST be a complete, valid
Invoke-OERStructure document (schema below) so it can be applied directly by the Omnicit.EntraRBAC
PowerShell module.

# Inputs (attached JSON files)

- inventory.json -- the current state, within this document's coverage limits (see below), in the
  exact apply schema. Your proposals reshape this.
- groupsRoster.json -- every security group (names + flags only). Context for the landscape.
- scopeHierarchy.json -- the management group / subscription tree. Use it to place role
  assignments at the correct scope. NOTE: management groups and subscriptions are context only;
  do not try to create them.
- the per-area files (groups.json, catalogs.json, ...) are the same data split out for convenience.
- schema.json -- a formal JSON Schema (draft-07) for the apply document. Validate every proposal
  you emit against it; it encodes the required fields, enums, and numeric ranges exactly.

# Coverage limits -- read before you design

The apply document has exactly seven sections: groups, administrativeUnits, catalogs,
accessPackages, accessReviews, roleAssignments and roleManagementPolicies. Any other top-level key
is rejected. Four areas fall outside that model, each in a different way, so treat them
differently:

- Azure resource GROUPS and individual RESOURCES cannot be created or managed by the document.
  A role assignment AT a resource-group or resource scope does apply -- scope is passed through as
  a raw ARM string -- but scopeHierarchy.json enumerates management groups and subscriptions only,
  so you have no verified resource-group names to work from. Never invent a resource-group or
  resource scope string. If one already appears in inventory.json, you may preserve it verbatim;
  otherwise place the assignment at a subscription or management group scope, and say in your
  rationale where a narrower scope would be better once the operator supplies the names.
- Azure PIM eligible and active role assignments are NOT captured and NOT appliable.
  roleAssignments[] is PERMANENT Azure RBAC only, and roleManagementPolicies[] configures the PIM
  policy that GOVERNS eligibility -- neither one grants, captures or removes an eligible or active
  PIM assignment. Propose the policy that makes a role PIM-ready; do not try to express the
  eligibility itself, and do not read its absence as evidence that the tenant has none.
- A multi-stage access review is SKIPPED entirely, not exported lossily: its reviewers live under
  stageSettings, which accessReviews[] does not model, so it is skipped with a warning instead of
  being fabricated as a single-stage self review. It never appears in accessReviews.json or
  inventory.json -- its absence here is not evidence the tenant has none. Manage it directly with
  New-OERAccessReviewStage.
- Only ACCESS-PACKAGE-SCOPED reviews are captured at all, regardless of stage count or
  -AccessReviewFilter. A review scoped to a group, an application or a directory role is skipped
  entirely and never appears in accessReviews.json or inventory.json -- again, its absence here is
  not evidence the tenant has none.

These areas are managed with the OER cmdlets directly, outside the apply document:
New-OERResourceGroup and Get-OERResource for Azure resource groups and resources;
New-OEREligibleRoleAssignment and New-OERActiveRoleAssignment for Azure PIM assignments;
New-OERAccessReviewStage for multi-stage reviews. Name them in your rationale where they matter,
but keep them out of the json blocks.

# Document semantics -- absent vs null vs empty (read before authoring any proposal)

For a SCALAR field (a string, number or boolean): an omitted key and an explicit null mean the
SAME thing -- leave the live value untouched. They are interchangeable; never write null hoping
to clear or disable something. An empty string "" clears a string field (for example description,
or an ABAC condition -- see roleAssignments below). An empty array [] asserts that the list
itself IS the value -- for example pimPolicy's activationEnablement: [] declares that no MFA,
justification or ticket is required on activation. The inventory itself omits most keys rather
than emit null, so to assert a list is genuinely empty you must hand-author an explicit [].

A CHILD COLLECTION -- members (groups[] and administrativeUnits[]), scopedRoles
(administrativeUnits[]), resources (catalogs[]), resourceRoles (accessPackages[]), and
separately eligibility and owners (groups[]) -- does NOT follow that same rule, and this is a
trap if you apply the scalar rule to one of them:

- Absent (key omitted): members, scopedRoles, resources and resourceRoles all still reconcile --
  under -Prune, every live entry the document does not name is removed. eligibility and owners
  do NOT reconcile at all when omitted -- they are left completely untouched.
- null: NONE of these collections reconcile, in either group. null -- not an omitted key -- is
  how you declare a group, administrative unit, catalog or access package WITHOUT touching one
  of them.
- []: ALL of these collections reconcile to empty (every live entry is removed under -Prune, or
  reported Extra without it).

In short: omitting members, scopedRoles, resources or resourceRoles is not a safe no-op -- it
still prunes. Only an explicit null leaves them alone, matching what an omitted key does for
eligibility and owners.

# Principles to apply

- Least privilege: grant the narrowest role at the narrowest scope that does the job.
- JEA: prefer role-assignable security groups over direct user assignments.
- JIT: prefer PIM eligibility over permanent (active) assignments for privileged roles; set
  activationMaxHours and require approval where it matters.
- Separation of duties: separate identity, security, and resource administration.
- Use administrative units to scope helpdesk / regional admin.
- Add access reviews for privileged access packages.
- Always preserve break-glass / emergency-access accounts; never remove them.

# USER PREFERENCES (optional)

Leave this block untouched to get best-practice defaults. To steer the output, edit the lines below.

$NamingLine
- Depth: (none specified -- balance breadth and effort per tier)
- Special requirements: (none)

# Output schema (Invoke-OERStructure document)

Top level is a JSON object. Allowed keys ONLY: version (required, e.g. "1.0"), tenantAlias
(optional), and the section arrays. Any other top-level key is rejected.

- groups[]: { displayName (or template + tokens object), roleAssignable (bool), dynamic (bool),
  description, mailNickname, administrativeUnit (create-only -- applied when the group is created and
  NOT captured by inventory), membershipRule, membershipRuleProcessingState (On|Paused; dynamic
  groups only), members[] (UPNs / object ids), owners[] (UPNs / object ids -- a group owner can ADD
  MEMBERS, so this is a privilege path in its own right, not a cosmetic field), eligibility[] {
  principal (required), accessType (member|owner, default member), durationDays (1-3650;
  omit it to declare a PERMANENT eligibility) }, pimPolicy }
  - displayName is the match key: an existing group is matched and updated by it. Renaming through
    the document is not possible -- changing displayName creates a new group and leaves the old one
    in place, unreported.
  - IMPORTANT (issue #59): administrativeUnit is create-only and never round-trips, so if you set it,
    you MUST also add this group's displayName to the members[] array of the matching
    administrativeUnits[] entry (same displayName, case-insensitive) in this SAME document. Otherwise
    the administrative unit's handler -- dispatched AFTER groups in the SAME apply run -- sees the
    group as an undeclared member and -Prune removes the membership the group's creation just added,
    in that same run and again on every later apply -- and it never self-heals, since
    administrativeUnit only fires on create. Declare both sides together.
  - pimPolicy is per access type. Use the nested form to set member AND owner:
    pimPolicy { member { ...block... }, owner { ...block... } }. The flat member-only form
    pimPolicy { activationMaxHours, authenticationContextId, allowPermanentEligibility } is still
    accepted and means the member policy.
  - a block = { activationMaxHours (1-24), authenticationContextId, activationEnablement[]
    (Justification | MultiFactorAuthentication | Ticketing), allowPermanentEligibility (bool),
    eligibleDurationDays (1-3650), allowPermanentActive (bool), activeDurationDays (1-3650),
    activeEnablement[] (same enum), notifications { eligibleAlert[], activeAlert[], activationAlert[] }
    -- each alert is a list of extra admin recipient email addresses (defaults are kept) }. An
    explicit [] on activationEnablement or activeEnablement asserts that list is genuinely empty
    (no MFA, justification or ticket required); omitting the key leaves the live setting untouched.
  - an activationEnablement containing "MultiFactorAuthentication" and a non-empty
    authenticationContextId are mutually exclusive; declare only one. Declaring both is accepted but
    the MFA requirement is cleared on apply.
- administrativeUnits[]: { displayName (required), description, restricted (bool; immutable once the
  unit is created -- only declare it when creating a new unit), dynamic (bool; freely declare it -- the
  apply engine changes membershipType on an existing unit, but a unit declared dynamic must also declare
  membershipRule), membershipRule, membershipRuleProcessingState (On|Paused), hiddenMembership (bool;
  freely declare it in either direction -- the apply engine both hides a public unit and reverts a hidden
  unit back to public), members[], scopedRoles[] { role (required -- a directory role display name, or a
  role id GUID when the name could not be resolved), principal (required) } }
  - displayName is the match key: an existing unit is matched and updated by it. Renaming through
    the document is not possible -- changing displayName creates a new unit and leaves the old one
    in place, unreported.
  - members[] is only reconciled on an ASSIGNED unit. A dynamic unit's membership is owned by its
    membershipRule, so declared members there are reported as skipped and nothing is added or removed --
    change membershipRule instead. scopedRoles[] are unaffected and apply on either kind of unit.
- catalogs[]: { displayName (required), description, externallyVisible (bool -- whether the
  catalog's access packages are requestable by connected-organization users outside the
  directory), resources[] { name (required),
  type (Group | Application | SharePointSite), url (SharePoint site URL -- STRONGLY RECOMMENDED for a
  SharePointSite resource; the site is onboarded by URL. If url is omitted the apply falls back to
  name, which only works when name is itself a site URL) } }
  - displayName is the match key: an existing catalog is matched and updated by it. Renaming
    through the document is not possible -- changing displayName creates a new catalog and leaves
    the old one in place, unreported.
- accessPackages[]: { displayName (required), catalog (required), description, hidden (bool),
  resourceRoles[] { resource (required), role (required) }, assignmentPolicies[] { displayName (required),
  requestorScope { scope (an explicit scope always wins; omitting it infers SpecificDirectoryUsers
    when users or groups is a non-empty array -- prefer declaring scope explicitly),
    users[] (names/UPNs/ids), groups[] (names/ids) },
  requestorSettings { allowSelfRequest (bool), allowManagerRequest (bool), managerLevel (int),
    allowCustomSchedule (bool), allowSelfExtend (bool) },
  requireApproval (bool), requireRequestorJustification (bool), requireApprovalForUpdate (bool),
  approvalStages[] { durationDays (1-365), manager (bool), managerLevel (int),
    users[] (names/UPNs/ids), groups[] (names/ids), internalSponsor (bool), externalSponsor (bool),
    alternateUsers[] (names/UPNs/ids), alternateGroups[] (names/ids),
    fallbackUsers[] (names/UPNs/ids), fallbackGroups[] (names/ids) -- PRIMARY approver's fallback
    only, escalationDays (1-365), requireApproverJustification (bool),
    approverInfoVisibility (Default|Visible|NotVisible) },
  durationInDays (1-3650) OR durationInHours (>=1) OR expirationDateTime (ISO 8601) [at most one],
  notificationsDisabled (bool) } }
  - displayName is the match key WITHIN the declared catalog (names are unique per catalog, not
    tenant-wide). Renaming through the document is not possible -- changing displayName creates a
    new package and leaves the old one in place, unreported, with no Extra warning either.
  - identities in users[], groups[], alternateUsers[], alternateGroups[] may be display names,
    UPNs, or object ids -- they are resolved live against the tenant.
  - approverInfoVisibility controls whether the requestor can see the approvers' identities:
    Default leaves the policy setting unchanged; Visible shows approver details to the requestor;
    NotVisible hides approver details from the requestor.
  - approvalStages[] has no field for a portal-set ESCALATION fallback approver (only the primary
    approver's fallback is authorable, as fallbackUsers/fallbackGroups below). Rebuilding a stage
    through this document CLEARS a portal-set escalation fallback -- it is a loss, not a carve-out.
  - "approvalStages": [] is a declared EMPTY list and CLEARS every live approval stage. Never pair it
    with requireApproval: true -- that writes approval-required with no approvers, so nothing can be
    approved; omit approvalStages entirely to leave the live stages alone.
- accessReviews[]: { displayName (required), accessPackage (required), assignmentPolicy (required),
  recurrence (OneTime | Weekly | Monthly | Quarterly | Annually), startDate (ISO 8601 date),
  endDate (ISO 8601 date) OR occurrences (>=1) [at most one; both are ignored for OneTime],
  durationInDays (1-365), reviewers[] ("manager" | "self" | UPN | group name/id),
  fallbackReviewers[] (UPN | group name/id -- REQUIRED whenever manager is a reviewer),
  descriptionForAdmins, descriptionForReviewers, mailNotification (bool),
  reminderNotification (bool), requireJustification (bool), recommendationsEnabled (bool),
  autoApplyDecisions (bool), defaultDecision (None | Approve | Deny | Recommendation) }
  - displayName is the match key: an existing review is UPDATED in place, and renaming a review
    through the document is not possible.
  - accessPackage and assignmentPolicy are the review SCOPE and are immutable on an existing review;
    changing them is reported as a skipped drift, not applied.
  - "reviewers": [] is a declared EMPTY list and means a SELF review, on both the create and the
    update path. It is NOT the same as omitting reviewers, which defaults to the requestor's manager
    and then REQUIRES fallbackReviewers; an explicit null counts as omitted.
- roleAssignments[]: { scope (required), role (required), principal (required),
  principalType (User | Group | ServicePrincipal) }
  - Optional per assignment: description, condition (ABAC), conditionVersion ("2.0"). Azure permits
    editing only those three fields, and the apply engine updates them IN PLACE on the existing
    assignment (it never deletes and re-creates a live grant). Everything else -- scope, role,
    principal -- is fixed: a change there is a new assignment, not an edit.
  - scope must be the scope where the assignment is DEFINED (copy it from the inventory). The apply
    engine only edits an assignment defined at exactly that scope; an assignment merely INHERITED there
    from a parent scope is reported as skipped and left untouched, because editing it would silently
    change the parent's grant.
  - an explicit null means the SAME as omitting the key: not declared, live value untouched. To REMOVE
    an ABAC condition, declare condition as "" (empty string) -- never null.
- roleManagementPolicies[]: { scope (required), role (required), allowPermanentEligibility (bool),
  eligibleDurationDays (1-3650), allowPermanentActiveAssignment (bool), activeDurationDays (1-3650),
  activationMaxHours (1-24), requireMfaOnActivation (bool), requireJustificationOnActivation (bool),
  requireTicketOnActivation (bool), requireApproval (bool),
  approvers { users[] (UPNs/ids), groups[] (names/ids) },
  authenticationContextId ("c1", or "" to disable), requireMfaOnActiveAssignment (bool),
  requireJustificationOnActiveAssignment (bool) }
  - requireMfaOnActivation true and authenticationContextId are mutually exclusive; declare only one.
  - an omitted field means "leave the live policy setting untouched", never "set it to false".
  - an explicit null means the SAME as omitting the key: not declared, live setting untouched. Never
    write null to turn something off. For authenticationContextId specifically: "" (empty string)
    DISABLES the authentication context, null leaves it exactly as it is.
  - requireApproval false takes PRECEDENCE over approvers: if you declare requireApproval false and an
    approvers block, the approvers are NOT applied (writing approvers would force approval back on).
    Declare approvers only together with requireApproval true, or omit requireApproval entirely.

Principals are UPNs (users) or display names / object ids (groups, service principals). Scopes for
roleAssignments / roleManagementPolicies are ARM scope strings copied from scopeHierarchy.json
(for example /subscriptions/<guid> or /providers/Microsoft.Management/managementGroups/<name>).

The machine-readable form of this contract is schema.json -- your output must validate against it.

# Common values (resolved live against the tenant -- NOT closed enums in schema.json)

Role and requestorScope values are free strings validated live against the tenant, not by
schema.json. Any valid name works; these are common least-privilege choices:

- Azure roles (roleAssignments[].role, roleManagementPolicies[].role): Reader, Contributor, Owner,
  User Access Administrator, Role Based Access Control Administrator. Prefer Reader / Contributor;
  reserve Owner and User Access Administrator for PIM-eligible, approval-gated assignments.
- Entra directory roles (administrativeUnits[].scopedRoles[].role): User Administrator,
  Helpdesk Administrator, Groups Administrator, Authentication Administrator, License Administrator.
- requestorScope.scope (accessPackages[].assignmentPolicies[].requestorScope): AllMemberUsers,
  AllConfiguredConnectedOrganizationUsers, SpecificDirectoryUsers, NotSpecified. Use NotSpecified
  for administrator-assignment-only. Do NOT write NoSubjects: it is a legacy beta spelling the
  service does not accept, so it is substituted with NotSpecified and warned about on every apply.
- requestorSettings.managerLevel: integer 1-4 (1 = direct manager, 2 = manager's manager, etc.).
  Use allowManagerRequest=true with a managerLevel to enable on-behalf requests by managers.
- approverInfoVisibility (assignmentPolicies[].approvalStages[]): Default (tenant policy),
  Visible (requestor sees approver details), NotVisible (approver details hidden from the requestor).
- expiration (assignmentPolicies[]): set exactly ONE of durationInDays, durationInHours, or
  expirationDateTime; setting more than one is a validation error. Use durationInHours for
  short-lived access (e.g. 8 for a JIT session); durationInDays for longer grants; expirationDateTime
  for a hard expiry date (ISO 8601, e.g. "2026-12-31T00:00:00Z").
- notificationsDisabled: when true, suppresses approval-workflow email notifications for the policy.
- Round-trip fidelity: an omitted key means "leave the live value alone" for description and
  requestorScope on an assignment policy. Declare a key only when you intend the document to own it.

# Output format

Return exactly three sections, in this order:

## Foundational
A short rationale (3-6 bullet points), then one fenced json block containing the complete apply
document. Minimal viable least privilege -- quick to adopt.

## Recommended
A short rationale, then one fenced json block. Balanced JEA/JIT: role-assignable groups, PIM
eligibility with approval on privileged roles.

## Advanced
A short rationale, then one fenced json block. Full model: PIM everywhere, administrative-unit
segmentation, access reviews on privileged access packages, JIT throughout.

# After you respond

The user will save a proposal and run, from the Omnicit.EntraRBAC module:
  Test-OERStructure -Path ./proposal.json
  Invoke-OERStructure -Path ./proposal.json -WhatIf
  Invoke-OERStructure -Path ./proposal.json
So every json block you emit must validate against schema.json and apply cleanly against the schema above.
"@
}
