# Live verification checklist -- a long run renews an expiring token (fix/renew-the-token-silently)

**This branch does not merge until every box in sections S, 0, 1, 2 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out
to be impossible to run, write "cannot be verified, and therefore we do not know" on its result line
and say why; do not leave it blank and do not tick it. A check that could not run for a stated reason
is marked `[~]`, never `[x]`. **Section C is the operator's own check (class C, decision A11) and is
run by hand AFTER the merge, with the published preview**: its boxes stay open in this file until the
operator runs it, and the merge does not wait for them.

**What this file writes to the tenant: nothing.** No object is created, changed or removed, so there
is no prerequisite script and no baseline. Every request is a read.

**Who runs it.** Sections S, 0, 1, 2 and T: the dedicated certificate identity `oer-live-cc`, through
the OerLive library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in there is app-only; nothing there signs in as
a person. A 401 or 403 as `oer-live-cc` is a stop. Section C: the operator, signed in as themself --
never Claude, and never the certificate identity.

**Sign-ins.** In sections 0 to 2 every block's first sign-in goes through `Connect-OerLive -Arm` (the
module's own `Connect-OER` with the certificate and `-IncludeARM`), which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and checks the identity as True/False, and every block installs the
no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s104/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** Each block is run in its own process whose whole
output (standard output and standard error) is written to a file under `raw\s104\`, redacted with
OerLive's redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-105 (decision A11): the transports renew a token before it expires** ("fix: renew an
  expiring token before the request instead of after a 401"). Before every Microsoft Graph attempt
  and page, and before every Azure Resource Manager call, the module renews the session's token when
  its recorded expiry lies within the renewal window (five minutes, `Get-OERTokenRenewalThreshold`),
  for an interactive or managed identity session, through `Initialize-OERAuth -Renewal` without
  `-ForceRefresh`. A device code session is not renewed (ruling R12: AzAuth's device-code request
  without `-Force` never returns once it reuses its credential), and an app-only session (client
  secret, certificate) is not renewed within a command: the module keeps no key material.
- **B. BL-105: a 401 for an expired token is renewed without `-Force` first** ("fix: renew an expired token after a 401 instead of forcing the refresh", and "fix: keep forcing the refresh of a device code session"). A 401
  for a token that has expired, or expires within the window, is renewed the same way; a 401 for a
  token that is still valid beyond the window, or whose expiry the state does not record, or of a
  device code session, is forced, as before.

The renewal itself happens only for a delegated or managed identity session, which `oer-live-cc`
cannot be (G9: the delegated renewal is class C, section C). What a live tenant adds here is the
REGRESSION for the app-only identity in a real session: a token whose recorded expiry is moved into
the renewal window is not renewed, and the request goes out with the token the session holds -- for
Microsoft Graph (1.1), for Azure Resource Manager (1.2) and across the pages of a paged read (1.3) --
and an ordinary command and a paged command read as before (2.1, 2.2).

## What this file does not check, and why

- **The renewal of a delegated session (class C, section C).** `oer-live-cc` is app-only. The unit
  tests prove it with the real `Initialize-OERAuth` and stubbed transports in
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, Describe `A long run renews its token with
  the credential AzAuth holds (A11, BL-105)` (E1 to E12), and with mocks in the two transports' test
  files.
- **A 401 (class B).** Moving the recorded expiry does not make the service reject the token, and
  nothing else here can produce a rejected token on purpose. Proved offline: the Describes `...
  renews a rejected token that has expired without -ForceRefresh (A11, BL-105)` in both transports'
  test files, and E7 to E10 and E12 end to end.
- **A managed identity (class B).** No managed identity is available to this run. Proved offline
  (R2 and RA2 in the transports' test files).
- **Whether AzAuth answers a renewal without a prompt.** That is what section C measures; the
  offline evidence is DECOMPILED only (`docs/development/rationale.md`, the subsection on how a long
  run renews its token).
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

Run first in every process of sections S to 2 and T. It loads OerLive and the configuration, and
defines the fences and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s104-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s104'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null

function Start-S104NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt. Every request is counted, with whether it carried -Force. A
    # global proxy of Get-AzToken, which the module calls unqualified, forwards only a certificate request.
    $global:S104TokenCalls = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S104TokenCalls.Add('force=' + [bool]`$PSBoundParameters['Force']); if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S104 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S104Count {
    # Counts every request the module sends, through global proxies of the two commands its transports
    # call unqualified: Invoke-MgGraphRequest (Microsoft Graph) and Invoke-WebRequest (Azure Resource Manager).
    $global:S104Arm = [System.Collections.Generic.List[string]]::new()
    $global:S104Graph = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S104Arm.Add(([uri]`$Uri).Host); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S104Graph.Add('request'); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S104Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-WebRequest', 'Invoke-MgGraphRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S104Sent {
    # A block that never started a counter says so: @($null).Count is 1, not 0.
    $Tokens = if ($null -eq $global:S104TokenCalls) { 'not counted in this block' } else { "$($global:S104TokenCalls.Count)$(if ($global:S104TokenCalls.Count) { " ($($global:S104TokenCalls -join ', '))" })" }
    $Graph = if ($null -eq $global:S104Graph) { 'not counted in this block' } else { [string]$global:S104Graph.Count }
    $Arm = if ($null -eq $global:S104Arm) { 'not counted in this block' } else { [string]$global:S104Arm.Count }
    "token requests: $Tokens; Microsoft Graph requests: $Graph; Azure Resource Manager requests: $Arm"
}

function Set-S104Expiry {
    # Moves the RECORDED expiry of one of the module's tokens, in the module's scope. The token itself is
    # never read or changed, so the service still accepts it.
    param([Parameter(Mandatory)][ValidateSet('Graph', 'Arm')][string]$Token, [Parameter(Mandatory)][double]$Minutes)
    & (Get-Module -Name Omnicit.EntraRBAC) {
        param($T, $Mi)
        if ($T -eq 'Graph') { $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($Mi) }
        else { $script:_OERAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes($Mi) }
    } $Token $Minutes
}

function Get-S104Window {
    # The session's sign-in method, and whether each recorded expiry lies inside the renewal window now
    # (Get-OERTokenRenewalThreshold), with the whole minutes left -- never a token, never a tenant value.
    & (Get-Module -Name Omnicit.EntraRBAC) {
        $Edge = Get-OERTokenRenewalThreshold
        $S = $script:_OERAuthState
        $G = if ($S.GraphTokenExpiry) { "$($S.GraphTokenExpiry -le $Edge) ($([int][math]::Floor(($S.GraphTokenExpiry - [DateTime]::UtcNow).TotalMinutes)) min left)" } else { 'no expiry recorded' }
        $A = if ($S.ArmTokenExpiry) { "$($S.ArmTokenExpiry -le $Edge) ($([int][math]::Floor(($S.ArmTokenExpiry - [DateTime]::UtcNow).TotalMinutes)) min left)" } else { 'no expiry recorded' }
        "sign-in method: $($S.AuthMethod); Graph token due for renewal: $G; ARM token due for renewal: $A"
    }
}

function Invoke-S104Transport {
    # Runs a script block in the module's scope and keeps its verbose lines apart from its output, so a
    # renewal ('... expires within the renewal window. Renewing it before the request...') can be counted.
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)
    $global:S104Verbose = [System.Collections.Generic.List[string]]::new()
    & (Get-Module -Name Omnicit.EntraRBAC) $ScriptBlock 4>&1 | ForEach-Object {
        if ($PSItem -is [System.Management.Automation.VerboseRecord]) { $global:S104Verbose.Add([string]$PSItem.Message) } else { $PSItem }
    }
}

function Get-S104Renewals {
    "renewal lines in the verbose stream: $(@($global:S104Verbose | Where-Object { $_ -like '*expires within the renewal window*' }).Count); verbose lines: $(@($global:S104Verbose).Count)"
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

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
Write-OerLiveStep "The worktree's build carries the window's owner: $(& $Has 'function Get-OERTokenRenewalThreshold'); A: $(& $Has 'expires within the renewal window. Renewing it before the request'); B: $(& $Has 'and expired. Renewing it and retrying once'); device code forced: $(& $Has "AuthMethod -ne 'DeviceCode'")"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `The worktree's build carries the
window's owner: True; A: True; B: True; device code forced: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree on this branch at e54a6c0 with 0 tracked changes (the build is of 9dc7287's source; e54a6c0 adds only this checklist); the build carries the window's owner, A, B and the device-code force.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s104] The module loads from a worktree that is not the main clone: True
[oer-s104] Main clone: branch main; HEAD 6817b33
[oer-s104] Worktree: branch fix/renew-the-token-silently; HEAD e54a6c0 docs: add the live checklist for renewing a token during a long run; tracked changes: 0
[oer-s104] The worktree's build carries the window's owner: True; A: True; B: True; device code forced: True
RUNNER: check S.1 exit code 0; started 2026-10-09T02:50:09Z; took 2 s.
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Write-OerLiveStep (Get-S104Window)
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, `The module is the worktree's
build: True`, and `sign-in method: ClientCertificate` with neither token due for renewal (`False`,
about an hour left).
**Failure looks like:** any `False` in the identity lines, or `application is disabled` -- STOP: the
identity is not enabled for this run; never sign in another way.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc; identity check passed; the module is the worktree's build (1.1.4); sign-in method ClientCertificate, with neither token due for renewal (59 min left).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] The module is the worktree's build: True
[oer-s104] sign-in method: ClientCertificate; Graph token due for renewal: False (59 min left); ARM token due for renewal: False (59 min left)
RUNNER: check 0.1 exit code 0; started 2026-10-09T02:50:11Z; took 6 s.
```

## 1. App-only: a token in the renewal window is not renewed within a command (regression, A)

### 1.1. Microsoft Graph: the request goes out with the token the session holds

- [x] **1.1** With the Microsoft Graph token's recorded expiry moved two minutes ahead -- inside the renewal window -- a Graph request through the module's transport makes no token request, writes no renewal line, sends once and is answered; the expiry stays where it was moved.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
Set-S104Expiry -Token Graph -Minutes 2
Write-OerLiveStep "Before: $(Get-S104Window)"
Start-S104Count
$Org = Invoke-S104Transport { try { Invoke-OERGraphRequest -Uri 'v1.0/organization?$select=id' -Verbose } catch { [pscustomobject]@{ Caught = [string]$PSItem.FullyQualifiedErrorId } } }
Write-OerLiveStep "error caught: $(if ($Org.Caught) { $Org.Caught } else { 'none' })"
Write-OerLiveStep "Response read: organizations $(@($Org.value).Count); it is the test tenant: $(@($Org.value).Count -eq 1 -and [string]$Org.value[0].id -eq $Cfg.TenantId)"
Write-OerLiveStep (Get-S104Renewals)
Write-OerLiveStep "After: $(Get-S104Window)"
Stop-S104Count
Write-OerLiveStep (Get-S104Sent)
Disconnect-OerLive
```

**Expect:** before: `sign-in method: ClientCertificate; Graph token due for renewal: True (1 min
left)`; `Response read: organizations 1; it is the test tenant: True`; `renewal lines in the verbose
stream: 0`; after: Graph token still due `True`; `token requests: 0; Microsoft Graph requests: 1;
Azure Resource Manager requests: 0`; `error caught: none`.
**Failure looks like:** a token request (the fence refuses it, and the line names it), a renewal line,
an error caught (`AppOnly...` or `SignInRefused`), or no response.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the Microsoft Graph token's recorded expiry moved two minutes ahead (due: True, 1 min left), a Graph request through the module's transport made no token request, wrote no renewal line (its one verbose line is the request itself), sent once and was answered with the test tenant's organization; no error; the expiry was still due afterwards, so nothing renewed it.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] Before: sign-in method: ClientCertificate; Graph token due for renewal: True (1 min left); ARM token due for renewal: False (59 min left)
[oer-s104] error caught: none
[oer-s104] Response read: organizations 1; it is the test tenant: True
[oer-s104] renewal lines in the verbose stream: 0; verbose lines: 1
[oer-s104] After: sign-in method: ClientCertificate; Graph token due for renewal: True (1 min left); ARM token due for renewal: False (59 min left)
[oer-s104] token requests: 0; Microsoft Graph requests: 1; Azure Resource Manager requests: 0
RUNNER: check 1.1 exit code 0; started 2026-10-09T02:50:26Z; took 5 s.
```

### 1.2. Azure Resource Manager: the same with the ARM token

- [x] **1.2** With the ARM token's recorded expiry moved two minutes ahead, an ARM request through the module's transport makes no token request, writes no renewal line, sends once and is answered with the test subscription; the expiry stays where it was moved.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
Set-S104Expiry -Token Arm -Minutes 2
Write-OerLiveStep "Before: $(Get-S104Window)"
Start-S104Count
$Subs = Invoke-S104Transport { try { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -Verbose -ErrorAction Stop } catch { [pscustomobject]@{ Caught = [string]$PSItem.FullyQualifiedErrorId } } }
Write-OerLiveStep "error caught: $(if ($Subs.Caught) { $Subs.Caught } else { 'none' })"
Write-OerLiveStep "Response read: subscriptions $(@($Subs.value).Count); the test subscription is among them: $(@($Subs.value | Where-Object { [string]$_.subscriptionId -eq $Cfg.SubscriptionId }).Count -eq 1)"
Write-OerLiveStep (Get-S104Renewals)
Write-OerLiveStep "After: $(Get-S104Window)"
Stop-S104Count
Write-OerLiveStep (Get-S104Sent)
Disconnect-OerLive
```

**Expect:** before: ARM token due `True (1 min left)`; the test subscription among those read
`True`; `renewal lines in the verbose stream: 0`; after: ARM token still due `True`; `token requests:
0; Microsoft Graph requests: 0; Azure Resource Manager requests: 1`; `error caught: none`.
**Failure looks like:** a token request, a renewal line, an error caught, or no response.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the ARM token's recorded expiry moved two minutes ahead (due: True, 1 min left), an ARM request through the module's transport made no token request, wrote no renewal line, sent once and was answered with the test subscription; no error; the ARM expiry was still due afterwards.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] Before: sign-in method: ClientCertificate; Graph token due for renewal: False (59 min left); ARM token due for renewal: True (1 min left)
[oer-s104] error caught: none
[oer-s104] Response read: subscriptions 1; the test subscription is among them: True
[oer-s104] renewal lines in the verbose stream: 0; verbose lines: 1
[oer-s104] After: sign-in method: ClientCertificate; Graph token due for renewal: False (59 min left); ARM token due for renewal: True (1 min left)
[oer-s104] token requests: 0; Microsoft Graph requests: 0; Azure Resource Manager requests: 1
RUNNER: check 1.2 exit code 0; started 2026-10-09T02:50:31Z; took 5 s.
```

### 1.3. A paged read with the Graph token in the window reads every page with the token it holds

- [x] **1.3** With the Graph token's recorded expiry inside the renewal window, a paged read of the tenant's groups two at a time (`-All`) makes no token request and no renewal, and returns exactly the groups one large page returns.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
Set-S104Expiry -Token Graph -Minutes 2
Start-S104Count
$Paged = Invoke-S104Transport { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=2&$select=id' -All -Verbose }
$PagedRenewals = Get-S104Renewals
$PagedRequests = $global:S104Graph.Count
$Whole = Invoke-S104Transport { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=999&$select=id' -All -Verbose }
$PagedIds = @($Paged.value | ForEach-Object { [string]$_.id } | Sort-Object)
$WholeIds = @($Whole.value | ForEach-Object { [string]$_.id } | Sort-Object)
Write-OerLiveStep "paged read: $($PagedIds.Count) groups in $PagedRequests requests; $PagedRenewals"
Write-OerLiveStep "one large page: $($WholeIds.Count) groups; the same groups: $(($PagedIds -join ',') -eq ($WholeIds -join ','))"
Write-OerLiveStep "After: $(Get-S104Window)"
Stop-S104Count
Write-OerLiveStep (Get-S104Sent)
Disconnect-OerLive
```

**Expect:** the paged read in more than one request (as many as half the groups, rounded up), `renewal
lines in the verbose stream: 0`; the same groups as one large page, `True`; the Graph token still due
`True`; `token requests: 0`.
**Failure looks like:** a token request or a renewal line; a different set of groups (a page lost or
read twice); a single request when the tenant holds more than two groups (the paging was not
exercised -- not a pass).

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the Graph token due, the paged read two at a time (-All) read 97 groups in 49 requests and wrote no renewal line; one large page read the same 97 groups (the same ids: True); 0 token requests and 50 Graph requests in all; the Graph token still due afterwards.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] paged read: 97 groups in 49 requests; renewal lines in the verbose stream: 0; verbose lines: 98
[oer-s104] one large page: 97 groups; the same groups: True
[oer-s104] After: sign-in method: ClientCertificate; Graph token due for renewal: True (1 min left); ARM token due for renewal: False (59 min left)
[oer-s104] token requests: 0; Microsoft Graph requests: 50; Azure Resource Manager requests: 0
RUNNER: check 1.3 exit code 0; started 2026-10-09T02:50:36Z; took 7 s.
```

## 2. Ordinary commands read as before (regression)

### 2.1. Get-OERSubscription

- [x] **2.1** `Get-OERSubscription` on a fresh module session returns the test subscription, with no token request and no error.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
Start-S104Count
$E = $null
$Out = @(Get-OERSubscription -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "subscriptions returned: $($Out.Count); the test subscription is among them: $(@($Out | Where-Object { [string]$_.SubscriptionId -eq $Cfg.SubscriptionId }).Count -eq 1); errors: $(@($E).Count)"
Stop-S104Count
Write-OerLiveStep (Get-S104Sent)
Disconnect-OerLive
```

**Expect:** at least one subscription, the test subscription among them `True`, errors 0; `token
requests: 0`; at least one Azure Resource Manager request.
**Failure looks like:** an error, a token request, or the test subscription missing.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Get-OERSubscription on a fresh module session returned 1 subscription, the test subscription, with no error; 0 token requests, 1 Azure Resource Manager request.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] subscriptions returned: 1; the test subscription is among them: True; errors: 0
[oer-s104] token requests: 0; Microsoft Graph requests: 0; Azure Resource Manager requests: 1
RUNNER: check 2.1 exit code 0; started 2026-10-09T02:50:52Z; took 5 s.
```

### 2.2. Get-OERGroup -All

- [x] **2.2** `Get-OERGroup -All` on a fresh module session returns as many groups as the transport's own paged read of security and non-security groups, with no token request and no error.

```powershell
Connect-OerLive -Arm
Start-S104NoPrompt
$E = $null
$Groups = @(Get-OERGroup -All -ErrorAction SilentlyContinue -ErrorVariable E)
$Raw2 = Invoke-S104Transport { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=999&$select=id' -All }
Write-OerLiveStep "Get-OERGroup -All: $($Groups.Count) groups; errors: $(@($E).Count); the transport's own read: $(@($Raw2.value).Count) groups; the same number: $($Groups.Count -eq @($Raw2.value).Count)"
Write-OerLiveStep (Get-S104Sent)
Disconnect-OerLive
```

**Expect:** errors 0; the same number `True`; `token requests: 0`.
**Failure looks like:** an error, a token request, or a different number (read the cmdlet's own
filter before calling it a defect: `Get-OERGroup -All` lists what its help says it lists).

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Get-OERGroup -All on a fresh module session returned 97 groups with no error, as many as the transport's own paged read; 0 token requests (the block does not start the request counters, and says so).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s104] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s104] Get-OERGroup -All: 97 groups; errors: 0; the transport's own read: 97 groups; the same number: True
[oer-s104] token requests: 0; Microsoft Graph requests: not counted in this block; Azure Resource Manager requests: not counted in this block
RUNNER: check 2.2 exit code 0; started 2026-10-09T02:50:57Z; took 5 s.
```

## C. The operator's check: a delegated session renews while a command runs (class C, after the merge)

**Run by the operator, by hand, after the merge, with the published preview -- never by Claude.** It
signs in as the operator, interactively or with a device code, which is exactly what makes it class
C (G9): `oer-live-cc` is app-only and cannot reach the renewal at all. Run it in the test tenant
unless C.4 says otherwise. Nothing here writes to the tenant. No tenant value is ever written into
this file: type the tenant ID at the prompt in C.1.

**What the code says will happen, before you run it.** Decision A11 expects a renewal without a
prompt. AzAuth's own code (2.10.0, read offline and DECOMPILED; see `docs/development/rationale.md`,
the subsection on how a long run renews its token) says otherwise for an interactive sign-in: every
interactive token request builds a new browser credential with no memory of the earlier sign-in, so
the renewal opens the browser's account picker again. A device code session is not renewed by this
branch at all (ruling R12): AzAuth's code shows that a device-code request without `-Force` that reuses
its credential never returns, so a 401 is still forced, as before. C.1 measures the interactive case,
C.2 that a device code session is left alone, and C.3, optionally, AzAuth's wait itself; write down
what happened, whichever it was.

### C.0. The preview is installed and carries the change

- [ ] **C.0** In a new PowerShell process, the preview the merge published is installed and loaded, and it carries the renewal.

```powershell
Install-PSResource -Name Omnicit.EntraRBAC -Prerelease -Scope CurrentUser -Reinstall -TrustRepository
Import-Module Omnicit.EntraRBAC -Force
$M = Get-Module -Name Omnicit.EntraRBAC
"Version: $($M.Version)-$($M.PrivateData.PSData.Prerelease)"
"Carries the renewal: $([bool](& $M { Get-Command -Name Get-OERTokenRenewalThreshold -ErrorAction SilentlyContinue }))"
```

**Expect:** the preview version the merge published (the sprint plan expects `1.1.4-preview0005`) and
`Carries the renewal: True`.

Result:

### C.1. Interactive: the transport renews while a command runs

- [ ] **C.1** After `Connect-OER -Interactive`, a command that has begun has its Graph token's recorded expiry moved inside the renewal window and then sends: one more token request, without `-Force`, the renewal line on the verbose stream, the request answered -- and whether a browser window or account picker appeared is written down.

```powershell
# In the process C.0 prepared.
$TenantId = Read-Host 'The test tenant ID (typed here, never written into this file)'
# Counts every token request the module makes from here on -- the resource, and whether it carried
# -Force or asked for an interactive or device-code sign-in -- and forwards each one unchanged.
$global:CTokens = [System.Collections.Generic.List[string]]::new()
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
$Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:CTokens.Add('resource=' + ([uri]`$Resource).Host + ' force=' + [bool]`$PSBoundParameters['Force'] + ' interactive=' + [bool]`$PSBoundParameters['Interactive'] + ' devicecode=' + [bool]`$PSBoundParameters['DeviceCode']); AzAuth\Get-AzToken @PSBoundParameters }"
Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))

Connect-OER -TenantId $TenantId -Interactive    # the one deliberate browser sign-in
$M = Get-Module -Name Omnicit.EntraRBAC
# A command of its own, in the module's scope. It signs in at its start (a cached return, no token
# request), THEN its Graph token's recorded expiry is moved two minutes ahead -- inside the renewal
# window -- and only then does it send. So the renewal measured is the transport's, made while the
# command runs, not the command's own start.
& $M {
    function Invoke-CCheckProbe {
        [CmdletBinding()]
        param()
        begin { Initialize-OERAuth }
        process {
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
            $Started = [DateTime]::UtcNow
            $Org = Invoke-OERGraphRequest -Uri 'v1.0/organization?$select=id' -Verbose
            "Request answered: $(@($Org.value).Count -eq 1) after $([int]([DateTime]::UtcNow - $Started).TotalSeconds) s"
            "Graph token due for renewal after the request: $($script:_OERAuthState.GraphTokenExpiry -le (Get-OERTokenRenewalThreshold))"
        }
    }
    Invoke-CCheckProbe
}
"Token requests: $($global:CTokens.Count)"
$global:CTokens | ForEach-Object { "token request: $_" }
```

**Expect (decision A11):** the line `VERBOSE: [Invoke-OERGraphRequest] The Microsoft Graph token
expires within the renewal window. Renewing it before the request...`; `Token requests: 2` -- the
sign-in and the renewal, both `resource=graph.microsoft.com force=False interactive=True`; **no
browser window and no account picker**; `Request answered: True` within a few seconds; `Graph token
due for renewal after the request: False`.
**Predicted from AzAuth's code (R1):** everything above except that the browser opens the account
picker for the renewal, and the request waits until you choose the account (or times out after 120
s). Write down: browser opened yes/no; account picker yes/no; did you have to click; the seconds the
request took.
**Failure looks like:** `force=True` on the renewal, more than two token requests, or no renewal line
-- each a defect of this branch, whatever the browser did.

Result:

### C.2. Device code, Microsoft Graph only: no renewal before the request

- [ ] **C.2** In a NEW process, after `Connect-OER -DeviceCode` without `-IncludeARM`, the same probe: the transport does NOT renew a device code session's token (ruling R12), makes no token request, and the request goes out with the token the session holds.

```powershell
# A new process: run C.0's Import-Module and $M lines, and C.1's lines up to and including Set-Item first.
Connect-OER -TenantId $TenantId -DeviceCode     # enter the code once
# Then run C.1's '& $M { ... }' block and the two lines after it, unchanged.
```

**Expect (ruling R12):** no renewal line on the verbose stream; `Token requests: 1` -- only the
sign-in, `resource=graph.microsoft.com force=False devicecode=True`; no new device code; `Request
answered: True` within a few seconds; `Graph token due for renewal after the request: True` (the token
the session holds is still valid for about two minutes, and is used).
**Failure looks like:** a renewal line or a second token request -- the branch renews device code, and
by AzAuth's code that call would never return.

Result:

### C.3. Optional: measure AzAuth's device-code reuse wait, outside the module

- [ ] **C.3** Optional, AzAuth alone, no module. Two device-code token requests for the same resource in one process, the second without `-Force`: whether the second prints a code, returns, or waits is written down. This is the measurement behind ruling R12, which the code only predicts.

```powershell
# A NEW process. Nothing of Omnicit.EntraRBAC is loaded.
Import-Module AzAuth
$TenantId = Read-Host 'The test tenant ID (typed here, never written into this file)'
$First = Get-AzToken -DeviceCode -Resource 'https://graph.microsoft.com/' -Tenant $TenantId    # enter the code
"First request returned a token: $([bool]$First.Token)"
$Started = Get-Date
# The second request, same resource and application, no -Force. If nothing has happened after three
# minutes, press Ctrl+C, write down the minutes, and close this PowerShell process (AzAuth's credential is
# then in an unknown state).
$Second = Get-AzToken -DeviceCode -Resource 'https://graph.microsoft.com/' -Tenant $TenantId
"Second request returned a token: $([bool]$Second.Token) after $([int]((Get-Date) - $Started).TotalSeconds) s"
```

**Predicted from AzAuth's code (DECOMPILED, ruling R12):** the second request prints no code and does
not return; Ctrl+C is the only way out. Either outcome is a result: write down whether a code was
printed, whether it returned, and after how long. If it returns a token without a code, R12's premise
is wrong and device code can be renewed without `-Force`.

Result:
### C.4. Optional: a long export

- [ ] **C.4** Optional. An interactive `Export-OERInventory` that runs longer than the token's lifetime (about an hour or more) completes without a timed-out sign-in; whether and when the account picker appeared is written down.

```powershell
# A new process, a tenant of your choosing (read-only; the export writes only to the folder named).
Connect-OER -TenantId $TenantId -Interactive -IncludeARM
Export-OERInventory -TenantId $TenantId -OutputPath (Join-Path ([System.IO.Path]::GetTempPath()) 'oer-s104-export') -Verbose 4>&1 |
    Where-Object { "$_" -like '*renewal window*' } | ForEach-Object { "$(Get-Date -Format 'HH:mm:ss') $_" }
```

**Expect (decision A11):** renewal lines near each token's expiry, no prompt, and a complete bundle
(no `PARTIAL`, no "Login timed out after 120 seconds").
**Predicted from AzAuth's code (R1):** each renewal opens the account picker. Answered, the export
carries on; left alone, the renewal times out after 120 seconds and the export reports a partial
result, as before this branch. Write down which it was.

Result:

### C.5. Clean up

- [ ] **C.5** The proxy and the session are gone.

```powershell
Disconnect-OER -Confirm:$false
if (Test-Path -Path function:Get-AzToken) { Remove-Item -Path function:Get-AzToken }
Remove-Item -LiteralPath (Join-Path ([System.IO.Path]::GetTempPath()) 'oer-s104-export') -Recurse -Force -ErrorAction SilentlyContinue
```

Result:

## Teardown

### T.1. Nothing left: no session and nothing with the prefix

- [x] **T.1** No module state and no Graph SDK session is left in the process; the sweep finds nothing with the prefix `oer-s104-` in the tenant.

```powershell
Connect-OerLive -Graph
Start-S104NoPrompt
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "After Disconnect-OerLive: Graph SDK session present: $([bool](Get-MgContext))"
```

**Expect:** objects with the prefix 0, unread collections 0; `Graph SDK session present: False`.
**Failure looks like:** an object with the prefix -- this file creates none, so it is someone else's
and a stop; an unread collection -- the sweep is not a proof of absence.

Result: 2026-10-09 02:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Nothing in the tenant carries the prefix oer-s104- (0 objects, 0 unread collections; this file creates none); no Graph SDK session is left after Disconnect-OerLive. The WARNING line is Disconnect-OER's own, written when OerLive's Disconnect-OerLive calls it after the -Graph sign-in, as in Sprint 10 step 3.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s104] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg4\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s104] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s104] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s104] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s104] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s104] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s104] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s104] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s104] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s104-' is left.
[oer-s104] objects with the prefix: 0; unread collections: 0
WARNING: Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.
[oer-s104] After Disconnect-OerLive: Graph SDK session present: False
RUNNER: check T.1 exit code 0; started 2026-10-09T02:51:01Z; took 4 s.
```

