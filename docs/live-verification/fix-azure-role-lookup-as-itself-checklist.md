# Live verification checklist -- a failed Azure role lookup is reported as itself (fix/azure-role-lookup-as-itself)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. Every cmdlet runs with `-WhatIf`, and a counting
fence on the two send commands (`Invoke-WebRequest` for Azure Resource Manager, `Invoke-MgGraphRequest`
for Microsoft Graph) proves that only `GET` requests left the process. There is no prerequisite script
and no test object; the teardown only proves that nothing carries the prefix `oer-s131-` and that no
session is left.

**Who runs it.** The dedicated certificate identities `oer-live-cc` and `oer-live-cc-noperm`, through
the OerLive library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only; nothing here signs in as a
person. Section 1 runs as `oer-live-cc-noperm` on purpose: its refusal is what this branch reports.
A 401 or 403 as `oer-live-cc` in section 2 is a stop.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s131/`, which
is git-ignored. Every block prints through the library's redactor. **No credential, token,
application id, tenant id, subscription id, account or certificate thumbprint is ever printed** --
identities are printed as True or False, records as their error id, category and a count -- and **no
error record is ever rendered**.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The seven Azure role assignment cmdlets** ("publish a failed role lookup as itself in the
  Azure role assignment cmdlets"). `New-OERRoleAssignment`, `New-OERActiveRoleAssignment`,
  `New-OEREligibleRoleAssignment`, `Remove-OERActiveRoleAssignment`, `Remove-OEREligibleRoleAssignment`,
  `Enable-OEREligibleRoleAssignment` and `Disable-OEREligibleRoleAssignment` published every failure of
  the role definition lookup as `RoleDefinitionNotFound`: a refused read, a throttled one, an
  incomplete answer and an ambiguous name all read as "no such role". Now only a lookup that succeeded
  and matched nothing is `RoleDefinitionNotFound` (same message, category and target as before); every
  other failure is published as itself.
- **B. An Azure list answer without a list** ("refuse an empty Azure list answer when the caller
  requires a value", "read the role definition and role policy lists as unread when Azure answers
  without a list"). The Azure Resource Manager transport takes a private switch, the mirror of the
  Microsoft Graph transport's, that refuses an answer whose body is empty, JSON null or has no `value`
  member with `ArmPagingIncomplete`; the role definition lookup and the role policy list use it.
  Proven offline only: Azure Resource Manager cannot be made to answer a list request that way.

A live tenant is needed for what the unit tests stub: the real refusal Azure Resource Manager sends an
identity without permissions on the role definition read, and the real answer for an identity with
them.

## What this file does not check, and why

- **B, an answer without a list** (class B): the shape is not producible live. The unit tests drive it
  through the real transport with a stubbed web request.
- **An ambiguous role name** (A, class B): producing one needs a second role definition of the same
  name in the scope chain, which is a write (a custom role) this file does not make.
  `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` holds every one of the seven.
- **The four cmdlets not run here** (A): `New-OERActiveRoleAssignment`, `Remove-OERActiveRoleAssignment`,
  `Enable-OEREligibleRoleAssignment` and `Disable-OEREligibleRoleAssignment` carry the same block as the
  three run here (`New-OERRoleAssignment`, `New-OEREligibleRoleAssignment`,
  `Remove-OEREligibleRoleAssignment`); the unit tests hold each of the seven.
- **Convergence (G8)**: this branch changes no write path, only the lookup in front of one. Section 2
  still runs its reads twice and compares them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm` enabled for the run.
  This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.

**Run every numbered block in its OWN PowerShell process.**

The blocks of sections 1 and 2 define the same two helpers. `Install-S131Fence` replaces, for the
rest of the process, `Invoke-WebRequest` (the Azure Resource Manager send) with a counter that
records each request's method and whether it is the role definition list, `Get-AzToken` with a
refusal (no token request is expected after the sign-in), and the module's `Invoke-OERGraphRequest`
with a refusal (none of these cmdlets needs Microsoft Graph); it returns `True` only when all three
are in place, and nothing is called before it does. `Invoke-S131Case` runs one cmdlet with `-WhatIf`
for the made-up principal `00000000-0000-0000-0000-000000000099` at the test subscription and prints
the cmdlet's OWN records (the `,<Cmdlet>` suffix of the error id), their categories and targets, and
the counted requests. `New-OEREligibleRoleAssignment` is given `-DurationDays 30`, so no permanent-policy pre-check runs.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
$A = @(Select-String -LiteralPath $Psm1 -SimpleMatch 'Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope -ThrowUnresolved').Count
$B1 = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch '[switch]$RequireValue' -Quiet)
$B2 = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch '$filter=$Filter" -RequireValue' -Quiet)
$B3 = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch 'roleManagementPolicyAssignments?api-version=2020-10-01" -All -RequireValue' -Quiet)
Write-OerLiveStep "The worktree's build carries A (role lookups with -ThrowUnresolved): $A; B (the value requirement, the role lookup, the policy list): $B1, $B2, $B3"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `A ...: 9` (the seven cmdlets plus
the two role management policy cmdlets); `B ...: True, True, True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; `A` below 9 or any `False` in `B` -- build the worktree first (`./build.ps1 -Tasks build`),
never while the gate runs.

Result:

## 1. As oer-live-cc-noperm: a refused role lookup is published as itself

### 1.1. Before: the base commit publishes the refusal as RoleDefinitionNotFound

- [ ] **1.1** As `oer-live-cc-noperm`, with the module imported from the SOURCE of the base commit `111a73f` (the commit this branch starts from): `New-OERRoleAssignment`, `New-OEREligibleRoleAssignment` and `Remove-OEREligibleRoleAssignment` with `-WhatIf` and the role `Reader` each write one own record, `RoleDefinitionNotFound`, for the refused role definition read, and send nothing but that read. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
# The base commit's source, from git, into the step's raw folder (git-ignored), imported in dev mode.
$Base = Join-Path $Raw 'base-111a73f'
if (-not (Test-Path -LiteralPath (Join-Path $Base 'source\Omnicit.EntraRBAC.psd1'))) {
    $null = New-Item -ItemType Directory -Path $Base -Force
    git -C $Cfg.Repo archive --format=zip -o (Join-Path $Raw 'base-111a73f.zip') 111a73f source
    Expand-Archive -LiteralPath (Join-Path $Raw 'base-111a73f.zip') -DestinationPath $Base -Force
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $Base 'source\Omnicit.EntraRBAC.psd1') -Force -Global
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the base commit's source: $($Module.ModuleBase.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)); it lacks the branch (no -RequireValue): $(-not [bool](& $Module { (Get-Command Invoke-OERArmRequest).Parameters.ContainsKey('RequireValue') }))"
Connect-OerLive -Arm -NoPerm
function Install-S131Fence {
    $global:S131Sent = [System.Collections.Generic.List[string]]::new()
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [uri]$Uri, [System.Collections.IDictionary]$Headers, [switch]$SkipHttpErrorCheck, [object]$Body, [string]$ContentType)
        $Kind = if ([string]$Uri -match '/providers/Microsoft\.Authorization/roleDefinitions\?') { 'roleDefinitions' } else { 'other' }
        $global:S131Sent.Add("$Method $Kind")
        Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }
    function global:Get-AzToken { $global:S131Sent.Add('TOKEN'); throw 'S131 fence: no token request is expected after the sign-in.' }
    $M = Get-Module -Name Omnicit.EntraRBAC
    & $M { function script:Invoke-OERGraphRequest { $global:S131Sent.Add('GRAPH'); throw 'S131 fence: no Microsoft Graph request is expected in this check.' } }
    $Ok = ((& $M { (Get-Command Invoke-WebRequest).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Get-AzToken).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() }) -match 'S131 fence')
    Write-OerLiveStep "Fences in place (ARM send counter, token refusal, Graph refusal): $Ok"
    $Ok
}
function Invoke-S131Case {
    param([string]$Cmdlet, [string]$Role)
    $global:S131Sent.Clear()
    $CaseErr = $null; $CaseWarn = $null
    $Params = @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)"; Role = $Role; PrincipalId = '00000000-0000-0000-0000-000000000099'
        WhatIf = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CaseErr'; WarningVariable = 'CaseWarn' }
    # A time-bound eligibility, so no permanent-policy pre-check runs (the default is permanent).
    if ($Cmdlet -eq 'New-OEREligibleRoleAssignment') { $Params.DurationDays = 30 }
    $Output = @(& $Cmdlet @Params 3>$null)
    $Own = @($CaseErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Cmdlet", [System.StringComparison]::Ordinal) })
    Write-OerLiveStep ("{0} -Role '{1}' -WhatIf: own records: {2}; own ids: {3}; categories: {4}; targets are the role: {5}; RoleDefinitionNotFound among them: {6}; the message names the refused read action: {7}; the message says the role was not found at the scope: {8}; output objects: {9}; warnings: {10}; requests: {11} ({12}); role definition list reads: {13}; requests other than GET: {14}" -f
        $Cmdlet, $Role, $Own.Count, ((@($Own | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Sort-Object -Unique) -join ', '),
        ((@($Own | ForEach-Object { [string]$_.CategoryInfo.Category }) | Sort-Object -Unique) -join ', '),
        ($Own.Count -gt 0 -and -not @($Own | Where-Object { [string]$_.TargetObject -ne $Role })),
        [bool]@($Own | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('RoleDefinitionNotFound,', [System.StringComparison]::Ordinal) }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).Contains('Microsoft.Authorization/roleDefinitions/read') }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).StartsWith("Role definition '$Role' was not found at scope", [System.StringComparison]::Ordinal) }),
        $Output.Count, @($CaseWarn).Count, $global:S131Sent.Count, ($global:S131Sent -join ', '),
        @($global:S131Sent | Where-Object { $_ -eq 'GET roleDefinitions' }).Count, @($global:S131Sent | Where-Object { $_ -notlike 'GET *' }).Count)
}
if (Install-S131Fence) {
    foreach ($C in 'New-OERRoleAssignment', 'New-OEREligibleRoleAssignment', 'Remove-OEREligibleRoleAssignment') { Invoke-S131Case -Cmdlet $C -Role 'Reader' }
}
Disconnect-OerLive
```

**Expect:** the module is the base commit's source `True`, it lacks the branch `True`; fences
`True`; for each of the three cmdlets `own records: 1; own ids: RoleDefinitionNotFound,<Cmdlet>;
categories: ObjectNotFound; targets are the role: True; RoleDefinitionNotFound among them: True; the
message names the refused read action: True` (the old code carried the refusal's text under the
not-found id), `output objects: 0; warnings: 0; requests: 1 (GET roleDefinitions); role definition
list reads: 1; requests other than GET: 0`.
**Failure looks like:** an own id other than `RoleDefinitionNotFound` -- the base is not the old
code; read the S.1 commit; `requests other than GET` above 0 -- STOP, something was written.

Result:

### 1.2. After: this branch publishes the refusal as itself

- [ ] **1.2** As `oer-live-cc-noperm`, with this branch's build: the same three calls each write one own record whose id is the refusal's own (`AuthorizationFailed`), category `PermissionDenied`, never `RoleDefinitionNotFound`, and send nothing but the refused role definition read. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Install-S131Fence {
    $global:S131Sent = [System.Collections.Generic.List[string]]::new()
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [uri]$Uri, [System.Collections.IDictionary]$Headers, [switch]$SkipHttpErrorCheck, [object]$Body, [string]$ContentType)
        $Kind = if ([string]$Uri -match '/providers/Microsoft\.Authorization/roleDefinitions\?') { 'roleDefinitions' } else { 'other' }
        $global:S131Sent.Add("$Method $Kind")
        Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }
    function global:Get-AzToken { $global:S131Sent.Add('TOKEN'); throw 'S131 fence: no token request is expected after the sign-in.' }
    $M = Get-Module -Name Omnicit.EntraRBAC
    & $M { function script:Invoke-OERGraphRequest { $global:S131Sent.Add('GRAPH'); throw 'S131 fence: no Microsoft Graph request is expected in this check.' } }
    $Ok = ((& $M { (Get-Command Invoke-WebRequest).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Get-AzToken).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() }) -match 'S131 fence')
    Write-OerLiveStep "Fences in place (ARM send counter, token refusal, Graph refusal): $Ok"
    $Ok
}
function Invoke-S131Case {
    param([string]$Cmdlet, [string]$Role)
    $global:S131Sent.Clear()
    $CaseErr = $null; $CaseWarn = $null
    $Params = @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)"; Role = $Role; PrincipalId = '00000000-0000-0000-0000-000000000099'
        WhatIf = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CaseErr'; WarningVariable = 'CaseWarn' }
    # A time-bound eligibility, so no permanent-policy pre-check runs (the default is permanent).
    if ($Cmdlet -eq 'New-OEREligibleRoleAssignment') { $Params.DurationDays = 30 }
    $Output = @(& $Cmdlet @Params 3>$null)
    $Own = @($CaseErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Cmdlet", [System.StringComparison]::Ordinal) })
    Write-OerLiveStep ("{0} -Role '{1}' -WhatIf: own records: {2}; own ids: {3}; categories: {4}; targets are the role: {5}; RoleDefinitionNotFound among them: {6}; the message names the refused read action: {7}; the message says the role was not found at the scope: {8}; output objects: {9}; warnings: {10}; requests: {11} ({12}); role definition list reads: {13}; requests other than GET: {14}" -f
        $Cmdlet, $Role, $Own.Count, ((@($Own | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Sort-Object -Unique) -join ', '),
        ((@($Own | ForEach-Object { [string]$_.CategoryInfo.Category }) | Sort-Object -Unique) -join ', '),
        ($Own.Count -gt 0 -and -not @($Own | Where-Object { [string]$_.TargetObject -ne $Role })),
        [bool]@($Own | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('RoleDefinitionNotFound,', [System.StringComparison]::Ordinal) }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).Contains('Microsoft.Authorization/roleDefinitions/read') }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).StartsWith("Role definition '$Role' was not found at scope", [System.StringComparison]::Ordinal) }),
        $Output.Count, @($CaseWarn).Count, $global:S131Sent.Count, ($global:S131Sent -join ', '),
        @($global:S131Sent | Where-Object { $_ -eq 'GET roleDefinitions' }).Count, @($global:S131Sent | Where-Object { $_ -notlike 'GET *' }).Count)
}
if (Install-S131Fence) {
    foreach ($C in 'New-OERRoleAssignment', 'New-OEREligibleRoleAssignment', 'Remove-OEREligibleRoleAssignment') { Invoke-S131Case -Cmdlet $C -Role 'Reader' }
}
Disconnect-OerLive
```

**Expect:** the module is the build `True`; fences `True`; for each of the three cmdlets `own
records: 1; own ids: AuthorizationFailed,<Cmdlet>; categories: PermissionDenied; targets are the
role: False` (the record is the refusal's own, whose target is the request, not the role);
`RoleDefinitionNotFound among them: False; the message names the refused read action: True; the
message says the role was not found at the scope: False; output objects: 0; warnings: 0; requests:
1 (GET roleDefinitions); role definition list reads: 1; requests other than GET: 0`.
**Failure looks like:** `RoleDefinitionNotFound` for the refused read -- the old shape; more than one
own record -- the cmdlet did not return after publishing; `requests other than GET` above 0 -- STOP.

Result:

## 2. As oer-live-cc: a missing role is still RoleDefinitionNotFound, an existing one resolves

### 2.1. A role name that does not exist

- [ ] **2.1** As `oer-live-cc`: the three calls with the role name `oer-s131-no-such-role` each write one own record `RoleDefinitionNotFound`, category `ObjectNotFound`, target the role name, with the message the module has always written ("Role definition '...' was not found at scope ..."), and send nothing but the role definition read. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Install-S131Fence {
    $global:S131Sent = [System.Collections.Generic.List[string]]::new()
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [uri]$Uri, [System.Collections.IDictionary]$Headers, [switch]$SkipHttpErrorCheck, [object]$Body, [string]$ContentType)
        $Kind = if ([string]$Uri -match '/providers/Microsoft\.Authorization/roleDefinitions\?') { 'roleDefinitions' } else { 'other' }
        $global:S131Sent.Add("$Method $Kind")
        Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }
    function global:Get-AzToken { $global:S131Sent.Add('TOKEN'); throw 'S131 fence: no token request is expected after the sign-in.' }
    $M = Get-Module -Name Omnicit.EntraRBAC
    & $M { function script:Invoke-OERGraphRequest { $global:S131Sent.Add('GRAPH'); throw 'S131 fence: no Microsoft Graph request is expected in this check.' } }
    $Ok = ((& $M { (Get-Command Invoke-WebRequest).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Get-AzToken).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() }) -match 'S131 fence')
    Write-OerLiveStep "Fences in place (ARM send counter, token refusal, Graph refusal): $Ok"
    $Ok
}
function Invoke-S131Case {
    param([string]$Cmdlet, [string]$Role)
    $global:S131Sent.Clear()
    $CaseErr = $null; $CaseWarn = $null
    $Params = @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)"; Role = $Role; PrincipalId = '00000000-0000-0000-0000-000000000099'
        WhatIf = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CaseErr'; WarningVariable = 'CaseWarn' }
    # A time-bound eligibility, so no permanent-policy pre-check runs (the default is permanent).
    if ($Cmdlet -eq 'New-OEREligibleRoleAssignment') { $Params.DurationDays = 30 }
    $Output = @(& $Cmdlet @Params 3>$null)
    $Own = @($CaseErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Cmdlet", [System.StringComparison]::Ordinal) })
    Write-OerLiveStep ("{0} -Role '{1}' -WhatIf: own records: {2}; own ids: {3}; categories: {4}; targets are the role: {5}; RoleDefinitionNotFound among them: {6}; the message names the refused read action: {7}; the message says the role was not found at the scope: {8}; output objects: {9}; warnings: {10}; requests: {11} ({12}); role definition list reads: {13}; requests other than GET: {14}" -f
        $Cmdlet, $Role, $Own.Count, ((@($Own | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Sort-Object -Unique) -join ', '),
        ((@($Own | ForEach-Object { [string]$_.CategoryInfo.Category }) | Sort-Object -Unique) -join ', '),
        ($Own.Count -gt 0 -and -not @($Own | Where-Object { [string]$_.TargetObject -ne $Role })),
        [bool]@($Own | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('RoleDefinitionNotFound,', [System.StringComparison]::Ordinal) }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).Contains('Microsoft.Authorization/roleDefinitions/read') }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).StartsWith("Role definition '$Role' was not found at scope", [System.StringComparison]::Ordinal) }),
        $Output.Count, @($CaseWarn).Count, $global:S131Sent.Count, ($global:S131Sent -join ', '),
        @($global:S131Sent | Where-Object { $_ -eq 'GET roleDefinitions' }).Count, @($global:S131Sent | Where-Object { $_ -notlike 'GET *' }).Count)
}
if (Install-S131Fence) {
    foreach ($C in 'New-OERRoleAssignment', 'New-OEREligibleRoleAssignment', 'Remove-OEREligibleRoleAssignment') { Invoke-S131Case -Cmdlet $C -Role 'oer-s131-no-such-role' }
}
Disconnect-OerLive
```

**Expect:** the module is the build `True`; fences `True`; for each cmdlet `own records: 1; own ids:
RoleDefinitionNotFound,<Cmdlet>; categories: ObjectNotFound; targets are the role: True;
RoleDefinitionNotFound among them: True; the message names the refused read action: False; the
message says the role was not found at the scope: True; output objects: 0; warnings: 0; requests: 1
(GET roleDefinitions); role definition list reads: 1; requests other than GET: 0`.
**Failure looks like:** any other own id -- the no-match case is no longer read as no match; a 401 or
403 as `oer-live-cc` -- STOP (G6).

Result:

### 2.2. An existing role, twice

- [ ] **2.2** As `oer-live-cc`: `New-OERRoleAssignment` and `New-OEREligibleRoleAssignment` with `-WhatIf` and the role `Reader` write no record and no warning, print their `What if:` line, send only `GET` requests, and a second run prints the same. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Install-S131Fence {
    $global:S131Sent = [System.Collections.Generic.List[string]]::new()
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [uri]$Uri, [System.Collections.IDictionary]$Headers, [switch]$SkipHttpErrorCheck, [object]$Body, [string]$ContentType)
        $Kind = if ([string]$Uri -match '/providers/Microsoft\.Authorization/roleDefinitions\?') { 'roleDefinitions' } else { 'other' }
        $global:S131Sent.Add("$Method $Kind")
        Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }
    function global:Get-AzToken { $global:S131Sent.Add('TOKEN'); throw 'S131 fence: no token request is expected after the sign-in.' }
    $M = Get-Module -Name Omnicit.EntraRBAC
    & $M { function script:Invoke-OERGraphRequest { $global:S131Sent.Add('GRAPH'); throw 'S131 fence: no Microsoft Graph request is expected in this check.' } }
    $Ok = ((& $M { (Get-Command Invoke-WebRequest).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Get-AzToken).CommandType }) -eq 'Function') -and
        ((& $M { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() }) -match 'S131 fence')
    Write-OerLiveStep "Fences in place (ARM send counter, token refusal, Graph refusal): $Ok"
    $Ok
}
function Invoke-S131Case {
    param([string]$Cmdlet, [string]$Role)
    $global:S131Sent.Clear()
    $CaseErr = $null; $CaseWarn = $null
    $Params = @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)"; Role = $Role; PrincipalId = '00000000-0000-0000-0000-000000000099'
        WhatIf = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CaseErr'; WarningVariable = 'CaseWarn' }
    # A time-bound eligibility, so no permanent-policy pre-check runs (the default is permanent).
    if ($Cmdlet -eq 'New-OEREligibleRoleAssignment') { $Params.DurationDays = 30 }
    $Output = @(& $Cmdlet @Params 3>$null)
    $Own = @($CaseErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Cmdlet", [System.StringComparison]::Ordinal) })
    Write-OerLiveStep ("{0} -Role '{1}' -WhatIf: own records: {2}; own ids: {3}; categories: {4}; targets are the role: {5}; RoleDefinitionNotFound among them: {6}; the message names the refused read action: {7}; the message says the role was not found at the scope: {8}; output objects: {9}; warnings: {10}; requests: {11} ({12}); role definition list reads: {13}; requests other than GET: {14}" -f
        $Cmdlet, $Role, $Own.Count, ((@($Own | ForEach-Object { [string]$_.FullyQualifiedErrorId }) | Sort-Object -Unique) -join ', '),
        ((@($Own | ForEach-Object { [string]$_.CategoryInfo.Category }) | Sort-Object -Unique) -join ', '),
        ($Own.Count -gt 0 -and -not @($Own | Where-Object { [string]$_.TargetObject -ne $Role })),
        [bool]@($Own | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('RoleDefinitionNotFound,', [System.StringComparison]::Ordinal) }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).Contains('Microsoft.Authorization/roleDefinitions/read') }),
        [bool]@($Own | Where-Object { ([string]$_.Exception.Message).StartsWith("Role definition '$Role' was not found at scope", [System.StringComparison]::Ordinal) }),
        $Output.Count, @($CaseWarn).Count, $global:S131Sent.Count, ($global:S131Sent -join ', '),
        @($global:S131Sent | Where-Object { $_ -eq 'GET roleDefinitions' }).Count, @($global:S131Sent | Where-Object { $_ -notlike 'GET *' }).Count)
}
if (Install-S131Fence) {
    foreach ($Run in 'first', 'second') {
        Write-OerLiveStep "2.2 $Run run"
        foreach ($C in 'New-OERRoleAssignment', 'New-OEREligibleRoleAssignment') { Invoke-S131Case -Cmdlet $C -Role 'Reader' }
    }
}
Disconnect-OerLive
```

**Expect:** the module is the build `True`; fences `True`; in both runs, for both cmdlets, a `What
if:` line naming the role and the made-up principal, and `own records: 0; ...; output objects: 0;
warnings: 0`, `role definition list reads: 1`, `requests other than GET: 0`; the second run's lines
equal the first's.
**Failure looks like:** a record as `oer-live-cc` -- STOP if it is a 401 or 403 (G6), otherwise read
it; `requests other than GET` above 0 -- STOP, something was written.

Result:

## Teardown

### T.1. Nothing carries the prefix, no session is left, the main clone was never switched

- [ ] **T.1** No object carries `oer-s131-`, the module holds no session, and the raw folder for the step is deleted after the results are copied. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s131-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s131'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "T.1 objects carrying the prefix: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count); collections that could not be read: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "T.1 the module holds a session after Disconnect-OerLive: $([bool](& $Module { $script:_OERAuthState }))"
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "T.1 the step's raw folder is gone: $(-not (Test-Path -LiteralPath $Raw))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
Write-OerLiveStep "T.1 main clone: branch $(([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', '')"
```

**Expect:** `objects carrying the prefix: 0; collections that could not be read: 0`; `the module holds
a session after Disconnect-OerLive: False`; `the step's raw folder is gone: True`; the main clone on
`main`.
**Failure looks like:** a count above 0 -- this file creates nothing, so an object with the prefix is
not this run's: STOP.

Result:
