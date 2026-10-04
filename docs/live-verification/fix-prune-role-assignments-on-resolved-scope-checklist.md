# Live verification checklist -- role assignments are pruned on the resolved scope, and duplicate entries are refused (fix/prune-role-assignments-on-resolved-scope)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s81-`.** The
prerequisite script creates the resource group `oer-s81-rg` in the test subscription, the two plain
security groups `oer-s81-grp1` and `oer-s81-grp2`, and one Azure role assignment: the built-in Reader
role for `oer-s81-grp1`, defined at `oer-s81-rg`. The checklist itself then writes through the module
at that resource group only (1.4): `Invoke-OERStructure` gives `oer-s81-grp2` the Reader role there.
**Nothing is ever written at the subscription scope.** The identity is Owner of the test subscription,
and the role assignment prune has no guard for its own assignment, so section 2 runs at the
subscription with `-WhatIf` and WITHOUT `-Prune`, behind a read-only fence that refuses every request
that is not a read. Sections 3 and 4 only read.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS81Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown run
first with `-WhatIf`; the one apply that writes (1.4) runs its own `-WhatIf` plan first, in the same
process, and writes only when that plan removes nothing and names only `oer-s81-` objects.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s81/` -- the
library writes its transcript and the baseline there, and the folder is git-ignored. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The test subscription's
display name is replaced by `Contoso Test Subscription` in the one block that reads it (2.2). The
library keeps one real-to-placeholder map per step, outside the clone and the operator's notes, and
deletes it after the write-up. **No credential, token, application id or certificate thumbprint is
ever printed.** **Never render an error record** (`Format-List` on `$Error[0]` or on an
`-ErrorVariable`): a raw failure's record can carry the bearer token. Every block prints the error
id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Role assignments are grouped on the scope the engine resolves** ("group role assignments on
  the resolved scope"). `Invoke-OERStructure` resolves every `roleAssignments` entry's scope once,
  before the first entry is dispatched, and groups the entries on that resolved scope, in a canonical
  form compared without regard to letter case. `sub:` and `subscription:` with an id,
  `/subscriptions/` with that id, the subscription's name, `mg:` with a management group's name or
  display name and its path are one scope. Before, each spelling was its own group, and under
  `-Prune` each group's pass removed the other group's assignments, on every run; a path with a
  trailing `/` never pruned and drew a false "inherited" row, and is now refused (G). The handler
  now takes the resolved scope and never resolves it again.
- **B. A role definition matches on its GUID** ("match role assignments on the role definition
  GUID"). A live assignment at a resource group carries the role definition id anchored at the
  subscription, so a role given by its GUID (anchored by the module at the resource group) never
  matched, and `-Prune` removed and re-created the assignment on every run.
- **C. An unresolved scope withholds the whole section's prune** ("withhold the role assignment
  prune while a scope is unresolved"): it may be another spelling of any scope.
- **D. A second entry that resolves to the same assignment is `Failed` and not written** ("fail a
  role assignment entry that duplicates an earlier one"); its key still counts as declared.
- **E. The validator refuses duplicate top-level entries** in every section ("refuse duplicate
  entries in the structure validator").
- **F. The export never writes a duplicate** ("never export a duplicate entry"): objects that share
  a name are left out and named in `InventoryPartial`, and role assignment principals that share a
  name are written by object id.
- **G. A scope written with a trailing or doubled `/` is refused** ("refuse a role scope written
  with a trailing or doubled slash", round 1, A15). `Test-OERStructureSchema` reports a
  `roleAssignments` or `roleManagementPolicies` scope that ends with `/` (other than `/` itself) or
  contains `//` as an Error at the entry's scope path, and `Invoke-OERStructure` refuses the
  document before it signs in. Round 0 merged such a scope with the scope written without the `/`,
  so a scope written only that way started to be pruned, and `//` became the root `/`.
- **H. A failed read of the assignments at a scope is `Failed`** ("report a failed read of the
  assignments at a scope as Failed", round 1, A14). The handler reads with `-ErrorAction Stop`: an
  entry whose scope cannot be read is `Failed` with the read error, nothing is planned for it, and
  no prune pass runs for that scope. Round 0 took the failed read for an empty list and planned to
  create assignments that exist (4.3).

### Round 1: what was run again, and why

Round 1 (A14, A15) changed what a scope with a trailing `/` does, so every check whose document
had one was run again: 1.1-1.3 were that check and are now an offline refusal; 1.4, 1.6 and 3.1 had
the `/` only on the side and ran again with the same scope written without it. 1.4 now also gives
`oer-s81-grp2` its Reader assignment, which 1.2 used to create. 4.4 is new and measures H. S.1, the
preparation (0.1-0.3) and the teardown (T.1-T.3) ran again around them. Checks 1.5, 2.1, 2.2 and
4.1-4.3 were not run again: their documents carry no trailing `/`, and their results below are round
0's, measured with the build of "read a role definition's built-in type from properties.type".

Round 1 loads the module from the step's own worktree, never by checking the main clone out on
another commit (G12): every block sets the session's `Repo` to the worktree named by
`OER_LIVE_REPO` after the config is loaded, and the prerequisite script does the same. The raw
folder, the baseline and the residue stay in the main clone's git-ignored `raw\` folder. Round 0's
redaction map was deleted after its write-up, so round 1's placeholders are numbered afresh: the same
`00000000-0000-0000-0000-0000000000NN` can name one object in a round-0 result and another in a
round-1 result.

A live tenant is needed for what mocks cannot show: how Azure Resource Manager really returns the
scope and the role definition id of an assignment at a resource group and at the subscription, and
that the engine's resolved scope and the role GUID meet them (sections 1 and 2), and that a real
tenant's export validates and applies without a planned removal (section 4).

## What this file does not check, and why

- **The `mg:` spellings.** `oer-live-cc` holds no management-group read (app-only, the listing is
  refused), so `mg:` and a management group path cannot be resolved here. They are proven by the
  mocked tests in `tests/Unit/Public/Invoke-OERStructure.Tests.ps1` (Describe
  `Invoke-OERStructure roleAssignments grouped on the resolved scope`) and the canonical form by
  `tests/Unit/Private/ConvertTo-OERCanonicalScope.Tests.ps1`.
- **A real prune at the subscription.** Never run: the identity's own Owner assignment is there.
  Section 2 shows, with `-WhatIf` and without `-Prune`, that the assignment is matched as declared and
  never reported as undeclared.
- **Two live objects with the same name in the export.** The tenant may hold none; section 4 records
  how many it holds, by count. The behaviour itself is proven by the mocked tests in
  `tests/Unit/Public/Get-OERInventory.Tests.ps1`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- with the test subscription, and the two
  configuration files OerLive reads beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS81Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. It creates and deletes
  groups and a resource group and writes role assignments at that resource group, with the
  permissions it already holds (Owner on the test subscription); this file adds none.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).

**The fence.** The blocks marked read-only replace the module's two transports, in the module's own
scope, with thin wrappers that refuse every request that is not a read (a Microsoft Graph
`getByIds`/`getMemberGroups` post excepted, which only reads), with an error naming the method and
path.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries round 1, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A14 = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'Get-OERRoleAssignment -Scope $RawScope -AtScope -ErrorAction Stop' -Quiet)
$A15 = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "must be written without a trailing or doubled '/'" -Quiet)
Write-OerLiveStep "The worktree's build carries A14: $A14; A15: $A15"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A14: True; A15: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built; `A14: False` or `A15: False` --
build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-04 16:26 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 2a86120, never switched; the worktree on s8-steg1-r1 at 7a751c3 with 0 tracked changes; the worktree's build carries A14 and A15.

[oer-s81] The module loads from a worktree that is not the main clone: True
[oer-s81] Main clone: branch main; HEAD 2a86120
[oer-s81] Worktree: branch s8-steg1-r1; HEAD 7a751c3 docs: run the resolved-scope checklist again for round 1; tracked changes: 0
[oer-s81] The worktree's build carries A14: True; A15: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
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
tenant and is Enabled), ending `identity check passed: True`, and `The module is the worktree's
build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result: 2026-10-04 16:27 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). Every identity line True for the module session (app-only certificate session with the identity's app id, app name oer-live-cc, test tenant, service principal named oer-live-cc and the token's signed-in object; organization name, verified domain, organization id; ARM token from the certificate; the test subscription belongs to the test tenant and is Enabled); identity check passed; the module is the worktree's build (1.1.2 from REPO\.claude\worktrees\s8-steg1-r1).

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] The module is the worktree's build: True
```

### 0.2. The prerequisite script's plan

- [x] **0.2** `-WhatIf` plans only `oer-s81-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s81\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s81-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s81-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s81-`
object; `oer-s81-rg exists: False`; the plan names the transcript and the baseline file under
`raw\s81\` and, in the tenant, four targets: the resource group `oer-s81-rg`, the groups
`oer-s81-grp1` and `oer-s81-grp2`, and `oer-s81-grp1 Reader at oer-s81-rg` -- every one starting
with `oer-s81-`; `WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result: 2026-10-04 16:27 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). Identity check passed; the prereq script loaded the module from the worktree's build (OER_LIVE_REPO); no residue; the sweep found no oer-s81- object; oer-s81-rg does not exist; the baseline would be written before the first write (groups 97, role assignments defined at the subscription 6); 4 tenant targets, oer-s81-rg, oer-s81-grp1, oer-s81-grp2 and oer-s81-grp1 Reader at oer-s81-rg, every one with the prefix; nothing written; exit code 0.

What if: Performing the operation "Start the redacted transcript" on target "raw\s81\prereq-20261004-162717Z.log".
[oer-s81] Mode: CREATE or complete. Prefix 'oer-s81-'. Objects (fixed): oer-s81-rg; oer-s81-grp1, oer-s81-grp2; Reader for oer-s81-grp1 at oer-s81-rg. OerLive 1.0.2.
[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Residue: raw\residue.json holds no rows.
[oer-s81] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s81-' is left.
[oer-s81] Found: oer-s81-grp1 exists: False; oer-s81-grp2 exists: False; oer-s81-rg exists: False; role assignments defined at oer-s81-rg: 0.
[oer-s81] No baseline yet: it is written now, before the first write to the tenant (groups 97, role assignments defined at the subscription 6).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s81\baseline-s81.json".
What if: Performing the operation "Create the resource group in the test subscription (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s81)')" on target "oer-s81-rg".
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, no member)" on target "oer-s81-grp1".
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, no member)" on target "oer-s81-grp2".
What if: Performing the operation "Assign the built-in Reader role at the resource group (Azure Resource Manager PUT roleAssignments)" on target "oer-s81-grp1 Reader at oer-s81-rg".
[oer-s81] Summary: oer-s81-rg absent; oer-s81-grp1 absent; oer-s81-grp2 absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s81] WhatIf: nothing was created, removed or written.
[oer-s81] Done.
[oer-s81] What-if targets: 6; in the tenant: 4; every tenant target starts with oer-s81-: True; exit code: 0
```

### 0.3. The prerequisite script, for real

- [x] **0.3** The resource group, the two groups and the Reader assignment of `oer-s81-grp1` exist.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written before the first write (the tenant's group count and the number
of role assignments defined at the subscription); `Created resource group oer-s81-rg`, the two
groups created and resolving by display name, `Assigned Reader to oer-s81-grp1 at oer-s81-rg` and
the assignment listed there; the summary with all three `present`; exit code `0`.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.3 again (the script
completes an earlier run) or tear down; never sign in another way.

Result: 2026-10-04 16:28 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). The baseline written and read back before the first write (groups 97, role assignments defined at the subscription 6); oer-s81-rg created and readable after 1 read; oer-s81-grp1 and oer-s81-grp2 created (201) and resolving by display name after 2 and 4 reads; Reader assigned to oer-s81-grp1 at oer-s81-rg on the first attempt (3.4 s) and listed there after 1 read; summary: all three present; exit code 0.

[oer-s81] Transcript (redacted): raw\s81\prereq-20261004-162736Z.log; OerLive 1.0.2.
[oer-s81] Mode: CREATE or complete. Prefix 'oer-s81-'. Objects (fixed): oer-s81-rg; oer-s81-grp1, oer-s81-grp2; Reader for oer-s81-grp1 at oer-s81-rg. OerLive 1.0.2.
[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s81] Residue: raw\residue.json holds no rows.
[oer-s81] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s81-' is left.
[oer-s81] Found: oer-s81-grp1 exists: False; oer-s81-grp2 exists: False; oer-s81-rg exists: False; role assignments defined at oer-s81-rg: 0.
[oer-s81] No baseline yet: it is written now, before the first write to the tenant (groups 97, role assignments defined at the subscription 6).
[oer-s81] Wrote the baseline raw\s81\baseline-s81.json and read it back.
[oer-s81] Created resource group oer-s81-rg.
[oer-s81] oer-s81-rg is readable: converged after 1 read(s), 0.6 s.
[oer-s81] Created group oer-s81-grp1: 201.
[oer-s81] oer-s81-grp1 resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s81] oer-s81-grp1 resolves by its display name: converged after 2 read(s), 2.2 s.
[oer-s81] Created group oer-s81-grp2: 201.
[oer-s81] oer-s81-grp2 resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s81] oer-s81-grp2 resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s81] oer-s81-grp2 resolves by its display name: not yet (read 3, 6.2 s, likely replication delay) -- reading again in 8 s.
[oer-s81] oer-s81-grp2 resolves by its display name: converged after 4 read(s), 14.3 s.
[oer-s81] Assigned Reader to oer-s81-grp1 at oer-s81-rg (attempts 1, 3.4 s).
[oer-s81] the Reader assignment of oer-s81-grp1 is listed at oer-s81-rg: converged after 1 read(s), 0.3 s.
[oer-s81] Summary: oer-s81-rg present; oer-s81-grp1 present; oer-s81-grp2 present; written to the tenant: True.
[oer-s81] Done.
[oer-s81] Exit code: 0
```

### 1. The resource group, written with -Prune (oer-s81- objects only)

Every document in this section names the resource group `oer-s81-rg` and the two `oer-s81-` groups,
and nothing else. The only role assignments DEFINED at that resource group are the two this file
makes; the identity's own Owner assignment is defined at the subscription, so the prune pass at the
resource group never sees it (it is inherited there, and skipped). Checks 1.1-1.3 are offline since
round 1: a scope written with a trailing or doubled `/` is refused before any sign-in, so they load
the worktree's build without signing in and replace `Initialize-OERAuth` with a stub that counts its
calls and throws.

### 1.1. A trailing `/`: refused offline, before the sign-in

- [x] **1.1** A document with the resource group's path and the same path with a trailing `/` is refused: `Test-OERStructure` reports one Error at the second entry's scope, and `Invoke-OERStructure -Prune -WhatIf` refuses with `StructureValidationFailed` without calling `Initialize-OERAuth`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls = 0; function script:Initialize-OERAuth { $script:S81AuthCalls++; throw 'S81: no sign-in in 1.1' } }
Write-OerLiveStep "The module is the worktree's build: $((Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
foreach ($F in @($V.Errors | Where-Object Severity -eq 'Error')) { Write-OerLiveStep "Error: $($F.Path) | $($F.Message)" }
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls }
Write-OerLiveStep "Invoke-OERStructure -Prune -WhatIf: rows $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', '); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** `The module is the worktree's build: True`; one Error, `roleAssignments[1].scope | 'scope'
at roleAssignments[1] must be written without a trailing or doubled '/'. Got: '.../oer-s81-rg/'.`;
`Valid: False; Errors: 1`; `rows 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0;
a Graph session exists: False`.
**Failure looks like:** `Valid: True` or a row -- the two spellings are merged as in round 0, and a
scope written only with the `/` would be pruned; an `Initialize-OERAuth` call -- the refusal came
after the sign-in.

Result: 2026-10-04 16:28 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, offline). The worktree's build, Initialize-OERAuth replaced by a counting stub. Test-OERStructure: Valid False, exactly one Error, at roleAssignments[1].scope, saying the scope must be written without a trailing or doubled '/' and naming it; Invoke-OERStructure -Prune -WhatIf: 0 rows, StructureValidationFailed, Initialize-OERAuth calls 0, no Graph session. Round 0 merged the two spellings into one group; A15 refuses the document instead.

[oer-s81] The module is the worktree's build: True
[oer-s81] Error: roleAssignments[1].scope | 'scope' at roleAssignments[1] must be written without a trailing or doubled '/'. Got: '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg/'.
[oer-s81] Valid: False; Errors: 1
[oer-s81] Invoke-OERStructure -Prune -WhatIf: rows 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph session exists: False
```

### 1.2. The same document for real: refused, nothing written

- [x] **1.2** The same document applied for real (`-Prune`, no `-WhatIf`) is refused the same way: no row, `StructureValidationFailed` naming the scope, and `Initialize-OERAuth` never called.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls = 0; function script:Initialize-OERAuth { $script:S81AuthCalls++; throw 'S81: no sign-in in 1.2' } }
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $(($E.FullyQualifiedErrorId -split ',')[0]) -- $($E.Exception.Message)" }
Write-OerLiveStep "Invoke-OERStructure -Prune: rows $($Rows.Count); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** one record, `StructureValidationFailed -- Structure document failed validation:
roleAssignments[1].scope: 'scope' at roleAssignments[1] must be written without a trailing or
doubled '/'. Got: '.../oer-s81-rg/'.`; `rows 0; Initialize-OERAuth calls: 0; a Graph session
exists: False`. Since round 1 this check writes nothing: `oer-s81-grp2`'s Reader assignment is
created in 1.4 instead.
**Failure looks like:** a row, or an `Initialize-OERAuth` call.

Result: 2026-10-04 16:28 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, offline). The same document for real (-Prune, no -WhatIf): one record, StructureValidationFailed naming roleAssignments[1].scope and the scope with its trailing slash; 0 rows; Initialize-OERAuth calls 0; no Graph session; nothing written. oer-s81-grp2's Reader assignment is created in 1.4 instead.

[oer-s81] Error: StructureValidationFailed -- Structure document failed validation: roleAssignments[1].scope: 'scope' at roleAssignments[1] must be written without a trailing or doubled '/'. Got: '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg/'.
[oer-s81] Invoke-OERStructure -Prune: rows 0; Initialize-OERAuth calls: 0; a Graph session exists: False
```

### 1.3. A doubled `/`, and the policy section: refused the same way; the root `/` is not

- [x] **1.3** A scope with `//` inside the path, a scope that is only `//`, and a `roleManagementPolicies` scope with a trailing `/` are each refused before the sign-in; the root `/` alone still validates.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls = 0; function script:Initialize-OERAuth { $script:S81AuthCalls++; throw 'S81: no sign-in in 1.3' } }
$Sub = $Cfg.SubscriptionId
$Cases = [ordered]@{
    'roleAssignments, // inside the path' = [ordered]@{ version = '1.0'; roleAssignments = @([ordered]@{ scope = "/subscriptions/$Sub//resourceGroups/oer-s81-rg"; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) }
    'roleAssignments, only //'           = [ordered]@{ version = '1.0'; roleAssignments = @([ordered]@{ scope = '//'; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) }
    'roleManagementPolicies, trailing /' = [ordered]@{ version = '1.0'; roleManagementPolicies = @([ordered]@{ scope = "/subscriptions/$Sub/resourceGroups/oer-s81-rg/"; role = 'Reader' }) }
}
foreach ($Name in $Cases.Keys) {
    $Json = ConvertTo-Json -Depth 10 -InputObject $Cases[$Name]
    $V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
    $Errs = @($V.Errors | Where-Object Severity -eq 'Error')
    $Err = $null
    $Include = if ($Cases[$Name].Contains('roleAssignments')) { 'RoleAssignments' } else { 'RoleManagementPolicies' }
    $Rows = @(Invoke-OERStructure -Json $Json -Include $Include -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
    Write-OerLiveStep "${Name}: Valid $($V.Valid); Errors $($Errs.Count) at $(@($Errs.Path) -join ', '); apply rows $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
}
$Root = Test-OERStructure -Json (ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @([ordered]@{ scope = '/'; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) })) -WarningAction SilentlyContinue
Write-OerLiveStep "The root '/' alone, validated only and never applied: Valid $($Root.Valid); Errors $(@($Root.Errors | Where-Object Severity -eq 'Error').Count)"
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls }
Write-OerLiveStep "Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** each of the three cases `Valid False; Errors 1` at `roleAssignments[0].scope` or
`roleManagementPolicies[0].scope`; `apply rows 0; errors: StructureValidationFailed`; the root `/`
`Valid True; Errors 0` (it is never applied here); `Initialize-OERAuth calls: 0; a Graph session
exists: False`.
**Failure looks like:** `Valid True` for a case -- `//` would become the root `/` as in round 0; an
Error for the root `/` -- the rule refuses more than A15 decided.

Result: 2026-10-04 16:28 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, offline). A roleAssignments scope with // inside the path, one that is only //, and a roleManagementPolicies scope with a trailing slash: each Valid False with exactly one Error at its entry's scope path, and each refused by Invoke-OERStructure -Prune (0 rows, StructureValidationFailed). The root '/' alone, validated only and never applied: Valid True, 0 Errors. Initialize-OERAuth calls 0; no Graph session.

[oer-s81] roleAssignments, // inside the path: Valid False; Errors 1 at roleAssignments[0].scope; apply rows 0; errors: StructureValidationFailed
[oer-s81] roleAssignments, only //: Valid False; Errors 1 at roleAssignments[0].scope; apply rows 0; errors: StructureValidationFailed
[oer-s81] roleManagementPolicies, trailing /: Valid False; Errors 1 at roleManagementPolicies[0].scope; apply rows 0; errors: StructureValidationFailed
[oer-s81] The root '/' alone, validated only and never applied: Valid True; Errors 0
[oer-s81] Initialize-OERAuth calls: 0; a Graph session exists: False
```

### 1.4. The role as the Reader role's GUID: Unchanged on two runs, beside the second group's new assignment

- [x] **1.4** With `oer-s81-grp1`'s role given as the Reader role's definition GUID and `oer-s81-grp2` declared at the same path, without a trailing `/`, `-Prune` keeps `oer-s81-grp1` `Unchanged` on both runs, creates `oer-s81-grp2`'s assignment on the first and removes nothing; the second run is all `Unchanged` (G8).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Filter = [uri]::EscapeDataString("roleName eq 'Reader'")
$Defs = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$Filter"
$ReaderGuid = [string](@($Defs.Body.value | Where-Object { $_.properties.type -eq 'BuiltInRole' })[0].name)
$Live = Invoke-OerLiveArm -All -Path "$RgScope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
foreach ($A in @($Live.Body.value | Where-Object { ([string]$_.properties.scope).TrimEnd('/') -ieq $RgScope })) {
    Write-OerLiveStep "Live at the resource group before the run: role definition id anchored at the subscription, not the resource group: $(([string]$A.properties.roleDefinitionId).StartsWith("/subscriptions/$($Cfg.SubscriptionId)/providers/", [System.StringComparison]::OrdinalIgnoreCase)); its GUID is the Reader GUID: $(([string]$A.properties.roleDefinitionId).EndsWith("/$ReaderGuid", [System.StringComparison]::OrdinalIgnoreCase))"
}
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = $ReaderGuid; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Plan = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
foreach ($R in $Plan) { Write-OerLiveStep "Plan row: $($R.Item) | $($R.Action) | $($R.Detail)" }
$PlanRemove = @($Plan | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
$PlanForeign = @($Plan | Where-Object { $_.Item -notmatch ' -> oer-s81-grp[12] @ ' })
$PlanGuid = @($Plan | Where-Object { $_.Item -like '* -> oer-s81-grp1 @ *' })
$GuidUnchanged = ($PlanGuid.Count -eq 1) -and ($PlanGuid[0].Action -eq 'Unchanged')
$Ok = ($Plan.Count -eq 2) -and ($PlanRemove.Count -eq 0) -and ($PlanForeign.Count -eq 0) -and $GuidUnchanged
Write-OerLiveStep "Plan: rows $($Plan.Count), planned removals $($PlanRemove.Count), rows not about an oer-s81- group $($PlanForeign.Count), the GUID entry Unchanged: $GuidUnchanged; writing: $Ok"
if ($Ok) {
    foreach ($Run in 1, 2) {
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
        foreach ($R in $Rows) { Write-OerLiveStep "Run ${Run} row: $($R.Item) | $($R.Action) | $($R.Detail)" }
        Write-OerLiveStep "Run ${Run}: rows $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records: $(@($Err).Count); warnings: $(@($Warn).Count)"
    }
    $AtRg = Wait-OerLiveConverged -Activity 'two Reader assignments are defined at oer-s81-rg' -Read {
        $L = Invoke-OerLiveArm -All -Path "$RgScope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
        , @(@($L.Body.value) | Where-Object { $null -ne $_ -and ([string]$_.properties.scope).TrimEnd('/') -ieq $RgScope })
    } -Test { @($args[0]).Count -eq 2 }
    foreach ($A in @($AtRg.Value)) { Write-OerLiveStep "Defined at the resource group: principal $($A.properties.principalId), scope equals the path exactly: $([string]$A.properties.scope -ceq $RgScope)" }
}
Disconnect-OerLive
```

**Expect:** one live assignment before the run (`oer-s81-grp1`'s, from 0.3) with `anchored at the
subscription, not the resource group: True` and `its GUID is the Reader GUID: True`; the plan's two
rows: the GUID entry (redacted to a placeholder) `-> oer-s81-grp1` `Unchanged`, and `Reader ->
oer-s81-grp2` `Skipped | would create ... at '.../oer-s81-rg'`; `Plan: rows 2, planned removals 0,
rows not about an oer-s81- group 0, the GUID entry Unchanged: True; writing: True`; `Run 1`:
`Unchanged 1, Created 1`; `Run 2`: `Unchanged 2`; 0 records and 0 warnings on both runs; two
assignments defined at the resource group, each with `scope equals the path exactly: True`.
**Failure looks like:** the GUID entry planned as `would create`, or `oer-s81-grp1`'s live assignment
as a candidate -- the role key compares the whole path (BL-35); `writing: False` -- read the plan,
nothing was written; a `Removed` row; anything but `Unchanged` in `Run 2`.

Result: 2026-10-04 16:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). Measured again: oer-s81-grp1's live assignment at oer-s81-rg carries the role definition id anchored at the SUBSCRIPTION, and its GUID is the Reader GUID (BL-35's shape). Plan in the same process: the GUID entry for oer-s81-grp1 Unchanged, oer-s81-grp2 at the same path (no trailing slash) would be created there, 0 planned removals, every row about an oer-s81- group, so the run wrote. Run 1 under -Prune: GUID entry Unchanged, oer-s81-grp2 Created, 0 records, 0 warnings. Run 2: Unchanged 2, 0 records, 0 warnings (G8). Read back: exactly two assignments defined at oer-s81-rg, each scope equal to the path. Nothing removed.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Live at the resource group before the run: role definition id anchored at the subscription, not the resource group: True; its GUID is the Reader GUID: True
What if: Performing the operation "Create role assignment 'Reader' for 'oer-s81-grp2'" on target "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg".
[oer-s81] Plan row: 00000000-0000-0000-0000-000000000004 -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Plan row: Reader -> oer-s81-grp2 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Skipped | would create role assignment 'Reader' for 'oer-s81-grp2' at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Plan: rows 2, planned removals 0, rows not about an oer-s81- group 0, the GUID entry Unchanged: True; writing: True
[oer-s81] Run 1 row: 00000000-0000-0000-0000-000000000004 -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Run 1 row: Reader -> oer-s81-grp2 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Created | created role assignment 'Reader' for 'oer-s81-grp2' at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Run 1: rows 2; by action: Created 1, Unchanged 1; records: 0; warnings: 0
[oer-s81] Run 2 row: 00000000-0000-0000-0000-000000000004 -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Run 2 row: Reader -> oer-s81-grp2 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Run 2: rows 2; by action: Unchanged 2; records: 0; warnings: 0
[oer-s81] two Reader assignments are defined at oer-s81-rg: converged after 1 read(s), 0.1 s.
[oer-s81] Defined at the resource group: principal 00000000-0000-0000-0000-000000000005, scope equals the path exactly: True
[oer-s81] Defined at the resource group: principal 00000000-0000-0000-0000-000000000006, scope equals the path exactly: True
```

### 1.5. A scope that cannot be resolved withholds the prune: the plan

- [x] **1.5** With an entry whose scope cannot be resolved, `-Prune -WhatIf` withholds the prune at the resource group: `oer-s81-grp2`'s assignment, now undeclared, is `Skipped` with `prune withheld`, not planned for removal.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = 'sub:oer-s81-no-such-subscription'; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' })) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Remove = @($Rows | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); planned removals: $($Remove.Count); warnings: $(@($Warn).Count)"
Disconnect-OerLive
```

**Expect:** three rows: `Reader -> oer-s81-grp2 @ sub:oer-s81-no-such-subscription | Failed | could
not resolve scope ...` (the subscription is not found), published once by `Invoke-OERStructure`;
`oer-s81-grp1 | Unchanged`; and `oer-s81-grp2`'s live assignment at the resource group `Skipped`
with a Detail starting `prune withheld: the scope of declared entry 'Reader -> oer-s81-grp2 @
sub:oer-s81-no-such-subscription' could not be resolved`; `planned removals: 0`; no warning.
**Failure looks like:** `would remove` for `oer-s81-grp2`'s assignment -- the withhold does not
reach a scope other than the unresolved entry's own.

Result: 2026-10-04 14:31 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Three rows: oer-s81-grp1 Unchanged; oer-s81-grp2's live assignment at oer-s81-rg, now undeclared, Skipped with "prune withheld: the scope of declared entry 'Reader -> oer-s81-grp2 @ sub:oer-s81-no-such-subscription' could not be resolved ..."; the unresolvable entry Failed (could not resolve scope: the subscription was not found), published once by Invoke-OERStructure. Planned removals 0; no warning. Observed, pre-existing and outside this step: the published record's error id is the message text itself, since Resolve-OERScope throws a plain string for a subscription name that matches nothing.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Row: Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Row: 00000000-0000-0000-0000-000000000006 -> 00000000-0000-0000-0000-000000000005 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Skipped | prune withheld: the scope of declared entry 'Reader -> oer-s81-grp2 @ sub:oer-s81-no-such-subscription' could not be resolved, so it may name this scope, and undeclared assignment '/subscriptions/00000000-0000-0000-0000-000000000002/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000006' for principal '00000000-0000-0000-0000-000000000005' may be the live counterpart of that entry; it is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this section.
[oer-s81] Row: Reader -> oer-s81-grp2 @ sub:oer-s81-no-such-subscription | Failed | could not resolve scope 'sub:oer-s81-no-such-subscription': Subscription 'oer-s81-no-such-subscription' was not found or you do not have access to it.
[oer-s81] Published: Subscription 'oer-s81-no-such-subscription' was not found or you do not have access to it.,Invoke-OERStructure -- Subscription 'oer-s81-no-such-subscription' was not found or you do not have access to it.
[oer-s81] Rows: 3; by action: Failed 1, Skipped 1, Unchanged 1; planned removals: 0; warnings: 0
```

### 1.6. A second entry for the same assignment: Failed, not written

- [x] **1.6** An entry that resolves to the same scope, principal and role as an earlier one is `Failed` naming the earlier index, and the plan removes nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Filter = [uri]::EscapeDataString("roleName eq 'Reader'")
$Defs = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$Filter"
$ReaderGuid = [string](@($Defs.Body.value | Where-Object { $_.properties.type -eq 'BuiltInRole' })[0].name)
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }
            [ordered]@{ scope = ($RgScope -replace '/resourceGroups/oer-s81-rg$', '/RESOURCEGROUPS/OER-S81-RG'); role = $ReaderGuid; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
$Remove = @($Rows | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); planned removals: $($Remove.Count); records: $(@($Err).Count); warnings: $(@($Warn).Count)"
Disconnect-OerLive
```

**Expect:** three rows: `oer-s81-grp1 | Unchanged`, `oer-s81-grp2 | Unchanged`, and the third entry
`Failed` with `roleAssignments[2] resolves to the same assignment as roleAssignments[0] ('Reader ->
oer-s81-grp1 @ ...')`; `planned removals: 0`; 0 records; no warning.
**Failure looks like:** the third entry `Unchanged` or `would update` -- the duplicate is applied;
any planned removal.

Result: 2026-10-04 16:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, the second entry's scope without the trailing slash). Three rows: oer-s81-grp1 Unchanged, oer-s81-grp2 Unchanged, and the third entry (the resource group path in upper case, the role as the Reader GUID, oer-s81-grp1) Failed: roleAssignments[2] resolves to the same assignment as roleAssignments[0], nothing written for it; planned removals 0; 0 records; no warning.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Row: Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Row: Reader -> oer-s81-grp2 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Row: 00000000-0000-0000-0000-000000000004 -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/RESOURCEGROUPS/OER-S81-RG | Failed | roleAssignments[2] resolves to the same assignment as roleAssignments[0] ('Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'): the same scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg', principal and role. Nothing was written for this entry; keep one of the two entries.
[oer-s81] Rows: 3; by action: Failed 1, Unchanged 2; planned removals: 0; records: 0; warnings: 0
```

### 2. The subscription, -WhatIf without -Prune, behind the read-only fence

The identity's own Owner assignment is defined at the test subscription. These blocks never pass
`-Prune` and run behind the fence; nothing in this section can write.

### 2.1. `sub:` and `/subscriptions/`: the identity's Owner assignment is declared, never Extra

- [x] **2.1** Entry A declares the identity's own Owner assignment as `sub:` with the subscription id; entry B declares Reader for `oer-s81-grp1` at `/subscriptions/` with the same id. A is `Unchanged`, B would be created, and the identity's Owner assignment is never reported `Extra`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
$SpId = ([string]$Sp.Body['id']).ToLowerInvariant()
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = "sub:$($Cfg.SubscriptionId)"; role = 'Owner'; principal = $SpId; principalType = 'ServicePrincipal' }
            [ordered]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($R in @($Rows | Where-Object { $_.Action -ne 'Extra' })) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
$OwnExtra = @($Rows | Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' -and $_.Item -like "* -> $SpId @ *" })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); the identity's own assignment as a prune candidate: $($OwnExtra.Count); records: $(@($Err).Count); refused by the fence: $($Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Owner -> <the identity> @ sub:<the subscription id> | Unchanged | role assignment
already exists at '/subscriptions/...'` (both redacted); `Reader -> oer-s81-grp1 @ /subscriptions/...
| Skipped | would create ...`; the other assignments defined at the subscription reported `Extra`
(counted, not printed); `the identity's own assignment as a prune candidate: 0`; 0 records; `refused
by the fence: 0`.
**Failure looks like:** the identity's own assignment counted as a candidate -- the two spellings
formed two groups, so B's pass called A's assignment undeclared (on `main` it does); a refused
request -- a write was attempted under `-WhatIf`.

Result: 2026-10-04 14:32 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. -WhatIf, no -Prune, behind the read-only fence. Entry A (sub: with the subscription id, Owner, the identity's own service principal) Unchanged: role assignment already exists at the subscription; entry B (/subscriptions/ with the id, Reader, oer-s81-grp1) Skipped, would create. The two spellings formed one group, so the identity's own Owner assignment was never a prune candidate (count 0). The other 5 assignments defined at the subscription are Extra (6 in all, as in the baseline), counted not printed. 0 records; refused by the fence: 0.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create role assignment 'Reader' for 'oer-s81-grp1'" on target "/subscriptions/00000000-0000-0000-0000-000000000002".
[oer-s81] Row: Owner -> 00000000-0000-0000-0000-000000000007 @ sub:00000000-0000-0000-0000-000000000002 | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002'
[oer-s81] Row: Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002 | Skipped | would create role assignment 'Reader' for 'oer-s81-grp1' at '/subscriptions/00000000-0000-0000-0000-000000000002'
[oer-s81] Rows: 7; by action: Extra 5, Skipped 1, Unchanged 1; the identity's own assignment as a prune candidate: 0; records: 0; refused by the fence: 0
```

### 2.2. The subscription by name

- [x] **2.2** The same check with entry A's scope as `sub:` and the subscription's display name, when `oer-live-cc` can resolve it; the name is redacted in every line.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$SubName = [string](Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)?api-version=2022-12-01").Body.displayName
function Out-S81 { param([string]$Text) Write-OerLiveStep $(if ($SubName) { $Text.Replace($SubName, 'Contoso Test Subscription') } else { $Text }) }
$Listed = @((Invoke-OerLiveArm -All -Path '/subscriptions?api-version=2022-12-01').Body.value | Where-Object { [string]$_.displayName -eq $SubName })
Out-S81 "The subscription's name was read: $([bool]$SubName); subscriptions listed under that name: $($Listed.Count)"
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
$SpId = ([string]$Sp.Body['id']).ToLowerInvariant()
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = "sub:$SubName"; role = 'Owner'; principal = $SpId; principalType = 'ServicePrincipal' }
            [ordered]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($R in @($Rows | Where-Object { $_.Action -ne 'Extra' })) { Out-S81 "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' })) { Out-S81 "Published: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$OwnExtra = @($Rows | Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' -and $_.Item -like "* -> $SpId @ *" })
Out-S81 "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); the identity's own assignment as a prune candidate: $($OwnExtra.Count); refused by the fence: $($Refused.Count)"
Disconnect-OerLive
```

**Expect:** `The subscription's name was read: True; subscriptions listed under that name: 1`; then
the rows of 2.1, with entry A's label reading `@ sub:Contoso Test Subscription`; `the identity's own
assignment as a prune candidate: 0`; `refused by the fence: 0`. If the name cannot be read, or two
subscriptions carry it (A is then `Failed` with `AmbiguousName`, and the section's prune would be
withheld), record it as it is: the check is then `[~]`.
**Failure looks like:** the real subscription name in any line -- redact before anything is copied;
the identity's own assignment counted as a candidate.

Result: 2026-10-04 14:32 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The subscription's display name was read as oer-live-cc and exactly one subscription carries it. With entry A's scope as sub: and that name (redacted to Contoso Test Subscription in every line): A Unchanged at the subscription; B Skipped, would create; the identity's own assignment as a prune candidate 0; Extra 5; refused by the fence 0. The name resolved to the same group as the /subscriptions/ path.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] The subscription's name was read: True; subscriptions listed under that name: 1
What if: Performing the operation "Create role assignment 'Reader' for 'oer-s81-grp1'" on target "/subscriptions/00000000-0000-0000-0000-000000000002".
[oer-s81] Row: Owner -> 00000000-0000-0000-0000-000000000007 @ sub:Contoso Test Subscription | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002'
[oer-s81] Row: Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002 | Skipped | would create role assignment 'Reader' for 'oer-s81-grp1' at '/subscriptions/00000000-0000-0000-0000-000000000002'
[oer-s81] Rows: 7; by action: Extra 5, Skipped 1, Unchanged 1; the identity's own assignment as a prune candidate: 0; refused by the fence: 0
```

### 3. The validator, offline

### 3.1. One duplicate per section: an Error each, and the apply refuses before it signs in

- [x] **3.1** `Test-OERStructure` reports one duplicate Error per section, nine in all, and `Invoke-OERStructure` refuses the document with `StructureValidationFailed` without calling `Initialize-OERAuth`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls = 0; function script:Initialize-OERAuth { $script:S81AuthCalls++; throw 'S81: no sign-in in 3.1' } }
$Sub = $Cfg.SubscriptionId
$Doc = [ordered]@{
    version                         = '1.0'
    groups                          = @([ordered]@{ displayName = 'oer-s81-dup-group'; members = $null }, [ordered]@{ displayName = 'OER-S81-DUP-GROUP'; members = $null })
    administrativeUnits             = @([ordered]@{ displayName = 'oer-s81-dup-au'; members = $null; scopedRoles = $null }, [ordered]@{ displayName = 'Oer-S81-Dup-Au'; members = $null; scopedRoles = $null })
    catalogs                        = @([ordered]@{ displayName = 'oer-s81-dup-catalog'; resources = $null }, [ordered]@{ displayName = 'OER-S81-DUP-CATALOG'; resources = $null })
    accessPackages                  = @([ordered]@{ displayName = 'oer-s81-dup-ap'; catalog = 'oer-s81-dup-catalog'; resourceRoles = $null }, [ordered]@{ displayName = 'OER-S81-DUP-AP'; catalog = 'OER-S81-DUP-CATALOG'; resourceRoles = $null })
    accessReviews                   = @([ordered]@{ displayName = 'oer-s81-dup-review'; accessPackage = 'oer-s81-dup-ap'; assignmentPolicy = 'oer-s81-policy'; reviewers = @() }, [ordered]@{ displayName = 'OER-S81-DUP-REVIEW'; accessPackage = 'oer-s81-dup-ap'; assignmentPolicy = 'oer-s81-policy'; reviewers = @() })
    roleAssignments                 = @([ordered]@{ scope = "sub:$Sub"; role = 'Reader'; principal = 'oer-s81-grp1' }, [ordered]@{ scope = "/subscriptions/$Sub"; role = 'READER'; principal = 'OER-S81-GRP1' })
    roleManagementPolicies          = @([ordered]@{ scope = "subscription:$Sub"; role = 'Reader' }, [ordered]@{ scope = "/SUBSCRIPTIONS/$Sub"; role = 'reader' })
    directoryRoleManagementPolicies = @([ordered]@{ role = 'Reports Reader' }, [ordered]@{ role = 'reports reader' })
    directoryRoleAssignments        = @([ordered]@{ role = 'Reports Reader'; principal = 'oer-s81-grp1'; assignmentType = 'Eligible' }, [ordered]@{ role = 'REPORTS READER'; principal = 'oer-s81-grp1'; assignmentType = 'Eligible' })
}
$Json = ConvertTo-Json -InputObject $Doc -Depth 10
$V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
$Dup = @($V.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like '*declares the same*' })
foreach ($F in $Dup) { Write-OerLiveStep "Duplicate: $($F.Section) | $($F.Path) | $($F.Message)" }
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); duplicate Errors: $($Dup.Count); sections: $((@($Dup.Section) | Sort-Object -Unique) -join ', ')"
$Rows = @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls }
Write-OerLiveStep "Invoke-OERStructure rows: $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', '); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** `Valid: False`; nine duplicate Errors, one per section, each at the LATER entry's path
(`groups[1]`, `administrativeUnits[1]`, ..., `directoryRoleAssignments[1]`) and naming `...[0]`; the
roleAssignments and roleManagementPolicies ones although the two entries spell the scope differently
(`sub:`/`subscription:` with the id against the path, the second in upper case; since round 1 the
path carries no trailing `/`, which would add an Error of its own);
`Invoke-OERStructure rows: 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph
session exists: False`.
**Failure looks like:** fewer than nine duplicate Errors, or one at the earlier entry's path; a
`roleAssignments` or `roleManagementPolicies` pair not reported -- the canonical scope is not used;
`Initialize-OERAuth calls` above 0.

Result: 2026-10-04 16:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, offline, the roleAssignments pair without the trailing slash). Test-OERStructure: Valid False, 9 Errors, all 9 duplicate Errors, one per section, each at the LATER entry's path naming [0] -- the roleAssignments pair spelled sub: with the id against /subscriptions/ with the id, role and principal in upper case, now with round 1's wording of the canonical form; the roleManagementPolicies pair subscription: against /SUBSCRIPTIONS/. Invoke-OERStructure: 0 rows, StructureValidationFailed, Initialize-OERAuth calls 0, no Graph session.

[oer-s81] Duplicate: groups | groups[1] | groups[1] declares the same group name 'OER-S81-DUP-GROUP' as groups[0] (compared without regard to letter case). Both entries reconcile one group, so each would undo the other's settings and, under -Prune, remove the members the other declares. Keep one entry.
[oer-s81] Duplicate: administrativeUnits | administrativeUnits[1] | administrativeUnits[1] declares the same display name 'Oer-S81-Dup-Au' as administrativeUnits[0] (compared without regard to letter case). Both entries reconcile one administrative unit, so each would undo the other's settings and, under -Prune, remove the members and scoped roles the other declares. Keep one entry.
[oer-s81] Duplicate: catalogs | catalogs[1] | catalogs[1] declares the same display name 'OER-S81-DUP-CATALOG' as catalogs[0] (compared without regard to letter case). Both entries reconcile one catalog, so each would undo the other's settings and, under -Prune, remove the resources the other declares. Keep one entry.
[oer-s81] Duplicate: accessPackages | accessPackages[1] | accessPackages[1] declares the same catalog 'OER-S81-DUP-CATALOG' and display name 'OER-S81-DUP-AP' as accessPackages[0] (compared without regard to letter case). Both entries reconcile one access package, so each would undo the other's settings and, under -Prune, remove the resource role bindings the other declares. Keep one entry.
[oer-s81] Duplicate: accessReviews | accessReviews[1] | accessReviews[1] declares the same display name 'OER-S81-DUP-REVIEW' as accessReviews[0] (compared without regard to letter case). Both entries reconcile one access review, so applying the document would rewrite its settings on every run. Keep one entry.
[oer-s81] Duplicate: roleAssignments | roleAssignments[1] | roleAssignments[1] declares the same scope, role and principal as roleAssignments[0] (compared without regard to letter case). Both entries describe one role assignment (the scope is compared in its canonical form: sub: and subscription: with an id, and mg:, are spellings of the scope's path), so applying the document would rewrite its condition and description on every run. Keep one entry.
[oer-s81] Duplicate: roleManagementPolicies | roleManagementPolicies[1] | roleManagementPolicies[1] declares the same scope and role as roleManagementPolicies[0] (compared without regard to letter case). Both entries describe one policy (the scope is compared in its canonical form), so applying the document would rewrite its settings on every run. Keep one entry.
[oer-s81] Duplicate: directoryRoleManagementPolicies | directoryRoleManagementPolicies[1] | directoryRoleManagementPolicies[1] declares the same role 'reports reader' as directoryRoleManagementPolicies[0] (compared without regard to letter case). Both entries describe one policy, so applying the document would rewrite its settings on every run. Keep one entry.
[oer-s81] Duplicate: directoryRoleAssignments | directoryRoleAssignments[1] | directoryRoleAssignments[1] declares the same role, principal and assignmentType as directoryRoleAssignments[0] (compared without regard to letter case). Both entries describe one live assignment, and applying the document would re-issue its window for each of them on every run; keep one entry.
[oer-s81] Valid: False; Errors: 9; duplicate Errors: 9; sections: accessPackages, accessReviews, administrativeUnits, catalogs, directoryRoleAssignments, directoryRoleManagementPolicies, groups, roleAssignments, roleManagementPolicies
[oer-s81] Invoke-OERStructure rows: 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph session exists: False
```

### 4. The whole tenant's export, read as oer-live-cc

### 4.1. The export, behind the read-only fence

- [x] **4.1** The export of the whole tenant is written, its rows per section are recorded, and names that two live objects share are counted, never named.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Seen = 0
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $script:S81Seen++
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        $script:S81Seen++
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-4.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S81Seen; Refused = @($script:S81Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), refused $($Fence.Refused.Count)"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, catalogs {2}, access packages {3}, access reviews {4}, directory role policies {5}, directory role assignments {6}, role assignments {7}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.Catalogs, $Bundle.AccessPackages, $Bundle.AccessReviews, $Bundle.DirectoryRoleManagementPolicies, $Bundle.DirectoryRoleAssignments, $Bundle.RoleAssignments)
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Reads = @($Bundle.IncompleteReads)
$Named = @($Reads | Where-Object { ($_ -match '^(groups|administrativeUnits|catalogs|accessReviews)/[^/]+$') -or (($_ -match '^accessPackages/[^/]+/[^/]+$') -and ($_ -notmatch '/(packages|catalogResourceNames|resourceRoles|assignmentPolicies)$')) })
$Collisions = @(foreach ($Sec in 'groups', 'administrativeUnits', 'catalogs', 'accessReviews') {
        $Names = @($Doc.$Sec | ForEach-Object { [string]$_.displayName })
        [PSCustomObject]@{ Section = $Sec; NamedInPartial = @($Named | Where-Object { $_ -like "$Sec/*" }).Count; WrittenAnyway = @($Named | Where-Object { $_ -like "$Sec/*" } | Where-Object { $Names -contains ($_ -replace '^[^/]+/', '') }).Count }
    })
foreach ($C in $Collisions) { Write-OerLiveStep "Shared names, $($C.Section): named in the partial $($C.NamedInPartial); written to the document anyway $($C.WrittenAnyway)" }
Write-OerLiveStep "Shared names, accessPackages (one catalog): named in the partial $(@($Named | Where-Object { $_ -like 'accessPackages/*' }).Count)"
$ById = @($Doc.roleAssignments | Where-Object { [string]$_.principal -match '^[0-9a-fA-F-]{36}$' -and [string]$_.principalType -in 'User', 'Group' })
Write-OerLiveStep "Role assignment entries written by object id because their principal's name is shared: $($ById.Count)"
Write-OerLiveStep "IncompleteReads: $($Reads.Count); SkippedScopes: $(@($Bundle.SkippedScopes).Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })) { Write-OerLiveStep "Partial: $($E.FullyQualifiedErrorId) -- causes clause shares-a-name: $($E.Exception.Message -like '*share the name*')" }
Disconnect-OerLive
```

**Expect:** `refused 0`; the summary counts recorded; for every section `written to the document
anyway 0`; the counts of shared names recorded as they are (the tenant may hold none); `IncompleteReads`
and `SkippedScopes` recorded (`oer-live-cc` holds no management-group read, so the Azure walk is
expected to skip that level, as in Sprint 7 step 1).
**Failure looks like:** a refused request -- a read path tried to write; a shared name written to the
document anyway.

Result: 2026-10-04 14:35 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Fence: 474 requests, refused 0. Summary: groups 10, administrative units 1, catalogs 5, access packages 6, access reviews 5, directory role policies 22, directory role assignments 51, role assignments 15. Shared names in the tenant, by count: groups 0, administrative units 0, catalogs 0, access reviews 0, access packages in one catalog 0; written to the document anyway 0 in every section; role assignment entries written by id for a shared principal name 0. IncompleteReads 0; SkippedScopes 1 (the management-group level, which oer-live-cc cannot list, as in Sprint 7 step 1); the one InventoryPartial is Export-OERInventory's for that skipped level, with no shares-a-name cause. The tenant holds no name collision, so the collision paths are proven by the unit tests only.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Fence: requests 474, refused 0
[oer-s81] Summary: groups 10, administrative units 1, catalogs 5, access packages 6, access reviews 5, directory role policies 22, directory role assignments 51, role assignments 15
[oer-s81] Shared names, groups: named in the partial 0; written to the document anyway 0
[oer-s81] Shared names, administrativeUnits: named in the partial 0; written to the document anyway 0
[oer-s81] Shared names, catalogs: named in the partial 0; written to the document anyway 0
[oer-s81] Shared names, accessReviews: named in the partial 0; written to the document anyway 0
[oer-s81] Shared names, accessPackages (one catalog): named in the partial 0
[oer-s81] Role assignment entries written by object id because their principal's name is shared: 0
[oer-s81] IncompleteReads: 0; SkippedScopes: 1
[oer-s81] Partial: InventoryPartial,Export-OERInventory -- causes clause shares-a-name: False
```

### 4.2. The export validates

- [x] **4.2** `Test-OERStructure` reports the export valid, and the bundle's own `schema.json` accepts it.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-4.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Json = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw
$Valid = Test-OERStructure -Path (Join-Path $BundlePath 'inventory.json') -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
$Dup = @($Valid.Errors | Where-Object { $_.Message -like '*declares the same*' })
Write-OerLiveStep "Test-OERStructure: Valid $($Valid.Valid); Errors $(@($Valid.Errors | Where-Object Severity -eq 'Error').Count); duplicate Errors $($Dup.Count); Warnings $(@($Valid.Errors | Where-Object Severity -eq 'Warning').Count)"
$Schema = Get-Content -LiteralPath (Join-Path $BundlePath 'schema.json') -Raw
Write-OerLiveStep "Test-Json against the bundle's schema.json: $(Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue)"
Disconnect-OerLive
```

**Expect:** `Valid True; Errors 0; duplicate Errors 0`; the warnings counted; `Test-Json ... True`.
**Failure looks like:** `Valid False` -- record every Error's section and path (not its names): an
Error the export writes is a defect of this branch.

Result: 2026-10-04 14:35 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Test-OERStructure on the whole-tenant inventory.json: Valid True, 0 Errors, 0 duplicate Errors, 0 Warnings; Test-Json against the bundle's own schema.json: True.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Test-OERStructure: Valid True; Errors 0; duplicate Errors 0; Warnings 0
[oer-s81] Test-Json against the bundle's schema.json: True
```

### 4.3. The export's role assignments applied with -WhatIf: no undeclared candidate

- [x] **4.3** Applying the export's `roleAssignments` with `-WhatIf`, WITHOUT `-Prune` (the subscription is in it), reports 0 `Extra` rows -- the candidates `-Prune` would remove -- and the test objects `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-4.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Doc = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Doc43 = [ordered]@{ version = $Doc.version; roleAssignments = @($Doc.roleAssignments) }
$Path43 = Join-Path $Raw 'apply-4.3.json'
[System.IO.File]::WriteAllText($Path43, (ConvertTo-Json -InputObject $Doc43 -Depth 30), [System.Text.UTF8Encoding]::new($false))
$Rows = @(Invoke-OERStructure -Path $Path43 -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApErr -WarningAction SilentlyContinue -WarningVariable ApWarn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($G in @($Rows | Group-Object Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name) = $($G.Count)" }
foreach ($R in @($Rows | Where-Object { $_.Item -match 'oer-s81-' })) { Write-OerLiveStep "Test object: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($R in @($Rows | Where-Object { $_.Action -notin 'Unchanged' -and $_.Item -notmatch 'oer-s81-' })) { Write-OerLiveStep "Other row: $($R.Action) | $($R.Detail)" }
Write-OerLiveStep "Document: role assignments $(@($Doc43.roleAssignments).Count); Extra rows: $(@($Rows | Where-Object Action -eq 'Extra').Count); refused by the fence: $($Refused.Count); records: $(@($ApErr).Count)"
Disconnect-OerLive
```

**Expect:** `Extra rows: 0`; the two `oer-s81-` rows `Unchanged`; every other row recorded as it is
(a `Skipped` row starting `prune withheld:` for an entry whose principal no longer resolves is the
guard working, not a planned removal); `refused by the fence: 0`.
**Failure looks like:** an `Extra` row -- an assignment the export wrote is not matched by its own
entry, so `-Prune` would remove it: record its section and detail.
**Round 1:** not run again. Its six management-group rows are the finding A14 corrects; 4.4
measures them again with the corrected read.

Result: 2026-10-04 14:38 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on the check, with a finding outside this step. -WhatIf without -Prune, behind the fence: 15 entries; Extra rows 0 -- no candidate -Prune would remove; the two oer-s81- rows Unchanged; 9 Unchanged in all; refused by the fence 0. FINDING (pre-existing, outside the step, P1): the 6 other rows are the export's entries at two management-group scopes, planned as "would create". The diagnosis below shows why: oer-live-cc cannot read role assignments at a management group (AuthorizationFailed, published by Get-OERRoleAssignment, 6 times, plus 36 nested copies of the same record in -ErrorVariable), and the handler's read of the current assignments (Sync-OERStructureRoleAssignment.ps1:383, unchanged in substance since fa7f274:234) carries no -ErrorAction Stop, so its catch never runs and the failed read is taken as an empty list. Nothing is removed (an empty read gives the prune pass no candidate), but the row says would create where it should say Failed. Tenant user names, the management group's name and a service principal's name are replaced by person2-4, mg-name-1 and sp-name-1.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create role assignment 'Owner' for 'person2@example.com'" on target "/providers/Microsoft.Management/managementGroups/mg-name-1".
What if: Performing the operation "Create role assignment 'Owner' for 'person1@example.com'" on target "/providers/Microsoft.Management/managementGroups/mg-name-1".
What if: Performing the operation "Create role assignment 'User Access Administrator' for 'person3@example.com'" on target "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008".
What if: Performing the operation "Create role assignment 'User Access Administrator' for 'person2@example.com'" on target "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008".
What if: Performing the operation "Create role assignment 'User Access Administrator' for 'person4@example.com'" on target "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008".
What if: Performing the operation "Create role assignment 'Log Analytics Contributor' for 'sp-name-1'" on target "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008".
[oer-s81] Rows: Skipped = 6
[oer-s81] Rows: Unchanged = 9
[oer-s81] Test object: Reader -> oer-s81-grp1 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Test object: Reader -> oer-s81-grp2 @ /subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s81-rg'
[oer-s81] Other row: Skipped | would create role assignment 'Owner' for 'person2@example.com' at '/providers/Microsoft.Management/managementGroups/mg-name-1'
[oer-s81] Other row: Skipped | would create role assignment 'Owner' for 'person1@example.com' at '/providers/Microsoft.Management/managementGroups/mg-name-1'
[oer-s81] Other row: Skipped | would create role assignment 'User Access Administrator' for 'person3@example.com' at '/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008'
[oer-s81] Other row: Skipped | would create role assignment 'User Access Administrator' for 'person2@example.com' at '/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008'
[oer-s81] Other row: Skipped | would create role assignment 'User Access Administrator' for 'person4@example.com' at '/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008'
[oer-s81] Other row: Skipped | would create role assignment 'Log Analytics Contributor' for 'sp-name-1' at '/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008'
[oer-s81] Document: role assignments 15; Extra rows: 0; refused by the fence: 0; records: 42

[diagnosis, the same document again, read-only behind the fence, records grouped]
[oer-s81] Export entries at a management-group scope: 6; distinct such scopes: 2
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/mg-name-1/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/mg-name-1/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] MG transport: THROW /providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000008/providers/Microsoft.Authorization/roleAssignments -> AuthorizationFailed
[oer-s81] Records: 54; ErrorRecords: 42; published by Invoke-OERStructure: 0
[oer-s81] Record x36: AuthorizationFailed | OperationStopped | - | AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000007' does not have authorization to perf
[oer-s81] Record x6: AuthorizationFailed,Get-OERRoleAssignment | OperationStopped | Get-OERRoleAssignment | AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000007' does not have authorization to perf
[oer-s81] Rows: Skipped 6, Unchanged 9
```

### 4.4. The export's management-group assignments with -WhatIf: a failed read is Failed, never a create (A14)

- [x] **4.4** The export's role assignments at a management-group scope, which `oer-live-cc` cannot read there, applied with `-WhatIf` WITHOUT `-Prune` behind the fence: every row is `Failed` with the read error, 0 creates are planned, and 0 prune candidates are reported.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Seen = 0
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $script:S81Seen++
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        $script:S81Seen++
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-4.4'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include RoleAssignments -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$MgEntries = @($Doc.roleAssignments | Where-Object { [string]$_.scope -like '/providers/Microsoft.Management/managementGroups/*' })
Write-OerLiveStep "Export: role assignments $(@($Doc.roleAssignments).Count); at a management-group scope $($MgEntries.Count); distinct such scopes $(@($MgEntries | ForEach-Object { ([string]$_.scope).ToLowerInvariant() } | Sort-Object -Unique).Count); SkippedScopes $(@($Bundle.SkippedScopes).Count)"
$Path44 = Join-Path $Raw 'apply-4.4.json'
[System.IO.File]::WriteAllText($Path44, (ConvertTo-Json -InputObject ([ordered]@{ version = $Doc.version; roleAssignments = $MgEntries }) -Depth 30), [System.Text.UTF8Encoding]::new($false))
$Rows = @(Invoke-OERStructure -Path $Path44 -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApErr -WarningAction SilentlyContinue -WarningVariable ApWarn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S81Seen; Refused = @($script:S81Refused) } }
foreach ($G in @($Rows | Group-Object Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name) = $($G.Count)" }
foreach ($R in $Rows) {
    Write-OerLiveStep "Row: $($R.Action) | the read failed: $($R.Detail -like 'could not read role assignments at scope*') | AuthorizationFailed: $($R.Detail -match 'AuthorizationFailed') | its record: $(if ($R.Error) { ($R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })"
}
$Creates = @($Rows | Where-Object { $_.Action -eq 'Created' -or $_.Detail -like 'would create*' })
$Records = @($ApErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
foreach ($G in @($Records | Group-Object { "$($_.FullyQualifiedErrorId) | $($_.InvocationInfo.MyCommand.Name)" } | Sort-Object Name)) { Write-OerLiveStep "Records: $($G.Name) = $($G.Count)" }
Write-OerLiveStep "Entries: $($MgEntries.Count); rows: $($Rows.Count); Failed with the read error: $(@($Rows | Where-Object { $_.Action -eq 'Failed' -and $_.Detail -like 'could not read role assignments at scope*' }).Count); planned creates: $($Creates.Count); Extra: $(@($Rows | Where-Object Action -eq 'Extra').Count); error records: $($Records.Count); warnings: $(@($ApWarn).Count); fence: requests $($Fence.Seen), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** the export's role assignments counted, with the entries at a management-group scope
(round 0 measured 6 at 2 scopes; the tenant may have changed since) and `SkippedScopes 1`; every row
`Failed`, with `the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed`;
`Failed with the read error` equal to the number of entries; `planned creates: 0`; `Extra: 0`; the
records grouped by error id and command; `refused 0`. The row's Detail carries the management
group's name and is therefore not printed, and neither are the entries' principals.
**Failure looks like:** a `Skipped` row with `would create` -- the failed read is taken for an empty
list, as in round 0 (4.3); a refused request -- a read path tried to write.

Result: 2026-10-04 16:30 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1, new, A14). Behind the read-only fence: the export of the role assignments holds 15 entries, 6 of them at 2 management-group scopes (as in round 0's 4.3), SkippedScopes 1. Applied with -WhatIf, no -Prune: 6 rows, every one Failed with the read error (AuthorizationFailed, its record attached); planned creates 0 (round 0: 6 would-create rows); Extra 0. Error records 42: the read error published once per entry by Invoke-OERStructure (6), plus Get-OERRoleAssignment's own records (12) and nested copies (24) that -ErrorVariable collects. Fence: 42 requests, refused 0. The rows' Detail and the entries' principals carry tenant names and are not printed.

[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Export: role assignments 15; at a management-group scope 6; distinct such scopes 2; SkippedScopes 1
[oer-s81] Rows: Failed = 6
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Row: Failed | the read failed: True | AuthorizationFailed: True | its record: AuthorizationFailed
[oer-s81] Records: AuthorizationFailed |  = 24
[oer-s81] Records: AuthorizationFailed,Get-OERRoleAssignment | Get-OERRoleAssignment = 12
[oer-s81] Records: AuthorizationFailed,Invoke-OERStructure | Invoke-OERStructure = 6
[oer-s81] Entries: 6; rows: 6; Failed with the read error: 6; planned creates: 0; Extra: 0; error records: 42; warnings: 0; fence: requests 42, refused 0
```

## Teardown

### T.1. The teardown's plan

- [x] **T.1** `-Teardown -WhatIf` plans the removal of the two role assignments at `oer-s81-rg`, the two groups and the resource group, and nothing else.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s81\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s81-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s81-') }).Count -eq 0); exit code: $Code"
```

**Expect:** five tenant targets, each starting with `oer-s81-`: the role assignments of
`oer-s81-grp1` and `oer-s81-grp2` at `oer-s81-rg`, the two groups and `oer-s81-rg`; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result: 2026-10-04 16:30 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). Five tenant targets, every one with the prefix: the role assignments of oer-s81-grp1 and oer-s81-grp2 at oer-s81-rg, the groups oer-s81-grp1 and oer-s81-grp2, and oer-s81-rg; no residue; nothing removed; exit code 0.

What if: Performing the operation "Start the redacted transcript" on target "raw\s81\teardown-20261004-163011Z.log".
[oer-s81] Mode: REMOVE. Prefix 'oer-s81-'. Objects (fixed): oer-s81-rg; oer-s81-grp1, oer-s81-grp2; Reader for oer-s81-grp1 at oer-s81-rg. OerLive 1.0.2.
[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Residue: raw\residue.json holds no rows.
What if: Performing the operation "Remove the role assignment (Azure Resource Manager DELETE)" on target "oer-s81-grp1 role assignment at oer-s81-rg".
What if: Performing the operation "Remove the role assignment (Azure Resource Manager DELETE)" on target "oer-s81-grp2 role assignment at oer-s81-rg".
[oer-s81] Teardown of 'oer-s81-': users 0, groups 2, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s81] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s81] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s81] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s81] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s81] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s81-grp1".
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s81-grp2".
[oer-s81] Teardown 6/6: the prefixed users.
[oer-s81] Teardown of 'oer-s81-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
What if: Performing the operation "Delete the resource group (Azure Resource Manager DELETE)" on target "oer-s81-rg".
[oer-s81] WhatIf: nothing was created, removed or written.
[oer-s81] Done.
[oer-s81] What-if targets: 6; in the tenant: 5; every tenant target starts with oer-s81-: True; exit code: 0
```

### T.2. The teardown

- [x] **T.2** Everything with the prefix is gone, and the counts equal the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** both role assignments removed, both groups deleted, `oer-s81-rg` deleted and gone; the
sweep finds nothing; `Resource group oer-s81-rg exists after the teardown: False`; both counts
`equal: True`; exit code `0`.
**Failure looks like:** exit code 3 -- residue: record each RESIDUE line, it stays prefixed and the
next run retries it; a count that differs from the baseline -- record it.

Result: 2026-10-04 16:31 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on the removals, with the group count read again in T.3. Both role assignments at oer-s81-rg removed (OK); both groups deleted (204); removed 2, residue 0, unreadable 0; oer-s81-rg deleted and gone after 2 reads (2.3 s); exists after the teardown: False; role assignments defined at the subscription 6, equal to the baseline. The group count read seconds after the deletions was 98 against the baseline 97 (equal: False), while the startswith sweep still listed the two deleted groups: the listing lags a group DELETE by a few seconds (measured in Sprint 7 step 1). T.3 reads both again later.

[oer-s81] Transcript (redacted): raw\s81\teardown-20261004-163037Z.log; OerLive 1.0.2.
[oer-s81] Mode: REMOVE. Prefix 'oer-s81-'. Objects (fixed): oer-s81-rg; oer-s81-grp1, oer-s81-grp2; Reader for oer-s81-grp1 at oer-s81-rg. OerLive 1.0.2.
[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s81] Residue: raw\residue.json holds no rows.
[oer-s81] Teardown 1: removed the oer-s81-grp1 role assignment at oer-s81-rg (OK).
[oer-s81] Teardown 1: removed the oer-s81-grp2 role assignment at oer-s81-rg (OK).
[oer-s81] Teardown of 'oer-s81-': users 0, groups 2, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s81] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s81] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s81] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s81] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s81] Teardown 5/6: the prefixed groups.
[oer-s81] Deleted: group oer-s81-grp1 (204).
[oer-s81] Deleted: group oer-s81-grp2 (204).
[oer-s81] Teardown 6/6: the prefixed users.
[oer-s81] Teardown of 'oer-s81-': removed 2, residue 0, unreadable 0.
[oer-s81] oer-s81-rg is gone: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s81] oer-s81-rg is gone: converged after 2 read(s), 2.3 s.
[oer-s81] Teardown RG: deleted oer-s81-rg.
[oer-s81] Sweep: group 'oer-s81-grp1' (00000000-0000-0000-0000-000000000005) carries the prefix.
[oer-s81] Sweep: group 'oer-s81-grp2' (00000000-0000-0000-0000-000000000006) carries the prefix.
[oer-s81] Resource group oer-s81-rg exists after the teardown: False
[oer-s81] Counts: groups now 98, at the baseline 97; equal: False
[oer-s81] Counts: subscriptionRoleAssignments now 6, at the baseline 6; equal: True
[oer-s81] Done.
[oer-s81] Exit code: 0
```

### T.3. Read back, and clean up

- [x] **T.3** A later read-back finds nothing, the main clone is still on `main` at the HEAD S.1 read, and the raw folder and the redaction map are deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone after the run: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** `prefixed objects left: 0; unread collections: 0`; `Resource group oer-s81-rg exists:
False`; both counts equal; the main clone on `main` at the HEAD S.1 read. After the results are
copied into the repository checklist: delete `raw\s81\` and run `Clear-OerLiveRedactionMap`.
**Failure looks like:** a prefixed object left -- run T.2 again; the main clone on another branch or
HEAD -- something switched it during the run (G12).

Result: 2026-10-04 16:31 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS (round 1). Read back about 40 s after T.2: the sweep finds no oer-s81- object; oer-s81-rg exists: False; both counts equal to the baseline (groups 97 -- T.2's 98 was the listing lag --, role assignments defined at the subscription 6); prefixed objects left 0, unread collections 0, residue rows 0. The main clone is on main at 2a86120, the HEAD S.1 read: it was never switched. raw\s81 and the redaction map are deleted after the write-up.

[oer-s81] Transcript (redacted): raw\s81\readback-20261004-163119Z.log; OerLive 1.0.2.
[oer-s81] Mode: READ BACK. Prefix 'oer-s81-'. Objects (fixed): oer-s81-rg; oer-s81-grp1, oer-s81-grp2; Reader for oer-s81-grp1 at oer-s81-rg. OerLive 1.0.2.
[oer-s81] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg1-r1\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s81] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s81] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s81-' is left.
[oer-s81] Read-back: resource group oer-s81-rg exists: False
[oer-s81] Counts: groups now 97, at the baseline 97; equal: True
[oer-s81] Counts: subscriptionRoleAssignments now 6, at the baseline 6; equal: True
[oer-s81] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s81] Done.
[oer-s81] Main clone after the run: branch main; HEAD 2a86120
```
