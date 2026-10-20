# Live verification checklist -- a failed policy read writes nothing, and the engine and the validator say what they do (fix/engine-and-validator-findings)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4, 5, 6 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be
impossible to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked `[~]`, never
`[x]`. **Section B lists what is proved offline only (class B).** No manual check (class C) is foreseen.

**What this file writes to the tenant.** The prerequisite script writes only objects whose names start with
`oer-s1111-`: a disabled user, four security groups (one owned by that user and by the service principal of
`oer-live-cc-noperm`, which is not changed), a catalog, a hidden access package with one assignment policy, a
monthly access review of one of the groups, and a tagged, empty resource group whose own policy for the
built-in role Reader it changes to require approval by the user and one of the groups -- after writing that
policy's baseline. The measurements in section 1 write to those objects only: a second assignment policy on the
package, a PUT of each policy, the removal of the user as an owner, the PIM-for-Groups policy rules of the two
groups never used with PIM for Groups (which onboards them; their deletion removes the policies), and a PUT of
the review. Section 2 applies a document to the Reader policy at the resource group. Sections 3 to 6 send no
write request (a fence refuses one). Teardown (T.1) deletes the review, restores the Reader policy and the
Reports Reader policy from their baselines, then removes every object and the resource group.

**The tenant's object names are never printed.** The blocks print counts, True/False and the step's own
prefixed names only.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives
beside the operator's copy of this file outside the repository ([README.md](README.md), first paragraph).
Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or 403 is a stop.

**Permissions.** The prerequisite script checks the six it needs (User.ReadWrite.All, Group.ReadWrite.All,
EntitlementManagement.ReadWrite.All, AccessReview.ReadWrite.All, RoleManagementPolicy.ReadWrite.AzureADGroup and
RoleManagementPolicy.ReadWrite.Directory) and is refused without them. Granting a permission is the operator's
decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, and every block that runs the module
installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs outside the repository. Every block prints through the
library's redactor, so its lines are already redacted per [README.md](README.md). **No credential, token,
application id, tenant id, subscription id, account or certificate thumbprint is ever printed.** Each block is
run in its own process whose WHOLE output (every stream) is written to a file outside the repository, redacted
with OerLive's redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main` before it
merges.

- **A. No write on a failed read** (BL-40, BL-38, BL-113, BL-47). The Azure role management policy handler
  reads the live policy so that every failure, a non-terminating one included, is a Failed row with the read's
  own record and no write, in a run and under `-WhatIf`; the group `pimPolicy` read does the same. A top-level
  section that is `null` is not declared: no row, no Azure Resource Manager token. The directory role and group
  PIM policy handlers report `ApproverRequired` before their `ShouldProcess`, so the plan says what the run does.
  An unread role name map stops only an administrative unit's scoped roles.
- **B. Measured first** (BL-49, BL-84, BL-97 F3, BL-117 sixth point): section 1.
- **C. The validator and the engine say what they do** (BL-139, BL-154, BL-155, BL-117, BL-54, BL-24, BL-53,
  BL-97 F2, BL-52, BL-86, BL-157, BL-121).

A live tenant is needed for the measurements, for an Azure role policy whose approvers are really on both sides
when a document declares one, for a session that holds no Azure Resource Manager token, for a host that cannot
show a confirmation prompt, and for Microsoft Graph's own refusals that the plan now predicts.

## What this file does not check, and why

- **A read of the live Azure role policy that fails (class B, B.1).** The read cannot be made to fail on demand
  without changing the identity's permissions; the unit tests drive the real `Get-OERRoleManagementPolicy` with a
  failing transport, non-terminating and terminating, under `-WhatIf` and in a script with no `try`.
- **A read of a group's PIM policy that fails (class B, B.2),** for the same reason.
- **An unread role name map of an administrative unit (class B, B.3).**
- **A PowerShell without `ConvertFrom-Json -DateKind` (class B, B.4).** The step's host runs a current
  PowerShell; the refusal of a value read as a date is proved offline through the seam that reports the parameter.
- **A split answer to two `-Confirm` prompts of `Set-OERGroupPimPolicy` (class B, B.5),** which needs a person at
  the keyboard; the unit tests answer the prompts through a test host.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`,
  and the environment variable `OER_LIVE_REPO` naming that worktree.
- The **prerequisite script** `Initialize-OerS1111Prereq.ps1` beside OerLive (0.2 runs it; T.1 removes what it
  created).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the counters and the
readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1111-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Work = Join-Path $Raw 'docs'
$null = New-Item -ItemType Directory -Path $Work -Force
$Prefix = 'oer-s1111-'
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Ar = 'v1.0/identityGovernance/accessReviews/definitions'
$PimBase = 'beta/policies'
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/${Prefix}rg"

function Get-S1111ReaderGuid {
    # The built-in Reader role's definition guid, read from Azure Resource Manager (never written in this file).
    $R = Invoke-OerLiveArm -Path ("/subscriptions/{0}/providers/Microsoft.Authorization/roleDefinitions?`$filter={1}&api-version=2022-04-01" -f $Cfg.SubscriptionId, [uri]::EscapeDataString("roleName eq 'Reader'"))
    Assert-OerLiveOk -Response $R -Activity 'Reading the Reader role definition' | Out-Null
    $Rows = @(@($R.Body.value) | Where-Object { [string]$_.properties.roleName -ceq 'Reader' -and [string]$_.properties.type -eq 'BuiltInRole' })
    if ($Rows.Count -ne 1) { throw "The Reader role resolved to $($Rows.Count) built-in definitions, not one." }
    [string]$Rows[0].name
}
function Start-S1111NoPrompt {
    # A token request without the certificate would be an interactive or device-code sign-in: refuse it.
    $global:S1111TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S1111TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S1111 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S1111Count {
    # Counts every request the module sends and, unless -AllowWrite, REFUSES every write: Microsoft Graph through
    # a global proxy of Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. Each entry
    # is the method and the path with every GUID segment written {id}. getByIds and getEntities are reads sent as
    # POST.
    param([switch]$AllowWrite)
    $global:S1111Graph = [System.Collections.Generic.List[string]]::new()
    $global:S1111Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Fence = if ($AllowWrite) { '' } else { 'if ($M -ne ''GET'' -and $S -notlike ''POST */getByIds'' -and $S -notlike ''POST */getEntities'') { throw ''S1111 fence: a write request was refused.'' }' }
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1111Shape -Uri ([string]`$Uri)); `$global:S1111Graph.Add(`$S); $Fence; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1111Shape -Uri ([string]`$Uri)); `$global:S1111Arm.Add(`$S); $Fence; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function global:Get-S1111Shape {
    # The request's path with each GUID segment as {id}.
    param([string]$Uri)
    $Path = $Uri
    if ([uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) { $Path = ([uri]$Uri).AbsolutePath }
    elseif ($Uri.Contains('?')) { $Path = $Uri.Substring(0, $Uri.IndexOf('?')) }
    $Path = '/' + $Path.TrimStart('/')
    $Path -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}'
}

function Stop-S1111Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S1111Sent {
    # Totals and writes since Start-S1111Count.
    $GraphWrites = @($global:S1111Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getByIds' })
    $ArmWrites = @($global:S1111Arm | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getEntities' })
    "token requests: $global:S1111TokenCalls; Microsoft Graph requests: $($global:S1111Graph.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S1111Arm.Count), writes: $($ArmWrites.Count)"
}

function Get-S1111Ids {
    # The ids the prerequisite script recorded (key -> id), never printed.
    $Path = Join-Path $Raw 'created-s1111.json'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{} }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Get-S1111FirstId {
    # The first segment of each record's FullyQualifiedErrorId, in order.
    param($Records)
    @(@($Records) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
}

function Invoke-S1111Graph {
    # One raw Microsoft Graph request with optional headers (the measurements need the Prefer header, which
    # Invoke-OerLiveGraph does not send). Status, code and message as data; never an error record, never a token.
    param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [object]$Body, [hashtable]$Headers)
    $Params = @{ Method = $Method; Uri = $Uri; OutputType = 'HashTable'; SkipHttpErrorCheck = $true; StatusCodeVariable = 'S1111Status'; ErrorAction = 'Stop'; Verbose = $false }
    if ($null -ne $Body) { $Params.Body = $Body | ConvertTo-Json -Depth 30 -Compress; $Params.ContentType = 'application/json' }
    if ($Headers) { $Params.Headers = $Headers }
    $S1111Status = $null
    $Response = $null
    $Transport = $null
    try { $Response = Microsoft.Graph.Authentication\Invoke-MgGraphRequest @Params } catch { $Transport = ConvertTo-OerLiveRedacted -Text $PSItem.Exception.Message; $global:Error.Clear() }
    $Status = if ($Transport) { 0 } else { [int]($S1111Status -as [int]) }
    $HasError = ($Response -is [System.Collections.IDictionary]) -and $Response.Contains('error')
    if ($Status -eq 0 -and -not $Transport -and -not $HasError) { $Status = 200 }
    $Code = ''; $Message = ''
    if ($HasError) { $Code = [string]$Response['error']['code']; $Message = ConvertTo-OerLiveRedacted -Text ([string]$Response['error']['message']); if ($Status -lt 400) { $Status = 400 } }
    if ($Transport) { $Code = 'TransportError'; $Message = $Transport }
    [PSCustomObject]@{ Status = $Status; Ok = ($Status -ge 200 -and $Status -lt 300); Code = $Code; Message = $Message; Body = $(if (-not $HasError) { $Response }) }
}

function Save-S1111Doc {
    # One structure document as a JSON file in the work folder; returns its path.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Json)
    $Path = Join-Path $Work "$Name.json"
    [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
    $Path
}

function Invoke-S1111Apply {
    # Invoke-OERStructure on one document, with -Confirm:$false; prints each row (prefixed names only) and returns
    # the rows, the first segment of every record's id, and how many warnings were written (not printed).
    param([Parameter(Mandatory)][string]$Path, [switch]$WhatIf, [string[]]$Include)
    $Params = @{ Path = $Path; Confirm = $false; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'ApplyErrors'; WarningVariable = 'ApplyWarnings' }
    if ($WhatIf) { $Params.WhatIf = $true }
    if ($Include) { $Params.Include = $Include }
    $Rows = @(Invoke-OERStructure @Params 3>$null)
    foreach ($Row in $Rows) { Write-OerLiveStep "Row: [$($Row.Section)] $($Row.Item) $($Row.Action) -- $($Row.Detail)" }
    [PSCustomObject]@{ Rows = $Rows; Errors = @(Get-S1111FirstId $ApplyErrors); Warnings = @($ApplyWarnings).Count; WarningText = @($ApplyWarnings | ForEach-Object { [string]$_ }) }
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Marks = [ordered]@{
    'reads the Azure role policy with -ErrorAction Stop' = 'Get-OERRoleManagementPolicy -Role $Item.role @ScopeSplat -ErrorAction Stop'
}
$Found = @(foreach ($Key in $Marks.Keys) { '{0}: {1}' -f $Key, [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Marks[$Key] -Quiet) })
Write-OerLiveStep "The branch build ($((Split-Path -Leaf (Split-Path -Parent $Psm1.FullName)))): $($Found -join '; ')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; `True` on every mark.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a `False`
mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, `The module is the worktree's build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

### 0.2. The prerequisite objects

- [ ] **0.2** `Initialize-OerS1111Prereq.ps1` shows its plan under `-WhatIf`, then with `-Unattended` checks the permissions, writes the baselines, creates the step's objects and changes the Reader policy at the resource group. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1111Prereq.ps1') -WhatIf
Write-OerLiveStep "The plan ended with exit code $LASTEXITCODE."
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1111Prereq.ps1') -Unattended
Write-OerLiveStep "The prerequisite script ended with exit code $LASTEXITCODE."
```

**Expect:** the plan: the six permissions `True`, every write as a `What if:` line, exit code 0; the run: the
baselines written (or found), the objects created or found, the Reader policy requiring approval by both, exit
code 0.
**Failure looks like:** a refusal (a missing permission, an unknown prefixed object), or exit code 1 or 3.

Result:

### 0.3. Read back what the prerequisite script created

- [ ] **0.3** Each recorded object is there; the owned group has two owners; the review is monthly; the Reader policy at the resource group requires approval by one user and one group. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1111Ids
Write-OerLiveStep "Recorded ids: $($Ids.Count) ($(@($Ids.Keys | Sort-Object) -join ', '))"
# Typed reads: the untyped owners read does not list a service principal.
$UserOwners = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids['owned'])/owners/microsoft.graph.user?`$select=id"
$SpOwners = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids['owned'])/owners/microsoft.graph.servicePrincipal?`$select=id"
Write-OerLiveStep "owned: user owners $(@($UserOwners.Body['value']).Count), service principal owners $(@($SpOwners.Body['value']).Count)"
$Review = Invoke-OerLiveGraph -Uri "$Ar/$($Ids['review'])"
$Pattern = $Review.Body['settings']['recurrence']['pattern']
Write-OerLiveStep "review: read $($Review.Status); pattern $([string]$Pattern['type']) interval $([string]$Pattern['interval'])"
$ReaderGuid = Get-S1111ReaderGuid
$P = Get-OerLiveArmRolePolicy -Scope $RgScope -RoleDefinitionGuid $ReaderGuid
$A = @($P.Rules | Where-Object { [string]$_['id'] -eq 'Approval_EndUser_Assignment' })[0]
$Stage = @($A['setting']['approvalStages'])[0]
$Kinds = @(@($Stage['primaryApprovers']) | ForEach-Object { [string]$_['userType'] })
Write-OerLiveStep "Reader at the resource group: approval required $([bool]$A['setting']['isApprovalRequired']); approvers: users $(@($Kinds | Where-Object { $_ -eq 'User' }).Count), groups $(@($Kinds | Where-Object { $_ -eq 'Group' }).Count)"
Disconnect-OerLive
```

**Expect:** 7 recorded ids (u1, apgroup, owned, pimraw, pimraw2, pimcmd, review); user owners 1, service principal owners 1; the review `absoluteMonthly`
interval 1; approval required `True`, approvers users 1, groups 1.
**Failure looks like:** a missing id, a read that is not 200, or approvers on one side only.

Result:

## 1. Measurements, made before the fixes that depend on them

### 1.1. BL-49: what an assignment policy reads back as without the Prefer header, and what a PUT of `unknownFutureValue` does

- [ ] **1.1** A policy for an evolvable target scope reads back as `unknownFutureValue` without the Prefer header or not, and a PUT whose `allowedTargetScope` is `unknownFutureValue` is refused, accepted without change, or changes the scope. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1111Ids
$Prefer = @{ Prefer = 'include-unknown-enum-members' }
$Pkg = @(@((Invoke-OerLiveGraph -All -Uri "$Em/accessPackages?`$select=id,displayName").Body['value']) | Where-Object { [string]$_['displayName'] -ceq "${Prefix}ap" })[0]
$PkgId = [string]$Pkg['id']
function Get-S1111PolicyByName { param([string]$Name) @(@((Invoke-OerLiveGraph -All -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$PkgId'"))).Body['value']) | Where-Object { [string]$_['displayName'] -ceq $Name })[0] }
$Member = Get-S1111PolicyByName -Name "${Prefix}policy"
$Plain = Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Member['id'])"
$WithPrefer = Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Member['id'])" -Headers $Prefer
Write-OerLiveStep "${Prefix}policy reads: without Prefer '$([string]$Plain.Body['allowedTargetScope'])', with Prefer '$([string]$WithPrefer.Body['allowedTargetScope'])'"
# An evolvable member of the enumeration: Microsoft Learn lists allDirectoryAgentIdentities beside unknownFutureValue.
$Agent = Get-S1111PolicyByName -Name "${Prefix}agentpol"
if (-not $Agent) {
    $Body = @{
        displayName = "${Prefix}agentpol"; description = "Omnicit.EntraRBAC live verification ($Prefix): BL-49 measurement."
        allowedTargetScope = 'allDirectoryAgentIdentities'; specificAllowedTargets = @(); expiration = @{ type = 'noExpiration' }
        requestorSettings = @{ enableTargetsToSelfAddAccess = $false; enableTargetsToSelfUpdateAccess = $false; enableTargetsToSelfRemoveAccess = $false; allowCustomAssignmentSchedule = $false; enableOnBehalfRequestorsToAddAccess = $false; enableOnBehalfRequestorsToUpdateAccess = $false; enableOnBehalfRequestorsToRemoveAccess = $false; onBehalfRequestors = @() }
        requestApprovalSettings = @{ isApprovalRequiredForAdd = $false; isApprovalRequiredForUpdate = $false; stages = @() }
        accessPackage = @{ id = $PkgId }
    }
    $Create = Invoke-S1111Graph -Method POST -Uri "$Em/assignmentPolicies" -Body $Body -Headers $Prefer
    Write-OerLiveStep "Creating ${Prefix}agentpol with allowedTargetScope allDirectoryAgentIdentities (Prefer sent): $($Create.Status) $($Create.Code) $($Create.Message)"
    if ($Create.Ok) { Start-Sleep -Seconds 10; $Agent = Get-S1111PolicyByName -Name "${Prefix}agentpol" }
}
$Target = $Member
if ($Agent) {
    $APlain = Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Agent['id'])"
    $APrefer = Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Agent['id'])" -Headers $Prefer
    Write-OerLiveStep "${Prefix}agentpol reads: without Prefer '$([string]$APlain.Body['allowedTargetScope'])', with Prefer '$([string]$APrefer.Body['allowedTargetScope'])'"
    if ([string]$APlain.Body['allowedTargetScope'] -eq 'unknownFutureValue') { $Target = $Agent }
}
# The PUT a cmdlet would send when it carries forward a value it read: the read body, allowedTargetScope 'unknownFutureValue'.
$TargetName = [string]$Target['displayName']
$Read = Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Target['id'])"
$Before = [string](Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Target['id'])" -Headers $Prefer).Body['allowedTargetScope']
$Put = @{}
foreach ($Key in 'displayName', 'description', 'specificAllowedTargets', 'expiration', 'requestorSettings', 'requestApprovalSettings') { $Put[$Key] = $Read.Body[$Key] }
$Put.allowedTargetScope = 'unknownFutureValue'
$Put.accessPackage = @{ id = $PkgId }
$Answer = Invoke-S1111Graph -Method PUT -Uri "$Em/assignmentPolicies/$([string]$Target['id'])" -Body $Put
Write-OerLiveStep "PUT of $TargetName with allowedTargetScope 'unknownFutureValue': $($Answer.Status) $($Answer.Code) $($Answer.Message)"
Start-Sleep -Seconds 10
$After = [string](Invoke-S1111Graph -Uri "$Em/assignmentPolicies/$([string]$Target['id'])" -Headers $Prefer).Body['allowedTargetScope']
Write-OerLiveStep "$TargetName allowedTargetScope (read with Prefer) before '$Before', after '$After'; changed: $($Before -ne $After)"
Disconnect-OerLive
```

**Expect:** a measurement: the four reads and the PUT's answer. If the PUT changed the scope, that is a STOP
(P0): the cmdlet would send it whenever Microsoft Graph returns it.
**Failure looks like:** a 401 or 403 (STOP), or no policy to read.

Result:

### 1.2. BL-84: does Microsoft Graph refuse to remove the last user owner while a service principal is an owner

- [ ] **1.2** The removal of the user owner of `oer-s1111-owned`, whose other owner is a service principal, is refused or accepted, and the group's owners are read back. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1111Ids
# Typed reads: the untyped owners read does not list a service principal.
function Get-S1111OwnerCount { param([string]$Type) @((Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids['owned'])/owners/microsoft.graph.$Type`?`$select=id").Body['value']).Count }
Write-OerLiveStep "owned before: user owners $(Get-S1111OwnerCount -Type user), service principal owners $(Get-S1111OwnerCount -Type servicePrincipal)"
$Remove = Invoke-OerLiveGraph -Method DELETE -Uri "v1.0/groups/$($Ids['owned'])/owners/$($Ids['u1'])/`$ref"
Write-OerLiveStep "DELETE of the owner ${Prefix}u1 (owners/`$ref): $($Remove.Status) $($Remove.Code) $($Remove.Message)"
Start-Sleep -Seconds 10
Write-OerLiveStep "owned after: user owners $(Get-S1111OwnerCount -Type user), service principal owners $(Get-S1111OwnerCount -Type servicePrincipal)"
Disconnect-OerLive
```

**Expect:** a measurement: the DELETE's answer and the owners after it.
**Failure looks like:** a 401 or 403 (STOP).

Result:

### 1.3. BL-97 F3: a first call with several rules on a group never used with PIM for Groups (raw)

- [ ] **1.3** On `oer-s1111-pimraw2`, two rule PATCHes sent to the policy id listed BEFORE the first: the listed policy id after each, and whether the second rule reaches the policy Microsoft Graph lists afterwards. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1111Ids
$Gid = $Ids['pimraw2']
function Get-S1111ListedPolicy {
    $Filter = [uri]::EscapeDataString("scopeId eq '$Gid' and scopeType eq 'Group'")
    $L = Invoke-OerLiveGraph -All -Uri "$PimBase/roleManagementPolicyAssignments?`$filter=$Filter"
    if ($L.Refused) { Assert-OerLiveOk -Response $L -Activity 'Listing the PIM-for-Groups policy assignments' | Out-Null }
    if (-not $L.Ok) { return '' }
    [string](@(@($L.Body['value']) | Where-Object { [string]$_['roleDefinitionId'] -eq 'member' })[0]['policyId'])
}
function Get-S1111Rule { param([string]$PolicyId, [string]$RuleId) (Invoke-OerLiveGraph -Uri "$PimBase/roleManagementPolicies/$PolicyId/rules/$RuleId").Body }
# A group created moments ago is not listed at once (replication delay): wait for its member policy.
$P0 = (Wait-OerLiveConverged -Activity 'the new group lists its member policy' -BudgetSeconds 300 -Read { Get-S1111ListedPolicy } -Test { -not [string]::IsNullOrEmpty([string]$args[0]) }).Value
$Exp0 = Get-S1111Rule -PolicyId $P0 -RuleId 'Expiration_EndUser_Assignment'
$Ena0 = Get-S1111Rule -PolicyId $P0 -RuleId 'Enablement_EndUser_Assignment'
Write-OerLiveStep "Before: maximumDuration $([string]$Exp0['maximumDuration']); enabledRules [$(@($Ena0['enabledRules']) -join ',')]"
$R1 = Invoke-OerLiveGraph -Method PATCH -Uri "$PimBase/roleManagementPolicies/$P0/rules/Expiration_EndUser_Assignment" -Body @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT5H'; target = $Exp0['target'] }
Write-OerLiveStep "PATCH 1 (Expiration_EndUser_Assignment, PT5H) to the id listed before: $($R1.Status) $($R1.Code)"
$P1 = Get-S1111ListedPolicy
Write-OerLiveStep "Listed policy id after PATCH 1 is the one before: $($P1 -eq $P0)"
$R2 = Invoke-OerLiveGraph -Method PATCH -Uri "$PimBase/roleManagementPolicies/$P0/rules/Enablement_EndUser_Assignment" -Body @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'; id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification', 'Ticketing'); target = $Ena0['target'] }
Write-OerLiveStep "PATCH 2 (Enablement_EndUser_Assignment, Justification and Ticketing) to the id listed before: $($R2.Status) $($R2.Code)"
Start-Sleep -Seconds 15
$P2 = Get-S1111ListedPolicy
$Exp2 = Get-S1111Rule -PolicyId $P2 -RuleId 'Expiration_EndUser_Assignment'
$Ena2 = Get-S1111Rule -PolicyId $P2 -RuleId 'Enablement_EndUser_Assignment'
Write-OerLiveStep "Listed policy id after PATCH 2 is the one before: $($P2 -eq $P0); on the listed policy: maximumDuration $([string]$Exp2['maximumDuration']), enabledRules [$(@($Ena2['enabledRules']) -join ',')]"
if ($P2 -ne $P0) {
    $ExpOld = Get-S1111Rule -PolicyId $P0 -RuleId 'Expiration_EndUser_Assignment'
    $EnaOld = Get-S1111Rule -PolicyId $P0 -RuleId 'Enablement_EndUser_Assignment'
    Write-OerLiveStep "On the id listed before: maximumDuration $([string]$ExpOld['maximumDuration']), enabledRules [$(@($EnaOld['enabledRules']) -join ',')]"
}
Disconnect-OerLive
```

**Expect:** a measurement: whether the listed id changes after the first PATCH, and whether PATCH 2 reaches the
policy listed afterwards (`enabledRules [Justification,Ticketing]` there; the default is `[Justification]`).
**Failure looks like:** a 401 or 403 (STOP).

Result:

### 1.4. BL-97 F3: the same first call through `Set-OERGroupPimPolicy`

- [ ] **1.4** On `oer-s1111-pimcmd`, one `Set-OERGroupPimPolicy` call with two rules (maximum activation 5 hours, and justification and a ticket on activation): both rules are on the policy Microsoft Graph lists afterwards. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Ids = Get-S1111Ids
$Gid = $Ids['pimcmd']
$Out = Set-OERGroupPimPolicy -Id $Gid -AccessType member -ActivationMaxHours 5 -ActivationEnabledRules Justification, Ticketing -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable SetErrors -WarningVariable SetWarnings 3>$null
Write-OerLiveStep "Set-OERGroupPimPolicy: Applied $($Out.Applied); errors: $(@(Get-S1111FirstId $SetErrors) -join ', '); warnings (counted): $(@($SetWarnings).Count)"
Start-Sleep -Seconds 15
$Filter = [uri]::EscapeDataString("scopeId eq '$Gid' and scopeType eq 'Group'")
$L = Invoke-OerLiveGraph -All -Uri "$PimBase/roleManagementPolicyAssignments?`$filter=$Filter"
$Listed = [string](@(@($L.Body['value']) | Where-Object { [string]$_['roleDefinitionId'] -eq 'member' })[0]['policyId'])
$Exp = (Invoke-OerLiveGraph -Uri "$PimBase/roleManagementPolicies/$Listed/rules/Expiration_EndUser_Assignment").Body
$Ena = (Invoke-OerLiveGraph -Uri "$PimBase/roleManagementPolicies/$Listed/rules/Enablement_EndUser_Assignment").Body
Write-OerLiveStep "On the listed policy: maximumDuration $([string]$Exp['maximumDuration']), enabledRules [$(@($Ena['enabledRules']) -join ',')]"
$Read = Get-OERGroupPimPolicy -Id $Gid -AccessType member -ErrorAction SilentlyContinue
Write-OerLiveStep "Get-OERGroupPimPolicy reads the listed policy: $([string]$Read.PolicyId -eq $Listed)"
Disconnect-OerLive
```

**Expect:** a measurement: `PT5H` and `[Justification,Ticketing]` on the listed policy means the cmdlet's single policy id
lookup is enough; anything else is BL-97 F3's defect.
**Failure looks like:** a 401 or 403 (STOP).

Result:

### 1.5. BL-117 sixth point: what Microsoft Graph reads back for `dayOfMonth`, and whether a PUT of the read recurrence is accepted

- [ ] **1.5** `oer-s1111-review`, created with `dayOfMonth` set to its start day, reads back with a `dayOfMonth`; a PUT that changes only the admin description and sends the recurrence as read is accepted or refused, and the recurrence is read back. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1111Ids
$Def = Invoke-OerLiveGraph -Uri "$Ar/$($Ids['review'])"
$Rec = $Def.Body['settings']['recurrence']
Write-OerLiveStep "Read: pattern $([string]$Rec['pattern']['type']) interval $([string]$Rec['pattern']['interval']) dayOfMonth $([string]$Rec['pattern']['dayOfMonth']); range $([string]$Rec['range']['type']) startDate $([string]$Rec['range']['startDate'])"
$Body = @{}
foreach ($Key in 'displayName', 'descriptionForReviewers', 'scope', 'reviewers', 'settings') { $Body[$Key] = $Def.Body[$Key] }
$Body.descriptionForAdmins = "Omnicit.EntraRBAC live verification ($Prefix): BL-117 measurement, description changed."
$Put = Invoke-OerLiveGraph -Method PUT -Uri "$Ar/$($Ids['review'])" -Body $Body
Write-OerLiveStep "PUT with the recurrence as read: $($Put.Status) $($Put.Code) $($Put.Message)"
Start-Sleep -Seconds 10
$Again = (Invoke-OerLiveGraph -Uri "$Ar/$($Ids['review'])").Body['settings']['recurrence']
Write-OerLiveStep "Read again: dayOfMonth $([string]$Again['pattern']['dayOfMonth']); startDate $([string]$Again['range']['startDate'])"
Disconnect-OerLive
```

**Expect:** a measurement: the `dayOfMonth` Graph returns, and the PUT's answer.
**Failure looks like:** a 401 or 403 (STOP).

Result:

## 2. BL-40: a document that declares one side of an Azure role policy's approvers

### 2.1. The plan keeps the side the document does not declare

- [ ] **2.1** A document that declares only `approvers.users` as empty for Reader at `oer-s1111-rg`, whose live policy requires approval by one user and one group, plans an update that sends the live group side unchanged, and sends no write request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Save-S1111Doc -Name 'bl40' -Json (@{ version = '1.0'; roleManagementPolicies = @(@{ scope = $RgScope; role = 'Reader'; approvers = @{ users = @() } }) } | ConvertTo-Json -Depth 10)
$Ids = Get-S1111Ids
Start-S1111Count
$Plan = Invoke-S1111Apply -Path $Doc -WhatIf -Include RoleManagementPolicies
$Row = @($Plan.Rows)[0]
Write-OerLiveStep "Plan: rows $(@($Plan.Rows).Count); action $($Row.Action); the plan sends the live group: $([string]$Row.Detail -match [regex]::Escape([string]$Ids['apgroup'])); errors: $(@($Plan.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** one row `Skipped` "would update role management policy" whose change list names `users=[]` and the
live group's id under `groups`; no error; Azure Resource Manager writes 0.
**Failure looks like:** a row whose `groups` list is empty (the undeclared side would be removed), a `Failed` row
(a read that failed: rerun once and record it), or a write.

Result:

### 2.2. The run updates the policy and keeps the group approver

- [ ] **2.2** The same document applied: one `Updated` row, and the policy then requires approval by the group alone -- the user side cleared as declared, the group side kept. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Join-Path $Work 'bl40.json'
$ReaderGuid = Get-S1111ReaderGuid
Start-S1111Count -AllowWrite
$Run = Invoke-S1111Apply -Path $Doc -Include RoleManagementPolicies
Write-OerLiveStep "Run: rows $(@($Run.Rows).Count); action $(@($Run.Rows)[0].Action); errors: $(@($Run.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
$Wait = Wait-OerLiveConverged -Activity 'the Reader policy lists the group approver alone' -Read {
    $P = Get-OerLiveArmRolePolicy -Scope $RgScope -RoleDefinitionGuid $ReaderGuid
    $A = @($P.Rules | Where-Object { [string]$_['id'] -eq 'Approval_EndUser_Assignment' })[0]
    , @(@(@($A['setting']['approvalStages'])[0]['primaryApprovers']) | ForEach-Object { [string]$_['userType'] })
} -Test { $K = @($args[0]); @($K | Where-Object { $_ -eq 'Group' }).Count -eq 1 -and @($K | Where-Object { $_ -eq 'User' }).Count -eq 0 }
Write-OerLiveStep "After the run: approvers users $(@(@($Wait.Value) | Where-Object { $_ -eq 'User' }).Count), groups $(@(@($Wait.Value) | Where-Object { $_ -eq 'Group' }).Count)"
Disconnect-OerLive
```

**Expect:** one `Updated` row; no error; exactly one Azure Resource Manager write (the policy PATCH); after it,
approvers users 0, groups 1.
**Failure looks like:** groups 0 (the undeclared side was removed: the defect), or a `Failed` row.

Result:

### 2.3. The same document again changes nothing (G8)

- [ ] **2.3** The same document applied a second time: one `Unchanged` row and no write request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Join-Path $Work 'bl40.json'
Start-S1111Count
$Again = Invoke-S1111Apply -Path $Doc -Include RoleManagementPolicies
Write-OerLiveStep "Second run: rows $(@($Again.Rows).Count); action $(@($Again.Rows)[0].Action); errors: $(@($Again.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** one `Unchanged` row; no error; writes 0.
**Failure looks like:** an `Updated` row (the run does not converge) or a refused write.

Result:

## 3. BL-38: a top-level section that is null

### 3.1. No row and no Azure Resource Manager token

- [ ] **3.1** In a session that holds no Azure Resource Manager token, a document whose `roleManagementPolicies` and `roleAssignments` are `null` beside one group entry gives the group's row only, requests no token and sends no Azure Resource Manager request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
# The module session again, Microsoft Graph only: -Force rebuilds it without an Azure Resource Manager token.
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
try { $null = Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -Force -ErrorAction Stop } finally { $Cert = $null }
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "Before: the session holds an Azure Resource Manager token: $([bool](& $Module { $script:_OERAuthState.ArmToken }))"
$Doc = Save-S1111Doc -Name 'bl38' -Json '{ "version": "1.0", "groups": [ { "displayName": "oer-s1111-apgroup" } ], "roleManagementPolicies": null, "roleAssignments": null }'
$global:S1111TokenCalls = 0
Start-S1111Count
$Run = Invoke-S1111Apply -Path $Doc
Write-OerLiveStep "Rows: $(@($Run.Rows).Count) ($(@($Run.Rows | ForEach-Object { "$($_.Section) $($_.Action)" }) -join '; ')); errors: $(@($Run.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Write-OerLiveStep "After: the session holds an Azure Resource Manager token: $([bool](& $Module { $script:_OERAuthState.ArmToken }))"
Disconnect-OerLive
```

**Expect:** `Before: ... False`; one row, `groups Unchanged`; no error; token requests 0; Azure Resource Manager
requests 0; writes 0; `After: ... False`.
**Failure looks like:** a `roleManagementPolicies` row (scope '' refused), a token request, or `After: ... True`.

Result:

## 4. BL-113: the plan says what the run does for a policy that would require approval by nobody

### 4.1. A directory role policy

- [ ] **4.1** For Reports Reader, a document declaring `requireApproval: true` and `approvers.users: []`, against a live policy without approvers, gives the same `Failed` row with `ApproverRequired` in the plan and in the run, and sends no write request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Live = Get-OerLiveDirectoryRolePolicy -RoleName 'Reports Reader'
$A = @($Live.Rules | Where-Object { [string]$_['id'] -eq 'Approval_EndUser_Assignment' })[0]
Write-OerLiveStep "Reports Reader live: approval required $([bool]$A['setting']['isApprovalRequired']); approvers in the first stage $(@(@(@($A['setting']['approvalStages'])[0]['primaryApprovers']) | Where-Object { $null -ne $_ }).Count)"
$Doc = Save-S1111Doc -Name 'bl113-dir' -Json '{ "version": "1.0", "directoryRoleManagementPolicies": [ { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [] } } ] }'
Start-S1111Count
$Plan = Invoke-S1111Apply -Path $Doc -WhatIf -Include DirectoryRoleManagementPolicies
$Run = Invoke-S1111Apply -Path $Doc -Include DirectoryRoleManagementPolicies
Write-OerLiveStep "Plan: $(@($Plan.Rows)[0].Action), errors $(@($Plan.Errors) -join ', '); run: $(@($Run.Rows)[0].Action), errors $(@($Run.Errors) -join ', '); the same Detail: $(@($Plan.Rows)[0].Detail -ceq @($Run.Rows)[0].Detail)"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** live approval not required, 0 approvers; plan `Failed`, errors `ApproverRequired`; run `Failed`, errors
`ApproverRequired`; the same Detail `True`; Microsoft Graph writes 0.
**Failure looks like:** a plan row `Skipped` "would update" (the defect), or a write.

Result:

### 4.2. A group's PIM policy

- [ ] **4.2** For `oer-s1111-pimcmd` (onboarded in 1.4), a document declaring `pimPolicy.member.requireApproval: true` and `approvers.users: []`, against a live member policy without approvers, gives the same `Failed` row with `ApproverRequired` in the plan and in the run, and sends no write request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Save-S1111Doc -Name 'bl113-group' -Json '{ "version": "1.0", "groups": [ { "displayName": "oer-s1111-pimcmd", "pimPolicy": { "member": { "requireApproval": true, "approvers": { "users": [] } } } } ] }'
Start-S1111Count
$Plan = Invoke-S1111Apply -Path $Doc -WhatIf -Include Groups
$Run = Invoke-S1111Apply -Path $Doc -Include Groups
$PlanRow = @($Plan.Rows | Where-Object { [string]$_.Detail -like 'pimPolicy*' -or [string]$_.Detail -like '*pimPolicy (member)*' })
$RunRow = @($Run.Rows | Where-Object { [string]$_.Detail -like 'pimPolicy*' -or [string]$_.Detail -like '*pimPolicy (member)*' })
Write-OerLiveStep "Plan pimPolicy rows: $($PlanRow.Count) ($(@($PlanRow | ForEach-Object { $_.Action }) -join ', ')), errors $(@($Plan.Errors) -join ', '); run: $($RunRow.Count) ($(@($RunRow | ForEach-Object { $_.Action }) -join ', ')), errors $(@($Run.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** one pimPolicy row `Failed` in the plan and in the run, errors `ApproverRequired` in both; Microsoft
Graph writes 0.
**Failure looks like:** a plan row "would set pimPolicy" (the defect), or a write.

Result:

## 5. The validator and the structure document reader

### 5.1. BL-139: a token value with `$` is inserted as text

- [ ] **5.1** A group declared by `template` `oer-s1111-{a}` with `tokens.a` = `x$$y$&z$_` is valid, and the plan names the group `oer-s1111-x$$y$&z$_` exactly. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Save-S1111Doc -Name 'bl139-dollar' -Json '{ "version": "1.0", "groups": [ { "template": "oer-s1111-{a}", "tokens": { "a": "x$$y$&z$_" } } ] }'
$V = Test-OERStructure -Path $Doc
Write-OerLiveStep "Test-OERStructure: Valid $($V.Valid); errors $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
Start-S1111Count
$Plan = Invoke-S1111Apply -Path $Doc -WhatIf -Include Groups
Write-OerLiveStep "The plan names the group exactly as written: $(@($Plan.Rows | Where-Object { $_.Item -ceq 'oer-s1111-x$$y$&z$_' }).Count -ge 1)"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** Valid `True`, errors 0; the plan names the group exactly as written `True`; writes 0.
**Failure looks like:** `False` (a `$` read as a substitution: `$$` becomes `$`, `$&` the token text).

Result:

### 5.2. BL-139: a template that cannot be resolved is an Error

- [ ] **5.2** A group whose template names a token the entry does not give is refused by `Test-OERStructure` with an Error at its `template`, and `Invoke-OERStructure` refuses the document before any request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Doc = Save-S1111Doc -Name 'bl139-unresolved' -Json '{ "version": "1.0", "groups": [ { "template": "oer-s1111-{a}-{b}", "tokens": { "a": "x" } } ] }'
$V = Test-OERStructure -Path $Doc
Write-OerLiveStep "Test-OERStructure: Valid $($V.Valid); errors at the template: $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' -and [string]$_.Path -like '*template*' }).Count)"
$global:S1111TokenCalls = 0
Start-S1111Count
$Run = Invoke-S1111Apply -Path $Doc
Write-OerLiveStep "Invoke-OERStructure: rows $(@($Run.Rows).Count); errors $(@($Run.Errors) -join ', ')"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
Disconnect-OerLive
```

**Expect:** Valid `False`, one Error at the template; rows 0, errors `StructureValidationFailed`; no request.
**Failure looks like:** Valid `True` (the template is silently left out), or a `Failed` row from the engine.

Result:

### 5.3. BL-154: a display name in date-and-time form reaches the validator and the engine as written

- [ ] **5.3** A document whose group `displayName` is `2026-01-01T10:00:00` is read with that exact string, and `Test-OERStructure` finds no error. #type/subtask

```powershell
& (Get-Module -Name OerLive) { Import-OerLiveModule }
$Doc = Save-S1111Doc -Name 'bl154-date' -Json '{ "version": "1.0", "groups": [ { "displayName": "2026-01-01T10:00:00" } ] }'
$Read = & (Get-Module -Name Omnicit.EntraRBAC) { param($P) Read-OERStructureDocument -Path $P } $Doc
$Name = $Read.groups[0].displayName
Write-OerLiveStep "PowerShell $($PSVersionTable.PSVersion); read as $($Name.GetType().Name), exactly as written: $($Name -is [string] -and $Name -ceq '2026-01-01T10:00:00')"
$V = Test-OERStructure -Path $Doc
Write-OerLiveStep "Test-OERStructure: Valid $($V.Valid); errors $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
```

**Expect:** read as `String`, exactly as written `True`; Valid `True`, errors 0. (On a PowerShell before 7.5 the
validator refuses it instead; B.4 proves that offline.)
**Failure looks like:** `DateTime`, or a string in another form.

Result:

### 5.4. BL-154: a structure document that cannot be read says why

- [ ] **5.4** A document file locked by another handle gives one `InvalidStructureDocument` whose message says it could not be read, and never "is empty". #type/subtask

```powershell
& (Get-Module -Name OerLive) { Import-OerLiveModule }
$Doc = Save-S1111Doc -Name 'bl154-locked' -Json '{ "version": "1.0" }'
$Lock = [System.IO.File]::Open($Doc, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $V = Test-OERStructure -Path $Doc -ErrorAction SilentlyContinue -ErrorVariable ReadErrors
} finally { $Lock.Dispose() }
$Own = @($ReadErrors | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('InvalidStructureDocument', [System.StringComparison]::Ordinal) })
Write-OerLiveStep "Records InvalidStructureDocument: $($Own.Count); says it could not be read: $([string]$Own[0].Exception.Message -like '*could not be read*'); says empty: $([string]$Own[0].Exception.Message -like '*empty*')"
```

**Expect:** 1 record; could not be read `True`; empty `False`.
**Failure looks like:** "The structure document is empty." (the old false reason).

Result:

## 6. BL-53: a host that cannot show the confirmation prompt

### 6.1. A thread job: refused before anything is read

- [ ] **6.1** `Invoke-OERStructure` without `-Confirm:$false` and without `-WhatIf`, in a thread job (a host with no user interface), is refused with `ConfirmationUnavailable` before any sign-in. #type/subtask

```powershell
& (Get-Module -Name OerLive) { Import-OerLiveModule }
$Psd1 = (Get-Module -Name Omnicit.EntraRBAC).Path -replace '\.psm1$', '.psd1'
$Doc = Save-S1111Doc -Name 'bl53' -Json '{ "version": "1.0", "groups": [ { "displayName": "oer-s1111-apgroup", "description": "BL-53 measurement" } ] }'
$Job = Start-ThreadJob -ScriptBlock {
    param($Psd1, $Doc)
    Import-Module $Psd1 -Force
    $Rows = @(Invoke-OERStructure -Path $Doc -ErrorAction SilentlyContinue -ErrorVariable E)
    [PSCustomObject]@{ Host = $Host.Name; Rows = $Rows.Count; Ids = @($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) }
} -ArgumentList $Psd1, $Doc
$R = $Job | Wait-Job -Timeout 120 | Receive-Job
Remove-Job -Job $Job -Force
Write-OerLiveStep "Thread job host '$($R.Host)': rows $($R.Rows); records: $(@($R.Ids) -join ', ')"
```

**Expect:** host `Default Host`; rows 0; records `ConfirmationUnavailable` and nothing else.
**Failure looks like:** a sign-in attempt, a `Failed` row "handler error", or no record.

Result:

### 6.2. A non-interactive console: the row says what is missing, and nothing is written

- [ ] **6.2** Run with `-NonInteractive`: `Invoke-OERStructure` without `-Confirm:$false` on a document that changes the description of `oer-s1111-apgroup` gives a `Failed` row that says the host cannot show the confirmation prompt, sends no write, and the description is unchanged. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1111NoPrompt
$Ids = Get-S1111Ids
$Before = [string](Invoke-OerLiveGraph -Uri "v1.0/groups/$($Ids['apgroup'])?`$select=description").Body['description']
$Doc = Save-S1111Doc -Name 'bl53-console' -Json '{ "version": "1.0", "groups": [ { "displayName": "oer-s1111-apgroup", "description": "BL-53 measurement" } ] }'
Start-S1111Count
$Rows = @(Invoke-OERStructure -Path $Doc -Include Groups -ErrorAction SilentlyContinue -ErrorVariable E 3>$null)
foreach ($Row in $Rows) { Write-OerLiveStep "Row: [$($Row.Section)] $($Row.Item) $($Row.Action) -- $($Row.Detail)" }
Write-OerLiveStep "Rows: $($Rows.Count); says the prompt cannot be shown: $(@($Rows | Where-Object { [string]$_.Detail -like '*cannot show the confirmation prompt*' }).Count -ge 1)"
Write-OerLiveStep (Get-S1111Sent)
Stop-S1111Count
$After = [string](Invoke-OerLiveGraph -Uri "v1.0/groups/$($Ids['apgroup'])?`$select=description").Body['description']
Write-OerLiveStep "The description is unchanged: $($After -ceq $Before)"
Disconnect-OerLive
```

**Expect:** one `Failed` row; says the prompt cannot be shown `True`; writes 0; unchanged `True`.
**Failure looks like:** "handler error: Exception calling ShouldProcess ... NonInteractive mode" alone (the old
text), or a write.

Result:

## B. Proved offline (class B)

- **B.1** A failed read of the live Azure role policy, non-terminating and terminating, with an entry that
  declares one approver side, in a run, under `-WhatIf` and in a script with no `try`: one `Failed` row with the
  read's record, and no write (`tests/Unit/Private/Sync-OERStructureRoleManagementPolicy.Tests.ps1`,
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`).
- **B.2** A failed read of a group's PIM policy: `Failed`, nothing written for that access type
  (`tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1`).
- **B.3** An unread role name map stops only an administrative unit's scoped roles
  (`tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1`).
- **B.4** A PowerShell without `ConvertFrom-Json -DateKind`: the validator refuses a value read as a date
  (`tests/Unit/Private/Read-OERStructureDocument.Tests.ps1`, `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`).
- **B.5** A split answer to the two `-Confirm` prompts of `Set-OERGroupPimPolicy`
  (`tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1`).

## T. Teardown

### T.1. Remove every object and restore both policies

- [ ] **T.1** `Initialize-OerS1111Prereq.ps1 -Teardown -Unattended` deletes the review, restores the Reader policy at the resource group and the Reports Reader policy from their baselines, removes every prefixed object and the resource group, and the sweep finds nothing. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1111Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "The teardown ended with exit code $LASTEXITCODE."
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1111Prereq.ps1') -ReadBack
Write-OerLiveStep "The read-back ended with exit code $LASTEXITCODE."
```

**Expect:** the review deleted; both policies restored (`True`); every object removed; the resource group gone;
no prefixed object left; the counts equal to the baseline; exit codes 0.
**Failure looks like:** a policy not restored (STOP, G11.5), residue, or a count that differs.

Result:
