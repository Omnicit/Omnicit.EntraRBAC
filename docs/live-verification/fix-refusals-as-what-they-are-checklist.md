# Live verification checklist -- refused combinations and policy ids as what they are (fix/refusals-as-what-they-are)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. It creates no object and sends no write: every
check runs with a request fence in the module's scope that refuses a request that writes, so there
is no prerequisite script and no teardown of objects. `oer-s141-` names only strings that match
nothing; they are never created.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Two of `-User`, `-Group` and `-ServicePrincipal`** on `Get-OERActiveRoleAssignment`,
  `Get-OEREligibleRoleAssignment` and `Get-OERRoleAssignment` publish `MutuallyExclusiveParameter`
  (InvalidArgument), not `PrincipalNotFound`.
- **B. A `-PolicyId` that is not an Azure Resource Manager path** is refused by
  `Get-OERRoleManagementPolicy` and `Set-OERRoleManagementPolicy` with `InvalidPolicyId`, before any
  Azure Resource Manager or Microsoft Graph request, and for `Set` before its confirmation.
- **C. The tenant's own ids.** The only thing unit tests cannot show is that a policy id the service
  really returns passes the guard, and that a real Microsoft Graph policy id does not.

## What this file does not check, and why

- **The full stops of an `InventoryPartial` message and the `-AccessReviewFilter` help** (class B):
  text only, held by the unit tests of `Format-OERUnreadCauseClause` and `Get-OERInventory`.
- **A policy id at a management group scope**, if `oer-live-cc` cannot read there (check 3.2 says
  which): the guard's test is the leading `/`, and the sample of the list call in Microsoft Learn
  shows `policyId` as a full path at a subscription; no sample for a management group is documented.

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

- [x] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s141-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
function Connect-S141 {
    Connect-OerLive -Arm
    $script:S141Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S141Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S141 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S141Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S141Module {
        $script:S141Log = [System.Collections.Generic.List[string]]::new()
        $script:S141RealGraph = ${function:Invoke-OERGraphRequest}
        $script:S141RealArm = ${function:Invoke-OERArmRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            if ($Method -ne 'GET' -and $Uri -notmatch 'getByIds') { throw "S141 fence: a $Method request was refused; this file writes nothing." }
            $script:S141Log.Add('graph')
            & $script:S141RealGraph @PSBoundParameters
        }
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [hashtable]$Body, [switch]$All, [switch]$RequireValue)
            if ($Method -ne 'GET') { throw "S141 fence: a $Method request was refused; this file writes nothing." }
            $script:S141Log.Add('arm')
            & $script:S141RealArm @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S141Module { (Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S141 fence' }))"
}
function Reset-S141Count { & $script:S141Module { $script:S141Log.Clear() } }
function Get-S141Count { & $script:S141Module { 'graph {0}, arm {1}' -f @($script:S141Log | Where-Object { $_ -eq 'graph' }).Count, @($script:S141Log | Where-Object { $_ -eq 'arm' }).Count } }
function Get-S141Own { param($Err, [string]$Name) @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like "*,$Name" }) }
function Show-S141 {
    # One line per call, ids and booleans only: never a message, a target or an id of the tenant.
    param([string]$Label, $Own, $Out)
    $Mine = @($Own | Where-Object { $null -ne $_ })
    $Id = if ($Mine.Count) { (([string]$Mine[0].FullyQualifiedErrorId) -split ',')[0] } else { 'none' }
    $Cat = if ($Mine.Count) { [string]$Mine[0].CategoryInfo.Category } else { 'none' }
    Write-OerLiveStep ('{0}: own records {1}, id {2}, category {3}, output {4}, {5}' -f $Label, $Mine.Count, $Id, $Cat, @($Out | Where-Object { $null -ne $_ }).Count, (Get-S141Count))
}
```

## 1. Two principal parameters

- [x] **1.1** Each of the three readers refuses two principal parameters as what it is, and sends nothing. #type/subtask

```powershell
Connect-S141
foreach ($Name in 'Get-OERActiveRoleAssignment', 'Get-OEREligibleRoleAssignment', 'Get-OERRoleAssignment') {
    Reset-S141Count
    $Err = $null
    $Out = & $Name -Scope $SubScope -User 'oer-s141-nobody@contoso.com' -Group 'oer-s141-nogroup' -ErrorVariable Err -ErrorAction SilentlyContinue
    Show-S141 -Label $Name -Own (Get-S141Own -Err $Err -Name $Name) -Out $Out
}
Disconnect-OerLive
```

**Expect:** for each cmdlet `own records 1, id MutuallyExclusiveParameter, category InvalidArgument, output 0, graph 0, arm 0`.
**Failure looks like:** `id PrincipalNotFound`, or a non-zero request count.
**Result (2026-11-09, as oer-live-cc, the module the worktree built, 1.5.1):** PASS. All three: `own records 1, id MutuallyExclusiveParameter, category InvalidArgument, output 0, graph 0, arm 0`. The identity check printed True for app, service principal and tenant.

- [x] **1.2** One principal parameter still goes through the lookup: an unknown user stays `PrincipalNotFound`, and a service principal object id reaches the read. #type/subtask

```powershell
Connect-S141
Reset-S141Count
$Err = $null
$Out = Get-OERActiveRoleAssignment -Scope $SubScope -User 'oer-s141-nobody@contoso.com' -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'unknown user' -Own (Get-S141Own -Err $Err -Name 'Get-OERActiveRoleAssignment') -Out $Out
Reset-S141Count
$Err = $null
$Out = Get-OERRoleAssignment -Scope $SubScope -ServicePrincipal '00000000-0000-0000-0000-000000000000' -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'service principal object id' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleAssignment') -Out $Out
Disconnect-OerLive
```

**Expect:** `unknown user`: `own records 1, id PrincipalNotFound, category ObjectNotFound`, at least one Graph read, `arm 0`. `service principal object id`: `own records 0`, `graph 0, arm 1`.
**Failure looks like:** `MutuallyExclusiveParameter` on a single parameter, or a read that never went out.
**Result:** PASS. `unknown user: own records 1, id PrincipalNotFound, category ObjectNotFound, output 0, graph 1, arm 0`. `service principal object id: own records 0, id none, category none, output 0, graph 0, arm 1`.

## 2. A policy id that is not an Azure Resource Manager path

- [x] **2.1** A real Microsoft Graph policy id from the module's own output is refused by `Get-` and `Set-OERRoleManagementPolicy`, as a parameter and from the pipeline, with no request. #type/subtask

```powershell
Connect-S141
$Graph = Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ErrorAction Stop
Write-OerLiveStep "The Graph policy id starts with '/': $(([string]$Graph.PolicyId).StartsWith('/', [System.StringComparison]::Ordinal))"
Reset-S141Count
$Err = $null
$Out = Get-OERRoleManagementPolicy -PolicyId $Graph.PolicyId -ErrorVariable Err -ErrorAction SilentlyContinue
$Own = Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy'
Show-S141 -Label 'Get, parameter' -Own $Own -Out $Out
Write-OerLiveStep "The message names the directory role cmdlet: $(([string]@($Own)[0].Exception.Message).Contains('Get-OERDirectoryRoleManagementPolicy'))"
Reset-S141Count
$Err = $null
$Out = Set-OERRoleManagementPolicy -PolicyId $Graph.PolicyId -ActivationMaxHours 1 -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue
$Own = Get-S141Own -Err $Err -Name 'Set-OERRoleManagementPolicy'
Show-S141 -Label 'Set -WhatIf, parameter' -Own $Own -Out $Out
Write-OerLiveStep "The message names the directory role cmdlet: $(([string]@($Own)[0].Exception.Message).Contains('Set-OERDirectoryRoleManagementPolicy'))"
Reset-S141Count
$Err = $null
$Out = $Graph | Get-OERRoleManagementPolicy -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'Get, pipeline' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy') -Out $Out
Reset-S141Count
$Err = $null
$Out = $Graph | Set-OERRoleManagementPolicy -ActivationMaxHours 1 -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'Set -WhatIf, pipeline' -Own (Get-S141Own -Err $Err -Name 'Set-OERRoleManagementPolicy') -Out $Out
Disconnect-OerLive
```

**Expect:** the id does not start with `/` (`False`). Each of the four calls: `own records 1, id InvalidPolicyId, category InvalidArgument, output 0, graph 0, arm 0`. Both message lines `True`. No `What if:` line.
**Failure looks like:** an ARM or Graph count above 0, a `What if:` line, or another id.
**Result:** PASS. The Graph policy id does not start with `/` (False). `Get, parameter`, `Set -WhatIf, parameter`, `Get, pipeline` and `Set -WhatIf, pipeline`: each `own records 1, id InvalidPolicyId, category InvalidArgument, output 0, graph 0, arm 0`. Both message lines True. No `What if:` line.

## 3. A real Azure Resource Manager policy id still works

- [x] **3.1** The id the module gives out for a role at the subscription passes the guard as a parameter and from the pipeline, reads the same policy, and a `Set -WhatIf` writes nothing. #type/subtask

```powershell
Connect-S141
$Arm = Get-OERRoleManagementPolicy -Role 'Reader' -Scope $SubScope -ErrorAction Stop
Write-OerLiveStep "The ARM policy id starts with '/': $(([string]$Arm.PolicyId).StartsWith('/', [System.StringComparison]::Ordinal))"
Reset-S141Count
$Err = $null
$Again = Get-OERRoleManagementPolicy -PolicyId $Arm.PolicyId -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'Get, parameter' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy') -Out $Again
Write-OerLiveStep "Same policy id read back: $([string]$Again.PolicyId -ceq [string]$Arm.PolicyId); same number of rules: $(@($Again.EffectiveRules).Count -eq @($Arm.EffectiveRules).Count)"
Reset-S141Count
$Err = $null
$Out = $Arm | Get-OERRoleManagementPolicy -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'Get, pipeline' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy') -Out $Out
Reset-S141Count
$Err = $null
$Out = $Arm | Set-OERRoleManagementPolicy -ActivationMaxHours 1 -WhatIf -ErrorVariable Err -ErrorAction SilentlyContinue
Show-S141 -Label 'Set -WhatIf, pipeline' -Own (Get-S141Own -Err $Err -Name 'Set-OERRoleManagementPolicy') -Out $Out
Disconnect-OerLive
```

**Expect:** `True` for the leading `/`. `Get, parameter` and `Get, pipeline`: `own records 0, output 1, graph 0, arm 1`. Same policy id and same number of rules, both `True`. `Set -WhatIf, pipeline`: no `InvalidPolicyId` (`own records 0`, or one `NoChange` when the rule already holds that value), `arm 1`, and the request fence refused nothing.
**Failure looks like:** `InvalidPolicyId` on the real id, or `S141 fence` in the output.
**Result:** PASS. The ARM policy id starts with `/` (True). `Get, parameter` and `Get, pipeline`: `own records 0, id none, category none, output 1, graph 0, arm 1`. Same policy id read back and same number of rules: True. `Set -WhatIf, pipeline`: a `What if:` line for the rule `Expiration_EndUser_Assignment`, `own records 0, output 0, graph 0, arm 1`; the request fence refused nothing.

- [~] **3.2** The id at a resource group, and at a management group where the identity can read there, also starts with `/` and passes. #type/subtask

```powershell
Connect-S141
$Rg = @(Get-OERResourceGroup -Subscription $Cfg.SubscriptionId -ErrorAction Stop | Select-Object -First 1)
if ($Rg.Count -eq 0) {
    Write-OerLiveStep 'resource group: the subscription has none, not measured'
} else {
    $Pol = Get-OERRoleManagementPolicy -Role 'Reader' -Scope $Rg[0].ResourceId -ErrorAction Stop
    Write-OerLiveStep "resource group: the policy id starts with '/': $(([string]$Pol.PolicyId).StartsWith('/', [System.StringComparison]::Ordinal))"
    Reset-S141Count
    $Err = $null
    $Out = Get-OERRoleManagementPolicy -PolicyId $Pol.PolicyId -ErrorVariable Err -ErrorAction SilentlyContinue
    Show-S141 -Label 'resource group, Get by id' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy') -Out $Out
}
$Mg = "/providers/Microsoft.Management/managementGroups/$($Cfg.TenantId)"
$Err = $null
$Pol = Get-OERRoleManagementPolicy -Role 'Reader' -Scope $Mg -ErrorVariable Err -ErrorAction SilentlyContinue
if (-not $Pol) {
    $Own = Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy'
    Write-OerLiveStep ('management group: not measured, the read answered {0}' -f $(if (@($Own).Count) { (([string]@($Own)[0].FullyQualifiedErrorId) -split ',')[0] } else { 'nothing' }))
} else {
    Write-OerLiveStep "management group: the policy id starts with '/': $(([string]$Pol.PolicyId).StartsWith('/', [System.StringComparison]::Ordinal))"
    Reset-S141Count
    $Err = $null
    $Out = Get-OERRoleManagementPolicy -PolicyId $Pol.PolicyId -ErrorVariable Err -ErrorAction SilentlyContinue
    Show-S141 -Label 'management group, Get by id' -Own (Get-S141Own -Err $Err -Name 'Get-OERRoleManagementPolicy') -Out $Out
}
Disconnect-OerLive
```

**Expect:** `True` for each scope read, and `own records 0, output 1` for the read by id. A refused read at the management group is recorded as not measured: this check asks exactly whether the identity can read there, so it is not a stop.
**Failure looks like:** `InvalidPolicyId` on a real id, or a policy id that does not start with `/`.
**Result:** PARTIAL, so marked `[~]`. Resource group: the policy id starts with `/` (True), and reading it by id gives `own records 0, id none, category none, output 1, graph 0, arm 1`. Management group: not measured, the read answered `InsufficientPermissions`: oer-live-cc cannot read there, so for that scope kind this cannot be verified, and therefore we do not know.

## Teardown

Nothing was created. **T.1** Delete `raw/` for the step if the run left one, and sign out (each block ends with `Disconnect-OerLive`).

**Result:** PASS. Nothing was created or written. No `raw/` folder for the step exists, in the main clone or in the vault. Each block signed out with `Disconnect-OerLive`.
