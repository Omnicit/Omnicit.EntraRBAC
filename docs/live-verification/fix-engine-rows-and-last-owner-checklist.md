# Live verification checklist -- engine rows and the last standing owner (fix/engine-rows-and-last-owner)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects whose name starts with `oer-s124-`: two
disabled users, one security group with both users as standing owners (one of them also eligible
for owner access in PIM for Groups), two catalogs and one access package (created by the
prerequisite script), and one group that check 3.2 creates to prove the create path converges.
Every other check is a plan (`-WhatIf`) or a real run fenced so that a write request is refused
before it is sent. The teardown removes everything with the prefix and sweeps it to zero.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library,
which lives beside the operator's copy of this file outside the repository ([README.md](README.md),
first paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 is a
stop.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s124/`,
which is git-ignored. Every block prints through the library's redactor. **No credential, token,
application id, tenant id, subscription id, account or certificate thumbprint is ever printed** --
identities are printed as True or False, records as their error id and a count.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The last standing owner** ("Count only standing owners for the last-owner floors of the owner
  prune"). With `-Prune`, an owner whose ownership PIM for Groups holds or makes eligible no longer
  counts as an owner still standing, so the last standing owner, and the last standing user owner,
  is never removed while the others hold their ownership only through PIM (or are eligible for it):
  the removal is a Skipped row starting `prune withheld:`, in the plan and the run alike.
- **B. Rows a handler wrote before it threw** ("Keep the rows a handler wrote before it threw, and
  label the pre-pass error row"). `Invoke-OERStructure` reports them, in order, before the
  `handler error:` row.
- **C. The validator's warnings** ("Write the structure validator warnings before the apply
  starts"). `Invoke-OERStructure` writes every validator warning as a warning, before the sign-in
  and before the first write -- except the omitted-key warning, which the engine's own `-Prune`
  warning states for the keys it would remove.
- **D. The alias check in the plan** ("Plan runs the creation's alias check before it promises a
  create"). A new group without `mailNickname` whose derived alias Microsoft Graph would refuse is
  `Failed` with `DerivedMailNicknameInvalid` already under `-WhatIf`.
- **E. A refusal through the rename map writes a record** ("A refusal through the rename map writes its own error record"). The Failed row now comes with its own error record.
- **F. `New-OERAccessPackage -Catalog`** ("Refuse a same-named access package of another catalog in
  New-OERAccessPackage"). A name that exists only in another catalog is refused with
  `AccessPackageInAnotherCatalog`; nothing is returned or created.
- **G. A policy read without the value** ("Refuse an assignment policy update when the successful
  read lacks a value"). Proven offline only (see below).

## What this file does not check, and why

- **G, a successful policy read without `expiration` or `requestApprovalSettings`** (class B):
  Microsoft Graph v1.0 answers with every key, so the shape cannot be produced live. The unit tests
  of `Set-OERAccessPackageAssignmentPolicy`, `ConvertTo-OERPolicyBody` and the apply engine hold it.
- **A, an owner held by a PIM activation or a time-bound active assignment** (class B): `oer-live-cc`
  holds no PIM for Groups assignment-write scope, so such an owner cannot be made. Check 1 uses an
  owner that is a standing owner AND eligible for owner access, which the rule counts the same way.
- **The pre-pass label for an entry without a name** (class B): the validator refuses such a
  document before the pre-pass, so only the unit tests (validator mocked) reach it.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.
- The prerequisite script `Initialize-OerS124Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`** (check
6.1 depends on it).

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
foreach ($Marker in @(
        @('A', 'last standing user owner'),
        @('B', '-OutVariable HandlerRows'),
        @('C', 'structure document warning at'),
        @('D', 'function Get-OERDerivedMailNicknameProblem'),
        @('E', 'StructureReferenceUnidentified'),
        @('F', 'AccessPackageInAnotherCatalog'),
        @('G', 'AssignmentPolicyValueUnknown'))) {
    Write-OerLiveStep "The worktree's build carries $($Marker[0]): $([bool](Select-String -LiteralPath $Psm1 -SimpleMatch $Marker[1] -Quiet))"
}
Write-OerLiveStep "Prerequisite ids recorded: $(Test-Path -LiteralPath (Join-Path $Raw 'known-ids.json'))"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; A to G `True`; prerequisite ids
recorded `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a marker `False` -- build the worktree first (`./build.ps1 -Tasks build`), never while the
gate runs; ids `False` -- run the prerequisite script.

Result:

## 1. The last standing owner stays (A)

### 1.1. A plan with -Prune keeps the last standing user owner

- [ ] **1.1** `Invoke-OERStructure -Prune -WhatIf` on a document that declares only `oer-s124-owner-b` as owner of `oer-s124-owners`: `oer-s124-owner-a`, the only owner that is standing and not PIM-eligible, is Skipped with `prune withheld: ... last standing user owner ...`, no removal is planned, and nothing is written. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
$Ids = Get-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
$A = "oer-s124-owner-a@$($Cfg.UserDomain)"
$B = "oer-s124-owner-b@$($Cfg.UserDomain)"
$Doc = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s124-owners'; owners = @($B); members = $null; eligibility = $null }) } | ConvertTo-Json -Depth 5
$Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningVariable Warn 3>$null)
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
$OwnErr = @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId) -match ',Invoke-OERStructure$' })
$Pattern = "prune withheld: undeclared owner '$($Ids['owner-a'].Id)' is the last standing user owner*"
Write-OerLiveStep "Rows: $($Rows.Count); owner-a refused as the last standing user owner: $([bool]@($Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like $Pattern }))"
Write-OerLiveStep "A removal is planned: $([bool]@($Rows | Where-Object { $_.Detail -like 'would remove*' }))"
Write-OerLiveStep "Own error records: $($OwnErr.Count); warnings: $(@($Warn).Count); requests: $(Get-S124Count)"
Disconnect-OerLive
```

**Expect:** the module is the build `True`, the token fence `True`; a row `oer-s124-owners | Unchanged |
group properties match`, owner-b `Unchanged` (already present), owner-a `Skipped` with
`prune withheld: undeclared owner '...' is the last standing user owner of group 'oer-s124-owners':
the other 1 user owner(s) hold their ownership through PIM for Groups or are eligible for it there
...`; `owner-a refused as the last standing user owner: True`; `A removal is planned: False`;
0 own error records; 0 writes.
**Failure looks like:** `would remove undeclared owner` for owner-a -- the old count, which took
owner-b's eligible ownership as a standing owner; any write -- the fence would refuse it.

Result:

### 1.2. The real run with -Prune keeps the owner, twice (G8)

- [ ] **1.2** The same document applied for real with `-Prune -Confirm:$false`, twice: both runs give the rows of 1.1, no write request is made, and both users are still owners when read back. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
$Ids = Get-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
$B = "oer-s124-owner-b@$($Cfg.UserDomain)"
$Doc = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s124-owners'; owners = @($B); members = $null; eligibility = $null }) } | ConvertTo-Json -Depth 5
$Lines = @{}
foreach ($Run in 1, 2) {
    $Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningVariable Warn 3>$null)
    $Lines[$Run] = @($Rows | ForEach-Object { '{0}|{1}|{2}' -f $_.Item, $_.Action, $_.Detail })
    foreach ($R in $Rows) { Write-OerLiveStep ("run $Run row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
    $OwnErr = @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId) -match ',Invoke-OERStructure$' })
    Write-OerLiveStep "Run $Run`: rows $($Rows.Count); owner-a withheld: $([bool]@($Rows | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld:*last standing user owner*' })); removed rows: $(@($Rows | Where-Object { $_.Action -eq 'Removed' }).Count); own error records: $($OwnErr.Count); warnings: $(@($Warn).Count)"
}
Write-OerLiveStep "The two runs gave the same rows: $((@($Lines[1]) -join "`n") -ceq (@($Lines[2]) -join "`n")); requests over both runs: $(Get-S124Count)"
$Owners = Invoke-OerLiveGraph -Uri "v1.0/groups/$($Ids['group-owners'].Id)/owners?`$select=id" -All
$Got = @($Owners.Body.value | ForEach-Object { [string]$_.id })
Write-OerLiveStep "Read back: owner-a is an owner: $($Got -contains $Ids['owner-a'].Id); owner-b is an owner: $($Got -contains $Ids['owner-b'].Id)"
Disconnect-OerLive
```

**Expect:** each run the rows of 1.1 (owner-a withheld `True`, removed rows 0, 0 own error records);
`The two runs gave the same rows: True`; 0 writes; both owners `True` when read back.
**Failure looks like:** a `Removed` row or a fence refusal -- the run would have removed the last
standing owner; the runs differ -- not convergent.

Result:

## 2. The validator's warnings are written before anything else (C)

### 2.1. A document that renames a group and declares no mailNickname

- [ ] **2.1** A document that declares `oer-s124-owners` with `previousDisplayName` `oer-s124-owners-old` and no `mailNickname` (the validator warns that the alias does not follow a rename): a plan writes that warning once; with `-WarningAction Stop` the call stops at it with no request sent at all, so the warning stands before the sign-in and the first write. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
function Reset-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { $script:S124Log.Clear() } }
$Doc = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s124-owners'; previousDisplayName = 'oer-s124-owners-old'; members = $null; owners = $null; eligibility = $null }) } | ConvertTo-Json -Depth 5
$Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -WhatIf -ErrorAction SilentlyContinue -WarningVariable Warn 3>$null)
$Own = @($Warn | Where-Object { ([string]$_.Message).StartsWith('Invoke-OERStructure: structure document warning at ') })
Write-OerLiveStep "2.1a plan: rows $($Rows.Count); validator warnings written: $($Own.Count); first: $(if ($Own) { ConvertTo-OerLiveRedacted -Text ([string]$Own[0].Message) } else { '-' }); requests: $(Get-S124Count)"
Reset-S124Count
$Stopped = $false
$Rows2 = @()
try {
    $Rows2 = @(Invoke-OERStructure -Json $Doc -Include Groups -WhatIf -WarningAction Stop -ErrorAction SilentlyContinue 3>$null)
} catch {
    $Stopped = $true
}
Write-OerLiveStep "2.1b -WarningAction Stop: stopped at the warning: $Stopped; rows: $($Rows2.Count); requests after the stop: $(Get-S124Count)"
Disconnect-OerLive
```

**Expect:** 2.1a: `validator warnings written: 1`, the text `Invoke-OERStructure: structure document
warning at groups[0].mailNickname: Group at groups[0] is renamed from 'oer-s124-owners-old' and declares no mailNickname, ...`; 0 writes. 2.1b:
`stopped at the warning: True; rows: 0; requests after the stop: 0 read(s), 0 write(s)`.
**Failure looks like:** `validator warnings written: 0` -- the old behaviour (only `Test-OERStructure`
showed it); a request counted in 2.1b -- the warning stood after the first read.

Result:

## 3. The plan runs the creation's alias check (D)

### 3.1. A new group whose derived alias would be 69 characters

- [ ] **3.1** A new group named `oer-s124-` followed by 60 `x` characters and no `mailNickname`: the plan (`-WhatIf`) and the real run are each one `Failed` row with an own `DerivedMailNicknameInvalid` record, no `would create group` row, and no write. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
$LongName = 'oer-s124-' + ('x' * 60)
$Doc = @{ version = '1.0'; groups = @(@{ displayName = $LongName }) } | ConvertTo-Json -Depth 5
foreach ($Mode in 'plan', 'run') {
    $Common = @{ Json = $Doc; Include = 'Groups'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Err'; WarningVariable = 'Warn' }
    if ($Mode -eq 'plan') { $Common.WhatIf = $true } else { $Common.Confirm = $false }
    $Rows = @(Invoke-OERStructure @Common 3>$null)
    foreach ($R in $Rows) { Write-OerLiveStep ("$Mode row: {0} | {1} | {2}" -f ($R.Item -replace 'x{60}', '(60 x)'), $R.Action, $R.Detail.Replace($LongName, 'oer-s124-(60 x)')) }
    $OwnIds = @($Err | ForEach-Object { [string]$_.FullyQualifiedErrorId } | Where-Object { $_ -like 'DerivedMailNicknameInvalid,*' } | Sort-Object -Unique)
    Write-OerLiveStep "$Mode`: rows $($Rows.Count); Failed rows: $(@($Rows | Where-Object { $_.Action -eq 'Failed' }).Count); would create: $([bool]@($Rows | Where-Object { $_.Detail -like 'would create group*' })); DerivedMailNicknameInvalid record ids: $($OwnIds -join ', '); requests so far: $(Get-S124Count)"
}
$Exists = Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq '$LongName'&`$select=id"
Write-OerLiveStep "Read back: a group of that name exists: $(@($Exists.Body.value).Count -gt 0)"
Disconnect-OerLive
```

**Expect:** plan and run each `rows 1; Failed rows: 1; would create: False`, a record id
`DerivedMailNicknameInvalid,Invoke-OERStructure`, the row's Detail `group not created: The mail alias
derived from the group name 'oer-s124-(60 x)' is 69 characters long; Microsoft Graph accepts 1 to 64
characters. ...`; 0 writes; no such group.
**Failure looks like:** a plan row `would create group ...` -- the old plan; any write.

Result:

### 3.2. A valid new group is created once and then reached Unchanged (G8 for the create path)

- [ ] **3.2** A new group `oer-s124-created-1` with an alias it can carry: the first real run creates it, and a second run, after the group reads back by name, reports only `Unchanged` for it. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
$Name = 'oer-s124-created-1'
$Doc = @{ version = '1.0'; groups = @(@{ displayName = $Name; description = 'Sprint 12 step 4 live check'; members = $null; owners = $null; eligibility = $null }) } | ConvertTo-Json -Depth 5
$Rows1 = @(Invoke-OERStructure -Json $Doc -Include Groups -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err1 3>$null)
foreach ($R in $Rows1) { Write-OerLiveStep ("run 1 row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
$Read = Wait-OerLiveConverged -Activity 'the new group reads back by name' -Read {
    Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq '$Name'&`$select=id,description"
} -Test { param($R) $R.Ok -and @($R.Body.value).Count -eq 1 -and $R.Body.value[0].description -eq 'Sprint 12 step 4 live check' }
Start-Sleep -Seconds 30
$Rows2 = @(Invoke-OERStructure -Json $Doc -Include Groups -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err2 3>$null)
foreach ($R in $Rows2) { Write-OerLiveStep ("run 2 row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
Write-OerLiveStep "Run 1 created the group: $([bool]@($Rows1 | Where-Object { $_.Action -eq 'Created' })); run 2 only Unchanged: $((@($Rows2).Count -gt 0) -and -not @($Rows2 | Where-Object { $_.Action -ne 'Unchanged' })); errors: $(@($Err1).Count) and $(@($Err2).Count)"
Disconnect-OerLive
```

**Expect:** run 1 one `Created` row; run 2 only `Unchanged` rows; 0 errors in both.
**Failure looks like:** run 2 `Created` again or `Updated` -- the create path does not converge.

Result:

## 4. New-OERAccessPackage -Catalog refuses a package of another catalog (F)

### 4.1. The name exists only in the other catalog

- [ ] **4.1** `New-OERAccessPackage -DisplayName oer-s124-pkg -Catalog oer-s124-cat-1`, where only `oer-s124-cat-2` holds that name: a plan and a real call are each refused with `AccessPackageInAnotherCatalog`, return nothing, write nothing, and `oer-s124-cat-1` still holds no package. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
$Ids = Get-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
foreach ($Mode in 'plan', 'run') {
    $P = @{ DisplayName = 'oer-s124-pkg'; Catalog = 'oer-s124-cat-1'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'Err' }
    if ($Mode -eq 'plan') { $P.WhatIf = $true } else { $P.Confirm = $false }
    $Out = @(New-OERAccessPackage @P)
    $Own = @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId) -match ',New-OERAccessPackage$' })
    Write-OerLiveStep "$Mode`: objects returned: $($Out.Count); own records: $($Own.Count); ids: $((@($Own | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Sort-Object -Unique) -join ', '); message: $(if ($Own) { ConvertTo-OerLiveRedacted -Text ([string]$Own[0].Exception.Message) } else { '-' })"
}
Write-OerLiveStep "Requests: $(Get-S124Count)"
$InCat1 = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=catalog/id eq '$($Ids['cat-1'].Id)'&`$select=id"
Write-OerLiveStep "Read back: packages in oer-s124-cat-1: $(@($InCat1.Body.value).Count)"
Disconnect-OerLive
```

**Expect:** plan and run each `objects returned: 0; own records: 1; ids:
AccessPackageInAnotherCatalog,New-OERAccessPackage`, the message naming another catalog; 0 writes;
packages in `oer-s124-cat-1`: 0.
**Failure looks like:** an object returned -- the package of the other catalog handed back as if it
were in `oer-s124-cat-1`; a write.

Result:

### 4.2. The name in the given catalog is returned, twice, with nothing created (G8)

- [ ] **4.2** `New-OERAccessPackage -DisplayName oer-s124-pkg -Catalog oer-s124-cat-2`, twice: each call returns the existing package (the prerequisite's id), and no write request is made. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
$Ids = Get-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
foreach ($Call in 1, 2) {
    $Out = @(New-OERAccessPackage -DisplayName 'oer-s124-pkg' -Catalog 'oer-s124-cat-2' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
    Write-OerLiveStep "Call $Call`: objects returned: $($Out.Count); it is the prerequisite's package: $([string]$Out[0].Id -eq $Ids['pkg'].Id); in oer-s124-cat-2: $([string]$Out[0].CatalogId -eq $Ids['cat-2'].Id); errors: $(@($Err).Count)"
}
Write-OerLiveStep "Requests over both calls: $(Get-S124Count)"
Disconnect-OerLive
```

**Expect:** each call one object, the prerequisite's package `True`, in `oer-s124-cat-2` `True`, 0 errors;
0 writes.
**Failure looks like:** a refusal -- the catalog comparison would refuse its own catalog; a write.

Result:

## 5. A refusal through the rename map writes a record (E)

### 5.1. A group to be created into a unit whose rename this run does not decide

- [ ] **5.1** A group `oer-s124-in-unit` to be created into `oer-s124-unit-new`, which the document renames from `oer-s124-unit-old`, applied with `-Include Groups` as a plan: one `Failed` row, an own `StructureReferenceUnidentified` record, `$?` false, and nothing written. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
$Doc = @{
    version             = '1.0'
    groups              = @(@{ displayName = 'oer-s124-in-unit'; administrativeUnit = 'oer-s124-unit-new' })
    administrativeUnits = @(@{ displayName = 'oer-s124-unit-new'; previousDisplayName = 'oer-s124-unit-old' })
} | ConvertTo-Json -Depth 5
$Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningVariable Warn 3>$null)
$Ok = $?
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
$Own = @($Err | Where-Object { ([string]$_.FullyQualifiedErrorId) -like 'StructureReferenceUnidentified,*' })
Write-OerLiveStep "Rows: $($Rows.Count); Failed: $(@($Rows | Where-Object { $_.Action -eq 'Failed' }).Count); the row carries the record: $([bool]@($Rows | Where-Object { $_.ErrorRecord -and ([string]$_.ErrorRecord.FullyQualifiedErrorId) -like 'StructureReferenceUnidentified*' })); StructureReferenceUnidentified records: $($Own.Count); `$?: $Ok; requests: $(Get-S124Count)"
Disconnect-OerLive
```

**Expect:** one `Failed` row for `oer-s124-in-unit` (`group not created: administrative unit
'oer-s124-unit-new' was not reconciled in this run ...`), the row carries the record `True`, at least
one `StructureReferenceUnidentified` record (the engine may publish it once more as the caller),
`$?: False`, 0 writes.
**Failure looks like:** `StructureReferenceUnidentified records: 0` and `$?: True` -- the old shape,
a row with no record.

Result:

## 6. Rows written before a handler stops are reported (B)

### 6.1. A run that cannot confirm its first change

- [ ] **6.1** In a process started with `-NonInteractive`, a real run without `-Confirm:$false` of a document that adds `oer-s124-owner-a` as a member of `oer-s124-owners`: the handler writes the `group properties match` row, then stops at the confirmation prompt the host cannot show; the output holds that row followed by the `handler error:` row, and nothing is written. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Write-OerLiveStep "This process is non-interactive: $([Environment]::GetCommandLineArgs() -contains '-NonInteractive')"
function global:Get-AzToken { throw 'S124 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S124Log = [System.Collections.Generic.List[string]]::new()
    $script:S124Fence = $true
    $script:S124Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S124Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S124Fence) { throw "S124 fence: a $Method request was refused; this check expects no write." }
        & $script:S124Real @PSBoundParameters
    }
}
function Get-S124Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S124Log | Where-Object { $_ -eq 'read' }).Count, @($script:S124Log | Where-Object { $_ -ne 'read' }).Count } }
$A = "oer-s124-owner-a@$($Cfg.UserDomain)"
$Doc = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s124-owners'; members = @($A); owners = $null; eligibility = $null }) } | ConvertTo-Json -Depth 5
$Rows = @(Invoke-OERStructure -Json $Doc -Include Groups -ErrorAction SilentlyContinue -ErrorVariable Err 3>$null)
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2}" -f $R.Item, $R.Action, $R.Detail) }
Write-OerLiveStep "Rows: $($Rows.Count); first: $(if ($Rows) { $Rows[0].Action + ' ' + $Rows[0].Detail } else { '-' }); last is the handler error: $([bool]($Rows -and $Rows[-1].Action -eq 'Failed' -and $Rows[-1].Detail -like 'handler error:*'))"
Write-OerLiveStep "Requests: $(Get-S124Count)"
$Members = Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq 'oer-s124-owners'&`$select=id&`$expand=members(`$select=id)"
Write-OerLiveStep "Read back: members of oer-s124-owners: $(@($Members.Body.value[0].members).Count)"
Disconnect-OerLive
```

**Expect:** the process is non-interactive `True`; rows: `Unchanged | group properties match`, then
`Failed | handler error: the host cannot show the confirmation prompt ...`; `last is the handler error:
True`; 0 writes; members 0.
**Failure looks like:** only the `handler error:` row -- the rows written before the stop were lost
(the old shape); a member added -- the prompt did not stop the write.

Result:

## Teardown

### T.1. Remove every object with the prefix

- [ ] **T.1** The prerequisite script's teardown removes every `oer-s124-` object (the two users, the two groups including `oer-s124-created-1`, the eligibility, the package and both catalogs) and its sweep ends at 0. #type/subtask

```powershell
pwsh -NoProfile -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS124Prereq.ps1') -Teardown -Unattended
```

**Expect:** `Teardown summary` with `Residue 0`; `Sweep: 0 object(s) with the prefix, 0 unread kind(s)`;
`Teardown complete: the sweep is 0.`
**Failure looks like:** residue or a sweep above 0 after five minutes -- run `-Teardown` again later
and record the residue here.

Result:

### T.2. The sweep is still 0 a minute later, and raw output is removed

- [ ] **T.2** A minute after T.1 the prefix sweep is still 0, no session is left, and `raw\s124` is deleted after the results are copied here. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s124-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s124'
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count) object(s) with the prefix; unread kinds: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "No module session is left: $($null -eq (& (Get-Module -Name Omnicit.EntraRBAC -ErrorAction SilentlyContinue) { $script:_OERAuthState } 2>$null))"
```

**Expect:** `Sweep: 0 object(s) with the prefix; unread kinds: 0`; no session left `True`. Then
delete `raw\s124` (after every Result above is written) and clear the redaction map.
**Failure looks like:** an object listed -- run T.1 again.

Result:
