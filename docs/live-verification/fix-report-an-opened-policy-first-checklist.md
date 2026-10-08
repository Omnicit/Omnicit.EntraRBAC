# Live verification checklist -- an opened policy is always reported (fix/report-an-opened-policy-first)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates a disabled user
`oer-s102-user` and two plain security groups with no member, `oer-s102-cmd` and `oer-s102-eng`.
Before its first write it records baselines: the tenant's user and group counts, and the member PIM
policy of each group. It then brings each member policy to the starting state: eligible assignments
must expire, so a PERMANENT eligibility has to open the policy first. Section 1 makes `oer-s102-user`
permanently eligible in `oer-s102-cmd` with `Add-OERGroupEligibility`, which opens that group's
policy; closes the policy again with the module's own advice; and then asks for a permanent
eligibility of a made-up principal id, which opens the policy and is refused by Microsoft Graph,
twice (with and without `-ErrorAction Stop`), closing the policy after each. Section 2 does the same
through `Invoke-OERStructure` on `oer-s102-eng`. The teardown removes the eligibility, puts both
member policies back to their baselines and removes every prefixed object through OerLive's fixed
order. No directory role, no other group's policy and no Azure resource is touched.

**The made-up principal id.** `00000000-0000-0000-0000-000000000099` names no object in any tenant:
it is the placeholder register's slot for a deliberately non-existent object id
([README.md](README.md), "The placeholder register"). It is sent as it is, so Microsoft Graph has a
grant to refuse; OerLive's redactor leaves a placeholder-shaped id alone and never hands out `...099`.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop. Neither `oer-live-cc` nor `oer-live-cc-noperm` is ever a principal here.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive -Arm`, which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False, and every
block installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s102/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s102\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-98: `Add-OERGroupEligibility` reports the opened policy FIRST.** A permanent grant opens the
  group's PIM-for-Groups policy first when it does not allow permanent eligibility. When Microsoft
  Graph then refused the grant, the cmdlet wrote the grant's own error first and
  `PolicyOpenedButGrantFailed`, with the advice on the open policy, after it -- so under
  `-ErrorAction Stop`, which the apply engine always uses, the advice was never written. Now
  `PolicyOpenedButGrantFailed` comes first, with the advice and the reason the request failed in its
  message, and the grant's own error after it. The engine's Failed row carries the same message.
- **B. Ruling R1: the advice names a command that closes the policy.** The advice used to say
  `Set-OERGroupPimPolicy -Group ... -AccessType ... -ActivationMaxHours <n>` "(without
  -AllowPermanentEligibility)", which never touches the eligibility-expiration rule and so leaves the
  policy open. It now says `-AllowPermanentEligibility:$false`, in one place
  (`Get-OERGroupPimPolicyCloseAdvice`) for the cmdlet and the engine.
- **C. BL-51: a new group's `GroupNotOnboarded` says whether the policy was opened.** When the engine
  gives up on a permanent eligibility for a group it created in the same run, the message now says
  whether the group's policy was opened for it, and how to close it; a policy read that fails says it
  MAY have been opened, never that it was not.
- **D. BL-99: a rollback answered `NoChange` is not a failed rollback.** `New-OERActiveRoleAssignment`
  and `New-OEREligibleRoleAssignment` said "The rollback ALSO failed, so the policy is still open" also
  when the policy had been closed again by someone else; decided on the error id, they now say that it
  already disallowed permanent assignments. The help of `Add-OERGroupEligibility` says which error is a
  refusal (`PolicyOpenedButGrantFailed`) and which an accepted request answered Failed
  (`EligibilityRequestFailed`).

A live tenant is needed for what the unit tests stub: the real refusal Microsoft Graph gives after a
real policy open, and the order in which a script with no `try` sees the errors under
`-ErrorAction Stop` (1.3, 1.4); the engine's Failed row built from that real refusal (2.4); that the
advice really closes the policy (1.2 and after each refusal); and that the success path still opens
the policy and grants, for the cmdlet (1.1) and for the engine, converging on a second run (2.1, 2.2,
G8).

## What this file does not check, and why

- **C, `GroupNotOnboarded` for a group created in the same run (class B, G9).** It needs Microsoft
  Graph to keep a new group's policy unlisted, or its requests answered Failed, for the whole 30-second
  wait, which cannot be produced on demand. Proved offline in
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (one test per outcome: no request sent; the
  policy not allowing permanent eligibility after the requests; a closed read where the run's own
  first request would have opened it -- "that read may be out of date"; already allowing it before
  them; opened by them; open with the state before not known; and a read after the requests that
  fails or finds nothing -- "may have been opened"). Out of reach live as well: a later attempt that
  is refused after an earlier one opened the policy ends the entry before that read (reported as a
  finding of this step, not changed by it).
- **D, the `NoChange` rollback text (class B).** It needs someone else to close an Azure role
  management policy between this command's open and its rollback, inside one call, after Azure
  Resource Manager refused the grant. Proved offline in `tests/Unit/Public/New-OERActiveRoleAssignment.Tests.ps1`
  and `tests/Unit/Public/New-OEREligibleRoleAssignment.Tests.ps1`, including a run of the real
  `Set-OERRoleManagementPolicy` against a policy that already disallows permanent assignments, and the
  decision taken on the error id rather than the message.
- **An accepted request answered with a status in the Failed family after an open (class B).** That
  path (`EligibilityRequestFailed` with the same advice) is unchanged in its order by this branch;
  Microsoft Graph cannot be made to accept and fail a request on demand. Its message now carries the
  corrected advice; proved offline in `tests/Unit/Public/Add-OERGroupEligibility.Tests.ps1`.
- **Owner access.** The same code path as member access with another access type; only member access
  is run.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **prerequisite script** `Initialize-OerS102Prereq.ps1` beside OerLive (outside the repository).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
advice runner, the state readers and the documents. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s102-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s102'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$UserUpn = "oer-s102-user@$($Cfg.UserDomain)"
# A made-up principal id that names no object: the placeholder register's slot for a non-existent id.
$Missing = '00000000-0000-0000-0000-000000000099'

function Start-S102NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt. A global proxy of Get-AzToken, which the module calls
    # unqualified, forwards only a request that carries -ClientCertificate.
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S102 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S102Fence {
    # Counts every Graph request the module sends that is not a read, through a global proxy of
    # Invoke-MgGraphRequest: the module's transport calls it unqualified, so the proxy is what it reaches.
    $global:S102Writes = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$M = if (`$PSBoundParameters.ContainsKey('Method')) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S102Writes.Add(`$M) }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S102Fence {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    if (Test-Path -Path function:Invoke-MgGraphRequest) { Remove-Item -Path function:Invoke-MgGraphRequest }
}

function Get-S102Policy {
    # The group's member PIM-for-Groups policy as the module reads it.
    param([Parameter(Mandatory)][string]$Name)
    Get-OERGroupPimPolicy -Group $Name -AccessType member -ErrorAction Stop
}

function Get-S102PolicyText {
    param([Parameter(Mandatory)][object]$Policy)
    "permanent eligibility allowed: $($Policy.AllowPermanentEligibility); eligible maximum: $($Policy.EligibleDuration); activation maximum hours: $($Policy.ActivationMaxHours)"
}

function Get-S102EligibilityText {
    # The direct eligibility of the group, per principal: the test user, the made-up id, anything else.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$UserId)
    $E = @(Get-OERGroupEligibility -Group $Name -ErrorAction Stop | Where-Object { $null -ne $_ })
    $U = @($E | Where-Object { [string]$_.PrincipalId -eq $UserId })
    "eligibility of oer-s102-user: $($U.Count) (permanent: $(@($U | Where-Object { -not $_.EndDateTime }).Count)); of the made-up id: $(@($E | Where-Object { [string]$_.PrincipalId -eq $Missing }).Count); of anyone else: $(@($E | Where-Object { [string]$_.PrincipalId -notin @($UserId, $Missing) }).Count)"
}

function Get-S102UserId {
    [string](Invoke-OerLiveGraph -Uri "v1.0/users/$([uri]::EscapeDataString($UserUpn))?`$select=id").Body['id']
}

function Get-S102Advice {
    # The module's OWN close advice for the group (its single owner, a private function), and the
    # command inside it: the text between 'close it with ' and ' if you do not intend to retry.' is one
    # single-quoted PowerShell string literal, so its doubled quotes are undone by parsing it as one.
    param([Parameter(Mandatory)][string]$GroupId)
    $Text = & (Get-Module -Name Omnicit.EntraRBAC) { param($G) Get-OERGroupPimPolicyCloseAdvice -GroupId $G -AccessType member } $GroupId
    $M = [regex]::Match([string]$Text, "^close it with ('(?:[^']|'')*') if you do not intend to retry\.$")
    $Command = if ($M.Success) { [string][scriptblock]::Create($M.Groups[1].Value).InvokeReturnAsIs() } else { $null }
    [PSCustomObject]@{ Text = [string]$Text; Command = $Command }
}

function Invoke-S102Close {
    # Runs the module's advice for a group exactly as it reads (plus -Confirm:$false), then reads the
    # policy until it no longer allows permanent eligibility.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Label)
    $Before = Get-S102Policy -Name $Name
    $A = Get-S102Advice -GroupId ([string]$Before.GroupId)
    Write-OerLiveStep "$Label advice: $($A.Text)"
    Write-OerLiveStep "$Label policy before the advice: $(Get-S102PolicyText -Policy $Before)"
    if (-not $A.Command) { Write-OerLiveStep "$Label the advice holds no command; nothing was run."; return }
    $Out = @(& ([scriptblock]::Create("$($A.Command) -Confirm:`$false -ErrorAction Stop")))
    Write-OerLiveStep "$Label the advice ran: objects returned $($Out.Count)"
    $Wait = Wait-OerLiveConverged -Activity "$Name's member policy no longer allows permanent eligibility" -Read { Get-S102Policy -Name $Name } -Test { $args[0].AllowPermanentEligibility -eq $false }
    Write-OerLiveStep "$Label policy after the advice ($($Wait.Attempts) read(s)): $(Get-S102PolicyText -Policy $Wait.Value); eligible maximum unchanged: $([string]$Wait.Value.EligibleDuration -eq [string]$Before.EligibleDuration); activation maximum unchanged: $($Wait.Value.ActivationMaxHours -eq $Before.ActivationMaxHours)"
}

function Write-S102Error {
    # One error record as a line: its id, category, target and message (redacted by Write-OerLiveStep).
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Record)
    if ($Record -isnot [System.Management.Automation.ErrorRecord]) { Write-OerLiveStep "$Label error (not an ErrorRecord): $($Record.GetType().Name): $([string]$Record.Message)"; return }
    Write-OerLiveStep "$Label error: $([string]$Record.FullyQualifiedErrorId) ($($Record.CategoryInfo.Category), target '$([string]$Record.TargetObject)'): $([string]$Record.Exception.Message)"
}

function Get-S102Document {
    # The engine's document: oer-s102-eng with ONE permanent member eligibility (no durationDays), of the
    # given principal -- oer-s102-user's UPN for the success path, the made-up id for the refusal.
    param([Parameter(Mandatory)][string]$Principal)
    [ordered]@{
        version = '1.0'
        groups  = @([ordered]@{ displayName = 'oer-s102-eng'; eligibility = @([ordered]@{ principal = $Principal; accessType = 'member' }) })
    } | ConvertTo-Json -Depth 10
}

function Write-S102Rows {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)
    foreach ($R in $Rows) {
        if ($R.PSObject.Properties['Action']) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
        else { Write-OerLiveStep "$Label object: $($R.PSObject.TypeNames[0])" }
    }
}

function Test-S102Advice {
    # Whether a message carries the opened policy, the corrected advice and the cause, in that order.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    $Opened = $Message.IndexOf('had been opened to allow permanent eligibility. The policy is still open; close it with ', [System.StringComparison]::Ordinal)
    $Advice = $Message.IndexOf("-AccessType member -AllowPermanentEligibility:`$false' if you do not intend to retry.", [System.StringComparison]::Ordinal)
    $Cause = $Message.IndexOf(' The request failed with: ', [System.StringComparison]::Ordinal)
    "opened policy named: $($Opened -ge 0); corrected advice: $($Advice -gt $Opened); cause after the advice: $($Cause -gt $Advice -and $Advice -ge 0)"
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Has = { param($Text) [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Text -Quiet) }
Write-OerLiveStep "The worktree's build carries A: $(& $Has '$PolicyStillOpenAdvice The request failed with:'); B: $(& $Has 'function Get-OERGroupPimPolicyCloseAdvice'); C: $(& $Has 'could not be read afterwards'); D: $(& $Has 'already disallowed permanent assignments again')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.2); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True; D: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result:

### 0.2. The prerequisite plan names only oer-s102- objects

- [ ] **0.2** `Initialize-OerS102Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every tenant `What if:` target starts with `oer-s102-`.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS102Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baselines) go to raw\s102\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s102\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s102\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s102\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s102-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s102-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own local files under `raw\s102\` (the transcript and, on a first run, the count baseline);
the tenant targets `oer-s102-user`, `oer-s102-cmd` and `oer-s102-eng`, every one starting with
`oer-s102-` (`True`); a "No member-policy baseline" line for each group, since under `-WhatIf` the
groups do not exist yet.
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run.

Result:

### 0.3. The prerequisite objects, the baselines and the starting state

- [ ] **0.3** `Initialize-OerS102Prereq.ps1 -Unattended` writes the count baseline, creates the user and the two groups, records each group's member-policy baseline and brings each policy to the starting state (eligible assignments must expire).

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS102Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $LASTEXITCODE"
```

**Expect:** the identity check passes; `Created user oer-s102-user (disabled)`, `Created group
oer-s102-cmd`, `Created group oer-s102-eng`; a baseline line for each member policy; for each group
either `already at the checklist's starting state` or `Sent rule Expiration_Admin_Eligibility` and
`at the starting state: True`, with `eligible assignments must expire: True`; `Exit code: 0`.
**Failure looks like:** exit code `1` -- read the `Stopped` line; a policy that does not converge on
the starting state -- the checklist cannot open it, so stop and tear down.

Result:

### 0.4. The starting state as the module reads it

- [ ] **0.4** The module reads both member policies as not allowing permanent eligibility, and neither group holds an eligibility.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$UserId = Get-S102UserId
foreach ($Name in 'oer-s102-cmd', 'oer-s102-eng') {
    Write-OerLiveStep "0.4 $($Name): $(Get-S102PolicyText -Policy (Get-S102Policy -Name $Name)); $(Get-S102EligibilityText -Name $Name -UserId $UserId)"
}
Disconnect-OerLive
```

**Expect:** for each group `permanent eligibility allowed: False`, an eligible maximum, and
`eligibility of oer-s102-user: 0 (permanent: 0); of the made-up id: 0; of anyone else: 0`.
**Failure looks like:** `permanent eligibility allowed: True` -- the starting state did not take; a
read error -- a group created moments ago, so wait a minute and run 0.4 again.

Result:

## 1. The cmdlet: Add-OERGroupEligibility on oer-s102-cmd (A, B)

### 1.1. A refused grant after an open, under -ErrorAction Stop, in a script with no try

- [ ] **1.1** `Add-OERGroupEligibility -Group oer-s102-cmd -PrincipalId` with the made-up id and `-ErrorAction Stop`, the last statement that runs in a script with no `try`, warns, opens the policy, is refused by Microsoft Graph, and stops the script with `PolicyOpenedButGrantFailed`, whose message names the opened policy, gives the corrected advice and then the reason the request failed.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
Write-OerLiveStep "1.1 policy before: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-cmd'))"
Write-OerLiveStep '1.1 the next call is the last statement that runs: no try stands around it, it runs with -ErrorAction Stop, and the line after it says REACHED.'
$ErrorView = 'NormalView'
Add-OERGroupEligibility -Group 'oer-s102-cmd' -PrincipalId $Missing -Confirm:$false -ErrorAction Stop
Write-OerLiveStep '1.1 REACHED: the script went on after the call.'
```

**Expect:** `permanent eligibility allowed: False` before; the warning `This eligibility requires
opening the PIM-for-groups policy for group '...' (member access) ...`; NO `REACHED` line; the
script's exit code `1`; on standard error ONE error, whose `FullyQualifiedErrorId` is
`PolicyOpenedButGrantFailed,Add-OERGroupEligibility`, category `InvalidOperation`, and whose message
reads `The PIM member eligibility grant failed after PIM-for-groups policy '...' had been opened to
allow permanent eligibility. The policy is still open; close it with 'Set-OERGroupPimPolicy -Group
''...'' -AccessType member -AllowPermanentEligibility:$false' if you do not intend to retry. The
request failed with: ` followed by Microsoft Graph's refusal. The grant's own error is not on
standard error: the first error stopped the script.
**Failure looks like:** the grant's own error is the one that stopped the script and the advice is
nowhere -- the old order (BL-98 not fixed); a `REACHED` line -- the script went on past a stop; an
`EligibilityRequestFailed` and an object -- Microsoft Graph ACCEPTED the request for a principal that
does not exist and answered it Failed, so the refusal cannot be produced here and A is class B
(record what Graph answered, and close the policy with 1.2 before going on); a `PolicyOpenFailed` --
the open itself was refused (a 403 is a STOP).

Result:

### 1.2. The policy 1.1 opened is open, nothing was granted, and the module's advice closes it

- [ ] **1.2** After 1.1 the member policy of `oer-s102-cmd` allows permanent eligibility and no eligibility was created; running the module's own advice, exactly as it reads, closes it again without changing the eligible or the activation maximum.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$UserId = Get-S102UserId
Write-OerLiveStep "1.2 $(Get-S102EligibilityText -Name 'oer-s102-cmd' -UserId $UserId)"
Invoke-S102Close -Name 'oer-s102-cmd' -Label '1.2'
Disconnect-OerLive
```

**Expect:** `eligibility of oer-s102-user: 0 (permanent: 0); of the made-up id: 0; of anyone else:
0`; the advice `close it with 'Set-OERGroupPimPolicy -Group ''...'' -AccessType member
-AllowPermanentEligibility:$false' if you do not intend to retry.`; the policy before the advice
`permanent eligibility allowed: True` (1.1 opened it); `the advice ran`; after it `permanent
eligibility allowed: False`, `eligible maximum unchanged: True`, `activation maximum unchanged: True`.
**Failure looks like:** `permanent eligibility allowed: True` after the advice, or a wait that runs
out -- the advice does not close the policy (Ruling R1 wrong); a changed maximum -- the advice
rewrites more than it says.

Result:

### 1.3. The same refusal without -ErrorAction Stop: both errors, the opened policy first

- [ ] **1.3** Without `-ErrorAction Stop` the same call writes two errors in this order -- `PolicyOpenedButGrantFailed` with the advice and the cause, then the grant's own error -- emits no object and the script goes on; the module's advice then closes the policy again.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
Write-OerLiveStep "1.3 policy before: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-cmd'))"
$Err = @()
$Out = @(Add-OERGroupEligibility -Group 'oer-s102-cmd' -PrincipalId $Missing -Confirm:$false -ErrorAction Continue -ErrorVariable Err 2>$null)
$Records = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "1.3 objects: $($Out.Count); error records: $($Records.Count) (other items in -ErrorVariable: $(@($Err).Count - $Records.Count))"
$I = 0
foreach ($E in $Records) { $I++; Write-S102Error -Label "1.3 [$I]" -Record $E }
if ($Records.Count -ge 1) { Write-OerLiveStep "1.3 [1] $(Test-S102Advice -Message ([string]$Records[0].Exception.Message))" }
if ($Records.Count -ge 2) { Write-OerLiveStep "1.3 [1] quotes [2]'s message as its cause: $(([string]$Records[0].Exception.Message).EndsWith(' The request failed with: ' + [string]$Records[1].Exception.Message, [System.StringComparison]::Ordinal))" }
Write-OerLiveStep '1.3 REACHED: the script went on, as it does without -ErrorAction Stop.'
Invoke-S102Close -Name 'oer-s102-cmd' -Label '1.3'
Disconnect-OerLive
```

**Expect:** `permanent eligibility allowed: False` before; `objects: 0; error records: 2`; `[1]` is
`PolicyOpenedButGrantFailed,Add-OERGroupEligibility (InvalidOperation, target 'Group_...')` and
`opened policy named: True; corrected advice: True; cause after the advice: True`; `[2]` is the
grant's own record with Microsoft Graph's code; `[1] quotes [2]'s message as its cause: True`; the
`REACHED` line; then the advice closes the policy (`permanent eligibility allowed: False`, both
maxima unchanged).
**Failure looks like:** `[1]` is the grant's own error -- the old order; a `False` in the advice line;
the second error missing -- the grant's own error is no longer re-published.

Result:

### 1.4. The success path still opens the policy and grants (regression)

- [ ] **1.4** `Add-OERGroupEligibility -Group oer-s102-cmd -User oer-s102-user` (permanent) warns, opens the policy, emits the request object with a status that is not in the Failed family, writes no error, and the user is then permanently eligible.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$UserId = Get-S102UserId
Write-OerLiveStep "1.4 policy before: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-cmd'))"
$Err = @()
$Warn = @()
$Out = @(Add-OERGroupEligibility -Group 'oer-s102-cmd' -User $UserUpn -Confirm:$false -ErrorAction Continue -ErrorVariable Err -WarningVariable Warn 2>$null 3>$null)
foreach ($W in $Warn) { Write-OerLiveStep "1.4 warning: $W" }
foreach ($O in $Out) { Write-OerLiveStep "1.4 object: $($O.PSObject.TypeNames[0]); status $($O.Status); action $($O.Action)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-S102Error -Label '1.4' -Record $E }
Write-OerLiveStep "1.4 objects: $($Out.Count); errors: $(@($Err).Count); warnings: $($Warn.Count)"
$Wait = Wait-OerLiveConverged -Activity 'oer-s102-user is permanently eligible in oer-s102-cmd' -Read { Get-S102EligibilityText -Name 'oer-s102-cmd' -UserId $UserId } -Test { $args[0] -like 'eligibility of oer-s102-user: 1 (permanent: 1);*' }
Write-OerLiveStep "1.4 $($Wait.Value)"
Write-OerLiveStep "1.4 policy after: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-cmd'))"
Disconnect-OerLive
```

**Expect:** `permanent eligibility allowed: False` before; one warning `This eligibility requires
opening the PIM-for-groups policy for group '...' (member access) to allow PERMANENT eligible
assignments, which affects ALL member eligibility for this group.`; one object
`Omnicit.EntraRBAC.GroupEligibility` with status `Provisioned` (or another status outside the Failed
family) and action `adminAssign`; `errors: 0`; then `eligibility of oer-s102-user: 1 (permanent: 1)`
and `permanent eligibility allowed: True`.
**Failure looks like:** a `PolicyOpenedButGrantFailed` or `EligibilityRequestFailed` -- the success
path regressed (or, for a group created minutes ago, Microsoft Graph does not know it yet: wait
five minutes and run 1.4 again, recording both runs).

Result:

## 2. The engine: Invoke-OERStructure on oer-s102-eng (A)

### 2.1. A refused grant after an open: the engine's Failed row carries the advice

- [ ] **2.1** `Invoke-OERStructure` with a document declaring a permanent member eligibility of the made-up id on `oer-s102-eng` warns, opens the policy and reports ONE `Failed` row whose Detail carries `PolicyOpenedButGrantFailed`'s message -- the opened policy, the corrected advice and the cause -- with that record as the row's error.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
Write-OerLiveStep "2.1 policy before: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-eng'))"
$Err = @()
$Warn = @()
$Rows = @(Invoke-OERStructure -Json (Get-S102Document -Principal $Missing) -Confirm:$false -ErrorAction Continue -ErrorVariable Err -WarningVariable Warn 2>$null 3>$null)
foreach ($W in $Warn) { Write-OerLiveStep "2.1 warning: $W" }
Write-S102Rows -Label '2.1' -Rows $Rows
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-S102Error -Label '2.1' -Record $E }
$Failed = @($Rows | Where-Object { $_.PSObject.Properties['Action'] -and $_.Action -eq 'Failed' })
Write-OerLiveStep "2.1 Failed rows: $($Failed.Count); errors: $(@($Err).Count); warnings: $($Warn.Count)"
if ($Failed.Count -eq 1) {
    Write-OerLiveStep "2.1 the Failed row's Detail: $(Test-S102Advice -Message ([string]$Failed[0].Detail))"
    Write-OerLiveStep "2.1 the Failed row's error: $(([string]$Failed[0].Error.FullyQualifiedErrorId -split ',')[0])"
}
Disconnect-OerLive
```

**Expect:** `permanent eligibility allowed: False` before; the one permanent-eligibility warning; a
`Failed` row `failed to add permanent eligibility for '00000000-0000-0000-0000-000000000099': The PIM
member eligibility grant failed after PIM-for-groups policy '...' had been opened ...`; `Failed rows:
1`; `opened policy named: True; corrected advice: True; cause after the advice: True`; the row's error
`PolicyOpenedButGrantFailed`; in `-ErrorVariable` the `PolicyOpenedButGrantFailed` record and no
record of the grant's own (the engine calls the cmdlet with `-ErrorAction Stop`).
**Failure looks like:** the Detail carries only Microsoft Graph's refusal and no advice -- the old
order (BL-98 not fixed in the engine's view); more than one Failed row.

Result:

### 2.2. The policy 2.1 opened is open, nothing was granted, and the module's advice closes it

- [ ] **2.2** After 2.1 the member policy of `oer-s102-eng` allows permanent eligibility and no eligibility was created; the module's advice closes it again.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$UserId = Get-S102UserId
Write-OerLiveStep "2.2 $(Get-S102EligibilityText -Name 'oer-s102-eng' -UserId $UserId)"
Invoke-S102Close -Name 'oer-s102-eng' -Label '2.2'
Disconnect-OerLive
```

**Expect:** as 1.2, for `oer-s102-eng`.
**Failure looks like:** as 1.2.

Result:

### 2.3. The success path still opens the policy and grants (regression)

- [ ] **2.3** `Invoke-OERStructure` with a document declaring a permanent member eligibility of `oer-s102-user` on `oer-s102-eng` warns once, reports `Updated` for it, writes no error, and the user is then permanently eligible; the state then reads the same three times, 5 s apart.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
$UserId = Get-S102UserId
Write-OerLiveStep "2.3 policy before: $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-eng'))"
Start-S102Fence
$Err = @()
$Warn = @()
$Rows = @(Invoke-OERStructure -Json (Get-S102Document -Principal $UserUpn) -Confirm:$false -ErrorAction Continue -ErrorVariable Err -WarningVariable Warn 2>$null 3>$null)
Stop-S102Fence
foreach ($W in $Warn) { Write-OerLiveStep "2.3 warning: $W" }
Write-S102Rows -Label '2.3' -Rows $Rows
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-S102Error -Label '2.3' -Record $E }
Write-OerLiveStep "2.3 rows: $(@($Rows | ForEach-Object { $_.Action }) -join ', '); errors: $(@($Err).Count); warnings: $($Warn.Count); Graph writes: $($global:S102Writes.Count) ($(@($global:S102Writes) -join ', '))"
# G8 waits for a state that reads the same three times, 5 s apart (Sprint 9 step 2).
$State = { "$(Get-S102EligibilityText -Name 'oer-s102-eng' -UserId $UserId); $(Get-S102PolicyText -Policy (Get-S102Policy -Name 'oer-s102-eng'))" }
$Wait = Wait-OerLiveConverged -Activity 'oer-s102-user is permanently eligible in oer-s102-eng' -Read { & $State } -Test { $args[0] -like 'eligibility of oer-s102-user: 1 (permanent: 1);*permanent eligibility allowed: True*' }
$Steady = @(1..3 | ForEach-Object { Start-Sleep -Seconds 5; & $State })
Write-OerLiveStep "2.3 state after $($Wait.Attempts) read(s): $($Wait.Value)"
Write-OerLiveStep "2.3 three reads 5 s apart agree: $(@($Steady | Select-Object -Unique).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** `permanent eligibility allowed: False` before; one warning (the permanent-eligibility
one); the rows `Unchanged` (group properties) and `Updated` (`set permanent member eligibility for
'oer-s102-user@...'`); `errors: 0`; Graph writes for the opened rule and the eligibility request (a
PATCH and a POST); then `eligibility of oer-s102-user: 1 (permanent: 1)`, `permanent eligibility
allowed: True`, and three reads that agree (`True`).
**Failure looks like:** a `Failed` row -- read its Detail; for a group created minutes ago Microsoft
Graph may not know it yet: wait five minutes and run 2.3 again, recording both runs.

Result:

### 2.4. The same document again: only Unchanged, no warning, nothing written (G8)

- [ ] **2.4** A second real run of the 2.3 document reports only `Unchanged`, writes no warning and sends no Graph write.

```powershell
Connect-OerLive -Arm
Start-S102NoPrompt
Start-S102Fence
$Err = @()
$Warn = @()
$Rows = @(Invoke-OERStructure -Json (Get-S102Document -Principal $UserUpn) -Confirm:$false -ErrorAction Continue -ErrorVariable Err -WarningVariable Warn 2>$null 3>$null)
Stop-S102Fence
Write-S102Rows -Label '2.4' -Rows $Rows
Write-OerLiveStep "2.4 rows: $(@($Rows | ForEach-Object { $_.Action }) -join ', '); errors: $(@($Err).Count); warnings: $($Warn.Count); Graph writes: $($global:S102Writes.Count)"
Disconnect-OerLive
```

**Expect:** `rows: Unchanged, Unchanged` (group properties; the permanent eligibility already
matches); `errors: 0; warnings: 0; Graph writes: 0`.
**Failure looks like:** an `Updated` row -- the second run does not converge (G8); a warning -- the
engine plans an open that is not needed.

Result:

## Teardown

### T.1. The eligibility removed, the policies put back, the objects removed, nothing carries the prefix

- [ ] **T.1** `Initialize-OerS102Prereq.ps1 -Teardown -Unattended` removes the two eligibility schedules, puts both member policies back to their baselines, removes the user and the two groups, finds nothing with the prefix and the counts back at the baseline.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS102Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Exit code: $LASTEXITCODE"
```

**Expect:** `Teardown A` removes one direct eligibility schedule in each group (none for the made-up
id); `Teardown B` reports, per group, which rules differ from the baseline and `restored: True` where
one was sent; OerLive's teardown deletes the two groups and the user; the sweep finds nothing with
the prefix; the user and group counts equal the baseline; `Exit code: 0`.
**Failure looks like:** a `STOP` line -- a policy could not be put back, so its group was not deleted;
`Exit code: 3` -- residue, named on its `RESIDUE` line; a count that differs -- name the object.

Result:

### T.2. Read back, a few minutes later

- [ ] **T.2** A few minutes after T.1, `-ReadBack` finds nothing with the prefix and no residue, the counts equal the baseline, and the main clone is still on `main` at the HEAD S.1 recorded.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS102Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts `equal:
True`; the main clone on `main` at the HEAD S.1 recorded.
**Failure looks like:** a prefixed object listed -- a deletion that has not replicated yet; run T.2
again a few minutes later before treating it as residue.

Result:
