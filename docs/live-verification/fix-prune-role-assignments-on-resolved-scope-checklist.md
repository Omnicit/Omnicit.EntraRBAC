# Live verification checklist -- role assignments are pruned on the resolved scope, and duplicate entries are refused (fix/prune-role-assignments-on-resolved-scope)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s81-`.** The
prerequisite script creates the resource group `oer-s81-rg` in the test subscription, the two plain
security groups `oer-s81-grp1` and `oer-s81-grp2`, and one Azure role assignment: the built-in Reader
role for `oer-s81-grp1`, defined at `oer-s81-rg`. The checklist itself then writes through the module
at that resource group only (1.2): `Invoke-OERStructure` gives `oer-s81-grp2` the Reader role there.
**Nothing is ever written at the subscription scope.** The identity is Owner of the test subscription,
and the role assignment prune has no guard for its own assignment, so section 2 runs at the
subscription with `-WhatIf` and WITHOUT `-Prune`, behind a read-only fence that refuses every request
that is not a read. Sections 3 and 4 only read.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS81Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown run
first with `-WhatIf`; every apply that writes (1.2, 1.4) runs its own `-WhatIf` plan first, in the same
process, and writes only when that plan removes nothing and names only `oer-s81-` objects.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s81/` -- the
library writes its transcript and the baseline there, and the folder is git-ignored. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The test subscription's
display name is replaced by `Contoso Test Subscription` in the one block that reads it (2.2). The
library keeps one real-to-placeholder map per step, outside the clone and the operator's notes, and
deletes it after the write-up. **No credential, token, application id or certificate thumbprint is
ever printed.** **Never render an error record** (`Format-List` on `$Error[0]` or on an
`-ErrorVariable`): a raw failure's record can carry the bearer token. Every block prints the error
id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Role assignments are grouped on the scope the engine resolves** ("group role assignments on
  the resolved scope"). `Invoke-OERStructure` resolves every `roleAssignments` entry's scope once,
  before the first entry is dispatched, and groups the entries on that resolved scope, in a canonical
  form compared without regard to letter case and without a trailing `/`. `sub:` and
  `subscription:` with an id, `/subscriptions/` with that id, the subscription's name, `mg:` with a
  management group's name or display name and its path are one scope. Before, each spelling was its
  own group, and under `-Prune` each group's pass removed the other group's assignments, on every
  run; a path with a trailing `/` never pruned and drew a false "inherited" row. The handler now
  takes the resolved scope and never resolves it again.
- **B. A role definition matches on its GUID** ("match role assignments on the role definition
  GUID"). A live assignment at a resource group carries the role definition id anchored at the
  subscription, so a role given by its GUID (anchored by the module at the resource group) never
  matched, and `-Prune` removed and re-created the assignment on every run.
- **C. An unresolved scope withholds the whole section's prune** ("withhold the role assignment
  prune while a scope is unresolved"): it may be another spelling of any scope.
- **D. A second entry that resolves to the same assignment is `Failed` and not written** ("fail a
  role assignment entry that duplicates an earlier one"); its key still counts as declared.
- **E. The validator refuses duplicate top-level entries** in every section ("refuse duplicate
  entries in the structure validator").
- **F. The export never writes a duplicate** ("never export a duplicate entry"): objects that share
  a name are left out and named in `InventoryPartial`, and role assignment principals that share a
  name are written by object id.

A live tenant is needed for what mocks cannot show: how Azure Resource Manager really returns the
scope and the role definition id of an assignment at a resource group and at the subscription, and
that the engine's resolved scope and the role GUID meet them (sections 1 and 2), and that a real
tenant's export validates and applies without a planned removal (section 4).

## What this file does not check, and why

- **The `mg:` spellings.** `oer-live-cc` holds no management-group read (app-only, the listing is
  refused), so `mg:` and a management group path cannot be resolved here. They are proven by the
  mocked tests in `tests/Unit/Public/Invoke-OERStructure.Tests.ps1` (Describe
  `Invoke-OERStructure roleAssignments grouped on the resolved scope`) and the canonical form by
  `tests/Unit/Private/ConvertTo-OERCanonicalScope.Tests.ps1`.
- **A real prune at the subscription.** Never run: the identity's own Owner assignment is there.
  Section 2 shows, with `-WhatIf` and without `-Prune`, that the assignment is matched as declared and
  never reported as undeclared.
- **Two live objects with the same name in the export.** The tenant may hold none; section 4 records
  how many it holds, by count. The behaviour itself is proven by the mocked tests in
  `tests/Unit/Public/Get-OERInventory.Tests.ps1`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- with the test subscription, and the two
  configuration files OerLive reads beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS81Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same four lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. It creates and deletes
  groups and a resource group and writes role assignments at that resource group, with the
  permissions it already holds (Owner on the test subscription); this file adds none.
- The **built module of this branch** in the clone OerLive loads from (S.1 does it; T.3 puts the
  clone back on `main`).

**The fence.** The blocks marked read-only replace the module's two transports, in the module's own
scope, with thin wrappers that refuse every request that is not a read (a Microsoft Graph
`getByIds`/`getMemberGroups` post excepted, which only reads), with an error naming the method and
path.

### S.1. Point the clone at this branch and build it

- [ ] **S.1** The clone OerLive loads from holds this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Write-OerLiveStep "Tracked changes in the clone before the switch: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count); branch before the switch: $(git -C $Cfg.Repo branch --show-current)"
$null = git -C $Cfg.Repo fetch origin fix/prune-role-assignments-on-resolved-scope 2>&1
$null = git -C $Cfg.Repo switch --detach FETCH_HEAD 2>&1
Write-OerLiveStep "Clone at: $(git -C $Cfg.Repo log -1 --format='%h %s')"
Push-Location -LiteralPath $Cfg.Repo
try { ./build.ps1 -Tasks build *> (Join-Path $env:TEMP 'oer-s81-build.log'); $Code = $LASTEXITCODE } finally { Pop-Location }
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Resolve-OERStructureRoleAssignmentScope' -Quiet)
Write-OerLiveStep "Build exit code: $Code; the built module carries this branch's fix: $Fix"
```

**Expect:** `Tracked changes in the clone before the switch: 0` and the branch it was on (T.3 puts
it back); the clone at the branch head; `Build exit code: 0; the built module carries this branch's
fix: True`.
**Failure looks like:** tracked changes in the clone -- stop, the clone is someone's work; a build
exit code other than 0; `False` -- the clone did not get this branch, and every check below would
measure `main`.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the clone's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` (app-only certificate session with the identity's app id,
the app name `oer-live-cc`, the test tenant, the service principal of that app id named
`oer-live-cc` and the token's signed-in object; the organization name, a verified domain and the
organization id; the ARM token from the certificate; the test subscription belongs to the test
tenant and is Enabled), ending `identity check passed: True`, and `The module is the clone's build:
True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. The prerequisite script's plan

- [ ] **0.2** `-WhatIf` plans only `oer-s81-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s81\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s81-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s81-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s81-`
object; `oer-s81-rg exists: False`; the plan names the transcript and the baseline file under
`raw\s81\` and, in the tenant, four targets: the resource group `oer-s81-rg`, the groups
`oer-s81-grp1` and `oer-s81-grp2`, and `oer-s81-grp1 Reader at oer-s81-rg` -- every one starting
with `oer-s81-`; `WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.3. The prerequisite script, for real

- [ ] **0.3** The resource group, the two groups and the Reader assignment of `oer-s81-grp1` exist.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written before the first write (the tenant's group count and the number
of role assignments defined at the subscription); `Created resource group oer-s81-rg`, the two
groups created and resolving by display name, `Assigned Reader to oer-s81-grp1 at oer-s81-rg` and
the assignment listed there; the summary with all three `present`; exit code `0`.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.3 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. The resource group, written with -Prune (oer-s81- objects only)

Every document in this section names the resource group `oer-s81-rg` and the two `oer-s81-` groups,
and nothing else. The only role assignments DEFINED at that resource group are the two this file
makes; the identity's own Owner assignment is defined at the subscription, so the prune pass at the
resource group never sees it (it is inherited there, and skipped).

### 1.1. Two spellings of one scope: the plan

- [ ] **1.1** The resource group's path and the same path with a trailing `/` form one group: `-Prune -WhatIf` plans `oer-s81-grp1` `Unchanged`, `oer-s81-grp2` created, and no removal.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Doc = [ordered]@{ version = '1.0'; roleAssignments = @(
        [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
        [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) }
$Rows = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
$Remove = @($Rows | Where-Object { $_.Action -eq 'Removed' -or ($_.Action -eq 'Skipped' -and $_.Detail -like 'would remove*') })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); planned removals: $($Remove.Count); records: $(@($Err).Count)"
Disconnect-OerLive
```

**Expect:** two rows: `Reader -> oer-s81-grp1 @ .../oer-s81-rg | Unchanged | role assignment already
exists at '.../oer-s81-rg'` and `Reader -> oer-s81-grp2 @ .../oer-s81-rg/ | Skipped | would create
role assignment 'Reader' for 'oer-s81-grp2' at '.../oer-s81-rg'` -- the second at the path WITHOUT
the trailing `/`; `planned removals: 0`; no record, no warning.
**Failure looks like:** a planned removal; `oer-s81-grp1` reported `Skipped` as inherited, or
`Extra` -- the two spellings formed two groups (the defect this branch fixes); a would-create target
ending in `/`.

Result:

### 1.2. The same document, for real, after its own plan

- [ ] **1.2** `oer-s81-grp1` `Unchanged`, `oer-s81-grp2` `Created`, 0 `Removed`; the new assignment is defined at the resource group's path without a trailing `/`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Plan = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$PlanRemove = @($Plan | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
$PlanForeign = @($Plan | Where-Object { $_.Item -notmatch ' -> oer-s81-grp[12] @ ' })
$Ok = ($Plan.Count -eq 2) -and ($PlanRemove.Count -eq 0) -and ($PlanForeign.Count -eq 0)
Write-OerLiveStep "Plan: rows $($Plan.Count), planned removals $($PlanRemove.Count), rows not about an oer-s81- group $($PlanForeign.Count); writing: $Ok"
if ($Ok) {
    $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
    foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
    foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
    foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
    Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records: $(@($Err).Count)"
    $AtRg = Wait-OerLiveConverged -Activity 'two Reader assignments are defined at oer-s81-rg' -Read {
        $L = Invoke-OerLiveArm -All -Path "$RgScope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
        , @(@($L.Body.value) | Where-Object { $null -ne $_ -and ([string]$_.properties.scope).TrimEnd('/') -ieq $RgScope })
    } -Test { @($args[0]).Count -eq 2 }
    foreach ($A in @($AtRg.Value)) { Write-OerLiveStep "Defined at the resource group: principal $($A.properties.principalId), scope ends without '/': $(-not ([string]$A.properties.scope).EndsWith('/')), scope equals the path exactly: $([string]$A.properties.scope -ceq $RgScope)" }
}
Disconnect-OerLive
```

**Expect:** `Plan: rows 2, planned removals 0, rows not about an oer-s81- group 0; writing: True`;
then `oer-s81-grp1 | Unchanged` and `oer-s81-grp2 | Created | created role assignment 'Reader' for
'oer-s81-grp2' at '.../oer-s81-rg'`; no `Removed` row; 0 records; two assignments defined at the
resource group, each with `scope ends without '/': True`.
**Failure looks like:** `writing: False` -- read the plan, nothing was written; a `Removed` row; a
`Failed` row for `oer-s81-grp2` -- record its message (ARM's answer to the create).

Result:

### 1.3. The same document again: only Unchanged (G8)

- [ ] **1.3** A second run gives `Unchanged` for both entries and writes nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Plan = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$Ok = ($Plan.Count -eq 2) -and (@($Plan | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0)
Write-OerLiveStep "Plan: rows $($Plan.Count), all Unchanged: $Ok"
if ($Ok) {
    $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
    foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
    Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records: $(@($Err).Count); warnings: $(@($Warn).Count)"
}
Disconnect-OerLive
```

**Expect:** `Plan: rows 2, all Unchanged: True`; the real run's two rows `Unchanged`; 0 records, 0
warnings.
**Failure looks like:** anything but `Unchanged` -- the document does not converge.

Result:

### 1.4. The role as the Reader role's GUID: Unchanged, twice

- [ ] **1.4** With `oer-s81-grp1`'s role given as the Reader role's definition GUID, `-Prune` gives `Unchanged` and removes nothing, on two runs.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Filter = [uri]::EscapeDataString("roleName eq 'Reader'")
$Defs = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$Filter"
$ReaderGuid = [string](@($Defs.Body.value | Where-Object { $_.properties.roleType -eq 'BuiltInRole' })[0].name)
$Live = Invoke-OerLiveArm -All -Path "$RgScope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
foreach ($A in @($Live.Body.value | Where-Object { ([string]$_.properties.scope).TrimEnd('/') -ieq $RgScope })) {
    Write-OerLiveStep "Live at the resource group: role definition id anchored at the subscription, not the resource group: $(([string]$A.properties.roleDefinitionId).StartsWith("/subscriptions/$($Cfg.SubscriptionId)/providers/", [System.StringComparison]::OrdinalIgnoreCase)); its GUID is the Reader GUID: $(([string]$A.properties.roleDefinitionId).EndsWith("/$ReaderGuid", [System.StringComparison]::OrdinalIgnoreCase))"
}
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = $ReaderGuid; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Plan = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$Ok = ($Plan.Count -eq 2) -and (@($Plan | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0)
foreach ($R in $Plan) { Write-OerLiveStep "Plan row: $($R.Item) | $($R.Action) | $($R.Detail)" }
Write-OerLiveStep "Plan: rows $($Plan.Count), all Unchanged: $Ok"
if ($Ok) {
    foreach ($Run in 1, 2) {
        $Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
        Write-OerLiveStep "Run ${Run}: rows $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); records: $(@($Err).Count); warnings: $(@($Warn).Count)"
    }
}
Disconnect-OerLive
```

**Expect:** both live assignments with `anchored at the subscription, not the resource group: True`
and `its GUID is the Reader GUID: True` -- the shape that made a GUID never match before; the plan's
two rows `Unchanged` (the first naming the GUID, redacted to a placeholder); `Run 1` and `Run 2`:
rows 2, `Unchanged 2`, 0 records, 0 warnings.
**Failure looks like:** the GUID entry planned as `would create` with `oer-s81-grp1`'s live
assignment as a candidate -- the role key still compares the whole path (the defect this branch
fixes); `writing` skipped because the plan was not all `Unchanged`.

Result:

### 1.5. A scope that cannot be resolved withholds the prune: the plan

- [ ] **1.5** With an entry whose scope cannot be resolved, `-Prune -WhatIf` withholds the prune at the resource group: `oer-s81-grp2`'s assignment, now undeclared, is `Skipped` with `prune withheld`, not planned for removal.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = 'sub:oer-s81-no-such-subscription'; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' })) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Remove = @($Rows | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); planned removals: $($Remove.Count); warnings: $(@($Warn).Count)"
Disconnect-OerLive
```

**Expect:** three rows: `Reader -> oer-s81-grp2 @ sub:oer-s81-no-such-subscription | Failed | could
not resolve scope ...` (the subscription is not found), published once by `Invoke-OERStructure`;
`oer-s81-grp1 | Unchanged`; and `oer-s81-grp2`'s live assignment at the resource group `Skipped`
with a Detail starting `prune withheld: the scope of declared entry 'Reader -> oer-s81-grp2 @
sub:oer-s81-no-such-subscription' could not be resolved`; `planned removals: 0`; no warning.
**Failure looks like:** `would remove` for `oer-s81-grp2`'s assignment -- the withhold does not
reach a scope other than the unresolved entry's own.

Result:

### 1.6. A second entry for the same assignment: Failed, not written

- [ ] **1.6** An entry that resolves to the same scope, principal and role as an earlier one is `Failed` naming the earlier index, and the plan removes nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s81-rg"
$Filter = [uri]::EscapeDataString("roleName eq 'Reader'")
$Defs = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$Filter"
$ReaderGuid = [string](@($Defs.Body.value | Where-Object { $_.properties.roleType -eq 'BuiltInRole' })[0].name)
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = $RgScope; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }
            [ordered]@{ scope = "$RgScope/"; role = 'Reader'; principal = 'oer-s81-grp2'; principalType = 'Group' }
            [ordered]@{ scope = ($RgScope -replace '/resourceGroups/oer-s81-rg$', '/RESOURCEGROUPS/OER-S81-RG'); role = $ReaderGuid; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
foreach ($R in $Rows) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
$Remove = @($Rows | Where-Object { $_.Action -eq 'Removed' -or $_.Detail -like 'would remove*' })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); planned removals: $($Remove.Count); records: $(@($Err).Count); warnings: $(@($Warn).Count)"
Disconnect-OerLive
```

**Expect:** three rows: `oer-s81-grp1 | Unchanged`, `oer-s81-grp2 | Unchanged`, and the third entry
`Failed` with `roleAssignments[2] resolves to the same assignment as roleAssignments[0] ('Reader ->
oer-s81-grp1 @ ...')`; `planned removals: 0`; 0 records; no warning.
**Failure looks like:** the third entry `Unchanged` or `would update` -- the duplicate is applied;
any planned removal.

Result:

### 2. The subscription, -WhatIf without -Prune, behind the read-only fence

The identity's own Owner assignment is defined at the test subscription. These blocks never pass
`-Prune` and run behind the fence; nothing in this section can write.

### 2.1. `sub:` and `/subscriptions/`: the identity's Owner assignment is declared, never Extra

- [ ] **2.1** Entry A declares the identity's own Owner assignment as `sub:` with the subscription id; entry B declares Reader for `oer-s81-grp1` at `/subscriptions/` with the same id. A is `Unchanged`, B would be created, and the identity's Owner assignment is never reported `Extra`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
$SpId = ([string]$Sp.Body['id']).ToLowerInvariant()
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = "sub:$($Cfg.SubscriptionId)"; role = 'Owner'; principal = $SpId; principalType = 'ServicePrincipal' }
            [ordered]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($R in @($Rows | Where-Object { $_.Action -ne 'Extra' })) { Write-OerLiveStep "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
$OwnExtra = @($Rows | Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' -and $_.Item -like "* -> $SpId @ *" })
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); the identity's own assignment as a prune candidate: $($OwnExtra.Count); records: $(@($Err).Count); refused by the fence: $($Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Owner -> <the identity> @ sub:<the subscription id> | Unchanged | role assignment
already exists at '/subscriptions/...'` (both redacted); `Reader -> oer-s81-grp1 @ /subscriptions/...
| Skipped | would create ...`; the other assignments defined at the subscription reported `Extra`
(counted, not printed); `the identity's own assignment as a prune candidate: 0`; 0 records; `refused
by the fence: 0`.
**Failure looks like:** the identity's own assignment counted as a candidate -- the two spellings
formed two groups, so B's pass called A's assignment undeclared (on `main` it does); a refused
request -- a write was attempted under `-WhatIf`.

Result:

### 2.2. The subscription by name

- [ ] **2.2** The same check with entry A's scope as `sub:` and the subscription's display name, when `oer-live-cc` can resolve it; the name is redacted in every line.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$SubName = [string](Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)?api-version=2022-12-01").Body.displayName
function Out-S81 { param([string]$Text) Write-OerLiveStep $(if ($SubName) { $Text.Replace($SubName, 'Contoso Test Subscription') } else { $Text }) }
$Listed = @((Invoke-OerLiveArm -All -Path '/subscriptions?api-version=2022-12-01').Body.value | Where-Object { [string]$_.displayName -eq $SubName })
Out-S81 "The subscription's name was read: $([bool]$SubName); subscriptions listed under that name: $($Listed.Count)"
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
$SpId = ([string]$Sp.Body['id']).ToLowerInvariant()
$Json = ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ version = '1.0'; roleAssignments = @(
            [ordered]@{ scope = "sub:$SubName"; role = 'Owner'; principal = $SpId; principalType = 'ServicePrincipal' }
            [ordered]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s81-grp1'; principalType = 'Group' }) })
$Rows = @(Invoke-OERStructure -Json $Json -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($R in @($Rows | Where-Object { $_.Action -ne 'Extra' })) { Out-S81 "Row: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OERStructure' })) { Out-S81 "Published: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$OwnExtra = @($Rows | Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' -and $_.Item -like "* -> $SpId @ *" })
Out-S81 "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '); the identity's own assignment as a prune candidate: $($OwnExtra.Count); refused by the fence: $($Refused.Count)"
Disconnect-OerLive
```

**Expect:** `The subscription's name was read: True; subscriptions listed under that name: 1`; then
the rows of 2.1, with entry A's label reading `@ sub:Contoso Test Subscription`; `the identity's own
assignment as a prune candidate: 0`; `refused by the fence: 0`. If the name cannot be read, or two
subscriptions carry it (A is then `Failed` with `AmbiguousName`, and the section's prune would be
withheld), record it as it is: the check is then `[~]`.
**Failure looks like:** the real subscription name in any line -- redact before anything is copied;
the identity's own assignment counted as a candidate.

Result:

### 3. The validator, offline

### 3.1. One duplicate per section: an Error each, and the apply refuses before it signs in

- [ ] **3.1** `Test-OERStructure` reports one duplicate Error per section, nine in all, and `Invoke-OERStructure` refuses the document with `StructureValidationFailed` without calling `Initialize-OERAuth`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls = 0; function script:Initialize-OERAuth { $script:S81AuthCalls++; throw 'S81: no sign-in in 3.1' } }
$Sub = $Cfg.SubscriptionId
$Doc = [ordered]@{
    version                         = '1.0'
    groups                          = @([ordered]@{ displayName = 'oer-s81-dup-group'; members = $null }, [ordered]@{ displayName = 'OER-S81-DUP-GROUP'; members = $null })
    administrativeUnits             = @([ordered]@{ displayName = 'oer-s81-dup-au'; members = $null; scopedRoles = $null }, [ordered]@{ displayName = 'Oer-S81-Dup-Au'; members = $null; scopedRoles = $null })
    catalogs                        = @([ordered]@{ displayName = 'oer-s81-dup-catalog'; resources = $null }, [ordered]@{ displayName = 'OER-S81-DUP-CATALOG'; resources = $null })
    accessPackages                  = @([ordered]@{ displayName = 'oer-s81-dup-ap'; catalog = 'oer-s81-dup-catalog'; resourceRoles = $null }, [ordered]@{ displayName = 'OER-S81-DUP-AP'; catalog = 'OER-S81-DUP-CATALOG'; resourceRoles = $null })
    accessReviews                   = @([ordered]@{ displayName = 'oer-s81-dup-review'; accessPackage = 'oer-s81-dup-ap'; assignmentPolicy = 'oer-s81-policy'; reviewers = @() }, [ordered]@{ displayName = 'OER-S81-DUP-REVIEW'; accessPackage = 'oer-s81-dup-ap'; assignmentPolicy = 'oer-s81-policy'; reviewers = @() })
    roleAssignments                 = @([ordered]@{ scope = "sub:$Sub"; role = 'Reader'; principal = 'oer-s81-grp1' }, [ordered]@{ scope = "/subscriptions/$Sub/"; role = 'READER'; principal = 'OER-S81-GRP1' })
    roleManagementPolicies          = @([ordered]@{ scope = "subscription:$Sub"; role = 'Reader' }, [ordered]@{ scope = "/SUBSCRIPTIONS/$Sub"; role = 'reader' })
    directoryRoleManagementPolicies = @([ordered]@{ role = 'Reports Reader' }, [ordered]@{ role = 'reports reader' })
    directoryRoleAssignments        = @([ordered]@{ role = 'Reports Reader'; principal = 'oer-s81-grp1'; assignmentType = 'Eligible' }, [ordered]@{ role = 'REPORTS READER'; principal = 'oer-s81-grp1'; assignmentType = 'Eligible' })
}
$Json = ConvertTo-Json -InputObject $Doc -Depth 10
$V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
$Dup = @($V.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like '*declares the same*' })
foreach ($F in $Dup) { Write-OerLiveStep "Duplicate: $($F.Section) | $($F.Path) | $($F.Message)" }
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); duplicate Errors: $($Dup.Count); sections: $((@($Dup.Section) | Sort-Object -Unique) -join ', ')"
$Rows = @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S81AuthCalls }
Write-OerLiveStep "Invoke-OERStructure rows: $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', '); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** `Valid: False`; nine duplicate Errors, one per section, each at the LATER entry's path
(`groups[1]`, `administrativeUnits[1]`, ..., `directoryRoleAssignments[1]`) and naming `...[0]`; the
roleAssignments and roleManagementPolicies ones although the two entries spell the scope differently
(`sub:`/`subscription:` with the id against the path with a trailing `/` or in upper case);
`Invoke-OERStructure rows: 0; errors: StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph
session exists: False`.
**Failure looks like:** fewer than nine duplicate Errors, or one at the earlier entry's path; a
`roleAssignments` or `roleManagementPolicies` pair not reported -- the canonical scope is not used;
`Initialize-OERAuth calls` above 0.

Result:

### 4. The whole tenant's export, read as oer-live-cc

### 4.1. The export, behind the read-only fence

- [ ] **4.1** The export of the whole tenant is written, its rows per section are recorded, and names that two live objects share are counted, never named.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Seen = 0
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $script:S81Seen++
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        $script:S81Seen++
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-4.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S81Seen; Refused = @($script:S81Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), refused $($Fence.Refused.Count)"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, catalogs {2}, access packages {3}, access reviews {4}, directory role policies {5}, directory role assignments {6}, role assignments {7}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.Catalogs, $Bundle.AccessPackages, $Bundle.AccessReviews, $Bundle.DirectoryRoleManagementPolicies, $Bundle.DirectoryRoleAssignments, $Bundle.RoleAssignments)
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Reads = @($Bundle.IncompleteReads)
$Named = @($Reads | Where-Object { ($_ -match '^(groups|administrativeUnits|catalogs|accessReviews)/[^/]+$') -or (($_ -match '^accessPackages/[^/]+/[^/]+$') -and ($_ -notmatch '/(packages|catalogResourceNames|resourceRoles|assignmentPolicies)$')) })
$Collisions = @(foreach ($Sec in 'groups', 'administrativeUnits', 'catalogs', 'accessReviews') {
        $Names = @($Doc.$Sec | ForEach-Object { [string]$_.displayName })
        [PSCustomObject]@{ Section = $Sec; NamedInPartial = @($Named | Where-Object { $_ -like "$Sec/*" }).Count; WrittenAnyway = @($Named | Where-Object { $_ -like "$Sec/*" } | Where-Object { $Names -contains ($_ -replace '^[^/]+/', '') }).Count }
    })
foreach ($C in $Collisions) { Write-OerLiveStep "Shared names, $($C.Section): named in the partial $($C.NamedInPartial); written to the document anyway $($C.WrittenAnyway)" }
Write-OerLiveStep "Shared names, accessPackages (one catalog): named in the partial $(@($Named | Where-Object { $_ -like 'accessPackages/*' }).Count)"
$ById = @($Doc.roleAssignments | Where-Object { [string]$_.principal -match '^[0-9a-fA-F-]{36}$' -and [string]$_.principalType -in 'User', 'Group' })
Write-OerLiveStep "Role assignment entries written by object id because their principal's name is shared: $($ById.Count)"
Write-OerLiveStep "IncompleteReads: $($Reads.Count); SkippedScopes: $(@($Bundle.SkippedScopes).Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })) { Write-OerLiveStep "Partial: $($E.FullyQualifiedErrorId) -- causes clause shares-a-name: $($E.Exception.Message -like '*share the name*')" }
Disconnect-OerLive
```

**Expect:** `refused 0`; the summary counts recorded; for every section `written to the document
anyway 0`; the counts of shared names recorded as they are (the tenant may hold none); `IncompleteReads`
and `SkippedScopes` recorded (`oer-live-cc` holds no management-group read, so the Azure walk is
expected to skip that level, as in Sprint 7 step 1).
**Failure looks like:** a refused request -- a read path tried to write; a shared name written to the
document anyway.

Result:

### 4.2. The export validates

- [ ] **4.2** `Test-OERStructure` reports the export valid, and the bundle's own `schema.json` accepts it.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-4.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Json = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw
$Valid = Test-OERStructure -Path (Join-Path $BundlePath 'inventory.json') -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
$Dup = @($Valid.Errors | Where-Object { $_.Message -like '*declares the same*' })
Write-OerLiveStep "Test-OERStructure: Valid $($Valid.Valid); Errors $(@($Valid.Errors | Where-Object Severity -eq 'Error').Count); duplicate Errors $($Dup.Count); Warnings $(@($Valid.Errors | Where-Object Severity -eq 'Warning').Count)"
$Schema = Get-Content -LiteralPath (Join-Path $BundlePath 'schema.json') -Raw
Write-OerLiveStep "Test-Json against the bundle's schema.json: $(Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue)"
Disconnect-OerLive
```

**Expect:** `Valid True; Errors 0; duplicate Errors 0`; the warnings counted; `Test-Json ... True`.
**Failure looks like:** `Valid False` -- record every Error's section and path (not its names): an
Error the export writes is a defect of this branch.

Result:

### 4.3. The export's role assignments applied with -WhatIf: no undeclared candidate

- [ ] **4.3** Applying the export's `roleAssignments` with `-WhatIf`, WITHOUT `-Prune` (the subscription is in it), reports 0 `Extra` rows -- the candidates `-Prune` would remove -- and the test objects `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S81Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S81Graph) { $script:S81Graph = ${function:Invoke-OERGraphRequest} }
    if (-not $script:S81Arm) { $script:S81Arm = ${function:Invoke-OERArmRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S81Refused.Add("$Method $Path"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Graph @PSBoundParameters
    }
    function script:Invoke-OERArmRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All)
        if ($Method -ne 'GET') { $script:S81Refused.Add("$Method $($Path -replace '\?.*$', '')"); throw "S81 read-only fence: refused $Method $Path" }
        & $script:S81Arm @PSBoundParameters
    }
}
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-4.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Doc = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Doc43 = [ordered]@{ version = $Doc.version; roleAssignments = @($Doc.roleAssignments) }
$Path43 = Join-Path $Raw 'apply-4.3.json'
[System.IO.File]::WriteAllText($Path43, (ConvertTo-Json -InputObject $Doc43 -Depth 30), [System.Text.UTF8Encoding]::new($false))
$Rows = @(Invoke-OERStructure -Path $Path43 -Include RoleAssignments -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApErr -WarningAction SilentlyContinue -WarningVariable ApWarn)
$Refused = & (Get-Module Omnicit.EntraRBAC) { @($script:S81Refused) }
foreach ($G in @($Rows | Group-Object Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name) = $($G.Count)" }
foreach ($R in @($Rows | Where-Object { $_.Item -match 'oer-s81-' })) { Write-OerLiveStep "Test object: $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($R in @($Rows | Where-Object { $_.Action -notin 'Unchanged' -and $_.Item -notmatch 'oer-s81-' })) { Write-OerLiveStep "Other row: $($R.Action) | $($R.Detail)" }
Write-OerLiveStep "Document: role assignments $(@($Doc43.roleAssignments).Count); Extra rows: $(@($Rows | Where-Object Action -eq 'Extra').Count); refused by the fence: $($Refused.Count); records: $(@($ApErr).Count)"
Disconnect-OerLive
```

**Expect:** `Extra rows: 0`; the two `oer-s81-` rows `Unchanged`; every other row recorded as it is
(a `Skipped` row starting `prune withheld:` for an entry whose principal no longer resolves is the
guard working, not a planned removal); `refused by the fence: 0`.
**Failure looks like:** an `Extra` row -- an assignment the export wrote is not matched by its own
entry, so `-Prune` would remove it: record its section and detail.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans the removal of the two role assignments at `oer-s81-rg`, the two groups and the resource group, and nothing else.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s81\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s81-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s81-') }).Count -eq 0); exit code: $Code"
```

**Expect:** five tenant targets, each starting with `oer-s81-`: the role assignments of
`oer-s81-grp1` and `oer-s81-grp2` at `oer-s81-rg`, the two groups and `oer-s81-rg`; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Everything with the prefix is gone, and the counts equal the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** both role assignments removed, both groups deleted, `oer-s81-rg` deleted and gone; the
sweep finds nothing; `Resource group oer-s81-rg exists after the teardown: False`; both counts
`equal: True`; exit code `0`.
**Failure looks like:** exit code 3 -- residue: record each RESIDUE line, it stays prefixed and the
next run retries it; a count that differs from the baseline -- record it.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** A later read-back finds nothing, the clone is back on the branch it was on, and the raw folder and the redaction map are deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s81-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s81'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS81Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
Write-OerLiveRaw -InputObject ($Out -join "`n")
$null = git -C $Cfg.Repo switch main 2>&1
Write-OerLiveStep "Clone branch after the switch back: $(git -C $Cfg.Repo branch --show-current); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
```

**Expect:** `prefixed objects left: 0; unread collections: 0`; `Resource group oer-s81-rg exists:
False`; both counts equal; the clone on `main` with 0 tracked changes. After the results are copied
into the repository checklist: delete `raw\s81\` and run `Clear-OerLiveRedactionMap`.
**Failure looks like:** a prefixed object left -- run T.2 again.

Result:
