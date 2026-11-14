# Live verification checklist -- the confirmation prompt in a background job (fix/confirmation-in-a-background-job)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. It creates no object and sends no write: every
check runs with a request fence in the module's scope that refuses every Microsoft Graph and Azure
Resource Manager request that writes, and a token fence that refuses every token request after the
sign-in. The document names a group `oer-s191-absent` that does not exist, so a plan reports it as a
group it would create and a refused run touches nothing. `oer-s191-` is the step's prefix; nothing is
created with it, so there is no prerequisite script and no teardown of objects.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The decision** (`fix: refuse the confirmation prompt in a local background job`).
  `Test-OERHostCanConfirm` now also answers that the host cannot ask a person in a background job
  (`Start-Job`): the host `ServerRemoteHost` in a `pwsh` started as a job server (`pwsh -s`), read through
  the new private `Test-OERProcessServerMode`. `Invoke-OERStructure` then refuses a run that would prompt
  with `ConfirmationUnavailable` before it signs in. A job's prompt went to the host that runs
  `Receive-Job`, where piped input answered it.
- **B. The failure row** (`fix: count the RemoteException a background job's confirmation prompt raises`).
  `Test-OERConfirmPromptFailure` also counts the `RemoteException` such a prompt raises when the receiver
  cannot answer; it is reached only when the refusal in A is not.
- **Why live:** the unit tests run the refusal in a real `Start-Job` with every sign-in and transport
  stubbed. Only a live run shows that a job that has really signed in as the test identity, with the
  worktree's build, is refused before any request, also when the receiver's input holds `y`, and that the
  plan (`-WhatIf`) still runs in the same job.

## What this file does not check, and why

- **A remote session** (`Enter-PSSession`, `Invoke-Command`) (class B): WinRM and SSH do not answer on the
  machine that runs this file, and enabling either changes a system setting. The unit tests hold that a
  `pwsh` started for SSH remoting (`-sshs`) and a runspace attached over a named pipe answer `$true`, and
  the rationale (`#confirmation-unavailable`) records the Learn pages for WinRM.
- **B. The failure row** (class B): it needs a prompt the refusal did not foresee; the unit tests drive it
  with a real job received in `pwsh -NonInteractive` and with its input at its end.
- **A real write with `-Confirm:$false`** (class B): the refusal is decided before the sign-in and does
  not reach a handler; the unit tests run `-Confirm:$false`, `-WhatIf` and `$ConfirmPreference = 'None'`
  past it in a real job, and no write path changed.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.

**Run every numbered block in its OWN PowerShell process, after the helpers block H.1** (the runner
prepends H.1 to every block), with its standard output and standard error redirected through the
redactor and its standard input redirected, holding the line `y` and then closed. That process is the
receiver: it starts a background job (`Start-Job`) that signs in and runs the checks, and receives it with
`Receive-Job`, so a prompt the job still asked would be passed to the receiver and answered Yes from its
input (the 2026-11-14 measurement); the fences stop any write all the same. The launch line of each block
is named in its check.

### H.1. The helpers every check uses

- [x] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s191-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
# The job runs in its own process: it loads OerLive and the configuration again, signs in there, puts the
# fences in the module's scope there, and prints only booleans, ids and counts.
$S191Job = {
    param([string]$VaultDir, [string]$Repo, [string]$Mode)
    Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
    $Cfg = Import-OerLiveConfig -Prefix 'oer-s191-' -ConfigDirectory $VaultDir
    $Cfg.Repo = $Repo
    $Doc = '{ "version": "1.0", "groups": [ { "displayName": "oer-s191-absent", "description": "oer-s191 live check; never created" } ] }'
    Connect-OerLive -Arm
    $M = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S191 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $M { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $M {
        $script:S191Graph = [System.Collections.Generic.List[string]]::new()
        $script:S191Arm = [System.Collections.Generic.List[string]]::new()
        $script:S191RealGraph = ${function:Invoke-OERGraphRequest}
        $script:S191RealArm = ${function:Invoke-OERArmRequest}
        # Counts every request by its method; refuses every one that writes. The address is never kept.
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $script:S191Graph.Add($Method)
            $IsRead = ($Method -eq 'GET') -or ($Method -eq 'POST' -and $Uri -match 'directoryObjects/getByIds|getMemberGroups|checkMember')
            if (-not $IsRead) { throw "S191 fence: a $Method request was refused; this file writes nothing." }
            & $script:S191RealGraph @PSBoundParameters
        }
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All, [switch]$RequireValue)
            $script:S191Arm.Add($Method)
            if ($Method -ne 'GET') { throw "S191 fence: a $Method request was refused; this file writes nothing." }
            & $script:S191RealArm @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fences in place: $((& $M { ((Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S191 fence') -and ((Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S191 fence') }))"
    $Answers = & $M { '{0}|{1}' -f (Test-OERProcessServerMode), (Test-OERHostCanConfirm) }
    $Parts = $Answers.Split('|')
    Write-OerLiveStep ('job: host {0}, sender info set {1}, started as a job server {2}, can confirm {3}' -f $Host.Name, ($null -ne $PSSenderInfo), $Parts[0], $Parts[1])
    $Count = { & $M { 'graph requests {0} (writes {1}), arm requests {2} (writes {3})' -f $script:S191Graph.Count, @($script:S191Graph | Where-Object { $_ -ne 'GET' }).Count, $script:S191Arm.Count, @($script:S191Arm | Where-Object { $_ -ne 'GET' }).Count } }
    $Show = {
        param([string]$Label, $Err, $Rows)
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-OERStructure' })
        $Ids = if ($Own.Count) { (@($Own | ForEach-Object { (([string]$_.FullyQualifiedErrorId) -split ',')[0] }) -join ' ') } else { 'none' }
        $RowText = if (@($Rows).Count) { (@($Rows | ForEach-Object { '{0}|{1}|{2}' -f $_.Section, $_.Item, $_.Action }) -join '; ') } else { 'none' }
        Write-OerLiveStep ('{0}: own records {1} ({2}), rows {3} [{4}], {5}' -f $Label, $Own.Count, $Ids, @($Rows).Count, $RowText, (& $Count))
    }
    & $M { $script:S191Graph.Clear(); $script:S191Arm.Clear() }
    $Err = $null
    $Rows = @(Invoke-OERStructure -Json $Doc -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    & $Show 'run' $Err $Rows
    & $M { $script:S191Graph.Clear(); $script:S191Arm.Clear() }
    $Err = $null
    $Rows = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    & $Show 'plan' $Err $Rows
    Write-OerLiveStep "The plan would create the prefixed group: $(@($Rows | Where-Object { $_.Item -ceq 'oer-s191-absent' -and $_.Action -eq 'Skipped' -and [string]$_.Detail -ceq 'would create group oer-s191-absent' }).Count -eq 1)"
    Disconnect-OerLive
}
function Invoke-S191Job {
    # The receiver: starts the job, waits for it with a bound, and receives it here, whose input holds y.
    Write-OerLiveStep ('receiver: host {0}, standard input redirected {1}' -f $Host.Name, [System.Console]::IsInputRedirected)
    $Job = Start-Job -ScriptBlock $S191Job -ArgumentList $VaultDir, $Cfg.Repo, 'live'
    try {
        # Wait-Job stops with an error on a job that waits at a prompt (Blocked); the state is what counts.
        try { $null = Wait-Job -Job $Job -Timeout 300 -ErrorAction Stop } catch { Write-OerLiveStep "the wait stopped with an error: $($PSItem.FullyQualifiedErrorId)" }
        Write-OerLiveStep "job state after the wait: $($Job.State)"
        if ($Job.State -eq 'Blocked') { Stop-Job -Job $Job }
        Receive-Job -Job $Job -Wait -ErrorAction SilentlyContinue
        Write-OerLiveStep "job state after the receive: $($Job.State)"
    } finally {
        if ($Job.State -notin 'Completed', 'Failed', 'Stopped') { Stop-Job -Job $Job }
        Remove-Job -Job $Job -Force
    }
}
```

## 1. A background job is refused before the sign-in, whatever its receiver's input holds

- [x] **1.1** The receiver launched as `pwsh -NoProfile -File`, its standard input holding `y`: in the job, a run of a document with a change, without `-Confirm:$false` and without `-WhatIf`, is refused with `ConfirmationUnavailable`, no row and no request; the same document under `-WhatIf` in the same job gives the plan. #type/subtask

```powershell
Invoke-S191Job
```

**Expect:** `receiver: host ConsoleHost, standard input redirected True`; `job state after the wait:
Completed` (a job that waited at a prompt would read `Blocked`); in the job the identity check prints True
for app, service principal and tenant; the module is the worktree's build, the token fence and the request
fences in place: True; `job: host ServerRemoteHost, sender info set True, started as a job server True, can
confirm False`; `run: own records 1 (ConfirmationUnavailable), rows 0 [none], graph requests 0 (writes 0),
arm requests 0 (writes 0)`; `plan: own records 0 (none), rows 1 [groups|oer-s191-absent|Skipped]`, graph
requests at least 1 with writes 0, arm requests 0; the plan would create the prefixed group: True.
**Failure looks like:** a `Blocked` job, a run row (the `y` answered a prompt), any request in the refused
run, a token request (the fence throws), a write, or no plan.
**Result (2026-11-14, as oer-live-cc, the module the worktree built at the commit `docs: name the host that answers an Invoke-Command -AsJob prompt`, 1.7.4 local build; each block in its own `pwsh`, standard input redirected and holding `y`, output redacted with OerLive before it was read):** PASS. `receiver: host ConsoleHost, standard input redirected True`; `job state after the wait: Completed`. In the job: identity check True for app, service principal and tenant (and the organization, the verified domain and the test subscription); the module is the worktree's build, the token fence and the request fences in place: True; `job: host ServerRemoteHost, sender info set True, started as a job server True, can confirm False`; `run: own records 1 (ConfirmationUnavailable), rows 0 [none], graph requests 0 (writes 0), arm requests 0 (writes 0)`; the plan printed `What if: Performing the operation "Create group" on target "oer-s191-absent".` and `plan: own records 0 (none), rows 1 [groups|oer-s191-absent|Skipped], graph requests 1 (writes 0), arm requests 0 (writes 0)`; the plan would create the prefixed group: True; `job state after the receive: Completed`. No token request, no write. Exit code 0.

- [x] **1.2** The receiver launched as `pwsh -NoProfile -NonInteractive -File`: the job is refused the same way, and the plan still runs. #type/subtask

```powershell
Invoke-S191Job
```

**Expect:** as 1.1, with the same `receiver:` line (the receiver's own switches do not decide the job's
answer; the job's process does).
**Failure looks like:** as 1.1.
**Result (2026-11-14, as oer-live-cc, the module the worktree built at the commit `docs: name the host that answers an Invoke-Command -AsJob prompt`, 1.7.4 local build; each block in its own `pwsh`, standard input redirected and holding `y`, output redacted with OerLive before it was read):** PASS. Launched `pwsh -NoProfile -NonInteractive -File`. The same lines as 1.1: `receiver: host ConsoleHost, standard input redirected True`, `job state after the wait: Completed`; identity check True; module is the worktree's build, fences in place: True; `job: host ServerRemoteHost, sender info set True, started as a job server True, can confirm False`; `run: own records 1 (ConfirmationUnavailable), rows 0 [none], graph requests 0 (writes 0), arm requests 0 (writes 0)`; `plan: own records 0 (none), rows 1 [groups|oer-s191-absent|Skipped], graph requests 1 (writes 0), arm requests 0 (writes 0)`; the plan would create the prefixed group: True. Exit code 0.

## Teardown

Nothing to remove: no object was created. Close with a sweep for the prefix.

- [x] **T.1** The sweep finds no object with the prefix `oer-s191-`. #type/subtask

```powershell
Connect-OerLive -Graph
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "Objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); kinds unread: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
```

**Expect:** `Objects with the prefix: 0; kinds unread: 0`.
**Failure looks like:** any object listed (a write got through), or a kind unread (the sweep proves nothing).
**Result (2026-11-14, as oer-live-cc, the module the worktree built at the commit `docs: name the host that answers an Invoke-Command -AsJob prompt`, 1.7.4 local build; each block in its own `pwsh`, standard input redirected and holding `y`, output redacted with OerLive before it was read):** PASS. Identity check True (Microsoft Graph sign-in); `Objects with the prefix: 0; kinds unread: 0`. Nothing was created, so nothing was removed.
