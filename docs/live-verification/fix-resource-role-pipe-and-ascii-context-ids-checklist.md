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

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.
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

Result: not yet run.

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.
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

Result: not yet run.

### 0.2. The prerequisite script's plan

- [ ] **0.2** `-WhatIf` plans only `oer-s181-` objects.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -WhatIf
```

**Expect:** the two permissions `True`; every `What if` line names an `oer-s181-` object (or, on a
re-run, none: the group exists).
**Failure looks like:** a target without the prefix, or a `STOP` -- STOP.

Result: not yet run.

### 0.3. The prerequisite script, for real

- [ ] **0.3** The group `oer-s181-g1` exists.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -Unattended
```

**Expect:** `Created group oer-s181-g1.` (or found); `Read back group g1: True`.
**Failure looks like:** a `STOP`, or `False` on the read back.

Result: not yet run.

## 1. The objects the reads need, written twice (G8)

### 1.1. Catalog with the group, access package with its Member role and a policy: Created, then only Unchanged

- [ ] **1.1** `Invoke-OERStructure` plans, creates and then finds unchanged the catalog and the access package.
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

Result: not yet run.

## 2. The reads give what the base build gave, and the policy and resource role pipes read their package (A, B)

### 2.1. The base build's reads, recorded

- [ ] **2.1** The base source (`021e976`) reads the package's resource roles by id and through the package, policy and resource role pipes, and the authentication contexts; the answers and the resource role requests are recorded.
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

Result: not yet run.

### 2.2. This branch's reads, compared with the base

- [ ] **2.2** This branch's build gives the same answer as the base for the explicit read, the package pipe and the contexts; the policy pipe and the resource role pipe now read their package's resource roles, and a piped object with an empty `AccessPackageId` is refused before any read.
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

Result: not yet run.

## T. Teardown

### T.1. Every prefixed object is removed

- [ ] **T.1** The teardown removes every `oer-s181-` object, and the sweep is 0.
```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS181Prereq.ps1 -Teardown -Unattended
```

**Expect:** the access package (with its policy and resource role), the catalog (with its resource) and
the group removed; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result: not yet run.
