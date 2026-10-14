# Live verification checklist -- the roster gets identity and type, and shared names are counted (feat/roster-identity-and-shared-names)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to
be impossible to run, write "cannot be verified, and therefore we do not know" on its result line and
say why; do not leave it blank and do not tick it. A check that could not run for a stated reason is
marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** This step has no
manual check (class C).

**What this file writes to the tenant: only inside the prefix `oer-s115-`.** The prerequisite script
`Initialize-OerS115Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates two security groups that share the name `oer-s115-dup`; a security group and a private
Microsoft 365 group that share the name `oer-s115-mix`; a security group `oer-s115-cnt` whose only
member is the service principal `oer-live-cc-noperm` (which holds no role through it); a security group
`oer-s115-req` with no member; two catalogs that share the name `oer-s115-cat`, the first holding the
hidden access package `oer-s115-ap-a`; a catalog `oer-s115-catu` holding the hidden access package
`oer-s115-ap-b` with two assignment policies that share the name `oer-s115-pol`, through which only the
members of `oer-s115-req` (none) may request; and a tagged resource group `oer-s115-rg`, empty, where the
first `oer-s115-dup` group is assigned Reader. Section 1 adds the second `oer-s115-dup` group as a member
of `oer-s115-cnt` and removes it again. Sections 2 and 3 must write nothing: 3.3 and 3.5 run
`Invoke-OERStructure` for real, on the step's own objects only, and must write nothing either. Nobody
is assigned anything. The teardown (T.1) removes the role assignment and the resource group, the
Microsoft 365 group, then the policies, the packages, the catalogs and the groups, and purges the
deleted Microsoft 365 group. Bundles, documents and counts are
written under `raw\s115\`, which is deleted after the results are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or
403 as `oer-live-cc` is a stop.

**Permissions.** The objects need the Microsoft Graph application permissions `Group.ReadWrite.All`,
`GroupMember.ReadWrite.All` and `EntitlementManagement.ReadWrite.All`; the prerequisite script reads them
and refuses its setup before anything is written when one is missing. The role assignment needs the
identity's existing Azure role on the test subscription; when Azure Resource Manager refuses it, the
script says so and carries on without it, and check 2.6 becomes class B. Granting a permission is the
operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm` (or `-Graph` for the raw
measurement), which runs `Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as
True/False, and every block that runs the module installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s115/`, which is
git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** A warning and an error that stops a script go straight to the
host, so each block is run in its own process whose WHOLE output (standard output and standard error) is
written to a file under `raw\s115\`, redacted with OerLive's redactor before anyone reads it, and then
deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The roster carries identity and type** ("feat: carry the group's id, type, visibility and creation
  time in the roster"). `ConvertTo-OERGroup` gains `MailEnabled`, `Visibility` and `CreatedDateTime` (a UTC
  ISO 8601 string), so `Get-OERGroup` shows them too; every `groupsRoster.json` row gains `id`,
  `securityEnabled`, `mailEnabled`, `groupTypes`, `visibility` and `createdDateTime` after its five keys.
- **B. Shared names are counted over every group and named with their count** ("feat: count shared group
  names over every group and name each with its count", "test: import the module again where the real
  group name index must run"). `Get-OERGroupNameIndex` holds which groups carry a name -- in the export from
  its unfiltered roster listing, in `Get-OERInventory` from one paged listing of every group's id and name.
  A security group that shares its name with a Microsoft 365 or distribution group is left out like two
  security groups that share one. The export warns once (names and objects counted) and its README lists
  each name with its count and section under "Names two or more objects share".
- **C. Two policies of one name in a package** ("feat: leave out assignment policies of one name and refuse
  them in the validator"). The export leaves both out and names them; `Test-OERStructure` gives an Error for
  two such entries.
- **D. References by id** ("feat: name a left-out catalog and a review's shared names by id in the export",
  "fix: hold the export's review lookups to the resolvers and name a shared catalog by id when unread",
  "feat: write a group principal whose name is shared by its object id", "fix: hold the principal note, the
  per-role directory collision and the null index guard"). A package in a catalog whose name another catalog
  shares names the catalog by id; an access review names its package or policy by id when the name would not
  resolve to that object; a group named as a principal of a role assignment or a directory role assignment is
  named by id, with principalType Group, when its name is shared.
- **E. A package re-created in its catalog never lands in another catalog's package** ("fix: fail an access
  package create that returns another catalog's package"). `New-OERAccessPackage` looks a package up by name
  across the tenant; when the package an entry declares is missing from its catalog and a package of the same
  name exists in another catalog, `Sync-OERStructureAccessPackage` now reports the entry `Failed` and writes
  nothing to that other package (before: `Created`, then the declared resource roles and policies written to
  it). D made this case reachable for two catalogs that share a name.
- **F. No listing for a group principal named by its id** ("fix: read no group listing for a group principal
  whose name is its id").
- **G. The texts** ("docs: describe the roster's id and type, shared names and references by id", "docs: name
  the id positions and each kind's counting domain in the shared-name texts", "docs: close the twin-catalog
  limit and state the per-scope listing cost").

A live tenant is needed because the claims are about what Microsoft Graph and Azure Resource Manager return
and what the engine then does with the export: that the listing really carries the three fields, that a
Microsoft 365 group and two security groups of one name are left out with their count, that the exported
document then validates and applies with no AmbiguousName, that the step's references by id converge, and
what a member count with `ConsistencyLevel: eventual` gives for a service principal member and right after a
change.

## What this file does not check, and why

- **An access review whose access package or assignment policy name is shared (class B).** A review of a
  package whose name another package carries would add two more packages, a review and its teardown; the
  claim is the export's id choice, which the unit tests hold against the exact lookups the apply engine
  makes, and the engine's acceptance of an id there (`Invoke-OERStructure` and the review handler's tests).
- **A group with a shared name as a principal of a Microsoft Entra directory role (class B).** Assigning a
  directory role to a prefixed group is a role assignment the step does not need; the Azure role assignment
  in 2.6 exercises the same naming rule (`Get-OERGroupReference`), and the unit tests hold the directory
  role section.
- **A failed listing of every group's name, a failed uniqueness lookup, and an unread roster (class B).** A
  read cannot be made to fail on demand; the unit tests hold the fallbacks and the partial signals.
- **The texts (class B).** Section B names the gates that hold them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets
  the session's `Repo` to it, so the module loads from the worktree's build; the main clone is never
  checked out on another commit or branch (S.1 reads that it was not).
- The **prerequisite objects**: check 0.2 runs `Initialize-OerS115Prereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the counters
and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s115-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Dup = 'oer-s115-dup'; $Mix = 'oer-s115-mix'; $Cnt = 'oer-s115-cnt'; $Req = 'oer-s115-req'
$Cat = 'oer-s115-cat'; $CatU = 'oer-s115-catu'; $ApA = 'oer-s115-ap-a'; $ApB = 'oer-s115-ap-b'; $Pol = 'oer-s115-pol'
$Rg = 'oer-s115-rg'
# The step's raw folder as OerLive fixed it (git-ignored), and the ids the prerequisite script recorded
# there (never printed).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Ids = if (Test-Path -LiteralPath (Join-Path $Raw 'created-s115.json')) { Get-Content -LiteralPath (Join-Path $Raw 'created-s115.json') -Raw | ConvertFrom-Json -AsHashtable } else { @{} }

function Start-S115NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S115TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S115TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S115 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S115Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is a
    # GET. The path of every request is recorded too (the query dropped).
    $global:S115Graph = [System.Collections.Generic.List[string]]::new()
    $global:S115Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S115Graph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S115Arm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S115Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S115Sent {
    # Requests counted since Start-S115Count: totals and writes (any method but GET), with the write paths.
    $GraphWrites = @($global:S115Graph | Where-Object { -not $_.StartsWith('GET ') })
    $ArmWrites = @($global:S115Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S115TokenCalls; Microsoft Graph requests: $($global:S115Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S115Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" })"
}

function Invoke-S115Header {
    # The SDK call OerLive's transport makes, with a header Invoke-OerLiveGraph cannot send (the
    # ConsistencyLevel header the member count needs). A refusal comes back as data (-SkipHttpErrorCheck);
    # a transport failure's record is removed. Returns Status, Code and Body (a $count arrives as a String).
    param([Parameter(Mandatory)][string]$Uri, [hashtable]$Headers)
    $Params = @{ Method = 'GET'; Uri = $Uri; OutputType = 'HashTable'; SkipHttpErrorCheck = $true; StatusCodeVariable = 'S115Status'; ErrorAction = 'Stop'; Verbose = $false }
    if ($Headers) { $Params.Headers = $Headers }
    $S115Status = $null
    $R = $null
    try { $R = Microsoft.Graph.Authentication\Invoke-MgGraphRequest @Params } catch {
        $Msg = $PSItem.Exception.Message
        & (Get-Module -Name OerLive) { param($Rec) Clear-OerLiveErrorRecord -Record $Rec } $PSItem
        return [PSCustomObject]@{ Status = 0; Code = 'TransportError'; Message = (ConvertTo-OerLiveRedacted -Text $Msg); Body = $null }
    }
    $Code = ''
    if ($R -is [System.Collections.IDictionary] -and $R.Contains('error')) { $Code = [string]$R['error']['code'] }
    [PSCustomObject]@{ Status = [int]$S115Status; Code = $Code; Message = ''; Body = $R }
}

function Get-S115MemberCount {
    # One group's members three ways (ids never printed): the full read the module makes (the member list
    # and the service principal cast, joined), $count with ConsistencyLevel: eventual, and $count without it.
    param([Parameter(Mandatory)][string]$Id)
    $M = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$Id/members?`$select=id"
    Assert-OerLiveOk -Response $M -Activity 'Reading the members' | Out-Null
    $S = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$Id/members/microsoft.graph.servicePrincipal?`$select=id"
    Assert-OerLiveOk -Response $S -Activity 'Reading the service principal members' | Out-Null
    $MemberIds = @(@($M.Body['value']) | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() })
    $SpIds = @(@($S.Body['value']) | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() })
    $E = Invoke-S115Header -Uri "v1.0/groups/$Id/members/`$count" -Headers @{ ConsistencyLevel = 'eventual' }
    $N = Invoke-S115Header -Uri "v1.0/groups/$Id/members/`$count"
    [PSCustomObject]@{
        MembersList        = $MemberIds.Count
        SpList             = $SpIds.Count
        MembersListHoldsSp = @($SpIds | Where-Object { $MemberIds -contains $_ }).Count
        FullRead           = @(@($MemberIds) + @($SpIds) | Sort-Object -Unique).Count
        CountEventual      = if ($E.Status -eq 200) { [int]("$($E.Body)".Trim()) } else { "$($E.Status) $($E.Code)" }
        CountNoHeader      = if ($N.Status -eq 200) { [int]("$($N.Body)".Trim()) } else { "$($N.Status) $($N.Code)" }
    }
}

function Get-S115Bundle {
    # The newest bundle folder under the step's raw export folder.
    $Root = Join-Path $Raw 'export'
    Get-ChildItem -LiteralPath $Root -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
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
Write-OerLiveStep "The worktree's build lists every group's name once: $(& $Has 'function Get-OERGroupNameIndex')"
Write-OerLiveStep "The worktree's build names a group principal through the index: $(& $Has 'function Get-OERGroupReference')"
Write-OerLiveStep "The worktree's build carries the roster's new keys: $(& $Has 'createdDateTime')"
Write-OerLiveStep "The worktree's build writes the README section on shared names: $(& $Has 'Names two or more objects share')"
Write-OerLiveStep "The worktree's build hands shared names over in an information record: $(& $Has 'Omnicit.EntraRBAC.SharedName')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a
`False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's build:
True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

### 0.2. The prerequisite objects

- [ ] **0.2** The prerequisite script plans, creates, and on a second run finds the whole set and creates nothing.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS115Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS115Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -File $Script @Run *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run plans every object (`What if:` lines) and writes nothing; the first
`-Unattended` run writes the baseline, creates the six groups, the three catalogs, the two packages, the two
policies, the resource group and the role assignment, and adds `oer-live-cc-noperm` to `oer-s115-cnt`,
`unavailable (class B): none`, exit code 0; the second run says `The whole set exists` and creates
nothing, exit code 0.
**Failure looks like:** a `Refusing to run` line (read it; nothing was written), a 401/403 (STOP), or an
`UNAVAILABLE` line (the check it names becomes class B).

Result:

## 1. The member count, measured (BL-130)

### 1.1. Which group fields Microsoft Graph returns without $select

- [ ] **1.1** `v1.0/groups` without `$select` returns `mailEnabled`, `visibility` and `createdDateTime` on every group, and the step's groups carry the types they were created with.

```powershell
Connect-OerLive -Graph
$All = Invoke-OerLiveGraph -All -Uri 'v1.0/groups'
Assert-OerLiveOk -Response $All -Activity 'Listing every group without $select' | Out-Null
$Groups = @(@($All.Body['value']) | Where-Object { $null -ne $_ })
Write-OerLiveStep "Groups listed: $($Groups.Count)"
foreach ($Key in 'mailEnabled', 'visibility', 'createdDateTime') {
    Write-OerLiveStep "Key $($Key): present on $(@($Groups | Where-Object { $_.Contains($Key) }).Count), non-null on $(@($Groups | Where-Object { $_.Contains($Key) -and $null -ne $_[$Key] }).Count)"
}
foreach ($G in @($Groups | Where-Object { ([string]$_['displayName']).StartsWith('oer-s115-', [System.StringComparison]::Ordinal) } | Sort-Object { [string]$_['displayName'] }, { [string]$_['mailNickname'] })) {
    Write-OerLiveStep ("{0} ({1}): securityEnabled {2}; mailEnabled {3}; groupTypes [{4}]; visibility {5}; createdDateTime is a {6}" -f $G['displayName'], $G['mailNickname'], $G['securityEnabled'], $G['mailEnabled'], (@($G['groupTypes']) -join ','), $(if ($null -eq $G['visibility']) { '(null)' } else { $G['visibility'] }), $G['createdDateTime'].GetType().Name)
}
Disconnect-OerLive
```

**Expect:** every key present on every group; the two `oer-s115-dup`, `oer-s115-mix` (security),
`oer-s115-cnt` and `oer-s115-req` groups security-enabled, not mail-enabled, no group type; the
`oer-s115-mix` Microsoft 365 group not security-enabled, mail-enabled, `Unified`, `Private`; every
`createdDateTime` a `DateTime` (the SDK parses it).
**Failure looks like:** a key absent -- the roster would need `$select` or a read of its own.

Result:

### 1.2. A member count with ConsistencyLevel: eventual against the full read, with a service principal member

- [ ] **1.2** For `oer-s115-cnt`, whose only member is a service principal, `members/$count` with `ConsistencyLevel: eventual` is compared with the full read the module makes.

```powershell
Connect-OerLive -Graph
Write-OerLiveStep "oer-s115-cnt recorded: $([bool]$Ids['cnt'])"
Get-S115MemberCount -Id $Ids['cnt'] | Format-List | Out-String | ForEach-Object { Write-OerLiveStep $_.TrimEnd() }
Disconnect-OerLive
```

**Expect:** `MembersList` and `SpList` and `FullRead` as measured, `CountNoHeader` a `400
Request_UnsupportedQuery`; whether `CountEventual` equals `FullRead` (the service principal counted) is the
measurement.
**Failure looks like:** a refusal -- read the code.

Result:

### 1.3. The count directly after a membership change

- [ ] **1.3** A second member is added to `oer-s115-cnt` and removed again; the eventual count is read at once and then until it equals the full read.

```powershell
Connect-OerLive -Graph
$Cnt = $Ids['cnt']; $Member = $Ids['dup-2']
Assert-OerLivePrefix -Name ([string](Invoke-OerLiveGraph -Uri "v1.0/groups/$Cnt`?`$select=displayName").Body['displayName'])
Assert-OerLivePrefix -Name ([string](Invoke-OerLiveGraph -Uri "v1.0/groups/$Member`?`$select=displayName").Body['displayName'])
foreach ($Step in 'add', 'remove') {
    $R = if ($Step -eq 'add') {
        Invoke-OerLiveGraph -Method POST -Uri "v1.0/groups/$Cnt/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$Member" }
    } else {
        Invoke-OerLiveGraph -Method DELETE -Uri "v1.0/groups/$Cnt/members/$Member/`$ref"
    }
    Assert-OerLiveOk -Response $R -Activity "The membership $Step" | Out-Null
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $C = Get-S115MemberCount -Id $Cnt
        Write-OerLiveStep ("after the {0}, {1:F0} s: full read {2}; eventual count {3}" -f $Step, $Watch.Elapsed.TotalSeconds, $C.FullRead, $C.CountEventual)
        if ("$($C.CountEventual)" -eq "$($C.FullRead)" -and $Watch.Elapsed.TotalSeconds -ge 1) { break }
        Start-Sleep -Seconds 5
    } while ($Watch.Elapsed.TotalSeconds -lt 300)
}
Disconnect-OerLive
```

**Expect:** the full read follows the change at once (or within seconds); how long the eventual count lags
is the measurement. Both requests answer 2xx.
**Failure looks like:** a refusal on the membership change (STOP, a 403 on the app path).

Result:

## 2. An export of the test tenant

### 2.1. The export, every group read in full

- [ ] **2.1** `Export-OERInventory -AllGroupsDetailed` with the default sections writes the bundle, warns once about the shared names, and writes nothing to the tenant.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
Start-S115Count
$Out = Join-Path $Raw 'export'
$null = New-Item -ItemType Directory -Path $Out -Force
$W = $null; $E = $null
$B = Export-OERInventory -OutputPath $Out -AllGroupsDetailed -WarningVariable W -ErrorVariable E -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S115Sent)
Stop-S115Count
Write-OerLiveStep "Bundle written: $([bool]$B.BundlePath); groups $($B.Groups); catalogs $($B.Catalogs); access packages $($B.AccessPackages); role assignments $($B.RoleAssignments); roster $($B.RosterCount)"
$Shared = @($W | Where-Object { ([string]$_.Message).StartsWith('Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares') })
Write-OerLiveStep "Shared-name warnings: $($Shared.Count)"
foreach ($S in $Shared) { Write-OerLiveStep "Warning: $($S.Message)" }
Write-OerLiveStep "IncompleteReads entries naming the step's objects: $((@($B.IncompleteReads) -split ', ' | Where-Object { $_ -like '*oer-s115-*' }) -join ' | ')"
Write-OerLiveStep "Errors: $(@($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Disconnect-OerLive
```

**Expect:** a bundle; the request line with `writes: 0` for Microsoft Graph and Azure Resource Manager;
exactly ONE shared-name warning, naming at least 4 names and 8 objects (the step's four: `oer-s115-dup`,
`oer-s115-mix`, `oer-s115-cat`, and `oer-s115-pol` in `oer-s115-ap-b`; more when the tenant holds other
shared names); `groups/oer-s115-dup`, `groups/oer-s115-mix`, `catalogs/oer-s115-cat` and
`accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol` among the IncompleteReads entries; the
errors only `InventoryPartial`.
**Failure looks like:** no warning, or two; a write; a missing entry.

Result:

### 2.2. The roster carries id and type, and tells same-named groups apart

- [ ] **2.2** Every row of `groupsRoster.json` carries the 11 keys in order; the two `oer-s115-dup` rows and the two `oer-s115-mix` rows differ by `id` and carry their own type.

```powershell
$Bundle = (Get-S115Bundle).FullName
$Roster = @(Get-Content -LiteralPath (Join-Path $Bundle 'groupsRoster.json') -Raw | ConvertFrom-Json -DateKind String)
$Order = 'displayName,roleAssignable,dynamic,onPremisesSynced,memberCount,id,securityEnabled,mailEnabled,groupTypes,visibility,createdDateTime'
Write-OerLiveStep "Rows: $($Roster.Count); every row carries the 11 keys in order: $(@($Roster | Where-Object { (@($_.PSObject.Properties.Name) -join ',') -ne $Order }).Count -eq 0)"
foreach ($Name in 'oer-s115-dup', 'oer-s115-mix') {
    $Rows = @($Roster | Where-Object { $_.displayName -ceq $Name })
    Write-OerLiveStep "$($Name): rows $($Rows.Count); distinct ids $(@($Rows.id | Sort-Object -Unique).Count)"
    foreach ($Row in $Rows) {
        $Key = @($Ids.Keys | Where-Object { $Ids[$_] -eq ([string]$Row.id).ToLowerInvariant() })
        Write-OerLiveStep ("  the row of {0}: securityEnabled {1}; mailEnabled {2}; groupTypes [{3}]; visibility {4}; createdDateTime {5}; memberCount {6}" -f ($Key -join ','), $Row.securityEnabled, $Row.mailEnabled, (@($Row.groupTypes) -join ','), $(if ($null -eq $Row.visibility) { '(null)' } else { $Row.visibility }), $(if ([string]$Row.createdDateTime -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$') { 'ISO 8601 UTC' } else { "'$($Row.createdDateTime)'" }), $(if ($null -eq $Row.memberCount) { 'null' } else { $Row.memberCount }))
    }
}
$Text = Get-Content -LiteralPath (Join-Path $Bundle 'groupsRoster.json') -Raw
Write-OerLiveStep "groupTypes is written as a JSON array on every row: $(([regex]::Matches($Text, '"groupTypes":\s*\[')).Count -eq $Roster.Count)"
```

**Expect:** every row carries the 11 keys in order (`True`); two rows and two distinct ids for each name,
each id one the prerequisite script recorded (`dup-1`, `dup-2`; `mix-sec`, `mix-m365`); the security rows
`securityEnabled True; mailEnabled False; groupTypes []`, the Microsoft 365 row `securityEnabled False;
mailEnabled True; groupTypes [Unified]; visibility Private`; every `createdDateTime` `ISO 8601 UTC`;
`groupTypes` an array on every row (`True`).
**Failure looks like:** a missing key, one id for two rows, a `createdDateTime` that is not UTC ISO 8601.

Result:

### 2.3. The README names each shared name with its count and section

- [ ] **2.3** `README.md` has the section "Names two or more objects share", with one bullet per shared name, its count and its section.

```powershell
$Bundle = (Get-S115Bundle).FullName
$Readme = Get-Content -LiteralPath (Join-Path $Bundle 'README.md') -Raw
$Start = $Readme.IndexOf('## Names two or more objects share')
Write-OerLiveStep "The section is there: $($Start -ge 0)"
$Section = $Readme.Substring($Start)
$Next = $Section.IndexOf("`n## ", 5)
if ($Next -gt 0) { $Section = $Section.Substring(0, $Next) }
foreach ($Line in @($Section -split "`r?`n" | Where-Object { $_ -like '- *oer-s115-*' })) { Write-OerLiveStep "Bullet: $Line" }
Write-OerLiveStep "Bullets in the section: $(@($Section -split "`r?`n" | Where-Object { $_ -like '- *' }).Count)"
```

**Expect:** the section is there; the bullets `` `oer-s115-dup` -- 2 objects, section `groups` ``,
`` `oer-s115-mix` -- 2 objects, section `groups` ``, `` `oer-s115-cat` -- 2 objects, section `catalogs` `` and
`` `oer-s115-ap-b/oer-s115-pol` -- 2 objects, section `assignmentPolicies` ``; the number of bullets equals the
names the warning in 2.1 counted.
**Failure looks like:** the section missing, a count other than 2, a name missing.

Result:

### 2.4. inventory.json leaves the shared names out and names a left-out catalog by its id

- [ ] **2.4** `inventory.json` holds none of the shared-name objects; `oer-s115-ap-a` names its catalog by the catalog's id; `oer-s115-ap-b` holds no `oer-s115-pol` policy; unique names are written as before.

```powershell
$Bundle = (Get-S115Bundle).FullName
$Doc = Get-Content -LiteralPath (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json -DateKind String
Write-OerLiveStep "Groups named oer-s115-dup or oer-s115-mix: $(@($Doc.groups | Where-Object { $_.displayName -in 'oer-s115-dup', 'oer-s115-mix' }).Count)"
Write-OerLiveStep "Groups named oer-s115-cnt or oer-s115-req (unique names, written as before): $(@($Doc.groups | Where-Object { $_.displayName -in 'oer-s115-cnt', 'oer-s115-req' }).Count)"
Write-OerLiveStep "Catalogs named oer-s115-cat: $(@($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-cat' }).Count); named oer-s115-catu: $(@($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-catu' }).Count)"
$ApA = @($Doc.accessPackages | Where-Object { $_.displayName -eq 'oer-s115-ap-a' })
Write-OerLiveStep "oer-s115-ap-a entries: $($ApA.Count); its catalog is the id of the first oer-s115-cat: $(@($ApA | Where-Object { ([string]$_.catalog).ToLowerInvariant() -eq $Ids['cat-1'] }).Count -eq 1)"
$ApB = @($Doc.accessPackages | Where-Object { $_.displayName -eq 'oer-s115-ap-b' })
Write-OerLiveStep "oer-s115-ap-b entries: $($ApB.Count); its catalog: $(@($ApB.catalog) -join ','); its policies named oer-s115-pol: $(@($ApB.assignmentPolicies | Where-Object { $_.displayName -eq 'oer-s115-pol' }).Count); policies written: $(@($ApB.assignmentPolicies).Count)"
Write-OerLiveStep "Any catalog reference written as an object id in the document: $(@($Doc.accessPackages | Where-Object { [string]$_.catalog -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' }).Count)"
```

**Expect:** 0 groups named `oer-s115-dup` or `oer-s115-mix`; 2 groups `oer-s115-cnt`/`oer-s115-req`
(security groups, `-AllGroupsDetailed`); 0 catalogs `oer-s115-cat` and 1 `oer-s115-catu`; one
`oer-s115-ap-a` entry whose catalog is the first catalog's id (`True`); one `oer-s115-ap-b` entry with catalog
`oer-s115-catu` and no policy (0 named, 0 written).
**Failure looks like:** a shared-name group or catalog in the document, `oer-s115-ap-a` named by the shared
catalog name, a `oer-s115-pol` policy written.

Result:

### 2.5. A group with a shared name as a principal is written by its id

- [ ] **2.5** The Reader role assignment at `oer-s115-rg` names the first `oer-s115-dup` group by its object id, with principalType Group.

```powershell
$Bundle = (Get-S115Bundle).FullName
$Doc = Get-Content -LiteralPath (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json -DateKind String
$Ra = @($Doc.roleAssignments | Where-Object { [string]$_.scope -like '*/resourceGroups/oer-s115-rg' })
Write-OerLiveStep "Role assignments at oer-s115-rg: $($Ra.Count)"
foreach ($Row in $Ra) {
    Write-OerLiveStep ("role {0}; the principal is the first oer-s115-dup group's id: {1}; principalType {2}; keys {3}" -f $Row.role, (([string]$Row.principal).ToLowerInvariant() -eq $Ids['dup-1']), $Row.principalType, (@($Row.PSObject.Properties.Name) -join ','))
}
Write-OerLiveStep "Role assignments whose principal is oer-s115-dup by name: $(@($Doc.roleAssignments | Where-Object { $_.principal -eq 'oer-s115-dup' }).Count)"
```

**Expect:** one role assignment, role `Reader`, principal the first group's id (`True`), principalType
`Group`, written directly after `principal` (keys `scope,role,principal,principalType`); 0 by name.
**Failure looks like:** the principal written as `oer-s115-dup`, or principalType missing.

Result:

### 2.6. The export without -AllGroupsDetailed reports the same shared names

- [ ] **2.6** The default export (groups decided by relevance) warns once and lists the same names in its README.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
Start-S115Count
$Out = Join-Path $Raw 'export-default'
$null = New-Item -ItemType Directory -Path $Out -Force
$W = $null
$B = Export-OERInventory -OutputPath $Out -WarningVariable W -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S115Sent)
Stop-S115Count
$Shared = @($W | Where-Object { ([string]$_.Message).StartsWith('Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares') })
Write-OerLiveStep "Shared-name warnings: $($Shared.Count)"
foreach ($S in $Shared) { Write-OerLiveStep "Warning: $($S.Message)" }
$Readme = Get-Content -LiteralPath (Join-Path $B.BundlePath 'README.md') -Raw
foreach ($Line in @($Readme -split "`r?`n" | Where-Object { $_ -like '- *oer-s115-*objects, section*' })) { Write-OerLiveStep "Bullet: $Line" }
Disconnect-OerLive
```

**Expect:** `writes: 0`; ONE shared-name warning with the same counts as 2.1; the same four bullets.
**Failure looks like:** a name missing because its group was not relevant (the count is made over every
listed group, R8).

Result:

## 3. The exported document applies

### 3.1. The validator accepts the export

- [ ] **3.1** `Test-OERStructure` on the exported `inventory.json` is valid, with no Error.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Bundle = (Get-S115Bundle).FullName
$V = Test-OERStructure -Path (Join-Path $Bundle 'inventory.json')
Write-OerLiveStep "Valid: $($V.Valid); errors: $(@($V.Errors).Count); warnings: $(@($V.Warnings).Count)"
foreach ($F in @($V.Errors)) { Write-OerLiveStep "Error at $($F.Path): $($F.Message)" }
foreach ($F in @($V.Warnings | Where-Object { "$($_.Path) $($_.Message)" -like '*oer-s115-*' -or [string]$_.Item -like 'oer-s115-*' })) { Write-OerLiveStep "Warning at $($F.Path): $($F.Message)" }
Disconnect-OerLive
```

**Expect:** `Valid: True; errors: 0`; for `oer-s115-ap-a` at most the Warning that its catalog (by id) is not
declared in the document ("It may already exist in the tenant").
**Failure looks like:** an Error.

Result:

### 3.2. The plan of the whole export: no AmbiguousName, and nothing written

- [ ] **3.2** `Invoke-OERStructure -WhatIf` on the exported document, twice: no AmbiguousName, no Failed row for anything the export wrote, only Unchanged for the step's entries, and no write.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Bundle = (Get-S115Bundle).FullName
foreach ($Pass in 1, 2) {
    Start-S115Count
    $E = $null
    $Rows = @(Invoke-OERStructure -Path (Join-Path $Bundle 'inventory.json') -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue 3>$null 6>$null)
    Write-OerLiveStep "Pass $($Pass): $(Get-S115Sent)"
    Stop-S115Count
    Write-OerLiveStep "Pass $($Pass): rows $($Rows.Count); by status: $(($Rows | Group-Object Status | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    Write-OerLiveStep "Pass $($Pass): AmbiguousName records: $(@($E | Where-Object { [string]$_.FullyQualifiedErrorId -like '*Ambiguous*' }).Count); error ids: $(@($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', ')"
    foreach ($Row in @($Rows | Where-Object { [string]$_.Item -like 'oer-s115-*' -or [string]$_.Detail -like '*oer-s115-*' })) { Write-OerLiveStep "Pass $($Pass): $($Row.Section) | $($Row.Item) | $($Row.Status) | $($Row.Detail)" }
    foreach ($Row in @($Rows | Where-Object { $_.Status -eq 'Failed' })) { Write-OerLiveStep "Pass $($Pass) FAILED: $($Row.Section) | $($Row.Item) | $($Row.Detail)" }
}
Disconnect-OerLive
```

**Expect:** both passes the same: `writes: 0`; 0 AmbiguousName records; no Failed row; the step's rows
(`oer-s115-catu`, `oer-s115-ap-a`, `oer-s115-ap-b`, the role assignment at `oer-s115-rg`, `oer-s115-cnt`,
`oer-s115-req`) Unchanged, apart from two Extra rows on `oer-s115-ap-b` that report the two `oer-s115-pol`
policies the export left out as still in force (the engine never removes an assignment policy).
**Failure looks like:** an AmbiguousName record or a Failed row for an entry the export wrote.

Result:

### 3.3. The step's entries applied for real, twice: only Unchanged (G8)

- [ ] **3.3** A document holding only the step's entries from the export -- `oer-s115-catu`, `oer-s115-ap-a` with its catalog's id, `oer-s115-ap-b`, and the role assignment by the group's id -- is applied for real twice; every row is Unchanged and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Bundle = (Get-S115Bundle).FullName
$Doc = Get-Content -LiteralPath (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json -DateKind String
$Part = [ordered]@{ version = $Doc.version }
if ($Doc.PSObject.Properties.Name -contains 'tenantId') { $Part.tenantId = $Doc.tenantId }
$Part.catalogs = @($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-catu' })
$Part.accessPackages = @($Doc.accessPackages | Where-Object { $_.displayName -in 'oer-s115-ap-a', 'oer-s115-ap-b' })
$Part.roleAssignments = @($Doc.roleAssignments | Where-Object { [string]$_.scope -like '*/resourceGroups/oer-s115-rg' })
$Path = Join-Path $Raw 'apply-s115.json'
$Part | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
foreach ($Name in @($Part.catalogs.displayName) + @($Part.accessPackages.displayName)) { Assert-OerLivePrefix -Name $Name }
Write-OerLiveStep "Entries: catalogs $(@($Part.catalogs).Count), access packages $(@($Part.accessPackages).Count), role assignments $(@($Part.roleAssignments).Count); every role assignment scope is the step's resource group: $(@($Part.roleAssignments | Where-Object { [string]$_.scope -notlike '*/resourceGroups/oer-s115-rg' }).Count -eq 0)"
foreach ($Pass in 1, 2) {
    Start-S115Count
    $E = $null
    $Rows = @(Invoke-OERStructure -Path $Path -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue 3>$null 6>$null)
    Write-OerLiveStep "Pass $($Pass): $(Get-S115Sent)"
    Stop-S115Count
    foreach ($Row in $Rows) { Write-OerLiveStep "Pass $($Pass): $($Row.Section) | $($Row.Item) | $($Row.Status) | $($Row.Detail)" }
    Write-OerLiveStep "Pass $($Pass): error ids: $(@($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** both passes the same and `writes: 0` for Microsoft Graph and Azure Resource Manager; every row
Unchanged (the catalog, both packages, the role assignment), apart from the two Extra rows on
`oer-s115-ap-b` that report the left-out `oer-s115-pol` policies as still in force; no error.
**Failure looks like:** a write, a Created or Updated row, an AmbiguousName or a Failed row.

Result:

### 3.4. The validator refuses two policies of one name in a package

- [ ] **3.4** A document whose `oer-s115-ap-b` declares both `oer-s115-pol` policies is refused offline with an Error.

```powershell
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{
            displayName = 'oer-s115-ap-b'; catalog = 'oer-s115-catu'
            assignmentPolicies = @([ordered]@{ displayName = 'oer-s115-pol' }, [ordered]@{ displayName = 'OER-S115-POL' })
        })
}
$Path = Join-Path $Raw 'dup-policies-s115.json'
$Doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
Import-Module (Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Select-Object -First 1).FullName -Force
$V = Test-OERStructure -Path $Path
Write-OerLiveStep "Valid: $($V.Valid); errors: $(@($V.Errors).Count)"
foreach ($F in @($V.Errors)) { Write-OerLiveStep "Error at $($F.Path): $($F.Message)" }
```

**Expect:** `Valid: False`, one Error at `accessPackages[0].assignmentPolicies[1]` naming
`accessPackages[0].assignmentPolicies[0]` (the names differ only in letter case). Offline: no sign-in.
**Failure looks like:** `Valid: True`.

Result:

### 3.5. A package missing from its catalog is never written into its twin

- [ ] **3.5** A document declares `oer-s115-ap-a` in the SECOND `oer-s115-cat` catalog (by id), where it does not exist, while `oer-s115-ap-a` exists in the first: the plan says it would create it, and the real run reports Failed and writes nothing.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{ displayName = 'oer-s115-ap-a'; catalog = $Ids['cat-2']; resourceRoles = @(); assignmentPolicies = @() })
}
$Path = Join-Path $Raw 'twin-s115.json'
$Doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
Write-OerLiveStep "The second oer-s115-cat recorded: $([bool]$Ids['cat-2']); oer-s115-ap-a recorded in the first: $([bool]$Ids['ap-a'])"
foreach ($Mode in 'plan', 'run') {
    Start-S115Count
    $E = $null
    $Rows = if ($Mode -eq 'plan') {
        @(Invoke-OERStructure -Path $Path -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue 3>$null 6>$null)
    } else {
        @(Invoke-OERStructure -Path $Path -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue 3>$null 6>$null)
    }
    Write-OerLiveStep "$($Mode): $(Get-S115Sent)"
    Stop-S115Count
    foreach ($Row in $Rows) { Write-OerLiveStep "$($Mode): $($Row.Section) | $($Row.Item) | $($Row.Status) | $($Row.Detail)" }
}
$Pol = Invoke-OerLiveGraph -All -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$($Ids['ap-a'])'"))
Assert-OerLiveOk -Response $Pol -Activity 'Reading the policies of oer-s115-ap-a' | Out-Null
Write-OerLiveStep "oer-s115-ap-a holds $(@(@($Pol.Body['value']) | Where-Object { $null -ne $_ }).Count) assignment policies after the run (it had none)"
$InCat2 = Invoke-OerLiveGraph -All -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("catalog/id eq '$($Ids['cat-2'])'"))
Assert-OerLiveOk -Response $InCat2 -Activity 'Listing the packages of the second oer-s115-cat' | Out-Null
Write-OerLiveStep "Packages in the second oer-s115-cat after the run: $(@(@($InCat2.Body['value']) | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
```

**Expect:** the plan one row `would create access package` (the plan never calls the create, so it cannot
see the twin) and `writes: 0`; the real run ONE `Failed` row whose detail names a package of that name in
another catalog, and `writes: 0` for Microsoft Graph and Azure Resource Manager; `oer-s115-ap-a` still holds 0
policies, and the second catalog still holds 0 packages.
**Failure looks like:** a `Created` row, a write, or a policy on `oer-s115-ap-a` -- the guard did not hold
(everything stays inside the prefix).

Result:

## T. Teardown

### T.1. Remove every oer-s115- object

- [ ] **T.1** The prerequisite script's teardown removes the role assignment, the resource group, the Microsoft 365 group and every other prefixed object, and the sweep finds none.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS115Prereq.ps1'
foreach ($Run in @(@('-Teardown', '-WhatIf'), @('-Teardown', '-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS115Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -File $Script @Run *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run removes nothing; the real run removes the role assignment and the resource
group, the Microsoft 365 group (after retries if Microsoft Graph refuses it at first), the two policies, the
two packages, the three catalogs and the six groups, purges the Microsoft 365 group from the deleted items
(or says it is left there for its 30 days), the sweep finds nothing, the counts equal the baseline, exit
code 0.
**Failure looks like:** a RESIDUE line (exit code 3): name it in the report.

Result:

### T.2. Read back

- [ ] **T.2** A read-only pass finds no prefixed object, no resource group and no residue row of this step.

```powershell
& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS115Prereq.ps1') -ReadBack *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `prefixed objects left: 0`; `resource group oer-s115-rg exists: False`; counts equal to the
baseline; 0 residue rows with this step's prefix.
**Failure looks like:** anything left.

Result:

## B. Proved offline only (class B)

Each line names the unit tests that hold the claim; the gate (`./build.ps1 -Tasks test`) runs them all.

- **B.1 An access review whose package or policy name is shared is written by id, and applies.**
  `tests/Unit/Public/Get-OERInventory.Tests.ps1`, Context "access review references are written by id when
  the apply engine could not resolve the name (BL-142)"; the named deviation is held by the Context "the
  export's review-reference lookups agree with the resolvers (named deviation)"; applied in
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe "Invoke-OERStructure applies what an export
  writes by id: a package's catalog and a review's access package and assignment policy (BL-39, BL-142)".
- **B.2 A group with a shared name as a directory role principal is written by id, and applies.**
  `Get-OERInventory.Tests.ps1`, Context "a group named as a principal is written by its object id when another
  group carries its name (BL-131, Task 3c)"; `Invoke-OERStructure.Tests.ps1`, Describe "Invoke-OERStructure
  applies a group principal an export writes by its object id (BL-131, Task 3c)".
- **B.3 A listing of every group's name that fails, an unread roster, and a failed uniqueness lookup.**
  `tests/Unit/Private/Get-OERGroupNameIndex.Tests.ps1`; `Get-OERInventory.Tests.ps1`, Context "shared names are
  counted over every group in the tenant (BL-131)"; `tests/Unit/Public/Export-OERInventory.Tests.ps1`,
  Describe "Export-OERInventory (names two or more objects share, BL-131)".
- **B.4 The counts and the README section.** `tests/Unit/Private/Get-OERInventoryGroup.Tests.ps1`, Context
  "shared names counted over every group in the tenant (BL-131)"; `tests/Unit/Private/Get-OERInventoryReadme.Tests.ps1`,
  Describe "Get-OERInventoryReadme (names two or more objects share, BL-131)";
  `tests/Unit/Private/Get-OERSharedNameCause.Tests.ps1`.
- **B.5 A group principal whose name could not be read (named by its id) costs no listing.**
  `Get-OERInventory.Tests.ps1`, Context "a group named as a principal is written by its object id when another
  group carries its name (BL-131, Task 3c)".
- **B.6 The twin-catalog guard with the catalog named by a unique display name, a failed catalog lookup, and a
  genuine create.** `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1` and
  `Invoke-OERStructure.Tests.ps1`; 3.5 runs the by-id case live.
- **B.7 The texts.** `tests/QA/docsync.tests.ps1` and `about.tests.ps1` (README and the about topic agree and
  name every cmdlet), `dochygiene.tests.ps1` (no tenant value, no tag-like bracket), `module.tests.ps1` (help,
  the changelog and its budget).
