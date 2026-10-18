# Live verification checklist -- the export and the apply engine stay in the home tenant's subscriptions (fix/stay-in-the-home-tenant)

**This branch does not merge until every box in sections S, 0, M, 1, 2, 3 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to
be impossible to run, write "cannot be verified, and therefore we do not know" on its result line and
say why; do not leave it blank and do not tick it. A check that could not run for a stated reason is
marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** One manual check
(class C) is foreseen and does not block the merge: a tenant that manages another tenant's subscription
through Azure Lighthouse (section C).

**What this file writes to the tenant: only inside the prefix `oer-s116c-`.** The prerequisite script
`Initialize-OerS116cPrereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a security group `oer-s116c-grp` with no member and no owner, and a tagged, empty resource group
`oer-s116c-rg` in the test subscription. It assigns nothing. Check 2.2 runs `Invoke-OERStructure` for
real and creates ONE role assignment: Reader for `oer-s116c-grp` at `oer-s116c-rg`. Checks 2.3, 3.1 and
3.2 run it for real too and must write nothing, and nothing else here writes. The teardown (T.1) removes
the role assignment, the resource group and the group, and purges the group from the deleted items.
Bundles, documents and request counts are written under `raw\s116c\`, which is deleted after the results
are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, and for check M.4
`oer-live-cc-noperm`, through the OerLive library, which lives beside the operator's copy of this file
outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only, with the
certificate; nothing here signs in as a person. A 401 or 403 as `oer-live-cc` is a stop; a refusal as
`oer-live-cc-noperm`, which holds no Azure role, is what M.4 measures.

**Permissions.** The group needs the Microsoft Graph application permission `Group.ReadWrite.All`; the
resource group and the role assignment need the identity's existing Azure role on the test subscription.
Nothing here needs a permission the earlier steps did not use, and granting one is the operator's
decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, and every block that runs the
module installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s116c/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** A tenant ID is compared and printed as True/False only. A
warning and an error that stops a script go straight to the host, so each block is run in its own
process whose WHOLE output (standard output and standard error) is written to a file under
`raw\s116c\`, redacted with OerLive's redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The export walks only the home tenant's subscriptions** ("fix: walk only the home tenant's
  subscriptions in the inventory export", "fix: name the commands the subscription tenant refusal speaks
  for", "fix: decide no home tenant for a scope a document could not declare"). A new private owner, `Get-OERSubscriptionHomeTenant`, decides whether a subscription belongs to
  the tenant the session's Microsoft Graph token was issued for (`TokenTenantId`), from the `tenantId`
  Azure Resource Manager returns for the subscription (api-version `2022-12-01`). The export's Azure walk
  decides each listed subscription from the list itself, with no request of its own, and an export
  `-Scope` with one read of its subscription. A subscription of another tenant is not walked: one warning,
  and the bundle README names it under "Subscriptions delegated from another tenant (not read)". A
  subscription whose tenant cannot be decided is not walked either: it is named in `IncompleteReads` as
  `subscriptionHomeTenant at` its scope, with one warning, and the export is partial. So is a raw `-Scope`
  spelled in a way a document could not declare (a `.` or `..` segment, `%`, `\`, a trailing `/`), which
  the request would send to another path than the text: nothing is read for it.
- **B. The apply engine refuses another tenant's subscription** ("fix: refuse another tenant's
  subscription in the apply engine", "fix: pin the engine's refusal outcomes and gate 10's row floor"). `Invoke-OERStructure` asks the owner once per subscription and
  document, before it reads or writes anything for a `roleAssignments` or `roleManagementPolicies` entry
  at a scope there. A subscription of another tenant makes the entry `Failed` with the new error
  `SubscriptionTenantMismatch`; one whose tenant cannot be decided makes it `Failed` with the error that
  stopped the decision, as itself. Nothing is read or written at that scope, and `-Prune` removes nothing
  there.
- **C. The texts** ("docs: say that the export and the apply stay in the home tenant", "docs: record the
  home tenant rulings and gate 10's fourteenth row", "docs: add the release note for the home tenant
  subscriptions", "docs: name the inherited management group rows a home tenant check does not see",
  "docs: record the final review rulings for the home tenant subscriptions", "docs: say a misspelled
  management group scope is not read either"): help, the prompt template,
  README, the about topic, the inventory-to-LLM guide, the rationale, the house rules and the release note.

A live tenant is needed because the claims are about what Azure Resource Manager answers for a
subscription -- its `tenantId` for the session's own subscription, and a refusal for one the identity
cannot see -- and about what the export and the engine then send: exactly one more request than `main`
for an export of the own subscription, the same `inventory.json` as `main`, and an apply that checks the
subscription once and then creates, keeps or refuses as it should.

## What this file does not check, and why

- **A subscription of another tenant (class B, B.1 to B.3, and class C, C.1).** The test tenant manages
  no other tenant, so no identity here can see a subscription whose `tenantId` is another tenant's. The
  unit tests hold the owner's `Foreign` verdict, the walk that names such a subscription and reads nothing
  from it, the README section, and the engine's `SubscriptionTenantMismatch` refusal with and without
  `-Prune`.
- **A subscription answer without a `tenantId`, and a session whose token names no tenant ID (class B,
  B.4).** Neither can be produced on demand.
- **The cache per piped document (class B, B.5).**
- **The texts (class B, B.6).** Section B names the gates that hold them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets
  the session's `Repo` to it, so the module loads from the worktree's build; the main clone is never
  checked out on another commit or branch (S.1 reads that it was not).
- The **prerequisite objects**: check 0.2 runs `Initialize-OerS116cPrereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence, the counters
and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s116c-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Grp = 'oer-s116c-grp'; $Rg = 'oer-s116c-rg'
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
$RgScope = "$SubScope/resourceGroups/$Rg"
# main's commit at the start of the step, for check 1.2.
$MainCommit = 'cd7e6a3'
# The step's raw folder as OerLive fixed it (git-ignored), and the ids the prerequisite script recorded
# there (never printed).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Ids = if (Test-Path -LiteralPath (Join-Path $Raw 'created-s116c.json')) { Get-Content -LiteralPath (Join-Path $Raw 'created-s116c.json') -Raw | ConvertFrom-Json -AsHashtable } else { @{} }

function Start-S116cNoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S116cTokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S116cTokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S116c fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S116cCount {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is a
    # GET. The path of every request is recorded, the query dropped.
    $global:S116cGraph = [System.Collections.Generic.List[string]]::new()
    $global:S116cArm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116cGraph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116cArm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S116cCount {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S116cArmCount {
    # How many Azure Resource Manager requests of one kind were counted since Start-S116cCount. A
    # subscription read is a GET of exactly /subscriptions/ and one id; -SubscriptionId narrows it to one
    # subscription, and -Touching counts every request whose path lies in that subscription.
    param([Parameter(Mandatory)][ValidateSet('SubscriptionRead', 'SubscriptionList', 'RoleAssignmentRead', 'RolePolicyRead', 'Lighthouse', 'Touching')][string]$Kind, [string]$SubscriptionId)
    $Id = [regex]::Escape([string]$SubscriptionId)
    $Pattern = switch ($Kind) {
        'SubscriptionRead' { if ($SubscriptionId) { "^GET /subscriptions/$Id/?$" } else { '^GET /subscriptions/[^/]+/?$' } }
        'SubscriptionList' { '^GET /subscriptions/?$' }
        'RoleAssignmentRead' { '^GET .*/providers/Microsoft\.Authorization/roleAssignments' }
        'RolePolicyRead' { '^GET .*/providers/Microsoft\.Authorization/roleManagementPolic' }
        'Lighthouse' { '/providers/Microsoft\.ManagedServices/' }
        'Touching' { "^[A-Z]+ /subscriptions/$Id(/|$)" }
    }
    @($global:S116cArm | Where-Object { $_ -match $Pattern }).Count
}

function Get-S116cSent {
    # Requests counted since Start-S116cCount: totals and writes (any method but GET), with the write paths.
    # directoryObjects/getByIds is a read sent as POST, so it is never counted as a write.
    $GraphWrites = @($global:S116cGraph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */directoryObjects/getByIds' })
    $ArmWrites = @($global:S116cArm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S116cTokenCalls; Microsoft Graph requests: $($global:S116cGraph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S116cArm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" }); subscription reads: $(Get-S116cArmCount -Kind SubscriptionRead); subscription list reads: $(Get-S116cArmCount -Kind SubscriptionList); role assignment reads: $(Get-S116cArmCount -Kind RoleAssignmentRead); role policy reads: $(Get-S116cArmCount -Kind RolePolicyRead)"
}

function Save-S116cRequests {
    # The counted request paths of one run, kept under raw\s116c for a later comparison.
    param([Parameter(Mandatory)][string]$Name)
    $null = New-Item -ItemType Directory -Path $Raw -Force
    $Data = [ordered]@{ Graph = @($global:S116cGraph); Arm = @($global:S116cArm) }
    [System.IO.File]::WriteAllText((Join-Path $Raw "$Name.json"), (ConvertTo-Json -InputObject $Data -Depth 5), [System.Text.UTF8Encoding]::new($false))
}

function Show-S116cRows {
    # One line per Invoke-OERStructure result row. The documents here hold only the step's own rows.
    param([object[]]$Rows)
    foreach ($R in @($Rows | Where-Object { $null -ne $_ })) { Write-OerLiveStep "Row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Show-S116cErrors {
    # The error ids an -ErrorVariable holds, each with its count; the records Invoke-OERStructure wrote
    # itself (FullyQualifiedErrorId ending ',Invoke-OERStructure') counted apart.
    param([object[]]$Errors)
    $All = @($Errors | Where-Object { $null -ne $_ })
    $Ids = @($All | ForEach-Object { $Id = ([string]$_.FullyQualifiedErrorId -split ',')[0]; if ($Id) { $Id } else { '(no id)' } })
    $Own = @($All | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "Errors: $(if ($Ids.Count) { (@($Ids | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name) x$($_.Count)" })) -join ', ' } else { 'none' }); written by Invoke-OERStructure itself: $(if ($Own.Count) { (@($Own | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name) x$($_.Count)" })) -join ', ' } else { 'none' })"
}

function Save-S116cDocument {
    # A structure document written as JSON under raw\s116c\docs; returns its path.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][object]$Document)
    $Dir = Join-Path $Raw 'docs'
    $null = New-Item -ItemType Directory -Path $Dir -Force
    $Path = Join-Path $Dir "$Name.json"
    [System.IO.File]::WriteAllText($Path, ($Document | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $Path
}

function New-S116cMadeUpSubscriptionId {
    # A subscription id no identity here can see: a new random GUID per process (check M.2 shows that
    # Azure Resource Manager answers 404 for one).
    [guid]::NewGuid().ToString()
}

function Get-S116cAtScope {
    # The role assignments Azure Resource Manager lists AT the step's resource group, as principal names.
    $Filter = [uri]::EscapeDataString('atScope()')
    $R = Invoke-OerLiveArm -All -Path "$RgScope/providers/Microsoft.Authorization/roleAssignments?`$filter=$Filter&api-version=2022-04-01"
    if (-not $R.Ok) { return "read failed ($($R.Status) $($R.Code))" }
    @($R.Body.value | Where-Object { $null -ne $_ -and ([string]$_.properties.scope).TrimEnd('/') -ieq $RgScope } | ForEach-Object {
            if ($Ids['grp'] -and ([string]$_.properties.principalId).ToLowerInvariant() -eq $Ids['grp']) { $Grp } else { 'another principal' }
        })
}

function Get-S116cBundle {
    # The newest bundle folder under one of the step's export folders.
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -LiteralPath (Join-Path $Raw $Name) -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Get-S116cReadmeSection {
    # One '## ' section of a bundle README, by the start of its heading, up to the next '## ' heading.
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Heading)
    $Lines = $Text.Replace("`r`n", "`n").Split("`n")
    $Out = [System.Collections.Generic.List[string]]::new(); $In = $false
    foreach ($L in $Lines) {
        if ($L.StartsWith('## ')) { if ($In) { break }; $In = $L.StartsWith("## $Heading") }
        if ($In) { $Out.Add($L) }
    }
    $Out
}

function ConvertTo-S116cCanonical {
    # A JSON value in a form that does not depend on order: object keys sorted, and array elements
    # sorted by their own canonical JSON (Microsoft Graph returns members and owners in no fixed order).
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $O = [ordered]@{}
        foreach ($K in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $O[$K] = ConvertTo-S116cCanonical -Value $Value[$K] }
        return $O
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $Items = @(foreach ($V in $Value) { , (ConvertTo-S116cCanonical -Value $V) })
        return , @($Items | Sort-Object { ConvertTo-Json -InputObject $_ -Depth 60 -Compress })
    }
    $O = [ordered]@{}
    foreach ($K in @($Value.PSObject.Properties.Name | Sort-Object)) { $O[$K] = ConvertTo-S116cCanonical -Value $Value.$K }
    $O
}

function Get-S116cFileCanonical {
    # A bundle file as canonical, compressed JSON text.
    param([Parameter(Mandatory)][string]$Path)
    ConvertTo-Json -InputObject (ConvertTo-S116cCanonical -Value (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate)) -Depth 60 -Compress
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched. #type/subtask

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
Write-OerLiveStep "The worktree's build decides a subscription's home tenant: $(& $Has 'function Get-OERSubscriptionHomeTenant')"
Write-OerLiveStep "The worktree's build carries the refusal SubscriptionTenantMismatch: $(& $Has "'SubscriptionTenantMismatch'")"
Write-OerLiveStep "The worktree's build names an undecided subscription: $(& $Has 'subscriptionHomeTenant at ')"
Write-OerLiveStep "The worktree's build writes the README section for another tenant's subscriptions: $(& $Has 'Subscriptions delegated from another tenant (not read)')"
Write-OerLiveStep "The worktree's build keeps one subscription check per document in the engine: $(& $Has '$SubscriptionTenantCache')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a
`False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-18 00:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. Run in session s11-steg6c-c2 (the step's third session): the module loads from the worktree s11-steg6c-c2, which is not the main clone; the worktree is on fix/stay-in-the-home-tenant at 8996fab with 0 tracked changes, and its build (1.2.1, built in this worktree) carries all five marks. The main clone is on main, never switched; its local main is an older commit of main (an ancestor of origin/main), which is the operator's clone and not this step's. Leak check: 0 hits.

Console, redacted (S.1):
Runner: check S.1; child exit code 0; 2 s; run at 2026-10-18 00:54 UTC.
[oer-s116c] The module loads from a worktree that is not the main clone: True
[oer-s116c] Main clone: branch main; HEAD 491e72e
[oer-s116c] Worktree: branch fix/stay-in-the-home-tenant; HEAD 8996fab docs: add the live checklist for the home tenant subscriptions; tracked changes: 0
[oer-s116c] The worktree's build decides a subscription's home tenant: True
[oer-s116c] The worktree's build carries the refusal SubscriptionTenantMismatch: True
[oer-s116c] The worktree's build names an undecided subscription: True
[oer-s116c] The worktree's build writes the README section for another tenant's subscriptions: True
[oer-s116c] The worktree's build keeps one subscription check per document in the engine: True
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's build:
True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result: 2026-10-18 00:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. Every identity line True, identity check passed, and the module is the worktree's build (1.2.1, loaded from the worktree s11-steg6c-c2). Leak check: 0 hits.

Console, redacted (0.1):
Runner: check 0.1; child exit code 0; 4 s; run at 2026-10-18 00:54 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] The module is the worktree's build: True; version 1.2.1
```

### 0.2. The prerequisite objects

- [x] **0.2** `Initialize-OerS116cPrereq.ps1 -WhatIf` plans the group and the resource group and writes nothing; the first `-Unattended` run writes the baseline and creates both; the second finds both and creates nothing. #type/subtask

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS116cPrereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "== Initialize-OerS116cPrereq.ps1 $($Run -join ' ')"
    $Lines = @(& pwsh -NoProfile -NonInteractive -File $Script @Run 2>&1)
    foreach ($L in $Lines) { Write-Host ('[prereq] ' + (ConvertTo-OerLiveRedacted -Text ([string]$L))) }
    Write-OerLiveStep "Exit code: $LASTEXITCODE"
}
Write-OerLiveStep "The created ids are recorded: group $([bool]((Get-Content -LiteralPath (Join-Path $Raw 'created-s116c.json') -Raw | ConvertFrom-Json -AsHashtable)['grp']))"
```

**Expect:** the `-WhatIf` run prints a `What if:` line for the baseline, the group and the resource group
and creates nothing; the first `-Unattended` run writes the baseline (no prefixed object, no resource
group before it), creates `oer-s116c-grp` and reads it back by its id, and creates `oer-s116c-rg`
(`swedencentral`, tagged); the second run finds both and creates nothing; exit code 0 each time; the
group's id recorded.
**Failure looks like:** a prefixed object before the first run (STOP: the script did not make it), a
401/403 (STOP: a missing permission), or a second run that creates something.

Result: 2026-10-18 00:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. The -WhatIf run printed a What if: line for the baseline, the group and the resource group and created nothing (the sweep found no prefixed object, the resource group did not exist). The first -Unattended run wrote the baseline, created oer-s116c-grp (its read by id answered 404 three times, replication delay, then read back True) and created oer-s116c-rg (Succeeded); the second run found both and created nothing; exit code 0 each time; the group's id is recorded. Leak check: 0 hits.

Console, redacted (0.2):
Runner: check 0.2; child exit code 0; 36 s; run at 2026-10-18 00:55 UTC.
[oer-s116c] == Initialize-OerS116cPrereq.ps1 -WhatIf
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: CREATE. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Baseline: objects carrying the prefix: 0; the resource group exists: False.
[prereq] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s116c\baseline-s116c.json".
[prereq] What if: Performing the operation "Create a security group with no member and no owner (Microsoft Graph POST v1.0/groups)" on target "oer-s116c-grp".
[prereq] What if: Performing the operation "Create a resource group with no resource in the test subscription (Azure Resource Manager PUT resourcegroups, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s116c)')" on target "oer-s116c-rg".
[prereq] [oer-s116c] Setup changes nothing outside the prefix, so nothing is restored by -Teardown; it removes the test objects.
[oer-s116c] Exit code: 0
[oer-s116c] == Initialize-OerS116cPrereq.ps1 -Unattended
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: CREATE. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Baseline: objects carrying the prefix: 0; the resource group exists: False.
[prereq] [oer-s116c] Wrote the baseline raw\s116c\baseline-s116c.json and read it back.
[prereq] [oer-s116c] Reading oer-s116c-grp back by its id answered 404 Request_ResourceNotFound (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[prereq] [oer-s116c] Reading oer-s116c-grp back by its id answered 404 Request_ResourceNotFound (attempt 2 of 6, likely replication delay) -- trying again in 5 s.
[prereq] [oer-s116c] Reading oer-s116c-grp back by its id answered 404 Request_ResourceNotFound (attempt 3 of 6, likely replication delay) -- trying again in 5 s.
[prereq] [oer-s116c] Created oer-s116c-grp; read back by its id: True.
[prereq] [oer-s116c] Created oer-s116c-rg; read back: True (provisioning state 'Succeeded').
[prereq] [oer-s116c] Setup changes nothing outside the prefix, so nothing is restored by -Teardown; it removes the test objects.
[oer-s116c] Exit code: 0
[oer-s116c] == Initialize-OerS116cPrereq.ps1 -Unattended
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: CREATE. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] Baseline: raw\s116c\baseline-s116c.json exists already (written by an earlier run); it is never overwritten.
[prereq] [oer-s116c] Found oer-s116c-grp (securityEnabled True, mailEnabled False); nothing created.
[prereq] [oer-s116c] Found oer-s116c-rg (location 'swedencentral', purpose tag 'Omnicit.EntraRBAC live verification (oer-s116c)'); nothing created.
[prereq] [oer-s116c] Setup changes nothing outside the prefix, so nothing is restored by -Teardown; it removes the test objects.
[oer-s116c] Exit code: 0
[oer-s116c] The created ids are recorded: group True
```

## M. The measurement behind the decision (reads only)

### M.1. The subscription's tenantId, read as oer-live-cc

- [x] **M.1** Subscriptions - List and Subscriptions - Get (api-version `2022-12-01`) answer for the test subscription with a `tenantId` that equals the session's `TokenTenantId`, no `homeTenantId`, and an empty `managedByTenants`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$Token = & (Get-Module -Name Omnicit.EntraRBAC) { [string]$script:_OERAuthState.TokenTenantId }
$GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
Write-OerLiveStep "The session's TokenTenantId is a GUID: $($Token -match $GuidPattern); it is the configured test tenant: $($Token -eq $Cfg.TenantId)"
$Show = {
    param($Label, $S)
    Write-OerLiveStep ("{0}: the test subscription: {1}; keys: {2}; tenantId is a GUID: {3}; tenantId equals the session's TokenTenantId: {4}; homeTenantId present: {5}; managedByTenants: {6}" -f $Label,
        ([string]$S.subscriptionId -eq $Cfg.SubscriptionId), ((@($S.PSObject.Properties.Name) | Sort-Object) -join ','), ([string]$S.tenantId -match $GuidPattern),
        ([string]$S.tenantId -eq $Token), ($null -ne $S.PSObject.Properties['homeTenantId']), @($S.managedByTenants | Where-Object { $null -ne $_ }).Count)
}
$L = Invoke-OerLiveArm -All -Path '/subscriptions?api-version=2022-12-01'
Write-OerLiveStep "Subscriptions - List: Ok=$($L.Ok) Status=$($L.Status) Code=$($L.Code) Count=$(@($L.Body.value | Where-Object { $null -ne $_ }).Count)"
foreach ($S in @($L.Body.value | Where-Object { $null -ne $_ })) { & $Show 'Listed' $S }
$G = Invoke-OerLiveArm -Path "$SubScope`?api-version=2022-12-01"
Write-OerLiveStep "Subscriptions - Get: Ok=$($G.Ok) Status=$($G.Status) Code=$($G.Code)"
if ($G.Ok) { & $Show 'Get' $G.Body }
Disconnect-OerLive
```

**Expect:** `TokenTenantId is a GUID: True; it is the configured test tenant: True`; the list `Ok=True`
with one subscription, the test subscription; for the list row and the Get: `tenantId is a GUID: True`,
`tenantId equals the session's TokenTenantId: True`, `homeTenantId present: False`, `managedByTenants: 0`,
and keys that include `tenantId`, `managedByTenants` and `subscriptionId`.
**Failure looks like:** a `tenantId` missing or unequal to the session's tenant (the owner's premise,
Ruling R-1 in `rationale.md#home-tenant-subscriptions`, would then be wrong), or a 401/403 (STOP).

Result: 2026-10-18 00:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. TokenTenantId is a GUID and the configured test tenant. Subscriptions - List (api-version 2022-12-01) answers 200 with one subscription, the test subscription; the list row and Subscriptions - Get carry the same keys (authorizationSource, displayName, id, managedByTenants, state, subscriptionId, subscriptionPolicies, tenantId), a tenantId that is a GUID and equals the session's TokenTenantId, no homeTenantId, and managedByTenants empty -- as measured in DEL 1 (2026-10-15), so Ruling R-1's field is the one ARM returns. Leak check: 0 hits.

Console, redacted (M.1):
Runner: check M.1; child exit code 0; 5 s; run at 2026-10-18 00:55 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] The session's TokenTenantId is a GUID: True; it is the configured test tenant: True
[oer-s116c] Subscriptions - List: Ok=True Status=200 Code= Count=1
[oer-s116c] Listed: the test subscription: True; keys: authorizationSource,displayName,id,managedByTenants,state,subscriptionId,subscriptionPolicies,tenantId; tenantId is a GUID: True; tenantId equals the session's TokenTenantId: True; homeTenantId present: False; managedByTenants: 0
[oer-s116c] Subscriptions - Get: Ok=True Status=200 Code=
[oer-s116c] Get: the test subscription: True; keys: authorizationSource,displayName,id,managedByTenants,state,subscriptionId,subscriptionPolicies,tenantId; tenantId is a GUID: True; tenantId equals the session's TokenTenantId: True; homeTenantId present: False; managedByTenants: 0
```

### M.2. A subscription the identity cannot see

- [x] **M.2** A GET of a made-up subscription, and a role assignment read at a resource group in it, answer 404 `SubscriptionNotFound`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$MadeUp = New-S116cMadeUpSubscriptionId
$G = Invoke-OerLiveArm -Path "/subscriptions/$MadeUp`?api-version=2022-12-01"
Write-OerLiveStep "GET of a made-up subscription: Ok=$($G.Ok) Status=$($G.Status) Code=$($G.Code)"
$Filter = [uri]::EscapeDataString('atScope()')
$A = Invoke-OerLiveArm -Path "/subscriptions/$MadeUp/resourceGroups/$Rg/providers/Microsoft.Authorization/roleAssignments?`$filter=$Filter&api-version=2022-04-01"
Write-OerLiveStep "Role assignments at a resource group of it: Ok=$($A.Ok) Status=$($A.Status) Code=$($A.Code)"
Disconnect-OerLive
```

**Expect:** both `Ok=False Status=404 Code=SubscriptionNotFound`.
**Failure looks like:** a 200 (the made-up id exists: run again, a new id is drawn), or a 401/403 (STOP).

Result: 2026-10-18 00:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. A GET of a made-up subscription (a new random id) and a role assignment read at a resource group in it both answer Ok=False Status=404 Code=SubscriptionNotFound. Leak check: 0 hits.

Console, redacted (M.2):
Runner: check M.2; child exit code 0; 6 s; run at 2026-10-18 00:56 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] GET of a made-up subscription: Ok=False Status=404 Code=SubscriptionNotFound
[oer-s116c] Role assignments at a resource group of it: Ok=False Status=404 Code=SubscriptionNotFound
```

### M.3. The owner's verdicts, in the module's scope

- [x] **M.3** `Get-OERSubscriptionHomeTenant`, called in the module's scope with one cache, decides the test subscription `Home` with one read, its resource group and its id in upper case from the cache, a management group and the root scope `NoSubscription` with no request, and a made-up subscription `Undecided` with the read's own `SubscriptionNotFound`, read once. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$MadeUp = New-S116cMadeUpSubscriptionId
$Cases = @(
    , @('the test subscription', $SubScope)
    , @("the resource group $Rg in it", $RgScope)
    , @('the test subscription in upper case, sub: form', "sub:$($Cfg.SubscriptionId.ToUpperInvariant())")
    , @('a management group named in the document syntax', 'mg:oer-s116c-none')
    , @('the root scope', '/')
    , @('a made-up subscription', "/subscriptions/$MadeUp")
    , @("the resource group $Rg in the made-up subscription", "/subscriptions/$MadeUp/resourceGroups/$Rg")
)
$Module = Get-Module -Name Omnicit.EntraRBAC
$Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($Case in $Cases) {
    Start-S116cCount
    $V = & $Module { param($S, $C) Get-OERSubscriptionHomeTenant -Scope $S -Cache $C } $Case[1] $Cache
    $Sent = $global:S116cArm.Count
    Stop-S116cCount
    $Rec = if ($V.ErrorRecord) { ([string]$V.ErrorRecord.FullyQualifiedErrorId -split ',')[0] } else { 'none' }
    Write-OerLiveStep ("{0}: Verdict {1}; Azure Resource Manager requests {2}; record {3}; home tenant equals the session's: {4}" -f $Case[0], $V.Verdict, $Sent, $Rec, ($null -ne $V.HomeTenantId -and $V.HomeTenantId -eq $V.SessionTenantId))
}
Write-OerLiveStep "Cache entries: $($Cache.Count)"
Disconnect-OerLive
```

**Expect:** the test subscription `Home`, 1 request, record `none`, home tenant equal `True`; its resource
group and the upper-case `sub:` form `Home` with 0 requests; the management group and the root scope
`NoSubscription` with 0 requests; the made-up subscription `Undecided` with 1 request and record
`SubscriptionNotFound`; its resource group `Undecided`, 0 requests, `SubscriptionNotFound`; 2 cache entries.
**Failure looks like:** a second read of a subscription, a request for the management group or the root
scope, or `Home` for the made-up subscription.

Result: 2026-10-18 00:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. With one cache: the test subscription Home with 1 Azure Resource Manager request, no record, home tenant equal True; its resource group and the upper-case sub: form Home with 0 requests (from the cache); mg:oer-s116c-none and the root scope NoSubscription with 0 requests; a made-up subscription Undecided with 1 request and the read's own SubscriptionNotFound; its resource group Undecided with 0 requests and SubscriptionNotFound (the failure is cached); 2 cache entries. Leak check: 0 hits.

Console, redacted (M.3):
Runner: check M.3; child exit code 0; 6 s; run at 2026-10-18 00:56 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] the test subscription: Verdict Home; Azure Resource Manager requests 1; record none; home tenant equals the session's: True
[oer-s116c] the resource group oer-s116c-rg in it: Verdict Home; Azure Resource Manager requests 0; record none; home tenant equals the session's: True
[oer-s116c] the test subscription in upper case, sub: form: Verdict Home; Azure Resource Manager requests 0; record none; home tenant equals the session's: True
[oer-s116c] a management group named in the document syntax: Verdict NoSubscription; Azure Resource Manager requests 0; record none; home tenant equals the session's: False
[oer-s116c] the root scope: Verdict NoSubscription; Azure Resource Manager requests 0; record none; home tenant equals the session's: False
[oer-s116c] a made-up subscription: Verdict Undecided; Azure Resource Manager requests 1; record SubscriptionNotFound; home tenant equals the session's: False
[oer-s116c] the resource group oer-s116c-rg in the made-up subscription: Verdict Undecided; Azure Resource Manager requests 0; record SubscriptionNotFound; home tenant equals the session's: False
[oer-s116c] Cache entries: 2
```

### M.4. An identity with no Azure role (oer-live-cc-noperm)

- [x] **M.4** As `oer-live-cc-noperm`, which holds no Azure role, Subscriptions - List and Get answer as measured here; the owner then decides the test subscription `Undecided` with that answer as itself, and `Invoke-OERStructure -WhatIf` reports the step's two entries `Failed` with it and sends nothing else. #type/subtask

An identity that cannot read its subscription cannot be shown to be in the session's tenant, so under A19
its Azure entries are refused with the read's own error. This identity holds no role at all; one whose
role covers only a resource group cannot be built here without changing an identity's roles, which this
checklist never does (C.1 asks the operator).

```powershell
Connect-OerLive -Arm -NoPerm
Start-S116cNoPrompt
$L = Invoke-OerLiveArm -All -Path '/subscriptions?api-version=2022-12-01'
Write-OerLiveStep "Subscriptions - List: Ok=$($L.Ok) Status=$($L.Status) Code=$($L.Code) Count=$(if ($L.Ok) { @($L.Body.value | Where-Object { $null -ne $_ }).Count } else { 'n/a' })"
$G = Invoke-OerLiveArm -Path "$SubScope`?api-version=2022-12-01"
Write-OerLiveStep "Subscriptions - Get of the test subscription: Ok=$($G.Ok) Status=$($G.Status) Code=$($G.Code)"
$Module = Get-Module -Name Omnicit.EntraRBAC
$V = & $Module { param($S) Get-OERSubscriptionHomeTenant -Scope $S } $RgScope
Write-OerLiveStep "Owner verdict for $Rg`: $($V.Verdict); record $(if ($V.ErrorRecord) { ([string]$V.ErrorRecord.FullyQualifiedErrorId -split ',')[0] } else { 'none' })"
$Path = Join-Path $Raw 'docs\home.json'
if (-not (Test-Path -LiteralPath $Path)) {
    $Doc = [ordered]@{
        version                = '1.0'
        roleAssignments        = @([ordered]@{ scope = $RgScope; role = 'Reader'; principal = $Grp; principalType = 'Group' })
        roleManagementPolicies = @([ordered]@{ scope = $RgScope; role = 'Reader' })
    }
    $Path = Save-S116cDocument -Name 'home' -Document $Doc
}
Start-S116cCount
$E = $null
$Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Requests in the test subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $Cfg.SubscriptionId), of them reads of the subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId)"
Stop-S116cCount
Show-S116cRows -Rows $Rows
Show-S116cErrors -Errors $E
Disconnect-OerLive
```

**Expect:** the identity check passes as `oer-live-cc-noperm`; the list and the Get answer whatever this
identity is given -- recorded, not prescribed (an empty list and a refused or not-found Get are both
possible); when the Get is refused, the verdict is `Undecided` with that answer's code as its record, and in
the plan one request in the test subscription (its read), both rows `Failed`, the errors written by
`Invoke-OERStructure` itself that same code twice, and `writes: 0`. When the Get answers 200, the verdict is
`Home` and the rows go on to the role assignment and policy reads, which this identity is refused.
**Failure looks like:** a write, or a role assignment or policy read after a refused subscription read.

Result: 2026-10-18 00:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed (recorded, as the check asks). As oer-live-cc-noperm the identity check passed; Subscriptions - List answers 200 with 0 subscriptions, and Subscriptions - Get of the test subscription answers 403 AuthorizationFailed. The owner decides oer-s116c-rg Undecided with that AuthorizationFailed as its record. Invoke-OERStructure -WhatIf: 0 token requests, 0 Microsoft Graph requests, 1 Azure Resource Manager request (the read of the test subscription), 0 writes, 0 role assignment and 0 role policy reads; both rows Failed with the failed read as itself; the records Invoke-OERStructure wrote itself AuthorizationFailed x2 (the other records in -ErrorVariable are the inner layers' copies). So an identity that cannot read its subscription gets its Azure entries refused with the read's own error, as Ruling R-18 records. Leak check: 0 hits.

Console, redacted (M.4):
Runner: check M.4; child exit code 0; 6 s; run at 2026-10-18 00:56 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: app name in the session is oer-live-cc-noperm: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc-noperm: identity check passed: True
[oer-s116c] Subscriptions - List: Ok=True Status=200 Code= Count=0
[oer-s116c] Subscriptions - Get of the test subscription: Ok=False Status=403 Code=AuthorizationFailed
[oer-s116c] Owner verdict for oer-s116c-rg: Undecided; record AuthorizationFailed
[oer-s116c] token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests in the test subscription: 1, of them reads of the subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000001' failed: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000002' with object id '00000000-0000-0000-0000-000000000003' does not have authorization to perform action 'Microsoft.Resources/subscriptions/read' over scope '/subscriptions/00000000-0000-0000-0000-000000000001' or the scope is invalid. If access was recently granted, please refresh your credentials; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000001' failed: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000002' with object id '00000000-0000-0000-0000-000000000003' does not have authorization to perform action 'Microsoft.Resources/subscriptions/read' over scope '/subscriptions/00000000-0000-0000-0000-000000000001' or the scope is invalid. If access was recently granted, please refresh your credentials; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, AuthorizationFailed x5; written by Invoke-OERStructure itself: AuthorizationFailed x2
```

## 1. Exports of the test subscription as oer-live-cc

### 1.1. An export of the own subscription is decided with one read

- [x] **1.1** An export with `-Scope` the test subscription decides it `Home` with one read of the subscription, warns about no other tenant's or undecided subscription, names nothing `subscriptionHomeTenant` in `IncompleteReads`, and its README section for another tenant's subscriptions says `None.`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
Start-S116cCount
$Out = Join-Path $Raw 'export-branch'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Reads of the test subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId)"
Save-S116cRequests -Name 'requests-export-branch'
Stop-S116cCount
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count); naming subscriptionHomeTenant: $(@($Bundle.IncompleteReads | Where-Object { [string]$_ -like 'subscriptionHomeTenant*' }).Count); SkippedScopes: $(@($Bundle.SkippedScopes).Count)"
Write-OerLiveStep "Errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Write-OerLiveStep "Warnings about another tenant's subscriptions: $(@($ExportWarnings | Where-Object { [string]$_ -like '*whose home tenant is another tenant*' }).Count); about undecided subscriptions: $(@($ExportWarnings | Where-Object { [string]$_ -like 'Could not tell whether*' }).Count)"
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
$Section = @(Get-S116cReadmeSection -Text $Readme -Heading 'Subscriptions delegated from another tenant (not read)')
Write-OerLiveStep "README section 'Subscriptions delegated from another tenant (not read)': $($Section.Count -gt 0); says None: $([bool]($Section -match '^None\.'))"
Write-OerLiveStep "README marks no delegation as managed by this tenant: $(-not $Readme.Contains('managed by this tenant'))"
Disconnect-OerLive
```

**Expect:** `Reads of the test subscription itself: 1`; no subscription list read (`subscription list
reads: 0`); `writes: 0` for both services and `token requests: 0`; no `subscriptionHomeTenant` entry,
no error, and no warning about another tenant's or an undecided subscription; the README section there
and saying `None.`.
**Failure looks like:** 0 or 2 reads of the subscription, a write, a token request, an
`InventoryPartial` naming the subscription, or the section missing.

Result: 2026-10-18 00:59 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. The export with -Scope the test subscription read the subscription itself exactly once and listed no subscriptions (subscription list reads: 0); 0 token requests and 0 writes for both services (334 Microsoft Graph and 11 Azure Resource Manager requests, all reads); no IncompleteReads entry, none naming subscriptionHomeTenant, no SkippedScopes, no error, and no warning about another tenant's or an undecided subscription; the bundle README carries the section 'Subscriptions delegated from another tenant (not read)' saying None., and marks no delegation as managed by this tenant. Leak check: 0 hits.

Console, redacted (1.1):
Runner: check 1.1; child exit code 0; 114 s; run at 2026-10-18 00:57 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 334, writes: 0; Azure Resource Manager requests: 11, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 1; role policy reads: 0
[oer-s116c] Reads of the test subscription itself: 1
[oer-s116c] IncompleteReads: 0; naming subscriptionHomeTenant: 0; SkippedScopes: 0
[oer-s116c] Errors:
[oer-s116c] Warnings about another tenant's subscriptions: 0; about undecided subscriptions: 0
[oer-s116c] README section 'Subscriptions delegated from another tenant (not read)': True; says None: True
[oer-s116c] README marks no delegation as managed by this tenant: True
```

### 1.2. inventory.json is the same as main's, and the export sends one request more

- [x] **1.2** The same export with `main`'s source (`cd7e6a3`, loaded in dev mode from a `git archive` copy under `raw\s116c\`) writes the same set of files and an `inventory.json` and per-area files equal to this branch's, and this branch sent exactly one request more: the read of the test subscription. #type/subtask

```powershell
$Src = Join-Path $Raw 'main-src'
if (-not (Test-Path -LiteralPath (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1'))) {
    $Zip = Join-Path $Raw 'main-src.zip'
    git -C $Cfg.Repo archive --format=zip -o $Zip $MainCommit source
    Expand-Archive -LiteralPath $Zip -DestinationPath $Src -Force
    Remove-Item -LiteralPath $Zip
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Write-OerLiveStep "main's source is loaded (dev mode, no home tenant owner): $(-not (Get-Command -Name Get-OERSubscriptionHomeTenant -ErrorAction SilentlyContinue)) and $([bool](Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith($Src, [System.StringComparison]::OrdinalIgnoreCase))"
Connect-OerLive -Arm
Start-S116cNoPrompt
Start-S116cCount
$Out = Join-Path $Raw 'export-main'
$null = New-Item -ItemType Directory -Path $Out -Force
$MainBundle = Export-OERInventory -OutputPath $Out -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable MainErrors 3>$null
Write-OerLiveStep "main: $(Get-S116cSent)"
$MainArm = @($global:S116cArm); $MainGraph = @($global:S116cGraph)
Stop-S116cCount
Disconnect-OerLive
$BranchReq = Get-Content -LiteralPath (Join-Path $Raw 'requests-export-branch.json') -Raw | ConvertFrom-Json
$Diff = {
    param([string[]]$A, [string[]]$B)
    # The entries of A that B does not hold, counted as a multiset.
    $Left = [System.Collections.Generic.List[string]]::new([string[]]@($B))
    foreach ($X in $A) { if (-not $Left.Remove($X)) { $X } }
}
Write-OerLiveStep "Azure Resource Manager requests only in this branch's export: $((@(& $Diff @($BranchReq.Arm) $MainArm)) -join ', '); only in main's: $((@(& $Diff $MainArm @($BranchReq.Arm))) -join ', ')"
Write-OerLiveStep "Microsoft Graph requests only in this branch's export: $(@(& $Diff @($BranchReq.Graph) $MainGraph).Count); only in main's: $(@(& $Diff $MainGraph @($BranchReq.Graph)).Count)"
$Branch = Get-S116cBundle -Name 'export-branch'
$Main = Get-Item -LiteralPath $MainBundle.BundlePath
$BranchFiles = @(Get-ChildItem -LiteralPath $Branch.FullName -File | ForEach-Object Name | Sort-Object)
$MainFiles = @(Get-ChildItem -LiteralPath $Main.FullName -File | ForEach-Object Name | Sort-Object)
Write-OerLiveStep "Files only in this branch's bundle: $(@($BranchFiles | Where-Object { $MainFiles -notcontains $_ }) -join ', '); only in main's: $(@($MainFiles | Where-Object { $BranchFiles -notcontains $_ }) -join ', ')"
foreach ($Name in @($MainFiles | Where-Object { $_ -like '*.json' -and $_ -ne 'schema.json' })) {
    $Same = (Get-S116cFileCanonical -Path (Join-Path $Branch.FullName $Name)) -ceq (Get-S116cFileCanonical -Path (Join-Path $Main.FullName $Name))
    Write-OerLiveStep "$Name equal: $Same"
}
Write-OerLiveStep "schema.json equal, line endings aside: $((Get-Content -LiteralPath (Join-Path $Branch.FullName 'schema.json') -Raw).Replace("`r", '') -ceq (Get-Content -LiteralPath (Join-Path $Main.FullName 'schema.json') -Raw).Replace("`r", ''))"
Write-OerLiveStep "main's errors: $(@($MainErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
```

**Expect:** main's source loaded (`True and True`); the only Azure Resource Manager request only in this
branch's export is `GET /subscriptions/` followed by the test subscription's id, and none is only in
main's; no Microsoft Graph request only in either; no file only in one bundle; every JSON file
`equal: True` -- `inventory.json` and every per-area file, the roster and the hierarchy, with arrays
compared without regard to order -- and `schema.json` equal with its line endings aside (the build writes
it with CRLF, the archived source keeps the repository's LF).
**Failure looks like:** `inventory.json equal: False` (the branch changed the apply document), another
request only in one export, or a file only in one bundle. A difference in a file that reads live state can
also mean the tenant changed between the two exports: run 1.1 and 1.2 again before reading it as a defect.

Result: 2026-10-18 01:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. main's source (cd7e6a3, dev mode from a git archive copy) was loaded (True and True). The only Azure Resource Manager request only in this branch's export is GET /subscriptions/ and the test subscription's id (branch 11, main 10), none only in main's; no Microsoft Graph request only in either (334 each); no file only in one bundle; every JSON file equal (inventory.json and every per-area file, the roster and the hierarchy, arrays compared without regard to order), and schema.json equal with its line endings aside; no error in either export. Leak check: 0 hits.

Console, redacted (1.2):
Runner: check 1.2; child exit code 0; 117 s; run at 2026-10-18 00:59 UTC.
[oer-s116c] main's source is loaded (dev mode, no home tenant owner): True and True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] main: token requests: 0; Microsoft Graph requests: 334, writes: 0; Azure Resource Manager requests: 10, writes: 0; subscription reads: 0; subscription list reads: 0; role assignment reads: 1; role policy reads: 0
[oer-s116c] Azure Resource Manager requests only in this branch's export: GET /subscriptions/00000000-0000-0000-0000-000000000001; only in main's:
[oer-s116c] Microsoft Graph requests only in this branch's export: 0; only in main's: 0
[oer-s116c] Files only in this branch's bundle: ; only in main's:
[oer-s116c] accessPackages.json equal: True
[oer-s116c] accessReviews.json equal: True
[oer-s116c] administrativeUnits.json equal: True
[oer-s116c] azurePimEligibility.json equal: True
[oer-s116c] catalogs.json equal: True
[oer-s116c] directoryRoleAssignments.json equal: True
[oer-s116c] directoryRoleManagementPolicies.json equal: True
[oer-s116c] groups.json equal: True
[oer-s116c] groupsRoster.json equal: True
[oer-s116c] inventory.json equal: True
[oer-s116c] lighthouseDelegations.json equal: True
[oer-s116c] roleAssignments.json equal: True
[oer-s116c] roleManagementPolicies.json equal: True
[oer-s116c] scopeHierarchy.json equal: True
[oer-s116c] schema.json equal, line endings aside: True
[oer-s116c] main's errors:
```

### 1.3. An export -Scope in a subscription the identity cannot see is partial and reads nothing there

- [x] **1.3** An export with `-Scope` a made-up subscription (Azure sections only) reads the subscription once (404), warns once that it could not tell its tenant, names it `subscriptionHomeTenant at` the scope in `IncompleteReads`, raises `InventoryPartial`, lists it in the README under what could not be read, and sends no other request at it. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$MadeUp = New-S116cMadeUpSubscriptionId
Start-S116cCount
$Out = Join-Path $Raw 'export-made-up'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Scope "/subscriptions/$MadeUp" -Include RoleAssignments, RoleManagementPolicies -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Requests at the made-up subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $MadeUp), of them reads of the subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $MadeUp); Lighthouse reads: $(Get-S116cArmCount -Kind Lighthouse)"
Stop-S116cCount
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count); $((@($Bundle.IncompleteReads) | ForEach-Object { [string]$_ }) -join ' | ')"
Write-OerLiveStep "Errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
foreach ($W in @($ExportWarnings)) { Write-OerLiveStep "Warning: $W" }
foreach ($Name in 'roleAssignments.json', 'roleManagementPolicies.json', 'scopeHierarchy.json') {
    $File = Join-Path $Bundle.BundlePath $Name
    Write-OerLiveStep "${Name}: $(if (Test-Path -LiteralPath $File) { $T = (Get-Content -LiteralPath $File -Raw).Trim(); if ($T.Length -le 200) { $T } else { "$($T.Length) characters" } } else { 'not written' })"
}
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
Write-OerLiveStep "README lists it with the label 'Azure subscription whose tenant could not be read': $($Readme.Contains('Azure subscription whose tenant could not be read'))"
Disconnect-OerLive
```

**Expect:** one request at the made-up subscription, and it is the read of the subscription itself; no
role assignment, role policy or Lighthouse read there; `writes: 0`; one `IncompleteReads` entry,
`subscriptionHomeTenant at /subscriptions/` and the made-up id; the error `InventoryPartial`; one warning
starting `Could not tell whether 1 subscription(s) belong to this tenant`; nothing from the subscription in
the files; the README label `True`.
**Failure looks like:** a role assignment or policy read at the made-up subscription, a complete export,
or the subscription named as another tenant's.

Result: 2026-10-18 01:02 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. One request at the made-up subscription, and it is the read of the subscription itself (404 SubscriptionNotFound); no role assignment, role policy or Lighthouse read; 0 Microsoft Graph requests, 0 writes, 0 token requests. One IncompleteReads entry, subscriptionHomeTenant at /subscriptions/ and the made-up id; the error InventoryPartial; one warning starting 'Could not tell whether 1 subscription(s) belong to this tenant' with the failed read as its cause; roleAssignments.json and roleManagementPolicies.json empty and scopeHierarchy.json with no subscription; the README label True. The -ErrorVariable also holds three SubscriptionNotFound records and one RuntimeException; a supplement run of the same export (1.3x, its own made-up id) named each record's writer: the only record Export-OERInventory wrote itself is InventoryPartial, and the three SubscriptionNotFound records name no command (the inner layers' copies of the failed read). Leak check: 0 hits for both runs.

Console, redacted (1.3):
Runner: check 1.3; child exit code 0; 6 s; run at 2026-10-18 01:01 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests at the made-up subscription: 1, of them reads of the subscription itself: 1; Lighthouse reads: 0
[oer-s116c] IncompleteReads: 1; subscriptionHomeTenant at /subscriptions/00000000-0000-0000-0000-000000000004
[oer-s116c] Errors: SubscriptionNotFound, SubscriptionNotFound, , SubscriptionNotFound, InventoryPartial
[oer-s116c] Warning: Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '/subscriptions/00000000-0000-0000-0000-000000000004' (the read of subscription '00000000-0000-0000-0000-000000000004' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000004' could not be found.)
[oer-s116c] roleAssignments.json: []
[oer-s116c] roleManagementPolicies.json: []
[oer-s116c] scopeHierarchy.json: {
  "managementGroups": [],
  "subscriptions": []
}
[oer-s116c] README lists it with the label 'Azure subscription whose tenant could not be read': True

Console, redacted (1.3x):
Runner: check 1.3x; child exit code 0; 6 s; run at 2026-10-18 01:02 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Record: id SubscriptionNotFound; written by (no command named)
[oer-s116c] Record: id SubscriptionNotFound; written by (no command named)
[oer-s116c] Record: not an ErrorRecord (RuntimeException)
[oer-s116c] Record: id SubscriptionNotFound; written by (no command named)
[oer-s116c] Record: id InventoryPartial; written by Export-OERInventory
[oer-s116c] Records Export-OERInventory wrote itself: InventoryPartial
[oer-s116c] Warnings: 1
```

### 1.3b. An export -Scope with '..' segments is not read at all

- [x] **1.3b** An export with `-Scope` written as the test subscription followed by `/../../subscriptions/` and a made-up id -- a spelling a document could not declare, which the request would send to the made-up subscription -- reads nothing at either subscription, names the scope `subscriptionHomeTenant at` the scope as given in `IncompleteReads`, and raises `InventoryPartial`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
$MadeUp = New-S116cMadeUpSubscriptionId
$Crafted = "$SubScope/../../subscriptions/$MadeUp"
Start-S116cCount
$Out = Join-Path $Raw 'export-crafted'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Scope $Crafted -Include RoleAssignments, RoleManagementPolicies -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Requests in the test subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $Cfg.SubscriptionId); at the made-up subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $MadeUp)"
Stop-S116cCount
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count); naming the scope as given: $(@($Bundle.IncompleteReads | Where-Object { [string]$_ -ceq "subscriptionHomeTenant at $Crafted" }).Count)"
Write-OerLiveStep "Errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
foreach ($W in @($ExportWarnings)) { Write-OerLiveStep "Warning: $W" }
Disconnect-OerLive
```

**Expect:** `Azure Resource Manager requests: 0`; no request in either subscription; one `IncompleteReads`
entry, naming the scope as given; the error `InventoryPartial`; one warning starting `Could not tell whether
1 subscription(s) belong to this tenant`; `writes: 0`.
**Failure looks like:** any request at the made-up subscription (the walk followed the `..` segments), or a
read of the test subscription that rates the scope its own.

Result: 2026-10-18 01:02 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. The -Scope written as the test subscription followed by /../../subscriptions/ and a made-up id sent 0 Azure Resource Manager requests (none in either subscription), 0 Microsoft Graph requests and 0 writes; one IncompleteReads entry naming the scope exactly as given; the error InventoryPartial; one warning starting 'Could not tell whether 1 subscription(s) belong to this tenant', whose cause names the spelling problem (DotSegment) and says nothing was resolved or read for it. Leak check: 0 hits.

Console, redacted (1.3b):
Runner: check 1.3b; child exit code 0; 5 s; run at 2026-10-18 01:01 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0; subscription reads: 0; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests in the test subscription: 0; at the made-up subscription: 0
[oer-s116c] IncompleteReads: 1; naming the scope as given: 1
[oer-s116c] Errors: InventoryPartial
[oer-s116c] Warning: Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '/subscriptions/00000000-0000-0000-0000-000000000001/../../subscriptions/00000000-0000-0000-0000-000000000005' (scope '/subscriptions/00000000-0000-0000-0000-000000000001/../../subscriptions/00000000-0000-0000-0000-000000000005' is written in a spelling no structure document can declare (DotSegment), so the path a request sends for it may name another scope than its text; nothing was resolved or read for it)
```

### 1.4. A walk without -Scope decides the listed subscription from the list

- [x] **1.4** An export of the role assignments without `-Scope` lists the subscriptions once, walks the test subscription with no read of the subscription itself, and warns about no other tenant's or undecided subscription. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S116cNoPrompt
Start-S116cCount
$Out = Join-Path $Raw 'export-walk'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Include RoleAssignments -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116cSent)
Stop-S116cCount
$SubId = [regex]::Escape($Cfg.SubscriptionId)
Write-OerLiveStep "Scopes enumerated (a count): $($Bundle.ScopesEnumerated); scopes read: $($Bundle.ScopeCount); role assignment reads at the test subscription: $(@($global:S116cArm | Where-Object { $_ -match "^GET /subscriptions/$SubId/providers/Microsoft\.Authorization/roleAssignments" }).Count); SkippedScopes: $((@($Bundle.SkippedScopes) | ForEach-Object { [string]$_ }) -join ' | ')"
Write-OerLiveStep "IncompleteReads naming subscriptionHomeTenant: $(@($Bundle.IncompleteReads | Where-Object { [string]$_ -like 'subscriptionHomeTenant*' }).Count)"
Write-OerLiveStep "Errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Write-OerLiveStep "Warnings about another tenant's subscriptions: $(@($ExportWarnings | Where-Object { [string]$_ -like '*whose home tenant is another tenant*' }).Count); about undecided subscriptions: $(@($ExportWarnings | Where-Object { [string]$_ -like 'Could not tell whether*' }).Count)"
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
Write-OerLiveStep "README section for another tenant's subscriptions says None: $([bool](@(Get-S116cReadmeSection -Text $Readme -Heading 'Subscriptions delegated from another tenant (not read)') -match '^None\.'))"
Disconnect-OerLive
```

**Expect:** `subscription list reads: 1` and `subscription reads: 0`; the test subscription walked --
`ScopesEnumerated` and `ScopeCount` are counts, here `1` each, and one role assignment read at it;
no `subscriptionHomeTenant` entry and no warning about another tenant's or an undecided subscription; the
README section says `None.`; `writes: 0`. The management group listing is refused for this identity
(measured in earlier steps), so `SkippedScopes` may name it and the export may be partial for that reason
alone -- behaviour that is `main`'s and not this branch's.
**Failure looks like:** a read of the test subscription itself, a second list read, or the test
subscription left out.

Result: 2026-10-18 01:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed, after a correction of this check's own print line. The first run (01:02 UTC) printed 'Scopes enumerated include the test subscription: False': the line tested the bundle's ScopesEnumerated with -contains as if it were a list of scopes, but ScopesEnumerated is a count, on main and on this branch alike, so the line could never print True. The line now prints ScopesEnumerated and ScopeCount and counts the role assignment reads at the test subscription; the module was not changed. The run below: the subscriptions listed once (subscription list reads: 1) and the test subscription itself read 0 times; ScopesEnumerated 1, ScopeCount 1, and one role assignment read at the test subscription, so the walk decided it from the list and walked it; no subscriptionHomeTenant entry, and no warning about another tenant's or an undecided subscription; the README section says None.; 0 writes and 0 token requests. SkippedScopes names the refused management group listing, and the errors are that AuthorizationFailed and the InventoryPartial it causes, main's behaviour and not this branch's, as the check foresaw. Leak check: 0 hits.

Console, redacted (1.4):
Runner: check 1.4; child exit code 0; 10 s; run at 2026-10-18 01:03 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 12, writes: 0; subscription reads: 0; subscription list reads: 1; role assignment reads: 1; role policy reads: 0
[oer-s116c] Scopes enumerated (a count): 1; scopes read: 1; role assignment reads at the test subscription: 1; SkippedScopes: <management groups: the listing failed>
[oer-s116c] IncompleteReads naming subscriptionHomeTenant: 0
[oer-s116c] Errors: AuthorizationFailed, AuthorizationFailed, InventoryPartial
[oer-s116c] Warnings about another tenant's subscriptions: 0; about undecided subscriptions: 0
[oer-s116c] README section for another tenant's subscriptions says None: True
```

## 2. Apply on the test subscription as oer-live-cc

The document holds one role assignment (Reader for `oer-s116c-grp` at `oer-s116c-rg`, created in 2.2)
and one role management policy entry for Reader at `oer-s116c-rg` that declares no rule, so it reads the
live policy and changes nothing.

### 2.1. The plan checks the subscription once and plans as before

- [x] **2.1** `Test-OERStructure` accepts the document; `Invoke-OERStructure -WhatIf` reads the test subscription once, plans the role assignment, reports the policy `Unchanged` and writes nothing. #type/subtask

```powershell
$Doc = [ordered]@{
    version                = '1.0'
    roleAssignments        = @([ordered]@{ scope = $RgScope; role = 'Reader'; principal = $Grp; principalType = 'Group' })
    roleManagementPolicies = @([ordered]@{ scope = $RgScope; role = 'Reader' })
}
$Path = Save-S116cDocument -Name 'home' -Document $Doc
Connect-OerLive -Arm
Start-S116cNoPrompt
$V = Test-OERStructure -Path $Path
Write-OerLiveStep "Valid: $($V.Valid); findings: $(@($V.Errors).Count); Errors: $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
Start-S116cCount
$E = $null
$Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Reads of the test subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId)"
Stop-S116cCount
Show-S116cRows -Rows $Rows
Show-S116cErrors -Errors $E
Disconnect-OerLive
```

**Expect:** `Valid: True` with no Error; `Reads of the test subscription itself: 1`; the role assignment
row `Skipped` with `would create role assignment 'Reader' for 'oer-s116c-grp'`; the policy row
`Unchanged`, with at least one role policy read; `writes: 0`; `token requests: 0`; no error.
**Failure looks like:** a write, a `Failed` row, 0 or 2 reads of the subscription.

Result: 2026-10-18 01:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. Test-OERStructure: Valid True, no finding. Invoke-OERStructure -WhatIf read the test subscription itself exactly once, printed a What if: line for the role assignment, reported the role assignment row Skipped 'would create role assignment 'Reader' for 'oer-s116c-grp'' and the policy row Unchanged after one role policy read; 0 writes for both services, 0 token requests, no error. Leak check: 0 hits.

Console, redacted (2.1):
Runner: check 2.1; child exit code 0; 11 s; run at 2026-10-18 01:04 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] Valid: True; findings: 0; Errors: 0
What if: Performing the operation "Create role assignment 'Reader' for 'oer-s116c-grp'" on target "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg".
[oer-s116c] token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 6, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 1; role policy reads: 1
[oer-s116c] Reads of the test subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Skipped | would create role assignment 'Reader' for 'oer-s116c-grp' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Errors: none; written by Invoke-OERStructure itself: none
```

### 2.2. The real run creates the role assignment after the one check

- [x] **2.2** The real run reads the test subscription once, creates the role assignment (one write), keeps the policy `Unchanged`, and Azure Resource Manager then lists the assignment at `oer-s116c-rg`. #type/subtask

```powershell
$Path = Join-Path $Raw 'docs\home.json'
Connect-OerLive -Arm
Start-S116cNoPrompt
Start-S116cCount
$E = $null
$Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Reads of the test subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId)"
Stop-S116cCount
Show-S116cRows -Rows $Rows
Show-S116cErrors -Errors $E
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((@(Get-S116cAtScope) | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** `Reads of the test subscription itself: 1`; the role assignment row `Created`; the policy row
`Unchanged`; Azure Resource Manager `writes: 1`, a `PUT` of a role assignment at `oer-s116c-rg`; Microsoft
Graph `writes: 0`; no error; `oer-s116c-grp` listed at the resource group.
**Failure looks like:** a `Failed` row, a second write, or the assignment not listed (a `PrincipalNotFound`
right after the group was created is replication delay: run 2.2 again after a minute).

Result: 2026-10-18 01:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. The real run read the test subscription itself once, created the role assignment (row Created) with the run's only write, one Azure Resource Manager PUT of a role assignment at oer-s116c-rg, and kept the policy Unchanged; 0 Microsoft Graph writes, 0 token requests, no error; Azure Resource Manager then lists oer-s116c-grp at the resource group. Leak check: 0 hits.

Console, redacted (2.2):
Runner: check 2.2; child exit code 0; 15 s; run at 2026-10-18 01:04 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 8, writes: 1 (PUT /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000006); subscription reads: 1; subscription list reads: 0; role assignment reads: 1; role policy reads: 1
[oer-s116c] Reads of the test subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Created | created role assignment 'Reader' for 'oer-s116c-grp' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Errors: none; written by Invoke-OERStructure itself: none
[oer-s116c] Azure Resource Manager lists at oer-s116c-rg: oer-s116c-grp
```

### 2.3. The same document again writes nothing (G8)

- [x] **2.3** The same document run again, and once more with `-Prune`, reads the test subscription once per run and reports both rows `Unchanged`, with no write. #type/subtask

```powershell
$Path = Join-Path $Raw 'docs\home.json'
Connect-OerLive -Arm
Start-S116cNoPrompt
foreach ($Mode in 'Real', 'Real -Prune') {
    Start-S116cCount
    $E = $null
    if ($Mode -eq 'Real') { $Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    else { $Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -Prune -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    Write-OerLiveStep "== ${Mode}: $(Get-S116cSent)"
    Write-OerLiveStep "Reads of the test subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId)"
    Stop-S116cCount
    Show-S116cRows -Rows $Rows
    Show-S116cErrors -Errors $E
}
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((@(Get-S116cAtScope) | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** in both runs `Reads of the test subscription itself: 1`, both rows `Unchanged`, `writes: 0`
for both services and no error; `oer-s116c-grp` still listed at the resource group.
**Failure looks like:** a write, a `Created` or `Removed` row, or a second read of the subscription.

Result: 2026-10-18 01:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed (G8). The same document run again for real, and once more with -Prune: in both runs the test subscription itself was read once, both rows Unchanged, 0 writes for both services, no error; oer-s116c-grp is still listed at the resource group. Leak check: 0 hits.

Console, redacted (2.3):
Runner: check 2.3; child exit code 0; 16 s; run at 2026-10-18 01:04 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] == Real: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 6, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 1; role policy reads: 1
[oer-s116c] Reads of the test subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Errors: none; written by Invoke-OERStructure itself: none
[oer-s116c] == Real -Prune: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 6, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 1; role policy reads: 1
[oer-s116c] Reads of the test subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Errors: none; written by Invoke-OERStructure itself: none
[oer-s116c] Azure Resource Manager lists at oer-s116c-rg: oer-s116c-grp
```

## 3. Apply at a subscription the identity cannot see

### 3.1. Both entries are Failed with the read's own error, and nothing is read or written there

- [x] **3.1** A document with a role assignment at a resource group of a made-up subscription and a role management policy entry at `sub:` the same subscription: under `-WhatIf`, `-WhatIf -Prune`, a real run and a real run with `-Prune`, both rows are `Failed` with `SubscriptionNotFound` as itself, the subscription is read once per run, and nothing else is sent there. #type/subtask

```powershell
$MadeUp = New-S116cMadeUpSubscriptionId
$Doc = [ordered]@{
    version                = '1.0'
    roleAssignments        = @([ordered]@{ scope = "/subscriptions/$MadeUp/resourceGroups/$Rg"; role = 'Reader'; principal = $Grp; principalType = 'Group' })
    roleManagementPolicies = @([ordered]@{ scope = "sub:$MadeUp"; role = 'Reader' })
}
$Path = Save-S116cDocument -Name 'made-up' -Document $Doc
Connect-OerLive -Arm
Start-S116cNoPrompt
$V = Test-OERStructure -Path $Path
Write-OerLiveStep "Valid: $($V.Valid); Errors: $(@($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
foreach ($Mode in 'WhatIf', 'WhatIf -Prune', 'Real', 'Real -Prune') {
    $Splat = @{ Path = $Path; Include = @('RoleAssignments', 'RoleManagementPolicies'); ErrorAction = 'SilentlyContinue' }
    if ($Mode -like 'WhatIf*') { $Splat.WhatIf = $true } else { $Splat.Confirm = $false }
    if ($Mode -like '*-Prune') { $Splat.Prune = $true }
    Start-S116cCount
    $E = $null
    $Rows = Invoke-OERStructure @Splat -ErrorVariable E 3>$null
    Write-OerLiveStep "== ${Mode}: $(Get-S116cSent)"
    Write-OerLiveStep "Requests at the made-up subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $MadeUp), of them reads of the subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $MadeUp)"
    Stop-S116cCount
    Show-S116cRows -Rows $Rows
    Show-S116cErrors -Errors $E
}
Disconnect-OerLive
```

**Expect:** `Valid: True`; in every run one request at the made-up subscription, the read of the
subscription itself; `role assignment reads: 0` and `role policy reads: 0`; both rows `Failed`, each
Detail starting with the failed read of the subscription; the errors written by `Invoke-OERStructure`
itself `SubscriptionNotFound x2`; `writes: 0` for both services.
**Failure looks like:** a role assignment or policy read or write at the made-up subscription, a second
read of it, a row that is not `Failed`, or `SubscriptionTenantMismatch` (that id is for a subscription
that was read and is another tenant's, or that gave no tenant).

Result: 2026-10-18 01:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. Test-OERStructure: Valid True, no Error. Under -WhatIf, -WhatIf -Prune, a real run and a real run with -Prune: one request at the made-up subscription per run, the read of the subscription itself (one read serves both entries); 0 role assignment and 0 role policy reads, 0 Microsoft Graph requests, 0 writes for both services, 0 token requests; both rows Failed, each Detail starting with the failed read of the subscription; the records Invoke-OERStructure wrote itself SubscriptionNotFound x2 in every run (the other records in -ErrorVariable are the inner layers' copies); no SubscriptionTenantMismatch. Leak check: 0 hits.

Console, redacted (3.1):
Runner: check 3.1; child exit code 0; 6 s; run at 2026-10-18 01:05 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] Valid: True; Errors: 0
[oer-s116c] == WhatIf: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests at the made-up subscription: 1, of them reads of the subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000007/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ sub:00000000-0000-0000-0000-000000000007 | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, SubscriptionNotFound x5; written by Invoke-OERStructure itself: SubscriptionNotFound x2
[oer-s116c] == WhatIf -Prune: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests at the made-up subscription: 1, of them reads of the subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000007/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ sub:00000000-0000-0000-0000-000000000007 | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, SubscriptionNotFound x5; written by Invoke-OERStructure itself: SubscriptionNotFound x2
[oer-s116c] == Real: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests at the made-up subscription: 1, of them reads of the subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000007/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ sub:00000000-0000-0000-0000-000000000007 | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, SubscriptionNotFound x5; written by Invoke-OERStructure itself: SubscriptionNotFound x2
[oer-s116c] == Real -Prune: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 1, writes: 0; subscription reads: 1; subscription list reads: 0; role assignment reads: 0; role policy reads: 0
[oer-s116c] Requests at the made-up subscription: 1, of them reads of the subscription itself: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000007/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ sub:00000000-0000-0000-0000-000000000007 | Failed | the read of subscription '00000000-0000-0000-0000-000000000007' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000007' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, SubscriptionNotFound x5; written by Invoke-OERStructure itself: SubscriptionNotFound x2
```

### 3.2. A refused entry does not stop the document's own entries

- [x] **3.2** One document with the role assignment of 2.2 and the two made-up entries of 3.1, run for real with `-Prune`: the own row `Unchanged`, the two made-up rows `Failed`, each subscription read once, nothing written and nothing pruned. #type/subtask

```powershell
$MadeUp = New-S116cMadeUpSubscriptionId
$Doc = [ordered]@{
    version                = '1.0'
    roleAssignments        = @(
        [ordered]@{ scope = $RgScope; role = 'Reader'; principal = $Grp; principalType = 'Group' }
        [ordered]@{ scope = "/subscriptions/$MadeUp/resourceGroups/$Rg"; role = 'Reader'; principal = $Grp; principalType = 'Group' }
    )
    roleManagementPolicies = @([ordered]@{ scope = "sub:$MadeUp"; role = 'Reader' })
}
$Path = Save-S116cDocument -Name 'mixed' -Document $Doc
Connect-OerLive -Arm
Start-S116cNoPrompt
Start-S116cCount
$E = $null
$Rows = Invoke-OERStructure -Path $Path -Include RoleAssignments, RoleManagementPolicies -Prune -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue
Write-OerLiveStep (Get-S116cSent)
Write-OerLiveStep "Reads of the test subscription itself: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $Cfg.SubscriptionId); requests at the made-up subscription: $(Get-S116cArmCount -Kind Touching -SubscriptionId $MadeUp), of them reads of it: $(Get-S116cArmCount -Kind SubscriptionRead -SubscriptionId $MadeUp)"
Stop-S116cCount
Show-S116cRows -Rows $Rows
Show-S116cErrors -Errors $E
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((@(Get-S116cAtScope) | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** one read of the test subscription and one request at the made-up subscription (its read);
the row at `oer-s116c-rg` `Unchanged`, the two made-up rows `Failed`; `writes: 0` for both services; no
`Removed` row; `oer-s116c-grp` still listed at the resource group.
**Failure looks like:** a write, a `Removed` row, or the own row `Failed`.

Result: 2026-10-18 01:06 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed. One document with the role assignment of 2.2 and the two made-up entries, run for real with -Prune: one read of the test subscription and one request at the made-up subscription (its read); the row at oer-s116c-rg Unchanged and the two made-up rows Failed with SubscriptionNotFound as itself (written by Invoke-OERStructure itself x2); 0 writes for both services, no Removed row, 0 token requests; oer-s116c-grp still listed at the resource group. A refused entry does not stop the document's own entries. Leak check: 0 hits.

Console, redacted (3.2):
Runner: check 3.2; child exit code 0; 7 s; run at 2026-10-18 01:05 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 5, writes: 0; subscription reads: 2; subscription list reads: 0; role assignment reads: 1; role policy reads: 0
[oer-s116c] Reads of the test subscription itself: 1; requests at the made-up subscription: 1, of them reads of it: 1
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/oer-s116c-rg'
[oer-s116c] Row: roleAssignments | Reader -> oer-s116c-grp @ /subscriptions/00000000-0000-0000-0000-000000000008/resourceGroups/oer-s116c-rg | Failed | the read of subscription '00000000-0000-0000-0000-000000000008' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000008' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Row: roleManagementPolicies | Reader @ sub:00000000-0000-0000-0000-000000000008 | Failed | the read of subscription '00000000-0000-0000-0000-000000000008' failed: SubscriptionNotFound: The subscription '00000000-0000-0000-0000-000000000008' could not be found; the apply engine reads and writes a role assignment or a role management policy in a subscription only when it can show that the subscription belongs to this session's tenant, so none was read or written for this entry
[oer-s116c] Errors: (no id) x1, SubscriptionNotFound x5; written by Invoke-OERStructure itself: SubscriptionNotFound x2
[oer-s116c] Azure Resource Manager lists at oer-s116c-rg: oer-s116c-grp
```

## B. Proved offline (class B)

Each item is held by unit tests on this branch, run by `./build.ps1 -Tasks test`, with invented ids.

- **B.1 A subscription of another tenant in the export's walk.** `tests/Unit/Private/Get-OERSubscriptionHomeTenant.Tests.ps1`,
  Describe "Get-OERSubscriptionHomeTenant (BL-150, A19)" (the `Foreign` verdict, Contexts "the -Scope set"
  and "the -Subscription set"); `tests/Unit/Private/Resolve-OERInventoryScopeTree.Tests.ps1`, Context "only
  the home tenant's subscriptions are walked (BL-150, A19)" (a walk with an own and a foreign subscription:
  the foreign one is not walked, named and warned about once); `tests/Unit/Public/Export-OERInventory.Tests.ps1`,
  Describe "Export-OERInventory stays in the home tenant's subscriptions (BL-150, A19)" (the warning before
  the confirmation, the README section, nothing read from the subscription); and
  `tests/Unit/Private/Get-OERInventoryReadme.Tests.ps1` (the section's text and place).
- **B.2 An export `-Scope` in another tenant's subscription, one that cannot be resolved, and one spelled so
  the request would reach another path.** The same Describes, and the owner's Context "a scope spelled so
  that the request would not reach it as written (Ruling R-27)".
- **B.3 The engine's refusal of another tenant's subscription, with and without `-Prune`, under `-WhatIf`,
  and in a script with no `try`.** `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe
  "Invoke-OERStructure stays in the home tenant's subscriptions (BL-150, A19)" and its Context "in a script
  with no try above it"; `tests/Unit/Private/Sync-OERStructureRoleManagementPolicy.Tests.ps1`, Context "the
  scope the engine resolved (-ResolvedScope, BL-150)".
- **B.4 A subscription answer without a `tenantId`, and a session whose token names no tenant ID.** The
  owner's Describe (Undecided with `SubscriptionTenantMismatch`, no read without a session tenant) and the
  engine's Describe (every Azure entry `Failed`, no subscription read).
- **B.5 One check per subscription and document, and a second piped document read again.** The owner's
  Context "the cache" and the engine's Describe (one read per subscription per document, in any letter case,
  by id and by name).
- **B.6 The texts.** `tests/QA/about.tests.ps1`, `tests/QA/docsync.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/QA/module.tests.ps1` (help, the release note budget) and `tests/QA/sourcehygiene.tests.ps1` (gate
  10 holds the owner to its two callers, and the api-version `2022-12-01` is documented under
  `rationale.md#arm-transport`).

## C. Manual check for the operator (class C, does not block the merge)

### C.1. A tenant that manages another tenant's subscription through Azure Lighthouse

- [ ] **C.1** (P-15, Philip, after the merge, optional) In a tenant that manages a customer subscription through Azure Lighthouse, export the role assignments and apply a document with a row at the delegated subscription. #type/subtask

Run `Export-OERInventory -Include RoleAssignments` in the managing tenant, with an identity that holds a
role on the delegated subscription, and then `Invoke-OERStructure -WhatIf` with a document that declares a
role assignment at a resource group of the delegated subscription.

**Expect:** the export warns once that it does not walk the delegated subscription, names it in the README
under "Subscriptions delegated from another tenant (not read)", and writes nothing from it; the apply
reports the row `Failed` with `SubscriptionTenantMismatch` and reads or writes nothing at that scope. Record
also what Subscriptions - List returns as the delegated subscription's `tenantId` in the managing tenant:
the customer's tenant is Ruling R-1's premise (`rationale.md#home-tenant-subscriptions`). Where an
identity holds a role only at a resource group of its own tenant's subscription, record too whether
Subscriptions - Get answers for it: a refusal there makes such an operator's Azure entries `Failed`
(Ruling R-18, a known limit in the same section).
**Failure looks like:** a role assignment of the delegated subscription in the export, or an apply row that
is not `Failed`.

Result: not run by Claude Code -- class C, for the operator after the merge, optional and not blocking (P-15). The test tenant manages no other tenant.

## T. Teardown

### T.1. The role assignment, the resource group and the group are gone, and the step's raw folders are deleted

- [x] **T.1** `Initialize-OerS116cPrereq.ps1 -Teardown -Unattended` removes the role assignment at `oer-s116c-rg`, the resource group and the group, and purges the group from the deleted items; the sweep finds nothing with the prefix; no residue row names it; the step's raw folders are deleted. The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check. #type/subtask

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS116cPrereq.ps1'
$Lines = @(& pwsh -NoProfile -NonInteractive -File $Script -Teardown -Unattended 2>&1)
foreach ($L in $Lines) { Write-Host ('[prereq] ' + (ConvertTo-OerLiveRedacted -Text ([string]$L))) }
Write-OerLiveStep "Teardown exit code: $LASTEXITCODE"
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed -Prefix 'oer-s116c-' -ThrowOnUnread)
Write-OerLiveStep "Objects carrying the prefix oer-s116c-: $($Found.Count)"
$RgRead = Invoke-OerLiveArm -Path "$SubScope/resourcegroups/$Rg`?api-version=2021-04-01"
Write-OerLiveStep "The resource group reads: Ok=$($RgRead.Ok) Status=$($RgRead.Status) Code=$($RgRead.Code)"
$Filter = [uri]::EscapeDataString("startswith(displayName,'oer-s116c-')")
$Deleted = Invoke-OerLiveGraph -All -Uri "v1.0/directory/deletedItems/microsoft.graph.group?`$filter=$Filter&`$select=id,displayName"
Write-OerLiveStep "Deleted groups carrying the prefix: $(if ($Deleted.Ok) { @($Deleted.Body['value']).Count } else { "unread ($($Deleted.Status) $($Deleted.Code))" })"
Write-OerLiveStep "Residue rows naming the prefix: $(@(Read-OerLiveResidue | Where-Object { (ConvertTo-Json -InputObject $_ -Compress -Depth 5) -match 'oer-s116c-' }).Count)"
Disconnect-OerLive
foreach ($Dir in @($Raw, (Join-Path $Cfg.Repo 'docs\live-verification\raw\s116c')) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    Write-OerLiveStep "Raw folder deleted: $(-not (Test-Path -LiteralPath $Dir))"
}
```

**Expect:** the teardown lists one role assignment at the resource group, of `oer-s116c-grp`, and removes
it, deletes the resource group (it reads 404), deletes the group and purges it; exit code 0; `Objects
carrying the prefix oer-s116c-: 0`; the resource group `Status=404`; `Deleted groups carrying the prefix:
0`; `Residue rows naming the prefix: 0`; every raw folder deleted (`True`).
**Failure looks like:** a role assignment at the resource group of another principal (STOP: the script did
not make it), a prefixed object left, or a residue row.

Result: 2026-10-18 01:09 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: passed, after a correction of the prerequisite script's teardown and a read-back. First run (01:06 UTC): the teardown listed one role assignment at oer-s116c-rg, of oer-s116c-grp, and removed it; deleted the resource group (it reads 404); deleted the group (204); but its purge read the group's id among the deleted items seconds after the delete and got 404, so it purged nothing, and the block's own sweep a few seconds later still listed the group (listing lag) and one deleted group with the prefix -- the Expect (prefix 0, deleted groups 0) was not met. The script's purge (Initialize-OerS116cPrereq.ps1, the step's own file in the vault) now waits until the group the run deleted is listed among the deleted items, then purges every deleted group carrying the prefix, and reads the sweep until it is empty. Its -Teardown -WhatIf plan (T.0) planned exactly one purge, of oer-s116c-grp, and wrote nothing. Second run (01:08 UTC): the active sweep was already empty, the one deleted group was purged (204), the script's sweep converged at 0, exit code 0; the block's read of the deleted items a second later still listed it once (the deleted items listing lags behind a purge too). The read-back (T.1r, 01:09 UTC, with a wait of up to 600 s on that listing) found 0 deleted groups with the prefix on its first read, 0 objects carrying the prefix, the resource group 404, 0 residue rows naming the prefix, and both raw folders absent. Nothing outside the prefix was touched; the other projects' 5 residue rows were left as they were. Leak check: 0 hits for every run.

Console, redacted (T.1first):
Runner: check T.1; child exit code 0; 22 s; run at 2026-10-18 01:06 UTC.
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: TEARDOWN. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] Role assignments at exactly oer-s116c-rg: 1; of a principal other than oer-s116c-grp: 0.
[prereq] [oer-s116c] Removed a role assignment of oer-s116c-grp at oer-s116c-rg (status 200).
[prereq] [oer-s116c] oer-s116c-rg reads 404: not yet (read 1, 0.2 s, likely replication delay) -- reading again in 2 s.
[prereq] [oer-s116c] oer-s116c-rg reads 404: converged after 2 read(s), 2.6 s.
[prereq] [oer-s116c] Deleted oer-s116c-rg; it reads 404: True.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': users 0, groups 1, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[prereq] [oer-s116c] Teardown 1/6: directory role assignments of the prefixed principals.
[prereq] [oer-s116c] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[prereq] [oer-s116c] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[prereq] [oer-s116c] Teardown 4/6: members of the prefixed role-assignable groups.
[prereq] [oer-s116c] Teardown 5/6: the prefixed groups.
[prereq] [oer-s116c] Deleted: group oer-s116c-grp (204).
[prereq] [oer-s116c] Teardown 6/6: the prefixed users.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': removed 1, residue 0, unreadable 0.
[prereq] [oer-s116c] Remove-OerLiveTestObjects: removed 1, residue 0, unreadable 0, unread 0.
[prereq] [oer-s116c] oer-s116c-grp among the deleted items: not found (status 404).
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Objects carrying the prefix oer-s116c-: 0; the resource group oer-s116c-rg exists: False.
[oer-s116c] Teardown exit code: 0
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] Sweep: group 'oer-s116c-grp' (00000000-0000-0000-0000-000000000009) carries the prefix.
[oer-s116c] Objects carrying the prefix oer-s116c-: 1
[oer-s116c] The resource group reads: Ok=False Status=404 Code=ResourceGroupNotFound
[oer-s116c] Deleted groups carrying the prefix: 1
[oer-s116c] Residue rows naming the prefix: 0
[oer-s116c] Raw folder deleted: True
[oer-s116c] Raw folder deleted: True

Console, redacted (T.0):
Runner: check T.0; child exit code 0; 9 s; run at 2026-10-18 01:08 UTC.
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: TEARDOWN. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] oer-s116c-rg does not exist; nothing to remove there.
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': users 0, groups 0, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[prereq] [oer-s116c] Teardown 1/6: directory role assignments of the prefixed principals.
[prereq] [oer-s116c] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[prereq] [oer-s116c] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[prereq] [oer-s116c] Teardown 4/6: members of the prefixed role-assignable groups.
[prereq] [oer-s116c] Teardown 5/6: the prefixed groups.
[prereq] [oer-s116c] Teardown 6/6: the prefixed users.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[prereq] [oer-s116c] Remove-OerLiveTestObjects: removed 0, residue 0, unreadable 0, unread 0.
[prereq] [oer-s116c] Deleted groups carrying the prefix before the purge: 1.
[prereq] What if: Performing the operation "Purge the deleted group from the deleted items (Microsoft Graph DELETE)" on target "oer-s116c-grp".
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Objects carrying the prefix oer-s116c-: 0; the resource group oer-s116c-rg exists: False.
[oer-s116c] Teardown plan exit code: 0

Console, redacted (T.1):
Runner: check T.1; child exit code 0; 13 s; run at 2026-10-18 01:08 UTC.
[prereq] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[prereq] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[prereq] [oer-s116c] Mode: TEARDOWN. Prefix 'oer-s116c-'. Objects (fixed): the security group oer-s116c-grp (no member, no owner); the resource group oer-s116c-rg (no resource, location 'swedencentral', tagged purpose). Nothing is assigned here. OerLive 1.0.3.
[prereq] [oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[prereq] [oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[prereq] [oer-s116c] oer-s116c-rg does not exist; nothing to remove there.
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': users 0, groups 0, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[prereq] [oer-s116c] Teardown 1/6: directory role assignments of the prefixed principals.
[prereq] [oer-s116c] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[prereq] [oer-s116c] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[prereq] [oer-s116c] Teardown 4/6: members of the prefixed role-assignable groups.
[prereq] [oer-s116c] Teardown 5/6: the prefixed groups.
[prereq] [oer-s116c] Teardown 6/6: the prefixed users.
[prereq] [oer-s116c] Teardown of 'oer-s116c-': removed 0, residue 0, unreadable 0.
[prereq] [oer-s116c] Remove-OerLiveTestObjects: removed 0, residue 0, unreadable 0, unread 0.
[prereq] [oer-s116c] Deleted groups carrying the prefix before the purge: 1.
[prereq] [oer-s116c] Purged oer-s116c-grp from the deleted items: True (status 204).
[prereq] [oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[prereq] [oer-s116c] the sweep finds no object carrying the prefix: converged after 1 read(s), 0.7 s.
[prereq] [oer-s116c] Objects carrying the prefix oer-s116c-: 0; the resource group oer-s116c-rg exists: False.
[oer-s116c] Teardown exit code: 0
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[oer-s116c] Objects carrying the prefix oer-s116c-: 0
[oer-s116c] The resource group reads: Ok=False Status=404 Code=ResourceGroupNotFound
[oer-s116c] Deleted groups carrying the prefix: 1
[oer-s116c] Residue rows naming the prefix: 0
[oer-s116c] Raw folder deleted: True
[oer-s116c] Raw folder deleted: True

Console, redacted (T.1r):
Runner: check T.1r; child exit code 0; 6 s; run at 2026-10-18 01:09 UTC.
[oer-s116c] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg6c-c2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s116c] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s116c] the deleted items list no group carrying the prefix: converged after 1 read(s), 0.1 s.
[oer-s116c] Deleted groups carrying the prefix: 0 (after 0.1 s, 1 read(s))
[oer-s116c] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s116c-' is left.
[oer-s116c] Objects carrying the prefix oer-s116c-: 0
[oer-s116c] The resource group reads: Ok=False Status=404 Code=ResourceGroupNotFound
[oer-s116c] Residue rows naming the prefix: 0
[oer-s116c] Raw folder absent: True
[oer-s116c] Raw folder absent: True
```
