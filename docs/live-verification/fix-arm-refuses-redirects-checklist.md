# Live verification checklist -- the ARM transport follows no redirect (fix/arm-refuses-redirects)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. It creates no object and sends no write: every
check runs with a request fence in the module's scope that refuses a request that writes, so there
is no prerequisite script and no teardown of objects. `oer-s161-` is the step's prefix; nothing is
created with it.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The transport** (`fix: refuse a redirect on the Azure Resource Manager transport`).
  `Invoke-OERArmRequest` sends every request with `-MaximumRedirection 0`. An answer that redirects
  makes PowerShell stop with `MaximumRedirectExceeded`, and the wrapper refuses it with the new
  `ArmRedirectRefused`; nothing is sent to the address the redirect named. Every other transport
  failure is still `ArmTransportError`.
- **Why live:** the unit tests drive the refusal with a mocked `Invoke-WebRequest`. Only a real read
  shows that the real Azure Resource Manager host answers the module's ordinary reads without a
  redirect, so the new parameter changes nothing for them, on a single request and on a walk that
  really follows `nextLink`.

## What this file does not check, and why

- **A redirect itself** (class B): no Azure Resource Manager path the module uses is known to answer
  with a redirect, and an invented host that redirects is not part of the test tenant. The behaviour
  is held by the unit tests (`tests/Unit/Private/Invoke-OERArmRequest.Tests.ps1`, Describe
  "Invoke-OERArmRequest refuses a redirect (Sprint 16 step 1, BL-185, A9)", and the no-try probes) and
  by the loopback measurement of Sprint 16 step 1 recorded in `docs/development/rationale.md`
  (`#arm-transport`).
- **A sovereign cloud, a 401 retry, a throttled retry** (class B): every send passes through the one
  splat that carries the parameter, and the unit tests pin it on the retries.

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

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block), and redirect the whole process through
the redactor.

### H.1. The helpers every check uses

- [x] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s161-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
function Connect-S161 {
    Connect-OerLive -Arm
    $script:S161Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S161Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S161 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S161Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S161Module {
        $script:S161Sent = [System.Collections.Generic.List[string]]::new()
        $script:S161NoRedirect = [System.Collections.Generic.List[bool]]::new()
        $script:S161Log = [System.Collections.Generic.List[string]]::new()
        $script:S161RealArm = ${function:Invoke-OERArmRequest}
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All, [switch]$RequireValue)
            if ($Method -ne 'GET') { throw "S161 fence: a $Method request was refused; this file writes nothing." }
            $script:S161Log.Add('arm')
            & $script:S161RealArm @PSBoundParameters
        }
        # Counts every send, keeps only its host and whether it bound MaximumRedirection 0: the address
        # itself is never kept or printed, and the Authorization header is never read.
        function script:Invoke-WebRequest {
            [CmdletBinding()]
            param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType, $MaximumRedirection)
            $script:S161Sent.Add(([System.Uri]$Uri).IdnHost)
            $script:S161NoRedirect.Add(($PSBoundParameters.ContainsKey('MaximumRedirection') -and [int]$MaximumRedirection -eq 0))
            Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S161Module { (Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S161 fence' }))"
    Write-OerLiveStep "Send counter in place: $((& $script:S161Module { (Get-Command Invoke-WebRequest).CommandType -eq 'Function' }))"
}
function Reset-S161Count { & $script:S161Module { $script:S161Log.Clear(); $script:S161Sent.Clear(); $script:S161NoRedirect.Clear() } }
function Get-S161Count {
    & $script:S161Module {
        'arm calls {0}, sends {1}, every send to the cloud host {2}, every send with MaximumRedirection 0 {3}' -f $script:S161Log.Count, $script:S161Sent.Count,
            (@($script:S161Sent | Where-Object { $_ -cne 'management.azure.com' }).Count -eq 0),
            ($script:S161NoRedirect.Count -gt 0 -and @($script:S161NoRedirect | Where-Object { -not $_ }).Count -eq 0)
    }
}
function Get-S161Own { param($Err, [string]$Name) @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like "*,$Name" }) }
function Show-S161 {
    # One line per call, ids and booleans only: never a message, a target or an id of the tenant.
    param([string]$Label, $Own, $Out)
    $Mine = @($Own | Where-Object { $null -ne $_ })
    $Id = if ($Mine.Count) { (([string]$Mine[0].FullyQualifiedErrorId) -split ',')[0] } else { 'none' }
    Write-OerLiveStep ('{0}: own records {1}, id {2}, output {3}, {4}' -f $Label, $Mine.Count, $Id, @($Out | Where-Object { $null -ne $_ }).Count, (Get-S161Count))
}
```

## 1. Ordinary reads work as before

- [x] **1.1** A single read of the subscription and a public role assignment read get their answers, every send bound `MaximumRedirection 0`. #type/subtask

```powershell
Connect-S161
Reset-S161Count
$Out = & $script:S161Module { param($P) Invoke-OERArmRequest -Path $P } "$SubScope`?api-version=2022-12-01"
Show-S161 -Label 'single read' -Own @() -Out $Out
Write-OerLiveStep "The answer names the subscription: $(([string]$Out.subscriptionId) -ceq $Cfg.SubscriptionId)"
Reset-S161Count
$Err = $null
$Out = Get-OERRoleAssignment -Scope $SubScope -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S161 -Label 'role assignment read' -Own (Get-S161Own -Err $Err -Name 'Get-OERRoleAssignment') -Out $Out
Write-OerLiveStep "Assignments read: $(@($Out).Count -gt 0)"
Disconnect-OerLive
```

**Expect:** `single read: own records 0, id none, output 1`, `sends 1`, `every send to the cloud host True`, `every send with MaximumRedirection 0 True`, and the answer names the subscription. `role assignment read: own records 0`, `sends` at least 1, both booleans True, at least one assignment.
**Failure looks like:** `ArmRedirectRefused` or `ArmTransportError` on an ordinary read; a send without the parameter; a send to another host.
**Result (2026-11-12, as oer-live-cc, the module the worktree built, 1.7.1):** PASS. The identity check printed True for app, service principal and tenant. `single read: own records 0, id none, output 1, arm calls 1, sends 1, every send to the cloud host True, every send with MaximumRedirection 0 True`; the answer names the subscription: True. `role assignment read: own records 0, id none, output 13, arm calls 1, sends 1, every send to the cloud host True, every send with MaximumRedirection 0 True`; assignments read: True.

- [x] **1.2** A read that really follows a next link: every page binds `MaximumRedirection 0`, goes to the cloud's own host, and the walk returns more than one page. #type/subtask

```powershell
Connect-S161
Reset-S161Count
$Out = & $script:S161Module { param($P) Invoke-OERArmRequest -Path $P -All } "$SubScope/resources?api-version=2025-04-01&`$top=1"
$Count = @($Out.value).Count
Show-S161 -Label 'paged read' -Own @() -Out @($Count)
$Sends = & $script:S161Module { $script:S161Sent.Count }
Write-OerLiveStep "Items: $Count; sends match items: $($Sends -ge $Count); more than one page: $($Sends -gt 1)"
Disconnect-OerLive
```

**Expect:** `paged read: own records 0, arm calls 1`, `every send to the cloud host True`, `every send with MaximumRedirection 0 True`, more than one send, `more than one page: True`.
**Failure looks like:** a refusal on a page, a single page reported as the walk (no paging exercised), a send without the parameter, or a send to another host.
**Result (2026-11-12, as oer-live-cc, the module the worktree built, 1.7.1):** PASS. `paged read: own records 0, id none, output 1, arm calls 1, sends 6, every send to the cloud host True, every send with MaximumRedirection 0 True`; `Items: 6; sends match items: True; more than one page: True`.

## Teardown

Nothing was created; there is nothing to remove. A sweep for the prefix still runs once and must
list nothing.

- [x] **T.1** The sweep finds nothing with the prefix `oer-s161-`. #type/subtask

```powershell
Connect-S161
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "Objects with the prefix: $($Found.Count)"
Disconnect-OerLive
```

**Expect:** `Objects with the prefix: 0`.
**Failure looks like:** anything else: stop, nothing here created an object.
**Result (2026-11-12, as oer-live-cc, the module the worktree built, 1.7.1):** PASS. `Objects with the prefix: 0`; the sweep named every kind as clear.
