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
- `groupsRoster.json`, `scopeHierarchy.json`, `azurePimEligibility.json` -- read-only context.
  `azurePimEligibility.json` (the Azure PIM eligible role assignments at the walked scopes) is
  written only when an Azure section (`RoleAssignments` or `RoleManagementPolicies`) is included.
- `schema.json` -- a formal JSON Schema (draft-07) for the apply document, so a proposal can be
  validated without the module (e.g. `Test-Json -Json (Get-Content proposal.json -Raw) -Schema (Get-Content schema.json -Raw)`).
- `rbac-architect-prompt.md` -- the predefined prompt.
- `README.md` -- explains the bundle, lists under "What this export could not read" everything the
  export could not read (or says that nothing was left unread), and holds the next steps. The list
  is written into this file only, never into `inventory.json` or any other JSON file.

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
Administrative units, catalogs and access packages cannot be renamed through the document.

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
another principal holding the same role and assignment type; a service principal, or a principal of
unknown type, is named by its object id. `principalType` is carried whenever the type is known. A
time-bound assignment carries `durationDays` reconstructed from the live schedule window, so a
re-applied export is `Unchanged`; a permanent one carries neither `durationDays` nor `permanent`.

Both sections are ordinary apply-document sections: propose changes to them like any other. A
directory role's policy always exists, so there is nothing to create or remove and `-Prune` has no
effect on `directoryRoleManagementPolicies`; `directoryRoleAssignments` reconciles, and can be
pruned, only for the `(role, assignmentType)` pairs the document declares.

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

## Unread collections

A read that fails is never written as a fact. A `members`, `scopedRoles`, `resources` or
`resourceRoles` collection that could not be read, or one with an entry the export could name by
nothing the apply engine accepts, is written as `null`, which `Invoke-OERStructure` leaves
untouched: keep it `null` in a proposal and never change it to `[]`, since under `-Prune` an empty
collection removes every live entry. A section that could not be read at all (the group list, the
administrative unit list or the access review list) is reported by a warning and through
`InventoryPartial` under the section's own name (`groups`, `administrativeUnits` or
`accessReviews`), and is written as an empty array, never `null`. The group roster that could not be
read is named `groupsRoster` in the bundle's `IncompleteReads` and written as an empty array in
`groupsRoster.json`. An empty section reported that way is not evidence the tenant has none, so no
deletion is proposed from it.

The bundle's `README.md` lists every such report, and every Azure scope the export could not read
(for `roleAssignments.json` and `roleManagementPolicies.json`, or for `azurePimEligibility.json`),
under "What this export could not read" -- one bullet per entry, each written as a code span so an
entry such as `<all Azure scopes: scope enumeration failed>` is shown as it is. An Azure scope where
at least one role management policy could not be judged is listed there too, after the Entra ID
entries, as `roleManagementPolicies/role selection at <scope>` under a label of its own. Every policy
there that could not be judged was kept, none of them left out -- where the scope's role assignment
or eligibility read failed, that is every policy of a role neither used nor changed there -- so
`roleManagementPolicies.json` may hold policies of roles that are neither used nor changed at that
scope, and such a policy is no evidence that its role is in use. The entry does not mean every
policy at the scope was kept: when only one policy could not be judged, the other unused, unchanged
ones are still left out. When nothing was left unread, that section says so. The list is in the
README alone: `inventory.json` and the other JSON files never carry it, so the apply document keeps
exactly the shape the schema describes.

## Notes

- The bundle folder is data you may not want in version control. Add it to `.gitignore`.
- Management groups and subscriptions are context only; the module never creates them.
- Everything `Export-OERInventory` does is read-only; it changes nothing in the tenant.
