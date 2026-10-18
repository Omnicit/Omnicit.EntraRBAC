# Inventory -> LLM -> Apply workflow

`Export-OERInventory` reads your tenant's RBAC posture into a bundle you can hand to any LLM to get
three appliable improvement proposals. The loop is:

inventory -> LLM proposal -> Test-OERStructure -> Invoke-OERStructure

## 1. Export the inventory

```powershell
Import-Module Omnicit.EntraRBAC
Connect-OER -TenantId <tenant> -Interactive -IncludeARM   # optional; cmdlets auto-auth on first use
Export-OERInventory -OutputPath C:\Temp
```

This creates `C:\Temp\oer-inventory-<tenant>-<timestamp>\` containing:

- `inventory.json` -- canonical, round-trippable inventory (all sections).
- per-area JSON files (`groups.json`, `catalogs.json`, `directoryRoleManagementPolicies.json`,
  `directoryRoleAssignments.json`, ...).
- `groupsRoster.json`, `scopeHierarchy.json`, `azurePimEligibility.json`,
  `lighthouseDelegations.json` -- read-only context.
  `groupsRoster.json` lists every group in the tenant, of every type, one row per group with the
  keys `displayName`, `roleAssignable`, `dynamic`, `onPremisesSynced`, `memberCount`, `id`,
  `securityEnabled`, `mailEnabled`, `groupTypes`, `visibility` and `createdDateTime` (a UTC ISO 8601
  time); the `id` tells apart two groups that share a name.
  `azurePimEligibility.json` (the Azure PIM eligible role assignments at the walked scopes) is
  written only when an Azure section (`RoleAssignments` or `RoleManagementPolicies`) is included,
  and so is `lighthouseDelegations.json` (the Azure Lighthouse delegations at the walked
  subscriptions; see "Azure Lighthouse delegations" below). The Azure walk enters only the session
  tenant's own subscriptions: a subscription of another tenant is named in `README.md` and read
  into no file (see the same section).
- `servicePrincipalAccess.json` -- read-only context, written only when the export runs with
  `-IncludeServicePrincipalAccess`: the application permissions, delegated permission grants and
  owners of the tenant's service principals and app registrations (see "Service principal access"
  below).
- `schema.json` -- a formal JSON Schema (draft-07) for the apply document, so a proposal can be
  validated without the module (e.g. `Test-Json -Json (Get-Content proposal.json -Raw) -Schema (Get-Content schema.json -Raw)`).
- `rbac-architect-prompt.md` -- the predefined prompt.
- `README.md` -- explains the bundle, lists under "What this export could not read" everything the
  export could not read (or says that nothing was left unread), lists under "Role assignments at the
  root scope (elevated access)" the role assignments at the Azure root scope the export left out
  (see below), lists under "Names two or more objects share" every name the export left out because
  two or more objects carry it (see below), lists under "Role assignments whose principal the
  directory did not return", "Role assignments at a scope no document can declare", "Groups using
  PIM for Groups in a restricted management unit" and "Azure Lighthouse delegations (access from
  another tenant)" the findings described below, lists under "Subscriptions delegated from another
  tenant (not read)" the subscriptions of another tenant the export did not read (see "Azure
  Lighthouse delegations" below), gives under "Service principal access (read-only)" the row count
  of each part of `servicePrincipalAccess.json` when the export wrote it, and holds the next steps.
  These lists are written
  into this file only, never into `inventory.json` or any other JSON file, except the Azure
  Lighthouse delegations, which are the rows of `lighthouseDelegations.json`.

By default the Entra sections -- including the Microsoft Entra directory role sections,
`DirectoryRoleManagementPolicies` and `DirectoryRoleAssignments` -- plus tenant-wide
`RoleAssignments` are captured. The two directory role sections are Graph-only and never acquire an
ARM token by themselves. `DirectoryRoleManagementPolicies` exports the policy of every directory
role that is actually in use; add `-AllDirectoryRolePolicies` to export the policy of every
directory role instead. Add `RoleManagementPolicies` to `-Include` to also read Azure PIM policies
at every scope (slower); `roleManagementPolicies` then keeps a role's policy at a scope only when the
role has an active role assignment or a PIM eligibility exactly at that scope, or the policy has been
changed, at the cost of one more role assignment list per scope, and a policy that cannot be judged
is kept and its scope named in `IncompleteReads`. Add `-AllRolePolicies` to export the policy of
every Azure role at every scope instead. Only RBAC-relevant groups are detailed in `inventory.json`;
the full landscape is in `groupsRoster.json`. The export decides which groups are relevant before it
reads any group in full, so a group it finds not relevant costs two requests and has `memberCount`
`null` in the roster; use `-AllGroupsDetailed` to read and keep every group in full detail.
`-GroupFilter` narrows the groups `inventory.json` is read from and never widens them, and
`groupsRoster.json` is never filtered.
Add `-IncludeSyncedGroups` to also keep the security groups synchronized from on-premises Active
Directory (`onPremisesSynced: true`); `Invoke-OERStructure` writes nothing to such a group.

## 2. Ask an LLM

Open `rbac-architect-prompt.md`. Leave the `USER PREFERENCES (optional)` block untouched for
best-practice defaults, or set your naming standard and depth. Give the prompt, the bundle's
`README.md` and the JSON files to any capable LLM: the README's "What this export could not read"
section is where the bundle says which collections, objects and Azure scopes are unknown rather
than empty. It returns three proposals: Foundational, Recommended, Advanced -- each a
complete `Invoke-OERStructure` document.

## 3. Validate and apply

Save a proposal (for example `proposal.json`) and run:

```powershell
Test-OERStructure -Path .\proposal.json          # offline schema validation
Invoke-OERStructure -Path .\proposal.json -WhatIf # preview the changes
Invoke-OERStructure -Path .\proposal.json         # apply
```

A proposal that keeps the `tenantId` of `inventory.json` is applied only in the tenant the export came
from: `Invoke-OERStructure` refuses it anywhere else with `DocumentTenantMismatch`. To apply it in
another tenant, change `tenantId` to that tenant's ID or remove it first.

## Groups schema -- pimPolicy

Groups carry a `pimPolicy` object in the inventory and apply document. The field
names below are the DOCUMENT field names the apply engine reads -- they are not the
`Set-OERGroupPimPolicy` parameter names, which spell some of the same settings differently (for
example the document field `activationEnablement` is sent through the `-ActivationEnabledRules`
parameter). A document written with the cmdlet's parameter names instead of these field names is
not applied: the apply engine does not recognize them, and `Test-OERStructure` warns about the
unknown key (see below). The schema supports two forms:

**Flat (member-only, back-compat):**

```json
"pimPolicy": {
  "activationMaxHours": 8,
  "authenticationContextId": "c1",
  "allowPermanentEligibility": false,
  "eligibleDurationDays": 365,
  "allowPermanentActive": false,
  "activeDurationDays": 180,
  "activationEnablement": ["MultiFactorAuthentication", "Justification"],
  "activeEnablement": [],
  "notifications": {
    "eligibleAlert": [],
    "activeAlert": [],
    "activationAlert": []
  }
}
```

All fields are optional. Omitted fields are not patched -- the existing policy value is preserved.

**Nested member + owner:**

```json
"pimPolicy": {
  "member": {
    "activationMaxHours": 8,
    "allowPermanentEligibility": true
  },
  "owner": {
    "activationMaxHours": 1,
    "activationEnablement": ["MultiFactorAuthentication", "Justification", "Ticketing"],
    "allowPermanentEligibility": false,
    "eligibleDurationDays": 90,
    "requireApproval": true,
    "approvers": {
      "users": ["person1@example.com"],
      "groups": ["pim-approvers"]
    }
  }
}
```

The nested form lets you express different policies for members and owners in one apply document.
Supplying only `"member"` or only `"owner"` is valid; the other access type is left unchanged.

**Field reference:**

| Field | Type | Description |
|---|---|---|
| `activationMaxHours` | integer 1-24 | End-user activation window. |
| `authenticationContextId` | string or null | Conditional-access context required on activation (e.g. `"c1"`). Empty string disables it. |
| `activationEnablement` | string[] | Requirements on activation: `Justification`, `MultiFactorAuthentication`, `Ticketing`. |
| `activeEnablement` | string[] | Requirements on admin active assignment: same enum values. |
| `allowPermanentEligibility` | boolean | Allow permanent eligible assignments (no expiry). |
| `eligibleDurationDays` | integer 1-3650 | Max days for time-bound eligible assignments. |
| `allowPermanentActive` | boolean | Allow permanent active assignments (no expiry). |
| `activeDurationDays` | integer 1-3650 | Max days for time-bound active assignments. |
| `notifications.eligibleAlert` | string[] | Extra admin email addresses for the eligible-assignment alert. Defaults are always kept. |
| `notifications.activeAlert` | string[] | Extra admin email addresses for the active-assignment alert. Defaults are always kept. |
| `notifications.activationAlert` | string[] | Extra admin email addresses for the role-activation alert. Defaults are always kept. |
| `requireApproval` | boolean | Whether an activation of this access type must be approved. |
| `approvers.users` | string[] | Approving users, as user principal names or object ids. |
| `approvers.groups` | string[] | Approving groups, as display names or object ids. |

To require approval, declare `requireApproval: true`. Approvers declared without `requireApproval`
are written only when they differ from the live approvers, and writing them turns approval on --
so approvers that already match the live ones leave an approval-off policy off. An explicit
`requireApproval: false` in the same block wins over a declared `approvers` block: the approvers
are ignored rather than applied. Declaring only `approvers.users` or only
`approvers.groups` leaves the other side untouched on the live rule. Names are resolved to object
ids before comparison (and de-duplicated case-insensitively), so a UPN or a group display name in
the document does not cause the apply to report a change on every run once it has converged. A
group with no existing approval stage gets a new one with a 1-day timeout and approver
justification required; a group that already has a stage keeps that stage's own timeout and
justification setting. An unknown key inside a `pimPolicy` block -- including the five field names
this page used to document (`activationEnabledRules`, `activeEnabledRules`,
`eligibleAlertRecipients`, `activeAlertRecipients`, `activationAlertRecipients`) -- is reported as a
`Warning` by `Test-OERStructure`, with a "did you mean" hint at the current name for those five.

Microsoft Graph lists PIM-for-Groups policies for every group, including one never used with PIM for
Groups, and applying a `pimPolicy` that changes such a group's policy onboards the group to PIM for
Groups, which cannot be undone (Microsoft Graph documentation, "Onboarding groups to PIM for
Groups"). The inventory therefore exports a `pimPolicy` only for a group found to use PIM for
Groups: one with PIM eligibility, or one whose PIM-for-Groups policy has been modified (it carries a
`lastModifiedDateTime` or a `lastModifiedBy`). A group without a `pimPolicy` in the export therefore
was not found to use PIM for Groups (no PIM eligibility and no modified policy), or has no policy
the inventory could project. That is what the inventory found, not a guarantee: a group used only
through PIM active assignments, with untouched policies, is not found to use PIM for Groups either.
Whenever a read behind that answer failed -- the policy listing, or the group's PIM eligibility when
no modified policy was found -- the bundle's `IncompleteReads` names the group's `pimPolicy`. A
`pimPolicy` added for a group that does not use PIM for Groups yet onboards it the first time the
apply changes its policy: for a group that already exists, the apply writes a warning before that
change, and still makes it. A `pimPolicy` whose policy Graph does not list yet -- in practice a
group created moments ago -- is not silently skipped: the apply reports that access type `Failed`
(`PimPolicyNotFound`), and a re-run usually applies it. For a group created by the same apply run,
the engine first waits up to about 30 seconds for its policies to be listed and readable.

## Members and owners that PIM for Groups holds

`members` and `owners` in `inventory.json` hold a group's STANDING members and owners only. A member
or owner whose access PIM for Groups holds -- an activation, or another active assignment that is not
standing, such as a time-bound one -- is left out, and the bundle's `README.md` counts what was left
out for each group, by group name and never by principal, under "Members and owners left out as PIM
for Groups access". The prompt tells the model not to propose a principal that is eligible, or known
to hold the access through PIM for Groups, as a standing member or owner, and not to read a missing
activation as a removal.

- When the group's PIM assignments could not be read, the members and owners that are eligible for
  the same access are left out instead, and `groups/<name>/pimAssignments` is listed under "What this
  export could not read".
- When its eligibility could not be read either, a `members` collection that holds entries is `null`
  and an `owners` collection that holds entries is left out, both listed there. Keep the `null`, as
  for any unread collection. A `members` collection read empty is written as `[]`, and one written
  after only the assignment read failed lists the members that were not eligible.

`Invoke-OERStructure` does not add a declared member or owner that is not in the group and that PIM
for Groups holds or makes eligible for the same access: the entry is reported `Skipped`, with a
warning, also under `-WhatIf`. So an activation that a document from an earlier version lists under
`members` is not added while PIM for Groups still holds that principal or makes it eligible.
`-Prune` removes none: it reports `Skipped` with "prune withheld:" under `-Prune` and `Extra`
without. The apply engine is stricter than the export about what it could not read: when EITHER of a
group's PIM for Groups reads (its assignments or its eligibility) fails for a group that already
existed, nothing is added to or removed from that group's members and owners, whereas the export
writes `members` as `null` only when BOTH failed. A group the same run creates is not read, so no
member or owner declared for it is held back for PIM for Groups. When a standing membership is
meant, add it with `Add-OERGroupMember`. The read needs the permission
`PrivilegedAssignmentSchedule.Read.AzureADGroup`.

## Role assignments at the root scope

The Azure root scope `/` stands above every management group and subscription in the tenant, so a
role assignment there reaches every Azure resource. It is elevated access -- most often User Access
Administrator, which the Microsoft Entra setting "Access management for Azure resources" grants a
Global Administrator -- and a finding to review, not part of the RBAC model a proposal describes.

- **The export leaves it out.** The read at every management group and subscription returns a root
  assignment as inherited. `inventory.json` and `roleAssignments.json` never carry one. The export
  writes one warning for the whole walk that names each such assignment once, by role and principal
  and, when it is known, the principal type, and the bundle's `README.md` lists them, with their
  count, under "Role assignments at the root scope (elevated access)", or says that none was read.
- **The prompt treats it as a finding.** It tells the model never to keep, recreate or declare one,
  and to name what the README lists there in its rationale.
- **The validator warns.** `Test-OERStructure` reports a `roleAssignments` entry whose scope is `/`
  as a `Warning` at the entry's scope path; the finding does not make the document invalid. A
  `roleManagementPolicies` scope `/` is not reported.
- **The apply engine skips it.** `Invoke-OERStructure` reports such an entry `Skipped`, with a
  warning, before it looks up, reads or writes anything for it, the same under `-WhatIf`, and never
  prunes the root scope, with or without `-Prune`. An entry at any other scope in the same document
  is applied and pruned as before.

## Role assignments whose principal the directory did not return

An Azure role assignment can name a principal that Microsoft Entra ID does not return: one that was
deleted, or one this directory cannot read. The export looks every principal of the `roleAssignments`
section up through `directoryObjects/getByIds`, over every directory object type, and looks for each
principal that lookup did not return among the directory's deleted items, with one read of
`directory/deletedItems` per principal (once per export when the read succeeds).

- **The export keeps the assignment and says why.** `inventory.json` and `roleAssignments.json` write
  it with the principal's object id as `principal` and `principalStatus` after `principalType`:
  `Deleted` when the principal is among the directory's deleted items, `Unresolved` when it is found
  neither there nor in the directory (deleted beyond the retention period, a principal of another
  tenant, for example through Azure Lighthouse, or not readable), or when the read of its deleted
  items failed. The export writes one warning with the count, and the bundle's `README.md` lists each
  one, by role, scope, principal and type, with the status and its reason in words -- or, where the
  deleted items read failed, that the reason is not known -- under "Role assignments whose principal
  the directory did not return".
- **A failed read is never a fact.** When the lookup itself fails, the principal is written by its
  object id with no `principalStatus`, and the row is named under "What this export could not read"
  as `roleAssignments/<role> -> <principal id> @ <scope>/principal`; when only the deleted items read
  fails, the row is written as `Unresolved` and named there as `.../principalStatus`. Both are
  labelled "Role assignment principal that could not be read" and raise `InventoryPartial`.
- **The prompt treats it as a finding.** It tells the model to keep such an entry as exported or
  leave it out, never to invent or substitute a principal for it, and never to write
  `principalStatus` itself.
- **The validator.** `Test-OERStructure` refuses a `principalStatus` other than `Deleted` or
  `Unresolved` (a non-canonical letter case is a warning), and a `principalStatus` beside a
  `principal` that is not an object id.
- **The apply engine never creates such an assignment.** `Invoke-OERStructure` takes the object id
  as written and looks no principal up. A live assignment of that principal and role at the scope is
  matched as for any entry (`Unchanged`, or `Updated` when the declared `description`, `condition` or
  `conditionVersion` differ), and one inherited from an ancestor scope is `Skipped`. Where the entry
  would create the assignment it is reported `Skipped`, with no prompt and nothing written, the same
  under `-WhatIf`. Under `-Prune` the entry protects the live assignment, and a document without it
  lets `-Prune` remove it like any undeclared assignment at a scope the document declares. To have
  the assignment created, name a principal that exists and remove `principalStatus`.

This covers the `roleAssignments` section only. Directory role assignments, a group's eligibility,
reviewers and catalog resources keep their earlier rule: a principal they cannot name is written by
its object id, with no status and no deleted items read.

## Role assignments at a scope no document can declare

Azure Resource Manager can return a role assignment at a scope whose spelling the validator refuses,
for example the scope of a resource whose name holds a `#` or a `%` (the `scope` description in
`schema.json` lists the rules). No document can declare such a scope, and one that carried it would
be refused as a whole. So the export leaves the assignment out of `inventory.json` and
`roleAssignments.json`, with one warning that counts them, and the bundle's `README.md` lists each
one, by role, scope, principal and type, with the rules its scope breaks, under "Role assignments at
a scope no document can declare". It is left out, not unread: it raises no `InventoryPartial`. A role
assignment at the root scope whose spelling is refused too is listed as a root scope assignment only.
`Invoke-OERStructure` never creates a role assignment at such a scope and never removes one, since it
prunes only at a scope a document declares. Leaving it out changes nothing in the tenant.

## Groups using PIM for Groups in a restricted management unit

Microsoft Learn states that Privileged Identity Management does not support a group in a restricted
management administrative unit. With `Groups` and `AdministrativeUnits` included, the export finds
each group `inventory.json` writes with PIM eligibility or a `pimPolicy` that a restricted unit lists
among its members, with no request of its own, writes one warning with the count, and lists each
group and its units by display name under "Groups using PIM for Groups in a restricted management
unit". Nothing is left out of the export. A unit whose members could not be read, and a unit left out
because another unit shares its name, are not checked; both are named under "What this export could
not read".

`Test-OERStructure` warns, and never refuses, when a document places a group that declares PIM
eligibility or a `pimPolicy` in a restricted unit the document declares: by the group's
`administrativeUnit`, or in the unit's `members`. An exported document raises neither warning, since
its groups carry no object id and no `administrativeUnit`. `Invoke-OERStructure` still sends such a
group's PIM settings and eligibility; what Microsoft Graph answers to them has not been measured.

## Azure Lighthouse delegations

Azure Lighthouse lets another tenant, a service provider for example, manage subscriptions or
resource groups of this one: a delegation gives principals of that managing tenant Azure built-in
roles over the delegated scope, and Microsoft Learn states that the role assignments of this tenant
do not list that access. With an Azure section included, the export reads the delegations at the
subscriptions its walk visits, and at their resource groups, into `lighthouseDelegations.json`: one
row per delegation with its `scope`, the managing tenant (`managedByTenantId`,
`managedByTenantName`), the offer (`offerName`), its `authorizations` and its
`eligibleAuthorizations` (the just-in-time ones), each with the principal and the role. When it
read any, it writes one warning with the count, and the bundle's `README.md` lists each delegation
under "Azure Lighthouse delegations (access from another tenant)", by scope, managing tenant, offer
and roles, never by principal. The walk reads only this tenant's own subscriptions (see the last
point below), and Azure Lighthouse refuses a delegation whose managing tenant is the subscription's
own tenant, so every row is access another tenant holds over a subscription or resource group of
this tenant.

- **A finding, not an apply section.** The file is read-only context: no apply cmdlet reads it, and
  `Invoke-OERStructure` never creates or removes a delegation. The prompt tells the model never to
  declare one in `roleAssignments[]`, never to propose creating or removing one through the
  document, and to name each in its rationale as a finding.
- **A failed read is named.** A subscription is read whole or not at all. One whose delegations
  could not be read has no row in the file, which can therefore be `[]` after a failed read, and is
  named under "What this export could not read" as `lighthouseDelegations at <scope>`, labelled
  "Azure Lighthouse read that failed"; a role whose name could not be read is named there as
  `lighthouseDelegations role <id>`, and its `roleName` is `null`. A walk that could not start is
  named as `lighthouseDelegations at <all Azure scopes: scope enumeration failed>`, and a
  subscription listing that failed as `lighthouseDelegations at <subscriptions: the listing failed>`.
  Each raises `InventoryPartial`.
- **Subscriptions of another tenant are not read.** The export's Azure walk reads only the
  subscriptions whose home tenant -- the `tenantId` Azure Resource Manager returns for each -- is the
  tenant the session's Microsoft Graph token was issued for, the `tenantId` of `inventory.json`. A
  subscription of another tenant that is listed for the session, such as a customer subscription
  delegated to this tenant through Azure Lighthouse, is not read: no role assignment, role
  management policy, PIM eligibility or delegation of it is in the bundle, `scopeHierarchy.json`
  does not list it, one warning names it, and the bundle's `README.md` lists it under "Subscriptions
  delegated from another tenant (not read)". That is a deliberate selection, and it does not make the
  bundle partial; nothing is read at a `-Scope` in such a subscription either. A subscription whose
  home tenant could not be read is not walked: it is named under "What this export could not read"
  as `subscriptionHomeTenant at <scope>`, labelled "Azure subscription whose tenant could not be
  read", and raises `InventoryPartial`. A proposal must not declare a role assignment or a role
  management policy at a scope in a subscription of another tenant: `Invoke-OERStructure` reports
  such an entry `Failed` with `SubscriptionTenantMismatch`, reads no role assignment or policy there
  and writes nothing for it, with or without `-Prune`, the same under `-WhatIf`. A document built
  with `Get-OERInventory -Scope` or `-Subscription` instead of the export follows the same rule:
  `Get-OERInventory` writes no `roleAssignments` or `roleManagementPolicies` row in a subscription
  of another tenant, and reports `SubscriptionTenantMismatch` once; where it cannot tell the
  subscription's tenant, it writes none either and names those sections in `InventoryPartial`.

## Service principal access

With `-IncludeServicePrincipalAccess`, the export also writes `servicePrincipalAccess.json`:
read-only context on the app roles and delegated permission grants of the tenant's service
principals and on the owners of its service principals and app registrations, which the apply
document does not model. A service principal's Microsoft Entra directory roles and Azure roles are
not in it but in `directoryRoleAssignments.json` and `roleAssignments.json`, each within its own
coverage, so a service principal this file does not name is not shown to be without privilege. It
is one JSON object with four parts, in this order:

- `applicationPermissions` -- one row per app role a service principal holds on a resource,
  application permissions among them, read from the client side: `servicePrincipalId`,
  `servicePrincipalDisplayName`, `resourceId`, `resourceDisplayName`, `appRoleId` and
  `appRoleValue`, which is `null` for a role the resource does not declare, such as the default
  access role.
- `delegatedPermissionGrants` -- one row per delegated permission grant: `clientId`,
  `clientDisplayName`, `resourceId`, `resourceDisplayName`, `consentType`, `principalId`,
  `principalDisplayName` and `principalUserPrincipalName` (the user's display name and user
  principal name, all three `null` for `AllPrincipals` and the two names `null` for a user the
  directory did not return) and `scope`, the space-separated delegated permissions.
- `applicationOwners` -- one row per owner of an app registration: `applicationId`, `appId`,
  `applicationDisplayName`, `ownerId`, `ownerType`, `ownerDisplayName` and
  `ownerUserPrincipalName`.
- `servicePrincipalOwners` -- one row per owner of a service principal: `servicePrincipalId`,
  `servicePrincipalDisplayName` and the same four owner keys.

Every blank value is `null`, and each part is sorted, so two exports of an unchanged tenant write the
same file. The bundle's `README.md` gives each part's row count under "Service principal access
(read-only)".

- **Context, never a proposal target.** `inventory.json` and `schema.json` do not carry the file, no
  apply cmdlet reads it back, and `Invoke-OERStructure` never grants, revokes or changes any of it.
  The prompt names the file among its inputs only when the export wrote it, and tells the model
  never to declare this access in a proposal and never to propose granting, revoking or changing it
  through the document, but to name what stands out in its rationale as a finding.
- **`null` is not `[]`.** A part is read whole or not at all. A part that could not be read is
  written `null`, never `[]`, and is named under "What this export could not read" as
  `servicePrincipalAccess/<part>`, labelled "Service principal access part that could not be read",
  and in `InventoryPartial`. The grants are not read when the service principal list they are named
  through was not, so that failure leaves both `applicationPermissions` and
  `delegatedPermissionGrants` `null`. An empty `[]` is a part that was read and holds nothing.
- **What it costs.** One request per page of each of three lists (the service principals with their
  app role assignments, the service principals with their owners, and the app registrations with
  their owners) and of the grants, one `directoryObjects/getByIds` per 1,000 users named in grants,
  and one more paged read per object with 20 or more expanded entries: 27 requests for a test tenant
  of 1,129 service principals and 67 app registrations. `Directory.Read.All`, which the export
  already requires, covers every read.
- **Without the switch** none of it is read or written, and neither `README.md` nor
  `rbac-architect-prompt.md` mentions it.

## Group names from a template

A `groups` entry carries its name in one of two ways: a literal `displayName`, or a `template` with a
`tokens` object that the apply engine turns into the name:

```json
{
  "template": "role_sec_{area}_{tier}",
  "tokens": { "area": "identity", "tier": "administrator" }
}
```

This entry is the group `role_sec_identity_administrator`.

- **Placeholders.** Each `{token}` in the template is replaced by the value of the token of that
  name. Token names are matched ignoring letter case.
- **Every placeholder must resolve.** A placeholder without a token leaves the name unbuilt: the
  entry is reported `Failed` with the message "Naming template ... has unresolved token(s)" and
  nothing is created or changed for it. `Test-OERStructure` raises no `Error` for it (with
  `-NamingStandard` it adds only a `Warning` saying the name was not checked), so in the LLM loop
  `Invoke-OERStructure -WhatIf` is the first step that shows the entry as `Failed`.
- **`template` and `displayName` are mutually exclusive.** `Test-OERStructure` refuses, as an
  `Error`, an entry that declares both, one that declares neither, and a `template` without a `tokens`
  object.
- **The export always writes `displayName`.** `Get-OERInventory` and `Export-OERInventory` never
  write `template` or `tokens`, so a template appears only in a document written by hand or proposed
  by a model.

`Test-OERStructure -NamingStandard` checks the name a template gives, not the template (see the next
section).

## Checking names against a naming standard

A naming standard kept as a file lets the names in an exported inventory, or in a proposal an LLM
wrote, be checked instead of read by eye:

```powershell
Test-OERStructure -Path .\proposal.json -NamingStandard .\naming-standard.json
```

A name gets one `Warning` for each rule it breaks, with `Section`, `Item`, `Path` and a message that
says which rule the name breaks and what was expected, for example:

```text
Name 'SG-Legal-Readers' at groups[2].displayName does not follow the naming standard (rule 'values', segment 2 'area'): 'Legal' is not one of the allowed values 'Finance', 'Sales', 'IT'.
```

It never makes a document invalid, and `Invoke-OERStructure` takes no naming standard: the check
tells you which names to change, and the apply engine applies the document as written.

- **The file.** `docs/examples/naming-standard.json` is a neutral example (`kind-area-purpose`, with
  an optional environment at the end) and `docs/examples/naming-standard.schema.json` is its JSON
  Schema. Copy the example and edit it: a `version` (`"1.0"`), a `separator`, the ordered `segments`
  (each has a `name` and may have a closed list of `values` or a `pattern`, a letter `case` and
  `optional`), a `maxLength`, `exceptions` for names that keep their names, and the `sections` to
  check. The six rules a warning names are `maxLength`, `separator`, `segmentCount`, `values`,
  `pattern` and `case`.
- **Patterns match the whole text.** A segment `pattern` and an `exceptions` entry are anchored at
  both ends and are case-sensitive unless they carry `(?i)`; a `values` entry is compared
  exactly and is never a pattern.
- **What is checked.** The name an object carries after the step: `displayName`, or the name a
  group's `template` and `tokens` give (a template that cannot be turned into a name gets one warning
  saying it was not checked). A `previousDisplayName` is never checked, so a rename is judged by its
  new name. A group with `onPremisesSynced` true is skipped, with a warning that says so, unless the
  file sets `includeSyncedGroups` to true.
- **The groups an export holds.** The check covers the groups `inventory.json` holds: by default the
  RBAC-relevant security groups (a role-assignable group, one with PIM eligibility, one with a
  `pimPolicy`). `Export-OERInventory -AllGroupsDetailed` keeps every group `inventory.json` covers in
  full detail and `-IncludeSyncedGroups` keeps the synchronized ones; a Microsoft 365 group whose
  `securityEnabled` is false is in `groupsRoster.json` only. The standard's `includeSyncedGroups`
  therefore matters for an export only when the export was made with
  `Export-OERInventory -IncludeSyncedGroups` (or `-AllGroupsDetailed`), a different switch with a
  similar name.
- **A proposal.** The bundle's prompt tells the model to propose names that follow the operator's
  naming standard (the `Naming convention` line of its `USER PREFERENCES (optional)` block) and that a
  name that does not is a Warning, never a refusal. The model never sees the standard file: write the
  standard's rules into that line of `rbac-architect-prompt.md` before you hand the prompt over, and
  let `Test-OERStructure -NamingStandard` tell you which proposed names still break them. On an
  exported `inventory.json` the warnings are the list a rename map is written from: declare the new
  name as `displayName` and the current one as `previousDisplayName` (see "Renaming a group" below).
- **A file that cannot be used.** A path that is not a file, a file that exists but cannot be read,
  malformed JSON, a key or value the standard does not allow or a pattern that does not compile is
  refused once with the error `InvalidNamingStandard`, which says what is wrong, and nothing is
  validated. A known limit: the JSON parser reads a string that holds an ISO 8601 date and time, such
  as `2024-01-01T10:00:00`, as a date (a date alone, such as `2024-01-01`, stays a string), so such a
  value in the file is refused as not a string.

## Renaming a group

`displayName` is the match key for a group. To rename a group through the apply document, declare
its new name as `displayName` and its current name as `previousDisplayName`, next to the entry's
other keys:

```json
{
  "displayName": "role_sec_hr_emea",
  "previousDisplayName": "role_sec_hr"
}
```

Every apply run looks up both names, with three outcomes:

- **Only `previousDisplayName` matches a live group.** That group is renamed to `displayName`, in
  the same update as any other property that changed, and reported `Updated`. Its members, owners,
  eligibility and `pimPolicy` are then reconciled as usual.
- **Both names match, and they are different groups.** The entry fails and nothing is changed for
  it -- the document never merges two groups. Rename or delete one of them, or remove
  `previousDisplayName`.
- **Neither name matches.** The entry fails with `GroupRenameNotFound` and nothing is created: a
  document that declares a rename names a group that already exists. To create a new group, declare
  it without `previousDisplayName`.

When both names find the same group, the entry is applied as usual.

**Microsoft Graph's name lookup can follow a rename with a delay.** Keep `previousDisplayName` in
the document, and wait until the new name resolves (for example `Get-OERGroup -Group '<new name>'`
finds the group) before you apply the document again: a run after that finds the group under
`displayName` and reports it `Unchanged`. A run inside the window in which neither name resolves yet
fails the entry with `GroupRenameNotFound` and creates nothing; wait and re-run. Once the new name
resolves, remove `previousDisplayName`: a group created later under the old name would make the entry
fail. `Get-OERInventory` never exports `previousDisplayName`, and `Test-OERStructure` reports an empty
or non-string one as an error and one equal to `displayName` (ignoring case) as a warning -- a
case-only rename is not possible through the document; use `Set-OERGroup -NewDisplayName`.
An administrative unit, a catalog, an access package, an assignment policy and an access review are
renamed the same way: see "Renaming units, catalogs, packages, policies and reviews" below. A
group's `mailNickname` does not follow a rename: a
renamed group keeps its alias unless the document declares one, which is 1 to 64 characters without
`@ ( ) \ [ ] " ; : < > ,` or white space.

`previousDisplayName` also accepts the group's object id instead of its old name. That is the way to
rename a group whose old name is ambiguous, since a name that matches several groups fails the
entry. The apply engine checks that the id still names a group: an id that no longer exists (a
deleted group, say) counts as not matching, exactly like an old name nobody carries any more -- so
with `displayName` not matching either, the entry fails as above.

Everywhere else in the SAME document, refer to the group by its NEW name: in
`administrativeUnits[].members`, catalog `resources`, access package `resourceRoles`,
`roleAssignments` and `directoryRoleAssignments` principals, and eligibility, owner, member or
approver entries. Once Graph's name lookup has caught up with the rename, the old name resolves to
nothing, so a reference that still uses it fails or is reported as not found. The new name can lag too: on the run that renames the group, a reference to the new name
can fail to resolve. It fails loudly -- a `Failed` row, and a handler that withholds its prune while
a declared entry does not resolve withholds it -- and re-applying the document once the new name
resolves, with `previousDisplayName` still in it, is safe. Under `-WhatIf` the rename is only
planned, so the new name does not resolve yet either -- those references are reported the same way
as references to a group that the same run would create.

**Catalog `resources` and access package `resourceRoles` follow the rename like every other
reference.** A Group or Application resource is identified by the object id its name resolves to,
never by the display name Microsoft Entra recorded for the resource when it was added to the catalog
-- that recorded name stays as it was after a group is renamed (measured live; the same is expected
of an application), so matching on it made a document naming the group's new name plan the removal
of the group's own resource under `-Prune`. `Get-OERInventory` writes the group's or application's
CURRENT name, and its object id when the name cannot be read or is blank; a name that resolves to no
object, or to several, fails its entry and withholds that catalog's prune. A catalog resource with a blank name is written under its origin
id. An entry the export can name by nothing the apply engine accepts -- a SharePoint binding with no
name, say -- makes the package's `resourceRoles` (or the catalog's `resources`) an explicit `null`,
named in `InventoryPartial`. The export never writes an empty name: `Test-OERStructure` refuses an
empty or blank `resource`, `role`, `name` or `principal`, and `schema.json` an empty one.

## Renaming units, catalogs, packages, policies and reviews

An administrative unit, a catalog, an access package, an assignment policy of an access package and
an access review are renamed with the key and the rules a group uses. Declare the new name as
`displayName` and the current name, or the object id, as `previousDisplayName`. An access package is
matched within the `catalog` it declares, and an assignment policy within its access package; an
access review is looked up in the whole tenant:

```json
{
  "catalogs": [
    { "displayName": "CAT-IT-Core-EMEA", "previousDisplayName": "CAT-IT-Core" }
  ],
  "accessPackages": [
    {
      "displayName": "AP-Helpdesk-EMEA", "previousDisplayName": "AP-Helpdesk", "catalog": "CAT-IT-Core-EMEA",
      "assignmentPolicies": [ { "displayName": "Helpdesk staff", "previousDisplayName": "Default" } ]
    }
  ],
  "accessReviews": [
    {
      "displayName": "AP-Helpdesk-EMEA quarterly", "previousDisplayName": "AP-Helpdesk quarterly",
      "accessPackage": "AP-Helpdesk-EMEA", "assignmentPolicy": "Helpdesk staff"
    }
  ]
}
```

Every apply run looks up both names before it reads or writes anything else for the object, with the
same outcomes as for a group:

- **Only `previousDisplayName` matches.** That object is renamed to `displayName`, in the same update
  as any other property that changed, and reported `Updated`. Its members and scoped roles (a unit),
  resources (a catalog) or resource roles and assignment policies (a package) are then reconciled as
  usual. If the update fails, the entry is `Failed` and none of those is reconciled. Under `-WhatIf`
  the row is `Skipped` with `would rename`, and they are planned against the object found under its
  previous name.
- **Both names match, and they are different objects.** The entry fails with
  `AdministrativeUnitRenameConflict`, `CatalogRenameConflict`, `AccessPackageRenameConflict`,
  `AssignmentPolicyRenameConflict` or `AccessReviewRenameConflict` and nothing is changed for it --
  the document never merges two objects. Rename or delete one of them, or remove
  `previousDisplayName`.
- **Neither name matches.** The entry fails with `AdministrativeUnitRenameNotFound`,
  `CatalogRenameNotFound`, `AccessPackageRenameNotFound`, `AssignmentPolicyRenameNotFound` or
  `AccessReviewRenameNotFound` and nothing is created: a document that declares a rename names an
  object that already exists. To create a new one, declare it without `previousDisplayName`. A
  policy that declares `previousDisplayName` in a package the same run creates fails this way too.

When both names find the same object, or only `displayName` does, the entry is applied as usual.

A policy's rows, its refusals included, are rows of its access package's entry (section
`accessPackages`, the package's name as the item) that name the policy in their detail, as every
other policy row does.

`previousDisplayName` also accepts the object id. For a unit, a catalog and an access review the
apply engine checks with one read that the id still names one: an id that no longer exists counts as
not matching, like an old name nobody carries any more. For an access review that rests on the
not-found codes the read declares: Microsoft Graph was measured to answer an id that names no review
with 404 and an empty error code, which the read takes as not found; a not-found answer under any other
code fails the entry, with nothing written. For an access package the id is matched only
against the packages of the declared catalog, and for an assignment policy only against the policies
of its package, which are already read, so the id of one in another catalog or package, or of a
deleted one, counts as not matching. A previous name that matches several units or catalogs fails
the entry with `AmbiguousName`, as an ambiguous `displayName` does; one that several packages of the
catalog carry fails it with a row naming every id, and one that several policies of the package, or
several access reviews, carry fails it with `AmbiguousName` naming every id. Declare
`previousDisplayName` as the object id then.

**An access review is checked before it is renamed.** The review found under either name is updated
or renamed only when it reviews the access package and assignment policy the entry declares;
otherwise the entry fails with `AccessReviewScopeMismatch`, in a plan and in a run alike, and nothing
is written to it. After a rename, the review read back must carry the new name exactly, letter case
included, or the entry is `Failed`.

**Microsoft Graph's name lookup can follow a rename with a delay.** Keep `previousDisplayName` in the
document until the new name resolves: a run after that finds the object under `displayName` and
reports it `Unchanged`, and a run inside the window in which neither name resolves yet fails the
entry with the `RenameNotFound` id and creates nothing. Once the new name resolves, remove
`previousDisplayName`: an object created later under the old name would make the entry fail.

**References in the same run.** Name a renamed object by its NEW name. When the same document
renames it, `Invoke-OERStructure` finds it by its object id: a group that is created into the
renamed unit (`administrativeUnit`) is created into it, an access package declared in the renamed
catalog (`catalog`) is read, and created or planned, in it, and an access review that names the
renamed access package (`accessPackage`) or assignment policy (`assignmentPolicy`) is checked, and
created or planned, against it, also in a `-WhatIf` plan, where the rename is not sent. Microsoft
Graph's lookup cannot find the new name yet. A review reaches a renamed policy, or is refused, under
the package as the review names it: by the package's new name, or by its object id once the
package's entry knows that package's id. When the target check refuses such a review, its error
names the package or policy by that id, and the `Failed` row says which name was read as which id.

**A rename the run cannot settle refuses its references.** When the rename is refused (a conflict,
or neither name found), or the run cannot decide it (one of its names could not be looked up, the
access package's entry stopped before it decided, or `-Include` leaves out the `AdministrativeUnits`,
`Catalogs` or `AccessPackages` section that holds the entry), a reference is not looked up by name,
since that could land in another object that carries the new name. A group that would be created
into the unit, every package declared in the catalog and every access review that names the package
or the policy by its new name is `Failed`, under `-WhatIf` too, and nothing is created or written
for it (a package or a review is not read either); the renamed object's own row carries the error id
when its rename was refused. A group that already exists is reconciled as usual, since
`administrativeUnit` applies only when a group is created; an access review that already exists is
refused too. A review that names the package by its object id and a renamed policy by its new name
is refused that way once the package's entry knows that package's id. Until then the review looks
the policy up by name, as before: so it does when the entry stopped before it knew any package id
(its catalog refused, a failed read of the catalog's packages, or a package rename that found
neither name), when the entry stopped at a display name several packages of its catalog carry and
the review names the package that carries the entry's previous name (only the packages that carry
the display name are marked; the previous name is not looked up by then), or when `-Include` leaves
out the `AccessPackages` section.

While `-Include` leaves the section out and the entry still declares `previousDisplayName`, that
refusal reaches every reference by the new name -- for a catalog every package declared in it, for
a package or a policy every review that names it by that name (one that names the package by object
id looks a policy up by name, as above), existing ones included -- even when the rename was done in
an earlier run: include the section, or remove `previousDisplayName` once the new name resolves. A
refusal because `-Include` leaves the section out publishes no error record, only the `Failed` row,
so `-ErrorAction Stop` and `$?` do not see it: check the rows.

**A review reaches the package its entry resolved, renamed or not.** Every `accessPackages` entry
records its package in the run, not only one that renames: the id of the package it found in its
declared catalog, or created there. So an access review whose `accessPackage` gives that package by
its display name is checked, and created, against that id, and the name is never looked up in the
whole tenant, where a package of that name in another catalog would be found; the `Failed` row of the
target check then says the name was read as the id of "the access package its accessPackages entry
resolved in this run". Until the entry has that id the review is refused, `Failed` with nothing read
or written for it, under `-WhatIf` too: when the entry stopped first (its catalog refused, a failed
or ambiguous lookup, a failed create, a create that returned another catalog's package), when a
`-WhatIf` plan would create the package or a declined confirmation skipped its create (the plan then
reports the review `Failed` although a real run creates the package first, then the review), and
when `-Include` leaves out the `AccessPackages` section. Such a refusal publishes no error record of
its own, only the review's `Failed` row, so `-ErrorAction Stop` and `$?` do not see it. A review that
names the package by object id, or names a package the document does not declare, is resolved as
before.

**Two packages with one name.** The same display name in two catalogs is two packages, but the run
keys every declared package, and its policies, by the package's name, without its catalog. So
`Test-OERStructure` refuses, as an error, an access review whose `accessPackage` gives by name a
package that two or more `accessPackages` entries declare, as `displayName` or
`previousDisplayName`, whether or not one of them is renamed; name the package by its object id in
such a review.

`Test-OERStructure` reports an empty or non-string `previousDisplayName` as an error, and one equal
to `displayName` (ignoring case) as a warning -- a case-only rename is not possible through the
document, except for an assignment policy together with another changed field of the policy; use
`Set-OERAdministrativeUnit`, `Set-OERCatalog` or `Set-OERAccessPackage -NewDisplayName`,
`Set-OERAccessPackageAssignmentPolicy -DisplayName` together with another property, or
`Set-OERAccessReviewDefinition -DisplayName`. Two entries of a section that claim one name, as
`displayName` or `previousDisplayName`, are an error, and so are two assignment policies of one
access package that claim one name, two equal `displayName`s included (the same name in two packages
is two policies). It also warns on a reference that still uses a
renamed object's previous name: a group's `administrativeUnit`, an access package's `catalog` and an
access review's `accessPackage` and `assignmentPolicy`; a `previousDisplayName` that is an object id
raises none, since a reference by id stays valid. `Get-OERInventory` never exports
`previousDisplayName`, and `-Prune` never deletes a unit, a catalog, an access package, an assignment
policy or an access review. A changed `displayName` WITHOUT `previousDisplayName` still creates a
new object and leaves the old one in place (an old assignment policy is reported `Extra`).

## Directory roles

`directoryRoleManagementPolicies[]` and `directoryRoleAssignments[]` cover Microsoft Entra directory
role PIM, through Microsoft Graph only -- neither one ever acquires an ARM token. Their full field
lists are in `schema.json`, under the same-named properties; this section covers only what
`Get-OERInventory` selects and exports into `inventory.json`.

**Policy selection.** `directoryRoleManagementPolicies` exports the policy of every directory role
that has at least one row in the tenant-scope eligibility or assignment schedules (any member type,
activations included). Add `-AllDirectoryRolePolicies` to export the policy of every directory role
instead -- the schedules are then not read for the policy section at all, though they are still read,
once, when `DirectoryRoleAssignments` is included too. A failed schedule or policy read is reported
through `InventoryPartial` and never stated as a fact.

**Assignment export.** `directoryRoleAssignments` exports only the rows
`Select-OERManagedDirectoryRoleAssignment` keeps: direct assignments at tenant scope. An activation of
an eligible assignment, an assignment a principal holds through a group, and one scoped to an
administrative unit are never exported -- their absence here is not evidence the tenant has none. A
user is named by its user principal name and a group by its display name, each falling back to its
object id when the name cannot be read, or, for a group, when its display name matches that of
another group anywhere in the tenant or of another principal holding the same role and assignment
type (see "Names two or more objects share" below); a service principal, or a principal of
unknown type, is named by its object id. `principalType` is carried whenever the type is known. A
time-bound assignment carries `durationDays` reconstructed from the live schedule window, so a
re-applied export is `Unchanged`; a permanent one carries neither `durationDays` nor `permanent`.

Both sections are ordinary apply-document sections: propose changes to them like any other. A
directory role's policy always exists, so there is nothing to create or remove and `-Prune` has no
effect on `directoryRoleManagementPolicies`; `directoryRoleAssignments` reconciles, and can be
pruned, only for the `(role, assignmentType)` pairs the document declares.

**Administrative unit scoped roles.** A directory role scoped to an administrative unit is declared
in that unit's `administrativeUnits[].scopedRoles`, as `role` and `principal`, which together are
its match key. The export also writes `principalType` (`User`, `Group` or `ServicePrincipal`) on a
row whose principal is an object id that the directory returns as one of those types, all of them
looked up together through `directoryObjects/getByIds`; a row whose principal the directory did not
return, of another type, or named by its display name carries none. A lookup that fails leaves those
rows without it and names the unit under "What this export could not read" as
`administrativeUnits/<name>/scopedRoles/principalType`, which raises `InventoryPartial`; the unit's
`scopedRoles` is still written. The key is optional: `Test-OERStructure` refuses a value outside the
three (another letter case is a warning), and `Invoke-OERStructure` does not use it to match or
write a scoped role, so a proposal may keep it, leave it out, or add it for a new row.

## Access reviews are matched by name

An `accessReviews[]` entry is matched to a live review by `displayName`, looked up in the whole
tenant, and access review display names are not unique. The review found is therefore updated only
when it reviews the `accessPackage` and the `assignmentPolicy` the entry declares: a GUID is
compared as written, and a name is resolved the way `New-OERAccessReviewDefinition` resolves it when
it creates a review. The scope of a review cannot be changed on an existing one.

- A review that reviews a group, a role, another access package or another policy is reported
  `Failed` with `AccessReviewScopeMismatch`, naming what it reviews, and nothing is written to it. A
  review of no access package at all is refused with no access package or assignment policy lookup.
- A declared name that matches nothing is reported `Failed` with `AccessPackageNotFound` or
  `AssignmentPolicyNotFound`; a lookup that fails (an ambiguous name, a 403) is reported `Failed`
  with its own error. Nothing is written in either case.
- An access package name is not unique in the tenant, nor an assignment policy name in its access
  package: when such a name is shared, the entry is reported `Failed` with `AmbiguousName` until it
  gives the package or the policy by id. The export writes either by id whenever that lookup would
  not find that package or policy alone, so an exported entry applies.
- The check runs before the reviewer lookups and before any confirmation, so a `-WhatIf` plan and a
  real run report the same `Failed` row.

The export captures only access-package-scoped, single-stage reviews, so a name missing from
`accessReviews.json` may still be in use by a review the bundle leaves out. Give a new review a
display name no other review in the tenant uses.

## Access package assignment policy schema

`accessPackages[].assignmentPolicies[]` in an apply document supports a rich set of optional fields
(all additive -- the legacy form keeps working unchanged).

### Requestor scope (who can get access)

```json
"requestorScope": {
  "scope": "specificDirectoryUsers",
  "users":  ["<upn-or-object-id>", "<object-id>"],
  "groups": ["<display-name-or-object-id>"]
}
```

`scope` takes a Microsoft Graph v1.0 `allowedTargetScope` value, in the casing the inventory writes
(`AllMemberUsers`) or the Graph casing (`allMemberUsers`). `AllMemberUsers`, `AllDirectoryUsers`,
`AllExternalUsers`, `AllConfiguredConnectedOrganizationUsers`, `AllDirectoryServicePrincipals`,
`AllDirectoryAgentIdentities`, `SpecificDirectoryUsers` and `NotSpecified` (administrator assignment
only) are written as declared. **`NoSubjects` is not a v1.0 value** -- it is a legacy beta spelling,
so the engine substitutes `NotSpecified` and warns on every apply; write `NotSpecified` directly.

`users` and `groups` are resolved by the engine (names or object ids) and apply to
`SpecificDirectoryUsers` only. They are the only targets the module models, and it cannot read a
scope Microsoft Graph does not name, so three cases are refused rather than written. Each is a
`Failed` row for that policy, decided before ShouldProcess (so the same under `-WhatIf`), with
nothing written for it:

- `SpecificDirectoryServicePrincipals`, whenever it is declared: its service principal targets are
  not modelled, so the scope cannot be built (`InvalidPolicyInput`).
- `SpecificConnectedOrganizationUsers`, declared on an update that changes the policy: its connected
  organization targets are not modelled, so the write would drop them. A declared scope that matches
  the live policy reports `Unchanged`, and a new policy is created with it, but with no connected
  organization targets: the module cannot write them, so they must be added outside the module.
- A live policy whose scope reads as `unknownFutureValue`, whatever the entry declares: Microsoft
  Graph names the real scope only to a caller that sends `Prefer: include-unknown-enum-members`,
  which this module never does. The inventory writes the value as it was read.

An omitted `requestorScope` is preserved on update: the engine does not send it, and the live scope
and its targets are carried forward as one unit. A new policy created without one gets
`AllMemberUsers`. The inventory always emits `requestorScope`, so an exported
`SpecificDirectoryServicePrincipals` policy fails until `requestorScope` is removed from its entry,
and an exported `SpecificConnectedOrganizationUsers` policy fails as soon as another of its fields
is changed while `requestorScope` stays in it. Removing `requestorScope` is how to update the other
fields of either policy.

### Requestor settings (how they can request)

```json
"requestorSettings": {
  "allowSelfRequest":       true,
  "allowManagerRequest":    false,
  "managerLevel":           1,
  "allowCustomSchedule":    false,
  "allowSelfExtend":        true
}
```

`allowManagerRequest` enables on-behalf-of requests by the direct manager. `managerLevel` (1-4, default
1) selects how many manager levels up are allowed. `allowCustomSchedule` lets the requestor supply their
own assignment timeline. `allowSelfExtend` lets an active assignee request an extension.

### Approval toggles

```json
"requireApproval":                true,
"requireRequestorJustification":  true,
"requireApprovalForUpdate":       false
```

`requireApproval` enables the approval workflow independently of the stage count (one stage is enough),
and it wins over that count rather than being derived from it. Never pair it with a declared-empty
`"approvalStages": []`: that combination writes approval-required with no approver stages at all, so no
request can ever be approved. `Test-OERStructure` reports the pair as a Warning.
`requireRequestorJustification` forces the requestor to supply a justification in the request form.
`requireApprovalForUpdate` additionally triggers approval for extension requests.

### Approval stages (richer form)

The existing `approvalStages[]{durationDays, manager}` shape keeps working. The richer form adds:

```json
"approvalStages": [
  {
    "durationDays":                 5,
    "managerLevel":                 1,
    "users":                        ["<upn-or-object-id>"],
    "groups":                       ["<display-name-or-object-id>"],
    "internalSponsor":              false,
    "externalSponsor":              false,
    "alternateUsers":               ["<upn-or-object-id>"],
    "alternateGroups":              ["<display-name-or-object-id>"],
    "escalationDays":               3,
    "requireApproverJustification": true,
    "approverInfoVisibility":       "Default"
  }
]
```

| Field | Description |
|---|---|
| `managerLevel` | Requestor's Nth-level manager (1 = direct manager). |
| `users` | Specific approver users (UPN or object id). |
| `groups` | Specific approver groups (display name or object id). |
| `internalSponsor` | Use the access package's internal sponsor as approver. |
| `externalSponsor` | Use the access package's external sponsor as approver. |
| `alternateUsers` / `alternateGroups` | Escalation approvers after `escalationDays` days. |
| `escalationDays` | Days before automatic escalation. |
| `requireApproverJustification` | Approver must supply a justification when deciding. |
| `approverInfoVisibility` | `Default` (portal default), `Visible`, or `NotVisible`. Controls whether the approver's identity is shown to the requestor. |

### Expiration (at most one form)

```json
"durationInDays":    90
```
```json
"durationInHours":   8
```
```json
"expirationDateTime": "2027-01-01T00:00:00Z"
```

Supply at most one expiration form. `durationInDays` sets an ISO-8601 `P{n}D` duration;
`durationInHours` sets `PT{n}H`; `expirationDateTime` sets a fixed end date. Omitting all three
leaves the live expiration unchanged on apply.

### Disable assignment emails

```json
"notificationsDisabled": true
```

Disables the built-in assignment notification emails for this policy.

### Description default

When `description` is omitted from the entry of a NEW policy, the engine uses the policy display name
as the description; an existing policy keeps its live description. Set `"description": ""` explicitly
to clear it.

### Overlay vs. preserve semantics

The policy is applied as a FULL object (PUT), but `Set-OERAccessPackageAssignmentPolicy` is
read-modify-write: it reads the live policy first and overlays only what is supplied. The apply engine
diffs and writes ONLY the fields you declare in the apply document, so fields you omit are PRESERVED
from the live policy. Declaring a field EMPTY is not the same as omitting it: `"approvalStages": []`
clears every live approval stage, just as `"description": ""` clears the description. On CREATE there
is no live value to keep, so every omitted field gets a default; two of those defaults are not the
obvious empty one:

- `description` -- a new policy gets the policy display name. On update it is preserved.
- `requestorScope` -- a new policy gets `AllMemberUsers`. On update it is preserved, its targets
  included (see above).

A declared `requestorScope` is written whole: its `users` and `groups` replace the live targets, so a
target the module does not model (a connected organization, a service principal) cannot round-trip
through it -- which is why `SpecificDirectoryServicePrincipals` is refused outright and
`SpecificConnectedOrganizationUsers` is refused on an update that changes the policy, though still
written on create (see above).

These out-of-scope fields are always preserved (never written by this module):

- `reviewSettings` -- policy-embedded access reviews.
- `questions` -- custom requestor questions.

Fallback approvers are only partly modelled. A stage's `fallbackUsers` / `fallbackGroups` are its
`fallbackPrimaryApprovers` and are diffed and written like its other approvers.
`fallbackEscalationApprovers` are not modelled: they are preserved while the entry does not declare
`approvalStages`, but an update of a policy whose entry declares `approvalStages` rebuilds and sends
every stage, and so clears the escalation fallbacks of every stage -- a known limitation.

## Names two or more objects share

Microsoft Entra ID does not keep display names unique, and `Invoke-OERStructure` refuses a name that
more than one live object answers to. So `Get-OERInventory` and `Export-OERInventory` leave out of
the document every object whose name another object of its kind shares, compared without regard to
letter case -- all of them -- and name each in `InventoryPartial`: groups, administrative units,
catalogs, access reviews, the access packages of one catalog and the assignment policies of one
access package. A group's name is counted over every group in the tenant, Microsoft 365 and
distribution groups included: `Export-OERInventory` counts over its roster, and `Get-OERInventory`
makes one more paged listing of every group's id and display name, at most once per call; when that
listing fails, `groupNames` is reported unread and the names are counted among the groups read.
`Export-OERInventory` shares one index of every group's name among all its `Get-OERInventory` calls,
built from the roster when it was read and otherwise with one listing, so an export lists the groups
at most once, never once per Azure scope. An
access package's name is counted among the packages of its catalog, an assignment policy's among the
policies of its own access package only, and the name of an administrative unit, a catalog or an
access review among the ones read (with `Get-OERInventory -Catalog`, only the catalogs it reads; an
access review among the access-package reviews captured). Leaving an
object out changes nothing in the tenant: `-Prune` acts on child collections only, and the apply
engine never removes an assignment policy.

`Export-OERInventory` writes ONE warning that gives how many names were left out and how many objects
carry them, and the bundle's `README.md` lists each name, with how many objects carry it and its
section (an assignment policy as `<package>/<policy>`, section `assignmentPolicies`), under "Names
two or more objects share". `Get-OERInventory` hands the same names to its caller in one information
record tagged `Omnicit.EntraRBAC.SharedName`, which the default `$InformationPreference` does not
display.

A reference to such an object elsewhere in the document is written by object id, which the apply
engine takes as the object itself:

- an access package's `catalog`, when another catalog the export read carries the catalog's name
  (with `-Catalog` given as an id, only that catalog is read, so its packages keep its name even
  when another catalog in the tenant carries it);
- an access review's `accessPackage` or `assignmentPolicy`, whenever the apply engine's own lookup --
  the package name in the whole tenant, the policy name among its package's policies -- would not
  find that object alone;
- a group named as the principal of a `roleAssignments` or `directoryRoleAssignments` entry, written
  with `principalType` `Group`, unless no other group in the tenant carries its name; when the
  listing of every group fails, every such group is written by its object id.

Keep such an id as an id in a proposal. A group named anywhere else -- an `eligibility` principal of
a group, an access review's reviewer, a catalog resource or an access package resource role -- is
still written by its display name, and a shared one is refused when it is applied. `Test-OERStructure`
refuses two assignment policies of one name in one access package, which an export made by an
earlier version can hold.

## Unread collections

A read that fails is never written as a fact. A `members`, `scopedRoles`, `resources` or
`resourceRoles` collection that could not be read, or one with an entry the export could name by
nothing the apply engine accepts, is written as `null`, which `Invoke-OERStructure` leaves
untouched: keep it `null` in a proposal and never change it to `[]`, since under `-Prune` an empty
collection removes every live entry. The `members` of a group that has members and whose PIM for
Groups assignments AND eligibility both could not be read is `null` for the same reason (see "Members
and owners that PIM for Groups holds"). A section that could not be read at all (the group list, the
administrative unit list or the access review list) is reported by a warning and through
`InventoryPartial` under the section's own name (`groups`, `administrativeUnits` or
`accessReviews`), and is written as an empty array, never `null`. The group roster that could not be
read is named `groupsRoster` in the bundle's `IncompleteReads` and written as an empty array in
`groupsRoster.json`. An empty section reported that way is not evidence the tenant has none, so no
deletion is proposed from it. A path ending in `scopedRoles/principalType` is not such a collection:
it names an administrative unit whose `scopedRoles` is written, not `null`, and some or all of whose
rows carry no `principalType`, since the type of their principals could not be looked up (see
"Administrative unit scoped roles" under "Directory roles").

The bundle's `README.md` lists every such report, and every Azure scope the export could not read
(for `roleAssignments.json` and `roleManagementPolicies.json`, or for `azurePimEligibility.json`),
under "What this export could not read" -- one bullet per entry, each written as a code span so an
entry such as `<all Azure scopes: scope enumeration failed>` is shown as it is. An Azure scope where
at least one role management policy could not be judged is listed there too, after the Entra ID
entries and after the role assignment principals that could not be read (see "Role assignments whose
principal the directory did not return", labelled "Role assignment principal that could not be
read"), as `roleManagementPolicies/role selection at <scope>` under a label of its own. Every policy
there that could not be judged was kept, none of them left out -- where the scope's role assignment
or eligibility read failed, that is every policy of a role neither used nor changed there -- so
`roleManagementPolicies.json` may hold policies of roles that are neither used nor changed at that
scope, and such a policy is no evidence that its role is in use. The entry does not mean every
policy at the scope was kept: when only one policy could not be judged, the other unused, unchanged
ones are still left out. An Azure subscription whose home tenant could not be read follows those
entries, as `subscriptionHomeTenant at <scope>`, labelled "Azure subscription whose tenant could not
be read": the Azure walk did not enter it, so nothing of it is in the bundle, which does not mean it
holds nothing. The Azure Lighthouse reads that failed come next, labelled "Azure Lighthouse read
that failed" (see "Azure Lighthouse delegations" above), and, for an export run with
`-IncludeServicePrincipalAccess`, the parts of `servicePrincipalAccess.json` that could not be read
come last, labelled "Service principal access part that could not be read" (see "Service principal
access" above). When nothing was
left unread, that section says so. The list is in the
README alone: `inventory.json` and the other JSON files never carry it, so the apply document keeps
exactly the shape the schema describes.

## Notes

- The bundle folder is data you may not want in version control. Add it to `.gitignore`.
- Management groups and subscriptions are context only; the module never creates them.
- Everything `Export-OERInventory` does is read-only; it changes nothing in the tenant.
