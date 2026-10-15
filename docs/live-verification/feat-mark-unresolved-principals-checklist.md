# Live verification checklist -- unresolved principals are marked, PIM in a restricted unit is warned about, the export writes no scope a document cannot declare, and a review reaches its package in the same run (feat/mark-unresolved-principals)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to
be impossible to run, write "cannot be verified, and therefore we do not know" on its result line and
say why; do not leave it blank and do not tick it. A check that could not run for a stated reason is
marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** One manual check
(class C) is foreseen and does not block the merge: the restricted-management-unit warning against a
tenant that holds such a unit (section C).

**What this file writes to the tenant: only inside the prefix `oer-s116-`.** The prerequisite script
`Initialize-OerS116Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a user `oer-s116-usr` (account disabled, a random password that is never printed or kept); three
security groups with no member, `oer-s116-grp`, `oer-s116-keep` and `oer-s116-req`; an empty catalog
`oer-s116-cat-a`; a catalog `oer-s116-cat-b` holding the hidden access package `oer-s116-ap` with one
assignment policy `oer-s116-pol`, through which only the members of `oer-s116-req` (none) may request;
a tagged, empty resource group `oer-s116-rg` where `oer-s116-usr`, `oer-s116-grp` and `oer-s116-keep` are
each assigned Reader; and a tagged, empty resource group `oer-s116-rg2` where `oer-s116-keep` is assigned
Reader. Check 1.1 deletes `oer-s116-usr` (it stays among the deleted items) and deletes `oer-s116-grp` and
purges it from the deleted items. Check 1.4 removes the two role assignments whose principal is gone, with
`Invoke-OERStructure -Prune`. Checks 1.3, 1.5 and 2.2 run `Invoke-OERStructure` for real and must write nothing,
and nothing else in sections 2 and 3 writes. Nobody is assigned anything else, and no access review is created. The teardown
(T.1) removes the remaining role assignments and both resource groups, then the policy, the package, the
catalogs, the groups and the user, and purges the deleted user and groups from the deleted items where
Microsoft Graph allows it. Bundles, documents and counts are written under `raw\s116\`, which is deleted
after the results are written.

**Nothing is created in a restricted management administrative unit** (an identity at tenant level could
not remove what landed there), so the restricted-unit warning is proved offline (B.3) and by the manual
check in section C.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or
403 as `oer-live-cc` is a stop.

**Permissions.** The objects need the Microsoft Graph application permissions `Group.ReadWrite.All`,
`User.ReadWrite.All` and `EntitlementManagement.ReadWrite.All`; the prerequisite script reads them and
refuses its setup before anything is written when one is missing. `User.DeleteRestore.All`, which
Microsoft Learn names for purging a deleted user, is optional: without it the deleted user stays among
the deleted items for its 30 days. The export's read of the deleted items needs `Directory.Read.All`,
which the export already lists. The role assignments need the identity's existing Azure role on the test
subscription; when Azure Resource Manager refuses one, the script says so and carries on without it, and
the check that needs it becomes class B. Granting a permission is the operator's decision, never this
checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, and every block that runs the
module installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s116/`, which is
git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** A warning and an error that stops a script go straight to the
host, so each block is run in its own process whose WHOLE output (standard output and standard error) is
written to a file under `raw\s116\`, redacted with OerLive's redactor before anyone reads it, and then
deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. One group name index per export** ("refactor: build the group name index once per export", "refactor:
  key the export's run context on its own invocation"). `Export-OERInventory` keeps one run context for its
  `Get-OERInventory` calls, so every group's name is listed at most once per export instead of once per
  Azure scope that names a group principal.
- **B. A principal the directory does not return** ("feat: tell a principal not returned from a failed
  lookup, and read the deleted items", "feat: write principalStatus for a role assignment whose principal is
  not returned", "feat: name role assignments whose principal could not be looked up in the export", "fix:
  read a getByIds batch with no value as not read under -Detailed", "fix: state no unread reason as fact and
  name the principal case for what it is", and the tests and docs commits beside them). An Azure role
  assignment whose principal `directoryObjects/getByIds` does not return is written by object id with its
  type and `principalStatus` `Deleted` (found among the deleted items) or `Unresolved`; a failed lookup is
  reported as partial, never as such a principal. The export warns once with the count and its README lists
  each with role, scope and reason.
- **C. The engine never creates such an assignment** ("feat: know principalStatus in the validator and schema
  and never create such an assignment"). The validator accepts `principalStatus` (only by object id); the
  engine reports a row that would be created `Skipped`, keeps a matching live assignment `Unchanged` and
  protected from `-Prune`, and `-Prune` removes it once the row is gone.
- **D. A scope no document can declare** ("refactor: give the scope spelling rules one owner the validator
  calls", "feat: leave a role assignment at a scope no document can declare out of the inventory", "feat:
  name the role assignments at a scope no document can declare once per export").
- **E. PIM for Groups in a restricted management unit** ("feat: name the groups that use PIM for Groups in a
  restricted management unit", "fix: state the documented PIM limit in a restricted management unit as
  fact"). The export warns and its README lists such groups; `Test-OERStructure` warns where a document shows
  the link.
- **F. An access review and the package its own entry resolves** ("feat: reach the access package its entry
  found or created from a review in the same run", "fix: say that leaving out AccessPackages refuses every
  review of a declared package"). Every access package entry's outcome is registered in the run's map, so a
  review that names a declared package reaches the package that entry resolved, or is refused; it is never
  looked up across the tenant by name. `Test-OERStructure` refuses a review whose package name two package
  entries carry.
- **G. The texts** (the `docs:` commits): help, the schema description, the prompt template, README, the
  about topic, the inventory-to-LLM guide, the rationale, the house rules and the release note.

A live tenant is needed because the claims are about what Microsoft Graph and Azure Resource Manager return
and what the engine then does with the export: that `directoryObjects/getByIds` leaves out a deleted and a
purged principal while Azure Resource Manager still lists their role assignments, that
`directory/deletedItems` finds the one and not the other, that the exported document validates and applies
with the two rows `Unchanged` and nothing created, that `-Prune` removes the two orphaned assignments once
the rows are gone, that an access review of a package missing from its declared catalog is refused while a
package of the same name exists in another catalog, and how many group listings an export of several scopes
sends.

## What this file does not check, and why

- **A failed `getByIds` or `deletedItems` read (class B, B.1 and B.2).** A read cannot be made to fail on
  demand; the unit tests hold the partial signal and the `Unresolved` fallback.
- **PIM for Groups in a restricted management unit (class B and C, B.3 and C.1).** Nothing may be created in
  such a unit here (see above).
- **A role assignment at a scope a document cannot declare (class B, B.4).** It needs a resource whose name
  holds `#`, `%` or a white space at an edge; the unit tests hold the owner, the export and the validator
  against each other.
- **A principal of another type, such as a device (class B, B.5).**
- **The texts (class B, B.6).** Section B names the gates that hold them.

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
- The **prerequisite objects**: check 0.2 runs `Initialize-OerS116Prereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the counters
and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s116-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Usr = 'oer-s116-usr'; $Grp = 'oer-s116-grp'; $Keep = 'oer-s116-keep'; $Req = 'oer-s116-req'
$CatA = 'oer-s116-cat-a'; $CatB = 'oer-s116-cat-b'; $Ap = 'oer-s116-ap'; $Pol = 'oer-s116-pol'; $Rev = 'oer-s116-rev'
$Rg = 'oer-s116-rg'; $Rg2 = 'oer-s116-rg2'
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
$RgScope = "$SubScope/resourceGroups/$Rg"
$Rg2Scope = "$SubScope/resourceGroups/$Rg2"
# The step's raw folder as OerLive fixed it (git-ignored), and the ids the prerequisite script recorded
# there (never printed).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Ids = if (Test-Path -LiteralPath (Join-Path $Raw 'created-s116.json')) { Get-Content -LiteralPath (Join-Path $Raw 'created-s116.json') -Raw | ConvertFrom-Json -AsHashtable } else { @{} }

function Start-S116NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S116TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S116TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S116 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S116Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is a
    # GET. The path of every request is recorded (the query dropped), and every Microsoft Graph request
    # in full in S116GraphUri (printed only through the redactor).
    $global:S116Graph = [System.Collections.Generic.List[string]]::new()
    $global:S116GraphUri = [System.Collections.Generic.List[string]]::new()
    $global:S116Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116Graph.Add((`$($Record)) + ' ' + $Path); `$global:S116GraphUri.Add((`$($Record)) + ' ' + [string]`$Uri); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116Arm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S116Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S116Sent {
    # Requests counted since Start-S116Count: totals and writes (any method but GET), with the write paths.
    # directoryObjects/getByIds is a read sent as POST, so it is counted apart and never as a write.
    $GraphWrites = @($global:S116Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */directoryObjects/getByIds' })
    $GetByIds = @($global:S116Graph | Where-Object { $_ -like 'POST */directoryObjects/getByIds' }).Count
    $ArmWrites = @($global:S116Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S116TokenCalls; Microsoft Graph requests: $($global:S116Graph.Count) (getByIds reads sent as POST: $GetByIds), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S116Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" })"
}

function Show-S116Rows {
    # One line per Invoke-OERStructure result row.
    param([object[]]$Rows)
    foreach ($R in @($Rows | Where-Object { $null -ne $_ })) { Write-OerLiveStep "Row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Show-S116Errors {
    # The error ids an -ErrorVariable holds, by their own id (the part before the first comma).
    param([object[]]$Errors)
    Write-OerLiveStep "Errors: $(@($Errors | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
}

function Get-S116Who {
    # A role assignment's principal as the step names it, never as an id.
    param([string]$Principal)
    if ($Ids['usr'] -and $Principal -eq $Ids['usr']) { return 'the deleted user (by id)' }
    if ($Ids['grp'] -and $Principal -eq $Ids['grp']) { return 'the purged group (by id)' }
    if ($Ids['keep'] -and $Principal -eq $Ids['keep']) { return "$Keep (by id)" }
    if ($Principal -eq $Keep) { return $Keep }
    'another principal'
}

function Save-S116Document {
    # A structure document written as JSON under raw\s116\docs; returns its path.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][object]$Document)
    $Dir = Join-Path $Raw 'docs'
    $null = New-Item -ItemType Directory -Path $Dir -Force
    $Path = Join-Path $Dir "$Name.json"
    [System.IO.File]::WriteAllText($Path, ($Document | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $Path
}

function Get-S116Bundle {
    # The newest bundle folder under one of the step's export folders.
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -LiteralPath (Join-Path $Raw $Name) -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Get-S116ReadmeSection {
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

function Get-S116AtScope {
    # The role assignments Azure Resource Manager lists AT a scope (atScope), as principal names.
    param([Parameter(Mandatory)][string]$Scope)
    $L = Invoke-OerLiveArm -All -Path "$Scope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
    Assert-OerLiveOk -Response $L -Activity 'Listing role assignments' | Out-Null
    @($L.Body.value | Where-Object { $null -ne $_ -and [string]$_.properties.scope -eq $Scope } | ForEach-Object { Get-S116Who -Principal ([string]$_.properties.principalId) })
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
Write-OerLiveStep "The worktree's build reads the deleted items: $(& $Has 'function Get-OERDeletedPrincipalStatus')"
Write-OerLiveStep "The worktree's build hands unresolved principals over in an information record: $(& $Has 'Omnicit.EntraRBAC.UnresolvedPrincipal')"
Write-OerLiveStep "The worktree's build owns the scope spelling rules once: $(& $Has 'function Get-OERScopeSpellingProblem')"
Write-OerLiveStep "The worktree's build hands undeclarable scopes over in an information record: $(& $Has 'Omnicit.EntraRBAC.UndeclarableScope')"
Write-OerLiveStep "The worktree's build keeps one run context per export: $(& $Has '_OERInventoryRunContext')"
Write-OerLiveStep "The worktree's build registers an access package entry without a rename: $(& $Has 'Unidentified')"
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
Start-S116NoPrompt
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
$Script = Join-Path $VaultDir 'Initialize-OerS116Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS116Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -File $Script @Run *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run plans every object (`What if:` lines) and writes nothing; the first
`-Unattended` run writes the baseline, creates the user, the three groups, the two catalogs, the package, the
policy, both resource groups and the four role assignments, `unavailable (class B): none`, exit code 0; the
second run says `The whole set exists` and creates nothing, exit code 0.
**Failure looks like:** a `Refusing to run` line (read it; nothing was written), a 401/403 (STOP), or an
`UNAVAILABLE` line (the check it names becomes class B).

Result:

## 1. A principal the directory no longer returns (BL-133, A18)

### 1.1. The user is deleted, and the group deleted and purged

- [ ] **1.1** `getByIds` no longer returns either principal; the user is among the deleted items and the group is not.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS116Prereq.ps1'
Write-OerLiveStep '=== Initialize-OerS116Prereq.ps1 -RemovePrincipals -Unattended ==='
& pwsh -NoProfile -File $Script -RemovePrincipals -Unattended *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
Write-OerLiveStep "exit code: $LASTEXITCODE"
Connect-OerLive -Arm
Write-OerLiveStep "Azure Resource Manager still lists at ${Rg}: $((Get-S116AtScope -Scope $RgScope | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** the user deleted; the group deleted and purged; `getByIds returns the user: False, the group:
False`; `the user is among the deleted items: True; the group is among the deleted items: False`; exit code
0; Azure Resource Manager still lists three role assignments at `oer-s116-rg`: the deleted user (by id), the
purged group (by id) and `oer-s116-keep` (by id).
**Failure looks like:** a 401/403 (STOP); an `UNAVAILABLE` line for the purge (the `Unresolved` half of 1.2
becomes class B, and the group is reported `Deleted`).

Result:

### 1.2. The export marks both principals and names them in the README

- [ ] **1.2** An export of `oer-s116-rg` writes `principalStatus` `Deleted` for the user and `Unresolved` for the group, by id with their type, warns once with the count, lists both in the README, and writes nothing.

```powershell
Connect-OerLive -Arm
Start-S116NoPrompt
Start-S116Count
$Out = Join-Path $Raw 'export-rg'
$null = New-Item -ItemType Directory -Path $Out -Force
$W = $null; $E = $null
$B = Export-OERInventory -OutputPath $Out -Include RoleAssignments -Scope $RgScope -WarningVariable W -ErrorVariable E -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S116Sent)
Write-OerLiveStep "deletedItems reads: $(@($global:S116Graph | Where-Object { $_ -like 'GET */directory/deletedItems/*' }).Count)"
Stop-S116Count
Write-OerLiveStep "Bundle written: $([bool]$B.BundlePath); role assignments $($B.RoleAssignments); IncompleteReads: $(@($B.IncompleteReads) -join ' | ')"
foreach ($X in @($W)) { Write-OerLiveStep "Warning: $($X.Message)" }
Show-S116Errors -Errors $E
$Inv = Get-Content -LiteralPath (Join-Path $B.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Rows = @($Inv.roleAssignments | Where-Object { $null -ne $_ })
Write-OerLiveStep "inventory.json roleAssignments: $($Rows.Count); at ${Rg}: $(@($Rows | Where-Object { $_.scope -eq $RgScope }).Count)"
foreach ($R in @($Rows | Where-Object { $_.scope -eq $RgScope })) {
    Write-OerLiveStep "Row at ${Rg}: role $($R.role); principal $(Get-S116Who -Principal ([string]$R.principal)); keys $(@($R.PSObject.Properties.Name) -join ','); principalType $($R.principalType); principalStatus $($R.principalStatus)"
}
$Readme = Get-Content -LiteralPath (Join-Path $B.BundlePath 'README.md') -Raw
foreach ($L in @(Get-S116ReadmeSection -Text $Readme -Heading 'Role assignments whose principal the directory did not return')) { Write-OerLiveStep "README: $L" }
Disconnect-OerLive
```

**Expect:** a bundle; Microsoft Graph and Azure Resource Manager `writes: 0`; two deletedItems reads (one per
principal; more only if the resource group inherits another assignment whose principal is gone); exactly
ONE warning about principals the directory did not return, counting the two (and any such inherited one); no
`InventoryPartial` and no IncompleteReads entry naming the two; three rows at `oer-s116-rg`: `oer-s116-keep`
by name with `principalType` `Group` and no `principalStatus`, the deleted user by id with `principalType`
`User` and `principalStatus` `Deleted`, the purged group by id with `principalType` `Group` and
`principalStatus` `Unresolved`, each row's keys in the order `scope, role, principal, principalType,
principalStatus`; the README section lists both with role, scope and the reason in words.
**Failure looks like:** a principal written by name or with no `principalStatus`; a second warning; an
`InventoryPartial`; a write.

Result:

### 1.3. The exported document validates and applies: Unchanged, nothing created (G8)

- [ ] **1.3** `Test-OERStructure` accepts the exported document; `Invoke-OERStructure -WhatIf` on it, and two real runs on its rows at `oer-s116-rg`, report the three rows `Unchanged` and write nothing.

An export at a resource group also reads the role assignments it inherits from the subscription, which are
not this step's: the plan runs on the whole exported document, and the real runs on the same document
limited to its rows at `oer-s116-rg`, so nothing outside the prefix is ever a target.

```powershell
$Doc = Join-Path (Get-S116Bundle -Name 'export-rg').FullName 'inventory.json'
$V = Test-OERStructure -Path $Doc
Write-OerLiveStep "Valid: $($V.Valid); findings: $(@($V.Errors).Count)"
foreach ($F in @($V.Errors)) { Write-OerLiveStep "Finding: $($F.Severity) $($F.Path): $($F.Message)" }
$Inv = Get-Content -LiteralPath $Doc -Raw | ConvertFrom-Json
$Own = [ordered]@{ version = $Inv.version; tenantId = $Inv.tenantId; roleAssignments = @($Inv.roleAssignments | Where-Object { $null -ne $_ -and $_.scope -eq $RgScope }) }
if (@($Own.roleAssignments | Where-Object { $_.scope -ne $RgScope }).Count -gt 0 -or @($Own.roleAssignments).Count -ne 3) { throw "STOP: the document limited to $Rg does not hold exactly the step's three rows; nothing is applied." }
$OwnDoc = Save-S116Document -Name 'export-rg-own-rows' -Document $Own
Write-OerLiveStep "Rows in the whole export: $(@($Inv.roleAssignments).Count); at ${Rg}: $(@($Own.roleAssignments).Count)"
Connect-OerLive -Arm
Start-S116NoPrompt
foreach ($Mode in 'WhatIf (whole export)', 'Real 1', 'Real 2') {
    Start-S116Count
    $E = $null
    if ($Mode -like 'WhatIf*') { $Rows = Invoke-OERStructure -Path $Doc -Include RoleAssignments -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue }
    else { $Rows = Invoke-OERStructure -Path $OwnDoc -Include RoleAssignments -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    Write-OerLiveStep "== ${Mode}: $(Get-S116Sent)"
    Stop-S116Count
    Show-S116Rows -Rows $Rows
    Show-S116Errors -Errors $E
}
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((Get-S116AtScope -Scope $RgScope | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** `Valid: True` with no Error; in the plan the three rows at `oer-s116-rg` are `Unchanged` (every
other row is a role assignment inherited from the subscription and is `Unchanged` or `Skipped`, never
`Created`), and in both real runs the three rows are `Unchanged`; `writes: 0` every time; no error; the three
role assignments still listed.
**Failure looks like:** a `Created` row or a write; a principal lookup failure for the two ids.

Result:

### 1.4. Without the two rows, -Prune removes the orphaned assignments (G8)

- [ ] **1.4** The step's rows without the two orphaned ones: `-Prune -WhatIf` plans removing both, a real `-Prune` removes both, and a second real `-Prune` reports only `Unchanged`.

The document is the one 1.3 applied, limited to `oer-s116-rg`, without the two rows that carry
`principalStatus`: `-Prune` then reaches only that resource group, the one scope the document declares.

```powershell
$Own = Get-Content -LiteralPath (Join-Path $Raw 'docs\export-rg-own-rows.json') -Raw | ConvertFrom-Json
$Own.roleAssignments = @($Own.roleAssignments | Where-Object { $null -ne $_ -and -not ($_.PSObject.Properties.Name -contains 'principalStatus') })
if (@($Own.roleAssignments | Where-Object { $_.scope -ne $RgScope }).Count -gt 0 -or @($Own.roleAssignments).Count -ne 1 -or [string]$Own.roleAssignments[0].principal -ne $Keep) { throw "STOP: the pruning document does not hold exactly the oer-s116-keep row at $Rg; nothing is applied." }
$Doc2 = Save-S116Document -Name 'without-orphans' -Document $Own
Write-OerLiveStep "Rows in the document: $(@($Own.roleAssignments).Count) ($Keep at $Rg); scopes declared: 1"
Connect-OerLive -Arm
Start-S116NoPrompt
foreach ($Mode in 'WhatIf', 'Real 1', 'Real 2') {
    Start-S116Count
    $E = $null
    if ($Mode -eq 'WhatIf') { $Rows = Invoke-OERStructure -Path $Doc2 -Include RoleAssignments -Prune -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue }
    else { $Rows = Invoke-OERStructure -Path $Doc2 -Include RoleAssignments -Prune -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    Write-OerLiveStep "== ${Mode}: $(Get-S116Sent)"
    Stop-S116Count
    Show-S116Rows -Rows $Rows
    Show-S116Errors -Errors $E
}
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((Get-S116AtScope -Scope $RgScope | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** the plan names the two orphaned role assignments at `oer-s116-rg` as removed and writes nothing;
the first real run removes them (two Azure Resource Manager `DELETE` requests, nothing else written); the
second real run reports `oer-s116-keep` `Unchanged` and removes nothing (`writes: 0`); Azure Resource Manager
then lists only `oer-s116-keep` at `oer-s116-rg`.
**Failure looks like:** `oer-s116-keep` removed; a third removal; a write in the second run.

Result:

### 1.5. With the assignments gone, the rows with principalStatus are Skipped and nothing is created (A18)

- [ ] **1.5** The document 1.3 applied, applied again after 1.4 removed the two orphaned assignments: the two rows with `principalStatus` are `Skipped` and never created, planned and run twice.

```powershell
$OwnDoc = Join-Path $Raw 'docs\export-rg-own-rows.json'
Connect-OerLive -Arm
Start-S116NoPrompt
foreach ($Mode in 'WhatIf', 'Real 1', 'Real 2') {
    Start-S116Count
    $E = $null
    if ($Mode -eq 'WhatIf') { $Rows = Invoke-OERStructure -Path $OwnDoc -Include RoleAssignments -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue }
    else { $Rows = Invoke-OERStructure -Path $OwnDoc -Include RoleAssignments -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    Write-OerLiveStep "== ${Mode}: $(Get-S116Sent)"
    Stop-S116Count
    Show-S116Rows -Rows $Rows
    Show-S116Errors -Errors $E
}
Write-OerLiveStep "Azure Resource Manager lists at ${Rg}: $((Get-S116AtScope -Scope $RgScope | Sort-Object) -join ', ')"
Disconnect-OerLive
```

**Expect:** in the plan and in both real runs, `oer-s116-keep` `Unchanged` and the two rows with
`principalStatus` `Skipped`, their detail starting `principalStatus 'Deleted':` and
`principalStatus 'Unresolved':` and saying nothing was written; no `What if:` line and no create request;
`writes: 0` every time; Azure Resource Manager still lists only `oer-s116-keep` at `oer-s116-rg`.
**Failure looks like:** a `Created` row, a role assignment `PUT`, or a principal lookup for the two ids.

Result:

## 2. An access review and the package its own entry resolves (BL-147)

### 2.1. The validator refuses a review of a name two package entries carry

- [ ] **2.1** `Test-OERStructure` gives an Error for an access review whose package name two package entries carry, with no rename (offline).

```powershell
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{ displayName = $Ap; catalog = $CatA }, [ordered]@{ displayName = $Ap; catalog = $CatB })
    accessReviews  = @([ordered]@{ displayName = $Rev; accessPackage = $Ap; assignmentPolicy = $Pol; reviewers = @() })
}
$V = Test-OERStructure -Json ($Doc | ConvertTo-Json -Depth 20)
Write-OerLiveStep "Valid: $($V.Valid); findings: $(@($V.Errors).Count)"
foreach ($F in @($V.Errors)) { Write-OerLiveStep "Finding: $($F.Severity) $($F.Path): $($F.Message)" }
```

**Expect:** `Valid: False`; an Error at the review's `accessPackage` that names the two entries; nothing
signs in.
**Failure looks like:** `Valid: True`, or only a Warning.

Result:

### 2.2. A review of a package missing from its declared catalog is refused, and nothing is created

- [ ] **2.2** `oer-s116-ap` declared in `oer-s116-cat-a` (where it does not exist; it exists in `oer-s116-cat-b`) and a review of it: the package entry is `Failed`, the review is `Failed`, no review is created, and nothing is written -- planned and run twice.

```powershell
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{ displayName = $Ap; catalog = $CatA })
    accessReviews  = @([ordered]@{ displayName = $Rev; accessPackage = $Ap; assignmentPolicy = $Pol; reviewers = @() })
}
$Path = Save-S116Document -Name 'review-of-a-missing-package' -Document $Doc
Connect-OerLive -Arm
Start-S116NoPrompt
foreach ($Mode in 'WhatIf', 'Real 1', 'Real 2') {
    Start-S116Count
    $E = $null
    if ($Mode -eq 'WhatIf') { $Rows = Invoke-OERStructure -Path $Path -Include AccessPackages, AccessReviews -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue }
    else { $Rows = Invoke-OERStructure -Path $Path -Include AccessPackages, AccessReviews -Confirm:$false -ErrorVariable E -ErrorAction SilentlyContinue }
    Write-OerLiveStep "== ${Mode}: $(Get-S116Sent)"
    $Named = @($global:S116GraphUri | Where-Object { $_ -match [regex]::Escape($Ap) })
    Write-OerLiveStep "Microsoft Graph requests that name ${Ap}: $($Named.Count)"
    foreach ($U in $Named) { Write-OerLiveStep "  $U" }
    Write-OerLiveStep "Access review requests: $(@($global:S116Graph | Where-Object { $_ -like '*accessReviews*' }).Count)"
    Stop-S116Count
    Show-S116Rows -Rows $Rows
    Show-S116Errors -Errors $E
}
$L = Invoke-OerLiveGraph -All -Uri 'v1.0/identityGovernance/accessReviews/definitions?$select=id,displayName'
Assert-OerLiveOk -Response $L -Activity 'Listing the access review definitions' | Out-Null
Write-OerLiveStep "Access review definitions carrying the prefix: $(@(@($L.Body['value']) | Where-Object { $null -ne $_ -and ([string]$_['displayName']).StartsWith('oer-s116-', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
Disconnect-OerLive
```

**Expect:** in the plan the package entry plans a create in `oer-s116-cat-a` (the known `-WhatIf` residual)
and the review is `Failed`, saying the plan would create the package, which has no id yet; in both real runs
the package entry is `Failed` (a package of that name exists in another catalog) and the review is `Failed`,
saying its access package entry was not resolved in this run; no access review request is sent; `writes: 0`
every time; no access review definition carries the prefix.
**Failure looks like:** a review row other than `Failed`; an access review request; a write; a definition
with the prefix.

Result:

### 2.3. A review of a package its entry finds in its catalog reaches that package (plan only)

- [ ] **2.3** `oer-s116-ap` declared in `oer-s116-cat-b`, where it exists, and a review of it: the plan reads the review's package as the id the package entry resolved, writes nothing; with `-Include` leaving AccessPackages out, the review is refused.

```powershell
$Doc = [ordered]@{
    version        = '1.0'
    accessPackages = @([ordered]@{ displayName = $Ap; catalog = $CatB })
    accessReviews  = @([ordered]@{ displayName = $Rev; accessPackage = $Ap; assignmentPolicy = $Pol; reviewers = @() })
}
$Path = Save-S116Document -Name 'review-of-a-found-package' -Document $Doc
Connect-OerLive -Arm
Start-S116NoPrompt
foreach ($Include in @(@('AccessPackages', 'AccessReviews'), @('AccessReviews'))) {
    Start-S116Count
    $E = $null
    $Rows = Invoke-OERStructure -Path $Path -Include $Include -WhatIf -ErrorVariable E -ErrorAction SilentlyContinue
    Write-OerLiveStep "== -Include $($Include -join ','), -WhatIf: $(Get-S116Sent)"
    Stop-S116Count
    Show-S116Rows -Rows $Rows
    Show-S116Errors -Errors $E
}
Disconnect-OerLive
```

**Expect:** with both sections, the package entry `Unchanged` and the review planned for creation, its detail
naming the access package its accessPackages entry resolved in this run; with AccessReviews alone, the
review `Failed`, saying the AccessPackages section was left out; `writes: 0` both times.
**Failure looks like:** a review planned against a package found by name across the tenant; a write.

Result:

## 3. One group listing per export (step 5, R-2)

### 3.1. An export of the subscription lists every group's name once

- [ ] **3.1** `Export-OERInventory -Include RoleAssignments -Scope` the test subscription walks several scopes, names `oer-s116-keep` by name at both resource groups, and lists every group's name exactly once.

```powershell
Connect-OerLive -Arm
Start-S116NoPrompt
Start-S116Count
$Out = Join-Path $Raw 'export-sub'
$null = New-Item -ItemType Directory -Path $Out -Force
$W = $null; $E = $null
$B = Export-OERInventory -OutputPath $Out -Include RoleAssignments -Scope $SubScope -WarningVariable W -ErrorVariable E -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep (Get-S116Sent)
$Listings = @($global:S116GraphUri | Where-Object { $_ -match '^GET .*v1\.0/groups\?' -and $_ -match 'select=id,displayName' -and $_ -notmatch 'skiptoken' })
Write-OerLiveStep "Group name listings (first pages): $($Listings.Count)"
$AtScopes = @($global:S116Arm | Where-Object { $_ -like 'GET */providers/Microsoft.Authorization/roleAssignments' } | Sort-Object -Unique)
Write-OerLiveStep "Distinct scopes whose role assignments were listed: $($AtScopes.Count)"
Stop-S116Count
foreach ($X in @($W)) { Write-OerLiveStep "Warning: $($X.Message)" }
Show-S116Errors -Errors $E
$Inv = Get-Content -LiteralPath (Join-Path $B.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Rows = @($Inv.roleAssignments | Where-Object { $null -ne $_ })
Write-OerLiveStep "inventory.json roleAssignments: $($Rows.Count); distinct scopes: $(@($Rows | ForEach-Object { $_.scope } | Sort-Object -Unique).Count)"
foreach ($S in @($RgScope, $Rg2Scope)) {
    $At = @($Rows | Where-Object { $_.scope -eq $S })
    Write-OerLiveStep "At $(if ($S -eq $RgScope) { $Rg } else { $Rg2 }): $(@($At | ForEach-Object { "$(Get-S116Who -Principal ([string]$_.principal)) ($($_.principalType))" }) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** `writes: 0`; `Group name listings (first pages): 1`; at least three distinct scopes listed (the
subscription and the two resource groups); `oer-s116-keep` by name, `Group`, at `oer-s116-rg` and at
`oer-s116-rg2`.
**Failure looks like:** two or more listings (one per scope, the cost step 5 found); `oer-s116-keep` written
by id.

Result:

## T. Teardown

### T.1. Remove every oer-s116- object

- [ ] **T.1** The prerequisite script's teardown removes the remaining role assignments, both resource groups and every other prefixed object, purges the deleted principals where allowed, and the sweep finds none.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS116Prereq.ps1'
foreach ($Run in @(@('-Teardown', '-WhatIf'), @('-Teardown', '-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS116Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -File $Script @Run *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run removes nothing; the real run removes the role assignments still at the two
resource groups and both groups, finds no prefixed access review, removes the policy, the package, the two
catalogs, the groups and the user through OerLive's fixed order, purges the deleted user and groups from the
deleted items (or says which are left there for their 30 days), the sweep finds nothing, the counts equal the
baseline, exit code 0.
**Failure looks like:** a RESIDUE line (exit code 3): name it in the report.

Result:

### T.2. Read back

- [ ] **T.2** A read-only run finds no prefixed object, neither resource group, and the counts at the baseline.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS116Prereq.ps1'
& pwsh -NoProfile -File $Script -ReadBack *>&1 | ForEach-Object { Write-OerLiveStep ([string]$_) }
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** prefixed objects left: 0; unread collections: 0; neither resource group exists; the counts equal
the baseline; no residue row with this step's prefix.
**Failure looks like:** anything left: name it in the report.

Result:

## B. Proved offline only (class B)

Each item below is held by unit tests (Pester, everything mocked at the module boundary, the transport
tripwire installed) and runs in the full gate, `./build.ps1 -Tasks test`, on all three CI runners.

- **B.1 A failed `directoryObjects/getByIds` lookup** -- the row is written by object id with its type and no
  `principalStatus`, named in IncompleteReads and reported `InventoryPartial`, by `Get-OERInventory` alone and
  through `Export-OERInventory` without skipping the scope (`tests/Unit/Public/Get-OERInventory.Tests.ps1`,
  `tests/Unit/Public/Export-OERInventory.Tests.ps1`, `tests/Unit/Private/Resolve-OERPrincipalName.Tests.ps1`).
- **B.2 A failed read of the deleted items** -- `Unresolved`, and the reason named as unread
  (`tests/Unit/Private/Get-OERDeletedPrincipalStatus.Tests.ps1`, `Get-OERInventory.Tests.ps1`).
- **B.3 PIM for Groups in a restricted management unit** -- the export's one warning and README section, no
  entry for a unit that is not restricted or whose members were not read, and the validator's Warning in both
  shapes (`Export-OERInventory.Tests.ps1`, `tests/Unit/Private/Get-OERInventoryReadme.Tests.ps1`,
  `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`). Live in a tenant that holds such a unit: C.1.
- **B.4 A role assignment at a scope a document cannot declare** (`#`, `%`, `\`, `?`, a dot segment, white
  space at an edge) -- left out with one warning and named in the README; the validator refuses exactly the
  scopes the owner reports (`tests/Unit/Private/Get-OERScopeSpellingProblem.Tests.ps1`, its agreement tests,
  `Get-OERInventory.Tests.ps1`, `Export-OERInventory.Tests.ps1`).
- **B.5 A principal of a type outside the schema, such as a device** -- written by object id with no
  `principalType` (`Get-OERInventory.Tests.ps1`).
- **B.6 The engine never creates an entry with `principalStatus`, proved in a runspace with no `try`**, and
  the review refused in a runspace with no `try` when its package entry was not resolved
  (`tests/Unit/Private/Sync-OERStructureRoleAssignment.Tests.ps1`, `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`).
  1.5 and 2.2 run the same paths live.
- **B.7 The texts** -- `tests/QA/about.tests.ps1`, `docsync.tests.ps1`, `dochygiene.tests.ps1` and
  `module.tests.ps1` (the release note's budget and floor).

## C. Manual, after the merge (class C, P-15)

- **C.1** An export of a tenant that holds a restricted management administrative unit with a group that uses
  PIM for Groups as a member: one warning naming the count, the README section naming the group and the
  unit. Optional and non-blocking; Philip runs it against his own tenant after the merge.
