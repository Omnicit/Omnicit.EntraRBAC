# Live verification checklist -- an unread role map or inventory section is never empty (fix/unread-role-map-and-section-are-partial)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s82-`.** The
prerequisite script creates one plain security group, `oer-s82-grp`, and one administrative unit with
hidden membership, `oer-s82-au`, with the group as its only member. It assigns no directory role,
changes no policy and touches no object outside the prefix. Every other check only READS the tenant:
the exports read it, and the one apply in this file (2.2) is a `-Prune -WhatIf` plan, run behind a
read-only fence that refuses every Microsoft Graph request that is not a read (see Setup). Section 3
runs offline.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS82Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 1 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all, so that every read
of the export is refused; a 403 there is the expected answer, not a stop. Every sign-in is app-only;
nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`; read the plan against the `Expect:` line before running the line that
writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s82/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. The bundles hold real object ids: never copy any of them into a tracked file. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
failure's record can carry the bearer token. Every block prints the error id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A scoped role whose name could not be read is never added and removed under a name
  declaration** ("withhold an AU scoped role whose live name could not be read", BL-03, decision A8).
  `Get-OERAdministrativeUnit` names a live scoped role through the directory role list, which lists
  ACTIVATED roles only; a role id the list does not name gets an empty `RoleName`. When the document
  declares a role by name for the same principal and no live role matches it, the unnamed live role
  may be that very role. `Sync-OERStructureAdministrativeUnit` used to add the declared role and then,
  under `-Prune`, remove the unnamed one. It now does neither and reports one `Skipped` row that says
  the live role's name could not be read; declaring the role by its id reconciles it.
- **B. A section that could not be read at all is partial** ("report an inventory section or the
  group roster that could not be read as partial", BL-05, decision A9). A refused, throttled or failed
  read of the group list, the administrative unit list or the access review list used to produce only
  a warning: the section was written as `[]` and no `InventoryPartial` named it, so
  `Export-OERInventory` reported the bundle as complete. The section is still written as `[]` (a
  top-level section is never `null`), and is now named in `InventoryPartial` by its own name
  (`groups`, `administrativeUnits`, `accessReviews`); a group roster that could not be read is named
  `groupsRoster` in `IncompleteReads`.
- **C. No binding or name without a key** ("never write a binding or a name without a key, and refuse
  an empty name", BL-06, decision A10). The export never writes an empty `resource`, `role`, resource
  `name`, scoped role or principal: a group or application binding whose name cannot be read is
  written by its object id (which the apply engine accepts), and an entry with neither makes its
  collection an explicit `null`, named in `InventoryPartial`. `Test-OERStructure` reports an empty or
  blank value in those five fields as an Error, and `schema.json` carries `minLength: 1` for them.
- **D. The texts** ("correct the texts on unread sections, unnamed roles and empty names", "tighten the texts on the unnamed-role guard, empty names and partial reports"): the help,
  the bundle README, the LLM prompt and `docs/inventory-to-llm/README.md`.

Round 1 (decisions A16 and A17, and two findings of the first run) added three more. Section R, at
the end of this file, runs again what they change of 1.1 and 2.1.

- **E. A scoped role declared by GUID also matches through the directory role name map** (BL-41,
  decision A16). The handler matched a GUID only on the membership's `RoleId`. The name map keys an
  activated role by its object id and by its role template id, so a role declared by one of the two
  ids is now the live scoped role that carries the other when the map gives both the same name; a
  role declared by its template id is no longer added again and, under `-Prune`, removed every other
  run if Graph stores the object id. A GUID the map does not name matches on the id alone, as before.
- **F. The bundle names what it could not read** (BL-42, decision A17). `IncompleteReads`,
  `SkippedScopes` and `SkippedEligibilityScopes` lived only on the returned object and in the error.
  The bundle's `README.md` now lists them under `## What this export could not read`, or says that
  nothing was left unread; `inventory.json` is unchanged, and the LLM prompt says where the list is.
- **G. Two small corrections.** A scoped role whose `RoleName` is only blanks is written by its role
  id, like a missing name (F4), and the opening of both partial messages also covers objects left
  out because two or more live objects share a name (F5).

A live tenant is needed for what mocks cannot show: what a real export does when every read is
refused (section 1, measured against the baseline below), that the success path is unchanged against
real Graph answers and the unchanged export applied with `-Prune` plans no removal of the test
objects (section 2).

**The baseline ("before").** The checklist of the unread-collection fix,
`fix-inventory-unread-collection-is-not-empty-checklist.md`, check 3.1 (2026-10-02, `oer-live-cc-noperm`,
the default `-Include`), recorded for the three sections this branch changes: the warnings `Could not
read groups`, `Could not read administrative units` and `Could not read access reviews`, and `Could
not read the group roster`, four in all; no `InventoryPartial` named `groups`, `administrativeUnits` or
`accessReviews`, and `IncompleteReads` did not name them either.

## What this file does not check, and why

- **A (the unnamed scoped role) cannot be provoked here.** The directory role list names every
  ACTIVATED role, and a scoped role can only hold an activated one, so a live tenant gives no unnamed
  role on demand. It is check class B of the sprint: proven by mocked, mutation-proven unit tests that
  run the REAL `Get-OERAdministrativeUnit` and `Get-OERDirectoryRoleNameMap` with only the transport
  answering, in `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1` (Context `a directory
  role name map that cannot be read is an unread scoped-role collection, never an undeclared role`),
  with the helper text in `tests/Unit/Private/ConvertTo-OERPruneWithheldResult.Tests.ps1`.
- **C (a binding with no name) cannot be provoked here either.** A catalog lists every resource it
  binds, and the names are read through the directory, so no live binding is left without a name on
  demand. Class B: `tests/Unit/Public/Get-OERInventory.Tests.ps1` holds the export cases and the
  export-to-apply round trip of an application binding with no name (Describe `an application binding
  with no readable name round-trips by its object id`); the validator and `schema.json` rule is proven
  in `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1` and
  `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1`, and offline here in 3.1.
- **No write path of the apply engine is exercised against the tenant.** A only withholds; the
  convergence check of this branch is 2.2, the unchanged export applied with `-Prune -WhatIf`.
- **E (a scoped role declared by GUID) cannot be run here.** Only a high-risk directory role can be
  scoped to an administrative unit, and the sprint's live checks use low-risk roles only, so no scoped
  role is assigned in the test tenant. Which id Graph stores for a membership created with a role
  template id is therefore not measured either; the fix does not depend on it. Class B: mocked,
  mutation-proven unit tests in `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1`
  (Context `a scoped role declared by GUID matches through the directory role name map (decision
  A16)`) run the REAL `Get-OERAdministrativeUnit`, `Get-OERDirectoryRoleNameMap`,
  `Add-OERAdministrativeUnitScopedRole` and `Remove-OERAdministrativeUnitScopedRole` against a
  simulated transport, for both premises (Graph stores the object id, Graph stores the template id),
  two runs in a row under `-Prune`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS82Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes a group and an administrative unit with
  the permissions it already holds (`Group.ReadWrite.All`, `AdministrativeUnit.ReadWrite.All`) and
  reads the directory and access reviews; this file adds none.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).

**The read-only fence.** 1.1, 2.1 and 2.2 replace the module's Graph transport, in the module's own
scope, with a thin wrapper that lets a GET through, and a POST only to
`v1.0/directoryObjects/getByIds` or `.../getMemberGroups` (two reads that Graph models as a POST),
and refuses everything else with an error naming the method and path. It counts what it saw.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'matches no live scoped role by name' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'could not be read at all and is written as an empty array' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'has no name, and no object id the apply engine accepts' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built; any `False` on the last line --
build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-04 20:40 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 2a86120, never switched; the worktree on fix/unread-role-map-and-section-are-partial at f9a7e13 with 0 tracked changes; the worktree's build carries A, B and C.

[oer-s82] The module loads from a worktree that is not the main clone: True
[oer-s82] Main clone: branch main; HEAD 2a86120
[oer-s82] Worktree: branch fix/unread-role-map-and-section-are-partial; HEAD f9a7e13 docs: add the live-verification checklist for unread role maps and sections; tracked changes: 0
[oer-s82] The worktree's build carries A: True; B: True; C: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` (app-only certificate session with the identity's app id,
the app name `oer-live-cc`, the test tenant, the service principal of that app id named
`oer-live-cc` and the token's signed-in object; the organization name, a verified domain and the
organization id; the ARM token from the certificate; the test subscription belongs to the test
tenant and is Enabled), `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result: 2026-10-04 20:40 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Every identity line True for the module session (app-only certificate session with the identity's app id, app name oer-live-cc, test tenant, the service principal named oer-live-cc and the token's signed-in object; organization name, verified domain, organization id; ARM token from the certificate; the test subscription belongs to the test tenant and is Enabled); identity check passed; the module is the worktree's build (1.1.2).

[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] The module is the worktree's build: True
```

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [x] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`. It proves its
name through the session, since it can read nothing.
**Failure looks like:** any `False` -- STOP; section 1 needs this session.

Result: 2026-10-04 20:40 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. oer-live-cc-noperm: app-only with its app id, app name oer-live-cc-noperm, test tenant, ARM token from the certificate: all True; identity check passed; the module is the worktree's build.

[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s82] The module is the worktree's build: True
```

### 0.3. The prerequisite script's plan

- [x] **0.3** `-WhatIf` plans only `oer-s82-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s82\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s82-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s82-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s82-`
object; the plan names the transcript and the baseline under `raw\s82\` and, in the tenant, the group
`oer-s82-grp`, the administrative unit `oer-s82-au` and the membership `oer-s82-au: member
oer-s82-grp` -- three tenant targets, every one starting with `oer-s82-`; `WhatIf: nothing was
created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result: 2026-10-04 20:41 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Identity check passed; the sweep read all six collections and found no oer-s82- object; 5 What-if targets: 2 local files under raw\s82\ (the transcript and the baseline) and 3 in the tenant (oer-s82-grp, oer-s82-au, oer-s82-au: member oer-s82-grp), every tenant target with the prefix; nothing written; exit code 0.

What if: Performing the operation "Start the redacted transcript" on target "raw\s82\prereq-20261004-204100Z.log".
[oer-s82] Mode: CREATE or complete. Prefix 'oer-s82-'. Objects (fixed): oer-s82-grp; oer-s82-au (hidden membership) with oer-s82-grp as its member. OerLive 1.0.2.
[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Residue: raw\residue.json holds no rows.
[oer-s82] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s82-' is left.
[oer-s82] Found: oer-s82-grp exists: False; oer-s82-au exists: False.
[oer-s82] No baseline yet: it is written now, before the first write to the tenant (groups 97, administrative units 1).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s82\baseline-s82.json".
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, no member)" on target "oer-s82-grp".
What if: Performing the operation "Create an administrative unit with hidden membership (Graph v1.0 POST directory/administrativeUnits: visibility HiddenMembership, assigned, not restricted)" on target "oer-s82-au".
What if: Performing the operation "Add the group as a member of the administrative unit (Graph v1.0 POST administrativeUnits/members/$ref)" on target "oer-s82-au: member oer-s82-grp".
[oer-s82] Summary: oer-s82-grp absent; oer-s82-au absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s82] WhatIf: nothing was created, removed or written.
[oer-s82] Done.
[oer-s82] What-if targets: 5; in the tenant: 3; every tenant target starts with oer-s82-: True; exit code: 0
```

### 0.4. The prerequisite script, for real

- [x] **0.4** The test objects exist: the group, and the hidden administrative unit with the group as its member.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group oer-s82-grp`,
`Created administrative unit oer-s82-au` and the unit readable as `HiddenMembership`, the group added
as its member and listed; the summary with both `present`; exit code `0`. A `likely replication
delay` line on a fresh object is expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result: 2026-10-04 20:43 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on the third run. Run 1 wrote the baseline (groups 97, administrative units 1), created oer-s82-grp (201) and oer-s82-au (201, readable as HiddenMembership after 3 reads, 6.2 s) and added the group (204), then stopped: the member listing of the unit, read at once, answered 404 Request_ResourceNotFound (replication), and the script's convergence read took a 404 as a stop. Run 2 stopped before writing anything new: a defect in the prerequisite script (its member read returned a list nested in a second array, so the group was not seen as a member), which tried the add again and got 400 'A conflicting object ... is present'. Both are defects of the prerequisite script, not of the module, and are fixed (a 404 while converging is 'not yet'; the member list is returned unwrapped; a conflict on the add means the membership exists). A read-only probe between the runs listed the group as the unit's member through all three member paths, the group's memberOf, and Get-OERAdministrativeUnit -IncludeMembers. Run 3 below completed: both objects present, the group listed as the member on the first read; exit code 0.

[oer-s82] Transcript (redacted): raw\s82\prereq-20261004-204246Z.log; OerLive 1.0.2.
[oer-s82] Mode: CREATE or complete. Prefix 'oer-s82-'. Objects (fixed): oer-s82-grp; oer-s82-au (hidden membership) with oer-s82-grp as its member. OerLive 1.0.2.
[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s82] Residue: raw\residue.json holds no rows.
[oer-s82] Found: oer-s82-grp exists: True; oer-s82-au exists: True.
[oer-s82] The baseline exists (groups 97, administrative units 1 when it was written).
[oer-s82] Group oer-s82-grp exists.
[oer-s82] Administrative unit oer-s82-au exists.
[oer-s82] Adding oer-s82-grp to oer-s82-au answered 400 Request_BadRequest (the membership exists already; the read below confirms it).
[oer-s82] oer-s82-au lists oer-s82-grp as a member: converged after 1 read(s), 0.1 s.
[oer-s82] Summary: oer-s82-grp present; oer-s82-au present; written to the tenant: True.
[oer-s82] Done.
[oer-s82] Exit code: 0
```

### 1. The export, read as oer-live-cc-noperm

### 1.1. Every section refused: each one named as partial, written as `[]`

- [x] **1.1** The no-permission export of groups, administrative units and access reviews names each of the three sections, and the group roster, as partial; the sections are written as `[]`, never `null`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-1.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count)"
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
$Partial = @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial errors: $($Partial.Count) [$((@($Partial | ForEach-Object { $_.FullyQualifiedErrorId })) -join '; ')]"
foreach ($P in $Partial) { Write-OerLiveStep "InventoryPartial ($($P.FullyQualifiedErrorId)) target: $($P.TargetObject)" }
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
foreach ($S in 'groups', 'administrativeUnits', 'accessReviews') {
    $V = $Doc.PSObject.Properties[$S].Value
    Write-OerLiveStep "inventory.json ${S}: present $($null -ne $Doc.PSObject.Properties[$S]); null $($null -eq $V); entries $(@($V | Where-Object { $null -ne $_ }).Count)"
}
$Roster = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
Write-OerLiveStep "groupsRoster.json entries: $(@($Roster | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
```

**Expect:** the fence saw only reads and refused `0`. Four warnings, as in the baseline: `Could not
read groups`, `Could not read administrative units`, `Could not read access reviews` (each a 403,
the expected answer for this identity) and `Could not read the group roster`. **New:**
`IncompleteReads` holds two entries, `groups, administrativeUnits, accessReviews` and `groupsRoster`;
two `InventoryPartial` errors, one from `Get-OERInventory` whose target is exactly
`groups, administrativeUnits, accessReviews` and whose message says such a section is written as an
empty array, and one from `Export-OERInventory`; each of the three sections present in
`inventory.json`, not `null`, with `0` entries; `groupsRoster.json` with `0` entries.
**Failure looks like:** an `IncompleteReads` without one of the three section names or without
`groupsRoster`, or no `InventoryPartial` -- the bundle still reads as complete (the defect of this
branch); a section `null` in `inventory.json` -- a top-level section must stay an array; `refused`
above 0.

Result: 2026-10-04 20:43 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Fence: 4 requests, 0 not a GET, refused 0. Every read refused (403, the expected answer for this identity). The same four warnings as the baseline (groups, administrative units, access reviews, the group roster). NEW against the baseline (check 3.1 of the unread-collection checklist, where no InventoryPartial and no IncompleteReads entry named these sections): IncompleteReads holds 2 entries, 'groups, administrativeUnits, accessReviews' and 'groupsRoster'; 2 InventoryPartial errors, the one from Get-OERInventory with the target exactly 'groups, administrativeUnits, accessReviews' and the sentence that such a section is written as an empty array, and one from Export-OERInventory naming groupsRoster; each of the three sections present in inventory.json, not null, with 0 entries; groupsRoster.json with 0 entries. The other error records are the transport's nested records of the same refusals, as in the baseline.

[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s82] Fence: requests 4, not a GET 0, refused 0
[oer-s82] Warnings: 4
[oer-s82] Warning: Could not read groups: Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Warning: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Warning: Could not read access reviews: Forbidden: Attempted to perform an unauthorized operation.
[oer-s82] Warning: Could not read the group roster: Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] IncompleteReads: 2 [groups, administrativeUnits, accessReviews; groupsRoster]
[oer-s82] InventoryPartial errors: 2 [InventoryPartial,Get-OERInventory; InventoryPartial,Export-OERInventory]
[oer-s82] InventoryPartial (InventoryPartial,Get-OERInventory) target: groups, administrativeUnits, accessReviews
[oer-s82] InventoryPartial (InventoryPartial,Export-OERInventory) target: REPO\docs\live-verification\raw\s82\export-1.1\oer-inventory-00000000-0000-0000-0000-000000000005-20261004-224338
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied,Get-OERGroup -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied,Get-OERAdministrativeUnit -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: InventoryPartial,Get-OERInventory -- This inventory is PARTIAL: 3 collection(s) could not be read, or could not be written without an empty name, and are not stated as facts in the document (an accessReviews entry named as unread may still carry an id where a name could not be read). Unread: groups, administrativeUnits, accessReviews. A section reported here by its name alone could not be read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read groups: Authorization_RequestDenied: Insufficient privileges to complete the operation.; Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.; Could not read access reviews: Forbidden: Attempted to perform an unauthorized operation..
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied,Get-OERGroup -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: Authorization_RequestDenied,Get-OERGroup -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s82] Error: InventoryPartial,Export-OERInventory -- This inventory bundle is PARTIAL: 2 partial Entra ID read entry(ies) name collections that could not be read, or could not be written without an empty name, and are NOT stated as facts in the bundle -- one entry can name several collections, so read the entries rather than this count: groups, administrativeUnits, accessReviews; groupsRoster. A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched. A section named alone is written as an empty array, which does not mean the tenant has none, and the entry groupsRoster means groupsRoster.json is empty since the group roster could not be read. Do not treat it as a full tenant snapshot.
[oer-s82] inventory.json groups: present True; null False; entries 0
[oer-s82] inventory.json administrativeUnits: present True; null False; entries 0
[oer-s82] inventory.json accessReviews: present True; null False; entries 0
[oer-s82] groupsRoster.json entries: 0
```

### 2. The export and the apply, read as oer-live-cc

### 2.1. The same export: no partial, and the test objects in the bundle

- [x] **2.1** The same export as 1.1 is complete (no `InventoryPartial`, no `IncompleteReads`), and the bundle carries `oer-s82-au` with its member and `oer-s82-grp` in the roster.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-2.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, access reviews {2}, roster {3}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.AccessReviews, $Bundle.RosterCount)
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count)"
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
$Partial = @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial errors: $($Partial.Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Au = @($Doc.administrativeUnits | Where-Object { $_.displayName -ceq 'oer-s82-au' })
Write-OerLiveStep "oer-s82-au entries: $($Au.Count); $(if ($Au.Count) { ConvertTo-Json -InputObject $Au[0] -Depth 10 -Compress })"
$GrpId = [string](Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s82-grp'"))).Body['value'][0]['id']
Write-OerLiveStep "oer-s82-au lists oer-s82-grp ($GrpId) as its member: $(if ($Au.Count) { @($Au[0].members) -contains $GrpId } else { $false })"
$Roster = @(Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
Write-OerLiveStep "groupsRoster.json entries named oer-s82-grp: $(@($Roster | Where-Object { $_.displayName -ceq 'oer-s82-grp' }).Count)"
$V = Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json') -WarningAction SilentlyContinue
Write-OerLiveStep "inventory.json validates: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
Disconnect-OerLive
```

**Expect:** the fence saw only reads and refused `0`; `IncompleteReads: 0 []` and `InventoryPartial
errors: 0`; the warnings, if any, are about access reviews that are not access-package-scoped (a
skipped review is not an unread one); `oer-s82-au entries: 1` with `"hiddenMembership":true`,
`"dynamic":false`, `"restricted":false`, `"members"` holding the group's id and `"scopedRoles":[]`;
`oer-s82-au lists oer-s82-grp ... as its member: True`; `groupsRoster.json entries named oer-s82-grp:
1`; `inventory.json validates: True`.
**Failure looks like:** an `InventoryPartial` or an `IncompleteReads` entry -- a read the identity can
do was reported as unread; `members` or `scopedRoles` `null` on `oer-s82-au` -- the hidden unit's
membership was not readable (record it, it is a finding, not a pass); `refused` above 0.

Result: 2026-10-04 20:46 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Fence: 405 requests, 3 not a GET (getByIds), refused 0. IncompleteReads 0 and no InventoryPartial: the same export as 1.1 is complete for this identity. The only warning is the known aggregate for 1 access review that is not access-package-scoped (skipped, not unread). oer-s82-au: 1 entry, hiddenMembership true, dynamic false, restricted false, members holding the group's id, scopedRoles [] -- the hidden unit's membership is readable app-only; groupsRoster.json lists oer-s82-grp once; inventory.json validates (0 Errors). Summary: groups 10 (RBAC-relevant only), administrative units 2, access reviews 5, roster 98.

[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Fence: requests 405, not a GET 3, refused 0
[oer-s82] Summary: groups 10, administrative units 2, access reviews 5, roster 98
[oer-s82] Warnings: 1
[oer-s82] Warning: Get-OERInventory: skipped 1 access review definition(s) that are not access-package-scoped. Only access-package reviews round-trip through Invoke-OERStructure; group, application and directory-role reviews are not captured.
[oer-s82] IncompleteReads: 0 []
[oer-s82] InventoryPartial errors: 0
[oer-s82] oer-s82-au entries: 1; {"displayName":"oer-s82-au","description":"Omnicit.EntraRBAC live verification (oer-s82-): an unread section is never empty.","restricted":false,"dynamic":false,"hiddenMembership":true,"members":["00000000-0000-0000-0000-000000000004"],"scopedRoles":[]}
[oer-s82] oer-s82-au lists oer-s82-grp (00000000-0000-0000-0000-000000000004) as its member: True
[oer-s82] groupsRoster.json entries named oer-s82-grp: 1
[oer-s82] inventory.json validates: True; Errors: 0
```

### 2.2. The unchanged export applied with -Prune -WhatIf: no removal planned for the test objects

- [x] **2.2** An export with every security group in full detail, applied unchanged with `-Prune -WhatIf`, plans 0 removals for `oer-s82-` objects; the rows per section are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-2.2'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -AllGroupsDetailed -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue
Write-OerLiveStep ("Export: groups {0}, administrative units {1}, access reviews {2}; IncompleteReads {3}; InventoryPartial errors {4}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.AccessReviews, @($Bundle.IncompleteReads).Count, @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count)
$Path = Join-Path $Bundle.BundlePath 'inventory.json'
$Doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
Write-OerLiveStep "oer-s82-grp in inventory.json: $(@($Doc.groups | Where-Object { $_.displayName -ceq 'oer-s82-grp' }).Count); oer-s82-au: $(@($Doc.administrativeUnits | Where-Object { $_.displayName -ceq 'oer-s82-au' }).Count)"
$Rows = @(Invoke-OERStructure -Path $Path -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
foreach ($G in @($Rows | Group-Object Section, Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name): $($G.Count)" }
$WouldRemove = @($Rows | Where-Object { [string]$_.Detail -like 'would remove*' })
$WouldRemoveOurs = @($WouldRemove | Where-Object { [string]$_.Item -like 'oer-s82-*' })
Write-OerLiveStep "Would-remove rows: $($WouldRemove.Count); for oer-s82- objects: $($WouldRemoveOurs.Count)"
foreach ($R in @($Rows | Where-Object { [string]$_.Item -like 'oer-s82-*' })) { Write-OerLiveStep "oer-s82 row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
Write-OerLiveStep "Would-remove warnings: $(@($ApplyWarn | Where-Object { "$_" -match 'would remove' }).Count)"
foreach ($E in @($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Apply error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** the export with no partial and both test objects in `inventory.json` (`oer-s82-grp in
inventory.json: 1; oer-s82-au: 1`); the fence refused `0`; every `oer-s82-` row `Unchanged`
(the group's members and the unit's properties, member and scoped roles); `Would-remove rows` counted
and `for oer-s82- objects: 0`. The rows per section are recorded as they are; a would-remove row for
another object of the tenant is recorded with its count and is not a failure of this branch (this
branch changes no prune of the group or unit handlers; a planned removal there is a finding).
**Failure looks like:** a would-remove row for an `oer-s82-` object; an `oer-s82-` row other than
`Unchanged`; `refused` above 0.

Result: 2026-10-04 20:51 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The export with every security group in full detail: groups 92, administrative units 2, access reviews 5, no IncompleteReads and no InventoryPartial; both test objects in inventory.json. Applied unchanged with -Prune -WhatIf behind the fence (899 requests, 3 getByIds, refused 0): 0 would-remove rows in all, 0 for oer-s82- objects, 0 would-remove warnings; every oer-s82- row Unchanged (the group's properties; the unit's properties and its member). Rows per section: accessReviews Unchanged 5, administrativeUnits Unchanged 3, groups Unchanged 254 and Skipped 67. A follow-up read-only plan grouped the 67 Skipped rows by their text with every quoted value masked: all 67 are one shape, a member of a dynamic group that the handler does not reconcile since the membership rule owns it (no write planned; recorded as a finding outside this step's scope: the export writes the members of a dynamic group, which the apply can only skip).

[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Export: groups 92, administrative units 2, access reviews 5; IncompleteReads 0; InventoryPartial errors 0
[oer-s82] oer-s82-grp in inventory.json: 1; oer-s82-au: 1
[oer-s82] Fence: requests 899, not a GET 3, refused 0
[oer-s82] Rows: accessReviews, Unchanged: 5
[oer-s82] Rows: administrativeUnits, Unchanged: 3
[oer-s82] Rows: groups, Skipped: 67
[oer-s82] Rows: groups, Unchanged: 254
[oer-s82] Would-remove rows: 0; for oer-s82- objects: 0
[oer-s82] oer-s82 row: groups | oer-s82-grp | Unchanged | group properties match
[oer-s82] oer-s82 row: administrativeUnits | oer-s82-au | Unchanged | administrative unit properties match
[oer-s82] oer-s82 row: administrativeUnits | oer-s82-au | Unchanged | member '00000000-0000-0000-0000-000000000004' already present
[oer-s82] Would-remove warnings: 0
```

### 3. The validator, offline

### 3.1. An empty name in each of the five fields: an Error each, and the apply refuses before it signs in

- [x] **3.1** `Test-OERStructure` reports an Error for `""` in `scopedRoles[].role`, `scopedRoles[].principal`, `resources[].name`, `resourceRoles[].resource` and `resourceRoles[].role`, and `Invoke-OERStructure` refuses the document with `StructureValidationFailed` without calling `Initialize-OERAuth`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S82AuthCalls = 0; function script:Initialize-OERAuth { $script:S82AuthCalls++; throw 'S82: no sign-in in 3.1' } }
$Doc = [ordered]@{
    version             = '1.0'
    administrativeUnits = @([ordered]@{ displayName = 'oer-s82-blank-au'; members = $null; scopedRoles = @([ordered]@{ role = ''; principal = '  ' }) })
    catalogs            = @([ordered]@{ displayName = 'oer-s82-blank-catalog'; resources = @([ordered]@{ type = 'Group'; name = '' }) })
    accessPackages      = @([ordered]@{ displayName = 'oer-s82-blank-ap'; catalog = 'oer-s82-blank-catalog'; resourceRoles = @([ordered]@{ resource = ''; role = ' ' }) })
}
$Json = ConvertTo-Json -InputObject $Doc -Depth 10
$V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
$Blank = @($V.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like '*must be a non-empty string*' })
foreach ($F in $Blank) { Write-OerLiveStep "Blank: $($F.Section) | $($F.Path) | $($F.Message)" }
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); blank-name Errors: $($Blank.Count)"
$Rows = @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S82AuthCalls }
Write-OerLiveStep "Invoke-OERStructure rows: $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', '); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** `Valid: False`; five blank-name Errors, at `administrativeUnits[0].scopedRoles[0].role`,
`administrativeUnits[0].scopedRoles[0].principal` (a blank `"  "` counts as empty),
`catalogs[0].resources[0].name`, `accessPackages[0].resourceRoles[0].resource` and
`accessPackages[0].resourceRoles[0].role`; `Invoke-OERStructure rows: 0; errors:
StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph session exists: False`.
**Failure looks like:** fewer than five blank-name Errors -- the validator still takes `""` as a
declared name, and the apply would throw on it or match an unnamed live role; `Initialize-OERAuth
calls` above 0.

Result: 2026-10-04 20:51 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (offline). Test-OERStructure: Valid False, 5 Errors, all 5 blank-name Errors at the five paths (the scoped role's role and its blank '  ' principal, the catalog resource name, the binding's resource and its blank ' ' role). Invoke-OERStructure: 0 rows, StructureValidationFailed, Initialize-OERAuth calls 0, no Graph session.

[oer-s82] Blank: administrativeUnits | administrativeUnits[0].scopedRoles[0].role | 'role' at administrativeUnits[0].scopedRoles[0] must be a non-empty string.
[oer-s82] Blank: administrativeUnits | administrativeUnits[0].scopedRoles[0].principal | 'principal' at administrativeUnits[0].scopedRoles[0] must be a non-empty string.
[oer-s82] Blank: catalogs | catalogs[0].resources[0].name | 'name' at catalogs[0].resources[0] must be a non-empty string.
[oer-s82] Blank: accessPackages | accessPackages[0].resourceRoles[0].resource | 'resource' at accessPackages[0].resourceRoles[0] must be a non-empty string.
[oer-s82] Blank: accessPackages | accessPackages[0].resourceRoles[0].role | 'role' at accessPackages[0].resourceRoles[0] must be a non-empty string.
[oer-s82] Valid: False; Errors: 5; blank-name Errors: 5
[oer-s82] Invoke-OERStructure rows: 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph session exists: False
```

## Teardown

### T.1. The teardown's plan

- [x] **T.1** `-Teardown -WhatIf` plans only `oer-s82-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s82\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s82-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s82-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the plan deletes `oer-s82-au` and the group `oer-s82-grp` (through the library), every
tenant target starting with `oer-s82-`; `WhatIf: nothing was created, removed or written`; exit code
`0`.
**Failure looks like:** a tenant target without the prefix -- STOP.

Result: 2026-10-04 20:51 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Identity check passed; 3 What-if targets: the transcript under raw\s82\ and 2 in the tenant, the deletion of oer-s82-au (this script) and of the group oer-s82-grp (the library, step 5 of 6), both with the prefix; nothing removed; exit code 0.

What if: Performing the operation "Start the redacted transcript" on target "raw\s82\teardown-20261004-205135Z.log".
[oer-s82] Mode: REMOVE. Prefix 'oer-s82-'. Objects (fixed): oer-s82-grp; oer-s82-au (hidden membership) with oer-s82-grp as its member. OerLive 1.0.2.
[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Residue: raw\residue.json holds no rows.
What if: Performing the operation "Delete the administrative unit (Graph v1.0 DELETE directory/administrativeUnits)" on target "oer-s82-au".
[oer-s82] Teardown of 'oer-s82-': users 0, groups 1, access packages 0, catalogs 0; administrative units 1 and app registrations 0 are reported only.
[oer-s82] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s82] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s82] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s82] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s82] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s82-grp".
[oer-s82] Teardown 6/6: the prefixed users.
[oer-s82] Teardown of 'oer-s82-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s82] WhatIf: nothing was created, removed or written.
[oer-s82] Done.
[oer-s82] What-if targets: 3; in the tenant: 2; every tenant target starts with oer-s82-: True; exit code: 0
```

### T.2. The teardown

- [x] **T.2** Every `oer-s82-` object is gone, and the counts match the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** `Teardown AU: deleted oer-s82-au`, the library deleting `oer-s82-grp`; the sweep finding
no `oer-s82-` object (a group deleted seconds earlier can still be listed by the `startswith`
listing for a few seconds -- T.3 reads again); `Counts: groups ... equal: True` and
`administrativeUnits ... equal: True`; exit code `0`.
**Failure looks like:** a `RESIDUE` line or exit code `3` -- record it in the report; exit code `1`.

Result: 2026-10-04 20:52 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, with the known listing delay. oer-s82-au deleted (204; gone by its id after 2 reads, 2.2 s), the library deleted oer-s82-grp (204): removed 1, residue 0, unreadable 0; exit code 0. The sweep right after still listed the group, and both counts were one above the baseline (groups 98 against 97, administrative units 2 against 1): the startswith and list reads lag a DELETE by seconds to minutes (measured in earlier steps). T.3 reads again minutes later.

[oer-s82] Transcript (redacted): raw\s82\teardown-20261004-205154Z.log; OerLive 1.0.2.
[oer-s82] Mode: REMOVE. Prefix 'oer-s82-'. Objects (fixed): oer-s82-grp; oer-s82-au (hidden membership) with oer-s82-grp as its member. OerLive 1.0.2.
[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s82] Residue: raw\residue.json holds no rows.
[oer-s82] Teardown AU: deleted oer-s82-au (204).
[oer-s82] oer-s82-au is gone: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s82] oer-s82-au is gone: converged after 2 read(s), 2.2 s.
[oer-s82] Teardown of 'oer-s82-': users 0, groups 1, access packages 0, catalogs 0; administrative units 1 and app registrations 0 are reported only.
[oer-s82] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s82] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s82] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s82] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s82] Teardown 5/6: the prefixed groups.
[oer-s82] Deleted: group oer-s82-grp (204).
[oer-s82] Teardown 6/6: the prefixed users.
[oer-s82] Teardown of 'oer-s82-': removed 1, residue 0, unreadable 0.
[oer-s82] Sweep: group 'oer-s82-grp' (00000000-0000-0000-0000-000000000004) carries the prefix.
[oer-s82] Counts: groups now 98, at the baseline 97; equal: False
[oer-s82] Counts: administrativeUnits now 2, at the baseline 1; equal: False
[oer-s82] Done.
[oer-s82] Exit code: 0
```

### T.3. Read back, and clean up

- [x] **T.3** Minutes later the sweep is clean, the counts match the baseline, the main clone is still on `main` at the HEAD S.1 recorded, and the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7)); exit code: $Code"
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts `equal:
True`; the main clone on `main` at the HEAD S.1 recorded; exit code `0`. After the results are
copied into this file: `Clear-OerLiveRedactionMap`, and `raw\s82\` deleted.
**Failure looks like:** a prefixed object left, or a residue row -- the teardown did not finish;
record it in the report.

Result: 2026-10-04 20:53 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Minutes after T.2 the sweep finds no oer-s82- object in any of the six collections; prefixed objects left 0, unread collections 0, residue rows 0; groups 97 and administrative units 1, both equal to the baseline; the main clone on main at 2a86120, the HEAD S.1 recorded, never switched; exit code 0. The redaction map is cleared and raw\s82\ deleted after this write-up.

[oer-s82] Transcript (redacted): raw\s82\readback-20261004-205247Z.log; OerLive 1.0.2.
[oer-s82] Mode: READ BACK. Prefix 'oer-s82-'. Objects (fixed): oer-s82-grp; oer-s82-au (hidden membership) with oer-s82-grp as its member. OerLive 1.0.2.
[oer-s82] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg2\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s82] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s82] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s82-' is left.
[oer-s82] Counts: groups now 97, at the baseline 97; equal: True
[oer-s82] Counts: administrativeUnits now 1, at the baseline 1; equal: True
[oer-s82] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s82] Done.
[oer-s82] Main clone: branch main; HEAD 2a86120; exit code: 0
```

## R. Round 1: the bundle names what it could not read

Round 1 runs again what E, F and G change of 1.1 and 2.1, against the round's build. **It writes
nothing to the tenant and needs no test object:** no prerequisite script runs, no teardown either,
and both exports run behind the read-only fence of the Setup above. E is class B (see "What this file
does not check"). The bundles go to `raw\s82\`, which is deleted when the results below are written up.

### R.0. The module loads from the round's build in the round's own worktree

- [ ] **R.0** The session's `Repo` is the round's worktree, whose build carries E, F and G, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$E = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'failed to read the directory roles that match a scopedRole declared by role id' -Quiet)
$F = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '## What this export could not read' -Quiet)
$G = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'or were left out because two or more live objects share a name' -Quiet)
Write-OerLiveStep "The worktree's build carries E: $E; F: $F; G: $G"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in R.3); the worktree at the round's head with 0 tracked
changes; `The worktree's build carries E: True; F: True; G: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any `False` on the last line -- build the worktree first, never while the gate runs.

Result:

### R.1. 1.1 again: the bundle itself names the three sections and the roster as unread

- [ ] **R.1** The no-permission export of 1.1 writes a `README.md` whose `What this export could not read` lists `groups, administrativeUnits, accessReviews` and `groupsRoster`; `inventory.json` carries no part of the list; the prompt says where it is; both partial messages open with G's wording.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-r.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count)"
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
$Partial = @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial errors: $($Partial.Count)"
foreach ($P in $Partial) { Write-OerLiveStep "Opening ($($P.FullyQualifiedErrorId)): $(($P.Exception.Message -split '(?<=\.) ', 2)[0])" }
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
$Head = '## What this export could not read'
$Section = (($Readme -split ('(?m)^' + [regex]::Escape($Head) + '\r?$'), 2)[1] -split '(?m)^## ', 2)[0]
Write-OerLiveStep "README.md has the section: $($Readme -match ('(?m)^' + [regex]::Escape($Head) + '\r?$')); before '## Files': $($Readme.IndexOf($Head) -ge 0 -and $Readme.IndexOf($Head) -lt $Readme.IndexOf('## Files'))"
Write-OerLiveStep "The section says PARTIAL: $(($Section -replace '\s+', ' ') -match 'This bundle is PARTIAL')"
$Entries = @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
Write-OerLiveStep "Entries in the section: $($Entries.Count)"
foreach ($L in $Entries) { Write-OerLiveStep "Entry: $L" }
$InvRaw = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
$Doc = $InvRaw | ConvertFrom-Json
Write-OerLiveStep "inventory.json keys: $(@($Doc.PSObject.Properties.Name) -join ', ')"
Write-OerLiveStep "inventory.json carries the list: $($InvRaw.Contains($Head.TrimStart('# ')) -or $InvRaw.Contains('IncompleteReads') -or $InvRaw.Contains('groupsRoster'))"
$Prompt = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'rbac-architect-prompt.md') -Raw
Write-OerLiveStep "The prompt says where the list is: $($Prompt.Contains('README.md') -and $Prompt.Contains('What this export could not read'))"
Disconnect-OerLive
```

**Expect:** the fence refused `0`; `IncompleteReads: 2 [groups, administrativeUnits, accessReviews;
groupsRoster]` and `InventoryPartial errors: 2`, as in 1.1. **New:** both openings name objects
`left out because two or more live objects share a name` (G); `README.md has the section: True;
before '## Files': True`; `The section says PARTIAL: True`; `Entries in the section: 2`, exactly
``- Entra ID: `groups, administrativeUnits, accessReviews` `` and ``- Entra ID: `groupsRoster` ``;
`inventory.json keys` the version and the nine sections, as before; `inventory.json carries the
list: False`; `The prompt says where the list is: True`.
**Failure looks like:** no section, or an entry missing -- the bundle still does not say what it
could not read (the defect of F); `inventory.json carries the list: True` -- the list leaked into the
document that is validated and applied; `refused` above 0.

Result:

### R.2. 2.1 again: the bundle says that everything was read

- [ ] **R.2** The same export as `oer-live-cc` is complete, and its `README.md` says so in `What this export could not read`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-r.2'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, access reviews {2}, roster {3}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.AccessReviews, $Bundle.RosterCount)
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count); SkippedScopes: $(@($Bundle.SkippedScopes).Count); SkippedEligibilityScopes: $(@($Bundle.SkippedEligibilityScopes).Count)"
Write-OerLiveStep "InventoryPartial errors: $(@($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count)"
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
$Head = '## What this export could not read'
$Section = (($Readme -split ('(?m)^' + [regex]::Escape($Head) + '\r?$'), 2)[1] -split '(?m)^## ', 2)[0]
Write-OerLiveStep "README.md has the section: $($Readme -match ('(?m)^' + [regex]::Escape($Head) + '\r?$')); entries: $(@($Section -split '\r?\n' | Where-Object { $_ -like '- *' }).Count)"
Write-OerLiveStep "The section: $(($Section -replace '\s+', ' ').Trim())"
$V = Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json') -WarningAction SilentlyContinue
Write-OerLiveStep "inventory.json validates: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
Disconnect-OerLive
```

**Expect:** the fence refused `0`; `IncompleteReads: 0; SkippedScopes: 0; SkippedEligibilityScopes:
0` and `InventoryPartial errors: 0`, as in 2.1; the warnings, if any, about access reviews that are
not access-package-scoped (skipped, not unread). **New:** `README.md has the section: True; entries:
0`, and the section reads `Nothing. Export-OERInventory read everything it was asked to read ...`;
`inventory.json validates: True`.
**Failure looks like:** the section missing, or an entry in it -- the bundle would claim, or fail to
claim, a read it did; `refused` above 0.

Result:

### R.3. Read back, and clean up

- [ ] **R.3** The main clone is still on `main` at the HEAD R.0 recorded, and the redaction map and `raw\s82\` are deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "raw\s82 holds: $(@(Get-ChildItem -LiteralPath $Raw -ErrorAction SilentlyContinue).Name -join ', ')"
```

**Expect:** the main clone on `main` at the HEAD R.0 recorded; `raw\s82` holds the two export
folders of R.1 and R.2. After the results are copied into this file: `Clear-OerLiveRedactionMap`,
and `raw\s82\` deleted.
**Failure looks like:** the main clone on another branch or HEAD -- record it in the report.

Result:
