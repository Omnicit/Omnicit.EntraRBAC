# Live verification checklist -- a successful row means it succeeded (fix/failed-request-is-an-error)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates two role-assignable security
groups with no member, `oer-s95-grp` and `oer-s95-grp2`, one empty resource group, `oer-s95-rg`, in the
test subscription, and a catalog `oer-s95-cat` holding a hidden access package `oer-s95-ap` with one
administrator-only assignment policy `oer-s95-pol`. It records two baselines before the first write:
the tenant's group, catalog and access package counts together with the direct holders of the two
low-risk directory roles, and the Reader role's policy at `oer-s95-rg`. Section 1 gives
`oer-s95-grp` a time-bound eligible and active assignment of one low-risk directory role and removes
them; section 2 does the same through `Invoke-OERStructure`, and removes them with `-Prune` while
`oer-s95-grp2` receives the role; section 3 gives `oer-s95-grp` the Reader role at `oer-s95-rg`,
eligible and active, and removes it; section 4 gives it a PERMANENT active Reader assignment there,
which opens the Reader policy at `oer-s95-rg` for permanent active assignments; section 5 sends a
refused update and one description change to `oer-s95-pol`. The teardown removes the Azure schedules
at `oer-s95-rg`, every prefixed object through OerLive's fixed order, puts the Reader policy at
`oer-s95-rg` back to its baseline and deletes the resource group. No role policy outside `oer-s95-rg`
is written, and no directory role policy at all.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop. Neither `oer-live-cc` nor `oer-live-cc-noperm` is ever a principal here: every
assignment names a prefixed group.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive -Arm`, which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s95/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed**, and **no error record is ever rendered**: every
block prints the error id, its category and the message (redacted, cut at 300 characters) only. A
`-WhatIf` line goes straight to the host and cannot be redirected inside one process, so every block
that runs a module cmdlet with `-WhatIf` (2.3 and 4.2) runs it in a CHILD process and prints the
child's whole output through the redactor.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-33: a schedule request answered with a Failed status is an error** ("report a failed
  schedule request as an error"). Eleven cmdlets emitted whatever status Microsoft Graph or Azure
  Resource Manager answered, so a request accepted but answered `Failed` read as a success, and the
  apply engine reported such a row `Created`, `Updated` or `Removed`. They now emit the request object
  and then write `EligibilityRequestFailed` (the eligibility variants) or the new
  `AssignmentRequestFailed` (the active variants, and `Enable-`/`Disable-OEREligibleRoleAssignment`)
  for `Failed` and every status starting with `Failed`, in any letter case. One private owner,
  `Test-OERScheduleRequestFailed`, decides it for all twelve cmdlets (`Add-OERGroupEligibility`
  included) and the engine's two new-group waits. `Revoked` is a removal's success.
- **B. BL-50: `Set-OERAccessPackageAssignmentPolicy` refuses a connected-organization scope with no
  target.** A `-RequestorScope` of `SpecificConnectedOrganizationUsers` with no target -- the only one
  `New-OERAccessPackageRequestorScope` can build -- would have replaced every connected organization
  the live policy names with an empty list. It is now refused with `InvalidPolicyInput` after the
  policy is read and before the confirmation gate, and nothing is sent.
- **C. BL-80: `New-OERActiveRoleAssignment` opens the role policy only after consent.** A permanent
  active assignment that needs the Azure role policy opened used to open it before the confirmation
  gate, so a declined prompt still weakened the policy. It now does what
  `New-OEREligibleRoleAssignment` does: the read and its warning before the gate, the open only once
  the assignment is confirmed (`-WhatIf` still plans it), a rollback when the assignment fails or is
  answered `Failed`, and `PolicyOpenedButGrantFailed` when a thrown grant follows an open.

A live tenant is needed for what the unit tests stub: that the REAL answers of a successful request
-- `Provisioned` for a grant, `Revoked` for a removal -- are not taken for a failure by the new rule,
on Microsoft Graph's directory role endpoints and on Azure Resource Manager (sections 1 and 3); that
the apply engine still reports `Created`, `Unchanged` and `Removed` (section 2, G8); the real order of
the policy open and the grant, and that `-WhatIf` writes nothing (section 4); and the refusal counted
by fences around the module's real transports (section 5).

## What this file does not check, and why

- **A Failed answer (class B, G9).** No request can be made to fail on demand: Graph answers
  `Failed` only in a replication window (measured live in Sprint 7 step 3, run 0: two 404s, then a 201
  whose status was already `Failed`, for PIM for Groups). Proved offline with the REAL cmdlets and only
  the transport answering, in each cmdlet's test file (the Context for a Failed answer), in
  `tests/Unit/Private/Test-OERScheduleRequestFailed.Tests.ps1` (the rule, and the check that no other
  file compares a status to a `'Failed'` literal), in
  `tests/Unit/Private/Sync-OERStructureDirectoryRoleAssignment.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (the engine's three paths), with that live
  answer's shape as the fixture, and in a script with no `try`.
- **A declined confirmation gate (class B, G9).** Declining needs a person at a prompt. Proved
  offline in the answering runspace of `tests/Unit/TestHelpers/OERConfirmHost.ps1`: the decline tests
  of `tests/Unit/Public/New-OERActiveRoleAssignment.Tests.ps1`, with the `Yes` control, and the AST
  check that every policy write sits under the gate's decision.
- **`Enable-OEREligibleRoleAssignment` and `Disable-OEREligibleRoleAssignment` (class B, G9).** They
  send a SelfActivate / SelfDeactivate request for the signed-in identity's own eligibility, and this
  file never makes `oer-live-cc` a principal (G6). Proved offline in their test files.
- **The rollback after a refused or Failed grant (class B).** It needs Azure to refuse or fail a grant
  after the open. Proved offline in `tests/Unit/Public/New-OERActiveRoleAssignment.Tests.ps1` and, for
  the eligible cmdlet, `tests/Unit/Public/New-OEREligibleRoleAssignment.Tests.ps1`.
- **`Remove-OERGroupEligibility` live.** It shares the rule and the converter with
  `Add-OERGroupEligibility`, whose live answers earlier steps recorded; its Failed path and the engine's
  prune of it are class B above.
- **Convergence (G8)** applies to section 2, the apply engine's write path: 2.2 and 2.5 run each
  document again. Sections 1, 3 and 4 call cmdlets, and a create sent twice is a second request, not a
  convergence check.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **prerequisite script** `Initialize-OerS95Prereq.ps1` beside OerLive (outside the repository).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.1 read that it was not).

**Run every numbered block in its OWN PowerShell process**, except where a section says that its
checks share one.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Test-OERScheduleRequestFailed' -Quiet)
$A2 = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch "-ErrorId 'AssignmentRequestFailed'").Count
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'New-OERAccessPackageRequestorScope cannot name one' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$Proceed = $PSCmdlet.ShouldProcess($Target, ''Create active Azure role assignment'')' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A (AssignmentRequestFailed sites: $A2); B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True (AssignmentRequestFailed sites: 6); B: True;
C: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; `False`, or a lower count, on the last line -- build the worktree first
(`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result:

### 0.2. The prerequisite plan names only oer-s95- objects

- [ ] **0.2** `Initialize-OerS95Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every tenant `What if:` target starts with `oer-s95-`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baseline) go to raw\s95\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s95\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s95\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s95\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s95-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s95-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own local files under `raw\s95\` (the transcript and, on a first run, the count baseline);
the direct holders of Reports Reader and Message Center Reader, and the role the checklist will use;
and the tenant targets `oer-s95-grp`, `oer-s95-grp2`, `oer-s95-rg`, `oer-s95-cat`, `oer-s95-ap` and
`oer-s95-ap: oer-s95-pol` (none that exists already), every tenant target starting with `oer-s95-`
(`True`); a "No Reader-policy baseline" line, since under `-WhatIf` the resource group does not exist
yet.
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run.

Result:

### 0.3. The prerequisite objects and the baselines

- [ ] **0.3** `Initialize-OerS95Prereq.ps1 -Unattended` writes the baseline when there is none (with the directory role the checklist uses), creates the two groups, the resource group, the catalog, the package and its policy, and records the Reader-policy baseline at the resource group.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the identity lines `True`; the baseline written before the first write, naming the
directory role the checklist uses (one of the two with no direct holder) or saying none is free;
`Created group oer-s95-grp (role-assignable)`, the same for `oer-s95-grp2`, `Created resource group
oer-s95-rg`, the catalog, the hidden package and the administrator-only policy; `Reader policy at
oer-s95-rg: rules N; permanent active assignment allowed: False` and the baseline written; exit code
0.
**Failure looks like:** a 403 on creating a role-assignable group, the catalog, the package or the
policy -- STOP: a missing permission on the app path (G6); exit code 1 with `Refusing to run` -- read
the reason.

Result:

## 1. BL-33: the directory role cmdlets on a real Provisioned and Revoked answer

**1.0 to 1.4 run in ONE process**, in order. The fences count every Graph and Azure Resource Manager
request the module sends, by method; each is a global function the module's unqualified
`Invoke-MgGraphRequest` or `Invoke-WebRequest` resolves to (a function outranks a cmdlet), and it
forwards each request to the real cmdlet, module-qualified. The role is the one the baseline names
(Reports Reader when the baseline names none: the cmdlets remove nothing but the test group's own
assignments). Principal: `oer-s95-grp`.

### 1.0. The fences and the role

- [ ] **1.0** The module resolves both transports to the fences, and the section's directory role is a low-risk one.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
$null = [System.IO.Directory]::CreateDirectory($Raw)
[System.IO.File]::WriteAllText($FencePath, @'
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { `$M = if ([string]`$Method) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S95GraphWrites++ }; `$global:S95GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'Get') { `$global:S95ArmWrites++; `$global:S95ArmLog.Add(`"`$(([string]`$Method).ToUpperInvariant()) `$(if ([string]`$Uri -match 'providers/Microsoft\.Authorization/([A-Za-z]+)') { `$Matches[1] } else { 'other' })`") }; `$global:S95ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$global:S95ArmLog = [System.Collections.Generic.List[string]]::new()
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Invoke-S95 {
    # A plain call, outside any try, as at a prompt. Prints the output objects (a StructureResult as
    # section, item, action and detail; a request object as its type, Status and expiration type), the
    # warnings, the error ids with their category and message, and the request counts; never a token,
    # never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S95GraphCalls = 0; $global:S95GraphWrites = 0; $global:S95ArmCalls = 0; $global:S95ArmWrites = 0
    $global:S95ArmLog.Clear()
    $All = @(& $Call 2>&1 3>&1)
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S95GraphCalls (writes: $global:S95GraphWrites); ARM requests: $global:S95ArmCalls (writes: $global:S95ArmWrites$(if ($global:S95ArmLog.Count) { ": $($global:S95ArmLog -join ', ')" }))"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
        } elseif ($O.PSObject.Properties['Status']) {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0]); Status $($O.Status)$(if ($O.PSObject.Properties['ExpirationType']) { "; expiration $($O.ExpirationType)" })"
        } else {
            Write-OerLiveStep "$($Label): object $($O.PSObject.TypeNames[0])"
        }
    }
    foreach ($W in $Warns) {
        $Text = ConvertTo-OerLiveRedacted -Text $W.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): warning -- $Text"
    }
    foreach ($E in $Errs) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): $(([string]$E.FullyQualifiedErrorId -split ',')[0]); category $($E.CategoryInfo.Category) -- $Text"
    }
    , $Out
}
'@, [System.Text.UTF8Encoding]::new($false))
. $FencePath
$Base = Read-OerLiveBaseline -Name 'baseline-s95'
$Role = if ($Base -and $Base['directoryRole']) { [string]$Base['directoryRole'] } else { 'Reports Reader' }
Write-OerLiveStep "1.0 the section's directory role: '$Role'; low-risk: $(@('Reports Reader', 'Message Center Reader') -ccontains $Role); the baseline names a role with no direct holder: $([bool]($Base -and $Base['directoryRole']))"
```

**Expect:** the identity lines `True`; the fences `True`; the role `'Reports Reader'` or `'Message
Center Reader'`, low-risk `True`.
**Failure looks like:** the fences `False` -- nothing was called; a role that is not low-risk -- STOP.

Result:

### 1.1. New-OEREligibleDirectoryRoleAssignment: Provisioned, no error

- [ ] **1.1** `New-OEREligibleDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one Graph write.

```powershell
$null = Invoke-S95 -Label '1.1 eligible create' -Call { New-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; Graph requests: N (writes: 1)`; `object
Omnicit.EntraRBAC.DirectoryRoleScheduleRequest; Status Provisioned; expiration afterDuration` (or
`afterDateTime`).
**Failure looks like:** `EligibilityRequestFailed` on a `Provisioned` object -- the rule takes a
success for a failure; any other error -- read it.

Result:

### 1.2. New-OERActiveDirectoryRoleAssignment: Provisioned, no error

- [ ] **1.2** `New-OERActiveDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one Graph write.

```powershell
$null = Invoke-S95 -Label '1.2 active create' -Call { New-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
$ActiveAt = [datetime]::UtcNow
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Provisioned`.
**Failure looks like:** `AssignmentRequestFailed` on a `Provisioned` object -- the rule takes a
success for a failure.

Result:

### 1.3. Remove-OEREligibleDirectoryRoleAssignment: Revoked, no error

- [ ] **1.3** After the active assignment has run five minutes, `Remove-OEREligibleDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error.

```powershell
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $ActiveAt).TotalSeconds))
Write-OerLiveStep "1.3 waiting $Wait s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes."
Start-Sleep -Seconds $Wait
$null = Invoke-S95 -Label '1.3 eligible remove' -Call { Remove-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Revoked`; the cmdlet's own
removal warning.
**Failure looks like:** `EligibilityRequestFailed` on a `Revoked` object -- a removal's success read as
a failure; `ActiveDurationTooShort` -- wait longer and run 1.3 again.

Result:

### 1.4. Remove-OERActiveDirectoryRoleAssignment: Revoked, no error, and nothing left

- [ ] **1.4** `Remove-OERActiveDirectoryRoleAssignment -Role` (the role) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error; afterwards neither kind is listed for the group.

```powershell
$null = Invoke-S95 -Label '1.4 active remove' -Call { Remove-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -Confirm:$false }
$W = Wait-OerLiveConverged -Activity "1.4 oer-s95-grp holds no '$Role' assignment" -Read {
    , @(@(Get-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "1.4 oer-s95-grp holds no '$Role' assignment: True ($($W.Attempts) read(s), $($W.Seconds) s)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... (writes: 1)`; `Status Revoked`; `holds no ...
assignment: True`.
**Failure looks like:** `AssignmentRequestFailed` on a `Revoked` object; a wait that does not
converge -- the teardown removes what is left.

Result:

## 2. BL-33: the apply engine's directory role rows, created, unchanged and pruned (G8)

**2.1 to 2.5 run in ONE process**, in order, with the fences of section 1 (the first block loads them
from the file 1.0 wrote); 2.3 runs its `-WhatIf` plan in a child process of its own. Two apply documents in the
step's raw folder, deleted at the end of 2.5, each declaring the section's role, eligible and active,
time-bound one day:

- **document A** -- principal `oer-s95-grp`;
- **document B** -- principal `oer-s95-grp2`. Applied with `-Prune`, the pairs it declares make
  `oer-s95-grp`'s two assignments undeclared candidates, which are removed.

**The prune runs only when the baseline names a role with no direct holder.** Otherwise a
`-Prune` of that role would remove a real holder's assignment: 2.3 to 2.5 are then `[~]`, class B,
and 2.1 and 2.2 still run.

### 2.1. Document A: Created, Created

- [ ] **2.1** `Invoke-OERStructure -Path` (document A) `-Confirm:$false` reports both rows `Created`, no error, two Graph writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Base = Read-OerLiveBaseline -Name 'baseline-s95'
$Role = if ($Base -and $Base['directoryRole']) { [string]$Base['directoryRole'] } else { 'Reports Reader' }
$PruneAllowed = [bool]($Base -and $Base['directoryRole'])
function New-S95Doc {
    param([string]$Name, [string]$Principal)
    $Path = Join-Path $Raw $Name
    $null = [System.IO.Directory]::CreateDirectory($Raw)
    [System.IO.File]::WriteAllText($Path, (@{
                version                  = '1.0'
                directoryRoleAssignments = @(
                    @{ role = $Role; principal = $Principal; principalType = 'Group'; assignmentType = 'Eligible'; durationDays = 1 }
                    @{ role = $Role; principal = $Principal; principalType = 'Group'; assignmentType = 'Active'; durationDays = 1 }
                )
            } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    $Path
}
$DocA = New-S95Doc -Name 'apply-s95-a.json' -Principal 'oer-s95-grp'
$DocB = New-S95Doc -Name 'apply-s95-b.json' -Principal 'oer-s95-grp2'
Write-OerLiveStep "2.1 role '$Role'; the prune checks run: $PruneAllowed"
$null = Invoke-S95 -Label '2.1 document A' -Call { Invoke-OERStructure -Path $DocA -Confirm:$false }
$CreatedAt = [datetime]::UtcNow
```

**Expect:** `errors: none; ... (writes: 2)`; two rows `directoryRoleAssignments | ... -> oer-s95-grp
(Eligible) | Created` and `(Active) | Created`.
**Failure looks like:** a `Failed` row with `EligibilityRequestFailed` or `AssignmentRequestFailed` --
a success read as a failure; a `Created` row with an error -- the old defect.

Result:

### 2.2. Document A again: only Unchanged (G8)

- [ ] **2.2** The same document A again: both rows `Unchanged`, no Graph write.

```powershell
$null = Invoke-S95 -Label '2.2 document A again' -Call { Invoke-OERStructure -Path $DocA -Confirm:$false }
```

**Expect:** `errors: none; ... (writes: 0)`; two rows `Unchanged`.
**Failure looks like:** a write, or a row other than `Unchanged`.

Result:

### 2.3. Document B with -Prune -WhatIf: the plan removes only oer-s95-grp's two assignments

- [ ] **2.3** After the active assignment has run five minutes, `Invoke-OERStructure -Path` (document B) `-Prune -WhatIf`, in a child process, plans `would create` for `oer-s95-grp2` twice and `would remove` for `oer-s95-grp` twice and for no other principal, and writes nothing.

```powershell
if (-not $PruneAllowed) { Write-OerLiveStep '2.3 SKIPPED: the baseline names no role free of direct holders; 2.3 to 2.5 are class B.' } else {
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $CreatedAt).TotalSeconds))
Write-OerLiveStep "2.3 waiting $Wait s: Graph removes a principal's assignments of a role once its active assignment of the role has run five minutes."
Start-Sleep -Seconds $Wait
$GrpId = [string](Get-OERGroup -Group 'oer-s95-grp' -ErrorAction Stop).Id
$Child = Join-Path $Raw 'child-s95-2.3.ps1'
[System.IO.File]::WriteAllText($Child, @"
`$ErrorActionPreference = 'Continue'
Import-Module (Join-Path '$VaultDir' 'OerLive\OerLive.psm1') -Force
`$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory '$VaultDir'
`$Cfg.Repo = '$($Cfg.Repo)'
Connect-OerLive -Arm
`$Rows = @(Invoke-OERStructure -Path '$DocB' -Prune -WhatIf 2>&1 3>&1)
foreach (`$R in `$Rows) {
    if (`$R.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') { "ROW|`$(`$R.Action)|`$(`$R.Item)|`$(`$R.Detail)" }
    elseif (`$R -is [System.Management.Automation.ErrorRecord]) { "ERROR|`$(([string]`$R.FullyQualifiedErrorId -split ',')[0])" }
    elseif (`$R -is [System.Management.Automation.WarningRecord]) { "WARNING|`$(`$R.Message)" }
}
Disconnect-OerLive
"@, [System.Text.UTF8Encoding]::new($false))
$ChildOut = @(& pwsh -NoProfile -File $Child 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $ChildOut) { Write-OerLiveStep "2.3 child: $(ConvertTo-OerLiveRedacted -Text $Line)" }
Remove-Item -LiteralPath $Child
$PlanRows = @($ChildOut | Where-Object { $_.StartsWith('ROW|') })
$Removes = @($PlanRows | Where-Object { $_ -match '^ROW\|Skipped\|' -and $_ -match '\|would remove ' })
$Foreign = @($Removes | Where-Object { $_ -notmatch [regex]::Escape($GrpId) })
$WhatIfLines = @($ChildOut | Where-Object { $_ -match '^What if: ' })
Write-OerLiveStep "2.3 plan rows: $($PlanRows.Count); would remove: $($Removes.Count); a would-remove row names a principal other than oer-s95-grp: $($Foreign.Count -gt 0); What if lines: $($WhatIfLines.Count); errors: $(@($ChildOut | Where-Object { $_.StartsWith('ERROR|') }).Count)"
if ($Foreign.Count -gt 0 -or $Removes.Count -ne 2) { Disconnect-OerLive; throw 'STOP: the prune plan does not remove exactly oer-s95-grp''s two assignments; 2.4 is not run.' }
}
```

**Expect:** the child's identity lines `True`; four plan rows, two `Skipped | ... -> oer-s95-grp2 ...
| would create ...` and two `Skipped | ... | would remove undeclared ... assignment of directory role
... for principal ...` whose principal is `oer-s95-grp` (`a would-remove row names a principal other
than oer-s95-grp: False`, `would remove: 2`); `errors: 0`; the child's `What if:` lines redacted.
**Failure looks like:** a would-remove row for another principal -- STOP, 2.4 is not run (a real
holder of the role); fewer than two -- read the plan.

Result:

### 2.4. Document B with -Prune: Created twice, Removed twice

- [ ] **2.4** `Invoke-OERStructure -Path` (document B) `-Prune -Confirm:$false` reports the two `oer-s95-grp2` rows `Created` and the two `oer-s95-grp` rows `Removed`, no `Failed` row and no error.

```powershell
if (-not $PruneAllowed) { Write-OerLiveStep '2.4 SKIPPED: class B (see 2.3).' } else {
$null = Invoke-S95 -Label '2.4 document B, prune' -Call { Invoke-OERStructure -Path $DocB -Prune -Confirm:$false }
$W = Wait-OerLiveConverged -Activity "2.4 oer-s95-grp holds no '$Role' assignment" -Read {
    , @(@(Get-OEREligibleDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveDirectoryRoleAssignment -Role $Role -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "2.4 oer-s95-grp holds no '$Role' assignment: True ($($W.Attempts) read(s), $($W.Seconds) s)"
}
```

**Expect:** `errors: none; ... (writes: 5)` -- the two removals, the two creates, and the POST
`getMemberGroups` read of the signed-in identity's memberships (the handler's guard 4 for a group
candidate), which the fence counts as a non-GET request; rows `Removed` twice (`removed undeclared eligible ...`
and `active ...`) and `Created` twice for `oer-s95-grp2`; the handler's prune warnings; `holds no ...
assignment: True`.
**Failure looks like:** a `Failed` row carrying `EligibilityRequestFailed` or
`AssignmentRequestFailed` on a `Revoked` answer -- a removal's success read as a failure.

Result:

### 2.5. Document B with -Prune again: only Unchanged (G8), and the documents are removed

- [ ] **2.5** The same document B with `-Prune` again: both rows `Unchanged`, no `Removed` or `Extra` row, no Graph write; the fences are removed and the two documents deleted.

```powershell
if ($PruneAllowed) {
    $null = Invoke-S95 -Label '2.5 document B again' -Call { Invoke-OERStructure -Path $DocB -Prune -Confirm:$false }
} else { Write-OerLiveStep '2.5 SKIPPED: class B (see 2.3).' }
# Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest
Remove-Item -LiteralPath $DocA, $DocB
Write-OerLiveStep "Fences removed: $(-not (Get-Command -Name Invoke-MgGraphRequest -CommandType Function -ErrorAction Ignore) -and -not (Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore)); documents deleted: $(-not (Test-Path -LiteralPath $DocA) -and -not (Test-Path -LiteralPath $DocB))"
Disconnect-OerLive
```

**Expect:** `errors: none; ... (writes: 0)`; two rows `Unchanged`; `Fences removed: True; documents
deleted: True`.
**Failure looks like:** a write, a `Removed` or an `Extra` row.

Result:

## 3. BL-33: the Azure role cmdlets on a real Provisioned and Revoked answer

**3.0 to 3.4 run in ONE process**, in order, with the fences of section 1. Role Reader at
`oer-s95-rg` (named by the subscription and the resource group), principal `oer-s95-grp`, time-bound
one day. The Reader policy at a resource group requires a justification for an active assignment
(measured in this run: without one Azure Resource Manager refuses the request with
`RoleAssignmentRequestPolicyValidationFailed`), so every active call passes `-Justification`. The
read-backs filter the principal's schedules to `oer-s95-rg`: a principal filter cannot be combined
with `-AtScope`.

### 3.0. The fences

- [ ] **3.0** The module resolves both transports to the fences.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Rg = @{ Subscription = $Cfg.SubscriptionId; ResourceGroup = 'oer-s95-rg' }
```

**Expect:** the identity lines `True`; the fences `True`.
**Failure looks like:** the fences `False` -- nothing was called.

Result:

### 3.1. New-OEREligibleRoleAssignment: Provisioned, no error

- [ ] **3.1** `New-OEREligibleRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -DurationDays 1 -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one ARM write.

```powershell
$null = Invoke-S95 -Label '3.1 eligible create' -Call { New-OEREligibleRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -DurationDays 1 -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... ARM requests: N (writes: 1: PUT
roleEligibilityScheduleRequests)`; `object Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned;
expiration AfterDuration`.
**Failure looks like:** `EligibilityRequestFailed` on a `Provisioned` object.

Result:

### 3.2. New-OERActiveRoleAssignment, time-bound: Provisioned, no error

- [ ] **3.2** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -DurationDays 1 -Justification ... -Confirm:$false` emits one request object with status `Provisioned` and writes no error; one ARM write and no policy write.

```powershell
$null = Invoke-S95 -Label '3.2 active create' -Call { New-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -DurationDays 1 -Justification 'oer-s95 live verification' -Confirm:$false }
$ActiveAt = [datetime]::UtcNow
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleAssignmentScheduleRequests)`;
`Status Provisioned; expiration AfterDuration`; no policy warning (a time-bound grant needs no open).
**Failure looks like:** `AssignmentRequestFailed` on a `Provisioned` object.

Result:

### 3.3. Remove-OEREligibleRoleAssignment: Revoked, no error

- [ ] **3.3** After the active assignment has run five minutes, `Remove-OEREligibleRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error.

```powershell
$Wait = [int][math]::Max(0, [math]::Ceiling(305 - ([datetime]::UtcNow - $ActiveAt).TotalSeconds))
Write-OerLiveStep "3.3 waiting $Wait s, so a removal of the group's Reader assignments is not refused as too young."
Start-Sleep -Seconds $Wait
$null = Invoke-S95 -Label '3.3 eligible remove' -Call { Remove-OEREligibleRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Confirm:$false }
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleEligibilityScheduleRequests)`;
`Status Revoked`.
**Failure looks like:** `EligibilityRequestFailed` on a `Revoked` object.

Result:

### 3.4. Remove-OERActiveRoleAssignment: Revoked, no error, and nothing left

- [ ] **3.4** `Remove-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Confirm:$false` emits one request object with status `Revoked` and writes no error; afterwards neither kind is listed for the group at `oer-s95-rg`.

```powershell
$null = Invoke-S95 -Label '3.4 active remove' -Call { Remove-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Confirm:$false }
$W = Wait-OerLiveConverged -Activity '3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg' -Read {
    , @(@(Get-OEREligibleRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop) + @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop) | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
} -Test { @($args[0]).Count -eq 0 }
Write-OerLiveStep "3.4 oer-s95-grp holds no Reader schedule at oer-s95-rg: True ($($W.Attempts) read(s), $($W.Seconds) s)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... (writes: 1: PUT roleAssignmentScheduleRequests)`;
`Status Revoked`; `holds no Reader schedule ...: True`.
**Failure looks like:** `AssignmentRequestFailed` on a `Revoked` object; a wait that does not
converge -- the teardown removes what is left.

Result:

## 4. BL-80: a permanent active Reader assignment at oer-s95-rg opens the policy only after consent

**4.0 to 4.3 run in ONE process**, in order, with the fences of section 1; 4.2 runs its `-WhatIf` in a
child process. The policy's baseline is recorded by the prerequisite (0.3) before the first write,
and the teardown puts it back.

### 4.0. The fences, and whether the policy forbids a permanent active assignment

- [ ] **4.0** The module resolves both transports to the fences, and the Reader policy at `oer-s95-rg` forbids a permanent active assignment (otherwise 4.2 and 4.3 are class B).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Rg = @{ Subscription = $Cfg.SubscriptionId; ResourceGroup = 'oer-s95-rg' }
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s95-rg"
function Get-S95PermanentAllowed {
    $Guid = ([string](Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$([uri]::EscapeDataString("roleName eq 'Reader'"))").Body.value[0].name).ToLowerInvariant()
    $P = Get-OerLiveArmRolePolicy -Scope $RgScope -RoleDefinitionGuid $Guid
    -not [bool](@($P.Rules | Where-Object { [string]$_['id'] -eq 'Expiration_Admin_Assignment' })[0]['isExpirationRequired'])
}
$Before = Get-S95PermanentAllowed
$Base = Read-OerLiveBaseline -Name 'baseline-s95-rgreader'
Write-OerLiveStep "4.0 the Reader policy at oer-s95-rg allows a permanent active assignment: $Before; the baseline exists: $([bool]$Base)"
```

**Expect:** the identity lines `True`; the fences `True`; `allows a permanent active assignment:
False; the baseline exists: True`.
**Failure looks like:** `allows ...: True` -- the policy already allows it, so the cmdlet opens
nothing: 4.2 and 4.3 are `[~]` class B (the unit tests of `New-OERActiveRoleAssignment` prove the
path), and 4.3 still runs as a plain permanent grant; `the baseline exists: False` -- STOP, nothing
is written to the policy without a baseline.

Result:

### 4.1. Nothing at oer-s95-rg for the group yet

- [ ] **4.1** Before the plan, the group holds no active Reader schedule at `oer-s95-rg`.

```powershell
$Pre = @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
Write-OerLiveStep "4.1 active Reader schedules of oer-s95-grp at oer-s95-rg: $($Pre.Count)"
```

**Expect:** `0` (section 3 removed its own).
**Failure looks like:** above 0 -- wait for 3.4's removal to converge, then read again.

Result:

### 4.2. -WhatIf in a child process: the warning, two planned writes, nothing written

- [ ] **4.2** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Permanent -Justification ... -WhatIf`, in a child process, warns that the assignment requires opening the policy, plans the policy change and the assignment, and writes nothing: the policy still forbids a permanent active assignment and the group holds none.

```powershell
$Child = Join-Path $Raw 'child-s95-4.2.ps1'
[System.IO.File]::WriteAllText($Child, @"
`$ErrorActionPreference = 'Continue'
Import-Module (Join-Path '$VaultDir' 'OerLive\OerLive.psm1') -Force
`$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory '$VaultDir'
`$Cfg.Repo = '$($Cfg.Repo)'
Connect-OerLive -Arm
`$global:ArmWrites = 0
`$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
`$WebFence = "`$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute(`$WebMeta))``nparam(`$([System.Management.Automation.ProxyCommand]::GetParamBlock(`$WebMeta)))``nend { if ([string]```$Method -and [string]```$Method -ne 'Get') { ```$global:ArmWrites++ }; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create(`$WebFence))
`$All = @(New-OERActiveRoleAssignment -Role 'Reader' -Subscription '$($Cfg.SubscriptionId)' -ResourceGroup 'oer-s95-rg' -Group 'oer-s95-grp' -Permanent -Justification 'oer-s95 live verification' -WhatIf 2>&1 3>&1)
foreach (`$R in `$All) {
    if (`$R -is [System.Management.Automation.WarningRecord]) { "WARNING|`$(`$R.Message)" }
    elseif (`$R -is [System.Management.Automation.ErrorRecord]) { "ERROR|`$(([string]`$R.FullyQualifiedErrorId -split ',')[0])" }
    else { "OBJECT|`$(`$R.PSObject.TypeNames[0])" }
}
"ARMWRITES|`$global:ArmWrites"
Remove-Item -Path function:global:Invoke-WebRequest
Disconnect-OerLive
"@, [System.Text.UTF8Encoding]::new($false))
$ChildOut = @(& pwsh -NoProfile -File $Child 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $ChildOut) { Write-OerLiveStep "4.2 child: $(ConvertTo-OerLiveRedacted -Text $Line)" }
Remove-Item -LiteralPath $Child
$WarnAt = [array]::FindIndex([string[]]$ChildOut, [Predicate[string]] { param($L) $L -like 'WARNING|*requires opening the role management policy*' })
$WhatIf = @($ChildOut | Where-Object { $_ -match '^What if: ' })
$After = Get-S95PermanentAllowed
$Held = @(Get-OERActiveRoleAssignment @Rg -Group 'oer-s95-grp' -ErrorAction Stop | Where-Object { $null -ne $_ -and [string]$_.RoleName -eq 'Reader' -and ([string]$_.Scope).EndsWith('/resourceGroups/oer-s95-rg', [System.StringComparison]::OrdinalIgnoreCase) })
Write-OerLiveStep "4.2 the policy warning under -WhatIf: $($WarnAt -ge 0); What if lines: $($WhatIf.Count); ARM writes: $(@($ChildOut | Where-Object { $_ -like 'ARMWRITES|*' }) -replace '^ARMWRITES\|', ''); objects: $(@($ChildOut | Where-Object { $_ -like 'OBJECT|*' }).Count); errors: $(@($ChildOut | Where-Object { $_ -like 'ERROR|*' }).Count); the policy now allows a permanent active assignment: $After; active Reader schedules of oer-s95-grp: $($Held.Count)"
```

**Expect:** the child's identity lines `True`; `the policy warning under -WhatIf: True`, from the `WARNING|This assignment requires opening the role
management policy for role 'Reader' at scope ... to allow PERMANENT active assignments ...` line;
two `What if:` lines (the policy change `Set-OERRoleManagementPolicy` plans, and `Create active Azure
role assignment`), redacted; `ARM writes: 0`; `objects: 0`; `errors: 0`; `the policy now allows a
permanent active assignment: False`; `active Reader schedules of oer-s95-grp: 0`.
**Failure looks like:** `ARM writes` above 0, or the policy allowing it after the plan -- the old
defect (the open before the gate); one `What if:` line -- the plan no longer shows the policy change.

Result:

### 4.3. Confirmed: the policy is opened, then the assignment is Provisioned

- [ ] **4.3** `New-OERActiveRoleAssignment -Role Reader` (at `oer-s95-rg`) `-Group oer-s95-grp -Permanent -Justification ... -Confirm:$false` warns, opens the policy, then creates the assignment: one request object `Provisioned` with no expiration, no error, the ARM writes in the order policy then request; afterwards the policy allows a permanent active assignment.

```powershell
$null = Invoke-S95 -Label '4.3 permanent active create' -Call { New-OERActiveRoleAssignment -Role 'Reader' @Rg -Group 'oer-s95-grp' -Permanent -Justification 'oer-s95 live verification' -Confirm:$false }
$After = Get-S95PermanentAllowed
Write-OerLiveStep "4.3 the policy now allows a permanent active assignment: $After (the teardown puts the baseline back)"
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; ... ARM requests: N (writes: 2: PATCH
roleManagementPolicies, PUT roleAssignmentScheduleRequests)`; `object
Omnicit.EntraRBAC.RoleScheduleRequest; Status Provisioned; expiration NoExpiration`; the warning;
`allows a permanent active assignment: True`.
**Failure looks like:** the PUT before the PATCH -- the open and the grant out of order; an error
after a `Provisioned` object; `PolicyOpenedButGrantFailed` -- read it, and check that the policy was
rolled back.

Result:

## 5. BL-50: a connected-organization scope with no target is refused, and nothing is sent

**5.0 to 5.2 run in ONE process**, in order, with the fences of section 1.

### 5.0. The fences and the policy

- [ ] **5.0** The module resolves both transports to the fences, and `oer-s95-ap` has one assignment policy, `oer-s95-pol`, administrator-only.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s95'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$FencePath = Join-Path $Raw 's95-fences.ps1'
if (-not (Test-Path -LiteralPath $FencePath)) { Disconnect-OerLive; throw 'STOP: run 1.0 first; it writes the fences to raw\s95\.' }
. $FencePath
$Pols = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s95-ap' -ErrorAction Stop)
$Pol = $Pols | Where-Object { $_.DisplayName -ceq 'oer-s95-pol' } | Select-Object -First 1
$PolId = [string]$Pol.Id
$Em = 'v1.0/identityGovernance/entitlementManagement'
function Get-S95PolicyState {
    $R = Invoke-OerLiveGraph -Uri "$Em/assignmentPolicies/$PolId"
    Assert-OerLiveOk -Response $R -Activity 'Reading oer-s95-pol' | Out-Null
    [PSCustomObject]@{ Scope = [string]$R.Body['allowedTargetScope']; Targets = @($R.Body['specificAllowedTargets']).Count; Modified = [string]$R.Body['modifiedDateTime']; Description = [string]$R.Body['description'] }
}
$Start = Get-S95PolicyState
Write-OerLiveStep "5.0 policies of oer-s95-ap: $($Pols.Count); oer-s95-pol found: $([bool]$PolId); allowedTargetScope $($Start.Scope); targets $($Start.Targets)"
```

**Expect:** the identity lines `True`; the fences `True`; `policies of oer-s95-ap: 1; oer-s95-pol
found: True; allowedTargetScope notSpecified; targets 0`.
**Failure looks like:** no policy -- run 0.3 again.

Result:

### 5.1. -RequestorScope SpecificConnectedOrganizationUsers with no target: InvalidPolicyInput, no write

- [ ] **5.1** `Set-OERAccessPackageAssignmentPolicy -Id` (the policy) `-DisplayName oer-s95-pol -RequestorScope` (a `SpecificConnectedOrganizationUsers` scope from `New-OERAccessPackageRequestorScope`) `-Confirm:$false` writes `InvalidPolicyInput`, emits nothing, sends one Graph read and no write, and leaves the policy as it was.

```powershell
$Scope = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers -ErrorAction Stop
$null = Invoke-S95 -Label '5.1 refused' -Call { Set-OERAccessPackageAssignmentPolicy -Id $PolId -DisplayName 'oer-s95-pol' -RequestorScope $Scope -Confirm:$false }
$Now = Get-S95PolicyState
Write-OerLiveStep "5.1 the policy is unchanged: $($Now.Scope -ceq $Start.Scope -and $Now.Targets -eq $Start.Targets -and $Now.Modified -ceq $Start.Modified)"
```

**Expect:** `output objects 0; errors: InvalidPolicyInput; Graph requests: 1 (writes: 0); ARM
requests: 0`; the message naming the connected organizations and `-RequestorScope`; `the policy is
unchanged: True`.
**Failure looks like:** `writes: 1` -- the PUT went out (the old defect); no error.

Result:

### 5.2. The control: the same call without -RequestorScope sends the update

- [ ] **5.2** `Set-OERAccessPackageAssignmentPolicy -Id` (the policy) `-DisplayName oer-s95-pol -Description 'oer-s95 control' -Confirm:$false` sends one PUT and emits the updated policy; the scope is carried forward unchanged.

```powershell
$null = Invoke-S95 -Label '5.2 control' -Call { Set-OERAccessPackageAssignmentPolicy -Id $PolId -DisplayName 'oer-s95-pol' -Description 'oer-s95 control' -Confirm:$false }
$Now = Get-S95PolicyState
Write-OerLiveStep "5.2 description changed: $($Now.Description -ceq 'oer-s95 control'); allowedTargetScope $($Now.Scope); targets $($Now.Targets)"
# Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest
Disconnect-OerLive
```

**Expect:** `output objects 1; errors: none; Graph requests: 2 (writes: 1)`; `object
Omnicit.EntraRBAC.AssignmentPolicy`; `description changed: True; allowedTargetScope notSpecified;
targets 0`.
**Failure looks like:** no PUT -- the refusal fires on a call without `-RequestorScope`.

Result:

## Teardown

### T.1. The Azure schedules, the objects and the Reader policy are put back, nothing carries the prefix, and the main clone is untouched

- [ ] **T.1** `Initialize-OerS95Prereq.ps1 -Teardown -Unattended` removes the Azure schedules of the prefixed groups at `oer-s95-rg` (4.3's permanent active assignment), the directory role assignments of `oer-s95-grp2` (2.4), the policy, the package, the catalog and both groups, puts the Reader policy at `oer-s95-rg` back to its baseline and deletes the resource group; the sweep finds nothing with the prefix; the counts equal the baseline; no session is left; the main clone is on `main` at the HEAD S.1 recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Teardown exit code: $Code"
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "A Graph SDK session is left: $([bool](Get-MgContext)); the module holds a session: $([bool]($Module -and (& $Module { $script:_OERAuthState })))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the teardown's identity lines `True`; `Teardown A: oer-s95-grp at oer-s95-rg: eligible 0,
active (Assigned) 1` and its removal (after the five-minute rule when 4.3 was less than five minutes
ago), `oer-s95-grp2 ... eligible 0, active (Assigned) 0`; the library's step 1 removing
`oer-s95-grp2`'s two directory role assignments, step 3 the policy, the package and the catalog, step
5 both groups; `Teardown C: Reader policy at oer-s95-rg at its baseline: True (rules differing
before: N...)` and `deleted oer-s95-rg`; `Resource group oer-s95-rg exists after the teardown:
False`; the three counts equal to the baseline (`True`); exit code 0; no session left; the main clone
on `main` at the HEAD S.1 recorded.
**Failure looks like:** exit code 1 with a `STOP` line -- the policy could not be put back: the
resource group is NOT deleted, and the step stops (G11.5); exit code 3 -- residue in
`raw\residue.json`, which the next prereq run retries; report each row. An object deleted with 204 can
still show in the sweep for a minute or two: read back with T.2 before judging.

Result:

### T.2. Read back, a few minutes later

- [ ] **T.2** `Initialize-OerS95Prereq.ps1 -ReadBack` finds no object with the prefix, no resource group `oer-s95-rg`, the counts equal to the baseline and no residue row.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS95Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s95-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
```

**Expect:** `Sweep: no user, group, ... starting with 'oer-s95-' is left.`; `Read-back: resource group
oer-s95-rg exists: False`; the three counts equal (`True`); `prefixed objects left: 0; unread
collections: 0; residue rows: 0`.
**Failure looks like:** an object left -- run T.1 again; a residue row -- report it.

Result:
