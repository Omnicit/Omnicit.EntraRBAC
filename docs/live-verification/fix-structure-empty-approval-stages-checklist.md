# Live verification checklist -- fix/structure-empty-approval-stages (issue #56)

**SUPERSEDED.** This checklist's 45 checks were never run in the sprints since it merged. The
still-relevant ones have been carried forward, re-verified against current source, into
`docs/live-verification/fix-declared-value-family-and-au-prune-checklist.md`, which also covers
issues #67, #68, #69, #70 and #59 against the SAME shared tenant setup (one access package, one
assignment policy, approval stages, access reviews, an administrative unit) rather than building it
twice. Run that file instead. This file is kept, unchanged below, because it carries the authoring
pattern the new one continues.

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

## What changed and why this needs a live tenant

An `Invoke-OERStructure` document declaring `"approvalStages": []` against an access package
assignment policy that HAS live approval stages never converged. `Sync-OERStructureAccessPackage`
gated the `-ApprovalStage` splat on the stage COUNT instead of on whether the document DECLARED the
key, so a declared-empty array was indistinguishable from an omitted one. Since PR #52 that produced
a `Failed` record on every pass (the call reached `Set-OERAccessPackageAssignmentPolicy` carrying only
`-Id` and `-DisplayName`, which trips its `NothingToUpdate` guard); before PR #52 it produced
`Updated` on every pass while changing nothing. This branch:

- makes all three `-ApprovalStage` splat sites in `Sync-OERStructureAccessPackage` gate on
  `@($Parts.DeclaredFields) -contains 'approvalStages'` instead of on `@($Parts.Stages).Count -gt 0`.
  **Only the UPDATE splat is behaviour-changing.** `Set-OERAccessPackageAssignmentPolicy` GETs the
  live policy and hands it to `ConvertTo-OERPolicyBody` as `-Existing`, so an OMITTED `-ApprovalStage`
  carries the live stages forward; the diff-body and create splats call the same helper with no
  `-Existing`, where bound-empty and omitted already produced an identical body. They were corrected
  for uniformity, and the checklist below does not pretend otherwise;
- adds an offline `Test-OERStructure` **Warning** for a document declaring `requireApproval: true`
  together with `approvalStages: []`. It stays a Warning and never an Error: the document is still
  `Valid` and the apply still runs. What actually gets written is `isApprovalRequiredForAdd: true`
  with `stages: []`, because an explicitly bound `-RequireApproval` wins over the value
  `ConvertTo-OERPolicyBody` would otherwise derive from the stage count;
- adds the matching caveat to `Get-OERInventoryPromptTemplate`, so a generating LLM does not author
  the contradiction in the first place; and
- fixes the same declared-empty class on the access review CREATE path.
  `Sync-OERStructureAccessReview` built its `$HasReviewers` flag with a triple gate whose middle
  clause was a bare truthiness test, and `[bool]@()` is `$false` in PowerShell, so a declared
  `"reviewers": []` short-circuited into the manager-default branch -- destroying a signal that the
  handler's OWN help and its OWN update path define as a **self review**. Commit `36fdde7` corrected
  the offline validator, which classified `@($AR.reviewers).Count -eq 0` as "uses manager" and so
  demanded `fallbackReviewers` for exactly the document that is now a self review. Check 8.1 confirms
  that correction is loaded.

**Every test on this branch mocks `Invoke-OERGraphRequest`.** The mocked suite proves the module
SENDS the right body. It proves nothing whatsoever about what Microsoft Graph DOES with that body.
Everything below writes to, or reads from, a real tenant.

### The five questions only a tenant can answer

Where these are recorded, the check deliberately carries NO `Expect:` line for the Graph-side
outcome. Record what actually happened, verbatim. A checklist that predicts an unknown and is
believed is worse than one that admits it.

| # | The question | Recorded in |
|---|---|---|
| U1 | Does Graph accept a `PUT` of an assignment policy whose `requestApprovalSettings.stages` is `[]`? | 2.2 (update), 7.5 (create) |
| U2 | When it does, does it leave the REST of `requestApprovalSettings` alone, or reset the sibling flags? | 4.1 - 4.5 |
| U3 | Does Graph accept a `POST accessReviewScheduleDefinitions` with an empty `reviewers` collection and NO `fallbackReviewers`? | 8.2 |
| U4 | Does Graph accept `isApprovalRequiredForAdd: true` together with `stages: []`, or reject it? | 6.2 |
| U5 | Does Graph accept `-SelfReview` together with `-FallbackReviewer`? | 8.5 |

U1 - U4 come from this branch's own investigation. U5 is a follow-on question the mocked suite is
equally unable to answer: the module refuses `-SelfReview` combined with `-Manager`/`-Reviewer`/
`-ReviewerGroup` (`MutuallyExclusiveReviewer`) but forwards `-SelfReview` and `-FallbackReviewer`
together untouched.

**U2 is the highest-risk item on this branch.** Audit PR-5 (issue #29) established the class: an
undeclared half of a composite field, sent empty, wipes live state. `requestApprovalSettings` is
assembled as a UNIT in `ConvertTo-OERPolicyBody.ps1` -- `isApprovalRequiredForAdd`,
`isApprovalRequiredForUpdate`, `isRequestorJustificationRequired` and `stages` all go out together on
every PUT. The unit suite now pins that the module BUILDS the sibling flags correctly from
`-Existing` when the caller never mentions them. **Do not read that as the hazard being handled. It
is UNPROVEN until section 4 is filled in.**

---

## Setup, once

You need:

- **Two DISPOSABLE Entitlement Management access packages**, both in a catalog you own, neither used
  by anything real. Sections 2 - 7 repeatedly rewrite the first package's approval configuration and
  section 7 creates and then deletes a second assignment policy on it.

  1. `<your-test-access-package>` with one assignment policy `<your-test-policy>`, used by sections
     1 - 7 and 9.
  2. `<your-review-access-package>` with one assignment policy `<your-review-policy>`, used ONLY by
     section 8. It must have **no** Lifecycle access review configured, so the access review
     definitions section 8 creates are unambiguously its own. (The first package deliberately DOES
     have one -- check 4.4 needs it.)

- **`<your-test-policy>` configured with DISTINCTIVE, non-default values in every field the documents
  below never mention**, before you start. A reset to a default is only visible if the starting value
  was not the default. Open the Microsoft Entra admin center at **ID Governance > Entitlement
  management > Access packages > `<your-test-access-package>` > Policies > `<your-test-policy>` >
  Edit** and set:

  | Portal tab | Setting | Set it to |
  |---|---|---|
  | Requests | Users who can request access | a SPECIFIC set of users or groups, not "All members" |
  | Requests > Approval | If requestors must be approved | Yes, with ONE approval stage naming `<approver-upn>` as approver and a decision deadline of 14 days |
  | Requests > Approval | Require requestor's justification | Yes |
  | Requestor information | Questions | at least ONE custom question |
  | Lifecycle | Access package assignments expire | Number of days, a specific value (not Never) |
  | Lifecycle | Require approval to grant extension | Yes |
  | Lifecycle | Require access review | Yes, with a review configured |

- **`<approver-upn>`** -- a user who can be named as an approval-stage approver.
- **`<fallback-upn>`** -- a user who can be named as an access review fallback reviewer, for section 8.
- **Identity Governance Administrator** in the tenant (catalog owner plus access package manager also
  works for most of this).
- **The module built from THIS branch.** Check 1.2 is the offline tell that confirms it.
- A scratch folder for the JSON documents. The commands below use `./live`.

Set these once and reuse them in every command block below:

```powershell
$Alias     = '<your-tenant-alias>'
$Catalog   = '<your-test-catalog>'
$Package   = '<your-test-access-package>'
$Policy    = '<your-test-policy>'
$NewPolicy = '<your-new-policy>'
$Approver  = '<approver-upn>'
$RvPackage = '<your-review-access-package>'
$RvPolicy  = '<your-review-policy>'
$Review1   = '<your-test-review>'
$Review2   = '<your-second-test-review>'
$Fallback  = '<fallback-upn>'

Import-Module ./output/module/Omnicit.EntraRBAC/2.0.0/Omnicit.EntraRBAC.psd1 -Force
Connect-OER -TenantAlias $Alias
New-Item -ItemType Directory -Path './live' -Force | Out-Null

$Pkg = Get-OERAccessPackage -Catalog $Catalog | Where-Object DisplayName -eq $Package
$Pol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $Policy

# Every property the module surfaces on an assignment policy. Note what is NOT here:
# reviewSettings and questions. The module's read projection does not model them at all, which is
# exactly why checks 4.4 and 4.5 go to the portal instead.
$AllFields = @(
    'Id', 'DisplayName', 'AccessPackageId', 'AllowedTargetScope', 'Description', 'RequestorScope',
    'RequestorSettings', 'RequireApproval', 'RequireRequestorJustification', 'RequireApprovalForUpdate',
    'ApprovalStages', 'DurationInDays', 'DurationInHours', 'ExpirationDateTime', 'NotificationsDisabled')

# The subset that section 2's document never declares. Section 4 proves every one of these survived
# the PUT that cleared the stages. RequireApproval is deliberately EXCLUDED: with -ApprovalStage
# bound and -RequireApproval unbound, ConvertTo-OERPolicyBody derives isApprovalRequiredForAdd from
# the stage count, so it is EXPECTED to flip to false. That is check 3.1, not a sibling regression.
$SiblingFields = @(
    'Description', 'AllowedTargetScope', 'RequestorScope', 'RequestorSettings',
    'RequireRequestorJustification', 'RequireApprovalForUpdate',
    'DurationInDays', 'DurationInHours', 'ExpirationDateTime', 'NotificationsDisabled')
```

| Placeholder | What it is |
|---|---|
| `<your-tenant-alias>` | The `Get-OERConfiguration` alias for the test tenant. |
| `<your-test-catalog>` | The catalog display name holding both disposable access packages. |
| `<your-test-access-package>` / `<your-test-policy>` | The disposable package and its existing assignment policy, from Setup. Sections 1 - 7 and 9. |
| `<your-new-policy>` | A policy display name that does NOT exist yet on `<your-test-access-package>`. Section 7 creates it and section 9 deletes it. |
| `<approver-upn>` | The user named as the approval-stage approver in Setup. Every document below that rebuilds a stage names this user. |
| `<your-review-access-package>` / `<your-review-policy>` | The SECOND disposable package and its policy, with no Lifecycle access review. Section 8 only. |
| `<your-test-review>` / `<your-second-test-review>` | Two access review display names that do NOT exist yet. Section 8 creates them and section 9 deletes them. |
| `<fallback-upn>` | The user named as the access review fallback reviewer in check 8.5. |

**Every JSON document below carries `"tenantAlias": "<your-tenant-alias>"`.** Substitute your own
alias when you save the file; the engine reads it to resolve Tenant Profile approver defaults.

**Every accessPackages document below validates with one expected Warning:**
`accessPackages[0].catalog :: Catalog '<your-test-catalog>' is not declared in this document. It may
already exist in the tenant.` That is correct and harmless -- the documents deliberately do not
declare the catalog, because creating one is not what this branch changed. Only ADDITIONAL findings
are interesting.

**Every accessPackages document below carries `"resourceRoles": null`** -- an explicit null, which is
how a package is declared without touching its resource role bindings at all. An OMITTED
`resourceRoles` key still runs the reconcile pass and would report every live binding as `Extra`.
Nothing is ever deleted either way, but the null keeps the output readable.

**Run sections 1 - 7 in order.** Each one depends on the live state the previous one left behind: the
policy is deliberately walked through the whole sequence (baseline with stages, stages cleared,
composite field inspected, stages restored via an omitted key, contradiction applied, plan-only and
create paths). **Section 8 is independent** -- it uses the second access package and can run any time
after Setup. **Section 9 runs last** and restores the tenant.

---

### 1. Preparation and baseline capture

- [ ] **1.1 Resolve the package and the policy.**

  ```powershell
  $Pkg | Select-Object Id, DisplayName, CatalogId
  $Pol | Select-Object Id, DisplayName
  ```

  **Expect:** exactly one row each. `$Pkg.Id` and `$Pol.Id` are GUIDs.
  **Failure looks like:** more than one row from `$Pkg` -- the package display name is reused inside
  the catalog, which cannot happen; or an empty `$Pol` -- the policy display name in `$Policy` does
  not match the live policy exactly (the filter is case-insensitive but not fuzzy). Fix the variables
  before going further; every later check reads `$Pol.Id`.
  **Result:**

- [ ] **1.2 Confirm the session is running THIS branch's build.**

  The new offline Warning is the cheapest tell, and it costs no tenant call.

  ```powershell
  $Probe = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requireApproval":true,"approvalStages":[]}]}]}'
  $Probe.Valid
  $Probe.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `$Probe.Valid` is `$true`, and TWO Warning findings: the expected
  `accessPackages[0].catalog` one, plus one at Path `accessPackages[0].assignmentPolicies[0].approvalStages`
  whose Message begins `'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while
  'approvalStages' is declared as an empty array`.
  **Failure looks like:** only the catalog Warning. The loaded module predates commit `4754f3c` --
  rebuild and re-import before running anything else, or every result below describes the wrong code.
  **Result:**

- [ ] **1.3 Capture the FULL baseline policy to disk, before anything is written.**

  Write it to a file, not just a variable: sections 4 and 9 both read it back, and a crashed console
  would otherwise take the only copy of the pre-state with it.

  ```powershell
  $Before = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $Before | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-before.json' -Encoding utf8
  Get-Content ./live/policy-before.json
  ```

  **Expect:** the file is written and prints a complete policy. Note that the default table view for
  an `Omnicit.EntraRBAC.AssignmentPolicy` shows only four columns, which is why every read in this
  checklist goes through `Select-Object` or `Format-List` explicitly.
  **Result:**

- [ ] **1.4 Confirm the baseline actually HAS approval stages, and record the identifiers.**

  This is a precondition, not a check of the fix. Nothing after this proves anything if the starting
  policy had no stages to clear.

  ```powershell
  @($Before.ApprovalStages).Count
  $Before.ApprovalStages | Format-List *
  $Before | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate,
      AllowedTargetScope, Description, DurationInDays, DurationInHours, ExpirationDateTime, NotificationsDisabled
  $Before.RequestorScope | Format-List *
  $Before.RequestorSettings | Format-List *
  ```

  **Expect:** `@($Before.ApprovalStages).Count` is at least `1`; `RequireApproval` is `$true`;
  `RequireRequestorJustification` and `RequireApprovalForUpdate` are `$true`; `AllowedTargetScope` is
  NOT `allMemberUsers`; a duration is set. If any of those is at its default, go back to Setup and
  make it distinctive -- section 4 cannot detect a reset to a value that was already there.

  **Access package id:** ______________________________
  **Assignment policy id:** ______________________________
  **Original policy `Description` (section 9 restores it):** ______________________________
  **Stage count / approver / decision deadline days:** ______________________________
  **Result:**

- [ ] **1.5 Record the two fields the module cannot see at all.**

  `reviewSettings` and `questions` are carry-forward-only collections. `ConvertTo-OERPolicyBody`
  preserves them verbatim from `-Existing`, and `ConvertTo-OERAssignmentPolicy` does not project them
  at all, so no `Get-OER*` cmdlet in this module will ever show you whether they survived. The only
  reading available is the portal. Record their present state now so checks 4.4 and 4.5 have
  something to compare against.

  Open **ID Governance > Entitlement management > Access packages > `<your-test-access-package>` >
  Policies > `<your-test-policy>` > Edit** and note:

  **Requestor information tab -- questions (text of each, and required/optional):**
  ______________________________
  **Lifecycle tab -- "Require access review" setting and its full configuration:**
  ______________________________
  **Result:**

---

### 2. The convergence proof -- a declared-empty `approvalStages` clears the stages and settles

This section is the headline. It depends on section 1's baseline being in force.

- [ ] **2.1 Save the clear-stages document and validate it offline.**

  Save as `./live/ap-clear-stages.json`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>",
            "approvalStages": []
          }
        ]
      }
    ]
  }
  ```

  Note what this document does NOT declare: `requestorScope`, `requestorSettings`, `description`,
  `requireApproval`, `requireRequestorJustification`, `requireApprovalForUpdate`, any expiration key,
  and `notificationsDisabled`. That is deliberate -- section 4 is about exactly those.

  ```powershell
  $V = Test-OERStructure -Path './live/ap-clear-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `$V.Valid` is `$true` and the ONLY finding is the expected `accessPackages[0].catalog`
  Warning. The contradiction Warning must NOT fire here: this document does not declare
  `requireApproval`.
  **Failure looks like:** the contradiction Warning appearing on a document that never mentions
  `requireApproval` -- the new schema check is keying off the wrong condition.
  **Result:**

- [ ] **2.2 First apply -- the headline write. RECORDS U1.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect (module side, CONDITIONAL on U1 below):** the record for `accessPackages` /
  `<your-test-access-package>` will read `Updated`, with Detail
  `updated assignmentPolicy '<your-test-policy>' (approvalStages)`, **IF Graph accepts the empty
  stages array**; if Graph rejects it, the same record reads `Failed` instead. Record which. Either
  way the package's own record is `Unchanged` with Detail `access package properties match`, and any
  additional `Extra` records naming other live assignment policies on the same package are
  informational -- the engine never removes assignment policies.

  **Unknown (Graph side) -- U1.** Nobody has yet observed Microsoft Graph accepting a `PUT` of an
  assignment policy whose `requestApprovalSettings.stages` is an empty array. `Updated` here means
  `Set-OERAccessPackageAssignmentPolicy` returned without throwing, which is the first direct
  evidence either way. **Record the Action and the full Detail text verbatim, whichever it is.**

  **If Graph refuses the empty stages array** you will see `Failed` with Detail
  `failed to update assignmentPolicy '<your-test-policy>': <the Graph message>`. That is a finding to
  write up, not a defect in this checklist: it would mean a declared-empty `approvalStages` cannot be
  honoured at all and the branch needs a different answer (a clear refusal at validation time, rather
  than a write that fails in the tenant). Capture the Graph message in full.

  **Failure looks like:** `Failed` with Detail matching `NothingToUpdate` -- that is the PRE-fix
  symptom (the call reached `Set-OERAccessPackageAssignmentPolicy` with only `-Id` and `-DisplayName`)
  and means the loaded module does not carry commit `99e787b`. Re-run check 1.2.
  **Result:**

- [ ] **2.3 Second apply, byte-identical document -- the convergence proof.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged` with Detail `assignmentPolicy '<your-test-policy>' matches` -- NOT another
  `Updated`. This is the whole point of the branch. Run 1 clears the live stages; run 2 must see the
  cleared state as already matching.
  **Failure looks like:** `Updated` again. Two distinct bugs produce that, and they are told apart by
  what a third and fourth run do (run them):
  - `Updated` forever, with the live stages still present, means the write is not landing -- the
    declared-empty array is still being dropped somewhere between the splat and the wire;
  - `Updated` forever, with the live stages gone, means the DIFF is wrong -- the desired projection
    and the current projection disagree about what "no stages" looks like.

  Either way it is the original issue #56 non-convergence, unfixed.
  **Result:**

- [ ] **2.4 Third apply, to rule out an alternating pattern.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged` again. A document that alternates Updated / Unchanged / Updated is still
  non-convergent even though every second run looks correct.
  **Result:**

---

### 3. Read-back -- the stages are gone and the derived flag followed

- [ ] **3.1 Read the policy back through the module.**

  ```powershell
  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($After.ApprovalStages).Count
  $After | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate
  ```

  **Expect:** `@($After.ApprovalStages).Count` is `0`, and `RequireApproval` is `$false`. The second
  half is derived, not carried: `ConvertTo-OERPolicyBody` resolves `isApprovalRequiredForAdd` from the
  bound `-ApprovalStage` count whenever `-RequireApproval` is not explicitly bound.
  `RequireRequestorJustification` and `RequireApprovalForUpdate` must be UNCHANGED from check 1.4 --
  they are section 4's business and are called out here only so a difference is noticed early.
  **Failure looks like:** a non-zero stage count (the write did not land, and check 2.3's `Unchanged`
  was a false convergence built on a wrong diff), or `RequireApproval` still `$true` with zero stages
  (Graph stored the stages clear but kept approval required -- a dead policy nobody asked for; record
  it, it is the same shape U4 asks about).
  **Result:**

- [ ] **3.2 Confirm the same thing in the portal, not only through the module's own converter.**

  Every read above goes through `ConvertTo-OERAssignmentPolicy`, the same projection the apply-time
  diff uses. If that projection were wrong in a way that happened to match the write path, checks 2.3
  and 3.1 would both pass on a policy that is not what anyone asked for. The portal is the
  independent view.

  Open **ID Governance > Entitlement management > Access packages > `<your-test-access-package>` >
  Policies > `<your-test-policy>` > Edit > Requests** tab and read the **Approval** section.

  **Expect:** "If requestors must be approved" reads **No**, and no approver stage is listed. The
  approver you named in Setup is gone.
  **Failure looks like:** the approval stage still shown in the portal while `Get-OER...` reports zero
  stages -- the module is reading something Graph is not storing, and every other check in this
  checklist is suspect.
  **Result:**

---

### 4. The audit PR-5 composite-field hazard -- RECORDS U2

`requestApprovalSettings` is assembled as a UNIT in `ConvertTo-OERPolicyBody.ps1`:
`isApprovalRequiredForAdd`, `isApprovalRequiredForUpdate`, `isRequestorJustificationRequired` and
`stages` all go out together on every PUT, and `requestorSettings`, `expiration`,
`notificationSettings`, `reviewSettings` and `questions` go out on the same body. The document in
section 2 declared exactly ONE of those things. Everything else was carried forward from the live
policy by the read-modify-write in `Set-OERAccessPackageAssignmentPolicy`.

**This is unknown, and there is no `Expect:` line for it.** The unit suite pins that the module
BUILDS the sibling values correctly from `-Existing`. It cannot pin what Graph stores. Record the
comparison output verbatim; do not tick a box here on the strength of "it looked fine".

- [ ] **4.1 Diff every field the section 2 document never declared.**

  ```powershell
  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $After | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-after.json' -Encoding utf8

  $BeforeSib = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $SiblingFields | ConvertTo-Json -Depth 10
  $AfterSib  = $After | Select-Object $SiblingFields | ConvertTo-Json -Depth 10
  "identical: $($BeforeSib -eq $AfterSib)"
  Compare-Object -ReferenceObject ($BeforeSib -split "`n") -DifferenceObject ($AfterSib -split "`n")
  ```

  **Record:** the `identical:` line and, if it says `False`, every line `Compare-Object` printed.
  `identical: True` with no `Compare-Object` output means every never-declared field the module can
  see survived the PUT that cleared the stages. `identical: False` is the PR-5 hazard reproducing
  live: name the fields that moved, and note whether each one landed on a `ConvertTo-OERPolicyBody`
  New-default (`enableTargetsToSelfAddAccess = true` and the rest false; `allowedTargetScope` gone;
  `notificationSettings.isAssignmentNotificationDisabled = false`) or on something else -- a
  New-default says the carry-forward did not happen; anything else says Graph rewrote it.
  **Result:**

- [ ] **4.2 Requestor scope specifically -- the field PR-5 was originally about.**

  ```powershell
  $BeforeObj = Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json
  '{0} -> {1}' -f $BeforeObj.AllowedTargetScope, $After.AllowedTargetScope
  $BeforeObj.RequestorScope | Format-List *
  $After.RequestorScope     | Format-List *
  ```

  **Record:** both sides of the arrow, and both `RequestorScope` blocks in full (`scope`, `users`,
  `groups`). The section 2 document never declared `requestorScope`, so `Sync-OERStructureAccessPackage`
  never put `-RequestorScope` in the splat and `ConvertTo-OERPolicyBody` carried `allowedTargetScope`
  and `specificAllowedTargets` forward together as a unit. Whether Graph honoured that is the point of
  this check. A scope that came back `allMemberUsers` with an empty `users` list, from a Setup that set
  a specific user list, is the exact failure this section exists to catch.
  **Result:**

- [ ] **4.3 The two sibling approval flags.**

  ```powershell
  '{0} -> {1}' -f $BeforeObj.RequireRequestorJustification, $After.RequireRequestorJustification
  '{0} -> {1}' -f $BeforeObj.RequireApprovalForUpdate,      $After.RequireApprovalForUpdate
  ```

  **Record:** both arrows. These are the two members of `requestApprovalSettings` that sit beside
  `stages` in the same composite block and that the document never mentioned. Cross-check them in the
  portal too, since they are the ones a reader is most likely to accept on the module's word: "Require
  requestor's justification" is on the **Requests > Approval** section, and "Require approval to grant
  extension" is on the **Lifecycle** tab.
  **Result:**

- [ ] **4.4 `reviewSettings` -- portal only, because the module cannot see it.**

  `ConvertTo-OERPolicyBody` copies `reviewSettings` verbatim from `-Existing` when it is present, and
  omits it entirely otherwise. `ConvertTo-OERAssignmentPolicy` does not project it at all, so no
  `Get-OER*` read in this module will tell you whether it survived. Nothing in the document mentions
  it, which is precisely why it is worth checking.

  Open **ID Governance > Entitlement management > Access packages > `<your-test-access-package>` >
  Policies > `<your-test-policy>` > Edit > Lifecycle** and read the "Require access review" section.

  **Record:** whether the access review configuration recorded in check 1.5 is still there,
  field by field. If it is gone or reset, that is a silent data loss on every apply that touches an
  assignment policy, far wider than issue #56.
  **Result:**

- [ ] **4.5 `questions` -- portal only, same reason.**

  Open the same policy's **Requestor information** tab.

  **Record:** whether every custom question recorded in check 1.5 is still present, with the same text
  and the same required/optional setting.
  **Result:**

---

### 5. Regression -- an OMITTED `approvalStages` still leaves the live stages alone

This is the other half of the declared-gate. Making `[]` mean "clear" is only correct if omitting the
key still means "leave them alone". Section 2 left the policy with no stages, so this section restores
them first -- otherwise there is nothing for the omitted key to preserve.

- [ ] **5.1 Restore a stage by applying the baseline document.**

  Save as `./live/ap-baseline-stages.json`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>",
            "approvalStages": [
              {
                "durationDays": 14,
                "users": [ "<approver-upn>" ],
                "requireApproverJustification": true,
                "approverInfoVisibility": "Default"
              }
            ]
          }
        ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-baseline-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** validation `Valid = True` with only the catalog Warning; then `Updated` with Detail
  `updated assignmentPolicy '<your-test-policy>' (approvalStages)`.
  **Failure looks like:** `Failed` with a `UserNotFound` message -- `<approver-upn>` does not resolve.
  Fix the placeholder; `New-OERAccessPackageApprovalStage` resolves the UPN to an object id before the
  body is built, and the diff compares ids on both sides.
  **Result:**

- [ ] **5.2 Confirm the stage is live again, and capture the exact stage state.**

  ```powershell
  $Restored = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($Restored.ApprovalStages).Count
  $Restored.ApprovalStages | Format-List *
  $Restored | Select-Object RequireApproval
  ```

  **Expect:** one stage, `durationDays` 14, `users` holding the object id of `<approver-upn>`,
  `requireApproverJustification` `True`, `approverInfoVisibility` `Default`. `RequireApproval` is
  `$true` again -- derived from the non-empty stage list, the mirror image of check 3.1.
  **Result:**

- [ ] **5.3 Save the omitted-key document and validate it offline.**

  Save as `./live/ap-omit-stages.json`. It changes ONE thing -- the description -- and never mentions
  `approvalStages`. The changed description is what forces a real PUT; without it the diff would
  report `Unchanged`, no write would happen, and the check would prove nothing about carry-forward.

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>",
            "description": "issue 56 regression check -- approvalStages omitted"
          }
        ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-omit-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True`, only the catalog Warning.
  **Result:**

- [ ] **5.4 Apply it -- the stages must survive.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-omit-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize

  $AfterOmit = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($AfterOmit.ApprovalStages).Count
  $AfterOmit | Select-Object Description, RequireApproval
  Compare-Object -ReferenceObject (@($Restored.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress) `
                 -DifferenceObject (@($AfterOmit.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress)
  ```

  **Expect:** `Updated` with Detail `updated assignmentPolicy '<your-test-policy>' (description)` --
  the ChangedFields list names `description` and NOT `approvalStages`. The stage count is still `1`,
  `Description` is the new text, `RequireApproval` is still `$true`, and `Compare-Object` prints
  nothing.
  **Failure looks like:** a stage count of `0`. That is the fix over-reaching -- the declared-gate is
  firing on an omitted key, which would make every partial update in the wild silently delete the
  approvers. It is a strictly worse bug than the one this branch set out to fix, so treat it as a
  blocker, not a nuance.
  **Result:**

- [ ] **5.5 Apply the omitted-key document again -- convergence.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-omit-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged` with Detail `assignmentPolicy '<your-test-policy>' matches`.
  **Result:**

---

### 6. The self-contradictory document -- RECORDS U4

`requireApproval: true` with `approvalStages: []` means "approval is required, and there is nobody
who can approve". Before this branch the combination was harmless, because the live stages were
silently carried forward. Now it is real. The offline Warning added by commit `4754f3c` says the
policy is written "with approval required and no approver stages at all and no request can ever be
approved" -- **that second clause is an offline extrapolation from what the module writes, not an
observed fact.** This section is what turns it into one, or corrects it.

The live state going in has one approval stage (check 5.4 left it there).

- [ ] **6.1 Save the contradictory document and confirm the new Warning fires without blocking.**

  Save as `./live/ap-contradiction.json`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>",
            "requireApproval": true,
            "approvalStages": []
          }
        ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-contradiction.json'
  $V.Valid
  $V.Errors | Where-Object Severity -eq 'Warning' | Format-List Section, Item, Path, Message
  ```

  **Expect:** `$V.Valid` is `$true` -- a Warning never blocks an apply -- and a Warning at Path
  `accessPackages[0].assignmentPolicies[0].approvalStages` whose Message reads, in full:
  `'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is
  declared as an empty array; requireApproval takes precedence over the stage count, so the policy is
  written with approval required and no approver stages at all and no request can ever be approved.
  Add at least one entry to 'approvalStages', or set 'requireApproval' to false.`

  **Note added 2026-09-06, quote is stale:** the message above is the ORIGINAL wording and no
  longer matches the module -- it described a write Graph does not perform, and has since been
  corrected to name the `InvalidApprovalStages` refusal. Left unedited here as the historical
  record; check 8.1 of `docs/live-verification/fix-declared-value-family-and-au-prune-checklist.md`
  carries the current full-message quote.

  **Failure looks like:** `Valid` is `$false`. The finding was shipped as an Error and would block
  every apply of a document that validates today, which is not what the branch intends.
  **Result:**

- [ ] **6.2 Apply it. Do NOT predict the outcome -- record it. This is U4.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false -ErrorVariable ContradictionErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $ContradictionErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  Two outcomes are possible and they are materially different for the operator. Nobody knows which
  one holds.

  - **`Updated`** -- Graph accepted `isApprovalRequiredForAdd: true` with `stages: []`. The policy is
    written and is dead: approval required, nobody able to approve. The Warning's wording is exactly
    right and needs no change.
  - **`Failed`** -- Graph rejected it. The apply reports `Failed` with the Graph message in the
    Detail, and the Warning's description of the OUTCOME overstates: the policy is never written at
    all. Its remediation sentence ("Add at least one entry to 'approvalStages', or set
    'requireApproval' to false") stays correct either way, but the sentence before it would need a
    one-line correction in `Test-OERStructureSchema.ps1` and in the rationale entry.

  **Record the Action verbatim, the full Detail text, and every line `$ContradictionErr` printed.**
  **Result:**

- [ ] **6.3 Read the resulting live state back.**

  ```powershell
  $AfterContradiction = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($AfterContradiction.ApprovalStages).Count
  $AfterContradiction | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate
  ```

  **Record:** the stage count and `RequireApproval`. If 6.2 recorded `Updated`, this should show `0`
  stages with `RequireApproval` `$true` -- the dead policy. If 6.2 recorded `Failed`, this should be
  identical to check 5.4's state (one stage, approval required), proving nothing partial was written
  before the refusal. Anything else -- stages cleared but `RequireApproval` false, or stages cleared
  with a `Failed` record -- is a partial write and is a finding in its own right.

  Cross-check the same thing in the portal (**Requests > Approval**): does it show approval required
  with an empty approver list?
  **Result:**

- [ ] **6.4 Apply the contradictory document a second time -- does it converge?**

  ```powershell
  Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Record:** the Action. A contradictory document that reports `Updated` forever is still a
  non-convergence, of the same class as issue #56, even though the document is the operator's own
  fault. If 6.2 recorded `Failed`, this run recording `Failed` again is expected and correct -- an
  unappliable document should keep saying so.
  **Result:**

- [ ] **6.5 If 6.2 recorded `Updated`: does the dead policy behave as the Warning claims?**

  Optional but conclusive. Sign in to https://myaccess.microsoft.com as a user in scope of
  `<your-test-policy>` and try to request `<your-test-access-package>`.

  **Record:** whether the request can be submitted at all, and if it can, whether it sits pending with
  no possible approver. This is the only direct evidence for the Warning's claim that "no request can
  ever be approved". If 6.2 recorded `Failed`, write "not applicable -- Graph refused the write" on
  the result line rather than leaving it blank.
  **Result:**

---

### 7. The `-WhatIf` plan and the create path

The live state going in has whatever check 6.3 recorded. Both checks below re-establish what they
need.

- [ ] **7.1 `-WhatIf` must plan the change and write nothing.**

  ```powershell
  $StagesBeforeWhatIf = @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  $StagesBeforeWhatIf

  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize

  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  **Expect:** a `Skipped` record with Detail `would update assignmentPolicy '<your-test-policy>'`, and
  the stage count AFTER identical to the count BEFORE. Reads still run under `-WhatIf` so the plan is
  complete; writes do not.
  **Failure looks like:** the stage count changing, or an `Updated` record under `-WhatIf`. Either
  means the handler wrote through a `ShouldProcess` gate it should have respected.
  **Result:**

- [ ] **7.2 Apply the baseline for real, to leave a stage in place for the create check.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  **Expect:** `Updated` naming `approvalStages`, and a stage count of `1`.
  **Result:**

- [ ] **7.3 Save the create document and validate it offline.**

  Save as `./live/ap-create-policy.json`. It declares the EXISTING policy with nothing but its
  display name (so it diffs to `Unchanged` and is left alone) plus a NEW policy carrying
  `"approvalStages": []`.

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>"
          },
          {
            "displayName": "<your-new-policy>",
            "approvalStages": []
          }
        ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-create-policy.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True`, only the catalog Warning.
  **Result:**

- [ ] **7.4 `-WhatIf` on the create path.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize

  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName
  ```

  **Expect:** a `Skipped` record with Detail `would create assignmentPolicy '<your-new-policy>'`, an
  `Unchanged` record for `<your-test-policy>`, and NO policy named `<your-new-policy>` in the
  read-back.
  **Result:**

- [ ] **7.5 Apply for real -- the create path with an empty stage list. Also touches U1.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize

  $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy
  $NewPol | Select-Object Id, DisplayName, AllowedTargetScope, RequireApproval
  @($NewPol.ApprovalStages).Count
  ```

  **Expect (module side, CONDITIONAL on U1 below):** the new policy's record will read `Created`, with
  Detail `created assignmentPolicy '<your-new-policy>'`, **IF Graph accepts the empty stages array on
  a POST**; if Graph rejects it, that record reads `Failed` instead. Record which. Independently of
  that, `<your-test-policy>` must read `Unchanged` -- an existing policy declared with only a display
  name has no declared fields to diff and must be left completely alone. If the policy WAS created, it
  reads back with `AllowedTargetScope` `allMemberUsers` (the handler's create default when the
  document declares no `requestorScope`), `RequireApproval` `$false`, and `0` stages.

  **Unknown (Graph side) -- U1 on the create path.** A `POST` of a policy whose
  `requestApprovalSettings.stages` is `[]` has the same never-observed shape as the `PUT` in check
  2.2. Note the branch commentary's own claim here: this splat site was corrected for uniformity and
  is described as behaviour-neutral, because `ConvertTo-OERPolicyBody` is called with no `-Existing`
  and bound-empty and omitted resolve identically. **Record the Action and Detail verbatim.** A
  `Failed` here would falsify that "behaviour-neutral" claim on the wire even though it holds in the
  body builder.

  **Note the id of the created policy -- section 9 deletes it:** ______________________________
  **Result:**

- [ ] **7.6 Re-apply the create document -- convergence on both entries.**

  ```powershell
  Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** two `Unchanged` records -- `assignmentPolicy '<your-test-policy>' matches` and
  `assignmentPolicy '<your-new-policy>' matches`. The second is the create path's convergence proof:
  a freshly created policy whose document declares `approvalStages: []` must read back as already
  matching.
  **Failure looks like:** `Updated` on `<your-new-policy>` -- the create wrote something the diff does
  not recognise as the declared state, which is the same non-convergence class in a different place.
  If check 7.5 recorded `Failed`, this run will record `Failed` again (there is nothing to converge
  on); note that and move on rather than treating it as a second finding.
  **Result:**

---

### 8. Access reviews -- a declared-empty `reviewers` list. RECORDS U3 and U5

Independent of sections 1 - 7. It runs against `<your-review-access-package>` /
`<your-review-policy>` -- the second package from Setup, deliberately one with NO Lifecycle access
review configured, so the definitions created here are unambiguously the ones under test.

Before this branch, `"reviewers": []` fell into the manager-default branch, and the
manager-requires-fallback guard then reported `Failed` with the definition never created -- forever,
on every run. With `fallbackReviewers` also declared, the review WAS created, but as a MANAGER
review; run 2 then hit the update path, read the same `[]` correctly as a SELF review, saw drift, and
rewrote it. So run 1 landed on a state the document never asked for and run 2 churned it. Both halves
of that are what this section retires.

- [ ] **8.1 Save the self-review document and validate it offline.**

  Save as `./live/ar-self-no-fallback.json`. **Change `startDate` to a date at least one day in the
  future before you run this.**

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      {
        "displayName": "<your-test-review>",
        "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>",
        "recurrence": "Weekly",
        "startDate": "2026-09-01",
        "occurrences": 4,
        "durationInDays": 7,
        "descriptionForAdmins": "issue 56 live check -- declared-empty reviewers",
        "descriptionForReviewers": "Please review your own access.",
        "reviewers": []
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-self-no-fallback.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True` and NO findings at all -- an empty list, not a list with one Warning in
  it. In particular there must be NO Warning at Path `accessReviews[0].fallbackReviewers`. A
  declared-empty `reviewers` list is a SELF review on both the create and the update path, and a self
  review needs no fallback, so the offline gate must not demand one. `Test-OERStructureSchema` used to
  classify `@($AR.reviewers).Count -eq 0` as "uses manager"; commit `36fdde7` removed that clause,
  which is exactly what this check confirms is loaded.
  **Failure looks like:** the manager-fallback Warning appearing anyway --
  `A manager reviewer at accessReviews[0] (declared, or the default when 'reviewers' is omitted)
  requires 'fallbackReviewers'; Microsoft Graph rejects the review otherwise.` That means the loaded
  module predates `36fdde7`, and the offline gate is contradicting the write path it is supposed to
  preview. Re-import a current build before running 8.2; it is NOT a reason to change the document,
  and NOT a reason to add `fallbackReviewers` here -- check 8.5 covers the fallback variant
  separately and on purpose.
  **Result:**

- [ ] **8.2 First apply -- U3. Do NOT predict the outcome.**

  ```powershell
  Invoke-OERStructure -Path './live/ar-self-no-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable ReviewErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $ReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect (module side):** the handler no longer takes the manager-default branch, so the
  manager-requires-fallback guard cannot fire. The record is whatever the `POST` produced.

  **Unknown (Graph side) -- U3.** Nobody has yet observed whether Microsoft Graph accepts a
  `POST accessReviewScheduleDefinitions` with an empty `reviewers` collection and NO
  `fallbackReviewers` -- that is, whether a self review genuinely needs no fallback.

  - **`Created`** with Detail `created access review '<your-test-review>' (recurrence: Weekly)` means
    it does not, and the branch's reading of a declared-empty list is confirmed end to end.
  - **`Failed`** means Graph does require something more. **Read this as a finding, not as a passed
    check.** It would mean the correct fix is a clearer `Failed` that NAMES the self-review case, not
    the silent manager substitution this branch removes -- the substitution was wrong either way,
    because it created a state the document never asked for.

  **Record the Action, the full Detail, and every line `$ReviewErr` printed.** The old symptom, for
  contrast, was `Failed` with Detail `manager reviewer requires fallbackReviewers; declare a
  fallbackReviewers user or group for '<your-test-review>'` -- if you see THAT exact text, the loaded
  module does not carry the access review fix.
  **Result:**

- [ ] **8.3 Read the created definition back.**

  Skip and mark "not applicable" if 8.2 recorded `Failed`.

  ```powershell
  $Def = Get-OERAccessReviewDefinition -DisplayName $Review1
  $Def | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount, Recurrence, DurationInDays
  $Def.Reviewers | Format-List *
  $Def.FallbackReviewers | Format-List *
  ```

  **Expect:** `ReviewerCount` is `0` and `Reviewers` is empty -- that is what a self review looks like
  on the wire; the reviewers collection is left empty rather than carrying a `./manager` query.
  `FallbackReviewers` is empty. `Scope` names the access package and assignment policy.
  **Failure looks like:** a reviewer whose query is `./manager` -- the manager default was applied
  after all, which is the pre-fix behaviour reaching the tenant.

  **Note the definition id -- section 9 deletes it:** ______________________________
  **Result:**

- [ ] **8.4 Second apply, same document -- the convergence proof.**

  ```powershell
  Invoke-OERStructure -Path './live/ar-self-no-fallback.json' -Include AccessReviews -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged` with Detail `access review '<your-test-review>' already matches`. This is
  the half of the fix that the create path alone cannot show: the update path already read `[]` as a
  self review, so run 2 must now agree with what run 1 created. Run a third time as well -- an
  alternating Created/Updated/Updated pattern is still non-convergent.
  **Failure looks like:** `Updated` with a `Changes` list naming the reviewers -- create and update
  still disagree about what a declared-empty list means, which is the churn this branch set out to
  end. Skip and mark "not applicable" if 8.2 recorded `Failed`.
  **Result:**

- [ ] **8.5 A declared-empty `reviewers` WITH a fallback -- U5.**

  Save as `./live/ar-self-with-fallback.json`, with the same future-dated `startDate`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      {
        "displayName": "<your-second-test-review>",
        "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>",
        "recurrence": "Weekly",
        "startDate": "2026-09-01",
        "occurrences": 4,
        "durationInDays": 7,
        "descriptionForAdmins": "issue 56 live check -- declared-empty reviewers with a fallback",
        "descriptionForReviewers": "Please review your own access.",
        "reviewers": [],
        "fallbackReviewers": [ "<fallback-upn>" ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-self-with-fallback.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable FbReviewErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $FbReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect (offline):** `Valid = True` with NO findings at all.

  **Unknown (Graph side) -- U5.** This document sends `-SelfReview` and `-FallbackReviewer` together.
  `New-OERAccessReviewDefinition` refuses `-SelfReview` combined with `-Manager`, `-Reviewer` or
  `-ReviewerGroup` (`MutuallyExclusiveReviewer`), but it forwards a fallback alongside a self review
  untouched. Whether Graph accepts that pairing has never been observed. **Record the Action, the full
  Detail, and every line `$FbReviewErr` printed.** A rejection here is a finding: the module would
  need to refuse the pairing offline, or drop the fallback, rather than let a tenant error surface.

  **Note the definition id if one was created -- section 9 deletes it:** ______________________________
  **Result:**

- [ ] **8.6 Read back and re-apply the fallback document.**

  Skip and mark "not applicable" if 8.5 recorded `Failed`.

  ```powershell
  $Def2 = Get-OERAccessReviewDefinition -DisplayName $Review2
  $Def2 | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount
  $Def2.Reviewers | Format-List *
  $Def2.FallbackReviewers | Format-List *

  Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `ReviewerCount` `0`, `Reviewers` empty, `FallbackReviewers` holding `<fallback-upn>`;
  then `Unchanged` with Detail `access review '<your-second-test-review>' already matches`.
  **Failure looks like:** `Updated` on run 2 -- the diff and the create disagree about the fallback
  half, which is a second, independent non-convergence.
  **Result:**

---

### 9. Teardown -- restore the tenant, and be honest about what cannot be restored

**A cleared approval stage cannot be un-cleared.** There is no undo: the only way back is to
re-declare the stage and write it again, which is what check 9.3 does. Two things do not come back
that way, and both are documented in the schema itself:

- a stage is always rebuilt as a WHOLE (Graph takes the full `approvalStages` array, not a per-stage
  patch), so any **escalation-approver fallback** set through the portal
  (`fallbackEscalationApprovers`) is cleared and is not authorable through the document. If the Setup
  policy had one, it must be re-created by hand in the portal;
- the policy `description` was overwritten in check 5.4 and is restored below from what you recorded
  in check 1.4.

- [ ] **9.1 Delete the assignment policy created in check 7.5.**

  ```powershell
  $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy
  $NewPol | Select-Object Id, DisplayName
  Remove-OERAccessPackageAssignmentPolicy -Id $NewPol.Id
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName
  ```

  **Expect:** the cmdlet prompts (it is `ConfirmImpact = High`) and warns
  `Deleting assignment policy '<id>'. This is irreversible.`; after confirming, the read-back lists
  only `<your-test-policy>`. Skip and mark "not applicable" if 7.5 recorded `Failed`.
  **Result:**

- [ ] **9.2 Delete the access review definitions created in section 8.**

  ```powershell
  Remove-OERAccessReviewDefinition -DisplayName $Review1
  Remove-OERAccessReviewDefinition -DisplayName $Review2
  Get-OERAccessReviewDefinition -All | Where-Object DisplayName -in @($Review1, $Review2)
  ```

  **Expect:** each removal prompts; the final read returns nothing. Skip either line, and say so, if
  the matching create recorded `Failed`.
  **Result:**

- [ ] **9.3 Re-apply the original stage AND the original description.**

  Save as `./live/ap-restore.json`, substituting the description you recorded in check 1.4 and the
  stage configuration you recorded there:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "<your-test-access-package>",
        "catalog": "<your-test-catalog>",
        "resourceRoles": null,
        "assignmentPolicies": [
          {
            "displayName": "<your-test-policy>",
            "description": "<original-description-from-1.4>",
            "requireApproval": true,
            "approvalStages": [
              {
                "durationDays": 14,
                "users": [ "<approver-upn>" ],
                "requireApproverJustification": true,
                "approverInfoVisibility": "Default"
              }
            ]
          }
        ]
      }
    ]
  }
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-restore.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** validation `Valid = True` with only the catalog Warning -- and specifically NOT the
  contradiction Warning, since `approvalStages` here is non-empty. Then `Updated`, naming
  `description` and/or `approvalStages` depending on what check 6 left behind, followed by an
  `Unchanged` if you re-run it.
  **Result:**

- [ ] **9.4 Compare the final policy against the section 1 baseline, field by field.**

  ```powershell
  $Final = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $BeforeAll = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $AllFields | ConvertTo-Json -Depth 10
  $FinalAll  = $Final | Select-Object $AllFields | ConvertTo-Json -Depth 10
  "identical: $($BeforeAll -eq $FinalAll)"
  Compare-Object -ReferenceObject ($BeforeAll -split "`n") -DifferenceObject ($FinalAll -split "`n")
  ```

  **Record:** the `identical:` line and every difference. Some differences are expected and benign --
  the restored stage carries the object id rather than the UPN you typed, and an
  `approverInfoVisibility` or `managerLevel` the portal left implicit may now read as an explicit
  `Default` / `1`. **Write down every field that did not come back and why**, rather than waving at
  the diff. A field that moved and has no explanation is a finding this branch caused.
  **Result:**

- [ ] **9.5 Confirm the portal-only fields survived the whole run.**

  Open **ID Governance > Entitlement management > Access packages > `<your-test-access-package>` >
  Policies > `<your-test-policy>` > Edit** and compare against what you recorded in check 1.5.

  **Record:** whether the **Requestor information** questions and the **Lifecycle** access review are
  still exactly as they were. If either is gone, restore it by hand now, and note that the loss --
  not the manual restore -- is the result of this check.
  **Result:**

- [ ] **9.6 Restore anything the document could not.**

  Specifically: any escalation-approver fallback that was configured on the approval stage in Setup,
  which check 9.3 could not re-declare. Re-create it in **Requests > Approval** by hand.

  **Record:** what you had to restore manually, or "nothing" if the stage had no portal-set
  escalation fallback to begin with.
  **Result:**

- [ ] **9.7 Clean up the working folder.**

  ```powershell
  Remove-Item -Path './live' -Recurse -Force
  Disconnect-OER
  ```

  **Result:**
