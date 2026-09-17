# Live verification checklist -- PR #53 (apply-engine round-trip)

**PR #53 does not merge until every box below has a written result.** A box with no result line
filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible to run,
write "cannot be verified, and therefore we do not know" on its result line and say why; do not leave
it blank and do not tick it.

This file lives on the branch rather than in the PR description for two reasons: a completed
checklist is larger than GitHub's 65,536-character body limit, and results written here land in the
diff, where they are reviewable and versioned instead of being edited invisibly. The PR body carries
the summary, the contracts verified against Microsoft Learn, and the lists of what needs no live test
and what was deliberately not fixed; it links here.

Sections 1-4 change what the apply engine writes to a live tenant. Section 5 is round-trip fidelity.
Section 6 holds the questions the fix rounds raised after the first live pass. Run 1-4 first; they are
the ones where a wrong fix degrades a tenant silently.

**Setup, once.** Use a throwaway tenant or a disposable slice of a test tenant. You need: one
security group (`oer-live-a`), one PIM-onboarded group (`oer-live-pim`), one dynamic group
(`oer-live-dyn`), two catalogs (`OER-CAT-A`, `OER-CAT-B`), an access package with the SAME display
name in both catalogs (`oer-live-ap`), one assignment policy on each, one administrative unit
(`oer-live-au`) that does NOT exist yet, and one access review on the package in `OER-CAT-A`.

**How to read a check.** Every `Apply { ... }` below is a *fragment*, not a runnable document. Two
things have to be added before it can be applied, and neither is optional:

1. **A top-level `"version"`.** Without it the offline validator reports
   `Required key "version" is missing or empty.` and `Invoke-OERStructure` aborts before it writes
   anything -- so a fragment pasted verbatim into a file fails validation instead of testing what the
   check is about. `"tenantAlias"` is optional but worth setting, since it is what supplies the
   profile defaults.
2. **The identifying `displayName`,** wherever the fragment shows only the part under test. Check 1.6
   writes `{ "pimPolicy": { ... } }`; that is one element of the `groups` array and still needs
   `"displayName": "oer-live-pim"` beside `pimPolicy`.

So the document actually applied for check 1.1 is this, and `$Doc` is the file you put it in:

```json
{
  "version": "1.0",
  "tenantAlias": "<alias>",
  "groups": [ { "displayName": "oer-live-a", "description": null, "mailNickname": null } ]
}
```

**The loop.** Wrap the fragment, validate it offline, read the `-WhatIf` plan, then apply. The helper
below does all four and leaves the exact document on disk, which is what you cite on the result line.

```powershell
$Alias = '<your-tenant-alias>'
$Doc   = './live/doc.json'
New-Item -ItemType Directory -Path './live' -Force | Out-Null

Connect-OER -TenantAlias $Alias -IncludeARM

function Invoke-LiveCheck {
    param(
        [Parameter(Mandatory)][string]$Fragment,
        [switch]$Prune,
        [switch]$PlanOnly
    )

    # 1. Wrap the checklist fragment into a valid document, and keep it for the record.
    #    A JSON null survives ConvertFrom-Json / ConvertTo-Json as null, which is the whole
    #    distinction section 1 tests -- read $Doc back if a result surprises you.
    $Document = $Fragment | ConvertFrom-Json
    $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
    $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
    $Document | ConvertTo-Json -Depth 20 | Set-Content -Path $Doc -Encoding utf8

    # 2. Offline validation. Anything here is wrong with the document, not with the module.
    $Validation = Test-OERStructure -Path $Doc
    if (-not $Validation.Valid) { $Validation.Errors; return }

    # 3. The plan. Under -WhatIf every write is Skipped and every read still runs.
    $Splat = @{ Path = $Doc }
    if ($Prune) { $Splat['Prune'] = $true }
    Write-Host '--- plan ---'
    Invoke-OERStructure @Splat -WhatIf

    # 4. The real run.
    if ($PlanOnly) { return }
    Write-Host '--- apply ---'
    Invoke-OERStructure @Splat
}
```

`Invoke-OERStructure` declares `ConfirmImpact = 'High'` and the handlers gate every write on the
engine's `ShouldProcess`, so each individual change prompts. Answer them one at a time on the
destructive checks; add `-Confirm:$false` to the `$Splat` call only once the plan you just read is
the plan you want.

Check 1.1 then reads, end to end:

```powershell
Invoke-LiveCheck '{ "groups": [ { "displayName": "oer-live-a", "description": null, "mailNickname": null } ] }'
Get-OERGroup -DisplayName oer-live-a | Select-Object DisplayName, Description
```

and a check that needs pruning -- 1.9, 2.1, 2.2 -- adds `-Prune`, or `-Prune -PlanOnly` first to
read the plan without acting on it.

**Placeholders.** Sections 2-5 are copy/paste blocks with angle-bracket placeholders left in them on
purpose: they are inside single-quoted strings, so a forgotten one fails loudly with
`Failed to resolve ... '<user-a>'` rather than acting on the wrong object. Replace them as you go:

| Placeholder | What it is |
|---|---|
| `<user-a>` / `<user-b>` | Two different ordinary users (UPN or object id). |
| `<policy-1>` | The display name of the FIRST assignment policy on `oer-live-ap` in `OER-CAT-A`. |
| `<review-name>` | The access review created on that package. |
| `<semi-annual-review>` | The semi-annual review from check 5.5. |
| `<two-stage-review>` | The two-stage review from check 5.7. |

---

### 1. Explicit null means undeclared

Every check here is the same shape: put a live value in the tenant, declare the field as JSON `null`,
apply, and confirm the live value is untouched and the record reads `Unchanged`. Before the fix each
of these silently overwrote live state.

- [x] **1.1 Group description and mail nickname.** Set a description on `oer-live-a` in the portal.
  Apply `{ "groups": [ { "displayName": "oer-live-a", "description": null, "mailNickname": null } ] }`.
  **Expect:** result `Unchanged`, and `Get-OERGroup -DisplayName oer-live-a` still shows the
  description. **Failure looks like:** an `Updated` record and an empty description.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.2 The same field as an explicit empty string still clears it.** Re-apply with
  `"description": ""`. **Expect:** `Updated`, description now empty. This proves the fix did not
  over-correct. **Failure looks like:** `Unchanged` -- the fix went too far and `""` is now inert.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.3 Access package hidden flag.** Hide `oer-live-ap` in the portal. Apply
  `{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A", "hidden": null } ] }`.
  **Expect:** `Unchanged`, package still hidden and NOT requestable in My Access.
  **Failure looks like:** the package becomes visible and requestable.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.4 PIM-for-Groups authentication context.** Set an authentication context (for example `c1`)
  on `oer-live-pim`'s member policy. Apply
  `{ "groups": [ { "displayName": "oer-live-pim", "pimPolicy": { "member": { "authenticationContextId": null } } } ] }`.
  **Expect:** `Unchanged`, and the portal still shows the context enabled on activation.
  **Failure looks like:** the conditional-access requirement disappears -- this is the sharpest
  regression in the whole PR, so check the portal, not just the record.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.5 The same field as `""` still disables it.** Re-apply with `"authenticationContextId": ""`.
  **Expect:** `Updated`, context disabled. **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.6 PIM permanence and MFA.** With `allowPermanentEligibility` true and
  `MultiFactorAuthentication` in the activation enablement rules, apply
  `{ "groups": [ { "displayName": "oer-live-pim", "pimPolicy": { "member": { "allowPermanentEligibility": null, "activationEnablement": null } } } ] }`.
  **Expect:** `Unchanged`; permanence still allowed and MFA still required.
  **Failure looks like:** permanence revoked and MFA silently removed.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.7 Requestor scope -- the only null that WIDENS access.** Set the assignment policy on
  `oer-live-ap` to `SpecificDirectoryUsers` with one named user. Apply
  `{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A", "assignmentPolicies": [ { "displayName": "<policy>", "requestorScope": null } ] } ] }`.
  **Expect:** `Unchanged`, scope still `SpecificDirectoryUsers` with the same user.
  **Failure looks like:** the scope becomes "All member users" -- everyone in the tenant can now
  request the package.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.8 Approval requirement.** With approval ON, apply `"requireApproval": null`.
  **Expect:** `Unchanged`, approval still required. **Failure looks like:** approval turned off.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.9 A null child collection must not empty it under -Prune.** With `oer-live-a` holding two
  members, run `Invoke-OERStructure -Prune` on
  `{ "groups": [ { "displayName": "oer-live-a", "members": null } ] }`.
  **Expect:** no `Removed` records, both members still in the group.
  **Failure looks like:** both members removed. Run this one with `-WhatIf` FIRST and read the plan
  before running it for real.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **1.10 An explicitly empty array still empties it.** Re-run with `"members": []` and `-Prune`.
  **Expect:** both members removed. **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

---

### 2. The two new prune / report passes

- [x] **2.1 Eligibility is reported as `Extra` without `-Prune`.** Grant an eligibility the document
  does not declare, then apply without `-Prune`.

  ```powershell
  Add-OERGroupEligibility -Group oer-live-pim -User '<user-a>' -AccessType member -DurationDays 30

  Invoke-LiveCheck '{ "groups": [ { "displayName": "oer-live-pim",
    "eligibility": [ { "principal": "<user-b>", "accessType": "member", "durationDays": 30 } ] } ] }'

  Get-OERGroupEligibility -Group oer-live-pim | Format-Table PrincipalId, AccessType, EndDateTime
  ```

  **Expect:** one `Extra` record naming `<user-a>` and `member`, and the eligibility still listed.
  **Failure looks like:** no `Extra` record at all -- the pass did not run.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **2.2 Eligibility is removed with `-Prune`, for both access types.** The helper prints the
  `-WhatIf` plan before it acts, so read it before answering the prompts.

  ```powershell
  # member
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-pim",
    "eligibility": [ { "principal": "<user-b>", "accessType": "member", "durationDays": 30 } ] } ] }'
  Get-OERGroupEligibility -Group oer-live-pim | Format-Table PrincipalId, AccessType

  # owner -- same document, so the owner eligibility is undeclared and must be pruned too
  Add-OERGroupEligibility -Group oer-live-pim -User '<user-a>' -AccessType owner -DurationDays 30
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-pim",
    "eligibility": [ { "principal": "<user-b>", "accessType": "member", "durationDays": 30 } ] } ] }'
  Get-OERGroupEligibility -Group oer-live-pim | Format-Table PrincipalId, AccessType
  ```

  **Expect:** a `Removed` record each time and the eligibility gone from the portal.
  **Failure looks like:** a `Failed` record carrying a Graph error -- most likely on `owner`, which is
  the path `Remove-OERGroupEligibility` is least exercised on.
  **Result (member):** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.
  **Result (owner):** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **2.3 An undeclared assignment policy is reported `Extra` and never deleted.** Add a second
  assignment policy to `oer-live-ap` in `OER-CAT-A` through the portal first.

  ```powershell
  $Ap = Get-OERAccessPackage -Catalog OER-CAT-A | Where-Object DisplayName -eq 'oer-live-ap'
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id | Format-Table Id, DisplayName

  Invoke-LiveCheck -Prune '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A",
    "assignmentPolicies": [ { "displayName": "<policy-1>", "durationInDays": 30 } ] } ] }'

  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id | Format-Table Id, DisplayName
  ```

  **Expect:** one `Extra` record naming the second policy, and BOTH policies still listed afterwards.
  **Failure looks like:** the second policy is gone -- that is destructive reach this PR deliberately
  did not add.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **2.4 Prune warnings are truthful under `-WhatIf`.**

  ```powershell
  Invoke-LiveCheck -Prune -PlanOnly '{ "groups": [ { "displayName": "oer-live-a", "members": [] } ] }' -WarningVariable Plan
  $Plan | Where-Object { $_ -match 'remov' }
  ```

  **Expect:** every matching warning says "would remove".
  **Failure looks like:** "removing undeclared ..." while nothing was removed.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **2.5 And they still say "removing" on a real run.**

  ```powershell
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-a", "members": [] } ] }' -WarningVariable Real
  $Real | Where-Object { $_ -match 'remov' }
  ```

  **Expect:** "removing undeclared ...". **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

---

### 3. Object identity and ordering

- [x] **3.1 An access package is matched inside its declared catalog.** `oer-live-ap` must exist in
  BOTH catalogs with DIFFERENT descriptions before you start.

  ```powershell
  # Before
  Get-OERAccessPackage -Catalog OER-CAT-A | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id, Description
  Get-OERAccessPackage -Catalog OER-CAT-B | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id, Description

  Invoke-LiveCheck '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-B",
    "description": "changed by check 3.1" } ] }'

  # After -- only the OER-CAT-B row may have changed
  Get-OERAccessPackage -Catalog OER-CAT-A | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id, Description
  Get-OERAccessPackage -Catalog OER-CAT-B | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id, Description
  ```

  **Expect:** the plan names the `OER-CAT-B` id, and only that description changed.
  **Failure looks like:** the `OER-CAT-A` package changed, or a `Failed` record saying
  `AmbiguousName ... matches 2 access packages` -- which is the pre-fix behaviour.
  **Result:** PASS. The `OER-CAT-B` package (`00000000-0000-0000-0000-000000000001`) carries
  `changed by check 3.1`; the `OER-CAT-A` package (`00000000-0000-0000-0000-000000000002`) was not
  touched, and no `AmbiguousName` error was raised.

- [x] **3.2 `Get-OERAccessPackage -Catalog` actually narrows.** The `catalog/id` filter is not
  documented for v1.0 and this endpoint family has a recorded history of silently IGNORING an
  unsupported server-side filter, so a 200 response proves nothing on its own. Two catalogs each
  holding a package called `oer-live-ap` is what makes this decidable.

  ```powershell
  $All = @(Get-OERAccessPackage)
  $InA = @(Get-OERAccessPackage -Catalog OER-CAT-A)
  $InB = @(Get-OERAccessPackage -Catalog OER-CAT-B)
  'all = {0}, OER-CAT-A = {1}, OER-CAT-B = {2}' -f $All.Count, $InA.Count, $InB.Count

  # the two catalogs must return DIFFERENT ids for the same display name
  $InA | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id
  $InB | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id
  @($InA.Id | Where-Object { $InB.Id -contains $_ }).Count   # expect 0 -- disjoint sets
  ```

  **Expect:** both catalog counts are strictly smaller than `all`, the two `oer-live-ap` ids differ,
  and the overlap count is 0.
  **Failure looks like:** the counts equal `all`, or the same id comes back from both catalogs.
  **Do NOT assert on `CatalogId`** -- see 3.2b; it is empty on every access package the module
  returns, and asserting on it would fail this check for the wrong reason.
  **Result:** PASS on the narrowing. `all = 9`, `OER-CAT-B = 1`, and the id returned for `OER-CAT-B`
  (`00000000-0000-0000-0000-000000000001`) is not the `OER-CAT-A` one (`00000000-0000-0000-0000-000000000002`). The filter is honoured server-side.

- [x] **3.2b `CatalogId` is empty on every access package -- can `$expand=catalog` fill it?**
  Found while running 3.2. `Get-OERAccessPackage` returns objects whose `CatalogId` is always empty,
  including the format view's own column. This is a **pre-existing read-contract gap, not a
  regression from this PR**, and nothing in the apply engine or the inventory consumes the property --
  but the shape advertises a field it can never populate. Learn confirms the cause: the v1.0
  `accessPackage` entity has **no `catalogId` property at all** (only `createdDateTime`,
  `description`, `displayName`, `id`, `isHidden`, `modifiedDateTime`), and `catalog` is a
  navigation property that the resource page marks `Read-only. Nullable.` **without** the
  "Supports `$expand`" note that `assignmentPolicies` carries. The List endpoint does document
  `$expand` support in general. So the question is whether `catalog` is expandable in practice.

  ```powershell
  # raw, one call -- does the response carry a catalog object?
  $Raw = & (Get-Module Omnicit.EntraRBAC) {
      Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/entitlementManagement/accessPackages?$expand=catalog' -All
  }
  @($Raw.value)[0].catalog
  ```

  **Expect one of, and write down which:** (a) a catalog object comes back -- then the fix is to add
  `catalog` to `Get-OERAccessPackage`'s expand list, which is exactly how PR #45 fixed the same class
  of gap on `Get-OERAccessPackageAssignment`; or (b) an error or a null -- then `CatalogId` cannot be
  populated from this endpoint and the honest fix is to drop it from the shape and the format view.
  Either answer is a real result. **This is a follow-up issue either way, not a change this PR makes.**
  **Result:** ANSWERED -- (a). `$expand=catalog` works. The raw call returned a full catalog
  object: `id 00000000-0000-0000-0000-000000000003`, `displayName OER-CAT-B`,
  `isExternallyVisible False`, `catalogType userManaged`, `state published`. So `CatalogId` can be
  populated, and the fix is the PR #45 one -- add `catalog` to the expand list. **Being fixed in
  this PR after all**, now that the premise is verified rather than assumed.

- [x] **3.3 Two packages with the same name in ONE catalog report `Failed`, not a wrong write.**
  Create the duplicate inside `OER-CAT-A` through the portal if the tenant permits it.

  ```powershell
  Get-OERAccessPackage -Catalog OER-CAT-A | Where-Object DisplayName -eq 'oer-live-ap' | Select-Object Id, DisplayName

  Invoke-LiveCheck '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A",
    "description": "changed by check 3.3" } ] }'
  ```

  **Expect:** a `Failed` record naming BOTH ids. If the tenant refuses to create the duplicate at all,
  that answers the open question about per-catalog uniqueness -- write that down instead.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **3.4 A group declared into a not-yet-existing AU succeeds on the FIRST apply.** Delete
  `oer-live-au` and `oer-live-new` first if they exist.

  ```powershell
  Get-OERAdministrativeUnit -Filter "displayName eq 'oer-live-au'"   # expect nothing

  Invoke-LiveCheck '{
    "groups": [ { "displayName": "oer-live-new", "administrativeUnit": "oer-live-au" } ],
    "administrativeUnits": [ { "displayName": "oer-live-au", "members": [ "oer-live-a" ] } ] }'

  Get-OERAdministrativeUnit -DisplayName oer-live-au -IncludeMembers |
      Select-Object -ExpandProperty Members | Format-Table DisplayName, ObjectType
  ```

  **Expect:** the AU is `Created` first, then the group is `Created` -- and `oer-live-new` shows up as
  a member of the AU.
  **Failure looks like:** `Failed: No administrative unit found for 'oer-live-au'` and no group at all.
  **Result:** PASS. Plan showed `Skipped would create administrative unit oer-live-au` and
  `Skipped would configure member 'oer-live-a' after unit is created`; the real run gave
  `Created administrative unit oer-live-au (00000000-0000-0000-0000-000000000004)` then
  `Created group oer-live-new (00000000-0000-0000-0000-000000000005)`, and both `oer-live-a` and `oer-live-new` are members.
  (The block above originally read `-AdministrativeUnit oer-live-au`, which PowerShell prefix-matched
  onto `-Id` and produced `Invalid object identifier`. The parameter is `-DisplayName`; corrected.)

- [x] **3.5 And the AU section still runs afterwards.** Read the same run's records.

  **Expect:** `oer-live-a` was added as an AU member by the administrativeUnits section, and
  `oer-live-au` is NOT reported `Created` twice.
  **Failure looks like:** two `Created` records for the AU, or the declared AU member never added.
  **Result:** PASS. One `Created` from the pre-pass, then the administrativeUnits section reported
  `Unchanged administrative unit properties match` and `Updated added member 'oer-live-a'`.

- [x] **3.6 Does `-Prune` on that same document undo the pre-pass?** Raised by 3.4's own output, which
  ended with `Extra undeclared member '00000000-0000-0000-0000-000000000005' (use -Prune to remove)` -- that id is
  `oer-live-new`, the group the groups section had just placed into the AU seconds earlier. The two
  sections model the same relationship from opposite ends: `groups[].administrativeUnit` puts a group
  in, and `administrativeUnits[].members` is the authoritative list the prune pass reconciles against.
  `Sync-OERStructureAdministrativeUnit` never reads the groups section, so it cannot know the
  placement was declared.

  ```powershell
  # SAME document as 3.4, now with -Prune. Read the plan before answering the prompts.
  Invoke-LiveCheck -Prune -PlanOnly '{
    "groups": [ { "displayName": "oer-live-new", "administrativeUnit": "oer-live-au" } ],
    "administrativeUnits": [ { "displayName": "oer-live-au", "members": [ "oer-live-a" ] } ] }'
  ```

  **Expect (the suspected defect):** the plan says it would remove `oer-live-new` from `oer-live-au` --
  the document fights itself, and a second apply does not put the group back, because the group now
  exists and is never re-created into the unit. If so, the answer is not a code change in this PR but
  a documented rule: **a group declared with `administrativeUnit` must also be listed in that unit's
  `members`**, and the schema description and prompt template should say so.
  **Failure looks like** (i.e. no defect): the plan leaves `oer-live-new` alone, which would mean the
  handler does cross-reference the groups section after all.
  **Do not run this one for real** unless you want the group removed from the unit -- `-PlanOnly` is
  enough to answer it.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

---

### 4. Live-state preservation on the PIM and EM write paths

- [x] **4.1 A permanence-only call preserves the live eligible maximum.**

  ```powershell
  Set-OERGroupPimPolicy -Group oer-live-pim -AccessType member -EligibleDurationDays 30
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member |
      Select-Object AllowPermanentEligibility, EligibleDurationDays

  Set-OERGroupPimPolicy -Group oer-live-pim -AccessType member -AllowPermanentEligibility
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member |
      Select-Object AllowPermanentEligibility, EligibleDurationDays
  ```

  **Expect:** `EligibleDurationDays` is 30 both times.
  **Failure looks like:** it is 365 -- the parameter default was sent over the live value.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.2 Same for the active side.**

  ```powershell
  Set-OERGroupPimPolicy -Group oer-live-pim -AccessType member -ActiveDurationDays 90
  Set-OERGroupPimPolicy -Group oer-live-pim -AccessType member -AllowPermanentActive
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member |
      Select-Object AllowPermanentActive, ActiveDurationDays
  ```

  **Expect:** still 90. **Failure looks like:** 180. **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.3 A non-day duration survives.** Only runnable if the portal will store an eligible
  expiration that is not a whole number of days.

  ```powershell
  # After setting a non-P{n}D expiration in the portal:
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member | Select-Object EligibleDurationDays
  Set-OERGroupPimPolicy -Group oer-live-pim -AccessType member -AllowPermanentEligibility
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member | Select-Object EligibleDurationDays
  ```

  **Expect:** the value is unchanged across the call, and `EligibleDurationDays` reports a number
  rather than nothing. If the portal only offers whole days, say so -- that is a legitimate
  "cannot be verified".
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.4 Requestor settings survive an unrelated policy edit.** Enable self-remove and on-behalf
  update on the policy in the portal first.

  ```powershell
  $Ap  = Get-OERAccessPackage -Catalog OER-CAT-A | Where-Object DisplayName -eq 'oer-live-ap'
  $Pol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id | Select-Object -First 1
  $Pol.RequestorSettings    # note all eight members BEFORE

  Invoke-LiveCheck '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A",
    "assignmentPolicies": [ { "displayName": "<policy-1>", "durationInDays": 45 } ] } ] }'

  (Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id | Select-Object -First 1).RequestorSettings
  ```

  **Expect:** `allowSelfRemove` and `allowOnBehalfUpdate` still true.
  **Failure looks like:** both reset to false -- the full-object PUT wiping members the builder does
  not model.
  **Result:** BLOCKED -- the run never reached the question, because it exposed a different and
  more serious defect. With `oer-live-ap` present in both catalogs (the arrangement checks 3.1 and
  3.2 require), the package itself resolved correctly (`Unchanged access package properties
  match`) but creating the assignment policy failed with `Access package display name
  'oer-live-ap' matches 2 access packages (00000000-0000-0000-0000-000000000001, 00000000-0000-0000-0000-000000000002)`. The catalog-scoped
  resolution this PR added covers the package but NOT the nested assignment-policy paths, which
  still pass the display name downstream. Being fixed; see the follow-ups section. Renaming the
  `OER-CAT-B` package to `oer-live-ap2` works around it and the rest of 4.4 then runs clean.

  **Re-run 2026-08-24: PASS**, reported by Philip, after renaming the `OER-CAT-B` package to
  `oer-live-ap2`. Aggregate confirmation, no per-item output captured. Note the underlying defect
  is FIXED -- the four nested paths now pass the resolved id -- so the rename should no longer be
  needed; check 6.3 exercises the same read.

- [x] **4.5 A partial `requestorSettings` PUT -- the open Learn question.** Learn does not state
  whether an omitted member of this complex type is preserved.

  ```powershell
  $Settings = New-OERAccessPackageRequestorSettings -AllowSelfRequest -AllowSelfExtend
  Set-OERAccessPackageAssignmentPolicy -Id $Pol.Id -DisplayName $Pol.DisplayName -RequestorSettings $Settings
  (Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id |
      Where-Object Id -eq $Pol.Id).RequestorSettings
  ```

  **Expect (this PR's assumption):** the merge means all eight members arrive populated, so nothing
  can be reset by omission. Record what the wire actually did -- especially `allowOnBehalfRemove`,
  which the builder above does not set.
  **Result:** BLOCKED on the block as first written -- `Set-OERAccessPackageAssignmentPolicy`
  prompted for `DisplayName:`, which is `Mandatory`. That is correct behaviour, not a defect: the
  update is a full-object PUT and Learn marks `displayName` required in the body. The block now
  passes it. Re-run and record what the eight members read back as.

  **Re-run 2026-08-24: PASS**, reported by Philip, with `-DisplayName` supplied. Aggregate
  confirmation, no per-item output captured.

- [x] **4.6 Approval-stage fallback approvers survive a rebuild.** Configure the policy in the portal
  with Manager as the first approver plus a named fallback approver.

  ```powershell
  $Pol.ApprovalStages | Format-List

  Invoke-LiveCheck '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A",
    "assignmentPolicies": [ { "displayName": "<policy-1>", "requireApproval": true,
      "approvalStages": [ { "durationDays": 14, "manager": true, "fallbackUsers": [ "<user-a>" ] } ] } ] } ] }'

  (Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id |
      Where-Object Id -eq $Pol.Id).ApprovalStages | Format-List
  ```

  **Expect:** the fallback approver is present after the rebuild.
  **Failure looks like:** an empty fallback list -- a manager-approval request then becomes
  unapprovable for a requestor with no manager.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.7 A declared fallback approver is written.** Same run as 4.6: confirm the portal shows
  `<user-a>` as the fallback, and record which `@odata.type` the collection accepted (Learn enumerates
  them only for `primaryApprovers`). A group fallback uses `"fallbackGroups": [ "<group>" ]`.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.8 An empty assignment-policy description -- the open Learn question.** Learn marks
  `description` **Required** in the PUT body and is silent on the empty case.

  ```powershell
  Set-OERAccessPackageAssignmentPolicy -Id $Pol.Id -DisplayName $Pol.DisplayName -Description ''
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id |
      Where-Object Id -eq $Pol.Id | Select-Object DisplayName, Description
  ```

  **Expect one of two, and write down which:** (a) it succeeds and the description is cleared -- the
  fix is right as shipped; or (b) a 400 -- then the cmdlet should reject an empty description up front
  instead, and that is a follow-up issue.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.9 And it converges.** Only if 4.8 succeeded.

  ```powershell
  $Frag = '{ "accessPackages": [ { "displayName": "oer-live-ap", "catalog": "OER-CAT-A",
    "assignmentPolicies": [ { "displayName": "<policy-1>", "description": "" } ] } ] }'
  Invoke-LiveCheck $Frag
  Invoke-LiveCheck $Frag
  ```

  **Expect:** `Updated` then `Unchanged`.
  **Failure looks like:** `Updated` both times -- the non-idempotency is not fixed.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.10 Group owners are added, reported and pruned.**

  ```powershell
  # add
  Invoke-LiveCheck '{ "groups": [ { "displayName": "oer-live-a", "owners": [ "<user-a>" ] } ] }'
  (Get-OERGroup -Group oer-live-a -IncludeOwners).Owners | Format-Table DisplayName, ObjectType

  # prune -- declare a DIFFERENT owner; <user-a> must be Removed
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-a", "owners": [ "<user-b>" ] } ] }'
  (Get-OERGroup -Group oer-live-a -IncludeOwners).Owners | Format-Table DisplayName, ObjectType

  # last owner -- <user-b> is now the only owner, and it is a user
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-a", "owners": [] } ] }'
  (Get-OERGroup -Group oer-live-a -IncludeOwners).Owners | Format-Table DisplayName, ObjectType
  ```

  **Expect:** `Updated`, then `Removed`, then a `Skipped` record citing the last-owner rule -- NOT a
  `Failed`, and the owner still there.
  **Failure looks like:** a `Failed` carrying Graph's rejection, which means the guard did not fire.
  **Result (add):** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.
  **Result (prune):** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.
  **Result (last owner):** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.11 Does the last-owner rule apply to a service principal?** Learn scopes the restriction to
  "the last owner (a user object)", and this PR's guard is deliberately wider. If you can make a
  service principal the sole owner, re-run the third block of 4.10 against it.

  **Expect:** unknown -- that is the point. Either Graph accepts the removal (the guard is
  over-conservative and can be narrowed) or it refuses (the guard is right as written).
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.12 A dynamic group's members are left alone.**

  ```powershell
  Invoke-LiveCheck -Prune '{ "groups": [ { "displayName": "oer-live-dyn", "members": [ "<user-a>" ] } ] }'
  (Get-OERGroup -Group oer-live-dyn -IncludeMembers).Members | Format-Table DisplayName
  ```

  **Expect:** one `Skipped` record per declared member saying the membership rule owns the membership,
  no add or remove call, and no prune pass.
  **Failure looks like:** `Failed` records carrying Graph's rejection -- the pre-fix behaviour.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.13 A `membershipRule` change IS applied on an already-dynamic group.** This is an open Learn
  question -- `membershipRule` is absent from Learn's updatable-properties table for groups.

  ```powershell
  Get-OERGroup -Group oer-live-dyn | Select-Object MembershipRule, MembershipRuleProcessingState

  Invoke-LiveCheck '{ "groups": [ { "displayName": "oer-live-dyn",
    "membershipRule": "(user.department -eq \"Live Check\")" } ] }'

  Get-OERGroup -Group oer-live-dyn | Select-Object MembershipRule, MembershipRuleProcessingState
  ```

  **Expect:** `Updated`, and the portal shows the new rule.
  **Failure looks like:** a Graph rejection, or `Unchanged` while the rule differs.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.14 Immutable group drift is reported, not attempted.**

  ```powershell
  Invoke-LiveCheck '{ "groups": [ { "displayName": "oer-live-a", "roleAssignable": true } ] }'
  Get-OERGroup -Group oer-live-a | Select-Object DisplayName, IsAssignableToRole
  ```

  **Expect:** a warning plus one `Skipped` record naming the divergence, and NO
  `Unchanged 'group properties match'`.
  **Failure looks like:** `Unchanged` -- the pre-fix lie.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.15 Catalog external visibility round-trips.** Set `OER-CAT-A` to allow external users first,
  so step 1 really is a no-op.

  ```powershell
  Get-OERCatalog -DisplayName OER-CAT-A | Select-Object DisplayName, ExternallyVisible

  # 1. re-declare the live value -- must be a no-op
  Invoke-LiveCheck '{ "catalogs": [ { "displayName": "OER-CAT-A", "externallyVisible": true } ] }'
  # 2. flip it
  Invoke-LiveCheck '{ "catalogs": [ { "displayName": "OER-CAT-A", "externallyVisible": false } ] }'

  Get-OERCatalog -DisplayName OER-CAT-A | Select-Object DisplayName, ExternallyVisible
  ```

  **Expect:** `Unchanged` on the first, `Updated` on the second, and the portal follows.
  **Failure looks like:** `Updated` on the first -- the field does not round-trip.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **4.16 A paused membership rule round-trips.** Pause `oer-live-dyn`'s rule in the portal first.

  ```powershell
  $Inv = Get-OERInventory -Include Groups -GroupFilter "displayName eq 'oer-live-dyn'"
  $Inv.groups | Select-Object displayName, membershipRule, membershipRuleProcessingState

  $Inv | Invoke-OERStructure -WhatIf
  ```

  **Expect:** `membershipRuleProcessingState` is `Paused` in the captured document, and the plan is
  `Unchanged`.
  **Failure looks like:** the key is absent -- the next apply then silently resumes the rule.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

---

### 5. Access review round-trip

- [x] **5.1 The settings actually round-trip.** Configure the review on `oer-live-ap` with auto-apply
  on, recommendations on, mail and reminder notifications on, justification required, and a default
  decision.

  ```powershell
  $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter '<review-name>'
  $Inv.accessReviews | Select-Object displayName, mailNotification, reminderNotification,
      requireJustification, recommendationsEnabled, autoApplyDecisions, defaultDecision
  ```

  **Expect:** all six keys present with the values the portal shows.
  **Failure looks like:** none of them present -- the pre-fix state.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.2 The wire spellings are what we send.** Same review, one level down -- this is the check
  that the `settings` key names really are `mailNotificationsEnabled`,
  `justificationRequiredOnApproval`, `autoApplyDecisionsEnabled` and so on.

  ```powershell
  Get-OERAccessReviewDefinition -DisplayName '<review-name>' |
      Select-Object DisplayName, MailNotificationsEnabled, ReminderNotificationsEnabled,
          JustificationRequired, RecommendationsEnabled, AutoApplyDecisionsEnabled,
          DefaultDecision, DefaultDecisionEnabled
  ```

  **Expect:** every value matches the portal.
  **Failure looks like:** an empty value where the portal shows a setting -- a wrong wire spelling
  reads as "not configured".
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.3 A bounded series exports as bounded.** Create one review limited to N occurrences and one
  with an end date.

  ```powershell
  $Inv = Get-OERInventory -Include AccessReviews
  $Inv.accessReviews | Select-Object displayName, recurrence, startDate, endDate, occurrences
  ```

  **Expect:** `occurrences` on the first and `endDate` on the second, and never both on one review.
  **Failure looks like:** neither key -- the series exports as unbounded and a rebuild in another
  tenant runs forever.
  **Result:** INCONCLUSIVE, not yet a pass or a fail. All six reviews in the tenant came back with
  both keys empty -- but none was arranged as a bounded series, and a `noEnd` recurrence
  legitimately has neither key. One of the six is `OneTime`, which has no recurrence range at all.
  To settle it, create one review limited to N occurrences and one with an end date, then re-run.
  If they still export empty, dump `$Def.Settings.recurrence.range` -- a `type` of `endDate` or
  `numbered` with the values present would prove the projection is dropping them.
  **Re-run 2026-08-24: PASS**, reported by Philip. Aggregate confirmation, no per-item output
  captured.

- [x] **5.4 Is `defaultDecision: "None"` accepted on write?** Learn's enum says
  Approve / Deny / Recommendation; Learn's own update example sends `None`, and this module's schema
  allows it.

  ```powershell
  Invoke-LiveCheck '{ "accessReviews": [ { "displayName": "<review-name>",
    "accessPackage": "oer-live-ap", "assignmentPolicy": "<policy-1>", "defaultDecision": "None" } ] }'
  ```

  **Expect one of:** accepted, or a Graph rejection naming the enum. Write down which.
  **Result:** FAIL -- and worse than the question asked. `"None"` is accepted, but that proves
  nothing, because `None` was already the live value. Applying `"defaultDecision": "Approve"`
  reported `Updated updated access review 'AccessRevuew Test' (defaultDecision=Approve)` while
  the definition read back immediately afterwards still showed `DefaultDecision : None` and
  `DefaultDecisionEnabled : False`. That is a false success AND a non-convergence -- the same
  document reports `Updated` on every run, forever. The review carried `Status : Completed`,
  which may be the whole cause. Being fixed; see the follow-ups section.

- [x] **5.5 Does `absoluteMonthly` accept `interval: 6`?** Create a semi-annual review in the portal
  (the PIM review UI offers "Semi-annually").

  ```powershell
  Get-OERAccessReviewDefinition -DisplayName '<semi-annual-review>' | Select-Object DisplayName, Recurrence
  ```

  **Expect:** it exists, and `Recurrence` collapses it to something that is NOT semi-annual -- that
  collapse is exactly what 5.6 tests.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.6 And an unrepresentable interval is NOT rewritten.**

  ```powershell
  $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter '<semi-annual-review>'
  $Inv.accessReviews | Select-Object displayName, recurrence, startDate

  # change ONLY the start date, then apply
  $Inv.accessReviews[0].startDate = '2026-10-01'
  $Inv | Invoke-OERStructure

  Get-OERAccessReviewDefinition -DisplayName '<semi-annual-review>' | Select-Object DisplayName, Recurrence
  ```

  **Expect:** a warning plus a `Skipped` record naming "interval 6", and the live pattern still
  semi-annual in the portal.
  **Failure looks like:** `Updated`, and the portal now shows a monthly review -- silent corruption,
  the pre-fix behaviour.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.7 A multi-stage review is skipped, not fabricated.** Create a two-stage review on the
  package.

  ```powershell
  $Inv = Get-OERInventory -Include AccessReviews -WarningVariable W
  $W
  $Inv.accessReviews | Select-Object displayName, reviewers
  ```

  **Expect:** a warning naming the review and its stage count, and NO entry for it in
  `accessReviews[]`.
  **Failure looks like:** an entry with `reviewers: ["self"]` -- a self review that was never
  configured.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.8 Does a bare GET return `stageSettings`?**

  ```powershell
  $Def = Get-OERAccessReviewDefinition -DisplayName '<two-stage-review>'
  $Def | Select-Object DisplayName, StageCount
  $Def.StageSettings | Format-List StageId, DependsOn, DurationInDays, DecisionsThatMoveToNextStage
  ```

  **Expect:** the stages, with their ids and dependencies.
  **Failure looks like:** an empty collection while `StageCount` is 2 -- meaning Graph does not return
  `stageSettings` by default and there is no documented `$expand` for that path. Either answer is a
  real result; write it down.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.9 Stage reviewers are readable.**

  ```powershell
  Get-OERAccessReviewInstance -Definition '<two-stage-review>' -IncludeStages |
      Select-Object -ExpandProperty Stages |
      Format-List Id, Status, StartDateTime, EndDateTime, Reviewers, FallbackReviewers
  ```

  **Expect:** each stage carries `Reviewers` and `FallbackReviewers`.
  **Failure looks like:** both empty on a stage the portal shows reviewers for.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **5.10 Non-access-package reviews are announced.** Needs at least one group or directory-role
  review in the tenant.

  ```powershell
  $Inv = Get-OERInventory -Include AccessReviews -WarningVariable W
  $W | Where-Object { $_ -match 'skipp' }
  ```

  **Expect:** one warning naming how many were skipped and why.
  **Failure looks like:** silence, and an `accessReviews[]` the operator reads as complete.
  **Result:** PASS. `Get-OERInventory: skipped 1 access review definition(s) that are not
  access-package-scoped. Only access-package reviews round-trip through Invoke-OERStructure;
  group, application and directory-role reviews are not captured.` -- on the warning stream, at
  default verbosity, naming the count and the reason.

- [x] **5.11 The full loop still closes.**

  ```powershell
  # -OutputPath is the PARENT; the bundle lands in a timestamped subfolder underneath it.
  $Bundle = Export-OERInventory -OutputPath ./live/export -Force
  Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json')
  Invoke-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json') -WhatIf
  ```

  **Expect:** `Valid` is true with no Errors, and a plan of all `Unchanged`.
  **Failure looks like:** validation findings caused by a key this PR added, or drift the engine wants
  to write against state it just captured.
  **Result:** FAIL, and it found a real export defect. `Export-OERInventory` warned
  `inventory.json did not pass apply-schema validation ... First issue: 'durationInDays' at
  accessReviews[0] must be an integer between 1 and 365`, and `Test-OERStructure` on the written
  bundle confirmed `Valid : False` with that one Error plus five `fallbackReviewers` Warnings on
  accessReviews[0..4]. The export writes a document its own shipped schema rejects -- the same
  class PR #43 fixed once already. Being fixed; see the follow-ups section.

- [x] **5.12 Idempotency.**

  ```powershell
  Invoke-OERStructure -Path ./live/export/inventory.json
  Invoke-OERStructure -Path ./live/export/inventory.json
  ```

  **Expect:** the second run is entirely `Unchanged`.
  **Failure looks like:** any `Updated` on the second run -- a non-converging field.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

### 6. Questions the 2026-08-23 fix round raised

The first live pass through sections 3-5 found five defects. Fixing them raised these. **6.1 to 6.4
are regression risks introduced by the fixes themselves and should be run first** -- the rest are open
questions where Microsoft Learn is silent.

#### Regression risks from the fixes

- [x] **6.1 A recurring review with future instances still reports `Updated`.** This is the sharpest
  regression risk in the round. `Sync-OERStructureAccessReview` now verifies every update by re-running
  the diff against the definition `Set-OERAccessReviewDefinition` reads back, and reports `Failed`
  when the declared state is not there. If Graph queues a settings change without reflecting it at the
  definition level immediately, a legitimately-applied change will now be reported `Failed`.

  ```powershell
  # a RECURRING review with instances still to come
  Invoke-LiveCheck '{ "accessReviews": [ { "displayName": "<recurring-review>",
    "accessPackage": "oer-live-ap", "assignmentPolicy": "<policy-1>", "requireJustification": true } ] }'
  Get-OERAccessReviewDefinition -DisplayName '<recurring-review>' |
      Select-Object DisplayName, Status, JustificationRequired
  ```

  **Expect:** `Updated`, and `JustificationRequired` true on the read-back.
  **Failure looks like:** `Failed` with "accepted the write but the definition read back still
  differs" while the portal shows the change did land -- then the verification needs a short retry, or
  it must distinguish queued from discarded.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.2 Read-after-write consistency of the verification re-GET.** Same mechanism, different
  cause: a genuinely successful PUT could read back stale within the same second. Run 6.1 three or
  four times in a row on different fields. **Expect:** no intermittent `Failed`. **Failure looks
  like:** it passes sometimes and fails sometimes -- eventual consistency, and the fix needs a retry.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.3 `$filter=catalog/id eq` together with `$expand=catalog`.** The live evidence for 3.2b
  covered `?$expand=catalog` alone. `Get-OERAccessPackage -Catalog` now sends both at once, and that
  is the read `Sync-OERStructureAccessPackage` depends on.

  ```powershell
  $InB = @(Get-OERAccessPackage -Catalog OER-CAT-B)
  $InB | Select-Object DisplayName, Id, CatalogId
  ```

  **Expect:** the same narrowing as 3.2, and `CatalogId` now POPULATED on every row.
  **Failure looks like:** a Graph error naming the query, or `CatalogId` still empty -- the pairing is
  not supported and `-Catalog` must expand separately.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.4 `-IncludeResourceRoles` after the spelling fix.** It sent
  `$expand=accessPackageResourceRoleScopes`, which is the **beta** spelling; v1.0 names the
  relationship `resourceRoleScopes`. The old spelling almost certainly 400'd the whole request, so the
  switch may never have worked at all -- and it had no test, which is why it survived. Fixed to match
  `Get-OERAccessPackageResourceRole`, which already used the v1.0 name against the same URI.

  **Read this before running it:** `ConvertTo-OERAccessPackage` emits a fixed five-property shape
  (`Id`, `DisplayName`, `Description`, `CatalogId`, `IsHidden`) and **discards both expanded
  collections**, so neither `-IncludeResourceRoles` nor `-IncludePolicies` surfaces anything to the
  caller. The only thing this check can observe through the cmdlet is that the request no longer
  fails. Use `Get-OERAccessPackageResourceRole` when you actually want the data.

  ```powershell
  # 1. through the cmdlet: the observable is the ABSENCE of an error
  Get-OERAccessPackage -Catalog OER-CAT-A -IncludeResourceRoles |
      Where-Object DisplayName -eq 'oer-live-ap'

  # 2. raw, to see what the expand actually returns
  $Raw = & (Get-Module Omnicit.EntraRBAC) {
      Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/entitlementManagement/accessPackages?$expand=catalog,resourceRoleScopes' -All
  }
  @($Raw.value)[0].resourceRoleScopes
  ```

  **Expect:** step 1 returns the package with no error; step 2 returns the role scopes.
  **Failure looks like:** a 400 naming the expand -- then the relationship name is wrong in a second
  way, or the two expands cannot be combined.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

#### Access review write path -- Learn is silent

- [x] **6.5 Does a PUT to a `Completed` definition EVER store a settings change?** This is the root
  question behind 5.4. Learn says a definition update "only applies to future instances" and that
  running instances cannot be updated, but never states that a terminal-status definition silently
  discards the write -- which is why the fix verifies rather than encoding a status rule.
  Set `defaultDecision=Approve` on a Completed one-time review, GET it back.
  **Expect one of:** stored (then 5.4 had a different cause -- see 6.9), or unchanged (then the
  verification is doing exactly its job). **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.6 Which other statuses discard a settings change?** Repeat 6.5 for `AutoReviewed`,
  `Completing`, `AutoReviewing`, and the ARM-only `Applied` / `Applying` if you can produce them.
  Learn's status list is prefixed "typical states include", so it is not a closed set.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.7 Is `defaultDecision: "None"` accepted as a WRITE?** The resource table lists only
  `Approve` / `Deny` / `Recommendation`, yet Learn's own update example body sends `"None"` with
  `defaultDecisionEnabled: false`. Check 5.4 could not answer this because `None` was already the live
  value. Set a review to `Approve` first, then apply `"defaultDecision": "None"`.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.8 Top-level `reviewers` on a group-reviewer or multi-stage review.** Learn restricts reviewer
  updates to reviews where individual users are assigned, and says only `stageSettings` reviewers are
  updatable on a multi-stage review -- but the engine always writes the top-level arrays regardless of
  `StageCount`. That is a second, Learn-DOCUMENTED false-success shape, distinct from 5.4.
  **Expect one of:** a Graph error (good -- it surfaces), or silent acceptance with no effect (bad --
  the same false-success class, now visible only because the verification catches it).
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.9 Does the PUT need `id` in the body?** The module omits it; Learn's example includes it.
  Only worth chasing if 6.5 comes back "Completed reviews DO accept updates", in which case this is the
  next candidate cause for 5.4. **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

#### Access review read path -- Learn is silent

- [x] **6.10 The decisive dump for 5.3.** Microsoft's own list-definitions example reports an
  UNBOUNDED quarterly review as `type: "numbered", numberOfOccurrences: 0, endDate: "9999-12-31"` --
  Graph does not use `noEnd` for a never-ending portal series. If that is what your tenant holds, the
  empty `endDate`/`occurrences` you saw is CORRECT and 5.3 closes as a non-defect.

  ```powershell
  Get-OERAccessReviewDefinition -All | Where-Object { $_.Recurrence.pattern } | ForEach-Object {
      [PSCustomObject]@{ Name = $_.DisplayName; Type = $_.Recurrence.range.type
                         Occ = $_.Recurrence.range.numberOfOccurrences; End = $_.Recurrence.range.endDate } }
  ```

  **Expect (non-defect):** `type=numbered, Occ=0, End=9999-12-31`, or `type=noEnd`.
  **Failure looks like:** `type=endDate` with a real date, or `type=numbered` with `Occ >= 1`, while
  the export still emits neither key -- that is a projection bug; reopen 5.3.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.11 The `interval 0` hazard on a OneTime review.**

  ```powershell
  (Get-OERAccessReviewDefinition -DisplayName 'AccessRevuew Test').Recurrence.pattern | Format-List *
  ```

  **Expect:** empty or absent -- the OneTime classification is right.
  **Failure looks like:** `type=weekly` or `absoluteMonthly` with `interval=0` -- the projection would
  then export a one-time review as `Weekly`/`Monthly`, always preceded by the "cannot represent"
  warning. File as a follow-up if seen.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.12 Confirm the five `fallbackReviewers` warnings describe real tenant state.**

  ```powershell
  Get-OERAccessReviewDefinition -All | Select-Object DisplayName,
      @{n='Rev'; e={ ($_.Reviewers.query) -join ',' }},
      @{n='Fb';  e={ ($_.FallbackReviewers.query) -join ',' }}
  ```

  **Expect:** `Rev = ./manager` and `Fb` empty on the five -- the warning is describing true state and
  there is no read gap.
  **Failure looks like:** `Fb` non-empty on any of them -- then it IS a read gap; reopen.
  **Result:** PASS -- Philip, 2026-08-24 run through 6.12. Aggregate confirmation; no per-item output was captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **6.13 Does the new reviewer-drop warning fire?** `Get-OERInventory` now warns when live reviewer
  scopes project to nothing, instead of silently emitting `reviewers: []` -- which the schema reads as
  a self review that was never configured. Re-run `Export-OERInventory`.
  **Expect:** no such warning, if every reviewer uses one of the three forms the module models
  (`/users/{id}`, `/groups/{id}/...`, `./manager`).
  **Failure looks like:** the warning fires and names a query form -- then that form must be added to
  the projection, and the empty `reviewers` arrays in your last export were fabricated.
  **Result:** FAIL -- and the failure was the point. The warning fired on four reviews, each
  naming `/v1.0/users/{id}`. **The stated Expect above was wrong**: it predicted silence. The cause
  is not an exotic reviewer form -- Microsoft Graph NORMALIZES a reviewer scope query on read. This
  module writes `/users/{id}` with no prefix; a GET returns `/v1.0/users/{id}`, and the anchored
  `^/users/([^/]+)$` parse matched none of them. `OER-DIAG-A-v1scope-userReviewer` and
  `OER-DIAG-B-betascope-userReviewer` BOTH read back prefixed, so this is not a v1.0-vs-beta split.
  Not just an export cosmetic: `Resolve-OERAccessReviewChange` ran the same parse on the live side
  of the apply diff and concluded `CurrentSelfReview = $true`, so the engine believed a review with
  a real named reviewer was a SELF review and would have written that back. Fixed -- both legs now
  route through the private `Resolve-OERReviewerScopeQuery`, which tolerates a `/v1.0` or `/beta`
  prefix and keeps `Unparsed` strictly distinct from "no reviewer scopes at all". Section 7
  confirms the fix.

- [x] **6.14 Does Graph really reject a manager reviewer with no fallback on CREATE?** The schema
  validator warns that it does, and the code comment quotes a real error (`Policy is invalid due to
  invalid criteria`) -- so the claim has empirical backing. But five such reviews EXIST in your tenant,
  which is evidence the other way, and Learn documents `fallbackReviewers` as optional except for
  reviews of PIM-for-groups-governed groups. The wording was deliberately left alone rather than
  softened on indirect evidence.
  Run `New-OERAccessReviewDefinition` with a manager reviewer and NO fallback in a scratch tenant.
  **Expect one of:** rejected (the warning is right as written), or accepted (the warning overstates
  and should name the PIM-for-groups case specifically).
  **Result:** VERIFIED by Philip, 2026-08-24, as an aggregate confirmation. This item asked
  WHICH of two behaviours Graph shows, and that answer was not captured, so the schema
  validator's claim that Graph rejects such a review stands as written -- neither confirmed
  nor softened. Read alongside 6.12, which established that the five warned-about reviews
  genuinely have a manager reviewer and no fallback and exist in the tenant regardless.

- [x] **6.15 Is `instanceDurationInDays` zero on a single GET too, or only on the list?** The inventory
  now omits `durationInDays` when the live value is outside 1-365, because Graph documents `0` as a
  real value meaning "this field does not drive the duration". If a single-definition GET returns a
  real duration where the list returns `0`, the inventory could re-fetch per definition for higher
  fidelity -- at one extra call each on a heavily throttled endpoint.

  ```powershell
  (Get-OERAccessReviewDefinition -Id '<id>').Settings.instanceDurationInDays
  ```

  **Result:** VERIFIED by Philip, 2026-08-24, as an aggregate confirmation. This item asked
  WHICH of two behaviours the tenant shows -- whether a single GET returns a real duration
  where the list returns 0 -- and that answer was not captured. The fidelity improvement it
  would have justified (re-fetching per definition) therefore stays unopened.

- [x] **6.16 The `9999-12-31` end-date sentinel.** If any review reports `range.type = 'endDate'` with
  `endDate = '9999-12-31'`, the export emits it verbatim. That is schema-valid and round-trip-faithful,
  but confirm you want it rather than treating the sentinel as "no end".
  **Result:** VERIFIED by Philip, 2026-08-24, as an aggregate confirmation. This item asked
  WHICH of two behaviours the tenant shows, and that specific answer was not captured, so the
  follow-up it might have triggered cannot be opened from this record.

---

## 7. Reviewer scope query parsing (added after the 2026-08-24 live export)

Check 6.13 above predicted "no such warning, if every reviewer uses one of the three forms the module
models". It fired anyway, on four reviews, naming `/v1.0/users/00000000-0000-0000-0000-000000000006`. The cause was not an
exotic reviewer form: Microsoft Graph NORMALIZES a reviewer scope query on read. This module writes
`/users/{id}` with no prefix (`Resolve-OERReviewerScope`), and a GET returns `/v1.0/users/{id}`.
Both `OER-DIAG-A-v1scope-userReviewer` and `OER-DIAG-B-betascope-userReviewer` read back with the
`/v1.0` prefix, so this is not a v1.0-vs-beta split. The anchored `'^/users/([^/]+)$'` parse -- which
existed in ten places -- matched none of them.

That was never only an export cosmetic. `Resolve-OERAccessReviewChange` ran the same parse on the
LIVE side of the apply diff, and when nothing parsed it concluded `CurrentSelfReview = $true`. So the
apply engine believed a review with a real named user reviewer was a SELF review, and would have
written that back. Both legs now route through the single private helper
`Resolve-OERReviewerScopeQuery`, which tolerates a `/v1.0` or `/beta` prefix and reports anything
else as `Unparsed` -- a state kept strictly distinct from "no reviewer scopes at all".

- [x] **7.1 Does the prefixed form now project correctly?** Re-run `Export-OERInventory` over the same
  tenant slice that produced the four warnings.
  **Expect:** no `cannot express` warning for the four reviews, and each one's `reviewers` array names
  the real reviewer (a UPN or group name), not an empty list. Check
  `OER-DIAG-A-v1scope-userReviewer` and `OER-DIAG-B-betascope-userReviewer` explicitly.
  **Failure looks like:** the warning still fires -- then read the query string it names. If it carries
  a prefix this fix did not anticipate, the tolerated vocabulary in `Resolve-OERReviewerScopeQuery`
  needs widening; if it is a genuinely different form (`./owners`, an owners filter), that is check 7.3.
  **Result:** PASS -- Philip, 2026-08-24. Aggregate confirmation; no per-item output was
  captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **7.2 Does the apply engine now leave those reviews alone?** Take the export from 7.1, apply it
  back with `Invoke-OERStructure -WhatIf` against the same tenant.
  **Expect:** `Unchanged` for the four reviews. In particular the plan must NOT show a reviewer change,
  and must never show `SelfReview` being set on a review that has a named reviewer.
  **Failure looks like:** a planned reviewer write. Capture the plan text -- a forced write here means
  the round trip still is not closed, and the pre-fix behaviour would have been a silent overwrite
  rather than a plan line.
  **Result:** PASS -- Philip, 2026-08-24. Aggregate confirmation; no per-item output was
  captured, so this line records that the check ran and behaved as expected, not what it printed.

- [x] **7.3 Are `reviewerId` and `scopeType` actually populated on a live read?** This is the check
  that decides whether the query-string parse should stay the PRIMARY source or become a fallback.
  Microsoft Learn documents both properties on the v1.0 `accessReviewReviewerScope` resource
  (`learn.microsoft.com/graph/api/resources/accessreviewreviewerscope?view=graph-rest-1.0`):
  `reviewerId` is "The identifier of the reviewer", and `scopeType` is an enum with values `user`,
  `group`, `self`, `manager`, `sponsor`, `resourceOwner`, `managerOrSponsor`, `unknownFutureValue`.
  Being documented is not evidence that a real tenant returns them populated -- this fix was
  deliberately NOT built on them for exactly that reason.

  Run this against a review with a NAMED user reviewer, one with a GROUP reviewer, one with a MANAGER
  reviewer, and one genuine SELF review (empty `reviewers`), and record all four:

  ```powershell
  # Raw, unconverted, so nothing the module's own projection does can mask a missing property.
  $Def = Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/accessReviews/definitions/<definition-id>'
  $Def.reviewers         | ConvertTo-Json -Depth 5
  $Def.fallbackReviewers | ConvertTo-Json -Depth 5
  ```

  `Invoke-OERGraphRequest` is private, so run it as
  `& (Get-Module Omnicit.EntraRBAC) { Invoke-OERGraphRequest -Uri '...' }`, or use
  `(Get-OERAccessReviewDefinition -Id '<id>').Reviewers | ConvertTo-Json -Depth 5`, which surfaces the
  raw scope objects unmodified.
  **Expect one of:**
  - Both keys present and populated on every scope -- then open a follow-up to make `scopeType` +
    `reviewerId` the primary source and demote the query-string parse to a fallback. Record which
    `scopeType` value each of the four cases returned; `self` on the empty-reviewers case would be
    especially useful, since that is the one shape the module currently infers from absence alone.
  - The keys absent, empty, or present on some scopes and not others -- then the query-string parse
    must stay primary, and this check should be pasted into the follow-up issue as the reason.
  **Result:** ANSWERED -- NEITHER KEY IS RETURNED. `$Defs.Reviewers | ForEach-Object { $_.scopeType }`
  and the same for `reviewerId` both produced NOTHING across all eight definitions. Every scope
  object carried exactly three properties -- `query`, `queryRoot`, `queryType`. Confirmed on a
  manager scope (`query ./manager`, `queryRoot decisions`), on named user scopes
  (`query /v1.0/users/00000000-0000-0000-0000-000000000006`, `queryRoot` empty), and on a fallback scope
  (`/v1.0/users/00000000-0000-0000-0000-000000000007`). So Learn documents both properties on the v1.0 resource and a
  real tenant returns neither.

  **This validates the fix as built.** The query-string parse STAYS the primary source; there is
  nothing to demote it to a fallback in favour of, and had the fix been built on `reviewerId` it
  would have read `$null` on every scope in this tenant. It is also why `self` must keep being
  inferred from an empty `reviewers` collection rather than read from a `scopeType`.

- [x] **7.4 Do any live reviews use a `scopeType` this module has no vocabulary for?** `sponsor`,
  `resourceOwner` and `managerOrSponsor` are documented enum values that the apply document cannot
  express at all -- there is no token for them in `reviewers[]`, and `Sync-OERStructureAccessReview`
  maps only `manager`, `self`, a UPN and a group name. A review using one of them exports with that
  reviewer dropped and now raises the `cannot express` warning rather than being silently lost.
  Separately, `accessReviewScheduleDefinition` carries a third reviewer collection, `backupReviewers`,
  which this module neither reads nor writes.
  **Expect:** no review in the tenant uses one of those three scope types, and none carries
  `backupReviewers`.
  **Failure looks like:** one does -- then record the review name and the exact scope JSON. That is a
  vocabulary gap to file, not a parsing bug, and it decides whether the apply engine should refuse
  such a review outright instead of exporting it minus a reviewer.
  **Result:** CANNOT BE VERIFIED FROM THIS READ, and therefore we do not know. The question
  presupposes `scopeType` is returned; per 7.3 it is not, so a review using `sponsor`,
  `resourceOwner` or `managerOrSponsor` is indistinguishable here from any other named scope --
  it would simply arrive as some `query` string. What CAN be said: across the eight definitions
  in the tenant, every scope carried exactly `query`, `queryRoot`, `queryType`, and every `query`
  was either `./manager` or `/v1.0/users/{id}` -- both forms the module now parses. No unparsed
  scope remained, so nothing in this tenant is currently being dropped. `backupReviewers` was not
  observed on any definition. The general question stays open and needs a tenant that actually
  uses one of the three scope types.

---
