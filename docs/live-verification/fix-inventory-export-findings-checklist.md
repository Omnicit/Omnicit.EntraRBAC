# Live verification checklist -- every unread inventory read is reported, and an export is stable (fix/inventory-export-findings)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4, 5, 6 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be
impossible to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked `[~]`, never
`[x]`. **Section B lists what is proved offline only (class B).** No manual check (class C) is foreseen.

**What this file writes to the tenant.** Only the prerequisite script writes, and only objects whose names start
with `oer-s1110-`: two disabled users, a dynamic security group whose rule lists them, two groups named
`oer-s1110-twin-a` and two named `oer-s1110-twin-b`, a group `oer-s1110-nested`, a group `oer-s1110-typed`
whose members are a user, that group and the service principal of `oer-live-cc-noperm` (which is not changed),
and a group `oer-s1110-pim` with a time-bound PIM-for-Groups member eligibility of each user. Teardown (T.1)
removes them all. Every check reads, except 1.4, which applies a document of those prefixed groups only, with a
fence that refuses any write request (G8); the exports and the comparison files go under the step's raw folder,
`raw\s1110\`, which is deleted after the results are written.

**The tenant's object names are never printed.** An export names the tenant's groups and their members. Every
export here is limited to the prefixed groups (`-GroupFilter`), and the blocks print counts, True/False and
the step's own prefixed names only; the export's own warnings are captured and counted, never printed. The
roster lists every security group of the tenant: only its prefixed rows are read.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives
beside the operator's copy of this file outside the repository ([README.md](README.md), first paragraph).
Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or 403 is a stop,
except in 3.1, which tests exactly a scope the reader cannot read.

**Permissions.** The reads use the permissions `oer-live-cc` already holds; the prerequisite script checks the
three it needs to write (User.ReadWrite.All, Group.ReadWrite.All and
PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup) and is refused without them. Granting a permission is the
operator's decision, never this checklist's.

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

- **A. Reads that became empty or silent** (BL-34, BL-155, BL-123, BL-58, BL-44). `Get-OERInventory` reports a
  failed RoleAssignments or RoleManagementPolicies read as an unread section through `InventoryPartial`, refuses
  a `-Scope`, `-Subscription` or `-ManagementGroup` of white space at binding, and reads a subscription named by
  its display name with the id its home-tenant check resolved. `Export-OERInventory` reports a stop in its Azure
  eligibility, Lighthouse or role policy selection read as incomplete, warns about `-AllRolePolicies` and
  `-AllDirectoryRolePolicies` without their section, and writes one warning for a scope it skips.
- **B. What the export writes** (BL-43, BL-121, BL-45, BL-101, BL-156). A dynamic group's members are written as
  null and read for no PIM decision; members, owners, eligibility and unit members are written in a fixed order;
  an export whose own sign-in is refused writes no bundle; every shared display name is a cause of its own.
- **C. Cost and measurements** (BL-122, BL-24, BL-21, BL-83).
- **D. The texts** (BL-46, BL-48).

A live tenant is needed for what the unit tests cannot show: that Microsoft Graph's own order of members does
not reach the file, a dynamic group whose rule really lists members, two real groups sharing a name, an Azure
scope the identity cannot read, a tenant name the discovery lookup refuses, and the measurements themselves.

## What this file does not check, and why

- **A session that names no tenant (class B, B.1).** An app-only sign-in always names its tenant, so the bundle
  folder named after the granted tenant id under `organizations` or no tenant is proved offline.
- **A stop in the export's Azure eligibility, Lighthouse or role policy selection read (class B, B.2),** and
  **a scope whose role assignments and policy list both fail (B.3).** Neither failure can be induced in the
  test tenant without changing the identity's permissions.
- **A refused Azure Resource Manager token in the export's sign-in (class B, B.4).**
- **The read order of a catalog's packages and resources, and the shared principal name cache (class B, B.5).**
- **The order of an administrative unit's members (class B, B.6).** No prefixed unit is created.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`,
  and the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it, so
  the module loads from the worktree's build; the main clone is never checked out on another commit or branch
  (S.1 reads that it was not).
- The **prerequisite script** `Initialize-OerS1110Prereq.ps1` beside OerLive (0.2 runs it; T.1 removes what it
  created).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the counters and the
readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1110-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Work = Join-Path $Raw 'exports'
$null = New-Item -ItemType Directory -Path $Work -Force
$Prefix = 'oer-s1110-'
$GroupFilter = "startswith(displayName,'$Prefix')"

function Start-S1110NoPrompt {
    # A token request without the certificate would be an interactive or device-code sign-in: refuse it.
    $global:S1110TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S1110TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S1110 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S1110Count {
    # Counts every request the module sends, and REFUSES every write: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest, the tenant lookup through
    # one of Invoke-RestMethod. Each entry is the method and the path with every GUID segment written {id}; the
    # full request text is kept in memory (and in the raw folder) for the checks that look for one object's id,
    # and never printed. getByIds and getEntities are reads sent as POST.
    $global:S1110TokenCalls = 0
    $global:S1110Lookups = 0
    $global:S1110Graph = [System.Collections.Generic.List[string]]::new()
    $global:S1110GraphRaw = [System.Collections.Generic.List[string]]::new()
    $global:S1110Arm = [System.Collections.Generic.List[string]]::new()
    $global:S1110ArmRaw = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Fence = 'if ($M -ne ''GET'' -and $S -notlike ''POST */getByIds'' -and $S -notlike ''POST */getEntities'') { throw ''S1110 fence: a write request was refused.'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1110Shape -Uri ([string]`$Uri)); `$global:S1110Graph.Add(`$S); `$global:S1110GraphRaw.Add(`$M + ' ' + [string]`$Uri); $Fence; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1110Shape -Uri ([string]`$Uri)); `$global:S1110Arm.Add(`$S); `$global:S1110ArmRaw.Add(`$M + ' ' + [string]`$Uri); $Fence; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-RestMethod -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S1110Lookups++; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-RestMethod -Value ([scriptblock]::Create($Text))
}

function global:Get-S1110Shape {
    # The request's path with each GUID segment as {id}.
    param([string]$Uri)
    $Path = $Uri
    if ([uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) { $Path = ([uri]$Uri).AbsolutePath }
    elseif ($Uri.Contains('?')) { $Path = $Uri.Substring(0, $Uri.IndexOf('?')) }
    $Path = '/' + $Path.TrimStart('/')
    $Path -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}'
}

function Stop-S1110Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest', 'Invoke-RestMethod') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S1110Sent {
    # Totals and writes since Start-S1110Count.
    $GraphWrites = @($global:S1110Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getByIds' })
    $ArmWrites = @($global:S1110Arm | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getEntities' })
    "token requests: $global:S1110TokenCalls; tenant lookups: $global:S1110Lookups; Microsoft Graph requests: $($global:S1110Graph.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S1110Arm.Count), writes: $($ArmWrites.Count)"
}

function Get-S1110Ids {
    # The ids the prerequisite script recorded (key -> id), never printed.
    $Path = Join-Path $Raw 'created-s1110.json'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{} }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Get-S1110FirstId {
    # The first segment of each record's FullyQualifiedErrorId, in order.
    param($Records)
    @(@($Records) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
}

function Compare-S1110Text {
    # Ordinal, letter case ignored, ties broken ordinally: the order an export writes (R-16).
    param([string]$X, [string]$Y)
    $C = [string]::Compare($X, $Y, [System.StringComparison]::OrdinalIgnoreCase)
    if ($C -ne 0) { return $C }
    [string]::CompareOrdinal($X, $Y)
}

function Test-S1110Order {
    # True when each item compares at most equal to the next one.
    param([object[]]$Items, [scriptblock]$Compare)
    for ($I = 1; $I -lt @($Items).Count; $I++) { if ((& $Compare $Items[$I - 1] $Items[$I]) -gt 0) { return $false } }
    $true
}

$S1110TextOrder = { param($A, $B) Compare-S1110Text -X ([string]$A) -Y ([string]$B) }
$S1110EligibilityOrder = {
    param($A, $B)
    $C = Compare-S1110Text -X ([string]$A.principal) -Y ([string]$B.principal)
    if ($C -ne 0) { return $C }
    $C = Compare-S1110Text -X ([string]$A.accessType) -Y ([string]$B.accessType)
    if ($C -ne 0) { return $C }
    $DA = if ($null -eq $A.durationDays) { -1 } else { [int]$A.durationDays }
    $DB = if ($null -eq $B.durationDays) { -1 } else { [int]$B.durationDays }
    $DA.CompareTo($DB)
}

function Save-S1110Export {
    # One export of the prefixed groups, read in full, into a folder of its own; its requests, files, errors and
    # partial messages go to a JSON file named after it in the raw folder, for the later checks.
    param([Parameter(Mandatory)][string]$Name)
    $Out = Join-Path $Work "export-$Name"
    $null = New-Item -ItemType Directory -Path $Out -Force
    Start-S1110Count
    $Params = @{ OutputPath = $Out; Include = 'Groups'; GroupFilter = $GroupFilter; AllGroupsDetailed = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'ExportErrors'; WarningVariable = 'ExportWarnings' }
    $Bundle = Export-OERInventory @Params 3>$null
    $Sent = Get-S1110Sent
    $Record = [ordered]@{
        Name = $Name; Sent = $Sent
        Graph = @($global:S1110Graph); GraphRaw = @($global:S1110GraphRaw); Arm = @($global:S1110Arm)
        Files = @($Bundle.Files); IncompleteReads = @($Bundle.IncompleteReads)
        Errors = @(Get-S1110FirstId $ExportErrors)
        Partials = @(@($ExportErrors) | Where-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] -eq 'InventoryPartial' } | ForEach-Object { $_.Exception.Message })
        Warnings = @($ExportWarnings).Count
        Dir = [string]$Bundle.BundlePath
    }
    Stop-S1110Count
    $Record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw "$Name.json") -Encoding utf8NoBOM
    [PSCustomObject]$Record
}

function Read-S1110Export {
    # A record Save-S1110Export wrote in an earlier block.
    param([Parameter(Mandatory)][string]$Name)
    Get-Content -LiteralPath (Join-Path $Raw "$Name.json") -Raw | ConvertFrom-Json
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
    'reports a failed role assignment read' = 'Could not read role assignments: '
    'warns about -AllRolePolicies'          = 'has no effect, since -Include does not name RoleManagementPolicies'
    'stops on a refused sign-in under Ignore' = '$SignInSplat.ErrorAction = ''SilentlyContinue'''
}
$Found = @(foreach ($Key in $Marks.Keys) { '{0}: {1}' -f $Key, [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Marks[$Key] -Quiet) })
Write-OerLiveStep "The branch build ($((Split-Path -Leaf (Split-Path -Parent $Psm1.FullName)))): $($Found -join '; ')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; `True` on every mark.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a `False`
mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: not run yet.

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, `The module is the worktree's build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result: not run yet.

### 0.2. The prerequisite objects

- [ ] **0.2** `Initialize-OerS1110Prereq.ps1 -Unattended` checks the permissions, writes the baseline, creates the step's objects and waits until the dynamic group's rule lists both users. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1110Prereq.ps1') -Unattended
Write-OerLiveStep "The prerequisite script ended with exit code $LASTEXITCODE."
```

**Expect:** the three permissions `True`; a baseline written (or found); the ten objects created or found; the
eligibility requests answered without a `Failed` status; the dynamic group listing both users; exit code 0.
**Failure looks like:** a refusal (a missing permission, an unknown prefixed object), a `NOTE` that the dynamic
group did not list both users within 15 minutes (1.2 then says so), or exit code 1 or 3.

Result: not run yet.

### 0.3. Read back what the prerequisite script created

- [ ] **0.3** Each recorded object is there: both users, the dynamic group with its two members, four twin groups, the nested group, the typed group with its three members, and two member eligibilities in the PIM group. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1110Ids
Write-OerLiveStep "Recorded ids: $($Ids.Count) ($(@($Ids.Keys | Sort-Object) -join ', '))"
foreach ($Key in 'dyn', 'typed', 'nested', 'twin-a-1', 'twin-a-2', 'twin-b-1', 'twin-b-2', 'pim') {
    $G = Invoke-OerLiveGraph -Uri "v1.0/groups/$($Ids[$Key])?`$select=displayName,groupTypes,securityEnabled,membershipRuleProcessingState"
    $Members = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids[$Key])/members?`$select=id"
    Write-OerLiveStep "$($Key): read $($G.Status); name $([string]$G.Body['displayName']); dynamic $(@($G.Body['groupTypes']) -contains 'DynamicMembership'); security $($G.Body['securityEnabled']); members $(@($Members.Body['value']).Count)"
}
$Filter = [uri]::EscapeDataString("groupId eq '$($Ids['pim'])'")
$Elig = Invoke-OerLiveGraph -All -Uri "beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=$Filter"
Write-OerLiveStep "pim: eligibility schedules $(@($Elig.Body['value']).Count), member $(@(@($Elig.Body['value']) | Where-Object { [string]$_['accessId'] -eq 'member' }).Count)"
Disconnect-OerLive
```

**Expect:** 10 recorded ids; `dyn` dynamic with 2 members; `typed` with 2 members through this untyped read,
since its third member, the service principal, is the untyped read's known gap (6.2 measures it; the module reads
service principal members typed, and 1.1 shows all 3); `nested`, the four twins and `pim` with 0 members; `pim`
with 2 member eligibility schedules.
**Failure looks like:** a missing id, a read that is not 200, or `dyn` with fewer than 2 members.

Result: not run yet.

## 1. A stable export, and a dynamic group's members

### 1.1. Two exports in a row are equal, and write members, owners and eligibility in the fixed order

- [ ] **1.1** Two exports of the prefixed groups, read in full, one after the other, send no write and write the same files, byte for byte apart from the folder's time stamp; every member, owner and eligibility list in them is in the fixed order. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$A = Save-S1110Export -Name 'first'
$B = Save-S1110Export -Name 'second'
foreach ($R in $A, $B) { Write-OerLiveStep "$($R.Name): $($R.Sent); files $(@($R.Files).Count); IncompleteReads $(@($R.IncompleteReads).Count); errors: $(@($R.Errors | Sort-Object -Unique) -join ', '); warnings (counted, not printed): $($R.Warnings)" }
$StampA = (Split-Path -Leaf $A.Dir) -replace '^.*-(\d{8}-\d{6})$', '$1'
$StampB = (Split-Path -Leaf $B.Dir) -replace '^.*-(\d{8}-\d{6})$', '$1'
Write-OerLiveStep "The two folder names differ only in their time stamp: $(((Split-Path -Leaf $A.Dir).Replace($StampA, 'STAMP')) -ceq ((Split-Path -Leaf $B.Dir).Replace($StampB, 'STAMP')))"
Write-OerLiveStep "The folder carries the tenant the session named: $((Split-Path -Leaf $A.Dir) -like "oer-inventory-$((& (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState.TenantId }))-*")"
$NamesA = @(Get-ChildItem -LiteralPath $A.Dir -File | ForEach-Object Name | Sort-Object)
$NamesB = @(Get-ChildItem -LiteralPath $B.Dir -File | ForEach-Object Name | Sort-Object)
Write-OerLiveStep "Same file names: $(($NamesA -join ',') -ceq ($NamesB -join ',')) ($($NamesA.Count) files)"
foreach ($F in $NamesA) {
    $TA = (Get-Content -LiteralPath (Join-Path $A.Dir $F) -Raw).Replace($StampA, 'STAMP')
    $TB = (Get-Content -LiteralPath (Join-Path $B.Dir $F) -Raw).Replace($StampB, 'STAMP')
    Write-OerLiveStep "$($F): identical apart from the time stamp: $($TA -ceq $TB)"
}
$Doc = Get-Content -LiteralPath (Join-Path $A.Dir 'inventory.json') -Raw | ConvertFrom-Json
$Groups = @($Doc.groups)
Write-OerLiveStep "inventory.json: groups $($Groups.Count), every one prefixed: $(@($Groups | Where-Object { -not ([string]$_.displayName).StartsWith($Prefix) }).Count -eq 0)"
foreach ($G in $Groups) {
    $Parts = foreach ($Key in 'members', 'owners', 'eligibility') {
        $Has = $G.PSObject.Properties.Name -contains $Key
        # A plain assignment: an if statement's output would unroll an empty list to $null.
        $Value = $null
        if ($Has) { $Value = $G.$Key }
        $State = if (-not $Has) { 'omitted' } elseif ($null -eq $Value) { 'null' } else {
            $Order = if ($Key -eq 'eligibility') { $S1110EligibilityOrder } else { $S1110TextOrder }
            "$(@($Value).Count), in order $(Test-S1110Order -Items @($Value) -Compare $Order)"
        }
        "$Key $State"
    }
    Write-OerLiveStep "$($G.displayName): $($Parts -join '; ')"
}
Disconnect-OerLive
```

**Expect:** both exports `writes: 0` on both transports and `token requests: 0`; the same counts in both; the
folder names equal apart from the time stamp, and the folder carries the tenant the session named; the same file
names, and every file `identical apart from the time stamp: True`; `inventory.json` holds the prefixed groups
other than the four twins, every one prefixed; `oer-s1110-typed` members 3, `oer-s1110-pim` eligibility 2, and
every list `in order True`; `oer-s1110-dyn` members `null` (1.2 reads it further).
**Failure looks like:** a write or a token request; a file that differs; a list `in order False`.

Result: not run yet.

### 1.2. The dynamic group: members null, counted in the roster, and no PIM read for them

- [ ] **1.2** In the first export of 1.1, `oer-s1110-dyn` is written with `dynamic` true and `members` an explicit null, is not named in `IncompleteReads`, has a roster `memberCount` equal to what its rule lists, and no PIM assignment read was sent for it. #type/subtask

```powershell
Connect-OerLive -Arm
$Ids = Get-S1110Ids
$R = Read-S1110Export -Name 'first'
$Doc = Get-Content -LiteralPath (Join-Path $R.Dir 'inventory.json') -Raw | ConvertFrom-Json
$Dyn = @($Doc.groups | Where-Object { $_.displayName -ceq "${Prefix}dyn" })
Write-OerLiveStep "oer-s1110-dyn in inventory.json: $($Dyn.Count); dynamic $($Dyn[0].dynamic); members key present $($Dyn[0].PSObject.Properties.Name -contains 'members'); members null $($null -eq $Dyn[0].members); membershipRule present $([bool]$Dyn[0].membershipRule)"
Write-OerLiveStep "IncompleteReads naming oer-s1110-dyn: $(@($R.IncompleteReads | Where-Object { $_ -like "*${Prefix}dyn*" }).Count)"
$Roster = @(Get-Content -LiteralPath (Join-Path $R.Dir 'groupsRoster.json') -Raw | ConvertFrom-Json)
$Row = @($Roster | Where-Object { $_.displayName -ceq "${Prefix}dyn" })
$Listed = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids['dyn'])/members?`$select=id"
Write-OerLiveStep "Roster row for oer-s1110-dyn: $($Row.Count); dynamic $($Row[0].dynamic); memberCount $($Row[0].memberCount); the rule lists $(@($Listed.Body['value']).Count) now"
$DynId = [string]$Ids['dyn']
Write-OerLiveStep "Requests naming oer-s1110-dyn: $(@($R.GraphRaw | Where-Object { $_ -match [regex]::Escape($DynId) }).Count); of them PIM assignment reads: $(@($R.GraphRaw | Where-Object { $_ -match [regex]::Escape($DynId) -and $_ -like '*assignmentSchedule*' }).Count); members reads: $(@($R.GraphRaw | Where-Object { $_ -match [regex]::Escape($DynId) -and $_ -like '*/members*' }).Count)"
Disconnect-OerLive
```

**Expect:** one entry, `dynamic True`, members key present and `null`, the rule present; 0 `IncompleteReads`
naming it; one roster row, `dynamic True`, `memberCount 2` and the rule listing 2; 0 PIM assignment reads naming
it, and its members read once (the count the roster carries).
**Failure looks like:** a members list, an omitted key, an `IncompleteReads` entry, a null `memberCount`, or a
PIM assignment read naming the group (the base build sends one, which Microsoft Graph answers 400).

Result: not run yet.

### 1.3. -Prune -WhatIf on the export plans no member change for the dynamic group

- [ ] **1.3** `Invoke-OERStructure -Prune -WhatIf` on the first export of 1.1 returns no row about the dynamic group's members, no `Skipped` row, and only `Unchanged` rows; it sends no write. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
Start-S1110Count
$R = Read-S1110Export -Name 'first'
$Rows = @(Invoke-OERStructure -Path (Join-Path $R.Dir 'inventory.json') -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApplyErrors -WarningVariable ApplyWarnings 3>$null)
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
Write-OerLiveStep "Rows: $($Rows.Count); by action: $((@($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', '); errors: $(@(Get-S1110FirstId $ApplyErrors | Sort-Object -Unique) -join ', '); warnings (counted): $(@($ApplyWarnings).Count)"
$DynRows = @($Rows | Where-Object { [string]$_.Item -like "*${Prefix}dyn*" })
Write-OerLiveStep "Rows naming oer-s1110-dyn: $($DynRows.Count); by action: $((@($DynRows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', '); about members: $(@($DynRows | Where-Object { [string]$_.Detail -match 'member' }).Count)"
Write-OerLiveStep "Skipped rows: $(@($Rows | Where-Object { $_.Action -eq 'Skipped' }).Count)"
Disconnect-OerLive
```

**Expect:** `writes: 0` on both transports, `token requests: 0`; every row `Unchanged`; the rows naming
`oer-s1110-dyn` all `Unchanged`, 0 about members; 0 `Skipped` rows; no error.
**Failure looks like:** a row about the dynamic group's members (the base build writes the aggregate `Skipped`
row "the N current member(s) were not reconciled"), a write, or a row other than `Unchanged`.

Result: not run yet.

### 1.4. The document applied twice changes nothing (G8)

- [ ] **1.4** The same document applied for real, with `-Prune`, twice in a row behind the write fence: both runs return only `Unchanged` rows and send no write. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$R = Read-S1110Export -Name 'first'
foreach ($Run in 1, 2) {
    Start-S1110Count
    $Rows = @(Invoke-OERStructure -Path (Join-Path $R.Dir 'inventory.json') -Prune -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ApplyErrors -WarningVariable ApplyWarnings 3>$null)
    Write-OerLiveStep "Run $($Run): $(Get-S1110Sent)"
    Stop-S1110Count
    Write-OerLiveStep "Run $($Run): rows $($Rows.Count); by action: $((@($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', '); errors: $(@(Get-S1110FirstId $ApplyErrors | Sort-Object -Unique) -join ', '); warnings (counted): $(@($ApplyWarnings).Count)"
}
Disconnect-OerLive
```

**Expect:** each run `writes: 0` and every row `Unchanged`, no error.
**Failure looks like:** a row `Failed` whose error is the S1110 fence (the engine tried to write), or any row
other than `Unchanged`.

Result: not run yet.

## 2. Two names, two causes

### 2.1. Each shared display name is a cause of its own in InventoryPartial

- [ ] **2.1** The first export of 1.1 and a `Get-OERInventory -Include Groups` of the prefixed groups each report InventoryPartial whose causes name `oer-s1110-twin-a` and `oer-s1110-twin-b` separately; neither twin is in `inventory.json`, and the roster lists all four. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$R = Read-S1110Export -Name 'first'
$Clause = { param($Message) if ($Message -match 'Causes: (.*)$') { $Matches[1] } else { '' } }
foreach ($Name in 'twin-a', 'twin-b') {
    $Hits = @($R.Partials | Where-Object { (& $Clause $_) -like "*'$Prefix$Name'*" })
    Write-OerLiveStep "Export: partial messages whose causes name $Prefix$($Name): $($Hits.Count)"
}
$Doc = Get-Content -LiteralPath (Join-Path $R.Dir 'inventory.json') -Raw | ConvertFrom-Json
$Roster = @(Get-Content -LiteralPath (Join-Path $R.Dir 'groupsRoster.json') -Raw | ConvertFrom-Json)
Write-OerLiveStep "Export: twins in inventory.json: $(@($Doc.groups | Where-Object { $_.displayName -like "${Prefix}twin-*" }).Count); twin rows in the roster: $(@($Roster | Where-Object { $_.displayName -like "${Prefix}twin-*" }).Count)"
Start-S1110Count
$Out = @(Get-OERInventory -Include Groups -GroupFilter $GroupFilter 2>&1)
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
$Errs = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Inv = @($Out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Get-OERInventory: objects $($Inv.Count); errors: $((Get-S1110FirstId $Errs) -join ', ')"
$Partial = @($Errs | Where-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] -eq 'InventoryPartial' })
$Causes = if ($Partial.Count) { & $Clause $Partial[0].Exception.Message } else { '' }
foreach ($Name in 'twin-a', 'twin-b') { Write-OerLiveStep "Get-OERInventory: the causes name $Prefix$($Name): $($Causes -like "*'$Prefix$Name'*")" }
Write-OerLiveStep "Get-OERInventory: twins in Groups: $(@($Inv[0].Groups | Where-Object { $_.displayName -like "${Prefix}twin-*" }).Count)"
Disconnect-OerLive
```

**Expect:** the export's partial messages name each twin name (1 or more for each); 0 twins in `inventory.json`
and 4 twin rows in the roster; `Get-OERInventory` one object, errors `InventoryPartial` only, its causes naming
both names, 0 twins in `Groups`, no write.
**Failure looks like:** one name missing from the causes (the base build folds the two names into one cause),
or a twin written to the document.

Result: not run yet.

## 3. Azure reads that cannot be read, and a blank scope

### 3.1. A role assignment read that fails is an unread section

- [ ] **3.1** `Get-OERInventory -Include RoleAssignments -ManagementGroup oer-s1110-no-such-group`, in a script with no `try`, writes the inventory with `RoleAssignments` empty, then one InventoryPartial naming `roleAssignments` with the cause, and the script carries on. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
Start-S1110Count
$Out = @(Get-OERInventory -Include RoleAssignments -ManagementGroup "${Prefix}no-such-group" 2>&1)
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
$Errs = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Inv = @($Out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Objects: $($Inv.Count); RoleAssignments rows: $(@($Inv[0].RoleAssignments).Count); the object came before the first error: $([array]::IndexOf($Out, $Inv[0]) -lt [array]::IndexOf($Out, $Errs[0]))"
Write-OerLiveStep "Error stream: $((Get-S1110FirstId $Errs) -join ', ')"
$P = @($Errs | Where-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] -eq 'InventoryPartial' })
Write-OerLiveStep "InventoryPartial names roleAssignments: $(@($P[0].TargetObject) -contains 'roleAssignments'); its cause starts 'Could not read role assignments: ': $([string]$P[0].Exception.Message -like '*Causes: Could not read role assignments: *')"
Write-OerLiveStep 'END: the script carried on.'
$E = $null
$null = Get-OERInventory -Include RoleAssignments -ManagementGroup "${Prefix}no-such-group" -ErrorAction SilentlyContinue -ErrorVariable E
Write-OerLiveStep "The same call with -ErrorVariable (R-17, measured): $((Get-S1110FirstId $E) -join ', ')"
Disconnect-OerLive
```

**Expect:** 0 writes; one object, 0 rows, before the error; the error stream `InventoryPartial` only, naming
`roleAssignments` with the cause; `END`; the `-ErrorVariable` line lists the reader's own record before
`InventoryPartial` (Ruling R-17: the reader's deposit reaches a caller's `-ErrorVariable`, not its error stream).
**Failure looks like:** the reader's own error in the error stream, a missing InventoryPartial, or no `END` line.

Result: not run yet.

### 3.2. A -Scope of white space is refused at binding

- [ ] **3.2** `Get-OERInventory -Include RoleAssignments -Scope '   '` and `Export-OERInventory -Include RoleAssignments -Scope '   '`, in a script with no `try`, are each refused at parameter binding with the white space message, send nothing, and the script carries on. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
Start-S1110Count
$Out1 = @(Get-OERInventory -Include RoleAssignments -Scope '   ' 2>&1)
$Out2 = @(Export-OERInventory -Include RoleAssignments -Scope '   ' -OutputPath (Join-Path $Work 'export-blank') 2>&1)
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
foreach ($Pair in @(@('Get-OERInventory', $Out1), @('Export-OERInventory', $Out2))) {
    $Errs = @($Pair[1] | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    Write-OerLiveStep "$($Pair[0]): objects $(@($Pair[1] | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count); errors: $((Get-S1110FirstId $Errs) -join ', '); the message is the white space one: $([string]$Errs[0].Exception.Message -like '*The Scope consists only of white space. Pass an Azure Resource Manager scope, or leave the parameter out.*')"
}
Write-OerLiveStep "Export folder written: $(Test-Path -LiteralPath (Join-Path $Work 'export-blank'))"
Write-OerLiveStep 'END: the script carried on.'
Disconnect-OerLive
```

**Expect:** 0 requests of every kind; each command 0 objects and one `ParameterArgumentValidationError` whose
message is the white space one; no export folder; `END`.
**Failure looks like:** a request, an object, another message, or no `END` line.

Result: not run yet.

### 3.3. A subscription named by its display name is resolved once and read by its id

- [ ] **3.3** `Get-OERInventory -Include RoleAssignments, RoleManagementPolicies -AllRolesAtScope -Subscription` with the test subscription's display name lists the subscriptions once (the home-tenant check), reads both sections at the subscription's id, never sends the name, and is not partial. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$Sub = Invoke-OerLiveArm -Uri "subscriptions/$($Cfg.SubscriptionId)?api-version=2022-12-01"
$SubName = [string]$Sub.Body['displayName']
Write-OerLiveStep "The test subscription's display name was read (not printed): $(-not [string]::IsNullOrWhiteSpace($SubName))"
Start-S1110Count
$Out = @(Get-OERInventory -Include RoleAssignments, RoleManagementPolicies -AllRolesAtScope -Subscription $SubName 2>&1)
Write-OerLiveStep (Get-S1110Sent)
$ArmRaw = @($global:S1110ArmRaw)
$ArmShapes = @($global:S1110Arm)
Stop-S1110Count
$Errs = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Inv = @($Out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Subscription list reads: $(@($ArmShapes | Where-Object { $_ -ceq 'GET /subscriptions' }).Count); single subscription reads: $(@($ArmShapes | Where-Object { $_ -ceq 'GET /subscriptions/{id}' }).Count)"
Write-OerLiveStep "Role assignment reads at the subscription id: $(@($ArmShapes | Where-Object { $_ -like 'GET /subscriptions/{id}/providers/Microsoft.Authorization/roleAssignments*' }).Count); role management policy reads at the subscription id: $(@($ArmShapes | Where-Object { $_ -like 'GET /subscriptions/{id}/providers/Microsoft.Authorization/roleManagementPolic*' }).Count)"
Write-OerLiveStep "Requests whose text holds the display name: $(@($ArmRaw | Where-Object { $_ -match [regex]::Escape([uri]::EscapeDataString($SubName)) -or $_ -match [regex]::Escape($SubName) }).Count)"
Write-OerLiveStep "Objects: $($Inv.Count); RoleAssignments rows: $(@($Inv[0].RoleAssignments).Count); RoleManagementPolicies rows: $(@($Inv[0].RoleManagementPolicies).Count); errors: $((Get-S1110FirstId $Errs) -join ', ')"
Disconnect-OerLive
```

**Expect:** 0 writes; 1 subscription list read and 0 single subscription reads; the role assignment and policy
reads at `/subscriptions/{id}`; 0 requests holding the name; one object with its rows and no error.
**Failure looks like:** more than one list read (the base build lists the subscriptions once for the check and
once per section), a request holding the name, or an error.

Result: not run yet.

## 4. An export whose own sign-in is refused

### 4.1. A tenant the lookup refuses: no bundle, no folder, and the script carries on

- [ ] **4.1** After a session in the test tenant, `Export-OERInventory -TenantId oer-sovereign-verify-doesnotexist.onmicrosoft.com`, in a script with no `try`, raises the sign-in's own `TenantResolutionFailed` as a terminating error, emits nothing, creates nothing under its output path, sends no Microsoft Graph or Azure Resource Manager request and no token request, and the script carries on with its next statement. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$Out = Join-Path $Work 'export-refused'
$null = New-Item -ItemType Directory -Path $Out -Force
$Before = @(Get-ChildItem -LiteralPath $Out -Force).Count
Start-S1110Count
$Error.Clear()
$Result = $null
# A terminating error ends this statement only (no try here): the assignment never happens, and the record is
# read from $Error, since 2>&1 does not carry a terminating error.
$Result = @(Export-OERInventory -TenantId 'oer-sovereign-verify-doesnotexist.onmicrosoft.com' -OutputPath $Out -Include Groups)
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
$Errs = @($Error | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Records in `$Error: $((Get-S1110FirstId $Errs) -join ', '); objects: $(@($Result).Count)"
$Refusal = @($Errs | Where-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] -eq 'TenantResolutionFailed' })
Write-OerLiveStep "The message names the domain: $([string]$Refusal[0].Exception.Message -like '*oer-sovereign-verify-doesnotexist.onmicrosoft.com*')"
Write-OerLiveStep "Entries under the output path: before $Before, after $(@(Get-ChildItem -LiteralPath $Out -Force).Count)"
Write-OerLiveStep 'END: the script carried on.'
Disconnect-OerLive
```

**Expect:** `token requests: 0`, `tenant lookups: 1`, 0 Microsoft Graph and 0 Azure Resource Manager requests;
`$Error` holding `TenantResolutionFailed` (once); 0 objects; the message names the domain; 0 entries before and
after; `END`.
**Failure looks like:** a folder under the output path (the base build names it after the previous session's
tenant), an object, a request, or no `END` line.

Result: not run yet.

## 5. -AllRolePolicies and -AllDirectoryRolePolicies without their section

### 5.1. Each switch without its section is warned about

- [ ] **5.1** `Export-OERInventory -Include AdministrativeUnits -AllRolePolicies -AllDirectoryRolePolicies -WhatIf` writes the two warnings, each once, and sends no write. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
Start-S1110Count
$Bundle = Export-OERInventory -Include AdministrativeUnits -AllRolePolicies -AllDirectoryRolePolicies -OutputPath (Join-Path $Work 'export-switches') -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S1110Sent)
Stop-S1110Count
$Texts = @($ExportWarnings | ForEach-Object { [string]$_.Message })
Write-OerLiveStep "Warnings: $($Texts.Count); the -AllRolePolicies one: $(@($Texts | Where-Object { $_ -ceq 'Export-OERInventory: -AllRolePolicies has no effect, since -Include does not name RoleManagementPolicies.' }).Count); the -AllDirectoryRolePolicies one: $(@($Texts | Where-Object { $_ -ceq 'Export-OERInventory: -AllDirectoryRolePolicies has no effect, since -Include does not name DirectoryRoleManagementPolicies.' }).Count)"
Write-OerLiveStep "The two are the first warnings: $(($Texts.Count -ge 2) -and $Texts[0] -like '*-All*Policies has no effect*' -and $Texts[1] -like '*-All*Policies has no effect*')"
Write-OerLiveStep "Errors: $(@(Get-S1110FirstId $ExportErrors | Sort-Object -Unique) -join ', '); bundle folder written: $(Test-Path -LiteralPath (Join-Path $Work 'export-switches\*'))"
Disconnect-OerLive
```

**Expect:** 0 writes; each warning exactly once, the two first; no bundle folder (`-WhatIf`).
**Failure looks like:** a missing or repeated warning, or a write.

Result: not run yet.

## 6. Measurements

### 6.1. BL-21: what Microsoft Graph answers for an access review and an instance that do not exist

- [ ] **6.1** The raw answers for a missing definition, the instance list of a missing definition, a missing instance of a missing and of an existing definition, and a missing catalog; and what the module now writes for each through `Get-OERAccessReviewInstance`, `Get-OERCatalog -Id` and `Get-OERInventory -Include Catalogs -Catalog`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$MissingA = [guid]::NewGuid().Guid
$MissingB = [guid]::NewGuid().Guid
$Sel = '$select=id,status,startDateTime,endDateTime,scope'
$Probes = [ordered]@{
    'definition by a missing id'               = "v1.0/identityGovernance/accessReviews/definitions/$MissingA"
    'instance list of a missing definition'    = "v1.0/identityGovernance/accessReviews/definitions/$MissingA/instances?$Sel"
    'missing instance of a missing definition' = "v1.0/identityGovernance/accessReviews/definitions/$MissingA/instances/$MissingB`?$Sel"
    'catalog by a missing id'                  = "v1.0/identityGovernance/entitlementManagement/catalogs/$MissingA"
}
foreach ($K in $Probes.Keys) {
    $R = Invoke-OerLiveGraph -Uri $Probes[$K]
    Write-OerLiveStep "Raw: $K -> status $($R.Status), code '$($R.Code)'"
}
$Defs = Invoke-OerLiveGraph -Uri 'v1.0/identityGovernance/accessReviews/definitions?$top=5&$select=id'
$Existing = @(@($Defs.Body['value']) | Where-Object { $_ })
Write-OerLiveStep "Access review definitions listed: status $($Defs.Status), at least one: $($Existing.Count -gt 0)"
if ($Existing.Count -gt 0) {
    $DefId = [string]$Existing[0]['id']
    $R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances/$MissingB`?$Sel"
    Write-OerLiveStep "Raw: missing instance of an existing definition -> status $($R.Status), code '$($R.Code)'"
    $E = $null
    $null = Get-OERAccessReviewInstance -Definition $DefId -Instance $MissingB -ErrorAction SilentlyContinue -ErrorVariable E
    Write-OerLiveStep "Module: missing instance of an existing definition -> records [$((Get-S1110FirstId $E) -join ' | ')]"
}
$E = $null
$null = Get-OERAccessReviewInstance -Definition $MissingA -Instance $MissingB -ErrorAction SilentlyContinue -ErrorVariable E
Write-OerLiveStep "Module: missing instance of a missing definition -> records [$((Get-S1110FirstId $E) -join ' | ')]"
$E = $null
$null = Get-OERCatalog -Id $MissingA -ErrorAction SilentlyContinue -ErrorVariable E
Write-OerLiveStep "Module: Get-OERCatalog -Id of a missing catalog -> records [$((Get-S1110FirstId $E) -join ' | ')]"
$Out = @(Get-OERInventory -Include Catalogs -Catalog $MissingA 2>&1)
Write-OerLiveStep "Module: Get-OERInventory -Include Catalogs -Catalog of a missing catalog -> error stream [$((Get-S1110FirstId $Out) -join ' | ')]; objects $(@($Out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count)"
Disconnect-OerLive
```

**Expect:** every access review probe 404 with an empty code; the catalog 404 with `CatalogNotFound`; through
the module, a missing instance (of an existing or a missing definition) exactly one record,
`AccessReviewInstanceNotFound`; `Get-OERCatalog -Id` `CatalogNotFound`; the inventory republishes
`CatalogNotFound`.
**Failure looks like:** a code in the access review bodies (then the expected code is wrong), more than one
record for a missing instance, or the catalog read named unread instead of not found.

Result: not run yet.

### 6.2. BL-83: the typed member read on a group with a user, a group and a service principal member

- [ ] **6.2** For `oer-s1110-typed` (members: a user, a group, a service principal) and `oer-s1110-dyn`, the untyped `members` and `owners` reads against the typed casts `user`, `group`, `device`, `orgContact` and `servicePrincipal`, and what the module returns for the typed group's members. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1110NoPrompt
$Ids = Get-S1110Ids
$Casts = 'user', 'group', 'device', 'orgContact', 'servicePrincipal'
foreach ($Key in 'typed', 'dyn') {
    foreach ($Relation in 'members', 'owners') {
        $Untyped = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids[$Key])/$Relation`?`$top=999"
        $UntypedIds = @(@($Untyped.Body['value']) | Where-Object { $_ } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() })
        $Types = @(@($Untyped.Body['value']) | Where-Object { $_ } | Group-Object { [string]$_['@odata.type'] } | ForEach-Object { "$($_.Name -replace '^#microsoft\.graph\.', '') $($_.Count)" })
        $Parts = foreach ($T in $Casts) {
            $Typed = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Ids[$Key])/$Relation/microsoft.graph.$T`?`$select=id&`$top=999"
            if (-not $Typed.Ok) { "$T $($Typed.Status) $($Typed.Code)"; continue }
            $Rows = @(@($Typed.Body['value']) | Where-Object { $_ })
            "$T $($Rows.Count) (missing from the untyped read $(@($Rows | Where-Object { $UntypedIds -notcontains ([string]$_['id']).ToLowerInvariant() }).Count))"
        }
        Write-OerLiveStep "$Key $($Relation): untyped $($Untyped.Status), $($UntypedIds.Count) [$($Types -join ', ')]; typed: $($Parts -join '; ')"
    }
}
$E = $null
$Members = @(Get-OERGroupMember -Group $Ids['typed'] -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "Get-OERGroupMember of oer-s1110-typed: $($Members.Count) member(s); errors: $((Get-S1110FirstId $E) -join ', ')"
Disconnect-OerLive
```

**Expect:** recorded as measured. The step changes no code here (Ruling R-14): the comment in
`Get-OERGroupRelation.ps1` states what is measured, and a type the untyped read misses that the code does not
read typed is a finding for the report.
**Failure looks like:** a read that is not 200 where a cast is documented to work.

Result: not run yet.

## B. Proved offline (class B)

- **B.1 A session that names no tenant.** Unit tests in `tests/Unit/Public/Export-OERInventory.Tests.ps1` hold
  the bundle folder named after the granted tenant id when the session's tenant is `organizations` or blank,
  after `-TenantId` otherwise, and `tenant` when neither is known.
- **B.2 A stop in the export's eligibility, Lighthouse or role policy selection read.** Unit tests hold, for each,
  the entries in `IncompleteReads`, the one warning, the bundle still written and no stray record, with a
  no-try runspace proof for the eligibility stop.
- **B.3 A scope whose role assignments and policy list both fail.** Unit tests hold exactly one warning
  (`Skipping scope`).
- **B.4 A refused Azure Resource Manager token in the export's sign-in, and the export's refusal under every
  error preference.** Unit tests and no-try runspace proofs hold no bundle, no folder and the sign-in's own
  record for the non-terminating `ArmTokenAcquisitionFailed` under Continue, SilentlyContinue, Stop and Ignore
  (as a parameter and as a preference variable), and that a caller's `try` catches a terminating refusal.
- **B.5 Read order and the shared cache.** Unit tests hold no catalog resource read for a catalog without a
  package or with a failed package list, and one principal lookup shared by the group read and the other Entra
  ID sections.
- **B.6 An administrative unit's members.** Unit tests hold the fixed order.

## T. Teardown

### T.1. The prerequisite objects are removed

- [ ] **T.1** `Initialize-OerS1110Prereq.ps1 -Teardown -Unattended` removes the eligibility, the groups and the users, the sweep lists no `oer-s1110-` object, and the counts equal the baseline. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1110Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "The teardown ended with exit code $LASTEXITCODE."
```

**Expect:** every removal answered, the sweep empty, the counts equal to the baseline, exit code 0.
**Failure looks like:** a residue row (exit code 3), or counts that differ.

Result: not run yet.

### T.2. Nothing is left, and the step's raw folder is gone

- [ ] **T.2** A read-back lists no `oer-s1110-` object and no residue row of this prefix, and the step's raw folder is deleted. The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1110Prereq.ps1') -ReadBack
Write-OerLiveStep "The read-back ended with exit code $LASTEXITCODE."
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "The step's raw folder exists: $(Test-Path -LiteralPath $Raw)"
```

**Expect:** 0 prefixed objects, 0 unread collections, 0 residue rows of this prefix; the raw folder gone.
**Failure looks like:** a prefixed object or a residue row of this prefix.

Result: not run yet.
