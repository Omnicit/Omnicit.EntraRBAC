# Live verification checklist -- the confirmation prompt in a redirected host (fix/confirmation-in-a-redirected-host)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. It creates no object and sends no write: every
check runs with a request fence in the module's scope that refuses every Microsoft Graph and Azure
Resource Manager request that writes, and a token fence that refuses every token request after the
sign-in. The document names a group `oer-s172-absent` that does not exist, so a plan reports it as a
group it would create and a refused run touches nothing. `oer-s172-` is the step's prefix; nothing is
created with it, so there is no prerequisite script and no teardown of objects.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The decision** (`fix: decide the confirmation prompt from the console's input and -NonInteractive`).
  `Test-OERHostCanConfirm` now also answers that the host cannot ask a person when the console host
  (`pwsh`) was started with `-NonInteractive`, or when its standard input is redirected (a pipe, a file,
  or a child process whose input is not a console). `Invoke-OERStructure` then refuses a run that would
  prompt with `ConfirmationUnavailable` before it signs in, as it already did in the Default Host.
- **Why live:** in Sprint 16 step 2 (finding F-6) a live block ran in exactly such a process -- `pwsh
  -File`, its output captured, its standard input redirected -- and every entry of a real run was
  reported `Failed` with "the host cannot show the confirmation prompt" after the run had signed in and
  read. The unit tests drive the decision with the two console signals mocked, and a child process
  offline; only a live run shows that the same process shape that produced F-6 now gives the refusal
  before any request, and that the plan (`-WhatIf`) still runs there.

## What this file does not check, and why

- **A console a person types into** (class B): that host has no redirected input, so nothing about it
  changed; the unit tests hold that the decision answers `$true` there
  (`tests/Unit/Private/Test-OERHostCanConfirm.Tests.ps1`), and the offline measurement of 2026-11-13
  recorded in `docs/development/rationale.md` (`#confirmation-unavailable`) showed the prompt waiting
  for an answer in that shape.
- **A real write with `-Confirm:$false`** (class B): the refusal is decided before the sign-in and does
  not reach a handler; the unit tests run `-Confirm:$false`, `-WhatIf` and `$ConfirmPreference = 'None'`
  past it in the same host shapes, and no write path changed.

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
redactor and its standard input redirected (not a console). The launch line of each block is named in
the block's check: `pwsh -NoProfile -File` (the shape of F-6) or `pwsh -NoProfile -NonInteractive -File`.
The runner writes the line `y` to the block's standard input and closes it, so a prompt that still read its
answer from the input would read Yes (the 2026-10-20 measurement); the fences stop any write all the same.

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s172-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Doc = '{ "version": "1.0", "groups": [ { "displayName": "oer-s172-absent", "description": "oer-s172 live check; never created" } ] }'
function Connect-S172 {
    Connect-OerLive -Arm
    $script:S172Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S172Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S172 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S172Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S172Module {
        $script:S172Graph = [System.Collections.Generic.List[string]]::new()
        $script:S172Arm = [System.Collections.Generic.List[string]]::new()
        $script:S172RealGraph = ${function:Invoke-OERGraphRequest}
        $script:S172RealArm = ${function:Invoke-OERArmRequest}
        # Counts every request by its method; refuses every one that writes. The address is never kept.
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $script:S172Graph.Add($Method)
            $IsRead = ($Method -eq 'GET') -or ($Method -eq 'POST' -and $Uri -match 'directoryObjects/getByIds|getMemberGroups|checkMember')
            if (-not $IsRead) { throw "S172 fence: a $Method request was refused; this file writes nothing." }
            & $script:S172RealGraph @PSBoundParameters
        }
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All, [switch]$RequireValue)
            $script:S172Arm.Add($Method)
            if ($Method -ne 'GET') { throw "S172 fence: a $Method request was refused; this file writes nothing." }
            & $script:S172RealArm @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fences in place: $((& $script:S172Module { ((Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S172 fence') -and ((Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S172 fence') }))"
}
function Reset-S172Count { & $script:S172Module { $script:S172Graph.Clear(); $script:S172Arm.Clear() } }
function Get-S172Count {
    & $script:S172Module {
        'graph requests {0} (writes {1}), arm requests {2} (writes {3})' -f $script:S172Graph.Count, @($script:S172Graph | Where-Object { $_ -ne 'GET' }).Count,
            $script:S172Arm.Count, @($script:S172Arm | Where-Object { $_ -ne 'GET' }).Count
    }
}
function Show-S172Host {
    $Answers = & $script:S172Module { '{0}|{1}' -f (Test-OERHostNonInteractive), (Test-OERHostCanConfirm) }
    $Parts = $Answers.Split('|')
    Write-OerLiveStep ('host {0}, standard input redirected {1}, started with -NonInteractive {2}, can confirm {3}' -f $Host.Name, [System.Console]::IsInputRedirected, $Parts[0], $Parts[1])
}
function Show-S172 {
    # One line per run, ids, counts and booleans only: never a message, a target or an id of the tenant.
    param([string]$Label, $Err, $Rows)
    $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Invoke-OERStructure' })
    $Ids = if ($Own.Count) { (@($Own | ForEach-Object { (([string]$_.FullyQualifiedErrorId) -split ',')[0] }) -join ' ') } else { 'none' }
    $RowText = if (@($Rows).Count) { (@($Rows | ForEach-Object { '{0}|{1}|{2}' -f $_.Section, $_.Item, $_.Action }) -join '; ') } else { 'none' }
    Write-OerLiveStep ('{0}: own records {1} ({2}), rows {3} [{4}], {5}' -f $Label, $Own.Count, $Ids, @($Rows).Count, $RowText, (Get-S172Count))
    $Prompt = @($Rows | Where-Object { [string]$_.Detail -like '*cannot show the confirmation prompt*' }).Count
    if ($Prompt) { Write-OerLiveStep ('{0}: rows that say the host cannot show the prompt {1}' -f $Label, $Prompt) }
}
```

## 1. A redirected or non-interactive console is refused before the sign-in

- [ ] **1.1** Launched as `pwsh -NoProfile -File` with standard input redirected (the shape of F-6): a run of a document with a change, without `-Confirm:$false` and without `-WhatIf`, is refused with `ConfirmationUnavailable`, no row and no request; the same document under `-WhatIf` gives the plan. #type/subtask

```powershell
Connect-S172
Show-S172Host
Reset-S172Count
$Err = $null
$Rows = @(Invoke-OERStructure -Json $Doc -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
Show-S172 -Label 'run' -Err $Err -Rows $Rows
Reset-S172Count
$Err = $null
$Rows = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
Show-S172 -Label 'plan' -Err $Err -Rows $Rows
Write-OerLiveStep "The plan would create the prefixed group: $(@($Rows | Where-Object { $_.Item -ceq 'oer-s172-absent' -and $_.Action -eq 'Skipped' -and [string]$_.Detail -ceq 'would create group oer-s172-absent' }).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** the identity check prints True for app, service principal and tenant; `host ConsoleHost,
standard input redirected True, started with -NonInteractive False, can confirm False`;
`run: own records 1 (ConfirmationUnavailable), rows 0 [none], graph requests 0 (writes 0), arm requests
0 (writes 0)`; `plan: own records 0 (none), rows 1 [groups|oer-s172-absent|Skipped]`, graph requests at
least 1 with writes 0, arm requests 0; the plan would create the prefixed group: True. The plan's row for a group
it would create is `Skipped` with the Detail `would create group oer-s172-absent` (the engine's plan form of a create).
**Failure looks like:** a `Failed` row saying the host cannot show the prompt (the F-6 behaviour), any
request in the refused run, a token request (the fence throws), a write, or no plan.
**Result:**

- [ ] **1.2** Launched as `pwsh -NoProfile -NonInteractive -File`: the same run is refused the same way, and the plan still runs. #type/subtask

```powershell
Connect-S172
Show-S172Host
Reset-S172Count
$Err = $null
$Rows = @(Invoke-OERStructure -Json $Doc -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
Show-S172 -Label 'run' -Err $Err -Rows $Rows
Reset-S172Count
$Err = $null
$Rows = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
Show-S172 -Label 'plan' -Err $Err -Rows $Rows
Disconnect-OerLive
```

**Expect:** identity check True; `host ConsoleHost, standard input redirected True, started with
-NonInteractive True, can confirm False`; `run: own records 1 (ConfirmationUnavailable), rows 0 [none],
graph requests 0 (writes 0), arm requests 0 (writes 0)`; `plan: own records 0 (none), rows 1
[groups|oer-s172-absent|Skipped]`, graph writes 0.
**Failure looks like:** as 1.1.
**Result:**

## Teardown

Nothing to remove: no object was created. Close with a sweep for the prefix.

- [ ] **T.1** The sweep finds no object with the prefix `oer-s172-`. #type/subtask

```powershell
Connect-OerLive -Graph
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "Objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); kinds unread: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
```

**Expect:** `Objects with the prefix: 0; kinds unread: 0`.
**Failure looks like:** any object listed (a write got through), or a kind unread (the sweep proves nothing).
**Result:**
