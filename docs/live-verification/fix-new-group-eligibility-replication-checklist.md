# Live verification checklist -- a new group's eligibility waits out replication (fix/new-group-eligibility-replication)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s73-`.** The
prerequisite script creates one DISABLED user, `oer-s73-user1`. The checklist itself then makes
exactly one apply through the module (1.2): `Invoke-OERStructure` creates the security group
`oer-s73-new` and gives `oer-s73-user1` a five-day PIM for Groups member eligibility in it, which
onboards the group to PIM for Groups -- that cannot be undone, and the teardown deletes the group. It
changes no directory role, no policy and no object outside the prefix. Section 2 signs in as
`oer-live-cc-noperm`, which holds no permission, so every write it attempts is refused by Graph. Every
other check only READS the tenant, and the checks that must not write run behind a read-only fence
that refuses every Microsoft Graph request that is not a read (see Setup).

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS73Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 2 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all: a 403 there is the
expected outcome, not a stop. Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown, and
the apply in 1.2, run first with `-WhatIf`; read the plan against the `Expect:` line before running
the line that writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s73/` -- the
library writes its transcript and the baseline there, and the folder is git-ignored. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
Graph failure's record carries the bearer token. Every block prints the error id, type, category and
message only.

## What changed and why this needs a live tenant

The branch makes the apply engine wait out a new group's replication on its eligibility write, as it
already did for the group's PIM policy, and measures two older claims about error records and
warnings. Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased
onto `main` before it merges.

- **A. A new group's eligibility waits out replication** ("wait out a 404 on a new group's
  eligibility within the shared budget", "prove the shared budget and a refused probe on a new
  group's eligibility"). When `Invoke-OERStructure` creates a group and the same document declares
  a PIM for Groups eligibility for it, Microsoft Graph can answer the eligibility request with 404
  ResourceNotFound while PIM for Groups does not know the group yet; Sprint 6 measured that live,
  with eleven error records left behind and a re-run as the only remedy. For a group THIS run
  created, a time-bound eligibility is now requested through a private twin of
  `Add-OERGroupEligibility`'s request that declares the 404 to the transport, so a 404 is waited on
  (2, 4, 8, 16 s) and leaves no record; a permanent eligibility first waits, silently, until Graph
  lists the group's policy for that access type and the listed policy can be read ("wait for a new
  group's policy to be readable before its permanent eligibility"), and then calls
  `Add-OERGroupEligibility` as before, so its policy self-heal finds the policy. Both share the one
  30-second budget per group that the `pimPolicy` step already spends. A spent budget gives a
  `Failed` row with one record whose message says a re-run usually applies it -- `ResourceNotFound`
  for a time-bound eligibility, `GroupNotOnboarded` for a permanent one, the ids those rows already
  carried; a refusal (403, a throttle the transport could not ride out, a 5xx) is reported as
  itself and never waited on. A request Graph accepts but answers with status `Failed` -- the second
  phase of the same replication, found by this file's first run (1.2 and 1.3, correction round 1) --
  is waited out the same way, in both steps ("wait out a new group's accepted-but-failed eligibility
  request"). A group that already existed is unchanged: no probe, no wait, the same cmdlet call.
- **B. A refused write: the records it leaves were measured, and nothing changed.** The claim from
  Sprint 6 -- "a refused Graph write leaves four records in `-ErrorVariable`, one of them empty" --
  was measured with the transport mocked: the count depends on the cmdlet (2 for
  `Add-OERGroupMember` and `Remove-OERGroupMember`, 9 for `Add-OERGroupEligibility`, 12 for an
  apply whose first lookup is refused), the empty records come from two different lines of the
  Graph wrapper, and a 404 or a 500 leaves exactly as many as a 403. The cause is not in one place,
  so by the spec's rule the module is unchanged; section 2 measures the real SDK on `main` and on
  this branch.
- **C. A prune no longer warns twice** ("silence the child's duplicate warning on two prune
  passes"). Removing an administrative unit's scoped role and an Azure role assignment under
  `-Prune` wrote the engine's warning and then the removing cmdlet's own; the engine now silences
  the cmdlet's duplicate at the call site, as it already did for group eligibility and directory
  role assignments. Its own warning, written before the confirmation gate, is unchanged.

A live tenant is needed for what mocks cannot show: that a group created by the apply engine gets its
eligibility in the same run with no error record left behind, however long Graph takes to know the
group (section 1), and how many records a refused write really leaves in `-ErrorVariable` when the
real Microsoft Graph SDK raises it, on `main` and on this branch (section 2).

## What this file does not check, and why

- **The wait cannot be provoked on demand.** Whether Graph answers the first eligibility request for a
  new group with 404 is up to Graph's replication on the day. 1.2 records how many times it did, and
  how long the run waited; if it answered at once, the wait itself is proven only by the mocked,
  mutation-proven tests in `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (Context
  `eligibility of a group created in the same run: 404 ResourceNotFound is replication (Sprint 7 step 3)`)
  and `tests/Unit/Private/Send-OERNewGroupEligibilityRequest.Tests.ps1`.
- **A budget that runs out, a refused new request, the shared budget with `pimPolicy`, and a new
  group's PERMANENT eligibility** need Graph to answer a particular way for a particular length of
  time, or a permission `oer-live-cc` holds to be refused; they are proven by the same tests. A group
  that already existed never waits: 1.4 shows the second run reads it as existing and writes nothing.
- **A refused write through `Invoke-OERStructure` cannot be provoked as `oer-live-cc-noperm`.** Every
  handler reads before it writes, and the no-permission identity can read nothing, so its first
  refused request is always a read (2.1 records that case). A refused WRITE through the engine is
  measured with the transport mocked in the unit measurement this branch's report describes.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- with PIM for Groups, and the two configuration
  files OerLive reads beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS73Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same four lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes users and groups and writes PIM for
  Groups eligibility, all with the permissions it already holds; this file adds none.
- The **built module of this branch** in the clone OerLive loads from (S.1 does it; 2.2 and 2.3 swap
  it for `main`'s build and back).

**The fence.** Every check that runs a module cmdlet replaces the module's Graph transport, in the
module's own scope, with a thin wrapper that records each request's method and path, and whether
Graph answered with a code the request had declared as an answer (a 404 the wait counts as
replication). In the checks marked read-only it also refuses every request that is not a GET, with
an error naming the method and path.

### S.1. Point the clone at this branch and build it

- [ ] **S.1** The clone OerLive loads from holds this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Write-OerLiveStep "Tracked changes in the clone before the switch: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$null = git -C $Cfg.Repo fetch origin fix/new-group-eligibility-replication 2>&1
$null = git -C $Cfg.Repo switch --detach FETCH_HEAD 2>&1
Write-OerLiveStep "Clone at: $(git -C $Cfg.Repo log -1 --format='%h %s')"
Push-Location -LiteralPath $Cfg.Repo
try { ./build.ps1 -Tasks build *> (Join-Path $env:TEMP 'oer-s73-build.log'); $Code = $LASTEXITCODE } finally { Pop-Location }
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'answers 404 (not known to PIM for Groups yet)' -Quiet)
Write-OerLiveStep "Build exit code: $Code; the built module carries this branch's fix: $Fix"
```

**Expect:** `Tracked changes in the clone before the switch: 0`; the clone at the branch head (its
subject is the last commit of this branch); `Build exit code: 0; the built module carries this
branch's fix: True`.
**Failure looks like:** tracked changes in the clone -- stop, the clone is someone's work; a build
exit code other than 0; `False` -- the clone did not get this branch, and every check below would
measure `main`.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, Graph and the module session

- [ ] **0.1** Both sign-ins pass the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Graph
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the clone's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` for both sign-ins (app-only certificate session with the
identity's app id, the app name `oer-live-cc`, the test tenant, the service principal of that app id
named `oer-live-cc` and, for the module session, the token's signed-in object; the organization name,
a verified domain and the organization id; the ARM token from the certificate; the test subscription
belongs to the test tenant and is Enabled), each sign-in ending `identity check passed: True`, and
`The module is the clone's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. Identity check as oer-live-cc-noperm, the module session and Graph

- [ ] **0.2** The no-permission identity signs in to a module session and to Graph.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Arm -NoPerm
Connect-OerLive -Graph -NoPerm
Disconnect-OerLive
```

**Expect:** for both sign-ins the lines for `oer-live-cc-noperm`: app-only with its app id `True`,
the app name in the session is `oer-live-cc-noperm`: `True`, the test tenant `True`, for the module
session the ARM token from the certificate `True`, and `identity check passed: True`.
**Failure looks like:** any `False` -- STOP; section 2 needs both sessions.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s73-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS73Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s73\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s73-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s73-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s73-`
object; the plan names the transcript and the baseline file under `raw\s73\` and, in the tenant, the
user `oer-s73-user1` -- one tenant target, starting with `oer-s73-`;
`WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The disabled test user exists.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS73Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created user oer-s73-user1
(disabled)` and the user resolving by its user principal name; the summary with the user `present`
and the checklist's own writes (`oer-s73-new`, eligibility) `absent`; exit code `0`.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. A new group and its eligibility in one run, as oer-live-cc

The document below declares the group `oer-s73-new` and a five-day member eligibility for
`oer-s73-user1`, and nothing else: no member, no owner, no `pimPolicy`. The group does not exist
before 1.2, so the apply creates it and, in the same run, writes the eligibility of a group Microsoft
Graph learned about a second earlier.

### 1.1. The apply document's plan: the group would be created, nothing written

- [ ] **1.1** `-WhatIf` plans the group and its eligibility, behind the read-only fence.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S73Seen = [System.Collections.Generic.List[string]]::new()
    $script:S73Refused = [System.Collections.Generic.List[string]]::new()
    $script:S73Declared = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S73Transport) { $script:S73Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S73Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S73Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S73 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S73Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s73): a new group''s eligibility waits out replication.'
$Doc = [ordered]@{
    version = '1.0'
    groups  = @([ordered]@{ displayName = 'oer-s73-new'; description = $Just; eligibility = @([ordered]@{ principal = "oer-s73-user1@$($Cfg.UserDomain)"; accessType = 'member'; durationDays = 5 }) })
}
$Rows = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Groups -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S73Seen); Refused = @($script:S73Refused) } }
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err)) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records in -ErrorVariable: $(@($Err).Count)"
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** two rows, both `Skipped`: `would create group oer-s73-new` and `would configure
eligibility for 'oer-s73-user1@example.com' after group is created`; no record, no warning; every
request a GET (the group's name lookup), `refused by the fence: 0`.
**Failure looks like:** a row other than `Skipped`; a request refused by the fence -- a write was
attempted under `-WhatIf`.

Result:

### 1.2. The apply document, for real: group and eligibility in the same run, no error record

- [ ] **1.2** The group is `Created` and its eligibility applied in the same run, with 0 records in `-ErrorVariable`; the wait is recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S73Seen = [System.Collections.Generic.List[string]]::new()
    $script:S73Declared = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S73Transport) { $script:S73Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S73Seen.Add("$($Method.ToUpperInvariant()) $Path")
        $Answer = & $script:S73Transport @PSBoundParameters
        if ($null -ne $Answer -and @($Answer.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
            $script:S73Declared.Add("$($Method.ToUpperInvariant()) $Path answered $($Answer.StatusCode) $($Answer.ExpectedErrorCode)")
        } elseif ($Method -ne 'GET' -and $Answer -is [System.Collections.IDictionary] -and $Answer.Contains('status')) {
            $script:S73Declared.Add("$($Method.ToUpperInvariant()) $Path accepted, request status $([string]$Answer['status'])")
        }
        $Answer
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s73): a new group''s eligibility waits out replication.'
$Doc = [ordered]@{
    version = '1.0'
    groups  = @([ordered]@{ displayName = 'oer-s73-new'; description = $Just; eligibility = @([ordered]@{ principal = "oer-s73-user1@$($Cfg.UserDomain)"; accessType = 'member'; durationDays = 5 }) })
}
$Clock = [System.Diagnostics.Stopwatch]::StartNew()
$Out = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Groups -Confirm:$false -Verbose -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn 4>&1)
$Clock.Stop()
$Rows = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
$WaitLines = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^Sync-OERStructureGroup: .*; retry \d+ in \d+ s\.$' } | ForEach-Object { $_.Message })
$Waited = 0
foreach ($L in $WaitLines) { if ($L -match 'in (\d+) s\.$') { $Waited += [int]$Matches[1] } }
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S73Seen); Declared = @($script:S73Declared) } }
$Writes = @($Fence.Seen | Where-Object { $_ -notlike 'GET *' })
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err)) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) [$($E.GetType().Name)] -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
foreach ($L in $WaitLines) { Write-OerLiveStep "Wait: $L" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records in -ErrorVariable: $(@($Err).Count)"
Write-OerLiveStep "Wait: $($WaitLines.Count) line(s), $Waited s of the 30 s budget; the whole apply took $([math]::Round($Clock.Elapsed.TotalSeconds, 1).ToString([cultureinfo]::InvariantCulture)) s"
Write-OerLiveStep "Requests: $($Fence.Seen.Count); not a GET: $($Writes.Count) [$($Writes -join '; ')]; answered with a declared code: $($Fence.Declared.Count) [$($Fence.Declared -join '; ')]"
Disconnect-OerLive
```

**Expect:** two rows -- `Created` `created group oer-s73-new (...)` and `Updated` `set time-bound
member eligibility for 'oer-s73-user1@example.com' (5 days): ...` (the handler reports an applied
eligibility as `Updated`, as it reports every child it adds; the GROUP row is the one that is
`Created`); `records in -ErrorVariable: 0`, no warning. The wait: a new group goes through two phases
of replication in PIM for Groups, measured in this file's first run -- the request answers 404
(`answered 404 ResourceNotFound`), then it is accepted but answers request status `Failed`. Each such
answer shows as one `Wait:` line and one entry in the declared/accepted list, and the requests that
are not a GET are the group's POST and then the eligibility POST once per attempt; the last entry is
`accepted, request status Provisioned` (or another status that is not `Failed`). Zero waits is a pass
too -- Graph knew the group at once -- and is recorded as such. 1.3 is what proves the eligibility
exists.
**Failure looks like:** a `Failed` row -- its Detail says whether the budget ran out
(`within the 30-second wait` ... `replication delay`, re-run once 1.3 shows nothing) or Graph refused
the request (the record says which); any record in `-ErrorVariable` on a run that ended `Created`
and `Updated` -- that is the defect this branch closes; a last accepted entry with request status
`Failed` beside an `Updated` row -- the second phase was not waited out.

Result:

### 1.3. Read back: the eligibility exists, for oer-s73-user1, five days

- [ ] **1.3** Graph lists exactly one member eligibility in `oer-s73-new`, for `oer-s73-user1`, ending five days after it starts.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Graph
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id,securityEnabled,isAssignableToRole" -f [uri]::EscapeDataString("displayName eq 'oer-s73-new'"))
Assert-OerLiveOk -Response $G -Activity 'Reading oer-s73-new' | Out-Null
$U = Invoke-OerLiveGraph -All -Uri ("v1.0/users?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("userPrincipalName eq 'oer-s73-user1@$($Cfg.UserDomain)'"))
Assert-OerLiveOk -Response $U -Activity 'Reading oer-s73-user1' | Out-Null
Write-OerLiveStep "oer-s73-new: $(@($G.Body['value']).Count) group(s), security $([bool]@($G.Body['value'])[0]['securityEnabled']), role-assignable $([bool]@($G.Body['value'])[0]['isAssignableToRole']); oer-s73-user1: $(@($U.Body['value']).Count) user(s)"
$Gid = [string]@($G.Body['value'])[0]['id']
$Uid = ([string]@($U.Body['value'])[0]['id']).ToLowerInvariant()
$W = Wait-OerLiveConverged -Activity 'oer-s73-new lists one member eligibility of oer-s73-user1' -Read {
    $R = Invoke-OerLiveGraph -All -Uri ("beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter={0}" -f [uri]::EscapeDataString("groupId eq '$Gid'"))
    Assert-OerLiveOk -Response $R -Activity 'Reading the eligibility of oer-s73-new' | Out-Null
    , @($R.Body['value'])
} -Test { @($args[0]).Count -eq 1 -and ([string]@($args[0])[0]['principalId']).ToLowerInvariant() -eq $Uid -and [string]@($args[0])[0]['accessId'] -eq 'member' }
$S = @($W.Value)[0]
$Start = [datetimeoffset]::Parse([string]$S['scheduleInfo']['startDateTime'], [cultureinfo]::InvariantCulture)
$End = $S['scheduleInfo']['expiration']['endDateTime']
$Days = if ($End) { [math]::Round(([datetimeoffset]::Parse([string]$End, [cultureinfo]::InvariantCulture) - $Start).TotalDays, 2).ToString([cultureinfo]::InvariantCulture) } else { 'none' }
Write-OerLiveStep "Eligibility: status $([string]$S['status']); member type $([string]$S['memberType']); expiration $([string]$S['scheduleInfo']['expiration']['type']) $([string]$S['scheduleInfo']['expiration']['duration']); days from start to end: $Days"
Disconnect-OerLive
```

**Expect:** one group, security `True`, role-assignable `False`; one user; the eligibility converged
(one row, the user, `member`); status `Provisioned`, member type `Direct`, an expiration that ends
five days after the start (`afterDuration` `P5D`, or `afterDateTime` with `days from start to end: 5`).
**Failure looks like:** no row after the budget -- the apply reported a success Graph does not show;
a row for anyone else, or of another access type.

Result:

### 1.4. The same document again: only Unchanged, nothing written (G8)

- [ ] **1.4** Run twice, the document converges: the second run is all `Unchanged`, writes nothing and waits for nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S73Seen = [System.Collections.Generic.List[string]]::new()
    $script:S73Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S73Transport) { $script:S73Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S73Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S73Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S73 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S73Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s73): a new group''s eligibility waits out replication.'
$Doc = [ordered]@{
    version = '1.0'
    groups  = @([ordered]@{ displayName = 'oer-s73-new'; description = $Just; eligibility = @([ordered]@{ principal = "oer-s73-user1@$($Cfg.UserDomain)"; accessType = 'member'; durationDays = 5 }) })
}
$Out = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Groups -Confirm:$false -Verbose -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn 4>&1)
$Rows = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
$WaitLines = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '; retry \d+ in \d+ s\.$' })
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S73Seen); Refused = @($script:S73Refused) } }
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err)) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records in -ErrorVariable: $(@($Err).Count); wait lines: $($WaitLines.Count)"
Write-OerLiveStep "Requests: $($Fence.Seen.Count); not a GET: $(@($Fence.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** two rows, both `Unchanged` -- `group properties match` and `eligibility for
'oer-s73-user1@example.com' (member) already matches`; no record, no warning, `wait lines: 0` (the
group now exists, and a group that already existed never waits); every request a GET,
`refused by the fence: 0`.
**Failure looks like:** any row other than `Unchanged` -- the write does not converge; a request
refused by the fence; a wait line.

Result:

### 2. Refused writes, as oer-live-cc-noperm: the records each one leaves, on this branch and on main

Each check signs in as `oer-live-cc-noperm`, which holds no permission, and runs four calls against
the test objects: three cmdlets that, given object ids, send their WRITE as the first request
(`Add-OERGroupMember`, `Add-OERGroupEligibility -DurationDays 5`, `Remove-OERGroupMember`), and the
apply engine with 1.2's document, whose first request -- the group's name lookup -- is refused
before it can reach a write (see "What this file does not check"). For each call it prints every
record the call left in `-ErrorVariable`: its id, type, the command that wrote it and whether it is
empty. A 403 is the expected outcome. The object ids are read first as `oer-live-cc`. 2.1 measures
this branch, 2.2 the same calls on `main`'s build, 2.3 puts the branch back and 2.4 reads back that
nothing was written.

### 2.1. This branch: the refused writes and their records

- [ ] **2.1** Every call is refused by Graph, and the records each leaves are counted and described.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Graph
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s73-new'"))
Assert-OerLiveOk -Response $G -Activity 'Reading oer-s73-new' | Out-Null
$U = Invoke-OerLiveGraph -All -Uri ("v1.0/users?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("userPrincipalName eq 'oer-s73-user1@$($Cfg.UserDomain)'"))
Assert-OerLiveOk -Response $U -Activity 'Reading oer-s73-user1' | Out-Null
$Gid = [string]@($G.Body['value'])[0]['id']
$Uid = [string]@($U.Body['value'])[0]['id']
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S73Seen = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S73Transport) { $script:S73Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S73Seen.Add("$($Method.ToUpperInvariant()) $Path")
        & $script:S73Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s73): a new group''s eligibility waits out replication.'
$Doc = [ordered]@{
    version = '1.0'
    groups  = @([ordered]@{ displayName = 'oer-s73-new'; description = $Just; eligibility = @([ordered]@{ principal = "oer-s73-user1@$($Cfg.UserDomain)"; accessType = 'member'; durationDays = 5 }) })
}
$Calls = [ordered]@{
    'Add-OERGroupMember'      = { Add-OERGroupMember -Group $Gid -PrincipalId $Uid -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable S73Err }
    'Add-OERGroupEligibility' = { Add-OERGroupEligibility -Group $Gid -PrincipalId $Uid -DurationDays 5 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable S73Err }
    'Remove-OERGroupMember'   = { Remove-OERGroupMember -Group $Gid -PrincipalId $Uid -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable S73Err }
    'Invoke-OERStructure'     = { Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Groups -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable S73Err -WarningAction SilentlyContinue }
}
foreach ($Name in $Calls.Keys) {
    & (Get-Module Omnicit.EntraRBAC) { $script:S73Seen.Clear() }
    $S73Err = $null
    $Out = @(. $Calls[$Name])
    $Seen = & (Get-Module Omnicit.EntraRBAC) { @($script:S73Seen) }
    Write-OerLiveStep "$($Name): output $($Out.Count) object(s); records in -ErrorVariable: $(@($S73Err).Count); empty records: $(@($S73Err | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Exception.Message) -or [string]::IsNullOrWhiteSpace([string]$_.FullyQualifiedErrorId) }).Count); requests: $($Seen.Count) [$($Seen -join '; ')]"
    $I = 0
    foreach ($E in @($S73Err)) {
        $I++
        $IsRecord = $E -is [System.Management.Automation.ErrorRecord]
        $Ex = if ($IsRecord) { $E.Exception } else { $E }
        $Msg = [string]$Ex.Message
        if ($Msg.Length -gt 90) { $Msg = $Msg.Substring(0, 90) + '...' }
        $Who = if ($IsRecord -and $E.InvocationInfo -and $E.InvocationInfo.MyCommand) { $E.InvocationInfo.MyCommand.Name } else { '(none)' }
        $Id = if ($IsRecord) { [string]$E.FullyQualifiedErrorId } else { '(no error id: a bare exception)' }
        Write-OerLiveStep "  $I. $Id [$($E.GetType().Name)$(if ($IsRecord -and $Ex) { ' / ' + $Ex.GetType().Name })] by $Who -- $Msg"
    }
}
Disconnect-OerLive
```

**Expect:** for each of the four calls no output and one or more records, every one naming the
refusal (`Authorization_RequestDenied`, or the code Graph gave for a 403) and none a `*NotFound`;
`empty records: 0` unless the measurement in "What changed" says otherwise; the three cmdlets each
sent exactly one request, the write (a `POST` to the group's members, a `POST` to
`eligibilityScheduleRequests`, a `DELETE` of the member reference); the engine sent one request, the
GET of the group's name lookup. The counts are the branch's half of the before/after table.
**Failure looks like:** a call that produced output or no record -- Graph accepted a write from an
identity with no permission: STOP; a cmdlet whose first request was not its write; an id ending in
`NotFound`.

Result:

### 2.2. main: the same refused writes on main's build

- [ ] **2.2** The same four calls on `main`'s build, for the before half of the table.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Write-OerLiveStep "Tracked changes in the clone before the switch: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$null = git -C $Cfg.Repo fetch origin main 2>&1
$null = git -C $Cfg.Repo switch --detach FETCH_HEAD 2>&1
Write-OerLiveStep "Clone at: $(git -C $Cfg.Repo log -1 --format='%h %s')"
Push-Location -LiteralPath $Cfg.Repo
try { ./build.ps1 -Tasks build *> (Join-Path $env:TEMP 'oer-s73-build-main.log'); $Code = $LASTEXITCODE } finally { Pop-Location }
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'answers 404 (not known to PIM for Groups yet)' -Quiet)
Write-OerLiveStep "Build exit code: $Code; the built module carries this branch's fix: $Fix"
```

Then run the block of 2.1 again, unchanged, in a fresh window.

**Expect:** `Tracked changes in the clone before the switch: 0`; the clone at `main`'s head; `Build
exit code: 0; the built module carries this branch's fix: False`; then 2.1's lines for `main`.
**Failure looks like:** `True` -- the clone still holds the branch, and the "before" half would
measure the branch.

Result:

### 2.3. Back to this branch

- [ ] **2.3** The clone holds this branch's build again.

Run the block of S.1 again, unchanged.

**Expect:** as S.1: `Tracked changes in the clone before the switch: 0`, the branch head, `Build exit
code: 0; the built module carries this branch's fix: True`.
**Failure looks like:** `False` -- the teardown would run on `main`'s build; it does not depend on
the module's version, but the clone must be left on the branch for the report.

Result:

### 2.4. Read back: none of the refused writes landed

- [ ] **2.4** `oer-s73-new` still has no member and exactly the one eligibility from 1.2.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
Connect-OerLive -Graph
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s73-new'"))
Assert-OerLiveOk -Response $G -Activity 'Reading oer-s73-new' | Out-Null
$Gid = [string]@($G.Body['value'])[0]['id']
$M = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$Gid/members?`$select=id"
Assert-OerLiveOk -Response $M -Activity 'Reading the members of oer-s73-new' | Out-Null
$E = Invoke-OerLiveGraph -All -Uri ("beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter={0}" -f [uri]::EscapeDataString("groupId eq '$Gid'"))
Assert-OerLiveOk -Response $E -Activity 'Reading the eligibility of oer-s73-new' | Out-Null
Write-OerLiveStep "oer-s73-new: members $(@($M.Body['value']).Count); eligibility rows $(@($E.Body['value']).Count) [$((@($E.Body['value']) | ForEach-Object { "$([string]$_['accessId']) $([string]$_['status'])" }) -join ', ')]"
Disconnect-OerLive
```

**Expect:** `members 0; eligibility rows 1 [member Provisioned]`.
**Failure looks like:** a member, or a second eligibility row -- a refused write landed after all:
STOP and record it.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans the removal of only `oer-s73-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS73Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s73\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s73-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s73-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the plan removes, in the library's order, the member
eligibility in `oer-s73-new` (step 2, where the assignment schedules are reported unreadable for this
identity, decision B8), the group `oer-s73-new` (step 5) and the user `oer-s73-user1` (step 6) --
every tenant target starting with `oer-s73-`; `WhatIf: nothing was created, removed or written`;
exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Every `oer-s73-` object is removed, and the tenant's counts are back at the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS73Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** each removal answered, in the library's order (the eligibility read back as gone before
it counts); the sweep finds no `oer-s73-` object (a group or user deleted seconds earlier can still
show in the listing for a few seconds -- T.3 reads again); `Counts: users ... equal: True` and
`Counts: groups ... equal: True`; no residue; exit code `0`.
**Failure looks like:** exit code `3` -- residue: record each RESIDUE line, T.3 retries; exit code
`1` -- read the stop line.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Nothing with the prefix is left, no residue, and the raw folder and the redaction map are deleted.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s73-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s73'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS73Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Clean = [bool]($Code -eq 0 -and ($Out -match 'prefixed objects left: 0; unread collections: 0; residue rows: 0'))
Write-OerLiveStep "Read back clean: $Clean"
if ($Clean) {
    if (Test-Path -LiteralPath $Raw) { [System.IO.Directory]::Delete($Raw, $true) }
    Write-OerLiveStep "raw\s73 deleted: $(-not (Test-Path -LiteralPath $Raw))"
    Clear-OerLiveRedactionMap
}
```

**Expect:** `Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.`; both
counts equal to the baseline; `Read back clean: True`; `raw\s73 deleted: True`; the redaction map
cleared.
**Failure looks like:** a prefixed object left, or a residue row -- record it in the report, do not
delete the raw folder.

Result:
