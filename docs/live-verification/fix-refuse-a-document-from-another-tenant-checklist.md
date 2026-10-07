# Live verification checklist -- an exported document carries its tenant, and apply refuses another (fix/refuse-a-document-from-another-tenant)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** One test object, `oer-s96b-grp` -- a plain security group
with no member and no owner -- created by the prerequisite script (0.2, 0.3) and removed by its
teardown (T.1). Every check after that only reads, exports, runs `Invoke-OERStructure -WhatIf`, or
runs an apply that is refused before anything is read. The export of 1.3 writes a bundle into the
step's git-ignored raw folder, and the documents the checks apply are written there too; T.2 deletes
them.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person, and no check needs
`oer-live-cc-noperm`. A 401 or 403 as `oer-live-cc` is a stop.

**Sign-ins.** Every block's first sign-in goes through `Connect-OerLive`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and checks the identity. The block then disconnects and signs in with
`Connect-OER` itself, with the certificate, so the fences below count every request the module makes
from then on.

**The other tenant.** `00000000-0000-0000-0000-000000000099`, the placeholder register's deliberately
non-existent id ([README.md](README.md), "The placeholder register"). It names no tenant; a document
whose `tenantId` is that value stands for a document exported from another tenant. The blocks call it
`$OtherTenant`, and the redactor leaves it as it is, since it is a placeholder already.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s96b/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, domain, account or
certificate thumbprint is ever printed** -- every comparison is printed as True or False -- and **no
error record is ever rendered**: every block prints the error id, the category and the redacted
message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The validator and the schema** ("validate a document's tenantId as a tenant ID").
  `Test-OERStructureSchema` knows a top-level `tenantId`: when the key is present it must be a
  canonical GUID, and any other value -- an explicit null included -- is an Error. A document without
  the key is valid as before. `schema.json` declares it as a string with the GUID pattern.
- **B. The export** ("write the granted tenant into an exported inventory"). `Get-OERInventory` and
  `Export-OERInventory` write `tenantId` directly after `version`: the tenant the session's Microsoft
  Graph token was issued for (`TokenTenantId`), read by the new private `Get-OERInventoryTenantId`,
  never the tenant as named. No other key changes.
- **C. The apply refusal** ("refuse a document whose tenantId is not the session's tenant"). The new
  private `Get-OERDocumentTenantMismatch` owns the comparison and the new `DocumentTenantMismatch`.
  `Invoke-OERStructure` refuses a document whose `tenantId` names another tenant than a `-TenantId`
  given as a GUID before it signs in, and otherwise, after the sign-in and before anything is read or
  written for the document, another tenant than the session's Graph token -- and the Azure Resource
  Manager token's when an Azure section is applied. The refusal is a non-terminating error per
  document. A document without `tenantId` is applied as before.
- **D.** Texts ("describe the document tenant rule in the help and the prompt", "record the document
  tenant rule", "name both export cmdlets in the release note and tighten the tenant rule texts",
  "make the tenantId wording conditional and tell the walkthroughs where an export applies"): the help
  of the four cmdlets, the prompt template, the bundle README, README, the about topic, `CLAUDE.md`,
  `docs/development/rationale.md` and the release note.
- **E.** Tests added after the reviews ("prove the pre-sign-in tenant check with no try and cover
  organizations and the ARM token", "pin the post-sign-in tenant comparison for a GUID -TenantId and
  cover a real run").

A live tenant is needed for what the unit tests stub: the tenant a real certificate token is issued
for, as the export writes it; a real export and plan of a real group; and the module's real requests
-- token calls, lookups, Graph and ARM -- counted by fences around the refused applies.

## What this file does not check, and why

- **BL-88 with a second tenant (class B, G9).** The shape is `Invoke-OERStructure` inside a
  `ForEach-Object` block, followed in the pipeline by a command whose `begin` block signs in to
  another tenant. The certificate reaches one tenant only, so the switch to a second tenant cannot be
  produced live. 7.1 runs the same shape in one tenant, with a document that names another tenant,
  which exercises the same check from the same place. Proved offline, end to end with the real
  `Initialize-OERAuth` over stubbed transports in a runspace with no `try`:
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` P19 (refused, no Graph or ARM request), P19b
  (a document without `tenantId` is still applied in the switched tenant: the open form), P19c and
  P19d (the same with `-IncludeARM`: neither transport sends), and P19e (`-TenantId` naming another
  tenant ID than the document: no token request).
- **An Azure Resource Manager token from another tenant than the Graph token** (class B). The
  certificate's tokens always come from the test tenant. Proved by
  `tests/Unit/Private/Get-OERDocumentTenantMismatch.Tests.ps1` and the ARM tests in the Describe
  `Invoke-OERStructure refuses a document from another tenant (BL-88, A14)`.
- **A token whose tenant AzAuth does not report as a GUID** (class B), and the export that then leaves
  `tenantId` out: the certificate's tokens always carry one. `Get-OERInventoryTenantId.Tests.ps1`.
- **G8 convergence** does not apply: this step adds no write path. The export only reads, and every
  apply here is a plan or a refusal.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).
- The prerequisite script `Initialize-OerS96bPrereq.ps1` beside OerLive (0.2, 0.3, T.1).

**Run every numbered block in its OWN PowerShell process.** Sections 1 to 7 start with block **H**
below, run first in the same process, unchanged; each section's own block follows it.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s96b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'tenantId' must be the tenant ID the document was exported from" -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERInventoryTenantId' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERDocumentTenantMismatch' -Quiet) -and
    [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'DocumentTenantMismatch'" -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `A: True; B: True; C: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any other `False` -- build the worktree first (`./build.ps1 -Tasks build`), never while the
gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s96b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result:

### 0.2. The prerequisite script's plan

- [ ] **0.2** `Initialize-OerS96bPrereq.ps1 -WhatIf`: signs in as `oer-live-cc`, finds no prefixed object (or only `oer-s96b-grp`), and plans one write, whose target is `oer-s96b-grp`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96bPrereq.ps1') -WhatIf
```

**Expect:** every identity line `True`; `Found: oer-s96b-grp exists: False.`; one `What if:` line for
the baseline and one whose target is `oer-s96b-grp`; `WhatIf: nothing was created, removed or
written.`; exit code 0.
**Failure looks like:** a `Refusing to run:` line -- read it, nothing was written; a target without
the prefix -- STOP.

Result:

### 0.3. The prerequisite script, for real

- [ ] **0.3** `Initialize-OerS96bPrereq.ps1 -Unattended`: writes the baseline, then creates `oer-s96b-grp` and waits until it resolves by its name.

```powershell
$VaultDir = $env:OER_LIVE_DIR
pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96bPrereq.ps1') -Unattended
```

**Expect:** `No baseline yet: it is written now`, `Created group oer-s96b-grp: 201.`, the
convergence line, `Summary: oer-s96b-grp present; written to the tenant: True.`, exit code 0.
**Failure looks like:** any refusal or stop line; exit code 1.

Result:

## H. The harness every section runs first

Run this block first in the process of each of sections 1 to 7, unchanged. After the identity check
it installs four fences: global functions that the module's unqualified calls resolve to (a function
outranks a cmdlet), each counting and forwarding to the real command, module-qualified -- except
that the token fence REFUSES any token request that does not carry the certificate, so no check can
open a browser or a device code prompt. It then disconnects and signs in with `Connect-OER` itself,
by GUID, with the certificate and `-IncludeARM`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s96b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
# Names no tenant: the placeholder register's deliberately non-existent id.
$OtherTenant = '00000000-0000-0000-0000-000000000099'
$Filter = "startswith(displayName,'oer-s96b-')"
$InventoryFile = Join-Path $Raw 'inventory-1.1.json'
function New-S96bFence {
    param([string]$Name, [string]$Body)
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $Name -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { $Body }"
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Text))
}
New-S96bFence -Name 'Invoke-MgGraphRequest' -Body '$global:S96bGraph++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters'
New-S96bFence -Name 'Invoke-WebRequest' -Body '$global:S96bArm++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters'
New-S96bFence -Name 'Invoke-RestMethod' -Body '$global:S96bLookup++; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters'
New-S96bFence -Name 'Get-AzToken' -Body ('$global:S96bToken++; if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { $global:S96bTokenRefused++; ' +
    'throw [System.InvalidOperationException]::new(''S96b fence: a token request without the certificate was refused before it was sent.'') }; AzAuth\Get-AzToken @PSBoundParameters')
$Fenced = @('Invoke-MgGraphRequest', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-AzToken' | ForEach-Object {
        (& $Module { param($N) Get-Command -Name $N } $_).CommandType -eq 'Function' })
Write-OerLiveStep "The module resolves the four fenced commands to the fences: $(@($Fenced) -notcontains $false)"
if (@($Fenced) -contains $false) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Get-S96bState {
    # Who the module is, as True/False only.
    $S = & $Module { $script:_OERAuthState }
    if (-not $S) { return 'the module holds a session: False' }
    "the module holds a session: True; the Graph token was issued for the test tenant: $(([string]$S.TokenTenantId) -eq $Cfg.TenantId); " +
    "the ARM token: $(([string]$S.ArmTokenTenantId) -eq $Cfg.TenantId); the client is oer-live-cc: $(([string]$S.ClientId) -eq $Cfg.AppId)"
}
function Invoke-S96b {
    # A plain call, outside any try, as at a prompt. Prints the counts, the error ids, categories,
    # targets and messages, the rows and the warnings, all redacted; never a token, never an error record.
    # The output objects are kept in $global:S96bLast.
    param([string]$Label, [scriptblock]$Call)
    $global:S96bGraph = 0; $global:S96bArm = 0; $global:S96bLookup = 0; $global:S96bToken = 0; $global:S96bTokenRefused = 0
    $All = @(& $Call 2>&1 3>&1)
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Warns = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    $IdText = if ($Ids) { ($Ids | Group-Object | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }) -join ', ' } else { 'none' }
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $IdText; warnings: $($Warns.Count); lookups: $global:S96bLookup; token requests: $global:S96bToken (refused by the fence: $global:S96bTokenRefused); Graph requests: $global:S96bGraph; ARM requests: $global:S96bArm; $(Get-S96bState)"
    foreach ($O in @($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult' })) {
        Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $(ConvertTo-OerLiveRedacted -Text ([string]$O.Detail))"
    }
    foreach ($E in @($Errs | Group-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { $_.Group[0] })) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 500) { $Text = $Text.Substring(0, 500) + ' ...' }
        Write-OerLiveStep "$($Label): $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category) -- $Text"
    }
    foreach ($W in $Warns) {
        $Text = ConvertTo-OerLiveRedacted -Text ([string]$W.Message)
        if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$($Label): warning -- $Text"
    }
    $global:S96bLast = $Out
}
function Copy-S96bDocument {
    # A deep copy, so a change to one document never reaches another.
    param([Parameter(Mandatory)]$Document)
    $Document | ConvertTo-Json -Depth 32 | ConvertFrom-Json -Depth 32
}
Disconnect-OerLive
Invoke-S96b -Label 'H sign-in, Connect-OER by GUID with the certificate' -Call { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
```

**Expect:** every identity line `True`; the fences `True`; `H sign-in ...: output objects 0; errors:
none; ... token requests: 2 (refused by the fence: 0); Graph requests: 0; ARM requests: 0; the module
holds a session: True; the Graph token was issued for the test tenant: True; the ARM token: True; the
client is oer-live-cc: True`.
**Failure looks like:** any `False`; a token request refused by the fence -- the sign-in did not use
the certificate (STOP).

## 1. The export writes the tenant the token was issued for

### 1.1. Get-OERInventory after a sign-in by GUID writes tenantId, the test tenant's GUID

- [ ] **1.1** `Get-OERInventory -Include Groups -GroupFilter` (the prefix): the document holds `oer-s96b-grp`, its second key is `tenantId`, and `tenantId` is the test tenant's GUID. The document is saved to the raw folder for sections 2 to 7.

```powershell
# Block H first, in this process.
Invoke-S96b -Label '1.1 Get-OERInventory after a sign-in by GUID' -Call { Get-OERInventory -Include Groups -GroupFilter $Filter }
$Inv = @($global:S96bLast | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.Inventory' })[0]
$Keys = @($Inv.PSObject.Properties.Name)
Write-OerLiveStep "1.1 root keys: $($Keys -join ', ')"
Write-OerLiveStep "1.1 the document carries tenantId: $($Keys -contains 'tenantId'); it is the test tenant's GUID: $(([string]$Inv.tenantId) -eq $Cfg.TenantId); groups: $(@($Inv.groups).Count) ($((@($Inv.groups) | ForEach-Object { $_.displayName }) -join ', '))"
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$Inv | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $InventoryFile -Encoding utf8
Write-OerLiveStep "1.1 saved to the raw folder: $(Test-Path -LiteralPath $InventoryFile)"
Disconnect-OerLive
```

**Expect:** `1.1 Get-OERInventory ...: output objects 1; errors: none; ... token requests: 0`, Graph
requests above 0, ARM requests 0; `root keys: version, tenantId, groups, administrativeUnits,
catalogs, accessPackages, accessReviews, directoryRoleManagementPolicies, directoryRoleAssignments,
roleAssignments, roleManagementPolicies`; `carries tenantId: True; it is the test tenant's GUID: True;
groups: 1 (oer-s96b-grp)`; saved `True`.
**Failure looks like:** no `tenantId`, or `False` for the GUID -- the export does not write the token's
tenant; `errors: InventoryPartial` -- read which collection; the document is still written.

Result:

### 1.2. After a sign-in by domain, tenantId is still the GUID, never the name

- [ ] **1.2** `Connect-OER` with the test tenant's primary domain, then the same export: `tenantId` is the test tenant's GUID, not the domain the sign-in named.

```powershell
# Block H first, in this process.
Disconnect-OerLive
Invoke-S96b -Label '1.2 Connect-OER by domain' -Call { Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
$Named = & $Module { [string]$script:_OERAuthState.TenantId }
Write-OerLiveStep "1.2 the session names the tenant by its domain: $($Named -eq $Cfg.UserDomain)"
Invoke-S96b -Label '1.2 Get-OERInventory after a sign-in by domain' -Call { Get-OERInventory -Include Groups -GroupFilter $Filter }
$Inv = @($global:S96bLast | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.Inventory' })[0]
Write-OerLiveStep "1.2 tenantId is the test tenant's GUID: $(([string]$Inv.tenantId) -eq $Cfg.TenantId); tenantId is the domain the sign-in named: $(([string]$Inv.tenantId) -eq $Cfg.UserDomain)"
Disconnect-OerLive
```

**Expect:** the sign-in: one lookup, two token requests; `the session names the tenant by its domain:
True`; `tenantId is the test tenant's GUID: True; tenantId is the domain the sign-in named: False`.
**Failure looks like:** `tenantId` equal to the domain -- the export writes the tenant as named.

Result:

### 1.3. Export-OERInventory writes the same tenantId into inventory.json, and the bundle validates

- [ ] **1.3** `Export-OERInventory -Include Groups` into the raw folder: `inventory.json` carries `tenantId`, the test tenant's GUID, the export writes no self-check warning, and `Test-OERStructure` on the file is valid.

```powershell
# Block H first, in this process.
$BundleRoot = Join-Path $Raw 'bundle'
New-Item -ItemType Directory -Force -Path $BundleRoot | Out-Null
Invoke-S96b -Label '1.3 Export-OERInventory -Include Groups' -Call { Export-OERInventory -OutputPath $BundleRoot -Include Groups }
$Bundle = @($global:S96bLast | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.InventoryBundle' })[0]
$File = Join-Path $Bundle.BundlePath 'inventory.json'
$Doc = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json -Depth 32
Write-OerLiveStep "1.3 inventory.json carries tenantId: $(@($Doc.PSObject.Properties.Name) -contains 'tenantId'); it is the test tenant's GUID: $(([string]$Doc.tenantId) -eq $Cfg.TenantId); its second key: $(@($Doc.PSObject.Properties.Name)[1])"
$Check = Test-OERStructure -Path $File
Write-OerLiveStep "1.3 Test-OERStructure on inventory.json: Valid $($Check.Valid); findings at tenantId: $(@($Check.Errors | Where-Object { $_.Path -eq 'tenantId' }).Count)"
Disconnect-OerLive
```

**Expect:** `1.3 Export-OERInventory ...: output objects 1`, no `inventory.json did not pass
apply-schema validation` warning among the warnings (an `InventoryPartial` error, if any, is read and
recorded); `carries tenantId: True; it is the test tenant's GUID: True; its second key: tenantId`;
`Valid True; findings at tenantId: 0`.
**Failure looks like:** the self-check warning -- the validator does not know the key; `False` --
`Export-OERInventory` drops or changes it.

Result:

## 2. The exported document applies as before

### 2.1. Invoke-OERStructure -WhatIf with the exported document: a normal plan

- [ ] **2.1** `Invoke-OERStructure -InputObject` (the document 1.1 exported) `-Include Groups -WhatIf`: no error, the row for `oer-s96b-grp` is `Unchanged`, and the group is read.

```powershell
# Block H first, in this process.
$Inv = Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32
Invoke-S96b -Label '2.1 the exported document, -WhatIf' -Call { Invoke-OERStructure -InputObject $Inv -Include Groups -WhatIf }
Disconnect-OerLive
```

**Expect:** `errors: none`, `token requests: 0`, Graph requests above 0, ARM requests 0; `row groups |
oer-s96b-grp | Unchanged`.
**Failure looks like:** `DocumentTenantMismatch` -- the session's tenant and the exported one differ,
which cannot be in one tenant; any other error -- read it.

Result:

### 2.2. The same document with an Azure section: the Azure Resource Manager half is planned too

- [ ] **2.2** The exported document with one `roleAssignments` entry added (Reader for `oer-s96b-grp` at the test subscription) and `-Include Groups,RoleAssignments -WhatIf`: no error, the Azure Resource Manager is read, and the assignment is planned, not made.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.roleAssignments = @([PSCustomObject]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s96b-grp' })
Invoke-S96b -Label '2.2 with an Azure section, -WhatIf' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups, RoleAssignments -WhatIf }
Disconnect-OerLive
```

**Expect:** `errors: none`, ARM requests above 0; `row groups | oer-s96b-grp | Unchanged` and one
`roleAssignments` row `Skipped` whose detail starts `would create`.
**Failure looks like:** `DocumentTenantMismatch` naming the Azure Resource Manager token -- the ARM
token's tenant is not the test tenant (STOP: impossible with this certificate).

Result:

## 3. A document from another tenant is refused before anything is read

### 3.1. With -WhatIf: DocumentTenantMismatch, and no request for the document

- [ ] **3.1** The exported document with `tenantId` set to the other tenant, `-Include Groups -WhatIf`: `DocumentTenantMismatch`, no row, no Graph and no ARM request.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.tenantId = $OtherTenant
Invoke-S96b -Label '3.1 another tenant, -WhatIf' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups -WhatIf }
Disconnect-OerLive
```

**Expect:** `output objects 0; errors: DocumentTenantMismatch; warnings: 0; lookups: 0; token requests:
0 (refused by the fence: 0); Graph requests: 0; ARM requests: 0`; the record's category
`InvalidOperation` and its message `The structure document names tenant
'00000000-0000-0000-0000-000000000099', but the session's Microsoft Graph token was issued for tenant
'...'. ... so nothing was read or written for this document. ...`.
**Failure looks like:** a row, or Graph requests above 0 -- the document was applied in the session's
tenant.

Result:

### 3.2. Without -WhatIf: the same refusal

- [ ] **3.2** The same document, `-Include Groups -Confirm:$false` (a real run): the same refusal, no row, no Graph and no ARM request. Nothing can be written: the document names only `oer-s96b-grp`, and the run is refused before it reads it.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.tenantId = $OtherTenant
Invoke-S96b -Label '3.2 another tenant, a real run' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups -Confirm:$false }
Disconnect-OerLive
```

**Expect:** as 3.1.
**Failure looks like:** as 3.1.

Result:

### 3.3. With an Azure section: no Azure Resource Manager request either

- [ ] **3.3** 2.2's document with `tenantId` set to the other tenant, `-Include Groups,RoleAssignments -WhatIf`: `DocumentTenantMismatch`, no Graph and no ARM request -- the scope pre-pass included.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.roleAssignments = @([PSCustomObject]@{ scope = "/subscriptions/$($Cfg.SubscriptionId)"; role = 'Reader'; principal = 'oer-s96b-grp' })
$Doc.tenantId = $OtherTenant
Invoke-S96b -Label '3.3 another tenant, with an Azure section, -WhatIf' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups, RoleAssignments -WhatIf }
Disconnect-OerLive
```

**Expect:** `output objects 0; errors: DocumentTenantMismatch; ... Graph requests: 0; ARM requests: 0`.
**Failure looks like:** ARM requests above 0 -- the scope pre-pass ran for a refused document.

Result:

### 3.4. With -Prune and an omitted members key: no prune warning, nothing read

- [ ] **3.4** The document from another tenant with the group's `members` key removed, `-Include Groups -Prune -Confirm:$false`: `DocumentTenantMismatch` and no warning; the control, the same document with the test tenant's `tenantId` and `-WhatIf`, writes the omitted-collection warning, so its absence in the refusal is the check's.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
foreach ($G in @($Doc.groups)) { $G.PSObject.Properties.Remove('members') }
$Control = Copy-S96bDocument -Document $Doc
$Doc.tenantId = $OtherTenant
Invoke-S96b -Label '3.4 another tenant, -Prune, a real run' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups -Prune -Confirm:$false }
Invoke-S96b -Label '3.4 control: the test tenant, -Prune -WhatIf' -Call { Invoke-OERStructure -InputObject $Control -Include Groups -Prune -WhatIf }
Disconnect-OerLive
```

**Expect:** the refusal: `output objects 0; errors: DocumentTenantMismatch; warnings: 0; ... Graph
requests: 0; ARM requests: 0`. The control: `errors: none; warnings: 1`, the warning starting
`Invoke-OERStructure: -Prune is set and the document omits 1 collection key(s)`, and `row groups |
oer-s96b-grp | Unchanged` (the group has no member, so nothing is pruned).
**Failure looks like:** a warning in the refusal -- the warning stands before the check.

Result:

## 4. -TenantId naming another tenant than the document: refused before the sign-in

### 4.1. From no session, -TenantId the test tenant's GUID against the other tenant's document

- [ ] **4.1** After `Disconnect-OER`, `Invoke-OERStructure -TenantId` (the test tenant's GUID) with the document naming the other tenant: `DocumentTenantMismatch` and no token request.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.tenantId = $OtherTenant
Disconnect-OerLive
Invoke-S96b -Label '4.1 from no session, -TenantId the test tenant, another tenant''s document' -Call { Invoke-OERStructure -InputObject $Doc -TenantId $Cfg.TenantId -Include Groups -WhatIf }
```

**Expect:** `output objects 0; errors: DocumentTenantMismatch; ... token requests: 0 (refused by the
fence: 0); Graph requests: 0; ARM requests: 0; the module holds a session: False`; the message names
`-TenantId names tenant '...'` and `nothing was signed in to, read or written for this document`.
**Failure looks like:** `token requests: 1 (refused by the fence: 1)` -- the command reached its
sign-in; the fence refused the token request, so nothing was prompted for or sent.

Result:

### 4.2. The control: the test tenant's own document reaches its token request

- [ ] **4.2** The same from no session with the exported document (the test tenant's `tenantId`): the command does reach its token request, which the fence refuses (`Invoke-OERStructure` takes no certificate) -- so 4.1's zero is the check's. Its refused sign-in leaves no session, and the document is refused too.

```powershell
# Block H first, in this process.
$Inv = Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32
Disconnect-OerLive
Invoke-S96b -Label '4.2 control: from no session, -TenantId the test tenant, its own document' -Call { Invoke-OERStructure -InputObject $Inv -TenantId $Cfg.TenantId -Include Groups -WhatIf }
```

**Expect:** `token requests: 1 (refused by the fence: 1); Graph requests: 0; ARM requests: 0; the module
holds a session: False`; the errors: the sign-in's own failure, and `DocumentTenantMismatch` whose
message says the session holds no Microsoft Graph token whose tenant can be compared with it.
**Failure looks like:** `token requests: 0` -- the fence did not shadow the module (4.1 proves
nothing); a Graph request -- something was sent without a session (STOP).

Result:

### 4.3. -TenantId by domain is compared after the sign-in, through its token

- [ ] **4.3** `Connect-OER` by the primary domain, then `Invoke-OERStructure -TenantId` (the same domain) with the other tenant's document: refused after the sign-in, which was the session's cached return -- no lookup, no token request, no Graph and no ARM request.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.tenantId = $OtherTenant
Disconnect-OerLive
Invoke-S96b -Label '4.3 Connect-OER by domain' -Call { Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
Invoke-S96b -Label '4.3 -TenantId the domain, another tenant''s document' -Call { Invoke-OERStructure -InputObject $Doc -TenantId $Cfg.UserDomain -Include Groups -WhatIf }
Disconnect-OerLive
```

**Expect:** the sign-in: one lookup, two token requests, no error. The apply: `output objects 0;
errors: DocumentTenantMismatch; lookups: 0; token requests: 0; Graph requests: 0; ARM requests: 0`, the
message naming the session's Microsoft Graph token.
**Failure looks like:** a row -- the document was applied.

Result:

## 5. A document without tenantId behaves as before

### 5.1. The exported document with tenantId removed: the same plan as 2.1, without and with -TenantId

- [ ] **5.1** The exported document with the `tenantId` key removed: `-Include Groups -WhatIf` plans `oer-s96b-grp` `Unchanged` with no error, and so does the same with `-TenantId` (the test tenant's GUID); no `DocumentTenantMismatch`.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.PSObject.Properties.Remove('tenantId')
Write-OerLiveStep "5.1 the document carries tenantId: $(@($Doc.PSObject.Properties.Name) -contains 'tenantId')"
Invoke-S96b -Label '5.1 no tenantId, -WhatIf' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups -WhatIf }
Invoke-S96b -Label '5.1 no tenantId, -TenantId the test tenant, -WhatIf' -Call { Invoke-OERStructure -InputObject $Doc -TenantId $Cfg.TenantId -Include Groups -WhatIf }
Disconnect-OerLive
```

**Expect:** `carries tenantId: False`; both: `errors: none`, Graph requests the same as 2.1's, `row
groups | oer-s96b-grp | Unchanged`.
**Failure looks like:** any error -- a document without the key is no longer applied as before.

Result:

## 6. The validator refuses a tenantId that is not a GUID

### 6.1. Test-OERStructure: an Error at tenantId for a value that is not a GUID; valid for the export

- [ ] **6.1** `Test-OERStructure` (offline) on the exported document: valid. With `tenantId` set to `not-a-guid`, to `null`, to the primary domain and to a braced GUID: not valid, one Error at path `tenantId` each.

```powershell
# Block H first, in this process (only for the config; this check makes no request).
$Inv = Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32
$R = Test-OERStructure -InputObject $Inv
Write-OerLiveStep "6.1 the exported document: Valid $($R.Valid); findings at tenantId: $(@($R.Errors | Where-Object { $_.Path -eq 'tenantId' }).Count)"
foreach ($Case in @(@('not-a-guid', 'not-a-guid'), @('null', $null), @('the primary domain', $Cfg.UserDomain), @('a braced GUID', '{' + $Cfg.TenantId + '}'))) {
    $Doc = Copy-S96bDocument -Document $Inv
    $Doc.tenantId = $Case[1]
    $R = Test-OERStructure -InputObject $Doc
    $F = @($R.Errors | Where-Object { $_.Path -eq 'tenantId' })
    Write-OerLiveStep "6.1 $($Case[0]): Valid $($R.Valid); findings at tenantId: $($F.Count); severity: $(($F | ForEach-Object { $_.Severity }) -join ', '); message: $(ConvertTo-OerLiveRedacted -Text (($F | ForEach-Object { $_.Message }) -join ' | '))"
}
Disconnect-OerLive
```

**Expect:** the export: `Valid True; findings at tenantId: 0`; each case: `Valid False; findings at
tenantId: 1; severity: Error; message: 'tenantId' must be the tenant ID the document was exported
from, in the canonical GUID form ...`.
**Failure looks like:** `Valid True` for a case -- the key is not checked.

Result:

### 6.2. Invoke-OERStructure: StructureValidationFailed, before any sign-in

- [ ] **6.2** `Invoke-OERStructure` with `tenantId` set to `not-a-guid`: `StructureValidationFailed`, no token request, no Graph and no ARM request.

```powershell
# Block H first, in this process.
$Doc = Copy-S96bDocument -Document (Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32)
$Doc.tenantId = 'not-a-guid'
Invoke-S96b -Label '6.2 tenantId not a GUID' -Call { Invoke-OERStructure -InputObject $Doc -Include Groups -WhatIf }
Disconnect-OerLive
```

**Expect:** `output objects 0; errors: StructureValidationFailed; ... token requests: 0; Graph requests:
0; ARM requests: 0`, the message naming `tenantId`.
**Failure looks like:** `DocumentTenantMismatch` -- the validation does not run first.

Result:

## 7. BL-88's shape: Invoke-OERStructure inside a ForEach-Object block

### 7.1. In one tenant: a document naming another tenant is refused whatever session the inner command takes

- [ ] **7.1** After the sign-in, `@(1) | ForEach-Object { Invoke-OERStructure -InputObject` (the other tenant's document) `-Include Groups -WhatIf } | ForEach-Object -Begin { Connect-OER` (the test tenant, with the certificate) `} -Process { $_ }`: the inner command begins after the downstream `-Begin`'s sign-in and takes that session for its own, and its document is refused with `DocumentTenantMismatch`, with no Graph and no ARM request. The control, the test tenant's document in the same shape, is planned.

```powershell
# Block H first, in this process.
$Inv = Get-Content -LiteralPath $InventoryFile -Raw | ConvertFrom-Json -Depth 32
$Doc = Copy-S96bDocument -Document $Inv
$Doc.tenantId = $OtherTenant
Invoke-S96b -Label '7.1 BL-88 shape, another tenant''s document' -Call {
    @(1) | ForEach-Object { Invoke-OERStructure -InputObject $Doc -Include Groups -WhatIf } |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert } -Process { $_ }
}
Invoke-S96b -Label '7.1 control: BL-88 shape, the test tenant''s document' -Call {
    @(1) | ForEach-Object { Invoke-OERStructure -InputObject $Inv -Include Groups -WhatIf } |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert } -Process { $_ }
}
Disconnect-OerLive
```

**Expect:** the refusal: `output objects 0; errors: DocumentTenantMismatch; ... Graph requests: 0; ARM
requests: 0` (the token requests are the `-Begin` sign-in's own, if any). The control: `errors: none`,
Graph requests above 0, `row groups | oer-s96b-grp | Unchanged`.
**Failure looks like:** a row for the other tenant's document -- the check does not run for a command
inside a script block.

Result:

### 7.2. With a second tenant (class B)

- [ ] **7.2** BL-88 with a real second tenant: class B (G9). The test environment reaches one tenant.

The shape in which the downstream `-Begin` signs in to ANOTHER tenant cannot be produced with this
certificate. It is proved end to end in a runspace with no `try`, with the real `Initialize-OERAuth`
over stubbed transports: P19 to P19e in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, Describe
`A command whose sign-in a later command in the pipeline replaced sends nothing (A20, F-E)`, and by the unit Describe
`Invoke-OERStructure refuses a document from another tenant (BL-88, A14)`.

Result:

## T. Teardown

### T.1. The prerequisite script removes oer-s96b-grp

- [ ] **T.1** `Initialize-OerS96bPrereq.ps1 -Teardown -Unattended`: `oer-s96b-grp` removed, the sweep finds no prefixed object, the group count equals the baseline, no residue.

```powershell
$VaultDir = $env:OER_LIVE_DIR
pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96bPrereq.ps1') -Teardown -Unattended
pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96bPrereq.ps1') -ReadBack
```

**Expect:** the group removed, `Counts: groups now N, at the baseline N; equal: True`, exit code 0;
the read-back: `prefixed objects left: 0; unread collections: 0; residue rows: 0`.
**Failure looks like:** a residue line or exit code 3 -- record it and retry with the read-back.

Result:

### T.2. The documents and the exported bundle are deleted

- [ ] **T.2** The raw folder's documents and the bundle of 1.3 are deleted after the results are written up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s96b'
Remove-Item -LiteralPath (Join-Path $Raw 'bundle') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $Raw 'inventory-1.1.json') -Force -ErrorAction SilentlyContinue
Write-OerLiveStep "T.2 the bundle is gone: $(-not (Test-Path -LiteralPath (Join-Path $Raw 'bundle'))); the exported document is gone: $(-not (Test-Path -LiteralPath (Join-Path $Raw 'inventory-1.1.json')))"
```

**Expect:** `True; True`. The rest of `raw\s96b` (transcripts, baseline) is deleted once the
write-up has passed its read-back.

Result:

### T.3. No session is left, and the main clone was never switched

- [ ] **T.3** No module or Graph SDK session in a fresh process, and the main clone is still on `main` at the HEAD S.1 recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96b-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "T.3 Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7)); a Graph SDK session in this process: $([bool](Get-MgContext -ErrorAction SilentlyContinue))"
```

**Expect:** `branch main`, the HEAD S.1 printed, `a Graph SDK session in this process: False`.

Result:
