# Live verification checklist -- piped package ids and whole context ids (fix/piped-package-and-whole-context-ids)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s171-`.** The
prerequisite script creates one security group without members or owners, `oer-s171-g1`. Check 1.1
writes, through `Invoke-OERStructure`, a catalog `oer-s171-cat`, an access package `oer-s171-ap` in it
with one assignment policy `oer-s171-pol` (administrator assignment only, requestor scope
`NotSpecified`, no approval) and a one-time access review `oer-s171-ar` of `oer-s171-g1`'s members.
Every other block only reads. No policy of any role or object is changed, and no access package is
assigned to anyone.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS171Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s171/`
(git-ignored). Every block prints through the library's redactor and prints counts, keys and
True/False only, never an object id, a display name read from the tenant or an error record. **No
credential, token, application id or certificate thumbprint is ever printed.**

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. A piped object binds its access package** ("bind a piped AccessPackageId before the object's own
  Id on three cmdlets"). `-AccessPackage` on `Get-OERAccessPackageAssignment`,
  `Add-OERAccessPackageResourceRole` and `New-OERAccessPackageAssignmentPolicy` lists `AccessPackageId`
  before `Id` (and `DisplayName`). A piped object whose `AccessPackageId` is empty is refused: by the
  binding in the two cmdlets where the parameter is mandatory, and with `EmptyAccessPackageId`, nothing
  read, in `Get-OERAccessPackageAssignment`.
- **B. Authentication context ids are read whole** ("read authentication context ids whole in the
  cmdlets and the validator"). `\A` and `\z` in `Set-OERRoleManagementPolicy`,
  `Set-OERDirectoryRoleManagementPolicy`, `Set-OERGroupPimPolicy`, `Get-OERAuthenticationContext` and, new,
  the validator's group `pimPolicy`; letter case unchanged.
- **C. A requestor scope the apply cannot write is a validator Warning** ("warn on a requestor scope the
  owner maps to null in the validator", "stop the requestor scope warning advising a widening and word the
  piped id refusal").
- **D.** Texts and a unit test for a same-account sign-in under another method or client (BL-188 b); no
  code change.

A live tenant is needed for what mocks cannot show: that a real assignment policy object, piped into
`Get-OERAccessPackageAssignment`, reads its own package's assignments, where the base build bound the
policy's own id (A); that a real access package from `Get-OERAccessPackage`, piped the same way, and
the real authentication contexts read exactly what the base build read (A, B); that a real access
review of a group, which names no access package, is refused before any assignment is read (A); and
that a fresh export of the test tenant raises no new Error under the stricter validator (B, C).

## What this file does not check, and why

- **The binding of the two writing cmdlets** (`Add-OERAccessPackageResourceRole`,
  `New-OERAccessPackageAssignmentPolicy`) and **the context id patterns of the three `Set-*` policy
  cmdlets** are class B: their unit tests and the AST cohort named in the step's report hold them;
  running them live would write.
- **The validation cases** (`["c1"]`, `c1` with a line break, a declared
  `SpecificDirectoryServicePrincipals`) are offline by nature. Class B: the unit tests named in the
  step's report. The test tenant holds no policy with that scope, so check 3 cannot meet one.
- **BL-188 (b)** is a text and a unit test about a user sign-in switching method or client; the test
  tenant is driven app-only. Class B.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS171Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "[Alias('AccessPackageId', 'Id', 'DisplayName')]" -Quiet) -and [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'EmptyAccessPackageId'" -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "[ValidatePattern('\Ac\d+\z|\A\z')]" -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result: 2026-11-13 02:41 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main; the worktree on fix/piped-package-and-whole-context-ids at ce55d7c with 0 tracked changes; the build carries A (the alias order and EmptyAccessPackageId) and B (the whole-read pattern).

[oer-s171] The module loads from a worktree that is not the main clone: True
[oer-s171] Main clone: branch main
[oer-s171] Worktree: branch fix/piped-package-and-whole-context-ids; HEAD ce55d7c test: make the piped binding refusal tests independent of the error preference; tracked changes: 0
[oer-s171] The worktree's build carries A: True; B: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** `identity check passed: True`; `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or "application is disabled" -- STOP.

Result: 2026-11-13 02:41 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The ARM module session as oer-live-cc passes every identity check line; the module loaded is the worktree's build (1.7.2).

[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s171] The module is the worktree's build: True
```

### 0.2. The prerequisite script's plan

- [x] **0.2** `-WhatIf` plans only `oer-s171-` objects.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS171Prereq.ps1 -WhatIf
```

**Expect:** the three permissions `True`; every `What if` line names an `oer-s171-` object (or, on a
re-run, none: the group exists).
**Failure looks like:** a target without the prefix, or a `STOP` -- STOP.

Result: 2026-11-13 02:41 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. All three permissions held; the sweep of the prefix is 0; the only object the plan creates is oer-s171-g1.

What if: Performing the operation "Create Directory" on target "Destination: REPO\docs\live-verification\raw\s171".
What if: Performing the operation "Start the redacted transcript" on target "raw\s171\prereq-20261113-024133Z.log".
[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s171] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s171-', the other 5 are left untouched.
[oer-s171] Permission held: Group.ReadWrite.All: True
[oer-s171] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s171] Permission held: AccessReview.ReadWrite.All: True
[oer-s171] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s171-' is left.
What if: Performing the operation "Write the baseline" on target "raw\s171\baseline-prereq.json".
[oer-s171] Baseline sweep: 0 object(s) with the prefix before this run.
What if: Performing the operation "Create security group (no members, no owners)" on target "oer-s171-g1".
```

### 0.3. The prerequisite script, for real

- [x] **0.3** The group `oer-s171-g1` exists.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS171Prereq.ps1 -Unattended
```

**Expect:** `Created group oer-s171-g1.` (or found); `Read back group g1: True`.
**Failure looks like:** a `STOP`, or `False` on the read back.

Result: 2026-11-13 02:42 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The baseline (sweep 0) was written before the first write; oer-s171-g1 was created and read back by id (one 404 on the first read, replication).

[oer-s171] Transcript (redacted): raw\s171\prereq-20261113-024148Z.log; OerLive 1.1.0.
[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s171] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s171-', the other 5 are left untouched.
[oer-s171] Permission held: Group.ReadWrite.All: True
[oer-s171] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s171] Permission held: AccessReview.ReadWrite.All: True
[oer-s171] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s171-' is left.
[oer-s171] Baseline sweep: 0 object(s) with the prefix before this run.
[oer-s171] Created group oer-s171-g1.
[oer-s171] read v1.0/groups/00000000-0000-0000-0000-000000000004?$select=id answered 404 Request_ResourceNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s171] Read back group g1: True
```

## 1. The objects the reads need, written twice (G8)

### 1.1. Catalog, access package, policy and review: Created, then only Unchanged

- [x] **1.1** `Invoke-OERStructure` plans, creates and then finds unchanged the four objects.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's171'
$Start = (Get-Date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-dd')
$Doc = Join-Path $Raw 'structure-objects.json'
if (-not (Test-Path -LiteralPath $Doc)) {
    [ordered]@{
        version        = '1.0'
        catalogs       = @([ordered]@{ displayName = 'oer-s171-cat'; description = 'Sprint 17 step 1 live check (oer-s171-)'; resources = @() })
        accessPackages = @([ordered]@{
                displayName = 'oer-s171-ap'; catalog = 'oer-s171-cat'; description = 'Sprint 17 step 1 live check (oer-s171-)'; resourceRoles = @()
                assignmentPolicies = @([ordered]@{ displayName = 'oer-s171-pol'; description = 'Sprint 17 step 1 live check (oer-s171-)'; requestorScope = [ordered]@{ scope = 'NotSpecified' }; requireApproval = $false; durationInDays = 30 })
            })
        accessReviews  = @([ordered]@{ displayName = 'oer-s171-ar'; group = 'oer-s171-g1'; reviewers = @('self'); recurrence = 'OneTime'; startDate = $Start; durationInDays = 3; descriptionForAdmins = 'Sprint 17 step 1 live check (oer-s171-)' })
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

Result: 2026-11-13 02:42 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The plan was Skipped with no own error; the first run created the catalog, the access package, its policy and the review; the second run was Unchanged for all four rows (G8), no own error.

[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create catalog" on target "oer-s171-cat".
What if: Performing the operation "Create access package" on target "oer-s171-ap".
What if: Performing the operation "Create access review definition" on target "oer-s171-ar".
[oer-s171] plan: own errors: ; rows: catalogs oer-s171-cat Skipped; accessPackages oer-s171-ap Skipped; accessPackages oer-s171-ap Skipped; accessReviews oer-s171-ar Skipped
[oer-s171] first: own errors: ; rows: catalogs oer-s171-cat Created; accessPackages oer-s171-ap Created; accessPackages oer-s171-ap Created; accessReviews oer-s171-ar Created
[oer-s171] second: own errors: ; rows: catalogs oer-s171-cat Unchanged; accessPackages oer-s171-ap Unchanged; accessPackages oer-s171-ap Unchanged; accessReviews oer-s171-ar Unchanged
```

## 2. The reads give what the base build gave, and the policy pipe reads its package (A, B)

### 2.1. The base build's reads, recorded

- [x] **2.1** The base source (`fc8f2fa`) reads the package's assignments by id and through the package, policy and review pipes, and the authentication contexts; the answers and the assignment requests are recorded.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's171'
$BaseDir = Join-Path $Raw 'base-fc8f2fa'
if (-not (Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))) {
    git -C $Cfg.Repo archive --format=zip -o (Join-Path $Raw 'base-fc8f2fa.zip') fc8f2fa source
    Expand-Archive -LiteralPath (Join-Path $Raw 'base-fc8f2fa.zip') -DestinationPath $BaseDir -Force
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the base source (fc8f2fa): $($M.ModuleBase.StartsWith($BaseDir, [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read, [string]$Command, [string]$PackageId) {
    $script:E = $null
    $All = @(& $Read 4>&1)
    $Verbose = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message })
    $Out = @($All | Where-Object { $null -ne $_ -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Requests = @($Verbose | Where-Object { $_.StartsWith('[Invoke-OERGraphRequest] GET ') -and $_.Contains('entitlementManagement/assignments') })
    [ordered]@{
        Objects            = @($Out | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors             = @($script:E | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Select-Object -Unique)
        AssignmentRequests = $Requests.Count
        FilteredOnPackage  = @($Requests | Where-Object { $_.Contains("accessPackage/id eq '$PackageId'") }).Count
    }
}
$Ap = @(Get-OERAccessPackage -DisplayName 'oer-s171-ap' -ErrorAction Stop)[0]
$PackageId = [string]$Ap.Id
$Policy = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $PackageId -ErrorAction Stop)[0]
$Review = @(Get-OERAccessReviewDefinition -DisplayName 'oer-s171-ar' -ErrorAction Stop)[0]
Write-OerLiveStep "Read objects: the policy carries the package's id: $([string]$Policy.AccessPackageId -eq $PackageId); the review carries an AccessPackageId property: $($Review.PSObject.Properties.Name -contains 'AccessPackageId'), empty: $([string]::IsNullOrEmpty([string]$Review.AccessPackageId))"
$G = 'Get-OERAccessPackageAssignment'
$C = 'Get-OERAuthenticationContext'
$Rec = [ordered]@{}
$Rec.Explicit = Get-ReadRecord { Get-OERAccessPackageAssignment -AccessPackage $PackageId -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.PackagePipe = Get-ReadRecord { $Ap | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.PolicyPipe = Get-ReadRecord { $Policy | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.ReviewPipe = Get-ReadRecord { $Review | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.Contexts = Get-ReadRecord { Get-OERAuthenticationContext -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextsAvailable = Get-ReadRecord { Get-OERAuthenticationContext -Available -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'c1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextUpperC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'C1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'base-reads.json') -Encoding utf8NoBOM
foreach ($K in $Rec.Keys) { Write-OerLiveStep "base ${K}: objects $(@($Rec[$K].Objects).Count); own error ids: $(@($Rec[$K].Errors) -join ', '); assignment requests $($Rec[$K].AssignmentRequests), filtered on the package $($Rec[$K].FilteredOnPackage)" }
Disconnect-OerLive
```

**Expect:** the module is the base source; `Explicit` and `PackagePipe` with no error, one assignment
request each, filtered on the package; the three context reads with no error. `PolicyPipe` and
`ReviewPipe` are the measurement of the defect A fixes: the base binds the piped object's own id as the
package and publishes `AccessPackageNotFound`, with no assignment request.
**Failure looks like:** an error id on any read but `PolicyPipe` and `ReviewPipe`.

Result: 2026-11-13 02:43 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (fc8f2fa) read the package's 0 assignments by id and through the package pipe, one assignment request each, filtered on the package, no error; the three context reads returned 3, 2 (available), 1 (c1) and 1 (C1) with no error. The policy pipe and the review pipe are the measured defect A fixes: the base bound the piped object's own id as the package and published AccessPackageNotFound, with no assignment request.

[oer-s171] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s171] The module is the base source (fc8f2fa): True
[oer-s171] Read objects: the policy carries the package's id: True; the review carries an AccessPackageId property: True, empty: True
[oer-s171] base Explicit: objects 0; own error ids: ; assignment requests 1, filtered on the package 1
[oer-s171] base PackagePipe: objects 0; own error ids: ; assignment requests 1, filtered on the package 1
[oer-s171] base PolicyPipe: objects 0; own error ids: AccessPackageNotFound; assignment requests 0, filtered on the package 0
[oer-s171] base ReviewPipe: objects 0; own error ids: AccessPackageNotFound; assignment requests 0, filtered on the package 0
[oer-s171] base Contexts: objects 3; own error ids: ; assignment requests 0, filtered on the package 0
[oer-s171] base ContextsAvailable: objects 2; own error ids: ; assignment requests 0, filtered on the package 0
[oer-s171] base ContextC1: objects 1; own error ids: ; assignment requests 0, filtered on the package 0
[oer-s171] base ContextUpperC1: objects 1; own error ids: ; assignment requests 0, filtered on the package 0
```

### 2.2. This branch's reads, compared with the base

- [x] **2.2** This branch's build gives the same answer as the base for the package's assignments by id, the package pipe and the contexts; the policy pipe now reads its package's assignments, and the review pipe is refused before any assignment request.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's171'
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read, [string]$Command, [string]$PackageId) {
    $script:E = $null
    $All = @(& $Read 4>&1)
    $Verbose = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message })
    $Out = @($All | Where-Object { $null -ne $_ -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Requests = @($Verbose | Where-Object { $_.StartsWith('[Invoke-OERGraphRequest] GET ') -and $_.Contains('entitlementManagement/assignments') })
    [ordered]@{
        Objects            = @($Out | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors             = @($script:E | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Select-Object -Unique)
        AssignmentRequests = $Requests.Count
        FilteredOnPackage  = @($Requests | Where-Object { $_.Contains("accessPackage/id eq '$PackageId'") }).Count
    }
}
$Ap = @(Get-OERAccessPackage -DisplayName 'oer-s171-ap' -ErrorAction Stop)[0]
$PackageId = [string]$Ap.Id
$Policy = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $PackageId -ErrorAction Stop)[0]
$Review = @(Get-OERAccessReviewDefinition -DisplayName 'oer-s171-ar' -ErrorAction Stop)[0]
Write-OerLiveStep "Read objects: the policy carries the package's id: $([string]$Policy.AccessPackageId -eq $PackageId); the review carries an AccessPackageId property: $($Review.PSObject.Properties.Name -contains 'AccessPackageId'), empty: $([string]::IsNullOrEmpty([string]$Review.AccessPackageId))"
$G = 'Get-OERAccessPackageAssignment'
$C = 'Get-OERAuthenticationContext'
$Rec = [ordered]@{}
$Rec.Explicit = Get-ReadRecord { Get-OERAccessPackageAssignment -AccessPackage $PackageId -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.PackagePipe = Get-ReadRecord { $Ap | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.PolicyPipe = Get-ReadRecord { $Policy | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.ReviewPipe = Get-ReadRecord { $Review | Get-OERAccessPackageAssignment -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $G $PackageId
$Rec.Contexts = Get-ReadRecord { Get-OERAuthenticationContext -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextsAvailable = Get-ReadRecord { Get-OERAuthenticationContext -Available -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'c1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextUpperC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'C1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'branch-reads.json') -Encoding utf8NoBOM
function ConvertTo-Canonical($V) { if ($V -is [System.Collections.IDictionary]) { $O = [ordered]@{}; foreach ($K in ($V.Keys | Sort-Object { [string]$_ } -CaseSensitive)) { $O[[string]$K] = ConvertTo-Canonical $V[$K] }; return $O } elseif ($V -is [System.Collections.IList]) { return , @($V | ForEach-Object { ConvertTo-Canonical $_ }) } else { return $V } }
function Get-CanonicalText([object[]]$Objects) { (@($Objects | ForEach-Object { ConvertTo-Canonical ($_ | ConvertFrom-Json -AsHashtable) | ConvertTo-Json -Depth 12 -Compress } | Sort-Object -CaseSensitive)) -join "`n" }
$Rec = $Rec | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
$Base = Get-Content -LiteralPath (Join-Path $Raw 'base-reads.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($K in 'Explicit', 'PackagePipe', 'Contexts', 'ContextsAvailable', 'ContextC1', 'ContextUpperC1') {
    $Same = ((Get-CanonicalText $Rec[$K].Objects) -ceq (Get-CanonicalText $Base[$K].Objects)) -and ((@($Rec[$K].Errors) -join ',') -ceq (@($Base[$K].Errors) -join ',')) -and ($Rec[$K].AssignmentRequests -eq $Base[$K].AssignmentRequests) -and ($Rec[$K].FilteredOnPackage -eq $Base[$K].FilteredOnPackage)
    Write-OerLiveStep "branch ${K}: objects $(@($Rec[$K].Objects).Count) (base $(@($Base[$K].Objects).Count)); own error ids: $(@($Rec[$K].Errors) -join ', '); identical to the base: $Same"
}
$PolicyReadsPackage = ((Get-CanonicalText $Rec.PolicyPipe.Objects) -ceq (Get-CanonicalText $Rec.Explicit.Objects)) -and $Rec.PolicyPipe.AssignmentRequests -ge 1 -and $Rec.PolicyPipe.FilteredOnPackage -eq $Rec.PolicyPipe.AssignmentRequests
Write-OerLiveStep "branch PolicyPipe: objects $(@($Rec.PolicyPipe.Objects).Count); own error ids: $(@($Rec.PolicyPipe.Errors) -join ', '); assignment requests $($Rec.PolicyPipe.AssignmentRequests), every one filtered on the package and answering what -AccessPackage <package id> answers: $PolicyReadsPackage (base: objects $(@($Base.PolicyPipe.Objects).Count); own error ids: $(@($Base.PolicyPipe.Errors) -join ', '))"
Write-OerLiveStep "branch ReviewPipe: objects $(@($Rec.ReviewPipe.Objects).Count); own error ids: $(@($Rec.ReviewPipe.Errors) -join ', '); assignment requests $($Rec.ReviewPipe.AssignmentRequests) (base: objects $(@($Base.ReviewPipe.Objects).Count); own error ids: $(@($Base.ReviewPipe.Errors) -join ', '))"
Write-OerLiveStep "For scale: every assignment in the tenant, unfiltered: $(@(Get-OERAccessPackageAssignment -ErrorAction SilentlyContinue).Count)"
Disconnect-OerLive
```

**Expect:** the module is the worktree's build; `identical to the base: True` for `Explicit`,
`PackagePipe` and the four context reads; `PolicyPipe`: no error id, at least one assignment request,
`... answering what -AccessPackage <package id> answers: True`; `ReviewPipe`: own error id
`EmptyAccessPackageId`, 0 objects, 0 assignment requests.
**Failure looks like:** any `False`; an error id on `PolicyPipe`; an assignment request on `ReviewPipe`.

Result: 2026-11-13 02:43 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Explicit, the package pipe and the four context reads are identical to the base (no error id). The policy pipe now sends one assignment request, filtered on the policy's package, and answers what -AccessPackage with the package id answers (0 assignments; the tenant holds 5 in all), where the base published AccessPackageNotFound. The review pipe is refused with EmptyAccessPackageId and sends no assignment request, where the base published AccessPackageNotFound.

[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s171] The module is the worktree's build: True
[oer-s171] Read objects: the policy carries the package's id: True; the review carries an AccessPackageId property: True, empty: True
[oer-s171] branch Explicit: objects 0 (base 0); own error ids: ; identical to the base: True
[oer-s171] branch PackagePipe: objects 0 (base 0); own error ids: ; identical to the base: True
[oer-s171] branch Contexts: objects 3 (base 3); own error ids: ; identical to the base: True
[oer-s171] branch ContextsAvailable: objects 2 (base 2); own error ids: ; identical to the base: True
[oer-s171] branch ContextC1: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s171] branch ContextUpperC1: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s171] branch PolicyPipe: objects 0; own error ids: ; assignment requests 1, every one filtered on the package and answering what -AccessPackage <package id> answers: True (base: objects 0; own error ids: AccessPackageNotFound)
[oer-s171] branch ReviewPipe: objects 0; own error ids: EmptyAccessPackageId; assignment requests 0 (base: objects 0; own error ids: AccessPackageNotFound)
[oer-s171] For scale: every assignment in the tenant, unfiltered: 5
```

## 3. A fresh export validates with no new Error (B, C)

### 3.1. This branch exports the test tenant and validates the export

- [x] **3.1** A fresh `Get-OERInventory` of every section (Azure for the test subscription, its policies for the common roles) is validated by this branch.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's171'
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
$Ctx = @(@($Doc[0].groups) | ForEach-Object { $P = $_.pimPolicy; if ($null -ne $P) { foreach ($B in @($P, $P.member, $P.owner)) { if ($null -ne $B -and $B.PSObject.Properties.Name -contains 'authenticationContextId') { [string]$B.authenticationContextId } } } })
$Scopes = @(@($Doc[0].accessPackages) | ForEach-Object { @($_.assignmentPolicies) } | Where-Object { $null -ne $_ -and $null -ne $_.requestorScope } | ForEach-Object { [string]$_.requestorScope.scope })
Write-OerLiveStep "Export holds: group pimPolicy authenticationContextId values $($Ctx.Count) (every one c<digits>: $(@($Ctx | Where-Object { $_ -cnotmatch '\Ac\d+\z' }).Count -eq 0)); requestorScope.scope values: $((@($Scopes | Group-Object -NoElement | Sort-Object Name | ForEach-Object { '{0} {1}' -f $_.Name, $_.Count })) -join ', ')"
$Result = Test-OERStructure -Path (Join-Path $Raw 'export.json')
$Findings = @($Result.Errors | ForEach-Object { [ordered]@{ Severity = [string]$_.Severity; Path = [string]$_.Path; Message = [string]$_.Message } })
ConvertTo-Json -InputObject @($Findings) -Depth 4 | Set-Content -LiteralPath (Join-Path $Raw 'branch-findings.json') -Encoding utf8NoBOM
Write-OerLiveStep "branch Test-OERStructure: Valid $($Result.Valid); errors $(@($Findings | Where-Object Severity -eq 'Error').Count); warnings $(@($Findings | Where-Object Severity -eq 'Warning').Count)"
Disconnect-OerLive
```

**Expect:** one document; every section read (a count, not `null`); the validation result recorded.
**Failure looks like:** no document, or a section `null` that the identity can read.

Result: 2026-11-13 02:47 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. One document, every section read with a count (no InventoryPartial). The export holds no group pimPolicy authenticationContextId (0 values) and requestorScope.scope values AllMemberUsers, NotSpecified and SpecificDirectoryUsers (2 each); no SpecificDirectoryServicePrincipals scope exists in the tenant. This branch validates it with 0 errors and 0 warnings.

[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s171] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s171] Export: documents 1; error ids: ; warnings: 2
[oer-s171] Export section groups: 94 entr(y/ies)
[oer-s171] Export section administrativeUnits: 1 entr(y/ies)
[oer-s171] Export section catalogs: 6 entr(y/ies)
[oer-s171] Export section accessPackages: 7 entr(y/ies)
[oer-s171] Export section accessReviews: 6 entr(y/ies)
[oer-s171] Export section directoryRoleManagementPolicies: 22 entr(y/ies)
[oer-s171] Export section directoryRoleAssignments: 51 entr(y/ies)
[oer-s171] Export section roleAssignments: 13 entr(y/ies)
[oer-s171] Export section roleManagementPolicies: 5 entr(y/ies)
[oer-s171] Export holds: group pimPolicy authenticationContextId values 0 (every one c<digits>: True); requestorScope.scope values: AllMemberUsers 2, NotSpecified 2, SpecificDirectoryUsers 2
[oer-s171] branch Test-OERStructure: Valid True; errors 0; warnings 0
```

### 3.2. The base build validates the same export: no new Error

- [x] **3.2** The base source (`fc8f2fa`) validates the same file; every Error this branch reports, the base reports too.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s171-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's171'
$BaseDir = Join-Path $Raw 'base-fc8f2fa'
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
the step's new one (a `SpecificDirectoryServicePrincipals` requestor scope), named by its path.
**Failure looks like:** an Error only this branch reports -- an exported document the stricter
validator refuses (STOP if it is not a defect of the export itself).

Result: 2026-11-13 02:47 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (fc8f2fa) validates the same export.json with 0 errors and 0 warnings; no Error and no Warning only this branch reports, none only the base reports.

[oer-s171] base Test-OERStructure: Valid True; errors 0; warnings 0
[oer-s171] Errors only this branch reports: 0
[oer-s171] Errors only the base reports: 0
[oer-s171] Warnings only this branch reports: 0
```

## T. Teardown

### T.1. Every prefixed object is removed

- [x] **T.1** The teardown removes every `oer-s171-` object, and the sweep is 0.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS171Prereq.ps1 -Teardown -Unattended
```

**Expect:** the access review definition, the access package (with its policy), the catalog and the
group removed; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result: 2026-11-13 02:48 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The teardown removed 5 objects: the access review definition oer-s171-ar, the assignment policy oer-s171-pol, the access package oer-s171-ap, the catalog oer-s171-cat and the group oer-s171-g1; residue 0. The sweep listed the deleted group once (listing lag) and was 0 thirty seconds later.

[oer-s171] Transcript (redacted): raw\s171\prereq-teardown-20261113-024742Z.log; OerLive 1.1.0.
[oer-s171] Omnicit.EntraRBAC 1.7.2 loaded from REPO\.claude\worktrees\s17-steg1\output\module\Omnicit.EntraRBAC\1.7.2.
[oer-s171] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s171] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s171] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s171-', the other 5 are left untouched.
[oer-s171] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s171] Teardown of 'oer-s171-': users 0, groups 1, access packages 1, access review definitions 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s171] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s171] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s171] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s171] Deleted: access review definition oer-s171-ar (204).
[oer-s171] Deleted: oer-s171-ap: assignment policy 'oer-s171-pol' (204).
[oer-s171] Deleted: access package oer-s171-ap (204, 1 attempt(s)).
[oer-s171] Deleted: catalog oer-s171-cat (204, 1 attempt(s)).
[oer-s171] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s171] Teardown 5/6: the prefixed groups.
[oer-s171] Deleted: group oer-s171-g1 (204).
[oer-s171] Teardown 6/6: the prefixed users.
[oer-s171] Teardown of 'oer-s171-': removed 5, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s171] Teardown summary: Removed 5, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s171] Sweep: 1 object(s) with the prefix, 0 unread kind(s).
[oer-s171] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s171-' is left.
[oer-s171] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s171] Teardown complete: the sweep is 0.
```
