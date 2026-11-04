# Live verification checklist -- the PowerShell floor is 7.6 and the tenant lookup is bounded (chore/powershell-7-6-floor)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. Every check either sends the unauthenticated tenant
lookup, signs in, or reads groups (a count only). There is no prerequisite script and no test object;
the teardown only proves that nothing carries the prefix `oer-s122-` and that no session is left.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person, and no check needs
`oer-live-cc-noperm`. A 401 or 403 as `oer-live-cc` is a stop.

**The made-up domain.** The label `oer-s122-doesnotexist` under `onmicrosoft.com`, which names no
tenant (measured 2026-10-06: the authority answers 400, AADSTS90002). The blocks join the two at run
time, and every line they print shows it as `MADE-UP-DOMAIN`.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s122/`, which
is git-ignored. Every block prints through the library's redactor. **No credential, token,
application id, tenant id, domain, account or certificate thumbprint is ever printed** -- every
comparison is printed as True or False -- and **no error record is ever rendered**: a block prints
the error id and the message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The floor** ("state PowerShell 7.6 as the floor"). The manifest's `PowerShellVersion` is
  `7.6`; PowerShell 7.4 and 7.5 reach end of support on 10-Nov-2026.
- **B. The tenant lookup** ("bound the tenant lookup body with -OperationTimeoutSeconds").
  `Resolve-OERTenantDomain` sends its one unauthenticated GET with `-OperationTimeoutSeconds 30`
  beside `-TimeoutSec 30`, so a body that stalls after the headers ends the lookup with
  `TenantResolutionFailed` instead of hanging. A body that trickles in slowly is still not bounded.
- **C. The 7.2-7.4 branch** ("remove the 7.2 to 7.4 date branch"). The structure document reader
  always parses with `-DateKind String`; `Test-OERJsonDateKindSupport` and the validator's date rule
  are gone.
- **D.** The other 7.2 texts and the generic-argument guard, and the release note.

A live tenant is needed for what the unit tests stub: the authority's real answer to the lookup with
the new parameter, a real certificate sign-in that names the tenant by domain, and a real Graph read
after it. The stalled-body case itself was measured offline against a local listener in Sprint 11
(issue #66) and is not repeated here: no tenant can be made to stall.

## What this file does not check, and why

- **A host on PowerShell 7.4 or 7.5 refuses the module** (class C, optional, Philip's after the
  merge): this machine runs one PowerShell, 7.6.
- **The stalled and trickling body**: the authority answers in well under a second; the measurement
  stands in issue #66 and `docs/development/rationale.md`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.

**Run every numbered block in its OWN PowerShell process.**

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s122-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s122'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
$A = ([string](Import-PowerShellDataFile -LiteralPath $Psd1.FullName).PowerShellVersion) -eq '7.6'
$B = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch '-TimeoutSec 30 -OperationTimeoutSeconds 30 -ErrorAction Stop' -Quiet)
$C = -not [bool](Select-String -LiteralPath $Psm1 -SimpleMatch 'function Test-OERJsonDateKindSupport' -Quiet)
Write-OerLiveStep "The worktree's build carries A (floor 7.6): $A; B (the bounded lookup): $B; C (no DateKind support question): $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `A (floor 7.6): True; B (the
bounded lookup): True; C (no DateKind support question): True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any other `False` -- build the worktree first (`./build.ps1 -Tasks build`), never while the
gate runs.

Result:

## 1. The module imports on PowerShell 7.6

### 1.1. Import-Module of the build in a fresh pwsh -NoProfile

- [ ] **1.1** In a fresh `pwsh -NoProfile` on 7.6, `Import-Module` of the build's manifest succeeds, and the loaded module declares `PowerShellVersion` 7.6.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s122-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s122'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Child = Join-Path ([System.IO.Path]::GetTempPath()) ('oer-s122-import-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
Set-Content -LiteralPath $Child -Encoding utf8NoBOM -Value @'
param([string]$Psd1)
$Env:PSModulePath = (@((Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $Psd1)))) 'RequiredModules')) + ($Env:PSModulePath -split [IO.Path]::PathSeparator)) -join [IO.Path]::PathSeparator
$Ok = $true
try { $M = Import-Module -Name $Psd1 -Force -PassThru -ErrorAction Stop } catch { $Ok = $false; "import error: $($_.FullyQualifiedErrorId)" }
"PowerShell $($PSVersionTable.PSVersion); at least 7.6.0: $($PSVersionTable.PSVersion -ge [version]'7.6.0')"
"Import-Module succeeded: $Ok"
if ($Ok) { "module $($M.Version); declares PowerShellVersion 7.6: $([string]$M.PowerShellVersion -eq '7.6'); exported commands: $($M.ExportedFunctions.Count)" }
'@
$Lines = @(pwsh -NoProfile -NonInteractive -File $Child -Psd1 $Psd1.FullName 2>&1)
Remove-Item -LiteralPath $Child
foreach ($L in $Lines) { Write-OerLiveStep "1.1 $L" }
```

**Expect:** `at least 7.6.0: True`; `Import-Module succeeded: True`; `declares PowerShellVersion 7.6:
True`; the exported command count the README states.
**Failure looks like:** an import error -- read the id; `False` on the version line -- the machine
does not run 7.6, and the check cannot be run here.

Result:

## 2. The tenant lookup, in the module's scope, with the bound timeout

**2.1 and 2.2 run in ONE process.** No sign-in: the lookup is unauthenticated. A fence on
`Invoke-RestMethod` (a global function the module's unqualified call resolves to, forwarding to the
real cmdlet, module-qualified) counts the requests and records the NAMES of the parameters bound, never
their values.

### 2.1. The test tenant's domain resolves to its tenant ID

- [ ] **2.1** `Resolve-OERTenantDomain -Domain` (the test tenant's primary domain) `-Environment Global` in the module's scope returns a GUID that is the test tenant's, in one request carrying exactly `Uri, Method, TimeoutSec, OperationTimeoutSeconds, ErrorAction`; the time is printed.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s122-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s122'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Env:PSModulePath = (@((Join-Path $Cfg.Repo 'output\RequiredModules')) + ($Env:PSModulePath -split [IO.Path]::PathSeparator)) -join [IO.Path]::PathSeparator
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Module = Import-Module -Name $Psd1.FullName -Force -PassThru
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
$FakeDomain = 'oer-s122-doesnotexist' + '.onmicrosoft.com'
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name 'Invoke-RestMethod' -CommandType Cmdlet))
$Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S122Lookup++; `$global:S122Params = @(`$PSBoundParameters.Keys | Sort-Object) -join ', '; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters }"
Set-Item -Path 'function:global:Invoke-RestMethod' -Value ([scriptblock]::Create($Text))
Write-OerLiveStep "The module resolves Invoke-RestMethod to the fence: $((& $Module { Get-Command -Name 'Invoke-RestMethod' }).CommandType -eq 'Function')"
$global:S122Lookup = 0; $global:S122Params = ''
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$Answer = $null; $Err = $null
try { $Answer = & $Module { param($D) Resolve-OERTenantDomain -Domain $D -Environment 'Global' } $Cfg.UserDomain } catch { $Err = $_ }
$Watch.Stop()
Write-OerLiveStep ("2.1 the test tenant's domain: error: {0}; the answer is a GUID: {1}; the answer is the test tenant's ID: {2}; requests: {3}; parameters bound: {4}; seconds: {5}" -f
    $(if ($Err) { $Err.Exception.GetType().Name } else { 'none' }), [bool]($Answer -and (& $Module { param($V) Test-OERGuid -Value $V } $Answer)),
    ([string]$Answer -eq $Cfg.TenantId), $global:S122Lookup, $global:S122Params, $Watch.Elapsed.TotalSeconds.ToString('0.00', [cultureinfo]::InvariantCulture))
```

**Expect:** the build `True`, the fence `True`; `error: none; the answer is a GUID: True; the answer
is the test tenant's ID: True; requests: 1; parameters bound: ErrorAction, Method,
OperationTimeoutSeconds, TimeoutSec, Uri`; a time well under 30 seconds.
**Failure looks like:** an error -- the authority refused a real domain (read 2.2's message format);
a parameter list without `OperationTimeoutSeconds` -- the build is not this branch's.

Result:

### 2.2. A made-up domain is refused, in the lookup and in the sign-in, before any token request

- [ ] **2.2** In the same process: `Resolve-OERTenantDomain` with the made-up domain throws (one request, the same five parameters); `Connect-OER -TenantId` (the made-up domain) `-ClientId -Certificate` is refused with `TenantResolutionFailed` and requests no token; the times are printed.

```powershell
# Run in 2.1's process, after 2.1.
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name 'Get-AzToken' -CommandType Cmdlet))
$Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S122Token++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw [System.InvalidOperationException]::new('S122 fence: a token request without the certificate was refused before it was sent.') }; AzAuth\Get-AzToken @PSBoundParameters }"
Set-Item -Path 'function:global:Get-AzToken' -Value ([scriptblock]::Create($Text))
Write-OerLiveStep "The module resolves Get-AzToken to the fence: $((& $Module { Get-Command -Name 'Get-AzToken' }).CommandType -eq 'Function')"
$global:S122Lookup = 0; $global:S122Params = ''
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$Err = $null
try { $null = & $Module { param($D) Resolve-OERTenantDomain -Domain $D -Environment 'Global' } $FakeDomain } catch { $Err = $_ }
$Watch.Stop()
$Message = if ($Err) { (ConvertTo-OerLiveRedacted -Text $Err.Exception.Message).Replace($FakeDomain, 'MADE-UP-DOMAIN') } else { 'none' }
Write-OerLiveStep ("2.2 the lookup of the made-up domain: threw: {0} ({1}); requests: {2}; parameters bound: {3}; seconds: {4}; message: {5}" -f
    [bool]$Err, $(if ($Err) { $Err.Exception.GetType().Name } else { '-' }), $global:S122Lookup, $global:S122Params,
    $Watch.Elapsed.TotalSeconds.ToString('0.00', [cultureinfo]::InvariantCulture), $Message)
Disconnect-OER -Confirm:$false 3>$null
$global:S122Lookup = 0; $global:S122Token = 0
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$All = @(Connect-OER -TenantId $FakeDomain -ClientId $Cfg.AppId -Certificate $Cert 2>&1)
$Watch.Stop()
$Ids = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
Write-OerLiveStep ("2.2 Connect-OER with the made-up domain: errors: {0}; lookups: {1}; token requests: {2}; the module holds a session: {3}; seconds: {4}" -f
    $(if ($Ids) { $Ids -join ', ' } else { 'none' }), $global:S122Lookup, $global:S122Token, [bool](& $Module { $script:_OERAuthState }),
    $Watch.Elapsed.TotalSeconds.ToString('0.00', [cultureinfo]::InvariantCulture))
Remove-Item -Path 'function:global:Invoke-RestMethod', 'function:global:Get-AzToken'
```

**Expect:** the fence `True`; `threw: True (InvalidOperationException); requests: 1; parameters
bound: ErrorAction, Method, OperationTimeoutSeconds, TimeoutSec, Uri`; a message naming the authority,
`MADE-UP-DOMAIN` and `invalid_tenant, AADSTS90002`; then `errors: TenantResolutionFailed; lookups: 1;
token requests: 0; the module holds a session: False`; both times well under 30 seconds.
**Failure looks like:** `threw: False`, or a token request -- STOP: the lookup does not refuse a
made-up domain before a token is requested.

Result:

## 3. A sign-in that names the tenant by domain, and a Graph read

### 3.1. Connect-OER as oer-live-cc with -TenantId the domain, then Get-OERGroup -All

- [ ] **3.1** After the identity check and `Disconnect-OerLive`, `Connect-OER -TenantId` (the test tenant's primary domain) `-ClientId -Certificate` signs in with one lookup carrying the five parameters, and `Get-OERGroup -All` returns groups (a count only).

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s122-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s122'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
function New-S122Fence {
    param([string]$Name, [string]$Body)
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $Name -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { $Body }"
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Text))
}
New-S122Fence -Name 'Invoke-RestMethod' -Body '$global:S122Lookup++; $global:S122Params = @($PSBoundParameters.Keys | Sort-Object) -join '', ''; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters'
New-S122Fence -Name 'Invoke-MgGraphRequest' -Body '$global:S122Graph++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters'
New-S122Fence -Name 'Get-AzToken' -Body ('$global:S122Token++; if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { ' +
    'throw [System.InvalidOperationException]::new(''S122 fence: a token request without the certificate was refused before it was sent.'') }; AzAuth\Get-AzToken @PSBoundParameters')
$Fenced = @('Invoke-RestMethod', 'Invoke-MgGraphRequest', 'Get-AzToken' | ForEach-Object { (& $Module { param($N) Get-Command -Name $N } $_).CommandType -eq 'Function' })
Write-OerLiveStep "The module resolves the three fenced commands to the fences: $(@($Fenced) -notcontains $false)"
if (@($Fenced) -contains $false) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
Disconnect-OerLive
$global:S122Lookup = 0; $global:S122Token = 0; $global:S122Graph = 0; $global:S122Params = ''
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$All = @(Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert 2>&1)
$Watch.Stop()
$Ids = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
$S = & $Module { $script:_OERAuthState }
Write-OerLiveStep ("3.1 Connect-OER by domain: errors: {0}; lookups: {1}; parameters bound: {2}; token requests: {3}; the Graph token was issued for the test tenant: {4}; the client is oer-live-cc: {5}; the state carries a signed-in object id: {6}; seconds: {7}" -f
    $(if ($Ids) { $Ids -join ', ' } else { 'none' }), $global:S122Lookup, $global:S122Params, $global:S122Token,
    ([string]$S.TokenTenantId -eq $Cfg.TenantId), ([string]$S.ClientId -eq $Cfg.AppId), [bool]$S.SignedInObjectId,
    $Watch.Elapsed.TotalSeconds.ToString('0.00', [cultureinfo]::InvariantCulture))
$global:S122Graph = 0
$All = @(Get-OERGroup -All 2>&1)
$Groups = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
$Ids = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
Write-OerLiveStep ("3.1 Get-OERGroup -All: errors: {0}; groups returned: more than 0: {1}; tagged Omnicit.EntraRBAC.Group: {2}; Graph requests at least 1: {3}" -f
    $(if ($Ids) { $Ids -join ', ' } else { 'none' }), ($Groups.Count -gt 0), [bool]($Groups.Count -gt 0 -and $Groups[0].PSObject.TypeNames -contains 'Omnicit.EntraRBAC.Group'), ($global:S122Graph -ge 1))
Remove-Item -Path 'function:global:Invoke-RestMethod', 'function:global:Invoke-MgGraphRequest', 'function:global:Get-AzToken'
Disconnect-OerLive
```

**Expect:** every identity line `True`; the build and the fences `True`; `errors: none; lookups: 1;
parameters bound: ErrorAction, Method, OperationTimeoutSeconds, TimeoutSec, Uri; token requests: 1`;
the three state lines `True`; then `errors: none; groups returned: more than 0: True; tagged
Omnicit.EntraRBAC.Group: True; Graph requests at least 1: True`.
**Failure looks like:** `application is disabled` -- STOP: the identity is not enabled for this run;
a 401 or 403 -- STOP; `TenantResolutionFailed` -- the lookup refused the real domain.

Result:

## Teardown

### T.1. Nothing carries the prefix, no session is left, the main clone was never switched

- [ ] **T.1** No group carries `oer-s122-`, the module holds no session, and the raw folder for the step is deleted after the results are copied.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s122-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s122'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "T.1 objects carrying the prefix: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count); collections that could not be read: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "T.1 the module holds a session after Disconnect-OerLive: $([bool](& (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState }))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
Write-OerLiveStep "T.1 main clone: branch $(([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', '')"
```

**Expect:** `objects carrying the prefix: 0; collections that could not be read: 0`; `the module holds a session after Disconnect-OerLive:
False`; the main clone on `main`.
**Failure looks like:** a count above 0 -- this file creates nothing, so an object with the prefix is
not this run's: STOP.

Result:
