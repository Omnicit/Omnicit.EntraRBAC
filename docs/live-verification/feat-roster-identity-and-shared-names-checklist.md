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
`oer-s115-req` with no member; a catalog `oer-s115-cat` holding the hidden access package
`oer-s115-ap-a`; an empty catalog `oer-s115-cat2` (Microsoft Graph refuses a second catalog whose name another
carries, letter case aside, on create and on rename, so the planned twin catalogs cannot be made: see 0.2);
a catalog `oer-s115-catu` holding the hidden access package
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
which also covers adding a member, and `EntitlementManagement.ReadWrite.All`; the prerequisite script reads them
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

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

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

Result: 2026-10-14 21:46 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at 225f275 with 0 tracked changes, and its build (built from db93fff, the last commit under source/; 225f275 adds only this checklist) carries every mark.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s115] The module loads from a worktree that is not the main clone: True
[oer-s115] Main clone: branch main; HEAD 491e72e
[oer-s115] Worktree: branch feat/roster-identity-and-shared-names; HEAD 225f275 docs: add the live checklist for the roster's identity and the shared names; tracked changes: 0
[oer-s115] The worktree's build lists every group's name once: True
[oer-s115] The worktree's build names a group principal through the index: True
[oer-s115] The worktree's build carries the roster's new keys: True
[oer-s115] The worktree's build writes the README section on shared names: True
[oer-s115] The worktree's build hands shared names over in an information record: True
RUNNER: check-S.1 exit code 0; started 2026-10-14T21:45:56Z; took 3 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

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

Result: 2026-10-14 21:46 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] The module is the worktree's build: True; version 1.2.1
RUNNER: check-0.1 exit code 0; started 2026-10-14T21:46:33Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The prerequisite objects

- [x] **0.2** The prerequisite script plans, creates, and on a second run finds the whole set and creates nothing.

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

Result: 2026-10-14 21:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, with one deviation measured live. The -WhatIf run planned every object and wrote nothing; the first -Unattended run created the six groups (the Microsoft 365 group included), oer-s115-cat, oer-s115-catu, the two packages, the two policies (the first after one SubjectNotFound retry), the resource group and the role assignment, and added oer-live-cc-noperm to oer-s115-cnt; the second run found the whole set and created only the empty catalog oer-s115-cat2; the third created nothing. MEASURED: Microsoft Graph refuses a catalog whose name another catalog carries, letter case aside, on create (400 DuplicateCatalog, for the exact name and for OER-S115-CAT) and on rename (409 DuplicateKey, oer-s115-cat2 to OER-S115-CAT), so the twin catalogs the checklist planned cannot be made: the twin-catalog case is class B (B.8). Earlier attempts on this run, recorded in the report: a first setup refused (the script asked for GroupMember.ReadWrite.All, which Group.ReadWrite.All covers; nothing written), and a second setup stopped on the DuplicateCatalog after creating six groups and one catalog, which -Teardown removed (counts back at the baseline) before this run.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s115] === Initialize-OerS115Prereq.ps1 -WhatIf ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] What if: Performing the operation "Start the redacted transcript" on target "raw\s115\prereq-20261014-215319Z.log".
[oer-s115] [oer-s115] Mode: CREATE. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] [oer-s115] oer-live-cc holds Group.ReadWrite.All: True
[oer-s115] [oer-s115] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s115] [oer-s115] Found: group 'oer-s115-dup': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-mix': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-cnt': 1 of 1.
[oer-s115] [oer-s115] Found: group 'oer-s115-req': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'OER-S115-CAT': 0 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat2': 0 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-catu': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-a': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-b': 1 of 1.
[oer-s115] What if: Performing the operation "Create a catalog (Graph v1.0 POST entitlementManagement/catalogs: published, not visible to external users, no resource)" on target "oer-s115-cat2 (cat-2)".
[oer-s115] [oer-s115] The whole set exists (10 prefixed objects, every one recorded; optional: the Microsoft 365 group True, the twin catalog False, the role assignment True); nothing is created.
[oer-s115] [oer-s115] WhatIf: nothing was created, removed or written.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
[oer-s115] === Initialize-OerS115Prereq.ps1 -Unattended ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] [oer-s115] Transcript (redacted): raw\s115\prereq-20261014-215325Z.log; OerLive 1.0.3.
[oer-s115] [oer-s115] Mode: CREATE. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] [oer-s115] oer-live-cc holds Group.ReadWrite.All: True
[oer-s115] [oer-s115] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s115] [oer-s115] Found: group 'oer-s115-dup': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-mix': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-cnt': 1 of 1.
[oer-s115] [oer-s115] Found: group 'oer-s115-req': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'OER-S115-CAT': 0 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat2': 0 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-catu': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-a': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-b': 1 of 1.
[oer-s115] [oer-s115] Created catalog oer-s115-cat2 (cat-2): 201.
[oer-s115] [oer-s115] Recorded the id of cat-2 under raw\s115 (not printed).
[oer-s115] [oer-s115] oer-s115-cat2 (cat-2) is readable by its id: converged after 1 read(s), 0.2 s.
[oer-s115] [oer-s115] UNAVAILABLE (class B): the twin catalog (the rename of oer-s115-cat2 to OER-S115-CAT) -- answered 409 DuplicateKey -- There is already a duplicated entity.. The run carries on without it; nothing else is tried.
[oer-s115] [oer-s115] The whole set exists (10 prefixed objects, every one recorded; optional: the Microsoft 365 group True, the twin catalog False, the role assignment True); nothing is created.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
[oer-s115] === Initialize-OerS115Prereq.ps1 -Unattended ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] [oer-s115] Transcript (redacted): raw\s115\prereq-20261014-215331Z.log; OerLive 1.0.3.
[oer-s115] [oer-s115] Mode: CREATE. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] [oer-s115] oer-live-cc holds Group.ReadWrite.All: True
[oer-s115] [oer-s115] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s115] [oer-s115] Found: group 'oer-s115-dup': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-mix': 2 of 2.
[oer-s115] [oer-s115] Found: group 'oer-s115-cnt': 1 of 1.
[oer-s115] [oer-s115] Found: group 'oer-s115-req': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'OER-S115-CAT': 0 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-cat2': 1 of 1.
[oer-s115] [oer-s115] Found: catalog 'oer-s115-catu': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-a': 1 of 1.
[oer-s115] [oer-s115] Found: access package 'oer-s115-ap-b': 1 of 1.
[oer-s115] [oer-s115] The whole set exists (11 prefixed objects, every one recorded; optional: the Microsoft 365 group True, the twin catalog True, the role assignment True); nothing is created.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
RUNNER: check-0.2 exit code 0; started 2026-10-14T21:53:17Z; took 19 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The member count, measured (BL-130)

### 1.1. Which group fields Microsoft Graph returns without $select

- [x] **1.1** `v1.0/groups` without `$select` returns `mailEnabled`, `visibility` and `createdDateTime` on every group, and the step's groups carry the types they were created with.

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

Result: 2026-10-14 21:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. v1.0/groups without $select listed 103 groups (97 plus the step's 6); mailEnabled and createdDateTime present and non-null on all 103, visibility present on all and non-null on 16 (the 15 measured earlier plus the step's Microsoft 365 group). The step's five security groups: securityEnabled True, mailEnabled False, no group type, visibility null; the Microsoft 365 group: securityEnabled False, mailEnabled True, Unified, Private; every createdDateTime arrives as a DateTime. The trailing warning is Disconnect-OER leaving the raw SDK session of Connect-OerLive -Graph (known, S103).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s115] Groups listed: 103
[oer-s115] Key mailEnabled: present on 103, non-null on 103
[oer-s115] Key visibility: present on 103, non-null on 16
[oer-s115] Key createdDateTime: present on 103, non-null on 103
[oer-s115] oer-s115-cnt (oer-s115-cnt): securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime is a DateTime
[oer-s115] oer-s115-dup (oer-s115-dup-1): securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime is a DateTime
[oer-s115] oer-s115-dup (oer-s115-dup-2): securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime is a DateTime
[oer-s115] oer-s115-mix (oer-s115-mix-m365): securityEnabled False; mailEnabled True; groupTypes [Unified]; visibility Private; createdDateTime is a DateTime
[oer-s115] oer-s115-mix (oer-s115-mix-sec): securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime is a DateTime
[oer-s115] oer-s115-req (oer-s115-req): securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime is a DateTime
WARNING: Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.
RUNNER: check-1.1 exit code 0; started 2026-10-14T21:54:51Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. A member count with ConsistencyLevel: eventual against the full read, with a service principal member

- [x] **1.2** For `oer-s115-cnt`, whose only member is a service principal, `members/$count` with `ConsistencyLevel: eventual` is compared with the full read the module makes.

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

Result: 2026-10-14 21:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (measurement). oer-s115-cnt, whose only member is the service principal oer-live-cc-noperm: the v1.0 member list returned 0 (it leaves the service principal out), the servicePrincipal cast returned 1, the full read the module makes (both joined) 1; members/$count with ConsistencyLevel: eventual answered 1 -- it counts the service principal, equal to the full read; without the header 400 Request_UnsupportedQuery.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s115] oer-s115-cnt recorded: True
[oer-s115] 
MembersList        : 0
SpList             : 1
MembersListHoldsSp : 0
FullRead           : 1
CountEventual      : 1
CountNoHeader      : 400 Request_UnsupportedQuery
WARNING: Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.
RUNNER: check-1.2 exit code 0; started 2026-10-14T21:55:04Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. The count directly after a membership change

- [x] **1.3** A second member is added to `oer-s115-cnt` and removed again; the eventual count is read at once and then until it equals the full read.

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

Result: 2026-10-14 21:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (measurement). Both membership changes answered 2xx. After the add (the second oer-s115-dup group as a member of oer-s115-cnt) both reads first still showed 1; the eventual count showed 2 at 6 s, the full read only at 16 s. After the remove both still showed 2 at once and 1 at 6 s. In this tenant the eventual count lagged no more than the full read did: both trail a change by seconds.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s115] after the add, 0 s: full read 1; eventual count 1
[oer-s115] after the add, 6 s: full read 1; eventual count 2
[oer-s115] after the add, 11 s: full read 1; eventual count 2
[oer-s115] after the add, 16 s: full read 2; eventual count 2
[oer-s115] after the remove, 0 s: full read 2; eventual count 2
[oer-s115] after the remove, 6 s: full read 1; eventual count 1
WARNING: Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.
RUNNER: check-1.3 exit code 0; started 2026-10-14T21:55:19Z; took 26 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. An export of the test tenant

### 2.1. The export, every group read in full

- [x] **2.1** `Export-OERInventory -AllGroupsDetailed` with the default sections writes the bundle, warns once about the shared names, and writes nothing to the tenant.

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
exactly ONE shared-name warning, naming at least 3 names and 6 objects (the step's three: `oer-s115-dup`,
`oer-s115-mix`, and `oer-s115-pol` in `oer-s115-ap-b`; more when the tenant holds other shared names);
`groups/oer-s115-dup`, `groups/oer-s115-mix` and
`accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol` among the IncompleteReads entries; the
errors only `InventoryPartial`.
**Failure looks like:** no warning, or two; a write; a missing entry.

Result: 2026-10-14 21:59 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The bundle was written; exactly ONE shared-name warning, 3 names carried by 6 objects (the step's oer-s115-dup, oer-s115-mix and oer-s115-pol in oer-s115-ap-b; the tenant holds no other shared name); groups/oer-s115-dup, groups/oer-s115-mix and accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol among the IncompleteReads entries. No write: the 11 POSTs counted are v1.0/directoryObjects/getByIds, a read sent as POST; Azure Resource Manager 10 requests, 0 writes; no token request. The errors are InventoryPartial (the inner one, shown, and the export's own) and two AuthorizationFailed records of the management-group listing this identity is refused (measured in earlier steps), named in the README as '<management groups: the listing failed>' -- not this step's.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
ERROR: Get-OERInventory: This inventory is PARTIAL: 1 collection(s) or object(s) could not be read, could not be written without an empty name,
ERROR: or were left out because two or more live objects share a name, and are not stated as facts in the document (an
ERROR: accessReviews entry named as unread may still carry an id where a name could not be read). Unread:
ERROR: accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol. A section reported here by its name alone could not be
ERROR: read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles,
ERROR: resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do
ERROR: not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: 2 live objects
ERROR: share the name accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol (compared without regard to letter case),
ERROR: so none of them is written: the apply engine refuses an ambiguous name..
[oer-s115] token requests: 0; Microsoft Graph requests: 761, writes: 11 (POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds); Azure Resource Manager requests: 10, writes: 0
[oer-s115] Bundle written: True; groups 93; catalogs 8; access packages 8; role assignments 14; roster 103
[oer-s115] Shared-name warnings: 1
[oer-s115] Warning: Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares, since the apply engine refuses an ambiguous name: 3 name(s), carried by 6 object(s) in all. README.md lists each name, how many objects carry it and its section under 'Names two or more objects share'.
[oer-s115] IncompleteReads entries naming the step's objects: groups/oer-s115-dup | groups/oer-s115-mix | accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol
[oer-s115] Errors: InventoryPartial, AuthorizationFailed, AuthorizationFailed, InventoryPartial
RUNNER: check-2.1 exit code 0; started 2026-10-14T21:55:56Z; took 221 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. The roster carries id and type, and tells same-named groups apart

- [x] **2.2** Every row of `groupsRoster.json` carries the 11 keys in order; the two `oer-s115-dup` rows and the two `oer-s115-mix` rows differ by `id` and carry their own type.

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

Result: 2026-10-14 22:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. 103 rows, every row with the 11 keys in order; oer-s115-dup and oer-s115-mix each have two rows with two distinct ids, each id one the prerequisite script recorded (dup-1, dup-2; mix-sec, mix-m365); the security rows securityEnabled True, mailEnabled False, groupTypes [], visibility null; the Microsoft 365 row securityEnabled False, mailEnabled True, groupTypes [Unified], visibility Private; every createdDateTime ISO 8601 UTC; groupTypes an array on every row; memberCount null for the four (left out for a shared name, or not security-enabled), as documented.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s115] Rows: 103; every row carries the 11 keys in order: True
[oer-s115] oer-s115-dup: rows 2; distinct ids 2
[oer-s115]   the row of dup-2: securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime ISO 8601 UTC; memberCount null
[oer-s115]   the row of dup-1: securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime ISO 8601 UTC; memberCount null
[oer-s115] oer-s115-mix: rows 2; distinct ids 2
[oer-s115]   the row of mix-m365: securityEnabled False; mailEnabled True; groupTypes [Unified]; visibility Private; createdDateTime ISO 8601 UTC; memberCount null
[oer-s115]   the row of mix-sec: securityEnabled True; mailEnabled False; groupTypes []; visibility (null); createdDateTime ISO 8601 UTC; memberCount null
[oer-s115] groupTypes is written as a JSON array on every row: True
RUNNER: check-2.2 exit code 0; started 2026-10-14T21:59:57Z; took 1 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.3. The README names each shared name with its count and section

- [x] **2.3** `README.md` has the section "Names two or more objects share", with one bullet per shared name, its count and its section.

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
`` `oer-s115-mix` -- 2 objects, section `groups` `` and
`` `oer-s115-ap-b/oer-s115-pol` -- 2 objects, section `assignmentPolicies` ``; the number of bullets equals the
names the warning in 2.1 counted.
**Failure looks like:** the section missing, a count other than 2, a name missing.

Result: 2026-10-14 22:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The README section 'Names two or more objects share' is there with exactly 3 bullets, the step's: oer-s115-dup -- 2 objects, section groups; oer-s115-mix -- 2 objects, section groups (the security group and the Microsoft 365 group); oer-s115-ap-b/oer-s115-pol -- 2 objects, section assignmentPolicies. The count matches the warning's 3 names and 6 objects. No catalog bullet: two catalogs of one name cannot be made in this tenant (0.2).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s115] The section is there: True
[oer-s115] Bullet: - `oer-s115-dup` -- 2 objects, section `groups`
[oer-s115] Bullet: - `oer-s115-mix` -- 2 objects, section `groups`
[oer-s115] Bullet: - `oer-s115-ap-b/oer-s115-pol` -- 2 objects, section `assignmentPolicies`
[oer-s115] Bullets in the section: 3
RUNNER: check-2.3 exit code 0; started 2026-10-14T22:00:09Z; took 1 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.4. inventory.json leaves the shared names out and writes unique names as before

- [x] **2.4** `inventory.json` holds none of the shared-name objects; `oer-s115-ap-b` holds no `oer-s115-pol` policy; unique names -- the groups `oer-s115-cnt` and `oer-s115-req`, the catalogs and `oer-s115-ap-a`'s catalog -- are written as before.

```powershell
$Bundle = (Get-S115Bundle).FullName
$Doc = Get-Content -LiteralPath (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json -DateKind String
Write-OerLiveStep "Groups named oer-s115-dup or oer-s115-mix: $(@($Doc.groups | Where-Object { $_.displayName -in 'oer-s115-dup', 'oer-s115-mix' }).Count)"
Write-OerLiveStep "Groups named oer-s115-cnt or oer-s115-req (unique names, written as before): $(@($Doc.groups | Where-Object { $_.displayName -in 'oer-s115-cnt', 'oer-s115-req' }).Count)"
Write-OerLiveStep "Catalogs named oer-s115-cat: $(@($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-cat' }).Count); named oer-s115-catu: $(@($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-catu' }).Count)"
$ApA = @($Doc.accessPackages | Where-Object { $_.displayName -eq 'oer-s115-ap-a' })
Write-OerLiveStep "oer-s115-ap-a entries: $($ApA.Count); its catalog: $(@($ApA.catalog) -join ',') (written by name: $(@($ApA | Where-Object { $_.catalog -ceq 'oer-s115-cat' }).Count -eq 1))"
Write-OerLiveStep "Catalogs named oer-s115-cat2: $(@($Doc.catalogs | Where-Object { $_.displayName -eq 'oer-s115-cat2' }).Count)"
$ApB = @($Doc.accessPackages | Where-Object { $_.displayName -eq 'oer-s115-ap-b' })
Write-OerLiveStep "oer-s115-ap-b entries: $($ApB.Count); its catalog: $(@($ApB.catalog) -join ','); its policies named oer-s115-pol: $(@($ApB.assignmentPolicies | Where-Object { $_.displayName -eq 'oer-s115-pol' }).Count); policies written: $(@($ApB.assignmentPolicies).Count)"
Write-OerLiveStep "Any catalog reference written as an object id in the document: $(@($Doc.accessPackages | Where-Object { [string]$_.catalog -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' }).Count)"
```

**Expect:** 0 groups named `oer-s115-dup` or `oer-s115-mix`; 2 groups `oer-s115-cnt`/`oer-s115-req`
(security groups, `-AllGroupsDetailed`); 1 catalog `oer-s115-cat`, 1 `oer-s115-catu` and 1 `oer-s115-cat2`;
one `oer-s115-ap-a` entry whose catalog is written by name (`True`), since no other catalog carries it; one
`oer-s115-ap-b` entry with catalog `oer-s115-catu` and no policy (0 named, 0 written); 0 catalog references
written as an object id. A catalog written by its id needs two catalogs of one name, which this tenant
refuses to hold (0.2): class B (B.8).
**Failure looks like:** a shared-name group in the document, a unique name written by id, a `oer-s115-pol`
policy written.

Result: 2026-10-14 22:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. inventory.json holds no group named oer-s115-dup or oer-s115-mix; the unique oer-s115-cnt and oer-s115-req are written (2, -AllGroupsDetailed); the catalogs oer-s115-cat, oer-s115-catu and oer-s115-cat2 once each; oer-s115-ap-a with its catalog written by name, oer-s115-cat, as before (no other catalog carries the name); oer-s115-ap-b with catalog oer-s115-catu, no oer-s115-pol policy and assignmentPolicies [] (read back below; the block's 'policies written: 1' is its own counting artefact); 0 catalog references written as an object id. The catalog-by-id case is class B (B.8).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.4 ===
[oer-s115] Groups named oer-s115-dup or oer-s115-mix: 0
[oer-s115] Groups named oer-s115-cnt or oer-s115-req (unique names, written as before): 2
[oer-s115] Catalogs named oer-s115-cat: 1; named oer-s115-catu: 1
[oer-s115] oer-s115-ap-a entries: 1; its catalog: oer-s115-cat (written by name: True)
[oer-s115] Catalogs named oer-s115-cat2: 1
[oer-s115] oer-s115-ap-b entries: 1; its catalog: oer-s115-catu; its policies named oer-s115-pol: 0; policies written: 1
[oer-s115] Any catalog reference written as an object id in the document: 0
RUNNER: check-2.4 exit code 0; started 2026-10-14T22:00:12Z; took 1 s.
LEAK CHECK: psd1 values surviving redaction: 0
READ-BACK (controller, same bundle): the oer-s115-ap-b entry of inventory.json reads displayName oer-s115-ap-b; catalog oer-s115-catu; hidden true; resourceRoles []; assignmentPolicies [] -- the 'policies written: 1' above is the block's own member enumeration counting the empty array as one item (@($ApB.assignmentPolicies) over a one-element array), not a written policy.
```

### 2.5. A group with a shared name as a principal is written by its id

- [x] **2.5** The Reader role assignment at `oer-s115-rg` names the first `oer-s115-dup` group by its object id, with principalType Group.

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

Result: 2026-10-14 22:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. One role assignment at oer-s115-rg: role Reader, principal the first oer-s115-dup group's object id (True), principalType Group directly after principal (keys scope, role, principal, principalType); 0 role assignments name oer-s115-dup by name.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.5 ===
[oer-s115] Role assignments at oer-s115-rg: 1
[oer-s115] role Reader; the principal is the first oer-s115-dup group's id: True; principalType Group; keys scope,role,principal,principalType
[oer-s115] Role assignments whose principal is oer-s115-dup by name: 0
RUNNER: check-2.5 exit code 0; started 2026-10-14T22:00:14Z; took 1 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.6. The export without -AllGroupsDetailed reports the same shared names

- [x] **2.6** The default export (groups decided by relevance) warns once and lists the same names in its README.

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

Result: 2026-10-14 22:03 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The default export (groups decided by relevance) made 359 Microsoft Graph requests against 761 with -AllGroupsDetailed, wrote nothing (the 11 POSTs are getByIds reads; ARM 10 requests, 0 writes), warned ONCE with the same counts (3 names, 6 objects) and listed the same three bullets: the step's groups are not relevant, and the names are still counted over every listed group (R8).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.6 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
ERROR: Get-OERInventory: This inventory is PARTIAL: 1 collection(s) or object(s) could not be read, could not be written without an empty name,
ERROR: or were left out because two or more live objects share a name, and are not stated as facts in the document (an
ERROR: accessReviews entry named as unread may still carry an id where a name could not be read). Unread:
ERROR: accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol. A section reported here by its name alone could not be
ERROR: read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles,
ERROR: resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do
ERROR: not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: 2 live objects
ERROR: share the name accessPackages/oer-s115-ap-b/assignmentPolicies/oer-s115-pol (compared without regard to letter case),
ERROR: so none of them is written: the apply engine refuses an ambiguous name..
[oer-s115] token requests: 0; Microsoft Graph requests: 359, writes: 11 (POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds, POST v1.0/directoryObjects/getByIds); Azure Resource Manager requests: 10, writes: 0
[oer-s115] Shared-name warnings: 1
[oer-s115] Warning: Export-OERInventory: left out of inventory.json and the per-area files every object whose name another object of its kind shares, since the apply engine refuses an ambiguous name: 3 name(s), carried by 6 object(s) in all. README.md lists each name, how many objects carry it and its section under 'Names two or more objects share'.
[oer-s115] Bullet: - `oer-s115-dup` -- 2 objects, section `groups`
[oer-s115] Bullet: - `oer-s115-mix` -- 2 objects, section `groups`
[oer-s115] Bullet: - `oer-s115-ap-b/oer-s115-pol` -- 2 objects, section `assignmentPolicies`
RUNNER: check-2.6 exit code 0; started 2026-10-14T22:00:52Z; took 142 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. The exported document applies

### 3.1. The validator accepts the export

- [x] **3.1** `Test-OERStructure` on the exported `inventory.json` is valid, with no Error.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Bundle = (Get-S115Bundle).FullName
$V = Test-OERStructure -Path (Join-Path $Bundle 'inventory.json')
Write-OerLiveStep "Valid: $($V.Valid); findings: $(@($V.Errors).Count) (Error $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count), Warning $(@($V.Errors | Where-Object { $_.Severity -eq 'Warning' }).Count))"
foreach ($F in @($V.Errors | Where-Object { $_.Severity -eq 'Error' })) { Write-OerLiveStep "Error at $($F.Path): $($F.Message)" }
foreach ($F in @($V.Errors | Where-Object { $_.Severity -ne 'Error' -and ("$($_.Path) $($_.Message)" -like '*oer-s115-*' -or [string]$_.Item -like 'oer-s115-*') })) { Write-OerLiveStep "$($F.Severity) at $($F.Path): $($F.Message)" }
Disconnect-OerLive
```

**Expect:** `Valid: True; errors: 0`; no Warning about the step's entries (every catalog they name is in the
document).
**Failure looks like:** an Error.

Result: 2026-10-14 22:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Test-OERStructure on the exported inventory.json (the -AllGroupsDetailed bundle of 2.1): Valid True with 0 findings, no Error and no Warning. (A first run of this block read a Warnings property the result does not have; the validator returns every finding in Errors with a Severity. Fixed in the block and run again.)

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] Valid: True; findings: 0 (Error 0, Warning 0)
RUNNER: check-3.1 exit code 0; started 2026-10-14T22:18:03Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The plan of the whole export: no AmbiguousName, and nothing written

- [x] **3.2** `Invoke-OERStructure -WhatIf` on the exported document, twice: no AmbiguousName, no Failed row for anything the export wrote, only Unchanged for the step's entries, and no write.

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
    Write-OerLiveStep "Pass $($Pass): rows $($Rows.Count); by action: $(($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    Write-OerLiveStep "Pass $($Pass): AmbiguousName records: $(@($E | Where-Object { [string]$_.FullyQualifiedErrorId -like '*Ambiguous*' }).Count); error ids: $(@($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', ')"
    foreach ($Row in @($Rows | Where-Object { [string]$_.Item -like 'oer-s115-*' -or [string]$_.Detail -like '*oer-s115-*' })) { Write-OerLiveStep "Pass $($Pass): $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
    foreach ($Row in @($Rows | Where-Object { $_.Action -eq 'Failed' })) { Write-OerLiveStep "Pass $($Pass) FAILED: $($Row.Section) | $($Row.Item) | $($Row.Detail)" }
}
Disconnect-OerLive
```

**Expect:** both passes the same: `writes: 0`; 0 AmbiguousName records; no Failed row; the step's rows
(`oer-s115-cat`, `oer-s115-catu`, `oer-s115-cat2`, `oer-s115-ap-a`, `oer-s115-ap-b`, the role assignment at
`oer-s115-rg`, `oer-s115-cnt`, `oer-s115-req`) Unchanged, apart from two Extra rows on `oer-s115-ap-b` that report the two `oer-s115-pol`
policies the export left out as still in force (the engine never removes an assignment policy).
**Failure looks like:** an AmbiguousName record or a Failed row for an entry the export wrote.

Result: 2026-10-14 22:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS for the step's claim, with 6 Failed rows that are not this step's. Both passes identical: 466 rows (Unchanged 391, Skipped 67, Extra 2, Failed 6); 0 AmbiguousName records; writes 0 (Microsoft Graph 1044 requests, Azure Resource Manager 42); no token request. Every row of the step's entries is Unchanged -- oer-s115-cnt (properties, and its service principal member), oer-s115-req, the catalogs oer-s115-cat, oer-s115-catu and oer-s115-cat2, the packages oer-s115-ap-a and oer-s115-ap-b, and the Reader role assignment at oer-s115-rg written with the group's id -- apart from the two expected Extra rows on oer-s115-ap-b for the left-out oer-s115-pol policies. The 6 Failed rows are role assignments at two management groups that this identity may not read (AuthorizationFailed on the role assignment read at that scope; the export already named the management-group listing as unread): a known limit of oer-live-cc, outside the step, and the plan wrote nothing for them. Management group and principal names in those 6 lines are masked by the controller (MG-1, MG-2, principal-1..5). The Skipped rows are pre-existing (dynamic groups' members and similar), unchanged between passes. A first run of this block printed no status (it read a Status property; the rows carry Action), fixed in the block and run again.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] Pass 1: token requests: 0; Microsoft Graph requests: 1044, writes: 0; Azure Resource Manager requests: 42, writes: 0
[oer-s115] Pass 1: rows 466; by action: Extra 2, Failed 6, Skipped 67, Unchanged 391
[oer-s115] Pass 1: AmbiguousName records: 0; error ids: , AuthorizationFailed
[oer-s115] Pass 1: groups | oer-s115-cnt | Unchanged | group properties match
[oer-s115] Pass 1: groups | oer-s115-cnt | Unchanged | member '00000000-0000-0000-0000-000000000001' already present
[oer-s115] Pass 1: groups | oer-s115-req | Unchanged | group properties match
[oer-s115] Pass 1: catalogs | oer-s115-cat2 | Unchanged | catalog properties match
[oer-s115] Pass 1: catalogs | oer-s115-catu | Unchanged | catalog properties match
[oer-s115] Pass 1: catalogs | oer-s115-cat | Unchanged | catalog properties match
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Unchanged | access package properties match
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 1: accessPackages | oer-s115-ap-a | Unchanged | access package properties match
[oer-s115] Pass 1: roleAssignments | Reader -> 00000000-0000-0000-0000-000000000002 @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg'
[oer-s115] Pass 1 FAILED: roleAssignments | Owner -> principal-1 @ /providers/Microsoft.Management/managementGroups/MG-1 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 1 FAILED: roleAssignments | Owner -> principal-2 @ /providers/Microsoft.Management/managementGroups/MG-1 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 1 FAILED: roleAssignments | User Access Administrator -> principal-3 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 1 FAILED: roleAssignments | User Access Administrator -> principal-1 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 1 FAILED: roleAssignments | User Access Administrator -> principal-4 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 1 FAILED: roleAssignments | Log Analytics Contributor -> principal-5 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2: token requests: 0; Microsoft Graph requests: 1044, writes: 0; Azure Resource Manager requests: 42, writes: 0
[oer-s115] Pass 2: rows 466; by action: Extra 2, Failed 6, Skipped 67, Unchanged 391
[oer-s115] Pass 2: AmbiguousName records: 0; error ids: , AuthorizationFailed
[oer-s115] Pass 2: groups | oer-s115-cnt | Unchanged | group properties match
[oer-s115] Pass 2: groups | oer-s115-cnt | Unchanged | member '00000000-0000-0000-0000-000000000001' already present
[oer-s115] Pass 2: groups | oer-s115-req | Unchanged | group properties match
[oer-s115] Pass 2: catalogs | oer-s115-cat2 | Unchanged | catalog properties match
[oer-s115] Pass 2: catalogs | oer-s115-catu | Unchanged | catalog properties match
[oer-s115] Pass 2: catalogs | oer-s115-cat | Unchanged | catalog properties match
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Unchanged | access package properties match
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 2: accessPackages | oer-s115-ap-a | Unchanged | access package properties match
[oer-s115] Pass 2: roleAssignments | Reader -> 00000000-0000-0000-0000-000000000002 @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg'
[oer-s115] Pass 2 FAILED: roleAssignments | Owner -> principal-1 @ /providers/Microsoft.Management/managementGroups/MG-1 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2 FAILED: roleAssignments | Owner -> principal-2 @ /providers/Microsoft.Management/managementGroups/MG-1 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2 FAILED: roleAssignments | User Access Administrator -> principal-3 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2 FAILED: roleAssignments | User Access Administrator -> principal-1 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2 FAILED: roleAssignments | User Access Administrator -> principal-4 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
[oer-s115] Pass 2 FAILED: roleAssignments | Log Analytics Contributor -> principal-5 @ /providers/Microsoft.Management/managementGroups/MG-2 | could not read role assignments at that scope: AuthorizationFailed (the identity holds no read at that management group; names masked by the controller)
RUNNER: check-3.2 exit code 0; started 2026-10-14T22:10:38Z; took 344 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.3. The step's entries applied for real, twice: only Unchanged (G8)

- [x] **3.3** A document holding only the step's entries from the export -- the catalogs `oer-s115-cat` and `oer-s115-catu`, the packages `oer-s115-ap-a` and `oer-s115-ap-b`, and the role assignment by the group's id -- is applied for real twice; every row is Unchanged and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Bundle = (Get-S115Bundle).FullName
$Doc = Get-Content -LiteralPath (Join-Path $Bundle 'inventory.json') -Raw | ConvertFrom-Json -DateKind String
$Part = [ordered]@{ version = $Doc.version }
if ($Doc.PSObject.Properties.Name -contains 'tenantId') { $Part.tenantId = $Doc.tenantId }
$Part.catalogs = @($Doc.catalogs | Where-Object { $_.displayName -in 'oer-s115-cat', 'oer-s115-catu' })
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
    foreach ($Row in $Rows) { Write-OerLiveStep "Pass $($Pass): $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
    Write-OerLiveStep "Pass $($Pass): error ids: $(@($E | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** both passes the same and `writes: 0` for Microsoft Graph and Azure Resource Manager; every row
Unchanged (the catalog, both packages, the role assignment), apart from the two Extra rows on
`oer-s115-ap-b` that report the left-out `oer-s115-pol` policies as still in force; no error.
**Failure looks like:** a write, a Created or Updated row, an AmbiguousName or a Failed row.

Result: 2026-10-14 22:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). The step's entries from the export -- the catalogs oer-s115-cat and oer-s115-catu, the packages oer-s115-ap-a and oer-s115-ap-b, and the Reader role assignment at oer-s115-rg naming the group by its id with principalType Group -- applied for real twice: both passes identical, every row Unchanged apart from the two Extra rows on oer-s115-ap-b reporting the left-out oer-s115-pol policies as still in force; writes 0 (Microsoft Graph 18 requests, Azure Resource Manager 3); no error; no token request.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] Entries: catalogs 2, access packages 2, role assignments 1; every role assignment scope is the step's resource group: True
[oer-s115] Pass 1: token requests: 0; Microsoft Graph requests: 18, writes: 0; Azure Resource Manager requests: 3, writes: 0
[oer-s115] Pass 1: catalogs | oer-s115-catu | Unchanged | catalog properties match
[oer-s115] Pass 1: catalogs | oer-s115-cat | Unchanged | catalog properties match
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Unchanged | access package properties match
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 1: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 1: accessPackages | oer-s115-ap-a | Unchanged | access package properties match
[oer-s115] Pass 1: roleAssignments | Reader -> 00000000-0000-0000-0000-000000000002 @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg'
[oer-s115] Pass 1: error ids: 
[oer-s115] Pass 2: token requests: 0; Microsoft Graph requests: 18, writes: 0; Azure Resource Manager requests: 3, writes: 0
[oer-s115] Pass 2: catalogs | oer-s115-catu | Unchanged | catalog properties match
[oer-s115] Pass 2: catalogs | oer-s115-cat | Unchanged | catalog properties match
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Unchanged | access package properties match
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 2: accessPackages | oer-s115-ap-b | Extra | undeclared assignmentPolicy 'oer-s115-pol' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
[oer-s115] Pass 2: accessPackages | oer-s115-ap-a | Unchanged | access package properties match
[oer-s115] Pass 2: roleAssignments | Reader -> 00000000-0000-0000-0000-000000000002 @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s115-rg'
[oer-s115] Pass 2: error ids:
RUNNER: check-3.3 exit code 0; started 2026-10-14T22:17:05Z; took 11 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.4. The validator refuses two policies of one name in a package

- [x] **3.4** A document whose `oer-s115-ap-b` declares both `oer-s115-pol` policies is refused offline with an Error.

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
Write-OerLiveStep "Valid: $($V.Valid); findings: $(@($V.Errors).Count) (Error $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count))"
foreach ($F in @($V.Errors | Where-Object { $_.Severity -eq 'Error' })) { Write-OerLiveStep "Error at $($F.Path): $($F.Message)" }
```

**Expect:** `Valid: False`, one Error at `accessPackages[0].assignmentPolicies[1]` naming
`accessPackages[0].assignmentPolicies[0]` (the names differ only in letter case). Offline: no sign-in.
**Failure looks like:** `Valid: True`.

Result: 2026-10-14 22:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Offline, no sign-in: Valid False with exactly one Error, at accessPackages[0].assignmentPolicies[1], naming accessPackages[0].assignmentPolicies[0] (the names differ only in letter case). The two other findings are Warnings unrelated to the rule (the catalog is not declared in this small document, and resourceRoles is omitted). (A first run listed all three under 'Error'; fixed in the block -- it now lists the Errors by Severity -- and run again.)

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.4 ===
[oer-s115] Valid: False; findings: 3 (Error 1)
[oer-s115] Error at accessPackages[0].assignmentPolicies[1]: accessPackages[0].assignmentPolicies[1] declares the same display name 'OER-S115-POL' as accessPackages[0].assignmentPolicies[0] (compared without regard to letter case). Both entries reconcile one assignment policy of the access package, so each would undo the other's settings. Keep one entry.
RUNNER: check-3.4 exit code 0; started 2026-10-14T22:18:10Z; took 2 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.5. A package missing from its catalog is never written into another catalog's package

- [x] **3.5** A document declares `oer-s115-ap-a` in the empty catalog `oer-s115-cat2` (by id), where it does not exist, while `oer-s115-ap-a` exists in `oer-s115-cat`: the plan says it would create it, and the real run reports Failed and writes nothing.

```powershell
Connect-OerLive -Arm
Start-S115NoPrompt
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{ displayName = 'oer-s115-ap-a'; catalog = $Ids['cat-2']; resourceRoles = @(); assignmentPolicies = @() })
}
$Path = Join-Path $Raw 'twin-s115.json'
$Doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
Write-OerLiveStep "oer-s115-cat2 recorded: $([bool]$Ids['cat-2']); oer-s115-ap-a recorded in the first: $([bool]$Ids['ap-a'])"
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
    foreach ($Row in $Rows) { Write-OerLiveStep "$($Mode): $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
}
$Pol = Invoke-OerLiveGraph -All -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$($Ids['ap-a'])'"))
Assert-OerLiveOk -Response $Pol -Activity 'Reading the policies of oer-s115-ap-a' | Out-Null
Write-OerLiveStep "oer-s115-ap-a holds $(@(@($Pol.Body['value']) | Where-Object { $null -ne $_ }).Count) assignment policies after the run (it had none)"
$InCat2 = Invoke-OerLiveGraph -All -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("catalog/id eq '$($Ids['cat-2'])'"))
Assert-OerLiveOk -Response $InCat2 -Activity 'Listing the packages of oer-s115-cat2' | Out-Null
Write-OerLiveStep "Packages in oer-s115-cat2 after the run: $(@(@($InCat2.Body['value']) | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
```

**Expect:** the plan one row `would create access package` (the plan never calls the create, so it cannot
see the twin) and `writes: 0`; the real run ONE `Failed` row whose detail names a package of that name in
another catalog, and `writes: 0` for Microsoft Graph and Azure Resource Manager; `oer-s115-ap-a` still holds 0
policies, and `oer-s115-cat2` still holds 0 packages. (Two catalogs of one name cannot be made in this
tenant, 0.2, so this is the older case the guard also closes: a package declared in a uniquely named catalog
whose name a package in another catalog carries.)
**Failure looks like:** a `Created` row, a write, or a policy on `oer-s115-ap-a` -- the guard did not hold
(everything stays inside the prefix).

Result: 2026-10-14 22:18 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. A document declaring oer-s115-ap-a in the empty catalog oer-s115-cat2 (by id), while oer-s115-ap-a exists in oer-s115-cat: the plan gave one row 'would create access package' (Skipped) with 0 writes, since the plan never calls the create; the real run gave ONE Failed row -- not created in that catalog, a package of that name already exists in another catalog and New-OERAccessPackage returned it, nothing written to it -- with 0 writes (Microsoft Graph 3 requests); oer-s115-ap-a still holds 0 policies and oer-s115-cat2 0 packages. Without the guard this run would have reported Created and written to oer-s115-ap-a.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.5 ===
[oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] oer-s115-cat2 recorded: True; oer-s115-ap-a recorded in the first: True
What if: Performing the operation "Create access package" on target "oer-s115-ap-a".
[oer-s115] plan: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s115] plan: accessPackages | oer-s115-ap-a | Skipped | would create access package oer-s115-ap-a
[oer-s115] run: token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s115] run: accessPackages | oer-s115-ap-a | Failed | access package 'oer-s115-ap-a' was not created in catalog '00000000-0000-0000-0000-000000000004': a package of that name already exists in another catalog (00000000-0000-0000-0000-000000000005), and New-OERAccessPackage returned it (00000000-0000-0000-0000-000000000006); nothing was written to it
[oer-s115] oer-s115-ap-a holds 0 assignment policies after the run (it had none)
[oer-s115] Packages in oer-s115-cat2 after the run: 0
RUNNER: check-3.5 exit code 0; started 2026-10-14T22:18:25Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## T. Teardown

### T.1. Remove every oer-s115- object

- [x] **T.1** The prerequisite script's teardown removes the role assignment, the resource group, the Microsoft 365 group and every other prefixed object, and the sweep finds none.

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

Result: 2026-10-14 22:20 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The -WhatIf teardown removed nothing; the real one removed the Reader role assignment and oer-s115-rg, the Microsoft 365 group (204 at the first attempt) and, through OerLive's fixed order, the PIM for Groups row that listed oer-live-cc-noperm's direct membership of oer-s115-cnt, the two policies, the two packages, the three catalogs and the other five groups (removed 14, residue 0), and purged the Microsoft 365 group from the deleted items (204). The last, printing sweep still listed three groups already deleted (204) -- a listing replica behind the deletes; the counts equal the baseline and T.2 reads nothing left. Exit code 0. (Before this run's setup, an earlier partial setup was torn down the same way: removed 8, residue 0, counts at the baseline.) The prerequisite script's mode line still says 'two catalogs oer-s115-cat'; the objects it made are the ones 0.2 lists.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s115] === Initialize-OerS115Prereq.ps1 -Teardown -WhatIf ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] What if: Performing the operation "Start the redacted transcript" on target "raw\s115\teardown-20261014-221845Z.log".
[oer-s115] [oer-s115] Mode: REMOVE. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] What if: Performing the operation "Remove the Reader role assignment (Azure Resource Manager DELETE roleAssignments)" on target "oer-s115-rg".
[oer-s115] What if: Performing the operation "Delete the resource group (Azure Resource Manager DELETE)" on target "oer-s115-rg".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups), retried while Graph refuses it" on target "oer-s115-mix (Microsoft 365)".
[oer-s115] [oer-s115] Teardown of 'oer-s115-': users 0, groups 6, access packages 2, catalogs 3; administrative units 0 and app registrations 0 are reported only.
[oer-s115] [oer-s115] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s115] [oer-s115] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s115] What if: Performing the operation "Remove (Graph beta schedule request, adminRemove)" on target "oer-s115-cnt: PIM for Groups member assignment of a principal".
[oer-s115] What if: Performing the operation "Remove (Graph beta schedule request, adminRemove)" on target "oer-s115-mix: PIM for Groups owner assignment of a principal".
[oer-s115] [oer-s115] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s115] What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s115-ap-b: assignment policy 'oer-s115-pol'".
[oer-s115] What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s115-ap-b: assignment policy 'oer-s115-pol'".
[oer-s115] What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s115-ap-b".
[oer-s115] What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s115-ap-a".
[oer-s115] What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s115-cat2".
[oer-s115] What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s115-catu".
[oer-s115] What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s115-cat".
[oer-s115] [oer-s115] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s115] [oer-s115] Teardown 5/6: the prefixed groups.
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-cnt".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-dup".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-dup".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-mix".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-mix".
[oer-s115] What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s115-req".
[oer-s115] [oer-s115] Teardown 6/6: the prefixed users.
[oer-s115] [oer-s115] Teardown of 'oer-s115-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s115] [oer-s115] WhatIf: nothing was created, removed or written.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
[oer-s115] === Initialize-OerS115Prereq.ps1 -Teardown -Unattended ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] [oer-s115] Transcript (redacted): raw\s115\teardown-20261014-221904Z.log; OerLive 1.0.3.
[oer-s115] [oer-s115] Mode: REMOVE. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] [oer-s115] Teardown A: removed the Reader role assignment at oer-s115-rg.
[oer-s115] [oer-s115] oer-s115-rg is gone: not yet (read 1, 0.2 s, likely replication delay) -- reading again in 2 s.
[oer-s115] [oer-s115] oer-s115-rg is gone: converged after 2 read(s), 2.6 s.
[oer-s115] [oer-s115] Teardown A: deleted oer-s115-rg.
[oer-s115] [oer-s115] Teardown B: DELETE the Microsoft 365 group oer-s115-mix: 204  after 1 attempt(s), 0.2 s.
[oer-s115] [oer-s115] the Microsoft 365 group oer-s115-mix is no longer listed: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s115] [oer-s115] the Microsoft 365 group oer-s115-mix is no longer listed: converged after 2 read(s), 2.2 s.
[oer-s115] [oer-s115] Teardown of 'oer-s115-': users 0, groups 6, access packages 2, catalogs 3; administrative units 0 and app registrations 0 are reported only.
[oer-s115] [oer-s115] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s115] [oer-s115] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s115] [oer-s115] Removed: oer-s115-cnt: PIM for Groups member assignment of a principal (201).
[oer-s115] [oer-s115] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s115] [oer-s115] Deleted: oer-s115-ap-b: assignment policy 'oer-s115-pol' (204).
[oer-s115] [oer-s115] Deleted: oer-s115-ap-b: assignment policy 'oer-s115-pol' (204).
[oer-s115] [oer-s115] Deleted: access package oer-s115-ap-b (204, 1 attempt(s)).
[oer-s115] [oer-s115] Deleted: access package oer-s115-ap-a (204, 1 attempt(s)).
[oer-s115] [oer-s115] Deleted: catalog oer-s115-cat2 (204, 1 attempt(s)).
[oer-s115] [oer-s115] Deleted: catalog oer-s115-catu (204, 1 attempt(s)).
[oer-s115] [oer-s115] Deleted: catalog oer-s115-cat (204, 1 attempt(s)).
[oer-s115] [oer-s115] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s115] [oer-s115] Teardown 5/6: the prefixed groups.
[oer-s115] [oer-s115] Deleted: group oer-s115-cnt (204).
[oer-s115] [oer-s115] Deleted: group oer-s115-dup (204).
[oer-s115] [oer-s115] Deleted: group oer-s115-dup (204).
[oer-s115] [oer-s115] Deleted: group oer-s115-mix (204).
[oer-s115] [oer-s115] Deleted: group oer-s115-mix (404).
[oer-s115] [oer-s115] Deleted: group oer-s115-req (204).
[oer-s115] [oer-s115] Teardown 6/6: the prefixed users.
[oer-s115] [oer-s115] Teardown of 'oer-s115-': removed 14, residue 0, unreadable 0.
[oer-s115] [oer-s115] Teardown D: purge of the Microsoft 365 group: 204  after 1 attempt(s).
[oer-s115] [oer-s115] no 'oer-s115-' object is listed: not yet (read 1, 0.4 s, likely replication delay) -- reading again in 2 s.
[oer-s115] [oer-s115] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s115-' is left.
[oer-s115] [oer-s115] no 'oer-s115-' object is listed: converged after 2 read(s), 2.7 s.
[oer-s115] [oer-s115] Sweep: group 'oer-s115-cnt' (00000000-0000-0000-0000-000000000007) carries the prefix.
[oer-s115] [oer-s115] Sweep: group 'oer-s115-mix' (00000000-0000-0000-0000-000000000008) carries the prefix.
[oer-s115] [oer-s115] Sweep: group 'oer-s115-req' (00000000-0000-0000-0000-000000000009) carries the prefix.
[oer-s115] [oer-s115] Resource group oer-s115-rg exists after the teardown: False
[oer-s115] [oer-s115] Counts: groups now 97, at the baseline 97; equal: True
[oer-s115] [oer-s115] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s115] [oer-s115] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s115] [oer-s115] Removed the recorded ids.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
RUNNER: check-T.1 exit code 0; started 2026-10-14T22:18:43Z; took 55 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read back

- [x] **T.2** A read-only pass finds no prefixed object, no resource group and no residue row of this step.

```powershell
& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS115Prereq.ps1') -ReadBack *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `prefixed objects left: 0`; `resource group oer-s115-rg exists: False`; counts equal to the
baseline; 0 residue rows with this step's prefix.
**Failure looks like:** anything left.

Result: 2026-10-14 22:20 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Read-only: no prefixed object left (0, 0 unread collections), oer-s115-rg does not exist, the counts equal the baseline (groups 97, catalogs 5, access packages 6), and raw\residue.json holds 5 rows, none with this step's prefix (they are older rows of other prefixes).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[oer-s115] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s115] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s115] [oer-s115] Transcript (redacted): raw\s115\readback-20261014-221952Z.log; OerLive 1.0.3.
[oer-s115] [oer-s115] Mode: READ BACK. Prefix 'oer-s115-'. Objects (fixed): two security groups oer-s115-dup; a security group and a Microsoft 365 group oer-s115-mix; oer-s115-cnt (member: oer-live-cc-noperm); oer-s115-req (no member); two catalogs oer-s115-cat, the first holding oer-s115-ap-a; oer-s115-catu holding oer-s115-ap-b with two policies oer-s115-pol; oer-s115-rg (tagged) with Reader for the first oer-s115-dup group. OerLive 1.0.3.
[oer-s115] [oer-s115] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg5\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s115] [oer-s115] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s115] [oer-s115] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s115] [oer-s115] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s115-' is left.
[oer-s115] [oer-s115] Read-back: resource group oer-s115-rg exists: False
[oer-s115] [oer-s115] Counts: groups now 97, at the baseline 97; equal: True
[oer-s115] [oer-s115] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s115] [oer-s115] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s115] [oer-s115] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s115] [oer-s115] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s115] [oer-s115] Read-back: residue row: PIM for Groups eligibility 'opim-s2-grp: PIM for Groups member eligibility of a principal' (prefix opim-s2-), first refused 2026-10-10T23:39:01Z, attempts 1: 400 BadRequest {"error":{"code":"Request_BadRequest","message":"The source resource object or one of the objects being referenced do not exist.","innerError":{"date":"2026-10-10T23:39:01","request-id":"00000000-0000-0000-0000-000000000010","client-request-id":"00000000-0000-0000-0000-000000000011"}}}
[oer-s115] [oer-s115] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-10T23:39:02Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s115] [oer-s115] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-11T14:55:13Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s115] [oer-s115] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 5, of them with this step's prefix: 0.
[oer-s115] [oer-s115] Done.
[oer-s115] exit code: 0
RUNNER: check-T.2 exit code 0; started 2026-10-14T22:19:50Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

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
  `Invoke-OERStructure.Tests.ps1`; 3.5 runs the by-id case live, with a uniquely named catalog.
- **B.8 A package in a catalog whose name another catalog carries is written with the catalog's id, and
  applies (BL-39).** Microsoft Graph refuses to create or rename a catalog to a name another catalog carries,
  letter case aside (0.2: 400 `DuplicateCatalog`, 409 `DuplicateKey`), so the pair cannot be made in the test
  tenant. `Get-OERInventory.Tests.ps1` (the BL-39 tests) and `Invoke-OERStructure.Tests.ps1`, Describe
  "Invoke-OERStructure applies what an export writes by id: a package's catalog and a review's access package
  and assignment policy (BL-39, BL-142)".
- **B.7 The texts.** `tests/QA/docsync.tests.ps1` and `about.tests.ps1` (README and the about topic agree and
  name every cmdlet), `dochygiene.tests.ps1` (no tenant value, no tag-like bracket), `module.tests.ps1` (help,
  the changelog and its budget).
