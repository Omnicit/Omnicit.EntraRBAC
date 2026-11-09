# Live verification checklist -- an ARM token goes only to the cloud's own host (fix/arm-token-own-host-only)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. It creates no object and sends no write: every
check runs with a request fence in the module's scope that refuses a request that writes, so there
is no prerequisite script and no teardown of objects. `oer-s1412-` names only strings that match
nothing; they are never created.

**Hosts.** Every host named in a refusal check ends in the top-level domain `.invalid`, which no
name server answers. No other invented host is used.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The transport.** `Invoke-OERArmRequest` parses the address it is about to send and refuses
  anything that is not https, without user information, on exactly the host and port of the
  session's Azure Resource Manager address, with `ArmRequestOutsideCloudHost`, before the token is
  read.
- **B. `Remove-OERRoleAssignment` and `Set-OERRoleAssignment`** refuse an `-Id` that does not begin
  with `/`, with the existing `InvalidRoleAssignmentId`.
- **Why live:** unit tests cover the refusals with a mocked `Invoke-WebRequest`. Only a real read
  shows that the real Azure Resource Manager host passes the parsed comparison, on a single request
  and on a walk that really follows `nextLink`, and that the ids the service really returns pass the
  anchored check.

## What this file does not check, and why

- **A sovereign cloud** (class B): the test tenant lives in the public cloud; the unit tests drive the
  USGov, USGovDoD and China hosts from `Get-OERCloudEndpoint`.
- **A real request refused after a 401 or a throttled retry** (class B): the guard stands in the one
  function every send passes through, and the unit tests drive both paths.

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
the redactor: a `What if:` line of a child goes past stream redirection.

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1412-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
function Connect-S1412 {
    Connect-OerLive -Arm
    $script:S1412Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S1412Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S1412 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S1412Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S1412Module {
        $script:S1412Sent = [System.Collections.Generic.List[string]]::new()
        $script:S1412Log = [System.Collections.Generic.List[string]]::new()
        $script:S1412RealArm = ${function:Invoke-OERArmRequest}
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All, [switch]$RequireValue)
            if ($Method -ne 'GET') { throw "S1412 fence: a $Method request was refused; this file writes nothing." }
            $script:S1412Log.Add('arm')
            & $script:S1412RealArm @PSBoundParameters
        }
        # Counts every send and keeps only its host: the address itself is never kept or printed, and
        # the Authorization header is never read.
        function script:Invoke-WebRequest {
            [CmdletBinding()]
            param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType)
            $script:S1412Sent.Add(([System.Uri]$Uri).IdnHost)
            Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S1412Module { (Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S1412 fence' }))"
    Write-OerLiveStep "Send counter in place: $((& $script:S1412Module { (Get-Command Invoke-WebRequest).CommandType -eq 'Function' }))"
}
function Reset-S1412Count { & $script:S1412Module { $script:S1412Log.Clear(); $script:S1412Sent.Clear() } }
function Get-S1412Count { & $script:S1412Module { 'arm calls {0}, sends {1}, every send to the cloud host {2}' -f $script:S1412Log.Count, $script:S1412Sent.Count, (@($script:S1412Sent | Where-Object { $_ -cne 'management.azure.com' }).Count -eq 0) } }
function Get-S1412Own { param($Err, [string]$Name) @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like "*,$Name" }) }
function Show-S1412 {
    # One line per call, ids and booleans only: never a message, a target or an id of the tenant.
    param([string]$Label, $Own, $Out)
    $Mine = @($Own | Where-Object { $null -ne $_ })
    $Id = if ($Mine.Count) { (([string]$Mine[0].FullyQualifiedErrorId) -split ',')[0] } else { 'none' }
    $Cat = if ($Mine.Count) { [string]$Mine[0].CategoryInfo.Category } else { 'none' }
    Write-OerLiveStep ('{0}: own records {1}, id {2}, category {3}, output {4}, {5}' -f $Label, $Mine.Count, $Id, $Cat, @($Out | Where-Object { $null -ne $_ }).Count, (Get-S1412Count))
}
```

## 1. An ordinary read works as before

- [ ] **1.1** A single read of the subscription and a role assignment read go to the cloud's own host. #type/subtask

```powershell
Connect-S1412
Reset-S1412Count
$Out = & $script:S1412Module { param($P) Invoke-OERArmRequest -Path $P } "$SubScope`?api-version=2022-12-01"
Show-S1412 -Label 'single read' -Own @() -Out $Out
Write-OerLiveStep "The answer names the subscription: $(([string]$Out.subscriptionId) -ceq $Cfg.SubscriptionId)"
Reset-S1412Count
$Err = $null
$Out = Get-OERRoleAssignment -Scope $SubScope -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S1412 -Label 'role assignment read' -Own (Get-S1412Own -Err $Err -Name 'Get-OERRoleAssignment') -Out $Out
Write-OerLiveStep "Assignments read: $(@($Out).Count -gt 0); every Id begins with '/': $(@($Out | Where-Object { -not ([string]$_.Id).StartsWith('/', [System.StringComparison]::Ordinal) }).Count -eq 0)"
Disconnect-OerLive
```

**Expect:** `single read: own records 0`, `sends 1`, `every send to the cloud host True`, and the answer names the subscription. `role assignment read: own records 0`, `sends` at least 1, `every send to the cloud host True`, at least one assignment, every Id begins with `/`.
**Failure looks like:** `ArmRequestOutsideCloudHost` on a real path; a send to another host; a subscription mismatch.
**Result:**

- [ ] **1.2** A read that really follows a next link: every page goes to the cloud's own host and the walk returns more than one page. #type/subtask

```powershell
Connect-S1412
Reset-S1412Count
$Out = & $script:S1412Module { param($P) Invoke-OERArmRequest -Path $P -All } "$SubScope/resources?api-version=2025-04-01&`$top=1"
$Count = @($Out.value).Count
Show-S1412 -Label 'paged read' -Own @() -Out @($Count)
$Sends = & $script:S1412Module { $script:S1412Sent.Count }
Write-OerLiveStep "Items: $Count; sends match items: $($Sends -ge $Count); more than one page: $($Sends -gt 1)"
Disconnect-OerLive
```

**Expect:** `paged read: own records 0, arm calls 1`, `every send to the cloud host True`, more than one send, `more than one page: True`.
**Failure looks like:** a refusal, a single page with many items reported as the walk (no paging exercised), or a send to another host.
**Result:**

## 2. Remove- and Set-OERRoleAssignment refuse an -Id that does not begin with /

- [ ] **2.1** A value that begins with a host suffix, `@host` or `:port@host`, or an absolute address, is refused by both cmdlets with no request. #type/subtask

```powershell
Connect-S1412
$Tail = '/providers/Microsoft.Authorization/roleAssignments/oer-s1412-none'
foreach ($Prefix in '.oer-s1412-none.invalid', '@oer-s1412-none.invalid', (':443' + '@oer-s1412-none.invalid'), 'https://oer-s1412-none.invalid') {
    $Bad = "$Prefix$Tail"
    Reset-S1412Count
    $Err = $null
    $Out = Remove-OERRoleAssignment -Id $Bad -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue
    Show-S1412 -Label "Remove $($Prefix.Substring(0, 2))" -Own (Get-S1412Own -Err $Err -Name 'Remove-OERRoleAssignment') -Out $Out
    Reset-S1412Count
    $Err = $null
    $Out = Set-OERRoleAssignment -Id $Bad -Description 'oer-s1412-none' -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue
    Show-S1412 -Label "Set $($Prefix.Substring(0, 2))" -Own (Get-S1412Own -Err $Err -Name 'Set-OERRoleAssignment') -Out $Out
}
Disconnect-OerLive
```

**Expect:** for every row `own records 1, id InvalidRoleAssignmentId, category InvalidArgument, output 0, arm calls 0, sends 0`.
**Failure looks like:** a request, any other id, or `ArmRequestOutsideCloudHost` (the check in the cmdlet did not catch it first).
**Result:**

- [ ] **2.2** A correctly shaped id still reaches the request: `Remove -WhatIf` passes the check and sends nothing, `Set` reads the id and gets the service's own answer for an assignment that does not exist. #type/subtask

```powershell
Connect-S1412
$Absent = "$SubScope/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000000"
Reset-S1412Count
$Err = $null
$Out = Remove-OERRoleAssignment -Id $Absent -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S1412 -Label 'Remove -WhatIf' -Own (Get-S1412Own -Err $Err -Name 'Remove-OERRoleAssignment') -Out $Out
Reset-S1412Count
$Err = $null
$Out = Set-OERRoleAssignment -Id $Absent -Description 'oer-s1412-none' -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue
$Own = Get-S1412Own -Err $Err -Name 'Set-OERRoleAssignment'
Show-S1412 -Label 'Set -WhatIf' -Own $Own -Out $Out
Disconnect-OerLive
```

**Expect:** `Remove -WhatIf`: `own records 0, arm calls 0, sends 0` (a `What if:` line is printed). `Set -WhatIf`: `arm calls 1, sends 1`, `every send to the cloud host True`, and the read's own refusal (`RoleAssignmentNotFound` or the service's error), never `InvalidRoleAssignmentId`.
**Failure looks like:** `InvalidRoleAssignmentId` on a well-shaped id.
**Result:**

## 3. The transport refuses an address on another host

- [ ] **3.1** A path that begins with a host suffix, `@host`, `:port@host` or an absolute address is refused by the transport with no send, and no token appears in the record. #type/subtask

```powershell
Connect-S1412
foreach ($Path in '.oer-s1412-none.invalid/x?api-version=1', '@oer-s1412-none.invalid/x?api-version=1', (':443' + '@oer-s1412-none.invalid/x?api-version=1'), 'https://oer-s1412-none.invalid/x?api-version=1') {
    Reset-S1412Count
    $Caught = & $script:S1412Module { param($P) try { Invoke-OERArmRequest -Path $P; $null } catch { $PSItem } } $Path
    $Id = if ($Caught) { (([string]$Caught.FullyQualifiedErrorId) -split ',')[0] } else { 'none' }
    $Cat = if ($Caught) { [string]$Caught.CategoryInfo.Category } else { 'none' }
    $Text = if ($Caught) { [string]$Caught.Exception.Message + [string]$Caught.TargetObject } else { '' }
    Write-OerLiveStep ('{0}: id {1}, category {2}, {3}, names a bearer: {4}, JWT shape: {5}' -f $Path.Substring(0, 2), $Id, $Cat, (Get-S1412Count), ($Text -match '(?i)bearer'), ($Text -match 'eyJ[A-Za-z0-9_-]{8,}'))
}
Disconnect-OerLive
```

**Expect:** for each row `id ArmRequestOutsideCloudHost, category InvalidArgument, arm calls 1, sends 0`, `names a bearer: False`, `JWT shape: False`.
**Failure looks like:** `sends 1`, any other id, or any token shape.
**Result:**

- [ ] **3.2** A public cmdlet whose value stands first in the address reaches a caller's `-ErrorVariable` with the refusal. #type/subtask

```powershell
Connect-S1412
Reset-S1412Count
$Err = $null
$Out = Get-OERRoleDefinition -Role '.oer-s1412-none.invalid/x/providers/Microsoft.Authorization/roleDefinitions/oer-s1412-none' -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S1412 -Label 'Get-OERRoleDefinition' -Own (Get-S1412Own -Err $Err -Name 'Get-OERRoleDefinition') -Out $Out
Disconnect-OerLive
```

**Expect:** `own records 1, id ArmRequestOutsideCloudHost, category InvalidArgument, output 0, arm calls 1, sends 0`.
**Failure looks like:** `sends 1`, or no record reaches `-ErrorVariable`.
**Result:**

## Teardown

Nothing was created; there is nothing to remove. A sweep for the prefix still runs once and must
list nothing.

- [ ] **T.1** The sweep finds nothing with the prefix `oer-s1412-`. #type/subtask

```powershell
Connect-S1412
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "Objects with the prefix: $($Found.Count)"
Disconnect-OerLive
```

**Expect:** `Objects with the prefix: 0`.
**Failure looks like:** anything else: stop, nothing here created an object.
**Result:**
