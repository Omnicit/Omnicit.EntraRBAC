# Live verification checklist -- declared-value family and AU-prune warning (issues #67, #68, #69, #70, #59)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

This file is a CONSOLIDATION. It absorbs every still-relevant check from
`fix-structure-empty-approval-stages-checklist.md` (issue #56, PR #66), whose own 45 checks were
never run in the four sprints since it merged. Rather than build the same access-package /
assignment-policy / access-review tenant setup twice, this file builds it once and covers both that
branch's fixes and this sprint's. See "What this file absorbs" below for exactly what moved, what
was re-verified against current source, and what was dropped.

**`-Prune` is opt-in and destructive.** Every prune-related check below uses `-Prune -PlanOnly`
through the `Invoke-LiveCheck` helper defined in Setup -- `-PlanOnly` reads the `-WhatIf` plan and
stops. Issue #59 explicitly does not need the destructive form run for real to prove its fix; do
not add `-Confirm:$false` to a prune call unless a specific check says to.

## What changed and why this needs a live tenant

Five issues, all fixed by routing more of the apply engine's declared-value reads through the
single "declared" owners `Test-OERDeclaredProperty` / `Test-OERDeclaredNull`
(`docs/development/rationale.md#declared-property`), plus one new offline cross-reference rule:

- **#67** (`0188a60`) -- proves a fix that was already loaded: an access review document with
  `"recurrence": null` is read the same as an omitted key (`Sync-OERStructureAccessReview.ps1`
  line 135), so it creates a `OneTime` review instead of failing with "unrecognised recurrence
  value ''". The live-relevant question is the non-convergence PROOF: does a second apply of the
  same document report `Unchanged`, not another `Created`/`Failed`.
- **#70** (`5f52223`, `5de8a9e`, `df62d77`, `5079469`) -- migrates the remaining
  `PSObject.Properties.Name -contains` sites across every `Sync-OERStructure*.ps1` handler. Most
  sites are behavior-identical (verified below, per site) or improve only a `-WhatIf` label text.
  Two are genuinely observable on a live tenant:
  - **Access review create fields** (`descriptionForAdmins`, `descriptionForReviewers`,
    `startDate`, `durationInDays`, `endDate`/`occurrences`, the notification-switch map,
    `defaultDecision`, `fallbackReviewers`): a null `startDate` or `endDate` used to CRASH the
    handler on an uncaught `[datetime]$null` cast (not the "coerces to 0001-01-01" outcome the
    original sprint plan assumed -- that premise was corrected during the work). Now a null in
    either field is read as omitted: `startDate` defaults to `(Get-Date)`, and `endDate: null`
    with `occurrences` declared falls through to the `occurrences` branch instead of crashing.
  - **Group `pimPolicy.member`/`.owner`** (`Sync-OERStructureGroup.ps1` around line 594): the
    nested-vs-flat selector now uses `Test-OERDeclaredProperty` (which access types have a usable
    block) together with `Test-OERDeclaredNull` (whether the nested form was used at all), so
    `"pimPolicy": {"member": null, "owner": {...}}` skips `member` and applies only `owner`. Before
    this fix, `member: null` selected the nested form (presence, not value) and passed a bare
    `$null` to `Resolve-OERGroupPimPolicyChange`'s non-nullable `-Declared` parameter, which threw
    -- so the WHOLE pimPolicy step failed for both access types, including the `owner` block the
    document correctly declared.
  - Two sites the sprint plan named as "observable" turned out NOT to be, on inspection of the
    current code: group `membershipRule` and `administrativeUnit` at group creation. See "What
    this file does not check, and why" below -- this was measured, not assumed, before being cut.
- **#68** (`5079469`, `da60669`) -- `Sync-OERStructureAccessPackage.ps1`'s back-compat approver
  fallback used to overwrite a stage's `alternateUsers` with the Tenant Profile
  `EscalationApprovers` default whenever the stage had no explicit primary approver (`users`,
  `groups`, `manager`, `internalSponsor`, `externalSponsor` all empty/absent) -- even when the
  document had declared its own `alternateUsers`. It is now gated on
  `Test-OERDeclaredProperty` finding no declared `alternateUsers` at all, so a document's own
  escalation approvers survive. The substitution, when it does happen, now also writes a
  `Write-Warning` naming the policy, the stage index, and the substituted counts. The same commit
  closes #70 site 3 (`durationDays`): an absent/null `durationDays` still applies `0`
  (`-DurationDays` is Mandatory, so the splat key can never be dropped), and `0` is NOT a quiet
  `P0D` stage -- `ConvertTo-OERDuration`'s `[ValidateRange(1, ...)]` throws, and the WHOLE
  assignmentPolicy is reported `Failed` instead of created or updated. `Test-OERStructureSchema`
  now warns offline about that real outcome.
- **#69** (`319cf09`, `9a52334`) -- a `requestorScope` declaring non-empty `users`/`groups` with no
  `scope` is now read as `SpecificDirectoryUsers`; an explicit `scope` still always wins, and a
  declared-empty list still falls back to `AllMemberUsers`. **What changed is that the document is
  now ACCEPTED, not what an accepted document does.** Such a document was REFUSED at validation
  before (`Test-OERStructureSchema`'s blanket Error, and `Invoke-OERStructure` aborts on any Error
  with no `-SkipValidation` escape), so it never reached the handler through `Invoke-OERStructure`
  and the `AllMemberUsers` fallback -- which would have discarded the `users`/`groups` entirely --
  was never applied to a tenant. Do not go looking for a customer tenant with a widened requestor
  scope written by an earlier release; there is none. The document now passes with a Warning
  instead of the Error. `schema.json` no longer requires `scope` on `requestorScope`.
- **#59** (`dcebb94`) -- `administrativeUnit` on a `groups[]` entry is create-path only
  (`Sync-OERStructureGroup.ps1`) and is never read back by `Get-OERInventory`, so the only way a
  document keeps a group inside a unit across repeated applies is to ALSO name the group in that
  unit's own `administrativeUnits[].members`. Without it, `-Prune` removes the membership the
  create just added in the SAME apply run -- `Invoke-OERStructure` dispatches `administrativeUnits`
  after `groups`, and the `-EnsureOnly` pre-pass reconciles no members -- and again on every later
  apply, and nothing self-heals it (the create-only field never
  fires again once the group exists). This was actually FOUND by PR #53's own live run (its check
  3.6). The fix is option A+B from the pre-authorised decision, not C: a new offline
  `Test-OERStructureSchema` Warning documents the trap; the destructive prune pass itself is
  deliberately left untouched and independent of the groups section.

**Every test on this branch mocks `Invoke-OERGraphRequest`.** It proves the module SENDS the
intended body. It proves nothing about what Microsoft Graph does with that body, or about what a
warning claims will happen downstream. Everything below writes to, or reads from, a real tenant.

## What this file absorbs, and what was re-verified

Per Task 10's instruction, every one of PR #66's 45 checks was re-read against source on this
branch, not carried over unread. **The arithmetic, stated explicitly so it can be checked rather
than derived:** the old file's Section 1 (Preparation, 5 checks: 1.1-1.5) plus Sections 2-8 (the
approvalStages/access-review fix walkthrough, 4+2+5+5+5+6+6 = 33 checks: 2.1-2.4, 3.1-3.2, 4.1-4.5,
5.1-5.5, 6.1-6.5, 7.1-7.6, 8.1-8.6) plus Section 9 (Teardown, 7 checks: 9.1-9.7) is `5 + 33 + 7 =
45` -- every one of the old file's checks. All 45 have a home below:

| Old file | Old count | Absorbed into | Re-verified against |
|---|---|---|---|
| Section 1 (Preparation) | 5 (1.1-1.5) | Section 1 (Preparation and baseline capture) | Renamed and renumbered 1:1, same checks, same policy setup; `1.2` gained a second probe for this sprint's own fixes. |
| Section 2 (convergence) | 4 (2.1-2.4) | Section 3 | `Sync-OERStructureAccessPackage.ps1`'s `-ApprovalStage` splat gating -- unchanged this sprint except for the stage-loop additions in `5079469`, which only run when `approvalStages` has at least one entry; a `[]` array still short-circuits the `foreach` before reaching any of them. |
| Section 3 (read-back) | 2 (3.1-3.2) | Section 4 | `ConvertTo-OERPolicyBody.ps1`'s `isApprovalRequiredForAdd` derivation -- not touched this sprint (confirmed by `git log` on that file). |
| Section 4 (composite hazard, U2) | 5 (4.1-4.5) | Section 5 | Same -- `ConvertTo-OERPolicyBody.ps1` carries every sibling field forward from `-Existing` exactly as before. |
| Section 5 (omitted-stages regression) | 5 (5.1-5.5) | Section 6 | The stage-restore document declares real `users`, so `HasExplicitApprover` is true and none of #68's new fallback/warning code paths fire; unaffected. |
| Section 6 (contradiction, U4) | 5 (6.1-6.5) | Section 8 | The exact Warning message text at `Test-OERStructureSchema.ps1` line 786 is byte-identical to what the old file quotes -- confirmed by direct `grep`, not assumption. |
| Section 7 (-WhatIf/create, U1) | 6 (7.1-7.6) | Section 9 | Unaffected -- same reasoning as row 2; the create document's second policy also declares `approvalStages: []`. |
| Section 8 (declared-empty reviewers, U3/U5) | 6 (8.1-8.6) | Section 10.3/10.4 | `Test-OERStructureSchema.ps1`'s manager/fallback Warning message GREW a clause this sprint ("... or explicitly null ... A declared-empty list counts as no fallback.") but the document under test here never takes that branch at all (a declared-empty `reviewers` is the self-review branch, not the manager one), so the check's `Expect:` is unaffected. The old file's "Failure looks like" quotes are updated below to the CURRENT message text so a stale-build reader is not shown a string current source no longer produces verbatim. |
| Section 9 (Teardown) | 7 (9.1-9.7) | Section 13, checks 13.1-13.5 and 13.10-13.11, IN ORDER | Old 9.1-9.5 become new 13.1-13.5 unchanged in substance; old 9.6 (restore what the document could not) becomes 13.10; old 9.7 (clean the working folder) becomes 13.11. Checks 13.6-13.9 in between are NEW, for this sprint's own additions (restoring the requestor scope section 2 changed, deleting the group/AU section 12 created, restoring the PIM owner policy section 11 changed, and removing the Tenant Profile Defaults added for section 7). |

**Nothing was dropped as stale.** `5 + 4 + 2 + 5 + 5 + 5 + 6 + 6 + 7 = 45`, matching the row counts
above, and every one of those 45 checks is represented in the new file. Every absorbed check's
`Expect:`/`Failure looks like:` prose was additionally checked line-by-line against the code as it
stands on this branch; the table above records what was checked, not an assumption that nothing
could have changed.

**What was NOT absorbed, and why:** the old file's Setup-only prose (the five-question `U1`-`U5`
table's framing, the placeholder table, the `$AllFields`/`$SiblingFields` variable definitions) is
folded into this file's own Setup section rather than duplicated verbatim; the SUBSTANCE is
unchanged, only where it lives.

## What this file does not check, and why

Two of the sprint plan's own candidate "observable" #70 sites turned out, on reading the current
code, to have **no observable difference at all** between the pre-fix and post-fix behaviour, so no
live check is written for them -- writing one would send the tenant operator to prove a difference
that does not exist on the wire:

- **Group `membershipRule` at creation** (`Sync-OERStructureGroup.ps1`, the `dynamic: true` block).
  A declared `"membershipRule": null` is read by `Test-OERDeclaredProperty` as not-declared, so the
  `-MembershipRule` parameter is never added to the creation splat. Before this fix, the OLD
  `-contains` check (presence, not value) DID add `-MembershipRule $null` to the splat. But
  `New-OERGroup`'s own `$MembershipRule` parameter is a plain `[string]` with no
  `[ValidateNotNull()]`, so PowerShell binds a `$null` argument to it without complaint, and the
  cmdlet's own guard (`if ($Dynamic -and -not $MembershipRule)`) is a VALUE check, not a
  binding-presence check -- `-not $null` and `-not <unbound, defaults to $null>` are both `$true`.
  Both the old splat (parameter bound to `$null`) and the new splat (parameter never bound) hit the
  identical `MembershipRuleRequired` non-terminating error with the identical message. The
  difference this sprint's unit tests observe (`$PSBoundParameters.Keys` containing
  `'MembershipRule'` or not) is real and correctly tested at that level, but it has no counterpart
  a live Graph call, or an operator watching the console, could ever tell apart.
- **Group `administrativeUnit` at creation**, same handler. Same reasoning: `New-OERGroup`'s
  `-AdministrativeUnit` is a plain `[string]`, and the cmdlet's own guard
  (`if ($AdministrativeUnit) { ... }`) is a truthiness check on the VALUE. A `$null` bound value and
  an unbound parameter are both falsy, so a group declared with `"administrativeUnit": null` is
  created outside any unit either way, with no error either way, before and after this fix.

If either analysis is wrong, the mistake would show up as a genuine difference in the live probes
in Setup check 1.2 below (which loads a build from this branch and would misbehave identically to a
pre-fix build if the analysis were backwards) -- but there is no separate numbered check for either
site here, and none should be added without first finding a Graph-observable difference that the
analysis above misses.

---

## Setup, once

You need:

- **One catalog** (`<your-test-catalog>`) holding two DISPOSABLE access packages, neither used by
  anything real:
  1. `<your-test-access-package>` with one assignment policy `<your-test-policy>`, used by
     sections 1, 2 and 3-9.
  2. `<your-review-access-package>` with one assignment policy `<your-review-policy>` and **no**
     Lifecycle access review configured, used only by section 10.
- **`<your-test-policy>` configured with DISTINCTIVE, non-default values** in every field the
  documents below never mention, exactly as PR #66's own checklist required (a reset to a default
  is only visible if the starting value was not the default already). Open **ID Governance >
  Entitlement management > Access packages > `<your-test-access-package>` > Policies >
  `<your-test-policy>` > Edit** and set:

  | Portal tab | Setting | Set it to |
  |---|---|---|
  | Requests | Users who can request access | a SPECIFIC set of users or groups, not "All members" |
  | Requests > Approval | If requestors must be approved | Yes, one stage naming `<approver-upn>` as approver, 14-day deadline |
  | Requests > Approval | Require requestor's justification | Yes |
  | Requestor information | Questions | at least ONE custom question |
  | Lifecycle | Access package assignments expire | a specific number of days (not Never) |
  | Lifecycle | Require approval to grant extension | Yes |
  | Lifecycle | Require access review | Yes, with a review configured |

- **A Tenant Profile with `Defaults` set**, needed for section 7 (#68) and the section 6 restore:

  ```powershell
  Set-OERConfiguration -TenantAlias $Alias -Defaults @{
      PrimaryApprovers    = @('<approver-upn>')
      EscalationApprovers = @('<profile-escalation-upn>')
  }
  ```

  `<profile-escalation-upn>` must be a DIFFERENT user from `<document-escalation-upn>` below --
  section 7 proves which one lands on the live stage, and that is only decidable if they differ.

- **`<approver-upn>`** -- the user named as the approval-stage approver in Setup, and as the
  profile's `PrimaryApprovers` default.
- **`<profile-escalation-upn>`** / **`<document-escalation-upn>`** -- two DIFFERENT users, for
  section 7.
- **`<specific-user-a>`** / **`<specific-user-b>`** -- two ordinary users, for section 2 (#69).
- **`<fallback-upn>`** -- a user who can be a fallback reviewer, for section 10.4.
- **One PIM-for-Groups onboarded group, `<your-pim-group>`**, with BOTH its member and owner
  policies configured with distinctive, non-default values (for example a distinctive
  `-EligibleDuration`/`-ActiveDuration` on both, and something observable set on the OWNER policy
  specifically, such as `-AuthenticationContextId 'c1'` or `-RequireJustification` via
  `-ActivationEnabledRules Justification`) -- section 11 needs the OWNER policy in a state that
  visibly changes, and the MEMBER policy in a state that must visibly NOT change.
- **`<your-test-au>`** -- an administrative unit that does NOT exist yet (section 12 creates it).
- **`<your-au-group>`** -- a group display name that does NOT exist yet (section 12 creates it,
  into `<your-test-au>`).
- **Identity Governance Administrator** in the tenant (catalog owner plus access package manager
  also works for most of section 1-10; section 12 additionally needs rights to create
  administrative units and groups).
- **The module built from THIS branch.** Setup check 1.2 below is the offline tell that confirms
  it, extended with a probe for this sprint's own fixes.
- A scratch folder for the JSON documents. The commands below use `./live`.

```powershell
$Alias              = '<your-tenant-alias>'
$Catalog            = '<your-test-catalog>'
$Package            = '<your-test-access-package>'
$Policy             = '<your-test-policy>'
$NewPolicy          = '<your-new-policy>'
$Approver           = '<approver-upn>'
$ProfileEscalation  = '<profile-escalation-upn>'
$DocEscalation      = '<document-escalation-upn>'
$SpecificUserA      = '<specific-user-a>'
$SpecificUserB      = '<specific-user-b>'
$RvPackage          = '<your-review-access-package>'
$RvPolicy           = '<your-review-policy>'
$Fallback           = '<fallback-upn>'
$PimGroup           = '<your-pim-group>'
$Au                 = '<your-test-au>'
$AuGroup            = '<your-au-group>'
$Doc                = './live/doc.json'

New-Item -ItemType Directory -Path './live' -Force | Out-Null
Connect-OER -TenantAlias $Alias

$Pkg = Get-OERAccessPackage -Catalog $Catalog | Where-Object DisplayName -eq $Package
$Pol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $Policy

# Every property the module surfaces on an assignment policy -- the same list PR #66's checklist
# used, unchanged this sprint. reviewSettings and questions are NOT here: the module's read
# projection does not model them at all (checks 5.4/5.5 below go to the portal instead).
$AllFields = @(
    'Id', 'DisplayName', 'AccessPackageId', 'AllowedTargetScope', 'Description', 'RequestorScope',
    'RequestorSettings', 'RequireApproval', 'RequireRequestorJustification', 'RequireApprovalForUpdate',
    'ApprovalStages', 'DurationInDays', 'DurationInHours', 'ExpirationDateTime', 'NotificationsDisabled')

# The subset that section 3's document never declares. Section 5 proves every one of these survived
# the PUT that cleared the stages. RequireApproval is deliberately EXCLUDED there -- see section 5.
$SiblingFields = @(
    'Description', 'AllowedTargetScope', 'RequestorScope', 'RequestorSettings',
    'RequireRequestorJustification', 'RequireApprovalForUpdate',
    'DurationInDays', 'DurationInHours', 'ExpirationDateTime', 'NotificationsDisabled')

function Invoke-LiveCheck {
    <#
    Wraps a checklist fragment into a valid document, validates offline, prints the -WhatIf plan,
    and (unless -PlanOnly) applies for real. Pattern reused from docs/live-verification/pr53-checklist.md.
    #>
    param(
        [Parameter(Mandatory)][string]$Fragment,
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews'),
        [switch]$Prune,
        [switch]$PlanOnly
    )
    $Document = $Fragment | ConvertFrom-Json
    $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
    $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
    $Document | ConvertTo-Json -Depth 20 | Set-Content -Path $Doc -Encoding utf8

    $Validation = Test-OERStructure -Path $Doc
    Write-Host '--- offline validation ---'
    $Validation | Select-Object Valid | Format-Table
    $Validation.Errors | Format-List Section, Item, Path, Message, Severity
    if (-not $Validation.Valid) { return }

    $Splat = @{ Path = $Doc; Include = $Include }
    if ($Prune) { $Splat['Prune'] = $true }
    Write-Host '--- plan ---'
    Invoke-OERStructure @Splat -WhatIf | Format-Table Section, Item, Action, Detail -AutoSize

    if ($PlanOnly) { return }
    Write-Host '--- apply ---'
    Invoke-OERStructure @Splat -Confirm:$false | Format-Table Section, Item, Action, Detail -AutoSize
}
```

| Placeholder | What it is |
|---|---|
| `<your-tenant-alias>` | The `Get-OERConfiguration` alias for the test tenant. |
| `<your-test-catalog>` | The catalog holding both disposable access packages. |
| `<your-test-access-package>` / `<your-test-policy>` | The package/policy used by sections 1-9. |
| `<your-new-policy>` | A policy display name not yet on `<your-test-access-package>`; section 9 creates and section 13 deletes it. |
| `<approver-upn>` | The Setup approval-stage approver, also the profile's `PrimaryApprovers` default. |
| `<profile-escalation-upn>` | The profile's `EscalationApprovers` default -- must differ from `<document-escalation-upn>`. |
| `<document-escalation-upn>` | The escalation approver a section 7 document declares itself. |
| `<specific-user-a>` / `<specific-user-b>` | Two ordinary users, for section 2. |
| `<your-review-access-package>` / `<your-review-policy>` | The SECOND package/policy, no Lifecycle review, section 10 only. |
| `<your-onetime-review>` | Access review name, not yet existing, section 10.1 (issue #67). |
| `<your-startdate-review>` | Access review name, not yet existing, section 10.2.1 (issue #70, null startDate). |
| `<your-enddate-review>` | Access review name, not yet existing, section 10.2.2 (issue #70, null endDate). |
| `<your-test-review>` / `<your-second-test-review>` | Access review names, not yet existing, section 10.3/10.4 (absorbed, U3/U5). |
| `<fallback-upn>` | The access review fallback reviewer, section 10.4. |
| `<your-pim-group>` | A PIM-for-Groups onboarded group with distinctive member AND owner policies, section 11. |
| `<your-test-au>` | An administrative unit that does not exist yet, section 12. |
| `<your-au-group>` | A group display name that does not exist yet, section 12. |

**Every JSON document below carries `"tenantAlias": "<your-tenant-alias>"`** via the
`Invoke-LiveCheck` helper. **Every accessPackages document below validates with one expected
Warning:** `accessPackages[0].catalog :: Catalog '<your-test-catalog>' is not declared in this
document. It may already exist in the tenant.` -- harmless, since these documents deliberately do
not declare the catalog. **Every accessPackages document below carries `"resourceRoles": null`**,
an explicit null meaning "declared without touching resource role bindings" (an omitted key would
run the reconcile pass and report every live binding as `Extra`).

**Run sections 1, 3-9 in that order** -- section 3 onward each depends on the live state the
previous one left. **Section 2 is independent** and can run any time after Setup (it touches
`requestorScope`, never `approvalStages`). **Sections 10-12 are independent of everything else**
and of each other. **Section 13 runs last.**

---

### 1. Preparation and baseline capture

- [x] **1.1 Resolve the package and the policy.** -- 2026-09-06

  ```powershell
  $Pkg | Select-Object Id, DisplayName, CatalogId
  $Pol | Select-Object Id, DisplayName
  ```

  **Expect:** exactly one row each; `$Pkg.Id` and `$Pol.Id` are GUIDs.
  **Failure looks like:** more than one row from `$Pkg`, or an empty `$Pol` -- fix the setup before
  going further; every later check reads `$Pol.Id`.
  **Result:**
  ```powershell
> $Pkg | Select-Object Id, DisplayName, CatalogId  
  
Id DisplayName CatalogId  
-- ----------- ---------  
00000000-0000-0000-0000-000000000001 oer-dv-ap 00000000-0000-0000-0000-000000000002  
  
> $Pol | Select-Object Id, DisplayName  
  
Id DisplayName  
-- -----------  
00000000-0000-0000-0000-000000000003 oer-dv-policy  
  
>
  ```

- [x] **1.2 Confirm the session is running THIS branch's build.** Three independent tells, neither
  costing a tenant call: the #56 contradiction Warning (unchanged this sprint), the #69
  requestorScope-inference Warning (added last sprint), and the requireApprovalForUpdate
  carry-forward Warning for a declared-empty `approvalStages` (new this sprint). -- 2026-09-06

  ```powershell
  $Probe1 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requireApproval":true,"approvalStages":[]}]}]}'
  $Probe1.Valid
  $Probe1.Errors | Format-List Section, Item, Path, Message, Severity

  $Probe2 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requestorScope":{"users":["u@contoso.com"]}}]}]}'
  $Probe2.Valid
  $Probe2.Errors | Format-List Section, Item, Path, Message, Severity

  $Probe3 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","approvalStages":[]}]}]}'
  $Probe3.Valid
  $Probe3.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `$Probe1.Valid` is `$true` with the catalog Warning PLUS one at path
  `accessPackages[0].assignmentPolicies[0].approvalStages` whose Message begins `'requireApproval'
  is true ... while 'approvalStages' is declared as an empty array`. `$Probe2.Valid` is `$true` with
  the catalog Warning PLUS one at path `accessPackages[0].assignmentPolicies[0].requestorScope.scope`
  whose Message begins `'requestorScope' at ... declares 'users' or 'groups' with no 'scope'`.
  `$Probe3.Valid` is `$true` with the catalog Warning PLUS one at path
  `accessPackages[0].assignmentPolicies[0].approvalStages` whose Message begins `'approvalStages' at
  ... clears every approval stage while the policy is not declared to stop requiring approval`.
  **Failure looks like:** `$Probe1` shows only the catalog Warning (predates commit `4754f3c`), or
  `$Probe2` shows only the catalog Warning (predates commit `319cf09`), or `$Probe3` shows only the
  catalog Warning (predates commit `37aca2d`) -- rebuild and re-import before running anything else,
  or every result below describes the wrong code.
  **Result:** (`$Probe1` and `$Probe2` only -- the third probe was added to this check AFTER the run,
  once the clear-stages Warning existed; check 14.0 is where it was actually measured.)
  ```powershell
> $Probe1.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : probe  
Path : accessPackages[0].assignmentPolicies[0].approvalStages  
Message : 'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is declared as an empty array; requireApproval takes precedence over the stage count, so the policy is written with approval required and no approver stages at all an  
d no request can ever be approved. Add at least one entry to 'approvalStages', or set 'requireApproval' to false.
Severity : Warning  
  
Section : accessPackages  
Item : probe  
Path : accessPackages[0].catalog  
Message : Catalog 'probe' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>  
> $Probe2 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requestorScope":{"users":["u@contoso.com"]}}]}]}'  
> $Probe2.Valid  
True  
> $Probe2.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : probe  
Path : accessPackages[0].assignmentPolicies[0].requestorScope.scope  
Message : 'requestorScope' at accessPackages[0].assignmentPolicies[0] declares 'users' or 'groups' with no 'scope'; Invoke-OERStructure infers 'scope' as 'SpecificDirectoryUsers'. Declare 'scope' explicitly instead of relying on the inference.
Severity : Warning  
  
Section : accessPackages  
Item : probe  
Path : accessPackages[0].catalog  
Message : Catalog 'probe' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
>
  ```

- [x] **1.3 Capture the FULL baseline policy to disk, before anything is written.** -- 2026-09-06

  ```powershell
  $Before = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $Before | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-before.json' -Encoding utf8
  Get-Content ./live/policy-before.json
  ```

  **Expect:** the file is written and prints a complete policy.
  **Result:**
  ```powershell
> $Before = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $Before | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-before.json' -Encoding utf8  
> Get-Content ./live/policy-before.json  
{  
"Id": "00000000-0000-0000-0000-000000000003",  
"DisplayName": "oer-dv-policy",  
"AccessPackageId": "00000000-0000-0000-0000-000000000001",  
"AllowedTargetScope": "specificDirectoryUsers",  
"Description": "oer-dv baseline: distinctive description, do not reset",  
"RequestorScope": {  
"scope": "SpecificDirectoryUsers",  
"users": [  
"00000000-0000-0000-0000-000000000004"  
],  
"groups": []  
},  
"RequestorSettings": {  
"allowSelfRequest": true,  
"allowManagerRequest": false,  
"managerLevel": 1,  
"allowCustomSchedule": false,  
"allowSelfExtend": true,  
"allowSelfRemove": true,  
"allowOnBehalfUpdate": false,  
"allowOnBehalfRemove": false  
},  
"RequireApproval": true,  
"RequireRequestorJustification": true,  
"RequireApprovalForUpdate": true,  
"ApprovalStages": [  
{  
"durationDays": 14,  
"manager": false,  
"managerLevel": 1,  
"users": [  
"00000000-0000-0000-0000-000000000004"  
],  
"groups": [],  
"internalSponsor": false,  
"externalSponsor": false,  
"alternateUsers": [],  
"alternateGroups": [],  
"fallbackUsers": [],  
"fallbackGroups": [],  
"escalationDays": null,  
"requireApproverJustification": true,  
"approverInfoVisibility": "Default"  
}  
],  
"DurationInDays": 90,  
"DurationInHours": null,  
"ExpirationDateTime": null,  
"NotificationsDisabled": false  
}  
>
  ```

- [x] **1.4 Confirm the baseline actually HAS approval stages, and record the identifiers.** -- 2026-09-06

  ```powershell
  @($Before.ApprovalStages).Count
  $Before.ApprovalStages | Format-List *
  $Before | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate,
      AllowedTargetScope, Description, DurationInDays, DurationInHours, ExpirationDateTime, NotificationsDisabled
  $Before.RequestorScope | Format-List *
  $Before.RequestorSettings | Format-List *
  ```

  **Expect:** `@($Before.ApprovalStages).Count` is at least `1`; `RequireApproval`,
  `RequireRequestorJustification`, `RequireApprovalForUpdate` are all `$true`; `AllowedTargetScope`
  is NOT `allMemberUsers`; a duration is set. If any is at its default, go back to Setup -- section
  5 cannot detect a reset to a value that was already there.

  **Access package id:** `00000000-0000-0000-0000-000000000001` (`oer-dv-ap`)
  **Assignment policy id:** `00000000-0000-0000-0000-000000000003` (`oer-dv-policy`)
  **Original policy `Description` (section 13 restores it):** `oer-dv baseline: distinctive description, do not reset`
  **Stage count / approver / decision deadline days:** 1 stage / `person1@example.com` (object id `00000000-0000-0000-0000-000000000004`, "Choose specific approvers") / 14 days, approver justification required, `approverInfoVisibility` Default; no alternate/fallback/escalation approvers
  **Result:**
  ```powershell
> @($Before.ApprovalStages).Count  
1  
> $Before.ApprovalStages | Format-List *  
  
durationDays : 14  
manager : False  
managerLevel : 1  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
internalSponsor : False  
externalSponsor : False  
alternateUsers : {}  
alternateGroups : {}  
fallbackUsers : {}  
fallbackGroups : {}  
escalationDays :  
requireApproverJustification : True  
approverInfoVisibility : Default  
  
> $Before | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate,  
> AllowedTargetScope, Description, DurationInDays, DurationInHours, ExpirationDateTime, NotificationsDisabled  
  
RequireApproval : True  
RequireRequestorJustification : True  
RequireApprovalForUpdate : True  
AllowedTargetScope : specificDirectoryUsers  
Description : oer-dv baseline: distinctive description, do not reset  
DurationInDays : 90  
DurationInHours :  
ExpirationDateTime :  
NotificationsDisabled : False  
  
> $Before.RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
  
> $Before.RequestorSettings | Format-List *  
  
allowSelfRequest : True  
allowManagerRequest : False  
managerLevel : 1  
allowCustomSchedule : False  
allowSelfExtend : True  
allowSelfRemove : True  
allowOnBehalfUpdate : False  
allowOnBehalfRemove : False  
  
>
  ```

- [x] **1.5 Record the two fields the module cannot see at all.** -- 2026-09-06 `reviewSettings` and `questions`
  are carry-forward-only; no `Get-OER*` read in this module will ever show them.

  Open **ID Governance > Entitlement management > Access packages > `<your-test-access-package>` >
  Policies > `<your-test-policy>` > Edit** and note:

  **Expect:** there is no single correct value to check against -- this only needs to capture
  whatever Setup put there, so checks 5.4/5.5 have something to compare against later. At minimum,
  per the Setup requirements above, at least one custom question and a configured Lifecycle access
  review should be visible; if either is missing, Setup was not completed and section 5 will not be
  able to detect a loss.

  **Requestor information tab -- questions (text, required/optional):** ONE question, text
  `oer-dv: why do you need this access? (setup question, section 1.5 / 5.5)`, answer format
  **Long text**, no localization, no regex pattern, **Required** (checked). No catalog resource
  attributes.
  **Lifecycle tab -- "Require access review" setting and configuration:** **Require access reviews:
  checked.** Starting on 9/7/2026 (the day after Setup), frequency **Quarterly**, duration **21**
  days, reviewers **Specific reviewer(s)** = `oer-dv-approver`. Advanced: if reviewers don't
  respond **No change**, show reviewer decision helpers **Yes**, require reviewer justification
  **Yes**, reminders **checked**.
  **Also captured from the same Edit view (2026-09-06), for 13.5/13.6 cross-checks:**
  Basics: Name `oer-dv-policy`, Description `oer-dv baseline: distinctive description, do not
  reset`, Disable assignment emails **No**. Requests: Who can get access **For users, service
  principals, and agent identities in your directory** > **Specific users and groups** =
  `oer-dv-approver`; Who can request access **Self** (Admin always on; Manager and Users in your
  directory unchecked); Require requestor justification **Yes**; Require approval **Yes**, 1 stage,
  First Approver **Choose specific approvers** = `oer-dv-approver`, decision in **14** days, Require
  approver justification **Yes**; no Verified ID issuers. Lifecycle: expire after **Number of days
  = 90**, Users can request specific timeline **No**, Allow users to extend access **Yes**, Require
  approval to grant extension **Yes**. Custom extensions: none.
  *Record (2026-09-06): both portal-only fields are present exactly as `Initialize-OerDvPrereq.ps1`
  set them, so section 5 has a non-default value to detect a loss against.*
  **Result:**
  ```powershell
  # Portal-only fields; no console output. Captured from the Edit policy blades above.
  # Cross-check through Graph (the only programmatic read of these two fields):
  # (Invoke-MgGraphRequest -Uri "v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000003" -OutputType PSObject) |
  #     Select-Object -ExpandProperty questions        -> 1 accessPackageTextInputQuestion, isRequired True
  # ... | Select-Object -ExpandProperty reviewSettings -> isEnabled True, absoluteMonthly/3, P21D, primaryReviewers singleUser
  ```

---

### 2. Requestor scope infers SpecificDirectoryUsers -- issue #69

Independent of sections 1, 3-9: it only touches `requestorScope`, never `approvalStages`. Run it
any time after Setup.

- [x] **2.1 Offline: the scope-less document with users is now a Warning, not an Error.** -- 2026-09-06

  ```powershell
  $Frag = @"
  { "accessPackages": [ { "displayName": "$Package", "catalog": "$Catalog", "resourceRoles": null,
    "assignmentPolicies": [ { "displayName": "$Policy",
      "requestorScope": { "users": [ "$SpecificUserA", "$SpecificUserB" ] } } ] } ] }
  "@
  $Document = $Frag | ConvertFrom-Json
  $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
  $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/ap-scopeless-users.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/ap-scopeless-users.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid` is `$true`; TWO Warnings -- the catalog one, plus one at
  `accessPackages[0].assignmentPolicies[0].requestorScope.scope` whose Message reads, in full:
  `'requestorScope' at accessPackages[0].assignmentPolicies[0] declares 'users' or 'groups' with no
  'scope'; Invoke-OERStructure infers 'scope' as 'SpecificDirectoryUsers'. Declare 'scope'
  explicitly instead of relying on the inference.`
  **Failure looks like:** an Error instead -- the loaded module predates commit `319cf09`/`9a52334`.
  **Result:**
  ```powershell
> $Frag = @"  
> { "accessPackages": [ { "displayName": "$Package", "catalog": "$Catalog", "resourceRoles": null,  
> "assignmentPolicies": [ { "displayName": "$Policy",  
> "requestorScope": { "users": [ "$SpecificUserA", "$SpecificUserB" ] } } ] } ] }  
> "@  
> $Document = $Frag | ConvertFrom-Json  
> $Document | Add-Member -NotePropertyName 'version' -NotePropertyValue '1.0' -Force  
> $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force  
> $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/ap-scopeless-users.json' -Encoding utf8   
>  
> $V = Test-OERStructure -Path './live/ap-scopeless-users.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].assignmentPolicies[0].requestorScope.scope  
Message : 'requestorScope' at accessPackages[0].assignmentPolicies[0] declares 'users' or 'groups' with no 'scope'; Invoke-OERStructure infers 'scope' as 'SpecificDirectoryUsers'. Declare 'scope' explicitly instead of relying on the inference.  
Severity : Warning  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  

>
  ```

- [x] **2.2 Apply it, and confirm the scope AND the users actually land on the live policy.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize

  $ScopedPol = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $ScopedPol.AllowedTargetScope
  $ScopedPol.RequestorScope | Format-List *
  ```

  **Expect:** `Updated`, naming `requestorScope`. `AllowedTargetScope` reads
  `SpecificDirectoryUsers` (not `allMemberUsers`), and `RequestorScope.users` (or the equivalent
  Graph-resolved ids) names BOTH `$SpecificUserA` and `$SpecificUserB`.
  **Failure looks like:** `AllowedTargetScope` is `allMemberUsers` with an empty user list -- the
  pre-fix behaviour reaching the tenant, discarding the declared users exactly as issue #69
  describes.

  Cross-check in the portal: **Access packages > `<your-test-access-package>` > Policies >
  `<your-test-policy>` > Edit > Requests** -- "Users who can request access" must show
  `$SpecificUserA` and `$SpecificUserB` by name, not "All members".
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requestorScope)  
  
>  
> $ScopedPol = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $ScopedPol.AllowedTargetScope  
specificDirectoryUsers  
> $ScopedPol.RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000005, 00000000-0000-0000-0000-000000000006}  
groups : {}  
  
>
  ```

- [x] **2.3 Second apply, byte-identical document -- convergence.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged`. **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>
  ```

- [x] **2.4 An explicit scope still wins over inference.** Apply a document declaring a
  `SpecificConnectedOrganizationUsers` scope (or any non-`SpecificDirectoryUsers` value your
  tenant's entitlement configuration allows) together with a non-empty `users` list. -- 2026-09-06

  **Expect:** offline validation reports a Warning at `...requestorScope.scope` reading, in full:
  `'requestorScope' at ... declares 'users' or 'groups' with 'scope' set to
  '<the-declared-scope>'; they are applied only when 'scope' is 'SpecificDirectoryUsers' and are
  otherwise ignored.` The apply reports `Updated`/`Unchanged` with the LIVE policy's
  `AllowedTargetScope` reading the DECLARED scope, not `SpecificDirectoryUsers`, and the declared
  `users` never appear on the live policy -- the explicit scope wins over inference, and the
  users are silently unused exactly as the Warning says.
  **Failure looks like:** the live policy ends up `SpecificDirectoryUsers` with the declared users
  applied anyway -- inference overriding an explicit scope, which #69's fix must never do.
  Skip and mark "not applicable" if your tenant does not support a second requestor-scope kind to
  demonstrate this with.

  On this tenant "For users not in your directory" is greyed out in the portal (no connected
  organizations), so `SpecificConnectedOrganizationUsers` is not available. `AllDirectoryUsers`
  ("All users (including guests)") is, and it is NOT the `AllMemberUsers` default, so section 5 can
  still tell a reset apart afterwards. The last step puts the scope back to what 2.2 left
  (`SpecificDirectoryUsers` with A and B), which is the state 5.2 and 13.6 compare against.

  ```powershell
  $Frag = @"
  { "accessPackages": [ { "displayName": "$Package", "catalog": "$Catalog", "resourceRoles": null,
    "assignmentPolicies": [ { "displayName": "$Policy",
      "requestorScope": { "scope": "AllDirectoryUsers", "users": [ "$SpecificUserA", "$SpecificUserB" ] } } ] } ] }
  "@
  $Document = $Frag | ConvertFrom-Json
  $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
  $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/ap-explicit-scope-users.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/ap-explicit-scope-users.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity      # Warning: '...scope set to AllDirectoryUsers; ... otherwise ignored.'

  Invoke-OERStructure -Path './live/ap-explicit-scope-users.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize            # Updated (requestorScope)

  $ExplicitPol = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $ExplicitPol.AllowedTargetScope                                     # expect allDirectoryUsers -- the DECLARED scope
  $ExplicitPol.RequestorScope | Format-List *                         # expect users: {} -- the declared users never landed

  # Convergence on the explicit form, then put the scope back to 2.2's state for sections 3-13.
  Invoke-OERStructure -Path './live/ap-explicit-scope-users.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize            # Unchanged
  Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize            # Updated (requestorScope) -- back to SpecificDirectoryUsers + A/B
  (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List *
  ```

  **Result:**
  ```powershell
> $Frag = @"  
> { "accessPackages": [ { "displayName": "$Package", "catalog": "$Catalog", "resourceRoles": null,  
> "assignmentPolicies": [ { "displayName": "$Policy",  
> "requestorScope": { "scope": "AllDirectoryUsers", "users": [ "$SpecificUserA", "$SpecificUserB" ] } } ] } ] }  
> "@  
> $Document = $Frag | ConvertFrom-Json  
> $Document | Add-Member -NotePropertyName 'version' -NotePropertyValue '1.0' -Force  
> $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force  
> $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/ap-explicit-scope-users.json' -Encoding utf8  
>  
> $V = Test-OERStructure -Path './live/ap-explicit-scope-users.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity # Warning: '...scope set to AllDirectoryUsers; ... otherwise ignored.'  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].assignmentPolicies[0].requestorScope.scope  
Message : 'requestorScope' at accessPackages[0].assignmentPolicies[0] declares 'users' or 'groups' with 'scope' set to 'AllDirectoryUsers'; they are applied only when 'scope' is 'SpecificDirectoryUsers' and are otherwise ignored.  
Severity : Warning  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>  
> Invoke-OERStructure -Path './live/ap-explicit-scope-users.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize # Updated (requestorScope)  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requestorScope)  
  
>  
> $ExplicitPol = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $ExplicitPol.AllowedTargetScope # expect allDirectoryUsers -- the DECLARED scope  
allDirectoryUsers  
> $ExplicitPol.RequestorScope | Format-List * # expect users: {} -- the declared users never landed  
  
scope : AllDirectoryUsers  
users : {}  
groups : {}  
  
>  
> # Convergence on the explicit form, then put the scope back to 2.2's state for sections 3-13.  
> Invoke-OERStructure -Path './live/ap-explicit-scope-users.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize # Unchanged  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
> Invoke-OERStructure -Path './live/ap-scopeless-users.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize # Updated (requestorScope) -- back to SpecificDirectoryUsers + A/B  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requestorScope)  
  
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000005, 00000000-0000-0000-0000-000000000006}  
groups : {}  
  
>
  ```

---

### 3. The convergence proof -- a declared-empty `approvalStages` clears the stages and settles

Depends on section 1's baseline. (Absorbed from the old file's section 2; re-verified accurate --
see "What this file absorbs" above.)

- [x] **3.1 Save the clear-stages document and validate it offline.** -- 2026-09-06

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
          { "displayName": "<your-test-policy>", "approvalStages": [] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-clear-stages.json`. This document deliberately does not declare
  `requestorScope`, `requestorSettings`, `description`, `requireApproval`,
  `requireRequestorJustification`, `requireApprovalForUpdate`, any expiration key, or
  `notificationsDisabled` -- section 5 is about exactly those.


  ```powershell
  $Frag = @"
  { "accessPackages": [ { "displayName": "$Package", "catalog": "$Catalog", "resourceRoles": null,
    "assignmentPolicies": [ { "displayName": "$Policy", "approvalStages": [] } ] } ] }
  "@
  $Document = $Frag | ConvertFrom-Json
  $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
  $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/ap-clear-stages.json' -Encoding utf8
  Get-Content './live/ap-clear-stages.json'

  $V = Test-OERStructure -Path './live/ap-clear-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid` is `$true` and TWO Warnings -- the catalog one, and a
  `accessPackages[0].assignmentPolicies[0].approvalStages` one saying that emptying the stage list
  without also declaring `requireApproval` false AND `requireApprovalForUpdate` false is refused by
  Graph while approval is still required for either. That second Warning is this document's own
  predicted outcome, made offline; do not read it as a validation failure. The self-contradiction
  Warning must NOT fire -- that one needs a declared `requireApproval` true beside the empty stage
  list, and this document never declares `requireApproval` at all.
  **Result:**
  ```powershell
> $V = Test-OERStructure -Path './live/ap-clear-stages.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>
  ```

- [x] **3.2 First apply -- the headline write. RECORDS U1.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Unknown (Graph side) -- U1.** Nobody has yet observed Microsoft Graph accepting a `PUT` of an
  assignment policy whose `requestApprovalSettings.stages` is `[]`.

  **Expect:** we do not know, and that is the point of this check -- either `Updated` with Detail
  `updated assignmentPolicy '<your-test-policy>' (approvalStages)` (Graph accepts the empty
  array) or `Failed` with the Graph message (it does not) is an acceptable, informative result.
  Record the Action and the full Detail text verbatim, whichever it is, and treat `Failed` as a
  finding to write up, not as a defect in this checklist.
  **Failure looks like:** `Failed` with Detail matching `NothingToUpdate` -- the loaded module
  predates commit `99e787b`.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
>
  ```

- [x] **3.3 Second apply, byte-identical document -- the convergence proof.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** conditional on check 3.2, exactly as 4.1 and 9.1 are -- if 3.2 recorded `Updated`,
  `Unchanged` with Detail `assignmentPolicy '<your-test-policy>' matches`, NOT another `Updated`;
  if 3.2 recorded `Failed`, `Failed` again with the identical `InvalidApprovalStages` Detail. A
  document Graph refuses that keeps saying so, identically, is the correct behaviour -- the write
  never landed, so there is nothing for the diff to find settled.
  **Failure looks like:** `Updated` again after an `Updated` 3.2, or an Action that ALTERNATES
  between runs -- run a third and fourth time to tell "write not landing" from "diff disagrees with
  itself" apart, per the old checklist's own guidance. `Updated` forever is the issue #56
  non-convergence class.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-clear-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
>
  ```

- [x] **3.4 Third apply, to rule out an alternating pattern.** -- 2026-09-06

  **Expect:** the same Action as 3.3, identically -- `Unchanged` again if 3.2 wrote, `Failed` again
  with the identical Detail if 3.2 was refused. An Action that differs from 3.3 is the finding.
  **Result:**
Same

---

### 4. Read-back -- the stages are gone and the derived flag followed

(Absorbed, old section 3.)

- [x] **4.1 Read the policy back through the module.** -- 2026-09-06

  ```powershell
  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($After.ApprovalStages).Count
  $After | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate
  ```

  **Expect: conditional on check 3.2, exactly as 8.3 is.** **Corrected 2026-09-06 (post-run F3):**
  the original Expect ("stage count `0`, `RequireApproval` `$false`") assumed the section 3 write had
  landed. It did not -- Graph refused every PUT with `InvalidApprovalStages` (3.2, 3.3, 3.4). So:
  if 3.2 recorded `Updated`, expect stage count `0` and `RequireApproval` `$false` (derived from the
  declared stage count, since `-RequireApproval` was never bound). **If 3.2 recorded `Failed`, expect
  the check 1.4 state unchanged** -- one stage, `RequireApproval` `$true` -- proving nothing partial
  was written before the refusal. Either way `RequireRequestorJustification` and
  `RequireApprovalForUpdate` are unchanged from check 1.4. Anything else -- stages cleared alongside a
  `Failed` record, or flags moved with the stages intact -- is a partial write and a finding.
  **Result:**
  ```powershell
> $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($After.ApprovalStages).Count  
1  
> $After | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate  
  
RequireApproval RequireRequestorJustification RequireApprovalForUpdate  
--------------- ----------------------------- ------------------------  
True True True  
>
  ```

- [x] **4.2 Confirm the same thing in the portal, independent of the module's own converter.** -- 2026-09-06

  Open **... Policies > `<your-test-policy>` > Edit > Requests > Approval**.
  **Expect: conditional on check 3.2.** **Corrected 2026-09-06 (post-run F3):** if 3.2 recorded
  `Updated`, "If requestors must be approved" reads No with no approver stage listed. **If 3.2
  recorded `Failed`, it still reads Yes with the check 1.4 stage** -- the portal must agree with 4.1,
  and both must show the write did not land. The original unconditional "reads No" assumed a write
  Graph refused.
  **Result:**
  ```powershell
REquire approval YES
# Post-run note: consistent with 4.1. Section 3 never wrote anything (Graph refused every PUT with
# InvalidApprovalStages, see 3.2), so the live policy is still the 1.4 state: Require approval = Yes,
# one stage (oer-dv-approver). The Expect ("reads No") assumed the write had landed; it did not.
  ```

---

### 5. The composite-field hazard -- RECORDS U2

(Absorbed, old section 4. Unresolved and unaddressed this sprint -- `ConvertTo-OERPolicyBody.ps1`
was not touched.)

**This is unknown.** Each check below still carries an explicit `Expect:` line, per the house rule
-- but for a genuinely unresolved question the honest expectation IS "we do not know", stated as
such, not a predicted value. Record the comparison verbatim regardless of which way it comes out.

> **Corrected 2026-09-06 (post-run F3). Read this before running section 5.** Every check here is
> written as if section 3 had cleared the stages. **It did not** -- Graph refused all three PUTs
> (3.2, 3.3, 3.4) with `InvalidApprovalStages`, so no write from section 3 ever reached the policy.
> Run against a `Failed` section 3, these checks compare a policy that NOTHING touched, and the only
> difference they can show is section 2's intentional requestor-scope change. **They therefore do
> NOT answer U2 on their own.** The real U2 evidence on this run came from the PUTs that DID
> succeed -- 6.4, 7.1, 7.2, 7.4 and 9.2 -- after which the stages, requestor scope, questions and
> reviewSettings all survived (13.5). Treat section 5 as a "no unrelated field moved" regression
> against whatever section 3 actually did, and read the U2 answer off those checks instead.

- [x] **5.1 Diff every field the section 3 document never declared.** -- 2026-09-06

  ```powershell
  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $After | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-after.json' -Encoding utf8

  $BeforeSib = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $SiblingFields | ConvertTo-Json -Depth 10
  $AfterSib  = $After | Select-Object $SiblingFields | ConvertTo-Json -Depth 10
  "identical: $($BeforeSib -eq $AfterSib)"
  Compare-Object -ReferenceObject ($BeforeSib -split "`n") -DifferenceObject ($AfterSib -split "`n")
  ```

  **Expect:** we do not know -- U2 exists to discover whether Graph carries every never-declared
  sibling field forward unchanged. `identical: True` with no `Compare-Object` output is one
  legitimate outcome; `identical: False` naming specific fields is another and is itself the PR-5
  hazard reproducing live, not a failure of this check.
  **Record:** the `identical:` line and every `Compare-Object` line if `False`.
  **Result:**
  ```powershell
> $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $After | Select-Object $AllFields | ConvertTo-Json -Depth 10 | Set-Content -Path './live/policy-after.json' -Encoding utf8  
>   
> $BeforeSib = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $SiblingFields | ConvertTo-Json -Depth 10  
> $AfterSib = $After | Select-Object $SiblingFields | ConvertTo-Json -Depth 10  
> "identical: $($BeforeSib -eq $AfterSib)"  
identical: False  
> Compare-Object -ReferenceObject ($BeforeSib -split "`n") -DifferenceObject ($AfterSib -split "`n")  
  
InputObject SideIndicator  
----------- -------------  
"00000000-0000-0000-0000-000000000005",... =>  
"00000000-0000-0000-0000-000000000006"... =>  
"00000000-0000-0000-0000-000000000004"... <=  
  
>
  ```

- [x] **5.2 Requestor scope specifically.** -- 2026-09-06

  ```powershell
  $BeforeObj = Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json
  '{0} -> {1}' -f $BeforeObj.AllowedTargetScope, $After.AllowedTargetScope
  $BeforeObj.RequestorScope | Format-List *
  $After.RequestorScope     | Format-List *
  ```

  **Expect:** we do not know -- same reasoning as 5.1, narrowed to the one field PR-5 was
  originally about. A `Before -> After` arrow showing no change is one legitimate outcome; an arrow
  showing `allMemberUsers` replacing a specific scope is the hazard, not a failure of this check.
  **Record:** both sides of the arrow and both `RequestorScope` blocks in full.
  **Result:**
  ```powershell
> $BeforeObj = Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json  
> '{0} -> {1}' -f $BeforeObj.AllowedTargetScope, $After.AllowedTargetScope  
specificDirectoryUsers -> specificDirectoryUsers  
> $BeforeObj.RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
  
> $After.RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000005, 00000000-0000-0000-0000-000000000006}  
groups : {}  
  
>
  ```

- [x] **5.3 The two sibling approval flags.** -- 2026-09-06

  ```powershell
  '{0} -> {1}' -f $BeforeObj.RequireRequestorJustification, $After.RequireRequestorJustification
  '{0} -> {1}' -f $BeforeObj.RequireApprovalForUpdate,      $After.RequireApprovalForUpdate
  ```

  **Expect:** we do not know -- same reasoning as 5.1/5.2. Both arrows showing no change is one
  legitimate outcome; either flipping is the hazard.
  **Record:** both arrows, cross-checked in the portal.
  **Result:**
  ```powershell
> '{0} -> {1}' -f $BeforeObj.RequireRequestorJustification, $After.RequireRequestorJustification  
True -> True  
> '{0} -> {1}' -f $BeforeObj.RequireApprovalForUpdate, $After.RequireApprovalForUpdate  
True -> True  
>
  ```

- [x] **5.4 `reviewSettings` -- portal only.** -- 2026-09-06

  Open **... Policies > `<your-test-policy>` > Edit > Lifecycle** and read "Require access review".
  **Expect:** we do not know -- no `Get-OER*` read in this module projects `reviewSettings` at all,
  so the portal is the only way to answer whether check 1.5's configuration survived a PUT that
  never mentioned it.
  **Record:** whether check 1.5's configuration survived, field by field.

  *Record (2026-09-06): SURVIVED, field by field identical to check 1.5's capture. Lifecycle tab
  after the section 3 PUT (the one that cleared the stages and never mentioned `reviewSettings`):
  Require access reviews **checked**; Starting on **9/7/2026**; Review frequency **Quarterly**;
  Duration **21** days; Reviewers **Specific reviewer(s)** = `oer-dv-approver`; advanced: If
  reviewers don't respond **No change**, Show reviewer decision helpers **Yes**, Require reviewer
  justification **Yes**, Reminders **checked**. Nothing moved. The same Lifecycle blade also shows
  the two expiration/extension fields still at their Setup values -- Assignments expire after
  **90** days (Number of days), Users can request specific timeline **No**, Allow users to extend
  access **Yes**, Require approval to grant extension **Yes** -- which is 5.1's `DurationInDays`,
  `RequestorSettings.allowCustomSchedule/allowSelfExtend` and `RequireApprovalForUpdate` confirmed
  through the portal as well as through the module.*
  **Result:**
  ```powershell
  # Portal-only field; no console output. Read from Edit policy > Lifecycle, 2026-09-06, after section 3.
  # Every value matches check 1.5:
  #   Require access reviews = checked | Starting on = 9/7/2026 | Review frequency = Quarterly | Duration = 21 days
  #   Reviewers = Specific reviewer(s): oer-dv-approver
  #   If reviewers don't respond = No change | Show reviewer decision helpers = Yes | Require reviewer justification = Yes | Reminders = checked
  # Also on the same blade (5.1 siblings): expire after 90 days | specific timeline = No | extend access = Yes | approval to extend = Yes
  ```

- [x] **5.5 `questions` -- portal only.** -- 2026-09-06

  Open **... Requestor information** tab.
  **Expect:** we do not know -- same reasoning as 5.4, for the custom questions instead of the
  access review configuration.
  **Record:** whether every custom question from check 1.5 is still present.

  *Record (2026-09-06): PRESENT, unchanged. Requestor information > Questions after the section 3
  PUT still lists exactly the one question from check 1.5: text `oer-dv: why do you need this
  access? (setup question, section 1.5 / 5.5)`, answer format **Long text**, no localization, no
  multiple-choice options, no regex pattern, **Required** (checked). No question was added, lost
  or reset; the second row is the portal's empty "Enter question" placeholder, not a question.
  Attributes tab not in scope (Setup added none).*
  **Result:**
  ```powershell
  # Portal-only field; no console output. Read from Edit policy > Requestor information > Questions, 2026-09-06, after section 3.
  # Matches check 1.5 exactly:
  #   1 question | "oer-dv: why do you need this access? (setup question, section 1.5 / 5.5)" | Long text | no localization | no regex | Required = checked
  ```

---

### 6. Regression -- an OMITTED `approvalStages` still leaves the live stages alone

(Absorbed, old section 5.)

- [x] **6.1 Restore a stage by applying the baseline document.** -- 2026-09-06

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
              { "durationDays": 14, "users": [ "<approver-upn>" ],
                "requireApproverJustification": true, "approverInfoVisibility": "Default" }
            ]
          }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-baseline-stages.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        {
          "displayName": "oer-dv-policy",
          "approvalStages": [
            { "durationDays": 14, "users": [ "person1@example.com" ],
              "requireApproverJustification": true, "approverInfoVisibility": "Default" }
          ]
        }
      ]
    }
  ]
}
  '@ | Set-Content -Path './live/ap-baseline-stages.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-baseline-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect: conditional on check 3.2.** **Corrected 2026-09-06 (post-run F9):** `Valid = True` with
  only the catalog Warning either way. If 3.2 cleared the stages, this restores one and reports
  `Updated` naming `approvalStages`. **If 3.2 recorded `Failed`, the stage was never gone, so this
  document already matches the live policy and correctly reports `Unchanged`** -- that is the right
  answer, not a missed write. Check 6.2 confirms the stage is live either way, which is what section
  6 actually needs.
  **Failure looks like:** `Failed` with `UserNotFound` -- `<approver-upn>` does not resolve.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> {  
> "displayName": "oer-dv-policy",  
> "approvalStages": [  
> { "durationDays": 14, "users": [ "person1@example.com" ],  
> "requireApproverJustification": true, "approverInfoVisibility": "Default" }  
> ]  
> }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-baseline-stages.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-baseline-stages.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
> Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>
  ```

- [x] **6.2 Confirm the stage is live again, and capture the exact stage state.** -- 2026-09-06

  ```powershell
  $Restored = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($Restored.ApprovalStages).Count
  $Restored.ApprovalStages | Format-List *
  $Restored | Select-Object RequireApproval
  ```

  **Expect:** one stage, `durationDays` 14, `users` holding `<approver-upn>`'s object id,
  `requireApproverJustification` `True`, `RequireApproval` `$true`.
  **Result:**
  ```powershell
> $Restored = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($Restored.ApprovalStages).Count  
1  
> $Restored.ApprovalStages | Format-List *  
  
durationDays : 14  
manager : False  
managerLevel : 1  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
internalSponsor : False  
externalSponsor : False  
alternateUsers : {}  
alternateGroups : {}  
fallbackUsers : {}  
fallbackGroups : {}  
escalationDays :  
requireApproverJustification : True  
approverInfoVisibility : Default  
   
> $Restored | Select-Object RequireApproval  
  
RequireApproval  
---------------  
True  
  
>
  ```

- [x] **6.3 Save the omitted-key document and validate it offline.** -- 2026-09-06

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
          { "displayName": "<your-test-policy>",
            "description": "declared-value-family regression check -- approvalStages omitted" }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-omit-stages.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy",
          "description": "declared-value-family regression check -- approvalStages omitted" }
      ]
    }
  ]
}
  '@ | Set-Content -Path './live/ap-omit-stages.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-omit-stages.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True`, only the catalog Warning.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "description": "declared-value-family regression check -- approvalStages omitted" }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-omit-stages.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-omit-stages.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  

>
  ```

- [x] **6.4 Apply it -- the stages must survive.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-omit-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize

  $AfterOmit = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($AfterOmit.ApprovalStages).Count
  $AfterOmit | Select-Object Description, RequireApproval
  Compare-Object -ReferenceObject (@($Restored.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress) `
                 -DifferenceObject (@($AfterOmit.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress)
  ```

  **Expect:** `Updated` naming `description` and NOT `approvalStages`. Stage count still `1`,
  `RequireApproval` still `$true`, `Compare-Object` prints nothing.
  **Failure looks like:** stage count `0` -- the fix over-reaching; treat as a blocker.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-omit-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (description)  
  
>  
> $AfterOmit = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($AfterOmit.ApprovalStages).Count  
1  
> $AfterOmit | Select-Object Description, RequireApproval  
  
Description RequireApproval  
----------- ---------------  
declared-value-family regression check -- approvalStages omitted True  
  
> Compare-Object -ReferenceObject (@($Restored.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress) `  
> -DifferenceObject (@($AfterOmit.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress)  
>
  ```

- [x] **6.5 Apply the omitted-key document again -- convergence.** -- 2026-09-06

  **Expect:** `Unchanged`. **Result:**
```powershell
> Invoke-OERStructure -Path './live/ap-omit-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>  
> $AfterOmit = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($AfterOmit.ApprovalStages).Count  
1  
> $AfterOmit | Select-Object Description, RequireApproval  
  
Description RequireApproval  
----------- ---------------  
declared-value-family regression check -- approvalStages omitted True  
  
> Compare-Object -ReferenceObject (@($Restored.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress) `  
> -DifferenceObject (@($AfterOmit.ApprovalStages) | ConvertTo-Json -Depth 10 -Compress)  
>
```

---

### 7. Approval-stage `alternateUsers` overwrite guard -- issue #68

The live state going in has one stage (check 6.4 left it there).

- [x] **7.1 A document declaring `users: []` with its own `alternateUsers` keeps the DOCUMENT'S
  value, not the Tenant Profile default.** -- 2026-09-06

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
          { "displayName": "<your-test-policy>",
            "approvalStages": [
              { "durationDays": 14, "users": [], "alternateUsers": [ "<document-escalation-upn>" ] }
            ] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-alternateusers-declared.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy",
          "approvalStages": [
            { "durationDays": 14, "users": [], "alternateUsers": [ "person2@example.com" ] }
          ] }
      ]
    }
  ]
}
  '@ | Set-Content -Path './live/ap-alternateusers-declared.json' -Encoding utf8
  ```

  ```powershell
  Invoke-OERStructure -Path './live/ap-alternateusers-declared.json' -Include AccessPackages -Confirm:$false -WarningVariable W68a |
      Format-Table Section, Item, Action, Detail -AutoSize
  $W68a

  $PolAfter68a = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $PolAfter68a.ApprovalStages[0] | Select-Object Users, AlternateUsers
  ```

  **Expect:** `Updated`. A Write-Warning fires (the `users: []` stage has no explicit primary
  approver, so the back-compat `PrimaryApprovers` substitution still runs for `Users` -- that part
  is unaffected by #68); its text begins `Sync-OERStructureAccessPackage: assignmentPolicy
  '<your-test-policy>' stage 1 declared approver keys (users/groups/manager/internalSponsor/
  externalSponsor) that are all empty; substituting Tenant Profile ...`. On the LIVE policy,
  `AlternateUsers` resolves to `<document-escalation-upn>`'s object id, NOT
  `<profile-escalation-upn>`'s.
  **Failure looks like:** `AlternateUsers` resolves to `<profile-escalation-upn>` instead -- the
  pre-#68 overwrite reaching the tenant.

  Cross-check in the portal: **... Policies > `<your-test-policy>` > Edit > Requests > Approval** --
  the escalation approver named there must be `<document-escalation-upn>`.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "approvalStages": [  
> { "durationDays": 14, "users": [], "alternateUsers": [ "person2@example.com" ] }  
> ] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-alternateusers-declared.json' -Encoding utf8  
> Invoke-OERStructure -Path './live/ap-alternateusers-declared.json' -Include AccessPackages -Confirm:$false -WarningVariable W68a |  
> Format-Table Section, Item, Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) instead of the zero-approver stage the document tried to express.
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
   
> $W68a  
Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) instead of the zero-approver stage the document tried to express.  
>  
> $PolAfter68a = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $PolAfter68a.ApprovalStages[0] | Select-Object Users, AlternateUsers  
  
users alternateUsers  
----- --------------  
{00000000-0000-0000-0000-000000000004} {00000000-0000-0000-0000-000000000007}  
  
>
  ```

- [x] **7.2 A document declaring NO approver keys at all still gets the profile defaults
  (back-compat fallback still works).** -- 2026-09-06

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
          { "displayName": "<your-test-policy>",
            "approvalStages": [ { "durationDays": 14 } ] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-alternateusers-omitted.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy",
          "approvalStages": [ { "durationDays": 14 } ] }
      ]
    }
  ]
}
  '@ | Set-Content -Path './live/ap-alternateusers-omitted.json' -Encoding utf8
  ```

  ```powershell
  Invoke-OERStructure -Path './live/ap-alternateusers-omitted.json' -Include AccessPackages -Confirm:$false -WarningVariable W68b |
      Format-Table Section, Item, Action, Detail -AutoSize
  $W68b

  $PolAfter68b = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $PolAfter68b.ApprovalStages[0] | Select-Object Users, AlternateUsers
  ```

  **Expect:** `Updated`. The Warning text begins `... stage 1 declared no approver keys at all;
  substituting Tenant Profile ... (back-compat).` `Users` resolves to `<approver-upn>`
  (`PrimaryApprovers` default) and `AlternateUsers` resolves to `<profile-escalation-upn>`
  (`EscalationApprovers` default) -- this time correctly, since NOTHING was declared to override it.
  **Failure looks like:** the fallback stops working entirely (`Failed` with "no manager, no
  explicit approvers, and no Tenant Profile PrimaryApprovers default") -- the profile Setup step
  above was not applied, or #68's gate over-corrected.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "approvalStages": [ { "durationDays": 14 } ] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-alternateusers-omitted.json' -Encoding utf8  
> Invoke-OERStructure -Path './live/ap-alternateusers-omitted.json' -Include AccessPackages -Confirm:$false -WarningVariable W68b |  
> Format-Table Section, Item, Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared no approver keys at all; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) (back-compat).  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
   
> $W68b  
Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared no approver keys at all; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) (back-compat).  
>  
> $PolAfter68b = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $PolAfter68b.ApprovalStages[0] | Select-Object Users, AlternateUsers  
  
users alternateUsers  
----- --------------  
{00000000-0000-0000-0000-000000000004} {00000000-0000-0000-0000-000000000008}  
  
>
  ```

- [x] **7.3 A stage omitting `durationDays` reports the WHOLE policy `Failed`, not a silent
  `P0D`.** Closes #70 site 3, shipped in the same commit as #68. -- 2026-09-06

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
          { "displayName": "<your-test-policy>",
            "approvalStages": [ { "users": [ "<approver-upn>" ] } ] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-durationdays-omitted.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy",
          "approvalStages": [ { "users": [ "person1@example.com" ] } ] }
      ]
    }
  ]
}
  '@ | Set-Content -Path './live/ap-durationdays-omitted.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-durationdays-omitted.json'
  $V.Valid
  $V.Errors | Where-Object Path -like '*durationDays' | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/ap-durationdays-omitted.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect (offline):** `Valid = True` with a Warning at `...approvalStages[0].durationDays` whose
  Message begins `'durationDays' is not declared at ...; the applied value defaults to 0, and
  New-OERAccessPackageApprovalStage requires at least 1 -- applying this document fails to create
  or update this assignmentPolicy (reported Failed) ...`.
  **Expect (apply):** `Failed`, with Detail matching `failed to build assignmentPolicy
  '<your-test-policy>': Cannot validate argument on parameter 'Days'...` (or the equivalent
  `ValidateRange` message on this PowerShell version). The policy's live state is left untouched by
  this failed apply -- confirm with a read-back.
  **Failure looks like:** the apply succeeds and the live stage ends up with a `durationDays` of 0
  or `P0D` -- the Warning's claimed outcome would then be wrong, which is a finding in its own
  right (the warning's text and the actual outcome would need to be reconciled).
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "approvalStages": [ { "users": [ "person1@example.com" ] } ] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-durationdays-omitted.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-durationdays-omitted.json'  
> $V.Valid  
True  
> $V.Errors | Where-Object Path -like '*durationDays' | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].assignmentPolicies[0].approvalStages[0].durationDays  
Message :'durationDays' is not declared at accessPackages[0].assignmentPolicies[0].approvalStages[0]; the applied value defaults to 0, and New-OERAccessPackageApprovalStage requires at least 1 -- applying this document fails to create or update this assignmentPolicy  
(reported Failed) instead of silently taking effect. Declare 'durationDays' explicitly.  
Severity : Warning  
  
>  
> Invoke-OERStructure -Path './live/ap-durationdays-omitted.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: Cannot validate argument on parameter 'Days'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap failed to build assignmentPolicy 'oer-dv-policy': Cannot validate argument on parameter 'Days'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the comman...  
  
>
  ```

- [x] **7.4 Restore a normal stage before moving on**, so section 8's contradiction test starts
  from a known one-stage state: -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  **Expect:** `Updated`, stage count `1`. **Result:**
```powershell
> Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
  
> @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count  
1  
>
```

---

### 8. The self-contradictory document -- RECORDS U4

(Absorbed, old section 6. Message text confirmed byte-identical to current source.)

- [x] **8.1 Save the contradictory document and confirm the Warning fires without blocking.** -- 2026-09-06

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
          { "displayName": "<your-test-policy>", "requireApproval": true, "approvalStages": [] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-contradiction.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy", "requireApproval": true, "approvalStages": [] }
      ]
    }
  ]
}
'@ | Set-Content -Path './live/ap-contradiction.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-contradiction.json'
  $V.Valid
  $V.Errors | Where-Object Severity -eq 'Warning' | Format-List Section, Item, Path, Message
  ```

  **Expect:** `Valid` is `$true`, and a Warning at `accessPackages[0].assignmentPolicies[0].approvalStages`.

  **Message text CORRECTED 2026-09-06 (post-run F2) -- the text below is what the run recorded, and
  it is wrong.** The old wording claimed the policy "is written with approval required and no
  approver stages at all and no request can ever be approved". Check 8.2 proved otherwise: Graph
  REFUSES the write, so that dead policy cannot exist and the claim describes a state the tenant
  never reaches. The current build says instead, in full:
  `'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is
  declared as an empty array; Microsoft Graph refuses the write with 'InvalidApprovalStages: If
  approval is required, a valid list of stages must be provided.', so the assignment policy is
  reported Failed and left completely unchanged -- the document never converges and reports Failed on
  every run. Add at least one entry to 'approvalStages', or set 'requireApproval' to false.`
  Check 14.4 re-runs this against the corrected build.

  *The old text, for the record, since the Result block below quotes it:* `... requireApproval takes
  precedence over the stage count, so the policy is written with approval required and no approver
  stages at all and no request can ever be approved. Add at least one entry to 'approvalStages', or
  set 'requireApproval' to false.`
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "requireApproval": true, "approvalStages": [] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-contradiction.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-contradiction.json'  
> $V.Valid  
True   
> $V.Errors | Where-Object Severity -eq 'Warning' | Format-List Section, Item, Path, Message  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].assignmentPolicies[0].approvalStages  
Message : 'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is declared as an empty array; requireApproval takes precedence over the stage count, so the policy is written with approval required and no approver stages at all and  
no request can ever be approved. Add at least one entry to 'approvalStages', or set 'requireApproval' to false. 
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
  
>
  ```

- [x] **8.2 Apply it. Do NOT predict the outcome -- record it. This is U4.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false -ErrorVariable ContradictionErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $ContradictionErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect:** we do not know -- this is U4 itself. Either `Updated` (Graph accepted the dead
  policy) or `Failed` (it did not) is an acceptable, informative result; do not predict which
  before running it.
  **Record:** the Action verbatim, the full Detail, and every `$ContradictionErr` line.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false -ErrorVariable ContradictionErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
> $ContradictionErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
InvalidApprovalStages,Set-OERAccessPackageAssignmentPolicy  
InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
InvalidApprovalStages,Invoke-OERStructure  
InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
>  
>
  ```

- [x] **8.3 Read the resulting live state back.** -- 2026-09-06

  ```powershell
  $AfterContradiction = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($AfterContradiction.ApprovalStages).Count
  $AfterContradiction | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate
  ```

  **Expect:** conditional on check 8.2 -- if 8.2 recorded `Updated`, stage count `0` with
  `RequireApproval` `$true` (the dead policy); if 8.2 recorded `Failed`, this should be identical to
  check 7.4's state (one stage, approval required), proving nothing partial was written before the
  refusal. Anything else -- stages cleared but `RequireApproval` false, or stages cleared alongside
  a `Failed` record -- is a partial write and a finding in its own right.
  **Record:** stage count and `RequireApproval`, cross-checked in the portal.
  **Result:**
  ```powershell
> $AfterContradiction = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($AfterContradiction.ApprovalStages).Count  
1  
> $AfterContradiction | Select-Object RequireApproval, RequireRequestorJustification, RequireApprovalForUpdate  
  
RequireApproval RequireRequestorJustification RequireApprovalForUpdate  
--------------- ----------------------------- ------------------------  
True True True  
  
>
  ```

- [x] **8.4 Apply the contradictory document a second time -- does it converge?** -- 2026-09-06

  **Expect:** the SAME Action check 8.2 recorded -- `Unchanged`/`Updated` reported identically both
  times if 8.2 recorded `Updated` (this is the convergence question), or `Failed` again if 8.2
  recorded `Failed` (an unappliable document should keep saying so). `Updated` forever is still a
  non-convergence of the same class as issue #56, even though the document is the operator's own
  fault.
  **Record:** the Action.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "requireApproval": true, "approvalStages": [] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-contradiction.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-contradiction.json'  
> $V.Valid  
True   
> $V.Errors | Where-Object Severity -eq 'Warning' | Format-List Section, Item, Path, Message  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].assignmentPolicies[0].approvalStages  
Message : 'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is declared as an empty array; requireApproval takes precedence over the stage count, so the policy is written with approval required and no approver stages at all and  
no request can ever be approved. Add at least one entry to 'approvalStages', or set 'requireApproval' to false. 
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
  
>
  ```

- [x] **8.5 If 8.2 recorded `Updated`: does the dead policy behave as the Warning claims?** -- 2026-09-06 Optional
  but conclusive -- sign in to https://myaccess.microsoft.com as a user in scope of
  `<your-test-policy>` and try to request `<your-test-access-package>`.
  **Expect:** we do not know -- this is the only direct evidence for the Warning's claim that "no
  request can ever be approved". Either the request cannot be submitted at all, or it can be
  submitted and sits pending with no possible approver -- both would confirm the claim; a request
  that gets approved would contradict it and is itself the finding.
  **Record:** whether the request can be submitted, and whether it sits pending with no possible
  approver. Write "not applicable -- Graph refused the write" if 8.2 recorded `Failed`.
  **Result:**
  ```powershell
# Formally: not applicable -- Graph refused the write in 8.2 (InvalidApprovalStages), so
# the "dead policy" never existed in the tenant and the Warning's claim cannot be tested
# against a live policy. The request flow was exercised anyway as extra evidence for 8.3
# (no partial write): if the refusal had left anything behind, the request would have
# had no approver stage.

# Setup for the test: person3@example.com (prod account) was ADDED to the requestor
# scope of oer-dv-policy in the portal, because oer-dv-approver is the only user Setup put
# in scope and the test users are disabled. The prod account was REMOVED from the scope again
# before section 13 ran. Teardown still owes one thing: the pending request below must be
# cancelled/adminRemoved (assignmentRequests/{id}/cancel or an admin denial) -- see section 14.

# My Access, signed in as person3@example.com:
#   Request oer-dv-ap -> "Requesting for: Yourself" -> Additional questions:
#     setup question 'oer-dv: why do you need this access? (setup question, section 1.5 / 5.5)' = Test1
#     Business justification (required, RequireRequestorJustification=true)             = Test2
#   Submit accepted -- request could be submitted.

# Entra admin center -> Access package oer-dv-ap -> Requests:
#   Requestor            Philip Haglund / person3@example.com
#   Request ID           00000000-0000-0000-0000-000000000009
#   Request type         User requests assignment
#   Submitted            9/6/2026 12:15:49 PM
#   Policy               oer-dv-policy
#   Status / Sub-status  Pending approval / Pending approval
#   Fulfillment errors   0
#   Provided answers     Test1
#   Assigned approvers   First stage: oer-dv-approver
#   Custom extension instances 0

# Conclusion: the request is NOT stuck with "no possible approver" -- it is pending with
# oer-dv-approver assigned in the first stage, i.e. the live policy is exactly the 7.4 /
# 8.3 state (one stage, approval required). Consistent with 8.2 = Failed and 8.3 = no
# partial write. The Warning's dead-policy behaviour could not be observed on this tenant
# because Graph never lets the dead policy be written.
  ```

---

### 9. The `-WhatIf` plan and the create path -- RECORDS U1 (create side)

(Absorbed, old section 7.)

- [x] **9.1 `-WhatIf` must plan the change and write nothing.** -- 2026-09-06

  ```powershell
  $StagesBeforeWhatIf = @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  $StagesBeforeWhatIf

  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize

  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  **Expect: conditional on what the live policy already holds.** **Corrected 2026-09-06 (post-run
  F9):** the point of this check is that `-WhatIf` WRITES NOTHING -- the stage count before and after
  must be identical. The Action depends on whether the document differs from the live policy: a
  `Skipped` record when it does, and `Unchanged` when it does not. After a `Failed` section 3 the
  baseline stage was never removed, so this document already matches and `Unchanged` is correct. The
  original unconditional "a `Skipped` record" assumed a difference that section 3 was supposed to
  have created.
  **Result:**
  ```powershell
> $StagesBeforeWhatIf = @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count  
> $StagesBeforeWhatIf  
1  
>  
> Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>  
> @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count  
1  
>
  ```

- [x] **9.2 Apply the baseline for real, to leave a stage in place for the create check.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  **Expect: conditional, same as 6.1.** **Corrected 2026-09-06 (post-run F9):** stage count `1` is
  the assertion that matters -- section 9's create check needs a known one-stage state. The Action is
  `Updated` if the stage was missing and `Unchanged` if 6.1 already left it in place, which is what a
  `Failed` section 3 produces. **Result:**
  
```powershell
> Invoke-OERStructure -Path './live/ap-baseline-stages.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
> @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count  
1  
>
```

- [x] **9.3 Save the create document and validate it offline.** -- 2026-09-06

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
          { "displayName": "<your-test-policy>" },
          { "displayName": "<your-new-policy>", "approvalStages": [] }
        ]
      }
    ]
  }
  ```

  Save as `./live/ap-create-policy.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-dv-ap",
      "catalog": "OER-DV-CAT",
      "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy" },
        { "displayName": "oer-dv-policy-new", "approvalStages": [] }
      ]
    }
  ]
}
 '@ | Set-Content -Path './live/ap-create-policy.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-create-policy.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True` and TWO Warnings -- the catalog one, and the same clear-stages one as
  in 3.1, here on `accessPackages[0].assignmentPolicies[1].approvalStages`, since the second policy
  also declares an empty `approvalStages` with neither approval flag. It is conservative on this
  document: on a CREATE there is no live policy to carry `requireApprovalForUpdate` forward from,
  so the refusal it predicts need not happen -- 9.5 recorded `Created` and the document applied
  fine. The validator cannot tell a create from an update offline, and the Warning's own closing
  sentence says exactly that.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy" },  
> { "displayName": "oer-dv-policy-new", "approvalStages": [] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-create-policy.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-create-policy.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>
  ```

- [x] **9.4 `-WhatIf` on the create path.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName
  ```

  **Expect:** `Skipped` for the new policy, `Unchanged` for the existing one, no `<your-new-policy>`
  in the read-back.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
What if: Performing the operation "Create assignmentPolicy 'oer-dv-policy-new'" on target "oer-dv-ap".  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
accessPackages oer-dv-ap Skipped would create assignmentPolicy 'oer-dv-policy-new'  
  
> Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName  
  
Id DisplayName  
-- -----------  
00000000-0000-0000-0000-000000000003 oer-dv-policy  
  
>
  ```

- [x] **9.5 Apply for real -- the create path with an empty stage list. Also touches U1.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize

  $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy
  $NewPol | Select-Object Id, DisplayName, AllowedTargetScope, RequireApproval
  @($NewPol.ApprovalStages).Count
  ```

  **Expect (module side, conditional on U1):** `Created` naming `<your-new-policy>` if Graph
  accepts an empty `stages` array on POST, `Failed` if not; `<your-test-policy>` reads `Unchanged`
  either way. If created: `AllowedTargetScope` `allMemberUsers`, `RequireApproval` `$false`, `0`
  stages.

  **Note the id of the created policy -- section 13 deletes it:** `00000000-0000-0000-0000-000000000010` (deleted in 13.1)
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
accessPackages oer-dv-ap Created created assignmentPolicy 'oer-dv-policy-new'  
  
>  
> $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy  
> $NewPol | Select-Object Id, DisplayName, AllowedTargetScope, RequireApproval  
  
Id DisplayName AllowedTargetScope RequireApproval  
-- ----------- ------------------ ---------------  
00000000-0000-0000-0000-000000000010 oer-dv-policy-new allMemberUsers False  
  
> @($NewPol.ApprovalStages).Count  
0  
>
  ```

- [x] **9.6 Re-apply the create document -- convergence on both entries.** -- 2026-09-06

  **Expect:** two `Unchanged` records. **Result:**
```powershell
> Invoke-OERStructure -Path './live/ap-create-policy.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy-new' matches  
  
>  
> $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy  
> $NewPol | Select-Object Id, DisplayName, AllowedTargetScope, RequireApproval  
  
Id DisplayName AllowedTargetScope RequireApproval  
-- ----------- ------------------ ---------------  
00000000-0000-0000-0000-000000000010 oer-dv-policy-new allMemberUsers False  
  
> @($NewPol.ApprovalStages).Count  
0  
>  
>
```

---

### 10. Access reviews -- three independent null-handling checks

Independent of everything else; uses `<your-review-access-package>` / `<your-review-policy>`
(no Lifecycle review configured, so definitions created here are unambiguous). Each subsection uses
its own review name and can run in any order.

#### 10.1 A `recurrence: null` document creates a review and converges -- issue #67

- [x] **10.1.1 Offline: a null recurrence is accepted, not refused.** -- 2026-09-06

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      { "displayName": "<your-onetime-review>", "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>", "recurrence": null,
        "descriptionForAdmins": "issue 67 live check", "descriptionForReviewers": "Please review your own access.",
        "reviewers": [] }
    ]
  }
  ```

  Save as `./live/ar-recurrence-null.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-onetime-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": null,
      "descriptionForAdmins": "issue 67 live check", "descriptionForReviewers": "Please review your own access.",
      "reviewers": [] }
  ]
}
'@ | Set-Content -Path './live/ar-recurrence-null.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-recurrence-null.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True`, no findings at all.
  **Result:**
  ```powershell
>  
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-onetime-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": null,  
> "descriptionForAdmins": "issue 67 live check", "descriptionForReviewers": "Please review your own access.",  
> "reviewers": [] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-recurrence-null.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ar-recurrence-null.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
>
  ```

- [x] **10.1.2 Apply it -- creates a OneTime review, does not fail.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ar-recurrence-null.json' -Include AccessReviews -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessReviewDefinition -DisplayName '<your-onetime-review>' | Select-Object DisplayName, Recurrence
  ```

  **Expect:** `Created` with Detail `created access review '<your-onetime-review>' (recurrence:
  OneTime)`. **Corrected 2026-09-06 (post-run F7):** the read-back's `Recurrence` is the RAW Graph
  object, not the module's cadence word -- `Get-OERAccessReviewDefinition` projects
  `settings.recurrence` verbatim, and `Resolve-OERAccessReviewChange` parses `pattern`/`range` out of
  it, which is why 10.1.3 converges. A OneTime review carries no recurrence pattern at all, so the
  read prints `{[pattern, ], [range, System.Collections.Hashtable]}` with an EMPTY pattern. Assert
  that instead: `(Get-OERAccessReviewDefinition -DisplayName '<your-onetime-review>').Recurrence.pattern.type`
  is null or empty for OneTime (compare 10.2.2's Weekly review, whose `pattern` IS a populated
  hashtable). The original `Expect: Recurrence is OneTime` was never satisfiable and was a checklist
  error, not a module defect.
  **Failure looks like:** `Failed` with Detail `unrecognised recurrence value ''` -- the loaded
  module predates the fix this check proves; `recurrence: null` is being coerced to an empty
  string somewhere upstream of `Test-OERDeclaredProperty`.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ar-recurrence-null.json' -Include AccessReviews -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-onetime-review Created created access review 'oer-dv-onetime-review' (recurrence: OneTime)  
  
> Get-OERAccessReviewDefinition -DisplayName 'oer-dv-onetime-review' | Select-Object DisplayName, Recurrence  
  
DisplayName Recurrence  
----------- ----------  
oer-dv-onetime-review {[pattern, ], [range, System.Collections.Hashtable]}  

>
  ```

- [x] **10.1.3 Second apply, byte-identical document -- THE non-convergence proof issue #67 exists
  to establish.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ar-recurrence-null.json' -Include AccessReviews -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Unchanged`. This is the headline: a document that used to report `Failed` forever
  now creates the review on run 1 and reports `Unchanged` on run 2 -- not `Created`/`Failed`
  alternating, and not a second `Created`.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ar-recurrence-null.json' -Include AccessReviews -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-onetime-review Unchanged access review 'oer-dv-onetime-review' already matches  
  
>
  ```

#### 10.2 A null `startDate`/`endDate` no longer crashes the handler -- issue #70

- [x] **10.2.1 A null `startDate` defaults to today instead of throwing.** -- 2026-09-06

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      { "displayName": "<your-startdate-review>", "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>", "recurrence": "OneTime", "startDate": null,
        "durationInDays": 7,
        "descriptionForAdmins": "issue 70 live check -- null startDate",
        "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
    ]
  }
  ```

  Save as `./live/ar-startdate-null.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-startdate-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": "OneTime", "startDate": null,
      "durationInDays": 7,
      "descriptionForAdmins": "issue 70 live check -- null startDate",
      "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
  ]
}
  '@ | Set-Content -Path './live/ar-startdate-null.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-startdate-null.json'
  $V.Valid
  Invoke-OERStructure -Path './live/ar-startdate-null.json' -Include AccessReviews -Confirm:$false -ErrorVariable StartErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $StartErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect:** `Valid = True`; apply reports `Created` (or `Failed` for an unrelated Graph reason,
  but NOT a PowerShell type-conversion error). `$StartErr` must NOT contain a
  `PSInvalidCastException`/`RuntimeException` naming `[datetime]` or `System.DateTime`.
  **Failure looks like:** the whole `Invoke-OERStructure` call throws a terminating cast error
  instead of producing a `Failed` StructureResult for just this item -- the pre-fix crash. Note that
  this is a STRICTER failure mode than "coerces to 0001-01-01", which the original sprint plan
  assumed and which this checklist deliberately does not test for, since it is not what the code
  actually did before the fix.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-startdate-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": "OneTime", "startDate": null,  
> "durationInDays": 7,  
> "descriptionForAdmins": "issue 70 live check -- null startDate",  
> "descriptionForReviewers": "Please review your own access.", "reviewers": [] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-startdate-null.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ar-startdate-null.json'  
> $V.Valid  
True  
> Invoke-OERStructure -Path './live/ar-startdate-null.json' -Include AccessReviews -Confirm:$false -ErrorVariable StartErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-startdate-review Created created access review 'oer-dv-startdate-review' (recurrence: OneTime)  
  
> $StartErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
>
  ```

- [x] **10.2.2 A null `endDate` with `occurrences` declared falls through to `occurrences`,
  instead of crashing on the same cast.** -- 2026-09-06

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      { "displayName": "<your-enddate-review>", "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>", "recurrence": "Weekly",
        "startDate": "2026-09-14", "endDate": null, "occurrences": 4, "durationInDays": 7,
        "descriptionForAdmins": "issue 70 live check -- null endDate with occurrences",
        "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
    ]
  }
  ```

  Save as `./live/ar-enddate-null.json`. Change `startDate` to a date at least one day in the
  future before running.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-enddate-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",
      "startDate": "2026-09-14", "endDate": null, "occurrences": 4, "durationInDays": 7,
      "descriptionForAdmins": "issue 70 live check -- null endDate with occurrences",
      "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
  ]
}
'@ | Set-Content -Path './live/ar-enddate-null.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-enddate-null.json'
  $V.Valid
  Invoke-OERStructure -Path './live/ar-enddate-null.json' -Include AccessReviews -Confirm:$false -ErrorVariable EndErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $EndErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  Get-OERAccessReviewDefinition -DisplayName '<your-enddate-review>' | Select-Object DisplayName, Recurrence
  ```

  **Expect:** `Valid = True`; apply reports `Created` with a review that recurs 4 times (occurrence
  count), not one carrying an end date. No datetime cast error in `$EndErr`.
  **Failure looks like:** a terminating cast error, or a review created with an end date of
  `0001-01-01`.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-enddate-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",  
> "startDate": "2026-09-14", "endDate": null, "occurrences": 4, "durationInDays": 7,  
> "descriptionForAdmins": "issue 70 live check -- null endDate with occurrences",  
> "descriptionForReviewers": "Please review your own access.", "reviewers": [] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-enddate-null.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ar-enddate-null.json'  
> $V.Valid  
True  
> Invoke-OERStructure -Path './live/ar-enddate-null.json' -Include AccessReviews -Confirm:$false -ErrorVariable EndErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-enddate-review Created created access review 'oer-dv-enddate-review' (recurrence: Weekly)  
  
> $EndErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
> Get-OERAccessReviewDefinition -DisplayName 'oer-dv-enddate-review' | Select-Object DisplayName, Recurrence  
  
DisplayName Recurrence  
----------- ----------  
oer-dv-enddate-review {[pattern, System.Collections.Hashtable], [range, System.Collections.Hashtable]}  

>
  ```

#### 10.3/10.4 Declared-empty `reviewers` -- absorbed from old section 8, RECORDS U3 and U5

Uses `<your-test-review>` / `<your-second-test-review>` -- two more names on the same
`<your-review-access-package>`.

- [x] **10.3.1 Save the self-review document and validate it offline.** Change `startDate` to at
  least one day in the future. -- 2026-09-06

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      { "displayName": "<your-test-review>", "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>", "recurrence": "Weekly",
        "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,
        "descriptionForAdmins": "declared-empty reviewers live check",
        "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
    ]
  }
  ```

  Save as `./live/ar-self-no-fallback.json`.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-test-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",
      "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,
      "descriptionForAdmins": "declared-empty reviewers live check",
      "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
  ]
}
'@ | Set-Content -Path './live/ar-self-no-fallback.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-self-no-fallback.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True`, NO findings at all -- specifically no Warning at
  `accessReviews[0].fallbackReviewers`.
  **Failure looks like:** a Warning reading `A manager reviewer at accessReviews[0] (declared, or
  the default when 'reviewers' is omitted or explicitly null) requires 'fallbackReviewers'; ...` --
  note this is the CURRENT message text (it grew an "or explicitly null" clause and a trailing
  sentence since PR #66 first wrote this check; if you see it at all here, the declared-empty case
  is being misclassified as the manager-default case, which is the defect either wording would
  describe).
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-test-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",  
> "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,  
> "descriptionForAdmins": "declared-empty reviewers live check",  
> "descriptionForReviewers": "Please review your own access.", "reviewers": [] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-self-no-fallback.json' -Encoding utf8   
> $V = Test-OERStructure -Path './live/ar-self-no-fallback.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
>
  ```

- [x] **10.3.2 First apply -- U3. Do NOT predict the outcome.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ar-self-no-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable ReviewErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $ReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Unknown (Graph side) -- U3.**

  **Expect:** we do not know -- either `Created` with Detail `created access review
  '<your-test-review>' (recurrence: Weekly)` (Graph accepts a self review with no fallback) or
  `Failed` (it does not) is an acceptable, informative result; treat `Failed` as a finding to write
  up, not as a defect here.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ar-self-no-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable ReviewErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-test-review Created created access review 'oer-dv-test-review' (recurrence: Weekly)  
  
> $ReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.   
>
  ```

- [x] **10.3.3 Read the created definition back.** Skip if 10.3.2 recorded `Failed`. -- 2026-09-06

  ```powershell
  $Def = Get-OERAccessReviewDefinition -DisplayName '<your-test-review>'
  $Def | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount, Recurrence, DurationInDays
  $Def.Reviewers | Format-List *
  $Def.FallbackReviewers | Format-List *
  ```

  **Expect:** `ReviewerCount` `0`, `Reviewers` empty (no `./manager` query), `FallbackReviewers`
  empty.
  **Note the definition id -- section 13 deletes it:** `00000000-0000-0000-0000-000000000011` (deleted in 13.2)
  **Result:**
  ```powershell
> $Def = Get-OERAccessReviewDefinition -DisplayName 'oer-dv-test-review'  
> $Def | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount, Recurrence, DurationInDays  
  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000011  
DisplayName : oer-dv-test-review  
Status : NotStarted  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000012' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000013')  
ReviewerCount : 0  
Recurrence : {[pattern, System.Collections.Hashtable], [range, System.Collections.Hashtable]}  
DurationInDays : 7  
  
> $Def.Reviewers | Format-List *  
> $Def.FallbackReviewers | Format-List *  
>
  ```

- [x] **10.3.4 Second apply, same document -- the convergence proof.** -- 2026-09-06

  **Expect:** `Unchanged`. Run a third time too. **Result:**
```powershell
> Invoke-OERStructure -Path './live/ar-self-no-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable ReviewErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-test-review Unchanged access review 'oer-dv-test-review' already matches  
  
>
```

- [x] **10.4.1 A declared-empty `reviewers` WITH a fallback -- U5.** -- 2026-09-06

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessReviews": [
      { "displayName": "<your-second-test-review>", "accessPackage": "<your-review-access-package>",
        "assignmentPolicy": "<your-review-policy>", "recurrence": "Weekly",
        "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,
        "descriptionForAdmins": "declared-empty reviewers with fallback live check",
        "descriptionForReviewers": "Please review your own access.",
        "reviewers": [], "fallbackReviewers": [ "<fallback-upn>" ] }
    ]
  }
  ```

  Save as `./live/ar-self-with-fallback.json`, future-dated.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-second-test-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",
      "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,
      "descriptionForAdmins": "declared-empty reviewers with fallback live check",
      "descriptionForReviewers": "Please review your own access.",
      "reviewers": [], "fallbackReviewers": [ "person4@example.com" ] }
  ]
}
'@ | Set-Content -Path './live/ar-self-with-fallback.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ar-self-with-fallback.json'
  $V.Valid
  Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable FbReviewErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $FbReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect (offline):** `Valid = True`, no findings.
  **Unknown (Graph side) -- U5.** This sends `-SelfReview` and `-FallbackReviewer` together, which
  `New-OERAccessReviewDefinition` allows (it only refuses `-SelfReview` with `-Manager`/
  `-Reviewer`/`-ReviewerGroup`) but which has never been observed against Graph. Record whichever
  Action comes back.
  **Note the definition id if created -- section 13 deletes it:** `00000000-0000-0000-0000-000000000014` (deleted in 13.2)
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-second-test-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": "Weekly",  
> "startDate": "2026-09-14", "occurrences": 4, "durationInDays": 7,  
> "descriptionForAdmins": "declared-empty reviewers with fallback live check",  
> "descriptionForReviewers": "Please review your own access.",  
> "reviewers": [], "fallbackReviewers": [ "person4@example.com" ] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-self-with-fallback.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ar-self-with-fallback.json'  
> $V.Valid  
True  
> Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false -ErrorVariable FbReviewErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-second-test-review Created created access review 'oer-dv-second-test-review' (recurrence: Weekly)  
   
> $FbReviewErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition  
No access review definition found for the ByFilter query.  
>
  ```

- [x] **10.4.2 Read back and re-apply.** Skip if 10.4.1 recorded `Failed`. -- 2026-09-06

  ```powershell
  $Def2 = Get-OERAccessReviewDefinition -DisplayName '<your-second-test-review>'
  $Def2 | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount
  $Def2.Reviewers | Format-List *
  $Def2.FallbackReviewers | Format-List *
  Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `ReviewerCount` `0`, `Reviewers` empty, `FallbackReviewers` holding `<fallback-upn>`;
  then `Unchanged` on re-apply.
  **Result:**
  ```powershell
> $Def2 = Get-OERAccessReviewDefinition -DisplayName 'oer-dv-second-test-review'  
> $Def2 | Select-Object AccessReviewDefinitionId, DisplayName, Status, Scope, ReviewerCount  
  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000014  
DisplayName : oer-dv-second-test-review  
Status : NotStarted  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000012' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000013')  
ReviewerCount : 0  
  
> $Def2.Reviewers | Format-List *  
> $Def2.FallbackReviewers | Format-List *  
  
Name : queryType  
Key : queryType  
Value : MicrosoftGraph  
  
Name : queryRoot  
Key : queryRoot  
Value :  
  
Name : query  
Key : query  
Value : /v1.0/users/00000000-0000-0000-0000-000000000015  
  
> Invoke-OERStructure -Path './live/ar-self-with-fallback.json' -Include AccessReviews -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-second-test-review Unchanged access review 'oer-dv-second-test-review' already matches  
  
>
  ```

---

### 11. Group PIM policy -- a `pimPolicy.member: null` no longer misreads the whole block, and no
    longer fails the sibling `owner` update -- issue #70

Independent of everything else; uses `<your-pim-group>` from Setup.

- [x] **11.1 Capture the baseline member and owner policies.** -- 2026-09-06

  ```powershell
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner  | Format-List *
  ```

  **Expect:** there is no single correct value to check against -- this only needs to capture
  whatever Setup configured, so checks 11.3/11.4 have something to compare against. The OWNER
  policy's distinctive setting (for example `AuthenticationContextId`) and the MEMBER policy's
  `EligibleDuration`/`ActiveDuration` must both be non-default per the Setup requirements above; if
  either is still at its default, go back to Setup -- check 11.3 cannot detect a reset to a value
  that was already there.
  **Record:** every field of both.
  **Result:**
  ```powershell
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *  
  
GroupId : 00000000-0000-0000-0000-000000000016  
PolicyId : Group_00000000-0000-0000-0000-000000000016_00000000-0000-0000-0000-000000000017  
AccessType : member  
ActivationMaxHours : 8  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : True  
EligibleDuration : P200D  
EligibleDurationDays : 200  
AllowPermanentActive : False  
ActiveDuration : P90D  
ActiveDurationDays : 90  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Enablement_Admin_Eligibility, Expiration_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}  
  
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner | Format-List *  
  
GroupId : 00000000-0000-0000-0000-000000000016  
PolicyId : Group_00000000-0000-0000-0000-000000000016_00000000-0000-0000-0000-000000000018  
AccessType : owner  
ActivationMaxHours : 3  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : False  
EligibleDuration : P150D  
EligibleDurationDays : 150  
AllowPermanentActive : False  
ActiveDuration : P60D  
ActiveDurationDays : 60  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Enablement_Admin_Eligibility, Expiration_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}  
  
>
  ```

- [x] **11.2 Apply a document declaring `member: null` and a REAL change to `owner`.** -- 2026-09-06

  Pick one field on the owner policy that is currently NOT at the value below (for example, if
  `activationMaxHours` is not currently `6`, use that):

  ```json
  { "groups": [
      { "displayName": "<your-pim-group>",
        "pimPolicy": { "member": null, "owner": { "activationMaxHours": 6 } } } ] }
  ```

  ```powershell
  $Frag = '{ "groups": [ { "displayName": "' + $PimGroup + '", "pimPolicy": { "member": null, "owner": { "activationMaxHours": 6 } } } ] }'
  Invoke-LiveCheck -Fragment $Frag -Include Groups
  ```

  **Expect:** the plan/apply shows an `Updated` (or `Skipped` under the plan step) record for
  `pimPolicy (owner)`, and NO record at all for `pimPolicy (member)` -- the member access type is
  never touched, exactly as if `pimPolicy.member` had been omitted entirely.
  **Failure looks like:** a `Failed` record for the WHOLE item (both member and owner), with an
  error naming `Resolve-OERGroupPimPolicyChange` or a null-argument binding error -- that is the
  pre-fix defect: `member: null` selected the nested form by presence, passed a bare `$null` as the
  declared policy, and threw before the owner block was ever reached, so a correctly-declared owner
  change was silently lost alongside the crash.
  **Result:**
  ```powershell
> $Frag = '{ "groups": [ { "displayName": "' + $PimGroup + '", "pimPolicy": { "member": null, "owner": { "activationMaxHours": 6 } } } ] }'  
> Invoke-LiveCheck -Fragment $Frag -Include Groups  
--- offline validation ---  
  
Valid  
-----  
True  
  
--- plan ---  
What if: Performing the operation "Set PIM policy (owner): activationMaxHours=6" on target "oer-dv-pim".  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-pim Unchanged group properties match  
groups oer-dv-pim Extra undeclared member '00000000-0000-0000-0000-000000000005' (use -Prune to remove)  
groups oer-dv-pim Skipped would set pimPolicy (owner): activationMaxHours=6  
  
--- apply ---  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-pim Unchanged group properties match  
groups oer-dv-pim Extra undeclared member '00000000-0000-0000-0000-000000000005' (use -Prune to remove)  
groups oer-dv-pim Updated pimPolicy (owner) set: activationMaxHours=6  
  
>
  ```

- [x] **11.3 Confirm the member policy is untouched and the owner policy changed.** -- 2026-09-06

  ```powershell
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner  | Format-List *
  ```

  **Expect:** the member policy is byte-identical to check 11.1's capture. The owner policy's
  `ActivationMaxHours` is now `6` (or whatever value you declared), and every other owner field
  from 11.1 that the document did not mention is unchanged.
  **Result:**
  ```powershell
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *  
  
GroupId : 00000000-0000-0000-0000-000000000016  
PolicyId : Group_00000000-0000-0000-0000-000000000016_00000000-0000-0000-0000-000000000017  
AccessType : member  
ActivationMaxHours : 8  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : True  
EligibleDuration : P200D  
EligibleDurationDays : 200  
AllowPermanentActive : False  
ActiveDuration : P90D  
ActiveDurationDays : 90  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Enablement_Admin_Eligibility, Expiration_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}  
  
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner | Format-List *  
  
GroupId : 00000000-0000-0000-0000-000000000016  
PolicyId : Group_00000000-0000-0000-0000-000000000016_00000000-0000-0000-0000-000000000018  
AccessType : owner  
ActivationMaxHours : 6  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : False  
EligibleDuration : P150D  
EligibleDurationDays : 150  
AllowPermanentActive : False  
ActiveDuration : P60D  
ActiveDurationDays : 60  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Enablement_Admin_Eligibility, Expiration_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}  
  
>
  ```

- [x] **11.4 Second apply, same document -- convergence for the owner change, still nothing for
  member.** -- 2026-09-06

  **Expect:** `Unchanged` for owner, still nothing for member.
  **Result:**
  ```powershell
> Invoke-LiveCheck -Fragment $Frag -Include Groups  
--- offline validation ---  
  
Valid  
-----  
True  
  
--- plan ---  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-pim Unchanged group properties match  
groups oer-dv-pim Extra undeclared member '00000000-0000-0000-0000-000000000005' (use -Prune to remove)  
groups oer-dv-pim Unchanged pimPolicy (owner) already matches  
  
--- apply ---  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-pim Unchanged group properties match  
groups oer-dv-pim Extra undeclared member '00000000-0000-0000-0000-000000000005' (use -Prune to remove)  
groups oer-dv-pim Unchanged pimPolicy (owner) already matches  
  
>
  ```

---

### 12. A group's `administrativeUnit` must be reciprocated, or `-Prune` undoes it -- issue #59

Independent of everything else. This is the exact defect PR #53's own live check 3.6 first
surfaced; the fix documents it offline rather than changing the destructive prune pass.

- [x] **12.1 Confirm the unit and the group do not exist yet.** -- 2026-09-06

  ```powershell
  Get-OERAdministrativeUnit -Filter "displayName eq '$Au'"
  Get-OERGroup -DisplayName $AuGroup -ErrorAction SilentlyContinue
  ```

  **Expect:** neither `<your-test-au>` nor `<your-au-group>` exists yet. Check 12.2's assertions (the
  AU and the group are BOTH `Created`, not matched to an existing object) depend on this being a true
  first creation.

  **Corrected 2026-09-06 (post-run F6):** the two commands do NOT both "return nothing".
  `Get-OERAdministrativeUnit -Filter` writes a non-terminating `AdministrativeUnitNotFound` error on
  a zero-match filter query -- that is its documented contract, not a defect -- so expect
  `Get-OERAdministrativeUnit: No administrative unit found for 'displayName eq '<your-test-au>''.`
  on the error stream and no object on the output stream. `Get-OERGroup -DisplayName` with
  `-ErrorAction SilentlyContinue` returns nothing and writes nothing, which is why the two lines
  differ. Neither `-Filter` cmdlet is probed by an apply handler, so this contract is only ever seen
  when an operator calls it directly, as here.
  **Failure looks like:** an actual OBJECT coming back for either -- a prior run's teardown (section
  13.7) did not complete. The not-found error alone is the expected result, not a failure.
  **Result:**
  ```powershell
> Get-OERAdministrativeUnit -Filter "displayName eq '$Au'"  
Get-OERAdministrativeUnit: No administrative unit found for 'displayName eq 'oer-dv-au''.   
> Get-OERGroup -DisplayName $AuGroup -ErrorAction SilentlyContinue  
>
  ```

- [x] **12.2 Create the group INTO the unit, reciprocating it in the SAME document -- the
  documented correct pattern, and the offline validator must NOT warn.** -- 2026-09-06

  ```json
  { "groups": [ { "displayName": "<your-au-group>", "administrativeUnit": "<your-test-au>" } ],
    "administrativeUnits": [ { "displayName": "<your-test-au>", "members": [ "<your-au-group>" ] } ] }
  ```

  ```powershell
  $Frag = '{ "groups": [ { "displayName": "' + $AuGroup + '", "administrativeUnit": "' + $Au + '" } ], "administrativeUnits": [ { "displayName": "' + $Au + '", "members": [ "' + $AuGroup + '" ] } ] }'
  $Document = $Frag | ConvertFrom-Json
  $Document | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
  $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/au-reciprocated.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/au-reciprocated.json'
  $V.Valid
  @($V.Errors | Where-Object Path -like '*administrativeUnit') | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/au-reciprocated.json' -Include Groups, AdministrativeUnits -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** no finding at path `groups[0].administrativeUnit` (the group IS named in the unit's
  members). The AU is `Created` first (the pre-pass), then the group is `Created` into it, then the
  administrativeUnits section reports the member as already present (added by the pre-pass) or adds
  it.
  **Result:**
  ```powershell
> $Frag = '{ "groups": [ { "displayName": "' + $AuGroup + '", "administrativeUnit": "' + $Au + '" } ], "administrativeUnits": [ { "displayName": "' + $Au + '", "members": [ "' + $AuGroup + '" ] } ] }'  
> $Document = $Frag | ConvertFrom-Json  
> $Document | Add-Member -NotePropertyName 'version' -NotePropertyValue '1.0' -Force  
> $Document | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force  
> $Document | ConvertTo-Json -Depth 20 | Set-Content -Path './live/au-reciprocated.json' -Encoding utf8  
>  
> $V = Test-OERStructure -Path './live/au-reciprocated.json'  
> $V.Valid  
True  
> @($V.Errors | Where-Object Path -like '*administrativeUnit') | Format-List Section, Item, Path, Message, Severity  
>  
> Invoke-OERStructure -Path './live/au-reciprocated.json' -Include Groups, AdministrativeUnits -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-dv-au Created created administrative unit oer-dv-au (00000000-0000-0000-0000-000000000019)  
groups oer-dv-au-grp Created created group oer-dv-au-grp (00000000-0000-0000-0000-000000000020)  
administrativeUnits oer-dv-au Unchanged administrative unit properties match  
administrativeUnits oer-dv-au Unchanged member 'oer-dv-au-grp' already present  
  
>
  ```

- [x] **12.3 Confirm the group is really a member of the unit.** -- 2026-09-06

  ```powershell
  Get-OERAdministrativeUnit -AdministrativeUnit $Au -IncludeMembers |
      Select-Object -ExpandProperty Members | Format-Table DisplayName, ObjectType
  ```

  **Expect:** `<your-au-group>` is listed. **Result:**
```powershell
> Get-OERAdministrativeUnit -AdministrativeUnit $Au -IncludeMembers |  
> Select-Object -ExpandProperty Members | Format-Table DisplayName, ObjectTyp  
  
DisplayName ObjectType  
----------- ----------  
oer-dv-au-grp group  
  
>
```

- [x] **12.4 Does `-Prune -PlanOnly` on that SAME document undo it?** This is the check PR #53's
  live run raised and #59 answers offline. Read the plan; do not act on it. -- 2026-09-06

  ```powershell
  Invoke-LiveCheck -Fragment $Frag -Include Groups, AdministrativeUnits -Prune -PlanOnly
  ```

  **Expect:** the plan does NOT show `oer-live-new`/`<your-au-group>` being removed from
  `<your-test-au>` -- because THIS document reciprocates the placement (the fix's whole point is
  that a CORRECTLY-written document is safe under `-Prune`).
  **Failure looks like:** the plan shows a `would remove` line naming `<your-au-group>` -- the
  reciprocal `members` entry is not being honoured by the prune pass at all, which would be a
  regression far worse than issue #59 (the offline Warning would then be describing a trap that
  cannot actually be avoided by following its own advice).
  **Result:**
  ```powershell
> Invoke-LiveCheck -Fragment $Frag -Include Groups, AdministrativeUnits -Prune -PlanOnly  
--- offline validation ---  
  
Valid  
-----  
True  
  
--- plan ---  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-au-grp Unchanged group properties match  
administrativeUnits oer-dv-au Unchanged administrative unit properties match  
administrativeUnits oer-dv-au Unchanged member 'oer-dv-au-grp' already present  
   
>
  ```

- [x] **12.5 Now write the UN-reciprocated form, and confirm the offline Warning fires.** This is
  the actual defect scenario: a group placed into a unit whose `members` does not name it. -- 2026-09-06

  ```json
  { "groups": [ { "displayName": "<your-au-group>", "administrativeUnit": "<your-test-au>" } ],
    "administrativeUnits": [ { "displayName": "<your-test-au>", "members": [] } ] }
  ```

  ```powershell
  $BadFrag = '{ "groups": [ { "displayName": "' + $AuGroup + '", "administrativeUnit": "' + $Au + '" } ], "administrativeUnits": [ { "displayName": "' + $Au + '", "members": [] } ] }'
  $BadDoc = $BadFrag | ConvertFrom-Json
  $BadDoc | Add-Member -NotePropertyName 'version'     -NotePropertyValue '1.0'  -Force
  $BadDoc | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $BadDoc | ConvertTo-Json -Depth 20 | Set-Content -Path './live/au-not-reciprocated.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/au-not-reciprocated.json'
  $V.Valid
  @($V.Errors | Where-Object Path -like '*administrativeUnit') | Format-List Section, Item, Path, Message, Severity
  ```

  **Expect:** `Valid = True` (a Warning never blocks), and a Warning at `groups[0].administrativeUnit`
  reading: `Group '<your-au-group>' at groups[0] declares administrativeUnit '<your-test-au>', but
  administrativeUnits[0].members does not list '<your-au-group>'. administrativeUnit is applied
  only when the group is created and never round-trips, so unless this document's
  administrativeUnits[0] entry also names the group in members, -Prune removes the membership the
  create just added in the SAME apply run -- the administrativeUnits section is dispatched after
  groups -- and again on every later apply.`
  **Failure looks like:** no Warning at all -- the loaded module predates commit `dcebb94`.
  **Result:**
  ```powershell
> $BadFrag = '{ "groups": [ { "displayName": "' + $AuGroup + '", "administrativeUnit": "' + $Au + '" } ], "administrativeUnits": [ { "displayName": "' + $Au + '", "members": [] } ] }'  
> $BadDoc = $BadFrag | ConvertFrom-Json  
> $BadDoc | Add-Member -NotePropertyName 'version' -NotePropertyValue '1.0' -Force  
> $BadDoc | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force  
> $BadDoc | ConvertTo-Json -Depth 20 | Set-Content -Path './live/au-not-reciprocated.json' -Encoding utf8  
>  
> $V = Test-OERStructure -Path './live/au-not-reciprocated.json'  
> $V.Valid  
True  
> @($V.Errors | Where-Object Path -like '*administrativeUnit') | Format-List Section, Item, Path, Message, Severity  
  
Section : groups  
Item : oer-dv-au-grp  
Path : groups[0].administrativeUnit  
Message : Group 'oer-dv-au-grp' at groups[0] declares administrativeUnit 'oer-dv-au', but administrativeUnits[0].members does not list 'oer-dv-au-grp'. administrativeUnit is applied only when the group is created and never round-trips, so unless this document's administrativeUnits[0] entry also names the group in members, -Prune removes the membership the create just added in the SAME apply run -- the administrativeUnits section is dispatched after groups -- and again on every later apply. 
Severity : Warning  
   
>
  ```

- [x] **12.6 Confirm `-Prune -PlanOnly` on THIS document DOES plan to remove the group -- proving
  the Warning's claim is accurate, not just present.** -- 2026-09-06

  ```powershell
  Invoke-LiveCheck -Fragment $BadFrag -Include Groups, AdministrativeUnits -Prune -PlanOnly
  ```

  **Expect:** the plan shows a `would remove`/`Extra` line naming `<your-au-group>` under
  `<your-test-au>` -- confirming the Warning is not just noise, and that option A+B (warn, don't
  fix the prune pass) is a real, live trade-off an operator needs to actually read.
  **What this check can and cannot prove.** The group already exists (check 12.2 created it), so
  this is a LATER apply and it confirms only the "and again on every later apply" half of the
  Warning. The "same apply run" half is not observable here and is not worth a destructive live
  run to observe: it follows from the dispatch order (`Invoke-OERStructure` runs `groups`, then
  `administrativeUnits`, in one call, and the `-EnsureOnly` pre-pass reconciles no members), so on
  a genuine FIRST apply of this same `$BadFrag` the create and this very `would remove` line land
  in one run. If you do want it live, delete `<your-au-group>` first and re-run this exact command
  -- the plan must then show the group being created into the unit AND removed from it, in the one
  plan.
  **Do NOT run this with `-Confirm:$false`** -- doing so removes the group from the unit for real.
  **Result:**
  ```powershell
> Invoke-LiveCheck -Fragment $BadFrag -Include Groups, AdministrativeUnits -Prune -PlanOnly  
--- offline validation ---  
  
Valid  
-----  
True  
  
  
Section : groups  
Item : oer-dv-au-grp  
Path : groups[0].administrativeUnit  
Message : Group 'oer-dv-au-grp' at groups[0] declares administrativeUnit 'oer-dv-au', but administrativeUnits[0].members does not list 'oer-dv-au-grp'. administrativeUnit is applied only when the group is created and never round-trips, so unless this document's admini  
strativeUnits[0] entry also names the group in members, -Prune removes the membership the create just added in the SAME apply run -- the administrativeUnits section is dispatched after groups -- and again on every later apply.
Severity : Warning  
  
--- plan ---  
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared member '00000000-0000-0000-0000-000000000020' from unit 'oer-dv-au'.  
What if: Performing the operation "Remove undeclared member '00000000-0000-0000-0000-000000000020'" on target "oer-dv-au".  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-dv-au-grp Unchanged group properties match  
administrativeUnits oer-dv-au Unchanged administrative unit properties match  
administrativeUnits oer-dv-au Skipped would remove undeclared member '00000000-0000-0000-0000-000000000020'  
  
>
  ```

- [x] **12.7 The round-trip check issue #59 calls the one that matters most: an inventory exported
  from a tenant that HAS this group must survive `-Prune -PlanOnly` without planning to remove it.**

  ```powershell
  $Inv = Get-OERInventory -Include Groups, AdministrativeUnits
  $Inv | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force
  $Inv | ConvertTo-Json -Depth 20 | Set-Content -Path './live/inventory-roundtrip.json' -Encoding utf8

  ($Inv.Groups | Where-Object DisplayName -eq $AuGroup).PSObject.Properties.Name
  ($Inv.AdministrativeUnits | Where-Object DisplayName -eq $Au).members

  $V = Test-OERStructure -Path './live/inventory-roundtrip.json'
  $V.Valid
  @($V.Errors | Where-Object Path -like '*administrativeUnit')

  Invoke-OERStructure -Path './live/inventory-roundtrip.json' -Include Groups, AdministrativeUnits -Prune -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** the exported `groups[]` entry for `<your-au-group>` carries NO `administrativeUnit`
  property at all (confirmed by the property-name check above -- `Get-OERInventory` does not
  project this field today), the exported `administrativeUnits[]` entry for `<your-test-au>` DOES
  list `<your-au-group>`'s object id in `members`, offline validation raises no
  `administrativeUnit`-path finding (there is nothing to cross-reference against, since the group
  entry declares no `administrativeUnit`), and the `-Prune -WhatIf` plan does NOT show
  `<your-au-group>` being removed from `<your-test-au>` anywhere.
  **Failure looks like:** the plan shows a removal -- meaning a straight
  export-then-reapply-with-prune round trip is UNSAFE for a tenant that already has this shape,
  independent of whether anyone ever writes an `administrativeUnit` key by hand. That would be a
  regression well beyond issue #59's stated scope.
  **Result:**
  ```powershell
> $Inv = Get-OERInventory -Include Groups, AdministrativeUnits  
> $Inv | Add-Member -NotePropertyName 'tenantAlias' -NotePropertyValue $Alias -Force  
> $Inv | ConvertTo-Json -Depth 20 | Set-Content -Path './live/inventory-roundtrip.json' -Encoding utf8  
>  
> ($Inv.Groups | Where-Object DisplayName -eq $AuGroup).PSObject.Properties.Name  
displayName  
roleAssignable  
dynamic  
description  
mailNickname  
members  
eligibility  
pimPolicy  
> ($Inv.AdministrativeUnits | Where-Object DisplayName -eq $Au).members  
00000000-0000-0000-0000-000000000020  
>  
> $V = Test-OERStructure -Path './live/inventory-roundtrip.json'  
> $V.Valid  
True  
> @($V.Errors | Where-Object Path -like '*administrativeUnit')  
>  
> Invoke-OERStructure -Path './live/inventory-roundtrip.json' -Include Groups, AdministrativeUnits -Prune -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
# ---- The whole-tenant `-Prune -WhatIf` plan is SUMMARISED here, not reproduced. ----
# The raw plan is 487 rows naming this tenant's entire production group inventory: group display
# names, member and owner UPNs, and member object ids. None of that belongs in the repository, and
# redacting it row by row would leave a wall of placeholders that proves nothing. What the check
# turns on is counted below instead, and the tail of the plan -- the rows that actually answer it --
# is kept verbatim.
#
#   487 rows total: 484 `groups`, 3 `administrativeUnits`.
#   401 `Unchanged`, 86 `Skipped`. NO `Created`, `Updated`, `Failed`, `Removed` or `Extra` row
#     anywhere, so the plan proposes no write of any kind against this tenant.
#   85 distinct group display names; 2 administrative units.
#   All 86 `Skipped` rows are one shape -- `member '<upn>' was not reconciled: group '<name>' is
#     dynamic and its membership is owned by its membership rule` -- spread over 7 dynamic groups.
#   77 groups carry BOTH a `pimPolicy (member) already matches` and a `pimPolicy (owner) already
#     matches` row: one pair per group, PIM-onboarded or not. Those pairs, and the per-member
#     `Skipped` rows above, are what finding F8 is about.
#   NOTHING in the plan removes `oer-dv-au-grp` from `oer-dv-au` -- which is what this check asked.
#
# The tail of the plan, verbatim:
groups oer-dv-pim Unchanged group properties match  
groups oer-dv-pim Unchanged member 'person5@example.com' already present  
groups oer-dv-pim Unchanged owner 'person1@example.com' already present  
groups oer-dv-pim Unchanged eligibility for 'person6@example.com' (member) already matches  
groups oer-dv-pim Unchanged pimPolicy (member) already matches  
groups oer-dv-pim Unchanged pimPolicy (owner) already matches  
groups oer-dv-au-grp Unchanged group properties match  
groups oer-dv-au-grp Unchanged pimPolicy (member) already matches  
groups oer-dv-au-grp Unchanged pimPolicy (owner) already matches  
administrativeUnits oer-dv-au Unchanged administrative unit properties match  
administrativeUnits oer-dv-au Unchanged member '00000000-0000-0000-0000-000000000020' already present  
administrativeUnits <production-administrative-unit-1> Unchanged administrative unit properties match  

>
  ```

---

### 13. Teardown -- restore the tenant, and be honest about what cannot be restored

**A cleared approval stage cannot be un-cleared.** The only way back is to re-declare it and write
it again (check 13.3). An **escalation-approver fallback** set through the portal
(`fallbackEscalationApprovers`) is cleared by any stage rebuild and is not authorable through the
document -- if Setup's policy had one, re-create it by hand.

- [x] **13.1 Delete the assignment policy created in check 9.5.** -- 2026-09-06

  ```powershell
  $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy
  $NewPol | Select-Object Id, DisplayName
  Remove-OERAccessPackageAssignmentPolicy -Id $NewPol.Id
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName
  ```

  **Expect:** the cmdlet prompts (`Remove-OERAccessPackageAssignmentPolicy` is
  `ConfirmImpact = High`) and warns `Deleting assignment policy '<id>'. This is irreversible.`;
  after confirming, the read-back lists only `<your-test-policy>`. Skip and mark "not applicable"
  if 9.5 recorded `Failed`.
  **Result:**
  ```powershell
> $NewPol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $NewPolicy  
> $NewPol | Select-Object Id, DisplayName  
  
Id DisplayName  
-- -----------  
00000000-0000-0000-0000-000000000010 oer-dv-policy-new  
  
> Remove-OERAccessPackageAssignmentPolicy -Id $NewPol.Id  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete assignment policy" on target "00000000-0000-0000-0000-000000000010".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting assignment policy '00000000-0000-0000-0000-000000000010'. This is irreversible.  
> Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Select-Object Id, DisplayName  
  
Id DisplayName  
-- -----------  
00000000-0000-0000-0000-000000000003 oer-dv-policy  
>
  ```

- [x] **13.2 Delete the access review definitions created in sections 10.1, 10.2, 10.3, 10.4.** -- 2026-09-06

  ```powershell
  Remove-OERAccessReviewDefinition -DisplayName '<your-onetime-review>'
  Remove-OERAccessReviewDefinition -DisplayName '<your-startdate-review>'
  Remove-OERAccessReviewDefinition -DisplayName '<your-enddate-review>'
  Remove-OERAccessReviewDefinition -DisplayName '<your-test-review>'
  Remove-OERAccessReviewDefinition -DisplayName '<your-second-test-review>'
  Get-OERAccessReviewDefinition -All | Where-Object DisplayName -in @(
      '<your-onetime-review>', '<your-startdate-review>', '<your-enddate-review>',
      '<your-test-review>', '<your-second-test-review>')
  ```

  Skip any line whose matching create recorded `Failed`.

  **Remove by these five names, one line each. NEVER by pattern.** **Corrected 2026-09-06 (post-run
  F1/F11):** the 2026-09-06 run replaced these five lines with
  `Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER` and deleted everything it matched.
  That swept up the access package's OWN Lifecycle access review (`oer-dv-ap - oer-dv-policy`), whose
  id the policy's `reviewSettings` still references -- and since every policy PUT carries
  `reviewSettings` forward, Graph then refused EVERY later update of `oer-dv-policy` with
  `NotFound: BusinessFlow not found for id ...`. That is why 13.3 failed and the tenant was left
  un-restored. It also removed four unrelated leftover test reviews. A display-name pattern is not a
  scope; the five names are.

  **Expect:** each removal prompts; the final read returns nothing. `Remove-OERAccessReviewDefinition`
  now emits an extra Warning when the definition is an access package's Lifecycle access review --
  if you see it here, you are about to repeat F1: stop and re-read the name you passed.
  **Result:**
  ```powershell
> Get-OERAccessReviewDefinition -All  
  
DisplayName Status StageCount ReviewerCount Id  
----------- ------ ---------- ------------- --  
oer-dv-second-test-review NotStarted 0 0 00000000-0000-0000-0000-000000000014  
oer-dv-test-review NotStarted 0 0 00000000-0000-0000-0000-000000000011  
oer-dv-enddate-review NotStarted 0 0 00000000-0000-0000-0000-000000000021  
oer-dv-startdate-review Completed 0 0 00000000-0000-0000-0000-000000000022  
oer-dv-onetime-review Completed 0 0 00000000-0000-0000-0000-000000000023  
oer-dv-ap - oer-dv-policy NotStarted 0 1 00000000-0000-0000-0000-000000000024  
oer-fr-review Completed 0 1 00000000-0000-0000-0000-000000000025  
<production-review-1> InProgress 0 1 00000000-0000-0000-0000-000000000026  
<production-review-2> Completed 0 1 00000000-0000-0000-0000-000000000027  
AR-OER-Demo InProgress 0 1 00000000-0000-0000-0000-000000000028  
OER-DIAG-B-betascope-userReviewer InProgress 0 1 00000000-0000-0000-0000-000000000029  
OER-DIAG-A-v1scope-userReviewer InProgress 0 1 00000000-0000-0000-0000-000000000030  
<production-review-3> InProgress 0 1 00000000-0000-0000-0000-000000000031  
<production-review-4> InProgress 0 0 00000000-0000-0000-0000-000000000032  
<production-review-5> InProgress 0 0 00000000-0000-0000-0000-000000000033  
  
> Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER  
  
DisplayName Status StageCount ReviewerCount Id  
----------- ------ ---------- ------------- --  
oer-dv-second-test-review NotStarted 0 0 00000000-0000-0000-0000-000000000014  
oer-dv-test-review NotStarted 0 0 00000000-0000-0000-0000-000000000011  
oer-dv-enddate-review NotStarted 0 0 00000000-0000-0000-0000-000000000021  
oer-dv-startdate-review Completed 0 0 00000000-0000-0000-0000-000000000022  
oer-dv-onetime-review Completed 0 0 00000000-0000-0000-0000-000000000023  
oer-dv-ap - oer-dv-policy NotStarted 0 1 00000000-0000-0000-0000-000000000024  
oer-fr-review Completed 0 1 00000000-0000-0000-0000-000000000025  
AR-OER-Demo InProgress 0 1 00000000-0000-0000-0000-000000000028  
OER-DIAG-B-betascope-userReviewer InProgress 0 1 00000000-0000-0000-0000-000000000029  
OER-DIAG-A-v1scope-userReviewer InProgress 0 1 00000000-0000-0000-0000-000000000030  
  
> $Reviews = Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER  
> foreach ($R in $Reviews) {Remove-OERAccessReviewDefinition -DisplayName $R.DisplayName}  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000014".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"): a  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000014'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000011".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"): a  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000011'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000021".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"): a  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000021'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000022".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"): a  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000022'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000023".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000023'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000024".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000024'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000025".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000025'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000028".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000028'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000029".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000029'. This is irreversible.  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000030".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000030'. This is irreversible.  
> $Reviews = Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER  
> $Reviews  
>
  ```

- [ ] **13.3 Re-apply the original stage AND the original description on `<your-test-policy>`.** -- FAILED 2026-09-06 -- see post-run review F1; re-run after the lifecycle review is repaired (section 14)
  Substitute the description and stage configuration recorded in check 1.4.

  **Corrected 2026-09-06 (post-run F13): this document MUST also declare
  `"requireApprovalForUpdate": true`.** Without it, `ap-restore.json` is not a complete restore
  document: an undeclared flag is carried forward from the LIVE policy, so any check that turned
  `requireApprovalForUpdate` off (14.3.1) could not be undone by re-applying this file. That is
  exactly what made the first 14.3.3 run inconclusive -- the restore reported `Updated`, the
  read-back showed `RequireApprovalForUpdate False`, and the probe that was supposed to ISOLATE that
  flag ran with the flag already off, so the write had nothing left to refuse. The same document is
  reused by 14.3.4 and 14.7.3, so the omission propagates. Both JSON blocks below carry the flag.

  Save as `./live/ap-restore.json`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-tenant-alias>",
    "accessPackages": [
      { "displayName": "<your-test-access-package>", "catalog": "<your-test-catalog>", "resourceRoles": null,
        "assignmentPolicies": [
          { "displayName": "<your-test-policy>", "description": "<original-description-from-1.4>",
            "requireApproval": true, "requireApprovalForUpdate": true,
            "approvalStages": [
              { "durationDays": 14, "users": [ "<approver-upn>" ],
                "requireApproverJustification": true, "approverInfoVisibility": "Default" }
            ] } ] } ] }
  ```

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy", "description": "oer-dv baseline: distinctive description, do not reset",
          "requireApproval": true, "requireApprovalForUpdate": true,
          "approvalStages": [
            { "durationDays": 14, "users": [ "person1@example.com" ],
              "requireApproverJustification": true, "approverInfoVisibility": "Default" }
          ] } ] } ] }
  '@ | Set-Content -Path './live/ap-restore.json' -Encoding utf8
  ```

  ```powershell
  $V = Test-OERStructure -Path './live/ap-restore.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Valid = True` with only the catalog Warning (not the contradiction one), then
  `Updated`, then `Unchanged` on re-run.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "description": "oer-dv baseline: distinctive description, do not reset",  
> "requireApproval": true,  
> "approvalStages": [  
> { "durationDays": 14, "users": [ "person1@example.com" ],  
> "requireApproverJustification": true, "approverInfoVisibility": "Default" }  
> ] } ] } ] }  
> '@ | Set-Content -Path './live/ap-restore.json' -Encoding utf8  
> $V = Test-OERStructure -Path './live/ap-restore.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: NotFound: {"error":{"code":"","message":"BusinessFlow not found for id 00000000-0000-0000-0000-000000000024"}}  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': NotFound: {"error":{"code":"","message":"BusinessFlow not found for id 00000000-0000-0000-0000-000000000024"}}  
  
>
# Post-run note: 00000000-0000-0000-0000-000000000024 is the policy's OWN Lifecycle access review ("oer-dv-ap - oer-dv-policy"),
# deleted by the `-Match OER` loop in 13.2. The policy's reviewSettings still references it, every PUT
# carries reviewSettings forward, and Graph now refuses the whole PUT. NOTHING was restored here:
# 13.4 shows the 6.3 description and the section 2 requestor scope still live.
  ```

- [ ] **13.4 Compare the final policy against the section 1 baseline, field by field.** -- PARTIAL 2026-09-06 -- ran, but the two differences are 13.3's failure, not explained-and-accepted; re-run after 13.3 succeeds

  ```powershell
  $Final = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $BeforeAll = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $AllFields | ConvertTo-Json -Depth 10
  $FinalAll  = $Final | Select-Object $AllFields | ConvertTo-Json -Depth 10
  "identical: $($BeforeAll -eq $FinalAll)"
  Compare-Object -ReferenceObject ($BeforeAll -split "`n") -DifferenceObject ($FinalAll -split "`n")
  ```

  **Expect:** `identical: True`, or `identical: False` with every difference EXPLAINABLE (an object
  id replacing a UPN you typed, an `approverInfoVisibility`/`managerLevel` the portal left implicit
  now reading as an explicit `Default`/`1`). A field that moved with no explanation is a finding
  this branch caused, not an accepted outcome of this check.
  **Record:** the `identical:` line and every difference, with an explanation for each.
  **Result:**
  ```powershell
> $Final = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id   
> $BeforeAll = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $AllFields | ConvertTo-Json -Depth 10  
> $FinalAll = $Final | Select-Object $AllFields | ConvertTo-Json -Depth 10  
> "identical: $($BeforeAll -eq $FinalAll)"  
identical: False  
> Compare-Object -ReferenceObject ($BeforeAll -split "`n") -DifferenceObject ($FinalAll -split "`n")  
  
InputObject SideIndicator  
----------- -------------  
"Description": "declared-value-family regression check -- approvalStages omitted",... =>  
"00000000-0000-0000-0000-000000000005",... =>  
"00000000-0000-0000-0000-000000000006"... =>  
"Description": "oer-dv baseline: distinctive description, do not reset",... <=  
"00000000-0000-0000-0000-000000000004"... <=  
  
>
# Post-run note: both differences are the un-restored state 13.3 left behind --
#   Description          : still 6.3's "declared-value-family regression check -- approvalStages omitted"
#   RequestorScope.users : still section 2's user-a/user-b instead of Setup's approver
# Neither is an unexplained field move; both go away once 13.3 lands.
  ```

- [x] **13.5 Confirm the portal-only fields survived the whole run.** Compare against check 1.5. -- 2026-09-06

  **Expect:** the Requestor information questions and the Lifecycle access review configuration
  match check 1.5's capture exactly. If either is gone or reset, restore it by hand and record that
  the loss -- not the manual restore -- is the finding.
  **Record:** whether they are still exactly as they were.
  **Result:**
  ```powershell
Confirmed.
# Post-run note: the Requestor information question survived. The Lifecycle "Require access review"
# CONFIGURATION may still render in the portal, but its backing definition (00000000-0000-0000-0000-000000000024) was deleted
# in 13.2 (see 13.3) -- re-check this blade after the section 14 repair and record what the portal shows.
  ```

- [x] **13.6 Restore the requestor scope to whatever Setup originally configured**, since section 2
  changed it to `SpecificDirectoryUsers` with `<specific-user-a>`/`<specific-user-b>` and section 5
  onward never re-declared it (it was carried forward by every subsequent PUT). Re-apply Setup's
  original scope through the portal or a document naming the original users/groups. -- 2026-09-06

  **Expect:** `Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id | Select-Object AllowedTargetScope`
  and `.RequestorScope` match whatever Setup's "Users who can request access" was configured to
  before section 2 ran. If you recorded that value at Setup time, confirm it matches field-by-field
  and say so; if you did not record it, write "cannot be verified, and therefore we do not know:
  the original requestor scope was not captured before Setup began" and record what you restored
  it to instead so the tenant is at least left in a deliberate, named state.
  **Result:**
  ```powershell
Confirmed.
# Post-run note: 13.4 (run before this) still showed user-a/user-b in RequestorScope.users, so this
# "Confirmed" can only be a portal edit made after 13.4 -- or it is not done. The prod account
# person3@example.com (added for 8.5) was removed before section 13. Re-verify in section 14 with
# (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope -- expected: approver only.
  ```

- [x] **13.7 Delete the group and administrative unit created in section 12.** -- 2026-09-06

  ```powershell
  Remove-OERGroup -DisplayName $AuGroup
  Remove-OERAdministrativeUnit -DisplayName $Au
  ```

  **Expect:** each cmdlet prompts (both are `ConfirmImpact = High`) and warns -- `Deleting Entra ID
  group '<id>'. This is a high-impact, hard-to-reverse operation.` and `Deleting Entra ID
  administrative unit '<id>'. This is a high-impact, hard-to-reverse operation.` respectively.
  After confirming both, `Get-OERGroup -DisplayName $AuGroup` and
  `Get-OERAdministrativeUnit -Filter "displayName eq '$Au'"` return nothing.
  **Result:**
  ```powershell
> Remove-OERGroup -DisplayName $AuGroup  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Permanently delete Entra ID group" on target "00000000-0000-0000-0000-000000000020".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting Entra ID group '00000000-0000-0000-0000-000000000020'. This is a high-impact, hard-to-reverse operation.  
> Remove-OERAdministrativeUnit -DisplayName $Au  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Permanently delete Entra ID administrative unit" on target "00000000-0000-0000-0000-000000000019".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting Entra ID administrative unit '00000000-0000-0000-0000-000000000019'. This is a high-impact, hard-to-reverse operation.  
>
  ```

- [x] **13.8 Restore `<your-pim-group>`'s owner policy to the state captured in check 11.1.** -- 2026-09-06

  **Expect:** `Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner` matches check 11.1's
  capture field-for-field once restored.
  **Record:** what you had to restore by hand, or "nothing" if it matched already.
  **Result:**
  ```powershell
Confirmed
  ```

- [x] **13.9 Remove the Tenant Profile Defaults added for this run**, if they were not already
  part of the profile before Setup: -- 2026-09-06

  ```powershell
  Set-OERConfiguration -TenantAlias $Alias -Defaults @{}
  Get-OERConfiguration -TenantAlias $Alias | Select-Object -ExpandProperty Defaults
  ```

  **Expect:** the command succeeds with no error, and the read-back's `Defaults` no longer carries
  the `PrimaryApprovers`/`EscalationApprovers` keys added for this run.
  **Failure looks like:** a `TenantProfileMalformed` error, or the read-back still showing
  `<approver-upn>`/`<profile-escalation-upn>` -- the write did not take.
  Skip if the profile already had different `Defaults` you need to keep -- restore those instead.
  **Result:**
  ```powershell
> Set-OERConfiguration -TenantAlias $Alias -Defaults @{}  
  
TenantAlias TenantId Environment Path  
----------- -------- ----------- ----  
Omnicit 00000000-0000-0000-0000-000000000034 C:\Users\SEGOTPHA\.config\Omnicit.EntraRBAC\Profiles\Omnicit.psd1  
  
> Get-OERConfiguration -TenantAlias $Alias | Select-Object -ExpandProperty Defaults  
>
  ```

- [x] **13.10 Restore anything the documents could not** -- specifically any
  `fallbackEscalationApprovers` set through the portal on `<your-test-policy>`'s stage in Setup,
  which no document in this checklist can re-declare. -- 2026-09-06

  **Expect:** either Setup never configured a portal-only escalation fallback (so there is nothing
  to restore -- record "nothing"), or the fallback is visible in the portal again after a manual
  re-creation.
  **Record:** what you had to restore manually, or "nothing".
  **Result:**
  ```powershell
Done/Confirmed
  ```

- [x] **13.11 Clean up the working folder.** -- 2026-09-06

  ```powershell
  Remove-Item -Path './live' -Recurse -Force
  Disconnect-OER
  ```

  **Expect:** both commands complete without error and `./live` no longer exists. A subsequent
  `Get-OER*`/`Invoke-OERStructure` call in this session does NOT fail: every public cmdlet calls
  `Initialize-OERAuth` at entry, so it re-authenticates automatically -- expect a fresh interactive
  sign-in prompt, exactly as `Disconnect-OER`'s own help says ("the next OER cmdlet will trigger a
  fresh sign-in"). `Connect-OER` is an optional pre-auth shortcut, never a precondition. If you are
  finished, close the session rather than running another cmdlet, so no prompt appears at all.
  **Result:**
  ```powershell
> Remove-Item -Path './live' -Recurse -Force  
> Disconnect-OER  
>
  ```

---

### Post-run review (2026-09-06) -- findings, corrections and what still needs a live answer

> Written after the full run (sections 1-13) by Philip + Claude (Cowork) as the hand-off to Claude
> Code. Everything below refers to results recorded above. **Section 14 goes directly after this
> block**: every item marked *VERIFY LIVE* is a candidate check for it; Philip runs 14 and reports
> back before the PR is merged and the issues are closed.
>
> Run status: every one of the 73 checks has a written result; 71 are ticked. Ticks corrected in
> this review: 4.2, 10.1.1, 12.7 and 13.1 were passed but un-ticked (now ticked); **13.3 is
> un-ticked -- it FAILED** and 13.4 follows it. The tenant is therefore NOT fully restored (F1).

**Issue verdicts, on the evidence above.**

| Issue | Checks | Verdict |
|---|---|---|
| #69 requestorScope inference | 1.2, 2.1-2.4 | **Proven live.** Warning fires, scope + users land, converges, explicit scope wins, declared users silently unused under a non-Specific scope. |
| #68 alternateUsers guard | 7.1, 7.2 | **Proven live** (7.1 kept the document's `oer-dv-esc-doc`, 7.2 fell back to the profile's `oer-dv-esc-profile`) -- with a wording finding, F5. |
| #70 durationDays (site 3) | 7.3 | **Proven live** -- the policy is reported failed, nothing written -- with a result-shape finding, F4. |
| #70 access review nulls | 10.1.x, 10.2.x | **Proven live** (`recurrence: null` -> OneTime + Unchanged; `startDate: null`/`endDate: null` no longer crash) -- with two side findings, F6 and F7. |
| #70 pimPolicy.member null | 11.1-11.4 | **Proven live.** member untouched, owner updated, converges. |
| #67 recurrence null convergence | 10.1.3 | **Proven live** -- `Unchanged` on the second apply. |
| #59 AU reciprocation warning | 12.1-12.7 | **Proven live**, both halves: reciprocated document safe under `-Prune -PlanOnly`, un-reciprocated one plans the removal, exported inventory round-trips safely. Side finding F8. |
| U1 (empty stages, update) | 3.2-3.4, 4.x | **Answered: Graph REFUSES** -- `InvalidApprovalStages`, and refuses forever (Failed x3). See F2. |
| U1 (empty stages, create) | 9.5, 9.6 | **Answered: Graph ACCEPTS** the POST -- `oer-dv-policy-new` created with 0 stages, `RequireApproval` false, converges. |
| U2 composite carry-forward | 5.x, 13.5 | **Answered, but not where the checklist thinks.** Section 3 never wrote, so 5.1-5.5 compare a policy nothing touched. The real evidence is the successful PUTs in 6.4, 7.1, 7.2, 7.4 and 9.2 after which stages, scope, questions and reviewSettings all survived (13.5). See F3. |
| U3 / U5 (self review, no fallback / with fallback) | 10.3.x, 10.4.x | **Answered: Graph accepts both**, both converge. |
| U4 (self-contradictory document) | 8.2-8.5 | **Answered: Graph refuses** the write (`InvalidApprovalStages`); the dead policy can never exist, so the Warning's "no request can ever be approved" clause describes a state Graph will not create. See F2. |

**Findings.** Severity: **Blocker** = must be resolved before merge; **Fix** = code/doc change on this
branch; **Decide** = design call for the maintainer; **Note** = record only.

- **F1 -- Blocker (tenant state), Fix (module).** `Remove-OERAccessReviewDefinition` deleted the
  access package policy's OWN lifecycle review (`oer-dv-ap - oer-dv-policy`, `00000000-0000-0000-0000-000000000024`) because
  13.2 was run as `Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER` instead of the
  five named removes. Since then every PUT to `oer-dv-policy` fails with `NotFound: BusinessFlow not
  found for id 00000000-0000-0000-0000-000000000024` (13.3): the module carries `reviewSettings` forward on every update,
  and Graph validates the referenced definition. Two consequences. (a) The tenant is not restored:
  description and requestor scope are still the test values (13.4), and section 14 must repair the
  review (portal: Edit policy > Lifecycle > un-tick and re-tick "Require access reviews", save; or
  whatever Claude Code finds works via Graph) and then re-run 13.3, 13.4, 13.5, 13.6. (b) Module:
  a policy whose lifecycle review definition has been deleted out from under it becomes
  un-updatable through `Invoke-OERStructure` with a raw Graph error. Decide whether
  `Set-OERAccessPackageAssignmentPolicy` should detect this (`reviewSettings.isEnabled` true + the
  definition missing) and produce a named error with the remedy, and whether
  `Remove-OERAccessReviewDefinition` should warn (or refuse without `-Force`) when the definition
  is an access-package lifecycle review (`scope` pointing at `entitlementManagement/assignments`
  and the display name in the `<package> - <policy>` shape). *VERIFY LIVE* after the fix: repair,
  then 13.3 must report `Updated` and 13.4 `identical: True` (or only the object-id/UPN class of
  difference).
- **F2 -- Fix (code or checklist), VERIFY LIVE.** U1 on the update path is now known: a PUT with
  `requestApprovalSettings.stages: []` is refused with `InvalidApprovalStages: If approval is
  required, a valid list of stages must be provided` (3.2), and refused identically on every re-run
  (3.3, 3.4) -- a `Failed`-forever non-convergence for a document that validates clean offline. The
  checklist's premise for 4.1 ("`RequireApproval` derived from the stage count, since
  `-RequireApproval` was never bound") did not hold on the wire: the body Graph rejected had an
  approval flag set. Claude Code must read `ConvertTo-OERPolicyBody.ps1` and establish WHICH flag
  it was -- `isApprovalRequired` carried forward from `-Existing` instead of derived, or
  `isApprovalRequiredForUpdate` (true on this policy, never declared, carried forward) -- and then
  decide: (i) derive `isApprovalRequired` from the declared stage count when `requireApproval` is
  not declared, and/or clear `isApprovalRequiredForUpdate` when the stages are cleared, or (ii)
  leave the body as is and make the offline validator warn that `approvalStages: []` on an
  EXISTING policy with approval required cannot be applied (the current contradiction Warning only
  fires when the document itself declares `requireApproval: true`). Section 14 candidates:
  `{"approvalStages": [], "requireApproval": false, "requireApprovalForUpdate": false}` -- does
  Graph accept the PUT then, and does it converge? And `{"approvalStages": [], "requireApproval":
  false}` alone -- does `isApprovalRequiredForUpdate` on its own still trigger the refusal? Whatever
  the outcome, the Warning text at `Test-OERStructureSchema.ps1` ("...so the policy is written with
  approval required and no approver stages at all and no request can ever be approved") describes a
  write Graph does not perform; reword it to the observed outcome ("Graph refuses the write with
  InvalidApprovalStages; the policy is reported Failed and left unchanged"). 8.5 confirmed there is
  no dead policy to observe.
- **F3 -- Fix (checklist text).** Sections 4 and 5 are written as if section 3 had cleared the
  stages. It did not (F2), so 4.1/4.2 recorded the untouched policy and 5.1-5.5 compared a policy
  no PUT had touched (5.1's only diff is section 2's intentional scope change). The U2 answer
  stands on 6.4, 7.1, 7.2, 7.4, 9.2 + 13.5 instead. Re-word the section 4/5 `Expect:` lines to be
  conditional on 3.2's outcome, exactly as 8.3 already is, so the next operator is not told to
  expect "reads No" from a policy Graph refused to change.
- **F4 -- Fix (code), VERIFY LIVE.** 7.3's result row has NO `Action` value: `accessPackages
  oer-dv-ap failed to build assignmentPolicy 'oer-dv-policy': Cannot validate argument on parameter
  'Days'...` -- compare 8.2's `Failed  failed to update ...`. The "failed to build" path in
  `Sync-OERStructureAccessPackage.ps1` appears to emit the StructureResult with an empty/missing
  Action (or the message in the Action slot). Every consumer that filters on `Action -eq 'Failed'`
  misses it. Fix and add a unit test that asserts `Action = 'Failed'` for the build-failure path.
  Section 14: re-run 7.3's apply and confirm the row reads `Failed`.
- **F5 -- Fix (warning text).** 7.1's Warning says `substituting Tenant Profile 'Omnicit' defaults
  (1 PrimaryApprovers, 1 EscalationApprovers)` although the EscalationApprovers default was NOT
  substituted -- the document's own `alternateUsers` survived (that is #68's fix working). The
  counts in the message are the profile's, not what was applied. Make the message name only what
  was actually substituted (here: PrimaryApprovers), so the Warning cannot be read as the pre-#68
  behaviour. (Confirm the id mapping while there: 7.1 landed `00000000-0000-0000-0000-000000000007` and 7.2 landed
  `00000000-0000-0000-0000-000000000008`; the first must be `oer-dv-esc-doc`, the second `oer-dv-esc-profile`.)
- **F6 -- Fix (code) -- the Sprint 1 pattern, in reverse.** Every access review create leaked TWO
  non-terminating errors into `-ErrorVariable`: `AccessReviewDefinitionNotFound,
  Get-OERAccessReviewDefinition -- No access review definition found for the ByFilter query`
  (10.2.1, 10.2.2, 10.3.2, 10.4.1). The create handler's existence probe is a cmdlet that reports
  "not found" as an error, and it is called twice per item. An operator running with
  `$ErrorActionPreference = 'Stop'` or inspecting `$Error` after an apply sees failures that are
  not failures. Same shape in 12.1: `Get-OERAdministrativeUnit -Filter` writes an error for zero
  matches while the checklist's `Expect:` says "returns nothing". Decide the contract for
  filter/by-name lookups (empty result vs. error), make the handlers' probes call with
  `-ErrorAction SilentlyContinue` / a dedicated `Test-`/`Find-` probe, and de-duplicate the double
  call. Section 14: `Invoke-OERStructure ... -ErrorVariable E` on a fresh review create must leave
  `$E` empty.
- **F7 -- Fix (checklist or projection).** `Get-OERAccessReviewDefinition` returns `Recurrence` as
  the raw Graph object (`{[pattern, ], [range, Hashtable]}`), not the module word the apply Detail
  prints (`recurrence: OneTime` / `Weekly`), so 10.1.2's `Expect: Recurrence is OneTime` cannot be
  met as written. Either project a normalised `Recurrence` word (with the raw object under another
  property) or rewrite the Expect to inspect `.Recurrence.pattern.type`. The convergence proofs
  (10.1.3, 10.3.4, 10.4.2) do not depend on it.
- **F8 -- Decide (inventory noise, performance).** 12.7's `-Prune -WhatIf` plan for the whole
  tenant contained 86 `Skipped member ... group is dynamic and its membership is owned by its
  membership rule` rows and a `pimPolicy (member)/(owner) already matches` pair for EVERY group,
  PIM-onboarded or not. `Get-OERInventory` exports `members` for dynamic groups (which the apply
  then refuses per member) and `pimPolicy` for every group. Consider: omit `members` on dynamic
  groups at export, emit one `Skipped` row per dynamic group instead of one per member, and only
  export/compare `pimPolicy` where the group is PIM-onboarded. Not a correctness defect; the #59
  round trip itself passed. (The 12.7 result block contains production group names and UPNs --
  redact before anything from it reaches the repo. Done: the tracked copy of 12.7 summarises the
  plan and keeps only its tail verbatim; the counts quoted here come from the raw plan.)
- **F9 -- Note (checklist wording).** 6.1 and 9.2 recorded `Unchanged` where the Expect says
  `Updated`, and 9.1 recorded `Unchanged` where it says `Skipped` -- all correct given that section
  3 wrote nothing (the stage was never gone), and 9.1's document matched live, so there was nothing
  to plan. Make those Expects conditional like 8.3.
- **F10 -- Note.** 13.9's `Set-OERConfiguration -Defaults @{}` succeeded; the `~` lines in the
  transcript are the prompt theme, not output. 13.8 and 13.10 were confirmed by hand without a
  read-back pasted; section 14 should include `Get-OERGroupPimPolicy -Group oer-dv-pim -AccessType
  owner | Select ActivationMaxHours` (expected 3) so the restore is on record.
- **F11 -- Note (teardown still owed).** The 8.5 request `00000000-0000-0000-0000-000000000009`
  by `person3@example.com` is still `Pending approval` on `oer-dv-policy`. It must be
  cancelled (My Access > Request history > Cancel, or an admin deny) and the cancellation recorded
  in 14, and the pre-req script's `-RestoreWrites` cannot do it. The leftover reviews the
  `-Match OER` loop also removed (`oer-fr-review`, `AR-OER-Demo`, `OER-DIAG-A/B-*`) were earlier
  test objects, so no production review was touched -- but 13.2's Expect should say explicitly
  "remove by the five names, never by pattern", which is what F1 cost.
- **F12 -- Fix (code), found in section 14 (14.1.2 re-run + 14.6.4).** The new
  `Remove-OERAccessReviewDefinition` scope guard -- and the pre-existing `This is irreversible`
  warning -- are written AFTER `ShouldProcess` has returned true: under `-WhatIf` only the `What if:`
  line prints and no warning at all (14.1.2), and on a real delete the order is Confirm prompt ->
  irreversible warning -> scope warning (14.6.4), i.e. the operator confirms BEFORE being told what
  they are deleting. Move both `Write-Warning` calls ahead of `$PSCmdlet.ShouldProcess(...)` so they
  print under `-WhatIf`, before the confirm prompt, and with `-Confirm:$false`; consider folding the
  "targets an access package's assignments" fact into the ShouldProcess action text as well. Add a
  unit test that asserts the scope warning is emitted when `-WhatIf` is passed. Same ordering audit
  for the other `ConfirmImpact = High` cmdlets (`Remove-OERGroup`, `Remove-OERAdministrativeUnit`,
  `Remove-OERAccessPackageAssignmentPolicy`): 13.1 and 13.7 show their irreversible warnings after
  the prompt too. *VERIFY LIVE* after the fix: 14.1.2 again -- warning visible under `-WhatIf`,
  nothing deleted.
- **F13 -- Fix (checklist).** `ap-restore.json` (13.3) must declare `"requireApprovalForUpdate":
  true`; without it any check that turned the flag off (14.3.1) cannot be undone by the restore
  document, which is what made the first 14.3.3 run inconclusive. Same document is reused by 14.3.4
  and 14.7.3. And 14.1's "run 14.1 before 14.2" contradicts 14.1.2, which needs the lifecycle review
  14.2.1 re-creates -- reorder or split.

**What section 14 should cover, in order** (Claude Code writes the checks; Philip runs them):

1. Repair `oer-dv-policy`'s lifecycle review (F1), then re-run 13.3 -> 13.4 -> 13.5 -> 13.6 with
   read-backs pasted.
2. F2 probes: the two `approvalStages: []` variants with the approval flags declared false, plus
   a third apply of whichever variant Graph accepts (convergence); then restore with
   `ap-restore.json`.
3. F4: re-run 7.3's apply on the fixed build; row must read `Failed`; policy unchanged.
4. F6: one access review create with `-ErrorVariable`, `$E.Count` must be `0`; delete it again by
   name.
5. F10: owner PIM policy read-back (ActivationMaxHours 3, EligibleDuration P150D,
   ActiveDuration P60D).
6. F11: cancel request `00000000-0000-0000-0000-000000000009` and paste the Requests blade state (Cancelled/Denied).
7. Final: `& $Dv -SkipUsers -SkipObjects` verify must be 32/32 again, and the pre-req script's
   `-RestoreWrites` PUT of the baseline must succeed (it will fail with F1's error until step 1).

---

### 14. Post-run repair and re-verification (2026-09-06)

Written by Claude Code after the post-run review above, in the order that block proposes. **Philip
runs this section and reports back; the PR is not merged until it has results.**

Same house rule as the rest of the file: a box with no written result is an UNRUN check, not a
passed one. A check that cannot be run gets "cannot be verified, and therefore we do not know" plus
the reason, and is not ticked.

**Three findings were overturned by measurement before this section was written.** Read this first,
because two of them mean a check below is confirming a correction rather than hunting a bug:

- **F4 is NOT a defect.** `Sync-OERStructureAccessPackage.ps1`'s build-failure path calls
  `ConvertTo-OERStructureResult ... -Action 'Failed'` as a literal at its one and only call site, and
  `-Action` is `[Parameter(Mandatory)]` with a seven-value `ValidateSet` -- an empty Action is
  structurally impossible there. Reproduced end-to-end through the real handler with mocks: the row
  reads `Failed`. The 7.3 transcript most likely lost the word to the very long, `-AutoSize`
  truncated Detail column when it was pasted. Check 14.5 re-runs it so the record is unambiguous, and
  a unit test now pins the Action so this can never become a real defect unnoticed.
- **F2's open question is ANSWERED, and the answer is neither of the two candidates the post-run
  block listed.** Read from `ConvertTo-OERPolicyBody.ps1`: with `-ApprovalStage @()` bound,
  `isApprovalRequiredForAdd` IS correctly derived as `false` from the declared stage count. The flag
  that was true on the wire is **`isApprovalRequiredForUpdate`**, carried forward from `-Existing`
  because the section 3 document never declared it -- and check 1.4 recorded the live policy as
  `RequireApprovalForUpdate: True`. So Graph's `InvalidApprovalStages` covers the UPDATE approval
  flag too, not only the ADD one. Checks 14.3 and 14.4 confirm that reading against the tenant.
- **F7 is a checklist error, not a code defect.** `Recurrence` is documented and consumed as the raw
  Graph object; `Resolve-OERAccessReviewChange` parses `pattern`/`range` out of it, which is why
  10.1.3 converged. 10.1.2's `Expect: Recurrence is OneTime` was simply wrong. Corrected in place;
  no live re-run needed.

**Setup for this section** -- same session variables as the rest of the file. `$Dv` is the
operator's own tenant preparation/verification helper; it lives outside this repository beside the
run notes, and only checks 14.10.1 and 14.10.2 use it.

```powershell
$Alias = '<your-tenant-alias>'; $Catalog = 'OER-DV-CAT'; $Package = 'oer-dv-ap'; $Policy = 'oer-dv-policy'
$Approver = '<approver-upn>'
$ProfileEscalation = '<profile-escalation-upn>'
$DocEscalation = '<document-escalation-upn>'
$RvPackage = 'oer-dv-review-ap'; $RvPolicy = 'oer-dv-review-policy'
$PimGroup = 'oer-dv-pim'
$Dv = './Initialize-OerDvPrereq.ps1'

New-Item -ItemType Directory -Path './live' -Force | Out-Null
Connect-OER -TenantAlias $Alias
$Pkg = Get-OERAccessPackage -Catalog $Catalog | Where-Object DisplayName -eq $Package
$Pol = Get-OERAccessPackageAssignmentPolicy -AccessPackage $Pkg.Id | Where-Object DisplayName -eq $Policy
$AllFields = @(
    'Id', 'DisplayName', 'AccessPackageId', 'AllowedTargetScope', 'Description', 'RequestorScope',
    'RequestorSettings', 'RequireApproval', 'RequireRequestorJustification', 'RequireApprovalForUpdate',
    'ApprovalStages', 'DurationInDays', 'DurationInHours', 'ExpirationDateTime', 'NotificationsDisabled')
```

**Rebuild first.** Every check below runs against the corrected build:
`./build.ps1 -Tasks build`, then re-import.

---

#### 14.0 Confirm the corrected build is loaded

- [x] **14.0 Two offline tells, no tenant call.** The reworded `approvalStages: []` Warning (F2) and
  the new clear-stages Warning must both be present. -- 2026-09-06

  ```powershell
  $P1 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requireApproval":true,"approvalStages":[]}]}]}'
  ($P1.Errors | Where-Object Path -like '*approvalStages').Message

  $P2 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","approvalStages":[]}]}]}'
  ($P2.Errors | Where-Object Path -like '*approvalStages').Message
  ```

  **Expect:** `$P1`'s Warning no longer claims the policy "is written with approval required and no
  approver stages at all and no request can ever be approved" -- it now says Microsoft Graph REFUSES
  the write with `InvalidApprovalStages` and the policy is reported `Failed` and left unchanged.
  `$P2` (a document that only clears the stages, declaring no approval flag) now produces a Warning
  of its own, naming `requireApprovalForUpdate` as the flag carried forward from the live policy.
  Before this build `$P2` produced no `approvalStages` Warning at all.
  **Failure looks like:** either message still matching the old text -- the build was not rebuilt or
  not re-imported, and every result below describes the wrong code.
  **Result:**
  ```powershell
> $P1 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","requireApproval":true,"approvalStages":[]}]}]}'  
> ($P1.Errors | Where-Object Path -like '*approvalStages').Message  
'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is declared as an empty array; Microsoft Graph refuses the write with 'InvalidApprovalStages: If approval is required, a valid list of stages must be provided.', so the assignment policy is reported Failed and left completely unchanged -- the document never converges and reports Failed on every run. Add at least one entry to 'approvalStages', or set 'requireApproval' to false.
>  
> $P2 = Test-OERStructure -Json '{"version":"1.0","accessPackages":[{"displayName":"probe","catalog":"probe","assignmentPolicies":[{"displayName":"probe","approvalStages":[]}]}]}'  
> ($P2.Errors | Where-Object Path -like '*approvalStages').Message  
'approvalStages' at accessPackages[0].assignmentPolicies[0] clears every approval stage while the policy is not declared to stop requiring approval; Microsoft Graph refuses that write with 'InvalidApprovalStages: If approval is required, a valid list of stages must be provided.' whenever approval is still required -- for ADD or for UPDATE. 'requireApprovalForUpdate' is carried forward from the live policy when the document does not declare it, so an undeclared flag is not an absent one: a live true value is re-sent with the emptied stage list and the assignment policy is reported Failed and left unchanged on every run. Declare 'requireApproval' false AND 'requireApprovalForUpdate' false alongside the empty 'approvalStages'. This applies to an EXISTING policy; on a create there is no live policy to carry a flag from.
>
  ```

---

#### 14.1 F1(b) -- the improved diagnostics, captured BEFORE the tenant is repaired

**Ordering corrected 2026-09-06 (post-run F13). The original "run 14.1 before 14.2" was wrong for
one of its own checks and cost a wasted run.** The two halves of 14.1 need OPPOSITE preconditions:

- **14.1.1 must run BEFORE 14.2.1**, while the lifecycle review is still missing. That broken
  reference is the one and only chance to see the new named error fire against a real tenant.
- **14.1.2 must run AFTER 14.2.1**, because it needs a lifecycle review to exist before it can be
  named. The first attempt returned `Access review definition not found.` for exactly that reason.
- **14.1.3 is independent** of both -- it uses an unrelated definition.

So the running order is **14.1.1 -> 14.2.1 -> 14.1.2 -> 14.1.3 -> 14.2.2** onward. 14.1.2 is left
here rather than moved into 14.2, so the F1(b) diagnostics stay together as one story.

- [x] **14.1.1 The dangling-lifecycle-review error is now named and actionable.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false -ErrorVariable DanglingErr |
      Format-Table Section, Item, Action, Detail -AutoSize
  $DanglingErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  If `./live/ap-restore.json` is gone (13.11 removed the folder), recreate it exactly as check 13.3
  writes it.

  **Expect:** still `Failed` -- the write genuinely cannot succeed while the referenced definition is
  missing, and nothing in this branch pretends otherwise. What must have changed is the DIAGNOSTIC:
  the error id reads `AccessPackageLifecycleReviewMissing` (not a bare Graph `NotFound`), and the
  message names the deleted definition id, says the policy's `reviewSettings` still references an
  access review definition that no longer exists, and states the remedy (re-create the Lifecycle
  access review on the policy, or clear "Require access reviews" on it).
  **Failure looks like:** the raw `NotFound: {"error":{"code":"","message":"BusinessFlow not found
  for id ..."}}` from check 13.3, unchanged -- the translation did not land.
  **Record:** the error id and the full message verbatim.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false -ErrorVariable DanglingErr |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: Assignment policy '00000000-0000-0000-0000-000000000003' could not be updated: its 'reviewSettings' still references access review definition '00000000-0000-0000-0000-000000000024', which no longer exists. Microsoft Graph validates that reference on every update of the policy, so every update fails with NotFound until it is resolved. Re-create the Lifecycle access review on this assignment policy, or turn off 'Require access reviews' on it.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': Assignment policy '00000000-0000-0000-0000-000000000003' could not be updated: its 'reviewSettings' still references access review definition '00000000-0000-0000-0000-000000000024', ...  
  
> $DanglingErr | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
AccessPackageLifecycleReviewMissing,Set-OERAccessPackageAssignmentPolicy  
Assignment policy '00000000-0000-0000-0000-000000000003' could not be updated: its 'reviewSettings' still references access review definition '00000000-0000-0000-0000-000000000024', which no longer exists. Microsoft Graph validates that reference on every update of the policy, so every update fails with NotFound until it is resolved. Re-create the Lifecycle access review on this assignment policy, or turn off 'Require access reviews' on it.  
AccessPackageLifecycleReviewMissing,Invoke-OERStructure  
Assignment policy '00000000-0000-0000-0000-000000000003' could not be updated: its 'reviewSettings' still references access review definition '00000000-0000-0000-0000-000000000024', which no longer exists. Microsoft Graph validates that reference on every update of the policy, so every update fails with NotFound until it is resolved. Re-create the Lifecycle access review on this assignment policy, or turn off 'Require access reviews' on it.  
>
  ```

- [ ] **14.1.2 `Remove-OERAccessReviewDefinition` now warns before deleting an access-package
  lifecycle review.** This is the guard for what F1 actually cost. **Answer `N` at any prompt --
  this check must NOT delete anything.** -- FAILED 2026-09-06 -- re-run after 14.2.1: NO scope warning under `-WhatIf` (finding F12)

  **Run this AFTER 14.2.1** -- it needs the re-created `oer-dv-ap - oer-dv-policy` to exist. See the
  ordering note at the top of 14.1.

  **RE-RUN 2026-09-06 after the F12 fix. Rebuild first (`./build.ps1 -Tasks build`) and re-import.**
  The first attempt failed: both warnings were written AFTER `ShouldProcess` returned true, so
  `-WhatIf` printed only the `What if:` line and a real delete showed them after the confirm prompt.
  Both `Write-Warning` calls now precede `ShouldProcess`, and the scope fact is folded into the
  `ShouldProcess` action text itself, so the `What if:` / `Confirm` line carries it too.

  ```powershell
  Get-OERAccessReviewDefinition -All | Select-Object DisplayName, AccessReviewDefinitionId, Scope | Format-List
  Remove-OERAccessReviewDefinition -DisplayName 'oer-dv-ap - oer-dv-policy' -WhatIf
  Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-ap - oer-dv-policy' |
      Select-Object DisplayName, AccessReviewDefinitionId
  ```

  **Expect, in this order:** the `This is irreversible` warning, then the scope warning, then the
  `What if:` line -- **both warnings BEFORE the `What if:`, and both visible under `-WhatIf`.** The
  `What if:` action text itself now names that the definition targets an access package's
  assignments. The scope warning still states the consequence **conditionally**: *if* this is that
  policy's Lifecycle access review, deleting it leaves the owning assignment policy un-updatable
  until the review is re-created or "Require access reviews" is turned off. The read-back must still
  show the definition present -- **nothing is deleted**.
  **Failure looks like:** the `What if:` line alone again (the fix did not land, or the build was not
  rebuilt), or the definition missing from the read-back (`-WhatIf` wrote something, which would be
  far worse than the ordering defect).

  **The warning is deliberately a SUPERSET, and the wording says so.** An ad-hoc access review over
  an access package has the SAME scope shape as that policy's Lifecycle review -- check 10.3.3's
  read-back proves it: the five reviews section 10 created all read
  `entitlementManagement/assignments?$filter=(accessPackage/id eq ... and assignmentPolicy/id eq ...)`.
  Scope alone cannot tell them apart, so the warning states the consequence conditionally and tells
  the operator to check the policy's Lifecycle tab. A false positive here is cheap; a false negative
  is what cost this run its entire teardown.
  **Failure looks like:** no extra warning at all, or a warning asserting UNCONDITIONALLY that this
  IS a lifecycle review -- the second would be the over-claim this correction removed.
  **Record:** every warning line verbatim.
  **Result:**
  ```powershell
# (first attempt, before 14.2.1 -- the lifecycle review did not exist yet)
> Remove-OERAccessReviewDefinition -DisplayName 'oer-dv-ap - oer-dv-policy' -WhatIf
Remove-OERAccessReviewDefinition: Access review definition not found.

# Re-run after 14.2.1 (definition 00000000-0000-0000-0000-000000000035 present):
> Remove-OERAccessReviewDefinition -DisplayName 'oer-dv-ap - oer-dv-policy' -WhatIf
What if: Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000035".
> Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-ap - oer-dv-policy' | Select-Object DisplayName, AccessReviewDefinitionId

DisplayName               AccessReviewDefinitionId
-----------               ------------------------
oer-dv-ap - oer-dv-policy 00000000-0000-0000-0000-000000000035

# FAILED: nothing was deleted (good), but the scope warning did NOT fire under -WhatIf -- only the
# "What if" line. Cross-check 14.6.4: on a REAL delete the order was Confirm prompt -> "This is
# irreversible" -> scope warning, i.e. BOTH warnings are written AFTER ShouldProcess returned true.
# A guard the operator sees only after confirming (and never under -WhatIf) is not a guard. See F12.
  ```

- [x] **14.1.3 An ordinary access review still gets no extra warning.** The guard must not cry wolf
  on every deletion. **Answer `N` at any prompt.** -- 2026-09-06

  ```powershell
  Remove-OERAccessReviewDefinition -DisplayName '<production-review-4>' -WhatIf
  ```

  Substitute any definition in the tenant whose scope is NOT an access package's assignments -- a
  group membership review or a directory role review. **Not** an ad-hoc review over an access
  package: those legitimately draw the warning (see 14.1.2).

  ```powershell
  Get-OERAccessReviewDefinition -All | Select-Object DisplayName, Scope | Format-List
  ```

  Pick one whose `Scope` does not contain `entitlementManagement/assignments`.

  **Expect:** the generic `This is irreversible` warning only -- no scope warning.
  **Failure looks like:** the scope warning firing on a definition whose scope does not target an
  access package's assignments, which would make the detection wrong rather than merely broad.
  **Result:**
  ```powershell
> Remove-OERAccessReviewDefinition -DisplayName '<production-review-4>' -WhatIf  
What if: Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000032".  
>
> Get-OERAccessReviewDefinition -All | Select-Object DisplayName, Scope | Format-List  
  
DisplayName : <production-review-1>  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000036' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000037')  
  
DisplayName : <production-review-2>  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000036' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000037')  
  
DisplayName : <production-review-3>  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000038' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000039')  
  
DisplayName : <production-review-4>  
Scope : /v1.0/groups/00000000-0000-0000-0000-000000000040/transitiveMembers/microsoft.graph.user/?$count=true&$filter=(userType eq 'Guest')  
  
DisplayName : <production-review-5>  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000041' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000042')  
  
>


  ```

---

#### 14.2 F1(a) -- repair the lifecycle review, then re-run 13.3 to 13.6

- [x] **14.2.1 Re-create the Lifecycle access review on `oer-dv-policy`.** -- 2026-09-06

  Portal: **ID Governance > Entitlement management > Access packages > `oer-dv-ap` > Policies >
  `oer-dv-policy` > Edit > Lifecycle**. If "Require access reviews" still renders as checked, un-tick
  it, **Save**, then re-tick it, re-enter check 1.5's configuration, and **Save** again -- the
  backing definition is only created on save, and the blade can keep rendering a setting whose
  definition is gone.

  Re-enter exactly what check 1.5 recorded: Starting on **9/7/2026**, frequency **Quarterly**,
  duration **21** days, reviewers **Specific reviewer(s)** = `oer-dv-approver`, if reviewers don't
  respond **No change**, show reviewer decision helpers **Yes**, require reviewer justification
  **Yes**, reminders **checked**.

  ```powershell
  Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-ap - oer-dv-policy' |
      Select-Object DisplayName, AccessReviewDefinitionId, Status
  (Invoke-MgGraphRequest -Uri "v1.0/identityGovernance/entitlementManagement/assignmentPolicies/$($Pol.Id)" -OutputType PSObject).reviewSettings
  ```

  **Expect:** a definition named `oer-dv-ap - oer-dv-policy` exists again with a NEW id (the old
  `00000000-0000-0000-0000-000000000024` is gone for good), and the policy's `reviewSettings.isEnabled` is `True`.
  **Record:** the new definition id, so 14.2.2's success can be attributed to this repair.
  **Result:**
  ```powershell
> Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-ap - oer-dv-policy' |  
> Select-Object DisplayName, AccessReviewDefinitionId, Status  
  
DisplayName AccessReviewDefinitionId Status  
----------- ------------------------ ------  
oer-dv-ap - oer-dv-policy 00000000-0000-0000-0000-000000000035 NotStarted  
  
> (Invoke-MgGraphRequest -Uri "v1.0/identityGovernance/entitlementManagement/assignmentPolicies/$($Pol.Id)" -OutputType PSObject).reviewSettings  
  
isEnabled : True  
expirationBehavior : keepAccess  
isRecommendationEnabled : True  
isReviewerJustificationRequired : True  
isSelfReview : False  
schedule : @{startDateTime=2026-09-06 21:59:59; expiration=; recurrence=}  
primaryReviewers : {@{@odata.type=#microsoft.graph.singleUser; userId=00000000-0000-0000-0000-000000000004; description=oer-dv-approver}}  
fallbackReviewers : {}  
  
>
# Full reviewSettings.schedule (ConvertTo-Json -Depth 5): expiration = afterDuration P25D; recurrence =
#   absoluteMonthly / interval 3, range noEnd. Start 2026-09-06T21:59:59Z = 9/7 local midnight, as entered.
# NEW definition id: 00000000-0000-0000-0000-000000000035 (old 00000000-0000-0000-0000-000000000024 is gone for good).
# Before the repair, Get-OERAccessReviewDefinition -All listed NO 'oer-dv-ap - oer-dv-policy' while the
# Lifecycle blade still rendered "Require access reviews" as checked -- the blade renders the policy's
# reviewSettings blob, not the existence of the definition (13.5 caveat confirmed, see 14.2.4).
# Deviation from 1.5: duration is now 25 d, not 21 d (portal re-entry). Not material for 14.2.2.
  ```

- [x] **14.2.2 Re-run 13.3 -- the restore that failed.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Updated` on the first run (description and approvalStages), `Unchanged` on the second
  -- 13.3's original Expect, now reachable.
  **Failure looks like:** `Failed` again with `BusinessFlow not found` naming the NEW id -- the
  repair did not take. `Failed` naming the OLD `00000000-0000-0000-0000-000000000024` id means the policy still carries the
  stale reference and the portal save did not rewrite `reviewSettings`.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (description)  
   
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>
  ```

- [x] **14.2.3 Re-run 13.4 -- the field-by-field comparison against the section 1 baseline.** -- 2026-09-06

  ```powershell
  $Final = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $BeforeAll = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $AllFields | ConvertTo-Json -Depth 10
  $FinalAll  = $Final | Select-Object $AllFields | ConvertTo-Json -Depth 10
  "identical: $($BeforeAll -eq $FinalAll)"
  Compare-Object -ReferenceObject ($BeforeAll -split "`n") -DifferenceObject ($FinalAll -split "`n")
  ```

  If `./live/policy-before.json` is gone, use check 1.3's pasted content to recreate it.

  **Expect:** `identical: True`, or `identical: False` where the ONLY remaining difference is the
  requestor scope (14.2.5 restores that), or an object id where check 1.3 recorded one. The
  Description difference 13.4 recorded must be GONE -- 14.2.2 rewrote it.
  **Failure looks like:** the Description still reading `declared-value-family regression check --
  approvalStages omitted` -- 14.2.2 reported `Updated` but did not land.
  **Result:**
  ```powershell
> $Final = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $BeforeAll = (Get-Content ./live/policy-before.json -Raw | ConvertFrom-Json) | Select-Object $AllFields | ConvertTo-Json -Depth 10   
> $FinalAll = $Final | Select-Object $AllFields | ConvertTo-Json -Depth 10  
> "identical: $($BeforeAll -eq $FinalAll)"  
identical: True  
> Compare-Object -ReferenceObject ($BeforeAll -split "`n") -DifferenceObject ($FinalAll -split "`n")  
>
# Post-run note: 13.11 had deleted ./live, so policy-before.json was recreated for this check. If it was
# regenerated from the LIVE policy (Get-OERAccessPackageAssignmentPolicy | ConvertTo-Json) this comparison
# is a tautology -- 14.2.5, run minutes later, still showed user-a/user-b in RequestorScope, which 1.3's
# baseline (approver only) would have flagged. The baseline comparison that counts is therefore 14.10.2:
# the pre-req script's PUT of %TEMP%\oer-dv\oer-dv-policy-baseline.json (captured at Setup, never
# overwritten) followed by its 32-point verify. Record here how the file was recreated.
  ```

- [x] **14.2.4 Re-run 13.5 -- the portal-only fields, now that the review definition is back.** -- 2026-09-06

  Open **... Policies > `oer-dv-policy` > Edit** and read both blades.

  **Expect:** Requestor information still carries check 1.5's one question, unchanged. Lifecycle now
  shows the re-created review with 14.2.1's configuration. 13.5's caveat ("the blade may still render
  a setting whose definition was deleted") is resolved either way -- record which of the two it was.
  **Result:**
  ```powershell
# Portal-only fields, read from Edit policy, 2026-09-06.
# Requestor information > Questions: 1 question, unchanged from 1.5 --
#   "oer-dv: why do you need this access? (setup question, section 1.5 / 5.5)" | Long text | Required | no localization | no regex
#   (second row is the portal's empty "Enter question" placeholder). Attributes: none, as in Setup.
# Lifecycle: Require access reviews = checked, now backed by the RE-CREATED definition
#   00000000-0000-0000-0000-000000000035 (14.2.1): Quarterly (absoluteMonthly/3), reviewer oer-dv-approver,
#   reviewer justification required, recommendations on, keepAccess if no response, duration 25 d (was 21 d in 1.5).
# 13.5 caveat resolved: the blade DID keep rendering "Require access reviews" as checked while definition
#   00000000-0000-0000-0000-000000000024 was deleted and Get-OERAccessReviewDefinition -All did not list it. The portal shows the
#   policy's reviewSettings, not the definition -- so the portal is NOT a valid check for F1; the
#   definition list (or the PUT itself) is.
  ```

- [x] **14.2.5 Re-run 13.6 -- the requestor scope. 13.4 contradicted its "Confirmed".** -- 2026-09-06

  ```powershell
  (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).AllowedTargetScope
  (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List *
  ```

  **Expect:** `specificDirectoryUsers` with `users` holding ONLY `oer-dv-approver`'s object id
  (`00000000-0000-0000-0000-000000000004` per check 1.3) -- Setup's original scope. If `oer-dv-user-a`/`oer-dv-user-b`
  (`00000000-0000-0000-0000-000000000005` / `00000000-0000-0000-0000-000000000006`) are still there, section 2's change was never rolled back and
  13.6's "Confirmed" was premature; restore it now through the portal or a document naming only the
  approver, and record what you did.
  **Failure looks like:** `person3@example.com` still in the list -- the prod account added for
  8.5 was not removed.
  **Result:**
  ```powershell
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).AllowedTargetScope  
specificDirectoryUsers  
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000005, 00000000-0000-0000-0000-000000000006}  
groups : {}  
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "requestorScope": { "scope": "SpecificDirectoryUsers", "users": [ "person1@example.com" ] } }  
> ] } ] }  
> '@ | Set-Content -Path './live/ap-scope-restore.json' -Encoding utf8  
>  
> Invoke-OERStructure -Path './live/ap-scope-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize # Updated (requestorScope)  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requestorScope)  
   
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List * # users: {00000000-0000-0000-0000-000000000004}  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
  
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).AllowedTargetScope  
specificDirectoryUsers  
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).RequestorScope | Format-List *  
  
scope : SpecificDirectoryUsers  
users : {00000000-0000-0000-0000-000000000004}  
groups : {}  
  
>
  ```

---

#### 14.3 F2 -- what does Graph actually accept when the stages are cleared?

This is the open question the post-run review left. The measurement above says the blocking flag is
`isApprovalRequiredForUpdate`, carried forward from the live policy. These probes decide whether
that reading is right, and therefore whether the new offline Warning gives correct advice.

**The live policy must be in the 14.2.2 state (one stage, approval required, approval-for-update
required) before starting.** Confirm with:

```powershell
Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
    Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
```

- [x] **14.3.1 Both approval flags declared false, stages cleared.** -- 2026-09-06

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy", "approvalStages": [],
          "requireApproval": false, "requireApprovalForUpdate": false }
      ] } ] }
'@ | Set-Content -Path './live/ap-clear-stages-flags-off.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/ap-clear-stages-flags-off.json'
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($After.ApprovalStages).Count
  $After | Select-Object RequireApproval, RequireApprovalForUpdate, RequireRequestorJustification
  ```

  **Expect (offline):** the catalog Warning only. The new clear-stages Warning must NOT fire here --
  this document declares both flags false, which is exactly what it asks for.
  **Expect (apply):** we do not know for certain, and that is the point. If the measurement is right,
  Graph ACCEPTS the PUT: `Updated` naming `approvalStages, requireApproval, requireApprovalForUpdate`,
  stage count `0`, both flags `False`. If it still refuses with `InvalidApprovalStages`, then some
  THIRD condition blocks a stage-less policy and the new Warning's advice is incomplete -- record the
  exact message, and that is the finding.
  **Record:** the Action, the full Detail, and the read-back.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "approvalStages": [],  
> "requireApproval": false, "requireApprovalForUpdate": false }  
> ] } ] }  
> '@ | Set-Content -Path './live/ap-clear-stages-flags-off.json' -Encoding utf8  
>  
> $V = Test-OERStructure -Path './live/ap-clear-stages-flags-off.json'  
> $V.Valid  
True  
> $V.Errors | Format-List Section, Item, Path, Message, Severity  
  
Section : accessPackages  
Item : oer-dv-ap  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-DV-CAT' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>  
> Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requireApproval, requireApprovalForUpdate, approvalStages)  
  
> $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($After.ApprovalStages).Count  
0  
> $After | Select-Object RequireApproval, RequireApprovalForUpdate, RequireRequestorJustification  
  
RequireApproval RequireApprovalForUpdate RequireRequestorJustification  
--------------- ------------------------ -----------------------------  
False False True  
  
>
  ```

- [x] **14.3.2 Convergence on whichever outcome 14.3.1 produced.** Apply the same document twice more. -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** conditional on 14.3.1. If it reported `Updated`, both further runs must report
  `Unchanged` -- a policy whose stages were cleared has to settle, or this is the issue #56
  non-convergence class all over again. If 14.3.1 reported `Failed`, both further runs must report
  `Failed` identically (an unappliable document should keep saying so, not alternate).
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
> Invoke-OERStructure -Path './live/ap-clear-stages-flags-off.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches  
  
>
  ```

- [x] **14.3.3 Only `requireApproval` declared false -- is `requireApprovalForUpdate` alone enough to
  block the write?** This is the check that isolates the flag, and its result decides the new
  Warning's wording. -- 2026-09-06 (second run, precondition met -- first run was inconclusive, see note)

  Restore a stage first, and confirm both flags are true again:

  ```powershell
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
      Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
  ```

  Then:

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy", "approvalStages": [], "requireApproval": false }
      ] } ] }
'@ | Set-Content -Path './live/ap-clear-stages-add-off-only.json' -Encoding utf8

  $V = Test-OERStructure -Path './live/ap-clear-stages-add-off-only.json'
  $V.Errors | Where-Object Path -like '*approvalStages' | Format-List Path, Message, Severity

  Invoke-OERStructure -Path './live/ap-clear-stages-add-off-only.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect (offline):** the new clear-stages Warning DOES fire here, naming
  `requireApprovalForUpdate` as the flag this document leaves carried forward.
  **Expect (apply):** if the measurement is right, `Failed` with `InvalidApprovalStages` -- proving
  `isApprovalRequiredForUpdate` alone blocks the write, which is exactly what the Warning claims. If
  it reports `Updated` instead, the Warning is over-warning: `requireApproval: false` alone would be
  sufficient, and the Warning should stop naming the second flag.
  **Record:** the Action and the full Detail.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requireApproval, approvalStages)  
  
> Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |  
> Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}  
  
RequireApproval RequireApprovalForUpdate Stages  
--------------- ------------------------ ------  
True False 1  
  
>  
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "approvalStages": [], "requireApproval": false }  
> ] } ] }  
> '@ | Set-Content -Path './live/ap-clear-stages-add-off-only.json' -Encoding utf8  
>  
> $V = Test-OERStructure -Path './live/ap-clear-stages-add-off-only.json'  
> $V.Errors | Where-Object Path -like '*approvalStages' | Format-List Path, Message, Severity  
  
Path : accessPackages[0].assignmentPolicies[0].approvalStages  
Message : 'approvalStages' at accessPackages[0].assignmentPolicies[0] clears every approval stage while the policy is not declared to stop requiring approval; Microsoft Graph refuses that write with 'InvalidApprovalStages: If approval is required, a valid list of stag  
es must be provided.' whenever approval is still required -- for ADD or for UPDATE. 'requireApprovalForUpdate' is carried forward from the live policy when the document does not declare it, so an undeclared flag is not an absent one: a live true value is re-  
sent with the emptied stage list and the assignment policy is reported Failed and left unchanged on every run. Declare 'requireApproval' false AND 'requireApprovalForUpdate' false alongside the empty 'approvalStages'. This applies to an EXISTING policy; on a  
create there is no live policy to carry a flag from.  
Severity : Warning  
  
>  
> Invoke-OERStructure -Path './live/ap-clear-stages-add-off-only.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requireApproval, approvalStages)  
  
>
# Post-run note: INCONCLUSIVE. The precondition "both flags true again" was NOT met -- the read-back after
# ap-restore.json shows RequireApprovalForUpdate = False. ap-restore.json (13.3's document) never declares
# requireApprovalForUpdate, so the False that 14.3.1 wrote was carried forward by the restore. The apply
# then reported Updated -- but only because the flag it was supposed to isolate was ALREADY false, so the
# write had nothing left to refuse. This result must NOT be read as "the Warning over-warns".
# Re-run, in this order:
#   1. PUT the flag back on:  { "displayName": "oer-dv-policy", "requireApprovalForUpdate": true }  (plus the
#      restore stage) -> read-back must show True / True / 1.
#   2. apply ap-clear-stages-add-off-only.json -> Expect Failed, InvalidApprovalStages (flag isolated).
#   3. a document with requireApprovalForUpdate: false ONLY (stages kept, requireApproval undeclared) is a
#      useful third probe: it shows whether the UPDATE flag alone, with a stage present, is accepted.
# Checklist finding: ap-restore.json is not a complete restore document -- add "requireApprovalForUpdate": true
# to it (13.3 / 14.3.4 / 14.7.3 all rely on it).

# ---- Second run, 2026-09-06, with an amended ap-restore.json that declares requireApprovalForUpdate: true ----
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
>     Format-Table Section, Item, Action, Detail -AutoSize
Section        Item      Action    Detail
-------        ----      ------    ------
accessPackages oer-dv-ap Unchanged access package properties match
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches
> Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
>     Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
RequireApproval RequireApprovalForUpdate Stages
--------------- ------------------------ ------
           True                     True      1
# (Unchanged because 14.10.2's baseline PUT had already put the flag back; precondition True / True / 1 met.)

> Invoke-OERStructure -Path './live/ap-clear-stages-add-off-only.json' -Include AccessPackages -Confirm:$false -ErrorVariable E33 |
>     Format-Table Section, Item, Action, Detail -AutoSize
Invoke-OERStructure: InvalidApprovalStages: If approval is required, a valid list of stages must be provided.
Section        Item      Action    Detail
-------        ----      ------    ------
accessPackages oer-dv-ap Unchanged access package properties match
accessPackages oer-dv-ap Failed    failed to update assignmentPolicy 'oer-dv-policy': InvalidApprovalStages: If approval is required, a valid list of stages must be provided.
> $E33 | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
InvalidApprovalStages,Set-OERAccessPackageAssignmentPolicy
InvalidApprovalStages: If approval is required, a valid list of stages must be provided.
InvalidApprovalStages,Invoke-OERStructure
InvalidApprovalStages: If approval is required, a valid list of stages must be provided.
> Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
>     Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
RequireApproval RequireApprovalForUpdate Stages
--------------- ------------------------ ------
           True                     True      1

# PROVEN: with requireApproval: false declared and requireApprovalForUpdate left undeclared (live True carried
# forward), Graph refuses the emptied stage list with InvalidApprovalStages and writes nothing. The UPDATE
# flag alone blocks the write -- exactly what the new clear-stages Warning (14.0, $P2) claims. Together with
# 14.3.1 (both flags false -> Updated, 0 stages, converges) the Warning's advice is complete and correct.
  ```

- [x] **14.3.4 Restore the baseline policy.** -- 2026-09-06 (second run with the amended ap-restore.json; first run left RequireApprovalForUpdate False, see note)

  ```powershell
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
      Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
  ```

  **Expect:** `Updated`, then one stage with both approval flags `True` again.
  **Failure looks like:** the policy cannot be restored because 14.3.1/14.3.3 left it stage-less and
  Graph will not re-add stages -- record that, it is a finding about the round trip, not about the
  teardown.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (requireApproval, approvalStages)  
  
> Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |  
> Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}  
  
RequireApproval RequireApprovalForUpdate Stages  
--------------- ------------------------ ------  
True False 1  
  
>
# Post-run note: NOT the baseline state -- Expect says both flags True, read-back is True / False / 1.
# 14.10.1's FAIL "RequireApprovalForUpdate AT DEFAULT" is this residue, not a deliberate one; 14.10.2's
# PUT of the Setup baseline repaired it (verify: RequireApprovalForUpdate ok). After re-running 14.3.3,
# restore with the amended ap-restore.json (requireApprovalForUpdate: true) and paste True / True / 1 here.

# ---- Second run, 2026-09-06, amended ap-restore.json ----
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
>     Format-Table Section, Item, Action, Detail -AutoSize
Section        Item      Action    Detail
-------        ----      ------    ------
accessPackages oer-dv-ap Unchanged access package properties match
accessPackages oer-dv-ap Unchanged assignmentPolicy 'oer-dv-policy' matches
> Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id |
>     Select-Object RequireApproval, RequireApprovalForUpdate, @{n='Stages';e={@($_.ApprovalStages).Count}}
RequireApproval RequireApprovalForUpdate Stages
--------------- ------------------------ ------
           True                     True      1
# Baseline state confirmed (Unchanged: the 14.3.3 probe wrote nothing, so there was nothing to restore).
  ```

---

#### 14.4 F2 -- the Warning text now matches what Graph does

- [x] **14.4 Re-run 8.1 and 8.2 on the corrected build.** -- 2026-09-06

  ```powershell
  $V = Test-OERStructure -Path './live/ap-contradiction.json'
  ($V.Errors | Where-Object Path -like '*approvalStages').Message

  Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false -ErrorVariable E84 |
      Format-Table Section, Item, Action, Detail -AutoSize
  @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count
  ```

  If `./live/ap-contradiction.json` is gone, recreate it exactly as check 8.1 writes it.

  **Expect:** the Warning now describes the OBSERVED outcome -- Graph refuses the write with
  `InvalidApprovalStages`, the policy is reported `Failed` and left unchanged -- instead of the old
  claim that the policy is written with approval required and no stages. The apply still reports
  `Failed` with the same Graph message as 8.2, and the stage count is still `1` (no partial write).
  **Record:** the Warning message verbatim, and confirm the apply behaviour is unchanged from 8.2 --
  this correction is text-only and must not have altered what the module does.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy", "requireApproval": true, "approvalStages": [] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-contradiction.json' -Encoding utf8^C  
> $V = Test-OERStructure -Path './live/ap-contradiction.json'  
> ($V.Errors | Where-Object Path -like '*approvalStages').Message  
'requireApproval' is true at accessPackages[0].assignmentPolicies[0] while 'approvalStages' is declared as an empty array; Microsoft Graph refuses the write with 'InvalidApprovalStages: If approval is required, a valid list of stages must be provided.', so the assignment policy is reported Failed and left completely unchanged -- the document never converges and reports Failed on every run. Add at least one entry to 'approvalStages', or set 'requireApproval' to false.
>  
> Invoke-OERStructure -Path './live/ap-contradiction.json' -Include AccessPackages -Confirm:$false -ErrorVariable E84 |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Failed failed to update assignmentPolicy 'oer-dv-policy': InvalidApprovalStages: If approval is required, a valid list of stages must be provided.  
  
> @((Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages).Count  
1
  ```

---

#### 14.5 F4 -- the build-failure row reads `Failed`

- [x] **14.5 Re-run 7.3's apply, and read the Action out of the object rather than off the table.** -- 2026-09-06
  The 7.3 transcript could not settle this because `-AutoSize` truncated a very long Detail; reading
  the property directly removes the ambiguity.

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessPackages": [
    { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,
      "assignmentPolicies": [
        { "displayName": "oer-dv-policy",
          "approvalStages": [ { "users": [ "person1@example.com" ] } ] }
      ] } ] }
'@ | Set-Content -Path './live/ap-durationdays-omitted.json' -Encoding utf8

  $Before = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  $R = @(Invoke-OERStructure -Path './live/ap-durationdays-omitted.json' -Include AccessPackages -Confirm:$false)
  $R | Format-List Section, Item, Action, Detail
  $R | Where-Object Detail -like 'failed to build*' | Select-Object -ExpandProperty Action

  $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id
  @($After.ApprovalStages).Count
  "policy unchanged: $((($Before | Select-Object $AllFields | ConvertTo-Json -Depth 10)) -eq (($After | Select-Object $AllFields | ConvertTo-Json -Depth 10)))"
  ```

  **Expect:** the `Action` property reads exactly `Failed` -- confirming F4 was a transcript artifact,
  as the code reading and the mocked end-to-end reproduction both say. The policy is byte-identical
  before and after (`policy unchanged: True`); a failed build must write nothing.
  **Failure looks like:** an empty or non-`Failed` Action, which would mean the reproduction missed a
  path the live tenant takes -- record it verbatim, it would be a real defect after all.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "oer-dv-ap", "catalog": "OER-DV-CAT", "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "approvalStages": [ { "users": [ "person1@example.com" ] } ] }  
> ] } ] }  
> '@ | Set-Content -Path './live/ap-durationdays-omitted.json' -Encoding utf8  
>  
> $Before = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> $R = @(Invoke-OERStructure -Path './live/ap-durationdays-omitted.json' -Include AccessPackages -Confirm:$false)  
Invoke-OERStructure: Cannot validate argument on parameter 'Days'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again.  
> $R | Format-List Section, Item, Action, Detail  
  
Section : accessPackages  
Item : oer-dv-ap  
Action : Unchanged  
Detail : access package properties match  
  
Section : accessPackages  
Item : oer-dv-ap  
Action : Failed  
Detail : failed to build assignmentPolicy 'oer-dv-policy': Cannot validate argument on parameter 'Days'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again. 
  
> $R | Where-Object Detail -like 'failed to build*' | Select-Object -ExpandProperty Action  
Failed  
>  
> $After = Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id  
> @($After.ApprovalStages).Count  
1  
> "policy unchanged: $((($Before | Select-Object $AllFields | ConvertTo-Json -Depth 10)) -eq (($After | Select-Object $AllFields | ConvertTo-Json -Depth 10)))"  
policy unchanged: True  
>
  ```

---

#### 14.6 F6 -- a clean access review create leaves the error stream empty

- [x] **14.6.1 Create one access review and inspect `-ErrorVariable`.** -- 2026-09-06

  ```powershell
  @'
{
  "version": "1.0",
  "tenantAlias": "<your-tenant-alias>",
  "accessReviews": [
    { "displayName": "oer-dv-f6-review", "accessPackage": "oer-dv-review-ap",
      "assignmentPolicy": "oer-dv-review-policy", "recurrence": null,
      "descriptionForAdmins": "F6 error-stream check",
      "descriptionForReviewers": "Please review your own access.", "reviewers": [] }
  ]
}
'@ | Set-Content -Path './live/ar-f6.json' -Encoding utf8

  $E = $null
  Invoke-OERStructure -Path './live/ar-f6.json' -Include AccessReviews -Confirm:$false -ErrorVariable E |
      Format-Table Section, Item, Action, Detail -AutoSize
  "error count: $(@($E).Count)"
  $E | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }
  ```

  **Expect:** `Created`, and **`error count: 0`**. Before this correction the same call produced two
  `AccessReviewDefinitionNotFound,Get-OERAccessReviewDefinition` records for a create that succeeded.
  **Failure looks like:** any count above `0`. Record each id and message -- if a DIFFERENT error id
  now appears, that is a new leak, not the old one.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> { "displayName": "oer-dv-f6-review", "accessPackage": "oer-dv-review-ap",  
> "assignmentPolicy": "oer-dv-review-policy", "recurrence": null,  
> "descriptionForAdmins": "F6 error-stream check",  
> "descriptionForReviewers": "Please review your own access.", "reviewers": [] }  
> ]  
> }  
> '@ | Set-Content -Path './live/ar-f6.json' -Encoding utf8  
>  
> $E = $null  
> Invoke-OERStructure -Path './live/ar-f6.json' -Include AccessReviews -Confirm:$false -ErrorVariable E |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-f6-review Created created access review 'oer-dv-f6-review' (recurrence: OneTime)  
  
> "error count: $(@($E).Count)"  
error count: 0  
> $E | ForEach-Object { $_.FullyQualifiedErrorId; $_.Exception.Message }  
>
  ```

- [x] **14.6.2 The same call under `$ErrorActionPreference = 'Stop'` still completes.** This is the
  operator-facing half: an apply that writes phantom errors stops a strict script dead. -- 2026-09-06

  ```powershell
  $Saved = $ErrorActionPreference
  try {
      $ErrorActionPreference = 'Stop'
      Invoke-OERStructure -Path './live/ar-f6.json' -Include AccessReviews -Confirm:$false |
          Format-Table Section, Item, Action, Detail -AutoSize
  } finally { $ErrorActionPreference = $Saved }
  ```

  **Expect:** `Unchanged` (the review already exists from 14.6.1) and no terminating error. This is
  the second apply, so it takes the existence-FOUND branch. To exercise the create path under `Stop`
  as well, delete the review with 14.6.4 first and re-run this block instead of 14.6.1.
  **Failure looks like:** a terminating error ending the pipeline.
  **Result:**
  ```powershell
> try {  
> $ErrorActionPreference = 'Stop'  
> Invoke-OERStructure -Path './live/ar-f6.json' -Include AccessReviews -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
> } finally { $ErrorActionPreference = $Saved }  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-dv-f6-review Unchanged access review 'oer-dv-f6-review' already matches  
  
>
  ```

- [ ] **14.6.3 A REAL read failure must still be reported, not swallowed.** This is the constraint
  that matters: Sprint 1 exists because a failed read was booked as an empty fact. The correction
  must silence a clean not-found WITHOUT silencing a genuine failure.

  Cannot be provoked from a normal session -- the read fails only on throttle, permission or
  transport error. **If you can run it at all**, do so by connecting with an identity that lacks
  `AccessReview.Read.All` and re-running 14.6.1; otherwise write "cannot be verified, and therefore
  we do not know" plus the reason, and rely on the unit coverage named below.

  **Expect:** the apply reports `Failed` for the item with the underlying permission error, and does
  NOT create the review. A `Created` under a failing read would be the Sprint 1 defect class
  reintroduced by this very correction.
  **Result:**
  ```powershell
  # Unit coverage standing in for the live case, if it cannot be provoked:
  # tests/Unit/Private/Sync-OERStructureAccessReview.Tests.ps1 -- the existence-probe tests
# cannot be verified, and therefore we do not know -- no identity without AccessReview.Read.All is available
# in this session to provoke a real read failure, and throttling/transport errors cannot be induced on demand.
# Standing in: the existence-probe unit tests named above. Not ticked, per the house rule.
  ```

- [x] **14.6.4 Delete the review 14.6.1 created. By NAME, never by pattern.** -- 2026-09-06

  ```powershell
  Remove-OERAccessReviewDefinition -DisplayName 'oer-dv-f6-review'
  Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-f6-review'
  ```

  **Expect:** the prompt and the irreversible warning, then nothing from the read-back. **The scope
  warning from 14.1.2 DOES fire here, and that is correct** -- `oer-dv-f6-review` is scoped to
  `oer-dv-review-ap`'s assignments, the same shape a Lifecycle review has, and the detection is a
  deliberate superset. Read the warning, confirm from the policy's Lifecycle tab that this review is
  not the one it references, and proceed. That two-step is exactly the discipline the warning exists
  to impose.
  **Failure looks like:** using a `-Match`/`-like` loop instead of the name. That is exactly what
  cost F1: `Get-OERAccessReviewDefinition -All | ? DisplayName -Match OER` swept up the access
  package's own lifecycle review and four unrelated leftovers.
  **Result:**
  ```powershell
> Remove-OERAccessReviewDefinition -DisplayName 'oer-dv-f6-review'  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000043".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
WARNING: Deleting access review definition '00000000-0000-0000-0000-000000000043'. This is irreversible.  
WARNING: Access review definition '00000000-0000-0000-0000-000000000043' targets an access package's assignments (its scope query targets entitlementManagement/assignments). That may be the assignment policy's own Lifecycle access review, or an ordinary review created over the same access package -- the two are indistinguishable by scope alone. If it is the Lifecycle access review -- the one configured under 'Lifecycle > Require access reviews' on the assignment policy -- then deleting it leaves that policy un-updatable: the policy carries 'reviewSettings' forward on every update and Microsoft Graph refuses the write while it references a definition that no longer exists. To tell the two apart, check that assignment policy's 'Lifecycle' tab: an ad-hoc review created by hand or by a document is not referenced there. If this is the Lifecycle access review, re-create it on that policy, or turn off 'Require access reviews' on it, to make the policy updatable again.
> Get-OERAccessReviewDefinition -All | Where-Object DisplayName -eq 'oer-dv-f6-review'  
>
  ```

---

#### 14.7 F5 -- the substitution warning names only what was substituted

- [x] **14.7.1 Re-run 7.1 on the corrected build.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-alternateusers-declared.json' -Include AccessPackages -Confirm:$false -WarningVariable W |
      Format-Table Section, Item, Action, Detail -AutoSize
  $W
  (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages[0] | Select-Object Users, AlternateUsers
  ```

  If `./live/ap-alternateusers-declared.json` is gone, recreate it exactly as check 7.1 writes it.

  **Expect:** the Warning names ONLY the PrimaryApprovers substitution. It must no longer say
  `(1 PrimaryApprovers, 1 EscalationApprovers)` on a document whose own `alternateUsers` survived --
  that phrasing reads as the pre-#68 behaviour and was the finding. `AlternateUsers` still resolves
  to `oer-dv-esc-doc`'s object id (`00000000-0000-0000-0000-000000000007`), unchanged: this correction is text-only.
  **Failure looks like:** the counts unchanged, or `AlternateUsers` now resolving to
  `oer-dv-esc-profile` (`00000000-0000-0000-0000-000000000008`) -- the second would mean the text fix broke #68's actual
  guard, which is far worse than the wording.
  **Result:**
  ```powershell
> @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-dv-ap",  
> "catalog": "OER-DV-CAT",  
> "resourceRoles": null,  
> "assignmentPolicies": [  
> { "displayName": "oer-dv-policy",  
> "approvalStages": [  
> { "durationDays": 14, "users": [], "alternateUsers": [ "person2@example.com" ] }  
> ] }  
> ]  
> }  
> ]  
> }  
> '@ | Set-Content -Path './live/ap-alternateusers-declared.json' -Encoding utf8  
> Invoke-OERStructure -Path './live/ap-alternateusers-declared.json' -Include AccessPackages -Confirm:$false -WarningVariable W |  
> Format-Table Section, Item, Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers) instead of the zero-approver stage the document tried to express.
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
  
> $W  
Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers) instead of the zero-approver stage the document tried to express.
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages[0] | Select-Object Users, AlternateUsers  
  
users alternateUsers  
----- --------------  
{00000000-0000-0000-0000-000000000004} {00000000-0000-0000-0000-000000000007}  
  
>
  ```

- [x] **14.7.2 And 7.2's warning is unchanged -- the fallback still names both.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-alternateusers-omitted.json' -Include AccessPackages -Confirm:$false -WarningVariable W2 |
      Format-Table Section, Item, Action, Detail -AutoSize
  $W2
  (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages[0] | Select-Object Users, AlternateUsers
  ```

  **Expect:** here BOTH defaults really are substituted, so the Warning still names PrimaryApprovers
  AND EscalationApprovers, and `AlternateUsers` resolves to `oer-dv-esc-profile` (`00000000-0000-0000-0000-000000000008`).
  The correction must distinguish the two cases, not delete the escalation half from both.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-alternateusers-omitted.json' -Include AccessPackages -Confirm:$false -WarningVariable W2 |  
> Format-Table Section, Item, Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared no approver keys at all; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) (back-compat).  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
  
> $W2  
Sync-OERStructureAccessPackage: assignmentPolicy 'oer-dv-policy' stage 1 declared no approver keys at all; substituting Tenant Profile 'Omnicit' defaults (1 PrimaryApprovers, 1 EscalationApprovers) (back-compat).   
> (Get-OERAccessPackageAssignmentPolicy -Id $Pol.Id).ApprovalStages[0] | Select-Object Users, AlternateUsers  
  
users alternateUsers  
----- --------------  
{00000000-0000-0000-0000-000000000004} {00000000-0000-0000-0000-000000000008}  
  
>
  ```

- [x] **14.7.3 Restore the baseline stage.** -- 2026-09-06

  ```powershell
  Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** `Updated`, one stage, `oer-dv-approver` as the approver, no alternate users.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path './live/ap-restore.json' -Include AccessPackages -Confirm:$false |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-dv-ap Unchanged access package properties match  
accessPackages oer-dv-ap Updated updated assignmentPolicy 'oer-dv-policy' (approvalStages)  
  
>
  ```

---

#### 14.8 F10 -- the PIM owner policy restore is on record

- [x] **14.8 Read back what 13.8 said it restored.** 13.8's result was a bare "Confirmed" with no
  read-back pasted, so the restore is asserted rather than evidenced. -- 2026-09-06

  ```powershell
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner |
      Select-Object ActivationMaxHours, EligibleDuration, ActiveDuration, AllowPermanentEligibility, ActivationEnabledRules
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType member |
      Select-Object ActivationMaxHours, EligibleDuration, ActiveDuration, AllowPermanentEligibility, ActivationEnabledRules
  ```

  **Expect:** owner reads `ActivationMaxHours 3`, `EligibleDuration P150D`, `ActiveDuration P60D`,
  `AllowPermanentEligibility False`, `ActivationEnabledRules {Justification}` -- check 11.1's
  capture, i.e. section 11's change from 3 to 6 is rolled back. Member is unchanged from 11.1:
  `ActivationMaxHours 8`, `P200D`, `P90D`, `AllowPermanentEligibility True`.
  **Failure looks like:** owner still reading `ActivationMaxHours 6` -- 13.8 was not actually done.
  **Result:**
  ```powershell
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType owner |  
> Select-Object ActivationMaxHours, EligibleDuration, ActiveDuration, AllowPermanentEligibility, ActivationEnabledRules  
  
ActivationMaxHours : 3  
EligibleDuration : P150D  
ActiveDuration : P60D  
AllowPermanentEligibility : False  
ActivationEnabledRules : {Justification}  
  
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType member |  
> Select-Object ActivationMaxHours, EligibleDuration, ActiveDuration, AllowPermanentEligibility, ActivationEnabledRules  
  
ActivationMaxHours : 8  
EligibleDuration : P200D  
ActiveDuration : P90D  
AllowPermanentEligibility : True  
ActivationEnabledRules : {Justification}  
   
>
  ```

---

#### 14.9 F11 -- cancel the pending access request

- [x] **14.9 The 8.5 request is still `Pending approval` and must be closed.** The pre-req script's
  `-RestoreWrites` cannot do this; it is a request, not policy state. -- 2026-09-06

  Portal: **My Access (https://myaccess.microsoft.com) > Request history >** the `oer-dv-ap` request
  **> Cancel**. Or, as an admin: **ID Governance > Entitlement management > Access packages >
  `oer-dv-ap` > Requests >** the request **> Deny**.

  ```powershell
  # Read-back through Graph (the module has no assignment-request cmdlet):
  Invoke-MgGraphRequest -Method GET -OutputType PSObject `
      -Uri 'v1.0/identityGovernance/entitlementManagement/assignmentRequests/00000000-0000-0000-0000-000000000009' |
      Select-Object id, state, status, createdDateTime
  ```

  **Expect:** `state` is no longer `submitted` and `status` no longer `Pending approval` -- it reads
  cancelled or denied. Paste the Requests blade state as well.
  **Failure looks like:** still pending -- the tenant keeps an open request against a disposable test
  package indefinitely.
  **Result:**
  ```powershell
# Verified tt is removed.
> Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri 'v1.0/identityGovernance/entitlementManagement/assignmentRequests/00000000-0000-0000-0000-000000000009' |  
> Select-Object id, state, status, createdDateTime  
Invoke-MgGraphRequest: GET https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests/00000000-0000-0000-0000-000000000009  
HTTP/1.1 404 Not Found  
Transfer-Encoding: chunked  
Vary: Accept-Encoding  
Strict-Transport-Security: max-age=31536000  
request-id: 00000000-0000-0000-0000-000000000044  
client-request-id: 00000000-0000-0000-0000-000000000045  
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"002","RoleInstance":"GV3PEPF0000090B"}}  
Date: Sun, 06 Sep 2026 18:45:58 GMT  
Content-Type: application/json  
  
{"error":{"code":"RequestNotFound","message":"The request was not found.","details":[],"innerError":{"date":"2026-09-06T18:45:58","request-id":"00000000-0000-0000-0000-000000000044","client-request-id":"00000000-0000-0000-0000-000000000045"}}}
>
  ```

---

#### 14.10 Final -- the tenant is back where Setup left it

- [x] **14.10.1 The pre-req verifier passes again.** -- 2026-09-06

  ```powershell
  & $Dv -SkipUsers -SkipObjects
  ```

  **Expect: conditional on WHEN you run it.** **Corrected 2026-09-06 (post-run F13).**
  - Run BEFORE 14.10.2, i.e. with the tenant still mid-teardown: expect **32/32 PASS**.
  - Run AFTER 14.10.2 and after 13.9 emptied the Tenant Profile `Defaults`: the verifier now counts
    an EMPTY `Defaults` as **PASS**, naming it as the torn-down state, so this is **32/32** as well.
    Before that script fix an emptied `Defaults` reported FAIL, and a verify run scored 31/32 with
    only that line red -- reporting the tenant as broken for being in exactly the state teardown put
    it in. A PARTIALLY or wrongly populated `Defaults` is still a FAIL.
  **Failure looks like:** any FAIL other than that -- record which check, and whether it is something
  this section was supposed to have repaired. A `RequireApprovalForUpdate AT DEFAULT` FAIL means
  14.3's residue was not cleared; 14.10.2's baseline PUT clears it.
  **Result:**
  ```powershell
> & $Dv -SkipUsers -SkipObjects  
  
== Phase 3: verify prerequisites  
[PASS] user Approver person1@example.com accountEnabled=False  
[PASS] user ProfileEscalation person7@example.com accountEnabled=False  
[PASS] user DocEscalation person2@example.com accountEnabled=False  
[PASS] user SpecificUserA person5@example.com accountEnabled=False  
[PASS] user SpecificUserB person6@example.com accountEnabled=False  
[PASS] user Fallback person4@example.com accountEnabled=False  
[PASS] escalation users differ profile vs document escalation are distinct  
[PASS] OER-DV-CAT 00000000-0000-0000-0000-000000000002  
[PASS] oer-dv-ap 00000000-0000-0000-0000-000000000001  
[PASS] oer-dv-policy: RequireApproval ok  
[PASS] oer-dv-policy: RequireRequestorJustification ok  
[FAIL] oer-dv-policy: RequireApprovalForUpdate AT DEFAULT -- section 5 cannot detect a reset  
[PASS] oer-dv-policy: AllowedTargetScope not allMemberUsers ok  
[PASS] oer-dv-policy: ApprovalStages >= 1 ok  
[PASS] oer-dv-policy: DurationInDays set ok  
[PASS] oer-dv-policy: Description distinctive ok  
[PASS] oer-dv-policy: questions 1 question(s) (portal-only field, 1.5 / 5.5)  
[PASS] oer-dv-policy: reviewSettings.isEnabled True (portal-only field, 1.5 / 5.4)  
[PASS] oer-dv-ap: other policies none  
[PASS] oer-dv-policy-new absent section 9 creates it  
[PASS] oer-dv-review-policy: no lifecycle review reviewSettings.isEnabled=False (must be False)  
[PASS] review oer-dv-onetime-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-startdate-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-enddate-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-test-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-second-test-review absent absent (correct, the checklist creates it)  
[PASS] oer-dv-pim member policy eligible=200d active=90d activation=8h (must NOT change in 11.3)  
[PASS] oer-dv-pim owner policy eligible=150d active=60d activation=3h rules=Justification (11.2 sets activation 6)  
[PASS] AU oer-dv-au absent absent (correct, the checklist creates it)  
[PASS] group oer-dv-au-grp absent absent (correct, the checklist creates it)  
[PASS] profile Omnicit Defaults PrimaryApprovers=person1@example.com EscalationApprovers=person7@example.com  
[PASS] baseline policy JSON C:\Users\SEGOTPHA\AppData\Local\Temp\oer-dv\oer-dv-policy-baseline.json  
  
Verify: 32 checks, 1 FAIL, 0 WARN -- fix before running the checklist  
  
== Paste into the session (the checklist's Setup variable block, filled in)  
  
$Alias = 'Omnicit'  
$Catalog = 'OER-DV-CAT'  
$Package = 'oer-dv-ap'  
$Policy = 'oer-dv-policy'  
$NewPolicy = 'oer-dv-policy-new'  
$Approver = 'person1@example.com'  
$ProfileEscalation = 'person7@example.com'  
$DocEscalation = 'person2@example.com'  
$SpecificUserA = 'person5@example.com'  
$SpecificUserB = 'person6@example.com'  
$RvPackage = 'oer-dv-review-ap'  
$RvPolicy = 'oer-dv-review-policy'  
$Fallback = 'person4@example.com'  
$PimGroup = 'oer-dv-pim'  
$Au = 'oer-dv-au'  
$AuGroup = 'oer-dv-au-grp'  
$Doc = './live/doc.json'  
# review names: oer-dv-onetime-review, oer-dv-startdate-review, oer-dv-enddate-review, oer-dv-test-review, oer-dv-second-test-review  
# baseline files: C:\Users\SEGOTPHA\AppData\Local\Temp\oer-dv  
  
Disconnected. Next: Connect-OER -TenantAlias Omnicit and section 1.  
# Post-run note: the one FAIL (RequireApprovalForUpdate AT DEFAULT) is 14.3's residue -- see 14.3.3/14.3.4 --
# not an accepted deviation. It was cleared by 14.10.2's baseline PUT. A verify run AFTER 14.10.2 shows
# one different FAIL (profile Defaults empty), which IS the intended teardown state (13.9), so 31/32 with
# only the Defaults line failing is the correct end state for a torn-down tenant.
  ```

- [x] **14.10.2 The baseline PUT succeeds.** This is the check that failed implicitly all through
  section 13, because F1's dangling reference refused every PUT. -- 2026-09-06

  ```powershell
  & $Dv -SkipUsers -RestoreWrites
  ```

  **Expect:** the saved baseline policy is PUT back with no error. Until 14.2.1 lands this fails with
  the `BusinessFlow not found` error -- if it still does after 14.2, the repair did not take and
  14.2.2's result is wrong.
  **Result:**
  ```powershell
> & $Dv -SkipUsers -RestoreWrites  
  
== Phase 2: Connect-OER interactive for object creation  
  
== Catalog and access packages  
OER-DV-CAT (00000000-0000-0000-0000-000000000002)  
oer-dv-ap (00000000-0000-0000-0000-000000000001); oer-dv-review-ap (00000000-0000-0000-0000-000000000012)  
oer-dv-policy exists (00000000-0000-0000-0000-000000000003)  
oer-dv-review-policy exists  
  
== PIM-for-Groups group  
oer-dv-pim (00000000-0000-0000-0000-000000000016)  
member (already there)  
owner (already there)  
member policy set  
owner policy set  
  
== Tenant Profile 'Omnicit' Defaults  
Defaults set (other keys preserved)  
  
== Restoring what the checklist wrote (section 13 aid)  
13.1 oer-dv-policy-new not present  
13.2 oer-dv-onetime-review not present  
13.2 oer-dv-startdate-review not present  
13.2 oer-dv-enddate-review not present  
13.2 oer-dv-test-review not present  
13.2 oer-dv-second-test-review not present  
13.3 oer-dv-policy restored from baseline  
13.7 oer-dv-au-grp not present  
13.7 oer-dv-au not present  
13.8 owner policy restored  
13.9 Defaults restored  
  
== Phase 3: verify prerequisites  
[PASS] user Approver person1@example.com accountEnabled=False  
[PASS] user ProfileEscalation person7@example.com accountEnabled=False  
[PASS] user DocEscalation person2@example.com accountEnabled=False  
[PASS] user SpecificUserA person5@example.com accountEnabled=False  
[PASS] user SpecificUserB person6@example.com accountEnabled=False  
[PASS] user Fallback person4@example.com accountEnabled=False  
[PASS] escalation users differ profile vs document escalation are distinct  
[PASS] OER-DV-CAT 00000000-0000-0000-0000-000000000002  
[PASS] oer-dv-ap 00000000-0000-0000-0000-000000000001  
[PASS] oer-dv-policy: RequireApproval ok  
[PASS] oer-dv-policy: RequireRequestorJustification ok  
[PASS] oer-dv-policy: RequireApprovalForUpdate ok  
[PASS] oer-dv-policy: AllowedTargetScope not allMemberUsers ok  
[PASS] oer-dv-policy: ApprovalStages >= 1 ok  
[PASS] oer-dv-policy: DurationInDays set ok  
[PASS] oer-dv-policy: Description distinctive ok  
[PASS] oer-dv-policy: questions 1 question(s) (portal-only field, 1.5 / 5.5)  
[PASS] oer-dv-policy: reviewSettings.isEnabled True (portal-only field, 1.5 / 5.4)  
[PASS] oer-dv-ap: other policies none  
[PASS] oer-dv-policy-new absent section 9 creates it  
[PASS] oer-dv-review-policy: no lifecycle review reviewSettings.isEnabled=False (must be False)  
[PASS] review oer-dv-onetime-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-startdate-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-enddate-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-test-review absent absent (correct, the checklist creates it)  
[PASS] review oer-dv-second-test-review absent absent (correct, the checklist creates it)  
[PASS] oer-dv-pim member policy eligible=200d active=90d activation=8h (must NOT change in 11.3)  
[PASS] oer-dv-pim owner policy eligible=150d active=60d activation=3h rules=Justification (11.2 sets activation 6)  
[PASS] AU oer-dv-au absent absent (correct, the checklist creates it)  
[PASS] group oer-dv-au-grp absent absent (correct, the checklist creates it)  
[FAIL] profile Omnicit Defaults PrimaryApprovers= EscalationApprovers=  
[PASS] baseline policy JSON C:\Users\SEGOTPHA\AppData\Local\Temp\oer-dv\oer-dv-policy-baseline.json  
  
Verify: 32 checks, 1 FAIL, 0 WARN -- fix before running the checklist  
  
== Paste into the session (the checklist's Setup variable block, filled in)  
  
$Alias = 'Omnicit'  
$Catalog = 'OER-DV-CAT'  
$Package = 'oer-dv-ap'  
$Policy = 'oer-dv-policy'  
$NewPolicy = 'oer-dv-policy-new'  
$Approver = 'person1@example.com'  
$ProfileEscalation = 'person7@example.com'  
$DocEscalation = 'person2@example.com'  
$SpecificUserA = 'person5@example.com'  
$SpecificUserB = 'person6@example.com'  
$RvPackage = 'oer-dv-review-ap'  
$RvPolicy = 'oer-dv-review-policy'  
$Fallback = 'person4@example.com'  
$PimGroup = 'oer-dv-pim'  
$Au = 'oer-dv-au'  
$AuGroup = 'oer-dv-au-grp'  
$Doc = './live/doc.json'  
# review names: oer-dv-onetime-review, oer-dv-startdate-review, oer-dv-enddate-review, oer-dv-test-review, oer-dv-second-test-review  
# baseline files: C:\Users\SEGOTPHA\AppData\Local\Temp\oer-dv  
  
Disconnected. Next: Connect-OER -TenantAlias Omnicit and section 1.  
>
# Post-run note: PASSED for what it tests -- "13.3 oer-dv-policy restored from baseline" with no error, and
# RequireApprovalForUpdate / Description / scope all read ok afterwards. The FAIL on profile Defaults is by
# design: -RestoreWrites puts profile-defaults-before.json (empty, pre-Setup) back as 13.9, then the verify
# phase expects Setup's Defaults. Pre-req script nit: with -RestoreWrites the verify should treat empty
# Defaults as PASS (teardown state) or skip that line.
  ```

- [x] **14.10.3 Clean up.** -- 2026-09-06

  ```powershell
  Remove-Item -Path './live' -Recurse -Force
  Disconnect-OER
  ```

  **Expect:** both complete without error. A later `Get-OER*` call re-authenticates on its own --
  `Initialize-OERAuth` runs at every cmdlet's entry, so expect a fresh sign-in prompt rather than a
  failure. `Connect-OER` is an optional pre-auth shortcut, never a precondition.
  **Result:**
  ```powershell
> Remove-Item -Path './live' -Recurse -Force  
> Disconnect-OER  
>
  ```
