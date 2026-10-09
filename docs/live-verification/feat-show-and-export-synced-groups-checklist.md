# Live verification checklist -- synchronized groups are shown, exported on request and never written to (feat/show-and-export-synced-groups)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.**
A box with no result line filled in is not a passed check -- it is an unrun one. If a check turns
out to be impossible to run, write "cannot be verified, and therefore we do not know" on its result
line and say why; do not leave it blank and do not tick it. A check that could not run for a stated
reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B)**, and
**section C is Philip's, in an environment of his own, after the merge**: this run never executes it.

**What this file writes to the tenant.** One object, created by the prerequisite script
`Initialize-OerS107bPrereq.ps1` (beside OerLive, outside the repository): the cloud security group
`oer-s107b-cloud`, with no member and no owner. Check 3.2 changes its description through
`Invoke-OERStructure`; the teardown (T.1) deletes the group. Nothing else is created, changed or
removed. The bundles of section 2, the documents section 3 applies and the kept build of `666a4c7`
are written under `raw\s107b\`, which the teardown deletes.

**Who runs it.** Every section: the dedicated certificate identity `oer-live-cc`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only, with the certificate; nothing
here signs in as a person.

**What the tenant holds.** Measured before the code (part 1 of the step, read-only): the tenant lists
98 groups, every one of them carries the key `onPremisesSyncEnabled` in the default read (no
`$select`), and every value is `null`; the organization's own `onPremisesSyncEnabled` is `null`, so
the tenant has never been synchronized from on-premises. **There is no synchronized group to read,
export or apply to here: the synchronized form is class B (section B) and class C (section C), as
decision A15 foresees.** A cloud group shows every change of this branch that does not need one.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s107b/`,
which is git-ignored. Every block prints through the library's redactor, and the helpers print
counts and True/False only -- never a group's name other than the step's own prefixed one, and never
an id. Each block is run in its own process whose whole output (standard output and standard error)
is written to a file under `raw\s107b\`, redacted with OerLive's redactor and a mask for any GUID the
redactor did not number, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. `Get-OERGroup` shows `OnPremisesSyncEnabled`** ("feat: show whether a group is synchronized
  from on-premises"). `ConvertTo-OERGroup`, the single owner of the group shape, carries Graph's
  `onPremisesSyncEnabled` as it is: `True` for a synchronized group, `False` for one that no longer is,
  empty for one that never was. The table view has a column for it. Nothing is filtered out, and
  `Get-OERGroup` has no new switch. The private `Test-OERGroupOnPremisesSynced` is the single owner of
  "this live group is synchronized" (only a boolean `True`).
- **B. The roster flag and the document key** ("feat: mark synchronized groups in the roster and the
  exported document"). Every row of `groupsRoster.json` carries `onPremisesSynced` (true or false);
  `Get-OERInventory` writes `onPremisesSynced: true` for a synchronized group only, and nothing for a
  cloud group, so a cloud group's exported entry is exactly what earlier versions wrote. `schema.json`
  and `Test-OERStructure` accept the key as a boolean and refuse any other type.
- **C. `Export-OERInventory -IncludeSyncedGroups`** ("feat: keep synchronized security groups in the
  export on request"). Also keeps the synchronized security groups in full detail in
  `inventory.json`; without it the selection is as before.
- **D. The apply engine writes nothing to a synchronized group** ("feat: write nothing to a group
  synchronized from on-premises in apply runs"). Decided on the LIVE read, never on the document's
  key: every property, member, owner, eligibility or `pimPolicy` change is `Skipped` with one warning
  per group and no `ShouldProcess` call, and `-Prune` withholds every candidate. A cloud group is
  written to as before, whatever the document's `onPremisesSynced` says.

What a live tenant adds: the property on the real Graph answer (1.1, 1.2), the roster, the export with
and without the switch and the cloud entries unchanged against `666a4c7` (2.1 to 2.4), an exported
document that converges (3.1, G8), a cloud group written to although its document entry says
`onPremisesSynced: true`, with the key never sent (3.2, G8), and the validator's refusal (3.3).

## What this file does not check, and why

- **A synchronized group, in every part of the change (class B, then class C).** The tenant has none
  (above), and none can be made here: synchronization needs an on-premises directory. Proved offline
  (section B); section C is the run in an environment that has one.
- **G8 for a write path to a synchronized group.** The engine writes nothing to one, so there is no
  write to converge; its rows are `Skipped` on every run (section B).

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run.
- The **built module of this branch** in the step's own worktree (`./build.ps1 -Tasks build`), and
  the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it.
- The **build of `origin/main` at `666a4c7`** (the commit this branch starts from), copied to
  `raw\s107b\before-666a4c7\output\module\Omnicit.EntraRBAC\` before this branch's first build.
  Section 2.1 loads it; it uses the worktree's `output\RequiredModules`.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences and the
readers. Nothing here signs in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s107b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s107b'
$Before = Join-Path $Raw 'before-666a4c7'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$GroupName = 'oer-s107b-cloud'

function Start-S107bFence {
    # Get-AzToken forwards only a request that carries the certificate, so nothing can prompt. In the
    # module's own scope, Invoke-OERGraphRequest is wrapped once: each request's method is recorded, and
    # whether its body names onPremisesSynced (True/False) -- never the body, the path or a value.
    $global:S107bToken = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $global:S107bToken.Add(((@($PSBoundParameters.Keys) | Sort-Object) -join '','')); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S107b fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
    $global:S107bGraph = [System.Collections.Generic.List[object]]::new()
    & (Get-Module -Name Omnicit.EntraRBAC) {
        if (-not $script:S107bOriginalGraph) { $script:S107bOriginalGraph = (Get-Command -Name Invoke-OERGraphRequest -CommandType Function).ScriptBlock }
        $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-OERGraphRequest -CommandType Function))
        $Body = 'end { $M = if ($PSBoundParameters.ContainsKey(''Method'')) { [string]$PSBoundParameters[''Method''] } else { ''GET'' }; $K = $PSBoundParameters.ContainsKey(''Body'') -and ((ConvertTo-Json -InputObject $PSBoundParameters[''Body''] -Depth 20 -Compress) -match ''onPremisesSynced''); $global:S107bGraph.Add([PSCustomObject]@{ Method = $M.ToUpperInvariant(); BodyNamesKey = [bool]$K }); & $script:S107bOriginalGraph @PSBoundParameters }'
        $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
        Set-Item -Path function:script:Invoke-OERGraphRequest -Value ([scriptblock]::Create($Text))
    }
    $Seen = & (Get-Module -Name Omnicit.EntraRBAC) { '{0},{1}' -f (Get-Command Get-AzToken).CommandType, ([bool]((Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S107bGraph')) }
    Write-OerLiveStep "fences in place (Get-AzToken is the proxy, the Graph wrapper records): $($Seen -eq 'Function,True')"
}

function Reset-S107bRequests { $global:S107bToken.Clear(); $global:S107bGraph.Clear() }

function Write-S107bRequests {
    # The counts since the last reset: token requests, Graph requests by method, and how many bodies
    # named onPremisesSynced.
    if ($null -eq $global:S107bGraph) { Write-OerLiveStep 'requests: not fenced in this block'; return }
    $Writes = @($global:S107bGraph | Where-Object { $_.Method -ne 'GET' })
    Write-OerLiveStep ("requests: token {0}; Graph {1} (GET {2}; writes {3}: POST {4}, PATCH {5}, DELETE {6}); bodies naming onPremisesSynced: {7}" -f $global:S107bToken.Count, $global:S107bGraph.Count, @($global:S107bGraph | Where-Object Method -eq 'GET').Count, $Writes.Count, @($Writes | Where-Object Method -eq 'POST').Count, @($Writes | Where-Object Method -eq 'PATCH').Count, @($Writes | Where-Object Method -eq 'DELETE').Count, @($global:S107bGraph | Where-Object BodyNamesKey).Count)
}

function Write-S107bRows {
    # The engine's rows, as Section | Item | Action | Detail, for the step's own group only.
    param([object[]]$Rows)
    foreach ($R in @($Rows | Where-Object { $null -ne $_ })) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $R.Section, $R.Item, $R.Action, $R.Detail) }
    Write-OerLiveStep "rows: $(@($Rows | Where-Object { $null -ne $_ }).Count); not Unchanged: $(@($Rows | Where-Object { $null -ne $_ -and $_.Action -ne 'Unchanged' }).Count)"
}

function Write-S107bOwn {
    # A command's OWN records in an -ErrorVariable (the id ends in a comma and the command's name), as ids only.
    param([object[]]$Records, [string]$Command)
    $Own = @($Records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    Write-OerLiveStep ("{0} own errors: {1}{2}" -f $Command, $Own.Count, $(if ($Own.Count) { ' -- ' + (($Own | ForEach-Object { $_.FullyQualifiedErrorId }) -join '; ') } else { '' }))
}

function Write-S107bSyncWarnings {
    # How many warnings say a group is synchronized from on-premises.
    param([object[]]$Warnings)
    Write-OerLiveStep "warnings: $(@($Warnings).Count); saying a group is synchronized from on-premises: $(@($Warnings | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count)"
}

function Get-S107bSorted {
    # A JSON array file, sorted by displayName and serialized compactly, for an exact comparison.
    param([Parameter(Mandatory)][string]$Path)
    $Items = @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -NoEnumerate | ForEach-Object { $_ }) | Where-Object { $null -ne $_ }
    @($Items | Sort-Object -Property displayName | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 30 -Compress })
}
```

### S.1. The module loads from this branch's build, and the 666a4c7 build is kept

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched; the kept `666a4c7` build carries none of this branch's changes.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Marks = @('function Test-OERGroupOnPremisesSynced', '[switch]$IncludeSyncedGroups', "ParameterSetName = 'SyncedGroup'", 'onPremisesSynced = (Test-OERGroupOnPremisesSynced -Group $Rg)')
foreach ($Side in @(@('this branch', (Join-Path $Cfg.Repo 'output\module')), @('666a4c7', (Join-Path $Before 'output\module')))) {
    $Psm1 = Get-ChildItem -Path (Join-Path $Side[1] 'Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Psm1) { Write-OerLiveStep "$($Side[0]) build: not found"; continue }
    $Hits = @($Marks | Where-Object { Select-String -LiteralPath $Psm1.FullName -SimpleMatch $_ -Quiet }).Count
    $Ver = (Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1'))
    Write-OerLiveStep "$($Side[0]) build: version $($Ver.ModuleVersion) $($Ver.PrivateData.PSData.Prerelease); marks of this branch: $Hits of $($Marks.Count)"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `this branch build: ... marks of
this branch: 4 of 4`; `666a4c7 build: ... marks of this branch: 0 of 4`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), fewer than 4 marks in this
branch's build (build it first, never while the gate runs), or any mark in the `666a4c7` build.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. The prerequisite: the cloud group, after a plan

- [ ] **0.2** `Initialize-OerS107bPrereq.ps1 -WhatIf` writes nothing and plans the group; the real run writes the baseline (groups, onPremisesSyncEnabled true 0) and creates `oer-s107b-cloud`; a second run finds it and writes nothing.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS107bPrereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "prereq run: $($Run -join ' ')"
    & pwsh -NoProfile -NonInteractive -File $Script @Run 2>&1 | ForEach-Object { "$_" }
    Write-OerLiveStep "prereq exit code: $LASTEXITCODE"
}
```

**Expect:** the plan run ends `WhatIf: nothing was created, removed or written.` with exit code 0;
the first real run writes the baseline (`groups 98; onPremisesSyncEnabled true: 0` or the tenant's
count that day) and `Created group oer-s107b-cloud`, exit code 0; the second real run `Group
oer-s107b-cloud exists.`, `written to the tenant: False`, exit code 0.
**Failure looks like:** a refusal, an exit code other than 0, or a second run that writes.

Result:

## 1. The property and the table (A)

### 1.1. A cloud group: OnPremisesSyncEnabled is empty, and the table has the column

- [ ] **1.1** `Get-OERGroup -Group oer-s107b-cloud` returns one group whose `OnPremisesSyncEnabled` is present and empty; `Test-OERGroupOnPremisesSynced` answers False for it; the table shows the headers `DisplayName`, `GroupType`, `OnPremisesSyncEnabled`, `Id` in that order.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$G = @(Get-OERGroup -Group $GroupName -ErrorAction Stop)
Write-OerLiveStep "groups returned: $($G.Count); carries the property OnPremisesSyncEnabled: $(@($G[0].PSObject.Properties.Name) -contains 'OnPremisesSyncEnabled'); value is empty: $($null -eq $G[0].OnPremisesSyncEnabled)"
Write-OerLiveStep "Test-OERGroupOnPremisesSynced answers: $(& (Get-Module -Name Omnicit.EntraRBAC) { param($X) Test-OERGroupOnPremisesSynced -Group $X } $G[0])"
$Table = ($G | Format-Table | Out-String -Width 250) -split "`r?`n" | Where-Object { $_.Trim() }
$Header = @($Table[0] -split '\s+' | Where-Object { $_ })
Write-OerLiveStep "table headers: $($Header -join ', ')"
Write-OerLiveStep "table row names the group: $([bool]($Table | Where-Object { $_ -match [regex]::Escape($GroupName) }))"
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** `groups returned: 1; carries the property OnPremisesSyncEnabled: True; value is empty:
True`; `Test-OERGroupOnPremisesSynced answers: False`; `table headers: DisplayName, GroupType,
OnPremisesSyncEnabled, Id`; the row names the group; requests: Graph reads only, writes 0.
**Failure looks like:** the property missing, a value other than empty, another header order, or a
write.

Result:

### 1.2. Every group carries the property, and nothing is filtered out

- [ ] **1.2** `Get-OERGroup -All` returns every group of the tenant (the count of a raw `v1.0/groups` read), each with the property; none is True (the tenant has none); `Where-Object OnPremisesSyncEnabled` returns none.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$All = @(Get-OERGroup -All -ErrorAction Stop)
$RawList = Invoke-OerLiveGraph -All -Uri 'v1.0/groups?$select=id'
Write-OerLiveStep "Get-OERGroup -All: $($All.Count); raw v1.0/groups: $(@($RawList.Body['value']).Count); equal: $($All.Count -eq @($RawList.Body['value']).Count)"
Write-OerLiveStep "carry the property: $(@($All | Where-Object { @($_.PSObject.Properties.Name) -contains 'OnPremisesSyncEnabled' }).Count); True: $(@($All | Where-Object { $_.OnPremisesSyncEnabled -eq $true }).Count); False: $(@($All | Where-Object { $_.OnPremisesSyncEnabled -is [bool] -and -not $_.OnPremisesSyncEnabled }).Count); empty: $(@($All | Where-Object { $null -eq $_.OnPremisesSyncEnabled }).Count)"
Write-OerLiveStep "Where-Object OnPremisesSyncEnabled: $(@($All | Where-Object OnPremisesSyncEnabled).Count)"
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** the two counts equal; every group carries the property; `True: 0; False: 0; empty:` the
count; `Where-Object OnPremisesSyncEnabled: 0`; requests: reads only.
**Failure looks like:** the counts differ (something filtered), a group without the property, or a
True (a synchronized group appeared: then section C can run here too -- record it).

Result:

## 2. The roster and the export (B, C)

### 2.1. Export with the 666a4c7 build, every group in detail (the reference)

- [ ] **2.1** `Export-OERInventory -Include Groups -AllGroupsDetailed` with the kept `666a4c7` build writes a bundle under `raw\s107b\bundle-before\`; its roster rows carry no `onPremisesSynced`.

```powershell
$Mod = Get-ChildItem -Path (Join-Path $Before 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Select-Object -First 1
$Req = Join-Path $Cfg.Repo 'output\RequiredModules'
$env:PSModulePath = (Resolve-Path $Req).Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module -Name $Mod.FullName -Force -Global
Connect-OerLive -Arm
Write-OerLiveStep "module loaded from the kept build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith($Before, [System.StringComparison]::OrdinalIgnoreCase))"
Start-S107bFence
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-before') -Include Groups -AllGroupsDetailed -Force -ErrorAction Continue -ErrorVariable ExErr
$Roster = @(Get-Content -LiteralPath (Join-Path $Out.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
Write-OerLiveStep "bundle: groups $($Out.Groups); roster $($Out.RosterCount); IncompleteReads $(@($Out.IncompleteReads).Count)"
Write-OerLiveStep "roster rows carrying onPremisesSynced: $(@($Roster | Where-Object { @($_.PSObject.Properties.Name) -contains 'onPremisesSynced' }).Count)"
Copy-Item -LiteralPath $Out.BundlePath -Destination (Join-Path $Raw 'before') -Recurse -Force
Write-S107bOwn -Records $ExErr -Command 'Export-OERInventory'
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** the module loaded from the kept build; `IncompleteReads 0`; roster rows carrying
`onPremisesSynced: 0`; no own error; reads only.
**Failure looks like:** an `InventoryPartial` (record which read failed), or a write.

Result:

### 2.2. Export with this branch, as before (no switch): the roster flag, no key in the document

- [ ] **2.2** `Export-OERInventory -Include Groups` writes a roster whose every row carries `onPremisesSynced` (all False); no group in `inventory.json` carries the key; `Test-OERStructure` passes `inventory.json`.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-plain') -Include Groups -Force -ErrorAction Continue -ErrorVariable ExErr
$Roster = @(Get-Content -LiteralPath (Join-Path $Out.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
$Inv = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
Write-OerLiveStep "bundle: groups $($Out.Groups); roster $($Out.RosterCount); IncompleteReads $(@($Out.IncompleteReads).Count)"
Write-OerLiveStep "roster rows carrying onPremisesSynced as a boolean: $(@($Roster | Where-Object { $_.onPremisesSynced -is [bool] }).Count) of $($Roster.Count); True: $(@($Roster | Where-Object { $_.onPremisesSynced -eq $true }).Count)"
Write-OerLiveStep "roster row keys: $((@($Roster)[0].PSObject.Properties.Name) -join ', ')"
Write-OerLiveStep "inventory.json groups carrying onPremisesSynced: $(@($Inv.groups | Where-Object { @($_.PSObject.Properties.Name) -contains 'onPremisesSynced' }).Count)"
$V = Test-OERStructure -Path (Join-Path $Out.BundlePath 'inventory.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count); warnings naming onPremisesSynced $(@($V.Errors | Where-Object { $_.Severity -eq 'Warning' -and "$($_.Message)" -match 'onPremisesSynced' }).Count)"
Copy-Item -LiteralPath $Out.BundlePath -Destination (Join-Path $Raw 'plain') -Recurse -Force
Write-S107bOwn -Records $ExErr -Command 'Export-OERInventory'
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** `IncompleteReads 0`; every roster row carries the flag as a boolean, `True: 0`; the row
keys `displayName, roleAssignable, dynamic, onPremisesSynced, memberCount`; no group in
`inventory.json` carries the key; `Test-OERStructure: valid True; errors 0; warnings naming
onPremisesSynced 0`; reads only.
**Failure looks like:** a row without the flag, a key in the document for a cloud group, a
validation error, or a write.

Result:

### 2.3. Export with -IncludeSyncedGroups: the same groups, since the tenant has no synchronized one

- [ ] **2.3** `Export-OERInventory -Include Groups -IncludeSyncedGroups` keeps exactly the groups 2.2 kept (the tenant has no synchronized group), and its roster equals 2.2's row for row.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-synced') -Include Groups -IncludeSyncedGroups -Force -ErrorAction Continue -ErrorVariable ExErr
$Now = @(Get-S107bSorted -Path (Join-Path $Out.BundlePath 'groups.json'))
$Was = @(Get-S107bSorted -Path (Join-Path $Raw 'plain\groups.json'))
$RNow = @(Get-S107bSorted -Path (Join-Path $Out.BundlePath 'groupsRoster.json'))
$RWas = @(Get-S107bSorted -Path (Join-Path $Raw 'plain\groupsRoster.json'))
Write-OerLiveStep "bundle: groups $($Out.Groups); IncompleteReads $(@($Out.IncompleteReads).Count)"
Write-OerLiveStep "groups.json equals 2.2's entry for entry: $(($Now.Count -eq $Was.Count) -and -not (Compare-Object $Now $Was -SyncWindow 0)) ($($Now.Count) and $($Was.Count))"
Write-OerLiveStep "groupsRoster.json equals 2.2's row for row: $(($RNow.Count -eq $RWas.Count) -and -not (Compare-Object $RNow $RWas -SyncWindow 0))"
Write-S107bOwn -Records $ExErr -Command 'Export-OERInventory'
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** both comparisons `True`; `IncompleteReads 0`; reads only.
**Failure looks like:** a group added or missing (the switch kept something that is not a
synchronized group), or a write.

Result:

### 2.4. Every group in detail: each cloud entry is exactly what 666a4c7 exported

- [ ] **2.4** `Export-OERInventory -Include Groups -AllGroupsDetailed` with this branch writes a `groups.json` equal entry for entry to 2.1's; its roster is 2.1's with `onPremisesSynced` False added to each row.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-all') -Include Groups -AllGroupsDetailed -Force -ErrorAction Continue -ErrorVariable ExErr
$Now = @(Get-S107bSorted -Path (Join-Path $Out.BundlePath 'groups.json'))
$Was = @(Get-S107bSorted -Path (Join-Path $Raw 'before\groups.json'))
Write-OerLiveStep "groups.json equals 666a4c7's entry for entry: $(($Now.Count -eq $Was.Count) -and -not (Compare-Object $Now $Was -SyncWindow 0)) ($($Now.Count) and $($Was.Count))"
$RosterNow = @(Get-Content -LiteralPath (Join-Path $Out.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
$Stripped = @($RosterNow | ForEach-Object { $C = $_.PSObject.Copy(); $C.PSObject.Properties.Remove('onPremisesSynced'); $C } | Sort-Object displayName | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress })
$RWas = @(Get-S107bSorted -Path (Join-Path $Raw 'before\groupsRoster.json'))
Write-OerLiveStep "roster without the new flag equals 666a4c7's row for row: $(($Stripped.Count -eq $RWas.Count) -and -not (Compare-Object $Stripped $RWas -SyncWindow 0)); flag False on every row: $(@($RosterNow | Where-Object { $_.onPremisesSynced -is [bool] -and -not $_.onPremisesSynced }).Count -eq $RosterNow.Count)"
Write-OerLiveStep "the step's group is in groups.json: $([bool](@($Now) -match [regex]::Escape('"displayName":"' + $GroupName + '"')))"
Copy-Item -LiteralPath $Out.BundlePath -Destination (Join-Path $Raw 'all') -Recurse -Force
Write-S107bOwn -Records $ExErr -Command 'Export-OERInventory'
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** `groups.json equals 666a4c7's entry for entry: True`; the roster equal without the flag
and the flag False on every row; the step's group present; reads only.
**Failure looks like:** an entry that differs from what `666a4c7` exported (R4: a cloud group's entry
must stay exactly as before), or a write. A group created or changed by another process between 2.1
and 2.4 shows as a difference: re-run 2.1 and 2.4 back to back before calling it a failure.

Result:

## 3. The apply engine on a cloud group (D, G8)

### 3.1. The exported document of the step's group converges: Unchanged twice

- [ ] **3.1** The step's group entry from 2.4's `inventory.json` (with its `tenantId`) passes `Test-OERStructure`, and `Invoke-OERStructure -Include Groups` applied twice gives only `Unchanged`, with no write and no warning about a synchronized group.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Inv = Get-Content -LiteralPath (Join-Path $Raw 'all\inventory.json') -Raw | ConvertFrom-Json
$Doc = [PSCustomObject]@{ version = $Inv.version; tenantId = $Inv.tenantId; groups = @($Inv.groups | Where-Object { [string]$_.displayName -ceq $GroupName }) }
Write-OerLiveStep "document: groups $(@($Doc.groups).Count), every one with the prefix: $(@($Doc.groups | Where-Object { -not ([string]$_.displayName).StartsWith('oer-s107b-') }).Count -eq 0); carries tenantId: $([bool]$Doc.tenantId)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-3.1.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-3.1.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
foreach ($Pass in 1, 2) {
    Reset-S107bRequests
    $Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-3.1.json') -Include Groups -Confirm:$false -ErrorAction Continue -ErrorVariable ApErr -WarningVariable ApWarn -WarningAction SilentlyContinue)
    Write-OerLiveStep "run $($Pass):"
    Write-S107bRows -Rows $Rows
    Write-S107bSyncWarnings -Warnings $ApWarn
    Write-S107bOwn -Records $ApErr -Command 'Invoke-OERStructure'
    Write-S107bRequests
}
Disconnect-OerLive
```

**Expect:** one group, prefixed, with `tenantId`; valid; in both runs every row `Unchanged` (`group
properties match`, no member), `not Unchanged: 0`, no synchronized-group warning, no own error,
writes 0.
**Failure looks like:** any row other than `Unchanged`, or a write (G8).

Result:

### 3.2. The document says onPremisesSynced: true, the group is a cloud group: written to, and the key never sent

- [ ] **3.2** The 3.1 document with `onPremisesSynced: true` and a changed `description`: the plan (`-WhatIf`) says `would update group properties (Description)` with no write; the real run `Updated` with one PATCH whose body does not name `onPremisesSynced`; the second run `Unchanged` (G8); no warning about a synchronized group in any of the three.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-3.1.json') -Raw | ConvertFrom-Json
$Doc.groups[0] | Add-Member -NotePropertyName onPremisesSynced -NotePropertyValue $true -Force
$Doc.groups[0].description = 'Omnicit.EntraRBAC live verification (oer-s107b-): changed by check 3.2'
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-3.2.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-3.2.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count); warnings naming onPremisesSynced $(@($V.Errors | Where-Object { $_.Severity -eq 'Warning' -and "$($_.Message)" -match 'onPremisesSynced' }).Count)"
foreach ($Step in @(@('plan', $true), @('run 1', $false), @('run 2', $false))) {
    Reset-S107bRequests
    $Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-3.2.json') -Include Groups -WhatIf:$Step[1] -Confirm:$false -ErrorAction Continue -ErrorVariable ApErr -WarningVariable ApWarn -WarningAction SilentlyContinue)
    Write-OerLiveStep "$($Step[0]):"
    Write-S107bRows -Rows $Rows
    Write-S107bSyncWarnings -Warnings $ApWarn
    Write-S107bOwn -Records $ApErr -Command 'Invoke-OERStructure'
    Write-S107bRequests
}
$After = Get-OERGroup -Group $GroupName -ErrorAction Stop
Write-OerLiveStep "the description read back is the declared one: $($After.Description -ceq $Doc.groups[0].description); OnPremisesSyncEnabled still empty: $($null -eq $After.OnPremisesSyncEnabled)"
Disconnect-OerLive
```

**Expect:** valid, no warning naming `onPremisesSynced`; plan: `Skipped | would update group
properties (Description)`, writes 0; run 1: `Updated | updated group properties (Description)`,
writes 1 (PATCH 1), `bodies naming onPremisesSynced: 0`; run 2: every row `Unchanged`, writes 0; no
synchronized-group warning anywhere; the description read back equal.
**Failure looks like:** a `Skipped` in the real run (the engine decided on the document's key), a
body naming `onPremisesSynced`, or a second run that writes.

Result:

### 3.3. A key that is not a boolean is refused before anything is read or written

- [ ] **3.3** The 3.1 document with `onPremisesSynced: "yes"`: `Test-OERStructure` reports exactly one Error at `groups[0].onPremisesSynced`; `Invoke-OERStructure` refuses the document (`StructureValidationFailed`) with no Graph request.

```powershell
Connect-OerLive -Arm
Start-S107bFence
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-3.1.json') -Raw | ConvertFrom-Json
$Doc.groups[0] | Add-Member -NotePropertyName onPremisesSynced -NotePropertyValue 'yes' -Force
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-3.3.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-3.3.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count); at groups[0].onPremisesSynced: $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Path -eq 'groups[0].onPremisesSynced' }).Count); message: $(@($V.Errors | Where-Object Severity -eq 'Error')[0].Message)"
Reset-S107bRequests
$Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-3.3.json') -Include Groups -Confirm:$false -ErrorAction Continue -ErrorVariable ApErr)
Write-OerLiveStep "rows: $($Rows.Count)"
Write-S107bOwn -Records $ApErr -Command 'Invoke-OERStructure'
Write-S107bRequests
Disconnect-OerLive
```

**Expect:** `valid False; errors 1; at groups[0].onPremisesSynced: 1`, the message
`'onPremisesSynced' at groups[0] must be a boolean.`; rows 0; `Invoke-OERStructure own errors: 1 --
StructureValidationFailed,Invoke-OERStructure`; Graph requests 0.
**Failure looks like:** the document accepted, or any Graph request.

Result:

## B. Proved offline (class B)

The tenant has no synchronized group, so these are proved in the unit suite only:

- **`OnPremisesSyncEnabled` True, False and empty, and a value that is not a boolean**:
  `tests/Unit/Private/ConvertTo-OERGroup.Tests.ps1`, `tests/Unit/Public/Get-OERGroup.Tests.ps1`.
- **The single predicate, and that nothing else reads the property**:
  `tests/Unit/Private/Test-OERGroupOnPremisesSynced.Tests.ps1` (with its cohort check).
- **The roster flag True, and `onPremisesSynced: true` in the document for a synchronized group
  only**: `tests/Unit/Public/Export-OERInventory.Tests.ps1`, `tests/Unit/Public/Get-OERInventory.Tests.ps1`.
- **`-IncludeSyncedGroups` keeping a synchronized group, and with `-AllGroupsDetailed`**:
  `tests/Unit/Public/Export-OERInventory.Tests.ps1`.
- **Every write path to a synchronized group `Skipped`, with one warning and no write, also under
  `-Prune`, as plan and as run; the rename; a synchronized group `New-OERGroup` found; the live read
  deciding over the document key; a no-longer-synchronized group written to; the key never sent**:
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1`, Context `a group synchronized from
  on-premises (A15)`, and `tests/Unit/Private/ConvertTo-OERPruneWithheldResult.Tests.ps1`.

## C. For Philip, after the merge, in an environment of his own (class C; this run does not execute it)

Where at least one SECURITY group is synchronized from on-premises Active Directory. Install the
preview that carries this change, sign in your own way, and run the block; it reads, exports into a
temporary folder and runs `Invoke-OERStructure -WhatIf` only, and prints counts and True/False only,
so the result can be reported without a name or an id.

### C.1. A synchronized group is shown, exported on request, and planned as Skipped

- [ ] **C.1** `Get-OERGroup -All` shows at least one group with `OnPremisesSyncEnabled` True; the roster marks it; it is in `inventory.json` only with `-IncludeSyncedGroups`, carrying `onPremisesSynced: true`; a plan that changes its description and members, with `-Prune`, is all `Skipped` with one warning and nothing written.

```powershell
$TenantId = Read-Host 'Tenant id or domain'
Connect-OER -TenantId $TenantId
$Synced = @(Get-OERGroup -All | Where-Object OnPremisesSyncEnabled)
"groups synchronized from on-premises: $($Synced.Count); security-enabled among them: $(@($Synced | Where-Object SecurityEnabled).Count)"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) "oer-s107b-c1-$([guid]::NewGuid().ToString('N'))"
$Plain = Export-OERInventory -OutputPath $Tmp -Include Groups
$With = Export-OERInventory -OutputPath $Tmp -Include Groups -IncludeSyncedGroups
$Roster = @(Get-Content -LiteralPath (Join-Path $With.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
$InvPlain = Get-Content -LiteralPath (Join-Path $Plain.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$InvWith = Get-Content -LiteralPath (Join-Path $With.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
"roster rows marked onPremisesSynced: $(@($Roster | Where-Object onPremisesSynced).Count) (equals the synchronized groups: $(@($Roster | Where-Object onPremisesSynced).Count -eq $Synced.Count))"
"inventory.json without the switch, entries with onPremisesSynced: $(@($InvPlain.groups | Where-Object onPremisesSynced).Count)"
"inventory.json with -IncludeSyncedGroups, entries with onPremisesSynced: $(@($InvWith.groups | Where-Object onPremisesSynced).Count) (equals the synchronized security groups: $(@($InvWith.groups | Where-Object onPremisesSynced).Count -eq @($Synced | Where-Object SecurityEnabled).Count))"
$Entry = @($InvWith.groups | Where-Object onPremisesSynced)[0]
$Entry.description = 'changed by check C.1 (plan only)'
$Entry.members = @(@($Entry.members) | Select-Object -Skip 1)
$Doc = [PSCustomObject]@{ version = $InvWith.version; tenantId = $InvWith.tenantId; groups = @($Entry) }
$Rows = @(Invoke-OERStructure -InputObject $Doc -Include Groups -Prune -WhatIf -WarningVariable W -WarningAction SilentlyContinue)
"plan rows: $($Rows.Count); Skipped: $(@($Rows | Where-Object Action -eq 'Skipped').Count); Unchanged: $(@($Rows | Where-Object Action -eq 'Unchanged').Count); any other: $(@($Rows | Where-Object { $_.Action -notin 'Skipped', 'Unchanged', 'Extra' }).Count)"
"rows naming the synchronized group as the reason or as a withheld prune: $(@($Rows | Where-Object { $_.Detail -match 'synchronized from on-premises' }).Count)"
"warnings saying the group is synchronized from on-premises: $(@($W | Where-Object { "$_" -match 'is synchronized from on-premises' }).Count)"
Remove-Item -LiteralPath $Tmp -Recurse -Force
```

**Expect:** at least one synchronized security group; the roster marks exactly the synchronized
groups; no entry with `onPremisesSynced` without the switch, and exactly the synchronized security
groups with it; the plan: only `Skipped` and `Unchanged` rows (no `Updated`, `Removed` or `Failed`),
the description change and the removed member's withheld prune among the rows naming the reason,
and exactly one warning. Nothing is written (`-WhatIf`).
**Failure looks like:** a synchronized group the roster does not mark, an entry with the key without
the switch, a plan row other than `Skipped`/`Unchanged`/`Extra`, or no warning. Report the lines
above; do not paste names or ids.

Result:

## Teardown

### T.1. The group removed, nothing left, raw\s107b deleted

- [ ] **T.1** `Initialize-OerS107bPrereq.ps1 -Teardown -Unattended` removes `oer-s107b-cloud`; the sweep finds nothing with the prefix and no unread collection; the group counts equal the baseline; no module or Graph SDK session remains; `raw\s107b\` is deleted after the results are written.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS107bPrereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -Teardown -Unattended 2>&1 | ForEach-Object { "$_" }
Write-OerLiveStep "teardown exit code: $LASTEXITCODE"
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
$State = & (Get-Module -Name Omnicit.EntraRBAC) { $null -eq $script:_OERAuthState }
Write-OerLiveStep "module session cleared: $State; Graph SDK session left: $([bool](Get-MgContext))"
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s107b deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** the teardown removes the group (`Removed`), exit code 0, and the counts equal the
baseline; 0 objects, 0 unread collections; `module session cleared: True; Graph SDK session left:
False`; `raw\s107b deleted: True`.
**Failure looks like:** residue (exit code 3: a row in `raw\residue.json`), an object or an unread
collection left, a session left, or the folder still there.

Result:
