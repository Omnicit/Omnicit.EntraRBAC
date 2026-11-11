# Live verification checklist -- lookups once and proven absence (fix/lookups-once-and-proven-absence)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s154-`.** The
prerequisite script creates three role-assignable security groups without members or owners,
`oer-s154-g1`, `oer-s154-g2` and `oer-s154-g3`, and gives `oer-s154-g3` an eligible assignment of
the low-risk directory role Reports Reader for 30 days. The checks write only these: eligible
assignments of Message Center Reader (check 1.3) and of Reports Reader (check 1.4) to `oer-s154-g1`
and `oer-s154-g2`, the removal of `oer-s154-g3`'s Reports Reader assignment (check 1.4, `-Prune`),
and one access review definition, `oer-s154-ar`, of `oer-s154-g1`'s members (check 2.1). Every real
apply runs behind a request fence in the module's scope that refuses any write but those. Both roles
are on the low-risk list; the prerequisite script stops before its first write if a principal
outside the prefix holds either of them.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS154Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s154/`
(git-ignored). Every block prints through the library's redactor, and the blocks print the test
objects by their key in the prerequisite script's id file (`g1`, `g2`, `g3`), never by id; any other
object id becomes `00000000-0000-0000-0000-0000000000NN`. **No credential, token, application id or
certificate thumbprint is ever printed. Never render an error record**: every block prints the error
id only. The request counts come from the Graph wrapper's own verbose line per request, counted by
kind; no request line is printed.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. Each name is looked up once per run** ("look a directory role and principal up once per
  run"). The `directoryRoleAssignments` handler of `Invoke-OERStructure` resolved every entry's role
  and principal in the section's prune pass and then again in each entry's own invocation; a name the
  section repeats was resolved once per entry. The engine now hands the section one cache per
  document, and each role and principal is looked up at most once; only a successful answer is kept,
  so a failed lookup is made again where it is next needed and every row and error record stays as it
  was.
- **B. A review is created only on a proven empty answer** ("create an access review only when the
  read proved none exists"). The `accessReviews` handler creates a review only when
  `Get-OERAccessReviewDefinition` published `AccessReviewDefinitionNotFound` (its first id segment,
  compared whole and ordinally). A read that gave no answer at all is reported `Failed` with
  `AccessReviewAbsenceUnproven`, and nothing is created.

A live tenant is needed for what mocks cannot show: the real number of Graph requests a document
named by names costs before and after, on a tenant whose answers do not change between the two runs
(A); and that the real `Get-OERAccessReviewDefinition`, against Graph, still publishes the answer the
stricter rule needs, so a review is still created when none exists and found the second time (B).

## What this file does not check, and why

- **The unanswered read of B cannot be produced live**: Graph answers the name read either with
  definitions or empty, and the module's own read publishes the not-found answer on an empty one.
  Class B: the Describe blocks of `tests/Unit/Private/Sync-OERStructureAccessReview.Tests.ps1` named
  in the step's report drive every shape (no output and no record, a longer or other-case id, a record
  without the publisher, a thrown id) offline.
- **A failed lookup kept out of the cache** (A) needs a lookup that fails on one call and not on the
  next. Class B: the handler's and the engine's unit tests.
- **Active assignments are not used.** An active assignment starts Microsoft Graph's five-minute rule
  and adds nothing to what A changes; both documents declare eligible assignments.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS154Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$LookupCache' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'AccessReviewAbsenceUnproven' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result: 2026-11-11 18:01 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main; the worktree on fix/lookups-once-and-proven-absence at 8fba072 with 0 tracked changes; the build carries A and B.

[oer-s154] The module loads from a worktree that is not the main clone: True
[oer-s154] Main clone: branch main
[oer-s154] Worktree: branch fix/lookups-once-and-proven-absence; HEAD 8fba072 docs: name the unanswered review refusal in the help; tracked changes: 0
[oer-s154] The worktree's build carries A: True; B: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** `identity check passed: True`; `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or "application is disabled" -- STOP.

Result: 2026-11-11 18:02 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The ARM module session as oer-live-cc passes every identity check line; the module loaded is the worktree's build.

[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] The module is the worktree's build: True
```

### 0.2. The prerequisite script's plan

- [x] **0.2** `-WhatIf` plans only `oer-s154-` objects, and neither role holds a foreign assignment.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS154Prereq.ps1 -WhatIf
```

**Expect:** the three permissions `True`; `Role Reports Reader` and `Role Message Center Reader` each
with `outside this run's groups: 0`; every `What if` line names an `oer-s154-` object (or, on a
re-run, none: the objects exist).
**Failure looks like:** a target without the prefix, a `STOP`, or a foreign assignment -- STOP.

Result: 2026-11-11 18:02 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. All three permissions held; neither role has any eligible or active schedule, so nothing outside the prefix holds them; every What if line for an object names an oer-s154- group (the assignment of g3 is not planned under -WhatIf, since it needs g3's id); the baseline sweep is 0.

What if: Performing the operation "Create Directory" on target "Destination: REPO\docs\live-verification\raw\s154".
What if: Performing the operation "Start the redacted transcript" on target "raw\s154\prereq-20261111-180217Z.log".
[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s154] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s154-', the other 5 are left untouched.
[oer-s154] Permission held: Group.ReadWrite.All: True
[oer-s154] Permission held: RoleManagement.ReadWrite.Directory: True
[oer-s154] Permission held: AccessReview.ReadWrite.All: True
[oer-s154] Role Reports Reader: 0 eligible and 0 active schedule(s); outside this run's groups: 0.
[oer-s154] Role Message Center Reader: 0 eligible and 0 active schedule(s); outside this run's groups: 0.
[oer-s154] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s154-' is left.
What if: Performing the operation "Write the baseline" on target "raw\s154\baseline-prereq.json".
[oer-s154] Baseline sweep: 0 object(s) with the prefix before this run.
What if: Performing the operation "Create role-assignable security group (no members, no owners)" on target "oer-s154-g1".
What if: Performing the operation "Create role-assignable security group (no members, no owners)" on target "oer-s154-g2".
What if: Performing the operation "Create role-assignable security group (no members, no owners)" on target "oer-s154-g3".
```

### 0.3. The prerequisite script, for real

- [x] **0.3** The three groups exist and `g3` holds its eligible Reports Reader assignment.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS154Prereq.ps1 -Unattended
```

**Expect:** every `Read back` line `True`, among them `eligible assignment of g3: True`.
**Failure looks like:** a `False`, or `STOP` -- stop the run.

Result: 2026-11-11 18:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The three role-assignable groups were created; g3's eligible Reports Reader request answered 404 SubjectNotFound once (replication, retried) and then Provisioned; every Read back line True, the eligible schedule of g3 listed at the first read.

[oer-s154] Transcript (redacted): raw\s154\prereq-20261111-180238Z.log; OerLive 1.1.0.
[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s154] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s154-', the other 5 are left untouched.
[oer-s154] Permission held: Group.ReadWrite.All: True
[oer-s154] Permission held: RoleManagement.ReadWrite.Directory: True
[oer-s154] Permission held: AccessReview.ReadWrite.All: True
[oer-s154] Role Reports Reader: 0 eligible and 0 active schedule(s); outside this run's groups: 0.
[oer-s154] Role Message Center Reader: 0 eligible and 0 active schedule(s); outside this run's groups: 0.
[oer-s154] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s154-' is left.
[oer-s154] Baseline sweep: 0 object(s) with the prefix before this run.
[oer-s154] Created group oer-s154-g1.
[oer-s154] Created group oer-s154-g2.
[oer-s154] Created group oer-s154-g3.
[oer-s154] create the eligible assignment of g3 answered 404 SubjectNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s154] Eligible assignment of g3 requested: status Provisioned.
[oer-s154] read v1.0/groups/00000000-0000-0000-0000-000000000004?$select=id answered 404 Request_ResourceNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s154] read v1.0/groups/00000000-0000-0000-0000-000000000004?$select=id answered 404 Request_ResourceNotFound (attempt 2 of 6, likely replication delay) -- trying again in 5 s.
[oer-s154] Read back group g1: True
[oer-s154] Read back group g2: True
[oer-s154] Read back group g3: True
[oer-s154] the eligible schedule of g3: converged after 1 read(s), 0.5 s.
[oer-s154] Read back eligible assignment of g3: True
```

## 1. Each name is looked up once per run (A)

The two documents name every role and principal by its NAME, so every lookup costs requests. Document
`structure-mcr.json` declares Message Center Reader as eligible for `oer-s154-g1` and `oer-s154-g2`;
document `structure-rr.json` declares Reports Reader the same way, and `oer-s154-g3`'s Reports Reader
assignment is the one `-Prune` removes. Checks 1.1 and 1.2 plan both documents (`-WhatIf`) with the
base build (`8295d3b`, before this branch) and with this branch, on the same tenant state, and count
the Graph requests by kind; checks 1.3 and 1.4 apply them for real, twice each (G8).

### 1.1. The base build's plans, counted

- [x] **1.1** The base build (`8295d3b`) plans both documents and its request counts are recorded.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's154'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[([string]$Ids[$K].Id).ToLowerInvariant()] = $K }
function L([string]$V) { [regex]::Replace($V, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { param($Hit) $Key = $Hit.Value.ToLowerInvariant(); if ($Label.ContainsKey($Key)) { $Label[$Key] } else { 'another-id' } }) }
foreach ($Doc in 'mcr', 'rr') {
    $Role = if ($Doc -eq 'mcr') { 'Message Center Reader' } else { 'Reports Reader' }
    $Entries = @(foreach ($G in 'oer-s154-g1', 'oer-s154-g2') { [ordered]@{ role = $Role; principal = $G; assignmentType = 'Eligible'; durationDays = 30; justification = 'Sprint 15 step 4 live check (oer-s154-)' } })
    [ordered]@{ version = '1.0'; directoryRoleAssignments = $Entries } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw "structure-$Doc.json") -Encoding utf8NoBOM
}
$BaseDir = Join-Path $Raw 'base-8295d3b'
if (-not (Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))) {
    git -C $Cfg.Repo archive --format=zip -o (Join-Path $Raw 'base-8295d3b.zip') 8295d3b source
    Expand-Archive -LiteralPath (Join-Path $Raw 'base-8295d3b.zip') -DestinationPath $BaseDir -Force
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the base source (8295d3b): $($M.ModuleBase.StartsWith($BaseDir, [System.StringComparison]::OrdinalIgnoreCase))"
& $M {
    Set-Item -Path 'function:script:Invoke-OERGraphRequestS154' -Value ${function:Invoke-OERGraphRequest}
    $script:S154Refused = [System.Collections.Generic.List[string]]::new()
    function script:Invoke-OERGraphRequest {
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        if ($Method -ne 'GET' -and $Uri -notmatch '/getMemberGroups$|directoryObjects/getByIds$') {
            $script:S154Refused.Add($Method)
            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S154 fence: write refused'), 'S154FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        }
        Invoke-OERGraphRequestS154 @PSBoundParameters
    }
}
Write-OerLiveStep "Fence installed (plans only, every write refused): $([bool](& $M { Get-Command Invoke-OERGraphRequestS154 -ErrorAction SilentlyContinue }))"
$Out = [ordered]@{}
foreach ($Case in @(@{ Doc = 'mcr'; Prune = $false }, @{ Doc = 'rr'; Prune = $true })) {
    $P = @{ Path = (Join-Path $Raw "structure-$($Case.Doc).json"); WhatIf = $true; Verbose = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'script:E' }
    if ($Case.Prune) { $P.Prune = $true }
    $script:E = $null
    $All = @(Invoke-OERStructure @P 4>&1 3>$null)
    $Lines = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message } | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ' })
    $Rows = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] } | ForEach-Object { [ordered]@{ Section = [string]$_.Section; Item = [string]$_.Item; Action = [string]$_.Action; Detail = [string]$_.Detail } })
    $Count = [ordered]@{
        Role      = @($Lines | Where-Object { $_ -match 'roleManagement/directory/roleDefinitions' }).Count
        Principal = @($Lines | Where-Object { $_ -match ' v1\.0/(groups|users|servicePrincipals)\?' }).Count
        Schedules = @($Lines | Where-Object { $_ -match 'roleEligibilitySchedules|roleAssignmentSchedules' }).Count
        Total     = $Lines.Count
    }
    $Count.Other = $Count.Total - $Count.Role - $Count.Principal - $Count.Schedules
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    $Name = "$($Case.Doc)$(if ($Case.Prune) { ' -Prune' })"
    $Out[$Name] = [ordered]@{ Count = $Count; Rows = $Rows; Own = $Own }
    Write-OerLiveStep "base plan ${Name}: requests role $($Count.Role), principal $($Count.Principal), schedules $($Count.Schedules), other $($Count.Other), total $($Count.Total); own errors: $($Own -join ', ')"
    Write-OerLiveStep "base plan ${Name}: rows: $((@($Rows) | ForEach-Object { '{0} {1} {2}' -f $_.Section, (L $_.Item), $_.Action }) -join '; ')"
}
Write-OerLiveStep "Writes refused by the fence: $((& $M { $script:S154Refused }).Count)"
$Out | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Raw 'base-plans.json') -Encoding utf8NoBOM
Disconnect-OerLive
```

**Expect:** `The module is the base source (8295d3b): True`; `mcr`: two rows
`directoryRoleAssignments Message Center Reader -> oer-s154-g1 (Eligible) Skipped` and the same for
`g2`; `rr -Prune`: a row `Reports Reader -> g3 (Eligible) Skipped` (would remove) and the two
`Skipped` rows for `g1` and `g2`; no own error; 0 writes refused. The counts are the "before"
numbers.
**Failure looks like:** a row for anything but `g1`, `g2` and `g3`, an own error, or a refused write.

Result: 2026-11-11 18:06 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (8295d3b) planned mcr: two Skipped rows (would create) for g1 and g2, 4 role-definition and 4 group-name lookups, 3 schedule reads, 11 requests in all; rr -Prune: g3's assignment Skipped (would remove) plus the two Skipped creates, 4 role and 4 principal lookups, 3 schedule reads and 1 other request (the membership read of the signed-in identity), 12 in all. No own error, 0 writes refused. These are the before numbers.

[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] The module is the base source (8295d3b): True
[oer-s154] Fence installed (plans only, every write refused): True
What if: Performing the operation "create eligible directory role assignment" on target "Message Center Reader -> oer-s154-g1 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Message Center Reader -> oer-s154-g2 (Eligible)".
[oer-s154] base plan mcr: requests role 4, principal 4, schedules 3, other 0, total 11; own errors: 
[oer-s154] base plan mcr: rows: directoryRoleAssignments Message Center Reader -> oer-s154-g1 (Eligible) Skipped; directoryRoleAssignments Message Center Reader -> oer-s154-g2 (Eligible) Skipped
What if: Performing the operation "Remove undeclared eligible directory role assignment" on target "Reports Reader -> 00000000-0000-0000-0000-000000000006 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s154-g1 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s154-g2 (Eligible)".
[oer-s154] base plan rr -Prune: requests role 4, principal 4, schedules 3, other 1, total 12; own errors: 
[oer-s154] base plan rr -Prune: rows: directoryRoleAssignments Reports Reader -> g3 (Eligible) Skipped; directoryRoleAssignments Reports Reader -> oer-s154-g1 (Eligible) Skipped; directoryRoleAssignments Reports Reader -> oer-s154-g2 (Eligible) Skipped
[oer-s154] Writes refused by the fence: 0
```

### 1.2. This branch's plans, counted and compared with the base

- [x] **1.2** This branch plans both documents with the same rows and fewer lookups.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's154'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[([string]$Ids[$K].Id).ToLowerInvariant()] = $K }
function L([string]$V) { [regex]::Replace($V, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { param($Hit) $Key = $Hit.Value.ToLowerInvariant(); if ($Label.ContainsKey($Key)) { $Label[$Key] } else { 'another-id' } }) }
$Base = Get-Content (Join-Path $Raw 'base-plans.json') -Raw | ConvertFrom-Json -AsHashtable
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
& $M {
    Set-Item -Path 'function:script:Invoke-OERGraphRequestS154' -Value ${function:Invoke-OERGraphRequest}
    $script:S154Refused = [System.Collections.Generic.List[string]]::new()
    function script:Invoke-OERGraphRequest {
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        if ($Method -ne 'GET' -and $Uri -notmatch '/getMemberGroups$|directoryObjects/getByIds$') {
            $script:S154Refused.Add($Method)
            throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S154 fence: write refused'), 'S154FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        }
        Invoke-OERGraphRequestS154 @PSBoundParameters
    }
}
Write-OerLiveStep "Fence installed (plans only, every write refused): $([bool](& $M { Get-Command Invoke-OERGraphRequestS154 -ErrorAction SilentlyContinue }))"
foreach ($Case in @(@{ Doc = 'mcr'; Prune = $false }, @{ Doc = 'rr'; Prune = $true })) {
    $P = @{ Path = (Join-Path $Raw "structure-$($Case.Doc).json"); WhatIf = $true; Verbose = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'script:E' }
    if ($Case.Prune) { $P.Prune = $true }
    $script:E = $null
    $All = @(Invoke-OERStructure @P 4>&1 3>$null)
    $Lines = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message } | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ' })
    $Rows = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] } | ForEach-Object { [ordered]@{ Section = [string]$_.Section; Item = [string]$_.Item; Action = [string]$_.Action; Detail = [string]$_.Detail } })
    $Count = [ordered]@{
        Role      = @($Lines | Where-Object { $_ -match 'roleManagement/directory/roleDefinitions' }).Count
        Principal = @($Lines | Where-Object { $_ -match ' v1\.0/(groups|users|servicePrincipals)\?' }).Count
        Schedules = @($Lines | Where-Object { $_ -match 'roleEligibilitySchedules|roleAssignmentSchedules' }).Count
        Total     = $Lines.Count
    }
    $Count.Other = $Count.Total - $Count.Role - $Count.Principal - $Count.Schedules
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    $Name = "$($Case.Doc)$(if ($Case.Prune) { ' -Prune' })"
    $Was = $Base[$Name]
    $Same = ((@($Rows) | ConvertTo-Json -Depth 4 -Compress) -ceq (@($Was.Rows) | ForEach-Object { [ordered]@{ Section = $_.Section; Item = $_.Item; Action = $_.Action; Detail = $_.Detail } } | ConvertTo-Json -Depth 4 -Compress)) -and (($Own -join ',') -ceq (@($Was.Own) -join ','))
    Write-OerLiveStep "branch plan ${Name}: requests role $($Count.Role) (base $($Was.Count.Role)), principal $($Count.Principal) (base $($Was.Count.Principal)), schedules $($Count.Schedules) (base $($Was.Count.Schedules)), other $($Count.Other) (base $($Was.Count.Other)), total $($Count.Total) (base $($Was.Count.Total)); own errors: $($Own -join ', ')"
    Write-OerLiveStep "branch plan ${Name}: rows and own errors identical to the base, Detail included: $Same"
    Write-OerLiveStep "branch plan ${Name}: rows: $((@($Rows) | ForEach-Object { '{0} {1} {2}' -f $_.Section, (L $_.Item), $_.Action }) -join '; ')"
}
Write-OerLiveStep "Writes refused by the fence: $((& $M { $script:S154Refused }).Count)"
Disconnect-OerLive
```

**Expect:** `The module is the worktree's build: True`; for both plans `rows and own errors identical
to the base, Detail included: True`; `role` and `principal` lower than the base (with one role named
twice and two group names: role 1 instead of 4 lookups when the name is typed in its exact case,
principal 2 instead of 4), `schedules` and `other` equal to the base; 0 writes refused.
**Failure looks like:** `False` on the identity line, a count higher than the base, or a refused write.

Result: 2026-11-11 18:06 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. This branch planned both documents with rows and own errors identical to the base, Detail included (True, True); mcr: role lookups 1 (base 4), principal 2 (base 4), schedules 3 (base 3), 6 requests in all (base 11); rr -Prune: role 1 (base 4), principal 2 (base 4), schedules 3 (base 3), other 1 (base 1), 7 in all (base 12). 0 writes refused.

[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] The module is the worktree's build: True
[oer-s154] Fence installed (plans only, every write refused): True
What if: Performing the operation "create eligible directory role assignment" on target "Message Center Reader -> oer-s154-g1 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Message Center Reader -> oer-s154-g2 (Eligible)".
[oer-s154] branch plan mcr: requests role 1 (base 4), principal 2 (base 4), schedules 3 (base 3), other 0 (base 0), total 6 (base 11); own errors: 
[oer-s154] branch plan mcr: rows and own errors identical to the base, Detail included: True
[oer-s154] branch plan mcr: rows: directoryRoleAssignments Message Center Reader -> oer-s154-g1 (Eligible) Skipped; directoryRoleAssignments Message Center Reader -> oer-s154-g2 (Eligible) Skipped
What if: Performing the operation "Remove undeclared eligible directory role assignment" on target "Reports Reader -> 00000000-0000-0000-0000-000000000006 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s154-g1 (Eligible)".
What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s154-g2 (Eligible)".
[oer-s154] branch plan rr -Prune: requests role 1 (base 4), principal 2 (base 4), schedules 3 (base 3), other 1 (base 1), total 7 (base 12); own errors: 
[oer-s154] branch plan rr -Prune: rows and own errors identical to the base, Detail included: True
[oer-s154] branch plan rr -Prune: rows: directoryRoleAssignments Reports Reader -> g3 (Eligible) Skipped; directoryRoleAssignments Reports Reader -> oer-s154-g1 (Eligible) Skipped; directoryRoleAssignments Reports Reader -> oer-s154-g2 (Eligible) Skipped
[oer-s154] Writes refused by the fence: 0
```

### 1.3. Applied twice without -Prune: Created, then only Unchanged (G8)

- [x] **1.3** `structure-mcr.json` creates the two Message Center Reader assignments, and a second run is only `Unchanged`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's154'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[([string]$Ids[$K].Id).ToLowerInvariant()] = $K }
function L([string]$V) { [regex]::Replace($V, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { param($Hit) $Key = $Hit.Value.ToLowerInvariant(); if ($Label.ContainsKey($Key)) { $Label[$Key] } else { 'another-id' } }) }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
$G1 = [string]$Ids['g1'].Id; $G2 = [string]$Ids['g2'].Id
$Rd = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq 'Message Center Reader'&`$select=id"
$RoleId = [string]@($Rd.Body.value)[0].id
& $M {
    param($Allowed)
    Set-Item -Path 'function:script:Invoke-OERGraphRequestS154' -Value ${function:Invoke-OERGraphRequest}
    $script:S154Allowed = $Allowed
    $script:S154Refused = [System.Collections.Generic.List[string]]::new()
    $script:S154Sent = [System.Collections.Generic.List[string]]::new()
    function script:Invoke-OERGraphRequest {
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        if ($Method -ne 'GET' -and $Uri -notmatch '/getMemberGroups$|directoryObjects/getByIds$') {
            $Ok = $Uri -match 'roleManagement/directory/roleEligibilityScheduleRequests$' -and $Body -and [string]$Body.action -eq 'adminAssign' -and
                [string]$Body.roleDefinitionId -eq $script:S154Allowed.RoleId -and $script:S154Allowed.Principals -contains [string]$Body.principalId
            if (-not $Ok) {
                $script:S154Refused.Add($Method)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S154 fence: write refused'), 'S154FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            $script:S154Sent.Add([string]$Body.principalId)
        }
        Invoke-OERGraphRequestS154 @PSBoundParameters
    }
} @{ RoleId = $RoleId; Principals = @($G1, $G2) }
Write-OerLiveStep "Fence installed (only adminAssign of Message Center Reader for g1 and g2): $([bool](& $M { Get-Command Invoke-OERGraphRequestS154 -ErrorAction SilentlyContinue }))"
$Doc = Join-Path $Raw 'structure-mcr.json'
foreach ($Run in 'first', 'second') {
    $script:E = $null
    $All = @(Invoke-OERStructure -Path $Doc -Confirm:$false -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 4>&1 3>$null)
    $Lines = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message } | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ' })
    $Rows = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$Run run: requests role $(@($Lines | Where-Object { $_ -match 'roleManagement/directory/roleDefinitions' }).Count), principal $(@($Lines | Where-Object { $_ -match ' v1\.0/(groups|users|servicePrincipals)\?' }).Count), total $($Lines.Count); own errors: $($Own -join ', ')"
    Write-OerLiveStep "$Run run: rows: $((@($Rows) | ForEach-Object { '{0} {1}' -f (L $_.Item), $_.Action }) -join '; ')"
    if ($Run -eq 'first') {
        $null = Wait-OerLiveConverged -Activity 'both Message Center Reader eligible schedules listed' -Read {
            $R = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleEligibilitySchedules?`$filter=roleDefinitionId eq '$RoleId'" -All
            if ($R.Ok) { , @($R.Body.value | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.principalId }) } else { $null }
        } -Test { $V = $args[0]; $null -ne $V -and @($V) -contains $G1 -and @($V) -contains $G2 }
        Start-Sleep -Seconds 30
    }
}
Write-OerLiveStep "Writes sent: $((& $M { $script:S154Sent }) | ForEach-Object { L $_ })"
Write-OerLiveStep "Writes refused by the fence: $((& $M { $script:S154Refused }).Count)"
Disconnect-OerLive
```

**Expect:** first run: `Message Center Reader -> oer-s154-g1 (Eligible) Created` and the same for
`g2`, role 1 and principal 2 requests; second run: the same two rows `Unchanged` and nothing else,
the same lookup counts; `Writes sent: g1 g2`; 0 writes refused; no own error.
**Failure looks like:** a second `Created`, an `Extra` row, a refused write or an own error.

Result: 2026-11-11 18:07 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The first run created both Message Center Reader eligible assignments (g1, g2) with 1 role and 2 principal lookups (10 requests, the creates' own reads included); the schedules listed at the first read; the second run, 30 s later, was only Unchanged for both, with 1 role and 2 principal lookups (6 requests). Writes sent: g1, g2; 0 refused; no own error (G8).

[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] Fence installed (only adminAssign of Message Center Reader for g1 and g2): True
[oer-s154] first run: requests role 1, principal 2, total 10; own errors: 
[oer-s154] first run: rows: Message Center Reader -> oer-s154-g1 (Eligible) Created; Message Center Reader -> oer-s154-g2 (Eligible) Created
[oer-s154] both Message Center Reader eligible schedules listed: converged after 1 read(s), 0.4 s.
[oer-s154] second run: requests role 1, principal 2, total 6; own errors: 
[oer-s154] second run: rows: Message Center Reader -> oer-s154-g1 (Eligible) Unchanged; Message Center Reader -> oer-s154-g2 (Eligible) Unchanged
[oer-s154] Writes sent: g1 g2
[oer-s154] Writes refused by the fence: 0
```

### 1.4. Applied twice with -Prune: g3's assignment removed, then only Unchanged (G8)

- [x] **1.4** `structure-rr.json` with `-Prune` creates the two Reports Reader assignments and removes `g3`'s; a second run is only `Unchanged`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's154'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[([string]$Ids[$K].Id).ToLowerInvariant()] = $K }
function L([string]$V) { [regex]::Replace($V, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { param($Hit) $Key = $Hit.Value.ToLowerInvariant(); if ($Label.ContainsKey($Key)) { $Label[$Key] } else { 'another-id' } }) }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
$G1 = [string]$Ids['g1'].Id; $G2 = [string]$Ids['g2'].Id; $G3 = [string]$Ids['g3'].Id
$Rd = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq 'Reports Reader'&`$select=id"
$RoleId = [string]@($Rd.Body.value)[0].id
& $M {
    param($Allowed)
    Set-Item -Path 'function:script:Invoke-OERGraphRequestS154' -Value ${function:Invoke-OERGraphRequest}
    $script:S154Allowed = $Allowed
    $script:S154Refused = [System.Collections.Generic.List[string]]::new()
    $script:S154Sent = [System.Collections.Generic.List[string]]::new()
    function script:Invoke-OERGraphRequest {
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        if ($Method -ne 'GET' -and $Uri -notmatch '/getMemberGroups$|directoryObjects/getByIds$') {
            $Ok = $Uri -match 'roleManagement/directory/roleEligibilityScheduleRequests$' -and $Body -and [string]$Body.roleDefinitionId -eq $script:S154Allowed.RoleId -and (
                ([string]$Body.action -eq 'adminAssign' -and $script:S154Allowed.Assign -contains [string]$Body.principalId) -or
                ([string]$Body.action -eq 'adminRemove' -and [string]$Body.principalId -eq $script:S154Allowed.Remove))
            if (-not $Ok) {
                $script:S154Refused.Add($Method)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S154 fence: write refused'), 'S154FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            $script:S154Sent.Add("$([string]$Body.action) $([string]$Body.principalId)")
        }
        Invoke-OERGraphRequestS154 @PSBoundParameters
    }
} @{ RoleId = $RoleId; Assign = @($G1, $G2); Remove = $G3 }
Write-OerLiveStep "Fence installed (only adminAssign of Reports Reader for g1 and g2, adminRemove for g3): $([bool](& $M { Get-Command Invoke-OERGraphRequestS154 -ErrorAction SilentlyContinue }))"
$Doc = Join-Path $Raw 'structure-rr.json'
foreach ($Run in 'first', 'second') {
    $script:E = $null
    $All = @(Invoke-OERStructure -Path $Doc -Prune -Confirm:$false -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 4>&1 3>$null)
    $Lines = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message } | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ' })
    $Rows = @($All | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$Run run: requests role $(@($Lines | Where-Object { $_ -match 'roleManagement/directory/roleDefinitions' }).Count), principal $(@($Lines | Where-Object { $_ -match ' v1\.0/(groups|users|servicePrincipals)\?' }).Count), total $($Lines.Count); own errors: $($Own -join ', ')"
    Write-OerLiveStep "$Run run: rows: $((@($Rows) | ForEach-Object { '{0} {1}' -f (L $_.Item), $_.Action }) -join '; ')"
    if ($Run -eq 'first') {
        $null = Wait-OerLiveConverged -Activity 'Reports Reader eligible schedules: g1 and g2 listed, g3 gone' -Read {
            $R = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleEligibilitySchedules?`$filter=roleDefinitionId eq '$RoleId'" -All
            if ($R.Ok) { , @($R.Body.value | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.principalId }) } else { $null }
        } -Test { $V = $args[0]; $null -ne $V -and @($V) -contains $G1 -and @($V) -contains $G2 -and @($V) -notcontains $G3 } -BudgetSeconds 420
        Start-Sleep -Seconds 30
    }
}
Write-OerLiveStep "Writes sent: $((& $M { $script:S154Sent }) | ForEach-Object { L $_ })"
Write-OerLiveStep "Writes refused by the fence: $((& $M { $script:S154Refused }).Count)"
Disconnect-OerLive
```

**Expect:** first run: `Reports Reader -> g3 (Eligible) Removed`, then
`Reports Reader -> oer-s154-g1 (Eligible) Created` and the same for `g2`, role 1 and principal 2
requests; second run: the two rows `Unchanged` and nothing else; `Writes sent: adminRemove g3
adminAssign g1 adminAssign g2` (in the order sent); 0 writes refused; no own error.
**Failure looks like:** a second `Created` or `Removed`, an `Extra` row, a refused write or an own
error.

Result: 2026-11-11 18:08 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. With -Prune the first run removed g3's undeclared Reports Reader eligible assignment and created g1's and g2's, with 1 role and 2 principal lookups (12 requests); the schedules showed g1 and g2 and no g3 at the first read; the second run, 30 s later, was only Unchanged for g1 and g2 (no Extra, no Removed), 6 requests. Writes sent: adminRemove g3, adminAssign g1, adminAssign g2; 0 refused; no own error (G8).

[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] Fence installed (only adminAssign of Reports Reader for g1 and g2, adminRemove for g3): True
[oer-s154] first run: requests role 1, principal 2, total 12; own errors: 
[oer-s154] first run: rows: Reports Reader -> g3 (Eligible) Removed; Reports Reader -> oer-s154-g1 (Eligible) Created; Reports Reader -> oer-s154-g2 (Eligible) Created
[oer-s154] Reports Reader eligible schedules: g1 and g2 listed, g3 gone: converged after 1 read(s), 0.4 s.
[oer-s154] second run: requests role 1, principal 2, total 6; own errors: 
[oer-s154] second run: rows: Reports Reader -> oer-s154-g1 (Eligible) Unchanged; Reports Reader -> oer-s154-g2 (Eligible) Unchanged
[oer-s154] Writes sent: adminRemove g3 adminAssign g1 adminAssign g2
[oer-s154] Writes refused by the fence: 0
```

## 2. A review is created only on a proven empty answer (B)

### 2.1. Created when none exists, then Unchanged (G8)

- [x] **2.1** The plan would create `oer-s154-ar`; the first run creates it, and the second is `Unchanged`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s154-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's154'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
$Doc = Join-Path $Raw 'structure-ar.json'
if (-not (Test-Path -LiteralPath $Doc)) {
    $Start = (Get-Date).ToUniversalTime().AddDays(7).ToString('yyyy-MM-dd')
    [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{ displayName = 'oer-s154-ar'; group = 'oer-s154-g1'; reviewers = @('self'); recurrence = 'OneTime'; startDate = $Start; durationInDays = 3; descriptionForAdmins = 'Sprint 15 step 4 live check (oer-s154-)' }) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Doc -Encoding utf8NoBOM
}
& $M {
    Set-Item -Path 'function:script:Invoke-OERGraphRequestS154' -Value ${function:Invoke-OERGraphRequest}
    $script:S154Refused = [System.Collections.Generic.List[string]]::new()
    $script:S154Sent = [System.Collections.Generic.List[string]]::new()
    function script:Invoke-OERGraphRequest {
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        if ($Method -ne 'GET' -and $Uri -notmatch '/getMemberGroups$|directoryObjects/getByIds$') {
            $Ok = $Method -eq 'POST' -and $Uri -match 'identityGovernance/accessReviews/definitions$' -and $Body -and [string]$Body.displayName -ceq 'oer-s154-ar' -and $script:S154Sent.Count -eq 0
            if (-not $Ok) {
                $script:S154Refused.Add($Method)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S154 fence: write refused'), 'S154FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            $script:S154Sent.Add('create oer-s154-ar')
        }
        Invoke-OERGraphRequestS154 @PSBoundParameters
    }
}
Write-OerLiveStep "Fence installed (one create of oer-s154-ar, nothing else): $([bool](& $M { Get-Command Invoke-OERGraphRequestS154 -ErrorAction SilentlyContinue }))"
foreach ($Run in 'plan', 'first', 'second') {
    $script:E = $null
    $Rows = if ($Run -eq 'plan') { @(Invoke-OERStructure -Path $Doc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable script:E 3>$null) } else { @(Invoke-OERStructure -Path $Doc -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E 3>$null) }
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "${Run}: own errors: $($Own -join ', '); rows: $((@($Rows) | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Item, $_.Action }) -join '; ')"
    if ($Run -eq 'first') {
        $null = Wait-OerLiveConverged -Activity 'oer-s154-ar listed by its name' -Read {
            $R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq 'oer-s154-ar'"
            if ($R.Ok) { , @($R.Body.value | Where-Object { $null -ne $_ }) } else { $null }
        } -Test { $V = $args[0]; $null -ne $V -and @($V).Count -eq 1 }
        Start-Sleep -Seconds 30
    }
}
$R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq 'oer-s154-ar'"
Write-OerLiveStep "Definitions named oer-s154-ar after the runs: $(@($R.Body.value | Where-Object { $null -ne $_ }).Count)"
Write-OerLiveStep "Writes sent: $((& $M { $script:S154Sent }) -join ', ')"
Write-OerLiveStep "Writes refused by the fence: $((& $M { $script:S154Refused }).Count)"
Disconnect-OerLive
```

**Expect:** `plan`: `accessReviews oer-s154-ar Skipped`; `first`: `accessReviews oer-s154-ar Created`;
`second`: `accessReviews oer-s154-ar Unchanged`; no own error in any run (no
`AccessReviewAbsenceUnproven`); one definition named `oer-s154-ar`; `Writes sent: create
oer-s154-ar`; 0 writes refused.
**Failure looks like:** `Failed` with `AccessReviewAbsenceUnproven` on the plan or the first run (the
real read did not publish its not-found answer), a second create, or a refused write.

Result: 2026-11-11 18:09 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The plan said would create (Skipped) with no own error, so the real Get-OERAccessReviewDefinition published its not-found answer against Graph and the stricter rule accepted it; the first run created oer-s154-ar; the definition was listed at the first read; the second run was Unchanged (G8). No AccessReviewAbsenceUnproven anywhere; one definition of that name; one create sent, 0 refused.

[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s154] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s154] Fence installed (one create of oer-s154-ar, nothing else): True
What if: Performing the operation "Create access review definition" on target "oer-s154-ar".
[oer-s154] plan: own errors: ; rows: accessReviews oer-s154-ar Skipped
[oer-s154] first: own errors: ; rows: accessReviews oer-s154-ar Created
[oer-s154] oer-s154-ar listed by its name: converged after 1 read(s), 0.4 s.
[oer-s154] second: own errors: ; rows: accessReviews oer-s154-ar Unchanged
[oer-s154] Definitions named oer-s154-ar after the runs: 1
[oer-s154] Writes sent: create oer-s154-ar
[oer-s154] Writes refused by the fence: 0
```

## T. Teardown

### T.1. Every prefixed object is removed

- [x] **T.1** The teardown removes every `oer-s154-` object and assignment, and the sweep is 0.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS154Prereq.ps1 -Teardown -Unattended
```

**Expect:** the access review definition, the four eligible assignments and the three groups
removed; `Teardown complete: the sweep is 0.`; both roles back at their baseline counts.
**Failure looks like:** `Left:` lines or a count above the baseline -- run it again later, and name
every remainder in the report.

Result: 2026-11-11 18:10 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The teardown removed 8 objects: the four eligible assignments of g1 and g2 (g3's had been removed by the -Prune run of 1.4), the access review definition oer-s154-ar and the three groups; residue 0. The sweep listed the three deleted groups once (listing lag) and was 0 thirty seconds later; both roles are back at their baseline (0 eligible, 0 active).

[oer-s154] Transcript (redacted): raw\s154\prereq-teardown-20261111-180928Z.log; OerLive 1.1.0.
[oer-s154] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg4\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s154] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s154] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s154] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s154-', the other 5 are left untouched.
[oer-s154] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s154] Teardown of 'oer-s154-': users 0, groups 3, access packages 0, access review definitions 1, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s154] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s154] Removed: oer-s154-g1: eligible 'Reports Reader' assignment at directory scope '/' (201).
[oer-s154] Removed: oer-s154-g1: eligible 'Message Center Reader' assignment at directory scope '/' (201).
[oer-s154] oer-s154-g1: no direct directory role schedule listed: not yet (read 1, 0.8 s, likely replication delay) -- reading again in 2 s.
[oer-s154] oer-s154-g1: no direct directory role schedule listed: converged after 2 read(s), 3.7 s.
[oer-s154] Removed: oer-s154-g2: eligible 'Reports Reader' assignment at directory scope '/' (201).
[oer-s154] Removed: oer-s154-g2: eligible 'Message Center Reader' assignment at directory scope '/' (201).
[oer-s154] oer-s154-g2: no direct directory role schedule listed: converged after 1 read(s), 0.7 s.
[oer-s154] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s154] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s154] Deleted: access review definition oer-s154-ar (204).
[oer-s154] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s154] Teardown 5/6: the prefixed groups.
[oer-s154] Deleted: group oer-s154-g1 (204).
[oer-s154] Deleted: group oer-s154-g2 (204).
[oer-s154] Deleted: group oer-s154-g3 (204).
[oer-s154] Teardown 6/6: the prefixed users.
[oer-s154] Teardown of 'oer-s154-': removed 8, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s154] Teardown summary: Removed 8, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s154] Sweep: 3 object(s) with the prefix, 0 unread kind(s).
[oer-s154] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s154-' is left.
[oer-s154] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s154] Role Reports Reader after teardown: eligible 0, active 0 (baseline eligible 0, active 0).
[oer-s154] Role Message Center Reader after teardown: eligible 0, active 0 (baseline eligible 0, active 0).
[oer-s154] Teardown complete: the sweep is 0.
```
