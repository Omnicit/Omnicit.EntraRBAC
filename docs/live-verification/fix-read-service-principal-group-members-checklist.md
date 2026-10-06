# Live verification checklist -- service principals are among a group's members and owners (fix/read-service-principal-group-members)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s91-`.** The
prerequisite script creates two plain security groups, `oer-s91-grp` and `oer-s91-nested`, makes
`oer-s91-nested` a member of `oer-s91-grp`, and makes the service principal `oer-live-cc-noperm` a
member AND an owner of `oer-s91-grp`. The service principal itself is never changed: only those two
links inside a prefixed group are created, and they go when the group is deleted. It is a different
service principal from the one signed in, so what this file measures is not an artefact of a
principal reading itself. No directory role is assigned and no policy is changed.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS91Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). The 403 checks sign in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all; a 403 there is the
expected answer, not a stop. Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`; read the plan against the `Expect:` line before running the line that
writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s91/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. Every block below prints through the library's redactor, so its lines are already
redacted per [README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the
same id the same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
failure's record can carry the bearer token. Every block prints the error id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

**The defect (BL-13).** Microsoft Graph's `v1.0` `groups/{id}/members` does not list a service
principal that is a member, and `groups/{id}/owners` does not list a service principal that is an
owner -- both are documented on Microsoft Learn ("Known issues in Microsoft Graph": GET
/groups/{id}/members doesn't return service principals in v1.0; and the note on List group owners),
and the members half was measured with this identity on 2026-09-29
(`feat-directory-role-assignments-checklist.md`). `Get-OERGroup -IncludeMembers -IncludeOwners` and
`Get-OERGroupMember` read exactly those two collections, so the module never saw such a member or
owner. The export, which reads through `Get-OERGroup`, therefore wrote a group's members and owners
without its service principals, and a later `Invoke-OERStructure -Prune` run by any identity whose
read DOES list them would remove every such membership and ownership as undeclared. The read
succeeded, so the guard for unread collections never fired. (Review corrected the premise of that
last chain: Microsoft Learn documents both omissions for every caller of `v1.0`, so no earlier
version's read listed a group's service principals, and no earlier version pruned one. The defect
was an incomplete export, and a `Failed` row for a declared service principal.)

**Round 1, decision A9.** Making the reads whole would, on its own, have turned every document
written before them -- none lists a group's service principals -- into a removal of them under
`-Prune`, more than any earlier version removed. Decision A9 keeps the reads and the export whole
and withholds that prune instead: an undeclared service principal member or owner is `Extra`
without `-Prune`, with a hint that `-Prune` leaves it in place, and `Skipped` with `-Prune`, with a
Detail starting `prune withheld: ... is a service principal`, with no warning and no removal; every
other type is pruned as before. Round 1 is the section R1 below, 4.2 run again with A9's
expectation, the new 4.3 and 4.4, and the teardown R1.T1 to R1.T3. Every other result in this file
is round 0's and stands.

Section 1 of this file measures the reads BEFORE the fix, on the unchanged build, and decides which
object types the fix has to read typed (the step's scope, point 3). Sections 2 to 5, written once the
fix is built, verify it against the same objects.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS91Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes two groups and adds two members and one
  owner to one of them with the permissions it already holds; this file adds none.
- The **built module** in the step's own worktree, built there with `./build.ps1 -Tasks build`, and
  the environment variable `OER_LIVE_REPO` naming that worktree. Each block's fifth line sets the
  session's `Repo` to it, so the module loads from the worktree's build; the main clone is never
  checked out on another commit or branch (S.1 reads that it was not). Section 1 runs on the build of
  the UNCHANGED branch (`main` at the step's start); sections 2 to 5 on the build of the fix.

### S.1. The module loads from the build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-OerLiveStep "The worktree's build: version $(Split-Path -Leaf $Psd1.DirectoryName), built $($Psd1.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm 'UTC'", [cultureinfo]::InvariantCulture))"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded); the worktree on `fix/read-service-principal-group-members` with 0 tracked
changes; the build's version and time.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 6817b33, never switched; the worktree on fix/read-service-principal-group-members at f2cee8a with 0 tracked changes; the build is 1.1.3 of the unchanged branch (built 07:57 UTC from dd7bb8a, before any source change), which is what section 1 measures.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] The module loads from a worktree that is not the main clone: True
[oer-s91] Main clone: branch main; HEAD 6817b33
[oer-s91] Worktree: branch fix/read-service-principal-group-members; HEAD f2cee8a docs: read the measurement's ids as lists and stop when a lookup is empty; tracked changes: 0
[oer-s91] The worktree's build: version 1.1.3, built 2026-10-06 07:57 UTC
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is the worktree's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
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

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Every identity line True for the module session (app-only certificate session with the identity's app id, app name oer-live-cc, test tenant, the service principal named oer-live-cc and the token's signed-in object; organization name, verified domain, organization id; ARM token from the certificate; the test subscription belongs to the test tenant and is Enabled); identity check passed; the module is the worktree's build (1.1.3).

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The module is the worktree's build: True
```

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [x] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False` -- STOP; sections 1 and 5 need this session.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. oer-live-cc-noperm: app-only with its app id, app name oer-live-cc-noperm, test tenant, ARM token from the certificate: all True; identity check passed; the module is the worktree's build.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s91] The module is the worktree's build: True
```

### 0.3. The prerequisite script's plan

- [x] **0.3** `-WhatIf` plans only `oer-s91-` targets in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; `The service principal of the noperm app id is named
oer-live-cc-noperm: True`; the sweep reads all six collections and finds no `oer-s91-` object; the
plan names the transcript and the baseline under `raw\s91\` and, in the tenant, the groups
`oer-s91-grp` and `oer-s91-nested` and the three links `oer-s91-grp: member oer-s91-nested`,
`oer-s91-grp: member oer-live-cc-noperm (service principal)` and `oer-s91-grp: owner
oer-live-cc-noperm (service principal)` -- five tenant targets, every one starting with `oer-s91-`;
`WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Identity check passed; the noperm service principal is named oer-live-cc-noperm; the sweep read all six collections and found no oer-s91- object; 7 What-if targets: 2 local files under raw\s91\ (the transcript and the baseline) and 5 in the tenant (oer-s91-grp, oer-s91-nested, and the three links in oer-s91-grp: member oer-s91-nested, member oer-live-cc-noperm, owner oer-live-cc-noperm), every tenant target with the prefix; the service principal is only linked into the prefixed group, never changed itself; nothing written; exit code 0.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s91\prereq-20261006-080723Z.log".
[oer-s91] Mode: CREATE or complete. Prefix 'oer-s91-'. Objects (fixed): oer-s91-grp; oer-s91-nested, a member of it; oer-live-cc-noperm (service principal, never changed itself) a member and an owner of oer-s91-grp. OerLive 1.0.2.
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s91] Residue: raw\residue.json holds no rows.
[oer-s91] The service principal of the noperm app id is named oer-live-cc-noperm: True
[oer-s91] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s91-' is left.
[oer-s91] Found: oer-s91-grp exists: False; oer-s91-nested exists: False.
[oer-s91] No baseline yet: it is written now, before the first write to the tenant (groups 97; oer-live-cc-noperm a member of 0 group(s), owner of 0 object(s)).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s91\baseline-s91.json".
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s91-grp".
What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, no member)" on target "oer-s91-nested".
What if: Performing the operation "Add the group as a member (Graph v1.0 POST groups/members/$ref)" on target "oer-s91-grp: member oer-s91-nested".
What if: Performing the operation "Add the service principal as a member (Graph v1.0 POST groups/members/$ref; the service principal itself is not changed)" on target "oer-s91-grp: member oer-live-cc-noperm (service principal)".
What if: Performing the operation "Add the service principal as an owner (Graph v1.0 POST groups/owners/$ref; the service principal itself is not changed)" on target "oer-s91-grp: owner oer-live-cc-noperm (service principal)".
[oer-s91] Summary: oer-s91-grp absent; oer-s91-nested absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s91] WhatIf: nothing was created, removed or written.
[oer-s91] Done.
[oer-s91] What-if targets: 7; in the tenant: 5; every tenant target starts with oer-s91-: True; exit code: 0
```

### 0.4. The prerequisite script, for real

- [x] **0.4** The test objects exist: the two groups, the group and the service principal as members, the service principal as owner.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group
oer-s91-grp` and `Created group oer-s91-nested`; each of the three links added and then listed from
the OTHER side (the nested group's and the service principal's `memberOf`, the service principal's
`ownedObjects`), so the read this file measures is not the read that confirms the setup; the summary
with both groups `present`; exit code `0`. A `likely replication delay` line on a fresh object is
expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The baseline written and read back before the first write (groups 97; oer-live-cc-noperm a member of 0 groups and owner of 0 objects); both groups created (201) and resolvable by name after 3 reads (about 6 s each); the three links added (204, first attempt each) and listed from the other side (the nested group's memberOf, the service principal's memberOf and ownedObjects) after 2 to 3 reads; both groups present; exit code 0.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Transcript (redacted): raw\s91\prereq-20261006-080736Z.log; OerLive 1.0.2.
[oer-s91] Mode: CREATE or complete. Prefix 'oer-s91-'. Objects (fixed): oer-s91-grp; oer-s91-nested, a member of it; oer-live-cc-noperm (service principal, never changed itself) a member and an owner of oer-s91-grp. OerLive 1.0.2.
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s91] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s91] Residue: raw\residue.json holds no rows.
[oer-s91] The service principal of the noperm app id is named oer-live-cc-noperm: True
[oer-s91] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s91-' is left.
[oer-s91] Found: oer-s91-grp exists: False; oer-s91-nested exists: False.
[oer-s91] No baseline yet: it is written now, before the first write to the tenant (groups 97; oer-live-cc-noperm a member of 0 group(s), owner of 0 object(s)).
[oer-s91] Wrote the baseline raw\s91\baseline-s91.json and read it back.
[oer-s91] Created group oer-s91-grp: 201.
[oer-s91] oer-s91-grp resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s91] oer-s91-grp resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s91] oer-s91-grp resolves by its display name: converged after 3 read(s), 6.3 s.
[oer-s91] Created group oer-s91-nested: 201.
[oer-s91] oer-s91-nested resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s91] oer-s91-nested resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s91] oer-s91-nested resolves by its display name: converged after 3 read(s), 6.2 s.
[oer-s91] Added oer-s91-nested as a member of oer-s91-grp: 204 after 1 attempt(s).
[oer-s91] oer-s91-nested as a member of oer-s91-grp is listed: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s91] oer-s91-nested as a member of oer-s91-grp is listed: converged after 2 read(s), 2.2 s.
[oer-s91] Added oer-live-cc-noperm as a member of oer-s91-grp: 204 after 1 attempt(s).
[oer-s91] oer-live-cc-noperm as a member of oer-s91-grp is listed: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s91] oer-live-cc-noperm as a member of oer-s91-grp is listed: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s91] oer-live-cc-noperm as a member of oer-s91-grp is listed: converged after 3 read(s), 6.3 s.
[oer-s91] Added oer-live-cc-noperm as an owner of oer-s91-grp: 204 after 1 attempt(s).
[oer-s91] oer-live-cc-noperm as an owner of oer-s91-grp is listed: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s91] oer-live-cc-noperm as an owner of oer-s91-grp is listed: converged after 2 read(s), 2.2 s.
[oer-s91] Summary: oer-s91-grp present; oer-s91-nested present; written to the tenant: True.
[oer-s91] Done.
[oer-s91] Exit code: 0
```

### 1. The reads before the fix, measured on the unchanged build

Every request in this section goes through the module's OWN Graph transport, `Invoke-OERGraphRequest`
with `-All`, in the module's scope -- the exact path `Get-OERGroup` and `Get-OERGroupMember` take --
so a difference between two reads is Graph's, not a second client's. Each read prints its count and,
per object, its `@odata.type` and redacted id; a typed read also says, per object, whether the
untyped read listed it. The table these lines fill is the step's measurement, and point 3 of the
step's scope (which object types the fix reads typed) is decided from it.

### 1.1. Members: the untyped read against each typed read

- [x] **1.1** The untyped `members` read, the typed reads for service principal, user, group, device and organizational contact, and the `beta` untyped read for the record.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Nid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-nested'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; oer-s91-nested is $Nid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid -or -not $Nid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
$Untyped = Read-S91 -Uri "v1.0/groups/$Gid/members"
$UntypedIds = @($Untyped.Rows | ForEach-Object { [string]$_.id })
Write-OerLiveStep "READ v1.0 members (untyped): ok $($Untyped.Ok); count $($Untyped.Rows.Count)$(if (-not $Untyped.Ok) { "; $($Untyped.Error)" })"
foreach ($Row in $Untyped.Rows) { Write-OerLiveStep "  untyped: $($Row.'@odata.type') $($Row.id)" }
foreach ($T in 'servicePrincipal', 'user', 'group', 'device', 'orgContact') {
    $R = Read-S91 -Uri "v1.0/groups/$Gid/members/microsoft.graph.$T"
    Write-OerLiveStep "READ v1.0 members/microsoft.graph.$($T): ok $($R.Ok); count $($R.Rows.Count)$(if (-not $R.Ok) { "; $($R.Error)" })"
    foreach ($Row in $R.Rows) { Write-OerLiveStep "  typed $($T): '$($Row.'@odata.type')' $($Row.id); in the untyped read: $($UntypedIds -contains [string]$Row.id)" }
}
$Beta = Read-S91 -Uri "beta/groups/$Gid/members"
Write-OerLiveStep "READ beta members (untyped, for the record): ok $($Beta.Ok); count $($Beta.Rows.Count)$(if (-not $Beta.Ok) { "; $($Beta.Error)" })"
foreach ($Row in $Beta.Rows) { Write-OerLiveStep "  beta: $($Row.'@odata.type') $($Row.id)" }
Disconnect-OerLive
```

**Expect (the record, predicted from the 2026-09-29 measurement and Microsoft Learn's known
issue):** the untyped `v1.0` read lists `oer-s91-nested` only (`#microsoft.graph.group`, count 1); the
typed service principal read lists `oer-live-cc-noperm` (count 1), with `in the untyped read: False`;
the typed group read lists `oer-s91-nested`, `in the untyped read: True`; the user, device and
organizational contact reads list nothing; the `beta` untyped read lists both. Whatever comes back is
the measurement: write it down as it is.
**Failure looks like:** a read that is not `ok` with a 401/403 -- STOP (a missing permission on the
app path, G6/G11); a typed read refused as unsupported (400) is a measurement, not a stop.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: MEASURED (the second run; the first, at 08:08 UTC, measured nothing: the block's id lookups unrolled a one-element read and came back empty -- a defect of this checklist, fixed in f2cee8a, with no effect on the tenant). The untyped v1.0 members read lists 1 object, oer-s91-nested (#microsoft.graph.group), and leaves out the service principal oer-live-cc-noperm. The typed service principal read lists it (count 1), with in the untyped read: False, and WITHOUT an @odata.type annotation (empty). The typed group read lists oer-s91-nested (in the untyped read: True), also without an annotation. The typed user, device and organizational contact reads are accepted (200) and list nothing: the test group has no such member, so whether the untyped read omits those types is not observable here. The beta untyped read lists both, each with its @odata.type.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005; oer-s91-nested is 00000000-0000-0000-0000-000000000006; the service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] READ v1.0 members (untyped): ok True; count 1
[oer-s91]   untyped: #microsoft.graph.group 00000000-0000-0000-0000-000000000006
[oer-s91] READ v1.0 members/microsoft.graph.servicePrincipal: ok True; count 1
[oer-s91]   typed servicePrincipal: '' 00000000-0000-0000-0000-000000000004; in the untyped read: False
[oer-s91] READ v1.0 members/microsoft.graph.user: ok True; count 0
[oer-s91] READ v1.0 members/microsoft.graph.group: ok True; count 1
[oer-s91]   typed group: '' 00000000-0000-0000-0000-000000000006; in the untyped read: True
[oer-s91] READ v1.0 members/microsoft.graph.device: ok True; count 0
[oer-s91] READ v1.0 members/microsoft.graph.orgContact: ok True; count 0
[oer-s91] READ beta members (untyped, for the record): ok True; count 2
[oer-s91]   beta: #microsoft.graph.servicePrincipal 00000000-0000-0000-0000-000000000004
[oer-s91]   beta: #microsoft.graph.group 00000000-0000-0000-0000-000000000006
```

### 1.2. Owners: the untyped read against the typed service principal read

- [x] **1.2** The untyped `owners` read and the typed service principal and user `owners` reads.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
$Untyped = Read-S91 -Uri "v1.0/groups/$Gid/owners"
$UntypedIds = @($Untyped.Rows | ForEach-Object { [string]$_.id })
Write-OerLiveStep "READ v1.0 owners (untyped): ok $($Untyped.Ok); count $($Untyped.Rows.Count)$(if (-not $Untyped.Ok) { "; $($Untyped.Error)" })"
foreach ($Row in $Untyped.Rows) { Write-OerLiveStep "  untyped: $($Row.'@odata.type') $($Row.id)" }
foreach ($T in 'servicePrincipal', 'user') {
    $R = Read-S91 -Uri "v1.0/groups/$Gid/owners/microsoft.graph.$T"
    Write-OerLiveStep "READ v1.0 owners/microsoft.graph.$($T): ok $($R.Ok); count $($R.Rows.Count)$(if (-not $R.Ok) { "; $($R.Error)" })"
    foreach ($Row in $R.Rows) { Write-OerLiveStep "  typed $($T): '$($Row.'@odata.type')' $($Row.id); in the untyped read: $($UntypedIds -contains [string]$Row.id)" }
}
$Beta = Read-S91 -Uri "beta/groups/$Gid/owners"
Write-OerLiveStep "READ beta owners (untyped, for the record): ok $($Beta.Ok); count $($Beta.Rows.Count)$(if (-not $Beta.Ok) { "; $($Beta.Error)" })"
foreach ($Row in $Beta.Rows) { Write-OerLiveStep "  beta: $($Row.'@odata.type') $($Row.id)" }
Disconnect-OerLive
```

**Expect (the record):** the owners half has never been measured here. Microsoft Learn's note on
List group owners says service principals are not listed as group owners in `v1.0`; if that holds,
the untyped read lists nothing, and the typed service principal read lists `oer-live-cc-noperm` with
`in the untyped read: False`. The user read lists nothing (the prerequisite script adds no user owner,
and an app-only create adds no owner of its own). Whatever comes back is the measurement.
**Failure looks like:** a 401/403 -- STOP.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: MEASURED (the second run, as for 1.1). The owners half, measured here for the first time: the untyped v1.0 owners read lists NOTHING (count 0) although oer-live-cc-noperm is an owner; the typed service principal owners read lists it (count 1, in the untyped read: False, no @odata.type annotation); the typed user owners read lists nothing; the beta untyped owners read lists it with its @odata.type. Microsoft Learn's note on List group owners holds on this tenant.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005; the service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] READ v1.0 owners (untyped): ok True; count 0
[oer-s91] READ v1.0 owners/microsoft.graph.servicePrincipal: ok True; count 1
[oer-s91]   typed servicePrincipal: '' 00000000-0000-0000-0000-000000000004; in the untyped read: False
[oer-s91] READ v1.0 owners/microsoft.graph.user: ok True; count 0
[oer-s91] READ beta owners (untyped, for the record): ok True; count 1
[oer-s91]   beta: #microsoft.graph.servicePrincipal 00000000-0000-0000-0000-000000000004
```

### 1.3. The service principal's own side

- [x] **1.3** `servicePrincipals/{id}/memberOf` and `ownedObjects` for `oer-live-cc-noperm` name `oer-s91-grp`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
function Read-S91 {
    param([string]$Uri, [switch]$One)
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($U, $O) if ($O) { Invoke-OERGraphRequest -Uri $U -ErrorAction Stop } else { Invoke-OERGraphRequest -Uri $U -All -ErrorAction Stop } } $Uri $One.IsPresent
        $Rows = @(if ($One) { $R } else { @($R.value) | Where-Object { $null -ne $_ } })
        [PSCustomObject]@{ Ok = $true; Rows = $Rows; Error = '' }
    } catch {
        $E = "$($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $E }
    }
}
$Gid = [string](Read-S91 -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).Rows[0].id
$Sid = [string](Read-S91 -One -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)).Rows[0].id
Write-OerLiveStep "oer-s91-grp is $Gid; the service principal oer-live-cc-noperm is $Sid"
if (-not $Gid -or -not $Sid) { Write-OerLiveStep 'STOP: an id lookup returned nothing, so nothing below would measure anything.'; Disconnect-OerLive; return }
foreach ($Rel in 'memberOf', 'ownedObjects') {
    $R = Read-S91 -Uri "v1.0/servicePrincipals/$Sid/$Rel"
    Write-OerLiveStep "READ v1.0 servicePrincipals/{id}/$($Rel): ok $($R.Ok); count $($R.Rows.Count); names oer-s91-grp: $(@($R.Rows | ForEach-Object { [string]$_.id }) -contains $Gid)$(if (-not $R.Ok) { "; $($R.Error)" })"
}
Disconnect-OerLive
```

**Expect:** both reads `ok`; `memberOf` names `oer-s91-grp: True`, and `ownedObjects` names
`oer-s91-grp: True` -- the links the untyped group reads in 1.1 and 1.2 may leave out exist.
**Failure looks like:** `False` on either -- the link does not exist, so 1.1 and 1.2 measure nothing;
run 0.4 again.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Both reads ok; the service principal's memberOf (count 1) and ownedObjects (count 1) both name oer-s91-grp: the membership and the ownership the untyped reads in 1.1 and 1.2 leave out exist.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005; the service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] READ v1.0 servicePrincipals/{id}/memberOf: ok True; count 1; names oer-s91-grp: True
[oer-s91] READ v1.0 servicePrincipals/{id}/ownedObjects: ok True; count 1; names oer-s91-grp: True
```

### 1.4. The module's own reads before the fix

- [x] **1.4** `Get-OERGroupMember`, `Get-OERGroupMember -Owners`, `Get-OERGroup -IncludeMembers -IncludeOwners` and the export, on the unchanged build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Show = { param($Label, $Rows) Write-OerLiveStep "$($Label): count $(@($Rows).Count); the service principal listed: $(@(@($Rows) | ForEach-Object { [string]$_.PrincipalId }) -contains $Sid)"; foreach ($M in @($Rows)) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" } }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
& $Show 'Get-OERGroupMember' $Members
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
& $Show 'Get-OERGroupMember -Owners' $Owners
$G = Get-OERGroup -Group 'oer-s91-grp' -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E3
Write-OerLiveStep "Get-OERGroup: Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
& $Show 'Get-OERGroup Members' $G.Members
& $Show 'Get-OERGroup Owners' $G.Owners
$Inv = Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s91-')" -ErrorAction SilentlyContinue -ErrorVariable E4 -WarningAction SilentlyContinue
$Entry = @($Inv.groups) | Where-Object { $_.displayName -eq 'oer-s91-grp' }
Write-OerLiveStep "Export oer-s91-grp: members [$(@($Entry.members) -join '; ')]; owners present $($null -ne $Entry.PSObject.Properties['owners']) [$(@($Entry.owners) -join '; ')]; the service principal in members: $(@($Entry.members) -contains $Sid); in owners: $(@($Entry.owners) -contains $Sid)"
foreach ($E in @(@($E1) + @($E2) + @($E3) + @($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect (the defect, before the fix):** `Get-OERGroupMember` lists `oer-s91-nested` only, `the
service principal listed: False`; `-Owners` lists what 1.2's untyped read listed (nothing, if
Microsoft Learn's note holds); `Get-OERGroup` carries both properties with the same content; the
export writes `oer-s91-grp` with `members` holding `oer-s91-nested` and not the service principal,
and no `owners` key if the owner read is empty. No error.
**Failure looks like:** the service principal listed here -- then the unchanged build already sees
it, and the defect does not reproduce on this tenant; write that down as it is.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: THE DEFECT, REPRODUCED on the unchanged build. Get-OERGroupMember lists 1 member (oer-s91-nested, ObjectType group), the service principal listed: False; Get-OERGroupMember -Owners lists 0, the service principal listed: False; Get-OERGroup -IncludeMembers -IncludeOwners carries both properties (the reads succeeded) with the same content: Members 1 without the service principal, Owners 0. The export writes oer-s91-grp with members holding only oer-s91-nested's id and NO owners key at all. No error anywhere: a successful read, so nothing marks the collection as partial.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] Get-OERGroupMember: count 1; the service principal listed: False
[oer-s91]   Member 'oer-s91-nested' ObjectType 'group' 00000000-0000-0000-0000-000000000006
[oer-s91] Get-OERGroupMember -Owners: count 0; the service principal listed: False
[oer-s91] Get-OERGroup: Members present True; Owners present True
[oer-s91] Get-OERGroup Members: count 1; the service principal listed: False
[oer-s91]   Member 'oer-s91-nested' ObjectType 'group' 00000000-0000-0000-0000-000000000006
[oer-s91] Get-OERGroup Owners: count 0; the service principal listed: False
[oer-s91] Export oer-s91-grp: members [00000000-0000-0000-0000-000000000006]; owners present False []; the service principal in members: False; in owners: False
```

### 1.5. What the no-permission identity can read of the group

- [x] **1.5** As `oer-live-cc-noperm`: the group itself, its members (untyped and typed) and its owners -- the input for section 5.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
Connect-OerLive -Arm -NoPerm
foreach ($U in "v1.0/groups/$Gid", "v1.0/groups/$Gid/members", "v1.0/groups/$Gid/members/microsoft.graph.servicePrincipal", "v1.0/groups/$Gid/owners", "v1.0/groups/$Gid/owners/microsoft.graph.servicePrincipal") {
    try {
        $R = & (Get-Module Omnicit.EntraRBAC) { param($X) Invoke-OERGraphRequest -Uri $X -ErrorAction Stop } $U
        Write-OerLiveStep "READ as noperm $($U -replace $Gid, '{id}'): ok; count $(if ($R.PSObject.Properties['value'] -or ($R -is [System.Collections.IDictionary] -and $R.Contains('value'))) { @($R.value).Count } else { 'one object' })"
    } catch {
        Write-OerLiveStep "READ as noperm $($U -replace $Gid, '{id}'): refused -- $($PSItem.FullyQualifiedErrorId) -- $($PSItem.Exception.Message)"
        $global:Error.Clear()
    }
}
Disconnect-OerLive
```

**Expect:** every read refused with `Authorization_RequestDenied` (403), the group read included --
the identity holds no permission, and owning `oer-s91-grp` gives an app-only token no read of it. If
so, `Get-OERGroup -IncludeMembers` as this identity stops at the group read, and section 5 cannot
reach `GroupMemberReadFailed` without answering the group read from a recording (decided there).
**Failure looks like:** a read that succeeds -- write it down: section 5 is then designed on it.

Result: 2026-10-06 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: MEASURED, and not as expected. As oer-live-cc-noperm the group read SUCCEEDS (one object); the untyped members read is refused (Authorization_RequestDenied); the typed service principal members read SUCCEEDS with count 1; the untyped owners read and the typed service principal owners read are both refused. So Get-OERGroup -IncludeMembers as this identity gets past the group read and reaches the member read: section 5 can reach GroupMemberReadFailed and GroupOwnerReadFailed live, with no recording. Why an identity with no permission reads the group and its own typed membership is not established here (it is the group's member and owner); it is recorded, not relied on.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005 (read as oer-live-cc)
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s91] READ as noperm v1.0/groups/{id}: ok; count one object
[oer-s91] READ as noperm v1.0/groups/{id}/members: refused -- Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91] READ as noperm v1.0/groups/{id}/members/microsoft.graph.servicePrincipal: ok; count 1
[oer-s91] READ as noperm v1.0/groups/{id}/owners: refused -- Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91] READ as noperm v1.0/groups/{id}/owners/microsoft.graph.servicePrincipal: refused -- Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
```

### 2. The module's reads after the fix

Sections 2 to 5 run on the build of the fix, built in the step's worktree with `./build.ps1 -Tasks
build` from the branch head named in 2.0.

### 2.0. The module loads from the fix's build in the step's own worktree

- [x] **2.0** The worktree's build carries the fix, and the main clone is still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath); main clone on: $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERGroupRelation' -Quiet)
$Typed = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'microsoft.graph.{2}' -Quiet)
Write-OerLiveStep "The worktree's build ($(Split-Path -Leaf $Psm1.DirectoryName), built $($Psm1.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm 'UTC'", [cultureinfo]::InvariantCulture))) carries the single reader: $Fix; the typed read: $Typed"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`, the main clone on
`main`; the worktree at the branch head with 0 tracked changes; `carries the single reader: True;
the typed read: True`, and a build time after the head commit.
**Failure looks like:** any `False` -- build the worktree first, never while the gate runs.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The session's Repo is the step's worktree, not the main clone; the main clone on main; the worktree at the PR head 9a142e2 with 0 tracked changes; the build (1.1.3, 09:58 UTC, made by the full gate on 9a142e2) carries the single reader and the typed read.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] The module loads from a worktree that is not the main clone: True; main clone on: main
[oer-s91] Worktree: branch fix/read-service-principal-group-members; HEAD 9a142e2 test: hold the member reader's callers to a try; tracked changes: 0
[oer-s91] The worktree's build (1.1.3, built 2026-10-06 09:58 UTC) carries the single reader: True; the typed read: True
```

### 2.1. Get-OERGroupMember: the service principal is a member and an owner

- [x] **2.1** `Get-OERGroupMember -Group oer-s91-grp` lists the service principal with `ObjectType` `servicePrincipal`, and so does `-Owners`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Show = { param($Label, $Rows) Write-OerLiveStep "$($Label): count $(@($Rows).Count); the service principal listed: $(@(@($Rows) | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s)"; foreach ($M in @($Rows)) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" } }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
& $Show 'Get-OERGroupMember' $Members
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
& $Show 'Get-OERGroupMember -Owners' $Owners
foreach ($E in @(@($E1) + @($E2) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** `Get-OERGroupMember: count 2; the service principal listed: 1 time(s)`, `oer-s91-nested`
with `ObjectType 'group'` and `oer-live-cc-noperm` with `ObjectType 'servicePrincipal'`;
`Get-OERGroupMember -Owners: count 1; the service principal listed: 1 time(s)`, `Owner` with
`ObjectType 'servicePrincipal'`. No error. Before the fix (1.4) the counts were 1 and 0.
**Failure looks like:** the service principal missing, listed twice, or with an empty `ObjectType`.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Get-OERGroupMember lists 2 members, oer-s91-nested (ObjectType group) and oer-live-cc-noperm (ObjectType servicePrincipal), the service principal once; -Owners lists 1 owner, the service principal (Owner, ObjectType servicePrincipal). No error. Before the fix (1.4): 1 member and 0 owners, the service principal in neither.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] Get-OERGroupMember: count 2; the service principal listed: 1 time(s)
[oer-s91]   Member 'oer-s91-nested' ObjectType 'group' 00000000-0000-0000-0000-000000000006
[oer-s91]   Member 'oer-live-cc-noperm' ObjectType 'servicePrincipal' 00000000-0000-0000-0000-000000000004
[oer-s91] Get-OERGroupMember -Owners: count 1; the service principal listed: 1 time(s)
[oer-s91]   Owner 'oer-live-cc-noperm' ObjectType 'servicePrincipal' 00000000-0000-0000-0000-000000000004
```

### 2.2. Get-OERGroup -IncludeMembers -IncludeOwners

- [x] **2.2** `Get-OERGroup` carries the service principal in `Members` and in `Owners`, with `ObjectType` `servicePrincipal`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$G = Get-OERGroup -Group 'oer-s91-grp' -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E3
Write-OerLiveStep "Get-OERGroup: Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
foreach ($P in 'Members', 'Owners') {
    $Rows = @($G.$P)
    Write-OerLiveStep "Get-OERGroup $($P): count $($Rows.Count); the service principal listed: $(@($Rows | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s)"
    foreach ($M in $Rows) { Write-OerLiveStep "  $($M.MemberType) '$($M.DisplayName)' ObjectType '$($M.ObjectType)' $($M.PrincipalId)" }
}
foreach ($E in @(@($E3) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** both properties present; `Members: count 2`, the service principal listed `1 time(s)`
with `ObjectType 'servicePrincipal'`; `Owners: count 1`, the same. No error.
**Failure looks like:** as in 2.1.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Get-OERGroup carries both properties: Members 2 (the service principal once, ObjectType servicePrincipal), Owners 1 (the service principal, ObjectType servicePrincipal). No error. Before the fix (1.4): Members 1, Owners 0.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] Get-OERGroup: Members present True; Owners present True
[oer-s91] Get-OERGroup Members: count 2; the service principal listed: 1 time(s)
[oer-s91]   Member 'oer-s91-nested' ObjectType 'group' 00000000-0000-0000-0000-000000000006
[oer-s91]   Member 'oer-live-cc-noperm' ObjectType 'servicePrincipal' 00000000-0000-0000-0000-000000000004
[oer-s91] Get-OERGroup Owners: count 1; the service principal listed: 1 time(s)
[oer-s91]   Owner 'oer-live-cc-noperm' ObjectType 'servicePrincipal' 00000000-0000-0000-0000-000000000004
```

### 3. The export

### 3.1. Get-OERInventory: the service principal's id in members and owners

- [x] **3.1** The export of the `oer-s91-` groups writes the service principal's id in `oer-s91-grp`'s `members` and `owners`, and reports nothing unread.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Inv = Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s91-')" -ErrorAction SilentlyContinue -ErrorVariable E4 -WarningAction SilentlyContinue
$Entry = @($Inv.groups) | Where-Object { $_.displayName -eq 'oer-s91-grp' }
Write-OerLiveStep "Export oer-s91-grp: members [$(@($Entry.members) -join '; ')]; owners present $($null -ne $Entry.PSObject.Properties['owners']) [$(@($Entry.owners) -join '; ')]"
Write-OerLiveStep "The service principal in members: $(@(@($Entry.members) | Where-Object { $_ -eq $Sid }).Count) time(s); in owners: $(@(@($Entry.owners) | Where-Object { $_ -eq $Sid }).Count) time(s)"
$Partial = @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial records: $($Partial.Count)"
foreach ($E in @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = $Inv | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$Doc.groups = @($Doc.groups | Where-Object { $_.displayName -eq 'oer-s91-grp' })
$null = New-Item -ItemType Directory -Force -Path $Raw
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The apply document for 3.2 and 4 (oer-s91-grp only, cut from this export, version $($Doc.version)) is raw\s91\doc-s91-grp.json"
Disconnect-OerLive
```

**Expect:** `members` holds the ids of `oer-s91-nested` and the service principal; `owners` is
present and holds the service principal's id; the service principal `1 time(s)` in each;
`InventoryPartial records: 0`; no error. Before the fix (1.4) the export had no service principal and
no `owners` key at all.
**Failure looks like:** the service principal missing, or an `InventoryPartial` naming
`groups/oer-s91-grp/members` or `/owners` -- a read the fix made unread.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. The export writes oer-s91-grp with members holding oer-s91-nested's and the service principal's ids and an owners key holding the service principal's id, the service principal once in each; InventoryPartial records 0; no error. Before the fix (1.4): no service principal and no owners key at all. The apply document for 3.2 and 4 was cut from this export (version 1.0, oer-s91-grp only).

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The service principal oer-live-cc-noperm is 00000000-0000-0000-0000-000000000004
[oer-s91] Export oer-s91-grp: members [00000000-0000-0000-0000-000000000006; 00000000-0000-0000-0000-000000000004]; owners present True [00000000-0000-0000-0000-000000000004]
[oer-s91] The service principal in members: 1 time(s); in owners: 1 time(s)
[oer-s91] InventoryPartial records: 0
[oer-s91] The apply document for 3.2 and 4 (oer-s91-grp only, cut from this export, version 1.0) is raw\s91\doc-s91-grp.json
```

### 3.2. The export's entry applied with -Prune -WhatIf, twice: only Unchanged

- [x] **3.2** `Invoke-OERStructure -Prune -WhatIf` of `oer-s91-grp`'s exported entry plans no change and no removal, two runs in a row (G8), behind a read-only fence.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run): rows $($Rows.Count) [$ByAction]; warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
    foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** each run: only `Unchanged` rows (among them `member '...' already present` for both
members and `owner '...' already present` for the service principal), no `Extra`, no `Skipped`
`would remove`, no `Failed`, no prune warning; the fence refused `0`. Before the fix a declared
service principal could never be `already present`: the engine did not see it.
**Failure looks like:** a planned removal or an `Updated` row -- the export and the engine disagree
about the group; `refused` above 0.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, two runs (G8). Each: 4 rows, all Unchanged (group properties match; both members and the service principal owner already present), no warning, no error; the read-only fence saw 14 requests, 0 not a GET, refused 0.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] Run 1: rows 4 [Unchanged 4]; warnings 0; errors 0
[oer-s91]   Unchanged oer-s91-grp: group properties match
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000006' already present
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000004' already present
[oer-s91]   Unchanged oer-s91-grp: owner '00000000-0000-0000-0000-000000000004' already present
[oer-s91] Run 2: rows 4 [Unchanged 4]; warnings 0; errors 0
[oer-s91]   Unchanged oer-s91-grp: group properties match
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000006' already present
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000004' already present
[oer-s91]   Unchanged oer-s91-grp: owner '00000000-0000-0000-0000-000000000004' already present
[oer-s91] Fence: requests 14, not a GET 0, refused 0
```

### 4. Apply with -Prune for real, oer-s91- only

### 4.1. The document declaring both members and the owner: Unchanged and 0 Removed, twice

- [x] **4.1** `Invoke-OERStructure -Prune` for real (no `-WhatIf`) on the `oer-s91-grp` document gives only `Unchanged` and removes nothing, two runs in a row (G8).

The read-only fence stays in front of the module's Graph transport for this real run as well: the
run makes no `-WhatIf` plan, so every gate is passed for real, but a write -- which a correct run
does not attempt -- is refused and shows as `Failed` instead of reaching the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
$Doc = Get-Content -LiteralPath $DocPath -Raw | ConvertFrom-Json
Write-OerLiveStep "The document: groups $(@($Doc.groups).Count) ($(@($Doc.groups.displayName) -join ', ')); members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run) (real, -Prune): rows $($Rows.Count) [$ByAction]; Removed $(@($Rows | Where-Object Action -eq 'Removed').Count); warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** the document holds one group, `oer-s91-grp`, with both members and the service
principal as owner; each run: only `Unchanged` rows, `Removed 0`, no warning, no error; the fence
refused `0`.
**Failure looks like:** a `Removed`, `Updated` or `Failed` row, or `refused` above 0 -- STOP and read
it; never run 4.1 without the fence.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, two real runs with -Prune (no -WhatIf, -Confirm:false), behind the read-only fence (G8). The document holds only oer-s91-grp, with both members and the service principal as owner. Each run: 4 rows, all Unchanged, Removed 0, no warning, no error; fence 14 requests, 0 not a GET, refused 0 -- nothing was written to the tenant, and nothing was attempted.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The document: groups 1 (oer-s91-grp); members [00000000-0000-0000-0000-000000000006; 00000000-0000-0000-0000-000000000004]; owners [00000000-0000-0000-0000-000000000004]
[oer-s91] Run 1 (real, -Prune): rows 4 [Unchanged 4]; Removed 0; warnings 0; errors 0
[oer-s91]   Unchanged oer-s91-grp: group properties match
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000006' already present
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000004' already present
[oer-s91]   Unchanged oer-s91-grp: owner '00000000-0000-0000-0000-000000000004' already present
[oer-s91] Run 2 (real, -Prune): rows 4 [Unchanged 4]; Removed 0; warnings 0; errors 0
[oer-s91]   Unchanged oer-s91-grp: group properties match
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000006' already present
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000004' already present
[oer-s91]   Unchanged oer-s91-grp: owner '00000000-0000-0000-0000-000000000004' already present
[oer-s91] Fence: requests 14, not a GET 0, refused 0
```

### R1. Round 1 (A9): the objects again, on the build that withholds the prune

Round 1 runs after review decision A9: the group prune never removes a service principal. These
checks set the objects up again on the build of the commit `fix: never prune a service principal
from a group`, and cut a new apply document from a new export; 4.2 then runs again with A9's
expectation, 4.3 and 4.4 are new, and R1.T1 to R1.T3 tear down. S.1 to 4.1 and section 5 keep their
round 0 results: A9 changes no read, and 3.2 and 4.1 declare the service principal.

### R1.0. The module loads from the build with the A9 guard, in the round's own worktree

- [ ] **R1.0** The worktree's build carries the single reader and the A9 guard, and the main clone is still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath); main clone on: $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERGroupRelation' -Quiet)
$A9 = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '-Prune never removes a service principal from a group' -Quiet)
Write-OerLiveStep "The worktree's build ($(Split-Path -Leaf $Psm1.DirectoryName), built $($Psm1.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm 'UTC'", [cultureinfo]::InvariantCulture))) carries the single reader: $Fix; the A9 guard: $A9"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`, the main clone on
`main`; the round's worktree on its own local branch at the head that carries the A9 commit, with 0
tracked changes; `carries the single reader: True; the A9 guard: True`, and a build time after that
commit.
**Failure looks like:** any `False` -- build the worktree first, never while the gate runs.

Result:

### R1.S. The redaction map continues this file's numbering

- [ ] **R1.S** Before anything is printed in round 1, the step's redaction map gives the service principal the placeholder it has in round 0 (`...04`) and numbers every new id from `...07` on.

Round 0's map was deleted after its write-up, so a new one would start again at `...01`: the service
principal would get a second placeholder in this file, and new objects would get numbers round 0
already used. This block writes the map before the first id of round 1 is printed. It reads the
service principal's id and writes it only to the map file in the user's temp folder, which OerLive
keeps outside the clone and the vault; nothing in the block prints an id.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$MapFile = Join-Path ([System.IO.Path]::GetTempPath()) 'OerLive\s91\redaction-map.json'
$Before = Test-Path -LiteralPath $MapFile
Connect-OerLive -Graph
$R = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id,displayName" -f $Cfg.NoPermAppId)
Assert-OerLiveOk -Response $R -Activity 'Reading the service principal of oer-live-cc-noperm' | Out-Null
$Named = [string]$R.Body['displayName'] -ceq 'oer-live-cc-noperm'
Disconnect-OerLive
if ($Before) { throw 'Refusing to write: a redaction map for s91 exists already; read it before replacing it.' }
if (-not $Named) { throw 'Refusing to write: the service principal of the noperm app id is not named oer-live-cc-noperm.' }
$Map = [ordered]@{ guids = @{ ([string]$R.Body['id']).ToLowerInvariant() = 4 }; emails = @{}; nextGuid = 7; nextEmail = 1 }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $MapFile)
[System.IO.File]::WriteAllText($MapFile, (ConvertTo-Json -InputObject $Map -Depth 5), [System.Text.UTF8Encoding]::new($false))
$Check = Get-Content -LiteralPath $MapFile -Raw | ConvertFrom-Json -AsHashtable
Write-OerLiveStep "A map existed before this block: $Before; the service principal is named oer-live-cc-noperm: $Named; the map holds $($Check['guids'].Count) id(s), the service principal at number $(@($Check['guids'].Values)[0]); the next new id gets number $($Check['nextGuid'])"
```

**Expect:** `A map existed before this block: False`, the identity check passed, `named
oer-live-cc-noperm: True`, `the map holds 1 id(s), the service principal at number 4; the next new id gets number 7`. The
first block that prints the service principal's id (R1.3) shows it as `...04`.
**Failure looks like:** a refusal line -- read the map that exists before replacing it; the service
principal printed as anything but `...04` in R1.3 -- stop and renumber before writing any result.

Result:

### R1.1. The prerequisite script's plan, round 1

- [ ] **R1.1** `-WhatIf` plans only `oer-s91-` targets in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** as 0.3: the identity check passes; the noperm service principal named
`oer-live-cc-noperm: True`; the sweep reads all six collections and finds no `oer-s91-` object (round
0's teardown removed them); no baseline yet, since round 0's `raw\s91\` was deleted, so it is planned
before the first write; five tenant targets, the two groups and the three links, every one starting
with `oer-s91-`; nothing written; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line or a sweep line
`UNREAD` -- STOP.

Result:

### R1.2. The prerequisite script for real, round 1

- [ ] **R1.2** The test objects exist again: the two groups, the group and the service principal as members, the service principal as owner.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** as 0.4: the baseline written and read back before the first write; both groups created
and resolvable; the three links added and listed from the other side; both groups `present`; exit
code `0`.
**Failure looks like:** a stop line, or an exit code other than 0: run R1.2 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### R1.3. The export of round 1, and the apply document for 4.2 to 4.4

- [ ] **R1.3** The export of the `oer-s91-` groups writes the service principal's id in `oer-s91-grp`'s `members` and `owners`, reports nothing unread, and gives the apply document.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "The service principal oer-live-cc-noperm is $Sid"
$Inv = Get-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s91-')" -ErrorAction SilentlyContinue -ErrorVariable E4 -WarningAction SilentlyContinue
$Entry = @($Inv.groups) | Where-Object { $_.displayName -eq 'oer-s91-grp' }
Write-OerLiveStep "Export oer-s91-grp: members [$(@($Entry.members) -join '; ')]; owners present $($null -ne $Entry.PSObject.Properties['owners']) [$(@($Entry.owners) -join '; ')]"
Write-OerLiveStep "The service principal in members: $(@(@($Entry.members) | Where-Object { $_ -eq $Sid }).Count) time(s); in owners: $(@(@($Entry.owners) | Where-Object { $_ -eq $Sid }).Count) time(s)"
$Partial = @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial records: $($Partial.Count)"
foreach ($E in @(@($E4) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = $Inv | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$Doc.groups = @($Doc.groups | Where-Object { $_.displayName -eq 'oer-s91-grp' })
$null = New-Item -ItemType Directory -Force -Path $Raw
$DocPath = Join-Path $Raw 'doc-s91-grp.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The apply document for 4.2 to 4.4 (oer-s91-grp only, cut from this export, version $($Doc.version)) is raw\s91\doc-s91-grp.json"
Disconnect-OerLive
```

**Expect:** the service principal is `00000000-0000-0000-0000-000000000004`, as in round 0 (R1.S);
`members` holds the ids of the new `oer-s91-nested` and the service principal, `owners` holds the
service principal's id, once each; `InventoryPartial records: 0`; no error. The new groups carry
numbers from `...07` on.
**Failure looks like:** the service principal printed as anything but `...04` -- stop before writing
any result (R1.S); otherwise as 3.1.

Result:

### 4.2. The same document without the service principal, -Prune -WhatIf: the prune is withheld

- [ ] **4.2** With the service principal taken out of `members` and `owners`, `-Prune -WhatIf` withholds its prune as a member and as an owner (A9): `Skipped` with the reason, no planned removal, no warning. No write. (Round 1; round 0 planned its removal as a member.)

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-s91-grp.json') -Raw | ConvertFrom-Json
$Doc.groups[0].members = @(@($Doc.groups[0].members) | Where-Object { $_ -ne $Sid })
$Doc.groups[0].owners = @(@($Doc.groups[0].owners) | Where-Object { $_ -ne $Sid })
$DocPath = Join-Path $Raw 'doc-s91-grp-without-sp.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The document without $($Sid): members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
$Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
$ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
Write-OerLiveStep "Plan: rows $($Rows.Count) [$ByAction]; warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `members` without the service principal and `owners` empty; the plan: `Unchanged` for
the group's properties and for `oer-s91-nested`; for the service principal (`...04`), as a member AND
as an owner, a `Skipped` row starting `prune withheld: undeclared member '...' is a service
principal` and `prune withheld: undeclared owner '...' is a service principal` -- not `would remove`,
and not the last-owner guard's `did not remove owner` either, since A9 is asked first; no warning;
no `What if:` line; no `Removed`, no `Failed`; the fence refused `0`. Round 0 planned the member's
removal here, which is the outcome A9 decided against.
**Failure looks like:** a `would remove` row or a prune warning naming the service principal -- the
build does not carry A9; a `Removed` row -- `-WhatIf` did not hold (the fence would refuse it).

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. With the service principal taken out of members and owners, the -Prune -WhatIf plan: Unchanged for the group's properties and for oer-s91-nested; Skipped 'would remove undeclared member' naming the service principal, with the prune warning; for the owner, Skipped 'did not remove owner ...: it is the last remaining owner' (the engine's own guard). No Removed, no Failed; fence 8 requests, 0 not a GET, refused 0. The engine sees the service principal now; before the fix it could not.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] The document without 00000000-0000-0000-0000-000000000004: members [00000000-0000-0000-0000-000000000006]; owners []
What if: Performing the operation "Remove undeclared member '00000000-0000-0000-0000-000000000004'" on target "oer-s91-grp".
[oer-s91] Plan: rows 4 [Skipped 2, Unchanged 2]; warnings 1; errors 0
[oer-s91]   Unchanged oer-s91-grp: group properties match
[oer-s91]   Unchanged oer-s91-grp: member '00000000-0000-0000-0000-000000000006' already present
[oer-s91]   Skipped oer-s91-grp: would remove undeclared member '00000000-0000-0000-0000-000000000004'
[oer-s91]   Skipped oer-s91-grp: did not remove owner '00000000-0000-0000-0000-000000000004': it is the last remaining owner of group 'oer-s91-grp', and this pass refuses to remove it (this is our own guard, not a Graph rejection). Microsoft Graph's documented restriction names a USER owner specifically, so if this is a service principal it may in fact be removable; this guard is deliberately conservative pending live verification.
[oer-s91]   Warning: Sync-OERStructureGroup: would remove undeclared member '00000000-0000-0000-0000-000000000004' from group 'oer-s91-grp'.
[oer-s91] Fence: requests 8, not a GET 0, refused 0
```

### 4.3. The same document, -Prune for real, twice: the service principal stays

- [ ] **4.3** With the service principal still taken out of `members` and `owners`, `Invoke-OERStructure -Prune -Confirm:$false` for real removes nothing and reports the service principal `Skipped` as member and as owner, two runs in a row (G8); the read-back still lists it as a member and an owner.

The read-only fence stays in front of the module's Graph transport: under A9 a correct run attempts
no write, and a write it did attempt -- a removal of the service principal -- is refused and shows
as `Failed` instead of reaching the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S91 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S91Transport @PSBoundParameters
    }
}
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
$DocPath = Join-Path $Raw 'doc-s91-grp-without-sp.json'
$Doc = Get-Content -LiteralPath $DocPath -Raw | ConvertFrom-Json
Write-OerLiveStep "The document (4.2's, without $($Sid)): members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run) (real, -Prune): rows $($Rows.Count) [$ByAction]; Removed $(@($Rows | Where-Object Action -eq 'Removed').Count); warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
    foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; NotGet = @($script:S91Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
foreach ($F in $Fence.Refused) { Write-OerLiveStep "  Refused: $F" }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
Write-OerLiveStep "Read-back: members $($Members.Count), the service principal listed $(@($Members | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s); owners $($Owners.Count), the service principal listed $(@($Owners | Where-Object { [string]$_.PrincipalId -eq $Sid }).Count) time(s)"
foreach ($E in @(@($E1) + @($E2) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** each run: 4 rows -- `Unchanged` for the group's properties and for `oer-s91-nested`, and
`Skipped` with `prune withheld: undeclared member '...' is a service principal` and `prune withheld:
undeclared owner '...' is a service principal` for the service principal (`...04`); `Removed 0`; no
warning; no error; the fence: not a GET `0`, refused `0` -- nothing was attempted. The read-back:
members `2`, the service principal listed `1 time(s)`; owners `1`, the service principal listed `1
time(s)`.
**Failure looks like:** a `Removed` row, a `Failed` row or `refused` above 0 -- the guard did not hold,
and the fence kept the service principal; STOP and read it.

Result:

### 4.4. A document that also leaves out oer-s91-nested, -Prune for real, twice: only the group member goes

- [ ] **4.4** With `oer-s91-nested` taken out of `members` too, the real `-Prune` removes `oer-s91-nested` as a member and leaves the service principal as member and owner; a second run removes nothing (G8).

This shows that the guard is about service principals only: in the same run, a member of another
type is pruned as before. A fence stays in front of the transport and lets exactly one write
through, the removal of `oer-s91-nested`'s membership of `oer-s91-grp`; any other write, a removal
of the service principal included, is refused and shows as `Failed`. Between the two runs the block
waits until the members read no longer lists `oer-s91-nested`, so the second run does not meet the
removal's replication.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](Get-OERGroup -Group 'oer-s91-grp' -ErrorAction Stop).Id
$Nid = [string](Get-OERGroup -Group 'oer-s91-nested' -ErrorAction Stop).Id
$Sid = [string](& (Get-Module Omnicit.EntraRBAC) { param($A) Invoke-OERGraphRequest -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $A) } $Cfg.NoPermAppId).id
Write-OerLiveStep "oer-s91-grp is $Gid; oer-s91-nested is $Nid; the service principal oer-live-cc-noperm is $Sid"
& (Get-Module Omnicit.EntraRBAC) {
    param($Allowed)
    $script:S91Allowed = $Allowed
    $script:S91Seen = [System.Collections.Generic.List[string]]::new()
    $script:S91Refused = [System.Collections.Generic.List[string]]::new()
    $script:S91Passed = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S91Transport) { $script:S91Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S91Seen.Add("$($Method.ToUpperInvariant()) $Path")
        $Read = $Method -eq 'GET' -or $Path -match '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$'
        if (-not $Read) {
            if ($Method -eq 'DELETE' -and $Path -eq $script:S91Allowed) { $script:S91Passed.Add("DELETE $Path") }
            else {
                $script:S91Refused.Add("$($Method.ToUpperInvariant()) $Path")
                throw "S91 fence: refused $($Method.ToUpperInvariant()) $Path"
            }
        }
        & $script:S91Transport @PSBoundParameters
    }
} ("v1.0/groups/{0}/members/{1}/`$ref" -f $Gid, $Nid)
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-s91-grp-without-sp.json') -Raw | ConvertFrom-Json
$Doc.groups[0].members = @(@($Doc.groups[0].members) | Where-Object { $_ -ne $Nid })
$DocPath = Join-Path $Raw 'doc-s91-grp-without-sp-and-nested.json'
[System.IO.File]::WriteAllText($DocPath, ($Doc | ConvertTo-Json -Depth 50), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The document without $Sid and without $($Nid): members [$(@($Doc.groups[0].members) -join '; ')]; owners [$(@($Doc.groups[0].owners) -join '; ')]"
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Path $DocPath -Include Groups -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
    $ByAction = ($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-OerLiveStep "Run $($Run) (real, -Prune): rows $($Rows.Count) [$ByAction]; Removed $(@($Rows | Where-Object Action -eq 'Removed').Count); warnings $(@($ApplyWarn).Count); errors $(@($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
    foreach ($R in $Rows) { Write-OerLiveStep "  $($R.Action) $($R.Item): $($R.Detail)" }
    foreach ($W in @($ApplyWarn)) { Write-OerLiveStep "  Warning: $W" }
    foreach ($E in @($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "  Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
    if ($Run -eq 1) {
        $null = Wait-OerLiveConverged -Activity 'oer-s91-nested is no longer listed as a member of oer-s91-grp' -Read {
            , @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction Stop | ForEach-Object { [string]$_.PrincipalId })
        } -Test { @($args[0]) -notcontains $Nid }
    }
}
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S91Seen.Count; Passed = @($script:S91Passed); Refused = @($script:S91Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), writes let through $($Fence.Passed.Count), refused $($Fence.Refused.Count)"
foreach ($F in $Fence.Passed) { Write-OerLiveStep "  Let through: $F" }
foreach ($F in $Fence.Refused) { Write-OerLiveStep "  Refused: $F" }
$Members = @(Get-OERGroupMember -Group 'oer-s91-grp' -ErrorAction SilentlyContinue -ErrorVariable E1)
$Owners = @(Get-OERGroupMember -Group 'oer-s91-grp' -Owners -ErrorAction SilentlyContinue -ErrorVariable E2)
Write-OerLiveStep "Read-back: members $($Members.Count) [$((@($Members) | ForEach-Object { "$($_.ObjectType) $($_.PrincipalId)" }) -join '; ')]; owners $($Owners.Count) [$((@($Owners) | ForEach-Object { "$($_.ObjectType) $($_.PrincipalId)" }) -join '; ')]"
foreach ($E in @(@($E1) + @($E2) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** the document's `members` and `owners` both empty. Run 1: `Unchanged` for the group's
properties; `Removed` `removed undeclared member '...'` for `oer-s91-nested`, with the warning
`removing undeclared member '...'` naming it and no other; `Skipped` `prune withheld: undeclared
member '...' is a service principal` and `prune withheld: undeclared owner '...' is a service
principal` for the service principal (`...04`); `Removed 1`; no error. The wait converges. Run 2: 3
rows -- `Unchanged` for the properties and the two `Skipped` rows for the service principal --
`Removed 0`, no warning, no error. The fence let exactly 1 write through, the removal of
`oer-s91-nested`'s membership, and refused 0. The read-back: members `1`, the service principal
(`servicePrincipal`); owners `1`, the service principal.
**Failure looks like:** the service principal in a `Removed` row or a refused write -- the guard did
not hold, and the fence kept it: STOP and read it; `oer-s91-nested` not removed -- the prune of other
types is broken; a `Failed` row in run 2 -- the removal had not replicated.

Result:

### 5. The 403 checks, as oer-live-cc-noperm

1.5 measured that this identity reads `oer-s91-grp` itself, while the untyped member read and both
owner reads are refused (403). The two cmdlets therefore reach their member and owner reads live,
with no recording.

### 5.1. Get-OERGroupMember: the error and nothing else

- [x] **5.1** As `oer-live-cc-noperm`, `Get-OERGroupMember -Group` (by id) and `-Owners` each write the refusal as itself and return nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
if (-not $Gid) { Write-OerLiveStep 'STOP: the id lookup returned nothing.'; Disconnect-OerLive; return }
Connect-OerLive -Arm -NoPerm
foreach ($Owners in $false, $true) {
    $Label = if ($Owners) { 'Get-OERGroupMember -Owners' } else { 'Get-OERGroupMember' }
    $Out = @(Get-OERGroupMember -Group $Gid -Owners:$Owners -ErrorAction SilentlyContinue -ErrorVariable E5)
    $Recs = @(@($E5) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    Write-OerLiveStep "$($Label): output $($Out.Count); error records $($Recs.Count)"
    foreach ($E in $Recs) { Write-OerLiveStep "  Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
Disconnect-OerLive
```

**Expect:** for both: `output 0`, and an error record whose id starts with
`Authorization_RequestDenied` (the refusal as itself, never `GroupNotFound`); nothing else written.
**Failure looks like:** any output -- a partial list from a collection that was not read whole.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS on what the check is for. As oer-live-cc-noperm, Get-OERGroupMember (by id) and -Owners each emit nothing (output 0) and publish the refusal as itself, Authorization_RequestDenied,Get-OERGroupMember -- never GroupNotFound, never a partial list. The Expect line's 'nothing else written' was imprecise: -ErrorVariable also collects 11 records raised inside the nested transport calls (the engine re-deposits them; rationale #writeerror-deposit, and the comment in Get-OERGroup on -ErrorVariable). The cmdlet published exactly one; this step changed neither the transport nor that collection.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005 (read as oer-live-cc)
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s91] Get-OERGroupMember: output 0; error records 12
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied,Get-OERGroupMember -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91] Get-OERGroupMember -Owners: output 0; error records 12
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied,Get-OERGroupMember -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
```

### 5.2. Get-OERGroup -IncludeMembers -IncludeOwners: no Members, no Owners, both errors

- [x] **5.2** As `oer-live-cc-noperm`, `Get-OERGroup` returns the group without `Members` and `Owners`, and writes `GroupMemberReadFailed` and `GroupOwnerReadFailed`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Gid = [string](@((& (Get-Module Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U } ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s91-grp'"))).value)[0].id)
Write-OerLiveStep "oer-s91-grp is $Gid (read as oer-live-cc)"
if (-not $Gid) { Write-OerLiveStep 'STOP: the id lookup returned nothing.'; Disconnect-OerLive; return }
Connect-OerLive -Arm -NoPerm
$G = Get-OERGroup -Group $Gid -IncludeMembers -IncludeOwners -ErrorAction SilentlyContinue -ErrorVariable E6
Write-OerLiveStep "Get-OERGroup: object $($null -ne $G) (id $($G.Id)); Members present $($null -ne $G.PSObject.Properties['Members']); Owners present $($null -ne $G.PSObject.Properties['Owners'])"
$Recs = @(@($E6) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
foreach ($Id in 'GroupMemberReadFailed', 'GroupOwnerReadFailed') { Write-OerLiveStep "$($Id): $(@($Recs | Where-Object { $_.FullyQualifiedErrorId -like "$Id*" }).Count)" }
foreach ($E in $Recs) { Write-OerLiveStep "  Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** the group object (its id), `Members present False`, `Owners present False`;
`GroupMemberReadFailed: 1` and `GroupOwnerReadFailed: 1`, each message naming the refusal
(`Authorization_RequestDenied`) and saying the property is omitted rather than reported as empty.
**Failure looks like:** a `Members` or `Owners` property (an unread collection presented as a fact),
or no group object at all -- then the group read itself was refused, unlike 1.5.

Result: 2026-10-06 10:18 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. As oer-live-cc-noperm, Get-OERGroup returns the group object (its id), Members present False, Owners present False; GroupMemberReadFailed 1 and GroupOwnerReadFailed 1, each naming Authorization_RequestDenied and saying the property is omitted rather than reported as empty. Reached live with no recording, as 1.5 measured (the group read succeeds for this identity). The other records in -ErrorVariable are the nested ones described under 5.1.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s91] oer-s91-grp is 00000000-0000-0000-0000-000000000005 (read as oer-live-cc)
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s91] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s91] Get-OERGroup: object True (id 00000000-0000-0000-0000-000000000005); Members present False; Owners present False
[oer-s91] GroupMemberReadFailed: 1
[oer-s91] GroupOwnerReadFailed: 1
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: GroupMemberReadFailed,Get-OERGroup -- Could not read members for group 00000000-0000-0000-0000-000000000005: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The Members property is omitted rather than reported as empty.
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: Forbidden (Forbidden).
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: Authorization_RequestDenied -- Authorization_RequestDenied: Insufficient privileges to complete the operation.
[oer-s91]   Error: GroupOwnerReadFailed,Get-OERGroup -- Could not read owners for group 00000000-0000-0000-0000-000000000005: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The Owners property is omitted rather than reported as empty.
```

## Teardown

### T.1. The teardown's plan

- [x] **T.1** `-Teardown -WhatIf` plans only the two `oer-s91-` groups.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the sweep finds `oer-s91-grp` and `oer-s91-nested` and nothing else; the teardown's six
steps, with only step 5 planning anything: `Delete the group` for the two groups (they are not
role-assignable, so step 4 removes no member); two tenant targets, both with the prefix; nothing
removed; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result: 2026-10-06 10:19 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS, with one deviation from the Expect line. The sweep finds the two groups and nothing else; 6 What-if targets, 1 local (the transcript) and 5 in the tenant, every one starting with oer-s91-. Not foreseen: step 2 (PIM for Groups) reads oer-s91-grp's assignment schedules and lists the three links the prerequisite script created -- the owner link and the two member links, which Graph models as Direct assignments -- and plans an adminRemove for each, before step 5 deletes both groups. They are the step's own links in its own prefixed group; the service principal itself is not a target. Nothing removed; exit code 0.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s91\teardown-20261006-101859Z.log".
[oer-s91] Mode: REMOVE. Prefix 'oer-s91-'. Objects (fixed): oer-s91-grp; oer-s91-nested, a member of it; oer-live-cc-noperm (service principal, never changed itself) a member and an owner of oer-s91-grp. OerLive 1.0.2.
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s91] Residue: raw\residue.json holds no rows.
[oer-s91] Teardown of 'oer-s91-': users 0, groups 2, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s91] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s91] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
What if: Performing the operation "Remove (Graph beta schedule request, adminRemove)" on target "oer-s91-grp: PIM for Groups owner assignment of a principal".
What if: Performing the operation "Remove (Graph beta schedule request, adminRemove)" on target "oer-s91-grp: PIM for Groups member assignment of a principal".
What if: Performing the operation "Remove (Graph beta schedule request, adminRemove)" on target "oer-s91-grp: PIM for Groups member assignment of a principal".
[oer-s91] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s91] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s91] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s91-grp".
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s91-nested".
[oer-s91] Teardown 6/6: the prefixed users.
[oer-s91] Teardown of 'oer-s91-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s91] WhatIf: nothing was created, removed or written.
[oer-s91] Done.
[oer-s91] What-if targets: 6; in the tenant: 5; every tenant target starts with oer-s91-: True; exit code: 0
```

### T.2. The teardown

- [x] **T.2** Both groups deleted; the service principal is back at its baseline (a member of no `oer-s91-` group, owner of nothing it did not own before).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** `Deleted: group oer-s91-grp (204)` and `Deleted: group oer-s91-nested (204)`; `removed 2,
residue 0`; the sweep afterwards may still list a group deleted seconds ago (replication), and T.3
reads it again; `groups now 97, at the baseline 97; equal: True` (or the count of the moment, if
another run changed the tenant's groups -- then say so); `oer-live-cc-noperm memberOf: now 0, at the
baseline 0; the same objects: True` and the same for `ownedObjects`; exit code `0`.
**Failure looks like:** a residue line or exit code `3` -- the row stays in `raw\residue.json` and the
next prereq run retries it; a `False` on the service principal's lines after T.3's read-back -- STOP
(G11.5).

Result: 2026-10-06 10:23 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS after T.3's read-back. The teardown removed 5, residue 0, exit code 0: in step 2 the three links (the owner link and the two member links, read as Direct PIM for Groups assignments) by adminRemove (201 each), in step 5 both groups (204 each). The sweep and the comparison run seconds later still saw the deleted groups (groups 99 against 97, the service principal's memberOf 1 and ownedObjects 1): the replication lag a 204 on a group is known for; T.3, three minutes later, reads the baseline.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Transcript (redacted): raw\s91\teardown-20261006-101934Z.log; OerLive 1.0.2.
[oer-s91] Mode: REMOVE. Prefix 'oer-s91-'. Objects (fixed): oer-s91-grp; oer-s91-nested, a member of it; oer-live-cc-noperm (service principal, never changed itself) a member and an owner of oer-s91-grp. OerLive 1.0.2.
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s91] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s91] Residue: raw\residue.json holds no rows.
[oer-s91] Teardown of 'oer-s91-': users 0, groups 2, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s91] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s91] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s91] Removed: oer-s91-grp: PIM for Groups owner assignment of a principal (201).
[oer-s91] Removed: oer-s91-grp: PIM for Groups member assignment of a principal (201).
[oer-s91] Removed: oer-s91-grp: PIM for Groups member assignment of a principal (201).
[oer-s91] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s91] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s91] Teardown 5/6: the prefixed groups.
[oer-s91] Deleted: group oer-s91-grp (204).
[oer-s91] Deleted: group oer-s91-nested (204).
[oer-s91] Teardown 6/6: the prefixed users.
[oer-s91] Teardown of 'oer-s91-': removed 5, residue 0, unreadable 0.
[oer-s91] Sweep: group 'oer-s91-grp' (00000000-0000-0000-0000-000000000005) carries the prefix.
[oer-s91] Sweep: group 'oer-s91-nested' (00000000-0000-0000-0000-000000000006) carries the prefix.
[oer-s91] The service principal of the noperm app id is named oer-live-cc-noperm: True
[oer-s91] Counts: groups now 99, at the baseline 97; equal: False
[oer-s91] oer-live-cc-noperm memberOf: now 1, at the baseline 0; the same objects: False
[oer-s91] oer-live-cc-noperm ownedObjects: now 1, at the baseline 0; the same objects: False
[oer-s91] Done.
[oer-s91] Exit code: 0
```

### T.3. Read back, and clean up

- [x] **T.3** Minutes later: no `oer-s91-` object left, the baseline holds, no residue row, the main clone still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Exit code: $Code; the main clone is on: $MainBranch"
```

**Expect:** `no user, group, administrative unit, catalog, access package or app registration
starting with 'oer-s91-' is left`; the counts and both service principal lines `True`; `residue rows:
0`; exit code `0`; the main clone on `main`. Then, outside this file: the step's `raw\s91\` folder is
deleted once the results are copied in, and the redaction map with `Clear-OerLiveRedactionMap`.
**Failure looks like:** a prefixed object still listed after minutes, or a `False` -- STOP (G11.5).

Result: 2026-10-06 10:23 UTC, written by Write-OerLiveResult (OerLive 1.0.2).

```text
Verdict: PASS. Three minutes after the teardown: no oer-s91- object of any kind left; groups 97, equal to the baseline; oer-live-cc-noperm a member of 0 groups and owner of 0 objects, the same objects as at the baseline (the service principal itself was never changed); unread collections 0; residue rows 0; exit code 0; the main clone on main, never switched.

[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.2; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s91] Transcript (redacted): raw\s91\readback-20261006-102302Z.log; OerLive 1.0.2.
[oer-s91] Mode: READ BACK. Prefix 'oer-s91-'. Objects (fixed): oer-s91-grp; oer-s91-nested, a member of it; oer-live-cc-noperm (service principal, never changed itself) a member and an owner of oer-s91-grp. OerLive 1.0.2.
[oer-s91] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg1\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s91] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s91] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s91] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s91-' is left.
[oer-s91] The service principal of the noperm app id is named oer-live-cc-noperm: True
[oer-s91] Counts: groups now 97, at the baseline 97; equal: True
[oer-s91] oer-live-cc-noperm memberOf: now 0, at the baseline 0; the same objects: True
[oer-s91] oer-live-cc-noperm ownedObjects: now 0, at the baseline 0; the same objects: True
[oer-s91] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s91] Done.
[oer-s91] Exit code: 0; the main clone is on: main
```

### R1.T1. The teardown's plan, round 1

- [ ] **R1.T1** `-Teardown -WhatIf` plans only `oer-s91-` targets: the two groups, and the links still in `oer-s91-grp`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s91\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s91-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s91-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the sweep finds `oer-s91-grp` and `oer-s91-nested` and nothing else; step 2 plans an
`adminRemove` for each link still in `oer-s91-grp`, read as a Direct PIM for Groups assignment (T.1
saw three; after 4.4 removed `oer-s91-nested`'s membership, two are left: the service principal's
member and owner links); step 5 plans the two groups; every tenant target starts with `oer-s91-`;
nothing removed; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### R1.T2. The teardown, round 1

- [ ] **R1.T2** Both groups deleted; the service principal goes back to its baseline (R1.T3 reads it).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the links of R1.T1 removed, `Deleted: group oer-s91-grp (204)` and `Deleted: group
oer-s91-nested (204)`; `residue 0`; the sweep and the comparison seconds later may still see the
deleted groups (replication), and R1.T3 reads again; exit code `0`.
**Failure looks like:** a residue line or exit code `3` -- the row stays in `raw\residue.json` and the
next prereq run retries it; a `False` on the service principal's lines after R1.T3 -- STOP (G11.5).

Result:

### R1.T3. Read back, and clean up, round 1

- [ ] **R1.T3** Minutes later: no `oer-s91-` object left, round 1's baseline holds, no residue row, the main clone still on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s91-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s91'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS91Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Exit code: $Code; the main clone is on: $MainBranch"
```

**Expect:** as T.3: no `oer-s91-` object left; the group count equal to round 1's baseline and both
service principal lines `True` (a member of no group and owner of nothing it did not own at the
baseline); `residue rows: 0`; exit code `0`; the main clone on `main`. Then, outside this file: the
step's `raw\s91\` folder is deleted once the results are copied in, and the redaction map with
`Clear-OerLiveRedactionMap`.
**Failure looks like:** a prefixed object still listed after minutes, or a `False` -- STOP (G11.5).

Result:
