# Live verification checklist -- a failed request or lookup is reported as itself (fix/failed-request-and-lookup-reported-as-themselves)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s83-`.** The
prerequisite script creates one catalog, `oer-s83-catalog` (published, visible to external users),
one hidden access package in it, `oer-s83-ap`, one security group with no member,
`oer-s83-approvers`, the policies' approver (Graph refuses a policy for any user without an
approval), and one assignment policy on the package,
`oer-s83-ext`, whose `allowedTargetScope` is `allExternalUsers`, with a raw Graph POST (the module
could not build that scope before this branch). Check 1.3 has the module create a second policy on
the same package, `oer-s83-ext2`. Nothing else is written: section 2 runs every command with
`-WhatIf` as an identity that holds no permission at all, and no group, role, policy or review
outside the prefix is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS83Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 2 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission, so that every lookup is
refused; a 403 there is the expected answer, not a stop. A 401 or 403 as `oer-live-cc` is a stop.
Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`, and so does each apply in section 1; read the plan against the `Expect:`
line before running the line that writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s83/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. The bundles hold real object ids: never copy any of them into a tracked file. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. **No credential,
token, application id or certificate thumbprint is ever printed. Never render an error record**
(`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw failure's record can carry the
bearer token. Every block prints the error id, category and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A request Graph accepts but answers `status: Failed` is an error** ("report a failed
  eligibility request as an error", BL-04). `Add-OERGroupEligibility` still returns the request object,
  and then writes `EligibilityRequestFailed`; `Invoke-OERStructure` reports such an eligibility of a
  group that already existed `Failed`, never `Updated`. A group created in the same run keeps its
  replication wait unchanged.
- **B. The requestor scope takes every v1.0 value** (BL-11, decision A7). `AllExternalUsers`,
  `AllDirectoryServicePrincipals` and `AllDirectoryAgentIdentities` are accepted, read and written, so
  an exported policy with one of them applies as `Unchanged` instead of `Failed`.
  `SpecificDirectoryServicePrincipals` is read but refused by the builder, `unknownFutureValue` read
  from Graph makes that policy `Failed` without a write, and a policy whose write would drop connected
  organization targets is refused.
- **C. An approver lookup follows the rule for every other lookup** (BL-14, decision A5). An
  ambiguous approver name is `AmbiguousApproverName`, a failed lookup is reported as itself, and only
  an approver that does not exist is `ApproverNotFound`, in `Set-OERGroupPimPolicy`,
  `Set-OERDirectoryRoleManagementPolicy`, `Set-OERRoleManagementPolicy` and the three apply paths.
- **D. Three places no longer swallow a failure** (BL-15, decision A6): the catalog read behind a
  derived access review scope, the definition read before `Remove-OERAccessReviewDefinition` deletes,
  and the instances read of `Get-OERAccessReviewDefinition`.

A live tenant is needed for what mocks cannot show: what a real v1.0 read returns for a policy whose
scope is `allExternalUsers` and that such a policy round-trips through an export and an apply
(section 1), and that a real refusal of each lookup is reported as itself (section 2).

## What this file does not check, and why

- **A cannot be provoked here.** Graph answers `status: Failed` only while a group created moments
  ago is not yet known to PIM for Groups (measured live in Sprint 7 step 3, run 0: two 404s, then a
  201 whose status was already Failed); no request can be made to fail on demand. It is check class B:
  mocked, mutation-proven unit tests that run the REAL `Add-OERGroupEligibility` with only the
  transport answering, in `tests/Unit/Public/Add-OERGroupEligibility.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (Context `a request Graph accepts but answers
  status Failed (Sprint 8 step 3, BL-04)`), with that live answer as the fixture.
- **`SpecificDirectoryServicePrincipals`, the connected organization guard and `unknownFutureValue`
  are class B unless section 1 meets them.** The first needs service principal targets the module
  cannot create, the second a connected organization, and the third appears live only if Graph
  answers a scope as `unknownFutureValue`. Unit tests in
  `tests/Unit/Public/New-OERAccessPackageRequestorScope.Tests.ps1`,
  `tests/Unit/Private/ConvertTo-OERAssignmentPolicy.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1` prove them.
- **An ambiguous or missing approver is class B.** The tenant holds no two groups of one name on
  demand; `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` and the cmdlet and handler tests prove
  both, for every call site. Section 2 proves the refusal live.
- **The access review catalog read and the instances read are class B**
  (`tests/Unit/Private/Resolve-OERAccessReviewScopeTarget.Tests.ps1`,
  `tests/Unit/Public/Get-OERAccessReviewDefinition.Tests.ps1`); 2.3 runs the third place live.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS83Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes a catalog, an access package and its
  policies, and a group, with the permissions it already holds (`EntitlementManagement.ReadWrite.All`,
  `Group.ReadWrite.All`); this file adds none.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'EligibilityRequestFailed' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'allDirectoryAgentIdentities' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'AmbiguousApproverName' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'so the check for an assignment policy' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C; D: $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True; D: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built; any `False` on the last line --
build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-05 06:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 2a86120, never switched; the worktree on fix/failed-request-and-lookup-reported-as-themselves at 2eeb653 with 0 tracked changes; the worktree's build carries A, B, C and D.

[oer-s83] The module loads from a worktree that is not the main clone: True
[oer-s83] Main clone: branch main; HEAD 2a86120
[oer-s83] Worktree: branch fix/failed-request-and-lookup-reported-as-themselves; HEAD 2eeb653 docs: add the live-verification checklist for failed requests and lookups; tracked changes: 0
[oer-s83] The worktree's build carries A: True; B: True; C: True; D: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
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

Result: 2026-10-05 06:19 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Every identity line True for the module session (app-only certificate session with the identity's app id, app name oer-live-cc, test tenant, the service principal named oer-live-cc and the token's signed-in object; organization name, verified domain, organization id; ARM token from the certificate; the test subscription belongs to the test tenant and is Enabled); identity check passed; the module is the worktree's build (1.1.2).

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] The module is the worktree's build: True
```

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [x] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False` -- STOP; section 2 needs this session.

Result: 2026-10-05 06:19 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The no-permission identity signs in to a module session: app-only with its app id, app name oer-live-cc-noperm, the test tenant, the ARM token from the certificate, all True; identity check passed; the module is the worktree's build.

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s83] The module is the worktree's build: True
```

### 0.3. The prerequisite script's plan

- [x] **0.3** `-WhatIf` plans only `oer-s83-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s83\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s83-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s83-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s83-`
object; the plan names the transcript and the baseline under `raw\s83\` and, in the tenant, the
catalog `oer-s83-catalog`, the access package `oer-s83-ap`, the group `oer-s83-approvers` and the
policy `oer-s83-ext` -- four tenant targets, every one starting with `oer-s83-`; `WhatIf: nothing was created, removed or
written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result: 2026-10-05 06:22 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, on the second plan. Run 1: identity check passed, the sweep read all six collections and found no oer-s83- object, 3 tenant targets (oer-s83-catalog, oer-s83-ap, oer-s83-ext), every one with the prefix, nothing written, exit code 0. 0.4 run 1 then showed that Graph refuses an 'any user' policy without an approval, so the prerequisite script gained a fourth object, the empty approver group oer-s83-approvers; run 2 planned the two objects still missing (oer-s83-approvers, oer-s83-ext), both with the prefix, and found the catalog and package of 0.4 run 1; nothing written; exit code 0.

Run 1 (before 0.4 run 1):
Result:

Run 2 (after the approver group was added, before 0.4 run 2):
What if: Performing the operation "Start the redacted transcript" on target "raw\s83\prereq-20261005-062148Z.log".
[oer-s83] Mode: CREATE or complete. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-approvers (no member, the approver); oer-s83-ext (allExternalUsers, approved by oer-s83-approvers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Residue: raw\residue.json holds no rows.
[oer-s83] Found: oer-s83-catalog exists: True; oer-s83-ap exists: True; oer-s83-approvers exists: False.
[oer-s83] The baseline exists (catalogs 5, access packages 6 when it was written).
[oer-s83] Catalog oer-s83-catalog exists.
[oer-s83] Access package oer-s83-ap exists.
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, no member), the approver of the policies" on target "oer-s83-approvers".
What if: Performing the operation "Create an assignment policy for all external users (Graph v1.0 POST entitlementManagement/assignmentPolicies: allowedTargetScope allExternalUsers, self-request, one approval stage by oer-s83-approvers, no expiration)" on target "oer-s83-ext".
[oer-s83] Summary: oer-s83-catalog present; oer-s83-ap present; oer-s83-approvers absent; oer-s83-ext absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s83] WhatIf: nothing was created, removed or written.
[oer-s83] Done.
[oer-s83] What-if targets: 3; in the tenant: 2; every tenant target starts with oer-s83-: True; exit code: 0
```

### 0.4. The prerequisite script, for real

- [x] **0.4** The test objects exist: the catalog, the hidden access package, the approver group and the policy for all external users.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created catalog
oer-s83-catalog`, `Created access package oer-s83-ap`, `Created group oer-s83-approvers`, `Created policy oer-s83-ext`, each readable;
a line `oer-s83-ext reads allowedTargetScope '...' (raw v1.0 read, no Prefer header)` that RECORDS
what a raw read returns (the measurement 1.1 compares against); the summary with all four
`present`; exit code `0`. A `likely replication delay` line on a fresh object is expected.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way. A refused POST of the policy --
record Graph's code and message; it is a finding about what Graph accepts, not about the module.

Result: 2026-10-05 06:22 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on the second run. Run 1 wrote the baseline (catalogs 5, access packages 6), created oer-s83-catalog (201) and oer-s83-ap (201), then stopped: the policy POST answered 400 AnyUserPolicyValidationError, 'An access package policy with Any User option must have an approval configured' -- a fact about what Graph accepts, fixed in the prerequisite script (an empty security group oer-s83-approvers as the policy's approver), not a module defect. Run 2 completed: oer-s83-approvers created (201, resolvable after 4 reads, 14.4 s), oer-s83-ext created (201); the create answer and a raw v1.0 read without the Prefer header both give allowedTargetScope 'allExternalUsers' -- NOT unknownFutureValue; all four objects present; exit code 0.

Run 1:
[oer-s83] Transcript (redacted): raw\s83\prereq-20261005-061954Z.log; OerLive 1.0.2.
[oer-s83] Mode: CREATE or complete. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-ext (allExternalUsers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s83] Residue: raw\residue.json holds no rows.
[oer-s83] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s83-' is left.
[oer-s83] Found: oer-s83-catalog exists: False; oer-s83-ap exists: False.
[oer-s83] No baseline yet: it is written now, before the first write to the tenant (catalogs 5, access packages 6).
[oer-s83] Wrote the baseline raw\s83\baseline-s83.json and read it back.
[oer-s83] Created catalog oer-s83-catalog: 201.
[oer-s83] oer-s83-catalog is readable by its id: converged after 1 read(s), 0.2 s.
[oer-s83] Created access package oer-s83-ap: 201 after 1 attempt(s).
[oer-s83] oer-s83-ap is readable by its id: converged after 1 read(s), 0.2 s.
[oer-s83] Stopped after this run had written to the tenant (see the lines above): Creating policy oer-s83-ext failed: POST v1.0/identityGovernance/entitlementManagement/assignmentPolicies answered 400 AnyUserPolicyValidationError -- An access package policy with Any User option must have an approval configured.
[oer-s83] Stopped at: at Assert-OerLiveOk, VAULT\OerLive\OerLive.psm1: line 673 <- at Invoke-S83Setup, VAULT\Initialize-OerS83Prereq.ps1: line 273 <- at <ScriptBlock>, VAULT\Initialize-OerS83Prereq.ps1: line 331
[oer-s83] Setup changes nothing outside the prefix, so nothing is restored here; the test objects are removed by -Teardown.
[oer-s83] Exit code: 1

Run 2:
[oer-s83] Transcript (redacted): raw\s83\prereq-20261005-062204Z.log; OerLive 1.0.2.
[oer-s83] Mode: CREATE or complete. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-approvers (no member, the approver); oer-s83-ext (allExternalUsers, approved by oer-s83-approvers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s83] Residue: raw\residue.json holds no rows.
[oer-s83] Found: oer-s83-catalog exists: True; oer-s83-ap exists: True; oer-s83-approvers exists: False.
[oer-s83] The baseline exists (catalogs 5, access packages 6 when it was written).
[oer-s83] Catalog oer-s83-catalog exists.
[oer-s83] Access package oer-s83-ap exists.
[oer-s83] Created group oer-s83-approvers: 201.
[oer-s83] oer-s83-approvers resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s83] oer-s83-approvers resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s83] oer-s83-approvers resolves by its display name: not yet (read 3, 6.3 s, likely replication delay) -- reading again in 8 s.
[oer-s83] oer-s83-approvers resolves by its display name: converged after 4 read(s), 14.4 s.
[oer-s83] Created policy oer-s83-ext: 201 after 1 attempt(s); the create answer's allowedTargetScope 'allExternalUsers'.
[oer-s83] oer-s83-ext is listed on oer-s83-ap: converged after 1 read(s), 0.2 s.
[oer-s83] oer-s83-ext reads allowedTargetScope 'allExternalUsers' (raw v1.0 read, no Prefer header).
[oer-s83] Summary: oer-s83-catalog present; oer-s83-ap present; oer-s83-approvers present; oer-s83-ext present; written to the tenant: True.
[oer-s83] Done.
[oer-s83] Exit code: 0
```

### 1. The export and the apply, as oer-live-cc

### 1.1. The export gives the policy with its scope

- [x] **1.1** `Export-OERInventory` writes `oer-s83-ext` with the scope Graph returned, and the value is recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Out = Join-Path $Raw 'export-1.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count); IncompleteReads: $(@($Bundle.IncompleteReads).Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Cat = @($Doc.catalogs | Where-Object { $_.displayName -ceq 'oer-s83-catalog' })
$Ap = @($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s83-ap' })
Write-OerLiveStep "inventory.json: catalogs named oer-s83-catalog $($Cat.Count) (externallyVisible $(@($Cat | ForEach-Object { $_.externallyVisible }) -join ',')); access packages named oer-s83-ap $($Ap.Count) (hidden $(@($Ap | ForEach-Object { $_.hidden }) -join ','))"
foreach ($Pol in @($Ap | ForEach-Object { $_.assignmentPolicies })) {
    Write-OerLiveStep "policy '$($Pol.displayName)': requestorScope.scope '$($Pol.requestorScope.scope)'; users $(@($Pol.requestorScope.users | Where-Object { $null -ne $_ }).Count); groups $(@($Pol.requestorScope.groups | Where-Object { $null -ne $_ }).Count)"
}
$Live = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap[0].displayName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ceq 'oer-s83-ext' })
Write-OerLiveStep "Get-OERAccessPackageAssignmentPolicy: oer-s83-ext AllowedTargetScope '$(@($Live | ForEach-Object { $_.AllowedTargetScope }) -join ',')'; RequestorScope.scope '$(@($Live | ForEach-Object { $_.RequestorScope.scope }) -join ',')'"
Disconnect-OerLive
```

**Expect:** no error and no `IncompleteReads` entry for the catalogs or access packages; one
`oer-s83-catalog` (externallyVisible `True`) and one `oer-s83-ap` (hidden `True`); the policy
`oer-s83-ext` with `requestorScope.scope` `AllExternalUsers` and no users or groups, and the cmdlet
reading `allExternalUsers` / `AllExternalUsers`. **Record the value exactly as read:** if Graph
answers `unknownFutureValue` (the module sends no `Prefer: include-unknown-enum-members`), that is
written here, and 1.2 then expects `Failed` for this policy (decision A7).
**Failure looks like:** the policy missing from the export, or a scope other than the two above.

Result: 2026-10-05 06:23 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. No warning, no error, no IncompleteReads entry; one oer-s83-catalog (externallyVisible True) and one oer-s83-ap (hidden True); the export writes oer-s83-ext with requestorScope.scope 'AllExternalUsers' and no users or groups, and Get-OERAccessPackageAssignmentPolicy reads allowedTargetScope 'allExternalUsers' / 'AllExternalUsers'. Recorded as read: Graph v1.0 answers allExternalUsers without the Prefer header, NOT unknownFutureValue. (A first run of this block printed 'users 1; groups 1': the block counted an absent key as one, @($null).Count; the block now counts non-null entries, and the bundle's JSON for the scope is {scope: AllExternalUsers} with no users or groups key.)

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Warnings: 0; IncompleteReads: 0
[oer-s83] inventory.json: catalogs named oer-s83-catalog 1 (externallyVisible True); access packages named oer-s83-ap 1 (hidden True)
[oer-s83] policy 'oer-s83-ext': requestorScope.scope 'AllExternalUsers'; users 0; groups 0
[oer-s83] Get-OERAccessPackageAssignmentPolicy: oer-s83-ext AllowedTargetScope 'allExternalUsers'; RequestorScope.scope 'AllExternalUsers'
```

### 1.2. The unchanged export applied: Unchanged with -WhatIf, and for real (G8)

- [x] **1.2** The export's `oer-s83-catalog` and `oer-s83-ap` entries, applied unchanged, give `Unchanged` for `oer-s83-ext` and no write, first with `-WhatIf`, then for real.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Bundle = Get-ChildItem -LiteralPath (Join-Path $Raw 'export-1.1') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.FullName 'inventory.json') -Raw | ConvertFrom-Json
$Mini = [ordered]@{
    version        = $Doc.version
    catalogs       = @($Doc.catalogs | Where-Object { $_.displayName -ceq 'oer-s83-catalog' })
    accessPackages = @($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s83-ap' })
}
$Json = $Mini | ConvertTo-Json -Depth 30
Set-Content -LiteralPath (Join-Path $Raw 'doc-1.2.json') -Value $Json -Encoding utf8
Write-OerLiveStep "Document: catalogs $(@($Mini.catalogs).Count), access packages $(@($Mini.accessPackages).Count), policies $(@($Mini.accessPackages | ForEach-Object { $_.assignmentPolicies }).Count)"
Connect-OerLive -Arm
foreach ($Run in 'WhatIf', 'Real') {
    $Rows = if ($Run -eq 'WhatIf') {
        @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    } else {
        @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    }
    Write-OerLiveStep "$Run rows: $(($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    foreach ($R in $Rows) { Write-OerLiveStep "$Run row: [$($R.Section)] $($R.Item) $($R.Action) -- $($R.Detail)" }
    foreach ($E in @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "$Run error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
Disconnect-OerLive
```

**Expect:** the document holds one catalog, one access package and one policy. Both runs give only
`Unchanged` rows (the catalog, the package, `assignmentPolicy 'oer-s83-ext' matches`), no
`Created`, `Updated`, `Removed` or `Failed`, and no error. Before this branch the policy was `Failed`
before the diff, with `-WhatIf` too, since the builder refused the scope. If 1.1 recorded
`unknownFutureValue`: the policy is `Failed` in both runs with the detail naming
`Prefer: include-unknown-enum-members`, and nothing is written -- record it as a finding.
**Failure looks like:** a `Failed` row for `oer-s83-ext` that names the builder or a parameter value,
or any `Updated` or `Created` row (the export did not round-trip).

Result: 2026-10-05 06:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Run 1 was refused by the validator (StructureValidationFailed, the document lacked the export's version key -- a defect of this checklist, fixed). Run 2: the document holds one catalog, one access package and one policy; with -WhatIf and for real alike, 3 rows, all Unchanged (catalog properties match; access package properties match; assignmentPolicy 'oer-s83-ext' matches); no Created, Updated, Removed or Failed row and no error. Run 3 repeated it after the real run gained -Confirm:$false (Invoke-OERStructure has ConfirmImpact High; see 1.3), with the same 3 Unchanged rows. Before this branch the policy was Failed before the diff, with -WhatIf too, since the builder refused the scope. The export round-trips.

Run 1:
[oer-s83] Document: catalogs 1, access packages 1, policies 1
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] WhatIf rows: 
[oer-s83] WhatIf error: StructureValidationFailed,Invoke-OERStructure -- Structure document failed validation: version: Required key "version" is missing or empty.
[oer-s83] Real rows: 
[oer-s83] Real error: StructureValidationFailed,Invoke-OERStructure -- Structure document failed validation: version: Required key "version" is missing or empty.

Run 2:
[oer-s83] Document: catalogs 1, access packages 1, policies 1
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] WhatIf rows: Unchanged 3
[oer-s83] WhatIf row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] Real rows: Unchanged 3
[oer-s83] Real row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] Real row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] Real row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches

Run 3 (the real run with -Confirm:$false):
[oer-s83] Document: catalogs 1, access packages 1, policies 1
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] WhatIf rows: Unchanged 3
[oer-s83] WhatIf row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] Real rows: Unchanged 3
[oer-s83] Real row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] Real row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] Real row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
```

### 1.3. A second policy for all external users: Created, then only Unchanged (G8)

- [x] **1.3** The same document plus a policy `oer-s83-ext2` with `requestorScope.scope` `AllExternalUsers` gives `Created` for it, and a run after that only `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Mini = Get-Content -LiteralPath (Join-Path $Raw 'doc-1.2.json') -Raw | ConvertFrom-Json
$Ext2 = [PSCustomObject][ordered]@{
    displayName       = 'oer-s83-ext2'
    description       = 'Omnicit.EntraRBAC live verification (oer-s83-): a second policy for all external users.'
    requestorScope    = [PSCustomObject]@{ scope = 'AllExternalUsers' }
    requestorSettings = [PSCustomObject]@{ allowSelfRequest = $true }
    requireApproval   = $true
    approvalStages    = @([PSCustomObject]@{ durationDays = 14; groups = @('oer-s83-approvers') })
}
$Ap = @($Mini.accessPackages)[0]
$Ap.assignmentPolicies = @(@($Ap.assignmentPolicies) | Where-Object { $_.displayName -cne 'oer-s83-ext2' }) + $Ext2
$Json = $Mini | ConvertTo-Json -Depth 30
Set-Content -LiteralPath (Join-Path $Raw 'doc-1.3.json') -Value $Json -Encoding utf8
Connect-OerLive -Arm
$Em = 'v1.0/identityGovernance/entitlementManagement'
foreach ($Run in 'WhatIf', 'Create', 'Again') {
    if ($Run -eq 'Again') {
        $ApId = (Get-OERAccessPackage -DisplayName 'oer-s83-ap' -ErrorAction Stop | Select-Object -First 1).Id
        $Filter = [uri]::EscapeDataString("accessPackage/id eq '$ApId'")
        $null = Wait-OerLiveConverged -Activity 'oer-s83-ext2 is listed on oer-s83-ap' -Read {
            $L = Invoke-OerLiveGraph -All -Uri "$Em/assignmentPolicies?`$filter=$Filter"
            if ($L.Refused) { Assert-OerLiveOk -Response $L -Activity 'Reading the policies of oer-s83-ap' | Out-Null }
            , @(if ($L.Ok) { @($L.Body['value']) | Where-Object { [string]$_['displayName'] -ceq 'oer-s83-ext2' } })
        } -Test { @($args[0]).Count -ge 1 }
    }
    $Rows = if ($Run -eq 'WhatIf') {
        @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    } else {
        @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    }
    Write-OerLiveStep "$Run rows: $(($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    foreach ($R in $Rows) { Write-OerLiveStep "$Run row: [$($R.Section)] $($R.Item) $($R.Action) -- $($R.Detail)" }
    foreach ($E in @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "$Run error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
$Live = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s83-ap' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'oer-s83-ext*' })
foreach ($P in $Live) { Write-OerLiveStep "Live policy '$($P.DisplayName)': AllowedTargetScope '$($P.AllowedTargetScope)'" }
Disconnect-OerLive
```

**Expect:** `WhatIf` plans `would create assignmentPolicy 'oer-s83-ext2'` and nothing else that
writes; `Create` gives `Created` for `oer-s83-ext2` and `Unchanged` for the rest; the wait lists the
new policy; `Again` gives only `Unchanged`, `oer-s83-ext2` included; no error in any run; both live
policies read `allExternalUsers`. If 1.1 recorded `unknownFutureValue`, `Again` gives `Failed` for
both policies instead -- record it as a finding (the convergence of such a policy then needs the
Prefer header, which this step does not add).
**Failure looks like:** a `Failed` row on `Create` (the builder refused the value), a second
`Created` on `Again`, or any `Updated` on `Again` (the policy did not converge).

Result: 2026-10-05 06:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on the second run. Run 1: -WhatIf planned 'would create assignmentPolicy oer-s83-ext2' and nothing else; the real run then failed the access package item as 'handler error' (NullReferenceException in ShouldProcess): Invoke-OERStructure has ConfirmImpact High and asked for confirmation in this non-interactive process; nothing was created (the wait never listed oer-s83-ext2) -- a defect of this checklist, fixed (the real runs pass -Confirm:$false). Run 2: -WhatIf plans the create; Create gives Created for oer-s83-ext2 and Unchanged for the rest; the wait lists it at once; Again gives only Unchanged, 4 rows, oer-s83-ext2 included (G8); no error; both live policies read allowedTargetScope 'allExternalUsers'. The module builds and writes AllExternalUsers, which it refused before this branch.

Run 1 (the real runs without -Confirm:$false; the nine 'not yet' wait lines are left out):
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create assignmentPolicy 'oer-s83-ext2'" on target "oer-s83-ap".
[oer-s83] WhatIf rows: Skipped 1, Unchanged 3
[oer-s83] WhatIf row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Skipped -- would create assignmentPolicy 'oer-s83-ext2'
[oer-s83] Create rows: Failed 1, Unchanged 1
[oer-s83] Create row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] Create row: [accessPackages] oer-s83-ap Failed -- handler error: Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] Create error: NullReferenceException -- Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] Create error: NullReferenceException -- Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] Create error: NullReferenceException -- Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] Create error: NullReferenceException,Sync-OERStructureAccessPackage -- Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] Create error: NullReferenceException,Invoke-OERStructure -- Exception calling "ShouldProcess" with "2" argument(s): "Object reference not set to an instance of an object."
[oer-s83] oer-s83-ext2 is listed on oer-s83-ap: NOT converged after 10 read(s), 181.4 s (budget 180 s).
Exception: OerLive: oer-s83-ext2 is listed on oer-s83-ap -- not converged within budget (180 s, 10 reads).

Run 2:
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create assignmentPolicy 'oer-s83-ext2'" on target "oer-s83-ap".
[oer-s83] WhatIf rows: Skipped 1, Unchanged 3
[oer-s83] WhatIf row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] WhatIf row: [accessPackages] oer-s83-ap Skipped -- would create assignmentPolicy 'oer-s83-ext2'
[oer-s83] Create rows: Created 1, Unchanged 3
[oer-s83] Create row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] Create row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] Create row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] Create row: [accessPackages] oer-s83-ap Created -- created assignmentPolicy 'oer-s83-ext2'
[oer-s83] oer-s83-ext2 is listed on oer-s83-ap: converged after 1 read(s), 0.1 s.
[oer-s83] Again rows: Unchanged 4
[oer-s83] Again row: [catalogs] oer-s83-catalog Unchanged -- catalog properties match
[oer-s83] Again row: [accessPackages] oer-s83-ap Unchanged -- access package properties match
[oer-s83] Again row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext' matches
[oer-s83] Again row: [accessPackages] oer-s83-ap Unchanged -- assignmentPolicy 'oer-s83-ext2' matches
[oer-s83] Live policy 'oer-s83-ext2': AllowedTargetScope 'allExternalUsers'
[oer-s83] Live policy 'oer-s83-ext': AllowedTargetScope 'allExternalUsers'
```

### 2. The lookups, as oer-live-cc-noperm

### 2.1. Set-OERGroupPimPolicy: a refused approver lookup is not ApproverNotFound

- [x] **2.1** `Set-OERGroupPimPolicy -ApproverUser ... -WhatIf` against a made-up group id reports the refused approver lookup as itself, never as `ApproverNotFound`; the error id and the HTTP status are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Approver = "oer-s83-nobody@$($Cfg.UserDomain)"
$Res = @(Set-OERGroupPimPolicy -Group '00000000-0000-0000-0000-000000000099' -AccessType member -ApproverUser $Approver -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERGroupPimPolicy' })
Write-OerLiveStep "Output objects: $($Res.Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($E in $Own) { Write-OerLiveStep "Own error: $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category); target '$($E.TargetObject)' -- $($E.Exception.Message)" }
Write-OerLiveStep "Any ApproverNotFound: $(@($All | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count -gt 0)"
$Filter = [uri]::EscapeDataString("userPrincipalName eq '$Approver'")
$Probe = Invoke-OerLiveGraph -Uri "v1.0/users?`$filter=$Filter&`$select=id"
Write-OerLiveStep "The same lookup, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** no output object; the cmdlet's own error is the refused lookup itself
(`Authorization_RequestDenied,Set-OERGroupPimPolicy`, the transport's id), never `ApproverNotFound`
and never `AmbiguousApproverName`; `Any ApproverNotFound: False`; the raw lookup answers
`HTTP 403 Authorization_RequestDenied`. Before this branch the cmdlet wrote `ApproverNotFound`
(category ObjectNotFound) for the same refusal. Nothing is written: `-WhatIf`, and an identity with no
permission.
**Failure looks like:** `ApproverNotFound` -- the defect of this branch; a 403 as `oer-live-cc` would
be a stop, but this is the no-permission identity.

Result: 2026-10-05 06:29 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. No output object; the cmdlet's own error is the refused approver lookup itself, Authorization_RequestDenied,Set-OERGroupPimPolicy (category OperationStopped, the transport's id and message), exactly once; no ApproverNotFound and no AmbiguousApproverName anywhere among the 15 records (the other 14 are the transport's nested records of the same refusal); the same user lookup made raw answers HTTP 403 Authorization_RequestDenied. Before this branch the cmdlet wrote ApproverNotFound (ObjectNotFound) for this refusal. Nothing written: -WhatIf and an identity with no permission.

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s83] Output objects: 0; error records: 15; the cmdlet's own: 1
[oer-s83] Own error: Authorization_RequestDenied,Set-OERGroupPimPolicy; category OperationStopped; target '' -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s83] Any ApproverNotFound: False
[oer-s83] The same lookup, raw: HTTP 403 Authorization_RequestDenied
```

### 2.2. Set-OERDirectoryRoleManagementPolicy: the same, for a low-risk role

- [x] **2.2** `Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser ... -WhatIf` reports the refused approver lookup as itself; the error id and the HTTP status are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Approver = "oer-s83-nobody@$($Cfg.UserDomain)"
$Res = @(Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser $Approver -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' })
Write-OerLiveStep "Output objects: $($Res.Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($E in $Own) { Write-OerLiveStep "Own error: $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category); target '$($E.TargetObject)' -- $($E.Exception.Message)" }
Write-OerLiveStep "Any ApproverNotFound: $(@($All | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count -gt 0)"
$Filter = [uri]::EscapeDataString("userPrincipalName eq '$Approver'")
$Probe = Invoke-OerLiveGraph -Uri "v1.0/users?`$filter=$Filter&`$select=id"
Write-OerLiveStep "The same lookup, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** as 2.1 for this cmdlet: `Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy`,
never `ApproverNotFound`; the raw lookup `HTTP 403 Authorization_RequestDenied`. The approvers are
resolved before the role and its policy are read, so the role lookup is never reached. Nothing is
written.
**Failure looks like:** `ApproverNotFound`; an error about the role instead of the approver (the order
changed).

Result: 2026-10-05 06:30 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. No output object; the cmdlet's own error is the refused approver lookup itself, Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy (category OperationStopped), exactly once, never ApproverNotFound; no error about the role (the approvers are resolved before the role and its policy are read); the same user lookup made raw answers HTTP 403 Authorization_RequestDenied. Nothing written: -WhatIf and an identity with no permission.

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s83] Output objects: 0; error records: 15; the cmdlet's own: 1
[oer-s83] Own error: Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy; category OperationStopped; target '' -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s83] Any ApproverNotFound: False
[oer-s83] The same lookup, raw: HTTP 403 Authorization_RequestDenied
```

### 2.3. Remove-OERAccessReviewDefinition: a refused read warns that the Lifecycle check could not be made

- [x] **2.3** `Remove-OERAccessReviewDefinition -WhatIf` against a made-up id warns that the definition could not be read and the Lifecycle check could not be made, writes no error, and still plans the delete.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Res = @(Remove-OERAccessReviewDefinition -Id '00000000-0000-0000-0000-000000000099' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue -WarningVariable RunWarn)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Remove-OERAccessReviewDefinition' })
Write-OerLiveStep "Output objects: $($Res.Count); warnings: $(@($RunWarn).Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($W in @($RunWarn)) { Write-OerLiveStep "Warning: $W" }
$Probe = Invoke-OerLiveGraph -Uri 'v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000099'
Write-OerLiveStep "The same read, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** a `What if:` line for the delete of the made-up id; one warning that names the read's
error and says the check for an assignment policy's Lifecycle access review could not be made; the
cmdlet's own errors `0`; the raw read answers `HTTP 403`. Before this branch the failed read was
swallowed and nothing said the check had not been made. Nothing is written: `-WhatIf`, and an
identity with no permission.
**Failure looks like:** no warning (the failure is still swallowed); an error record from the cmdlet
(under a global Stop it would stop the delete).

Result: 2026-10-05 06:30 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, with one measured difference from the Expect line. A What if line plans the delete of the made-up id; besides the cmdlet's usual 'irreversible' warning, one new warning names the read's error and says the check for an assignment policy's Lifecycle access review could not be made and that the delete is not blocked; the cmdlet's own errors 0 (the 6 records are the transport's nested records of the failed read). MEASURED: Graph answered the read of a made-up definition id with 404 NotFound ('Fusion batch response 0 returned not found'), not 403, even for this identity with no permission -- it reports a missing definition before it checks authorization. The warning path is the same for any failed read, so the check stands; a 403 on an existing definition would need a target without this step's prefix, which is a stop condition, so it was not run. Before this branch the failed read was swallowed and nothing said the check had not been made. Nothing written.

[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
What if: Performing the operation "Delete access review definition" on target "00000000-0000-0000-0000-000000000099".
[oer-s83] Output objects: 0; warnings: 2; error records: 6; the cmdlet's own: 0
[oer-s83] Warning: Deleting access review definition '00000000-0000-0000-0000-000000000099'. This is irreversible.
[oer-s83] Warning: Could not read access review definition '00000000-0000-0000-0000-000000000099' before deleting it (NotFound: Fusion batch response 0 returned not found for review 00000000-0000-0000-0000-000000000099.), so the check for an assignment policy's Lifecycle access review could not be made. Whether this definition is an assignment policy's own Lifecycle access review is therefore unknown; if it is, deleting it leaves that policy un-updatable until the review is re-created or 'Require access reviews' is turned off. The delete is not blocked.
[oer-s83] The same read, raw: HTTP 404
```

## Teardown

### T.1. The teardown's plan

- [x] **T.1** `-Teardown -WhatIf` plans only `oer-s83-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s83\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s83-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s83-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the plan deletes, through the library (step 3 of 6), the policies `oer-s83-ext` and
`oer-s83-ext2`, the access package `oer-s83-ap` and the catalog `oer-s83-catalog`, and (step 5 of 6) the
group `oer-s83-approvers`, every tenant target
starting with `oer-s83-`; `WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP.

Result: 2026-10-05 06:30 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Identity check passed; 6 What-if targets: the transcript under raw\s83\ and 5 in the tenant, all through the library: the policies oer-s83-ext2 and oer-s83-ext, the access package oer-s83-ap and the catalog oer-s83-catalog (step 3 of 6), and the group oer-s83-approvers (step 5 of 6), every one with the prefix; nothing removed; exit code 0.

What if: Performing the operation "Start the redacted transcript" on target "raw\s83\teardown-20261005-063034Z.log".
[oer-s83] Mode: REMOVE. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-approvers (no member, the approver); oer-s83-ext (allExternalUsers, approved by oer-s83-approvers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Residue: raw\residue.json holds no rows.
[oer-s83] Teardown of 'oer-s83-': users 0, groups 1, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s83] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s83] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s83] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s83-ap: assignment policy 'oer-s83-ext2'".
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s83-ap: assignment policy 'oer-s83-ext'".
What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s83-ap".
What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s83-catalog".
[oer-s83] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s83] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s83-approvers".
[oer-s83] Teardown 6/6: the prefixed users.
[oer-s83] Teardown of 'oer-s83-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s83] WhatIf: nothing was created, removed or written.
[oer-s83] Done.
[oer-s83] What-if targets: 6; in the tenant: 5; every tenant target starts with oer-s83-: True; exit code: 0
```

### T.2. The teardown

- [x] **T.2** Every `oer-s83-` object is gone, and the counts match the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the library deleting both policies, the package, the catalog and the group; the sweep finding no
`oer-s83-` object (a catalog or package deleted seconds earlier can still be listed for a while --
T.3 reads again); `Counts: catalogs ... equal: True` and `accessPackages ... equal: True`; exit code
`0`.
**Failure looks like:** a `RESIDUE` line or exit code `3` -- record it in the report; exit code `1`.

Result: 2026-10-05 06:31 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, with the known listing delay. The library deleted the policies oer-s83-ext2 and oer-s83-ext (204 each), the access package oer-s83-ap (204), the catalog oer-s83-catalog (204) and the group oer-s83-approvers (204): removed 5, residue 0, unreadable 0; exit code 0. Both counts equal the baseline (catalogs 5, access packages 6). The sweep right after still listed the group: the startswith listing lags a DELETE by seconds to minutes (measured in earlier steps). T.3 reads again minutes later.

[oer-s83] Transcript (redacted): raw\s83\teardown-20261005-063054Z.log; OerLive 1.0.2.
[oer-s83] Mode: REMOVE. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-approvers (no member, the approver); oer-s83-ext (allExternalUsers, approved by oer-s83-approvers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s83] Residue: raw\residue.json holds no rows.
[oer-s83] Teardown of 'oer-s83-': users 0, groups 1, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s83] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s83] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s83] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s83] Deleted: oer-s83-ap: assignment policy 'oer-s83-ext2' (204).
[oer-s83] Deleted: oer-s83-ap: assignment policy 'oer-s83-ext' (204).
[oer-s83] Deleted: access package oer-s83-ap (204, 1 attempt(s)).
[oer-s83] Deleted: catalog oer-s83-catalog (204, 1 attempt(s)).
[oer-s83] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s83] Teardown 5/6: the prefixed groups.
[oer-s83] Deleted: group oer-s83-approvers (204).
[oer-s83] Teardown 6/6: the prefixed users.
[oer-s83] Teardown of 'oer-s83-': removed 5, residue 0, unreadable 0.
[oer-s83] Sweep: group 'oer-s83-approvers' (00000000-0000-0000-0000-000000000007) carries the prefix.
[oer-s83] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s83] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s83] Done.
[oer-s83] Exit code: 0
```

### T.3. Read back, and clean up

- [x] **T.3** Minutes later the sweep is clean, the counts match the baseline, the main clone is still on `main` at the HEAD S.1 recorded, and the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7)); exit code: $Code"
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts `equal:
True`; the main clone on `main` at the HEAD S.1 recorded; exit code `0`. After the results are
copied into this file: `Clear-OerLiveRedactionMap`, and `raw\s83\` deleted.
**Failure looks like:** a prefixed object left, or a residue row -- the teardown did not finish;
record it in the report.

Result: 2026-10-05 06:35 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Minutes after T.2 the sweep finds no oer-s83- object in any of the six collections; prefixed objects left 0, unread collections 0, residue rows 0; catalogs 5 and access packages 6, both equal to the baseline; the main clone on main at 2a86120, the HEAD S.1 recorded, never switched; exit code 0. The redaction map is cleared and raw\s83\ deleted after this write-up.

[oer-s83] Transcript (redacted): raw\s83\readback-20261005-063453Z.log; OerLive 1.0.2.
[oer-s83] Mode: READ BACK. Prefix 'oer-s83-'. Objects (fixed): oer-s83-catalog (published, externally visible); oer-s83-ap (hidden) in it; oer-s83-approvers (no member, the approver); oer-s83-ext (allExternalUsers, approved by oer-s83-approvers) on it. OerLive 1.0.2.
[oer-s83] Omnicit.EntraRBAC 1.1.2 loaded from REPO\.claude\worktrees\s8-steg3\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s83] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s83] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s83-' is left.
[oer-s83] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s83] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s83] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s83] Done.
[oer-s83] Main clone: branch main; HEAD 2a86120; exit code: 0
```
