# Live verification checklist -- an unread role map or inventory section is never empty (fix/unread-role-map-and-section-are-partial)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s82-`.** The
prerequisite script creates one plain security group, `oer-s82-grp`, and one administrative unit with
hidden membership, `oer-s82-au`, with the group as its only member. It assigns no directory role,
changes no policy and touches no object outside the prefix. Every other check only READS the tenant:
the exports read it, and the one apply in this file (2.2) is a `-Prune -WhatIf` plan, run behind a
read-only fence that refuses every Microsoft Graph request that is not a read (see Setup). Section 3
runs offline.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS82Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 1 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all, so that every read
of the export is refused; a 403 there is the expected answer, not a stop. Every sign-in is app-only;
nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`; read the plan against the `Expect:` line before running the line that
writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s82/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. The bundles hold real object ids: never copy any of them into a tracked file. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
failure's record can carry the bearer token. Every block prints the error id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A scoped role whose name could not be read is never added and removed under a name
  declaration** ("withhold an AU scoped role whose live name could not be read", BL-03, decision A8).
  `Get-OERAdministrativeUnit` names a live scoped role through the directory role list, which lists
  ACTIVATED roles only; a role id the list does not name gets an empty `RoleName`. When the document
  declares a role by name for the same principal and no live role matches it, the unnamed live role
  may be that very role. `Sync-OERStructureAdministrativeUnit` used to add the declared role and then,
  under `-Prune`, remove the unnamed one. It now does neither and reports one `Skipped` row that says
  the live role's name could not be read; declaring the role by its id reconciles it.
- **B. A section that could not be read at all is partial** ("report an inventory section or the
  group roster that could not be read as partial", BL-05, decision A9). A refused, throttled or failed
  read of the group list, the administrative unit list or the access review list used to produce only
  a warning: the section was written as `[]` and no `InventoryPartial` named it, so
  `Export-OERInventory` reported the bundle as complete. The section is still written as `[]` (a
  top-level section is never `null`), and is now named in `InventoryPartial` by its own name
  (`groups`, `administrativeUnits`, `accessReviews`); a group roster that could not be read is named
  `groupsRoster` in `IncompleteReads`.
- **C. No binding or name without a key** ("never write a binding or a name without a key, and refuse
  an empty name", BL-06, decision A10). The export never writes an empty `resource`, `role`, resource
  `name`, scoped role or principal: a group or application binding whose name cannot be read is
  written by its object id (which the apply engine accepts), and an entry with neither makes its
  collection an explicit `null`, named in `InventoryPartial`. `Test-OERStructure` reports an empty or
  blank value in those five fields as an Error, and `schema.json` carries `minLength: 1` for them.
- **D. The texts** ("correct the texts on unread sections, unnamed roles and empty names", "tighten the texts on the unnamed-role guard, empty names and partial reports"): the help,
  the bundle README, the LLM prompt and `docs/inventory-to-llm/README.md`.

A live tenant is needed for what mocks cannot show: what a real export does when every read is
refused (section 1, measured against the baseline below), that the success path is unchanged against
real Graph answers and the unchanged export applied with `-Prune` plans no removal of the test
objects (section 2).

**The baseline ("before").** The checklist of the unread-collection fix,
`fix-inventory-unread-collection-is-not-empty-checklist.md`, check 3.1 (2026-10-02, `oer-live-cc-noperm`,
the default `-Include`), recorded for the three sections this branch changes: the warnings `Could not
read groups`, `Could not read administrative units` and `Could not read access reviews`, and `Could
not read the group roster`, four in all; no `InventoryPartial` named `groups`, `administrativeUnits` or
`accessReviews`, and `IncompleteReads` did not name them either.

## What this file does not check, and why

- **A (the unnamed scoped role) cannot be provoked here.** The directory role list names every
  ACTIVATED role, and a scoped role can only hold an activated one, so a live tenant gives no unnamed
  role on demand. It is check class B of the sprint: proven by mocked, mutation-proven unit tests that
  run the REAL `Get-OERAdministrativeUnit` and `Get-OERDirectoryRoleNameMap` with only the transport
  answering, in `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1` (Context `a directory
  role name map that cannot be read is an unread scoped-role collection, never an undeclared role`),
  with the helper text in `tests/Unit/Private/ConvertTo-OERPruneWithheldResult.Tests.ps1`.
- **C (a binding with no name) cannot be provoked here either.** A catalog lists every resource it
  binds, and the names are read through the directory, so no live binding is left without a name on
  demand. Class B: `tests/Unit/Public/Get-OERInventory.Tests.ps1` holds the export cases and the
  export-to-apply round trip of an application binding with no name (Describe `an application binding
  with no readable name round-trips by its object id`); the validator and `schema.json` rule is proven
  in `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1` and
  `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1`, and offline here in 3.1.
- **No write path of the apply engine is exercised against the tenant.** A only withholds; the
  convergence check of this branch is 2.2, the unchanged export applied with `-Prune -WhatIf`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS82Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes a group and an administrative unit with
  the permissions it already holds (`Group.ReadWrite.All`, `AdministrativeUnit.ReadWrite.All`) and
  reads the directory and access reviews; this file adds none.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).

**The read-only fence.** 1.1, 2.1 and 2.2 replace the module's Graph transport, in the module's own
scope, with a thin wrapper that lets a GET through, and a POST only to
`v1.0/directoryObjects/getByIds` or `.../getMemberGroups` (two reads that Graph models as a POST),
and refuses everything else with an error naming the method and path. It counts what it saw.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'matches no live scoped role by name' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'could not be read at all and is written as an empty array' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'has no name, and no object id the apply engine accepts' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built; any `False` on the last line --
build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` (app-only certificate session with the identity's app id,
the app name `oer-live-cc`, the test tenant, the service principal of that app id named
`oer-live-cc` and the token's signed-in object; the organization name, a verified domain and the
organization id; the ARM token from the certificate; the test subscription belongs to the test
tenant and is Enabled), `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [ ] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`. It proves its
name through the session, since it can read nothing.
**Failure looks like:** any `False` -- STOP; section 1 needs this session.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s82-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s82\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s82-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s82-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s82-`
object; the plan names the transcript and the baseline under `raw\s82\` and, in the tenant, the group
`oer-s82-grp`, the administrative unit `oer-s82-au` and the membership `oer-s82-au: member
oer-s82-grp` -- three tenant targets, every one starting with `oer-s82-`; `WhatIf: nothing was
created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The test objects exist: the group, and the hidden administrative unit with the group as its member.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group oer-s82-grp`,
`Created administrative unit oer-s82-au` and the unit readable as `HiddenMembership`, the group added
as its member and listed; the summary with both `present`; exit code `0`. A `likely replication
delay` line on a fresh object is expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. The export, read as oer-live-cc-noperm

### 1.1. Every section refused: each one named as partial, written as `[]`

- [ ] **1.1** The no-permission export of groups, administrative units and access reviews names each of the three sections, and the group roster, as partial; the sections are written as `[]`, never `null`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-1.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count)"
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
$Partial = @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial errors: $($Partial.Count) [$((@($Partial | ForEach-Object { $_.FullyQualifiedErrorId })) -join '; ')]"
foreach ($P in $Partial) { Write-OerLiveStep "InventoryPartial ($($P.FullyQualifiedErrorId)) target: $($P.TargetObject)" }
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
foreach ($S in 'groups', 'administrativeUnits', 'accessReviews') {
    $V = $Doc.PSObject.Properties[$S].Value
    Write-OerLiveStep "inventory.json ${S}: present $($null -ne $Doc.PSObject.Properties[$S]); null $($null -eq $V); entries $(@($V | Where-Object { $null -ne $_ }).Count)"
}
$Roster = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
Write-OerLiveStep "groupsRoster.json entries: $(@($Roster | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
```

**Expect:** the fence saw only reads and refused `0`. Four warnings, as in the baseline: `Could not
read groups`, `Could not read administrative units`, `Could not read access reviews` (each a 403,
the expected answer for this identity) and `Could not read the group roster`. **New:**
`IncompleteReads` holds two entries, `groups, administrativeUnits, accessReviews` and `groupsRoster`;
two `InventoryPartial` errors, one from `Get-OERInventory` whose target is exactly
`groups, administrativeUnits, accessReviews` and whose message says such a section is written as an
empty array, and one from `Export-OERInventory`; each of the three sections present in
`inventory.json`, not `null`, with `0` entries; `groupsRoster.json` with `0` entries.
**Failure looks like:** an `IncompleteReads` without one of the three section names or without
`groupsRoster`, or no `InventoryPartial` -- the bundle still reads as complete (the defect of this
branch); a section `null` in `inventory.json` -- a top-level section must stay an array; `refused`
above 0.

Result:

### 2. The export and the apply, read as oer-live-cc

### 2.1. The same export: no partial, and the test objects in the bundle

- [ ] **2.1** The same export as 1.1 is complete (no `InventoryPartial`, no `IncompleteReads`), and the bundle carries `oer-s82-au` with its member and `oer-s82-grp` in the roster.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-2.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, access reviews {2}, roster {3}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.AccessReviews, $Bundle.RosterCount)
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count)"
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
$Partial = @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial errors: $($Partial.Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Au = @($Doc.administrativeUnits | Where-Object { $_.displayName -ceq 'oer-s82-au' })
Write-OerLiveStep "oer-s82-au entries: $($Au.Count); $(if ($Au.Count) { ConvertTo-Json -InputObject $Au[0] -Depth 10 -Compress })"
$GrpId = [string](Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s82-grp'"))).Body['value'][0]['id']
Write-OerLiveStep "oer-s82-au lists oer-s82-grp ($GrpId) as its member: $(if ($Au.Count) { @($Au[0].members) -contains $GrpId } else { $false })"
$Roster = @(Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json)
Write-OerLiveStep "groupsRoster.json entries named oer-s82-grp: $(@($Roster | Where-Object { $_.displayName -ceq 'oer-s82-grp' }).Count)"
$V = Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json') -WarningAction SilentlyContinue
Write-OerLiveStep "inventory.json validates: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
Disconnect-OerLive
```

**Expect:** the fence saw only reads and refused `0`; `IncompleteReads: 0 []` and `InventoryPartial
errors: 0`; the warnings, if any, are about access reviews that are not access-package-scoped (a
skipped review is not an unread one); `oer-s82-au entries: 1` with `"hiddenMembership":true`,
`"dynamic":false`, `"restricted":false`, `"members"` holding the group's id and `"scopedRoles":[]`;
`oer-s82-au lists oer-s82-grp ... as its member: True`; `groupsRoster.json entries named oer-s82-grp:
1`; `inventory.json validates: True`.
**Failure looks like:** an `InventoryPartial` or an `IncompleteReads` entry -- a read the identity can
do was reported as unread; `members` or `scopedRoles` `null` on `oer-s82-au` -- the hidden unit's
membership was not readable (record it, it is a finding, not a pass); `refused` above 0.

Result:

### 2.2. The unchanged export applied with -Prune -WhatIf: no removal planned for the test objects

- [ ] **2.2** An export with every security group in full detail, applied unchanged with `-Prune -WhatIf`, plans 0 removals for `oer-s82-` objects; the rows per section are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S82Seen = [System.Collections.Generic.List[string]]::new()
    $script:S82Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S82Transport) { $script:S82Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S82Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S82Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S82 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S82Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-2.2'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Groups, AdministrativeUnits, AccessReviews -AllGroupsDetailed -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue
Write-OerLiveStep ("Export: groups {0}, administrative units {1}, access reviews {2}; IncompleteReads {3}; InventoryPartial errors {4}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.AccessReviews, @($Bundle.IncompleteReads).Count, @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count)
$Path = Join-Path $Bundle.BundlePath 'inventory.json'
$Doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
Write-OerLiveStep "oer-s82-grp in inventory.json: $(@($Doc.groups | Where-Object { $_.displayName -ceq 'oer-s82-grp' }).Count); oer-s82-au: $(@($Doc.administrativeUnits | Where-Object { $_.displayName -ceq 'oer-s82-au' }).Count)"
$Rows = @(Invoke-OERStructure -Path $Path -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErr -WarningAction SilentlyContinue -WarningVariable ApplyWarn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S82Seen.Count; NotGet = @($script:S82Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S82Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
foreach ($G in @($Rows | Group-Object Section, Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name): $($G.Count)" }
$WouldRemove = @($Rows | Where-Object { [string]$_.Detail -like 'would remove*' })
$WouldRemoveOurs = @($WouldRemove | Where-Object { [string]$_.Item -like 'oer-s82-*' })
Write-OerLiveStep "Would-remove rows: $($WouldRemove.Count); for oer-s82- objects: $($WouldRemoveOurs.Count)"
foreach ($R in @($Rows | Where-Object { [string]$_.Item -like 'oer-s82-*' })) { Write-OerLiveStep "oer-s82 row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
Write-OerLiveStep "Would-remove warnings: $(@($ApplyWarn | Where-Object { "$_" -match 'would remove' }).Count)"
foreach ($E in @($ApplyErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Apply error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Disconnect-OerLive
```

**Expect:** the export with no partial and both test objects in `inventory.json` (`oer-s82-grp in
inventory.json: 1; oer-s82-au: 1`); the fence refused `0`; every `oer-s82-` row `Unchanged`
(the group's members and the unit's properties, member and scoped roles); `Would-remove rows` counted
and `for oer-s82- objects: 0`. The rows per section are recorded as they are; a would-remove row for
another object of the tenant is recorded with its count and is not a failure of this branch (this
branch changes no prune of the group or unit handlers; a planned removal there is a finding).
**Failure looks like:** a would-remove row for an `oer-s82-` object; an `oer-s82-` row other than
`Unchanged`; `refused` above 0.

Result:

### 3. The validator, offline

### 3.1. An empty name in each of the five fields: an Error each, and the apply refuses before it signs in

- [ ] **3.1** `Test-OERStructure` reports an Error for `""` in `scopedRoles[].role`, `scopedRoles[].principal`, `resources[].name`, `resourceRoles[].resource` and `resourceRoles[].role`, and `Invoke-OERStructure` refuses the document with `StructureValidationFailed` without calling `Initialize-OERAuth`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Disconnect-OerLive
$Built = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Built.FullName -Force
& (Get-Module Omnicit.EntraRBAC) { $script:S82AuthCalls = 0; function script:Initialize-OERAuth { $script:S82AuthCalls++; throw 'S82: no sign-in in 3.1' } }
$Doc = [ordered]@{
    version             = '1.0'
    administrativeUnits = @([ordered]@{ displayName = 'oer-s82-blank-au'; members = $null; scopedRoles = @([ordered]@{ role = ''; principal = '  ' }) })
    catalogs            = @([ordered]@{ displayName = 'oer-s82-blank-catalog'; resources = @([ordered]@{ type = 'Group'; name = '' }) })
    accessPackages      = @([ordered]@{ displayName = 'oer-s82-blank-ap'; catalog = 'oer-s82-blank-catalog'; resourceRoles = @([ordered]@{ resource = ''; role = ' ' }) })
}
$Json = ConvertTo-Json -InputObject $Doc -Depth 10
$V = Test-OERStructure -Json $Json -WarningAction SilentlyContinue
$Blank = @($V.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like '*must be a non-empty string*' })
foreach ($F in $Blank) { Write-OerLiveStep "Blank: $($F.Section) | $($F.Path) | $($F.Message)" }
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); blank-name Errors: $($Blank.Count)"
$Rows = @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
$Calls = & (Get-Module Omnicit.EntraRBAC) { $script:S82AuthCalls }
Write-OerLiveStep "Invoke-OERStructure rows: $($Rows.Count); errors: $((@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] }) -join ', '); Initialize-OERAuth calls: $Calls; a Graph session exists: $([bool](Get-MgContext))"
```

**Expect:** `Valid: False`; five blank-name Errors, at `administrativeUnits[0].scopedRoles[0].role`,
`administrativeUnits[0].scopedRoles[0].principal` (a blank `"  "` counts as empty),
`catalogs[0].resources[0].name`, `accessPackages[0].resourceRoles[0].resource` and
`accessPackages[0].resourceRoles[0].role`; `Invoke-OERStructure rows: 0; errors:
StructureValidationFailed; Initialize-OERAuth calls: 0; a Graph session exists: False`.
**Failure looks like:** fewer than five blank-name Errors -- the validator still takes `""` as a
declared name, and the apply would throw on it or match an unnamed live role; `Initialize-OERAuth
calls` above 0.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans only `oer-s82-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s82\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s82-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s82-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the plan deletes `oer-s82-au` and the group `oer-s82-grp` (through the library), every
tenant target starting with `oer-s82-`; `WhatIf: nothing was created, removed or written`; exit code
`0`.
**Failure looks like:** a tenant target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Every `oer-s82-` object is gone, and the counts match the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** `Teardown AU: deleted oer-s82-au`, the library deleting `oer-s82-grp`; the sweep finding
no `oer-s82-` object (a group deleted seconds earlier can still be listed by the `startswith`
listing for a few seconds -- T.3 reads again); `Counts: groups ... equal: True` and
`administrativeUnits ... equal: True`; exit code `0`.
**Failure looks like:** a `RESIDUE` line or exit code `3` -- record it in the report; exit code `1`.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Minutes later the sweep is clean, the counts match the baseline, the main clone is still on `main` at the HEAD S.1 recorded, and the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s82-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s82'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS82Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7)); exit code: $Code"
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts `equal:
True`; the main clone on `main` at the HEAD S.1 recorded; exit code `0`. After the results are
copied into this file: `Clear-OerLiveRedactionMap`, and `raw\s82\` deleted.
**Failure looks like:** a prefixed object left, or a residue row -- the teardown did not finish;
record it in the report.

Result:
