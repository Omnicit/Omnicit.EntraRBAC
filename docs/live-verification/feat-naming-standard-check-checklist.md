# Live verification checklist -- names are checked against a naming standard file (feat/naming-standard-check)

**This branch does not merge until every box in sections S, 0, 1, 2 and T has a written result.** A box
with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be
impossible to run, write "cannot be verified, and therefore we do not know" on its result line and say
why; do not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** No manual check (class C)
is foreseen.

**What this file writes to the tenant: nothing.** Every tenant call reads, and the check under test makes
no call at all. No object is created, so there is no prerequisite script and no prefixed object; the prefix
`oer-s117-` names only the step's raw folder. The export bundle, the edited document copies and the two
standard files the checks write go under `raw\s117\`, which is deleted after the results are written. No
write path changes in this step, so there is no convergence check (G8).

**The tenant's object names are never printed.** The export's `inventory.json` carries the display names of
the test tenant's objects, and every naming Warning quotes the name it is about. The blocks therefore print
counts only -- per section and per rule -- and the export's own warnings are captured and counted, never
printed. The one place a Warning's text is printed is check 1.3, and only for entries the check itself adds
to a local copy, whose names it invents.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives
beside the operator's copy of this file outside the repository ([README.md](README.md), first paragraph).
Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or 403 is a stop.

**Permissions.** The export reads Microsoft Graph with the permissions `oer-live-cc` already holds; no Azure
section is exported. `Test-OERStructure` needs none. Granting a permission is the operator's decision, never
this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, and every block that runs the module
installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s117/`, which is
git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** Each block is run in its own process whose WHOLE output (every
stream) is written to a file under `raw\s117\`, redacted with OerLive's redactor before anyone reads it, and
then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The standard and its reader** ("feat: read a naming standard file and check names against it", "test:
  pin the whole refusal message for a segment that is not an object", "fix: name an unreadable naming standard
  file once, with its reason"). A naming standard is a JSON file:
  separator, maximum length, an ordered list of segments (each with a closed list of values or a pattern, a
  letter case, and optional or not), exceptions as patterns, the sections it applies to and whether synced
  groups are included. The module carries its draft-07 schema; the reader refuses a file that breaks it,
  naming every problem. `Test-OERStructureSchema` adds one Warning per object and rule for every name the
  standard covers.
- **B. The parameter** ("feat: add -NamingStandard to Test-OERStructure"). `Test-OERStructure -NamingStandard`
  reads the file once and checks every document it validates; an unreadable file is one
  `InvalidNamingStandard` error and nothing is validated. `Invoke-OERStructure` takes no standard.
- **C. The texts** ("docs: document the naming standard check and add a neutral example", "docs: correct the
  date limit and tighten the naming standard texts", "docs: say which groups an export holds for the naming
  check, and tighten the naming texts", "docs: match the export's group selection in the naming check texts"):
  the neutral example
  `docs/examples/naming-standard.json` and its schema, README, the about topic, the inventory-to-LLM guide
  (also `groups[].template` and `tokens`), the prompt template, the rationale and the release note.

A live tenant is needed for one claim the unit tests cannot make: that the check works on a REAL exported
`inventory.json` -- the names, the shapes and the counts a tenant actually produces -- keeps the document
valid, changes no other finding, and sends nothing while it runs.

## What this file does not check, and why

- **Each rule, each section and every refusal of the file (class B, B.1 to B.4).** The unit tests hold them
  exactly, message for message; the live run counts what a real export gives.
- **A synced group in the export (class B, B.3).** The test tenant has no group synchronized from
  on-premises; check 1.3 adds one to a local copy instead.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`,
  and the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it, so
  the module loads from the worktree's build and the example standard is read from the worktree; the main
  clone is never checked out on another commit or branch (S.1 reads that it was not).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence, the counters and
the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s117-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Std = Join-Path $Cfg.Repo 'docs\examples\naming-standard.json'
$Include = 'Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews'

function Start-S117NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S117TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S117TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S117 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S117Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is a
    # GET. The token counter starts again with the request counters.
    $global:S117TokenCalls = 0
    $global:S117Graph = [System.Collections.Generic.List[string]]::new()
    $global:S117Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S117Graph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S117Arm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S117Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S117Sent {
    # Requests counted since Start-S117Count: totals and writes (any method but GET; getByIds is a read sent as POST).
    $GraphWrites = @($global:S117Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */directoryObjects/getByIds' })
    $ArmWrites = @($global:S117Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S117TokenCalls; Microsoft Graph requests: $($global:S117Graph.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S117Arm.Count), writes: $($ArmWrites.Count)"
}

function Get-S117Bundle {
    # The newest bundle folder under the step's export folder.
    Get-ChildItem -LiteralPath (Join-Path $Raw 'export') -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Test-S117Naming {
    # Whether a finding is a naming finding: a rule Warning, or a "was not checked" Warning.
    param([Parameter(Mandatory)][object]$Finding)
    $M = [string]$Finding.Message
    $M -like '* the naming standard (rule *' -or $M -like '* was not checked against the naming standard: *'
}

function Get-S117Kind {
    # The kind a finding's Path names: its top-level section, or assignmentPolicies for a policy.
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -match '\.assignmentPolicies\[') { 'assignmentPolicies' } else { ($Path -split '\[')[0] }
}

function Get-S117AtPath {
    # The value a finding's Path names in a parsed document, for example accessPackages[0].assignmentPolicies[1].displayName.
    param([Parameter(Mandatory)][object]$Doc, [Parameter(Mandatory)][string]$Path)
    $Node = $Doc
    foreach ($Part in $Path.Split('.')) {
        if ($Part -match '^(\w+)\[(\d+)\]$') { $Node = @($Node.($Matches[1]))[[int]$Matches[2]] } else { $Node = $Node.$Part }
    }
    $Node
}

function Get-S117NameCount {
    # How many names of each kind the document carries (a non-empty string displayName), never the names.
    param([Parameter(Mandatory)][object]$Doc)
    $Count = [ordered]@{}
    foreach ($Kind in 'groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'accessReviews') {
        $Count[$Kind] = @(@($Doc.$Kind) | Where-Object { $_.displayName -is [string] -and $_.displayName.Length -gt 0 }).Count
    }
    $Count['assignmentPolicies'] = @(@($Doc.accessPackages) | ForEach-Object { @($_.assignmentPolicies) } | Where-Object { $_.displayName -is [string] -and $_.displayName.Length -gt 0 }).Count
    ($Count.Keys | ForEach-Object { "$_ $($Count[$_])" }) -join ', '
}

function Get-S117NamingSummary {
    # The naming findings of a StructureValidation, counted per kind and rule. Never prints a name.
    param([Parameter(Mandatory)][object]$Validation, [Parameter(Mandatory)][object]$Doc)
    $Naming = @($Validation.Errors | Where-Object { Test-S117Naming -Finding $_ })
    $Rows = foreach ($F in $Naming) {
        $M = [string]$F.Message
        $Rule = if ($M -match "\(rule '([A-Za-z]+)'") { $Matches[1] } elseif ($M -like '*synchronized from on-premises*') { 'not checked (synced)' } else { 'not checked (template)' }
        [PSCustomObject]@{ Kind = Get-S117Kind -Path ([string]$F.Path); Rule = $Rule }
    }
    $ItemOk = @($Naming | Where-Object { ([string]$_.Path).EndsWith('.displayName') -and [string](Get-S117AtPath -Doc $Doc -Path ([string]$_.Path)) -cne [string]$_.Item }).Count -eq 0
    "Naming findings: $($Naming.Count); every one a Warning: $(@($Naming | Where-Object { $_.Severity -ne 'Warning' }).Count -eq 0); on distinct names: $(@($Naming | ForEach-Object { [string]$_.Path } | Sort-Object -Unique).Count); every Item is the name at its Path: $ItemOk"
    foreach ($G in @($Rows | Group-Object -Property Kind, Rule | Sort-Object -Property Name)) { "  $($G.Name.Replace(', ', ' / ')): $($G.Count)" }
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
$Has = { param($Text) [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Text -Quiet) }
Write-OerLiveStep "The worktree's build reads a naming standard file: $(& $Has 'function Read-OERNamingStandard')"
Write-OerLiveStep "The worktree's build checks a name against it: $(& $Has 'function Test-OERNamingStandardName')"
Write-OerLiveStep "The worktree's build refuses an unreadable file: $(& $Has "'InvalidNamingStandard'")"
Write-OerLiveStep "The neutral example is in the worktree: $(Test-Path -LiteralPath $Std -PathType Leaf)"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a
`False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S117NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Write-OerLiveStep "Test-OERStructure has -NamingStandard: $((Get-Command -Name Test-OERStructure).Parameters.ContainsKey('NamingStandard')); Invoke-OERStructure has none: $(-not (Get-Command -Name Invoke-OERStructure).Parameters.ContainsKey('NamingStandard'))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, `The module is the worktree's build: True`, and
both parameter lines `True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

## 1. An export of the test tenant, checked against the neutral example

### 1.1. The export reads only

- [ ] **1.1** An export of the five Entra ID sections that carry names writes `inventory.json` with reads only. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S117NoPrompt
Start-S117Count
$Out = Join-Path $Raw 'export'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Include $Include -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S117Sent)
Stop-S117Count
$InvPath = Join-Path $Bundle.BundlePath 'inventory.json'
$Inv = Get-Content -LiteralPath $InvPath -Raw | ConvertFrom-Json
Write-OerLiveStep "inventory.json exists: $(Test-Path -LiteralPath $InvPath -PathType Leaf); names it carries: $(Get-S117NameCount -Doc $Inv)"
Write-OerLiveStep "Groups marked onPremisesSynced true: $(@(@($Inv.groups) | Where-Object { $_.onPremisesSynced -is [bool] -and $_.onPremisesSynced }).Count)"
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count); errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) -join ', '); export warnings (counted, not printed): $(@($ExportWarnings).Count)"
Disconnect-OerLive
```

**Expect:** Microsoft Graph `writes: 0`, Azure Resource Manager `requests: 0`, `token requests: 0`;
`inventory.json exists: True` with the name counts printed; `IncompleteReads: 0` and no error. By default
`inventory.json` keeps only the RBAC-relevant security groups (Export-OERInventory's help), so the group count
is below the tenant's, and the check in 1.2 covers exactly the groups the file holds.
**Failure looks like:** a write, a token request (the fence would have refused it), an ARM request (no Azure
section was asked for), or an unread collection (the export is then partial and 1.2 still runs on what was
read, with the partial reads recorded here).

Result:

### 1.2. The check on the exported inventory.json: valid, nothing else changes, nothing is sent

- [ ] **1.2** `Test-OERStructure -NamingStandard` with the neutral example on the export's `inventory.json` keeps the document valid, adds only naming Warnings (counted per section and rule), changes no other finding, and sends no request. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S117NoPrompt
$InvPath = Join-Path (Get-S117Bundle).FullName 'inventory.json'
$Inv = Get-Content -LiteralPath $InvPath -Raw | ConvertFrom-Json
Start-S117Count
$Plain = Test-OERStructure -Path $InvPath
$Named = Test-OERStructure -Path $InvPath -NamingStandard $Std
Write-OerLiveStep (Get-S117Sent)
Stop-S117Count
$Count = { param($V, $S) @($V.Errors | Where-Object { $_.Severity -eq $S }).Count }
Write-OerLiveStep "Without the standard: Valid $($Plain.Valid); Errors $(& $Count $Plain 'Error'); Warnings $(& $Count $Plain 'Warning')"
Write-OerLiveStep "With the standard: Valid $($Named.Valid); Errors $(& $Count $Named 'Error'); Warnings $(& $Count $Named 'Warning')"
$Other = @($Named.Errors | Where-Object { -not (Test-S117Naming -Finding $_) })
$Same = (ConvertTo-Json -InputObject @($Plain.Errors) -Depth 5 -Compress) -ceq (ConvertTo-Json -InputObject $Other -Depth 5 -Compress)
Write-OerLiveStep "Every other finding is the same, in the same order, with and without the standard: $Same; naming findings without the standard: $(@($Plain.Errors | Where-Object { Test-S117Naming -Finding $_ }).Count)"
Write-OerLiveStep "Names the standard covers: $(Get-S117NameCount -Doc $Inv)"
foreach ($Line in @(Get-S117NamingSummary -Validation $Named -Doc $Inv)) { Write-OerLiveStep $Line }
Disconnect-OerLive
```

**Expect:** `token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0`
-- the check sends nothing, with a session open in which it could; `Valid` the same with and without the
standard (`True` for an export); the Error count the same; every other finding the same; no naming finding
without the standard; every naming finding a `Warning`, every Item the name at its Path; the counts per
section and rule printed. The test tenant's names were not chosen for the neutral example, so most of them are
expected not to follow it.
**Failure looks like:** a request, a `Valid` or Error count that changes, a naming finding that is an Error,
an Item that is not the name at its Path, or another finding that differs (the check then touches more than
names).

Result:

### 1.3. A local copy with names the check invents

- [ ] **1.3** On a local copy of the export with eight invented entries added, a following name, an exception, a renamed entry and an optional segment give no finding; a wrong separator, a value outside the list and a template name give one rule Warning each; a synced group gives one "not checked" Warning; the copy stays valid. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S117NoPrompt
$InvPath = Join-Path (Get-S117Bundle).FullName 'inventory.json'
$Doc = Get-Content -LiteralPath $InvPath -Raw | ConvertFrom-Json
foreach ($Key in 'groups', 'administrativeUnits', 'catalogs', 'accessPackages') {
    if ($Doc.PSObject.Properties.Name -notcontains $Key) { $Doc | Add-Member -NotePropertyName $Key -NotePropertyValue @() }
}
$Base = @{ groups = @($Doc.groups).Count; administrativeUnits = @($Doc.administrativeUnits).Count; catalogs = @($Doc.catalogs).Count; accessPackages = @($Doc.accessPackages).Count }
$Doc.groups = @(@($Doc.groups) + @(
        [PSCustomObject]@{ displayName = 'SG-Finance-Readers'; members = $null },
        [PSCustomObject]@{ displayName = 'SG_Finance_Readers'; members = $null },
        [PSCustomObject]@{ template = 'SG-{area}-{purpose}'; tokens = [PSCustomObject]@{ area = 'Finance'; purpose = 'readers' }; members = $null },
        [PSCustomObject]@{ displayName = 'SG-Legal-Readers'; onPremisesSynced = $true; members = $null },
        [PSCustomObject]@{ displayName = 'SG-Finance-Owners'; previousDisplayName = 'old name without a standard'; members = $null }))
$Doc.administrativeUnits = @(@($Doc.administrativeUnits) + @([PSCustomObject]@{ displayName = 'All Users'; members = $null; scopedRoles = $null }))
$Doc.catalogs = @(@($Doc.catalogs) + @([PSCustomObject]@{ displayName = 'CAT-Legal-Documents'; resources = $null }))
$Doc.accessPackages = @(@($Doc.accessPackages) + @([PSCustomObject]@{ displayName = 'AP-IT-Laptops-Prod'; catalog = 'CAT-Legal-Documents'; resourceRoles = $null }))
$Copy = Join-Path $Raw 'control.json'
$Doc | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Copy -Encoding utf8NoBOM
Start-S117Count
$V = Test-OERStructure -Path $Copy -NamingStandard $Std
Write-OerLiveStep (Get-S117Sent)
Stop-S117Count
Write-OerLiveStep "The copy is valid: $($V.Valid)"
$Added = @(
    "groups[$($Base.groups)].displayName", "groups[$($Base.groups + 1)].displayName", "groups[$($Base.groups + 2)].template",
    "groups[$($Base.groups + 3)].displayName", "groups[$($Base.groups + 4)].displayName",
    "administrativeUnits[$($Base.administrativeUnits)].displayName", "catalogs[$($Base.catalogs)].displayName",
    "accessPackages[$($Base.accessPackages)].displayName")
$Labels = 'a following name', 'a wrong separator', 'a template name', 'a synced group', 'a renamed entry', 'an exception', 'a value outside the list', 'an optional segment present'
for ($I = 0; $I -lt $Added.Count; $I++) {
    $Mine = @($V.Errors | Where-Object { [string]$_.Path -ceq $Added[$I] -and (Test-S117Naming -Finding $_) })
    Write-OerLiveStep "$($Labels[$I]) (an added entry): $($Mine.Count) naming finding(s)"
    # The added entries carry names this check invents, so their messages may be printed.
    foreach ($F in $Mine) { Write-OerLiveStep ("  [{0}] {1}" -f $F.Severity, [string]$F.Message) }
}
Disconnect-OerLive
```

**Expect:** 0 requests; `The copy is valid: True`; a following name 0, a wrong separator 1 (`rule 'separator'`),
a template name 1 at `.template` (`rule 'case', segment 3 'purpose'` for `SG-Finance-readers`), a synced group 1
(`was not checked against the naming standard: the group is synchronized from on-premises`), a renamed entry 0
(its `previousDisplayName` is never checked), an exception 0, a value outside the list 1 (`rule 'values',
segment 2 'area'` for `Legal`), an optional segment present 0; every printed finding `[Warning]`.
**Failure looks like:** any other count, an Error, a request, or a copy that is not valid.

Result:

## 2. An invalid naming standard file

### 2.1. The file is refused, and nothing is validated

- [ ] **2.1** A standard file that breaks the schema, and a path that names no file, are each refused with `InvalidNamingStandard`, the message names what is wrong, no validation result is returned, and nothing is sent. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S117NoPrompt
$InvPath = Join-Path (Get-S117Bundle).FullName 'inventory.json'
$Obj = Get-Content -LiteralPath $Std -Raw | ConvertFrom-Json
$Obj.segments[0] | Add-Member -NotePropertyName case -NotePropertyValue 'Pascal' -Force
$Obj | Add-Member -NotePropertyName seperator -NotePropertyValue '_'
$Bad = Join-Path $Raw 'naming-standard-invalid.json'
$Obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Bad -Encoding utf8NoBOM
Start-S117Count
$R1 = Test-OERStructure -Path $InvPath -NamingStandard $Bad -ErrorAction SilentlyContinue -ErrorVariable E1
$R2 = Test-OERStructure -Path $InvPath -NamingStandard (Join-Path $Raw 'no-such-standard.json') -ErrorAction SilentlyContinue -ErrorVariable E2
Write-OerLiveStep (Get-S117Sent)
Stop-S117Count
foreach ($Case in @(@('a file that breaks the schema', $R1, $E1), @('a path that names no file', $R2, $E2))) {
    $Own = @($Case[2] | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' })
    Write-OerLiveStep "$($Case[0]): validation results returned: $(@($Case[1]).Count); InvalidNamingStandard errors: $($Own.Count); category: $(if ($Own) { $Own[0].CategoryInfo.Category })"
    if ($Own) { Write-OerLiveStep "  Message: $($Own[0].Exception.Message)" }
}
Disconnect-OerLive
```

**Expect:** 0 requests; for each case `validation results returned: 0`, `InvalidNamingStandard errors: 1`,
`category: InvalidData`; the first message names `seperator` (an unknown key) and `segments[0].case` (found
`Pascal`), the second says the naming standard was not found at the path.
**Failure looks like:** a validation result (the document was validated after all), another error id, a
message that does not say what is wrong, or a request.

Result:

## B. Proved offline (class B)

Each item is held by unit tests on this branch, run by `./build.ps1 -Tasks test`.

- **B.1 Each rule, its order and its text.** `tests/Unit/Private/Test-OERNamingStandardName.Tests.ps1`: a
  following name, a wrong separator, an empty segment, a missing required segment, too many segments, a value
  outside the list (with the letter-case hint), a pattern, each letter case, too long, an exception, an
  optional segment that is missing (no finding) and one that is forced, non-ASCII letters and metacharacters.
- **B.2 The file and its refusals.** `tests/Unit/Private/Read-OERNamingStandard.Tests.ps1` (every schema rule,
  the reader-only rules, every problem named in one message, a BOM, a file that is not found, empty or not
  JSON) and `tests/Unit/Private/Get-OERNamingStandardSchemaJson.Tests.ps1` (the schema, and that
  `docs/examples/naming-standard.schema.json` is the same).
- **B.3 Every section, a template group, a synced group with and without inclusion, `previousDisplayName`
  never checked, the document valid and malformed documents.** `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`,
  Describe "Rule 17, naming standard".
- **B.4 The parameter, the refusal and an exported inventory.json.** `tests/Unit/Public/Test-OERStructure.Tests.ps1`
  (read once, nothing validated after a refusal, a pipeline, `-ErrorAction Stop`, a script with no `try`) and
  `tests/Unit/Public/Export-OERInventory.Tests.ps1` (the real export writes `inventory.json`, and the check on
  it gives the exact Paths).
- **B.5 The texts.** `tests/QA/about.tests.ps1`, `tests/QA/docsync.tests.ps1`, `tests/QA/dochygiene.tests.ps1`
  and `tests/QA/module.tests.ps1` (help, the release note budget).

## T. Teardown

### T.1. Nothing was created, and the step's raw folders are gone

- [ ] **T.1** No object with the prefix `oer-s117-` exists, and the step's raw folders are deleted. The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check. #type/subtask

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed -Prefix 'oer-s117-' -ThrowOnUnread)
Write-OerLiveStep "Objects carrying the prefix oer-s117-: $($Found.Count)"
Disconnect-OerLive
foreach ($Dir in @($Raw, (Join-Path $Cfg.Repo 'docs\live-verification\raw\s117')) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    Write-OerLiveStep "Raw folder deleted: $(-not (Test-Path -LiteralPath $Dir))"
}
```

**Expect:** `Objects carrying the prefix oer-s117-: 0`; every raw folder deleted (`True`).
**Failure looks like:** a prefixed object (this checklist creates none: STOP and find who made it), or a folder
left behind.

Result:
