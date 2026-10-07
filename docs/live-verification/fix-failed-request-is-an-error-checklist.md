# Live verification checklist -- a successful row means it succeeded (fix/failed-request-is-an-error)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates two role-assignable security
groups with no member, `oer-s95-grp` and `oer-s95-grp2`, one empty resource group, `oer-s95-rg`, in the
test subscription, and a catalog `oer-s95-cat` holding a hidden access package `oer-s95-ap` with one
administrator-only assignment policy `oer-s95-pol`. It records two baselines before the first write:
the tenant's group, catalog and access package counts together with the direct holders of the two
low-risk directory roles, and the Reader role's policy at `oer-s95-rg`. Section 1 gives
`oer-s95-grp` a time-bound eligible and active assignment of one low-risk directory role and removes
them; section 2 does the same through `Invoke-OERStructure`, and removes them with `-Prune` while
`oer-s95-grp2` receives the role; section 3 gives `oer-s95-grp` the Reader role at `oer-s95-rg`,
eligible and active, and removes it; section 4 gives it a PERMANENT active Reader assignment there,
which opens the Reader policy at `oer-s95-rg` for permanent active assignments; section 5 sends a
refused update and one description change to `oer-s95-pol`. The teardown removes the Azure schedules
at `oer-s95-rg`, every prefixed object through OerLive's fixed order, puts the Reader policy at
`oer-s95-rg` back to its baseline and deletes the resource group. No role policy outside `oer-s95-rg`
is written, and no directory role policy at all.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop. Neither `oer-live-cc` nor `oer-live-cc-noperm` is ever a principal here: every
assignment names a prefixed group.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive -Arm`, which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s95/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed**, and **no error record is ever rendered**: every
block prints the error id, its category and the message (redacted, cut at 300 characters) only. A
`-WhatIf` line goes straight to the host and cannot be redirected inside one process, so every block
that runs a module cmdlet with `-WhatIf` (2.3 and 4.2) runs it in a CHILD process and prints the
child's whole output through the redactor.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-33: a schedule request answered with a Failed status is an error** ("report a failed
  schedule request as an error"). Eleven cmdlets emitted whatever status Microsoft Graph or Azure
  Resource Manager answered, so a request accepted but answered `Failed` read as a success, and the
  apply engine reported such a row `Created`, `Updated` or `Removed`. They now emit the request object
  and then write `EligibilityRequestFailed` (the eligibility variants) or the new
  `AssignmentRequestFailed` (the active variants, and `Enable-`/`Disable-OEREligibleRoleAssignment`)
  for `Failed` and every status starting with `Failed`, in any letter case. One private owner,
  `Test-OERScheduleRequestFailed`, decides it for all twelve cmdlets (`Add-OERGroupEligibility`
  included) and the engine's two new-group waits. `Revoked` is a removal's success.
- **B. BL-50: `Set-OERAccessPackageAssignmentPolicy` refuses a connected-organization scope with no
  target.** A `-RequestorScope` of `SpecificConnectedOrganizationUsers` with no target -- the only one
  `New-OERAccessPackageRequestorScope` can build -- would have replaced every connected organization
  the live policy names with an empty list. It is now refused with `InvalidPolicyInput` after the
  policy is read and before the confirmation gate, and nothing is sent.
- **C. BL-80: `New-OERActiveRoleAssignment` opens the role policy only after consent.** A permanent
  active assignment that needs the Azure role policy opened used to open it before the confirmation
  gate, so a declined prompt still weakened the policy. It now does what
  `New-OEREligibleRoleAssignment` does: the read and its warning before the gate, the open only once
  the assignment is confirmed (`-WhatIf` still plans it), a rollback when the assignment fails or is
  answered `Failed`, and `PolicyOpenedButGrantFailed` when a thrown grant follows an open.

A live tenant is needed for what the unit tests stub: that the REAL answers of a successful request
-- `Provisioned` for a grant, `Revoked` for a removal -- are not taken for a failure by the new rule,
on Microsoft Graph's directory role endpoints and on Azure Resource Manager (sections 1 and 3); that
the apply engine still reports `Created`, `Unchanged` and `Removed` (section 2, G8); the real order of
the policy open and the grant, and that `-WhatIf` writes nothing (section 4); and the refusal counted
by fences around the module's real transports (section 5).

## What this file does not check, and why

- **A Failed answer (class B, G9).** No request can be made to fail on demand: Graph answers
  `Failed` only in a replication window (measured live in Sprint 7 step 3, run 0: two 404s, then a 201
  whose status was already `Failed`, for PIM for Groups). Proved offline with the REAL cmdlets and only
  the transport answering, in each cmdlet's test file (the Context for a Failed answer), in
  `tests/Unit/Private/Test-OERScheduleRequestFailed.Tests.ps1` (the rule, and the check that no other
  file compares a status to a `'Failed'` literal), in
  `tests/Unit/Private/Sync-OERStructureDirectoryRoleAssignment.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (the engine's three paths), with that live
  answer's shape as the fixture, and in a script with no `try`.
- **A declined confirmation gate (class B, G9).** Declining needs a person at a prompt. Proved
  offline in the answering runspace of `tests/Unit/TestHelpers/OERConfirmHost.ps1`: the decline tests
  of `tests/Unit/Public/New-OERActiveRoleAssignment.Tests.ps1`, with the `Yes` control, and the AST
  check that every policy write sits under the gate's decision.
- **`Enable-OEREligibleRoleAssignment` and `Disable-OEREligibleRoleAssignment` (class B, G9).** They
  send a SelfActivate / SelfDeactivate request for the signed-in identity's own eligibility, and this
  file never makes `oer-live-cc` a principal (G6). Proved offline in their test files.
- **The rollback after a refused or Failed grant (class B).** It needs Azure to refuse or fail a grant
  after the open. Proved offline in `tests/Unit/Public/New-OERActiveRoleAssignment.Tests.ps1` and, for
  the eligible cmdlet, `tests/Unit/Public/New-OEREligibleRoleAssignment.Tests.ps1`.
- **`Remove-OERGroupEligibility` live.** It shares the rule and the converter with
  `Add-OERGroupEligibility`, whose live answers earlier steps recorded; its Failed path and the engine's
  prune of it are class B above.
- **Convergence (G8)** applies to section 2, the apply engine's write path: 2.2 and 2.5 run each
  document again. Sections 1, 3 and 4 call cmdlets, and a create sent twice is a second request, not a
  convergence check.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **prerequisite script** `Initialize-OerS95Prereq.ps1` beside OerLive (outside the repository).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.1 read that it was not).

**Run every numbered block in its OWN PowerShell process**, except where a section says that its
checks share one.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Test-OERScheduleRequestFailed' -Quiet)
$A2 = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch "-ErrorId 'AssignmentRequestFailed'").Count
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'New-OERAccessPackageRequestorScope cannot name one' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$Proceed = $PSCmdlet.ShouldProcess($Target, ''Create active Azure role assignment'')' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A (AssignmentRequestFailed sites: $A2); B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True (AssignmentRequestFailed sites: 6); B: True;
C: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; `False`, or a lower count, on the last line -- build the worktree first
(`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-07 09:12 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:24 UTC. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 6817b33, never switched; the worktree on this branch at 29f4193 (the final fix wave, built there before this run) with 0 tracked changes; the build carries A (Test-OERScheduleRequestFailed: True; AssignmentRequestFailed in the six active-variant cmdlets: 6), B (the BL-50 refusal: True) and C (the BL-80 gate decision: True). 0.1 to 0.3 ran earlier against the 040bb3c build; the commits after it change only help, comments and the rationale.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] The module loads from a worktree that is not the main clone: True
[oer-s95] Main clone: branch main; HEAD 6817b33
[oer-s95] Worktree: branch fix/failed-request-is-an-error; HEAD 29f4193 docs: correct the help and comments on the owner and the policy rollback; tracked changes: 0
[oer-s95] The worktree's build carries A: True (AssignmentRequestFailed sites: 6); B: True; C: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result: 2026-10-07 08:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 08:48 UTC: every identity line True for the module session as oer-live-cc (app-only certificate session, app name, test tenant, service principal named oer-live-cc and the token's signed-in object, organization, verified domain, ARM token from the certificate, test subscription Enabled); identity check passed; the module is the worktree's build (1.1.3, built at 040bb3c).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module is the worktree's build: True
```

### 0.2. The prerequisite plan names only oer-s95- objects

- [x] **0.2** `Initialize-OerS95Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every tenant `What if:` target starts with `oer-s95-`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baseline) go to raw\s95\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s95\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s95\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s95\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s95-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s95-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own local files under `raw\s95\` (the transcript and, on a first run, the count baseline);
the direct holders of Reports Reader and Message Center Reader, and the role the checklist will use;
and the tenant targets `oer-s95-grp`, `oer-s95-grp2`, `oer-s95-rg`, `oer-s95-cat`, `oer-s95-ap` and
`oer-s95-ap: oer-s95-pol` (none that exists already), every tenant target starting with `oer-s95-`
(`True`); a "No Reader-policy baseline" line, since under `-WhatIf` the resource group does not exist
yet.
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run.

Result: 2026-10-07 08:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 08:48 UTC: identity check passed; no residue; the sweep finds nothing with the prefix; no baseline yet; Reports Reader and Message Center Reader have no direct tenant-scope holder, so the checklist uses Reports Reader. The plan: the transcript and the count baseline under raw\s95\, and six tenant targets, oer-s95-grp, oer-s95-grp2, oer-s95-rg, oer-s95-cat, oer-s95-ap and oer-s95-ap: oer-s95-pol, every one with the prefix (True); no Reader-policy baseline under -WhatIf. WhatIf: nothing was created or written. Read and confirmed by the controller before 0.3.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] What if: Performing the operation "Start the redacted transcript" on target "raw\s95\prereq-20261007-084831Z.log".
[oer-s95] [oer-s95] Mode: CREATE or complete. Prefix 'oer-s95-'. Objects (fixed): oer-s95-grp, oer-s95-grp2 (role-assignable, no member); oer-s95-rg (tagged, empty, its Reader policy baselined); oer-s95-cat, oer-s95-ap (hidden), oer-s95-pol (administrator-only). OerLive 1.0.3.
[oer-s95] [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] [oer-s95] Residue: raw\residue.json holds no rows.
[oer-s95] [oer-s95] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s95-' is left.
[oer-s95] [oer-s95] Found: oer-s95-grp exists: False; oer-s95-grp2 exists: False; oer-s95-rg exists: False; oer-s95-cat exists: False; oer-s95-ap exists: False.
[oer-s95] [oer-s95] Directory role 'Reports Reader': direct tenant-scope eligible schedules 0, active (Assigned) 0.
[oer-s95] [oer-s95] Directory role 'Message Center Reader': direct tenant-scope eligible schedules 0, active (Assigned) 0.
[oer-s95] [oer-s95] No baseline yet: it is written now, before the first write to the tenant (groups 98, catalogs 5, access packages 6; oer-s95-rg exists: False; the checklist's directory role: 'Reports Reader' (no direct holder)).
[oer-s95] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s95\baseline-s95.json".
[oer-s95] What if: Performing the operation "Create a role-assignable security group with no member (Graph v1.0 POST groups: isAssignableToRole true, not mail-enabled, assigned membership)" on target "oer-s95-grp".
[oer-s95] What if: Performing the operation "Create a role-assignable security group with no member (Graph v1.0 POST groups: isAssignableToRole true, not mail-enabled, assigned membership)" on target "oer-s95-grp2".
[oer-s95] What if: Performing the operation "Create the resource group in the test subscription (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s95)')" on target "oer-s95-rg".
[oer-s95] What if: Performing the operation "Create a catalog, not externally visible (Graph v1.0 POST catalogs)" on target "oer-s95-cat".
[oer-s95] What if: Performing the operation "Create a HIDDEN access package in oer-s95-cat, no resource role (Graph v1.0 POST accessPackages)" on target "oer-s95-ap".
[oer-s95] What if: Performing the operation "Create an administrator-only assignment policy: allowedTargetScope notSpecified, no approval, no expiration (Graph v1.0 POST assignmentPolicies)" on target "oer-s95-ap: oer-s95-pol".
[oer-s95] [oer-s95] No Reader-policy baseline: oer-s95-rg does not exist (WhatIf).
[oer-s95] [oer-s95] Summary: oer-s95-grp absent; oer-s95-grp2 absent; oer-s95-rg absent; oer-s95-cat absent; oer-s95-ap absent; oer-s95-pol absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s95] [oer-s95] WhatIf: nothing was created, removed or written.
[oer-s95] [oer-s95] Done.
[oer-s95] Planned writes: 8; local files under raw\s95\: 2; tenant targets: 6; every tenant target starts with oer-s95-: True
```

### 0.3. The prerequisite objects and the baselines

- [x] **0.3** `Initialize-OerS95Prereq.ps1 -Unattended` writes the baseline when there is none (with the directory role the checklist uses), creates the two groups, the resource group, the catalog, the package and its policy, and records the Reader-policy baseline at the resource group.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the identity lines `True`; the baseline written before the first write, naming the
directory role the checklist uses (one of the two with no direct holder) or saying none is free;
`Created group oer-s95-grp (role-assignable)`, the same for `oer-s95-grp2`, `Created resource group
oer-s95-rg`, the catalog, the hidden package and the administrator-only policy; `Reader policy at
oer-s95-rg: rules N; permanent active assignment allowed: False` and the baseline written; exit code
0.
**Failure looks like:** a 403 on creating a role-assignable group, the catalog, the package or the
policy -- STOP: a missing permission on the app path (G6); exit code 1 with `Refusing to run` -- read
the reason.

Result: 2026-10-07 08:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 08:48 UTC: identity check passed; the baseline written before the first write (groups 98, catalogs 5, access packages 6; oer-s95-rg absent; the checklist's directory role Reports Reader, no direct holder); both groups created role-assignable (201; oer-s95-grp resolved by name after 4 reads, 14.3 s, replication delay); the resource group, the catalog, the hidden package and the administrator-only policy created (201); the Reader policy at oer-s95-rg read as the scope's own (17 rules; permanent active assignment allowed: False) and its baseline written; exit code 0.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [oer-s95] Transcript (redacted): raw\s95\prereq-20261007-084855Z.log; OerLive 1.0.3.
[oer-s95] [oer-s95] Mode: CREATE or complete. Prefix 'oer-s95-'. Objects (fixed): oer-s95-grp, oer-s95-grp2 (role-assignable, no member); oer-s95-rg (tagged, empty, its Reader policy baselined); oer-s95-cat, oer-s95-ap (hidden), oer-s95-pol (administrator-only). OerLive 1.0.3.
[oer-s95] [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] [oer-s95] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s95] [oer-s95] Residue: raw\residue.json holds no rows.
[oer-s95] [oer-s95] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s95-' is left.
[oer-s95] [oer-s95] Found: oer-s95-grp exists: False; oer-s95-grp2 exists: False; oer-s95-rg exists: False; oer-s95-cat exists: False; oer-s95-ap exists: False.
[oer-s95] [oer-s95] Directory role 'Reports Reader': direct tenant-scope eligible schedules 0, active (Assigned) 0.
[oer-s95] [oer-s95] Directory role 'Message Center Reader': direct tenant-scope eligible schedules 0, active (Assigned) 0.
[oer-s95] [oer-s95] No baseline yet: it is written now, before the first write to the tenant (groups 98, catalogs 5, access packages 6; oer-s95-rg exists: False; the checklist's directory role: 'Reports Reader' (no direct holder)).
[oer-s95] [oer-s95] Wrote the baseline raw\s95\baseline-s95.json and read it back.
[oer-s95] [oer-s95] Created group oer-s95-grp (role-assignable): 201.
[oer-s95] [oer-s95] oer-s95-grp resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s95] [oer-s95] oer-s95-grp resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s95] [oer-s95] oer-s95-grp resolves by its display name: not yet (read 3, 6.3 s, likely replication delay) -- reading again in 8 s.
[oer-s95] [oer-s95] oer-s95-grp resolves by its display name: converged after 4 read(s), 14.3 s.
[oer-s95] [oer-s95] Created group oer-s95-grp2 (role-assignable): 201.
[oer-s95] [oer-s95] oer-s95-grp2 resolves by its display name: converged after 1 read(s), 0.1 s.
[oer-s95] [oer-s95] Created resource group oer-s95-rg.
[oer-s95] [oer-s95] Created catalog oer-s95-cat: 201.
[oer-s95] [oer-s95] Created access package oer-s95-ap (hidden): 201 after 1 attempt(s).
[oer-s95] [oer-s95] Created assignment policy oer-s95-pol (administrator-only): 201 after 1 attempt(s).
[oer-s95] [oer-s95] The scope lists its role management policy: converged after 1 read(s), 3.8 s.
[oer-s95] [oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] [oer-s95] Reader policy at oer-s95-rg: rules 17; permanent active assignment allowed: False
[oer-s95] [oer-s95] Wrote the baseline raw\s95\baseline-s95-rgreader.json and read it back.
[oer-s95] [oer-s95] Summary: oer-s95-grp present; oer-s95-grp2 present; oer-s95-rg present; oer-s95-cat present; oer-s95-ap present; oer-s95-pol present; written to the tenant: True.
[oer-s95] [oer-s95] Done.
[oer-s95] Exit code: 0
```

## 1. BL-33: the directory role cmdlets on a real Provisioned and Revoked answer

**1.0 to 1.4 run in ONE process**, in order. The fences count every Graph and Azure Resource Manager
request the module sends, by method; each is a global function the module's unqualified
`Invoke-MgGraphRequest` or `Invoke-WebRequest` resolves to (a function outranks a cmdlet), and it
forwards each request to the real cmdlet, module-qualified. The role is the one the baseline names
(Reports Reader when the baseline names none: the cmdlets remove nothing but the test group's own
assignments). Principal: `oer-s95-grp`.

### 1.0. The fences and the role

- [x] **1.0** The module resolves both transports to the fences, and the section's directory role is a low-risk one.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
$null = [System.IO.Directory]::CreateDirectory($Raw)
[System.IO.File]::WriteAllText($FencePath, @'
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { `$M = if ([string]`$Method) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S95GraphWrites++ }; `$global:S95GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'Get') { `$global:S95ArmWrites++; `$global:S95ArmLog.Add(`"`$(([string]`$Method).ToUpperInvariant()) `$(if ([string]`$Uri -match 'providers/Microsoft\.Authorization/([A-Za-z]+)') { `$Matches[1] } else { 'other' })`") }; `$global:S95ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$global:S95ArmLog = [System.Collections.Generic.List[string]]::new()
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Invoke-S95 {
    # A plain call, outside any try, as at a prompt. Prints the output objects (a StructureResult as
    # section, item, action and detail; a request object as its type, Status and expiration type), the
    # warnings, the error ids with their category and message, and the request counts; never a token,
    # never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S95GraphCalls = 0; $global:S95GraphWrites = 0; $global:S95ArmCalls = 0; $global:S95ArmWrites = 0
    $global:S95ArmLog.Clear()
    $All = @(& $Call 2>&1 3>&1)
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S95GraphCalls (writes: $global:S95GraphWrites); ARM requests: $global:S95ArmCalls (writes: $global:S95ArmWrites$(if ($global:S95ArmLog.Count) { ": $($global:S95ArmLog -join ', ')" }))"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
        } elseif ($O.PSObject.Properties['Status']) {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0]); Status $($O.Status)$(if ($O.PSObject.Properties['ExpirationType']) { "; expiration $($O.ExpirationType)" })"
        } else {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0])"
        }
    }
    foreach ($W in $Warns) {
        $Text = ConvertTo-OerLiveRedacted -Text $W.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): warning -- $Text"
    }
    foreach ($E in $Errs) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): $(([string]$E.FullyQualifiedErrorId -split ',')[0]); category $($E.CategoryInfo.Category) -- $Text"
    }
    , $Out
}
'@, [System.Text.UTF8Encoding]::new($false))
. $FencePath
$Base = Read-OerLiveBaseline -Name 'baseline-s95'
$Role = if ($Base -and $Base['directoryRole']) { [string]$Base['directoryRole'] } else { 'Reports Reader' }
Write-OerLiveStep "1.0 the section's directory role: '$Role'; low-risk: $(@('Reports Reader', 'Message Center Reader') -ccontains $Role); the baseline names a role with no direct holder: $([bool]($Base -and $Base['directoryRole']))"
```

**Expect:** the identity lines `True`; the fences `True`; the role `'Reports Reader'` or `'Message
Center Reader'`, low-risk `True`.
**Failure looks like:** the fences `False` -- nothing was called; a role that is not low-risk -- STOP.

Result: 2026-10-07 09:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:27 UTC as oer-live-cc (every identity line True), with the fences resolving for the module (True). The section's role is Reports Reader, low-risk True, and the baseline names it as free of direct holders (True).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s95] 1.0 the section's directory role: 'Reports Reader'; low-risk: True; the baseline names a role with no direct holder: True
```

### 1.1. New-OEREligibleDirectoryRoleAssignment: Provisioned, no error

- [x] **1.1** `New-OEREligibleDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one Graph write.

```powershell
$null = Invoke-S95 -Label '1.1 eligible create' -Call { New-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; Graph requests: N (writes: 1)`; `object
Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Provisioned; expiration afterDuration` (or
`afterDateTime`).
**Failure looks like:** `EligibilityRequestFailed` on a `Provisioned` object -- the rule takes a
success for a failure; any other error -- read it.

Result: 2026-10-07 09:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. New-OEREligibleDirectoryRoleAssignment, Reports Reader, oer-s95-grp, one day: one request object, Status Provisioned, expiration afterDuration; errors none; 4 Graph requests, 1 write. The new rule does not take the real success answer for a failure.

[oer-s95] 1.1 eligible create: output objects 1; errors: none; Graph requests: 4 (writes: 1); ARM requests: 0 (writes: 0)
[oer-s95] 1.1 eligible create: object Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Provisioned; expiration afterDuration
```

### 1.2. New-OERActiveDirectoryRoleAssignment: Provisioned, no error

- [x] **1.2** `New-OERActiveDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one Graph write.

```powershell
$null = Invoke-S95 -Label '1.2 active create' -Call { New-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
$ActiveAt = [datetime]::UtcNow
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Provisioned`.
**Failure looks like:** `AssignmentRequestFailed` on a `Provisioned` object -- the rule takes a
success for a failure.

Result: 2026-10-07 09:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. New-OERActiveDirectoryRoleAssignment, Reports Reader, oer-s95-grp, one day: one request object, Status Provisioned, expiration afterDuration; errors none; 4 Graph requests, 1 write.

[oer-s95] 1.2 active create: output objects 1; errors: none; Graph requests: 4 (writes: 1); ARM requests: 0 (writes: 0)
[oer-s95] 1.2 active create: object Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Provisioned; expiration afterDuration
```

### 1.3. Remove-OEREligibleDirectoryRoleAssignment: Revoked, no error

- [x] **1.3** After the active assignment has run five minutes, `Remove-OEREligibleDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error.

```powershell
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $ActiveAt).TotalSeconds))
Write-OerLiveStep "1.3 waiting $Wait s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes."
Start-Sleep -Seconds $Wait
$null = Invoke-S95 -Label '1.3 eligible remove' -Call { Remove-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Revoked`; the cmdlet's own
removal warning.
**Failure looks like:** `EligibilityRequestFailed` on a `Revoked` object -- a removal's success read as
a failure; `ActiveDurationTooShort` -- wait longer and run 1.3 again.

Result: 2026-10-07 09:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After waiting 305 s (the five-minute rule), Remove-OEREligibleDirectoryRoleAssignment: one request object, Status Revoked; errors none; 3 Graph requests, 1 write; the cmdlet's own removal warning. A removal's success is not read as a failure.

[oer-s95] 1.3 waiting 305 s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes.
[oer-s95] 1.3 eligible remove: output objects 1; errors: none; Graph requests: 3 (writes: 1); ARM requests: 0 (writes: 0)
[oer-s95] 1.3 eligible remove: object Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Revoked; expiration 
[oer-s95] 1.3 eligible remove: warning -- Removing eligible directory role 'Reports Reader' for principal 'oer-s95-grp' at directory scope '/'.
```

### 1.4. Remove-OERActiveDirectoryRoleAssignment: Revoked, no error, and nothing left

- [x] **1.4** `Remove-OERActiveDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error; afterwards neither kind is listed for the group.

```powershell
$null = Invoke-S95 -Label '1.4 active remove' -Call { Remove-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -Confirm:$false }
$W = Wait-OerLiveConverged -Activity "1.4 oer-s95-grp holds no '$Role' assignment" -Read {
    , @(@(Get-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "1.4 oer-s95-grp holds no '$Role' assignment: True ($($W.Attempts) read(s), $($W.Seconds) s)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Revoked`; `holds no ...
assignment: True`.
**Failure looks like:** `AssignmentRequestFailed` on a `Revoked` object; a wait that does not
converge -- the teardown removes what is left.

Result: 2026-10-07 09:19 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Remove-OERActiveDirectoryRoleAssignment: one request object, Status Revoked; errors none; 3 Graph requests, 1 write; the removal warning; oer-s95-grp holds no Reports Reader assignment after 1 read (1.3 s).

[oer-s95] 1.4 active remove: output objects 1; errors: none; Graph requests: 3 (writes: 1); ARM requests: 0 (writes: 0)
[oer-s95] 1.4 active remove: object Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Revoked; expiration 
[oer-s95] 1.4 active remove: warning -- Removing active directory role 'Reports Reader' for principal 'oer-s95-grp' at directory scope '/'.
[oer-s95] 1.4 oer-s95-grp holds no 'Reports Reader' assignment: converged after 1 read(s), 1.3 s.
[oer-s95] 1.4 oer-s95-grp holds no 'Reports Reader' assignment: True (1 read(s), 1.3 s)
```

## 2. BL-33: the apply engine's directory role rows, created, unchanged and pruned (G8)

**2.1 to 2.5 run in ONE process**, in order, with the fences of section 1 (the first block loads them
from the file 1.0 wrote); 2.3 runs its `-WhatIf` plan in a child process of its own. Two apply documents in the
step's raw folder, deleted at the end of 2.5, each declaring the section's role, eligible and active,
time-bound one day:

- **document A** -- principal `oer-s95-grp`;
- **document B** -- principal `oer-s95-grp2`. Applied with `-Prune`, the pairs it declares make
  `oer-s95-grp`'s two assignments undeclared candidates, which are removed.

**The prune runs only when the baseline names a role with no direct holder.** Otherwise a
`-Prune` of that role would remove a real holder's assignment: 2.3 to 2.5 are then `[~]`, class B,
and 2.1 and 2.2 still run.

### 2.1. Document A: Created, Created

- [x] **2.1** `Invoke-OERStructure -Path` (document A) `-Confirm:$false` reports both rows `Created`, no error, two Graph writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Base = Read-OerLiveBaseline -Name 'baseline-s95'
$Role = if ($Base -and $Base['directoryRole']) { [string]$Base['directoryRole'] } else { 'Reports Reader' }
$PruneAllowed = [bool]($Base -and $Base['directoryRole'])
function New-S95Doc {
    param([string]$Name, [string]$Principal)
    $Path = Join-Path $Raw $Name
    $null = [System.IO.Directory]::CreateDirectory($Raw)
    [System.IO.File]::WriteAllText($Path, (@{
                version                  = '1.0'
                directoryRoleAssignments = @(
                    @{ role = $Role; principal = $Principal; principalType = 'Group'; assignmentType = 'Eligible'; durationDays = 1 }
                    @{ role = $Role; principal = $Principal; principalType = 'Group'; assignmentType = 'Active'; durationDays = 1 }
                )
            } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    $Path
}
$DocA = New-S95Doc -Name 'apply-s95-a.json' -Principal 'oer-s95-grp'
$DocB = New-S95Doc -Name 'apply-s95-b.json' -Principal 'oer-s95-grp2'
Write-OerLiveStep "2.1 role '$Role'; the prune checks run: $PruneAllowed"
$null = Invoke-S95 -Label '2.1 document A' -Call { Invoke-OERStructure -Path $DocA -Confirm:$false }
$CreatedAt = [datetime]::UtcNow
```

**Expect:** `errors: none; ... (writes: 2)`; two rows `directoryRoleAssignments | ... -> oer-s95-grp
(Eligible) | Created` and `(Active) | Created`.
**Failure looks like:** a `Failed` row with `EligibilityRequestFailed` or `AssignmentRequestFailed` --
a success read as a failure; a `Created` row with an error -- the old defect.

Result: 2026-10-07 09:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:34 UTC as oer-live-cc (identity True, fences True); role Reports Reader; the prune checks run (True). Document A: errors none; 16 Graph requests, 2 writes; both rows Created (eligible and active, time-bound one day). A real Provisioned answer through the apply engine still reads Created.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s95] 2.1 role 'Reports Reader'; the prune checks run: True
[oer-s95] 2.1 document A: output objects 2; errors: none; Graph requests: 16 (writes: 2); ARM requests: 0 (writes: 0)
[oer-s95] 2.1 document A: row directoryRoleAssignments | Reports Reader -> oer-s95-grp (Eligible) | Created | created the eligible assignment (time-bound assignment (1 days) is absent)
[oer-s95] 2.1 document A: row directoryRoleAssignments | Reports Reader -> oer-s95-grp (Active) | Created | created the active assignment (time-bound assignment (1 days) is absent)
```

### 2.2. Document A again: only Unchanged (G8)

- [x] **2.2** The same document A again: both rows `Unchanged`, no Graph write.

```powershell
$null = Invoke-S95 -Label '2.2 document A again' -Call { Invoke-OERStructure -Path $DocA -Confirm:$false }
```

**Expect:** `errors: none; ... (writes: 0)`; two rows `Unchanged`.
**Failure looks like:** a write, or a row other than `Unchanged`.

Result: 2026-10-07 09:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). Document A again: errors none; 12 Graph requests, 0 writes; both rows Unchanged, "assignment matches".

[oer-s95] 2.2 document A again: output objects 2; errors: none; Graph requests: 12 (writes: 0); ARM requests: 0 (writes: 0)
[oer-s95] 2.2 document A again: row directoryRoleAssignments | Reports Reader -> oer-s95-grp (Eligible) | Unchanged | assignment matches
[oer-s95] 2.2 document A again: row directoryRoleAssignments | Reports Reader -> oer-s95-grp (Active) | Unchanged | assignment matches
```

### 2.3. Document B with -Prune -WhatIf: the plan removes only oer-s95-grp's two assignments

- [x] **2.3** After the active assignment has run five minutes, `Invoke-OERStructure -Path` (document B) `-Prune -WhatIf`, in a child process, plans `would create` for `oer-s95-grp2` twice and `would remove` for `oer-s95-grp` twice and for no other principal, and writes nothing.

```powershell
if (-not $PruneAllowed) { Write-OerLiveStep '2.3 SKIPPED: the baseline names no role free of direct holders; 2.3 to 2.5 are class B.' } else {
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $CreatedAt).TotalSeconds))
Write-OerLiveStep "2.3 waiting $Wait s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes."
Start-Sleep -Seconds $Wait
$GrpId = [string](Get-OERGroup -Group 'oer-s95-grp' -ErrorAction Stop).Id
$Child = Join-Path $Raw 'child-s95-2.3.ps1'
[System.IO.File]::WriteAllText($Child, @"
`$ErrorActionPreference = 'Continue'
Import-Module (Join-Path '$VaultDir' 'OerLive\OerLive.psm1') -Force
`$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory '$VaultDir'
`$Cfg.Repo = '$($Cfg.Repo)'
Connect-OerLive -Arm
`$Rows = @(Invoke-OERStructure -Path '$DocB' -Prune -WhatIf 2>&1 3>&1)
foreach (`$R in `$Rows) {
    if (`$R.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') { "ROW|`$(`$R.Action)|`$(`$R.Item)|`$(`$R.Detail)" }
    elseif (`$R -is [System.Management.Automation.ErrorRecord]) { "ERROR|`$(([string]`$R.FullyQualifiedErrorId -split ',')[0])" }
    elseif (`$R -is [System.Management.Automation.WarningRecord]) { "WARNING|`$(`$R.Message)" }
}
Disconnect-OerLive
"@, [System.Text.UTF8Encoding]::new($false))
$ChildOut = @(& pwsh -NoProfile -File $Child 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $ChildOut) { Write-OerLiveStep "2.3 child: $(ConvertTo-OerLiveRedacted -Text $Line)" }
Remove-Item -LiteralPath $Child
$PlanRows = @($ChildOut | Where-Object { $_.StartsWith('ROW|') })
$Removes = @($PlanRows | Where-Object { $_ -match '^ROW\|Skipped\|' -and $_ -match '\|would remove ' })
$Foreign = @($Removes | Where-Object { $_ -notmatch [regex]::Escape($GrpId) })
$WhatIfLines = @($ChildOut | Where-Object { $_ -match '^What if: ' })
Write-OerLiveStep "2.3 plan rows: $($PlanRows.Count); would remove: $($Removes.Count); a would-remove row names a principal other than oer-s95-grp: $($Foreign.Count -gt 0); What if lines: $($WhatIfLines.Count); errors: $(@($ChildOut | Where-Object { $_.StartsWith('ERROR|') }).Count)"
if ($Foreign.Count -gt 0 -or $Removes.Count -ne 2) { Disconnect-OerLive; throw 'STOP: the prune plan does not remove exactly oer-s95-grp''s two assignments; 2.4 is not run.' }
}
```

**Expect:** the child's identity lines `True`; four plan rows, two `Skipped | ... -> oer-s95-grp2 ...
| would create ...` and two `Skipped | ... | would remove undeclared ... assignment of directory role
... for principal ...` whose principal is `oer-s95-grp` (`a would-remove row names a principal other
than oer-s95-grp: False`, `would remove: 2`); `errors: 0`; the child's `What if:` lines redacted.
**Failure looks like:** a would-remove row for another principal -- STOP, 2.4 is not run (a real
holder of the role); fewer than two -- read the plan.

Result: 2026-10-07 09:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After waiting 302 s, document B with -Prune -WhatIf in a child process: the child's identity lines True; four plan rows: two Skipped "would remove undeclared ... assignment" for one principal, oer-s95-grp (its id redacted as ...04, the id the block read for the group), and two Skipped "would create" for oer-s95-grp2; would remove 2; a would-remove row names another principal: False; the four What if lines and the two handler warnings, redacted; errors 0. Nothing was written.

[oer-s95] 2.3 waiting 302 s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes.
[oer-s95] 2.3 child: [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] 2.3 child: [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] 2.3 child: [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] 2.3 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] 2.3 child: What if: Performing the operation "Remove undeclared eligible directory role assignment" on target "Reports Reader -> 00000000-0000-0000-0000-000000000004 (Eligible)".
[oer-s95] 2.3 child: What if: Performing the operation "Remove undeclared active directory role assignment" on target "Reports Reader -> 00000000-0000-0000-0000-000000000004 (Active)".
[oer-s95] 2.3 child: What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s95-grp2 (Eligible)".
[oer-s95] 2.3 child: What if: Performing the operation "create active directory role assignment" on target "Reports Reader -> oer-s95-grp2 (Active)".
[oer-s95] 2.3 child: WARNING|Sync-OERStructureDirectoryRoleAssignment: would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'.
[oer-s95] 2.3 child: WARNING|Sync-OERStructureDirectoryRoleAssignment: would remove undeclared active assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'.
[oer-s95] 2.3 child: ROW|Skipped|Reports Reader -> 00000000-0000-0000-0000-000000000004 (Eligible)|would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'
[oer-s95] 2.3 child: ROW|Skipped|Reports Reader -> 00000000-0000-0000-0000-000000000004 (Active)|would remove undeclared active assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'
[oer-s95] 2.3 child: ROW|Skipped|Reports Reader -> oer-s95-grp2 (Eligible)|would create the eligible assignment (time-bound assignment (1 days) is absent)
[oer-s95] 2.3 child: ROW|Skipped|Reports Reader -> oer-s95-grp2 (Active)|would create the active assignment (time-bound assignment (1 days) is absent)
[oer-s95] 2.3 plan rows: 4; would remove: 2; a would-remove row names a principal other than oer-s95-grp: False; What if lines: 4; errors: 0
```

### 2.4. Document B with -Prune: Created twice, Removed twice

- [x] **2.4** `Invoke-OERStructure -Path` (document B) `-Prune -Confirm:$false` reports the two `oer-s95-grp2` rows `Created` and the two `oer-s95-grp` rows `Removed`, no `Failed` row and no error.

```powershell
if (-not $PruneAllowed) { Write-OerLiveStep '2.4 SKIPPED: class B (see 2.3).' } else {
$null = Invoke-S95 -Label '2.4 document B, prune' -Call { Invoke-OERStructure -Path $DocB -Prune -Confirm:$false }
$W = Wait-OerLiveConverged -Activity "2.4 oer-s95-grp holds no '$Role' assignment" -Read {
    , @(@(Get-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "2.4 oer-s95-grp holds no '$Role' assignment: True ($($W.Attempts) read(s), $($W.Seconds) s)"
}
```

**Expect:** `errors: none; ... (writes: 5)` -- the two removals, the two creates, and the POST
`getMemberGroups` read of the signed-in identity's memberships (the handler's guard 4 for a group
candidate), which the fence counts as a non-GET request; rows `Removed` twice (`removed undeclared eligible ...`
and `active ...`) and `Created` twice for `oer-s95-grp2`; the handler's prune warnings; `holds no ...
assignment: True`.
**Failure looks like:** a `Failed` row carrying `EligibilityRequestFailed` or
`AssignmentRequestFailed` on a `Revoked` answer -- a removal's success read as a failure.

Result: 2026-10-07 09:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Document B with -Prune: errors none; 19 Graph requests, 5 non-GET: the two removals, the two creates, and the POST getMemberGroups read of the signed-in identity's memberships (guard 4, run for a group candidate), which the fence counts as non-GET. The checklist's Expect said 4 and is corrected to 5 with that reason; nothing extra was written. Rows: Removed twice for oer-s95-grp (eligible and active), Created twice for oer-s95-grp2; the prune warnings; oer-s95-grp holds no Reports Reader assignment after 1 read (1.1 s). A real Revoked answer through the engine still reads Removed.

[oer-s95] 2.4 document B, prune: output objects 4; errors: none; Graph requests: 19 (writes: 5); ARM requests: 0 (writes: 0)
[oer-s95] 2.4 document B, prune: row directoryRoleAssignments | Reports Reader -> 00000000-0000-0000-0000-000000000004 (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'
[oer-s95] 2.4 document B, prune: row directoryRoleAssignments | Reports Reader -> 00000000-0000-0000-0000-000000000004 (Active) | Removed | removed undeclared active assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'
[oer-s95] 2.4 document B, prune: row directoryRoleAssignments | Reports Reader -> oer-s95-grp2 (Eligible) | Created | created the eligible assignment (time-bound assignment (1 days) is absent)
[oer-s95] 2.4 document B, prune: row directoryRoleAssignments | Reports Reader -> oer-s95-grp2 (Active) | Created | created the active assignment (time-bound assignment (1 days) is absent)
[oer-s95] 2.4 document B, prune: warning -- Sync-OERStructureDirectoryRoleAssignment: removing undeclared eligible assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'.
[oer-s95] 2.4 document B, prune: warning -- Sync-OERStructureDirectoryRoleAssignment: removing undeclared active assignment of directory role 'Reports Reader' for principal '00000000-0000-0000-0000-000000000004'.
[oer-s95] 2.4 oer-s95-grp holds no 'Reports Reader' assignment: converged after 1 read(s), 1.1 s.
[oer-s95] 2.4 oer-s95-grp holds no 'Reports Reader' assignment: True (1 read(s), 1.1 s)
```

### 2.5. Document B with -Prune again: only Unchanged (G8), and the documents are removed

- [x] **2.5** The same document B with `-Prune` again: both rows `Unchanged`, no `Removed` or `Extra` row, no Graph write; the fences are removed and the two documents deleted.

```powershell
if ($PruneAllowed) {
    $null = Invoke-S95 -Label '2.5 document B again' -Call { Invoke-OERStructure -Path $DocB -Prune -Confirm:$false }
} else { Write-OerLiveStep '2.5 SKIPPED: class B (see 2.3).' }
# Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest
Remove-Item -LiteralPath $DocA, $DocB
Write-OerLiveStep "Fences removed: $(-not (Get-Command -Name Invoke-MgGraphRequest -CommandType Function -ErrorAction Ignore) -and -not (Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore)); documents deleted: $(-not (Test-Path -LiteralPath $DocA) -and -not (Test-Path -LiteralPath $DocB))"
Disconnect-OerLive
```

**Expect:** `errors: none; ... (writes: 0)`; two rows `Unchanged`; `Fences removed: True; documents
deleted: True`.
**Failure looks like:** a write, a `Removed` or an `Extra` row.

Result: 2026-10-07 09:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8), with one corrected line of the check itself. Document B with -Prune again: errors none; 12 Graph requests, 0 writes; both rows Unchanged; no Removed or Extra row; documents deleted True. "Fences removed: False" came from the check's own code: a scope-qualified function:global: path given to the removal cmdlet removes nothing (CLAUDE.md, Testing Conventions); the line is corrected to the unqualified form the step 4 checklist used. The fences lived only in that process, which ended with the section.

[oer-s95] 2.5 document B again: output objects 2; errors: none; Graph requests: 12 (writes: 0); ARM requests: 0 (writes: 0)
[oer-s95] 2.5 document B again: row directoryRoleAssignments | Reports Reader -> oer-s95-grp2 (Eligible) | Unchanged | assignment matches
[oer-s95] 2.5 document B again: row directoryRoleAssignments | Reports Reader -> oer-s95-grp2 (Active) | Unchanged | assignment matches
[oer-s95] Fences removed: False; documents deleted: True
```

## 3. BL-33: the Azure role cmdlets on a real Provisioned and Revoked answer

**3.0 to 3.4 run in ONE process**, in order, with the fences of section 1. Role Reader at
`oer-s95-rg` (named by the subscription and the resource group), principal `oer-s95-grp`, time-bound
one day. The Reader policy at a resource group requires a justification for an active assignment
(measured in this run: without one Azure Resource Manager refuses the request with
`RoleAssignmentRequestPolicyValidationFailed`), so every active call passes `-Justification`. The
read-backs filter the principal's schedules to `oer-s95-rg`: a principal filter cannot be combined
with `-AtScope`.

### 3.0. The fences

- [x] **3.0** The module resolves both transports to the fences.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Rg = @{ Subscription = $Cfg.SubscriptionId; ResourceGroup = 'oer-s95-rg' }
```

**Expect:** the identity lines `True`; the fences `True`.
**Failure looks like:** the fences `False` -- nothing was called.

Result: 2026-10-07 09:47 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:31, 09:36 and 09:42 UTC (three processes, below) as oer-live-cc, every identity line True, the fences resolving for the module (True).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
```

### 3.1. New-OEREligibleRoleAssignment: Provisioned, no error

- [x] **3.1** `New-OEREligibleRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one ARM write.

```powershell
$null = Invoke-S95 -Label '3.1 eligible create' -Call { New-OEREligibleRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... ARM requests: N (writes: 1: PUT
roleEligibilityScheduleRequests)`; `object Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned;
expiration AfterDuration`.
**Failure looks like:** `EligibilityRequestFailed` on a `Provisioned` object.

Result: 2026-10-07 09:47 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 1, 09:31 UTC. New-OEREligibleRoleAssignment, Reader at oer-s95-rg, oer-s95-grp, one day: one request object, Status Provisioned, expiration AfterDuration; errors none; 1 ARM write (PUT roleEligibilityScheduleRequests).

[oer-s95] 3.1 eligible create: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleEligibilityScheduleRequests)
[oer-s95] 3.1 eligible create: object Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned; expiration AfterDuration
```

### 3.2. New-OERActiveRoleAssignment, time-bound: Provisioned, no error

- [x] **3.2** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -DurationDays 1 -Justification ... -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one ARM write and no policy write.

```powershell
$null = Invoke-S95 -Label '3.2 active create' -Call { New-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -DurationDays 1 -Justification 'oer-s95 live verification' -Confirm:$false }
$ActiveAt = [datetime]::UtcNow
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleAssignmentScheduleRequests)`;
`Status Provisioned; expiration AfterDuration`; no policy warning (a time-bound grant needs no open).
**Failure looks like:** `AssignmentRequestFailed` on a `Provisioned` object.

Result: 2026-10-07 09:47 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS on the second run. Run 1, 09:31 UTC: Azure Resource Manager refused the request with RoleAssignmentRequestPolicyValidationFailed ('JustificationRule - Justification is required'): the Reader policy at a resource group requires a justification for an active assignment, and the checklist's block passed none. A thrown refusal, not a Failed answer; nothing was created. The block is corrected to pass -Justification (and 4.2 and 4.3 with it). Run 2, 09:36 UTC: one request object, Status Provisioned, expiration AfterDuration; errors none; 1 ARM write (PUT roleAssignmentScheduleRequests); no policy warning.

--- run 2 ---
[oer-s95] 3.2 active create: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleAssignmentScheduleRequests)
[oer-s95] 3.2 active create: object Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned; expiration AfterDuration

--- run 1 ---
[oer-s95] 3.2 active create: output objects 0; errors: RoleAssignmentRequestPolicyValidationFailed; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleAssignmentScheduleRequests)
[oer-s95] 3.2 active create: RoleAssignmentRequestPolicyValidationFailed; category OperationStopped -- RoleAssignmentRequestPolicyValidationFailed: The following policy rules failed: JustificationRule - Justification is required
```

### 3.3. Remove-OEREligibleRoleAssignment: Revoked, no error

- [x] **3.3** After the active assignment has run five minutes, `Remove-OEREligibleRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error.

```powershell
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $ActiveAt).TotalSeconds))
Write-OerLiveStep "3.3 waiting $Wait s, so a removal of the group's Reader assignments is not refused as too young."
Start-Sleep -Seconds $Wait
$null = Invoke-S95 -Label '3.3 eligible remove' -Call { Remove-OEREligibleRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleEligibilityScheduleRequests)`;
`Status Revoked`.
**Failure looks like:** `EligibilityRequestFailed` on a `Revoked` object.

Result: 2026-10-07 09:47 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 1, after waiting 305 s: Remove-OEREligibleRoleAssignment: one request object, Status Revoked; errors none; 1 ARM write; the removal warning (the subscription id redacted).

[oer-s95] 3.3 waiting 305 s, so a removal of the group's Reader assignments is not refused as too young.
[oer-s95] 3.3 eligible remove: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleEligibilityScheduleRequests)
[oer-s95] 3.3 eligible remove: object Omnicit.EntraRBAC.RoleScheduleRequest; Status Revoked; expiration 
[oer-s95] 3.3 eligible remove: warning -- Removing eligible role 'Reader' for principal 'oer-s95-grp' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg'.
```

### 3.4. Remove-OERActiveRoleAssignment: Revoked, no error, and nothing left

- [x] **3.4** `Remove-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error; afterwards neither kind is listed for the group at `oer-s95-rg`.

```powershell
$null = Invoke-S95 -Label '3.4 active remove' -Call { Remove-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Confirm:$false }
$W = Wait-OerLiveConverged -Activity '3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg' -Read {
    , @(@(Get-OEREligibleRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: True ($($W.Attempts) read(s), $($W.Seconds) s)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleAssignmentScheduleRequests)`;
`Status Revoked`; `holds no Reader schedule ...: True`.
**Failure looks like:** `AssignmentRequestFailed` on a `Revoked` object; a wait that does not
converge -- the teardown removes what is left.

Result: 2026-10-07 09:47 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS on the second run, with a slow read-back. Run 1, 09:36 UTC: RoleAssignmentDoesNotExist, since run 1's 3.2 had created nothing, and the read-back block stopped on a binding error of its own: a principal filter cannot be combined with -AtScope (corrected: the principal's schedules are filtered to oer-s95-rg). Run 2, 09:42 UTC, after the five-minute rule: Remove-OERActiveRoleAssignment: one request object, Status Revoked; errors none; 1 ARM write; the removal warning. The read-back did not converge within its 180 s budget (10 reads); a read-only read about four minutes after the removal lists nothing: no eligible or active row through the module, and 0 rows of roleAssignmentSchedules, roleAssignmentScheduleInstances and roleEligibilitySchedules at oer-s95-rg for the group. Azure Resource Manager kept listing the revoked schedule for more than 180 s (replication delay), as OerLive's F5 records for Graph.

--- run 2 ---
[oer-s95] 3.4 active remove: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleAssignmentScheduleRequests)
[oer-s95] 3.4 active remove: object Omnicit.EntraRBAC.RoleScheduleRequest; Status Revoked; expiration 
[oer-s95] 3.4 active remove: warning -- Removing active assignment of role 'Reader' for principal 'oer-s95-grp' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg'.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 1, 3.3 s, likely replication delay) -- reading again in 2 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 2, 7.4 s, likely replication delay) -- reading again in 4 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 3, 14.3 s, likely replication delay) -- reading again in 8 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 4, 24.7 s, likely replication delay) -- reading again in 16 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 5, 43.5 s, likely replication delay) -- reading again in 30 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 6, 76.7 s, likely replication delay) -- reading again in 30 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 7, 108.8 s, likely replication delay) -- reading again in 30 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 8, 141.7 s, likely replication delay) -- reading again in 30 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: not yet (read 9, 174.8 s, likely replication delay) -- reading again in 6 s.
[oer-s95] 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: NOT converged after 10 read(s), 184.6 s (budget 180 s).
Exception: OerLive: 3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg -- not converged within budget (180 s, 10 reads).

--- the read about four minutes later ---
[oer-s95] Eligible rows for oer-s95-grp: 0
[oer-s95] Active rows for oer-s95-grp: 0
[oer-s95] roleAssignmentSchedules: status 200; rows 0
[oer-s95] roleAssignmentScheduleInstances: status 200; rows 0
[oer-s95] roleEligibilitySchedules: status 200; rows 0

--- run 1 ---
[oer-s95] 3.4 active remove: output objects 0; errors: RoleAssignmentDoesNotExist; Graph requests: 1 (writes: 0); ARM requests: 2 (writes: 1: PUT roleAssignmentScheduleRequests)
[oer-s95] 3.4 active remove: warning -- Removing active assignment of role 'Reader' for principal 'oer-s95-grp' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg'.
[oer-s95] 3.4 active remove: RoleAssignmentDoesNotExist; category OperationStopped -- RoleAssignmentDoesNotExist: The Role assignment does not exist.
Get-OEREligibleRoleAssignment: HOME\AppData\Local\Temp\claude\C--Git-contoso-test-EntraRBAC\00000000-0000-0000-0000-000000000005\scratchpad\child-sec3.ps1:27
Line |
  27 |      , @(@(Get-OEREligibleRoleAssignment @Rg -Group 'oer-s95-grp' -AtS …
     |            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | A principal filter (-User, -Group or -ServicePrincipal) cannot be combined with -AtScope or -AsTarget.
```

## 4. BL-80: a permanent active Reader assignment at oer-s95-rg opens the policy only after consent

**4.0 to 4.3 run in ONE process**, in order, with the fences of section 1; 4.2 runs its `-WhatIf` in a
child process. The policy's baseline is recorded by the prerequisite (0.3) before the first write,
and the teardown puts it back.

### 4.0. The fences, and whether the policy forbids a permanent active assignment

- [x] **4.0** The module resolves both transports to the fences, and the Reader policy at `oer-s95-rg` forbids a permanent active assignment (otherwise 4.2 and 4.3 are class B).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Rg = @{ Subscription = $Cfg.SubscriptionId; ResourceGroup = 'oer-s95-rg' }
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s95-rg"
function Get-S95PermanentAllowed {
    $Guid = ([string](Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$([uri]::EscapeDataString("roleName eq 'Reader'"))").Body.value[0].name).ToLowerInvariant()
    $P = Get-OerLiveArmRolePolicy -Scope $RgScope -RoleDefinitionGuid $Guid
    -not [bool](@($P.Rules | Where-Object { [string]$_['id'] -eq 'Expiration_Admin_Assignment' })[0]['isExpirationRequired'])
}
$Before = Get-S95PermanentAllowed
$Base = Read-OerLiveBaseline -Name 'baseline-s95-rgreader'
Write-OerLiveStep "4.0 the Reader policy at oer-s95-rg allows a permanent active assignment: $Before; the baseline exists: $([bool]$Base)"
```

**Expect:** the identity lines `True`; the fences `True`; `allows a permanent active assignment:
False; the baseline exists: True`.
**Failure looks like:** `allows ...: True` -- the policy already allows it, so the cmdlet opens
nothing: 4.2 and 4.3 are `[~]` class B (the unit tests of `New-OERActiveRoleAssignment` prove the
path), and 4.3 still runs as a plain permanent grant; `the baseline exists: False` -- STOP, nothing
is written to the policy without a baseline.

Result: 2026-10-07 09:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:50 UTC as oer-live-cc (every identity line True), the fences resolving (True). The Reader policy at oer-s95-rg, read as the scope's own, does not allow a permanent active assignment (False), and its baseline exists (True), so 4.2 and 4.3 are live, not class B.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s95] The scope lists its role management policy: converged after 1 read(s), 3.9 s.
[oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] 4.0 the Reader policy at oer-s95-rg allows a permanent active assignment: False; the baseline exists: True
```

### 4.1. Nothing at oer-s95-rg for the group yet

- [x] **4.1** Before the plan, the group holds no active Reader schedule at `oer-s95-rg`.

```powershell
$Pre = @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
Write-OerLiveStep "4.1 active Reader schedules of oer-s95-grp at oer-s95-rg: $($Pre.Count)"
```

**Expect:** `0` (section 3 removed its own).
**Failure looks like:** above 0 -- wait for 3.4's removal to converge, then read again.

Result: 2026-10-07 09:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-s95-grp holds 0 active Reader schedules at oer-s95-rg before the plan (section 3's own removed).

[oer-s95] 4.1 active Reader schedules of oer-s95-grp at oer-s95-rg: 0
```

### 4.2. -WhatIf in a child process: the warning, two planned writes, nothing written

- [x] **4.2** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Permanent -Justification ... -WhatIf`, in a child process, warns that the assignment requires opening the policy, plans the policy change and the assignment, and writes nothing: the policy still forbids a permanent active assignment and the group holds none.

```powershell
$Child = Join-Path $Raw 'child-s95-4.2.ps1'
[System.IO.File]::WriteAllText($Child, @"
`$ErrorActionPreference = 'Continue'
Import-Module (Join-Path '$VaultDir' 'OerLive\OerLive.psm1') -Force
`$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory '$VaultDir'
`$Cfg.Repo = '$($Cfg.Repo)'
Connect-OerLive -Arm
`$global:ArmWrites = 0
`$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
`$WebFence = "`$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute(`$WebMeta))``nparam(`$([System.Management.Automation.ProxyCommand]::GetParamBlock(`$WebMeta)))``nend { if ([string]```$Method -and [string]```$Method -ne 'Get') { ```$global:ArmWrites++ }; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create(`$WebFence))
`$All = @(New-OERActiveRoleAssignment -Role 'Reader' -Subscription '$($Cfg.SubscriptionId)' -ResourceGroup 'oer-s95-rg' -Group 'oer-s95-grp' -Permanent -Justification 'oer-s95 live verification' -WhatIf 2>&1 3>&1)
foreach (`$R in `$All) {
    if (`$R -is [System.Management.Automation.WarningRecord]) { "WARNING|`$(`$R.Message)" }
    elseif (`$R -is [System.Management.Automation.ErrorRecord]) { "ERROR|`$(([string]`$R.FullyQualifiedErrorId -split ',')[0])" }
    else { "OBJECT|`$(`$R.PSObject.TypeNames[0])" }
}
"ARMWRITES|`$global:ArmWrites"
Remove-Item -Path function:global:Invoke-WebRequest
Disconnect-OerLive
"@, [System.Text.UTF8Encoding]::new($false))
$ChildOut = @(& pwsh -NoProfile -File $Child 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $ChildOut) { Write-OerLiveStep "4.2 child: $(ConvertTo-OerLiveRedacted -Text $Line)" }
Remove-Item -LiteralPath $Child
$WarnAt = [array]::FindIndex([string[]]$ChildOut, [Predicate[string]] { param($L) $L -like 'WARNING|*requires opening the role management policy*' })
$WhatIf = @($ChildOut | Where-Object { $_ -match '^What if: ' })
$After = Get-S95PermanentAllowed
$Held = @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
Write-OerLiveStep "4.2 the policy warning under -WhatIf: $($WarnAt -ge 0); What if lines: $($WhatIf.Count); ARM writes: $(@($ChildOut | Where-Object { $_ -like 'ARMWRITES|*' }) -replace '^ARMWRITES\|', ''); objects: $(@($ChildOut | Where-Object { $_ -like 'OBJECT|*' }).Count); errors: $(@($ChildOut | Where-Object { $_ -like 'ERROR|*' }).Count); the policy now allows a permanent active assignment: $After; active Reader schedules of oer-s95-grp: $($Held.Count)"
```

**Expect:** the child's identity lines `True`; `the policy warning under -WhatIf: True`, from the `WARNING|This assignment requires opening the role
management policy for role 'Reader' at scope ... to allow PERMANENT active assignments ...` line;
two `What if:` lines (the policy change `Set-OERRoleManagementPolicy` plans, and `Create active Azure
role assignment`), redacted; `ARM writes: 0`; `objects: 0`; `errors: 0`; `the policy now allows a
permanent active assignment: False`; `active Reader schedules of oer-s95-grp: 0`.
**Failure looks like:** `ARM writes` above 0, or the policy allowing it after the plan -- the old
defect (the open before the gate); one `What if:` line -- the plan no longer shows the policy change.

Result: 2026-10-07 09:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. New-OERActiveRoleAssignment -Permanent -WhatIf in a child process (its identity lines True): the policy warning under -WhatIf (True, 'This assignment requires opening the role management policy ... to allow PERMANENT active assignments'); two What if lines, redacted, in this order: the gate's own 'Create active Azure role assignment', then the policy change Set-OERRoleManagementPolicy plans ('Update rules: Expiration_Admin_Assignment') -- the gate is decided before the open, which the old code did the other way round; ARM writes 0; objects 0; errors 0; afterwards the policy still does not allow a permanent active assignment (False) and the group holds no active Reader schedule (0).

[oer-s95] 4.2 child: [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] 4.2 child: [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] 4.2 child: [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] 4.2 child: [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] 4.2 child: What if: Performing the operation "Create active Azure role assignment" on target "active role 'Reader' for Group 'oer-s95-grp' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg'".
[oer-s95] 4.2 child: What if: Performing the operation "Update rules: Expiration_Admin_Assignment" on target "role management policy '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000003'".
[oer-s95] 4.2 child: WARNING|This assignment requires opening the role management policy for role 'Reader' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg' to allow PERMANENT active assignments, which affects ALL active assignments for this role at this scope.
[oer-s95] 4.2 child: ARMWRITES|0
[oer-s95] The scope lists its role management policy: converged after 1 read(s), 3.2 s.
[oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] 4.2 the policy warning under -WhatIf: True; What if lines: 2; ARM writes: 0; objects: 0; errors: 0; the policy now allows a permanent active assignment: False; active Reader schedules of oer-s95-grp: 0
```

### 4.3. Confirmed: the policy is opened, then the assignment is Provisioned

- [x] **4.3** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Permanent -Justification ... -Confirm:$false` warns, opens the policy, then creates the assignment: one request object `Provisioned` with no expiration, no error, the ARM writes in the order policy then request; afterwards the policy allows a permanent active assignment.

```powershell
$null = Invoke-S95 -Label '4.3 permanent active create' -Call { New-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Permanent -Justification 'oer-s95 live verification' -Confirm:$false }
$After = Get-S95PermanentAllowed
Write-OerLiveStep "4.3 the policy now allows a permanent active assignment: $After (the teardown puts the baseline back)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... ARM requests: N (writes: 2: PATCH
roleManagementPolicies, PUT roleAssignmentScheduleRequests)`; `object
Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned; expiration NoExpiration`; the warning;
`allows a permanent active assignment: True`.
**Failure looks like:** the PUT before the PATCH -- the open and the grant out of order; an error
after a `Provisioned` object; `PolicyOpenedButGrantFailed` -- read it, and check that the policy was
rolled back.

Result: 2026-10-07 09:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. New-OERActiveRoleAssignment -Permanent -Justification -Confirm:$false: the warning; ARM writes 2 in the order PATCH roleManagementPolicies, then PUT roleAssignmentScheduleRequests (the open, then the grant); one request object, Status Provisioned, expiration NoExpiration; errors none; afterwards the policy allows a permanent active assignment (True). The teardown removes the assignment and puts the policy back to its baseline.

[oer-s95] 4.3 permanent active create: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 5 (writes: 2: PATCH roleManagementPolicies, PUT roleAssignmentScheduleRequests)
[oer-s95] 4.3 permanent active create: object Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned; expiration NoExpiration
[oer-s95] 4.3 permanent active create: warning -- This assignment requires opening the role management policy for role 'Reader' at scope '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/oer-s95-rg' to allow PERMANENT active assignments, which affects ALL active assignments for this role at this scope.
[oer-s95] The scope lists its role management policy: converged after 1 read(s), 2.6 s.
[oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] 4.3 the policy now allows a permanent active assignment: True (the teardown puts the baseline back)
```

## 5. BL-50: a connected-organization scope with no target is refused, and nothing is sent

**5.0 to 5.2 run in ONE process**, in order, with the fences of section 1.

### 5.0. The fences and the policy

- [x] **5.0** The module resolves both transports to the fences, and `oer-s95-ap` has one assignment policy, `oer-s95-pol`, administrator-only.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Pols = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s95-ap' -ErrorAction Stop)
$Pol = $Pols | Where-Object { $_.DisplayName -ceq 'oer-s95-pol' } | Select-Object -First 1
$PolId = [string]$Pol.Id
$Em = 'v1.0/identityGovernance/entitlementManagement'
function Get-S95PolicyState {
    $R = Invoke-OerLiveGraph -Uri "$Em/assignmentPolicies/$PolId"
    Assert-OerLiveOk -Response $R -Activity 'Reading oer-s95-pol' | Out-Null
    [PSCustomObject]@{ Scope = [string]$R.Body['allowedTargetScope']; Targets = @($R.Body['specificAllowedTargets']).Count; Modified = [string]$R.Body['modifiedDateTime']; Description = [string]$R.Body['description'] }
}
$Start = Get-S95PolicyState
Write-OerLiveStep "5.0 policies of oer-s95-ap: $($Pols.Count); oer-s95-pol found: $([bool]$PolId); allowedTargetScope $($Start.Scope); targets $($Start.Targets)"
```

**Expect:** the identity lines `True`; the fences `True`; `policies of oer-s95-ap: 1; oer-s95-pol
found: True; allowedTargetScope notSpecified; targets 0`.
**Failure looks like:** no policy -- run 0.3 again.

Result: 2026-10-07 09:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 09:52 UTC as oer-live-cc (every identity line True), the fences resolving (True). oer-s95-ap has one assignment policy, oer-s95-pol, found; allowedTargetScope notSpecified; 0 targets.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s95] 5.0 policies of oer-s95-ap: 1; oer-s95-pol found: True; allowedTargetScope notSpecified; targets 0
```

### 5.1. -RequestorScope SpecificConnectedOrganizationUsers with no target: InvalidPolicyInput, no write

- [x] **5.1** `Set-OERAccessPackageAssignmentPolicy -Id` (the policy) `-DisplayName oer-s95-pol -RequestorScope` (a `SpecificConnectedOrganizationUsers` scope from `New-OERAccessPackageRequestorScope`) `-Confirm:$false` writes `InvalidPolicyInput`, emits nothing, sends one Graph read and no write, and leaves the policy as it was.

```powershell
$Scope = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers -ErrorAction Stop
$null = Invoke-S95 -Label '5.1 refused' -Call { Set-OERAccessPackageAssignmentPolicy -Id $PolId -DisplayName 'oer-s95-pol' -RequestorScope $Scope -Confirm:$false }
$Now = Get-S95PolicyState
Write-OerLiveStep "5.1 the policy is unchanged: $($Now.Scope -ceq $Start.Scope -and $Now.Targets -eq $Start.Targets -and $Now.Modified -ceq $Start.Modified)"
```

**Expect:** `output objects 0; errors: InvalidPolicyInput; Graph requests: 1 (writes: 0); ARM
requests: 0`; the message naming the connected organizations and `-RequestorScope`; `the policy is
unchanged: True`.
**Failure looks like:** `writes: 1` -- the PUT went out (the old defect); no error.

Result: 2026-10-07 09:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Set-OERAccessPackageAssignmentPolicy with a SpecificConnectedOrganizationUsers scope from New-OERAccessPackageRequestorScope: output objects 0; InvalidPolicyInput, category InvalidArgument, the message naming the scope, the builder that cannot name a connected organization and the update it would have made (redacted, cut at 300 characters); 1 Graph request (the read of the policy) and 0 writes; no ARM request; the policy is unchanged (scope, targets and modifiedDateTime: True).

[oer-s95] 5.1 refused: output objects 0; errors: InvalidPolicyInput; Graph requests: 1 (writes: 0); ARM requests: 0 (writes: 0)
[oer-s95] 5.1 refused: InvalidPolicyInput; category InvalidArgument -- -RequestorScope names allowedTargetScope SpecificConnectedOrganizationUsers but no connected organization -- New-OERAccessPackageRequestorScope cannot name one -- so the full update of assignment policy '00000000-0000-0000-0000-000000000006' would replace every connected organization the live policy ...
[oer-s95] 5.1 the policy is unchanged: True
```

### 5.2. The control: the same call without -RequestorScope sends the update

- [x] **5.2** `Set-OERAccessPackageAssignmentPolicy -Id` (the policy) `-DisplayName oer-s95-pol -Description 'oer-s95 control' -Confirm:$false` sends one PUT and emits the updated policy; the scope is carried forward unchanged.

```powershell
$null = Invoke-S95 -Label '5.2 control' -Call { Set-OERAccessPackageAssignmentPolicy -Id $PolId -DisplayName 'oer-s95-pol' -Description 'oer-s95 control' -Confirm:$false }
$Now = Get-S95PolicyState
Write-OerLiveStep "5.2 description changed: $($Now.Description -ceq 'oer-s95 control'); allowedTargetScope $($Now.Scope); targets $($Now.Targets)"
# Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; Graph requests: 2 (writes: 1)`; `object
Omnicit.EntraRBAC.AssignmentPolicy`; `description changed: True; allowedTargetScope notSpecified;
targets 0`.
**Failure looks like:** no PUT -- the refusal fires on a call without `-RequestorScope`.

Result: 2026-10-07 09:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The control, the same call with -Description and without -RequestorScope: one AssignmentPolicy object; errors none; 2 Graph requests, 1 write (the PUT); the description changed (True); allowedTargetScope still notSpecified, 0 targets. The refusal does not fire on a call without -RequestorScope.

[oer-s95] 5.2 control: output objects 1; errors: none; Graph requests: 2 (writes: 1); ARM requests: 0 (writes: 0)
[oer-s95] 5.2 control: object Omnicit.EntraRBAC.AssignmentPolicy
[oer-s95] 5.2 description changed: True; allowedTargetScope notSpecified; targets 0
```

## Teardown

### T.1. The Azure schedules, the objects and the Reader policy are put back, nothing carries the prefix, and the main clone is untouched

- [x] **T.1** `Initialize-OerS95Prereq.ps1 -Teardown -Unattended` removes the Azure schedules of the prefixed groups at `oer-s95-rg` (4.3's permanent active assignment), the directory role assignments of `oer-s95-grp2` (2.4), the policy, the package, the catalog and both groups, puts the Reader policy at `oer-s95-rg` back to its baseline and deletes the resource group; the sweep finds nothing with the prefix; the counts equal the baseline; no session is left; the main clone is on `main` at the HEAD S.1 recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Teardown exit code: $Code"
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "A Graph SDK session is left: $([bool](Get-MgContext)); the module holds a session: $([bool]($Module -and (& $Module { $script:_OERAuthState })))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the teardown's identity lines `True`; `Teardown A: oer-s95-grp at oer-s95-rg: eligible 0,
active (Assigned) 1` and its removal (after the five-minute rule when 4.3 was less than five minutes
ago), `oer-s95-grp2 ... eligible 0, active (Assigned) 0`; the library's step 1 removing
`oer-s95-grp2`'s two directory role assignments, step 3 the policy, the package and the catalog, step
5 both groups; `Teardown C: Reader policy at oer-s95-rg at its baseline: True (rules differing
before: N...)` and `deleted oer-s95-rg`; `Resource group oer-s95-rg exists after the teardown:
False`; the three counts equal to the baseline (`True`); exit code 0; no session left; the main clone
on `main` at the HEAD S.1 recorded.
**Failure looks like:** exit code 1 with a `STOP` line -- the policy could not be put back: the
resource group is NOT deleted, and the step stops (G11.5); exit code 3 -- residue in
`raw\residue.json`, which the next prereq run retries; report each row. An object deleted with 204 can
still show in the sweep for a minute or two: read back with T.2 before judging.

Result: 2026-10-07 09:58 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, with one slow listing recorded as residue by the script and proven gone in T.2. Run 2026-10-07 09:53 UTC: identity check passed; no residue from earlier runs. Teardown A: oer-s95-grp held 1 active (Assigned) Azure schedule at oer-s95-rg (4.3's permanent Reader assignment); after waiting 218 s (the five-minute rule) it was removed (200, Revoked); Azure Resource Manager kept listing it beyond the 180 s budget, so the script counted it as residue and carried on (the same replication delay as 3.4); oer-s95-grp2 held none. The library's teardown: step 1 removed oer-s95-grp2's eligible and active Reports Reader assignments (201, 201) and the listing converged after 2 reads; step 2: the PIM for Groups assignment schedules of both groups are unreadable for oer-live-cc (PermissionScopeNotGranted), counted as such; step 3 deleted the policy, the package and the catalog (204); step 5 deleted both groups (204); removed 7, residue 0, unreadable 2. Teardown C: the Reader policy at oer-s95-rg had 1 rule differing from its baseline (Expiration_Admin_Assignment, opened by 4.3); it was put back and read back at the baseline after 1 read, and only then the resource group was deleted. The sweep finds nothing with the prefix; oer-s95-rg exists after the teardown: False; groups 98, catalogs 5 and access packages 6, each equal to the baseline (True); exit code 3 (the one slow listing); no Graph SDK session and no module session left; the main clone on main at 6817b33, the HEAD S.1 recorded, never switched.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [oer-s95] Transcript (redacted): raw\s95\teardown-20261007-094915Z.log; OerLive 1.0.3.
[oer-s95] [oer-s95] Mode: REMOVE. Prefix 'oer-s95-'. Objects (fixed): oer-s95-grp, oer-s95-grp2 (role-assignable, no member); oer-s95-rg (tagged, empty, its Reader policy baselined); oer-s95-cat, oer-s95-ap (hidden), oer-s95-pol (administrator-only). OerLive 1.0.3.
[oer-s95] [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] [oer-s95] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s95] [oer-s95] Residue: raw\residue.json holds no rows.
[oer-s95] [oer-s95] Teardown A: oer-s95-grp at oer-s95-rg: eligible 0, active (Assigned) 1.
[oer-s95] [oer-s95] oer-s95-grp: active Reader-or-other Azure role schedule at oer-s95-rg: waiting 218 s (an active assignment is removed once it has run five minutes).
[oer-s95] [oer-s95] Removed: oer-s95-grp: active Reader-or-other Azure role schedule at oer-s95-rg (200 Revoked).
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 1, 2.7 s, likely replication delay) -- reading again in 2 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 2, 7.7 s, likely replication delay) -- reading again in 4 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 3, 13.8 s, likely replication delay) -- reading again in 8 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 4, 24.1 s, likely replication delay) -- reading again in 16 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 5, 44.8 s, likely replication delay) -- reading again in 30 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 6, 79.7 s, likely replication delay) -- reading again in 30 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 7, 112.6 s, likely replication delay) -- reading again in 30 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 8, 145 s, likely replication delay) -- reading again in 30 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: not yet (read 9, 177.4 s, likely replication delay) -- reading again in 3 s.
[oer-s95] [oer-s95] oer-s95-grp: no Azure role schedule listed at oer-s95-rg: NOT converged after 10 read(s), 182.8 s (budget 180 s).
[oer-s95] [oer-s95] Teardown A: RESIDUE: oer-s95-grp: its Azure role schedules at oer-s95-rg are still listed after the budget; the teardown carries on.
[oer-s95] [oer-s95] Teardown A: oer-s95-grp2 at oer-s95-rg: eligible 0, active (Assigned) 0.
[oer-s95] [oer-s95] Teardown of 'oer-s95-': users 0, groups 2, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s95] [oer-s95] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s95] [oer-s95] Removed: oer-s95-grp2: eligible 'Reports Reader' assignment at directory scope '/' (201).
[oer-s95] [oer-s95] Removed: oer-s95-grp2: active 'Reports Reader' assignment at directory scope '/' (201).
[oer-s95] [oer-s95] oer-s95-grp2: no direct directory role schedule listed: not yet (read 1, 1 s, likely replication delay) -- reading again in 2 s.
[oer-s95] [oer-s95] oer-s95-grp2: no direct directory role schedule listed: converged after 2 read(s), 4.5 s.
[oer-s95] [oer-s95] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s95] [oer-s95] Unreadable for this identity: PIM for Groups assignment schedules of oer-s95-grp (PermissionScopeNotGranted). oer-live-cc cannot create such assignments; deleting the group removes any that exist.
[oer-s95] [oer-s95] Unreadable for this identity: PIM for Groups assignment schedules of oer-s95-grp2 (PermissionScopeNotGranted). oer-live-cc cannot create such assignments; deleting the group removes any that exist.
[oer-s95] [oer-s95] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s95] [oer-s95] Deleted: oer-s95-ap: assignment policy 'oer-s95-pol' (204).
[oer-s95] [oer-s95] Deleted: access package oer-s95-ap (204, 1 attempt(s)).
[oer-s95] [oer-s95] Deleted: catalog oer-s95-cat (204, 1 attempt(s)).
[oer-s95] [oer-s95] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s95] [oer-s95] Teardown 5/6: the prefixed groups.
[oer-s95] [oer-s95] Deleted: group oer-s95-grp (204).
[oer-s95] [oer-s95] Deleted: group oer-s95-grp2 (204).
[oer-s95] [oer-s95] Teardown 6/6: the prefixed users.
[oer-s95] [oer-s95] Teardown of 'oer-s95-': removed 7, residue 0, unreadable 2.
[oer-s95] [oer-s95] The scope lists its role management policy: converged after 1 read(s), 3.3 s.
[oer-s95] [oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] [oer-s95] Azure role policy at the scope: rules differing from the baseline: 1 (Expiration_Admin_Assignment)
[oer-s95] [oer-s95] The scope lists its role management policy: converged after 1 read(s), 3.5 s.
[oer-s95] [oer-s95] The policy listed at the scope is the scope's own: True
[oer-s95] [oer-s95] Azure role policy back at its baseline: converged after 1 read(s), 4.3 s.
[oer-s95] [oer-s95] Teardown C: Reader policy at oer-s95-rg at its baseline: True (rules differing before: 1: Expiration_Admin_Assignment).
[oer-s95] [oer-s95] oer-s95-rg is gone: not yet (read 1, 0.3 s, likely replication delay) -- reading again in 2 s.
[oer-s95] [oer-s95] oer-s95-rg is gone: converged after 2 read(s), 3.1 s.
[oer-s95] [oer-s95] Teardown C: deleted oer-s95-rg.
[oer-s95] [oer-s95] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s95-' is left.
[oer-s95] [oer-s95] Resource group oer-s95-rg exists after the teardown: False
[oer-s95] [oer-s95] Counts: groups now 98, at the baseline 98; equal: True
[oer-s95] [oer-s95] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s95] [oer-s95] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s95] [oer-s95] Done, with 1 residue item(s): see the RESIDUE lines and raw\residue.json.
[oer-s95] [oer-s95] Done.
[oer-s95] Teardown exit code: 3
[oer-s95] A Graph SDK session is left: False; the module holds a session: False
[oer-s95] Main clone: branch main; HEAD 6817b33
```

### T.2. Read back, a few minutes later

- [x] **T.2** `Initialize-OerS95Prereq.ps1 -ReadBack` finds no object with the prefix, no resource group `oer-s95-rg`, the counts equal to the baseline and no residue row.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
```

**Expect:** `Sweep: no user, group, ... starting with 'oer-s95-' is left.`; `Read-back: resource group
oer-s95-rg exists: False`; the three counts equal (`True`); `prefixed objects left: 0; unread
collections: 0; residue rows: 0`.
**Failure looks like:** an object left -- run T.1 again; a residue row -- report it.

Result: 2026-10-07 09:58 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 10:01 UTC: identity check passed; the sweep finds nothing with the prefix; oer-s95-rg exists: False; the three counts equal to the baseline (True); prefixed objects left 0, unread collections 0, residue rows 0. An extra read of the test subscription's Azure PIM schedules lists 0 rows whose scope is oer-s95-rg: roleAssignmentSchedules (12 rows in all), roleEligibilitySchedules (3) and roleAssignmentScheduleInstances (12). The schedule T.1 counted as residue is gone. The redaction map is cleared and raw\s95\ deleted after this write-up.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s95] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s95] [oer-s95] Transcript (redacted): raw\s95\readback-20261007-095738Z.log; OerLive 1.0.3.
[oer-s95] [oer-s95] Mode: READ BACK. Prefix 'oer-s95-'. Objects (fixed): oer-s95-grp, oer-s95-grp2 (role-assignable, no member); oer-s95-rg (tagged, empty, its Reader policy baselined); oer-s95-cat, oer-s95-ap (hidden), oer-s95-pol (administrator-only). OerLive 1.0.3.
[oer-s95] [oer-s95] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg5\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s95] [oer-s95] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s95] [oer-s95] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s95-' is left.
[oer-s95] [oer-s95] Read-back: resource group oer-s95-rg exists: False
[oer-s95] [oer-s95] Counts: groups now 98, at the baseline 98; equal: True
[oer-s95] [oer-s95] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s95] [oer-s95] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s95] [oer-s95] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s95] [oer-s95] Done.

--- extra read ---
[oer-s95] T.2 extra read: roleAssignmentSchedules in the test subscription: status 200; rows 12; rows at oer-s95-rg: 0
[oer-s95] T.2 extra read: roleEligibilitySchedules in the test subscription: status 200; rows 3; rows at oer-s95-rg: 0
[oer-s95] T.2 extra read: roleAssignmentScheduleInstances in the test subscription: status 200; rows 12; rows at oer-s95-rg: 0
```
