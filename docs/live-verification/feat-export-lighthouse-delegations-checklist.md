# Live verification checklist -- Azure Lighthouse delegations are exported as read-only context (feat/export-lighthouse-delegations)

**This branch does not merge until every box in sections S, 0, M, 1, 2 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to
be impossible to run, write "cannot be verified, and therefore we do not know" on its result line and
say why; do not leave it blank and do not tick it. A check that could not run for a stated reason is
marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** One manual check
(class C) is foreseen and does not block the merge: an export of a tenant that holds a real Azure
Lighthouse delegation (section C).

**What this file writes to the tenant: nothing.** Every check reads. No object is created, so there is
no prerequisite script and no prefixed object; the prefix `oer-s116b-` names only the step's raw folder
and a resource group name that must NOT exist (check M.2). Bundles and documents are written under
`raw\s116b\`, which is deleted after the results are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, and for the 403 checks
`oer-live-cc-noperm`, through the OerLive library, which lives beside the operator's copy of this file
outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only, with the
certificate; nothing here signs in as a person. A 401 or 403 as `oer-live-cc` is a stop; a 403 as
`oer-live-cc-noperm` is what sections M.4 and 2 expect.

**Permissions.** The read needs nothing beyond the Azure role Reader on the subscription, whose `*/read`
covers `Microsoft.ManagedServices/registrationAssignments/read` and
`Microsoft.ManagedServices/registrationDefinitions/read`; `oer-live-cc` holds its existing role on the
test subscription, and `oer-live-cc-noperm` holds no Azure role at all. Granting a permission is the
operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm` (or `-Arm -NoPerm`), which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False, and every
block that runs the module installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s116b/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** A warning and an error that stops a script go straight to the
host, so each block is run in its own process whose WHOLE output (standard output and standard error) is
written to a file under `raw\s116b\`, redacted with OerLive's redactor before anyone reads it, and then
deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The read** ("feat: read the Azure Lighthouse delegations of the subscriptions an export walks",
  "feat: write lighthouseDelegations.json and list the delegations in the export README", and the `test:`
  commits beside them). `Export-OERInventory` reads the Azure Lighthouse delegations at the subscriptions
  its Azure walk visits, whenever an Azure section is included: the registration assignments (with their
  definitions) and the registration definitions of each subscription, api-version `2022-10-01`; a
  definition no assignment of the subscription references makes it read the assignments of each resource
  group; the role names are read once per role. It writes `lighthouseDelegations.json`, one row per
  delegation, always a JSON array (`[]` when there is none), as read-only context with no apply section,
  warns once when it read any, and its README lists them under "Azure Lighthouse delegations (access from
  another tenant)".
- **B. A failed read** ("feat: name a failed Azure Lighthouse read in IncompleteReads and make the export
  partial"). A subscription whose delegations could not be read is named in `IncompleteReads` as
  `lighthouseDelegations at <scope>` and none of its delegations is written; a role whose name could not
  be read as `lighthouseDelegations role <id>`; both make the export `InventoryPartial`, with a clause of
  their own, and the README lists them under "What this export could not read".
- **C. The direction of a delegation** ("fix: mark an Azure Lighthouse delegation this tenant manages, and
  word the warning without a direction"). In a managing tenant the walk also reaches the customer
  subscriptions delegated to it; the README marks a delegation whose managing tenant is the exported
  tenant itself, and the warning names no direction.
- **D. The texts** ("docs: describe lighthouseDelegations.json in the export help, the prompt, README and
  the about topic", "docs: record the Azure Lighthouse measurement, rulings, limits and mutation proofs in
  the rationale", "docs: say how to read the direction of an Azure Lighthouse delegation, and record
  Ruling R-12", "docs: record the mutation proofs of the final fix wave in the rationale"): help, the
  prompt template, README, the about topic, the inventory-to-LLM guide, the rationale and the release
  note.
A live tenant is needed because the claims are about what Azure Resource Manager answers for
`Microsoft.ManagedServices` at a subscription and at a resource group, for an identity with and without
an Azure role, and what the export then writes: an empty file after a read that succeeded, a named, partial
read after one that was refused, and an `inventory.json` that is the same as `main`'s.

## What this file does not check, and why

- **A real delegation (class B, B.1 to B.4, and class C, C.1).** The test tenant has no managing tenant,
  so no delegation can be made to it here. The unit tests hold a delegation at a subscription and at a
  resource group, several authorizations, eligible ones, and every failed read, with responses shaped
  after Microsoft Learn's examples.
- **Whether a subscription's list returns the delegations of its resource groups (class C, C.1).**
  Microsoft Learn does not say; the read finds such a delegation either way (rationale.md,
  `#lighthouse-delegations`), and C.1 records the answer when a tenant has one.
- **The texts (class B, B.5).** Section B names the gates that hold them.

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

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence, the counters
and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s116b-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
$Ms = 'providers/Microsoft.ManagedServices'
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }

function Start-S116bNoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S116bTokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S116bTokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S116b fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S116bCount {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is a
    # GET. The path of every request is recorded, the query dropped.
    $global:S116bGraph = [System.Collections.Generic.List[string]]::new()
    $global:S116bArm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116bGraph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S116bArm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S116bCount {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S116bSent {
    # Requests counted since Start-S116bCount: totals, writes (any method but GET; getByIds is a read sent
    # as POST), and the Lighthouse reads by kind.
    $GraphWrites = @($global:S116bGraph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */directoryObjects/getByIds' })
    $ArmWrites = @($global:S116bArm | Where-Object { -not $_.StartsWith('GET ') })
    $Assign = @($global:S116bArm | Where-Object { $_ -like "GET */$Ms/registrationAssignments" }).Count
    $Defs = @($global:S116bArm | Where-Object { $_ -like "GET */$Ms/registrationDefinitions" }).Count
    $Groups = @($global:S116bArm | Where-Object { $_ -like 'GET */resourcegroups' -or $_ -like 'GET */resourceGroups' }).Count
    "token requests: $global:S116bTokenCalls; Microsoft Graph requests: $($global:S116bGraph.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S116bArm.Count), writes: $($ArmWrites.Count); Lighthouse reads: registrationAssignments $Assign, registrationDefinitions $Defs, resource group listings $Groups"
}

function Show-S116bRead {
    # One ARM read as status, code, count and top-level keys; the message only for a failure (redacted).
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$R)
    $Count = if ($R.Ok -and $null -ne $R.Body) { @($R.Body.value | Where-Object { $null -ne $_ }).Count } else { 'n/a' }
    $Keys = if ($R.Ok -and $null -ne $R.Body) { (@($R.Body.PSObject.Properties.Name) -join ',') } else { '' }
    Write-OerLiveStep ("{0}: Ok={1} Status={2} Code={3} Count={4} TopKeys={5}" -f $Label, $R.Ok, $R.Status, $R.Code, $Count, $Keys)
    if (-not $R.Ok) { Write-OerLiveStep ("{0}: Message={1}" -f $Label, $R.Message) }
}

function Get-S116bBundle {
    # The newest bundle folder under one of the step's export folders.
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -LiteralPath (Join-Path $Raw $Name) -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Get-S116bReadmeSection {
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

function ConvertTo-S116bCanonical {
    # A JSON value in a form that does not depend on order: object keys sorted, and array elements
    # sorted by their own canonical JSON (Microsoft Graph returns members and owners in no fixed order).
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $O = [ordered]@{}
        foreach ($K in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $O[$K] = ConvertTo-S116bCanonical -Value $Value[$K] }
        return $O
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $Items = @(foreach ($V in $Value) { , (ConvertTo-S116bCanonical -Value $V) })
        return , @($Items | Sort-Object { ConvertTo-Json -InputObject $_ -Depth 60 -Compress })
    }
    $O = [ordered]@{}
    foreach ($K in @($Value.PSObject.Properties.Name | Sort-Object)) { $O[$K] = ConvertTo-S116bCanonical -Value $Value.$K }
    $O
}

function Get-S116bFileCanonical {
    # A bundle file as canonical, compressed JSON text.
    param([Parameter(Mandatory)][string]$Path)
    ConvertTo-Json -InputObject (ConvertTo-S116bCanonical -Value (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate)) -Depth 60 -Compress
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
Write-OerLiveStep "The worktree's build reads the Lighthouse delegations: $(& $Has 'function Get-OERInventoryLighthouseDelegation')"
Write-OerLiveStep "The worktree's build converts a delegation into a row: $(& $Has 'function ConvertTo-OERLighthouseDelegation')"
Write-OerLiveStep "The worktree's build writes lighthouseDelegations.json: $(& $Has "'lighthouseDelegations.json'")"
Write-OerLiveStep "The worktree's build names a failed Lighthouse read: $(& $Has 'lighthouseDelegations at ')"
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
Start-S116bNoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's build:
True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

## M. The measurement behind the read (reads only)

### M.1. The subscription's two lists as oer-live-cc

- [ ] **M.1** The registration assignment list (with and without `$expandRegistrationDefinition`) and the registration definition list of the test subscription answer, and what the resource provider's registration state is.

```powershell
Connect-OerLive -Arm
Start-S116bNoPrompt
$A = Invoke-OerLiveArm -All -Path "$SubScope/$Ms/registrationAssignments?`$expandRegistrationDefinition=true&api-version=2022-10-01"
Show-S116bRead 'Subscription registrationAssignments (expand, 2022-10-01)' $A
$A1 = Invoke-OerLiveArm -Path "$SubScope/$Ms/registrationAssignments?api-version=2022-10-01"
Show-S116bRead 'Subscription registrationAssignments (no expand, one page)' $A1
if ($A1.Ok) { Write-OerLiveStep ('Body: ' + (ConvertTo-OerLiveRedacted -Text (ConvertTo-Json -InputObject $A1.Body -Depth 6 -Compress))) }
$D = Invoke-OerLiveArm -All -Path "$SubScope/$Ms/registrationDefinitions?api-version=2022-10-01"
Show-S116bRead 'Subscription registrationDefinitions (2022-10-01)' $D
$P = Invoke-OerLiveArm -Path "$SubScope/providers/Microsoft.ManagedServices?api-version=2025-04-01"
Show-S116bRead 'Microsoft.ManagedServices at the subscription' $P
if ($P.Ok) { Write-OerLiveStep "Resource provider registration state: $([string]$P.Body.registrationState)" }
Disconnect-OerLive
```

**Expect:** the three lists `Ok=True Status=200 Count=0 TopKeys=value`, the one-page body `{"value":[]}`;
the registration state printed (the lists answer whatever it is).
**Failure looks like:** a 401 or 403 (STOP: a missing permission on the app path), or a list that is not
empty (the tenant then has a delegation, and C.1 can be run here).

Result:

### M.2. A resource group's list, and the definitions at a resource group

- [ ] **M.2** One resource group's registration assignment list answers, a registration definition list at a resource group is refused, and an assignment list at a resource group that does not exist answers.

```powershell
Connect-OerLive -Arm
Start-S116bNoPrompt
$G = Invoke-OerLiveArm -All -Path "$SubScope/resourcegroups?api-version=2025-04-01"
Show-S116bRead 'Resource groups of the subscription' $G
$Rg = @($G.Body.value | Where-Object { $null -ne $_ }) | Select-Object -First 1
if ($Rg) {
    $RA = Invoke-OerLiveArm -All -Path "$($Rg.id)/$Ms/registrationAssignments?`$expandRegistrationDefinition=true&api-version=2022-10-01"
    Show-S116bRead 'One resource group: registrationAssignments (expand)' $RA
    $RD = Invoke-OerLiveArm -All -Path "$($Rg.id)/$Ms/registrationDefinitions?api-version=2022-10-01"
    Write-OerLiveStep "One resource group: registrationDefinitions: Ok=$($RD.Ok) Code=$($RD.Code)"
} else { Write-OerLiveStep 'The subscription holds no resource group.' }
$X = Invoke-OerLiveArm -Path "$SubScope/resourceGroups/oer-s116b-doesnotexist/$Ms/registrationAssignments?api-version=2022-10-01"
Show-S116bRead 'A resource group that does not exist: registrationAssignments' $X
Disconnect-OerLive
```

**Expect:** the resource group's list `Ok=True Status=200 Count=0`; the definitions at a resource group
`Ok=False Code=InvalidRegistrationDefinitionUri` (definitions are allowed at a subscription only); the list
at the resource group that does not exist `Ok=True Status=200 Count=0`.
**Failure looks like:** a 401 or 403 (STOP), or a definition list that answers at a resource group (then
the read's resource group fallback needs another look).

Result:

### M.3. A role definition read by its id

- [ ] **M.3** A built-in role definition read by its id at the subscription answers with its name, and an id that names no role definition answers `RoleDefinitionDoesNotExist`.

```powershell
Connect-OerLive -Arm
Start-S116bNoPrompt
$L = Invoke-OerLiveArm -Path "$SubScope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20'Reader'"
$ReaderGuid = [string](@($L.Body.value) | Select-Object -First 1).name
$R = Invoke-OerLiveArm -Path "$SubScope/providers/Microsoft.Authorization/roleDefinitions/$($ReaderGuid)?api-version=2022-04-01"
Show-S116bRead 'Role definition read by the id of Reader' $R
if ($R.Ok) { Write-OerLiveStep "roleName: $([string]$R.Body.properties.roleName); type: $([string]$R.Body.properties.type)" }
$U = Invoke-OerLiveArm -Path "$SubScope/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000099?api-version=2022-04-01"
Show-S116bRead 'Role definition read by an id that names none' $U
Disconnect-OerLive
```

**Expect:** `roleName: Reader; type: BuiltInRole`; the second read `Ok=False Code=RoleDefinitionDoesNotExist`.
**Failure looks like:** another code for the second read (the read's not-found test needs it too).

Result:

### M.4. The two lists as oer-live-cc-noperm (no Azure role)

- [ ] **M.4** Without an Azure role both lists are refused with `AuthorizationFailed`, naming the two read actions Reader covers.

```powershell
Connect-OerLive -Arm -NoPerm
Start-S116bNoPrompt
$NA = Invoke-OerLiveArm -All -Path "$SubScope/$Ms/registrationAssignments?`$expandRegistrationDefinition=true&api-version=2022-10-01"
Show-S116bRead 'noperm: subscription registrationAssignments' $NA
$ND = Invoke-OerLiveArm -All -Path "$SubScope/$Ms/registrationDefinitions?api-version=2022-10-01"
Show-S116bRead 'noperm: subscription registrationDefinitions' $ND
Disconnect-OerLive
```

**Expect:** both `Ok=False Status=403 Code=AuthorizationFailed`, the messages naming
`Microsoft.ManagedServices/registrationAssignments/read` and
`Microsoft.ManagedServices/registrationDefinitions/read`.
**Failure looks like:** a 200 (the identity holds a role it should not), or another code.

Result:

## 1. An export of the test subscription as oer-live-cc

### 1.1. lighthouseDelegations.json is [] after a read that succeeded

- [ ] **1.1** An export of the test subscription writes `lighthouseDelegations.json` as `[]`, names no Lighthouse read unread, and its README and prompt name the file.

```powershell
Connect-OerLive -Arm
Start-S116bNoPrompt
Start-S116bCount
$Out = Join-Path $Raw 'export-branch'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116bSent)
Stop-S116bCount
$File = Join-Path $Bundle.BundlePath 'lighthouseDelegations.json'
Write-OerLiveStep "lighthouseDelegations.json exists: $(Test-Path -LiteralPath $File); its text: $((Get-Content -LiteralPath $File -Raw).Trim())"
Write-OerLiveStep "Files lists it: $($Bundle.Files -contains 'lighthouseDelegations.json'); azurePimEligibility.json beside it: $($Bundle.Files -contains 'azurePimEligibility.json')"
Write-OerLiveStep "IncompleteReads entries naming Lighthouse: $(@($Bundle.IncompleteReads | Where-Object { [string]$_ -like 'lighthouseDelegations*' }).Count); IncompleteReads: $(@($Bundle.IncompleteReads).Count); SkippedScopes: $(@($Bundle.SkippedScopes).Count)"
Write-OerLiveStep "Errors: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Write-OerLiveStep "Lighthouse warnings: $(@($ExportWarnings | Where-Object { [string]$_ -like '*Lighthouse*' }).Count)"
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
$Section = @(Get-S116bReadmeSection -Text $Readme -Heading 'Azure Lighthouse delegations')
Write-OerLiveStep "README section 'Azure Lighthouse delegations (access from another tenant)': $($Section.Count -gt 0); says None: $([bool]($Section -match '^None\.'))"
Write-OerLiveStep "README Files list names lighthouseDelegations.json: $([bool](@(Get-S116bReadmeSection -Text $Readme -Heading 'Files') -match 'lighthouseDelegations\.json'))"
$Prompt = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'rbac-architect-prompt.md') -Raw
Write-OerLiveStep "The prompt names lighthouseDelegations.json: $($Prompt.Contains('lighthouseDelegations.json'))"
Disconnect-OerLive
```

**Expect:** the file exists and its text is `[]`; `Files` lists it beside `azurePimEligibility.json`; no
`IncompleteReads` entry names Lighthouse; no Lighthouse warning; the Lighthouse reads
`registrationAssignments 1, registrationDefinitions 1, resource group listings 0`; Microsoft Graph and Azure
Resource Manager `writes: 0`; `token requests: 0`; the README section is there and says `None.`; the README
Files list and the prompt name the file.
**Failure looks like:** no file, a file that is not `[]`, a Lighthouse entry in `IncompleteReads`, a write,
or a token request (the fence would have refused it).

Result:

### 1.2. inventory.json is the same as main's

- [ ] **1.2** The same export with `main`'s source (`d153e9d`, loaded in dev mode from a `git archive` copy under `raw\s116b\`) writes an `inventory.json` and per-area files equal to this branch's, and the two bundles differ by `lighthouseDelegations.json` alone.

```powershell
$Src = Join-Path $Raw 'main-src'
if (-not (Test-Path -LiteralPath (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1'))) {
    $Zip = Join-Path $Raw 'main-src.zip'
    git -C $Cfg.Repo archive --format=zip -o $Zip d153e9d source
    Expand-Archive -LiteralPath $Zip -DestinationPath $Src -Force
    Remove-Item -LiteralPath $Zip
}
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1') -Force -Global
Write-OerLiveStep "main's source is loaded (dev mode, no Lighthouse read): $(-not (Get-Command -Name Get-OERInventoryLighthouseDelegation -ErrorAction SilentlyContinue)) and $([bool](Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith($Src, [System.StringComparison]::OrdinalIgnoreCase))"
Connect-OerLive -Arm
Start-S116bNoPrompt
$Out = Join-Path $Raw 'export-main'
$null = New-Item -ItemType Directory -Path $Out -Force
$MainBundle = Export-OERInventory -OutputPath $Out -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable MainErrors 3>$null
Disconnect-OerLive
$Branch = Get-S116bBundle -Name 'export-branch'
$Main = Get-Item -LiteralPath $MainBundle.BundlePath
$BranchFiles = @(Get-ChildItem -LiteralPath $Branch.FullName -File | ForEach-Object Name | Sort-Object)
$MainFiles = @(Get-ChildItem -LiteralPath $Main.FullName -File | ForEach-Object Name | Sort-Object)
Write-OerLiveStep "Files only in this branch's bundle: $(@($BranchFiles | Where-Object { $MainFiles -notcontains $_ }) -join ', '); only in main's: $(@($MainFiles | Where-Object { $BranchFiles -notcontains $_ }) -join ', ')"
foreach ($Name in @($MainFiles | Where-Object { $_ -like '*.json' -and $_ -ne 'schema.json' })) {
    $Same = (Get-S116bFileCanonical -Path (Join-Path $Branch.FullName $Name)) -ceq (Get-S116bFileCanonical -Path (Join-Path $Main.FullName $Name))
    Write-OerLiveStep "$Name equal: $Same"
}
Write-OerLiveStep "schema.json equal: $((Get-Content -LiteralPath (Join-Path $Branch.FullName 'schema.json') -Raw) -ceq (Get-Content -LiteralPath (Join-Path $Main.FullName 'schema.json') -Raw))"
Write-OerLiveStep "main's errors: $(@($MainErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
```

**Expect:** main's source loaded (`True and True`); the only file only in this branch's bundle is
`lighthouseDelegations.json`, none only in main's; every JSON file `equal: True` -- `inventory.json` and every
per-area file, the roster and the hierarchy, with arrays compared without regard to order -- and
`schema.json` byte-equal.
**Failure looks like:** `inventory.json equal: False` (the branch changed the apply document), or another
file only in one bundle. A difference in a file that reads live state (the roster, a group's members) can
also mean the tenant changed between the two exports: run 1.1 and 1.2 again before reading it as a defect.

Result:

## 2. An export without an Azure role (oer-live-cc-noperm)

### 2.1. The read is named as unread and the export is partial

- [ ] **2.1** As `oer-live-cc-noperm`, an export of the test subscription names `lighthouseDelegations at` the subscription last in `IncompleteReads`, raises `InventoryPartial` with a Lighthouse clause, and its README lists the read as failed; the file is `[]` and does not stand for "none" alone.

```powershell
Connect-OerLive -Arm -NoPerm
Start-S116bNoPrompt
Start-S116bCount
$Out = Join-Path $Raw 'export-noperm'
$null = New-Item -ItemType Directory -Path $Out -Force
$Bundle = Export-OERInventory -OutputPath $Out -Include RoleAssignments -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S116bSent)
Stop-S116bCount
$File = Join-Path $Bundle.BundlePath 'lighthouseDelegations.json'
Write-OerLiveStep "lighthouseDelegations.json exists: $(Test-Path -LiteralPath $File); its text: $((Get-Content -LiteralPath $File -Raw).Trim())"
$Entries = @($Bundle.IncompleteReads)
Write-OerLiveStep "IncompleteReads ($($Entries.Count)): $(($Entries | ForEach-Object { ConvertTo-OerLiveRedacted -Text ([string]$_) }) -join ' | ')"
Write-OerLiveStep "The last entry is the subscription's Lighthouse read: $([string]$Entries[-1] -eq "lighthouseDelegations at $SubScope")"
Write-OerLiveStep "SkippedScopes: $(@($Bundle.SkippedScopes).Count); SkippedEligibilityScopes: $(@($Bundle.SkippedEligibilityScopes).Count)"
$Partial = @($ExportErrors | Where-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] -eq 'InventoryPartial' })
Write-OerLiveStep "InventoryPartial: $($Partial.Count); its Lighthouse clause: $(if ($Partial.Count) { [bool]([string]$Partial[0].Exception.Message -match 'Azure Lighthouse read\(s\) failed') } else { $false }); the clause names AuthorizationFailed: $(if ($Partial.Count) { [bool]([string]$Partial[0].Exception.Message -match 'Causes of the unread Azure Lighthouse reads: AuthorizationFailed') } else { $false })"
Write-OerLiveStep "Error ids: $(@($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Write-OerLiveStep "Lighthouse warnings: $(@($ExportWarnings | Where-Object { [string]$_ -like '*Azure Lighthouse delegations at scope*' }).Count)"
$Readme = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'README.md') -Raw
$Could = @(Get-S116bReadmeSection -Text $Readme -Heading 'What this export could not read')
Write-OerLiveStep "README 'What this export could not read' lists it under 'Azure Lighthouse read that failed': $([bool]($Could -match '^- Azure Lighthouse read that failed: `lighthouseDelegations at '))"
Disconnect-OerLive
```

**Expect:** the file exists and holds `[]`; the last `IncompleteReads` entry is `lighthouseDelegations at`
the subscription (`True`); the subscription in `SkippedScopes` and `SkippedEligibilityScopes` (its role
assignment and eligibility reads are refused too); one `InventoryPartial` whose message carries the
Lighthouse clause and names `AuthorizationFailed`; one Lighthouse warning; the README bullet `True`; the
Lighthouse reads `registrationAssignments 1, registrationDefinitions 0, resource group listings 0` (the
first refusal ends the subscription's read); `writes: 0`; `token requests: 0`.
**Failure looks like:** no `lighthouseDelegations at` entry, no `InventoryPartial`, a Lighthouse entry that is
not last, or a definition read after the refusal.

Result:

## B. Proved offline (class B)

Each item is held by unit tests on this branch, run by `./build.ps1 -Tasks test`. The fixtures are shaped
after Microsoft Learn's examples for Registration Assignments - List and Registration Definitions - List,
with invented ids.

- **B.1 A delegation at a subscription, with several authorizations and an eligible one.**
  `tests/Unit/Private/ConvertTo-OERLighthouseDelegation.Tests.ps1` (the row shape, the property order and
  the arrays) and `tests/Unit/Private/Get-OERInventoryLighthouseDelegation.Tests.ps1`, Context "a delegation
  at a subscription"; `tests/Unit/Public/Export-OERInventory.Tests.ps1`, "writes lighthouseDelegations.json
  as an array of the rows the reader returned, every field kept, and lists it in Files", "warns exactly once
  with the count of delegations when there are some" and "lists both delegations in the README section,
  names the file, and writes no principal there".
- **B.2 A delegation at a resource group**, found through the fallback (a definition no assignment of the
  subscription references) and through the subscription's own list: the reader's Contexts "a delegation at
  a resource group" and "which scopes are read" (a scope below a subscription keeps the delegations at the
  subscription and at its resource group).
- **B.3 A failed read.** Whole or nothing per subscription, a missing definition, a failed resource group
  listing or read, and the export's naming, partial clause and README label: the reader's Context "a failed
  read" and the Export Context "a failed Azure Lighthouse read is named in IncompleteReads and makes the
  export partial (Scope item 2)".
- **B.4 Role names.** One read per role; not found leaves `roleName` null and is not unread; any other
  failure is named: the reader's Context "the role names".
- **B.5 The texts.** `tests/QA/about.tests.ps1`, `tests/QA/docsync.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/QA/module.tests.ps1` (help, the release note budget) and `tests/QA/sourcehygiene.tests.ps1` (the
  api-version `2022-10-01` documented under `rationale.md#arm-transport`).

## C. Manual check for the operator (class C, does not block the merge)

### C.1. An export of a tenant that holds a real Azure Lighthouse delegation

- [ ] **C.1** (P-15, Philip, after the merge, optional) Export a tenant where a managing tenant has a delegation at a subscription, and if possible one at a resource group.

Run `Export-OERInventory -Include RoleAssignments` against such a tenant with an identity that holds
Reader on the delegated subscription.

**Expect:** one Lighthouse warning with the count; `lighthouseDelegations.json` holds one row per
delegation with the managing tenant's id and name, the offer name and each authorization (principal id,
display name, role id and role name), eligible ones under `eligibleAuthorizations`; the README section
lists each one; `roleAssignments.json` does not show that access. Record also whether the resource group
delegation was found in the subscription's own list (`resource group listings 0` in the request count) or
through the fallback -- the open question of `rationale.md#lighthouse-delegations`. Where the operator also
runs a MANAGING tenant, export it too: the customer subscriptions delegated to it are walked, and a row whose
`managedByTenantId` is that tenant's own id is marked in the README as access it holds over another tenant
(Ruling R-12; whether those reads answer or are refused is not measured).
**Failure looks like:** a delegation missing from the file, a row without the managing tenant, or a
`roleName` null for a built-in role.

Result:

## T. Teardown

### T.1. Nothing was created, and the step's raw folders are gone

- [ ] **T.1** No object with the prefix `oer-s116b-` exists, and the step's raw folders are deleted. The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check.

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed -Prefix 'oer-s116b-' -ThrowOnUnread)
Write-OerLiveStep "Objects carrying the prefix oer-s116b-: $($Found.Count)"
Disconnect-OerLive
foreach ($Dir in @($Raw, (Join-Path $Cfg.Repo 'docs\live-verification\raw\s116b')) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    Write-OerLiveStep "Raw folder deleted: $(-not (Test-Path -LiteralPath $Dir))"
}
```

**Expect:** `Objects carrying the prefix oer-s116b-: 0`; every raw folder deleted (`True`).
**Failure looks like:** a prefixed object (this checklist creates none: STOP and find who made it), or a
folder left behind.

Result:
