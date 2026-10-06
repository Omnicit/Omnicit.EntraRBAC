# Live verification checklist -- a tenant named by domain is checked against the token, and a refused sign-in leaves the session uncertain (fix/verify-a-tenant-named-by-domain)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. Every check signs in, reads with a filter on the
prefix `oer-s93-` that matches no object, or runs `Invoke-OERStructure -WhatIf`. There is no
prerequisite script and no test object; the teardown only proves that nothing carries the prefix and
that no session is left. Section 4 writes two Tenant Profile files into the step's git-ignored raw
folder and deletes them in the teardown.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person, and no check needs
`oer-live-cc-noperm`. A 401 or 403 as `oer-live-cc` is a stop.

**Sign-ins.** Every block's first sign-in goes through `Connect-OerLive`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and checks the identity. A block that then signs in with `Connect-OER`
itself, by domain or by GUID, runs `Disconnect-OerLive` first. The `Connect-OER` calls that a check is
ABOUT -- a refused one followed by commands under the session it left -- follow the block's sign-in on
purpose: a disconnect between them would be the very thing the check must not do.

**The made-up domain.** The label `oer-s93-doesnotexist` under `onmicrosoft.com`, which names no
tenant (measured in section 1). The blocks join the two at run time, and every line they print shows
it as `MADE-UP-DOMAIN`.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s93/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, domain, account or
certificate thumbprint is ever printed** -- every comparison is printed as True or False -- and **no
error record is ever rendered**: every block prints the error id, the target of a `SignInRefused` (a
command name) and the message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The tenant lookup** ("add the tenant lookup helper and its owner rules"). The new private
  `Resolve-OERTenantDomain` asks the cloud's Microsoft Entra ID authority for its OpenID discovery
  document -- one unauthenticated GET, no `Authorization` header -- and reads the tenant ID from the
  document's issuer. It caches a tenant ID found per cloud and domain for the rest of the process.
- **B. BL-12, a domain is resolved before any token is requested** ("resolve a tenant named by domain
  before any token request"). `Initialize-OERAuth` looks a domain up after its cached return and
  before any token call, and refuses the sign-in with the new `TenantResolutionFailed` when the lookup
  fails -- no token is requested.
- **C. BL-12, the token is compared with the resolved tenant** ("compare a tenant named by domain
  with the token's tenant"). The Graph and ARM `TenantMismatch` checks, which compared a GUID only,
  now compare the domain's tenant ID too. The post-call tenant-switch warning, which could only warn
  about a domain, is retired: after the lookup it could fire only for a domain that names the very
  tenant its token came from.
- **D. BL-77** ("identify a sign-in by the tenant its token was issued for"). The sign-in identity's
  tenant term is the tenant the Graph token was issued for when that is a GUID, never the ARM token's.
- **E. A10, BL-89** ("refuse a command that names no tenant after a refused sign-in"). A sign-in that
  fails or is refused leaves the session uncertain: until a command that names its tenant signs in,
  or `Connect-OER` or `Disconnect-OER` runs, a command without `-TenantId` is refused with
  `SignInRefused` before it requests a token or sends anything. `Connect-OER` marks the session
  uncertain first thing, so its own refusals before a sign-in (an unknown tenant alias) count too.
- **F.** Texts: README, the about topic, `CLAUDE.md`, `docs/development/rationale.md` and the release
  note ("describe the tenant lookup and the uncertain session in the texts", "correct the texts on
  consumers, the session left by a refusal and the check limits").
- **G.** From the branch's final review ("refuse a blank tenant alias, gate the session reclaim and
  compare the ARM token with the Graph token"): `Connect-OER` refuses a blank `-TenantAlias` with the
  existing `InvalidTenantAlias`, so a blank row in a loop leaves the session uncertain instead of
  continuing in the previous tenant; a source gate holds `-ReclaimGraphSession` to `Connect-OER`; and
  a sign-in that names no tenant refuses an Azure Resource Manager token issued for another tenant than
  its Microsoft Graph token (`TenantMismatch`). An explicitly empty `-TenantId` still names no tenant
  and continues in the current session's tenant (a stated limit).

A live tenant is needed for what the unit tests stub: the authority's real answer for a real domain,
its GUID and a made-up domain; a real certificate token issued for the tenant a domain resolves to;
and the module's real requests -- token calls, lookups, Graph and ARM -- counted by fences, around a
real refused `Connect-OER` and the commands after it.

## What this file does not check, and why

- **`TenantMismatch` for a domain (class B, G9).** The certificate's tokens always come from the test
  tenant, the only tenant reachable, so a domain that resolves to one tenant and a token from another
  cannot be produced live. Proved offline: `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe
  `Initialize-OERAuth granted-tenant guard` (the domain Its for Graph and ARM), and in a runspace with
  no `try`, `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` H7.
- **A sovereign cloud's authority.** No sovereign tenant is reachable. Class B: the lookup's own tests
  (`tests/Unit/Private/Resolve-OERTenantDomain.Tests.ps1`), which read the host from the cloud table.
- **A transport refresh while the session is uncertain** (it does not clear the marker),
  **`ArmTokenAcquisitionFailed` marks too**, and **A19's same-frame retry under `-TenantId`**. Class B:
  `Initialize-OERAuth.Tests.ps1`, Describe `Initialize-OERAuth session uncertain after a refused
  sign-in (A10)`, and H4 in `Invoke-OERGraphRequest.Tests.ps1` (two documents piped to
  `Invoke-OERStructure -TenantId`, the first sign-in failing: the second is applied, and a command after
  it that names no tenant sends).
- **After `Disconnect-OER`, a command without `-TenantId` signs in interactively**, which no check may
  do (G9). 4.3 fences the token request instead: the command reaching its token request at all is the
  proof that the marker was cleared.

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
  the main clone is never checked out on another commit or branch (S.1 and T.1 read that it was not).

**Run every numbered block in its OWN PowerShell process**, except where a section says that its
checks share one.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s93-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s93'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Resolve-OERTenantDomain' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "-ErrorId 'TenantResolutionFailed'" -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$ExpectedTenantId -and (Test-OERGuid -Value $GrantedTenant)' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '[string]$Tenant = if (Test-OERGuid -Value ([string]$State.TokenTenantId))' -Quiet)
$E = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'function Set-OERSessionUncertain' -Quiet) -and
    [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'if ($SessionWasUncertain -and -not $TenantNamed -and -not $ReclaimGraphSession)' -Quiet)
$W = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '_OERLastIssuedSession' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C; D: $D; E: $E; the retired post-call warning's tracker: $W"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `A: True; B: True; C: True; D: True; E: True; the retired post-call warning's tracker: False`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any other `False`, or the tracker `True` -- build the worktree first
(`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s93-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s93'
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

## 1. The measurement: the authority tells a real domain from a made-up one

### 1.1. OpenID discovery, unauthenticated, for the domain, the GUID, the made-up domain and organizations

- [ ] **1.1** One GET without an `Authorization` header to `{AuthorityHost}{id}/v2.0/.well-known/openid-configuration` for each identifier, the host read from `Get-OERCloudEndpoint`: the test tenant's primary domain and its GUID answer 200 with the test tenant's GUID in `issuer`; the made-up domain answers an error; `organizations` answers the template issuer, which names no tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s93-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s93'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
# No sign-in. The cloud table is read from the branch's own source, not copied here.
. (Join-Path $Cfg.Repo 'source\Private\Get-OERCloudEndpoint.ps1')
$Authority = (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
$FakeDomain = 'oer-s93-doesnotexist' + '.onmicrosoft.com'
$Cases = @(
    , @('the test tenant primary domain', $Cfg.UserDomain)
    , @('the same domain in upper case', $Cfg.UserDomain.ToUpperInvariant())
    , @('the test tenant GUID', $Cfg.TenantId)
    , @('the made-up domain', $FakeDomain)
    , @('organizations', 'organizations')
)
foreach ($Case in $Cases) {
    $Uri = '{0}{1}/v2.0/.well-known/openid-configuration' -f $Authority, [uri]::EscapeDataString($Case[1])
    $Resp = Invoke-WebRequest -Uri $Uri -Method Get -SkipHttpErrorCheck -TimeoutSec 30 -UseBasicParsing
    $Body = $null
    try { $Body = $Resp.Content | ConvertFrom-Json } catch { $Body = $null }
    $Issuer = if ($Body) { [string]$Body.issuer } else { '' }
    $Shape = if (-not $Issuer) { 'none' } elseif ($Issuer -match '\{tenantid\}') { 'template' } elseif ($Issuer -match '/[0-9a-fA-F-]{36}/v2\.0$') { 'tenant ID' } else { 'other' }
    $HasGuid = [bool]($Issuer -and $Issuer.IndexOf($Cfg.TenantId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    $Err = if ($Body -and $Body.error) { "$($Body.error), AADSTS$(@($Body.error_codes)[0])" } else { 'none' }
    $Auth = [bool]$Resp.BaseResponse.RequestMessage.Headers.Authorization
    Write-OerLiveStep "1.1 $($Case[0]): status $([int]$Resp.StatusCode); issuer: $Shape; issuer holds the test tenant's GUID: $HasGuid; error: $Err; Authorization header sent: $Auth"
}
```

**Expect:** the domain, the domain in upper case and the GUID: `status 200; issuer: tenant ID; issuer
holds the test tenant's GUID: True`; the made-up domain: `status 400; issuer: none; ... False; error:
invalid_tenant, AADSTS90002`; `organizations`: `status 200; issuer: template; ... False`;
`Authorization header sent: False` on every line.
**Failure looks like:** the made-up domain answering 200 -- STOP (decision A3): the lookup cannot tell a
real domain from a made-up one, and the step goes back to the architect.

Result:

## 2. A tenant named by domain is resolved and checked; a GUID is unchanged

**2.1 to 2.3 run in ONE process**, in order. After the identity check, the block disconnects and
signs in with `Connect-OER` itself. Four fences count the module's requests: the token requests
(`Get-AzToken`), the tenant lookups (`Invoke-RestMethod`), the Graph requests
(`Invoke-MgGraphRequest`) and the ARM requests (`Invoke-WebRequest`). Each is a global function that
the module's unqualified call resolves to (a function outranks a cmdlet), and each forwards to the
real command, module-qualified -- except that the token fence REFUSES any token request that does not
carry the certificate, so no check can open a browser or a device code prompt.

### 2.1. Connect-OER with the test tenant's domain: signed in, and the session records the test tenant's GUID

- [ ] **2.1** `Connect-OER -TenantId` (the test tenant's primary domain) `-ClientId -Certificate -IncludeARM`, after `Disconnect-OerLive`: no error, one lookup, two token requests (Graph and ARM), the state names the domain and both tokens were issued for the test tenant's GUID, and the sign-in identity's tenant is that GUID (BL-77); a read afterwards goes out.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s93-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s93'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$FakeDomain = 'oer-s93-doesnotexist' + '.onmicrosoft.com'
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
function New-S93Fence {
    param([string]$Name, [string]$Body)
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $Name -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { $Body }"
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Text))
}
New-S93Fence -Name 'Invoke-MgGraphRequest' -Body '$global:S93Graph++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters'
New-S93Fence -Name 'Invoke-WebRequest' -Body '$global:S93Arm++; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters'
New-S93Fence -Name 'Invoke-RestMethod' -Body '$global:S93Lookup++; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters'
New-S93Fence -Name 'Get-AzToken' -Body ('$global:S93Token++; if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { $global:S93TokenRefused++; ' +
    'throw [System.InvalidOperationException]::new(''S93 fence: a token request without the certificate was refused before it was sent.'') }; AzAuth\Get-AzToken @PSBoundParameters')
$Fenced = @('Invoke-MgGraphRequest', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-AzToken' | ForEach-Object {
        (& $Module { param($N) Get-Command -Name $N } $_).CommandType -eq 'Function' })
Write-OerLiveStep "The module resolves the four fenced commands to the fences: $(@($Fenced) -notcontains $false)"
if (@($Fenced) -contains $false) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
function Get-S93State {
    # Who the module is, as True/False only.
    $S = & $Module { $script:_OERAuthState }
    $Uncertain = & $Module { [bool]$script:_OERSessionUncertain }
    if (-not $S) { return "the module holds a session: False; the session is uncertain: $Uncertain" }
    $Term = ([string](& $Module { Get-OERSignInIdentity }) -split "`n")[0]
    "the state names the test tenant by GUID: $(([string]$S.TenantId) -eq $Cfg.TenantId); by its primary domain: $(([string]$S.TenantId) -eq $Cfg.UserDomain); " +
    "the Graph token was issued for the test tenant: $(([string]$S.TokenTenantId) -eq $Cfg.TenantId); the ARM token: $(([string]$S.ArmTokenTenantId) -eq $Cfg.TenantId); " +
    "the client is oer-live-cc: $(([string]$S.ClientId) -eq $Cfg.AppId); the identity's tenant term is the test tenant's GUID: $($Term -eq $Cfg.TenantId); the session is uncertain: $Uncertain"
}
function Invoke-S93 {
    # A plain call, outside any try, as at a prompt. Prints the counts, the error ids (with the target
    # of a SignInRefused, a command name) and the messages, the made-up domain shown as MADE-UP-DOMAIN;
    # never a token, never an error record.
    param([string]$Label, [scriptblock]$Call)
    $global:S93Graph = 0; $global:S93Arm = 0; $global:S93Lookup = 0; $global:S93Token = 0; $global:S93TokenRefused = 0
    $All = @(& $Call 2>&1)
    $Out = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $Errs = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $Ids = @($Errs | ForEach-Object {
            $Id = ([string]$_.FullyQualifiedErrorId -split ',')[0]
            if ($Id -eq 'SignInRefused') { "$Id ($($_.TargetObject))" } else { $Id }
        })
    Write-OerLiveStep "$($Label): output objects $($Out.Count); errors: $(if ($Ids) { ($Ids | Group-Object | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }) -join ', ' } else { 'none' }); lookups: $global:S93Lookup; token requests: $global:S93Token (refused by the fence: $global:S93TokenRefused); Graph requests: $global:S93Graph; ARM requests: $global:S93Arm; Graph SDK session: $([bool](Get-MgContext)); $(Get-S93State)"
    foreach ($O in @($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.StructureResult' })) {
        Write-OerLiveStep "$($Label): row $($O.Section) | $($O.Item) | $($O.Action) | $((ConvertTo-OerLiveRedacted -Text ([string]$O.Detail)).Replace($FakeDomain, 'MADE-UP-DOMAIN'))"
    }
    foreach ($E in @($Errs | Group-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { $_.Group[0] })) {
        $Text = (ConvertTo-OerLiveRedacted -Text $E.Exception.Message).Replace($FakeDomain, 'MADE-UP-DOMAIN')
        if ($Text.Length -gt 400) { $Text = $Text.Substring(0, 400) + ' ...' }
        Write-OerLiveStep "$($Label): $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category) -- $Text"
    }
}
$Filter = "startswith(displayName,'oer-s93-')"
Disconnect-OerLive
Invoke-S93 -Label '2.1 Connect-OER by domain' -Call { Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
Invoke-S93 -Label '2.1 then a read without -TenantId' -Call { Get-OERGroup -Filter $Filter }
```

**Expect:** the identity lines and the fences `True`; `2.1 Connect-OER by domain: output objects 0;
errors: none; lookups: 1; token requests: 2 (refused by the fence: 0)`; Graph and ARM requests 0;
`Graph SDK session: True`; `the state names the test tenant by GUID: False; by its primary domain:
True; the Graph token was issued for the test tenant: True; the ARM token: True; the client is
oer-live-cc: True; the identity's tenant term is the test tenant's GUID: True; the session is
uncertain: False`. The read: `errors: none`, `lookups: 0`, `token requests: 0`, `Graph requests: 1`.
**Failure looks like:** `TenantResolutionFailed` -- the lookup refused a real domain (read the
message); `TenantMismatch` -- the token's tenant differs from the domain's (impossible with this
certificate; STOP); `lookups: 0` -- the domain was not looked up; the identity term `False` -- BL-77 is
not in the build.

Result:

### 2.2. The same with the test tenant's GUID: unchanged, no lookup

- [ ] **2.2** In the same process, `Disconnect-OerLive`, then `Connect-OER -TenantId` (the GUID) `-ClientId -Certificate -IncludeARM`: no error, no lookup, two token requests, the state names the GUID; a read afterwards goes out.

```powershell
Disconnect-OerLive
Invoke-S93 -Label '2.2 Connect-OER by GUID' -Call { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
Invoke-S93 -Label '2.2 then a read without -TenantId' -Call { Get-OERGroup -Filter $Filter }
```

**Expect:** `errors: none; lookups: 0; token requests: 2 (refused by the fence: 0)`; `the state names
the test tenant by GUID: True; by its primary domain: False; the Graph token was issued for the test
tenant: True; the ARM token: True; ... the identity's tenant term is the test tenant's GUID: True; the
session is uncertain: False`. The read: `errors: none`, `token requests: 0`, `Graph requests: 1`.
**Failure looks like:** `lookups: 1` -- a GUID was looked up; any error.

Result:

### 2.3. The domain again in the same process: the tenant ID comes from the cache

- [ ] **2.3** In the same process, `Disconnect-OerLive`, then the domain sign-in of 2.1 again: no error, no lookup (the tenant ID found in 2.1 is cached for the process; `Disconnect-OER` does not clear it), two token requests.

```powershell
Disconnect-OerLive
Invoke-S93 -Label '2.3 Connect-OER by domain again' -Call { Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Write-OerLiveStep "Fences removed: $(-not (Test-Path function:Invoke-MgGraphRequest) -and -not (Test-Path function:Invoke-WebRequest) -and -not (Test-Path function:Invoke-RestMethod) -and -not (Test-Path function:Get-AzToken))"
Disconnect-OerLive
```

**Expect:** `errors: none; lookups: 0; token requests: 2`; the state names the domain, both tokens
the test tenant, the identity term the GUID; `Fences removed: True`.
**Failure looks like:** `lookups: 1` -- the cache did not hold (one request per sign-in instead of per
process).

Result:

## 3. A made-up domain is refused before any token is requested

### 3.1. Connect-OER with the made-up domain: TenantResolutionFailed, no token request, no session

- [ ] **3.1** From no session (`Disconnect-OerLive` after the identity check), `Connect-OER -TenantId` (the made-up domain) `-ClientId -Certificate -IncludeARM`: `TenantResolutionFailed` naming the domain; one lookup; no token request; no Graph SDK session and no module session; the session is uncertain.

```powershell
# The first lines are 2.1's block up to and including Invoke-S93's definition and $Filter (run them
# first, unchanged); this check starts here.
Disconnect-OerLive
Invoke-S93 -Label '3.1 Connect-OER with the made-up domain' -Call { Connect-OER -TenantId $FakeDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM }
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Disconnect-OerLive
```

**Expect:** `errors: TenantResolutionFailed; lookups: 1; token requests: 0 (refused by the fence: 0);
Graph requests: 0; ARM requests: 0; Graph SDK session: False; the module holds a session: False; the
session is uncertain: True`; the message names `MADE-UP-DOMAIN`, the authority's `invalid_tenant`
(AADSTS90002) and says no token was requested.
**Failure looks like:** `token requests: 1` or more -- a token was requested for a tenant that was never
resolved; `GraphTokenAcquisitionFailed` instead of `TenantResolutionFailed` -- the lookup did not run
first.

Result:

## 4. A10: after a refused sign-in, a command that names no tenant sends nothing

Each of 4.1 to 4.4 is its OWN process. Each starts with the first lines of 2.1's block up to and
including `$Filter` (the identity check as `oer-live-cc` by GUID, the fences, the helpers), unchanged;
the check starts after them.

### 4.1. A refused Connect-OER, then a command without -TenantId; a command naming the tenant clears it

- [ ] **4.1** Under the GUID session, a refused `Connect-OER` (made-up domain), then `Get-OERGroup` without `-TenantId`: `SignInRefused` naming `Get-OERGroup`, no token request and no Graph request. Then `Get-OERGroup -TenantId` (the GUID) goes out, and after it `Get-OERGroup` without `-TenantId` goes out again.

```powershell
Invoke-S93 -Label '4.1 a: Connect-OER with the made-up domain' -Call { Connect-OER -TenantId $FakeDomain -ClientId $Cfg.AppId -Certificate $Cert }
Invoke-S93 -Label '4.1 b: Get-OERGroup without -TenantId' -Call { Get-OERGroup -Filter $Filter }
Invoke-S93 -Label '4.1 c: Get-OERGroup -TenantId with the GUID' -Call { Get-OERGroup -TenantId $Cfg.TenantId -Filter $Filter }
Invoke-S93 -Label '4.1 d: Get-OERGroup without -TenantId again' -Call { Get-OERGroup -Filter $Filter }
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Disconnect-OerLive
```

**Expect:** a: `errors: TenantResolutionFailed; token requests: 0`; the state still names the test
tenant by GUID, `the session is uncertain: True`. b: `errors: SignInRefused (Get-OERGroup); lookups: 0;
token requests: 0; Graph requests: 0`; the message begins `An earlier sign-in in this PowerShell session
failed or was refused`. c: `errors: none; token requests: 0; Graph requests: 1`; `the session is
uncertain: False`. d: `errors: none; Graph requests: 1`.
**Failure looks like:** b with `Graph requests: 1` and no error -- the command acted on the session the
refused sign-in left (BL-89 open); c refused -- a command that names its tenant does not clear the
marker.

Result:

### 4.2. The same, cleared by Connect-OER

- [ ] **4.2** A refused `Connect-OER`, `Get-OERGroup` without `-TenantId` refused, then `Connect-OER -TenantId` (the GUID) `-ClientId -Certificate`: signed in; `Get-OERGroup` without `-TenantId` goes out.

```powershell
Invoke-S93 -Label '4.2 a: Connect-OER with the made-up domain' -Call { Connect-OER -TenantId $FakeDomain -ClientId $Cfg.AppId -Certificate $Cert }
Invoke-S93 -Label '4.2 b: Get-OERGroup without -TenantId' -Call { Get-OERGroup -Filter $Filter }
Invoke-S93 -Label '4.2 c: Connect-OER with the GUID' -Call { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert }
Invoke-S93 -Label '4.2 d: Get-OERGroup without -TenantId' -Call { Get-OERGroup -Filter $Filter }
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Disconnect-OerLive
```

**Expect:** a `TenantResolutionFailed`; b `SignInRefused (Get-OERGroup)`, `Graph requests: 0`, `token
requests: 0`; c `errors: none`, `the session is uncertain: False` (a cached return: `token requests:
0`); d `errors: none; Graph requests: 1`.
**Failure looks like:** d refused -- `Connect-OER` does not clear the marker.

Result:

### 4.3. The same, cleared by Disconnect-OER

- [ ] **4.3** A refused `Connect-OER`, `Get-OERGroup` without `-TenantId` refused, then `Disconnect-OER`; `Get-OERGroup` without `-TenantId` now gets past the refusal to its own sign-in, which -- with no session -- is interactive and stops at the token fence: `GraphTokenAcquisitionFailed`, one token request refused by the fence, no Graph request.

```powershell
Invoke-S93 -Label '4.3 a: Connect-OER with the made-up domain' -Call { Connect-OER -TenantId $FakeDomain -ClientId $Cfg.AppId -Certificate $Cert }
Invoke-S93 -Label '4.3 b: Get-OERGroup without -TenantId' -Call { Get-OERGroup -Filter $Filter }
Invoke-S93 -Label '4.3 c: Disconnect-OER' -Call { Disconnect-OER -Confirm:$false }
Invoke-S93 -Label '4.3 d: Get-OERGroup without -TenantId' -Call { Get-OERGroup -Filter $Filter }
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Disconnect-OerLive
```

**Expect:** a `TenantResolutionFailed`; b `SignInRefused (Get-OERGroup)`, `token requests: 0`; c
`errors: none; the module holds a session: False; the session is uncertain: False`; d `errors:
GraphTokenAcquisitionFailed` (and the `SignInRefused` its own refused sign-in then gives its request,
if any); `token requests: 1 (refused by the fence: 1)`; `Graph requests: 0`; the message carries the
fence's text.
**Failure looks like:** d `SignInRefused` with `token requests: 0` and the message `An earlier sign-in`
-- `Disconnect-OER` does not clear the marker; d with `refused by the fence: 0` -- STOP: a token request
without the certificate went out.

Result:

### 4.4. The loop over Tenant Profiles: a refused Connect-OER -TenantAlias, then Invoke-OERStructure without -TenantId

- [ ] **4.4** Two Tenant Profiles in the step's raw folder -- `oer-s93-test` (the test tenant's GUID) and `oer-s93-made-up` (the made-up domain) -- and the loop `Connect-OER -TenantAlias $Alias ...; Invoke-OERStructure -Path <doc> -WhatIf` over `oer-s93-test`, `oer-s93-missing` (no profile), `oer-s93-test`, a blank alias, `oer-s93-test`, `oer-s93-made-up`: the three `oer-s93-test` rounds plan the document; after `oer-s93-missing` (`TenantAliasNotFound`), the blank alias (`InvalidTenantAlias`) and `oer-s93-made-up` (`TenantResolutionFailed`) `Invoke-OERStructure` is refused with `SignInRefused`, sending nothing.

```powershell
$ProfileDir = Join-Path $Raw 'profiles'
$null = [System.IO.Directory]::CreateDirectory($ProfileDir)
New-OERConfiguration -TenantAlias 'oer-s93-test' -TenantId $Cfg.TenantId -BasePath $ProfileDir -Confirm:$false
New-OERConfiguration -TenantAlias 'oer-s93-made-up' -TenantId $FakeDomain -BasePath $ProfileDir -Confirm:$false
$Doc = Join-Path $Raw 'apply-s93.json'
[System.IO.File]::WriteAllText($Doc, (@{
            version = '1.0'
            groups  = @(@{ displayName = 'oer-s93-grp'; description = 'Omnicit.EntraRBAC live verification (oer-s93-): never created' })
        } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
foreach ($Alias in 'oer-s93-test', 'oer-s93-missing', 'oer-s93-test', '', 'oer-s93-test', 'oer-s93-made-up') {
    $Shown = if ($Alias) { $Alias } else { '(blank)' }
    Invoke-S93 -Label "4.4 Connect-OER -TenantAlias $Shown" -Call { Connect-OER -TenantAlias $Alias -BasePath $ProfileDir -ClientId $Cfg.AppId -Certificate $Cert }
    Invoke-S93 -Label "4.4 Invoke-OERStructure -WhatIf after $Shown" -Call { Invoke-OERStructure -Path $Doc -WhatIf }
}
Remove-Item -Path function:Invoke-MgGraphRequest, function:Invoke-WebRequest, function:Invoke-RestMethod, function:Get-AzToken
Disconnect-OerLive
```

**Expect:** after each `oer-s93-test`: `errors: none` for `Connect-OER` (a cached return, `token
requests: 0`), and `Invoke-OERStructure`: a row `groups | oer-s93-grp` that plans the group, `errors:
none`, `Graph requests` 1 or more, `ARM requests: 0`. After `oer-s93-missing`: `Connect-OER` `errors:
TenantAliasNotFound; lookups: 0; token requests: 0`; `Invoke-OERStructure`: errors `SignInRefused
(Invoke-OERStructure)` only (once for its own sign-in, and again for each sign-in or request the
handler then attempts), every row it writes `Failed`, none planned, `token requests: 0; Graph requests:
0; ARM requests: 0`. After the blank alias: `Connect-OER` `errors: InvalidTenantAlias; lookups: 0;
token requests: 0`; `Invoke-OERStructure` refused the same way. After `oer-s93-made-up`: `Connect-OER`
`errors: TenantResolutionFailed; token requests: 0`; `Invoke-OERStructure` refused the same way.
**Failure looks like:** a planning row after `oer-s93-missing` or `oer-s93-made-up` -- the document was
planned in the session the refused sign-in left (the BL-89 shape; with `-Prune` and without `-WhatIf`,
an apply in the previous tenant).

Result:

## 5. TenantMismatch with a domain: class B

- [ ] **5** Not runnable live (see "What this file does not check"). The offline proof instead, with its result in the step's gate run on the branch head: in `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe `Initialize-OERAuth granted-tenant guard`, `refuses a Graph token issued for another tenant than the one a domain resolves to` and `refuses an ARM token issued for another tenant than the one a domain resolves to, caching nothing`; and in a runspace with no `try`, `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` `H7: Invoke-OERStructure with a tenant named by domain whose token comes back from another tenant, outside any try, connects nothing and sends no Graph or ARM request (BL-12)`.

Result:

## Teardown

### T.1. Nothing carries the prefix, no session is left, the profiles are gone, and the main clone is untouched

- [ ] **T.1** The sweep finds nothing with the prefix `oer-s93-`; the two profile files and the document are deleted; no session is left; the main clone is still on `main` at the HEAD S.1 recorded; the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s93-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s93'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Left = @(Find-OerLivePrefixed -ThrowOnUnread)
Disconnect-OerLive
$Module = Get-Module -Name Omnicit.EntraRBAC
$ProfileDir = Join-Path $Raw 'profiles'
foreach ($F in @(Get-ChildItem -LiteralPath $ProfileDir -File -ErrorAction SilentlyContinue) + @(Get-Item -LiteralPath (Join-Path $Raw 'apply-s93.json') -ErrorAction SilentlyContinue)) {
    [System.IO.File]::Delete($F.FullName)
}
Write-OerLiveStep "Prefixed objects: $($Left.Count); a Graph SDK session is left: $([bool](Get-MgContext)); the module holds a session: $([bool](& $Module { $script:_OERAuthState })); profile files left: $(@(Get-ChildItem -LiteralPath $ProfileDir -File -ErrorAction SilentlyContinue).Count)"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the identity lines `True`; the sweep's "no ... starting with 'oer-s93-' is left";
`Prefixed objects: 0; a Graph SDK session is left: False; the module holds a session: False; profile
files left: 0`; the main clone on `main` at the HEAD S.1 recorded. After the results are copied into
this file: `Clear-OerLiveRedactionMap`, and `raw\s93\` deleted.
**Failure looks like:** a prefixed object -- STOP: this file creates none, so it is not this run's
(G11 stop condition: an object the prerequisite script did not create).

Result:
