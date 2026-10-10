# Live verification checklist -- the group export reads only the kept groups in full (feat/export-groups-in-large-tenants)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4 and T has a written result.**
A box with no result line filled in is not a passed check -- it is an unrun one. If a check turns
out to be impossible to run, write "cannot be verified, and therefore we do not know" on its result
line and say why; do not leave it blank and do not tick it. A check that could not run for a stated
reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).**
Nothing here is class C.

**What this file writes to the tenant.** Five objects, created by the prerequisite script
`Initialize-OerS108Prereq.ps1` (beside OerLive, outside the repository): the disabled user
`oer-s108-user`; the role-assignable group `oer-s108-ra` with the user as its member; the group
`oer-s108-elig` with the user as its owner and a time-bound (P30D) PIM-for-Groups member eligibility
of the user; the group `oer-s108-mod` with the user as its member and its member PIM policy changed
once (activation maximum PT4H); and the group `oer-s108-plain` with the user as its member and owner.
The eligibility and the policy change onboard their groups to PIM for Groups, which cannot be undone;
both groups are deleted at teardown. Section 4 applies an exported document to the three kept step
groups and must write nothing. The teardown (T.1) removes every prefixed object. The bundles, the
request logs and the kept build of `9761434` are written under `raw\s108\`, which the teardown
deletes.

**Who runs it.** Every section: the dedicated certificate identity `oer-live-cc`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only, with the certificate; nothing
here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s108/`,
which is git-ignored. Every block prints through the library's redactor, and the helpers print
counts and True/False only -- never a group's name other than the step's own prefixed ones, and never
an id. Each block is run in its own process whose whole output (standard output and standard error)
is written to a file under `raw\s108\`, redacted with OerLive's redactor and a mask for any GUID the
redactor did not number, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The export decides relevance first** ("feat: decide group relevance before reading groups in
  full when exporting"). Without `-AllGroupsDetailed`, `Export-OERInventory` lists the security
  groups, reads each group's PIM eligibility (one request) and, when it finds none and the group is
  neither role-assignable nor a synchronized group kept by `-IncludeSyncedGroups`, asks
  `Test-OERGroupPimInUse` (one more request). Only a group that may be kept is read in full (members,
  owners, PIM policies). A group whose relevance could not be read is read in full as before. The
  private `Get-OERInventoryGroup` holds the inventory's Groups section, shared with
  `Get-OERInventory`, whose output is unchanged; `Read-OERGroupCollection` reads one collection of a
  group without reading the group again.
- **B. The roster's member count** ("feat: write the roster count only for groups read in full").
  `groupsRoster.json` gives `memberCount` null for a group the export did not read in full.
- **C. `Export-OERInventory -GroupFilter`** ("feat: narrow the exported groups with -GroupFilter").
  The operator's OData filter is ANDed as `securityEnabled eq true and (<filter>)`, and the export
  keeps only groups the read shows security-enabled, so a filter that closes the parenthesis cannot
  widen `inventory.json`. The roster stays unfiltered.
- **D. Progress** ("feat: show progress while the export reads groups"). `Write-Progress` during the
  group read, completed in a `finally`.

What a live tenant adds: the real Graph answers behind the relevance decision, an export with the
`9761434` build and with this branch in the same tenant giving the same groups with the same content
and fewer requests for the groups not kept (1.1, 1.2), `-AllGroupsDetailed` reading as before (2.1,
2.2), the filter narrowing and an `or` filter not widening on the real endpoint (3.0 to 3.2), and the
exported document converging (4.1, G8).

## What this file does not check, and why

- **A tenant with about 3 100 groups.** The test tenant holds about a hundred. The request counts per
  group are measured here; the time saved in a large tenant is Philip's run after the merge (decision
  A13).
- **A synchronized group in the new selection.** The test tenant holds none (step 7b, measured). The
  selection of a synchronized security group under `-IncludeSyncedGroups` is class B (section B).
- **A relevance read that fails live.** `oer-live-cc` holds the PIM-for-Groups read scopes, so no
  eligibility or criterion read is refused here; the "read in full as before" path is class B.
- **Progress on the console.** `Write-Progress` is not captured by a redirected child process; it is
  class B.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run.
- The **built module of this branch** in the step's own worktree (`./build.ps1 -Tasks build`), and
  the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it.
- The **build of `origin/main` at `9761434`** (the commit this branch starts from), copied to
  `raw\s108\before-9761434\output\module\Omnicit.EntraRBAC\` before this branch's first build.
  Sections 1.1 and 2.1 load it; it uses the worktree's `output\RequiredModules`.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration (`oer-testmiljo.psd1` and
`oer-cc-identitet.psd1`), and defines the fences, the request log and the readers. Nothing here signs
in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s108-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s108'
$Before = Join-Path $Raw 'before-9761434'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$Kept = @('oer-s108-ra', 'oer-s108-elig', 'oer-s108-mod')
$NotKept = @('oer-s108-plain')
$StepGroups = @($Kept) + @($NotKept)

function Import-S108Before {
    # The kept 9761434 build, loaded before any sign-in so OerLive does not load this branch's build.
    $Mod = Get-ChildItem -Path (Join-Path $Before 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Select-Object -First 1
    $Req = Join-Path $Cfg.Repo 'output\RequiredModules'
    $env:PSModulePath = (Resolve-Path $Req).Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
    Import-Module -Name $Mod.FullName -Force -Global
    Write-OerLiveStep "module loaded from the kept 9761434 build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith($Before, [System.StringComparison]::OrdinalIgnoreCase))"
}

function Start-S108Fence {
    # Get-AzToken forwards only a request that carries the certificate, so nothing can prompt. In the
    # module's own scope, Invoke-OERGraphRequest is wrapped once: each request's method and path are
    # recorded in memory, for the request log, and never printed.
    $global:S108Token = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $global:S108Token.Add(((@($PSBoundParameters.Keys) | Sort-Object) -join '','')); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S108 fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
    $global:S108Graph = [System.Collections.Generic.List[object]]::new()
    & (Get-Module -Name Omnicit.EntraRBAC) {
        if (-not $script:S108OriginalGraph) { $script:S108OriginalGraph = (Get-Command -Name Invoke-OERGraphRequest -CommandType Function).ScriptBlock }
        $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-OERGraphRequest -CommandType Function))
        $Body = 'end { $M = if ($PSBoundParameters.ContainsKey(''Method'')) { [string]$PSBoundParameters[''Method''] } else { ''GET'' }; $global:S108Graph.Add([PSCustomObject]@{ Method = $M.ToUpperInvariant(); Uri = [string]$PSBoundParameters[''Uri''] }); & $script:S108OriginalGraph @PSBoundParameters }'
        $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
        Set-Item -Path function:script:Invoke-OERGraphRequest -Value ([scriptblock]::Create($Text))
    }
    $Seen = & (Get-Module -Name Omnicit.EntraRBAC) { '{0},{1}' -f (Get-Command Get-AzToken).CommandType, ([bool]((Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S108Graph')) }
    Write-OerLiveStep "fences in place (Get-AzToken is the proxy, the Graph wrapper records): $($Seen -eq 'Function,True')"
}

function Reset-S108Requests { $global:S108Token.Clear(); $global:S108Graph.Clear() }

function Get-S108GroupMap {
    # id -> display name of every group in the tenant, read with the module before the fence is reset;
    # kept in memory only and never printed.
    $Map = @{}
    foreach ($G in @(Get-OERGroup -All -ErrorAction Stop)) { $Map[([string]$G.Id).ToLowerInvariant()] = [string]$G.DisplayName }
    Write-OerLiveStep "groups mapped for the request log: $($Map.Count)"
    $Map
}

function Save-S108RequestLog {
    # The request log of one export: one line per Graph request the module made, "METHOD path", every id
    # replaced by its placeholder through OerLive's redactor (the same map numbers the same id the same way
    # in every log of this step). This file is the transcription the counts are read from.
    param([Parameter(Mandatory)][string]$Name)
    $Path = Join-Path $Raw "requests-$Name.log"
    $Lines = @($global:S108Graph | ForEach-Object { ConvertTo-OerLiveRedacted -Text ('{0} {1}' -f $_.Method, [uri]::UnescapeDataString($_.Uri)) })
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, [System.Text.UTF8Encoding]::new($false))
    Write-OerLiveStep "request log: $($Lines.Count) line(s) written to raw\s108\requests-$Name.log; token requests: $($global:S108Token.Count)"
}

function Measure-S108RequestLog {
    # Reads a request log back and counts the requests per group: a line belongs to the group whose
    # placeholder it carries (a members, owners, eligibility, policy listing, policy-id or policy-rule
    # path), and to no group when it carries none (the group list, the roster, a principal-name lookup).
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$Map)
    $Of = @{}
    foreach ($Id in $Map.Keys) { $Of[(ConvertTo-OerLiveRedacted -Text $Id)] = $Map[$Id] }
    $Per = @{}
    $Shared = 0
    foreach ($Line in @(Get-Content -LiteralPath (Join-Path $Raw "requests-$Name.log"))) {
        $Names = @([regex]::Matches($Line, '00000000-0000-0000-0000-[0-9]{12}') | ForEach-Object { $Of[$_.Value] } | Where-Object { $_ } | Select-Object -Unique)
        if ($Names.Count -eq 0) { $Shared++; continue }
        $Kind = switch -Regex ($Line) {
            '/members' { 'members'; break }
            '/owners' { 'owners'; break }
            'eligibilityScheduleInstances' { 'eligibility'; break }
            'roleManagementPolicyAssignments' { 'policy-id'; break }
            '/rules' { 'policy-rules'; break }
            'roleManagementPolicies\?' { 'criterion'; break }
            default { 'other' }
        }
        foreach ($N in $Names) {
            if (-not $Per.ContainsKey($N)) { $Per[$N] = [ordered]@{ total = 0; members = 0; owners = 0; eligibility = 0; criterion = 0; 'policy-id' = 0; 'policy-rules' = 0; other = 0 } }
            $Per[$N].total++
            $Per[$N][$Kind]++
        }
    }
    [PSCustomObject]@{ Shared = $Shared; Per = $Per }
}

function Write-S108RequestCount {
    # Counts only: the requests no group owns, then the kept and the not-kept groups (how many, how many
    # requests, the least and most per group), then each step group by kind.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Measure, [Parameter(Mandatory)][string[]]$KeptNames)
    $KeptSet = @($Measure.Per.Keys | Where-Object { $KeptNames -contains $_ })
    $NotSet = @($Measure.Per.Keys | Where-Object { $KeptNames -notcontains $_ })
    $Range = { param($Set) if ($Set.Count) { $T = @($Set | ForEach-Object { $Measure.Per[$_].total }); '{0} group(s), {1} request(s), per group {2} to {3}' -f $Set.Count, (($T | Measure-Object -Sum).Sum), (($T | Measure-Object -Minimum).Minimum), (($T | Measure-Object -Maximum).Maximum) } else { '0 group(s)' } }
    Write-OerLiveStep "$($Label): requests owned by no group: $($Measure.Shared)"
    Write-OerLiveStep "$($Label): kept groups: $(& $Range $KeptSet)"
    Write-OerLiveStep "$($Label): groups not kept: $(& $Range $NotSet)"
    foreach ($N in $StepGroups) {
        $C = $Measure.Per[$N]
        if (-not $C) { Write-OerLiveStep "$($Label): $($N): 0 requests"; continue }
        Write-OerLiveStep ("{0}: {1}: {2} request(s) (members {3}, owners {4}, eligibility {5}, criterion {6}, policy ids {7}, policy rules {8}, other {9})" -f $Label, $N, $C.total, $C.members, $C.owners, $C.eligibility, $C.criterion, $C['policy-id'], $C['policy-rules'], $C.other)
    }
}

function Write-S108Own {
    # A command's OWN records in an -ErrorVariable (the id ends in a comma and the command's name), as ids only.
    param([object[]]$Records, [string]$Command)
    $Own = @($Records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    Write-OerLiveStep ("{0} own errors: {1}{2}" -f $Command, $Own.Count, $(if ($Own.Count) { ' -- ' + (($Own | ForEach-Object { $_.FullyQualifiedErrorId }) -join '; ') } else { '' }))
}

function Get-S108Normalized {
    # A JSON array file as sorted compact lines: each members, owners and eligibility list sorted (Graph
    # lists them in no fixed order, measured in step 7b), entries sorted by displayName.
    param([Parameter(Mandatory)][string]$Path)
    @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -NoEnumerate | ForEach-Object { $_ } | Where-Object { $null -ne $_ } | ForEach-Object {
            foreach ($K in 'members', 'owners', 'eligibility') { if ($null -ne $_.$K) { $_.$K = @(@($_.$K) | Sort-Object { ConvertTo-Json -InputObject $_ -Depth 30 -Compress }) } }
            $_
        } | Sort-Object displayName | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 30 -Compress })
}

function Get-S108Roster {
    # groupsRoster.json as displayName -> row (the rows' names are unique in this tenant; a repeat is reported).
    param([Parameter(Mandatory)][string]$Path)
    $Rows = @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -NoEnumerate | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
    $T = @{}
    foreach ($R in $Rows) { if ($T.ContainsKey([string]$R.displayName)) { Write-OerLiveStep 'roster: a display name repeats' }; $T[[string]$R.displayName] = $R }
    $T
}

function Invoke-S108Export {
    # One export of the Groups section into a folder of raw\s108 named after it, fenced; the request log written; the bundle
    # summary and the export's own errors printed as counts and ids.
    param([Parameter(Mandatory)][string]$Name, [hashtable]$Extra = @{})
    Reset-S108Requests
    $Out = Export-OERInventory -OutputPath (Join-Path $Raw "bundle-$Name") -Include Groups -Force -ErrorAction Continue -ErrorVariable ExErr -WarningVariable ExWarn @Extra
    Save-S108RequestLog -Name $Name
    Write-OerLiveStep "bundle $($Name): groups $($Out.Groups); roster $($Out.RosterCount); IncompleteReads $(@($Out.IncompleteReads).Count); warnings $(@($ExWarn).Count)"
    Write-S108Own -Records $ExErr -Command 'Export-OERInventory'
    Copy-Item -LiteralPath $Out.BundlePath -Destination (Join-Path $Raw $Name) -Recurse -Force
    [PSCustomObject]@{ Out = $Out; Warnings = @($ExWarn) }
}

function Get-S108KeptNames {
    # The display names inventory.json carries in a kept bundle.
    param([Parameter(Mandatory)][string]$Name)
    @((Get-Content -LiteralPath (Join-Path $Raw "$Name\inventory.json") -Raw | ConvertFrom-Json).groups | ForEach-Object { [string]$_.displayName })
}
```

### S.1. The module loads from this branch's build, and the 9761434 build is kept

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched; the kept `9761434` build carries none of this branch's changes.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Marks = @('function Get-OERInventoryGroup', 'function Read-OERGroupCollection', 'function Format-OERUnreadCauseClause', '[switch]$RelevantOnly')
foreach ($Side in @(@('this branch', (Join-Path $Cfg.Repo 'output\module')), @('9761434', (Join-Path $Before 'output\module')))) {
    $Psm1 = Get-ChildItem -Path (Join-Path $Side[1] 'Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Psm1) { Write-OerLiveStep "$($Side[0]) build: not found"; continue }
    $Hits = @($Marks | Where-Object { Select-String -LiteralPath $Psm1.FullName -SimpleMatch $_ -Quiet }).Count
    $Ver = (Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1'))
    Write-OerLiveStep "$($Side[0]) build: version $($Ver.ModuleVersion) $($Ver.PrivateData.PSData.Prerelease); marks of this branch: $Hits of $($Marks.Count)"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `this branch build: ... marks of
this branch: 4 of 4`; `9761434 build: ... marks of this branch: 0 of 4`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), fewer than 4 marks in this
branch's build (build it first, never while the gate runs), or any mark in the `9761434` build.

Result: not yet run.

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

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

Result: not yet run.

### 0.2. The prerequisite: the user, four groups, the eligibility and the policy change, after a plan

- [ ] **0.2** `Initialize-OerS108Prereq.ps1 -WhatIf` writes nothing and plans every object; the real run writes the baseline (users, groups) and creates the five objects, the memberships, the eligibility and the policy change; a second run finds every object and writes nothing.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS108Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "prereq run: $($Run -join ' ')"
    & pwsh -NoProfile -NonInteractive -File $Script @Run 2>&1 | ForEach-Object { "$_" }
    Write-OerLiveStep "prereq exit code: $LASTEXITCODE"
}
```

**Expect:** the plan run ends `WhatIf: nothing was created, removed or written.` with exit code 0;
the first real run writes the baseline, creates `oer-s108-user` (disabled) and the four groups,
adds the five memberships, requests the eligibility (`Provisioned` or `PendingProvisioning`) and
changes the policy, each awaited until it is listed, exit code 0; the second real run finds every
object, `written to the tenant: False`, exit code 0.
**Failure looks like:** a refusal, an exit code other than 0, or a second run that writes.

Result: not yet run.

### 0.3. The step groups read as the export will see them

- [ ] **0.3** Read through the module: `oer-s108-ra` is role-assignable; `oer-s108-elig` has one PIM eligibility; `oer-s108-mod` has none and `Test-OERGroupPimInUse` finds it in use (a modified policy); `oer-s108-plain` has none and is not found in use; each has one member or owner as the prerequisite made it.

```powershell
Connect-OerLive -Arm
foreach ($N in $StepGroups) {
    $G = Get-OERGroup -Filter "displayName eq '$N'" -IncludeMembers -IncludeOwners -IncludePimEligibility -ErrorAction Stop
    $Elig = @($G.PimEligibility | Where-Object { $null -ne $_ }).Count
    $Use = & (Get-Module -Name Omnicit.EntraRBAC) { param($Id, $Count) Test-OERGroupPimInUse -GroupId $Id -EligibilityCount $Count } $G.Id $Elig
    Write-OerLiveStep ("{0}: role-assignable {1}; members {2}; owners {3}; PIM eligibility {4}; PIM in use {5} ({6})" -f $N, $G.IsAssignableToRole, @($G.Members).Count, @($G.Owners).Count, $Elig, $Use.InUse, $Use.Reason)
}
Disconnect-OerLive
```

**Expect:** `oer-s108-ra: role-assignable True; members 1; owners 0; PIM eligibility 0; PIM in use
False`; `oer-s108-elig: role-assignable False; members 0; owners 1; PIM eligibility 1; PIM in use
True (the group has PIM eligibility)`; `oer-s108-mod: ... members 1; owners 0; PIM eligibility 0; PIM
in use True (a PIM policy of the group has been modified)`; `oer-s108-plain: ... members 1; owners
1; PIM eligibility 0; PIM in use False`.
**Failure looks like:** another shape: the export's decisions below would then not be the ones this
checklist expects (run 0.2 again, or wait for the listings to settle).

Result: not yet run.

## 1. The default export: the same document, fewer requests (A, B)

### 1.1. Export with the 9761434 build (the reference)

- [ ] **1.1** `Export-OERInventory -Include Groups` with the kept `9761434` build writes a bundle under `raw\s108\before\` and a request log; every group is read in full.

```powershell
Import-S108Before
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'before'
$Measure = Measure-S108RequestLog -Name 'before' -Map $Map
Write-S108RequestCount -Label 'before' -Measure $Measure -KeptNames (Get-S108KeptNames -Name 'before')
Write-OerLiveStep "the step's kept groups are in inventory.json: $(@($Kept | Where-Object { (Get-S108KeptNames -Name 'before') -contains $_ }).Count) of $($Kept.Count); oer-s108-plain is not: $((Get-S108KeptNames -Name 'before') -notcontains 'oer-s108-plain')"
Disconnect-OerLive
```

**Expect:** the module loaded from the kept build; `IncompleteReads 0`; no own error; a request log
with every group's members, owners and eligibility read; every group not kept at 6 requests or more
(members 2, owners 2, eligibility 1, criterion 1); `oer-s108-plain: 6 request(s)`; the three kept step
groups in `inventory.json` and `oer-s108-plain` not; token requests 0.
**Failure looks like:** an `InventoryPartial` (record which read failed), a token request, or a step
group decided otherwise than 0.3 predicts.

Result: not yet run.

### 1.2. Export with this branch: the same groups and content, two requests per group not kept, the roster count null for them

- [ ] **1.2** `Export-OERInventory -Include Groups` with this branch writes a `groups.json` equal entry for entry to 1.1's once each members, owners and eligibility list is sorted; `inventory.json` keeps the same groups; every group not kept costs exactly 2 requests (eligibility 1, criterion 1) and every kept group as many as in 1.1; `groupsRoster.json` equals 1.1's except that `memberCount` is null for every group not kept.

```powershell
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'after'
$Now = @(Get-S108Normalized -Path (Join-Path $Raw 'after\groups.json'))
$Was = @(Get-S108Normalized -Path (Join-Path $Raw 'before\groups.json'))
Write-OerLiveStep "groups.json equals 9761434's entry for entry, each list sorted: $(($Now.Count -eq $Was.Count) -and -not (Compare-Object $Now $Was -SyncWindow 0)) ($($Now.Count) and $($Was.Count))"
$KeptNow = @(Get-S108KeptNames -Name 'after' | Sort-Object); $KeptWas = @(Get-S108KeptNames -Name 'before' | Sort-Object)
Write-OerLiveStep "inventory.json keeps the same groups: $(($KeptNow.Count -eq $KeptWas.Count) -and -not (Compare-Object $KeptNow $KeptWas -SyncWindow 0))"
$MNow = Measure-S108RequestLog -Name 'after' -Map $Map
$MWas = Measure-S108RequestLog -Name 'before' -Map $Map
Write-S108RequestCount -Label 'after' -Measure $MNow -KeptNames $KeptNow
$NotKeptNames = @($MWas.Per.Keys | Where-Object { $KeptWas -notcontains $_ })
Write-OerLiveStep "every group not kept costs exactly 2 requests now: $(@($NotKeptNames | Where-Object { -not $MNow.Per[$_] -or $MNow.Per[$_].total -ne 2 -or $MNow.Per[$_].eligibility -ne 1 -or $MNow.Per[$_].criterion -ne 1 }).Count -eq 0) ($($NotKeptNames.Count) groups; before $((@($NotKeptNames | ForEach-Object { $MWas.Per[$_].total }) | Measure-Object -Sum).Sum) requests, now $((@($NotKeptNames | ForEach-Object { if ($MNow.Per[$_]) { $MNow.Per[$_].total } else { 0 } }) | Measure-Object -Sum).Sum))"
Write-OerLiveStep "every kept group costs what it cost before: $(@($KeptWas | Where-Object { -not $MNow.Per[$_] -or -not $MWas.Per[$_] -or $MNow.Per[$_].total -ne $MWas.Per[$_].total }).Count -eq 0)"
$RNow = Get-S108Roster -Path (Join-Path $Raw 'after\groupsRoster.json'); $RWas = Get-S108Roster -Path (Join-Path $Raw 'before\groupsRoster.json')
$Diff = @($RWas.Keys | Where-Object { -not $RNow.ContainsKey($_) -or (($RNow[$_] | Select-Object displayName, roleAssignable, dynamic, onPremisesSynced | ConvertTo-Json -Compress) -ne ($RWas[$_] | Select-Object displayName, roleAssignable, dynamic, onPremisesSynced | ConvertTo-Json -Compress)) })
Write-OerLiveStep "roster: rows $($RNow.Count) and $($RWas.Count); every row equal apart from memberCount: $($Diff.Count -eq 0 -and $RNow.Count -eq $RWas.Count)"
Write-OerLiveStep "roster: memberCount equal for every kept group: $(@($KeptWas | Where-Object { $RNow[$_].memberCount -ne $RWas[$_].memberCount }).Count -eq 0); null now for every group not kept: $(@($NotKeptNames | Where-Object { $null -ne $RNow[$_].memberCount }).Count -eq 0) ($($NotKeptNames.Count)); a number before for $(@($NotKeptNames | Where-Object { $null -ne $RWas[$_].memberCount }).Count) of them"
Write-OerLiveStep "oer-s108-plain memberCount: before $($RWas['oer-s108-plain'].memberCount), now $(if ($null -eq $RNow['oer-s108-plain'].memberCount) { 'null' } else { $RNow['oer-s108-plain'].memberCount })"
Disconnect-OerLive
```

**Expect:** `groups.json equals 9761434's entry for entry, each list sorted: True`; `inventory.json
keeps the same groups: True`; `every group not kept costs exactly 2 requests now: True` with the
totals before and now; `every kept group costs what it cost before: True`; the roster equal apart
from `memberCount`, equal for every kept group and null now for every group not kept;
`oer-s108-plain memberCount: before 1, now null`; `IncompleteReads 0`, no own error, token requests 0.
**Failure looks like:** an entry that differs, with its lists sorted, from what `9761434` exported; a
group not kept read in full; a kept group read differently. A group created or changed by another
process between 1.1 and 1.2 shows as a difference: run 1.1 and 1.2 again back to back before calling
it a failure.

Result: not yet run.

## 2. -AllGroupsDetailed reads as before

### 2.1. Every group in detail with the 9761434 build (the reference)

- [ ] **2.1** `Export-OERInventory -Include Groups -AllGroupsDetailed` with the kept `9761434` build writes `raw\s108\before-all\` and a request log.

```powershell
Import-S108Before
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'before-all' -Extra @{ AllGroupsDetailed = $true }
Write-S108RequestCount -Label 'before-all' -Measure (Measure-S108RequestLog -Name 'before-all' -Map $Map) -KeptNames (Get-S108KeptNames -Name 'before-all')
Disconnect-OerLive
```

**Expect:** the module loaded from the kept build; `IncompleteReads 0`; no own error; every security
group in `inventory.json`; token requests 0.
**Failure looks like:** an `InventoryPartial`, or a token request.

Result: not yet run.

### 2.2. Every group in detail with this branch: the same document and the same requests per group

- [ ] **2.2** `Export-OERInventory -Include Groups -AllGroupsDetailed` with this branch writes a `groups.json` equal entry for entry to 2.1's (lists sorted), a roster equal row for row, and costs each group as many requests as 2.1.

```powershell
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'after-all' -Extra @{ AllGroupsDetailed = $true }
$Now = @(Get-S108Normalized -Path (Join-Path $Raw 'after-all\groups.json'))
$Was = @(Get-S108Normalized -Path (Join-Path $Raw 'before-all\groups.json'))
Write-OerLiveStep "groups.json equals 9761434's entry for entry, each list sorted: $(($Now.Count -eq $Was.Count) -and -not (Compare-Object $Now $Was -SyncWindow 0)) ($($Now.Count) and $($Was.Count))"
$RNow = @(Get-Content -LiteralPath (Join-Path $Raw 'after-all\groupsRoster.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ } | Sort-Object displayName | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress })
$RWas = @(Get-Content -LiteralPath (Join-Path $Raw 'before-all\groupsRoster.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ } | Sort-Object displayName | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress })
Write-OerLiveStep "roster equals 9761434's row for row: $(($RNow.Count -eq $RWas.Count) -and -not (Compare-Object $RNow $RWas -SyncWindow 0))"
$MNow = Measure-S108RequestLog -Name 'after-all' -Map $Map
$MWas = Measure-S108RequestLog -Name 'before-all' -Map $Map
Write-S108RequestCount -Label 'after-all' -Measure $MNow -KeptNames (Get-S108KeptNames -Name 'after-all')
$Off = @($MWas.Per.Keys | Where-Object { -not $MNow.Per[$_] -or $MNow.Per[$_].total -ne $MWas.Per[$_].total })
Write-OerLiveStep "every group costs what it cost before: $($Off.Count -eq 0 -and $MNow.Per.Count -eq $MWas.Per.Count) ($($MNow.Per.Count) groups)"
Disconnect-OerLive
```

**Expect:** `groups.json equals 9761434's entry for entry, each list sorted: True`; `roster equals
9761434's row for row: True`; `every group costs what it cost before: True`; `IncompleteReads 0`, no
own error, token requests 0.
**Failure looks like:** any difference: `-AllGroupsDetailed` must read and write exactly as before.

Result: not yet run.

## 3. -GroupFilter narrows and never widens (C)

### 3.0. What Graph answers for a composed filter with an `or` (a read, no export)

- [ ] **3.0** One Graph read of the groups with the filter the export composes from `startswith(displayName,'oer-s108-')) or (securityEnabled eq false`: its status, and how many groups it lists that are not security-enabled.

```powershell
Connect-OerLive -Arm
$Composed = "securityEnabled eq true and (startswith(displayName,'oer-s108-')) or (securityEnabled eq false)"
$L = Invoke-OerLiveGraph -All -Uri ('v1.0/groups?$filter={0}&$select=id,displayName,securityEnabled' -f [uri]::EscapeDataString($Composed))
$G = @(@($L.Body['value']) | Where-Object { $null -ne $_ })
Write-OerLiveStep "composed filter: status $($L.Status) $($L.Code); groups listed $($G.Count); not security-enabled $(@($G | Where-Object { -not [bool]$_['securityEnabled'] }).Count); step groups $(@($G | Where-Object { ([string]$_['displayName']).StartsWith('oer-s108-') }).Count)"
Disconnect-OerLive
```

**Expect:** a measurement, not a verdict: either `status 200` with the four step groups and every
group that is not security-enabled (the filter widened the read, which is what 3.2 must not let into
`inventory.json`), or a refusal of the expression (then 3.2 shows the read failing, which widens
nothing, and the post-read check is class B).
**Failure looks like:** a 401 or 403 (STOP).

Result: not yet run.

### 3.1. A narrowing filter: only the step's groups are read, the roster stays whole

- [ ] **3.1** `Export-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s108-')"` reads only the four step groups (the list request carries the composed filter in parentheses), keeps the three kept ones, and writes the whole roster.

```powershell
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'filter' -Extra @{ GroupFilter = "startswith(displayName,'oer-s108-')" }
$Log = @(Get-Content -LiteralPath (Join-Path $Raw 'requests-filter.log'))
Write-OerLiveStep "the group list carries the composed filter: $(@($Log | Where-Object { $_ -like "GET v1.0/groups?`$filter=securityEnabled eq true and (startswith(displayName,'oer-s108-'))*" }).Count -eq 1)"
$M = Measure-S108RequestLog -Name 'filter' -Map $Map
Write-S108RequestCount -Label 'filter' -Measure $M -KeptNames (Get-S108KeptNames -Name 'filter')
Write-OerLiveStep "groups read: only the step groups: $(@($M.Per.Keys | Where-Object { -not $_.StartsWith('oer-s108-') }).Count -eq 0) ($($M.Per.Count))"
$KeptF = @(Get-S108KeptNames -Name 'filter' | Sort-Object)
Write-OerLiveStep "inventory.json keeps exactly the three kept step groups: $(($KeptF -join ',') -eq ((@($Kept) | Sort-Object) -join ','))"
Write-OerLiveStep "roster rows: $($R.Out.RosterCount), as many as 1.2's: $($R.Out.RosterCount -eq @(Get-Content -LiteralPath (Join-Path $Raw 'after\groupsRoster.json') -Raw | ConvertFrom-Json).Count)"
Disconnect-OerLive
```

**Expect:** `the group list carries the composed filter: True`; `groups read: only the step groups:
True (4)`; `oer-s108-plain: 2 request(s)`; `inventory.json keeps exactly the three kept step groups:
True`; the roster as many rows as 1.2's; `IncompleteReads 0`, no own error, no warning.
**Failure looks like:** another group read or kept, a filter without the parentheses, or a roster
narrowed by the filter.

Result: not yet run.

### 3.2. A filter that closes the parenthesis with an `or` widens nothing

- [ ] **3.2** `Export-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s108-')) or (securityEnabled eq false"` keeps exactly the three kept step groups in `inventory.json`: a group the read returns although it is not security-enabled is left out, with one warning naming how many.

```powershell
Connect-OerLive -Arm
$Map = Get-S108GroupMap
Start-S108Fence
$R = Invoke-S108Export -Name 'filter-or' -Extra @{ GroupFilter = "startswith(displayName,'oer-s108-')) or (securityEnabled eq false" }
foreach ($W in $R.Warnings) { Write-OerLiveStep "warning: $W" }
$KeptO = @(Get-S108KeptNames -Name 'filter-or' | Sort-Object)
Write-OerLiveStep "inventory.json keeps exactly the three kept step groups: $(($KeptO -join ',') -eq ((@($Kept) | Sort-Object) -join ',')) ($($KeptO.Count))"
$M = Measure-S108RequestLog -Name 'filter-or' -Map $Map
Write-OerLiveStep "groups read beyond the step groups: $(@($M.Per.Keys | Where-Object { -not $_.StartsWith('oer-s108-') }).Count)"
Disconnect-OerLive
```

**Expect:** when 3.0 measured `status 200`: one warning `-GroupFilter returned N group(s) that are not
security-enabled; inventory.json keeps security-enabled groups only, so they were left out.`, N the
count 3.0 measured; `inventory.json keeps exactly the three kept step groups: True (3)`; `groups read
beyond the step groups: 0` (a group left out is not read at all); `IncompleteReads 0`. When 3.0
measured a refusal: `IncompleteReads 1` naming `groups`, `inventory.json` with no group -- narrower,
never wider.
**Failure looks like:** any group in `inventory.json` other than the three, or a group that is not
security-enabled read in full.

Result: not yet run.

## 4. The exported document converges (G8)

### 4.1. The kept step groups from 1.2's inventory.json: Unchanged twice

- [ ] **4.1** The three kept step groups' entries from 1.2's `inventory.json` (with its `tenantId`) pass `Test-OERStructure`, and `Invoke-OERStructure -Include Groups` applied twice gives only `Unchanged`, with no write.

```powershell
Connect-OerLive -Arm
Start-S108Fence
$Inv = Get-Content -LiteralPath (Join-Path $Raw 'after\inventory.json') -Raw | ConvertFrom-Json
$Doc = [PSCustomObject]@{ version = $Inv.version; tenantId = $Inv.tenantId; groups = @($Inv.groups | Where-Object { $Kept -ccontains [string]$_.displayName }) }
Write-OerLiveStep "document: groups $(@($Doc.groups).Count), every one with the prefix: $(@($Doc.groups | Where-Object { -not ([string]$_.displayName).StartsWith('oer-s108-') }).Count -eq 0); carries tenantId: $([bool]$Doc.tenantId)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-4.1.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-4.1.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
foreach ($Pass in 1, 2) {
    Reset-S108Requests
    $Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-4.1.json') -Include Groups -Confirm:$false -ErrorAction Continue -ErrorVariable ApErr -WarningVariable ApWarn -WarningAction SilentlyContinue)
    Write-OerLiveStep "run $($Pass):"
    foreach ($Row in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $Row.Section, $Row.Item, $Row.Action, $Row.Detail) }
    Write-OerLiveStep "rows: $($Rows.Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); warnings: $(@($ApWarn).Count)"
    Write-S108Own -Records $ApErr -Command 'Invoke-OERStructure'
    $Writes = @($global:S108Graph | Where-Object { $_.Method -ne 'GET' -and -not ($_.Method -eq 'POST' -and $_.Uri -match '/(getByIds|getMemberGroups|getMemberObjects|checkMemberGroups|checkMemberObjects)$') })
    Write-OerLiveStep "requests: Graph $($global:S108Graph.Count); writes $($Writes.Count); token $($global:S108Token.Count)"
}
Disconnect-OerLive
```

**Expect:** three groups, prefixed, with `tenantId`; valid; in both runs every row `Unchanged`, `not
Unchanged: 0`, no own error, writes 0.
**Failure looks like:** any row other than `Unchanged`, or a write (G8). A membership or policy
written minutes earlier can still be settling (a PATCH needed about 30 s in step 7b): wait and run
again before calling it a failure.

Result: not yet run.

## B. Proved offline (class B)

- **A synchronized security group in the new selection.** `tests/Unit/Private/Get-OERInventoryGroup.Tests.ps1`:
  kept in full under `-IncludeSyncedGroups` (members read), and exactly two requests without it.
- **A relevance read that fails.** The same file: an eligibility read refused, and a criterion
  refused, each read in full as before and named as unread; every group refused at once, none
  dropped.
- **A relevant group sharing its name with a group that is not relevant.** The same file: both left
  out and the name reported once, as before.
- **Progress, completed on a failure.** The same file: one record per group and exactly one
  `-Completed`, also when the loop stops on an uncaught error.
- **The post-read security check when Graph refuses the composed filter of 3.0.** The same file and
  `tests/Unit/Public/Export-OERInventory.Tests.ps1`.

## Teardown

### T.1. The objects removed, nothing left, raw\s108 deleted

- [ ] **T.1** `Initialize-OerS108Prereq.ps1 -Teardown -Unattended` removes the eligibility, the memberships, the four groups and the user; the sweep finds nothing with the prefix and no unread collection; the counts equal the baseline; no module or Graph SDK session remains; `raw\s108\` is deleted after the results are written.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS108Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -Teardown -Unattended 2>&1 | ForEach-Object { "$_" }
Write-OerLiveStep "teardown exit code: $LASTEXITCODE"
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
$State = & (Get-Module -Name Omnicit.EntraRBAC) { $null -eq $script:_OERAuthState }
Write-OerLiveStep "module session cleared: $State; Graph SDK session left: $([bool](Get-MgContext))"
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s108 deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** the teardown removes every object (`Removed`), exit code 0, and the counts equal the
baseline; 0 objects, 0 unread collections; `module session cleared: True; Graph SDK session left:
False`; `raw\s108 deleted: True`.
**Failure looks like:** residue (exit code 3: a row in `raw\residue.json`), an object or an unread
collection left, a session left, or the folder still there. The listings can lag a deletion: T.2
reads back once they have settled.

Result: not yet run.

### T.2. Read-back once the listings have settled

- [ ] **T.2** At least a minute after T.1, the sweep lists nothing with the prefix and no unread collection, and the tenant lists as many users and groups as the baseline of 0.2 recorded; `raw\s108\` (which H.1 creates again) is deleted afterwards.

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
$Users = Invoke-OerLiveGraph -All -Uri 'v1.0/users?$select=id'
$Groups = Invoke-OerLiveGraph -All -Uri 'v1.0/groups?$select=id'
Write-OerLiveStep "users listed: $(@(@($Users.Body['value']) | Where-Object { $null -ne $_ }).Count); groups listed: $(@(@($Groups.Body['value']) | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s108 deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0 objects, 0 unread collections; users and groups equal to the baseline counts 0.2
printed; `raw\s108 deleted: True`.
**Failure looks like:** a step object still listed after several minutes (read back again later
before calling it residue), another count than the baseline, or the folder still there.

Result: not yet run.
