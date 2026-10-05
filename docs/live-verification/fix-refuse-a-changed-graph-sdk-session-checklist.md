# Live verification checklist -- a Graph call is refused when the Graph SDK session changed under the module (fix/refuse-a-changed-graph-sdk-session)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes nothing to the tenant.** No object is created, changed or deleted, and every
Microsoft Graph request below is a read. The prefix `oer-s84b-` appears only in the name of a group
that does not exist, `oer-s84b-does-not-exist`, which the module is asked to read. There is no
prerequisite script and no teardown of objects.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph), and its no-permission twin `oer-live-cc-noperm`. A 403 for `oer-live-cc-noperm` is the
expected answer in 1.3, not a stop. A 401 or 403 as `oer-live-cc` is a stop. Every sign-in is
app-only; nothing here signs in as a person.

**These checks sign in twice in one process, on purpose.** Every block's FIRST sign-in goes through
`Connect-OerLive`, which runs `Disconnect-OER` and `Disconnect-MgGraph` first. The SECOND sign-in --
`Connect-MgGraph -ContextScope Process` as `oer-live-cc-noperm`, or `Connect-OER` again -- is NOT
preceded by a disconnect: replacing the Graph SDK session under a module that is still connected is
exactly what this branch is about. Every `Connect-MgGraph` here carries `-ContextScope Process`, so no
SDK token cache is written to disk, and every sign-in is followed by its identity lines as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s84b/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, account or certificate
thumbprint is ever printed**: the Graph SDK context is described by type, by True/False against the
expected value, and by enumeration values (`AuthType`, `TokenCredentialType`, `ContextScope`,
`Environment`) only. **Never render an error record**: every block prints the error id, category and
message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The module remembers the Graph SDK session it connected** ("record the Graph SDK session the
  module connected"). Straight after its own `Connect-MgGraph`, `Initialize-OERAuth` stores a
  fingerprint of `Get-MgContext`: `AuthType`, `TokenCredentialType`, `ClientId`, `TenantId`,
  `Account`, `AppName`, `Environment` and the sorted `Scopes`. Never a token, never the context object.
- **B. A session the module did not connect is refused** ("refuse a Graph call under a session the
  module did not connect", decision A18). Every `Initialize-OERAuth` entry, the cached return
  included, compares the session; another `Connect-MgGraph` gives the terminating `GraphSessionChanged`
  (AuthenticationError, target the module's tenant), and `Invoke-OERGraphRequest` refuses again
  before every Graph call, since a cmdlet carries on past `Initialize-OERAuth`'s refusal. No session at
  all is a cache miss; the module never switches the session back by itself.
- **C. `Connect-OER` takes the session back** ("let Connect-OER take the Graph SDK session back").
- **D. A refused sign-in that names another tenant leaves no ARM token behind** ("drop the cached ARM
  token when a refused sign-in names another tenant", decision R20 of the step). A cmdlet carries on
  past the refusal when it is called outside a try, and its Azure calls send the module's cached ARM
  token; a request naming another tenant, identity or cloud therefore drops that token first.
- **E. The paged read ends on a refused page** ("end a paged Graph read that a refusal interrupts"),
  and the fingerprint is compared ordinally ("compare the Graph SDK session fingerprint ordinally").

A live tenant is needed for what mocks cannot show: what `Get-MgContext` really holds after the
module's `Connect-MgGraph -AccessToken` and after a certificate `Connect-MgGraph` for another app in the
same tenant (section 1, which decides whether the fingerprint tells them apart); that the latest
`Connect-MgGraph` in a process really carries the Graph calls (1.3, the defect's premise); and that
on this branch the module's read is refused before any Graph request leaves (section 2).

## What this file does not check, and why

- **No session after `Disconnect-MgGraph` for a delegated or managed identity session** reconnects by
  itself (a cache miss). Both identities here are app-only, which cannot renew: their `Disconnect-MgGraph`
  case gives `AppOnlySessionCredentialUnavailable` instead (2.4). The delegated case needs a person to
  sign in, which no check in Sprint 8 may do (G9). Class B: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`,
  Describe `Initialize-OERAuth Graph SDK session check (A18)`, test A2.
- **An Azure-only cmdlet of the module's own tenant, the token-rejected retry and the claims-challenge
  retry** under a changed session are refused at their entry too, and keep the module's ARM token
  (class B: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe `Initialize-OERAuth Graph SDK
  session check (A18)`, A6 to A9 and A13, and `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`,
  G5). A cmdlet that names ANOTHER tenant with `-TenantId` is refused and its ARM token is dropped
  first (A12, G10); 2.5 runs that case live.- **The refusal under `-ErrorAction SilentlyContinue`, outside any `try`.** 2.2 runs it through a
  cmdlet; the wrapper's own shape is class B (G7 in the same Describe, in a runspace with no `try`).
- **Convergence (G8)** does not apply: nothing in this branch writes.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`). Every block starts with the same five lines, so each block also runs on its own in
  a fresh window. Run every block in its OWN PowerShell process: the checks depend on what one process
  holds.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and `oer-live-cc-noperm`.
  This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.1 read that it was not).

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Get-OERGraphSessionFingerprint' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "'GraphSessionChanged'" -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'ReclaimGraphSession = $true' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$script:_OERAuthState.ArmTokenTenantId = $null' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C; D: $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True; D: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
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

### 0.2. Identity check as oer-live-cc-noperm, a Graph SDK session

- [ ] **0.2** The no-permission identity signs in to a Graph SDK session of its own.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Graph -NoPerm
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, `identity check passed: True`.
**Failure looks like:** any `False` -- STOP; sections 1 and 2 need this identity.

Result:

### 1. The measurement and the premise

### 1.1. What Get-MgContext holds: the module's session, then another app's certificate session

- [ ] **1.1** `Get-MgContext` after `Connect-OER` as `oer-live-cc`, and after `Connect-MgGraph -ContextScope Process` as `oer-live-cc-noperm` in the same process, described property by property without a value; the module's fingerprint tells the two apart.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
function Show-S84bContext {
    param([string]$Label, [object]$Ctx, [string]$AppId, [string]$AppName)
    if ($null -eq $Ctx) { Write-OerLiveStep "$($Label): Get-MgContext returned nothing"; return }
    $Type = $Ctx.GetType().FullName
    Write-OerLiveStep "$($Label): type $Type"
    Write-OerLiveStep "$($Label): AuthType $($Ctx.AuthType); TokenCredentialType $($Ctx.TokenCredentialType); ContextScope $($Ctx.ContextScope); Environment $($Ctx.Environment)"
    Write-OerLiveStep "$($Label): ClientId is the expected app id: $([string]$Ctx.ClientId -eq $AppId); TenantId is the test tenant: $(([string]$Ctx.TenantId).ToLowerInvariant() -eq $Cfg.TenantId); AppName is $($AppName): $([string]$Ctx.AppName -ceq $AppName)"
    Write-OerLiveStep "$($Label): Account populated: $(-not [string]::IsNullOrEmpty([string]$Ctx.Account)); Scopes: $(@($Ctx.Scopes).Count) entries; CertificateThumbprint populated: $(-not [string]::IsNullOrEmpty([string]$Ctx.CertificateThumbprint)); ClientSecret populated: $($null -ne $Ctx.ClientSecret); Certificate populated: $($null -ne $Ctx.Certificate); ManagedIdentityId populated: $(-not [string]::IsNullOrEmpty([string]$Ctx.ManagedIdentityId))"
}
$Own1 = Get-MgContext
$Own2 = Get-MgContext
Show-S84bContext -Label "After Connect-OER as oer-live-cc" -Ctx $Own1 -AppId $Cfg.AppId -AppName 'oer-live-cc'
Write-OerLiveStep "Two Get-MgContext calls return the same object: $([object]::ReferenceEquals($Own1, $Own2))"
$OwnPrint = & $Module { Get-OERGraphSessionFingerprint }
$Recorded = & $Module { $script:_OERAuthState.GraphSessionFingerprint }
Write-OerLiveStep "The module's recorded fingerprint equals the one Get-MgContext gives now: $($OwnPrint -ceq $Recorded); it holds no token: $(-not ([string]$Recorded).Contains('eyJ'))"
Write-OerLiveStep "Get-OERGraphSessionState: $(& $Module { Get-OERGraphSessionState })"
$Swap = 'direct'
try {
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
} catch {
    Write-OerLiveStep "Connect-MgGraph straight after Connect-OER failed: $($PSItem.Exception.GetType().Name) -- $(ConvertTo-OerLiveRedacted -Text $PSItem.Exception.Message)"
    Clear-OerLiveErrorRecord -Record $PSItem
    $Swap = 'after Disconnect-MgGraph'
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
}
Write-OerLiveStep "Swap made: $Swap"
$Other = Get-MgContext
Show-S84bContext -Label "After Connect-MgGraph as oer-live-cc-noperm" -Ctx $Other -AppId $Cfg.NoPermAppId -AppName 'oer-live-cc-noperm'
Write-OerLiveStep "The noperm session is another object than the module's: $(-not [object]::ReferenceEquals($Own1, $Other))"
$OtherPrint = & $Module { Get-OERGraphSessionFingerprint }
Write-OerLiveStep "The fingerprints differ: $($OtherPrint -cne $Recorded)"
Write-OerLiveStep "Get-OERGraphSessionState: $(& $Module { Get-OERGraphSessionState })"
$Own1 = $null; $Own2 = $null; $Other = $null; $OwnPrint = $null; $OtherPrint = $null; $Recorded = $null
Disconnect-OerLive
```

**Expect:** after `Connect-OER`: `AuthType UserProvidedAccessToken; TokenCredentialType
UserProvidedAccessToken; ContextScope Process; Environment Global`; `ClientId is the expected app id:
True`, `TenantId is the test tenant: True`, `AppName is oer-live-cc: True`; `Account populated: False`
(app-only); `CertificateThumbprint`, `ClientSecret`, `Certificate` and `ManagedIdentityId` populated
`False`; two calls return the same object `True`; the recorded fingerprint equals the current one
`True`, holds no token `True`; state `Own`. After the swap (either way, recorded): `AuthType AppOnly;
TokenCredentialType ClientCertificate; ContextScope Process`; `ClientId is the expected app id: True`
for the noperm app id, the test tenant `True`, `AppName is oer-live-cc-noperm: True`;
`CertificateThumbprint populated: True`; another object `True`; `The fingerprints differ: True`; state
`Changed`.
**Failure looks like:** `The fingerprints differ: False` -- the fingerprint cannot tell the two
sessions apart: STOP (the spec's own stop for this measurement); `ClientSecret populated: True` or a
token in the fingerprint -- STOP; any identity `False` -- STOP.

Result:

### 1.2. How often Get-MgContext is read, and that no Graph call is added, per cmdlet

- [ ] **1.2** One `Get-OERGroup` read on the module's own session: `Get-MgContext` reads and Graph requests counted by a forwarding fence.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
# The fence: two global functions the module's unqualified calls resolve to (a function outranks a
# cmdlet). Each counts and forwards to the real SDK cmdlet, module-qualified.
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$Fence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S84bGraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Fence))
Set-Item -Path function:global:Get-MgContext -Value { $global:S84bContextReads++; Microsoft.Graph.Authentication\Get-MgContext }
$global:S84bGraphCalls = 0; $global:S84bContextReads = 0
$Out = @(Get-OERGroup -Group 'oer-s84b-does-not-exist' 2>&1)
$Errs = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Get-OERGroup on the module's own session: output objects $(@($Out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count); errors: $((@($Errs | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] })) -join ', ')"
Write-OerLiveStep "Graph requests: $global:S84bGraphCalls; Get-MgContext reads: $global:S84bContextReads"
Remove-Item -Path function:Invoke-MgGraphRequest, function:Get-MgContext
Disconnect-OerLive
```

**Expect:** errors `GroupNotFound` only; `Graph requests: 1` (the same one request `main` makes for a
read by name -- no Graph call is added); `Get-MgContext reads: 2` (one at the cmdlet's entry, one
before its one Graph request).
**Failure looks like:** more than 1 Graph request -- the check added a call; a `GraphSessionChanged` on
the module's own session -- the fingerprint is not stable across reads.

Result:

### 1.3. The premise: the latest Connect-MgGraph in the process carries the Graph calls

- [ ] **1.3** After `Connect-OER` as `oer-live-cc` and `Connect-MgGraph -ContextScope Process` as `oer-live-cc-noperm`, a raw `Invoke-MgGraphRequest` GET of one group answers 403: the latest connection carries the call.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$First = Microsoft.Graph.Authentication\Invoke-MgGraphRequest -Method GET -Uri 'v1.0/groups?$top=1&$select=id' -SkipHttpErrorCheck -StatusCodeVariable FirstStatus -ErrorAction Stop
Write-OerLiveStep "The same read as oer-live-cc, before the swap: HTTP $FirstStatus"
$First = $null
try {
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: direct'
} catch {
    Clear-OerLiveErrorRecord -Record $PSItem
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: after Disconnect-MgGraph'
}
$Ctx = Get-MgContext
Write-OerLiveStep "Identity: the session's app id is oer-live-cc-noperm's: $([string]$Ctx.ClientId -eq $Cfg.NoPermAppId); app name oer-live-cc-noperm: $([string]$Ctx.AppName -ceq 'oer-live-cc-noperm'); the test tenant: $(([string]$Ctx.TenantId).ToLowerInvariant() -eq $Cfg.TenantId)"
$Ctx = $null
$State = & (Get-Module -Name Omnicit.EntraRBAC) { [bool]$script:_OERAuthState }
Write-OerLiveStep "The module still holds its session state: $State"
$Body = Microsoft.Graph.Authentication\Invoke-MgGraphRequest -Method GET -Uri 'v1.0/groups?$top=1&$select=id' -SkipHttpErrorCheck -StatusCodeVariable Status -ErrorAction Stop
$Code = if ($Body -is [System.Collections.IDictionary] -and $Body['error']) { [string]$Body['error']['code'] } else { '' }
Write-OerLiveStep "The same read after the swap: HTTP $Status $Code"
$Body = $null
Disconnect-OerLive
```

**Expect:** before the swap `HTTP 200`; the noperm identity lines `True`; the module still holds its
state `True`; after the swap `HTTP 403 Authorization_RequestDenied`. The call went out under the
latest `Connect-MgGraph`, not the session `Connect-OER` set up: on `main`, every Graph call the module
made from here until its token's five-minute window went to that session.
**Failure looks like:** `HTTP 200` after the swap -- the SDK did not switch, and the premise of this
branch is wrong: STOP; a 401/403 for `oer-live-cc` before the swap -- STOP.

Result:

### 2. The fix on this branch

**2.1 to 2.5 run in ONE PowerShell process, in this order.** The first block starts with the five
lines and signs in; 2.2 to 2.5 continue in the same window, without those lines, since each
check turns on what the process already holds.

### 2.1. The module's own session: the read answers

- [ ] **2.1** On the module's own session, `Get-OERGroup` of `oer-s84b-does-not-exist` answers `GroupNotFound` with one Graph request.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
# The fence: a global function the module's unqualified call resolves to (a function outranks a
# cmdlet). It counts each Graph request and forwards it to the real SDK cmdlet, module-qualified.
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
$Fence = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S84bGraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Fence))
function Invoke-S84bRead {
    # A plain call, outside any try, as at a prompt; -Silent repeats it under -ErrorAction SilentlyContinue.
    param([string]$Label, [switch]$Silent)
    $global:S84bGraphCalls = 0
    if ($Silent) {
        $Out = @(Get-OERGroup -Group 'oer-s84b-does-not-exist' -ErrorAction SilentlyContinue -ErrorVariable S84bEv)
        $Errs = @($S84bEv | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    } else {
        $All = @(Get-OERGroup -Group 'oer-s84b-does-not-exist' 2>&1)
        $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
    $Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S84bGraphCalls; session state: $(& $Module { Get-OERGraphSessionState })"
    foreach ($E in @($Errs | Group-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { $_.Group[0] })) {
        $Text = ConvertTo-OerLiveRedacted -Text $E.Exception.Message
        if ($Text.Length -gt 400) { $Text = $Text.Substring(0, 400) + ' ...' }
        Write-OerLiveStep "$($Label): $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category); target is the module's tenant: $(([string]$E.TargetObject).ToLowerInvariant() -eq $Cfg.TenantId) -- $Text"
    }
}
Invoke-S84bRead -Label '2.1 the module''s own session'
```

**Expect:** `output objects 0; errors: GroupNotFound; Graph requests: 1; session state: Own`.
**Failure looks like:** `GraphSessionChanged` on the module's own session -- the fingerprint is not
stable; a 401/403 -- STOP.

Result:

### 2.2. After another Connect-MgGraph: refused, and no Graph request leaves

- [ ] **2.2** After `Connect-MgGraph -ContextScope Process` as `oer-live-cc-noperm`, the same read gives `GraphSessionChanged` and the fence counts 0 Graph requests, also under `-ErrorAction SilentlyContinue`.

```powershell
try {
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: direct'
} catch {
    Clear-OerLiveErrorRecord -Record $PSItem
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: after Disconnect-MgGraph'
}
$Ctx = Get-MgContext
Write-OerLiveStep "Identity: the session's app id is oer-live-cc-noperm's: $([string]$Ctx.ClientId -eq $Cfg.NoPermAppId); app name oer-live-cc-noperm: $([string]$Ctx.AppName -ceq 'oer-live-cc-noperm'); the test tenant: $(([string]$Ctx.TenantId).ToLowerInvariant() -eq $Cfg.TenantId)"
$Ctx = $null
Invoke-S84bRead -Label '2.2 after another Connect-MgGraph'
Invoke-S84bRead -Label '2.2 the same, -ErrorAction SilentlyContinue' -Silent
```

**Expect:** the noperm identity lines `True`; both reads `output objects 0`, errors
`GraphSessionChanged` (the cmdlet's entry, then the wrapper's gate, which the cmdlet reports as
itself), `Graph requests: 0`, `session state: Changed`; the error's category `AuthenticationError`,
target the module's tenant `True`, and a message that names `Connect-OER` and no other tenant. On
`main` the same read went out under the noperm session (1.3 shows that session answers 403).
**Failure looks like:** `Graph requests: 1` -- the read left under the other session, which is the
defect this branch closes; `GroupNotFound` or `Authorization_RequestDenied` -- the same.

Result:

### 2.3. Connect-OER takes the session back

- [ ] **2.3** `Connect-OER` again takes the session back, and the read answers `GroupNotFound` with one Graph request.

```powershell
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
try {
    Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction Stop
} finally { $Cert = $null }
$Ctx = Get-MgContext
$S = & $Module { $script:_OERAuthState }
Write-OerLiveStep "Identity: the session's app id is oer-live-cc's: $([string]$Ctx.ClientId -eq $Cfg.AppId); app name oer-live-cc: $([string]$Ctx.AppName -ceq 'oer-live-cc'); the test tenant: $(([string]$Ctx.TenantId).ToLowerInvariant() -eq $Cfg.TenantId); the module's state names the certificate app and the test tenant: $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId -and ([string]$S.TenantId).ToLowerInvariant() -eq $Cfg.TenantId -and [string]$S.AuthMethod -eq 'ClientCertificate')"
$Ctx = $null; $S = $null
Invoke-S84bRead -Label '2.3 after Connect-OER'
```

**Expect:** every identity line `True`; `output objects 0; errors: GroupNotFound; Graph requests: 1;
session state: Own`.
**Failure looks like:** `GraphSessionChanged` -- `Connect-OER` did not take the session back; a
401/403 for `oer-live-cc` -- STOP.

Result:

### 2.4. After Disconnect-MgGraph: no session, and an app-only session cannot connect again by itself

- [ ] **2.4** After `Disconnect-MgGraph`, the read gives `AppOnlySessionCredentialUnavailable` and no request can leave, since no session exists; after `Connect-OER` it answers again.

```powershell
Disconnect-MgGraph -ErrorAction Stop | Out-Null
Write-OerLiveStep "Get-MgContext after Disconnect-MgGraph returns nothing: $($null -eq (Get-MgContext))"
Invoke-S84bRead -Label '2.4 after Disconnect-MgGraph'
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
try {
    Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction Stop
} finally { $Cert = $null }
Write-OerLiveStep "Identity: the session's app id is oer-live-cc's: $([string](Get-MgContext).ClientId -eq $Cfg.AppId)"
Invoke-S84bRead -Label '2.4 after Connect-OER'
```

**Expect:** `Get-MgContext after Disconnect-MgGraph returns nothing: True`; the first read
`output objects 0`, `session state: Absent`, and first among its errors
`AppOnlySessionCredentialUnavailable`, with a message saying the Microsoft Graph PowerShell SDK session
was closed outside the module -- no session is a cache miss, and an app-only identity cannot mint a
token without its certificate, which the module never keeps. The cmdlet then still makes its one call
(the gate refuses only a CHANGED session), which the fence counts as `Graph requests: 1`; the SDK
refuses it locally because the process holds no session at all, and its error is the second one listed.
Nothing can go out under another session, since there is none. After `Connect-OER` the identity line
`True` and `errors: GroupNotFound; Graph requests: 1; session state: Own`. A delegated or managed
identity session would connect again by itself here (class B, test A2).
**Failure looks like:** `GraphSessionChanged` -- no session was taken for another one; a read that
answers (`GroupNotFound`) before `Connect-OER` -- a request went out with no session of the module's.
Result:

### 2.5. Another tenant named under a changed session: no Azure data, and no ARM token left to send

- [ ] **2.5** After another `Connect-MgGraph`, `Get-OERSubscription -TenantId` naming a tenant that is not the module's gets `GraphSessionChanged`, returns no subscription, and leaves the module no ARM token to send under the other tenant's name.

```powershell
try {
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: direct'
} catch {
    Clear-OerLiveErrorRecord -Record $PSItem
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -ClientId $Cfg.NoPermAppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
    Write-OerLiveStep 'Swap made: after Disconnect-MgGraph'
}
Write-OerLiveStep "Identity: the session's app id is oer-live-cc-noperm's: $([string](Get-MgContext).ClientId -eq $Cfg.NoPermAppId)"
$HadArm = [bool](& $Module { $script:_OERAuthState.ArmToken })
$global:S84bGraphCalls = 0
$All = @(Get-OERSubscription -TenantId '00000000-0000-0000-0000-000000000099' 2>&1)
$Subs = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
$Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Ids = @($Errs | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
$S = & $Module { $script:_OERAuthState }
Write-OerLiveStep "2.5 another tenant named: subscriptions returned $($Subs.Count); errors: $(if ($Ids) { $Ids -join ', ' } else { 'none' }); Graph requests: $global:S84bGraphCalls; the module held an ARM token before: $HadArm; after: $([bool]$S.ArmToken); its state still names the test tenant: $(([string]$S.TenantId).ToLowerInvariant() -eq $Cfg.TenantId)"
$Subs = $null; $S = $null
Disconnect-OerLive
```

**Expect:** the noperm identity line `True`; `subscriptions returned 0`; errors starting with
`GraphSessionChanged` (any further error is the Azure call that carries on with no token, which Azure
Resource Manager refuses); `Graph requests: 0`; `the module held an ARM token before: True; after:
False`; the state still names the test tenant `True`. `00000000-0000-0000-0000-000000000099` is a
deliberately non-existent id; nothing signs in to it. Before this branch's final fix the same call
returned the TEST tenant's subscriptions under the other tenant's name (measured offline in the
final review).
**Failure looks like:** `subscriptions returned 1` or more -- an Azure call went out with the module's
own ARM token under another tenant's name; `after: True` -- the token was not dropped.

Result:
## Teardown

### T.1. No session is left, nothing carries the prefix, and the main clone is untouched

- [ ] **T.1** `Disconnect-OER` and `Disconnect-MgGraph` leave no session; the sweep finds nothing with the prefix `oer-s84b-`; the main clone is still on `main` at the HEAD S.1 recorded; the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s84b-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s84b'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Left = @(Find-OerLivePrefixed -ThrowOnUnread)
Disconnect-OerLive
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "Prefixed objects: $($Left.Count); a Graph SDK session is left: $([bool](Get-MgContext)); the module holds a session: $([bool](& $Module { $script:_OERAuthState }))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the identity lines `True`; the sweep's "no ... starting with 'oer-s84b-' is left";
`Prefixed objects: 0; a Graph SDK session is left: False; the module holds a session: False`; the
main clone on `main` at the HEAD S.1 recorded. After the results are copied into this file:
`Clear-OerLiveRedactionMap`, and `raw\s84b\` deleted.
**Failure looks like:** a prefixed object -- nothing here creates one, so it is not this run's: STOP
and report it; a session left -- run `Disconnect-OER` and `Disconnect-MgGraph` again.

Result:
