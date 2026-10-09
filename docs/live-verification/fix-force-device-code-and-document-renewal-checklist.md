# Live verification checklist -- every device code sign-in is forced, and how a long run renews (fix/force-device-code-and-document-renewal)

**This branch does not merge until every box in sections S, 0, 1, 2 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out
to be impossible to run, write "cannot be verified, and therefore we do not know" on its result line
and say why; do not leave it blank and do not tick it. A check that could not run for a stated reason
is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B)**: device code
and interactive sign-ins are never run here.

**What this file writes to the tenant: nothing.** No object is created, changed or removed, so there
is no prerequisite script and no baseline. Every request is a token request or a read.

**Who runs it.** Sections S, 0, 1, 2 and T: the dedicated certificate identity `oer-live-cc`, through
the OerLive library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in here is app-only, with the certificate;
nothing here signs in as a person, interactively or with a device code. A 401 or 403 as `oer-live-cc`
is a stop.

**Sign-ins.** Every block's first sign-in goes through `Connect-OerLive -Arm` (the module's own
`Connect-OER` with the certificate and `-IncludeARM`), which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and checks the identity as True/False. Sections 1 and 2 then install the
token fence (H.1) and make their own sign-ins with the same certificate, each after `Disconnect-OER`
and `Disconnect-MgGraph`, and print the new session's identity as True/False against the configuration
and the session the identity check verified.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s104b/`,
which is git-ignored. Every block prints through the library's redactor, so its lines are already
redacted per [README.md](README.md). **No credential, token, application id, tenant id, subscription
id, account or certificate thumbprint is ever printed, and the fence records parameter NAMES only,
never a value.** Each block is run in its own process whose whole output (standard output and standard
error) is written to a file under `raw\s104b\`, redacted with OerLive's redactor before anyone reads
it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-112 (decision A17): every device code token request carries `-Force`** ("fix: force every
  device code token request so a reused credential cannot hang"). `Initialize-OERAuth` adds `Force` to
  the Microsoft Graph and the Azure Resource Manager `Get-AzToken` request of every device code sign-in
  (`$DeviceCodeForced`), so AzAuth builds a new credential and prints a new code each time instead of
  reusing one that never returns. Every other sign-in type gets `Force` exactly as before: only for
  `-ForceRefresh` (`Connect-OER -Force`, a transport's 401 refresh) or a cloud switch. The cached
  return is unchanged.
- **B. BL-105: the known limit of a long run is documented** ("docs: describe how a long run renews
  its token per sign-in type", "docs: say every device code sign-in asks for a new code", "docs:
  record why every device code sign-in is forced and how a long run renews", "docs: narrow the device
  code release note and label the second code as measured", "docs: correct the renewal and device
  code comments and narrow the cached-session sentence"). README `### Long runs`, the about topic
  `LONG RUNS` and `Connect-OER`'s help say what a renewal needs per sign-in type; the device code
  known limitation now says every device code sign-in asks for a new code. No code.

Device code is never run here (G9, and the run's own rule: never a device code or interactive
sign-in). What a live tenant adds is the REGRESSION on the certificate path, through the module's
real `Get-AzToken`: a fence records the bound parameter names of every token request, and
`Connect-OER` with and without `-IncludeARM`, and a new `Connect-OER` after `Disconnect-OER`, request
their tokens WITHOUT `Force` (1.1-1.3). It also measures the long-run advice the new texts give for an
app-only run: a repeated `Connect-OER` answers from the cache while the token has more than five
minutes left, signs in again without `Force` inside that window, and `Connect-OER -Force` requests
both tokens with `Force` (1.4). And a Microsoft Graph read, a paged `-All` read and an Azure Resource
Manager read work as before (2.1-2.3).

## What this file does not check, and why

- **Device code and interactive sign-ins (class B, section B).** `oer-live-cc` is app-only, and this
  run never signs in as a person. Proved offline in `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`,
  Describe `Initialize-OERAuth forces every device code sign-in (A17, BL-112)`, and end to end through
  the two transports (E1-E3).
- **A managed identity (class B).** None is available to this run; the N tests cover it offline.
- **A 401 or a claims challenge (class B).** Nothing here can make the service reject a token on
  purpose; E1-E3 prove the device code refresh and step-up offline.
- **G8 (convergence).** This branch changes no write path of the apply engine.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence and the
readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s104b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s104b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null

function Start-S104bFence {
    # A global proxy of Get-AzToken, which the module calls unqualified. For every token request it records
    # the resource's kind (graph or arm) and the NAMES of the bound parameters, never a value, and it forwards
    # only a request that carries the certificate: any other would be an interactive or device code sign-in,
    # and is refused instead of prompting.
    $global:S104bTokenCalls = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $Kind = if ([string]$PSBoundParameters[''Resource''] -like ''*graph*'') { ''graph'' } elseif ([string]$PSBoundParameters[''Resource''] -like ''*management*'') { ''arm'' } else { ''other'' }; $global:S104bTokenCalls.Add(($Kind + '': '' + ((@($PSBoundParameters.Keys) | Sort-Object) -join '',''))); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S104b fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Write-S104bTokenCalls {
    # One line per recorded token request, then the totals. A block that never started the fence says so.
    if ($null -eq $global:S104bTokenCalls) { Write-OerLiveStep 'token requests: not fenced in this block'; return }
    foreach ($Call in $global:S104bTokenCalls) { Write-OerLiveStep "token request -- $Call" }
    $Names = @($global:S104bTokenCalls | ForEach-Object { , @((($_ -split ': ', 2)[1]) -split ',') })
    $Forced = @($Names | Where-Object { $_ -contains 'Force' }).Count
    $Person = @($Names | Where-Object { $_ -contains 'DeviceCode' -or $_ -contains 'Interactive' }).Count
    Write-OerLiveStep "token requests: $($global:S104bTokenCalls.Count); with Force: $Forced; with DeviceCode or Interactive: $Person"
}

function Connect-S104bCertificate {
    # The module's own Connect-OER with the certificate, as Connect-OerLive -Arm makes it, after
    # Disconnect-OER and Disconnect-MgGraph. The certificate object is dropped as soon as the call returns.
    param([switch]$IncludeARM, [switch]$Force, [switch]$KeepSession)
    if (-not $KeepSession) { Disconnect-OerLive }
    $Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
    try { $null = Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM:$IncludeARM -Force:$Force -ErrorAction Stop }
    finally { $Cert = $null }
}

function Get-S104bVerifiedObject {
    # The signed-in object of the session Connect-OerLive just verified, kept in a variable and never printed.
    & (Get-Module -Name Omnicit.EntraRBAC) { ([string]$script:_OERAuthState.SignedInObjectId).ToLowerInvariant() }
}

function Get-S104bSession {
    # The module session's identity as True/False against the configuration and the verified session.
    param([string]$VerifiedObject)
    $S = & (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState }
    $Method = [string]$S.AuthMethod -eq 'ClientCertificate'
    $Client = ([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId
    $Tenant = (([string]$S.TenantId).ToLowerInvariant() -eq $Cfg.TenantId) -and (([string]$S.TokenTenantId).ToLowerInvariant() -eq $Cfg.TenantId)
    $Object = [bool]$VerifiedObject -and (([string]$S.SignedInObjectId).ToLowerInvariant() -eq $VerifiedObject)
    $Arm = if ($S.ArmToken) { [string](([string]$S.ArmTokenTenantId).ToLowerInvariant() -eq $Cfg.TenantId) } else { 'no ARM token' }
    $Left = if ($S.GraphTokenExpiry) { [int][math]::Floor(($S.GraphTokenExpiry - [DateTime]::UtcNow).TotalMinutes) } else { 'none' }
    "certificate session: $Method; the identity's app id: $Client; the test tenant, requested and granted: $Tenant; the signed-in object the identity check verified: $Object; ARM token for the test tenant: $Arm; Graph token minutes left: $Left"
}

function Set-S104bExpiry {
    # Moves the RECORDED expiry of the module's Microsoft Graph token, in the module's scope. The token itself
    # is never read or changed, so the service still accepts it.
    param([Parameter(Mandatory)][double]$Minutes)
    & (Get-Module -Name Omnicit.EntraRBAC) { param($Mi) $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($Mi) } $Minutes
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
$Owner = & $Has '[bool]$DeviceCodeForced = $EffectiveMethod -eq ''DeviceCode'''
$Decision = & $Has 'if ($ForceRefresh -or $DeviceCodeForced -or'
$Kept = & $Has '-not $ForceRefresh -and -not $DeviceCodeForced'
Write-OerLiveStep "The worktree's build carries the device code force: $Owner; on the Force decision: $Decision; kept for the ARM request: $Kept"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; the three build lines `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Write-OerLiveStep (Get-S104bSession -VerifiedObject (Get-S104bVerifiedObject))
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, `The module is the worktree's
build: True`, and the session line `True` throughout, with about an hour of Graph token left.
**Failure looks like:** any `False` in the identity lines, or `application is disabled` -- STOP: the
identity is not enabled for this run; never sign in another way.

Result:

## 1. The certificate path requests its tokens without Force (regression, A)

### 1.1. Connect-OER with -IncludeARM

- [ ] **1.1** After `Disconnect-OER`, `Connect-OER` with the certificate and `-IncludeARM` makes two token requests, one for Microsoft Graph and one for Azure Resource Manager, neither with `Force`, and the session it builds is the verified identity's.

```powershell
Connect-OerLive -Arm
$Verified = Get-S104bVerifiedObject
Start-S104bFence
Connect-S104bCertificate -IncludeARM
Write-OerLiveStep (Get-S104bSession -VerifiedObject $Verified)
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** two `token request` lines, `graph` and `arm`, each naming `ClientCertificate`,
`ClientId`, `ErrorAction`, `Resource` and `Tenant` and NOT `Force`; `token requests: 2; with Force: 0;
with DeviceCode or Interactive: 0`; the session line `True` throughout.
**Failure looks like:** `Force` among the names, a third request, a fence refusal, or a `False` in the
session line.

Result:

### 1.2. Connect-OER without -IncludeARM

- [ ] **1.2** After `Disconnect-OER`, `Connect-OER` with the certificate and without `-IncludeARM` makes one Microsoft Graph token request, without `Force`.

```powershell
Connect-OerLive -Arm
$Verified = Get-S104bVerifiedObject
Start-S104bFence
Connect-S104bCertificate
Write-OerLiveStep (Get-S104bSession -VerifiedObject $Verified)
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** one `token request -- graph: ...` line without `Force`; `token requests: 1; with Force: 0;
with DeviceCode or Interactive: 0`; the session line `True` with `ARM token for the test tenant: no
ARM token`.
**Failure looks like:** `Force` among the names, an ARM request, or a `False` in the session line.

Result:

### 1.3. A new Connect-OER after Disconnect-OER

- [ ] **1.3** In one process, `Connect-OER -IncludeARM`, then `Disconnect-OER` and `Disconnect-MgGraph`, then `Connect-OER -IncludeARM` again: four token requests in all, none with `Force`, and the second session is the verified identity's.

```powershell
Connect-OerLive -Arm
$Verified = Get-S104bVerifiedObject
Start-S104bFence
Connect-S104bCertificate -IncludeARM
Write-OerLiveStep "first sign-in: $(Get-S104bSession -VerifiedObject $Verified)"
Connect-S104bCertificate -IncludeARM
Write-OerLiveStep "after Disconnect-OER, the new sign-in: $(Get-S104bSession -VerifiedObject $Verified)"
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** four `token request` lines, `graph`, `arm`, `graph`, `arm`, none naming `Force`; `token
requests: 4; with Force: 0; with DeviceCode or Interactive: 0`; both session lines `True` throughout.
**Failure looks like:** `Force` among the names, a fence refusal, or a `False` in a session line.

Result:

### 1.4. Connect-OER again on a live session: the cache, the five-minute window and -Force

- [ ] **1.4** On the session `Connect-OerLive -Arm` verified, a repeated `Connect-OER -IncludeARM` answers from the cache (no token request); with the Graph token's recorded expiry moved two minutes ahead it signs in again with one Graph request without `Force`; and `Connect-OER -IncludeARM -Force` requests both tokens with `Force`, as before this branch.

```powershell
Connect-OerLive -Arm
$Verified = Get-S104bVerifiedObject
Start-S104bFence
Connect-S104bCertificate -IncludeARM -KeepSession
Write-OerLiveStep "repeated Connect-OER, token far from expiry: $($global:S104bTokenCalls.Count) token requests"
Set-S104bExpiry -Minutes 2
Connect-S104bCertificate -IncludeARM -KeepSession
Write-OerLiveStep "repeated Connect-OER, Graph token two minutes from expiry: $(Get-S104bSession -VerifiedObject $Verified)"
$Inside = $global:S104bTokenCalls.Count
Connect-S104bCertificate -IncludeARM -Force -KeepSession
Write-OerLiveStep "Connect-OER -Force: $(Get-S104bSession -VerifiedObject $Verified); requests made by it: $($global:S104bTokenCalls.Count - $Inside)"
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** `repeated Connect-OER, token far from expiry: 0 token requests`; after the move one
`graph` request without `Force` and a session line `True` with about an hour left again; then
`Connect-OER -Force` with two requests, `graph` and `arm`, both naming `Force`; in all `token
requests: 3; with Force: 2; with DeviceCode or Interactive: 0`.
**Failure looks like:** a request from the first repeat (the cache was bypassed), an ARM request or
`Force` on the in-window renewal, or a `-Force` request without `Force`.

Result:

## 2. Ordinary commands read as before (regression)

### 2.1. A Microsoft Graph read

- [ ] **2.1** `Get-OERGroup` on a fresh module session returns groups with no token request and no error.

```powershell
Connect-OerLive -Arm
Start-S104bFence
$E = $null
$Out = @(Get-OERGroup -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "groups returned: $($Out.Count); errors: $(@($E).Count)"
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** at least one group, errors 0; `token requests: 0`.
**Failure looks like:** an error, a token request, or no group.

Result:

### 2.2. A paged -All read

- [ ] **2.2** A paged read of the tenant's groups two at a time (`-All`) returns exactly the groups one large page returns, and `Get-OERGroup -All` returns as many, with no token request and no error.

```powershell
Connect-OerLive -Arm
Start-S104bFence
$Paged = & (Get-Module -Name Omnicit.EntraRBAC) { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=2&$select=id' -All }
$Whole = & (Get-Module -Name Omnicit.EntraRBAC) { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=999&$select=id' -All }
$PagedIds = @($Paged.value | ForEach-Object { [string]$_.id } | Sort-Object)
$WholeIds = @($Whole.value | ForEach-Object { [string]$_.id } | Sort-Object)
$E = $null
$Groups = @(Get-OERGroup -All -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "paged read: $($PagedIds.Count) groups; one large page: $($WholeIds.Count) groups; the same groups: $(($PagedIds -join ',') -eq ($WholeIds -join ','))"
Write-OerLiveStep "Get-OERGroup -All: $($Groups.Count) groups; errors: $(@($E).Count); as many as the transport read: $($Groups.Count -eq $WholeIds.Count)"
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** the same groups `True`; `Get-OERGroup -All` errors 0 and as many `True`; `token requests:
0`.
**Failure looks like:** a different set of groups (a page lost or read twice), an error, or a token
request.

Result:

### 2.3. An Azure Resource Manager read

- [ ] **2.3** `Get-OERSubscription` on a fresh module session returns the test subscription, with no token request and no error.

```powershell
Connect-OerLive -Arm
Start-S104bFence
$E = $null
$Out = @(Get-OERSubscription -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "subscriptions returned: $($Out.Count); the test subscription is among them: $(@($Out | Where-Object { [string]$_.SubscriptionId -eq $Cfg.SubscriptionId }).Count -eq 1); errors: $(@($E).Count)"
Write-S104bTokenCalls
Disconnect-OerLive
```

**Expect:** at least one subscription, the test subscription among them `True`, errors 0; `token
requests: 0`.
**Failure looks like:** an error, a token request, or the test subscription missing.

Result:

## B. Proved offline (class B): device code and interactive are never run here

Each is a unit test with the real `Initialize-OERAuth` and a mocked `Get-AzToken`; none of them signs
in. `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe `Initialize-OERAuth forces every
device code sign-in (A17, BL-112)`:

| Path | Device code: `Force` on the request | Other types (Interactive, ManagedIdentity, ClientSecret, ClientCertificate): no `Force` |
|---|---|---|
| `Connect-OER` with `-IncludeARM` | D1 (Graph and ARM) | N4 (after `Disconnect-OER`) and N1 |
| `Connect-OER` without `-IncludeARM` | D1b | -- |
| A command's start near expiry | D2, D2b (`Get-OERSubscription`), D3 (ARM alone) | N2 |
| `-ForceRefresh` | D4 | (unchanged: `Force`, as before) |
| A claims challenge | D5, and E1 through the Graph transport | N3 |
| After `Disconnect-OER` | D6 | N4 |
| The cache is unchanged | D7 | -- |
| The code is still shown | D8 (both codes on the information stream, Force bound) | -- |
| A 401 refresh | E2 (Graph), E3 (ARM) | (unchanged) |

The mutants that turn them red are in the PR description and in
`docs/development/rationale.md`, under the subsection on why every device code sign-in is forced.

## Teardown

### T.1. Nothing left: no session and nothing with the prefix

- [ ] **T.1** No module session and no Graph SDK session remain, and the sweep finds nothing with the prefix `oer-s104b-` and no unread collection.

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
$State = & (Get-Module -Name Omnicit.EntraRBAC) { $null -eq $script:_OERAuthState }
Write-OerLiveStep "module session cleared: $State; Graph SDK session left: $([bool](Get-MgContext))"
```

**Expect:** 0 objects, 0 unread collections; `module session cleared: True; Graph SDK session left:
False`.
**Failure looks like:** an object or an unread collection (STOP: this run creates nothing), or a
session left.

Result:
