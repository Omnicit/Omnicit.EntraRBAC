# Live verification checklist -- service principal access, scoped-role principal types and the inventory home-tenant check (feat/service-principal-access)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A box
with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be
impossible to run, write "cannot be verified, and therefore we do not know" on its result line and say
why; do not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** No manual check (class C)
is foreseen.

**What this file writes to the tenant: nothing.** Every tenant call reads. No object is created, so there is
no prerequisite script and no prefixed object; the prefix `oer-s118-` names only the step's raw folder. The
export bundles, the comparison files and the base build the comparisons load go under `raw\s118\`, which is
deleted after the results are written. No write path changes in this step, so there is no convergence check
(G8).

**The tenant's object names are never printed.** `servicePrincipalAccess.json` names every service
principal, app registration, owner and user it lists, and an inventory names the tenant's objects. The blocks
therefore print counts only -- per part and per request kind -- and the export's own warnings are captured and
counted, never printed. The one list of names a block prints is the test identity's own application
permissions in 1.1: Microsoft Graph permission names (`Group.Read.All`, for example), the same in every
tenant, which is what the check is about.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives
beside the operator's copy of this file outside the repository ([README.md](README.md), first paragraph);
check 1.3 signs in as `oer-live-cc-noperm`, which holds no permission, to produce a 403 on every part. Every
sign-in is app-only, with the certificate; nothing here signs in as a person. A 401 or 403 is a stop, except
in 1.3, which tests exactly that.

**Permissions.** The reads use the permissions `oer-live-cc` already holds. Microsoft Learn's tables decide
what the switch needs (Directory.Read.All covers every read); a green run here does not prove that, since
`oer-live-cc` holds more. Granting a permission is the operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm` (or `-Arm -NoPerm` in 1.3), which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block
that runs the module installs the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s118/`, which is
git-ignored. Every block prints through the library's redactor, so its lines are already redacted per
[README.md](README.md). **No credential, token, application id, tenant id, subscription id, account or
certificate thumbprint is ever printed.** Each block is run in its own process whose WHOLE output (every
stream) is written to a file outside the repository, redacted with OerLive's redactor before anyone reads it,
and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Service principal access** ("feat: export service principal access behind -IncludeServicePrincipalAccess",
  "fix: name grant principals by display name and user principal name"). `Export-OERInventory
  -IncludeServicePrincipalAccess` writes `servicePrincipalAccess.json`: the service principals' application
  permissions (app role assignments, with the resource's name and the permission's value), the delegated
  permission grants, and the owners of app registrations and service principals, every row naming its objects
  by id and name. It is read-only context, never applied. A part that could not be read is `null` and named in
  `IncompleteReads`. Without the switch the export is unchanged.
- **B. Scoped-role principal types** ("feat: write principalType on administrative unit scoped roles"). An
  inventory writes `principalType` on an administrative unit's scoped role whose principal the directory
  returned; apply does not use it to match or write.
- **C. The inventory's home tenant** ("fix: keep Get-OERInventory out of another tenant's subscriptions", "fix:
  acquire the ARM token before the inventory's home-tenant check", "fix: ask for the ARM token only when a role
  policy section will read"). `Get-OERInventory` reads no role assignment or policy in a subscription of
  another tenant, reports one it cannot decide as unread, and inside an export costs no extra request.
- **D. The texts** ("test: gate the service principal access paths in requiredscope", "fix: explain an unread
  scoped role principalType in the bundle and correct the step's help", "docs: document service principal
  access, scoped-role principal types and the inventory home-tenant check", "docs: keep every release-note fact
  and correct the step's texts", "docs: tighten the release note and the service principal access texts").

A live tenant is needed for what the unit tests cannot show: the real shape and cost of the reads in a tenant
with a thousand service principals, the identity's own permissions as the file names them, an export without
the switch that sends exactly what the previous build sent, and the home-tenant check on a real subscription.

## What this file does not check, and why

- **A subscription of another tenant (class B, B.1).** The test tenant has no delegated subscription; the unit
  tests hold the refusal.
- **A scoped role in the test tenant, if it has none (class B, B.2).** Check 2.1 counts them; with none, the
  unit tests hold the types.
- **A 403 on one part only, an object with 20 or more expanded entries, and an empty tenant (class B, B.3).**
  The identity's permissions cannot be cut per part, and no object in the test tenant reaches 20.
- **The export's request count with the run context's shared answers (class B, B.4)** beyond what 1.2 measures.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it
  (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`,
  and the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it, so
  the module loads from the worktree's build; the main clone is never checked out on another commit or branch
  (S.1 reads that it was not).
- **A build of the base commit** (`12d9901`, the `main` this branch started from), copied before the branch's
  first commit to `raw\s118\before-12d9901\output\module` in the worktree. Checks 1.2a and 3.1a load it in
  their own process to measure what the export and the inventory sent before this branch.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence, the counters and
the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s118-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Work = Join-Path $Cfg.Repo 'docs\live-verification\raw\s118'
$Base = Join-Path $Work 'before-12d9901'
$Include = 'AdministrativeUnits', 'RoleAssignments'
$null = New-Item -ItemType Directory -Path $Work -Force

function Use-S118BaseBuild {
    # Before Connect-OerLive: the module then loads from the base build, with the worktree's RequiredModules.
    $Cfg.Repo = $Base
    $env:PSModulePath = (Join-Path $env:OER_LIVE_REPO 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
}

function Start-S118NoPrompt {
    # A token request without the certificate would be an interactive or device-code sign-in: refuse it.
    $global:S118TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S118TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S118 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S118Count {
    # Counts every request the module sends: Microsoft Graph through a global proxy of Invoke-MgGraphRequest,
    # Azure Resource Manager through one of Invoke-WebRequest. Each entry is the method, the path with every
    # GUID segment written {id}, and for Graph the relationship a $expand names. Ids are never recorded.
    $global:S118TokenCalls = 0
    $global:S118Graph = [System.Collections.Generic.List[string]]::new()
    $global:S118Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Shape = '$(Get-S118Shape -Uri ([string]$Uri))'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S118Graph.Add((`$($Record)) + ' ' + $Shape); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S118Arm.Add((`$($Record)) + ' ' + $Shape); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function global:Get-S118Shape {
    # The request's path with each GUID segment as {id}, then ' expand=' and the relationship when the query expands one.
    param([string]$Uri)
    $Path = $Uri; $Query = ''
    if ([uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) { $U = [uri]$Uri; $Path = $U.AbsolutePath; $Query = $U.Query }
    elseif ($Uri.Contains('?')) { $Path = $Uri.Substring(0, $Uri.IndexOf('?')); $Query = $Uri.Substring($Uri.IndexOf('?')) }
    $Path = '/' + $Path.TrimStart('/')
    $Path = $Path -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}'
    $Query = [uri]::UnescapeDataString($Query)
    if ($Query -match '[?&]\$expand=([A-Za-z]+)') { "$Path expand=$($Matches[1])" } else { $Path }
}

function Stop-S118Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S118Sent {
    # Totals and writes since Start-S118Count (getByIds is a read sent as POST).
    $GraphWrites = @($global:S118Graph | Where-Object { -not $_.StartsWith('GET ') -and $_ -notlike 'POST */directoryObjects/getByIds' })
    $ArmWrites = @($global:S118Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S118TokenCalls; Microsoft Graph requests: $($global:S118Graph.Count), writes: $($GraphWrites.Count); Azure Resource Manager requests: $($global:S118Arm.Count), writes: $($ArmWrites.Count)"
}

function Get-S118SpAccessRequests {
    # The Graph requests that belong to the service principal access read, counted per kind.
    $Kinds = [ordered]@{
        'service principal list with app role assignments' = 'GET /v1.0/servicePrincipals expand=appRoleAssignments'
        'full app role assignment re-reads' = 'GET /v1.0/servicePrincipals/{id}/appRoleAssignments'
        'service principal list with owners' = 'GET /v1.0/servicePrincipals expand=owners'
        'full service principal owner re-reads' = 'GET /v1.0/servicePrincipals/{id}/owners'
        'app registration list with owners' = 'GET /v1.0/applications expand=owners'
        'full app registration owner re-reads' = 'GET /v1.0/applications/{id}/owners'
        'delegated permission grant list' = 'GET /v1.0/oauth2PermissionGrants'
    }
    foreach ($K in $Kinds.Keys) { "  $($K): $(@($global:S118Graph | Where-Object { $_ -ceq $Kinds[$K] }).Count)" }
    "  directoryObjects/getByIds (all callers): $(@($global:S118Graph | Where-Object { $_ -like 'POST */directoryObjects/getByIds' }).Count)"
}

function Get-S118Bundle {
    # The newest bundle folder under an export folder.
    param([Parameter(Mandatory)][string]$Folder)
    Get-ChildItem -LiteralPath $Folder -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function ConvertTo-S118Canonical {
    # JSON with object keys sorted and arrays of scalars and objects sorted by their canonical text.
    param($Node)
    if ($null -eq $Node) { return 'null' }
    if ($Node -is [System.Collections.IList]) { return '[' + ((@($Node | ForEach-Object { ConvertTo-S118Canonical $_ }) | Sort-Object -CaseSensitive) -join ',') + ']' }
    if ($Node -is [System.Management.Automation.PSCustomObject]) { return '{' + ((@($Node.PSObject.Properties | Sort-Object Name -CaseSensitive | ForEach-Object { (ConvertTo-Json -InputObject $_.Name -Compress) + ':' + (ConvertTo-S118Canonical $_.Value) })) -join ',') + '}' }
    ConvertTo-Json -InputObject $Node -Compress
}

function Save-S118Export {
    # One export of $Include into a folder of its own; its requests and files go to a JSON file named after it, for 1.2b.
    param([Parameter(Mandatory)][string]$Name, [switch]$Switch)
    $Out = Join-Path $Work "export-$Name"
    $null = New-Item -ItemType Directory -Path $Out -Force
    Start-S118Count
    $Params = @{ OutputPath = $Out; Include = $Include; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'ExportErrors'; WarningVariable = 'ExportWarnings' }
    if ($Switch) { $Params.IncludeServicePrincipalAccess = $true }
    $Bundle = Export-OERInventory @Params 3>$null
    $Sent = Get-S118Sent
    $Graph = @($global:S118Graph); $Arm = @($global:S118Arm)
    Stop-S118Count
    $Dir = (Get-S118Bundle -Folder $Out).FullName
    $Record = [ordered]@{
        Sent = $Sent; Graph = @($Graph | Sort-Object -CaseSensitive); Arm = @($Arm | Sort-Object -CaseSensitive)
        Files = @($Bundle.Files); IncompleteReads = @($Bundle.IncompleteReads)
        Errors = @($ExportErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique)
        Warnings = @($ExportWarnings).Count
        Inventory = ConvertTo-S118Canonical (Get-Content -LiteralPath (Join-Path $Dir 'inventory.json') -Raw | ConvertFrom-Json)
        Readme = (Get-FileHash -LiteralPath (Join-Path $Dir 'README.md')).Hash
        Prompt = @(Get-Content -LiteralPath (Join-Path $Dir 'rbac-architect-prompt.md'))
        Dir = $Dir
    }
    $Record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Work "$Name.json") -Encoding utf8NoBOM
    [PSCustomObject]$Record
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, the base build is in place, and the main clone is on `main`, never switched. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
foreach ($Pair in @(@('branch', $Cfg.Repo), @('base', $Base))) {
    $Psm1 = Get-ChildItem -Path (Join-Path $Pair[1] 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $Has = { param($Text) [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Text -Quiet) }
    Write-OerLiveStep "The $($Pair[0]) build: reads service principal access: $(& $Has 'function Get-OERServicePrincipalAccess'); has the switch: $(& $Has '[switch]$IncludeServicePrincipalAccess'); maps principal types: $(& $Has 'function ConvertTo-OERPrincipalType'); checks the home tenant in Get-OERInventory with a shared cache: $(& $Has '-Cache $SubscriptionTenantCache')"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; the branch build `True` on every mark and the base build
`False` on every mark.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a
`False` mark on the branch build -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate
runs; a `True` mark on the base build -- the copy is not the base.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, the module is this branch's build, and the switch is the one new parameter. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Write-OerLiveStep "Export-OERInventory has -IncludeServicePrincipalAccess, a switch: $((Get-Command -Name Export-OERInventory).Parameters['IncludeServicePrincipalAccess'].SwitchParameter)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, `The module is the worktree's build: True`, and
the switch line `True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

## 1. Service principal access in an export of the test tenant

### 1.1. The export with the switch reads only, and names the identity's own permissions

- [ ] **1.1** `Export-OERInventory -Include AdministrativeUnits, RoleAssignments -IncludeServicePrincipalAccess` sends no write, writes `servicePrincipalAccess.json` with its four parts, every row naming its objects by id and name, and the identity's own application permissions with the resource's name and the permission's value; the requests per part are counted. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
$R = Save-S118Export -Name 'branch-switch' -Switch
Write-OerLiveStep $R.Sent
foreach ($Line in @(Get-S118SpAccessRequests)) { Write-OerLiveStep $Line }
$File = Join-Path $R.Dir 'servicePrincipalAccess.json'
$Doc = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
Write-OerLiveStep "servicePrincipalAccess.json exists: $(Test-Path -LiteralPath $File -PathType Leaf); in Files: $(@($R.Files) -contains 'servicePrincipalAccess.json'); keys in order: $(@($Doc.PSObject.Properties.Name) -join ', ')"
$Named = @{
    applicationPermissions    = @('servicePrincipalId', 'servicePrincipalDisplayName', 'resourceId', 'resourceDisplayName')
    delegatedPermissionGrants = @('clientId', 'clientDisplayName', 'resourceId', 'resourceDisplayName')
    applicationOwners         = @('applicationId', 'applicationDisplayName', 'ownerId', 'ownerDisplayName')
    servicePrincipalOwners    = @('servicePrincipalId', 'servicePrincipalDisplayName', 'ownerId', 'ownerDisplayName')
}
foreach ($Part in 'applicationPermissions', 'delegatedPermissionGrants', 'applicationOwners', 'servicePrincipalOwners') {
    $Rows = $Doc.$Part
    if ($null -eq $Rows) { Write-OerLiveStep "$($Part): null (not read)"; continue }
    $Rows = @($Rows)
    $Missing = @($Rows | Where-Object { $Row = $_; @($Named[$Part] | Where-Object { [string]::IsNullOrEmpty([string]$Row.$_) }).Count -gt 0 }).Count
    Write-OerLiveStep "$($Part): $($Rows.Count) row(s); rows missing an id or a name: $Missing; key order of the first row: $(if ($Rows.Count) { @($Rows[0].PSObject.Properties.Name) -join ', ' })"
}
$Perms = @($Doc.applicationPermissions)
Write-OerLiveStep "Application permissions whose role the resource does not declare (appRoleValue null): $(@($Perms | Where-Object { $null -eq $_.appRoleValue }).Count)"
$Grants = @($Doc.delegatedPermissionGrants)
Write-OerLiveStep "Grants: AllPrincipals $(@($Grants | Where-Object { $_.consentType -ceq 'AllPrincipals' }).Count), Principal $(@($Grants | Where-Object { $_.consentType -ceq 'Principal' }).Count); Principal grants with a user principal name: $(@($Grants | Where-Object { $_.consentType -ceq 'Principal' -and $_.principalUserPrincipalName }).Count); AllPrincipals grants naming a principal: $(@($Grants | Where-Object { $_.consentType -ceq 'AllPrincipals' -and ($_.principalId -or $_.principalDisplayName) }).Count)"
Write-OerLiveStep "Owner types: $((@(@($Doc.applicationOwners) + @($Doc.servicePrincipalOwners)) | Group-Object ownerType | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
$OwnSp = & (Get-Module -Name OerLive) { $script:OerLive.SpId }
$Own = @($Perms | Where-Object { [string]$_.servicePrincipalId -eq $OwnSp })
Write-OerLiveStep "The identity's own application permissions: $($Own.Count); resources: $((@($Own | ForEach-Object { [string]$_.resourceDisplayName } | Sort-Object -Unique)) -join ', '); every one with a value: $(@($Own | Where-Object { -not $_.appRoleValue }).Count -eq 0)"
Write-OerLiveStep "Their values: $((@($Own | ForEach-Object { [string]$_.appRoleValue } | Sort-Object)) -join ', ')"
$SpUnread = @($R.IncompleteReads | Where-Object { $_ -like 'servicePrincipalAccess/*' })
Write-OerLiveStep "IncompleteReads: $(@($R.IncompleteReads).Count), of them service principal access parts: $($SpUnread.Count); errors: $($R.Errors -join ', '); export warnings (counted, not printed): $($R.Warnings)"
Write-OerLiveStep "README has the section: $([bool](Select-String -LiteralPath (Join-Path $R.Dir 'README.md') -SimpleMatch '## Service principal access (read-only)' -Quiet))"
Disconnect-OerLive
```

**Expect:** `writes: 0` for both transports and `token requests: 0`; the service principal access requests:
the service principal list with app role assignments and the one with owners one request per page each (12
measured on 2026-10-18), the app registration list 1, the grant list 1, no re-read (no object reaches 20);
`servicePrincipalAccess.json exists: True`, in Files, keys `applicationPermissions, delegatedPermissionGrants,
applicationOwners, servicePrincipalOwners`; every part read with 0 rows missing an id or a name and the key
orders of the plan (grants with both `principalDisplayName` and `principalUserPrincipalName`); about 1
application permission with `appRoleValue` null (measured); no AllPrincipals grant naming a principal; the
identity's own permissions all on `Microsoft Graph`, every one with a value, their values printed; no service
principal access part in `IncompleteReads` (the export may still be partial for the management group listing
this identity cannot read, as in earlier steps); README has the section.
**Failure looks like:** a write, a token request, a part `null`, a row without an id or a name, an own
permission without a value, or a service principal access entry in `IncompleteReads`.

Result:

### 1.2a. The base build's export, without the switch (the measurement to compare with)

- [ ] **1.2a** The base build (`12d9901`) exports the same sections without the switch; its requests, files and texts are saved for 1.2b. #type/subtask

```powershell
Use-S118BaseBuild
Connect-OerLive -Arm
Start-S118NoPrompt
$R = Save-S118Export -Name 'base'
Write-OerLiveStep "The module is the base build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Base 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); Export-OERInventory has no -IncludeServicePrincipalAccess: $(-not (Get-Command -Name Export-OERInventory).Parameters.ContainsKey('IncludeServicePrincipalAccess'))"
Write-OerLiveStep $R.Sent
Write-OerLiveStep "Files: $(@($R.Files).Count); IncompleteReads: $(@($R.IncompleteReads).Count); errors: $($R.Errors -join ', ')"
Disconnect-OerLive
```

**Expect:** both lines `True`; the request totals with `writes: 0`; the counts printed.
**Failure looks like:** the branch build loaded (the comparison would compare the branch with itself).

Result:

### 1.2b. The branch's export without the switch: no new file and the same requests as before

- [ ] **1.2b** The branch build exports the same sections without the switch: no `servicePrincipalAccess.json`, the same files, the same Graph and Azure Resource Manager requests as the base, an unchanged README, a prompt that differs only in part B's `scopedRoles` keys, and an `inventory.json` that differs only where part B adds `principalType`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
$R = Save-S118Export -Name 'branch'
$B = Get-Content -LiteralPath (Join-Path $Work 'base.json') -Raw | ConvertFrom-Json
Write-OerLiveStep $R.Sent
Write-OerLiveStep "servicePrincipalAccess.json written: $(Test-Path -LiteralPath (Join-Path $R.Dir 'servicePrincipalAccess.json')); in Files: $(@($R.Files) -contains 'servicePrincipalAccess.json')"
Write-OerLiveStep "Same files as the base, in order: $((@($R.Files) -join '|') -ceq (@($B.Files) -join '|'))"
$GraphSame = (@($R.Graph) -join '|') -ceq (@($B.Graph) -join '|')
$ArmSame = (@($R.Arm) -join '|') -ceq (@($B.Arm) -join '|')
Write-OerLiveStep "Same Microsoft Graph requests as the base: $GraphSame ($(@($R.Graph).Count) vs $(@($B.Graph).Count)); same Azure Resource Manager requests: $ArmSame ($(@($R.Arm).Count) vs $(@($B.Arm).Count))"
if (-not $GraphSame) { foreach ($G in @(Compare-Object -ReferenceObject @($B.Graph) -DifferenceObject @($R.Graph) -CaseSensitive)) { Write-OerLiveStep "  Graph $(if ($G.SideIndicator -eq '=>') { 'only branch' } else { 'only base' }): $($G.InputObject)" } }
if (-not $ArmSame) { foreach ($G in @(Compare-Object -ReferenceObject @($B.Arm) -DifferenceObject @($R.Arm) -CaseSensitive)) { Write-OerLiveStep "  ARM $(if ($G.SideIndicator -eq '=>') { 'only branch' } else { 'only base' }): $($G.InputObject)" } }
Write-OerLiveStep "README.md the same as the base: $($R.Readme -ceq $B.Readme)"
# The prompt is the module's own text (no tenant value), so the lines that differ may be printed.
$PromptDiff = @(Compare-Object -ReferenceObject @($B.Prompt) -DifferenceObject @($R.Prompt) -CaseSensitive)
Write-OerLiveStep "rbac-architect-prompt.md lines that differ from the base: $($PromptDiff.Count)"
foreach ($D in $PromptDiff) { Write-OerLiveStep "  $(if ($D.SideIndicator -eq '=>') { 'branch' } else { 'base' }): $($D.InputObject.Trim())" }
$Strip = { param($Text) $Text -replace ',"principalType":"(User|Group|ServicePrincipal)"', '' }
Write-OerLiveStep "inventory.json the same as the base: $($R.Inventory -ceq $B.Inventory); the same once scoped-role principalType keys are taken out: $((& $Strip $R.Inventory) -ceq (& $Strip $B.Inventory)); IncompleteReads the same: $((@($R.IncompleteReads) -join '|') -ceq (@($B.IncompleteReads) -join '|'))"
Disconnect-OerLive
```

**Expect:** `writes: 0`; `servicePrincipalAccess.json written: False; in Files: False`; the same files; the same
Graph requests (unless the test tenant has a scoped role, when part B adds exactly one
`POST /v1.0/directoryObjects/getByIds`, printed as `only branch`) and the same Azure Resource Manager requests
(the home-tenant check inside the export costs nothing); README the same; the prompt differing only in part B's
`scopedRoles` key line (`principal (required)` followed by the optional `principalType`), and naming no
`servicePrincipalAccess.json`; `inventory.json` the same,
or the same once part B's keys are taken out; IncompleteReads the same.
**Failure looks like:** the file, another file list, any other request difference (above all an extra
subscription GET), a changed README or prompt.

Result:

### 1.3. A 403 on every part is a part that was not read, never an empty list

- [ ] **1.3** As `oer-live-cc-noperm`, which holds no permission, the export with the switch completes: every part is `null` in the file, each is named in `IncompleteReads`, the export reports `InventoryPartial`, and the grant list is not requested since the service principal list was not read. #type/subtask

```powershell
Connect-OerLive -Arm -NoPerm
Start-S118NoPrompt
$Out = Join-Path $Work 'export-noperm'
$null = New-Item -ItemType Directory -Path $Out -Force
Start-S118Count
$Bundle = Export-OERInventory -OutputPath $Out -Include AdministrativeUnits -IncludeServicePrincipalAccess -ErrorAction SilentlyContinue -ErrorVariable ExportErrors -WarningVariable ExportWarnings 3>$null
Write-OerLiveStep (Get-S118Sent)
foreach ($Line in @(Get-S118SpAccessRequests)) { Write-OerLiveStep $Line }
Stop-S118Count
$File = Join-Path (Get-S118Bundle -Folder $Out).FullName 'servicePrincipalAccess.json'
$Raw = Get-Content -LiteralPath $File -Raw
Write-OerLiveStep "The export completed and wrote the file: $(Test-Path -LiteralPath $File -PathType Leaf)"
foreach ($Part in 'applicationPermissions', 'delegatedPermissionGrants', 'applicationOwners', 'servicePrincipalOwners') {
    Write-OerLiveStep "$($Part): null in the file: $($Raw -match ('"' + $Part + '":\s*null')); [] in the file: $($Raw -match ('"' + $Part + '":\s*\[\s*\]')); named in IncompleteReads: $(@($Bundle.IncompleteReads) -contains "servicePrincipalAccess/$Part")"
}
$Own = @($ExportErrors | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InventoryPartial,*Export-OERInventory' })
Write-OerLiveStep "InventoryPartial from the export: $($Own.Count); its message names the service principal access parts: $(if ($Own) { [string]$Own[0].Exception.Message -like '*service principal access part(s) could not be read*' })"
Disconnect-OerLive
```

**Expect:** `writes: 0`; the service principal list with app role assignments 1, the one with owners 1, the
app registration list 1, the grant list 0, getByIds 0; the file written; every part `null: True`,
`[]: False`, named `True`; one `InventoryPartial` from the export whose message names the parts.
**Failure looks like:** a part written `[]`, a part not named, the export stopping, or a grant request.

Result:

## 2. Scoped-role principal types

### 2.1. The test tenant's scoped roles carry principalType

- [ ] **2.1** Every `administrativeUnits[].scopedRoles` row of the 1.1 export whose principal is an object id carries a `principalType` of the schema's enum; if the test tenant holds no scoped role, that is recorded and B.2 holds the rule. #type/subtask

```powershell
$Inv = Get-Content -LiteralPath (Join-Path (Get-S118Bundle -Folder (Join-Path $Work 'export-branch-switch')).FullName 'inventory.json') -Raw | ConvertFrom-Json
$Units = @($Inv.administrativeUnits)
$Rows = @($Units | ForEach-Object { @($_.scopedRoles) } | Where-Object { $null -ne $_ })
$Typed = @($Rows | Where-Object { $_.principalType -cin 'User', 'Group', 'ServicePrincipal' })
Write-OerLiveStep "Administrative units: $($Units.Count); with scopedRoles null: $(@($Units | Where-Object { $null -eq $_.scopedRoles }).Count); scoped role rows: $($Rows.Count); with a principalType of the enum: $($Typed.Count); per type: $((@($Typed | Group-Object principalType | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', ')"
```

**Expect:** the counts printed; every row with a GUID principal typed. With `scoped role rows: 0` the test
tenant holds none (S114 created one and removed it): mark `[~]` with that reason and rely on B.2.
**Failure looks like:** a row with an object id principal and no `principalType`, or a type outside the enum.

Result:

## 3. Get-OERInventory and the session's own subscription

### 3.1a. The base build's inventory of the test subscription

- [ ] **3.1a** The base build reads `RoleAssignments` of the test subscription by `-Subscription` and by `-Scope`, without `-IncludeARM`; its rows and requests are saved for 3.1b. #type/subtask

```powershell
Use-S118BaseBuild
Connect-OerLive -Arm
Start-S118NoPrompt
$Saved = [ordered]@{}
foreach ($Case in @(@('subscription', @{ Subscription = $Cfg.SubscriptionId }), @('scope', @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)" }))) {
    Start-S118Count
    $Params = $Case[1]
    $Inv = Get-OERInventory -Include RoleAssignments @Params -ErrorAction SilentlyContinue -ErrorVariable InvErrors 3>$null
    $Saved[$Case[0]] = [ordered]@{ Rows = ConvertTo-S118Canonical @($Inv.roleAssignments); Count = @($Inv.roleAssignments).Count; Arm = @($global:S118Arm | Sort-Object -CaseSensitive); Errors = @($InvErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique) }
    Write-OerLiveStep "$($Case[0]): $(Get-S118Sent); rows $(@($Inv.roleAssignments).Count); errors: $($Saved[$Case[0]].Errors -join ', ')"
    Stop-S118Count
}
$Saved | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Work 'inventory-base.json') -Encoding utf8NoBOM
Disconnect-OerLive
```

**Expect:** both cases read rows (14 measured in Sprint 10 for this subscription; the count may have moved),
`writes: 0`, no error.
**Failure looks like:** an error, or no row (the comparison would compare nothing).

Result:

### 3.1b. The branch reads the session's own subscription exactly as before, plus one read of the subscription

- [ ] **3.1b** The branch build reads the same rows for both cases, without `-IncludeARM`, writes no error, is not partial, and sends the base's Azure Resource Manager requests plus exactly one `GET /subscriptions/{id}` (the home-tenant check). #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
$B = Get-Content -LiteralPath (Join-Path $Work 'inventory-base.json') -Raw | ConvertFrom-Json
foreach ($Case in @(@('subscription', @{ Subscription = $Cfg.SubscriptionId }), @('scope', @{ Scope = "/subscriptions/$($Cfg.SubscriptionId)" }))) {
    Start-S118Count
    $Params = $Case[1]
    $Inv = Get-OERInventory -Include RoleAssignments @Params -ErrorAction SilentlyContinue -ErrorVariable InvErrors 3>$null
    $Arm = @($global:S118Arm | Sort-Object -CaseSensitive)
    $Errors = @($InvErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique)
    $Base = $B.($Case[0])
    $Extra = @(Compare-Object -ReferenceObject @($Base.Arm) -DifferenceObject $Arm -CaseSensitive | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject })
    $Lost = @(Compare-Object -ReferenceObject @($Base.Arm) -DifferenceObject $Arm -CaseSensitive | Where-Object { $_.SideIndicator -eq '<=' }).Count
    Write-OerLiveStep "$($Case[0]): $(Get-S118Sent); rows $(@($Inv.roleAssignments).Count) (base $($Base.Count)); the same rows as the base: $((ConvertTo-S118Canonical @($Inv.roleAssignments)) -ceq [string]$Base.Rows); errors: $($Errors -join ', ')"
    Write-OerLiveStep "  ARM requests the base did not send: $($Extra -join '; '); base requests missing: $Lost"
    Stop-S118Count
}
Disconnect-OerLive
```

**Expect:** for both cases `writes: 0`, the same rows as the base, no error (no `InventoryPartial`, no
`SubscriptionTenantMismatch`), and exactly one extra ARM request, `GET /subscriptions/{id}`, with none missing.
**Failure looks like:** fewer rows, an error, a partial inventory, or another extra request.

Result:

### 3.2. A subscription that cannot be decided is reported unread, with no row

- [ ] **3.2** `Get-OERInventory -Include RoleAssignments -Subscription 00000000-0000-0000-0000-000000000099` (the register's deliberately non-existent id) reads no role assignment, writes no row, reports `InventoryPartial` naming `roleAssignments`, and writes no `SubscriptionTenantMismatch`. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
Start-S118Count
$Inv = Get-OERInventory -Include RoleAssignments -Subscription '00000000-0000-0000-0000-000000000099' -ErrorAction SilentlyContinue -ErrorVariable InvErrors 3>$null
Write-OerLiveStep (Get-S118Sent)
Write-OerLiveStep "ARM requests: $((@($global:S118Arm | Sort-Object -Unique)) -join '; ')"
Stop-S118Count
$Partial = @($InvErrors | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InventoryPartial,*Get-OERInventory' })
Write-OerLiveStep "Rows: $(@($Inv.roleAssignments).Count); InventoryPartial: $($Partial.Count), naming roleAssignments: $(if ($Partial) { @(([string]$Partial[0].TargetObject) -split ', ') -contains 'roleAssignments' }); SubscriptionTenantMismatch: $(@($InvErrors | Where-Object { [string]$_.FullyQualifiedErrorId -like 'SubscriptionTenantMismatch,*' }).Count)"
Disconnect-OerLive
```

**Expect:** `writes: 0`; one ARM request, `GET /subscriptions/{id}` (answered with a refusal or not-found:
the verdict is undecided), and no role assignment request; `Rows: 0`; one `InventoryPartial` naming
`roleAssignments`; `SubscriptionTenantMismatch: 0`.
**Failure looks like:** a role assignment request, a row, no partial, or a mismatch error (that would claim a
tenant the read never established).

Result:

### 3.3. A management group scope is not checked

- [ ] **3.3** `Get-OERInventory -Include RoleAssignments -ManagementGroup oer-s118-no-such-group` sends no subscription read (a management group is not checked); the reader's own refusal or not-found is all that comes back. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S118NoPrompt
Start-S118Count
$Inv = Get-OERInventory -Include RoleAssignments -ManagementGroup 'oer-s118-no-such-group' -ErrorAction SilentlyContinue -ErrorVariable InvErrors 3>$null
Write-OerLiveStep (Get-S118Sent)
Write-OerLiveStep "Subscription reads: $(@($global:S118Arm | Where-Object { $_ -ceq 'GET /subscriptions/{id}' }).Count); ARM request kinds: $((@($global:S118Arm | Sort-Object -Unique)) -join '; ')"
Stop-S118Count
Write-OerLiveStep "Rows: $(@($Inv.roleAssignments).Count); errors: $((@($InvErrors | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique)) -join ', ')"
Disconnect-OerLive
```

**Expect:** `writes: 0`; `Subscription reads: 0`; the request kinds name the management group path only; `Rows: 0`;
the reader's own error (this identity cannot read management groups, and the name does not exist); no
`SubscriptionTenantMismatch`.
**Failure looks like:** a subscription read, or a mismatch error.

Result:

## B. Proved offline (class B)

Each item is held by unit tests on this branch, run by `./build.ps1 -Tasks test`.

- **B.1 A subscription of another tenant.** `tests/Unit/Public/Get-OERInventory.Tests.ps1`: `-Scope` on a
  resource group and `-Subscription` in another tenant's subscription give one `SubscriptionTenantMismatch`, no
  row in either section and no read there; an undecidable subscription is unread; `-ManagementGroup` is not
  checked; a script with no `try` carries on. `tests/Unit/Private/Get-OERSubscriptionHomeTenant.Tests.ps1` and
  `tests/QA/sourcehygiene.tests.ps1` (gate 10: three callers).
- **B.2 Scoped-role principal types.** `tests/Unit/Public/Get-OERInventory.Tests.ps1` (user, group, service
  principal, not found, a failed lookup, one batch), `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1` and
  `Read-OERStructureDocument.Tests.ps1` (the enum, the casing, the canonical form), and the round trip in
  `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1` (an export with `principalType` applies
  Unchanged, with and without `-Prune`).
- **B.3 One part unread, the 20-or-more re-read, an empty tenant.**
  `tests/Unit/Private/Get-OERServicePrincipalAccess.Tests.ps1` and `tests/Unit/Public/Export-OERInventory.Tests.ps1`.
- **B.4 The export's requests with the shared answers.** `tests/Unit/Public/Export-OERInventory.Tests.ps1`: a
  listed walk sends no subscription read, an export `-Scope` on a resource group sends the tree's one.
- **B.5 The texts.** `tests/QA/about.tests.ps1`, `docsync.tests.ps1`, `dochygiene.tests.ps1`,
  `requiredscope.tests.ps1` and `module.tests.ps1`.

## T. Teardown

### T.1. Nothing was created, and the step's raw folders are gone

- [ ] **T.1** No object with the prefix `oer-s118-` exists, and the step's raw folders are deleted (the export bundles and the base build with them). The redaction map is deleted with `Clear-OerLiveRedactionMap` once every result is written up, after this check. #type/subtask

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed -Prefix 'oer-s118-' -ThrowOnUnread)
Write-OerLiveStep "Objects carrying the prefix oer-s118-: $($Found.Count)"
Disconnect-OerLive
$MainRaw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
foreach ($Dir in @($MainRaw, $Work) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    Write-OerLiveStep "Raw folder deleted: $(-not (Test-Path -LiteralPath $Dir))"
}
```

**Expect:** `Objects carrying the prefix oer-s118-: 0`; every raw folder deleted (`True`).
**Failure looks like:** a prefixed object (this checklist creates none: STOP and find who made it), or a folder
left behind.

Result:
