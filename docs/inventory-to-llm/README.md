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
- per-area JSON files (`groups.json`, `catalogs.json`, ...).
- `groupsRoster.json`, `scopeHierarchy.json` -- read-only context.
- `schema.json` -- a formal JSON Schema (draft-07) for the apply document, so a proposal can be
  validated without the module (e.g. `Test-Json -Json (Get-Content proposal.json -Raw) -Schema (Get-Content schema.json -Raw)`).
- `rbac-architect-prompt.md` -- the predefined prompt.
- `README.md` -- a short next-steps guide.

By default the Entra sections plus tenant-wide `RoleAssignments` are captured. Add
`RoleManagementPolicies` to `-Include` to also read PIM policies at every scope (slower). Only
RBAC-relevant groups are detailed in `inventory.json`; the full landscape is in `groupsRoster.json`.
Use `-AllGroupsDetailed` to keep every group in full detail.

## 2. Ask an LLM

Open `rbac-architect-prompt.md`. Leave the `USER PREFERENCES (optional)` block untouched for
best-practice defaults, or set your naming standard and depth. Give the prompt plus the JSON files
to any capable LLM. It returns three proposals: Foundational, Recommended, Advanced -- each a
complete `Invoke-OERStructure` document.

## 3. Validate and apply

Save a proposal (for example `proposal.json`) and run:

```powershell
Test-OERStructure -Path .\proposal.json          # offline schema validation
Invoke-OERStructure -Path .\proposal.json -WhatIf # preview the changes
Invoke-OERStructure -Path .\proposal.json         # apply
```

## Groups schema -- pimPolicy

PIM-onboarded groups carry a `pimPolicy` object in the inventory and apply document. The schema
supports two forms:

**Flat (member-only, back-compat):**

```json
"pimPolicy": {
  "activationMaxHours": 8,
  "authenticationContextId": "c1",
  "allowPermanentEligibility": false,
  "eligibleDurationDays": 365,
  "allowPermanentActive": false,
  "activeDurationDays": 180,
  "activationEnabledRules": ["MultiFactorAuthentication", "Justification"],
  "activeEnabledRules": [],
  "eligibleAlertRecipients": [],
  "activeAlertRecipients": [],
  "activationAlertRecipients": []
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
    "activationEnabledRules": ["MultiFactorAuthentication", "Justification", "Ticketing"],
    "allowPermanentEligibility": false,
    "eligibleDurationDays": 90
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
| `activationEnabledRules` | string[] | Requirements on activation: `Justification`, `MultiFactorAuthentication`, `Ticketing`. |
| `activeEnabledRules` | string[] | Requirements on admin active assignment: same enum values. |
| `allowPermanentEligibility` | boolean | Allow permanent eligible assignments (no expiry). |
| `eligibleDurationDays` | integer 1-3650 | Max days for time-bound eligible assignments. |
| `allowPermanentActive` | boolean | Allow permanent active assignments (no expiry). |
| `activeDurationDays` | integer 1-3650 | Max days for time-bound active assignments. |
| `eligibleAlertRecipients` | string[] | Extra admin email addresses for the eligible-assignment alert. Defaults are always kept. |
| `activeAlertRecipients` | string[] | Extra admin email addresses for the active-assignment alert. Defaults are always kept. |
| `activationAlertRecipients` | string[] | Extra admin email addresses for the role-activation alert. Defaults are always kept. |

Groups that are not PIM-onboarded carry no `pimPolicy` in the inventory and are silently skipped
by the apply engine.

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

`scope` accepts any `allowedTargetScope` value (e.g. `allMemberUsers`, `specificDirectoryUsers`,
`notSpecified`). **`noSubjects` is not one of them** -- it is a legacy beta spelling that is absent
from the v1.0 enum, so the engine substitutes `notSpecified` and warns on every apply; write
`notSpecified` directly for administrator-assignment-only.
`users` and `groups` are resolved by the engine (names or object ids). Always declare
`requestorScope`: unlike the other policy fields it is not preserved on update -- if it is omitted and
the policy is updated for any other reason, the scope defaults to `allMemberUsers`. The inventory always
emits it, so round-tripped documents are safe.

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

When `description` is omitted from an apply document, the engine uses the policy display name as the
description. Set `"description": ""` explicitly to clear it.

### Overlay vs. preserve semantics

The policy is applied as a FULL object (PUT), but `Set-OERAccessPackageAssignmentPolicy` is
read-modify-write: it reads the live policy first and overlays only what is supplied. The apply engine
diffs and writes ONLY the fields you declare in the apply document, so fields you omit are PRESERVED
from the live policy. Declaring a field EMPTY is not the same as omitting it: `"approvalStages": []`
clears every live approval stage, just as `"description": ""` clears the description. The exceptions
to "omit = preserved":

- `description` -- defaults to the policy display name when omitted (it is not preserved). Set
  `"description": ""` to clear it.
- `requestorScope` -- always (re)applied; if omitted it defaults to `allMemberUsers` when the policy is
  updated (see above). Declare it explicitly; the inventory always emits it.

These out-of-scope fields are always preserved (never written by this module):

- `reviewSettings` -- policy-embedded access reviews.
- `questions` -- custom requestor questions.
- Fallback approvers (`fallbackPrimaryApprovers` / `fallbackEscalationApprovers`) are preserved
  when their stage is otherwise unchanged. If a stage is rebuilt (because another field in it
  changed), fallback approvers on that stage are not carried over -- this is a known limitation.

## Notes

- The bundle folder is data you may not want in version control. Add it to `.gitignore`.
- Management groups and subscriptions are context only; the module never creates them.
- Everything `Export-OERInventory` does is read-only; it changes nothing in the tenant.
