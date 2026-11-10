# Live verification checklist -- an access package named within its catalog (feat/access-package-catalog-parameter)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s1512-`.** The
prerequisite script creates two catalogs, `oer-s1512-cat-a` and `oer-s1512-cat-b`, each holding an
access package named `oer-s1512-ap`; two more packages in `oer-s1512-cat-a` only (`oer-s1512-new`,
`oer-s1512-eng`); a direct-assignment policy `oer-s1512-pol` on each `oer-s1512-ap`; and a security
group `oer-s1512-grp` with no member, a resource of both catalogs, whose Member role is bound to the
package in `oer-s1512-cat-b`. The checks write only to those objects or create new ones with the
prefix: a resource role binding, an assignment policy, a description, a self-review access review
that starts seven days ahead and sends no mail, and two access packages in `oer-s1512-cat-b`. No
assignment is made, no directory role is assigned and no policy outside the prefix is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS1512Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s1512/`
(git-ignored). Every block prints through the library's redactor, and the blocks print the test
objects by their key in the prerequisite script's id file (`catA`, `catB`, `apA`, `apB`, `newA`,
`engA`, `polA`, `polB`, `grp`), never by id; any other object id becomes
`00000000-0000-0000-0000-0000000000NN`. **No credential, token, application id or certificate
thumbprint is ever printed. Never render an error record**: every block prints the error id and
message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. The resolver looks a package up within a catalog** ("look an access package up within a
  catalog in the resolver"). `Resolve-OERAccessPackageId -Catalog` resolves the catalog (an id as
  it is), looks a name up with `displayName eq '...' and catalog/id eq '...'`, reads an id with
  `$expand=catalog` and refuses one whose catalog is another with the new `AccessPackageNotInCatalog`.
- **B. Eight cmdlets gain `-Catalog`** ("name an access package within its catalog on eight
  cmdlets"): `Get-OERAccessPackageAssignment`, `Get-OERAccessPackageAssignmentPolicy`,
  `Get-OERAccessPackageResourceRole`, `New-OERAccessPackageAssignment`,
  `New-OERAccessPackageAssignmentPolicy`, `Remove-OERAccessPackageResourceRole`,
  `Remove-OERAccessPackage` and `Set-OERAccessPackage` (the last two in their `-DisplayName` set).
  `Get-OERAccessPackageAssignment -Catalog` without `-AccessPackage` is refused with the new
  `CatalogWithoutAccessPackage`.
- **C. The existing `-Catalog` scopes the lookup** ("scope the existing -Catalog to the access
  package lookup"): `Add-OERAccessPackageResourceRole`, `New-OERAccessPackage` (a name in another
  catalog no longer stops the create) and `New-OERAccessReviewDefinition`.

A live tenant is needed for what mocks cannot show: that Microsoft Graph accepts two packages of one
name in two catalogs (M1), which request forms answer exactly one of them (M2 to M5), and that each
cmdlet, run against real answers, reaches the package of the catalog it names and refuses the other.

## What this file does not check, and why

- **New-OERAccessPackageAssignment is run with `-WhatIf` only.** A real assignment needs a user as
  its target, and the test objects hold none; the `-WhatIf` line names the package the request
  would carry, which is what the step changes.
- **Remove-OERAccessPackage is run with `-WhatIf` only.** Its warning names the package it would
  delete; deleting a test package is the teardown's job.
- **An ambiguous catalog name** cannot be produced: Microsoft Graph refuses two catalogs of one name
  (measured in Sprint 11). Class B: the mocked guard cases in
  `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1`.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS1512Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'AccessPackageNotInCatalog'" -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'CatalogWithoutAccessPackage'" -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERPipedAccessPackageId' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True; C: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP; never sign in another way.

Result:

### 0.2. The prerequisite script's plan

- [ ] **0.2** `-WhatIf` plans only `oer-s1512-` objects.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS1512Prereq.ps1 -WhatIf
```

**Expect:** every `What if` line names an `oer-s1512-` object (or, on a re-run, none: the objects exist).
**Failure looks like:** a target without the prefix -- STOP.

Result:

### 0.3. The prerequisite script, for real

- [ ] **0.3** The test objects exist, each package in its own catalog.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS1512Prereq.ps1 -Unattended
```

**Expect:** every `Read back` line `True`, among them `package apA in its catalog: True` and `package apB in its catalog: True`.
**Failure looks like:** a `False`, or `STOP` -- stop the run.

Result:

## M. Measurements of Microsoft Graph (Part 1, read-only)

### M.1. Two packages of one name in two catalogs, and the request forms

- [ ] **M.1** Graph accepts the twin package, and each request form answers exactly the package of the catalog it names.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
Connect-OerLive -Graph
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Name = 'oer-s1512-ap'
$Twin = Get-Content (Join-Path $Raw 'twin-create.json') -Raw | ConvertFrom-Json
Write-OerLiveStep "M1 the twin package create (prerequisite script): status $($Twin.Status), error code '$($Twin.ErrorCode)'"
$R = Invoke-OerLiveGraph -Uri "$Em/accessPackages?`$filter=displayName eq '$Name'&`$select=id,displayName"
Write-OerLiveStep "M5 tenant-wide displayName eq: status $($R.Status), rows: $((@($R.Body.value) | ForEach-Object { L ([string]$_.id) }) -join ', ')"
foreach ($C in 'catA', 'catB') {
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages?`$filter=displayName eq '$Name' and catalog/id eq '$($Ids[$C].Id)'&`$select=id,displayName"
    Write-OerLiveStep "M2 displayName eq and catalog/id eq ($C): status $($R.Status), rows: $((@($R.Body.value) | ForEach-Object { L ([string]$_.id) }) -join ', ')"
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages?`$filter=displayName eq '$($Name.ToUpperInvariant())' and catalog/id eq '$($Ids[$C].Id)'&`$select=id,displayName"
    Write-OerLiveStep "M2 the name in upper case ($C): status $($R.Status), rows: $((@($R.Body.value) | ForEach-Object { L ([string]$_.id) }) -join ', ')"
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages?`$filter=catalog/id eq '$($Ids[$C].Id)'&`$expand=catalog" -All
    $Hit = @($R.Body.value | Where-Object { [string]$_.displayName -ieq $Name } | ForEach-Object { L ([string]$_.id) })
    Write-OerLiveStep "M3 the engine's form, catalog/id eq and a match here ($C): status $($R.Status), matches: $($Hit -join ', ')"
}
$R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids.apB.Id)?`$expand=catalog"
Write-OerLiveStep "M4 apB by id with expand=catalog: status $($R.Status), catalog: $(L ([string]$R.Body.catalog.id))"
$R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$([guid]::NewGuid())?`$expand=catalog"
Write-OerLiveStep "M4 an id that does not exist, with expand=catalog: status $($R.Status), code '$($R.Code)'"
Disconnect-OerLive
```

**Expect:** M1 `status 201`; M5 rows `apA, apB` (in either order); M2 for `catA` exactly `apA`, for
`catB` exactly `apB`, the upper-case name the same; M3 the same single package; M4 `catalog: catB`,
and `404` with `AccessPackageNotFound` for an id that does not exist.
**Failure looks like:** M1 refused (then there is nothing to solve: STOP), or an M2 row of the other
catalog (the server filter would not scope the lookup: STOP).

Result:

## 1. Each cmdlet with -Catalog reaches the package of that catalog

Every block in sections 1 to 4 starts with the same lines: it loads the library and the id file,
signs the module in as `oer-live-cc` (`Connect-OerLive -Arm`), and prints ids by their key.

### 1.1. The three read cmdlets

- [ ] **1.1** `Get-OERAccessPackageAssignment`, `Get-OERAccessPackageAssignmentPolicy` and `Get-OERAccessPackageResourceRole` with `-Catalog` each read the package of that catalog.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
function Req($Out) { @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like '`[Invoke-OERGraphRequest`] GET *' } | ForEach-Object { T ($_.Message -replace '^\[Invoke-OERGraphRequest\] ', '') }) }
Connect-OerLive -Arm
foreach ($C in @(@('catA', 'oer-s1512-cat-a'), @('catB', 'oer-s1512-cat-b'))) {
    $Err = $null
    $Out = @(Get-OERAccessPackageAssignment -AccessPackage 'oer-s1512-ap' -Catalog $C[1] -Verbose -ErrorAction SilentlyContinue -ErrorVariable Err 4>&1)
    Write-OerLiveStep "Get-OERAccessPackageAssignment -Catalog $($C[0]): errors $(@($Err).Count); requests: $((Req $Out) -join ' | ')"
    $Err = $null
    $P = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s1512-ap' -Catalog $C[1] -ErrorAction SilentlyContinue -ErrorVariable Err)
    Write-OerLiveStep "Get-OERAccessPackageAssignmentPolicy -Catalog $($C[0]): errors $(@($Err).Count); policies: $((@($P) | ForEach-Object { '{0} of {1}' -f (L ([string]$_.Id)), (L ([string]$_.AccessPackageId)) }) -join ', ')"
    $Err = $null
    $B = @(Get-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -Catalog $C[1] -ErrorAction SilentlyContinue -ErrorVariable Err)
    Write-OerLiveStep "Get-OERAccessPackageResourceRole -Catalog $($C[0]): errors $(@($Err).Count); bindings: $((@($B) | ForEach-Object { '{0} of {1}' -f $_.RoleName, (L ([string]$_.AccessPackageId)) }) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** no errors; the assignment request's filter names `apA` for `catA` and `apB` for `catB`;
the policies `polA of apA` and `polB of apB`; no binding for `catA`, `Member of apB` for `catB`.
**Failure looks like:** an `AmbiguousAccessPackageName`, or a package of the other catalog.

Result:

### 1.2. The writing cmdlets that take -AccessPackage

- [ ] **1.2** `New-OERAccessPackageAssignment` (`-WhatIf`), `New-OERAccessPackageAssignmentPolicy`, `Add-OERAccessPackageResourceRole` and `Remove-OERAccessPackageResourceRole` with `-Catalog` write only to the package of that catalog.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
Connect-OerLive -Arm
# A What if line goes to the host, not to a stream: it prints with the id, which the redactor gives the placeholder printed here.
Write-OerLiveStep "Keys: apA is $($Ids.apA.Id); apB is $($Ids.apB.Id)"
$Err = $null
New-OERAccessPackageAssignment -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-cat-a' -Policy $Ids.polA.Id -TargetId '00000000-0000-0000-0000-000000000000' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err
Write-OerLiveStep "New-OERAccessPackageAssignment -Catalog catA -WhatIf: errors $(@($Err).Count)$(@($Err) | ForEach-Object { ' | ' + $_.FullyQualifiedErrorId })"
$Scope = New-OERAccessPackageRequestorScope -Scope NoSubjects
$Err = $null
$Pol = New-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-cat-b' -DisplayName 'oer-s1512-pol2' -Description 'Sprint 15 step 1b live check (oer-s1512-)' -RequestorScope $Scope -DisableAssignmentNotifications -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
if ($Pol.Id) { $Ids['pol2'] = @{ Kind = 'assignment policy'; Id = [string]$Pol.Id }; $Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Encoding utf8NoBOM; $Label[[string]$Pol.Id] = 'pol2' }
Write-OerLiveStep "New-OERAccessPackageAssignmentPolicy -Catalog catB: errors $(@($Err).Count); created $(L ([string]$Pol.Id)) on $(L ([string]$Pol.AccessPackageId))"
$Err = $null
$Bind = Add-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-cat-a' -Group 'oer-s1512-grp' -Role 'Member' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
Write-OerLiveStep "Add-OERAccessPackageResourceRole -Catalog catA: errors $(@($Err).Count); bound $($Bind.RoleName) on $(L ([string]$Bind.AccessPackageId))"
Start-Sleep -Seconds 10
$Err = $null
Remove-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-cat-a' -ResourceRoleScopeId $Bind.ResourceRoleScopeId -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
Write-OerLiveStep "Remove-OERAccessPackageResourceRole -Catalog catA: errors $(@($Err).Count)$(@($Err) | ForEach-Object { ' | ' + (T $_.FullyQualifiedErrorId) + ' ' + (T $_.Exception.Message) })"
Start-Sleep -Seconds 10
$Em = 'v1.0/identityGovernance/entitlementManagement'
foreach ($K in 'apA', 'apB') {
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids[$K].Id)?`$expand=resourceRoleScopes(`$expand=role),assignmentPolicies"
    Write-OerLiveStep "Read back ${K}: bindings $(@($R.Body.resourceRoleScopes).Count) ($((@($R.Body.resourceRoleScopes) | ForEach-Object { $_.role.displayName }) -join ', ')); policies: $((@($R.Body.assignmentPolicies) | ForEach-Object { L ([string]$_.id) }) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** the `What if` line names the placeholder the `Keys` line gives `apA` (`Assign to access package ...`) and no error; the new
policy `pol2 on apB`; the binding `Member on apA`; the removal without error; read back: `apA`
bindings 0, policies `polA`; `apB` bindings 1 (`Member`), policies `polB, pol2` (either order).
**Failure looks like:** `AmbiguousAccessPackageName`, a write to the other package, or a binding left on `apA`.

Result:

### 1.3. Set-OERAccessPackage and Remove-OERAccessPackage by display name

- [ ] **1.3** `Set-OERAccessPackage -DisplayName -Catalog` updates only that catalog's package, and `Remove-OERAccessPackage -DisplayName -Catalog -WhatIf` names it.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
Connect-OerLive -Arm
$Em = 'v1.0/identityGovernance/entitlementManagement'
$New = 'Sprint 15 step 1b live check (oer-s1512-), updated by 1.3'
$Err = $null
Set-OERAccessPackage -DisplayName 'oer-s1512-ap' -Catalog 'oer-s1512-cat-b' -Description $New -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
Write-OerLiveStep "Set-OERAccessPackage -Catalog catB: errors $(@($Err).Count)"
Start-Sleep -Seconds 10
foreach ($K in 'apA', 'apB') {
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids[$K].Id)"
    Write-OerLiveStep "Read back ${K}: description updated by 1.3: $([string]$R.Body.description -ceq $New)"
}
$Err = $null
Write-OerLiveStep "Keys: apA is $($Ids.apA.Id); apB is $($Ids.apB.Id)"
$Lines = @(Remove-OERAccessPackage -DisplayName 'oer-s1512-ap' -Catalog 'oer-s1512-cat-a' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err 3>&1 | ForEach-Object { T ([string]$_) })
Write-OerLiveStep "Remove-OERAccessPackage -Catalog catA -WhatIf: errors $(@($Err).Count); output: $($Lines -join ' | ')"
$R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids.apA.Id)?`$select=id"
Write-OerLiveStep "Read back apA still exists: $($R.Ok)"
Disconnect-OerLive
```

**Expect:** no errors; `apA` description updated `False`, `apB` `True`; the warning names `apA` and the
`What if` line the placeholder the `Keys` line gives `apA`; `apA still exists: True`.
**Failure looks like:** `AmbiguousAccessPackageName`, `apA` updated, or the other package named.

Result:

### 1.4. New-OERAccessReviewDefinition with -Catalog

- [ ] **1.4** The review is created on the package of the named catalog.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
Connect-OerLive -Arm
$Err = $null
$Rv = New-OERAccessReviewDefinition -DisplayName 'oer-s1512-rv' -DescriptionForAdmins 'Sprint 15 step 1b live check (oer-s1512-)' -DescriptionForReviewers 'Sprint 15 step 1b live check (oer-s1512-)' -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-cat-b' -AssignmentPolicy 'oer-s1512-pol' -SelfReview -Recurrence OneTime -StartDate ((Get-Date).Date.AddDays(7)) -DurationInDays 3 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
if ($Rv.Id) { $Ids['rv'] = @{ Kind = 'access review definition'; Id = [string]$Rv.Id }; $Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Encoding utf8NoBOM }
Write-OerLiveStep "New-OERAccessReviewDefinition -Catalog catB: errors $(@($Err).Count)$(@($Err) | ForEach-Object { ' | ' + $_.FullyQualifiedErrorId })"
$R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions/$($Rv.Id)"
Write-OerLiveStep "Read back the review's scope query: $(T ([string]$R.Body.scope.query))"
Disconnect-OerLive
```

**Expect:** no error; the scope query filters on `accessPackage/id eq 'apB'` and `assignmentPolicy/id eq 'polB'`.
**Failure looks like:** `AmbiguousAccessPackageName`, or `apA`/`polA` in the query.

Result:

### 1.5. New-OERAccessPackage creates the package in the named catalog although the other one holds the name

- [ ] **1.5** `New-OERAccessPackage -Catalog catB` creates `oer-s1512-new` in `catB`, and a second call returns the same package.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
Connect-OerLive -Arm
$Err = $null
$P1 = New-OERAccessPackage -DisplayName 'oer-s1512-new' -Catalog 'oer-s1512-cat-b' -Description 'Sprint 15 step 1b live check (oer-s1512-)' -Hidden -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
if ($P1.Id) { $Ids['newB'] = @{ Kind = 'access package'; Id = [string]$P1.Id }; $Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Encoding utf8NoBOM; $Label[[string]$P1.Id] = 'newB' }
Write-OerLiveStep "First call: errors $(@($Err).Count)$(@($Err) | ForEach-Object { ' | ' + $_.FullyQualifiedErrorId }); package $(L ([string]$P1.Id)) in $(L ([string]$P1.CatalogId))"
Start-Sleep -Seconds 15
$Err = $null
$P2 = New-OERAccessPackage -DisplayName 'oer-s1512-new' -Catalog 'oer-s1512-cat-b' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
Write-OerLiveStep "Second call: errors $(@($Err).Count); package $(L ([string]$P2.Id)) in $(L ([string]$P2.CatalogId))"
$R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'oer-s1512-new'&`$expand=catalog"
Write-OerLiveStep "Packages named oer-s1512-new: $((@($R.Body.value) | ForEach-Object { '{0} in {1}' -f (L ([string]$_.id)), (L ([string]$_.catalog.id)) }) -join ', ')"
Disconnect-OerLive
```

**Expect:** first call no error, `newB in catB`; second call no error, `newB in catB` (returned, not
created again); two packages named `oer-s1512-new`: `newA in catA` and `newB in catB`.
**Failure looks like:** `AccessPackageInAnotherCatalog` (the old tenant-wide check), or a third package.

Result:

## 2. Refusals

### 2.1. Without -Catalog a shared name is refused as on main

- [ ] **2.1** Each of the eight cmdlets, given the shared name and no `-Catalog`, reports `AmbiguousAccessPackageName` and writes nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
Connect-OerLive -Arm
$Scope = New-OERAccessPackageRequestorScope -Scope NoSubjects
$Calls = [ordered]@{
    'Get-OERAccessPackageAssignment'       = { Get-OERAccessPackageAssignment -AccessPackage 'oer-s1512-ap' -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Get-OERAccessPackageAssignmentPolicy' = { Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s1512-ap' -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Get-OERAccessPackageResourceRole'     = { Get-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessPackageAssignment'       = { New-OERAccessPackageAssignment -AccessPackage 'oer-s1512-ap' -Policy $Ids.polA.Id -TargetId '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessPackageAssignmentPolicy' = { New-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s1512-ap' -DisplayName 'oer-s1512-pol-x' -RequestorScope $Scope -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Remove-OERAccessPackageResourceRole'  = { Remove-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -ResourceRoleScopeId '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Remove-OERAccessPackage'              = { Remove-OERAccessPackage -DisplayName 'oer-s1512-ap' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E -WarningAction SilentlyContinue }
    'Set-OERAccessPackage'                 = { Set-OERAccessPackage -DisplayName 'oer-s1512-ap' -Description 'must not be written' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
}
foreach ($N in $Calls.Keys) {
    $script:E = $null
    $null = & $Calls[$N]
    $Own = @(@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(",$N") })
    Write-OerLiveStep "${N}: $((@($Own) | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
}
$Em = 'v1.0/identityGovernance/entitlementManagement'
foreach ($K in 'apA', 'apB') {
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids[$K].Id)?`$expand=assignmentPolicies"
    Write-OerLiveStep "Read back ${K}: exists $($R.Ok); description untouched by 2.1: $([string]$R.Body.description -cne 'must not be written'); policy oer-s1512-pol-x: $(@($R.Body.assignmentPolicies | Where-Object displayName -eq 'oer-s1512-pol-x').Count)"
}
Disconnect-OerLive
```

**Expect:** each of the eight lines `AmbiguousAccessPackageName,<cmdlet>`; both packages exist,
description untouched `True`, policy `oer-s1512-pol-x` 0.
**Failure looks like:** any other id, or a write.

Result:

### 2.2. A package id of the other catalog is refused, and nothing is written

- [ ] **2.2** With `-Catalog catA` and the id of `apB`, each cmdlet reports `AccessPackageNotInCatalog` and writes nothing; `-Catalog` without `-AccessPackage` and an unknown catalog are refused too.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
Connect-OerLive -Arm
$B = $Ids.apB.Id
$A = 'oer-s1512-cat-a'
$Scope = New-OERAccessPackageRequestorScope -Scope NoSubjects
$Before = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages/$B`?`$expand=resourceRoleScopes,assignmentPolicies"
$Calls = [ordered]@{
    'Get-OERAccessPackageAssignment'       = { Get-OERAccessPackageAssignment -AccessPackage $B -Catalog $A -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Get-OERAccessPackageAssignmentPolicy' = { Get-OERAccessPackageAssignmentPolicy -AccessPackage $B -Catalog $A -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Get-OERAccessPackageResourceRole'     = { Get-OERAccessPackageResourceRole -AccessPackage $B -Catalog $A -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessPackageAssignment'       = { New-OERAccessPackageAssignment -AccessPackage $B -Catalog $A -Policy $Ids.polB.Id -TargetId '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessPackageAssignmentPolicy' = { New-OERAccessPackageAssignmentPolicy -AccessPackage $B -Catalog $A -DisplayName 'oer-s1512-pol-x' -RequestorScope $Scope -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Remove-OERAccessPackageResourceRole'  = { Remove-OERAccessPackageResourceRole -AccessPackage $B -Catalog $A -ResourceRoleScopeId '00000000-0000-0000-0000-000000000000' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Remove-OERAccessPackage'              = { Remove-OERAccessPackage -DisplayName $B -Catalog $A -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E -WarningAction SilentlyContinue }
    'Set-OERAccessPackage'                 = { Set-OERAccessPackage -DisplayName $B -Catalog $A -Description 'must not be written' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'Add-OERAccessPackageResourceRole'     = { Add-OERAccessPackageResourceRole -AccessPackage $B -Catalog $A -Group 'oer-s1512-grp' -Role 'Owner' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessReviewDefinition'        = { New-OERAccessReviewDefinition -DisplayName 'oer-s1512-rv-x' -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' -AccessPackage $B -Catalog $A -AssignmentPolicy $Ids.polB.Id -SelfReview -Recurrence OneTime -StartDate ((Get-Date).Date.AddDays(7)) -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
    'New-OERAccessPackage'                 = { New-OERAccessPackage -DisplayName $B -Catalog $A -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E }
}
foreach ($N in $Calls.Keys) {
    $script:E = $null
    $null = & $Calls[$N]
    $Own = @(@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(",$N") })
    Write-OerLiveStep "${N}: $((@($Own) | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
}
$Own = @(); $script:E = $null
$null = Get-OERAccessPackageAssignment -Catalog $A -ErrorAction SilentlyContinue -ErrorVariable script:E
Write-OerLiveStep "Get-OERAccessPackageAssignment -Catalog without -AccessPackage: $((@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERAccessPackageAssignment') } | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
$script:E = $null
$null = Get-OERAccessPackageResourceRole -AccessPackage 'oer-s1512-ap' -Catalog 'oer-s1512-nope' -ErrorAction SilentlyContinue -ErrorVariable script:E
Write-OerLiveStep "Get-OERAccessPackageResourceRole -Catalog of no catalog: $((@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERAccessPackageResourceRole') } | ForEach-Object { $_.FullyQualifiedErrorId + ' | ' + $_.Exception.Message }) -join ', ')"
$After = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages/$B`?`$expand=resourceRoleScopes,assignmentPolicies"
Write-OerLiveStep "apB unchanged: description $([string]$Before.Body.description -ceq [string]$After.Body.description); bindings $(@($Before.Body.resourceRoleScopes).Count) -> $(@($After.Body.resourceRoleScopes).Count); policies $(@($Before.Body.assignmentPolicies).Count) -> $(@($After.Body.assignmentPolicies).Count)"
$Rv = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq 'oer-s1512-rv-x'"
Write-OerLiveStep "Review oer-s1512-rv-x created: $(@($Rv.Body.value).Count)"
Disconnect-OerLive
```

**Expect:** each of the eleven lines `AccessPackageNotInCatalog,<cmdlet>`;
`CatalogWithoutAccessPackage,Get-OERAccessPackageAssignment`;
`CatalogNotFound,Get-OERAccessPackageResourceRole | Catalog 'oer-s1512-nope' not found.`; `apB`
unchanged (description `True`, bindings and policies the same counts); review created `0`.
**Failure looks like:** any other id, any write, or an `AccessPackageResolveFailed` from `New-OERAccessPackage`.

Result:

## 3. The pipeline

### 3.1. A piped package keeps its own catalog

- [ ] **3.1** `Get-OERAccessPackage -Catalog catB` piped into the read cmdlets reaches only `apB`; with `-Catalog catA` the piped `apB` is refused.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
Connect-OerLive -Arm
$Piped = @(Get-OERAccessPackage -Catalog 'oer-s1512-cat-b' | Where-Object DisplayName -eq 'oer-s1512-ap')
Write-OerLiveStep "Piped from catB: $((@($Piped) | ForEach-Object { L ([string]$_.Id) }) -join ', ')"
$Err = $null
$Rr = @($Piped | Get-OERAccessPackageResourceRole -ErrorAction SilentlyContinue -ErrorVariable Err)
Write-OerLiveStep "| Get-OERAccessPackageResourceRole: errors $(@($Err).Count); bindings of $((@($Rr) | ForEach-Object { L ([string]$_.AccessPackageId) } | Select-Object -Unique) -join ', ')"
$Err = $null
$Po = @($Piped | Get-OERAccessPackageAssignmentPolicy -Catalog 'oer-s1512-cat-b' -ErrorAction SilentlyContinue -ErrorVariable Err)
Write-OerLiveStep "| Get-OERAccessPackageAssignmentPolicy -Catalog catB: errors $(@($Err).Count); policies of $((@($Po) | ForEach-Object { L ([string]$_.AccessPackageId) } | Select-Object -Unique) -join ', ')"
$script:E = $null
$Po = @($Piped | Get-OERAccessPackageAssignmentPolicy -Catalog 'oer-s1512-cat-a' -ErrorAction SilentlyContinue -ErrorVariable script:E)
Write-OerLiveStep "| Get-OERAccessPackageAssignmentPolicy -Catalog catA: policies $(@($Po).Count); $((@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERAccessPackageAssignmentPolicy') } | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
$script:E = $null
$Piped | New-OERAccessPackageAssignment -Catalog 'oer-s1512-cat-a' -Policy $Ids.polB.Id -TargetId '00000000-0000-0000-0000-000000000000' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable script:E
Write-OerLiveStep "| New-OERAccessPackageAssignment -Catalog catA -WhatIf: $((@($script:E) | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',New-OERAccessPackageAssignment') } | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
Disconnect-OerLive
```

**Expect:** piped `apB`; bindings of `apB` with no error; policies of `apB` with no error; with
`-Catalog catA` 0 policies and `AccessPackageNotInCatalog,Get-OERAccessPackageAssignmentPolicy`; the
piped `New-OERAccessPackageAssignment -Catalog catA -WhatIf` `AccessPackageNotInCatalog,New-OERAccessPackageAssignment` and no
`What if` line (both cmdlets bind a piped package by its display name and, with `-Catalog`, check it by its own id).
**Failure looks like:** `apA` anywhere, or policies read with `-Catalog catA`.

Result:

## 4. The apply engine (G8)

### 4.1. A package created in its catalog while the other catalog holds the name, applied twice

- [ ] **4.1** `Invoke-OERStructure` creates `oer-s1512-eng` in `catB` (the name exists in `catA`), and a second run is `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1512-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's1512'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
Connect-OerLive -Arm
$Doc = Join-Path $Raw 'structure-4.1.json'
@{ accessPackages = @(@{ displayName = 'oer-s1512-eng'; catalog = 'oer-s1512-cat-b'; description = 'Sprint 15 step 1b live check (oer-s1512-)'; hidden = $true }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Doc -Encoding utf8NoBOM
foreach ($Run in 'plan', 'first', 'second') {
    $Err = $null
    $Rows = if ($Run -eq 'plan') { @(Invoke-OERStructure -Path $Doc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err) } else { @(Invoke-OERStructure -Path $Doc -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err) }
    Write-OerLiveStep "${Run}: errors $(@($Err).Count); rows: $((@($Rows) | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Item, $_.Action }) -join '; ')"
    if ($Run -eq 'first') { Start-Sleep -Seconds 30 }
}
$R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'oer-s1512-eng'&`$expand=catalog"
Write-OerLiveStep "Packages named oer-s1512-eng: $((@($R.Body.value) | ForEach-Object { '{0} in {1}' -f (L ([string]$_.id)), (L ([string]$_.catalog.id)) }) -join ', ')"
Disconnect-OerLive
```

**Expect:** plan `accessPackages oer-s1512-eng Skipped` (would create); first `Created`; second
`Unchanged`; two packages named `oer-s1512-eng`: `engA in catA` and one more (`another id`) in `catB`.
**Failure looks like:** the first run `Failed` with `AccessPackageInAnotherCatalog`, or a second create.

Result:

## T. Teardown

### T.1. Every prefixed object is removed

- [ ] **T.1** The teardown removes every `oer-s1512-` object and the sweep is 0.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS1512Prereq.ps1 -Teardown -Unattended
```

**Expect:** `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result:
