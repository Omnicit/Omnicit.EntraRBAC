# Live verification checklist -- Get-OERManagementGroup shows the parent of every listed group (fix/list-management-group-parents)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.**
A box with no result line filled in is not a passed check -- it is an unrun one. If a check turns
out to be impossible to run, write "cannot be verified, and therefore we do not know" on its result
line and say why; do not leave it blank and do not tick it. A check that could not run for a stated
reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B)**, and
**section C is Philip's, in an environment of his own, after the merge**: this run never executes it.

**What this file writes to the tenant: nothing.** No object is created, changed or removed, so there
is no prerequisite script and no baseline. Every request is a token request or a read. The only
files written are the two inventory bundles of section 3 and the kept build of `3f19ce4`, all under
`raw\s107\`, which the teardown deletes.

**Who runs it.** Sections S, 0, 1, 2, 3 and T: the dedicated certificate identity `oer-live-cc`
(1.3 also `oer-live-cc-noperm`), through the OerLive library, which lives beside the operator's copy
of this file outside the repository ([README.md](README.md), first paragraph). Every sign-in is
app-only, with the certificate; nothing here signs in as a person.

**What the identity can see.** Measured before the code (part 1 of the step): `oer-live-cc` holds
Owner on one subscription and no role on any management group, so the management group LIST answers
it `403 AuthorizationFailed`, and a read of the root group, with or without
`$expand=children&$recurse=true`, and of `/descendants` answers `403` too. Entities - List
(`getEntities`) answers `200` with its subscription and the two management groups above it (the root
and one more), both `noaccess`. **So the identity lists no management group, and the parent of a
LISTED group cannot be shown live here: that check is class B (section B) and class C (section C),
as decision A10 foresees.** A 403 below is therefore an expected, measured answer, never a missing
permission a check needs; this file adds no permission to either identity.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s107/`,
which is git-ignored. Every block prints through the library's redactor, and the helpers print
counts and True/False only -- never a management group's name, display name or id, which are object
names the redactor does not know. Each block is run in its own process whose whole output (standard
output and standard error) is written to a file under `raw\s107\`, redacted with OerLive's redactor
and a mask for any `managementGroups/` path segment that is not a placeholder, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The list carries each group's parent** ("fix: show the parent of every listed management
  group"). The management group list carries no parent (Learn, and the measurement). The list now
  reads every group's parent with ONE Entities - List call per list
  (`POST /providers/Microsoft.Management/getEntities?api-version=2020-05-01&$view=GroupsOnly`, paged),
  through the new private `Get-OERManagementGroupParent`, and passes it to
  `ConvertTo-OERManagementGroup`, which stays the single owner of the shape. The tenant root group
  (its name is the tenant id) has no parent and stays empty. A parent that could not be read leaves
  the three properties empty and is reported, after the groups, as one non-terminating
  `ManagementGroupParentReadFailed` that names the groups. An Entities - List entry is used only when
  it is complete and its name chain ends in the segment of its `parent.id`, so an answer that
  disagrees with itself is reported as unread, never shown.
- **B. The export gains no failure mode.** The inventory walk (`Resolve-OERInventoryScopeTree`) lists
  through the new private `Get-OERManagementGroupList` (the same list call) and never reads parents.
- **C. `-Expand` and `-Recurse` need `-Name`.** They belong to the `-Name` parameter set, so without
  `-Name` the call is refused at parameter binding instead of silently listing. `-Name` keeps its
  position (0) and `-TenantId` its position (1).

What a live tenant adds: the parent read parses the REAL Entities - List answer (1.2), it needs no
role of its own (1.3), the list's refusal and the `-Name` path behave as before (1.1, 1.4), the
binding refusal in the built module (2.1), and the export walking the same scopes before and after
(3.1, 3.2).

## What this file does not check, and why

- **The parent of every listed group, on several levels, compared with a read per group with `-Name`
  (class B, then class C).** The identity lists no management group (above). Proved offline in
  `tests/Unit/Public/Get-OERManagementGroup.Tests.ps1`, Context `the parent of every listed group
  (A10)`; section C is the run in an environment where groups can be read.
- **A parent that cannot be read (class B).** Nothing here makes Entities - List fail or leave out a
  listed group on purpose; the same Context proves both reasons offline.
- **The export when the parent read fails (class B).** `tests/Unit/Private/Resolve-OERInventoryScopeTree.Tests.ps1`
  proves the export never sends the parent read; 3.1 and 3.2 show it walks the same scopes live.
- **G8 (convergence).** This branch changes no write path.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm` enabled for the run.
- The **built module of this branch** in the step's own worktree (`./build.ps1 -Tasks build`), and
  the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it.
- The **build of `origin/main` at `3f19ce4`** (the commit this branch starts from), copied to
  `raw\s107\before-3f19ce4\output\module\Omnicit.EntraRBAC\` before this branch's first build. Section
  3.1 loads it; it uses the worktree's `output\RequiredModules`.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences and the
readers. Nothing here signs in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s107-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s107'
$Before = Join-Path $Raw 'before-3f19ce4'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null

function Start-S107Fence {
    # Two global proxies, which the module calls unqualified. Get-AzToken forwards only a request that
    # carries the certificate, so nothing can prompt. Invoke-WebRequest (the ARM transport) records each
    # request's method and KIND of path -- the management group list, Entities - List, one group, or
    # other -- never the path or a value.
    $global:S107Token = [System.Collections.Generic.List[string]]::new()
    $global:S107Arm = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $global:S107Token.Add(((@($PSBoundParameters.Keys) | Sort-Object) -join '','')); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S107 fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
    $Meta2 = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Body2 = 'end { $U = [string]$PSBoundParameters[''Uri'']; $Kind = if ($U -match ''/getEntities\?'') { ''entities'' } elseif ($U -match ''/managementGroups\?'') { ''list'' } elseif ($U -match ''/managementGroups/[^/?]+\?'') { ''group'' } else { ''other'' }; $global:S107Arm.Add(([string]$PSBoundParameters[''Method''] + '' '' + $Kind)); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }'
    $Text2 = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta2))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta2)))`n$Body2"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text2))
    $Seen = & (Get-Module -Name Omnicit.EntraRBAC) { '{0},{1}' -f (Get-Command Get-AzToken).CommandType, (Get-Command Invoke-WebRequest).CommandType }
    Write-OerLiveStep "fences in place (the module resolves both names to the proxies): $($Seen -eq 'Function,Function')"
}

function Reset-S107Requests { $global:S107Token.Clear(); $global:S107Arm.Clear() }

function Write-S107Requests {
    # The counts since the last reset: token requests and ARM requests by kind.
    if ($null -eq $global:S107Arm) { Write-OerLiveStep 'requests: not fenced in this block'; return }
    $By = { param($K) @($global:S107Arm | Where-Object { $_ -like "* $K" }).Count }
    Write-OerLiveStep ("requests: token {0}; ARM {1} (list {2}; Entities - List {3}, all POST: {4}; one group {5}; other {6})" -f $global:S107Token.Count, $global:S107Arm.Count, (& $By 'list'), (& $By 'entities'), (@($global:S107Arm | Where-Object { $_ -like '* entities' } | Where-Object { $_ -notlike 'POST *' }).Count -eq 0), (& $By 'group'), (& $By 'other'))
}

function Get-S107Entities {
    # The raw Entities - List answer (every entity type), read with the module's own transport. Kept in a
    # variable and never printed: it holds names and ids.
    $R = Invoke-OerLiveArm -Method POST -Path '/providers/Microsoft.Management/getEntities?api-version=2020-05-01' -All
    if (-not $R.Ok) { throw "Entities - List failed: $($R.Status) $($R.Code)" }
    @($R.Body.value | Where-Object { $null -ne $_ })
}

function Write-S107Own {
    # A command's OWN records in an -ErrorVariable (the id ends in a comma and the command's name), as ids only.
    param([object[]]$Records, [string]$Command)
    $Own = @($Records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    Write-OerLiveStep ("{0} own errors: {1}{2}" -f $Command, $Own.Count, $(if ($Own.Count) { ' -- ' + (($Own | ForEach-Object { $_.FullyQualifiedErrorId }) -join '; ') } else { '' }))
}

function Get-S107ExportSummary {
    # What an Export-OERInventory -Include RoleAssignments run walked: counts, the skipped levels and the
    # scope list (sorted; ids are redacted when printed).
    param([Parameter(Mandatory)][object]$Out)
    $Hier = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'scopeHierarchy.json') -Raw | ConvertFrom-Json
    [PSCustomObject]@{
        ScopesEnumerated = [int]$Out.ScopesEnumerated
        ScopeCount       = [int]$Out.ScopeCount
        SkippedScopes    = @(@($Out.SkippedScopes) | Sort-Object)
        HierarchyGroups  = @($Hier.managementGroups).Count
        HierarchySubs    = @($Hier.subscriptions).Count
        Scopes           = @(@($Hier.managementGroups | ForEach-Object { [string]$_.id }) + @($Hier.subscriptions | ForEach-Object { [string]$_.id }) | Sort-Object)
        RoleAssignments  = [int]$Out.RoleAssignments
    }
}
```

### S.1. The module loads from this branch's build, and the 3f19ce4 build is kept

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched; the kept `3f19ce4` build carries none of this branch's changes.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Marks = @('function Get-OERManagementGroupList', 'getEntities?api-version=2020-05-01&$view=GroupsOnly', "'ManagementGroupParentReadFailed'", "[Parameter(ParameterSetName = 'ByName', Mandatory, Position = 0, ValueFromPipelineByPropertyName)]")
foreach ($Side in @(@('this branch', (Join-Path $Cfg.Repo 'output\module')), @('3f19ce4', (Join-Path $Before 'output\module')))) {
    $Psm1 = Get-ChildItem -Path (Join-Path $Side[1] 'Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Psm1) { Write-OerLiveStep "$($Side[0]) build: not found"; continue }
    $Hits = @($Marks | Where-Object { Select-String -LiteralPath $Psm1.FullName -SimpleMatch $_ -Quiet }).Count
    $Ver = (Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1'))
    Write-OerLiveStep "$($Side[0]) build: version $($Ver.ModuleVersion) $($Ver.PrivateData.PSData.Prerelease); marks of this branch: $Hits of $($Marks.Count)"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `this branch build: ... marks of
this branch: 4 of 4`; `3f19ce4 build: ... marks of this branch: 0 of 4`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), fewer than 4 marks in this
branch's build (build it first, never while the gate runs), or any mark in the `3f19ce4` build.

Result: 2026-10-09 18:28 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree on this branch at 5a71de6 with 0 tracked changes (the build is of a0bf5e3's source; the commits after it change only this checklist); this branch's build carries all 4 marks of the change, the kept build carries none of them. Both builds show the prerelease label fix0001: the kept one was built on this branch before its first commit, from 3f19ce4's source.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s107] The module loads from a worktree that is not the main clone: True
[oer-s107] Main clone: branch main
[oer-s107] Worktree: branch fix/list-management-group-parents; HEAD 5a71de6 docs: keep angle brackets out of the live checklist's code; tracked changes: 0
[oer-s107] this branch build: version 1.1.4 fix0001; marks of this branch: 4 of 4
[oer-s107] 3f19ce4 build: version 1.1.4 fix0001; marks of this branch: 0 of 4
RUNNER: check S.1 exit code 0; started 2026-10-09T18:28:34Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result: 2026-10-09 18:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc; identity check passed; the module is the worktree's build (1.1.4).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] The module is the worktree's build: True
RUNNER: check 0.1 exit code 0; started 2026-10-09T18:28:57Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The list and its parents (A)

### 1.1. The list as oer-live-cc: refused as before, and no parent read follows

- [x] **1.1** `Get-OERManagementGroup` (no parameters) returns no group and writes the list's own `AuthorizationFailed`, exactly as before; it sends the list request once and never the Entities - List call, and writes no `ManagementGroupParentReadFailed`.

```powershell
Connect-OerLive -Arm
Start-S107Fence
Reset-S107Requests
$Groups = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "groups returned: $($Groups.Count)"
Write-S107Own -Records $E -Command 'Get-OERManagementGroup'
Write-OerLiveStep "ManagementGroupParentReadFailed written: $([bool](@($E | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ManagementGroupParentReadFailed*' }).Count))"
Write-S107Requests
Disconnect-OerLive
```

**Expect:** `groups returned: 0`; `Get-OERManagementGroup own errors: 1 --
AuthorizationFailed,Get-OERManagementGroup`; `ManagementGroupParentReadFailed written: False`;
`requests: token 0; ARM 1 (list 1; Entities - List 0, ...; one group 0; other 0)`.
**Failure looks like:** an Entities - List request after a failed list, a
`ManagementGroupParentReadFailed`, or a different error id.

Result: 2026-10-09 18:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Get-OERManagementGroup returned no group and wrote exactly its own AuthorizationFailed, as before; one ARM request (the list), no Entities - List request, no ManagementGroupParentReadFailed, no token request.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
[oer-s107] groups returned: 0
[oer-s107] Get-OERManagementGroup own errors: 1 -- AuthorizationFailed,Get-OERManagementGroup
[oer-s107] ManagementGroupParentReadFailed written: False
[oer-s107] requests: token 0; ARM 1 (list 1; Entities - List 0, all POST: True; one group 0; other 0)
RUNNER: check 1.1 exit code 0; started 2026-10-09T18:29:11Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. The parent read on the real Entities - List answer

- [x] **1.2** `Get-OERManagementGroupParent`, in the module's scope, reads the real answer with one `POST` and maps every non-root group it returns to exactly the parent the raw answer names (id, the id's last segment, the last display name of the chain); the root and the subscription are not in the map.

```powershell
Connect-OerLive -Arm
$Entities = Get-S107Entities
$Groups = @($Entities | Where-Object { [string]$_.type -eq 'Microsoft.Management/managementGroups' })
$Root = @($Groups | Where-Object { [string]$_.name -eq $Cfg.TenantId })
$NonRoot = @($Groups | Where-Object { [string]$_.name -ne $Cfg.TenantId })
$Subs = @($Entities | Where-Object { [string]$_.type -ne 'Microsoft.Management/managementGroups' })
Start-S107Fence
Reset-S107Requests
$Map = & (Get-Module -Name Omnicit.EntraRBAC) { Get-OERManagementGroupParent }
Write-S107Requests
Write-OerLiveStep "raw answer: entities $($Entities.Count); groups $($Groups.Count) (root $($Root.Count), other $($NonRoot.Count)); subscriptions $($Subs.Count)"
Write-OerLiveStep "the map is a hashtable: $($Map -is [hashtable]); entries: $($Map.Count)"
$Same = @($NonRoot | Where-Object {
        $E1 = $Map[[string]$_.name]
        $Id = [string]$_.properties.parent.id
        $E1 -and ([string]$E1.id -eq $Id) -and ([string]$E1.name -eq $Id.Split('/')[-1]) -and ([string]$E1.displayName -eq [string]@($_.properties.parentDisplayNameChain)[-1])
    }).Count
Write-OerLiveStep "non-root groups whose map entry equals the raw parent (id, name, display name): $Same of $($NonRoot.Count)"
$Chain = @($NonRoot | Where-Object { $Id = [string]$_.properties.parent.id; @($_.properties.parentNameChain).Count -gt 0 -and ([string]@($_.properties.parentNameChain)[-1] -eq $Id.Split('/')[-1]) }).Count
Write-OerLiveStep "non-root groups whose parentNameChain ends in the parent.id segment (the raw answer): $Chain of $($NonRoot.Count); map entries with a non-empty id, name and display name: $(@($Map.Values | Where-Object { $_.id -and $_.name -and $_.displayName }).Count)"
Write-OerLiveStep "the root is not in the map: $(-not @($Root | Where-Object { $Map.ContainsKey([string]$_.name) }).Count); no subscription is in the map: $(-not @($Subs | Where-Object { $Map.ContainsKey([string]$_.name) }).Count)"
Disconnect-OerLive
```

**Expect:** `requests: token 0; ARM 1 (list 0; Entities - List 1, all POST: True; one group 0; other
0)`; `raw answer: entities 3; groups 2 (root 1, other 1); subscriptions 1` (the measurement);
`the map is a hashtable: True; entries: 1`; `1 of 1` twice and `map entries with a non-empty id, name and display name: 1` -- the map is built from the `GroupsOnly` answer the module sends, so an entry proves that answer carries both chains; both `True`.
**Failure looks like:** a `False`, fewer matching entries than non-root groups, or the root or a
subscription in the map.

Result: 2026-10-09 18:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Get-OERManagementGroupParent sent one POST (Entities - List, GroupsOnly) and returned a hashtable with 1 entry: the one non-root group, whose entry equals the raw answer's parent (id, the id's last segment, the last display name of the chain); its parentNameChain ends in the parent.id segment, so the GroupsOnly answer the module requests carries both chains (R17, R21); the root and the subscription are not in the map. Raw answer as measured in part 1: 3 entities, 2 groups (root 1, other 1), 1 subscription.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
[oer-s107] requests: token 0; ARM 1 (list 0; Entities - List 1, all POST: True; one group 0; other 0)
[oer-s107] raw answer: entities 3; groups 2 (root 1, other 1); subscriptions 1
[oer-s107] the map is a hashtable: True; entries: 1
[oer-s107] non-root groups whose map entry equals the raw parent (id, name, display name): 1 of 1
[oer-s107] non-root groups whose parentNameChain ends in the parent.id segment (the raw answer): 1 of 1; map entries with a non-empty id, name and display name: 1
[oer-s107] the root is not in the map: True; no subscription is in the map: True
RUNNER: check 1.2 exit code 0; started 2026-10-09T18:29:23Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. The parent read needs no role of its own (oer-live-cc-noperm)

- [x] **1.3** As `oer-live-cc-noperm`, which holds no Azure role at all, `Get-OERManagementGroupParent` answers with an empty map and no error, and `Get-OERManagementGroup` is refused by the list exactly as in 1.1.

```powershell
Connect-OerLive -Arm -NoPerm
Start-S107Fence
Reset-S107Requests
$Failed = $false
try { $Map = & (Get-Module -Name Omnicit.EntraRBAC) { Get-OERManagementGroupParent } } catch { $Failed = $true }
Write-OerLiveStep "the parent read failed: $Failed; entries: $(if ($Map -is [hashtable]) { $Map.Count } else { 'no map' })"
$Groups = @(Get-OERManagementGroup -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "groups returned: $($Groups.Count)"
Write-S107Own -Records $E -Command 'Get-OERManagementGroup'
Write-S107Requests
Disconnect-OerLive
```

**Expect:** `the parent read failed: False; entries: 0`; `groups returned: 0`;
`Get-OERManagementGroup own errors: 1 -- AuthorizationFailed,Get-OERManagementGroup`;
`requests: token 0; ARM 2 (list 1; Entities - List 1, all POST: True; one group 0; other 0)`.
**Failure looks like:** the parent read refused (it would need a role after all), or an Entities -
List request from `Get-OERManagementGroup` after its list was refused.

Result: 2026-10-09 18:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. As oer-live-cc-noperm (no Azure role), Get-OERManagementGroupParent did not fail and returned 0 entries; Get-OERManagementGroup returned no group with exactly its own AuthorizationFailed; requests: the helper's one Entities - List POST and the cmdlet's one list request, no Entities - List request after the refused list.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
[oer-s107] the parent read failed: False; entries: 0
[oer-s107] groups returned: 0
[oer-s107] Get-OERManagementGroup own errors: 1 -- AuthorizationFailed,Get-OERManagementGroup
[oer-s107] requests: token 0; ARM 2 (list 1; Entities - List 1, all POST: True; one group 0; other 0)
RUNNER: check 1.3 exit code 0; started 2026-10-09T18:29:38Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.4. A read with -Name: positional, piped, and with -Recurse, as before

- [x] **1.4** A group the identity cannot read (the non-root group of the Entities - List answer) is read by `-Name` given by position, and by a piped object carrying `ManagementGroupName` with `-Recurse`: each answers `ManagementGroupNotFound` as before, each sends one group read, and neither sends the Entities - List call.

```powershell
Connect-OerLive -Arm
$Name = [string](@(Get-S107Entities | Where-Object { [string]$_.type -eq 'Microsoft.Management/managementGroups' -and [string]$_.name -ne $Cfg.TenantId }) | Select-Object -First 1).name
Write-OerLiveStep "a non-root group name was found in the answer: $([bool]$Name)"
Start-S107Fence
Reset-S107Requests
$A = @(Get-OERManagementGroup $Name -ErrorAction SilentlyContinue -ErrorVariable E1)
$B = @([PSCustomObject]@{ ManagementGroupName = $Name } | Get-OERManagementGroup -Recurse -ErrorAction SilentlyContinue -ErrorVariable E2)
Write-OerLiveStep "objects: positional $($A.Count); piped $($B.Count)"
Write-S107Own -Records $E1 -Command 'Get-OERManagementGroup'
Write-S107Own -Records $E2 -Command 'Get-OERManagementGroup'
Write-S107Requests
Disconnect-OerLive
```

**Expect:** `a non-root group name was found in the answer: True`; `objects: positional 0; piped 0`;
twice `Get-OERManagementGroup own errors: 1 -- ManagementGroupNotFound,Get-OERManagementGroup`;
`requests: token 0; ARM 2 (list 0; Entities - List 0, ...; one group 2; other 0)`.
**Failure looks like:** a binding error (the positional or the pipeline binding broke), a list or
Entities - List request, or another error id.

Result: 2026-10-09 18:30 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The non-root group (noaccess for this identity), read by -Name given by position and by a piped object carrying ManagementGroupName with -Recurse, answered ManagementGroupNotFound each time, as before; both bound (no binding error); two group reads, no list and no Entities - List request.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] a non-root group name was found in the answer: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
[oer-s107] objects: positional 0; piped 0
[oer-s107] Get-OERManagementGroup own errors: 1 -- ManagementGroupNotFound,Get-OERManagementGroup
[oer-s107] Get-OERManagementGroup own errors: 1 -- ManagementGroupNotFound,Get-OERManagementGroup
[oer-s107] requests: token 0; ARM 2 (list 0; Entities - List 0, all POST: True; one group 2; other 0)
RUNNER: check 1.4 exit code 0; started 2026-10-09T18:29:50Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. -Expand and -Recurse need -Name (C)

### 2.1. The binding refusal in the built module

- [x] **2.1** In a runspace that cannot prompt and holds no session, this branch's built module refuses `-Recurse`, `-Expand`, `-Expand -Recurse` and `-TenantId ... -Recurse` without `-Name` at parameter binding, with `MissingMandatoryParameter`, and `-Name ''` with the empty-string refusal; nothing runs, so no token is requested.

```powershell
$M = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
$Calls = [ordered]@{
    '-Recurse'                 = 'Get-OERManagementGroup -Recurse'
    '-Expand'                  = 'Get-OERManagementGroup -Expand'
    '-Expand -Recurse'         = 'Get-OERManagementGroup -Expand -Recurse'
    '-TenantId (test) -Recurse' = "Get-OERManagementGroup -TenantId '$($Cfg.TenantId)' -Recurse"
    "-Name ''"                 = "Get-OERManagementGroup -Name ''"
}
foreach ($K in $Calls.Keys) {
    $Ps = [powershell]::Create()
    try {
        # A fence first: should a call ever bind, it reaches no token request and no prompt.
        $null = $Ps.AddScript("function global:Get-AzToken { throw 'S107 fence: token request' }; Import-Module '$($M.FullName)' -Force -ErrorAction Stop; $($Calls[$K])")
        $Out = @($Ps.Invoke())
        $Ids = @($Ps.Streams.Error | ForEach-Object { $_.FullyQualifiedErrorId })
    } catch {
        $Inner = $PSItem.Exception.InnerException
        $Ids = @(if ($Inner -and $Inner.ErrorRecord) { $Inner.ErrorRecord.FullyQualifiedErrorId } else { $PSItem.Exception.GetType().Name })
        $Out = @()
    } finally { $Ps.Dispose() }
    Write-OerLiveStep ("{0}: objects {1}; errors {2} -- {3}; the fence was reached: {4}" -f $K, $Out.Count, $Ids.Count, ($Ids -join '; '), [bool](@($Ids | Where-Object { $_ -like '*fence*' }).Count))
}
# The same refusal as a script sees it: a child pwsh started with -NonInteractive, behind the same fence.
$Child = "`$ErrorView = 'NormalView'; function global:Get-AzToken { throw 'S107 fence: token request' }; Import-Module '$($M.FullName)' -Force -ErrorAction Stop; try { Get-OERManagementGroup -Recurse -ErrorAction Stop } catch { 'CHILD ERROR: ' + `$_.FullyQualifiedErrorId }"
$Lines = @(pwsh -NoProfile -NonInteractive -Command $Child 2>&1 | ForEach-Object { [string]$_ })
Write-OerLiveStep "pwsh -NonInteractive, -Recurse without -Name: $(@($Lines | Where-Object { $_ -like 'CHILD ERROR:*' }) -join ' | '); the fence was reached: $([bool](@($Lines | Where-Object { $_ -like '*S107 fence*' }).Count))"
```

**Expect:** for the four calls without `-Name`: `objects 0; errors 1 --
MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False`; for `-Name ''`:
`ParameterArgumentValidationErrorEmptyStringNotAllowed,Get-OERManagementGroup`, the fence not
reached; and `pwsh -NonInteractive, -Recurse without -Name: CHILD ERROR: MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False`.
**Failure looks like:** any other id, an object, or the fence reached (the call bound and began).

Result: 2026-10-09 18:30 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. In a runspace that cannot prompt, this branch's built module refused -Recurse, -Expand, -Expand -Recurse and -TenantId with -Recurse without -Name, each with exactly MissingMandatoryParameter, and -Name '' with ParameterArgumentValidationErrorEmptyStringNotAllowed; no object, and the token fence was never reached, so nothing began. A child pwsh started with -NonInteractive, as a script runs, got the same MissingMandatoryParameter for -Recurse without -Name.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s107] -Recurse: objects 0; errors 1 -- MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False
[oer-s107] -Expand: objects 0; errors 1 -- MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False
[oer-s107] -Expand -Recurse: objects 0; errors 1 -- MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False
[oer-s107] -TenantId (test) -Recurse: objects 0; errors 1 -- MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False
[oer-s107] -Name '': objects 0; errors 1 -- ParameterArgumentValidationErrorEmptyStringNotAllowed,Get-OERManagementGroup; the fence was reached: False
[oer-s107] pwsh -NonInteractive, -Recurse without -Name: CHILD ERROR: MissingMandatoryParameter,Get-OERManagementGroup; the fence was reached: False
RUNNER: check 2.1 exit code 0; started 2026-10-09T18:30:03Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. The export walks the same scopes before and after (B, G8)

### 3.1. Export with the 3f19ce4 build

- [x] **3.1** `Export-OERInventory -Include RoleAssignments`, run by the build of `3f19ce4`, writes its bundle under `raw\s107\` and its walk is recorded (counts, skipped levels, scopes) for 3.2.

```powershell
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
$Cfg.Repo = $Before
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "the module is the 3f19ce4 build: $($M.ModuleBase.StartsWith((Join-Path $Before 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); it has no Get-OERManagementGroupList: $(-not (& $M { Get-Command Get-OERManagementGroupList -ErrorAction SilentlyContinue }))"
Start-S107Fence
Reset-S107Requests
$Out = Export-OERInventory -Include RoleAssignments -OutputPath (Join-Path $Raw 'export-before') -ErrorAction SilentlyContinue -ErrorVariable E
$S = Get-S107ExportSummary -Out $Out
[System.IO.File]::WriteAllText((Join-Path $Raw 'export-before.json'), ($S | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "scopes enumerated $($S.ScopesEnumerated); read $($S.ScopeCount); skipped: $($S.SkippedScopes -join ' | '); hierarchy: groups $($S.HierarchyGroups), subscriptions $($S.HierarchySubs); role assignments $($S.RoleAssignments)"
Write-OerLiveStep "scopes: $($S.Scopes -join ' | ')"
Write-S107Own -Records $E -Command 'Export-OERInventory'
Write-S107Requests
Disconnect-OerLive
```

**Expect:** both module lines `True`; the walk as the measurement predicts: the management group
level skipped as `<management groups: the listing failed>`, the subscription walked; one
`InventoryPartial` (the export's own coverage signal for the skipped level); `Entities - List 0`.
**Failure looks like:** the module is not the `3f19ce4` build, or no bundle.

Result: 2026-10-09 18:30 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The 3f19ce4 build (no Get-OERManagementGroupList) exported RoleAssignments: 1 scope enumerated and read (the test subscription), the management group level skipped as the listing failed (with its warning), hierarchy 0 groups and 1 subscription, 14 role assignments, one InventoryPartial; one list request, no Entities - List request. Recorded for 3.2.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\docs\live-verification\raw\s107\before-3f19ce4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] the module is the 3f19ce4 build: True; it has no Get-OERManagementGroupList: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
WARNING: Could not list the management groups, so no management group is walked: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000002' does not have authorization to perform action 'Microsoft.Management/managementGroups/read' over scope '/providers/Microsoft.Management' or the scope is invalid. If access was recently granted, please refresh your credentials.
[oer-s107] scopes enumerated 1; read 1; skipped: <management groups: the listing failed>; hierarchy: groups 0, subscriptions 1; role assignments 14
[oer-s107] scopes: /subscriptions/00000000-0000-0000-0000-000000000003
[oer-s107] Export-OERInventory own errors: 1 -- InventoryPartial,Export-OERInventory
[oer-s107] requests: token 0; ARM 10 (list 1; Entities - List 0, all POST: True; one group 0; other 9)
RUNNER: check 3.1 exit code 0; started 2026-10-09T18:30:17Z; took 10 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. Export with this branch's build, compared with 3.1

- [x] **3.2** The same export, run by this branch's build, walks exactly the scopes 3.1 walked, skips exactly the same levels, and sends no Entities - List call.

```powershell
Connect-OerLive -Arm
Start-S107Fence
Reset-S107Requests
$Out = Export-OERInventory -Include RoleAssignments -OutputPath (Join-Path $Raw 'export-after') -ErrorAction SilentlyContinue -ErrorVariable E
$S = Get-S107ExportSummary -Out $Out
$P = Get-Content -LiteralPath (Join-Path $Raw 'export-before.json') -Raw | ConvertFrom-Json
Write-OerLiveStep "scopes enumerated $($S.ScopesEnumerated); read $($S.ScopeCount); skipped: $($S.SkippedScopes -join ' | '); hierarchy: groups $($S.HierarchyGroups), subscriptions $($S.HierarchySubs); role assignments $($S.RoleAssignments)"
Write-OerLiveStep "scopes: $($S.Scopes -join ' | ')"
Write-OerLiveStep ("same as 3.1 -- scopes: {0}; skipped levels: {1}; counts: {2}" -f (($S.Scopes -join '|') -eq (@($P.Scopes) -join '|')), (($S.SkippedScopes -join '|') -eq (@($P.SkippedScopes) -join '|')), (($S.ScopesEnumerated -eq $P.ScopesEnumerated) -and ($S.ScopeCount -eq $P.ScopeCount) -and ($S.HierarchyGroups -eq $P.HierarchyGroups) -and ($S.HierarchySubs -eq $P.HierarchySubs) -and ($S.RoleAssignments -eq $P.RoleAssignments)))
Write-S107Own -Records $E -Command 'Export-OERInventory'
Write-S107Requests
Disconnect-OerLive
```

**Expect:** the same walk as 3.1; `same as 3.1 -- scopes: True; skipped levels: True; counts: True`;
the same own errors as 3.1; `Entities - List 0`.
**Failure looks like:** any `False`, or an Entities - List request from the export.

Result: 2026-10-09 18:30 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. This branch's build exported exactly what 3.1 exported: the same scope list (1 subscription), the same skipped level (the management group listing failed), the same counts (1 enumerated, 1 read, hierarchy 0 groups and 1 subscription, 14 role assignments), the same one InventoryPartial; no Entities - List request. The export gains no failure mode and walks the same scopes before and after (G8).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] fences in place (the module resolves both names to the proxies): True
WARNING: Could not list the management groups, so no management group is walked: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000002' does not have authorization to perform action 'Microsoft.Management/managementGroups/read' over scope '/providers/Microsoft.Management' or the scope is invalid. If access was recently granted, please refresh your credentials.
[oer-s107] scopes enumerated 1; read 1; skipped: <management groups: the listing failed>; hierarchy: groups 0, subscriptions 1; role assignments 14
[oer-s107] scopes: /subscriptions/00000000-0000-0000-0000-000000000003
[oer-s107] same as 3.1 -- scopes: True; skipped levels: True; counts: True
[oer-s107] Export-OERInventory own errors: 1 -- InventoryPartial,Export-OERInventory
[oer-s107] requests: token 0; ARM 10 (list 1; Entities - List 0, all POST: True; one group 0; other 9)
RUNNER: check 3.2 exit code 0; started 2026-10-09T18:30:35Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## B. Proved offline (class B)

The identity lists no management group, so these are proved in the unit suite only:

- **Every listed group's parent, on three levels, and the root empty**:
  `tests/Unit/Public/Get-OERManagementGroup.Tests.ps1`, Context `the parent of every listed group
  (A10)`.
- **An unread parent is an error, never an empty parent**: the same Context -- the Entities - List
  call failing, and the answer leaving a listed group out.
- **The export gains no failure mode**: `tests/Unit/Private/Resolve-OERInventoryScopeTree.Tests.ps1`.
- **The binding refusal and the binding kept**: `tests/Unit/Public/Get-OERManagementGroup.Tests.ps1`,
  Context `parameter sets (A10)`; live in 2.1 and 1.4.

## C. For Philip, after the merge, in an environment of his own (class C; this run does not execute it)

Where management groups can be read on several levels. Install the preview that carries this
change, sign in your own way, and run the block; it prints counts and True/False only, so the result
can be reported without a name or an id.

### C.1. Every listed group's parent equals a read per group with -Name

- [ ] **C.1** Every listed group shows the parent a read per group with `-Name` shows; only the root group's parent is empty; no `ManagementGroupParentReadFailed`.

```powershell
$TenantId = Read-Host 'Tenant id or domain'
Connect-OER -TenantId $TenantId -IncludeARM
$List = @(Get-OERManagementGroup -ErrorAction Continue -ErrorVariable ListErr)
$Rows = foreach ($G in $List) {
    $One = Get-OERManagementGroup -Name $G.ManagementGroupName
    [PSCustomObject]@{
        Root = [string]$G.ManagementGroupName -eq [string]$G.TenantId
        HasParent = [bool]$G.ParentId
        SameAsName = ([string]$One.ParentId -eq [string]$G.ParentId) -and ([string]$One.ParentName -eq [string]$G.ParentName) -and ([string]$One.ParentDisplayName -eq [string]$G.ParentDisplayName)
    }
}
"groups listed: $($List.Count); parent equals the -Name read: $(@($Rows | Where-Object SameAsName).Count) of $($List.Count)"
"root groups: $(@($Rows | Where-Object Root).Count), with an empty parent: $(@($Rows | Where-Object { $_.Root -and -not $_.HasParent }).Count); other groups with a parent: $(@($Rows | Where-Object { -not $_.Root -and $_.HasParent }).Count) of $(@($Rows | Where-Object { -not $_.Root }).Count)"
"ManagementGroupParentReadFailed: $(@($ListErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ManagementGroupParentReadFailed*' }).Count)"
$List | Format-Table ManagementGroupName, DisplayName, ParentName, ParentDisplayName
```

**Expect:** `parent equals the -Name read: N of N`; the root group with an empty parent and every
other group with one; `ManagementGroupParentReadFailed: 0`; the table shows the hierarchy (do not
paste it into this file -- it holds names).
**Failure looks like:** a group whose parent differs from its `-Name` read, a non-root group with an
empty parent, or a `ManagementGroupParentReadFailed`.

Result: 2026-10-09 18:31 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: NOT RUN HERE (class C, for Philip after the merge; this run does not execute it).

Not run by this run (class C): the test identity lists no management group (the list answers 403 AuthorizationFailed), so a list with parents on several levels cannot be produced here, and the step creates no management group (ruling R7). Philip runs this block after the merge in an environment of his own where groups can be read on several levels, and reports the counts and True/False lines only.
```

## Teardown

### T.1. Nothing left: no session, nothing with the prefix, raw\s107 deleted

- [x] **T.1** No module session and no Graph SDK session remain, the sweep finds nothing with the prefix `oer-s107-` and no unread collection, and `raw\s107\` (the kept build and the two bundles) is deleted after the results are written.

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
$State = & (Get-Module -Name Omnicit.EntraRBAC) { $null -eq $script:_OERAuthState }
Write-OerLiveStep "module session cleared: $State; Graph SDK session left: $([bool](Get-MgContext))"
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s107 deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0 objects, 0 unread collections; `module session cleared: True; Graph SDK session left:
False`; `raw\s107 deleted: True`.
**Failure looks like:** an object or an unread collection (STOP: this run creates nothing), a session
left, or the folder still there.

Result: 2026-10-09 18:31 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The sweep found 0 objects with the prefix oer-s107- and 0 unread collections (this run created nothing); the module session is cleared and no Graph SDK session is left; raw\s107 (the kept 3f19ce4 build, the two bundles, export-before.json) is deleted. The runner captured this block outside raw\s107, since the block deletes that folder.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s107] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg7\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s107] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s107] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s107-' is left.
[oer-s107] objects with the prefix: 0; unread collections: 0
[oer-s107] module session cleared: True; Graph SDK session left: False
[oer-s107] raw\s107 deleted: True
RUNNER: check T.1 exit code 0; started 2026-10-09T18:31:29Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```
