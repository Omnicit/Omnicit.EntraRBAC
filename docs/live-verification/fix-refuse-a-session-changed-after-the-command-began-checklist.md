# Live verification checklist -- a command acts under the sign-in it began with (fix/refuse-a-session-changed-after-the-command-began)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates two plain security groups,
`oer-s92-grp` and `oer-s92-member`, and nothing else. Section 1 applies a small document that changes
`oer-s92-grp`'s description and adds `oer-s92-member` as its member, then applies it twice more,
which must change nothing. Every other check reads only, or runs with `-WhatIf`. The teardown deletes
both groups. No policy, role or permission is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph), and its no-permission twin `oer-live-cc-noperm`, which section 2 signs in as INSIDE a
pipeline to switch the identity. Every sign-in is app-only; nothing here signs in as a person. A 401 or
403 as `oer-live-cc` is a stop.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first. The second sign-in of a section 2 check is `Connect-OER` in a
`ForEach-Object -Begin` block, on purpose: that `begin` runs after the upstream command's `begin` and
before its `process` block, exactly where a downstream OER cmdlet's own sign-in runs. After a check
that signs in as `oer-live-cc-noperm`, the next check signs in as `oer-live-cc` again with
`Connect-OerLive -Arm` before it reads or writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s92/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, account or certificate
thumbprint is ever printed**, and **no error record is ever rendered**: every block prints the error
id, the target of a `SignInSuperseded` or `SignInRefused` (a command name) and the message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. One owner of the session a command began with** ("take a snapshot of the sign-in a command
  began with"). The new private `Checkpoint-OERSignIn` takes a snapshot of the identity the module's
  state carries -- tenant, method, client and cloud, built by `Get-OERSignInIdentity`, never a token --
  or of no session at all, and later tells whether that identity changed.
- **B. BL-76: `Invoke-OERStructure` without `-TenantId`** ("refuse a document when the session changed
  after Invoke-OERStructure began"). It signs in in its `process` block, so a downstream command's
  `begin` block, which runs first, could switch the session it inherits -- its document, `-Prune`
  deletions included, then went to that session's tenant with no error. It now takes the snapshot in
  a new `begin` block and, before it signs in without `-TenantId`, refuses the document with the
  existing `SignInSuperseded` when the identity changed, sending nothing. The snapshot is taken again
  after each sign-in, so several piped documents work. With `-TenantId` nothing changes.
- **C. BL-81: the three builders that look up a name** ("refuse a name lookup when the session changed
  after the builder began") -- `New-OERAccessPackageApprovalStage`, `New-OERAccessPackageRequestorScope`
  and `New-OERAccessReviewStage` -- sign in only when they resolve a name, in `process`. They do the
  same before their lookup.
- **D. BL-74: a sign-in under a refused command** ("refuse a sign-in under a command whose sign-in
  was refused"). `Initialize-OERAuth` refuses with `SignInRefused`, before it latches its caller and
  before any token call or `Connect-MgGraph`, when a command outside its caller is latched.
- **E.** The `SignInSuperseded` message now reads "after X began" instead of "after X signed in": a
  command refused under B or C has not signed in yet.

A live tenant is needed for what the unit tests stub: a real `Connect-OER` switching the module's
identity inside a running pipeline, and the module's real Graph requests counted by a fence -- both
for the refusal (section 2) and for the regression that the same commands, alone or with an
unchanged identity, still apply and resolve (sections 1 and 2).

## What this file does not check, and why

- **BL-74 (class B, G9).** Reaching it needs a command whose own sign-in is refused and that then
  calls a cmdlet whose sign-in would request a token -- a cached token within five minutes of expiry,
  or a sign-in to another tenant, which on this app-only identity opens an interactive prompt.
  Proved offline instead: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe
  `Initialize-OERAuth sign-in latch (A19)` (`Get-AzToken` and `Connect-MgGraph` `-Times 0 -Exactly`),
  `tests/Unit/Private/Get-OERSignInRefusal.Tests.ps1` (`-OutsideCaller`), and in runspaces with no
  `try`, `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` H3 (a nested sign-in near expiry under
  a refused `Invoke-OERStructure` requests no token) and H4 (the command's own second document still
  signs in).
- **Two tenants.** Only the test tenant is reachable, so section 2 switches the IDENTITY instead; the
  four terms are compared together, so one tenant with two identities exercises the same comparison
  as two tenants. The two-tenant pipelines are class B: `Invoke-OERGraphRequest.Tests.ps1`, Describe
  `A command whose sign-in a later command in the pipeline replaced sends nothing (A20, F-E)`, P10 to
  P17.
- **Several documents from no session, and a downstream `Disconnect-OER`.** A first sign-in from no
  session without `-TenantId` is interactive, which no check may do (G9). Class B: P13, and
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe `Invoke-OERStructure acts only under the
  session it began with (BL-76)`.
- **A command called inside a script block or a function in a pipeline** (for example
  `Get-ChildItem *.json | ForEach-Object { Invoke-OERStructure -Path $_ } | ...`) begins only when
  that block runs, after every other command's `begin` block, so its snapshot already holds a session
  a later command switched to. That limit is older than this branch, not made worse by it, and stays
  open (`docs/development/rationale.md`, anchor auth-state, "Known limits"); no check here exercises
  it, since there is nothing new to verify.- **Convergence (G8)** applies to section 1, the one write: 1.2 and 1.3 run the same document again.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and `oer-live-cc-noperm`.
  This file adds no permission to either.
- The **prerequisite script** `Initialize-OerS92Prereq.ps1` beside OerLive (outside the repository).
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
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s92'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Checkpoint-OERSignIn' -Quiet)
$B = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'if (-not $TenantId -and (Checkpoint-OERSignIn -ChangedSince $SignInSnapshot))').Count
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$OuterRefused = Get-OERSignInRefusal -OutsideCaller' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; the check before a sign-in, B and C (four call sites): $B; D: $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; the check before a sign-in, B and C (four call sites): 4; D: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:06 UTC. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 6817b33, never switched; the worktree on this branch at e1e85d2 (docs-only commits after the a4f8d95 build) with 0 tracked changes; the build carries A (Checkpoint-OERSignIn), the check before a sign-in at four call sites (B and C) and D (the BL-74 check).

[oer-s92] The module loads from a worktree that is not the main clone: True
[oer-s92] Main clone: branch main; HEAD 6817b33
[oer-s92] Worktree: branch fix/refuse-a-session-changed-after-the-command-began; HEAD e1e85d2 docs: count only tenant targets in the live checklist's prerequisite plan check; tracked changes: 0
[oer-s92] The worktree's build carries A: True; the check before a sign-in, B and C (four call sites): 4; D: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s92'
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

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:05 UTC: every identity line True for the module session as oer-live-cc (app-only certificate session, app name, test tenant, service principal named oer-live-cc and the token's signed-in object, organization, verified domain, ARM token from the certificate, test subscription Enabled); identity check passed; the module is the worktree's build (1.1.3).

[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] The module is the worktree's build: True
```

### 0.2. Identity check as oer-live-cc-noperm

- [x] **0.2** The no-permission identity signs in to a Graph SDK session of its own.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s92'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Graph -NoPerm
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, `identity check passed: True`.
**Failure looks like:** any `False` -- STOP; section 2 needs this identity.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:05 UTC: oer-live-cc-noperm signs in to a Graph SDK session of its own: app-only with its app id, app name oer-live-cc-noperm, the test tenant, all True; identity check passed.

[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Microsoft Graph sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Microsoft Graph sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc-noperm: identity check passed: True
```

### 0.3. The prerequisite plan names only oer-s92- objects

- [x] **0.3** `Initialize-OerS92Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every `What if:` line names an object with the prefix `oer-s92-`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS92Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baseline) go to raw\s92\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s92\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s92\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s92\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s92-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s92-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own two local files under `raw\s92\` (the transcript and, on a first run, the baseline) and
two tenant targets (the two groups, or none if they exist already), every tenant target starting
with `oer-s92-` (`True`).
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:06 UTC (the second run: the first run, at 16:05 UTC, counted the script's own two local files under raw\s92\ as targets and printed False; check 0.3 was corrected to count tenant targets apart, commit "count only tenant targets in the live checklist's prerequisite plan check"). Identity check passed; no residue; the sweep finds nothing with the prefix; no baseline yet. The plan: the transcript and the baseline under raw\s92\, and two tenant targets, oer-s92-grp and oer-s92-member, both with the prefix (True). WhatIf: nothing was created or written. Read and confirmed by the controller before 0.4.

[oer-s92] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s92] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s92] What if: Performing the operation "Start the redacted transcript" on target "raw\s92\prereq-20261006-160648Z.log".
[oer-s92] [oer-s92] Mode: CREATE or complete. Prefix 'oer-s92-'. Objects (fixed): oer-s92-grp (prereq description, no member); oer-s92-member (no member). OerLive 1.0.3.
[oer-s92] [oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s92] [oer-s92] Residue: raw\residue.json holds no rows.
[oer-s92] [oer-s92] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s92-' is left.
[oer-s92] [oer-s92] Found: oer-s92-grp exists: False; oer-s92-member exists: False.
[oer-s92] [oer-s92] No baseline yet: it is written now, before the first write to the tenant (groups 98).
[oer-s92] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s92\baseline-s92.json".
[oer-s92] What if: Performing the operation "Create a plain security group with the prereq description and no member (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s92-grp".
[oer-s92] What if: Performing the operation "Create a plain security group with no member (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s92-member".
[oer-s92] [oer-s92] Summary: oer-s92-grp absent; oer-s92-member absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s92] [oer-s92] WhatIf: nothing was created, removed or written.
[oer-s92] [oer-s92] Done.
[oer-s92] Planned writes: 4; local files under raw\s92\: 2; tenant targets: 2; every tenant target starts with oer-s92-: True
```

### 0.4. The prerequisite objects

- [x] **0.4** `Initialize-OerS92Prereq.ps1 -Unattended` writes the baseline when there is none, and creates `oer-s92-grp` (prereq description, no member) and `oer-s92-member`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS92Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the identity lines `True`; the baseline written (groups N) or found; `Created group
oer-s92-grp` and `Created group oer-s92-member` (or `exists`); `Summary: oer-s92-grp present;
oer-s92-member present`; exit code 0.
**Failure looks like:** exit code 1 -- read the `Refusing to run` or `Stopped` line; a 401/403 -- STOP.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:06 UTC: identity check passed; the baseline written (groups 98) and read back; oer-s92-grp created (201, resolves by name after 6.5 s) and oer-s92-member created (201, after 14.3 s); summary both present; exit code 0. (Before section 1 was run again, the two groups were removed with the script's -Teardown and created again with this same setup at 16:11 UTC, exit code 0: see 1.2.)

[oer-s92] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s92] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s92] [oer-s92] Transcript (redacted): raw\s92\prereq-20261006-160659Z.log; OerLive 1.0.3.
[oer-s92] [oer-s92] Mode: CREATE or complete. Prefix 'oer-s92-'. Objects (fixed): oer-s92-grp (prereq description, no member); oer-s92-member (no member). OerLive 1.0.3.
[oer-s92] [oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s92] [oer-s92] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s92] [oer-s92] Residue: raw\residue.json holds no rows.
[oer-s92] [oer-s92] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s92-' is left.
[oer-s92] [oer-s92] Found: oer-s92-grp exists: False; oer-s92-member exists: False.
[oer-s92] [oer-s92] No baseline yet: it is written now, before the first write to the tenant (groups 98).
[oer-s92] [oer-s92] Wrote the baseline raw\s92\baseline-s92.json and read it back.
[oer-s92] [oer-s92] Created group oer-s92-grp: 201.
[oer-s92] [oer-s92] oer-s92-grp resolves by its display name: not yet (read 1, 0.3 s, likely replication delay) -- reading again in 2 s.
[oer-s92] [oer-s92] oer-s92-grp resolves by its display name: not yet (read 2, 2.4 s, likely replication delay) -- reading again in 4 s.
[oer-s92] [oer-s92] oer-s92-grp resolves by its display name: converged after 3 read(s), 6.5 s.
[oer-s92] [oer-s92] Created group oer-s92-member: 201.
[oer-s92] [oer-s92] oer-s92-member resolves by its display name: not yet (read 1, 0 s, likely replication delay) -- reading again in 2 s.
[oer-s92] [oer-s92] oer-s92-member resolves by its display name: not yet (read 2, 2.1 s, likely replication delay) -- reading again in 4 s.
[oer-s92] [oer-s92] oer-s92-member resolves by its display name: not yet (read 3, 6.2 s, likely replication delay) -- reading again in 8 s.
[oer-s92] [oer-s92] oer-s92-member resolves by its display name: converged after 4 read(s), 14.3 s.
[oer-s92] [oer-s92] Summary: oer-s92-grp present; oer-s92-member present; written to the tenant: True.
[oer-s92] [oer-s92] Done.
[oer-s92] Exit code: 0
```

## 1. Regression: each command alone works as before

**1.1 to 1.4 run in ONE process**, in order. The fence counts every Graph request by method; it is a
global function the module's unqualified `Invoke-MgGraphRequest` resolves to (a function outranks a
cmdlet), and it forwards each request to the real cmdlet, module-qualified. The apply document is
written to the step's raw folder and deleted at the end of 1.3.

### 1.1. Invoke-OERStructure alone, without -TenantId: the document is applied

- [x] **1.1** `Invoke-OERStructure -Path <doc> -Confirm:$false`, a statement of its own, without `-TenantId`: `oer-s92-grp`'s description is updated and `oer-s92-member` is added as its member; no `SignInSuperseded`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s92'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'GET') { `$global:S92GraphWrites++ }; `$global:S92GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { `$global:S92ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
function Get-S92Who {
    # Who the module is, as True/False only.
    $S = & $Module { $script:_OERAuthState }
    "the state names the test tenant: $(([string]$S.TenantId).ToLowerInvariant() -eq $Cfg.TenantId); the state's client is oer-live-cc: $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId); is oer-live-cc-noperm: $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.NoPermAppId); the module holds an ARM token: $([bool]$S.ArmToken)"
}
function Invoke-S92 {
    # A plain call, outside any try, as at a prompt. Prints the output objects (a StructureResult as
    # section, item, action and detail; anything else by its type), the error ids (with the target of a
    # SignInSuperseded or SignInRefused, a command name), the request counts and who the module is now;
    # never a token, never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S92GraphCalls = 0; $global:S92GraphWrites = 0; $global:S92ArmCalls = 0
    $All = @(& $Call 2>&1)
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Ids = @($Errs | ForEach-Object {
            $Id = ([string]$_.FullyQualifiedErrorId -split ',')[0]
            if ($Id -in 'SignInSuperseded', 'SignInRefused') { "$Id ($($_.TargetObject))" } else { $Id }
        })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S92GraphCalls (writes: $global:S92GraphWrites); ARM requests: $global:S92ArmCalls; $(Get-S92Who)"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
        } else {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0])"
        }
    }
    foreach ($E in @($Errs | Group-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { $_.Group[0] })) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category) -- $Text"
    }
    , $Out
}
$null = [System.IO.Directory]::CreateDirectory($Raw)
$Doc = Join-Path $Raw 'apply-s92.json'
[System.IO.File]::WriteAllText($Doc, (@{
            version = '1.0'
            groups  = @(@{ displayName = 'oer-s92-grp'; description = 'Omnicit.EntraRBAC live verification (oer-s92-): applied'; members = @('oer-s92-member') })
        } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$null = Invoke-S92 -Label '1.1 Invoke-OERStructure alone, without -TenantId' -Call { Invoke-OERStructure -Path $Doc -Confirm:$false }
$GroupId = [string](Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s92-grp'"))).Body['value'][0]['id']
$MemberId = [string](Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s92-member'"))).Body['value'][0]['id']
$Listed = Wait-OerLiveConverged -Activity 'oer-s92-member is listed as a member of oer-s92-grp' -Read {
    $R = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$GroupId/members?`$select=id"
    , @(if ($R.Ok) { @($R.Body['value']) | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } })
} -Test { @($args[0]) -contains $MemberId.ToLowerInvariant() }
$Desc = [string](Invoke-OerLiveGraph -Uri "v1.0/groups/$($GroupId)?`$select=description").Body['description']
Write-OerLiveStep "1.1 read back: oer-s92-member is a member of oer-s92-grp: $(@($Listed.Value) -contains $MemberId.ToLowerInvariant()) (after $($Listed.Seconds) s); the description is the document's: $($Desc -ceq 'Omnicit.EntraRBAC live verification (oer-s92-): applied')"
```

**Expect:** the identity lines `True`; the fences `True`; `errors: none`; a row `groups | oer-s92-grp |
Updated` for the description and a row for the member `oer-s92-member` that adds it; `Graph requests`
with `writes: 2` (the PATCH and the member `$ref` POST); `ARM requests: 0`; the read back `True` and
`True`.
**Failure looks like:** `SignInSuperseded` -- the new check refuses a command whose session did not
change (a false refusal of every plain apply); `writes: 0` -- nothing was applied; a `Failed` row --
read its detail.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:12 UTC as oer-live-cc (every identity line True), with the module from the step's worktree build (a4f8d95 code: the snapshot helper, the four checks before a sign-in and the BL-74 check present) and the two forwarding fences resolving for the module (True). Invoke-OERStructure -Path (the document, in raw\s92\) -Confirm:$false, a statement of its own, without -TenantId: no error; two rows, groups | oer-s92-grp | Updated (Description) and Updated (added member 'oer-s92-member'); Graph requests 8, of which 2 writes (the PATCH and the member reference); ARM requests 0. Read back: oer-s92-member is a member of oer-s92-grp (True, after 0.1 s) and the description is the document's (True). A plain apply whose session did not change is not refused.

[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s92] 1.1 Invoke-OERStructure alone, without -TenantId: output objects 2; errors: none; Graph requests: 8 (writes: 2); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.1 Invoke-OERStructure alone, without -TenantId: row groups | oer-s92-grp | Updated | updated group properties (Description)
[oer-s92] 1.1 Invoke-OERStructure alone, without -TenantId: row groups | oer-s92-grp | Updated | added member 'oer-s92-member'
[oer-s92] oer-s92-member is listed as a member of oer-s92-grp: converged after 1 read(s), 0.1 s.
[oer-s92] 1.1 read back: oer-s92-member is a member of oer-s92-grp: True (after 0.1 s); the description is the document's: True
```

### 1.2. The same document again: only Unchanged (G8)

- [x] **1.2** The same `Invoke-OERStructure -Path <doc> -Confirm:$false` again: every row `Unchanged`, no write.

```powershell
# Graph's replicas can answer a read by id with the old description for a while after the PATCH:
# the first run of this check, started seconds after 1.1, read it and reported Updated again, while
# 1.3 a few seconds later found every row Unchanged. Wait until three reads in a row, 5 s apart,
# return the document's description, then run the same document again.
$Steady = 0; $Waited = 0
while ($Steady -lt 3 -and $Waited -lt 120) {
    Start-Sleep -Seconds 5; $Waited += 5
    $Now = [string](Invoke-OerLiveGraph -Uri "v1.0/groups/$($GroupId)?`$select=description").Body['description']
    if ($Now -ceq 'Omnicit.EntraRBAC live verification (oer-s92-): applied') { $Steady++ } else { $Steady = 0 }
}
Write-OerLiveStep "1.2: three reads in a row return the document's description: $($Steady -ge 3) (after $Waited s)"
$null = Invoke-S92 -Label '1.2 the same document again, without -TenantId' -Call { Invoke-OERStructure -Path $Doc -Confirm:$false }
```

**Expect:** `three reads in a row return the document's description: True`; `errors: none`; every row
`Unchanged`; `writes: 0`; `ARM requests: 0`.
**Failure looks like:** an `Updated` or a member row that adds again -- the first run did not converge
(wait and run again before judging); `SignInSuperseded` -- a false refusal.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (round 1). Run 2026-10-06 16:12 UTC: after three reads in a row returned the document's description (True, after 20 s), the same document again without -TenantId: both rows Unchanged (group properties match; member already present); Graph requests 5, writes 0; ARM requests 0. The first run of this check (16:07 UTC), started seconds after 1.1, reported the description Updated a second time (writes 1) while 1.3 a few seconds later found every row Unchanged: Graph's replicas returned the old description to a read by id after the PATCH. The checklist gained the wait (commit "wait for the description to settle before the live checklist's second apply"), the two groups were removed and created again with the prerequisite script, and section 1 was run again from 1.1. No code changed.

[oer-s92] 1.2: three reads in a row return the document's description: True (after 20 s)
[oer-s92] 1.2 the same document again, without -TenantId: output objects 2; errors: none; Graph requests: 5 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.2 the same document again, without -TenantId: row groups | oer-s92-grp | Unchanged | group properties match
[oer-s92] 1.2 the same document again, without -TenantId: row groups | oer-s92-grp | Unchanged | member 'oer-s92-member' already present

The first run of 1.2 (16:07 UTC, before the wait was added):
[oer-s92] 1.2 the same document again, without -TenantId: output objects 2; errors: none; Graph requests: 7 (writes: 1); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.2 the same document again, without -TenantId: row groups | oer-s92-grp | Updated | updated group properties (Description)
[oer-s92] 1.2 the same document again, without -TenantId: row groups | oer-s92-grp | Unchanged | member 'oer-s92-member' already present
```

### 1.3. The same document with -TenantId: only Unchanged

- [x] **1.3** `Invoke-OERStructure -Path <doc> -TenantId <test tenant> -Confirm:$false`: every row `Unchanged`, no write -- a command with `-TenantId` behaves as before.

```powershell
$null = Invoke-S92 -Label '1.3 the same document with -TenantId' -Call { Invoke-OERStructure -Path $Doc -TenantId $Cfg.TenantId -Confirm:$false }
[System.IO.File]::Delete($Doc)
Write-OerLiveStep "1.3: the apply document is deleted: $(-not (Test-Path -LiteralPath $Doc))"
```

**Expect:** `errors: none`; every row `Unchanged`; `writes: 0`; the document deleted `True`.
**Failure looks like:** any write, or any error.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:12 UTC: the same document with -TenantId naming the test tenant: both rows Unchanged; Graph requests 5, writes 0; ARM requests 0; the document deleted (True). A command with -TenantId behaves as before.

[oer-s92] 1.3 the same document with -TenantId: output objects 2; errors: none; Graph requests: 5 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.3 the same document with -TenantId: row groups | oer-s92-grp | Unchanged | group properties match
[oer-s92] 1.3 the same document with -TenantId: row groups | oer-s92-grp | Unchanged | member 'oer-s92-member' already present
[oer-s92] 1.3: the apply document is deleted: True
```

### 1.4. Each builder alone, with a name it looks up

- [x] **1.4** `New-OERAccessPackageApprovalStage -DurationDays 7 -Group oer-s92-member`, `New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group oer-s92-member` and `New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member`, each a statement of its own: each builds its object around `oer-s92-member`'s object id, one Graph request each, no error.

```powershell
$Stage = Invoke-S92 -Label '1.4a New-OERAccessPackageApprovalStage alone' -Call { New-OERAccessPackageApprovalStage -DurationDays 7 -Group 'oer-s92-member' }
Write-OerLiveStep "1.4a: the primary approver is oer-s92-member: $(@($Stage)[0].GraphStage.primaryApprovers[0].groupId -eq $MemberId)"
$Scope = Invoke-S92 -Label '1.4b New-OERAccessPackageRequestorScope alone' -Call { New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'oer-s92-member' }
Write-OerLiveStep "1.4b: the allowed target is oer-s92-member: $(@($Scope)[0].SpecificAllowedTargets[0].groupId -eq $MemberId)"
$Review = Invoke-S92 -Label '1.4c New-OERAccessReviewStage alone' -Call { New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup 'oer-s92-member' }
Write-OerLiveStep "1.4c: the reviewer query names oer-s92-member: $(@($Review)[0].GraphStage.reviewers[0].query -eq "/groups/$MemberId/transitiveMembers")"
foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { Remove-Item -Path "function:$Name" -ErrorAction SilentlyContinue }
Write-OerLiveStep "Fences removed: $(-not (Test-Path function:Invoke-MgGraphRequest) -and -not (Test-Path function:Invoke-WebRequest))"
Disconnect-OerLive
```

**Expect:** for each builder `output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM
requests: 0`, and its line naming `oer-s92-member` `True`; `Fences removed: True`.
**Failure looks like:** `SignInSuperseded` -- a false refusal of a builder whose session did not
change; `Graph requests: 0` with an object -- the name was not looked up (check the call).

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:12 UTC, each a statement of its own: New-OERAccessPackageApprovalStage -DurationDays 7 -Group oer-s92-member, New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group oer-s92-member and New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member: each one object, no error, Graph requests 1 (the name lookup), writes 0, ARM requests 0; the primary approver, the allowed target and the reviewer query each name oer-s92-member's object id (True). The fences removed (True).

[oer-s92] 1.4a New-OERAccessPackageApprovalStage alone: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.4a New-OERAccessPackageApprovalStage alone: object Omnicit.EntraRBAC.ApprovalStage
[oer-s92] 1.4a: the primary approver is oer-s92-member: True
[oer-s92] 1.4b New-OERAccessPackageRequestorScope alone: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.4b New-OERAccessPackageRequestorScope alone: object Omnicit.EntraRBAC.RequestorScope
[oer-s92] 1.4b: the allowed target is oer-s92-member: True
[oer-s92] 1.4c New-OERAccessReviewStage alone: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 1.4c New-OERAccessReviewStage alone: object Omnicit.EntraRBAC.AccessReviewStageSetting
[oer-s92] 1.4c: the reviewer query names oer-s92-member: True
[oer-s92] Fences removed: True
```

## 2. A command does not act under a session another command in the pipeline switched to

**2.1 to 2.6 run in ONE process**, in order. Each check that switches identity signs in again with
`Connect-OerLive -Arm` (which runs `Disconnect-OER` and `Disconnect-MgGraph` first) before its own
pipeline. The mechanism is that of the previous step's section 4 (the checklist
[fix-refuse-a-changed-graph-sdk-session-checklist.md](fix-refuse-a-changed-graph-sdk-session-checklist.md)):
`Connect-OER` in `ForEach-Object -Begin`, as `oer-live-cc-noperm`, runs after the upstream command's
`begin` block and before its `process` block. Token requests are real here; only Graph and ARM
requests are fenced and counted.

### 2.1. Invoke-OERStructure without -TenantId, then a sign-in as another identity in the same pipeline: refused, nothing sent

- [x] **2.1** `Invoke-OERStructure -Path <doc> -WhatIf` without `-TenantId`, piped into `ForEach-Object -Begin { Connect-OER ... }` signing in as `oer-live-cc-noperm`: the only error is `SignInSuperseded` naming `Invoke-OERStructure`, no row, and the fences count 0 Graph and 0 ARM requests.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s92'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'GET') { `$global:S92GraphWrites++ }; `$global:S92GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { `$global:S92ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
function Get-S92Who {
    # Who the module is, as True/False only.
    $S = & $Module { $script:_OERAuthState }
    "the state names the test tenant: $(([string]$S.TenantId).ToLowerInvariant() -eq $Cfg.TenantId); the state's client is oer-live-cc: $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId); is oer-live-cc-noperm: $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.NoPermAppId); the module holds an ARM token: $([bool]$S.ArmToken)"
}
function Invoke-S92 {
    # A plain call, outside any try, as at a prompt. Prints the output objects (a StructureResult as
    # section, item, action and detail; anything else by its type), the error ids (with the target of a
    # SignInSuperseded or SignInRefused, a command name), the request counts and who the module is now;
    # never a token, never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S92GraphCalls = 0; $global:S92GraphWrites = 0; $global:S92ArmCalls = 0
    $All = @(& $Call 2>&1)
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Ids = @($Errs | ForEach-Object {
            $Id = ([string]$_.FullyQualifiedErrorId -split ',')[0]
            if ($Id -in 'SignInSuperseded', 'SignInRefused') { "$Id ($($_.TargetObject))" } else { $Id }
        })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S92GraphCalls (writes: $global:S92GraphWrites); ARM requests: $global:S92ArmCalls; $(Get-S92Who)"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
        } else {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0])"
        }
    }
    foreach ($E in @($Errs | Group-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { $_.Group[0] })) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category) -- $Text"
    }
    , $Out
}
$null = [System.IO.Directory]::CreateDirectory($Raw)
$Doc = Join-Path $Raw 'apply-s92.json'
[System.IO.File]::WriteAllText($Doc, (@{
            version = '1.0'
            groups  = @(@{ displayName = 'oer-s92-grp'; description = 'Omnicit.EntraRBAC live verification (oer-s92-): applied'; members = @('oer-s92-member') })
        } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "Before 2.1: $(Get-S92Who)"
$null = Invoke-S92 -Label '2.1 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc-noperm in the same pipeline' -Call {
    Invoke-OERStructure -Path $Doc -WhatIf |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert } -Process { $_ }
}
```

**Expect:** the identity lines `True`; the fences `True`; before 2.1 the state's client is `oer-live-cc`
(`True`); then `output objects 0`; errors `SignInSuperseded (Invoke-OERStructure)` and nothing else;
`Graph requests: 0 (writes: 0); ARM requests: 0`; afterwards the state's client is
`oer-live-cc-noperm` (`True`): `Connect-OER` ran in the pipeline's `begin`, after
`Invoke-OERStructure`'s, and switched the identity before the document was processed. The message
names `Invoke-OERStructure` and no tenant.
**Failure looks like:** `Graph requests: 1` or more, and a 403 or rows -- the document was planned
under `oer-live-cc-noperm`'s session, the identity `Invoke-OERStructure` never began under (BL-76);
`SignInRefused` or `GraphSessionChanged` instead -- another gate caught it, so this check proves
nothing about the new one; the state's client still `oer-live-cc` -- `Connect-OER` did not run in the
pipeline's `begin`; a 401 or 403 for `oer-live-cc` before the pipeline -- STOP.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:12 UTC as oer-live-cc (every identity line True), with the module from the step's worktree build (a4f8d95 code: the snapshot helper, the four checks before a sign-in and the BL-74 check present) and the fences resolving (True). Before: the state's client is oer-live-cc, the module holds an ARM token. Invoke-OERStructure -Path (the document) -WhatIf without -TenantId piped into ForEach-Object -Begin { Connect-OER ... } as oer-live-cc-noperm: no output object; the only error SignInSuperseded with target Invoke-OERStructure (category AuthenticationError; the message names Invoke-OERStructure and no tenant); Graph requests 0, writes 0, ARM requests 0. Afterwards the state's client is oer-live-cc-noperm (True) and the module holds no ARM token. Before this branch the same pipeline planned the document under oer-live-cc-noperm's session (BL-76; read in the code and reproduced by the unit and end-to-end tests with the check removed).

[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: True
[oer-s92] Before 2.1: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.1 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc-noperm in the same pipeline: output objects 0; errors: SignInSuperseded (Invoke-OERStructure); Graph requests: 0 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: False; is oer-live-cc-noperm: True; the module holds an ARM token: False
[oer-s92] 2.1 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc-noperm in the same pipeline: SignInSuperseded,Invoke-OERStructure; category AuthenticationError -- Another OER command in the same pipeline signed in to a different tenant or identity after Invoke-OERStructure began, so Omnicit.EntraRBAC sends nothing while Invoke-OERStructure runs: this request was not sent. Run the commands as separate statements, so that each one signs in and finishes before t ...
```

### 2.2. The same identity again in the same pipeline: nothing is refused

- [x] **2.2** After signing in again as `oer-live-cc`, the same pipeline with `Connect-OER` signing in as `oer-live-cc` again: no `SignInSuperseded`, the plan is read (Graph requests, no write), and every row is `Unchanged`.

```powershell
Connect-OerLive -Arm
Write-OerLiveStep "Before 2.2: $(Get-S92Who)"
$null = Invoke-S92 -Label '2.2 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc again in the same pipeline' -Call {
    Invoke-OERStructure -Path $Doc -WhatIf |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert } -Process { $_ }
}
[System.IO.File]::Delete($Doc)
Write-OerLiveStep "2.2: the apply document is deleted: $(-not (Test-Path -LiteralPath $Doc))"
```

**Expect:** the identity lines `True`; `errors: none`; every row `Unchanged`; `Graph requests` 1 or more
with `writes: 0`; `ARM requests: 0`; the state's client `oer-live-cc` before and after; the document
deleted `True`. The same tenant, method, client and cloud are no change, so a pipeline that does not
change identity works exactly as before.
**Failure looks like:** `SignInSuperseded` -- the snapshot comparison refuses an identical sign-in (a
false refusal of every ordinary pipeline); `Graph requests: 0` with no error -- the plan never ran.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After Connect-OerLive -Arm as oer-live-cc again (identity check passed), the same pipeline with Connect-OER as oer-live-cc again in -Begin: no error; both rows Unchanged; Graph requests 5, writes 0; ARM requests 0; the client oer-live-cc before and after, ARM token kept; the document deleted (True). The same identity is no change, so an ordinary pipeline works as before.

[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Before 2.2: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.2 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc again in the same pipeline: output objects 2; errors: none; Graph requests: 5 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.2 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc again in the same pipeline: row groups | oer-s92-grp | Unchanged | group properties match
[oer-s92] 2.2 Invoke-OERStructure -WhatIf, then Connect-OER as oer-live-cc again in the same pipeline: row groups | oer-s92-grp | Unchanged | member 'oer-s92-member' already present
[oer-s92] 2.2: the apply document is deleted: True
```

### 2.3. New-OERAccessReviewStage, then a sign-in as another identity in the same pipeline: refused, no lookup

- [x] **2.3** After signing in again as `oer-live-cc`, `New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member` piped into `ForEach-Object -Begin { Connect-OER ... }` as `oer-live-cc-noperm`: the only error is `SignInSuperseded` naming `New-OERAccessReviewStage`, no object, and 0 Graph requests.

```powershell
Connect-OerLive -Arm
Write-OerLiveStep "Before 2.3: $(Get-S92Who)"
$null = Invoke-S92 -Label '2.3 New-OERAccessReviewStage, then Connect-OER as oer-live-cc-noperm in the same pipeline' -Call {
    New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup 'oer-s92-member' |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert } -Process { $_ }
}
```

**Expect:** `output objects 0`; errors `SignInSuperseded (New-OERAccessReviewStage)` only; `Graph
requests: 0 (writes: 0); ARM requests: 0`; afterwards the state's client is `oer-live-cc-noperm`.
**Failure looks like:** `Graph requests: 1` -- the name was looked up under `oer-live-cc-noperm`'s
session (BL-81); an error carrying a 403 instead of `SignInSuperseded`.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After Connect-OerLive -Arm again: New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member piped into ForEach-Object -Begin { Connect-OER ... } as oer-live-cc-noperm: no object; the only error SignInSuperseded with target New-OERAccessReviewStage; Graph requests 0, ARM requests 0; afterwards the client is oer-live-cc-noperm. The name was not looked up under the switched session (BL-81).

[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Before 2.3: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.3 New-OERAccessReviewStage, then Connect-OER as oer-live-cc-noperm in the same pipeline: output objects 0; errors: SignInSuperseded (New-OERAccessReviewStage); Graph requests: 0 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: False; is oer-live-cc-noperm: True; the module holds an ARM token: False
[oer-s92] 2.3 New-OERAccessReviewStage, then Connect-OER as oer-live-cc-noperm in the same pipeline: SignInSuperseded,New-OERAccessReviewStage; category AuthenticationError -- Another OER command in the same pipeline signed in to a different tenant or identity after New-OERAccessReviewStage began, so Omnicit.EntraRBAC sends nothing while New-OERAccessReviewStage runs: this request was not sent. Run the commands as separate statements, so that each one signs in and finishe ...
```

### 2.4. New-OERAccessPackageApprovalStage, then a sign-in as another identity in the same pipeline: refused, no lookup

- [x] **2.4** After signing in again as `oer-live-cc`, `New-OERAccessPackageApprovalStage -DurationDays 7 -Group oer-s92-member` piped into the same `ForEach-Object -Begin { Connect-OER ... }` as `oer-live-cc-noperm`: `SignInSuperseded` naming `New-OERAccessPackageApprovalStage`, no object, 0 Graph requests.

```powershell
Connect-OerLive -Arm
Write-OerLiveStep "Before 2.4: $(Get-S92Who)"
$null = Invoke-S92 -Label '2.4 New-OERAccessPackageApprovalStage, then Connect-OER as oer-live-cc-noperm in the same pipeline' -Call {
    New-OERAccessPackageApprovalStage -DurationDays 7 -Group 'oer-s92-member' |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert } -Process { $_ }
}
```

**Expect:** `output objects 0`; errors `SignInSuperseded (New-OERAccessPackageApprovalStage)` only;
`Graph requests: 0 (writes: 0); ARM requests: 0`.
**Failure looks like:** `Graph requests: 1` -- the lookup went out under the switched session.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After Connect-OerLive -Arm again: New-OERAccessPackageApprovalStage -DurationDays 7 -Group oer-s92-member in the same pipeline shape: no object; the only error SignInSuperseded with target New-OERAccessPackageApprovalStage; Graph requests 0, ARM requests 0.

[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Before 2.4: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.4 New-OERAccessPackageApprovalStage, then Connect-OER as oer-live-cc-noperm in the same pipeline: output objects 0; errors: SignInSuperseded (New-OERAccessPackageApprovalStage); Graph requests: 0 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: False; is oer-live-cc-noperm: True; the module holds an ARM token: False
[oer-s92] 2.4 New-OERAccessPackageApprovalStage, then Connect-OER as oer-live-cc-noperm in the same pipeline: SignInSuperseded,New-OERAccessPackageApprovalStage; category AuthenticationError -- Another OER command in the same pipeline signed in to a different tenant or identity after New-OERAccessPackageApprovalStage began, so Omnicit.EntraRBAC sends nothing while New-OERAccessPackageApprovalStage runs: this request was not sent. Run the commands as separate statements, so that each one si ...
```

### 2.5. New-OERAccessPackageRequestorScope, then a sign-in as another identity in the same pipeline: refused, no lookup

- [x] **2.5** After signing in again as `oer-live-cc`, `New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group oer-s92-member` piped into the same `ForEach-Object -Begin { Connect-OER ... }` as `oer-live-cc-noperm`: `SignInSuperseded` naming `New-OERAccessPackageRequestorScope`, no object, 0 Graph requests.

```powershell
Connect-OerLive -Arm
Write-OerLiveStep "Before 2.5: $(Get-S92Who)"
$null = Invoke-S92 -Label '2.5 New-OERAccessPackageRequestorScope, then Connect-OER as oer-live-cc-noperm in the same pipeline' -Call {
    New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'oer-s92-member' |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert } -Process { $_ }
}
```

**Expect:** `output objects 0`; errors `SignInSuperseded (New-OERAccessPackageRequestorScope)` only;
`Graph requests: 0 (writes: 0); ARM requests: 0`.
**Failure looks like:** `Graph requests: 1` -- the lookup went out under the switched session.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After Connect-OerLive -Arm again: New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group oer-s92-member in the same pipeline shape: no object; the only error SignInSuperseded with target New-OERAccessPackageRequestorScope; Graph requests 0, ARM requests 0.

[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Before 2.5: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.5 New-OERAccessPackageRequestorScope, then Connect-OER as oer-live-cc-noperm in the same pipeline: output objects 0; errors: SignInSuperseded (New-OERAccessPackageRequestorScope); Graph requests: 0 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: False; is oer-live-cc-noperm: True; the module holds an ARM token: False
[oer-s92] 2.5 New-OERAccessPackageRequestorScope, then Connect-OER as oer-live-cc-noperm in the same pipeline: SignInSuperseded,New-OERAccessPackageRequestorScope; category AuthenticationError -- Another OER command in the same pipeline signed in to a different tenant or identity after New-OERAccessPackageRequestorScope began, so Omnicit.EntraRBAC sends nothing while New-OERAccessPackageRequestorScope runs: this request was not sent. Run the commands as separate statements, so that each one  ...
```

### 2.6. A builder with the same identity again in the same pipeline: nothing is refused

- [x] **2.6** After signing in again as `oer-live-cc`, `New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member` piped into `ForEach-Object -Begin { Connect-OER ... }` as `oer-live-cc` again: no `SignInSuperseded`, one Graph request, and the stage names `oer-s92-member`.

```powershell
Connect-OerLive -Arm
$MemberId = [string](Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s92-member'"))).Body['value'][0]['id']
Write-OerLiveStep "Before 2.6: $(Get-S92Who)"
$Review = Invoke-S92 -Label '2.6 New-OERAccessReviewStage, then Connect-OER as oer-live-cc again in the same pipeline' -Call {
    New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup 'oer-s92-member' |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert } -Process { $_ }
}
Write-OerLiveStep "2.6: the reviewer query names oer-s92-member: $(@($Review)[0].GraphStage.reviewers[0].query -eq "/groups/$MemberId/transitiveMembers")"
foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { Remove-Item -Path "function:$Name" -ErrorAction SilentlyContinue }
Write-OerLiveStep "Fences removed: $(-not (Test-Path function:Invoke-MgGraphRequest) -and -not (Test-Path function:Invoke-WebRequest))"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 0`; the
reviewer query `True`; `Fences removed: True`.
**Failure looks like:** `SignInSuperseded` -- a false refusal; `Graph requests: 0` -- the name was not
looked up.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After Connect-OerLive -Arm again: New-OERAccessReviewStage -DurationInDays 7 -ReviewerGroup oer-s92-member with Connect-OER as oer-live-cc again in -Begin: one object, no error, Graph requests 1 (the lookup), ARM requests 0; the reviewer query names oer-s92-member (True); the client oer-live-cc before and after. The fences removed (True).

[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Before 2.6: the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.6 New-OERAccessReviewStage, then Connect-OER as oer-live-cc again in the same pipeline: output objects 1; errors: none; Graph requests: 1 (writes: 0); ARM requests: 0; the state names the test tenant: True; the state's client is oer-live-cc: True; is oer-live-cc-noperm: False; the module holds an ARM token: True
[oer-s92] 2.6 New-OERAccessReviewStage, then Connect-OER as oer-live-cc again in the same pipeline: object Omnicit.EntraRBAC.AccessReviewStageSetting
[oer-s92] 2.6: the reviewer query names oer-s92-member: True
[oer-s92] Fences removed: True
```

## Teardown

### T.1. The prerequisite objects are removed, nothing carries the prefix, no session is left, and the main clone is untouched

- [x] **T.1** `Initialize-OerS92Prereq.ps1 -Teardown -Unattended` removes `oer-s92-grp` and `oer-s92-member`; the sweep finds nothing with the prefix `oer-s92-`; the group count equals the baseline; no session is left; the main clone is still on `main` at the HEAD S.1 recorded; the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS92Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s92-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Teardown exit code: $Code"
Connect-OerLive -Arm
$Left = @(Find-OerLivePrefixed -ThrowOnUnread)
Disconnect-OerLive
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "Prefixed objects: $($Left.Count); a Graph SDK session is left: $([bool](Get-MgContext)); the module holds a session: $([bool](& $Module { $script:_OERAuthState }))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the teardown's identity lines `True`; both groups deleted (the library's step 5); `Counts:
groups now N, at the baseline N; equal: True`; teardown exit code 0; the sweep's "no ... starting with
'oer-s92-' is left"; `Prefixed objects: 0; a Graph SDK session is left: False; the module holds a
session: False`; the main clone on `main` at the HEAD S.1 recorded. After the results are copied into
this file: `Clear-OerLiveRedactionMap`, and `raw\s92\` deleted.
**Failure looks like:** exit code 3 -- residue: the rows are in `raw\residue.json` and the next prereq
run retries them; report each in the step's report. A group deleted with 204 can still show in the
sweep for a few seconds: read back again before judging.

Result: 2026-10-06 16:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-06 16:14 UTC: the prerequisite script's -Teardown (identity check passed, no residue to retry) removed the member link (201) and deleted oer-s92-grp and oer-s92-member (204 each): removed 3, residue 0, unreadable 0, exit code 0. The sweep straight after still listed both deleted groups and counted 99 groups against the baseline's 98 -- the listing lags a DELETE by seconds (measured before in this programme), so the controller read back at 16:16 UTC with -ReadBack: no object starting with oer-s92- in any of the six collections, groups 98 equal to the baseline (True), no residue row. After Disconnect-OerLive no Graph SDK session is left and the module holds no session; the main clone is on main at 6817b33, the HEAD S.1 recorded, never switched. The redaction map is cleared and raw\s92\ deleted after this write-up.

[oer-s92] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s92] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s92] [oer-s92] Transcript (redacted): raw\s92\teardown-20261006-161403Z.log; OerLive 1.0.3.
[oer-s92] [oer-s92] Mode: REMOVE. Prefix 'oer-s92-'. Objects (fixed): oer-s92-grp (prereq description, no member); oer-s92-member (no member). OerLive 1.0.3.
[oer-s92] [oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] [oer-s92] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s92] [oer-s92] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s92] [oer-s92] Residue: raw\residue.json holds no rows.
[oer-s92] [oer-s92] Teardown of 'oer-s92-': users 0, groups 2, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s92] [oer-s92] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s92] [oer-s92] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s92] [oer-s92] Removed: oer-s92-grp: PIM for Groups member assignment of a principal (201).
[oer-s92] [oer-s92] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s92] [oer-s92] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s92] [oer-s92] Teardown 5/6: the prefixed groups.
[oer-s92] [oer-s92] Deleted: group oer-s92-grp (204).
[oer-s92] [oer-s92] Deleted: group oer-s92-member (204).
[oer-s92] [oer-s92] Teardown 6/6: the prefixed users.
[oer-s92] [oer-s92] Teardown of 'oer-s92-': removed 3, residue 0, unreadable 0.
[oer-s92] [oer-s92] Sweep: group 'oer-s92-grp' (00000000-0000-0000-0000-000000000005) carries the prefix.
[oer-s92] [oer-s92] Counts: groups now 99, at the baseline 98; equal: False
[oer-s92] [oer-s92] Done.
[oer-s92] Teardown exit code: 0
[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s92] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s92] Sweep: group 'oer-s92-grp' (00000000-0000-0000-0000-000000000005) carries the prefix.
[oer-s92] Sweep: group 'oer-s92-member' (00000000-0000-0000-0000-000000000006) carries the prefix.
[oer-s92] Prefixed objects: 2; a Graph SDK session is left: False; the module holds a session: False
[oer-s92] Main clone: branch main; HEAD 6817b33

Read-back at 16:16 UTC (Initialize-OerS92Prereq.ps1 -ReadBack):
[oer-s92] Transcript (redacted): raw\s92\readback-20261006-161658Z.log; OerLive 1.0.3.
[oer-s92] Mode: READ BACK. Prefix 'oer-s92-'. Objects (fixed): oer-s92-grp (prereq description, no member); oer-s92-member (no member). OerLive 1.0.3.
[oer-s92] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg2\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s92] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s92] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s92] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s92-' is left.
[oer-s92] Counts: groups now 98, at the baseline 98; equal: True
[oer-s92] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s92] Done.
Exit code: 0; started 2026-10-06 16:16:57 UTC
```
