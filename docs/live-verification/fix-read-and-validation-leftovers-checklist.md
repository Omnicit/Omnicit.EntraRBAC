# Live verification checklist -- read and validation leftovers (fix/read-and-validation-leftovers)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s162-`.** The
prerequisite script creates one security group without members or owners, `oer-s162-g1`. Check 1.1
writes, through `Invoke-OERStructure`, a catalog `oer-s162-cat`, an access package `oer-s162-ap` in it
with one assignment policy `oer-s162-pol` (administrator assignment only, requestor scope
`NotSpecified`, no approval) and a one-time access review `oer-s162-ar` of `oer-s162-g1`'s members.
Every other block only reads. No policy of any role or object is changed.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS162Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s162/`
(git-ignored). Every block prints through the library's redactor and prints counts, keys and
True/False only, never an object id, a display name read from the tenant or an error record. **No
credential, token, application id or certificate thumbprint is ever printed.**

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. Access review reads refuse an answer without a value list** ("read access review definitions'
  first page with RequireValue"). `Get-OERAccessReviewDefinition -DisplayName` and `-All` now read
  their first page as `-Filter` already did: a page without `value` is published as
  `GraphPagingIncomplete`, never read as no definitions. A well-formed answer changes nothing.
- **B. A piped assignment policy binds its access package id** ("bind a piped policy's access package
  id in Get-OERAccessPackageAssignmentPolicy"). `-AccessPackage` lists `AccessPackageId` before
  `DisplayName` in its aliases.
- **C. The validator checks more** ("check requestorScope.scope offline against one owner of the scope
  list", and the commits for `authenticationContextId` and the GUID-form unit names):
  `requestorScope.scope` against the scope list `New-OERAccessPackageRequestorScope` also reads,
  `authenticationContextId` as a string with `\A`/`\z`, and Warnings for an administrative unit name or
  a group's `administrativeUnit` in the form of an object id.
- **D.** `Format-OERUnreadCauseClause` drops exactly one closing full stop of a cause.

A live tenant is needed for what mocks cannot show: that the real Microsoft Graph answers for
`-All` and `-DisplayName` still produce exactly the objects the base build produced (A); that a real
assignment policy object, piped back into the cmdlet, lists its package's policies (B); that the
builder, now reading its scope map from the new owner, still writes and converges (G8); and that a
fresh export of the test tenant raises no new Error under the stricter validator (C).

## What this file does not check, and why

- **An answer without `value`** cannot be produced live: Microsoft Graph answers the definitions
  list with a `value` member. Class B: the tests named in the step's report drive the shape offline,
  with the real `Get-OERAccessReviewDefinition` under `Get-OERInventory`.
- **The validation cases of C and D** (a scope outside the list, `["c1"]`, `c1` with a line break,
  a GUID-form unit name, an ellipsis cause) are offline by nature. Class B: the unit tests named in the
  step's report.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS162Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERRequestorScopeMap' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "[Alias('AccessPackageId', 'DisplayName')]" -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result: 2026-11-12 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main; the worktree on fix/read-and-validation-leftovers at cd9f8fa with 0 tracked changes; the build carries A and B.

[oer-s162] The module loads from a worktree that is not the main clone: True
[oer-s162] Main clone: branch main
[oer-s162] Worktree: branch fix/read-and-validation-leftovers; HEAD cd9f8fa test: comment and help cosmetics of the read and validation leftovers; tracked changes: 0
[oer-s162] The worktree's build carries A: True; B: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** `identity check passed: True`; `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or "application is disabled" -- STOP.

Result: 2026-11-12 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The ARM module session as oer-live-cc passes every identity check line; the module loaded is the worktree's build (1.7.1).

[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s162] The module is the worktree's build: True
```

### 0.2. The prerequisite script's plan

- [x] **0.2** `-WhatIf` plans only `oer-s162-` objects. #type/subtask
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS162Prereq.ps1 -WhatIf
```

**Expect:** the three permissions `True`; every `What if` line names an `oer-s162-` object (or, on a
re-run, none: the group exists).
**Failure looks like:** a target without the prefix, or a `STOP` -- STOP.

Result: 2026-11-12 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. All three permissions held; the sweep of the prefix is 0; the only object the plan creates is oer-s162-g1.

What if: Performing the operation "Create Directory" on target "Destination: REPO\docs\live-verification\raw\s162".
What if: Performing the operation "Start the redacted transcript" on target "raw\s162\prereq-20261112-160015Z.log".
[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s162] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s162-', the other 5 are left untouched.
[oer-s162] Permission held: Group.ReadWrite.All: True
[oer-s162] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s162] Permission held: AccessReview.ReadWrite.All: True
[oer-s162] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s162-' is left.
What if: Performing the operation "Write the baseline" on target "raw\s162\baseline-prereq.json".
[oer-s162] Baseline sweep: 0 object(s) with the prefix before this run.
What if: Performing the operation "Create security group (no members, no owners)" on target "oer-s162-g1".
```

### 0.3. The prerequisite script, for real

- [x] **0.3** The group `oer-s162-g1` exists. #type/subtask
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS162Prereq.ps1 -Unattended
```

**Expect:** `Created group oer-s162-g1.` (or found); `Read back group g1: True`.
**Failure looks like:** a `STOP`, or `False` on the read back.

Result: 2026-11-12 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The baseline (sweep 0) was written before the first write; oer-s162-g1 was created and read back by id.

[oer-s162] Transcript (redacted): raw\s162\prereq-20261112-160032Z.log; OerLive 1.1.0.
[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s162] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s162-', the other 5 are left untouched.
[oer-s162] Permission held: Group.ReadWrite.All: True
[oer-s162] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s162] Permission held: AccessReview.ReadWrite.All: True
[oer-s162] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s162-' is left.
[oer-s162] Baseline sweep: 0 object(s) with the prefix before this run.
[oer-s162] Created group oer-s162-g1.
[oer-s162] read v1.0/groups/00000000-0000-0000-0000-000000000004?$select=id answered 404 Request_ResourceNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s162] Read back group g1: True
```

## 1. The objects the reads need, written twice (G8)

### 1.1. Catalog, access package, policy and review: Created, then only Unchanged

- [x] **1.1** `Invoke-OERStructure` plans, creates and then finds unchanged the four objects; the policy's requestor scope goes through the builder's new scope map. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's162'
$Start = (Get-Date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-dd')
$Doc = Join-Path $Raw 'structure-objects.json'
if (-not (Test-Path -LiteralPath $Doc)) {
    [ordered]@{
        version        = '1.0'
        catalogs       = @([ordered]@{ displayName = 'oer-s162-cat'; description = 'Sprint 16 step 2 live check (oer-s162-)'; resources = @() })
        accessPackages = @([ordered]@{
                displayName = 'oer-s162-ap'; catalog = 'oer-s162-cat'; description = 'Sprint 16 step 2 live check (oer-s162-)'; resourceRoles = @()
                assignmentPolicies = @([ordered]@{ displayName = 'oer-s162-pol'; description = 'Sprint 16 step 2 live check (oer-s162-)'; requestorScope = [ordered]@{ scope = 'NotSpecified' }; requireApproval = $false; durationInDays = 30 })
            })
        accessReviews  = @([ordered]@{ displayName = 'oer-s162-ar'; group = 'oer-s162-g1'; reviewers = @('self'); recurrence = 'OneTime'; startDate = $Start; durationInDays = 3; descriptionForAdmins = 'Sprint 16 step 2 live check (oer-s162-)' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Doc -Encoding utf8NoBOM
}
Connect-OerLive -Arm
foreach ($Run in 'plan', 'first', 'second') {
    $P = @{ Path = $Doc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'script:E'; Include = @('Catalogs', 'AccessPackages', 'AccessReviews') }
    if ($Run -eq 'plan') { $P.WhatIf = $true } else { $P.Confirm = $false }
    $script:E = $null
    $Rows = @(Invoke-OERStructure @P 3>$null)
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "${Run}: own errors: $($Own -join ', '); rows: $((@($Rows | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Item, $_.Action })) -join '; ')"
    if ($Run -eq 'first') { Start-Sleep -Seconds 30 }
}
Disconnect-OerLive
```

**Expect:** `plan`: every row `Skipped` (would create), no own error; `first`: the catalog, the access
package, the policy and the review `Created`; `second`: every row `Unchanged` (G8), no own error.
**Failure looks like:** an own error, a `Failed` row, or a second run with a change.

Result: 2026-11-12 16:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS (second attempt). The first attempt ran the real runs without -Confirm:$false in a redirected child process: every entry was reported Failed with the engine's own 'the host cannot show the confirmation prompt' text and nothing was written (a defect of the block, corrected in both files). Rerun: the plan was Skipped with no own error; the first run created the catalog, the access package, its policy and the review; the second run was Unchanged for all four rows (G8), no own error.

[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create catalog" on target "oer-s162-cat".
What if: Performing the operation "Create access package" on target "oer-s162-ap".
What if: Performing the operation "Create access review definition" on target "oer-s162-ar".
[oer-s162] plan: own errors: ; rows: catalogs oer-s162-cat Skipped; accessPackages oer-s162-ap Skipped; accessPackages oer-s162-ap Skipped; accessReviews oer-s162-ar Skipped
[oer-s162] first: own errors: ; rows: catalogs oer-s162-cat Created; accessPackages oer-s162-ap Created; accessPackages oer-s162-ap Created; accessReviews oer-s162-ar Created
[oer-s162] second: own errors: ; rows: catalogs oer-s162-cat Unchanged; accessPackages oer-s162-ap Unchanged; accessPackages oer-s162-ap Unchanged; accessReviews oer-s162-ar Unchanged
```

## 2. The reads give what the base build gave (A, B)

### 2.1. The base build's reads, recorded

- [x] **2.1** The base source (`8c33706`) reads every access review definition, the review by name and by wildcard, and the package's policies through both pipes; the answers are recorded. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's162'
$BaseDir = Join-Path $Raw 'base-8c33706'
if (-not (Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))) {
    git -C $Cfg.Repo archive --format=zip -o (Join-Path $Raw 'base-8c33706.zip') 8c33706 source
    Expand-Archive -LiteralPath (Join-Path $Raw 'base-8c33706.zip') -DestinationPath $BaseDir -Force
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the base source (8c33706): $($M.ModuleBase.StartsWith($BaseDir, [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read) {
    $script:E = $null
    $Out = @(& $Read | Where-Object { $null -ne $_ })
    [ordered]@{
        Objects = @($Out | Sort-Object { [string]$_.Id } | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors  = @($script:E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    }
}
$Rec = [ordered]@{}
$Rec.All = Get-ReadRecord { Get-OERAccessReviewDefinition -All -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.ByName = Get-ReadRecord { Get-OERAccessReviewDefinition -DisplayName 'oer-s162-ar' -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.ByWildcard = Get-ReadRecord { Get-OERAccessReviewDefinition -DisplayName 'oer-s162-*' -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.PackagePipe = Get-ReadRecord { Get-OERAccessPackage -DisplayName 'oer-s162-ap' -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction SilentlyContinue -ErrorVariable script:E }
$PolicyId = [string](@(Get-OERAccessPackage -DisplayName 'oer-s162-ap' -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction Stop)[0].Id)
$Rec.PolicyPipe = Get-ReadRecord { Get-OERAccessPackageAssignmentPolicy -Id $PolicyId -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'base-reads.json') -Encoding utf8NoBOM
foreach ($K in $Rec.Keys) { Write-OerLiveStep "base ${K}: objects $(@($Rec[$K].Objects).Count); error ids: $(@($Rec[$K].Errors) -join ', ')" }
Disconnect-OerLive
```

**Expect:** the module is the base source; `All` at least 1 object, `ByName` and `ByWildcard` 1 each,
`PackagePipe` 1 (the policy) with no error. `PolicyPipe` is the measurement of the defect B fixes:
the base build binds the policy's own display name as the package name.
**Failure looks like:** an error id on any read but `PolicyPipe`.

Result: 2026-11-12 16:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (8c33706) read 7 access review definitions with -All, 1 by exact name and 1 by wildcard, and the package's 1 policy through the package pipe, with no error. The policy pipe is the measured defect B fixes: the base bound the policy's own display name as the package name and published AccessPackageNotFound.

[oer-s162] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s162] The module is the base source (8c33706): True
[oer-s162] base All: objects 7; error ids: 
[oer-s162] base ByName: objects 1; error ids: 
[oer-s162] base ByWildcard: objects 1; error ids: 
[oer-s162] base PackagePipe: objects 1; error ids: 
[oer-s162] base PolicyPipe: objects 0; error ids: AccessPackageNotFound
```

### 2.2. This branch's reads, compared with the base

- [x] **2.2** This branch's build gives the same objects as the base for every access review read and the package pipe, and the policy pipe now lists the package's policies. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's162'
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read) {
    $script:E = $null
    $Out = @(& $Read | Where-Object { $null -ne $_ })
    [ordered]@{
        Objects = @($Out | Sort-Object { [string]$_.Id } | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors  = @($script:E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    }
}
$Rec = [ordered]@{}
$Rec.All = Get-ReadRecord { Get-OERAccessReviewDefinition -All -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.ByName = Get-ReadRecord { Get-OERAccessReviewDefinition -DisplayName 'oer-s162-ar' -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.ByWildcard = Get-ReadRecord { Get-OERAccessReviewDefinition -DisplayName 'oer-s162-*' -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec.PackagePipe = Get-ReadRecord { Get-OERAccessPackage -DisplayName 'oer-s162-ap' -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction SilentlyContinue -ErrorVariable script:E }
$PolicyId = [string](@(Get-OERAccessPackage -DisplayName 'oer-s162-ap' -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction Stop)[0].Id)
$Rec.PolicyPipe = Get-ReadRecord { Get-OERAccessPackageAssignmentPolicy -Id $PolicyId -ErrorAction Stop | Get-OERAccessPackageAssignmentPolicy -ErrorAction SilentlyContinue -ErrorVariable script:E }
$Rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'branch-reads.json') -Encoding utf8NoBOM
# Graph returns its settings and recurrence bags as hashtables whose key order differs between processes: compare with every key sorted.
function ConvertTo-Canonical($V) { if ($V -is [System.Collections.IDictionary]) { $O = [ordered]@{}; foreach ($K in ($V.Keys | Sort-Object { [string]$_ } -CaseSensitive)) { $O[[string]$K] = ConvertTo-Canonical $V[$K] }; return $O } elseif ($V -is [System.Collections.IList]) { return , @($V | ForEach-Object { ConvertTo-Canonical $_ }) } else { return $V } }
function Get-CanonicalText([object[]]$Objects) { (@($Objects | ForEach-Object { ConvertTo-Canonical ($_ | ConvertFrom-Json -AsHashtable) | ConvertTo-Json -Depth 12 -Compress })) -join "`n" }
$Rec = $Rec | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
$Base = Get-Content -LiteralPath (Join-Path $Raw 'base-reads.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($K in 'All', 'ByName', 'ByWildcard', 'PackagePipe') {
    $Same = ((Get-CanonicalText $Rec[$K].Objects) -ceq (Get-CanonicalText $Base[$K].Objects)) -and ((@($Rec[$K].Errors) -join ',') -ceq (@($Base[$K].Errors) -join ','))
    Write-OerLiveStep "branch ${K}: objects $(@($Rec[$K].Objects).Count) (base $(@($Base[$K].Objects).Count)); error ids: $(@($Rec[$K].Errors) -join ', '); identical to the base: $Same"
}
$PolicySame = (Get-CanonicalText $Rec.PolicyPipe.Objects) -ceq (Get-CanonicalText $Rec.PackagePipe.Objects)
Write-OerLiveStep "branch PolicyPipe: objects $(@($Rec.PolicyPipe.Objects).Count); error ids: $(@($Rec.PolicyPipe.Errors) -join ', '); the package's policies, as the package pipe lists them: $PolicySame (base: objects $(@($Base.PolicyPipe.Objects).Count); error ids: $(@($Base.PolicyPipe.Errors) -join ', '))"
Disconnect-OerLive
```

**Expect:** the module is the worktree's build; `identical to the base: True` for `All`, `ByName`,
`ByWildcard` and `PackagePipe`; `PolicyPipe`: 1 object, no error id, `the package's policies ...: True`.
**Failure looks like:** any `False`, or an error id on this branch's reads.

Result: 2026-11-12 16:05 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS (second run of the block). The first run compared the objects' JSON text as written and reported the three access review reads not identical: the only differing properties were Recurrence and Settings, Graph bags whose key order differs between processes (canonically equal in all 9 objects). The block now compares with every key sorted (both files). Rerun: All (7), ByName (1), ByWildcard (1) and the package pipe (1) identical to the base, no error id; the policy pipe now lists the package's 1 policy, the same as the package pipe, where the base published AccessPackageNotFound.

[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s162] The module is the worktree's build: True
[oer-s162] branch All: objects 7 (base 7); error ids: ; identical to the base: True
[oer-s162] branch ByName: objects 1 (base 1); error ids: ; identical to the base: True
[oer-s162] branch ByWildcard: objects 1 (base 1); error ids: ; identical to the base: True
[oer-s162] branch PackagePipe: objects 1 (base 1); error ids: ; identical to the base: True
[oer-s162] branch PolicyPipe: objects 1; error ids: ; the package's policies, as the package pipe lists them: True (base: objects 0; error ids: AccessPackageNotFound)
```

## 3. A fresh export validates with no new Error (C)

### 3.1. This branch exports the test tenant and validates the export

- [x] **3.1** A fresh `Get-OERInventory` of every section (Azure for the test subscription, its policies for the common roles) is validated by this branch. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's162'
Connect-OerLive -Arm
$Sections = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')
$script:E = $null
$Out = @(Get-OERInventory -Include $Sections -Subscription $Cfg.SubscriptionId -CommonRoles -IncludeARM -ErrorAction SilentlyContinue -ErrorVariable script:E -WarningAction SilentlyContinue -WarningVariable script:W)
$Doc = @($Out | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains 'version' })
Write-OerLiveStep "Export: documents $($Doc.Count); error ids: $(@($script:E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', '); warnings: $(@($script:W).Count)"
foreach ($X in @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId) -like 'InventoryPartial*' })) { Write-OerLiveStep ("InventoryPartial, quoted names masked: {0}" -f ([string]$X.Exception.Message -replace "'[^']{1,120}'", "'name'")) }
$Doc[0] | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $Raw 'export.json') -Encoding utf8NoBOM
foreach ($S in 'groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'accessReviews', 'directoryRoleManagementPolicies', 'directoryRoleAssignments', 'roleAssignments', 'roleManagementPolicies') {
    $V = $Doc[0].$S
    Write-OerLiveStep "Export section ${S}: $(if ($null -eq $V) { 'null' } else { "$(@($V).Count) entr(y/ies)" })"
}
$Result = Test-OERStructure -Path (Join-Path $Raw 'export.json')
$Findings = @($Result.Errors | ForEach-Object { [ordered]@{ Severity = [string]$_.Severity; Path = [string]$_.Path; Message = [string]$_.Message } })
ConvertTo-Json -InputObject @($Findings) -Depth 4 | Set-Content -LiteralPath (Join-Path $Raw 'branch-findings.json') -Encoding utf8NoBOM
Write-OerLiveStep "branch Test-OERStructure: Valid $($Result.Valid); errors $(@($Findings | Where-Object Severity -eq 'Error').Count); warnings $(@($Findings | Where-Object Severity -eq 'Warning').Count)"
Disconnect-OerLive
```

**Expect:** one document; every section read (a count, not `null`); the validation result recorded.
**Failure looks like:** no document, or a section `null` that the identity can read.

Result: 2026-11-12 16:25 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS (fourth run of the block). Runs 1-3 corrected the block, not the module: run 1 exported without -CommonRoles (roleManagementPolicies skipped) and recorded an InventoryPartial whose cause the block did not print (a second export a minute later had none); run 3 wrote no findings file for an empty list (@() piped to ConvertTo-Json writes nothing; now -InputObject). Final run: one document, every section read with a count (no InventoryPartial); the export holds an authenticationContextId in 1 Azure and 1 directory role policy and requestorScope.scope values AllMemberUsers, NotSpecified and SpecificDirectoryUsers (2 each); no administrative unit has a name in object-id form. This branch validates it with 0 errors and 0 warnings.

[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s162] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s162] Export: documents 1; error ids: ; warnings: 2
[oer-s162] Export section groups: 94 entr(y/ies)
[oer-s162] Export section administrativeUnits: 1 entr(y/ies)
[oer-s162] Export section catalogs: 6 entr(y/ies)
[oer-s162] Export section accessPackages: 7 entr(y/ies)
[oer-s162] Export section accessReviews: 6 entr(y/ies)
[oer-s162] Export section directoryRoleManagementPolicies: 22 entr(y/ies)
[oer-s162] Export section directoryRoleAssignments: 51 entr(y/ies)
[oer-s162] Export section roleAssignments: 13 entr(y/ies)
[oer-s162] Export section roleManagementPolicies: 5 entr(y/ies)
[oer-s162] branch Test-OERStructure: Valid True; errors 0; warnings 0
```

### 3.2. The base build validates the same export: no new Error

- [x] **3.2** The base source (`8c33706`) validates the same file; every Error this branch reports, the base reports too. #type/subtask
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s162-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's162'
$BaseDir = Join-Path $Raw 'base-8c33706'
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Force -Global
$Result = Test-OERStructure -Path (Join-Path $Raw 'export.json')
$BaseF = @($Result.Errors | ForEach-Object { [ordered]@{ Severity = [string]$_.Severity; Path = [string]$_.Path; Message = [string]$_.Message } })
$BranchF = @(Get-Content -LiteralPath (Join-Path $Raw 'branch-findings.json') -Raw | ConvertFrom-Json)
$Key = { param($F) '{0}|{1}|{2}' -f $F.Severity, $F.Path, $F.Message }
$BaseKeys = @($BaseF | ForEach-Object { & $Key $_ })
$BranchKeys = @($BranchF | ForEach-Object { & $Key $_ })
$NewErrors = @($BranchF | Where-Object { $_.Severity -eq 'Error' -and $BaseKeys -cnotcontains (& $Key $_) })
$GoneErrors = @($BaseF | Where-Object { $_.Severity -eq 'Error' -and $BranchKeys -cnotcontains (& $Key $_) })
$NewWarnings = @($BranchF | Where-Object { $_.Severity -eq 'Warning' -and $BaseKeys -cnotcontains (& $Key $_) })
Write-OerLiveStep "base Test-OERStructure: Valid $($Result.Valid); errors $(@($BaseF | Where-Object Severity -eq 'Error').Count); warnings $(@($BaseF | Where-Object Severity -eq 'Warning').Count)"
Write-OerLiveStep "Errors only this branch reports: $($NewErrors.Count)$(if ($NewErrors.Count) { ' at ' + ((@($NewErrors | ForEach-Object { $_.Path })) -join ', ') })"
Write-OerLiveStep "Errors only the base reports: $($GoneErrors.Count)"
Write-OerLiveStep "Warnings only this branch reports: $($NewWarnings.Count)$(if ($NewWarnings.Count) { ' at ' + ((@($NewWarnings | ForEach-Object { $_.Path })) -join ', ') })"
```

**Expect:** `Errors only this branch reports: 0`; `Errors only the base reports: 0`; any new Warning is
one of the step's new Warnings (a GUID-form unit name or reference, an `unknownFutureValue` scope),
named by its path.
**Failure looks like:** an Error only this branch reports -- an exported document the stricter
validator refuses (STOP if it is not a defect of the export itself).

Result: 2026-11-12 16:25 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (8c33706) validates the same export.json with 0 errors and 0 warnings; no Error and no Warning only this branch reports, none only the base reports.

[oer-s162] base Test-OERStructure: Valid True; errors 0; warnings 0
[oer-s162] Errors only this branch reports: 0
[oer-s162] Errors only the base reports: 0
[oer-s162] Warnings only this branch reports: 0
```

## T. Teardown

### T.1. Every prefixed object is removed

- [x] **T.1** The teardown removes every `oer-s162-` object, and the sweep is 0. #type/subtask
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS162Prereq.ps1 -Teardown -Unattended
```

**Expect:** the access review definition, the access package (with its policy), the catalog and the
group removed; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result: 2026-11-12 16:26 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The teardown removed 5 objects: the access review definition oer-s162-ar, the assignment policy oer-s162-pol, the access package oer-s162-ap, the catalog oer-s162-cat and the group oer-s162-g1; residue 0. The sweep listed the deleted group once (listing lag) and was 0 thirty seconds later.

[oer-s162] Transcript (redacted): raw\s162\prereq-teardown-20261112-162608Z.log; OerLive 1.1.0.
[oer-s162] Omnicit.EntraRBAC 1.7.1 loaded from REPO\.claude\worktrees\s16-steg2\output\module\Omnicit.EntraRBAC\1.7.1.
[oer-s162] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s162] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s162] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s162-', the other 5 are left untouched.
[oer-s162] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s162] Teardown of 'oer-s162-': users 0, groups 1, access packages 1, access review definitions 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s162] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s162] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s162] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s162] Deleted: access review definition oer-s162-ar (204).
[oer-s162] Deleted: oer-s162-ap: assignment policy 'oer-s162-pol' (204).
[oer-s162] Deleted: access package oer-s162-ap (204, 1 attempt(s)).
[oer-s162] Deleted: catalog oer-s162-cat (204, 1 attempt(s)).
[oer-s162] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s162] Teardown 5/6: the prefixed groups.
[oer-s162] Deleted: group oer-s162-g1 (204).
[oer-s162] Teardown 6/6: the prefixed users.
[oer-s162] Teardown of 'oer-s162-': removed 5, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s162] Teardown summary: Removed 5, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s162] Sweep: 1 object(s) with the prefix, 0 unread kind(s).
[oer-s162] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s162-' is left.
[oer-s162] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s162] Teardown complete: the sweep is 0.
```
