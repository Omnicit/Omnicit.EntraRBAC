# Live verification checklist -- PIM policies without a half-applied pair and without contradictory approval (fix/pim-policy-pair-restore-and-approval-refusals)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates one plain security group,
`oer-s94-grp`, and one empty resource group, `oer-s94-rg`, in the test subscription, and records three
baselines before the first write: the tenant's group count, the activation pair of `oer-s94-grp`'s
MEMBER PIM-for-Groups policy, and the Reader role's policy at `oer-s94-rg`. Section 1 switches the
activation of `oer-s94-grp`'s member policy between multi-factor authentication and an
authentication context with `Invoke-OERStructure`, and back -- the only writes of this file. Sections
2 and 3 are refusals that must send nothing, a few reads, and one apply run with `-WhatIf`. The
teardown puts the group's policy pair back to its baseline, deletes the group, puts the Reader policy
at `oer-s94-rg` back to its baseline (it is never written, so this must find nothing to do) and
deletes the resource group. No directory role policy and no Azure role policy is written: a role
policy outside `oer-s94-rg` is never changed, and the one at `oer-s94-rg` only planned.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive -Arm`, which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s94/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed**, and **no error record is ever rendered**: every
block prints the error id, its category and the message (redacted, cut at 300 characters) only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-09: the pair put-back moves into one owner, and the group cmdlet gains it** ("put back the
  accepted half of a rejected PIM rule pair in Set-OERGroupPimPolicy"). The new private
  `Send-OERPimRulePatch` sends a confirmed PIM rule set one PATCH per rule and, when Microsoft Graph
  accepts the first rule of the MFA / authentication-context pair and rejects the second, PATCHes the
  first straight back to its live version. `Set-OERDirectoryRoleManagementPolicy` already did this
  inline and now calls the helper. `Set-OERGroupPimPolicy` did not; it now confirms every rule before
  it sends any, reads the first half's live rule before the first PATCH (or reuses the rule its MFA /
  context reconcile already read), and reports a rule it put back as not changed.
- **B. BL-10: no warning between the first PATCH and the last put-back.** The helper writes no
  warning; both cmdlets write its messages after it returns, so `-WarningAction Stop` can no longer
  stop a cmdlet half-way ("prove no warning stops a PIM policy update half-way").
- **C. BL-08: `-RequireApproval $false` beside an approver parameter is refused** ("refuse
  -RequireApproval false beside an approver parameter"). `Set-OERGroupPimPolicy`,
  `Set-OERDirectoryRoleManagementPolicy` and `Set-OERRoleManagementPolicy` used to let the approvers
  turn approval back ON; they now refuse the combination with the existing `MutuallyExclusiveParameter`
  before any lookup or request.
- **D. BL-16: a declared empty approver side converges on Azure, and zero approvers are refused**
  ("converge a declared empty approver side on Azure and refuse zero approvers"). The Azure apply diff
  compared a declared `[]` as one blank entry and planned a change on every run;
  `Set-OERRoleManagementPolicy` now refuses approver parameters that name no approver with
  `ApproverRequired`, before any lookup or request.

A live tenant is needed for what the unit tests stub: the real PATCH order Graph sees for the pair in
both directions, with the new first-half read and no put-back on the happy path (section 1); a real
apply converging twice (G8); and the refusals counted by fences around the module's real transports
(sections 2 and 3).

## What this file does not check, and why

- **The put-back itself (class B, G9).** It needs Graph to accept the first half of the pair and
  reject the second, and in the order `Get-OERPimRulePatchOrder` gives Graph accepts both. Proved
  offline: `tests/Unit/Private/Send-OERPimRulePatch.Tests.ps1` (the put-back, its body, a failed
  put-back, a missing live version, a first half rejected), `tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1`,
  Describe `Set-OERGroupPimPolicy MFA and authentication context pair, one half rejected`, and the
  existing Context `MFA and authentication context rules sent together, and one of them rejected` in
  `tests/Unit/Public/Set-OERDirectoryRoleManagementPolicy.Tests.ps1`.
- **BL-10 (class B, G9).** It needs a rejected rule. Proved offline with `-WarningAction Stop`, inside
  a `try` and in a runspace whose script has no `try`, in both cmdlet test files (the
  `-WarningAction Stop` Describes and Contexts), and at the helper level in
  `Send-OERPimRulePatch.Tests.ps1`.
- **A failed first-half read** (the group cmdlet warns before any PATCH and carries on without a
  possible put-back): class B, the same Describe in `Set-OERGroupPimPolicy.Tests.ps1`.
- **The directory cmdlet's PATCH loop live.** It moved into the helper unchanged, but this step makes
  no change to a role policy outside `oer-s94-rg`, so the directory role is only read and refused
  here (section 2). Its loop is proved offline by the unchanged directory test file and by the helper's
  tests.
- **Convergence (G8)** applies to section 1, the one write: 1.3 and 1.5 run each document again. The
  Azure diff change is a plan (3.2), and a plan has nothing to run twice.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **prerequisite script** `Initialize-OerS94Prereq.ps1` beside OerLive (outside the repository).
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
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s94'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Send-OERPimRulePatch' -Quiet)
$C = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch '-RequireApproval $false and -ApproverUser/-ApproverGroup contradict each other').Count
$D = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'name no approver, ').Count
Write-OerLiveStep "The worktree's build carries A: $A; the C refusal (three cmdlets): $C; the D refusal: $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; the C refusal (three cmdlets): 3; the D refusal: 1`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; `False`, or a count below the expected one, on the last line -- build the worktree first
(`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s94'
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

### 0.2. The prerequisite plan names only oer-s94- objects

- [ ] **0.2** `Initialize-OerS94Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every tenant `What if:` target starts with `oer-s94-`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS94Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baseline) go to raw\s94\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s94\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s94\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s94\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s94-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s94-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own local files under `raw\s94\` (the transcript and, on a first run, the count baseline) and
two tenant targets, `oer-s94-grp` and `oer-s94-rg` (none if they exist already), every tenant target
starting with `oer-s94-` (`True`); "No member-policy baseline" and "No Reader-policy baseline" lines,
since under `-WhatIf` neither object exists yet.
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run.

Result:

### 0.3. The prerequisite objects and the policy baselines

- [ ] **0.3** `Initialize-OerS94Prereq.ps1 -Unattended` writes the count baseline when there is none, creates `oer-s94-grp` and `oer-s94-rg`, and records the member-policy baseline of the group and the Reader-policy baseline at the resource group.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS94Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the identity lines `True`; the count baseline written (groups N) or found; `Created group
oer-s94-grp` and `Created resource group oer-s94-rg` (or `exists`); the member policy of `oer-s94-grp`
listed (after a replication wait, if any), its pair printed (`MFA on activation: ...; authentication
context: ...`) and its baseline written; the Reader policy at `oer-s94-rg` read as the scope's own
(`True`) and its baseline written; `Summary: oer-s94-grp present; oer-s94-rg present`; exit code 0.
**Failure looks like:** exit code 1 -- read the `Refusing to run` or `Stopped` line; a 401/403 -- STOP;
the member policy not listed within the budget -- run the script again (it completes what is missing,
and a baseline is written once).

Result:

## 1. The group cmdlet's pair, both directions, through Invoke-OERStructure (G8)

**1.0 to 1.5 run in ONE process**, in order. The fences count every Graph and Azure Resource Manager
request the module sends, by method; each is a global function the module's unqualified
`Invoke-MgGraphRequest` or `Invoke-WebRequest` resolves to (a function outranks a cmdlet), and it
forwards each request to the real cmdlet, module-qualified. The Graph fence also records, in order,
every request to ONE rule of a PIM policy as `METHOD rule-id` -- the PATCH order and the first-half
read this file is about -- and nothing else (no id, no path). The apply documents are written to the
step's raw folder and deleted at the end of 1.5.

Two documents for the MEMBER policy of `oer-s94-grp`:

- **document M** ("MFA"): `activationEnablement` `MultiFactorAuthentication`, `Justification`, and
  `authenticationContextId` `""` (no context);
- **document X** ("context"): `activationEnablement` `Justification` and `authenticationContextId` the
  context 1.0 picks. If the tenant has no published authentication context, document X declares only
  `activationEnablement` `Justification` -- the MFA half alone -- and the pair is class B (see 1.0).

### 1.0. The authentication context this section uses

- [ ] **1.0** The tenant's authentication contexts are read; the section uses the first published one in id order, or, when there is none, says so and runs the MFA half only.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s94'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { `$M = if ([string]`$Method) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S94GraphWrites++ }; `$global:S94GraphCalls++; if ([string]`$Uri -match 'roleManagementPolicies/[^/?]+/rules/([A-Za-z_]+)') { `$global:S94RuleLog.Add(`"`$M `$(`$Matches[1])`") }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'Get') { `$global:S94ArmWrites++ }; `$global:S94ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$global:S94RuleLog = [System.Collections.Generic.List[string]]::new()
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Invoke-S94 {
    # A plain call, outside any try, as at a prompt. Prints the output objects (a StructureResult as
    # section, item, action and detail; anything else by its type), the warnings, the error ids with
    # their category and message, the request counts and the rule-level requests in order; never a
    # token, never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S94GraphCalls = 0; $global:S94GraphWrites = 0; $global:S94ArmCalls = 0; $global:S94ArmWrites = 0
    $global:S94RuleLog.Clear()
    $All = @(& $Call 2>&1 3>&1)
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S94GraphCalls (writes: $global:S94GraphWrites); ARM requests: $global:S94ArmCalls (writes: $global:S94ArmWrites)"
    Write-OerLiveStep "$($Label): rule-level requests in order: $(if ($global:S94RuleLog.Count) { $global:S94RuleLog -join ', ' } else { 'none' })"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
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
function Get-S94Pair {
    # The member policy's activation pair, read through the module (outside any counted call).
    $P = Get-OERGroupPimPolicy -Group 'oer-s94-grp' -AccessType member -ErrorAction Stop
    [PSCustomObject]@{
        Mfa     = @($P.ActivationEnabledRules) -contains 'MultiFactorAuthentication'
        Flags   = (@($P.ActivationEnabledRules | Sort-Object) -join ',')
        Context = if ($P.AuthenticationContextId) { [string]$P.AuthenticationContextId } else { '' }
    }
}
function Wait-S94Pair {
    # Three reads in a row, 5 s apart, showing the expected pair -- replicas can disagree for a while
    # after a PATCH -- within 180 s.
    param([string]$Activity, [bool]$Mfa, [string]$Context)
    $Streak = 0
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Watch.Elapsed.TotalSeconds -lt 180) {
        $Now = Get-S94Pair
        if ($Now.Mfa -eq $Mfa -and $Now.Context -ceq $Context) { $Streak++ } else { $Streak = 0 }
        if ($Streak -ge 3) { break }
        Start-Sleep -Seconds 5
    }
    Write-OerLiveStep "$($Activity): three steady reads: $($Streak -ge 3) (after $([math]::Round($Watch.Elapsed.TotalSeconds, 1)) s); MFA on activation: $($Now.Mfa); flags: $($Now.Flags); authentication context: $(if ($Now.Context) { "'$($Now.Context)'" } else { 'none' })"
    $Streak -ge 3
}
function New-S94Doc {
    param([string]$Name, [string[]]$Enablement, [AllowNull()][string]$Context, [switch]$NoContext)
    $Member = [ordered]@{ activationEnablement = @($Enablement) }
    if (-not $NoContext) { $Member.authenticationContextId = $Context }
    $Path = Join-Path $Raw $Name
    $null = [System.IO.Directory]::CreateDirectory($Raw)
    [System.IO.File]::WriteAllText($Path, (@{
                version = '1.0'
                groups  = @(@{ displayName = 'oer-s94-grp'; pimPolicy = @{ member = $Member } })
            } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    $Path
}
$Contexts = @(Get-OERAuthenticationContext -ErrorAction Stop)
$Published = @($Contexts | Where-Object { $_.IsAvailable } | Sort-Object { [int](([string]$_.AuthenticationContextId) -replace '^c', '') })
$Ctx = if ($Published.Count -gt 0) { [string]$Published[0].AuthenticationContextId } else { $null }
Write-OerLiveStep "1.0 authentication contexts in the tenant: $($Contexts.Count); published: $($Published.Count); this section uses: $(if ($Ctx) { "'$Ctx'" } else { 'none -- the MFA half only, the pair is class B' })"
$DocM = New-S94Doc -Name 'apply-s94-mfa.json' -Enablement @('MultiFactorAuthentication', 'Justification') -Context ''
$DocX = if ($Ctx) { New-S94Doc -Name 'apply-s94-context.json' -Enablement @('Justification') -Context $Ctx } else { New-S94Doc -Name 'apply-s94-context.json' -Enablement @('Justification') -NoContext }
$Start = Get-S94Pair
Write-OerLiveStep "1.0 the member pair before section 1: MFA on activation: $($Start.Mfa); flags: $($Start.Flags); authentication context: $(if ($Start.Context) { "'$($Start.Context)'" } else { 'none' })"
```

**Expect:** the identity lines `True`; the fences `True`; the count of authentication contexts and of
published ones, and the context the section uses (an id such as `'c1'`), or `none -- the MFA half
only, the pair is class B`; the member pair as the prerequisite's baseline recorded it.
**Failure looks like:** `AuthenticationContext.Read.All` refused (a 403 error from
`Get-OERAuthenticationContext`) -- STOP: a missing permission on the app path; the fences `False` --
nothing was called.

Result:

### 1.1. Document M: the start state, multi-factor authentication on activation

- [ ] **1.1** `Invoke-OERStructure -Path` (document M) `-Confirm:$false` leaves the member pair at MFA on and no context: `Updated` when the baseline differs, `Unchanged` when it already matches; no error; and when both rules are sent, the context rule goes first.

```powershell
$null = Invoke-S94 -Label '1.1 document M' -Call { Invoke-OERStructure -Path $DocM -Confirm:$false }
$null = Wait-S94Pair -Activity '1.1 read back' -Mfa $true -Context ''
```

**Expect:** `errors: none`; one row `groups | oer-s94-grp | Updated | pimPolicy (member) set: ...` (or
`Unchanged ... already matches`); `ARM requests: 0`; when the baseline had a context AND no MFA, the
rule-level requests `GET AuthenticationContext_EndUser_Assignment, PATCH
AuthenticationContext_EndUser_Assignment, PATCH Enablement_EndUser_Assignment`; when only one rule
differed, one PATCH of that rule and no GET of a single rule; a warning that the group was not found
to use PIM for Groups (its first policy write onboards it) is expected on the first write; the read
back `three steady reads: True`, `MFA on activation: True`, `authentication context: none`.
**Failure looks like:** a `Failed` row, an error id, a third PATCH (a put-back) or a 401/403.

Result:

### 1.2. Document X: multi-factor authentication to an authentication context -- both rules, enablement first, no put-back

- [ ] **1.2** `Invoke-OERStructure -Path` (document X) `-Confirm:$false` switches the member pair to the context: the enablement rule's live version is read first, then the enablement rule is PATCHed, then the context rule, and nothing else -- no put-back, no error.

```powershell
$null = Invoke-S94 -Label '1.2 document X' -Call { Invoke-OERStructure -Path $DocX -Confirm:$false }
$null = Wait-S94Pair -Activity '1.2 read back' -Mfa $false -Context $(if ($Ctx) { $Ctx } else { '' })
```

**Expect:** `errors: none`; one row `groups | oer-s94-grp | Updated | pimPolicy (member) set: ...`;
`ARM requests: 0`; with a context: the rule-level requests exactly `GET Enablement_EndUser_Assignment,
PATCH Enablement_EndUser_Assignment, PATCH AuthenticationContext_EndUser_Assignment` (Graph writes 2);
without one: exactly `PATCH Enablement_EndUser_Assignment` (writes 1, class B for the pair); the read
back `three steady reads: True`, `MFA on activation: False`, and the context.
**Failure looks like:** the context PATCHed before the enablement rule; a third PATCH (a put-back of
the enablement rule: Graph rejected the context rule -- record its message); a `PolicyRulesRejected`
error or a `Failed` row; no GET before the PATCHes (the first-half read is missing).

Result:

### 1.3. Document X again: only Unchanged (G8)

- [ ] **1.3** The same document X again: the row is `Unchanged`, no Graph write.

```powershell
$null = Invoke-S94 -Label '1.3 document X again' -Call { Invoke-OERStructure -Path $DocX -Confirm:$false }
```

**Expect:** `errors: none`; `groups | oer-s94-grp | Unchanged | pimPolicy (member) already matches`;
`writes: 0`; rule-level requests `none`.
**Failure looks like:** `Updated` again (a declared field never converges); any write.

Result:

### 1.4. Document M: the authentication context back to multi-factor authentication -- both rules, context first, no put-back

- [ ] **1.4** `Invoke-OERStructure -Path` (document M) `-Confirm:$false` switches the member pair back: the context rule's live version is read first, then the context rule is PATCHed (disabled), then the enablement rule (MFA), and nothing else.

```powershell
$null = Invoke-S94 -Label '1.4 document M' -Call { Invoke-OERStructure -Path $DocM -Confirm:$false }
$null = Wait-S94Pair -Activity '1.4 read back' -Mfa $true -Context ''
```

**Expect:** `errors: none`; one row `Updated`; `ARM requests: 0`; with a context: the rule-level
requests exactly `GET AuthenticationContext_EndUser_Assignment, PATCH
AuthenticationContext_EndUser_Assignment, PATCH Enablement_EndUser_Assignment` (writes 2); without
one: exactly `PATCH Enablement_EndUser_Assignment`; the read back `three steady reads: True`, `MFA on
activation: True`, `authentication context: none`.
**Failure looks like:** the enablement rule PATCHed first (Graph answers `MfaAndAcrsConflict`, a
`PolicyRulesRejected`); a third PATCH; a `Failed` row.

Result:

### 1.5. Document M again: only Unchanged (G8), and the documents are removed

- [ ] **1.5** The same document M again: `Unchanged`, no Graph write; the fences are removed and the two documents deleted.

```powershell
$null = Invoke-S94 -Label '1.5 document M again' -Call { Invoke-OERStructure -Path $DocM -Confirm:$false }
[System.IO.File]::Delete($DocM)
[System.IO.File]::Delete($DocX)
Remove-Item -Path function:Invoke-MgGraphRequest
Remove-Item -Path function:Invoke-WebRequest
Write-OerLiveStep "Fences removed: $(-not (Get-Command -Name Invoke-MgGraphRequest -CommandType Function -ErrorAction Ignore) -and -not (Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore)); documents deleted: $(-not (Test-Path -LiteralPath $DocM) -and -not (Test-Path -LiteralPath $DocX))"
Disconnect-OerLive
```

**Expect:** `errors: none`; `Unchanged ... already matches`; `writes: 0`; `Fences removed: True;
documents deleted: True`.
**Failure looks like:** `Updated` again; any write.

Result:

## 2. BL-08: -RequireApproval $false beside an approver is refused, and nothing is sent

**2.1 to 2.4 run in ONE process**, in order, with the same fences as section 1 (the first block sets
them up again). The approver named in each refused call is the group `oer-s94-grp` itself: the refusal
comes before any lookup, so the name is never resolved. The directory role is the low-risk Reports
Reader (G7); its policy is read before and after, outside the counted calls, and must not change. The
Azure role is Reader at `oer-s94-rg`.

### 2.1. Set-OERGroupPimPolicy

- [ ] **2.1** `Set-OERGroupPimPolicy -Group oer-s94-grp -RequireApproval $false -ApproverGroup oer-s94-grp -Confirm:$false` writes `MutuallyExclusiveParameter` and sends no Graph or ARM request.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s94'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { `$M = if ([string]`$Method) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S94GraphWrites++ }; `$global:S94GraphCalls++; if ([string]`$Uri -match 'roleManagementPolicies/[^/?]+/rules/([A-Za-z_]+)') { `$global:S94RuleLog.Add(`"`$M `$(`$Matches[1])`") }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'Get') { `$global:S94ArmWrites++ }; `$global:S94ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$global:S94RuleLog = [System.Collections.Generic.List[string]]::new()
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Invoke-S94 {
    # As in section 1: a plain call outside any try; counts, rows, warnings, error ids; never a token.
    param([string]$Label, [scriptblock]$Call)
    $global:S94GraphCalls = 0; $global:S94GraphWrites = 0; $global:S94ArmCalls = 0; $global:S94ArmWrites = 0
    $global:S94RuleLog.Clear()
    $All = @(& $Call 2>&1 3>&1)
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S94GraphCalls (writes: $global:S94GraphWrites); ARM requests: $global:S94ArmCalls (writes: $global:S94ArmWrites)"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
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
        Write-OerLiveStep "$($Label): $(([string]$E.FullyQualifiedErrorId -split ',')[0]); category $($E.CategoryInfo.Category); target $($E.TargetObject) -- $Text"
    }
    , $Out
}
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s94-rg"
$null = Invoke-S94 -Label '2.1 Set-OERGroupPimPolicy' -Call { Set-OERGroupPimPolicy -Group 'oer-s94-grp' -RequireApproval $false -ApproverGroup 'oer-s94-grp' -Confirm:$false -ErrorAction Continue }
```

**Expect:** the identity lines `True`; the fences `True`; `output objects 0; errors:
MutuallyExclusiveParameter; Graph requests: 0 (writes: 0); ARM requests: 0 (writes: 0)`; the error's
category `InvalidArgument`, target `oer-s94-grp`, and the message beginning `-RequireApproval $false
and -ApproverUser/-ApproverGroup contradict each other` and ending `Nothing was looked up or sent.`
**Failure looks like:** any request counted (the refusal came after a lookup); no error (approval was
turned on or off).

Result:

### 2.2. Set-OERDirectoryRoleManagementPolicy, Reports Reader

- [ ] **2.2** `Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $false -ApproverGroup oer-s94-grp -Confirm:$false` writes `MutuallyExclusiveParameter`, sends no Graph or ARM request, and the role's policy is the same before and after.

```powershell
$Before = Get-OerLiveDirectoryRolePolicy -RoleName 'Reports Reader'
$null = Invoke-S94 -Label '2.2 Set-OERDirectoryRoleManagementPolicy' -Call { Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $false -ApproverGroup 'oer-s94-grp' -Confirm:$false -ErrorAction Continue }
$After = Get-OerLiveDirectoryRolePolicy -RoleName 'Reports Reader'
Write-OerLiveStep "2.2 Reports Reader policy: rules differing after the call: $(@(Compare-OerLivePolicyRule -Live $After.Rules -Baseline $Before.Rules).Count)"
```

**Expect:** `errors: MutuallyExclusiveParameter; Graph requests: 0 (writes: 0); ARM requests: 0`;
target `Reports Reader`; `rules differing after the call: 0`.
**Failure looks like:** any request counted; a rule differing (stop and restore it by hand from the
`Before` read before anything else).

Result:

### 2.3. Set-OERRoleManagementPolicy, Reader at oer-s94-rg

- [ ] **2.3** `Set-OERRoleManagementPolicy -Role Reader -Scope` (the `oer-s94-rg` scope) `-RequireApproval $false -ApproverGroup oer-s94-grp -Confirm:$false` writes `MutuallyExclusiveParameter` and sends no Graph or ARM request.

```powershell
$null = Invoke-S94 -Label '2.3 Set-OERRoleManagementPolicy' -Call { Set-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -RequireApproval $false -ApproverGroup 'oer-s94-grp' -Confirm:$false -ErrorAction Continue }
```

**Expect:** `errors: MutuallyExclusiveParameter; Graph requests: 0 (writes: 0); ARM requests: 0
(writes: 0)`; target `Reader`.
**Failure looks like:** any request counted.

Result:

### 2.4. The controls: -RequireApproval $false alone is not refused (under -WhatIf)

- [ ] **2.4** The same three cmdlets with `-RequireApproval $false` alone and `-WhatIf` are not refused with `MutuallyExclusiveParameter`: each reads (requests counted above 0) and writes nothing.

```powershell
$null = Invoke-S94 -Label '2.4 group, -RequireApproval $false alone' -Call { Set-OERGroupPimPolicy -Group 'oer-s94-grp' -RequireApproval $false -WhatIf -ErrorAction Continue }
$null = Invoke-S94 -Label '2.4 directory, -RequireApproval $false alone' -Call { Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -RequireApproval $false -WhatIf -ErrorAction Continue }
$null = Invoke-S94 -Label '2.4 Azure, -RequireApproval $false alone' -Call { Set-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -RequireApproval $false -WhatIf -ErrorAction Continue }
Remove-Item -Path function:Invoke-MgGraphRequest
Remove-Item -Path function:Invoke-WebRequest
Write-OerLiveStep "Fences removed: $(-not (Get-Command -Name Invoke-MgGraphRequest -CommandType Function -ErrorAction Ignore) -and -not (Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore))"
Disconnect-OerLive
```

**Expect:** no `MutuallyExclusiveParameter` on any line; the group line with Graph requests above 0
and `writes: 0` (its `What if:` line goes to the host, not counted); the directory line with Graph
requests above 0 and `writes: 0` (a `NoChange` error when approval is already off on the role); the
Azure line with ARM requests above 0 and `writes: 0` (a `NoChange` error when approval is already off
at the resource group); `Fences removed: True`.
**Failure looks like:** `MutuallyExclusiveParameter` on a line (the refusal fires without an
approver); any write.

Result:

## 3. BL-16: an empty approver list on Azure

**3.1 and 3.2 run in ONE process**, with the same fences again.

### 3.1. Set-OERRoleManagementPolicy with an empty approver list is refused

- [ ] **3.1** `Set-OERRoleManagementPolicy -Role Reader -Scope` (the `oer-s94-rg` scope) `-ApproverUser @() -Confirm:$false`, and the same with `-ApproverGroup @() -ApproverUser @('')`, each write `ApproverRequired` and send no Graph or ARM request.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s94'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$GraphMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$GraphFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($GraphMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($GraphMeta)))`nend { `$M = if ([string]`$Method) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S94GraphWrites++ }; `$global:S94GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($GraphFence))
$WebMeta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
$WebFence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($WebMeta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($WebMeta)))`nend { if ([string]`$Method -and [string]`$Method -ne 'Get') { `$global:S94ArmWrites++ }; `$global:S94ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($WebFence))
$FencesHold = ((& $Module { Get-Command -Name Invoke-MgGraphRequest }).CommandType -eq 'Function') -and
    ((& $Module { Get-Command -Name Invoke-WebRequest }).CommandType -eq 'Function')
Write-OerLiveStep "The module resolves Invoke-MgGraphRequest and Invoke-WebRequest to the fences: $FencesHold"
if (-not $FencesHold) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Invoke-S94 {
    # As in section 1: a plain call outside any try; counts, rows, warnings, error ids; never a token.
    param([string]$Label, [scriptblock]$Call)
    $global:S94GraphCalls = 0; $global:S94GraphWrites = 0; $global:S94ArmCalls = 0; $global:S94ArmWrites = 0
    $All = @(& $Call 2>&1 3>&1)
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S94GraphCalls (writes: $global:S94GraphWrites); ARM requests: $global:S94ArmCalls (writes: $global:S94ArmWrites)"
    foreach ($O in $Out) {
        if ($O.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult') {
            Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)"
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
        Write-OerLiveStep "$($Label): $(([string]$E.FullyQualifiedErrorId -split ',')[0]); category $($E.CategoryInfo.Category); target $($E.TargetObject) -- $Text"
    }
    , $Out
}
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s94-rg"
$null = Invoke-S94 -Label '3.1 -ApproverUser @()' -Call { Set-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -ApproverUser @() -Confirm:$false -ErrorAction Continue }
$null = Invoke-S94 -Label "3.1 -ApproverGroup @() -ApproverUser @('')" -Call { Set-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -ApproverGroup @() -ApproverUser @('') -Confirm:$false -ErrorAction Continue }
```

**Expect:** the identity lines `True`; the fences `True`; on both lines `output objects 0; errors:
ApproverRequired; Graph requests: 0 (writes: 0); ARM requests: 0 (writes: 0)`, category
`InvalidArgument`, target `Reader`, and the message beginning `Approval cannot be required with no
approver: -ApproverUser and -ApproverGroup name no approver`.
**Failure looks like:** any request counted; an ARM write (an empty approver list sent with approval
forced on).

Result:

### 3.2. Invoke-OERStructure -WhatIf with a declared empty approver side plans Unchanged

- [ ] **3.2** The Reader policy at `oer-s94-rg` has no approver; `Invoke-OERStructure -WhatIf` with a document declaring that policy with `approvers.groups` `[]` plans `Unchanged`, not an update, and writes nothing.

```powershell
$Live = Get-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -ErrorAction Stop
Write-OerLiveStep "3.2 the Reader policy at oer-s94-rg: approval required: $([bool]$Live.RequireApproval); approvers: $(@($Live.Approvers | Where-Object { $_ }).Count)"
$Doc = Join-Path $Raw 'apply-s94-reader.json'
$null = [System.IO.Directory]::CreateDirectory($Raw)
[System.IO.File]::WriteAllText($Doc, (@{
            version                = '1.0'
            roleManagementPolicies = @(@{ role = 'Reader'; scope = $RgScope; approvers = @{ groups = @() } })
        } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$null = Invoke-S94 -Label '3.2 Invoke-OERStructure -WhatIf' -Call { Invoke-OERStructure -Path $Doc -WhatIf }
[System.IO.File]::Delete($Doc)
Remove-Item -Path function:Invoke-MgGraphRequest
Remove-Item -Path function:Invoke-WebRequest
Write-OerLiveStep "Fences removed: $(-not (Get-Command -Name Invoke-MgGraphRequest -CommandType Function -ErrorAction Ignore) -and -not (Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore)); document deleted: $(-not (Test-Path -LiteralPath $Doc))"
Disconnect-OerLive
```

**Expect:** `approval required: False; approvers: 0`; `errors: none`; one row `roleManagementPolicies
| Reader @ ... | Unchanged | policy already matches for 'Reader' at '...'`; Graph and ARM `writes:
0`; `Fences removed: True; document deleted: True`. Before this branch the same document planned
`Skipped | would update role management policy ...` on every run (the declared `[]` was compared as
one blank approver).
**Failure looks like:** a `Skipped ... would update` row; any write.

Result:

## Teardown

### T.1. The policies are put back, the objects removed, nothing carries the prefix, and the main clone is untouched

- [ ] **T.1** `Initialize-OerS94Prereq.ps1 -Teardown -Unattended` puts the member pair of `oer-s94-grp` back to its baseline, deletes the group, finds the Reader policy at `oer-s94-rg` at its baseline and deletes the resource group; the sweep finds nothing with the prefix; the group count equals the baseline; no session is left; the main clone is on `main` at the HEAD S.1 recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS94Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
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

**Expect:** the teardown's identity lines `True`; `Teardown A: member policy of oer-s94-grp now: ...;
rules differing from the baseline: N` and, when N is above 0, each rule sent from the baseline (200 or
204) and `restored: True`; the library's step 5 deleting `oer-s94-grp`; `Teardown C: Reader policy at
oer-s94-rg at its baseline: True (rules differing before: 0)` and `deleted oer-s94-rg`; `Resource
group oer-s94-rg exists after the teardown: False`; `Counts: groups now N, at the baseline N; equal:
True`; exit code 0; no session left; the main clone on `main` at the HEAD S.1 recorded.
**Failure looks like:** exit code 1 with a `STOP` line -- a policy could not be put back: the object is
NOT deleted, and the step stops (G11.5); exit code 3 -- residue in `raw\residue.json`, which the next
prereq run retries; report each row. A group deleted with 204 can still show in the sweep for a minute
or two: read back with T.2 before judging.

Result:

### T.2. Read back, a few minutes later

- [ ] **T.2** `Initialize-OerS94Prereq.ps1 -ReadBack` finds no object with the prefix, no resource group `oer-s94-rg`, the group count equal to the baseline and no residue row.

```powershell
$VaultDir = $env:OER_LIVE_DIR
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS94Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s94-' -ConfigDirectory $VaultDir
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Read-back exit code: $Code"
```

**Expect:** `Read-back: resource group oer-s94-rg exists: False`; `Counts: groups now N, at the
baseline N; equal: True`; `Read-back: prefixed objects left: 0; unread collections: 0; residue rows:
0`; exit code 0. After the results are copied into this file: `Clear-OerLiveRedactionMap`, and
`raw\s94\` deleted.
**Failure looks like:** a prefixed object or a residue row -- report it in the step's report.

Result:
