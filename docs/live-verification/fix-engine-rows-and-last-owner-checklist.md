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

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Run 2026-11-05 UTC, no sign-in. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at b2c3322 with 0 tracked changes; its build (made at 785a278, gated green: 13597 passed, 0 failed, coverage 96.42 %) carries A to G; the prerequisite ids are recorded.

[oer-s124] The module loads from a worktree that is not the main clone: True
[oer-s124] Main clone: branch main
[oer-s124] Worktree: branch fix/engine-rows-and-last-owner; HEAD b2c3322 Add the live verification checklist for the engine rows and the last owner; tracked changes: 0
[oer-s124] The worktree's build carries A: True
[oer-s124] The worktree's build carries B: True
[oer-s124] The worktree's build carries C: True
[oer-s124] The worktree's build carries D: True
[oer-s124] The worktree's build carries E: True
[oer-s124] The worktree's build carries F: True
[oer-s124] The worktree's build carries G: True
[oer-s124] Prerequisite ids recorded: True
```

## 1. The last standing owner stays (A)

### 1.1. A plan with -Prune keeps the last standing user owner

- [x] **1.1** `Invoke-OERStructure -Prune -WhatIf` on a document that declares only `oer-s124-owner-b` as owner of `oer-s124-owners`: `oer-s124-owner-a`, the only owner that is standing and not PIM-eligible, is Skipped with `prune withheld: ... last standing user owner ...`, no removal is planned, and nothing is written. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. As oer-live-cc (every identity line True), the build in the worktree, token fence in place. The plan with -Prune keeps owner-a, the only standing owner that is not PIM-eligible, as the last standing user owner (prune withheld, the new text, the other user owner counted 1); owner-b Unchanged; no removal planned; 0 own records, 0 warnings, 9 reads, 0 writes.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] row: oer-s124-owners | Unchanged | group properties match
[oer-s124] row: oer-s124-owners | Unchanged | owner 'oer-s124-owner-b@example.com' already present
[oer-s124] row: oer-s124-owners | Skipped | prune withheld: undeclared owner '00000000-0000-0000-0000-000000000001' is the last standing user owner of group 'oer-s124-owners': the other 1 user owner(s) hold their ownership through PIM for Groups or are eligible for it there (an activation, a time-bound assignment or an eligibility), so they do not count as standing, and removing it could leave the group without a user owner; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember -AccessType owner if it is meant to go.
[oer-s124] Rows: 3; owner-a refused as the last standing user owner: True
[oer-s124] A removal is planned: False
[oer-s124] Own error records: 0; warnings: 0; requests: 9 read(s), 0 write(s)
```

### 1.2. The real run with -Prune keeps the owner, twice (G8)

- [x] **1.2** The same document applied for real with `-Prune -Confirm:$false`, twice: both runs give the rows of 1.1, no write request is made, and both users are still owners when read back. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The real run with -Prune -Confirm:$false, twice: both runs give the rows of 1.1, no Removed row, 0 own records, 0 warnings; the two runs are identical (G8); 18 reads and 0 writes over both runs; both users are still owners when read back.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] run 1 row: oer-s124-owners | Unchanged | group properties match
[oer-s124] run 1 row: oer-s124-owners | Unchanged | owner 'oer-s124-owner-b@example.com' already present
[oer-s124] run 1 row: oer-s124-owners | Skipped | prune withheld: undeclared owner '00000000-0000-0000-0000-000000000001' is the last standing user owner of group 'oer-s124-owners': the other 1 user owner(s) hold their ownership through PIM for Groups or are eligible for it there (an activation, a time-bound assignment or an eligibility), so they do not count as standing, and removing it could leave the group without a user owner; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember -AccessType owner if it is meant to go.
[oer-s124] Run 1: rows 3; owner-a withheld: True; removed rows: 0; own error records: 0; warnings: 0
[oer-s124] run 2 row: oer-s124-owners | Unchanged | group properties match
[oer-s124] run 2 row: oer-s124-owners | Unchanged | owner 'oer-s124-owner-b@example.com' already present
[oer-s124] run 2 row: oer-s124-owners | Skipped | prune withheld: undeclared owner '00000000-0000-0000-0000-000000000001' is the last standing user owner of group 'oer-s124-owners': the other 1 user owner(s) hold their ownership through PIM for Groups or are eligible for it there (an activation, a time-bound assignment or an eligibility), so they do not count as standing, and removing it could leave the group without a user owner; it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember -AccessType owner if it is meant to go.
[oer-s124] Run 2: rows 3; owner-a withheld: True; removed rows: 0; own error records: 0; warnings: 0
[oer-s124] The two runs gave the same rows: True; requests over both runs: 18 read(s), 0 write(s)
[oer-s124] Read back: owner-a is an owner: True; owner-b is an owner: True
```

## 2. The validator's warnings are written before anything else (C)

### 2.1. A document that renames a group and declares no mailNickname

- [x] **2.1** A document that declares `oer-s124-owners` with `previousDisplayName` `oer-s124-owners-old` and no `mailNickname` (the validator warns that the alias does not follow a rename): a plan writes that warning once; with `-WarningAction Stop` the call stops at it with no request sent at all, so the warning stands before the sign-in and the first write. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A document that renames oer-s124-owners from oer-s124-owners-old without mailNickname: the plan writes exactly one validator warning with the expected text, 0 writes; under -WarningAction Stop the call stops at that warning with 0 requests of any kind, so the warning stands before the first read and the first write.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] 2.1a plan: rows 1; validator warnings written: 1; first: Invoke-OERStructure: structure document warning at groups[0].mailNickname: Group at groups[0] is renamed from 'oer-s124-owners-old' and declares no mailNickname, so it keeps its current mail alias: the alias does not follow a rename. If that alias was derived from the old name, declare mailNickname with the alias the new name should carry.; requests: 5 read(s), 0 write(s)
[oer-s124] 2.1b -WarningAction Stop: stopped at the warning: True; rows: 0; requests after the stop: 0 read(s), 0 write(s)
```

## 3. The plan runs the creation's alias check (D)

### 3.1. A new group whose derived alias would be 69 characters

- [x] **3.1** A new group named `oer-s124-` followed by 60 `x` characters and no `mailNickname`: the plan (`-WhatIf`) and the real run are each one `Failed` row with an own `DerivedMailNicknameInvalid` record, no `would create group` row, and no write. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A new group oer-s124- followed by 60 x and no mailNickname: the plan and the real run are each one Failed row (group not created: ... 69 characters long ...) with an own DerivedMailNicknameInvalid record, no would-create row, 0 writes; no group of that name exists.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] plan row: oer-s124-(60 x) | Failed | group not created: The mail alias derived from the group name 'oer-s124-(60 x)' is 69 characters long; Microsoft Graph accepts 1 to 64 characters. Nothing was sent. Pass -MailNickname with the alias the group should carry.
[oer-s124] plan: rows 1; Failed rows: 1; would create: False; DerivedMailNicknameInvalid record ids: DerivedMailNicknameInvalid,Invoke-OERStructure; requests so far: 1 read(s), 0 write(s)
[oer-s124] run row: oer-s124-(60 x) | Failed | group not created: The mail alias derived from the group name 'oer-s124-(60 x)' is 69 characters long; Microsoft Graph accepts 1 to 64 characters. Nothing was sent. Pass -MailNickname with the alias the group should carry.
[oer-s124] run: rows 1; Failed rows: 1; would create: False; DerivedMailNicknameInvalid record ids: DerivedMailNicknameInvalid,Invoke-OERStructure; requests so far: 2 read(s), 0 write(s)
[oer-s124] Read back: a group of that name exists: False
```

### 3.2. A valid new group is created once and then reached Unchanged (G8 for the create path)

- [x] **3.2** A new group `oer-s124-created-1` with an alias it can carry: the first real run creates it, and a second run, after the group reads back by name, reports only `Unchanged` for it. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS (G8 for the create path). Run 1 created oer-s124-created-1; after it read back by name (converged after 4 reads, 14.6 s) and a 30 s settle, run 2 reported only Unchanged; 0 errors in both runs.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] run 1 row: oer-s124-created-1 | Created | created group oer-s124-created-1 (00000000-0000-0000-0000-000000000002)
[oer-s124] the new group reads back by name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s124] the new group reads back by name: not yet (read 2, 2.3 s, likely replication delay) -- reading again in 4 s.
[oer-s124] the new group reads back by name: not yet (read 3, 6.6 s, likely replication delay) -- reading again in 8 s.
[oer-s124] the new group reads back by name: converged after 4 read(s), 14.6 s.
[oer-s124] run 2 row: oer-s124-created-1 | Unchanged | group properties match
[oer-s124] Run 1 created the group: True; run 2 only Unchanged: True; errors: 0 and 0
```

## 4. New-OERAccessPackage -Catalog refuses a package of another catalog (F)

### 4.1. The name exists only in the other catalog

- [x] **4.1** `New-OERAccessPackage -DisplayName oer-s124-pkg -Catalog oer-s124-cat-1`, where only `oer-s124-cat-2` holds that name: a plan and a real call are each refused with `AccessPackageInAnotherCatalog`, return nothing, write nothing, and `oer-s124-cat-1` still holds no package. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. New-OERAccessPackage -DisplayName oer-s124-pkg -Catalog oer-s124-cat-1 (only oer-s124-cat-2 holds the name): plan and real call each return nothing and write one AccessPackageInAnotherCatalog record naming both catalogs; 6 reads, 0 writes; oer-s124-cat-1 holds 0 packages.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] plan: objects returned: 0; own records: 1; ids: AccessPackageInAnotherCatalog,New-OERAccessPackage; message: Access package 'oer-s124-pkg' exists in another catalog (00000000-0000-0000-0000-000000000003), not in catalog 'oer-s124-cat-1' (00000000-0000-0000-0000-000000000004), so it was not returned and nothing was created. Access package names are unique only within a catalog, and this command looks the name up in the whole tenant; use a name no other access package carries.
[oer-s124] run: objects returned: 0; own records: 1; ids: AccessPackageInAnotherCatalog,New-OERAccessPackage; message: Access package 'oer-s124-pkg' exists in another catalog (00000000-0000-0000-0000-000000000003), not in catalog 'oer-s124-cat-1' (00000000-0000-0000-0000-000000000004), so it was not returned and nothing was created. Access package names are unique only within a catalog, and this command looks the name up in the whole tenant; use a name no other access package carries.
[oer-s124] Requests: 6 read(s), 0 write(s)
[oer-s124] Read back: packages in oer-s124-cat-1: 0
```

### 4.2. The name in the given catalog is returned, twice, with nothing created (G8)

- [x] **4.2** `New-OERAccessPackage -DisplayName oer-s124-pkg -Catalog oer-s124-cat-2`, twice: each call returns the existing package (the prerequisite's id), and no write request is made. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS (G8). New-OERAccessPackage -Catalog oer-s124-cat-2, twice: each call returns the prerequisite's package in oer-s124-cat-2, 0 errors; 6 reads, 0 writes over both calls.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] Call 1: objects returned: 1; it is the prerequisite's package: True; in oer-s124-cat-2: True; errors: 0
[oer-s124] Call 2: objects returned: 1; it is the prerequisite's package: True; in oer-s124-cat-2: True; errors: 0
[oer-s124] Requests over both calls: 6 read(s), 0 write(s)
```

## 5. A refusal through the rename map writes a record (E)

### 5.1. A group to be created into a unit whose rename this run does not decide

- [x] **5.1** A group `oer-s124-in-unit` to be created into `oer-s124-unit-new`, which the document renames from `oer-s124-unit-old`, applied with `-Include Groups` as a plan: one `Failed` row, an own `StructureReferenceUnidentified` record, `$?` false, and nothing written. #type/subtask

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
Write-OerLiveStep "Rows: $($Rows.Count); Failed: $(@($Rows | Where-Object { $_.Action -eq 'Failed' }).Count); the row carries the record: $([bool]@($Rows | Where-Object { $_.Error -and ([string]$_.Error.FullyQualifiedErrorId) -like 'StructureReferenceUnidentified*' })); StructureReferenceUnidentified records: $($Own.Count); `$?: $Ok; requests: $(Get-S124Count)"
Disconnect-OerLive
```

**Expect:** one `Failed` row for `oer-s124-in-unit` (`group not created: administrative unit
'oer-s124-unit-new' was not reconciled in this run ...`), the row carries the record `True`, at least
one `StructureReferenceUnidentified` record (the engine may publish it once more as the caller),
`$?: False`, 0 writes.
**Failure looks like:** `StructureReferenceUnidentified records: 0` and `$?: True` -- the old shape,
a row with no record.

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A group to be created into a unit the document renames, applied with -Include Groups as a plan: one Failed row carrying its record, one own StructureReferenceUnidentified record, $? False, 1 read, 0 writes. First run of the block printed "the row carries the record: False": the block read the row's ErrorRecord property, but the result row names it Error; the block was corrected and run again (output below).

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] Token fence in place: True
[oer-s124] row: oer-s124-in-unit | Failed | group not created: administrative unit 'oer-s124-unit-new' was not reconciled in this run -- its rename from 'oer-s124-unit-old' was refused (the administrativeUnits section is not selected by -Include, so its rename is not reconciled in this run), so the unit the group is to be created into cannot be identified
[oer-s124] Rows: 1; Failed: 1; the row carries the record: True; StructureReferenceUnidentified records: 1; $?: False; requests: 1 read(s), 0 write(s)
```

## 6. Rows written before a handler stops are reported (B)

### 6.1. A run that cannot confirm its first change

- [x] **6.1** In a process started with `-NonInteractive`, a real run without `-Confirm:$false` of a document that adds `oer-s124-owner-a` as a member of `oer-s124-owners`: the handler writes the `group properties match` row, then stops at the confirmation prompt the host cannot show; the output holds that row followed by the `handler error:` row, and nothing is written. #type/subtask

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

Result: 2026-11-05 01:49 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. In a -NonInteractive process, a real run without -Confirm:$false that would add owner-a as a member: the output holds the Unchanged "group properties match" row the handler wrote first, then the handler error (the host cannot show the confirmation prompt); 7 reads, 0 writes; the group still has 0 members.

[oer-s124] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg4\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s124] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s124] The module is the worktree's build: True
[oer-s124] This process is non-interactive: True
[oer-s124] Token fence in place: True
[oer-s124] row: oer-s124-owners | Unchanged | group properties match
[oer-s124] row: oer-s124-owners | Failed | handler error: the host cannot show the confirmation prompt Invoke-OERStructure asks before each change (PowerShell is in NonInteractive mode. Read and Prompt functionality is not available.); nothing was written for this entry. Run Invoke-OERStructure with -Confirm:$false to apply without prompts, or with -WhatIf to plan.
[oer-s124] Rows: 2; first: Unchanged group properties match; last is the handler error: True
[oer-s124] Requests: 7 read(s), 0 write(s)
[oer-s124] Read back: members of oer-s124-owners: 0
```

## Teardown

### T.1. Remove every object with the prefix

- [x] **T.1** The prerequisite script's teardown removes every `oer-s124-` object (the two users, the two groups including `oer-s124-created-1`, the eligibility, the package and both catalogs) and its sweep ends at 0. #type/subtask

```powershell
pwsh -NoProfile -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS124Prereq.ps1') -Teardown -Unattended
```

**Expect:** `Teardown summary` with `Residue 0`; `Sweep: 0 object(s) with the prefix, 0 unread kind(s)`;
`Teardown complete: the sweep is 0.`
**Failure looks like:** residue or a sweep above 0 after five minutes -- run `-Teardown` again later
and record the residue here.

Result: 2026-11-05 01:50 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The prerequisite script's teardown removed every oer-s124- object: 8 removed (the owner eligibility, the package, both catalogs, both groups including oer-s124-created-1, both users), residue 0, unreadable 0, already gone 0, skipped 2 (the two owner rows of the PIM assignment schedules, which the group's deletion removes); its sweep ended at 0 after one 30 s wait. The script's own summary line printed wrong counts (a counting bug in the script, fixed after the run); OerLive's line below is the authority.

[oer-s124] Transcript (redacted): raw\s124\prereq-teardown-20261105-014812Z.log; OerLive 1.1.0.
[oer-s124] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s124] Teardown of 'oer-s124-': users 2, groups 2, access packages 1, access review definitions 0, catalogs 2; administrative units 0 and app registrations 0 are reported only.
[oer-s124] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s124] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s124] Removed: oer-s124-owners: PIM for Groups owner eligibility of a principal (201).
[oer-s124] oer-s124-owners: PIM for Groups owner assignment skipped: deleting the group removes it (1.1.0, BL-122; adminRemove answered 400 CannotDeleteLastAdminAssignment).
[oer-s124] oer-s124-owners: PIM for Groups owner assignment skipped: deleting the group removes it (1.1.0, BL-122; adminRemove answered 400 CannotDeleteLastAdminAssignment).
[oer-s124] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s124] Deleted: access package oer-s124-pkg (204, 1 attempt(s)).
[oer-s124] Deleted: catalog oer-s124-cat-2 (204, 1 attempt(s)).
[oer-s124] Deleted: catalog oer-s124-cat-1 (204, 1 attempt(s)).
[oer-s124] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s124] Teardown 5/6: the prefixed groups.
[oer-s124] Deleted: group oer-s124-created-1 (204).
[oer-s124] Deleted: group oer-s124-owners (204).
[oer-s124] Teardown 6/6: the prefixed users.
[oer-s124] DELETE user oer-s124-owner-a@example.com: 204  after 1 attempt(s), 0.2 s; first attempt no membership removed in this run.
[oer-s124] DELETE user oer-s124-owner-b@example.com: 204  after 1 attempt(s), 0.1 s; first attempt no membership removed in this run.
[oer-s124] Teardown of 'oer-s124-': removed 8, residue 0, unreadable 0, already gone 0, skipped 2.
[oer-s124] Sweep: 2 object(s) with the prefix, 0 unread kind(s).
[oer-s124] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s124-' is left.
[oer-s124] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s124-' is left.
[oer-s124] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s124] Teardown complete: the sweep is 0.
```

### T.2. The sweep is still 0 a minute later, and raw output is removed

- [x] **T.2** A minute after T.1 the prefix sweep is still 0, no session is left, and `raw\s124` is deleted after the results are copied here. #type/subtask

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

Result: 2026-11-05 01:50 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A minute after T.1 the sweep is 0 with 0 unread kinds, and no module session is left. raw\s124 is deleted after the results were copied, and the redaction map is cleared after the report (this block signs in through Connect-OerLive -Graph, which loads the main clone's older build; only Graph reads are made).

[oer-s124] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s124] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s124] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s124] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s124] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s124] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s124] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s124] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s124] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s124-' is left.
[oer-s124] Sweep: 0 object(s) with the prefix; unread kinds: 0
[oer-s124] No module session is left: True
```

## Round 1 (A12): the plan of a new review, and a policy read without its settings

Round 1 of the step (the architect's decision A12 after the review of PR 77) changes two things:

- **H. A plan's review of a package the run would create** ("A plan's review of a package the run
  would create writes no error record"). Under `-WhatIf` (or after a declined confirmation of the
  package's create) the review of a package the same document creates is `Failed` as in 1.3.1 --
  "has no id in this run" -- but writes NO error record any more, so the plan of a new document has
  `$?` true and does not stop under `-ErrorAction Stop`; the real run creates the package and then the
  review. A real refusal (a refused or undecided rename, `-Include`, an entry that stopped first) keeps
  its record.
- **I. A policy read without `requestorSettings` or `notificationSettings`**
  (`Set-OERAccessPackageAssignmentPolicy`). Such a read is refused with `AssignmentPolicyValueUnknown`
  unless the call names the value (`-RequestorSettings`, `-DisableAssignmentNotifications`). Class B,
  like G: Microsoft Graph v1.0 answers with both keys, so only the unit tests reach the shape.

**What round 1 writes to the tenant.** Only objects whose name starts with `oer-s1241-`, all created
by check R1.2 through `Invoke-OERStructure`: one catalog, one access package in it with one assignment
policy (admin assignment only, so nobody can request it), and one one-time self review of that policy.
The prerequisite script `Initialize-OerS1241Prereq.ps1` creates nothing: it writes the baseline (the
prefix must be empty) and owns the teardown. Raw output goes to `docs/live-verification/raw/s1241/`.

The document every check applies (built in each block):

```json
{ "version": "1.0",
  "catalogs": [ { "displayName": "oer-s1241-cat", "description": "Sprint 12 step 4 round 1 live check" } ],
  "accessPackages": [ { "displayName": "oer-s1241-pkg", "catalog": "oer-s1241-cat",
      "description": "Sprint 12 step 4 round 1 live check", "resourceRoles": [],
      "assignmentPolicies": [ { "displayName": "oer-s1241-policy",
          "requestorScope": { "scope": "NotSpecified" }, "durationInDays": 30 } ] } ],
  "accessReviews": [ { "displayName": "oer-s1241-review", "accessPackage": "oer-s1241-pkg",
      "assignmentPolicy": "oer-s1241-policy", "reviewers": [], "recurrence": "OneTime",
      "durationInDays": 14 } ] }
```

### R1.S. The build carries round 1, and the prefix is empty

- [ ] **R1.S** The worktree's build carries H and I, and the prerequisite script's baseline finds no `oer-s1241-` object. #type/subtask

```powershell
pwsh -NoProfile -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS1241Prereq.ps1') -Unattended
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1241-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
foreach ($Marker in @(@('H', 'CreatePending'), @('I', 'RequestorSettingsUnknown'))) {
    Write-OerLiveStep "The worktree's build carries $($Marker[0]): $([bool](Select-String -LiteralPath $Psm1 -SimpleMatch $Marker[1] -Quiet))"
}
```

**Expect:** `Baseline sweep: 0 object(s) with the prefix, 0 unread kind(s)`; `Baseline written: True`;
`The prefix is empty, as check R1.1 needs: True`; the worktree on this branch with 0 tracked changes;
H and I `True`.
**Failure looks like:** an object with the prefix -- run the teardown first; a marker `False` -- build
the worktree (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### R1.1. The plan of the new document writes no error record

- [ ] **R1.1** `Invoke-OERStructure -WhatIf` on the document: the catalog and the package are planned, the review is `Failed` with "has no id in this run" and no error record, `$?` is `True`, the same plan under `-ErrorAction Stop` completes, and nothing is written. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1241-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S1241 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "Token fence in place: $((& $Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
& $Module {
    $script:S1241Log = [System.Collections.Generic.List[string]]::new()
    $script:S1241Fence = $true
    $script:S1241Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S1241Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read -and $script:S1241Fence) { throw "S1241 fence: a $Method request was refused; this check expects no write." }
        & $script:S1241Real @PSBoundParameters
    }
}
function Get-S1241Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S1241Log | Where-Object { $_ -eq 'read' }).Count, @($script:S1241Log | Where-Object { $_ -ne 'read' }).Count } }
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check' })
    accessPackages = @([ordered]@{
            displayName = 'oer-s1241-pkg'; catalog = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check'; resourceRoles = @()
            assignmentPolicies = @([ordered]@{ displayName = 'oer-s1241-policy'; requestorScope = @{ scope = 'NotSpecified' }; durationInDays = 30 })
        })
    accessReviews  = @([ordered]@{ displayName = 'oer-s1241-review'; accessPackage = 'oer-s1241-pkg'; assignmentPolicy = 'oer-s1241-policy'; reviewers = @(); recurrence = 'OneTime'; durationInDays = 14 })
} | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3} | record: {4}" -f $R.Section, $R.Item, $R.Action, $R.Detail, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) }
Write-OerLiveStep "Plan: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count)"
$StopOutcome = try {
    $null = Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction Stop -OutVariable StopRows 3>$null
    "completed with $(@($StopRows).Count) rows"
} catch { "stopped: $(([string]$PSItem.FullyQualifiedErrorId -split ',')[0])" }
Write-OerLiveStep "Plan under -ErrorAction Stop: $StopOutcome"
Write-OerLiveStep "Requests over both plans: $(Get-S1241Count)"
Disconnect-OerLive
```

**Expect:** the module is the build `True`, the token fence `True`; rows `catalogs | oer-s1241-cat |
Skipped | would create catalog ...`, `accessPackages | oer-s1241-pkg | Skipped | would create access
package oer-s1241-pkg`, `accessPackages | oer-s1241-pkg | Skipped | would create assignmentPolicy
'oer-s1241-policy' after access package is created`, and `accessReviews | oer-s1241-review | Failed | access package 'oer-s1241-pkg'
has no id in this run (the accessPackages entry would create it, and the create was not carried out:
-WhatIf, or a declined confirmation), ...` with `record: none`; `$? True`; 0 error records; the plan
under Stop `completed` with the same number of rows; 0 writes.
**Failure looks like:** `record: StructureReferenceUnidentified` or `$? False` -- the plan still
writes the refusal as an error; `stopped:` -- the plan stops under Stop although the real run succeeds.

Result:

### R1.2. The real run of the same document creates the package and then the review

- [ ] **R1.2** The same document with `-Confirm:$false`: the catalog, the package, its policy and the review are `Created`, `$?` is `True`, and the review read back reviews that package. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1241-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s1241'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S1241 fence: no token request is expected after the sign-in.' }
& $Module {
    $script:S1241Log = [System.Collections.Generic.List[string]]::new()
    $script:S1241Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        if (-not $Read -and $Body -and $Body.ContainsKey('displayName') -and -not ([string]$Body.displayName).StartsWith('oer-s1241-')) { throw "S1241 fence: a $Method of an object without the prefix was refused." }
        $script:S1241Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        & $script:S1241Real @PSBoundParameters
    }
}
function Get-S1241Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S1241Log | Where-Object { $_ -eq 'read' }).Count, @($script:S1241Log | Where-Object { $_ -ne 'read' }).Count } }
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check' })
    accessPackages = @([ordered]@{
            displayName = 'oer-s1241-pkg'; catalog = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check'; resourceRoles = @()
            assignmentPolicies = @([ordered]@{ displayName = 'oer-s1241-policy'; requestorScope = @{ scope = 'NotSpecified' }; durationInDays = 30 })
        })
    accessReviews  = @([ordered]@{ displayName = 'oer-s1241-review'; accessPackage = 'oer-s1241-pkg'; assignmentPolicy = 'oer-s1241-policy'; reviewers = @(); recurrence = 'OneTime'; durationInDays = 14 })
} | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $R.Section, $R.Item, $R.Action, $R.Detail) }
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S1241Count)"
# The ids this run created, for the teardown: from the rows and from the prefix sweep.
$Ids = @{}
foreach ($Hit in @(Find-OerLivePrefixed -Quiet | Where-Object { $_.Kind -ne 'unread' })) { $Ids["$($Hit.Kind)|$($Hit.Name)"] = @{ Kind = $Hit.Kind; Id = [string]$Hit.Id } }
$PkgRow = @($Rows | Where-Object { $_.Section -eq 'accessPackages' -and $_.Action -eq 'Created' -and $_.Detail -like 'created access package*' }) | Select-Object -First 1
if ($PkgRow -and $PkgRow.Detail -match '\(([0-9a-fA-F-]{36})\)') { $Ids['access package|oer-s1241-pkg'] = @{ Kind = 'access package'; Id = $Matches[1] } }
$null = New-Item -ItemType Directory -Force -Path $Raw
$Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Encoding utf8NoBOM
Write-OerLiveStep "Ids recorded: $(@($Ids.Keys | Sort-Object) -join ', ')"
$PkgId = [string]$Ids['access package|oer-s1241-pkg'].Id
$RevId = [string]$Ids['access review definition|oer-s1241-review'].Id
$Rev = if ($RevId) { Invoke-OerLiveRetry -Activity 'read the review' -ScriptBlock { Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions/$RevId`?`$select=id,displayName,scope" } }
$Query = if ($Rev -and $Rev.Ok) { [string]$Rev.Body.scope.query } else { '' }
Write-OerLiveStep "Read back: the review oer-s1241-review exists: $([bool]($Rev -and $Rev.Ok)); its scope names the created package: $([bool]($PkgId -and $Query.Contains($PkgId)))"
Disconnect-OerLive
```

**Expect:** rows `Created` for the catalog, the package (with its id), the policy and the review;
`$? True`; 0 error records; the ids recorded for the catalog, the package and the review; read back:
the review exists `True` and its scope names the created package `True`.
**Failure looks like:** the review `Failed` with a not-found record -- Microsoft Graph had not yet
replicated the new policy (run R1.2 again a minute later and record both runs here); the review
missing from the read back.

Result:

### R1.3. A second real run reports only Unchanged (G8)

- [ ] **R1.3** The same document again with `-Confirm:$false`: every row is `Unchanged`, `$?` is `True`, and no write request is made. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1241-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function global:Get-AzToken { throw 'S1241 fence: no token request is expected after the sign-in.' }
& $Module {
    $script:S1241Log = [System.Collections.Generic.List[string]]::new()
    $script:S1241Real = ${function:Invoke-OERGraphRequest}
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
        $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
        $script:S1241Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
        if (-not $Read) { throw "S1241 fence: a $Method request was refused; this run expects no write." }
        & $script:S1241Real @PSBoundParameters
    }
}
function Get-S1241Count { & (Get-Module -Name Omnicit.EntraRBAC) { '{0} read(s), {1} write(s)' -f @($script:S1241Log | Where-Object { $_ -eq 'read' }).Count, @($script:S1241Log | Where-Object { $_ -ne 'read' }).Count } }
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check' })
    accessPackages = @([ordered]@{
            displayName = 'oer-s1241-pkg'; catalog = 'oer-s1241-cat'; description = 'Sprint 12 step 4 round 1 live check'; resourceRoles = @()
            assignmentPolicies = @([ordered]@{ displayName = 'oer-s1241-policy'; requestorScope = @{ scope = 'NotSpecified' }; durationInDays = 30 })
        })
    accessReviews  = @([ordered]@{ displayName = 'oer-s1241-review'; accessPackage = 'oer-s1241-pkg'; assignmentPolicy = 'oer-s1241-policy'; reviewers = @(); recurrence = 'OneTime'; durationInDays = 14 })
} | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
foreach ($R in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $R.Section, $R.Item, $R.Action, $R.Detail) }
Write-OerLiveStep "Run 2: rows $(@($Rows).Count); every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S1241Count)"
Disconnect-OerLive
```

**Expect:** every row `Unchanged` (`every row Unchanged: True`); `$? True`; 0 error records; 0 writes.
**Failure looks like:** an `Updated` row or a fence refusal -- the run is not convergent.

Result:

### R1.T1. Remove every object with the round's prefix

- [ ] **R1.T1** The prerequisite script's teardown removes the review, the package (with its policy) and the catalog, and its sweep ends at 0. #type/subtask

```powershell
pwsh -NoProfile -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS1241Prereq.ps1') -Teardown -Unattended
```

**Expect:** `Teardown summary` with `Residue 0`; `Sweep: 0 object(s) with the prefix, 0 unread kind(s).`;
`Teardown complete: the sweep is 0.`
**Failure looks like:** residue or a sweep above 0 after five minutes -- run `-Teardown` again later
and record the residue here.

Result:

### R1.T2. The sweep is still 0 a minute later, and raw output is removed

- [ ] **R1.T2** A minute after R1.T1 the prefix sweep is still 0 and no session is left; `raw\s1241` is deleted after the results are copied here. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1241-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count) object(s) with the prefix; unread kinds: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "No module session is left: $($null -eq (& (Get-Module -Name Omnicit.EntraRBAC -ErrorAction SilentlyContinue) { $script:_OERAuthState } 2>$null))"
```

**Expect:** `Sweep: 0 object(s) with the prefix; unread kinds: 0`; no session left `True`. Then delete
`raw\s1241` (after every Result above is written).
**Failure looks like:** an object listed -- run R1.T1 again.

Result:
