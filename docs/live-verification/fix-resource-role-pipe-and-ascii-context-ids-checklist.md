# Live verification checklist -- piped package in the resource role read, ASCII digits in context ids (fix/resource-role-pipe-and-ascii-context-ids)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s181-`.** The
prerequisite script creates one security group without members or owners, `oer-s181-g1`. Check 1.1
writes, through `Invoke-OERStructure`, a catalog `oer-s181-cat` holding that group as a resource, and
an access package `oer-s181-ap` in it that binds the group's `Member` role, with one assignment policy
`oer-s181-pol` (administrator assignment only, requestor scope `NotSpecified`, no approval). Every other
block only reads. No policy of any role or object is changed, and no access package is assigned to
anyone.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS181Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s181/`
(git-ignored). Every block prints through the library's redactor and prints counts, keys and
True/False only, never an object id, a display name read from the tenant or an error record. **No
credential, token, application id or certificate thumbprint is ever printed.**

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. A piped object binds its access package in the resource role read** ("bind a piped
  AccessPackageId before Id in Get-OERAccessPackageResourceRole"). `-AccessPackage` on
  `Get-OERAccessPackageResourceRole` lists `AccessPackageId` before `Id`. An object that carries no
  `AccessPackageId` (an access package from `Get-OERAccessPackage`) still binds its `Id`; a piped object
  whose `AccessPackageId` is empty is refused at binding. The AST cohort
  `AccessPackageAliasOrder.Cohort.Tests.ps1` now also holds every pipeline-bound `-AccessPackage` with an
  `Id` or `DisplayName` alias.
- **B. An authentication context id is `c` followed by ASCII digits** ("accept only ASCII digits in an
  authentication context id"). `\d` became `[0-9]` in `Set-OERRoleManagementPolicy`,
  `Set-OERDirectoryRoleManagementPolicy`, `Set-OERGroupPimPolicy`, `Get-OERAuthenticationContext` and the
  validator's two checks; letter case unchanged.
- **C.** The inventory bundle's advice to omit `requestorScope` names its limit: it keeps the scope of an
  existing policy, and a new policy without it is created with `AllMemberUsers`. Text only.

A live tenant is needed for what mocks cannot show: that a real assignment policy object and a real
resource role object, piped into `Get-OERAccessPackageResourceRole`, read their own package's resource
roles, where the base build bound the policy's own id or bound nothing (A); and that a real access
package from `Get-OERAccessPackage`, piped the same way, the explicit read, and the real authentication
contexts read exactly what the base build read (A, B).

## What this file does not check, and why

- **The Unicode digit cases** (`c` followed by a digit of another script refused, in the four cmdlets and
  the validator) are class B: the unit tests named in the step's report hold them, and a refused id
  sends nothing, so a live run adds nothing. The three `Set-*` policy cmdlets would write.
- **The cohort** reads source by AST: class B, its own test.
- **C** is a text in the bundle prompt; its unit test holds it.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS181Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s181-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Text = Get-Content -LiteralPath $Psm1.FullName -Raw
$Start = $Text.IndexOf('function Get-OERAccessPackageResourceRole {')
$Region = if ($Start -ge 0) { $Text.Substring($Start) -replace '(?s)\r?\nfunction .*$', '' } else { '' }
$A = $Region -match "\[Alias\('AccessPackageId', 'Id'\)\]\r?\n\s*\[string\]\`$AccessPackage"
$B = $Text.Contains("[ValidatePattern('\Ac[0-9]+\z|\A\z')]") -and $Text.Contains("[ValidatePattern('\Ac[0-9]+\z')]") -and -not $Text.Contains('\Ac\d+\z')
Write-OerLiveStep "The worktree's build carries A: $A; B: $B"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main; the worktree on fix/resource-role-pipe-and-ascii-context-ids at e23a511 with 0 tracked changes; the build carries A (the alias inside Get-OERAccessPackageResourceRole) and B (the [0-9] patterns, no \d context pattern left).

[oer-s181] The module loads from a worktree that is not the main clone: True
[oer-s181] Main clone: branch main
[oer-s181] Worktree: branch fix/resource-role-pipe-and-ascii-context-ids; HEAD e23a511 test: pipe a resource role into the resource role read and tighten the live checklist; tracked changes: 0
[oer-s181] The worktree's build carries A: True; B: True
```

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s181-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** `identity check passed: True`; `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or "application is disabled" -- STOP.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The ARM module session as oer-live-cc passes every identity check line (app, service principal and tenant True); the module loaded is the worktree's build (1.7.3).

[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s181] The module is the worktree's build: True
```

### 0.2. The prerequisite script's plan

- [x] **0.2** `-WhatIf` plans only `oer-s181-` objects.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -WhatIf
```

**Expect:** the two permissions `True`; every `What if` line names an `oer-s181-` object (or, on a
re-run, none: the group exists).
**Failure looks like:** a target without the prefix, or a `STOP` -- STOP.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Both permissions held; the sweep of the prefix is 0; the only object the plan creates is oer-s181-g1.

What if: Performing the operation "Create Directory" on target "Destination: REPO\docs\live-verification\raw\s181".
What if: Performing the operation "Start the redacted transcript" on target "raw\s181\prereq-20261113-213012Z.log".
[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s181] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s181-', the other 5 are left untouched.
[oer-s181] Permission held: Group.ReadWrite.All: True
[oer-s181] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s181] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s181-' is left.
What if: Performing the operation "Write the baseline" on target "raw\s181\baseline-prereq.json".
[oer-s181] Baseline sweep: 0 object(s) with the prefix before this run.
What if: Performing the operation "Create security group (no members, no owners)" on target "oer-s181-g1".
```

### 0.3. The prerequisite script, for real

- [x] **0.3** The group `oer-s181-g1` exists.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -Unattended
```

**Expect:** `Created group oer-s181-g1.` (or found); `Read back group g1: True`.
**Failure looks like:** a `STOP`, or `False` on the read back.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The baseline (sweep 0) was written before the first write; oer-s181-g1 was created and read back by id (two 404s on the first reads, replication).

[oer-s181] Transcript (redacted): raw\s181\prereq-20261113-213026Z.log; OerLive 1.1.0.
[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s181] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s181-', the other 5 are left untouched.
[oer-s181] Permission held: Group.ReadWrite.All: True
[oer-s181] Permission held: EntitlementManagement.ReadWrite.All: True
[oer-s181] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s181-' is left.
[oer-s181] Baseline sweep: 0 object(s) with the prefix before this run.
[oer-s181] Created group oer-s181-g1.
[oer-s181] read v1.0/groups/00000000-0000-0000-0000-000000000001?$select=id answered 404 Request_ResourceNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s181] read v1.0/groups/00000000-0000-0000-0000-000000000001?$select=id answered 404 Request_ResourceNotFound (attempt 2 of 6, likely replication delay) -- trying again in 5 s.
[oer-s181] Read back group g1: True
```

## 1. The objects the reads need, written twice (G8)

### 1.1. Catalog with the group, access package with its Member role and a policy: Created, then only Unchanged

- [x] **1.1** `Invoke-OERStructure` plans, creates and then finds unchanged the catalog and the access package.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s181-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's181'
$Doc = Join-Path $Raw 'structure-objects.json'
if (-not (Test-Path -LiteralPath $Doc)) {
    [ordered]@{
        version        = '1.0'
        catalogs       = @([ordered]@{ displayName = 'oer-s181-cat'; description = 'Sprint 18 step 1 live check (oer-s181-)'; resources = @([ordered]@{ type = 'Group'; name = 'oer-s181-g1' }) })
        accessPackages = @([ordered]@{
                displayName = 'oer-s181-ap'; catalog = 'oer-s181-cat'; description = 'Sprint 18 step 1 live check (oer-s181-)'
                resourceRoles = @([ordered]@{ resource = 'oer-s181-g1'; role = 'Member' })
                assignmentPolicies = @([ordered]@{ displayName = 'oer-s181-pol'; description = 'Sprint 18 step 1 live check (oer-s181-)'; requestorScope = [ordered]@{ scope = 'NotSpecified' }; requireApproval = $false; durationInDays = 30 })
            })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Doc -Encoding utf8NoBOM
}
Connect-OerLive -Arm
foreach ($Run in 'plan', 'first', 'second') {
    $P = @{ Path = $Doc; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'script:E'; Include = @('Catalogs', 'AccessPackages') }
    if ($Run -eq 'plan') { $P.WhatIf = $true } else { $P.Confirm = $false }
    $script:E = $null
    $Rows = @(Invoke-OERStructure @P 3>$null)
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "${Run}: own errors: $($Own -join ', '); rows: $((@($Rows | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Item, $_.Action })) -join '; ')"
    if ($Run -eq 'first') { Start-Sleep -Seconds 30 }
}
Disconnect-OerLive
```

**Expect:** `plan`: every row `Skipped` (would create), no own error; `first`: every row `Created`
(the `catalogs oer-s181-cat` row and each `accessPackages oer-s181-ap` row), no `Failed` row, no own
error; `second`: every row `Unchanged` (G8), no own error.
**Failure looks like:** an own error, a `Failed` row, or a second run with a change.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS, with one deviation from the Expect's wording. The plan was Skipped with no own error; the first run created the catalog, the access package, its resource role binding and its policy, and reported the catalog's resource row (the group added to oer-s181-cat) as Updated rather than Created -- adding a resource to the just-created catalog is an update of the catalog; no row Failed, no own error. The second run was Unchanged for all five rows (G8), no own error.

[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create catalog" on target "oer-s181-cat".
What if: Performing the operation "Create access package" on target "oer-s181-ap".
[oer-s181] plan: own errors: ; rows: catalogs oer-s181-cat Skipped; catalogs oer-s181-cat Skipped; accessPackages oer-s181-ap Skipped; accessPackages oer-s181-ap Skipped; accessPackages oer-s181-ap Skipped
[oer-s181] first: own errors: ; rows: catalogs oer-s181-cat Created; catalogs oer-s181-cat Updated; accessPackages oer-s181-ap Created; accessPackages oer-s181-ap Created; accessPackages oer-s181-ap Created
[oer-s181] second: own errors: ; rows: catalogs oer-s181-cat Unchanged; catalogs oer-s181-cat Unchanged; accessPackages oer-s181-ap Unchanged; accessPackages oer-s181-ap Unchanged; accessPackages oer-s181-ap Unchanged
```

## 2. The reads give what the base build gave, and the policy and resource role pipes read their package (A, B)

### 2.1. The base build's reads, recorded

- [x] **2.1** The base source (`021e976`) reads the package's resource roles by id and through the package, policy and resource role pipes, and the authentication contexts; the answers and the resource role requests are recorded.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s181-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's181'
$BaseDir = Join-Path $Raw 'base-021e976'
if (-not (Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))) {
    git -C $Cfg.Repo archive --format=zip -o (Join-Path $Raw 'base-021e976.zip') 021e976 source
    Expand-Archive -LiteralPath (Join-Path $Raw 'base-021e976.zip') -DestinationPath $BaseDir -Force
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the base source (021e976): $($M.ModuleBase.StartsWith($BaseDir, [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read, [string]$Command, [string]$PackageId) {
    $script:E = $null
    $Error.Clear()
    $All = @(try { & $Read 4>&1 } catch { $null })
    $Verbose = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message })
    $Out = @($All | Where-Object { $null -ne $_ -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Requests = @($Verbose | Where-Object { $_.StartsWith('[Invoke-OERGraphRequest] GET ') -and $_.Contains('resourceRoleScopes') })
    $Records = @(@($script:E) + @($Error) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    [ordered]@{
        Objects             = @($Out | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors              = @($Records | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Select-Object -Unique)
        ResourceRoleReads   = $Requests.Count
        ReadOfThePackage    = @($Requests | Where-Object { $_.Contains("accessPackages/$PackageId") }).Count
    }
}
$Ap = @(Get-OERAccessPackage -DisplayName 'oer-s181-ap' -ErrorAction Stop)[0]
$PackageId = [string]$Ap.Id
$Policy = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $PackageId -ErrorAction Stop)[0]
$Role = @(Get-OERAccessPackageResourceRole -AccessPackage $PackageId -ErrorAction Stop)[0]
Write-OerLiveStep "Read objects: the policy carries the package's id: $([string]$Policy.AccessPackageId -eq $PackageId), and its own Id differs: $([string]$Policy.Id -ne $PackageId); the resource role carries the package's id: $([string]$Role.AccessPackageId -eq $PackageId), and an Id property: $($Role.PSObject.Properties.Name -contains 'Id')"
$R = 'Get-OERAccessPackageResourceRole'
$C = 'Get-OERAuthenticationContext'
$Rec = [ordered]@{}
$Rec.Explicit = Get-ReadRecord { Get-OERAccessPackageResourceRole -AccessPackage $PackageId -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.PackagePipe = Get-ReadRecord { $Ap | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.PolicyPipe = Get-ReadRecord { $Policy | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.RolePipe = Get-ReadRecord { $Role | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.Contexts = Get-ReadRecord { Get-OERAuthenticationContext -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextsAvailable = Get-ReadRecord { Get-OERAuthenticationContext -Available -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'c1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec.ContextUpperC1 = Get-ReadRecord { Get-OERAuthenticationContext -Id 'C1' -ErrorAction SilentlyContinue -ErrorVariable script:E } $C $PackageId
$Rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'base-reads.json') -Encoding utf8NoBOM
foreach ($K in $Rec.Keys) { Write-OerLiveStep "base ${K}: objects $(@($Rec[$K].Objects).Count); own error ids: $(@($Rec[$K].Errors) -join ', '); resource role reads $($Rec[$K].ResourceRoleReads), of the package $($Rec[$K].ReadOfThePackage)" }
Disconnect-OerLive
```

**Expect:** the module is the base source; the policy carries the package's id and an `Id` of its own;
the resource role carries the package's id and no `Id`; `Explicit` and `PackagePipe` with no error, one
resource role read each, of the package, and one object (the `Member` binding); the four context reads
with no error. `PolicyPipe` and `RolePipe` are the measurement of the defect A fixes: the base binds the
policy's own id as the package (an error, no resource role read of the package), and binds nothing from
the resource role (a binding error, no read).
**Failure looks like:** an error id on any read but `PolicyPipe` and `RolePipe`; `Explicit` with no object.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (021e976) read the package's 1 resource role binding by id and through the package pipe, one resource role read each, of the package, no error; the four context reads returned 3, 2 (available), 1 (c1) and 1 (C1) with no error. The policy pipe and the resource role pipe are the measured defect A fixes: the base bound the policy's own id and published AccessPackageNotFound, and bound nothing from the resource role (InputObjectNotBound), with no resource role read.

[oer-s181] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s181] The module is the base source (021e976): True
[oer-s181] Read objects: the policy carries the package's id: True, and its own Id differs: True; the resource role carries the package's id: True, and an Id property: False
[oer-s181] base Explicit: objects 1; own error ids: ; resource role reads 1, of the package 1
[oer-s181] base PackagePipe: objects 1; own error ids: ; resource role reads 1, of the package 1
[oer-s181] base PolicyPipe: objects 0; own error ids: AccessPackageNotFound; resource role reads 0, of the package 0
[oer-s181] base RolePipe: objects 0; own error ids: InputObjectNotBound; resource role reads 0, of the package 0
[oer-s181] base Contexts: objects 3; own error ids: ; resource role reads 0, of the package 0
[oer-s181] base ContextsAvailable: objects 2; own error ids: ; resource role reads 0, of the package 0
[oer-s181] base ContextC1: objects 1; own error ids: ; resource role reads 0, of the package 0
[oer-s181] base ContextUpperC1: objects 1; own error ids: ; resource role reads 0, of the package 0
```

### 2.2. This branch's reads, compared with the base

- [x] **2.2** This branch's build gives the same answer as the base for the explicit read, the package pipe and the contexts; the policy pipe and the resource role pipe now read their package's resource roles, and a piped object with an empty `AccessPackageId` is refused before any read.
```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s181-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's181'
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Get-ReadRecord([scriptblock]$Read, [string]$Command, [string]$PackageId) {
    $script:E = $null
    $Error.Clear()
    $All = @(try { & $Read 4>&1 } catch { $null })
    $Verbose = @($All | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { [string]$_.Message })
    $Out = @($All | Where-Object { $null -ne $_ -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Requests = @($Verbose | Where-Object { $_.StartsWith('[Invoke-OERGraphRequest] GET ') -and $_.Contains('resourceRoleScopes') })
    $Records = @(@($script:E) + @($Error) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    [ordered]@{
        Objects             = @($Out | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress })
        Errors              = @($Records | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Select-Object -Unique)
        ResourceRoleReads   = $Requests.Count
        ReadOfThePackage    = @($Requests | Where-Object { $_.Contains("accessPackages/$PackageId") }).Count
    }
}
$Ap = @(Get-OERAccessPackage -DisplayName 'oer-s181-ap' -ErrorAction Stop)[0]
$PackageId = [string]$Ap.Id
$Policy = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $PackageId -ErrorAction Stop)[0]
$Role = @(Get-OERAccessPackageResourceRole -AccessPackage $PackageId -ErrorAction Stop)[0]
$Empty = [pscustomobject]@{ AccessPackageId = ''; Id = $PackageId }
$R = 'Get-OERAccessPackageResourceRole'
$C = 'Get-OERAuthenticationContext'
$Rec = [ordered]@{}
$Rec.Explicit = Get-ReadRecord { Get-OERAccessPackageResourceRole -AccessPackage $PackageId -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.PackagePipe = Get-ReadRecord { $Ap | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.PolicyPipe = Get-ReadRecord { $Policy | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.RolePipe = Get-ReadRecord { $Role | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
$Rec.EmptyPipe = Get-ReadRecord { $Empty | Get-OERAccessPackageResourceRole -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E } $R $PackageId
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
    $Same = ((Get-CanonicalText $Rec[$K].Objects) -ceq (Get-CanonicalText $Base[$K].Objects)) -and ((@($Rec[$K].Errors) -join ',') -ceq (@($Base[$K].Errors) -join ',')) -and ($Rec[$K].ResourceRoleReads -eq $Base[$K].ResourceRoleReads) -and ($Rec[$K].ReadOfThePackage -eq $Base[$K].ReadOfThePackage)
    Write-OerLiveStep "branch ${K}: objects $(@($Rec[$K].Objects).Count) (base $(@($Base[$K].Objects).Count)); own error ids: $(@($Rec[$K].Errors) -join ', '); identical to the base: $Same"
}
foreach ($K in 'PolicyPipe', 'RolePipe') {
    $ReadsPackage = ((Get-CanonicalText $Rec[$K].Objects) -ceq (Get-CanonicalText $Rec.Explicit.Objects)) -and $Rec[$K].ResourceRoleReads -eq 1 -and $Rec[$K].ReadOfThePackage -eq 1
    Write-OerLiveStep "branch ${K}: objects $(@($Rec[$K].Objects).Count); own error ids: $(@($Rec[$K].Errors) -join ', '); one resource role read, of the package, answering what -AccessPackage with the package id answers: $ReadsPackage (base: objects $(@($Base[$K].Objects).Count); own error ids: $(@($Base[$K].Errors) -join ', '); resource role reads $($Base[$K].ResourceRoleReads))"
}
Write-OerLiveStep "branch EmptyPipe: objects $(@($Rec.EmptyPipe.Objects).Count); own error ids: $(@($Rec.EmptyPipe.Errors) -join ', '); resource role reads $($Rec.EmptyPipe.ResourceRoleReads)"
Disconnect-OerLive
```

**Expect:** the module is the worktree's build; `identical to the base: True` for `Explicit`,
`PackagePipe` and the four context reads; `PolicyPipe` and `RolePipe`: no error id and
`... answering what -AccessPackage with the package id answers: True`; `EmptyPipe`: own error id
`ParameterArgumentValidationErrorEmptyStringNotAllowed`, 0 objects, 0 resource role reads.
**Failure looks like:** any `False`; an error id on `PolicyPipe` or `RolePipe`; a read on `EmptyPipe`.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The explicit read, the package pipe and the four context reads are identical to the base (no error id). The policy pipe and the resource role pipe now send one resource role read each, of the package, and answer what -AccessPackage with the package id answers (1 binding), where the base published AccessPackageNotFound and InputObjectNotBound. A piped object with an empty AccessPackageId is refused at binding (ParameterArgumentValidationErrorEmptyStringNotAllowed) with no read.

[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s181] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s181] The module is the worktree's build: True
[oer-s181] branch Explicit: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s181] branch PackagePipe: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s181] branch Contexts: objects 3 (base 3); own error ids: ; identical to the base: True
[oer-s181] branch ContextsAvailable: objects 2 (base 2); own error ids: ; identical to the base: True
[oer-s181] branch ContextC1: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s181] branch ContextUpperC1: objects 1 (base 1); own error ids: ; identical to the base: True
[oer-s181] branch PolicyPipe: objects 1; own error ids: ; one resource role read, of the package, answering what -AccessPackage with the package id answers: True (base: objects 0; own error ids: AccessPackageNotFound; resource role reads 0)
[oer-s181] branch RolePipe: objects 1; own error ids: ; one resource role read, of the package, answering what -AccessPackage with the package id answers: True (base: objects 0; own error ids: InputObjectNotBound; resource role reads 0)
[oer-s181] branch EmptyPipe: objects 0; own error ids: ParameterArgumentValidationErrorEmptyStringNotAllowed; resource role reads 0
```

## T. Teardown

### T.1. Every prefixed object is removed

- [x] **T.1** The teardown removes every `oer-s181-` object, and the sweep is 0.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -Teardown -Unattended
```

**Expect:** the access package (with its policy and resource role), the catalog (with its resource) and
the group removed; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result: 2026-11-13 21:33 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The teardown removed 6: the resource role binding, the assignment policy oer-s181-pol, the access package oer-s181-ap, the catalog resource, the catalog oer-s181-cat and the group oer-s181-g1; residue 0. The sweep listed the deleted group once (listing lag) and was 0 thirty seconds later.

[oer-s181] Transcript (redacted): raw\s181\prereq-teardown-20261113-213228Z.log; OerLive 1.1.0.
[oer-s181] Omnicit.EntraRBAC 1.7.3 loaded from REPO\.claude\worktrees\s18-steg1\output\module\Omnicit.EntraRBAC\1.7.3.
[oer-s181] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s181] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s181] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s181-', the other 5 are left untouched.
[oer-s181] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s181] Teardown of 'oer-s181-': users 0, groups 1, access packages 1, access review definitions 0, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s181] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s181] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s181] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s181] Removed: oer-s181-ap: resource role binding 'Member' (200).
[oer-s181] Deleted: oer-s181-ap: assignment policy 'oer-s181-pol' (204).
[oer-s181] Deleted: access package oer-s181-ap (204, 1 attempt(s)).
[oer-s181] Removed: oer-s181-cat: resource 'oer-s181-g1' (201).
[oer-s181] Deleted: catalog oer-s181-cat (204, 1 attempt(s)).
[oer-s181] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s181] Teardown 5/6: the prefixed groups.
[oer-s181] Deleted: group oer-s181-g1 (204).
[oer-s181] Teardown 6/6: the prefixed users.
[oer-s181] Teardown of 'oer-s181-': removed 6, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s181] Teardown summary: Removed 6, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s181] Sweep: 1 object(s) with the prefix, 0 unread kind(s).
[oer-s181] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s181-' is left.
[oer-s181] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s181] Teardown complete: the sweep is 0.
```
