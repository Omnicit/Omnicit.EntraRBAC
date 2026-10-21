# Live verification checklist -- a page walk that cannot complete is never read as complete (fix/transport-findings)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4 and T has a written result.** A box
with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do not leave it
blank and do not tick it. A check that could not run for a stated reason is marked `[~]`, never `[x]`.
**Section B lists what is proved offline only (class B).** No manual check (class C) is foreseen.

**What this file writes to the tenant.** Only the prerequisite script writes, and only objects whose names start
with `oer-s1112-`: the security group `oer-s1112-grp` (no member, no owner) and the resource group
`oer-s1112-rg` (no resource) in the test subscription. Teardown (T.1) removes both. Every check reads; 3.1 runs
`Invoke-OERStructure -WhatIf` under a fence that refuses any write request. The exports and the comparison
files go under the step's raw folder, `raw\s1112\`, which is deleted after the results are written.

**The tenant's object names are never printed.** An export names the tenant's groups, members and role
assignments. The blocks print counts, True/False, request shapes with every GUID written `{id}`, and the step's
own prefixed names only; an export's warnings and errors are counted by id, never printed.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives beside
the operator's copy of this file outside the repository ([README.md](README.md), first paragraph). Every sign-in
is app-only, with the certificate; nothing here signs in as a person. A 401 or 403 is a stop.

**Permissions.** The reads use the permissions `oer-live-cc` already holds; the prerequisite script writes a group
(Group.ReadWrite.All) and a resource group (its Azure role on the test subscription). Granting a permission is the
operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, and every block that runs the module
installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs outside the repository. Every block prints through the
library's redactor, so its lines are already redacted per [README.md](README.md). **No credential, token,
application id, tenant id, subscription id, account or certificate thumbprint is ever printed.** Each block is run
in its own process whose WHOLE output (every stream) is written to a file outside the repository, redacted with
OerLive's redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main` before it
merges.

- **A. Microsoft Graph** ("fix: refuse a Graph page walk that cannot complete", BL-72). With `-All`, a later page
  that is empty or has no `value`, a next link already requested, or a walk past the page limit
  (`Get-OERPageWalkLimit`) is refused with `GraphPagingIncomplete`, carrying `PartialValue`, `NextLink` and
  `PageNumber` on the exception, instead of returning the pages read so far as the whole list.
- **B. Azure Resource Manager** ("fix: refuse an ARM page walk that cannot complete", BL-71, BL-73, BL-24,
  BL-120). The same refusal as `ArmPagingIncomplete` (also for a next link that is not an absolute URI), so a
  page is never requested twice; a 2xx body that cannot be read as JSON is `ArmResponseUnreadable`; ARM page
  failures carry the same three facts as Graph's; every page is sent with the call's own method and body; a first page whose body is JSON `null` reads as empty, like an empty body ("fix: read a null first ARM page as empty and prove the first-page return").
- **C. The claims step-up and the management group list** ("fix: step up a claims challenge only with a sign-in
  state", BL-124 O1, BL-120). A claims challenge without the module's sign-in state is reported as the Graph
  error; `Resolve-OERScope` lists management groups through `Get-OERManagementGroupList`; a clearer reason text.
- **D. The bearer header and the texts** ("test: prove no error copy keeps the bearer header", BL-157,
  BL-109 F4; and the help, CLAUDE.md, rationale and release notes, BL-63, BL-93).

A live tenant is needed for what the unit tests cannot show: that a real walk across several pages in each
transport still reads every page and returns the same collection as one large page; that a whole export of the
test tenant reads the same as on `main`; what the real Graph SDK leaves in a caller's `-ErrorVariable` after a
failed `Get-OERCatalog -Id`; and that a plan of a document with a group and a role assignment reads through both
transports and writes nothing.

## What this file does not check, and why

- **A walk that cannot complete (class B, B.1-B.3).** Microsoft Graph and Azure Resource Manager do not answer a
  later page empty, unreadable or with a repeated link on request, and no test tenant reaches the page limit
  (100,000 pages). The refusals are proved offline.
- **A claims challenge without a sign-in state (class B, B.4).** A live claims challenge needs a Conditional
  Access authentication context on the identity's path, which the test tenant does not set for app-only.
- **Resolve-OERScope by a management group name (class B, B.5).** Both identities are refused the management
  group list (403, measured in Sprint 11 step 7), so the list read cannot be shown live.

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
- The **prerequisite script** `Initialize-OerS1112Prereq.ps1` beside OerLive (0.2 runs it; T.1 removes what it
  created).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the counters and the
readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1112-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = [System.IO.Path]::GetFullPath($env:OER_LIVE_REPO).TrimEnd('\', '/') }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Work = Join-Path $Raw 'exports'
$null = New-Item -ItemType Directory -Path $Work -Force
$Prefix = 'oer-s1112-'
$Grp = 'oer-s1112-grp'
$Rg = 'oer-s1112-rg'
$NewIds = 'GraphPagingIncomplete', 'ArmPagingIncomplete', 'ArmResponseUnreadable'

function Start-S1112NoPrompt {
    # A token request without the certificate would be an interactive or device-code sign-in: refuse it.
    $global:S1112TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S1112TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S1112 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function global:Get-S1112Shape {
    # The request's path with each GUID segment as {id}; a later page is marked by its skip token.
    param([string]$Uri)
    $Path = $Uri
    if ([uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) { $Path = ([uri]$Uri).AbsolutePath }
    elseif ($Uri.Contains('?')) { $Path = $Uri.Substring(0, $Uri.IndexOf('?')) }
    $Path = '/' + $Path.TrimStart('/')
    $Path = $Path -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}'
    if ($Uri -match '(?i)[?&]\$?skiptoken=') { $Path += ' [later page]' }
    $Path
}

function Start-S1112Count {
    # Counts every request the module sends, and REFUSES every write: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. Each entry is the method and
    # the path with every GUID segment written {id}; a request carrying a skip token is a later page. getByIds and
    # getEntities are reads sent as POST. The full request text is kept in memory for the no-page-twice check and
    # never printed.
    $global:S1112TokenCalls = 0
    $global:S1112Graph = [System.Collections.Generic.List[string]]::new()
    $global:S1112Arm = [System.Collections.Generic.List[string]]::new()
    $global:S1112GraphRaw = [System.Collections.Generic.List[string]]::new()
    $global:S1112ArmRaw = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Fence = 'if ($M -ne ''GET'' -and $S -notlike ''POST */getByIds*'' -and $S -notlike ''POST */getEntities*'') { throw ''S1112 fence: a write request was refused.'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1112Shape -Uri ([string]`$Uri)); `$global:S1112Graph.Add(`$S); `$global:S1112GraphRaw.Add(`$M + ' ' + [string]`$Uri); $Fence; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$M = $Record; `$S = `$M + ' ' + (Get-S1112Shape -Uri ([string]`$Uri)); `$global:S1112Arm.Add(`$S); `$global:S1112ArmRaw.Add(`$M + ' ' + [string]`$Uri); $Fence; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S1112Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S1112Sent {
    # Totals, later pages and writes since Start-S1112Count.
    $GraphWrites = @($global:S1112Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getByIds*' })
    $ArmWrites = @($global:S1112Arm | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */getEntities*' })
    $GraphLater = @($global:S1112Graph | Where-Object { $_.EndsWith('[later page]') })
    $ArmLater = @($global:S1112Arm | Where-Object { $_.EndsWith('[later page]') })
    "token requests: $global:S1112TokenCalls; Microsoft Graph requests: $($global:S1112Graph.Count), later pages: $($GraphLater.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S1112Arm.Count), later pages: $($ArmLater.Count), writes: $($ArmWrites.Count)"
}

function Get-S1112FirstId {
    # The first segment of each record's FullyQualifiedErrorId, in order.
    param($Records)
    @(@($Records) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
}

function Get-S1112IdCounts {
    # "id xN" for each distinct first id, sorted.
    param($Records)
    (@(Get-S1112FirstId $Records) | Group-Object | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', '
}

function ConvertTo-S1112Canonical {
    # Keys sorted ordinally, arrays sorted by their own canonical text: two exports that hold the same facts in
    # another order compare equal.
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $Parts = foreach ($K in @($Value.Keys | Sort-Object { [string]$_ } -CaseSensitive)) { (ConvertTo-Json -InputObject ([string]$K) -Compress) + ':' + (ConvertTo-S1112Canonical $Value[$K]) }
        return '{' + ($Parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IList]) {
        $Items = @(foreach ($I in $Value) { ConvertTo-S1112Canonical $I })
        [System.Array]::Sort($Items, [System.StringComparer]::Ordinal)
        return '[' + ($Items -join ',') + ']'
    }
    ConvertTo-Json -InputObject $Value -Compress
}

function Compare-S1112Json {
    # The key paths whose canonical values differ (no values printed), for two JSON files.
    param([string]$A, [string]$B, [string]$Path = '$')
    $X = Get-Content -LiteralPath $A -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
    $Y = Get-Content -LiteralPath $B -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
    Compare-S1112Node -X $X -Y $Y -Path $Path
}

function Compare-S1112Node {
    param($X, $Y, [string]$Path)
    if ((ConvertTo-S1112Canonical $X) -ceq (ConvertTo-S1112Canonical $Y)) { return }
    if ($X -is [System.Collections.IDictionary] -and $Y -is [System.Collections.IDictionary]) {
        $Keys = @(@($X.Keys) + @($Y.Keys) | Sort-Object -Unique)
        foreach ($K in $Keys) { Compare-S1112Node -X $X[$K] -Y $Y[$K] -Path "$Path.$K" }
        return
    }
    $Path
}

function Save-S1112Export {
    # One export of the test tenant (the default sections, Entra ID and Azure), into a folder of its own; its
    # requests, files, errors and partial messages go to a JSON file named after it in the raw folder.
    param([Parameter(Mandatory)][string]$Name)
    $Out = Join-Path $Work "export-$Name"
    $null = New-Item -ItemType Directory -Path $Out -Force
    Start-S1112Count
    $Params = @{ OutputPath = $Out; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'ExportErrors'; WarningVariable = 'ExportWarnings' }
    $Bundle = Export-OERInventory @Params 3>$null
    $Sent = Get-S1112Sent
    $Record = [ordered]@{
        Name = $Name; Sent = $Sent
        Graph = @($global:S1112Graph); Arm = @($global:S1112Arm)
        Files = @($Bundle.Files | ForEach-Object { Split-Path -Leaf ([string]$_) }); IncompleteReads = @($Bundle.IncompleteReads).Count
        Errors = Get-S1112IdCounts $ExportErrors
        NewIdRecords = @(Get-S1112FirstId $ExportErrors | Where-Object { $NewIds -contains $_ }).Count
        Warnings = @($ExportWarnings).Count
        Dir = [string]$Bundle.BundlePath
    }
    Stop-S1112Count
    $Record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Raw "$Name.json") -Encoding utf8NoBOM
    [PSCustomObject]$Record
}

function Read-S1112Export {
    # A record Save-S1112Export wrote in an earlier block.
    param([Parameter(Mandatory)][string]$Name)
    Get-Content -LiteralPath (Join-Path $Raw "$Name.json") -Raw | ConvertFrom-Json
}

function Get-S1112Requests {
    # Every distinct HttpRequestMessage reachable from a set of records (exception chains, InnerExceptions,
    # Response.RequestMessage, TargetObject), by reference.
    param($Records)
    $Seen = [System.Collections.Generic.List[object]]::new()
    $Found = [System.Collections.Generic.List[object]]::new()
    $Queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($R in @($Records)) { if ($null -ne $R) { $Queue.Enqueue($R) } }
    $Visits = 0
    while ($Queue.Count -gt 0 -and $Visits -lt 5000) {
        $N = $Queue.Dequeue()
        $Visits++
        if ($null -eq $N -or $N -is [string] -or $N.GetType().IsPrimitive) { continue }
        if (@($Seen | Where-Object { [object]::ReferenceEquals($_, $N) }).Count -gt 0) { continue }
        $Seen.Add($N)
        if ($N -is [System.Net.Http.HttpRequestMessage]) { $Found.Add($N); continue }
        foreach ($P in 'Exception', 'InnerException', 'TargetObject', 'Response', 'RequestMessage', 'ErrorRecord') {
            $V = $null
            try { $V = $N.$P } catch { Clear-OerLiveErrorRecord -Record $PSItem }
            if ($null -ne $V) { $Queue.Enqueue($V) }
        }
        $Inner = $null
        try { $Inner = $N.InnerExceptions } catch { Clear-OerLiveErrorRecord -Record $PSItem }
        foreach ($I in @($Inner)) { if ($null -ne $I) { $Queue.Enqueue($I) } }
    }
    , $Found.ToArray()
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Found = @(foreach ($Id in $NewIds + 'Get-OERPageWalkLimit') { '{0}: {1}' -f $Id, [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Id -Quiet) })
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
Start-S1112NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, `The module is the worktree's build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

### 0.2. The prerequisite objects

- [ ] **0.2** `Initialize-OerS1112Prereq.ps1 -Unattended` writes the baseline and creates `oer-s1112-grp` and `oer-s1112-rg`. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1112Prereq.ps1') -Unattended
Write-OerLiveStep "The prerequisite script ended with exit code $LASTEXITCODE."
```

**Expect:** the baseline written (0 prefixed objects, no resource group before), both objects created and read
back, exit code 0.
**Failure looks like:** a STOP for an object with the prefix that existed before, a refusal, or exit code 1.

Result:

### 0.3. Read back what the prerequisite script created

- [ ] **0.3** The group and the resource group are there, by their recorded id and path. #type/subtask

```powershell
Connect-OerLive -Arm
$Created = Get-Content -LiteralPath (Join-Path $Raw 'created-s1112.json') -Raw | ConvertFrom-Json -AsHashtable
$G = Invoke-OerLiveGraph -Uri "v1.0/groups/$($Created['grp'])?`$select=displayName,securityEnabled,mailEnabled"
$Members = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($Created['grp'])/members?`$select=id"
$R = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/resourcegroups/$Rg`?api-version=2021-04-01"
Write-OerLiveStep "Group: read $($G.Status); name $([string]$G.Body['displayName']); security $($G.Body['securityEnabled']); members $(@($Members.Body['value']).Count)"
Write-OerLiveStep "Resource group: read ok $($R.Ok); name $([string]$R.Body.name); provisioning $([string]$R.Body.properties.provisioningState)"
Disconnect-OerLive
```

**Expect:** the group read 200, named `oer-s1112-grp`, security `True`, 0 members; the resource group read,
named `oer-s1112-rg`, `Succeeded`.
**Failure looks like:** a read that is not 200, another name, or a member.

Result:

## 1. Walks across several pages, in both transports

### 1.1. A Microsoft Graph walk of ten groups a page returns the same groups as one page of 999

- [ ] **1.1** `Invoke-OERGraphRequest -All` over `v1.0/groups` with `$top=10` reads every page, sends no request twice, and returns the same group ids as one request with `$top=999`; no new error id. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1112NoPrompt
$Module = Get-Module -Name Omnicit.EntraRBAC
Start-S1112Count
$Out = & $Module {
    $E = $null
    $Small = @((Invoke-OERGraphRequest -Uri 'v1.0/groups?$select=id&$top=10' -All -ErrorAction SilentlyContinue -ErrorVariable E).value)
    $E1 = @($E)
    $E = $null
    $One = Invoke-OERGraphRequest -Uri 'v1.0/groups?$select=id&$top=999' -ErrorAction SilentlyContinue -ErrorVariable E
    [PSCustomObject]@{ Small = $Small; Big = @($One.value); BigNext = [bool]$One.'@odata.nextLink'; Errors = @($E1) + @($E) }
}
$Sent = Get-S1112Sent
$RawGraph = @($global:S1112GraphRaw)
Stop-S1112Count
$SmallIds = @($Out.Small | ForEach-Object { ([string]$_.id).ToLowerInvariant() } | Sort-Object)
$BigIds = @($Out.Big | ForEach-Object { ([string]$_.id).ToLowerInvariant() } | Sort-Object)
Write-OerLiveStep "Requests: $Sent"
Write-OerLiveStep "No request sent twice: $(@($RawGraph | Sort-Object -Unique -CaseSensitive).Count -eq $RawGraph.Count)"
Write-OerLiveStep "Groups: ten a page $($SmallIds.Count); one page of 999 $($BigIds.Count) (that page has a next link: $($Out.BigNext)); the same ids: $((Compare-Object $SmallIds $BigIds -SyncWindow 0).Count -eq 0 -and $SmallIds.Count -eq @($SmallIds | Sort-Object -Unique).Count)"
Write-OerLiveStep "Records: [$(Get-S1112IdCounts $Out.Errors)]; new ids: $(@(Get-S1112FirstId $Out.Errors | Where-Object { $NewIds -contains $_ }).Count)"
Disconnect-OerLive
```

**Expect:** 0 writes, 0 token requests; Microsoft Graph requests = the pages of the small walk (at least 10, the
group count divided by ten, rounded up) plus 1, with later pages = that count minus 1; no request sent twice; the same ids in both reads,
none twice; the large page has no next link; no record.
**Failure looks like:** fewer ids in the small walk (a page lost), an id twice (a page read twice), a record with a
new id (a real page the walk refused), or a write.

Result:

### 1.2. An Azure Resource Manager walk of one resource group a page returns the same resource groups as one read

- [ ] **1.2** `Invoke-OERArmRequest -All` over the test subscription's resource groups with `$top=1` reads every page and returns the same resource groups as one read without `$top`; no new error id. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1112NoPrompt
$Module = Get-Module -Name Omnicit.EntraRBAC
Start-S1112Count
$Out = & $Module {
    param($Sub)
    $E = $null
    $Small = @((Invoke-OERArmRequest -Path "/subscriptions/$Sub/resourcegroups?api-version=2021-04-01&`$top=1" -All -ErrorAction SilentlyContinue -ErrorVariable E).value)
    $E1 = @($E)
    $E = $null
    $All = @((Invoke-OERArmRequest -Path "/subscriptions/$Sub/resourcegroups?api-version=2021-04-01" -All -ErrorAction SilentlyContinue -ErrorVariable E).value)
    [PSCustomObject]@{ Small = $Small; All = $All; Errors = @($E1) + @($E) }
} $Cfg.SubscriptionId
$Sent = Get-S1112Sent
$RawArm = @($global:S1112ArmRaw)
Stop-S1112Count
$SmallIds = @($Out.Small | ForEach-Object { ([string]$_.id).ToLowerInvariant() } | Sort-Object)
Write-OerLiveStep "No request sent twice: $(@($RawArm | Sort-Object -Unique -CaseSensitive).Count -eq $RawArm.Count)"
$AllIds = @($Out.All | ForEach-Object { ([string]$_.id).ToLowerInvariant() } | Sort-Object)
Write-OerLiveStep "Requests: $Sent"
Write-OerLiveStep "Resource groups: one a page $($SmallIds.Count); one read $($AllIds.Count); the same ids: $((Compare-Object $SmallIds $AllIds -SyncWindow 0).Count -eq 0 -and $SmallIds.Count -eq @($SmallIds | Sort-Object -Unique).Count); $Rg among them: $(@($Out.Small | Where-Object { [string]$_.name -eq $Rg }).Count -eq 1)"
Write-OerLiveStep "Records: [$(Get-S1112IdCounts $Out.Errors)]; new ids: $(@(Get-S1112FirstId $Out.Errors | Where-Object { $NewIds -contains $_ }).Count)"
Disconnect-OerLive
```

**Expect:** 0 writes, 0 token requests; at least 2 resource groups (`oer-s1112-rg` among them); later pages in the
small walk equal to the resource group count minus 1, no request sent twice (if ARM honours `$top` here; if it answers every row on one
page, write that down -- the walk is then not shown across pages and 1.1 alone carries this check); the same ids
in both reads, none twice; no record.
**Failure looks like:** fewer ids in the small walk, an id twice, a record with a new id, or a write.

Result:

### 1.3. An export of the test tenant on this branch reads and writes the same as on `main`

- [ ] **1.3** `Export-OERInventory` (the default sections, Entra ID and Azure) on this branch's build and on `main`'s source write the same files with the same facts, send no write, and this branch's export raises no new error id. #type/subtask

Run the two halves in two processes, each after H.1. First this branch's build:

```powershell
Connect-OerLive -Arm
Start-S1112NoPrompt
$E = Save-S1112Export -Name 'branch'
Write-OerLiveStep "Branch export: $($E.Sent); files $($E.Files.Count); IncompleteReads $($E.IncompleteReads); records [$($E.Errors)]; new ids $($E.NewIdRecords); warnings $($E.Warnings)"
Disconnect-OerLive
```

Then `main`'s source (the commit the branch started from), loaded before the sign-in, so `Connect-OerLive` keeps it:

```powershell
$Base = Join-Path $Raw 'base-src'
if (-not (Test-Path -LiteralPath $Base)) {
    $null = New-Item -ItemType Directory -Path $Base -Force
    $Tar = Join-Path $Raw 'base.tar'
    git -C $Cfg.Repo archive --format=tar -o $Tar (git -C $Cfg.Repo merge-base origin/main HEAD) source
    tar -xf $Tar -C $Base
    Remove-Item -LiteralPath $Tar
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $Base 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Write-OerLiveStep "Base module loaded from the archived source of the merge base: $((Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase))"
Connect-OerLive -Arm
Start-S1112NoPrompt
$E = Save-S1112Export -Name 'main'
Write-OerLiveStep "Main export: $($E.Sent); files $($E.Files.Count); IncompleteReads $($E.IncompleteReads); records [$($E.Errors)]; warnings $($E.Warnings)"
Disconnect-OerLive
$B = Read-S1112Export -Name 'branch'
$M = Read-S1112Export -Name 'main'
Write-OerLiveStep "The same requests, in shape and number: $((Compare-Object @($B.Graph + $B.Arm | Sort-Object) @($M.Graph + $M.Arm | Sort-Object) -SyncWindow 0).Count -eq 0)"
Write-OerLiveStep "The same file names: $((Compare-Object @($B.Files | Sort-Object) @($M.Files | Sort-Object) -SyncWindow 0).Count -eq 0)"
foreach ($F in @($B.Files | Where-Object { $_ -like '*.json' } | Sort-Object)) {
    $Pa = Join-Path $B.Dir $F
    $Pb = Join-Path $M.Dir $F
    if (-not (Test-Path -LiteralPath $Pb)) { Write-OerLiveStep "$F`: missing on main"; continue }
    $Diff = @(Compare-S1112Json -A $Pa -B $Pb)
    Write-OerLiveStep "$F`: differing key paths $($Diff.Count)$(if ($Diff.Count) { ' [' + (($Diff | Select-Object -First 10) -join ', ') + ']' })"
}
```

**Expect:** both exports 0 writes and 0 token requests; the same request shapes and counts, with the later pages
each read (the number is recorded, 0 when every list fits one page); the same file names; in every JSON file 0
differing key paths, apart from a time stamp of the export (its path recorded); the branch export 0 records with
a new id, and the same records, IncompleteReads and warning counts as `main`.
**Failure looks like:** a write; a request on one build only; a differing key path that is not a time stamp; a
new id in the branch export (a walk this branch refuses that `main` read as whole -- STOP and record the request
shape).

Result:

## 2. What a failed Get-OERCatalog -Id leaves in -ErrorVariable (BL-157, BL-109 F4)

### 2.1. No copy of the request keeps the Authorization header

- [ ] **2.1** After `Get-OERCatalog -Id` of a catalog that does not exist, the records in the caller's `-ErrorVariable` and in `$Error` are counted by type, every distinct request instance they reach is found, and none of them carries an `Authorization` header. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1112NoPrompt
$Missing = [guid]::NewGuid().Guid
$Error.Clear()
$EV = $null
$Out = @(Get-OERCatalog -Id $Missing -ErrorAction SilentlyContinue -ErrorVariable EV)
$Types = (@($EV) | Group-Object { $T = $_.GetType().Name; if ($_ -is [System.Management.Automation.ErrorRecord]) { "$T/$($_.Exception.GetType().Name)" } else { $T } } | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', '
Write-OerLiveStep "Objects: $($Out.Count); -ErrorVariable records: $(@($EV).Count) [$Types]; first ids [$(Get-S1112IdCounts $EV)]"
$Requests = @(Get-S1112Requests -Records (@($EV) + @($Error)))
$WithHeader = @($Requests | Where-Object { $null -ne $_.Headers.Authorization -or $_.Headers.Contains('Authorization') })
Write-OerLiveStep "Distinct request instances reached from -ErrorVariable and `$Error: $($Requests.Count); with an Authorization header: $($WithHeader.Count)"
Disconnect-OerLive
```

**Expect:** 0 objects; the cmdlet's own record `CatalogNotFound` among the records, with the inner layers' records
beside it (the Graph SDK's raw exception among them, as measured in Sprint 11 step 10); at least 1 request
instance reached; 0 with an `Authorization` header. If no instance is reached, write that down: the live record
then holds no request, and the unit test (Task 4) is the proof.
**Failure looks like:** any instance with an `Authorization` header -- STOP: a bearer in a caller's
`-ErrorVariable` is a security finding; record the record type and the path to the request, never the value.

Result:

## 3. A plan through both transports writes nothing

### 3.1. Invoke-OERStructure -WhatIf of a group and a role assignment, twice

- [ ] **3.1** A document declaring `oer-s1112-grp` and a Reader role assignment for it at `oer-s1112-rg`, run twice with `-WhatIf` under the write fence, sends no write, reads through both transports, and plans the same rows both times. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1112NoPrompt
$Doc = [ordered]@{
    version         = '1.0'
    tenantId        = $Cfg.TenantId
    groups          = @(@{ displayName = $Grp })
    roleAssignments = @(@{ scope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/$Rg"; role = 'Reader'; principal = $Grp; principalType = 'Group' })
}
$DocPath = Join-Path $Raw 'plan-s1112.json'
$Doc | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $DocPath -Encoding utf8NoBOM
$Runs = foreach ($Run in 1, 2) {
    Start-S1112Count
    $E = $null
    $Rows = @(Invoke-OERStructure -Path $DocPath -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E 3>$null)
    $Sent = Get-S1112Sent
    Stop-S1112Count
    $Text = @($Rows | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Action, $(if ([string]$_.Item -like "*$Prefix*") { $_.Item } else { '(other)' }) })
    Write-OerLiveStep "Run $Run`: $Sent; rows [$($Text -join '; ')]; records [$(Get-S1112IdCounts $E)]"
    , $Text
}
Write-OerLiveStep "The two plans are the same: $((Compare-Object @($Runs[0]) @($Runs[1]) -SyncWindow 0).Count -eq 0)"
Disconnect-OerLive
```

**Expect:** each run 0 writes and 0 token requests, Microsoft Graph and Azure Resource Manager requests both above
0; the group `Unchanged`, the role assignment planned as a creation (`Skipped` with "would create"); no record;
the two plans the same (G8).
**Failure looks like:** a write (the fence refuses it and the row is `Failed`), a row naming an object without the
prefix, a record, or two different plans.

Result:

## 4. Measurement

### 4.1. BL-93: what `-TimeoutSec 30` bounds in the tenant lookup

- [ ] **4.1** The call `Resolve-OERTenantDomain` sends, exactly as written (`Invoke-RestMethod -Uri ... -Method Get -TimeoutSec 30 -ErrorAction Stop`), against a local listener and an address that never answers, each in its own process, no tenant and no module. #type/subtask

```powershell
$Out = Join-Path $Raw 'bl93'
$null = New-Item -ItemType Directory -Path $Out -Force
$Listener = {
    param([int]$Port, [string]$Mode)
    $L = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $L.Start()
    try {
        $C = $L.AcceptTcpClient(); $S = $C.GetStream(); $Buf = [byte[]]::new(4096); $null = $S.Read($Buf, 0, $Buf.Length)
        $Head = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: 1000`r`n`r`n{")
        switch ($Mode) {
            'silent' { Start-Sleep -Seconds 600 }
            'stalled' { $S.Write($Head, 0, $Head.Length); $S.Flush(); Start-Sleep -Seconds 600 }
            'trickle' { $S.Write($Head, 0, $Head.Length); $S.Flush(); for ($I = 0; $I -lt 300; $I++) { Start-Sleep -Seconds 2; $S.WriteByte(32); $S.Flush() } }
        }
    } finally { $L.Stop() }
}
$Cases = @(
    @{ Name = 'A silent connection'; Uri = 'http://127.0.0.1:18931/x/v2.0/.well-known/openid-configuration'; Port = 18931; Mode = 'silent' }
    @{ Name = 'B an address that never answers'; Uri = 'http://10.255.255.1/x/v2.0/.well-known/openid-configuration'; Port = 0; Mode = '' }
    @{ Name = 'C headers, then a stalled body'; Uri = 'http://127.0.0.1:18933/x/v2.0/.well-known/openid-configuration'; Port = 18933; Mode = 'stalled' }
    @{ Name = 'D headers, then a trickled body'; Uri = 'http://127.0.0.1:18934/x/v2.0/.well-known/openid-configuration'; Port = 18934; Mode = 'trickle' }
)
$Jobs = @(foreach ($Case in $Cases) { if ($Case.Port) { Start-ThreadJob -ScriptBlock $Listener -ArgumentList $Case.Port, $Case.Mode } })
Start-Sleep -Milliseconds 500
$Procs = foreach ($Case in $Cases) {
    $Child = "`$Sw = [System.Diagnostics.Stopwatch]::StartNew(); try { `$null = Invoke-RestMethod -Uri '$($Case.Uri)' -Method Get -TimeoutSec 30 -ErrorAction Stop; `$R = 'returned' } catch { `$R = 'error ' + `$_.Exception.GetType().FullName }; [string]::Format([cultureinfo]::InvariantCulture, '{0:N1} s, {1}', `$Sw.Elapsed.TotalSeconds, `$R)"
    $File = Join-Path $Out ("child-{0}.txt" -f $Case.Name.Substring(0, 1))
    $P = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-EncodedCommand', ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Child))) -RedirectStandardOutput $File -NoNewWindow -PassThru
    [PSCustomObject]@{ Case = $Case.Name; Proc = $P; File = $File; Started = [DateTime]::UtcNow }
}
foreach ($Item in $Procs) {
    $Left = [Math]::Max(1, 130 - ([DateTime]::UtcNow - $Item.Started).TotalSeconds)
    if (-not $Item.Proc.WaitForExit([int]($Left * 1000))) { $Item.Proc.Kill(); $Line = 'NOT BOUNDED: still running at 130 s, stopped by the harness' }
    else { $Line = (Get-Content -LiteralPath $Item.File -Raw).Trim() }
    Write-OerLiveStep "$($Item.Case): $Line"
}
$Jobs | Stop-Job -PassThru | Remove-Job -Force
Write-OerLiveStep "PowerShell $($PSVersionTable.PSVersion)"
```

**Expect:** recorded as measured. A about 30 s (`TaskCanceledException`); B about 21 s (`HttpRequestException`,
the operating system's connect timeout); C and D NOT BOUNDED at 130 s. The step adds no bound (decision A28): the
function's help and `rationale.md` state the limit, which the operator accepted as known; its future handling is tracked in issue #66.
**Failure looks like:** nothing fails here; a C or D that ends would mean the runtime bounds the body, and is
recorded as such.

Result:

## B. Proved offline (class B)

- **B.1 A Microsoft Graph walk that cannot complete.** Unit tests in
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` hold `GraphPagingIncomplete` for a later page that is
  `$null` or has no `value`, a repeated next link (never requested twice, counted exactly) and the page limit
  (`Get-OERPageWalkLimit` mocked to 3), each with `PartialValue`, `NextLink` and `PageNumber`; a later page whose
  `value` is empty is a normal page; a `$null` first page is still an empty collection; and the no-try runspace
  proofs under `-ErrorAction SilentlyContinue` show no result and no further request. The export proof in
  `tests/Unit/Public/Get-OERInventory.Tests.ps1` reports a group whose member walk breaks off as unread, never
  with the first page's members.
- **B.2 An Azure Resource Manager walk that cannot complete, and an unreadable body.** Unit tests in
  `tests/Unit/Private/Invoke-OERArmRequest.Tests.ps1` hold `ArmPagingIncomplete` for an empty, JSON `null` or
  `value`-less later page, a repeated path, the page limit and a next link that is not absolute; and
  `ArmResponseUnreadable` for an unreadable 2xx body on a single request, on the first page and on a later page
  (with the facts); a 204 single request, and a first page under `-All` whose body is empty or JSON `null`, still return `$null`; a non-2xx or failed later page carries the facts;
  the no-try runspace proofs show no result and no further request.
- **B.3 The same body on every page.** A unit test holds that a `-All` call with a body sends the same method and
  body on page 2.
- **B.4 A claims challenge without a sign-in state.** Unit tests hold one request, no sign-in call and the Graph
  error for a 401 claims challenge and a PIM 400 claims body without state, and the step-up with state; a no-try
  runspace proof holds the same.
- **B.5 Resolve-OERScope by a management group name.** Unit tests hold that the list is read through
  `Get-OERManagementGroupList`, with the ambiguous, not-found and failed-read paths unchanged.
- **B.6 The bearer header.** A unit test drives `Get-OERCatalog -Id` through the real wrapper with an SDK-shaped
  404 whose request carries a test bearer, and finds no copy with the header; a control with the scrub disabled
  finds it.

## T. Teardown

### T.1. The prerequisite objects are removed

- [ ] **T.1** `Initialize-OerS1112Prereq.ps1 -Teardown -Unattended` removes the resource group and the group, purges the group from the deleted items, and the sweep lists no `oer-s1112-` object. #type/subtask

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS1112Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "The teardown ended with exit code $LASTEXITCODE."
```

**Expect:** 0 role assignments at the resource group; the resource group reads 404; the group removed and purged;
the sweep 0 objects with the prefix; exit code 0.
**Failure looks like:** a role assignment of another principal (STOP), a residue row, or a prefixed object left.

Result:

### T.2. Nothing is left, and the step's raw folder is gone

- [ ] **T.2** A read-back lists no `oer-s1112-` object, no residue row of this prefix and no resource group `oer-s1112-rg`, and the step's raw folder is deleted. The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check. #type/subtask

```powershell
Connect-OerLive -Arm
$Left = @(Find-OerLivePrefixed -Prefix $Prefix -ThrowOnUnread -Quiet)
$Residue = @(Read-OerLiveResidue | Where-Object { [string]$_['name'] -like "$Prefix*" })
$R = Invoke-OerLiveArm -Path "/subscriptions/$($Cfg.SubscriptionId)/resourcegroups/$Rg`?api-version=2021-04-01"
Write-OerLiveStep "Prefixed objects: $($Left.Count); residue rows of this prefix: $($Residue.Count); the resource group reads 404: $($R.NotFound)"
Disconnect-OerLive
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "The step's raw folder exists: $(Test-Path -LiteralPath $Raw)"
```

**Expect:** 0 prefixed objects, 0 residue rows of this prefix, the resource group 404; the raw folder gone.
**Failure looks like:** a prefixed object, a residue row of this prefix, or the resource group still there.

Result:
